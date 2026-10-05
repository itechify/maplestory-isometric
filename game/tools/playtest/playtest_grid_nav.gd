class_name PlaytestGridNav
extends RefCounted
## Grid paths on the real collision for the places the exported route network does not reach (an NPC on a terrace,
## a drop at the edge of a field): A* over CELL_M cells with the player's own reach, read from its MovementModel:
##   walk   to a neighbouring cell whose ground is within step_up (up or down)
##   jump   up onto ground higher than step_up and at most jump_apex + step_up - JUMP_MARGIN_M (RouteBot jumps there)
##   drop   down onto ground up to MAX_DROP_M lower (walked off)
## Ground is what the PlayerController's feet stand on: the first surface of its floor layers (walkable, blocking,
## scenery) whose normal is within floor_max_angle. That includes the flat top of a blocking prop (a counter, a rock):
## the controller stands there, so a player can too, but such cells cost PROP_COST_M more and are counted ("props"), so
## a path over the ground is preferred and a scenario can flag one that is not. A cell needs the body's capsule clear
## of blocking and containment collision (TraversalPaths' planning capsule), and so does the middle of every walk
## between two cells. Ladders are not known here: the route graph (TraversalNav) carries them, so PlaytestWalker tries
## the routes first.
##
##   var r := PlaytestGridNav.search(world, player.model, from, to)   # {"path", "props", "expansions"}
##   var path := PlaytestGridNav.path(world, player.model, from, to)  # PackedVector3Array, empty when none

const CELL_M := 0.35
## The search stays in the box around both ends grown by this much (m).
const MARGIN_M := 12.0
const MAX_EXPANSIONS := 25000
const MAX_DROP_M := 3.0
## Rises planned as jumps stay this far below the highest ledge the player can land on.
const JUMP_MARGIN_M := 0.2
## Extra cost (m) of a jump, a drop and a cell on a prop's top, so walking on the ground is preferred.
const JUMP_COST_M := 2.0
const DROP_COST_M := 0.5
const PROP_COST_M := 1.5
## The goal is reached within this distance (m, horizontal) and height.
const GOAL_XZ_M := 0.45
const GOAL_DY_M := 0.6
## What the feet stand on (the controller's collision mask without the containment walls).
const FLOOR_MASK := WorldLayers.WALKABLE | WorldLayers.BLOCKING | WorldLayers.SCENERY


## A path from `from` to `to` (both feet positions), or an empty array when the box holds none.
static func path(world: IslandWorld, model: MovementModel, from: Vector3, to: Vector3) -> PackedVector3Array:
	return search(world, model, from, to)["path"]


## {"path" (empty when none), "props" (cells of the path on a prop's top, not walkable ground), "expansions"}.
static func search(world: IslandWorld, model: MovementModel, from: Vector3, to: Vector3) -> Dictionary:
	var none := {"path": PackedVector3Array(), "props": 0, "expansions": 0}
	var q := world.ground_query if world != null else null
	if q == null or q.space == null or model == null:
		return none
	var ctx := {"q": q, "cache": {}, "step": model.step_up,
		"jump": maxf(model.step_up, model.jump_apex + model.step_up - JUMP_MARGIN_M),
		"min_floor_y": cos(model.floor_max_angle) - 0.001}
	var lo := Vector2(minf(from.x, to.x), minf(from.z, to.z)) - Vector2(MARGIN_M, MARGIN_M)
	var hi := Vector2(maxf(from.x, to.x), maxf(from.z, to.z)) + Vector2(MARGIN_M, MARGIN_M)
	var origin := Vector2(from.x, from.z)
	var start := _key(Vector2i.ZERO, from.y)
	var nodes := {start: from}
	var on_prop := {start: false}
	var dist := {start: 0.0}
	var prev := {}
	var heap := _Heap.new()
	heap.push(0.0, start)
	var closed := {}
	var goal := Vector3i.MAX
	var expansions := 0
	while not heap.is_empty() and expansions < MAX_EXPANSIONS:
		var cur: Vector3i = heap.pop()
		if closed.has(cur):
			continue
		closed[cur] = true
		expansions += 1
		var cp: Vector3 = nodes[cur]
		if Vector2(cp.x - to.x, cp.z - to.z).length() <= GOAL_XZ_M and absf(cp.y - to.y) <= GOAL_DY_M:
			goal = cur
			break
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var cell := Vector2i(cur.x + dx, cur.y + dz)
				var x := origin.x + cell.x * CELL_M
				var z := origin.y + cell.y * CELL_M
				if x < lo.x or x > hi.x or z < lo.y or z > hi.y:
					continue
				for n: Dictionary in _moves(ctx, cell, x, z, cp):
					var np: Vector3 = n["at"]
					var nk := _key(cell, np.y)
					if closed.has(nk):
						continue
					var cost := float(dist[cur]) + Vector2(dx, dz).length() * CELL_M + float(n["extra"])
					if cost < float(dist.get(nk, INF)):
						dist[nk] = cost
						prev[nk] = cur
						nodes[nk] = np
						on_prop[nk] = bool(n["prop"])
						heap.push(cost + Vector2(np.x - to.x, np.z - to.z).length() + absf(np.y - to.y) * 0.5, nk)
	if goal == Vector3i.MAX:
		none["expansions"] = expansions
		return none
	var rev := PackedVector3Array([to])
	var props := 0
	var c := goal
	while true:
		rev.append(nodes[c])
		if bool(on_prop.get(c, false)):
			props += 1
		if c == start:
			break
		c = prev[c]
	rev.reverse()
	return {"path": rev, "props": props, "expansions": expansions}


## The cells reachable from `cp` at (x, z): [{"at": feet, "extra": cost, "prop": bool}] for a walk, a jump and a drop.
static func _moves(ctx: Dictionary, cell: Vector2i, x: float, z: float, cp: Vector3) -> Array:
	var q: PhysicsGroundQuery = ctx["q"]
	var step: float = ctx["step"]
	var jump: float = ctx["jump"]
	var out: Array = []
	# Walking or dropping: the first floor below a step above the current height.
	var low := _ground(ctx, cell, x, z, cp.y + step + 0.05, cp.y - MAX_DROP_M)
	if not low.is_empty() and bool(low["clear"]):
		var ly: float = low["y"]
		var feet := Vector3(x, ly, z)
		var prop_cost := 0.0 if bool(low["walkable"]) else PROP_COST_M
		if absf(ly - cp.y) <= step:
			if _clear(q, Vector3((cp.x + x) * 0.5, maxf(cp.y, ly), (cp.z + z) * 0.5)):
				out.append({"at": feet, "extra": prop_cost, "prop": not bool(low["walkable"])})
		else:
			out.append({"at": feet, "extra": DROP_COST_M + prop_cost, "prop": not bool(low["walkable"])})
	# Jumping up: the first floor below the jump reach, when it is higher than a step.
	var high := _ground(ctx, cell, x, z, cp.y + jump, cp.y + step)
	if not high.is_empty() and bool(high["clear"]):
		var hy: float = high["y"]
		if hy - cp.y > step and hy - cp.y <= jump and _clear(q, Vector3(cp.x, hy, cp.z)):
			out.append({"at": Vector3(x, hy, z), "extra": JUMP_COST_M + (0.0 if bool(high["walkable"]) else PROP_COST_M),
				"prop": not bool(high["walkable"])})
	return out


## {"y", "clear", "walkable"} of the first floor between y_top and y_bottom at (x, z), or {} when the first surface
## there is none or too steep to stand on (cached).
static func _ground(ctx: Dictionary, cell: Vector2i, x: float, z: float, y_top: float, y_bottom: float) -> Dictionary:
	var cache: Dictionary = ctx["cache"]
	var key := Vector4i(cell.x, cell.y, roundi(y_top * 20.0), roundi(y_bottom * 20.0))
	if cache.has(key):
		return cache[key]
	var q: PhysicsGroundQuery = ctx["q"]
	var ray := PhysicsRayQueryParameters3D.create(Vector3(x, y_top, z), Vector3(x, y_bottom, z), FLOOR_MASK, q.exclude)
	var hit := q.space.intersect_ray(ray)
	var r := {}
	if not hit.is_empty() and (hit["normal"] as Vector3).y >= float(ctx["min_floor_y"]):
		var y := (hit["position"] as Vector3).y
		var col: Object = hit.get("collider")
		var layer := (col as CollisionObject3D).collision_layer if col is CollisionObject3D else 0
		r = {"y": y, "clear": _clear(q, Vector3(x, y, z)), "walkable": layer & WorldLayers.WALKABLE != 0}
	cache[key] = r
	return r


static func _clear(q: PhysicsGroundQuery, feet: Vector3) -> bool:
	return q.is_clear(feet + Vector3.UP * TraversalPaths.LIFT_M, TraversalPaths.PLAN_RADIUS_M, TraversalPaths.HEIGHT_M)


static func _key(cell: Vector2i, y: float) -> Vector3i:
	return Vector3i(cell.x, cell.y, roundi(y * 4.0))


## A binary min-heap of (priority, key).
class _Heap:
	var _f: PackedFloat64Array = PackedFloat64Array()
	var _k: Array = []

	func is_empty() -> bool:
		return _k.is_empty()

	func push(f: float, k: Variant) -> void:
		_f.append(f)
		_k.append(k)
		var i := _k.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if _f[parent] <= _f[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> Variant:
		var top: Variant = _k[0]
		var last := _k.size() - 1
		_swap(0, last)
		_f.resize(last)
		_k.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < last and _f[l] < _f[m]:
				m = l
			if r < last and _f[r] < _f[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var tf := _f[a]
		_f[a] = _f[b]
		_f[b] = tf
		var tk: Variant = _k[a]
		_k[a] = _k[b]
		_k[b] = tk
