extends TestCase
## Spawn parity and SpawnSlot placement (MAP_ARCHITECTURE.md sections 4.7.1 and 4.13). Counts are checked from
## canonical data alone; placement rules run on the exported spawn areas with the flat GroundQuery (the physics
## version of the same checks is test_world_static.gd).

static var _placed: MapDefinitions = null


func placed(test_name: String) -> MapDefinitions:
	if not WorldSidecars.exists():
		print("SKIP %s: game/assets/world not present (run with INCLUDE_WORLD=1)" % test_name)
		return null
	if _placed == null:
		_placed = MapDefinitions.build(db(), WorldSidecars.load_dir())
		_placed.ground_all(GroundQuery.new())
	return _placed


func test_per_map_per_species_counts_equal_meowdb() -> void:
	var d := MapDefinitions.build(db())
	var total := 0
	for id in d.ids():
		var expected := {}
		for m in db().map(id).get("monsters", []):
			expected[str(m.id)] = int(m.count)
		var actual := {}
		for s in d.get_def(id).monster_spawn_definitions:
			actual[s.mob_id] = int(actual.get(s.mob_id, 0)) + 1
			total += 1
		assert_eq(actual, expected, "%s species counts" % id)
	assert_eq(total, 577, "island spawn slots")


func test_species_are_meowdb_monsters() -> void:
	var d := MapDefinitions.build(db())
	for id in d.ids():
		for s in d.get_def(id).monster_spawn_definitions:
			assert_true(db().has("monsters", s.mob_id), "%s slot %d mob %s has a monster page" % [id, s.index, s.mob_id])


func test_every_slot_is_placed_with_spacing_and_portal_clearance() -> void:
	var d := placed("test_every_slot_is_placed_with_spacing_and_portal_clearance")
	if d == null:
		return
	var spacing := d.tuning.num("spawns", "slot_min_spacing_m")
	var clearance := d.tuning.num("spawns", "slot_portal_clearance_m")
	for id in d.ids():
		var def := d.get_def(id)
		var arrivals: Array[Vector3] = [def.player_spawns[0].origin]
		for p in def.portals:
			arrivals.append(p.spawn_transform.origin)
		var slots := def.monster_spawn_definitions
		var region := SpawnSlotPlanner.mob_region(def, d.tuning)
		for i in slots.size():
			var s := slots[i]
			assert_true(s.grounded, "%s slot %d grounded" % [id, i])
			assert_true(s.placement in ["strict", "relaxed", "pinned"], "%s slot %d placement %s" % [id, i, s.placement])
			assert_true(region.size() >= 3 and Geometry2D.is_point_in_polygon(Vector2(s.position().x, s.position().z), region), "%s slot %d inside its mob region" % [id, i])
			for a in arrivals:
				assert_true(s.position().distance_to(a) >= clearance - 1e-4, "%s slot %d is %.2f m from an arrival" % [id, i, s.position().distance_to(a)])
			for j in range(i + 1, slots.size()):
				assert_true(s.position().distance_to(slots[j].position()) >= spacing - 1e-4,
					"%s slots %d and %d are %.2f m apart" % [id, i, j, s.position().distance_to(slots[j].position())])


## A slot stands in an area tagged with its species unless every such area is full: it holds as many slots as its room
## allows at presentation.json spawns.min_area_per_slot_m2 (the density rule spills the rest to roomier areas).
func test_species_matched_areas_are_used_first() -> void:
	var d := placed("test_species_matched_areas_are_used_first")
	if d == null:
		return
	var min_area := d.tuning.num("spawns", "min_area_per_slot_m2")
	var spilled := 0
	for id in d.ids():
		var def := d.get_def(id)
		var areas := SpawnSlotPlanner._areas_for(def, d.tuning)
		var load := {}
		for s in def.monster_spawn_definitions:
			load[s.region] = int(load.get(s.region, 0)) + 1
		for s in def.monster_spawn_definitions:
			var name := String(def.mob_names.get(s.mob_id, ""))
			var matched: Array[Dictionary] = []
			for a in areas:
				if name in (a.species as PackedStringArray):
					matched.append(a)
			if matched.is_empty():
				continue
			var used: Dictionary = {}
			for a in areas:
				if String(a.name) == s.region:
					used = a
			if name in (used.get("species", PackedStringArray()) as PackedStringArray):
				continue
			spilled += 1
			for a in matched:
				var n_in := int(load.get(String(a.name), 0))
				assert_true(float(a.room) / float(n_in + 1) < min_area,
					"%s slot %d (%s) spilled to %s while %s had room (%d slots in %.0f m^2)" % [id, s.index, name, s.region, a.name, n_in, float(a.room)])
	print("  %d slots spilled out of their species' areas by the density rule" % spilled)


func test_map_without_areas_uses_the_footprint_fallback() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_map_without_areas_uses_the_footprint_fallback: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	# The Phase 1 export had no spawn area on 000000030; emulate that in memory.
	var side := WorldSidecars.load_dir()
	side.chunks = side.chunks.duplicate(true)
	var sc: Dictionary = side.chunks["EastEntranceMushroomTown_30000"]
	sc.erase("spawn_regions")
	sc["spawn_areas"] = []
	var d := MapDefinitions.build(db(), side)
	d.ground_all(GroundQuery.new())
	var def := d.get_def("000000030")
	assert_eq(def.monster_spawn_definitions.size(), 6, "6 Tutorial Jr. Sentinels")
	var region := SpawnSlotPlanner.mob_region(def, d.tuning)
	for s in def.monster_spawn_definitions:
		assert_eq(s.region, "fallback:footprint", "slot %d region" % s.index)
		assert_true(s.grounded, "slot %d placed" % s.index)
		assert_true(Geometry2D.is_point_in_polygon(Vector2(s.position().x, s.position().z), region), "slot %d inside the mob region" % s.index)


func test_placement_is_deterministic() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_placement_is_deterministic: game/assets/world not present")
		return
	var a := MapDefinitions.build(db(), WorldSidecars.load_dir())
	a.ground_all(GroundQuery.new())
	var b := placed("test_placement_is_deterministic")
	for id in ["000000040", "000001000", "000001021"]:
		var sa := a.get_def(id).monster_spawn_definitions
		var sb := b.get_def(id).monster_spawn_definitions
		for i in sa.size():
			assert_true(sa[i].position().is_equal_approx(sb[i].position()), "%s slot %d stable" % [id, i])


## A flat world that records the clearance capsule each sample is tested with.
class RecordingQuery extends GroundQuery:
	var heights: Array[float] = []

	func is_clear(_feet: Vector3, _radius: float, height: float) -> bool:
		heights.append(height)
		return true


## A synthetic 20 x 20 m map with one Tutorial Jr. Sentinel ("1") and one Snail ("2") slot, no spawn areas (the
## planner samples the mob region).
func synthetic_def(sidecar: Dictionary = {}) -> MapDefinition:
	var def := MapDefinition.new()
	def.map_id = "000000030"
	def.has_markers = true
	def.sidecar = sidecar
	def.footprint_layout = PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 20)])
	def.footprint = def.footprint_layout
	def.player_spawns.append(Transform3D(Basis.IDENTITY, Vector3(-50, 0, -50)))
	def.mob_names = {"1": "Tutorial Jr. Sentinel", "2": "Snail"}
	for i in 2:
		var s := SpawnSlot.new()
		s.index = i
		s.mob_id = "1" if i == 0 else "2"
		def.monster_spawn_definitions.append(s)
	return def


## The clearance capsule is as tall as the species' body (canonical sprite height x WorldScale.actor when the
## monster data fits the model to the sprite height), never below presentation.json spawns.clearance_height_m.
func test_clearance_is_as_tall_as_the_species() -> void:
	var heights := SpawnSlotPlanner.species_body_heights(db())
	var sentinel := db().monster("1")
	assert_near(float(heights.get("1", 0.0)), WorldScale.actor(float(sentinel.sprite_size_px[1])), 1e-6,
		"Tutorial Jr. Sentinel: canonical sprite height x WorldScale.actor")
	assert_near(float(heights.get("1", 0.0)), 1.7, 1e-6, "68 px = 1.7 m")
	var tuning := MapDefinitions.build(db()).tuning
	var floor_h := tuning.num("spawns", "clearance_height_m")
	assert_near(SpawnSlotPlanner.clearance_height("1", tuning, heights), 1.7, 1e-6, "the Sentinel's capsule")
	assert_near(SpawnSlotPlanner.clearance_height("2", tuning, heights), maxf(floor_h, float(heights.get("2", 0.0))), 1e-6,
		"a Snail keeps the presentation.json floor")
	assert_near(SpawnSlotPlanner.clearance_height("no-such-mob", tuning, heights), floor_h, 1e-6, "unknown species: the floor")
	var q := RecordingQuery.new()
	var def := synthetic_def()
	SpawnSlotPlanner.plan(def, q, tuning, heights)
	assert_true(q.heights.size() >= 2, "both slots probed")
	assert_near(q.heights[0], 1.7, 1e-6, "slot 0 (Sentinel) probed with its body height")
	assert_near(q.heights[q.heights.size() - 1], SpawnSlotPlanner.clearance_height("2", tuning, heights), 1e-6,
		"slot 1 (Snail) probed with its own")


## maps/<id>.json spawn_keepouts: a disc around a named prop (from the sidecar's prop instances) or a centre; no
## sampled slot lands inside one.
func test_keepouts_keep_slots_out() -> void:
	var tuning := MapDefinitions.build(db()).tuning
	var side := {"collision": {"prop_instances": [{"shape": "House", "xform": [1, 0, 0, 0, 1, 0, 0, 0, 1, 10.0, 0.0, 10.0]}]}}
	var def := synthetic_def(side)
	tuning.per_map = {def.map_id: {"spawn_keepouts": [{"around_prop": "House", "radius_m": 7.0}, {"center": [3.0, 0.0, 17.0], "radius_m": 2.0}]}}
	var outs := SpawnSlotPlanner.keepouts_of(def, tuning)
	assert_eq(outs.size(), 2, "both discs resolved")
	assert_eq(outs[0].center, Vector2(10, 10), "around the prop instance")
	assert_eq(outs[1].center, Vector2(3, 17), "an explicit centre")
	for seed_shift in 6:
		def.map_id = "00000003%d" % seed_shift  # other seeds, same rules
		tuning.per_map = {def.map_id: {"spawn_keepouts": [{"around_prop": "House", "radius_m": 7.0}, {"center": [3.0, 17.0], "radius_m": 2.0}]}}
		var warnings := SpawnSlotPlanner.plan(def, GroundQuery.new(), tuning)
		assert_eq(warnings.size(), 0, "placed without warnings: %s" % ", ".join(warnings))
		for s in def.monster_spawn_definitions:
			var xz := Vector2(s.position().x, s.position().z)
			assert_true(xz.distance_to(Vector2(10, 10)) >= 7.0, "slot %d outside the prop disc (%.2f m)" % [s.index, xz.distance_to(Vector2(10, 10))])
			assert_true(xz.distance_to(Vector2(3, 17)) >= 2.0, "slot %d outside the centre disc" % s.index)
	var problems: Array = []
	tuning.per_map = {def.map_id: {"spawn_keepouts": [{"around_prop": "Nope", "radius_m": 1.0}, {"radius_m": 1.0}, {"around_prop": "House"}]}}
	SpawnSlotPlanner.keepouts_of(def, tuning, problems)
	assert_eq(problems.size(), 3, "unknown prop, no anchor, no radius are reported: %s" % str(problems))


## East Entrance to Mushroom Town: no Tutorial Jr. Sentinel slot stands under the yellow mushroom house's cap
## (maps/000000030.json spawn_keepouts; MONSTERS_AND_COMBAT_RUNTIME.md request).
func test_no_sentinel_under_the_mushroom_house_cap() -> void:
	var d := placed("test_no_sentinel_under_the_mushroom_house_cap")
	if d == null:
		return
	var def := d.get_def("000000030")
	var outs := SpawnSlotPlanner.keepouts_of(def, d.tuning)
	assert_eq(outs.size(), 1, "the house's keep-out resolves from the sidecar")
	for s in def.monster_spawn_definitions:
		for k in outs:
			var dist := Vector2(s.position().x, s.position().z).distance_to(k.center)
			assert_true(dist >= float(k.radius), "slot %d stands %.2f m from the house, inside its %.1f m cap disc" % [s.index, dist, float(k.radius)])
