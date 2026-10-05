extends TestCase
## The reachability check (game/tools/reach_check.gd; brief Phase 6 "avoid unreachable terrain"): every NPC talk zone,
## monster spawn slot, Wooden Box placement and portal trigger of every map can be reached on foot from the map's
## entries, proven on the stuck-region scan's graph with edges the controller can certainly take.
##
## Model tests on hand-made worlds (PlayerTestWorld boxes, no export needed): a 1 m ledge is reached by a certified
## hop; two 0.9 m steps by two hops on one path; a 2.4 m plateau with no way up is not; a ladder makes it reachable;
## the arc check refuses a hop through a wall and never climbs by walking off.
## The island test (INCLUDE_WORLD=1; a SKIP line without the export) scans all 25 maps and fails on any target no
## proof reaches; every canonical portal and spawn slot must be a target (counted from the canonical records), and a
## portal without an anchor fails rather than dropping out. REACH_REPORT_OUT=<file> also writes the report document.

const AREA_HALF := 8.0


func parity_keys() -> Dictionary:
	var keys := ["mechanic:stuck-region-scan"]
	for id in ["000000001", "000000010", "000000020", "000000021", "000000030", "000000040", "000000041", "000000042",
			"000000050", "000000060", "000000061", "000001000", "000001001", "000001002", "000001003", "000001004",
			"000001005", "000001006", "000001010", "000001011", "000001012", "000001013", "000001014", "000001020",
			"000001021"]:
		keys.append("map:" + id)
	return {
		"test_every_npc_slot_box_and_portal_is_reachable": keys,
		"test_a_one_metre_ledge_is_reached_by_a_certified_hop": ["mechanic:stuck-region-scan"],
		"test_a_plateau_with_no_way_up_is_unreachable": ["mechanic:stuck-region-scan"],
		"test_a_ladder_makes_the_plateau_reachable": ["mechanic:stuck-region-scan"],
		"test_two_ledges_are_climbed_hop_by_hop": ["mechanic:stuck-region-scan"],
		"test_the_arc_check_refuses_a_hop_through_a_wall": ["mechanic:stuck-region-scan"],
	}


# --- model tests ----------------------------------------------------------------------------------------------------

func test_a_one_metre_ledge_is_reached_by_a_certified_hop() -> void:
	var w := _ground_world()
	w.add_box(Vector3(3.0, 0.5, 0.0), Vector3(3.0, 1.0, 4.0))  # top at 1.0 m, x 1.5..4.5
	var r := _scan(w, [])
	var g: StuckScan.MapGraph = r.graph
	var check: ReachCheck = r.check
	var top := g.node_near(Vector3(3.5, 1.0, 0.0), 0.3, 0.3, 1)
	assert_true(top >= 0, "the ledge top is a node")
	var res := check.prove(g, _start(g), PackedInt32Array([top]))
	assert_true(bool(res.ok), "a 1 m ledge is within a jump: %s" % str(res))
	assert_true(int(res.into_edges) >= 1, "proven through a certified hop (%d)" % int(res.into_edges))
	w.free_all()


## Two steps of 0.9 m (1.8 m in all, above any single jump): the top is proven hop by hop, two certified hops on one
## path (the search keeps every uncertified edge of a multi-level path).
func test_two_ledges_are_climbed_hop_by_hop() -> void:
	var w := _ground_world()
	w.add_box(Vector3(2.5, 0.45, 0.0), Vector3(2.0, 0.9, 4.0))  # x 1.5..3.5, top 0.9
	w.add_box(Vector3(4.5, 0.9, 0.0), Vector3(2.0, 1.8, 4.0))  # x 3.5..5.5, top 1.8
	var r := _scan(w, [])
	var g: StuckScan.MapGraph = r.graph
	var top := g.node_near(Vector3(5.0, 1.8, 0.0), 0.3, 0.3, 1)
	assert_true(top >= 0, "the upper ledge is a node")
	var res := (r.check as ReachCheck).prove(g, _start(g), PackedInt32Array([top]))
	assert_true(bool(res.ok), "up the steps: %s" % str(res))
	# The scan may have refined a certain jump for one step; with those set aside both steps are into edges, and one
	# path must carry both, each certified.
	g.extra = {}
	g.extra_rev = {}
	var mid := g.node_near(Vector3(2.5, 0.9, 0.0), 0.3, 0.3, 1)
	var check := ReachCheck.create(r.scan)  # nothing certified yet
	assert_eq(check._closure(g, _start(g))[mid], 0, "the lower step is not certain without a jump")
	var found := check._search(g, check._closure(g, _start(g)), _goal_set(g, top))
	assert_eq((found.path as Array).size(), 2, "the best path carries both hops: %s" % str(found.path))
	res = check.prove(g, _start(g), PackedInt32Array([top]))
	assert_true(bool(res.ok), "two hops: %s" % str(res))
	assert_eq(int(res.into_edges), 2, "through two certified hops")
	w.free_all()


func test_a_plateau_with_no_way_up_is_unreachable() -> void:
	var w := _ground_world()
	w.add_box(Vector3(3.5, 1.2, 0.0), Vector3(3.0, 2.4, 4.0))  # top at 2.4 m
	var r := _scan(w, [])
	var g: StuckScan.MapGraph = r.graph
	var top := g.node_near(Vector3(3.5, 2.4, 0.0), 0.3, 0.3, 1)
	assert_true(top >= 0, "the plateau top is a node")
	var res := (r.check as ReachCheck).prove(g, _start(g), PackedInt32Array([top]))
	assert_false(bool(res.ok), "2.4 m is above any jump: %s" % str(res))
	assert_ne(String(res.why), "", "says why")
	w.free_all()


func test_a_ladder_makes_the_plateau_reachable() -> void:
	var w := _ground_world()
	w.add_box(Vector3(3.5, 1.2, 0.0), Vector3(3.0, 2.4, 4.0))  # top at 2.4 m, x 2..5
	var ladder := ClimbableDef.from_sidecar({"name": "PlateauLadder", "kind": "ladder", "descend_only": false,
		"bottom": [1.95, 0.0, 0.0], "top": [1.95, 2.4, 0.0], "foot_ground": [1.65, 0.0, 0.0],
		"top_exit": [2.5, 2.4, 0.0], "facing_xz": [1.0, 0.0]})
	var r := _scan(w, [ladder])
	var g: StuckScan.MapGraph = r.graph
	var top := g.node_near(Vector3(3.5, 2.4, 0.0), 0.3, 0.3, 1)
	var res := (r.check as ReachCheck).prove(g, _start(g), PackedInt32Array([top]))
	assert_true(bool(res.ok), "up the ladder: %s" % str(res))
	assert_eq(int(res.into_edges), 0, "certain edges only (the ladder)")
	w.free_all()


## The arc check: a running jump from the ground in front of a 0.7 m ledge lands on it, walking off never climbs, and
## once a wall taller than any jump stands between them no jump from that ground lands there (whatever the scan's
## L-shaped hop sweep says).
func test_the_arc_check_refuses_a_hop_through_a_wall() -> void:
	var w := _ground_world()
	w.add_box(Vector3(3.0, 0.35, 0.0), Vector3(3.0, 0.7, 4.0))  # a 0.7 m ledge, x 1.5..4.5
	var r := _scan(w, [])
	var pairs := _hops_onto_ledge(r, 0.7)
	assert_true(pairs > 0, "a running jump from the ground lands on the ledge")
	var g: StuckScan.MapGraph = r.graph
	var check: ReachCheck = r.check
	var below := g.node_near(Vector3(1.0, 0.0, 0.0), 0.3, 0.3, 1)
	var top := g.node_near(Vector3(2.2, 0.7, 0.0), 0.3, 0.3, 1)
	assert_false(check.arc_lands(g, g.node_pos[below], g.node_pos[top], 0.0), "walking off never climbs")
	w.add_box(Vector3(1.4, 2.0, 0.0), Vector3(0.2, 4.0, 15.0))  # a 4 m wall along the ledge's face
	r = _scan(w, [])
	assert_eq(_hops_onto_ledge(r, 0.7), 0, "the wall stops every jump")
	w.free_all()


## How many (ground node, ledge-top node) pairs within 2 m across the ledge face (x = 1.5) the arc check lands.
func _hops_onto_ledge(r: Dictionary, top_y: float) -> int:
	var g: StuckScan.MapGraph = r.graph
	var check: ReachCheck = r.check
	var n := 0
	for gx in [0.3, 0.6, 0.9]:
		var a := g.node_near(Vector3(gx, 0.0, 0.0), 0.3, 0.3, 1)
		if a < 0:
			continue
		for tx in [1.9, 2.2, 2.5]:
			var b := g.node_near(Vector3(tx, top_y, 0.0), 0.3, 0.3, 1)
			if b >= 0 and check.arc_lands(g, g.node_pos[a], g.node_pos[b], check.model.jump_velocity):
				n += 1
	return n


# --- the island -----------------------------------------------------------------------------------------------------

func test_every_npc_slot_box_and_portal_is_reachable() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_every_npc_slot_box_and_portal_is_reachable: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var tree := Engine.get_main_loop() as SceneTree
	var world := IslandWorld.new()
	world.name = "ReachWorld"
	world.build_on_ready = false
	world.load_visuals = false
	world.attach_to_session = false
	tree.current_scene.add_child(world)
	world.build_now(db())
	var check := ReachCheck.create(StuckScan.create(world, db()))
	var doc := check.run()
	var t: Dictionary = doc.totals
	var by_kind := {}
	for id: String in (doc.maps as Dictionary):
		var row: Dictionary = doc.maps[id]
		var counts := {}
		for target: Dictionary in row.targets:
			counts[target.kind] = int(counts.get(target.kind, 0)) + 1
			by_kind[target.kind] = int(by_kind.get(target.kind, 0)) + 1
		print("REACH %s %s: %d targets %s, %d entries, %d unreachable, %d certified edges, %d replays (%d ms)" % [
			id, row.name, (row.targets as Array).size(), str(counts), int(row.entries), (row.unreachable as Array).size(),
			int(row.certified), int(row.replays), int(row.ms)])
		assert_true(int(row.entries) > 0, "%s: the map has entries on the graph" % id)
	print("REACH totals: %d maps, %d targets %s, %d unreachable, %d certified edges, %d replays (%d ms)" % [int(t.maps),
		int(t.targets), str(by_kind), int(t.unreachable), int(t.certified_edges), int(t.replays), int(t.ms)])
	assert_eq(int(t.maps), 25, "every map checked")
	for kind in [ReachCheck.KIND_NPC, ReachCheck.KIND_SLOT, ReachCheck.KIND_BOX, ReachCheck.KIND_PORTAL]:
		assert_true(int(by_kind.get(kind, 0)) > 0, "the check found %s targets" % kind)
	assert_eq(int(by_kind.get(ReachCheck.KIND_NPC, 0)), 21, "every NPC")
	assert_eq(int(by_kind.get(ReachCheck.KIND_BOX, 0)), 19, "every Wooden Box placement")
	# Every canonical portal and spawn slot is a target, counted from the canonical records: none may drop out of the
	# proof (a portal the export lost is a failed target, see below), so the totals cannot shrink unnoticed.
	var canon_portals := 0
	var canon_slots := 0
	for id in world.defs.ids():
		var rec := db().map(id)
		canon_portals += (rec.get("portals", []) as Array).size()
		canon_slots += (rec.get("spawns", []) as Array).size()
	assert_eq(int(by_kind.get(ReachCheck.KIND_PORTAL, 0)), canon_portals, "every canonical portal (%d)" % canon_portals)
	assert_eq(int(by_kind.get(ReachCheck.KIND_SLOT, 0)), canon_slots, "every canonical spawn slot (%d)" % canon_slots)
	for bad: Dictionary in doc.unreachable:
		fail("%s %s %s (%s) at map-local %s is not reachable from the map's entries (%s): %s" % [bad.map_id, bad.kind,
			bad.id, bad.name, bad.local, bad.rule, bad.why])
	# The check says no on real geometry too: the one-column pocket of A Split Road that the stuck scan's real
	# controller could not get into (stuck_allowlist.json unenterable) is no place a player can be proven to reach.
	var g50 := check.scan.scan_map("000000050")
	var pocket := g50.node_near(g50.to_world(Vector3(48.37, 2.2, -28.03)), 0.3, 0.3, 1)
	assert_true(pocket >= 0, "the pocket's floor is a node")
	if pocket >= 0:
		var no := check.prove(g50, check.entries(g50), PackedInt32Array([pocket]))
		assert_false(bool(no.ok), "the unenterable pocket is not proven reachable: %s" % str(no))
	# A canonical portal the export placed nowhere fails the proof instead of dropping out of it.
	var lost: PortalDef = world.defs.get_def("000000050").canonical_portals()[0]
	lost.has_anchor = false
	var r50 := check.check(g50)
	lost.has_anchor = true
	var flagged := (r50.unreachable as Array).filter(func(row: Dictionary) -> bool:
		return String(row.kind) == ReachCheck.KIND_PORTAL and String(row.id) == lost.portal_id)
	assert_eq(flagged.size(), 1, "a portal without an anchor is an unreachable target: %s" % str(r50.unreachable))
	check.free_all()
	var out := OS.get_environment("REACH_REPORT_OUT")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(doc, "  ") + "\n")
	world.free()


# --- helpers ----------------------------------------------------------------------------------------------------------

## A flat 16 x 16 m ground, top at y = 0.
func _ground_world() -> PlayerTestWorld:
	var w := PlayerTestWorld.create(db())
	w.add_box(Vector3(0.0, -0.5, 0.0), Vector3(AREA_HALF * 2.0, 1.0, AREA_HALF * 2.0))
	return w


## Scans the 16 x 16 m area (entry at (-5, 0, 0)); returns the graph and a check over it.
func _scan(w: PlayerTestWorld, climbables: Array[ClimbableDef]) -> Dictionary:
	var scan := StuckScan.create_in(w.host, db(), {"host": w.host})
	var g := StuckScan.MapGraph.new()
	g.map_id = "test"
	g.name = "test"
	var a := AREA_HALF - 0.5
	g.polygons.append(PackedVector2Array([Vector2(-a, -a), Vector2(a, -a), Vector2(a, a), Vector2(-a, a)]))
	g.kill_y = -6.0
	g.y_top = 6.0
	g.entry_points.append(Vector3(-5.0, 0.0, 0.0))
	g.exit_boxes.append(AABB(Vector3(-6.0, -0.5, -1.0), Vector3(2.0, 2.0, 2.0)))
	g.climbables = climbables
	scan.scan(g)
	return {"scan": scan, "graph": g, "check": ReachCheck.create(scan)}


func _goal_set(g: StuckScan.MapGraph, n: int) -> PackedByteArray:
	var s := PackedByteArray()
	s.resize(g.node_count())
	s.fill(0)
	s[n] = 1
	return s


func _start(g: StuckScan.MapGraph) -> PackedInt32Array:
	return PackedInt32Array([g.node_near(Vector3(-5.0, 0.0, 0.0), 0.3, 0.3, 1)])
