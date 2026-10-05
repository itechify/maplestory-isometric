class_name MinimapModel
extends RefCounted
## What the minimap shows for one map (pure: no scene tree), in minimap metres (MinimapProjection's (u, v)). Built
## once per map from the map's runtime definition and the canonical records:
##
##   name, street    canonical maps/<id>.json name and street_name (the title strip)
##   ground          the map's walkable ground, projected triangles with a height tier each (collision Ground*
##                   faces from IslandWorld.ground_faces), lower tiers first: for near-horizontal surfaces under the
##                   gameplay camera a higher surface in front is the one that covers a lower one behind it, so
##                   drawing in this order is a correct painter's order. Without collision faces (headless tools,
##                   tests) the footprint is filled instead and the routes are drawn (`ground_source`)
##   climbables      ladders, ropes and vines (sidecar climbables), bottom to top
##   portals         the visible canonical portals only (MeowDB type 2): no arrival gates (adaptation geometry) and
##                   no hidden type-1 portal (000001020 in00, Tomato Field), as on a classic minimap. Each with its
##                   canonical destination name, the way out (-inward) and a shop badge when a shopkeeper stands in
##                   the destination map
##   npcs            the map's canonical NPCs at their placements, with their role icon (MapIcons.npc_role)
##   trails          the walkable trails leaving the map (edge-mode links; not the hidden hedge lane), from this map's
##                   end, so the minimap shows the stub of the way out
##
## No gameplay number is involved: every position is the runtime's, every name is canonical.

## Height step of one ground tier (m). Presentation: Maple Island's terraces rise in steps of about 1.5-4 m.
const TIER_M := 1.5
## Ground faces whose XZ centroid lies further than this outside the map's footprint are left out (m). The footprint
## already includes the containment ring offset and the region extensions.
const FOOTPRINT_MARGIN_M := 2.0
## A ground face is drawn when its outward normal's y is at least this (an upward face, slopes up to 60 degrees).
## The Ground trimeshes are closed volumes with outward faces (as many faces point down as up: slab and plinth
## undersides, down to 13 m below the map's base); steeper faces are cliff sides. Neither is seen from the gameplay
## camera, and under the painter's order by tier they would cover the terrace tops or hang below the map.
const MIN_GROUND_NORMAL_Y := 0.5
## Padding around the content when computing the bounds (m).
const BOUNDS_PAD_M := 1.0

const SOURCE_COLLISION := "collision"
const SOURCE_FOOTPRINT := "footprint"

var map_id: String = ""
var map_name: String = ""
var street_name: String = ""
var projection: MinimapProjection = null
## The content's rectangle in minimap metres (ground, footprint, portals, NPCs, climbables; trails may leave it).
var bounds: Rect2 = Rect2()
## Projected ground triangles (three points each), lower tiers first.
var ground: PackedVector2Array = PackedVector2Array()
## One tier per ground triangle: floor((centroid y - base_y) / TIER_M).
var ground_tiers: PackedInt32Array = PackedInt32Array()
## SOURCE_COLLISION or SOURCE_FOOTPRINT.
var ground_source: String = SOURCE_FOOTPRINT
## Closed polylines: the map's layout rectangle, then each region extension's ring line (at base_y).
var outline: Array[PackedVector2Array] = []
## Sidecar routes (polylines), drawn with the footprint fallback.
var routes: Array[PackedVector2Array] = []
## [{name, kind, bottom: Vector2, top: Vector2}]
var climbables: Array[Dictionary] = []
## [{id, key, pos: Vector2, world: Vector3, out_dir: Vector2, kind ("edge" | "door"), dest_map_id, dest_name,
##   dest_street, dest_shop: bool, dest_shop_npcs: PackedStringArray}]
var portals: Array[Dictionary] = []
## [{npc_id, name, pos: Vector2, world: Vector3, role (MapIcons.ROLE_*), function_title, roles: Array}]
var npcs: Array[Dictionary] = []
## [{link_id, other_map, other_name, points: PackedVector2Array (from this map's end outward)}]
var trails: Array[Dictionary] = []


## Builds the model of `def`. `ground_faces` are world triangles (IslandWorld.ground_faces); empty = the footprint
## fallback. `projection` defaults to the map's gameplay camera (MinimapProjection.for_map), else a top-down view.
static func build(def: MapDefinition, defs: MapDefinitions, db: ContentDB, ground_faces: PackedVector3Array = PackedVector3Array(),
		p_projection: MinimapProjection = null) -> MinimapModel:
	var m := MinimapModel.new()
	if def == null:
		return m
	m.map_id = def.map_id
	m.projection = p_projection if p_projection != null else MinimapProjection.for_map(def)
	if m.projection == null:
		m.projection = top_down()
	var rec := _map_record(db, def.map_id)
	m.map_name = String(rec.get("name", def.map_name if def.map_name != "" else def.map_id))
	m.street_name = String(rec.get("street_name", def.street_name)) if rec.get("street_name") != null else def.street_name
	var extent := PackedVector3Array()
	m._build_ground(def, ground_faces, extent)
	m._build_outline(def, extent)
	m._build_climbables(def, extent)
	m._build_portals(def, db, extent)
	m._build_npcs(def, db, extent)
	m._build_trails(def, defs, db)
	if extent.is_empty() and m.ground.is_empty():
		return m
	var b := m.projection.bounds_of(extent) if not extent.is_empty() else rect_of(m.ground)
	m.bounds = (b.merge(rect_of(m.ground)) if not m.ground.is_empty() else b).grow(BOUNDS_PAD_M)
	return m


## The rectangle holding every point (Rect2() for none).
static func rect_of(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var lo := points[0]
	var hi := points[0]
	for q in points:
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2(lo, hi - lo)


## A straight-down projection (north up): only for a map whose sidecar has no gameplay camera.
static func top_down() -> MinimapProjection:
	return MinimapProjection.from_basis(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP))


## World point -> minimap metres.
func project(p: Vector3) -> Vector2:
	return projection.project(p)


## The portal entry named `id` ({} when not shown).
func portal(id: String) -> Dictionary:
	for p in portals:
		if String(p["id"]) == id:
			return p
	return {}


## The NPC entry of `npc_id` ({} when not on this map).
func npc(npc_id: String) -> Dictionary:
	for n in npcs:
		if String(n["npc_id"]) == npc_id:
			return n
	return {}


func portal_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for p in portals:
		out.append(String(p["id"]))
	return out


func npc_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for n in npcs:
		out.append(String(n["npc_id"]))
	return out


## Number of ground triangles.
func ground_count() -> int:
	return ground.size() / 3


# --- building -------------------------------------------------------------------------------------------------

func _build_ground(def: MapDefinition, faces: PackedVector3Array, extent: PackedVector3Array) -> void:
	var keep := _grown(def.footprint, FOOTPRINT_MARGIN_M)
	# tier -> Array of face start indices (an Array, so appending works in place).
	var groups := {}
	var n := faces.size() - faces.size() % 3
	for i in range(0, n, 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() < 1e-12 or normal.normalized().y < MIN_GROUND_NORMAL_Y:
			continue
		var centre := (a + b + c) / 3.0
		if not keep.is_empty() and not _inside_any(Vector2(centre.x, centre.z), keep):
			continue
		var tier := floori((centre.y - def.base_y) / TIER_M)
		if not groups.has(tier):
			groups[tier] = []
		(groups[tier] as Array).append(i)
	var tiers: Array = groups.keys()
	tiers.sort()
	for tier: int in tiers:
		for i: int in groups[tier]:
			for k in 3:
				ground.append(projection.project(faces[i + k]))
			ground_tiers.append(tier)
	if not ground.is_empty():
		ground_source = SOURCE_COLLISION
		return
	# Fallback: the footprint filled at the map's base height, and the authored routes over it.
	ground_source = SOURCE_FOOTPRINT
	var poly := def.footprint if def.footprint.size() >= 3 else def.footprint_layout
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in idx:
		var w := Vector3(poly[i].x, def.base_y, poly[i].y)
		ground.append(projection.project(w))
		extent.append(w)
	for _t in idx.size() / 3:
		ground_tiers.append(0)
	var rs: Variant = def.sidecar.get("routes", null)
	for r: Variant in (rs as Array if rs is Array else []):
		var pts: Variant = (r as Dictionary).get("points", null) if r is Dictionary else null
		if not (pts is Array):
			continue
		var line := PackedVector2Array()
		for q: Variant in pts:
			var w := WorldSidecars.vec3(q)
			line.append(projection.project(w))
			extent.append(w)
		if line.size() >= 2:
			routes.append(line)


func _build_outline(def: MapDefinition, extent: PackedVector3Array) -> void:
	var rings: Array[PackedVector2Array] = [def.footprint_layout]
	for e in def.region_extensions:
		if e.get("ring_line") is PackedVector2Array:
			rings.append(e["ring_line"])
	for ring in rings:
		if ring.size() < 2:
			continue
		var line := PackedVector2Array()
		for q in ring:
			var w := Vector3(q.x, def.base_y, q.y)
			line.append(projection.project(w))
			extent.append(w)
		line.append(line[0])
		outline.append(line)


func _build_climbables(def: MapDefinition, extent: PackedVector3Array) -> void:
	var cs: Variant = def.sidecar.get("climbables", null)
	for c: Variant in (cs as Array if cs is Array else []):
		if not (c is Dictionary):
			continue
		var bottom := WorldSidecars.vec3((c as Dictionary).get("bottom", null))
		var top := WorldSidecars.vec3((c as Dictionary).get("top", null))
		climbables.append({"name": String(c.get("name", "")), "kind": String(c.get("kind", "")),
			"bottom": projection.project(bottom), "top": projection.project(top)})
		extent.append(bottom)
		extent.append(top)


func _build_portals(def: MapDefinition, db: ContentDB, extent: PackedVector3Array) -> void:
	for p in def.portals:
		if not p.is_canonical() or p.hidden or not p.has_anchor:
			continue
		var dest := _map_record(db, p.destination_map_id)
		var shop_npcs := shopkeepers_on(db, p.destination_map_id)
		portals.append({"id": p.portal_id, "key": p.key(), "pos": projection.project(p.anchor_ground),
			"world": p.anchor_ground, "out_dir": projection.project_dir(-p.inward), "kind": p.portal_type,
			"dest_map_id": p.destination_map_id, "dest_name": String(dest.get("name", p.destination_map_id)),
			"dest_street": String(dest.get("street_name", "")) if dest.get("street_name") != null else "",
			"dest_shop": not shop_npcs.is_empty(), "dest_shop_npcs": shop_npcs})
		extent.append(p.anchor_ground)


func _build_npcs(def: MapDefinition, db: ContentDB, extent: PackedVector3Array) -> void:
	for pl in def.npc_definitions:
		var rec: Dictionary = db.npc(pl.npc_id) if db != null and db.has("npcs", pl.npc_id) else {}
		var at := pl.transform.origin
		npcs.append({"npc_id": pl.npc_id, "name": String(rec.get("name", pl.npc_name)), "pos": projection.project(at),
			"world": at, "role": MapIcons.npc_role(rec),
			"function_title": String(rec.get("function_title")) if rec.get("function_title") is String else "",
			"roles": rec.get("roles") if rec.get("roles") is Array else []})
		extent.append(at)


func _build_trails(def: MapDefinition, defs: MapDefinitions, db: ContentDB) -> void:
	if defs == null:
		return
	for t in defs.trails_of(def.map_id):
		if t.hidden or not t.has_geometry() or (defs.graph != null and not defs.graph.is_edge(t.link_id)):
			continue
		var line := PackedVector2Array()
		for q in t.centreline_from(def.map_id):
			line.append(projection.project(q))
		var other := t.other_map(def.map_id)
		trails.append({"link_id": t.link_id, "other_map": other,
			"other_name": String(_map_record(db, other).get("name", other)), "points": line})


## Names of the shopkeepers in `map_id` (canonical maps/<id>.json npcs whose npcs/<id>.json has a shop).
static func shopkeepers_on(db: ContentDB, map_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var ns: Variant = _map_record(db, map_id).get("npcs", null)
	for n: Variant in (ns as Array if ns is Array else []):
		var nid := str((n as Dictionary).get("id", "")) if n is Dictionary else str(n)
		if db.has("npcs", nid) and MapIcons.npc_role(db.npc(nid)) == MapIcons.ROLE_SHOP:
			out.append(String(db.npc(nid).get("name", nid)))
	return out


static func _map_record(db: ContentDB, map_id: String) -> Dictionary:
	return db.map(map_id) if db != null and map_id != "" and db.has("maps", map_id) else {}


## `poly` grown by `margin` (Geometry2D.offset_polygon may split it; empty in, empty out).
static func _grown(poly: PackedVector2Array, margin: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if poly.size() < 3:
		return out
	for p: PackedVector2Array in Geometry2D.offset_polygon(poly, margin, Geometry2D.JOIN_MITER):
		out.append(p)
	return out


static func _inside_any(p: Vector2, polys: Array[PackedVector2Array]) -> bool:
	for poly in polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false
