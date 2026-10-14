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


func test_a_new_character_of_the_other_gender_swaps_the_preset() -> void:
	if _skip("test_a_new_character_of_the_other_gender_swaps_the_preset"):
		return
	var pair := _player("male")
	var vis: PlayerVisual = pair[1]
	vis.set_see_through(true)
	_tick(vis, 5)
	vis.set_gender("female")
	assert_eq(vis.preset, "Beginner_Female", "the female preset")
	assert_eq(vis.get_children().filter(func(c: Node) -> bool: return c.name == "Model").size(), 1, "one Model")
	assert_true(vis.model.is_inside_tree() and vis.model.find_child("Hat_*", true, false) != null, "the new model shows")
	var sk: Skeleton3D = vis.model.find_child("Skeleton3D", true, false)
	assert_true(vis.outline_meshes().size() >= 10, "outline hulls for the new model")
	for o in vis.outline_meshes():
		assert_true(is_instance_valid(o) and o.get_node_or_null(o.skeleton) == sk, "posed by the new skeleton")
	_tick(vis, 5)
	assert_true(vis.outline_meshes()[0].visible, "the see-through state carries over")
	vis.set_gender("female")
	assert_eq(vis.model.find_child("Skeleton3D", true, false), sk, "the same gender keeps the model")


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


## An equip or unequip rebuilds the model; the clip playing goes on from where it was instead of starting over (a
## swing keeps its timing, a seated Beginner stays down in the seat).
func test_changing_equipment_keeps_the_clip_going() -> void:
	if _skip("test_changing_equipment_keeps_the_clip_going"):
		return
	var pair := _player()
	var p: PlayerController = pair[0]
	var vis: PlayerVisual = pair[1]
	_tick(vis, 10)
	rig.w.bot.press(&"attack")
	_tick(vis, 6)
	assert_eq(_playing(vis), "attack", "swinging")
	var at := vis.animator.anim.current_animation_position
	assert_true(at > 0.02, "into the swing (%.3f s)" % at)
	vis.set_equipment({"hat": "708"})
	assert_eq(vis.worn.keys(), ["hat"], "the hat is on")
	assert_eq(_playing(vis), "attack", "still swinging after the rebuild")
	assert_near(vis.animator.anim.current_animation_position, at, 0.001, "from where it was")
	_tick(vis, 90)
	assert_true(p.sit("522"), "sits")
	_tick(vis, 60)
	var lift := vis.seat_lift()
	assert_true(lift > 0.1, "down in the seat (lift %.3f)" % lift)
	vis.set_equipment({})
	_tick(vis, 1)
	assert_eq(_playing(vis), "sit", "still seated after the rebuild")
	assert_near(vis.seat_lift(), lift, 0.01, "and stays down instead of sitting down again")


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
	# Hanging still: the clip holds its pose, but only after the blend into it has finished (a held clip at speed 0
	# would freeze the crossfade too, leaving the idle arms on the rope).
	_tick(vis, 60)
	assert_eq(_playing(vis), "climb", "hanging still")
	var sk: Skeleton3D = vis.model.find_child("Skeleton3D", true, false)
	var hand := sk.get_bone_global_pose(sk.find_bone("hand.R")).origin
	assert_true(hand.x > -0.2 and hand.y > 0.75, "the hand is up on the rope, not at the side (%s)" % hand)
	rig.w.bot.climb = 1.0
	_tick(vis, 20)
	assert_eq(_playing(vis), "climb", "climbing")


## The lowest point of the seated body's pelvis above the player's feet (m): the skinned Body_/Clothing_ vertices
## that sit around the hips in the rest pose (0.25-0.45 m up, within 0.15 m of the middle, so not the hands), posed
## by the skeleton as it stands now.
func _pelvis_bottom(vis: PlayerVisual, p: PlayerController) -> float:
	return _lowest_posed(vis, p, true)


## The lowest posed vertex above the player's feet (m): of the pelvis (see _pelvis_bottom) or of the whole body.
func _lowest_posed(vis: PlayerVisual, p: PlayerController, pelvis_only: bool = false) -> float:
	var sk: Skeleton3D = vis.model.find_child("Skeleton3D", true, false)
	var to_model := ArtImport._to_root(vis.model, sk)
	var lowest := INF
	for node in sk.get_children():
		var mi := node as MeshInstance3D
		if mi == null or mi.skin == null:
			continue
		if pelvis_only and not (String(mi.name).begins_with("Body_") or String(mi.name).begins_with("Clothing_")):
			continue
		var bind_bone: Array[int] = []
		for b in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_bone(b)
			bind_bone.append(bone if bone >= 0 else sk.find_bone(String(mi.skin.get_bind_name(b))))
		var a := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		for i in verts.size():
			var rest := to_model * verts[i]
			if pelvis_only and (rest.y < 0.25 or rest.y > 0.45 or absf(rest.x) > 0.15):
				continue
			var posed := Vector3.ZERO
			for k in per:
				var wt := weights[i * per + k]
				if wt > 0.0:
					var bi := bones[i * per + k]
					posed += (sk.get_bone_global_pose(bind_bone[bi]) * mi.skin.get_bind_pose(bi) * verts[i]) * wt
			lowest = minf(lowest, (sk.global_transform * posed).y - p.global_position.y)
	return lowest


## The chair's seat top above the player's feet (m): the height holding the most upward-facing surface area between
## 0.15 and 0.6 m (the seat cushion; not the armrests or the back's top rail).
func _seat_top(chair: Node3D, p: PlayerController) -> float:
	var area := {}
	for node in chair.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			for t in range(0, idx.size(), 3):
				var p0 := xf * v[idx[t]]
				var n := (xf * v[idx[t + 1]] - p0).cross(xf * v[idx[t + 2]] - p0)
				var y := (p0.y + (xf * v[idx[t + 1]]).y + (xf * v[idx[t + 2]]).y) / 3.0 - p.global_position.y
				if n.length() > 0.0 and n.normalized().y > 0.9 and y > 0.15 and y < 0.6:
					var key := snappedf(y, 0.01)
					area[key] = float(area.get(key, 0.0)) + n.length() * 0.5
	var best := -1.0
	for k in area:
		if best < 0.0 or float(area[k]) > float(area[best]):
			best = k
	return best


func test_the_seated_beginner_sits_on_the_green_relaxer() -> void:
	if _skip("test_the_seated_beginner_sits_on_the_green_relaxer"):
		return
	for g in ["male", "female"]:
		var pair := _player(g)
		var p: PlayerController = pair[0]
		var vis: PlayerVisual = pair[1]
		_tick(vis, 10)
		var standing := _pelvis_bottom(vis, p)
		assert_true(p.sit("522"), "%s sits on The Green Relaxer" % g)
		_tick(vis, 120)
		var chair := vis.chair_prop
		assert_true(chair != null and chair.visible, "%s: the chair shows" % g)
		assert_eq(String(chair.get_meta("item_id", "")), "522", "%s: it is the pack's Green Relaxer model" % g)
		var seat := _seat_top(chair, p)
		var pelvis := _pelvis_bottom(vis, p)
		assert_between(seat, 0.3, 0.4, "%s: the seat is a chair's height at the character scale (%.3f m)" % [g, seat])
		assert_near(pelvis, seat, 0.03, "%s: the pelvis rests on the cushion: no floating, no sinking" % g)
		assert_true(pelvis > standing, "%s: seated higher than the standing pelvis (the chibi climbs onto it)" % g)
		p.stand_up()
		_tick(vis, 60)
		assert_false(chair.visible, "%s: the chair goes away on standing" % g)
		assert_near(vis.seat_lift(), 0.0, 1e-3, "%s: and the lift with it" % g)
		rig.free_all()
		rig = MonsterTestRig.create(db(), 63)
		rig.floor(40.0)


func test_the_dead_beginner_lies_on_the_ground() -> void:
	if _skip("test_the_dead_beginner_lies_on_the_ground"):
		return
	for g in ["male", "female"]:
		var pair := _player(g)
		var p: PlayerController = pair[0]
		var vis: PlayerVisual = pair[1]
		_tick(vis, 10)
		assert_near(_lowest_posed(vis, p), 0.0, 0.03, "%s: standing on the ground" % g)
		p.die()
		var worst := INF
		for i in 120:
			_tick(vis)
			if i % 6 == 0:
				worst = minf(worst, _lowest_posed(vis, p))
		# The v1 death clip lays the big chibi head 0.18 m under the feet once its root lift is held (#62): the X-ray
		# fill then painted the buried head and heels blue on a dead player nothing hides.
		assert_true(worst > -0.04, "%s: nothing sinks into the ground while falling (%.3f m)" % [g, worst])
		assert_near(_lowest_posed(vis, p), 0.0, 0.03, "%s: the body rests on the ground" % g)
		p.revive()
		_tick(vis, 30)
		assert_near(vis.position.y - p.presentation_offset.y, 0.0, 1e-4, "%s: no lift once alive" % g)
		rig.free_all()
		rig = MonsterTestRig.create(db(), 63)
		rig.floor(40.0)


func test_the_xray_fill_and_outline_follow_the_skinned_pose() -> void:
	if _skip("test_the_xray_fill_and_outline_follow_the_skinned_pose"):
		return
	var vis: PlayerVisual = _player()[1]
	var sk: Skeleton3D = vis.model.find_child("Skeleton3D", true, false)
	var skinned := 0
	for node in vis.model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		skinned += 1 if mi.skin != null else 0
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			assert_true(m != null, "%s: a BaseMaterial3D" % mi.name)
			if m == null:
				continue
			assert_eq(m.stencil_flags, BaseMaterial3D.STENCIL_FLAG_WRITE, "%s writes the stencil" % mi.name)
			assert_eq(m.stencil_reference, PlayerVisual.STENCIL_REF, "%s: the player's reference" % mi.name)
			assert_eq(m.next_pass, vis.silhouette_materials().fill, "%s carries the X-ray fill (same instance: skinned)" % mi.name)
		assert_eq(mi.layers, PlayerVisual.PLAYER_LAYER, "%s is on the player layer (no blob shadow on it)" % mi.name)
	assert_true(skinned >= 10, "the merged Beginner meshes are skinned (%d)" % skinned)
	var outlines := vis.outline_meshes()
	assert_eq(outlines.size(), skinned, "one outline hull per skinned mesh")
	for o in outlines:
		# A copy without the skin and the bone channels would stand in the bind pose while the body animates.
		assert_true(o.skin != null, "%s has the rig's skin" % o.name)
		assert_true(o.get_node_or_null(o.skeleton) == sk, "%s is posed by the rig's skeleton" % o.name)
		var a := o.mesh.surface_get_arrays(0)
		assert_true(a[Mesh.ARRAY_BONES] != null and a[Mesh.ARRAY_WEIGHTS] != null, "%s keeps its bones and weights" % o.name)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		assert_true(a[Mesh.ARRAY_BONES] != null and (a[Mesh.ARRAY_BONES] as PackedInt32Array).size() >= verts.size() * 4,
			"%s: four or eight bones per vertex" % o.name)


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
		worst.bob = maxf(worst.bob, absf(vis.position.y - p.presentation_offset.y - vis.ground_lift()))
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
