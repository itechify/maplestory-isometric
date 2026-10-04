class_name TraversalNav
extends RefCounted
## In-map paths for the traversal bot's tour legs (MAP_ARCHITECTURE.md section 4.13 L3): a graph over one map's
## exported route polylines (sidecar routes[], validated walkable both ways by the L2 route sweep, one_way routes in
## their direction only), joined where routes meet, searched with Dijkstra.
##
##   var nav := TraversalNav.build(def)
##   var path := nav.path(from_world_pos, to_world_pos)   # PackedVector3Array; empty when no route connects them
##
## Graph:
##   nodes     every route point;
##   edges     consecutive points of a route (one_way routes forward only);
##   junctions points of different routes (or far-apart points of one route) within JUNCTION_XZ_M horizontally and
##             JUNCTION_DY_M vertically, both ways (Iteration One's routes start and end on each other and on portal
##             anchors);
##   ends      the start and goal attach to route points within ATTACH_XZ_M (nearest first) by a straight stretch,
##             which the 4.5 m architecture-free corridor at every portal keeps clear.
## The bot walks the result with RouteBot (pure pursuit, jumps at rises, ladders on climb segments).

## Route points of different routes this close (m, horizontally) and level (m) are one place.
const JUNCTION_XZ_M := 1.0
const JUNCTION_DY_M := 0.5
## How far (m) a start or goal may be from the route graph, and the height window of that attachment.
const ATTACH_XZ_M := 6.0
const ATTACH_DY_M := 1.2
## A straight attachment longer than this is penalised (prefer the route network to cutting across).
const ATTACH_PENALTY := 3.0

var map_id: String = ""
var points: PackedVector3Array = PackedVector3Array()
## node index -> Array of [neighbour index, cost]
var adj: Array = []
var _grid: Dictionary = {}


static func build(def: MapDefinition) -> TraversalNav:
	var nav := TraversalNav.new()
	nav.map_id = def.map_id
	var route_of := PackedInt32Array()
	var index_in := PackedInt32Array()
	var r := 0
	for route in def.sidecar.get("routes", []):
		if not (route is Dictionary):
			continue
		var first := nav.points.size()
		var k := 0
		for pt in route.get("points", []):
			if pt is Array and (pt as Array).size() >= 3:
				nav.points.append(Vector3(float(pt[0]), float(pt[1]), float(pt[2])))
				nav.adj.append([])
				route_of.append(r)
				index_in.append(k)
				k += 1
		var one_way := bool(route.get("one_way", false))
		for i in range(first + 1, nav.points.size()):
			var c := nav.points[i - 1].distance_to(nav.points[i])
			(nav.adj[i - 1] as Array).append([i, c])
			if not one_way:
				(nav.adj[i] as Array).append([i - 1, c])
		r += 1
	for i in nav.points.size():
		nav._grid_add(i)
	for i in nav.points.size():
		for j in nav._near(nav.points[i], JUNCTION_XZ_M):
			if j <= i:
				continue
			if route_of[i] == route_of[j] and absi(index_in[i] - index_in[j]) <= 3:
				continue
			var a := nav.points[i]
			var b := nav.points[j]
			if absf(a.y - b.y) > JUNCTION_DY_M:
				continue
			var c := a.distance_to(b)
			(nav.adj[i] as Array).append([j, c])
			(nav.adj[j] as Array).append([i, c])
	return nav


## A walkable path from `from` to `to` over the route network (both ends attached by straight stretches), or an
## empty array when none connects them. A pair within ATTACH_XZ_M and level gets the straight line.
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var direct := Vector2(from.x - to.x, from.z - to.z).length()
	if direct <= ATTACH_XZ_M and absf(from.y - to.y) <= ATTACH_DY_M:
		return PackedVector3Array([from, to])
	var starts := _attach(from)
	var goals := _attach(to)
	if starts.is_empty() or goals.is_empty():
		return PackedVector3Array()
	var n := points.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	var open: Array = []
	for s in starts:
		var c := from.distance_to(points[int(s)]) * ATTACH_PENALTY
		if c < dist[int(s)]:
			dist[int(s)] = c
			open.append(int(s))
	var goal_cost := {}
	for g in goals:
		goal_cost[int(g)] = to.distance_to(points[int(g)]) * ATTACH_PENALTY
	var best_goal := -1
	var best_total := INF
	while not open.is_empty():
		var bi := 0
		for k in range(1, open.size()):
			if dist[int(open[k])] < dist[int(open[bi])]:
				bi = k
		var u: int = open[bi]
		open.remove_at(bi)
		if done[u] == 1:
			continue
		done[u] = 1
		if dist[u] >= best_total:
			break
		if goal_cost.has(u):
			var total := dist[u] + float(goal_cost[u])
			if total < best_total:
				best_total = total
				best_goal = u
		for e in (adj[u] as Array):
			var v: int = e[0]
			var nd := dist[u] + float(e[1])
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
				open.append(v)
	if best_goal < 0:
		return PackedVector3Array()
	var rev := PackedVector3Array([to])
	var cur := best_goal
	while cur >= 0:
		rev.append(points[cur])
		cur = prev[cur]
	rev.append(from)
	rev.reverse()
	return rev


## Route points a position can reach by a straight stretch (within ATTACH_XZ_M and ATTACH_DY_M), nearest first.
func _attach(p: Vector3) -> PackedInt32Array:
	var cand: Array = []
	for i in _near(p, ATTACH_XZ_M):
		if absf(points[i].y - p.y) <= ATTACH_DY_M:
			cand.append([Vector2(points[i].x - p.x, points[i].z - p.z).length(), i])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out := PackedInt32Array()
	for c in cand.slice(0, 6):
		out.append(int(c[1]))
	return out


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.z))


func _grid_add(i: int) -> void:
	var c := _cell(points[i])
	if not _grid.has(c):
		_grid[c] = PackedInt32Array()
	var bucket: PackedInt32Array = _grid[c]
	bucket.append(i)
	_grid[c] = bucket


## Indices of the points within r (XZ) of p.
func _near(p: Vector3, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c := _cell(p)
	var span := int(ceil(r))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := Vector2i(c.x + dx, c.y + dz)
			if not _grid.has(key):
				continue
			for i in (_grid[key] as PackedInt32Array):
				if Vector2(points[i].x - p.x, points[i].z - p.z).length() <= r:
					out.append(i)
	return out
