extends TestCase
## The gameplay acceptance flow through the real main scene in a child process (real frames, physics, autoloads and
## whatever subsystems exist): title -> new game -> world ready -> player at 000000001 player_spawns[0] -> walk ->
## save -> pause/resume and Esc -> quit to title -> continue -> the same map, position and stats.
## Needs the Blender export (INCLUDE_WORLD=1); prints one SKIP line without it. The checks themselves are in
## scripts/game/checks/shell_checks.gd ("flow").


func test_new_game_save_quit_continue() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_new_game_save_quit_continue: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var r := ShellCheckRunner.run("flow")
	for f in r.failures:
		fail(f)
	for e in r.script_errors:
		fail("shell script error: " + e)
	for i in r.infos:
		print("  [flow] " + i)
	assert_true(r.done, "the checks scene did not finish (exit %d): %s" % [r.exit_code, r.tail()])
	assert_true(r.passed >= 30, "expected the full set of flow checks, got %d" % r.passed)
	if r.done:
		assert_eq(r.exit_code, 0 if r.failures.is_empty() else 1, "child exit code")
	print("  [flow] %d checks passed in %d ms" % [r.passed, r.elapsed_ms])
