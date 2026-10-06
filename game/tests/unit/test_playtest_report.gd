extends TestCase
## The playtest harness's pure parts (docs/runtime/PLAYTEST_HARNESS.md): PlaytestReport (checks, soft checks, step
## counts by kind, PASS rules, the JSON round trip that a reload_process relies on, report.md), the walker's analog
## input (PlaytestInput.screen_move_for turns a world direction into the move_* strengths KeyboardInput maps back),
## the action-to-key lookup and PlaytestDriver.diff.


## Contract C6: none of these tests proves a canonical value; they prove the harness that carries the parity keys.
func parity_keys() -> Dictionary:
	return {}


func _report() -> PlaytestReport:
	var r := PlaytestReport.new()
	r.scenario = "unit"
	r.seed_value = 7
	return r


func test_checks_soft_checks_and_pass_rules() -> void:
	var r := _report()
	assert_false(r.passed(), "an unfinished report never passes")
	r.finished = true
	assert_false(r.passed(), "a report without checks never passes")
	r.add_check(0, "a", true, "", 0.0, -1)
	assert_true(r.passed(), "one passing check")
	r.add_check(0, "known issue", false, "why", 1.0, -1, true)
	assert_true(r.passed(), "a soft check that does not hold is a warning, not a failure")
	assert_eq(r.warnings().size(), 1, "warnings")
	assert_eq(r.failed_checks().size(), 0, "no hard failure")
	r.add_check(0, "b", false, "broken", 2.0, -1)
	assert_false(r.passed(), "a failed check fails the run")
	assert_eq(r.result_text(), "FAIL")
	var r2 := _report()
	r2.finished = true
	r2.add_check(0, "a", true, "", 0.0, -1)
	r2.add_error(0, "script", "res://x.gd:1 in f: boom")
	assert_false(r2.passed(), "a fatal error fails the run")
	var r3 := _report()
	r3.reload_requested = true
	assert_eq(r3.result_text(), "RELOADING", "a phase that asked for a reload")


func test_step_counts_are_top_level_by_kind() -> void:
	var r := _report()
	var a := r.begin_step(0, PlaytestReport.KIND_PLAY, "talk_to", "3", 0.0, 0)
	var b := r.begin_step(0, PlaytestReport.KIND_PLAY, "walk_to", "npc", 0.0, 0)
	(r.steps[b] as Dictionary)["depth"] = 1
	r.end_step(b, true, "", 2.0, 100)
	r.end_step(a, true, "", 3.0, 150)
	r.begin_step(0, PlaytestReport.KIND_CONSOLE, "console", "warp 40", 3.0, 150)
	r.begin_step(0, PlaytestReport.KIND_API, "new_game", "", 3.0, 150)
	var c := r.step_counts()
	assert_eq(int(c["play"]), 1, "the nested walk is part of its talk_to")
	assert_eq(int(c["console"]), 1)
	assert_eq(int(c["api"]), 1)
	assert_near(float((r.steps[a] as Dictionary)["game_s"]), 3.0, 1e-6, "step game time")
	assert_near(float((r.steps[a] as Dictionary)["wall_s"]), 0.15, 1e-6, "step wall time")


func test_round_trip_keeps_carry_types_and_writes_markdown() -> void:
	var r := _report()
	r.add_check(0, "a | b", true, "x", 0.0, -1)
	r.add_check(0, "known", false, "warned", 0.0, -1, true)
	r.carry = {"level": 3, "position": Vector3(1.5, 2.0, -3.25), "items": {"use": [{"id": "2000000", "qty": 4}]}}
	r.reload_requested = true
	r.phases.append({"phase": 0, "game_s": 12.5, "wall_s": 2.0, "end": "reload"})
	var dir := ProjectSettings.globalize_path("user://_tests/playtest_report_%d_%d" % [Time.get_ticks_usec(), randi()])
	r.out_dir = dir
	assert_eq(r.write(), OK, "write")
	var back := PlaytestReport.from_file(dir)
	assert_true(back != null, "read back")
	if back == null:
		return
	assert_eq(typeof(back.carry["level"]), TYPE_INT, "an int stays an int across the reload")
	assert_eq(back.carry["position"], Vector3(1.5, 2.0, -3.25), "a Vector3 stays a Vector3")
	assert_eq(PlaytestDriver.diff(back.carry["items"], r.carry["items"]), "", "nested values")
	assert_true(back.reload_requested and not back.finished, "the reload request survives")
	assert_eq(back.checks.size(), 2)
	assert_eq(back.phases.size(), 1)
	var md := FileAccess.get_file_as_string(dir.path_join("report.md"))
	assert_true(md.begins_with("# Playtest: unit - RELOADING"), md.left(60))
	assert_true(md.contains("| WARN | known |"), "soft check shown as WARN")
	assert_true(md.contains("a \\| b"), "pipes escaped in the table")
	for f in ["report.json", "report.md"]:
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func test_checks_carry_parity_keys_through_the_round_trip() -> void:
	var r := _report()
	r.add_check(0, "1005 rewards", true, "", 0.0, -1, false, ["quest:1005", "quest:1005", "item:347"])
	r.add_check(0, "1005 marker", false, "warned", 0.0, -1, true, ["quest:1005"])
	r.add_check(0, "plain", true, "", 0.0, -1)
	assert_eq(r.checks[0]["parity"], ["quest:1005", "item:347"], "keys are kept once, in order")
	assert_false((r.checks[2] as Dictionary).has("parity"), "a check without keys carries none")
	var sum := r.parity_summary()
	assert_eq(int((sum["quest:1005"] as Dictionary)["checks"]), 2)
	assert_eq(int((sum["quest:1005"] as Dictionary)["passed"]), 1)
	assert_eq(int((sum["quest:1005"] as Dictionary)["warned"]), 1)
	assert_eq(int((sum["item:347"] as Dictionary)["passed"]), 1)
	var d := r.to_dict()
	assert_eq(int((d["counts"] as Dictionary)["parity_keys"]), 2, "counts.parity_keys")
	var back := PlaytestReport.from_dict(JSON.parse_string(JSON.stringify(PlaytestReport._plain(d))))
	assert_eq(Array((back.checks[0] as Dictionary)["parity"]), ["quest:1005", "item:347"], "report.json keeps them")
	var md := r.to_markdown()
	assert_true(md.contains("## Parity keys"), "report.md lists the keys")
	assert_true(md.contains("| quest:1005 | 2 | 1 | 0 | 1 |"), md)


func test_screen_move_maps_back_onto_the_world_direction() -> void:
	# KeyboardInput: wish = right * mv.x + forward * mv.y (InputSource.world_move); screen_move_for inverts it.
	var axes := [[Vector3(1, 0, 1).normalized(), Vector3(1, 0, -1).normalized()],
		[Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(0.8, 0, 0.6), Vector3(0.6, 0, -0.8)]]
	for ax: Array in axes:
		var right: Vector3 = ax[0]
		var forward: Vector3 = ax[1]
		for deg in range(0, 360, 30):
			var dir := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(deg))
			var mv := PlaytestInput.screen_move_for(dir, right, forward)
			var back := right * mv.x + forward * mv.y
			assert_near(back.x, dir.x, 1e-4, "x at %d deg" % deg)
			assert_near(back.z, dir.z, 1e-4, "z at %d deg" % deg)
			assert_true(mv.length() <= 1.0001, "within the stick's range")
	assert_eq(PlaytestInput.screen_move_for(Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD), Vector2.ZERO, "no direction")
	var half := PlaytestInput.screen_move_for(Vector3(0.5, 0, 0), Vector3.RIGHT, Vector3.FORWARD)
	assert_near(half.length(), 0.5, 1e-4, "a slow step keeps its strength")


func test_actions_press_their_first_keyboard_binding() -> void:
	for action: String in ["jump", "attack", "pickup", "interact", "portal_enter", "menu"]:
		var want: Variant = null
		for b: Variant in Controls.BINDINGS[action]:
			if typeof(b) == TYPE_INT:
				want = b
				break
		assert_eq(int(PlaytestInput.key_for_action(StringName(action))), int(want), action)
	assert_eq(PlaytestInput.key_for_action(&"no_such_action"), KEY_NONE, "unknown action")


func test_diff_compares_values_with_tolerance() -> void:
	assert_eq(PlaytestDriver.diff({"a": 1, "b": [1, 2]}, {"a": 1.0, "b": [1, 2]}), "", "int equals the same float")
	assert_eq(PlaytestDriver.diff({"a": 1}, {"a": 2}), "$.a: 1 != 2")
	assert_eq(PlaytestDriver.diff({"a": 1}, {}), "$.a missing")
	assert_eq(PlaytestDriver.diff({}, {"z": 1}), "$.z appeared")
	assert_eq(PlaytestDriver.diff([1, 2], [1]), "$: size 2 != 1")
	assert_eq(PlaytestDriver.diff("x", &"x"), "", "String and StringName")
	assert_eq(PlaytestDriver.diff(Vector3.ONE, Vector3.ONE), "")
