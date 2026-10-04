extends TestCase
## Weapon profiles (families, multipliers, odds), ordinary action selection, hit rectangles and attack timing.


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _weapon_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for id in db().ids("items"):
		if db().item(id).get("weapon", null) is Dictionary:
			out.append(id)
	return out


func test_every_weapon_item_resolves() -> void:
	var ids := _weapon_ids()
	assert_true(ids.size() >= 4, "the Maple Island weapons are in the data")
	for id in ids:
		var w := WeaponProfile.from_item(id, db())
		var item := db().item(id)
		assert_true(w.valid, "%s %s resolves" % [id, w.name])
		assert_eq(w.watk, int(item["stats"]["watk"]), "%s W.ATK" % id)
		assert_eq(w.speed_tier, int(item["weapon"]["attack_speed"]), "%s speed tier" % id)
		assert_true(w.primary_stats.size() > 0, "%s has a primary stat" % id)
		assert_true(w.presentations_for("crouch").size() == 1, "%s has a crouched attack" % id)


func test_multipliers_match_the_item_pages() -> void:
	for id in _weapon_ids():
		var w := WeaponProfile.from_item(id, db())
		var page: Dictionary = db().item(id)["weapon"]["multipliers"]
		if page.has("swing"):
			assert_eq(w.multiplier("swing"), float(page["swing"]), "%s swing" % id)
			assert_eq(w.multiplier("stab"), float(page["stab"]), "%s stab" % id)
		if page.has("firing"):
			assert_eq(w.multiplier("shoot"), float(page["firing"]), "%s projectile" % id)
			var close: Dictionary = CombatRules.of(db()).special_branches["close_range_ranged_swing"]
			assert_eq(float(close["weapon_mult"]), float(page["close_range"]), "%s close range" % id)


func test_families_use_the_right_stats() -> void:
	var expect := {"541": ["str", "dex"], "576": ["str", "dex"], "585": ["str", "dex"], "558": ["luk", "str+dex"],
		"666": ["dex", "str"], "651": ["str", "dex"]}
	for id in expect:
		var w := WeaponProfile.from_item(id, db())
		assert_eq("+".join(w.primary_stats), expect[id][0], "%s primary" % id)
		assert_eq("+".join(w.secondary_stats), expect[id][1], "%s secondary" % id)
	# The Wooden Club shares the wand's hit boxes but not its multiplier (attack_styles.json naming note).
	var club := WeaponProfile.from_item("585", db())
	assert_eq(club.hitzone_set, "mace", "club boxes")
	assert_eq(club.multiplier("swing"), 2.4, "club swings as a 1H blunt weapon")


func test_hit_boxes_match_the_item_pages_and_attack_styles() -> void:
	for id in _weapon_ids():
		var w := WeaponProfile.from_item(id, db())
		for b in db().item(id)["weapon"]["basic_attacks"]:
			var box: Array = b["box_px"]
			var expected := Rect2(float(box[0]), float(box[1]), float(box[2]) - float(box[0]), float(box[3]) - float(box[1]))
			assert_eq(w.hit_box_px(String(b["action"])), expected, "%s %s box" % [id, b["action"]])
	for bw in db().formula("attack_styles")["beginner_weapons"]:
		var w := WeaponProfile.from_item(String(bw["item_id"]), db())
		assert_eq(w.hitzone_set, String(bw["hitzone_set"]), "%s hit-zone set" % bw["name"])


func test_level_100_band_replaces_boxes() -> void:
	var sword := WeaponProfile.from_item("541", db())
	var lvl100: Dictionary = db().formula("attack_styles")["hitzone_sets"][sword.hitzone_set]["level100"]
	var pres: String = lvl100.keys()[0]
	assert_ne(sword.hit_box_px(pres, 99), sword.hit_box_px(pres, 100), "level 100 uses the level100 band")


func test_bare_hands_profile() -> void:
	var bh := WeaponProfile.bare_hands(db())
	var adapt: Dictionary = db().miso_table("combat")["bare_hands"]
	assert_true(bh.is_bare_hands, "flag")
	assert_eq(bh.watk, int(adapt["weapon_watk"]), "W.ATK line from combat.json")
	assert_eq(bh.speed_tier, int(adapt["attack_speed_tier"]), "speed from combat.json")
	assert_eq(bh.ordinary_actions(), {"stab": 1.0}, "Barehanded: Stab 100% (canonical)")
	var boxes: Dictionary = db().formula("beginner")["basic_attack"]["bare_hands"]["hit_boxes_px"]
	for pres in boxes:
		var b: Array = boxes[pres]
		assert_eq(bh.hit_box_px(pres), Rect2(float(b[0]), float(b[1]), float(b[2]) - float(b[0]), float(b[3]) - float(b[1])), "punch box %s" % pres)
	assert_eq(bh.presentations_for("stab"), PackedStringArray(["stabO1", "stabO2"]), "Punch 1 and Punch 2")


func test_ordinary_action_odds_60_40_with_equal_presentations() -> void:
	var sword := WeaponProfile.from_item("541", db())
	var rng := _rng(606)
	var counts := {}
	var swings := 0
	var n := 20000
	for i in n:
		var pick := CombatFormula.choose_ordinary_action(sword, rng)
		counts[pick["presentation"]] = int(counts.get(pick["presentation"], 0)) + 1
		if pick["action"] == "swing":
			swings += 1
			assert_true(String(pick["presentation"]).begins_with("swing"), "swing plays a swing box")
		else:
			assert_true(String(pick["presentation"]).begins_with("stab"), "stab plays a thrust box")
	assert_near(float(swings) / n, 0.6, 0.012, "60% swing")
	assert_eq(counts.size(), 5, "five standing presentations, no crouch")
	for pres in counts:
		assert_near(float(counts[pres]) / n, 0.2, 0.012, "%s ~20%%" % pres)


func test_other_weapon_action_rules() -> void:
	var wand := WeaponProfile.from_item("651", db())
	var bow := WeaponProfile.from_item("666", db())
	var bare := WeaponProfile.bare_hands(db())
	var rng := _rng(1)
	for i in 200:
		var w_pick := CombatFormula.choose_ordinary_action(wand, rng)
		assert_eq(w_pick["presentation"], "swingO2", "wands attack with Swing 2 only")
		var b_pick := CombatFormula.choose_ordinary_action(bare, rng)
		assert_eq(b_pick["action"], "stab", "punches are stabs")
		var close := CombatFormula.choose_ordinary_action(bow, rng, true)
		assert_eq(close["action"], "swing", "a bow always swings at close range")
		var far := CombatFormula.choose_ordinary_action(bow, rng, false)
		assert_eq(far, {"action": "shoot", "presentation": ""}, "a bow shoots at range")
	assert_eq(CombatFormula.crouch_action(WeaponProfile.from_item("541", db())), {"action": "crouch", "presentation": "proneStab"}, "crouched attack")


func test_geometry() -> void:
	var box := Rect2(-102, -50, 80, 40)  # Sword Swing 3, facing left
	assert_eq(CombatReach.mirror_box(box, false), box, "facing left unchanged")
	assert_eq(CombatReach.mirror_box(box, true), Rect2(22, -50, 80, 40), "facing right mirrors x")
	assert_true(CombatReach.boxes_overlap(Rect2(0, 0, 10, 10), Rect2(5, 5, 10, 10)), "overlap")
	assert_false(CombatReach.boxes_overlap(Rect2(0, 0, 10, 10), Rect2(10, 0, 10, 10)), "touching edges do not hit")
	var snail := MonsterCombatStats.from_id("2", db())
	assert_eq(CombatReach.monster_touch_box_px(snail), Rect2(-18.5, -26, 37, 26), "touch zone anchored bottom centre")
	# A Snail standing 60 px to the left of a left-facing Sword Beginner is inside Swing 3 (22-102 px out).
	var sword := WeaponProfile.from_item("541", db())
	var attack := CombatReach.attack_box_px(sword, "swingO3", false)
	assert_true(CombatReach.boxes_overlap(attack, CombatReach.translated(CombatReach.monster_touch_box_px(snail), Vector2(-60, 0))), "in reach")
	assert_false(CombatReach.boxes_overlap(attack, CombatReach.translated(CombatReach.monster_touch_box_px(snail), Vector2(60, 0))), "behind the attacker")
	assert_true(CombatReach.attack_box_depth_px(db()) > 0.0, "isometric depth adaptation")
	assert_eq(CombatReach.touch_zone_depth_px(snail, db()), 37.0, "touch depth = width")


func test_target_order() -> void:
	var picked := CombatReach.pick_targets([
		{"id": "a", "distance": 50.0, "spawn_order": 3},
		{"id": "b", "distance": 20.0, "spawn_order": 9},
		{"id": "c", "distance": 50.0, "spawn_order": 1},
	], 2)
	assert_eq(picked.size(), 2, "mob cap")
	assert_eq(picked[0]["id"], "b", "nearest first")
	assert_eq(picked[1]["id"], "c", "a tie goes to the monster that appeared first")


func test_attack_durations() -> void:
	# Item pages publish the cycle at the weapon's own tier.
	for id in _weapon_ids():
		var item: Dictionary = db().item(id)["weapon"]
		var w := WeaponProfile.from_item(id, db())
		if item.get("attack_cycle_ms", null) != null:
			var action := "shoot" if w.ranged else "swing"
			assert_eq(w.attack_duration_ms(action, db()), int(item["attack_cycle_ms"]), "%s cycle" % id)
		var by_kind: Variant = item.get("attack_cycle_by_kind_ms", null)
		if by_kind is Dictionary:
			for k in by_kind:
				assert_eq(w.attack_duration_ms(String(k), db()), int(by_kind[k]["ms"]), "%s %s cycle" % [id, k])
	var bare := WeaponProfile.bare_hands(db())
	assert_eq(bare.attack_duration_ms("stab", db()), 810, "bare hands at Normal (6)")


func test_timing_model_reproduces_the_ladder() -> void:
	var speed := db().formula("attack_speed")
	var mismatches := {}
	for mm in speed["whole_total_scaling_check"]["mismatches"]:
		mismatches["%d/%s" % [int(mm["tier"]), mm["column"]]] = true
	var bases := {"ordinary_attack_ms": "swing", "spear_stab_ms": "spear_polearm_stab", "crossbow_ms": "crossbow_shot"}
	var r := CombatRules.of(db())
	for row in speed["speed_tiers"]:
		var tier := int(row["tier"])
		for col in bases:
			var model := CombatFormula.animation_time_ms(float(r.base_action_ms[bases[col]]), tier, db())
			var published := int(row[col])
			if mismatches.has("%d/%s" % [tier, col]):
				assert_ne(model, published, "documented mismatch %d/%s" % [tier, col])
			else:
				assert_eq(model, published, "tier %d %s" % [tier, col])
			assert_eq(CombatFormula.attack_duration_ms(tier, bases[col], db()), published, "ladder wins at tier %d %s" % [tier, col])
	assert_eq(CombatFormula.attack_duration_ms(6, "crouched_attack", db()), 720, "crouched attack 700 ms base at Normal: 30 x ceil(700 / 30)")
