extends TestCase
## MovementModel: canonical MeowDB movement numbers converted through WorldScale, plus the adaptation table.


func _model() -> MovementModel:
	return MovementModel.from_db(db())


func _canon() -> Dictionary:
	return db().formula("movement")


func test_walk_speed_is_canonical_px_times_horizontal_scale() -> void:
	var m := _model()
	var ws: Dictionary = _canon()["walk_speed"]
	assert_near(m.walk_speed, WorldScale.h(float(ws["base_px_per_s"])), 1e-6, "walk speed at Speed 100")
	assert_near(m.walk_speed, 3.0, 1e-6, "150 px/s x 0.02 m/px")


func test_walk_formula_matches_meowdb_line_at_base_and_cap() -> void:
	var m := _model()
	var ws: Dictionary = _canon()["walk_speed"]
	assert_near(m.walk_px_per_s(float(_canon()["base_speed"])), float(ws["base_px_per_s"]), 1e-6, "Speed 100")
	assert_near(m.walk_px_per_s(float(_canon()["speed_cap"])), float(ws["cap_px_per_s"]), 1e-6, "Speed cap")
	# MeowDB's formula text: 125 x (Speed + 20) / 100. The model reproduces it between the published points.
	assert_near(m.walk_px_per_s(120.0), 175.0, 1e-6, "Speed 120 on the published line")
	assert_near(m.walk_px_per_s(500.0), float(ws["cap_px_per_s"]), 1e-6, "Speed above the cap does nothing")


func test_climb_speed_follows_speed_plus_offset() -> void:
	var m := _model()
	var cs: Dictionary = _canon()["climb_speed"]
	assert_near(m.climb_px_per_s(100.0), float(cs["base_px_per_s"]), 1e-6, "Climb at Speed 100")
	assert_near(m.climb_px_per_s(130.0), 150.0, 1e-6, "Climb speed = Speed + 20 px/s")
	assert_near(m.climb_speed, WorldScale.v(float(cs["base_px_per_s"])), 1e-6, "vertical px -> m")


func test_jump_apex_is_canonical_table_times_vertical_scale() -> void:
	var m := _model()
	var rows: Array = _canon()["jump_height_px_by_jump"]
	assert_near(m.jump_apex, WorldScale.v(float(rows[0]["height_px"])), 1e-6, "Jump 100 apex")
	for r in rows:
		assert_near(m.jump_height_px(float(r["jump"])), float(r["height_px"]), 1e-6, "table row Jump %s" % r["jump"])
	assert_near(m.jump_height_px(102.5), lerpf(77.0, 85.0, 0.5), 1e-6, "between rows")


func test_jump_apex_at_cap_in_adaptation_table_matches_derivation() -> void:
	var m := _model()
	var tuning: Dictionary = db().miso_table("movement")
	assert_near(float(tuning["jump_apex_m_at_cap"]), m.jump_apex_at_cap(), 1e-4, "movement.json jump_apex_m_at_cap must equal canonical table[cap] x WorldScale.v")


func test_gravity_is_meowdb_knockback_model() -> void:
	var m := _model()
	var kb: Dictionary = _canon()["knockback_airtime"]
	assert_near(m.gravity, WorldScale.v(float(kb["gravity_px_per_s2"])), 1e-6, "gravity")
	assert_near(m.knockback_up_speed, WorldScale.v(float(kb["upward_speed_px_per_s"])), 1e-6, "knockback launch")
	# 77 px apex under 2000 px/s^2 needs a 555 px/s launch; the m/s value is that times WorldScale.v.
	assert_near(m.jump_velocity, WorldScale.v(sqrt(2.0 * 2000.0 * 77.0)), 1e-4, "jump launch speed")
	assert_near(m.jump_airtime(), 2.0 * sqrt(2.0 * 2000.0 * 77.0) / 2000.0, 1e-4, "same-height airtime")


func test_stats_change_speed_and_jump_and_respect_caps() -> void:
	var m := _model()
	m.set_stats(140.0, 120.0)
	assert_near(m.walk_speed, WorldScale.h(200.0), 1e-6, "walk at cap")
	assert_near(m.jump_apex, WorldScale.v(111.0), 1e-6, "apex at Jump cap")
	m.set_stats(999.0, 999.0)
	assert_near(m.walk_speed, WorldScale.h(200.0), 1e-6, "Speed clamped")
	assert_near(m.jump_apex, WorldScale.v(111.0), 1e-6, "Jump clamped")


func test_adaptation_table_has_reasons_and_is_marked_unverified() -> void:
	var tuning: Dictionary = db().miso_table("movement")
	assert_eq(tuning.get("verified"), false, "movement.json verified flag")
	var reasons: Dictionary = tuning.get("reasons", {})
	for key in tuning:
		if key in ["id", "kind", "verified", "description", "reasons"]:
			continue
		var base := String(key)
		assert_true(reasons.has(base), "movement.json key '%s' has no reason" % base)
	var cam: Dictionary = db().miso_table("camera")
	var cam_reasons: Dictionary = cam.get("reasons", {})
	for key in cam:
		if key in ["id", "kind", "verified", "description", "reasons"]:
			continue
		assert_true(cam_reasons.has(String(key)), "camera.json key '%s' has no reason" % key)
