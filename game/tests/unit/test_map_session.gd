extends TestCase
## MapSession logic without a world (MAP_ARCHITECTURE.md sections 4.3, 4.5, 4.8, 4.9): guards, the event order,
## the ring buffer, instances and the cache, death and respawn, the load fallback chain and the location model.
## A private MapSession instance is used (never the autoload's state); with no world every transition completes
## synchronously. The physics version (fades, grounding, triggers) is test_world_transitions.gd.

const SESSION_SCRIPT := "res://scripts/autoload/map_session.gd"

var ms: Node = null
var t: float = 0.0
var events: Array[String] = []
var _links: Array = []


func before_each() -> void:
	ms = load(SESSION_SCRIPT).new()
	ms.defs = MapDefinitions.build(db())
	ms.content = db()
	ms.character = CharacterState.new()
	var r := RandomNumberGenerator.new()
	r.seed = 42
	ms.rng = r
	ms.autosave_enabled = false
	t = 0.0
	ms.clock_provider = func() -> float: return t
	events.clear()
	var ev: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Events")
	_link(ev, "map_left", func(m: String) -> void: events.append("left:" + m))
	_link(ev, "map_entered", func(m: String, old: String) -> void: events.append("entered:%s<%s" % [m, old]))
	_link(ev, "portal_used", func(m: String, p: String, to: String) -> void: events.append("portal:%s.%s>%s" % [m, p, to]))
	_link(ev, "player_died", func(m: String) -> void: events.append("died:" + m))
	_link(ev, "player_respawned", func(m: String) -> void: events.append("respawned:" + m))


func after_each() -> void:
	for l in _links:
		(l[0] as Node).disconnect(l[1], l[2])
	_links.clear()
	ms.free()


func _link(ev: Node, sig: String, c: Callable) -> void:
	ev.connect(sig, c)
	_links.append([ev, sig, c])


func portal(map_id: String, portal_id: String) -> PortalDef:
	return ms.defs.portal(map_id, portal_id)


func test_starts_in_boot_and_new_game_enters_the_start_map() -> void:
	assert_eq(ms.state, ms.State.BOOT, "boot state")
	assert_false(ms.can_save(), "no saving in BOOT")
	assert_eq(ms.start_new_game(), OK, "new game")
	assert_eq(ms.current_map, "000000001", "new_character.json start map")
	assert_eq(ms.state, ms.State.IDLE, "idle after arriving")
	assert_eq(ms.last_arrival.to_dict(), {"map_id": "000000001", "spawn_index": 0}, "last_arrival")
	assert_eq(ms.last_transition.via, "load", "via load")
	assert_eq(ms.respawn_reference, "000000001", "respawn reference")
	assert_eq(events, ["entered:000000001<"] as Array[String], "first entry emits map_entered only")
	assert_true(ms.can_save(), "IDLE can save")
	assert_eq(ms.character.location, {"map_id": "000000001", "entry": {"map_id": "000000001", "spawn_index": 0}}, "location written")
	assert_eq(ms.character.respawn_reference, "000000001", "respawn written")


func test_press_up_event_order_and_arrival() -> void:
	ms.start_new_game()
	events.clear()
	assert_eq(ms.request_portal(portal("000000001", "out00")), OK, "press up")
	assert_eq(ms.current_map, "000000010", "destination")
	assert_eq(ms.last_arrival.to_dict(), {"map_id": "000000010", "portal_id": "in00"}, "arrives at the reciprocal portal")
	assert_eq(events, ["left:000000001", "entered:000000010<000000001", "portal:000000001.out00>000000010"] as Array[String], "event order")
	var rec: TransitionRecord = ms.last_transition
	assert_eq([rec.from_map, rec.to_map, rec.via, rec.portal_id], ["000000001", "000000010", "press_up", "out00"], "record")


func test_guards_reject_without_side_effects() -> void:
	ms.start_new_game()
	events.clear()
	assert_ne(ms.request_portal(portal("000000010", "out00")), OK, "portal of another map")
	assert_ne(ms.request_portal(null), OK, "no portal")
	assert_ne(ms.debug_warp("999999999"), OK, "unknown map")
	assert_ne(ms.debug_warp("000000040", "nope"), OK, "unknown portal")
	assert_ne(ms.respawn(), OK, "respawn while alive")
	assert_eq(ms.current_map, "000000001", "unchanged")
	assert_eq(events.size(), 0, "no events")


func test_one_way_link_cannot_be_walked_back_by_press() -> void:
	ms.start_new_game()
	ms.debug_warp("000000030")
	assert_eq(ms.request_portal(portal("000000030", "out00")), OK, "30 -> 40")
	assert_eq(ms.current_map, "000000040", "in 40")
	assert_eq(ms.last_arrival.to_dict(), {"map_id": "000000040", "spawn_index": 0}, "player_spawns[0] arrival")
	var forged := TransitionRequest.make("000000030", ArrivalRef.at_portal("000000030", "out00"), "press_up", portal("000000040", "east00"))
	assert_eq(ms.transition(forged), ERR_UNAVAILABLE, "no link 40 -> 30")
	assert_eq(ms.request_portal(portal("000000040", "arrival:T_000000030_out00__000000040")), ERR_UNAVAILABLE, "walk-only gate")
	assert_eq(ms.current_map, "000000040", "still in 40")


## A portal request cannot be redirected: the destination map and arrival are the portal's own (MeowDB toMapId and
## the PortalGraph resolution), even toward another neighbour of the same map.
func test_portal_requests_cannot_be_redirected() -> void:
	ms.start_new_game()
	ms.debug_warp("000001000")
	var to_1001 := portal("000001000", "in00")
	var redirect := TransitionRequest.make("000001002", ArrivalRef.at_portal("000001002", "out01"), "press_up", to_1001)
	assert_eq(ms.transition(redirect), ERR_UNAVAILABLE, "in00 leads to 000001001, not to its neighbour 000001002")
	var west := portal("000001000", "west00")
	var wrong_arrival := TransitionRequest.make("000000050", ArrivalRef.at_portal("000000050", "east01"), "press_up", west)
	assert_eq(ms.transition(wrong_arrival), ERR_UNAVAILABLE, "west00 arrives at 000000050.east00, not east01")
	assert_eq(ms.current_map, "000001000", "nothing changed")
	assert_eq(ms.request_portal(west), OK, "the real press")
	assert_eq(ms.last_arrival.to_dict(), {"map_id": "000000050", "portal_id": "east00"}, "resolved arrival")


## Events.player_died during a warp (a hit landing in the fade) enters DEAD when the warp completes.
func test_death_during_a_transition_is_not_lost() -> void:
	ms.start_new_game()
	ms.state = ms.State.WARP_IN
	ms._on_player_died("000000001")
	assert_eq(ms.state, ms.State.WARP_IN, "the warp is not interrupted")
	var rec := TransitionRecord.new()
	rec.via = "debug"
	rec.to_map = "000000001"
	ms._complete(rec)
	assert_eq(ms.state, ms.State.DEAD, "DEAD after the warp")
	assert_eq(ms.respawn(), OK, "respawn is possible")
	assert_eq(ms.state, ms.State.IDLE, "respawned")
	# The direct call path behaves the same: announced now, DEAD when the warp completes.
	ms.state = ms.State.ARRIVING
	events.clear()
	assert_eq(ms.enter_dead(), OK, "enter_dead mid-warp is accepted")
	assert_eq(events, ["died:000000001"] as Array[String], "player_died announced at once")
	assert_eq(ms.state, ms.State.ARRIVING, "the warp is not interrupted")
	ms._complete(rec)
	assert_eq(ms.state, ms.State.DEAD, "DEAD after the warp (enter_dead path)")


func test_door_via_and_debug_warp_to_portal() -> void:
	ms.start_new_game()
	assert_eq(ms.debug_warp("000000020", "in01"), OK, "debug warp to a portal arrival")
	assert_eq(ms.last_transition.via, "debug", "via debug")
	assert_eq(ms.last_arrival.portal_id, "in01", "arrival portal")
	assert_eq(ms.request_portal(portal("000000020", "in01")), OK, "door")
	assert_eq(ms.current_map, "000000021", "interior")
	var expect_via := "door" if portal("000000020", "in01").portal_type == PortalDef.TYPE_DOOR else "press_up"
	assert_eq(ms.last_transition.via, expect_via, "via door (door-ness comes from the Blender marker)")
	assert_eq(ms.request_portal(portal("000000021", "out00")), OK, "door out")
	assert_eq(ms.last_arrival.to_dict(), {"map_id": "000000020", "portal_id": "in01"}, "back at the door")


func test_death_and_respawn_go_to_the_return_map() -> void:
	ms.start_new_game()
	ms.debug_warp("000000040")
	events.clear()
	assert_eq(ms.enter_dead(), OK, "dies")
	assert_eq(ms.state, ms.State.DEAD, "DEAD")
	assert_false(ms.can_save(), "no saving while dead")
	assert_ne(ms.debug_warp("000000041"), OK, "no warps while dead")
	assert_eq(ms.respawn(), OK, "respawn")
	assert_eq(ms.current_map, "000000060", "40 respawns in Southperry")
	assert_eq(ms.last_transition.via, "respawn", "via respawn")
	assert_eq(ms.last_arrival.to_dict(), {"map_id": "000000060", "spawn_index": 0}, "player_spawns[0]")
	assert_eq(events, ["died:000000040", "left:000000040", "entered:000000060<000000040", "respawned:000000060"] as Array[String], "events")
	for pair in [["000001014", "000001010"], ["000000021", "000000021"], ["000001011", "000001010"], ["000000061", "000000060"]]:
		ms.debug_warp(pair[0])
		ms.enter_dead()
		ms.respawn()
		assert_eq(ms.current_map, pair[1], "%s respawns in" % pair[0])


func test_death_announced_by_another_system() -> void:
	ms.start_new_game()
	ms._on_player_died("000000001")
	assert_eq(ms.state, ms.State.DEAD, "DEAD without re-emitting")
	assert_eq(ms.respawn(), OK, "respawn")
	assert_eq(ms.current_map, "000000001", "town respawns in itself")


func test_transition_log_is_a_ring_of_64() -> void:
	ms.start_new_game()
	for i in 70:
		ms.debug_warp("000000040" if i % 2 == 0 else "000000041")
	assert_eq(ms.transition_log.size(), 64, "ring buffer size")
	assert_eq(ms.transition_log[63], ms.last_transition, "newest last")


func test_instances_are_cached_and_restored() -> void:
	ms.start_new_game()
	ms.debug_warp("000000040")
	var st: MapInstanceState = ms.instance_state
	assert_eq(st.alive_count(), 30, "40 fills to its solo capacity")
	var killed: int = st.alive_indices()[0]
	st.kill(killed, t)
	t = 1.0
	ms.debug_warp("000000041")
	assert_true(ms.cache.has("000000040"), "40 parked")
	assert_eq(ms.instance_state.capacity, 33, "41 capacity")
	t = 2.0
	ms.debug_warp("000000040")
	assert_false(ms.instance_state.is_alive(killed), "the kill survived the round trip (no tick passed)")
	assert_eq(ms.instance_state.alive_count(), 29, "29 alive")
	t = 20.0
	ms.debug_warp("000000041")
	ms.debug_warp("000000040")
	assert_eq(ms.instance_state.alive_count(), 30, "refilled after the 15.12 s tick")
	for m in ["000000041", "000000042", "000000050", "000001000", "000001001"]:
		ms.debug_warp(m)
	assert_false(ms.cache.has("000000040"), "evicted after 4 newer maps")


func test_load_fallback_chain_without_a_world() -> void:
	ms.start_new_game()
	assert_eq(ms.enter_from_location({"map_id": "000001000", "entry": {"map_id": "000001000", "portal_id": "west00"},
		"resume": {"local_pos": [1, 2, 3], "facing_deg": 0}}), OK, "entry")
	assert_eq(ms.last_transition.load_step, "entry", "no world: resume cannot be validated, entry used")
	assert_eq(ms.last_arrival.to_dict(), {"map_id": "000001000", "portal_id": "west00"}, "entry arrival")
	assert_eq(ms.enter_from_location({"map_id": "000000041"}), OK, "map only")
	assert_eq(ms.last_transition.load_step, "player_spawn", "player_spawns[0]")
	assert_eq(ms.enter_from_location({"map_id": "000000041", "entry": {"map_id": "000000042", "portal_id": "west00"}}), OK, "foreign entry")
	assert_eq(ms.last_transition.load_step, "player_spawn", "an entry in another map is ignored")
	assert_eq(ms.enter_from_location({"map_id": "123456789"}), OK, "unknown map")
	assert_eq(ms.current_map, "000000001", "fallback map")
	assert_eq(ms.last_transition.load_step, "fallback_map", "fallback step")
	assert_eq(ms.load_character(ms.character), OK, "load the character's own location")


func test_resume_is_used_when_valid() -> void:
	var d: MapDefinitions = ms.defs
	var loc := {"map_id": "000000042", "entry": {"map_id": "000000042", "portal_id": "west00"},
		"resume": {"local_pos": [4.0, 0.5, -2.0], "facing_deg": 90.0}}
	var ok := ArrivalResolver.resolve_load(loc, d, func(_m: String, _p: Vector3) -> bool: return true, "000000001")
	assert_eq(String(ok.step), "resume", "valid resume wins")
	assert_true((ok.xform as Transform3D).origin.is_equal_approx(d.get_def("000000042").to_world(Vector3(4.0, 0.5, -2.0))), "frame * local_pos")
	assert_eq((ok.arrival as ArrivalRef).portal_id, "west00", "entry is still the recorded arrival")
	var bad := ArrivalResolver.resolve_load(loc, d, func(_m: String, _p: Vector3) -> bool: return false, "000000001")
	assert_eq(String(bad.step), "entry", "invalid resume falls back to the entry")


func test_save_world_block() -> void:
	ms.start_new_game()
	ms.debug_warp("000001003")
	var w: Dictionary = ms.save_world()
	assert_eq(w.respawn_reference, "000001010", "Rainbow Street respawns in Amherst")
	assert_eq(w.location.map_id, "000001003", "map")
	assert_eq(w.location.entry, {"map_id": "000001003", "spawn_index": 0}, "entry")
	assert_false(w.location.has("resume"), "no world, no SafeGround, no resume")


## Game.character_replaced during play (load / reset / new game): the session enters the new character's location
## instead of keeping the old map and overwriting the loaded location (docs/runtime/SAVES.md integration notes).
func test_character_replaced_during_play_loads_the_new_location() -> void:
	ms.start_new_game()
	ms.debug_warp("000000040")
	var loaded := CharacterState.new()
	loaded.location = {"map_id": "000001010", "entry": {"map_id": "000001010", "portal_id": "west00"}}
	loaded.respawn_reference = "000001010"
	ms.character = loaded
	events.clear()
	ms._on_character_replaced("load")
	assert_eq(ms.current_map, "000001010", "entered the loaded map")
	assert_eq(ms.last_transition.via, "load", "via load")
	assert_eq(ms.last_arrival.to_dict(), {"map_id": "000001010", "portal_id": "west00"}, "at the saved entry")
	assert_eq(loaded.location.map_id, "000001010", "the loaded location is not overwritten with the old map")
	assert_eq(events, ["left:000000040", "entered:000001010<000000040"] as Array[String], "a load emits no portal_used")


func test_character_replaced_before_the_world_starts_is_left_to_the_main_scene() -> void:
	var c := CharacterState.new()
	c.location = {"map_id": "000000040"}
	ms.character = c
	ms._on_character_replaced("new_game")
	assert_eq(ms.state, ms.State.BOOT, "still BOOT")
	assert_eq(ms.current_map, "", "no map entered")


func test_character_replaced_mid_transition_loads_after_it() -> void:
	ms.start_new_game()
	var c := CharacterState.new()
	c.location = {"map_id": "000001020", "entry": {"map_id": "000001020", "spawn_index": 0}}
	ms.character = c
	# A warp is in flight (as with a world attached): the load must wait, and keep the location it was given.
	ms.state = ms.State.WARP_OUT
	ms._on_character_replaced("load")
	assert_eq(ms.current_map, "000000001", "nothing changes mid-flight")
	c.location = {"map_id": "000000001"}  # what the in-flight swap's capture_location() would write
	var rec := TransitionRecord.new()
	rec.via = "debug"
	rec.to_map = "000000001"
	ms._complete(rec)
	assert_eq(ms.current_map, "000001020", "the queued load ran when IDLE was reached")
	assert_eq(ms.last_transition.via, "load", "via load")


func test_load_from_dead_revives() -> void:
	ms.start_new_game()
	ms.debug_warp("000000040")
	ms.enter_dead()
	events.clear()
	assert_eq(ms.enter_from_location({"map_id": "000001010"}), OK, "load while dead (death screen)")
	assert_eq(ms.state, ms.State.IDLE, "alive again")
	assert_true(events.has("respawned:000001010"), "player_respawned tells the controller and HUD: %s" % str(events))


func test_link_mode_hooks() -> void:
	assert_eq(ms.get_defs().graph.set_link_mode("all", "warp"), OK, "warp")
	assert_eq(ms._cmd_link_mode(["all", "edge"]), "ok", "edge works since M2")
	assert_eq(ms.get_defs().graph.mode_counts(), {"edge": 24}, "every (pure: trail) link edge")
	var door := "T_000001010_in00__000001011_out00"
	ms.get_defs().graph.links[door]["kind"] = PortalGraph.KIND_DOOR
	assert_true(String(ms._cmd_link_mode([door, "edge"])).contains("always warp"), "a door link refuses edge")
	ms.start_new_game()
	var info: Dictionary = ms.debug_info()
	assert_eq(info.current_map, "000000001", "overlay map")
	assert_eq(info.state, "IDLE", "overlay state")
	assert_eq(info.link_mode, JSON.stringify(ms.get_defs().graph.mode_counts()), "overlay link modes (nothing forced)")
	assert_eq(info.trail, "", "not on a trail")


## The console calls handlers exactly like Debug.run(): handler.call(parts.slice(1)), a PackedStringArray.
func test_console_commands_accept_the_debug_argument_type() -> void:
	ms.start_new_game()
	var argv := "map_warp 000000040 east00".split(" ", false).slice(1)
	assert_eq(str(Callable(ms, "_cmd_warp").call(argv)), "ok", "map_warp through the console call path")
	assert_eq(ms.current_map, "000000040", "warped by the console")
	assert_eq(ms.last_arrival.portal_id, "east00", "console warp to a portal")
	var info := str(Callable(ms, "_cmd_info").call(PackedStringArray()))
	assert_true(info.contains("000000040"), "map_info output: %s" % info.left(80))
	assert_eq(str(Callable(ms, "_cmd_link_mode").call(PackedStringArray(["all", "warp"]))), "ok", "map_link_mode")
	assert_eq(str(Callable(ms, "_cmd_reload").call(PackedStringArray())), "ok", "map_reload")
	var dbg: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Debug")
	if dbg != null and dbg.has_method("run"):
		assert_false(str(dbg.call("run", "map_link_mode all warp")).begins_with("unknown command"), "registered with Debug")


# --- reset (quit to title) ------------------------------------------------------------------------------------

func test_reset_returns_to_boot_with_nothing_left() -> void:
	ms.start_new_game()
	ms.debug_warp("000000040")
	ms.instance_state.add_drop({"uid": "x", "kind": "mesos", "amount": 1, "expires_at": 999.0})
	ms.debug_warp("000000041")
	assert_true(ms.cache.has("000000040"), "40 parked before the reset")
	var resets := [0]
	var on_reset := func() -> void: resets[0] += 1
	ms.session_reset.connect(on_reset)
	ms.reset()
	assert_eq(resets[0], 1, "session_reset emitted")
	assert_eq(ms.state, ms.State.BOOT, "BOOT")
	assert_eq(ms.current_map, "", "no current map")
	assert_eq(ms.respawn_reference, "", "no respawn reference")
	assert_true(ms.last_arrival == null and ms.last_transition == null, "no last arrival or transition")
	assert_eq(ms.transition_log.size(), 0, "empty transition log")
	assert_eq(ms.cache.size(), 0, "empty instance cache")
	assert_true(ms.instance_state == null, "no live instance")
	assert_false(ms.can_save(), "nothing to save in BOOT")
	assert_eq(ms.capture_location(), {}, "no location")
	assert_true(ms.defs != null and ms.character != null, "collaborators kept")
	# A new session enters exactly like the first one: no map_left of the old map, a fresh 40.
	events.clear()
	assert_eq(ms.start_new_game(), OK, "new game from BOOT")
	assert_eq(events, ["entered:000000001<"] as Array[String], "first entry again: no map_left of the previous session")
	ms.debug_warp("000000040")
	assert_true(ms.instance_state.drops.is_empty(), "the previous session's drops are gone")
	assert_eq(ms.instance_state.alive_count(), ms.instance_state.capacity, "fresh instance")


## The world leaving the tree (the shell's quit to title) resets the session, and a Continue afterwards goes through
## BOOT like GameSession.start's first entry: Game.load_game -> character_replaced (ignored in BOOT) ->
## load_character().
func test_detach_world_resets_and_continue_still_loads() -> void:
	ms.start_new_game()
	ms.debug_warp("000001010")
	var saved: Dictionary = ms.save_world()
	var stub := Node.new()
	ms.world = stub
	ms.detach_world(stub)
	assert_eq(ms.state, ms.State.BOOT, "detach_world resets to BOOT")
	assert_true(ms.world == null, "world forgotten")
	var c := CharacterState.new()
	c.location = (saved.location as Dictionary).duplicate(true)
	c.respawn_reference = String(saved.respawn_reference)
	ms.character = c
	ms._on_character_replaced("load")
	assert_eq(ms.state, ms.State.BOOT, "character_replaced in BOOT is left to the shell")
	events.clear()
	assert_eq(ms.load_character(c), OK, "Continue: load_character from BOOT")
	assert_eq(ms.current_map, "000001010", "back in the saved map")
	assert_eq(ms.last_transition.load_step, "entry", "through the saved entry (no world: no resume)")
	assert_eq(events, ["entered:000001010<"] as Array[String], "a first entry: no map_left")
	stub.free()


## A warp the world was carrying when it left: a committed swap completes, then the reset still happens.
func test_detach_world_mid_warp_settles_then_resets() -> void:
	ms.start_new_game()
	var stub := Node.new()
	ms.world = stub
	ms.state = ms.State.WARP_IN
	var rec := TransitionRecord.new()
	rec.via = "debug"
	rec.to_map = "000000001"
	ms._pending = rec
	var finished := [0]
	var on_finished := func(_r: TransitionRecord) -> void: finished[0] += 1
	ms.transition_finished.connect(on_finished)
	ms.detach_world(stub)
	assert_eq(finished[0], 1, "the committed swap completed")
	assert_eq(ms.state, ms.State.BOOT, "then reset")
	assert_true(ms._pending == null, "nothing pending")
	stub.free()


# --- the death commit (classic: the loss at the moment of death) ---------------------------------------------

## death_commit runs once, at the death; the character's location is the respawn point at once; saving while
## DEAD is legal and stores that point; respawn() does not apply death_rules again.
func test_death_commit_applies_at_death_and_makes_saving_legal() -> void:
	var commits: Array = []
	var respawn_rules := [0]
	ms.death_commit = func(c: CharacterState) -> Dictionary:
		commits.append(c)
		c.exp = maxi(c.exp - 10, 0)
		return {"exp_lost": 10}
	ms.death_rules = func(_c: CharacterState) -> void: respawn_rules[0] += 1
	ms.character.exp = 50
	ms.start_new_game()
	ms.debug_warp("000000040")
	var order: Array[String] = []
	var on_commit := func(m: String, report: Variant) -> void:
		order.append("committed:%s:%s" % [m, str((report as Dictionary).get("exp_lost", -1))])
	ms.death_committed.connect(on_commit)
	var ev: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Events")
	var on_died := func(m: String) -> void: order.append("died:" + m)
	_link(ev, "player_died", on_died)
	assert_eq(ms.enter_dead(), OK, "dies")
	assert_eq(order, ["committed:000000040:10", "died:000000040"] as Array[String], "the commit precedes the announcement")
	assert_eq(commits.size(), 1, "death_commit ran once")
	assert_eq(ms.character.exp, 40, "the loss is applied at the moment of death")
	assert_true(ms.is_death_committed(), "committed")
	var town := {"map_id": "000000060", "entry": {"map_id": "000000060", "spawn_index": ms.get_defs().tuning.respawn_spawn_index()}}
	assert_eq(ms.respawn_location(), town, "respawn_location: the canonical returnMap's respawn spawn")
	assert_eq(ms.character.location, town, "the character's location is the respawn point already")
	assert_eq(ms.character.respawn_reference, "000000060", "and its respawn reference is the town's")
	assert_true(ms.can_save(), "saving while DEAD is legal once committed")
	var w: Dictionary = ms.save_world()
	assert_eq(w.location, town, "a save while dead stores the town, no resume point")
	assert_eq(w.respawn_reference, "000000060", "save block respawn reference")
	assert_eq(ms.last_death_commit.get("map_id", ""), "000000040", "last_death_commit")
	assert_eq(ms.commit_death(), ERR_ALREADY_EXISTS, "one commit per death")
	ms._on_player_died("000000040")
	assert_eq(commits.size(), 1, "a repeated announcement does not commit again")
	assert_eq(ms.respawn(), OK, "respawn")
	assert_eq(respawn_rules[0], 0, "death_rules skipped: the death was committed")
	assert_eq(ms.current_map, "000000060", "respawned in town")
	assert_false(ms.is_death_committed(), "the commit ends with DEAD")
	assert_eq(ms.character.exp, 40, "no second loss")
	assert_eq(ms.character.location.map_id, "000000060", "location follows the live map again")
	# The next death commits again.
	ms.debug_warp("000001014")
	ms._on_player_died("000001014")
	assert_eq(commits.size(), 2, "a new death, a new commit (Events.player_died path)")
	assert_eq(ms.character.location.map_id, "000001010", "1014 respawns in Amherst")


## A death announced mid-warp commits when DEAD is entered, in the map the warp ended in.
func test_death_commit_mid_warp_happens_when_dead_is_entered() -> void:
	var commits := [0]
	ms.death_commit = func(_c: CharacterState) -> Variant:
		commits[0] += 1
		return null
	ms.start_new_game()
	ms.state = ms.State.WARP_IN
	ms._on_player_died("000000001")
	assert_eq(commits[0], 0, "not committed while the warp is in flight")
	assert_false(ms.can_save(), "no saving mid-warp")
	var rec := TransitionRecord.new()
	rec.via = "debug"
	rec.to_map = "000000001"
	ms._complete(rec)
	assert_eq(ms.state, ms.State.DEAD, "DEAD after the warp")
	assert_eq(commits[0], 1, "committed as DEAD was entered")
	assert_true(ms.can_save(), "saving legal")


## Without death_commit nothing changes: the loss waits for respawn() (death_rules) and saving while dead is refused.
func test_without_death_commit_the_respawn_applies_the_rules() -> void:
	var rules := [0]
	ms.death_rules = func(_c: CharacterState) -> void: rules[0] += 1
	ms.start_new_game()
	ms.debug_warp("000000040")
	ms.enter_dead()
	assert_false(ms.is_death_committed(), "nothing committed")
	assert_false(ms.can_save(), "no saving while dead")
	assert_eq(ms.commit_death(), ERR_UNCONFIGURED, "commit_death needs the hook")
	assert_eq(rules[0], 0, "no loss before the respawn")
	ms.respawn()
	assert_eq(rules[0], 1, "death_rules applied once on respawn")


## The real DeathRules as the commit hook: the canonical EXP penalty and death.json's HP at the moment of death.
func test_death_rules_as_the_commit_hook() -> void:
	var rules := DeathRules.from_db(db())
	ms.death_commit = Callable(rules, "apply")
	var c: CharacterState = ms.character
	c.level = 10
	c.exp = 200
	c.hp = 0
	ms.start_new_game()
	ms.debug_warp("000000040")
	var expected_loss := mini(Progression.death_exp_loss(c.level, c.get_base_stat("luk"), db()), 200)
	ms.enter_dead()
	assert_eq(rules.applied_count, 1, "DeathRules applied once, at the death")
	assert_true(expected_loss > 0, "a level-10 death costs EXP")
	assert_eq(200 - c.exp, expected_loss, "the canonical EXP penalty, at the moment of death")
	assert_true(c.hp >= 1, "HP set for the respawn (death.json respawn_vitals)")
	assert_eq(int((ms.last_death_commit.report as Dictionary).get("exp_lost", -1)), 200 - c.exp, "report passed through")
	ms.respawn()
	assert_eq(rules.applied_count, 1, "not again on respawn")


## A load out of a committed death (the death screen's load) ends it; reset() forgets it too.
func test_a_load_or_reset_ends_a_committed_death() -> void:
	ms.death_commit = func(_c: CharacterState) -> Variant: return null
	ms.start_new_game()
	ms.debug_warp("000000040")
	ms.enter_dead()
	assert_true(ms.is_death_committed(), "committed")
	ms.enter_from_location({"map_id": "000001010"})
	assert_eq(ms.state, ms.State.IDLE, "alive again")
	assert_false(ms.is_death_committed(), "the load ended the death")
	ms.debug_warp("000000040")
	ms.enter_dead()
	ms.reset()
	assert_false(ms.is_death_committed(), "reset forgets it")
	assert_true(ms.last_death_commit.is_empty(), "and the last commit")
