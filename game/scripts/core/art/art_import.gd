@tool
class_name ArtImport
extends RefCounted
## The import normalisation of the pinned art pack (Project art, ADR 0002; the owner's rules on #59, ticket #62).
## scripts/core/art/art_pack_post_import.gd runs normalize() on every pack GLB as Godot imports it (project.godot sets
## it as the scene importer's default import script; it leaves every file outside the pack alone), so the game loads
## models that already follow the rules:
##
##   Looping     character idle/walk/run/climb, monster Idle/Walk, the box's Idle and a drop's Hover loop; every
##               other clip of those families plays once. Effect (Loop) clips are left exactly as imported.
##   Root        animation never moves the body: in every character, monster and box clip except `sit`, the `root`
##               bone's translation is held at its rest position (one key at the rest pose; a clip that never moved
##               the root gets that key too, so leaving `sit` never leaves the body sunk). Sit keeps its drop (#59
##               decision 5, lined up with The Green Relaxer). Bone rotations and every other bone are untouched.
##               A drop's Hover keeps its root lift: that lift is the drop's bob on the ground (GroundDrop then
##               leaves out its procedural bob).
##   Draw calls  a model's meshes are merged per material, and for characters and their parts per name prefix as
##               well (Body_, Clothing_, Face_, Footwear_, Hair_, Hat_, Prop_, Uniform_, Wear_), so the merged nodes
##               are named "<Prefix>_<material>" and customization can still hide or swap a part by prefix. Each merged
##               character mesh remembers which of its triangles each source garment drew (garments(),
##               garment_indices(): the Beginner's collar and socks share a material), so equipment can hide one
##               garment without another draw call (#68). Skinning
##               (the shared Skin and skeleton path), materials and the BoneAttachment3D sockets (socket_weapon_r,
##               socket_shield_l, socket_hat, socket_back) survive; static parts are baked into their parent's space.
##   Scale       characters (player presets, NPCs) and character parts (wearables, hair and face modules) get the one
##               character factor (art_pack.json character_scale.factor) on the rig node(s) under the scene root.
##               The root itself stays identity, so the game places and scales it freely; a part re-parented under a
##               character's (already scaled) skeleton must not be scaled again. Monsters keep their size: model_fit
##               sizes them in the game.
##
## Environment models are not normalised: the Blender build imports them (ADR 0002).

const CHARACTER := "character"
const CHARACTER_PART := "character_part"
const MONSTER := "monster"
const BREAKABLE := "breakable"
const DROP := "drop"
const EFFECT := "effect"
const ITEM := "item"
const ENVIRONMENT := "environment"

## family -> the clips that loop; every other clip of these families plays once.
const LOOPING := {CHARACTER: ["idle", "walk", "run", "climb"], MONSTER: ["Idle", "Walk"], BREAKABLE: ["Idle"],
	DROP: ["Hover"]}
## The families whose clips hold the root bone at rest (every clip but ROOT_MOTION_KEPT).
const ROOT_HELD := [CHARACTER, MONSTER, BREAKABLE]
const ROOT_BONE := "root"
## Clips whose root translation is kept.
const ROOT_MOTION_KEPT := ["sit"]
const PART_PREFIXES := ["Body", "Clothing", "Face", "Footwear", "Hair", "Hat", "Prop", "Uniform", "Wear"]
## Meta on a merged character mesh: garment -> PackedInt32Array [first index, index count, ...] (garments()).
const GARMENTS_META := &"art_garments"
const SCALED := [CHARACTER, CHARACTER_PART]
const MERGED := [CHARACTER, CHARACTER_PART, MONSTER, BREAKABLE, DROP, EFFECT, ITEM]
const MONSTER_CATEGORIES := {"monster": MONSTER, "breakable": BREAKABLE, "drop": DROP, "effect": EFFECT}


## The family of one pack file (pack-root relative path), given the pack's monsters/manifest.json; "" when unknown.
static func family_of(pack_path: String, monsters_manifest: Dictionary) -> String:
	if pack_path.begins_with("characters/glb/"):
		return CHARACTER
	if pack_path.begins_with("characters/wearables/") or pack_path.begins_with("characters/modules/"):
		return CHARACTER_PART
	if pack_path.begins_with("equipment/glb/"):
		return ITEM
	if pack_path.begins_with("environment/"):
		return ENVIRONMENT
	if pack_path.begins_with("monsters/") and pack_path.count("/") == 1:
		var file := pack_path.get_file()
		for a in monsters_manifest.get("assets", []):
			if a is Dictionary and String(a.get("glb", "")) == file:
				return String(MONSTER_CATEGORIES.get(String(a.get("category", "")), ""))
	return ""


## Applies the family's rules to an imported scene in place. Returns {family, draw_calls_before, draw_calls_after}.
static func normalize(root: Node3D, family: String, character_scale: float) -> Dictionary:
	var stats := {"family": family, "draw_calls_before": draw_calls(root)}
	if LOOPING.has(family):
		for ap in _players(root):
			_set_loops(ap, LOOPING[family])
			if family in ROOT_HELD:
				_hold_root(ap)
	if family in MERGED:
		_merge(root, family in [CHARACTER, CHARACTER_PART])
	if family in SCALED and not is_equal_approx(character_scale, 1.0):
		for child in root.get_children():
			if child is Node3D:
				var n := child as Node3D
				n.transform = Transform3D(n.basis.scaled(Vector3.ONE * character_scale), n.position * character_scale)
	stats["draw_calls_after"] = draw_calls(root)
	return stats


## Surfaces drawn by the model's visible meshes (one draw call each, before shadow passes).
static func draw_calls(root: Node) -> int:
	var n := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh != null and (mi as MeshInstance3D).visible:
			n += (mi as MeshInstance3D).mesh.get_surface_count()
	return n


## The union of the meshes' bounds in the root's space (rest pose), without needing the scene tree.
static func visual_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = _to_root(root, mi) * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


static func _to_root(root: Node, node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _players(root: Node) -> Array:
	return root.find_children("*", "AnimationPlayer", true, false)


static func _animations(ap: AnimationPlayer) -> Dictionary:
	var out := {}
	for lib_name in ap.get_animation_library_list():
		var lib := ap.get_animation_library(lib_name)
		for clip in lib.get_animation_list():
			out[String(clip)] = lib.get_animation(clip)
	return out


static func _set_loops(ap: AnimationPlayer, looping: Array) -> void:
	var clips := _animations(ap)
	for clip in clips:
		(clips[clip] as Animation).loop_mode = Animation.LOOP_LINEAR if clip in looping else Animation.LOOP_NONE


## Holds the root bone's translation at rest in every clip but ROOT_MOTION_KEPT.
static func _hold_root(ap: AnimationPlayer) -> void:
	var base := ap.get_node_or_null(ap.root_node)
	if base == null:
		return
	var skeleton: Skeleton3D = null
	for sk in base.find_children("*", "Skeleton3D", true, false):
		if (sk as Skeleton3D).find_bone(ROOT_BONE) >= 0:
			skeleton = sk
			break
	if skeleton == null:
		return
	var sk_path := String(base.get_path_to(skeleton))
	var rest := skeleton.get_bone_rest(skeleton.find_bone(ROOT_BONE)).origin
	var clips := _animations(ap)
	for clip in clips:
		if clip in ROOT_MOTION_KEPT:
			continue
		var a: Animation = clips[clip]
		for t in range(a.get_track_count() - 1, -1, -1):
			var path := a.track_get_path(t)
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D and String(path.get_concatenated_subnames()) == ROOT_BONE \
					and String(path.get_concatenated_names()) == sk_path:
				a.remove_track(t)
		var t := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t, NodePath(sk_path + ":" + ROOT_BONE))
		a.position_track_insert_key(t, 0.0, rest)


## The garments merged into a character mesh, sorted ("tunic", "sleeve", "sock", ...; [] for a mesh that was not
## merged by part).
static func garments(mi: MeshInstance3D) -> PackedStringArray:
	var out := PackedStringArray((mi.get_meta(GARMENTS_META, {}) as Dictionary).keys())
	out.sort()
	return out


## The positions in a merged character mesh's index buffer that draw `garment`'s triangles ([] when it has none).
static func garment_indices(mi: MeshInstance3D, garment: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var ranges: PackedInt32Array = (mi.get_meta(GARMENTS_META, {}) as Dictionary).get(garment, PackedInt32Array())
	for r in range(0, ranges.size(), 2):
		for i in ranges[r + 1]:
			out.append(ranges[r] + i)
	return out


## A part mesh's garment: its name without the part prefix and Blender's numeric suffix ("Clothing_sleeve_001" ->
## "sleeve", "Hair_pigtail_tie" -> "pigtail_tie"); "" outside a part.
static func _garment_of(node_name: String, part: String) -> String:
	if part == "":
		return ""
	var parts := node_name.substr(part.length() + 1).split("_")
	while parts.size() > 1 and parts[parts.size() - 1].is_valid_int():
		parts.remove_at(parts.size() - 1)
	return "_".join(parts)


static func _part_of(node_name: String) -> String:
	var head := node_name.get_slice("_", 0)
	return head if head in PART_PREFIXES and node_name.length() > head.length() else ""


## Merges mesh instances that share a parent, a part prefix (when by_part), a material, a skin and a vertex format.
static func _merge(root: Node3D, by_part: bool) -> void:
	var groups := {}
	var order: Array = []
	var merged_nodes: Array = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not _mergeable(mi):
			continue
		var part := _part_of(String(mi.name)) if by_part else ""
		if by_part and part == "":
			continue
		var xf := Transform3D.IDENTITY if mi.skin != null else mi.transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var mat := mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			var key := "%d|%s|%d|%d|%s|%s" % [mi.get_parent().get_instance_id(), part,
				mat.get_instance_id() if mat != null else 0, mi.skin.get_instance_id() if mi.skin != null else 0,
				String(mi.skeleton), _signature(arrays)]
			if not groups.has(key):
				groups[key] = {"parent": mi.get_parent(), "part": part, "material": mat, "skin": mi.skin,
					"skeleton": mi.skeleton, "first": mi, "surfaces": []}
				order.append(key)
			groups[key].surfaces.append({"arrays": arrays, "xf": xf, "garment": _garment_of(String(mi.name), part)})
		merged_nodes.append(mi)
	if merged_nodes.is_empty():
		return
	var built: Array = []
	for key in order:
		var g: Dictionary = groups[key]
		var out := MeshInstance3D.new()
		var mat: Material = g.material
		var mat_name := mat.resource_name if mat != null and mat.resource_name != "" else "material"
		out.name = ("%s_%s" % [g.part, mat_name]) if g.part != "" else mat_name
		var ranges := {}
		out.mesh = _combine(g.surfaces, mat, ranges)
		var first: MeshInstance3D = g.first
		out.cast_shadow = first.cast_shadow
		out.layers = first.layers
		out.set_meta("art_merged_from", g.surfaces.size())
		if not ranges.is_empty():
			out.set_meta(GARMENTS_META, ranges)
		built.append([g.parent, out, g])
	for mi in merged_nodes:
		mi.get_parent().remove_child(mi)
		mi.free()
	for b in built:
		var parent: Node = b[0]
		var out: MeshInstance3D = b[1]
		var g: Dictionary = b[2]
		parent.add_child(out, true)
		out.owner = root
		if g.skin != null:
			out.skin = g.skin
			out.skeleton = g.skeleton


static func _mergeable(mi: MeshInstance3D) -> bool:
	if not (mi.mesh is ArrayMesh) or mi.get_child_count() > 0 or mi.mesh.get_blend_shape_count() > 0:
		return false
	if mi.skin != null and not mi.transform.is_equal_approx(Transform3D.IDENTITY):
		return false
	for s in mi.mesh.get_surface_count():
		if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		var arrays := mi.mesh.surface_get_arrays(s)
		for k in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			if arrays[k] != null:
				return false
	return true


## Which vertex channels a surface has, plus its bones per vertex: surfaces merge only with their own kind.
static func _signature(arrays: Array) -> String:
	var s := ""
	for k in Mesh.ARRAY_MAX:
		s += "1" if arrays[k] != null else "0"
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if arrays[Mesh.ARRAY_BONES] != null and verts.size() > 0:
		s += ":%d" % ((arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() / verts.size())
	return s


## Concatenates the surfaces into one; `ranges` receives garment -> [first index, index count, ...] in the result's
## index buffer for every surface that names its garment.
static func _combine(surfaces: Array, mat: Material, ranges: Dictionary = {}) -> ArrayMesh:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var first: Array = surfaces[0].arrays
	for k in Mesh.ARRAY_MAX:
		if first[k] != null:
			out[k] = first[k].duplicate()
			out[k].clear()
	if out[Mesh.ARRAY_INDEX] == null:
		out[Mesh.ARRAY_INDEX] = PackedInt32Array()
	var offset := 0
	for surf in surfaces:
		var a: Array = surf.arrays
		var xf: Transform3D = surf.xf
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var baked := not xf.is_equal_approx(Transform3D.IDENTITY)
		var nbasis := xf.basis.inverse().transposed()
		for k in Mesh.ARRAY_MAX:
			if out[k] == null or k == Mesh.ARRAY_INDEX:
				continue
			if not baked or not (k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT]):
				out[k].append_array(a[k])
			elif k == Mesh.ARRAY_VERTEX:
				for v in verts:
					out[k].append(xf * v)
			elif k == Mesh.ARRAY_NORMAL:
				for n in (a[k] as PackedVector3Array):
					out[k].append((nbasis * n).normalized())
			else:
				var tan: PackedFloat32Array = a[k]
				for i in range(0, tan.size(), 4):
					var t := (xf.basis * Vector3(tan[i], tan[i + 1], tan[i + 2])).normalized()
					out[k].append_array([t.x, t.y, t.z, tan[i + 3]])
		var first_index: int = out[Mesh.ARRAY_INDEX].size()
		if a[Mesh.ARRAY_INDEX] != null:
			for i in (a[Mesh.ARRAY_INDEX] as PackedInt32Array):
				out[Mesh.ARRAY_INDEX].append(i + offset)
		else:
			for i in verts.size():
				out[Mesh.ARRAY_INDEX].append(i + offset)
		offset += verts.size()
		var garment := String(surf.get("garment", ""))
		if garment != "":
			if not ranges.has(garment):
				ranges[garment] = PackedInt32Array()
			ranges[garment].append_array([first_index, out[Mesh.ARRAY_INDEX].size() - first_index])
	var flags := 0
	if out[Mesh.ARRAY_BONES] != null and offset > 0 and (out[Mesh.ARRAY_BONES] as PackedInt32Array).size() == offset * 8:
		flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, flags)
	mesh.surface_set_material(0, mat)
	return mesh
