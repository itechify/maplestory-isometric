extends TestCase
## BreakablePlacementPlanner (contract C8). L0: a synthetic map on the flat GroundQuery (with blocked discs) proves
## the rules: one box per canonical placement in index order, deterministic per map, spacing, portal, NPC and spawn
## slot clearances, the spawn areas first and the floor fallback, "unplaced" when nothing fits. L1: the real island's
## collision (INCLUDE_WORLD=1; one SKIP line without it): all 19 Wooden Boxes on the six maps, interiors included,
## stand on walkable ground with a clear capsule, inside their map, outside triggers, keep-outs and NPC talk spaces,
## away from arrivals, slots and each other, with room for the player beside them, on the base floor where a map has
## no spawn areas.

const BOX_MAPS := ["000001000", "000001010", "000001011", "000001012", "000001013", "000001014"]


func parity_keys() -> Dictionary:
	return {
		"test_every_box_stands_on_real_collision": ["breakable:0000001", "breakable-placement:000001000",
			"breakable-placement:000001010", "breakable-placement:000001011", "breakable-placement:000001012",
			"breakable-placement:000001013", "breakable-placement:000001014"],
	}


## A flat GroundQuery with walls: discs (XZ centre, radius) where nothing is clear and the ground is not walkable.
class DiscWorld:
	extends GroundQuery
	var discs: Array[Vector3] = []

	func _blocked(x: float, z: float, r: float = 0.0) -> bool:
		for d in discs:
			if Vector2(x - d.x, z - d.y).length() < d.z + r:
				return true
		return false

	func ground_at(p: Vector3, _up_m: float, _down_m: float) -> Dictionary:
		return {"ok": not _blocked(p.x, p.z), "y": 0.0, "normal": Vector3.UP, "note": "disc"}

	func top_surface(x: float, z: float, _y_top: float, _y_bottom: float, _hint_y: float) -> Dictionary:
		return {"ok": not _blocked(x, z), "y": 0.0, "normal": Vector3.UP, "note": "disc"}

	func is_clear(feet: Vector3, radius: float, _height: float) -> bool:
		return not _blocked(feet.x, feet.z, radius)


## A 30 x 30 m map at the origin with `n` Wooden Box placements, a portal arrival at (2, 0, 2), one NPC at (15, 0, 25)
## and two monster spawn slots.
func synthetic(n: int, with_areas: bool) -> MapDefinition:
	var def := MapDefinition.new()
	def.map_id = "999999001"
	def.map_name = "Box Test"
	var reactors: Array = []
	for i in n:
		reactors.append({"id": "0000001", "name": "Wooden Box", "x_px": i * 100, "y_px": 0, "respawn_s": 60 + i})
	def.canonical = {"reactors": reactors}
	def.footprint_layout = PackedVector2Array([Vector2(0, 0), Vector2(30, 0), Vector2(30, 30), Vector2(0, 30)])
	def.footprint = PackedVector2Array([Vector2(-1, -1), Vector2(31, -1), Vector2(31, 31), Vector2(-1, 31)])
	def.base_y = 0.0
	def.y_min = -1.0
	def.y_max = 5.0
	def.player_spawns = [Transform3D(Basis.IDENTITY, Vector3(2, 0, 2))] as Array[Transform3D]
	var arrival := PortalDef.new()
	arrival.portal_id = "arrival:test"
	arrival.portal_type = PortalDef.TYPE_ARRIVAL
	arrival.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(2, 0, 2))
	def.portals = [arrival] as Array[PortalDef]
	var npc := NpcPlacement.new()
	npc.npc_id = "18"
	npc.npc_name = "Pio"
	npc.map_id = def.map_id
	npc.transform = Transform3D(Basis.IDENTITY, Vector3(15, 0, 25))
	def.npc_definitions = [npc] as Array[NpcPlacement]
	for k in 2:
		var s := SpawnSlot.new()
		s.index = k
		s.mob_id = "2"
		s.grounded = true
		s.transform = Transform3D(Basis.IDENTITY, Vector3(20 + k * 3, 0, 8))
		def.monster_spawn_definitions.append(s)
	if with_areas:
		def.spawn_areas = [{"name": "Area_A", "species": PackedStringArray(["Snail"]), "surface_y": 0.0, "weight": 1.0,
			"polygon": PackedVector2Array([Vector2(12, 4), Vector2(28, 4), Vector2(28, 16), Vector2(12, 16)])}] as Array[Dictionary]
	return def


func tuning() -> WorldTuning:
	return WorldTuning.from_db(db())


func cfg() -> Dictionary:
	return BreakablePlacementPlanner.config(db())


func positions(placements: Array) -> Array:
	var out: Array = []
	for b: BreakablePlacement in placements:
		out.append(b.position())
	return out


func test_config_is_complete() -> void:
	var problems := PackedStringArray()
	var c := BreakablePlacementPlanner.config(db(), problems)
	assert_eq(problems.size(), 0, "breakables.json placement: %s" % ", ".join(problems))
	for k: String in BreakablePlacementPlanner.CONFIG_KEYS:
		assert_true(c.has(k), "placement.%s" % k)


func test_one_box_per_placement_deterministic_and_clear() -> void:
	var def := synthetic(4, true)
	var q := DiscWorld.new()
	var res := BreakablePlacementPlanner.plan(def, q, tuning(), db())
	var placements: Array = res.placements
	assert_eq(placements.size(), 4, "one per canonical placement")
	assert_eq((res.warnings as PackedStringArray).size(), 0, "no warnings: %s" % "; ".join(res.warnings))
	var c := cfg()
	var zone := float(tuning().talk_zone("18").radius_m)
	for i in placements.size():
		var b: BreakablePlacement = placements[i]
		assert_eq(b.index, i, "index order")
		assert_eq(b.key(), "999999001:%d" % i, "key")
		assert_eq(b.respawn_s, 60.0 + i, "canonical respawn_s carried")
		assert_eq(b.breakable_id, "0000001", "breakable id")
		assert_true(b.grounded and b.is_placed(), "placed")
		var p := b.position()
		assert_true(p.distance_to(Vector3(2, 0, 2)) >= float(c.portal_clearance_m), "away from the arrival")
		assert_true(Vector2(p.x - 15, p.z - 25).length() >= zone + float(c.npc_clearance_m), "outside Pio's talk space")
		for s in def.monster_spawn_definitions:
			assert_true(p.distance_to(s.position()) >= float(c.spawn_slot_clearance_m), "away from spawn slot %d" % s.index)
		for j in range(i + 1, placements.size()):
			assert_true(p.distance_to((placements[j] as BreakablePlacement).position()) >= float(c.min_spacing_m), "boxes %d and %d apart" % [i, j])
	# The areas come first: with room for all four, every box is in Area_A.
	for b: BreakablePlacement in placements:
		assert_eq(b.region, "Area_A", "box %d sampled in the spawn area" % b.index)
		assert_eq(b.placement, "area", "on the area's tier")
	var again := BreakablePlacementPlanner.plan(def, q, tuning(), db())
	assert_eq(positions(again.placements), positions(placements), "the same map always gets the same boxes")
	var other := synthetic(4, true)
	other.map_id = "999999002"
	assert_ne(positions(BreakablePlacementPlanner.plan(other, q, tuning(), db()).placements), positions(placements),
		"seeded per map")


func test_maps_without_areas_use_the_floor() -> void:
	var def := synthetic(3, false)
	var res := BreakablePlacementPlanner.plan(def, DiscWorld.new(), tuning(), db())
	var inset := tuning().num("spawns", "mob_region_inset_m")
	for b: BreakablePlacement in res.placements:
		assert_eq(b.region, BreakablePlacementPlanner.REGION_FLOOR, "box %d on the floor" % b.index)
		assert_eq(b.placement, "floor", "box %d on the base tier" % b.index)
		var p := b.position()
		assert_true(p.x >= inset - 1e-4 and p.x <= 30.0 - inset + 1e-4 and p.z >= inset - 1e-4 and p.z <= 30.0 - inset + 1e-4,
			"box %d inside the mob region (%s)" % [b.index, p])


func test_walls_and_crowding() -> void:
	# A wall disc over most of the area: the boxes go around it, or to the floor when the area is full.
	var def := synthetic(5, true)
	var q := DiscWorld.new()
	q.discs.append(Vector3(20, 10, 5.0))
	var res := BreakablePlacementPlanner.plan(def, q, tuning(), db())
	var c := cfg()
	for b: BreakablePlacement in res.placements:
		assert_true(b.is_placed(), "box %d placed" % b.index)
		var p := b.position()
		assert_true(Vector2(p.x - 20, p.z - 10).length() >= 5.0 + float(c.clearance_radius_m), "box %d clear of the wall" % b.index)
	# No room at all: unplaced, logged, not grounded.
	var none := synthetic(2, true)
	var solid := DiscWorld.new()
	solid.discs.append(Vector3(15, 15, 40.0))
	var r2 := BreakablePlacementPlanner.plan(none, solid, tuning(), db())
	for b: BreakablePlacement in r2.placements:
		assert_false(b.is_placed() or b.grounded, "box %d unplaced" % b.index)
	assert_eq((r2.warnings as PackedStringArray).size(), 2, "one warning per unplaced box")
	# A map without reactors plans nothing.
	assert_eq((BreakablePlacementPlanner.plan(synthetic(0, true), q, tuning(), db()).placements as Array).size(), 0, "no reactors")


func test_every_box_stands_on_real_collision() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_every_box_stands_on_real_collision: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var tree := Engine.get_main_loop() as SceneTree
	var world := IslandWorld.new()
	world.name = "BoxWorld"
	world.build_on_ready = false
	world.load_visuals = false
	world.attach_to_session = false
	tree.current_scene.add_child(world)
	world.build_now(db())
	var d := world.defs
	var q := world.ground_query
	var tun := d.tuning
	var c := cfg()
	var tol := tun.num("grounding", "grounded_tolerance_m")
	var up := tun.num("grounding", "probe_up_m")
	var down := tun.num("grounding", "probe_down_m")
	var lift := tun.num("grounding", "capsule_lift_m")
	var total := 0
	for map_id in BOX_MAPS:
		var def := d.get_def(map_id)
		var res := BreakablePlacementPlanner.plan(def, q, tun, db())
		var placements: Array = res.placements
		for w in res.warnings:
			print("box placement warning: " + w)
		assert_eq((res.warnings as PackedStringArray).size(), 0, "%s: no placement warning" % map_id)
		assert_eq(placements.size(), BreakableRules.placements_of(def.canonical).size(), "%s: one box per placement" % map_id)
		var rules := BreakablePlacementPlanner.rules_for(def, tun, db())
		var others: Array[Vector3] = []
		for b: BreakablePlacement in placements:
			total += 1
			var p := b.position()
			print("box %s %s %s at (%.2f, %.2f, %.2f)" % [b.key(), b.placement, b.region, p.x, p.y, p.z])
			assert_true(b.grounded and b.placement != BreakablePlacement.UNPLACED, "%s placed (%s)" % [b.key(), b.placement])
			# Physics, independently of the planner's own checks.
			var g := q.ground_at(p, up, down)
			assert_true(bool(g.ok), "%s on walkable ground (%s)" % [b.key(), String(g.get("note", ""))])
			if bool(g.ok):
				assert_true(absf(float(g.y) - p.y) <= tol, "%s is %.2f m off the ground" % [b.key(), absf(float(g.y) - p.y)])
			assert_true(q.is_clear(p + Vector3.UP * lift, float(c.clearance_radius_m), float(c.clearance_height_m)),
				"%s capsule blocked by %s" % [b.key(), ", ".join(q.blockers(p + Vector3.UP * lift, float(c.clearance_radius_m),
					float(c.clearance_height_m)))])
			assert_true(def.footprint_contains(p), "%s inside its map" % b.key())
			assert_eq(String(world.region_index.region_of(p, map_id).get("id", "")), map_id, "%s region" % b.key())
			for o in def.canonical_portals():
				assert_false(o.trigger_contains(p + Vector3.UP * 0.1), "%s inside trigger %s" % [b.key(), o.key()])
			for n in def.npc_definitions:
				var gap := Vector2(p.x - n.transform.origin.x, p.z - n.transform.origin.z).length()
				assert_true(gap >= float(tun.talk_zone(n.npc_id).radius_m) + float(c.npc_clearance_m),
					"%s is %.2f m from %s" % [b.key(), gap, n.npc_name])
			for s in def.monster_spawn_definitions:
				assert_true(p.distance_to(s.position()) >= float(c.spawn_slot_clearance_m), "%s near slot %d" % [b.key(), s.index])
			assert_true(BreakablePlacementPlanner.approach_points(p, q, rules) >= int(c.approach_min_free),
				"%s: a player can stand beside it" % b.key())
			# Every rule of the planner holds against the boxes placed before it.
			assert_eq(BreakablePlacementPlanner.violation(p, q, rules, others), "", "%s keeps every placement rule" % b.key())
			others.append(p)
			# Maps without spawn areas: on the base floor (no terrace, counter or ledge).
			if def.spawn_areas.is_empty():
				assert_eq(b.placement, "floor", "%s on the base floor tier" % b.key())
		var again := BreakablePlacementPlanner.plan(def, q, tun, db())
		assert_eq(positions(again.placements), positions(placements), "%s: deterministic" % map_id)
	assert_eq(total, 19, "all 19 Wooden Boxes placed")
	world.free()
