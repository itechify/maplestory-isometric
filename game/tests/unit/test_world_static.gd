extends TestCase
## L1 static geometry (MAP_ARCHITECTURE.md section 4.13), headless and synchronous: the island's collision is loaded
## into the test runner's tree (no visuals) and probed with physics queries, which Jolt answers before the first
## physics step. Needs the Blender export (INCLUDE_WORLD=1); prints one SKIP line without it.
##
## Checks: the island builds with no error and no warning (no arrival, player spawn or NPC had to be moved to stand
## clear: the Blender source is clean, blender_export.md round 2); every portal arrival, player_spawns[0], NPC
## placement and spawn slot is grounded on walkable collision within grounding.grounded_tolerance_m, capsule-clear
## (a slot with a capsule as tall as its species), inside its own map, outside every other trigger and every spawn
## keep-out; collision layers are assigned; the containment rings are closed except at the gate gaps of edge-mode
## trails, the plugs close those gaps in warp mode, and the trail ribbons, gates, zones and side walls agree with the
## export (milestone M2: see _check_trails); no containment wall stands on an authored route, and region extensions
## join their map's ring (Southperry's ship, with the layout ring kept below the gangway).


## Trails that pass closer to another map's ring line than their half-width + side_wall_offset_m (that ring's wall
## stands on the ribbon). A Blender layout request each (WORLD_RUNTIME.md "Source world status"); any other is a
## failure.
const KNOWN_RING_CROWDING := {
	"T_000001000_in05__000001006_out00": "000001002",  # the plank bridge runs 1.04 m from 000001002's ring line
}


func test_l1_static_geometry() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_l1_static_geometry: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var tree := Engine.get_main_loop() as SceneTree
	var world := IslandWorld.new()
	world.name = "L1World"
	world.build_on_ready = false
	world.load_visuals = false
	world.attach_to_session = false
	# The runner's root is busy readying the main scene; the runner node itself accepts children.
	tree.current_scene.add_child(world)
	var t0 := Time.get_ticks_msec()
	world.build_now(db())
	print("L1 world built in %d ms: %s" % [Time.get_ticks_msec() - t0, str(world.stats)])
	_check(world)
	world.free()


func _check(world: IslandWorld) -> void:
	assert_eq(world.build_errors.size(), 0, "build errors: %s" % "; ".join(world.build_errors))
	for w in world.build_warnings:
		print("L1 warning: " + w)
	# The source world is clean: nothing is settled ("moved"), nothing unplaced or forced, no other warning.
	assert_eq(world.build_warnings.size(), 0, "build warnings: %s" % "; ".join(world.build_warnings))
	var moved := 0
	for w in world.build_warnings:
		if w.contains("moved") or w.contains("no grounded, clear point"):
			moved += 1
	assert_eq(moved, 0, "settled (moved) arrivals, player spawns or NPCs")
	var d := world.defs
	var q := world.ground_query
	var tol := d.tuning.num("grounding", "grounded_tolerance_m")
	var up := d.tuning.num("grounding", "probe_up_m")
	var down := d.tuning.num("grounding", "probe_down_m")
	var radius := d.tuning.num("grounding", "capsule_radius_m")
	var height := d.tuning.num("grounding", "capsule_height_m")
	var lift := d.tuning.num("grounding", "capsule_lift_m")
	assert_eq(world.portal_nodes.size(), 47, "one portal node per MeowDB portal")
	assert_eq(world.npc_nodes.size(), 21, "one NPC node per MeowDB NPC")
	assert_eq(world.rings.size(), 25, "one containment ring per map")
	_check_trails(world)
	assert_true(int(world.stats.get("collision_bodies", 0)) > 1000, "collision bodies loaded")
	_check_layers(world)
	var grounded_points := 0
	for id in d.ids():
		var def := d.get_def(id)
		var others: Array[PortalDef] = []
		for p in def.portals:
			if p.is_canonical():
				others.append(p)
		# Arrivals: every canonical portal's spawn_transform, and player_spawns[0].
		var points: Array[Dictionary] = [{"what": "%s player_spawns[0]" % id, "p": def.player_spawns[0].origin}]
		for p in def.canonical_portals():
			points.append({"what": "%s arrival" % p.key(), "p": p.spawn_transform.origin})
		for pt in points:
			var p3: Vector3 = pt.p
			var g := q.ground_at(p3, up, down)
			assert_true(bool(g.ok), "%s not grounded on walkable (%s)" % [pt.what, String(g.get("note", ""))])
			if bool(g.ok):
				assert_true(absf(float(g.y) - p3.y) <= tol, "%s is %.2f m off the ground" % [pt.what, absf(float(g.y) - p3.y)])
				grounded_points += 1
			var clear := q.is_clear(p3 + Vector3.UP * lift, radius, height)
			assert_true(clear, "%s capsule blocked by %s" % [pt.what, ", ".join(q.blockers(p3 + Vector3.UP * lift, radius, height))])
			assert_true(def.footprint_contains(p3), "%s outside its map" % pt.what)
			assert_eq(String(world.region_index.region_of(p3, id).get("id", "")), id, "%s region" % pt.what)
			for o in others:
				assert_false(o.trigger_contains(p3 + Vector3.UP * 0.1), "%s stands inside trigger %s" % [pt.what, o.key()])
		# NPCs.
		for n in def.npc_definitions:
			var g2 := q.ground_at(n.transform.origin, up, down)
			assert_true(n.grounded and bool(g2.ok), "%s NPC %s not grounded" % [id, n.npc_name])
			if bool(g2.ok):
				assert_true(absf(float(g2.y) - n.transform.origin.y) <= tol, "%s NPC %s off the ground" % [id, n.npc_name])
			assert_true(def.footprint_contains(n.transform.origin), "%s NPC %s outside its map" % [id, n.npc_name])
			if not n.from_marker:
				assert_true(q.is_clear(n.transform.origin + Vector3.UP * lift, radius, height), "%s fallback NPC %s blocked" % [id, n.npc_name])
		# Spawn slots.
		var region := SpawnSlotPlanner.mob_region(def, d.tuning)
		var mr := d.tuning.num("spawns", "clearance_radius_m")
		var keepouts := SpawnSlotPlanner.keepouts_of(def, d.tuning)
		var spacing := d.tuning.num("spawns", "slot_min_spacing_m")
		var clearance := d.tuning.num("spawns", "slot_portal_clearance_m")
		var arrivals: Array[Vector3] = [def.player_spawns[0].origin]
		for p in def.portals:
			arrivals.append(p.spawn_transform.origin)
		var slots := def.monster_spawn_definitions
		for i in slots.size():
			var s := slots[i]
			# Placed against real collision, every rule held (no "forced" best-effort or "unplaced" slot).
			assert_true(s.placement in ["strict", "relaxed", "pinned"], "%s slot %d placement %s" % [id, i, s.placement])
			for a in arrivals:
				assert_true(s.position().distance_to(a) >= clearance - 1e-4, "%s slot %d is %.2f m from an arrival" % [id, i, s.position().distance_to(a)])
			for j in range(i + 1, slots.size()):
				assert_true(s.position().distance_to(slots[j].position()) >= spacing - 1e-4,
					"%s slots %d and %d are %.2f m apart" % [id, i, j, s.position().distance_to(slots[j].position())])
		for s in def.monster_spawn_definitions:
			var g3 := q.ground_at(s.position(), up, down)
			assert_true(s.grounded and bool(g3.ok), "%s slot %d not grounded (%s)" % [id, s.index, s.placement])
			if bool(g3.ok):
				assert_true(absf(float(g3.y) - s.position().y) <= tol, "%s slot %d off the ground" % [id, s.index])
			var mh := d.clearance_height(s.mob_id)
			assert_true(q.is_clear(s.position(), mr, mh), "%s slot %d (%s, %.2f m body) blocked by %s" % [id, s.index, s.mob_id, mh,
				", ".join(q.blockers(s.position(), mr, mh))])
			assert_false(SpawnSlotPlanner.in_keepout(Vector2(s.position().x, s.position().z), keepouts), "%s slot %d inside a spawn keep-out" % [id, s.index])
			assert_true(Geometry2D.is_point_in_polygon(Vector2(s.position().x, s.position().z), region), "%s slot %d outside its mob region" % [id, s.index])
			for o in others:
				assert_false(o.trigger_contains(s.position() + Vector3.UP * 0.1), "%s slot %d inside trigger %s" % [id, s.index, o.key()])
	assert_eq(grounded_points, 47 + 25, "47 arrivals + 25 player_spawns[0] grounded")
	_check_rings(world)
	# Warp mode closes every gap: the plugs fill exactly what the gaps left open.
	world.defs.graph.set_link_mode("all", PortalDef.LINK_WARP)
	_check_rings(world)
	world.defs.graph.set_link_mode("all", PortalDef.LINK_EDGE)
	_check_rings(world)
	_check_region_extensions(world)
	# Routes with every trail mouth plugged (warp mode: the most containment there is), then the configured modes.
	world.defs.graph.set_link_mode("all", PortalDef.LINK_WARP)
	_check_routes_clear_of_containment(world)
	world.defs.apply_configured_link_modes()


## Every ring is closed except where an edge-mode trail's gate crosses it: points along each ring line (inside the
## wall's thickness, at mid-height) hit containment collision everywhere but inside the gaps, and inside a gap only
## while its plug is enabled (warp mode).
func _check_rings(world: IslandWorld) -> void:
	var d := world.defs
	var space := world.get_world_3d().direct_space_state
	var thickness := d.tuning.num("containment", "wall_thickness_m")
	var below := d.tuning.num("containment", "margin_below_m")
	var above := d.tuning.num("containment", "margin_above_m")
	var q := PhysicsPointQueryParameters3D.new()
	q.collision_mask = WorldLayers.CONTAINMENT
	var open_expected := 0
	var open_found := 0
	for id in d.ids():
		var def := d.get_def(id)
		if def.footprint.size() < 3:
			continue
		var gaps: Array[Dictionary] = []
		for key in world.ring_gaps:
			var gap: Dictionary = world.ring_gaps[key]
			if String(gap.map_id) == id:
				var g := d.trail(String(gap.link_id)).gate_into(id)
				gaps.append({"point": Vector2(g.origin.x, g.origin.z), "half": float(gap.half_width), "edge": d.graph.is_edge(g.link_id)})
		var side := ContainmentBuilder.outward_side(def.footprint)
		var y := ((def.y_min - below) + (def.y_max + above)) * 0.5
		var holes := 0
		var first_hole := ""
		for i in def.footprint.size():
			var a := def.footprint[i]
			var b := def.footprint[(i + 1) % def.footprint.size()]
			var dir := (b - a).normalized()
			var normal := ContainmentBuilder.edge_outward(def.footprint, i, side)
			var length := a.distance_to(b)
			var s := 0.1
			while s < length - 0.1:
				var p := a + dir * s
				var open := false
				var edge_of_gap := false
				for gap in gaps:
					var dg := p.distance_to(gap.point)
					if dg < float(gap.half) - 0.05:
						open = bool(gap.edge)
					elif dg < float(gap.half) + 0.05:
						edge_of_gap = true
				q.position = Vector3(p.x + normal.x * thickness * 0.5, y, p.y + normal.y * thickness * 0.5)
				var hit := not space.intersect_point(q, 1).is_empty()
				if edge_of_gap:
					pass
				elif open:
					open_expected += 1
					if not hit:
						open_found += 1
				elif not hit:
					holes += 1
					if first_hole == "":
						first_hole = " first at %s (edge %d, %.2f m along)" % [q.position, i, s]
				s += 0.25
		assert_eq(holes, 0, "%s ring has %d open samples outside the gate gaps (or a warp-mode plug is off)%s; gaps %s" % [id, holes, first_hole, str(gaps)])
	assert_eq(open_found, open_expected, "every gate gap of an edge-mode link is open (%d of %d samples)" % [open_found, open_expected])


## No containment wall stands on an authored route: a body-sized capsule (grounding capsule radius, from the player's
## step band (movement.json step_up_m) to the capsule height above each route point) touches no containment
## collision, with every trail mouth plugged. Before Southperry's region extension the 000000060 ring wall stood
## across the gangplank (Main, ShipDecks, ShipForecastle and ClimbMast run onto the ship, outside the layout).
func _check_routes_clear_of_containment(world: IslandWorld) -> void:
	var d := world.defs
	var space := world.get_world_3d().direct_space_state
	var radius := d.tuning.num("grounding", "capsule_radius_m")
	var height := d.tuning.num("grounding", "capsule_height_m")
	var step := 0.45
	var mv: Variant = db().miso_table("movement")
	if mv is Dictionary and (mv as Dictionary).has("step_up_m"):
		step = float(mv.step_up_m)
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(height - step, radius * 2.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collision_mask = WorldLayers.CONTAINMENT
	var points := 0
	var blocked := 0
	var first := ""
	for id in d.ids():
		for r in d.get_def(id).sidecar.get("routes", []):
			if not (r is Dictionary):
				continue
			for pt in r.get("points", []):
				var p := WorldSidecars.vec3(pt)
				q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * (step + capsule.height * 0.5))
				points += 1
				var hits := space.intersect_shape(q, 1)
				if not hits.is_empty():
					blocked += 1
					if first == "":
						first = " (first: %s/%s at %s, %s)" % [id, String(r.get("name", "?")), p, (hits[0].collider as Node).name]
	assert_true(points > 1000, "route points probed: %d" % points)
	assert_eq(blocked, 0, "%d route points have a containment wall within the body%s" % [blocked, first])


## Region extensions (maps/<id>.json region_extensions): the extension's ring line is part of the map's ring (its
## points outside the layout ring lie on the merged footprint's boundary), and where keep_footprint_ring_below_y is
## set the layout's own ring line under the extension still has its wall below that height and none above it.
func _check_region_extensions(world: IslandWorld) -> void:
	var d := world.defs
	var space := world.get_world_3d().direct_space_state
	var thickness := d.tuning.num("containment", "wall_thickness_m")
	var below := d.tuning.num("containment", "margin_below_m")
	var q := PhysicsPointQueryParameters3D.new()
	q.collision_mask = WorldLayers.CONTAINMENT
	var extended := 0
	for id in d.ids():
		var def := d.get_def(id)
		for ext: Dictionary in def.region_extensions:
			extended += 1
			var ring: PackedVector2Array = ext.ring_line
			for v in ring:
				if Geometry2D.is_point_in_polygon(v, def.footprint_base):
					continue
				var on := INF
				for k in def.footprint.size():
					var cp := Geometry2D.get_closest_point_to_segment(v, def.footprint[k], def.footprint[(k + 1) % def.footprint.size()])
					on = minf(on, cp.distance_to(v))
				assert_true(on < 0.01, "%s extension %s: ring vertex %s is %.3f m off the map's ring line" % [id, String(ext.name), v, on])
			var top := float(ext.keep_ring_below_y)
			if is_nan(top):
				continue
			var y0 := def.y_min - below
			var base := def.footprint_base
			var side := ContainmentBuilder.outward_side(base)
			var low_hits := 0
			var high_hits := 0
			var samples := 0
			for i in base.size():
				var normal := ContainmentBuilder.edge_outward(base, i, side)
				var a := base[i]
				var b := base[(i + 1) % base.size()]
				for seg: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), ring):
					var s0 := seg[0]
					var s1 := seg[seg.size() - 1]
					var length := s0.distance_to(s1)
					var t := 0.3
					while t < length - 0.3:
						var p := s0.lerp(s1, t / length) + normal * thickness * 0.5
						samples += 1
						q.position = Vector3(p.x, (y0 + top) * 0.5, p.y)
						if not space.intersect_point(q, 1).is_empty():
							low_hits += 1
						q.position = Vector3(p.x, top + 1.0, p.y)
						if not space.intersect_point(q, 1).is_empty():
							high_hits += 1
						t += 0.25
			assert_true(samples > 10, "%s extension %s opens the layout ring (%d samples)" % [id, String(ext.name), samples])
			assert_eq(low_hits, samples, "%s extension %s: the layout ring keeps its wall below %.1f m (%d of %d)" % [id, String(ext.name), top, low_hits, samples])
			assert_eq(high_hits, 0, "%s extension %s: the layout ring is open above %.1f m (%d of %d closed)" % [id, String(ext.name), top, high_hits, samples])
	assert_true(extended >= 1, "Southperry's ship extension is loaded")


## Milestone M2 trails (MAP_ARCHITECTURE sections 4.3, 4.4, 4.6): every trail link has a ribbon and two gates; each
## gate lies on its map's ring line, across the trail's cap; the one-way ledge's gate is the sidecar's gate plane;
## the ribbon is outside every map region between the gates and inside its own zone; kill_y covers the trails; the
## side walls leave the ribbon free and stand beside it; a ring gap is never wider than the corridor between them.
func _check_trails(world: IslandWorld) -> void:
	var d := world.defs
	var trails := d.trail_list()
	assert_eq(trails.size(), 20, "one TrailDef per trail link")
	assert_eq(world.trail_walls.size(), 20, "side walls for every trail")
	assert_eq(world.plugs.size(), 40, "one plug per gate (39 portal gates + the arrival gate)")
	var side := d.tuning.num("trails", "side_wall_offset_m")
	var margin := d.tuning.num("fall_recovery", "kill_y_margin_m")
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	q.shape = probe
	q.collision_mask = WorldLayers.CONTAINMENT
	for t in trails:
		assert_true(t.has_geometry(), "%s has a ribbon" % t.link_id)
		if not t.has_geometry():
			continue
		assert_eq(t.source, "mesh", "%s ribbon derived from the export's trail mesh (no sidecar centreline yet)" % t.link_id)
		for i in 2:
			var g := t.gates[i]
			assert_true(g != null, "%s gate into %s" % [t.link_id, t.maps[i]])
			if g == null:
				continue
			var def := d.get_def(g.map_id)
			var on_ring := INF
			for k in def.footprint.size():
				var pt := Geometry2D.get_closest_point_to_segment(Vector2(g.origin.x, g.origin.z), def.footprint[k],
					def.footprint[(k + 1) % def.footprint.size()])
				on_ring = minf(on_ring, pt.distance_to(Vector2(g.origin.x, g.origin.z)))
			assert_true(on_ring < 0.01, "%s gate into %s is %.3f m off the ring line" % [t.link_id, g.map_id, on_ring])
			var cap := t.centre[0] if i == 0 else t.centre[t.centre.size() - 1]
			if not (t.link_id == "T_000001000_in05__000001006_out00" and i == 1):
				assert_true(absf(g.lateral_offset(cap)) < 0.1, "%s cap at %s is %.2f m off its gate's centre" % [t.link_id, g.map_id, g.lateral_offset(cap)])
			assert_true(g.normal.dot(g.portal.inward) > 0.999, "%s gate normal = the portal's inward" % t.link_id)
		# Between the gates the ribbon lies in no map region, and always in its own zone.
		for c in t.centre:
			assert_true(t.zone_contains(c), "%s centreline point %s outside its zone" % [t.link_id, c])
			var between := t.gates[0].signed_distance(c) < -0.3 and t.gates[1].signed_distance(c) < -0.3
			if between:
				assert_true(world.region_index.maps_at(c + Vector3.UP * 0.1).is_empty(), "%s point %s between the gates lies in map %s" % [
					t.link_id, c, world.region_index.maps_at(c)])
		# Another map's ring wall must not stand on the ribbon (only the known, requested layout fix).
		for id in d.ids():
			if t.touches(id):
				continue
			var def2 := d.get_def(id)
			var crowd := INF
			for c in t.centre:
				if c.y < def2.y_min - 2.0 or c.y > def2.y_max + 4.0:
					continue
				for k in def2.footprint.size():
					var cp := Geometry2D.get_closest_point_to_segment(Vector2(c.x, c.z), def2.footprint[k], def2.footprint[(k + 1) % def2.footprint.size()])
					crowd = minf(crowd, cp.distance_to(Vector2(c.x, c.z)))
			if crowd < t.half_widths[0] + side:
				assert_eq(String(KNOWN_RING_CROWDING.get(t.link_id, "")), id, "%s passes %.2f m from %s's ring line (its wall stands on the ribbon)" % [t.link_id, crowd, id])
		for m in t.maps:
			assert_true(d.get_def(m).kill_y <= t.y_lo - margin + 0.001, "%s kill_y %.2f above trail %s low %.2f" % [m, d.get_def(m).kill_y, t.link_id, t.y_lo])
		# Side walls along the ribbon's own edges: nothing on the ribbon (a probe touching each edge from inside, 1 m
		# up), a wall just outside it (a probe past side_wall_offset_m).
		var free := 0
		var walled := 0
		var samples := 0
		var blocked_at := ""
		for edge_line in [t.side_a, t.side_b]:
			for e: Vector3 in (edge_line as PackedVector3Array):
				if t.gates[0].signed_distance(e) > -1.5 or t.gates[1].signed_distance(e) > -1.5:
					continue
				var n := t.nearest(e)
				var c: Vector3 = n.point
				var out := Vector3(e.x - c.x, 0.0, e.z - c.z)
				if out.length() < 0.5:
					continue  # a fold remnant, not an edge point
				out = out.normalized()
				samples += 1
				q.transform = Transform3D(Basis.IDENTITY, e - out * 0.25 + Vector3.UP * 1.0)
				var own := true
				for hit in space.intersect_shape(q, 4):
					var nm := String((hit.collider as Node).name)
					if nm.begins_with("Walls_"):
						own = false
						if blocked_at == "":
							blocked_at = " (first at %s by %s)" % [e, nm]
				if own:
					free += 1
				q.transform = Transform3D(Basis.IDENTITY, e + out * (side + 0.25) + Vector3.UP * 1.0)
				if not space.intersect_shape(q, 1).is_empty():
					walled += 1
		assert_eq(free, samples, "%s: a side wall stands on the ribbon (%d of %d probes free)%s" % [t.link_id, free, samples, blocked_at])
		assert_true(walled >= samples - 2, "%s: walls missing beside the ribbon (%d of %d probes hit)" % [t.link_id, walled, samples])
	# The one-way ledge: 000000040's arrival gate is the sidecar's gate plane (section 4.4, within the ledge tolerance).
	var ledge_trail := d.trail("T_000000030_out00__000000040")
	var g40 := ledge_trail.gate_into("000000040")
	var tol := d.tuning.portal_num("one_way_ledge", "gate_plane_tolerance_m")
	for lg in d.get_def("000000040").sidecar.get("ledges", []):
		var plane: Dictionary = lg.get("gate_plane", {})
		var pt := WorldSidecars.vec3(plane.get("point", null))
		assert_true(absf(g40.signed_distance(pt)) <= tol, "the 40 arrival gate is %.3f m off the ledge's gate plane" % absf(g40.signed_distance(pt)))
		var n: Array = plane.get("outward_normal_xz", [0, 0])
		assert_true(g40.normal.dot(-Vector3(float(n[0]), 0.0, float(n[1]))) > 0.999, "the 40 arrival gate faces into 40")
	assert_true(g40.source_portal != null and g40.source_portal.key() == "000000030.out00", "walking down the ledge commits 30.out00")
	assert_true(ledge_trail.gate_into("000000030").source_portal == null, "no way back into 30 through the trail")
	# Ring gaps are no wider than the corridor between the side walls (no slot beside a wall).
	for key in world.ring_gaps:
		var gap: Dictionary = world.ring_gaps[key]
		var t2 := d.trail(String(gap.link_id))
		var g2 := t2.gate_into(String(gap.map_id))
		var n2 := t2.nearest(g2.origin)
		assert_true(float(gap.half_width) <= minf(g2.half_width, float(n2.half) + side) + 0.001, "%s gap %.2f m is wider than its corridor" % [key, float(gap.half_width)])


func _check_layers(world: IslandWorld) -> void:
	var counts := {}
	for body in world.collision_root.find_children("*", "StaticBody3D", true, false):
		var layer := (body as StaticBody3D).collision_layer
		counts[layer] = int(counts.get(layer, 0)) + 1
	assert_true(int(counts.get(WorldLayers.WALKABLE, 0)) >= 26, "walkable ground bodies (25 maps + trails): %s" % str(counts))
	assert_true(int(counts.get(WorldLayers.BLOCKING, 0)) > 100, "blocking bodies")
	assert_true(int(counts.get(WorldLayers.SCENERY, 0)) > 0, "scenery bodies")
	for layer in counts:
		assert_true(int(layer) in [WorldLayers.WALKABLE, WorldLayers.BLOCKING, WorldLayers.SCENERY], "unexpected layer %d" % int(layer))
