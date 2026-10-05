extends TestCase
## Brief Test F through the real main scene in a child process: die in 000000040 and 000001014 (HP 0 through
## Game.change_hp) and once by another system's Events.player_died in 000000001. Each death: MapSession DEAD, the
## player dead, the modal death notice (Esc cannot close it), no saving while dead, OK -> the canonical EXP penalty,
## the canonical returnMap at the respawn player spawn, death.json HP/MP, the player revived with input, a valid
## save; inventory, equipment and quest state unchanged in memory and in the save. Then quit to title and continue
## from the post-death save. Needs the Blender export (INCLUDE_WORLD=1). Checks: scripts/game/checks/shell_checks.gd.


## Contract C6 (the run needs INCLUDE_WORLD=1; without the world it prints SKIP).
func parity_keys() -> Dictionary:
	return {"test_die_in_40_and_1014_respawn_and_reload": ["mechanic:death-respawn", "persistence:respawn-information"]}


func test_die_in_40_and_1014_respawn_and_reload() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_die_in_40_and_1014_respawn_and_reload: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var r := ShellCheckRunner.run("death")
	for f in r.failures:
		fail(f)
	for e in r.script_errors:
		fail("shell script error: " + e)
	assert_true(r.done, "the checks scene did not finish (exit %d): %s" % [r.exit_code, r.tail()])
	assert_true(r.passed >= 60, "expected the full set of death checks, got %d" % r.passed)
	if r.done:
		assert_eq(r.exit_code, 0 if r.failures.is_empty() else 1, "child exit code")
	print("  [death] %d checks passed in %d ms" % [r.passed, r.elapsed_ms])
