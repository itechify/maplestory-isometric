class_name GroundQuery
extends RefCounted
## The question pure map code asks the world: "where is walkable ground here, and is there room to stand?".
##
## MapDefinitions.ground_all() and SpawnSlotPlanner only talk to this interface, so they stay pure. The world
## runtime answers with PhysicsGroundQuery (raycasts and shape queries on the collision layers). This base class
## answers for an imaginary flat world: the ground is wherever the caller hints and everything is clear, which
## lets L0 tests run the full placement logic without any geometry.


## Ground under p, searching from p.y + up_m down to p.y - down_m. The first surface hit must be walkable.
## Returns {"ok": bool, "y": float, "normal": Vector3, "note": String}.
func ground_at(p: Vector3, _up_m: float, _down_m: float) -> Dictionary:
	return {"ok": true, "y": p.y, "normal": Vector3.UP, "note": "flat"}


## The topmost surface at (x, z) between y_top and y_bottom. ok only when that surface is walkable.
## `hint_y` is what the flat base implementation answers.
func top_surface(_x: float, _z: float, _y_top: float, _y_bottom: float, hint_y: float) -> Dictionary:
	return {"ok": true, "y": hint_y, "normal": Vector3.UP, "note": "flat"}


## True when an upright capsule (radius, height) standing with its feet at `feet` overlaps no blocking or
## containment collision.
func is_clear(_feet: Vector3, _radius: float, _height: float) -> bool:
	return true
