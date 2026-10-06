extends TestCase
## Iteration Three spawn placement rules (presentation.json spawns; MAP_ARCHITECTURE.md section 4.7.1): slots keep
## clear of NPC interaction spaces, small regions never clump (min_area_per_slot_m2, spilling to roomier regions),
## authored avoid zones (sidecar exclude_xz) keep slots out, and a respawn is never realized on the player. Counts and
## species stay MeowDB's. Synthetic maps on the flat GroundQuery; the exported island where noted (INCLUDE_WORLD=1).


## A flat 20 x 20 m map with `n` slots of `mob` and the given spawn areas (none = the mob region).
func _map(n: int, mob: String = "2", areas: Array[Dictionary] = []) -> MapDefinition:
	var def := MapDefinition.new()
	def.map_id = "000000040"
	def.has_markers = true
	def.footprint_layout = PackedVector2Array([Vector2(0, 0), Vector2(24, 0), Vector2(24, 24), Vector2(0, 24)])
	def.footprint = def.footprint_layout
	def.player_spawns.append(Transform3D(Basis.IDENTITY, Vector3(-50, 0, -50)))
	def.mob_names = {"2": "Snail", "3": "Blue Snail"}
	for i in n:
		var s := SpawnSlot.new()
		s.index = i
		s.mob_id = mob
		def.monster_spawn_definitions.append(s)
	for a in areas:
		def.spawn_areas.append(a)
	return def


static func _square(x0: float, z0: float, size: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, z0), Vector2(x0 + size, z0), Vector2(x0 + size, z0 + size), Vector2(x0, z0 + size)])


static func _area(name_: String, species: String, poly: PackedVector2Array) -> Dictionary:
	var sp := PackedStringArray([species]) if species != "" else PackedStringArray()
	return {"name": name_, "species": sp, "polygon": poly, "surface_y": 0.0, "weight": absf(_poly_area(poly)),
		"y_lo": NAN, "y_hi": NAN, "exclude": [] as Array[PackedVector2Array]}


static func _poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].x * p[(i + 1) % p.size()].y - p[(i + 1) % p.size()].x * p[i].y
	return a * 0.5


func _tuning() -> WorldTuning:
	return WorldTuning.from_db(db())


func test_slots_keep_clear_of_npcs() -> void:
	var tuning := _tuning()
	var clear := tuning.num("spawns", "slot_npc_clearance_m")
	assert_true(clear >= tuning.num("npc", "interaction_radius_m"), "at least the talk radius (%.2f m)" % clear)
	for k in 6:
		var def := _map(12)
		def.map_id = "00000004%d" % k  # other seeds, same rules
		var npc := NpcPlacement.new()
		npc.npc_name = "Sam"
		npc.transform = Transform3D(Basis.IDENTITY, Vector3(12, 0, 12))
		def.npc_definitions.append(npc)
		var warnings := SpawnSlotPlanner.plan(def, GroundQuery.new(), tuning)
		assert_eq(warnings.size(), 0, "placed without warnings: %s" % ", ".join(warnings))
		for s in def.monster_spawn_definitions:
			var dd := s.position().distance_to(npc.transform.origin)
			assert_true(dd >= clear - 1e-4, "slot %d stands %.2f m from the NPC" % [s.index, dd])
			assert_true(s.placement in ["strict", "relaxed"], "slot %d %s" % [s.index, s.placement])


func test_small_regions_do_not_clump_and_spill_to_roomier_ones() -> void:
	var tuning := _tuning()
	var min_area := tuning.num("spawns", "min_area_per_slot_m2")
	assert_true(min_area > 0.0, "a density rule exists")
	var small := _area("Snail_7", "Snail", _square(4, 4, 4))  # 16 m^2
	var big := _area("BlueSnail_1", "Blue Snail", _square(4, 12, 10))  # 100 m^2
	var areas: Array[Dictionary] = [small, big]
	var def := _map(5, "2", areas)
	var warnings := SpawnSlotPlanner.plan(def, GroundQuery.new(), tuning)
	assert_eq(warnings.size(), 0, ", ".join(warnings))
	var in_small := 0
	for s in def.monster_spawn_definitions:
		if s.region == "Snail_7/Snail" or s.region.begins_with("Snail_7"):
			in_small += 1
	assert_eq(in_small, int(floor(16.0 / min_area)), "the 16 m^2 region keeps %d m^2 per slot" % int(min_area))
	assert_eq(def.monster_spawn_definitions.size(), 5, "every slot placed somewhere")
	# Without the rule every Snail slot would crowd its own small region.
	var plain := SpawnSlotPlanner._assign_areas(_map(5, "2", areas), SpawnSlotPlanner._areas_for(_map(5, "2", areas), tuning), 0.0)
	for i in 5:
		assert_eq(int(plain[i]), 0, "no density rule: slot %d in the small region" % i)


## One species' overflow never takes another species' own room: the Snails' 16 m^2 region holds 2 of their 5 slots,
## and the 3 left over spill only after the Blue Snails have their own region (41 m^2: room for exactly their 5 slots
## at 8 m^2 each). Spilling slot by slot in species order let the Snails (id "2") take 3 of that room first, so 3 Blue
## Snails had to spill and the last one landed in the Snails' region.
func test_one_species_overflow_never_displaces_another_species() -> void:
	var tuning := _tuning()
	var min_area := tuning.num("spawns", "min_area_per_slot_m2")
	var small := _area("Snail_7", "Snail", _square(2, 2, 4))  # 16 m^2
	var blue := _area("BlueSnail_1", "Blue Snail", _square(10, 2, sqrt(5.0 * min_area + 1.0)))  # room for exactly 5 slots
	var areas: Array[Dictionary] = [small, blue]
	var def := _map(10, "2", areas)
	for i in range(5, 10):
		def.monster_spawn_definitions[i].mob_id = "3"
	var got := SpawnSlotPlanner._assign_areas(def, SpawnSlotPlanner._areas_for(def, tuning), min_area)
	assert_eq(got.size(), 10, "every slot assigned")
	var snails_home := 0
	for i in 5:
		if int(got[i]) == 0:
			snails_home += 1
	# 10 slots in 57 m^2 cannot all keep 8 m^2: the spill evens the crowding out over both regions.
	assert_true(snails_home >= int(floor(16.0 / min_area)), "the Snails fill their own region first (%d)" % snails_home)
	for i in range(5, 10):
		assert_eq(int(got[i]), 1, "Blue Snail slot %d stays in its own region" % i)


func test_a_species_shares_its_regions_by_weight() -> void:
	var tuning := _tuning()
	var a := _area("Snail_1", "Snail", _square(2, 2, 10))  # 100 m^2
	var b := _area("Snail_2", "Snail", _square(14, 2, 6))  # 36 m^2 (keeps 8 m^2 per slot up to 4 slots)
	var areas: Array[Dictionary] = [a, b]
	var def := _map(8, "2", areas)
	var got := SpawnSlotPlanner._assign_areas(def, SpawnSlotPlanner._areas_for(def, tuning), tuning.num("spawns", "min_area_per_slot_m2"))
	var n := [0, 0]
	for i in 8:
		n[int(got[i])] += 1
	assert_eq(n, [6, 2], "proportional to the areas (100 : 36 of 8 slots)")


## A species' share of a region weighted by area counts only the room a slot can use: the region minus its authored
## exclusions (flower beds). A 100 m^2 region that is 64 m^2 beds holds as much as an open 36 m^2 one; weighting by
## the full 100 m^2 gave it 6 of 8 slots on the 36 m^2 left. An authored proxy count (`points`) stays as authored.
func test_a_share_by_area_counts_only_the_room_left_after_exclusions() -> void:
	var tuning := _tuning()
	var a := _area("Snail_1", "Snail", _square(2, 2, 10))  # 100 m^2
	(a["exclude"] as Array[PackedVector2Array]).append(_square(3, 3, 8))  # 64 m^2 of beds: 36 m^2 left
	var b := _area("Snail_2", "Snail", _square(14, 2, 6))  # 36 m^2, open
	var areas: Array[Dictionary] = [a, b]
	var def := _map(8, "2", areas)
	var clipped := SpawnSlotPlanner._areas_for(def, tuning)
	assert_near(float(clipped[0].room), 36.0, 1e-3, "the beds are not room")
	assert_near(float(clipped[0].weight), 36.0, 1e-3, "and not weight")
	var got := SpawnSlotPlanner._assign_areas(def, clipped, 0.0)
	var n := [0, 0]
	for i in 8:
		n[int(got[i])] += 1
	assert_eq(n, [4, 4], "equal room, equal share (the density rule off)")
	# Authored proxy counts are a share in themselves: kept, whatever the room.
	var pa := a.duplicate(true)
	pa["weight"] = 6.0
	pa["weight_from_points"] = true
	var pb := b.duplicate(true)
	pb["weight"] = 2.0
	pb["weight_from_points"] = true
	var pointed: Array[Dictionary] = [pa, pb]
	var def2 := _map(8, "2", pointed)
	var got2 := SpawnSlotPlanner._assign_areas(def2, SpawnSlotPlanner._areas_for(def2, tuning), 0.0)
	var m := [0, 0]
	for i in 8:
		m[int(got2[i])] += 1
	assert_eq(m, [6, 2], "6 : 2 proxies")


func test_authored_exclusions_keep_slots_out() -> void:
	var tuning := _tuning()
	var area := _area("BlueSnail_1", "Snail", _square(2, 2, 20))
	var plaza := _square(7, 7, 10)  # the middle quarter of the region
	(area["exclude"] as Array[PackedVector2Array]).append(plaza)
	var areas: Array[Dictionary] = [area]
	for k in 4:
		var def := _map(10, "2", areas)
		def.map_id = "00000005%d" % k
		var clipped := SpawnSlotPlanner._areas_for(def, tuning)
		assert_near(float(clipped[0].room), 400.0 - 100.0, 1e-3, "the plaza is not room")
		var warnings := SpawnSlotPlanner.plan(def, GroundQuery.new(), tuning)
		assert_eq(warnings.size(), 0, ", ".join(warnings))
		for s in def.monster_spawn_definitions:
			var xz := Vector2(s.position().x, s.position().z)
			assert_false(Geometry2D.is_point_in_polygon(xz, plaza), "slot %d inside the excluded plaza %s" % [s.index, xz])


## Overlapping exclusions (Snail Garden's and Mushroom Garden's flower beds are drawn across each other) take their
## shared ground out of a region's room once, not once per exclusion: room is the region minus the union of its
## exclusions. Summing the cuts made rooms up to 3 m^2 too small, so a region that can hold a slot at
## min_area_per_slot_m2 (Mushroom Garden Shroom_7: 9.7 m^2) spilled all of its slots.
func test_overlapping_exclusions_are_counted_once() -> void:
	assert_near(SpawnSlotPlanner.union_area([_square(0, 0, 6)]), 36.0, 1e-4, "one square")
	assert_near(SpawnSlotPlanner.union_area([_square(0, 0, 6), _square(3, 0, 6)]), 54.0, 1e-4, "two half-overlapping squares")
	assert_near(SpawnSlotPlanner.union_area([_square(0, 0, 10), _square(4, 4, 2)]), 100.0, 1e-4, "one inside the other")
	assert_near(SpawnSlotPlanner.union_area([_square(4, 4, 2), _square(0, 0, 10)]), 100.0, 1e-4, "either order")
	var strip := func(x0: float) -> PackedVector2Array:
		return PackedVector2Array([Vector2(x0, 0), Vector2(x0 + 4, 0), Vector2(x0 + 4, 4), Vector2(x0, 4)])
	assert_near(SpawnSlotPlanner.union_area([strip.call(0.0), strip.call(2.0), strip.call(1.0)]), 24.0, 1e-4,
		"three strips overlapping each other: [0, 6] x [0, 4]")
	assert_near(SpawnSlotPlanner.union_area([_square(0, 0, 2), _square(5, 5, 2)]), 8.0, 1e-4, "apart")
	assert_near(SpawnSlotPlanner.union_area([]), 0.0, 1e-9, "none")
	var area := _area("Shroom_7", "Shroom", _square(2, 2, 20))
	(area["exclude"] as Array[PackedVector2Array]).append(_square(6, 6, 6))
	(area["exclude"] as Array[PackedVector2Array]).append(_square(9, 6, 6))
	var areas: Array[Dictionary] = [area]
	var clipped := SpawnSlotPlanner._areas_for(_map(4, "2", areas), _tuning())
	assert_near(float(clipped[0].room), 400.0 - 54.0, 1e-3, "the beds' shared 18 m^2 is taken out once")


## The exported island: every slot of every map stands clear of every NPC, inside no exclusion of its region, and no
## species-tagged region holds more slots than its room allows unless the whole map is that crowded.
func test_island_slots_keep_clear_of_npcs_and_exclusions() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_island_slots_keep_clear_of_npcs_and_exclusions: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var d := MapDefinitions.build(db(), WorldSidecars.load_dir())
	d.ground_all(GroundQuery.new())
	var clear := d.tuning.num("spawns", "slot_npc_clearance_m")
	var min_area := d.tuning.num("spawns", "min_area_per_slot_m2")
	var checked := 0
	for id in d.ids():
		var def := d.get_def(id)
		if def.monster_spawn_definitions.is_empty():
			continue
		var npcs := SpawnSlotPlanner.npc_points(def)
		var areas := SpawnSlotPlanner._areas_for(def, d.tuning)
		var load := {}
		var room_total := 0.0
		for a in areas:
			room_total += float(a.room)
		for s in def.monster_spawn_definitions:
			assert_true(s.placement in ["strict", "relaxed", "pinned"], "%s slot %d %s" % [id, s.index, s.placement])
			for n in npcs:
				assert_true(s.position().distance_to(n) >= clear - 1e-4, "%s slot %d is %.2f m from an NPC" % [id, s.index, s.position().distance_to(n)])
			load[s.region] = int(load.get(s.region, 0)) + 1
			for a in areas:
				if String(a.name) == s.region:
					assert_false(SpawnSlotPlanner._in_any(Vector2(s.position().x, s.position().z), a.get("exclude", [])),
						"%s slot %d inside an exclusion of %s" % [id, s.index, s.region])
			checked += 1
		var map_density := room_total / maxf(def.monster_spawn_definitions.size(), 1)
		for a in areas:
			var n_in := int(load.get(String(a.name), 0))
			if n_in <= 1:
				continue
			var per := float(a.room) / n_in
			assert_true(per >= minf(min_area, map_density) * 0.5 - 1e-6,
				"%s %s: %d slots in %.0f m^2 (%.1f m^2 each)" % [id, a.name, n_in, float(a.room), per])
	assert_eq(checked, 577, "every MeowDB spawn point")


## A respawn waits while the player stands on its slot (spawns.respawn_player_clearance_m), and is realized once the
## player has moved away; the slot stays alive in MapInstanceState all along, so the counts never change.
func test_a_respawn_is_never_realized_on_the_player() -> void:
	var defs := MapDefinitions.build(db())
	var def := defs.get_def("000000040")
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var now: Array = [0.0]  # a reference: a lambda copies plain locals
	var state := MapInstanceState.fresh(def, defs.spawn_model, r, 0.0)
	var view := MapInstanceView.new()
	view.tuning = defs.tuning
	view.clock = func() -> float: return float(now[0])
	view.monster_factory = func(_mob: String, slot: SpawnSlot) -> Node3D:
		var n := Node3D.new()
		n.transform = slot.transform
		return n
	var released: Array[Node3D] = []
	view.monster_releaser = func(n: Node3D) -> void: released.append(n)
	var player_at: Array = [Vector3(50, 0, 50)]
	view.player_position = func() -> Variant: return player_at[0]
	view.realize(state, def, Vector3(100, 0, 0))
	for k in 10:
		view._process(0.0)
	assert_eq(view.live_count(), state.alive_count(), "the arrival's fill, far from the player, is realized at once")
	assert_eq(view.deferred_respawns, 0, "nothing waited")
	player_at[0] = def.monster_spawn_definitions[0].position()  # every slot sits at the origin without the export
	var killed: int = state.alive_indices()[0]
	assert_true(view.notify_killed(killed), "killed")
	var before := Array(state.alive_indices())
	now[0] = 60.0
	view._process(0.0)
	var back := Array(state.alive_indices()).filter(func(x: int) -> bool: return not before.has(x))
	assert_eq(back.size(), 1, "one slot came back in the state on the tick (capacity unchanged)")
	if back.size() != 1:
		view.free()
		return
	var i: int = back[0]
	assert_eq(state.alive_count(), state.capacity, "at capacity")
	assert_false(view.nodes.has(i), "but it is not realized on the player")
	assert_true(view.deferred_respawns > 0, "it waited")
	assert_true(view.respawn_waited(i), "the view says the respawn is waiting")
	for k in 5:
		view._process(0.0)
	assert_false(view.nodes.has(i), "still waiting while the player stays")
	assert_eq(view.deferred_respawns, 1, "one held-back respawn, counted once however many frames it waits")
	assert_eq(view.live_count(), state.alive_count() - 1, "every other alive slot stays realized")
	var seen_waited: Array = []
	view.monster_spawned.connect(func(_n: Node3D, slot: SpawnSlot) -> void: seen_waited.append(view.respawn_waited(slot.index)))
	player_at[0] = Vector3(50, 0, 50)
	view._process(0.0)
	assert_true(view.nodes.has(i), "realized once the player moved away")
	assert_eq(seen_waited, [true], "listeners of monster_spawned can tell it was held back")
	assert_false(view.respawn_waited(i), "and it is forgotten afterwards")
	assert_eq(view.live_count(), state.alive_count(), "every alive slot realized")
	for n in view.get_children():
		n.free()
	for n in released:
		if is_instance_valid(n):
			n.free()
	view.free()


## A game loaded at its saved resume point can stand on a slot of the map's fresh fill (a portal arrival never does:
## slots stand 4 m from arrivals): that slot's monster waits until the player moves away; every other slot of the fill
## is realized at once.
func test_an_arrival_fill_never_realizes_a_monster_on_the_player() -> void:
	var defs := MapDefinitions.build(db())
	var def := defs.get_def("000000040")
	for s in def.monster_spawn_definitions:
		s.transform = Transform3D(Basis.IDENTITY, Vector3(s.index * 3.0, 0.0, 0.0))  # 3 m apart in a row
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var state := MapInstanceState.fresh(def, defs.spawn_model, r, 0.0)
	var view := MapInstanceView.new()
	view.tuning = defs.tuning
	view.clock = func() -> float: return 0.0
	view.monster_factory = func(_mob: String, slot: SpawnSlot) -> Node3D:
		var n := Node3D.new()
		n.transform = slot.transform
		return n
	var released: Array[Node3D] = []
	view.monster_releaser = func(n: Node3D) -> void: released.append(n)
	var on: int = state.alive_indices()[3]
	var resume := def.monster_spawn_definitions[on].position() + Vector3(0.5, 0.0, 0.0)
	var player_at: Array = [resume]
	view.player_position = func() -> Variant: return player_at[0]
	view.realize(state, def, resume)
	for k in 20:
		view._process(0.0)
	assert_false(view.nodes.has(on), "the slot the player stands on is not realized")
	assert_true(view.respawn_waited(on), "it waits")
	assert_eq(view.live_count(), state.alive_count() - 1, "every other slot of the fill is realized")
	assert_eq(view.deferred_respawns, 1, "one held back")
	player_at[0] = resume + Vector3(0.0, 0.0, 10.0)
	view._process(0.0)
	assert_true(view.nodes.has(on), "realized once the player moved away")
	assert_eq(view.live_count(), state.alive_count(), "the whole fill is live")
	for n in view.get_children():
		n.free()
	for n in released:
		if is_instance_valid(n):
			n.free()
	view.free()


func parity_keys() -> Dictionary:
	return {
		"test_slots_keep_clear_of_npcs": ["mechanic:spawn-placement-npc-clearance"],
		"test_small_regions_do_not_clump_and_spill_to_roomier_ones": ["mechanic:spawn-density"],
		"test_one_species_overflow_never_displaces_another_species": ["mechanic:spawn-density"],
		"test_a_species_shares_its_regions_by_weight": ["mechanic:spawn-density"],
		"test_authored_exclusions_keep_slots_out": ["mechanic:spawn-placement-exclusions"],
		"test_overlapping_exclusions_are_counted_once": ["mechanic:spawn-placement-exclusions", "mechanic:spawn-density"],
		"test_island_slots_keep_clear_of_npcs_and_exclusions": ["mechanic:spawn-placement-npc-clearance", "mechanic:spawn-density"],
		"test_a_respawn_is_never_realized_on_the_player": ["mechanic:spawn-placement-player-overlap"],
		"test_an_arrival_fill_never_realizes_a_monster_on_the_player": ["mechanic:spawn-placement-player-overlap"],
	}
