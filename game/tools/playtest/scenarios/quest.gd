extends PlaytestScenario
## quest: the every-quest real-game scenario (brief "Full Quest Playthrough Requirement"). One quest or one chain per
## run, chosen with --quest <spec> (or the QUEST environment variable): "1002", "1013-1019", "1006,1009,1010".
## scripts/playtest_quests.sh runs every chain of the canonical set (PlaytestQuestPlan.chains) and writes the
## per-quest table. Everything about a quest comes from PlaytestQuestPlan (canonical data): its NPCs and maps, level,
## prerequisites, objectives and where they are met, the quiz answers and the rewards. The play itself is
## PlaytestQuestRunner's (the clean-character playthrough plays its quests through the same runner).
##
## Phase 0 is the SETUP, the only place a console command may run (each is a logged console step): a new game
## through the real title and creation screens, a warp to the first quest's start map, the first quest's level and
## the prerequisite quests outside the chain (quest accept + quest complete force). Before the level is set, a
## level-gated quest is checked to be refused (no offer marker, the engine says unavailable). The pause menu saves
## and Quit Game ends the process. A chain that needs none of that setup (1000-1001: Heena stands in the creation map)
## turns strict mode on right after character creation instead.
## Phase 1 starts from that save (Continue) and turns STRICT mode on: from here no console command, no api fallback
## and no change to the character the event bus did not announce. Every quest of the chain is then PLAYED with real
## input: availability (the NPC's marker, the Quest Log's Available tab), the offer accepted in the dialogue, the
## accept items, objective progress (kills with the attack key, drops picked up with Z, Wooden Boxes broken, items
## used by double-click, quizzes answered in the menu, one wrong answer first), the turn-in, the exact canonical
## rewards (EXP, mesos, items, one item of each random group), and the follow-up's availability. A save and a
## process restart happen in the middle (mid-objective of each quest with objectives, after the accept of the first
## talk-only quest, and between two quests at the middle of a long chain); the next phase checks the progress survived.
## Every quest check carries the parity key quest:<id>; d.carry["quest_results"] is the per-quest verdict and
## d.carry["quest_evidence"] what each quest showed (PlaytestQuestSummary's per-quest report).

const WEAPON := "585"
const CHAR_NAME := "QuestRun"
## AP goes into the stats window in this order (a Wooden Club warrior's split, as test_c's hunter).
const AP_PLAN := ["str", "dex"]

var d: PlaytestDriver = null
var db: ContentDB = null
var k: PlaytestKit = null
var qr: PlaytestQuestRunner = null
var ids: PackedStringArray = []


func description() -> String:
	return "Every-quest set: one quest or chain (--quest / QUEST) played with real input from a setup save, strict after the setup"


## Game seconds per phase: a phase can hold two item hunts (ITEM_BUDGET_S each) and the walks between them.
func max_seconds() -> float:
	return 4800.0


func run(p_d: PlaytestDriver) -> void:
	d = p_d
	db = d.db()
	k = PlaytestKit.new(d)
	qr = PlaytestQuestRunner.new(d, k)
	qr.ap_plan = AP_PLAN
	qr.mid_reload_policy = "auto"
	var spec := _spec()
	ids = PlaytestQuestPlan.parse_ids(spec, db)
	if not d.check("--quest / QUEST names canonical quests ('%s')" % spec, not ids.is_empty(), "known: %s" % db.ids("quests")):
		return
	d.carry["quest_spec"] = spec
	var names := {}
	for id in ids:
		names[id] = String(qr.plan(id).get("name", id))
	# The quests' names for PlaytestQuestSummary, even when a run ends before its verdict.
	d.carry["quest_names"] = names
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
		var p := qr.plan(id)
		d.check("%s: a play plan from canonical data (%s)" % [id, p["name"]], bool(p["ok"]), "; ".join(p["blocked"]),
			PlaytestQuestRunner.pq_of(id))
		d.note("%s plan: start %s@%s, end %s@%s, level %d, prerequisites %s, kills %s, items %s, uses %s, quiz %s, rewards %s"
			% [id, p["start"]["npc_name"], p["start"]["map"], p["end"]["npc_name"], p["end"]["map"], int(p["min_level"]),
			p["prerequisites"], _kills_text(p), _items_text(p), p["uses"], (p["quiz"] as Dictionary).get("text", "-"), p["rewards"]])
	var setup := PlaytestQuestPlan.setup_for(ids, db)
	d.carry["setup"] = setup
	# A chain that needs no setup at all (its first quest starts in the creation map, at the creation level, with no
	# prerequisite) is strict from character creation: the run proves a console-free playthrough from the very start.
	if d.current_map() == String(setup["map"]) and int(setup["level"]) <= d.character().level \
			and (setup["complete"] as PackedStringArray).is_empty():
		d.begin_strict("after character creation")
	var first := ids[0]
	var fp := qr.plan(first)
	if d.current_map() != String(setup["map"]):
		await _setup_console("warp %s" % setup["map"])
	d.check("setup: in %s's start map %s" % [first, setup["map"]], d.current_map() == String(setup["map"]), d.current_map())
	if int(setup["level"]) > d.character().level:
		# The canonical level gate: below min_level the quest is not offered.
		var m := await k.marker(String(fp["start"]["npc"]))
		var engine := d.game().quests.engine
		var refused := not engine.is_available(first) and not qr.offers(m, first)
		d.check("%s is refused below its canonical level %d (level %d: no offer, the engine says unavailable)" % [first,
			int(setup["level"]), d.character().level], refused, "marker %s" % m, PlaytestQuestRunner.pq_of(first))
		var ev: Dictionary = d.carry.get("quest_evidence", {})
		var row: Dictionary = ev.get(first, {"quest": first, "name": String(fp["name"])})
		row["refused_below_level"] = d.character().level
		row["refused_ok"] = refused
		ev[first] = row
		d.carry["quest_evidence"] = ev
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
	await qr.verify_mid()
	var c := d.character()
	var stopped := ""
	for qid in ids:
		if c.quests.is_completed(qid):
			continue
		if c.quests.status(qid) == QuestLog.NOT_STARTED and not await qr.offer(qid):
			stopped = qid
			break
		if not await qr.objectives(qid):
			stopped = qid
			break
		if not await qr.turn_in(qid):
			stopped = qid
			break
		await qr.after(qid)
		await _maybe_reload_between(qid)
	if stopped != "":
		d.note("the chain stopped at %s" % stopped)
	k.checkpoint("end of %s" % ",".join(ids))
	d.note("travel %s; deaths %d; %d damage from %d touches; survival %s" % [k.travel_text(), k.deaths.size(),
		k.damage_taken, k.touches.size(), k.survival])
	qr.results(ids)


## At the middle of a chain of 3 or more, after quest floor(n / 2) (1006 of 1006,1009,1010; 1015 of 1013-1019): one
## more save and restart, between two quests.
func _maybe_reload_between(qid: String) -> void:
	if ids.size() < 3 or qid != ids[floori(ids.size() / 2.0) - 1] or (d.carry.get("reloaded", {}) as Dictionary).has("between"):
		return
	await qr.mid_reload("between", "after %s, the middle of the chain" % qid)


# --- helpers ----------------------------------------------------------------------------------------------------

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
