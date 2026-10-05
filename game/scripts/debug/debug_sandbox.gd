extends Node3D
## Debug tools sandbox (res://scenes/debug/debug_sandbox.tscn): the real island, the game's player and camera rig, a
## game context and the debug UI, driven by a step list. Run it from an ISOLATE copy (never against game/):
##
##   bash scripts/godot.sh --path _scratch/godot_runs/<name>/game --resolution 1600x900 --disable-vsync \
##       res://scenes/debug/debug_sandbox.tscn -- --map 000000040 \
##       --steps "@console open; help; @wait 0.5; @shot user://debug/console.png; @console close; @quit"
##
## Steps (separated by ";"): a console command (typed into the console, so it shows in its output), or
##   @wait <s>            let the game run
##   @shot <path>         save the next frame (user:// or absolute)
##   @console open|close
##   @tab <text>          type <text> into the console input and press Tab
##   @walk <x> <z> <s>    hold a world direction for s seconds (moves the player through its BotInput)
##   @quit
## Saving is off: the game is a quick-start character in slot "debug_sandbox", autosave and save-on-quit disabled,
## so a sandbox run never touches a real save slot.

var world: Node3D = null
var player: Node3D = null
var rig: Node3D = null
var ui_root: CanvasLayer = null
## GameContext.systems: the parent for gameplay system nodes (empty here; the console fences key handlers under it).
var systems: Node = null
var debug_ui: DebugUI = null
var ctx: Object = null
var _args: PackedStringArray = []


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	var game := get_node("/root/Game")
	game.set("autosave_enabled", false)
	game.set("autosave_on_quit", false)
	game.call("new_game", {"save": false, "slot": "debug_sandbox"})
	world = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	if DisplayServer.get_name() == "headless":
		world.set("load_visuals", false)
	add_child(world)
	await world.world_ready
	player = (load("res://scenes/actors/player.tscn") as PackedScene).instantiate()
	add_child(player)
	world.call("set_player", player)
	rig = (load("res://scenes/actors/camera_rig.tscn") as PackedScene).instantiate()
	add_child(rig)
	rig.call("set_target", player)
	rig.call("scan_occluders", world)
	var session := get_node("/root/MapSession")
	session.call("attach_camera", rig)
	ui_root = CanvasLayer.new()
	ui_root.name = "UI"
	add_child(ui_root)
	systems = Node.new()
	systems.name = "Systems"
	add_child(systems)
	ctx = _make_context()
	debug_ui = (load("res://scenes/debug/debug_ui.tscn") as PackedScene).instantiate()
	ui_root.add_child(debug_ui)
	debug_ui.setup(ctx)
	session.call("start_new_game")
	await _idle(session)
	var map := _arg("--map", "")
	if map != "":
		print("SANDBOX ", get_node("/root/Debug").call("run", "warp " + map))
		await _idle(session)
	await _wait(0.5)
	await _run_steps(_arg("--steps", ""))


func _run_steps(text: String) -> void:
	for raw in DebugTools.split_commands(text):
		var step := raw.strip_edges()
		var words := DebugTools.tokenize(step)
		if words.is_empty():
			continue
		match words[0]:
			"@wait":
				await _wait(float(words[1]) if words.size() > 1 else 0.5)
			"@shot":
				await _shot(words[1] if words.size() > 1 else "user://debug/shot.png")
			"@console":
				if words.size() > 1 and words[1] == "close":
					debug_ui.close_console()
				else:
					debug_ui.open_console()
			"@tab":
				debug_ui.console.input.text = step.substr(5)
				debug_ui.console._complete()
				await get_tree().process_frame
			"@walk":
				await _walk(Vector3(float(words[1]), 0.0, float(words[2])), float(words[3]) if words.size() > 3 else 1.0)
			"@quit":
				get_tree().quit(0)
				return
			_:
				var out := debug_ui.console.submit(step)
				print("SANDBOX > %s\n%s" % [step, out])
				await get_tree().process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	if img != null:
		img.save_png(abs_path)
		print("SHOT %s" % abs_path)
	else:
		print("SHOT failed (no renderer)")


func _walk(dir: Vector3, seconds: float) -> void:
	var bot := BotInput.new()
	var before: Variant = player.get("input_source")
	player.call("set_input_source", bot)
	bot.world_dir = dir.normalized()
	await _wait(seconds)
	bot.world_dir = Vector3.ZERO
	player.call("set_input_source", before)


func _idle(session: Node) -> void:
	var frames := 0
	while not bool(session.call("is_idle")) and frames < 600:
		await get_tree().physics_frame
		frames += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _arg(flag: String, fallback: String) -> String:
	var i := _args.find(flag)
	return _args[i + 1] if i >= 0 and i + 1 < _args.size() else fallback


## The shell's GameContext when its script loads, else a stand-in with the same duck-typed surface.
func _make_context() -> Object:
	var script := load("res://scripts/game/game_context.gd") as GDScript
	var c: Object = null
	if script != null and script.can_instantiate():
		c = script.new()
	else:
		push_warning("[debug sandbox] scripts/game/game_context.gd does not compile; using a stand-in context")
		c = StandInContext.new()
	c.set("main", self)
	c.set("world", world)
	c.set("player", player)
	c.set("camera", rig)
	c.set("ui_root", ui_root)
	c.set("systems", systems)
	return c


## Enough of GameContext for the debug UI: the references and the modal / window calls.
class StandInContext:
	extends RefCounted
	var main: Node = null
	var world: Node = null
	var player: Node = null
	var camera: Node = null
	var ui_root: CanvasLayer = null
	var systems: Node = null
	var _modals: Array = []

	func push_modal(owner: Object) -> void:
		if not (owner in _modals):
			_modals.append(owner)
		if player != null and player.has_method("set_input_enabled"):
			player.call("set_input_enabled", false)

	func pop_modal(owner: Object) -> void:
		_modals.erase(owner)
		if _modals.is_empty() and player != null and player.has_method("set_input_enabled"):
			player.call("set_input_enabled", true)

	func is_modal_active() -> bool:
		return not _modals.is_empty()

	func window_opened(_w: Control) -> void:
		pass

	func window_closed(_w: Control) -> void:
		pass
