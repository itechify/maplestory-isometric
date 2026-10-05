extends TestCase
## Monster deaths and contact damage, end to end on canonical data with seeded RNGs:
##   - a kill grants exactly the canonical EXP (Game.gain_exp), emits monster_killed and loot_dropped (the canonical
##     drop table rolled once at death), is recorded in MapInstanceState, and the slot respawns on the canonical tick
##   - survivors keep their HP through a release and a realize
##   - contact damage is CombatFormula.resolve_monster_touch applied to the character, gated by the canonical
##     post-hit invincibility, with MISS/GUARD outcomes, the Peace rule, the death announcement and no touches
##     during a warp

var rig: MonsterTestRig


func before_each() -> void:
	rig = MonsterTestRig.create(db(), 2024)
	rig.floor(60.0)


func after_each() -> void:
	rig.free_all()


func _hold(m: Monster) -> void:
	m.brain.mode = MonsterBrain.Mode.IDLE
	m.brain.timer = 1000.0


func _canon_invincibility() -> float:
	return CombatFormula.post_hit_invincibility_s(db())


# --- kills ----------------------------------------------------------------------------------------------------------

func test_a_seeded_kill_grants_exactly_the_canonical_exp_and_announces_it() -> void:
	rig.set_weapon("541")
	rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var m := rig.spawn("2", Vector3(1.2, 0, 0))
	m.map_id = "000000040"
	_hold(m)
	var c := rig.character()
	var level_before := c.level
	var exp_before := c.exp
	var pc := rig.system.player_combat
	var swings := 0
	while m.is_alive() and swings < 20:
		pc.lockout_left = 0.0
		pc.attack()
		swings += 1
	assert_true(m.is_dying(), "the Snail died (%d swings)" % swings)
	assert_between(swings, 3, 6, "a Sword kills a Snail in a handful of hits (Beginner's guide: 3-4)")
	var canonical_exp := int(db().monster("2")["exp"])
	assert_eq(c.level, level_before, "no level-up from one Snail")
	assert_eq(c.exp - exp_before, canonical_exp, "exactly the canonical EXP")
	var gained := rig.events_named("exp_gained")
	assert_eq(gained.size(), 1, "one exp_gained")
	assert_eq(int(gained[0][1]), canonical_exp)
	assert_eq(String(gained[0][2]), "monster:2", "the source names the monster")
	var killed := rig.events_named("monster_killed")
	assert_eq(killed.size(), 1, "one monster_killed")
	assert_eq(killed[0].slice(1), ["2", "000000040"], "monster_killed(monster_id, map_id)")
	assert_eq(rig.system.kills, 1)
	# Hits after death do nothing.
	pc.lockout_left = 0.0
	assert_eq(pc.attack(), null, "a dying monster is no longer a target")
	assert_eq(rig.events_named("monster_killed").size(), 1, "killed once")


func test_every_species_dies_to_the_basic_attack_with_its_own_canonical_exp_and_drops() -> void:
	# Brief Test B: fight every implemented monster. Each Maple Island species takes Sword hits from a fresh level-1
	# Beginner, staggers, shows its HP bar, dies, and awards exactly its own canonical EXP and its own drop table.
	var species := ["1", "2", "3", "4", "5", "9"]
	for id in species:
		var r := MonsterTestRig.create(db(), 4242)
		r.floor(30.0)
		r.set_weapon("541")
		r.spawn_player(Vector3.ZERO, Vector3.RIGHT)
		var m := r.spawn(id, Vector3(1.2, 0, 0))
		m.map_id = "000001020"
		m.brain.mode = MonsterBrain.Mode.IDLE
		m.brain.timer = 1000.0
		var pc := r.system.player_combat
		var swings := 0
		var staggered := false
		var bar := false
		while m.is_alive() and swings < 40:
			pc.lockout_left = 0.0
			# Stand still at the same spot so every swing reaches it (the stagger pushes it 20 px).
			m.global_position = Vector3(1.2, 0, 0)
			pc.attack()
			swings += 1
			staggered = staggered or m.brain.mode == MonsterBrain.Mode.STAGGER
			bar = bar or (m.visual.hp_bar.visible and m.is_alive())
		var rec := db().monster(id)
		assert_true(m.is_dying(), "%s died (%d swings)" % [rec["name"], swings])
		assert_true(staggered, "%s staggers when a hit reaches its KB" % rec["name"])
		assert_true(bar or swings == 1, "%s shows its HP bar while damaged" % rec["name"])
		var canonical_exp := int(rec["exp"])
		var gained := r.events_named("exp_gained")
		assert_eq(gained.size(), 1 if canonical_exp > 0 else 0, "%s: one exp_gained" % rec["name"])
		if gained.size() == 1:
			assert_eq(int(gained[0][1]), canonical_exp, "%s: exactly its canonical EXP" % rec["name"])
			assert_eq(String(gained[0][2]), "monster:%s" % id)
		var killed := r.events_named("monster_killed")
		assert_eq(killed.size(), 1, "%s: one monster_killed" % rec["name"])
		if killed.size() == 1:
			assert_eq(killed[0].slice(1), [id, "000001020"], "%s: monster_killed(id, map)" % rec["name"])
		var table := {}
		for e in db().drop_table(id).get("entries", []):
			table[str(e["item_id"])] = true  # [drops package] null for an unresolved member
		for l in r.events_named("loot_dropped"):
			for d in l[1]:
				if String(d["kind"]) == "item":
					assert_true(table.has(String(d["item_id"])), "%s drops item %s from its own table" % [rec["name"], d["item_id"]])
		r.free_all()


func test_drops_are_the_canonical_table_rolled_once_at_death() -> void:
	var m := rig.spawn("2", Vector3(3, 0, 0))
	m.map_id = "000000040"
	# Find a seed whose roll drops something (rates are placeholders; the roll itself is DropRoller's).
	var seed_value := -1
	var expected: Array = []
	for s in range(1, 200):
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		expected = DropRoller.roll("2", db(), probe)
		if not expected.is_empty():
			seed_value = s
			break
	assert_true(seed_value > 0, "some seed drops something")
	rig.rng.seed = seed_value
	var at := m.global_position
	m.die()
	var loot := rig.events_named("loot_dropped")
	assert_eq(loot.size(), 1, "one loot_dropped")
	if loot.size() == 1:
		assert_eq(loot[0][1], expected, "DropRoller.roll output, rolled at death with the gameplay RNG")
		assert_true((loot[0][2] as Vector3).is_equal_approx(at), "at the monster's feet")
		assert_eq(String(loot[0][3]), "000000040", "map id")
		var table := {}
		for e in db().drop_table("2")["entries"]:
			table[str(e["item_id"])] = true  # [drops package] null for an unresolved member
		for d in loot[0][1]:
			if String(d["kind"]) == "item":
				assert_true(table.has(String(d["item_id"])), "item %s is in the canonical table" % d["item_id"])
	# A death that drops nothing announces no loot.
	var empty_seed := -1
	for s in range(1, 400):
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		if DropRoller.roll("2", db(), probe).is_empty():
			empty_seed = s
			break
	if empty_seed > 0:
		var m2 := rig.spawn("2", Vector3(-3, 0, 0))
		rig.rng.seed = empty_seed
		m2.die()
		assert_eq(rig.events_named("loot_dropped").size(), 1, "no loot_dropped for an empty roll")


func _live_map(map_id: String) -> Dictionary:
	var defs := MapDefinitions.build(db(), null)
	var def := defs.get_def(map_id)
	# No export in this test: lay the slots out on the test floor.
	var cols := 8
	for i in def.monster_spawn_definitions.size():
		var s := def.monster_spawn_definitions[i]
		s.transform = Transform3D(Basis.IDENTITY, Vector3(-20.0 + 5.0 * (i % cols), 0.0, -20.0 + 5.0 * (i / cols)))
	var view := MapInstanceView.new()
	view.name = "Monsters"
	view.tuning = WorldTuning.from_db(db())
	var now := [0.0]
	view.clock = func() -> float: return now[0]
	rig.w.host.add_child(view)
	rig.system.use_view(view)
	var model := SpawnModel.from_db(db())
	var srng := RandomNumberGenerator.new()
	srng.seed = 11
	var st := MapInstanceState.fresh(def, model, srng, 0.0)
	view.realize(st, def, Vector3.ZERO)
	var guard := 0
	while view.pending_count() > 0 and guard < 100:
		view._process(0.0)
		guard += 1
	return {"def": def, "view": view, "state": st, "now": now, "model": model}


func test_kill_is_recorded_and_the_slot_respawns_on_the_canonical_tick() -> void:
	var live := _live_map("000000040")
	var view: MapInstanceView = live.view
	var st: MapInstanceState = live.state
	var now: Array = live.now
	var model: SpawnModel = live.model
	assert_eq(view.live_count(), st.capacity, "the map fills to capacity with real monsters")
	for i in view.nodes:
		var n: Node = view.nodes[i]
		assert_true(n is Monster, "slot %d is a Monster, not a static proxy" % i)
		assert_eq(String(n.get_meta("mob_id")), (n as Monster).def.id, "species of slot %d" % i)
		assert_eq((n as Monster).hp, (n as Monster).def.max_hp, "full HP")
	var k: int = st.alive_indices()[0]
	# Keep every never-alive slot out of the next tick, so the respawn there can only be ours.
	for i in st.slots.size():
		if not st.is_alive(i):
			st.slots[i]["died_at"] = 1.0e6
	now[0] = 1.0
	var m: Monster = view.nodes[k]
	m.die()
	assert_false(st.is_alive(k), "the kill is recorded in MapInstanceState")
	assert_near(float(st.slots[k]["died_at"]), 1.0, 1e-9, "died_at = the game clock at death")
	assert_false(view.nodes.has(k), "released from the view")
	assert_true(is_instance_valid(m) and m.is_dying(), "the body stays to fade out (canonical die time)")
	var tick := float(db().formula("spawn_rate")["global_respawn_tick_s"])
	var cooldown := float(db().formula("spawn_rate")["wave_point_cooldown_s"])
	var due := model.respawn_time(1.0)
	assert_near(due, ceil((1.0 + cooldown) / tick) * tick, 1e-9, "first %.2f s boundary after death + %.0f s" % [tick, cooldown])
	assert_near(due, 7.56, 1e-9, "the 7.56 s tick")
	now[0] = due - 0.01
	view._process(0.0)
	assert_false(st.is_alive(k), "not before the tick")
	assert_false(view.nodes.has(k))
	now[0] = due
	view._process(0.0)
	assert_true(st.is_alive(k), "respawned on the tick")
	assert_true(view.nodes.has(k) and view.nodes[k] is Monster and view.nodes[k] != m, "a fresh Monster in the slot")
	assert_eq((view.nodes[k] as Monster).hp, (view.nodes[k] as Monster).def.max_hp, "at full HP")
	assert_eq(view.live_count(), st.capacity, "back to capacity")


func test_survivors_keep_their_hp_through_release_and_realize() -> void:
	var live := _live_map("000000041")
	var view: MapInstanceView = live.view
	var st: MapInstanceState = live.state
	var k: int = st.alive_indices()[1]
	var m: Monster = view.nodes[k]
	m.hp = m.def.max_hp - 7
	view.release()
	assert_eq(int(st.slots[k]["hp"]), m.def.max_hp - 7, "HP written back on release")
	view.realize(st, live.def, Vector3.ZERO)
	while view.pending_count() > 0:
		view._process(0.0)
	assert_eq((view.nodes[k] as Monster).hp, m.def.max_hp - 7, "restored at its slot with that HP")


func test_setup_replaces_static_proxies_on_an_already_live_map() -> void:
	var defs := MapDefinitions.build(db(), null)
	var def := defs.get_def("000000040")
	var view := MapInstanceView.new()
	view.tuning = WorldTuning.from_db(db())
	view.clock = func() -> float: return 0.0
	rig.w.host.add_child(view)
	var st := MapInstanceState.fresh(def, SpawnModel.from_db(db()), RandomNumberGenerator.new(), 0.0)
	view.realize(st, def, Vector3.ZERO)
	while view.pending_count() > 0:
		view._process(0.0)
	var any: Node = view.nodes.values()[0]
	assert_false(any is Monster, "default proxies before the monster system")
	rig.system.use_view(view)
	while view.pending_count() > 0:
		view._process(0.0)
	assert_eq(view.live_count(), st.capacity)
	for n in view.nodes.values():
		assert_true(n is Monster, "re-realized as real monsters")


# --- contact damage --------------------------------------------------------------------------------------------------

func test_contact_damage_uses_the_touch_formula_and_respects_invulnerability() -> void:
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var m := rig.spawn("9", Vector3(0.3, 0, 0))
	_hold(m)
	var c := rig.character()
	# Find a seed where the first touch lands, then expect exactly CombatFormula's numbers with that seed.
	var seed_value := -1
	var expected: IncomingResult = null
	for s in range(1, 100):
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		expected = CombatFormula.resolve_monster_touch(m.def.stats, PlayerCombatStats.from_character(c, db()), probe, db())
		if expected.landed():
			seed_value = s
			break
	assert_true(seed_value > 0, "an Orange Mushroom touch lands for some seed")
	rig.rng.seed = seed_value
	var hp0 := c.hp
	rig.tick()
	assert_eq(rig.system.touches, 1, "one touch resolved")
	assert_eq(hp0 - c.hp, expected.final, "HP lost = CombatFormula.resolve_monster_touch(...).final")
	var dmg := rig.events_named("player_damaged")
	assert_eq(dmg.size(), 1, "Events.player_damaged")
	assert_eq(dmg[0].slice(1), [expected.final, "9"])
	var hpc := rig.events_named("hp_changed")
	assert_true(hpc.size() >= 1 and int(hpc[-1][1]) == c.hp, "Events.hp_changed with the new HP")
	assert_true(p.is_invulnerable(), "invulnerable after the hit")
	assert_near(p.invulnerable_time_left(), _canon_invincibility() - MonsterTestRig.TICK, MonsterTestRig.TICK * 1.5, "for the canonical %.1f s" % _canon_invincibility())
	assert_true(p.in_hitstun, "knocked back")
	assert_true(rig.system.damage_numbers.live_texts().has(str(expected.final)), "a damage-taken number shows")
	# Keep the player inside the touch zone: no further damage while invulnerable.
	var hp1 := c.hp
	var keep := func(_i: int) -> void:
		p.global_position = Vector3(0.1, 0, 0)
	rig.run(int(_canon_invincibility() / MonsterTestRig.TICK) - 3, keep)
	assert_eq(c.hp, hp1, "no damage while invulnerable")
	assert_eq(rig.system.touches, 1, "no touch resolved while invulnerable")
	rig.run(10, keep)
	assert_eq(rig.system.touches, 2, "touched again once the invincibility ended")


func test_a_missed_touch_grants_invincibility_without_damage_or_push() -> void:
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var m := rig.spawn("2", Vector3(0.3, 0, 0))
	_hold(m)
	# A level-1 Beginner almost never dodges a Snail; give this one a poor aim so a miss is easy to find.
	m.def = MonsterDef.build("2", db())
	m.def.stats.acc = 2
	var c := rig.character()
	var seed_value := -1
	for s in range(1, 2000):
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		if CombatFormula.resolve_monster_touch(m.def.stats, PlayerCombatStats.from_character(c, db()), probe, db()).missed:
			seed_value = s
			break
	assert_true(seed_value > 0, "a Snail touch misses for some seed")
	rig.rng.seed = seed_value
	var hp0 := c.hp
	rig.tick()
	assert_eq(c.hp, hp0, "a miss deals nothing")
	assert_eq(rig.events_named("player_missed_by").size(), 1, "Events.player_missed_by")
	assert_true(p.is_invulnerable(), "the canonical invincibility also follows a miss")
	assert_false(p.in_hitstun, "no push on a miss (combat.json player_knockback)")
	assert_true(rig.system.damage_numbers.live_texts().has("MISS"), "MISS shows over the player")


func test_a_guarded_touch_applies_like_a_miss() -> void:
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var c := rig.character()
	var res := IncomingResult.new()
	res.guarded = true
	res.invincibility_s = _canon_invincibility()
	var hp0 := c.hp
	var lost := ContactDamage.apply(res, "2", Vector3(1, 0, 0), p, c, db(), rig.bus)
	assert_eq(lost, 0)
	assert_eq(c.hp, hp0, "a guard deals nothing")
	assert_true(p.is_invulnerable(), "and grants the invincibility")
	assert_eq(rig.events_named("player_missed_by").size(), 1)
	rig.system.damage_numbers.guard(Vector3.UP, p)
	assert_true(rig.system.damage_numbers.live_texts().has("GUARD"), "GUARD text exists")


func test_peace_monster_touches_only_after_being_provoked() -> void:
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var m := rig.spawn("1", Vector3(0.2, 0, 0))
	_hold(m)
	rig.run(30)
	assert_eq(rig.system.touches, 0, "walking into an unprovoked Tutorial Jr. Sentinel is safe")
	assert_false(p.is_invulnerable())
	m.brain.provoked = true
	rig.tick()
	assert_eq(rig.system.touches, 1, "provoked: its touch zone attacks")


func test_hp_zero_announces_the_death() -> void:
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var m := rig.spawn("9", Vector3(0.3, 0, 0))
	m.map_id = "000001020"
	_hold(m)
	var c := rig.character()
	c.hp = 1
	var seed_value := -1
	for s in range(1, 100):
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		if CombatFormula.resolve_monster_touch(m.def.stats, PlayerCombatStats.from_character(c, db()), probe, db()).landed():
			seed_value = s
			break
	rig.rng.seed = seed_value
	rig.tick()
	assert_eq(c.hp, 0, "HP clamps at 0")
	var died := rig.events_named("player_died")
	assert_eq(died.size(), 1, "Events.player_died (no MapSession could take it)")
	assert_eq(String(died[0][1]), "000001020")
	assert_true(p.is_dead(), "the player is in its death state")
	rig.run(120)
	assert_eq(rig.system.touches, 1, "no touches on a dead player")


func test_no_touch_while_the_session_is_warping() -> void:
	rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var m := rig.spawn("9", Vector3(0.3, 0, 0))
	_hold(m)
	rig.set_session_state("WARP_OUT")
	rig.run(10)
	assert_eq(rig.system.touches, 0, "no contact damage during a warp")
	rig.set_session_state("IDLE")
	rig.tick()
	assert_eq(rig.system.touches, 1, "contact resumes when idle")


func test_touch_geometry_is_the_canonical_touch_zone() -> void:
	var size := MonsterDef.from_id("2", db()).touch_size_m
	var r := 0.3
	var h := 1.5
	# Just inside / just outside the zone's half width plus the body radius, along the monster's facing.
	assert_true(MeleeQuery.touch_overlaps(Vector3.ZERO, Vector3.RIGHT, size, Vector3(size.x * 0.5 + r - 0.01, 0, 0), r, h))
	assert_false(MeleeQuery.touch_overlaps(Vector3.ZERO, Vector3.RIGHT, size, Vector3(size.x * 0.5 + r + 0.01, 0, 0), r, h))
	assert_true(MeleeQuery.touch_overlaps(Vector3.ZERO, Vector3.RIGHT, size, Vector3(0, 0, size.z * 0.5 + r - 0.01), r, h), "depth = width")
	assert_false(MeleeQuery.touch_overlaps(Vector3.ZERO, Vector3.RIGHT, size, Vector3(0, size.y + 0.01, 0), r, h), "standing above the zone")
	assert_false(MeleeQuery.touch_overlaps(Vector3.ZERO, Vector3.RIGHT, size, Vector3(0, -h - 0.01, 0), r, h), "below it")
