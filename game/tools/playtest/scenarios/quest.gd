extends PlaytestScenario
## quest: the every-quest real-game scenario (brief "Full Quest Playthrough Requirement"). One quest or one chain per
## run, chosen with --quest <spec> (or the QUEST environment variable): "1002", "1013-1019", "1006,1009,1010".
## scripts/playtest_quests.sh runs every chain of the canonical set (PlaytestQuestPlan.chains) and writes the
## per-quest table. Everything about a quest comes from PlaytestQuestPlan (canonical data): its NPCs and maps, level,
## prerequisites, objectives and where they are met, the quiz answers and the rewards.
##
## Phase 0 is the SETUP, the only place a console command may run (each is a logged console step): a new game
## through the real title and creation screens, a warp to the first quest's start map, the first quest's level and
## the prerequisite quests outside the chain (quest accept + quest complete force). Before the level is set, a
## level-gated quest is checked to be refused (no offer marker, the engine says unavailable). The pause menu saves
## and Quit Game ends the process.
## Phase 1 starts from that save (Continue) and turns STRICT mode on: from here no console command, no api fallback
## and no change to the character the event bus did not announce. Every quest of the chain is then PLAYED with real
## input: availability (the NPC's marker, the Quest Log's Available tab), the offer accepted in the dialogue, the
## accept items, objective progress (kills with the attack key, drops picked up with Z, Wooden Boxes broken, items
## used by double-click, quizzes answered in the menu, one wrong answer first), the turn-in, the exact canonical
## rewards (EXP, mesos, items, one item of each random group), and the follow-up's availability. A save and a
## process restart happen in the middle (mid-objective of each quest with objectives, after the accept of the first
## talk-only quest, and after the middle quest of a long chain); the next phase checks the progress survived.
## Every quest check carries the parity key quest:<id>; d.carry["quest_results"] is the per-quest verdict.

const WEAPON := "585"
const CHAR_NAME := "QuestRun"
## AP goes into the stats window in this order (a Wooden Club warrior's split, as test_c's hunter).
const AP_PLAN := ["str", "dex"]
## Game-second budgets of the objective hunts.
const KILL_BUDGET_S := 1200.0
const ITEM_BUDGET_S := 1500.0
const LEVEL_BUDGET_S := 1500.0
## Wooden Box respawns are 90-180 s (maps/<id>.json reactors); the box hunt waits for them up to this long.
const BOX_BUDGET_S := 1500.0

var d: PlaytestDriver = null
var db: ContentDB = null
var k: PlaytestKit = null
var ids: PackedStringArray = []
var plans: Dictionary = {}


func description() -> String:
	return "Every-quest set: one quest or chain (--quest / QUEST) played with real input from a setup save, strict after the setup"


func max_seconds() -> float:
	return 3000.0


func run(p_d: PlaytestDriver) -> void:
	d = p_d
	db = d.db()
	k = PlaytestKit.new(d)
	var spec := _spec()
	ids = PlaytestQuestPlan.parse_ids(spec, db)
	if not d.check("--quest / QUEST names canonical quests ('%s')" % spec, not ids.is_empty(), "known: %s" % db.ids("quests")):
		return
	d.carry["quest_spec"] = spec
	for id in ids:
		plans[id] = PlaytestQuestPlan.plan(id, db)
	if d.phase == 0:
		await _setup_phase()
		return
	await _play_phase()


## The chain: --quest <spec> on the command line, else QUEST, else what phase 0 kept in carry.
func _spec() -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--quest")
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	if OS.get_environment("QUEST") != "":
		return OS.get_environment("QUEST")
	return String(d.carry.get("quest_spec", "")) if d.carry != null else ""


# =================================================================================================================
# Phase 0: the setup (console allowed, every command logged)
# =================================================================================================================

func _setup_phase() -> void:
	var ng: Dictionary = await d.new_game(CHAR_NAME, "female", WEAPON, {"str": 5, "dex": 4})
	if not d.check("new game through the title and creation screens", bool(ng["ok"]) and ng["via"] == "screen",
			"%s in %s via %s %s" % [ng["slot"], ng["map"], ng["via"], ng["why"]]):
		return
	k.connect_bus()
	for id in ids:
		var p: Dictionary = plans[id]
		d.check("%s: a play plan from canonical data (%s)" % [id, p["name"]], bool(p["ok"]), "; ".join(p["blocked"]), _pq(id))
		d.note("%s plan: start %s@%s, end %s@%s, level %d, prerequisites %s, kills %s, items %s, uses %s, quiz %s, rewards %s"
			% [id, p["start"]["npc_name"], p["start"]["map"], p["end"]["npc_name"], p["end"]["map"], int(p["min_level"]),
			p["prerequisites"], _kills_text(p), _items_text(p), p["uses"], (p["quiz"] as Dictionary).get("text", "-"), p["rewards"]])
	var setup := PlaytestQuestPlan.setup_for(ids, db)
	d.carry["setup"] = setup
	var first := ids[0]
	var fp: Dictionary = plans[first]
	if d.current_map() != String(setup["map"]):
		await _setup_console("warp %s" % setup["map"])
	d.check("setup: in %s's start map %s" % [first, setup["map"]], d.current_map() == String(setup["map"]), d.current_map())
	if int(setup["level"]) > d.character().level:
		# The canonical level gate: below min_level the quest is not offered.
		var m := await k.marker(String(fp["start"]["npc"]))
		var engine := d.game().quests.engine
		d.check("%s is refused below its canonical level %d (level %d: no offer, the engine says unavailable)" % [first,
			int(setup["level"]), d.character().level], not engine.is_available(first) and not _offers(m, first),
			"marker %s" % m, _pq(first))
		await _setup_console("level %d" % int(setup["level"]))
	for pid in setup["complete"]:
		await _setup_console("quest accept %s" % pid)
		await _setup_console("quest complete %s force" % pid)
	var c := d.character()
	d.check("setup: level %d, prerequisites %s completed" % [int(setup["level"]), setup["complete"]],
		c.level >= int(setup["level"]) and Array(setup["complete"]).all(func(q: String) -> bool: return c.quests.is_completed(q)),
		"level %d, completed %s" % [c.level, c.quests.completed_ids()])
	var saved: Dictionary = await d.save_game()
	d.check("setup saved through the pause menu", bool(saved["ok"]) and saved["via"] == "screen", str(saved))
	d.carry["slot"] = String(saved.get("slot", ng["slot"]))
	await d.reload_process()


## A setup console command (logged as a "console" step). Only phase 0 calls it; strict mode would refuse it.
func _setup_console(cmd: String) -> void:
	var out := await d.console(cmd)
	d.note("setup: %s -> %s" % [cmd, out.left(120).replace("\n", " / ")])


# =================================================================================================================
# Phase 1+: play, strict
# =================================================================================================================

func _play_phase() -> void:
	var cont: Dictionary = await d.continue_game()
	if not d.check("Continue loads the run's save (phase %d)" % d.phase, bool(cont["ok"]) and cont["via"] == "screen"
			and String(cont["slot"]) == String(d.carry.get("slot", cont["slot"])), str(cont)):
		return
	if d.phase == 1:
		d.begin_strict("after the setup save")
	k.connect_bus()
	await _verify_mid()
	var c := d.character()
	var stopped := ""
	for qid in ids:
		if c.quests.is_completed(qid):
			continue
		if c.quests.status(qid) == QuestLog.NOT_STARTED and not await _offer(qid):
			stopped = qid
			break
		if not await _objectives(qid):
			stopped = qid
			break
		if not await _turn_in(qid):
			stopped = qid
			break
		await _after(qid)
		await _maybe_reload_between(qid)
	if stopped != "":
		d.note("the chain stopped at %s" % stopped)
	k.checkpoint("end of %s" % ",".join(ids))
	d.note("travel %s; deaths %d; %d damage from %d touches; survival %s" % [k.travel_text(), k.deaths.size(),
		k.damage_taken, k.touches.size(), k.survival])
	_results()


# --- availability and acceptance --------------------------------------------------------------------------------

func _offer(qid: String) -> bool:
	var p: Dictionary = plans[qid]
	var c := d.character()
	var pq := _pq(qid)
	var npc := String(p["start"]["npc"])
	if c.level < int(p["min_level"]) and not await _reach_level(int(p["min_level"]), String(p["start"]["map"])):
		d.check("%s: level %d reached by play for its canonical min_level" % [qid, int(p["min_level"])], false,
			"level %d" % c.level, pq)
		return false
	if not d.check("%s: walked to %s's map %s" % [qid, p["start"]["npc_name"], p["start"]["map"]],
			await k.travel_to(String(p["start"]["map"])), d.current_map(), pq):
		return false
	await k.approach(npc)
	var m0 := await k.marker(npc)
	d.check("%s: %s's marker offers it (gold !; the engine agrees)" % [qid, p["start"]["npc_name"]],
		m0["state"] == "available" and m0["engine"] == "available" and d.game().quests.engine.is_available(qid), str(m0),
		pq + ["mechanic:quest-indicators"])
	var avail := await k.quest_window(qid, "available")
	d.check("%s: the Quest Log's Available tab lists it before the accept" % qid, bool(avail["listed"]),
		"list %s" % [avail["list"]], pq + ["mechanic:quest-log"])
	await d.close_window("quests")
	var bag0 := k.snapshot()
	var talk: Dictionary = await k.talk(npc)
	if not d.check("%s: %s can be talked to on foot" % [qid, p["start"]["npc_name"]], bool(talk.get("open", false)),
			"%s %s" % [talk.get("talk_gap", ""), talk.get("why", "")], pq + ["npc:" + npc]):
		return false
	var clock0 := float((talk["pre"] as Dictionary)["clock"])
	var conv: Dictionary = await k.converse({qid: "accept"})
	d.note("%s accept pages: %s" % [qid, " | ".join(conv["pages"])])
	if not d.check("%s: accepted in %s's dialogue (Yes)" % [qid, p["start"]["npc_name"]], c.quests.is_in_progress(qid)
			or c.quests.is_completed(qid), c.quests.status(qid), pq):
		return false
	var given := PackedStringArray()
	var given_ok := true
	for it: Dictionary in p["accept_items"]:
		var id := String(it["item_id"])
		var n := c.inventory.count(id)
		given_ok = given_ok and n >= int(it["count"])
		given.append("%s %s x%d (held %d, was %d)%s" % [id, k.item_name(id), int(it["count"]), n,
			PlaytestKit.count_in(bag0["bag"], id), " (MisoStory adaptation)" if bool(it["adaptation"]) else ""])
	if not (p["accept_items"] as Array).is_empty():
		d.check("%s: the accept items are in the bag: %s" % [qid, ", ".join(given)], given_ok, ", ".join(given), pq)
	var lines := k.log_since(clock0)
	d.check("%s: the HUD log says 'Quest started: %s'" % [qid, p["name"]], ("Quest started: %s" % p["name"]) in lines,
		" / ".join(lines), pq)
	var m1 := await k.marker(npc)
	d.check("%s: %s's marker after the accept is the engine's ('%s')" % [qid, p["start"]["npc_name"], m1["engine"]],
		m1["state"] == m1["engine"] and (m1["state"] != "available" or _offers_other(npc, qid)), str(m1),
		pq + ["mechanic:quest-indicators"])
	var qw := await k.quest_window(qid, "in_progress")
	d.check("%s: the Quest Log lists it In Progress (%s)" % [qid, PlaytestKit.rows_text(qw["rows"])], bool(qw["listed"])
		or c.quests.is_completed(qid), "list %s" % [qw["list"]], pq + ["mechanic:quest-log"])
	await d.close_window("quests")
	# A quest with nothing but a talk, quiz or use objective: the save and restart happen right after the accept.
	if _talk_only(qid) and not _reloaded_once():
		await _mid_reload(qid, "after the accept")
	return true


## True when `m` (a marker read) shows an offer for `qid` at its NPC.
func _offers(m: Dictionary, qid: String) -> bool:
	return String(m.get("state", "")) == "available" and d.game().quests.engine.is_available(qid)


## True when the NPC still offers another quest (its marker stays "available" after the accept).
func _offers_other(npc: String, qid: String) -> bool:
	var engine := d.game().quests.engine
	for other in engine.catalog.started_by(npc):
		if other != qid and engine.is_available(other):
			return true
	return false


# --- objectives -------------------------------------------------------------------------------------------------

func _objectives(qid: String) -> bool:
	var p: Dictionary = plans[qid]
	var c := d.character()
	var pq := _pq(qid)
	for kobj: Dictionary in p["kills"]:
		var mob := String(kobj["mob_id"])
		var need := int(kobj["count"])
		if c.quests.kills(qid, mob) >= need:
			continue
		var map := String(kobj["hunt_map"])
		if not d.check("%s: walked to %s to hunt %s" % [qid, map, kobj["name"]], await k.travel_to(map), d.current_map(), pq):
			return false
		var half := floori(need / 2.0)
		if not _reloaded(qid) and c.quests.kills(qid, mob) < half:
			var h0: Dictionary = await k.hunt([mob], func() -> bool: return c.quests.kills(qid, mob) >= half,
				{"map": map, "ap_plan": AP_PLAN, "max_s": KILL_BUDGET_S})
			d.note("%s: hunted %s to %d/%d (%s)" % [qid, kobj["name"], c.quests.kills(qid, mob), need, h0])
			if c.quests.kills(qid, mob) >= half:
				await _mid_reload(qid, "at %d/%d %s" % [c.quests.kills(qid, mob), need, kobj["name"]])
		elif not _reloaded(qid) and half < 1:
			await _mid_reload(qid, "at 0/%d %s" % [need, kobj["name"]])
		var k0 := c.quests.kills(qid, mob)
		var h: Dictionary = await k.hunt([mob], func() -> bool: return c.quests.kills(qid, mob) >= need,
			{"map": map, "ap_plan": AP_PLAN, "max_s": KILL_BUDGET_S})
		var qw := await k.quest_window(qid, "in_progress")
		var row := "%s %d/%d" % [kobj["name"], mini(c.quests.kills(qid, mob), need), need]
		await d.close_window("quests")
		if not d.check("%s: %d %s killed with the attack key in %s (%d -> %d of %d)" % [qid, need, kobj["name"], map, k0,
				c.quests.kills(qid, mob), need], c.quests.kills(qid, mob) >= need, "%s; Quest Log rows %s" % [h,
				PlaytestKit.rows_text(qw["rows"])], pq + ["monster:" + mob]):
			return false
		d.check("%s: the Quest Log shows '%s'" % [qid, row], PlaytestKit.row_has(qw["rows"], row, true)
			or c.quests.is_completed(qid), PlaytestKit.rows_text(qw["rows"]), pq + ["mechanic:quest-log"])
	for iobj: Dictionary in p["items"]:
		var id := String(iobj["item_id"])
		var need := int(iobj["count"])
		if c.inventory.count(id) >= need or bool(iobj["from_accept"]):
			continue
		if not await _collect(qid, iobj):
			return false
	for uobj: Dictionary in p["uses"]:
		var id := String(uobj["item_id"])
		var need := int(uobj["count"])
		while c.quests.uses(qid, id) < need:
			var hp0 := c.hp
			var r: Dictionary = await k.use_item(id)
			if not d.check("%s: %s used by a double-click in the Item window (%d/%d)" % [qid, uobj["name"], c.quests.uses(qid, id),
					need], bool(r["ok"]), "%s; HP %d -> %d" % [r["status"], hp0, c.hp], pq + ["item:" + id]):
				return false
	return true


## Collects a quest item from its best source: a monster's drop (hunting it and picking up with Z) or the Wooden Box
## (breaking boxes, C8). The source and its chance come from the canonical drop tables (PlaytestQuestPlan).
func _collect(qid: String, iobj: Dictionary) -> bool:
	var c := d.character()
	var pq := _pq(qid)
	var id := String(iobj["item_id"])
	var need := int(iobj["count"])
	var src: Dictionary = iobj.get("hunt", {})
	if src.is_empty():
		d.check("%s: a source for %s" % [qid, iobj["name"]], false, str(iobj["sources"]), pq)
		return false
	var map := String(src["map"])
	if not d.check("%s: walked to %s for %s (%s %s, chance %s)" % [qid, map, iobj["name"], src["kind"], src["owner_name"],
			src["chance"]], await k.travel_to(map), d.current_map(), pq):
		return false
	var n0 := c.inventory.count(id)
	if String(src["kind"]) == "breakable":
		return await _collect_from_boxes(qid, iobj, src)
	var half := floori(need / 2.0)
	if not _reloaded(qid) and half >= 1 and n0 < half:
		await k.hunt([String(src["owner"])], func() -> bool: return c.inventory.count(id) >= half,
			{"map": map, "ap_plan": AP_PLAN, "max_s": ITEM_BUDGET_S})
		if c.inventory.count(id) >= half:
			await _mid_reload(qid, "at %d/%d %s" % [c.inventory.count(id), need, iobj["name"]])
	var h: Dictionary = await k.hunt([String(src["owner"])], func() -> bool: return c.inventory.count(id) >= need,
		{"map": map, "ap_plan": AP_PLAN, "max_s": ITEM_BUDGET_S})
	return d.check("%s: %d %s collected from %s drops picked up with Z (%d -> %d)" % [qid, need, iobj["name"],
		src["owner_name"], n0, c.inventory.count(id)], c.inventory.count(id) >= need, str(h),
		pq + ["item:" + id, "drop:%s/%s" % [src["owner"], id]])


## Breaks Wooden Boxes (contract C8) in the source's maps until the bag holds `need`: the attack key on each box,
## the drops picked up with Z, the next map when every box of this one is broken, and a wait for the respawns.
func _collect_from_boxes(qid: String, iobj: Dictionary, src: Dictionary) -> bool:
	var c := d.character()
	var pq := _pq(qid) + ["breakable:%s" % src["owner"]]
	var id := String(iobj["item_id"])
	var need := int(iobj["count"])
	var boxes := k.breakables(true)
	if not d.check("%s: Wooden Boxes stand in %s (group miso_breakables, contract C8)" % [qid, d.current_map()],
			not boxes.is_empty(), "the breakables runtime is not built: %s comes only from the Wooden Box" % iobj["name"], pq):
		return false
	var maps: Array = Array(src["maps"])
	var t0 := d.game_s()
	var broken := 0
	var mi := maps.find(d.current_map())
	while _still_need(qid) and d.game_s() - t0 < BOX_BUDGET_S:
		if k.is_dead():
			await k.respawn()
			continue
		var r: Dictionary = await k.break_box(null)
		if bool(r["ok"]):
			broken += 1
			d.check("%s: a Wooden Box broke after %d landed hits (canonical hits_to_break %d)" % [qid, int(r["hits"]),
				int(db.get_entity("breakables", String(src["owner"])).get("hits_to_break", -1))],
				int(r["hits"]) == int(db.get_entity("breakables", String(src["owner"])).get("hits_to_break", -1)), str(r), pq)
			continue
		# Every box here is broken: the next map that has boxes, or a wait for the respawns.
		mi = (mi + 1) % maps.size()
		if maps.size() > 1 and String(maps[mi]) != d.current_map():
			await k.travel_to(String(maps[mi]))
		else:
			await d.wait(10.0)
	return d.check("%s: %s x%d from %d broken Wooden Boxes (held %d)" % [qid, iobj["name"], need, broken, c.inventory.count(id)],
		not _still_need(qid), "", pq + ["item:" + id])


func _still_need(qid: String) -> bool:
	var c := d.character()
	for iobj: Dictionary in (plans[qid] as Dictionary)["items"]:
		if not bool(iobj["from_accept"]) and c.inventory.count(String(iobj["item_id"])) < int(iobj["count"]):
			return true
	return false


## Hunts in the nearest map with monsters until the character reaches `level` (a later quest of the chain needs it).
func _reach_level(level: int, near_map: String) -> bool:
	var c := d.character()
	var best := ""
	var best_h := 1 << 30
	for m in db.ids("maps"):
		if (db.map(m).get("spawns", []) as Array).is_empty():
			continue
		var h := PlaytestQuestPlan.hops(d.current_map(), m, db)
		var back := PlaytestQuestPlan.hops(m, near_map, db)
		if h >= 0 and back >= 0 and h + back < best_h:
			best_h = h + back
			best = m
	if best == "" or not await k.travel_to(best):
		return false
	var mobs: Array = []
	for s: Dictionary in db.map(best).get("spawns", []):
		if not mobs.has(String(s.get("mob_id", ""))):
			mobs.append(String(s.get("mob_id", "")))
	var h: Dictionary = await k.hunt(mobs, func() -> bool: return c.level >= level, {"map": best, "ap_plan": AP_PLAN,
		"max_s": LEVEL_BUDGET_S})
	d.note("hunted in %s to level %d for the next quest: %s" % [best, c.level, h])
	return c.level >= level


# --- turn-in ----------------------------------------------------------------------------------------------------

func _turn_in(qid: String) -> bool:
	var p: Dictionary = plans[qid]
	var c := d.character()
	var pq := _pq(qid)
	var npc := String(p["end"]["npc"])
	if c.quests.is_completed(qid):
		return true
	if not d.check("%s: walked to %s's map %s for the turn-in" % [qid, p["end"]["npc_name"], p["end"]["map"]],
			await k.travel_to(String(p["end"]["map"])), d.current_map(), pq):
		return false
	await k.approach(npc)
	var m0 := await k.marker(npc)
	d.check("%s: %s's marker reads 'completable' (green ?)" % [qid, p["end"]["npc_name"]], m0["state"] == "completable"
		and m0["engine"] == "completable", str(m0), pq + ["mechanic:quest-indicators"])
	var quiz: Dictionary = p["quiz"]
	if not quiz.is_empty():
		# One wrong answer first: the canonical paired line, and the quest stays in progress.
		var wrong: Dictionary = (quiz["wrong"] as Array)[0] if not (quiz["wrong"] as Array).is_empty() else {}
		var tw: Dictionary = await k.talk(npc)
		if not d.check("%s: %s can be talked to for the quiz" % [qid, p["end"]["npc_name"]], bool(tw.get("open", false)),
				String(tw.get("why", "")), pq):
			return false
		var cw: Dictionary = await k.converse({qid: "quiz_wrong"})
		var aw: Dictionary = (cw["quiz"] as Array)[0] if not (cw["quiz"] as Array).is_empty() else {}
		d.check("%s: the quiz '%s' is a menu of the canonical choices" % [qid, quiz["question"]], not aw.is_empty(),
			" | ".join(cw["pages"]), pq + ["mechanic:quiz-quests"])
		d.check("%s: the wrong answer '%s' shows its canonical line and leaves the quest in progress" % [qid, wrong.get("text", "")],
			not aw.is_empty() and not bool(aw["correct"]) and _same_text(String(aw["response"]), String(wrong.get("response", "")))
			and c.quests.is_in_progress(qid), "picked '%s'; shown '%s'; canonical '%s'; status %s" % [aw.get("choice", ""),
				String(aw.get("response", "")).left(100), String(wrong.get("response", "")).left(100), c.quests.status(qid)],
			pq + ["mechanic:quiz-quests"])
	var talk: Dictionary = await k.talk(npc)
	if not d.check("%s: %s can be talked to for the turn-in" % [qid, p["end"]["npc_name"]], bool(talk.get("open", false)),
			"%s %s" % [talk.get("talk_gap", ""), talk.get("why", "")], pq + ["npc:" + npc]):
		return false
	var snap: Dictionary = talk["pre"]
	var t0 := float(snap["t"])
	var conv: Dictionary = await k.converse({qid: "complete"})
	d.note("%s turn-in pages: %s" % [qid, " | ".join(conv["pages"])])
	await d.wait(0.3)
	if not quiz.is_empty():
		var ar: Dictionary = (conv["quiz"] as Array)[0] if not (conv["quiz"] as Array).is_empty() else {}
		d.check("%s: the canonical answer '%s' (%s) completes the quiz" % [qid, quiz["text"], quiz["basis"]], not ar.is_empty()
			and bool(ar["correct"]) and String(ar["choice"]) == String(quiz["text"]) and c.quests.is_completed(qid),
			"picked %s; shown '%s'" % [ar, String(ar.get("response", "")).left(100)], pq + ["mechanic:quiz-quests"])
	if not d.check("%s: completed at %s" % [qid, p["end"]["npc_name"]], c.quests.is_completed(qid), c.quests.status(qid), pq):
		return false
	_check_rewards(qid, snap, t0)
	var lines := k.log_since(float(snap["clock"]))
	d.check("%s: the HUD log says 'Quest complete: %s'" % [qid, p["name"]], ("Quest complete: %s" % p["name"]) in lines,
		" / ".join(lines), pq)
	var done := await k.quest_window(qid, "completed")
	d.check("%s: the Quest Log's Completed tab lists it" % qid, bool(done["listed"]), "list %s" % [done["list"]],
		pq + ["mechanic:quest-log"])
	await d.close_window("quests")
	return true


## The exact canonical reward: total EXP + rewards.exp (one EXP event, "quest:<id>"), mesos + rewards.mesos, every
## fixed item, exactly one item of each random group, the hand-in items taken, nothing else in the bag.
func _check_rewards(qid: String, snap: Dictionary, t0: float) -> void:
	var p: Dictionary = plans[qid]
	var c := d.character()
	var pq := _pq(qid)
	var rew: Dictionary = p["rewards"]
	var after := k.snapshot()
	var dexp := int(after["total_exp"]) - int(snap["total_exp"])
	var ev := k.exp_since(t0)
	var exp_ok := dexp == int(rew["exp"]) and (ev.size() == 1 and int(ev[0][0]) == int(rew["exp"])
		and String(ev[0][1]) == "quest:" + qid if int(rew["exp"]) > 0 else ev.is_empty())
	d.check("%s: EXP exactly +%d (canonical rewards.exp)" % [qid, int(rew["exp"])], exp_ok,
		"total EXP %d -> %d (%+d), level %d -> %d, events %s" % [int(snap["total_exp"]), int(after["total_exp"]), dexp,
			int(snap["level"]), int(after["level"]), ev], pq)
	d.check("%s: mesos exactly +%d (canonical rewards.mesos)" % [qid, int(rew["mesos"])],
		int(after["mesos"]) - int(snap["mesos"]) == int(rew["mesos"]), "%d -> %d" % [int(snap["mesos"]), int(after["mesos"])], pq)
	# Expected bag changes: fixed rewards in, hand-ins out.
	var want := {}
	for it: Dictionary in rew["items"]:
		want[String(it["item_id"])] = int(want.get(String(it["item_id"]), 0)) + int(it["count"])
	for iobj: Dictionary in p["items"]:
		var id := String(iobj["item_id"])
		want[id] = int(want.get(id, 0)) - int(iobj["count"])
	var delta := PlaytestKit.bag_delta(snap["bag"], after["bag"], [])
	var picks := PackedStringArray()
	var bad := PackedStringArray()
	for group: Variant in rew["random"]:
		var hits := PackedStringArray()
		for id: String in group:
			if int(delta.get(id, 0)) - int(want.get(id, 0)) == 1:
				hits.append(id)
		if hits.size() == 1:
			want[hits[0]] = int(want.get(hits[0], 0)) + 1
			picks.append("%s %s" % [hits[0], k.item_name(hits[0])])
		else:
			bad.append("random group %s gave %s" % [group, hits])
	for id: String in want:
		if int(delta.get(id, 0)) != int(want[id]):
			bad.append("%s %s %+d, expected %+d" % [id, k.item_name(id), int(delta.get(id, 0)), int(want[id])])
	for id: String in delta:
		if not want.has(id):
			bad.append("%s %s %+d unexpected" % [id, k.item_name(id), int(delta[id])])
	d.check("%s: the bag changed by exactly the canonical rewards and hand-ins%s" % [qid,
		(" (random pick: %s)" % ", ".join(picks)) if not picks.is_empty() else ""], bad.is_empty(),
		"; ".join(bad) if not bad.is_empty() else str(delta), pq + (["mechanic:quest-random-rewards"] if not picks.is_empty() else []))
	if not (rew["random"] as Array).is_empty():
		d.carry["random_%s" % qid] = picks
		var entry: Dictionary = (c.quests.to_dict().get("quests", {}) as Dictionary).get(qid, {})
		if entry.has("rewards_received"):
			var rr: Dictionary = entry["rewards_received"] if entry["rewards_received"] is Dictionary else {}
			var recorded := PackedStringArray()
			for pick: Variant in rr.get("random_picks", []):
				if pick is Dictionary:
					recorded.append(String((pick as Dictionary).get("item_id", "")))
			d.check("%s: the quest log records the random pick it granted (C3 rewards_received)" % qid,
				picks.size() == recorded.size() and Array(picks).all(func(s: String) -> bool: return recorded.has(s.get_slice(" ", 0))),
				"granted %s, recorded %s" % [picks, recorded], pq + ["mechanic:quest-persistence"])
		else:
			d.soft_check("%s: the quest log records the random pick it granted (C3 rewards_received)" % qid, false,
				"no rewards_received in the quest entry yet (the saves/quests packages add it)", pq)


# --- after the turn-in ------------------------------------------------------------------------------------------

## Follow-up availability: each canonical follow-up is offered now (when the level allows), and its NPC's marker says
## so when the NPC stands in this map.
func _after(qid: String) -> void:
	var p: Dictionary = plans[qid]
	var c := d.character()
	var engine := d.game().quests.engine
	for f in p["followups"]:
		var fp := PlaytestQuestPlan.plan(f, db)
		var lvl_ok := c.level >= int(fp.get("min_level", 1))
		d.check("%s: its follow-up %s (%s) is %s at level %d" % [qid, f, fp.get("name", ""), "available" if lvl_ok else
			"level-gated", c.level], engine.is_available(f) == lvl_ok, "engine %s, min_level %d" % [engine.is_available(f),
			int(fp.get("min_level", 1))], _pq(qid) + ["quest:" + f])
		var npc := String((fp.get("start", {}) as Dictionary).get("npc", ""))
		if lvl_ok and String((fp.get("start", {}) as Dictionary).get("map", "")) == d.current_map():
			var m := await k.marker(npc)
			d.check("%s: %s's marker offers the follow-up %s" % [qid, k.npc_name(npc), f], m["state"] == "available", str(m),
				_pq(qid) + ["mechanic:quest-indicators"])


# --- the mid-run save and process restart ------------------------------------------------------------------------

func _reloaded(qid: String) -> bool:
	return (d.carry.get("reloaded", {}) as Dictionary).has(qid)


func _reloaded_once() -> bool:
	return not (d.carry.get("reloaded", {}) as Dictionary).is_empty()


## A quest with nothing to hunt or collect (talk, quiz, use, or a hand-in of what the accept gave).
func _talk_only(qid: String) -> bool:
	var p: Dictionary = plans[qid]
	return (p["kills"] as Array).is_empty() and (p["items"] as Array).all(func(it: Dictionary) -> bool: return bool(it["from_accept"]))


## After the middle quest of a chain of 3 or more: one more save and restart between quests.
func _maybe_reload_between(qid: String) -> void:
	if ids.size() < 3 or qid != ids[floori(ids.size() / 2.0) - 1] or (d.carry.get("reloaded", {}) as Dictionary).has("between"):
		return
	await _mid_reload("between", "after %s, the middle of the chain" % qid)


## Saves through the pause menu, keeps what must survive, and ends the process with Quit Game. The next phase's
## _verify_mid() checks it. Never returns.
func _mid_reload(qid: String, when: String) -> void:
	var c := d.character()
	var r: Dictionary = d.carry.get("reloaded", {})
	r[qid] = when
	d.carry["reloaded"] = r
	var saved: Dictionary = await d.save_game()
	d.check("%s: saved through the pause menu %s" % [qid, when], bool(saved["ok"]) and saved["via"] == "screen", str(saved),
		_pq(qid) + ["mechanic:quest-persistence"] if qid != "between" else ["mechanic:quest-persistence"])
	d.carry["mid"] = {"quest": qid, "when": when, "map": d.current_map(), "level": c.level, "exp": c.exp, "mesos": c.mesos,
		"log": c.quests.to_dict(), "bag": k.snapshot()["bag"]}
	k.checkpoint("before the restart %s" % when)
	await d.reload_process()


## After a restart: the quest log, level, EXP, mesos, bag and map are the saved ones, and the Quest Log window shows
## the quest at the same progress.
func _verify_mid() -> void:
	var mid: Dictionary = d.carry.get("mid", {})
	if mid.is_empty():
		return
	d.carry.erase("mid")
	var c := d.character()
	var qid := String(mid["quest"])
	var pq := (_pq(qid) if qid != "between" else []) + ["mechanic:quest-persistence"]
	var diff := PlaytestDriver.diff(mid["log"], c.quests.to_dict())
	d.check("%s: after Quit Game and a new process the quest log is the saved one (%s)" % [qid, mid["when"]], diff == "",
		diff, pq)
	d.check("%s: level, EXP, mesos and the bag survive the restart" % qid, c.level == int(mid["level"])
		and c.exp == int(mid["exp"]) and c.mesos == int(mid["mesos"]) and PlaytestDriver.diff(mid["bag"], k.snapshot()["bag"]) == "",
		"level %d/%d exp %d/%d mesos %d/%d bag %s" % [c.level, int(mid["level"]), c.exp, int(mid["exp"]), c.mesos,
			int(mid["mesos"]), PlaytestDriver.diff(mid["bag"], k.snapshot()["bag"])], pq)
	d.check("%s: Continue resumes in the map it was saved in (%s)" % [qid, mid["map"]], d.current_map() == String(mid["map"]),
		d.current_map(), pq)
	if qid != "between" and c.quests.is_in_progress(qid):
		var qw := await k.quest_window(qid, "in_progress")
		d.check("%s: the Quest Log still lists it In Progress (%s)" % [qid, PlaytestKit.rows_text(qw["rows"])], bool(qw["listed"]),
			"list %s" % [qw["list"]], pq + ["mechanic:quest-log"])
		await d.close_window("quests")


# --- results ----------------------------------------------------------------------------------------------------

## The per-quest verdict into d.carry["quest_results"] (scripts/playtest_quests.sh reads it): {id: {"result" (PASS |
## FAIL | NOT_PLAYED), "completed", "checks", "failed" [names], "warnings"}}.
func _results() -> void:
	var c := d.character()
	var out := {}
	for qid in ids:
		var key := "quest:" + qid
		var n := 0
		var failed := PackedStringArray()
		var warned := 0
		for ch: Dictionary in d.report.checks:
			if not (ch.get("parity", []) as Array).has(key):
				continue
			n += 1
			if not bool(ch["ok"]):
				if bool(ch.get("soft", false)):
					warned += 1
				else:
					failed.append(String(ch["name"]))
		var done := c.quests.is_completed(qid)
		out[qid] = {"result": "PASS" if done and failed.is_empty() and n > 0 else ("FAIL" if n > 0 else "NOT_PLAYED"),
			"completed": done, "checks": n, "failed": failed, "warnings": warned, "name": String((plans[qid] as Dictionary)["name"])}
	d.carry["quest_results"] = out
	for qid: String in out:
		d.note("QUEST %s %s: %s (%d checks, %d failed, %d warnings)" % [qid, out[qid]["name"], out[qid]["result"],
			int(out[qid]["checks"]), (out[qid]["failed"] as PackedStringArray).size(), int(out[qid]["warnings"])])


# --- helpers ----------------------------------------------------------------------------------------------------

static func _pq(qid: String) -> Array:
	return ["quest:" + qid]


## Dialogue text compared as the window shows it: whitespace collapsed.
static func _same_text(a: String, b: String) -> bool:
	var norm := func(s: String) -> String: return " ".join(s.strip_edges().split(" ", false)).replace("\n", " ")
	return b != "" and String(norm.call(a)) == String(norm.call(b))


func _kills_text(p: Dictionary) -> String:
	var parts := PackedStringArray()
	for kobj: Dictionary in p["kills"]:
		parts.append("%s x%d in %s" % [kobj["name"], int(kobj["count"]), kobj["hunt_map"]])
	return ", ".join(parts) if not parts.is_empty() else "-"


func _items_text(p: Dictionary) -> String:
	var parts := PackedStringArray()
	for iobj: Dictionary in p["items"]:
		var src: Dictionary = iobj.get("hunt", {})
		parts.append("%s x%d from %s" % [iobj["name"], int(iobj["count"]), "the accept" if bool(iobj["from_accept"]) else
			("%s %s in %s (chance %s)" % [src.get("kind", "?"), src.get("owner_name", "?"), src.get("map", "?"), src.get("chance")])])
	return ", ".join(parts) if not parts.is_empty() else "-"
