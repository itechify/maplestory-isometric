class_name AttackLockInput
extends InputSource
## Decorates the player's InputSource while a ground attack plays: no walking and no jumping until the attack's
## lockout ends (classic: a basic attack on the ground plants the character for its animation; in the air the jump
## carries on). Every other read passes straight through to `inner`, so portals, NPC talk and the bot keep working.
## PlayerCombat installs it as player.input_source and re-wraps whenever another system swaps the source.

var inner: InputSource = null
var locked: bool = false


func _init(p_inner: InputSource = null) -> void:
	inner = p_inner


func begin_tick() -> void:
	if inner != null:
		inner.begin_tick()


func move_vector() -> Vector2:
	if locked or inner == null:
		return Vector2.ZERO
	return inner.move_vector()


func world_move(right: Vector3, forward: Vector3) -> Vector3:
	if locked or inner == null:
		return Vector3.ZERO
	return inner.world_move(right, forward)


func is_held(action: StringName) -> bool:
	if inner == null or (locked and action == &"jump"):
		return false
	return inner.is_held(action)


func just_pressed(action: StringName) -> bool:
	if inner == null or (locked and action == &"jump"):
		return false
	return inner.just_pressed(action)


func climb_axis() -> float:
	return inner.climb_axis() if inner != null else 0.0
