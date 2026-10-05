extends TestCase
## The monster system in the real game (res://scenes/main.tscn, every subsystem the shell installs, real frames,
## physics and input) through res://scenes/actors/monster_game_checks.tscn in a child Godot process (the unit-test
## runner cannot await frames): the debug console's "spawn 2 3" and "kill all" end to end (EXP, drops on the ground,
## slots, the respawn tick), the see-through silhouette by distance to the player (on near, none far, dropped by a
## kill) and real mouse clicks (a HUD button never swings, nor the pause menu's Resume, the world does, J does).
## Needs the Blender export (INCLUDE_WORLD=1); prints one SKIP line without it. The checks themselves are in
## scripts/actors/monsters/monster_game_checks.gd.

const CHECK_SCENE := "res://scenes/actors/monster_game_checks.tscn"
## Watchdog for the child process (frames at --fixed-fps 60).
const QUIT_AFTER_FRAMES := 20000


func test_console_and_mouse_in_the_real_game() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_console_and_mouse_in_the_real_game: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var out: Array = []
	var args := PackedStringArray(["--headless", "--fixed-fps", "60", "--quit-after", str(QUIT_AFTER_FRAMES),
		"--path", ProjectSettings.globalize_path("res://"), CHECK_SCENE])
	var t0 := Time.get_ticks_msec()
	var code := OS.execute(OS.get_executable_path(), args, out, true)
	var text := "\n".join(PackedStringArray(out))
	var lines := text.split("\n")
	var passes := 0
	var done := false
	for i in lines.size():
		var l := lines[i].strip_edges()
		if l.begins_with("MONSTER_CHECK PASS"):
			passes += 1
		elif l.begins_with("MONSTER_CHECK FAIL"):
			fail(l.trim_prefix("MONSTER_CHECK FAIL "))
		elif l.begins_with("MONSTER_INFO"):
			print("  [monster game] " + l.trim_prefix("MONSTER_INFO "))
		elif l.begins_with("MONSTER_CHECKS_DONE"):
			done = true
		elif l.begins_with("SCRIPT ERROR"):
			# Errors raised from this system's own scripts fail here; other systems report their own.
			var at := " ".join(PackedStringArray(Array(lines.slice(i, mini(i + 4, lines.size()))).map(func(s: String) -> String: return s.strip_edges())))
			if at.contains("res://scripts/actors/monsters/") or at.contains("res://scripts/actors/combat/"):
				fail("script error in the child: " + at)
	assert_true(done, "the checks scene did not finish (exit %d): %s" % [code, text.right(1500)])
	assert_true(passes >= 36, "expected the full set of checks, got %d" % passes)
	if done:
		assert_eq(code, 0, "child exit code")
	print("  [monster game] %d checks passed in %d ms" % [passes, Time.get_ticks_msec() - t0])
