extends TestCase
## Tree canopies in the Wooden Box sight rule (breakables.json placement.canopies, an adaptation). The canopies have
## no collision, so the physics sight lines of BreakablePlacementPlanner.in_camera_sight passed through them and
## Amherst's box 000001010:4 stood behind an orange tree's leaves (the acceptance review). The planner reads a table
## of canopy boxes (asset frame) placed by the sidecar's prop instances, never the meshes, so headless and windowed
## runs plan the same boxes. L0: the canopy box test. World (INCLUDE_WORLD=1; one SKIP line without it): the table
## matches the visual export of every box map, and no box stands behind a canopy.

const BOX_MAPS := ["000001000", "000001010", "000001011", "000001012", "000001013", "000001014"]
## Metres of rounding the table may differ from the export by (it holds 3 decimals).
const TOLERANCE_M := 0.002


func _canopy(at: Vector3, half: Vector3) -> Dictionary:
	return {"what": "test", "to_local": Transform3D.IDENTITY, "box": AABB(at - half, half * 2.0)}


func test_a_segment_through_the_canopy_box_hits_and_one_beside_it_misses() -> void:
	var c := _canopy(Vector3(0, 6, 0), Vector3(3, 2, 3))
	assert_true(BreakablePlacementPlanner.segment_hits_canopy(Vector3(-10, 6, 0), Vector3(10, 6, 0), c), "through the middle")
	assert_true(BreakablePlacementPlanner.segment_hits_canopy(Vector3(2.9, 0, 0), Vector3(2.9, 20, 0), c), "near the rim")
	assert_false(BreakablePlacementPlanner.segment_hits_canopy(Vector3(3.1, 0, 0), Vector3(3.1, 20, 0), c), "past the rim")
	# Generous: the corners of the box count, where a round crown may leave a gap.
	assert_true(BreakablePlacementPlanner.segment_hits_canopy(Vector3(2.8, 7.8, -5), Vector3(2.8, 7.8, 5), c), "box corner")
	assert_false(BreakablePlacementPlanner.segment_hits_canopy(Vector3(0, 0, 0), Vector3(0, 3.9, 0), c), "ends short of it")
	assert_true(BreakablePlacementPlanner.segment_hits_canopy(Vector3(0, 6, 0), Vector3(0, 6.5, 0), c), "starts inside")


func test_an_instance_xform_places_rotates_and_scales_the_canopy() -> void:
	var def := MapDefinition.new()
	def.sidecar = {"collision": {"prop_instances": [
		# A tree at (100, 5, 50), turned 90 degrees and scaled 0.5.
		{"shape": "Tree_Test", "xform": [0.0, 0.0, -0.5, 0.0, 0.5, 0.0, 0.5, 0.0, 0.0, 100.0, 5.0, 50.0]},
		{"shape": "Not_A_Tree", "xform": [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]},
	]}}
	var table := {"Tree_Test": {"min": [-1.0, 4.0, -3.0], "max": [1.0, 8.0, 3.0]}}
	var cans := BreakablePlacementPlanner.canopies_of(def, table)
	assert_eq(cans.size(), 1, "one canopy per listed instance")
	var c: Dictionary = cans[0]
	# Centre in the world: (100, 5 + 6 * 0.5, 50); the long local z axis (half 3 * 0.5 = 1.5) now runs along world x.
	var mid := Vector3(100, 8, 50)
	assert_true(BreakablePlacementPlanner.segment_hits_canopy(mid + Vector3(1.4, 0, -5), mid + Vector3(1.4, 0, 5), c), "x 1.4 in")
	assert_false(BreakablePlacementPlanner.segment_hits_canopy(mid + Vector3(1.6, 0, -5), mid + Vector3(1.6, 0, 5), c), "x 1.6 out")
	assert_true(BreakablePlacementPlanner.segment_hits_canopy(mid + Vector3(-5, 0, 0.45), mid + Vector3(5, 0, 0.45), c), "z 0.45 in")
	assert_false(BreakablePlacementPlanner.segment_hits_canopy(mid + Vector3(-5, 0, 0.55), mid + Vector3(5, 0, 0.55), c), "z 0.55 out")


## The table is the export: every <asset>_Canopy mesh of a box map has its asset listed with its mesh box, every
## mesh stands where a sidecar instance of that shape does (the planner places canopies by those instances), and
## every listed asset occurs.
func test_the_canopy_table_matches_the_visual_export() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_the_canopy_table_matches_the_visual_export: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var table := BreakablePlacementPlanner.canopy_table(db())
	assert_true(not table.is_empty(), "breakables.json placement.canopies is filled")
	var seen := {}
	var checked := 0
	for map_id in BOX_MAPS:
		var chunk := _chunk_of(map_id)
		assert_true(chunk != "", "%s has a chunk" % map_id)
		var side: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world/%s.json" % chunk))
		var insts: Array = (side.get("collision", {}) as Dictionary).get("prop_instances", [])
		var ps: PackedScene = load("res://assets/world/%s.glb" % chunk)
		var root := ps.instantiate()
		for n in root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var ex: Variant = mi.get_meta("extras", null)
			var asset := String((ex as Dictionary).get("asset", "")) if ex is Dictionary else ""
			if asset == "" or not String(mi.name).ends_with("%s_Canopy" % asset):
				continue
			checked += 1
			seen[asset] = true
			assert_true(table.has(asset), "%s: canopy asset %s is in the table" % [chunk, asset])
			if not table.has(asset):
				continue
			var box := mi.get_aabb()
			var want: Dictionary = table[asset]
			for k in 3:
				assert_near(box.position[k], float(want.min[k]), TOLERANCE_M, "%s %s min[%d]" % [chunk, asset, k])
				assert_near(box.end[k], float(want.max[k]), TOLERANCE_M, "%s %s max[%d]" % [chunk, asset, k])
			var xf := _scene_xform(mi, root)
			var placed := false
			for inst in insts:
				if String(inst.get("shape", "")) != asset:
					continue
				var x: Array = inst.xform
				var o := Vector3(x[9], x[10], x[11])
				var b := Basis(Vector3(x[0], x[1], x[2]), Vector3(x[3], x[4], x[5]), Vector3(x[6], x[7], x[8]))
				if o.distance_to(xf.origin) < 0.01 and b.is_equal_approx(xf.basis):
					placed = true
			assert_true(placed, "%s: the %s canopy at %s stands where a sidecar instance does" % [chunk, asset, xf.origin])
		root.free()
	assert_true(checked > 0, "canopies were checked")
	for asset in table:
		assert_true(seen.has(asset), "table asset %s occurs on a box map" % asset)


## No box of the six maps stands behind a canopy, the reviewed one included (the world placement test checks every
## other rule).
func test_no_wooden_box_stands_behind_a_canopy() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_no_wooden_box_stands_behind_a_canopy: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var tree := Engine.get_main_loop() as SceneTree
	var world := IslandWorld.new()
	world.name = "CanopyWorld"
	world.build_on_ready = false
	world.load_visuals = false
	world.attach_to_session = false
	tree.current_scene.add_child(world)
	world.build_now(db())
	var d := world.defs
	var n_canopies := 0
	for map_id in BOX_MAPS:
		var def := d.get_def(map_id)
		var rules := BreakablePlacementPlanner.rules_for(def, d.tuning, db())
		n_canopies += (rules.canopies as Array).size()
		var res := BreakablePlacementPlanner.plan(def, world.ground_query, d.tuning, db())
		for b: BreakablePlacement in res.placements:
			var p := b.position()
			var fwd: Vector3 = rules.camera_forward
			var cfg: Dictionary = rules.cfg
			for h: float in [1.0, 0.5]:
				var from := p + Vector3.UP * (float(rules.lift) + float(cfg.clearance_height_m) * h)
				for c: Dictionary in rules.canopies:
					assert_false(BreakablePlacementPlanner.segment_hits_canopy(from, from - fwd * float(cfg.camera_sight_m), c),
						"%s at %s is behind a %s canopy" % [b.key(), p, c.what])
			print("box %s %s at (%.2f, %.2f, %.2f)" % [b.key(), b.placement, p.x, p.y, p.z])
	assert_true(n_canopies > 20, "the box maps' canopies are in the rules (%d)" % n_canopies)
	world.free()


func _chunk_of(map_id: String) -> String:
	for path in DirAccess.get_files_at("res://assets/world"):
		if path.ends_with(".json"):
			var side: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world/" + path))
			if side is Dictionary and String(side.get("meowdb_map_id", "")) == map_id:
				return String(side.get("chunk", ""))
	return ""


static func _scene_xform(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
