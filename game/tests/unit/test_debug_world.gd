extends TestCase
## The console against the real island (needs the Blender export: INCLUDE_WORLD=1; prints SKIP without it). The
## world is built synchronously (collision only) into the runner's tree and attached to a private DebugHarness
## session; with no player registered every warp completes in the same call.
##
## Checks: warp to all 25 maps through the command with the world swapping instances and portals; every draw layer
## builds real lines in a hunting map and follows a map change; debug spawns never occupy a slot and leave with the
## map; kill nearest/all go through the view and announce monster_killed (the static-proxy fallback, and the real
## MonsterSystem death path the game uses); reload; goto and coords with a player;
## the overlay text names the map.

var h: DebugHarness = null
var world: IslandWorld = null
## A MonsterSystem a test installed on the world (freed first in after_each).
var monsters: MonsterSystem = null


func before_each() -> void:
	if not WorldSidecars.exists():
		return
	h = DebugHarness.create(db())
	world = IslandWorld.new()
	world.name = "DebugTestWorld"
	world.build_on_ready = false
	world.load_visuals = false
	world.attach_to_session = false
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(world)
	world.build_now(db())
	h.attach_world(world)


func after_each() -> void:
	if monsters != null and is_instance_valid(monsters):
		monsters.free()
	monsters = null
	if world != null:
		world.free()
	if h != null:
		h.free_all()


func _skip(test_name: String) -> bool:
	if WorldSidecars.exists():
		return false
	print("SKIP %s: game/assets/world not present (run with INCLUDE_WORLD=1)" % test_name)
	return true


func _defs() -> MapDefinitions:
	return h.session.call("get_defs")


## Spawns every queued monster of the live instance (MapInstanceView realizes a few per frame).
func _realize() -> void:
	for i in 40:
		if world.instance_view.pending_count() == 0:
			break
		world.instance_view._process(0.0)


func test_warp_to_every_map_with_the_world() -> void:
	if _skip("test_warp_to_every_map_with_the_world"):
		return
	assert_eq(world.build_errors.size(), 0, "world built: %s" % "; ".join(world.build_errors))
	assert_eq(_defs(), world.defs, "the session uses the world's grounded definitions")
	for id in _defs().ids():
		var out := h.run("warp " + id)
		assert_true(out.begins_with("warped to " + id), out)
		assert_eq(String(h.session.get("current_map")), id, "current map")
		assert_eq(world.instance_view.def.map_id, id, "the world realized %s" % id)
		for wp in world.portals_of(id):
			assert_true(wp.interaction_enabled, "%s portals enabled" % id)
		var text := h.dbg.overlay_text()
		assert_true(text.contains("MAP  %s" % id), "overlay names %s" % id)


func test_draw_layers_in_a_hunting_map() -> void:
	if _skip("test_draw_layers_in_a_hunting_map"):
		return
	h.run("warp 000000040")
	var def := _defs().get_def("000000040")
	var expect := {
		"collision": ["collision on", 1000, 0],
		"spawns": ["spawns on", def.monster_spawn_definitions.size() * 2, def.monster_spawn_definitions.size()],
		"portals": ["portaldata on", def.portals.size() * 4, def.portals.size()],
		"npcs": ["npcs on", def.npc_definitions.size(), def.npc_definitions.size()],
		"camera": ["bounds on", 3, 1],
		"mobregion": ["mobregion on", 3, 1],
		"rings": ["rings on", 12, 1],
		"safeground": ["safeground on", 4, 1],
	}
	for layer in expect:
		var row: Array = expect[layer]
		var out := h.run(String(row[0]))
		assert_true(out.begins_with("%s layer on (" % layer) and out.contains("in 000000040"), out)
		var st := h.dbg.draw.layer_stats(layer)
		assert_true(int(st.segments) >= int(row[1]), "%s: %d lines (expected >= %d)" % [layer, int(st.segments), int(row[1])])
		assert_true(int(st.labels) >= int(row[2]), "%s: %d labels (expected >= %d)" % [layer, int(st.labels), int(row[2])])
	assert_eq(h.dbg.draw.get_parent(), world, "the draw node lives under the world")
	# The collision wireframe is clipped to the map: a small interior has far fewer lines than the hunting field.
	var field := int(h.dbg.draw.layer_stats("collision").segments)
	var interior: String = _defs().id_of_v8["1010001"]
	h.run("warp " + interior)
	h.dbg.draw.rebuild_now()
	assert_eq(String(h.dbg.draw.layer_stats("portals").map), interior, "layers follow the map change")
	assert_true(int(h.dbg.draw.layer_stats("collision").segments) < field, "collision clipped to the current map")
	h.run("draw all off")
	for layer in expect:
		assert_false(h.dbg.is_layer_on(layer), "%s off" % layer)


func test_debug_spawns_kill_and_reload() -> void:
	if _skip("test_debug_spawns_kill_and_reload"):
		return
	h.run("warp 000000040")
	_realize()
	var view := world.instance_view
	var inst: MapInstanceState = h.session.get("instance_state")
	var live := view.live_count()
	assert_eq(live, inst.alive_count(), "all alive slots realized")
	var out := h.run("spawn 2 3")
	assert_true(out.begins_with("spawned 3 x Snail (2) in 000000040"), out)
	var spawns := h.dbg.builtins.debug_spawns
	assert_eq(spawns.size(), 3, "three debug spawns")
	var def := _defs().get_def("000000040")
	for m in spawns:
		assert_true(bool(m.get_meta("debug_spawn", false)) and bool(m.get_meta("non_canonical", false)), "flagged")
		assert_eq(int(m.get_meta("spawn_slot")), -1, "never a slot")
		assert_eq(String(m.get_meta("mob_id")), "2", "species")
		assert_true(def.footprint_contains(m.global_position), "inside the map")
	assert_eq(view.live_count(), live, "slot monsters unchanged")
	assert_eq(inst.alive_count(), live, "slot state unchanged")
	assert_true(h.dbg.overlay_text().contains("debug spawns 3"), "overlay counts them")
	out = h.run("kill nearest")
	assert_true(out.begins_with("killed 1 in 000000040"), out)
	assert_eq(view.live_count() + h.dbg.builtins.debug_spawn_count(), live + 2, "one fewer monster")
	assert_eq(h.count("monster_killed"), 1, "monster_killed announced")
	out = h.run("kill all")
	assert_eq(view.live_count(), 0, "no slot monsters left")
	assert_eq(h.dbg.builtins.debug_spawn_count(), 0, "no debug spawns left")
	assert_eq(inst.alive_count(), 0, "every slot dead in the state")
	assert_eq(h.count("monster_killed"), live + 3, "one monster_killed per kill")
	h.run("spawn snail 2")
	out = h.run("reload")
	assert_true(out.contains("2 debug spawns removed"), out)
	_realize()
	var fresh: MapInstanceState = h.session.get("instance_state")
	assert_eq(view.live_count(), fresh.capacity, "reload realized a full instance")
	h.run("spawn 2 2")
	h.run("warp 000000041")
	assert_eq(h.dbg.builtins.debug_spawn_count(), 0, "debug spawns leave with their map")


## What the game runs: the MonsterSystem's factory on the world's view. `kill` must go through Monster.die() (EXP
## through Game.gain_exp, one monster_killed from the monster system, the slot freed by the view's died link), and
## debug spawns are real Monsters that still never occupy a slot.
func test_kill_and_spawn_through_the_real_monster_system() -> void:
	if _skip("test_kill_and_spawn_through_the_real_monster_system"):
		return
	monsters = MonsterSystem.new()
	var ms := monsters
	ms.name = "DebugTestMonsters"
	ms.db = db()
	ms.game = h.game
	ms.events = h.bus
	ms.session = h.session
	var r := RandomNumberGenerator.new()
	r.seed = 5
	ms.rng = r
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(ms)
	ms.attach_world(world)
	assert_true(world.instance_view.monster_factory == Callable(ms, &"make_monster"), "the monster system's factory")
	h.run("warp 000000040")
	_realize()
	var view := world.instance_view
	var inst: MapInstanceState = h.session.get("instance_state")
	var live := view.live_count()
	assert_true(live > 0, "monsters realized")
	for n in view.nodes.values():
		assert_true(n is Monster, "real monsters, not proxies")
	var c := h.game.character
	var lv_before := c.level
	var xp_before := c.exp
	var killed_before := h.count("monster_killed")
	var out := h.run("kill nearest")
	assert_true(out.begins_with("killed 1 in 000000040") and out.contains("1 through the monster's own death"), out)
	assert_eq(ms.kills, 1, "Monster.die() ran the monster system's death")
	assert_true(ms.exp_awarded > 0, "the canonical EXP was awarded")
	assert_true(c.level > lv_before or c.exp > xp_before, "Game.gain_exp reached the character")
	assert_eq(h.count("monster_killed"), killed_before + 1, "exactly one monster_killed (Debug does not announce it again)")
	assert_eq(view.live_count(), live - 1, "the view released the slot's node")
	assert_eq(inst.alive_count(), live - 1, "the slot is dead in the instance state")
	out = h.run("spawn snail 2")
	assert_true(out.begins_with("spawned 2 x Snail (2)"), out)
	var spawns := h.dbg.builtins.debug_spawns
	assert_eq(spawns.size(), 2, "two debug spawns")
	for m in spawns:
		assert_true(m is Monster, "the monster system made them")
		assert_true(bool(m.get_meta("debug_spawn", false)), "flagged")
		assert_eq(int(m.get_meta("spawn_slot", 0)), -1, "never a slot")
		assert_false(m in view.nodes.values(), "the view does not track them")
		assert_true((m as Monster).is_alive(), "alive")
	assert_eq(inst.alive_count(), live - 1, "slot state unchanged by debug spawns")
	assert_eq((ms.live_monsters() as Array).size(), live - 1 + 2, "attackable: the monster system sees them")
	var kills_before := ms.kills
	out = h.run("kill all")
	assert_true(out.contains("through the monster's own death") and not out.contains("no EXP/drops"), out)
	assert_eq(ms.kills, kills_before + live - 1 + 2, "every slot monster and debug spawn died through die()")
	assert_eq(h.dbg.builtins.debug_spawn_count(), 0, "no debug spawns left")
	assert_eq(view.live_count(), 0, "no slot monsters left")
	assert_eq(inst.alive_count(), 0, "every slot dead")


func test_goto_and_coords_with_a_player() -> void:
	if _skip("test_goto_and_coords_with_a_player"):
		return
	h.run("warp 000000040")
	assert_true(h.run("goto slot 0").contains("needs the world and a player"), "no player yet")
	var p := WorldTestPlayer.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(p)
	world.set_player(p)
	var def := _defs().get_def("000000040")
	var out := h.run("goto slot 3")
	assert_true(out.begins_with("moved to slot 3"), out)
	assert_true(p.global_position.distance_to(def.monster_spawn_definitions[3].transform.origin) < 0.5, "at the slot")
	var portal := def.canonical_portals()[0]
	assert_true(h.run("goto portal " + portal.portal_id).begins_with("moved to portal"), "portal arrival")
	assert_true(p.global_position.distance_to(portal.spawn_transform.origin) < 0.5, "at the arrival")
	if not def.npc_definitions.is_empty():
		assert_true(h.run("goto npc " + def.npc_definitions[0].npc_id).begins_with("moved to npc"), "npc")
	assert_true(h.run("goto 99999 99999").contains("outside 000000040"), "outside the map")
	assert_true(h.run("goto slot 999").contains("has slots 0.."), "bad slot")
	var coords := h.run("coords")
	assert_true(coords.contains("region map:000000040"), coords)
	assert_true(h.dbg.overlay_text().contains("PLAYER grounded"), "player line")
	p.free()
