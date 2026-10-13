extends TestCase
## ArtImport: the import normalisation of the pinned art pack (#62, the owner's rules on #59), on small stand-in
## scenes shaped like the pack's GLBs as Godot imports them (<Name>/<Name>_rig/Skeleton3D/{BoneAttachment3D/socket_*,
## skinned MeshInstance3D...} plus an AnimationPlayer at the top). Needs no pack: test_art_pack_imported.gd checks
## the real imports.

const ROOT_REST := Vector3(0.0, 0.0, 0.0)
const HIPS_REST := Vector3(0.0, 0.55, 0.0)


func _material(name: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = name
	return m


## A skinned box-ish triangle pair spanning y0..y1, every vertex weighted to `bone`.
func _skinned_mesh(mat: Material, bone: int, y0: float, y1: float) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.1, y0, 0), Vector3(0.1, y0, 0), Vector3(0.1, y1, 0), Vector3(-0.1, y1, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for _i in 4:
		bones.append_array([bone, 0, 0, 0])
		weights.append_array([1.0, 0.0, 0.0, 0.0])
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh


func _static_mesh(mat: Material, size: float) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-size, 0, 0), Vector3(size, 0, 0), Vector3(0, size, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh


func _position_clip(name: String, root_keys: Array) -> Animation:
	var a := Animation.new()
	a.resource_name = name
	a.length = 1.0
	if not root_keys.is_empty():
		var t := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t, NodePath("Hero_rig/Skeleton3D:root"))
		for i in root_keys.size():
			a.position_track_insert_key(t, float(i) / maxf(1.0, root_keys.size() - 1), root_keys[i])
	var r := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(r, NodePath("Hero_rig/Skeleton3D:hips"))
	a.rotation_track_insert_key(r, 0.0, Quaternion.IDENTITY)
	return a


## The Beginner-like character: 2 m tall, Body/Clothing/Hair parts over two materials, one shared skin, four sockets.
func _character(clips: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Hero"
	var rig := Node3D.new()
	rig.name = "Hero_rig"
	root.add_child(rig)
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	rig.add_child(sk)
	for b in [["root", -1, ROOT_REST], ["hips", 0, HIPS_REST], ["spine", 1, Vector3(0, 0.2, 0)], ["head", 2, Vector3(0, 0.5, 0)],
			["hand.L", 2, Vector3(0.4, 0, 0)], ["hand.R", 2, Vector3(-0.4, 0, 0)]]:
		var i := sk.add_bone(b[0])
		sk.set_bone_parent(i, b[1])
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, b[2]))
	sk.reset_bone_poses()
	var skin := Skin.new()
	for i in sk.get_bone_count():
		skin.add_named_bind(sk.get_bone_name(i), sk.get_bone_global_rest(i).affine_inverse())
	for s in [["head", "socket_hat"], ["hand_L", "socket_shield_l"], ["hand_R", "socket_weapon_r"], ["spine", "socket_back"]]:
		var att := BoneAttachment3D.new()
		att.name = s[0]
		att.bone_name = {"head": "head", "hand_L": "hand.L", "hand_R": "hand.R", "spine": "spine"}[s[0]]
		sk.add_child(att)
		var sock := Node3D.new()
		sock.name = s[1]
		att.add_child(sock)
	var skin_mat := _material("Skin 0")
	var cloth := _material("Cloth sage")
	var hair := _material("Hair chestnut")
	for part in [["Body_head", skin_mat, 3, 1.5, 1.8], ["Body_forearm", skin_mat, 4, 0.8, 1.1], ["Body_shoulder", cloth, 2, 1.0, 1.3],
			["Clothing_tunic", cloth, 2, 0.7, 1.4], ["Clothing_sleeve", cloth, 4, 0.9, 1.3], ["Hair_scalp", hair, 3, 1.7, 2.0],
			["Hair_fringe_00", hair, 3, 1.6, 1.9]]:
		var mi := MeshInstance3D.new()
		mi.name = part[0]
		mi.mesh = _skinned_mesh(part[1], part[2], part[3], part[4])
		mi.skin = skin
		sk.add_child(mi)
		mi.skeleton = NodePath("..")
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	var lib := AnimationLibrary.new()
	for clip in clips:
		lib.add_animation(clip, _position_clip(clip, clips[clip]))
	ap.add_animation_library("", lib)
	root.add_child(ap)
	return root


func _nine_clips() -> Dictionary:
	var lift := [ROOT_REST, ROOT_REST + Vector3(0, 0.42, 0), ROOT_REST]
	return {"idle": [], "walk": [ROOT_REST, ROOT_REST + Vector3(0, 0.02, 0)], "run": [ROOT_REST, ROOT_REST + Vector3(0, 0.05, 0)],
		"jump": lift, "attack": [], "hit": [ROOT_REST, ROOT_REST + Vector3(0, 0, -0.08)], "climb": [ROOT_REST, ROOT_REST + Vector3(0, 0.05, 0)],
		"death": [ROOT_REST, ROOT_REST + Vector3(0, 0.12, 0)], "sit": [ROOT_REST, ROOT_REST + Vector3(0, -0.28, 0)]}


func _clip(root: Node, name: String) -> Animation:
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	return ap.get_animation(name)


func _root_keys(a: Animation) -> Array:
	var out := []
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_POSITION_3D and String(a.track_get_path(t).get_concatenated_subnames()) == "root":
			for k in a.track_get_key_count(t):
				out.append(a.track_get_key_value(t, k))
	return out


func _meshes(root: Node) -> Array:
	return root.find_children("*", "MeshInstance3D", true, false)


func _with(root: Node, fn: Callable) -> void:
	fn.call(root)
	root.free()


# --- looping -----------------------------------------------------------------------------------------------------

func test_character_locomotion_loops_and_every_other_clip_plays_once() -> void:
	_with(_character(_nine_clips()), func(root: Node3D) -> void:
		ArtImport.normalize(root, ArtImport.CHARACTER, 1.0)
		for clip in ["idle", "walk", "run", "climb"]:
			assert_eq(_clip(root, clip).loop_mode, Animation.LOOP_LINEAR, clip + " loops")
		for clip in ["jump", "attack", "hit", "sit", "death"]:
			assert_eq(_clip(root, clip).loop_mode, Animation.LOOP_NONE, clip + " plays once"))


func test_monster_idle_and_walk_loop_and_the_box_loops_only_idle() -> void:
	var monster_clips := {"Idle": [], "Walk": [], "Attack": [], "Hit": [], "Death": []}
	_with(_character(monster_clips), func(root: Node3D) -> void:
		ArtImport.normalize(root, ArtImport.MONSTER, 1.0)
		assert_eq(_clip(root, "Idle").loop_mode, Animation.LOOP_LINEAR, "monster Idle loops")
		assert_eq(_clip(root, "Walk").loop_mode, Animation.LOOP_LINEAR, "monster Walk loops")
		for clip in ["Attack", "Hit", "Death"]:
			assert_eq(_clip(root, clip).loop_mode, Animation.LOOP_NONE, "monster " + clip + " plays once"))
	_with(_character({"Idle": [], "Hit": [], "Break": []}), func(root: Node3D) -> void:
		ArtImport.normalize(root, ArtImport.BREAKABLE, 1.0)
		assert_eq(_clip(root, "Idle").loop_mode, Animation.LOOP_LINEAR, "box Idle loops")
		assert_eq(_clip(root, "Hit").loop_mode, Animation.LOOP_NONE, "box Hit plays once")
		assert_eq(_clip(root, "Break").loop_mode, Animation.LOOP_NONE, "box Break plays once"))


# --- root translation --------------------------------------------------------------------------------------------

func test_the_jump_no_longer_lifts_the_root() -> void:
	_with(_character(_nine_clips()), func(root: Node3D) -> void:
		ArtImport.normalize(root, ArtImport.CHARACTER, 1.0)
		var keys := _root_keys(_clip(root, "jump"))
		assert_false(keys.is_empty(), "jump holds the root with a key")
		for k in keys:
			assert_eq(k, ROOT_REST, "jump root key at rest"))


func test_only_sit_keeps_its_root_drop() -> void:
	_with(_character(_nine_clips()), func(root: Node3D) -> void:
		ArtImport.normalize(root, ArtImport.CHARACTER, 1.0)
		assert_eq(_root_keys(_clip(root, "sit")), [ROOT_REST, ROOT_REST + Vector3(0, -0.28, 0)], "sit keeps its 0.28 m drop")
		for clip in ["idle", "walk", "run", "hit", "climb", "death", "attack"]:
			var keys := _root_keys(_clip(root, clip))
			# Every clip pins the root, even one that never moved it, so leaving sit never leaves the body sunk.
			assert_false(keys.is_empty(), clip + " pins the root")
			for k in keys:
				assert_eq(k, ROOT_REST, clip + " root key at rest"))


func test_monster_lunges_and_bobs_are_held_at_rest() -> void:
	var clips := {"Idle": [ROOT_REST, Vector3(0, 0.025, 0)], "Attack": [ROOT_REST, Vector3(0, 0, 0.22)], "Walk": [], "Hit": [], "Death": []}
	_with(_character(clips), func(root: Node3D) -> void:
		ArtImport.normalize(root, ArtImport.MONSTER, 1.0)
		for clip in clips:
			for k in _root_keys(_clip(root, clip)):
				assert_eq(k, ROOT_REST, clip + " root key at rest"))


func test_drops_and_effects_keep_their_animation_untouched() -> void:
	for family in [ArtImport.DROP, ArtImport.EFFECT]:
		_with(_character({"Hover": [ROOT_REST, Vector3(0, 0.1, 0)]}), func(root: Node3D) -> void:
			_clip(root, "Hover").loop_mode = Animation.LOOP_LINEAR
			ArtImport.normalize(root, family, 1.0)
			assert_eq(_clip(root, "Hover").loop_mode, Animation.LOOP_LINEAR, family + " loop left alone")
			assert_eq(_root_keys(_clip(root, "Hover")), [ROOT_REST, Vector3(0, 0.1, 0)], family + " motion left alone"))


# --- mesh merging ------------------------------------------------------------------------------------------------

func test_meshes_merge_per_part_and_material() -> void:
	_with(_character(_nine_clips()), func(root: Node3D) -> void:
		assert_eq(ArtImport.draw_calls(root), 7, "seven parts before")
		ArtImport.normalize(root, ArtImport.CHARACTER, 1.0)
		var names := []
		for mi in _meshes(root):
			names.append(String(mi.name))
		# Body has two materials (skin, cloth); Clothing and Hair one each.
		assert_eq(ArtImport.draw_calls(root), 4, "one draw per part and material after: %s" % [names])
		var prefixes := {}
		for n in names:
			prefixes[n.get_slice("_", 0)] = int(prefixes.get(n.get_slice("_", 0), 0)) + 1
		assert_eq(prefixes, {"Body": 2, "Clothing": 1, "Hair": 1}, "merged names keep their part prefix"))


func test_merged_meshes_keep_vertices_materials_and_skinning() -> void:
	_with(_character(_nine_clips()), func(root: Node3D) -> void:
		var skin: Skin = _meshes(root)[0].skin
		ArtImport.normalize(root, ArtImport.CHARACTER, 1.0)
		var verts := 0
		var mats := {}
		for mi: MeshInstance3D in _meshes(root):
			assert_eq(mi.skin, skin, "%s keeps the shared skin" % mi.name)
			assert_true(mi.get_node_or_null(mi.skeleton) is Skeleton3D, "%s still finds its skeleton" % mi.name)
			var arrays := mi.mesh.surface_get_arrays(0)
			verts += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			assert_eq((arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size(), (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() * 4, "%s keeps bone indices" % mi.name)
			mats[mi.mesh.surface_get_material(0).resource_name] = true
		assert_eq(verts, 7 * 4, "no vertex lost")
		var names := mats.keys()
		names.sort()
		assert_eq(names, ["Cloth sage", "Hair chestnut", "Skin 0"], "materials kept by name"))


func test_hair_bones_stay_on_the_head_after_merging() -> void:
	_with(_character(_nine_clips()), func(root: Node3D) -> void:
		ArtImport.normalize(root, ArtImport.CHARACTER, 1.0)
		var hair: MeshInstance3D = null
		for mi in _meshes(root):
			if String(mi.name).begins_with("Hair_"):
				hair = mi
		var bones: PackedInt32Array = hair.mesh.surface_get_arrays(0)[Mesh.ARRAY_BONES]
		for i in range(0, bones.size(), 4):
			assert_eq(bones[i], 3, "hair vertex %d weighted to the head" % (i / 4)))


func test_the_four_sockets_survive_merging() -> void:
	_with(_character(_nine_clips()), func(root: Node3D) -> void:
		ArtImport.normalize(root, ArtImport.CHARACTER, 1.0)
		for s in [["socket_weapon_r", "hand.R"], ["socket_shield_l", "hand.L"], ["socket_hat", "head"], ["socket_back", "spine"]]:
			var sock := root.find_child(s[0], true, false)
			assert_true(sock != null, s[0] + " reachable")
			if sock != null:
				assert_true(sock.get_parent() is BoneAttachment3D and (sock.get_parent() as BoneAttachment3D).bone_name == s[1], s[0] + " on " + s[1]))


func test_static_item_parts_merge_without_moving() -> void:
	var root := Node3D.new()
	root.name = "item_1302000_Sword2"
	var holder := Node3D.new()
	holder.name = "item_1302000_Sword"
	root.add_child(holder)
	var brass := _material("Brass")
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.name = "Grip wrap_%d" % i
		mi.mesh = _static_mesh(brass, 0.05)
		mi.position = Vector3(0, -0.1 + 0.1 * i, 0)
		holder.add_child(mi)
	var blade := MeshInstance3D.new()
	blade.name = "Forged blade"
	blade.mesh = _static_mesh(_material("Blue steel"), 0.5)
	holder.add_child(blade)
	var before := ArtImport.visual_aabb(root)
	ArtImport.normalize(root, ArtImport.ITEM, 1.0)
	assert_eq(ArtImport.draw_calls(root), 2, "brass and steel")
	var after := ArtImport.visual_aabb(root)
	assert_true(after.position.is_equal_approx(before.position) and after.size.is_equal_approx(before.size), "bounds unchanged: %s vs %s" % [before, after])
	root.free()


# --- character scale ---------------------------------------------------------------------------------------------

func test_the_character_factor_scales_the_rig_and_leaves_the_root_free() -> void:
	_with(_character(_nine_clips()), func(root: Node3D) -> void:
		var before := ArtImport.visual_aabb(root)
		assert_near(before.size.y, 1.3, 1e-4, "stand-in spans 0.7..2.0 m")
		ArtImport.normalize(root, ArtImport.CHARACTER, 0.75)
		assert_true(root.transform.is_equal_approx(Transform3D.IDENTITY), "the scene root stays identity for the game to place")
		assert_near(ArtImport.visual_aabb(root).size.y, 1.3 * 0.75, 1e-4, "height scaled by the factor")
		assert_near(ArtImport.visual_aabb(root).end.y, 2.0 * 0.75, 1e-4, "top scaled about the feet"))


func test_character_parts_take_the_factor_and_monsters_do_not() -> void:
	_with(_character({}), func(root: Node3D) -> void:
		ArtImport.normalize(root, ArtImport.CHARACTER_PART, 0.75)
		assert_near(ArtImport.visual_aabb(root).end.y, 1.5, 1e-4, "a wearable or hair module is scaled like the body"))
	_with(_character({"Idle": []}), func(root: Node3D) -> void:
		ArtImport.normalize(root, ArtImport.MONSTER, 0.75)
		assert_near(ArtImport.visual_aabb(root).end.y, 2.0, 1e-4, "monsters keep their size (model_fit sizes them)"))


# --- which rules apply to which file -----------------------------------------------------------------------------

func test_family_of_a_pack_path() -> void:
	var monsters := {"assets": [{"glb": "Snail.glb", "category": "monster"}, {"glb": "WoodenBox.glb", "category": "breakable"},
		{"glb": "SnailShell.glb", "category": "drop"}, {"glb": "HitSpark.glb", "category": "effect"}]}
	assert_eq(ArtImport.family_of("characters/glb/Beginner_Male.glb", monsters), ArtImport.CHARACTER, "preset")
	assert_eq(ArtImport.family_of("characters/glb/Shanks.glb", monsters), ArtImport.CHARACTER, "NPC")
	assert_eq(ArtImport.family_of("characters/wearables/708_Brown_Skullcap.glb", monsters), ArtImport.CHARACTER_PART, "wearable")
	assert_eq(ArtImport.family_of("characters/modules/Hair_0.glb", monsters), ArtImport.CHARACTER_PART, "hair module")
	assert_eq(ArtImport.family_of("monsters/Snail.glb", monsters), ArtImport.MONSTER, "monster")
	assert_eq(ArtImport.family_of("monsters/WoodenBox.glb", monsters), ArtImport.BREAKABLE, "box")
	assert_eq(ArtImport.family_of("monsters/SnailShell.glb", monsters), ArtImport.DROP, "drop")
	assert_eq(ArtImport.family_of("monsters/HitSpark.glb", monsters), ArtImport.EFFECT, "effect")
	assert_eq(ArtImport.family_of("equipment/glb/item_1302000_Sword.glb", monsters), ArtImport.ITEM, "item")
	assert_eq(ArtImport.family_of("environment/glb/Bed.glb", monsters), ArtImport.ENVIRONMENT, "environment")
	assert_eq(ArtImport.family_of("monsters/Unknown.glb", monsters), "", "unlisted monster file")
