class_name TrailGeometry
extends RefCounted
## Derives a trail's ribbon from its exported triangles: the two side edges of its walkable top (side walls follow
## them) and rows along it (centreline and half-width: the trail zone, the bot's path, the HUD). Pure.
##
## Stopgap until the Blender export writes the centreline into World_Trails.json trails[] (MapDefinitions then uses
## that field; see WORLD_RUNTIME.md "Trails"). Iteration One builds a trail (src/misostory/trails.py build_trail)
## as rows across the path: each row has a left and a right top-edge vertex at one height, the top is a strip of
## quads between consecutive rows (one width along the whole causeway), sloped flanks fall away outside the edges
## (49.6 deg or steeper; the top is at most 36 deg), and each end is a straight cap across the exit, square to the
## sides. The export cuts the mesh on a 2 m grid (extra vertices, T-junctions), and sharp turns fold the inner edge
## of the strip over itself. So:
##   1. keep the triangles whose normal is within `max_slope_deg` of vertical (the top; flanks and caps drop out,
##      even on the hidden lane whose top and flanks share one material);
##   2. weld vertices by position, take the boundary edges (used by one kept triangle) and chain them into loops;
##      the longest loop is the ribbon outline;
##   3. clean it: T-junctions and folds show up as spikes and zigzags (the outline doubling back on itself,
##      ZIGZAG_DEG or more) and are cut;
##   4. corners are the square turns of the outline (CORNER_MIN_DEG..CORNER_MAX_DEG); of the runs between
##      consecutive corners, the one nearest each end's point (its gate) is that end's cap;
##   5. the runs between the caps are the two sides (walls follow them, cleaned of any remaining reversal);
##   6. rows: one side every ROW_STEP_M, each point paired with the nearest point of the other side; the trail's
##      half-width is the median pairing (it has one width by construction) and each row's centre lies that far
##      from its side point toward the other side, so a fold or a bend never drags the centreline.
## A plank bridge at the trail's far end (the 000001006 trail: the causeway stops where the bridge begins) is
## appended from the deck's planks: deck_rows() turns each plank into one row.

## Vertices closer than this are one vertex (glTF splits vertices by normal and UV).
const WELD_M := 0.001
## Spacing of the derived rows along the trail.
const ROW_STEP_M := 0.5
## An outline vertex turning this much or more is a spike or zigzag (the outline doubles back): cut.
const ZIGZAG_DEG := 135.0
## A side vertex turning this much or more reverses the side (a fold on the inner edge of a bend): cut.
const SIDE_REVERSAL_DEG := 100.0
## Self-crossings of a side are looked for this many segments ahead (folds are local).
const UNTANGLE_WINDOW := 40
## The ribbon's corners: where the sides meet the caps, square (a grid cut across a cap end skews one a little: the
## 000001006 causeway meets its bridge at 113 deg).
const CORNER_MIN_DEG := 65.0
const CORNER_MAX_DEG := 125.0


## The ribbon of `tris` (a flat list of triangle corners, world space). `end_a` / `end_b`: {"point": Vector3,
## "normal": Vector3} of each end (a gate's origin and normal; the point marks where the cap is). Returns {"ok",
## "centre", "left", "right" (rows: PackedVector3Array), "half" (PackedFloat32Array), "side_a", "side_b" (the raw
## edges from end a to end b: PackedVector3Array), "caps" ([Vector3, Vector3]: cap midpoints), "error", "notes"}.
static func ribbon(tris: PackedVector3Array, end_a: Dictionary, end_b: Dictionary, max_slope_deg: float) -> Dictionary:
	var out := {"ok": false, "centre": PackedVector3Array(), "left": PackedVector3Array(), "right": PackedVector3Array(),
		"half": PackedFloat32Array(), "side_a": PackedVector3Array(), "side_b": PackedVector3Array(), "caps": [],
		"error": "", "notes": PackedStringArray()}
	var notes: PackedStringArray = out.notes
	var weld := _weld(_top_triangles(tris, max_slope_deg))
	var verts: PackedVector3Array = weld.verts
	var faces: PackedInt32Array = weld.faces
	if faces.is_empty():
		out["error"] = "no up-facing triangles"
		return out
	var loops := _boundary_loops(faces, verts.size())
	if loops.is_empty():
		out["error"] = "no boundary loop"
		return out
	var loop: PackedInt32Array = loops[0]
	var best := -1.0
	for l: PackedInt32Array in loops:
		var per := _perimeter(l, verts)
		if per > best:
			best = per
			loop = l
	if loops.size() > 1:
		notes.append("%d boundary loops; kept the longest (%.1f m)" % [loops.size(), best])
	var pts := PackedVector3Array()
	for i in loop:
		pts.append(verts[i])
	var cut := _clean_outline(pts, ZIGZAG_DEG)
	if cut > 0:
		notes.append("%d spike or zigzag points cut from the outline" % cut)
	if pts.size() < 4:
		out["error"] = "ribbon outline has %d vertices" % pts.size()
		return out
	var corners := PackedInt32Array()
	for i in pts.size():
		var turn := _turn_deg(pts, i)
		if turn >= CORNER_MIN_DEG and turn <= CORNER_MAX_DEG:
			corners.append(i)
	if corners.size() < 4:
		out["error"] = "ribbon outline has %d square corners (needs 4)" % corners.size()
		return out
	var ka := _nearest_run(pts, corners, end_a.get("point", Vector3.ZERO), -1)
	var kb := _nearest_run(pts, corners, end_b.get("point", Vector3.ZERO), ka)
	var ca := PackedInt32Array([corners[ka], corners[(ka + 1) % corners.size()]])
	var cb := PackedInt32Array([corners[kb], corners[(kb + 1) % corners.size()]])
	var sides := _split(pts, ca, cb)
	if String(sides.error) != "":
		out["error"] = String(sides.error)
		return out
	var side_a: PackedVector3Array = sides.a
	var side_b: PackedVector3Array = sides.b
	var folds := clean_side(side_a) + clean_side(side_b)
	if folds > 0:
		notes.append("%d reversing side points cut (folds on the inner edge of a bend)" % folds)
	if corners.size() > 4:
		notes.append("%d square corners on the outline (4 expected); the caps are the runs nearest the gates" % corners.size())
	var rows := _rows(side_a, side_b)
	out["centre"] = rows.centre
	out["left"] = rows.left
	out["right"] = rows.right
	out["half"] = rows.half
	out["side_a"] = side_a
	out["side_b"] = side_b
	out["caps"] = [_mean_of(pts, ca), _mean_of(pts, cb)]
	out["ok"] = true
	return out


## One row per plank of a deck mesh: each connected component of up-facing triangles is a plank top (or its
## underside); its row is the component's centroid at the top's height, with half its length as the half-width and
## its long axis (across the path) as "axis". A plank's top and underside give one row. Rows are returned unordered:
## {"centre": Vector3, "half": float, "axis": Vector3}.
static func deck_rows(tris: PackedVector3Array, max_slope_deg: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var weld := _weld(_top_triangles(tris, max_slope_deg))
	var verts: PackedVector3Array = weld.verts
	var faces: PackedInt32Array = weld.faces
	if faces.is_empty():
		return out
	var parent := PackedInt32Array()
	parent.resize(verts.size())
	for k in verts.size():
		parent[k] = k
	for f in range(0, faces.size(), 3):
		_union(parent, faces[f], faces[f + 1])
		_union(parent, faces[f], faces[f + 2])
	var groups := {}
	for f in range(0, faces.size(), 3):
		var root := _find(parent, faces[f])
		if not groups.has(root):
			groups[root] = {}
		var members: Dictionary = groups[root]
		for c in 3:
			members[faces[f + c]] = true
	for root in groups:
		var ids: Array = (groups[root] as Dictionary).keys()
		var sum := Vector3.ZERO
		var top := -INF
		for v in ids:
			sum += verts[int(v)]
			top = maxf(top, verts[int(v)].y)
		var c := sum / float(ids.size())
		# A plank lies across the path: its long axis (the principal axis of its corners in XZ) is the row's lateral,
		# and half its extent along that axis the half-width, whatever its turn along a curving bridge.
		var sxx := 0.0
		var szz := 0.0
		var sxz := 0.0
		for v in ids:
			var dx := verts[int(v)].x - c.x
			var dz := verts[int(v)].z - c.z
			sxx += dx * dx
			szz += dz * dz
			sxz += dx * dz
		var angle := 0.5 * atan2(2.0 * sxz, sxx - szz)
		var axis := Vector3(cos(angle), 0.0, sin(angle))
		var lo := INF
		var hi := -INF
		for v in ids:
			var o := (verts[int(v)] - c).dot(axis)
			lo = minf(lo, o)
			hi = maxf(hi, o)
		var row := {"centre": Vector3(c.x + axis.x * (lo + hi) * 0.5, top, c.z + axis.z * (lo + hi) * 0.5),
			"half": (hi - lo) * 0.5, "axis": axis}
		var merged := false
		for o in out:
			var oc: Vector3 = o.centre
			if Vector2(oc.x - c.x, oc.z - c.z).length() < 0.15:
				o["centre"] = oc if oc.y >= top else (row.centre as Vector3)
				o["half"] = maxf(float(o.half), float(row.half))
				merged = true
				break
		if not merged:
			out.append(row)
	return out


## Makes an open side polyline (a wall line) the envelope of the walkable top, in place: self-crossings are cut
## out (_untangle) and reversing vertices removed (_clean_side). Returns how many points were removed.
static func clean_side(pts: PackedVector3Array) -> int:
	return _untangle(pts) + _clean_side(pts)


## `pts` resampled to `count` points evenly spaced by 3D arc length (end points kept).
static func resample_count(pts: PackedVector3Array, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.size() < 2 or count < 2:
		return pts.duplicate()
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
	var total := cum[cum.size() - 1]
	var j := 1
	for k in count:
		var s := total * float(k) / float(count - 1)
		while j < pts.size() - 1 and cum[j] < s:
			j += 1
		var seg := cum[j] - cum[j - 1]
		var t := 0.0 if seg <= 1e-9 else clampf((s - cum[j - 1]) / seg, 0.0, 1.0)
		out.append(pts[j - 1].lerp(pts[j], t))
	return out


## `pts` resampled every `step` meters of 3D arc length (end points kept).
static func resample_step(pts: PackedVector3Array, step: float) -> PackedVector3Array:
	if pts.size() < 2:
		return pts.duplicate()
	var total := 0.0
	for k in range(1, pts.size()):
		total += pts[k].distance_to(pts[k - 1])
	return resample_count(pts, maxi(2, int(ceil(total / maxf(step, 0.01))) + 1))


# --- the outline ------------------------------------------------------------------------------------------------

## Removes near-duplicate neighbours and every vertex where the closed outline turns `max_turn_deg` or more (a
## spike: out along a grid line and straight back at a T-junction; a zigzag: the inner edge folding at a sharp
## bend), in place. Returns how many points were removed beyond the duplicates.
static func _clean_outline(pts: PackedVector3Array, max_turn_deg: float) -> int:
	var removed := 0
	var changed := true
	var guard := 0
	while changed and guard < 2000:
		guard += 1
		changed = false
		_dedupe(pts, true)
		var n := pts.size()
		if n < 4:
			return removed
		for i in n:
			var a := pts[posmod(i - 1, n)]
			var c := pts[(i + 1) % n]
			if Vector2(a.x - c.x, a.z - c.z).length() < 0.02 or _turn_deg(pts, i) >= max_turn_deg:
				pts.remove_at(i)
				removed += 1
				changed = true
				break
	return removed


## Cuts the loops out of an open side polyline where it crosses itself (the inner edge of a sharp bend: one section's
## edge runs past the next one's before turning back), in place: the two crossing segments are joined at their
## intersection and everything between is dropped, which leaves the envelope of the walkable top. Only crossings
## within UNTANGLE_WINDOW segments are looked for (folds are local). Returns how many points were removed.
static func _untangle(pts: PackedVector3Array) -> int:
	var removed := 0
	var i := 0
	while i < pts.size() - 3:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var cut := false
		for j in range(mini(pts.size() - 2, i + UNTANGLE_WINDOW), i + 1, -1):
			var c := Vector2(pts[j].x, pts[j].z)
			var d := Vector2(pts[j + 1].x, pts[j + 1].z)
			var hit: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
			if hit == null:
				continue
			var x: Vector2 = hit
			var t := 0.0 if a.distance_to(b) < 1e-6 else a.distance_to(x) / a.distance_to(b)
			var y := lerpf(pts[i].y, pts[i + 1].y, t)
			var n := j - i
			for _k in n:
				pts.remove_at(i + 1)
			pts.insert(i + 1, Vector3(x.x, y, x.y))
			removed += n - 1
			cut = true
			break
		if not cut:
			i += 1
	return removed


## Removes inner vertices of an open side polyline where it reverses (SIDE_REVERSAL_DEG or more), in place, keeping
## both end points (the cap corners). Returns how many were removed.
static func _clean_side(pts: PackedVector3Array) -> int:
	var removed := 0
	var changed := true
	var guard := 0
	while changed and guard < 2000:
		guard += 1
		changed = false
		_dedupe(pts, false)
		for i in range(1, pts.size() - 1):
			var a := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z)
			var b := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z)
			if a.length_squared() < 1e-8 or b.length_squared() < 1e-8:
				continue
			if rad_to_deg(absf(a.angle_to(b))) >= SIDE_REVERSAL_DEG:
				pts.remove_at(i)
				removed += 1
				changed = true
				break
	return removed


## Removes consecutive points closer than 1 cm in XZ (`closed`: also the last against the first), in place.
static func _dedupe(pts: PackedVector3Array, closed: bool) -> void:
	var i := 0
	while pts.size() > 1 and i < pts.size():
		var j := i + 1
		if j >= pts.size():
			if not closed:
				break
			j = 0
			if j == i:
				break
		if Vector2(pts[i].x - pts[j].x, pts[i].z - pts[j].z).length() < 0.01:
			pts.remove_at(j)
			if j < i:
				i -= 1
			continue
		i += 1


## Index k of the run corners[k] -> corners[k + 1] (along the outline) whose mean point is nearest `point` in XZ,
## skipping run `skip`.
static func _nearest_run(pts: PackedVector3Array, corners: PackedInt32Array, point: Vector3, skip: int) -> int:
	var best := -1
	var best_d := INF
	var n := pts.size()
	for k in corners.size():
		if k == skip:
			continue
		var i := corners[k]
		var j := corners[(k + 1) % corners.size()]
		var s := Vector3.ZERO
		var c := 0
		var m := i
		while true:
			s += pts[m]
			c += 1
			if m == j:
				break
			m = (m + 1) % n
		var mean := s / float(c)
		var d := Vector2(mean.x - point.x, mean.z - point.z).length()
		if d < best_d:
			best_d = d
			best = k
	return best


## The outline's two sides between the caps `ca` and `cb` (corner index pairs): {"a", "b" (each from cap a to cap
## b), "error"}.
static func _split(pts: PackedVector3Array, ca: PackedInt32Array, cb: PackedInt32Array) -> Dictionary:
	var out := {"a": PackedVector3Array(), "b": PackedVector3Array(), "error": ""}
	var n := pts.size()
	if ca[0] < 0 or ca[1] < 0 or cb[0] < 0 or cb[1] < 0 or ca[0] == ca[1] or cb[0] == cb[1]:
		out.error = "no cap corners (%s, %s)" % [ca, cb]
		return out
	# Orient the start cap so that walking forward from s1 reaches s2 before either end corner.
	var s1 := ca[0]
	var s2 := ca[1]
	if not (_fd(s1, s2, n) < _fd(s1, cb[0], n) and _fd(s1, s2, n) < _fd(s1, cb[1], n)):
		s1 = ca[1]
		s2 = ca[0]
		if not (_fd(s1, s2, n) < _fd(s1, cb[0], n) and _fd(s1, s2, n) < _fd(s1, cb[1], n)):
			out.error = "the caps interleave on the outline"
			return out
	var e1 := cb[0] if _fd(s2, cb[0], n) < _fd(s2, cb[1], n) else cb[1]
	var e2 := cb[1] if e1 == cb[0] else cb[0]
	if not (_fd(e1, e2, n) < _fd(e1, s1, n)):
		out.error = "the end cap is not between the sides"
		return out
	var a := PackedVector3Array()
	var i := s2
	while true:
		a.append(pts[i])
		if i == e1:
			break
		i = (i + 1) % n
	var b := PackedVector3Array()
	i = s1
	while true:
		b.append(pts[i])
		if i == e2:
			break
		i = posmod(i - 1, n)
	if a.size() < 2 or b.size() < 2:
		out.error = "degenerate sides (%d / %d points)" % [a.size(), b.size()]
		return out
	out.a = a
	out.b = b
	return out


## Rows from two sides (both from end a to end b): side a every ROW_STEP_M, each point paired with the nearest point
## of side b. The half-width is the median pairing; each centre lies that far from its side-a point toward side b.
## {"centre", "left" (side a's side), "right", "half"}.
static func _rows(side_a: PackedVector3Array, side_b: PackedVector3Array) -> Dictionary:
	var l := resample_step(side_a, ROW_STEP_M)
	var partner := PackedVector3Array()
	var widths := PackedFloat32Array()
	var j := 0
	for k in l.size():
		var q: Vector3
		if k == 0:
			q = side_b[0]
		elif k == l.size() - 1:
			q = side_b[side_b.size() - 1]  # both sides end at the cap's corners
		else:
			var hit := _nearest_on(side_b, l[k], j)
			j = int(hit.index)
			q = hit.point
		partner.append(q)
		widths.append(Vector2(l[k].x - q.x, l[k].z - q.z).length())
	var sorted := widths.duplicate()
	sorted.sort()
	var half := sorted[sorted.size() / 2] * 0.5
	var c := PackedVector3Array()
	var h := PackedFloat32Array()
	for k in l.size():
		var d := partner[k] - l[k]
		var flat := Vector3(d.x, 0.0, d.z)
		var p := l[k].lerp(partner[k], 0.5)
		if flat.length_squared() > 1e-8:
			p = l[k] + flat.normalized() * half
			p.y = (l[k].y + partner[k].y) * 0.5
		c.append(p)
		h.append(half)
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for k in c.size():
		var lat := Vector3(l[k].x - c[k].x, 0.0, l[k].z - c[k].z)
		if lat.length_squared() < 1e-8:
			var t := c[mini(k + 1, c.size() - 1)] - c[maxi(k - 1, 0)]
			lat = Vector3.UP.cross(Vector3(t.x, 0.0, t.z))
		lat = lat.normalized() if lat.length_squared() > 1e-12 else Vector3.RIGHT
		left.append(c[k] + lat * h[k])
		right.append(c[k] - lat * h[k])
	return {"centre": c, "left": left, "right": right, "half": h}


## The point of polyline `line` nearest `p` in XZ, searching forward from segment `from` (rows advance along the
## trail): {"point" (Vector3, height interpolated), "index" (segment)}.
static func _nearest_on(line: PackedVector3Array, p: Vector3, from: int) -> Dictionary:
	var best := {"point": line[0], "index": 0}
	var best_d := INF
	var q := Vector2(p.x, p.z)
	for i in range(maxi(from - 2, 0), line.size() - 1):
		var a := Vector2(line[i].x, line[i].z)
		var b := Vector2(line[i + 1].x, line[i + 1].z)
		var ab := b - a
		var t := 0.0 if ab.length_squared() < 1e-12 else clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := q.distance_to(a + ab * t)
		if d < best_d:
			best_d = d
			best = {"point": line[i].lerp(line[i + 1], t), "index": i}
		elif d > best_d + 6.0:
			break  # well past the nearest stretch
	return best


## Turning angle (deg, XZ) of the closed outline at vertex i, from neighbours at least 5 cm away.
static func _turn_deg(pts: PackedVector3Array, i: int) -> float:
	var n := pts.size()
	var p := Vector2(pts[i].x, pts[i].z)
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	for k in range(1, n):
		var q := pts[posmod(i - k, n)]
		a = p - Vector2(q.x, q.z)
		if a.length() >= 0.05:
			break
	for k in range(1, n):
		var q := pts[(i + k) % n]
		b = Vector2(q.x, q.z) - p
		if b.length() >= 0.05:
			break
	if a.length_squared() < 1e-9 or b.length_squared() < 1e-9:
		return 0.0
	return rad_to_deg(absf(a.angle_to(b)))


## Forward distance from index x to index y on a loop of n.
static func _fd(x: int, y: int, n: int) -> int:
	return posmod(y - x, n)


static func _mean_of(pts: PackedVector3Array, idx: PackedInt32Array) -> Vector3:
	var s := Vector3.ZERO
	var k := 0
	for i in idx:
		if i >= 0:
			s += pts[i]
			k += 1
	return s / float(maxi(k, 1))


# --- mesh internals ---------------------------------------------------------------------------------------------

static func _top_triangles(tris: PackedVector3Array, max_slope_deg: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var min_cos := cos(deg_to_rad(max_slope_deg))
	for k in range(0, tris.size() - 2, 3):
		var a := tris[k]
		var b := tris[k + 1]
		var c := tris[k + 2]
		var nrm := (b - a).cross(c - a)
		var l := nrm.length()
		if l < 1e-9:
			continue
		if absf(nrm.y) / l >= min_cos:
			out.append(a)
			out.append(b)
			out.append(c)
	return out


## {"verts": PackedVector3Array (welded), "faces": PackedInt32Array (3 indices per kept, non-degenerate face)}.
static func _weld(tris: PackedVector3Array) -> Dictionary:
	var index := {}
	var verts := PackedVector3Array()
	var faces := PackedInt32Array()
	var q := 1.0 / WELD_M
	for k in range(0, tris.size() - 2, 3):
		var ids := PackedInt32Array()
		for c in 3:
			var v := tris[k + c]
			var key := Vector3i(roundi(v.x * q), roundi(v.y * q), roundi(v.z * q))
			if not index.has(key):
				index[key] = verts.size()
				verts.append(v)
			ids.append(int(index[key]))
		if ids[0] == ids[1] or ids[1] == ids[2] or ids[0] == ids[2]:
			continue
		faces.append_array(ids)
	return {"verts": verts, "faces": faces}


## Closed loops of boundary edges (edges used by exactly one face), as vertex index lists.
static func _boundary_loops(faces: PackedInt32Array, vertex_count: int) -> Array[PackedInt32Array]:
	var uses := {}
	for f in range(0, faces.size(), 3):
		for c in 3:
			var a := faces[f + c]
			var b := faces[f + (c + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			uses[key] = int(uses.get(key, 0)) + 1
	var adj := {}
	for key: Vector2i in uses:
		if int(uses[key]) != 1:
			continue
		if not adj.has(key.x):
			adj[key.x] = PackedInt32Array()
		if not adj.has(key.y):
			adj[key.y] = PackedInt32Array()
		# A typed local shares the dictionary's array (appending through an `as` cast would change a copy).
		var ax: PackedInt32Array = adj[key.x]
		ax.append(key.y)
		var ay: PackedInt32Array = adj[key.y]
		ay.append(key.x)
	var used_edges := {}
	var loops: Array[PackedInt32Array] = []
	for start in adj:
		for first in (adj[start] as PackedInt32Array):
			var e0 := Vector2i(mini(start, first), maxi(start, first))
			if used_edges.has(e0):
				continue
			var loop := PackedInt32Array([int(start)])
			used_edges[e0] = true
			var prev := int(start)
			var cur := int(first)
			var guard := 0
			while cur != int(start) and guard < vertex_count + 2:
				guard += 1
				loop.append(cur)
				var nxt := -1
				for cand in (adj[cur] as PackedInt32Array):
					var e := Vector2i(mini(cur, cand), maxi(cur, cand))
					if not used_edges.has(e) and cand != prev:
						nxt = cand
						break
				if nxt < 0:
					for cand in (adj[cur] as PackedInt32Array):
						var e2 := Vector2i(mini(cur, cand), maxi(cur, cand))
						if not used_edges.has(e2):
							nxt = cand
							break
				if nxt < 0:
					break
				used_edges[Vector2i(mini(cur, nxt), maxi(cur, nxt))] = true
				prev = cur
				cur = nxt
			if cur == int(start) and loop.size() >= 3:
				loops.append(loop)
	return loops


static func _perimeter(loop: PackedInt32Array, verts: PackedVector3Array) -> float:
	var p := 0.0
	for k in loop.size():
		p += verts[loop[k]].distance_to(verts[loop[(k + 1) % loop.size()]])
	return p


static func _find(parent: PackedInt32Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb
