extends TestCase
## Monster -> player: hit chance with the 8% rescue, guards, the 1.1-1.5 roll, the DEF curve, magic attacks,
## resistance, the clamp, invincibility and knockback.


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _player(level: int, avoid: int, wdef: int, mdef: int = 1) -> PlayerCombatStats:
	var p := PlayerCombatStats.new()
	p.level = level
	p.avoid = avoid
	p.wdef = wdef
	p.mdef = mdef
	p.weapon = WeaponProfile.bare_hands(db())
	return p


func test_published_examples() -> void:
	var a := db().formula("accuracy")
	for ex in a["parity_examples"]:
		var inp: Dictionary = ex["input"]
		match String(ex["kind"]):
			"incoming_damage":
				var r := CombatFormula.incoming_damage_range(float(inp["mob_attack"]), float(inp["def"]), int(inp["player_level"]), db())
				assert_eq([r["taken_min"], r["taken_max"]], [int(ex["taken"][0]), int(ex["taken"][1])], String(ex["note"]))
			"incoming_hit":
				var h := CombatFormula.incoming_hit(float(inp["mob_acc"]), float(inp["player_eva"]), int(inp["player_level"]), int(inp["mob_level"]), db())
				assert_near(snappedf(float(h["chance"]) * 100.0, 0.1), float(ex["hit_chance_pct"]), 1e-9, "hit chance (1 decimal)")
				var f: float = h["f"]
				assert_near(float(h["A"]) * (1.0 - f), float(ex["accuracy_roll"][0]), 0.005, "monster accuracy roll low")
				assert_near(float(h["A"]) * (1.0 + f), float(ex["accuracy_roll"][1]), 0.005, "monster accuracy roll high")


func test_beginner_never_dodges_maple_island_monsters() -> void:
	# A level-1 Beginner has AVOID 6; MeowDB: "AVOID 11.26 is needed before a Snail can miss at all".
	for mid in ["2", "3", "4", "5", "9"]:
		var m := MonsterCombatStats.from_id(mid, db())
		assert_eq(CombatFormula.incoming_hit_chance(m.acc, 6, 1, m.level, db()), 1.0, "monster %s always hits" % mid)


func test_minimum_hit_rescue_and_far_miss() -> void:
	var h := CombatFormula.incoming_hit(10, 500, 1, 1, db())
	assert_true(bool(h["far_miss"]), "huge avoid reaches the far-miss branch")
	assert_between(float(h["candidate"]), 0.02, 0.03, "far-miss candidate clamp")
	assert_near(float(h["chance"]), float(h["candidate"]) + (1.0 - float(h["candidate"])) * 0.08, 1e-12, "8% rescue applied after the clamp")
	assert_true(float(h["chance"]) >= 0.08, "never below the 8% rescue")
	assert_eq(CombatFormula.incoming_hit_chance(0, 0, 1, 1, db()), 0.0, "a monster without ACC never hits")


func test_observed_hit_rate_matches_the_chance() -> void:
	var m := MonsterCombatStats.from_id("2", db())
	var p := _player(1, 15, 3)
	var chance := CombatFormula.incoming_hit_chance(m.acc, p.avoid, p.level, m.level, db())
	assert_true(chance > 0.2 and chance < 0.95, "a mid chance: %s" % chance)
	var rng := _rng(31337)
	var landed := 0
	var n := 20000
	for i in n:
		var res := CombatFormula.resolve_monster_touch(m, p, rng, db())
		if not res.missed:
			landed += 1
	assert_near(float(landed) / n, chance, 0.012, "observed hit rate")


func test_touch_damage_roll_and_curve() -> void:
	var m := MonsterCombatStats.from_id("9", db())
	var p := _player(1, 6, 3)
	var window := CombatFormula.incoming_damage_range(m.pdmg, p.wdef, p.level, db())
	assert_eq([window["taken_min"], window["taken_max"]], [18, 25], "Orange Mushroom vs Lv1 Beginner (oracles.md)")
	var rng := _rng(5)
	for i in 500:
		var res := CombatFormula.resolve_monster_touch(m, p, rng, db())
		assert_eq(res.kind, "touch", "kind")
		assert_between(res.roll, 1.1, 1.5, "Roll = 1.1 + 0.4U")
		assert_near(res.raw, res.effective_attack * res.roll, 1e-9, "Raw")
		var expected := res.raw * (1.0 - 3.0 / (3.0 + 5.0 * (1 + 40) + 1.2 * res.raw))
		assert_near(res.after_defense, expected, 1e-9, "Taken curve")
		assert_between(float(res.final), float(window["taken_min"]), float(window["taken_max"]), "within the touch window")
		assert_true(res.knockback, "a landed touch knocks the player back")
		assert_near(res.invincibility_s, 1.5, 1e-9, "canonical 1.5 s invincibility")


func test_defense_reduces_damage_and_clamp_keeps_one() -> void:
	assert_true(CombatFormula.incoming_taken(100.0, 50.0, 10, db()) < CombatFormula.incoming_taken(100.0, 0.0, 10, db()), "DEF reduces damage")
	assert_eq(CombatFormula.finalize_incoming(0.4, db()), 1, "a landed hit deals at least 1")
	assert_eq(CombatFormula.finalize_incoming(7.9, db()), 7, "trunc")
	assert_eq(CombatFormula.effective_mob_attack(17, 100), 17, "touch ratio 100")
	assert_eq(CombatFormula.effective_mob_attack(17, 150), 25, "trunc(17 x 1.5)")


func test_shield_guard() -> void:
	assert_eq(CombatFormula.shield_guard_chance(0), 0.0, "no shield")
	assert_eq(CombatFormula.shield_guard_chance(10), 0.05, "5% floor")
	assert_near(CombatFormula.shield_guard_chance(100), 100.0 / 600.0, 1e-12, "W / (W + 500)")
	assert_eq(CombatFormula.guard_chance(0, 0.04), 0.04, "the larger guard applies")
	var m := MonsterCombatStats.from_id("2", db())
	var p := _player(1, 0, 3)
	p.shield_wdef = 500
	var rng := _rng(12)
	var guarded := 0
	var n := 4000
	for i in n:
		var res := CombatFormula.resolve_monster_touch(m, p, rng, db())
		if res.guarded:
			guarded += 1
			assert_eq(res.final, 0, "a guard negates the hit")
			assert_false(res.knockback, "no push after a guard")
			assert_near(res.invincibility_s, 1.5, 1e-9, "a guard still grants invincibility")
	assert_near(float(guarded) / n, 0.5, 0.03, "guard rate W / (W + 500) = 0.5")


func test_misses_grant_invincibility_without_knockback() -> void:
	var m := MonsterCombatStats.from_id("2", db())
	var p := _player(1, 60, 3)
	var rng := _rng(3)
	var saw_miss := false
	var rescued := 0
	for i in 400:
		var res := CombatFormula.resolve_monster_touch(m, p, rng, db())
		if res.rescued:
			rescued += 1
			assert_false(res.missed, "a rescued attack lands")
		if res.missed:
			saw_miss = true
			assert_eq(res.final, 0, "a miss deals nothing")
			assert_false(res.knockback, "no push after a miss")
			assert_near(res.invincibility_s, 1.5, 1e-9, "a miss grants the same 1.5 s")
	assert_true(saw_miss, "high avoid produces misses")
	assert_true(rescued > 10, "the 8%% minimum-hit rescue lands some attacks (%d of 400)" % rescued)


func test_magic_attacks_skip_evasion_and_use_mdef() -> void:
	var m := MonsterCombatStats.from_id("2", db())
	m.mdmg = 40  # a hypothetical magic attack (no Maple Island monster has one)
	var p := _player(10, 9999, 0, 20)
	p.shield_wdef = 500
	var rng := _rng(9)
	for i in 200:
		var res := CombatFormula.resolve_monster_attack(m, p, rng, db(), {"magic": true})
		assert_false(res.missed, "magic bypasses evasion")
		assert_false(res.guarded, "magic bypasses guards")
		assert_eq(res.def, 20, "uses MDEF")
	var none := CombatFormula.resolve_monster_attack(MonsterCombatStats.from_id("2", db()), p, rng, db(), {"magic": true})
	assert_true(none.no_attack, "M.DMG 0: no magic attack")
	assert_eq(none.final, 0, "and no damage (oracles.md discrepancy 2)")


func test_elemental_resistance_only_for_elemental_attacks() -> void:
	var m := MonsterCombatStats.from_id("9", db())
	var p := _player(1, 0, 3)
	p.element_resist = {"fire": 50.0}
	var a := CombatFormula.resolve_monster_attack(m, p, _rng(2), db(), {"kind": "physical", "element": "fire"})
	assert_near(a.after_resist, a.after_defense * 0.5, 1e-9, "50% fire resistance")
	var b := CombatFormula.resolve_monster_touch(m, p, _rng(2), db())
	assert_eq(b.resist_pct, 0.0, "touch damage has no element")


func test_incoming_is_deterministic_per_seed() -> void:
	var m := MonsterCombatStats.from_id("5", db())
	var p := _player(3, 20, 4)
	for seed_value in [1, 7, 42]:
		assert_eq(CombatFormula.resolve_monster_touch(m, p, _rng(seed_value), db()).to_dict(),
			CombatFormula.resolve_monster_touch(m, p, _rng(seed_value), db()).to_dict(), "seed %d" % seed_value)
