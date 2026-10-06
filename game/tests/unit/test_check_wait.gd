extends TestCase
## CheckWait: the in-game check scenes' waits. A default wait (a load, a warp, a respawn) lasts its 2400 frames and at
## least a minute of wall time, because headless frames can be shorter than a millisecond (test_death_flow's new game
## once gave up after 2400 frames in about 2 s while a threaded island load ran beside two other Godot runs). Short
## settle waits keep their frame budget alone.


func test_a_default_wait_outlasts_fast_frames() -> void:
	# The failure of 2026-10-06: 2400 frames spent in about 1.5 s of wall time.
	assert_true(CheckWait.keep_waiting(2400, CheckWait.DEFAULT_FRAMES, 1500), "2400 fast frames: keep waiting")
	assert_true(CheckWait.keep_waiting(5000, CheckWait.DEFAULT_FRAMES, CheckWait.DEFAULT_MIN_MS - 1), "until the minute")
	assert_false(CheckWait.keep_waiting(2400, CheckWait.DEFAULT_FRAMES, CheckWait.DEFAULT_MIN_MS), "frames and time spent")


func test_frames_are_still_a_floor() -> void:
	assert_true(CheckWait.keep_waiting(100, CheckWait.DEFAULT_FRAMES, CheckWait.DEFAULT_MIN_MS * 2),
		"slow frames: the 2400-frame budget still holds")


func test_short_settle_waits_keep_their_frame_budget() -> void:
	assert_true(CheckWait.keep_waiting(59, 60, 10), "a settle of 60 frames runs its frames")
	assert_false(CheckWait.keep_waiting(60, 60, 10), "and stops after them, however fast they were")
	assert_false(CheckWait.keep_waiting(120, 120, 0))
