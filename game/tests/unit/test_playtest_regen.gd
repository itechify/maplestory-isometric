extends TestCase
## Natural HP recovery and sitting in the real game: the "regen" playtest scenario (recovery.json natural_hp: 6 s still
## + 5 s walking + 4 s still reach one tick, jumping and attacking pause the clock, The Green Relaxer sits the player
## down and adds its own +30 per 10 s, move keys and warps stand up, Up at a real portal while seated stands up and
## uses the portal, the clock survives Quit Game + Continue and the seat does not) runs headless through PlaytestProcess and must PASS. Needs the Blender export (INCLUDE_WORLD=1);
## prints a SKIP line without it.


func parity_keys() -> Dictionary:
	return {"test_regen_scenario_passes_in_the_real_game": ["mechanic:natural-hp-regen",
		"mechanic:natural-hp-regen-pause-walking", "mechanic:natural-hp-regen-pause-jumping",
		"mechanic:natural-hp-regen-pause-attacking", "mechanic:natural-hp-regen-sitting", "mechanic:sitting", "chair:522",
		"mechanic:chair-hp-bonus"]}


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
