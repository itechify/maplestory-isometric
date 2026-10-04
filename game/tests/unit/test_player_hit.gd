extends TestCase
## The wave-2 hit-reaction API (knockback, hit-stun, invulnerability, death) and the world runtime hooks
## (teleport, SafeGround, kill_y, input enable, the camera follow anchor).

var w: PlayerTestWorld


func before_each() -> void:
	w = PlayerTestWorld.create(db())
	w.add_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))


func after_each() -> void:
	w.free_all()


func _canon_kb() -> Dictionary:
	return db().formula("movement")["knockback_airtime"]


func test_knockback_follows_meowdb_airtime_model() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	p.apply_knockback(Vector3(1, 0, 0))
	assert_true(p.in_hitstun, "hit-stun starts")
	assert_true(p.is_invulnerable(), "invulnerable after a hit")
	var kb := _canon_kb()
	var peak := 0.0
	var ticks := 0
	for i in 120:
		w.player.step(PlayerTestWorld.TICK)
		peak = maxf(peak, p.global_position.y)
		ticks += 1
		if p.is_grounded():
			break
	assert_near(peak, WorldScale.v(float(kb["rise_px"])), 0.01, "rise = 18.225 px x WorldScale.v")
	assert_near(ticks / 60.0, float(kb["same_height_airtime_s"]), 0.03, "same-height airtime 0.27 s")
	var model := MovementModel.from_db(db())
	assert_near(p.global_position.x, model.knockback_speed * float(kb["same_height_airtime_s"]), 0.06, "horizontal push (adaptation)")
	assert_false(p.in_hitstun, "hit-stun ends on landing")
	assert_near(p.move_velocity.length(), 0.0, 1e-6, "the push stops on landing")


func test_hitstun_blocks_input() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	p.apply_knockback(Vector3(1, 0, 0))
	w.bot.world_dir = Vector3(-1, 0, 0)
	w.bot.press(&"jump")
	w.player.step(PlayerTestWorld.TICK)
	assert_true(p.move_velocity.x > 0.0, "input ignored during hit-stun")
	assert_true(p.vertical_speed < MovementModel.from_db(db()).jump_velocity * 0.6, "no jump during hit-stun")


func test_knockback_direction_conventions() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0), Vector3(0, 0, 1))
	p.apply_knockback(Vector3.ZERO)
	assert_true(p.move_velocity.z < 0.0, "no direction: pushed backwards (against facing)")
	w.run(60)
	p.apply_knockback_from_point(p.global_position + Vector3(-2, 0, 0))
	assert_true(p.move_velocity.x > 0.0, "pushed away from the source point")


func test_invulnerability_timer_and_default() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	p.apply_knockback(Vector3(1, 0, 0), 1.0, 0.5)
	assert_near(p.invulnerable_time_left(), 0.5, 1e-6, "explicit duration")
	w.run(31)
	assert_false(p.is_invulnerable(), "expired")
	p.set_invulnerable(1.0)
	assert_true(p.is_invulnerable(), "set_invulnerable hook")
	# The duration belongs to the combat data: combat.json's override when set, else MeowDB's canonical value.
	var expected := float(db().formula("accuracy")["after_hit"]["post_hit_invincibility_s"])
	var combat: Variant = db().miso_table("combat")
	if combat is Dictionary and (combat as Dictionary).get("post_hit_invincibility") is Dictionary:
		var override: Variant = combat["post_hit_invincibility"].get("override_s")
		if override != null:
			expected = float(override)
	assert_near(p.default_invulnerability_seconds(), expected, 1e-6, "post-hit invincibility from the combat data")
	p.apply_knockback(Vector3(1, 0, 0))
	assert_near(p.invulnerable_time_left(), expected, 1e-6, "a knockback without a duration uses it")
	assert_near(MovementModel.post_hit_invincibility({"after_hit": {"post_hit_invincibility_s": 1.5}}, {"post_hit_invincibility": {"override_s": 0.8}}), 0.8, 1e-6, "override wins")
	assert_near(MovementModel.post_hit_invincibility({"after_hit": {"post_hit_invincibility_s": 1.5}}, {"post_hit_invincibility": {"override_s": null}}), 1.5, 1e-6, "null override -> canonical")


func test_safe_ground_filter_accepts_one_or_two_arguments() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	# FallRecovery installs a one-argument region check: func(pos) -> bool.
	p.safe_ground_filter = func(pos: Vector3) -> bool: return pos.x < 1.0
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(60)
	assert_true(p.safe_ground.position.x < 1.0, "one-argument filter honoured")
	var seen: Array = []
	p.safe_ground_filter = func(_pos: Vector3, collider: Object) -> bool:
		seen.append(collider)
		return true
	w.run(5)
	assert_true(seen.size() > 0 and seen[0] != null, "two-argument filter gets the floor collider")


func test_knockback_knocks_off_a_ladder() -> void:
	var c := ClimbableDef.from_sidecar({"name": "L", "kind": "ladder", "bottom": [0.5, 0, 0], "top": [0.5, 4, 0], "top_exit": [1.0, 4, 0], "foot_ground": [0.5, 0, 0], "facing_xz": [0.5, 0]})
	var p := w.spawn_player(Vector3(0, 0, 0))
	p.grab_climbable(c)
	assert_true(p.is_climbing(), "on the ladder")
	p.apply_knockback(Vector3(-1, 0, 0))
	assert_false(p.is_climbing(), "knocked off")
	assert_true(p.in_hitstun, "in hit-stun")


func test_death_disables_input_and_revive_restores() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	var died := [0]
	p.died.connect(func() -> void: died[0] += 1)
	p.die()
	p.die()
	assert_eq(died[0], 1, "died once")
	assert_true(p.is_dead(), "dead")
	w.bot.world_dir = Vector3(1, 0, 0)
	w.bot.press(&"jump")
	w.run(30)
	assert_near(p.global_position.x, 0.0, 1e-4, "no movement while dead")
	assert_true(p.is_grounded(), "no jump while dead")
	p.apply_knockback(Vector3(1, 0, 0))
	assert_false(p.in_hitstun, "no knockback on a dead body")
	p.revive()
	assert_false(p.is_dead(), "alive again")
	w.run(30)
	assert_true(p.global_position.x > 0.5, "moves after revive")


func test_teleport_resets_motion_and_safe_ground() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(10)
	w.bot.press(&"jump")
	w.player.step(PlayerTestWorld.TICK)
	assert_false(p.is_grounded(), "mid-jump")
	var xf := Transform3D(Basis(Vector3(0, 1, 0), PI * 0.5), Vector3(10, 0.3, 5))
	p.teleport(xf)
	assert_true(p.is_grounded(), "settled on arrival")
	assert_near(p.global_position.y, 0.0, 0.01, "grounded at the floor below the arrival point")
	assert_near(p.move_velocity.length(), 0.0, 1e-6, "velocity zeroed")
	assert_near(p.vertical_speed, 0.0, 1e-6, "vertical speed zeroed")
	assert_true(p.safe_ground.valid, "safe ground reset")
	assert_near(p.safe_ground.position.distance_to(Vector3(10, 0, 5)), 0.0, 0.01, "safe ground at the arrival")
	assert_near(p.facing.dot(xf.basis.z.normalized()), 1.0, 1e-4, "facing from basis +Z (MODEL_FRONT)")
	w.bot.world_dir = Vector3.ZERO
	w.run(5)
	assert_near(p.global_position.distance_to(Vector3(10, 0, 5)), 0.0, 0.01, "no buffered jump or momentum after teleport")


func test_safe_ground_records_only_on_safe_floor() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(30)
	var at := p.safe_ground.position
	assert_near(at.x, p.global_position.x, 0.001, "recorded while walking")
	w.bot.press(&"jump")
	w.player.step(PlayerTestWorld.TICK)
	w.run(10)
	assert_true(p.safe_ground.position.x < p.global_position.x - 0.2, "not recorded while airborne")
	w.run_until(func() -> bool: return p.is_grounded(), 120)
	p.safe_ground_filter = func(pos: Vector3, _collider: Object) -> bool: return pos.x < 5.0
	w.run(120)
	assert_true(p.safe_ground.position.x < 5.0, "filter rejects positions (x=%.2f)" % p.safe_ground.position.x)
	assert_true(p.global_position.x > 5.0, "kept walking")
	var xf := p.safe_ground.transform()
	assert_near(xf.origin.distance_to(p.safe_ground.position), 0.0, 1e-6, "recovery transform")


func test_kill_y_reports_fall_once() -> void:
	w.free_all()
	w = PlayerTestWorld.create(db())
	w.add_box(Vector3(0, -0.5, 0), Vector3(4, 1, 4))
	var p := w.spawn_player(Vector3(0, 0, 0))
	p.kill_y = -6.0
	var falls: Array = []
	p.fell_out_of_world.connect(func(at: Vector3) -> void: falls.append(at))
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(150)
	assert_eq(falls.size(), 1, "reported once")
	assert_true(p.safe_ground.valid and p.safe_ground.position.y > -0.01, "safe ground stays on the platform")
	p.teleport(p.safe_ground.transform())
	assert_true(p.is_grounded(), "recovered to safe ground")


func test_input_disable_and_follow_anchor() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	p.set_input_enabled(false)
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(20)
	assert_near(p.global_position.x, 0.0, 1e-4, "no movement with input disabled")
	p.set_input_enabled(true)
	w.bot.world_dir = Vector3.ZERO
	w.bot.press(&"jump")
	var max_anchor := -INF
	for i in 40:
		w.player.step(PlayerTestWorld.TICK)
		max_anchor = maxf(max_anchor, p.follow_anchor().y)
	assert_near(max_anchor, 0.0, 1e-4, "the camera anchor ignores the jump height")
