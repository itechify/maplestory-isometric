class_name SafeGround
extends RefCounted
## The player's last safe standing point (MAP_ARCHITECTURE.md section 4.6 and 4.9).
##
## The controller records it on every tick the player stands on walkable floor, is not in hit-stun, is alive and
## passes the controller's optional safe_ground_filter (the world runtime plugs its RegionIndex check in there).
## Recovery from a fall belongs to MapSession: it reads `position` (or transform()) and calls player.teleport().
## Saves read it too, so a save made mid-jump or mid-knockback stores the last safe ground point.

## World-space feet position of the last safe ground point.
var position: Vector3 = Vector3.ZERO
## False until the first record()/reset().
var valid: bool = false
## Floor normal under that point.
var floor_normal: Vector3 = Vector3.UP
## instance_id of the collider stood on (0 when unknown, e.g. after reset()).
var collider_id: int = 0
## Horizontal facing when it was recorded (MODEL_FRONT convention, +Z at yaw 0).
var facing: Vector3 = Vector3.BACK
## Physics ticks since the record was last refreshed (0 = this tick).
var age_ticks: int = 0


## Records a standing point (called by the controller).
func record(pos: Vector3, normal: Vector3, collider: int, face: Vector3) -> void:
	position = pos
	floor_normal = normal
	collider_id = collider
	if face.length_squared() > 0.0001:
		facing = face
	valid = true
	age_ticks = 0


## Forces the safe point (teleport, respawn, load).
func reset(pos: Vector3, face: Vector3 = Vector3.ZERO) -> void:
	record(pos, Vector3.UP, 0, face)


## A transform suitable for player.teleport(): the safe point, facing the recorded direction.
func transform() -> Transform3D:
	var f := Vector3(facing.x, 0.0, facing.z)
	if f.length_squared() < 0.0001:
		f = Vector3.BACK
	f = f.normalized()
	var x := Vector3.UP.cross(f).normalized()
	return Transform3D(Basis(x, Vector3.UP, f), position)


func tick() -> void:
	age_ticks += 1
