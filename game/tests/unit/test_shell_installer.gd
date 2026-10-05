extends TestCase
## SubsystemInstaller: the data-driven list of subsystem scenes. Missing scenes are skipped, existing ones are added
## under the context node their entry names, and setup(ctx) runs on each once every node is in the tree. Uses real
## .tscn files written to a private user:// directory (never the production scene paths, which other systems fill).

const PROBE_SCRIPT := """extends Node
var ctx_seen: Object = null
var siblings_at_setup: int = -1
func setup(ctx: GameContext) -> void:
	ctx_seen = ctx
	siblings_at_setup = get_parent().get_child_count()
"""
const UI_PROBE_SCRIPT := """extends Control
var ctx_seen: Object = null
func setup(ctx: GameContext) -> void:
	ctx_seen = ctx
"""

var dir := ""
var holder: Node = null
var ctx: GameContext = null


func before_each() -> void:
	dir = "user://_tests/shell_installer_%d_%d" % [Time.get_ticks_usec(), randi()]
	DirAccess.make_dir_recursive_absolute(dir)
	holder = Node.new()
	_parent().add_child(holder)
	ctx = GameContext.new()
	ctx.systems = Node.new()
	ctx.systems.name = "Systems"
	holder.add_child(ctx.systems)
	ctx.ui_root = CanvasLayer.new()
	ctx.ui_root.name = "UI"
	holder.add_child(ctx.ui_root)


## The test runner scene (the root is still busy adding it while tests run).
func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root.get_child(tree.root.get_child_count() - 1)


func after_each() -> void:
	holder.free()
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


## Writes a scene whose root runs `source` (or has no script when source is "") and returns its path.
func _scene(file_name: String, source: String, root_type: String = "Node") -> String:
	var root: Node = Control.new() if root_type == "Control" else Node.new()
	if source != "":
		var s := GDScript.new()
		s.source_code = source
		assert_eq(s.reload(), OK, "probe script compiles")
		root.set_script(s)
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK, "pack")
	root.free()
	var path := dir.path_join(file_name)
	assert_eq(ResourceSaver.save(packed, path), OK, "save " + path)
	return path


func _installer() -> SubsystemInstaller:
	var i := SubsystemInstaller.new()
	i.log_lines = false
	return i


func test_missing_scenes_are_skipped_and_existing_ones_set_up() -> void:
	var a := _scene("a.tscn", PROBE_SCRIPT)
	var hud := _scene("hud.tscn", UI_PROBE_SCRIPT, "Control")
	var entries := [
		{"name": "Monsters", "scene": a, "parent": SubsystemInstaller.PARENT_SYSTEMS},
		{"name": "Loot", "scene": dir.path_join("missing.tscn"), "parent": SubsystemInstaller.PARENT_SYSTEMS},
		{"name": "HUD", "scene": hud, "parent": SubsystemInstaller.PARENT_UI},
	]
	var rows := _installer().install(ctx, entries)
	assert_eq(rows.size(), 3, "one row per entry")
	assert_eq([rows[0]["status"], rows[1]["status"], rows[2]["status"]],
		[SubsystemInstaller.STATUS_INSTALLED, SubsystemInstaller.STATUS_MISSING, SubsystemInstaller.STATUS_INSTALLED], "statuses")
	var monsters: Node = rows[0]["node"]
	assert_true(monsters != null and monsters.get_parent() == ctx.systems, "a system goes under ctx.systems")
	assert_eq(monsters.name, &"Monsters", "named after its entry")
	assert_true(monsters.get("ctx_seen") == ctx, "setup(ctx) received the context")
	var ui: Node = rows[2]["node"]
	assert_true(ui.get_parent() == ctx.ui_root, "UI goes under ctx.ui_root")
	assert_true(ui.get("ctx_seen") == ctx, "UI setup(ctx)")
	assert_eq(rows[1]["node"], null, "a missing scene adds nothing")
	assert_eq(ctx.systems.get_child_count(), 1, "only the existing system was added")


func test_every_node_is_in_the_tree_before_any_setup() -> void:
	var a := _scene("a.tscn", PROBE_SCRIPT)
	var b := _scene("b.tscn", PROBE_SCRIPT)
	var rows := _installer().install(ctx, [
		{"name": "First", "scene": a, "parent": "systems"},
		{"name": "Second", "scene": b, "parent": "systems"},
	])
	assert_eq(int((rows[0]["node"] as Node).get("siblings_at_setup")), 2, "the first setup already sees its later sibling")


func test_a_root_without_setup_still_runs() -> void:
	var plain := _scene("plain.tscn", "")
	var i := _installer()
	var rows := i.install(ctx, [{"name": "Plain", "scene": plain, "parent": "systems"}])
	assert_eq(rows[0]["status"], SubsystemInstaller.STATUS_NO_SETUP, "no setup(ctx)")
	assert_true(rows[0]["node"] != null and (rows[0]["node"] as Node).is_inside_tree(), "still added")
	assert_eq(i.names_with(SubsystemInstaller.STATUS_NO_SETUP), PackedStringArray(["Plain"]), "names_with")


func test_bad_entries_and_missing_parents_fail_cleanly() -> void:
	var a := _scene("a.tscn", PROBE_SCRIPT)
	var bare := GameContext.new()  # no systems / ui_root nodes
	var i := _installer()
	var rows := i.install(bare, [
		{"name": "", "scene": a, "parent": "systems"},
		{"name": "NoParent", "scene": a, "parent": "systems"},
		{"name": "BadParent", "scene": a, "parent": "elsewhere"},
		"not a dictionary",
	])
	for r in rows:
		assert_eq(r["status"], SubsystemInstaller.STATUS_FAILED, "failed: %s" % r["name"])
		assert_eq(r["node"], null, "nothing added for %s" % r["name"])
	assert_true(i.summary().begins_with("failed 4"), i.summary())


func test_node_of_and_summary() -> void:
	var a := _scene("a.tscn", PROBE_SCRIPT)
	var i := _installer()
	i.install(ctx, [{"name": "A", "scene": a, "parent": "systems"},
		{"name": "Gone", "scene": dir.path_join("x.tscn"), "parent": "ui_root"}])
	assert_true(i.node_of("A") != null, "node_of")
	assert_eq(i.node_of("Gone"), null, "node_of a missing one")
	assert_eq(i.summary(), "installed 1 (A), missing 1 (Gone)", "summary")


func test_the_default_list_is_data() -> void:
	var names: PackedStringArray = []
	for e: Dictionary in SubsystemInstaller.DEFAULT_SUBSYSTEMS:
		assert_true(e.has("name") and e.has("scene") and e.has("parent"), "entry shape %s" % e)
		assert_true(String(e["parent"]) in [SubsystemInstaller.PARENT_SYSTEMS, SubsystemInstaller.PARENT_UI], "parent key")
		names.append(String(e["name"]))
	assert_eq(names, PackedStringArray(["MonsterSystem", "LootSystem", "InteractionSystem", "HUD", "Minimap", "Windows",
		"NpcUI", "DebugUI"]), "the wave-2 subsystems, gameplay systems first")
	var scenes: PackedStringArray = []
	for e: Dictionary in SubsystemInstaller.DEFAULT_SUBSYSTEMS:
		scenes.append(String(e["scene"]))
	assert_has(scenes, "res://scenes/systems/monster_system.tscn", "monster system path")
	assert_has(scenes, "res://scenes/debug/debug_ui.tscn", "debug UI path")
