class_name PlaytestScenario
extends RefCounted
## Base class of an automated playthrough (docs/runtime/PLAYTEST_HARNESS.md "Writing a scenario"). A scenario is
## game/tools/playtest/scenarios/<name>.gd; `bash scripts/playtest.sh <name>` runs it in the real game.
##
##   extends PlaytestScenario
##
##   func run(d: PlaytestDriver) -> void:
##       await d.new_game("Tester", "female", "541", {"str": 9})
##       var r: Dictionary = await d.walk_route("000000001", "Main")
##       d.check("walked Main", r.ok, str(r.issues))
##
## run() is a coroutine: await every driver call that says "Await it". It is called once per process; after
## d.reload_process() the next process calls it again with d.phase + 1 (branch on d.phase, keep values in d.carry).
## Use d.console() only for setup: the report counts console steps apart from play.

## Plays the scenario. Override it.
func run(_d: PlaytestDriver) -> void:
	pass


## Game-time budget of one phase (seconds). Past it the runner's watchdog stops the run with a "timeout" error.
func max_seconds() -> float:
	return 600.0


## One line for the report: what this scenario covers.
func description() -> String:
	return ""
