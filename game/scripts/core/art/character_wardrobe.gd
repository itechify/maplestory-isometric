class_name CharacterWardrobe
extends RefCounted
## Puts a character's equipped items (#68, Equipment.equipped(): slot -> item id) on an instance of the art pack's
## rigged Beginner preset, after its look (CharacterLook):
##   wearables  (hat, top, bottom, overall, shoes, gloves, earrings, ...) are skinned parts with their own copy of the
##              17-bone rig: CharacterLook.graft moves their meshes onto the character's skeleton by bone name. They
##              inherit the character scale from its rig node and are never rescaled;
##   weapons    sit in socket_weapon_r and shields in socket_shield_l, at the socket's transform (the grip at the
##              origin, the long axis along the socket's +Y), so they follow the hand through every clip;
##   the preset's own garments a slot replaces are taken off first (HIDES): a merged mesh keeps the garments that
##              stay (ArtImport.garment_indices) and is freed once nothing of it is left, so a hidden garment costs no
##              draw call and leaves no X-ray fill or outline behind.
## Every model is looked up through ArtPack by item id (wearable files are named by MeowDB id, equipment files by game
## item id: only the pack's index is consistent). An item the pack has no model for is listed in "missing" and not
## shown (the stats never depend on it).
##
##   var worn := CharacterWardrobe.dress(model, character.equipment.equipped(), art)

## Equipment slot -> the preset garments it takes off: part prefix -> garments ("*": every garment of the part).
## Garment names are the pack's mesh names (ArtImport.garments). Read from the contact sheets
## (tools/wardrobe_sheet.tscn): the wearables are cut to the base body, so the base garment they cover pokes through.
##   top       the tunic and everything sewn on it; the satchel stays (it is carried, not worn).
##   bottom    the trousers and the female preset's flared skirt; the socks stay (shoes decide).
##   overall   both.
##   shoes     the preset's shoes; the socks show above them.
##   hat       the female preset's bow (Hat_; #67 keeps it on every hair style) and the hair on the crown, which a
##             cap covers; the hair that hangs below it (temples, long locks, pigtails) stays.
const HIDES := {
	"top": {"Clothing_": ["tunic", "sleeve", "collar", "button", "hem"]},
	"bottom": {"Clothing_": ["trouser", "flared_skirt", "skirt_piping"]},
	"overall": {"Clothing_": ["tunic", "sleeve", "collar", "button", "hem", "trouser", "flared_skirt", "skirt_piping"]},
	"shoes": {"Footwear_": ["*"]},
	"hat": {"Hat_": ["*"], "Hair_": ["scalp", "cowlick", "bun", "fringe"]},
}
## Items whose wearable needs another rule than its slot's (replaces HIDES[slot]):
##   headbands (711-715)  a band round the head, not a cap: the hair on the crown stays (without it the crown showed
##                        bald inside the band); the fringe the band would cut through and the bow go;
##   sandals (1305, 1327) straps on a sole: the preset's shoe stays as the bare foot (ITEM_PAINT), the laces, the
##                        sole and the socks go (without the shoe the sandal floated under no foot).
const BAND := {"Hat_": ["*"], "Hair_": ["fringe"]}
const ITEM_HIDES := {
	"711": BAND, "712": BAND, "713": BAND, "714": BAND,
	"715": BAND,
	"1305": {"Footwear_": ["lace", "sole"], "Clothing_": ["sock"]},
	"1327": {"Footwear_": ["lace", "sole"], "Clothing_": ["sock"]},
}
## Preset garments that stay but take another colour: garment -> WEAR (the wearable's own cloth, its first "Wear "
## material) or SKIN (the character's skin). The preset's puffed shoulders are cloth in the tunic's colour: under a
## new top they take the top's colour, as its sleeves. The sandals' bare foot is the preset's shoe in the skin colour.
const WEAR := "wear"
const SKIN := "skin"
const PAINT := {"top": {"shoulder": WEAR}, "overall": {"shoulder": WEAR}}
const ITEM_PAINT := {"1305": {"shoe": SKIN}, "1327": {"shoe": SKIN}}
## Slots held in a hand socket instead of worn on the skeleton.
const SOCKETS := {"weapon": "socket_weapon_r", "shield": "socket_shield_l"}
## Name of the node a held item hangs under its socket by.
const HELD_PREFIX := "Held_"


## Dresses `model` (an instance of a pack preset, with its Skeleton3D) in `equipped` (slot -> item id). Returns
## {"worn": {slot: [MeshInstance3D]}, "held": {slot: Node3D}, "hidden": int (preset meshes changed or removed),
## "missing": [item ids without a model]}. Without the pack or a skeleton nothing changes.
static func dress(model: Node3D, equipped: Dictionary, art: ArtPack) -> Dictionary:
	var out := {"worn": {}, "held": {}, "hidden": 0, "missing": []}
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or art == null or not art.present():
		return out
	var slots := PackedStringArray(equipped.keys())
	slots.sort()
	var hide := {}
	for slot in slots:
		var item_id := String(equipped[slot])
		if item_id == "" or SOCKETS.has(slot):
			continue
		var rule: Dictionary = ITEM_HIDES.get(item_id, HIDES.get(slot, {}))
		for prefix in rule:
			if not hide.has(prefix):
				hide[prefix] = []
			hide[prefix].append_array(rule[prefix])
	var skin := _skin_material(skeleton)
	out["hidden"] = hide_garments(skeleton, hide)
	for slot in slots:
		var item_id := String(equipped[slot])
		if item_id == "":
			continue
		if SOCKETS.has(slot):
			var held := _hold(model, SOCKETS[slot], art.instance(ArtPack.ITEM, item_id), item_id)
			if held == null:
				out["missing"].append(item_id)
			else:
				out["held"][slot] = held
			continue
		var part := art.instance(ArtPack.WEARABLE, item_id)
		var worn: Array[MeshInstance3D] = []
		if part != null:
			worn = CharacterLook.graft(part, skeleton)
		if worn.is_empty():
			out["missing"].append(item_id)
			continue
		for mi in worn:
			mi.set_meta(&"item_id", item_id)
		out["worn"][slot] = worn
		var paint: Dictionary = (PAINT.get(slot, {}) as Dictionary).merged(ITEM_PAINT.get(item_id, {}), true)
		for garment: String in paint:
			var mat := skin if paint[garment] == SKIN else _wear_material(worn)
			if mat != null:
				paint_garment(skeleton, garment, mat)
	return out


## Gives every preset mesh of the skeleton that draws only `garment` the material `mat` (on every surface). Returns
## how many meshes were painted.
static func paint_garment(skeleton: Node, garment: String, mat: Material) -> int:
	var n := 0
	for child in skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or ArtImport.garments(mi) != PackedStringArray([garment]):
			continue
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, mat)
		n += 1
	return n


## The skin as shown on the body (CharacterLook's painted copy, else the preset's own); null without one.
static func _skin_material(skeleton: Node) -> Material:
	for child in skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null and String(mi.name).begins_with("Body_"):
			var mat := mi.get_active_material(0)
			if mat != null and mat.resource_name.begins_with(CharacterLook.SKIN_MATERIAL_PREFIX):
				return mat
	return null


## A worn wearable's own cloth: its first material named "Wear ..." (the pack's wearable colours); null without one.
static func _wear_material(worn: Array[MeshInstance3D]) -> Material:
	for mi in worn:
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat != null and mat.resource_name.begins_with("Wear "):
				return mat
	return null


## Takes the garments `hide` names (part prefix -> garments, "*" for all) off the skeleton's merged meshes: a mesh
## with garments left keeps only their triangles (same node, same materials), a mesh with none left is freed. A mesh
## that does not record its garments (not merged by ArtImport) only goes with "*". Returns how many meshes changed.
static func hide_garments(skeleton: Node, hide: Dictionary) -> int:
	var changed := 0
	for child in skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var prefix := ""
		for p: String in hide:
			if String(mi.name).begins_with(p):
				prefix = p
		if prefix == "":
			continue
		var wanted: Array = hide[prefix]
		var has := ArtImport.garments(mi)
		var gone := PackedStringArray()
		for g in has:
			if g in wanted or "*" in wanted:
				gone.append(g)
		if gone.is_empty() and not (has.is_empty() and "*" in wanted):
			continue
		changed += 1
		if gone.size() == has.size():
			skeleton.remove_child(mi)
			mi.free()
		else:
			_keep_only(mi, gone)
	return changed


## Rebuilds `mi`'s mesh without the triangles of the garments in `gone` (one surface, as merged).
static func _keep_only(mi: MeshInstance3D, gone: PackedStringArray) -> void:
	var mesh := mi.mesh
	var arrays := mesh.surface_get_arrays(0)
	var old_index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var ranges: Dictionary = mi.get_meta(ArtImport.GARMENTS_META, {})
	var index := PackedInt32Array()
	var kept := {}
	for g: String in ArtImport.garments(mi):
		if g in gone:
			continue
		var r := PackedInt32Array()
		var own: PackedInt32Array = ranges[g]
		for k in range(0, own.size(), 2):
			r.append_array([index.size(), own[k + 1]])
			index.append_array(old_index.slice(own[k], own[k] + own[k + 1]))
		kept[g] = r
	arrays[Mesh.ARRAY_INDEX] = index
	var overrides := []
	for s in mesh.get_surface_count():
		overrides.append(mi.get_surface_override_material(s))
	var flags := SkinnedCopy.bone_flags_of(mesh, 0)
	var trimmed := ArrayMesh.new()
	trimmed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	trimmed.surface_set_material(0, mesh.surface_get_material(0))
	mi.mesh = trimmed
	mi.set_surface_override_material(0, overrides[0])
	mi.set_meta(ArtImport.GARMENTS_META, kept)


## Hangs `item` (a pack item instance, or null) under the model's `socket` at identity, so it takes the socket's
## transform and the rig's character scale. Returns the holder node, or null (no item, no socket: the item is freed).
static func _hold(model: Node3D, socket: String, item: Node3D, item_id: String) -> Node3D:
	if item == null:
		return null
	var at := model.find_child(socket, true, false) as Node3D
	if at == null:
		item.free()
		return null
	item.name = HELD_PREFIX + item_id
	item.transform = Transform3D.IDENTITY
	item.set_meta(&"item_id", item_id)
	at.add_child(item)
	return item
