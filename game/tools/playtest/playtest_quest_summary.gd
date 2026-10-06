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
## quests, and so does a fatal error or a failed check that names no quest (a quest's own failure fails only it).


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := _arg(args, "--out", "")
	if args.has("--combine"):
		# Several runs of the set (one --out each, e.g. one per seed) into one per-quest evidence report:
		#   --combine "<dir1> <dir2> ..." --out <file.md>
		var dirs := _arg(args, "--combine", "").split(" ", false)
		var sums: Array = []
		for dir in dirs:
			var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("quests.json"))) \
				if FileAccess.file_exists(dir.path_join("quests.json")) else null
			if j is Dictionary:
				(j as Dictionary)["dir"] = dir
				sums.append(j)
		if sums.is_empty() or out == "":
			push_error("usage: --combine \"<dir> <dir> ...\" --out <file.md> (each dir holds a quests.json)")
			quit(2)
			return
		_write(out, combined_markdown(sums))
		print("PLAYTEST_QUESTS combined %d runs - %s" % [sums.size(), out])
		quit(0)
		return
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
		var setup_cmds := PackedStringArray()
		var since := int((strict.get("since", {}) as Dictionary).get("step", 1 << 30))
		for st: Variant in r.get("steps", []):
			if st is Dictionary and String((st as Dictionary).get("kind", "")) == "console" and int((st as Dictionary).get("i", 0)) < since:
				console_setup += 1
				setup_cmds.append(String((st as Dictionary).get("detail", "")))
		chain_rows.append({"chain": chain, "dir": dir, "result": String(r.get("result", "NO REPORT")),
			"strict": "ok" if strict_ok else ("VIOLATED" if bool(strict.get("enabled", false)) else "off"),
			"game_s": float(totals.get("game_s", 0.0)), "wall_s": float(totals.get("wall_s", 0.0)),
			"phases": (r.get("phases", []) as Array).size(), "console_setup": console_setup,
			"errors": (r.get("errors", []) as Array).size()})
		# What failed the chain without naming a quest (a fatal script error, a timeout, a failed check with no quest
		# key): no quest of the chain can PASS over it. A failure tagged to one quest does not touch the others.
		var unattributed := PackedStringArray()
		for e: Variant in r.get("errors", []):
			unattributed.append("error: %s" % String((e as Dictionary).get("message", "")).left(120) if e is Dictionary else str(e))
		for c: Variant in r.get("checks", []):
			if c is Dictionary and not bool((c as Dictionary).get("ok", true)) and not bool((c as Dictionary).get("soft", false)) \
					and not ((c as Dictionary).get("parity", []) as Array).any(func(k: Variant) -> bool: return String(k).begins_with("quest:")):
				unattributed.append("failed check: %s" % String((c as Dictionary).get("name", "")))
		var results: Dictionary = (r.get("carry", {}) as Dictionary).get("quest_results", {})
		var names: Dictionary = (r.get("carry", {}) as Dictionary).get("quest_names", {})
		var parity: Dictionary = r.get("parity", {})
		for id in _chain_ids(chain):
			var q: Dictionary = results.get(id, {})
			var row := {"id": id, "chain": chain, "name": String(q.get("name", names.get(id, ""))), "result": String(q.get("result", "")),
				"completed": bool(q.get("completed", false)), "checks": int(q.get("checks", 0)),
				"failed": Array(q.get("failed", [])), "warnings": int(q.get("warnings", 0)),
				"random": Array((r.get("carry", {}) as Dictionary).get("random_%s" % id, [])),
				"evidence": (((r.get("carry", {}) as Dictionary).get("quest_evidence", {}) as Dictionary).get(id, {})),
				"console_setup": console_setup, "setup_commands": setup_cmds,
				"strict_since": String(strict.get("reason", ""))}
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
			if not unattributed.is_empty() and row["result"] == "PASS":
				row["result"] = "FAIL"
				(row["failed"] as Array).append("chain %s: %s" % [chain, "; ".join(unattributed)])
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


## Several runs of the set (quests.json documents, e.g. seeds 1, 2 and 3) as one report: the verdicts side by side,
## then per quest what each run showed (PlaytestQuestRunner's evidence): availability, acceptance, objectives,
## completion, rewards with the random pick and the C3 rewards_received record, follow-ups, the mid-quest save and
## restart, and the chain's setup.
static func combined_markdown(sums: Array) -> String:
	var L := PackedStringArray()
	var seeds := PackedStringArray()
	for s: Dictionary in sums:
		seeds.append("seed %d" % int(s.get("seed", 0)))
	var head := "| Quest | Name | Chain | " + " | ".join(seeds) + " |"
	L.append(head)
	L.append("|---|---|---|" + "---|".repeat(sums.size()))
	var first: Dictionary = sums[0]
	for qi in (first["quests"] as Array).size():
		var q0: Dictionary = (first["quests"] as Array)[qi]
		var cells := PackedStringArray()
		for s: Dictionary in sums:
			var q := _quest_in(s, String(q0["id"]))
			var res := String(q.get("result", "-"))
			cells.append(("%s (%d)" % [res, int(q.get("checks", 0))]) if res == "PASS" else "**%s** (%d): %s" % [res,
				int(q.get("checks", 0)), PlaytestReport._md("; ".join(PackedStringArray(q.get("failed", [])))).left(160)])
		L.append("| %s | %s | %s | %s |" % [q0["id"], PlaytestReport._md(String(q0["name"])), q0["chain"], " | ".join(cells)])
	L.append("")
	L.append("| Chain | " + " | ".join(seeds) + " |")
	L.append("|---|" + "---|".repeat(sums.size()))
	for ci in (first["chains"] as Array).size():
		var c0: Dictionary = (first["chains"] as Array)[ci]
		var cells := PackedStringArray()
		for s: Dictionary in sums:
			var c: Dictionary = {}
			for x: Dictionary in s["chains"]:
				if String(x["chain"]) == String(c0["chain"]):
					c = x
			cells.append("%s, strict %s, %d setup console, %d phases, %.0f game s / %.0f wall s" % [c.get("result", "-"),
				c.get("strict", "-"), int(c.get("console_setup", 0)), int(c.get("phases", 0)), float(c.get("game_s", 0.0)),
				float(c.get("wall_s", 0.0))])
		L.append("| %s | %s |" % [c0["chain"], " | ".join(cells)])
	L.append("")
	for qi in (first["quests"] as Array).size():
		var q0: Dictionary = (first["quests"] as Array)[qi]
		var id := String(q0["id"])
		L.append("### %s %s" % [id, q0["name"]])
		L.append("")
		L.append("| | " + " | ".join(seeds) + " |")
		L.append("|---|" + "---|".repeat(sums.size()))
		for aspect: String in ["Availability", "Acceptance", "Objectives", "Completion", "Rewards", "Random reward",
				"rewards_received", "Follow-ups", "Mid-quest save and restart", "Setup"]:
			var cells := PackedStringArray()
			for s: Dictionary in sums:
				cells.append(PlaytestReport._md(_aspect(_quest_in(s, id), aspect)))
			L.append("| %s | %s |" % [aspect, " | ".join(cells)])
		L.append("")
	return "\n".join(L)


static func _quest_in(s: Dictionary, id: String) -> Dictionary:
	for q: Dictionary in s.get("quests", []):
		if String(q["id"]) == id:
			return q
	return {}


## One cell of the per-quest evidence table.
static func _aspect(q: Dictionary, aspect: String) -> String:
	var ev: Dictionary = q.get("evidence", {})
	match aspect:
		"Availability":
			var o: Dictionary = ev.get("offer", {})
			var parts := PackedStringArray()
			if ev.has("refused_below_level"):
				parts.append("refused at level %d%s" % [int(ev["refused_below_level"]), "" if bool(ev.get("refused_ok", true)) else " (NOT refused)"])
			if not o.is_empty():
				parts.append("%s's marker '%s' (engine '%s') at level %d; Quest Log Available %s" % [o.get("npc", "?"), o.get("marker", "?"),
					o.get("engine", "?"), int(o.get("level", 0)), "yes" if bool(o.get("log_available", false)) else "NO"])
			if ev.has("gate_probe"):
				var g: Dictionary = ev["gate_probe"]
				parts.append("box %s broken before the accept, gained '%s'" % [g.get("box", ""), g.get("gained", "")])
			return "; ".join(parts) if not parts.is_empty() else "-"
		"Acceptance":
			var a: Dictionary = ev.get("accept", {})
			if a.is_empty():
				return "-"
			return "%s at level %d (phase %d); marker after '%s'; Quest Log: %s%s" % ["accepted" if bool(a.get("ok", false)) else "NOT accepted",
				int(a.get("level", 0)), int(a.get("phase", 0)), a.get("marker_after", "?"), a.get("log_rows", ""),
				("; accept items: %s" % a["items"]) if a.has("items") else ""]
		"Objectives":
			var parts := PackedStringArray()
			for o: Dictionary in ev.get("objectives", []):
				parts.append("%s %s in %s: %s%s%s" % [o.get("kind", ""), o.get("what", ""), o.get("where", ""), o.get("progress", ""),
					(" from " + String(o["source"])) if o.has("source") else "", "" if bool(o.get("ok", false)) else " (NOT met)"])
			if ev.has("boxes_broken"):
				parts.append("%d Wooden Boxes broken" % int(ev["boxes_broken"]))
			if ev.has("quiz"):
				var z: Dictionary = ev["quiz"]
				parts.append("quiz '%s': wrong '%s' %s, then '%s' (%s) %s" % [String(z.get("question", "")).left(60), z.get("wrong", ""),
					"kept it in progress" if bool(z.get("wrong_ok", false)) else "WRONG LINE", z.get("right", ""), z.get("basis", ""),
					"completed it" if bool(z.get("right_ok", false)) else "DID NOT complete it"])
			return "; ".join(parts) if not parts.is_empty() else "talk only"
		"Completion":
			var t: Dictionary = ev.get("turn_in", {})
			if t.is_empty():
				return "-"
			return "%s's marker '%s'; %s at level %d (phase %d); Completed tab %s" % [t.get("npc", "?"), t.get("marker", "?"),
				"completed" if bool(t.get("completed", false)) else "NOT completed", int(t.get("level", 0)), int(t.get("phase", 0)),
				"yes" if bool(t.get("log_completed", false)) else "no"]
		"Rewards":
			var r: Dictionary = ev.get("rewards", {})
			if r.is_empty():
				return "-"
			return "EXP %+d (canonical %d)%s, mesos %+d (canonical %d), bag %s%s; level %s" % [int(r.get("exp", 0)), int(r.get("exp_canonical", 0)),
				"" if bool(r.get("exp_ok", false)) else " MISMATCH", int(r.get("mesos", 0)), int(r.get("mesos_canonical", 0)),
				r.get("bag", "") if String(r.get("bag", "")) != "" else "unchanged", "" if bool(r.get("bag_ok", false)) else " MISMATCH",
				r.get("level", "")]
		"Random reward":
			var pick := String((ev.get("rewards", {}) as Dictionary).get("random_pick", ""))
			return pick if pick != "" else ", ".join(PackedStringArray(q.get("random", []))) if not (q.get("random", []) as Array).is_empty() else "-"
		"rewards_received":
			var r: Dictionary = ev.get("rewards", {})
			return "%s%s" % [r.get("rewards_received", "-"), "" if not r.has("rewards_received_ok") else (" (matches the pick)"
				if bool(r["rewards_received_ok"]) else " (DOES NOT match)")]
		"Follow-ups":
			var parts := PackedStringArray()
			for f: Dictionary in ev.get("followups", []):
				parts.append("%s %s at level %d (min %d)%s" % [f.get("quest", ""), "available" if bool(f.get("available", false)) else "not available",
					int(f.get("level", 0)), int(f.get("min_level", 1)), (", marker '%s'" % f["marker"]) if f.has("marker") else ""])
			return "; ".join(parts) if not parts.is_empty() else "none (canonical)"
		"Mid-quest save and restart":
			var m: Dictionary = ev.get("mid_reload", {})
			if m.is_empty():
				return "-"
			return "%s in %s (phase %d -> %s): %s%s" % [m.get("when", ""), m.get("map", ""), int(m.get("phase", 0)),
				str(int(m["resumed_phase"])) if m.has("resumed_phase") else "?", "progress restored" if bool(m.get("verified", false)) else "NOT verified",
				("; Quest Log after: " + String(m["log_row_after"])) if String(m.get("log_row_after", "")) != "" else ""]
		"Setup":
			var cmds := PackedStringArray(q.get("setup_commands", []))
			if cmds.is_empty():
				return "none: strict %s" % String(q.get("strict_since", "")) if String(q.get("strict_since", "")) != "" else "none"
			return "%d console step(s) before strict mode (%s): %s" % [cmds.size(), q.get("strict_since", ""), "; ".join(cmds)]
	return "-"


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
