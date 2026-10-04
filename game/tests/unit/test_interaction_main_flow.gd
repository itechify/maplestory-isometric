extends TestCase
## The world UI inside the REAL game, in a child process: res://scenes/main.tscn (the shell, GameSession,
## SubsystemInstaller, HUD, monster system, death controller) driven by
## res://scripts/systems/interaction/sandbox/world_ui_main_checks.tscn with real frames, physics and key presses:
##   Roger's Apple: prompt, marker and tag; F; Esc through the shell's window stack; Y accepts (the accept summary shows on the instructions card; Enter closes it); Space on the last line
##   ends the chat without making the player jump; the chat sits above the HUD bar; the completion page and summary.
##   A portal's prompt names its destination and Up enters it; at a ladder the prompt says Climb and F climbs (no chat).
##   Lucy: greeting -> shop; mashing Enter/Space buys nothing; Right + Enter buys at the canonical price; selling from
##   the Use tab at the sell-back price; insufficient mesos and a full inventory refused; Esc leaves; Esc again pauses.
##   Snail Hunting Ground I: the monster system's kills land as drops; Z picks up with a notice; the map round trip keeps
##   them; a full inventory: the drop stays, the refusal is said once while Z is held.
##   Sam's Suggestion: Sam's offer, Backspace, the console's kill all until 10 Snails, every drop picked up with Z, Mai's
##   ready marker, the completion summary and the reward.
##   Robustness: WASD/arrows in a quiz menu never walk; Up in a menu inside a portal never warps; a warp closes the chat
##   and the shop; a shop request replaces a chat; a death closes the chat.
##   A death with the shop open; quit to title and continue (the new loot system and its console commands).
## Needs the Blender export (INCLUDE_WORLD=1); prints one SKIP line without it.

const CHECK_SCENE := "res://scripts/systems/interaction/sandbox/world_ui_main_checks.tscn"
## Watchdog for the child process (frames at --fixed-fps 60).
const QUIT_AFTER_FRAMES := 60000
## Every check the scene runs passes; a flow that returns early (fewer checks) fails the test.
const EXPECTED_CHECKS := 96


func test_world_ui_in_the_real_game() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_world_ui_in_the_real_game: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var out: Array = []
	var args := PackedStringArray(["--headless", "--fixed-fps", "60", "--quit-after", str(QUIT_AFTER_FRAMES),
		"--path", ProjectSettings.globalize_path("res://"), CHECK_SCENE, "--", "--scenario", "main"])
	var t0 := Time.get_ticks_msec()
	var code := OS.execute(OS.get_executable_path(), args, out, true)
	var text := "\n".join(PackedStringArray(out))
	var passed := 0
	var done := false
	var lines := text.split("\n")
	for i in lines.size():
		var l := lines[i].strip_edges()
		if l.begins_with("WORLDUI_CHECK PASS"):
			passed += 1
		elif l.begins_with("WORLDUI_CHECK FAIL"):
			fail(l.trim_prefix("WORLDUI_CHECK FAIL "))
		elif l.begins_with("WORLDUI_INFO"):
			print("  [worldui] " + l.trim_prefix("WORLDUI_INFO "))
		elif l.begins_with("WORLDUI_CHECKS_DONE"):
			done = true
		elif l.begins_with("SCRIPT ERROR"):
			# Script errors raised in this system's own files fail the test; other systems report their own.
			var where := l
			for j in range(i + 1, mini(i + 4, lines.size())):
				where += " " + lines[j].strip_edges()
			for own in ["res://scripts/systems/interaction/", "res://scripts/actors/loot/", "res://scripts/actors/npcs/",
					"res://scripts/ui/npc/"]:
				if where.contains(own):
					fail("script error in the world UI: " + where)
					break
	assert_true(done, "the checks scene did not finish (exit %d): %s" % [code, text.right(1500)])
	assert_true(passed >= EXPECTED_CHECKS, "expected the full set of %d checks, got %d" % [EXPECTED_CHECKS, passed])
	if done:
		assert_eq(code, 0, "child exit code")
	print("  [worldui] %d checks passed in %d ms" % [passed, Time.get_ticks_msec() - t0])
