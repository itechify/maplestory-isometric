extends TestCase
## StatCalculator: totals, derived stats per job, HP/MP with gear, limits, speed/jump caps, the stat-window range.


## Stands in for the items system's Equipment through its fixed contract (item_in / total_bonuses / weapon_id).
class FakeEquipment:
	extends Equipment
	var slots: Dictionary = {}
	var bonus: Dictionary = {}

	func item_in(slot: String) -> String:
		return String(slots.get(slot, ""))

	func total_bonuses(_db: ContentDB) -> Dictionary:
		return bonus.duplicate()


func _char(level: int, stats: Dictionary) -> CharacterState:
	var c := CharacterState.new()
	c.level = level
	c.base_stats = stats.duplicate()
	var hm := Progression.base_max_hp_mp("beginner", level, db())
	c.base_max_hp = int(hm["max_hp"])
	c.base_max_mp = int(hm["max_mp"])
	c.hp = c.base_max_hp
	c.mp = c.base_max_mp
	return c


func test_totals_are_base_plus_equipment_plus_effects() -> void:
	var c := _char(5, {"str": 20, "dex": 6, "int": 4, "luk": 4})
	var eq := FakeEquipment.new()
	eq.slots = {"weapon": "541"}
	eq.bonus = {"watk": 17, "str": 1, "wdef": 6}
	c.equipment = eq
	c.effects = [{"id": "test", "bonuses": {"str": 2, "speed": 10}}, {"id": "no_bonus"}]
	assert_eq(StatCalculator.total_stat(c, "str", db()), 23, "20 base + 1 gear + 2 effect")
	assert_eq(StatCalculator.total_stat(c, "dex", db()), 6, "no bonus")
	var snap := StatCalculator.snapshot(c, db())
	assert_eq(snap["str"], 23, "snapshot total")
	assert_eq(snap["watk"], 17, "weapon W.ATK pool")
	assert_eq(snap["wdef"], int(23 / 4.0) + 6, "derived WDEF + gear WDEF")
	assert_eq(snap["speed"], 110, "Nimble Feet style +10 speed")
	assert_eq(snap["weapon_id"], "541", "weapon from Equipment.weapon_id()")
	for k in ["str", "dex", "int", "luk", "max_hp", "max_mp", "watk", "matk", "wdef", "mdef", "acc", "avoid", "magic", "speed", "jump", "damage_min", "damage_max"]:
		assert_has(snap, k, "snapshot contract key")
	assert_eq(c.get_base_stat("str"), 20, "base values are never changed by derivation")


func test_beginner_derived_stats() -> void:
	var snap := StatCalculator.compute("beginner", 1, {"str": 13, "dex": 4, "int": 4, "luk": 4}, 50, 5, {}, "", db())
	assert_eq(snap["acc"], 8, "floor((1.2 x 4 + 2 x 1 + 0.6 x 4) / 2.5 + 5)")
	assert_eq(snap["avoid"], 6, "floor(4/3) + floor(4/6) + 5")
	assert_eq(snap["magic"], 2, "floor(4/2)")
	assert_eq(snap["wdef"], 3, "floor(13/4)")
	assert_eq(snap["mdef"], 1, "floor(4/4)")
	assert_eq(snap["crit_rate_pct"], 5.0, "base crit rate")
	assert_eq(snap["crit_damage_pct"], 20.0, "base crit damage")


func test_derived_stats_per_job() -> void:
	# /formulas Try-values defaults (derived_stats.json parity_examples[0]).
	var ex: Dictionary = db().formula("derived_stats")["parity_examples"][0]
	var i: Dictionary = ex["input"]
	var o: Dictionary = ex["output"]
	var lvl := int(i["level"])
	for job in ["beginner", "warrior", "bowman", "thief", "magician"]:
		assert_eq(StatCalculator.derived_accuracy(job, lvl, int(i["dex"]), int(i["int"]), int(i["luk"]), db()), int(o[job + "_acc"]), job + " ACC")
	assert_eq(StatCalculator.derived_avoid(int(i["dex"]), int(i["luk"]), db()), int(o["eva"]), "EVA")
	assert_eq(StatCalculator.derived_magic(int(i["int"]), db()), int(o["magic"]), "Magic")
	assert_eq(StatCalculator.derived_wdef(int(i["str"]), db()), int(o["wdef"]), "WDEF")
	assert_eq(StatCalculator.derived_mdef(int(i["int"]), db()), int(o["mdef"]), "MDEF")
	# Jobs differ: the same stats give different ACC.
	assert_ne(StatCalculator.derived_accuracy("beginner", 30, 30, 4, 4, db()), StatCalculator.derived_accuracy("warrior", 30, 30, 4, 4, db()), "Warrior ACC differs")


func test_guide_lv30_warrior_example() -> void:
	var snap := StatCalculator.compute("warrior", 30, {"str": 132, "dex": 30, "int": 4, "luk": 4}, 1104, 503, {"watk": 47}, "551", db())
	assert_eq([snap["damage_min"], snap["damage_max"]], [60, 172], "damage 60-172")
	assert_eq(snap["acc"], 49, "ACC 49")
	assert_eq(snap["avoid"], 11, "EVA 11")
	assert_eq(snap["magic"], 2, "Magic 2")
	assert_eq(snap["wdef"], 33, "WDEF 33")
	assert_eq(snap["mdef"], 1, "MDEF 1")


func test_max_hp_mp_with_gear_and_percent() -> void:
	assert_eq(StatCalculator.hp_mp_total(100, {"max_hp_pct": 25, "max_hp": 30}, "max_hp"), 155, "trunc(100 x 1.25) + 30")
	assert_eq(StatCalculator.hp_mp_total(99, {"max_hp_pct": 25}, "max_hp"), 123, "trunc(123.75)")
	var c := _char(10, {"str": 4, "dex": 4, "int": 4, "luk": 4})
	assert_eq(StatCalculator.max_hp(c, db()), 194, "Beginner Lv10 base HP")
	assert_eq(StatCalculator.max_mp(c, db()), 113, "Beginner Lv10 base MP")
	var eq := FakeEquipment.new()
	eq.bonus = {"max_hp": 12, "max_mp": 17}
	c.equipment = eq
	assert_eq(StatCalculator.max_hp(c, db()), 206, "+ equipment HP")
	assert_eq(StatCalculator.max_mp(c, db()), 130, "+ equipment MP")


func test_hp_mp_limits() -> void:
	var c := _char(1, {"str": 4, "dex": 4, "int": 4, "luk": 4})
	assert_eq(StatCalculator.change_hp(c, -20, db()), -20, "damage")
	assert_eq(c.hp, 30, "HP after damage")
	assert_eq(StatCalculator.change_hp(c, 100, db()), 20, "healing stops at max HP")
	assert_eq(c.hp, 50, "full")
	assert_eq(StatCalculator.change_hp(c, -999, db()), -50, "HP never below 0")
	assert_eq(c.hp, 0, "zero HP")
	assert_true(Progression.is_dead(c, db()), "dies at 0 HP")
	assert_eq(StatCalculator.change_mp(c, 50, db()), 0, "MP already full")
	c.hp = 999
	c.mp = 999
	StatCalculator.clamp_vitals(c, db())
	assert_eq([c.hp, c.mp], [50, 5], "clamped to maxima")


func test_speed_and_jump_caps() -> void:
	var c := _char(1, {"str": 4, "dex": 4, "int": 4, "luk": 4})
	assert_eq(StatCalculator.speed(c, db()), 100, "base speed")
	assert_eq(StatCalculator.jump(c, db()), 100, "base jump")
	c.effects = [{"bonuses": {"speed": 80, "jump": 50}}]
	assert_eq(StatCalculator.speed(c, db()), 140, "speed cap")
	assert_eq(StatCalculator.jump(c, db()), 120, "jump cap")


func test_stat_window_range() -> void:
	var c := _char(1, {"str": 13, "dex": 4, "int": 4, "luk": 4})
	var eq := FakeEquipment.new()
	eq.slots = {"weapon": "576"}
	eq.bonus = {"watk": 17}
	c.equipment = eq
	var r := StatCalculator.damage_range(c, db())
	assert_eq([r["min"], r["max"], r["avg"]], [14, 22, 18.3], "Hand Axe Lv1: stab MIN, swing MAX (oracles.md)")
	c.equipment = FakeEquipment.new()
	var bare := StatCalculator.damage_range(c, db())
	assert_eq([bare["min"], bare["max"]], [1, 1], "bare hands (combat.json adaptation)")


func test_shield_guard_from_the_shield_slot() -> void:
	var c := _char(1, {"str": 4, "dex": 4, "int": 4, "luk": 4})
	var eq := FakeEquipment.new()
	eq.slots = {"shield": "541"}  # any item id with stats; only its WDEF line is read (the Sword has none)
	c.equipment = eq
	assert_eq(StatCalculator.snapshot(c, db())["shield_wdef"], 0, "no WDEF line")
	assert_eq(StatCalculator.combat_stats(c, db()).shield_wdef, 0, "combat record")


func test_combat_stats_record() -> void:
	var c := _char(1, {"str": 13, "dex": 4, "int": 4, "luk": 4})
	var eq := FakeEquipment.new()
	eq.slots = {"weapon": "541"}
	eq.bonus = {"watk": 17}
	c.equipment = eq
	var s := PlayerCombatStats.from_character(c, db())
	assert_eq(s.level, 1, "level")
	assert_eq(s.total_watk, 17, "W.ATK")
	assert_eq(s.acc, 8, "ACC")
	assert_eq(s.primary(), 13.0, "STR primary")
	assert_eq(s.secondary(), 4.0, "DEX secondary")
	assert_near(s.crit_rate, 0.05, 1e-12, "c")
	assert_near(s.crit_damage, 0.2, 1e-12, "d")
	assert_eq(s.weapon.item_id, "541", "weapon")


func test_jobs_plug_in() -> void:
	assert_eq(StatCalculator.job_class("beginner"), "beginner", "Beginner")
	for job in ["warrior", "magician", "bowman", "thief"]:
		assert_eq(StatCalculator.job_class(job), job, job)
		assert_true(CombatRules.of(db()).acc_by_job.has(job), "%s has an ACC row" % job)
		assert_true((db().formula("hp_mp_gain")["per_class"] as Dictionary).has(job), "%s has HP/MP rates" % job)


func test_bare_hands_watk_line_joins_the_pool() -> void:
	# combat.json bare_hands.weapon_watk is the empty weapon slot's W.ATK line. Shipped value 0 -> 1-1 (asserted in
	# test_stat_window_range); on a private ContentDB with the line patched the window must follow the formula.
	var shipped := int(db().miso_table("combat")["bare_hands"]["weapon_watk"])
	assert_eq(StatCalculator.compute("beginner", 1, {"str": 13, "dex": 4, "int": 4, "luk": 4}, 50, 5, {}, "", db())["watk"], shipped, "shipped bare-hands line")
	var private_db := ContentDB.new().load_all()
	var bh: Dictionary = private_db.miso_table("combat")["bare_hands"]
	bh["weapon_watk"] = 10
	var snap := StatCalculator.compute("beginner", 1, {"str": 13, "dex": 4, "int": 4, "luk": 4}, 50, 5, {"watk": 2}, "", private_db)
	assert_eq(snap["watk"], 12, "bare-hands line 10 + a glove's 2 in one pool")
	var wm := float(bh["weapon_mult"])
	var m := CombatFormula.mastery_factor(0, private_db)
	# Barehanded: stab 100% (canonical), STR primary / DEX secondary (adaptation).
	assert_eq(snap["damage_min"], int(12 * (0.8 + (13 * m * wm + 4) / 100.0)), "MIN with the patched line")
	assert_eq(snap["damage_max"], int(12 * (1.0 + (13 * wm + 4) / 100.0)), "MAX with the patched line")
	# An equipped weapon's own line comes from the equipment bonuses only (never the bare-hands line).
	var sword := StatCalculator.compute("beginner", 1, {"str": 13, "dex": 4, "int": 4, "luk": 4}, 50, 5, {"watk": 17}, "541", private_db)
	assert_eq(sword["watk"], 17, "weapon line not doubled")


func test_shield_guard_uses_the_shield_pieces_own_stats() -> void:
	# Equipment.total_bonuses reads a piece's per-instance "stats" (a scroll result) before its canonical stats; the
	# Shield Guard WDEF must follow the same rule.
	var c := _char(1, {"str": 4, "dex": 4, "int": 4, "luk": 4})
	var canonical_wdef := int(db().item("1157")["stats"]["wdef"])
	assert_true(c.equipment.force_equip("shield", "1157", db()), "any WDEF piece in the shield slot")
	assert_eq(StatCalculator.snapshot(c, db())["shield_wdef"], canonical_wdef, "clean piece: canonical WDEF")
	c.equipment = Equipment.new()
	assert_true(c.equipment.force_equip("shield", "1157", db(), {"stats": {"wdef": 100}}), "scrolled piece")
	var snap := StatCalculator.snapshot(c, db())
	assert_eq(snap["shield_wdef"], 100, "per-instance WDEF")
	assert_near(float(snap["shield_guard_chance"]), 100.0 / 600.0, 1e-12, "guard = W / (W + 500)")
	assert_eq(StatCalculator.combat_stats(c, db()).shield_wdef, 100, "combat record")
