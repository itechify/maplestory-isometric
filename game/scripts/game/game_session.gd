class_name GameSession
extends Node
## One running game: the island, the player, the camera, the subsystems and the death flow, composed in the order
## WORLD_RUNTIME.md and ARCHITECTURE.md require (docs/runtime/GAME_SHELL.md):
##
##   0. session    MapSession must be in BOOT. Quit to title resets it (IslandWorld._exit_tree -> detach_world ->
##                 reset(), and teardown() makes sure); a MapSession found past BOOT is reset here first
##   1. world      res://scenes/world/world.tscn; wait for world_ready (load_progress drives the loading screen)
##   2. player     res://scenes/actors/player.tscn, world.set_player(player)
##   3. camera     res://scenes/actors/camera_rig.tscn: set_target(player), MapSession.attach_camera, scan_occluders
##   4. context    GameContext {main, world, player, camera, ui_root (CanvasLayer "UI"), systems (Node "Systems")},
##                 handed to the world (world.set_context): a warp never gives the keyboard back under a modal, and
##                 portal keys pressed in a modal are ignored
##   5. death      DeathController (MapSession.death_commit = its commit_rules: the loss at the moment of death)
##   6. subsystems SubsystemInstaller: every scene of DEFAULT_SUBSYSTEMS that exists, then setup(ctx) on each
##   7. character  Game.new_game(params) or Game.load_game(slot), after the subsystems so they hear the new
##                 character's refresh signals (MapSession ignores Game.character_replaced while in BOOT)
##   8. enter      MapSession.start_new_game() / load_character(Game.character), then wait for IDLE.
##
## The session is pausable (process_mode PAUSABLE) even though the shell above it always processes.

signal progress(fraction: float, stage: String)

const WORLD_SCENE := "res://scenes/world/world.tscn"
const PLAYER_SCENE := "res://scenes/actors/player.tscn"
const CAMERA_SCENE := "res://scenes/actors/camera_rig.tscn"
const MODE_NEW := "new"
const MODE_LOAD := "load"
## CanvasLayer order: the HUD/window layer under the world's ScreenFader (100); the death notice over the HUD.
const UI_LAYER := 10
const NOTICE_LAYER := 90
## Share of the loading bar the island load takes (the rest: composing and placing the character).
const WORLD_SHARE := 0.85
## Frames to wait for MapSession to reach IDLE after the first transition before giving up.
const ENTER_TIMEOUT_FRAMES := 1800

var ctx: GameContext = null
var world: Node = null
var player: Node3D = null
var camera: Node3D = null
var ui_root: CanvasLayer = null
var notice_layer: CanvasLayer = null
var systems: Node = null
var death: DeathController = null
var installer: SubsystemInstaller = SubsystemInstaller.new()
## Subsystem list (SubsystemInstaller entries); tests replace it.
var subsystems: Array = SubsystemInstaller.DEFAULT_SUBSYSTEMS
## Load the visual chunks (forced off when headless: the threaded visual load crashes the dummy renderer).
var load_visuals: bool = true
## The main scene root (GameContext.main).
var main: Node = null
## Why start() failed ("" when it did not).
var error_message: String = ""
var is_ready: bool = false

var _stats_hooked := false


func _init() -> void:
	name = "GameSession"
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Composes everything and enters the world. mode MODE_NEW with `arg` = Game.new_game params, or MODE_LOAD with
## `arg` = the slot. Returns OK when the player stands in the world with MapSession IDLE.
func start(mode: String, arg: Variant) -> Error:
	error_message = ""
	var session := _autoload("MapSession")
	var game := _autoload("Game") as GameState
	if session == null or game == null:
		return _fail(ERR_UNCONFIGURED, "the MapSession and Game autoloads are required")
	# 0. a clean MapSession: the world is entered from BOOT, by start_new_game() / load_character() below
	_reset_map_session(session)
	# 1. world
	progress.emit(0.0, "loading the island")
	var world_scene := load(WORLD_SCENE) as PackedScene
	if world_scene == null:
		return _fail(ERR_FILE_NOT_FOUND, "%s is missing" % WORLD_SCENE)
	world = world_scene.instantiate()
	world.name = "World"
	if not ("is_built" in world) or not world.has_signal("world_ready"):
		# The IslandWorld script did not load (a parse error): fail with a message instead of waiting forever.
		world.free()
		world = null
		return _fail(ERR_CANT_CREATE, "the island world could not be created (%s has no working IslandWorld script)" % WORLD_SCENE)
	if "load_visuals" in world:
		world.set("load_visuals", load_visuals and DisplayServer.get_name() != "headless")
	if world.has_signal("load_progress"):
		world.connect("load_progress", _on_world_progress)
	add_child(world)
	if not bool(world.get("is_built")):
		await Signal(world, &"world_ready")
	if not is_inside_tree():
		return _fail(ERR_UNAVAILABLE, "the session was closed while loading")
	var build_errors: PackedStringArray = world.get("build_errors")
	if not build_errors.is_empty():
		push_warning("[GameSession] the world loaded with errors: %s" % "; ".join(build_errors))
	# 2. player
	progress.emit(WORLD_SHARE, "placing the player")
	player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Node3D
	player.name = "Player"
	add_child(player)
	world.call("set_player", player)
	# 3. camera
	camera = (load(CAMERA_SCENE) as PackedScene).instantiate() as Node3D
	camera.name = "CameraRig"
	add_child(camera)
	if camera.has_method("set_target"):
		camera.call("set_target", player)
	session.call("attach_camera", camera)
	if camera.has_method("scan_occluders"):
		camera.call("scan_occluders", world)
	# 4. context
	ui_root = CanvasLayer.new()
	ui_root.name = "UI"
	ui_root.layer = UI_LAYER
	add_child(ui_root)
	systems = Node.new()
	systems.name = "Systems"
	add_child(systems)
	notice_layer = CanvasLayer.new()
	notice_layer.name = "Notices"
	notice_layer.layer = NOTICE_LAYER
	add_child(notice_layer)
	ctx = GameContext.new()
	ctx.main = main if main != null else self
	ctx.world = world
	ctx.player = player
	ctx.camera = camera
	ctx.ui_root = ui_root
	ctx.systems = systems
	if world.has_method("set_context"):
		world.call("set_context", ctx)
	# 5. death
	death = DeathController.new()
	death.name = "DeathController"
	add_child(death)
	death.configure(session, game, _autoload("Events"), _db(), player, ctx, notice_layer)
	death.attach()
	# 6. subsystems
	progress.emit(WORLD_SHARE + 0.05, "starting systems")
	installer.install(ctx, subsystems)
	print("[GameSession] subsystems: %s" % installer.summary())
	_hook_stats(true)
	# 7. the character
	progress.emit(WORLD_SHARE + 0.1, "entering the world")
	var err := OK
	if mode == MODE_NEW:
		err = game.new_game(arg if arg is Dictionary else {})
		if err != OK:
			return _fail(err, "the character could not be created: %s" % "; ".join(game.last_creation_errors))
	elif mode == MODE_LOAD:
		err = game.load_game(String(arg))
		if err != OK:
			var saves := _autoload("Saves")
			return _fail(err, "the save could not be loaded: %s" % (String(saves.get("last_error_message")) if saves != null else error_string(err)))
	else:
		return _fail(ERR_INVALID_PARAMETER, "unknown session mode '%s'" % mode)
	# 8. enter the world
	err = session.call("start_new_game") if mode == MODE_NEW else session.call("load_character", game.character)
	if err != OK:
		return _fail(err, "MapSession could not place the character: %s" % String(session.get("last_error")))
	var frames := 0
	while not bool(session.call("is_idle")) and frames < ENTER_TIMEOUT_FRAMES:
		await get_tree().process_frame
		if not is_inside_tree():
			return _fail(ERR_UNAVAILABLE, "the session was closed while entering the world")
		frames += 1
	if not bool(session.call("is_idle")):
		return _fail(ERR_TIMEOUT, "MapSession did not reach IDLE (state %s)" % session.call("state_name"))
	_refresh_player_stats()
	death.armed = true
	is_ready = true
	progress.emit(1.0, "ready")
	return OK


## Undoes the composition: the death flow and the stat hooks are detached, MapSession forgets the camera, and the
## subtree is freed. The world's _exit_tree detaches it from MapSession, which then resets to BOOT (detach_world ->
## reset()); MapSession is also reset here if it is still past BOOT (a world that never attached, a failed start), so
## the next session always starts clean. The caller saves first.
func teardown() -> void:
	is_ready = false
	if death != null:
		death.armed = false
		death.detach()
	_hook_stats(false)
	var session := _autoload("MapSession")
	if session != null and camera != null and session.get("camera") == camera:
		session.call("attach_camera", null)
	if is_inside_tree():
		get_parent().remove_child(self)
	_reset_map_session(session)
	queue_free()


## The installer's row for a subsystem ({} when not listed).
func subsystem_row(subsystem_name: String) -> Dictionary:
	for row in installer.report:
		if row["name"] == subsystem_name:
			return row
	return {}


# --- player stats -----------------------------------------------------------------------------------------------

## Keeps the player's movement stats in sync (the controller itself only listens to stats_changed).
func _hook_stats(on: bool) -> void:
	var ev := _autoload("Events")
	var game := _autoload("Game")
	if on == _stats_hooked or ev == null:
		return
	var pairs := [[ev, &"stats_changed", _on_stats_signal], [ev, &"equipment_changed", _on_stats_signal_1],
		[ev, &"leveled_up", _on_level_signal], [game, &"character_replaced", _on_stats_signal_1]]
	for p in pairs:
		var src: Object = p[0]
		if src == null or not src.has_signal(p[1]):
			continue
		if on and not src.is_connected(p[1], p[2]):
			src.connect(p[1], p[2])
		elif not on and src.is_connected(p[1], p[2]):
			src.disconnect(p[1], p[2])
	_stats_hooked = on


func _on_stats_signal() -> void:
	_refresh_player_stats()


func _on_stats_signal_1(_arg: Variant) -> void:
	_refresh_player_stats()


func _on_level_signal(_level: int) -> void:
	_refresh_player_stats()


## player.refresh_stats(Game.character, Data.db).
func _refresh_player_stats() -> void:
	var game := _autoload("Game")
	if player == null or not is_instance_valid(player) or game == null or not player.has_method("refresh_stats"):
		return
	player.call("refresh_stats", game.get("character"), _db())


# --- internals ----------------------------------------------------------------------------------------------------

## MapSession.reset() unless it is already in BOOT (reset() emits session_reset each time it runs).
static func _reset_map_session(session: Node) -> void:
	if session != null and session.has_method("reset") and String(session.call("state_name")) != "BOOT":
		session.call("reset")


func _on_world_progress(fraction: float, stage: String) -> void:
	progress.emit(clampf(fraction, 0.0, 1.0) * WORLD_SHARE, stage)


func _fail(err: Error, why: String) -> Error:
	error_message = why
	push_warning("[GameSession] " + why)
	return err


func _db() -> ContentDB:
	var data := _autoload("Data")
	return data.get("db") as ContentDB if data != null else null


static func _autoload(autoload_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(autoload_name) if tree != null else null
