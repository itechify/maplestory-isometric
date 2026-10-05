extends TestCase
## Monster AI: the pure brain (stand/walk/turn/stagger/chase), the mob-region clamp, and the terrain probes on
## synthetic collision (ledges, walls, the region edge, Orange Mushroom hops). Synchronous: monsters are stepped
## tick by tick against primitive physics bodies (MonsterTestRig).

var rig: MonsterTestRig


func before_each() -> void:
	rig = MonsterTestRig.create(db())


func after_each() -> void:
	rig.free_all()


func _walk(m: Monster, dir: Vector3, seconds: float = 100.0) -> void:
	m.brain.mode = MonsterBrain.Mode.WALK
	m.brain.heading = dir.normalized()
	m.brain.timer = seconds
	m.facing = dir.normalized()


# --- brain -----------------------------------------------------------------------------------------------------------

func test_brain_alternates_stand_and_walk_with_the_species_timings() -> void:
	var def := MonsterDef.from_id("2", db())
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var b := MonsterBrain.new(def, rng)
	b.start(Vector3.RIGHT)
	assert_eq(b.mode, MonsterBrain.Mode.IDLE, "starts standing")
	assert_between(b.timer, def.idle_s.x, def.idle_s.y, "stand length")
	var seen_walk := false
	var seen_idle_again := false
	for i in 60 * 20:
		b.tick(1.0 / 60.0)
		if b.mode == MonsterBrain.Mode.WALK:
			seen_walk = true
			assert_between(b.timer, -0.02, def.walk_s.y, "walk length")
		elif seen_walk and b.mode == MonsterBrain.Mode.IDLE:
			seen_idle_again = true
	assert_true(seen_walk and seen_idle_again, "stand -> walk -> stand")
	assert_eq(b.move_dir(Vector3.ZERO, Vector3.ZERO) == Vector3.ZERO, b.mode == MonsterBrain.Mode.IDLE, "no motion while standing")


func test_brain_turns_around_when_blocked() -> void:
	var def := MonsterDef.from_id("2", db())
	var b := MonsterBrain.new(def, RandomNumberGenerator.new())
	b.start(Vector3.RIGHT)
	b.mode = MonsterBrain.Mode.WALK
	b.heading = Vector3.RIGHT
	for i in 20:
		var before := b.heading
		b.on_blocked()
		assert_true(b.heading.dot(before) < cos(PI * 0.5 - def.turn_jitter_rad) + 1e-6, "reversed (within the jitter)")
		assert_near(b.heading.length(), 1.0, 1e-5, "unit heading")
		assert_near(b.heading.y, 0.0, 1e-9, "horizontal")
	assert_eq(b.turns, 20)


func test_brain_staggers_then_chases_the_attacker_then_wanders() -> void:
	var def := MonsterDef.from_id("2", db())
	var b := MonsterBrain.new(def, RandomNumberGenerator.new())
	b.start(Vector3.RIGHT)
	b.on_hit(Vector3.ZERO, Vector3(-2, 0, 0), true)
	assert_eq(b.mode, MonsterBrain.Mode.STAGGER)
	assert_true(b.provoked, "provoked")
	assert_near(b.timer, def.stagger_s, 1e-6, "stagger = canonical hit clip")
	assert_true(b.push_dir.x > 0.99, "pushed away from the attacker")
	assert_near(b.push_left, def.knockback_m, 1e-6, "push distance (combat.json)")
	assert_true(b.heading.x < -0.99, "turns to face the attacker")
	assert_eq(b.move_dir(Vector3.ZERO, Vector3(-2, 0, 0)), Vector3.ZERO, "no walking while staggered")
	var t := 0.0
	while b.mode == MonsterBrain.Mode.STAGGER and t < 5.0:
		b.tick(1.0 / 60.0)
		t += 1.0 / 60.0
	assert_near(t, def.stagger_s, 0.02, "stagger lasts the hit clip")
	assert_eq(b.mode, MonsterBrain.Mode.CHASE, "then follows the attacker")
	assert_true(b.move_dir(Vector3.ZERO, Vector3(-2, 0, 1)).dot(Vector3(-2, 0, 1).normalized()) > 0.999, "walks toward the attacker")
	b.on_blocked()
	assert_eq(b.mode, MonsterBrain.Mode.CHASE, "a chase stops at an edge instead of turning away")
	for i in int(def.provoked_chase_s * 60.0) + 2:
		b.tick(1.0 / 60.0)
	assert_eq(b.mode, MonsterBrain.Mode.IDLE, "the chase ends")
	assert_true(b.provoked, "stays provoked (Peace touch rule)")


func test_a_hit_below_the_kb_threshold_does_not_stagger() -> void:
	var def := MonsterDef.from_id("2", db())
	var b := MonsterBrain.new(def, RandomNumberGenerator.new())
	b.start(Vector3.RIGHT)
	b.on_hit(Vector3.ZERO, Vector3(-1, 0, 0), false)
	assert_ne(b.mode, MonsterBrain.Mode.STAGGER, "no stagger without the KB threshold")
	assert_eq(b.mode, MonsterBrain.Mode.CHASE, "still provoked into a chase")


# --- mob region ------------------------------------------------------------------------------------------------------

func test_region_blocks_leaving_and_portal_discs_but_lets_strays_walk_back() -> void:
	var square := PackedVector2Array([Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5)])
	var discs: Array[Dictionary] = [{"center": Vector2(3, 0), "radius": 1.0}]
	var r := MobRegion.make(square, discs)
	assert_true(r.allows_step(Vector3(0, 0, 0), Vector3(0.5, 0, 0)), "inside")
	assert_false(r.allows_step(Vector3(4.8, 0, 3), Vector3(5.2, 0, 3)), "leaving the polygon")
	assert_false(r.allows_step(Vector3(1.8, 0, 0), Vector3(2.2, 0, 0)), "entering a portal disc")
	assert_true(r.allows_step(Vector3(2.5, 0, 0), Vector3(2.0, 0, 0)), "inside a disc: walking out is allowed")
	assert_false(r.allows_step(Vector3(2.5, 0, 0), Vector3(2.7, 0, 0)), "inside a disc: deeper is not")
	assert_true(r.allows_step(Vector3(6, 0, 0), Vector3(5.8, 0, 0)), "outside: walking back in is allowed")
	assert_false(r.allows_step(Vector3(6, 0, 0), Vector3(6.2, 0, 0)), "outside: further out is not")
	assert_true(r.contains(Vector3(0, 0, 0)))
	assert_false(r.contains(Vector3(3, 0, 0.5)), "in a disc")
	assert_true(MobRegion.new().allows_step(Vector3.ZERO, Vector3(100, 0, 0)), "unbounded without a footprint")


func test_region_from_a_map_definition_uses_the_mob_region_and_arrivals() -> void:
	var defs := MapDefinitions.build(db(), null)
	var def := defs.get_def("000000040")
	def.footprint_layout = PackedVector2Array([Vector2(0, 0), Vector2(30, 0), Vector2(30, 20), Vector2(0, 20)])
	def.portals[0].spawn_transform = Transform3D(Basis.IDENTITY, Vector3(3, 0, 10))
	def.portals[0].has_anchor = true
	var t := WorldTuning.from_db(db())
	var r := MobRegion.from_def(def, t)
	var inset := t.num("spawns", "mob_region_inset_m")
	assert_true(r.contains(Vector3(15, 0, 10)), "centre")
	assert_false(r.contains(Vector3(inset * 0.5, 0, 10)), "the inset band along the footprint edge is outside")
	assert_false(r.contains(Vector3(3 + t.num("spawns", "slot_portal_clearance_m") * 0.5, 0, 10)), "the arrival disc")


# --- terrain on collision ---------------------------------------------------------------------------------------------

func test_walker_turns_at_a_ledge_and_never_falls() -> void:
	rig.floor(4.0)  # top at y = 0, edges at +/- 2 m
	var m := rig.spawn("2", Vector3(1.0, 0, 0))
	_walk(m, Vector3.RIGHT)
	var max_x := 0.0
	for i in 60 * 12:
		rig.tick()
		max_x = maxf(max_x, m.global_position.x)
		assert_false(m.airborne, "never airborne on a flat platform (tick %d)" % i)
		if m.airborne:
			break
	assert_true(max_x < 2.0, "stays on the platform (max x %.2f)" % max_x)
	assert_true(int(m.blocked_by.ledge) > 0, "saw the ledge")
	assert_true(m.brain.turns > 0, "turned")
	assert_near(m.global_position.y, 0.0, 1e-3, "on the ground")
	assert_true(m.distance_walked > 1.0, "kept wandering (%.2f m)" % m.distance_walked)


func test_walker_turns_at_a_wall() -> void:
	rig.floor(20.0)
	rig.wall(Vector3(2.0, 1.0, 0), Vector3(0.3, 2.0, 6.0))
	var m := rig.spawn("4", Vector3(0.0, 0, 0))
	_walk(m, Vector3.RIGHT)
	var max_x := -INF
	for i in 60 * 6:
		rig.tick()
		max_x = maxf(max_x, m.global_position.x)
	assert_true(max_x < 2.0 - 0.15, "never walks into the wall (max x %.2f)" % max_x)
	assert_true(int(m.blocked_by.wall) > 0, "saw the wall")


func test_walker_walks_up_a_gentle_step_and_not_a_high_one() -> void:
	rig.floor(20.0)
	var low := rig.w.add_box(Vector3(3.0, 0.1, 0), Vector3(2.0, 0.2, 6.0))  # 0.2 m step: below the wall probe
	low.collision_layer = WorldLayers.WALKABLE
	var m := rig.spawn("2", Vector3(0.0, 0, 0))
	_walk(m, Vector3.RIGHT)
	for i in 60 * 4:
		rig.tick()
		if m.global_position.x > 3.0:
			break
	assert_true(m.global_position.x > 2.2, "walked onto the 0.2 m step (x %.2f)" % m.global_position.x)
	assert_near(m.global_position.y, 0.2, 0.01, "standing on it")


func test_walker_stays_inside_its_mob_region() -> void:
	rig.floor(30.0)
	var square := PackedVector2Array([Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3)])
	var region := MobRegion.make(square)
	var monsters: Array[Monster] = []
	for i in 6:
		var m := rig.spawn("4", Vector3(-2.0 + i * 0.8, 0, (i % 3) - 1.0), Vector3(cos(i), 0, sin(i)), region)
		_walk(m, Vector3(cos(i * 1.3), 0, sin(i * 1.3)), 2.0)
		monsters.append(m)
	var worst := -INF
	for t in 60 * 30:
		rig.tick()
		for m in monsters:
			worst = maxf(worst, region.outside_distance(m.global_position))
	assert_true(worst <= 0.0, "never left the region (worst %.3f m outside)" % worst)
	var turned := 0
	for m in monsters:
		turned += int(m.blocked_by.region)
		assert_true(m.distance_walked > 2.0, "%s wandered (%.1f m)" % [m.name, m.distance_walked])
	assert_true(turned > 0, "the region edge turned them")


func test_orange_mushroom_hops_up_a_terrace_and_will_not_jump_off_a_cliff() -> void:
	rig.floor(30.0)
	var terrace := rig.w.add_box(Vector3(6.0, 0.3, 0), Vector3(6.0, 0.6, 10.0))  # top at 0.6 m, face at x = 3
	terrace.collision_layer = WorldLayers.WALKABLE
	var m := rig.spawn("9", Vector3(0.5, 0, 0))
	_walk(m, Vector3.RIGHT)
	m.brain.hop_timer = 100.0  # no ambient hops: only the terrace may make it jump
	var peak := 0.0
	for i in 60 * 4:
		rig.tick()
		peak = maxf(peak, m.global_position.y)
		if not m.airborne and m.global_position.x > 3.2:
			break
	assert_true(m.hops >= 1, "hopped")
	assert_true(m.global_position.x > 3.0 and absf(m.global_position.y - 0.6) < 0.02, "landed on the terrace (%s)" % m.global_position)
	assert_true(peak <= 0.0 + m.def.hop_apex_m + 0.01, "apex = the character base jump (%.2f m)" % peak)
	# A deep cliff: a lone platform 5 m up; walking off its edge would drop more than hop_max_drop_m.
	var rig2 := MonsterTestRig.create(db())
	var top := rig2.w.add_box(Vector3(0, 4.5, 0), Vector3(4.0, 1.0, 4.0))  # top at y = 5
	top.collision_layer = WorldLayers.WALKABLE
	rig2.floor(40.0)
	var m2 := rig2.spawn("9", Vector3(1.0, 5.0, 0))
	_walk(m2, Vector3.RIGHT)
	for i in 60 * 8:
		rig2.tick()
	assert_near(m2.global_position.y, 5.0, 0.02, "still on its platform")
	assert_false(m2.airborne and m2.global_position.y < 4.0, "never jumped off")
	rig2.free_all()


func test_orange_mushroom_ambient_hops_land_back_on_the_ground() -> void:
	rig.floor(30.0)
	var m := rig.spawn("9", Vector3(0, 0, 0))
	_walk(m, Vector3.RIGHT, 6.0)
	m.brain.hop_timer = 0.0
	var max_y := 0.0
	for i in 60 * 6:
		rig.tick()
		max_y = maxf(max_y, m.global_position.y)
	assert_true(m.hops >= 2, "hops while walking (%d)" % m.hops)
	assert_true(max_y > 0.5, "visibly leaves the ground (%.2f m)" % max_y)
	assert_false(m.airborne and m.global_position.y < -0.01, "never sinks")


func test_a_monster_spawned_in_the_air_falls_and_lands() -> void:
	rig.floor(10.0)
	var m := rig.spawn("2", Vector3(0, 2.0, 0))
	m.global_position = Vector3(0, 2.0, 0)
	m.airborne = true
	for i in 60:
		rig.tick()
	assert_false(m.airborne, "landed")
	assert_near(m.global_position.y, 0.0, 0.02, "on the floor")


func test_knockback_push_covers_the_full_distance() -> void:
	# The push used to run after the brain's tick, which zeroes push_left on the stagger's last tick, so a monster
	# travelled 35/36 of combat.json's knockback distance (playtest finding monster-push-one-tick-short).
	rig.floor(20.0)
	var m := rig.spawn("2", Vector3.ZERO)
	var x0 := m.global_position.x
	m.brain.on_hit(m.global_position, m.global_position - Vector3(1, 0, 0), true)
	for i in 120:
		rig.tick()
	assert_near(m.global_position.x - x0, m.def.knockback_m, 0.002, "pushed the whole knockback distance")


func test_a_hit_mid_hop_still_staggers() -> void:
	# The canonical KB rule has no airborne exception (playtest finding airborne-hit-no-stagger).
	rig.floor(20.0)
	var m := rig.spawn("9", Vector3.ZERO)
	m.airborne = true
	var res := DamageResult.new()
	res.final = 1
	res.knockback = true
	m.receive_hit(res, null)
	assert_eq(m.brain.mode, MonsterBrain.Mode.STAGGER, "a mid-air hit staggers the monster")


func test_knockback_push_stops_at_a_ledge() -> void:
	rig.floor(4.0)
	var m := rig.spawn("2", Vector3(1.75, 0, 0))
	# Pushed away from an attacker at -x, toward the +x edge at 2 m.
	m.brain.on_hit(m.global_position, m.global_position - Vector3(1, 0, 0), true)
	for i in 60:
		rig.tick()
	assert_true(m.global_position.x < 2.0, "the push stops before the edge (x %.2f)" % m.global_position.x)
	assert_false(m.airborne, "not knocked off")
