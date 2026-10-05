class_name PlaytestQuestSummary
extends SceneTree
## The every-quest table (docs/runtime/PLAYTEST_HARNESS.md "The every-quest set"): scripts/playtest_quests.sh runs
## the `quest` scenario once per chain, each into <out>/<chain>/, then this script reads every report.json and writes
## <out>/quests.json and <out>/quests.md, one row per quest. Run headless:
##
##   godot --headless --path <copy> --script res://tools/playtest/playtest_quest_summary.gd -- --out <dir> \
##       --chains "1000-1001 1002 ..." [--seed 1]
##
## Exit code 0 when every quest of every chain is PASS, 1 otherwise, 2 on a bad command line. A quest's verdict is the
## scenario's own (carry.quest_results); when a run ended early (a timeout, a crash) it is rebuilt from the report's
## parity keys, and a quest with no check at all is NOT_PLAYED. A chain whose strict block was violated fails all its
## quests.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := _arg(args, "--out", "")
	var chains := _arg(args, "--chains", "").split(" ", false)
	if out == "" or chains.is_empty():
		push_error("usage: --out <dir> --chains \"<chain> <chain> ...\"")
		quit(2)
		return
	var s := collect(out, chains)
	s["seed"] = int(_arg(args, "--seed", "1"))
	_write(out.path_join("quests.json"), JSON.stringify(PlaytestReport._plain(s), "  ", false) + "\n")
	_write(out.path_join("quests.md"), to_markdown(s))
	print("PLAYTEST_QUESTS %d/%d quests PASS - %s" % [int(s["passed"]), (s["quests"] as Array).size(), out.path_join("quests.md")])
	quit(0 if bool(s["ok"]) else 1)


## Reads <out>/<chain dir>/report.json for every chain. {"ok", "passed", "chains": [{chain, dir, result, strict,
## game_s, wall_s, phases, console_setup, errors}], "quests": [{id, name, chain, result, completed, checks, failed,
## warnings, random}]}.
static func collect(out_dir: String, chains: PackedStringArray) -> Dictionary:
	var rows: Array = []
	var chain_rows: Array = []
	var passed := 0
	for chain in chains:
		var dir := out_dir.path_join(chain_dir(chain))
		var rep: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("report.json"))) \
			if FileAccess.file_exists(dir.path_join("report.json")) else null
		var r: Dictionary = rep if rep is Dictionary else {}
		var strict: Dictionary = r.get("strict", {})
		var strict_ok := bool(strict.get("ok", false))
		var totals: Dictionary = r.get("totals", {})
		var console_setup := 0
		var since := int((strict.get("since", {}) as Dictionary).get("step", 1 << 30))
		for st: Variant in r.get("steps", []):
			if st is Dictionary and String((st as Dictionary).get("kind", "")) == "console" and int((st as Dictionary).get("i", 0)) < since:
				console_setup += 1
		chain_rows.append({"chain": chain, "dir": dir, "result": String(r.get("result", "NO REPORT")),
			"strict": "ok" if strict_ok else ("VIOLATED" if bool(strict.get("enabled", false)) else "off"),
			"game_s": float(totals.get("game_s", 0.0)), "wall_s": float(totals.get("wall_s", 0.0)),
			"phases": (r.get("phases", []) as Array).size(), "console_setup": console_setup,
			"errors": (r.get("errors", []) as Array).size()})
		var results: Dictionary = (r.get("carry", {}) as Dictionary).get("quest_results", {})
		var names: Dictionary = (r.get("carry", {}) as Dictionary).get("quest_names", {})
		var parity: Dictionary = r.get("parity", {})
		for id in _chain_ids(chain):
			var q: Dictionary = results.get(id, {})
			var row := {"id": id, "chain": chain, "name": String(q.get("name", names.get(id, ""))), "result": String(q.get("result", "")),
				"completed": bool(q.get("completed", false)), "checks": int(q.get("checks", 0)),
				"failed": Array(q.get("failed", [])), "warnings": int(q.get("warnings", 0)),
				"random": Array((r.get("carry", {}) as Dictionary).get("random_%s" % id, []))}
			if q.is_empty():
				# The run ended before the scenario's own verdict: rebuilt from the parity keys.
				var pk: Dictionary = parity.get("quest:" + id, {})
				row["checks"] = int(pk.get("checks", 0))
				row["warnings"] = int(pk.get("warned", 0))
				row["failed"] = _failed_names(r, "quest:" + id)
				row["result"] = "NOT_PLAYED" if int(pk.get("checks", 0)) == 0 else "FAIL"
				if row["result"] == "FAIL" and (row["failed"] as Array).is_empty():
					row["failed"] = ["the run ended before the quest finished (%s)" % chain_rows[-1]["result"]]
			if not strict_ok and row["result"] == "PASS":
				row["result"] = "FAIL"
				(row["failed"] as Array).append("strict mode %s for chain %s" % [chain_rows[-1]["strict"], chain])
			if row["result"] == "PASS":
				passed += 1
			rows.append(row)
	return {"ok": passed == rows.size() and not rows.is_empty(), "passed": passed, "chains": chain_rows, "quests": rows,
		"written_at": Time.get_datetime_string_from_system(true) + "Z"}


static func to_markdown(s: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("# Every-quest real-game playthrough")
	lines.append("")
	lines.append("%d of %d quests PASS (seed %d, %s). Each chain is one `quest` scenario run: setup by logged console "
		% [int(s["passed"]), (s["quests"] as Array).size(), int(s.get("seed", 1)), s.get("written_at", "")]
		+ "commands in phase 0 only, then strict play with real input from the setup save.")
	lines.append("")
	lines.append("| Quest | Name | Chain | Result | Checks | Failed | Warnings | Random reward |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for q: Dictionary in s["quests"]:
		lines.append("| %s | %s | %s | %s | %d | %s | %d | %s |" % [q["id"], PlaytestReport._md(String(q["name"])),
			q["chain"], "**%s**" % q["result"] if q["result"] != "PASS" else q["result"], int(q["checks"]),
			PlaytestReport._md("; ".join(PackedStringArray(q["failed"])).left(300)), int(q["warnings"]),
			PlaytestReport._md(", ".join(PackedStringArray(q["random"])))])
	lines.append("")
	lines.append("| Chain | Result | Strict | Setup console steps | Phases | Game s | Wall s | Errors | Report |")
	lines.append("|---|---|---|---|---|---|---|---|---|")
	for c: Dictionary in s["chains"]:
		lines.append("| %s | %s | %s | %d | %d | %.0f | %.0f | %d | `%s/report.md` |" % [c["chain"], c["result"], c["strict"],
			int(c["console_setup"]), int(c["phases"]), float(c["game_s"]), float(c["wall_s"]), int(c["errors"]), c["dir"]])
	lines.append("")
	return "\n".join(lines)


## The directory name of a chain ("1006,1009,1010" -> "1006_1009_1010").
static func chain_dir(chain: String) -> String:
	return chain.replace(",", "_")


static func _chain_ids(chain: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in chain.split(",", false):
		if part.contains("-"):
			for n in range(int(part.get_slice("-", 0)), int(part.get_slice("-", 1)) + 1):
				out.append(str(n))
		else:
			out.append(part)
	return out


static func _failed_names(r: Dictionary, key: String) -> Array:
	var out: Array = []
	for c: Variant in r.get("checks", []):
		if c is Dictionary and not bool((c as Dictionary).get("ok", true)) and not bool((c as Dictionary).get("soft", false)) \
				and ((c as Dictionary).get("parity", []) as Array).has(key):
			out.append(String((c as Dictionary).get("name", "")))
	return out


static func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var i := args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


static func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
