extends TestCase
## The player is the pack's rigged Beginner (#63): the preset follows the character's gender, each gameplay state plays
## its clip on the rig, animation never moves the body (the hitbox and the feet agree through a jump), the procedural
## motions a clip covers never run, the seated Beginner sits on The Green Relaxer, and the X-ray outline follows the
## skinned pose. Needs the art pack installed (bash scripts/art_pack.sh fetch); every test prints SKIP without it.
## The pack-free selection rule is test_player_animation.gd; the placeholder's own motions are pinned at the end.

const TICK := 1.0 / 60.0

var rig: MonsterTestRig
var art: ArtPack


func before_each() -> void:
	art = ArtPack.load_installed()
	rig = MonsterTestRig.create(db(), 63)
	rig.floor(40.0)


func after_each() -> void:
	rig.free_all()


func _skip(test: String) -> bool:
	if art.present():
		return false
	print("SKIP %s: no art pack installed (bash scripts/art_pack.sh fetch)" % test)
	return true


## The player with PlayerCombat attached and a PlayerVisual ("Visual", no blob shadow) driven by hand.
func _player(gender: String = "male") -> Array:
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var vis := PlayerVisual.new()
	vis.name = "Visual"
	vis.blob_shadow = false
	vis.gender = gender
	p.add_child(vis)
	vis.set_process(false)
	return [p, vis]


func _tick(vis: PlayerVisual, n: int = 1, each: Callable = Callable()) -> void:
	for i in n:
		rig.tick()
		vis.advance(TICK)
		if each.is_valid():
			each.call()


func _playing(vis: PlayerVisual) -> String:
	var ap: AnimationPlayer = vis.model.find_child("AnimationPlayer", true, false)
	return String(ap.current_animation) if ap != null else "(no AnimationPlayer)"


func test_the_player_is_the_beginner_preset_for_the_gender() -> void:
	if _skip("test_the_player_is_the_beginner_preset_for_the_gender"):
		return
	var male: PlayerVisual = _player("male")[1]
	assert_true(male.rigged(), "the pack's rig, not the placeholder")
	assert_eq(male.preset, "Beginner_Male", "male -> Beginner_Male")
	assert_true(male.model.find_child("Skeleton3D", true, false) is Skeleton3D, "a skeleton under the model")
	assert_near(ArtImport.visual_aabb(male.model).size.y, 1.5, 0.01, "at the character scale: the 1.5 m body")
	assert_true(male.model.find_child("Hat_*", true, false) == null, "the male Beginner wears no hat")
	rig.free_all()
	rig = MonsterTestRig.create(db(), 63)
	rig.floor(40.0)
	var female: PlayerVisual = _player("female")[1]
	assert_eq(female.preset, "Beginner_Female", "female -> Beginner_Female")
	assert_true(female.model.find_child("Hat_*", true, false) != null, "the female Beginner's hair bow (Hat_ meshes)")


func test_each_gameplay_state_plays_its_clip() -> void:
	if _skip("test_each_gameplay_state_plays_its_clip"):
		return
	var pair := _player()
	var p: PlayerController = pair[0]
	var vis: PlayerVisual = pair[1]
	_tick(vis, 10)
	assert_eq(_playing(vis), "idle", "standing")
	rig.w.bot.world_dir = Vector3.RIGHT
	_tick(vis, 30)
	assert_eq(_playing(vis), "walk", "walking at Speed 100")
	p.model.set_stats(150.0, 100.0)
	_tick(vis, 30)
	assert_eq(_playing(vis), "run", "faster than a Speed 100 walk")
	p.model.set_stats(100.0, 100.0)
	rig.w.bot.world_dir = Vector3.ZERO
	_tick(vis, 30)
	rig.w.bot.press(&"jump")
	_tick(vis, 6)
	assert_eq(_playing(vis), "jump", "airborne")
	_tick(vis, 90)
	assert_eq(_playing(vis), "idle", "landed")
	rig.w.bot.press(&"attack")
	_tick(vis, 3)
	assert_eq(_playing(vis), "attack", "a basic attack")
	_tick(vis, 90)
	p.apply_knockback(Vector3.LEFT)
	_tick(vis, 3)
	assert_eq(_playing(vis), "hit", "knocked back")
	_tick(vis, 150)
	assert_true(p.sit("522"), "sits on The Green Relaxer")
	_tick(vis, 3)
	assert_eq(_playing(vis), "sit", "seated")
	p.stand_up()
	_tick(vis, 10)
	p.die()
	_tick(vis, 3)
	assert_eq(_playing(vis), "death", "dead")


func test_climbing_a_rope_plays_climb() -> void:
	if _skip("test_climbing_a_rope_plays_climb"):
		return
	var pair := _player()
	var p: PlayerController = pair[0]
	var vis: PlayerVisual = pair[1]
	var rope := ClimbableDef.from_sidecar({"name": "R", "kind": "rope", "bottom": [0.3, 0.0, 0.0], "top": [0.3, 4.0, 0.0],
		"foot_ground": [0.3, 0.0, 0.0], "top_exit": [0.3, 4.0, -0.5], "facing_xz": [1.0, 0.0], "descend_only": false})
	p.set_climbables([rope])
	rig.w.bot.press(&"portal_enter")
	_tick(vis, 2)
	assert_true(p.is_climbing(), "on the rope")
	rig.w.bot.climb = 1.0
	_tick(vis, 20)
	assert_eq(_playing(vis), "climb", "climbing")


func _bone_y(sk: Skeleton3D, bone: String) -> float:
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin.y


func test_the_hitbox_and_the_feet_agree_through_a_full_jump() -> void:
	if _skip("test_the_hitbox_and_the_feet_agree_through_a_full_jump"):
		return
	var pair := _player()
	var p: PlayerController = pair[0]
	var vis: PlayerVisual = pair[1]
	var sk: Skeleton3D = vis.model.find_child("Skeleton3D", true, false)
	_tick(vis, 20)
	var rest_foot := _bone_y(sk, "foot.L") - p.global_position.y
	rig.w.bot.press(&"jump")
	var apex := 0.0
	var jumped := false
	var worst_root := 0.0
	var worst_offset := 0.0
	var feet_band := Vector2(INF, -INF)
	for i in 120:
		_tick(vis)
		jumped = jumped or vis.current_clip() == &"jump"
		apex = maxf(apex, p.global_position.y)
		# The body's feet as drawn: the hitbox's, plus the controller's own step smoothing after a snap (it eases a
		# landing's snap down over visual_step_smoothing; not a clip, not a procedural motion).
		var feet := p.global_position.y + p.presentation_offset.y
		# The root bone (the rig's ground point) stays on the body's feet: the clip lifts nothing.
		worst_root = maxf(worst_root, absf(_bone_y(sk, "root") - feet))
		# The visual adds nothing vertical either.
		worst_offset = maxf(worst_offset, absf(vis.global_position.y - feet))
		for foot in ["foot.L", "foot.R"]:
			var y := _bone_y(sk, foot) - feet
			feet_band = Vector2(minf(feet_band.x, y), maxf(feet_band.y, y))
		if i > 10 and p.is_grounded():
			break
	assert_true(jumped, "the jump clip played")
	assert_true(apex > 0.5, "physics lifted the body (apex %.2f m)" % apex)
	assert_true(p.is_grounded(), "and landed")
	assert_near(worst_root, 0.0, 1e-3, "the root bone never leaves the feet")
	assert_near(worst_offset, 0.0, 1e-4, "no vertical offset from the visual")
	assert_true(feet_band.x >= rest_foot - 0.03, "the ankles never sink under the body's feet (%.3f vs %.3f)" % [feet_band.x, rest_foot])
	assert_true(feet_band.y <= rest_foot + 0.15, "and only tuck up a little (%.3f)" % feet_band.y)


func test_the_rig_retires_the_procedural_motions() -> void:
	if _skip("test_the_rig_retires_the_procedural_motions"):
		return
	var pair := _player()
	var p: PlayerController = pair[0]
	var vis: PlayerVisual = pair[1]
	for motion in [&"bob", &"lean", &"death_fall", &"sit_drop", &"sit_lean", &"lunge"]:
		assert_true(vis.covers(motion), "a clip covers %s" % motion)
	var worst := {"bob": 0.0, "tilt": 0.0, "lunge": 0.0, "lunging": false}
	var pc := rig.system.player_combat
	var watch := func() -> void:
		worst.bob = maxf(worst.bob, absf(vis.position.y - p.presentation_offset.y - vis.seat_lift()))
		worst.tilt = maxf(worst.tilt, absf(vis.rotation.x))
		worst.lunge = maxf(worst.lunge, vis.model.position.length())
		worst.lunging = worst.lunging or pc.is_lunging()
	rig.w.bot.world_dir = Vector3.RIGHT
	_tick(vis, 40, watch)
	rig.w.bot.world_dir = Vector3.ZERO
	_tick(vis, 20, watch)
	rig.w.bot.press(&"attack")
	_tick(vis, 60, watch)
	assert_true(p.sit("522"), "sits")
	_tick(vis, 60, watch)
	p.stand_up()
	_tick(vis, 30, watch)
	p.die()
	_tick(vis, 60, watch)
	assert_near(worst.bob, 0.0, 1e-4, "no walk bob and no sit drop on the visual")
	assert_near(worst.tilt, 0.0, 1e-4, "no lean, no sit lean, no 80 degree death fall")
	assert_near(worst.lunge, 0.0, 1e-4, "no attack lunge on the model")
	assert_eq(pc.attacks, 1, "the attack happened")
	assert_false(worst.lunging, "and PlayerCombat never started its lunge tween")


func test_without_a_rig_the_placeholder_keeps_its_motions() -> void:
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var vis := PlayerVisual.new()
	vis.name = "Visual"
	vis.use_library_model = false
	vis.blob_shadow = false
	p.add_child(vis)
	vis.set_process(false)
	assert_false(vis.rigged(), "the placeholder has no rig")
	for motion in [&"bob", &"lean", &"death_fall", &"sit_drop", &"lunge"]:
		assert_false(vis.covers(motion), "nothing covers %s" % motion)
	var seen := {"bob": 0.0, "lean": 0.0}
	rig.w.bot.world_dir = Vector3.RIGHT
	_tick(vis, 40, func() -> void:
		seen.bob = maxf(seen.bob, vis.position.y)
		seen.lean = maxf(seen.lean, vis.rotation.x))
	rig.w.bot.world_dir = Vector3.ZERO
	_tick(vis, 30)
	rig.w.bot.press(&"attack")
	_tick(vis, 2)
	assert_true(seen.bob > 0.02, "the walk bob (%.3f m)" % seen.bob)
	assert_true(seen.lean > 0.05, "the lean into the motion (%.3f rad)" % seen.lean)
	assert_true(rig.system.player_combat.is_lunging(), "the attack lunge")
	_tick(vis, 60)
	assert_true(p.sit("522"), "sits")
	_tick(vis, 30)
	assert_near(vis.position.y, -PlayerVisual.SIT_DROP_M, 1e-3, "the procedural sit drop")
	p.stand_up()
	_tick(vis, 30)
	p.die()
	_tick(vis, 40)
	assert_near(vis.rotation.x, -deg_to_rad(80.0), 1e-3, "the procedural death fall")
