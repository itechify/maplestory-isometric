class_name ShellCheckRunner
extends RefCounted
## Runs res://scenes/ui/screens/shell_checks.tscn in a child Godot process (the unit-test runner cannot await
## frames) and parses its output: "SHELL_CHECK PASS|FAIL <name>[: detail]", "SHELL_INFO ...",
## "SHELL_CHECKS_DONE <passed> <failed>". Used by test_shell_acceptance.gd and test_death_flow.gd.

const CHECK_SCENE := "res://scenes/ui/screens/shell_checks.tscn"
## Watchdog for the child process (frames at --fixed-fps 60).
const QUIT_AFTER_FRAMES := 40000

var exit_code: int = -1
var done: bool = false
var passed: int = 0
var failures: PackedStringArray = []
var infos: PackedStringArray = []
## Child-process script errors (parse errors, runtime errors in the shell's own scripts).
var script_errors: PackedStringArray = []
var output: String = ""
var elapsed_ms: int = 0


## Runs `scenario` headless and returns this runner with the parsed result.
static func run(scenario: String, extra: PackedStringArray = PackedStringArray()) -> ShellCheckRunner:
	var r := ShellCheckRunner.new()
	var out: Array = []
	var args := PackedStringArray(["--headless", "--fixed-fps", "60", "--quit-after", str(QUIT_AFTER_FRAMES),
		"--path", ProjectSettings.globalize_path("res://"), CHECK_SCENE, "--", "--scenario", scenario])
	args.append_array(extra)
	var t0 := Time.get_ticks_msec()
	r.exit_code = OS.execute(OS.get_executable_path(), args, out, true)
	r.elapsed_ms = Time.get_ticks_msec() - t0
	r.output = "\n".join(PackedStringArray(out))
	r._parse()
	return r


func _parse() -> void:
	var lines := output.split("\n")
	for i in lines.size():
		var l := lines[i].strip_edges()
		if l.begins_with("SHELL_CHECK PASS"):
			passed += 1
		elif l.begins_with("SHELL_CHECK FAIL"):
			failures.append(l.trim_prefix("SHELL_CHECK FAIL "))
		elif l.begins_with("SHELL_INFO"):
			infos.append(l.trim_prefix("SHELL_INFO "))
		elif l.begins_with("SHELL_CHECKS_DONE"):
			done = true
		elif l.begins_with("SCRIPT ERROR"):
			# Only errors raised from the shell's own scripts count here; other systems report their own.
			var at := lines[i + 1].strip_edges() if i + 1 < lines.size() else ""
			var where := l + " " + at
			for j in range(i + 1, mini(i + 4, lines.size())):
				where += " " + lines[j].strip_edges()
			if where.contains("res://scripts/game/") or where.contains("res://scripts/ui/screens/"):
				script_errors.append(l + " | " + at)


## The last `n` characters of the output (for failure messages).
func tail(n: int = 1500) -> String:
	return output.right(n)
