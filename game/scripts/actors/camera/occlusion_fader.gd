class_name OcclusionFader
extends Node
## Dithers out the trees, canopies, buildings and tall props that stand between the camera and the player or a
## monster near the player (MAP_ARCHITECTURE.md section 4.11 "Occlusion", milestone M3; the brief's camera review:
## "Can I see the player? Can I see nearby enemies?"). Terrain never fades.
##
## scan(root) collects every MeshInstance3D whose exported glTF extras pass camera.json `occluders`
## (OcclusionMath.is_occluder, with the height of its whole instance) and groups the parts of one Blender instance (a
## tree's trunk and canopy) into one fading unit. Each update(cam_xform, feet, monsters, delta):
##   1. builds the targets: the player's whole body (5 heights x 3 columns), a disc of points around the player's
##      chest in the screen plane (`occluder_hole_radius_m`), and the body of each nearby monster;
##   2. selects every unit with a mesh nearer the camera than one of those points along the view: a prefilter on
##      the mesh's view-frame box, then an exact segment test against its triangles (a TriangleMesh BVH per mesh
##      resource, shared by every instance of the mesh);
##   3. fades the selected units in and the others out over `occluder_fade_s`. A faded mesh renders with the
##      OccluderDither stand-ins of its materials, which screen-door the mesh out inside the holes around the
##      player and the monsters (nearer than their depth, above their feet); meshes whose materials cannot be
##      converted fade with GeometryInstance3D.transparency instead. When a mesh is clear again its own materials
##      come back.
## `player_covered` is true while a selected unit hides part of the player's body (CameraRig shows the player's
## see-through outline then). Architecture meshes whose box holds a target's chest (the room it stands in) never
## fade for that target.

## camera.json `occluders` (OcclusionMath.is_occluder, is_room).
var rules: Dictionary = {
	"categories": ["Trees"], "groups": ["Architecture"], "tall_categories": [], "tall_groups": [],
	"tall_min_height_m": 1.8, "never": ["Terrain"], "never_flags": ["walkable", "climbable"], "room_groups": ["Architecture"],
	"room_min_size_m": 8.0,
}
## Meshes whose ground footprint is within this distance of the player are tested.
var radius: float = 22.0
## Screen radius (meters on the view plane) around the player's chest inside which occluders in front dither out.
var hole_radius: float = 2.4
## Hole radius around a monster beyond half its size.
var monster_hole_margin: float = 0.5
## A hole cuts fragments up to this far behind its target's centre (depth along the view).
var hole_depth_margin: float = 0.8
## A hole cuts nothing lower than its target's feet + this (OcclusionMath.hole_floor).
var hole_floor_margin: float = 0.1
## GeometryInstance3D.transparency of a faded mesh whose materials cannot be dithered.
var faded_transparency: float = 0.85
var fade_time: float = 0.2
## Body of the player (meters): height and half width on screen.
var player_height: float = 1.5
var player_half_width: float = 0.35
var dither: OccluderDither = OccluderDither.new()

## True while a selected occluder hides part of the player's body (updated by update()).
var player_covered: bool = false
## The holes of the last update (view space, OcclusionMath.hole) and their floors (world y, OcclusionMath.hole_floor).
var holes: PackedVector4Array = PackedVector4Array()
var hole_floors: PackedFloat32Array = PackedFloat32Array()

const _CELL := 8.0
const MODE_DITHER := 0
const MODE_ALPHA := 1

var _meshes: Array[MeshInstance3D] = []
var _aabbs: Array[AABB] = []
var _extras: Array[Dictionary] = []
var _round: Array[bool] = []
var _unit_of: PackedInt32Array = PackedInt32Array()
## unit id -> member mesh indices (Arrays: reference types, appended in place)
var _units: Array[Array] = []
var _unit_ids: Dictionary = {}
## Mesh instance id -> index (a second scan of the same chunk adds nothing).
var _scanned: Dictionary = {}
## Vector2i ground cell -> Array of mesh indices whose footprint touches it.
var _grid: Dictionary = {}
var _stamp: PackedInt32Array = PackedInt32Array()
var _tick: int = 0
## View-frame boxes for the basis _vbox_basis.
var _vboxes: Array[AABB] = []
var _vbox_basis: Basis = Basis()
## Mesh resource id -> TriangleMesh (mesh-local).
var _tri_cache: Dictionary = {}
## Mesh instance id -> {fade: float, mode: int, prev: Array (surface overrides before the fade)}.
var _active: Dictionary = {}
## Unit ids selected by the last update.
var _selected: Dictionary = {}


func configure(cfg: Dictionary) -> void:
	if cfg.get("occluders") is Dictionary:
		rules = cfg["occluders"]
	radius = float(cfg.get("occluder_radius_m", radius))
	player_half_width = float(cfg.get("occluder_player_half_width_m", player_half_width))
	hole_radius = float(cfg.get("occluder_hole_radius_m", hole_radius))
	monster_hole_margin = float(cfg.get("occluder_monster_hole_margin_m", monster_hole_margin))
	hole_depth_margin = float(cfg.get("occluder_hole_depth_margin_m", hole_depth_margin))
	hole_floor_margin = float(cfg.get("occluder_hole_floor_margin_m", hole_floor_margin))
	faded_transparency = float(cfg.get("occluder_transparency", faded_transparency))
	fade_time = float(cfg.get("occluder_fade_s", fade_time))
	dither.strength = float(cfg.get("occluder_dither_strength", dither.strength))
	dither.core_strength = float(cfg.get("occluder_hole_core_strength", dither.core_strength))
	dither.edge = float(cfg.get("occluder_hole_edge", dither.edge))


## Adds the occluder meshes under `root` (call once per added chunk; boxes are cached, so static meshes only).
## The "tall" rules (OcclusionMath.is_occluder) read the height of the whole Blender instance (every part of the
## mesh's unit under `root`), not of the part: a giant mushroom's 1.5 m cap on its 2 m stem, or a lily of the
## valley's bells on its stalk, fade with the instance instead of staying solid while the stem dithers.
func scan(root: Node) -> void:
	if root == null:
		return
	var found: Array = []  # [mesh, world box, extras, unit key]
	var unit_boxes: Dictionary = {}  # unit key -> union of its parts' world boxes
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.has_meta(&"extras") or _scanned.has(mi.get_instance_id()):
			continue
		var extras: Variant = mi.get_meta(&"extras")
		if not (extras is Dictionary):
			continue
		var box := mi.global_transform * mi.get_aabb()
		var key := _unit_key_of(mi)
		unit_boxes[key] = (unit_boxes[key] as AABB).merge(box) if unit_boxes.has(key) else box
		found.append([mi, box, extras, key])
	for f in found:
		if OcclusionMath.is_occluder(f[2], (unit_boxes[f[3]] as AABB).size.y, rules):
			_add(f[0], f[1], f[2], f[3])
	_vboxes.clear()


static func _unit_key_of(mi: MeshInstance3D) -> String:
	var parent := mi.get_parent()
	return OcclusionMath.unit_key(String(mi.name), parent.get_instance_id() if parent != null else 0)


func _add(mi: MeshInstance3D, box: AABB, extras: Dictionary, key: String) -> void:
	var idx := _meshes.size()
	_scanned[mi.get_instance_id()] = idx
	_meshes.append(mi)
	_aabbs.append(box)
	_extras.append(extras)
	_round.append(String(extras.get("category", "")) == "Trees")
	_stamp.append(0)
	var unit: int
	if _unit_ids.has(key):
		unit = _unit_ids[key]
	else:
		unit = _units.size()
		_unit_ids[key] = unit
		_units.append([])
	_unit_of.append(unit)
	_units[unit].append(idx)
	var c0 := _cell(box.position.x, box.position.z)
	var c1 := _cell(box.end.x, box.end.z)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var k := Vector2i(cx, cz)
			if not _grid.has(k):
				_grid[k] = []
			(_grid[k] as Array).append(idx)


static func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / _CELL), floori(z / _CELL))


## Forgets every scanned mesh (map unload) and gives the faded ones their own materials back.
func clear() -> void:
	for id in _active.keys():
		var mi := instance_from_id(id) as MeshInstance3D
		if mi != null:
			_restore(mi, _active[id])
	_active.clear()
	_selected.clear()
	_meshes.clear()
	_aabbs.clear()
	_extras.clear()
	_round.clear()
	_unit_of.clear()
	_units.clear()
	_unit_ids.clear()
	_scanned.clear()
	_grid.clear()
	_stamp.clear()
	_vboxes.clear()
	_tri_cache.clear()
	player_covered = false


func candidate_count() -> int:
	return _meshes.size()


## True if `mi` was scanned as an occluder candidate.
func is_candidate(mi: MeshInstance3D) -> bool:
	return mi != null and _scanned.has(mi.get_instance_id())


## Number of fading units (a tree's trunk and canopy count once) scanned.
func unit_count() -> int:
	return _units.size()


## Number of meshes currently faded or fading.
func active_count() -> int:
	return _active.size()


## Number of units the last update selected.
func selected_count() -> int:
	return _selected.size()


## Current fade (0 solid .. 1 fully faded) of a scanned mesh.
func fade_of(mi: MeshInstance3D) -> float:
	if mi == null:
		return 0.0
	var st: Variant = _active.get(mi.get_instance_id(), null)
	return float((st as Dictionary).fade) if st is Dictionary else 0.0


## True if `mi` is faded with the dither stand-ins (false: not faded, or faded by transparency).
func is_dithered(mi: MeshInstance3D) -> bool:
	var st: Variant = _active.get(mi.get_instance_id(), null) if mi != null else null
	return st is Dictionary and int((st as Dictionary).mode) == MODE_DITHER


## Re-selects and fades for the camera at `cam_xform`, the player's feet at `feet` and `monsters` near the player
## (each {feet: Vector3, height: float, half_width: float}; nearest first, at most OccluderDither.MAX_HOLES - 1
## are used).
func update(cam_xform: Transform3D, feet: Vector3, monsters: Array, delta: float) -> void:
	var cam := cam_xform.basis.orthonormalized()
	_ensure_view_boxes(cam)
	var targets := _targets(cam, cam_xform, feet, monsters)
	_select(cam, feet, targets)
	_fade(delta)
	dither.update(holes, -cam.z, hole_floors)


## Targets: [{chest, points (world), views, body (bool: the player's own body)}]; also fills `holes`.
func _targets(cam: Basis, cam_xform: Transform3D, feet: Vector3, monsters: Array) -> Array:
	var out: Array = []
	holes = PackedVector4Array()
	hole_floors = PackedFloat32Array()
	var chest := feet + Vector3.UP * (player_height * 0.55)
	var body := OcclusionMath.body_samples(feet, player_height, player_half_width, cam)
	out.append({"chest": chest, "points": body, "body": true})
	out.append({"chest": chest, "points": OcclusionMath.disc_samples(chest, hole_radius, cam), "body": false})
	holes.append(OcclusionMath.hole(chest, hole_radius, hole_depth_margin, cam_xform))
	hole_floors.append(OcclusionMath.hole_floor(feet, hole_floor_margin))
	var n := 0
	for m in monsters:
		if n >= OccluderDither.MAX_HOLES - 1 or not (m is Dictionary):
			break
		var mf: Vector3 = m.get("feet", Vector3.ZERO)
		var h := maxf(float(m.get("height", 1.0)), 0.1)
		var hw := maxf(float(m.get("half_width", 0.4)), 0.05)
		var mc := mf + Vector3.UP * (h * 0.5)
		out.append({"chest": mc, "points": OcclusionMath.body_samples(mf, h, hw, cam, 3), "body": false})
		holes.append(OcclusionMath.hole(mc, maxf(h * 0.5, hw) + monster_hole_margin, hole_depth_margin, cam_xform))
		hole_floors.append(OcclusionMath.hole_floor(mf, hole_floor_margin))
		n += 1
	for t in out:
		var views := PackedVector3Array()
		for p in (t.points as PackedVector3Array):
			views.append(OcclusionMath.to_view(p, cam))
		t["views"] = views
	return out


func _select(cam: Basis, feet: Vector3, targets: Array) -> void:
	_selected.clear()
	player_covered = false
	var all_views := PackedVector3Array()
	var far := -INF
	for t in targets:
		all_views.append_array(t.views)
	for v in all_views:
		far = maxf(far, v.z)
	var rect := OcclusionMath.screen_rect(all_views)
	var back := cam.z  # toward the camera
	for idx in _nearby(feet):
		var vb := _vboxes[idx]
		if vb.position.z >= far or not rect.intersects(Rect2(vb.position.x, vb.position.y, vb.size.x, vb.size.y), true):
			continue
		var unit := _unit_of[idx]
		var unit_done := _selected.has(unit)
		for t in targets:
			var is_body := bool(t.body)
			if unit_done and (not is_body or player_covered):
				continue
			if OcclusionMath.is_room(_extras[idx], _aabbs[idx], t.chest, rules):
				continue
			var pts: PackedVector3Array = t.points
			var views: PackedVector3Array = t.views
			for i in pts.size():
				if not OcclusionMath.may_cover(vb, views[i]):
					continue
				if _hides(idx, pts[i], back):
					_selected[unit] = true
					unit_done = true
					if is_body:
						player_covered = true
					break


## Indices of scanned meshes whose footprint lies within `radius` of `feet` (ground cells, then the exact box).
func _nearby(feet: Vector3) -> PackedInt32Array:
	_tick += 1
	var out := PackedInt32Array()
	var c0 := _cell(feet.x - radius, feet.z - radius)
	var c1 := _cell(feet.x + radius, feet.z + radius)
	var r2 := radius * radius
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var list: Variant = _grid.get(Vector2i(cx, cz), null)
			if list == null:
				continue
			for idx: int in (list as Array):
				if _stamp[idx] == _tick:
					continue
				_stamp[idx] = _tick
				if not is_instance_valid(_meshes[idx]) or not _meshes[idx].is_visible_in_tree():
					continue
				var b := _aabbs[idx]
				var dx := maxf(maxf(b.position.x - feet.x, feet.x - b.end.x), 0.0)
				var dz := maxf(maxf(b.position.z - feet.z, feet.z - b.end.z), 0.0)
				if dx * dx + dz * dz <= r2:
					out.append(idx)
	return out


## Exact test: does mesh `idx` cross the segment from `p` toward the camera (`back` = the camera's +Z)?
func _hides(idx: int, p: Vector3, back: Vector3) -> bool:
	var mi := _meshes[idx]
	var q := p + back * 300.0
	var tri := _triangles(mi)
	if tri != null:
		var inv := mi.global_transform.affine_inverse()
		return not tri.intersect_segment(inv * p, inv * q).is_empty()
	var box := _aabbs[idx]
	if _round[idx]:
		return OcclusionMath.ray_hits_ellipsoid(p, back, box.get_center(), box.size * 0.5)
	return box.intersects_segment(p, q) != null


func _triangles(mi: MeshInstance3D) -> TriangleMesh:
	var key := mi.mesh.get_instance_id()
	if not _tri_cache.has(key):
		_tri_cache[key] = mi.mesh.generate_triangle_mesh()
	return _tri_cache[key]


func _ensure_view_boxes(cam: Basis) -> void:
	if _vboxes.size() == _meshes.size() and cam.is_equal_approx(_vbox_basis):
		return
	_vbox_basis = cam
	_vboxes.resize(_meshes.size())
	for i in _meshes.size():
		_vboxes[i] = OcclusionMath.view_box(_aabbs[i], cam)


func _fade(delta: float) -> void:
	for unit in _selected:
		for idx in _units[unit]:
			var mi := _meshes[idx]
			if is_instance_valid(mi) and not _active.has(mi.get_instance_id()):
				_active[mi.get_instance_id()] = _begin(mi, unit)
	var done: Array = []
	for id in _active:
		var mi := instance_from_id(id) as MeshInstance3D
		if mi == null:
			done.append(id)
			continue
		var st: Dictionary = _active[id]
		var goal := 1.0 if _selected.has(int(st.unit)) else 0.0
		st.fade = OcclusionMath.fade_step(float(st.fade), goal, delta, fade_time)
		_apply(mi, st)
		if goal == 0.0 and float(st.fade) <= 0.0:
			_restore(mi, st)
			done.append(id)
	for id in done:
		_active.erase(id)


## Starts fading `mi`: its surfaces get their dither stand-ins (or, if any material cannot be converted, the
## mesh fades with GeometryInstance3D.transparency).
func _begin(mi: MeshInstance3D, unit: int) -> Dictionary:
	var st := {"fade": 0.0, "mode": MODE_ALPHA, "prev": [], "unit": unit}
	if mi.material_override == null:
		var clones: Array = []
		for s in mi.mesh.get_surface_count():
			var c := dither.clone_for(mi.get_active_material(s))
			if c == null:
				clones.clear()
				break
			clones.append(c)
		if not clones.is_empty():
			var prev: Array = []
			for s in clones.size():
				prev.append(mi.get_surface_override_material(s))
				mi.set_surface_override_material(s, clones[s])
			st.mode = MODE_DITHER
			st.prev = prev
	return st


func _apply(mi: MeshInstance3D, st: Dictionary) -> void:
	if int(st.mode) == MODE_DITHER:
		mi.set_instance_shader_parameter(OccluderDither.FADE_PARAM, float(st.fade))
	else:
		mi.transparency = float(st.fade) * faded_transparency


func _restore(mi: MeshInstance3D, st: Dictionary) -> void:
	if int(st.mode) == MODE_DITHER:
		var prev: Array = st.prev
		for s in prev.size():
			mi.set_surface_override_material(s, prev[s])
		mi.set_instance_shader_parameter(OccluderDither.FADE_PARAM, 0.0)
	else:
		mi.transparency = 0.0
