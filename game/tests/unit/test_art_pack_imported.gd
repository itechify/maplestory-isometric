extends TestCase
## The real art pack as Godot imported it (#62): the import normalisation (ArtImport through the post-import script)
## holds on the pinned v1 models, looked up by ID. Needs the pack installed (bash scripts/art_pack.sh fetch); every test
## prints SKIP without it. The rules themselves are pinned on stand-in scenes in test_art_import.gd.

var _art: ArtPack = null


func before_each() -> void:
	_art = ArtPack.load_installed()


func _skip(test: String) -> bool:
	if _art.present():
		return false
	print("SKIP %s: no art pack installed (bash scripts/art_pack.sh fetch)" % test)
	return true


func _clip(root: Node, clip: String) -> Animation:
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	return ap.get_animation(clip) if ap != null and ap.has_animation(clip) else null


## The root bone's position keys in a clip (the y of each).
func _root_ys(a: Animation) -> Array:
	var out := []
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_POSITION_3D and String(a.track_get_path(t).get_concatenated_subnames()) == "root":
			for k in a.track_get_key_count(t):
				out.append((a.track_get_key_value(t, k) as Vector3).y)
	return out


## The pack's own v1 height of a file (its godot_validation.json bounds, measured by Jarvis on Godot 4.6.3).
func _v1_height(rel: String) -> float:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_art.root.path_join("godot_validation.json")))
	for f in (data as Dictionary).get("files", []):
		if String(f.get("file", "")) == rel:
			return float(f.bounds_max[1]) - float(f.bounds_min[1])
	return -1.0


func _with(kind: String, id: String, fn: Callable) -> void:
	var n := _art.instance(kind, id)
	assert_true(n != null, "%s %s imports" % [kind, id])
	if n != null:
		fn.call(n)
		n.free()


func test_one_of_each_kind_loads_by_id() -> void:
	if _skip("test_one_of_each_kind_loads_by_id"):
		return
	for pair in [[ArtPack.NPC, "15"], [ArtPack.MONSTER, "2"], [ArtPack.ITEM, "1302000"], [ArtPack.WEARABLE, "1060001"],
			[ArtPack.KIT, "Sign_Board"], [ArtPack.BREAKABLE, "0000001"], [ArtPack.PRESET, "Beginner_Female"],
			[ArtPack.HAIR, "5"], [ArtPack.FACE, "sleepy"], [ArtPack.MESO, ""], [ArtPack.EFFECT, "HitSpark"]]:
		_with(pair[0], pair[1], func(_n: Node3D) -> void: pass)
	assert_true(ResourceLoader.exists(_art.icon(ArtPack.ITEM, "1302000")), "the Sword's icon is imported")


func test_beginner_clips_loop_by_the_owner_rules() -> void:
	if _skip("test_beginner_clips_loop_by_the_owner_rules"):
		return
	_with(ArtPack.PRESET, "Beginner_Male", func(n: Node3D) -> void:
		for clip in ["idle", "walk", "run", "climb"]:
			assert_eq(_clip(n, clip).loop_mode, Animation.LOOP_LINEAR, clip + " loops")
		for clip in ["jump", "attack", "hit", "sit", "death"]:
			assert_eq(_clip(n, clip).loop_mode, Animation.LOOP_NONE, clip + " plays once"))
	_with(ArtPack.MONSTER, "9", func(n: Node3D) -> void:
		assert_eq(_clip(n, "Idle").loop_mode, Animation.LOOP_LINEAR, "Orange Mushroom Idle loops")
		assert_eq(_clip(n, "Walk").loop_mode, Animation.LOOP_LINEAR, "Orange Mushroom Walk loops")
		assert_eq(_clip(n, "Death").loop_mode, Animation.LOOP_NONE, "Orange Mushroom Death plays once"))
	_with(ArtPack.BREAKABLE, "0000001", func(n: Node3D) -> void:
		assert_eq(_clip(n, "Idle").loop_mode, Animation.LOOP_LINEAR, "box Idle loops")
		assert_eq(_clip(n, "Break").loop_mode, Animation.LOOP_NONE, "box Break plays once"))


func test_the_jump_lifts_nothing_and_sit_keeps_its_drop() -> void:
	if _skip("test_the_jump_lifts_nothing_and_sit_keeps_its_drop"):
		return
	_with(ArtPack.PRESET, "Beginner_Male", func(n: Node3D) -> void:
		var jump := _root_ys(_clip(n, "jump"))
		assert_false(jump.is_empty(), "jump pins the root")
		for y in jump:
			assert_near(y, 0.0, 1e-4, "the v1 jump lifted the root 0.42 m; now it stays at rest")
		var sit := _root_ys(_clip(n, "sit"))
		assert_near(sit.min(), -0.28, 0.01, "sit keeps its 0.28 m drop (in rig units, before the character factor)"))
	_with(ArtPack.MONSTER, "2", func(n: Node3D) -> void:
		for y in _root_ys(_clip(n, "Attack")):
			assert_near(y, 0.0, 1e-4, "the Snail's lunge no longer moves its root"))


func test_the_four_sockets_survive_merging() -> void:
	if _skip("test_the_four_sockets_survive_merging"):
		return
	for pair in [[ArtPack.PRESET, "Beginner_Male"], [ArtPack.NPC, "15"]]:
		_with(pair[0], pair[1], func(n: Node3D) -> void:
			for s in ["socket_weapon_r", "socket_shield_l", "socket_hat", "socket_back"]:
				var sock := n.find_child(s, true, false)
				assert_true(sock != null and sock.get_parent() is BoneAttachment3D, "%s %s has %s on a bone" % [pair[0], pair[1], s]))


func test_merging_cuts_the_beginners_draw_calls() -> void:
	if _skip("test_merging_cuts_the_beginners_draw_calls"):
		return
	var path := _art.model(ArtPack.PRESET, "Beginner_Male")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	assert_eq(doc.append_from_file(ProjectSettings.globalize_path(path), state), OK, "the source GLB reads")
	var raw := doc.generate_scene(state)
	var before := ArtImport.draw_calls(raw)
	raw.free()
	assert_eq(before, 61, "v1 Beginner_Male: 61 meshes, one surface each")
	_with(ArtPack.PRESET, "Beginner_Male", func(n: Node3D) -> void:
		var after := ArtImport.draw_calls(n)
		assert_true(after < before, "fewer draws after merging: %d -> %d" % [before, after])
		assert_eq(after, 16, "one per part and material (Body 2, Clothing 5, Face 5, Footwear 3, Hair 1)"))


func test_characters_stand_at_their_v1_height_times_the_one_factor() -> void:
	if _skip("test_characters_stand_at_their_v1_height_times_the_one_factor"):
		return
	var f := ArtPack.character_scale()
	_with(ArtPack.PRESET, "Beginner_Male", func(n: Node3D) -> void:
		var h := ArtImport.visual_aabb(n).size.y
		assert_near(h, 1.5, 0.01, "the Beginner fits the game's 1.5 m body")
		assert_near(h, _v1_height("characters/glb/Beginner_Male.glb") * f, 0.005, "Beginner = v1 height x factor"))
	_with(ArtPack.NPC, "15", func(n: Node3D) -> void:
		var v1 := _v1_height("characters/glb/Shanks.glb")
		assert_near(v1, 2.3525, 0.001, "Shanks is 2.35 m in v1")
		assert_near(ArtImport.visual_aabb(n).size.y, v1 * f, 0.005, "Shanks = v1 height x the same factor"))
	_with(ArtPack.MONSTER, "9", func(n: Node3D) -> void:
		assert_near(ArtImport.visual_aabb(n).size.y, _v1_height("monsters/OrangeMushroom.glb"), 0.005, "monsters keep their v1 size"))
