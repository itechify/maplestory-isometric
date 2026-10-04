extends Node
## One process (phase) of a playtest run: res://tools/playtest/playtest_runner.tscn (docs/runtime/PLAYTEST_HARNESS.md).
## scripts/playtest.sh and PlaytestProcess start it; it is not meant to be started by hand, but it can be:
##
##   godot --headless --fixed-fps 60 --path <copy> res://tools/playtest/playtest_runner.tscn -- \
##       --scenario smoke --out <abs dir> [--seed 1] [--max-s 600] [--max-wall-s 1800] [--continue-run]
##
## It loads game/tools/playtest/scenarios/<scenario>.gd (a PlaytestScenario), boots the real main scene through a
## PlaytestDriver with saves in <out>/saves, seeds Game.rng (and MapSession's instance RNG), attaches a
## ScriptErrorGuard (GDScript runtime errors fail the run) and a PlaytestEngineLog (push_error and engine errors are
## reported, not fatal), runs the scenario, writes <out>/report.json and <out>/report.md and quits: exit 0 when the
## report passes, 1 otherwise.
##
## Phases: without --continue-run the run starts fresh (the old report, saves and shots in <out> are removed). When
## the scenario calls reload_process(), this process writes the report with "reload_requested": true and ends through
## the game's own Quit Game; the caller starts the next process with --continue-run, which reads that report,
## appends to it and calls the scenario's run() again with phase + 1.
##
## Watchdog: past the scenario's max_seconds() of game time (or --max-s), or --max-wall-s of wall time, the run stops
## with a "timeout" error and the report is still written (a coroutine waiting forever cannot hang the process).

const SCENARIO_DIR := "res://tools/playtest/scenarios"
const DEFAULT_SEED := 1
const MAX_PHASES := 8
## Exit code when the process has to end itself after a reload request the game did not complete.
const RELOAD_EXIT_CODE := 75
## The largest default wall-time budget (s): below scripts/playtest.sh's outer timeout (3600 s by default).
const DEFAULT_MAX_WALL_S := 3300.0

var scenario_name: String = ""
var out_dir: String = ""
var seed_value: int = DEFAULT_SEED
var continue_run: bool = false
var max_game_s: float = -1.0
var max_wall_s: float = -1.0

var report: PlaytestReport = null
var driver: PlaytestDriver = null
var scenario: PlaytestScenario = null
var guard: ScriptErrorGuard = null
var engine_log: PlaytestEngineLog = null
var phase: int = 0

var _done: bool = false
var _f0: int = 0
var _wall0: int = 0
var _quit_at_ms: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_wall0 = Time.get_ticks_msec()
	_f0 = Engine.get_physics_frames()
	var args := OS.get_cmdline_user_args()
	scenario_name = _arg(args, "--scenario", "")
	out_dir = _arg(args, "--out", "")
	if out_dir == "":
		out_dir = "user://playtest/%s" % scenario_name
	if out_dir.begins_with("user://") or out_dir.begins_with("res://"):
		out_dir = ProjectSettings.globalize_path(out_dir)
	out_dir = out_dir.replace("\\", "/")
	seed_value = int(_arg(args, "--seed", str(DEFAULT_SEED)))
	continue_run = "--continue-run" in args
	max_game_s = float(_arg(args, "--max-s", "-1"))
	max_wall_s = float(_arg(args, "--max-wall-s", "-1"))
	guard = ScriptErrorGuard.new()
	guard.attach()
	engine_log = PlaytestEngineLog.new()
	engine_log.attach()
	_run.call_deferred()


func _run() -> void:
	report = _open_report()
	if report == null:
		return
	print("PLAYTEST_BEGIN %s phase %d seed %d out %s" % [scenario_name, phase, seed_value, out_dir])
	var path := SCENARIO_DIR.path_join(scenario_name + ".gd")
	if scenario_name == "" or not ResourceLoader.exists(path):
		report.add_error(phase, "scenario", "no scenario '%s' (%s)" % [scenario_name, path])
		_finish("error")
		return
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		report.add_error(phase, "scenario", "%s failed to load or compile" % path)
		_finish("error")
		return
	var inst: Variant = script.new()
	if not (inst is PlaytestScenario):
		report.add_error(phase, "scenario", "%s does not extend PlaytestScenario" % path)
		_finish("error")
		return
	scenario = inst
	if max_game_s <= 0.0:
		max_game_s = scenario.max_seconds()
	if max_wall_s <= 0.0:
		# Three times the game budget, at least 900 s, and below playtest.sh's outer timeout (PLAYTEST_TIMEOUT_S,
		# 3600 s), so the watchdog writes the report before the process can be killed without one.
		max_wall_s = clampf(max_game_s * 3.0, 900.0, DEFAULT_MAX_WALL_S)
	if phase == 0 and scenario.description() != "":
		report.notes.append("scenario: " + scenario.description())
	_seed_rngs()
	driver = PlaytestDriver.new()
	driver.setup(report, phase, out_dir)
	driver.reload_requested.connect(func() -> void: _finish("reload"))
	add_child(driver)
	if not await driver.boot():
		report.add_error(phase, "harness", "the main scene did not reach the title screen")
		_finish("error")
		return
	await scenario.run(driver)
	if not _done and not driver.reloading:
		_finish("done")


func _process(_delta: float) -> void:
	if _quit_at_ms > 0 and Time.get_ticks_msec() >= _quit_at_ms:
		# A reload the game did not finish by itself (its Quit Game never ran): end the process here.
		_quit_at_ms = -1
		get_tree().quit(RELOAD_EXIT_CODE)
		return
	if _done or report == null:
		return
	var game_s := (Engine.get_physics_frames() - _f0) / float(Engine.physics_ticks_per_second)
	var wall_s := (Time.get_ticks_msec() - _wall0) / 1000.0
	if max_game_s > 0.0 and game_s > max_game_s:
		report.add_error(phase, "timeout", "the scenario ran past its %.0f s game-time budget" % max_game_s)
		_finish("timeout")
	elif max_wall_s > 0.0 and wall_s > max_wall_s:
		report.add_error(phase, "timeout", "the scenario ran past its %.0f s wall-time budget" % max_wall_s)
		_finish("timeout")


## Writes the report and ends the phase: "done" (quit 0/1), "reload" (the game quits itself), "timeout" or "error".
func _finish(end: String) -> void:
	if _done:
		return
	_done = true
	if driver != null and driver.input != null:
		driver.input.release_all()
		report.input_reasserts += driver.input.reasserts
	for e in guard.errors():
		report.add_error(phase, "script", e)
	for e: Dictionary in engine_log.take():
		report.add_engine_error(phase, String(e["kind"]), String(e["message"]))
	if driver != null and not driver.open_steps().is_empty():
		report.notes.append("phase %d ended inside step(s) %s" % [phase, str(driver.open_steps())])
	report.phases.append({"phase": phase, "started_at": Time.get_datetime_string_from_unix_time(
		int(Time.get_unix_time_from_system() - (Time.get_ticks_msec() - _wall0) / 1000.0), false) + "Z",
		"game_s": snappedf((Engine.get_physics_frames() - _f0) / float(Engine.physics_ticks_per_second), 0.001),
		"wall_s": snappedf((Time.get_ticks_msec() - _wall0) / 1000.0, 0.001), "end": end})
	report.reload_requested = end == "reload"
	if end == "reload" and phase + 1 >= MAX_PHASES:
		report.add_error(phase, "harness", "more than %d phases (reload_process loop?)" % MAX_PHASES)
		report.reload_requested = false
	report.finished = not report.reload_requested
	var err := report.write()
	if err != OK:
		push_error("[playtest] cannot write the report into %s: %s" % [out_dir, error_string(err)])
	var counts := report.step_counts()
	print("PLAYTEST_RESULT %s %s phase %d: %d checks (%d failed), %d errors, steps play %d / console %d / api %d" % [
		report.result_text(), scenario_name, phase, report.checks.size(), report.failed_checks().size(),
		report.errors.size(), int(counts["play"]), int(counts["console"]), int(counts["api"])])
	for c: Dictionary in report.failed_checks():
		print("PLAYTEST_FAILED_CHECK %s: %s" % [c["name"], c["details"]])
	for e: Dictionary in report.errors:
		print("PLAYTEST_ERROR [%s] %s" % [e["kind"], e["message"]])
	print("PLAYTEST_REPORT " + out_dir.path_join("report.json"))
	if report.reload_requested:
		# The driver now presses Quit Game; if the process is still alive after a while, end it here.
		_quit_at_ms = Time.get_ticks_msec() + 15000
		return
	guard.detach()
	engine_log.detach()
	get_tree().paused = false
	get_tree().quit(0 if report.passed() else 1)


## The report this phase writes into: a fresh one (phase 0), or the previous phase's when --continue-run.
func _open_report() -> PlaytestReport:
	if scenario_name == "":
		push_error("[playtest] --scenario is required")
		get_tree().quit(2)
		return null
	DirAccess.make_dir_recursive_absolute(out_dir)
	if continue_run:
		var prev := PlaytestReport.from_file(out_dir)
		if prev == null or not prev.reload_requested or prev.finished:
			var r := _fresh_report()
			r.add_error(0, "harness", "--continue-run without a report that asked for a reload in %s" % out_dir)
			_finish_early(r)
			return null
		prev.reload_requested = false
		phase = prev.phases.size()
		return prev
	for f in ["report.json", "report.md"]:
		if FileAccess.file_exists(out_dir.path_join(f)):
			DirAccess.remove_absolute(out_dir.path_join(f))
	for sub in ["saves", "shots"]:
		_remove_tree(out_dir.path_join(sub))
	return _fresh_report()


func _fresh_report() -> PlaytestReport:
	var r := PlaytestReport.new()
	r.scenario = scenario_name
	r.seed_value = seed_value
	r.out_dir = out_dir
	r.windowed = DisplayServer.get_name() != "headless"
	r.args = OS.get_cmdline_user_args()
	return r


func _finish_early(r: PlaytestReport) -> void:
	report = r
	_finish("error")


## Game.rng (combat rolls, drops, quest rewards) and MapSession's instance RNG, so a seed replays a run.
func _seed_rngs() -> void:
	var game := get_node_or_null(^"/root/Game")
	if game != null and game.get("rng") is RandomNumberGenerator:
		(game.get("rng") as RandomNumberGenerator).seed = seed_value + phase
	var session := get_node_or_null(^"/root/MapSession")
	if session != null:
		var r := RandomNumberGenerator.new()
		r.seed = seed_value * 7919 + phase
		session.set("rng", r)


static func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var i := args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


static func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
