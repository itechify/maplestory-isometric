extends TestCase
## The playtest harness's strict no-cheat mode (docs/runtime/PLAYTEST_HARNESS.md "Strict mode"): the Debug
## autoload counts every command it dispatches whoever runs it, a strict report fails on a console or api step taken
## after the strict step and on any violation or ledger mismatch, PlaytestLedger explains every change that went
## through the game's own services and flags a direct write, and the strict scenarios (and the shared PlaytestKit)
## contain no cheat call outside their setup functions.

const SCENARIO_DIR := "res://tools/playtest/scenarios"
const KIT := "res://tools/playtest/playtest_kit.gd"
## Calls a strict scenario (or the kit) may never make: teleports, the developer console behind the driver's back,
## and direct writes to the character or its services.
const FORBIDDEN: PackedStringArray = ["place_player", "Debug.run", "debug().call", "call(\"run\"", "call_command(",
	"ItemService.new(", ".inventory.add(", ".inventory.remove(", ".quests.start(", ".quests.complete(",
	"start_new_game(", "Progression.gain_exp", "Progression.allocate_ap", ".mesos +=", ".mesos -=", ".mesos = ",
	".exp += ", ".exp = ", ".level = ", ".hp = ", "gain_exp(", "force_equip("]


func parity_keys() -> Dictionary:
	return {
		"test_strict_report_fails_on_console_and_api_steps_after_the_strict_step": ["mechanic:no-console-playthrough"],
		"test_ledger_explains_service_changes_and_flags_direct_writes": ["mechanic:no-console-playthrough"],
		"test_strict_scenarios_and_the_kit_make_no_cheat_calls": ["mechanic:no-console-playthrough"],
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
	var files := PackedStringArray([KIT])
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
		var fn := ""
		var n := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			var t := line.strip_edges()
			if t.begins_with("func ") or t.begins_with("static func "):
				fn = t.get_slice("(", 0).get_slice(" ", t.get_slice("(", 0).get_slice_count(" ") - 1)
			if t.begins_with("#"):
				continue
			for bad in FORBIDDEN:
				assert_false(t.contains(bad), "%s:%d (%s) calls %s: %s" % [path.get_file(), n, fn, bad, t])
			if t.contains("console(") and not t.contains("func console("):
				assert_true(fn.begins_with("_setup"), "%s:%d: console() outside a _setup function (%s): %s" % [
					path.get_file(), n, fn, t])
