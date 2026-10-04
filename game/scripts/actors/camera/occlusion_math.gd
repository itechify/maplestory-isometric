class_name OcclusionMath
extends RefCounted
## Pure rules of the occlusion system (OcclusionFader, docs/runtime/PLAYER_AND_CAMERA.md "Occlusion"). No scene tree.
##
## Which meshes may fade (camera.json `occluders`), how meshes group into one fading unit (a tree's trunk and
## canopy), where the sample points of a body and of the readability disc around the player lie, the in-front test
## in the camera's view frame, the dither holes handed to the occluder shader and a CPU mirror of that shader's cut.
##
## View frame: for a camera basis `cam` (Godot cameras look along -Z), a world point p has view coordinates
## x = p . cam.x (screen right), y = p . cam.y (screen up) and depth z = -p . cam.z (grows away from the camera).
## The gameplay camera is orthographic, so two points with the same (x, y) cover the same pixel and the one with the
## smaller depth hides the other.


# =================================================================================================================
# Candidates
# =================================================================================================================

## True if a mesh with these glTF extras may fade. `height_m` is the world height of the mesh's fading unit (all
## parts of its Blender instance, OcclusionFader.scan), so the parts of one tall instance pass or fail together.
## `rules` is camera.json `occluders`:
##   never            groups or categories that never fade (terrain, plinths, rocks, island body, sky)
##   never_flags      extras flags that never fade when set (walkable ground, climbables)
##   categories       categories that always fade (Trees, Architecture)
##   groups           groups that always fade (Architecture)
##   tall_categories, tall_groups, tall_min_height_m   these fade only when at least that tall (props, giant
##                    mushrooms, hedges), so flowers, bushes and crates never do
static func is_occluder(extras: Dictionary, height_m: float, rules: Dictionary) -> bool:
	var cat := String(extras.get("category", ""))
	var grp := String(extras.get("group", ""))
	var never: Array = rules.get("never", [])
	if (cat != "" and cat in never) or (grp != "" and grp in never):
		return false
	for flag in rules.get("never_flags", []):
		if _flag_set(extras.get(String(flag))):
			return false
	if (cat != "" and cat in rules.get("categories", [])) or (grp != "" and grp in rules.get("groups", [])):
		return true
	if height_m >= float(rules.get("tall_min_height_m", INF)):
		if (cat != "" and cat in rules.get("tall_categories", [])) or (grp != "" and grp in rules.get("tall_groups", [])):
			return true
	return false


static func _flag_set(v: Variant) -> bool:
	if v is bool:
		return v
	if v is String:
		return v != "" and v != "false" and v != "none"
	if v is float or v is int:
		return v != 0
	return false


## True if a target standing inside `box` (its chest at `chest`) must not fade the mesh: the room the player stands
## in (camera.json `occluders.room_groups`, e.g. Architecture), a shell whose ground footprint is at least
## `room_min_size_m` on both axes (the interior shells and the cutaway house are 10-18 m). Smaller architecture the
## chest happens to be inside (a town gate, an arch, a gazebo, a sign, a door frame: at most 7.1 m) is no room and
## fades like any building; so does a tree or tunnel the player stands in.
static func is_room(extras: Dictionary, box: AABB, chest: Vector3, rules: Dictionary) -> bool:
	var grp := String(extras.get("group", ""))
	var cat := String(extras.get("category", ""))
	var rooms: Array = rules.get("room_groups", [])
	if not ((grp != "" and grp in rooms) or (cat != "" and cat in rooms)):
		return false
	if minf(box.size.x, box.size.z) < float(rules.get("room_min_size_m", 0.0)):
		return false
	return box.grow(0.05).has_point(chest)


## The fading unit of a mesh: Blender instances export one node per part, named "<instance>__<part>" under one parent
## (a tree's trunk and canopy), and all parts of an instance fade together.
static func unit_key(node_name: String, parent_id: int) -> String:
	var base := node_name.get_slice("__", 0) if node_name.contains("__") else node_name
	return "%d/%s" % [parent_id, base]


# =================================================================================================================
# View frame
# =================================================================================================================

## View coordinates (x right, y up, depth) of a world point.
static func to_view(p: Vector3, cam: Basis) -> Vector3:
	return Vector3(p.dot(cam.x), p.dot(cam.y), -p.dot(cam.z))


## The view-frame box (x, y, depth) of a world AABB: the screen rectangle it can cover and its depth range.
static func view_box(box: AABB, cam: Basis) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in 8:
		var v := to_view(box.get_endpoint(i), cam)
		lo = lo.min(v)
		hi = hi.max(v)
	return AABB(lo, hi - lo)


## Prefilter: a mesh with view box `vbox` can hide the point at view position `pv` only if pv lies inside its screen
## rectangle and part of the mesh is nearer the camera than pv.
static func may_cover(vbox: AABB, pv: Vector3) -> bool:
	return pv.x >= vbox.position.x and pv.x <= vbox.end.x and pv.y >= vbox.position.y and pv.y <= vbox.end.y \
		and vbox.position.z < pv.z


## The screen rectangle (view x, y) of a set of view points, grown by `margin`.
static func screen_rect(points_view: PackedVector3Array, margin: float = 0.0) -> Rect2:
	if points_view.is_empty():
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in points_view:
		lo = lo.min(Vector2(v.x, v.y))
		hi = hi.max(Vector2(v.x, v.y))
	return Rect2(lo, hi - lo).grow(margin)


# =================================================================================================================
# Sample points
# =================================================================================================================

## Points covering a standing body as the camera sees it: `rows` heights from near the feet to near the top of
## `height`, each at the left edge, the centre and the right edge (`half_width` along the camera's ground right
## axis). The whole silhouette is tested, not one ray.
static func body_samples(feet: Vector3, height: float, half_width: float, cam: Basis, rows: int = 5) -> PackedVector3Array:
	var out := PackedVector3Array()
	var right := Vector3(cam.x.x, 0.0, cam.x.z)
	right = right.normalized() if right.length_squared() > 1e-8 else Vector3.RIGHT
	var n := maxi(rows, 1)
	for i in n:
		var t := 0.5 if n == 1 else float(i) / float(n - 1)
		var h := height * lerpf(0.1, 0.95, t)
		for side in [-1.0, 0.0, 1.0]:
			out.append(feet + Vector3.UP * h + right * (side * half_width))
	return out


## Points of the readability disc: the centre and `rings` rings of `per_ring` points out to `radius`, all in the
## screen plane through `center` (perpendicular to the view), so every point has the centre's depth. An occluder that
## hides any of them is in front of the player within that screen radius.
static func disc_samples(center: Vector3, radius: float, cam: Basis, rings: int = 2, per_ring: int = 8) -> PackedVector3Array:
	var out := PackedVector3Array([center])
	for r in range(1, rings + 1):
		var rr := radius * float(r) / float(rings)
		for k in per_ring:
			var a := TAU * (float(k) + 0.5 * float(r % 2)) / float(per_ring)
			out.append(center + cam.x * (cos(a) * rr) + cam.y * (sin(a) * rr))
	return out


# =================================================================================================================
# Dither holes (occluder shader)
# =================================================================================================================

## One hole of the occluder dither shader: the target's centre in the camera's view space (x, y in meters, Godot
## view space: the camera at the origin looking along -Z), the hole radius, and the depth up to which fragments are
## cut (the target's depth + `depth_margin`; anything further away stays solid).
static func hole(center: Vector3, radius: float, depth_margin: float, cam_xform: Transform3D) -> Vector4:
	var v := cam_xform.affine_inverse() * center
	return Vector4(v.x, v.y, radius, -v.z + depth_margin)


## The floor of a hole: the world height below which it cuts nothing (the target's feet + `margin`). An occluder
## point in front of a target that covers its body on screen is always above its feet (at the 40 degree pitch a point
## d meters nearer the camera must be at least 0.84 d higher), so this costs the body nothing; it keeps the deck,
## floor or platform the target stands on (a gazebo floor, an interior shell) from getting a hole.
static func hole_floor(feet: Vector3, margin: float) -> float:
	return feet.y + margin


## CPU mirror of the occluder shader's cut for a fragment at view-space position `v` and world height `world_y`:
## 1 inside a hole's inner radius (1 - edge), easing to 0 at its rim, 0 outside every hole, behind its depth or
## below its floor (`floors[i]`, hole_floor; holes without one have no floor). The shader multiplies it by the
## mesh's fade and the strength, and discards the fragment when that exceeds the dither threshold.
static func hole_cut(v: Vector3, holes: PackedVector4Array, edge: float, world_y: float = INF,
		floors: PackedFloat32Array = PackedFloat32Array()) -> float:
	var cut := 0.0
	for i in holes.size():
		var h := holes[i]
		if -v.z > h.w or h.z <= 0.0 or (i < floors.size() and world_y < floors[i]):
			continue
		var d := Vector2(v.x - h.x, v.y - h.y).length() / h.z
		cut = maxf(cut, 1.0 - smoothstep(1.0 - edge, 1.0, d))
	return cut


## Moves a fade value toward `goal` at full range per `fade_s` seconds.
static func fade_step(current: float, goal: float, delta: float, fade_s: float) -> float:
	return move_toward(current, goal, delta / maxf(fade_s, 0.001))


## Ray (origin, dir) against the axis-aligned ellipsoid (center, radii), only in front of the origin. The round test
## of a tree canopy when no triangles are available.
static func ray_hits_ellipsoid(origin: Vector3, dir: Vector3, center: Vector3, radii: Vector3) -> bool:
	if radii.x <= 0.0 or radii.y <= 0.0 or radii.z <= 0.0:
		return false
	var o := (origin - center) / radii
	var d := dir / radii
	var a := d.dot(d)
	var b := 2.0 * o.dot(d)
	var c := o.dot(o) - 1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return false
	var t_far := (-b + sqrt(disc)) / (2.0 * a)
	return t_far > 0.0
