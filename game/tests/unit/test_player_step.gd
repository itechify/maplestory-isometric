extends TestCase
## Phase 4 traversal on synthetic collision: step-up (0.45 m), walls, stairs, the 38 degree slope limit,
## small clutter and trimesh seams (the exported ground is a ConcavePolygonShape3D).

var w: PlayerTestWorld


func before_each() -> void:
	w = PlayerTestWorld.create(db())


func after_each() -> void:
	w.free_all()


func _floor() -> void:
	w.add_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))


## Walks along +X for `ticks` and returns the player.
func _walk_x(start: Vector3, ticks: int) -> PlayerController:
	var p := w.spawn_player(start)
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(ticks)
	return p


func test_steps_up_a_0_4_m_step() -> void:
	_floor()
	w.add_box(Vector3(4, 0.2, 0), Vector3(4, 0.4, 6))  # top at 0.4, front face at x = 2
	var p := _walk_x(Vector3(0, 0, 0), 90)
	assert_near(p.global_position.y, 0.4, 0.02, "standing on the step")
	assert_true(p.global_position.x > 3.0, "kept walking across it (x=%.2f)" % p.global_position.x)
	assert_true(p.is_grounded(), "grounded on the step")


func test_does_not_step_up_a_0_6_m_wall() -> void:
	_floor()
	w.add_box(Vector3(4, 0.3, 0), Vector3(4, 0.6, 6))  # top at 0.6, front face at x = 2
	var p := _walk_x(Vector3(0, 0, 0), 90)
	assert_near(p.global_position.y, 0.0, 0.02, "still on the floor")
	assert_between(p.global_position.x, 1.5, 2.0, "stopped at the wall face")
	# A jump clears it (apex 0.90 m at Jump 100).
	w.bot.press(&"jump")
	w.run(60)
	assert_near(p.global_position.y, 0.6, 0.02, "jumped onto the 0.6 m ledge")


func test_walks_up_and_down_stairs() -> void:
	_floor()
	# 6 risers of 0.28 m on 0.35 m treads up to a landing.
	for i in 6:
		var top := (i + 1) * 0.28
		w.add_box(Vector3(2.0 + i * 0.35 + 0.175, top * 0.5, 0), Vector3(0.35, top, 4))
	w.add_box(Vector3(7.1, 0.84, 0), Vector3(6.0, 1.68, 4))  # landing x 4.1..10.1, top 1.68
	var p := w.spawn_player(Vector3(0, 0, 0))
	w.bot.world_dir = Vector3(1, 0, 0)
	var max_air := 0
	var air := 0
	for i in 150:
		w.player.step(PlayerTestWorld.TICK)
		air = air + 1 if not p.is_grounded() else 0
		max_air = maxi(max_air, air)
	assert_true(p.global_position.x > 7.0, "crossed the stairs and the landing (x=%.2f)" % p.global_position.x)
	assert_true(max_air <= 2, "never airborne on the stairs (%d ticks)" % max_air)


func test_walks_down_small_drops_without_falling() -> void:
	_floor()
	w.add_box(Vector3(0, 0.2, 0), Vector3(6, 0.4, 6))  # a 0.4 m high platform, edge at x = 3
	var p := w.spawn_player(Vector3(0, 0.4, 0))
	w.bot.world_dir = Vector3(1, 0, 0)
	var air := 0
	for i in 90:
		w.player.step(PlayerTestWorld.TICK)
		if not p.is_grounded():
			air += 1
	assert_near(p.global_position.y, 0.0, 0.02, "down on the floor")
	assert_true(air <= 1, "stepped down instead of falling (%d airborne ticks)" % air)


func test_slope_limit() -> void:
	_floor()
	w.add_ramp(2.0, 0.0, -6.0, 30.0, 6.0, 4.0)   # walkable lane at z = -6
	w.add_ramp(2.0, 0.0, 6.0, 45.0, 6.0, 4.0)    # too steep lane at z = +6
	var p := w.spawn_player(Vector3(0, 0, -6))
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(120)
	assert_true(p.global_position.y > 1.5, "walked up the 30 degree ramp (y=%.2f)" % p.global_position.y)
	assert_true(p.is_grounded(), "grounded on the 30 degree ramp")
	w.free_all()
	w = PlayerTestWorld.create(db())
	_floor()
	w.add_ramp(2.0, 0.0, 6.0, 45.0, 6.0, 4.0)
	p = w.spawn_player(Vector3(0, 0, 6))
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(120)
	assert_true(p.global_position.y < 0.5, "cannot walk up the 45 degree ramp (y=%.2f)" % p.global_position.y)


func test_slope_just_under_and_over_38_degrees() -> void:
	_floor()
	w.add_ramp(2.0, 0.0, 0.0, 36.0, 6.0, 4.0)
	var p := _walk_x(Vector3(0, 0, 0), 150)
	assert_true(p.global_position.y > 2.0, "36 degrees is walkable (y=%.2f)" % p.global_position.y)
	w.free_all()
	w = PlayerTestWorld.create(db())
	_floor()
	w.add_ramp(2.0, 0.0, 0.0, 41.0, 6.0, 4.0)
	p = _walk_x(Vector3(0, 0, 0), 150)
	assert_true(p.global_position.y < 0.6, "41 degrees is not (y=%.2f)" % p.global_position.y)


func test_no_creep_standing_on_a_slope() -> void:
	_floor()
	w.add_ramp(-4.0, 0.0, 0.0, 30.0, 8.0, 4.0)
	var p := w.spawn_player(Vector3(0, 2.4, 0))
	w.run(10)
	var at := p.global_position
	w.run(120)
	assert_true(p.is_grounded(), "grounded on the slope")
	assert_true(p.global_position.distance_to(at) < 0.01, "did not slide (moved %.3f m)" % p.global_position.distance_to(at))


func test_walking_down_a_slope_stays_grounded_at_full_speed() -> void:
	_floor()
	w.add_ramp(-8.0, 0.0, 0.0, -30.0, 6.0, 4.0)  # descends along +X from y=0 at x=-8
	w.add_box(Vector3(-12, -0.5, 0), Vector3(8, 1, 4))
	var p := w.spawn_player(Vector3(-10, 0, 0))
	w.bot.world_dir = Vector3(1, 0, 0)
	var air := 0
	for i in 200:
		w.player.step(PlayerTestWorld.TICK)
		if not p.is_grounded():
			air += 1
	assert_true(p.global_position.x > -2.5, "walked down (x=%.2f)" % p.global_position.x)
	assert_true(air <= 1, "stayed on the ground (%d airborne ticks)" % air)


func test_passes_small_clutter_without_snagging() -> void:
	_floor()
	# A 0.12 m lip, a 0.25 m rock and a 0.38 m root across the path: all walkable without jumping.
	w.add_box(Vector3(3, 0.06, 0), Vector3(0.3, 0.12, 4))
	w.add_box(Vector3(6, 0.125, 0), Vector3(0.4, 0.25, 0.5), Vector3(0, 30, 0))
	w.add_box(Vector3(9, 0.19, 0), Vector3(0.2, 0.38, 4))
	var p := w.spawn_player(Vector3(0, 0, 0))
	w.bot.world_dir = Vector3(1, 0, 0)
	var ticks := w.run_until(func() -> bool: return p.global_position.x > 12.0, 400)
	assert_true(ticks > 0, "got past the clutter")
	var walk := MovementModel.from_db(db()).walk_speed
	assert_true(ticks <= int(ceil(12.0 / walk * 60.0 * 1.15)), "no snagging: %d ticks for 12 m (ideal %d)" % [ticks, int(12.0 / walk * 60.0)])


func test_trimesh_seams_do_not_snag() -> void:
	w.add_trimesh_floor(Vector3(0, 0, 0), 20.0, 16)
	var p := w.spawn_player(Vector3(-15, 0, -15))
	w.bot.world_dir = Vector3(1, 0, 1)
	var x0 := p.global_position.x
	w.run(240)
	var dist := Vector2(p.global_position.x - x0, 0.0).length() * sqrt(2.0)
	var walk := MovementModel.from_db(db()).walk_speed
	assert_near(dist, walk * 4.0, walk * 4.0 * 0.03, "diagonal across 2.5 m triangles at full speed")
	assert_near(p.global_position.y, 0.0, 0.02, "on the trimesh")


func test_slides_along_walls() -> void:
	_floor()
	w.add_box(Vector3(0, 1.5, 2.0), Vector3(30, 3, 0.4))  # wall face at z = 1.8
	var p := w.spawn_player(Vector3(0, 0, 0))
	w.bot.world_dir = Vector3(1, 0, 1).normalized()
	w.run(120)
	assert_true(p.global_position.z < 1.8 - 0.25, "never inside the wall")
	assert_true(p.global_position.x > 4.0, "slid along the wall (x=%.2f)" % p.global_position.x)


func test_step_up_boundary_is_step_up_m() -> void:
	var step := MovementModel.from_db(db()).step_up
	_floor()
	w.add_box(Vector3(4, step * 0.5, 0), Vector3(4, step, 6))  # exactly step_up (0.45 m): walked onto
	var p := _walk_x(Vector3(0, 0, 0), 90)
	assert_near(p.global_position.y, step, 0.02, "a riser of exactly step_up is mounted")
	w.free_all()
	w = PlayerTestWorld.create(db())
	_floor()
	w.add_box(Vector3(4, (step + 0.05) * 0.5, 0), Vector3(4, step + 0.05, 6))  # 5 cm taller: a wall
	p = _walk_x(Vector3(0, 0, 0), 90)
	assert_near(p.global_position.y, 0.0, 0.02, "a riser above step_up is not")
	assert_true(p.global_position.x < 2.0, "stopped at its face (x=%.2f)" % p.global_position.x)


## Drops the player beside a 1.2 m ledge with its centre `outside` meters out from the face; returns the landings
## and the highest height at which it was ever grounded.
func _drop_beside_ledge(outside: float) -> Dictionary:
	_floor()
	w.add_box(Vector3(4, 0.6, 0), Vector3(4, 1.2, 6))  # top 1.2, face at x = 2
	var p := w.spawn_player(Vector3(2.0 - outside, 2.0, 0))
	var lands := [0]
	p.landed.connect(func(_s: float) -> void: lands[0] += 1)
	var grounded_max := -INF
	for i in 120:
		w.player.step(PlayerTestWorld.TICK)
		if p.is_grounded():
			grounded_max = maxf(grounded_max, p.global_position.y)
	return {"lands": lands[0], "grounded_max": grounded_max, "y": p.global_position.y}


func test_feet_over_the_ledge_land_on_it() -> void:
	var r := _drop_beside_ledge(0.12)  # the feet disc (0.15 m) reaches over the edge
	assert_eq(r["lands"], 1, "one landing")
	assert_near(float(r["y"]), 1.2, 0.02, "stands on the ledge")


func test_capsule_touching_a_ledge_edge_is_not_a_landing() -> void:
	# Regression: the capsule's rounded bottom touching the edge (walkable contact normal) while no feet ray is over
	# the ledge used to count as a landing, lifting the body ~0.5 m onto the ledge height for one tick.
	for outside in [0.16, 0.18, 0.25]:
		w.free_all()
		w = PlayerTestWorld.create(db())
		var r := _drop_beside_ledge(outside)
		assert_eq(r["lands"], 1, "%.2f m outside: lands once, on the floor below" % outside)
		assert_true(float(r["grounded_max"]) < 0.05, "%.2f m outside: never grounded at the ledge height (max %.2f)" % [outside, r["grounded_max"]])
		assert_near(float(r["y"]), 0.0, 0.02, "%.2f m outside: slid off the edge to the floor" % outside)


func test_wedged_between_steep_faces_is_steady_ground() -> void:
	# A V crevice of two 45 degree faces (too steep to stand on): the capsule rests in it. The player must count as
	# grounded (so it can jump out) without flickering between ground and air every few ticks.
	w.add_ramp(-3.0, 3.0, 0.0, -45.0, 3.0, 4.0)
	w.add_ramp(0.0, 0.0, 0.0, 45.0, 3.0, 4.0)
	var p := w.spawn_player(Vector3(0.0, 2.0, 0))
	var spawn_safe := p.safe_ground.position
	var lands := [0]
	p.landed.connect(func(_s: float) -> void: lands[0] += 1)
	var air_after_landing := 0
	for i in 180:
		w.player.step(PlayerTestWorld.TICK)
		if lands[0] > 0 and not p.is_grounded():
			air_after_landing += 1
	assert_eq(lands[0], 1, "one landing, no landing spam")
	assert_eq(air_after_landing, 0, "no ground/air flicker once wedged")
	assert_true(p.is_grounded(), "wedged counts as grounded")
	assert_near(p.safe_ground.position.distance_to(spawn_safe), 0.0, 1e-4, "a wedge is never recorded as SafeGround")
	var y := p.global_position.y
	w.bot.press(&"jump")
	w.player.step(PlayerTestWorld.TICK)
	w.run(10)
	assert_true(p.global_position.y > y + 0.3, "can jump out of the crevice")
