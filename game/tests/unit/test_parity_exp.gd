extends ParityTestCase
## EXP requirements, cumulative EXP, the EXP calculator and kills per level vs MeowDB's exp-calculator
## (game/tests/data/parity_vectors.json).


## Contract C6 (Definition of Done: MeowDB parity tests still pass).
func parity_keys() -> Dictionary:
	return {"test_exp_requirement": ["canon:meowdb-formula-parity"], "test_exp_calculator_validation": ["canon:meowdb-formula-parity"]}


## exp_requirement: levels 1-30: EXP to next, total at level start, cumulative, calculator result, kills.
func test_exp_requirement() -> void:
	for v in vectors("exp_requirement"):
		var inp: Dictionary = v["inputs"]
		var out: Dictionary = v["outputs"]
		var id := String(v["case_id"])
		var lvl := int(inp["level"])
		assert_eq(Progression.exp_to_next(lvl, db()), int(out["exp_to_next_level"]), id + " exp_to_next")
		assert_eq(Progression.total_exp_at(lvl, int(inp["current_exp"]), db()), int(out["total_exp_at_level_start"]), id + " H1")
		assert_eq(Progression.cumulative_exp_through(lvl, db()), int(out["cumulative_through_level"]), id + " Bq")
		var calc := Progression.exp_remaining(lvl, int(inp["current_exp"]), int(inp["target_level"]), db())
		assert_same_data(calc, out["calculator_result_lv_to_next"], id + " calculator")
		var kills: Variant = out.get("kills_lv_to_next_by_monster", null)
		if kills is Dictionary:
			for mid in kills:
				var mexp := int(db().monster(String(mid))["exp"])
				var remaining := int(calc["result"]["expRemaining"])
				assert_eq(Progression.kills_needed(remaining, mexp), int(kills[mid]), "%s kills of %s" % [id, mid])
		var g: Variant = v.get("guide_expected", null)
		if g is Dictionary:
			assert_eq(Progression.exp_to_next(lvl, db()), int(g["exp_to_next"]), id + " guide")


## exp_calculator_validation: the calculator's default (10 -> 30 = 545,290) and its rejection rules.
func test_exp_calculator_validation() -> void:
	for v in vectors("exp_calculator_validation"):
		var inp: Dictionary = v["inputs"]
		var got := Progression.exp_remaining(int(inp["currentLevel"]), int(inp["currentExp"]), int(inp["targetLevel"]), db())
		assert_same_data(got, v["outputs"], String(v["case_id"]))
