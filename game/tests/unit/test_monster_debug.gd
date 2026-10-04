extends TestCase
## The monster side of the debug console (DEBUG_TOOLS.md "Kill" and "Debug spawns"):
##   - Monster.debug_kill(): zero arguments, the normal death path (canonical EXP, the drop roll and
##     Events.loot_dropped, Events.monster_killed, `died` for the slot report), once
##   - a debug spawn (SpawnSlot index -1, placement "debug", metadata debug_spawn) never reports to MapInstanceView
##     and never respawns, yet dies like any monster
##   - on the real island (INCLUDE_WORLD=1) with the real MonsterSystem factory: Debug's "spawn 2 3" then "kill all",
##     checking the EXP sum, the drops (replayed with the same seed), the slot state and the respawn tick

var rig: MonsterTestRig = null
var h: DebugHarness = null
var world: IslandWorld = null
var monsters: MonsterSystem = null


func after_each() -> void:
	if rig != null:
		rig.free_all()
		rig = null
	if monsters != null and is_instance_valid(monsters):
		monsters.free()
	monsters = null
	if world != null and is_instance_valid(world):
		world.free()
	world = null
	if h != null:
		h.free_all()
		h = null


func _loot_events(r: MonsterTestRig) -> Array:
	return r.events_named("loot_dropped")


# --- debug_kill on its own ---------------------------------------------------------------------------------------------

func test_debug_kill_takes_no_arguments_and_the_console_prefers_it() -> void:
	rig = MonsterTestRig.create(db(), 11)
	rig.floor(20.0)
	var m := rig.spawn("2", Vector3(2, 0, 0))
	assert_eq(DebugCommands.zero_arg_method(m, ["debug_kill", "kill", "die"]), "debug_kill", "the console's first choice")


func test_debug_kill_runs_the_normal_death_path_once() -> void:
	rig = MonsterTestRig.create(db(), 11)
	rig.floor(20.0)
	var replay := RandomNumberGenerator.new()
	replay.seed = rig.rng.seed
	replay.state = rig.rng.state
	var m := rig.spawn("9", Vector3(2, 0, 0))
	m.map_id = "000001020"
	var died := [0]
	m.died.connect(func(_who: Monster) -> void: died[0] += 1)
	var exp_before := rig.character().exp
	var lv_before := rig.character().level
	assert_true(m.debug_kill(), "a live monster dies")
	assert_false(m.is_alive(), "dead")
	assert_true(m.is_dying(), "fading out over its canonical die time")
	assert_eq(died[0], 1, "`died` fires once (the slot report)")
	assert_eq(rig.system.kills, 1, "the monster system ran its death handling")
	var gained := rig.events_named("exp_gained")
	assert_eq(gained.size(), 1, "one exp_gained")
	assert_eq(int(gained[0][1]), int(db().monster("9")["exp"]), "exactly the canonical EXP")
	assert_eq(String(gained[0][2]), "monster:9", "credited to the monster")
	assert_true(rig.character().exp != exp_before or rig.character().level > lv_before, "the character got it")
	var killed := rig.events_named("monster_killed")
	assert_eq(killed.size(), 1, "one monster_killed")
	assert_eq([String(killed[0][1]), String(killed[0][2])], ["9", "000001020"], "id and map")
	var expected := DropRoller.roll("9", db(), replay)
	var loot := _loot_events(rig)
	assert_eq(loot.size(), 0 if expected.is_empty() else 1, "loot_dropped when the seeded roll drops something")
	if not loot.is_empty():
		assert_eq(loot[0][1], expected, "the same drops as DropRoller.roll with the same seed")
		assert_eq(String(loot[0][3]), "000001020", "on its map")
	assert_false(m.debug_kill(), "a second kill does nothing")
	assert_eq(rig.system.kills, 1, "no second death")
	assert_eq(died[0], 1, "no second `died`")
	assert_eq(rig.events_named("exp_gained").size(), 1, "no second award")


func test_debug_kill_on_an_unset_monster_does_nothing() -> void:
	var m := Monster.new()
	assert_false(m.debug_kill(), "no species, nothing to kill")
	m.die()  # die() itself no longer needs a brain
	assert_true(m.is_dying(), "die() on a bare monster marks it dying without errors")
	m.free()


func test_drops_over_many_debug_kills_come_from_the_canonical_table() -> void:
	rig = MonsterTestRig.create(db(), 23)
	rig.floor(30.0)
	var table := {}
	for e in db().drop_table("2").get("entries", []):
		table[String((e as Dictionary).get("item_id", ""))] = true
	for i in 40:
		var m := rig.spawn("2", Vector3(-10 + i * 0.5, 0, 3))
		m.debug_kill()
	assert_eq(rig.system.kills, 40, "40 deaths")
	assert_eq(rig.events_named("exp_gained").size(), 40, "40 awards")
	assert_eq(rig.events_named("monster_killed").size(), 40, "40 monster_killed")
	assert_true(_loot_events(rig).size() > 0, "40 Snails drop something")
	for e in _loot_events(rig):
		for d in e[1]:
			var item := String((d as Dictionary).get("item_id", ""))
			if item != "":
				assert_true(table.has(item), "item %s is in the Snail's canonical drop table" % item)


func test_a_debug_slot_is_no_slot() -> void:
	rig = MonsterTestRig.create(db(), 5)
	rig.floor(20.0)
	var slot := SpawnSlot.new()
	slot.index = -1
	slot.mob_id = "2"
	slot.placement = "debug"
	slot.transform = Transform3D(Basis.IDENTITY, Vector3(1, 0, 1))
	var m := rig.system.make_monster("2", slot) as Monster
	assert_eq(m.slot_index, Monster.NO_SLOT, "slot index -1 is no slot")
	assert_false(m.has_slot(), "has_slot")
	assert_eq(m.hp, m.def.max_hp, "full HP")
	m.set_meta("debug_spawn", true)
	assert_true(m.is_debug_spawn(), "flagged by the console's metadata")
	slot.index = 4
	var real := rig.system.make_monster("2", slot) as Monster
	assert_eq(real.slot_index, 4, "a real slot index is kept")
	assert_true(real.has_slot(), "fills a slot")
	m.free()
	real.free()


# --- the console on the real island ---------------------------------------------------------------------------------

func _skip(test_name: String) -> bool:
	if WorldSidecars.exists():
		return false
	print("SKIP %s: game/assets/world not present (run with INCLUDE_WORLD=1)" % test_name)
	return true


## The real island attached to a private DebugHarness, with the real MonsterSystem factory on its view (what the
## game runs), on Snail Hunting Ground I with every slot realized.
func _island(seed_value: int) -> void:
	h = DebugHarness.create(db())
	world = IslandWorld.new()
	world.name = "MonsterDebugWorld"
	world.build_on_ready = false
	world.load_visuals = false
	world.attach_to_session = false
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(world)
	world.build_now(db())
	h.attach_world(world)
	monsters = MonsterSystem.new()
	monsters.name = "MonsterDebugSystem"
	monsters.db = db()
	monsters.game = h.game
	monsters.events = h.bus
	monsters.session = h.session
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	monsters.rng = r
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(monsters)
	monsters.attach_world(world)
	world.instance_view.clock = func() -> float: return h.now
	h.run("warp 000000040")
	_pump()


## Runs the view's frame until nothing is queued: the instance ticks on the clock (respawns), then the queued slots
## spawn (MapInstanceView realizes a few per frame).
func _pump() -> void:
	for i in 60:
		world.instance_view._process(0.0)
		if world.instance_view.pending_count() == 0:
			break


func test_console_spawn_then_kill_all_awards_exp_and_drops_and_never_touches_a_slot() -> void:
	if _skip("test_console_spawn_then_kill_all_awards_exp_and_drops_and_never_touches_a_slot"):
		return
	_island(77)
	var view := world.instance_view
	var inst: MapInstanceState = h.session.get("instance_state")
	var live := view.live_count()
	assert_true(live > 0 and live == inst.alive_count(), "every alive slot realized (%d)" % live)
	var released: Array = []
	view.monster_released.connect(func(n: Node3D, slot_index: int) -> void: released.append([n, slot_index]))
	var loot: Array = []
	h.bus.connect("loot_dropped", func(drops: Array, at: Vector3, map_id: String) -> void: loot.append([drops, at, map_id]))

	var out := h.run("spawn 2 3")
	assert_true(out.begins_with("spawned 3 x Snail (2) in 000000040"), out)
	var spawns: Array[Node3D] = h.dbg.builtins.debug_spawns.duplicate()
	assert_eq(spawns.size(), 3, "three debug spawns")
	for m in spawns:
		assert_true(m is Monster, "a real Monster from the monster system's factory")
		var mon := m as Monster
		assert_false(mon.has_slot(), "no slot (SpawnSlot index -1)")
		assert_true(mon.is_debug_spawn(), "flagged debug_spawn")
		assert_eq(mon.hp, mon.def.max_hp, "full HP")
		assert_false(m in view.nodes.values(), "the view does not track it")
		assert_true(mon in monsters.live_monsters(), "attackable")
	assert_eq(inst.alive_count(), live, "slot state unchanged by the spawn")
	assert_eq(view.live_count(), live, "the view's monsters unchanged")

	# Replay of the drop rolls: the monster system's RNG is used only by the drop roll here (no player, no touches).
	var replay := RandomNumberGenerator.new()
	replay.seed = monsters.rng.seed
	replay.state = monsters.rng.state
	var c := h.game.character
	var total_before := Progression.total_exp_at(c.level, c.exp, db())
	var killed_before := h.count("monster_killed")
	out = h.run("kill all")
	assert_true(out.begins_with("killed %d in 000000040" % (live + 3)), out)
	assert_true(out.contains("through the monster's own death") and not out.contains("no EXP/drops"), out)
	assert_eq(monsters.kills, live + 3, "every slot monster and debug spawn died through debug_kill()")

	# EXP: exactly the canonical EXP of each monster killed, in kill order.
	var killed_ids: Array[String] = []
	for e in h.heard:
		if e[0] == "monster_killed":
			killed_ids.append(String(e[1][0]))
	killed_ids = killed_ids.slice(killed_before)
	assert_eq(killed_ids.size(), live + 3, "one monster_killed per kill (Debug does not announce them again)")
	var expected_exp := 0
	for id in killed_ids:
		expected_exp += int(db().monster(id)["exp"])
	var gained := 0
	for e in h.heard:
		if e[0] == "exp_gained":
			assert_true(String(e[1][1]).begins_with("monster:"), "EXP comes from the kills: %s" % e[1][1])
			gained += int(e[1][0])
	assert_eq(gained, expected_exp, "EXP gained = the sum of the canonical EXP of the %d kills" % (live + 3))
	assert_eq(monsters.exp_awarded, expected_exp, "the monster system's own count agrees")
	assert_eq(Progression.total_exp_at(c.level, c.exp, db()) - total_before, expected_exp, "the character holds exactly that much more EXP")

	# Drops: one loot_dropped per non-empty roll, the same rolls as DropRoller with the same seed, on this map.
	var expected_loot: Array = []
	for id in killed_ids:
		var d := DropRoller.roll(id, db(), replay)
		if not d.is_empty():
			expected_loot.append(d)
	assert_eq(loot.size(), expected_loot.size(), "one loot_dropped per kill that dropped something")
	for i in mini(loot.size(), expected_loot.size()):
		assert_eq(loot[i][0], expected_loot[i], "kill %d dropped the seeded roll" % i)
		assert_eq(String(loot[i][2]), "000000040", "on Snail Hunting Ground I")
	assert_true(loot.size() > 0, "%d kills drop something" % (live + 3))

	# Slots: the slot monsters were reported (and released) once each; the debug spawns never were.
	assert_eq(inst.alive_count(), 0, "every slot dead")
	assert_eq(released.size(), live, "the view released one node per slot kill")
	for r in released:
		assert_true(int(r[1]) >= 0, "only real slots are released")
		assert_false(r[0] in spawns, "never a debug spawn")
	assert_eq(h.dbg.builtins.debug_spawn_count(), 0, "no debug spawns left")
	for m in spawns:
		assert_true(not is_instance_valid(m) or (m as Monster).is_dying(), "the debug spawns died")

	# The respawn tick brings back the slots, and only the slots.
	h.now += 30.0
	_pump()
	assert_eq(inst.alive_count(), inst.capacity, "the slots respawn on their tick")
	assert_eq(view.live_count(), inst.capacity, "one monster per slot, no debug spawn came back")
	var debug_back := 0
	for n in view.nodes.values():
		if (n as Node).has_meta("debug_spawn"):
			debug_back += 1
	assert_eq(debug_back, 0, "no respawned node is a debug spawn")
	var alive_debug := 0
	for m in monsters.live_monsters():
		if m.is_debug_spawn():
			alive_debug += 1
	assert_eq(alive_debug, 0, "no live debug spawn")
