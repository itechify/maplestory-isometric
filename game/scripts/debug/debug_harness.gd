class_name DebugHarness
extends RefCounted
## A private, fully injected debug setup for tests and headless tools: its own Debug (DebugTools), MapSession, Game,
## Saves (in a throwaway user:// directory) and Events bus, so console commands run headless without touching the
## autoloads' state or a real save slot. Without a world every warp completes synchronously; attach_world() hands the
## session (and the console) a built IslandWorld.
##
##   var h := DebugHarness.create(db)
##   h.run("warp 000000040")      # -> "warped to 000000040 Snail Hunting Ground I at player_spawns[0]"
##   h.free_all()

var dbg: DebugTools = null
var session: Node = null
var game: GameState = null
var saves: SaveService = null
var bus: Node = null
var db: ContentDB = null
var save_dir: String = ""
## Game time the private session and Game read (advance it in tests).
var now: float = 0.0
## [signal name, args] heard on the private bus for the WATCHED signals.
var heard: Array = []

const WATCHED: PackedStringArray = ["exp_gained", "leveled_up", "stats_changed", "hp_changed", "mp_changed",
	"mesos_changed", "item_gained", "item_lost", "inventory_changed", "monster_killed", "quest_started",
	"quest_completed", "quest_forfeited"]


## Builds everything. `wire_quests`: give the private Game a live QuestService (Game.wire_quests) instead of letting
## the console fall back to its own unattached one.
static func create(content: ContentDB, wire_quests: bool = false) -> DebugHarness:
	var h := DebugHarness.new()
	h.db = content
	h.bus = load("res://scripts/autoload/events.gd").new()
	for sig in WATCHED:
		var s := sig
		h.bus.connect(s, func(a: Variant = null, b: Variant = null) -> void: h.heard.append([s, [a, b]]))
	h.save_dir = "user://_tests/debug_%d_%d" % [Time.get_ticks_usec(), randi()]
	h.saves = SaveService.new()
	h.saves.save_dir = h.save_dir
	h.saves.db = content
	h.saves.event_bus = h.bus
	h.saves.log_failures = false
	h.saves.can_save_override = func() -> bool: return true
	h.saves.world_provider = func(ch: CharacterState) -> Dictionary: return SaveDocument.world_from_character(ch)
	h.game = GameState.new()
	h.game.db = content
	h.game.save_service = h.saves
	h.game.event_bus = h.bus
	h.game.log_warnings = false
	h.game.autosave_enabled = false
	h.game.rng.seed = 1
	h.saves.game_node = h.game
	h.game.new_game({"save": false})
	if wire_quests and h.game.has_method("wire_quests"):
		h.game.call("wire_quests", h.bus)
	h.session = load("res://scripts/autoload/map_session.gd").new()
	h.session.set("defs", MapDefinitions.build(content))
	h.session.set("content", content)
	h.session.set("character", h.game.character)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	h.session.set("rng", r)
	h.session.set("autosave_enabled", false)
	h.session.set("clock_provider", func() -> float: return h.now)
	h.dbg = DebugTools.new()
	h.dbg.content = content
	h.dbg.event_bus = h.bus
	h.dbg.game = h.game
	h.dbg.session = h.session
	h.dbg.install_builtins()
	h.adopt_game_commands()
	return h


## Registers the private Game's console commands on the private Debug, as Game._register_debug_commands() does for
## the autoloads (save, load, saves, delete_save, reset_save).
func adopt_game_commands() -> void:
	dbg.register_command("save", "save [slot]: save the game (default: current slot)", Callable(game, "_cmd_save"))
	dbg.register_command("load", "load [slot]: load a save (default: current slot)", Callable(game, "_cmd_load"))
	dbg.register_command("saves", "saves: list save slots", Callable(game, "_cmd_saves"))
	dbg.register_command("delete_save", "delete_save <slot>: delete a save and its backup", Callable(game, "_cmd_delete"))
	dbg.register_command("reset_save", "reset_save [slot]: wipe the slot and start a clean new game in it", Callable(game, "_cmd_reset"))


## Hands a built IslandWorld to the private session and the console.
func attach_world(world: Node) -> void:
	world.set("session", session)
	session.call("attach_world", world)
	dbg.world_node = world


func run(line: String) -> String:
	return dbg.run(line)


## Signals heard with this name.
func count(sig: String) -> int:
	var n := 0
	for e in heard:
		if e[0] == sig:
			n += 1
	return n


func free_all() -> void:
	if dbg != null and is_instance_valid(dbg):
		dbg.free()
	for n: Node in [session, game, saves, bus]:
		if n != null and is_instance_valid(n):
			n.free()
	_remove_tree(save_dir)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	for d in dir.get_directories():
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
