extends TestCase
## 'Stays on its floor' and 'Jumps between floors' (MeowDB movement labels) in 3D: the spawn floor band
## (monsters/_shared.json floor_band_m, MonsterDef.floor_range), pacing back and forth on it, the Orange Mushroom's
## floors (its spawn floor and one hop above or below it: monsters/9.json hop_floor_rule, MonsterDef.hop_floor), and
## a knockback hit in mid-hop (combat.json monster_knockback.airborne_hit). Synchronous, on primitive collision
## (MonsterTestRig).

var rig: MonsterTestRig


func before_each() -> void:
	rig = MonsterTestRig.create(db())


func after_each() -> void:
	rig.free_all()


func _box(center: Vector3, size: Vector3, rotation_deg: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var b := rig.w.add_box(center, size, rotation_deg)
	b.collision_layer = WorldLayers.WALKABLE
	return b


# --- pure rules --------------------------------------------------------------------------------------------------------

func test_the_spawn_floor_band() -> void:
	var snail := MonsterDef.from_id("2", db())
	var band := snail.floor_band_m
	assert_true(band > 0.0 and band < 1.0, "a band of a fraction of a metre (%.2f)" % band)
	assert_eq(snail.floor_range(5.0), Vector2(5.0 - band, 5.0 + band), "spawn height +/- floor_band_m")
	assert_eq(snail.floor_range(5.0, 4.9, 5.1), Vector2(4.9 - band, 5.1 + band), "a flat authored tier")
	assert_eq(snail.floor_range(20.2, 20.1, 21.7), Vector2(20.1 - band, 21.7 + band), "a hillside region: its whole band")
	assert_eq(snail.floor_range(9.0, 5.0, 5.2), Vector2(9.0 - band, 9.0 + band), "a slot on another surface keeps its own")
	var om := MonsterDef.from_id("9", db())
	assert_eq(om.floor_range(5.0), Vector2(5.0 - band, 5.0 + band), "a jumper's spawn floor is the walkers' floor")


func test_a_jumper_reaches_one_floor_above_or_below_its_spawn_floor_and_no_further() -> void:
	var om := MonsterDef.from_id("9", db())
	var spawn := om.floor_range(0.0)
	assert_eq(om.hop_floor(0, spawn, spawn, 0.2), 0, "a hop on its spawn floor")
	assert_eq(om.hop_floor(0, spawn, spawn, 0.7), 1, "from the spawn floor up one")
	assert_eq(om.hop_floor(0, spawn, spawn, -1.6), -1, "from the spawn floor down one")
	var up := om.floor_band_at(0.7)
	assert_eq(om.hop_floor(1, up, spawn, 0.9), 1, "a hop along the floor above")
	assert_eq(om.hop_floor(1, up, spawn, 0.0), 0, "back down to the spawn floor")
	assert_eq(om.hop_floor(1, up, spawn, 1.4), MonsterDef.NO_FLOOR, "never two floors up")
	var down := om.floor_band_at(-0.7)
	assert_eq(om.hop_floor(-1, down, spawn, -1.4), MonsterDef.NO_FLOOR, "never two floors down")
	assert_eq(om.hop_floor(-1, down, spawn, 0.1), 0, "back up to the spawn floor")
	var snail := MonsterDef.from_id("2", db())
	var s := snail.floor_range(0.0)
	assert_eq(snail.hop_floor(0, s, s, 0.7), MonsterDef.NO_FLOOR, "a walker has no other floor")


func test_a_slot_monster_takes_its_spawn_region_tier() -> void:
	var def := MapDefinition.new()
	def.map_id = "test"
	def.spawn_areas.append({"name": "Snail_5/Snail", "y_lo": 20.1, "y_hi": 21.7})
	var slot := SpawnSlot.new()
	slot.index = 0
	slot.mob_id = "2"
	slot.region = "Snail_5/Snail"
	def.monster_spawn_definitions.append(slot)
	assert_eq(MonsterSystem.region_band(def, 0), Vector2(20.1, 21.7), "the slot's region band")
	assert_true(is_nan(MonsterSystem.region_band(def, 3).x), "no slot: no band")
	_box(Vector3(0, 19.7, 0), Vector3(10, 1, 10))  # top at 20.2
	var m := rig.spawn("2", Vector3(0, 20.2, 0))
	m.set_region_band(20.1, 21.7)
	assert_near(m.spawn_floor.y, 21.7 + m.def.floor_band_m, 1e-6, "the floor reaches the top of the hillside")


# --- on collision --------------------------------------------------------------------------------------------------------

## A ramp from the spawn floor up to a terrace 1.5 m higher: a walker walks onto its foot, never further than its floor
## band, and turns there ('Stays on its floor': Iteration Two walkers climbed ramps to other terraces).
func test_a_walker_never_climbs_a_ramp_off_its_floor() -> void:
	_box(Vector3(-4, -0.5, 0), Vector3(12, 1, 8))  # spawn floor, top 0, x -10..2
	var a := atan2(1.5, 6.0)
	_box(Vector3(5 + 0.1 * sin(a), 0.75 - 0.1 * cos(a), 0), Vector3(6.0 / cos(a), 0.2, 8), Vector3(0, 0, rad_to_deg(a)))
	_box(Vector3(11, 1.0, 0), Vector3(6, 1, 8))  # terrace, top 1.5, x 8..14
	for mob in ["2", "4"]:
		var m := rig.spawn(mob, Vector3(1, 0, 0), Vector3.RIGHT)
		# One long walk along its line (+x first): no stand can turn it back before it reaches the ramp.
		m.brain.mode = MonsterBrain.Mode.WALK
		m.brain.timer = 100.0
		var top := -INF
		for i in 60 * 30:
			rig.tick()
			if not m.airborne:
				top = maxf(top, m.global_position.y)
		assert_true(top <= m.def.floor_band_m + 1e-3, "%s stayed on its floor (highest %.2f m)" % [mob, top])
		assert_true(top > 0.1, "%s walked onto the foot of the ramp (%.2f m)" % [mob, top])
		assert_true(int(m.blocked_by.floor) > 0, "%s turned at the edge of its floor" % mob)
		m.die()


## Back and forth: on a flat 4 m platform a walker spawned facing +x paces along x, turns at both ledges and never
## drifts off its line.
func test_a_walker_paces_back_and_forth_on_its_line() -> void:
	rig.floor(4.0)
	var m := rig.spawn("4", Vector3.ZERO, Vector3.RIGHT)
	var seen := {"+": false, "-": false}
	var max_z := 0.0
	for i in 60 * 40:
		rig.tick()
		if m.is_walking():
			assert_true(absf(m.facing.dot(Vector3.RIGHT)) > 0.999, "walks along its line (tick %d, facing %s)" % [i, m.facing])
			seen["+" if m.facing.x > 0.0 else "-"] = true
		max_z = maxf(max_z, absf(m.global_position.z))
	assert_true(seen["+"] and seen["-"], "both ways: %s" % seen)
	assert_true(max_z < 1e-4, "never left its line (|z| %.4f)" % max_z)
	assert_true(int(m.blocked_by.ledge) >= 2, "turned at the ledges (%d)" % int(m.blocked_by.ledge))
	assert_true(m.distance_walked > 4.0, "kept pacing (%.1f m)" % m.distance_walked)


## Terraces every 0.7 m (each one hop up or down): over two minutes the Orange Mushroom reaches the floor above and the
## floor below its spawn floor, and never the second floor up or down.
func test_orange_mushroom_hops_to_the_floors_next_to_its_spawn_floor_only() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(6, 1, 6))  # spawn floor, top 0, x -3..3
	_box(Vector3(5, 0.2, 0), Vector3(4, 1, 6))  # top 0.7, x 3..7
	_box(Vector3(9, 0.9, 0), Vector3(4, 1, 6))  # top 1.4, x 7..11
	_box(Vector3(-5, -1.2, 0), Vector3(4, 1, 6))  # top -0.7, x -7..-3
	_box(Vector3(-9, -1.9, 0), Vector3(4, 1, 6))  # top -1.4, x -11..-7
	var m := rig.spawn("9", Vector3(0, 0, 0), Vector3.RIGHT)
	var lo := INF
	var hi := -INF
	var floors := {}
	for i in 60 * 120:
		rig.tick()
		if not m.airborne:
			lo = minf(lo, m.global_position.y)
			hi = maxf(hi, m.global_position.y)
			floors[m.floor_index] = true
	assert_true(m.hops > 0, "it hops (%d)" % m.hops)
	assert_true(hi <= 0.7 + 0.01, "never the second floor up (highest %.2f m)" % hi)
	assert_true(lo >= -0.7 - 0.01, "never the second floor down (lowest %.2f m)" % lo)
	assert_true(floors.has(1) and floors.has(-1), "reached the floor above and the floor below: %s" % [floors.keys()])
	assert_true(floors.has(0), "and its spawn floor")


## A knockback hit while the Orange Mushroom is in mid-hop toward the attacker: the hop is cancelled, it falls, and over
## the stagger it is pushed the full knockback distance away from the attacker, like a monster hit on the ground
## (test_b WARN #43: Iteration Two let the hop carry it on, up to 1.4 m, toward the attacker).
func test_a_hit_mid_hop_is_pushed_away_from_the_attacker() -> void:
	rig.floor(30.0)
	var m := rig.spawn("9", Vector3.ZERO, Vector3.RIGHT)
	m.brain.mode = MonsterBrain.Mode.WALK
	m.brain.heading = Vector3.RIGHT
	m.brain.timer = 100.0
	m.brain.hop_timer = 0.0
	for i in 60:
		rig.tick()
		if m.hops > 0:
			break
	assert_true(m.airborne and m.hops == 1, "hopping")
	for i in 10:
		rig.tick()
	assert_true(m.airborne, "still in the air")
	var attacker := Node3D.new()
	rig.system.add_child(attacker)
	attacker.global_position = m.global_position + Vector3(2.0, -m.global_position.y, 0.0)
	var at_hit := m.global_position
	var res := DamageResult.new()
	res.final = 1
	res.knockback = true
	m.receive_hit(res, attacker)
	assert_eq(m.brain.mode, MonsterBrain.Mode.STAGGER, "staggered")
	assert_eq(m.hops_cut, 1, "the hop was cut short")
	m.brain.chase_left = 0.0  # measure the push alone (no chase toward the attacker after it)
	var ticks := 0
	while m.brain.mode == MonsterBrain.Mode.STAGGER and ticks < 120:
		rig.tick()
		ticks += 1
	assert_false(m.airborne, "landed during the stagger")
	var moved := Vector3(m.global_position.x - at_hit.x, 0.0, m.global_position.z - at_hit.z)
	assert_near(moved.length(), m.def.knockback_m, 0.03, "pushed the knockback distance (%.3f m)" % moved.length())
	assert_true(moved.normalized().dot(Vector3.LEFT) > 0.9, "away from the attacker (%s)" % moved)
	attacker.free()


func parity_keys() -> Dictionary:
	return {
		"test_the_spawn_floor_band": ["mechanic:monster-movement-floor-walker"],
		"test_a_jumper_reaches_one_floor_above_or_below_its_spawn_floor_and_no_further": ["mechanic:monster-movement-jumper", "monster:9"],
		"test_a_slot_monster_takes_its_spawn_region_tier": ["mechanic:monster-movement-floor-walker"],
		"test_a_walker_never_climbs_a_ramp_off_its_floor": ["mechanic:monster-movement-floor-walker", "monster:2"],
		"test_a_walker_paces_back_and_forth_on_its_line": ["mechanic:monster-movement-floor-walker", "monster:4"],
		"test_orange_mushroom_hops_to_the_floors_next_to_its_spawn_floor_only": ["mechanic:monster-movement-jumper", "monster:9"],
		"test_a_hit_mid_hop_is_pushed_away_from_the_attacker": ["mechanic:monster-knockback-push", "monster:9"],
	}
