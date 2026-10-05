class_name DebugTools
extends Node
## Autoload "Debug": the developer console's command registry, the collaborators its commands drive, and the state
## of the debug overlay and draw layers (brief Phase 20). See docs/runtime/DEBUG_TOOLS.md.
##
## Fixed contract (any system may call these):
##   register_command(name: String, help: String, handler: Callable) -> void
##   run(command_line: String) -> String
## A handler receives the arguments as a PackedStringArray (double quotes group words: give "Red Potion" 5) and
## returns the text to print. `run` accepts several commands separated by ";".
##
## The console UI (scenes/debug/debug_ui.tscn), tests and the traversal bot all go through run(), so every command
## works headless against the autoloads. Built-in commands live in scripts/debug/debug_commands.gd and are installed
## synchronously in _ready (other autoloads register theirs before or after; nothing here depends on the order).
##
## Collaborators are resolved on every call: an injected field when set (tests), else the GameContext handed to the
## debug UI's setup(ctx), else the autoloads (MapSession, Game, Data, Events) and MapSession.world / .camera.

## Emitted after every run() with the line and its output (the console mirrors commands run by code).
signal command_ran(line: String, output: String)
## Text produced later than the command that caused it (screenshots, async warps).
signal message(text: String)
signal overlay_toggled(on: bool)
signal layer_toggled(layer: String, on: bool)
## The console should clear its output ("clear").
signal clear_requested()
## Emitted around a screenshot capture so the console can hide itself (true) and come back (false).
signal capture_state(capturing: bool)

const MAX_HISTORY := 200
## The draw layers (scripts/debug/debug_draw.gd) and the command that toggles each.
const LAYERS: PackedStringArray = ["collision", "spawns", "portals", "npcs", "camera", "mobregion", "rings", "safeground"]

# --- registry -------------------------------------------------------------------------------------------------
var _commands: Dictionary = {}
## alias -> {"target": command name, "args": PackedStringArray prepended to the alias's own arguments}
var _aliases: Dictionary = {}
## command -> Array of argument kinds for Tab completion (see DebugCompleter.KINDS)
var _completions: Dictionary = {}
## Debug-owned dispatcher commands (e.g. "quest"): a later or earlier registration under the same name is kept as
## the dispatcher's fallback in _shadowed instead of replacing it.
var _composites: Dictionary = {}
var _shadowed: Dictionary = {}
## Console input history, oldest first (shared by every console instance).
var history: PackedStringArray = []

# --- injectable collaborators (null = context / autoloads) ----------------------------------------------------
var session: Node = null
var game: Node = null
var content: ContentDB = null
var event_bus: Object = null
var world_node: Node = null
var player_node: Node3D = null
var camera_node: Object = null
## The GameContext the debug UI received in setup(ctx) (null when standalone). Duck-typed (world, player, camera,
## push_modal ...) so this file compiles on its own.
var ctx: Object = null

# --- state ----------------------------------------------------------------------------------------------------
var overlay_enabled: bool = false
## layer name -> bool
var layers: Dictionary = {}
var god_mode: bool = false
## The built-in commands (null until install_builtins()).
var builtins: DebugCommands = null
## The 3D draw layers (created on demand under the world).
var draw: DebugDraw = null
## Smoothed frame timing for the overlay (ms).
var frame_ms: float = 0.0

var _god_hp_lock: bool = false
var _draw_check_t: float = 0.0
var _fallback_db: ContentDB = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	install_builtins()


## Installs the built-in commands and god mode's HP lock (the autoload does this in _ready; tests call it on a
## private instance after injecting its collaborators).
func install_builtins() -> void:
	if builtins != null:
		return
	builtins = DebugCommands.new(self)
	builtins.install()
	var ev := get_bus()
	if ev != null and ev.has_signal("hp_changed") and not ev.is_connected("hp_changed", _on_hp_changed):
		ev.connect("hp_changed", _on_hp_changed)


# --- the registry (fixed contract) ----------------------------------------------------------------------------

## Registers (or replaces) a command. `help` is one line, conventionally "name <args>: what it does".
func register_command(cmd_name: String, help: String, handler: Callable) -> void:
	var key := cmd_name.strip_edges().to_lower()
	if key == "":
		return
	if _composites.has(key):
		_shadowed[key] = {"help": help, "handler": handler}
		return
	_commands[key] = {"help": help, "handler": handler}


## Runs one console line (or several separated by ";") and returns the printed text.
func run(command_line: String) -> String:
	var outputs: PackedStringArray = []
	for line in split_commands(command_line):
		var out := _run_one(line)
		command_ran.emit(line, out)
		if out != "":
			outputs.append(out)
	return "\n".join(outputs)


# --- registry extras ------------------------------------------------------------------------------------------

## Registers a Debug-owned dispatcher. A command already registered under the name (or registered later) becomes
## its fallback: shadowed_handler(name).
func register_composite(cmd_name: String, help: String, handler: Callable) -> void:
	var key := cmd_name.to_lower()
	if _commands.has(key) and not _composites.has(key):
		_shadowed[key] = _commands[key]
	_composites[key] = true
	_commands[key] = {"help": help, "handler": handler}


## The handler another system registered under a composite's name (invalid Callable when none).
func shadowed_handler(cmd_name: String) -> Callable:
	var e: Dictionary = _shadowed.get(cmd_name.to_lower(), {})
	return e.get("handler", Callable())


func shadowed_help(cmd_name: String) -> String:
	return String((_shadowed.get(cmd_name.to_lower(), {}) as Dictionary).get("help", ""))


## `alias` runs `target` with `prefix_args` before the alias's own arguments. Resolved at run time, so the target
## may be registered later (Game registers save/load/reset_save deferred).
func register_alias(alias_name: String, target: String, prefix_args: PackedStringArray = PackedStringArray()) -> void:
	_aliases[alias_name.to_lower()] = {"target": target.to_lower(), "args": prefix_args}


## Tab-completion kinds for each argument position (DebugCompleter.KINDS), e.g. ["map", "portal"].
func set_completion(cmd_name: String, kinds: Array) -> void:
	_completions[cmd_name.to_lower()] = kinds


func completion_kinds(cmd_name: String) -> Array:
	return _completions.get(resolve_name(cmd_name), [])


func has_command(cmd_name: String) -> bool:
	var key := cmd_name.to_lower()
	return _commands.has(key) or (_aliases.has(key) and _commands.has(String(_aliases[key].target)))


## Every registered command name, sorted (aliases not included).
func command_names() -> PackedStringArray:
	var out := PackedStringArray(_commands.keys())
	out.sort()
	return out


func alias_names() -> PackedStringArray:
	var out := PackedStringArray(_aliases.keys())
	out.sort()
	return out


## The command an alias stands for (the name itself when it is not an alias).
func resolve_name(cmd_name: String) -> String:
	var key := cmd_name.to_lower()
	return String(_aliases[key].target) if _aliases.has(key) else key


func command_help(cmd_name: String) -> String:
	return String((_commands.get(cmd_name.to_lower(), {}) as Dictionary).get("help", ""))


## The handler's owner (e.g. the QuestService behind quest_accept), or null.
func command_owner(cmd_name: String) -> Object:
	var e: Dictionary = _commands.get(cmd_name.to_lower(), {})
	var h: Variant = e.get("handler", null)
	return (h as Callable).get_object() if h is Callable else null


## Runs a registered command with already-split arguments.
func call_command(cmd_name: String, args: PackedStringArray) -> String:
	return _dispatch(cmd_name.to_lower(), args)


## Splits a console line into words; double quotes group words ("Red Potion"), \" is a literal quote.
static func tokenize(line: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var cur := ""
	var quoted := false
	var has_token := false
	var i := 0
	while i < line.length():
		var ch := line[i]
		if ch == "\\" and i + 1 < line.length() and line[i + 1] == "\"":
			cur += "\""
			has_token = true
			i += 2
			continue
		if ch == "\"":
			quoted = not quoted
			has_token = true
		elif not quoted and (ch == " " or ch == "\t"):
			if has_token:
				out.append(cur)
			cur = ""
			has_token = false
		else:
			cur += ch
			has_token = true
		i += 1
	if has_token:
		out.append(cur)
	return out


## Splits a line on ";" outside double quotes; empty pieces are dropped.
static func split_commands(line: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var cur := ""
	var quoted := false
	for ch in line:
		if ch == "\"":
			quoted = not quoted
		if ch == ";" and not quoted:
			if cur.strip_edges() != "":
				out.append(cur.strip_edges())
			cur = ""
		else:
			cur += ch
	if cur.strip_edges() != "":
		out.append(cur.strip_edges())
	return out


## Remembers a console line (consecutive duplicates collapse).
func add_history(line: String) -> void:
	var l := line.strip_edges()
	if l == "":
		return
	if history.is_empty() or history[history.size() - 1] != l:
		history.append(l)
	while history.size() > MAX_HISTORY:
		history.remove_at(0)


## Tab completion for a console line: {"line": completed line, "candidates": [display strings]}.
func complete(line: String) -> Dictionary:
	return DebugCompleter.new(self).complete(line)


func _run_one(line: String) -> String:
	var parts := tokenize(line)
	if parts.is_empty():
		return ""
	return _dispatch(parts[0].to_lower(), parts.slice(1))


func _dispatch(key: String, args: PackedStringArray) -> String:
	if not _commands.has(key) and _aliases.has(key):
		var a: Dictionary = _aliases[key]
		var full := PackedStringArray(a.args)
		full.append_array(args)
		var alias_name := key
		key = String(a.target)
		args = full
		if not _commands.has(key):
			return "unknown command: %s (an alias of %s, which is not registered yet)" % [alias_name, key]
	var entry: Dictionary = _commands.get(key, {})
	if entry.is_empty():
		var near := suggest(key)
		return "unknown command: %s%s (type help)" % [key, (" - did you mean %s?" % ", ".join(near)) if not near.is_empty() else ""]
	var handler: Callable = entry.handler
	if not handler.is_valid():
		return "%s: its owner is gone (the system that registered it was freed)" % key
	var result: Variant = handler.call(args)
	if result == null:
		return "%s: no result (the handler failed; see the log)" % key
	return str(result)


## Up to 3 command names close to `word` (prefix match first, then edit distance <= 2).
func suggest(word: String) -> PackedStringArray:
	var names := command_names()
	names.append_array(alias_names())
	var out: PackedStringArray = []
	for n in names:
		if n.begins_with(word) and word.length() >= 2:
			out.append(n)
	if out.is_empty():
		for n in names:
			if absi(n.length() - word.length()) <= 2 and _distance(n, word) <= 2:
				out.append(n)
	out.sort()
	return out.slice(0, 3)


static func _distance(a: String, b: String) -> int:
	var prev: Array[int] = []
	for j in b.length() + 1:
		prev.append(j)
	for i in range(1, a.length() + 1):
		var cur: Array[int] = [i]
		for j in range(1, b.length() + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			cur.append(mini(mini(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost))
		prev = cur
	return prev[b.length()]


# --- collaborators --------------------------------------------------------------------------------------------

## Wires the game's references (the debug UI's setup(ctx) calls this). Any null field means "not available".
func attach_context(context: Object) -> void:
	ctx = context
	if draw != null and is_instance_valid(draw):
		draw.request_rebuild()


## A field of the attached GameContext (null when there is none, it is unset or its object was freed).
func _ctx_field(field: String) -> Variant:
	if ctx == null or not is_instance_valid(ctx):
		return null
	var v: Variant = ctx.get(field)
	if typeof(v) == TYPE_OBJECT and not is_instance_valid(v):
		return null
	return v


func get_session() -> Node:
	if session != null and is_instance_valid(session):
		return session
	return _autoload("MapSession")


func get_game() -> Node:
	if game != null and is_instance_valid(game):
		return game
	return _autoload("Game")


func get_db() -> ContentDB:
	if content != null:
		return content
	var data := _autoload("Data")
	var db: Variant = data.get("db") if data != null else null
	if db is ContentDB:
		return db
	if _fallback_db == null:
		_fallback_db = ContentDB.new().load_all()
	return _fallback_db


func get_bus() -> Object:
	if event_bus != null:
		return event_bus
	return _autoload("Events")


## The IslandWorld in play (injected, the context's, or MapSession's), or null.
func get_world() -> Node:
	if world_node != null and is_instance_valid(world_node):
		return world_node
	var cw: Variant = _ctx_field("world")
	if cw is Node:
		return cw
	var s := get_session()
	var w: Variant = s.get("world") if s != null else null
	return w if is_instance_valid(w) and w is Node else null


## The player body (injected, the context's, or the world's), or null.
func get_player() -> Node3D:
	if player_node != null and is_instance_valid(player_node):
		return player_node
	var cp: Variant = _ctx_field("player")
	if cp is Node3D:
		return cp
	var w := get_world()
	var p: Variant = w.get("player") if w != null else null
	return p if is_instance_valid(p) and p is Node3D else null


## The camera rig (injected, the context's, or MapSession's), or null.
func get_camera() -> Object:
	if camera_node != null and is_instance_valid(camera_node):
		return camera_node
	var cc: Variant = _ctx_field("camera")
	if cc is Object:
		return cc
	var s := get_session()
	var c: Variant = s.get("camera") if s != null else null
	return c if is_instance_valid(c) else null


## The map definitions in use (MapSession's, which are the world's once it is attached).
func get_defs() -> MapDefinitions:
	var s := get_session()
	if s != null and s.has_method("get_defs"):
		return s.call("get_defs") as MapDefinitions
	return MapDefinitions.build(get_db())


func get_character() -> CharacterState:
	var g := get_game()
	var c: Variant = g.get("character") if g != null else null
	return c if c is CharacterState else null


## The gameplay RNG (Game.rng), or null.
func get_rng() -> RandomNumberGenerator:
	var g := get_game()
	var r: Variant = g.get("rng") if g != null else null
	return r if r is RandomNumberGenerator else null


## Game time (Game.clock), 0 without a Game.
func get_clock() -> float:
	var g := get_game()
	var t: Variant = g.get("clock") if g != null else null
	return float(t) if t != null else 0.0


## The current map id ("" before the first map).
func current_map() -> String:
	var s := get_session()
	return String(s.get("current_map")) if s != null and s.get("current_map") != null else ""


## Emits an Events signal (the injected bus or the Events autoload).
func emit_event(sig: StringName, args: Array = []) -> void:
	var bus := get_bus()
	if bus != null and bus.has_signal(sig):
		bus.callv(&"emit_signal", [sig] + args)


func _autoload(autoload_name: String) -> Node:
	if is_inside_tree():
		return get_tree().root.get_node_or_null(autoload_name)
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(autoload_name) if tree != null else null


# --- overlay and draw layers ----------------------------------------------------------------------------------

func set_overlay(on: bool) -> void:
	if overlay_enabled == on:
		return
	overlay_enabled = on
	overlay_toggled.emit(on)


## The overlay text (FPS, map, session, player, monsters, camera); the UI shows it, tests read it.
func overlay_text() -> String:
	return "\n".join(DebugReport.overlay_lines(self))


func is_layer_on(layer: String) -> bool:
	return bool(layers.get(layer, false))


## Turns a draw layer on or off. Returns false for an unknown layer. The draw node is created under the world when
## one exists (now or later).
func set_layer(layer: String, on: bool) -> bool:
	if not (layer in LAYERS):
		return false
	layers[layer] = on
	layer_toggled.emit(layer, on)
	var d := ensure_draw()
	if d != null:
		d.set_layer_visible(layer, on)
	return true


func any_layer_on() -> bool:
	for l in layers:
		if bool(layers[l]):
			return true
	return false


## The DebugDraw node under the current world (created on first use), or null without a world.
func ensure_draw() -> DebugDraw:
	var w := get_world()
	if w == null or not (w is Node3D) or not w.is_inside_tree():
		return null
	if draw != null and is_instance_valid(draw) and draw.get_parent() == w:
		return draw
	if draw != null and is_instance_valid(draw):
		draw.queue_free()
	draw = DebugDraw.new()
	draw.name = "DebugDraw"
	draw.dbg = self
	w.add_child(draw)
	for l in layers:
		draw.set_layer_visible(String(l), bool(layers[l]))
	return draw


func _process(delta: float) -> void:
	frame_ms = lerpf(frame_ms, delta * 1000.0 / maxf(Engine.time_scale, 0.0001), 0.1) if frame_ms > 0.0 else delta * 1000.0
	if any_layer_on():
		_draw_check_t += delta
		if _draw_check_t >= 0.5:
			_draw_check_t = 0.0
			ensure_draw()


func _physics_process(_delta: float) -> void:
	if not god_mode:
		return
	var p := get_player()
	if p != null and p.has_method("set_invulnerable"):
		# Topped up every tick with a short window, so "god off" ends it within that window through the public API.
		p.call("set_invulnerable", 0.25)


# --- god mode -------------------------------------------------------------------------------------------------

func set_god_mode(on: bool) -> void:
	god_mode = on
	if on:
		_refill_hp()


func _on_hp_changed(hp: int, max_hp: int) -> void:
	if god_mode and not _god_hp_lock and hp < max_hp:
		_refill_hp()


## Restores HP to the derived maximum (god mode's HP lock).
func _refill_hp() -> void:
	var c := get_character()
	if c == null:
		return
	var m := StatCalculator.max_hp(c, get_db())
	if c.hp >= m:
		return
	_god_hp_lock = true
	c.hp = m
	emit_event(&"hp_changed", [c.hp, m])
	_god_hp_lock = false


# --- screenshots ----------------------------------------------------------------------------------------------

## Saves the next rendered frame (without the console) to `path` (user:// or absolute). Returns the absolute path
## it will write, or "" with the reason in `why` when no renderer is available.
func screenshot(path: String = "") -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {"ok": false, "error": "no renderer in headless mode"}
	if not is_inside_tree():
		return {"ok": false, "error": "the Debug node is not in the scene tree"}
	var p := path
	if p == "":
		p = "user://screenshots/misostory_%s.png" % Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	elif not p.ends_with(".png"):
		p += ".png"
	var abs_path := ProjectSettings.globalize_path(p)
	_capture(abs_path)
	return {"ok": true, "path": abs_path}


func _capture(abs_path: String) -> void:
	capture_state.emit(true)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	capture_state.emit(false)
	if img == null:
		message.emit("screenshot failed: the viewport returned no image")
		return
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err := img.save_png(abs_path)
	message.emit("screenshot saved: %s" % abs_path if err == OK else "screenshot failed: %s (%s)" % [error_string(err), abs_path])
