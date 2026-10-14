extends TestCase
## MonsterDef: the canonical record joined with data/misostory/monsters/_shared.json and <id>.json (the species file
## overrides the shared table). Gameplay numbers must be the canonical ones (read here straight from the canonical
## JSON, never restated), the derived conversions must follow their documented rule, and every Maple Island species
## must be complete.

const SPECIES := ["1", "2", "3", "4", "5", "9"]


## Contract C6: the stat comparison proves each species' monster-stats row (every stat the runtime reads, plus MP).
func parity_keys() -> Dictionary:
	var stats: Array = []
	for id in SPECIES:
		stats.append("monster-stats:%s" % id)
	return {"test_gameplay_stats_are_canonical": stats, "test_monster_mp_is_the_canonical_record_value": stats}


func test_every_maple_island_species_builds_without_errors() -> void:
	for id in SPECIES:
		var d := MonsterDef.build(id, db())
		assert_eq(d.errors.size(), 0, "monster %s: %s" % [id, "; ".join(d.errors)])
		assert_true(d.stats != null, "%s stats" % id)


func test_every_monster_on_a_maple_island_map_has_an_adaptation() -> void:
	var seen := {}
	for map_id in db().ids("maps"):
		for s in db().map(map_id).get("spawns", []):
			seen[String((s as Dictionary).get("mob_id", ""))] = true
	for id in seen:
		assert_false(db().miso_entity("monsters", id).is_empty(), "data/misostory/monsters/%s.json missing" % id)


func test_gameplay_stats_are_canonical() -> void:
	for id in SPECIES:
		var rec := db().monster(id)
		var d := MonsterDef.build(id, db())
		assert_eq(d.max_hp, int(rec["hp"]), "%s hp" % id)
		assert_eq(d.exp_reward, int(rec["exp"]), "%s exp" % id)
		assert_eq(d.level, int(rec["level"]), "%s level" % id)
		assert_eq(d.stats.pdmg, int(rec["physical_damage"]), "%s P.DMG" % id)
		assert_eq(d.stats.mdmg, int(rec["magic_damage"]), "%s M.DMG" % id)
		assert_eq(d.stats.pdef, int(rec["physical_defense"]), "%s P.DEF" % id)
		assert_eq(d.stats.mdef, int(rec["magic_defense"]), "%s M.DEF" % id)
		assert_eq(d.stats.avoid, int(rec["avoidability"]), "%s EVA (avoidability)" % id)
		assert_eq(d.stats.level, int(rec["level"]), "%s combat level" % id)
		assert_eq(d.stats.hp, int(rec["hp"]), "%s combat HP" % id)
		assert_eq(d.stats.exp, int(rec["exp"]), "%s combat EXP" % id)
		assert_eq(d.stats.acc, int(rec["accuracy"]), "%s ACC" % id)
		assert_eq(d.stats.kb, int(rec["knockback_threshold_damage"]), "%s KB" % id)
		assert_eq(d.speed_modifier, int(rec["speed"]), "%s speed modifier" % id)
		assert_eq(d.peaceful, bool(rec["flags"]["non_aggressive"]), "%s Peace flag" % id)
		assert_near(d.die_fade_s, float(rec["die_fade_ms"]) / 1000.0, 1e-9, "%s die fade" % id)
		var tz: Array = rec["touch_zone_px"]
		assert_near(d.touch_size_m.x, WorldScale.actor(float(tz[0])), 1e-5, "%s touch width" % id)
		assert_near(d.touch_size_m.y, WorldScale.actor(float(tz[1])), 1e-5, "%s touch height" % id)


## MeowDB shows a monster's MP only in its "Other Attributes" list ("MP 30"), which the extractor reads (the record's
## field_sources.mp). No Maple Island monster has a skill to spend MP on, so no runtime system holds monster MP:
## MonsterDef and MonsterCombatStats carry none, and the game can show no MP other than the record's.
func test_monster_mp_is_the_canonical_record_value() -> void:
	for id in SPECIES:
		var rec := db().monster(id)
		var mp: Variant = rec.get("mp", null)
		assert_true(mp is int or mp is float, "%s MP is a published number: %s" % [id, mp])
		var labels: Array = (rec.get("other_attributes", []) as Array).map(
			func(a: Variant) -> String: return String((a as Dictionary).get("label", "")) if a is Dictionary else "")
		assert_true(labels.has("MP %d" % int(mp)), "%s MP %s is the page's 'MP n' attribute %s" % [id, mp, labels])
		assert_true(String((rec.get("field_sources", {}) as Dictionary).get("mp", {}).get("url", "")).ends_with("/monsters/%s" % id),
			"%s MP cites its MeowDB monster page" % id)
		var skills: Variant = rec.get("skills", [])
		assert_true(not (skills is Array) or (skills as Array).is_empty(), "%s has no monster skill to spend MP on" % id)
		var d := MonsterDef.build(id, db())
		assert_false("mp" in d, "%s: MonsterDef holds no MP of its own" % id)
		assert_false("mp" in d.stats, "%s: MonsterCombatStats holds no MP of its own" % id)


func test_movement_kind_follows_the_canonical_label() -> void:
	for id in SPECIES:
		var d := MonsterDef.build(id, db())
		var jumps := String(db().monster(id)["movement"]["label"]).contains("Jump")
		assert_eq(d.is_jumper(), jumps, "%s movement kind vs '%s'" % [id, d.movement_label])
	assert_true(MonsterDef.build("9", db()).is_jumper(), "Orange Mushroom hops")


func test_speed_is_the_walk_line_slope_times_base_plus_modifier() -> void:
	# The derivation is read from the canonical movement record, never from a restated 1.25.
	var mv := db().formula("movement")
	var ws: Dictionary = mv["walk_speed"]
	var slope := (float(ws["cap_px_per_s"]) - float(ws["base_px_per_s"])) / (float(mv["speed_cap"]) - float(mv["base_speed"]))
	for id in SPECIES:
		var d := MonsterDef.build(id, db())
		var px := slope * (float(mv["base_speed"]) + float(db().monster(id)["speed"]))
		assert_near(d.move_speed_mps, WorldScale.h(px), 1e-9, "%s speed" % id)
	# Pins of the documented examples (docs and data reasons quote them).
	assert_near(MonsterDef.build("2", db()).move_speed_mps, 0.875, 1e-6, "Snail 43.75 px/s")
	assert_near(MonsterDef.build("9", db()).move_speed_mps, 2.5, 1e-6, "Orange Mushroom 125 px/s")
	var player_walk := WorldScale.h(float(ws["base_px_per_s"]))
	for id in SPECIES:
		assert_true(MonsterDef.build(id, db()).move_speed_mps < player_walk, "%s slower than the player" % id)


func test_hop_uses_the_character_base_jump_and_canonical_gravity() -> void:
	var mv := db().formula("movement")
	var d := MonsterDef.build("9", db())
	var base_px := 0.0
	for row in mv["jump_height_px_by_jump"]:
		if float(row["jump"]) == float(mv["base_jump"]):
			base_px = float(row["height_px"])
	assert_near(d.hop_apex_m, WorldScale.v(base_px), 1e-9, "apex = Jump 100 height")
	assert_near(d.gravity_mps2, WorldScale.v(float(mv["knockback_airtime"]["gravity_px_per_s2"])), 1e-9, "gravity")
	assert_true(d.hop_interval_s.x > 0.0 and d.hop_interval_s.y >= d.hop_interval_s.x, "hop interval")


func test_stagger_and_push_come_from_the_combat_rules() -> void:
	for id in SPECIES:
		var d := MonsterDef.build(id, db())
		var canon := MonsterDef.canonical_stagger_s(db().monster(id))
		if canon > 0.0:
			assert_near(d.stagger_s, canon, 1e-9, "%s stagger = the canonical record's STAGGER" % id)
			assert_eq(d.stagger_source, "canonical", "%s stagger source" % id)
		else:
			assert_near(d.stagger_s, CombatFormula.monster_stagger_s(d.stats, db()), 1e-9, "%s stagger = the hit clip" % id)
			assert_eq(d.stagger_source, "hit_animation", "%s stagger source" % id)
		# MeowDB's live pages (2026-10-05) publish STAGGER 0.6 s for all six; the hit1 clips are 600 ms too.
		assert_near(d.stagger_s, 0.6, 1e-9, "%s staggers 0.6 s" % id)
		assert_near(d.knockback_m, WorldScale.h(CombatFormula.monster_knockback_distance_px(db())), 1e-9, "%s push" % id)


## The canonical record's own stagger time wins over the hit clip (combat.json monster_knockback
## stagger_from_canonical_record); without one, or with the switch off, the hit1 clip decides.
func test_a_canonical_stagger_field_wins_over_the_hit_clip() -> void:
	var c := ContentDB.new()
	c.canonical = db().canonical.duplicate(true)
	c.miso = db().miso.duplicate(true)
	c.loaded = true
	var rec: Dictionary = c.canonical["monsters"]["2"]
	for k in ["stagger_s", "stagger_ms", "stagger_duration_s", "stagger_duration_ms", "stagger"]:
		rec.erase(k)
	var by_clip := MonsterDef.build("2", c)
	assert_eq(by_clip.stagger_source, "hit_animation", "no stagger field: the hit clip")
	assert_near(by_clip.stagger_s, float(rec["animations"]["hit1"]["duration_ms"]) / 1000.0, 1e-9, "hit1 length")
	rec["stagger_ms"] = 450
	var by_record := MonsterDef.build("2", c)
	assert_eq(by_record.stagger_source, "canonical", "the record's stagger wins")
	assert_near(by_record.stagger_s, 0.45, 1e-9, "stagger_ms 450")
	assert_near(MonsterBrain.new(by_record).push_speed(), by_record.knockback_m / 0.45, 1e-9, "the push spreads over it")
	c.miso[""]["combat"]["monster_knockback"]["stagger_from_canonical_record"] = false
	var c2 := ContentDB.new()
	c2.canonical = c.canonical
	c2.miso = c.miso
	c2.loaded = true
	assert_eq(MonsterDef.build("2", c2).stagger_source, "hit_animation", "switch off: the clip again")


func test_canonical_stagger_fields() -> void:
	assert_near(MonsterDef.canonical_stagger_s({"stagger_s": 0.6}), 0.6, 1e-9)
	assert_near(MonsterDef.canonical_stagger_s({"stagger_ms": 600}), 0.6, 1e-9)
	assert_near(MonsterDef.canonical_stagger_s({"stagger_duration_ms": 750}), 0.75, 1e-9)
	assert_near(MonsterDef.canonical_stagger_s({"stagger": 0.6}), 0.6, 1e-9)
	assert_near(MonsterDef.canonical_stagger_s({"stagger": {"seconds": 0.6, "raw_value": "0.6 seconds"}}), 0.6, 1e-9)
	assert_near(MonsterDef.canonical_stagger_s({"stagger": {"ms": 600}}), 0.6, 1e-9)
	assert_eq(MonsterDef.canonical_stagger_s({}), 0.0, "none: 0, never a guess")
	assert_eq(MonsterDef.canonical_stagger_s({"stagger": null, "stagger_s": "0.6"}), 0.0, "text is not a number")


func test_peace_monster_touch_rule() -> void:
	var sentinel := MonsterDef.build("1", db())
	assert_true(sentinel.peaceful, "canonical Peace attribute")
	assert_eq(sentinel.touch_rule, MonsterDef.TOUCH_WHEN_PROVOKED)
	assert_false(sentinel.touch_active(false), "safe to walk past")
	assert_true(sentinel.touch_active(true), "provoked: touch hurts")
	var snail := MonsterDef.build("2", db())
	assert_true(snail.touch_active(false), "a Snail always hurts")
	var data := db().miso_entity("monsters", "1")
	assert_eq(data.get("verified"), false, "the Peace rule is unverified")


func test_models_and_capsules() -> void:
	for id in SPECIES:
		var d := MonsterDef.build(id, db())
		# Every species has a proxy since Iteration Three (the Tutorial Jr. Sentinel: Mob_TutorialJrSentinel).
		assert_true(d.has_model() and d.model.begins_with("Mob_"), "%s model %s" % [id, d.model])
		assert_true(d.capsule_radius_m > 0.0 and d.capsule_radius_m <= d.touch_size_m.x * 0.5 + 1e-6, "%s capsule inside the touch zone" % id)
		assert_near(d.capsule_height_m, d.touch_size_m.y, 0.02, "%s capsule height = touch zone height" % id)


func test_every_adaptation_value_has_a_reason() -> void:
	for id in SPECIES + [MonsterDef.SHARED_TABLE]:
		var a := db().miso_entity("monsters", id)
		assert_false(a.is_empty(), "monsters/%s.json loads" % id)
		var reasons: Dictionary = a.get("reasons", {})
		for k in a:
			if k in ["id", "kind", "description", "verified", "reasons"]:
				continue
			assert_true(String(reasons.get(k, "")) != "", "monsters/%s.json %s has no reason" % [id, k])
		for k in reasons:
			assert_true(a.has(k), "monsters/%s.json explains '%s', which it does not set" % [id, k])
		assert_eq(a.get("verified"), false, "monsters/%s.json is unverified" % id)
	# The merged view a species runs with: every value it reads is explained, by the species or the shared table.
	for id in SPECIES:
		var merged := MonsterDef.build(id, db()).adaptation
		for k in merged:
			if k in ["id", "kind", "description", "verified", "reasons"]:
				continue
			assert_true(String((merged["reasons"] as Dictionary).get(k, "")) != "", "monster %s: %s unexplained" % [id, k])


func test_shared_values_reach_every_species_and_a_species_file_overrides_them() -> void:
	var shared := db().miso_entity("monsters", MonsterDef.SHARED_TABLE)
	for k in ["probe_ahead_m", "ledge_tolerance_m", "wall_probe_height_m", "floor_band_m", "pace_reverse_chance",
			"pace_min_run_m", "turn_jitter_deg",
			"provoked_chase_s", "model_fit", "model_max_width_touch_ratio", "hop_max_rise_apex_fraction", "fall_landing_tolerance_m",
			"see_through_radius_m", "see_through_hysteresis_m", "see_through_color", "see_through_fade_s",
			"see_through_min_cover_m"]:
		assert_true(shared.has(k), "_shared.json holds %s" % k)
		for id in SPECIES:
			assert_false(db().miso_entity("monsters", id).has(k), "monsters/%s.json no longer repeats %s" % [id, k])
	for id in SPECIES:
		var d := MonsterDef.build(id, db())
		assert_near(d.probe_ahead_m, float(shared["probe_ahead_m"]), 1e-9, "%s probe" % id)
		assert_near(d.ledge_tolerance_m, float(shared["ledge_tolerance_m"]), 1e-9, "%s ledge tolerance" % id)
		assert_near(d.wall_probe_height_m, float(shared["wall_probe_height_m"]), 1e-9, "%s wall probe" % id)
		assert_near(d.pace_reverse_chance, float(shared["pace_reverse_chance"]), 1e-9, "%s pacing reverse chance" % id)
		assert_near(d.pace_min_run_m, float(shared["pace_min_run_m"]), 1e-9, "%s pacing min run" % id)
		assert_near(d.floor_band_m, float(shared["floor_band_m"]), 1e-9, "%s floor band" % id)
		assert_near(d.turn_jitter_rad, deg_to_rad(float(shared["turn_jitter_deg"])), 1e-9, "%s jitter" % id)
		assert_near(d.provoked_chase_s, float(shared["provoked_chase_s"]), 1e-9, "%s chase" % id)
		assert_eq(d.model_fit, String(shared["model_fit"]), "%s model fit" % id)
		assert_near(d.model_max_width_touch_ratio, float(shared["model_max_width_touch_ratio"]), 1e-9, "%s model width cap" % id)
		assert_near(d.model_max_width_m(), d.touch_size_m.x * d.model_max_width_touch_ratio, 1e-9, "%s widest model (m)" % id)
		assert_near(d.fall_landing_tolerance_m, float(shared["fall_landing_tolerance_m"]), 1e-9, "%s fall tolerance" % id)
		assert_near(d.see_through_radius_m, float(shared["see_through_radius_m"]), 1e-9, "%s see-through radius" % id)
		assert_near(d.see_through_fade_s, float(shared["see_through_fade_s"]), 1e-9, "%s see-through fade" % id)
	var om := MonsterDef.build("9", db())
	assert_near(om.hop_max_rise_apex_fraction, float(shared["hop_max_rise_apex_fraction"]), 1e-9, "OM hop reach")
	# A species file that names a shared key wins, with its own reason; the other species keep the shared value.
	var c := ContentDB.new()
	c.canonical = db().canonical
	c.miso = db().miso.duplicate(true)
	c.loaded = true
	c.miso["monsters"]["2"]["probe_ahead_m"] = 0.8
	c.miso["monsters"]["2"]["reasons"]["probe_ahead_m"] = "test override"
	c.miso["monsters"]["9"]["hop_max_rise_apex_fraction"] = 0.5
	var snail := MonsterDef.build("2", c)
	assert_eq(snail.errors.size(), 0, "; ".join(snail.errors))
	assert_near(snail.probe_ahead_m, 0.8, 1e-9, "the Snail's own probe wins")
	assert_eq(String(snail.adaptation["reasons"]["probe_ahead_m"]), "test override", "with its own reason")
	assert_near(MonsterDef.build("3", c).probe_ahead_m, float(shared["probe_ahead_m"]), 1e-9, "Blue Snail keeps the shared probe")
	assert_near(MonsterDef.build("9", c).hop_max_rise_apex_fraction, 0.5, 1e-9, "OM override")
	assert_eq(float(db().miso_entity("monsters", MonsterDef.SHARED_TABLE)["probe_ahead_m"]), float(shared["probe_ahead_m"]),
		"merging never edits the shared table")


func test_a_missing_shared_table_or_shared_value_is_an_error() -> void:
	var c := ContentDB.new()
	c.canonical = db().canonical
	c.miso = db().miso.duplicate(true)
	c.loaded = true
	(c.miso["monsters"] as Dictionary).erase(MonsterDef.SHARED_TABLE)
	var d := MonsterDef.build("2", c)
	var text := "; ".join(d.errors)
	assert_true(text.contains("_shared"), "the missing table is named: %s" % text)
	assert_true(text.contains("probe_ahead_m"), "and the values it held are missing: %s" % text)
	assert_true(text.contains("model_fit"), "model_fit too (no silent default): %s" % text)
	assert_true(text.contains("model_max_width_touch_ratio"), "and the model width cap: %s" % text)
	assert_true(text.contains("see_through_radius_m") and text.contains("see_through_color"), "and the see-through values: %s" % text)
	assert_true(MonsterDef.build("9", c).errors.size() > d.errors.size(), "a jumper also misses its hop reach")


## Owner decision (2026-10-14, #59/#64): a monster model never spans more than 1.35x its canonical touch zone width;
## the Tutorial Jr. Sentinel's limit is its 21 px touch zone (0.525 m) x 1.35.
func test_the_model_width_cap_is_the_owners_1_35x_touch_width() -> void:
	var d := MonsterDef.build("1", db())
	assert_near(d.model_max_width_touch_ratio, 1.35, 1e-9, "1.35x the touch width")
	assert_near(d.model_max_width_m(), WorldScale.actor(float(d.stats.touch_zone_px.x)) * 1.35, 1e-6, "the Sentinel's widest model")
