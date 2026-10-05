class_name PlaytestReport
extends RefCounted
## The record of one playtest run (docs/runtime/PLAYTEST_HARNESS.md "Report"): every step the driver took, every
## check, the screenshots, the errors, and the timings, written as <out>/report.json and <out>/report.md.
##
## A run can span several processes (PlaytestDriver.reload_process): each phase process reads the report the previous
## phase wrote (from_file), appends to it and writes it again, so the files on disk are always the whole run so far.
##
## Step kinds tell legitimate play from setup:
##   play     driven through the game's own input (keys, mouse, actions) or by waiting on it
##   console  a debug console command (setup only)
##   api      a shell or system method called directly because the UI could not be driven (logged with the reason)
##   observe  reading state (state(), read_dialogue(), window_text()); never changes the game
## Times are game time (physics frames / ticks per second: under --fixed-fps 60 one frame is 1/60 s whatever the
## wall clock does) with the wall clock alongside.
##
## Format 2 adds two things (docs/runtime/ITERATION_THREE_CONTRACTS.md C6, and the strict no-cheat mode):
##   parity   a check may carry "parity": ["quest:1005", ...]; parity_summary() counts them per key
##   strict   PlaytestDriver.begin_strict() fills `strict`: from that step on no console command, no api fallback, no
##            debug command and no change to the character that the game's own event bus did not announce
##            (PlaytestLedger). strict_ok() is part of passed().

const FORMAT := 2
const KIND_PLAY := "play"
const KIND_CONSOLE := "console"
const KIND_API := "api"
const KIND_OBSERVE := "observe"
const KINDS: PackedStringArray = ["play", "console", "api", "observe"]

var scenario: String = ""
var seed_value: int = 0
var out_dir: String = ""
var windowed: bool = false
var args: PackedStringArray = PackedStringArray()
## One entry per process: {phase, started_at, game_s, wall_s, end ("done" | "reload" | "timeout" | "error")}.
var phases: Array = []
## {i, phase, kind, name, detail, ok, at_game_s, game_s, wall_s}
var steps: Array = []
## {i, phase, name, ok, details, at_game_s, step, soft, parity?}: a soft check that does not hold is a WARN, never a
## failure; "parity" (when present) lists the parity keys the check proves (contract C6).
var checks: Array = []
## {name, path, phase, skipped, reason}
var screenshots: Array = []
## Fatal: {kind ("script" | "scenario" | "timeout" | "harness"), message, phase}. Any one fails the run.
var errors: Array = []
## Not fatal: push_error / engine errors and warnings seen while the scenario ran ({kind, message, phase}).
var engine_errors: Array = []
## Free-form lines (PlaytestDriver.note).
var notes: Array = []
## Input re-asserted after Godot released it (a window that lost focus releases every pressed key).
var input_reasserts: int = 0
## Values a scenario keeps across a reload_process (PlaytestDriver.carry), with their Godot types (var_to_str).
var carry: Dictionary = {}
var reload_requested: bool = false
var finished: bool = false
## The strict no-cheat block ({} until PlaytestDriver.begin_strict()): {"enabled", "reason", "since" {phase, step,
## game_s}, "debug_commands" (Debug.commands_run deltas summed over the strict phases), "ledger" {"reconciled",
## "mismatches"}, "violations" [{phase, kind, detail}]}. strict_summary() adds the counted steps and "ok".
var strict: Dictionary = {}


## Starts a step; returns its index (finish it with end_step).
func begin_step(phase: int, kind: String, step_name: String, detail: String, at_game_s: float, wall_ms: int) -> int:
	steps.append({"i": steps.size(), "phase": phase, "kind": kind, "name": step_name, "detail": detail, "ok": true,
		"at_game_s": snappedf(at_game_s, 0.001), "game_s": 0.0, "wall_s": 0.0, "_wall0": wall_ms})
	return steps.size() - 1


## Closes step `i` with its outcome and durations.
func end_step(i: int, ok: bool, result: String, game_s: float, wall_ms: int) -> void:
	if i < 0 or i >= steps.size():
		return
	var s: Dictionary = steps[i]
	s["ok"] = ok
	if result != "":
		s["result"] = result
	s["game_s"] = snappedf(maxf(0.0, game_s - float(s["at_game_s"])), 0.001)
	s["wall_s"] = snappedf(maxf(0.0, (wall_ms - int(s.get("_wall0", wall_ms))) / 1000.0), 0.001)
	s.erase("_wall0")


func add_check(phase: int, check_name: String, ok: bool, details: String, at_game_s: float, step: int, soft: bool = false,
		parity: Array = []) -> void:
	var c := {"i": checks.size(), "phase": phase, "name": check_name, "ok": ok, "details": details,
		"at_game_s": snappedf(at_game_s, 0.001), "step": step, "soft": soft}
	if not parity.is_empty():
		var keys: Array = []
		for k: Variant in parity:
			if not keys.has(String(k)):
				keys.append(String(k))
		c["parity"] = keys
	checks.append(c)


## Per parity key: {"checks", "passed", "failed", "warned"} over the checks that carry it (contract C6).
func parity_summary() -> Dictionary:
	var out := {}
	for c: Dictionary in checks:
		for k: Variant in c.get("parity", []):
			var row: Dictionary = out.get(String(k), {"checks": 0, "passed": 0, "failed": 0, "warned": 0})
			row["checks"] = int(row["checks"]) + 1
			if bool(c["ok"]):
				row["passed"] = int(row["passed"]) + 1
			elif bool(c.get("soft", false)):
				row["warned"] = int(row["warned"]) + 1
			else:
				row["failed"] = int(row["failed"]) + 1
			out[String(k)] = row
	return out


## Records a strict-mode violation (a refused console command, an api fallback, a debug command, a ledger mismatch).
## Ignored without strict mode.
func add_violation(phase: int, kind: String, detail: String) -> void:
	if not bool(strict.get("enabled", false)):
		return
	var v: Array = strict.get("violations", [])
	v.append({"phase": phase, "kind": kind, "detail": detail})
	strict["violations"] = v


## The strict block plus what the steps show: the console and api steps (any depth) from the strict step on, and
## "ok" (none of them, no debug command, no violation, no ledger mismatch). {"enabled": false} without strict mode.
func strict_summary() -> Dictionary:
	if not bool(strict.get("enabled", false)):
		return {"enabled": false}
	var out := strict.duplicate(true)
	var since := int((strict.get("since", {}) as Dictionary).get("step", 0))
	var console_steps := 0
	var api_steps := 0
	for s: Dictionary in steps:
		if int(s["i"]) < since:
			continue
		if String(s["kind"]) == KIND_CONSOLE:
			console_steps += 1
		elif String(s["kind"]) == KIND_API:
			api_steps += 1
	out["console_steps"] = console_steps
	out["api_steps"] = api_steps
	var ledger: Dictionary = strict.get("ledger", {})
	out["ok"] = console_steps == 0 and api_steps == 0 and int(strict.get("debug_commands", 0)) == 0 \
		and (strict.get("violations", []) as Array).is_empty() and (ledger.get("mismatches", []) as Array).is_empty()
	return out


## True without strict mode; with it, strict_summary()'s "ok".
func strict_ok() -> bool:
	return bool(strict_summary().get("ok", false)) if bool(strict.get("enabled", false)) else true


func add_error(phase: int, kind: String, message: String) -> void:
	errors.append({"phase": phase, "kind": kind, "message": message})


func add_engine_error(phase: int, kind: String, message: String) -> void:
	engine_errors.append({"phase": phase, "kind": kind, "message": message})


## Top-level step counts by kind ({"play": n, "console": n, "api": n, "observe": n}); a step taken inside
## another (the walks of a talk_to) is part of its parent.
func step_counts() -> Dictionary:
	var out := {}
	for k in KINDS:
		out[k] = 0
	for s: Dictionary in steps:
		if int(s.get("depth", 0)) == 0:
			out[String(s["kind"])] = int(out.get(String(s["kind"]), 0)) + 1
	return out


## The (hard) checks that failed.
func failed_checks() -> Array:
	return checks.filter(func(c: Dictionary) -> bool: return not bool(c["ok"]) and not bool(c.get("soft", false)))


## The soft checks that did not hold (WARN lines).
func warnings() -> Array:
	return checks.filter(func(c: Dictionary) -> bool: return not bool(c["ok"]) and bool(c.get("soft", false)))


## PASS: finished, at least one check, every check passed, no fatal error and (in strict mode) no violation.
func passed() -> bool:
	return finished and not checks.is_empty() and failed_checks().is_empty() and errors.is_empty() and strict_ok()


func result_text() -> String:
	if reload_requested and not finished:
		return "RELOADING"
	return "PASS" if passed() else "FAIL"


## Game and wall seconds over every phase.
func totals() -> Dictionary:
	var g := 0.0
	var w := 0.0
	for p: Dictionary in phases:
		g += float(p.get("game_s", 0.0))
		w += float(p.get("wall_s", 0.0))
	return {"game_s": snappedf(g, 0.001), "wall_s": snappedf(w, 0.001)}


func to_dict() -> Dictionary:
	var fails := failed_checks()
	var parity := parity_summary()
	return {
		"format": FORMAT, "scenario": scenario, "result": result_text(), "seed": seed_value, "out_dir": out_dir,
		"windowed": windowed, "args": Array(args), "finished": finished, "reload_requested": reload_requested,
		"totals": totals(), "phases": phases,
		"counts": {"steps": step_counts(), "checks": checks.size(), "checks_failed": fails.size(),
			"warnings": warnings().size(),
			"errors": errors.size(), "engine_errors": engine_errors.size(), "screenshots": screenshots.size(),
			"input_reasserts": input_reasserts, "parity_keys": parity.size()},
		"strict": strict_summary(), "strict_raw": strict, "parity": parity,
		"checks": checks, "steps": steps, "screenshots": screenshots, "errors": errors, "engine_errors": engine_errors,
		"notes": notes, "carry": carry, "carry_var": var_to_str(carry),
	}


static func from_dict(d: Dictionary) -> PlaytestReport:
	var r := PlaytestReport.new()
	r.scenario = String(d.get("scenario", ""))
	r.seed_value = int(d.get("seed", 0))
	r.out_dir = String(d.get("out_dir", ""))
	r.windowed = bool(d.get("windowed", false))
	r.args = PackedStringArray(d.get("args", []))
	r.phases = (d.get("phases", []) as Array).duplicate(true)
	r.steps = (d.get("steps", []) as Array).duplicate(true)
	r.checks = (d.get("checks", []) as Array).duplicate(true)
	r.screenshots = (d.get("screenshots", []) as Array).duplicate(true)
	r.errors = (d.get("errors", []) as Array).duplicate(true)
	r.engine_errors = (d.get("engine_errors", []) as Array).duplicate(true)
	r.notes = (d.get("notes", []) as Array).duplicate(true)
	# carry_var keeps Godot types (ints, vectors) across the process boundary; carry is the readable copy.
	var typed: Variant = str_to_var(String(d.get("carry_var", ""))) if d.has("carry_var") else null
	r.carry = (typed as Dictionary).duplicate(true) if typed is Dictionary else (d.get("carry", {}) as Dictionary).duplicate(true)
	r.input_reasserts = int((d.get("counts", {}) as Dictionary).get("input_reasserts", 0))
	r.reload_requested = bool(d.get("reload_requested", false))
	r.finished = bool(d.get("finished", false))
	r.strict = (d.get("strict_raw") as Dictionary).duplicate(true) if d.get("strict_raw") is Dictionary else {}
	return r


## The report in `dir`/report.json, or null when there is none (or it does not parse).
static func from_file(dir: String) -> PlaytestReport:
	var path := dir.path_join("report.json")
	if not FileAccess.file_exists(path):
		return null
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_dict(v) if v is Dictionary else null


## Writes report.json and report.md into out_dir. Returns the first error.
func write() -> Error:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var err := _write_text(out_dir.path_join("report.json"), JSON.stringify(_plain(to_dict()), "  ", false) + "\n")
	var err2 := _write_text(out_dir.path_join("report.md"), to_markdown())
	return err if err != OK else err2


func to_markdown() -> String:
	var t := totals()
	var counts := step_counts()
	var fails := failed_checks()
	var lines := PackedStringArray()
	lines.append("# Playtest: %s - %s" % [scenario, result_text()])
	lines.append("")
	lines.append("- Seed %d, %s, %d phase(s), %.1f s game time, %.1f s wall time" % [seed_value,
		"windowed" if windowed else "headless", phases.size(), float(t["game_s"]), float(t["wall_s"])])
	lines.append("- Checks: %d passed, %d failed, %d warnings (soft checks that did not hold)" % [
		checks.size() - fails.size() - warnings().size(), fails.size(), warnings().size()])
	lines.append("- Top-level steps: %d play, %d console (setup), %d api (shell fallback), %d observe" % [int(counts["play"]),
		int(counts["console"]), int(counts["api"]), int(counts["observe"])])
	lines.append("- Errors: %d fatal, %d engine (not fatal); input re-asserted %d times" % [errors.size(),
		engine_errors.size(), input_reasserts])
	var st := strict_summary()
	if bool(st.get("enabled", false)):
		var since: Dictionary = st.get("since", {})
		lines.append(("- Strict (no cheats) since phase %d, step %d (%s): %s; %d console, %d api, %d debug commands, "
			+ "%d ledger mismatches, %d violations") % [int(since.get("phase", 0)), int(since.get("step", 0)),
			String(st.get("reason", "")), "OK" if bool(st["ok"]) else "**VIOLATED**", int(st["console_steps"]),
			int(st["api_steps"]), int(st.get("debug_commands", 0)),
			((st.get("ledger", {}) as Dictionary).get("mismatches", []) as Array).size(), (st.get("violations", []) as Array).size()])
	else:
		lines.append("- Strict (no cheats): off")
	lines.append("")
	if bool(st.get("enabled", false)) and not bool(st["ok"]):
		lines.append("## Strict violations")
		lines.append("")
		for v: Dictionary in st.get("violations", []):
			lines.append("- [%s, phase %d] %s" % [v.get("kind", ""), int(v.get("phase", 0)), _md(String(v.get("detail", "")))])
		for m: Variant in (st.get("ledger", {}) as Dictionary).get("mismatches", []):
			lines.append("- [ledger] " + _md(str(m)))
		lines.append("")
	if not errors.is_empty():
		lines.append("## Errors")
		lines.append("")
		for e: Dictionary in errors:
			lines.append("- [%s, phase %d] %s" % [e["kind"], int(e["phase"]), _md(String(e["message"]))])
		lines.append("")
	lines.append("## Checks")
	lines.append("")
	lines.append("| # | Phase | Result | Check | Details | Parity |")
	lines.append("|---|---|---|---|---|---|")
	for c: Dictionary in checks:
		var verdict := "PASS" if bool(c["ok"]) else ("WARN" if bool(c.get("soft", false)) else "**FAIL**")
		lines.append("| %d | %d | %s | %s | %s | %s |" % [int(c["i"]), int(c["phase"]), verdict,
			_md(String(c["name"])), _md(String(c["details"])), _md(", ".join(PackedStringArray(c.get("parity", []))))])
	lines.append("")
	var parity := parity_summary()
	if not parity.is_empty():
		lines.append("## Parity keys (contract C6)")
		lines.append("")
		lines.append("| Key | Checks | Passed | Failed | Warned |")
		lines.append("|---|---|---|---|---|")
		var keys := parity.keys()
		keys.sort()
		for k: Variant in keys:
			var row: Dictionary = parity[k]
			lines.append("| %s | %d | %d | %d | %d |" % [_md(str(k)), int(row["checks"]), int(row["passed"]),
				int(row["failed"]), int(row["warned"])])
		lines.append("")
	lines.append("## Steps")
	lines.append("")
	lines.append("| # | Phase | Kind | Step | OK | Game s | Wall s | Detail / result |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for s: Dictionary in steps:
		var detail := String(s.get("detail", ""))
		if s.has("result") and String(s["result"]) != "":
			detail += (" -> " if detail != "" else "") + String(s["result"])
		lines.append("| %d | %d | %s | %s | %s | %.2f | %.2f | %s |" % [int(s["i"]), int(s["phase"]), s["kind"],
			_md("· ".repeat(int(s.get("depth", 0))) + String(s["name"])), "yes" if bool(s["ok"]) else "**no**",
			float(s["game_s"]), float(s["wall_s"]),
			_md(detail.left(300))])
	lines.append("")
	if not screenshots.is_empty():
		lines.append("## Screenshots")
		lines.append("")
		for sh: Dictionary in screenshots:
			if bool(sh.get("skipped", false)):
				lines.append("- %s: skipped (%s)" % [sh["name"], sh.get("reason", "")])
			else:
				lines.append("- %s: `%s`" % [sh["name"], sh["path"]])
		lines.append("")
	if not engine_errors.is_empty():
		lines.append("## Engine errors and warnings (not fatal)")
		lines.append("")
		for e: Dictionary in engine_errors.slice(0, 200):
			lines.append("- [%s, phase %d] %s" % [e["kind"], int(e["phase"]), _md(String(e["message"]))])
		if engine_errors.size() > 200:
			lines.append("- ... %d more in report.json" % (engine_errors.size() - 200))
		lines.append("")
	if not notes.is_empty():
		lines.append("## Notes")
		lines.append("")
		for n: Variant in notes:
			lines.append("- " + _md(str(n)))
		lines.append("")
	lines.append("## Phases")
	lines.append("")
	for p: Dictionary in phases:
		lines.append("- phase %d: %s, %.1f s game, %.1f s wall" % [int(p["phase"]), p.get("end", "?"),
			float(p.get("game_s", 0.0)), float(p.get("wall_s", 0.0))])
	lines.append("")
	return "\n".join(lines)


static func _md(s: String) -> String:
	return s.replace("|", "\\|").replace("\n", " ")


static func _write_text(path: String, text: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return OK


## JSON-safe values: vectors as arrays, packed arrays as arrays, objects as their string.
static func _plain(v: Variant) -> Variant:
	if v is Dictionary:
		var o := {}
		for k: Variant in v:
			o[str(k)] = _plain(v[k])
		return o
	if v is Array or v is PackedStringArray or v is PackedFloat32Array or v is PackedInt32Array \
			or v is PackedVector3Array or v is PackedInt64Array or v is PackedFloat64Array:
		var a: Array = []
		for e: Variant in v:
			a.append(_plain(e))
		return a
	if v is Vector3:
		return [snappedf((v as Vector3).x, 0.001), snappedf((v as Vector3).y, 0.001), snappedf((v as Vector3).z, 0.001)]
	if v is Vector2:
		return [snappedf((v as Vector2).x, 0.001), snappedf((v as Vector2).y, 0.001)]
	if v is float:
		return snappedf(v, 0.0001)
	if v is Object:
		return str(v)
	if v is StringName or v is NodePath:
		return str(v)
	return v
