extends TestCase
## GateMonitor (MAP_ARCHITECTURE.md section 4.4, milestone M2) on a fake world and session with the export's gates
## (MapDefinitions with sidecars, no physics): only the far-end gates of edge-mode trails touching current_map are
## tested; an inward crossing commits through MapSession.transition(via "gate") with the trail's source portal and
## its arrival; the gates of current_map itself never commit (no ping-pong); a tick that jumps farther than
## gates.teleport_step_m is a teleport, not a crossing; a warp-mode link's gate never commits; hit-stun delays it.
## Needs the export (gate positions come from the portal anchors); prints one SKIP line without it.

var defs: MapDefinitions = null
var world: FakeWorld = null
var session: FakeSession = null
var player: FakePlayer = null
var mon: GateMonitor = null


class FakeSession extends Node:
	var current_map: String = ""
	var idle: bool = true
	var last_error: String = ""
	var requests: Array[TransitionRequest] = []

	func is_idle() -> bool:
		return idle

	func transition(req: TransitionRequest) -> Error:
		requests.append(req)
		current_map = req.to_map
		return OK


class FakePlayer extends Node3D:
	var on_floor: bool = true
	var in_hitstun: bool = false

	func is_on_floor() -> bool:
		return on_floor


class FakeWorld extends Node:
	var player: Node3D = null
	var defs: MapDefinitions = null
	var session: Node = null

	func session_node() -> Node:
		return session


func before_each() -> void:
	if not WorldSidecars.exists():
		return
	if defs == null:
		var side := WorldSidecars.load_dir()
		defs = MapDefinitions.build(db(), side)
		TrailLoader.attach(defs, side)
		defs.finish_trails()
	defs.apply_configured_link_modes()
	world = FakeWorld.new()
	session = FakeSession.new()
	player = FakePlayer.new()
	world.add_child(player)
	world.player = player
	world.defs = defs
	world.session = session
	mon = GateMonitor.new()
	mon.world = world
	# The runner's root is busy readying the main scene; the runner node itself accepts children.
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(world)


func after_each() -> void:
	if world != null:
		world.free()
		session.free()
		mon.free()
		world = null


func _tick() -> void:
	mon._physics_process(1.0 / 60.0)


## Walks the fake player from `from` to `to` in `steps` ticks.
func _walk(from: Vector3, to: Vector3, steps: int) -> void:
	for k in steps + 1:
		player.global_position = from.lerp(to, float(k) / float(steps))
		_tick()


func test_walking_across_the_far_gate_commits_the_link() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_walking_across_the_far_gate_commits_the_link: game/assets/world not present")
		return
	session.current_map = "000000040"
	var t := defs.trail("T_000000040_east00__000000041_west00")
	var g := t.gate_into("000000041")
	# 40 tests two gates: its east trail's far end (into 41) and the one-way trail's 30 end.
	assert_eq(defs.far_gates("000000040").size(), 2, "40's far gates")
	_walk(g.origin - g.normal * 2.0, g.origin + g.normal * 1.0, 30)
	assert_eq(session.requests.size(), 1, "one commit")
	var req := session.requests[0]
	assert_eq(req.via, "gate", "via gate")
	assert_eq(req.to_map, "000000041", "into 41")
	assert_eq(req.source_portal.key(), "000000040.east00", "the trail's source portal")
	assert_true(req.arrival.equals(defs.arrival_for(req.source_portal)), "its arrival, as a press-Up")
	assert_eq(mon.commits, 1, "counted")


func test_the_current_maps_own_gate_never_commits() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_the_current_maps_own_gate_never_commits: game/assets/world not present")
		return
	session.current_map = "000000040"
	var g := defs.trail("T_000000040_east00__000000041_west00").gate_into("000000040")
	# Coming back off the trail into 40 itself (turning back): nothing happens.
	_walk(g.origin - g.normal * 2.0, g.origin + g.normal * 1.0, 30)
	assert_eq(session.requests.size(), 0, "turning back on the trail is a no-op")


func test_a_teleport_is_not_a_crossing() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_a_teleport_is_not_a_crossing: game/assets/world not present")
		return
	session.current_map = "000000040"
	var g := defs.trail("T_000000040_east00__000000041_west00").gate_into("000000041")
	player.global_position = g.origin - g.normal * 3.0
	_tick()
	player.global_position = g.origin + g.normal * 0.5
	_tick()
	_tick()
	assert_eq(session.requests.size(), 0, "a 3.5 m jump in one tick does not cross")


func test_hit_stun_and_warp_mode() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_hit_stun_and_warp_mode: game/assets/world not present")
		return
	session.current_map = "000000040"
	var g := defs.trail("T_000000040_east00__000000041_west00").gate_into("000000041")
	player.in_hitstun = true
	_walk(g.origin - g.normal * 1.0, g.origin + g.normal * 0.5, 10)
	assert_eq(session.requests.size(), 0, "no commit in hit-stun")
	assert_eq(mon.armed_maps(), PackedStringArray(["000000041"]), "armed under knockback")
	player.in_hitstun = false
	_tick()
	assert_eq(session.requests.size(), 1, "the first tick after hit-stun commits")
	# The same walk with the link in warp mode: the plug would close it; the gate never commits.
	session.requests.clear()
	session.current_map = "000000040"
	defs.graph.set_link_mode("T_000000040_east00__000000041_west00", PortalDef.LINK_WARP)
	mon.refresh()
	_walk(g.origin - g.normal * 1.0, g.origin + g.normal * 0.5, 10)
	assert_eq(session.requests.size(), 0, "warp mode: no gate")
	defs.apply_configured_link_modes()


func test_the_one_way_ledge() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_the_one_way_ledge: game/assets/world not present")
		return
	var t := defs.trail("T_000000030_out00__000000040")
	# 30 -> 40: stepping off the ledge arms mid-fall and commits on landing.
	session.current_map = "000000030"
	var g40 := t.gate_into("000000040")
	player.on_floor = true
	_walk(g40.origin - g40.normal * 1.0 + Vector3.UP * 2.4, g40.origin - g40.normal * 0.1 + Vector3.UP * 2.4, 6)
	player.on_floor = false
	_walk(g40.origin + Vector3.UP * 2.4 - g40.normal * 0.1, g40.origin + g40.normal * 0.4 + Vector3.UP * 0.5, 8)
	assert_eq(session.requests.size(), 0, "airborne: armed, not committed")
	player.on_floor = true
	player.global_position = g40.origin + g40.normal * 0.5
	_tick()
	assert_eq(session.requests.size(), 1, "landing commits")
	assert_eq(session.requests[0].source_portal.key(), "000000030.out00", "through 30.out00")
	# 40 -> 30: even if a player reached the 30 end, there is no portal of 40 leading to 30.
	session.requests.clear()
	session.current_map = "000000040"
	var g30 := t.gate_into("000000030")
	_walk(g30.origin - g30.normal * 1.0, g30.origin + g30.normal * 0.5, 10)
	assert_eq(session.requests.size(), 0, "no commit into 30")
	assert_true(mon.errors.size() >= 1, "reported as a gate without a link")
