extends TestCase
## Sitting on the PlayerController (contract C5): the player sits only when grounded, still, alive and with input
## enabled; while seated it cannot walk, jump or climb; a move, jump, attack or sit press stands it up (that press does
## nothing else that tick); knockback, death, climbing, teleport and losing the chair stand it up; the sit key (X) sits
## on the first chair owned or reports that there is none; and the seated state is never saved (contract C3).

const RELAXER := "522"

var w: PlayerTestWorld
var holder: CharacterState


func parity_keys() -> Dictionary:
	var sit := ["mechanic:sitting"]
	return {
		"test_sits_only_when_grounded_still_alive_and_free": sit,
		"test_seated_player_cannot_walk_a_move_press_stands_it_up_first": sit,
		"test_a_jump_press_stands_up_without_jumping": sit,
		"test_an_attack_or_a_cast_stands_up": sit,
		"test_knockback_death_climb_and_teleport_stand_up": sit,
		"test_sit_key_toggles_on_the_first_owned_chair": sit + ["chair:522"],
		"test_sit_key_without_a_chair_says_so": sit,
		"test_losing_the_chair_stands_up": sit + ["chair:522"],
		"test_seated_state_is_not_saved": sit + ["chair:522"],
	}


class FakeCombat:
	extends Node
	var attacking: bool = false

	func is_attacking() -> bool:
		return attacking


func before_each() -> void:
	w = PlayerTestWorld.create(db())
	w.add_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))
	holder = CharacterState.new()


func after_each() -> void:
	w.free_all()


## A player standing still on the floor whose Set-up tab the sit key reads.
func _player() -> PlayerController:
	var p := w.spawn_player(Vector3.ZERO)
	p.chair_owner = holder
	w.run(2)
	return p


func _record(p: PlayerController) -> Array:
	var seen := []
	p.sat_down.connect(func(id: String) -> void: seen.append(["sat", id]))
	p.stood_up.connect(func(why: StringName) -> void: seen.append(["stood", why]))
	return seen


func test_sits_only_when_grounded_still_alive_and_free() -> void:
	var p := _player()
	var seen := _record(p)
	assert_eq(p.can_sit(), "", "standing still on the floor")
	assert_true(p.sit(RELAXER), "sat down")
	assert_true(p.is_seated())
	assert_eq(p.seated_chair_id(), RELAXER)
	assert_eq(seen, [["sat", RELAXER]], "sat_down(chair)")
	assert_eq(p.can_sit(), "seated", "already seated")
	assert_true(p.stand_up(&"test"), "stood up")
	assert_false(p.stand_up(&"test"), "standing already: no-op")
	assert_eq(seen, [["sat", RELAXER], ["stood", &"test"]])
	# Walking.
	w.bot.world_dir = Vector3.RIGHT
	w.run(5)
	assert_eq(p.can_sit(), "walking")
	assert_false(p.sit(RELAXER), "no sitting while walking")
	w.bot.world_dir = Vector3.ZERO
	w.run(5)
	# Airborne.
	w.bot.press(&"jump")
	w.run(3)
	assert_eq(p.can_sit(), "jumping")
	assert_false(p.sit(RELAXER))
	w.run(60)
	# A modal window (input disabled).
	p.set_input_enabled(false)
	assert_eq(p.can_sit(), "input")
	p.set_input_enabled(true)
	# Dead.
	p.die()
	assert_eq(p.can_sit(), "dead")
	assert_false(p.sit(RELAXER))
	p.revive()
	assert_eq(p.can_sit(), "")
	assert_false(p.sit(""), "no chair id")


func test_seated_player_cannot_walk_a_move_press_stands_it_up_first() -> void:
	var p := _player()
	p.sit(RELAXER)
	w.run(30)
	var at := p.global_position
	assert_true(p.is_seated(), "seated without input")
	w.bot.world_dir = Vector3.RIGHT
	w.run(1)
	assert_false(p.is_seated(), "a move press stands the player up")
	assert_near(p.global_position.distance_to(at), 0.0, 1e-4, "that press does not also move it")
	assert_eq(p.activity(), &"walking", "the player wants to move")
	w.run(10)
	assert_true(p.global_position.x > at.x + 0.2, "the held key walks from the next tick on")


func test_a_jump_press_stands_up_without_jumping() -> void:
	var p := _player()
	p.sit(RELAXER)
	w.bot.hold(&"jump")
	w.run(1)
	assert_false(p.is_seated(), "jump stands up")
	assert_true(p.is_grounded(), "no jump on that press")
	w.run(20)
	assert_true(p.is_grounded(), "holding the key does not jump either (a new press is needed)")
	w.bot.release(&"jump")
	w.run(1)
	w.bot.press(&"jump")
	w.run(3)
	assert_false(p.is_grounded(), "the next press jumps")


func test_an_attack_or_a_cast_stands_up() -> void:
	# A real PlayerCombat (MonsterTestRig): the attack key swings, and the swing stands the player up.
	var rig := MonsterTestRig.create(db(), 3)
	rig.floor(40.0)
	var rp := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var rig_seen := _record(rp)
	rig.run(2)
	assert_true(rp.sit(RELAXER), "seated")
	rig.w.bot.press(&"attack")
	rig.run(2)
	assert_eq(rig.system.player_combat.attacks, 1, "the attack press swings (PlayerCombat runs after the body)")
	assert_false(rp.is_seated(), "the swing stands the player up")
	assert_eq(rig_seen.back(), ["stood", &"attack"])
	rig.free_all()
	# Any other system's attack lockout (a skill cast) does the same.
	var p := _player()
	var combat := FakeCombat.new()
	combat.name = "PlayerCombat"
	p.add_child(combat)
	w.run(2)
	p.sit(RELAXER)
	combat.attacking = true  # a skill cast (or a held attack) started by another system
	w.run(1)
	assert_false(p.is_seated(), "PlayerCombat attacking stands up")
	combat.attacking = false


func test_knockback_death_climb_and_teleport_stand_up() -> void:
	var p := _player()
	var seen := _record(p)
	p.sit(RELAXER)
	p.apply_knockback(Vector3.RIGHT)
	assert_false(p.is_seated(), "knockback")
	w.run(60)
	p.sit(RELAXER)
	p.die()
	assert_false(p.is_seated(), "death")
	p.revive()
	w.run(2)
	p.sit(RELAXER)
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(4, 0, 4)))
	assert_false(p.is_seated(), "teleport (warps, respawns, loads)")
	w.run(2)
	p.sit(RELAXER)
	var c := ClimbableDef.from_sidecar({"name": "L", "kind": "ladder", "bottom": [4.5, 0.0, 4.0], "top": [4.5, 4.0, 4.0],
		"foot_ground": [4.5, 0.0, 4.0], "top_exit": [5.0, 4.0, 4.0], "facing_xz": [0.5, 0.0]})
	p.grab_climbable(c)
	assert_false(p.is_seated(), "a climb")
	var reasons := seen.filter(func(e: Array) -> bool: return e[0] == "stood").map(func(e: Array) -> StringName: return e[1])
	assert_eq(reasons, [&"knockback", &"death", &"teleport", &"climb"])


func test_seated_player_ignores_ladder_keys() -> void:
	var p := _player()
	var c := ClimbableDef.from_sidecar({"name": "L", "kind": "ladder", "bottom": [0.3, 0.0, 0.0], "top": [0.3, 4.0, 0.0],
		"foot_ground": [0.3, 0.0, 0.0], "top_exit": [0.8, 4.0, 0.0], "facing_xz": [0.5, 0.0]})
	var list: Array[ClimbableDef] = [c]
	p.set_climbables(list)
	p.sit(RELAXER)
	w.bot.press(&"portal_enter")
	w.run(2)
	assert_true(p.is_seated(), "Up does not grab a ladder from a chair")
	assert_false(p.is_climbing())


func test_sit_key_toggles_on_the_first_owned_chair() -> void:
	var p := _player()
	holder.inventory.add(RELAXER, 1, db())
	w.bot.press(&"sit")
	w.run(1)
	assert_true(p.is_seated(), "X sits on the first chair in the Set-up tab")
	assert_eq(p.seated_chair_id(), RELAXER)
	w.run(30)
	assert_true(p.is_seated())
	w.bot.press(&"sit")
	w.run(1)
	assert_false(p.is_seated(), "X again stands up")
	w.run(2)
	var res := p.sit_key()
	assert_true(res.ok, str(res))
	assert_eq(res.action, "sit")
	res = p.sit_key()
	assert_eq(res.action, "stand")


func test_sit_key_without_a_chair_says_so() -> void:
	var p := _player()
	var res := p.sit_key()
	assert_eq(res.code, ItemCodes.NO_CHAIR, "no chair in the Set-up tab")
	assert_eq(ItemCodes.message(res), "You do not have a chair to sit on.")
	assert_false(p.is_seated())
	holder.inventory.add("270", 3, db())  # a potion is not a chair
	assert_eq(p.sit_key().code, ItemCodes.NO_CHAIR)
	holder.inventory.add(RELAXER, 1, db())
	w.bot.world_dir = Vector3.RIGHT
	w.run(5)
	res = p.sit_key()
	assert_eq(res.code, ItemCodes.CANNOT_SIT, "a chair, but the player is walking")
	assert_eq(res.reason, "walking")


func test_losing_the_chair_stands_up() -> void:
	var p := _player()
	holder.inventory.add(RELAXER, 1, db())
	p.sit(RELAXER)
	p._on_item_lost("270", 1)
	assert_true(p.is_seated(), "another item")
	holder.inventory.remove(RELAXER, 1)
	p._on_item_lost(RELAXER, 1)
	assert_false(p.is_seated(), "sold or dropped the chair it sits on")


func test_seated_state_is_not_saved() -> void:
	var p := _player()
	holder.inventory.add(RELAXER, 1, db())
	p.sit(RELAXER)
	var d := holder.to_dict()
	var text := JSON.stringify(d)
	for word in ["seat", "sitting", "sat_"]:
		assert_false(text.contains(word), "no '%s' in the save: %s" % [word, d.keys()])
	assert_eq((d["natural_recovery"] as Dictionary).keys(), ["hp_rest_s"], "natural_recovery holds only the clock")
	var loaded := CharacterState.from_dict(JSON.parse_string(text))
	assert_eq(loaded.inventory.count(RELAXER), 1, "the chair itself is owned after a load (Set-up tab)")
	# A load places the player with teleport() (MapSession, via load): it arrives standing.
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(2, 0, 2)))
	assert_false(p.is_seated(), "a loaded game starts standing")
