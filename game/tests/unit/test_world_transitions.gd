extends TestCase
## L2-lite transitions with real physics frames (MAP_ARCHITECTURE.md section 4.13): press Up at all 47 portals
## (arrival within 0.1 m, grounded within the frame budget, exact event order, no re-trigger while Up is held), doors in
## and out, death respawns, the load fallback chain, monster population and respawn, fall recovery and NPC
## interaction. The checks need frames, so they run in their own headless process
## (res://scenes/world/checks/world_checks.tscn); this test launches it and reports every failed check.
## It runs twice: with the world's WorldTestPlayer capsule, and with the game's PlayerController
## (scenes/actors/player.tscn, `--player real`), which also walks out through every portal to prove the warp-mode
## containment rings hold the real body. Needs the Blender export (INCLUDE_WORLD=1); prints one SKIP line without it.

const CHECK_SCENE := "res://scenes/world/checks/world_checks.tscn"
const PLAYER_SCENE := "res://scenes/actors/player.tscn"
## Watchdog for the child process (frames at --fixed-fps 60); a full real-player run takes about 25k frames.
const QUIT_AFTER_FRAMES := 60000


func test_l2_world_transitions() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_l2_world_transitions: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	_run_checks(PackedStringArray(), "capsule")


func test_l2_world_transitions_with_the_real_player() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_l2_world_transitions_with_the_real_player: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	if not ResourceLoader.exists(PLAYER_SCENE):
		print("SKIP test_l2_world_transitions_with_the_real_player: %s does not exist yet" % PLAYER_SCENE)
		return
	_run_checks(PackedStringArray(["--", "--player", "real"]), "real player")


func _run_checks(user_args: PackedStringArray, label: String) -> void:
	var out: Array = []
	var args := PackedStringArray(["--headless", "--fixed-fps", "60", "--quit-after", str(QUIT_AFTER_FRAMES),
		"--path", ProjectSettings.globalize_path("res://"), CHECK_SCENE])
	args.append_array(user_args)
	var t0 := Time.get_ticks_msec()
	var code := OS.execute(OS.get_executable_path(), args, out, true)
	var text := "\n".join(PackedStringArray(out))
	var done := false
	var fails := 0
	for line in text.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("WORLD_CHECK FAIL"):
			fails += 1
			fail("[%s] %s" % [label, l.trim_prefix("WORLD_CHECK FAIL ")])
		elif l.begins_with("WORLD_SECTION") or l.begins_with("WORLD_BUILD") or l.begins_with("WORLD_PLAYER"):
			print("  [%s] %s" % [label, l])
		elif l.begins_with("WORLD_CHECKS_DONE"):
			done = true
			print("  [%s] %s (%d ms)" % [label, l, Time.get_ticks_msec() - t0])
		elif l.begins_with("SCRIPT ERROR") or l.contains("Parse Error"):
			fail("[%s] child process: %s" % [label, l])
	assert_true(done, "[%s] the checks scene did not finish (exit %d); output tail: %s" % [label, code, text.right(1500)])
	if done:
		assert_eq(code, 0 if fails == 0 else 1, "[%s] child exit code" % label)
