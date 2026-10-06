extends TestCase
## PlayerController.activity() (contract C4): still, walking, jumping (any airborne state), climbing, attacking
## (PlayerCombat.is_attacking()), seated, hitstun, dead, other. "Standing completely still" is grounded, no movement
## input and about zero horizontal speed; natural HP recovery runs only while still or seated.

var w: PlayerTestWorld


func parity_keys() -> Dictionary:
	return {
		"test_standing_on_the_ground_is_still": ["mechanic:natural-hp-regen"],
		"test_walking_and_pushing_into_a_wall_are_walking": ["mechanic:natural-hp-regen-pause-walking"],
		"test_airborne_is_jumping": ["mechanic:natural-hp-regen-pause-jumping"],
		"test_attack_lockout_is_attacking_even_when_planted": ["mechanic:natural-hp-regen-pause-attacking"],
		"test_seated_is_seated": ["mechanic:natural-hp-regen-sitting"],
	}


## A stand-in for PlayerCombat: is_attacking() as set (a basic attack's or a skill cast's lockout).
class FakeCombat:
	extends Node
	var attacking: bool = false

	func is_attacking() -> bool:
		return attacking


func before_each() -> void:
	w = PlayerTestWorld.create(db())
	w.add_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))


func after_each() -> void:
	w.free_all()


func test_standing_on_the_ground_is_still() -> void:
	var p := w.spawn_player(Vector3.ZERO)
	w.run(5)
	assert_eq(p.activity(), &"still")


func test_walking_and_pushing_into_a_wall_are_walking() -> void:
	var p := w.spawn_player(Vector3.ZERO)
	w.bot.world_dir = Vector3.RIGHT
	w.run(10)
	assert_eq(p.activity(), &"walking", "walking")
	w.bot.world_dir = Vector3.ZERO
	w.run(1)
	assert_eq(p.activity(), &"walking", "still decelerating on the first tick after the key is released")
	w.run(3)
	assert_eq(p.activity(), &"still", "stopped")
	# A wall: input held, the body does not move, and the player still counts as walking (not standing still).
	w.add_box(Vector3(3.0, 1.0, 0.0), Vector3(1.0, 2.0, 6.0))
	w.bot.world_dir = Vector3.RIGHT
	w.run(120)
	assert_near(p.actual_velocity.length(), 0.0, 0.01, "pressed against the wall")
	assert_eq(p.activity(), &"walking", "movement input against a wall is walking")


func test_input_disabled_with_a_key_held_is_still() -> void:
	var p := w.spawn_player(Vector3.ZERO)
	p.set_input_enabled(false)
	w.bot.world_dir = Vector3.RIGHT
	w.run(10)
	assert_eq(p.activity(), &"still", "a dialogue holds the keyboard: standing still")


func test_airborne_is_jumping() -> void:
	var p := w.spawn_player(Vector3.ZERO)
	w.bot.press(&"jump")
	w.run(3)
	assert_eq(p.activity(), &"jumping", "a jump")
	w.run(60)
	assert_eq(p.activity(), &"still", "landed")
	var q := w.spawn_player(Vector3(10, 4, 0))
	w.run(2)
	assert_eq(q.activity(), &"jumping", "falling is airborne too")


func test_holding_jump_is_jumping_on_every_tick_including_the_landings() -> void:
	var p := w.spawn_player(Vector3.ZERO)
	w.run(2)
	w.bot.hold(&"jump")
	var landings := 0
	for i in 180:
		w.run(1)
		if p.is_grounded():
			landings += 1
		assert_eq(p.activity(), &"jumping", "tick %d of a held jump (grounded %s)" % [i, p.is_grounded()])
	assert_true(landings > 0, "the held jump landed and re-hopped (%d grounded ticks)" % landings)
	w.bot.release(&"jump")
	w.run(60)
	assert_eq(p.activity(), &"still", "released: standing still again")


func test_climbing_hitstun_and_dead() -> void:
	var p := w.spawn_player(Vector3.ZERO)
	var c := ClimbableDef.from_sidecar({"name": "L", "kind": "ladder", "bottom": [0.5, 0.0, 0.0], "top": [0.5, 4.0, 0.0],
		"foot_ground": [0.5, 0.0, 0.0], "top_exit": [1.0, 4.0, 0.0], "facing_xz": [0.5, 0.0]})
	assert_true(p.grab_climbable(c), "grabbed")
	assert_eq(p.activity(), &"climbing")
	var p2 := w.spawn_player(Vector3(5, 0, 0))
	w.run(2)
	p2.apply_knockback(Vector3.RIGHT)
	assert_eq(p2.activity(), &"hitstun", "a knockback in flight")
	p2.die()
	assert_eq(p2.activity(), &"dead")


func test_attack_lockout_is_attacking_even_when_planted() -> void:
	var p := w.spawn_player(Vector3.ZERO)
	var combat := FakeCombat.new()
	combat.name = "PlayerCombat"
	p.add_child(combat)
	w.run(2)
	combat.attacking = true
	w.run(2)
	assert_near(p.actual_velocity.length(), 0.0, 0.001, "planted: speed 0")
	assert_eq(p.activity(), &"attacking", "a planted ground attack is not standing still")
	combat.attacking = false
	assert_eq(p.activity(), &"still")


func test_seated_is_seated() -> void:
	var p := w.spawn_player(Vector3.ZERO)
	w.run(2)
	assert_true(p.sit("522"), "sat down")
	assert_eq(p.activity(), &"seated")
	w.run(30)
	assert_eq(p.activity(), &"seated", "stays seated without input")


func test_frozen_or_outside_the_tree_is_other() -> void:
	var p := w.spawn_player(Vector3.ZERO)
	w.run(2)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	assert_eq(p.activity(), &"other", "frozen for a warp")
	p.process_mode = Node.PROCESS_MODE_INHERIT
	assert_eq(p.activity(), &"still")
	var loose := PlayerController.new()
	assert_eq(loose.activity(), &"other", "no model, not in the tree")
	loose.free()
