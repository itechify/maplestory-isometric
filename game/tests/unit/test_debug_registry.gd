extends TestCase
## The Debug registry (scripts/autoload/debug_tools.gd) on private instances: the fixed contract (register_command,
## run), argument types, quoting, ";" chains, aliases resolved at run time, composite commands that keep another
## system's registration as their fallback, help, history and suggestions.

var dbg: DebugTools = null
var got: Array = []


func before_each() -> void:
	dbg = DebugTools.new()
	got = []


func after_each() -> void:
	dbg.free()


func _record(args: Variant) -> String:
	got.append(args)
	return "ok %d" % (args as PackedStringArray).size()


func test_register_and_run_pass_a_packed_string_array() -> void:
	dbg.register_command("echo", "echo <words>: repeat", _record)
	assert_eq(dbg.run("echo a b c"), "ok 3", "output")
	assert_eq(typeof(got[0]), TYPE_PACKED_STRING_ARRAY, "handlers get a PackedStringArray (other systems type it so)")
	assert_eq(Array(got[0]), ["a", "b", "c"], "arguments")
	assert_eq(dbg.run("   "), "", "blank line prints nothing")
	assert_eq(dbg.run("ECHO x"), "ok 1", "command names are case-insensitive")


func test_unknown_command_keeps_the_stub_prefix_and_suggests() -> void:
	dbg.register_command("warp", "warp <map>", _record)
	var out := dbg.run("wrap 40")
	assert_true(out.begins_with("unknown command: wrap"), out)
	assert_true(out.contains("warp"), "suggests the close command: " + out)


func test_quotes_group_words_and_semicolons_chain() -> void:
	dbg.register_command("echo", "", _record)
	dbg.run("echo \"Red Potion\" 5")
	assert_eq(Array(got[0]), ["Red Potion", "5"], "quoted words")
	assert_eq(Array(DebugTools.tokenize("say \\\"hi\\\"")), ["say", "\"hi\""], "escaped quote")
	got.clear()
	var out := dbg.run("echo a; echo b c ;; echo \"x;y\"")
	assert_eq(got.size(), 3, "three commands")
	assert_eq(Array(got[2]), ["x;y"], "a quoted ';' does not split")
	assert_eq(out, "ok 1\nok 2\nok 1", "outputs joined")


func test_aliases_resolve_at_run_time() -> void:
	dbg.register_alias("reset", "reset_save")
	assert_eq(dbg.run("reset"), "unknown command: reset (an alias of reset_save, which is not registered yet)",
		"target missing: names the alias and its target")
	dbg.register_command("reset_save", "reset_save [slot]", _record)
	assert_eq(dbg.run("reset slot2"), "ok 1", "alias reaches the target registered later")
	assert_eq(Array(got[0]), ["slot2"], "arguments pass through")
	dbg.register_alias("rs", "reset_save", PackedStringArray(["slot9"]))
	dbg.run("rs")
	assert_eq(Array(got[1]), ["slot9"], "prefix arguments")
	assert_eq(dbg.resolve_name("reset"), "reset_save", "resolve_name")
	assert_true(dbg.has_command("reset"), "has_command follows aliases")


func test_composite_keeps_earlier_and_later_registrations_as_fallback() -> void:
	dbg.register_command("quest", "quest <id>: status (registered first)", func(a: PackedStringArray) -> String: return "status-1 " + a[0])
	dbg.register_composite("quest", "quest accept|...", func(a: PackedStringArray) -> String:
		return "dispatch " + str(dbg.shadowed_handler("quest").call(a)))
	assert_eq(dbg.run("quest 1006"), "dispatch status-1 1006", "earlier registration became the fallback")
	dbg.register_command("quest", "quest <id>: status (registered later)", func(a: PackedStringArray) -> String: return "status-2 " + a[0])
	assert_eq(dbg.run("quest 7"), "dispatch status-2 7", "a later registration replaces the fallback, not the dispatcher")
	assert_true(dbg.shadowed_help("quest").contains("registered later"), "fallback help")


func test_handler_owner_freed_is_reported() -> void:
	var n := Node.new()
	dbg.register_command("gone", "", Callable(n, "get_name"))
	n.free()
	assert_true(dbg.run("gone").contains("owner is gone"), "freed owner")
	dbg.register_command("bad", "", func(_a: PackedStringArray) -> Variant: return null)
	assert_true(dbg.run("bad").contains("no result"), "null result")


func test_command_owner_finds_the_registering_object() -> void:
	var holder := Node.new()
	dbg.register_command("q", "", Callable(holder, "get_name"))
	assert_eq(dbg.command_owner("q"), holder, "owner")
	assert_eq(dbg.command_owner("missing"), null, "missing")
	holder.free()


func test_history_collapses_repeats_and_is_bounded() -> void:
	for i in DebugTools.MAX_HISTORY + 20:
		dbg.add_history("cmd %d" % i)
	dbg.add_history("cmd %d" % (DebugTools.MAX_HISTORY + 19))
	dbg.add_history("  ")
	assert_eq(dbg.history.size(), DebugTools.MAX_HISTORY, "bounded, no duplicate, no blank")
	assert_eq(dbg.history[dbg.history.size() - 1], "cmd %d" % (DebugTools.MAX_HISTORY + 19), "newest last")


func test_help_lists_every_registered_command_with_its_help() -> void:
	dbg.install_builtins()
	dbg.register_command("map_warp", "map_warp <map_id> [portal]: registered by MapSession", _record)
	var out := dbg.run("help")
	for n in dbg.command_names():
		assert_true(out.contains("\n  " + n), "help lists %s" % n)
	assert_true(out.contains("registered by MapSession"), "other systems' help text")
	assert_true(out.contains("reset -> reset_save"), "aliases listed")
	var one := dbg.run("help warp")
	assert_true(one.begins_with("warp <map> [portal]"), one)
	assert_true(dbg.run("help reset").contains("alias of reset_save"), "alias help")
	assert_true(dbg.run("help nope").begins_with("unknown command"), "unknown")
	for c in ["warp", "portals", "where", "showmap", "coords", "collision", "spawns", "portaldata", "spawn", "kill",
			"exp", "level", "mesos", "give", "clearinv", "quest", "reload", "heal", "god", "linkmode", "timescale",
			"screenshot", "seed", "help"]:
		assert_true(dbg.has_command(c), "brief command %s registered" % c)
	assert_eq(dbg.resolve_name("reset"), "reset_save", "reset is an alias of the save system's reset_save")


func test_quest_service_commands_still_work_on_a_bare_instance() -> void:
	# The quest system's own test pattern: a bare debug_tools.gd instance with QuestService's commands only.
	var c := CharacterState.new()
	var svc := QuestService.create(null, db(), c)
	svc.register_debug_commands(dbg)
	assert_true(dbg.run("quest_accept 1006").contains("accepted"), "accept")
	assert_true(dbg.run("quest 1006").contains("monster_kills:2 0/10"), "status")
	assert_eq(dbg.run("quest_complete 1006 force"), "completed", "exact output kept")
