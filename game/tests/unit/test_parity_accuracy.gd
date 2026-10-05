extends ParityTestCase
## Hit chance, avoid, guards and incoming damage vs MeowDB's accuracy-sim, avoidability-sim, mob-hit-sim and the
## /formulas calculators (game/tests/data/parity_vectors.json, docs/canonical/oracles.md).

## JavaScript's Number.EPSILON: MeowDB's "min" milestone searches for the first hit chance above 0.
const JS_EPSILON := 2.220446049250313e-16


## Contract C6: every test replays MeowDB's own calculators (Definition of Done: MeowDB parity tests still pass).
func parity_keys() -> Dictionary:
	var out := {}
	for t in ["test_accuracy_vs_monster", "test_acc_milestones", "test_accuracy_grid", "test_incoming_hit_grid",
			"test_incoming_damage_curve", "test_shield_guard_chance", "test_avoid_and_incoming_vs_monster", "test_mob_hit_danger"]:
		out[t] = ["canon:meowdb-formula-parity"]
	out["test_monster_touch_damage_display"] = ["canon:meowdb-formula-parity", "mechanic:monster-touch-damage"]
	out["test_monster_records_touch_estimate"] = ["canon:meowdb-formula-parity", "mechanic:monster-touch-damage"]
	return out


func _check_acc_milestones(out: Dictionary, plv: int, mlv: int, eva: float, id: String) -> void:
	assert_rel(CombatFormula.acc_needed_for_hit_chance(JS_EPSILON, plv, mlv, eva, db()), float(out["min"]), id + " min")
	assert_rel(CombatFormula.acc_needed_for_hit_chance(100.0, plv, mlv, eva, db()), float(out["max"]), id + " max")
	for m in out["milestones"]:
		var expected: Variant = m["acc"]
		var got := CombatFormula.acc_needed_for_hit_chance(float(m["pct"]), plv, mlv, eva, db())
		if expected == null:
			assert_true(is_inf(got), "%s milestone %s unreachable" % [id, m["pct"]])
		else:
			assert_rel(got, float(expected), "%s milestone %s" % [id, m["pct"]])


## accuracy_hit_chance_vs_monster: Beginner ACC vs the six monsters (all AVOID 0: 100%).
func test_accuracy_vs_monster() -> void:
	for v in vectors("accuracy_hit_chance_vs_monster"):
		var inp: Dictionary = v["inputs"]
		var id := String(v["case_id"])
		var m := MonsterCombatStats.from_id(String(inp["monster_id"]), db())
		assert_eq(m.level, int(inp["monLevel"]), id + " canonical monster level")
		assert_eq(m.avoid, int(inp["monAvoid"]), id + " canonical monster avoid")
		var chance := CombatFormula.outgoing_hit_chance(float(inp["acc"]), int(inp["charLevel"]), m.level, m.avoid, db())
		assert_rel(chance * 100.0, float(v["outputs"]["hitRate"]), id + " hitRate")
		_check_acc_milestones(v["outputs"], int(inp["charLevel"]), m.level, m.avoid, id)


## accuracy_acc_milestones: ACC needed for 0+/25/50/75/90/95/100% (64-step bisection).
func test_acc_milestones() -> void:
	for v in vectors("accuracy_acc_milestones"):
		var inp: Dictionary = v["inputs"]
		_check_acc_milestones(v["outputs"], int(inp["charLevel"]), int(inp["monLevel"]), float(inp["monAvoid"]), String(v["case_id"]))


## accuracy_hit_chance_grid: hit % for ACC 8/15/25/40/80 across levels and AVOID.
func test_accuracy_grid() -> void:
	for v in vectors("accuracy_hit_chance_grid"):
		var inp: Dictionary = v["inputs"]
		var chance := CombatFormula.outgoing_hit_chance(float(inp["acc"]), int(inp["charLevel"]), int(inp["monLevel"]), float(inp["monAvoid"]), db())
		assert_rel(chance * 100.0, float(v["outputs"]["hitRate"]), String(v["case_id"]))
		assert_rel(chance * 100.0, float(v["outputs"]["outgoing_hit_rate_pct"]), String(v["case_id"]) + " /formulas")


## incoming_hit_chance_grid: monster hit % and dodge % (8% minimum-hit rescue included).
func test_incoming_hit_grid() -> void:
	for v in vectors("incoming_hit_chance_grid"):
		var inp: Dictionary = v["inputs"]
		var chance := CombatFormula.incoming_hit_chance(float(inp["monAcc"]), float(inp["charAvoid"]), int(inp["charLevel"]), int(inp["monLevel"]), db())
		assert_rel(chance * 100.0, float(v["outputs"]["monster_hit_chance_pct"]), String(v["case_id"]) + " hit")
		assert_rel(100.0 - chance * 100.0, float(v["outputs"]["dodge_rate_pct"]), String(v["case_id"]) + " dodge")


## incoming_damage_curve: raw/taken at rolls 1.1, 1.3, 1.5 vs DEF and level.
func test_incoming_damage_curve() -> void:
	for v in vectors("incoming_damage_curve"):
		_check_incoming_kernel(v["inputs"], v["outputs"], String(v["case_id"]))


## monster_touch_damage_display: each monster page's "Touch DMG" equals the kernel at DEF 0, level 1.
func test_monster_touch_damage_display() -> void:
	for v in vectors("monster_touch_damage_display"):
		var inp: Dictionary = v["inputs"]
		var out: Dictionary = v["outputs"]
		_check_incoming_kernel(inp, out, String(v["case_id"]))
		var got := CombatFormula.incoming_damage_range(float(inp["monster_attack"]), float(inp["player_def"]), int(inp["player_level"]), db())
		assert_eq("%d-%d" % [got["taken_min"], got["taken_max"]], String(out["display"]), String(v["case_id"]) + " display")


## The canonical monster records' touch estimate matches the kernel too.
func test_monster_records_touch_estimate() -> void:
	for mid in ["1", "2", "3", "4", "5", "9"]:
		var m := db().monster(mid)
		var est: Dictionary = m["touch_damage_estimate_at_0_wdef"]
		var got := CombatFormula.incoming_damage_range(float(m["physical_damage"]), 0.0, 1, db())
		assert_eq(got["taken_min"], int(est["min"]), "monster %s touch min" % mid)
		assert_eq(got["taken_max"], int(est["max"]), "monster %s touch max" % mid)


## shield_guard_chance: max(0.05, W / (W + 500)), 0 without a shield.
func test_shield_guard_chance() -> void:
	for v in vectors("shield_guard_chance"):
		var inp: Dictionary = v["inputs"]
		assert_eq(int(inp["claw_guard_level"]), 0, "vectors only cover Shield Guard")
		assert_rel(CombatFormula.guard_chance(float(inp["shield_wdef"])), float(v["outputs"]["guard_chance"]), String(v["case_id"]))


## avoid_and_incoming_damage_vs_monster: dodge, land rate, guard, expected damage, avoid milestones and the
## physical/magic damage blocks for the Beginner builds vs the six monsters.
func test_avoid_and_incoming_vs_monster() -> void:
	for v in vectors("avoid_and_incoming_damage_vs_monster"):
		var inp: Dictionary = v["inputs"]
		var out: Dictionary = v["outputs"]
		var id := String(v["case_id"])
		var m := MonsterCombatStats.from_id(String(inp["monster_id"]), db())
		assert_eq(m.acc, int(inp["monAcc"]), id + " canonical ACC")
		assert_eq(m.pdmg, int(inp["monPdmg"]), id + " canonical P.DMG")
		assert_eq(m.mdmg, int(inp["monMdmg"]), id + " canonical M.DMG")
		var plv := int(inp["charLevel"])
		var hit := CombatFormula.incoming_hit_chance(m.acc, float(inp["charAvoid"]), plv, m.level, db())
		assert_rel(100.0 - hit * 100.0, float(out["dodgeRate"]), id + " dodgeRate")
		assert_rel(hit * 100.0, float(out["physicalLandRate"]), id + " physicalLandRate")
		var guard := CombatFormula.guard_chance(float(inp["shieldWdef"]))
		assert_rel(guard, float(out["guardChance"]), id + " guardChance")
		var phys := CombatFormula.incoming_damage_range(m.pdmg, float(inp["charWdef"]), plv, db())
		_check_kernel_block(phys, out["physical"], id + " physical")
		_check_kernel_block(CombatFormula.incoming_damage_range(m.mdmg, float(inp["charMdef"]), plv, db()), out["magic"], id + " magic (kernel)")
		assert_rel(float(phys["taken_avg"]) * hit * (1.0 - guard), float(out["expectedPhysicalDamagePerAttempt"]), id + " expected per attempt")
		# Avoid milestones (null = unreachable because of the 8% rescue).
		var min_expected: Variant = out["min"]
		var got_min := CombatFormula.avoid_needed_for_dodge(JS_EPSILON, m.acc, plv, m.level, db())
		if min_expected == null:
			assert_true(is_inf(got_min), id + " min unreachable")
		else:
			assert_rel(got_min, float(min_expected), id + " avoid min")
		assert_true(out["max"] == null and is_inf(CombatFormula.avoid_needed_for_dodge(100.0, m.acc, plv, m.level, db())), id + " 100% dodge unreachable")
		for ms in out["milestones"]:
			var e: Variant = ms["avoid"]
			var got := CombatFormula.avoid_needed_for_dodge(float(ms["pct"]), m.acc, plv, m.level, db())
			if e == null:
				assert_true(is_inf(got), "%s avoid milestone %s unreachable" % [id, ms["pct"]])
			else:
				assert_rel(got, float(e), "%s avoid milestone %s" % [id, ms["pct"]])
		# Game rule (oracles.md discrepancy 2, chosen 0): no magic attack deals no magic damage.
		if m.mdmg <= 0:
			var p := PlayerCombatStats.new()
			p.level = plv
			p.mdef = int(inp["charMdef"])
			var res := CombatFormula.resolve_monster_attack(m, p, RandomNumberGenerator.new(), db(), {"magic": true})
			assert_true(res.no_attack and res.final == 0, id + " M.DMG 0 deals no magic damage")


## mob_hit_danger: the mob-hit-sim's per-monster damage for each build (the danger tiers are UI, not game rules).
func test_mob_hit_danger() -> void:
	for v in vectors("mob_hit_danger"):
		var inp: Dictionary = v["inputs"]
		var plv := int(inp["charLevel"])
		for mid in v["outputs"]:
			var row: Dictionary = v["outputs"][mid]
			var m := MonsterCombatStats.from_id(String(mid), db())
			assert_eq(row["levelDiff"], m.level - plv, "%s/%s levelDiff" % [v["case_id"], mid])
			var phys := CombatFormula.incoming_damage_range(m.pdmg, float(inp["charWdef"]), plv, db())
			var id := "%s/%s" % [v["case_id"], mid]
			assert_eq(phys["raw_min"], int(row["physicalRawMinDamage"]), id + " raw min")
			assert_eq(phys["raw_avg"], int(row["physicalRawAvgDamage"]), id + " raw avg")
			assert_eq(phys["raw_max"], int(row["physicalRawDamage"]), id + " raw max")
			assert_eq(phys["taken_min"], int(row["physicalDamageMinAfterDef"]), id + " taken min")
			assert_eq(phys["taken_avg"], int(row["physicalDamageAvgAfterDef"]), id + " taken avg")
			assert_eq(phys["taken_max"], int(row["physicalDamageAfterDef"]), id + " taken max")
			assert_eq(phys["taken_max"], int(row["damageAfterDef"]), id + " damageAfterDef")
			# mob-hit-sim guards a zero attack to 0, as the game does (oracles.md discrepancy 2).
			assert_eq(int(row["magicDamageAfterDef"]), 0, id + " no magic attack")


func _check_incoming_kernel(inp: Dictionary, out: Dictionary, id: String) -> void:
	var got := CombatFormula.incoming_damage_range(float(inp["monster_attack"]), float(inp["player_def"]), int(inp["player_level"]), db())
	_check_kernel_block(got, out, id)


func _check_kernel_block(got: Dictionary, out: Dictionary, id: String) -> void:
	assert_eq(got["raw_min"], int(out["rawMin"]), id + " rawMin")
	assert_eq(got["raw_avg"], int(out["rawAvg"]), id + " rawAvg")
	assert_eq(got["raw_max"], int(out["rawMax"]), id + " rawMax")
	assert_eq(got["taken_min"], int(out["takenMin"]), id + " takenMin")
	assert_eq(got["taken_avg"], int(out["takenAvg"]), id + " takenAvg")
	assert_eq(got["taken_max"], int(out["takenMax"]), id + " takenMax")
	assert_rel(float(got["base_attack"]), float(out["baseAttack"]), id + " baseAttack")
