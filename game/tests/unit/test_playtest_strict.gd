extends TestCase
## The playtest harness's strict no-cheat mode (docs/runtime/PLAYTEST_HARNESS.md "Strict mode"): the Debug
## autoload counts every command it dispatches whoever runs it, a strict report fails on a console or api step taken
## after the strict step and on any violation or ledger mismatch, PlaytestLedger explains every change that went
## through the game's own services (EXP, mesos, items, quests, the level, AP, SP, base stats, skills, HP and MP) and
## flags a direct write, the strict scenarios (and the shared PlaytestKit and quest runner) contain no cheat call
## outside their setup functions, and every harness file (game/tools/playtest/*.gd) contains none outside its counted
## console and api paths and its named exceptions.

const SCENARIO_DIR := "res://tools/playtest/scenarios"
## Beginner skills the ledger tests learn and cast.
const RECOVERY := "0001001"
const NIMBLE := "0001002"
const KIT := "res://tools/playtest/playtest_kit.gd"
## The quest runner the strict scenarios (quest, playthrough) play their quests through: scanned like the kit.
const QUEST_RUNNER := "res://tools/playtest/playtest_quest_runner.gd"
## Calls a strict scenario (or the kit) may never make: teleports, the developer console behind the driver's back,
## and direct writes to the character or its services. The game's own services announce what they change on the
## event bus, so PlaytestLedger cannot tell a service call from play (and it does not follow the player's position at
## all): those calls are refused here.
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
	# GameState and the character's other fields (the ledger reconciles their effect, but a service call is announced).
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
## Every harness file: each .gd directly in this directory (the driver, the kit, the quest runner and plan, the walker
## and its grid navigation, the input injector, the ledger, the report and the quest summary, the runner, the
## child-process runner, the engine log, the scenario base class, and any file added later). Scanned with the same
## FORBIDDEN list, so a helper that teleports or writes AP/HP under a play step fails here, not only at runtime. The
## scenarios are scanned apart (test_strict_scenarios_and_the_kit_make_no_cheat_calls): only the strict ones must be
## console-free.
const HARNESS_DIR := "res://tools/playtest"
## The harness files the scan must at least find (a moved directory must not make it pass on nothing).
const HARNESS_CORE: PackedStringArray = ["playtest_driver.gd", "playtest_kit.gd", "playtest_ledger.gd",
	"playtest_quest_runner.gd", "playtest_report.gd", "playtest_runner.gd", "playtest_walker.gd"]
## The harness's counted console and api paths: {file: {function: [FORBIDDEN entries it may use]}}. Such a call is
## allowed only below a line of the same function that opens a counted step (COUNTED_STEP): the step is logged as
## "api" or "console", so strict mode counts it and the run fails if it happens after the strict step. An entry that
## matches nothing any more is stale and fails the scan (a renamed function must be renamed here too).
const COUNTED_PATHS := {
	"playtest_driver.gd": {
		"new_game": ["start_new_game("],
		"save_game": ["save_now("],
		"console": ["call(\"run\""],
	},
}
## Opening a counted step (PlaytestDriver._begin with an api or console kind).
const COUNTED_STEP: PackedStringArray = ["_begin(PlaytestReport.KIND_API", "_begin(PlaytestReport.KIND_CONSOLE"]
## The harness's other uses of a FORBIDDEN entry, each named with its reason: {file: {function: {entry: reason}}}.
## Allowed anywhere in that function. Like COUNTED_PATHS, an entry that matches nothing any more fails the scan.
const EXCEPTIONS := {
	"playtest_report.gd": {
		"_write_text": {"FileAccess.WRITE": "writes report.json and report.md into the run's --out directory"},
	},
	"playtest_quest_summary.gd": {
		"_write": {"FileAccess.WRITE": "writes the every-quest table (quests.md, quests.json) into its --out directory"},
	},
}


func parity_keys() -> Dictionary:
	return {
		"test_strict_report_fails_on_console_and_api_steps_after_the_strict_step": ["mechanic:no-console-playthrough"],
		"test_ledger_explains_service_changes_and_flags_direct_writes": ["mechanic:no-console-playthrough"],
		"test_ledger_explains_level_ups_ap_sp_skills_and_vitals": ["mechanic:no-console-playthrough"],
		"test_ledger_flags_ap_sp_stats_skills_hp_and_mp_without_an_event": ["mechanic:no-console-playthrough"],
		"test_strict_scenarios_and_the_kit_make_no_cheat_calls": ["mechanic:no-console-playthrough"],
		"test_the_cheat_scan_flags_service_calls_teleports_and_console_outside_setup": ["mechanic:no-console-playthrough"],
		"test_the_harness_makes_no_cheat_call_outside_its_counted_paths": ["mechanic:no-console-playthrough"],
		"test_the_harness_scan_allows_a_listed_call_only_after_its_counted_step": ["mechanic:no-console-playthrough"],
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


## The HP and MP console commands (#39) count as console use like every other command: after the strict step the
## driver refuses them (they never reach Debug, so nothing changes) and the run fails.
func test_a_strict_phase_refuses_the_hp_and_mp_commands() -> void:
	var drv := PlaytestDriver.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(drv)
	var r := PlaytestReport.new()
	r.scenario = "unit"
	r.finished = true
	drv.log_steps = false
	drv.setup(r, 0, "user://_tests/strict_hp_mp")
	var dbg := drv.debug()
	assert_true(dbg != null and dbg.has_command("hp") and dbg.has_command("mp"), "the Debug autoload has hp and mp")
	r.add_check(0, "a", true, "", 0.0, -1)
	drv.begin_strict("unit")
	var ran0 := int(dbg.get("commands_run"))
	for cmd in ["hp 1", "mp 0", "hp max"]:
		assert_eq(str(drv.call("console", cmd)), "", "'%s' is refused (it never runs)" % cmd)
	assert_eq(int(dbg.get("commands_run")), ran0, "no developer command ran")
	var st := r.strict_summary()
	assert_eq(int(st["console_steps"]), 3, "three refused console steps after the strict step")
	assert_eq((st["violations"] as Array).size(), 3, "each one a violation")
	assert_false(r.passed(), "the run fails")
	drv.free()


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


## The level, AP, SP, base stats, skills, HP and MP (#41): every change the game's own paths make is explained by the
## events they announce (a level-up's AP and SP, AP spent, a skill bought, damage, a potion, a natural tick, a chair's
## bonus, a Recovery tick, a skill's MP cost announced after it was paid, a death's respawn vitals, the level-up heal).
func test_ledger_explains_level_ups_ap_sp_skills_and_vitals() -> void:
	var bus: Node = (load("res://scripts/autoload/events.gd") as GDScript).new()
	var c := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	c.inventory.add("270", 3, db())
	c.inventory.add("522", 1, db())
	var g := _game(c, bus)
	var led := PlaytestLedger.new()
	led.baseline(bus, c, db())
	# Two level-ups (their AP, SP, base Max HP/MP and the level-up heal), then AP and SP spent as the windows do.
	g.gain_exp(Progression.exp_to_next(1, db()) + Progression.exp_to_next(2, db()), "unit")
	assert_eq(c.level, 3, "two level-ups")
	assert_true(g.allocate_ap("str") and g.allocate_ap("dex"), "AP spent through GameState")
	for sid in [RECOVERY, NIMBLE]:
		assert_true(bool(SkillBook.learn(c, sid, db()).ok), "SP spent on %s" % sid)
		bus.emit_signal(&"skill_leveled", sid, 1)
		bus.emit_signal(&"stats_changed")
	assert_eq(led.reconcile(c), PackedStringArray(), "level-ups, AP and SP are explained")
	# Damage, a Red Potion, a natural tick and a chair's bonus with the natural tick (one NaturalRecovery step).
	var mx := StatCalculator.max_hp(c, db())
	g.damage_player(mx - 5, "100100")
	var items := ItemService.new(c, db(), bus)
	assert_true(bool(items.use_item("270").ok), "a Red Potion")
	var tick := NaturalRecoveryRule.from_db(db()).hp_per_tick
	g.change_hp(tick)
	bus.emit_signal(&"player_sat_down", "522")
	g.change_hp(tick + int(Chairs.bonus("522", db())["hp"]))
	bus.emit_signal(&"player_stood_up", "move")
	# Recovery: its MP is paid, then skill_used; its heal ticks (the last one after the effect has ended).
	var rec := SkillDef.of(RECOVERY, db())
	g.change_mp(-rec.mp_cost(1))
	EffectBook.add(c, PlayerSkills.effect_id(RECOVERY), "skill:" + RECOVERY, rec.duration_s(1), {"skill_id": RECOVERY,
		"level": 1, "hp_total": rec.hp_total(1), "duration_s": rec.duration_s(1), "tick_s": SkillRules.of(db()).recovery_tick_s,
		"ticks_done": 0})
	bus.emit_signal(&"skill_used", RECOVERY, 1)
	g.damage_player(rec.hp_total(1) + 5, "100100")
	var healed := 0
	for i in 600:
		var r := EffectBook.tick(c, 0.1)
		if int(r.heal) > 0:
			healed += g.change_hp(int(r.heal))
		if not (r.expired as Array).is_empty():
			bus.emit_signal(&"effects_changed")
	assert_eq(healed, rec.hp_total(1), "Recovery healed its total")
	assert_eq(led.reconcile(c), PackedStringArray(), "damage, a potion, recovery ticks and a skill's MP are explained")
	# A death: the killing blow, the death's respawn vitals (set silently at the death), then their announcement.
	g.damage_player(c.hp + 100, "100100")
	bus.emit_signal(&"player_died", "000001000")
	var death := DeathRules.from_db(db()).apply(c)
	bus.emit_signal(&"exp_gained", -int(death.get("exp_lost", 0)), "death")
	assert_eq(led.reconcile(c), PackedStringArray(), "while the death is pending, the respawn vitals are expected")
	bus.emit_signal(&"hp_changed", c.hp, StatCalculator.max_hp(c, db()))
	bus.emit_signal(&"mp_changed", c.mp, StatCalculator.max_mp(c, db()))
	assert_eq(led.reconcile(c), PackedStringArray(), "a death and its respawn are explained")
	for cause in ["damage", "item", "recovery tick", "level-up", "skill cost", "respawn"]:
		assert_true(int(led.vital_steps.get(cause, 0)) > 0, "a '%s' step: %s" % [cause, led.vital_steps])
	led.disarm()
	g.free()
	bus.free()


## A change of the level, AP, SP, a base stat, a skill level, base Max HP/MP, HP or MP with no event behind it is a
## mismatch (#41), and so is an announced HP or MP step that nothing explains.
func test_ledger_flags_ap_sp_stats_skills_hp_and_mp_without_an_event() -> void:
	var bus: Node = (load("res://scripts/autoload/events.gd") as GDScript).new()
	var c := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	var g := _game(c, bus)
	var led := PlaytestLedger.new()
	# {case: the mismatch it must produce}; _cheat() makes the change.
	var cases := {
		"AP written": "AP changed by +1",
		"a base stat written": "the base stats by +1",
		"AP moved into a stat behind the bus": "after the last stats_changed",
		"a base stat lowered": "base DEX fell",
		"SP written": "SP changed by +1",
		"a skill level written": "skill %s went level 0 -> 1" % NIMBLE,
		"a level written": "level went 1 -> 2",
		"base Max HP written": "base Max HP changed by +10",
		"HP written": "HP is 45, the bus last announced 50",
		"MP written": "MP is 4, the bus last announced 5",
		"an HP loss announced with no damage": "HP went 50 -> 45",
		"an HP gain that is no recovery tick": "HP went 20 -> 27",
		"an MP drop no skill paid": "no skill_used paid it",
		"AP announced by a stats_changed but granted by nothing": "AP changed by +5",
	}
	var fresh := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	for case: String in cases:
		_copy_character(fresh, c)
		led.baseline(bus, c, db())
		assert_eq(led.reconcile(c), PackedStringArray(), "%s: clean before" % case)
		_cheat(case, c, g, bus)
		var mm := led.reconcile(c)
		assert_true(Array(mm).any(func(m: String) -> bool: return m.contains(String(cases[case]))),
			"%s is a mismatch (wants '%s'): %s" % [case, cases[case], mm])
	_copy_character(fresh, c)
	# The same heal as a recovery tick, and an MP drop the cast that follows pays, are not.
	led.baseline(bus, c, db())
	g.damage_player(30, "100100")
	g.change_hp(NaturalRecoveryRule.from_db(db()).hp_per_tick)
	assert_eq(led.reconcile(c), PackedStringArray(), "a natural tick after damage")
	c.skills[NIMBLE] = 1
	led.baseline(bus, c, db())
	g.change_mp(-SkillDef.of(NIMBLE, db()).mp_cost(1))
	bus.emit_signal(&"skill_used", NIMBLE, 1)
	assert_eq(led.reconcile(c), PackedStringArray(), "an MP drop paid by the skill_used right after it")
	led.disarm()
	g.free()
	bus.free()


## One change of test_ledger_flags_ap_sp_stats_skills_hp_and_mp_without_an_event, made the way a cheat would.
func _cheat(case: String, c: CharacterState, g: GameState, bus: Node) -> void:
	match case:
		"AP written":
			c.ap += 1
		"a base stat written":
			c.base_stats["str"] = c.get_base_stat("str") + 1
		"AP moved into a stat behind the bus":
			c.ap -= 1
			c.base_stats["luk"] = c.get_base_stat("luk") + 1
		"a base stat lowered":
			c.base_stats["dex"] = c.get_base_stat("dex") - 1
		"SP written":
			c.sp += 1
		"a skill level written":
			c.skills[NIMBLE] = 1
		"a level written":
			c.level += 1
		"base Max HP written":
			c.base_max_hp += 10
		"HP written":
			c.hp -= 5
		"MP written":
			c.mp -= 1
		"an HP loss announced with no damage":
			g.change_hp(-5)
		"an HP gain that is no recovery tick":
			g.damage_player(30, "100100")
			g.change_hp(7)
		"an MP drop no skill paid":
			g.change_mp(-1)
		"AP announced by a stats_changed but granted by nothing":
			c.ap += 5
			bus.emit_signal(&"stats_changed")


## A GameState on a private bus for `c` (not in the tree: no autosave, no quests).
func _game(c: CharacterState, bus: Node) -> GameState:
	var g := GameState.new()
	g.db = db()
	g.event_bus = bus
	g.log_warnings = false
	g.character = c
	return g


## Puts `c` back to the fresh character `src` (a new baseline per case).
func _copy_character(src: CharacterState, c: CharacterState) -> void:
	c.level = src.level
	c.exp = src.exp
	c.ap = src.ap
	c.sp = src.sp
	c.hp = src.hp
	c.mp = src.mp
	c.base_max_hp = src.base_max_hp
	c.base_max_mp = src.base_max_mp
	c.base_stats = src.base_stats.duplicate()
	c.skills = {}


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


func test_the_harness_makes_no_cheat_call_outside_its_counted_paths() -> void:
	var used := {}
	var files := harness_files()
	for core in HARNESS_CORE:
		assert_true(files.has(HARNESS_DIR.path_join(core)), "the scan covers %s: %s" % [core, files])
	for path in files:
		var file := path.get_file()
		var r := harness_cheat_calls(FileAccess.get_file_as_string(path), file, COUNTED_PATHS.get(file, {}),
			EXCEPTIONS.get(file, {}))
		for v in r["findings"]:
			assert_true(false, v)
		for k in r["used"]:
			used["%s|%s" % [file, k]] = true
	for file in COUNTED_PATHS:
		for fn in COUNTED_PATHS[file]:
			for bad in COUNTED_PATHS[file][fn]:
				assert_true(used.has("%s|%s|%s" % [file, fn, bad]),
					"COUNTED_PATHS %s %s() %s matches nothing any more: stale (renamed? update the whitelist)" % [file, fn, bad])
	for file in EXCEPTIONS:
		for fn in EXCEPTIONS[file]:
			for bad in EXCEPTIONS[file][fn]:
				assert_true(used.has("%s|%s|%s" % [file, fn, bad]),
					"EXCEPTIONS %s %s() %s matches nothing any more: stale (renamed? update the list)" % [file, fn, bad])


## Every .gd file directly in HARNESS_DIR (res:// paths, sorted).
static func harness_files() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(HARNESS_DIR):
		if f.ends_with(".gd"):
			out.append(HARNESS_DIR.path_join(f))
	out.sort()
	return out


func test_the_harness_scan_allows_a_listed_call_only_after_its_counted_step() -> void:
	# The scan itself must be able to fail: a synthetic driver.
	var src := "\n".join(PackedStringArray([
		"func save_game() -> Dictionary:",
		"\tvar err := main.save_now()",
		"\tvar j := _begin(PlaytestReport.KIND_API, \"MainShell.save_now\")",
		"\terr = main.save_now()",
		"func walk_to(p: Vector3) -> void:",
		"\tmain.save_now()",
		"\tplayer().global_position = p",
		"func console(cmd: String) -> String:",
		"\tvar i := _begin(PlaytestReport.KIND_CONSOLE, \"console\", cmd)",
		"\treturn str(dbg.call(\"run\", cmd))",
		"func helper() -> void:",
		"\tawait console(\"level 10\")",
		"\t# main.save_now() in a comment is not a call",
		"func _write_text(path: String) -> void:",
		"\tvar f := FileAccess.open(path, FileAccess.WRITE)",
		"func dump(path: String) -> void:",
		"\tvar f := FileAccess.open(path, FileAccess.WRITE)",
	]))
	var counted := {"save_game": ["save_now("], "console": ["call(\"run\""]}
	var excepted := {"_write_text": {"FileAccess.WRITE": "the report writer"}}
	var r := harness_cheat_calls(src, "synthetic_driver.gd", counted, excepted)
	var v: PackedStringArray = r["findings"]
	assert_eq(v.size(), 5, "the call before the counted step, the unlisted function's call, the teleport, the console call and the unnamed write: %s" % v)
	assert_true(Array(v).any(func(x: String) -> bool: return x.contains(":17 (dump)") and x.contains("FileAccess.WRITE")), "line 17: %s" % v)
	assert_true((r["used"] as Dictionary).has("_write_text|FileAccess.WRITE"), "the named exception: %s" % r["used"])
	assert_true(Array(v).any(func(x: String) -> bool: return x.contains(":2 ") and x.contains("before its counted step")), "line 2: %s" % v)
	assert_true(Array(v).any(func(x: String) -> bool: return x.contains(":6 (walk_to)") and x.contains("save_now(")), "line 6: %s" % v)
	assert_true(Array(v).any(func(x: String) -> bool: return x.contains(":7 (walk_to)") and x.contains("global_position = ")), "line 7: %s" % v)
	assert_true(Array(v).any(func(x: String) -> bool: return x.contains(":12") and x.contains("console() outside")), "line 12: %s" % v)
	assert_eq((r["used"] as Dictionary).keys().size(), 3, "both listed paths after their counted step and the exception: %s" % r["used"])


## The cheat calls in a harness file: the cheat_calls() rules, except that a FORBIDDEN entry `counted` lists for the
## enclosing function ({function: [entries]}, COUNTED_PATHS) is allowed below a line of that function that opens a
## counted step (COUNTED_STEP), and an entry `excepted` names for the enclosing function ({function: {entry: reason}},
## EXCEPTIONS) is allowed anywhere in it. Returns {"findings": PackedStringArray, "used": {"<function>|<entry>": true}}.
static func harness_cheat_calls(text: String, file: String, counted: Dictionary, excepted: Dictionary = {}) -> Dictionary:
	var out := PackedStringArray()
	var used := {}
	var fn := ""
	var opened := false
	var n := 0
	for line in text.split("\n"):
		n += 1
		var t := line.strip_edges()
		if t.begins_with("func ") or t.begins_with("static func "):
			fn = t.get_slice("(", 0).get_slice(" ", t.get_slice("(", 0).get_slice_count(" ") - 1)
			opened = false
		if t.begins_with("#") or Array(ALLOWED).any(func(a: String) -> bool: return t.contains(a)):
			continue
		if Array(COUNTED_STEP).any(func(s: String) -> bool: return t.contains(s)):
			opened = true
		for bad in FORBIDDEN:
			if not t.contains(bad):
				continue
			var listed := Array(counted.get(fn, [])).has(bad)
			if (excepted.get(fn, {}) as Dictionary).has(bad) or (listed and opened):
				used["%s|%s" % [fn, bad]] = true
			elif listed:
				out.append("%s:%d (%s) calls %s before its counted step (a COUNTED_STEP line): %s" % [file, n, fn, bad, t])
			else:
				out.append("%s:%d (%s) calls %s: %s" % [file, n, fn, bad, t])
		if t.contains("console(") and not t.contains("func console(") and not fn.begins_with("_setup"):
			out.append("%s:%d: console() outside a _setup function (%s): %s" % [file, n, fn, t])
	return {"findings": out, "used": used}


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
