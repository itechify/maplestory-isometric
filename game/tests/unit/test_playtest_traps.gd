extends TestCase
## Former traps stay escapable: the "trap_probe" scenario (no TRAP_MAP / TRAP_LOCAL) lands a player on the surface over
## every spot in its KNOWN_TRAPS list (pockets the playtests found and the Blender source filled) and must walk out with
## real input. Needs the Blender export (INCLUDE_WORLD=1); prints a SKIP line without it.


func test_former_traps_are_escapable() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_former_traps_are_escapable: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var out := "user://_tests/playtest_traps_%d_%d" % [Time.get_ticks_usec(), randi()]
	var r := PlaytestProcess.run("trap_probe", {"out": out})
	for p in r.problems():
		fail("trap_probe: %s" % p)
	assert_false(r.report.is_empty(), "trap_probe: report.json written (exit codes %s): %s" % [r.exit_codes, r.tail()])
	assert_eq(String(r.report.get("result", "")), "PASS", "trap_probe result")
	var probed := 0
	for c: Dictionary in r.report.get("checks", []):
		if String(c.get("name", "")).contains("is not a trap"):
			probed += 1
		if not bool(c.get("ok", false)):
			fail("trap_probe check failed: %s: %s" % [c.get("name", ""), c.get("details", "")])
	assert_eq(probed, 2, "both known former traps probed")
