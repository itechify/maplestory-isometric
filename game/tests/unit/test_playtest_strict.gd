extends TestCase
## The playtest harness's strict no-cheat mode (docs/runtime/PLAYTEST_HARNESS.md "Strict mode"): the Debug
## autoload counts every command it dispatches whoever runs it, a strict report fails on a console or api step taken
## after the strict step and on any violation or ledger mismatch, PlaytestLedger explains every change that went
## through the game's own services and flags a direct write, and the strict scenarios (and the shared PlaytestKit)
## contain no cheat call outside their setup functions.

const SCENARIO_DIR := "res://tools/playtest/scenarios"
const KIT := "res://tools/playtest/playtest_kit.gd"
## The quest runner the strict scenarios (quest, playthrough) play their quests through: scanned like the kit.
const QUEST_RUNNER := "res://tools/playtest/playtest_quest_runner.gd"
## Calls a strict scenario (or the kit) may never make: teleports, the developer console behind the driver's back,
## and direct writes to the character or its services. The game's own services announce what they change on the
## event bus, so PlaytestLedger cannot tell a service call from play (and it does not cover AP, SP, stats, HP, skills
## or position at all): those calls are refused here.
const FORBIDDEN: PackedStringArray = ["place_player", "Debug.run", "debug().call", "call(\"run\"", "call_command(",
	"ItemService.new(", ".inventory.add(", ".inventory.remove(", ".quests.start(", ".quests.complete(",
	"start_new_game(", "Progression.gain_exp", "Progression.allocate_ap", ".mesos +=", ".mesos -=", ".mesos = ",
	".exp += ", ".exp = ", ".level = ", ".hp = ", "gain_exp(", "force_equip(",
	# ItemService and QuestService (d.game().items / .quests): announced on the bus, so only this scan catches them.
	".items.gain", ".items.lose", ".items.clear_inventory(", ".items.move(", ".items.pickup(", ".items.use_item(",
	".items.equip(", ".items.unequip(", ".items.spend_mesos(", ".quests.accept(", ".quests.forfeit(",
	"engine.accept(", "engine.complete(", "engine.forfeit(", "engine.on_",
	# QuestLog, Inventory and Equipment writes.
	".quests.add_kills(", ".quests.add_uses(", ".quests.mark_talked(", ".quests.mark_visited(", ".quests.set_other(",
	".inventory.remove_at(", ".inventory.put_at(", ".inventory.clear(", ".inventory.add_instance(", ".inventory.move(",
	".inventory.swap(", ".inventory.set_capacity(", ".equipment.equip(", ".equipment.unequip(",
	# GameState and the character's other fields (the ledger does not reconcile them).
	"().allocate_ap(", "Game.allocate_ap(", "change_hp(", "change_mp(", "damage_player(", "apply_level_up",
	"apply_death_penalty", ".ap = ", ".ap += ", ".ap -= ", ".sp = ", ".sp += ", ".sp -= ", ".hp += ", ".hp -= ",
	".mp = ", ".mp += ", ".level += ", "set_base_stat(", ".base_stats[", ".skills[", ".cooldowns[", ".effects.append(",
	".quickslots[",
	# Moving the player or the map behind the walker, and hits or kills that no attack made.
	"global_position = ", "global_transform = ", "teleport(", "request_portal(", "debug_warp(", "enter_from_location(",
	"receive_hit(", "land_hit(", "report_monster_killed", "\"die\"",
	# The save on disk between phases.
	"FileAccess.WRITE", "save_now(", "SaveService."]
## Lines a FORBIDDEN entry matches that are not a cheat (a synthetic input event's own position).
const ALLOWED: PackedStringArray = ["ev.global_position = ev.position"]


func parity_keys() -> Dictionary:
	return {
		"test_strict_report_fails_on_console_and_api_steps_after_the_strict_step": ["mechanic:no-console-playthrough"],
		"test_ledger_explains_service_changes_and_flags_direct_writes": ["mechanic:no-console-playthrough"],
		"test_strict_scenarios_and_the_kit_make_no_cheat_calls": ["mechanic:no-console-playthrough"],
		"test_the_cheat_scan_flags_service_calls_teleports_and_console_outside_setup": ["mechanic:no-console-playthrough"],
	}


func test_debug_tools_counts_every_dispatched_command() -> void:
	var dbg := DebugTools.new()
	dbg.register_command("echo", "echo <words>: repeat", func(args: PackedStringArray) -> String: return " ".join(args))
	assert_eq(dbg.commands_run, 0, "a fresh instance has run nothing")
	dbg.run("echo a; echo b")
	assert_eq(dbg.commands_run, 2, "run() counts each command of a ';' chain")
	dbg.call_command("echo", PackedStringArray(["c"]))
	assert_eq(dbg.commands_run, 3, "call_command() counts too")
	dbg.run("no_such_command")
	assert_eq(dbg.commands_run, 4, "an unknown command was still dispatched")
	dbg.run("   ")
	assert_eq(dbg.commands_run, 4, "a blank line runs nothing")
	dbg.free()


func test_strict_report_fails_on_console_and_api_steps_after_the_strict_step() -> void:
	var r := PlaytestReport.new()
	r.scenario = "unit"
	r.finished = true
	r.add_check(0, "a", true, "", 0.0, -1)
	# Setup before the strict step: a console step does not count against it.
	r.begin_step(0, PlaytestReport.KIND_CONSOLE, "console", "level 5", 0.0, 0)
	assert_false(bool(r.strict_summary()["enabled"]), "no strict block until begin_strict")
	assert_true(r.passed(), "without strict mode a console step is setup")
	r.strict = {"enabled": true, "reason": "unit", "since": {"phase": 0, "step": r.steps.size(), "game_s": 0.0},
		"debug_commands": 0, "ledger": {"reconciled": 1, "heard": 3, "mismatches": []}, "violations": []}
	r.begin_step(0, PlaytestReport.KIND_PLAY, "talk_to", "3", 1.0, 0)
	var st := r.strict_summary()
	assert_true(bool(st["ok"]), "play steps only: %s" % st)
	assert_eq(int(st["console_steps"]), 0, "the setup console step is before the strict step")
	assert_true(r.passed(), "a clean strict run passes")
	r.begin_step(0, PlaytestReport.KIND_CONSOLE, "console", "warp 000000040", 2.0, 0)
	assert_false(r.passed(), "a console step after the strict step fails the run")
	assert_eq(int(r.strict_summary()["console_steps"]), 1)
	var r2 := PlaytestReport.from_dict(r.to_dict())
	assert_true(bool(r2.strict.get("enabled", false)), "the strict block survives the report round trip (phases)")
	assert_false(r2.strict_ok(), "and so does the verdict")
	var r3 := PlaytestReport.new()
	r3.finished = true
	r3.add_check(0, "a", true, "", 0.0, -1)
	r3.strict = {"enabled": true, "since": {"step": 0}, "ledger": {"mismatches": ["mesos changed by +10"]}}
	assert_false(r3.passed(), "a ledger mismatch fails the run")
	r3.strict["ledger"] = {"mismatches": []}
	r3.add_violation(0, "api", "new_game: the Start button did not respond")
	assert_false(r3.passed(), "a violation fails the run")
	r3.strict["violations"] = []
	r3.strict["debug_commands"] = 1
	assert_false(r3.passed(), "a developer command fails the run")
	r3.strict["debug_commands"] = 0
	assert_true(r3.passed(), "nothing left")
	r3.begin_step(0, PlaytestReport.KIND_API, "MainShell.save_now", "", 0.0, 0)
	assert_false(r3.passed(), "an api step fails the run")
	assert_true(r3.to_markdown().contains("VIOLATED"), "report.md says so")


func test_ledger_explains_service_changes_and_flags_direct_writes() -> void:
	var bus: Node = (load("res://scripts/autoload/events.gd") as GDScript).new()
	var c := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	var led := PlaytestLedger.new()
	led.baseline(bus, c, db())
	assert_true(led.armed, "armed on a character")
	var items := ItemService.new(c, db(), bus)
	items.gain("270", 3)
	items.lose("270", 1)
	items.gain_mesos(50)
	items.spend_mesos(20)
	var eq := c.equipment.equipped()
	assert_false(eq.is_empty(), "the creation weapon is equipped")
	var slot := String(eq.keys()[0])
	c.equipment.unequip(c, slot, db())
	assert_eq(led.reconcile(c), PackedStringArray(), "pickups, spending and unequipping are all explained")
	c.mesos += 10
	var mm := led.reconcile(c)
	assert_eq(mm.size(), 1, "a direct meso write: %s" % mm)
	assert_true(mm[0].begins_with("mesos changed by +40"), mm[0] if not mm.is_empty() else "")
	c.mesos -= 10
	c.inventory.add("237", 2, db())
	mm = led.reconcile(c)
	assert_true(mm.size() == 1 and mm[0].contains("item 237"), "an item added behind the bus: %s" % mm)
	bus.emit_signal(&"item_gained", "237", 2)
	assert_eq(led.reconcile(c), PackedStringArray(), "the same change announced")
	c.quests.start("1006", 0.0)
	mm = led.reconcile(c)
	assert_true(mm.size() == 1 and mm[0].contains("quest 1006"), "a quest started behind the bus: %s" % mm)
	bus.emit_signal(&"quest_started", "1006")
	assert_eq(led.reconcile(c), PackedStringArray(), "announced")
	c.exp += 5
	mm = led.reconcile(c)
	assert_true(mm.size() == 1 and mm[0].begins_with("EXP changed by +5"), "an EXP write: %s" % mm)
	bus.emit_signal(&"exp_gained", 5, "unit")
	assert_eq(led.reconcile(c), PackedStringArray(), "announced")
	# gain, lose, gain_mesos, spend_mesos, and the three announced by hand (unequipping announces nothing).
	assert_eq(led.heard, 7, "the events it heard")
	led.disarm()
	assert_false(bus.is_connected(&"exp_gained", led._on_exp), "disarm disconnects")
	bus.free()


func test_strict_scenarios_and_the_kit_make_no_cheat_calls() -> void:
	var files := PackedStringArray([KIT, QUEST_RUNNER])
	var strict_n := 0
	for f in DirAccess.get_files_at(SCENARIO_DIR):
		if not f.ends_with(".gd"):
			continue
		var path := SCENARIO_DIR.path_join(f)
		if FileAccess.get_file_as_string(path).contains("begin_strict("):
			files.append(path)
			strict_n += 1
	assert_true(strict_n >= 1, "at least one strict scenario (quest.gd)")
	for path in files:
		for v in cheat_calls(FileAccess.get_file_as_string(path), path.get_file()):
			assert_true(false, v)


func test_the_cheat_scan_flags_service_calls_teleports_and_console_outside_setup() -> void:
	# The scan itself must be able to fail: a synthetic strict scenario with one cheat per line.
	var src := "\n".join(PackedStringArray([
		"func _setup_world() -> void:",
		"\tawait d.console(\"warp 000000040\")",
		"func run(d) -> void:",
		"\td.game().items.gain(\"349\", 10)",
		"\td.game().quests.accept(\"1006\")",
		"\td.game().allocate_ap(\"str\")",
		"\td.player().global_position = Vector3.ZERO",
		"\tc.ap = 99",
		"\tawait d.console(\"level 10\")",
		"\t# d.game().items.gain(\"349\", 10) in a comment is not a call",
		"\tev.global_position = ev.position",
	]))
	var v := cheat_calls(src, "synthetic.gd")
	assert_eq(v.size(), 6, "one finding per cheat line (the setup console, the comment and the input event are fine): %s" % v)
	for want in [".items.gain", ".quests.accept(", "().allocate_ap(", "global_position = ", ".ap = ", "console() outside"]:
		assert_true(Array(v).any(func(x: String) -> bool: return x.contains(want)), "flags %s: %s" % [want, v])
	assert_eq(cheat_calls("func _setup_x() -> void:\n\tawait d.console(\"give 270 5\")", "ok.gd"), PackedStringArray(),
		"console() inside a _setup function is setup")


## The cheat calls in the source of a strict scenario: one line per FORBIDDEN match outside comments and ALLOWED
## lines, and one per console() call outside a function named _setup*.
static func cheat_calls(text: String, file: String) -> PackedStringArray:
	var out := PackedStringArray()
	var fn := ""
	var n := 0
	for line in text.split("\n"):
		n += 1
		var t := line.strip_edges()
		if t.begins_with("func ") or t.begins_with("static func "):
			fn = t.get_slice("(", 0).get_slice(" ", t.get_slice("(", 0).get_slice_count(" ") - 1)
		if t.begins_with("#") or Array(ALLOWED).any(func(a: String) -> bool: return t.contains(a)):
			continue
		for bad in FORBIDDEN:
			if t.contains(bad):
				out.append("%s:%d (%s) calls %s: %s" % [file, n, fn, bad, t])
		if t.contains("console(") and not t.contains("func console(") and not fn.begins_with("_setup"):
			out.append("%s:%d: console() outside a _setup function (%s): %s" % [file, n, fn, t])
	return out
