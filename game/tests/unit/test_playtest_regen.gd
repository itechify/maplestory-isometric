extends TestCase
## Natural HP recovery in the real game: the "regen" playtest scenario (no recovery while walking with real input, then
## one combat.json natural_recovery tick per interval while standing still, never above max HP) runs headless through
## PlaytestProcess and must PASS. Needs the Blender export (INCLUDE_WORLD=1); prints a SKIP line without it.


func test_regen_scenario_passes_in_the_real_game() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_regen_scenario_passes_in_the_real_game: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var out := "user://_tests/playtest_regen_%d_%d" % [Time.get_ticks_usec(), randi()]
	var r := PlaytestProcess.run("regen", {"out": out})
	for p in r.problems():
		fail("regen: %s" % p)
	assert_false(r.report.is_empty(), "regen: report.json written (exit codes %s): %s" % [r.exit_codes, r.tail()])
	assert_eq(String(r.report.get("result", "")), "PASS", "regen result")
	assert_eq((r.report.get("errors", []) as Array).size(), 0, "regen fatal errors")
	for c: Dictionary in r.report.get("checks", []):
		if not bool(c.get("ok", false)):
			fail("regen check failed: %s: %s" % [c.get("name", ""), c.get("details", "")])
