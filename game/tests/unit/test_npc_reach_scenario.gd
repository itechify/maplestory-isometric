extends TestCase
## Every MeowDB NPC can be talked to on foot (brief Phase 14): the "npcs" playtest scenario runs headless through
## PlaytestProcess, as scripts/playtest.sh runs it, and must PASS with hard checks only: each of the 21 NPCs reached
## from its map's arrival with real input (routes, stairs, the grid planner) and the interact key, and a player pressing
## on toward it at least 0.4 m inside its talk zone (docs/runtime/WORLD_RUNTIME.md "NPC talk zones"). Needs the Blender
## export (INCLUDE_WORLD=1); prints a SKIP line without it.

const NPC_COUNT := 21


func test_every_npc_is_talked_to_on_foot_with_margin() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_every_npc_is_talked_to_on_foot_with_margin: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var out := "user://_tests/playtest_npcs_%d_%d" % [Time.get_ticks_usec(), randi()]
	var r := PlaytestProcess.run("npcs", {"out": out})
	for p in r.problems():
		fail("npcs: %s" % p)
	assert_false(r.report.is_empty(), "npcs: report.json written (exit codes %s): %s" % [r.exit_codes, r.tail()])
	assert_eq(String(r.report.get("result", "")), "PASS", "npcs result")
	assert_true(bool(r.report.get("finished", false)), "npcs finished")
	assert_eq((r.report.get("errors", []) as Array).size(), 0, "npcs fatal errors")
	var counts: Dictionary = r.report.get("counts", {})
	assert_eq(int(counts.get("warnings", -1)), 0, "no soft checks: every NPC is a hard check")
	assert_eq(int((counts.get("steps", {}) as Dictionary).get("api", -1)), 0, "no shell fallback")
	var reached := 0
	var margins := 0
	for c: Dictionary in r.report.get("checks", []):
		var cname := String(c.get("name", ""))
		if not bool(c.get("ok", false)):
			fail("npcs check failed: %s: %s" % [cname, c.get("details", "")])
		if cname.contains("can be talked to on foot") and bool(c.get("ok", false)):
			reached += 1
		if cname.contains("inside the talk zone") and bool(c.get("ok", false)):
			margins += 1
		assert_false(bool(c.get("soft", false)), "a soft check in npcs: " + cname)
	assert_eq(reached, NPC_COUNT, "NPCs talked to on foot")
	assert_eq(margins, NPC_COUNT, "NPCs with a player at least 0.4 m inside the talk zone")
	# Only console warps (one per NPC) are setup; every walk and talk is play.
	for s: Dictionary in r.report.get("steps", []):
		if String(s.get("kind", "")) == "console" and int(s.get("depth", 0)) == 0:
			assert_true(String(s.get("detail", "")).begins_with("warp "), "unexpected console step: %s" % s.get("detail", ""))
	var margin_records: Dictionary = (r.report.get("carry", {}) as Dictionary).get("npc_margins", {})
	assert_eq(margin_records.size(), NPC_COUNT, "carry.npc_margins has every NPC")
	for id: String in margin_records:
		var m: Dictionary = margin_records[id]
		assert_true(bool(m.get("reached", false)), "NPC %s reached" % id)
		assert_true(float(m.get("pressed_m", 0.0)) <= -0.4, "NPC %s: %.3f m inside the talk zone pressed in" % [id, -float(m.get("pressed_m", 0.0))])
	for n: Variant in r.report.get("notes", []):
		if String(n).contains("NPCs reached on foot") or String(n).contains("margin "):
			print("  [npcs] " + String(n))
	print("  [npcs] %s: %d checks, %d ms wall" % [r.report.get("result", "?"), int(counts.get("checks", 0)), r.elapsed_ms])
	if r.passed():
		_remove_tree(r.out_dir)


static func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
