class_name CameraMath
extends RefCounted
## Pure math of the gameplay camera (MAP_ARCHITECTURE.md section 4.11). No scene tree.
##
## The camera's "plane coordinates" are a 2D frame on the ground: r along the camera's horizontal right axis and
## f along its ground-projected forward axis (both unit, horizontal). An orthographic view of height `size` (Godot
## KEEP_HEIGHT) at pitch p covers size x aspect along r and size / sin(p) along f on the ground plane through its
## focus. Bounds polygons are projected onto (r, f) to an AABB; the focus is clamped so the view stays inside
## that AABB plus an overscan, and centred on any axis where the expanded AABB is narrower than the view.


## Horizontal unit right and forward axes of a camera basis (Godot cameras look along -Z).
static func ground_axes(basis: Basis) -> Array[Vector3]:
	var right := Vector3(basis.x.x, 0.0, basis.x.z)
	var fwd := -basis.z
	var forward := Vector3(fwd.x, 0.0, fwd.z)
	if right.length_squared() < 1e-8:
		right = forward.cross(Vector3.UP)
	if forward.length_squared() < 1e-8:
		forward = Vector3.UP.cross(right)
	return [right.normalized(), forward.normalized()]


## Pitch below the horizon of a camera basis, in radians (Iteration One: 40 degrees).
static func pitch_down(basis: Basis) -> float:
	var fwd := (-basis.z).normalized()
	return asin(clampf(-fwd.y, -1.0, 1.0))


## A camera basis looking down at `pitch_down_deg` with yaw `yaw_deg` (Godot rotation.y).
static func basis_from_angles(pitch_down_deg: float, yaw_deg: float) -> Basis:
	return Basis.from_euler(Vector3(-deg_to_rad(pitch_down_deg), deg_to_rad(yaw_deg), 0.0), EULER_ORDER_YXZ)


## A Basis from a sidecar `xform` (12 floats: basis columns x, y, z, then the origin).
static func basis_from_xform_array(a: Array) -> Basis:
	if a.size() < 9:
		return Basis.IDENTITY
	return Basis(Vector3(float(a[0]), float(a[1]), float(a[2])), Vector3(float(a[3]), float(a[4]), float(a[5])),
		Vector3(float(a[6]), float(a[7]), float(a[8]))).orthonormalized()


## World point -> plane coordinates (r, f).
static func to_plane(p: Vector3, right: Vector3, forward: Vector3) -> Vector2:
	return Vector2(p.dot(right), p.dot(forward))


## Plane coordinates (r, f) at height y -> world point.
static func from_plane(rf: Vector2, y: float, right: Vector3, forward: Vector3) -> Vector3:
	var v := right * rf.x + forward * rf.y
	return Vector3(v.x, y, v.z)


## Half extents (r, f) of the ground area an orthographic KEEP_HEIGHT view of `size` covers.
static func view_half_extents(size: float, aspect: float, pitch_down_rad: float) -> Vector2:
	var s := maxf(sin(pitch_down_rad), 0.05)
	return Vector2(size * aspect * 0.5, size * 0.5 / s)


## Normalizes the accepted bounds forms to a world x/z polygon: PackedVector2Array (x, z), Array of Vector2 or
## [x, z] pairs, Rect2 (x, z), or AABB (its x/z extent). Anything else (or fewer than 1 point) -> empty.
static func bounds_points(bounds: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if bounds is PackedVector2Array:
		out = bounds
	elif bounds is Rect2:
		var r: Rect2 = bounds
		out = PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)])
	elif bounds is AABB:
		var b: AABB = bounds
		var p0 := Vector2(b.position.x, b.position.z)
		var p1 := Vector2(b.end.x, b.end.z)
		out = PackedVector2Array([p0, Vector2(p1.x, p0.y), p1, Vector2(p0.x, p1.y)])
	elif bounds is Array:
		for e in bounds:
			if e is Vector2:
				out.append(e)
			elif e is Vector3:
				out.append(Vector2(e.x, e.z))
			elif e is Array and (e as Array).size() >= 2:
				out.append(Vector2(float(e[0]), float(e[1])))
	return out


## The (r, f) AABB of a world x/z polygon.
static func bounds_rect(points_xz: PackedVector2Array, right: Vector3, forward: Vector3) -> Rect2:
	if points_xz.is_empty():
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points_xz:
		var rf := to_plane(Vector3(p.x, 0.0, p.y), right, forward)
		lo = lo.min(rf)
		hi = hi.max(rf)
	return Rect2(lo, hi - lo)


## Clamps a focus (plane coords) so the view (half extents) stays inside `bounds` grown by `overscan`. On an axis
## where the grown bounds are smaller than the view, the focus is centred on the bounds.
static func clamp_focus(focus: Vector2, bounds: Rect2, half: Vector2, overscan: float) -> Vector2:
	var out := focus
	for axis in 2:
		var lo := bounds.position[axis] - overscan + half[axis]
		var hi := bounds.end[axis] + overscan - half[axis]
		if lo > hi:
			out[axis] = bounds.position[axis] + bounds.size[axis] * 0.5
		else:
			out[axis] = clampf(focus[axis], lo, hi)
	return out


## Dead-zone follow: the smallest move of `center` that brings `target` inside center +- half_zone.
static func dead_zone_follow(center: Vector2, target: Vector2, half_zone: Vector2) -> Vector2:
	var out := center
	for axis in 2:
		var d := target[axis] - center[axis]
		if d > half_zone[axis]:
			out[axis] = target[axis] - half_zone[axis]
		elif d < -half_zone[axis]:
			out[axis] = target[axis] + half_zone[axis]
	return out


## Frame-rate independent exponential approach: the fraction of the remaining gap closed in `delta` at `rate_hz`.
static func smoothing(rate_hz: float, delta: float) -> float:
	if rate_hz <= 0.0:
		return 1.0
	return 1.0 - exp(-rate_hz * delta)


## Per-map orthographic size: the sidecar's KEEP_HEIGHT size x the global scale x a per-map scale, clamped.
static func ortho_size(sidecar_keep_height: float, global_scale: float, map_scale: float, min_size: float, max_size: float) -> float:
	return clampf(sidecar_keep_height * global_scale * map_scale, min_size, max_size)
