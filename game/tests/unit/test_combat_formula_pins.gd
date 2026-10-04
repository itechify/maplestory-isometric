extends TestCase
## Formula pins. Where MeowDB publishes a constant only inside a formula string (not as a data field), CombatFormula,
## StatCalculator and Progression transcribe that formula in code. These tests fail if a refreshed extract changes
## the published text, so the code is reviewed together with the data.


func _has_line(lines: Variant, text: String, where: String) -> void:
	var found := false
	if lines is Array:
		for l in lines:
			if String(l) == text:
				found = true
	elif lines is String:
		found = String(lines) == text
	assert_true(found, "%s no longer publishes: %s" % [where, text])


func test_damage_formulas() -> void:
	var d := db().formula("damage")
	assert_eq(String(d["physical"]["mastery"]["formula"]), "M = (MasteryLevel / 10 + 0.1) × 0.8", "mastery formula")
	_has_line(d["physical"]["formulas"], "S = SkillDamage / 100", "damage.physical")
	_has_line(d["physical"]["formulas"], "Raw = S × TotalWATK × (B + (Q × WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)", "damage.physical")
	_has_line(d["physical"]["formulas"], "Q = uniform(Primary × M, Primary)", "damage.physical")
	assert_eq(String(d["physical"]["independent_rolls"]), "B and Q are independent random draws.", "independent draws")
	_has_line(d["magic"]["formulas"], "MIN = S × MagicTotal × (1 + TotalINT × M / 100)", "damage.magic")
	_has_line(d["magic"]["formulas"], "MAX = S × MagicTotal × (1 + TotalINT / 100)", "damage.magic")
	_has_line(d["defense"]["formulas"], "EffectiveDEF = max(0, FlatBonus + trunc((1 + PercentBonus / 100) × BaseDEF))", "damage.defense")
	_has_line(d["defense"]["formulas"], "Defended = Raw × 100 / (EffectiveDEF + 100)", "damage.defense")
	assert_eq(String(d["defense"]["bypass_expected"]), "Raw × ((1 - g) × 100 / (EffectiveDEF + 100) + g)", "bypass")
	_has_line(d["critical"]["formulas"], "Critical hit = Normal × (1 + d)", "damage.critical")
	_has_line(d["critical"]["formulas"], "Expected with crit = Normal × (1 + c × d)", "damage.critical")
	assert_eq(String(d["final_clamp"]["formula"]), "Final = trunc(clamp(value, 1, 99,999))", "final clamp")
	_has_line(d["level_gap"]["formulas"], "LevelScale = 1 / (1 + Gap² × 0.005) when Gap is 1-9", "damage.level_gap")
	_has_line(d["level_gap"]["formulas"], "LevelScale = 1 / (1 + Gap × 0.05) when Gap ≥ 10", "damage.level_gap")
	assert_eq(String(d["pipeline_order"]["steps"][0]), "hit_check", "pipeline starts with the hit check")
	assert_eq(d["pipeline_order"]["steps"], ["hit_check", "raw_roll", "defense", "element", "level_gap", "critical", "final_clamp"], "pipeline order")


func test_accuracy_and_incoming_formulas() -> void:
	var a := db().formula("accuracy")
	_has_line(a["outgoing_hit"]["formulas"], "A = TotalACC × 100 / (10 × L + 255)", "outgoing hit")
	_has_line(a["outgoing_hit"]["formulas"], "R = uniform(1 - f, 1 + f)", "outgoing hit")
	_has_line(a["darkness"]["formulas"], "d = clamp(Darkness / 100, 0, 1)", "darkness")
	_has_line(a["darkness"]["formulas"], "Lands = Hit and v > d", "darkness")
	_has_line(a["incoming_hit"]["formulas"], "CandidateChance = clamp(exp((A - E) / 18) × 0.03, 0.02, 0.03)", "incoming hit")
	_has_line(a["incoming_hit"]["formulas"], "FinalHitChance = CandidateChance + (1 - CandidateChance) × 0.08", "incoming hit")
	_has_line(a["guards"]["formulas"], "ShieldGuardChance = 0 when ShieldWDEF ≤ 0", "guards")
	_has_line(a["guards"]["formulas"], "ShieldGuardChance = max(0.05, ShieldWDEF / (ShieldWDEF + 500))", "guards")
	_has_line(a["incoming_damage"]["formulas"], "EffectiveMobAttack = trunc(MobAttack × AttackRatio / 100)", "incoming damage")
	_has_line(a["incoming_damage"]["formulas"], "Roll = 1.1 + 0.4 × U", "incoming damage")
	_has_line(a["incoming_damage"]["formulas"], "Taken = Raw × (1 - DEF / (DEF + 5 × (PlayerLevel + 40) + 1.2 × Raw))", "incoming damage")
	_has_line(a["incoming_damage"]["formulas"], "FinalTaken = trunc(clamp(Taken, 1, 50,000,000))", "incoming damage")
	_has_line(a["elemental_resistance"]["formula"], "Taken = AfterDefense × (1 - Resist / 100)", "resistance")
	assert_eq(String(a["avoidability"]["formula"]), "EVA = floor(LUK / 3) + floor(DEX / 6) + 5", "EVA")


func test_timing_hp_and_death_formulas() -> void:
	var s := db().formula("attack_speed")
	_has_line(s["timing_formula"], "ScaledFrame = truncTowardZero(FrameDelay × (10 + timingTier) / 16)", "timing")
	_has_line(s["timing_formula"], "Player-facing Animation Time = 30 × ceil(nativeMs / 30)", "timing")
	var h := db().formula("hp_mp_gain")
	_has_line(h["formulas"], "TotalHP = trunc(JobHP × (1 + MaxHP% / 100)) + EquipmentHP", "hp")
	_has_line(h["formulas"], "JobHP = 50 + 16 × B + HPAdv × A + HPPerLevel × C", "hp")
	_has_line(db().formula("death")["exp_penalty"]["formulas"], "Loss = floor(EXP to next level × (5 + 20 / LUK) / 100)", "death")
	_has_line(db().formula("beginner")["ap"]["total_ap_formula"], "Total AP = 25 + 5 × (Level - 1)", "AP")
	var note := String(db().formula("attack_styles")["hitzone_data_source"]["note"])
	assert_true(note.contains("from level %d" % WeaponProfile.LEVEL100_BAND_MIN_LEVEL), "level-100 hit-zone band starts at %d" % WeaponProfile.LEVEL100_BAND_MIN_LEVEL)


func test_no_canonical_data_errors() -> void:
	assert_eq(CombatRules.of(db()).errors.size(), 0, "CombatRules: %s" % ", ".join(CombatRules.of(db()).errors))
