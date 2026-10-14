extends TestCase
## The saved look on the rigged Beginner (#67): CharacterLook grafts the chosen hair and face modules onto the
## preset's skeleton by bone name (replacing its own Hair_ / Face_ meshes) and paints every "Skin " material with the
## chosen palette colour; PlayerVisual shows the live character's look and rebuilds when it changes. The graft itself
## is tested without the pack on a hand-made skeleton; the rest needs the art pack (SKIP without it).

var art: ArtPack


func before_each() -> void:
	art = ArtPack.load_installed()


func _skip(test: String) -> bool:
	if art.present():
		return false
	print("SKIP %s: no art pack installed (bash scripts/art_pack.sh fetch)" % test)
	return true


# --- the graft, without the pack ----------------------------------------------------------------------------------

## A skeleton with `bones` (each a child of the previous, 1 m apart) under a Node3D "rig" scaled by `scale`.
func _skeleton(bones: Array, scale: float) -> Skeleton3D:
	var rig := Node3D.new()
	rig.scale = Vector3.ONE * scale
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	rig.add_child(sk)
	for i in bones.size():
		sk.add_bone(bones[i])
		if i > 0:
			sk.set_bone_parent(i, i - 1)
		sk.set_bone_rest(i, Transform3D(Basis(), Vector3(0, 1.0 if i > 0 else 0.0, 0)))
		sk.reset_bone_pose(i)
	return sk


## A one-triangle mesh skinned fully to `bind_bone` of `sk`, named `mesh_name`, bound by name (as the pack's are).
func _skinned(sk: Skeleton3D, mesh_name: String, bind_bone: String, by_name: bool = true) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 2, 0), Vector3(1, 2, 0), Vector3(0, 2, 1)])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	var skin := Skin.new()
	var bone := sk.find_bone(bind_bone)
	if by_name:
		skin.add_named_bind(bind_bone, sk.get_bone_global_rest(bone).affine_inverse())
	else:
		skin.add_bind(bone, sk.get_bone_global_rest(bone).affine_inverse())
	mi.skin = skin
	sk.add_child(mi)
	mi.skeleton = mi.get_path_to(sk)
	return mi


func test_graft_moves_a_part_onto_the_skeleton_by_bone_name() -> void:
	var body := _skeleton(["root", "hips", "head"], 0.75)
	var part := _skeleton(["head", "root", "hips"], 0.75)  # same names, another order: binds must follow names
	_skinned(part, "Hair_Hair chestnut", "head", false)
	var part_root := part.get_parent()
	var grafted := CharacterLook.graft(part_root, body)
	assert_eq(grafted.size(), 1, "one mesh grafted")
	var mi: MeshInstance3D = grafted[0]
	assert_eq(mi.get_parent(), body, "under the body's skeleton")
	assert_true(mi.transform.is_equal_approx(Transform3D.IDENTITY), "at the skeleton's origin: it inherits the rig's scale, never rescaled")
	assert_eq(mi.get_node(mi.skeleton), body, "skinned to the body's skeleton")
	assert_eq(String(mi.skin.get_bind_name(0)), "head", "bound by name to the head")
	assert_eq(mi.name, &"Hair_Hair chestnut", "keeps its part name")
	assert_false(is_instance_valid(part_root), "the part's own rig is freed")
	body.get_parent().free()


func test_graft_refuses_a_part_whose_bone_the_skeleton_lacks() -> void:
	var body := _skeleton(["root", "hips"], 1.0)
	var part := _skeleton(["root", "hips", "tail"], 1.0)
	_skinned(part, "Wear_tail", "tail")
	var part_root := part.get_parent()
	assert_eq(CharacterLook.graft(part_root, body).size(), 0, "no tail bone: nothing grafted")
	assert_eq(body.get_child_count(), 0, "the skeleton is untouched")
	assert_false(is_instance_valid(part_root), "the part is freed either way")
	body.get_parent().free()


# --- the look on the pack's Beginner -------------------------------------------------------------------------------

func _preset(gender: String) -> Node3D:
	return art.instance(ArtPack.PRESET, PlayerVisual.preset_for(gender))


func _meshes(model: Node, prefix: String) -> Array:
	var out := []
	for n in model.find_children("*", "MeshInstance3D", true, false):
		if String(n.name).begins_with(prefix):
			out.append(n)
	return out


## Every (mesh name, material name, albedo) of the model's "Skin " surfaces.
func _skin_surfaces(model: Node) -> Array:
	var out := []
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m != null and m.resource_name.begins_with("Skin "):
				out.append([String(mi.name), m.resource_name, m.albedo_color])
	return out


func _aabb_of(model: Node3D, meshes: Array) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in meshes:
		var box: AABB = ArtImport.to_root(model, mi) * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func test_the_default_look_is_the_preset_as_built() -> void:
	if _skip("test_the_default_look_is_the_preset_as_built"):
		return
	for gender in ["male", "female"]:
		var plain := _preset(gender)
		var model := _preset(gender)
		CharacterLook.apply(model, CharacterAppearance.default_for(gender), PlayerVisual.preset_for(gender), art)
		for prefix in ["Hair_", "Face_", "Hat_", "Body_"]:
			var a := _meshes(plain, prefix).map(func(m: MeshInstance3D) -> Array: return [String(m.name), m.mesh])
			var b := _meshes(model, prefix).map(func(m: MeshInstance3D) -> Array: return [String(m.name), m.mesh])
			assert_eq(b, a, "%s: the preset's own %s meshes" % [gender, prefix])
		var skin := art.skin_color(int(CharacterAppearance.default_for(gender)["skin"]))
		for s: Array in _skin_surfaces(model):
			assert_true((s[2] as Color).is_equal_approx(skin), "%s %s keeps the preset skin" % [gender, s])
		plain.free()
		model.free()


func test_a_chosen_hair_style_replaces_the_preset_hair_on_the_head() -> void:
	if _skip("test_a_chosen_hair_style_replaces_the_preset_hair_on_the_head"):
		return
	for style in CharacterAppearance.choices(CharacterAppearance.HAIR_STYLE):
		var model := _preset("male")
		var look := CharacterAppearance.default_for("male")
		look["hair_style"] = style
		CharacterLook.apply(model, look, "Beginner_Male", art)
		var module := art.instance(ArtPack.HAIR, str(style))
		var want := _meshes(module, "Hair_").map(func(m: MeshInstance3D) -> Mesh: return m.mesh)
		var hair := _meshes(model, "Hair_")
		if style != 3:  # 3 is the male preset's own hair, kept as built (test_the_default_look_is_the_preset_as_built)
			assert_eq(hair.map(func(m: MeshInstance3D) -> Mesh: return m.mesh), want, "hair %d: exactly the module's meshes" % style)
		var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
		for mi: MeshInstance3D in hair:
			assert_eq(mi.get_parent(), sk, "hair %d on the body's skeleton" % style)
			assert_eq(mi.get_node(mi.skeleton), sk, "hair %d skinned to it" % style)
		# On the head at the 1.5 m body: the rest-pose bounds sit around the head bone, above the neck.
		var box := _aabb_of(model, hair)
		var head := ArtImport.to_root(model, sk) * sk.get_bone_global_rest(sk.find_bone("head")).origin
		var neck := ArtImport.to_root(model, sk) * sk.get_bone_global_rest(sk.find_bone("neck")).origin
		assert_true(box.position.y + box.size.y > head.y and box.position.y + box.size.y < 1.6,
			"hair %d tops out over the head, within the 1.5 m body: %s (head %s)" % [style, box, head])
		assert_true(box.get_center().y > neck.y, "hair %d is above the neck: %s (neck %s)" % [style, box, neck])
		assert_true(absf(box.get_center().x - head.x) < 0.15, "hair %d is centred on the head: %s" % [style, box])
		module.free()
		model.free()


func test_a_chosen_face_replaces_the_preset_face_and_takes_the_skin() -> void:
	if _skip("test_a_chosen_face_replaces_the_preset_face_and_takes_the_skin"):
		return
	var styles := art.face_styles()
	for i in styles.size():
		var model := _preset("female")
		var look := {"hair_style": 2, "face": i, "skin": 3}
		CharacterLook.apply(model, look, "Beginner_Female", art)
		if i == 0:
			model.free()
			continue  # the female default: the preset's own face (test_the_default_look_is_the_preset_as_built)
		var module := art.instance(ArtPack.FACE, styles[i])
		var want := _meshes(module, "Face_").map(func(m: MeshInstance3D) -> Mesh: return m.mesh)
		assert_eq(_meshes(model, "Face_").map(func(m: MeshInstance3D) -> Mesh: return m.mesh), want,
			"face %s: exactly the module's meshes" % styles[i])
		# The module's nose is "Skin 0.00N" in the male skin; on this character it is the chosen skin 3.
		var faces := _skin_surfaces(model).filter(func(s: Array) -> bool: return String(s[0]).begins_with("Face_"))
		assert_false(faces.is_empty(), "the face has skin")
		for s: Array in faces:
			assert_true((s[2] as Color).is_equal_approx(art.skin_color(3)), "face %s %s is skin 3" % [styles[i], s])
		module.free()
		model.free()


func test_every_skin_colour_paints_every_skin_material_and_nothing_else() -> void:
	if _skip("test_every_skin_colour_paints_every_skin_material_and_nothing_else"):
		return
	var plain := _preset("male")
	for skin in CharacterAppearance.choices(CharacterAppearance.SKIN):
		var model := _preset("male")
		CharacterLook.apply(model, {"hair_style": 3, "face": 0, "skin": skin}, "Beginner_Male", art)
		var surfaces := _skin_surfaces(model)
		assert_true(surfaces.size() >= 2, "body and face skin: %s" % [surfaces])
		for s: Array in surfaces:
			assert_true((s[2] as Color).is_equal_approx(art.skin_color(skin)), "skin %d: %s" % [skin, s])
		# Cheeks, irises, clothes: untouched.
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var m := mi.get_active_material(0) as BaseMaterial3D
			if m != null and not m.resource_name.begins_with("Skin "):
				var orig := plain.find_child(String(mi.name), true, false) as MeshInstance3D
				assert_true(orig != null and (orig.get_active_material(0) as BaseMaterial3D).albedo_color == m.albedo_color,
					"skin %d leaves %s alone" % [skin, mi.name])
		model.free()
	# The pack's own materials are shared by every instance: painting one character never repaints another.
	var other := _preset("male")
	for s: Array in _skin_surfaces(other):
		assert_true((s[2] as Color).is_equal_approx(art.skin_color(0)), "a fresh preset keeps skin 0: %s" % [s])
	other.free()
	plain.free()


# --- PlayerVisual -----------------------------------------------------------------------------------------------

func test_the_player_shows_the_look_and_rebuilds_when_it_changes() -> void:
	if _skip("test_the_player_shows_the_look_and_rebuilds_when_it_changes"):
		return
	var rig := MonsterTestRig.create(db(), 67)
	rig.floor(40.0)
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var vis := PlayerVisual.new()
	vis.name = "Visual"
	vis.blob_shadow = false
	vis.gender = "female"
	vis.appearance = {"hair_style": 5, "face": 1, "skin": 2}
	p.add_child(vis)
	vis.set_process(false)
	assert_true(vis.rigged(), "the rig")
	assert_eq(vis.look, {"hair_style": 5, "face": 1, "skin": 2}, "the look shown")
	var hair5 := art.instance(ArtPack.HAIR, "5")
	assert_eq(_meshes(vis.model, "Hair_").map(func(m: MeshInstance3D) -> Mesh: return m.mesh),
		_meshes(hair5, "Hair_").map(func(m: MeshInstance3D) -> Mesh: return m.mesh), "hair 5 on the player")
	hair5.free()
	for s: Array in _skin_surfaces(vis.model):
		assert_true((s[2] as Color).is_equal_approx(art.skin_color(2)), "skin 2: %s" % [s])
	var outlines := vis.outline_meshes().size()
	var old_model := vis.model
	vis.set_look("female", {"hair_style": 5, "face": 1, "skin": 2})
	assert_true(vis.model == old_model, "the same look: no rebuild")
	vis.set_look("female", {"hair_style": 0, "face": 1, "skin": 2})
	assert_true(vis.model != old_model, "another hair style: rebuilt")
	assert_eq(vis.look["hair_style"], 0)
	assert_true(vis.outline_meshes().size() > 0 and vis.outline_meshes().size() <= outlines + 2,
		"the see-through outline follows the new model (%d meshes, was %d)" % [vis.outline_meshes().size(), outlines])
	vis.set_gender("male")
	assert_eq(vis.preset, "Beginner_Male", "set_gender still swaps the preset")
	assert_eq(vis.look, {"hair_style": 0, "face": 1, "skin": 2}, "and keeps the chosen look")
	rig.free_all()


func test_the_look_costs_no_extra_draw_calls() -> void:
	if _skip("test_the_look_costs_no_extra_draw_calls"):
		return
	for gender in ["male", "female"]:
		var plain := _preset(gender)
		var base := ArtImport.draw_calls(plain)
		var most := 0
		for h in CharacterAppearance.choices(CharacterAppearance.HAIR_STYLE):
			for f in CharacterAppearance.choices(CharacterAppearance.FACE):
				var model := _preset(gender)
				CharacterLook.apply(model, {"hair_style": h, "face": f, "skin": 1}, PlayerVisual.preset_for(gender), art)
				most = maxi(most, ArtImport.draw_calls(model))
				model.free()
		print("NOTE %s: preset %d draw calls, any look at most %d" % [gender, base, most])
		assert_true(most <= base + 1, "%s: at most one more draw call than the preset (%d vs %d)" % [gender, most, base])
		plain.free()
