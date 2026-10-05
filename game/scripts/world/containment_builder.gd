class_name ContainmentBuilder
extends RefCounted
## Builds the invisible containment (MAP_ARCHITECTURE.md section 4.6), all on the containment layer (the player
## collides with it, monsters do not):
##   rings   one StaticBody3D per map: a box wall per edge of the map's footprint + ring offset
##           (MapDefinition.footprint, with its region extensions), spanning the map chunk's whole height (bounds)
##           from containment.margin_below_m below to margin_above_m above. The inner face of every wall lies on the
##           ring line, the wall outside it (outside by the polygon's winding, so a concave ring works); pieces are
##           lengthened by the wall thickness only at convex corners, which closes them without poking into the
##           region at a concave one. At each trail end (a GateDef into the map) the wall leaves a gap centred on the
##           gate, as wide as the corridor between the trail's side walls and at most the gate's width. Where a region
##           extension with keep_footprint_ring_below_y opens the layout's own ring line, that line keeps a low wall
##           up to that height ("Kept" pieces of the same body).
##   plugs   one StaticBody3D per gap, the missing piece of wall: enabled (containment layer) while the trail's link
##           is in warp mode, disabled (no layer) in edge mode. set_plugs() applies the PortalGraph modes.
##   walls   one StaticBody3D per trail: box walls along both ribbon edges, trails.side_wall_offset_m outward, from
##           trails.side_wall_below_m under the edge to side_wall_height_m above it, from gate plane to gate plane.

## Bodies created by build(): rings (Array[StaticBody3D], one per map), plugs (gate key -> StaticBody3D), walls
## (Array[StaticBody3D], one per trail with geometry), gaps (gate key -> {map_id, half_width}).
static func build(defs: MapDefinitions, parent: Node3D) -> Dictionary:
	var rings: Array[StaticBody3D] = []
	var plugs := {}
	var walls: Array[StaticBody3D] = []
	var gaps_out := {}
	var thickness := defs.tuning.num("containment", "wall_thickness_m")
	var below := defs.tuning.num("containment", "margin_below_m")
	var above := defs.tuning.num("containment", "margin_above_m")
	var side := defs.tuning.num("trails", "side_wall_offset_m")
	for id in defs.ids():
		var def := defs.get_def(id)
		if def.footprint.size() < 3:
			continue
		var gaps: Array[Dictionary] = []
		for t in defs.trails_of(id):
			var g := t.gate_into(id)
			if g == null:
				continue
			var half := g.half_width
			if t.has_geometry():
				var n := t.nearest(g.origin)
				if not n.is_empty():
					half = minf(half, float(n.half) + side)
			gaps.append({"key": g.key(), "point": Vector2(g.origin.x, g.origin.z), "half": half})
			gaps_out[g.key()] = {"map_id": id, "half_width": half, "link_id": t.link_id}
		var y0 := def.y_min - below
		var y1 := def.y_max + above
		var body := build_ring(def.footprint, y0, y1, thickness, gaps)
		for ext: Dictionary in def.region_extensions:
			var top := float(ext.get("keep_ring_below_y", NAN))
			if not is_nan(top) and top > y0:
				add_kept_ring(body, def.footprint_base, ext.ring_line, y0, top, thickness)
		body.name = "Ring_%s" % id
		body.set_meta("map_id", id)
		parent.add_child(body)
		rings.append(body)
		for gap in gaps:
			var plug := build_plug(def.footprint, gap, y0, y1, thickness)
			if plug == null:
				continue
			plug.name = ("Plug_%s" % String(gap.key)).validate_node_name()
			plug.set_meta("map_id", id)
			plug.set_meta("gate", String(gap.key))
			parent.add_child(plug)
			plugs[String(gap.key)] = plug
	for t in defs.trail_list():
		if not t.has_geometry():
			continue
		var w := build_trail_walls(t, defs.tuning, thickness)
		if w == null:
			continue
		w.name = ("Walls_%s" % t.link_id).validate_node_name()
		w.set_meta("link_id", t.link_id)
		parent.add_child(w)
		walls.append(w)
	set_plugs(defs, plugs)
	return {"rings": rings, "plugs": plugs, "walls": walls, "gaps": gaps_out}


## Enables each plug whose trail link is not in edge mode (warp mode closes the trail mouth).
static func set_plugs(defs: MapDefinitions, plugs: Dictionary) -> void:
	for key in plugs:
		var link := String(key).split(">")[0]
		set_plug_enabled(plugs[key], not defs.graph.is_edge(link))


static func set_plug_enabled(plug: StaticBody3D, on: bool) -> void:
	plug.collision_layer = WorldLayers.CONTAINMENT if on else 0
	plug.set_meta("enabled", on)
	for c in plug.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = not on


## A ring of box walls along `poly` (world XZ) from y0 to y1, walls `thickness` thick outside the line, leaving
## `gaps` ([{point: Vector2 on the line, half: float}]) open.
static func build_ring(poly: PackedVector2Array, y0: float, y1: float, thickness: float, gaps: Array[Dictionary] = []) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = WorldLayers.CONTAINMENT
	body.collision_mask = 0
	var side := outward_side(poly)
	var convex := convex_corners(poly)
	var h := maxf(y1 - y0, 0.1)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var length := (b - a).length()
		if length < 0.001:
			continue
		# The open intervals of this edge (arc length along a -> b).
		var cuts: Array[Vector2] = []
		for gap in gaps:
			var t := _edge_param(a, b, gap.point)
			if t >= 0.0:
				cuts.append(Vector2(t - float(gap.half), t + float(gap.half)))
		cuts.sort_custom(func(u: Vector2, v: Vector2) -> bool: return u.x < v.x)
		var start := 0.0
		var k := 0
		for c in cuts:
			if c.x > start:
				_wall_piece(body, a, b, side, start, c.x, y0, h, thickness, start == 0.0 and convex[i] == 1, false, "Wall%d_%d" % [i, k])
				k += 1
			start = maxf(start, c.y)
		if start < length:
			_wall_piece(body, a, b, side, start, length, y0, h, thickness, start == 0.0 and convex[i] == 1,
				convex[(i + 1) % poly.size()] == 1, "Wall%d_%d" % [i, k])
	return body


## The plug of one gap: the wall piece the gap left out (same line, thickness and height).
static func build_plug(poly: PackedVector2Array, gap: Dictionary, y0: float, y1: float, thickness: float) -> StaticBody3D:
	var side := outward_side(poly)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var t := _edge_param(a, b, gap.point)
		if t < 0.0:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = WorldLayers.CONTAINMENT
		body.collision_mask = 0
		_wall_piece(body, a, b, side, t - float(gap.half), t + float(gap.half), y0, maxf(y1 - y0, 0.1), thickness, false, false, "Plug")
		return body
	return null


## Side walls of a trail: along each ribbon edge pushed side_wall_offset_m outward, trimmed to the stretch between
## the two gate planes (outside both maps' regions), one box per edge segment.
static func build_trail_walls(t: TrailDef, tuning: WorldTuning, thickness: float) -> StaticBody3D:
	var offset := tuning.num("trails", "side_wall_offset_m")
	var height := tuning.num("trails", "side_wall_height_m")
	var below := tuning.num("trails", "side_wall_below_m")
	var body := StaticBody3D.new()
	body.collision_layer = WorldLayers.CONTAINMENT
	body.collision_mask = 0
	var count := 0
	for side in [t.side_a, t.side_b]:
		var line := PackedVector3Array()
		for e: Vector3 in (side as PackedVector3Array):
			var n := t.nearest(e)
			var c: Vector3 = n.point if not n.is_empty() else e
			var out := Vector3(e.x - c.x, 0.0, e.z - c.z)
			out = out.normalized() if out.length_squared() > 1e-9 else Vector3.ZERO
			line.append(e + out * offset)
		line = trim_to_gates(line, t.gates[0], t.gates[1])
		for i in range(line.size() - 1):
			var a := line[i]
			var b := line[i + 1]
			var a2 := Vector2(a.x, a.z)
			var b2 := Vector2(b.x, b.z)
			var length := a2.distance_to(b2)
			if length < 0.01:
				continue
			# Outward: away from the centreline at the segment's midpoint.
			var mid := (a + b) * 0.5
			var n := t.nearest(mid)
			var dir := (b2 - a2) / length
			var normal := Vector2(dir.y, -dir.x)
			if not n.is_empty():
				var c: Vector3 = n.point
				if normal.dot(Vector2(mid.x - c.x, mid.z - c.z)) < 0.0:
					normal = -normal
			var y0 := minf(a.y, b.y) - below
			var y1 := maxf(a.y, b.y) + height
			# Consecutive walls share their offset vertex, so their inner faces meet without a gap; no box sticks out past
			# it (on the inner side of a bend an extended box would reach into the trail).
			var shape := BoxShape3D.new()
			shape.size = Vector3(length, y1 - y0, thickness)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			var centre2 := (a2 + b2) * 0.5 + normal * (thickness * 0.5)
			cs.transform = Transform3D(Basis(Vector3(dir.x, 0.0, dir.y), Vector3.UP, Vector3(normal.x, 0.0, normal.y)),
				Vector3(centre2.x, (y0 + y1) * 0.5, centre2.y))
			cs.name = "Side%d" % count
			body.add_child(cs)
			count += 1
	if count == 0:
		body.free()
		return null
	return body


## The stretch of an edge polyline (running from the trail's end 0 to end 1) between the two gate planes: its
## start is cut where it first leaves `start_gate`'s map (signed distance <= 0), its end where it last leaves
## `end_gate`'s; crossing points are interpolated. Only those first and last crossings count: a curving trail can
## pass the far side of a gate's infinite plane elsewhere. A null gate keeps that end.
static func trim_to_gates(line: PackedVector3Array, start_gate: GateDef, end_gate: GateDef) -> PackedVector3Array:
	var out := line.duplicate()
	if start_gate != null:
		out = _trim_front(out, start_gate)
	if end_gate != null:
		out.reverse()
		out = _trim_front(out, end_gate)
		out.reverse()
	return out


## Drops the leading points of `line` inside `gate`'s map (signed distance > 0) and starts it at the crossing.
static func _trim_front(line: PackedVector3Array, gate: GateDef) -> PackedVector3Array:
	var k := 0
	while k < line.size() and gate.signed_distance(line[k]) > 0.0:
		k += 1
	if k == 0 or k >= line.size():
		return line if k == 0 else PackedVector3Array()
	var q := line[k - 1]
	var p := line[k]
	var dq := gate.signed_distance(q)
	var dp := gate.signed_distance(p)
	var out := PackedVector3Array([q.lerp(p, dq / (dq - dp))])
	out.append_array(line.slice(k))
	return out


## Where a region extension (`ext`, its ring line) opens the layout's own ring line (`base`,
## MapDefinition.footprint_base), adds that line's wall back to `body` from y0 up to `top` only: the parts of every
## base edge inside `ext`, outside the base line like any ring wall, named "Kept<edge>_<n>". Returns how many pieces it
## added.
static func add_kept_ring(body: StaticBody3D, base: PackedVector2Array, ext: PackedVector2Array, y0: float, top: float, thickness: float) -> int:
	if base.size() < 3 or ext.size() < 3 or top <= y0:
		return 0
	var side := outward_side(base)
	var count := 0
	for i in base.size():
		var a := base[i]
		var b := base[(i + 1) % base.size()]
		var length := a.distance_to(b)
		if length < 0.001:
			continue
		var dir := (b - a) / length
		for seg: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), ext):
			if seg.size() < 2:
				continue
			var s0 := clampf((seg[0] - a).dot(dir), 0.0, length)
			var s1 := clampf((seg[seg.size() - 1] - a).dot(dir), 0.0, length)
			if absf(s1 - s0) < 0.01:
				continue
			_wall_piece(body, a, b, side, minf(s0, s1), maxf(s0, s1), y0, top - y0, thickness, false, false, "Kept%d_%d" % [i, count])
			count += 1
	return count


## +1 when `poly` winds counter-clockwise in (x, z) (positive shoelace area), else -1: the outward normal of edge
## a -> b is Vector2(dir.y, -dir.x) * outward_side(poly). Works for concave polygons, unlike a centroid test.
static func outward_side(poly: PackedVector2Array) -> float:
	var area := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		area += p.x * q.y - q.x * p.y
	return 1.0 if area >= 0.0 else -1.0


## The outward unit normal of `poly`'s edge i (from poly[i] to poly[i + 1]). `side`: outward_side(poly) when known.
static func edge_outward(poly: PackedVector2Array, i: int, side: float = 0.0) -> Vector2:
	var a := poly[i]
	var b := poly[(i + 1) % poly.size()]
	var dir := (b - a).normalized()
	return Vector2(dir.y, -dir.x) * (side if side != 0.0 else outward_side(poly))


## 1 for each vertex of `poly` where the ring turns convex (the region's interior angle is below 180 degrees), else 0
## (concave or straight). Edges shorter than 1 mm are skipped.
static func convex_corners(poly: PackedVector2Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(poly.size())
	var side := outward_side(poly)
	var n := poly.size()
	for i in n:
		var prev := Vector2.ZERO
		for k in range(1, n):
			prev = poly[i] - poly[(i - k + n) % n]
			if prev.length() >= 0.001:
				break
		var next := Vector2.ZERO
		for k in range(1, n):
			next = poly[(i + k) % n] - poly[i]
			if next.length() >= 0.001:
				break
		out[i] = 1 if prev.cross(next) * side > 1e-9 else 0
	return out


## Arc length of `p` along edge a -> b when p lies on it (within 5 cm), else -1.
static func _edge_param(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var l := ab.length()
	if l < 1e-6:
		return -1.0
	var t := (p - a).dot(ab) / l
	if t < -0.05 or t > l + 0.05:
		return -1.0
	var off := absf((p - a).cross(ab) / l)
	return clampf(t, 0.0, l) if off <= 0.05 else -1.0


## One box of wall along edge a -> b between arc lengths s0 and s1, outside the line (`side`: outward_side() of the
## ring). The ring's convex corners are closed by extending a piece that starts or ends there by the wall thickness.
static func _wall_piece(body: StaticBody3D, a: Vector2, b: Vector2, side: float, s0: float, s1: float, y0: float,
		h: float, thickness: float, at_start_corner: bool, at_end_corner: bool, piece_name: String) -> void:
	var length := (b - a).length()
	var dir := (b - a) / length
	var normal := Vector2(dir.y, -dir.x) * side
	var lo := s0 - (thickness if at_start_corner else 0.0)
	var hi := s1 + (thickness if at_end_corner else 0.0)
	if hi - lo < 0.001:
		return
	var mid := a + dir * ((lo + hi) * 0.5) + normal * (thickness * 0.5)
	var shape := BoxShape3D.new()
	shape.size = Vector3(hi - lo, h, thickness)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(Basis(Vector3(dir.x, 0.0, dir.y), Vector3.UP, Vector3(normal.x, 0.0, normal.y)),
		Vector3(mid.x, y0 + h * 0.5, mid.y))
	cs.name = piece_name
	body.add_child(cs)
