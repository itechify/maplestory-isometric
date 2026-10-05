class_name MinimapProjection
extends RefCounted
## The minimap's projection (pure, no scene tree): world points onto the gameplay camera's own image plane, so the
## minimap is a scaled-down orthographic view of what the player sees. A world point p maps to
##
##   (u, v) = (p . right, -(p . up))      minimap metres: u grows to the right, v grows downwards
##
## where right and up are the camera basis' x and y columns (a Godot camera looks along -z). Ground further from the
## camera and raised tiers sit higher on the minimap, as in the game view, and W (camera forward on the ground) is up.
## The orthographic camera's own unproject_position differs from this by one uniform scale and an offset only
## (test_ui_minimap_projection).
##
## The basis comes from the live camera rig when there is one (CameraRig.view_basis), else from the map's sidecar
## (cameras.gameplay.xform, identical on all 25 maps and equal to camera.json's default pitch and yaw).

var right: Vector3 = Vector3.RIGHT
var up: Vector3 = Vector3.UP
## The camera's view direction (-z): larger p . forward is further from the camera.
var forward: Vector3 = Vector3.FORWARD


## The projection of a camera basis (orthonormalized).
static func from_basis(b: Basis) -> MinimapProjection:
	var p := MinimapProjection.new()
	var o := b.orthonormalized()
	p.right = o.x
	p.up = o.y
	p.forward = -o.z
	return p


## The projection of a sidecar `xform` (12 floats: basis columns x, y, z, then the origin).
static func from_xform_array(a: Array) -> MinimapProjection:
	return from_basis(CameraMath.basis_from_xform_array(a))


## The projection for a map: `live_basis` (the camera rig's view_basis) unless it is the identity, else the map
## sidecar's cameras.gameplay.xform. Null when neither is known.
static func for_map(def: MapDefinition, live_basis: Basis = Basis.IDENTITY) -> MinimapProjection:
	if not live_basis.is_equal_approx(Basis.IDENTITY):
		return from_basis(live_basis)
	var a := sidecar_xform(def)
	return from_xform_array(a) if a.size() >= 9 else null


## The sidecar's gameplay camera xform of a map ([] when it has none).
static func sidecar_xform(def: MapDefinition) -> Array:
	if def == null:
		return []
	var cams: Variant = def.sidecar.get("cameras", null)
	var gp: Variant = (cams as Dictionary).get("gameplay", null) if cams is Dictionary else null
	var a: Variant = (gp as Dictionary).get("xform", null) if gp is Dictionary else null
	return a if a is Array else []


## World point -> minimap metres (u, v).
func project(p: Vector3) -> Vector2:
	return Vector2(p.dot(right), -p.dot(up))


## A world direction as a minimap direction (normalized; zero when it points along the view).
func project_dir(d: Vector3) -> Vector2:
	var v := Vector2(d.dot(right), -d.dot(up))
	return v.normalized() if v.length_squared() > 1e-10 else Vector2.ZERO


## Depth along the view (larger is further from the camera).
func depth(p: Vector3) -> float:
	return p.dot(forward)


## The minimap-space rectangle holding every projected point (Rect2() for none).
func bounds_of(points: PackedVector3Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		var q := project(p)
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2(lo, hi - lo)


## The transform that fits `bounds` (minimap metres) into a widget of `widget_size` px with `margin` px on every side:
## one uniform scale (at most `max_scale` px per metre), centred. Identity for an empty bounds or widget.
static func fit(bounds: Rect2, widget_size: Vector2, margin: float, max_scale: float = INF) -> Transform2D:
	var avail := widget_size - Vector2(margin, margin) * 2.0
	if (bounds.size.x <= 0.0 and bounds.size.y <= 0.0) or avail.x <= 0.0 or avail.y <= 0.0:
		return Transform2D.IDENTITY
	var sx := avail.x / bounds.size.x if bounds.size.x > 0.0 else INF
	var sy := avail.y / bounds.size.y if bounds.size.y > 0.0 else INF
	var s := minf(minf(sx, sy), max_scale)
	var offset := widget_size * 0.5 - bounds.get_center() * s
	return Transform2D(Vector2(s, 0.0), Vector2(0.0, s), offset)


## The uniform scale of a fit() transform (px per minimap metre).
static func scale_of(xf: Transform2D) -> float:
	return xf.x.length()


## Keeps a point inside `rect`: {"pos" (Vector2), "clamped" (bool), "angle" (radians, the direction from the rect's
## centre to the point; 0 when it was inside)}. A point outside is moved along the line to the centre onto the edge,
## so the clamped marker still points the way the player is.
static func clamp_to_rect(pt: Vector2, rect: Rect2) -> Dictionary:
	if rect.has_point(pt) or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return {"pos": pt, "clamped": false, "angle": 0.0}
	var c := rect.get_center()
	var d := pt - c
	var half := rect.size * 0.5
	var t := 1.0
	if absf(d.x) > 1e-9:
		t = minf(t, half.x / absf(d.x))
	if absf(d.y) > 1e-9:
		t = minf(t, half.y / absf(d.y))
	return {"pos": c + d * t, "clamped": true, "angle": d.angle()}
