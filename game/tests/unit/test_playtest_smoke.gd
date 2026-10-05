extends TestCase
## The playtest harness end to end (docs/runtime/PLAYTEST_HARNESS.md): the "smoke", "reload" and "counter" scenarios
## run headless through PlaytestProcess, exactly as scripts/playtest.sh runs them (res://tools/playtest/
## playtest_runner.tscn in child processes, --fixed-fps 60), and their report.json must be clean: finished, every check
## passed, no fatal error, no script error, the steps counted by kind. Needs the Blender export (INCLUDE_WORLD=1);
## prints one SKIP line per test without it.


## Contract C6: the quest run proves Roger's Apple through real play.
func parity_keys() -> Dictionary:
	return {"test_quest_scenario_plays_1002_in_strict_mode": ["quest:1002", "mechanic:no-console-playthrough"]}


func test_smoke_scenario_runs_clean_through_the_runner() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_smoke_scenario_runs_clean_through_the_runner: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var out := "user://_tests/playtest_smoke_%d_%d" % [Time.get_ticks_usec(), randi()]
	var r := PlaytestProcess.run("smoke", {"out": out})
	_assert_clean(r, "smoke")
	var rep := r.report
	var counts: Dictionary = rep.get("counts", {})
	var steps: Dictionary = counts.get("steps", {})
	assert_eq(int(counts.get("checks", 0)) >= 15, true, "smoke runs its full set of checks (%d)" % int(counts.get("checks", 0)))
	assert_eq((rep.get("phases", []) as Array).size(), 1, "smoke is one process")
	assert_true(int(steps.get("play", 0)) >= 8, "the flow is played (%d play steps)" % int(steps.get("play", 0)))
	assert_eq(int(steps.get("api", -1)), 0, "every shell screen was driven with the mouse and keys (no api fallback)")
	# The only console step allowed is the documented one: placing the player before Roger when he cannot be reached.
	var console_steps := 0
	for s: Dictionary in rep.get("steps", []):
		if String(s.get("kind", "")) == "console":
			console_steps += 1
			assert_true(String(s.get("detail", "")).begins_with("goto npc"), "unexpected console step: %s" % s.get("detail", ""))
	assert_true(console_steps <= 1, "at most one console step (%d)" % console_steps)
	var names := PackedStringArray()
	for c: Dictionary in rep.get("checks", []):
		names.append(String(c.get("name", "")))
	for want in ["walked route Main of 000000001", "walked the trail into 000000010 across the gate",
			"Roger's conversation opens with the interact key", "saved through the pause menu", "continued in the same map"]:
		assert_has(names, want, "smoke check")
	for w in r.warnings():
		print("  [playtest smoke] WARN " + w)
	assert_true(FileAccess.file_exists(r.out_dir.path_join("report.md")), "report.md written")
	assert_true(DirAccess.dir_exists_absolute(r.out_dir.path_join("saves")), "the run's private save directory")
	print("  [playtest smoke] %s: %d checks, %d warnings, steps %s, %.1f s game, %d ms wall" % [rep.get("result", "?"),
		int(counts.get("checks", 0)), int(counts.get("warnings", 0)), steps, float((rep.get("totals", {}) as Dictionary).get("game_s", 0.0)),
		r.elapsed_ms])
	_remove_tree(r.out_dir)


func test_reload_scenario_continues_in_a_second_process() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_reload_scenario_continues_in_a_second_process: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var out := "user://_tests/playtest_reload_%d_%d" % [Time.get_ticks_usec(), randi()]
	var r := PlaytestProcess.run("reload", {"out": out})
	_assert_clean(r, "reload")
	var phases: Array = r.report.get("phases", [])
	assert_eq(phases.size(), 2, "two processes")
	assert_eq(r.exit_codes.size(), 2, "two child processes ran")
	if phases.size() == 2:
		assert_eq(String((phases[0] as Dictionary).get("end", "")), "reload", "the first ends with a reload")
		assert_eq(String((phases[1] as Dictionary).get("end", "")), "done", "the second finishes")
	assert_true(int((r.report.get("counts", {}) as Dictionary).get("checks", 0)) >= 15, "reload runs its checks in both phases")
	print("  [playtest reload] %s in %d processes, %d ms wall" % [r.report.get("result", "?"), r.exit_codes.size(), r.elapsed_ms])
	_remove_tree(r.out_dir)


func test_quest_scenario_plays_1002_in_strict_mode() -> void:
	# The cheapest chain of the every-quest set (scripts/playtest_quests.sh): setup in phase 0, strict play after it,
	# a save and process restart after the accept, every quest check tagged quest:1002.
	if not WorldSidecars.exists():
		print("SKIP test_quest_scenario_plays_1002_in_strict_mode: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var out := "user://_tests/playtest_quest_%d_%d" % [Time.get_ticks_usec(), randi()]
	var r := PlaytestProcess.run("quest", {"out": out, "extra": PackedStringArray(["--quest", "1002"])})
	_assert_clean(r, "quest 1002")
	var st: Dictionary = r.report.get("strict", {})
	assert_true(bool(st.get("enabled", false)) and bool(st.get("ok", false)), "strict and clean: %s" % st)
	assert_eq(int(st.get("console_steps", -1)), 0, "no console step after the setup")
	assert_eq(int(st.get("debug_commands", -1)), 0, "no developer command after the setup")
	assert_eq((r.report.get("phases", []) as Array).size(), 3, "setup, accept + save, restart + finish")
	var pk: Dictionary = (r.report.get("parity", {}) as Dictionary).get("quest:1002", {})
	assert_true(int(pk.get("checks", 0)) >= 20 and int(pk.get("failed", -1)) == 0, "quest:1002 checks %s" % pk)
	var res: Dictionary = ((r.report.get("carry", {}) as Dictionary).get("quest_results", {}) as Dictionary).get("1002", {})
	assert_eq(String(res.get("result", "")), "PASS", "the per-quest verdict")
	print("  [playtest quest 1002] %s: %d checks, strict %s, %d ms wall" % [r.report.get("result", "?"),
		int((r.report.get("counts", {}) as Dictionary).get("checks", 0)), st.get("ok"), r.elapsed_ms])
	_remove_tree(r.out_dir)


func test_kit_helpers_work_in_the_real_game() -> void:
	# PlaytestKit's reference run: AP, a shop by talking, buy and sell, quickslot, drink, equip, checkpoint. The
	# contract helpers (sit, skills, Wooden Boxes) may WARN until their packages are merged.
	if not WorldSidecars.exists():
		print("SKIP test_kit_helpers_work_in_the_real_game: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var out := "user://_tests/playtest_kit_%d_%d" % [Time.get_ticks_usec(), randi()]
	var r := PlaytestProcess.run("kit", {"out": out})
	_assert_clean(r, "kit")
	var names := PackedStringArray()
	for c: Dictionary in r.report.get("checks", []):
		names.append(String(c.get("name", "")))
	for want in ["open_shop: talking to Lucy opens her shop", "close_shop"]:
		assert_has(names, want, "kit check")
	assert_eq(int(((r.report.get("counts", {}) as Dictionary).get("steps", {}) as Dictionary).get("api", -1)), 0,
		"no api fallback")
	for w in r.warnings():
		print("  [playtest kit] WARN " + w.left(160))
	print("  [playtest kit] %s, %d ms wall" % [r.report.get("result", "?"), r.elapsed_ms])
	_remove_tree(r.out_dir)


func test_counter_npc_is_talked_to_on_foot_by_leaning_in() -> void:
	# Regression: talk_to() once filtered approach points by a 1.45 m feet-to-feet distance, so it reported Pan (behind
	# his counter, 1.9 m from the floor) unreachable although the game's talk zone reaches a player at the counter.
	if not WorldSidecars.exists():
		print("SKIP test_counter_npc_is_talked_to_on_foot_by_leaning_in: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var out := "user://_tests/playtest_counter_%d_%d" % [Time.get_ticks_usec(), randi()]
	var r := PlaytestProcess.run("counter", {"out": out})
	_assert_clean(r, "counter")
	var talked := false
	for s: Dictionary in r.report.get("steps", []):
		if String(s.get("name", "")) == "talk_to" and int(s.get("depth", 0)) == 0:
			talked = bool(s.get("ok", false)) and String(s.get("kind", "")) == "play"
	assert_true(talked, "talk_to(16) is a play step that succeeded")
	print("  [playtest counter] %s, %d ms wall" % [r.report.get("result", "?"), r.elapsed_ms])
	_remove_tree(r.out_dir)


func _assert_clean(r: PlaytestProcess, scenario: String) -> void:
	for p in r.problems():
		fail("%s: %s" % [scenario, p])
	assert_false(r.report.is_empty(), "%s: report.json written (exit codes %s): %s" % [scenario, r.exit_codes, r.tail()])
	assert_eq(String(r.report.get("result", "")), "PASS", "%s result" % scenario)
	assert_true(bool(r.report.get("finished", false)), "%s finished" % scenario)
	assert_eq((r.report.get("errors", []) as Array).size(), 0, "%s fatal errors" % scenario)
	assert_true(r.passed(), "%s passed (exit codes %s)" % [scenario, r.exit_codes])


static func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
