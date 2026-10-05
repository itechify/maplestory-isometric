extends TestCase
## All six Maple Island species spawn as real monsters in their own maps and behave on the exported collision: the
## island is built synchronously (collision only), MonsterSystem installs its factory into the world's
## MapInstanceView, maps are realized from fresh MapInstanceStates, and every monster is stepped for 12 s. Each must
## stay on walkable ground (no falls, no recoveries), inside its map's mob region, and the population must wander;
## Orange Mushrooms must hop. Needs the Blender export (INCLUDE_WORLD=1); prints one SKIP line without it.

const TICK := 1.0 / 60.0
const SECONDS := 12.0
## Maps that together hold every Maple Island species (canonical spawns): Tutorial Jr. Sentinel (030), Snail (040,
## 1020), Blue Snail / Shroom / Red Snail (050), Orange Mushroom (1002, 1020).
const MAPS := ["000000030", "000000040", "000000050", "000001002", "000001020"]


func test_every_species_spawns_and_behaves_on_real_collision() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_every_species_spawns_and_behaves_on_real_collision: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var rig := MonsterTestRig.create(db(), 31)
	var world := IslandWorld.new()
	world.name = "MonsterWorld"
	world.build_on_ready = false
	world.load_visuals = false
	world.attach_to_session = false
	rig.w.host.add_child(world)
	var t0 := Time.get_ticks_msec()
	world.build_now(db())
	print("monster world built in %d ms" % (Time.get_ticks_msec() - t0))
	rig.system.attach_world(world)
	assert_true(rig.system.view == world.instance_view, "the factory is installed on the world's view")
	assert_true(world.instance_view.monster_factory == Callable(rig.system, &"make_monster"), "monster_factory")
	var now := [0.0]
	world.instance_view.clock = func() -> float: return now[0]
	var species_seen := {}
	var species_walked := {}
	var hops := 0
	t0 = Time.get_ticks_msec()
	for map_id in MAPS:
		var def := world.defs.get_def(map_id)
		var srng := RandomNumberGenerator.new()
		srng.seed = hash(map_id)
		var st := MapInstanceState.fresh(def, world.defs.spawn_model, srng, now[0])
		world.activate_map(def, st, null, def.player_spawn(0))
		while world.instance_view.pending_count() > 0:
			world.instance_view._process(0.0)
		var monsters: Array[Monster] = []
		for n in world.instance_view.nodes.values():
			assert_true(n is Monster, "%s: real monsters, not proxies" % map_id)
			if n is Monster:
				(n as Monster).autostep = false
				monsters.append(n)
		assert_eq(monsters.size(), st.capacity, "%s fills to capacity (%d)" % [map_id, st.capacity])
		var region := rig.system.region_for(def)
		# Monsters never cross portals: no portal trigger of the map reaches into the mob region (centre and corners of
		# its footprint), and no monster ever stands in a trigger while it wanders.
		for p in def.portals:
			var tt := p.trigger_transform()
			var half := p.trigger_size * 0.5
			var pts: Array[Vector3] = [tt.origin]
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					pts.append(tt * Vector3(sx * half.x, 0.0, sz * half.z))
			var reach := 0
			for q in pts:
				if region.contains(q):
					reach += 1
			assert_eq(reach, 0, "%s portal %s: its trigger lies outside the mob region" % [map_id, p.portal_id])
		var in_portal := {}
		var start_out := {}
		for m in monsters:
			start_out[m] = maxf(region.outside_distance(m.global_position), 0.0)
			species_seen[m.def.id] = true
			assert_false(m.airborne, "%s %s spawned on the ground" % [map_id, m.name])
		var worst_out := {}
		for t in int(SECONDS / TICK):
			for m in monsters:
				m.step(TICK)
				var out := region.outside_distance(m.global_position)
				worst_out[m] = maxf(float(worst_out.get(m, -INF)), out)
				if t % 10 == 0:
					for p in def.portals:
						if p.trigger_contains(m.global_position + Vector3.UP * 0.1):
							in_portal[m] = p.portal_id
		var g := world.ground_query
		for m in monsters:
			var id := m.def.id
			species_walked[id] = float(species_walked.get(id, 0.0)) + m.distance_walked
			hops += m.hops
			assert_eq(m.recoveries, 0, "%s %s never fell off the world" % [map_id, m.name])
			assert_false(in_portal.has(m), "%s %s never stood in a portal trigger (%s)" % [map_id, m.name, in_portal.get(m, "")])
			assert_true(m.global_position.y > def.kill_y, "%s %s above kill_y" % [map_id, m.name])
			assert_true(float(worst_out[m]) <= float(start_out[m]) + 0.02, "%s %s stayed in its mob region (%.2f m out)" % [map_id, m.name, float(worst_out[m])])
			assert_true(def.footprint_contains(m.global_position), "%s %s inside its map" % [map_id, m.name])
			if not m.airborne:
				var gr := g.ground_at(m.global_position, 0.3, 0.3)
				assert_true(bool(gr.ok) and absf(float(gr.y) - m.global_position.y) < 0.05, "%s %s stands on walkable ground" % [map_id, m.name])
		world.release_instance()
	print("monster world: %d maps stepped %.0f s each in %d ms; walked %s; OM hops %d" % [MAPS.size(), SECONDS,
		Time.get_ticks_msec() - t0, str(species_walked), hops])
	for id in ["1", "2", "3", "4", "5", "9"]:
		assert_true(species_seen.has(id), "species %s spawned" % id)
		assert_true(float(species_walked.get(id, 0.0)) > 2.0, "species %s wandered (%.1f m)" % [id, float(species_walked.get(id, 0.0))])
	assert_true(hops > 0, "Orange Mushrooms hop")
	world.free()
	rig.free_all()
