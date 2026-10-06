extends TestCase
## The Beginner skills as data and rules: SkillDef reads every number from canonical formulas/beginner.json (plus the
## Three Snails timing row in attack_speed.json and its search band in attack_styles.json), SkillBook spends SP (one
## per level, max level 3, no prerequisites, no refunds) and decides whether a cast is allowed (learned, cast
## position, cooldown, MP, the shell item), SkillTargeting builds the canonical stepped search band, and SkillRules
## reads the MisoStory gaps in misostory/skills.json.

const SNAILS := "0001000"
const RECOVERY := "0001001"
const NIMBLE := "0001002"


func parity_keys() -> Dictionary:
	return {
		"test_catalog_is_the_three_canonical_beginner_skills": ["skill:0001000", "skill:0001001", "skill:0001002"],
		"test_three_snails_costs_and_damage_per_level": ["skill:0001000"],
		"test_recovery_costs_heal_and_cooldown_per_level": ["skill:0001001"],
		"test_nimble_feet_costs_speed_duration_and_cooldown_per_level": ["skill:0001002"],
		"test_cast_positions_come_from_the_records": ["skill:0001000", "skill:0001001", "skill:0001002"],
		"test_three_snails_action_follows_the_weapon_speed": ["skill:0001000"],
		"test_learning_spends_one_sp_per_level_up_to_the_max": ["mechanic:sp-allocation"],
		"test_the_nine_sp_of_levels_2_to_10_max_all_three_skills": ["mechanic:beginner-sp-gain", "mechanic:sp-allocation"],
		"test_cast_checks_and_their_order": ["skill:0001000", "skill:0001001", "skill:0001002"],
		"test_three_snails_search_band_is_the_canonical_stepped_band": ["skill:0001000"],
		"test_three_snails_picks_the_nearest_body_in_the_band": ["skill:0001000"],
	}


func _records() -> Dictionary:
	var out := {}
	for rec in db().formula("beginner").get("skills", []):
		out[String(rec["skill_id"])] = rec
	return out


func _character() -> CharacterState:
	var cr := CharacterFactory.create(CharacterFactory.default_params(db()), db())
	assert_true(cr.ok, "factory character")
	return cr.character


# --- SkillDef ---------------------------------------------------------------------------------------------------

func test_catalog_is_the_three_canonical_beginner_skills() -> void:
	var ids: Array = []
	for s in SkillDef.catalog("beginner", db()):
		ids.append(s.id)
		assert_eq(s.errors.size(), 0, "%s builds without errors: %s" % [s.id, "; ".join(s.errors)])
	assert_eq(ids, _records().keys(), "the catalog is beginner.json skills[] in record order")
	assert_eq(ids, [SNAILS, RECOVERY, NIMBLE], "Three Snails, Recovery, Nimble Feet")
	for sid in ids:
		var def := SkillDef.of(sid, db())
		assert_eq(def.max_level, int(_records()[sid]["max_level"]), "%s max level from the record" % sid)
		assert_eq(def.max_level, 3, "%s: max level 3 (MeowDB)" % sid)
		assert_eq(def.levels.size(), def.max_level, "%s: one row per level" % sid)
		assert_true(def.prerequisites.is_empty(), "%s: Beginner skills have no prerequisites" % sid)
	assert_eq(SkillDef.of(SNAILS, db()).kind, SkillDef.KIND_ATTACK, "Three Snails attacks")
	assert_eq(SkillDef.of(RECOVERY, db()).kind, SkillDef.KIND_HEAL, "Recovery heals over time")
	assert_eq(SkillDef.of(NIMBLE, db()).kind, SkillDef.KIND_BUFF, "Nimble Feet is a buff")
	assert_true(SkillDef.of("9999999", db()) == null, "an unknown id has no view")


func test_three_snails_costs_and_damage_per_level() -> void:
	var def := SkillDef.of(SNAILS, db())
	var rows: Array = _records()[SNAILS]["levels"]
	# MeowDB: Snail Shell -1, MP -3, Damage 15 / Blue Snail Shell -1, MP -4, 25 / Red Snail Shell -1, MP -5, 40.
	var pins := [[3, "348", 15.0], [4, "349", 25.0], [5, "351", 40.0]]
	for lv in range(1, 4):
		var row: Dictionary = rows[lv - 1]
		assert_eq(def.mp_cost(lv), int(row["mp_cost"]), "Lv%d MP from the record" % lv)
		assert_eq(def.item_cost(lv), {"item_id": String(row["item_cost_id"]), "qty": int(row["item_cost_qty"])}, "Lv%d shell" % lv)
		assert_eq(def.fixed_damage(lv), float(row["fixed_damage"]), "Lv%d damage" % lv)
		assert_eq(def.mp_cost(lv), pins[lv - 1][0], "Lv%d MP pin" % lv)
		assert_eq(String(def.item_cost(lv)["item_id"]), pins[lv - 1][1], "Lv%d shell pin" % lv)
		assert_eq(def.fixed_damage(lv), pins[lv - 1][2], "Lv%d damage pin" % lv)
		assert_eq(def.cooldown_s(lv), 0.0, "Lv%d: no cooldown" % lv)
		assert_true(db().has("items", String(row["item_cost_id"])), "Lv%d shell is a canonical item" % lv)
	assert_eq(def.targets, 1, "one target")
	assert_eq(def.range_px, 300.0, "300 px range")
	assert_eq(def.delivery, "projectile", "a projectile")
	assert_eq(def.item_cost(4), {}, "no level 4")


func test_recovery_costs_heal_and_cooldown_per_level() -> void:
	var def := SkillDef.of(RECOVERY, db())
	var rows: Array = _records()[RECOVERY]["levels"]
	var pins := [[5, 24], [10, 48], [15, 72]]
	for lv in range(1, 4):
		var row: Dictionary = rows[lv - 1]
		assert_eq(def.mp_cost(lv), int(row["mp_cost"]), "Lv%d MP" % lv)
		assert_eq(def.hp_total(lv), int(row["hp_total"]), "Lv%d HP total" % lv)
		assert_eq([def.mp_cost(lv), def.hp_total(lv)], pins[lv - 1], "Lv%d MeowDB pins" % lv)
		assert_eq(def.duration_s(lv), 30.0, "Lv%d: 30 s" % lv)
		assert_eq(def.cooldown_s(lv), 120.0, "Lv%d: 2 min cooldown" % lv)
		assert_eq(def.item_cost(lv), {}, "Lv%d: no item" % lv)
	assert_eq(def.action_ms(6, db()), 0, "no cast timing ('Timing unavailable')")


func test_nimble_feet_costs_speed_duration_and_cooldown_per_level() -> void:
	var def := SkillDef.of(NIMBLE, db())
	var rows: Array = _records()[NIMBLE]["levels"]
	var bonus := int(db().formula("movement")["nimble_feet_speed_bonus"])
	var pins := [[4, 10.0], [7, 20.0], [10, 30.0]]
	for lv in range(1, 4):
		var row: Dictionary = rows[lv - 1]
		assert_eq(def.mp_cost(lv), int(row["mp_cost"]), "Lv%d MP" % lv)
		assert_eq(def.speed_bonus(lv), int(row["speed_bonus"]), "Lv%d speed" % lv)
		assert_eq(def.speed_bonus(lv), bonus, "Lv%d: movement.json nimble_feet_speed_bonus agrees" % lv)
		assert_eq([def.mp_cost(lv), def.duration_s(lv)], pins[lv - 1], "Lv%d MeowDB pins" % lv)
		assert_eq(def.cooldown_s(lv), 180.0, "Lv%d: 3 min cooldown" % lv)
	assert_eq(def.action_ms(6, db()), 0, "no cast timing ('Timing unavailable')")


func test_cast_positions_come_from_the_records() -> void:
	assert_eq(SkillDef.of(SNAILS, db()).cast_positions, PackedStringArray(["ground"]), "Three Snails: ground only")
	for sid in [RECOVERY, NIMBLE]:
		assert_eq(SkillDef.of(sid, db()).cast_positions, PackedStringArray(["ground", "air", "rope"]), "%s: ground, air, or rope" % sid)
	assert_eq(SkillDef.parse_positions("Ground or air"), PackedStringArray(["ground", "air"]), "the parser reads any order")


func test_three_snails_action_follows_the_weapon_speed() -> void:
	var def := SkillDef.of(SNAILS, db())
	var row: Dictionary = db().formula("attack_speed")["three_snails"]
	assert_eq(def.base_action_ms, float(row["base_action_ms"]), "800 ms base action from attack_speed.json")
	assert_true(def.weapon_speed_based, "weapon-speed based")
	assert_eq(def.action_ms(6, db()), int(row["animation_ms_at_normal_6"]), "810 ms at Normal (6), as MeowDB shows")
	assert_eq(def.action_ms(4, db()), CombatFormula.animation_time_ms(800.0, 4, db()), "a faster weapon casts faster")
	assert_true(def.action_ms(4, db()) < def.action_ms(6, db()), "tier 4 is quicker than tier 6")


# --- SP ----------------------------------------------------------------------------------------------------------

func test_learning_spends_one_sp_per_level_up_to_the_max() -> void:
	var c := _character()
	assert_eq(c.sp, 0, "a new Beginner has 0 SP")
	var none := SkillBook.learn(c, NIMBLE, db())
	assert_false(none.ok, "no SP, no level")
	assert_eq(String(none.code), SkillBook.NO_SP, "refused for SP")
	c.sp = 4
	for lv in range(1, 4):
		var r := SkillBook.learn(c, NIMBLE, db())
		assert_true(r.ok, "level %d learned" % lv)
		assert_eq(int(r.level), lv, "new level %d" % lv)
		assert_eq(SkillBook.level_of(c, NIMBLE), lv, "stored in CharacterState.skills")
		assert_eq(c.sp, 4 - lv, "one SP per level")
	var over := SkillBook.learn(c, NIMBLE, db())
	assert_false(over.ok, "no 4th level")
	assert_eq(String(over.code), SkillBook.MAX_LEVEL, "refused at the max level")
	assert_eq(c.sp, 1, "a refused learn keeps the SP")
	assert_eq(String(SkillBook.learn(c, "9999999", db()).code), SkillBook.UNKNOWN_SKILL, "unknown skill")
	assert_eq(c.skills, {NIMBLE: 3}, "only the learned skill is stored")
	assert_false(SkillBook.new().has_method("unlearn"), "no refunds: MeowDB documents none")


func test_the_nine_sp_of_levels_2_to_10_max_all_three_skills() -> void:
	var c := _character()
	var need := 0
	for lv in range(1, 10):
		need += Progression.exp_to_next(lv, db())
	Progression.gain_exp(c, need, db())
	assert_eq(c.level, 10, "level 10")
	var sp_total := int(db().formula("beginner")["sp"]["beginner_total_sp"])
	assert_eq(c.sp, sp_total, "9 SP by level 10 (beginner.json sp)")
	var spent := 0
	for def in SkillDef.catalog(c.job, db()):
		while SkillBook.learn(c, def.id, db()).ok:
			spent += 1
	assert_eq(spent, sp_total, "exactly enough to max all three")
	assert_eq(c.sp, 0, "nothing left")
	for def in SkillDef.catalog(c.job, db()):
		assert_eq(SkillBook.level_of(c, def.id), def.max_level, "%s maxed" % def.name)


# --- casting -----------------------------------------------------------------------------------------------------

func test_cast_checks_and_their_order() -> void:
	var c := _character()
	assert_eq(String(SkillBook.check_cast(c, SNAILS, db(), "ground").code), SkillBook.NOT_LEARNED, "not learned")
	c.skills = {SNAILS: 1, RECOVERY: 1, NIMBLE: 1}
	c.mp = 0
	for pos in ["air", "rope"]:
		assert_eq(String(SkillBook.check_cast(c, SNAILS, db(), pos).code), SkillBook.POSITION, "Three Snails from %s" % pos)
	assert_eq(String(SkillBook.check_cast(c, SNAILS, db(), "ground").code), SkillBook.NO_MP, "no MP")
	c.mp = 3
	var no_shell := SkillBook.check_cast(c, SNAILS, db(), "ground")
	assert_eq(String(no_shell.code), SkillBook.NO_ITEM, "no Snail Shell")
	assert_eq(String(no_shell.item_id), "348", "names the shell it needs")
	ItemService.new(c, db(), null).gain("348", 1)
	var ok := SkillBook.check_cast(c, SNAILS, db(), "ground")
	assert_true(ok.ok, "learned, ground, MP 3 and a shell")
	assert_eq([int(ok.mp), String(ok.item_id), int(ok.item_qty), int(ok.level)], [3, "348", 1, 1], "the level 1 costs")
	c.mp = 5
	for pos in ["ground", "air", "rope"]:
		assert_true(SkillBook.check_cast(c, RECOVERY, db(), pos).ok, "Recovery from %s" % pos)
	EffectBook.start_cooldown(c, RECOVERY, 30.0)
	var cd := SkillBook.check_cast(c, RECOVERY, db(), "ground")
	assert_eq(String(cd.code), SkillBook.COOLDOWN, "cooling down")
	assert_near(float(cd.cooldown_left), 30.0, 1e-9, "the time left")
	assert_true(SkillBook.affordable(c, NIMBLE, db()), "MP 5 pays Nimble Feet Lv1 (4)")
	c.mp = 3
	assert_false(SkillBook.affordable(c, NIMBLE, db()), "MP 3 does not")


# --- the search band ----------------------------------------------------------------------------------------------

func test_three_snails_search_band_is_the_canonical_stepped_band() -> void:
	var def := SkillDef.of(SNAILS, db())
	var styles := db().formula("attack_styles")
	var t: Dictionary = styles["three_snails_targeting"]
	var shape: Dictionary = styles["ranged_search_bands"]
	assert_eq(float(def.band["start_px"]), float(t["band_start_px"]), "starts 50 px ahead")
	assert_eq(float(def.band["reach_px"]), float(t["horizontal_reach_px"]), "300 px")
	assert_eq(float(def.band["band_px"]), float(shape["band_length_px"]), "20 px bands")
	assert_eq(float(def.band["aim_px"]), float(shape["aim_height_px"]), "28 px aim")
	var bands := SkillTargeting.bands_px(def.band)
	assert_eq(bands.size(), 13, "bands at 50, 70, ... 290 px")
	assert_eq(bands[0], Rect2(50, -28 - 12, 20, 24), "the first band: half-height floor(50 / 4) = 12 around 28 px up")
	assert_eq(bands[12], Rect2(290, -28 - 72, 10, 144), "the last band stops at the 300 px reach")
	var ext := SkillTargeting.vertical_extent_px(bands)
	assert_eq(ext, {"up_px": float(t["vertical_reach_px"]["up"]), "down_px": float(t["vertical_reach_px"]["down"])},
		"the bands reach exactly MeowDB's 100 px up / 44 px down")


func test_three_snails_picks_the_nearest_body_in_the_band() -> void:
	var bands := SkillTargeting.bands_px(SkillDef.of(SNAILS, db()).band)
	var snail := MonsterCombatStats.from_id("2", db())
	var depth := CombatReach.attack_box_depth_px(db())
	var px := WorldScale.actor(1.0)
	var at := func(ahead_px: float, up_px: float = 0.0, side_px: float = 0.0, order: int = 0) -> Dictionary:
		return {"node": null, "feet": Vector3(ahead_px * px, up_px * px, side_px * px), "touch_px": snail.touch_zone_px,
			"depth_px": CombatReach.touch_zone_depth_px(snail, db()), "spawn_order": order, "name": "%d,%d" % [ahead_px, up_px]}
	var pick := func(cands: Array) -> String:
		var hits := SkillTargeting.pick(Vector3.ZERO, Vector3.RIGHT, bands, depth, cands, 1)
		return "" if hits.is_empty() else String(hits[0]["name"])
	assert_eq(pick.call([at.call(200.0)]), "200,0", "a Snail 200 px ahead")
	assert_eq(pick.call([at.call(25.0)]), "", "a Snail whose body ends before the 50 px band start")
	assert_eq(pick.call([at.call(310.0)]), "310,0", "a body overlapping the last band")
	assert_eq(pick.call([at.call(330.0)]), "", "beyond 300 px")
	assert_eq(pick.call([at.call(-150.0)]), "", "never behind")
	assert_eq(pick.call([at.call(200.0, 50.0)]), "200,50", "50 px above the feet at 200 px: inside the widened band")
	assert_eq(pick.call([at.call(120.0, 70.0)]), "", "70 px up at 120 px: above the narrower band there")
	assert_eq(pick.call([at.call(280.0, 130.0)]), "", "above 100 px up")
	assert_eq(pick.call([at.call(200.0, 0.0, 200.0)]), "", "far off the facing line (isometric depth)")
	assert_eq(pick.call([at.call(250.0, 0.0, 0.0, 0), at.call(120.0, 0.0, 0.0, 1)]), "120,0", "nearest first")


# --- MisoStory values ----------------------------------------------------------------------------------------------

func test_skill_rules_read_the_adaptation_table() -> void:
	var r := SkillRules.of(db())
	assert_eq(r.errors.size(), 0, "misostory/skills.json is complete: %s" % "; ".join(r.errors))
	var t: Dictionary = db().miso_table("skills")
	assert_eq(r.recovery_tick_s, float(t["recovery_heal"]["tick_s"]), "Recovery tick")
	assert_eq(r.buff_lockout_s, float(t["buff_cast"]["lockout_s"]), "buff lockout")
	assert_eq(r.whiff_consumes_costs, bool(t["three_snails"]["whiff_consumes_costs"]), "whiff costs")
	assert_eq(r.end_effects_on_death, bool(t["effects_on_death"]["end_effects"]), "death ends effects")
	assert_false(bool(t["recovery_heal"]["verified"]), "an adaptation, never verified")
	var broken := SkillRules.from_table({"recovery_heal": {"tick_s": -1, "distribution": "equal_ticks"}})
	assert_true(broken.errors.size() >= 4, "missing sections and a bad value are reported: %s" % "; ".join(broken.errors))
	assert_eq(broken.recovery_tick_s, 0.0, "a bad tick turns the ticks off (one heal at the end)")
	assert_eq(SkillRules.from_table(null).errors.size(), 1, "a missing table is one error")
	# terrain_check (#6): walls block Three Snails; the canonical value stays a source-data gap.
	assert_true(r.terrain_check, "the owner's wall rule is on")
	assert_eq(r.errors.size(), 0, "skills.json reads cleanly: %s" % "; ".join(r.errors))
	assert_eq(r.sight_blocking_hulls, PackedStringArray(t["three_snails"]["sight_blocking_hulls"]), "the blocking hull list")
	assert_true(r.sight_blocking_hulls.has("X1010000_YellowHouse") and not r.sight_blocking_hulls.has("Barrel"),
		"a house blocks, a barrel does not")
	assert_true(String(t["three_snails"]["terrain_check_reason"]).contains("#6"), "the reason cites the owner's ruling")
	var open: Dictionary = t.duplicate(true)
	open["three_snails"]["terrain_check"] = false
	var o := SkillRules.from_table(open)
	assert_eq(o.errors.size(), 0, "false is accepted too")
	assert_false(o.terrain_check, "no wall test")
	assert_eq(o.sight_blocking_hulls.size(), 0, "and no list read")
	var bad: Dictionary = t.duplicate(true)
	bad["three_snails"]["sight_blocking_hulls"] = ["House_Cottage_Red", 3]
	var b := SkillRules.from_table(bad)
	assert_eq(b.errors.size(), 1, "a malformed list is reported: %s" % "; ".join(b.errors))
	assert_eq(b.sight_blocking_hulls.size(), 0, "and read as empty")
