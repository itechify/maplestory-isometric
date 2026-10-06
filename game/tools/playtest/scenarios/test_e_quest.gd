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
## NPC quest markers (available, in progress, completable) are read from the NPC presenters the HUD draws. The
## composite play (travel, talk, conversations, markers, the Quest Log, item use, deaths) is PlaytestKit's.

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
## Travel falls back to a logged console warp when a trail cannot be walked (this scenario is not strict).
const TRAVEL := {"fallback_warp": true}

var d: PlaytestDriver = null
var db: ContentDB = null
var k: PlaytestKit = null


func description() -> String:
	return "Test E: Roger's Apple (1002), Sam's Suggestion (1006) twice (once straight, once with save / title / " \
		+ "continue / process restart at 5/10), Maria -> Lucas -> Maria (1007 -> 1008), exact canonical rewards"


func max_seconds() -> float:
	return 2400.0


func run(p_d: PlaytestDriver) -> void:
	d = p_d
	db = d.db()
	k = PlaytestKit.new(d)
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
	k.connect_bus()
	var c := d.character()
	d.check("A: a clean character: level 1, 0 EXP, no quest started or completed, empty bag",
		c.level == 1 and c.exp == 0 and c.quests.active_ids().is_empty() and c.quests.completed_ids().is_empty()
		and c.inventory.is_empty() and d.current_map() == START_MAP,
		"level %d exp %d active %s completed %s map %s" % [c.level, c.exp, c.quests.active_ids(), c.quests.completed_ids(),
			d.current_map()])
	d.carry["slot_a"] = String(ng["slot"])

	# --- Roger's Apple (1002) -----------------------------------------------------------------------------------
	if not await k.travel_to(ROGER_MAP, TRAVEL):
		return
	await _roger()

	# --- Sam's Suggestion (1006), straight through ---------------------------------------------------------------
	if not await k.travel_to(SAM_MAP, TRAVEL):
		return
	if not await _accept_sam("A"):
		return
	await _hunt_sam("A", _kill_req(Q_SAM), true)
	await _finish_sam("A")

	# --- Letter for Lucas (1007) -> Lucas's Reply (1008) ------------------------------------------------------------
	await _letter_chain()

	# --- Character B: 1006 with the interruption --------------------------------------------------------------------
	_note_travel("A")
	# B's notes start empty.
	k.travel_rows.clear()
	k.fallbacks.clear()
	k.deaths.clear()
	k.touches.clear()
	k.damage_taken = 0
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
	if not await k.travel_to(SAM_MAP, TRAVEL):
		return
	if not await _accept_sam("B"):
		return
	await _hunt_sam("B", HALF, true)
	var kn := c.quests.kills(Q_SAM, _mob(Q_SAM))
	d.check("B: progress stopped halfway at %d/%d" % [HALF, _kill_req(Q_SAM)], kn == HALF, "%d kills counted" % kn,
		["quest:" + Q_SAM, "mechanic:quest-persistence"])
	var before := _quest_snapshot()

	var saved: Dictionary = await d.save_game()
	d.check("B: the pause menu's Save writes the slot mid-quest", bool(saved["ok"]) and saved["via"] == "screen"
		and String(saved["slot"]) == String(d.carry["slot_b"]), "%s '%s' via %s" % [saved["slot"], saved["status"], saved["via"]])
	var disk := _disk_quest(String(d.carry["slot_b"]))
	d.check("B: the save file on disk holds 1006 in progress at %d kills" % kn, String(disk.get("status", "")) == "in_progress"
		and _disk_kills(disk) == kn, "%s" % str(disk).left(240), ["quest:" + Q_SAM, "mechanic:quest-persistence"])
	var q2: Dictionary = await d.quit_to_title()
	if not d.check("B: Quit to Title mid-quest", bool(q2["ok"]) and q2["via"] == "screen", str(q2)):
		return
	var cont: Dictionary = await d.continue_game()
	if not d.check("B: Continue from the title loads B", bool(cont["ok"]) and cont["via"] == "screen"
			and String(cont["slot"]) == String(d.carry["slot_b"]) and d.character().name == NAME_B,
			"%s in %s via %s, %s" % [cont["slot"], cont["map"], cont["via"], d.character().name]):
		return
	await _verify_resumed("B after Quit to Title + Continue", before)
	await k.shot("b_questlog_after_continue")
	d.carry["b_before"] = before
	_note_travel("B")
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
	k.connect_bus()
	var before: Dictionary = d.carry.get("b_before", {})
	var disk := _disk_quest(String(d.carry["slot_b"]))
	d.check("B: after the process restart the save file still holds %d kills" % int(before.get("kills", -1)),
		_disk_kills(disk) == int(before.get("kills", -2)), str(disk).left(240), ["quest:" + Q_SAM, "mechanic:quest-persistence"])
	await _verify_resumed("B after Quit Game + a new process + Continue", before)
	await k.shot("b_questlog_after_restart")
	if d.current_map() != SAM_MAP and not await k.travel_to(SAM_MAP, TRAVEL):
		return
	await _hunt_sam("B", _kill_req(Q_SAM), true)
	await _finish_sam("B")
	_note_travel("B (phase 1)")
	await k.shot("b_done")


func _note_travel(who: String) -> void:
	var deaths := PackedStringArray()
	for row: Dictionary in k.deaths:
		deaths.append("%s -> %s (OK %s)" % [row["map"], row["respawn_map"], row["ok_clicked"]])
	d.note("%s: travel %s; fallbacks %s; deaths %s; %d damage from %d touches; survival %s" % [who, k.travel_text(),
		k.fallbacks, deaths, k.damage_taken, k.touches.size(), k.survival])


# =================================================================================================================
# Roger's Apple (1002)
# =================================================================================================================

func _roger() -> void:
	var c := d.character()
	var qrec := db.quest(Q_APPLE)
	var qname := String(qrec.get("name", Q_APPLE))
	var pq := ["quest:" + Q_APPLE]
	await k.approach(ROGER)
	var m0 := await k.marker(ROGER)
	d.check("Roger's marker reads 'available' before 1002 (gold !)", m0["state"] == "available" and m0["engine"] == "available",
		str(m0), pq + ["mechanic:quest-indicators"])
	await k.shot("roger_available")
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

	var talk: Dictionary = await k.talk(ROGER)
	var clock0 := float((talk.get("pre", {}) as Dictionary).get("clock", k.log_clock()))
	if not d.check("Roger can be talked to on foot (the round-4 garden steps)", bool(talk["open"]),
			"gap %s: %s" % [talk.get("talk_gap", "-"), talk.get("why", "")], ["npc:" + ROGER]):
		return
	var card := String(talk.get("text", ""))
	var conv: Dictionary = await k.converse({Q_APPLE: "accept"})
	d.note("Roger accept pages: %s" % " | ".join(conv["pages"]))
	d.check("1002 offered as a quest card (journal summary + 'Accept this quest?') and accepted with Y",
		c.quests.is_in_progress(Q_APPLE) and card.contains(String((qrec.get("journal", {}) as Dictionary).get("summary", "@@"))),
		"status %s, card '%s'" % [c.quests.status(Q_APPLE), card.left(120)], pq)
	d.check("Roger handed over %d x %s on accepting" % [apple_n, k.item_name(apple)], c.inventory.count(apple) == apple_n,
		"count %d" % c.inventory.count(apple), pq)
	var lines := k.log_since(clock0)
	var want_item := MisoUiText.item_gained_line(k.item_name(apple), apple_n)
	d.check("the HUD log says '%s' and 'Quest started: %s'" % [want_item, qname], want_item in lines
		and ("Quest started: %s" % qname) in lines, " / ".join(lines))
	d.check("the accept banner names the quest and the item", PlaytestKit.any_contains(conv["banners"], "Quest accepted: %s" % qname),
		" / ".join(conv["banners"]))
	var m1 := await k.marker(ROGER)
	d.check("Roger's marker reads 'in_progress' after the accept (grey ...)", m1["state"] == "in_progress", str(m1),
		pq + ["mechanic:quest-indicators"])
	var qw := await k.quest_window(Q_APPLE, "in_progress")
	var want_row := "Use %s 0/%d" % [String((use_obj[0] as Dictionary).get("name", "")), use_n]
	d.check("the Quest Log lists 1002 In Progress with '%s'" % want_row, bool(qw["listed"]) and PlaytestKit.row_has(qw["rows"], want_row, false),
		PlaytestKit.rows_text(qw["rows"]), pq + ["mechanic:quest-log"])
	await d.close_window("quests")

	# --- Eat the apple: Use tab, double-click --------------------------------------------------------------------
	var hp0 := c.hp
	var clock_use := k.log_clock()
	var used: Dictionary = await k.use_item(apple)
	var restore := int((db.item(apple).get("consumable", {}) as Dictionary).get("hp_restore", 0))
	var max_hp := StatCalculator.max_hp(c, db)
	d.check("double-clicking %s in the Use tab eats it: count %d -> %d, HP %d -> min(Max HP %d, +%d)" % [k.item_name(apple),
		apple_n, apple_n - 1, hp0, max_hp, restore], bool(used["ok"]) and c.inventory.count(apple) == apple_n - 1
		and c.hp == mini(max_hp, hp0 + restore), "count %d, HP %d, status '%s'" % [c.inventory.count(apple), c.hp, used["status"]],
		pq + ["item:" + apple])
	d.check("the usage objective counts it (%d/%d)" % [use_n, use_n], c.quests.uses(Q_APPLE, apple) == use_n,
		"uses %d" % c.quests.uses(Q_APPLE, apple), pq)
	var use_line := "%s: Use %s %d/%d" % [qname, String((use_obj[0] as Dictionary).get("name", "")), use_n, use_n]
	var use_lines := k.log_since(clock_use)
	d.check("the HUD log counts the use: '%s'" % use_line, use_line in use_lines, " / ".join(use_lines))
	var m2 := await k.marker(ROGER)
	d.check("Roger's marker reads 'completable' once the apple is eaten (green ?)", m2["state"] == "completable", str(m2),
		pq + ["mechanic:quest-indicators"])
	await k.shot("roger_completable")

	# --- Turn in --------------------------------------------------------------------------------------------------
	talk = await k.talk(ROGER)
	if not d.check("Roger can be talked to again for the turn-in", bool(talk["open"]), str(talk.get("why", ""))):
		return
	var snap: Dictionary = talk["pre"]
	var t0 := float(snap["t"])
	clock0 = float(snap["clock"])
	conv = await k.converse({Q_APPLE: "complete"})
	d.note("Roger turn-in pages: %s" % " | ".join(conv["pages"]))
	await d.wait(0.3)
	var rew := qrec.get("rewards", {}) as Dictionary
	var after := k.snapshot()
	d.check("1002 completed at Roger", c.quests.is_completed(Q_APPLE), c.quests.status(Q_APPLE), pq)
	d.check("1002's canonical reward exactly: EXP +%d, mesos +%d, no items" % [int(rew.get("exp", 0)), int(rew.get("mesos", 0))],
		int(after["total_exp"]) - int(snap["total_exp"]) == int(rew.get("exp", 0))
		and int(after["mesos"]) - int(snap["mesos"]) == int(rew.get("mesos", 0))
		and PlaytestDriver.diff(snap["bag"], after["bag"]) == "" and (rew.get("items", []) as Array).is_empty()
		and k.exp_since(t0).is_empty() == (int(rew.get("exp", 0)) == 0),
		"EXP %d -> %d, mesos %d -> %d, bag diff '%s', exp events %s" % [snap["total_exp"], after["total_exp"], snap["mesos"],
			after["mesos"], PlaytestDriver.diff(snap["bag"], after["bag"]), k.exp_since(t0)], pq)
	lines = k.log_since(clock0)
	d.check("the HUD log says 'Quest complete: %s'" % qname, ("Quest complete: %s" % qname) in lines, " / ".join(lines))
	var m3 := await k.marker(ROGER)
	d.check("Roger's marker is gone once 1002 is completed (he has no other quest)", m3["state"] == "", str(m3),
		pq + ["mechanic:quest-indicators"])


# =================================================================================================================
# Sam's Suggestion (1006)
# =================================================================================================================

func _accept_sam(who: String) -> bool:
	var c := d.character()
	var qname := k.qname(Q_SAM)
	var pq := ["quest:" + Q_SAM]
	await k.approach(SAM)
	var m0 := await k.marker(SAM)
	d.check("%s: Sam's marker reads 'available' before 1006" % who, m0["state"] == "available", str(m0),
		pq + ["mechanic:quest-indicators"])
	if who == "A":
		await k.shot("sam_available")
		var avail := await k.quest_window(Q_SAM, "available")
		d.check("A: the Quest Log's Available tab lists 1006 before the accept", bool(avail["listed"]),
			"tab '%s', list %s" % [avail["tab_text"], avail["list"]], pq + ["mechanic:quest-log"])
		d.soft_check("A: the Available tab marks 1006 '[nearby]' while standing in Sam's map (quest_window.gd docs)",
			PlaytestKit.any_contains(avail["list"], "[nearby]"), "list %s; Sam's canonical map %s, current %s" % [avail["list"],
				SAM_MAP, d.current_map()])
		await d.close_window("quests")
	var talk: Dictionary = await k.talk(SAM)
	var clock0 := float((talk.get("pre", {}) as Dictionary).get("clock", k.log_clock()))
	if not d.check("%s: Sam can be talked to on foot" % who, bool(talk["open"]), str(talk.get("why", "")), ["npc:" + SAM]):
		return false
	var conv: Dictionary = await k.converse({Q_SAM: "accept"})
	d.note("%s: Sam accept pages: %s" % [who, " | ".join(conv["pages"])])
	if not d.check("%s: 1006 accepted through Sam's dialogue (Yes)" % who, c.quests.is_in_progress(Q_SAM),
			c.quests.status(Q_SAM), pq):
		return false
	var lines := k.log_since(clock0)
	d.check("%s: the HUD log says 'Quest started: %s'" % [who, qname], ("Quest started: %s" % qname) in lines, " / ".join(lines))
	var m1 := await k.marker(SAM)
	d.check("%s: Sam's marker reads 'in_progress' after the accept (1006 ends at Mai)" % who, m1["state"] == "in_progress", str(m1),
		pq + ["mechanic:quest-indicators"])
	var qw := await k.quest_window(Q_SAM, "in_progress")
	var want := _kill_row(0)
	d.check("%s: the Quest Log shows 1006 In Progress with '%s' and a turn-in row naming Mai" % [who, want], bool(qw["listed"])
		and PlaytestKit.row_has(qw["rows"], want, false) and PlaytestKit.row_contains(qw["rows"], k.npc_name(MAI)),
		PlaytestKit.rows_text(qw["rows"]), pq + ["mechanic:quest-log"])
	if who == "A":
		await k.shot("questlog_0_of_10")
	return true


## Kills Snails with the attack key until 1006 counts `target`. With the Quest Log open, its objective row is read
## after every kill; the HUD log's "<quest>: Snail k/10" line too.
func _hunt_sam(who: String, target: int, watch: bool) -> void:
	var c := d.character()
	var mob := _mob(Q_SAM)
	var start := c.quests.kills(Q_SAM, mob)
	var clock0 := k.log_clock()
	if watch:
		await k.quest_window(Q_SAM, "in_progress")
	var wr := d.windows() as MisoWindowsRoot
	var seen: PackedStringArray = []
	var bad: PackedStringArray = []
	var exclude := {}
	var fails := 0
	var t0 := d.game_s()
	var last_k := start
	var jumps: PackedStringArray = []
	while c.quests.kills(Q_SAM, mob) < target and d.game_s() - t0 < HUNT_BUDGET_S:
		if k.is_dead():
			await k.respawn()
			continue
		if d.current_map() != SAM_MAP:
			if not await k.travel_to(SAM_MAP, TRAVEL):
				break
			if watch:
				await k.quest_window(Q_SAM, "in_progress")
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
				var shown := PlaytestKit.rows_text(wr.quests.objective_rows())
				seen.append("%d:%s" % [k1, shown.get_slice(";", 0)])
				if not PlaytestKit.row_has(wr.quests.objective_rows(), _kill_row(k1), k1 >= _kill_req(Q_SAM)):
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
		end == target, "%.0f s; count steps of more than one between two reads: %s" % [d.game_s() - t0, jumps],
		["quest:" + Q_SAM, "monster:" + mob])
	if watch:
		d.check("%s: the open Quest Log's objective row followed every kill (%d reads)" % [who, seen.size()],
			bad.is_empty() and not seen.is_empty() and last_k == end, "%s; %s" % [", ".join(seen), ", ".join(bad)],
			["quest:" + Q_SAM, "mechanic:quest-log"])
		await d.close_window("quests")
	# The HUD log: one "<quest>: Snail k/10" line per kill, in order.
	var lines := k.log_since(clock0)
	var missing: PackedStringArray = []
	var at := -1
	for kk in range(start + 1, end + 1):
		var want := "%s: %s" % [k.qname(Q_SAM), _kill_row(kk)]
		var idx := lines.find(want, at + 1)
		if idx < 0:
			missing.append(want)
		else:
			at = idx
	d.check("%s: the HUD log counted every kill in order ('%s: %s' .. '%s')" % [who, k.qname(Q_SAM), _kill_row(start + 1),
		_kill_row(end)], missing.is_empty() and end > start, "missing %s; quest lines %s" % [missing, PlaytestKit.quest_lines(lines)])
	d.note("%s: hunt %d -> %d in %.0f s, window reads %s" % [who, start, end, d.game_s() - t0, ", ".join(seen)])


func _finish_sam(who: String) -> void:
	var c := d.character()
	var qrec := db.quest(Q_SAM)
	var rew := qrec.get("rewards", {}) as Dictionary
	var reward_exp := int(rew.get("exp", 0))
	var reward_items: Array = rew.get("items", [])
	var qname := k.qname(Q_SAM)
	var pq := ["quest:" + Q_SAM]
	var qw := await k.quest_window(Q_SAM, "in_progress")
	d.check("%s: the Quest Log shows 1006 '[ready]' with '%s' ticked" % [who, _kill_row(_kill_req(Q_SAM))],
		PlaytestKit.any_contains(qw["list"], "[ready]") and PlaytestKit.row_has(qw["rows"], _kill_row(_kill_req(Q_SAM)), true)
		and PlaytestKit.any_contains(qw["detail"], "Ready to turn in"), "list %s rows %s" % [qw["list"], PlaytestKit.rows_text(qw["rows"])],
		pq + ["mechanic:quest-log"])
	await d.close_window("quests")
	if not await k.travel_to(MAI_MAP, TRAVEL):
		return
	await k.approach(MAI)
	var m0 := await k.marker(MAI)
	d.check("%s: Mai's marker reads 'completable' (green ?) with 1006 ready" % who, m0["state"] == "completable", str(m0),
		pq + ["mechanic:quest-indicators"])
	if who == "A":
		await k.shot("mai_completable")
	var talk: Dictionary = await k.talk(MAI)
	if not d.check("%s: Mai can be talked to on foot" % who, bool(talk["open"]), str(talk.get("why", "")), ["npc:" + MAI]):
		return
	# The baseline: right before the approach that opened the chat (PlaytestKit.talk).
	var snap: Dictionary = talk["pre"]
	var t0 := float(snap["t"])
	var clock0 := float(snap["clock"])
	var n0 := int(snap["notices"])
	var conv: Dictionary = await k.converse({Q_SAM: "complete"}, {"shot_on_complete": who == "A"})
	d.note("%s: Mai turn-in pages: %s" % [who, " | ".join(conv["pages"])])
	await d.wait(0.3)
	var after := k.snapshot()
	var events := k.exp_since(t0)
	d.check("%s: 1006 completed at Mai" % who, c.quests.is_completed(Q_SAM), c.quests.status(Q_SAM), pq)
	var dexp := int(after["total_exp"]) - int(snap["total_exp"])
	d.check("%s: EXP delta is exactly the canonical rewards.exp %d (cumulative over levels)" % [who, reward_exp],
		dexp == reward_exp and events.size() == 1 and int(events[0][0]) == reward_exp and String(events[0][1]) == "quest:" + Q_SAM,
		"total EXP %d -> %d (+%d); level %d -> %d, exp %d -> %d; exp events %s" % [snap["total_exp"], after["total_exp"], dexp,
			snap["level"], after["level"], snap["exp"], after["exp"], events], pq)
	var item_txt: PackedStringArray = []
	var items_ok := true
	for it: Dictionary in reward_items:
		var id := String(it.get("item_id", ""))
		var n := int(it.get("count", 0))
		var got := c.inventory.count(id) - int((snap["counts"] as Dictionary).get(id, PlaytestKit.count_in(snap["bag"], id)))
		items_ok = items_ok and got == n
		item_txt.append("%s %s: %+d (canonical %d)" % [id, k.item_name(id), got, n])
	var others := PlaytestKit.bag_delta(snap["bag"], after["bag"], reward_items)
	d.check("%s: exactly the canonical reward items, nothing else: %s" % [who, ", ".join(item_txt)],
		items_ok and not reward_items.is_empty() and others.is_empty() and int(after["mesos"]) == int(snap["mesos"]) + int(rew.get("mesos", 0)),
		"%s; other bag changes %s; mesos %d -> %d" % [", ".join(item_txt), others, snap["mesos"], after["mesos"]], pq)
	var lines := k.log_since(clock0)
	var want_exp := MisoUiText.exp_gained_line(reward_exp)
	d.check("%s: the HUD log shows '%s'" % [who, want_exp], want_exp in lines, " / ".join(lines))
	d.check("%s: and that line is on screen when the quest completes" % who, want_exp in k.on_screen_at_complete,
		" / ".join(k.on_screen_at_complete))
	for it: Dictionary in reward_items:
		var want_it := MisoUiText.item_gained_line(k.item_name(String(it.get("item_id", ""))), int(it.get("count", 1)))
		d.check("%s: the HUD log shows '%s'" % [who, want_it], want_it in lines, " / ".join(lines))
	d.check("%s: the HUD log shows 'Quest complete: %s'" % [who, qname], ("Quest complete: %s" % qname) in lines, " / ".join(lines))
	var shown_banner := " / ".join(conv["banners"]) + " / " + " / ".join(Array(d.notices).slice(n0))
	d.check("%s: the dialogue's completion banner names +%d EXP and the items" % [who, reward_exp],
		shown_banner.contains("Quest complete: %s" % qname) and shown_banner.contains("+%d EXP" % reward_exp)
		and (reward_items.is_empty() or shown_banner.contains(k.item_name(String((reward_items[0] as Dictionary).get("item_id", ""))))),
		shown_banner)
	var done := await k.quest_window(Q_SAM, "completed")
	d.check("%s: the Quest Log's Completed tab lists 1006 as Completed" % who, bool(done["listed"])
		and PlaytestKit.any_contains(done["detail"], "Completed"), "tab '%s' list %s detail %s" % [done["tab_text"], done["list"],
			" / ".join(done["detail"]).left(200)], pq + ["mechanic:quest-log"])
	if who == "A":
		await k.shot("questlog_completed")
	await d.close_window("quests")
	var m1 := await k.marker(MAI)
	var engine := d.game().quests.engine
	var next_avail := false
	for qid in engine.catalog.started_by(MAI):
		next_avail = next_avail or engine.is_available(qid)
	d.check("%s: Mai's marker after 1006: '%s' (her own quests %s, level %d)" % [who, "available" if next_avail else "",
		engine.catalog.started_by(MAI), c.level], m1["state"] == ("available" if next_avail else ""), str(m1),
		pq + ["mechanic:quest-indicators"])


# =================================================================================================================
# 1007 -> 1008: Maria's letter to Lucas, his reply back
# =================================================================================================================

func _letter_chain() -> void:
	var c := d.character()
	var q7 := db.quest(Q_LETTER)
	var q8 := db.quest(Q_REPLY)
	var p7 := ["quest:" + Q_LETTER]
	var p8 := ["quest:" + Q_REPLY]
	if c.level < int(q7.get("min_level", 0)):
		d.soft_check("A: level %d reaches 1007's canonical min_level %d for the letter chain" % [c.level, int(q7.get("min_level", 0))],
			false, "skipping 1007 -> 1008")
		return
	if d.current_map() != MAI_MAP and not await k.travel_to(MAI_MAP, TRAVEL):
		return
	var letter := String(((q7.get("items_given_on_accept", []) as Array)[0] as Dictionary).get("item_id", ""))
	await k.approach(MARIA)
	var m0 := await k.marker(MARIA)
	d.check("Maria's marker reads 'available' (1007)", m0["state"] == "available", str(m0), p7 + ["mechanic:quest-indicators"])
	var talk: Dictionary = await k.talk(MARIA)
	if not d.check("Maria can be talked to on foot", bool(talk["open"]), str(talk.get("why", "")), ["npc:" + MARIA]):
		return
	var conv: Dictionary = await k.converse({Q_LETTER: "accept"})
	d.note("Maria accept pages: %s" % " | ".join(conv["pages"]))
	d.check("1007 accepted from Maria: %s x1 handed over (canonical items_given_on_accept)" % k.item_name(letter),
		c.quests.is_in_progress(Q_LETTER) and c.inventory.count(letter) == 1, "status %s, %s x%d" % [c.quests.status(Q_LETTER),
			letter, c.inventory.count(letter)], p7)
	var m1 := await k.marker(MARIA)
	d.check("Maria's marker reads 'in_progress' (1007 ends at Lucas)", m1["state"] == "in_progress", str(m1),
		p7 + ["mechanic:quest-indicators"])
	if not await k.travel_to(LUCAS_MAP, TRAVEL):
		return
	await k.approach(LUCAS)
	var m2 := await k.marker(LUCAS)
	d.check("Lucas's marker reads 'completable' with the letter", m2["state"] == "completable", str(m2),
		p7 + ["mechanic:quest-indicators"])
	var reply := String(((q8.get("items_given_on_accept", []) as Array)[0] as Dictionary).get("item_id", "")) \
		if not (q8.get("items_given_on_accept", []) as Array).is_empty() else ""
	talk = await k.talk(LUCAS)
	if not d.check("Lucas can be talked to on foot", bool(talk["open"]), str(talk.get("why", "")), ["npc:" + LUCAS]):
		return
	var snap: Dictionary = talk["pre"]
	var t0 := float(snap["t"])
	conv = await k.converse({Q_LETTER: "complete", Q_REPLY: "accept"})
	d.note("Lucas pages: %s" % " | ".join(conv["pages"]))
	var r7 := q7.get("rewards", {}) as Dictionary
	var a7 := k.snapshot()
	d.check("1007 completed at Lucas: the letter handed in, canonical EXP +%d" % int(r7.get("exp", 0)),
		c.quests.is_completed(Q_LETTER) and c.inventory.count(letter) == 0
		and int(a7["total_exp"]) - int(snap["total_exp"]) == int(r7.get("exp", 0)),
		"status %s, %s x%d, EXP %+d, events %s" % [c.quests.status(Q_LETTER), letter, c.inventory.count(letter),
			int(a7["total_exp"]) - int(snap["total_exp"]), k.exp_since(t0)], p7)
	d.check("1008 accepted from Lucas in the same conversation: %s x1" % k.item_name(reply), c.quests.is_in_progress(Q_REPLY)
		and reply != "" and c.inventory.count(reply) == 1, "status %s, %s x%d" % [c.quests.status(Q_REPLY), reply,
			c.inventory.count(reply)], p8)
	if not await k.travel_to(MAI_MAP, TRAVEL):
		return
	await k.approach(MARIA)
	var m3 := await k.marker(MARIA)
	d.check("Maria's marker reads 'completable' with Lucas's reply", m3["state"] == "completable", str(m3),
		p8 + ["mechanic:quest-indicators"])
	talk = await k.talk(MARIA)
	if not d.check("Maria can be talked to again", bool(talk["open"]), str(talk.get("why", ""))):
		return
	snap = talk["pre"]
	t0 = float(snap["t"])
	var clock0 := float(snap["clock"])
	conv = await k.converse({Q_REPLY: "complete"})
	d.note("Maria turn-in pages: %s" % " | ".join(conv["pages"]))
	await d.wait(0.3)
	var after := k.snapshot()
	var r8 := q8.get("rewards", {}) as Dictionary
	var group: Array = []
	for g: Dictionary in r8.get("random", []):
		for it: Dictionary in g.get("items", []):
			group.append(String(it.get("item_id", "")))
	var gained := PlaytestKit.bag_delta(snap["bag"], after["bag"], [])
	var hats: PackedStringArray = []
	var other: PackedStringArray = []
	for id: String in gained:
		var n := int(gained[id])
		if id in group and n == 1:
			hats.append(id)
		elif not (id == reply and n == -1):
			other.append("%s %+d" % [id, n])
	var dexp := int(after["total_exp"]) - int(snap["total_exp"])
	var ev := k.exp_since(t0)
	d.check("1008 completed at Maria: the reply handed in, EXP exactly +%d (canonical), one item of the random group" % int(r8.get("exp", 0)),
		c.quests.is_completed(Q_REPLY) and c.inventory.count(reply) == 0 and dexp == int(r8.get("exp", 0))
		and ev.size() == 1 and int(ev[0][0]) == int(r8.get("exp", 0)) and hats.size() == 1 and other.is_empty(),
		"status %s, reply x%d, EXP %+d events %s, won %s (%s), other %s; group %s" % [c.quests.status(Q_REPLY), c.inventory.count(reply),
			dexp, ev, hats, k.item_name(hats[0]) if not hats.is_empty() else "-", other, group],
		p8 + ["mechanic:quest-random-rewards"])
	var lines := k.log_since(clock0)
	d.check("the HUD log shows '%s' for 1008" % MisoUiText.exp_gained_line(int(r8.get("exp", 0))),
		MisoUiText.exp_gained_line(int(r8.get("exp", 0))) in lines, " / ".join(lines))
	var m4 := await k.marker(MARIA)
	d.check("Maria's marker is gone after 1008", m4["state"] == "", str(m4), p8 + ["mechanic:quest-indicators"])


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
	var kn := c.quests.kills(Q_SAM, _mob(Q_SAM))
	var pq := ["quest:" + Q_SAM, "mechanic:quest-persistence"]
	d.check("%s: 1006 still in progress at %d/%d" % [when, int(before.get("kills", -1)), _kill_req(Q_SAM)],
		c.quests.is_in_progress(Q_SAM) and kn == int(before.get("kills", -1)) and c.name == String(before.get("name", "")),
		"status %s kills %d, %s" % [c.quests.status(Q_SAM), kn, c.name], pq)
	var diff := PlaytestDriver.diff(before.get("log", {}), c.quests.to_dict())
	d.check("%s: the whole quest log is the saved one" % when, diff == "", diff, pq)
	d.check("%s: level and EXP kept" % when, c.level == int(before.get("level", -1)) and c.exp == int(before.get("exp", -1)),
		"level %d exp %d (saved %s / %s)" % [c.level, c.exp, before.get("level"), before.get("exp")])
	var qw := await k.quest_window(Q_SAM, "in_progress")
	d.check("%s: the Quest Log shows '%s'" % [when, _kill_row(kn)], bool(qw["listed"]) and PlaytestKit.row_has(qw["rows"], _kill_row(kn), false),
		PlaytestKit.rows_text(qw["rows"]), pq + ["mechanic:quest-log"])
	if d.current_map() == SAM_MAP:
		var m := await k.marker(SAM)
		d.check("%s: Sam's marker still reads 'in_progress'" % when, m["state"] == "in_progress", str(m),
			pq + ["mechanic:quest-indicators"])


# =================================================================================================================
# Canonical lookups
# =================================================================================================================

func _mob(qid: String) -> String:
	var kills: Array = (db.quest(qid).get("objectives", {}) as Dictionary).get("monster_kills", [])
	return String((kills[0] as Dictionary).get("mob_id", "")) if not kills.is_empty() else ""


func _kill_req(qid: String) -> int:
	var kills: Array = (db.quest(qid).get("objectives", {}) as Dictionary).get("monster_kills", [])
	return int((kills[0] as Dictionary).get("count", 0)) if not kills.is_empty() else 0


## The Quest Log's kill row as the UI formats it ("Snail 3/10"), from the canonical objective.
func _kill_row(n: int) -> String:
	var kills: Array = (db.quest(Q_SAM).get("objectives", {}) as Dictionary).get("monster_kills", [])
	var o := kills[0] as Dictionary
	return "%s %d/%d" % [String(o.get("name", "")), mini(n, int(o.get("count", 0))), int(o.get("count", 0))]


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
