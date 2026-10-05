extends PlaytestScenario
## test_d_probe: a measurement run for Test D (not a brief test). A new game, a console warp to a hunting ground,
## then the attack key and the pickup key for a bounded time; notes every drop, meso gain, kill and death, and every
## drop the pickup sweep leaves behind (distance, height), so the real Test D scenario can size its hunting budget
## from measured numbers.

const MAP := "000000050"
const TOWN := "000000060"


func description() -> String:
	return "probe: kills, drops and mesos per game minute in %s" % MAP


func max_seconds() -> float:
	return 1500.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Probe", "male", "585", {"str": 9})
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	await d.console("warp " + MAP)
	await d.wait(1.0)
	var gained := {}
	var mesos := [0]
	var deaths := [0]
	var dropped := {}
	var expired := [0]
	var on_item := func(id: String, q: int) -> void: gained[id] = int(gained.get(id, 0)) + q
	var on_mesos := func(_m: int, delta: int) -> void:
		if delta > 0:
			mesos[0] += delta
	var on_died := func(_m: String) -> void: deaths[0] += 1
	var on_loot := func(list: Array, _at: Vector3, _map: String) -> void:
		for e: Variant in list:
			var k := String((e as Dictionary).get("item_id", "mesos"))
			dropped[k] = int(dropped.get(k, 0)) + 1
	var on_expired := func(_uid: String) -> void: expired[0] += 1
	d.events().connect(&"item_gained", on_item)
	d.events().connect(&"mesos_changed", on_mesos)
	d.events().connect(&"player_died", on_died)
	d.events().connect(&"loot_dropped", on_loot)
	d.loot().connect(&"drop_expired", on_expired)
	var kills := 0
	var t0 := d.game_s()
	var marks: Array = []
	var left_notes := 0
	while d.game_s() - t0 < 900.0:
		if d.game().is_character_dead():
			await d.wait(1.0)
			var ok: Dictionary = await d.click("OK")
			await d.wait_idle(30.0)
			d.note("died at kill %d; OK %s; now in %s" % [kills, ok["ok"], d.current_map()])
			if d.current_map() == TOWN:
				await d.walk_trail(TOWN, MAP)
			continue
		var r: Dictionary = await d.face_and_attack_nearest(20.0)
		if bool(r["ok"]):
			kills += 1
			var pk: Dictionary = await d.pickup_all_nearby(10.0, 25.0)
			if int(pk["left"]) > 0 and left_notes < 12:
				left_notes += 1
				d.note("left after kill %d: %s" % [kills, _left_text(d, 10.0)])
		elif d.nearest_monster() == null:
			await d.wait(1.0)
		if kills > 0 and kills % 10 == 0 and marks.size() < kills / 10:
			marks.append("%d kills at %.0f s: mesos %d, items %s, level %d, hp %d/%d, map %s" % [kills, d.game_s() - t0,
				mesos[0], gained, d.character().level, d.character().hp, int(d.state()["max_hp"]), d.current_map()])
			d.note(marks[-1])
	d.note("TOTAL %d kills in %.0f s, %d deaths, mesos +%d, gained %s, dropped %s, expired %d, level %d, map %s" % [kills,
		d.game_s() - t0, deaths[0], mesos[0], gained, dropped, expired[0], d.character().level, d.current_map()])
	d.check("probe finished", true)


static func _left_text(d: PlaytestDriver, radius: float) -> String:
	var p := d.player().global_position
	var parts: PackedStringArray = []
	for n: Node3D in (d.loot().call("nodes") as Dictionary).values():
		var landing: Vector3 = n.get("landing")
		var flat := Vector2(landing.x - p.x, landing.z - p.z).length()
		if flat > radius:
			continue
		var pl: Dictionary = d.walker.plan(landing)
		parts.append("%s flat %.2f dy %.2f landed %s plan %s" % [String((n.get("record") as Dictionary).get("item_id", "mesos")) if n.get("record") is Dictionary else "?",
			flat, landing.y - p.y, n.call("is_landed"), pl.get("how", "?")])
	return "; ".join(parts)
