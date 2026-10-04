class_name WorldTestPlayer
extends CharacterBody3D
## A minimal capsule used ONLY by the world runtime's own tests and checks (the game's player controller lives in
## scripts/actors/player/). It implements the duck-typed player API the world and MapSession rely on
## (docs/runtime/WORLD_RUNTIME.md "Player contract"): teleport(xform), is_on_floor(), global_position, velocity,
## set_input_enabled(bool) / is_input_enabled(), and an optional `input_source` (BotInput in tests) that it ticks like
## the controller.
## It does not walk: tests move it with teleport() and press keys through `input_source`.

## Read by PortalInteractor (the same contract as the real controller).
var input_source: InputSource = null
var input_enabled: bool = true
var teleports: int = 0
var _shape: CollisionShape3D = null


## Builds the capsule (feet at the origin). Call before adding to the tree.
func configure(radius: float, height: float) -> void:
	name = "WorldTestPlayer"
	collision_layer = WorldLayers.PLAYER
	collision_mask = WorldLayers.PLAYER_MASK
	_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	_shape.shape = capsule
	_shape.position = Vector3.UP * (capsule.height * 0.5)
	add_child(_shape)


func _physics_process(delta: float) -> void:
	if input_source != null:
		input_source.begin_tick()
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func teleport(xform: Transform3D) -> void:
	global_transform = xform
	velocity = Vector3.ZERO
	teleports += 1
	reset_physics_interpolation()


func set_input_enabled(on: bool) -> void:
	input_enabled = on


func is_input_enabled() -> bool:
	return input_enabled
