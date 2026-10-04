class_name NpcDialogueBuilder
extends RefCounted
## Generates every NPC's conversation from canonical data (NPC lines, quest dialogue, quizzes, shops), then applies
## the NPC's override file data/misostory/dialogue/<npc_id>.json (add / replace / remove nodes). Nothing here names a
## specific NPC or quest: a new quest NPC needs only data.
##
## Generated graph (node ids):
##   start                 menu (auto_single) of the quest entries visible now, in this order:
##                           turn-ins of quests completed here and in progress   -> q<id>.turnin
##                           lost accept items of quests started here            -> q<id>.lost.0   (MeowDB "lost")
##                           reminders of quests started here, ended elsewhere   -> q<id>.reminder.0 (MeowDB "wrong_npc")
##                           offers of quests started here and available         -> q<id>.offer.0
##                         no entry -> talk. The menu text (several entries) is the NPC's first own line.
##   talk                  default talk: quest NPCs say their first "What X Says" line until all their quests are
##                         done, then the last one; other NPCs say all their lines in order; NPCs without quoted
##                         lines say their first idle-chatter line; shopkeepers -> shop.greeting -> open_shop.
##   q<id>.offer.<i>       on_accept lines; the last one is a Yes/No (accept). A quest with no "On accept" text
##                         (MeowDB gap, e.g. 1002) shows its journal text as a quest card instead.
##   q<id>.accepted.<i> / q<id>.declined.<i>    the accept / decline branches
##   q<id>.turnin          branch: ready -> completion lines (if any) -> quiz (if any) -> reward pick (if any) ->
##                         complete; else missing_kills / missing_items
##   q<id>.done.<i>        on_completion main lines, then the quiz, q<id>.select or q<id>.complete (action) ->
##                         q<id>.ready.<i> or start
##   q<id>.quiz            menu of the quiz choices; each runs complete_quest with its quiz_choice (answer_quiz when
##                         the quest also has a selection reward, then q<id>.quiz_right -> q<id>.select); a wrong
##                         choice shows its wrong-answer line (paired with the wrong choices in order) and ends the chat
##   q<id>.select          menu of a selection reward (MeowDB rewardChoices); each choice completes with that pick
##   sys.*                 MisoStory system lines (inventory full, cannot accept / complete)

const SYSTEM_FILE_ID := DialogueText.SYSTEM_FILE_ID

var db: ContentDB
var quests: QuestCatalog
var npcs: NpcCatalog


func _init(p_db: ContentDB = null, p_quests: QuestCatalog = null, p_npcs: NpcCatalog = null) -> void:
	db = p_db
	quests = p_quests if p_quests != null else QuestCatalog.new(db)
	npcs = p_npcs if p_npcs != null else NpcCatalog.new(db)


## The NPC's conversation: generated, then overridden. Empty graph (no nodes) for an unknown NPC.
func build(npc_id: String) -> DialogueGraph:
	var g := generate(npc_id)
	var o := db.miso_entity("dialogue", npc_id)
	if not o.is_empty():
		g.apply_override(o)
	return g


## The generated conversation without the override file.
func generate(npc_id: String) -> DialogueGraph:
	var g := DialogueGraph.new()
	g.id = "npc_" + npc_id
	g.npc_id = npc_id
	var n := npcs.get_def(npc_id)
	if n == null:
		return g
	var own_line := _own_line(n)
	var entries: Array = []
	# The quest records decide which quests an NPC starts and ends (the same lookups QuestEngine.npc_marker uses),
	# so a quest added as data is offered even if the NPC record does not list it yet; an adaptation can still
	# switch the behaviour off ("disabled_behaviors": ["quest"]).
	var quest_disabled := "quest" in QuestJson.strings(n.adaptation.get("disabled_behaviors"))
	var quest_npc := not quest_disabled and (n.has_behavior("quest") or not quests.started_by(npc_id).is_empty()
		or not quests.completed_by(npc_id).is_empty())
	if quest_npc:
		for qid in quests.completed_by(npc_id):
			_add_turn_in(g, quests.get_def(qid), entries)
		for qid in quests.started_by(npc_id):
			_add_start_side(g, quests.get_def(qid), entries)
	g.set_node("start", {"type": "menu", "line": own_line, "auto_single": true, "empty_next": "talk",
		"choices": entries})
	_add_talk(g, n)
	_add_system_nodes(g)
	return g


## Builds and validates every NPC's conversation. Empty = valid.
func validate_all() -> PackedStringArray:
	var errs := PackedStringArray()
	for nid in npcs.ids():
		errs.append_array(build(nid).validate(db))
	for oid: String in db.miso.get("dialogue", {}):
		var o: Dictionary = db.miso["dialogue"][oid]
		if oid != SYSTEM_FILE_ID and not npcs.has(oid):
			errs.append("misostory/dialogue/%s.json: no canonical npc %s" % [oid, oid])
		if QuestJson.s(o.get("reason")).is_empty():
			errs.append("misostory/dialogue/%s.json: missing top-level reason" % oid)
		if not o.has("verified"):
			errs.append("misostory/dialogue/%s.json: missing top-level verified flag" % oid)
	return errs


# --- quest offer side -----------------------------------------------------------------------------------------

func _add_start_side(g: DialogueGraph, d: QuestDef, entries: Array) -> void:
	var q := d.id
	var p := "q%s." % q
	var elsewhere := d.end_npc_id != d.start_npc_id
	var has_lost := d.has_branch("on_completion", "lost_items")
	# MeowDB files "lost" and "wrong_npc" under On completion, but they read as the start NPC speaking
	# (docs/canonical/npcs.md, speaker caveat): MisoStory routes them to the start NPC.
	if has_lost and not d.accept_items.is_empty():
		_chain(g, p + "lost", _branch_specs(d, "on_completion", "lost_items"), p + "reissue", d.name)
		g.set_node(p + "reissue", {"type": "action", "actions": [{"type": "reissue_quest_items", "quest": q}],
			"next": "", "on_fail": {"inventory_full": "sys.inventory_full", "*": ""}})
		entries.append(_entry(d, "lost", {"type": "all", "of": [_status(q, QuestLog.IN_PROGRESS),
			{"type": "quest_items_lost", "quest": q}]}, p + "lost.0"))
	if elsewhere and d.has_branch("on_completion", "wrong_npc"):
		_chain(g, p + "reminder", _branch_specs(d, "on_completion", "wrong_npc"), "", d.name)
		var cond := _status(q, QuestLog.IN_PROGRESS)
		if has_lost and not d.accept_items.is_empty():
			cond = {"type": "all", "of": [cond, {"type": "not", "of": {"type": "quest_items_lost", "quest": q}}]}
		entries.append(_entry(d, "reminder", cond, p + "reminder.0"))
	_add_offer(g, d)
	entries.append(_entry(d, "offer", {"type": "quest_available", "quest": q}, p + "offer.0"))


func _add_offer(g: DialogueGraph, d: QuestDef) -> void:
	var q := d.id
	var p := "q%s." % q
	var specs: Array = []
	var speaker := "npc"
	for i in d.section_lines("on_accept").size():
		specs.append({"quest": q, "section": "on_accept", "line": i})
	if specs.is_empty():
		# No canonical "On accept" text: offer the quest as a card showing its canonical journal text.
		speaker = "journal"
		var jl := d.journal_lines.size()
		specs.append({"quest": q, "journal": 1 if jl >= 3 else 0})
	var accepted := _branch_specs(d, "on_accept", "accepted")
	var declined := _branch_specs(d, "on_accept", "declined")
	for i in specs.size():
		var nid := p + "offer.%d" % i
		if i < specs.size() - 1:
			g.set_node(nid, {"type": "say", "line": specs[i], "next": p + "offer.%d" % (i + 1), "title": d.name, "speaker": speaker})
		else:
			g.set_node(nid, {"type": "yes_no", "line": specs[i], "title": d.name, "speaker": speaker,
				"yes": {"actions": [{"type": "accept_quest", "quest": q}],
					"next": p + "accepted.0" if not accepted.is_empty() else "",
					"on_fail": {"inventory_full": "sys.inventory_full", "*": "sys.cannot_accept"}},
				"no": {"next": p + "declined.0" if not declined.is_empty() else ""}})
	_chain(g, p + "accepted", accepted, "", d.name)
	_chain(g, p + "declined", declined, "", d.name)


# --- quest turn-in side ---------------------------------------------------------------------------------------

func _add_turn_in(g: DialogueGraph, d: QuestDef, entries: Array) -> void:
	var q := d.id
	var p := "q%s." % q
	var main := _main_specs(d, "on_completion")
	var ready := _branch_specs(d, "on_completion", "ready")
	var kills := _branch_specs(d, "on_completion", "missing_kills")
	var items := _branch_specs(d, "on_completion", "missing_items")
	var has_quiz := not d.quiz.is_empty()
	var has_selection := not d.reward_selection.is_empty()

	# What happens once the quest is ready to turn in.
	var finish := p + "complete"
	if has_selection:
		finish = p + "select"
		_add_selection(g, d, ready)
	g.set_node(p + "complete", {"type": "action", "actions": [{"type": "complete_quest", "quest": q}],
		"next": p + "ready.0" if not ready.is_empty() else "start",
		"on_fail": {"inventory_full": "sys.inventory_full", "*": "sys.cannot_complete"}})
	# Main completion lines come first, then the quiz (if any), then the reward pick / completion.
	var after_main := finish
	if has_quiz:
		after_main = p + "quiz"
		_add_quiz(g, d, has_selection, ready)
	var on_ready := after_main
	if not main.is_empty():
		on_ready = p + "done.0"
		_chain(g, p + "done", main, after_main, d.name)
	_chain(g, p + "ready", ready, "", d.name)
	_chain(g, p + "missing_kills", kills, "", d.name)
	_chain(g, p + "missing_items", items, "", d.name)

	var cases: Array = [{"condition": {"type": "quest_ready", "quest": q}, "next": on_ready}]
	if not kills.is_empty():
		cases.append({"condition": {"type": "objective", "quest": q, "kind": "monster_kills", "done": false},
			"next": p + "missing_kills.0"})
	if not items.is_empty():
		cases.append({"condition": {"type": "any", "of": [
			{"type": "objective", "quest": q, "kind": "item_collection", "done": false},
			{"type": "objective", "quest": q, "kind": "item_usage", "done": false}]}, "next": p + "missing_items.0"})
	var fallback := "talk"
	if not kills.is_empty():
		fallback = p + "missing_kills.0"
	elif not items.is_empty():
		fallback = p + "missing_items.0"
	g.set_node(p + "turnin", {"type": "branch", "cases": cases, "default": fallback})
	entries.append(_entry(d, "turnin", _status(q, QuestLog.IN_PROGRESS), p + "turnin"))


## The quiz menu. Without a selection reward each choice completes the quest with its quiz_choice (graded against
## canonical correct_choice_index), then shows the correct-answer line and the "ready" lines. With a selection reward
## each choice only grades the answer (answer_quiz); the correct-answer line then leads to the reward pick, which
## completes the quest.
func _add_quiz(g: DialogueGraph, d: QuestDef, has_selection: bool = false, ready: Array = []) -> void:
	var q := d.id
	var p := "q%s." % q
	var choices := QuestJson.arr(d.quiz.get("choices"))
	var correct := QuestJson.i(d.quiz.get("correct_choice_index"), -1)
	var wrong_lines := QuestJson.arr(d.quiz.get("wrong_answer_responses"))
	for k in wrong_lines.size():
		g.set_node(p + "quiz_wrong.%d" % k, {"type": "say", "line": {"quest": q, "quiz": "wrong", "line": k},
			"next": "", "title": d.name, "back": false})
	var after_right := ""
	if has_selection:
		after_right = p + "select"
	elif not ready.is_empty():
		after_right = p + "ready.0"
	var right_line := {"quest": q, "quiz": "right"}
	if QuestJson.dict(d.quiz.get("correct_answer_response")).is_empty():
		# No canonical correct-answer line: go straight on.
		right_line = {}
	if right_line.is_empty():
		g.set_node(p + "quiz_right", {"type": "branch", "cases": [], "default": after_right})
	else:
		g.set_node(p + "quiz_right", {"type": "say", "line": right_line, "next": after_right, "title": d.name})
	var opts: Array = []
	var wrong_rank := 0
	for i in choices.size():
		# MeowDB lists one wrong-answer line per wrong choice, in choice order, without linking them; MisoStory
		# pairs them in that order (true for every Maple Island quiz).
		var wrong_target := "sys.cannot_complete"
		if i != correct:
			if not wrong_lines.is_empty():
				wrong_target = p + "quiz_wrong.%d" % mini(wrong_rank, wrong_lines.size() - 1)
			wrong_rank += 1
		var act := {"type": "answer_quiz", "quest": q, "choice": i} if has_selection \
			else {"type": "complete_quest", "quest": q, "quiz_choice": i}
		opts.append({"line": {"quest": q, "quiz": "choice", "line": i},
			"actions": [act],
			"next": p + "quiz_right",
			"on_fail": {"wrong_answer": wrong_target, "inventory_full": "sys.inventory_full", "*": "sys.cannot_complete"}})
	g.set_node(p + "quiz", {"type": "menu", "line": {"quest": q, "quiz": "question"}, "title": d.name,
		"auto_single": false, "empty_next": "", "choices": opts})


## A selection reward (MeowDB rewardChoices) becomes a menu of the items; picking one completes the quest.
func _add_selection(g: DialogueGraph, d: QuestDef, ready: Array) -> void:
	var q := d.id
	var p := "q%s." % q
	var opts: Array = []
	var group: Dictionary = d.reward_selection[0]
	for i in (group["items"] as Array).size():
		var it: Dictionary = group["items"][i]
		var item_name := QuestJson.s(db.item(it["item_id"]).get("name"), String(it["item_id"]))
		opts.append({"line": {"text": "%s x%d" % [item_name, int(it["count"])], "source": "canonical/items/%s.json#name" % it["item_id"]},
			"actions": [{"type": "complete_quest", "quest": q, "selection_index": i}],
			"next": p + "ready.0" if not ready.is_empty() else "start",
			"on_fail": {"inventory_full": "sys.inventory_full", "*": "sys.cannot_complete"}})
	g.set_node(p + "select", {"type": "menu", "line": {"quest": q, "name": true}, "title": d.name,
		"auto_single": false, "empty_next": "", "choices": opts})


# --- talk, shop, system ---------------------------------------------------------------------------------------

func _add_talk(g: DialogueGraph, n: NpcDef) -> void:
	var own := n.dialogue_lines.size()
	if n.has_behavior("shop"):
		g.set_node("talk", {"type": "branch", "cases": [], "default": "shop.greeting"})
		# MeowDB has no shop greeting (docs/canonical/npcs.md gaps): the NPC's own first line is used unless the
		# NPC's dialogue override picks another.
		g.set_node("shop.greeting", {"type": "say", "line": _own_line(n), "next": "shop.open"})
		g.set_node("shop.open", {"type": "action", "actions": [{"type": "open_shop", "shop": n.shop_id}], "next": ""})
		return
	if own == 0:
		g.set_node("talk", {"type": "say", "line": _own_line(n), "next": ""})
		return
	var mine := n.all_quests()
	if n.has_behavior("quest") and own >= 2 and not mine.is_empty():
		# MeowDB does not label when each "What X Says" line is shown; the last one reads as the after-quest line
		# (Heena, Roger, Maria, Rain, Mai), so MisoStory shows it once all of the NPC's quests are completed.
		var done_all: Array = []
		for q in mine:
			done_all.append(_status(q, QuestLog.COMPLETED))
		var before: Array = []
		for i in own - 1:
			before.append({"npc": n.id, "field": "dialogue", "line": i})
		_chain(g, "talk.before", before, "", "")
		_chain(g, "talk.after", [{"npc": n.id, "field": "dialogue", "line": own - 1}], "", "")
		g.set_node("talk", {"type": "branch", "cases": [{"condition": {"type": "all", "of": done_all},
			"next": "talk.after.0"}], "default": "talk.before.0"})
		return
	var all_lines: Array = []
	for i in own:
		all_lines.append({"npc": n.id, "field": "dialogue", "line": i})
	_chain(g, "talk.lines", all_lines, "", "")
	g.set_node("talk", {"type": "branch", "cases": [], "default": "talk.lines.0"})


func _add_system_nodes(g: DialogueGraph) -> void:
	for key in ["inventory_full", "cannot_accept", "cannot_complete"]:
		g.set_node("sys." + key, {"type": "say", "line": {"system": key}, "next": "", "speaker": "system", "back": false})


# --- helpers --------------------------------------------------------------------------------------------------

## A chain of say nodes "<prefix>.0", "<prefix>.1", ... ; the last leads to `last_next`.
func _chain(g: DialogueGraph, prefix: String, specs: Array, last_next: String, title: String) -> void:
	for i in specs.size():
		var nxt := prefix + ".%d" % (i + 1) if i < specs.size() - 1 else last_next
		var node := {"type": "say", "line": specs[i], "next": nxt}
		if not title.is_empty():
			node["title"] = title
		g.set_node(prefix + ".%d" % i, node)


func _main_specs(d: QuestDef, section_name: String) -> Array:
	var out: Array = []
	for i in d.section_lines(section_name).size():
		out.append({"quest": d.id, "section": section_name, "line": i})
	return out


func _branch_specs(d: QuestDef, section_name: String, state: String) -> Array:
	var out: Array = []
	for i in d.branch_lines(section_name, state).size():
		out.append({"quest": d.id, "section": section_name, "branch": state, "line": i})
	return out


func _entry(d: QuestDef, tag: String, condition: Dictionary, next_id: String) -> Dictionary:
	return {"line": {"quest": d.id, "name": true}, "quest_id": d.id, "tag": tag, "condition": condition, "next": next_id}


static func _status(q: String, st: String) -> Dictionary:
	return {"type": "quest_status", "quest": q, "is": st}


## The NPC's first own line: "What X Says" line 0, else idle chatter line 0, else its name as literal text.
static func _own_line(n: NpcDef) -> Dictionary:
	if not n.dialogue_lines.is_empty():
		return {"npc": n.id, "field": "dialogue", "line": 0}
	if not n.idle_chatter.is_empty():
		return {"npc": n.id, "field": "idle_chatter", "line": 0}
	return {"text": n.name, "source": "canonical/npcs/%s.json#name" % n.id}
