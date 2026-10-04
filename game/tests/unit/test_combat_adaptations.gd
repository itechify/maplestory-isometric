extends TestCase
## data/misostory/combat.json: every value MeowDB does not publish is marked with a reason and verified: false,
## and the rules that read it behave as documented (stagger, invincibility, knockback).


func _sections_with_values(d: Dictionary, path: String, out: Array) -> void:
	# A section is any Dictionary that holds at least one non-Dictionary value other than reason/verified.
	var leaf := false
	for k in d:
		if not d[k] is Dictionary and k != "reason" and k != "verified":
			leaf = true
	if leaf:
		out.append([path, d])
	for k in d:
		if d[k] is Dictionary:
			_sections_with_values(d[k], path + "." + String(k), out)


func test_every_adaptation_has_a_reason_and_is_unverified() -> void:
	var table: Variant = db().miso_table("combat")
	assert_true(table is Dictionary, "data/misostory/combat.json loads")
	if not table is Dictionary:
		return
	var sections: Array = []
	for k in table:
		if table[k] is Dictionary:
			_sections_with_values(table[k], String(k), sections)
	assert_true(sections.size() >= 8, "adaptation sections found: %d" % sections.size())
	for s in sections:
		var d: Dictionary = s[1]
		assert_true(String(d.get("reason", "")).length() > 40, "%s has a reason" % s[0])
		assert_eq(d.get("verified", null), false, "%s is verified: false" % s[0])


func test_rules_read_every_section_without_errors() -> void:
	var r := CombatRules.of(db())
	for section in ["bare_hands", "post_hit_invincibility", "player_knockback", "monster_knockback",
			"fixed_damage_skills", "level_up", "beginner_sp_after_level_10", "ap_allocation", "isometric_reach"]:
		assert_false(r.adaptation(section).is_empty(), section)
	assert_eq(r.errors.size(), 0, "rules errors: %s" % ", ".join(r.errors))


func test_post_hit_invincibility_is_canonical() -> void:
	var canonical := float(db().formula("accuracy")["after_hit"]["post_hit_invincibility_s"])
	assert_eq(canonical, 1.5, "MeowDB: 1.5 s")
	assert_eq(CombatFormula.post_hit_invincibility_s(db()), canonical, "no override in combat.json")


func test_monster_stagger_rule_uses_the_kb_stat() -> void:
	assert_true(CombatFormula.monster_staggers(500, 500, db()), "500 KB needs 500+ damage")
	assert_false(CombatFormula.monster_staggers(499, 500, db()), "499 does not stagger")
	assert_false(CombatFormula.monster_staggers(0, 0, db()), "a miss never staggers")
	for mid in ["1", "2", "3", "4", "5", "9"]:
		var m := MonsterCombatStats.from_id(mid, db())
		assert_eq(m.kb, 1, "monster %s KB" % mid)
		assert_true(CombatFormula.monster_staggers(1, m.kb, db()), "monster %s staggers on any hit" % mid)
		assert_near(CombatFormula.monster_stagger_s(m, db()), m.hit_animation_ms / 1000.0, 1e-9, "monster %s stagger = hit clip" % mid)
	var no_clip := MonsterCombatStats.new()
	assert_eq(CombatFormula.monster_stagger_s(no_clip, db()), float(db().miso_table("combat")["monster_knockback"]["fallback_stagger_s"]), "fallback")
	assert_true(CombatFormula.monster_knockback_distance_px(db()) > 0.0, "knockback distance")


func test_player_knockback_combines_canonical_and_adaptation() -> void:
	var kb := CombatFormula.player_knockback(db())
	var model: Dictionary = db().formula("movement")["knockback_airtime"]
	assert_eq(kb["upward_speed_px_s"], float(model["upward_speed_px_per_s"]), "canonical 270 px/s")
	assert_eq(kb["gravity_px_s2"], float(model["gravity_px_per_s2"]), "canonical gravity")
	assert_eq(kb["airtime_s"], float(model["same_height_airtime_s"]), "canonical airtime")
	# One source for the horizontal push: the player controller's movement.json (combat.json must not hold a second,
	# conflicting speed).
	assert_eq(kb["horizontal_speed_mps"], float(db().miso_table("movement")["knockback_horizontal_speed_mps"]), "adaptation (movement.json)")
	var combat_kb: Dictionary = db().miso_table("combat")["player_knockback"]
	for k in combat_kb:
		assert_false(String(k).contains("speed"), "combat.json player_knockback holds no speed (%s)" % k)
	assert_true(bool(combat_kb["on_landed_hit"]), "landed hits push")
	assert_false(bool(combat_kb["on_miss_or_guard"]), "misses and guards do not push")
