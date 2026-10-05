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
## stands intact again with all its hits left (box state is never saved). Three Snails, learned there with the setup
## level's SP through the Skills window and put on key 1, is thrown with its key at the nearest Amherst box until it
## breaks: one landed hit per throw (breakables.json hit_rule), so exactly hits_to_break throws (setup: the shells and
## an MP refill, by console). Then the other 13 placements: setup by console (counted: god mode, so the hunting maps'
## monsters cannot end the tour, and a warp to each map), every box of The Field West of Amherst, the three Amherst
## interiors and Snail Field of Flowers is walked up to and broken with the attack key after exactly hits_to_break
## landed swings. All 19 canonical placements stand in the real game; the 13 of the other five maps are all broken,
## Amherst's six only as far as 1012 needs (three in the 2026-10-05 runs) plus the one Three Snails breaks: 17 boxes
## broken in a run, not 19.

const AMHERST := "000001010"
## The other maps with Wooden Box placements (canonical maps/<id>.json reactors[]), toured in phase 1.
const OTHER_BOX_MAPS := ["000001000", "000001011", "000001012", "000001013", "000001014"]
const PIO := "18"
const QUEST := "1012"
const WEAPON := "585"
const BOX_REACH_SHARE := 0.6
const BREAK_BUDGET_S := 1500.0
## Approach spots around a box (directions) and the height difference (m) a spot may have from the box's feet.
const APPROACH_DIRECTIONS := 8
const APPROACH_DY_M := 0.3

var d: PlaytestDriver = null
var db: ContentDB = null
var bs: Node = null
## Every box broken: [key, landed swings, swings, whiffs].
var broken_rows: Array = []
var loot_events: Array = []
var exp_log: Array = []


func description() -> String:
	return "Pio's quest (1012) with the Wooden Boxes: accept, break boxes with the attack key, pick up 3 Rusty Screws " \
		+ "and 3 Old Wooden Boards, turn in, The Green Relaxer; box state not saved across a real reload; every box of " \
		+ "the other five box maps broken with the attack key"


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
	# Only meaningful when the box really had hits taken before the quit (phase 0 records how many it had left).
	var hit_left_before := int(d.carry.get("hit_left", _hits()))
	d.check("the box hit before the quit (%d hits left then) stands with all %d hits left (box state is not saved)" % [hit_left_before, _hits()],
		hit_box != null and hit_left_before < _hits() and not bool(hit_box.call("is_broken")) and int(hit_box.call("hits_left")) == _hits(),
		"%s: %s" % [key, "missing" if hit_box == null else "%d hits left, broken %s" % [int(hit_box.call("hits_left")), hit_box.call("is_broken")]])
	var broken_before: Array = d.carry.get("broken_keys", [])
	d.check("every box of Amherst is intact after the reload (broken before: %s)" % str(broken_before), not broken_before.is_empty()
		and boxes.size() == BreakableRules.placements_of(db.map(AMHERST)).size() and boxes.all(func(b: Node) -> bool: return not bool(b.call("is_broken"))),
		"%d boxes" % boxes.size())
	d.check("1012 stays completed", d.character().quests.is_completed(QUEST), d.character().quests.status(QUEST))
	await _three_snails_box()
	await _tour_other_maps()


## Three Snails at a Wooden Box (misostory/breakables.json hit_rule, PlayerSkills._hit_box): the setup level's SP
## learns the skill with the Skills window's "+", Set key puts it on key 1, and it is thrown with that key at the
## nearest intact box of Amherst from inside its canonical band (PlaytestKit.throw_at) until the box breaks. Each throw
## that picks the box lands one hit, so it breaks after exactly hits_to_break throws, each paying the level's MP and
## one shell. Setup (logged): the shells and an MP refill.
func _three_snails_box() -> void:
	var k := PlaytestKit.new(d)
	var c := d.character()
	var snails := "0001000"
	var def := SkillDef.of(snails, db)
	if SkillBook.level_of(c, snails) == 0:
		if not d.check("SP to learn Three Snails (the setup level's)", c.sp > 0, "SP %d" % c.sp):
			return
		var ls: Dictionary = await k.learn_skill(snails)
		if not d.check("Three Snails learned with the Skills window's '+'", bool(ls["ok"]), str(ls)):
			return
	var bk: Dictionary = await k.bind_skill(snails, "1")
	if not d.check("Three Snails on key 1 with the Skills window's Set key", bool(bk["ok"]), str(bk)):
		return
	var lv := SkillBook.level_of(c, snails)
	await _setup_throws(String(def.item_cost(lv)["item_id"]), _hits() + 2)
	var box := _nearest_intact()
	if not d.check("an intact Wooden Box in Amherst to throw at", box != null):
		return
	var key := String(box.call("placement_key"))
	var r: Dictionary = await k.throw_at(box as Node3D, {"casts": _hits() + 2, "max_s": 90.0})
	d.check("Three Snails broke box %s after exactly %d landed throws (one hit per throw that picks it)" % [key, _hits()],
		bool(r["killed"]) and int(r["hits"]) == _hits(), "%d throws, %d hits, broken %s %s" % [int(r["casts"]), int(r["hits"]),
			r["killed"], r["why"]], ["skill:0001000", "mechanic:breakable-hit-break-respawn"])
	d.check("each throw spent the level's MP and one shell", int(r["casts"]) > 0
		and int(r["shells0"]) - int(r["shells1"]) == int(r["casts"]) and int(r["mp0"]) - int(r["mp1"]) == int(r["casts"]) * def.mp_cost(lv),
		"%d casts: shells %d -> %d, MP %d -> %d" % [int(r["casts"]), int(r["shells0"]), int(r["shells1"]), int(r["mp0"]), int(r["mp1"])],
		["skill:0001000"])


func _setup_throws(shell: String, n: int) -> void:
	await d.console("give %s %d" % [shell, n])
	await d.console("heal")


## Every box of the other five maps, broken with the attack key (nearest first; each placement once).
func _tour_other_maps() -> void:
	await d.console("god on")
	for m: String in OTHER_BOX_MAPS:
		await d.console("warp " + m)
		await d.wait_idle(20.0)
		await d.wait(0.5)
		var canon := BreakableRules.placements_of(db.map(m)).size()
		var boxes := _boxes()
		d.check("%s shows its %d canonical Wooden Boxes, intact" % [m, canon], d.current_map() == m and boxes.size() == canon
			and boxes.all(func(b: Node) -> bool: return not bool(b.call("is_broken")) and int(b.call("hits_left")) == _hits()),
			"%d boxes in %s" % [boxes.size(), d.current_map()])
		var done := {}
		var rows: PackedStringArray = []
		var all_ok := true
		while true:
			var box := _nearest_intact(done)
			if box == null:
				break
			var at := (box as Node3D).global_position
			var r := await _break_box(box, 0, 45.0)
			done[String(r["key"])] = true
			var good := bool(r["ok"]) and int(r["landed"]) == _hits()
			all_ok = all_ok and good
			rows.append("%s at (%.1f, %.1f, %.1f): %s" % [r["key"], at.x, at.y, at.z, "%d landed / %d swings, %d whiffs" % [r["landed"],
				r["swings"], r["whiffs"]] if bool(r["ok"]) else String(r["why"])])
		d.check("%s: every box walked up to and broken after exactly %d landed swings" % [m, _hits()], all_ok and done.size() == canon,
			"; ".join(rows))


# =================================================================================================================
# Boxes
# =================================================================================================================

## Walks up to `box`, faces it and taps the attack key until it breaks (or `stop_after` landed hits). Landed swings
## are counted from its hits_left. `walk_s` bounds each walk (the hunting maps' boxes can be 100 m away). Returns
## {"ok", "key", "landed", "swings", "whiffs", "why"}.
func _break_box(box: Node, stop_after: int = 0, walk_s: float = 25.0) -> Dictionary:
	var p := d.player()
	var pc := d.combat()
	var key := String(box.call("placement_key"))
	var out := {"ok": false, "key": key, "landed": 0, "swings": 0, "whiffs": 0, "why": ""}
	var stand := _reach_m() * BOX_REACH_SHARE
	var t0 := d.game_s()
	var routed := 0
	var whiff_run := 0
	var spots: Array = []
	while not bool(box.call("is_broken")) and d.game_s() - t0 < maxf(60.0, walk_s * 4.0):
		if stop_after > 0 and int(out["landed"]) >= stop_after:
			break
		await d.get_tree().process_frame
		d.input.reassert()
		var to: Vector3 = box.global_position - p.global_position
		var dy := absf(to.y)
		to.y = 0.0
		var dist := to.length()
		if dist > 2.5 or dy > 0.8:
			if routed == 0:
				spots = _approach_spots(box, stand)
			if routed >= mini(4, spots.size()):
				out["why"] = "could not reach the box (%.1f m away, %.1f m up/down; %d approach spots)" % [dist, dy, spots.size()]
				break
			# Each try walks to another spot beside the box on its own ground (a walk can end on a prop's top above a
			# spot: the arrival test is horizontal), with the next planner (the routes, then the collision grid).
			var spot: Vector3 = spots[routed]
			routed += 1
			d.input.release_movement()
			var planner: String = ["auto", "routes", "grid", "auto"][mini(routed - 1, 3)]
			await d.walk_to(spot, {"max_s": walk_s, "retries": 1, "within_m": 0.35, "planner": planner})
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
		if d.phase == 0 and broken_rows.size() < 3 and int(out["swings"]) == 0 and stop_after == 0:
			await d.screenshot("box_%d_before_hit" % (broken_rows.size() + 1))
		await d.input.tap_action(&"attack")
		if int(pc.get("attacks")) == swings:
			continue
		out["swings"] = int(out["swings"]) + 1
		if bool(box.call("is_broken")) or int(box.call("hits_left")) < left:
			out["landed"] = int(out["landed"]) + 1
			whiff_run = 0
			if d.phase == 0 and broken_rows.is_empty() and (int(out["landed"]) == 1 or bool(box.call("is_broken"))):
				await d.frames(3)
				await d.screenshot("box_hit_%d" % int(out["landed"]))
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


## Spots `stand` m around `box` in APPROACH_DIRECTIONS directions whose ground is the box's own (within APPROACH_DY_M)
## and where the body fits, nearest to the player first (the first one faces the player, as a walk-up would).
func _approach_spots(box: Node, stand: float) -> Array:
	var p := d.player()
	var feet: Vector3 = (box as Node3D).global_position
	var away := p.global_position - feet
	away.y = 0.0
	var base := away.normalized() if away.length() > 0.01 else Vector3.BACK
	var out: Array = []
	for k in APPROACH_DIRECTIONS:
		var spot: Vector3 = d.walker.grounded(feet + base.rotated(Vector3.UP, TAU * k / APPROACH_DIRECTIONS) * stand)
		if absf(spot.y - feet.y) <= APPROACH_DY_M and d.walker.standable(spot):
			out.append(spot)
	var from := p.global_position
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(from) < b.distance_to(from))
	if out.is_empty():
		out.append(d.walker.grounded(feet + base * stand))
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
