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
