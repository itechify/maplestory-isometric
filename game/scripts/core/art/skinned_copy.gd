@tool
class_name SkinnedCopy
extends RefCounted
## Single-surface copies of a (possibly skinned) mesh for the see-through passes: the player's outline hull
## (PlayerVisual.smoothed_hull) and a monster's X-ray fill (MonsterVisual.fill_mesh). A copy of a rig's mesh keeps each
## vertex's bones and weights and is bound to the source's skin and skeleton, so it follows every clip instead of
## standing in the bind pose (#63, #64). The import's merge (ArtImport) and the wardrobe's trim (CharacterWardrobe)
## decide the 8-bone flag here too.
##
##   var g := SkinnedCopy.gather(mesh, [0, 2])      # {verts, normals, index, bones, weights, per_vertex}
##   var copy := SkinnedCopy.build(g)               # one triangle surface (normals: pass your own)
##   SkinnedCopy.bind(copy_instance, source_instance)   # once both are in the same tree


## The triangle surfaces `surfaces` of `mesh` concatenated: positions, source normals (zero where a surface has none),
## indices (rebased; a surface without indices gets 0..n-1), and, when every surface carries the same number of bones
## per vertex, the bones and weights. per_vertex is that number, 0 when the copy is not skinned (a surface without
## bones, or two that differ: positions only). Non-triangle surfaces of an ArrayMesh are left out.
static func gather(mesh: Mesh, surfaces: Array) -> Dictionary:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var index := PackedInt32Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	# Bones per vertex shared by every surface so far: -1 = not known yet, 0 = not skinned alike.
	var per_vertex := -1
	for s in surfaces:
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(int(s)) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arr := mesh.surface_get_arrays(int(s))
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var k := 0
		if arr[Mesh.ARRAY_BONES] != null and arr[Mesh.ARRAY_WEIGHTS] != null and v.size() > 0:
			k = (arr[Mesh.ARRAY_BONES] as PackedInt32Array).size() / v.size()
		per_vertex = k if per_vertex < 0 or per_vertex == k else 0
		if per_vertex > 0:
			bones.append_array(arr[Mesh.ARRAY_BONES])
			weights.append_array(arr[Mesh.ARRAY_WEIGHTS])
		var base := verts.size()
		verts.append_array(v)
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		# One normal per vertex (missing ones are zero), so the normals stay aligned with the positions.
		nrm.resize(v.size())
		normals.append_array(nrm)
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if ind.is_empty():
			for i in v.size():
				index.append(base + i)
		else:
			for i in ind:
				index.append(base + i)
	return {"verts": verts, "normals": normals, "index": index, "bones": bones, "weights": weights,
		"per_vertex": maxi(per_vertex, 0)}


## One triangle surface from gather()'s result: its positions and indices, `normals` when given (else none), and the
## bones and weights when it is skinned. Null when it holds no triangles.
static func build(g: Dictionary, normals: PackedVector3Array = PackedVector3Array()) -> ArrayMesh:
	var index: PackedInt32Array = g.index
	if index.is_empty():
		return null
	var verts: PackedVector3Array = g.verts
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = index
	if not normals.is_empty():
		arrays[Mesh.ARRAY_NORMAL] = normals
	var per_vertex := int(g.per_vertex)
	var flags := 0
	if per_vertex > 0 and (g.bones as PackedInt32Array).size() == verts.size() * per_vertex:
		arrays[Mesh.ARRAY_BONES] = g.bones
		arrays[Mesh.ARRAY_WEIGHTS] = g.weights
		flags = bone_flags(per_vertex)
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return out


## The surface format flag for `per_vertex` bones per vertex: Godot reads 8 bones only with
## ARRAY_FLAG_USE_8_BONE_WEIGHTS (4 is the default).
static func bone_flags(per_vertex: int) -> int:
	return Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per_vertex == 8 else 0


## The 8-bone flag of an existing surface (a copy of it keeps the flag).
static func bone_flags_of(mesh: Mesh, surface: int) -> int:
	return (mesh as ArrayMesh).surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if mesh is ArrayMesh else 0


## Poses `copy` with `source`'s skin and skeleton (a no-op for a static source). Call it once both are in the same
## tree: the skeleton path is made relative to the copy, wherever it hangs.
static func bind(copy: MeshInstance3D, source: MeshInstance3D) -> void:
	if source.skin == null or source.skeleton.is_empty():
		return
	if source.skeleton.is_absolute():
		copy.skin = source.skin
		copy.skeleton = source.skeleton
		return
	var skeleton := source.get_node_or_null(source.skeleton)
	if skeleton == null:
		return
	copy.skin = source.skin
	copy.skeleton = copy.get_path_to(skeleton)
