class_name TraversalWalker
extends Node
## The traversal bot's body in the real game world (MAP_ARCHITECTURE.md section 4.13 L2/L3): the island
## (IslandWorld, collision only), the game's PlayerController (scenes/actors/player.tscn) driven by a BotInput, and
## the real MapSession autoload with its GateMonitor, RegionMonitor, PortalInteractor and FallRecovery. Everything
## runs on real physics frames (run headless with --fixed-fps 60); the waits are coroutines.
##
##   var w := TraversalWalker.new(); add_child(w); await w.setup()
##   await w.warp("000000040", "east00")
##   var r: Dictionary = await w.walk(path, "label")     # RouteBot along path: {ok, result, time_s, distance_m, ...}
##   var ok: bool = await w.press_up(portal)             # step into its trigger, press Up, wait for IDLE
##
## Every walk reports the fall recoveries, region invariant violations and gate errors it caused, and `events` holds
## the Events map_left / map_entered / portal_used sequence ("left:<map>", "entered:<map><<old>", "portal:<map>.<portal>><to>").

## A walk's or press's result is complete once the session is IDLE again; frames to wait for that at most.
const IDLE_WAIT_FRAMES := 300
## Before the player (0): the bot decides this tick's intent before the controller steps.
const PHYSICS_PRIORITY := -10
## Row spacing of the paths handed to RouteBot (m): rises along stairs stay below a step.
const PATH_STEP_M := 0.5
## How far sideways (m) a path point may move to step around a prop on the walkable ground (TraversalPaths).
const DEFAULT_CLEARANCE_M := 2.0
## Frames of a straight nudge into a portal trigger after a walk stopped short of it.
const NUDGE_FRAMES := 45
const PLAYER_SCENE := "res://scenes/actors/player.tscn"

signal walk_done(result: Dictionary)

var world: IslandWorld = null
var session: Node = null
var player: PlayerController = null
var bot: BotInput = BotInput.new()
var events: Array[String] = []
## The session and instance clock (frozen: instances never respawn under the bot, and runs are repeatable).
var fake_t: float = 1000.0
var setup_error: String = ""

var _rb: RouteBot = null
var _walk: Dictionary = {}


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY


## Builds the world and the player. Returns false (with setup_error) when either is missing.
func setup() -> bool:
	session = get_node_or_null("/root/MapSession")
	if session == null:
		setup_error = "no MapSession autoload"
		return false
	session.set("autosave_enabled", false)
	session.set("clock_provider", func() -> float: return fake_t)
	world = IslandWorld.new()
	world.name = "World"
	world.build_on_ready = false
	world.load_visuals = false
	add_child(world)
	world.build_now()
	world.instance_view.clock = func() -> float: return fake_t
	if not world.build_errors.is_empty():
		setup_error = "build errors: %s" % "; ".join(world.build_errors)
		return false
	var scene: PackedScene = load(PLAYER_SCENE) if ResourceLoader.exists(PLAYER_SCENE) else null
	var node: Node = scene.instantiate() if scene != null else null
	if not (node is PlayerController):
		setup_error = "%s is not a PlayerController" % PLAYER_SCENE
		if node != null:
			node.free()
		return false
	player = node
	add_child(player)
	player.set_input_source(bot)
	world.set_player(player)
	var ev := get_node("/root/Events")
	ev.connect("map_left", func(m: String) -> void: events.append("left:" + m))
	ev.connect("map_entered", func(m: String, old: String) -> void: events.append("entered:%s<%s" % [m, old]))
	ev.connect("portal_used", func(m: String, p: String, to: String) -> void: events.append("portal:%s.%s>%s" % [m, p, to]))
	await get_tree().physics_frame
	return true


func defs() -> MapDefinitions:
	return world.defs


## Enters the world as a new game (new_character.json start_location: 000000001 player_spawns[0]).
func new_game() -> bool:
	if session.call("start_new_game") != OK:
		return false
	return await idle()


## Debug warp to a map's player_spawns[0] or a portal's arrival.
func warp(map_id: String, portal_id: String = "") -> bool:
	if session.call("debug_warp", map_id, portal_id) != OK:
		return false
	var ok: bool = await idle()
	await frames(2)
	return ok


func idle(max_frames: int = IDLE_WAIT_FRAMES) -> bool:
	for _i in max_frames:
		if bool(session.call("is_idle")):
			return true
		await get_tree().physics_frame
	return bool(session.call("is_idle"))


func frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


## Walks `path` (world points; the first is replaced by the player's position) with RouteBot, every point moved
## sideways up to `clearance_m` around props standing on the way (TraversalPaths). Returns {"ok" (DONE
## with no recovery, violation or gate error), "result", "time_s", "distance_m", "recoveries", "violations",
## "gate_errors", "issues" (PackedStringArray), "report" (RouteBot.report()), "end" (Vector3)}.
func walk(path: PackedVector3Array, label: String, clearance_m: float = DEFAULT_CLEARANCE_M) -> Dictionary:
	var pts := PackedVector3Array([player.global_position])
	for k in range(1, path.size()):
		pts.append(path[k])
	if path.size() == 1:
		pts.append(path[0])
	pts = TraversalPaths.resample(pts, PATH_STEP_M)
	if clearance_m > 0.0:
		pts = TraversalPaths.with_clearance(world, pts, clearance_m).path
	_rb = RouteBot.create(pts, player.climbables, player.model, label)
	player.fell_out_of_world.connect(_on_fell)
	_walk = {"label": label, "t0": Time.get_ticks_msec(), "frames": 0, "distance": 0.0, "last": player.global_position,
		"recoveries": world.fall_recovery.recoveries, "violations": world.region_monitor.violations,
		"gate_errors": world.gate_monitor.errors.size()}
	var result: Dictionary = await walk_done
	return result


## Steps into `p`'s trigger (straight at its anchor for a moment if the walk ended short of it), presses Up and waits
## for the warp to finish. Returns {"ok", "time_s", "issues"}.
func press_up(p: PortalDef) -> Dictionary:
	var node := world.portal_node(p.source_map_id, p.portal_id)
	var issues := PackedStringArray()
	var f := 0
	while world.portal_under_player() != node and f < NUDGE_FRAMES:
		var d := Vector3(p.anchor_ground.x - player.global_position.x, 0.0, p.anchor_ground.z - player.global_position.z)
		bot.world_dir = d.normalized() if d.length() > 0.05 else Vector3.ZERO
		await get_tree().physics_frame
		f += 1
	bot.release_all()
	await frames(2)
	if world.portal_under_player() != node:
		issues.append("not inside %s's trigger at %s" % [p.key(), player.global_position])
		return {"ok": false, "time_s": 0.0, "issues": issues}
	var start := Time.get_ticks_msec()
	var frames_used := 0
	bot.press(&"portal_enter")
	var started := false
	for _f in 4:
		await get_tree().physics_frame
		frames_used += 1
		if not bool(session.call("is_idle")):
			started = true
			break
	if not started:
		issues.append("pressing Up in %s did not start a transition (%s)" % [p.key(), world.interactor.last_block])
		return {"ok": false, "time_s": 0.0, "issues": issues}
	for _i in IDLE_WAIT_FRAMES:
		if bool(session.call("is_idle")):
			break
		await get_tree().physics_frame
		frames_used += 1
	var ok := bool(session.call("is_idle"))
	if not ok:
		issues.append("%s: the warp did not finish" % p.key())
	return {"ok": ok and issues.is_empty(), "time_s": snappedf(frames_used / 60.0, 0.001), "issues": issues,
		"wall_ms": Time.get_ticks_msec() - start}


func _physics_process(delta: float) -> void:
	if _rb == null:
		return
	var pos := player.global_position
	_walk["distance"] = float(_walk.distance) + pos.distance_to(_walk.last)
	_walk["last"] = pos
	_walk["frames"] = int(_walk.frames) + 1
	var res := _rb.tick(player, bot, delta)
	if res == RouteBot.Result.RUNNING:
		return
	_finish()


func _on_fell(_at: Vector3) -> void:
	if _rb != null:
		_rb.notify_fall()


func _finish() -> void:
	var rb := _rb
	_rb = null
	bot.release_all()
	if player.fell_out_of_world.is_connected(_on_fell):
		player.fell_out_of_world.disconnect(_on_fell)
	var rec := world.fall_recovery.recoveries - int(_walk.recoveries)
	var vio := world.region_monitor.violations - int(_walk.violations)
	var gerr := world.gate_monitor.errors.size() - int(_walk.gate_errors)
	var issues := PackedStringArray()
	var result := String(RouteBot.Result.keys()[rb.result])
	if result != "DONE":
		issues.append(rb.report())
	if rec > 0:
		issues.append("%d fall recoveries" % rec)
	if vio > 0:
		issues.append("%d region invariant violations (last %s)" % [vio, str(world.region_monitor.last_violation)])
	if gerr > 0:
		issues.append("gate errors: %s" % "; ".join(world.gate_monitor.errors.slice(int(_walk.gate_errors))))
	walk_done.emit({"ok": issues.is_empty(), "result": result, "time_s": snappedf(int(_walk.frames) / 60.0, 0.001),
		"distance_m": snappedf(float(_walk.distance), 0.01), "recoveries": rec, "violations": vio, "gate_errors": gerr,
		"issues": issues, "report": rb.report(), "end": player.global_position})
