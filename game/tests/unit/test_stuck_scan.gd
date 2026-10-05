extends TestCase
## The stuck-region scan (game/tools/stuck_scan.gd, docs/runtime/STUCK_SCAN.md).
##
## Model tests on hand-made worlds (PlayerTestWorld boxes, no export needed): a pit deeper than any jump is a
## CONFIRMED trap, a 1 m step is not, a ladder out of a pit makes it escapable, a descend-only rope does not, and a
## surface inside a closed solid is never a node.
##
## The island test (INCLUDE_WORLD=1; a SKIP line without the export) scans all 25 maps, verifies every flagged
## component with the real PlayerController and fails on any CONFIRMED trap that game/data/misostory/
## stuck_allowlist.json does not list (the allowlist holds only reviewed, intended dead ends). STUCK_REPORT_OUT=<file>
## also writes the report document (docs/runtime/stuck_report.json is that document, regenerated at milestones).

const PIT_HALF := 1.5
const AREA_HALF := 8.0


func parity_keys() -> Dictionary:
	var maps := ["mechanic:stuck-region-scan"]
	for id in ["000000001", "000000010", "000000020", "000000021", "000000030", "000000040", "000000041", "000000042",
			"000000050", "000000060", "000000061", "000001000", "000001001", "000001002", "000001003", "000001004",
			"000001005", "000001006", "000001010", "000001011", "000001012", "000001013", "000001014", "000001020",
			"000001021"]:
		maps.append("map:" + id)
	return {
		"test_every_map_has_no_unlisted_trap": maps,
		"test_a_deep_pit_is_a_confirmed_trap": ["mechanic:stuck-region-scan"],
		"test_a_one_metre_step_is_not_a_trap": ["mechanic:stuck-region-scan"],
		"test_a_ladder_out_of_a_pit_is_not_a_trap": ["mechanic:stuck-region-scan"],
		"test_a_descend_only_rope_out_of_a_pit_is_a_trap": ["mechanic:stuck-region-scan"],
		"test_a_surface_inside_a_solid_is_not_a_node": ["mechanic:stuck-region-scan"],
	}


# --- model tests ----------------------------------------------------------------------------------------------------

func test_a_deep_pit_is_a_confirmed_trap() -> void:
	var w := _pit_world(2.4)
	var r := _scan(w, [])
	var pit := _component_at(r.graph, Vector3(0.0, -2.4, 0.0))
	assert_false(pit.is_empty(), "the 2.4 m pit is flagged (components %s)" % str(_verdicts(r.graph)))
	if not pit.is_empty():
		assert_eq(String(pit.verdict), StuckScan.VERDICT_CONFIRMED, "the real controller gets in and not out")
		assert_true(bool(pit.entered), "the controller walked into the pit from its rim")
	w.free_all()


func test_a_one_metre_step_is_not_a_trap() -> void:
	var w := _pit_world(1.0)
	var r := _scan(w, [])
	# Escapable in the graph (a certain jump edge), or flagged and then cleared by the real controller.
	var pit := _component_at(r.graph, Vector3(0.0, -1.0, 0.0))
	assert_true(pit.is_empty() or String(pit.verdict) == StuckScan.VERDICT_CLEARED,
		"a 1.0 m step is climbed by a jump: %s" % str(_verdicts(r.graph)))
	for c: Dictionary in r.graph.components:
		assert_ne(String(c.verdict), StuckScan.VERDICT_CONFIRMED, "no trap: %s" % str(c.local))
	w.free_all()


func test_a_ladder_out_of_a_pit_is_not_a_trap() -> void:
	var w := _pit_world(2.4)
	var r := _scan(w, [_ladder(false)])
	assert_true(_component_at(r.graph, Vector3(0.0, -2.4, 0.0)).is_empty(),
		"a ladder from the pit floor to the rim makes it escapable: %s" % str(_verdicts(r.graph)))
	w.free_all()


func test_a_descend_only_rope_out_of_a_pit_is_a_trap() -> void:
	var w := _pit_world(2.4)
	var r := _scan(w, [_ladder(true)])
	var pit := _component_at(r.graph, Vector3(0.0, -2.4, 0.0))
	assert_false(pit.is_empty(), "a descend-only rope is no way out")
	if not pit.is_empty():
		assert_eq(String(pit.verdict), StuckScan.VERDICT_CONFIRMED, "the controller cannot climb a descend-only rope")
	w.free_all()


func test_a_surface_inside_a_solid_is_not_a_node() -> void:
	var w := PlayerTestWorld.create(db())
	w.add_box(Vector3(0.0, -0.5, 0.0), Vector3(AREA_HALF * 2.0, 1.0, AREA_HALF * 2.0))
	# A closed trimesh block (faces outward) on the ground, with a slab floating inside it: the slab's top is buried.
	_closed_trimesh_box(w, AABB(Vector3(-2.0, 0.0, -2.0), Vector3(4.0, 3.0, 4.0)))
	w.add_box(Vector3(0.0, 1.0, 0.0), Vector3(2.0, 0.2, 2.0))
	var r := _scan(w, [])
	var g: StuckScan.MapGraph = r.graph
	var c := g.column_at(0.0, 0.0)
	var heights := PackedFloat32Array()
	for k in g.col_count[c]:
		var n := g.surf_node[g.col_first[c] + k]
		if n >= 0:
			heights.append(g.node_pos[n].y)
	var top := false
	for y in heights:
		top = top or absf(y - 3.0) < 0.05
	assert_true(top, "the block's top is a node: %s" % heights)
	for y in heights:
		assert_false(absf(y - 1.1) < 0.05, "the slab inside the block is not a node: %s" % heights)
		assert_false(absf(y) < 0.05, "the ground under the block is not a node: %s" % heights)
	w.free_all()


# --- the island -----------------------------------------------------------------------------------------------------

func test_every_map_has_no_unlisted_trap() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_every_map_has_no_unlisted_trap: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var tree := Engine.get_main_loop() as SceneTree
	var world := IslandWorld.new()
	world.name = "StuckScanWorld"
	world.build_on_ready = false
	world.load_visuals = false
	world.attach_to_session = false
	tree.current_scene.add_child(world)
	world.build_now(db())
	var scan := StuckScan.create(world, db())
	var doc := scan.run()
	var t: Dictionary = doc.totals
	print("STUCK scan: %d maps, %d nodes, %d flagged in %d components: %d confirmed (%d allowlisted), %d cleared, %d unenterable (%d ms)" % [
		int(t.maps), int(t.nodes), int(t.flagged), int(t.components), int(t.confirmed), int(t.allowlisted), int(t.cleared),
		int(t.unenterable), int(t.ms)])
	assert_eq(int(t.maps), 25, "every map scanned")
	for trap: Dictionary in doc.traps:
		fail("%s: a trap (%d nodes, %.2f m2) at map-local %s, Blender-local xy %s, %.2f m below its way in %s: %s" % [trap.id,
			int(trap.nodes), float(trap.area_m2), trap.local, trap.blender_local_xy, float(trap.drop_m),
			trap.in_edges[0] if not (trap.in_edges as Array).is_empty() else "?", trap.get("enter_how", "")])
	for e in scan.allowlist:
		assert_true(e is Dictionary and String((e as Dictionary).get("reason", "")) != "", "every allowlist entry has a reason")
	var out := OS.get_environment("STUCK_REPORT_OUT")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(doc, "  ") + "\n")
	world.free()


# --- helpers ----------------------------------------------------------------------------------------------------------

## A flat 16 x 16 m ground (top y = 0) with a 3 x 3 m pit in the middle, its floor `depth` below.
func _pit_world(depth: float) -> PlayerTestWorld:
	var w := PlayerTestWorld.create(db())
	var a := AREA_HALF
	var h := PIT_HALF
	w.add_box(Vector3(-(a + h) * 0.5, -0.5, 0.0), Vector3(a - h, 1.0, a * 2.0))
	w.add_box(Vector3((a + h) * 0.5, -0.5, 0.0), Vector3(a - h, 1.0, a * 2.0))
	w.add_box(Vector3(0.0, -0.5, -(a + h) * 0.5), Vector3(h * 2.0, 1.0, a - h))
	w.add_box(Vector3(0.0, -0.5, (a + h) * 0.5), Vector3(h * 2.0, 1.0, a - h))
	w.add_box(Vector3(0.0, -depth - 0.5, 0.0), Vector3(h * 2.0, 1.0, h * 2.0))
	# side walls up the pit (the ground boxes are only 1 m thick)
	if depth > 1.0:
		w.add_box(Vector3(-h - 0.5, -depth * 0.5, 0.0), Vector3(1.0, depth, h * 2.0 + 2.0))
		w.add_box(Vector3(h + 0.5, -depth * 0.5, 0.0), Vector3(1.0, depth, h * 2.0 + 2.0))
		w.add_box(Vector3(0.0, -depth * 0.5, -h - 0.5), Vector3(h * 2.0, depth, 1.0))
		w.add_box(Vector3(0.0, -depth * 0.5, h + 0.5), Vector3(h * 2.0, depth, 1.0))
	return w


## A ladder on the pit's west wall from its floor (y -2.4) to the rim, top exit on the ground beyond.
func _ladder(descend_only: bool) -> ClimbableDef:
	return ClimbableDef.from_sidecar({"name": "TestLadder", "kind": "rope" if descend_only else "ladder",
		"descend_only": descend_only, "bottom": [-PIT_HALF + 0.05, -2.4, 0.0], "top": [-PIT_HALF + 0.05, 0.0, 0.0],
		"foot_ground": [-PIT_HALF + 0.35, -2.4, 0.0], "top_exit": [-PIT_HALF - 0.45, 0.0, 0.0], "facing_xz": [-1.0, 0.0]})


## Scans the 16 x 16 m area with an entry and an exit (a press-Up box) at its north-west corner, and verifies.
func _scan(w: PlayerTestWorld, climbables: Array[ClimbableDef]) -> Dictionary:
	var scan := StuckScan.create_in(w.host, db(), {"host": w.host})
	var g := StuckScan.MapGraph.new()
	g.map_id = "test"
	g.name = "test"
	var a := AREA_HALF - 0.5
	g.polygons.append(PackedVector2Array([Vector2(-a, -a), Vector2(a, -a), Vector2(a, a), Vector2(-a, a)]))
	g.kill_y = -6.0
	g.y_top = 6.0
	g.entry_points.append(Vector3(-5.0, 0.0, -5.0))
	g.exit_boxes.append(AABB(Vector3(-6.0, -0.5, -6.0), Vector3(2.0, 2.0, 2.0)))
	g.climbables = climbables
	scan.scan(g)
	scan.verify(g)
	return {"scan": scan, "graph": g}


## The component holding a node near world point `p` (empty when that ground is not flagged).
func _component_at(g: StuckScan.MapGraph, p: Vector3) -> Dictionary:
	var n := g.node_near(p, 0.3, 0.3, 1)
	if n < 0:
		return {}
	for c: Dictionary in g.components:
		if n in (c.members as PackedInt32Array):
			return c
	return {}


func _verdicts(g: StuckScan.MapGraph) -> Array:
	var out: Array = []
	for c: Dictionary in g.components:
		out.append([c.local, c.nodes, c.verdict])
	return out


## A closed trimesh box with outward faces (like an exported terrain solid).
func _closed_trimesh_box(w: PlayerTestWorld, b: AABB) -> void:
	var p := [Vector3(b.position.x, b.position.y, b.position.z), Vector3(b.end.x, b.position.y, b.position.z),
		Vector3(b.end.x, b.position.y, b.end.z), Vector3(b.position.x, b.position.y, b.end.z),
		Vector3(b.position.x, b.end.y, b.position.z), Vector3(b.end.x, b.end.y, b.position.z),
		Vector3(b.end.x, b.end.y, b.end.z), Vector3(b.position.x, b.end.y, b.end.z)]
	var faces := PackedVector3Array()
	for q in [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]:
		# wound so the front faces point out of the box (Godot: clockwise seen from the front)
		faces.append_array([p[q[0]], p[q[2]], p[q[1]], p[q[0]], p[q[3]], p[q[2]]])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	w.add_node(body)
