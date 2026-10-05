extends TestCase
## Former traps stay escapable: the "trap_probe" scenario (no TRAP_MAP / TRAP_LOCAL) lands a player on the surface over
## every spot in its KNOWN_TRAPS list (pockets the playtests found and the Blender source filled, and the map-corner
## slots the Iteration Three stuck-region scan found) and must get back to the map's main traversal graph with real
## input: escapable ground by the live StuckScan graph, a press-Up portal trigger or a trail gate. Needs the Blender
## export (INCLUDE_WORLD=1); prints a SKIP line without it.

const SCENARIO := "res://tools/playtest/scenarios/trap_probe.gd"


func parity_keys() -> Dictionary:
	var keys := ["mechanic:trap-regression-guard"]
	for entry: Array in _known_traps():
		var k := "map:%s" % String(entry[0])
		if not (k in keys):
			keys.append(k)
	return {"test_former_traps_are_escapable": keys}


func test_former_traps_are_escapable() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_former_traps_are_escapable: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var known := _known_traps()
	assert_true(known.size() >= 2, "trap_probe lists its known traps")
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
	assert_eq(probed, known.size(), "every KNOWN_TRAPS spot probed")


## trap_probe.gd's KNOWN_TRAPS ([map, map-local spot, what it was]).
func _known_traps() -> Array:
	var script := load(SCENARIO) as GDScript
	if script == null:
		fail("cannot load %s" % SCENARIO)
		return []
	return script.get_script_constant_map().get("KNOWN_TRAPS", [])
