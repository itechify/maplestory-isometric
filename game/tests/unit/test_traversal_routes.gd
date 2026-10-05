extends TestCase
## L2 route sweep (MAP_ARCHITECTURE.md section 4.13 "Per map", PLAYER_AND_CAMERA.md "Route sweep"): every exported
## route of all 25 maps, in both directions, walked by the RouteBot driving the game's PlayerController on the map's
## exported collision (tools/traversal_bot.gd). The source world is clean (blender_export.md round 2: 360 / 360), so
## any stall, fall or timeout fails. Needs the export (INCLUDE_WORLD=1); prints one SKIP line without it.


func test_every_route_of_every_map_both_ways() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_every_route_of_every_map_both_ways: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var report := TraversalBot.sweep(db())
	print("  route sweep: %d maps, %d runs, %d failed (%d ms)" % [int(report.maps), int(report.runs), int(report.failed), int(report.ms)])
	assert_eq(int(report.maps), db().ids("maps").size(), "every map swept")
	var expected_runs := 0
	var side := WorldSidecars.load_dir()
	for id in (report.per_map as Dictionary):
		for r in side.chunk(String(report.per_map[id].slug)).get("routes", []):
			expected_runs += 1 if bool((r as Dictionary).get("one_way", false)) else 2
	assert_eq(int(report.runs), expected_runs, "every route, both ways (one_way routes once)")
	assert_true(int(report.runs) >= 300, "the export's routes were found (%d runs)" % int(report.runs))
	var lines: PackedStringArray = []
	for r: Dictionary in report.failures:
		lines.append(String(r.report))
	assert_eq(int(report.failed), 0, "route failures:\n  " + "\n  ".join(lines))


func test_a_single_map_by_slug_or_id() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_a_single_map_by_slug_or_id: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var by_slug := TraversalBot.sweep(db(), PackedStringArray(["MushroomTown_10000"]))
	assert_eq(int(by_slug.maps), 1, "one map by slug")
	assert_true((by_slug.per_map as Dictionary).has("000000010"), "slug resolved to its MeowDB id")
	var by_id := TraversalBot.sweep(db(), PackedStringArray(["000000010"]))
	assert_eq(int(by_id.runs), int(by_slug.runs), "same runs by id")
