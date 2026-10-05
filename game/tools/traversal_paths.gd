class_name TraversalPaths
extends RefCounted
## Bot paths with clearance (MAP_ARCHITECTURE.md section 4.13 L2/L3): the traversal bot follows a trail's centreline
## or a map's routes with RouteBot's pure pursuit, which walks straight into a prop standing on the walkable top (an
## Iteration One trail sign or rail on the inner side of a sharp bend, a rail across the 000001006 bridge's
## landing). A player steps around it; so does the bot: every stretch of the path whose body capsule is not clear of
## blocking and containment collision is replanned on a small grid (A*, GRID_M cells, 8 neighbours) around it, over
## cells with ground at about the path's height and a clear capsule, with no step higher than MAX_STEP_M. Stretches
## that cannot be replanned stay (the walk then reports the stall).

## The bot's clearance capsule: a little wider than the 0.3 m body, lifted over steps. A stretch is replanned where
## it fails; the replanning grid needs only the body itself (PLAN_RADIUS_M) to pass a squeeze.
const RADIUS_M := 0.38
const PLAN_RADIUS_M := 0.31
const LIFT_M := 0.5
const HEIGHT_M := 1.3
## Samples along each segment when looking for blocked stretches (m).
const SAMPLE_M := 0.15
## Replanning grid: cell size, margin around the blocked stretch, the stretch's extension on each side (points).
const GRID_M := 0.25
const MARGIN_M := 2.5
const EXTEND_POINTS := 3
## Ground within this height window around the path's height counts; steps up to MAX_STEP_M between cells.
const GROUND_UP_M := 0.8
const GROUND_DOWN_M := 1.2
const MAX_STEP_M := 0.4


## `pts` with points added every `step` m along walkable segments; a steep segment (a ladder, a rope, a drop, or a
## rise to jump: more than 1 m up per 1 m across) stays one segment, so RouteBot still sees it as a rise to climb.
static func resample(pts: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.is_empty():
		return out
	out.append(pts[0])
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var flat := Vector2(b.x - a.x, b.z - a.z).length()
		var n := 1 if absf(b.y - a.y) > maxf(flat, 0.01) else maxi(1, int(ceil(flat / maxf(step, 0.01))))
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / float(n)))
	return out


## `pts` (resampled) with every blocked stretch replanned around the obstacle. `max_offset` bounds how far (m) the
## new path may leave the old one. Returns {"path", "replanned" (stretches), "blocked" (stretches left)}.
static func with_clearance(world: IslandWorld, pts: PackedVector3Array, max_offset: float) -> Dictionary:
	var q := world.ground_query
	if q == null or pts.size() < 2:
		return {"path": pts, "replanned": 0, "blocked": 0}
	var blocked := PackedByteArray()
	blocked.resize(pts.size() - 1)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var t := Vector3(b.x - a.x, 0.0, b.z - a.z)
		# Ladder and rope stretches (steep) and drops keep their line: the climbable is there.
		if absf(b.y - a.y) > maxf(t.length(), 0.01) * 1.2:
			continue
		var n := maxi(1, int(ceil(a.distance_to(b) / SAMPLE_M)))
		for k in n + 1:
			var p := a.lerp(b, float(k) / float(n))
			if not _clear(q, p):
				blocked[i] = 1
				break
	# Blocked stretches as point ranges [s, e], extended on both sides and merged where they overlap.
	var ranges: Array[Vector2i] = []
	var i := 0
	while i < blocked.size():
		if blocked[i] == 0:
			i += 1
			continue
		var j := i
		while j < blocked.size() and blocked[j] == 1:
			j += 1
		var r := Vector2i(maxi(i - EXTEND_POINTS, 0), mini(j + EXTEND_POINTS, pts.size() - 1))
		if not ranges.is_empty() and r.x <= ranges[ranges.size() - 1].y:
			ranges[ranges.size() - 1].y = maxi(ranges[ranges.size() - 1].y, r.y)
		else:
			ranges.append(r)
		i = j
	var out := PackedVector3Array()
	var replanned := 0
	var left := 0
	var cursor := 0
	for r in ranges:
		for k in range(cursor, r.x):
			out.append(pts[k])
		var detour := _plan(q, pts, r.x, r.y, max_offset)
		if detour.is_empty():
			left += 1
			for k in range(r.x, r.y + 1):
				out.append(pts[k])
		else:
			replanned += 1
			out.append_array(detour)
		cursor = r.y + 1
	for k in range(cursor, pts.size()):
		out.append(pts[k])
	return {"path": out, "replanned": replanned, "blocked": left}


static func _clear(q: PhysicsGroundQuery, p: Vector3) -> bool:
	return q.is_clear(p + Vector3.UP * LIFT_M, RADIUS_M, HEIGHT_M)


## A* from pts[s] to pts[e] on a grid around pts[s..e] (cells within max_offset + MARGIN_M of the old path). Returns
## the new points (including both ends) or [] when there is none.
static func _plan(q: PhysicsGroundQuery, pts: PackedVector3Array, s: int, e: int, max_offset: float) -> PackedVector3Array:
	var seg := pts.slice(s, e + 1)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in seg:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var pad := max_offset + MARGIN_M
	lo -= Vector2(pad, pad)
	hi += Vector2(pad, pad)
	var w := int(ceil((hi.x - lo.x) / GRID_M)) + 1
	var h := int(ceil((hi.y - lo.y) / GRID_M)) + 1
	var cells := {}  # Vector2i -> y (float) or NAN when not passable
	var start := Vector2i(roundi((pts[s].x - lo.x) / GRID_M), roundi((pts[s].z - lo.y) / GRID_M))
	var goal := Vector2i(roundi((pts[e].x - lo.x) / GRID_M), roundi((pts[e].z - lo.y) / GRID_M))
	cells[start] = pts[s].y
	cells[goal] = pts[e].y
	var dist := {start: 0.0}
	var prev := {}
	var open: Array = [start]
	var closed := {}
	var found := false
	var guard := 0
	while not open.is_empty() and guard < 20000:
		guard += 1
		var bi := 0
		var bf := INF
		for k in open.size():
			var c: Vector2i = open[k]
			var f := float(dist[c]) + Vector2(c - goal).length() * GRID_M
			if f < bf:
				bf = f
				bi = k
		var cur: Vector2i = open[bi]
		open.remove_at(bi)
		if closed.has(cur):
			continue
		closed[cur] = true
		if cur == goal:
			found = true
			break
		var cy := float(cells[cur])
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var nb := Vector2i(cur.x + dx, cur.y + dz)
				if nb.x < 0 or nb.y < 0 or nb.x >= w or nb.y >= h or closed.has(nb):
					continue
				if not cells.has(nb):
					cells[nb] = _cell_y(q, lo, nb, seg, max_offset + MARGIN_M)
				var ny := float(cells[nb])
				if is_nan(ny) or absf(ny - cy) > MAX_STEP_M:
					continue
				var nd := float(dist[cur]) + Vector2(dx, dz).length() * GRID_M
				if nd < float(dist.get(nb, INF)):
					dist[nb] = nd
					prev[nb] = cur
					open.append(nb)
	if not found:
		return PackedVector3Array()
	var rev := PackedVector3Array()
	var c2 := goal
	while true:
		rev.append(Vector3(lo.x + c2.x * GRID_M, float(cells[c2]), lo.y + c2.y * GRID_M))
		if c2 == start:
			break
		c2 = prev[c2]
	rev.reverse()
	rev[0] = pts[s]
	rev[rev.size() - 1] = pts[e]
	return rev


## Ground height of grid cell c (ground near the old path's height there, capsule clear), NAN when not passable.
static func _cell_y(q: PhysicsGroundQuery, lo: Vector2, c: Vector2i, seg: PackedVector3Array, reach: float) -> float:
	var x := lo.x + c.x * GRID_M
	var z := lo.y + c.y * GRID_M
	var best := INF
	var y_ref := seg[0].y
	for p in seg:
		var d := Vector2(p.x - x, p.z - z).length()
		if d < best:
			best = d
			y_ref = p.y
	if best > reach:
		return NAN
	var g := q.top_surface(x, z, y_ref + GROUND_UP_M, y_ref - GROUND_DOWN_M, y_ref)
	if not bool(g.ok):
		return NAN
	var feet := Vector3(x, float(g.y), z)
	return feet.y if q.is_clear(feet + Vector3.UP * LIFT_M, PLAN_RADIUS_M, HEIGHT_M) else NAN
