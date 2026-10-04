extends TestCase
## PlayerController on flat ground: walk speed, 8-direction input relative to the isometric camera, stopping,
## facing, jump apex and airtime, air control, coyote time and the jump buffer.

var w: PlayerTestWorld


func before_each() -> void:
	w = PlayerTestWorld.create(db())
	w.add_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))


func after_each() -> void:
	w.free_all()


func _expected_walk() -> float:
	return WorldScale.h(float(db().formula("movement")["walk_speed"]["base_px_per_s"]))


func test_spawn_settles_on_floor() -> void:
	var p := w.spawn_player(Vector3(0, 0.3, 0))
	assert_true(p.is_grounded(), "grounded right after teleport")
	assert_near(p.global_position.y, 0.0, 0.01, "feet on the floor")
	w.run(30)
	assert_true(p.is_grounded(), "still grounded after idling")
	assert_near(p.global_position.y, 0.0, 0.01, "no sinking or creeping")


func test_walk_speed_per_second_matches_canonical_times_scale() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(30)  # accelerate (full speed within 3 ticks), then measure a full second
	var x0 := p.global_position.x
	w.run(60)
	var per_second := p.global_position.x - x0
	assert_near(per_second, _expected_walk(), 0.01, "meters walked in one second")
	assert_near(p.actual_velocity.length(), _expected_walk(), 0.01, "measured velocity")
	assert_near(p.global_position.y, 0.0, 0.01, "stayed on the floor")


func test_reaches_full_speed_fast_and_stops_fast() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	w.bot.world_dir = Vector3(0, 0, 1)
	w.run(4)
	assert_near(p.actual_velocity.length(), _expected_walk(), 0.01, "full speed after 4 ticks")
	w.bot.world_dir = Vector3.ZERO
	var z := p.global_position.z
	w.run(3)
	assert_near(p.actual_velocity.length(), 0.0, 0.001, "stopped after 3 ticks")
	assert_between(p.global_position.z - z, 0.0, 0.1, "stopping distance (no slide)")


func test_screen_relative_input_maps_w_to_view_forward_and_diagonals_are_normalized() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	w.bot.move = Vector2(0, 1)  # W
	w.run(20)
	var dir := p.actual_velocity.normalized()
	assert_near(dir.dot(p.view_forward), 1.0, 0.001, "W walks along the camera's ground-forward axis")
	w.bot.move = Vector2(1, 1)  # W + D
	w.run(20)
	assert_near(p.actual_velocity.length(), _expected_walk(), 0.01, "diagonal speed equals straight speed")
	var diag := (p.view_forward + p.view_right).normalized()
	assert_near(p.actual_velocity.normalized().dot(diag), 1.0, 0.001, "diagonal direction")
	assert_near(p.facing.dot(diag), 1.0, 0.001, "facing follows movement")


func test_default_view_axes_are_iteration_one_isometric() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	# Sidecar cameras.gameplay.forward is (0.5417, -0.6428, -0.5417): W walks toward Godot +X -Z.
	assert_near(p.view_forward.x, 0.7071, 0.001, "forward x")
	assert_near(p.view_forward.z, -0.7071, 0.001, "forward z")
	assert_near(p.view_right.dot(p.view_forward), 0.0, 0.0001, "axes orthogonal")


func test_jump_apex_height_matches_canonical() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	var expected := WorldScale.v(77.0)
	var model := MovementModel.from_db(db())
	assert_near(model.jump_apex, expected, 1e-6, "model apex")
	w.bot.press(&"jump")
	var peak := 0.0
	var air_ticks := 0
	for i in 60:
		w.player.step(PlayerTestWorld.TICK)
		peak = maxf(peak, p.global_position.y)
		if not p.is_grounded():
			air_ticks += 1
		elif i > 2:
			break
	assert_near(peak, expected, 0.01, "apex reached (m)")
	assert_true(p.is_grounded(), "landed again")
	assert_near(air_ticks / 60.0, model.jump_airtime(), 0.04, "airtime")


func test_jump_apex_scales_with_jump_stat() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	p.set_stats(100.0, 120.0)
	w.bot.press(&"jump")
	var peak := 0.0
	for i in 70:
		w.player.step(PlayerTestWorld.TICK)
		peak = maxf(peak, p.global_position.y)
	assert_near(peak, WorldScale.v(111.0), 0.01, "apex at the Jump cap")


func test_running_jump_distance_and_air_momentum() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(10)
	var x0 := p.global_position.x
	w.bot.press(&"jump")
	w.player.step(PlayerTestWorld.TICK)
	w.bot.world_dir = Vector3.ZERO  # release: momentum is kept in the air (classic)
	var ticks := w.run_until(func() -> bool: return p.is_grounded(), 120)
	assert_true(ticks > 0, "landed")
	var model := MovementModel.from_db(db())
	assert_near(p.global_position.x - x0, model.walk_speed * model.jump_airtime(), 0.12, "jump length at walk speed")


func test_air_control_is_limited() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(10)
	w.bot.press(&"jump")
	w.player.step(PlayerTestWorld.TICK)
	w.bot.world_dir = Vector3(-1, 0, 0)  # try to reverse mid-air
	w.run_until(func() -> bool: return p.is_grounded(), 120)
	assert_true(p.move_velocity.x > -0.5 * _expected_walk(), "cannot turn a running jump around (vx=%.2f)" % p.move_velocity.x)
	assert_true(p.move_velocity.x < 0.5 * _expected_walk(), "but steering does slow it (vx=%.2f)" % p.move_velocity.x)
	# A standing jump can still drift a little.
	var q0 := p.global_position
	w.bot.world_dir = Vector3.ZERO
	w.run(10)
	q0 = p.global_position
	w.bot.press(&"jump")
	w.player.step(PlayerTestWorld.TICK)
	w.bot.world_dir = Vector3(0, 0, 1)
	w.run_until(func() -> bool: return p.is_grounded(), 120)
	assert_between(p.global_position.z - q0.z, 0.3, 1.2, "standing-jump drift")


func test_coyote_time_and_jump_buffer() -> void:
	# A ledge: floor top at y=0 ends at x=2; lower floor 3 m below.
	w.free_all()
	w = PlayerTestWorld.create(db())
	w.add_box(Vector3(-10, -0.5, 0), Vector3(24, 1, 10))
	w.add_box(Vector3(0, -3.5, 0), Vector3(80, 1, 80))
	var p := w.spawn_player(Vector3(0, 0, 0))
	w.bot.world_dir = Vector3(1, 0, 0)
	var left := w.run_until(func() -> bool: return not p.is_grounded(), 120)
	assert_true(left > 0, "walked off the ledge")
	w.player.step(PlayerTestWorld.TICK)
	w.bot.press(&"jump")  # 2 ticks after leaving the edge: within coyote time
	w.player.step(PlayerTestWorld.TICK)
	assert_true(p.vertical_speed > 0.0, "coyote jump fired")
	# Buffer: press jump a few ticks before landing on the lower floor.
	w.bot.world_dir = Vector3.ZERO
	var near_ground := w.run_until(func() -> bool: return p.vertical_speed < 0.0 and p.global_position.y < -2.6, 240)
	assert_true(near_ground > 0, "falling toward the lower floor")
	w.bot.press(&"jump")
	var jumped := false
	for i in 30:
		w.player.step(PlayerTestWorld.TICK)
		if p.vertical_speed > 0.0:
			jumped = true
			break
	assert_true(jumped, "buffered jump fired on landing")


func test_hold_jump_keeps_hopping() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	var jumps := [0]
	p.jumped.connect(func() -> void: jumps[0] += 1)
	w.bot.hold(&"jump")
	w.run(150)
	assert_true(jumps[0] >= 3, "held jump re-jumps on landing (%d jumps)" % jumps[0])


## A ledge (floor top y = 0 ending at x = 2) over a lower floor 3 m below; returns the player walking off it.
func _ledge_world() -> PlayerController:
	w.free_all()
	w = PlayerTestWorld.create(db())
	w.add_box(Vector3(-10, -0.5, 0), Vector3(24, 1, 10))
	w.add_box(Vector3(0, -3.5, 0), Vector3(80, 1, 80))
	return w.spawn_player(Vector3(0, 0, 0))


func test_coyote_time_expires() -> void:
	var p := _ledge_world()
	var model := MovementModel.from_db(db())
	w.bot.world_dir = Vector3(1, 0, 0)
	assert_true(w.run_until(func() -> bool: return not p.is_grounded(), 120) > 0, "walked off the ledge")
	# Wait past the coyote window, then press jump: it must not fire in mid-air.
	w.run(int(ceil(model.coyote_time * 60.0)) + 2)
	w.bot.press(&"jump")
	w.player.step(PlayerTestWorld.TICK)
	assert_true(p.vertical_speed <= 0.0, "no jump after coyote time (vy=%.2f)" % p.vertical_speed)


func test_jump_buffer_expires() -> void:
	var p := _ledge_world()
	var model := MovementModel.from_db(db())
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run_until(func() -> bool: return not p.is_grounded(), 120)
	w.bot.world_dir = Vector3.ZERO
	# Past the coyote window, press jump about 0.5 s before landing: far earlier than the jump buffer allows.
	w.run(int(ceil(model.coyote_time * 60.0)) + 2)
	w.bot.press(&"jump")
	var jumps := [0]
	p.jumped.connect(func() -> void: jumps[0] += 1)
	var landed_at := w.run_until(func() -> bool: return p.is_grounded(), 240)
	assert_true(landed_at > int(ceil(model.jump_buffer * 60.0)) + 2, "the press came well before the buffer window (%d ticks)" % landed_at)
	w.run(5)
	assert_eq(jumps[0], 0, "a press older than the jump buffer does not fire on landing")
	assert_true(p.is_grounded(), "stays on the ground")


func test_landed_reports_impact_speed_and_falls_are_capped() -> void:
	var p := _ledge_world()
	var model := MovementModel.from_db(db())
	var speeds: Array = []
	p.landed.connect(func(s: float) -> void: speeds.append(s))
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(150)
	assert_eq(speeds.size(), 1, "one landing")
	assert_near(float(speeds[0]), sqrt(2.0 * model.gravity * 3.0), 0.2, "impact speed of a 3 m drop = sqrt(2 g h)")
	# A tall drop reaches the terminal fall speed (movement.json max_fall_speed_mps), never more.
	w.free_all()
	w = PlayerTestWorld.create(db())
	w.add_box(Vector3(0, -20.5, 0), Vector3(40, 1, 40))
	p = w.spawn_player(Vector3(0, 0, 0))
	speeds.clear()
	p.landed.connect(func(s: float) -> void: speeds.append(s))
	var fastest := 0.0
	for i in 240:
		w.player.step(PlayerTestWorld.TICK)
		fastest = maxf(fastest, -p.vertical_speed)
	assert_near(fastest, model.max_fall_speed, 1e-4, "fall speed capped")
	assert_eq(speeds.size(), 1, "landed once at the bottom")
	assert_near(float(speeds[0]), model.max_fall_speed, 1e-3, "impact at the cap")


func test_speed_stat_comes_from_stat_calculator() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	var canon: Dictionary = db().formula("movement")
	var bonus := int(canon["nimble_feet_speed_bonus"])
	var c := CharacterState.new()
	c.effects = [{"id": "nimble_feet_test", "bonuses": {"speed": bonus}}]
	p.refresh_stats(c, db())
	var expected_speed := float(StatCalculator.snapshot(c, db())["speed"])
	assert_near(p.model.speed_stat, expected_speed, 1e-6, "total Speed from StatCalculator")
	assert_true(expected_speed > float(canon["base_speed"]), "the effect raised Speed")
	var expected := WorldScale.h(p.model.walk_px_per_s(expected_speed))
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(30)
	var x0 := p.global_position.x
	w.run(60)
	assert_near(p.global_position.x - x0, expected, 0.01, "walks at the boosted canonical speed")
	assert_true(expected > _expected_walk(), "faster than at Speed 100")
