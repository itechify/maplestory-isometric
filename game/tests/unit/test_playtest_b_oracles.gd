extends TestCase
## The canonical oracles of the Test B playthrough (game/tools/playtest/scenarios/test_b_combat.gd), checked by hand
## against the published formulas and against the game's own CombatFormula / CombatReach / MeleeQuery, so a pass of
## the scenario means the game agrees with canonical data, not with itself.

const Scenario := preload("res://tools/playtest/scenarios/test_b_combat.gd")
const BASE := {"str": 13, "dex": 4}
const GEAR := {"watk": 17, "str": 0, "dex": 0}


func _oracle() -> Object:
	var s: Object = Scenario.new()
	s.set("db", db())
	s.call("_load_tables")
	return s


func test_damage_window_by_hand() -> void:
	var s := _oracle()
	# MIN = 17 x (0.8 + (13 x 0.08 x 1.8 + 4) / 100) = 14.598; MAX = 17 x (1.0 + (13 x 1.8 + 4) / 100) = 21.658
	assert_eq(s.call("_oracle_window", "2", "swing", 1, false, BASE, GEAR), Vector2i(14, 21), "Sword, STR 13, Snail")
	assert_eq(s.call("_oracle_window", "2", "stab", 1, false, BASE, GEAR), Vector2i(14, 21), "1H sword stab is also x1.8")
	# critical x (1 + 0.2): 17.52 .. 25.99
	assert_eq(s.call("_oracle_window", "2", "swing", 1, true, BASE, GEAR), Vector2i(17, 25), "critical")
	# Orange Mushroom Lv 8 vs Lv 1: gap 7, scale 1 / (1 + 49 x 0.005) = 0.8032 -> 11.73 .. 17.40
	assert_eq(s.call("_oracle_window", "9", "swing", 1, false, BASE, GEAR), Vector2i(11, 17), "level gap 7")
	# same level: no scale
	assert_eq(s.call("_oracle_window", "9", "swing", 8, false, BASE, GEAR), Vector2i(14, 21), "level gap 0")


func test_damage_window_agrees_with_combat_formula() -> void:
	var s := _oracle()
	var c := CharacterState.new()
	c.level = 1
	c.base_stats = {"str": 13, "dex": 4, "int": 4, "luk": 4}
	assert_true(c.equipment.force_equip("weapon", "541", db()), "Sword equipped")
	for lv in [1, 3, 5, 8]:
		c.level = lv
		var stats := PlayerCombatStats.from_character(c, db())
		for mob in ["1", "2", "3", "4", "5", "9"]:
			for action in ["swing", "stab"]:
				for crit in [false, true]:
					var w: Vector2i = s.call("_oracle_window", mob, action, lv, crit, BASE, GEAR)
					var cf := CombatFormula.damage_window(stats, MonsterCombatStats.from_id(mob, db()), db(),
						{"action": action, "critical": crit})
					assert_eq(w, Vector2i(int(cf["min"]), int(cf["max"])), "mob %s %s lv %d crit %s" % [mob, action, lv, crit])


func test_touch_window_by_hand_and_against_combat_formula() -> void:
	var s := _oracle()
	# Orange Mushroom P.DMG 17, Lv 1, WDEF 3: 18.7 x (1 - 3 / (3 + 205 + 22.44)) = 18.46; 25.5 x (1 - 3 / 238.6) = 25.18
	assert_eq(s.call("_oracle_touch", "9", 1, 3), Vector2i(18, 25))
	assert_eq(s.call("_oracle_touch", "2", 1, 3), Vector2i(3, 4), "Snail, MeowDB's 3-4 estimate")
	assert_eq(s.call("_oracle_touch", "1", 1, 3), Vector2i(1, 1), "Tutorial Jr. Sentinel")
	for mob in ["1", "2", "3", "4", "5", "9"]:
		for lv in [1, 4, 8]:
			var r: Vector2i = s.call("_oracle_touch", mob, lv, 3)
			var k := CombatFormula.incoming_damage_range(float(db().monster(mob)["physical_damage"]), 3.0, lv, db())
			assert_eq(r, Vector2i(int(k["taken_min"]), int(k["taken_max"])), "mob %s lv %d" % [mob, lv])


func test_reach_oracle_cases() -> void:
	var s := _oracle()
	var front := {"fwd_px": 40.0, "up_px": 0.0, "lat_px": 0.0}
	var behind_far := {"fwd_px": -40.0, "up_px": 0.0, "lat_px": 0.0}
	var behind_near := {"fwd_px": -16.0, "up_px": 0.0, "lat_px": 0.0}
	var too_far := {"fwd_px": 128.0, "up_px": 0.0, "lat_px": 0.0}
	var lateral_out := {"fwd_px": 40.0, "up_px": 0.0, "lat_px": 50.0}
	var lateral_in := {"fwd_px": 40.0, "up_px": 0.0, "lat_px": 45.0}
	for pres in ["swingO1", "swingO2", "swingO3", "stabO1", "stabO2"]:
		assert_true(s.call("_oracle_overlap", pres, 1, front, "2"), "%s: a Snail 1 m in front" % pres)
		assert_false(s.call("_oracle_overlap", pres, 1, behind_far, "2"), "%s: a Snail 1 m behind" % pres)
		assert_false(s.call("_oracle_overlap", pres, 1, too_far, "2"), "%s: a Snail 3.2 m in front" % pres)
		assert_false(s.call("_oracle_overlap", pres, 1, lateral_out, "2"), "%s: 1.25 m to the side" % pres)
		assert_true(s.call("_oracle_overlap", pres, 1, lateral_in, "2"), "%s: 1.125 m to the side" % pres)
		# swingO2 [-73, -50, 5, 17] reaches 5 px behind the feet: a Snail whose feet are 16 px behind overlaps it
		assert_eq(bool(s.call("_oracle_overlap", pres, 1, behind_near, "2")), pres == "swingO2", "%s: 0.4 m behind" % pres)


func test_reach_oracle_agrees_with_melee_query() -> void:
	var s := _oracle()
	var weapon := WeaponProfile.for_weapon_id("541", db())
	var depth := CombatReach.attack_box_depth_px(db())
	var n := 0
	for mob in ["1", "2", "9"]:
		var tz: Array = db().monster(mob)["touch_zone_px"]
		var touch := Vector2(float(tz[0]), float(tz[1]))
		for pres in ["swingO1", "swingO2", "swingO3", "stabO1", "stabO2"]:
			var box := CombatReach.attack_box_px(weapon, pres, true, 1)
			for fwd in range(-60, 160, 7):
				for lat in range(-70, 71, 9):
					for up in [-40.0, -10.0, 0.0, 30.0]:
						var g := {"fwd_px": float(fwd), "up_px": up, "lat_px": float(lat)}
						var mine: bool = s.call("_oracle_overlap", pres, 1, g, mob)
						var theirs := MeleeQuery.attack_hits(box, depth, Vector3(fwd, up, lat), touch, touch.x)
						assert_eq(mine, theirs, "%s %s at fwd %d lat %d up %.0f" % [mob, pres, fwd, lat, up])
						n += 1
	assert_true(n > 10000, "grid size %d" % n)
