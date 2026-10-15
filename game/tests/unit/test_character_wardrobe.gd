extends TestCase
## Equipped items on the rigged Beginner (#68): CharacterWardrobe grafts each worn wearable onto the character's
## skeleton by bone name (CharacterLook.graft), holds weapons and shields in their sockets, and takes off the preset's
## own garments each slot replaces (hats: the hair on the crown and the female preset's bow). Hiding garments is
## tested without the pack on a hand-made merged mesh; the rest needs the art pack (SKIP without it).

var art: ArtPack


func before_each() -> void:
	art = ArtPack.load_installed()


func _skip(test: String) -> bool:
	if art.present():
		return false
	print("SKIP %s: no art pack installed (bash scripts/art_pack.sh fetch)" % test)
	return true


# --- hiding garments, without the pack ------------------------------------------------------------------------------

## A skeleton holding one merged mesh `mesh_name` with one triangle per garment (garment i at y = i), each garment's
## index range recorded the way ArtImport records it.
func _merged(mesh_name: String, garments: Array) -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.add_bone("root")
	var verts := PackedVector3Array()
	var ranges := {}
	for i in garments.size():
		verts.append_array([Vector3(0, i, 0), Vector3(1, i, 0), Vector3(0, i, 1)])
		ranges[garments[i]] = PackedInt32Array([i * 3, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var index := PackedInt32Array()
	for i in verts.size():
		index.append(i)
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Warm porcelain"
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	mi.set_meta(ArtImport.GARMENTS_META, ranges)
	sk.add_child(mi)
	return sk


func _ys(mi: MeshInstance3D) -> Array:
	var arrays := mi.mesh.surface_get_arrays(0)
	var out := []
	for i: int in arrays[Mesh.ARRAY_INDEX]:
		var y := int((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)[i].y)
		if not out.has(y):
			out.append(y)
	return out


func test_hiding_one_garment_keeps_the_others_in_the_same_mesh() -> void:
	var sk := _merged("Clothing_Warm porcelain", ["collar", "sock"])
	var mi: MeshInstance3D = sk.get_child(0)
	var painted := StandardMaterial3D.new()
	mi.set_surface_override_material(0, painted)
	assert_eq(CharacterWardrobe.hide_garments(sk, {"Clothing_": ["sock"]}), 1, "one mesh changed")
	assert_eq(sk.get_child_count(), 1, "the collar's mesh stays: no new draw call")
	assert_eq(_ys(mi), [0], "only the collar's triangle is drawn")
	assert_eq(ArtImport.garments(mi), PackedStringArray(["collar"]), "it now holds the collar only")
	assert_eq(mi.get_surface_override_material(0), painted, "keeps its painted material")
	assert_eq(mi.mesh.surface_get_material(0).resource_name, "Warm porcelain", "and its own")
	sk.free()


func test_hiding_every_garment_of_a_mesh_removes_it() -> void:
	var sk := _merged("Clothing_Cloth sage", ["sleeve", "tunic"])
	var other := _merged("Hair_Hair chestnut", ["scalp"])
	var hair := other.get_child(0)
	other.remove_child(hair)
	other.free()
	sk.add_child(hair)
	assert_eq(CharacterWardrobe.hide_garments(sk, {"Clothing_": ["tunic", "sleeve", "hem"], "Hat_": ["*"]}), 1, "one mesh gone")
	var names := sk.get_children().map(func(n: Node) -> String: return String(n.name))
	assert_eq(names, ["Hair_Hair chestnut"], "the tunic and sleeves are freed (no silhouette, no draw call); the hair stays")
	assert_eq(CharacterWardrobe.hide_garments(sk, {"Hair_": ["*"]}), 1, "\"*\": every garment of the part")
	assert_eq(sk.get_child_count(), 0, "the hair is gone")
	sk.free()


# --- dressing the pack's Beginner ----------------------------------------------------------------------------------

## One item per slot the pack covers (male top and bottom), and the female pieces.
const MALE_KIT := {"weapon": "541", "hat": "708", "top": "933", "bottom": "1157", "shoes": "1306", "gloves": "1439",
	"earrings": "900"}
const FEMALE_KIT := {"weapon": "585", "hat": "711", "top": "937", "bottom": "1160", "shoes": "1305", "gloves": "1440"}


func _preset(gender: String) -> Node3D:
	return art.instance(ArtPack.PRESET, PlayerVisual.preset_for(gender))


func _skeleton_of(model: Node) -> Skeleton3D:
	return model.find_child("Skeleton3D", true, false) as Skeleton3D


## Every garment the model's `prefix` meshes still draw.
func _garments(model: Node, prefix: String) -> Array:
	var out := []
	for n in _skeleton_of(model).get_children():
		if n is MeshInstance3D and String(n.name).begins_with(prefix):
			for g in ArtImport.garments(n):
				if not out.has(g):
					out.append(g)
	out.sort()
	return out


func test_each_slot_is_worn_on_the_skeleton_or_held_in_its_socket() -> void:
	if _skip("test_each_slot_is_worn_on_the_skeleton_or_held_in_its_socket"):
		return
	for kit: Dictionary in [MALE_KIT, FEMALE_KIT]:
		var gender := "male" if kit == MALE_KIT else "female"
		var model := _preset(gender)
		var sk := _skeleton_of(model)
		var out := CharacterWardrobe.dress(model, kit, art)
		assert_eq(out["missing"], [], "%s: the pack covers every piece" % gender)
		for slot: String in kit:
			if slot == "weapon":
				var held: Node3D = out["held"].get(slot)
				assert_true(held != null and held.get_parent().name == &"socket_weapon_r", "%s weapon in socket_weapon_r" % gender)
				assert_true(held != null and held.transform.is_equal_approx(Transform3D.IDENTITY), "%s weapon at the socket's grip, not rescaled" % gender)
				continue
			var worn: Array = out["worn"].get(slot, [])
			assert_false(worn.is_empty(), "%s %s worn" % [gender, slot])
			for mi: MeshInstance3D in worn:
				assert_eq(mi.get_parent(), sk, "%s %s on the body's skeleton" % [gender, slot])
				assert_eq(mi.get_node(mi.skeleton), sk, "%s %s skinned to it" % [gender, slot])
				assert_true(mi.transform.is_equal_approx(Transform3D.IDENTITY), "%s %s inherits the rig's scale" % [gender, slot])
				assert_true(String(mi.name).begins_with("Wear_"), "%s %s: the wearable's own meshes (%s)" % [gender, slot, mi.name])
				for b in mi.skin.get_bind_count():
					assert_eq(mi.skin.get_bind_bone(b), sk.find_bone(mi.skin.get_bind_name(b)), "%s %s bound by bone name" % [gender, slot])
		model.free()


func test_the_replaced_default_garments_are_taken_off() -> void:
	if _skip("test_the_replaced_default_garments_are_taken_off"):
		return
	var male := _preset("male")
	assert_eq(_garments(male, "Clothing_"), ["button", "collar", "hem", "satchel", "satchel_strap", "sleeve", "sock", "trouser", "tunic"], "the male preset as built")
	CharacterWardrobe.dress(male, {"top": "933"}, art)
	assert_eq(_garments(male, "Clothing_"), ["satchel", "satchel_strap", "sock", "trouser"], "a top takes off the tunic and what is sewn on it")
	CharacterWardrobe.dress(male, {"bottom": "1157"}, art)
	assert_eq(_garments(male, "Clothing_"), ["satchel", "satchel_strap", "sock"], "a bottom takes off the trousers")
	assert_eq(_garments(male, "Footwear_"), ["lace", "shoe", "sole"], "the shoes stay")
	CharacterWardrobe.dress(male, {"shoes": "1306"}, art)
	assert_eq(_garments(male, "Footwear_"), [], "shoes take off the preset's shoes")
	assert_eq(_garments(male, "Clothing_"), ["satchel", "satchel_strap", "sock"], "the socks show above them")
	male.free()
	var female := _preset("female")
	assert_eq(_garments(female, "Hat_"), ["ribbon_knot", "ribbon_loop"], "the female preset's bow")
	CharacterWardrobe.dress(female, {"bottom": "1160"}, art)
	assert_eq(_garments(female, "Clothing_"), ["button", "collar", "hem", "sleeve", "sock", "tunic"], "a skirt takes off the trousers and the flared skirt")
	CharacterWardrobe.dress(female, {"hat": "708"}, art)
	assert_eq(_garments(female, "Hat_"), [], "a cap takes off the bow")
	assert_eq(_garments(female, "Hair_"), ["pigtail", "pigtail_tie", "temple"], "and the hair on the crown; the pigtails hang below")
	female.free()


func test_a_headband_keeps_the_crown_and_takes_off_the_fringe_and_the_bow() -> void:
	if _skip("test_a_headband_keeps_the_crown_and_takes_off_the_fringe_and_the_bow"):
		return
	for band in ["711", "712", "713", "714", "715"]:
		var female := _preset("female")
		CharacterWardrobe.dress(female, {"hat": band}, art)
		assert_eq(_garments(female, "Hat_"), [], "%s takes off the bow" % band)
		assert_eq(_garments(female, "Hair_"), ["pigtail", "pigtail_tie", "scalp", "temple"], "%s keeps the hair on the crown; only the fringe it would cut through goes" % band)
		female.free()


func test_a_new_top_colours_the_preset_shoulders_and_sandals_bare_the_feet() -> void:
	if _skip("test_a_new_top_colours_the_preset_shoulders_and_sandals_bare_the_feet"):
		return
	var male := _preset("male")
	var sk := _skeleton_of(male)
	CharacterWardrobe.dress(male, {"top": "934", "shoes": "1305"}, art)
	var shoulder := sk.get_node("Body_Cloth sage") as MeshInstance3D
	assert_eq(shoulder.get_active_material(0).resource_name, "Wear Grey", "the Grey T-Shirt's cloth on the puffed shoulders")
	assert_eq(_garments(male, "Footwear_"), ["shoe"], "sandals keep the preset's foot")
	var foot := sk.get_node("Footwear_Cocoa leather") as MeshInstance3D
	assert_eq(foot.get_active_material(0).resource_name, "Skin 0", "in the skin colour: a bare foot")
	assert_false("sock" in _garments(male, "Clothing_"), "no socks in sandals")
	male.free()


func test_gloves_and_earrings_take_nothing_off() -> void:
	if _skip("test_gloves_and_earrings_take_nothing_off"):
		return
	var plain := _preset("male")
	var model := _preset("male")
	var out := CharacterWardrobe.dress(model, {"gloves": "1440", "earrings": "900"}, art)
	assert_eq(out["hidden"], 0, "nothing hidden")
	for prefix in ["Body_", "Clothing_", "Footwear_", "Hair_", "Face_"]:
		assert_eq(_garments(model, prefix), _garments(plain, prefix), prefix + " as built")
	plain.free()
	model.free()


func test_an_item_without_a_model_is_listed_and_not_shown() -> void:
	if _skip("test_an_item_without_a_model_is_listed_and_not_shown"):
		return
	var model := _preset("male")
	# 2000 is a potion: no wearable and no held model; a slot without an item is skipped.
	var out := CharacterWardrobe.dress(model, {"top": "2000", "weapon": "nope", "hat": ""}, art)
	assert_eq(out["missing"], ["2000", "nope"], "both listed, in slot order")
	assert_eq(out["worn"], {}, "nothing worn")
	model.free()


func test_without_the_pack_nothing_changes() -> void:
	var empty := ArtPack.load_from("res://_no_pack_here")
	var sk := _merged("Clothing_Cloth sage", ["tunic"])
	sk.name = "Skeleton3D"
	var root := Node3D.new()
	root.add_child(sk)
	var out := CharacterWardrobe.dress(root, MALE_KIT, empty)
	assert_eq(out, {"worn": {}, "held": {}, "hidden": 0, "missing": []}, "nothing dressed")
	assert_eq(sk.get_child_count(), 1, "the tunic stays")
	root.free()


# --- PlayerVisual -------------------------------------------------------------------------------------------------

## A PlayerVisual ("Visual", no blob shadow, processed by hand) for `gender` wearing `equipped`, on a fresh player.
func _visual(rig: MonsterTestRig, gender: String, equipped: Dictionary, use_pack: bool = true) -> PlayerVisual:
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var vis := PlayerVisual.new()
	vis.name = "Visual"
	vis.blob_shadow = false
	vis.use_library_model = use_pack
	vis.gender = gender
	vis.equipment = equipped
	p.add_child(vis)
	vis.set_process(false)
	return vis


func _item_ids_on(vis: PlayerVisual) -> Array:
	var out := []
	for n in vis.model.find_children("*", "", true, false):
		if n.has_meta(&"item_id") and not out.has(String(n.get_meta(&"item_id"))):
			out.append(String(n.get_meta(&"item_id")))
	out.sort()
	return out


func test_the_player_wears_its_equipment_and_follows_every_change() -> void:
	if _skip("test_the_player_wears_its_equipment_and_follows_every_change"):
		return
	var rig := MonsterTestRig.create(db(), 68)
	rig.floor(40.0)
	var vis := _visual(rig, "male", {"weapon": "541", "top": "933"})
	assert_eq(vis.worn, {"weapon": "541", "top": "933"}, "the equipment shown")
	assert_eq(_item_ids_on(vis), ["541", "933"], "sword and undershirt on the model")
	assert_true(vis.model.find_child("socket_weapon_r", true, false).get_child(0).get_meta(&"item_id") == "541", "the sword in the right hand")
	var old := vis.model
	vis.set_equipment({"weapon": "541", "top": "933", "ring_1": ""})
	assert_true(vis.model == old, "the same items: no rebuild")
	vis.set_equipment({"weapon": "576", "top": "933", "hat": "708"})
	assert_true(vis.model != old, "a swap rebuilds at once")
	assert_eq(_item_ids_on(vis), ["576", "708", "933"], "axe, skullcap and undershirt")
	vis.set_equipment({"weapon": "576"})
	assert_eq(_item_ids_on(vis), ["576"], "unequipped pieces are gone")
	assert_true(vis.model.find_child("Clothing_Cloth sage", true, false) != null, "and the tunic is back")
	vis.set_look("male", {"hair_style": 0, "face": 1, "skin": 2})
	assert_eq(_item_ids_on(vis), ["576"], "a new look keeps the equipment")
	vis.set_gender("female")
	assert_eq(vis.preset, "Beginner_Female", "another preset")
	assert_eq(_item_ids_on(vis), ["576"], "still holding the axe")
	rig.free_all()


func test_the_see_through_outline_covers_what_is_worn_and_held() -> void:
	if _skip("test_the_see_through_outline_covers_what_is_worn_and_held"):
		return
	var rig := MonsterTestRig.create(db(), 68)
	rig.floor(40.0)
	var vis := _visual(rig, "male", MALE_KIT)
	var skinned := 0
	for o in vis.outline_meshes():
		if o.skin != null:
			skinned += 1
	var worn := 0
	for slot in vis.wardrobe["worn"]:
		worn += (vis.wardrobe["worn"][slot] as Array).size()
	assert_true(worn > 0, "worn meshes")
	# Every worn (skinned) mesh has a skinned hull; the sword's static parts follow the hand (checked through a clip).
	var sword := vis.model.find_child("socket_weapon_r", true, false).get_child(0) as Node3D
	vis.set_see_through(true)
	var mi := sword.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var rest := mi.global_transform
	var ap := vis.model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	ap.play("attack")
	ap.seek(0.3, true)
	(vis.model.find_child("Skeleton3D", true, false) as Skeleton3D).force_update_all_bone_transforms()
	(vis.model.find_child("hand_R", true, false) as BoneAttachment3D).on_skeleton_update()
	assert_false(mi.global_transform.origin.is_equal_approx(rest.origin), "the swing moves the sword (%s)" % [rest.origin])
	vis.step_see_through(1.0)
	var hull := vis.held_outline(mi)
	assert_true(hull != null, "the sword has an outline")
	if hull != null:
		assert_true(hull.global_transform.is_equal_approx(mi.global_transform), "the sword's outline follows the swing: %s vs %s" % [hull.global_transform.origin, mi.global_transform.origin])
	assert_true(skinned >= worn, "worn meshes have skinned outline hulls (%d hulls, %d worn)" % [skinned, worn])
	rig.free_all()


func test_without_the_pack_the_placeholder_ignores_equipment() -> void:
	var rig := MonsterTestRig.create(db(), 68)
	rig.floor(40.0)
	var vis := _visual(rig, "male", MALE_KIT, false)
	assert_false(vis.rigged(), "the placeholder")
	assert_eq(vis.worn, {}, "nothing shown")
	var old := vis.model
	vis.set_equipment({"hat": "708"})
	assert_true(vis.model == old, "no rebuild without a rig")
	rig.free_all()


func test_a_fully_equipped_player_costs_few_extra_draw_calls() -> void:
	if _skip("test_a_fully_equipped_player_costs_few_extra_draw_calls"):
		return
	for kit: Dictionary in [MALE_KIT, FEMALE_KIT]:
		var gender := "male" if kit == MALE_KIT else "female"
		var plain := _preset(gender)
		var model := _preset(gender)
		CharacterWardrobe.dress(model, kit, art)
		var base := ArtImport.draw_calls(plain)
		var dressed := ArtImport.draw_calls(model)
		print("NOTE %s: preset %d draw calls, fully equipped %d" % [gender, base, dressed])
		# Each wearable is 2-4 merged surfaces and the weapon 4-5; what it covers is taken off.
		assert_true(dressed <= base + 24, "%s: %d draw calls (preset %d)" % [gender, dressed, base])
		plain.free()
		model.free()
