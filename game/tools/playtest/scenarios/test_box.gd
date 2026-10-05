extends PlaytestScenario
## test_box: Pio's Collecting Recycled Goods (1012) played in the real game with the Wooden Boxes (contract C8). A new
## game through the title and creation screens; setup by console (counted in the report): level 5 (1012's canonical
## minimum level) and a warp to Amherst (000001010). Pio's quest is accepted through his dialogue, then the boxes are
## broken with the attack key: the player walks up to the nearest intact box, faces it and swings until it breaks
## (every box must take exactly the canonical hits_to_break landed swings), and picks up what it dropped with the
## pickup key, until the bag holds the canonical 3 Rusty Screws and 3 Old Wooden Boards. When every box of the map is
## broken it waits for the first to come back (its canonical respawn_s). The quest is turned in to Pio: completed, the
## two items handed in, and the canonical rewards (EXP, mesos, The Green Relaxer) received.
## Phase 1, after Quit Game and a new process: Continue in Amherst, and the box that took hits right before the quit
## stands intact again with all its hits left (box state is never saved).

const AMHERST := "000001010"
const PIO := "18"
const QUEST := "1012"
const WEAPON := "585"
const BOX_REACH_SHARE := 0.6
const BREAK_BUDGET_S := 1500.0

var d: PlaytestDriver = null
var db: ContentDB = null
var bs: Node = null
## Every box broken: [key, landed swings, swings, whiffs].
var broken_rows: Array = []
var loot_events: Array = []
var exp_log: Array = []


func description() -> String:
	return "Pio's quest (1012) with the Wooden Boxes: accept, break boxes with the attack key, pick up 3 Rusty Screws " \
		+ "and 3 Old Wooden Boards, turn in, The Green Relaxer; box state not saved across a real reload"


func max_seconds() -> float:
	return 2400.0


func run(p_d: PlaytestDriver) -> void:
	d = p_d
	db = d.db()
	if d.phase == 0:
		await _phase0()
	else:
		await _phase1()


func _phase0() -> void:
	var ng: Dictionary = await d.new_game("BoxTester", "female", WEAPON)
	if not d.check("new game through the title and creation screens", bool(ng["ok"]), "%s via %s %s" % [ng["map"], ng["via"], ng["why"]]):
		return
	bs = d.system("BreakableSystem")
	if not d.check("the BreakableSystem is installed", bs != null, "" if bs != null else "no BreakableSystem under ctx.systems"):
		return
	_connect_bus()
	var q := db.quest(QUEST)
	var min_level := int(q.get("min_level", 1))
	await d.console("level %d" % min_level)
	await d.console("warp " + AMHERST)
	await d.wait_idle(20.0)
	if not d.check("setup: level %d (1012's minimum) and in Amherst" % min_level, d.character().level >= min_level
			and d.current_map() == AMHERST, "level %d in %s" % [d.character().level, d.current_map()]):
		return
	await d.wait(0.5)
	var boxes := _boxes()
	var canon := BreakableRules.placements_of(db.map(AMHERST)).size()
	d.check("Amherst shows its %d canonical Wooden Boxes, intact" % canon, boxes.size() == canon
		and boxes.all(func(b: Node) -> bool: return not bool(b.call("is_broken")) and int(b.call("hits_left")) == _hits()),
		"%d boxes: %s" % [boxes.size(), ", ".join(PackedStringArray(boxes.map(func(b: Node) -> String:
			return "%s(%d)" % [b.call("placement_key"), int(b.call("hits_left"))])))])

	# --- accept 1012 from Pio ---------------------------------------------------------------------------------------
	var talk: Dictionary = await d.talk_to(PIO)
	if not d.check("Pio can be talked to on foot", bool(talk.get("open", false)), str(talk.get("why", ""))):
		return
	var conv := await _converse("accept")
	d.note("Pio accept pages: %s" % " | ".join(conv))
	if not d.check("1012 accepted through Pio's dialogue", d.character().quests.is_in_progress(QUEST), d.character().quests.status(QUEST)):
		return

	# --- break boxes until 3 + 3 ---------------------------------------------------------------------------------------
	var need := _needs()
	var inv := d.character().inventory
	var t0 := d.game_s()
	var waits := 0
	var unreachable := {}
	while not _collected(need) and d.game_s() - t0 < BREAK_BUDGET_S:
		var box := _nearest_intact(unreachable)
		if box == null:
			# Every box is broken (or out of reach): wait by the one that comes back first, as a player would.
			var first := _first_back(unreachable)
			if first == null:
				d.note("no box left to break or wait for (unreachable: %s)" % str(unreachable.keys()))
				break
			waits += 1
			await d.walk_to(d.walker.grounded(first.global_position + Vector3(0.9, 0, 0)), {"max_s": 25.0, "within_m": 0.6})
			var back := await d.wait_until(func() -> bool: return _nearest_intact(unreachable) != null, 200.0)
			d.note("every box of Amherst broken; waited for the first respawn by %s (%s)" % [first.call("placement_key"),
				"back" if back else "timeout"])
			if not back:
				break
			continue
		var r := await _break_box(box)
		if not bool(r["ok"]):
			d.soft_check("broke box %s with the attack key" % r["key"], false, String(r["why"]))
			if String(r["why"]).begins_with("could not reach"):
				unreachable[String(r["key"])] = true
			continue
		await d.wait(0.6)
		var picked: Dictionary = await d.pickup_all_nearby(5.0, 30.0)
		if int(picked["left"]) > 0:
			await _step_onto_drops(5.0)
			_note_left_drops(String(r["key"]))
	var counts := {}
	for id: String in need:
		counts[id] = inv.count(id)
	d.check("collected the canonical items by breaking boxes and picking up", _collected(need),
		"%s after %d boxes in %.0f s (waits %d)" % [str(counts), broken_rows.size(), d.game_s() - t0, waits])
	var exact := broken_rows.all(func(row: Array) -> bool: return int(row[1]) == _hits())
	d.check("every box broke after exactly %d landed swings (canonical hits_to_break)" % _hits(), exact and not broken_rows.is_empty(),
		"; ".join(PackedStringArray(broken_rows.map(func(row: Array) -> String: return "%s: %d landed / %d swings, %d whiffs" % row))))
	var at_box := loot_events.all(func(e: Array) -> bool: return bool(e[2]))
	d.check("every broken box's drops were announced at the box", at_box, "%d loot events" % loot_events.size())
	if not _collected(need):
		return

	# --- turn in --------------------------------------------------------------------------------------------------------
	var rew: Dictionary = q.get("rewards", {})
	var before := {"mesos": d.character().mesos, "exp_log": exp_log.size()}
	for it: Dictionary in rew.get("items", []):
		before["item_" + String(it.item_id)] = inv.count(String(it.item_id))
	for id: String in need:
		before["need_" + id] = inv.count(id)
	var talk2: Dictionary = await d.talk_to(PIO)
	if not d.check("Pio can be talked to for the turn-in", bool(talk2.get("open", false)), str(talk2.get("why", ""))):
		return
	var conv2 := await _converse("complete")
	d.note("Pio turn-in pages: %s" % " | ".join(conv2))
	await d.wait(0.3)
	d.check("1012 completed at Pio", d.character().quests.is_completed(QUEST), d.character().quests.status(QUEST))
	var handed := PackedStringArray()
	var handed_ok := true
	for id: String in need:
		var delta := int(before["need_" + id]) - inv.count(id)
		handed.append("%s -%d" % [id, delta])
		handed_ok = handed_ok and delta == int(need[id])
	d.check("the quest items were handed in (canonical counts)", handed_ok, ", ".join(handed))
	var events := exp_log.slice(int(before["exp_log"]))
	d.check("EXP reward exactly the canonical %d" % int(rew.get("exp", 0)), events.size() == 1 and int(events[0][0]) == int(rew.get("exp", 0))
		and String(events[0][1]) == "quest:" + QUEST, str(events))
	d.check("meso reward exactly the canonical %d" % int(rew.get("mesos", 0)), d.character().mesos - int(before["mesos"]) == int(rew.get("mesos", 0)),
		"%d -> %d" % [int(before["mesos"]), d.character().mesos])
	for it: Dictionary in rew.get("items", []):
		var id := String(it.item_id)
		var got := inv.count(id) - int(before["item_" + id])
		d.check("received %s (%s) x%d" % [String(it.get("name", id)), id, int(it.get("count", 1))], got == int(it.get("count", 1)),
			"%s: +%d" % [id, got])
	await d.screenshot("after_turn_in")

	# --- not saved: hit a box, then a real reload ------------------------------------------------------------------------
	var last_box := _nearest_intact()
	if last_box != null:
		var r2 := await _break_box(last_box, 2)
		d.carry["hit_key"] = String(r2["key"])
		d.carry["hit_left"] = int(last_box.call("hits_left"))
		d.check("a box took 2 landed hits before the quit", int(last_box.call("hits_left")) == _hits() - 2,
			"%s: %d hits left" % [r2["key"], int(last_box.call("hits_left"))])
	d.carry["broken_keys"] = _boxes().filter(func(b: Node) -> bool: return bool(b.call("is_broken"))).map(
		func(b: Node) -> String: return String(b.call("placement_key")))
	d.note("before the quit: hit box %s, broken %s" % [d.carry.get("hit_key", ""), d.carry["broken_keys"]])
	await d.reload_process()


func _phase1() -> void:
	var cont: Dictionary = await d.continue_game()
	if not d.check("Continue in a new process", bool(cont["ok"]), "%s in %s via %s" % [cont["slot"], cont["map"], cont["via"]]):
		return
	await d.wait_idle(20.0)
	await d.wait(0.5)
	d.check("back in Amherst", d.current_map() == AMHERST, d.current_map())
	var boxes := _boxes()
	var key := String(d.carry.get("hit_key", ""))
	var hit_box: Node = null
	for b: Node in boxes:
		if String(b.call("placement_key")) == key:
			hit_box = b
	d.check("the box hit before the quit stands with all %d hits left (box state is not saved)" % _hits(), hit_box != null
		and not bool(hit_box.call("is_broken")) and int(hit_box.call("hits_left")) == _hits(),
		"%s: %s" % [key, "missing" if hit_box == null else "%d hits left, broken %s" % [int(hit_box.call("hits_left")), hit_box.call("is_broken")]])
	d.check("every box of Amherst is intact after the reload (broken before: %s)" % str(d.carry.get("broken_keys", [])),
		boxes.size() == BreakableRules.placements_of(db.map(AMHERST)).size() and boxes.all(func(b: Node) -> bool: return not bool(b.call("is_broken"))),
		"%d boxes" % boxes.size())
	d.check("1012 stays completed", d.character().quests.is_completed(QUEST), d.character().quests.status(QUEST))


# =================================================================================================================
# Boxes
# =================================================================================================================

## Walks up to `box`, faces it and taps the attack key until it breaks (or `stop_after` landed hits). Landed swings
## are counted from its hits_left. Returns {"ok", "key", "landed", "swings", "whiffs", "why"}.
func _break_box(box: Node, stop_after: int = 0) -> Dictionary:
	var p := d.player()
	var pc := d.combat()
	var key := String(box.call("placement_key"))
	var out := {"ok": false, "key": key, "landed": 0, "swings": 0, "whiffs": 0, "why": ""}
	var stand := _reach_m() * BOX_REACH_SHARE
	var t0 := d.game_s()
	var routed := 0
	var whiff_run := 0
	while not bool(box.call("is_broken")) and d.game_s() - t0 < 60.0:
		if stop_after > 0 and int(out["landed"]) >= stop_after:
			break
		await d.get_tree().process_frame
		d.input.reassert()
		var to: Vector3 = box.global_position - p.global_position
		var dy := absf(to.y)
		to.y = 0.0
		var dist := to.length()
		if dist > 2.5 or dy > 0.8:
			if routed >= 3:
				out["why"] = "could not reach the box (%.1f m away, %.1f m up/down)" % [dist, dy]
				break
			routed += 1
			d.input.release_movement()
			var dir := -to.normalized() if dist > 0.01 else Vector3.BACK
			var spot: Vector3 = d.walker.grounded(box.global_position + dir * stand)
			# A stalled walk is tried again with the other planners (the routes, then the collision grid).
			var planner: String = ["auto", "routes", "grid"][mini(routed - 1, 2)]
			await d.walk_to(spot, {"max_s": 25.0, "retries": 1, "within_m": 0.35, "planner": planner})
			continue
		if dist > stand + 0.2:
			d.input.set_move_world(to.normalized(), p.view_right, p.view_forward)
			continue
		if dist < 0.25:
			# Standing in the (walk-through) box: step back out of it.
			d.input.set_move_world(-p.facing, p.view_right, p.view_forward)
			continue
		d.input.release_movement()
		var face := to.normalized()
		if p.facing.dot(face) < cos(deg_to_rad(15.0)):
			d.input.set_move_world(face * 0.2, p.view_right, p.view_forward)
			await d.get_tree().physics_frame
			await d.get_tree().process_frame
			d.input.release_movement()
			continue
		if not bool(pc.call("can_attack")):
			continue
		var left := int(box.call("hits_left"))
		var swings := int(pc.get("attacks"))
		await d.input.tap_action(&"attack")
		if int(pc.get("attacks")) == swings:
			continue
		out["swings"] = int(out["swings"]) + 1
		if bool(box.call("is_broken")) or int(box.call("hits_left")) < left:
			out["landed"] = int(out["landed"]) + 1
			whiff_run = 0
		else:
			out["whiffs"] = int(out["whiffs"]) + 1
			whiff_run += 1
			if whiff_run >= 3:
				stand = maxf(0.4, stand * 0.8)
				whiff_run = 0
	d.input.release_movement()
	if bool(box.call("is_broken")):
		out["ok"] = true
		broken_rows.append([key, int(out["landed"]), int(out["swings"]), int(out["whiffs"])])
	elif stop_after > 0 and int(out["landed"]) >= stop_after:
		out["ok"] = true
	elif String(out["why"]) == "":
		out["why"] = "still standing after %.0f s (%d landed of %d swings)" % [d.game_s() - t0, int(out["landed"]), int(out["swings"])]
	return out


## How far (m, feet to feet) the current weapon's shortest basic attack reaches a box: its hit boxes' nearest far
## edge plus half the box's body (CombatReach, breakables.json box.touch_px, WorldScale.actor).
func _reach_m() -> float:
	var c := d.character()
	var stats := PlayerCombatStats.from_character(c, db)
	var weapon := stats.weapon if stats.weapon != null else WeaponProfile.bare_hands(db)
	var far := INF
	for action: Variant in weapon.ordinary_actions().keys():
		for pres in weapon.presentations_for(String(action)):
			far = minf(far, CombatReach.attack_box_px(weapon, pres, true, c.level).end.x)
	return WorldScale.actor((0.0 if far == INF else far) + BreakableRules.touch_px(db).x * 0.5)


## The drops pickup_all_nearby left within `radius_m`: the player walks straight onto each (real movement input, as a
## player steps onto an item lying where the box stood) and presses the pickup key. pickup_all_nearby's walk ends
## within the walker's arrival distance, which can stop just outside the canonical pickup box (25 px = 0.625 m).
func _step_onto_drops(radius_m: float) -> void:
	var p := d.player()
	var ls := d.loot()
	for n: Node3D in (ls.call("nodes") as Dictionary).values():
		if not is_instance_valid(n):
			continue
		var landing: Vector3 = n.get("landing")
		var flat := Vector2(landing.x - p.global_position.x, landing.z - p.global_position.z)
		if flat.length() > radius_m or absf(landing.y - p.global_position.y) > 1.0:
			continue
		var t0 := d.game_s()
		while is_instance_valid(n) and d.game_s() - t0 < 3.0:
			var to := landing - p.global_position
			to.y = 0.0
			if to.length() <= 0.25:
				break
			d.input.set_move_world(to.normalized() * clampf(to.length() * 2.0, 0.3, 1.0), p.view_right, p.view_forward)
			await d.get_tree().physics_frame
		d.input.release_movement()
		await d.frames(2)
		if is_instance_valid(n) and not (ls.call("pickup_target", p.global_position, {}) as Dictionary).is_empty():
			await d.input.tap_action(&"pickup")
			await d.frames(2)


## A note on every drop still on the ground (where it landed against where the player stands).
func _note_left_drops(key: String) -> void:
	var p := d.player()
	var rows: PackedStringArray = []
	for n: Node3D in (d.loot().call("nodes") as Dictionary).values():
		var landing: Vector3 = n.get("landing")
		rows.append("%s at (%.2f, %.2f, %.2f) landed %s, player (%.2f, %.2f, %.2f)" % [String(n.get("uid")), landing.x,
			landing.y, landing.z, n.call("is_landed"), p.global_position.x, p.global_position.y, p.global_position.z])
	if not rows.is_empty():
		d.note("drops left after box %s: %s" % [key, "; ".join(rows)])


func _boxes() -> Array:
	return d.get_tree().get_nodes_in_group(&"miso_breakables").filter(
		func(b: Node) -> bool: return String(b.call("map_id")) == d.current_map())


func _nearest_intact(skip: Dictionary = {}) -> Node:
	var best: Node = null
	var best_d := INF
	var p := d.player()
	for b: Node in _boxes():
		if bool(b.call("is_broken")) or skip.has(String(b.call("placement_key"))):
			continue
		var dd := (b as Node3D).global_position.distance_to(p.global_position)
		if dd < best_d:
			best_d = dd
			best = b
	return best


## The broken box of this map that comes back first (the live map instance's respawn times), or null.
func _first_back(skip: Dictionary = {}) -> Node:
	var st: Variant = d.session().get("instance_state")
	if not (st is MapInstanceState):
		return null
	var best: Node = null
	var best_t := INF
	for b: Node in _boxes():
		if not bool(b.call("is_broken")) or skip.has(String(b.call("placement_key"))):
			continue
		var t := (st as MapInstanceState).breakable_respawn_at(int(b.call("index")))
		if t < best_t:
			best_t = t
			best = b
	return best


func _hits() -> int:
	return BreakableRules.hits_to_break(BreakableRules.WOODEN_BOX, db)


## The quest's item objectives: item id -> count (canonical).
func _needs() -> Dictionary:
	var out := {}
	for it: Dictionary in (db.quest(QUEST).get("objectives", {}) as Dictionary).get("item_collection", []):
		out[String(it.item_id)] = int(it.count)
	return out


func _collected(need: Dictionary) -> bool:
	for id: String in need:
		if d.character().inventory.count(id) < int(need[id]):
			return false
	return true


# =================================================================================================================
# Dialogue and the bus
# =================================================================================================================

## Answers Pio's dialogue toward `goal` ("accept" / "complete") for 1012: its menu choice, Yes on its offer, Next on
## every page. Returns the pages seen.
func _converse(goal: String) -> PackedStringArray:
	var c := d.character()
	var pages: PackedStringArray = []
	var v := d.read_dialogue()
	var guard := 0
	while bool(v["open"]) and guard < 40:
		guard += 1
		var view: Dictionary = v["view"]
		var t := String(v["type"])
		pages.append("[%s] %s" % [t, String(v.get("text", "")).replace("\n", " ").left(60)])
		if t == "menu":
			var pick := -1
			var choices: Array = view.get("choices", [])
			for k in choices.size():
				if String((choices[k] as Dictionary).get("quest_id", "")) == QUEST and not _goal_met(goal):
					pick = k
					break
			if pick < 0:
				v = await d.choose("end")
				break
			v = await d.choose(pick)
		elif t == "yes_no":
			v = await d.choose("yes" if goal == "accept" and c.quests.status(QUEST) == QuestLog.NOT_STARTED else "no")
		elif "next" in v["buttons"] or "ok" in v["buttons"]:
			v = await d.next()
		else:
			break
	if d.dialogue_open():
		await d.close_dialogue()
	await d.frames(2)
	return pages


func _goal_met(goal: String) -> bool:
	var c := d.character()
	return c.quests.status(QUEST) != QuestLog.NOT_STARTED if goal == "accept" else c.quests.is_completed(QUEST)


func _connect_bus() -> void:
	d.events().connect(&"exp_gained", func(amount: int, source: String) -> void: exp_log.append([amount, source, d.game_s()]))
	d.events().connect(&"loot_dropped", func(drops: Array, at: Vector3, map_id: String) -> void:
		var near := false
		for b: Node in _boxes():
			if bool(b.call("is_broken")) and (b as Node3D).global_position.distance_to(at) < 0.05:
				near = true
		loot_events.append([drops.size(), map_id, near]))
