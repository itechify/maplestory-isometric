class_name TrailLoader
extends RefCounted
## Attaches ribbon geometry to MapDefinitions' trails from the export (MAP_ARCHITECTURE.md sections 4.3, 4.6).
##
## Stopgap: World_Trails.json trails[] names each trail's meshes but carries no centreline yet (requested from the
## Blender export). MapDefinitions uses the sidecar's centreline when it has one; otherwise this reads the trail's
## main mesh (trails[].mesh) from the World_Trails visual glb (the live chunk when the world loaded visuals, else
## the glb itself: ~10 ms) and derives the rows with TrailGeometry.ribbon(). A plank bridge part (*_BridgeDeck) at
## the far end is appended plank by plank (TrailGeometry.deck_rows()).


## Attaches every trail's ribbon. `visual_root`: the instantiated World_Trails visual chunk when already loaded.
## Returns warnings (a trail whose ribbon could not be derived; the caller's finish_trails() then keeps it warp).
static func attach(defs: MapDefinitions, sidecars: WorldSidecars, visual_root: Node = null) -> PackedStringArray:
	var out: PackedStringArray = []
	var entries := defs.sidecar_trails()
	if entries.is_empty():
		return out
	var chunk := ""
	for n in sidecars.chunks:
		if (sidecars.chunks[n] as Dictionary).get("trails", null) is Array:
			chunk = String(n)
	var root := visual_root
	var owned := false
	if root == null:
		var path := sidecars.file_path(chunk, "visual")
		var res: Resource = load(path) if path != "" and ResourceLoader.exists(path) else null
		if not (res is PackedScene):
			out.append("trails: cannot load %s to derive the trail ribbons" % path)
			return out
		root = (res as PackedScene).instantiate()
		owned = true
	var meshes := {}
	for m in root.find_children("*", "MeshInstance3D", true, false):
		meshes[String(m.name)] = m
	var slope := defs.tuning.num("trails", "top_max_slope_deg")
	for e in entries:
		if not (e is Dictionary):
			continue
		var from_map := String(defs.id_of_slug.get(String(e.get("from_chunk", "")), ""))
		var p := defs.portal(from_map, String(e.get("from_portal", "")))
		var t := defs.trail(p.link_id) if p != null else null
		if t == null:
			out.append("trails: %s matches no trail link" % String(e.get("mesh", "?")))
			continue
		if t.has_geometry():
			continue  # the sidecar's own centreline
		var main: MeshInstance3D = meshes.get(String(e.get("mesh", "")), null)
		if main == null:
			out.append("trails: %s has no mesh %s in the visual glb" % [t.link_id, String(e.get("mesh", ""))])
			continue
		var ends := _ends(defs, t)
		var r := TrailGeometry.ribbon(triangles(main, root), ends[0], ends[1], slope)
		if not bool(r.ok):
			out.append("trails: %s ribbon not derived (%s)" % [t.link_id, String(r.error)])
			continue
		var notes: PackedStringArray = r.notes
		var c: PackedVector3Array = r.centre
		var l: PackedVector3Array = r.left
		var rr: PackedVector3Array = r.right
		var h: PackedFloat32Array = r.half
		var sa: PackedVector3Array = r.side_a
		var sb: PackedVector3Array = r.side_b
		for part in e.get("parts", []):
			if String(part).contains("BridgeDeck") and meshes.has(String(part)):
				var n0 := c.size()
				var added := _append_deck(triangles(meshes[String(part)], root), ends[1].point, slope, c, l, rr, h)
				for k in range(n0, c.size()):
					sa.append(l[k])
					sb.append(rr[k])
				notes.append("plank bridge %s: %d rows appended" % [String(part), added])
				TrailGeometry.clean_side(sa)
				TrailGeometry.clean_side(sb)
		defs.attach_trail_geometry(t.link_id, c, l, rr, h, "mesh", notes, sa, sb)
	if owned:
		root.free()
	return out


## World-space triangle corners of every surface of `mi` (its transform relative to `root` applied).
static func triangles(mi: MeshInstance3D, root: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mi.mesh == null:
		return out
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			for v in verts:
				out.append(xf * v)
		else:
			for i in idx:
				out.append(xf * verts[i])
	return out


## Each end of the trail as {point, normal (into that end's map)}: its gate (origin and normal), else its portal's
## anchor and inward direction. The ribbon's cap at that end is its part deepest along the normal.
static func _ends(defs: MapDefinitions, t: TrailDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in 2:
		var g := t.gates[i]
		if g != null:
			out.append({"point": g.origin, "normal": g.normal})
			continue
		var p: PortalDef = defs.graph.portals.get(t.portal_keys[i], null)
		out.append({"point": p.anchor_transform.origin if p != null else Vector3.ZERO, "normal": p.inward if p != null else Vector3.BACK})
	return out


## Appends the deck planks lying beyond the ribbon's far end toward `end_hint` as rows. Returns how many.
static func _append_deck(tris: PackedVector3Array, end_hint: Vector3, slope: float, c: PackedVector3Array,
		l: PackedVector3Array, r: PackedVector3Array, h: PackedFloat32Array) -> int:
	var last := c[c.size() - 1]
	var to_end := Vector3(end_hint.x - last.x, 0.0, end_hint.z - last.z)
	var span := to_end.length()
	if span < 0.5:
		return 0
	var dir := to_end / span
	var rows := TrailGeometry.deck_rows(tris, slope)
	var keep: Array[Dictionary] = []
	for row in rows:
		var d := Vector3((row.centre as Vector3).x - last.x, 0.0, (row.centre as Vector3).z - last.z).dot(dir)
		if d > 0.1 and d < span + 0.5:
			row["d"] = d
			keep.append(row)
	keep.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.d) < float(b.d))
	for row in keep:
		var p: Vector3 = row.centre
		# The plank's own long axis is the row's lateral, signed like the previous row's (left stays left as the
		# bridge turns).
		var lat: Vector3 = row.axis
		var last_left := l[l.size() - 1] - c[c.size() - 1]
		if lat.dot(Vector3(last_left.x, 0.0, last_left.z)) < 0.0:
			lat = -lat
		c.append(p)
		l.append(p + lat * float(row.half))
		r.append(p - lat * float(row.half))
		h.append(float(row.half))
	return keep.size()
