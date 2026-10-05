extends TestCase
## CombatFormula outgoing stages, one by one, then the whole pipeline (brief: Beginner, no mastery, representative
## weapons, swing/stab, min/max, seeded rolls, defense, levels, misses, criticals, clamping).


func _beginner(level: int, ap: Dictionary, weapon_id: String) -> PlayerCombatStats:
	var watk := int(db().item(weapon_id)["stats"]["watk"]) if weapon_id != "" else 0
	var hm := Progression.base_max_hp_mp("beginner", level, db())
	var snap := StatCalculator.compute("beginner", level, ap, int(hm["max_hp"]), int(hm["max_mp"]), {"watk": watk}, weapon_id, db())
	return StatCalculator.player_stats_from(snap, WeaponProfile.for_weapon_id(weapon_id, db()))


func _lv1(weapon_id: String) -> PlayerCombatStats:
	return _beginner(1, {"str": 13, "dex": 4, "int": 4, "luk": 4}, weapon_id)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# --- mastery -----------------------------------------------------------------------------------------------------

func test_no_mastery_is_the_published_factor() -> void:
	assert_near(CombatFormula.mastery_factor(0, db()), CombatRules.of(db()).no_mastery_factor, 1e-12, "M at mastery 0")
	assert_near(CombatFormula.mastery_factor(10, db()), 0.88, 1e-12, "M at mastery 10")
	assert_near(CombatFormula.mastery_factor(-3, db()), CombatFormula.mastery_factor(0, db()), 1e-15, "clamped below 0")
	assert_near(CombatFormula.mastery_factor(25, db()), CombatFormula.mastery_factor(10, db()), 1e-15, "clamped above 10")


func test_beginner_has_no_mastery() -> void:
	var s := _lv1("541")
	assert_eq(s.mastery_level, 0, "Beginner mastery level")
	var p := CombatFormula.physical_attack(s, "swing", db())
	assert_near(p.mastery, CombatRules.of(db()).no_mastery_factor, 1e-12, "Beginner M")


func test_mastery_raises_min_only() -> void:
	var s := _lv1("541")
	var low := CombatFormula.calculate_physical_range(CombatFormula.physical_attack(s, "swing", db()))
	s.mastery_level = 10
	var high := CombatFormula.calculate_physical_range(CombatFormula.physical_attack(s, "swing", db()))
	assert_true(float(high["min"]) > float(low["min"]), "mastery raises MIN")
	assert_near(float(high["max"]), float(low["max"]), 1e-9, "mastery leaves MAX")


# --- raw roll ----------------------------------------------------------------------------------------------------

func test_min_max_match_the_published_formula() -> void:
	# MIN = S x W x (0.8 + (P x M x Wm + Sec) / 100 + AP / 50); MAX = S x W x (1.0 + (P x Wm + Sec) / 100 + AP / 50)
	var s := _beginner(10, {"str": 58, "dex": 4, "int": 4, "luk": 4}, "576")
	s.attack_power = 6
	var p := CombatFormula.physical_attack(s, "swing", db(), 150.0)
	var r := CombatFormula.calculate_physical_range(p)
	var m := 0.08
	var expected_min := 1.5 * 17 * (0.8 + (58 * m * 2.4 + 4) / 100.0 + 6 / 50.0)
	var expected_max := 1.5 * 17 * (1.0 + (58 * 2.4 + 4) / 100.0 + 6 / 50.0)
	assert_near(float(r["min"]), expected_min, 1e-9, "MIN")
	assert_near(float(r["max"]), expected_max, 1e-9, "MAX")
	var expected_avg := 1.5 * 17 * (0.9 + (58 * (m + 1) / 2.0 * 2.4 + 4) / 100.0 + 6 / 50.0)
	assert_near(float(r["avg"]), expected_avg, 1e-9, "published Average")


func test_representative_weapons_and_actions() -> void:
	# Sword: swing = stab (1.8); Hand Axe / Wooden Club: swing 2.4 > stab 1.2; Razor (dagger): stab 2.0 > swing 1.0.
	var sword := _lv1("541")
	var axe := _lv1("576")
	var club := _lv1("585")
	var razor := _beginner(5, {"str": 33, "dex": 4, "int": 4, "luk": 4}, "558")
	assert_near(CombatFormula.physical_attack(sword, "swing", db()).weapon_mult, CombatFormula.physical_attack(sword, "stab", db()).weapon_mult, 0.0, "sword swing = stab")
	for s in [axe, club]:
		var sw := CombatFormula.calculate_physical_range(CombatFormula.physical_attack(s, "swing", db()))
		var st := CombatFormula.calculate_physical_range(CombatFormula.physical_attack(s, "stab", db()))
		assert_true(float(sw["max"]) > float(st["max"]), "%s swing hits harder" % s.weapon.name)
		assert_true(float(st["min"]) < float(sw["min"]), "%s stab has the lower MIN" % s.weapon.name)
	var rsw := CombatFormula.calculate_physical_range(CombatFormula.physical_attack(razor, "swing", db()))
	var rst := CombatFormula.calculate_physical_range(CombatFormula.physical_attack(razor, "stab", db()))
	assert_true(float(rst["max"]) > float(rsw["max"]), "dagger stab hits harder")
	assert_eq(razor.primary(), 4.0, "dagger primary is LUK")
	assert_eq(razor.secondary(), 37.0, "dagger secondary is STR + DEX")
	# Split weapons: the window is the lowest MIN and the highest MAX across swing and stab.
	var win := CombatFormula.damage_window(axe, null, db())
	var asw := CombatFormula.calculate_physical_range(CombatFormula.physical_attack(axe, "swing", db()))
	var ast := CombatFormula.calculate_physical_range(CombatFormula.physical_attack(axe, "stab", db()))
	assert_eq(win["min"], int(minf(float(asw["min"]), float(ast["min"]))), "axe window MIN = stab MIN")
	assert_eq(win["max"], int(maxf(float(asw["max"]), float(ast["max"]))), "axe window MAX = swing MAX")


func test_roll_uses_two_independent_draws() -> void:
	var s := _lv1("541")
	var p := CombatFormula.physical_attack(s, "swing", db())
	var a := _rng(1234)
	var b := _rng(1234)
	var got := CombatFormula.roll_physical_damage(p, a)
	var u1 := b.randf()
	var u2 := b.randf()
	assert_near(got, CombatFormula.raw_physical_roll(p, u1, u2), 1e-12, "raw = f(B draw, Q draw)")
	assert_eq(a.randf(), b.randf(), "exactly two draws consumed")


func test_seeded_rolls_are_deterministic_and_inside_the_window() -> void:
	var s := _lv1("576")
	var p := CombatFormula.physical_attack(s, "swing", db())
	var w := CombatFormula.calculate_physical_range(p)
	var a := _rng(99)
	var b := _rng(99)
	var c := _rng(100)
	var differs := false
	for i in 200:
		var x := CombatFormula.roll_physical_damage(p, a)
		var y := CombatFormula.roll_physical_damage(p, b)
		var z := CombatFormula.roll_physical_damage(p, c)
		assert_eq(x, y, "same seed, same roll %d" % i)
		differs = differs or x != z
		assert_between(x, float(w["min"]), float(w["max"]), "roll inside [MIN, MAX]")
	assert_true(differs, "another seed gives other rolls")


func test_two_draw_distribution_is_centre_heavy() -> void:
	# B and Q are independent: their sum is trapezoid-shaped, not uniform over [MIN, MAX]. For the level-1 Sword
	# Beginner both draws span about 3.5 damage, so the shape is close to a triangle (uniform: middle half 0.5,
	# each 10% tail 0.1; triangle: 0.75 and 0.02).
	var s := _lv1("541")
	var p := CombatFormula.physical_attack(s, "swing", db())
	var w := CombatFormula.calculate_physical_range(p)
	var lo := float(w["min"])
	var span := float(w["max"]) - lo
	var rng := _rng(424242)
	var n := 20000
	var middle := 0
	var low_tail := 0
	var high_tail := 0
	var total := 0.0
	for i in n:
		var t := (CombatFormula.roll_physical_damage(p, rng) - lo) / span
		total += t
		if t >= 0.25 and t <= 0.75:
			middle += 1
		if t < 0.1:
			low_tail += 1
		if t > 0.9:
			high_tail += 1
	var mid_frac := float(middle) / n
	assert_true(mid_frac > 0.68, "middle half holds %.3f of rolls (uniform: 0.5)" % mid_frac)
	assert_true(float(low_tail) / n < 0.04, "low 10%% tail %.3f (uniform: 0.1)" % (float(low_tail) / n))
	assert_true(float(high_tail) / n < 0.04, "high 10%% tail %.3f (uniform: 0.1)" % (float(high_tail) / n))
	var mean_raw := lo + span * total / n
	assert_near(mean_raw, float(w["avg"]), 0.01 * float(w["avg"]), "mean = published average")


# --- special branches --------------------------------------------------------------------------------------------

func test_special_branches_come_from_data() -> void:
	var branches := CombatRules.of(db()).special_branches
	var s := _lv1("541")
	var crouch := CombatFormula.physical_attack(s, "crouch", db())
	var cb: Dictionary = branches["crouched_attack"]
	assert_eq(crouch.branch, "crouched_attack", "crouch branch")
	assert_eq(crouch.weapon_mult, float(cb["weapon_mult"]), "crouch multiplier")
	assert_eq(crouch.stat_div, float(cb["stat_div"]), "crouch StatDiv")
	assert_eq(crouch.ap_div, float(cb["ap_div"]), "crouch APDiv")
	assert_eq(crouch.base_roll_min, float(cb["base_roll"]["min"]), "crouch B min")
	assert_eq(crouch.base_roll_max, float(cb["base_roll"]["max"]), "crouch B max")
	var bow := PlayerCombatStats.new()
	bow.weapon = WeaponProfile.from_item("666", db())
	bow.totals = {"str": 10, "dex": 40, "int": 4, "luk": 4}
	bow.total_watk = 42
	assert_eq(bow.primary(), 40.0, "bow primary DEX")
	var shot := CombatFormula.physical_attack(bow, "shoot", db())
	assert_eq(shot.branch, "ranged_projectile", "bow shot branch")
	assert_eq(shot.weapon_mult, float(branches["ranged_projectile"]["weapon_mult"]), "projectile multiplier")
	var close_swing := CombatFormula.physical_attack(bow, "swing", db())
	assert_eq(close_swing.branch, "close_range_ranged_swing", "bow whack")
	assert_eq(close_swing.stat_div, float(branches["close_range_ranged_swing"]["stat_div"]), "close swing StatDiv")
	assert_eq(close_swing.ap_div, float(branches["close_range_ranged_swing"]["ap_div"]), "close swing APDiv")
	var close_stab := CombatFormula.physical_attack(bow, "stab", db())
	assert_eq(close_stab.ap_div, float(branches["close_range_ranged_stab"]["ap_div"]), "close stab keeps APDiv")
	var l7 := CombatFormula.physical_attack(s, "mixed", db(), 100.0, "lucky_seven")
	assert_eq(l7.weapon_mult, float(branches["lucky_seven"]["weapon_mult"]), "Lucky Seven multiplier")
	assert_eq(l7.mastery, float(branches["lucky_seven"]["mastery_factor"]), "Lucky Seven M")
	# Not every weapon behaves the same: a bow's window is its projectile, a sword's is swing/stab.
	assert_true(bow.weapon.ordinary_actions(false).has("shoot"), "bow shoots at range")
	assert_true(bow.weapon.ordinary_actions(true).has("swing"), "bow whacks at close range")


# --- defense, element, level, critical, clamp -------------------------------------------------------------------

func test_physical_defense_curve() -> void:
	assert_near(CombatFormula.apply_defense(100.0, 0), 100.0, 1e-12, "no DEF")
	assert_near(CombatFormula.apply_defense(100.0, 30), 100.0 * 100.0 / 130.0, 1e-12, "DEF 30")
	assert_near(CombatFormula.apply_defense(100.0, 30, true), 100.0, 0.0, "bypass proc ignores DEF")
	assert_eq(CombatFormula.effective_defense(10, 0, 50), 15, "percent bonus, truncated")
	assert_eq(CombatFormula.effective_defense(10, 3, 25), 15, "flat + trunc(12.5)")
	assert_eq(CombatFormula.effective_defense(10, -20, 0), 0, "never below 0")
	assert_near(CombatFormula.apply_defense_expected(100.0, 30, 0.2), 100.0 * (0.8 * 100.0 / 130.0 + 0.2), 1e-12, "expected bypass")


func test_magic_damage_path() -> void:
	var r := CombatFormula.calculate_magic_range(150.0, 50.0, 100.0, 10.0, db())
	var m := CombatFormula.mastery_factor(10, db())
	assert_near(float(r["min"]), 1.5 * 50.0 * (1.0 + 100.0 * m / 100.0), 1e-9, "magic MIN")
	assert_near(float(r["max"]), 1.5 * 50.0 * (1.0 + 100.0 / 100.0), 1e-9, "magic MAX")
	var a := _rng(5)
	var b := _rng(5)
	var got := CombatFormula.roll_magic_damage(150.0, 50.0, 100.0, 10.0, a, db())
	assert_near(got, float(r["min"]) + (float(r["max"]) - float(r["min"])) * b.randf(), 1e-9, "one uniform draw")
	assert_eq(a.randf(), b.randf(), "exactly one draw")
	assert_eq(CombatFormula.magic_total(9, 3, db()), 4 + 3, "MagicTotal = floor(INT / 2) + MATK")
	# Magic uses M.DEF: Red Snail (M.DEF 30) takes less than a target without it.
	var mage := PlayerCombatStats.new()
	mage.level = 10
	mage.weapon = WeaponProfile.bare_hands(db())
	mage.totals = {"str": 4, "dex": 4, "int": 100, "luk": 4}
	mage.magic_total = 50
	mage.spell_mastery_level = 10
	var red := MonsterCombatStats.from_id("5", db())
	var res := CombatFormula.resolve_magic_hit(mage, red, 150.0, _rng(3), db())
	assert_eq(res.effective_def, 30, "Red Snail M.DEF")
	assert_near(res.after_defense, res.raw * 100.0 / 130.0, 1e-9, "magic defense curve")
	assert_between(res.raw, float(r["min"]), float(r["max"]), "spell roll in window")


func test_elements() -> void:
	assert_eq(CombatFormula.element_relation("", "fire"), "neutral", "no affinity")
	assert_eq(CombatFormula.element_relation("fire", "fire"), "weak", "weak")
	assert_eq(CombatFormula.element_relation("ice|fire-strong", "fire"), "resistant", "resistant")
	assert_eq(CombatFormula.element_relation("fire-immune", "fire"), "immune", "immune")
	assert_eq(CombatFormula.element_relation("fire", ""), "neutral", "no attack element")
	assert_eq(CombatFormula.element_multiplier("immune", db()), 0.0, "immune 0")
	assert_eq(CombatFormula.element_multiplier("resistant", db()), 0.75, "resistant 0.75")
	assert_eq(CombatFormula.element_multiplier("neutral", db()), 1.0, "neutral 1")
	assert_eq(CombatFormula.element_multiplier("weak", db()), 1.25, "weak 1.25")
	assert_eq(CombatFormula.element_multiplier("something else", db()), 1.0, "other results count as 1.0")
	var results := {}
	for a in ["immune", "resistant", "neutral", "weak"]:
		for b in ["immune", "resistant", "neutral", "weak"]:
			results[CombatFormula.composition_multiplier(a, b, db())] = true
	var published: Array = []
	for row in db().formula("damage")["elements"]["result_table"]:
		published.append(float(row["multiplier"]))
	var got: Array = results.keys()
	got.sort()
	published.sort()
	assert_eq(got, published, "composition yields MeowDB's 7 results")
	assert_eq(CombatFormula.apply_element(80.0, 1.25), 100.0, "apply")


func test_level_scaling_cases() -> void:
	assert_eq(CombatFormula.level_scale(10, 7, db()), 1.0, "lower-level target")
	assert_eq(CombatFormula.level_scale(10, 10, db()), 1.0, "same-level target")
	assert_near(CombatFormula.level_scale(10, 13, db()), 1.0 / (1.0 + 9 * 0.005), 1e-12, "slightly higher (gap 3)")
	assert_near(CombatFormula.level_scale(1, 8, db()), 1.0 / (1.0 + 49 * 0.005), 1e-12, "Orange Mushroom vs Lv1 (gap 7)")
	assert_near(CombatFormula.level_scale(10, 19, db()), 1.0 / (1.0 + 81 * 0.005), 1e-12, "gap 9: square branch")
	assert_near(CombatFormula.level_scale(10, 20, db()), 1.0 / (1.0 + 10 * 0.05), 1e-12, "gap 10: linear branch")
	assert_near(CombatFormula.level_scale(10, 35, db()), 1.0 / (1.0 + 25 * 0.05), 1e-12, "much higher (gap 25)")
	assert_near(CombatFormula.apply_level_scaling(1000.0, 10, 15, db()), 1000.0 / 1.125, 1e-9, "/formulas example 888.889")


func test_criticals_are_independent() -> void:
	assert_eq(CombatFormula.base_crit_rate(db()), 0.05, "base c")
	assert_eq(CombatFormula.base_crit_damage(db()), 0.2, "base d")
	assert_near(CombatFormula.apply_critical(100.0, true, 0.2), 120.0, 1e-12, "x (1 + d)")
	assert_near(CombatFormula.apply_critical(100.0, true, 0.5), 150.0, 1e-12, "higher crit damage, same rule")
	assert_eq(CombatFormula.apply_critical(100.0, false, 0.5), 100.0, "no crit")
	assert_near(CombatFormula.expected_with_critical(1000.0, 0.05, 0.2), 1010.0, 1e-9, "Normal x (1 + c x d)")
	var always := _rng(1)
	var never := _rng(1)
	for i in 50:
		assert_true(CombatFormula.roll_critical(1.0, always), "rate 1 always crits")
		assert_false(CombatFormula.roll_critical(0.0, never), "rate 0 never crits")
	# Observed rate follows c.
	var rng := _rng(77)
	var crits := 0
	for i in 20000:
		if CombatFormula.roll_critical(0.05, rng):
			crits += 1
	assert_near(float(crits) / 20000.0, 0.05, 0.006, "observed crit rate")


func test_skill_modifiers_and_final_clamp() -> void:
	assert_near(CombatFormula.apply_skill_modifiers(100.0, 0.8), 80.0, 1e-12, "skill multiplier")
	assert_eq(CombatFormula.finalize_damage(0.3, db()), 1, "tiny hit clamps to 1")
	assert_eq(CombatFormula.finalize_damage(17.99, db()), 17, "trunc, not round")
	assert_eq(CombatFormula.finalize_damage(250000.0, db()), 99999, "damage cap")


# --- hit check and misses ----------------------------------------------------------------------------------------

func test_hit_check_terms() -> void:
	# /formulas Try-values defaults: ACC 100, levels 50/50, EVA 20 -> 100% (accuracy.json parity_examples).
	var acc := CombatFormula.calculate_accuracy(100, 50, 50, 20, db())
	assert_eq(acc["chance"], 1.0, "default example hits")
	var ex: Dictionary = db().formula("accuracy")["parity_examples"][0]
	var f: float = acc["f"]
	assert_near(float(acc["A"]) * (1.0 - f), float(ex["accuracy_roll"][0]), 0.005, "accuracy roll low")
	assert_near(float(acc["A"]) * (1.0 + f), float(ex["accuracy_roll"][1]), 0.005, "accuracy roll high")
	assert_eq(CombatFormula.outgoing_hit_chance(0, 10, 10, 5, db()), 0.0, "ACC 0 never hits an evasive target")
	assert_eq(CombatFormula.outgoing_hit_chance(0, 10, 10, 0, db()), 1.0, "EVA 0 is always hit")
	var auto := CombatFormula.calculate_accuracy(200, 10, 10, 5, db())
	assert_true(bool(auto["auto_hit"]), "big accuracy lead skips the roll")
	assert_eq(auto["auto_hit_threshold"], 25.0, "same level: D >= 25")
	var higher := CombatFormula.calculate_accuracy(200, 10, 14, 5, db())
	assert_near(float(higher["auto_hit_threshold"]), 25.0 + 4 * (0.5 * 10 + 15), 1e-12, "D >= 25 + L x (0.5 x PlayerLevel + 15)")
	assert_near(float(higher["A"]), 200.0 * 100.0 / (10 * 4 + 255), 1e-12, "A = ACC x 100 / (10L + 255)")
	var no_auto := CombatFormula.calculate_accuracy(200, 10, 10, 5, db(), false)
	assert_false(bool(no_auto["auto_hit"]), "auto hit can be disabled")


func test_misses_follow_the_hit_chance() -> void:
	var s := _lv1("541")
	var target := MonsterCombatStats.from_id("2", db())
	target.avoid = 3  # a hypothetical evasive Snail (no Maple Island monster has AVOID)
	var acc := CombatFormula.calculate_accuracy(s.acc, s.level, target.level, target.avoid, db())
	var chance: float = acc["chance"]
	assert_true(chance > 0.0 and chance < 1.0, "a real chance to miss: %s" % chance)
	var rng := _rng(2024)
	var misses := 0
	var n := 20000
	var f: float = acc["f"]
	for i in n:
		var res := CombatFormula.resolve_physical_hit(s, target, "swing", rng, db())
		assert_between(res.hit_roll, 1.0 - f, 1.0 + f, "R = uniform(1 - f, 1 + f) is recorded")
		assert_eq(res.missed, float(acc["A"]) * res.hit_roll < float(acc["mob_eva"]), "hit when A x R >= MobEVA")
		if res.missed:
			misses += 1
			assert_eq(res.final, 0, "a miss deals nothing")
			assert_eq(res.miss_reason, "accuracy", "miss reason")
			assert_eq(res.stages().size(), 1, "a miss stops after the hit check")
	assert_near(float(misses) / n, 1.0 - chance, 0.012, "observed miss rate")


func test_darkness_is_a_separate_check() -> void:
	var s := _lv1("541")
	s.darkness_pct = 100.0
	var res := CombatFormula.resolve_physical_hit(s, MonsterCombatStats.from_id("2", db()), "swing", _rng(1), db())
	assert_true(res.missed, "full darkness always misses")
	assert_eq(res.miss_reason, "darkness", "after a hit roll that passed")
	assert_eq(res.hit_chance, 1.0, "darkness does not lower the hit chance")


# --- whole pipeline ----------------------------------------------------------------------------------------------

func test_pipeline_records_every_stage() -> void:
	var s := _lv1("541")
	s.crit_rate = 1.0
	var mush := MonsterCombatStats.from_id("9", db())
	var res := CombatFormula.resolve_physical_hit(s, mush, "stab", _rng(11), db(), {"presentation": "stabO1"})
	assert_false(res.missed, "Orange Mushroom has no AVOID")
	assert_eq(res.presentation, "stabO1", "presentation recorded")
	assert_between(res.raw, res.range_min, res.range_max, "raw in window")
	assert_near(res.after_defense, res.raw, 1e-12, "P.DEF 0")
	assert_near(res.after_element, res.after_defense, 1e-12, "neutral")
	assert_near(res.level_scale, 1.0 / (1.0 + 49 * 0.005), 1e-12, "gap 7")
	assert_near(res.after_level, res.after_element * res.level_scale, 1e-12, "level stage")
	assert_true(res.critical, "crit rate 1")
	assert_near(res.after_critical, res.after_level * 1.2, 1e-9, "base crit damage")
	assert_eq(res.final, int(res.after_skill), "final = trunc")
	var names: Array = []
	for st in res.stages():
		names.append(st["stage"])
	assert_eq(names, ["hit_check", "raw_roll", "defense", "element", "level_gap", "critical", "skill_modifiers", "final_clamp"], "stage order")
	assert_true(res.knockback, "KB 1: every landed hit staggers")
	assert_has(res.to_dict(), "after_critical", "debug dict")


func test_pipeline_is_deterministic_per_seed() -> void:
	var s := _lv1("576")
	var target := MonsterCombatStats.from_id("5", db())
	for seed_value in [1, 2, 3, 99]:
		var a := CombatFormula.resolve_physical_hit(s, target, "swing", _rng(seed_value), db())
		var b := CombatFormula.resolve_physical_hit(s, target, "swing", _rng(seed_value), db())
		assert_eq(a.to_dict(), b.to_dict(), "seed %d" % seed_value)


func test_damage_window_vs_lower_same_and_higher_levels() -> void:
	var s := _lv1("541")
	var snail := CombatFormula.damage_window(s, MonsterCombatStats.from_id("2", db()), db())
	var red := CombatFormula.damage_window(s, MonsterCombatStats.from_id("5", db()), db())
	var mush := CombatFormula.damage_window(s, MonsterCombatStats.from_id("9", db()), db())
	assert_eq([snail["min"], snail["max"]], [14, 21], "same level: the stat window (oracles.md)")
	assert_eq([red["min"], red["max"]], [13, 20], "Red Snail, gap 3 (oracles.md)")
	assert_eq([mush["min"], mush["max"]], [11, 17], "Orange Mushroom, gap 7 (oracles.md)")
	var strong := _beginner(10, {"str": 58, "dex": 4, "int": 4, "luk": 4}, "541")
	var low := CombatFormula.damage_window(strong, MonsterCombatStats.from_id("2", db()), db())
	var own := CombatFormula.damage_window(strong, null, db())
	assert_eq([low["min"], low["max"]], [own["min"], own["max"]], "lower-level target: no bonus, no penalty")


func test_bare_hands_punch_deals_the_clamp_minimum() -> void:
	var s := _lv1("")
	assert_true(s.weapon.is_bare_hands, "no weapon")
	var res := CombatFormula.resolve_physical_hit(s, MonsterCombatStats.from_id("2", db()), "stab", _rng(8), db())
	assert_eq(res.raw, 0.0, "TotalWATK 0 -> raw 0")
	assert_eq(res.final, 1, "final clamp gives 1")
	var win := CombatFormula.damage_window(s, null, db())
	assert_eq([win["min"], win["max"]], [1, 1], "bare-hands window 1-1")


func test_three_snails_fixed_damage() -> void:
	var s := _lv1("541")
	var mush := MonsterCombatStats.from_id("9", db())
	var dmg := float(db().formula("beginner")["skills"][0]["levels"][0]["fixed_damage"])
	var res := CombatFormula.resolve_fixed_damage(s, mush, dmg, "0001000", _rng(4), db())
	assert_eq(res.kind, "fixed", "kind")
	assert_eq(res.final, int(dmg), "fixed value is not scaled by level gap or crit")
	assert_eq(res.level_scale, 1.0, "no level gap")
	assert_false(res.critical, "no critical")


func test_a_record_without_a_weapon_fights_bare_handed() -> void:
	var s := PlayerCombatStats.new()
	s.level = 1
	s.totals = {"str": 13, "dex": 4, "int": 4, "luk": 4}
	var bare := _lv1("")
	var p := CombatFormula.physical_attack(s, "stab", db())
	var q := CombatFormula.physical_attack(bare, "stab", db())
	assert_eq(p.to_dict(), q.to_dict(), "null weapon = bare-hands profile")
	assert_eq(CombatFormula.damage_window(s, null, db()), CombatFormula.damage_window(bare, null, db()), "window")


func test_monster_record_with_unpublished_values() -> void:
	# Canonical records keep a value MeowDB does not publish as null; the combat record must not crash on it.
	var m := MonsterCombatStats.from_monster({"id": "x", "level": null, "hp": 10, "magic_damage": null,
		"knockback_threshold_damage": null, "element": null, "animations": {}})
	assert_eq([m.level, m.hp, m.mdmg, m.kb, m.element_raw], [1, 10, 0, 0, ""], "nulls fall back to neutral values")
	var snail := MonsterCombatStats.from_id("2", db())
	var raw: Dictionary = db().monster("2")
	assert_eq([snail.level, snail.hp, snail.exp, snail.acc, snail.pdmg, snail.kb],
		[int(raw["level"]), int(raw["hp"]), int(raw["exp"]), int(raw["accuracy"]), int(raw["physical_damage"]),
		int(raw["knockback_threshold_damage"])], "canonical Snail fields")
	assert_eq(snail.hit_animation_ms, int(raw["animations"]["hit1"]["duration_ms"]), "hit clip")
