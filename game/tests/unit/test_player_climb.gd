extends TestCase
## Ladders, ropes and vines from sidecar-shaped climbables: grab with Up / interact, climb at the canonical climb
## speed, exit at the top onto top_exit, grab from the top with Down, drop off at the bottom, jump off sideways,
## descend-only ropes and ropes without foot ground.

var w: PlayerTestWorld


func before_each() -> void:
	w = PlayerTestWorld.create(db())
	w.add_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))     # floor, top y = 0
	w.add_box(Vector3(5, 1.5, 0), Vector3(6, 3, 12))       # cliff x 2..8, top y = 3


func after_each() -> void:
	w.free_all()


## A ladder against the cliff face (x = 2), shaped like an exported sidecar entry.
func _ladder(extra: Dictionary = {}) -> ClimbableDef:
	var d := {
		"name": "Test_Ladder", "kind": "ladder", "descend_only": false,
		"bottom": [1.85, 0.0, 0.0], "top": [1.85, 3.0, 0.0], "foot_ground": [1.85, 0.0, 0.0],
		"top_exit": [2.35, 3.0, 0.0], "facing_xz": [0.5, 0.0],
	}
	d.merge(extra, true)
	return ClimbableDef.from_sidecar(d)


func _climb_time(height: float) -> float:
	return height / MovementModel.from_db(db()).climb_speed


func test_sidecar_entry_parses() -> void:
	var c := _ladder()
	assert_eq(c.kind, &"ladder")
	assert_near(c.facing.x, 1.0, 1e-6, "facing normalized into the wall")
	assert_true(c.has_foot_ground, "foot ground present")
	var rope := ClimbableDef.from_sidecar({"name": "R", "kind": "rope", "bottom": [0, 1, 0], "top": [0, 4, 0], "foot_ground": null, "top_exit": [0, 4, -0.5], "facing_xz": [0, -0.5], "descend_only": true})
	assert_false(rope.has_foot_ground, "null foot_ground")
	assert_true(rope.descend_only, "descend_only")
	assert_eq(ClimbableDef.list_from_sidecar([{"name": "bad"}, {"bottom": [0, 0, 0], "top": [0, 1, 0]}]).size(), 1, "invalid entries skipped")


func test_climbs_a_ladder_end_to_end() -> void:
	var c := _ladder()
	var p := w.spawn_player(Vector3(0.0, 0, 0))
	p.set_climbables([c])
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(40)  # walk up to the cliff face beside the ladder
	assert_true(c.line_distance_xz(p.global_position) <= 0.8, "beside the ladder")
	w.bot.world_dir = Vector3.ZERO
	w.bot.press(&"portal_enter")  # Up arrow
	w.player.step(PlayerTestWorld.TICK)
	assert_true(p.is_climbing(), "grabbed with Up")
	assert_true(p.current_climbable == c, "on the right ladder")
	w.bot.climb = 1.0
	var ended := []
	p.climb_ended.connect(func(cc: ClimbableDef, how: StringName) -> void: ended.append(how))
	var ticks := w.run_until(func() -> bool: return not p.is_climbing(), 600)
	assert_true(ticks > 0, "reached the top")
	assert_eq(ended, [&"top"], "left at the top")
	var expected := _climb_time(3.0 - MovementModel.from_db(db()).climb_exit_below_top)
	assert_near(ticks / 60.0, expected, 0.05, "climb time at the canonical climb speed")
	assert_true(p.is_grounded(), "standing on the upper cap")
	assert_near(p.global_position.y, 3.0, 0.02, "on top of the cliff")
	assert_true(p.global_position.x > 2.0, "stepped onto top_exit")
	# Back down: Down arrow (climb_down) at the top grabs from above.
	w.bot.climb = 0.0
	w.bot.press(&"climb_down")
	w.player.step(PlayerTestWorld.TICK)
	assert_true(p.is_climbing(), "grabbed from the top with Down")
	w.bot.climb = -1.0
	ticks = w.run_until(func() -> bool: return not p.is_climbing(), 600)
	assert_true(ticks > 0, "reached the bottom")
	assert_eq(ended, [&"top", &"bottom"], "left at the bottom")
	assert_true(p.is_grounded(), "standing at the foot")
	assert_near(p.global_position.y, 0.0, 0.02, "on the floor")


func test_interact_grabs_and_w_s_climb() -> void:
	var c := _ladder()
	var p := w.spawn_player(Vector3(1.2, 0, 0))
	p.set_climbables([c])
	w.bot.press(&"interact")
	w.player.step(PlayerTestWorld.TICK)
	assert_true(p.is_climbing(), "interact grabs when near")
	var y0 := p.global_position.y
	w.bot.move = Vector2(0, 1)  # W climbs while on a ladder
	w.run(30)
	assert_near(p.global_position.y - y0, MovementModel.from_db(db()).climb_speed * 0.5, 0.02, "W climbs at climb speed")
	w.bot.move = Vector2(0, 0)
	var y1 := p.global_position.y
	w.run(30)
	assert_near(p.global_position.y, y1, 1e-6, "no input: hang still")


func test_no_grab_when_far() -> void:
	var c := _ladder()
	var p := w.spawn_player(Vector3(-2.0, 0, 0))
	p.set_climbables([c])
	w.bot.press(&"portal_enter")
	w.player.step(PlayerTestWorld.TICK)
	assert_false(p.is_climbing(), "too far from the ladder")


func test_jump_off_sideways() -> void:
	var c := _ladder()
	var p := w.spawn_player(Vector3(1.4, 0, 0))
	p.set_climbables([c])
	w.bot.press(&"portal_enter")
	w.player.step(PlayerTestWorld.TICK)
	w.bot.climb = 1.0
	w.run(60)
	assert_true(p.is_climbing(), "climbing")
	w.bot.climb = 0.0
	w.bot.press(&"jump")  # jump alone does nothing (classic)
	w.player.step(PlayerTestWorld.TICK)
	assert_true(p.is_climbing(), "jump without a direction keeps holding on")
	w.player.step(PlayerTestWorld.TICK)  # release jump for a tick (two taps in a row read as a hold)
	w.bot.world_dir = Vector3(0, 0, 1)
	w.bot.press(&"jump")
	w.player.step(PlayerTestWorld.TICK)
	assert_false(p.is_climbing(), "jumped off sideways")
	assert_true(p.vertical_speed > 0.0, "a small hop")
	w.bot.world_dir = Vector3.ZERO
	var t := w.run_until(func() -> bool: return p.is_grounded(), 240)
	assert_true(t > 0, "landed")
	assert_true(p.global_position.z > 0.5, "moved sideways (z=%.2f)" % p.global_position.z)
	# Holding Up right after letting go does not re-grab immediately.
	assert_near(p.global_position.y, 0.0, 0.02, "on the floor")


func test_descend_only_rope() -> void:
	var c := _ladder({"kind": "rope", "descend_only": true})
	var p := w.spawn_player(Vector3(1.4, 0, 0))
	p.set_climbables([c])
	w.bot.press(&"portal_enter")
	w.player.step(PlayerTestWorld.TICK)
	assert_false(p.is_climbing(), "cannot grab a descend-only rope from the ground")
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(2.6, 3.0, 0)))
	w.bot.press(&"climb_down")
	w.player.step(PlayerTestWorld.TICK)
	assert_true(p.is_climbing(), "grab from the top")
	var y0 := p.global_position.y
	w.bot.climb = 1.0
	w.run(30)
	assert_near(p.global_position.y, y0, 1e-6, "cannot climb up")
	w.bot.climb = -1.0
	var t := w.run_until(func() -> bool: return not p.is_climbing(), 400)
	assert_true(t > 0, "climbed down")
	assert_true(p.is_grounded(), "at the foot")


func test_rope_without_foot_ground_drops() -> void:
	# A rope over a pit: its bottom hangs 1.5 m above the floor and has no foot ground.
	var c := _ladder({"kind": "rope", "bottom": [1.85, 1.5, 0.0], "foot_ground": null})
	var p := w.spawn_player(Vector3(2.6, 3.0, 0))
	p.set_climbables([c])
	w.bot.press(&"climb_down")
	w.player.step(PlayerTestWorld.TICK)
	assert_true(p.is_climbing(), "grabbed from the top")
	w.bot.climb = -1.0
	w.run_until(func() -> bool: return not p.is_climbing(), 400)
	assert_false(p.is_grounded(), "let go at the bottom: falling")
	w.bot.climb = 0.0
	var t := w.run_until(func() -> bool: return p.is_grounded(), 120)
	assert_true(t > 0, "landed below")
	assert_near(p.global_position.y, 0.0, 0.02, "on the floor")


func test_catch_rope_mid_air_holding_up() -> void:
	var c := _ladder()
	var p := w.spawn_player(Vector3(1.4, 0, 0))
	p.set_climbables([c])
	w.bot.press(&"jump")
	w.player.step(PlayerTestWorld.TICK)
	w.run(8)
	assert_false(p.is_grounded(), "airborne")
	w.bot.hold(&"portal_enter")
	w.player.step(PlayerTestWorld.TICK)
	assert_true(p.is_climbing(), "caught the ladder mid-jump by holding Up")
	assert_true(p.global_position.y > 0.2, "caught above the foot")


func test_jump_off_is_not_undone_by_a_held_up() -> void:
	var c := _ladder()
	var p := w.spawn_player(Vector3(1.4, 0, 0))
	p.set_climbables([c])
	w.bot.hold(&"portal_enter")  # Up held the whole time: grabs, climbs, and stays held through the jump-off
	w.player.step(PlayerTestWorld.TICK)
	assert_true(p.is_climbing(), "grabbed with Up")
	w.run(45)
	var y_on_ladder := p.global_position.y
	assert_true(y_on_ladder > 0.5, "climbed with Up held (y=%.2f)" % y_on_ladder)
	w.bot.world_dir = Vector3(0, 0, 1)
	w.bot.press(&"jump")
	w.player.step(PlayerTestWorld.TICK)
	assert_false(p.is_climbing(), "jumped off sideways")
	var cooldown_ticks := int(ceil(MovementModel.from_db(db()).climb_regrab_cooldown * 60.0))
	var regrabbed_at := w.run_until(func() -> bool: return p.is_climbing(), cooldown_ticks - 1)
	assert_eq(regrabbed_at, -1, "no re-grab during the re-grab cooldown while Up is held")
	w.run_until(func() -> bool: return p.is_grounded() or p.is_climbing(), 120)
	assert_false(p.is_climbing(), "the hop carried the player out of grab range")
	assert_true(c.line_distance_xz(p.global_position) > MovementModel.from_db(db()).climb_grab_radius, "landed beside the ladder")


func test_top_exit_and_descend_only_grab_respect_sidecar_fields() -> void:
	# A rope whose top_exit lies 0.5 m into the cliff: climbing up ends exactly on the probed top_exit.
	var c := _ladder({"kind": "vine"})
	var p := w.spawn_player(Vector3(1.4, 0, 0))
	p.set_climbables([c])
	assert_true(p.grabbable_climbable() == c, "grabbable_climbable() reports the vine within reach")
	assert_true(p.grab_climbable(c), "grab_climbable() API")
	w.bot.climb = 1.0
	w.run_until(func() -> bool: return not p.is_climbing(), 600)
	assert_near(Vector2(p.global_position.x, p.global_position.z).distance_to(Vector2(c.top_exit.x, c.top_exit.z)), 0.0, 0.01, "exited onto top_exit")
	assert_true(p.is_grounded(), "standing on the cap")
