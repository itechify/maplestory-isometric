class_name CameraRig
extends Node3D
## The gameplay camera (MAP_ARCHITECTURE.md section 4.11): Iteration One's fixed isometric orthographic view
## (pitched 40 degrees down, looking toward Godot +X -Z), following the player with a dead zone and smoothing,
## clamped to the current map's bounds with an overscan, never bobbing on jumps.
##
##   rig.set_target(player)                                 # follows player.follow_anchor() (ground height)
##   rig.configure_from_sidecar(sidecar.cameras.gameplay)   # orientation + per-map ortho size
##   rig.set_bounds(def.camera_bounds, def.ortho_size, 0.35)   # MapSession on every map change (blend for gates);
##                                                          # def.ortho_size is the map's base frame WIDTH
##   rig.snap()                                              # warps: jump straight to the player
##
## The camera sits `distance_m` behind its focus along the view axis, behind all terrain, so the near plane never
## cuts geometry. Trees, buildings and tall props between the camera and the player or a nearby monster dither out
## around them (OcclusionFader child). While anything hides part of the player (a faded occluder, or terrain on a
## physics ray toward the camera) the rig turns on the player's see-through outline (PlayerVisual.set_see_through).
## Numbers live in data/misostory/camera.json; `map_overrides` there can replace one map's view size.

## The node followed: uses its follow_anchor() when it has one (PlayerController), else its position.
@export var target_path: NodePath
## Update in _physics_process (after the player, so both move on the same tick) unless physics interpolation is
## enabled, in which case _process follows the interpolated target.
@export var follow_in_physics: bool = true
## Read the aspect from the viewport every update (tests turn it off and set `aspect`).
@export var auto_aspect: bool = true

var camera: Camera3D = null
var fader: OcclusionFader = null
var target: Node3D = null
## camera.json (data/misostory) as loaded.
var config: Dictionary = {}
## Current view orientation and its ground axes.
var view_basis: Basis = Basis.IDENTITY
var ground_right: Vector3 = Vector3(1, 0, 1).normalized()
var ground_forward: Vector3 = Vector3(1, 0, -1).normalized()
## Current orthographic KEEP_HEIGHT size (meters of view height).
var ortho_size: float = 15.0
## Viewport aspect used for the clamp (refreshed every update; tests set it directly).
var aspect: float = 16.0 / 9.0

var _center: Vector2 = Vector2.ZERO
var _height: float = 0.0
var _has_bounds: bool = false
var _bounds_rect: Rect2 = Rect2()
var _bounds_points: PackedVector2Array = PackedVector2Array()
var _blend_t: float = 1.0
var _blend_len: float = 0.0
var _blend_from_center: Vector2 = Vector2.ZERO
var _size_from: float = 15.0
var _size_to: float = 15.0
var _initialized: bool = false
var _size_configured: bool = false
var _occluded: bool = false
var _monster_query: PhysicsShapeQueryParameters3D = null
var _terrain_query: PhysicsRayQueryParameters3D = null


func _init() -> void:
	process_physics_priority = 100


func _ready() -> void:
	if config.is_empty():
		config = _load_config()
	camera = get_node_or_null(^"Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = float(config.get("near_m", 1.0))
	camera.far = float(config.get("far_m", 1000.0))
	fader = get_node_or_null(^"OcclusionFader") as OcclusionFader
	if fader == null:
		fader = OcclusionFader.new()
		fader.name = "OcclusionFader"
		add_child(fader)
	fader.configure(config)
	if view_basis == Basis.IDENTITY:
		set_view_basis(CameraMath.basis_from_angles(float(config.get("default_pitch_down_deg", 40.0)), float(config.get("default_yaw_deg", -45.0))))
	if not _size_configured:
		_set_size_now(float(config.get("default_ortho_size_m", 15.0)))
	if target == null and not target_path.is_empty():
		set_target(get_node_or_null(target_path) as Node3D)
	camera.make_current()


func _physics_process(delta: float) -> void:
	if follow_in_physics and not _interpolated():
		update_camera(delta)


func _process(delta: float) -> void:
	if not follow_in_physics or _interpolated():
		update_camera(delta)


func _interpolated() -> bool:
	return is_inside_tree() and get_tree().is_physics_interpolation_enabled()


static func _load_config() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://data/misostory/camera.json")
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	return parsed if parsed is Dictionary else {}


# =================================================================================================================
# Public API
# =================================================================================================================

## Follows `node` (a PlayerController or any Node3D) and gives it this view's ground axes for its input.
func set_target(node: Node3D) -> void:
	target = node
	_push_view_axes()
	if target != null:
		snap()


## Orientation and per-map framing from a sidecar `cameras.gameplay` entry: basis from `xform`, ortho size =
## godot_size_keep_height x camera.json ortho_size_scale x `map_scale` (the map's adaptation
## camera.ortho_size_scale), clamped to camera.json's min/max.
func configure_from_sidecar(gameplay_camera: Dictionary, map_scale: float = 1.0, blend_s: float = 0.0) -> void:
	if gameplay_camera.get("xform") is Array:
		set_view_basis(CameraMath.basis_from_xform_array(gameplay_camera["xform"]))
	if gameplay_camera.has("godot_size_keep_height"):
		set_ortho_size(sidecar_ortho_size(float(gameplay_camera["godot_size_keep_height"]), map_scale), blend_s)


## The ortho size this rig uses for a sidecar KEEP_HEIGHT size (camera.json scale and clamp applied).
func sidecar_ortho_size(keep_height: float, map_scale: float = 1.0) -> float:
	if config.is_empty():
		config = _load_config()
	return CameraMath.ortho_size(keep_height, float(config.get("ortho_size_scale", 1.0)), map_scale,
		float(config.get("min_ortho_size_m", 0.0)), float(config.get("max_ortho_size_m", INF)))


## The view size for a map's base frame WIDTH (MapDefinition.ortho_size: sidecar godot_size_keep_width x the map's
## camera.ortho_size_scale, Camera3D.KEEP_WIDTH): converted to KEEP_HEIGHT with the sidecar reference aspect,
## then camera.json's scale and clamp, exactly like configure_from_sidecar().
func view_size_for_frame_width(frame_width: float) -> float:
	if config.is_empty():
		config = _load_config()
	return sidecar_ortho_size(frame_width / maxf(float(config.get("sidecar_reference_aspect", 16.0 / 9.0)), 0.01))


## Sets the fixed view orientation.
func set_view_basis(b: Basis) -> void:
	view_basis = b.orthonormalized()
	var axes := CameraMath.ground_axes(view_basis)
	ground_right = axes[0]
	ground_forward = axes[1]
	_push_view_axes()
	if camera != null:
		_apply_transform()


## Sets the orthographic size (view height in meters), blended over blend_s.
func set_ortho_size(size: float, blend_s: float = 0.0) -> void:
	if size <= 0.0:
		return
	if blend_s <= 0.0 or not _initialized:
		_set_size_now(size)
		return
	_size_from = ortho_size
	_size_to = size
	_start_blend(blend_s)


## The camera bounds of the current map (MAP_ARCHITECTURE section 4.11): a world x/z polygon
## (PackedVector2Array or Array of [x, z]), a Rect2 in x/z, or an AABB; empty clears them. frame_width > 0 also
## sets the view size: it is the map's base frame WIDTH as MapSession passes it (MapDefinition.ortho_size,
## KEEP_WIDTH semantics), converted by view_size_for_frame_width(), unless camera.json `map_overrides` gives the
## current MapSession map its own size (map_view_size). blend_s > 0 blends from the current framing (gate
## commits); 0 cuts (warps then call snap()).
func set_bounds(bounds: Variant, frame_width: float = -1.0, blend_s: float = 0.0) -> void:
	var size := view_size_for_frame_width(frame_width) if frame_width > 0.0 else -1.0
	if frame_width > 0.0:
		var forced := map_view_size(session_map_id())
		if forced > 0.0:
			size = forced
	_bounds_points = CameraMath.bounds_points(bounds)
	_has_bounds = not _bounds_points.is_empty()
	_recompute_bounds_rect()
	if size > 0.0:
		_size_from = ortho_size
		_size_to = size
		# Before the first snap there is nothing to blend from: cut (snap() would otherwise drop the new size).
		if blend_s <= 0.0 or not _initialized:
			_set_size_now(size)
	if blend_s > 0.0 and _initialized:
		if size <= 0.0:
			_size_from = ortho_size
			_size_to = ortho_size
		_start_blend(blend_s)


func clear_bounds() -> void:
	set_bounds(PackedVector2Array())


## camera.json `map_overrides[map_id].ortho_size_m` (KEEP_HEIGHT view size, clamped to min/max), or -1 when the
## map has none.
func map_view_size(map_id: String) -> float:
	if config.is_empty():
		config = _load_config()
	var all: Variant = config.get("map_overrides", {})
	if map_id == "" or not (all is Dictionary) or not ((all as Dictionary).get(map_id) is Dictionary):
		return -1.0
	var size := float((all[map_id] as Dictionary).get("ortho_size_m", -1.0))
	if size <= 0.0:
		return -1.0
	return clampf(size, float(config.get("min_ortho_size_m", 0.0)), float(config.get("max_ortho_size_m", INF)))


## The current map when this rig is MapSession's camera, else "" (tests, sandboxes, previews).
func session_map_id() -> String:
	if not is_inside_tree():
		return ""
	var s := get_node_or_null(^"/root/MapSession")
	if s == null or s.get("camera") != self:
		return ""
	return String(s.get("current_map"))


## True while something hides part of the player: a faded occluder over its body or terrain on a ray toward the
## camera (the see-through outline is on).
func player_occluded() -> bool:
	return _occluded


## Jumps straight to the target (no smoothing, no blend): warps, respawns, loads.
func snap() -> void:
	_blend_t = 1.0
	_set_size_now(_size_to if _initialized else ortho_size)
	if target != null and is_instance_valid(target):
		var a := _anchor()
		_center = _clamped(CameraMath.to_plane(a, ground_right, ground_forward))
		_height = a.y
	_initialized = true
	if camera != null:
		_apply_transform()
		if camera.is_inside_tree():
			camera.reset_physics_interpolation()


## Advances the follow by `delta` seconds (called from _physics_process/_process; tests call it directly).
func update_camera(delta: float) -> void:
	if target != null and not is_instance_valid(target):
		target = null  # the followed node was freed (scene change): hold the current framing
	if auto_aspect and camera != null and is_inside_tree():
		var vs := get_viewport().get_visible_rect().size
		if vs.y > 0.0:
			aspect = vs.x / vs.y
	if not _initialized:
		snap()
	if _blend_t < 1.0:
		_blend_t = minf(1.0, _blend_t + delta / maxf(_blend_len, 0.0001))
		ortho_size = lerpf(_size_from, _size_to, _ease(_blend_t))
	if target != null:
		var a := _anchor()
		var t := CameraMath.to_plane(a, ground_right, ground_forward)
		var half_zone := view_half_extents() * float(config.get("dead_zone_fraction", 0.15))
		var desired := _clamped(CameraMath.dead_zone_follow(_center, t, half_zone))
		var k := CameraMath.smoothing(float(config.get("follow_rate_hz", 7.0)), delta)
		var follow := _center.lerp(desired, k)
		if _blend_t < 1.0:
			follow = _blend_from_center.lerp(follow, _ease(_blend_t))
		_center = follow
		_height = lerpf(_height, a.y, CameraMath.smoothing(float(config.get("height_follow_rate_hz", 4.0)), delta))
	if camera != null:
		_apply_transform()
		if target != null:
			update_occlusion(delta)


## Fades the occluders for this frame's camera (the player and the monsters near it) and shows the player's
## see-through outline while anything hides the player. Called by update_camera().
func update_occlusion(delta: float) -> void:
	if target == null or not is_instance_valid(target) or camera == null:
		return
	var feet := target.global_position
	if fader != null:
		# The body height the movement model gives the player (PlayerController.model.body_height).
		var mm: Variant = target.get("model")
		if mm is MovementModel:
			fader.player_height = (mm as MovementModel).body_height
		fader.update(camera.global_transform, feet, nearby_monsters(feet), delta)
	_occluded = (fader != null and fader.player_covered) or terrain_hides(feet)
	var vis := target.get_node_or_null(^"Visual")
	if vis != null and vis.has_method(&"set_see_through"):
		vis.call(&"set_see_through", _occluded)


## Live monsters whose body is within camera.json occluder_monster_radius_m of the player's chest (a physics
## query on WorldLayers.MONSTERS), nearest first: [{feet, height, half_width, node}]. Height and width come from the
## monster's def.sprite_size_m when it has one.
func nearby_monsters(feet: Vector3) -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	var space := get_world_3d().direct_space_state
	if space == null:
		return out
	if _monster_query == null:
		_monster_query = PhysicsShapeQueryParameters3D.new()
		_monster_query.collide_with_areas = false
		_monster_query.collide_with_bodies = true
		_monster_query.collision_mask = WorldLayers.MONSTERS
		_monster_query.shape = SphereShape3D.new()
	(_monster_query.shape as SphereShape3D).radius = float(config.get("occluder_monster_radius_m", 8.0))
	_monster_query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 0.8)
	var seen: Dictionary = {}
	for hit in space.intersect_shape(_monster_query, 32):
		var body := hit.get("collider") as Node3D
		if body == null or seen.has(body) or body == target:
			continue
		seen[body] = true
		if body.has_method(&"is_alive") and not bool(body.call(&"is_alive")):
			continue
		var size := Vector2(float(config.get("occluder_monster_default_width_m", 0.8)), float(config.get("occluder_monster_default_height_m", 1.0)))
		var def: Variant = body.get("def")
		if def is Object and (def as Object).get("sprite_size_m") is Vector2:
			var s: Vector2 = (def as Object).get("sprite_size_m")
			if s.x > 0.0 and s.y > 0.0:
				size = s
		out.append({"feet": body.global_position, "height": size.y, "half_width": size.x * 0.5, "node": body,
			"d": body.global_position.distance_squared_to(feet)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.d) < float(b.d))
	return out


## True if world collision (walkable, blocking or scenery: cliffs, walls, hulls) crosses a ray from the player's body
## toward the camera at any of camera.json silhouette_terrain_heights_m.
func terrain_hides(feet: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	if _terrain_query == null:
		_terrain_query = PhysicsRayQueryParameters3D.new()
		_terrain_query.collide_with_areas = false
		_terrain_query.collision_mask = WorldLayers.WALKABLE | WorldLayers.BLOCKING | WorldLayers.SCENERY
		_terrain_query.hit_back_faces = true
	if target is CollisionObject3D:
		_terrain_query.exclude = [(target as CollisionObject3D).get_rid()]
	var back := view_basis.z
	var reach := float(config.get("silhouette_terrain_ray_m", 60.0))
	for h in config.get("silhouette_terrain_heights_m", [0.5, 0.95, 1.4]):
		var p := feet + Vector3.UP * float(h)
		_terrain_query.from = p
		_terrain_query.to = p + back * reach
		if not space.intersect_ray(_terrain_query).is_empty():
			return true
	return false


## Ground half extents (r, f) of the current view.
func view_half_extents() -> Vector2:
	return CameraMath.view_half_extents(ortho_size, aspect, CameraMath.pitch_down(view_basis))


## The ground point at the centre of the view.
func focus_point() -> Vector3:
	return CameraMath.from_plane(_center, _height, ground_right, ground_forward)


## Plane-coordinate rectangle of the current bounds (empty Rect2 when unbounded).
func bounds_rect() -> Rect2:
	return _bounds_rect if _has_bounds else Rect2()


## Hands the occlusion fader the meshes under `root` (call after a map chunk is added).
func scan_occluders(root: Node) -> void:
	if fader != null:
		fader.scan(root)


# =================================================================================================================
# Internals
# =================================================================================================================

func _anchor() -> Vector3:
	if target == null or not is_instance_valid(target):
		return focus_point()
	if target.has_method(&"follow_anchor"):
		return target.call(&"follow_anchor")
	return target.global_position


func _clamped(rf: Vector2) -> Vector2:
	if not _has_bounds:
		return rf
	return CameraMath.clamp_focus(rf, _bounds_rect, view_half_extents(), float(config.get("overscan_m", 6.0)))


func _recompute_bounds_rect() -> void:
	_bounds_rect = CameraMath.bounds_rect(_bounds_points, ground_right, ground_forward) if _has_bounds else Rect2()


func _start_blend(blend_s: float) -> void:
	_blend_from_center = _center
	_blend_len = blend_s
	_blend_t = 0.0


func _set_size_now(size: float) -> void:
	_size_configured = true
	ortho_size = size
	_size_from = size
	_size_to = size
	if camera != null:
		camera.size = size


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _apply_transform() -> void:
	camera.size = ortho_size
	var focus := focus_point()
	var fwd := -view_basis.z
	camera.global_transform = Transform3D(view_basis, focus - fwd * float(config.get("distance_m", 150.0)))


func _push_view_axes() -> void:
	if target != null and is_instance_valid(target) and target.has_method(&"set_view_axes"):
		target.call(&"set_view_axes", ground_right, ground_forward)
	if _has_bounds:
		_recompute_bounds_rect()
