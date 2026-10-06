extends TestCase
## The Beginner skills in the real game: the "test_skills" playtest scenario (SP from a level-up, "+" in the Skills
## window by mouse, keys 1-3 bound in the window, a Snail killed by Three Snails alone, Recovery's canonical heal and
## cooldown, Nimble Feet's walk speed, and a Quit Game / Continue that keeps the levels, bindings and cooldowns) runs
## headless through PlaytestProcess and must PASS. Needs the Blender export (INCLUDE_WORLD=1); prints a SKIP line
## without it.


func parity_keys() -> Dictionary:
	return {
		"test_skills_scenario_passes_in_the_real_game": ["skill:0001000", "skill:0001001", "skill:0001002",
			"mechanic:sp-allocation", "mechanic:skill-persistence", "ui:skill-window", "ui:sp-notification",
			"persistence:skills", "persistence:sp", "persistence:quickslots", "persistence:skill-cooldowns-buffs"],
	}


func test_skills_scenario_passes_in_the_real_game() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_skills_scenario_passes_in_the_real_game: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var out := "user://_tests/playtest_skills_%d_%d" % [Time.get_ticks_usec(), randi()]
	var r := PlaytestProcess.run("test_skills", {"out": out})
	for p in r.problems():
		fail("test_skills: %s" % p)
	assert_false(r.report.is_empty(), "test_skills: report.json written (exit codes %s): %s" % [r.exit_codes, r.tail()])
	assert_eq(String(r.report.get("result", "")), "PASS", "test_skills result")
	assert_eq((r.report.get("errors", []) as Array).size(), 0, "test_skills fatal errors")
	for c: Dictionary in r.report.get("checks", []):
		if not bool(c.get("ok", false)):
			fail("test_skills check failed: %s: %s" % [c.get("name", ""), c.get("details", "")])
