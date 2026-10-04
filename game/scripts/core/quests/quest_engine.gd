class_name QuestEngine
extends RefCounted
## The quest rules: availability, accept, objective progress, completion, rewards and forfeit, all driven by quest
## data (QuestCatalog). Pure: it works on a CharacterState, a ContentDB, an injectable RandomNumberGenerator and a
## game clock, never touches the scene tree and emits nothing. Every mutating call returns a result:
##
##   {"ok": bool, "reason": String, "quest_id": String, "effects": Array, ...}
##
## `effects` lists what changed, in order, as dictionaries with a "type":
##   quest_started / quest_progressed / quest_completed / quest_forfeited  {quest_id}
##   item_gained / item_lost   {item_id, qty}
##   exp_gained                {amount, source, exp_added, levels_gained, new_level}
##   mesos_changed             {delta, mesos}
##   fame_changed              {delta, fame}
##   flag_set                  {flag, value}
## QuestService turns them into Events signals. Failure reasons: unknown_quest, not_available (see "reasons"),
## wrong_npc, inventory_full, not_enough_mesos, not_in_progress, objectives_incomplete (see "blockers"),
## level_too_low, wrong_answer, no_quiz, selection_required, invalid_selection, nothing_lost.

const NOT_STARTED := QuestLog.NOT_STARTED
const IN_PROGRESS := QuestLog.IN_PROGRESS
const COMPLETED := QuestLog.COMPLETED

var character: CharacterState
var db: ContentDB
var rng: RandomNumberGenerator
## () -> float: the game clock (Game.clock). Unset = 0.0.
var clock: Callable
var catalog: QuestCatalog


func _init(p_character: CharacterState = null, p_db: ContentDB = null, p_rng: RandomNumberGenerator = null,
		p_clock: Callable = Callable(), p_catalog: QuestCatalog = null) -> void:
	character = p_character if p_character != null else CharacterState.new()
	db = p_db
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	clock = p_clock
	catalog = p_catalog if p_catalog != null else QuestCatalog.new(db)


## Current game-clock time.
func now() -> float:
	return float(clock.call()) if clock.is_valid() else 0.0


## The character's quest log.
func quest_log() -> QuestLog:
	return character.quests


func definition(quest_id: String) -> QuestDef:
	return catalog.get_def(quest_id)


func status(quest_id: String) -> String:
	return quest_log().status(quest_id)


# --- availability ---------------------------------------------------------------------------------------------

## {"ok": bool, "reasons": PackedStringArray}. Reasons: unknown_quest, in_progress, already_completed,
## level_too_low, level_too_high, wrong_job, prerequisite:<id>, missing_item:<id>, has_item:<id>, fame_too_low,
## not_enough_mesos, unsupported_prerequisite.
func availability(quest_id: String) -> Dictionary:
	var reasons := PackedStringArray()
	var d := definition(quest_id)
	if d == null:
		reasons.append("unknown_quest")
		return {"ok": false, "reasons": reasons}
	var st := status(quest_id)
	if st == IN_PROGRESS:
		reasons.append("in_progress")
	elif st == COMPLETED and not d.repeatable:
		reasons.append("already_completed")
	if d.min_level > 0 and character.level < d.min_level:
		reasons.append("level_too_low")
	if d.max_level > 0 and character.level > d.max_level:
		reasons.append("level_too_high")
	if not job_matches(d.job_restriction):
		reasons.append("wrong_job")
	for p in d.prereq_quests:
		if quest_log().completions(p) <= 0:
			reasons.append("prerequisite:" + p)
	for it: Dictionary in d.prereq_items:
		if _count(it["item_id"]) < int(it["count"]):
			reasons.append("missing_item:" + String(it["item_id"]))
	for it: Dictionary in d.must_not_have_items:
		if _count(it["item_id"]) > 0:
			reasons.append("has_item:" + String(it["item_id"]))
	if d.fame_min > 0 and character.fame < d.fame_min:
		reasons.append("fame_too_low")
	if d.acceptance_meso_cost > 0 and character.mesos < d.acceptance_meso_cost:
		reasons.append("not_enough_mesos")
	if not d.unsupported_prereqs.is_empty():
		reasons.append("unsupported_prerequisite")
	return {"ok": reasons.is_empty(), "reasons": reasons}


func is_available(quest_id: String) -> bool:
	return bool(availability(quest_id)["ok"])


## Quests that can be accepted now (optionally only those started by `npc_id`), sorted.
func available_quests(npc_id: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	var pool := catalog.ids() if npc_id.is_empty() else catalog.started_by(npc_id)
	for qid in pool:
		if is_available(qid):
			out.append(qid)
	return out


func active_quests() -> PackedStringArray:
	return quest_log().active_ids()


func completed_quests() -> PackedStringArray:
	return quest_log().completed_ids()


## True if the character's job satisfies a job restriction (empty = any job). Entries are MeowDB display names
## ("Beginner"); the character stores a class slug ("beginner"), matched through formulas/<slug>.json "name".
func job_matches(restriction: PackedStringArray) -> bool:
	if restriction.is_empty():
		return true
	var display := _job_display_name()
	for r in restriction:
		if r == character.job or (not display.is_empty() and r == display) or r.to_lower() == character.job.to_lower():
			return true
	return false


# --- objectives -----------------------------------------------------------------------------------------------

## Per-objective progress for the quest log UI:
## [{key, kind, id, name, current, required, done, purpose, type, supported}]. Item collection reads the live
## inventory count.
func objective_status(quest_id: String) -> Array:
	var out: Array = []
	var d := definition(quest_id)
	if d == null:
		return out
	var ql := quest_log()
	for o: Dictionary in d.objectives:
		var cur := 0
		var req := int(o["count"])
		var oid := String(o["id"])
		match String(o["kind"]):
			"monster_kills":
				cur = ql.kills(quest_id, oid)
			"item_collection":
				cur = _count(oid)
			"item_usage":
				cur = ql.uses(quest_id, oid)
			"npc_talk":
				req = 1
				cur = 1 if ql.has_talked(quest_id, oid) else 0
			"map_visit":
				req = 1
				cur = 1 if ql.has_visited(quest_id, oid) else 0
			"other":
				req = 1
				cur = 1 if bool(o["supported"]) and ql.other_value(quest_id, String(o["type"])) == true else 0
		var row := o.duplicate()
		row["current"] = cur
		row["required"] = req
		row["done"] = cur >= req
		out.append(row)
	return out


## True if every objective of `kind` (and `target_id` when given) is satisfied. Vacuously true when none exist.
func objective_done(quest_id: String, kind: String, target_id: String = "") -> bool:
	for row: Dictionary in objective_status(quest_id):
		if row["kind"] == kind and (target_id.is_empty() or row["id"] == target_id) and not bool(row["done"]):
			return false
	return true


## What still blocks completion: objective keys, plus "not_in_progress", "level_too_low", "wrong_npc". Talking to
## the turn-in NPC is satisfied by `at_npc_id` being that NPC. Keys or kinds in `ignore` are skipped.
func completion_blockers(quest_id: String, at_npc_id: String = "", ignore: PackedStringArray = []) -> PackedStringArray:
	var out := PackedStringArray()
	var d := definition(quest_id)
	if d == null:
		out.append("unknown_quest")
		return out
	if status(quest_id) != IN_PROGRESS:
		out.append("not_in_progress")
		return out
	if not at_npc_id.is_empty() and at_npc_id != d.end_npc_id:
		out.append("wrong_npc")
	for row: Dictionary in objective_status(quest_id):
		if String(row["key"]) in ignore or String(row["kind"]) in ignore:
			continue
		if row["kind"] == "npc_talk" and row["purpose"] == "turn_in" and row["id"] == at_npc_id:
			continue
		if not bool(row["done"]):
			out.append(String(row["key"]))
	if d.completion_min_level > 0 and character.level < d.completion_min_level:
		out.append("level_too_low")
	return out


## True if the quest can be completed now (at `at_npc_id`, when given).
func can_complete(quest_id: String, at_npc_id: String = "") -> bool:
	return completion_blockers(quest_id, at_npc_id).is_empty()


## True if everything except objectives resolved inside the turn-in conversation (the quiz) is done, so the NPC
## can start the turn-in conversation.
func ready_to_turn_in(quest_id: String, at_npc_id: String = "") -> bool:
	return completion_blockers(quest_id, at_npc_id, QuestDef.DIALOGUE_RESOLVED_KEYS).is_empty()


## Items handed over on accept that an unfinished objective still needs and the character no longer holds
## (the canonical "If you lost the items" case): [{item_id, count}] to re-issue.
func lost_items(quest_id: String) -> Array:
	var out: Array = []
	var d := definition(quest_id)
	if d == null or status(quest_id) != IN_PROGRESS:
		return out
	for a: Dictionary in d.accept_items:
		var item_id := String(a["item_id"])
		var still_needed := 0
		for o: Dictionary in d.objectives:
			if o["id"] != item_id:
				continue
			if o["kind"] == "item_collection":
				still_needed = maxi(still_needed, int(o["count"]))
			elif o["kind"] == "item_usage":
				still_needed = maxi(still_needed, int(o["count"]) - quest_log().uses(quest_id, item_id))
		var missing := mini(int(a["count"]), still_needed) - _count(item_id)
		if missing > 0:
			out.append({"item_id": item_id, "count": missing})
	return out


# --- progress hooks (return the quest ids whose progress changed) -----------------------------------------------

func on_monster_killed(mob_id: String) -> PackedStringArray:
	return _count_hook("monster_kills", mob_id)


func on_item_used(item_id: String) -> PackedStringArray:
	return _count_hook("item_usage", item_id)


## Item collection is read live from the inventory, so this only reports which quests' displayed progress changed.
func on_item_gained(item_id: String, _qty: int = 1) -> PackedStringArray:
	return _quests_with_objective("item_collection", item_id)


func on_item_lost(item_id: String, _qty: int = 1) -> PackedStringArray:
	return _quests_with_objective("item_collection", item_id)


## Records talking to an NPC. A "turn_in" talk is recorded only once every other objective is done (the classic
## "...then talk to Roger" order); other talks are recorded immediately.
func on_npc_talk(npc_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for qid in active_quests():
		var d := definition(qid)
		if d == null:
			continue
		for o: Dictionary in d.objectives_of("npc_talk"):
			if o["id"] != npc_id:
				continue
			if o["purpose"] == "turn_in":
				var others := completion_blockers(qid, npc_id)
				others.erase(String(o["key"]))
				if not others.is_empty():
					continue
			if quest_log().mark_talked(qid, npc_id) and not (qid in out):
				out.append(qid)
	return out


func on_map_entered(map_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for qid in active_quests():
		var d := definition(qid)
		if d == null:
			continue
		for o: Dictionary in d.objectives_of("map_visit"):
			if o["id"] == map_id and quest_log().mark_visited(qid, map_id) and not (qid in out):
				out.append(qid)
	return out


# --- actions --------------------------------------------------------------------------------------------------

## Accepts a quest: checks availability (and the start NPC when `at_npc_id` is given), checks inventory space for
## the accept items (canonical + next_quest_grants + MisoStory adaptation), then starts it and hands them over.
func accept(quest_id: String, at_npc_id: String = "") -> Dictionary:
	var d := definition(quest_id)
	if d == null:
		return _fail(quest_id, "unknown_quest")
	var av := availability(quest_id)
	if not bool(av["ok"]):
		var r := _fail(quest_id, "not_available")
		r["reasons"] = av["reasons"]
		return r
	if not at_npc_id.is_empty() and at_npc_id != d.start_npc_id:
		return _fail(quest_id, "wrong_npc")
	var give := _qty_list(d.accept_items)
	if not give.is_empty() and not character.inventory.can_add_all(give, db):
		return _full(quest_id, d.accept_items)
	var effects: Array = []
	if d.acceptance_meso_cost > 0:
		if not bool(Mesos.spend(character, d.acceptance_meso_cost).get("ok", false)):
			return _fail(quest_id, "not_enough_mesos")
		effects.append({"type": "mesos_changed", "delta": -d.acceptance_meso_cost, "mesos": character.mesos})
	quest_log().start(quest_id, now())
	effects.push_front({"type": "quest_started", "quest_id": quest_id})
	var given := _grant(d.accept_items, effects)
	return {"ok": true, "reason": "", "quest_id": quest_id, "items_given": given, "effects": effects}


## Grades a quiz answer (0-based index into dialogue.on_completion.quiz.choices) against canonical
## correct_choice_index. A right answer satisfies the quiz objective; a wrong one changes nothing.
func answer_quiz(quest_id: String, choice_index: int) -> Dictionary:
	var d := definition(quest_id)
	if d == null:
		return _fail(quest_id, "unknown_quest")
	if status(quest_id) != IN_PROGRESS:
		return _fail(quest_id, "not_in_progress")
	if d.quiz.is_empty():
		return _fail(quest_id, "no_quiz")
	var correct := QuestJson.i(d.quiz.get("correct_choice_index"), -1)
	if correct < 0 or choice_index != correct:
		var r := _fail(quest_id, "wrong_answer")
		r["choice"] = choice_index
		return r
	quest_log().set_other(quest_id, "quiz", true)
	return {"ok": true, "reason": "", "quest_id": quest_id,
		"effects": [{"type": "quest_progressed", "quest_id": quest_id}]}


## Rolls the rewards a completion would grant, without granting anything:
## {"ok", "reason", "items": [{item_id, count}], "random_picks": [...], "selection_pick": {}}.
## Random groups pick one item each, weighted by MeowDB chance_pct, with the engine RNG. Selection groups need
## options.selection_index (the player's pick).
func resolve_rewards(quest_id: String, options: Dictionary = {}) -> Dictionary:
	var d := definition(quest_id)
	if d == null:
		return _fail(quest_id, "unknown_quest")
	var items: Array = []
	for it: Dictionary in d.reward_items:
		items.append(it.duplicate())
	var picks: Array = []
	var display := _job_display_name()
	for g: Dictionary in d.reward_random:
		if not QuestDef.group_applies(String(g["job_name"]), character.job, display):
			continue
		var pick := _weighted_pick(g["items"])
		if not pick.is_empty():
			var p := {"item_id": pick["item_id"], "count": pick["count"]}
			picks.append(p)
			items.append(p.duplicate())
	var selection_pick := {}
	for g: Dictionary in d.reward_selection:
		if not QuestDef.group_applies(String(g["job_name"]), character.job, display):
			continue
		var choices: Array = g["items"]
		if choices.is_empty():
			continue
		if not options.has("selection_index"):
			return _fail(quest_id, "selection_required")
		var idx := QuestJson.i(options.get("selection_index"), -1)
		if idx < 0 or idx >= choices.size():
			return _fail(quest_id, "invalid_selection")
		selection_pick = (choices[idx] as Dictionary).duplicate()
		items.append(selection_pick.duplicate())
		break
	return {"ok": true, "reason": "", "quest_id": quest_id, "items": items, "random_picks": picks,
		"selection_pick": selection_pick}


## Completes a quest. Options: at_npc_id (the NPC being talked to; must be the end NPC), quiz_choice (graded first),
## selection_index (for selection rewards). Refuses when objectives are unfinished or the reward items do not fit
## (Inventory.can_add_all) and then changes nothing. Otherwise removes the hand-in items, grants EXP
## (Progression.gain_exp), mesos, fame and items, and marks the quest completed. Follow-ups become available through
## their prerequisites ("followups_available" lists those that are now acceptable).
func complete(quest_id: String, options: Dictionary = {}) -> Dictionary:
	var d := definition(quest_id)
	if d == null:
		return _fail(quest_id, "unknown_quest")
	if status(quest_id) != IN_PROGRESS:
		return _fail(quest_id, "not_in_progress")
	var at_npc := QuestJson.s(options.get("at_npc_id"))
	if not at_npc.is_empty() and at_npc != d.end_npc_id:
		return _fail(quest_id, "wrong_npc")
	# A quiz answer given with this call is graded first; if the completion is then refused, the answer is undone
	# (a quiz answered in an earlier call is kept), so a refused completion changes nothing.
	var quiz_before: Variant = quest_log().other_value(quest_id, "quiz")
	var answered_now := false
	if options.has("quiz_choice"):
		var qa := answer_quiz(quest_id, QuestJson.i(options.get("quiz_choice"), -1))
		if not bool(qa["ok"]):
			return qa
		answered_now = not (quiz_before is bool and bool(quiz_before))
	var blockers := completion_blockers(quest_id, at_npc)
	if not blockers.is_empty():
		var r := _fail(quest_id, "level_too_low" if blockers == PackedStringArray(["level_too_low"]) else "objectives_incomplete")
		r["blockers"] = blockers
		_undo_quiz(quest_id, answered_now, quiz_before)
		return r
	var rolled := resolve_rewards(quest_id, options)
	if not bool(rolled["ok"]):
		rolled["effects"] = []
		_undo_quiz(quest_id, answered_now, quiz_before)
		return rolled
	var grant: Array = rolled["items"]
	if not grant.is_empty() and not character.inventory.can_add_all(_qty_list(grant), db):
		_undo_quiz(quest_id, answered_now, quiz_before)
		return _full(quest_id, grant)
	var effects: Array = []
	if answered_now:
		effects.append({"type": "quest_progressed", "quest_id": quest_id})

	if not at_npc.is_empty():
		quest_log().mark_talked(quest_id, at_npc)
	var removed: Array = []
	for it: Dictionary in d.removed_on_completion:
		var n := character.inventory.remove(String(it["item_id"]), int(it["count"]))
		if n > 0:
			removed.append({"item_id": it["item_id"], "count": n})
			effects.append({"type": "item_lost", "item_id": it["item_id"], "qty": n})
	var exp_added := 0
	if d.reward_exp > 0:
		var gained: Dictionary = Progression.gain_exp(character, d.reward_exp, db)
		exp_added = QuestJson.i(gained.get("exp_added"))
		effects.append({"type": "exp_gained", "amount": d.reward_exp, "source": "quest:" + quest_id,
			"exp_added": exp_added, "levels_gained": QuestJson.i(gained.get("levels_gained")),
			"new_level": QuestJson.i(gained.get("new_level"), character.level)})
	var mesos_added := 0
	if d.reward_mesos > 0:
		# Mesos (items system) owns the meso cap; a capped wallet simply gains less.
		mesos_added = Mesos.add(character, d.reward_mesos, db)
		if mesos_added > 0:
			effects.append({"type": "mesos_changed", "delta": mesos_added, "mesos": character.mesos})
	if d.reward_fame != 0:
		character.fame += d.reward_fame
		effects.append({"type": "fame_changed", "delta": d.reward_fame, "fame": character.fame})
	var given := _grant(grant, effects)
	quest_log().complete(quest_id, now())
	effects.append({"type": "quest_completed", "quest_id": quest_id})
	var unlocked := PackedStringArray()
	for f in d.followups:
		if is_available(f):
			unlocked.append(f)
	return {"ok": true, "reason": "", "quest_id": quest_id, "exp": d.reward_exp, "exp_added": exp_added,
		"mesos": d.reward_mesos, "mesos_added": mesos_added, "fame": d.reward_fame, "items_given": given,
		"items_removed": removed,
		"random_picks": rolled["random_picks"], "selection_pick": rolled["selection_pick"],
		"followups_available": unlocked, "effects": effects}


## Drops an in-progress quest. Items the quest handed over on accept are taken back if still held (up to the amount
## given), so forfeiting and re-accepting cannot duplicate them (MisoStory rule; MeowDB is silent on forfeits).
func forfeit(quest_id: String) -> Dictionary:
	var d := definition(quest_id)
	if d == null:
		return _fail(quest_id, "unknown_quest")
	if status(quest_id) != IN_PROGRESS:
		return _fail(quest_id, "not_in_progress")
	var effects: Array = []
	for a: Dictionary in d.accept_items:
		var take := mini(_count(a["item_id"]), int(a["count"]))
		if take > 0:
			var n := character.inventory.remove(String(a["item_id"]), take)
			if n > 0:
				effects.append({"type": "item_lost", "item_id": a["item_id"], "qty": n})
	quest_log().forfeit(quest_id)
	effects.append({"type": "quest_forfeited", "quest_id": quest_id})
	return {"ok": true, "reason": "", "quest_id": quest_id, "effects": effects}


## Re-issues accept items the player lost (see lost_items), as the canonical "If you lost the items" branch does.
func reissue_lost_items(quest_id: String) -> Dictionary:
	var missing := lost_items(quest_id)
	if missing.is_empty():
		return _fail(quest_id, "nothing_lost")
	if not character.inventory.can_add_all(_qty_list(missing), db):
		return _full(quest_id, missing)
	var effects: Array = []
	var given := _grant(missing, effects)
	return {"ok": true, "reason": "", "quest_id": quest_id, "items_given": given, "effects": effects}


## Gives items ([{item_id, count}]) all-or-nothing (dialogue give_item action).
func give_items(items: Array) -> Dictionary:
	if items.is_empty():
		return {"ok": true, "reason": "", "effects": []}
	if not character.inventory.can_add_all(_qty_list(items), db):
		return _full("", items)
	var effects: Array = []
	_grant(items, effects)
	return {"ok": true, "reason": "", "effects": effects}


## Takes items ([{item_id, count}]) only if all are held (dialogue take_item action).
func take_items(items: Array) -> Dictionary:
	for it: Dictionary in items:
		if _count(it["item_id"]) < int(it["count"]):
			return _fail("", "missing_items")
	var effects: Array = []
	for it: Dictionary in items:
		var n := character.inventory.remove(String(it["item_id"]), int(it["count"]))
		if n > 0:
			effects.append({"type": "item_lost", "item_id": it["item_id"], "qty": n})
	return {"ok": true, "reason": "", "effects": effects}


## Sets a character progression flag (dialogue set_flag action).
func set_flag(flag: String, value: Variant) -> Dictionary:
	character.flags[flag] = value
	return {"ok": true, "reason": "", "effects": [{"type": "flag_set", "flag": flag, "value": value}]}


# --- NPC-facing queries (quest indicators, Phase 17 data side) --------------------------------------------------

## The quest entries an NPC offers right now: [{quest_id, name, state}] with state "completable" (in progress,
## turn-in here, ready), "in_progress" (turn-in here or started here, not ready) or "available" (startable here).
func npc_entries(npc_id: String) -> Array:
	var out: Array = []
	for qid in catalog.completed_by(npc_id):
		if status(qid) == IN_PROGRESS:
			out.append({"quest_id": qid, "name": definition(qid).name,
				"state": "completable" if ready_to_turn_in(qid, npc_id) else "in_progress"})
	for qid in catalog.started_by(npc_id):
		var d := definition(qid)
		if status(qid) == IN_PROGRESS and d.end_npc_id != npc_id:
			out.append({"quest_id": qid, "name": d.name, "state": "in_progress"})
		elif is_available(qid):
			out.append({"quest_id": qid, "name": d.name, "state": "available"})
	return out


## The indicator to show over an NPC: "completable", "available", "in_progress" or "" (in that priority).
func npc_marker(npc_id: String) -> String:
	var best := ""
	var rank := {"": 0, "in_progress": 1, "available": 2, "completable": 3}
	for e: Dictionary in npc_entries(npc_id):
		if int(rank[e["state"]]) > int(rank[best]):
			best = e["state"]
	return best


## Everything the quest window shows for one quest:
## {quest_id, name, status, journal, start_npc_id, end_npc_id, end_npc_name, can_complete, objectives}
## (objectives = objective_status rows; the turn-in talk row is the "Return to <NPC>" line).
func quest_summary(quest_id: String) -> Dictionary:
	var d := definition(quest_id)
	if d == null:
		return {}
	return {
		"quest_id": quest_id,
		"name": d.name,
		"status": status(quest_id),
		"journal": journal_text(quest_id),
		"start_npc_id": d.start_npc_id,
		"end_npc_id": d.end_npc_id,
		"end_npc_name": QuestJson.s(db.npc(d.end_npc_id).get("name")) if db != null else "",
		"can_complete": ready_to_turn_in(quest_id, d.end_npc_id),
		"objectives": objective_status(quest_id),
	}


## Summaries of every quest in the given statuses (default: in progress), sorted by quest id.
func quest_summaries(statuses: PackedStringArray = [IN_PROGRESS]) -> Array:
	var out: Array = []
	for qid in catalog.ids():
		if status(qid) in statuses:
			out.append(quest_summary(qid))
	return out


## The journal text for the quest's current state. MeowDB does not label journal lines by state; MisoStory reads
## them as docs/canonical/quests.md §5 describes: line 1 = available, middle lines = in progress, last = completed
## (2-line journals: line 1 until completed).
func journal_text(quest_id: String) -> String:
	var d := definition(quest_id)
	if d == null or d.journal_lines.is_empty():
		return ""
	var lines := d.journal_lines
	var n := lines.size()
	var st := status(quest_id)
	if n == 1:
		return lines[0]
	if st == COMPLETED:
		return lines[n - 1]
	if st == IN_PROGRESS and n >= 3:
		return "\n".join(lines.slice(1, n - 1))
	return lines[0]


# --- internals ------------------------------------------------------------------------------------------------

## Restores the quiz objective to its value before a refused complete() call that graded an answer.
func _undo_quiz(quest_id: String, answered_now: bool, before: Variant) -> void:
	if not answered_now:
		return
	var other: Dictionary = quest_log().progress(quest_id)["other"]
	if before == null:
		other.erase("quiz")
	else:
		other["quiz"] = before


func _count_hook(kind: String, target_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for qid in active_quests():
		var d := definition(qid)
		if d == null:
			continue
		for o: Dictionary in d.objectives_of(kind):
			if o["id"] != target_id:
				continue
			var cap := int(o["count"])
			var before := quest_log().kills(qid, target_id) if kind == "monster_kills" else quest_log().uses(qid, target_id)
			if before >= cap:
				continue
			if kind == "monster_kills":
				quest_log().add_kills(qid, target_id, 1, cap)
			else:
				quest_log().add_uses(qid, target_id, 1, cap)
			if not (qid in out):
				out.append(qid)
	return out


func _quests_with_objective(kind: String, target_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for qid in active_quests():
		var d := definition(qid)
		if d == null:
			continue
		for o: Dictionary in d.objectives_of(kind):
			if o["id"] == target_id and not (qid in out):
				out.append(qid)
	return out


func _grant(items: Array, effects: Array) -> Array:
	var given: Array = []
	for it: Dictionary in items:
		var n := character.inventory.add(String(it["item_id"]), int(it["count"]), db)
		if n > 0:
			given.append({"item_id": it["item_id"], "count": n})
			effects.append({"type": "item_gained", "item_id": it["item_id"], "qty": n})
	return given


func _weighted_pick(items: Array) -> Dictionary:
	var total := 0.0
	for it: Dictionary in items:
		total += maxf(0.0, float(it.get("weight", 1.0)))
	if items.is_empty() or total <= 0.0:
		return {}
	var roll := rng.randf() * total
	for it: Dictionary in items:
		roll -= maxf(0.0, float(it.get("weight", 1.0)))
		if roll < 0.0:
			return it
	return items[items.size() - 1]


func _count(item_id: Variant) -> int:
	return character.inventory.count(String(item_id))


func _job_display_name() -> String:
	if db == null:
		return ""
	return QuestJson.s(db.formula(character.job).get("name"))


## Inventory.can_add_all takes [{item_id, qty}]; quest data uses "count".
static func _qty_list(items: Array) -> Array:
	var out: Array = []
	for it: Dictionary in items:
		out.append({"item_id": String(it["item_id"]), "qty": int(it["count"])})
	return out


static func _fail(quest_id: String, reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "quest_id": quest_id, "effects": []}


## An inventory_full failure naming the first item that was to be given (for Events.inventory_full).
func _full(quest_id: String, items: Array) -> Dictionary:
	var r := _fail(quest_id, "inventory_full")
	r["item_id"] = String((items[0] as Dictionary)["item_id"]) if not items.is_empty() else ""
	return r
