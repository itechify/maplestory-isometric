class_name PhysicsGroundQuery
extends GroundQuery
## GroundQuery answered by the physics space: vertical rays against walkable + blocking collision (the first surface
## hit must be walkable) and capsule overlap queries against blocking + containment collision. Works synchronously
## as soon as the static bodies are in the tree (Jolt answers queries before the first physics step).

var space: PhysicsDirectSpaceState3D = null
var surface_mask: int = WorldLayers.SURFACE_MASK
var walkable_mask: int = WorldLayers.WALKABLE
var clearance_mask: int = WorldLayers.CLEARANCE_MASK
## Bodies to ignore (e.g. the player itself).
var exclude: Array[RID] = []
## A blocking, floor-like first surface within this height above walkable ground counts as ground
## (presentation.json grounding.coplanar_tolerance_m; 0 disables).
var coplanar_tolerance: float = 0.0


func _init(p_space: PhysicsDirectSpaceState3D = null) -> void:
	space = p_space


func ground_at(p: Vector3, up_m: float, down_m: float) -> Dictionary:
	return _first_surface(p + Vector3.UP * up_m, p - Vector3.UP * down_m)


func top_surface(x: float, z: float, y_top: float, y_bottom: float, _hint_y: float) -> Dictionary:
	return _first_surface(Vector3(x, y_top, z), Vector3(x, y_bottom, z))


func is_clear(feet: Vector3, radius: float, height: float) -> bool:
	if space == null:
		return false
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(height, radius * 2.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (shape.height * 0.5))
	q.collision_mask = clearance_mask
	q.exclude = exclude
	return space.intersect_shape(q, 1).is_empty()


## What blocks a capsule at `feet` (names of up to 4 colliders), for diagnostics.
func blockers(feet: Vector3, radius: float, height: float) -> PackedStringArray:
	var out: PackedStringArray = []
	if space == null:
		return out
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(height, radius * 2.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (shape.height * 0.5))
	q.collision_mask = clearance_mask
	q.exclude = exclude
	for hit in space.intersect_shape(q, 4):
		var c: Object = hit.get("collider")
		out.append(String((c as Node).name) if c is Node else "?")
	return out


## Walkable ground directly under p within `down_m` (no blocking check): {"ok", "y", "collider"}.
func walkable_below(p: Vector3, down_m: float) -> Dictionary:
	if space == null:
		return {"ok": false, "y": p.y}
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.05, p - Vector3.UP * down_m, walkable_mask, exclude)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {"ok": false, "y": p.y}
	return {"ok": true, "y": (hit.position as Vector3).y, "collider": hit.get("collider")}


func _first_surface(from: Vector3, to: Vector3) -> Dictionary:
	if space == null:
		return {"ok": false, "y": from.y, "normal": Vector3.UP, "note": "no physics space"}
	var q := PhysicsRayQueryParameters3D.create(from, to, surface_mask, exclude)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {"ok": false, "y": to.y, "normal": Vector3.UP, "note": "no surface between %.2f and %.2f" % [from.y, to.y]}
	var pos: Vector3 = hit.position
	var col: Object = hit.get("collider")
	var layer := (col as CollisionObject3D).collision_layer if col is CollisionObject3D else 0
	if layer & walkable_mask == 0:
		var nm := String((col as Node).name) if col is Node else "?"
		# A blocking surface lying on walkable ground (within coplanar_tolerance) counts as that ground.
		var n: Vector3 = hit.normal
		if coplanar_tolerance > 0.0:
			var below := walkable_below(pos, coplanar_tolerance)
			if bool(below.ok):
				return {"ok": true, "y": pos.y, "normal": n, "note": "on %s, coplanar with walkable" % nm}
		return {"ok": false, "y": pos.y, "normal": n, "note": "first surface is not walkable (%s)" % nm}
	return {"ok": true, "y": pos.y, "normal": hit.normal, "note": ""}
