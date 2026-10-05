extends TestCase
## Brief Test F, death -> quit -> reload, as a real quit: three child processes of the real main scene share one
## save directory. The first starts a new game, dies in 000000040 and closes the window while the death notice is up;
## the second continues (the player must wake up in 40's return town with the canonical EXP penalty taken exactly
## once, death.json HP/MP, inventory and quest state intact), then dies in 000001014 and closes the window; the third
## continues and checks the 1014 death the same way. Needs the Blender export (INCLUDE_WORLD=1). The checks are the
## "death_quit" / "death_reload" scenarios of scripts/game/checks/shell_checks.gd.


func test_death_quit_reload_in_40_and_1014() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_death_quit_reload_in_40_and_1014: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var dir := "user://_tests/death_quit_%d_%d" % [Time.get_ticks_usec(), randi()]
	var shared := PackedStringArray(["--save-dir", dir, "--keep-saves"])
	var links := [
		["death_quit", "000000040", "new game, die in 40, quit", 8],
		["death_quit", "000001014", "reload after 40, die in 1014, quit", 18],
		["death_reload", "", "reload after 1014", 12],
	]
	for link: Array in links:
		var extra := PackedStringArray(shared)
		if String(link[1]) != "":
			extra.append_array(["--map", String(link[1])])
		var r := ShellCheckRunner.run(String(link[0]), extra)
		for f in r.failures:
			fail("%s: %s" % [link[2], f])
		for e in r.script_errors:
			fail("%s: shell script error: %s" % [link[2], e])
		assert_true(r.done, "%s: the checks scene did not finish (exit %d): %s" % [link[2], r.exit_code, r.tail()])
		assert_true(r.passed >= int(link[3]), "%s: expected at least %d checks, got %d" % [link[2], link[3], r.passed])
		if r.done:
			assert_eq(r.exit_code, 0 if r.failures.is_empty() else 1, "%s: child exit code" % link[2])
		print("  [%s] %d checks passed in %d ms" % [link[2], r.passed, r.elapsed_ms])
		if not r.failures.is_empty() or not r.done:
			break  # the next link would only report the same broken save
	_remove_tree(dir)


func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
