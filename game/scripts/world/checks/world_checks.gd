extends Node3D
## L2-lite world checks with real physics frames (MAP_ARCHITECTURE.md section 4.13), run as a separate headless
## process by tests/unit/test_world_transitions.gd:
##
##   bash scripts/godot.sh --headless --fixed-fps 60 --quit-after 60000 --path game res://scenes/world/checks/world_checks.tscn [-- --only <section>] [--player real]
##
## It builds the island (collision only), adds a player driven by a BotInput, and checks, through the real
## MapSession autoload and PortalInteractor. The player is the world's WorldTestPlayer capsule, or with
## `--player real` the game's PlayerController (res://scenes/actors/player.tscn) exactly as authored, which also
## exercises the layer contract IslandWorld.set_player() applies, the controller's teleport/settle and its SafeGround:
##   press_up  every MeowDB portal: Up pressed inside the trigger lands at the destination arrival within 0.1 m,
##             grounded within transition.arrive_grounded_frames, with the exact event order, and holding Up for 2 s
##             afterwards never re-triggers
##   doors     each interior in and out
##   death     death in 000000040, 000001014, 000000021 and 000001011 respawns at the returnMap's player_spawns[0]
##   load      the load fallback chain: resume, entry, player_spawns[0], unknown map
##   save      the save location round trip (section 4.13 L2): at player_spawns[0] of every map, capture_location() then
##             a load lands on the saved resume point; with a walking player, a save made mid-jump stores SafeGround
##   monsters  a map populates to its solo capacity, a kill respawns on the tick
##   misc      fall recovery below kill_y, NPC interaction only in the current map, can_save, the location model
##   gating    the portal keys and the input hand-back under a real GameContext (IslandWorld.set_context): Up under a
##             modal or with input off (or dead, with the real player) never warps, a warp completing under a modal
##             leaves input off and the last pop_modal gives it back
##   commit    MapSession.death_commit: the commit at the death, saving while DEAD stores the returnMap respawn
##             point, the respawn and a load of that save land on it
##   containment  (walking players only) from every portal's arrival, walk out through the portal for
##             CONTAINMENT_WALK_FRAMES, twice: with every link in warp mode the plugs close each ring and stop the
##             player inside its map; with the configured link modes (M2: trails walk) a door still stops it, and an
##             edge portal lets it out onto its trail, where the side walls keep it (inside the map's region set, no
##             fall recovery) unless it reaches the far gate and commits to the trail's other map; then the rings of
##             region extensions (Southperry's ship): pushed at every stretch of them with jumps, the player stays
##             on the floor, walks back, never falls out or leaves the region (_check_extension_rings)
## Output: "WORLD_CHECK FAIL <section>: <detail>" per failure, "WORLD_SECTION <name> <checks> <failed>" per section,
## and a final "WORLD_CHECKS_DONE <checks> <failed>". Exit code 0 when everything passed.

const PLAYER_SCENE := "res://scenes/actors/player.tscn"
## Walking time per portal in the containment section (4 s at 60 Hz: ~12 m at MeowDB's walk speed, well past every
## ring, which stands at most ~2.5 m outward of an arrival).
const CONTAINMENT_WALK_FRAMES := 240
## Region-extension rings (containment section): spacing of the pushes along each extension ring edge, and how long
## each push walks and jumps at the wall (2.5 s: 1.2 to 3 m to the rail, then jumps against it).
const EXTENSION_SAMPLE_M := 1.0
const EXTENSION_PUSH_FRAMES := 150
## Known source-world slots inside region extensions: map id -> [[map-local x, map-local y, radius m, reason]]. A push
## that ends in the air within the radius is printed as WORLD_KNOWN instead of failing; walking back, falling out and
## the region stay strict. Each entry goes when the Blender export fixes it (WORLD_RUNTIME.md "Source world status").
const KNOWN_EXTENSION_SLOTS := {
	"000000060": [[81.6, -6.7, 1.2, "the ship's main deck stops short of the port hull below the forecastle (x 81.2 to " +
		"82.6, the hull's inner face 2 to 2.6 m lower): a body pushed there drops about 0.45 m into the slot, wedged " +
		"between deck edge and hull, and walks back out"]],
}

var world: IslandWorld = null
var session: Node = null
## WorldTestPlayer (default) or PlayerController (--player real); both on the duck-typed player contract.
var player: CharacterBody3D = null
var real_player: bool = false
var bot: BotInput = null
var total: int = 0
var failed: int = 0
var events: Array[String] = []
var fake_t: float = 1000.0
var _section: String = ""
var _section_total: int = 0
var _section_failed: int = 0


func _ready() -> void:
	var only := ""
	var args := OS.get_cmdline_user_args()
	var i := args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1]
	var j := args.find("--player")
	real_player = j >= 0 and j + 1 < args.size() and args[j + 1] == "real"
	await _setup()
	if world.is_built and player != null:
		for section in ["press_up", "doors", "death", "load", "save", "monsters", "misc", "gating", "commit", "containment"]:
			if section == "containment" and not real_player:
				continue  # the test capsule does not walk
			if only == "" or only == section:
				_begin(section)
				match section:
					"press_up":
						await _check_press_up()
					"doors":
						await _check_doors()
					"death":
						await _check_death()
					"load":
						await _check_load()
					"save":
						await _check_save()
					"monsters":
						await _check_monsters()
					"misc":
						await _check_misc()
					"gating":
						await _check_gating()
					"commit":
						await _check_commit()
					"containment":
						await _check_containment()
				_end()
	print("WORLD_CHECKS_DONE %d %d" % [total, failed])
	get_tree().quit(0 if failed == 0 else 1)


func _setup() -> void:
	session = get_node("/root/MapSession")
	session.autosave_enabled = false
	session.clock_provider = func() -> float: return fake_t
	world = IslandWorld.new()
	world.name = "World"
	world.build_on_ready = false
	world.load_visuals = false
	add_child(world)
	var t0 := Time.get_ticks_msec()
	world.build_now()
	world.instance_view.clock = func() -> float: return fake_t
	print("WORLD_BUILD %d ms %s errors=%d warnings=%d" % [Time.get_ticks_msec() - t0, str(world.stats), world.build_errors.size(),
		world.build_warnings.size()])
	_begin("build")
	_ok(world.is_built and world.build_errors.is_empty(), "build errors: %s" % "; ".join(world.build_errors))
	# The source world is clean (blender_export.md round 2): no arrival, spawn or NPC is settled, no slot forced.
	_ok(world.build_warnings.is_empty(), "build warnings: %s" % "; ".join(world.build_warnings))
	_end()
	var tuning := world.tuning
	bot = BotInput.new()
	if real_player:
		var scene: PackedScene = load(PLAYER_SCENE) if ResourceLoader.exists(PLAYER_SCENE) else null
		var pc: Node = scene.instantiate() if scene != null else null
		if not (pc is CharacterBody3D and pc.has_method("set_input_source") and pc.has_method("teleport")):
			_begin("build")
			_ok(false, "%s is not a player controller (set_input_source, teleport)" % PLAYER_SCENE)
			_end()
			if pc != null:
				pc.free()
			return
		player = pc
		add_child(player)
		player.call("set_input_source", bot)
		print("WORLD_PLAYER real %s (authored layer %d mask %d)" % [PLAYER_SCENE, player.collision_layer, player.collision_mask])
	else:
		var capsule := WorldTestPlayer.new()
		capsule.configure(tuning.num("grounding", "capsule_radius_m"), tuning.num("grounding", "capsule_height_m"))
		add_child(capsule)
		capsule.input_source = bot
		player = capsule
	world.set_player(player)
	_begin("build")
	_ok(player.collision_layer == WorldLayers.PLAYER, "player layer %d after set_player, expected %d" % [player.collision_layer, WorldLayers.PLAYER])
	_ok((player.collision_mask & WorldLayers.PLAYER_MASK) == WorldLayers.PLAYER_MASK, "player mask %d lacks %d" % [player.collision_mask, WorldLayers.PLAYER_MASK])
	# MapSession's ARRIVING check must run after the player's physics step, or it reads a pre-warp floor state.
	_ok(session.process_physics_priority > player.process_physics_priority, "MapSession physics priority %d is not after the player's %d" % [
		session.process_physics_priority, player.process_physics_priority])
	_end()
	var ev := get_node("/root/Events")
	ev.map_left.connect(func(m: String) -> void: events.append("left:" + m))
	ev.map_entered.connect(func(m: String, old: String) -> void: events.append("entered:%s<%s" % [m, old]))
	ev.portal_used.connect(func(m: String, p: String, to: String) -> void: events.append("portal:%s.%s>%s" % [m, p, to]))
	ev.player_died.connect(func(m: String) -> void: events.append("died:" + m))
	ev.player_respawned.connect(func(m: String) -> void: events.append("respawned:" + m))
	session.start_new_game()
	await _idle()


# --- sections ---------------------------------------------------------------------------------------------------

func _check_press_up() -> void:
	var d := world.defs
	var limit := d.tuning.count("transition", "arrive_grounded_frames")
	var hold_frames := 120
	for p in d.canonical_portals():
		var label := p.key()
		if not await _warp(p.source_map_id, p.portal_id):
			_ok(false, "%s: cannot warp to the source portal" % label)
			continue
		# Step into the trigger (onto the grounded anchor) and let the overlap update.
		world.place_player(Transform3D(MapDefinitions.facing_basis(-p.inward), p.anchor_ground))
		await _frames(3)
		var node := world.portal_node(p.source_map_id, p.portal_id)
		_ok(world.portal_under_player() == node, "%s: player not inside an armed trigger (inside=%s armed=%s)" % [label,
			node.contains(player) if node != null else false, node.armed if node != null else false])
		_ok(node != null and node.shows_prompt() == (not p.hidden), "%s: prompt shown=%s hidden=%s" % [label,
			node.shows_prompt() if node != null else false, p.hidden])
		events.clear()
		bot.press(&"portal_enter")
		var started := false
		for _f in 4:
			await get_tree().physics_frame
			if not session.is_idle():
				started = true
				break
		_ok(started, "%s: pressing Up did not start a transition" % label)
		if not started:
			continue
		if not await _idle():
			_ok(false, "%s: transition did not finish" % label)
			continue
		var arrival := d.arrival_for(p)
		var xf: Transform3D = d.arrival_transform(arrival).xform
		var rec: TransitionRecord = session.last_transition
		_ok(session.current_map == p.destination_map_id, "%s: current_map %s, expected %s" % [label, session.current_map, p.destination_map_id])
		_ok(session.last_arrival.equals(arrival), "%s: last_arrival %s, expected %s" % [label, session.last_arrival, arrival])
		var dist := player.global_position.distance_to(xf.origin)
		_ok(dist <= 0.1, "%s: landed %.3f m from the arrival %s (at %s)" % [label, dist, xf.origin, player.global_position])
		_ok(rec.frames_to_ground >= 1 and rec.frames_to_ground <= limit and not rec.replaced, "%s: grounded after %d frames (budget %d, re-placed %s)" % [
			label, rec.frames_to_ground, limit, rec.replaced])
		_ok(player.is_on_floor(), "%s: not on the floor after arriving" % label)
		var via := "door" if p.portal_type == PortalDef.TYPE_DOOR else "press_up"
		_ok(rec.via == via and rec.portal_id == p.portal_id, "%s: record via %s portal %s" % [label, rec.via, rec.portal_id])
		var expect: Array[String] = ["left:" + p.source_map_id, "entered:%s<%s" % [p.destination_map_id, p.source_map_id],
			"portal:%s.%s>%s" % [p.source_map_id, p.portal_id, p.destination_map_id]]
		_ok(events == expect, "%s: events %s" % [label, str(events)])
		# Holding Up after arriving never re-triggers.
		bot.hold(&"portal_enter")
		await _physics_frames(hold_frames)
		bot.release(&"portal_enter")
		_ok(session.last_transition == rec and session.current_map == p.destination_map_id,
			"%s: re-triggered while Up was held" % label)


func _check_doors() -> void:
	var d := world.defs
	for p in d.canonical_portals():
		if p.portal_type != PortalDef.TYPE_DOOR or d.get_def(p.source_map_id).is_interior():
			continue
		var inside := d.get_def(p.destination_map_id)
		if not await _press(p):
			continue
		_ok(session.current_map == inside.map_id and inside.is_interior(), "%s: entered %s" % [p.key(), session.current_map])
		_ok(inside.footprint_contains(player.global_position), "%s: player inside the interior room" % p.key())
		var back := d.portal(inside.map_id, "out00")
		if back == null or not await _press(back):
			_ok(false, "%s: no way out" % inside.map_id)
			continue
		var xf: Transform3D = d.arrival_transform(ArrivalRef.at_portal(p.source_map_id, p.portal_id)).xform
		_ok(session.current_map == p.source_map_id and player.global_position.distance_to(xf.origin) <= 0.1,
			"%s: back out at %s (%.3f m off)" % [inside.map_id, session.current_map, player.global_position.distance_to(xf.origin)])


func _check_death() -> void:
	var d := world.defs
	for pair in [["000000040", "000000060"], ["000001014", "000001010"], ["000000021", "000000021"], ["000001011", "000001010"]]:
		if not await _warp(pair[0]):
			_ok(false, "cannot warp to %s" % pair[0])
			continue
		events.clear()
		_ok(session.enter_dead() == OK and session.state == session.State.DEAD, "%s: enter_dead" % pair[0])
		_ok(not session.can_save(), "%s: no saving while dead" % pair[0])
		_ok(session.respawn() == OK, "%s: respawn accepted" % pair[0])
		_ok(await _idle(), "%s: respawn finished" % pair[0])
		var xf := d.get_def(pair[1]).player_spawn(0)
		_ok(session.current_map == pair[1], "%s: respawned in %s, expected %s" % [pair[0], session.current_map, pair[1]])
		_ok(player.global_position.distance_to(xf.origin) <= 0.1, "%s: respawn point %.3f m off" % [pair[0], player.global_position.distance_to(xf.origin)])
		_ok(session.last_transition.via == "respawn", "%s: via respawn" % pair[0])
		_ok(events.has("died:" + pair[0]) and events.has("respawned:" + pair[1]), "%s: events %s" % [pair[0], str(events)])


func _check_load() -> void:
	var d := world.defs
	var def := d.get_def("000000041")
	var good := def.portal("east00").spawn_transform.origin
	var local := def.to_local(good)
	# 1. a valid resume point.
	_ok(await _load({"map_id": "000000041", "entry": {"map_id": "000000041", "portal_id": "west00"},
		"resume": {"local_pos": [local.x, local.y, local.z], "facing_deg": 90.0}}), "load resume accepted")
	_ok(session.last_transition.load_step == "resume", "resume step: %s" % session.last_transition.load_step)
	_ok(player.global_position.distance_to(good) <= 0.1, "resume landed %.3f m off" % player.global_position.distance_to(good))
	_ok(session.last_arrival.portal_id == "west00", "resume keeps the entry as last_arrival")
	# 2. an invalid resume (outside the map) falls back to the entry portal.
	_ok(await _load({"map_id": "000001000", "entry": {"map_id": "000001000", "portal_id": "west00"},
		"resume": {"local_pos": [500.0, 0.0, 500.0], "facing_deg": 0.0}}), "load entry accepted")
	var west := d.portal("000001000", "west00").spawn_transform.origin
	_ok(session.last_transition.load_step == "entry", "entry step: %s" % session.last_transition.load_step)
	_ok(player.global_position.distance_to(west) <= 0.1, "entry landed %.3f m off" % player.global_position.distance_to(west))
	# 3. a resume inside a portal trigger is rejected too.
	var trig := d.portal("000001000", "east00").anchor_ground
	var tl := d.get_def("000001000").to_local(trig)
	_ok(await _load({"map_id": "000001000", "entry": {"map_id": "000001000", "portal_id": "west00"},
		"resume": {"local_pos": [tl.x, tl.y, tl.z], "facing_deg": 0.0}}), "load in-trigger accepted")
	_ok(session.last_transition.load_step == "entry", "a resume inside a trigger falls back: %s" % session.last_transition.load_step)
	# 4. no entry: player_spawns[0].
	_ok(await _load({"map_id": "000001021"}), "load map-only accepted")
	_ok(session.last_transition.load_step == "player_spawn", "player_spawn step: %s" % session.last_transition.load_step)
	_ok(player.global_position.distance_to(d.get_def("000001021").player_spawn(0).origin) <= 0.1, "player_spawns[0] landing")
	# 5. an unknown map: the fallback map.
	_ok(await _load({"map_id": "999999999"}), "load unknown accepted")
	_ok(session.current_map == "000000001" and session.last_transition.load_step == "fallback_map", "fallback map: %s" % session.current_map)


func _check_save() -> void:
	var d := world.defs
	for id in d.ids():
		if not await _warp(id):
			_ok(false, "%s: cannot warp" % id)
			continue
		await _frames(3)
		var loc: Dictionary = session.capture_location()
		_ok(loc.get("map_id", "") == id and loc.has("resume"), "%s: saved location %s" % [id, str(loc)])
		if not loc.has("resume"):
			continue
		var lp: Array = loc.resume.local_pos
		var saved := d.get_def(id).to_world(Vector3(float(lp[0]), float(lp[1]), float(lp[2])))
		_ok(saved.distance_to(d.get_def(id).player_spawn(0).origin) <= 0.1, "%s: resume is the safe point at player_spawns[0] (%.3f m off)" % [
			id, saved.distance_to(d.get_def(id).player_spawn(0).origin)])
		# Load it back from another map, as a fresh session would.
		var other := "000000060" if id != "000000060" else "000001010"
		if not await _warp(other):
			continue
		_ok(await _load(loc), "%s: load accepted" % id)
		_ok(session.current_map == id and session.last_transition.load_step == "resume", "%s: loaded into %s by step %s" % [
			id, session.current_map, session.last_transition.load_step])
		_ok(player.global_position.distance_to(saved) <= 0.1, "%s: loaded %.3f m from the saved point" % [id, player.global_position.distance_to(saved)])
		_ok(session.last_arrival.to_dict() == (loc.entry as Dictionary), "%s: entry kept as last_arrival" % id)
	if not real_player:
		return
	# Mid-jump: the save stores the last SafeGround point, never the airborne position (section 4.9).
	if not await _warp("000000041"):
		return
	await _frames(5)
	var safe: Dictionary = world.safe_point()
	bot.press(&"jump")
	var airborne := false
	for _f in 20:
		await get_tree().physics_frame
		if not player.is_on_floor() and player.global_position.y > float((safe.position as Vector3).y) + 0.3:
			airborne = true
			break
	_ok(airborne, "the player jumped")
	if airborne:
		var loc2: Dictionary = session.capture_location()
		var lp2: Array = loc2.resume.local_pos
		var at := d.get_def("000000041").to_world(Vector3(float(lp2[0]), float(lp2[1]), float(lp2[2])))
		_ok(at.distance_to(safe.position) <= 0.05, "mid-jump save stores SafeGround (%.3f m from it, live point %.2f m up)" % [
			at.distance_to(safe.position), player.global_position.y - float((safe.position as Vector3).y)])
	await _frames(60)


func _check_monsters() -> void:
	if not await _warp("000000040"):
		_ok(false, "cannot warp to 000000040")
		return
	await _frames(12)
	var view := world.instance_view
	var cap: int = session.instance_state.capacity
	_ok(cap == 30, "000000040 capacity %d" % cap)
	_ok(view.live_count() == cap, "000000040 shows %d monsters, expected %d" % [view.live_count(), cap])
	var slot: int = session.instance_state.alive_indices()[0]
	_ok(view.notify_killed(slot), "kill accepted")
	_ok(view.live_count() == cap - 1, "one fewer after the kill")
	fake_t += 4.0
	await _frames(3)
	_ok(view.live_count() == cap - 1, "no respawn before death + cooldown")
	fake_t += 8.0
	await _frames(3)
	_ok(view.live_count() == cap, "respawned on the tick (%d live)" % view.live_count())
	if not await _warp("000000060"):
		return
	await _frames(3)
	_ok(view.live_count() == 0, "Southperry has no monsters")
	var proxies := 0
	for n in view.get_children():
		if n.is_inside_tree():
			proxies += 1
	_ok(proxies == 0, "released proxies left the scene")


func _check_misc() -> void:
	var d := world.defs
	# NPC interaction only in the current map.
	if await _warp("000001010"):
		for id in world.npc_nodes:
			var n: WorldNpc = world.npc_nodes[id]
			_ok(n.interaction_enabled == (n.map_id() == "000001010"), "NPC %s interaction %s" % [n.npc_id(), n.interaction_enabled])
		var lucas: WorldNpc = world.npc_nodes.get("17", null)
		if lucas != null:
			world.place_player(Transform3D(Basis.IDENTITY, lucas.global_position + Vector3.BACK * 0.5))
			await _frames(3)
			var near := world.nearest_interactable(player.global_position)
			_ok(String(near.get("kind", "")) == "npc" and String(near.get("id", "")) == "17", "nearest interactable near Lucas: %s" % str(near.get("id", "")))
	# Fall recovery below kill_y, back onto SafeGround.
	if await _warp("000000041"):
		await _frames(10)
		var safe: Dictionary = world.safe_point()
		_ok(bool(safe.ok), "SafeGround recorded")
		_ok(session.can_save(), "can_save in IDLE with SafeGround")
		var loc: Dictionary = session.capture_location()
		_ok(loc.has("resume"), "location has a resume point")
		if loc.has("resume"):
			var lp: Array = loc.resume.local_pos
			var back := d.get_def("000000041").to_world(Vector3(lp[0], lp[1], lp[2]))
			_ok(back.distance_to(safe.position) < 0.01, "resume local_pos maps back to the SafeGround point")
		var before := world.fall_recovery.recoveries
		player.global_position = Vector3(player.global_position.x, d.get_def("000000041").kill_y - 2.0, player.global_position.z)
		await _frames(3)
		_ok(world.fall_recovery.recoveries == before + 1, "fell below kill_y: recovered")
		_ok(player.global_position.distance_to(safe.position) < 0.5, "back on the safe point")
		await _frames(5)
		_ok(player.is_on_floor(), "standing after the recovery")
	# ARRIVING really waits for the floor (§4.5 step 14): an arrival far above the ground is not "grounded" on the
	# first frame from a stale pre-warp floor flag; after arrive_replace_frames the player is re-placed at
	# player_spawns[0] and the record says so.
	if await _warp("000000041"):
		var ps0 := d.get_def("000000041").player_spawn(0)
		var drop := Transform3D(ps0.basis, ps0.origin + Vector3.UP * 6.0)
		var req := TransitionRequest.make_xform("000000041", drop, ArrivalRef.at_spawn("000000041", 0), "debug")
		_ok(session.transition(req) == OK, "mid-air arrival accepted")
		_ok(await _idle(), "mid-air arrival finished")
		var rec: TransitionRecord = session.last_transition
		_ok(rec.replaced, "a 6 m drop was reported grounded after %d frames without re-placement" % rec.frames_to_ground)
		_ok(player.global_position.distance_to(ps0.origin) <= 0.1, "re-placed at player_spawns[0] (%.3f m off)" % player.global_position.distance_to(ps0.origin))
		_ok(player.is_on_floor(), "standing after the re-placement")
	# The hidden type-1 portal: no swirl, no prompt. Every other portal shows its library visual.
	var hidden := world.portal_node("000001020", "in00")
	_ok(hidden != null and hidden.visual_root.get_child_count() == 0 and not hidden.visual_root.visible, "type-1 portal has no visual")
	for key in world.portal_nodes:
		var wp: WorldPortal = world.portal_nodes[key]
		if not wp.def.hidden:
			_ok(wp.visual_root.visible and wp.visual_root.get_child_count() == 1, "%s shows %s" % [key, wp.def.visual])


## The portal keys and the end-of-warp input hand-back respect the game context (WORLD_RUNTIME.md "Input gating").
func _check_gating() -> void:
	var d := world.defs
	var p := d.portal("000000040", "east00")
	if p == null or not await _warp(p.source_map_id, p.portal_id):
		_ok(false, "cannot warp next to 000000040.east00")
		return
	var stand := Transform3D(MapDefinitions.facing_basis(-p.inward), p.anchor_ground)
	world.place_player(stand)
	await _frames(3)
	_ok(world.portal_under_player() != null, "standing in 000000040.east00")
	var ctx := GameContext.new()
	ctx.player = player
	world.set_context(ctx)
	var holder := Node.new()
	# A modal (a dialogue) opens: GameContext turns input off; even if something hands it back, Up never warps.
	ctx.push_modal(holder)
	_ok(not bool(player.call("is_input_enabled")), "push_modal turned the player input off")
	player.call("set_input_enabled", true)
	var rec: TransitionRecord = session.last_transition
	bot.press(&"portal_enter")
	await _frames(4)
	_ok(session.is_idle() and session.last_transition == rec, "Up under a modal warped to %s" % session.current_map)
	_ok(world.interactor.last_block == "modal", "blocked as modal: %s" % world.interactor.last_block)
	player.call("set_input_enabled", false)
	# A warp (typed into the console, say) completes under the modal: input stays off until the modal closes.
	_ok(await _warp("000000041"), "warp under the modal finished")
	_ok(not bool(player.call("is_input_enabled")), "the end of the warp did not hand input back under the modal")
	ctx.pop_modal(holder)
	_ok(bool(player.call("is_input_enabled")), "the last pop_modal gave input back")
	# Input off without a modal (a transition-style freeze): ignored.
	if await _warp(p.source_map_id, p.portal_id):
		world.place_player(stand)
		await _frames(3)
		player.call("set_input_enabled", false)
		rec = session.last_transition
		bot.press(&"portal_enter")
		await _frames(4)
		_ok(session.last_transition == rec, "Up with input off warped")
		_ok(world.interactor.last_block == "input off", "blocked as input off: %s" % world.interactor.last_block)
		player.call("set_input_enabled", true)
		if player.has_method("die") and player.has_method("revive"):
			player.call("die")
			bot.press(&"portal_enter")
			await _frames(4)
			_ok(session.last_transition == rec, "Up while dead warped")
			_ok(world.interactor.last_block == "dead", "blocked as dead: %s" % world.interactor.last_block)
			player.call("revive")
		# Everything clear: the same press works.
		bot.press(&"portal_enter")
		var started := false
		for _f in 4:
			await get_tree().physics_frame
			if not session.is_idle():
				started = true
				break
		_ok(started, "with nothing blocking, Up warps")
		await _idle()
	world.set_context(null)
	holder.free()


## MapSession.death_commit in the real world: committed at the death, a save while dead stores the respawn point.
func _check_commit() -> void:
	var d := world.defs
	var commits := [0]
	session.death_commit = func(_c: CharacterState) -> Dictionary:
		commits[0] += 1
		return {"check": true}
	if not await _warp("000000040"):
		_ok(false, "cannot warp to 000000040")
		session.death_commit = Callable()
		return
	_ok(session.enter_dead() == OK and session.is_death_committed(), "committed as DEAD is entered")
	_ok(commits[0] == 1, "death_commit ran %d times" % commits[0])
	_ok(session.can_save(), "saving is legal while dead after the commit")
	var w: Dictionary = session.save_world()
	var loc: Dictionary = w.location
	var idx := d.tuning.respawn_spawn_index()
	_ok(loc == {"map_id": "000000060", "entry": {"map_id": "000000060", "spawn_index": idx}}, "a save while dead stores %s" % str(loc))
	_ok(String(w.respawn_reference) == "000000060", "respawn reference %s" % str(w.respawn_reference))
	_ok(session.respawn() == OK, "respawn accepted")
	_ok(await _idle(), "respawn finished")
	var xf := d.get_def("000000060").player_spawn(idx)
	_ok(session.current_map == "000000060" and player.global_position.distance_to(xf.origin) <= 0.1,
		"respawned at the saved point (%s, %.3f m off)" % [session.current_map, player.global_position.distance_to(xf.origin)])
	_ok(commits[0] == 1, "no second commit on respawn")
	if await _warp("000001010"):
		_ok(await _load(loc), "the save made while dead loads")
		_ok(session.current_map == "000000060" and session.last_transition.load_step == "entry"
			and player.global_position.distance_to(xf.origin) <= 0.1, "loaded into %s by %s" % [session.current_map,
			session.last_transition.load_step])
	session.death_commit = Callable()


## Containment (MAP_ARCHITECTURE section 4.6). Warp mode closes every map: from each portal's arrival, walking out
## through the portal must end against the containment ring and its plug inside the map, never on the trail beyond
## it and never in a fall recovery. With the configured link modes (trails walk), a door still closes its map, and
## an edge portal opens onto its trail: the player stays in the map's region set (the map or its trail; the trail's
## side walls hold it) with no fall recovery, unless it walked far enough to commit the far gate (a short trail),
## which must then be the trail's other map, through a gate.
func _check_containment() -> void:
	var d := world.defs
	d.graph.set_link_mode("all", PortalDef.LINK_WARP)
	for p in d.canonical_portals():
		if not await _warp(p.source_map_id, p.portal_id):
			_ok(false, "%s: cannot warp to the arrival" % p.key())
			continue
		var def := d.get_def(p.source_map_id)
		var before := world.fall_recovery.recoveries
		bot.world_dir = -p.inward
		await _frames(CONTAINMENT_WALK_FRAMES)
		bot.world_dir = Vector3.ZERO
		await _frames(2)
		var pos := player.global_position
		_ok(def.footprint_contains(pos), "warp: %s: walked out of %s to %s (outside footprint + ring offset)" % [p.key(), def.map_id, pos])
		_ok(world.fall_recovery.recoveries == before, "warp: %s: fell out while walking against the ring" % p.key())
		_ok(session.current_map == p.source_map_id and session.is_idle(), "warp: %s: map changed to %s while walking" % [p.key(), session.current_map])
	d.apply_configured_link_modes()
	var opened := 0
	for p in d.canonical_portals():
		if not await _warp(p.source_map_id, p.portal_id):
			_ok(false, "%s: cannot warp to the arrival" % p.key())
			continue
		var def := d.get_def(p.source_map_id)
		var before := world.fall_recovery.recoveries
		var violations := world.region_monitor.violations
		bot.world_dir = -p.inward
		await _frames(CONTAINMENT_WALK_FRAMES)
		bot.world_dir = Vector3.ZERO
		await _frames(2)
		var pos := player.global_position
		_ok(world.fall_recovery.recoveries == before, "edge: %s: fell out while walking out" % p.key())
		_ok(world.region_monitor.violations == violations, "edge: %s: region invariant violated (%s)" % [p.key(), str(world.region_monitor.last_violation)])
		if not d.graph.is_edge(p.link_id):
			_ok(def.footprint_contains(pos), "edge: %s (warp link): walked out of %s to %s" % [p.key(), def.map_id, pos])
			_ok(session.current_map == p.source_map_id, "edge: %s (warp link): map changed to %s" % [p.key(), session.current_map])
			continue
		if session.current_map == p.source_map_id:
			_ok(world.region_index.allowed(pos, p.source_map_id), "edge: %s: ended at %s, outside %s and its trails" % [p.key(), pos, def.map_id])
			if not def.footprint_contains(pos):
				opened += 1
		else:
			var rec: TransitionRecord = session.last_transition
			_ok(session.current_map == p.destination_map_id and rec.via == "gate", "edge: %s: walked into %s via %s" % [p.key(), session.current_map, rec.via])
			opened += 1
	_ok(opened >= 30, "edge: only %d edge portals let the player out onto their trail" % opened)
	await _check_extension_rings()


## Region extensions (maps/<id>.json region_extensions: Southperry's ship). The ring there must hug what the extension
## brings in, so a body pushed against it stays on that walkable top: no pocket below a deck edge to hang in, no void
## in front of a bow to fall through. Along every ring edge of the extension outside the layout ring, every
## EXTENSION_SAMPLE_M: the start is the first walkable deck point (capsule clear) 1.2 to 3 m inward; from it the
## player walks at the wall for EXTENSION_PUSH_FRAMES, jumping every 25 frames (over a rail, off an edge), then walks
## back without jumping. It must stand on the floor after the push, be back within 0.75 m of the start, and neither
## fall out (fall recovery) nor leave the region (RegionMonitor).
func _check_extension_rings() -> void:
	var d := world.defs
	var space := world.get_world_3d().direct_space_state
	var gq := PhysicsGroundQuery.new(space)
	var radius := d.tuning.num("grounding", "capsule_radius_m")
	var height := d.tuning.num("grounding", "capsule_height_m")
	var pushes := 0
	for id in d.ids():
		var def := d.get_def(id)
		for ext: Dictionary in def.region_extensions:
			var ring: PackedVector2Array = ext.ring_line
			if not await _warp(id):
				_ok(false, "extension %s %s: cannot warp to %s" % [id, String(ext.name), id])
				continue
			var side := ContainmentBuilder.outward_side(ring)
			for i in ring.size():
				var a := ring[i]
				var b := ring[(i + 1) % ring.size()]
				var normal := ContainmentBuilder.edge_outward(ring, i, side)
				for seg: PackedVector2Array in Geometry2D.clip_polyline_with_polygon(PackedVector2Array([a, b]), def.footprint_base):
					var s0 := seg[0]
					var s1 := seg[seg.size() - 1]
					var length := s0.distance_to(s1)
					if length < 0.3:
						continue
					var n := maxi(1, ceili(length / EXTENSION_SAMPLE_M))
					for k in n:
						var at := s0.lerp(s1, (k + 0.5) / n)
						var start := _deck_point_inward(gq, def, at, -normal, radius, height)
						if is_nan(start.x):
							continue
						pushes += 1
						await _push_at_ring(def, String(ext.name), start, at)
	_ok(pushes >= 10, "extension rings: only %d pushes found a deck to start from" % pushes)


## The first point 1.2 to 3 m from `at` along `inward` whose top surface (a ray from the map's top down, containment
## ignored) is walkable collision with a clear capsule on it; Vector3(NAN, NAN, NAN) when there is none.
func _deck_point_inward(gq: PhysicsGroundQuery, def: MapDefinition, at: Vector2, inward: Vector2, radius: float, height: float) -> Vector3:
	var space := world.get_world_3d().direct_space_state
	var k := 1.2
	while k <= 3.0 + 0.001:
		var p := at + inward * k
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, def.y_max + 2.0, p.y), Vector3(p.x, def.y_min - 2.0, p.y),
			WorldLayers.WALKABLE | WorldLayers.BLOCKING | WorldLayers.SCENERY)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (int((hit.collider as CollisionObject3D).collision_layer) & WorldLayers.WALKABLE) \
				and (hit.normal as Vector3).y > 0.8 and gq.is_clear(hit.position + Vector3.UP * 0.05, radius, height):
			return hit.position
		k += 0.2
	return Vector3(NAN, NAN, NAN)


## The reason of the KNOWN_EXTENSION_SLOTS entry of `def`'s map around world point `p`, or "".
func _known_extension_slot(def: MapDefinition, p: Vector3) -> String:
	var local := def.to_local(p)
	for e: Array in KNOWN_EXTENSION_SLOTS.get(def.map_id, []):
		if Vector2(local.x, -local.z).distance_to(Vector2(float(e[0]), float(e[1]))) <= float(e[2]):
			return String(e[3])
	return ""


func _push_at_ring(def: MapDefinition, ext_name: String, start: Vector3, at: Vector2) -> void:
	var label := "extension %s %s: from %s toward the ring at (%.2f, %.2f)" % [def.map_id, ext_name, start, at.x, at.y]
	world.place_player(Transform3D(Basis.IDENTITY, start))
	await _frames(20)
	var recoveries := world.fall_recovery.recoveries
	var violations := world.region_monitor.violations
	var dir := Vector3(at.x - start.x, 0.0, at.y - start.z).normalized()
	for f in EXTENSION_PUSH_FRAMES:
		bot.world_dir = dir
		if f % 25 == 0:
			bot.press(&"jump")
		await _frames(1)
	bot.world_dir = Vector3.ZERO
	await _frames(30)
	var pushed := player.global_position
	var known := _known_extension_slot(def, pushed)
	if known != "" and not player.is_on_floor():
		print("WORLD_KNOWN %s: hangs in the air at %s after the push: %s" % [label, pushed, known])
	else:
		_ok(player.is_on_floor(), "%s: hangs in the air at %s after the push" % [label, pushed])
	for _f in 240:
		var to := Vector3(start.x - player.global_position.x, 0.0, start.z - player.global_position.z)
		if to.length() < 0.5:
			break
		bot.world_dir = to.normalized()
		await _frames(1)
	bot.world_dir = Vector3.ZERO
	await _frames(10)
	var back := player.global_position
	_ok(Vector2(back.x - start.x, back.z - start.z).length() <= 0.75 and absf(back.y - start.y) <= 0.6,
		"%s: pushed to %s, cannot walk back (ended at %s)" % [label, pushed, back])
	_ok(world.fall_recovery.recoveries == recoveries, "%s: fell out of the ring (fall recovery; pushed to %s)" % [label, pushed])
	_ok(world.region_monitor.violations == violations, "%s: region invariant violated (%s)" % [label, str(world.region_monitor.last_violation)])
	_ok(session.current_map == def.map_id, "%s: map changed to %s" % [label, session.current_map])


# --- helpers ----------------------------------------------------------------------------------------------------

func _warp(map_id: String, portal_id: String = "") -> bool:
	if session.debug_warp(map_id, portal_id) != OK:
		return false
	return await _idle()


func _load(location: Dictionary) -> bool:
	if session.enter_from_location(location) != OK:
		return false
	return await _idle()


## Presses Up inside portal p (after warping next to it) and waits for the arrival.
func _press(p: PortalDef) -> bool:
	if not await _warp(p.source_map_id, p.portal_id):
		return false
	world.place_player(Transform3D(MapDefinitions.facing_basis(-p.inward), p.anchor_ground))
	await _frames(3)
	bot.press(&"portal_enter")
	for _f in 4:
		await get_tree().physics_frame
		if not session.is_idle():
			return await _idle()
	_ok(false, "%s: press not taken" % p.key())
	return false


func _idle(max_frames: int = 240) -> bool:
	for _i in max_frames:
		if session.is_idle():
			return true
		await get_tree().physics_frame
	return session.is_idle()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _physics_frames(n: int) -> void:
	await _frames(n)


func _begin(section: String) -> void:
	_section = section
	_section_total = 0
	_section_failed = 0


func _end() -> void:
	print("WORLD_SECTION %s %d %d" % [_section, _section_total, _section_failed])


func _ok(cond: bool, detail: String) -> void:
	total += 1
	_section_total += 1
	if not cond:
		failed += 1
		_section_failed += 1
		print("WORLD_CHECK FAIL %s: %s" % [_section, detail])
