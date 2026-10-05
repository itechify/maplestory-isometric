class_name ReachCheck
extends RefCounted
## The reachability check (brief Phase 6 "avoid unreachable terrain"; docs/runtime/STUCK_SCAN.md): proves on the
## stuck-region scan's walkability graph (StuckScan.MapGraph) that every place the game needs a player to get to on a
## map can be reached on foot from the map's entries:
##   npc     the NPC's talk zone (WorldTuning.talk_zone: a sphere over its feet, the TalkArea) overlaps the player's
##           body capsule (step_up to body_height above the feet, body_radius wide) standing on a node
##   slot    a monster spawn slot: a node at the slot (StuckScan.SNAP_UP_M / SNAP_DOWN_M, one column), else a node on
##           the slot's tier (within the movement model's step_up in height) within STAND_BESIDE_M of it
##   box     a Wooden Box placement (BreakablePlacementPlanner): a node on its tier (the planner's tier_tolerance_m)
##           within its approach_m, where the planner's own standing points are
##   portal  a canonical portal: its press-Up trigger holds the feet (accepts_press), or, for a walked trail, the feet
##           are past the gate into the other map, inside its corridor and band (GateMonitor's arm rule, as
##           StuckScan.exit_reason)
## The entries are where a player appears in the map: its player_spawns and every portal's arrival (spawn_transform),
## arrival gates included. The authored route points the stuck scan also seeds from are not entries here: a route point
## on a ledge nobody can reach would hide the very gap this check is for.
##
## The proof is a path of edges the controller can certainly take. The scan's certain edges (walk, drop, ladder and the
## refined jumps) count as they are. Its into edges (hop, long drop, slide) are generous by design, so an into edge is
## used only once it is certified: a hop or a long drop by its arc (the movement model's gravity, fall-speed cap and walk
## speed), swept with the body capsule and landing on the target column first, inside the controller's landing window
## with StuckScan.MARGIN_M to spare; failing that, by replaying it with the real PlayerController (StuckScan._try_enter:
## walking, creeping, hopping). A slide is never certified. The search is a 0-1 BFS (certain and certified edges cost
## 0, an uncertified into edge 1): it finds the path with the fewest uncertified edges, certifies them, drops those that
## fail and searches again, so a place behind several hops is proven hop by hop.
##
##   var check := ReachCheck.create(StuckScan.create(world, db))     # world: a built IslandWorld (collision only)
##   var r := check.check(check.scan.scan_map("000000040"))           # {map_id, targets, unreachable, ...}
##   var doc := check.run()                                           # every map
##   check.free_all()

const KIND_NPC := "npc"
const KIND_SLOT := "slot"
const KIND_BOX := "box"
const KIND_PORTAL := "portal"
## A slot whose own ground has no node (a low overhang the player's 1.5 m body does not fit under, a monster does) is
## reached by standing beside it: a node on its tier this close (m). The Wooden Box planner's approach distance (1 m,
## breakables.json placement.approach_m) is the same idea; the basic attack reaches further (test_monster_combat hits
## a Snail 1.2 m away).
const STAND_BESIDE_M := 1.0
## Certification rounds per target (a failed into edge is dropped and the search runs again) and the most uncertified
## edges a path may use.
const MAX_ROUNDS := 60
const MAX_LEVELS := 8
## Arc samples of a certified hop or long drop (capsule sweeps between consecutive samples).
const ARC_SAMPLES := 8

var scan: StuckScan = null
var world: IslandWorld = null
var db: ContentDB = null
var tuning: WorldTuning = null
var model: MovementModel = null
## Replay into edges the arc check refuses with the real PlayerController (slow; off for model tests).
var replay: bool = true

## Per map, reset by check(): into edge (from * node count + to) -> true (certified) / false (refused).
var _certified: Dictionary = {}
var _pw: PlayerTestWorld = null
var _n_arcs: int = 0
var _n_replays: int = 0


## A check over `s`'s island (s.world must be built).
static func create(s: StuckScan) -> ReachCheck:
	var c := ReachCheck.new()
	c.scan = s
	c.world = s.world
	c.db = s.db
	c.model = s.model
	c.tuning = s.world.defs.tuning if s.world != null and s.world.defs != null else WorldTuning.from_db(s.db)
	c.replay = s.host != null
	return c


## Frees the replay world (call once done).
func free_all() -> void:
	if _pw != null:
		_pw.free_all()
		_pw = null


# =================================================================================================================
# Targets
# =================================================================================================================

## Every target of the map of `g`: [{kind, id, name, pos (world), local, nodes: PackedInt32Array, rule}]. A target
## with no node at all is unreachable whatever the entries (nothing a body can stand on reaches it).
func targets(g: StuckScan.MapGraph) -> Array[Dictionary]:
	var def := world.defs.get_def(g.map_id)
	var out: Array[Dictionary] = []
	for n in def.npc_definitions:
		var zone := tuning.talk_zone(n.npc_id)
		var feet := n.transform.origin
		out.append(_target(g, KIND_NPC, n.npc_id, n.npc_name, feet,
			npc_nodes(g, feet + Vector3.UP * float(zone.centre_height_m), float(zone.radius_m)),
			"talk zone r %.2f m (%s)" % [float(zone.radius_m), String(zone.profile)]))
	for s in def.monster_spawn_definitions:
		var p := s.position()
		var at := g.node_near(p, StuckScan.SNAP_UP_M, StuckScan.SNAP_DOWN_M, 1)
		var nodes := PackedInt32Array([at]) if at >= 0 else beside_nodes(g, p, STAND_BESIDE_M, model.step_up)
		out.append(_target(g, KIND_SLOT, str(s.index), String(def.mob_names.get(s.mob_id, s.mob_id)), p, nodes,
			"at the slot" if at >= 0 else "beside the slot (%.1f m)" % STAND_BESIDE_M))
	if not BreakableRules.placements_of(def.canonical).is_empty():
		var cfg := BreakablePlacementPlanner.config(db)
		var approach := float(cfg.get("approach_m", STAND_BESIDE_M))
		var tol := float(cfg.get("tier_tolerance_m", model.step_up))
		for b: BreakablePlacement in BreakablePlacementPlanner.plan(def, world.ground_query, tuning, db).placements:
			if not b.is_placed():
				out.append(_target(g, KIND_BOX, b.key(), "Wooden Box", b.position(), PackedInt32Array(), "unplaced"))
				continue
			out.append(_target(g, KIND_BOX, b.key(), "Wooden Box", b.position(), beside_nodes(g, b.position(), approach, tol),
				"within %.1f m on its tier" % approach))
	for p in def.canonical_portals():
		if not p.has_anchor:
			continue
		if p.accepts_press():
			out.append(_target(g, KIND_PORTAL, p.portal_id, "-> " + p.destination_map_id, p.anchor_ground,
				_nodes_where(g, func(q: Vector3) -> bool: return p.trigger_contains(q + Vector3.UP * 0.1)), "press-Up trigger"))
			continue
		var t := world.defs.trail_at_portal(g.map_id, p.portal_id)
		var gate := t.gate_into(t.other_map(g.map_id)) if t != null else null
		if gate == null:
			# A walk-only portal with no way out of this map (the arrival end of a one-way link) is no target.
			continue
		out.append(_target(g, KIND_PORTAL, p.portal_id, "-> " + p.destination_map_id, p.anchor_ground,
			_nodes_where(g, func(q: Vector3) -> bool: return gate.signed_distance(q) > 0.0 and gate.in_box(q)),
			"past the gate of trail %s" % t.link_id))
	return out


func _target(g: StuckScan.MapGraph, kind: String, id: String, label: String, pos: Vector3, nodes: PackedInt32Array,
		rule: String) -> Dictionary:
	return {"kind": kind, "id": id, "name": label, "pos": pos, "local": _r3(g.to_local(pos)), "nodes": nodes,
		"rule": rule}


## Nodes whose body capsule (the controller's: step_up to body_height above the feet, body_radius wide) overlaps the
## sphere of `radius` at `centre` (an NPC's TalkArea).
func npc_nodes(g: StuckScan.MapGraph, centre: Vector3, radius: float) -> PackedInt32Array:
	var lo := model.step_up + model.body_radius
	var hi := maxf(model.body_height - model.body_radius, lo)
	var reach := radius + model.body_radius
	return _nodes_near(g, centre, reach, func(q: Vector3) -> bool:
		var a := q + Vector3.UP * lo
		var b := q + Vector3.UP * hi
		return Geometry3D.get_closest_point_to_segment(centre, a, b).distance_to(centre) <= reach)


## Nodes within `radius` of `p` horizontally and within `dy` of its height (standing beside a slot or a box).
func beside_nodes(g: StuckScan.MapGraph, p: Vector3, radius: float, dy: float) -> PackedInt32Array:
	return _nodes_near(g, p, radius, func(q: Vector3) -> bool:
		return Vector2(q.x - p.x, q.z - p.z).length() <= radius and absf(q.y - p.y) <= dy)


func _nodes_near(g: StuckScan.MapGraph, p: Vector3, radius: float, keep: Callable) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r := int(ceil(radius / g.cell)) + 1
	var c0 := g.column_at(p.x, p.z)
	var ix0 := int(floor((p.x - g.origin.x) / g.cell + 0.5))
	var iz0 := int(floor((p.z - g.origin.y) / g.cell + 0.5))
	if c0 < 0 and (ix0 < -r or iz0 < -r or ix0 >= g.nx + r or iz0 >= g.nz + r):
		return out
	for ix in range(ix0 - r, ix0 + r + 1):
		for iz in range(iz0 - r, iz0 + r + 1):
			if ix < 0 or iz < 0 or ix >= g.nx or iz >= g.nz:
				continue
			var c := ix * g.nz + iz
			var first := g.col_first[c]
			if first < 0:
				continue
			for k in g.col_count[c]:
				var n := g.surf_node[first + k]
				if n >= 0 and bool(keep.call(g.node_pos[n])):
					out.append(n)
	return out


func _nodes_where(g: StuckScan.MapGraph, keep: Callable) -> PackedInt32Array:
	var out := PackedInt32Array()
	for n in g.node_count():
		if bool(keep.call(g.node_pos[n])):
			out.append(n)
	return out


## The entry nodes of `g`: its map's player_spawns and portal arrivals, snapped as the stuck scan snaps entries.
func entries(g: StuckScan.MapGraph) -> PackedInt32Array:
	var def := world.defs.get_def(g.map_id)
	var pts := PackedVector3Array()
	for xf in def.player_spawns:
		pts.append(xf.origin)
	for p in def.portals:
		pts.append(p.spawn_transform.origin)
	var out := PackedInt32Array()
	for q in pts:
		var n := g.node_near(q, StuckScan.SNAP_UP_M, StuckScan.SNAP_DOWN_M, 2)
		if n >= 0 and not (n in out):
			out.append(n)
	return out


# =================================================================================================================
# The proof
# =================================================================================================================

## Checks every target of `g` (a scanned StuckScan.MapGraph; verification is not needed). Returns {map_id, name,
## entries, targets: [{kind, id, name, local, rule, ok, nodes, into_edges (certified edges on the path), why}],
## unreachable: [the failed targets], certified, refused, arcs, replays, ms}.
func check(g: StuckScan.MapGraph) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	_certified = {}
	_n_arcs = 0
	_n_replays = 0
	var starts := entries(g)
	var reach := _closure(g, starts)
	var rows: Array = []
	var bad: Array = []
	for t: Dictionary in targets(g):
		var r := _prove(g, starts, reach, t.nodes, String(t.rule))
		var row := {"kind": t.kind, "id": t.id, "name": t.name, "local": t.local, "rule": t.rule, "ok": bool(r.ok),
			"nodes": (t.nodes as PackedInt32Array).size(), "into_edges": int(r.get("into_edges", 0)), "why": String(r.get("why", ""))}
		rows.append(row)
		if not bool(r.ok):
			bad.append(row)
	var refused := 0
	var certified := 0
	for k in _certified:
		if bool(_certified[k]):
			certified += 1
		else:
			refused += 1
	return {"map_id": g.map_id, "name": g.name, "entries": starts.size(), "targets": rows, "unreachable": bad,
		"certified": certified, "refused": refused, "arcs": _n_arcs, "replays": _n_replays, "ms": Time.get_ticks_msec() - t0}


## Scans and checks every map (or `maps`): {totals, maps: {id: check()}, unreachable: [rows with map_id]}.
func run(maps: PackedStringArray = PackedStringArray()) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var ids := maps if not maps.is_empty() else world.defs.ids()
	var per_map := {}
	var bad: Array = []
	var totals := {"maps": 0, "targets": 0, "unreachable": 0, "certified_edges": 0, "replays": 0}
	for id in ids:
		if not world.defs.has_map(id):
			continue
		var r := check(scan.scan_map(id))
		per_map[id] = r
		totals.maps += 1
		totals.targets += (r.targets as Array).size()
		totals.unreachable += (r.unreachable as Array).size()
		totals.certified_edges += int(r.certified)
		totals.replays += int(r.replays)
		for row: Dictionary in r.unreachable:
			var e := row.duplicate()
			e["map_id"] = id
			bad.append(e)
	totals["ms"] = Time.get_ticks_msec() - t0
	free_all()
	return {"totals": totals, "maps": per_map, "unreachable": bad}


## Proves that a node of `goal` can be reached from the nodes `starts` of `g` (a scanned graph): {ok, into_edges (the
## certified into edges the proof needed), why}. The low-level entry point (hand-made graphs in tests); check() calls it
## for every target.
func prove(g: StuckScan.MapGraph, starts: PackedInt32Array, goal: PackedInt32Array) -> Dictionary:
	_certified = {}
	return _prove(g, starts, _closure(g, starts), goal, "")


## `reach` (the certain closure of the entries, grown as edges are certified) holds a node of `goal`, or a path of
## certified into edges leads there. {ok, into_edges, why}.
func _prove(g: StuckScan.MapGraph, starts: PackedInt32Array, reach: PackedByteArray, goal: PackedInt32Array,
		rule: String) -> Dictionary:
	if goal.is_empty():
		return {"ok": false, "why": "no place a body can stand meets it (%s)" % rule}
	if starts.is_empty():
		return {"ok": false, "why": "the map has no entry on the graph"}
	for n in goal:
		if reach[n] == 1:
			return {"ok": true, "into_edges": 0}
	var goal_set := PackedByteArray()
	goal_set.resize(g.node_count())
	goal_set.fill(0)
	for n in goal:
		goal_set[n] = 1
	var used := 0
	for round in MAX_ROUNDS:
		var path := _search(g, reach, goal_set)
		if path.is_empty():
			return {"ok": false, "into_edges": used,
				"why": "no path even over the scan's generous edges" if round == 0 else "every way in needs an edge that failed certification"}
		var all_ok := true
		for e: Vector3i in path:
			if not _certify(g, e.x, e.y, e.z):
				all_ok = false
		if all_ok:
			# The path is certain now: grow the closure from its last node (every edge on it is certain or certified).
			for e: Vector3i in path:
				used += 1
				_grow(g, reach, e.y)
			for n in goal:
				if reach[n] == 1:
					return {"ok": true, "into_edges": used}
	return {"ok": false, "into_edges": used, "why": "not proven in %d certification rounds" % MAX_ROUNDS}


## The certain closure (certain edges, refined jumps and certified into edges) of `starts`.
func _closure(g: StuckScan.MapGraph, starts: PackedInt32Array) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(g.node_count())
	seen.fill(0)
	for s in starts:
		_grow(g, seen, s)
	return seen


## Marks `from` and everything certainly reachable from it in `seen`.
func _grow(g: StuckScan.MapGraph, seen: PackedByteArray, from: int) -> void:
	if seen[from] == 1:
		return
	seen[from] = 1
	var queue := PackedInt32Array([from])
	var head := 0
	var count := g.node_count()
	while head < queue.size():
		var u := queue[head]
		head += 1
		for k in range(g.e_off[u], g.e_off[u + 1]):
			var v := g.e_dst[k]
			if seen[v] == 0:
				seen[v] = 1
				queue.append(v)
		for v: int in g.extra.get(u, PackedInt32Array()):
			if seen[v] == 0:
				seen[v] = 1
				queue.append(v)
		for k in range(g.i_off[u], g.i_off[u + 1]):
			var v := g.i_dst[k]
			if seen[v] == 0 and bool(_certified.get(u * count + v, false)):
				seen[v] = 1
				queue.append(v)


## 0-1 BFS from the closure `reach` (distance 0) to a node of `goal_set`: certain and certified edges cost 0, an
## uncertified into edge (not refused, not a slide) 1. Returns the uncertified edges on the best path as
## [Vector3i(from, to, kind)] in path order; [] when no node of the goal is reachable within MAX_LEVELS.
func _search(g: StuckScan.MapGraph, reach: PackedByteArray, goal_set: PackedByteArray) -> Array[Vector3i]:
	var count := g.node_count()
	var level := PackedInt32Array()
	level.resize(count)
	level.fill(-1)
	var parent := PackedInt32Array()
	parent.resize(count)
	parent.fill(-1)
	var pkind := PackedByteArray()
	pkind.resize(count)
	pkind.fill(255)
	var current := PackedInt32Array()
	for n in count:
		if reach[n] == 1:
			level[n] = 0
			current.append(n)
	var found := -1
	for lv in MAX_LEVELS + 1:
		var nxt := PackedInt32Array()
		var head := 0
		while head < current.size() and found < 0:
			var u := current[head]
			head += 1
			if goal_set[u] == 1:
				found = u
				break
			for k in range(g.e_off[u], g.e_off[u + 1]):
				_relax0(g.e_dst[k], u, lv, level, parent, pkind, current)
			for v: int in g.extra.get(u, PackedInt32Array()):
				_relax0(v, u, lv, level, parent, pkind, current)
			for k in range(g.i_off[u], g.i_off[u + 1]):
				var v := g.i_dst[k]
				var key := u * count + v
				if _certified.has(key):
					if bool(_certified[key]):
						_relax0(v, u, lv, level, parent, pkind, current)
					continue
				if g.i_kind[k] == StuckScan.Edge.SLIDE or level[v] >= 0:
					continue
				level[v] = lv + 1
				parent[v] = u
				pkind[v] = g.i_kind[k]
				nxt.append(v)
		if found >= 0 or nxt.is_empty():
			break
		current = nxt
	if found < 0:
		return []
	var path: Array[Vector3i] = []
	var v := found
	while level[v] > 0:
		var u := parent[v]
		if pkind[v] != 255 and level[v] == level[u] + 1:
			path.push_front(Vector3i(u, v, pkind[v]))
		v = u
	return path


func _relax0(v: int, u: int, lv: int, level: PackedInt32Array, parent: PackedInt32Array, pkind: PackedByteArray,
		current: PackedInt32Array) -> void:
	if level[v] >= 0 and level[v] <= lv:
		return
	level[v] = lv
	parent[v] = u
	pkind[v] = 255
	current.append(v)


## Certifies into edge from -> to of `kind` (cached per map): the arc check, else a replay with the real controller.
func _certify(g: StuckScan.MapGraph, from: int, to: int, kind: int) -> bool:
	var key := from * g.node_count() + to
	if _certified.has(key):
		return bool(_certified[key])
	var ok := false
	if kind == StuckScan.Edge.HOP or kind == StuckScan.Edge.LONG_DROP:
		ok = arc_lands(g, g.node_pos[from], g.node_pos[to], model.jump_velocity if kind == StuckScan.Edge.HOP else 0.0)
		if not ok and replay:
			ok = _replay(g, from, to, kind)
	_certified[key] = ok
	return ok


## A body leaving feet `pa` with upward speed `v0` (the jump velocity for a hop, 0 for walking off a ledge) and a
## steady horizontal speed no faster than the walk speed lands on `pb`: the controller lands only while descending, on
## a surface its feet come down to or one up to step_up above them (StuckScan.MARGIN_M less here). The feet must be
## over pb inside that window (the earliest such time: the slowest horizontal speed that makes it), the capsule must
## sweep clear along the arc (gravity, then the max_fall_speed cap), and the feet must not come down on another floor
## surface first. The certain counterpart of the scan's hop and long-drop into edges.
func arc_lands(g: StuckScan.MapGraph, pa: Vector3, pb: Vector3, v0: float) -> bool:
	_n_arcs += 1
	var dist := Vector2(pb.x - pa.x, pb.z - pa.z).length()
	if dist < g.cell * 0.5:
		return false
	var dy := pb.y - pa.y
	var apex := v0 * v0 / (2.0 * model.gravity)
	var low := dy - (model.step_up - StuckScan.MARGIN_M)
	if low > apex:
		return false
	var t_apex := v0 / model.gravity
	var t_max := _time_to_height(v0, low)
	var t_open := t_apex if dy >= apex else _time_to_height(v0, dy)
	var t_land := maxf(t_open, dist / model.walk_speed)
	if t_land > t_max:
		return false
	var vh := dist / t_land
	var dir := Vector3(pb.x - pa.x, 0.0, pb.z - pa.z) / dist
	var prev := pa
	for k in range(1, ARC_SAMPLES + 1):
		var t := t_land * k / ARC_SAMPLES
		var p := pa + dir * (vh * t)
		p.y = pa.y + _height_at(v0, t)
		if k == ARC_SAMPLES:
			p.y = maxf(p.y, pb.y)
		if not scan._sweep(prev, p):
			return false
		if t > t_apex and k < ARC_SAMPLES:
			var col := g.column_at(p.x, p.z)
			if col >= 0:
				var s := scan._first_at_or_below(g, col, p.y + model.step_up + StuckScan.RAY_HEADROOM_M)
				if s >= 0 and g.surf_y[s] >= p.y - 0.01 and g.surf_floor[s] == 1 and absf(g.surf_y[s] - pb.y) > 0.1:
					return false
		prev = p
	return true


## Height of the feet over the take-off `t` seconds after leaving with upward speed v0 (gravity, the fall-speed cap).
func _height_at(v0: float, t: float) -> float:
	var grav := model.gravity
	var vmax := model.max_fall_speed
	var t_cap := (v0 + vmax) / grav if vmax > 0.0 else INF
	if t <= t_cap:
		return v0 * t - 0.5 * grav * t * t
	var y_cap := v0 * t_cap - 0.5 * grav * t_cap * t_cap
	return y_cap - vmax * (t - t_cap)


## The time the descending feet reach height `h` over the take-off (h <= the apex).
func _time_to_height(v0: float, h: float) -> float:
	var grav := model.gravity
	var vmax := model.max_fall_speed
	var t := (v0 + sqrt(maxf(v0 * v0 - 2.0 * grav * h, 0.0))) / grav
	var t_cap := (v0 + vmax) / grav if vmax > 0.0 else INF
	if t <= t_cap:
		return t
	var y_cap := v0 * t_cap - 0.5 * grav * t_cap * t_cap
	return t_cap + (y_cap - h) / vmax


## Replays into edge from -> to with the real PlayerController on the island (walking, creeping, hopping): certified
## when it stands on `to` or on a node with a certain edge into it.
func _replay(g: StuckScan.MapGraph, from: int, to: int, kind: int) -> bool:
	_n_replays += 1
	if _pw == null:
		_pw = PlayerTestWorld.create(db, scan.host)
		var p := _pw.spawn_player(g.node_pos[from] + Vector3.UP * 0.05)
		p.collision_mask = WorldLayers.PLAYER_MASK
	_pw.player.set_climbables(g.climbables.duplicate())
	_pw.player.kill_y = g.kill_y
	var land := {to: true}
	for k in range(g.r_off[to], g.r_off[to + 1]):
		var w := g.r_src[k]
		if g.node_pos[w].distance_to(g.node_pos[to]) <= g.cell * 1.5 + 0.01:
			land[w] = true
	return scan._try_enter(g, _pw, from, to, StuckScan.EDGE_NAMES[kind], land) != ""


static func _r3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
