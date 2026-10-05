extends TestCase
## The real Debug autoload, headless: its built-ins are installed synchronously in _ready next to the commands other
## autoloads register (MapSession's map_*), and Debug.run() drives the autoloads directly (what the traversal bot
## does). Read-only and failure-path commands run as they are; the one warp restores MapSession and Game afterwards.


func _debug() -> DebugTools:
	return (Engine.get_main_loop() as SceneTree).root.get_node("Debug") as DebugTools


func _session() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("MapSession")


func test_the_autoload_has_the_builtins_and_the_other_systems_commands() -> void:
	var d := _debug()
	assert_true(d != null and d.builtins != null, "built-ins installed in _ready")
	for c in ["warp", "portals", "where", "showmap", "coords", "collision", "spawns", "portaldata", "spawn", "kill",
			"exp", "level", "mesos", "give", "clearinv", "quest", "quests", "reload", "heal", "god", "linkmode",
			"timescale", "screenshot", "seed", "help", "map_warp", "map_info", "map_link_mode", "map_reload",
			"quest_accept", "quest_complete", "quest_reset"]:
		assert_true(d.has_command(c), "%s registered" % c)
	assert_eq(d.resolve_name("reset"), "reset_save", "reset reuses the save system's reset_save")
	assert_true(d.run("help").contains("map_warp <map_id> [portal]"), "help includes MapSession's commands")


func test_read_only_and_failing_commands_against_the_autoloads() -> void:
	var d := _debug()
	var before := String(_session().get("current_map"))
	assert_true(d.run("portals 000000040").begins_with("000000040 Snail Hunting Ground I:"), "portals")
	assert_true(d.run("warp nowhere").begins_with("warp: no map matches"), "unknown map")
	assert_eq(d.run("maps").split("\n").size(), 25, "maps")
	assert_eq(String(_session().get("current_map")), before, "nothing moved")


func test_warp_through_the_autoloads_then_restore() -> void:
	var d := _debug()
	var ms := _session()
	if ms.get("world") != null:
		print("SKIP test_warp_through_the_autoloads_then_restore: a world is attached to MapSession")
		return
	var game := (Engine.get_main_loop() as SceneTree).root.get_node("Game")
	var c: CharacterState = game.get("character")
	var saved := {}
	for f in ["state", "current_map", "instance_state", "last_arrival", "last_transition", "respawn_reference", "cache"]:
		saved[f] = ms.get(f)
	var log_copy: Array = (ms.get("transition_log") as Array).duplicate()
	var loc := c.location.duplicate(true)
	var respawn := c.respawn_reference
	ms.set("cache", MapStateCache.new())
	var out := d.run("warp 000000040")
	assert_eq(out, "warped to 000000040 Snail Hunting Ground I at player_spawns[0]", "Debug.run(\"warp 000000040\")")
	assert_eq(String(ms.get("current_map")), "000000040", "MapSession moved")
	assert_true(d.overlay_text().contains("MAP  000000040"), "overlay")
	assert_true(d.run("where").begins_with("000000040 Snail Hunting Ground I"), "where")
	for f in saved:
		ms.set(f, saved[f])
	(ms.get("transition_log") as Array).assign(log_copy)
	c.location = loc
	c.respawn_reference = respawn
