extends TestCase
## DeathRules (pure): the death penalties in data/misostory/death.json order. The canonical EXP penalty comes from
## Progression (formulas/death.json, MeowDB's model); HP/MP after the respawn are the death.json adaptation. A
## death must never touch the inventory, equipment or quest log, and new rules slot in by name.


## Contract C6.
func parity_keys() -> Dictionary:
	return {
		"test_exp_penalty_is_the_canonical_formula": ["mechanic:death-respawn"],
		"test_respawn_vitals_follow_death_json": ["mechanic:death-respawn"],
		"test_a_death_does_not_touch_items_equipment_or_quests": ["mechanic:death-respawn"],
	}


func _character(level: int = 5, exp_value: int = 40, luk: int = 4) -> CharacterState:
	var c := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	c.level = level
	c.exp = exp_value
	c.base_stats["luk"] = luk
	var hp_mp := Progression.base_max_hp_mp(c.job, level, db())
	c.base_max_hp = int(hp_mp.get("max_hp", c.base_max_hp))
	c.base_max_mp = int(hp_mp.get("max_mp", c.base_max_mp))
	c.hp = 0
	c.mp = 7
	return c


func test_death_json_is_valid_and_ordered() -> void:
	var r := DeathRules.from_db(db())
	assert_eq(r.errors, PackedStringArray(), "no problems in death.json")
	assert_eq(r.order, PackedStringArray([DeathRules.RULE_EXP_PENALTY, DeathRules.RULE_RESPAWN_VITALS]), "order from data")
	var t := r.table()
	for section in ["rules", "respawn_vitals"]:
		var s: Dictionary = t[section]
		assert_true(String(s.get("reason", "")).length() > 40, "%s has a reason" % section)
		assert_eq(s.get("verified", null), false, "%s is an unverified adaptation (a MeowDB gap)" % section)


func test_exp_penalty_is_the_canonical_formula() -> void:
	for case: Array in [[5, 40, 4], [5, 40, 20], [10, 200, 9], [1, 10, 4], [3, 0, 4], [30, 47850, 4]]:
		var c := _character(case[0], case[1], case[2])
		var want := Progression.death_exp_loss(case[0], case[2], db())
		var report := DeathRules.from_db(db()).apply(c)
		assert_eq(int(report["exp_lost"]), mini(want, int(case[1])), "loss at %s" % [case])
		assert_eq(c.exp, maxi(0, int(case[1]) - want), "EXP after at %s" % [case])
		assert_eq(c.level, int(case[0]), "a death never takes a level")
	# MeowDB's parity example (formulas/death.json): Lv 30, LUK 4, 47,850 EXP -> loss 9,570.
	var pe: Dictionary = (db().formula("death")["exp_penalty"] as Dictionary)["parity_example"]
	var c30 := _character(int(pe["level"]), int(pe["exp_before"]), int(pe["base_luk"]))
	DeathRules.from_db(db()).apply(c30)
	assert_eq(c30.exp, int(pe["exp_after"]), "MeowDB parity example")


func test_respawn_vitals_follow_death_json() -> void:
	var r := DeathRules.from_db(db())
	var vit := r.respawn_vitals()
	var c := _character()
	var max_hp := StatCalculator.max_hp(c, db())
	var max_mp := StatCalculator.max_mp(c, db())
	var report := r.apply(c)
	assert_eq(c.hp, maxi(1, DeathRules.vital_value(vit["hp"], 0, max_hp)), "HP per death.json")
	assert_eq(c.mp, DeathRules.vital_value(vit["mp"], 7, max_mp), "MP per death.json")
	assert_eq([report["hp"], report["mp"]], [c.hp, c.mp], "reported")
	assert_true(c.hp >= 1 and c.hp <= max_hp, "alive and within max")
	assert_false(Progression.is_dead(c, db()), "not dead after the respawn rules")


func test_vital_modes() -> void:
	assert_eq(DeathRules.vital_value({"mode": "fixed", "value": 50}, 0, 130), 50, "fixed")
	assert_eq(DeathRules.vital_value({"mode": "fixed", "value": 50}, 0, 30), 30, "fixed is capped at max")
	assert_eq(DeathRules.vital_value({"mode": "fraction_of_max", "value": 0.5}, 0, 131), 65, "fraction")
	assert_eq(DeathRules.vital_value({"mode": "full"}, 3, 90), 90, "full")
	assert_eq(DeathRules.vital_value({"mode": "keep"}, 12, 90), 12, "keep")
	assert_eq(DeathRules.vital_value({"mode": "keep"}, 120, 90), 90, "keep never exceeds max")


func test_a_death_does_not_touch_items_equipment_or_quests() -> void:
	var c := _character()
	c.inventory.add("270", 4, db())
	var qe := QuestEngine.new(c, db())
	qe.accept("1000")
	c.mesos = 1234
	var before := [c.inventory.to_dict(), c.equipment.to_dict(), c.quests.to_dict(), c.mesos, c.ap, c.sp,
		c.base_stats.duplicate()]
	DeathRules.from_db(db()).apply(c)
	assert_eq([c.inventory.to_dict(), c.equipment.to_dict(), c.quests.to_dict(), c.mesos, c.ap, c.sp, c.base_stats],
		before, "inventory, equipment, quests, mesos, AP/SP and stats untouched")


func test_new_rules_slot_in_by_name() -> void:
	var r := DeathRules.from_db(db())
	var calls: Array = []
	r.register_rule("lose_buffs", func(c: CharacterState, report: Dictionary) -> void:
		calls.append(c.exp)
		c.effects.clear()
		report["buffs_cleared"] = true)
	assert_eq(r.order[r.order.size() - 1], "lose_buffs", "appended to the order")
	var c := _character()
	c.effects.append({"id": "test_buff"})
	var report := r.apply(c)
	assert_eq(report["applied"], [DeathRules.RULE_EXP_PENALTY, DeathRules.RULE_RESPAWN_VITALS, "lose_buffs"], "applied in order")
	assert_eq(calls.size(), 1, "ran once")
	assert_true(c.effects.is_empty() and bool(report["buffs_cleared"]), "its effect and report")
	assert_true(r.last_report == report, "last_report")


func test_unknown_rules_are_reported_not_fatal() -> void:
	var r := DeathRules.new(db())
	r.order = PackedStringArray(["no_such_rule", DeathRules.RULE_EXP_PENALTY])
	assert_has(r.validate(), "death.json rules.order names an unknown rule 'no_such_rule'", "validate")
	var c := _character()
	var report := r.apply(c)
	assert_eq(report["applied"], [DeathRules.RULE_EXP_PENALTY], "the known rule still runs")
	assert_true(r.errors.size() == 1, "the unknown rule is recorded")


func test_missing_table_is_an_error() -> void:
	var r := DeathRules.from_db(ContentDB.new())
	assert_false(r.errors.is_empty(), "no death.json is reported")
	assert_eq(r.order.size(), 0, "no rules run without data")
