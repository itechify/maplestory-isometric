class_name ClimbableDef
extends RefCounted
## One ladder, rope or vine, as exported in a map sidecar's `climbables[]` (docs/runtime/blender_export.md).
##
## The climb line is vertical through `bottom`/`top` (the validator's climb point). `facing` points from the
## climb line into the cliff/wall (top_exit = top + 0.5 m x facing), so a climber faces `facing` and hangs on
## the opposite side. `top_exit` is the probed standing point on the upper cap. `foot_ground` is the walkable
## point at the foot, or absent for ropes that hang over a pit (letting go at the bottom is then a fall).

var name: String = ""
## &"ladder", &"rope" or &"vine".
var kind: StringName = &"ladder"
## Descend-only ropes can be grabbed from the top (or caught mid-air) and only climbed down.
var descend_only: bool = false
var bottom: Vector3 = Vector3.ZERO
var top: Vector3 = Vector3.ZERO
var top_exit: Vector3 = Vector3.ZERO
var has_foot_ground: bool = false
var foot_ground: Vector3 = Vector3.ZERO
## Horizontal unit vector from the climb line into the wall.
var facing: Vector3 = Vector3.FORWARD


## Builds one definition from a sidecar entry. Returns null if the entry lacks bottom/top.
static func from_sidecar(d: Dictionary) -> ClimbableDef:
	if not (d.get("bottom") is Array and d.get("top") is Array):
		return null
	var c := ClimbableDef.new()
	c.name = String(d.get("name", ""))
	c.kind = StringName(String(d.get("kind", "ladder")))
	c.descend_only = bool(d.get("descend_only", false))
	c.bottom = _vec3(d["bottom"])
	c.top = _vec3(d["top"])
	if d.get("top_exit") is Array:
		c.top_exit = _vec3(d["top_exit"])
	else:
		c.top_exit = c.top
	if d.get("foot_ground") is Array:
		c.has_foot_ground = true
		c.foot_ground = _vec3(d["foot_ground"])
	var f := Vector3.ZERO
	if d.get("facing_xz") is Array and (d["facing_xz"] as Array).size() >= 2:
		f = Vector3(float(d["facing_xz"][0]), 0.0, float(d["facing_xz"][1]))
	if f.length_squared() < 0.0001:
		f = Vector3(c.top_exit.x - c.top.x, 0.0, c.top_exit.z - c.top.z)
	c.facing = f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD
	return c


## Every valid entry of a sidecar `climbables` array.
static func list_from_sidecar(entries: Array) -> Array[ClimbableDef]:
	var out: Array[ClimbableDef] = []
	for e in entries:
		if e is Dictionary:
			var c := from_sidecar(e)
			if c != null:
				out.append(c)
	return out


static func _vec3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Horizontal distance from `p` to the vertical climb line.
func line_distance_xz(p: Vector3) -> float:
	return Vector2(p.x - bottom.x, p.z - bottom.z).length()


## Horizontal distance from `p` to the top exit.
func top_exit_distance_xz(p: Vector3) -> float:
	return Vector2(p.x - top_exit.x, p.z - top_exit.z).length()


## Where a climber's feet are at height `y`: on the climb line, `standoff` meters out from the wall.
func climb_position(y: float, standoff: float) -> Vector3:
	return Vector3(bottom.x - facing.x * standoff, y, bottom.z - facing.z * standoff)


func height() -> float:
	return top.y - bottom.y
