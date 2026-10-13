class_name CharacterLook
extends RefCounted
## Puts a character's look (#67, CharacterAppearance: hair style, face, skin) on an instance of the art pack's rigged
## Beginner preset, the way the pack's characters/customization.json describes it:
##   hair  the preset's own Hair_ meshes are replaced by the chosen hair module's (customization hair.files);
##   face  the preset's own Face_ meshes are replaced by the chosen face module's (customization faces);
##   skin  every material whose name starts "Skin " (body, face, the face modules' "Skin 0.00N" nose) takes the chosen
##         skin palette colour (ArtPack.skin_color, already sRGB); cheek, iris and everything else stay as built.
## A choice equal to the preset's own base_recipe keeps the preset's meshes as they are; skin is painted every time,
## on duplicated materials (the imported ones are shared by every instance), so a grafted face never keeps the
## module's skin colour.
##
## graft() is the general part swap (wearables, #68, use it too): a pack part (hair or face module, wearable) has its
## own copy of the 17-bone rig; its skinned meshes move onto the character's Skeleton3D at identity and bind by bone
## name. The part's rig node carries the character scale (x0.7566) like the character's, so a grafted mesh inherits
## the scale from the character's rig and is never rescaled.
##
##   var model := art.instance(ArtPack.PRESET, "Beginner_Female")
##   CharacterLook.apply(model, character.appearance, "Beginner_Female", art)

const HAIR_PREFIX := "Hair_"
const FACE_PREFIX := "Face_"
const SKIN_MATERIAL_PREFIX := "Skin "


## Applies `look` (a CharacterAppearance look) to `model`, an instance of the preset `preset_name`. Returns what
## changed: {"hair": bool (module grafted), "face": bool, "skin_surfaces": int (surfaces painted)}.
static func apply(model: Node3D, look: Dictionary, preset_name: String, art: ArtPack) -> Dictionary:
	var out := {"hair": false, "face": false, "skin_surfaces": 0}
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or art == null or not art.present():
		return out
	var recipe := art.base_recipe(preset_name)
	var hair := int(look.get(CharacterAppearance.HAIR_STYLE, recipe.get("hair_style", -1)))
	if hair != int(recipe.get("hair_style", -1)):
		out["hair"] = _swap(skeleton, art.instance(ArtPack.HAIR, str(hair)), HAIR_PREFIX)
	var face := int(look.get(CharacterAppearance.FACE, recipe.get("face", -1)))
	var styles := art.face_styles()
	if face != int(recipe.get("face", -1)) and face >= 0 and face < styles.size():
		out["face"] = _swap(skeleton, art.instance(ArtPack.FACE, styles[face]), FACE_PREFIX)
	var skin := int(look.get(CharacterAppearance.SKIN, recipe.get("skin", 0)))
	if skin >= 0 and skin < art.skin_count():
		out["skin_surfaces"] = paint_skin(model, art.skin_color(skin))
	return out


## Moves every skinned mesh of `part` (an instanced pack part) onto `skeleton` and frees the part's own nodes.
## Each mesh lands at the skeleton's origin and is skinned to it, every bind resolved by bone name (a bind without
## a name takes its bone's name from the part's skeleton). Returns the grafted meshes; when any bind names a bone
## the skeleton lacks, nothing is grafted and [] is returned. The part is freed either way.
static func graft(part: Node, skeleton: Skeleton3D) -> Array[MeshInstance3D]:
	var moved: Array[MeshInstance3D] = []
	var plan: Array = []
	for n in part.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null or mi.mesh == null:
			continue
		var source := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		var skin := mi.skin.duplicate() as Skin
		for i in skin.get_bind_count():
			var bone_name := String(skin.get_bind_name(i))
			if bone_name == "" and source != null and skin.get_bind_bone(i) >= 0:
				bone_name = source.get_bone_name(skin.get_bind_bone(i))
			var target := skeleton.find_bone(bone_name) if bone_name != "" else -1
			if target < 0:
				part.free()
				return moved
			skin.set_bind_name(i, bone_name)
			skin.set_bind_bone(i, target)
		plan.append([mi, skin])
	for p: Array in plan:
		var mi: MeshInstance3D = p[0]
		mi.get_parent().remove_child(mi)
		mi.owner = null
		mi.transform = Transform3D.IDENTITY
		skeleton.add_child(mi, true)
		mi.skin = p[1]
		mi.skeleton = mi.get_path_to(skeleton)
		moved.append(mi)
	part.free()
	return moved


## Paints every surface of `root`'s meshes whose material name starts "Skin " with `color` (sRGB), on a duplicate
## of the material. Returns the number of surfaces painted.
static func paint_skin(root: Node, color: Color) -> int:
	var n := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if mat == null or not mat.resource_name.begins_with(SKIN_MATERIAL_PREFIX):
				continue
			var copy := mat.duplicate() as BaseMaterial3D
			copy.albedo_color = Color(color, mat.albedo_color.a)
			mi.set_surface_override_material(s, copy)
			n += 1
	return n


## Replaces the skeleton's `prefix` meshes by `module`'s (null: nothing changes). False when nothing was grafted.
static func _swap(skeleton: Skeleton3D, module: Node3D, prefix: String) -> bool:
	if module == null:
		return false
	# Only the module's own part (a face module is all Face_ meshes, a hair module all Hair_ ones; anything else stays
	# out). The preset's part is taken off first, so the module's meshes keep their names, and put back if the module
	# does not fit the skeleton.
	for n in module.find_children("*", "MeshInstance3D", true, false):
		if not String(n.name).begins_with(prefix):
			n.get_parent().remove_child(n)
			n.free()
	var old: Array = []
	for c in skeleton.get_children():
		if c is MeshInstance3D and String(c.name).begins_with(prefix):
			old.append(c)
	for c: Node in old:
		skeleton.remove_child(c)
	var grafted := graft(module, skeleton)
	if grafted.is_empty():
		for c: Node in old:
			skeleton.add_child(c)
		return false
	for c: Node in old:
		c.free()
	return true
