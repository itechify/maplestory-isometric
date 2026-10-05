extends ParityTestCase
## Outgoing damage vs MeowDB's dmg-simulator, character builder and /formulas calculators
## (game/tests/data/parity_vectors.json, docs/canonical/oracles.md).


## beginner_damage_vs_monster: basic attack vs the six Maple Island monsters, window (no crit) and default crit.
func test_beginner_damage_vs_monster() -> void:
	for v in vectors("beginner_damage_vs_monster"):
		var inp: Dictionary = v["inputs"]
		var out: Dictionary = v["outputs"]
		var id := String(v["case_id"])
		var s := sim_attacker(inp, String(inp["weapon_item_id"]))
		var target := sim_target(inp.get("target", null))
		var win := CombatFormula.damage_window(s, target, db())
		var ph: Dictionary = out["per_hit"]
		assert_eq(win["min"], int(ph["min"]), id + " per_hit.min")
		assert_eq(win["max"], int(ph["max"]), id + " per_hit.max")
		assert_eq(win["avg"], float(ph["avg"]), id + " per_hit.avg")
		var display: Dictionary = out["display"]
		assert_eq(str(win["min"]), String(display["min"]), id + " display.min")
		assert_eq(str(win["max"]), String(display["max"]), id + " display.max")
		assert_rel(CombatFormula.expected_damage_with_crit(s, target, db()), float(out["per_cast_avg_with_crit"]), id + " per_cast_avg_with_crit")
		var bonuses: Dictionary = out["bonuses"]
		assert_rel(s.crit_rate * 100.0, float(bonuses["critRate"]), id + " critRate")
		assert_rel(s.crit_damage * 100.0, float(bonuses["critDamage"]), id + " critDamage")
		var wm: Dictionary = out["weapon_multiplier"]
		var odds := s.weapon.ordinary_actions(false)
		var avg_mult := 0.0
		for a in odds:
			avg_mult += float(odds[a]) * s.weapon.multiplier(a)
		assert_rel(avg_mult, float(wm["avg"]), id + " weapon_multiplier.avg")


## physical_roll_explicit: the two-draw raw roll at fixed (base, stat) draws, then defense/level/crit/clamp vs
## Snail and Orange Mushroom.
func test_physical_roll_explicit() -> void:
	for v in vectors("physical_roll_explicit"):
		var inp: Dictionary = v["inputs"]
		var out: Dictionary = v["outputs"]
		var id := String(v["case_id"])
		var s := sim_attacker(inp["damage_input"], String(inp["weapon_item_id"]))
		var p := CombatFormula.physical_attack(s, String(inp["action"]), db())
		var raw := CombatFormula.raw_physical_roll(p, float(inp["baseRoll"]), float(inp["statRoll"]))
		assert_rel(raw, float(out["raw"]), id + " raw")
		for mid in out["final_by_monster"]:
			var exp_m: Dictionary = out["final_by_monster"][mid]
			var target := fixture_monster(String(mid))
			var v_def := CombatFormula.apply_defense(raw, CombatFormula.effective_defense(target.pdef))
			var v_el := CombatFormula.apply_element(v_def, CombatFormula.element_multiplier(CombatFormula.element_relation(target.element_raw, ""), db()))
			var v_lv := CombatFormula.apply_level_scaling(v_el, s.level, target.level, db())
			assert_rel(v_lv, float(exp_m["final_untruncated"]), "%s vs %s untruncated" % [id, mid])
			assert_eq(CombatFormula.finalize_damage(v_lv, db()), int(exp_m["final_truncated"]), "%s vs %s truncated" % [id, mid])
			var v_cr := CombatFormula.apply_critical(v_lv, true, 0.2)
			assert_eq(CombatFormula.finalize_damage(v_cr, db()), int(exp_m["with_crit_20pct_truncated"]), "%s vs %s crit" % [id, mid])


## The same explicit draws through the full pipeline (resolve_physical_hit) with a scripted RNG.
func test_physical_roll_explicit_through_pipeline() -> void:
	for v in vectors("physical_roll_explicit"):
		var inp: Dictionary = v["inputs"]
		var s := sim_attacker(inp["damage_input"], String(inp["weapon_item_id"]))
		var target := fixture_monster("2")
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var res := CombatFormula.resolve_physical_hit(s, target, String(inp["action"]), rng, db())
		# Re-run the stage functions on the draws the pipeline actually made.
		var p := CombatFormula.physical_attack(s, String(inp["action"]), db())
		assert_rel(res.raw, CombatFormula.raw_physical_roll(p, res.base_roll_u, res.stat_roll_u), String(v["case_id"]) + " pipeline raw")
		assert_between(res.raw, res.range_min, res.range_max, String(v["case_id"]) + " raw in window")
		assert_false(res.missed, String(v["case_id"]) + " Snail has AVOID 0: never missed")
		assert_false(res.critical, String(v["case_id"]) + " crit rate 0 in this input")


## guide_example_lv30_warrior_damage_window: the guide's Gladius 60-172 and Power Strike 157-449.
func test_guide_lv30_warrior_damage_window() -> void:
	for v in vectors("guide_example_lv30_warrior_damage_window"):
		var inp: Dictionary = v["inputs"]
		var out: Dictionary = v["outputs"]
		var s := sim_attacker(inp, String(inp["weapon_item_id"]))
		var basic := CombatFormula.damage_window(s, null, db())
		var ba: Dictionary = out["basic_attack"]["per_hit"]
		assert_eq(basic["min"], int(ba["min"]), "basic min (guide 60)")
		assert_eq(basic["max"], int(ba["max"]), "basic max (guide 172)")
		assert_eq(basic["avg"], float(ba["avg"]), "basic avg")
		var ps := CombatFormula.damage_window(s, null, db(), {"skill_pct": 260.0})
		var pa: Dictionary = out["power_strike"]["per_hit"]
		assert_eq(ps["min"], int(pa["min"]), "Power Strike min (guide 157)")
		assert_eq(ps["max"], int(pa["max"]), "Power Strike max (guide 449)")
		assert_eq(ps["avg"], float(pa["avg"]), "Power Strike avg")
		assert_eq("%d-%d" % [basic["min"], basic["max"]], String(v["guide_expected"]["window"]), "guide window text")


## The guide's worked example also through StatCalculator: a level 30 Warrior with 132/30/4/4 and a Gladius.
func test_guide_lv30_warrior_window_through_stat_calculator() -> void:
	var snap := StatCalculator.compute("warrior", 30, {"str": 132, "dex": 30, "int": 4, "luk": 4}, 0, 0,
		{"watk": 47}, "551", db())
	assert_eq(snap["damage_min"], 60, "Lv30 Warrior window min")
	assert_eq(snap["damage_max"], 172, "Lv30 Warrior window max")


## guide_example_beginner_starter_weapon_hits: hits to kill a Snail (45 HP) at min/avg/max (Beginner's guide).
func test_guide_beginner_starter_weapon_hits() -> void:
	for v in vectors("guide_example_beginner_starter_weapon_hits"):
		var inp: Dictionary = v["inputs"]
		var out: Dictionary = v["outputs"]
		var ap: Dictionary = inp["ap"]
		var weapon_id := String(inp["weapon_item_id"])
		var watk := int(inp["equipment"]["weapon"]["stats"]["watk"])
		var snap := StatCalculator.compute("beginner", int(inp["level"]), ap, 50, 5, {"watk": watk}, weapon_id, db())
		var bd: Dictionary = out["beginner_damage"]
		assert_eq(snap["damage_min"], int(bd["min"]), String(v["case_id"]) + " min")
		assert_eq(snap["damage_max"], int(bd["max"]), String(v["case_id"]) + " max")
		assert_eq(snap["damage_avg"], float(bd["avg"]), String(v["case_id"]) + " avg")
		var hp := float(db().monster(String(inp["monster_id"]))["hp"])
		assert_eq(int(inp["monster_hp"]), int(hp), "Snail HP from canonical data")
		var hits := [ceili(hp / float(snap["damage_min"])), ceili(hp / float(snap["damage_avg"])), ceili(hp / float(snap["damage_max"]))]
		assert_eq(hits, [int(out["hits_at_min_avg_max"][0]), int(out["hits_at_min_avg_max"][1]), int(out["hits_at_min_avg_max"][2])], String(v["case_id"]) + " hits")


## defense_curve_and_final_clamp: Raw x 100 / (DEF + 100), clamp and trunc, with and without +20% crit.
func test_defense_curve_and_final_clamp() -> void:
	for v in vectors("defense_curve_and_final_clamp"):
		var inp: Dictionary = v["inputs"]
		var out: Dictionary = v["outputs"]
		var id := String(v["case_id"])
		var after := CombatFormula.apply_defense_expected(float(inp["raw"]), CombatFormula.effective_defense(float(inp["pdef"])), float(inp["wdef_ignore"]))
		after = CombatFormula.apply_level_scaling(after, int(inp["player_level"]), int(inp["target_level"]), db())
		var r := CombatRules.of(db())
		assert_rel(clampf(after, r.damage_clamp_min, r.damage_clamp_max), float(out["final_untruncated"]), id + " untruncated")
		assert_eq(CombatFormula.finalize_damage(after, db()), int(out["final_truncated"]), id + " truncated")
		var crit := CombatFormula.apply_critical(after, true, 0.2)
		assert_eq(CombatFormula.finalize_damage(crit, db()), int(out["with_crit_20pct_truncated"]), id + " crit")


## defense_ignore: the expected value of a full-defense-bypass proc with rate g.
func test_defense_ignore() -> void:
	for v in vectors("defense_ignore"):
		var inp: Dictionary = v["inputs"]
		var after := CombatFormula.apply_defense_expected(float(inp["raw"]), CombatFormula.effective_defense(float(inp["pdef"])), float(inp["wdef_ignore"]))
		assert_eq(CombatFormula.finalize_damage(after, db()), int(v["outputs"]["final_truncated"]), String(v["case_id"]))


## magic_defense_curve: the same curve on M.DEF, through the magic pipeline's defense stage.
func test_magic_defense_curve() -> void:
	for v in vectors("magic_defense_curve"):
		var inp: Dictionary = v["inputs"]
		var after := CombatFormula.apply_defense(float(inp["raw"]), CombatFormula.effective_defense(float(inp["mdef"])))
		assert_eq(CombatFormula.finalize_damage(after, db()), int(v["outputs"]["final_truncated"]), String(v["case_id"]))


## final_clamp: trunc(clamp(value, 1, 99999)).
func test_final_clamp() -> void:
	for v in vectors("final_clamp"):
		assert_eq(CombatFormula.finalize_damage(float(v["inputs"]["value"]), db()), int(v["outputs"]["final"]), String(v["case_id"]))


## level_gap_scale: gap -5, 0, 1, 5, 9, 10, 20.
func test_level_gap_scale() -> void:
	for v in vectors("level_gap_scale"):
		var inp: Dictionary = v["inputs"]
		var got := CombatFormula.level_scale(int(inp["player_level"]), int(inp["target_level"]), db())
		assert_rel(got, float(v["outputs"]["level_scale"]), String(v["case_id"]))


## crit_expectation: /formulas "critical" calculator (display strings, half-expand rounding).
func test_crit_expectation() -> void:
	for v in vectors("crit_expectation"):
		var inp: Dictionary = v["inputs"]
		var normal := float(inp["normal"])
		var d := float(inp["criticalDamage"]) / 100.0
		var c := float(inp["criticalRate"]) / 100.0
		var rows: Array = v["outputs"]
		for row in rows:
			var label := String(row["label"])
			var got := 0.0
			if label == "Critical hit":
				got = CombatFormula.apply_critical(normal, true, d)
			elif label == "Expected with crits":
				got = CombatFormula.expected_with_critical(normal, c, d)
			else:
				fail("unknown crit row %s" % label)
			assert_eq(display_round(got), String(row["minimum"]), "%s %s" % [v["case_id"], label])
