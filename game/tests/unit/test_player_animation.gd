extends TestCase
## Which clip of the rigged Beginner the player's gameplay state selects (PlayerAnimator.select, #63), without the art
## pack: the selection is pure. The clips playing on the real rig are pinned in test_player_rig.gd.


func _state(over: Dictionary = {}) -> Dictionary:
	var s := {"dead": false, "seated": false, "hit": false, "climbing": false, "attacking": false, "airborne": false,
		"speed": 0.0, "run_speed": 3.45}
	s.merge(over, true)
	return s


func test_ground_speed_picks_idle_walk_or_run() -> void:
	assert_eq(PlayerAnimator.select(_state()), &"idle", "standing still")
	assert_eq(PlayerAnimator.select(_state({"speed": 0.1})), &"idle", "drifting to a stop is still idle")
	assert_eq(PlayerAnimator.select(_state({"speed": 3.0})), &"walk", "Speed 100 walks (3 m/s)")
	assert_eq(PlayerAnimator.select(_state({"speed": 4.2})), &"run", "a hasted player runs")


func test_airborne_jumps_and_ladders_climb() -> void:
	assert_eq(PlayerAnimator.select(_state({"airborne": true, "speed": 3.0})), &"jump", "any airborne state")
	assert_eq(PlayerAnimator.select(_state({"climbing": true})), &"climb", "ladders, ropes and vines")


func test_one_shots_take_priority_in_gameplay_order() -> void:
	assert_eq(PlayerAnimator.select(_state({"attacking": true, "speed": 3.0})), &"attack", "attack over walk")
	assert_eq(PlayerAnimator.select(_state({"attacking": true, "airborne": true})), &"attack", "a jump attack")
	assert_eq(PlayerAnimator.select(_state({"hit": true, "attacking": true})), &"hit", "a hit interrupts the swing")
	assert_eq(PlayerAnimator.select(_state({"hit": true, "climbing": true})), &"hit", "and the climb")
	assert_eq(PlayerAnimator.select(_state({"seated": true})), &"sit", "seated")
	assert_eq(PlayerAnimator.select(_state({"dead": true, "hit": true, "airborne": true})), &"death", "death wins")


func test_every_selected_clip_is_one_the_beginner_has() -> void:
	var clips := ["idle", "walk", "run", "jump", "climb", "attack", "hit", "sit", "death"]
	for c in PlayerAnimator.CLIPS:
		assert_true(String(c) in clips, "%s is a Beginner clip" % c)
	assert_eq(PlayerAnimator.CLIPS.size(), 9, "all nine are used")
