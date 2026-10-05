class_name MapDefinitions
extends RefCounted
## All 25 MapDefinitions, keyed by MeowDB id, plus the PortalGraph that links them (MAP_ARCHITECTURE.md section 4.3).
##
## This is the one place where canonical data and geometry are joined (the assembler's job in section 4.10, done at
## load time for M1). Inputs:
##   game/data/canonical/maps/<id>.json          WHAT: names, portals + destinations, spawns, NPC ids, returnMap ...
##   game/data/misostory/map_id_crosswalk.json   MeowDB id <-> GMS v8 id <-> Blender slug
##   game/assets/world/<slug>.json (optional)    WHERE: portal anchors, NPC markers, player start, spawn areas,
##                                               footprint, frame, bounds, gameplay camera
##   game/data/misostory/portal_adaptations.json, presentation.json, maps/<id>.json   adaptation rules (maps/<id>.json
##                                               region_extensions grow a map's footprint: apply_region_extensions)
## build() is pure and works without the export (every transform stays identity, has_markers = false), so the graph
## and spawn-count checks run anywhere. ground_all(GroundQuery) then snaps every transform onto collision and plans
## the spawn slots; the world calls it with PhysicsGroundQuery once collision is loaded.
##
## Trails (milestone M2): build() makes one TrailDef per trail link with its two gates (GateDef on each map's ring
## line, from the portal anchors; section 4.4). The ribbon geometry comes from the export: the sidecar's centreline
## when World_Trails.json provides one, else IslandWorld derives it from the trail meshes (TrailGeometry) and calls
## finish_trails(), which folds the trails into kill_y and camera_bounds (section 4.11: footprint + the zones of the
## edge-mode trails touching the map).

var maps: Dictionary = {}
var graph: PortalGraph = PortalGraph.new()
var tuning: WorldTuning = null
var spawn_model: SpawnModel = null
var sidecars: WorldSidecars = null
var errors: PackedStringArray = []
var warnings: PackedStringArray = []
## NPC parity (section 3.3): {"missing_markers": [{map_id, npc_id, name}], "extra_markers": [{map_id, name,
## sidecar_npc_id}], "matched": int}.
var npc_report: Dictionary = {"missing_markers": [], "extra_markers": [], "matched": 0}
## Crosswalk rows as read, and the lookups built from them.
var crosswalk_rows: Array[Dictionary] = []
var slug_of: Dictionary = {}
var id_of_slug: Dictionary = {}
var id_of_v8: Dictionary = {}
## True once ground_all() ran.
var grounded: bool = false
## Monster species body heights (mob_id -> m) for the spawn clearance (SpawnSlotPlanner.species_body_heights).
var body_heights: Dictionary = {}
## link id -> TrailDef, one per trail link (geometry attached by the world; see the class doc).
var trails: Dictionary = {}
## map id -> kill_y before trails were folded in (finish_trails() is idempotent).
var _own_kill_y: Dictionary = {}


## Builds every definition from `db` (Data.db at runtime, TestCase.db() in tests) and the optional export.
static func build(db: ContentDB, world: WorldSidecars = null) -> MapDefinitions:
	var d := MapDefinitions.new()
	d.tuning = WorldTuning.from_db(db)
	d.spawn_model = SpawnModel.from_db(db)
	d.body_heights = SpawnSlotPlanner.species_body_heights(db)
	d.sidecars = world
	d.errors.append_array(d.tuning.errors)
	d.errors.append_array(d.spawn_model.errors)
	d._read_crosswalk(db)
	for id in db.ids("maps"):
		d._build_map(db, id)
	d._add_arrival_gates()
	d.graph.resolve_destinations(d.tuning.portal_section("destination_overrides").get("overrides", {}))
	var modes := d.tuning.portal_section("default_link_mode")
	d.graph.build_links({PortalGraph.KIND_TRAIL: String(modes.get("trail", PortalDef.LINK_WARP)),
		PortalGraph.KIND_DOOR: String(modes.get("door", PortalDef.LINK_WARP))},
		d.tuning.portal_section("link_modes").get("overrides", {}), d.tuning.forced_link_mode())
	d._check_v8_names()
	d._compute_spawn_transforms()
	d._build_trails()
	d.errors.append_array(d.graph.errors)
	return d


func get_def(map_id: String) -> MapDefinition:
	return maps.get(map_id, null)


func has_map(map_id: String) -> bool:
	return maps.has(map_id)


func ids() -> PackedStringArray:
	var out := PackedStringArray(maps.keys())
	out.sort()
	return out


func portal(map_id: String, portal_id: String) -> PortalDef:
	return graph.portal(map_id, portal_id)


## The transform an ArrivalRef stands for: a portal's spawn_transform or player_spawns[i].
## Returns {"ok": bool, "xform": Transform3D, "error": String}.
func arrival_transform(ref: ArrivalRef) -> Dictionary:
	if ref == null:
		return {"ok": false, "xform": Transform3D.IDENTITY, "error": "no arrival"}
	var def := get_def(ref.map_id)
	if def == null:
		return {"ok": false, "xform": Transform3D.IDENTITY, "error": "unknown map %s" % ref.map_id}
	if ref.is_portal():
		var p := def.portal(ref.portal_id)
		if p == null:
			return {"ok": false, "xform": Transform3D.IDENTITY, "error": "unknown portal %s" % ref}
		return {"ok": true, "xform": p.spawn_transform, "error": ""}
	if def.player_spawns.is_empty():
		return {"ok": false, "xform": Transform3D.IDENTITY, "error": "%s has no player spawn" % ref.map_id}
	return {"ok": true, "xform": def.player_spawn(ref.spawn_index), "error": ""}


## The ArrivalRef a portal press lands on.
func arrival_for(p: PortalDef) -> ArrivalRef:
	if p.destination_portal_id != "":
		return ArrivalRef.at_portal(p.destination_map_id, p.destination_portal_id)
	return ArrivalRef.at_spawn(p.destination_map_id, maxi(p.destination_spawn_index, 0))


## Height (m) of the spawn clearance capsule for a species: its body height, at least presentation.json
## spawns.clearance_height_m (SpawnSlotPlanner.clearance_height).
func clearance_height(mob_id: String) -> float:
	return SpawnSlotPlanner.clearance_height(mob_id, tuning, body_heights)


## Capacity of a map (SpawnModel.capacity_for_map: the map's mob rate counts only when presentation.json
## map_mob_rate.apply is on).
func capacity_of(map_id: String, players: int = 1) -> int:
	var def := get_def(map_id)
	return spawn_model.capacity_for_map(map_id, def.spawn_point_count(), players) if def != null else 0


## Snaps every transform onto collision (portal arrivals and anchors, player spawns, NPCs) and plans the spawn
## slots. Returns the warnings it produced (also appended to `warnings`).
func ground_all(q: GroundQuery) -> PackedStringArray:
	var out: PackedStringArray = []
	var up := tuning.num("grounding", "probe_up_m")
	var down := tuning.num("grounding", "probe_down_m")
	for id in ids():
		var def := get_def(id)
		if not def.has_markers:
			continue
		# Anchors first: the trigger boxes are built on the grounded anchors.
		for p in def.portals:
			if p.has_anchor:
				var ga := q.ground_at(p.anchor_transform.origin, up, down)
				p.anchor_ground = Vector3(p.anchor_transform.origin.x, float(ga.y) if bool(ga.ok) else p.anchor_transform.origin.y,
					p.anchor_transform.origin.z)
		# Player spawns: authored ones are settled; unauthored indices repeat the settled [0].
		var ps_ok: Array[bool] = []
		var authored := maxi(def.player_spawns_authored, 1)
		for i in def.player_spawns.size():
			var t := def.player_spawns[i]
			if i >= authored and not ps_ok.is_empty():
				def.player_spawns[i] = def.player_spawns[0]
				ps_ok.append(ps_ok[0])
				continue
			var s := settle(def, t.origin, t.basis.z, q)
			if bool(s.ok):
				t.origin = s.origin
				def.player_spawns[i] = t
				if float(s.moved) > 0.0:
					out.append("%s player_spawns[%d] moved %.1f m to stand clear (%s)" % [id, i, float(s.moved), String(s.note)])
			else:
				out.append("%s player_spawns[%d] has no grounded, clear point within reach (%s)" % [id, i, String(s.note)])
			ps_ok.append(bool(s.ok))
		for p in def.portals:
			if p.portal_type == PortalDef.TYPE_ARRIVAL:
				var si := clampi(int(p.provenance.get("spawn_index", 0)), 0, maxi(def.player_spawns.size() - 1, 0))
				p.spawn_transform = def.player_spawn(si)
				p.grounded = ps_ok[si] if si < ps_ok.size() else false
				continue
			if not p.has_anchor:
				continue
			var sp := settle(def, p.spawn_transform.origin, p.inward, q)
			p.grounded = bool(sp.ok)
			p.ground_note = String(sp.note)
			if bool(sp.ok):
				p.spawn_transform.origin = sp.origin
				if float(sp.moved) > 0.0:
					p.ground_note = "moved %.1f m: %s" % [float(sp.moved), String(sp.note)]
					out.append("%s arrival %s" % [p.key(), p.ground_note])
			else:
				out.append("%s arrival has no grounded, clear point within reach (%s)" % [p.key(), p.ground_note])
		for n in def.npc_definitions:
			_ground_npc(def, n, q, up, down, out)
		out.append_array(SpawnSlotPlanner.plan(def, q, tuning, body_heights))
	_ground_gates(q)
	grounded = true
	warnings.append_array(out)
	return out


## The standing point nearest to `origin` that is grounded (grounding probe), capsule-clear, inside the map and
## outside every portal trigger: `origin` itself, else rings of grounding.search_step_m up to search_radius_m,
## each ring starting in direction `prefer` (inward for arrivals). {"ok", "origin": Vector3, "moved": float,
## "note": why the original point failed}.
func settle(def: MapDefinition, origin: Vector3, prefer: Vector3, q: GroundQuery) -> Dictionary:
	var first := _standing(def, origin, q)
	if bool(first.ok):
		return {"ok": true, "origin": first.origin, "moved": 0.0, "note": ""}
	var step := maxf(tuning.num("grounding", "search_step_m"), 0.01)
	var max_r := tuning.num("grounding", "search_radius_m")
	var dir := Vector3(prefer.x, 0.0, prefer.z)
	dir = dir.normalized() if dir.length_squared() > 0.000001 else Vector3.BACK
	var ring := step
	while ring <= max_r + 0.000001:
		var n := maxi(8, int(ceil(TAU * ring / step)))
		for k in n:
			var j := ((k + 1) / 2) * (1 if k % 2 == 1 else -1)
			var c := origin + dir.rotated(Vector3.UP, TAU * j / n) * ring
			var t := _standing(def, c, q)
			if bool(t.ok):
				return {"ok": true, "origin": t.origin, "moved": ring, "note": String(first.note)}
		ring += step
	return {"ok": false, "origin": origin, "moved": 0.0, "note": String(first.note)}


func _standing(def: MapDefinition, p: Vector3, q: GroundQuery) -> Dictionary:
	if def.footprint.size() >= 3 and not def.footprint_contains(p):
		return {"ok": false, "note": "outside the map"}
	var g := q.ground_at(p, tuning.num("grounding", "probe_up_m"), tuning.num("grounding", "probe_down_m"))
	if not bool(g.ok):
		return {"ok": false, "note": String(g.get("note", "no ground"))}
	var feet := Vector3(p.x, float(g.y), p.z)
	if not q.is_clear(feet + Vector3.UP * tuning.num("grounding", "capsule_lift_m"), tuning.num("grounding", "capsule_radius_m"),
			tuning.num("grounding", "capsule_height_m")):
		var who: PackedStringArray = q.call("blockers", feet + Vector3.UP * tuning.num("grounding", "capsule_lift_m"),
			tuning.num("grounding", "capsule_radius_m"), tuning.num("grounding", "capsule_height_m")) if q.has_method("blockers") else PackedStringArray()
		return {"ok": false, "note": "capsule blocked by %s" % ", ".join(who) if not who.is_empty() else "capsule blocked"}
	for o in def.portals:
		if o.is_canonical() and o.has_anchor and o.trigger_contains(feet + Vector3.UP * 0.1):
			return {"ok": false, "note": "inside trigger %s" % o.key()}
	return {"ok": true, "origin": feet, "note": ""}


## Every canonical portal, sorted by "<map>.<portal>".
func canonical_portals() -> Array[PortalDef]:
	return graph.canonical_portals()


# --- trails and gates (milestone M2) ---------------------------------------------------------------------------

## Re-applies the link modes portal_adaptations.json configures (force_link_mode, else link_modes overrides, else
## default_link_mode by kind; doors always warp), undoing runtime switches (the debug console, a traversal run). A
## trail link without ribbon geometry stays warp. Emits link_mode_changed for every link that changes.
func apply_configured_link_modes() -> void:
	var modes := tuning.portal_section("default_link_mode")
	graph.build_links({PortalGraph.KIND_TRAIL: String(modes.get("trail", PortalDef.LINK_WARP)),
		PortalGraph.KIND_DOOR: String(modes.get("door", PortalDef.LINK_WARP))},
		tuning.portal_section("link_modes").get("overrides", {}), tuning.forced_link_mode())
	if sidecars != null:
		for t in trail_list():
			if not t.has_geometry() and graph.is_edge(t.link_id):
				graph.set_link_mode(t.link_id, PortalDef.LINK_WARP)


## Every TrailDef, sorted by link id.
func trail_list() -> Array[TrailDef]:
	var out: Array[TrailDef] = []
	var keys := trails.keys()
	keys.sort()
	for k in keys:
		out.append(trails[k])
	return out


func trail(link_id: String) -> TrailDef:
	return trails.get(link_id, null)


## The trails touching `map_id` (any link mode), sorted by link id.
func trails_of(map_id: String) -> Array[TrailDef]:
	var out: Array[TrailDef] = []
	for t in trail_list():
		if t.touches(map_id):
			out.append(t)
	return out


## The gates GateMonitor tests while `current_map` is current: the far-end gate of every edge-mode trail touching
## it (the gate into the other map; never a gate of current_map itself, so a player cannot ping-pong). At most 8
## (000001000).
func far_gates(current_map: String) -> Array[GateDef]:
	var out: Array[GateDef] = []
	for t in trails_of(current_map):
		if not graph.is_edge(t.link_id):
			continue
		var g := t.gate_into(t.other_map(current_map))
		if g != null:
			out.append(g)
	return out


## Every gate of every trail (both ends), sorted by trail.
func all_gates() -> Array[GateDef]:
	var out: Array[GateDef] = []
	for t in trail_list():
		for g in t.gates:
			if g != null:
				out.append(g)
	return out


## The trail whose `map_id` end is `portal_id` (null when that portal is not a trail end).
func trail_at_portal(map_id: String, portal_id: String) -> TrailDef:
	var key := "%s.%s" % [map_id, portal_id]
	for t in trail_list():
		if key in t.portal_keys:
			return t
	return null


## Merges authored region extensions (data/misostory/maps/<id>.json `region_extensions`) into `def.footprint`, so a
## walkable part of the map that the export builds outside its layout rectangle (Southperry's moored ship) belongs
## to the map's region and lies inside its containment ring. Each entry:
##   name                         label for logs
##   ring_line_local              [[x, y], ...] in the map's local frame (the sidecar's footprint.local_frame, metres,
##                                x and y as in the Blender map source; world = def.frame * Vector3(x, 0, -y)). It is
##                                the region's edge itself, where the ring wall's inner face stands: it is NOT grown by
##                                containment.ring_offset_m. It must overlap the footprint so the union is one polygon.
##   keep_footprint_ring_below_y  optional world height: where the extension opens the layout's own ring line, that
##                                wall still stands from the ring's foot up to this height (ContainmentBuilder), so
##                                ground below the extension stays closed while a walkway crosses above it.
##   reason, verified             the adaptation convention.
## Appends to `def.region_extensions`; `def.footprint_base` keeps the footprint before the union. Returns the errors
## (an entry without a reason, with fewer than 3 points, or that does not merge into one polygon is skipped). A map
## without a footprint (no export geometry) has nothing to extend: nothing happens and nothing is reported.
static func apply_region_extensions(def: MapDefinition, entries: Array) -> PackedStringArray:
	var errs := PackedStringArray()
	if def.footprint.size() < 3:
		return errs
	if def.footprint_base.is_empty():
		def.footprint_base = def.footprint.duplicate()
	for e in entries:
		if not (e is Dictionary):
			errs.append("%s: region_extensions entries must be objects" % def.map_id)
			continue
		var label := "%s region extension %s" % [def.map_id, String(e.get("name", "?"))]
		if String(e.get("reason", "")) == "":
			errs.append("%s has no reason" % label)
			continue
		var ring := PackedVector2Array()
		var pts: Variant = e.get("ring_line_local", [])
		if pts is Array:
			for p in pts:
				if p is Array and (p as Array).size() >= 2:
					var w := def.frame * Vector3(float(p[0]), 0.0, -float(p[1]))
					ring.append(Vector2(w.x, w.z))
		if ring.size() < 3:
			errs.append("%s needs a ring_line_local of at least 3 points" % label)
			continue
		var merged := Geometry2D.merge_polygons(def.footprint, ring)
		if merged.size() != 1:
			errs.append("%s does not merge with the footprint into one polygon (%d pieces): it must overlap it" % [label, merged.size()])
			continue
		def.footprint = merged[0]
		var below: Variant = e.get("keep_footprint_ring_below_y", null)
		def.region_extensions.append({"name": String(e.get("name", "")), "ring_line": ring,
			"keep_ring_below_y": float(below) if (below is float or below is int) else NAN, "reason": String(e.reason)})
	return errs


## The point where a portal's outward ray (from its anchor, along -inward) crosses `footprint` (the ring line,
## footprint + containment.ring_offset_m), at the anchor's height. The anchor itself when the ray misses.
static func ring_point(footprint: PackedVector2Array, anchor: Vector3, inward: Vector3) -> Vector3:
	var a := Vector2(anchor.x, anchor.z)
	var d := -Vector2(inward.x, inward.z)
	if d.length_squared() < 1e-12 or footprint.size() < 3:
		return anchor
	d = d.normalized()
	var best := INF
	for i in footprint.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(a, a + d * 10000.0, footprint[i], footprint[(i + 1) % footprint.size()])
		if hit is Vector2:
			best = minf(best, ((hit as Vector2) - a).length())
	if best == INF:
		return anchor
	return Vector3(a.x + d.x * best, anchor.y, a.y + d.y * best)


## Attaches a ribbon to `link_id`'s trail (TrailGeometry rows, ordered from the trail's end 0 to end 1). `side_a` /
## `side_b`: the top's own edges (the side walls follow them); the rows' left and right when omitted.
func attach_trail_geometry(link_id: String, centre: PackedVector3Array, left: PackedVector3Array, right: PackedVector3Array,
		half: PackedFloat32Array, source: String, notes: PackedStringArray = PackedStringArray(),
		side_a: PackedVector3Array = PackedVector3Array(), side_b: PackedVector3Array = PackedVector3Array()) -> Error:
	var t := trail(link_id)
	if t == null:
		return ERR_DOES_NOT_EXIST
	t.set_ribbon(centre, left, right, half)
	t.side_a = side_a if side_a.size() >= 2 else left
	t.side_b = side_b if side_b.size() >= 2 else right
	t.source = source
	t.notes.append_array(notes)
	return OK


## After the ribbons are attached: a trail link without geometry is an error and falls back to warp (it cannot be
## walked); kill_y of each map drops to its trails' lowest point minus fall_recovery.kill_y_margin_m (the 30 -> 40
## trail falls 9.8 m below 000000030); camera bounds include the touching edge-mode trails. Idempotent.
func finish_trails() -> PackedStringArray:
	var out: PackedStringArray = []
	for t in trail_list():
		if not t.has_geometry() and sidecars != null:
			out.append("trail %s has no ribbon geometry; the link stays warp" % t.link_id)
			if graph.is_edge(t.link_id):
				graph.set_link_mode(t.link_id, PortalDef.LINK_WARP)
	var margin := tuning.num("fall_recovery", "kill_y_margin_m")
	for id in ids():
		var def := get_def(id)
		if not _own_kill_y.has(id):
			_own_kill_y[id] = def.kill_y
		def.kill_y = float(_own_kill_y[id])
		for t in trails_of(id):
			if t.has_geometry():
				def.kill_y = minf(def.kill_y, t.y_lo - margin)
	refresh_camera_bounds()
	for e in out:
		if not (e in errors):
			errors.append(e)
	return out


## camera_bounds of every map: its footprint united with the zones of the edge-mode trails touching it (section
## 4.11). Call again when link modes change (IslandWorld does).
func refresh_camera_bounds() -> void:
	for id in ids():
		var def := get_def(id)
		var acc := def.footprint.duplicate()
		if acc.size() < 3:
			def.camera_bounds = acc
			continue
		for t in trails_of(id):
			if not (t.has_geometry() and graph.is_edge(t.link_id)):
				continue
			acc = MapDefinitions._union(acc, t.zone_polygon())
		def.camera_bounds = acc


## The outline of a and b united; the convex hull of both when they do not merge into one simple polygon (the
## camera only uses the bounds' extent along its axes, which the hull keeps).
static func _union(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	if b.size() < 3:
		return a
	var merged := Geometry2D.merge_polygons(a, b)
	if merged.size() == 1:
		return merged[0]
	var pts := a.duplicate()
	pts.append_array(b)
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	return hull


func _build_trails() -> void:
	var sizes := tuning.portal_section("gates")
	var margin := tuning.num("trails", "zone_margin_m")
	var band := tuning.num("trails", "zone_band_m")
	var order := _sidecar_trail_order()
	var keys := graph.links.keys()
	keys.sort()
	for id in keys:
		var link: Dictionary = graph.links[id]
		if String(link.kind) != PortalGraph.KIND_TRAIL:
			continue
		var ends: Array[PortalDef] = []
		for k in link.ends:
			var p: PortalDef = graph.portals.get(k, null)
			if p != null:
				ends.append(p)
		if ends.size() != 2:
			errors.append("trail link %s has %d ends" % [id, ends.size()])
			continue
		# The sidecar's from end first, so the ribbon runs maps[0] -> maps[1] as Blender built it.
		if order.has(ends[1].key()) and not order.has(ends[0].key()):
			ends.reverse()
		var t := TrailDef.new()
		t.link_id = String(id)
		t.one_way = bool(link.one_way)
		t.zone_margin = margin
		t.zone_band = band
		for p in ends:
			t.maps.append(p.source_map_id)
			t.portal_keys.append(p.key())
			t.hidden = t.hidden or (p.hidden and p.is_canonical())  # a hidden MeowDB portal (type 1), not the arrival gate
		t.gates = [_make_gate(t, ends[0], ends[1], sizes), _make_gate(t, ends[1], ends[0], sizes)]
		trails[String(id)] = t
		_apply_sidecar_ribbon(t)


## Uses the export's own centreline when World_Trails.json trails[] carries one ("centreline": [[x, y, z], ...] from
## the from end, with "half_width_m" (one number) or "half_widths_m" (one per point)); the mesh-derived ribbon is
## the stopgap until then (IslandWorld, TrailGeometry).
func _apply_sidecar_ribbon(t: TrailDef) -> void:
	for e in sidecar_trails():
		if not (e is Dictionary) or not (e.get("centreline", null) is Array):
			continue
		var m := String(id_of_slug.get(String(e.get("from_chunk", "")), ""))
		if "%s.%s" % [m, String(e.get("from_portal", ""))] != t.portal_keys[0]:
			continue
		var c := PackedVector3Array()
		for p in e.centreline:
			c.append(WorldSidecars.vec3(p))
		if c.size() < 2:
			return
		var halves := PackedFloat32Array()
		var per: Variant = e.get("half_widths_m", null)
		for i in c.size():
			halves.append(float(per[i]) if per is Array and i < (per as Array).size() else float(e.get("half_width_m", 0.0)))
		var l := PackedVector3Array()
		var r := PackedVector3Array()
		for i in c.size():
			var d := c[mini(i + 1, c.size() - 1)] - c[maxi(i - 1, 0)]
			var lat := Vector3.UP.cross(Vector3(d.x, 0.0, d.z)).normalized()
			l.append(c[i] + lat * halves[i])
			r.append(c[i] - lat * halves[i])
		t.set_ribbon(c, l, r, halves)
		t.side_a = l
		t.side_b = r
		t.source = "sidecar"
		return


## Portal keys that are a trail's from end in World_Trails.json trails[] ({} without the export).
func _sidecar_trail_order() -> Dictionary:
	var out := {}
	for e in sidecar_trails():
		var m := String(id_of_slug.get(String(e.get("from_chunk", "")), ""))
		if m != "":
			out["%s.%s" % [m, String(e.get("from_portal", ""))]] = true
	return out


## World_Trails.json trails[] entries ([] without the export).
func sidecar_trails() -> Array:
	if sidecars == null:
		return []
	for n in sidecars.chunks:
		var c: Dictionary = sidecars.chunks[n]
		if c.get("trails", null) is Array:
			return c.trails
	return []


## The gate into the map of trail end `p`: on the ring line where the portal's outward ray leaves the footprint,
## normal p.inward. Its commit's source portal is the other end when that portal leads into the map.
func _make_gate(t: TrailDef, p: PortalDef, other: PortalDef, sizes: Dictionary) -> GateDef:
	var def := get_def(p.source_map_id)
	if def == null or not p.has_anchor or def.footprint.size() < 3:
		return null
	var at := MapDefinitions.ring_point(def.footprint, p.anchor_ground, p.inward)
	var g := GateDef.make(t.link_id, p.source_map_id, other.source_map_id, at, p.inward, sizes)
	g.portal = p
	if other.is_canonical() and other.destination_map_id == p.source_map_id:
		g.source_portal = other
	return g


## Gate heights: the ground just inside the map at the gate (0.3 m along the normal), probed from the anchor's
## grounded height (the 000000040 landing under the one-way ledge, not the trail top).
func _ground_gates(q: GroundQuery) -> void:
	var up := tuning.num("grounding", "probe_up_m")
	var down := tuning.num("grounding", "probe_down_m")
	for g in all_gates():
		var base := g.portal.anchor_ground if g.portal != null else g.origin
		var probe := Vector3(g.origin.x, base.y, g.origin.z) + g.normal * 0.3
		var r := q.ground_at(probe, up, down)
		g.origin.y = float(r.y) if bool(r.ok) else base.y


# --- building ---------------------------------------------------------------------------------------------

func _read_crosswalk(db: ContentDB) -> void:
	var raw: Variant = db.miso_table("map_id_crosswalk")
	if raw is Dictionary and (raw as Dictionary).get("rows", null) is Array:
		raw = (raw as Dictionary).rows
	if not (raw is Array):
		errors.append("data/misostory/map_id_crosswalk.json is missing or not an array of rows")
		return
	for r in raw:
		if not (r is Dictionary):
			continue
		var row: Dictionary = r
		crosswalk_rows.append(row)
		var id := String(row.get("meowdb_id", row.get("map_id", "")))
		var slug := String(row.get("iteration_one_slug", row.get("blender_slug", "")))
		if id == "":
			continue
		if slug_of.has(id):
			errors.append("crosswalk lists %s twice" % id)
		slug_of[id] = slug
		if slug != "":
			if id_of_slug.has(slug):
				errors.append("crosswalk lists slug %s twice" % slug)
			id_of_slug[slug] = id
		if row.has("gms_v8_id"):
			id_of_v8[str(int(row.gms_v8_id))] = id


func _build_map(db: ContentDB, id: String) -> void:
	var rec := db.map(id)
	var def := MapDefinition.new()
	def.map_id = id
	def.map_name = String(rec.get("name", ""))
	def.street_name = String(rec.get("street_name", ""))
	def.canonical = rec
	# MeowDB gives the returnMap; which of its playerSpawns a respawn uses is an adaptation (open question 1,
	# data/misostory/death.json respawn_player_spawn_index).
	def.respawn_location = ArrivalRef.at_spawn(String(rec.get("return_map_id", id)), tuning.respawn_spawn_index())
	var bgm: Dictionary = rec.get("bgm", {}) if rec.get("bgm", null) is Dictionary else {}
	var override := tuning.map_override(id)
	def.environment_configuration = {
		"bgm": String(bgm.get("path", "")),
		"bgm_name": String(bgm.get("name", "")),
		"is_town": bool(rec.get("is_town", false)),
		"safe_zone": bool(rec.get("safe_zone", false)),
		"field_limit": int(rec.get("field_limit", 0)),
		"mob_rate": float(rec.get("mob_rate", 1.0)),
		"preset": String(override.get("environment_preset", tuning.text("environment", "default_preset"))),
	}
	for m in rec.get("monsters", []):
		if m is Dictionary:
			def.mob_names[str(m.get("id", ""))] = String(m.get("name", ""))
	def.slug = String(slug_of.get(id, ""))
	for row in crosswalk_rows:
		if String(row.get("meowdb_id", row.get("map_id", ""))) == id and row.has("gms_v8_id"):
			def.gms_v8_id = int(row.gms_v8_id)
	if def.slug == "":
		errors.append("map %s has no crosswalk row" % id)
	var sc: Dictionary = sidecars.chunk(def.slug) if sidecars != null and def.slug != "" else {}
	def.sidecar = sc
	def.has_markers = not sc.is_empty()
	if sidecars != null and not def.has_markers:
		errors.append("map %s (%s) has no sidecar in %s" % [id, def.slug, sidecars.dir])
	if def.has_markers:
		_apply_sidecar(def, sc)
	# Portals: exactly MeowDB's list; the sidecar only places them.
	var markers := {}
	for m in sc.get("portals", []):
		if m is Dictionary:
			markers[String(m.get("name", ""))] = m
	graph.add_map(id)
	for p in rec.get("portals", []):
		if not (p is Dictionary):
			continue
		var pd := PortalDef.new()
		pd.portal_id = String(p.get("name", ""))
		pd.source_map_id = id
		pd.destination_map_id = String(p.get("to_map_id", ""))
		pd.canonical_type = int(p.get("type", 2))
		pd.hidden = pd.canonical_type in tuning.hidden_portal_types()
		pd.trigger_size = tuning.trigger_size()
		pd.provenance = {"meowdb_url": String((rec.get("source", {}) as Dictionary).get("url", "")),
			"meowdb_to_portal": String(p.get("to_portal", "")) if p.get("to_portal", null) != null else "",
			"v8_to_portal": "", "v8_name_match": false}
		if markers.has(pd.portal_id):
			_apply_portal_marker(pd, markers[pd.portal_id], def)
		elif def.has_markers:
			errors.append("%s has no portal marker in sidecar %s" % [pd.key(), def.slug])
		def.portals.append(pd)
		graph.add_portal(pd)
		if not (pd.destination_map_id in def.destination_maps):
			def.destination_maps.append(pd.destination_map_id)
	# Player spawns: MeowDB says how many; the export says where ([0] = player_start for M1).
	# The sidecar's own player_spawns[] (by "index") when exported, else player_start as [0].
	var authored := {}
	if sc.get("player_spawns", null) is Array:
		var k := 0
		for m in sc.player_spawns:
			if m is Dictionary:
				authored[int(m.get("index", k))] = WorldSidecars.marker_xform(m)
			k += 1
	if not authored.has(0) and sc.get("player_start", null) is Dictionary:
		authored[0] = WorldSidecars.marker_xform(sc.player_start)
	def.player_spawns_authored = authored.size()
	var count := maxi((rec.get("player_spawns", []) as Array).size(), 1)
	for key in authored:
		count = maxi(count, int(key) + 1)
	for i in count:
		if authored.has(i):
			def.player_spawns.append(authored[i])
		elif authored.has(0):
			def.player_spawns.append(authored[0])
		else:
			def.player_spawns.append(Transform3D.IDENTITY)
	# Spawn slots: exactly MeowDB's spawns[], index preserved; placed later by ground_all().
	var spawns: Array = rec.get("spawns", [])
	for i in spawns.size():
		var s: Dictionary = spawns[i]
		var slot := SpawnSlot.new()
		slot.index = i
		slot.mob_id = str(s.get("mob_id", ""))
		slot.mob_time_s = float(s.get("mob_time_s", 0.0))
		def.monster_spawn_definitions.append(slot)
	_place_npcs(def, rec, sc)
	maps[id] = def


func _apply_sidecar(def: MapDefinition, sc: Dictionary) -> void:
	var kind := String(sc.get("kind", ""))
	def.kind = String(sc.get("map_kind", kind))
	def.world_space = MapDefinition.SPACE_INTERIOR if (kind == "interior" or def.kind == "interior") else MapDefinition.SPACE_ISLAND
	if sidecars != null and sc.has("map_id") and id_of_v8.get(str(int(sc.map_id)), def.map_id) != def.map_id:
		errors.append("sidecar %s says map_id %s, crosswalk says %s" % [def.slug, str(sc.map_id), def.map_id])
	if sc.has("meowdb_map_id") and str(sc.meowdb_map_id) != def.map_id:
		errors.append("sidecar %s says meowdb_map_id %s, crosswalk says %s" % [def.slug, str(sc.meowdb_map_id), def.map_id])
	var fp: Dictionary = sc.get("footprint", {}) if sc.get("footprint", null) is Dictionary else {}
	def.footprint_layout = WorldSidecars.poly_xz(fp.get("outline_xz", fp.get("polygon", [])))
	def.base_y = float(fp.get("base_y", 0.0))
	var lf: Dictionary = fp.get("local_frame", {}) if fp.get("local_frame", null) is Dictionary else {}
	def.frame = Transform3D(Basis(Vector3.UP, deg_to_rad(float(lf.get("yaw_deg", 0.0)))),
		WorldSidecars.vec3(lf.get("origin", null), Vector3(0, def.base_y, 0)))
	if def.footprint_layout.size() >= 3:
		var grown := Geometry2D.offset_polygon(def.footprint_layout, tuning.num("containment", "ring_offset_m"), Geometry2D.JOIN_MITER)
		def.footprint = grown[0] if not grown.is_empty() else def.footprint_layout
	def.footprint_base = def.footprint.duplicate()
	var ext: Variant = tuning.map_override(def.map_id).get("region_extensions", [])
	if ext is Array and not (ext as Array).is_empty():
		errors.append_array(apply_region_extensions(def, ext))
	def.camera_bounds = def.footprint.duplicate()
	var b: Dictionary = sc.get("bounds", {}) if sc.get("bounds", null) is Dictionary else {}
	var bpos := WorldSidecars.vec3(b.get("position", null), Vector3(0, def.base_y, 0))
	var bsize := WorldSidecars.vec3(b.get("size", null), Vector3.ZERO)
	def.y_min = bpos.y
	def.y_max = bpos.y + bsize.y
	# Lowest walkable height: base, player start, portal anchors, spawn areas, route points, climbable feet.
	var lowest := def.base_y
	for m in sc.get("portals", []):
		if m is Dictionary:
			lowest = minf(lowest, WorldSidecars.marker_xform(m).origin.y)
	if sc.get("player_start", null) is Dictionary:
		lowest = minf(lowest, WorldSidecars.marker_xform(sc.player_start).origin.y)
	for key in ["spawn_areas", "spawn_regions", "player_spawns", "arrival_points"]:
		for a in sc.get(key, []):
			if a is Dictionary and a.has("surface_y"):
				lowest = minf(lowest, float(a.surface_y))
			elif a is Dictionary and (a.has("xform") or a.has("position")):
				lowest = minf(lowest, WorldSidecars.marker_xform(a).origin.y)
	for r in sc.get("routes", []):
		if r is Dictionary:
			for pt in r.get("points", []):
				if pt is Array and (pt as Array).size() >= 3:
					lowest = minf(lowest, float(pt[1]))
	for c in sc.get("climbables", []):
		if c is Dictionary and c.get("foot_ground", null) is Array:
			lowest = minf(lowest, WorldSidecars.vec3(c.foot_ground).y)
	def.kill_y = float(sc.kill_y) if sc.has("kill_y") else lowest - tuning.num("fall_recovery", "kill_y_margin_m")
	var cams: Dictionary = sc.get("cameras", {}) if sc.get("cameras", null) is Dictionary else {}
	var gcam: Dictionary = cams.get("gameplay", {}) if cams.get("gameplay", null) is Dictionary else {}
	var cam_override: Dictionary = tuning.map_override(def.map_id).get("camera", {}) \
		if tuning.map_override(def.map_id).get("camera", null) is Dictionary else {}
	var scale := float(cam_override.get("ortho_size_scale", 1.0))
	def.ortho_size = float(gcam.get("godot_size_keep_width", gcam.get("gameplay_scale", 0.0))) * scale
	def.environment_configuration["ortho_size"] = def.ortho_size
	def.environment_configuration["ortho_size_keep_height"] = float(gcam.get("godot_size_keep_height", 0.0)) * scale
	def.environment_configuration["camera_pitch_deg"] = float(gcam.get("pitch_down_deg", 0.0))
	def.environment_configuration["camera_forward"] = WorldSidecars.vec3(gcam.get("forward", null))
	def.environment_configuration["camera_xform"] = WorldSidecars.xform(gcam.get("xform", null))
	if sidecars != null:
		def.content_hash = String(sidecars.content_hash(def.slug).get("collision", ""))
	for sp in sc.get("spawn_points", []):
		if sp is Dictionary and String(sp.get("species", "")) != "" and String(sp.get("proxy", "")) != "":
			def.species_proxies[String(sp.species)] = String(sp.proxy)
	# Authored spawn_regions win; the derived per-tier spawn_areas are the fallback (blender_export.md).
	var area_key := "spawn_regions" if (sc.get("spawn_regions", []) is Array and not (sc.get("spawn_regions", []) as Array).is_empty()) else "spawn_areas"
	for a in sc.get(area_key, []):
		if a is Dictionary:
			def.spawn_areas.append(_parse_area(a, def))


## One exported spawn area / region -> {name, species, polygon, surface_y, weight, y_lo, y_hi, exclude}. `exclude`
## holds the region's authored avoid zones (sidecar exclude_xz, world XZ polygons: Blender m.mobs(avoid=...)), which
## SpawnSlotPlanner keeps slots out of.
func _parse_area(a: Dictionary, def: MapDefinition) -> Dictionary:
	var species := PackedStringArray()
	var sv: Variant = a.get("species", a.get("mobs", null))
	if sv is String and String(sv) != "":
		species.append(String(sv))
	elif sv is Array:
		for x in sv:
			species.append(str(x))
	var poly := WorldSidecars.poly_xz(a.get("polygon_xz", a.get("outline_xz", a.get("polygon", []))))
	var weight := float(a.get("points", 0))
	if weight <= 0.0:
		weight = float(a.get("area_m2", 0.0))
	if weight <= 0.0 and poly.size() >= 3:
		weight = absf(_polygon_area(poly))
	var area_name := String(a.get("ground", a.get("name", "area")))
	if not species.is_empty():
		area_name += "/" + ",".join(species)
	var band: Variant = a.get("y_band", null)
	var has_band := band is Array and (band as Array).size() >= 2 and band[0] != null and band[1] != null
	var exclude: Array[PackedVector2Array] = []
	for ex in a.get("exclude_xz", []):
		var ep := WorldSidecars.poly_xz(ex)
		if ep.size() >= 3:
			exclude.append(ep)
	return {"name": area_name, "species": species, "polygon": poly,
		"surface_y": float(a.get("surface_y", a.get("y", def.base_y))), "weight": maxf(weight, 0.0001),
		"y_lo": float(band[0]) if has_band else NAN, "y_hi": float(band[1]) if has_band else NAN, "exclude": exclude}


func _apply_portal_marker(pd: PortalDef, marker: Dictionary, def: MapDefinition) -> void:
	pd.anchor_transform = WorldSidecars.marker_xform(marker)
	pd.has_anchor = true
	pd.anchor_ground = pd.anchor_transform.origin
	pd.provenance["v8_to_portal"] = String(marker.get("to_portal", "")) if marker.get("to_portal", null) != null else ""
	pd.provenance["v8_to_map"] = str(marker.get("to_map", ""))
	# A one-way portal names its destination's arrival anchor instead of a portal (blender_export.md: to_arrival).
	pd.provenance["v8_to_arrival"] = String(marker.get("to_arrival", "")) if marker.get("to_arrival", null) != null else ""
	pd.portal_type = PortalDef.TYPE_DOOR if String(marker.get("kind", "edge")) == "door" else PortalDef.TYPE_EDGE
	var n: Variant = marker.get("anchor_normal_xz", null)
	if n is Array and (n as Array).size() >= 2 and Vector2(float(n[0]), float(n[1])).length() > 0.001:
		pd.inward = -Vector3(float(n[0]), 0.0, float(n[1])).normalized()
	else:
		var facing := pd.anchor_transform.basis.z
		facing.y = 0.0
		pd.inward = facing.normalized() if facing.length() > 0.001 else Vector3.BACK
	# Iteration One drew v8 arrival-only points with Portal_Arrival; MeowDB says they are ordinary visible portals.
	var visual := String(marker.get("visual", ""))
	if pd.hidden:
		pd.visual = ""
	elif visual == "" or visual == "Portal_Arrival":
		pd.visual = "Portal_Door" if pd.portal_type == PortalDef.TYPE_DOOR else "Portal_Swirl"
	else:
		pd.visual = visual
	var v8_map := str(marker.get("to_map", ""))
	if v8_map != "" and id_of_v8.has(v8_map) and String(id_of_v8[v8_map]) != pd.destination_map_id:
		errors.append("%s: MeowDB leads to %s but the Blender marker leads to v8 %s (%s)" % [pd.key(),
			pd.destination_map_id, v8_map, String(id_of_v8[v8_map])])


func _add_arrival_gates() -> void:
	var section := tuning.portal_section("arrival_gates")
	for g in section.get("gates", []):
		if not (g is Dictionary):
			continue
		var gd: Dictionary = g
		var def := get_def(String(gd.get("map_id", "")))
		if def == null:
			errors.append("arrival gate %s names unknown map %s" % [String(gd.get("portal_id", "")), String(gd.get("map_id", ""))])
			continue
		if String(gd.get("reason", "")) == "":
			errors.append("arrival gate %s has no reason" % String(gd.get("portal_id", "")))
		var pd := PortalDef.new()
		pd.portal_id = String(gd.get("portal_id", ""))
		pd.source_map_id = def.map_id
		pd.portal_type = PortalDef.TYPE_ARRIVAL
		pd.canonical_type = -1
		pd.interaction_type = PortalDef.INTERACT_WALK_ONLY
		pd.hidden = true
		pd.trigger_size = tuning.trigger_size()
		pd.provenance = {"source_portal": String(gd.get("source_portal", "")), "adaptation_reason": String(gd.get("reason", "")),
			"anchor_marker": String(gd.get("anchor_marker", "")), "spawn_index": int(gd.get("spawn_index", 0))}
		var anchors: Array = []
		anchors.append_array(def.sidecar.get("arrival_points", []))
		anchors.append_array(def.sidecar.get("portals", []))
		for m in anchors:
			if pd.has_anchor:
				break
			if m is Dictionary and String(m.get("name", "")) == pd.provenance.anchor_marker:
				pd.anchor_transform = WorldSidecars.marker_xform(m)
				pd.anchor_ground = pd.anchor_transform.origin
				pd.has_anchor = true
				var n: Variant = m.get("anchor_normal_xz", null)
				if n is Array and (n as Array).size() >= 2:
					pd.inward = -Vector3(float(n[0]), 0.0, float(n[1])).normalized()
		def.portals.append(pd)
		graph.add_portal(pd)


## v8 cross-check (section 4.4): a canonical portal's resolved destination must equal Iteration One's v8 to_portal,
## or, for a player-spawn resolution, v8 must name the anchor of the destination's arrival gate.
func _check_v8_names() -> void:
	for p in graph.canonical_portals():
		var v8 := String(p.provenance.get("v8_to_portal", ""))
		if v8 == "":
			v8 = String(p.provenance.get("v8_to_arrival", ""))
		if not p.has_anchor:
			continue
		var ok := false
		if p.destination_portal_id != "":
			ok = v8 == p.destination_portal_id
		else:
			for q in graph.portals_of(p.destination_map_id):
				if q.portal_type == PortalDef.TYPE_ARRIVAL and String(q.provenance.get("source_portal", "")) == p.key() \
						and String(q.provenance.get("anchor_marker", "")) == v8:
					ok = true
		p.provenance["v8_name_match"] = ok
		if not ok:
			errors.append("%s resolves to %s but Iteration One's v8 to_portal is '%s'" % [p.key(),
				p.destination_portal_id if p.destination_portal_id != "" else "player_spawns[%d]" % p.destination_spawn_index, v8])


func _compute_spawn_transforms() -> void:
	var inset := tuning.portal_num("arrival", "inset_m")
	for id in ids():
		var def := get_def(id)
		for p in def.portals:
			if p.portal_type == PortalDef.TYPE_ARRIVAL:
				p.spawn_transform = def.player_spawn(int(p.provenance.get("spawn_index", 0)))
			elif p.has_anchor:
				p.spawn_transform = Transform3D(MapDefinitions.facing_basis(p.inward), p.anchor_transform.origin + p.inward * inset)


## A Y-up basis whose +Z (Vector3.MODEL_FRONT) looks along `dir` on the ground plane.
static func facing_basis(dir: Vector3) -> Basis:
	var f := Vector3(dir.x, 0.0, dir.z)
	if f.length_squared() < 0.000001:
		return Basis.IDENTITY
	f = f.normalized()
	var x := Vector3.UP.cross(f).normalized()
	return Basis(x, Vector3.UP, f)


func _place_npcs(def: MapDefinition, rec: Dictionary, sc: Dictionary) -> void:
	var markers := {}
	var by_meowdb := {}
	for m in sc.get("npcs", []):
		if m is Dictionary:
			markers[_norm(String(m.get("name", "")))] = m
			if m.get("meowdb_npc_id", null) != null and str(m.meowdb_npc_id) != "":
				by_meowdb[str(m.meowdb_npc_id)] = _norm(String(m.get("name", "")))
	var used := {}
	var k := 0
	for n in rec.get("npcs", []):
		if not (n is Dictionary):
			continue
		var pl := NpcPlacement.new()
		pl.npc_id = str(n.get("id", ""))
		pl.npc_name = String(n.get("name", ""))
		pl.map_id = def.map_id
		var key: String = by_meowdb.get(pl.npc_id, _norm(pl.npc_name))
		if markers.has(key) and not used.has(key):
			var mk: Dictionary = markers[key]
			pl.transform = WorldSidecars.marker_xform(mk)
			pl.proxy = String(mk.get("proxy", "")) if String(mk.get("proxy", "")) != "" else "NPC_" + _alnum(pl.npc_name)
			pl.from_marker = true
			used[key] = true
			npc_report["matched"] = int(npc_report.matched) + 1
		else:
			pl.proxy = "NPC_" + _alnum(pl.npc_name)
			pl.from_marker = false
			k += 1
			if def.has_markers:
				pl.transform = _npc_fallback(def, k, 0)
				var msg := "%s: no Blender NPC marker for MeowDB NPC %s (%s); placed next to player_spawns[0] (MAP_ARCHITECTURE section 3.3)" % [
					def.map_id, pl.npc_name, pl.npc_id]
				warnings.append(msg)
				push_warning("[MapDefinitions] " + msg)
			(npc_report.missing_markers as Array).append({"map_id": def.map_id, "npc_id": pl.npc_id, "name": pl.npc_name})
		pl.set_meta("fallback_rank", k if not pl.from_marker else 0)
		def.npc_definitions.append(pl)
	for key in markers:
		if not used.has(key):
			var mk: Dictionary = markers[key]
			(npc_report.extra_markers as Array).append({"map_id": def.map_id, "name": String(mk.get("name", "")),
				"sidecar_npc_id": str(mk.get("npc_id", ""))})


## Fallback NPC spot: player_spawns[0] moved `rank` x npc.fallback_spacing_m along one of the map frame's four
## ground directions (`dir_index` 0..3), facing the spawn point.
func _npc_fallback(def: MapDefinition, rank: int, dir_index: int) -> Transform3D:
	var spacing := tuning.num("npc", "fallback_spacing_m")
	var base := def.player_spawn(0).origin
	var dirs := [def.frame.basis.x, -def.frame.basis.x, def.frame.basis.z, -def.frame.basis.z]
	var d: Vector3 = dirs[posmod(dir_index, 4)]
	d.y = 0.0
	d = d.normalized()
	var pos := base + d * spacing * rank
	return Transform3D(MapDefinitions.facing_basis(-d), pos)


## NPC markers are authored positions: snapped to the ground under them, never moved. Fallback NPCs (no marker)
## are settled like arrivals: grounded, clear, inside the map, outside triggers.
func _ground_npc(def: MapDefinition, n: NpcPlacement, q: GroundQuery, up: float, down: float, out: PackedStringArray) -> void:
	if n.from_marker:
		var g := q.ground_at(n.transform.origin, up, down)
		n.grounded = bool(g.ok)
		if n.grounded:
			n.transform.origin.y = float(g.y)
		else:
			out.append("%s NPC %s marker is not on walkable ground (%s)" % [def.map_id, n.npc_name, String(g.get("note", ""))])
		return
	var s := settle(def, n.transform.origin, -n.transform.basis.z, q)
	n.grounded = bool(s.ok)
	if n.grounded:
		n.transform.origin = s.origin
	else:
		out.append("%s fallback NPC %s has no grounded, clear point (%s)" % [def.map_id, n.npc_name, String(s.note)])


static func _norm(s: String) -> String:
	return _alnum(s).to_lower()


static func _alnum(s: String) -> String:
	var out := ""
	for ch in s:
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


static func _polygon_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5
