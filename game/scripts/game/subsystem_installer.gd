class_name SubsystemInstaller
extends RefCounted
## Puts the gameplay subsystems into a game: instantiates each subsystem scene, adds it under the GameContext node
## its entry names, then calls setup(ctx) on every installed node (docs/runtime/GAME_SHELL.md).
##
## The list is data: one entry per subsystem, {"name", "scene", "parent": "systems" | "ui_root"}. A scene that does
## not exist (yet) is skipped with one log line, so the shell runs with whatever subsystems exist. Every node is
## added before any setup() runs, so a subsystem's setup can find its siblings; setup() runs in list order.
##
##   var installer := SubsystemInstaller.new()
##   var rows := installer.install(ctx)               # DEFAULT_SUBSYSTEMS
##   installer.summary()                              # "installed 3 (HUD, ...), missing 4 (...)"

const PARENT_SYSTEMS := "systems"
const PARENT_UI := "ui_root"

const STATUS_INSTALLED := "installed"
const STATUS_MISSING := "missing"
const STATUS_FAILED := "failed"
## Installed, but the root node has no setup(ctx) method (it still runs, without the context).
const STATUS_NO_SETUP := "no_setup"

## The wave-2 subsystems, in setup order. Gameplay systems first (they own state the UI shows), then the UI, then
## debug tools (they may inspect everything else).
const DEFAULT_SUBSYSTEMS := [
	{"name": "MonsterSystem", "scene": "res://scenes/systems/monster_system.tscn", "parent": PARENT_SYSTEMS},
	{"name": "LootSystem", "scene": "res://scenes/systems/loot_system.tscn", "parent": PARENT_SYSTEMS},
	# Breakables (Iteration Three, contract C8): after MonsterSystem (it adds the PlayerCombat whose swings hit boxes)
	# and LootSystem (it puts a broken box's drops on the ground).
	{"name": "BreakableSystem", "scene": "res://scenes/systems/breakable_system.tscn", "parent": PARENT_SYSTEMS},
	{"name": "InteractionSystem", "scene": "res://scenes/systems/interaction_system.tscn", "parent": PARENT_SYSTEMS},
	{"name": "HUD", "scene": "res://scenes/ui/hud.tscn", "parent": PARENT_UI},
	{"name": "Windows", "scene": "res://scenes/ui/windows.tscn", "parent": PARENT_UI},
	{"name": "NpcUI", "scene": "res://scenes/ui/npc_ui.tscn", "parent": PARENT_UI},
	{"name": "DebugUI", "scene": "res://scenes/debug/debug_ui.tscn", "parent": PARENT_UI},
]

## Print one line per skipped or failed subsystem (tests switch it off).
var log_lines: bool = true
## One row per entry of the last install(): {"name", "scene", "parent", "status", "node", "error"}.
var report: Array[Dictionary] = []


## Installs `entries` into `ctx` and returns the report (also kept in `report`).
func install(ctx: GameContext, entries: Array = DEFAULT_SUBSYSTEMS) -> Array[Dictionary]:
	report = []
	# Pass 1: instantiate and add every scene that exists.
	for e: Variant in entries:
		report.append(_add(ctx, e))
	# Pass 2: setup(ctx) in list order, now that every sibling is in the tree.
	for row in report:
		var node: Node = row["node"]
		if node == null or row["status"] != STATUS_INSTALLED:
			continue
		if node.has_method("setup"):
			node.call("setup", ctx)
		else:
			row["status"] = STATUS_NO_SETUP
			_log("subsystem %s (%s) has no setup(ctx); it runs without the game context" % [row["name"], row["scene"]], true)
	return report


## The installed node named `subsystem_name`, or null.
func node_of(subsystem_name: String) -> Node:
	for row in report:
		if row["name"] == subsystem_name:
			return row["node"]
	return null


## Names of the rows with `status`.
func names_with(status: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for row in report:
		if row["status"] == status:
			out.append(String(row["name"]))
	return out


## One line for the log and the debug overlay.
func summary() -> String:
	var parts: PackedStringArray = []
	for status in [STATUS_INSTALLED, STATUS_NO_SETUP, STATUS_MISSING, STATUS_FAILED]:
		var n := names_with(status)
		if not n.is_empty():
			parts.append("%s %d (%s)" % [status, n.size(), ", ".join(n)])
	return ", ".join(parts) if not parts.is_empty() else "no subsystems"


func _add(ctx: GameContext, entry: Variant) -> Dictionary:
	var e: Dictionary = entry if entry is Dictionary else {}
	var row := {"name": str(e.get("name", "")), "scene": str(e.get("scene", "")), "parent": str(e.get("parent", "")),
		"status": STATUS_FAILED, "node": null, "error": ""}
	if row["name"] == "" or row["scene"] == "":
		row["error"] = "entry needs a name and a scene"
		_log("subsystem entry %s skipped: %s" % [var_to_str(entry), row["error"]], true)
		return row
	if not ResourceLoader.exists(row["scene"]):
		row["status"] = STATUS_MISSING
		_log("subsystem %s skipped: %s does not exist" % [row["name"], row["scene"]], false)
		return row
	var parent := _parent(ctx, row["parent"])
	if parent == null:
		row["error"] = "the game context has no '%s' node" % row["parent"]
		_log("subsystem %s skipped: %s" % [row["name"], row["error"]], true)
		return row
	var packed := load(row["scene"]) as PackedScene
	if packed == null:
		row["error"] = "%s is not a loadable scene" % row["scene"]
		_log("subsystem %s failed: %s" % [row["name"], row["error"]], true)
		return row
	var node := packed.instantiate()
	if node == null:
		row["error"] = "%s did not instantiate" % row["scene"]
		_log("subsystem %s failed: %s" % [row["name"], row["error"]], true)
		return row
	node.name = row["name"]
	parent.add_child(node)
	row["node"] = node
	row["status"] = STATUS_INSTALLED
	return row


static func _parent(ctx: GameContext, key: String) -> Node:
	if ctx == null:
		return null
	match key:
		PARENT_SYSTEMS:
			return ctx.systems
		PARENT_UI:
			return ctx.ui_root
	return null


func _log(text: String, warning: bool) -> void:
	if not log_lines:
		return
	if warning:
		push_warning("[Shell] " + text)
	else:
		print("[Shell] " + text)
