extends TestCase
## MapSession and walk-through gates (MAP_ARCHITECTURE.md sections 4.3, 4.4, 4.5, 4.9; milestone M2), on a fake world:
## a gate commit (via "gate") swaps the instance in one frame without a fade, never touches the player's input or
## position, anchors the new instance on the player, emits map_left -> map_entered -> portal_used with the source
## portal, and records that portal's arrival; a gate needs the link direction (40 -> 30 cannot); set_trail drives
## trail_changed (the HUD line) and every map change clears it; a save made on a trail keeps current_map's portal at
## that trail as its entry and no resume point.

var ms: Node = null
var w: FakeWorld = null
var events: Array[String] = []
var trails_seen: Array[String] = []
var _links: Array = []


## The world MapSession talks to, recording what MapSession asks of it.
class FakeWorld extends Node:
	var player: Node3D = null
	var region_index: RegionIndex = null
	var fader: Node = null
	var input_calls: Array[bool] = []
	var placed: Array[Transform3D] = []
	var activated_at: Array[Vector3] = []
	var safe: Dictionary = {"ok": false, "position": Vector3.ZERO, "facing": Vector3.BACK}

	func release_instance() -> void:
		pass

	func activate_map(_def: MapDefinition, _state: MapInstanceState, _arrival: ArrivalRef, xform: Transform3D) -> void:
		activated_at.append(xform.origin)

	func place_player(xform: Transform3D) -> void:
		placed.append(xform)
		player.global_transform = xform

	func apply_environment(_def: MapDefinition, _blend: float) -> void:
		pass

	func set_player_input(on: bool) -> void:
		input_calls.append(on)

	func freeze_player(_on: bool) -> void:
		pass

	func has_player() -> bool:
		return player != null

	func player_on_floor() -> bool:
		return true

	func safe_point() -> Dictionary:
		return safe

	func debug_info() -> Dictionary:
		return {}


func before_each() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	ms = load("res://scripts/autoload/map_session.gd").new()
	ms.defs = MapDefinitions.build(db())
	ms.autosave_enabled = false
	var r := RandomNumberGenerator.new()
	r.seed = 7
	ms.rng = r
	ms.clock_provider = func() -> float: return 100.0
	w = FakeWorld.new()
	w.player = Node3D.new()
	w.add_child(w.player)
	tree.current_scene.add_child(w)  # the runner's root is busy readying the main scene
	ms.world = w
	events.clear()
	trails_seen.clear()
	var ev: Node = tree.root.get_node("Events")
	_link(ev, "map_left", func(m: String) -> void: events.append("left:" + m))
	_link(ev, "map_entered", func(m: String, old: String) -> void: events.append("entered:%s<%s" % [m, old]))
	_link(ev, "portal_used", func(m: String, p: String, to: String) -> void: events.append("portal:%s.%s>%s" % [m, p, to]))
	ms.trail_changed.connect(func(dest: String) -> void: trails_seen.append(dest))


func after_each() -> void:
	for l in _links:
		if (l[0] as Node).is_connected(l[1], l[2]):
			(l[0] as Node).disconnect(l[1], l[2])
	_links.clear()
	ms.world = null
	ms.free()
	w.free()


func _link(ev: Node, sig: String, c: Callable) -> void:
	ev.connect(sig, c)
	_links.append([ev, sig, c])


func _enter(map_id: String) -> void:
	ms.world = null  # enter synchronously, then attach the fake world for the gate
	ms.debug_warp(map_id)
	ms.world = w
	events.clear()
	w.input_calls.clear()
	w.placed.clear()
	w.activated_at.clear()


func gate_request(src: PortalDef) -> TransitionRequest:
	return TransitionRequest.make(src.destination_map_id, ms.defs.arrival_for(src), "gate", src)


func test_a_gate_commit_is_one_frame_and_leaves_the_player_alone() -> void:
	_enter("000000040")
	var src: PortalDef = ms.defs.portal("000000040", "east00")
	w.player.global_position = Vector3(57.4, 8.6, 282.9)
	assert_eq(ms.transition(gate_request(src)), OK, "gate accepted")
	assert_eq(ms.state_name(), "IDLE", "no fade: IDLE at once")
	assert_eq(ms.current_map, "000000041", "committed")
	assert_eq(events, ["left:000000040", "entered:000000041<000000040", "portal:000000040.east00>000000041"] as Array[String], "event order")
	assert_eq(ms.last_transition.via, "gate", "via gate")
	assert_eq(ms.last_transition.portal_id, "east00", "the source portal")
	assert_true(ms.last_arrival.equals(ms.defs.arrival_for(src)), "last_arrival is the portal's arrival, as a press-Up records")
	assert_true(w.placed.is_empty(), "the player is not placed")
	assert_eq(w.input_calls, [] as Array[bool], "input untouched (a window that turned it off keeps it off)")
	assert_eq(w.activated_at, [Vector3(57.4, 8.6, 282.9)] as Array[Vector3], "monsters realize around the player")


func test_a_press_up_still_takes_and_gives_back_input() -> void:
	_enter("000000040")
	assert_eq(ms.request_portal(ms.defs.portal("000000040", "east00")), OK, "press Up")
	ms._physics_process(1.0 / 60.0)  # ARRIVING: the fake player stands on the floor at once
	assert_eq(ms.state_name(), "IDLE", "arrived")
	assert_eq(w.input_calls, [false, true] as Array[bool], "off for the warp, on at the end")
	assert_eq(w.placed.size(), 1, "placed at the arrival")


func test_a_gate_needs_the_link_direction() -> void:
	_enter("000000040")
	# The 000000030 end of the one-way trail: no 40 portal leads to 30, so the commit is refused.
	var p40: PortalDef = ms.defs.portal("000000040", "east00")
	var req := TransitionRequest.make("000000030", ArrivalRef.at_portal("000000030", "out00"), "gate", p40)
	assert_ne(ms.transition(req), OK, "40 -> 30 refused")
	assert_eq(ms.current_map, "000000040", "still 40")
	# Through the arrival gate the one-way link commits like 30.out00's press-Up.
	_enter("000000030")
	var out00: PortalDef = ms.defs.portal("000000030", "out00")
	assert_eq(ms.transition(gate_request(out00)), OK, "30 -> 40 by the ledge")
	assert_true(ms.last_arrival.equals(ArrivalRef.at_spawn("000000040", 0)), "the arrival gate records player_spawns[0]")


func test_trail_changed_drives_the_hud_line() -> void:
	_enter("000000040")
	ms.set_trail("T_000000040_east00__000000041_west00", "000000041")
	ms.set_trail("T_000000040_east00__000000041_west00", "000000041")
	assert_eq(trails_seen, ["000000041"] as Array[String], "one signal per change")
	assert_eq(ms.trail_destination, "000000041", "destination")
	assert_eq(ms.trail_link_id, "T_000000040_east00__000000041_west00", "trail id")
	ms.transition(gate_request(ms.defs.portal("000000040", "east00")))
	assert_eq(trails_seen, ["000000041", ""] as Array[String], "a map change clears the trail line")
	assert_eq(ms.trail_destination, "", "cleared")
	ms.set_trail("T_000000040_east00__000000041_west00", "000000040")
	ms.reset()
	assert_eq(trails_seen.back(), "", "reset clears it too")


func test_a_save_on_a_trail_keeps_the_trail_portal() -> void:
	_enter("000000040")
	var t := TrailDef.new()
	t.link_id = "T_000000040_east00__000000041_west00"
	t.maps = PackedStringArray(["000000040", "000000041"])
	t.set_ribbon(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 10)]), PackedVector3Array([Vector3(1, 0, 0), Vector3(1, 0, 10)]),
		PackedVector3Array([Vector3(-1, 0, 0), Vector3(-1, 0, 10)]), PackedFloat32Array([1.0, 1.0]))
	var maps: Array[Dictionary] = []
	var trails: Array[TrailDef] = [t]
	w.region_index = RegionIndex.make(maps, trails)
	w.safe = {"ok": true, "position": Vector3(0, 0, 5), "facing": Vector3.BACK}
	var loc: Dictionary = ms.capture_location()
	assert_eq(loc.get("entry", {}), {"map_id": "000000040", "portal_id": "east00"}, "entry: current map's portal at the trail")
	assert_false(loc.has("resume"), "no resume point on a trail")
	# The same trail while 41 is current gives 41's end.
	ms.transition(gate_request(ms.defs.portal("000000040", "east00")))
	var loc2: Dictionary = ms.capture_location()
	assert_eq(loc2.get("entry", {}), {"map_id": "000000041", "portal_id": "west00"}, "the trail belongs to the map you came from")
