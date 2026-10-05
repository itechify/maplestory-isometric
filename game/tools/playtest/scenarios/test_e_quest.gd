extends PlaytestScenario
## test_e_quest: brief "Test E - Quest" (playtester play-E), played in the real main scene with real input, from a
## CLEAN save (a new game through the title and creation screens; no console EXP, items, quest or warp commands).
##
## Phase 0, character A: walks 000000001 -> 000000010 and does Roger's Apple (1002): Roger's marker, the quest card
## accepted with Y, the apple he hands over (MisoStory adaptation 1002.json) double-clicked in the inventory's Use
## tab, the turn-in, the canonical reward (none). Walks on to Snail Hunting Ground I (000000040): Sam's Suggestion
## (1006) is accepted from Sam, 10 Snails are killed with the attack key while the Quest Log window stays open (its
## objective row and the HUD log's counter line are read after every kill), the trails to A Split Road (000000050)
## are walked and the quest is turned in to Mai: the cumulative EXP must grow by exactly the canonical rewards.exp,
## the only EXP event must be "quest:1006" with that amount, the HUD log must show the EXP line, and the Egg count
## must grow by exactly the canonical count. Then the 1007 -> 1008 chain through dialogue: Maria's letter to Lucas in
## Amherst (000001010) and his reply back to Maria (+canonical EXP, one item of the canonical random group).
## Then Quit to Title and a second new game (character B, the next free slot): 1006 is accepted again and stopped
## halfway (5 of 10 Snails), saved through the pause menu, Quit to Title, Continue (progress must read 5/10), then
## Quit Game ends the process.
## Phase 1, a new process: Continue, progress 5/10 in the quest state, the save file on disk, the Quest Log window and
## Sam's marker; the other 5 Snails, the walk to Mai and the exact canonical reward again.
## NPC quest markers (available, in progress, completable) are read from the NPC presenters the HUD draws.

const START_MAP := "000000001"
const ROGER_MAP := "000000010"
const SAM_MAP := "000000040"
const MAI_MAP := "000000050"
const LUCAS_MAP := "000001010"
const ROGER := "3"
const SAM := "9"
const MARIA := "10"
const MAI := "11"
const LUCAS := "17"
const Q_APPLE := "1002"
const Q_SAM := "1006"
const Q_LETTER := "1007"
const Q_REPLY := "1008"
const WEAPON := "585"
const NAME_A := "QuestE"
const NAME_B := "QuestEtwo"
## The interruption: kills before the save (the brief's "halfway").
const HALF := 5
const HUNT_BUDGET_S := 420.0

var d: PlaytestDriver = null
var db: ContentDB = null
## [amount, source, game_s] for every Events.exp_gained this process heard.
var exp_log: Array = []
## [quest_id, kind, game_s] for quest_started / quest_progressed / quest_completed.
var quest_events: Array = []
var deaths: Array = []
var travel_rows: PackedStringArray = []
var fallbacks: PackedStringArray = []
var shots := 0
var damage_taken := 0
## "mob:damage@map" for every player_damaged.
var touches: PackedStringArray = []
## Set by _converse when a quest of its goals completes: the HUD log lines on screen right then.
var on_screen_at_complete: PackedStringArray = []


func description() -> String:
	return "Test E: Roger's Apple (1002), Sam's Suggestion (1006) twice (once straight, once with save / title / " \
		+ "continue / process restart at 5/10), Maria -> Lucas -> Maria (1007 -> 1008), exact canonical rewards"


func max_seconds() -> float:
	return 2400.0


func run(p_d: PlaytestDriver) -> void:
	d = p_d
	db = d.db()
	if d.phase == 0:
		await _phase0()
	else:
		await _phase1()


# =================================================================================================================
# Phase 0
# =================================================================================================================

func _phase0() -> void:
	var ng: Dictionary = await d.new_game(NAME_A, "female", WEAPON)
	if not d.check("A: new game through the title and creation screens (clean save)", bool(ng["ok"]) and ng["via"] == "screen",
			"%s in %s via %s %s" % [ng["slot"], ng["map"], ng["via"], ng["why"]]):
		return
	_connect_bus()
	var c := d.character()
	d.check("A: a clean character: level 1, 0 EXP, no quest started or completed, empty bag",
		c.level == 1 and c.exp == 0 and c.quests.active_ids().is_empty() and c.quests.completed_ids().is_empty()
		and c.inventory.is_empty() and d.current_map() == START_MAP,
		"level %d exp %d active %s completed %s map %s" % [c.level, c.exp, c.quests.active_ids(), c.quests.completed_ids(),
			d.current_map()])
	d.carry["slot_a"] = String(ng["slot"])

	# --- Roger's Apple (1002) -----------------------------------------------------------------------------------
	if not await _travel(ROGER_MAP):
		return
	await _roger()

	# --- Sam's Suggestion (1006), straight through ---------------------------------------------------------------
	if not await _travel(SAM_MAP):
		return
	if not await _accept_sam("A"):
		return
	await _hunt_sam("A", _kill_req(Q_SAM), true)
	await _finish_sam("A")

	# --- Letter for Lucas (1007) -> Lucas's Reply (1008) ------------------------------------------------------------
	await _letter_chain()

	# --- Character B: 1006 with the interruption --------------------------------------------------------------------
	d.note("A: travel %s; fallbacks %s; deaths %s; %d damage from %d touches" % [", ".join(travel_rows), fallbacks, deaths, damage_taken, touches.size()])
	# B's notes start empty.
	travel_rows.clear()
	fallbacks.clear()
	deaths.clear()
	touches.clear()
	damage_taken = 0
	var q: Dictionary = await d.quit_to_title()
	if not d.check("A: Quit to Title through the pause menu", bool(q["ok"]) and q["via"] == "screen", str(q)):
		return
	var ng2: Dictionary = await d.new_game(NAME_B, "male", WEAPON)
	if not d.check("B: a second new game from the title (clean character, next free slot)", bool(ng2["ok"])
			and ng2["via"] == "screen" and String(ng2["slot"]) != String(d.carry["slot_a"]),
			"%s (A was %s) in %s via %s %s" % [ng2["slot"], d.carry["slot_a"], ng2["map"], ng2["via"], ng2["why"]]):
		return
	c = d.character()
	d.check("B: clean: level 1, 0 EXP, no quests", c.name == NAME_B and c.level == 1 and c.exp == 0
		and c.quests.active_ids().is_empty() and c.quests.completed_ids().is_empty(),
		"%s level %d exp %d active %s completed %s" % [c.name, c.level, c.exp, c.quests.active_ids(), c.quests.completed_ids()])
	d.carry["slot_b"] = String(ng2["slot"])
	if not await _travel(SAM_MAP):
		return
	if not await _accept_sam("B"):
		return
	await _hunt_sam("B", HALF, true)
	var k := c.quests.kills(Q_SAM, _mob(Q_SAM))
	d.check("B: progress stopped halfway at %d/%d" % [HALF, _kill_req(Q_SAM)], k == HALF, "%d kills counted" % k)
	var before := _quest_snapshot()

	var saved: Dictionary = await d.save_game()
	d.check("B: the pause menu's Save writes the slot mid-quest", bool(saved["ok"]) and saved["via"] == "screen"
		and String(saved["slot"]) == String(d.carry["slot_b"]), "%s '%s' via %s" % [saved["slot"], saved["status"], saved["via"]])
	var disk := _disk_quest(String(d.carry["slot_b"]))
	d.check("B: the save file on disk holds 1006 in progress at %d kills" % k, String(disk.get("status", "")) == "in_progress"
		and _disk_kills(disk) == k, "%s" % str(disk).left(240))
	var q2: Dictionary = await d.quit_to_title()
	if not d.check("B: Quit to Title mid-quest", bool(q2["ok"]) and q2["via"] == "screen", str(q2)):
		return
	var cont: Dictionary = await d.continue_game()
	if not d.check("B: Continue from the title loads B", bool(cont["ok"]) and cont["via"] == "screen"
			and String(cont["slot"]) == String(d.carry["slot_b"]) and d.character().name == NAME_B,
			"%s in %s via %s, %s" % [cont["slot"], cont["map"], cont["via"], d.character().name]):
		return
	await _verify_resumed("B after Quit to Title + Continue", before)
	await _shot("b_questlog_after_continue")
	d.carry["b_before"] = before
	d.note("B: travel %s; fallbacks %s; deaths %s; %d damage from %d touches" % [", ".join(travel_rows), fallbacks, deaths, damage_taken, touches.size()])
	await d.reload_process()


# =================================================================================================================
# Phase 1: a new process on the same saves
# =================================================================================================================

func _phase1() -> void:
	var cont: Dictionary = await d.continue_game()
	if not d.check("B: Continue in a new process loads B", bool(cont["ok"]) and cont["via"] == "screen"
			and String(cont["slot"]) == String(d.carry.get("slot_b", "")) and d.character().name == NAME_B,
			"%s in %s via %s, %s" % [cont["slot"], cont["map"], cont["via"], d.character().name]):
		return
	_connect_bus()
	var before: Dictionary = d.carry.get("b_before", {})
	var disk := _disk_quest(String(d.carry["slot_b"]))
	d.check("B: after the process restart the save file still holds %d kills" % int(before.get("kills", -1)),
		_disk_kills(disk) == int(before.get("kills", -2)), str(disk).left(240))
	await _verify_resumed("B after Quit Game + a new process + Continue", before)
	await _shot("b_questlog_after_restart")
	if d.current_map() != SAM_MAP and not await _travel(SAM_MAP):
		return
	await _hunt_sam("B", _kill_req(Q_SAM), true)
	await _finish_sam("B")
	d.note("B (phase 1): travel %s; fallbacks %s; deaths %s; %d damage from %d touches" % [", ".join(travel_rows), fallbacks, deaths, damage_taken, touches.size()])
	await _shot("b_done")


# =================================================================================================================
# Roger's Apple (1002)
# =================================================================================================================

func _roger() -> void:
	var c := d.character()
	var qrec := db.quest(Q_APPLE)
	var qname := String(qrec.get("name", Q_APPLE))
	await _approach(ROGER)
	var m0 := await _marker(ROGER)
	d.check("Roger's marker reads 'available' before 1002 (gold !)", m0["state"] == "available" and m0["engine"] == "available",
		str(m0))
	await _shot("roger_available")
	# The apple Roger hands over: MisoStory adaptation data/misostory/quests/1002.json accept_items (MeowDB lists none).
	var adapt := db.miso_entity("quests", Q_APPLE)
	var accept_items: Array = adapt.get("accept_items", [])
	var apple := String((accept_items[0] as Dictionary).get("item_id", "")) if not accept_items.is_empty() else ""
	var apple_n := int((accept_items[0] as Dictionary).get("count", 0)) if not accept_items.is_empty() else 0
	var use_obj: Array = (qrec.get("objectives", {}) as Dictionary).get("item_usage", [])
	var use_id := String((use_obj[0] as Dictionary).get("item_id", "")) if not use_obj.is_empty() else ""
	var use_n := int((use_obj[0] as Dictionary).get("count", 0)) if not use_obj.is_empty() else 0
	d.check("1002 data: the apple handed over is the item the usage objective needs", apple != "" and apple == use_id
		and apple_n >= use_n, "accept %s x%d, objective use %s x%d" % [apple, apple_n, use_id, use_n])

	var clock0 := _log_clock()
	var talk: Dictionary = await _talk(ROGER)
	if not d.check("Roger can be talked to on foot (the round-4 garden steps)", bool(talk["open"]),
			"gap %s: %s" % [talk.get("talk_gap", "-"), talk.get("why", "")]):
		return
	var card := String(talk.get("text", ""))
	var conv: Dictionary = await _converse({Q_APPLE: "accept"})
	d.note("Roger accept pages: %s" % " | ".join(conv["pages"]))
	d.check("1002 offered as a quest card (journal summary + 'Accept this quest?') and accepted with Y",
		c.quests.is_in_progress(Q_APPLE) and card.contains(String((qrec.get("journal", {}) as Dictionary).get("summary", "@@"))),
		"status %s, card '%s'" % [c.quests.status(Q_APPLE), card.left(120)])
	d.check("Roger handed over %d x %s on accepting" % [apple_n, _item_name(apple)], c.inventory.count(apple) == apple_n,
		"count %d" % c.inventory.count(apple))
	var lines := _log_since(clock0)
	var want_item := MisoUiText.item_gained_line(_item_name(apple), apple_n)
	d.check("the HUD log says '%s' and 'Quest started: %s'" % [want_item, qname], want_item in lines
		and ("Quest started: %s" % qname) in lines, " / ".join(lines))
	d.check("the accept banner names the quest and the item", _any_contains(conv["banners"], "Quest accepted: %s" % qname),
		" / ".join(conv["banners"]))
	var m1 := await _marker(ROGER)
	d.check("Roger's marker reads 'in_progress' after the accept (grey ...)", m1["state"] == "in_progress", str(m1))
	var qw := await _quest_window(Q_APPLE, "in_progress")
	var want_row := "Use %s 0/%d" % [String((use_obj[0] as Dictionary).get("name", "")), use_n]
	d.check("the Quest Log lists 1002 In Progress with '%s'" % want_row, bool(qw["listed"]) and _row_has(qw["rows"], want_row, false),
		_rows_text(qw["rows"]))
	await d.close_window("quests")

	# --- Eat the apple: Use tab, double-click --------------------------------------------------------------------
	var hp0 := c.hp
	var clock_use := _log_clock()
	var used: Dictionary = await _use_by_double_click(apple)
	var restore := int((db.item(apple).get("consumable", {}) as Dictionary).get("hp_restore", 0))
	var max_hp := StatCalculator.max_hp(c, db)
	d.check("double-clicking %s in the Use tab eats it: count %d -> %d, HP %d -> min(Max HP %d, +%d)" % [_item_name(apple),
		apple_n, apple_n - 1, hp0, max_hp, restore], bool(used["ok"]) and c.inventory.count(apple) == apple_n - 1
		and c.hp == mini(max_hp, hp0 + restore), "count %d, HP %d, status '%s'" % [c.inventory.count(apple), c.hp, used["status"]])
	d.check("the usage objective counts it (%d/%d)" % [use_n, use_n], c.quests.uses(Q_APPLE, apple) == use_n,
		"uses %d" % c.quests.uses(Q_APPLE, apple))
	var use_line := "%s: Use %s %d/%d" % [qname, String((use_obj[0] as Dictionary).get("name", "")), use_n, use_n]
	var use_lines := _log_since(clock_use)
	d.check("the HUD log counts the use: '%s'" % use_line, use_line in use_lines, " / ".join(use_lines))
	var m2 := await _marker(ROGER)
	d.check("Roger's marker reads 'completable' once the apple is eaten (green ?)", m2["state"] == "completable", str(m2))
	await _shot("roger_completable")

	# --- Turn in --------------------------------------------------------------------------------------------------
	talk = await _talk(ROGER)
	if not d.check("Roger can be talked to again for the turn-in", bool(talk["open"]), str(talk.get("why", ""))):
		return
	var snap: Dictionary = talk["pre"]
	var t0 := float(snap["t"])
	clock0 = float(snap["clock"])
	conv = await _converse({Q_APPLE: "complete"})
	d.note("Roger turn-in pages: %s" % " | ".join(conv["pages"]))
	await d.wait(0.3)
	var rew := qrec.get("rewards", {}) as Dictionary
	var after := _snapshot()
	d.check("1002 completed at Roger", c.quests.is_completed(Q_APPLE), c.quests.status(Q_APPLE))
	d.check("1002's canonical reward exactly: EXP +%d, mesos +%d, no items" % [int(rew.get("exp", 0)), int(rew.get("mesos", 0))],
		int(after["total_exp"]) - int(snap["total_exp"]) == int(rew.get("exp", 0))
		and int(after["mesos"]) - int(snap["mesos"]) == int(rew.get("mesos", 0))
		and PlaytestDriver.diff(snap["bag"], after["bag"]) == "" and (rew.get("items", []) as Array).is_empty()
		and _exp_since(t0).is_empty() == (int(rew.get("exp", 0)) == 0),
		"EXP %d -> %d, mesos %d -> %d, bag diff '%s', exp events %s" % [snap["total_exp"], after["total_exp"], snap["mesos"],
			after["mesos"], PlaytestDriver.diff(snap["bag"], after["bag"]), _exp_since(t0)])
	lines = _log_since(clock0)
	d.check("the HUD log says 'Quest complete: %s'" % qname, ("Quest complete: %s" % qname) in lines, " / ".join(lines))
	var m3 := await _marker(ROGER)
	d.check("Roger's marker is gone once 1002 is completed (he has no other quest)", m3["state"] == "", str(m3))


# =================================================================================================================
# Sam's Suggestion (1006)
# =================================================================================================================

func _accept_sam(who: String) -> bool:
	var c := d.character()
	var qname := _qname(Q_SAM)
	await _approach(SAM)
	var m0 := await _marker(SAM)
	d.check("%s: Sam's marker reads 'available' before 1006" % who, m0["state"] == "available", str(m0))
	if who == "A":
		await _shot("sam_available")
		var avail := await _quest_window(Q_SAM, "available")
		d.check("A: the Quest Log's Available tab lists 1006 before the accept", bool(avail["listed"]),
			"tab '%s', list %s" % [avail["tab_text"], avail["list"]])
		d.soft_check("A: the Available tab marks 1006 '[nearby]' while standing in Sam's map (quest_window.gd docs)",
			_any_contains(avail["list"], "[nearby]"), "list %s; Sam's canonical map %s, current %s" % [avail["list"],
				SAM_MAP, d.current_map()])
		await d.close_window("quests")
	var clock0 := _log_clock()
	var talk: Dictionary = await _talk(SAM)
	if not d.check("%s: Sam can be talked to on foot" % who, bool(talk["open"]), str(talk.get("why", ""))):
		return false
	var conv: Dictionary = await _converse({Q_SAM: "accept"})
	d.note("%s: Sam accept pages: %s" % [who, " | ".join(conv["pages"])])
	if not d.check("%s: 1006 accepted through Sam's dialogue (Yes)" % who, c.quests.is_in_progress(Q_SAM),
			c.quests.status(Q_SAM)):
		return false
	var lines := _log_since(clock0)
	d.check("%s: the HUD log says 'Quest started: %s'" % [who, qname], ("Quest started: %s" % qname) in lines, " / ".join(lines))
	var m1 := await _marker(SAM)
	d.check("%s: Sam's marker reads 'in_progress' after the accept (1006 ends at Mai)" % who, m1["state"] == "in_progress", str(m1))
	var qw := await _quest_window(Q_SAM, "in_progress")
	var want := _kill_row(0)
	d.check("%s: the Quest Log shows 1006 In Progress with '%s' and 'Return to Mai'" % [who, want], bool(qw["listed"])
		and _row_has(qw["rows"], want, false) and _row_has(qw["rows"], "Return to %s" % _npc_name(MAI), false),
		_rows_text(qw["rows"]))
	if who == "A":
		await _shot("questlog_0_of_10")
	return true


## Kills Snails with the attack key until 1006 counts `target`. With the Quest Log open, its objective row is read
## after every kill; the HUD log's "<quest>: Snail k/10" line too.
func _hunt_sam(who: String, target: int, watch: bool) -> void:
	var c := d.character()
	var mob := _mob(Q_SAM)
	var start := c.quests.kills(Q_SAM, mob)
	var clock0 := _log_clock()
	if watch:
		await _quest_window(Q_SAM, "in_progress")
	var wr := d.windows() as MisoWindowsRoot
	var seen: PackedStringArray = []
	var bad: PackedStringArray = []
	var exclude := {}
	var fails := 0
	var t0 := d.game_s()
	var last_k := start
	var jumps: PackedStringArray = []
	while c.quests.kills(Q_SAM, mob) < target and d.game_s() - t0 < HUNT_BUDGET_S:
		if _dead():
			await _respawn()
			continue
		if d.current_map() != SAM_MAP:
			if not await _travel(SAM_MAP):
				break
			if watch:
				await _quest_window(Q_SAM, "in_progress")
			continue
		var o := {"mob_id": mob, "exclude": exclude, "max_dist_m": 80.0}
		var tgt := d.nearest_monster(o)
		if tgt == null:
			await d.wait(1.0)
			continue
		var r: Dictionary = await d.face_and_attack_nearest(20.0, o)
		# The window is read after every fight: a kill whose hit resolves after the fight returned is counted then.
		await d.frames(3)
		var k1 := c.quests.kills(Q_SAM, mob)
		if k1 != last_k:
			if k1 != last_k + 1:
				jumps.append("%d -> %d" % [last_k, k1])
			last_k = k1
			if watch and bool(wr.call("is_open", "quests")):
				var shown := _rows_text(wr.quests.objective_rows())
				seen.append("%d:%s" % [k1, shown.get_slice(";", 0)])
				if not _row_has(wr.quests.objective_rows(), _kill_row(k1), k1 >= _kill_req(Q_SAM)):
					bad.append("at %d kills the window shows '%s'" % [k1, shown])
			elif watch:
				bad.append("the Quest Log closed itself at %d kills" % k1)
		if bool(r["ok"]):
			fails = 0
		else:
			fails += 1
			if is_instance_valid(tgt) and String(r["why"]).begins_with("could not reach"):
				exclude[tgt.get_instance_id()] = true
			if fails >= 4:
				fails = 0
				exclude.clear()
				await d.walk_to("spawn:0", {"max_s": 20.0})
	var end := c.quests.kills(Q_SAM, mob)
	d.check("%s: %d Snails killed with the attack key: 1006 counts %d -> %d (target %d)" % [who, end - start, start, end, target],
		end == target, "%.0f s; count steps of more than one between two reads: %s" % [d.game_s() - t0, jumps])
	if watch:
		d.check("%s: the open Quest Log's objective row followed every kill (%d reads)" % [who, seen.size()],
			bad.is_empty() and not seen.is_empty() and last_k == end, "%s; %s" % [", ".join(seen), ", ".join(bad)])
		await d.close_window("quests")
	# The HUD log: one "<quest>: Snail k/10" line per kill, in order.
	var lines := _log_since(clock0)
	var missing: PackedStringArray = []
	var at := -1
	for k in range(start + 1, end + 1):
		var want := "%s: %s" % [_qname(Q_SAM), _kill_row(k)]
		var idx := lines.find(want, at + 1)
		if idx < 0:
			missing.append(want)
		else:
			at = idx
	d.check("%s: the HUD log counted every kill in order ('%s: %s' .. '%s')" % [who, _qname(Q_SAM), _kill_row(start + 1),
		_kill_row(end)], missing.is_empty() and end > start, "missing %s; quest lines %s" % [missing, _quest_lines(lines)])
	d.note("%s: hunt %d -> %d in %.0f s, window reads %s" % [who, start, end, d.game_s() - t0, ", ".join(seen)])


func _finish_sam(who: String) -> void:
	var c := d.character()
	var qrec := db.quest(Q_SAM)
	var rew := qrec.get("rewards", {}) as Dictionary
	var reward_exp := int(rew.get("exp", 0))
	var reward_items: Array = rew.get("items", [])
	var qname := _qname(Q_SAM)
	var qw := await _quest_window(Q_SAM, "in_progress")
	d.check("%s: the Quest Log shows 1006 '[ready]' with '%s' ticked" % [who, _kill_row(_kill_req(Q_SAM))],
		_any_contains(qw["list"], "[ready]") and _row_has(qw["rows"], _kill_row(_kill_req(Q_SAM)), true)
		and _any_contains(qw["detail"], "Ready to turn in"), "list %s rows %s" % [qw["list"], _rows_text(qw["rows"])])
	await d.close_window("quests")
	if not await _travel(MAI_MAP):
		return
	await _approach(MAI)
	var m0 := await _marker(MAI)
	d.check("%s: Mai's marker reads 'completable' (green ?) with 1006 ready" % who, m0["state"] == "completable", str(m0))
	if who == "A":
		await _shot("mai_completable")
	var talk: Dictionary = await _talk(MAI)
	if not d.check("%s: Mai can be talked to on foot" % who, bool(talk["open"]), str(talk.get("why", ""))):
		return
	# The baseline: right before the approach that opened the chat (_talk).
	var snap: Dictionary = talk["pre"]
	var t0 := float(snap["t"])
	var clock0 := float(snap["clock"])
	var n0 := int(snap["notices"])
	var conv: Dictionary = await _converse({Q_SAM: "complete"}, who == "A")
	d.note("%s: Mai turn-in pages: %s" % [who, " | ".join(conv["pages"])])
	await d.wait(0.3)
	var after := _snapshot()
	var events := _exp_since(t0)
	d.check("%s: 1006 completed at Mai" % who, c.quests.is_completed(Q_SAM), c.quests.status(Q_SAM))
	var dexp := int(after["total_exp"]) - int(snap["total_exp"])
	d.check("%s: EXP delta is exactly the canonical rewards.exp %d (cumulative over levels)" % [who, reward_exp],
		dexp == reward_exp and events.size() == 1 and int(events[0][0]) == reward_exp and String(events[0][1]) == "quest:" + Q_SAM,
		"total EXP %d -> %d (+%d); level %d -> %d, exp %d -> %d; exp events %s" % [snap["total_exp"], after["total_exp"], dexp,
			snap["level"], after["level"], snap["exp"], after["exp"], events])
	var item_txt: PackedStringArray = []
	var items_ok := true
	for it: Dictionary in reward_items:
		var id := String(it.get("item_id", ""))
		var n := int(it.get("count", 0))
		var got := c.inventory.count(id) - int((snap["counts"] as Dictionary).get(id, _count_in(snap["bag"], id)))
		items_ok = items_ok and got == n
		item_txt.append("%s %s: %+d (canonical %d)" % [id, _item_name(id), got, n])
	var others := _bag_delta(snap["bag"], after["bag"], reward_items)
	d.check("%s: exactly the canonical reward items, nothing else: %s" % [who, ", ".join(item_txt)],
		items_ok and not reward_items.is_empty() and others.is_empty() and int(after["mesos"]) == int(snap["mesos"]) + int(rew.get("mesos", 0)),
		"%s; other bag changes %s; mesos %d -> %d" % [", ".join(item_txt), others, snap["mesos"], after["mesos"]])
	var lines := _log_since(clock0)
	var want_exp := MisoUiText.exp_gained_line(reward_exp)
	d.check("%s: the HUD log shows '%s'" % [who, want_exp], want_exp in lines, " / ".join(lines))
	d.check("%s: and that line is on screen when the quest completes" % who, want_exp in on_screen_at_complete,
		" / ".join(on_screen_at_complete))
	for it: Dictionary in reward_items:
		var want_it := MisoUiText.item_gained_line(_item_name(String(it.get("item_id", ""))), int(it.get("count", 1)))
		d.check("%s: the HUD log shows '%s'" % [who, want_it], want_it in lines, " / ".join(lines))
	d.check("%s: the HUD log shows 'Quest complete: %s'" % [who, qname], ("Quest complete: %s" % qname) in lines, " / ".join(lines))
	var shown_banner := " / ".join(conv["banners"]) + " / " + " / ".join(Array(d.notices).slice(n0))
	d.check("%s: the dialogue's completion banner names +%d EXP and the items" % [who, reward_exp],
		shown_banner.contains("Quest complete: %s" % qname) and shown_banner.contains("+%d EXP" % reward_exp)
		and (reward_items.is_empty() or shown_banner.contains(_item_name(String((reward_items[0] as Dictionary).get("item_id", ""))))),
		shown_banner)
	var done := await _quest_window(Q_SAM, "completed")
	d.check("%s: the Quest Log's Completed tab lists 1006 as Completed" % who, bool(done["listed"])
		and _any_contains(done["detail"], "Completed"), "tab '%s' list %s detail %s" % [done["tab_text"], done["list"],
			" / ".join(done["detail"]).left(200)])
	if who == "A":
		await _shot("questlog_completed")
	await d.close_window("quests")
	var m1 := await _marker(MAI)
	var engine := d.game().quests.engine
	var next_avail := false
	for qid in engine.catalog.started_by(MAI):
		next_avail = next_avail or engine.is_available(qid)
	d.check("%s: Mai's marker after 1006: '%s' (her own quests %s, level %d)" % [who, "available" if next_avail else "",
		engine.catalog.started_by(MAI), c.level], m1["state"] == ("available" if next_avail else ""), str(m1))


# =================================================================================================================
# 1007 -> 1008: Maria's letter to Lucas, his reply back
# =================================================================================================================

func _letter_chain() -> void:
	var c := d.character()
	var q7 := db.quest(Q_LETTER)
	var q8 := db.quest(Q_REPLY)
	if c.level < int(q7.get("min_level", 0)):
		d.soft_check("A: level %d reaches 1007's canonical min_level %d for the letter chain" % [c.level, int(q7.get("min_level", 0))],
			false, "skipping 1007 -> 1008")
		return
	if d.current_map() != MAI_MAP and not await _travel(MAI_MAP):
		return
	var letter := String(((q7.get("items_given_on_accept", []) as Array)[0] as Dictionary).get("item_id", ""))
	await _approach(MARIA)
	var m0 := await _marker(MARIA)
	d.check("Maria's marker reads 'available' (1007)", m0["state"] == "available", str(m0))
	var talk: Dictionary = await _talk(MARIA)
	if not d.check("Maria can be talked to on foot", bool(talk["open"]), str(talk.get("why", ""))):
		return
	var conv: Dictionary = await _converse({Q_LETTER: "accept"})
	d.note("Maria accept pages: %s" % " | ".join(conv["pages"]))
	d.check("1007 accepted from Maria: %s x1 handed over (canonical items_given_on_accept)" % _item_name(letter),
		c.quests.is_in_progress(Q_LETTER) and c.inventory.count(letter) == 1, "status %s, %s x%d" % [c.quests.status(Q_LETTER),
			letter, c.inventory.count(letter)])
	var m1 := await _marker(MARIA)
	d.check("Maria's marker reads 'in_progress' (1007 ends at Lucas)", m1["state"] == "in_progress", str(m1))
	if not await _travel(LUCAS_MAP):
		return
	await _approach(LUCAS)
	var m2 := await _marker(LUCAS)
	d.check("Lucas's marker reads 'completable' with the letter", m2["state"] == "completable", str(m2))
	var reply := String(((q8.get("items_given_on_accept", []) as Array)[0] as Dictionary).get("item_id", "")) \
		if not (q8.get("items_given_on_accept", []) as Array).is_empty() else ""
	talk = await _talk(LUCAS)
	if not d.check("Lucas can be talked to on foot", bool(talk["open"]), str(talk.get("why", ""))):
		return
	var snap: Dictionary = talk["pre"]
	var t0 := float(snap["t"])
	conv = await _converse({Q_LETTER: "complete", Q_REPLY: "accept"})
	d.note("Lucas pages: %s" % " | ".join(conv["pages"]))
	var r7 := q7.get("rewards", {}) as Dictionary
	var a7 := _snapshot()
	d.check("1007 completed at Lucas: the letter handed in, canonical EXP +%d" % int(r7.get("exp", 0)),
		c.quests.is_completed(Q_LETTER) and c.inventory.count(letter) == 0
		and int(a7["total_exp"]) - int(snap["total_exp"]) == int(r7.get("exp", 0)),
		"status %s, %s x%d, EXP %+d, events %s" % [c.quests.status(Q_LETTER), letter, c.inventory.count(letter),
			int(a7["total_exp"]) - int(snap["total_exp"]), _exp_since(t0)])
	d.check("1008 accepted from Lucas in the same conversation: %s x1" % _item_name(reply), c.quests.is_in_progress(Q_REPLY)
		and reply != "" and c.inventory.count(reply) == 1, "status %s, %s x%d" % [c.quests.status(Q_REPLY), reply,
			c.inventory.count(reply)])
	if not await _travel(MAI_MAP):
		return
	await _approach(MARIA)
	var m3 := await _marker(MARIA)
	d.check("Maria's marker reads 'completable' with Lucas's reply", m3["state"] == "completable", str(m3))
	talk = await _talk(MARIA)
	if not d.check("Maria can be talked to again", bool(talk["open"]), str(talk.get("why", ""))):
		return
	snap = talk["pre"]
	t0 = float(snap["t"])
	var clock0 := float(snap["clock"])
	conv = await _converse({Q_REPLY: "complete"})
	d.note("Maria turn-in pages: %s" % " | ".join(conv["pages"]))
	await d.wait(0.3)
	var after := _snapshot()
	var r8 := q8.get("rewards", {}) as Dictionary
	var group: Array = []
	for g: Dictionary in r8.get("random", []):
		for it: Dictionary in g.get("items", []):
			group.append(String(it.get("item_id", "")))
	var gained := _bag_delta(snap["bag"], after["bag"], [])
	var hats: PackedStringArray = []
	var other: PackedStringArray = []
	for id: String in gained:
		var n := int(gained[id])
		if id in group and n == 1:
			hats.append(id)
		elif not (id == reply and n == -1):
			other.append("%s %+d" % [id, n])
	var dexp := int(after["total_exp"]) - int(snap["total_exp"])
	var ev := _exp_since(t0)
	d.check("1008 completed at Maria: the reply handed in, EXP exactly +%d (canonical), one item of the random group" % int(r8.get("exp", 0)),
		c.quests.is_completed(Q_REPLY) and c.inventory.count(reply) == 0 and dexp == int(r8.get("exp", 0))
		and ev.size() == 1 and int(ev[0][0]) == int(r8.get("exp", 0)) and hats.size() == 1 and other.is_empty(),
		"status %s, reply x%d, EXP %+d events %s, won %s (%s), other %s; group %s" % [c.quests.status(Q_REPLY), c.inventory.count(reply),
			dexp, ev, hats, _item_name(hats[0]) if not hats.is_empty() else "-", other, group])
	var lines := _log_since(clock0)
	d.check("the HUD log shows '%s' for 1008" % MisoUiText.exp_gained_line(int(r8.get("exp", 0))),
		MisoUiText.exp_gained_line(int(r8.get("exp", 0))) in lines, " / ".join(lines))
	var m4 := await _marker(MARIA)
	d.check("Maria's marker is gone after 1008", m4["state"] == "", str(m4))


# =================================================================================================================
# Resume checks
# =================================================================================================================

## The quest state a reload must keep.
func _quest_snapshot() -> Dictionary:
	var c := d.character()
	return {"kills": c.quests.kills(Q_SAM, _mob(Q_SAM)), "status": c.quests.status(Q_SAM), "level": c.level, "exp": c.exp,
		"map": d.current_map(), "name": c.name, "log": c.quests.to_dict()}


func _verify_resumed(when: String, before: Dictionary) -> void:
	var c := d.character()
	var k := c.quests.kills(Q_SAM, _mob(Q_SAM))
	d.check("%s: 1006 still in progress at %d/%d" % [when, int(before.get("kills", -1)), _kill_req(Q_SAM)],
		c.quests.is_in_progress(Q_SAM) and k == int(before.get("kills", -1)) and c.name == String(before.get("name", "")),
		"status %s kills %d, %s" % [c.quests.status(Q_SAM), k, c.name])
	var diff := PlaytestDriver.diff(before.get("log", {}), c.quests.to_dict())
	d.check("%s: the whole quest log is the saved one" % when, diff == "", diff)
	d.check("%s: level and EXP kept" % when, c.level == int(before.get("level", -1)) and c.exp == int(before.get("exp", -1)),
		"level %d exp %d (saved %s / %s)" % [c.level, c.exp, before.get("level"), before.get("exp")])
	var qw := await _quest_window(Q_SAM, "in_progress")
	d.check("%s: the Quest Log shows '%s'" % [when, _kill_row(k)], bool(qw["listed"]) and _row_has(qw["rows"], _kill_row(k), false),
		_rows_text(qw["rows"]))
	if d.current_map() == SAM_MAP:
		var m := await _marker(SAM)
		d.check("%s: Sam's marker still reads 'in_progress'" % when, m["state"] == "in_progress", str(m))


# =================================================================================================================
# Conversation
# =================================================================================================================

## Plays the open conversation with the window's keys. goals: quest id -> "accept" | "complete". A menu picks the
## entry of a goal not met yet (else End Chat); a Yes/No answers Y only for a goal "accept" of a quest not started; a
## line is paged with Enter. Returns {"pages", "banners"}.
func _converse(goals: Dictionary, shot_on_complete: bool = false) -> Dictionary:
	var c := d.character()
	var pages: PackedStringArray = []
	var banners: PackedStringArray = []
	var guard := 0
	var done_before := {}
	for qid: String in goals:
		done_before[qid] = c.quests.is_completed(qid)
	var v := d.read_dialogue()
	while bool(v["open"]) and guard < 40:
		guard += 1
		var view: Dictionary = v["view"]
		var node := String(view.get("node_id", ""))
		var t := String(v["type"])
		var b := String(v.get("banner", ""))
		if b != "" and (banners.is_empty() or banners[banners.size() - 1] != b):
			banners.append(b)
		pages.append("%s[%s] %s" % [node, t, String(v.get("text", "")).replace("\n", " ").left(70)])
		for qid: String in goals:
			if not bool(done_before[qid]) and c.quests.is_completed(qid) and on_screen_at_complete.is_empty():
				on_screen_at_complete = _log_on_screen()
				if shot_on_complete:
					await _shot("reward_%s" % qid)
		if t == "menu":
			var pick := -1
			var choices: Array = view.get("choices", [])
			for k in choices.size():
				var qid := String((choices[k] as Dictionary).get("quest_id", ""))
				if goals.has(qid) and not _goal_met(qid, String(goals[qid])):
					pick = k
					break
			if pick < 0:
				v = await d.choose("end")
				break
			v = await d.choose(pick)
		elif t == "yes_no":
			var qid := _node_quest(node)
			var yes := String(goals.get(qid, "")) == "accept" and c.quests.status(qid) == QuestLog.NOT_STARTED
			v = await d.choose("yes" if yes else "no")
		elif "next" in v["buttons"] or "ok" in v["buttons"]:
			v = await d.next()
		else:
			break
	for qid: String in goals:
		if not bool(done_before[qid]) and c.quests.is_completed(qid) and on_screen_at_complete.is_empty():
			on_screen_at_complete = _log_on_screen()
	if d.dialogue_open():
		await d.close_dialogue()
	await d.frames(2)
	return {"pages": pages, "banners": banners}


func _goal_met(qid: String, goal: String) -> bool:
	var c := d.character()
	if goal == "accept":
		return c.quests.status(qid) != QuestLog.NOT_STARTED
	return c.quests.is_completed(qid)


static func _node_quest(node: String) -> String:
	if not node.begins_with("q"):
		return ""
	return node.substr(1).get_slice(".", 0)


# =================================================================================================================
# Windows, HUD, markers
# =================================================================================================================

## The quest marker the HUD draws over an NPC (its NpcPresenter's QuestMarker), after its own refresh tick, and the
## engine's answer for comparison.
func _marker(npc_id: String) -> Dictionary:
	await d.wait(0.5)
	var inter := d.interaction()
	var pres: Dictionary = inter.get("presenters") if inter != null else {}
	var p: Variant = pres.get(npc_id)
	var out := {"npc": npc_id, "state": "(no presenter)", "visible": false, "engine": d.game().npc_talk.marker(npc_id)}
	if p is NpcPresenter and is_instance_valid(p):
		var mk := (p as NpcPresenter).marker
		if mk != null and is_instance_valid(mk):
			out["state"] = mk.state
			out["visible"] = mk.visible
		var npc := (p as NpcPresenter).npc
		if npc != null and is_instance_valid(npc) and d.player() != null:
			out["dist_m"] = snappedf(npc.global_position.distance_to(d.player().global_position), 0.01)
	# Windowed, a marker with a state over an NPC the player stands next to must be drawn.
	if DisplayServer.get_name() != "headless" and String(out["state"]) not in ["", "(no presenter)"] \
			and float(out.get("dist_m", 99.0)) < 6.0:
		d.soft_check("the '%s' marker over %s is drawn (the player stands %.1f m away)" % [out["state"], _npc_name(npc_id),
			float(out["dist_m"])], bool(out["visible"]), str(out))
	return out


## Opens the Quest Log with its key (if closed), clicks the tab and the quest's row with the mouse, and reads it.
func _quest_window(qid: String, tab: String) -> Dictionary:
	var wr := d.windows() as MisoWindowsRoot
	var qw := wr.quests
	if not bool(wr.call("is_open", "quests")):
		await d.open_window("quests")
	if qw.current_tab != tab:
		await d.click(qw.tab_buttons[tab])
		await d.frames(2)
	var btn: Button = null
	var names: PackedStringArray = []
	for b in qw.list_box.get_children():
		if b is Button:
			names.append((b as Button).text)
			if String(b.get_meta("quest_id", "")) == qid:
				btn = b
	if btn != null and qw.selected_quest != qid:
		await d.click(btn)
		await d.frames(2)
	return {"open": bool(wr.call("is_open", "quests")), "tab": qw.current_tab, "tab_text": (qw.tab_buttons[tab] as Button).text,
		"listed": btn != null, "selected": qw.selected_quest, "list": names, "rows": qw.objective_rows(),
		"detail": qw.detail_texts()}


static func _row_has(rows: Array, text: String, done: bool) -> bool:
	for r: Dictionary in rows:
		if String(r.get("text", "")) == text and (not done or bool(r.get("done", false))):
			return true
	return false


static func _rows_text(rows: Array) -> String:
	var out: PackedStringArray = []
	for r: Dictionary in rows:
		out.append("%s%s" % [r.get("text", ""), " [x]" if bool(r.get("done", false)) else ""])
	return "; ".join(out)


func _hud() -> MisoHud:
	return d.hud() as MisoHud


func _log_clock() -> float:
	var h := _hud()
	return float(h.log_panel.get("_clock")) if h != null else 0.0


## HUD log lines added at or after `clock0` (the log's own clock).
func _log_since(clock0: float) -> PackedStringArray:
	var out: PackedStringArray = []
	var h := _hud()
	if h == null:
		return out
	for e: Dictionary in h.log_panel.history:
		if float(e.get("time", -1.0)) >= clock0:
			out.append(String(e.get("text", "")))
	return out


## The log lines on screen now (not faded out).
func _log_on_screen() -> PackedStringArray:
	var out: PackedStringArray = []
	var h := _hud()
	if h == null:
		return out
	for ch in h.log_panel.get_children():
		if ch.is_queued_for_deletion() or not (ch as Control).visible or (ch as Control).modulate.a <= 0.05:
			continue
		for l in ch.find_children("*", "Label", true, false):
			out.append((l as Label).text)
	return out


static func _quest_lines(lines: PackedStringArray) -> String:
	var out: PackedStringArray = []
	for l in lines:
		if not l.begins_with("You have gained"):
			out.append(l)
	return " / ".join(out)


static func _any_contains(list: Variant, needle: String) -> bool:
	for s: Variant in list:
		if String(s).contains(needle):
			return true
	return false


# =================================================================================================================
# Items
# =================================================================================================================

## Opens the inventory, clicks the item's tab, double-clicks its slot (a real double-click), closes the inventory.
func _use_by_double_click(item_id: String) -> Dictionary:
	var wr := d.windows() as MisoWindowsRoot
	var tab := String(db.item(item_id).get("inventory_tab", "use"))
	await d.open_window("inventory")
	await d.click(wr.inventory.tab_buttons[tab])
	await d.frames(2)
	var idx := -1
	var c := d.character()
	for i in c.inventory.capacity(tab):
		if String(c.inventory.get_slot(tab, i).get("item_id", "")) == item_id:
			idx = i
			break
	if idx < 0 or idx >= wr.inventory.slots.size():
		await d.close_window("inventory")
		return {"ok": false, "status": "no slot for %s in %s" % [item_id, tab]}
	var n0 := c.inventory.count(item_id)
	await _double_click(wr.inventory.slots[idx])
	await d.frames(2)
	var status := wr.inventory.status_label.text
	await d.close_window("inventory")
	return {"ok": c.inventory.count(item_id) == n0 - 1, "status": status}


static func _center(c: Control) -> Vector2:
	return c.get_global_transform_with_canvas() * (c.size * 0.5)


## A real double-click: press, release, then the second press with double_click set (as the OS sends it), release.
func _double_click(c: Control) -> void:
	var at := _center(c)
	d.input.mouse_move(at)
	await d.frames(1)
	d.input.mouse_button(at, true)
	await d.frames(1)
	d.input.mouse_button(at, false)
	await d.frames(1)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = true
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = d.input.to_window(at)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await d.frames(1)
	d.input.mouse_button(at, false)
	await d.frames(1)


func _snapshot() -> Dictionary:
	var c := d.character()
	var bag := {}
	for tab in Inventory.TABS:
		for i in c.inventory.capacity(tab):
			var s := c.inventory.get_slot(tab, i)
			if not s.is_empty():
				var id := String(s.get("item_id", ""))
				bag[id] = int(bag.get(id, 0)) + int(s.get("qty", 1))
	return {"total_exp": _total_exp(), "level": c.level, "exp": c.exp, "mesos": c.mesos, "bag": bag, "counts": bag.duplicate()}


static func _count_in(bag: Dictionary, id: String) -> int:
	return int(bag.get(id, 0))


## Bag changes other than the listed reward items: {item_id: delta}.
static func _bag_delta(a: Dictionary, b: Dictionary, skip: Array) -> Dictionary:
	var skip_ids := {}
	for it: Dictionary in skip:
		skip_ids[String(it.get("item_id", ""))] = true
	var out := {}
	for id: String in a:
		if not skip_ids.has(id) and int(b.get(id, 0)) != int(a[id]):
			out[id] = int(b.get(id, 0)) - int(a[id])
	for id: String in b:
		if not skip_ids.has(id) and not a.has(id):
			out[id] = int(b[id])
	return out


# =================================================================================================================
# Canonical lookups
# =================================================================================================================

## EXP from level 1 at 0 EXP: the EXP to next level of every level below (formulas/exp_table.json) plus the bar.
func _total_exp() -> int:
	var c := d.character()
	var t := c.exp
	for l in range(1, c.level):
		t += Progression.exp_to_next(l, db)
	return t


func _qname(qid: String) -> String:
	return String(db.quest(qid).get("name", qid))


func _mob(qid: String) -> String:
	var kills: Array = (db.quest(qid).get("objectives", {}) as Dictionary).get("monster_kills", [])
	return String((kills[0] as Dictionary).get("mob_id", "")) if not kills.is_empty() else ""


func _kill_req(qid: String) -> int:
	var kills: Array = (db.quest(qid).get("objectives", {}) as Dictionary).get("monster_kills", [])
	return int((kills[0] as Dictionary).get("count", 0)) if not kills.is_empty() else 0


## The Quest Log's kill row as the UI formats it ("Snail 3/10"), from the canonical objective.
func _kill_row(k: int) -> String:
	var kills: Array = (db.quest(Q_SAM).get("objectives", {}) as Dictionary).get("monster_kills", [])
	var o := kills[0] as Dictionary
	return "%s %d/%d" % [String(o.get("name", "")), mini(k, int(o.get("count", 0))), int(o.get("count", 0))]


func _item_name(id: String) -> String:
	return String(db.item(id).get("name", id))


func _npc_name(id: String) -> String:
	return String(db.npc(id).get("name", id))


func _exp_since(t0: float) -> Array:
	var out: Array = []
	for e: Array in exp_log:
		if float(e[2]) >= t0:
			out.append([e[0], e[1]])
	return out


# =================================================================================================================
# Saves on disk
# =================================================================================================================

func _disk_quest(slot: String) -> Dictionary:
	var path := d.save_dir.path_join(slot + ".json")
	var txt := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(txt) if txt != "" else null
	if not (data is Dictionary):
		return {"error": "cannot read %s" % path}
	var q: Variant = (((data as Dictionary).get("character", {}) as Dictionary).get("quests", {}) as Dictionary).get("quests", {})
	return ((q as Dictionary).get(Q_SAM, {}) as Dictionary) if q is Dictionary else {}


func _disk_kills(entry: Dictionary) -> int:
	var prog: Variant = entry.get("progress", {})
	if not (prog is Dictionary):
		return -1
	var kills: Variant = (prog as Dictionary).get("kills", {})
	if not (kills is Dictionary):
		return -1
	return int((kills as Dictionary).get(_mob(Q_SAM), -1))


# =================================================================================================================
# Travel, death, events, screenshots
# =================================================================================================================

## Walks map by map (BFS over the canonical portals) with walk_trail; a hop that fails twice is a WARN and a console
## warp (setup fallback, flagged).
func _travel(to_map: String) -> bool:
	var guard := 0
	while d.current_map() != to_map and guard < 16:
		guard += 1
		if _dead():
			await _respawn()
			continue
		var path := _bfs(d.current_map(), to_map)
		if path.size() < 2:
			d.check("a way from %s to %s" % [d.current_map(), to_map], false, "no canonical portal path")
			return false
		var cur := d.current_map()
		var hop := String(path[1])
		var t0 := d.game_s()
		var r: Dictionary = await d.walk_trail(cur, hop)
		if d.current_map() == cur and not _dead():
			r = await d.walk_trail(cur, hop)
		var ok := d.current_map() == hop
		travel_rows.append("%s->%s %s %.0fs" % [cur.right(4), hop.right(4), "ok" if ok else "FAIL", d.game_s() - t0])
		if not ok and not _dead():
			d.soft_check("walked the trail %s -> %s" % [cur, hop], false, "ended in %s: %s" % [d.current_map(),
				", ".join(r.get("issues", PackedStringArray()))])
			fallbacks.append("%s -> %s" % [cur, hop])
			await d.console("warp " + hop)
	return d.current_map() == to_map


func _bfs(from: String, to: String) -> Array:
	var prev_of := {from: ""}
	var queue: Array = [from]
	while not queue.is_empty():
		var m: String = queue.pop_front()
		if m == to:
			break
		for p: Dictionary in db.map(m).get("portals", []):
			var n := String(p.get("to_map_id", ""))
			if n != "" and not prev_of.has(n) and db.has("maps", n):
				prev_of[n] = m
				queue.append(n)
	if not prev_of.has(to):
		return []
	var path: Array = [to]
	while String(path[0]) != from:
		path.push_front(prev_of[path[0]])
	return path


## talk_to, as a player keeps trying: when the walk to the NPC ends in a death (monsters touch the player on the way),
## the death notice's OK, the walk back to the NPC's map and another approach (at most 3). Each death is a note and
## a WARN (it is play, not a quest failure).
func _talk(npc_id: String) -> Dictionary:
	var map := d.current_map()
	var v: Dictionary = {}
	for attempt in 3:
		var hp0 := d.character().hp
		var dmg0 := damage_taken
		var tc0 := touches.size()
		# The baseline of a reward check: taken right before the approach that opens the chat (walking changes no EXP,
		# item or meso; only a death would, and a death ends the attempt). A quest with no completion text (1002, 1007)
		# completes the moment the chat opens, so it cannot be taken after.
		var pre := _snapshot()
		pre["t"] = d.game_s()
		pre["clock"] = _log_clock()
		pre["notices"] = d.notices.size()
		on_screen_at_complete = []
		v = await d.talk_to(npc_id)
		v["pre"] = pre
		if bool(v.get("open", false)) or not _dead():
			return v
		d.soft_check("the walk up to %s (%s) ends alive" % [_npc_name(npc_id), map], false,
			"died on the approach (attempt %d): HP %d at the start, %d damage from %d touches since (%s)" % [attempt + 1, hp0,
				damage_taken - dmg0, touches.size() - tc0, ", ".join(touches.slice(tc0))])
		await _respawn()
		if not await _travel(map):
			return v
	return v


## Walks up to a few metres of an NPC (real input), as a player does before talking, so its quest marker is on
## screen when it is read. A death on the way: OK, the walk back, one more try.
func _approach(npc_id: String) -> void:
	var map := d.current_map()
	for attempt in 2:
		var hp0 := d.character().hp
		var dmg0 := damage_taken
		var tc0 := touches.size()
		await d.walk_to("npc:" + npc_id, {"within_m": 3.5, "max_s": 45.0})
		if not _dead():
			return
		d.soft_check("the walk up to %s (%s) ends alive" % [_npc_name(npc_id), map], false,
			"died on the approach (walk %d): HP %d at the start, %d damage from %d touches since (%s)" % [attempt + 1, hp0,
				damage_taken - dmg0, touches.size() - tc0, ", ".join(touches.slice(tc0))])
		await _respawn()
		if not await _travel(map):
			return


func _dead() -> bool:
	var p := d.player()
	return d.game().is_character_dead() or (p != null and p.is_dead())


func _respawn() -> void:
	var where := d.current_map()
	await d.wait(0.5)
	var ok: Dictionary = await d.click("OK")
	await d.wait_until(func() -> bool: return not d.game().is_character_dead(), 30.0)
	await d.wait_idle(30.0)
	deaths.append("%s -> %s (OK %s)" % [where, d.current_map(), ok["ok"]])
	d.note("died in %s, respawned in %s" % [where, d.current_map()])


func _connect_bus() -> void:
	var ev := d.events()
	ev.connect(&"exp_gained", func(amount: int, source: String) -> void: exp_log.append([amount, source, d.game_s()]))
	ev.connect(&"quest_started", func(qid: String) -> void: quest_events.append([qid, "started", d.game_s()]))
	ev.connect(&"quest_completed", func(qid: String) -> void: quest_events.append([qid, "completed", d.game_s()]))
	ev.connect(&"player_damaged", func(amount: int, mob: String) -> void:
		damage_taken += amount
		touches.append("%s:%d@%s" % [mob, amount, d.current_map().right(4)]))


func _shot(shot_name: String) -> void:
	shots += 1
	await d.screenshot(shot_name)
