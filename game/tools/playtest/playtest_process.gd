class_name PlaytestProcess
extends RefCounted
## Runs a playtest scenario in child Godot processes, the way scripts/playtest.sh does, and returns its report
## (docs/runtime/PLAYTEST_HARNESS.md). For unit tests and tools that already run inside a project copy:
##
##   var r := PlaytestProcess.run("smoke", {"out": "user://_tests/playtest_smoke"})
##   r.report        # report.json as a Dictionary ({} when none was written)
##   r.passed()      # finished, every check passed, no fatal error, exit code 0
##
## Each phase is one headless process (--fixed-fps 60) of res://tools/playtest/playtest_runner.tscn; a report that
## asks for a reload ("reload_requested": true, not "finished") starts the next phase with --continue-run, up to
## PlaytestRunner's limit. The child's output is kept (`output`), and SCRIPT ERROR lines in it (parse errors happen
## before the runner's ScriptErrorGuard exists) are collected in `script_errors`. A report left in `out` by an earlier
## run is removed first, and a phase that writes no report (a crash) ends the run with a `process_errors` line instead
## of being started again.

const RUNNER_SCENE := "res://tools/playtest/playtest_runner.tscn"
const MAX_PHASES := 12
## Game seconds a child may run when opts has no "max_s" (the hard --quit-after cap; it ends the process without a
## report, so it sits far above any scenario budget: the runner's own watchdog ends a run first, with a report).
const DEFAULT_CAP_S := 14400.0

var scenario: String = ""
var out_dir: String = ""
var report: Dictionary = {}
var exit_codes: PackedInt32Array = PackedInt32Array()
var output: String = ""
var script_errors: PackedStringArray = PackedStringArray()
## Phases that ended without writing their report (a crash or a hang before the runner could write).
var process_errors: PackedStringArray = PackedStringArray()
var elapsed_ms: int = 0


## Runs `scenario_name`. opts: "out" (directory; user:// is globalized; default user://playtest/<name>), "seed",
## "max_s", "extra" (PackedStringArray of more runner arguments).
static func run(scenario_name: String, opts: Dictionary = {}) -> PlaytestProcess:
	var r := PlaytestProcess.new()
	r.scenario = scenario_name
	var out := String(opts.get("out", "user://playtest/%s" % scenario_name))
	r.out_dir = ProjectSettings.globalize_path(out) if out.begins_with("user://") or out.begins_with("res://") else out
	var t0 := Time.get_ticks_msec()
	# An old report in a reused directory must never stand in for this run's (a child that dies before writing).
	for f in ["report.json", "report.md"]:
		if FileAccess.file_exists(r.out_dir.path_join(f)):
			DirAccess.remove_absolute(r.out_dir.path_join(f))
	var phases_seen := 0
	for phase in MAX_PHASES:
		var cap_s := float(opts["max_s"]) * 2.0 + 300.0 if opts.has("max_s") else DEFAULT_CAP_S
		var args := PackedStringArray(["--headless", "--fixed-fps", "60", "--quit-after", str(int(cap_s * 60.0)),
			"--path", ProjectSettings.globalize_path("res://"), RUNNER_SCENE, "--", "--scenario", scenario_name,
			"--out", r.out_dir])
		if opts.has("seed"):
			args.append_array(["--seed", str(opts["seed"])])
		if opts.has("max_s"):
			args.append_array(["--max-s", str(opts["max_s"])])
		args.append_array(opts.get("extra", PackedStringArray()))
		if phase > 0:
			args.append("--continue-run")
		var lines: Array = []
		var code := OS.execute(OS.get_executable_path(), args, lines, true)
		r.exit_codes.append(code)
		var text := "\n".join(PackedStringArray(lines))
		r.output += text + "\n"
		r._collect_script_errors(text)
		var rep: Variant = JSON.parse_string(FileAccess.get_file_as_string(r.out_dir.path_join("report.json"))) \
			if FileAccess.file_exists(r.out_dir.path_join("report.json")) else null
		r.report = rep if rep is Dictionary else {}
		var phases_now := (r.report.get("phases", []) as Array).size()
		if phase > 0 and phases_now <= phases_seen:
			# This phase wrote nothing (it crashed or hung before its report): running it again would only repeat that.
			r.process_errors.append("phase %d wrote no report (exit code %d)" % [phase, code])
			break
		phases_seen = phases_now
		if not (bool(r.report.get("reload_requested", false)) and not bool(r.report.get("finished", false))):
			break
	r.elapsed_ms = Time.get_ticks_msec() - t0
	return r


## Finished, every check passed, no fatal error, no script error in the output, every phase wrote its report, and
## the last exit code 0.
func passed() -> bool:
	return String(report.get("result", "")) == "PASS" and script_errors.is_empty() and process_errors.is_empty() \
		and not exit_codes.is_empty() and exit_codes[exit_codes.size() - 1] == 0


## The failed checks and errors as lines (for test failure messages). Soft checks are warnings(), not problems.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	for c: Variant in report.get("checks", []):
		if c is Dictionary and not bool((c as Dictionary).get("ok", false)) and not bool((c as Dictionary).get("soft", false)):
			out.append("check failed: %s: %s" % [(c as Dictionary).get("name", ""), (c as Dictionary).get("details", "")])
	for e: Variant in report.get("errors", []):
		if e is Dictionary:
			out.append("error [%s]: %s" % [(e as Dictionary).get("kind", ""), (e as Dictionary).get("message", "")])
	for e in script_errors:
		out.append("script error: " + e)
	for e in process_errors:
		out.append("process: " + e)
	return out


## The soft checks that did not hold (known issues the run surfaced without failing), as lines.
func warnings() -> PackedStringArray:
	var out := PackedStringArray()
	for c: Variant in report.get("checks", []):
		if c is Dictionary and not bool((c as Dictionary).get("ok", false)) and bool((c as Dictionary).get("soft", false)):
			out.append("%s: %s" % [(c as Dictionary).get("name", ""), (c as Dictionary).get("details", "")])
	return out


## The last `n` characters of the children's output.
func tail(n: int = 2000) -> String:
	return output.right(n)


func _collect_script_errors(text: String) -> void:
	var lines := text.split("\n")
	for i in lines.size():
		var l := lines[i].strip_edges()
		if l.begins_with("SCRIPT ERROR") or l.begins_with("Parse Error") or l.contains("Failed to load script"):
			var at := lines[i + 1].strip_edges() if i + 1 < lines.size() else ""
			script_errors.append(l + (" | " + at if at.begins_with("at:") else ""))
