extends TestCase
## Progression: EXP thresholds, level-ups (single, several, cap), AP/SP gains and allocation, HP/MP growth,
## the level-up heal, the new-character setup and the death EXP penalty.


func _fresh() -> CharacterState:
	var c := CharacterState.new()
	Progression.init_new_character(c, db())
	return c


func test_new_character_is_a_meowdb_beginner() -> void:
	var c := _fresh()
	var b := db().formula("beginner")
	assert_eq(c.job, "beginner", "job")
	assert_eq(c.level, 1, "level 1")
	assert_eq(c.exp, 0, "0 EXP")
	assert_eq(c.base_stats, {"str": 4, "dex": 4, "int": 4, "luk": 4}, "4/4/4/4")
	assert_eq(c.ap, int(b["creation_ap"]), "9 creation AP to place")
	assert_eq(c.sp, 0, "0 SP")
	assert_eq([c.base_max_hp, c.base_max_mp, c.hp, c.mp], [50, 5, 50, 5], "50 HP / 5 MP, full")
	assert_eq(Progression.total_ap(1, db()), 25, "Total AP at level 1 = 16 + 9")


func test_exp_thresholds() -> void:
	var expect := [15, 34, 57, 92, 135, 372, 560, 840, 1242, 1716]
	for i in expect.size():
		assert_eq(Progression.exp_to_next(i + 1, db()), expect[i], "level %d" % (i + 1))
	assert_eq(Progression.exp_to_next(99, db()), 9692044, "level 99")
	assert_eq(Progression.level_cap(db()), 100, "level cap 100")
	assert_eq(Progression.exp_to_next(100, db()), 0, "nothing past the cap")
	assert_eq(Progression.exp_to_next(0, db()), 0, "invalid level")
	# The table rows agree with MeowDB's published formula segments.
	for l in range(1, 50):
		var q := floori(l * l / 3.0)
		var formula := (floori(l * l / 2.0) + 15) * l if l <= 5 else (q + 19) * q
		assert_eq(Progression.exp_to_next(l, db()), formula, "formula row %d" % l)


func test_gain_exp_below_threshold() -> void:
	var c := _fresh()
	var r := Progression.gain_exp(c, 10, db())
	assert_eq([c.level, c.exp], [1, 10], "still level 1")
	assert_eq(r["levels_gained"], 0, "no level")
	assert_eq(r["exp_added"], 10, "added")
	assert_eq(Progression.gain_exp(c, 0, db())["exp_added"], 0, "zero EXP is a no-op")
	assert_eq(Progression.gain_exp(c, -5, db())["exp_added"], 0, "negative EXP is ignored")


func test_single_level_up_effects() -> void:
	var c := _fresh()
	c.hp = 10
	c.mp = 1
	var r := Progression.gain_exp(c, 15, db())
	assert_eq([c.level, c.exp], [2, 0], "level 2 at exactly 15 EXP")
	assert_eq(r["levels_gained"], 1, "one level")
	assert_eq(r["new_level"], 2, "new level")
	assert_eq(c.ap, 9 + 5, "+5 AP")
	assert_eq(c.sp, 1, "+1 SP at level 2")
	assert_eq([c.base_max_hp, c.base_max_mp], [66, 17], "+16 HP / +12 MP")
	assert_eq([c.hp, c.mp], [66, 17], "level-up heal: full (combat.json level_up)")


func test_several_level_ups_at_once() -> void:
	var c := _fresh()
	var r := Progression.gain_exp(c, 15 + 34 + 57 + 20, db())
	assert_eq(c.level, 4, "three levels from one award")
	assert_eq(c.exp, 20, "the excess carries into level 4")
	assert_eq(r["levels_gained"], 3, "levels gained")
	assert_eq(r["ap_gained"], 15, "5 AP each")
	assert_eq(r["sp_gained"], 3, "1 SP each")
	assert_eq(r["max_hp_gained"], 48, "16 HP each")
	assert_eq(r["max_mp_gained"], 36, "12 MP each")
	assert_eq(c.base_max_hp, 98, "BeginnerHP(4) = 50 + 16 x 3")


func test_beginner_progression_to_level_11() -> void:
	var c := _fresh()
	var table: Array = db().formula("beginner")["hp_mp"]["by_level_1_to_10"]
	for row in table:
		var lvl := int(row["level"])
		if lvl > 1:
			Progression.gain_exp(c, Progression.exp_to_next(c.level, db()), db())
		assert_eq(c.level, lvl, "level %d" % lvl)
		assert_eq(c.base_max_hp, int(row["hp"]), "HP at %d" % lvl)
		assert_eq(c.base_max_mp, int(row["mp"]), "MP at %d" % lvl)
	assert_eq(c.sp, int(db().formula("beginner")["sp"]["beginner_total_sp"]), "9 SP by level 10")
	assert_eq(c.ap + 16 + 0, Progression.total_ap(10, db()), "unspent AP + the starting 16 = Total AP (nothing placed)")
	Progression.gain_exp(c, Progression.exp_to_next(10, db()), db())
	assert_eq(c.level, 11, "a Beginner can level past 10")
	assert_eq(c.sp, 9, "no Beginner SP after level 10 (combat.json adaptation)")
	assert_eq(c.ap, 9 + 50, "5 AP per level continues")


func test_level_cap() -> void:
	var c := _fresh()
	c.level = 99
	var r := Progression.gain_exp(c, 50000000, db())
	assert_eq(c.level, 100, "reaches the cap")
	assert_eq(c.exp, 0, "EXP does not accumulate at the cap")
	assert_eq(r["exp_added"], 9692044, "only the EXP that counted")
	var again := Progression.gain_exp(c, 1000, db())
	assert_eq([again["levels_gained"], again["exp_added"], c.level, c.exp], [0, 0, 100, 0], "nothing past level 100")


func test_allocate_ap() -> void:
	var c := _fresh()
	assert_true(Progression.allocate_ap(c, "str", 5), "spend 5 into STR")
	assert_eq(c.get_base_stat("str"), 9, "STR 4 + 5")
	assert_eq(c.ap, 4, "AP left")
	assert_true(Progression.allocate_ap(c, "DEX", 1, db()), "case-insensitive, canonical allowed list")
	assert_eq(c.get_base_stat("dex"), 5, "DEX")
	assert_false(Progression.allocate_ap(c, "luk", 10), "not enough AP")
	assert_false(Progression.allocate_ap(c, "luk", 0), "nothing to spend")
	assert_false(Progression.allocate_ap(c, "max_hp", 1, db()), "AP never goes into Max HP (combat.json ap_allocation)")
	assert_false(Progression.allocate_ap(c, "hp", 1), "or HP")
	assert_eq(c.ap, 3, "failed allocations spend nothing")
	var allowed: Array = db().formula("beginner")["ap"]["allocatable_stats"]
	assert_eq(allowed, ["str", "dex", "int", "luk"], "canonical allocatable stats")


func test_ap_is_retained_and_changes_derived_stats() -> void:
	var c := _fresh()
	var before := StatCalculator.snapshot(c, db())
	Progression.gain_exp(c, 15, db())
	assert_eq(c.ap, 14, "unused AP is kept")
	Progression.allocate_ap(c, "dex", 6)
	Progression.allocate_ap(c, "luk", 3)
	var after := StatCalculator.snapshot(c, db())
	assert_true(int(after["acc"]) > int(before["acc"]), "DEX/LUK raise ACC")
	assert_true(int(after["avoid"]) > int(before["avoid"]), "DEX/LUK raise EVA")


func test_class_hp_mp_formula() -> void:
	# hp_mp_gain.json parity examples: Beginner 10 (194/113), late Warrior 11 (572/275), Warrior 50 with 2nd job.
	for ex in db().formula("hp_mp_gain")["parity_examples"]:
		var adv := 0 if String(ex["class"]) == "beginner" else (2 if bool(ex.get("second_job", false)) else 1)
		var got := Progression.class_base_max_hp_mp(String(ex["class"]), int(ex["level"]), adv, db())
		assert_eq([got["max_hp"], got["max_mp"]], [int(ex["max_hp"]), int(ex["max_mp"])], "%s %s" % [ex["class"], ex["level"]])
	var w := Progression.base_max_hp_mp("warrior", 30, db())
	assert_eq([w["max_hp"], w["max_mp"]], [1104, 503], "Lv30 Warrior (guide example build)")


func test_level_up_gains_for_other_classes() -> void:
	var g := Progression.level_up_gains("warrior", 31, db())
	assert_eq(g["ap"], 5, "5 AP for every class")
	assert_eq([g["max_hp"], g["max_mp"]], [28, 12], "Warrior +28 / +12")
	var m := Progression.level_up_gains("magician", 31, db())
	assert_eq([m["max_hp"], m["max_mp"]], [16, 22], "Magician +16 / +22")


func test_death_penalty_example() -> void:
	var ex: Dictionary = db().formula("death")["exp_penalty"]["parity_example"]
	var c := _fresh()
	c.level = int(ex["level"])
	c.base_stats["luk"] = int(ex["base_luk"])
	c.exp = int(ex["exp_before"])
	var lost := Progression.apply_death_penalty(c, db())
	assert_eq(lost, int(ex["loss"]), "loss 9,570")
	assert_eq(c.exp, int(ex["exp_after"]), "EXP after 38,280")
	assert_eq(c.level, int(ex["level"]), "level kept")


func test_death_penalty_luk_table() -> void:
	# "LUK 4: 10% · LUK 10: 7% · LUK 20: 6% · LUK 50: 5.4% · LUK 100: 5.2%" of the level's requirement.
	var pct := {4: 10.0, 10: 7.0, 20: 6.0, 50: 5.4, 100: 5.2}
	var need := Progression.exp_to_next(20, db())
	for luk in pct:
		assert_eq(Progression.death_exp_loss(20, luk, db()), floori(need * pct[luk] / 100.0), "LUK %d" % luk)
	assert_eq(Progression.death_exp_loss(20, 1, db()), Progression.death_exp_loss(20, 4, db()), "LUK below 4 clamps to 4")
	assert_eq(Progression.death_exp_loss(100, 50, db()), 0, "no loss at the cap")


func test_death_never_below_zero_or_a_level() -> void:
	var c := _fresh()
	c.level = 8
	c.exp = 3
	var lost := Progression.apply_death_penalty(c, db())
	assert_eq(c.exp, 0, "EXP stops at 0")
	assert_eq(lost, 3, "only what the character had")
	assert_eq(c.level, 8, "a death never takes away a level")
	c.exp = 0
	assert_eq(Progression.apply_death_penalty(c, db()), 0, "nothing to lose")
	assert_eq(c.get_base_stat("luk"), 4, "uses base LUK, unchanged")


func test_death_uses_base_luk_not_gear() -> void:
	var c := _fresh()
	c.level = 20
	c.exp = 10000
	c.effects = [{"bonuses": {"luk": 96}}]
	var expected := Progression.death_exp_loss(20, 4, db())
	assert_eq(Progression.apply_death_penalty(c, db()), expected, "LUK from effects is ignored")
