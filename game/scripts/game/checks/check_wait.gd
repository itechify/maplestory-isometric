class_name CheckWait
extends RefCounted
## How long the in-game check scenes (ShellChecks, MonsterGameChecks, WorldUiMainChecks) wait for a condition. They
## count frames, and a headless frame with nothing to draw can take well under a millisecond, so the default budget of
## 2400 frames gave a threaded island load about 2 s. In the final evidence run of 2026-10-06, with three Godot runs on
## the machine, test_death_flow's new game had not left LOADING after its 2400 frames (2.5 s with the boot) and
## "new game reaches PLAYING" failed. A wait with the default budget therefore also lasts at least DEFAULT_MIN_MS of
## wall time; the short settle waits (a few dozen frames for a body to land) keep their frame budget alone.

## The frame budget of a default wait (a load, a warp, a respawn).
const DEFAULT_FRAMES := 2400
## The least wall time (ms) a default wait lasts before it gives up.
const DEFAULT_MIN_MS := 60000


## True while a wait that has run `frames` frames and `elapsed_ms` of wall time should go on waiting for its
## condition: until both its frame budget and, for a default-budget wait, DEFAULT_MIN_MS are spent.
static func keep_waiting(frames: int, max_frames: int, elapsed_ms: int) -> bool:
	if frames < max_frames:
		return true
	return max_frames >= DEFAULT_FRAMES and elapsed_ms < DEFAULT_MIN_MS
