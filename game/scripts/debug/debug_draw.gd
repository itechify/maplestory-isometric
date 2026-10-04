class_name DebugDraw
extends Node3D
## The debug draw layers for the current map (MAP_ARCHITECTURE.md section 4.14): line meshes and labels built from
## what the world actually created, never from a second copy of the data.
##
##   collision   every collision shape under IslandWorld.collision_root that lies in the map's box, coloured by its
##               layer (walkable green, blocking orange, scenery blue); concave shapes from their faces, boxes from
##               their extents, convex hulls from their debug mesh (their AABB when the renderer gives none)
##   spawns      exported spawn areas, every SpawnSlot (alive green / dead red with its respawn time, from the live
##               MapInstanceState), live monster nodes (yellow, with a line back to their slot) and debug spawns
##   portals     trigger boxes, anchors, arrival points with facing, labels "name -> map.portal (name) / link mode,
##               type" (type 1 is hidden; arrival gates are walk-only)
##   npcs        NPC anchors with their talk radius and labels
##   camera      MapDefinition.camera_bounds and the camera rig's live view rectangle
##   mobregion   SpawnSlotPlanner.mob_region (the layout footprint inset)
##   rings       the current map's containment ring (the ContainmentBuilder boxes)
##   safeground  the SafeGround point in use and the map's fall-recovery height (kill_y)
##
## Static layers rebuild when the map changes; spawns, camera and safeground refresh LIVE_REFRESH_S. Lines use an
## unshaded vertex-colour shader pulled slightly toward the camera so they sit on the surfaces they outline; labels
## and markers ignore depth. Colours are debug presentation only.

const LIVE_REFRESH_S := 0.25
const LIVE_LAYERS: PackedStringArray = ["spawns", "camera", "safeground"]
## Hard cap per layer so a huge collision mesh cannot stall the editor.
const MAX_SEGMENTS := 400000
## How far outside the footprint collision is still drawn (m), and above/below the map's height range.
const BOX_MARGIN_M := 1.5
const BOX_BELOW_M := 3.0
const BOX_ABOVE_M := 6.0

const C_WALKABLE := Color(0.25, 1.0, 0.35, 0.8)
const C_BLOCKING := Color(1.0, 0.55, 0.12, 0.9)
const C_SCENERY := Color(0.45, 0.65, 1.0, 0.6)
const C_CONTAINMENT := Color(1.0, 0.92, 0.2, 0.8)
const C_OTHER := Color(0.8, 0.8, 0.8, 0.5)
const C_AREA := Color(0.2, 0.95, 1.0, 0.9)
const C_ALIVE := Color(0.3, 1.0, 0.3, 1.0)
const C_DEAD := Color(1.0, 0.25, 0.25, 1.0)
const C_UNFILLED := Color(0.65, 0.65, 0.7, 0.9)
const C_LIVE := Color(1.0, 0.95, 0.2, 1.0)
const C_DEBUG := Color(1.0, 0.3, 1.0, 1.0)
const C_PORTAL := Color(0.3, 0.85, 1.0, 1.0)
const C_DOOR := Color(1.0, 0.8, 0.3, 1.0)
const C_HIDDEN := Color(0.7, 0.7, 0.7, 0.9)
const C_GATE := Color(0.75, 0.45, 1.0, 1.0)
const C_ARRIVAL := Color(0.4, 1.0, 0.6, 1.0)
const C_NPC := Color(1.0, 0.6, 0.85, 1.0)
const C_CAMERA := Color(1.0, 1.0, 1.0, 0.9)
const C_VIEW := Color(0.6, 0.9, 1.0, 0.9)
const C_MOBREGION := Color(1.0, 0.4, 0.2, 0.95)
const C_SAFE := Color(0.3, 1.0, 0.9, 1.0)
const C_KILL := Color(1.0, 0.2, 0.2, 0.7)

const LINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled%s;
uniform float bias = 0.04;
void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.z += bias;
	POSITION = PROJECTION_MATRIX * v;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
"""

var dbg: DebugTools = null
## layer -> {"root": Node3D, "mesh": MeshInstance3D, "labels": Array[Label3D], "used": int, "segments": int,
##           "map": String, "visible": bool}
var _layers: Dictionary = {}
var _dirty: bool = true
var _live_t: float = 0.0
var _depth_material: ShaderMaterial = null
var _xray_material: ShaderMaterial = null
## shape instance id -> local AABB
var _aabb_cache: Dictionary = {}
var _built_map: String = ""


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bus := dbg.get_bus() if dbg != null else null
	if bus != null and bus.has_signal("map_entered"):
		bus.connect("map_entered", request_rebuild.unbind(2))


func set_layer_visible(layer: String, on: bool) -> void:
	var L := _layer(layer)
	L.visible = on
	(L.root as Node3D).visible = on
	if on:
		_dirty = true


## Rebuilds every visible layer at the next frame (map change, new context).
func request_rebuild() -> void:
	_dirty = true


## Rebuilds every visible layer now (the console's layer commands call this so their report is current).
func rebuild_now() -> void:
	_dirty = false
	_built_map = dbg.current_map() if dbg != null else ""
	for layer in DebugTools.LAYERS:
		var L := _layer(layer)
		if bool(L.visible):
			_build(layer)


## {"segments", "labels", "map"} of a layer's last build.
func layer_stats(layer: String) -> Dictionary:
	var L := _layer(layer)
	return {"segments": int(L.segments), "labels": int(L.used), "map": String(L.map)}


func _process(delta: float) -> void:
	if dbg == null:
		return
	if _dirty or (dbg.current_map() != _built_map):
		rebuild_now()
		return
	_live_t += delta
	if _live_t < LIVE_REFRESH_S:
		return
	_live_t = 0.0
	for layer in LIVE_LAYERS:
		if bool(_layer(layer).visible):
			_build(layer)


# --- layers ---------------------------------------------------------------------------------------------------

func _layer(layer: String) -> Dictionary:
	if _layers.has(layer):
		return _layers[layer]
	var root := Node3D.new()
	root.name = "Layer_" + layer
	root.visible = false
	add_child(root)
	var mi := MeshInstance3D.new()
	mi.name = "Lines"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _material(layer != "collision")
	root.add_child(mi)
	var L := {"root": root, "mesh": mi, "labels": [], "used": 0, "segments": 0, "map": "", "visible": false}
	_layers[layer] = L
	return L


func _build(layer: String) -> void:
	var L := _layer(layer)
	var lines := Lines.new()
	L.used = 0
	var map := dbg.current_map()
	var defs := dbg.get_defs()
	var def := defs.get_def(map) if map != "" else null
	var w := dbg.get_world()
	if def != null:
		match layer:
			"collision":
				_build_collision(lines, def, w)
			"spawns":
				_build_spawns(lines, L, def, w)
			"portals":
				_build_portals(lines, L, def, defs, w)
			"npcs":
				_build_npcs(lines, L, def, defs)
			"camera":
				_build_camera(lines, L, def)
			"mobregion":
				_build_mobregion(lines, L, def, defs)
			"rings":
				_build_rings(lines, L, def, w)
			"safeground":
				_build_safeground(lines, L, def, w)
	(L.mesh as MeshInstance3D).mesh = lines.to_mesh()
	L.segments = lines.count()
	L.map = map
	var labels: Array = L.labels
	for i in range(int(L.used), labels.size()):
		(labels[i] as Label3D).visible = false


func _build_collision(lines: Lines, def: MapDefinition, w: Node) -> void:
	var root: Variant = w.get("collision_root") if w != null else null
	if not (root is Node):
		return
	var box := map_box(def)
	for node in (root as Node).find_children("*", "CollisionShape3D", true, false):
		var cs := node as CollisionShape3D
		if cs.disabled or cs.shape == null:
			continue
		var body := cs.get_parent() as CollisionObject3D
		var col := layer_color(body.collision_layer if body != null else 0)
		var xf := cs.global_transform
		var local := _local_aabb(cs.shape)
		if local.size == Vector3.ZERO and local.position == Vector3.ZERO:
			continue
		if not (xf * local).intersects(box):
			continue
		shape_lines(lines, cs.shape, xf, col, box)
		if lines.count() >= MAX_SEGMENTS:
			push_warning("[DebugDraw] collision layer capped at %d segments" % MAX_SEGMENTS)
			return


func _build_spawns(lines: Lines, L: Dictionary, def: MapDefinition, w: Node) -> void:
	for a in def.spawn_areas:
		var poly: PackedVector2Array = a.get("polygon", PackedVector2Array())
		var y := float(a.get("surface_y", def.base_y)) + 0.05
		lines.polygon(poly, y, C_AREA)
		if poly.size() >= 3:
			_label(L, "area %s: %s" % [String(a.get("name", "")), ", ".join(PackedStringArray(a.get("species", [])))],
				_centroid3(poly, y) + Vector3.UP * 0.3, C_AREA, 20)
	var s := dbg.get_session()
	var st: Variant = s.get("instance_state") if s != null else null
	var inst: MapInstanceState = st if st is MapInstanceState and (st as MapInstanceState).map_id == def.map_id else null
	var now := dbg.get_clock()
	var tuning := dbg.get_defs().tuning
	var radius := tuning.num("spawns", "clearance_radius_m")
	var height := tuning.num("spawns", "clearance_height_m")
	for slot in def.monster_spawn_definitions:
		var alive := inst != null and inst.is_alive(slot.index)
		var died_at := float(inst.slots[slot.index].died_at) if inst != null else -1.0
		# Dead slots wait for their respawn tick; never-filled slots are the ones above capacity.
		var col := C_ALIVE if alive else (C_DEAD if died_at >= 0.0 else C_UNFILLED)
		var p := slot.transform.origin
		lines.circle(p + Vector3.UP * 0.03, radius, col)
		lines.seg(p, p + Vector3.UP * height, col)
		var mob_name := String(def.mob_names.get(slot.mob_id, slot.mob_id))
		var text := "#%d %s" % [slot.index, mob_name]
		if inst != null and not alive:
			if died_at >= 0.0:
				text += " %.1fs" % maxf(0.0, inst.model.respawn_time(died_at, slot.mob_time_s) - now)
			else:
				text += " (unfilled)"
		_label(L, text, p + Vector3.UP * (height + 0.15), col, 16)
	var view: Variant = w.get("instance_view") if w != null else null
	if view is MapInstanceView:
		for i in (view as MapInstanceView).nodes:
			var n: Variant = (view as MapInstanceView).nodes[i]
			if not (n is Node3D) or not is_instance_valid(n):
				continue
			var np := (n as Node3D).global_position
			lines.circle(np + Vector3.UP * 0.05, radius * 1.4, C_LIVE)
			if int(i) >= 0 and int(i) < def.monster_spawn_definitions.size():
				lines.seg(np + Vector3.UP * 0.05, def.monster_spawn_definitions[int(i)].transform.origin + Vector3.UP * 0.05, C_LIVE)
	if dbg.builtins != null:
		for m in dbg.builtins.debug_spawns:
			if not is_instance_valid(m):
				continue
			var mp := m.global_position
			lines.circle(mp + Vector3.UP * 0.05, radius * 1.4, C_DEBUG)
			lines.cross(mp, 0.5, C_DEBUG)
			_label(L, "debug %s" % String(dbg.get_db().monster(String(m.get_meta("mob_id", ""))).get("name", "?")),
				mp + Vector3.UP * (height + 0.15), C_DEBUG, 16)


func _build_portals(lines: Lines, L: Dictionary, def: MapDefinition, defs: MapDefinitions, w: Node) -> void:
	for p in def.portals:
		var col := C_PORTAL
		if p.portal_type == PortalDef.TYPE_ARRIVAL:
			col = C_GATE
		elif p.hidden:
			col = C_HIDDEN
		elif p.portal_type == PortalDef.TYPE_DOOR:
			col = C_DOOR
		var anchor := p.anchor_ground if p.has_anchor else p.anchor_transform.origin
		if p.has_anchor:
			lines.box(p.trigger_transform(), p.trigger_size, col)
		lines.cross(anchor, 0.6, col)
		var arrival := p.spawn_transform.origin
		lines.circle(arrival + Vector3.UP * 0.05, 0.35, C_ARRIVAL)
		var facing := p.spawn_transform.basis.z
		facing.y = 0.0
		if facing.length_squared() > 0.0001:
			lines.arrow(arrival + Vector3.UP * 0.1, arrival + Vector3.UP * 0.1 + facing.normalized() * 1.0, C_ARRIVAL)
		var state := ""
		var node: Variant = w.call("portal_node", def.map_id, p.portal_id) if w != null and w.has_method("portal_node") else null
		if node is WorldPortal:
			state = "" if (node as WorldPortal).armed else ", disarmed"
		var text := DebugReport.portal_label(p, defs) + state
		_label(L, text.replace(" [", "\n["), anchor + Vector3.UP * (p.trigger_size.y + 0.4), col, 22)


func _build_npcs(lines: Lines, L: Dictionary, def: MapDefinition, defs: MapDefinitions) -> void:
	var radius := defs.tuning.num("npc", "interaction_radius_m")
	for n in def.npc_definitions:
		var p := n.transform.origin
		lines.cross(p, 0.5, C_NPC)
		lines.circle(p + Vector3.UP * 0.05, radius, C_NPC)
		lines.seg(p, p + Vector3.UP * 2.0, C_NPC)
		_label(L, "%s (npc %s)%s" % [n.npc_name, n.npc_id, "" if n.from_marker else " fallback"], p + Vector3.UP * 2.2, C_NPC, 20)


func _build_camera(lines: Lines, L: Dictionary, def: MapDefinition) -> void:
	lines.polygon(def.camera_bounds, def.base_y + 0.1, C_CAMERA)
	if def.camera_bounds.size() >= 3:
		_label(L, "camera bounds (ortho %.2f m)" % def.ortho_size, Vector3(def.camera_bounds[0].x, def.base_y + 0.5, def.camera_bounds[0].y), C_CAMERA, 18)
	var cam := dbg.get_camera()
	if cam == null or not cam.has_method("focus_point") or not cam.has_method("view_half_extents"):
		return
	var right: Variant = cam.get("ground_right")
	var fwd: Variant = cam.get("ground_forward")
	if not (right is Vector3 and fwd is Vector3):
		return
	var f: Vector3 = cam.call("focus_point")
	var h: Vector2 = cam.call("view_half_extents")
	var r := right as Vector3
	var g := fwd as Vector3
	var pts := PackedVector3Array([f - r * h.x - g * h.y, f + r * h.x - g * h.y, f + r * h.x + g * h.y, f - r * h.x + g * h.y])
	for i in 4:
		lines.seg(pts[i], pts[(i + 1) % 4], C_VIEW)
	lines.cross(f, 0.4, C_VIEW)
	if cam.has_method("bounds_rect"):
		var b: Rect2 = cam.call("bounds_rect")
		if b.size != Vector2.ZERO:
			var y := f.y
			var c := [b.position, b.position + Vector2(b.size.x, 0), b.end, b.position + Vector2(0, b.size.y)]
			for i in 4:
				var a2: Vector2 = c[i]
				var b2: Vector2 = c[(i + 1) % 4]
				var a3 := r * a2.x + g * a2.y
				var b3 := r * b2.x + g * b2.y
				lines.seg(Vector3(a3.x, y, a3.z), Vector3(b3.x, y, b3.z), C_VIEW.darkened(0.3))
	_label(L, "view (rig ortho %.2f m)" % float(cam.get("ortho_size")), pts[3] + Vector3.UP * 0.3, C_VIEW, 18)


func _build_mobregion(lines: Lines, L: Dictionary, def: MapDefinition, defs: MapDefinitions) -> void:
	var region := SpawnSlotPlanner.mob_region(def, defs.tuning)
	lines.polygon(region, def.base_y + 0.15, C_MOBREGION)
	if region.size() >= 3:
		_label(L, "mob region (footprint inset %.1f m)" % defs.tuning.num("spawns", "mob_region_inset_m"),
			Vector3(region[0].x, def.base_y + 0.6, region[0].y), C_MOBREGION, 18)


func _build_rings(lines: Lines, L: Dictionary, def: MapDefinition, w: Node) -> void:
	var root: Variant = w.get("containment_root") if w != null else null
	if not (root is Node):
		return
	var ring := (root as Node).get_node_or_null("Ring_%s" % def.map_id)
	if ring == null:
		return
	for node in ring.find_children("*", "CollisionShape3D", true, false):
		var cs := node as CollisionShape3D
		shape_lines(lines, cs.shape, cs.global_transform, C_CONTAINMENT, AABB())
	if def.footprint.size() >= 1:
		_label(L, "containment ring %s" % def.map_id, Vector3(def.footprint[0].x, def.y_max + 1.0, def.footprint[0].y), C_CONTAINMENT, 18)


func _build_safeground(lines: Lines, L: Dictionary, def: MapDefinition, w: Node) -> void:
	var b := map_box(def)
	var y := def.kill_y
	lines.polygon(PackedVector2Array([Vector2(b.position.x, b.position.z), Vector2(b.end.x, b.position.z),
		Vector2(b.end.x, b.end.z), Vector2(b.position.x, b.end.z)]), y, C_KILL)
	_label(L, "fall recovery below y %.1f" % y, Vector3(b.position.x, y + 0.3, b.position.z), C_KILL, 18)
	if w == null or not w.has_method("safe_point"):
		return
	var sp: Dictionary = w.call("safe_point")
	if not bool(sp.get("ok", false)):
		return
	var p: Vector3 = sp.get("position", Vector3.ZERO)
	lines.cross(p, 0.6, C_SAFE)
	lines.circle(p + Vector3.UP * 0.03, 0.3, C_SAFE)
	lines.seg(p, p + Vector3.UP * 1.8, C_SAFE)
	_label(L, "SafeGround %s" % DebugReport.vec(p), p + Vector3.UP * 2.0, C_SAFE, 18)


# --- geometry helpers -----------------------------------------------------------------------------------------

## The world box collision is drawn in: the footprint's XZ bounds plus a margin, the map's height range plus margins.
static func map_box(def: MapDefinition) -> AABB:
	var poly := def.footprint if def.footprint.size() >= 3 else def.camera_bounds
	if poly.is_empty():
		return AABB(Vector3(-1.0e6, -1.0e6, -1.0e6), Vector3(2.0e6, 2.0e6, 2.0e6))
	var lo := poly[0]
	var hi := poly[0]
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var y0 := minf(def.y_min, def.base_y) - BOX_BELOW_M
	var y1 := maxf(def.y_max, def.base_y) + BOX_ABOVE_M
	return AABB(Vector3(lo.x - BOX_MARGIN_M, y0, lo.y - BOX_MARGIN_M),
		Vector3(hi.x - lo.x + 2.0 * BOX_MARGIN_M, y1 - y0, hi.y - lo.y + 2.0 * BOX_MARGIN_M))


static func layer_color(layer_bits: int) -> Color:
	if layer_bits & WorldLayers.WALKABLE:
		return C_WALKABLE
	if layer_bits & WorldLayers.BLOCKING:
		return C_BLOCKING
	if layer_bits & WorldLayers.SCENERY:
		return C_SCENERY
	if layer_bits & WorldLayers.CONTAINMENT:
		return C_CONTAINMENT
	return C_OTHER


## Adds the edges of `shape` (at `xf`) to `lines`. With a non-empty `clip`, concave triangles whose centroid lies
## outside it are skipped (the island body is one shape spanning every map).
static func shape_lines(lines: Lines, shape: Shape3D, xf: Transform3D, col: Color, clip: AABB) -> void:
	var use_clip := clip.size != Vector3.ZERO
	if shape is ConcavePolygonShape3D:
		var f := (shape as ConcavePolygonShape3D).get_faces()
		var i := 0
		while i + 2 < f.size():
			var a := xf * f[i]
			var b := xf * f[i + 1]
			var c := xf * f[i + 2]
			i += 3
			if use_clip and not clip.has_point((a + b + c) / 3.0):
				continue
			lines.seg(a, b, col)
			lines.seg(b, c, col)
			lines.seg(c, a, col)
	elif shape is BoxShape3D:
		lines.box(xf, (shape as BoxShape3D).size, col)
	elif shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		lines.circle(xf.origin, r, col)
		lines.circle_basis(xf.origin, r, col, Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP))
	elif shape is CapsuleShape3D or shape is CylinderShape3D:
		var r2: float = shape.get("radius")
		var h: float = shape.get("height")
		lines.circle(xf * Vector3(0, -h * 0.5, 0), r2, col)
		lines.circle(xf * Vector3(0, h * 0.5, 0), r2, col)
		for k in 4:
			var d := Vector3(cos(k * PI * 0.5), 0, sin(k * PI * 0.5)) * r2
			lines.seg(xf * (d + Vector3(0, -h * 0.5, 0)), xf * (d + Vector3(0, h * 0.5, 0)), col)
	else:
		var verts := PackedVector3Array()
		var mesh := shape.get_debug_mesh()
		if mesh != null and mesh.get_surface_count() > 0:
			var arr := mesh.surface_get_arrays(0)
			if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				verts = arr[Mesh.ARRAY_VERTEX]
		if verts.size() >= 2:
			var j := 0
			while j + 1 < verts.size():
				lines.seg(xf * verts[j], xf * verts[j + 1], col)
				j += 2
		elif shape is ConvexPolygonShape3D:
			var pts := (shape as ConvexPolygonShape3D).points
			if not pts.is_empty():
				var bb := AABB(pts[0], Vector3.ZERO)
				for p in pts:
					bb = bb.expand(p)
				lines.box(xf * Transform3D(Basis.IDENTITY, bb.get_center()), bb.size, col)


## The shape's local AABB (cached per shape).
func _local_aabb(shape: Shape3D) -> AABB:
	var key := shape.get_instance_id()
	if _aabb_cache.has(key):
		return _aabb_cache[key]
	var box := AABB()
	var pts := PackedVector3Array()
	if shape is ConcavePolygonShape3D:
		pts = (shape as ConcavePolygonShape3D).get_faces()
	elif shape is ConvexPolygonShape3D:
		pts = (shape as ConvexPolygonShape3D).points
	elif shape is BoxShape3D:
		var s := (shape as BoxShape3D).size
		box = AABB(-s * 0.5, s)
	else:
		var m := shape.get_debug_mesh()
		box = m.get_aabb() if m != null else AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	if not pts.is_empty():
		box = AABB(pts[0], Vector3.ZERO)
		for p in pts:
			box = box.expand(p)
	_aabb_cache[key] = box
	return box


static func _centroid3(poly: PackedVector2Array, y: float) -> Vector3:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= maxf(1.0, float(poly.size()))
	return Vector3(c.x, y, c.y)


func _label(L: Dictionary, text: String, pos: Vector3, col: Color, size: int) -> void:
	var labels: Array = L.labels
	var idx := int(L.used)
	var lb: Label3D = null
	if idx < labels.size():
		lb = labels[idx]
	else:
		lb = Label3D.new()
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.fixed_size = true
		lb.pixel_size = 0.0016
		lb.outline_size = 10
		lb.outline_modulate = Color(0, 0, 0, 0.85)
		lb.render_priority = 10
		lb.outline_render_priority = 9
		lb.double_sided = true
		lb.shaded = false
		(L.root as Node3D).add_child(lb)
		labels.append(lb)
	lb.visible = true
	lb.text = text
	lb.font_size = size
	lb.modulate = col
	lb.position = pos
	L.used = idx + 1


func _material(xray: bool) -> ShaderMaterial:
	if xray and _xray_material != null:
		return _xray_material
	if not xray and _depth_material != null:
		return _depth_material
	var sh := Shader.new()
	sh.code = LINE_SHADER % (", depth_test_disabled" if xray else "")
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = 5 if xray else 0
	if xray:
		_xray_material = m
	else:
		_depth_material = m
	return m


## A batch of coloured line segments that becomes one PRIMITIVE_LINES mesh.
class Lines:
	extends RefCounted
	var verts := PackedVector3Array()
	var cols := PackedColorArray()

	func count() -> int:
		return verts.size() >> 1

	func seg(a: Vector3, b: Vector3, c: Color) -> void:
		verts.append(a)
		verts.append(b)
		cols.append(c)
		cols.append(c)

	## A polygon given in world XZ at height y (closed).
	func polygon(poly: PackedVector2Array, y: float, c: Color) -> void:
		if poly.size() < 2:
			return
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			seg(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), c)

	## The 12 edges of a box of `size` centred on xf.
	func box(xf: Transform3D, size: Vector3, c: Color) -> void:
		var h := size * 0.5
		var p: Array[Vector3] = []
		for k in 8:
			p.append(xf * Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
		for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
			seg(p[e[0]], p[e[1]], c)

	func cross(p: Vector3, size: float, c: Color) -> void:
		var h := size * 0.5
		seg(p + Vector3(-h, 0, 0), p + Vector3(h, 0, 0), c)
		seg(p + Vector3(0, 0, -h), p + Vector3(0, 0, h), c)
		seg(p, p + Vector3(0, size, 0), c)

	## A horizontal circle.
	func circle(center: Vector3, r: float, c: Color, n: int = 16) -> void:
		circle_basis(center, r, c, Basis.IDENTITY, n)

	func circle_basis(center: Vector3, r: float, c: Color, basis: Basis, n: int = 16) -> void:
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			seg(center + basis * Vector3(cos(a0), 0, sin(a0)) * r, center + basis * Vector3(cos(a1), 0, sin(a1)) * r, c)

	func arrow(a: Vector3, b: Vector3, c: Color) -> void:
		seg(a, b, c)
		var d := b - a
		if d.length_squared() < 0.0001:
			return
		var side := d.cross(Vector3.UP).normalized() * d.length() * 0.25
		seg(b, b - d * 0.3 + side, c)
		seg(b, b - d * 0.3 - side, c)

	func to_mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		if verts.is_empty():
			return m
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = cols
		m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		return m
