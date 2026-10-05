class_name StuckScan
extends RefCounted
## The stuck-region scanner (docs/runtime/STUCK_SCAN.md; MAP_ARCHITECTURE.md section 4.13, L1 "flood-fill coverage"):
## finds the walkable places a player can get into but not out of.
##
## Per map it samples every surface the feet can stand on, on a world-aligned grid over the map's region and the
## zones of its trails, and builds a directed walkability graph with the PlayerController's own limits
## (MovementModel: step_up, snap_down, floor angle, body capsule, jump arc, walk speed, ladder grab radii). Forward
## reachability runs from the entries (player spawns, every portal's arrival, the authored route points); backward
## reachability runs from the exits (the press-Up triggers of the canonical portals, and the regions of the other
## maps, reached through a trail). A node that is reachable but cannot get back to an exit is flagged; flagged nodes
## are grouped into components.
##
## Edges come in two kinds, because the two searches need opposite errors:
##   certain   used by both searches: walking within step_up/snap_down, walking off an edge onto the first surface
##             below (swept), ladders and ropes along their whole grab band, and (for flagged nodes only, see
##             _refine) jumps along a swept arc with a reach below the controller's (MARGIN_M). An escape the graph
##             claims must be real, since nothing re-checks it.
##   into      forward only: longer drops (momentum carries the body further) and unswept hops. Being generous here
##             only flags more; verify() clears what the controller cannot get into.
## verify() then drops the game's real PlayerController (PlayerTestWorld, real physics, synchronous ticks) onto every
## flagged component and tries to leave with scripted input (toward the nearest escapable nodes, then in 16
## directions, walking and hopping, with Up held for ladders). A component it gets out of is CLEARED, one it cannot is
## CONFIRMED, and one the controller could not get into from its in-edges is UNENTERABLE.
##
##   var scan := StuckScan.create(world, db)       # world: a built IslandWorld (collision only is enough)
##   var g := scan.scan_map("000000041")           # a StuckScan.MapGraph
##   scan.verify(g)                                # labels g.components
##   var doc := scan.run(PackedStringArray())      # every map, verified: the docs/runtime/stuck_report.json document
##
## Every number of the body comes from the MovementModel (data/canonical/formulas/movement.json via WorldScale, and
## data/misostory/movement.json); the constants below are the scanner's own sampling choices.

const VERDICT_CONFIRMED := "CONFIRMED"
const VERDICT_CLEARED := "CLEARED"
const VERDICT_UNENTERABLE := "UNENTERABLE"

## Default grid spacing (m): the column pitch of the surface samples.
const DEFAULT_CELL_M := 0.35
## At most this many stacked surfaces are recorded per column (top down).
const MAX_SURFACES := 8
## The next ray of a column starts this far below the surface just found.
const SURFACE_GAP_M := 0.01
## The controller's feet rays start this far above the step band (PlayerController.RAY_HEADROOM).
const RAY_HEADROOM_M := 0.05
## Certain jumps reach this much less high than the controller can (jump_apex + step_up): a jump the graph counts as
## an escape must not depend on a perfect take-off.
const MARGIN_M := 0.2
## Certain jumps down are considered only to targets at most this far below the take-off (lower ones are drops).
const MAX_JUMP_DOWN_M := 1.5
## Arc samples of a certain jump (capsule sweeps between consecutive samples).
const ARC_SAMPLES := 6
## Unswept hops (into edges) reach this many cells away.
const HOP_CELLS := 3
## Longer drops (into edges) reach at most this many cells away.
const DROP_CELLS := 5
## A sample point (entry, verification probe) snaps to a node within this height above / below it.
const SNAP_UP_M := 0.6
const SNAP_DOWN_M := 0.6

## Edge kinds (MapGraph.e_kind / i_kind).
enum Edge { WALK, DROP, LADDER, JUMP, LONG_DROP, HOP, SLIDE }
const EDGE_NAMES := ["walk", "drop", "ladder", "jump", "long drop", "hop", "slide"]

## Verification: ticks per try, the number of nearest escapable targets tried, the directions of the fallback sweep,
## the samples per component and the try budget per component.
const TRY_TICKS := 180
const SWEEP_TICKS := 120
const TARGETS := 4
const SWEEP_DIRECTIONS := 16
const SAMPLES := 3
const MAX_TRIES := 120
const ENTER_TICKS := 120
## In-edges replayed per component (the report lists the first 3).
const IN_EDGES := 8
## How far (xz) from the start a try may end before its end point becomes a new start (depth search).
const RESTART_M := 1.0
const MAX_STARTS := 3

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


## One map's walkability graph and its result.
class MapGraph:
	extends RefCounted
	# --- what is scanned: StuckScan.map_graph() fills it from the island; a test may fill it by hand --------------
	var map_id: String = ""
	var name: String = ""
	## Map-local -> world (MapDefinition.frame); identity for a hand-made graph.
	var frame: Transform3D = Transform3D.IDENTITY
	## Region polygons sampled (world XZ): the map's footprint, then the zones of its trails.
	var polygons: Array[PackedVector2Array] = []
	## Fall recovery height: a walk-off with nothing above it below is a fall-out, and no node lies below it.
	var kill_y: float = -INF
	## Where players appear (feet): player spawns, portal arrivals, the authored route points.
	var entry_points: PackedVector3Array = PackedVector3Array()
	## Ladders, ropes and vines (the map's sidecar climbables).
	var climbables: Array[ClimbableDef] = []
	## The canonical portals that accept a press (exits), and the gates of this map's trails into the other maps (a
	## node past such a gate plane, inside its corridor and height band, has crossed into the other map's region).
	var exit_portals: Array[PortalDef] = []
	var exit_gates: Array[GateDef] = []
	## Plain exit boxes (feet inside one have left): hand-made graphs.
	var exit_boxes: Array[AABB] = []
	# --- the graph ------------------------------------------------------------------------------------------------
	var cell: float = DEFAULT_CELL_M
	## World XZ of the centre of cell (0, 0); column c = ix * nz + iz.
	var origin: Vector2 = Vector2.ZERO
	var nx: int = 0
	var nz: int = 0
	var y_top: float = 0.0
	var y_bottom: float = 0.0
	## Per column: index of its first surface (-1: not sampled) and the number of surfaces (top down).
	var col_first: PackedInt32Array = PackedInt32Array()
	var col_count: PackedByteArray = PackedByteArray()
	## Surfaces: height, node id (-1 when the feet cannot stand there: too steep, the body blocked, buried in a solid,
	## below kill_y) and whether the surface is floor by angle.
	var surf_y: PackedFloat32Array = PackedFloat32Array()
	var surf_node: PackedInt32Array = PackedInt32Array()
	var surf_floor: PackedByteArray = PackedByteArray()
	## Nodes (standable surfaces): feet position and column.
	var node_pos: PackedVector3Array = PackedVector3Array()
	var node_col: PackedInt32Array = PackedInt32Array()
	## Certain edges (CSR: node i's targets are e_dst[e_off[i] .. e_off[i + 1])) and into edges (i_*), with kinds.
	var e_off: PackedInt32Array = PackedInt32Array()
	var e_dst: PackedInt32Array = PackedInt32Array()
	var e_kind: PackedByteArray = PackedByteArray()
	var i_off: PackedInt32Array = PackedInt32Array()
	var i_dst: PackedInt32Array = PackedInt32Array()
	var i_kind: PackedByteArray = PackedByteArray()
	## Reverse of the certain edges (CSR).
	var r_off: PackedInt32Array = PackedInt32Array()
	var r_src: PackedInt32Array = PackedInt32Array()
	## Certain jump edges found for flagged nodes (_refine): node -> PackedInt32Array, and their reverse.
	var extra: Dictionary = {}
	var extra_rev: Dictionary = {}
	## Ladder/rope edges, collected before the CSR pass: node -> PackedInt32Array.
	var ladder_out: Dictionary = {}
	var entries: PackedInt32Array = PackedInt32Array()
	var exits: PackedInt32Array = PackedInt32Array()
	## 1 = forward reachable from an entry / backward reachable from an exit (an escapable node).
	var fwd: PackedByteArray = PackedByteArray()
	var bwd: PackedByteArray = PackedByteArray()
	## Flagged components (see StuckScan._component_summary), verified or not.
	var components: Array[Dictionary] = []
	## Fall-outs: walking off an edge with no surface above kill_y below (FallRecovery's case, never a trap).
	var fall_outs: int = 0
	var fall_out_samples: PackedVector3Array = PackedVector3Array()
	var stats: Dictionary = {}

	func node_count() -> int:
		return node_pos.size()

	func to_local(p: Vector3) -> Vector3:
		return frame.affine_inverse() * p

	func to_world(local: Vector3) -> Vector3:
		return frame * local

	## The x index of column c (its z index is c % nz).
	@warning_ignore("integer_division")
	func col_ix(c: int) -> int:
		return c / nz

	## Column index of the world point (-1 outside the grid).
	func column_at(x: float, z: float) -> int:
		var ix := int(floor((x - origin.x) / cell + 0.5))
		var iz := int(floor((z - origin.y) / cell + 0.5))
		if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
			return -1
		return ix * nz + iz

	## The node standing nearest to `p` in height in p's column (feet within `up` above / `down` below p), else in the
	## columns around it within `radius_cells`; -1 if none.
	func node_near(p: Vector3, up: float = SNAP_UP_M, down: float = SNAP_DOWN_M, radius_cells: int = 1) -> int:
		var c0 := column_at(p.x, p.z)
		if c0 < 0:
			return -1
		var best := -1
		var best_d := INF
		var ix0 := col_ix(c0)
		var iz0 := c0 % nz
		for r in radius_cells + 1:
			for dx in range(-r, r + 1):
				for dz in range(-r, r + 1):
					if maxi(absi(dx), absi(dz)) != r:
						continue
					var ix := ix0 + dx
					var iz := iz0 + dz
					if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
						continue
					var c := ix * nz + iz
					var first := col_first[c]
					if first < 0:
						continue
					for k in col_count[c]:
						var n := surf_node[first + k]
						if n < 0:
							continue
						var q := node_pos[n]
						if q.y > p.y + up or q.y < p.y - down:
							continue
						var d := Vector2(q.x - p.x, q.z - p.z).length() + absf(q.y - p.y) * 0.5
						if d < best_d:
							best_d = d
							best = n
			if best >= 0:
				return best
		return best

	## True when `p` (feet) stands on a node that can get back to an exit.
	func escapable_at(p: Vector3, up: float = 0.3, down: float = 0.3) -> bool:
		var n := node_near(p, up, down, 1)
		return n >= 0 and bwd[n] == 1

	## Every out-edge of node a (certain, into and refined jumps): [[target, kind], ...].
	func out_edges(a: int) -> Array:
		var out: Array = []
		for k in range(e_off[a], e_off[a + 1]):
			out.append([e_dst[k], e_kind[k]])
		for k in range(i_off[a], i_off[a + 1]):
			out.append([i_dst[k], i_kind[k]])
		for t in extra.get(a, PackedInt32Array()):
			out.append([t, Edge.JUMP])
		return out


var world: IslandWorld = null
var db: ContentDB = null
var model: MovementModel = null
var cell: float = DEFAULT_CELL_M
var space: PhysicsDirectSpaceState3D = null
## Bodies the queries ignore (the in-game player when scanning inside main.tscn).
var exclude: Array[RID] = []
## Node the verification's PlayerTestWorld is hosted under (same World3D as the island); the world's parent by default.
var host: Node = null
## The reviewed dead ends (game/data/misostory/stuck_allowlist.json entries).
var allowlist: Array = []

var _ray: PhysicsRayQueryParameters3D = null
var _up_ray: PhysicsRayQueryParameters3D = null
var _shape_q: PhysicsShapeQueryParameters3D = null
var _cap_lift: float = 0.0
var _n_rays: int = 0
var _n_shapes: int = 0
var _n_sweeps: int = 0


## A scanner over `w`'s physics space (the island must be built). `options`: cell (m), exclude (Array[RID]), host.
static func create(w: IslandWorld, content: ContentDB, options: Dictionary = {}) -> StuckScan:
	return create_in(w, content, options, w)


## A scanner over the physics space of `node` (any Node3D in the tree), for hand-made graphs (scan(), verify());
## map_graph(), scan_map() and run() also need `island`.
static func create_in(node: Node3D, content: ContentDB, options: Dictionary = {}, island: IslandWorld = null) -> StuckScan:
	var s := StuckScan.new()
	var w := node
	s.world = island
	s.db = content
	s.model = MovementModel.from_db(content)
	s.cell = float(options.get("cell", DEFAULT_CELL_M))
	var ex: Variant = options.get("exclude", [])
	for r in (ex as Array):
		s.exclude.append(r as RID)
	s.host = options.get("host", w.get_parent()) as Node
	s.space = w.get_world_3d().direct_space_state
	var table: Variant = content.miso_table("stuck_allowlist")
	if table is Dictionary:
		s.allowlist = (table as Dictionary).get("entries", [])
	s._setup_queries()
	return s


## The movement numbers the scan uses (also written into the report).
func params() -> Dictionary:
	return {"cell_m": cell, "step_up_m": model.step_up, "snap_down_m": model.snap_down,
		"floor_max_angle_deg": rad_to_deg(model.floor_max_angle), "body_radius_m": model.body_radius,
		"body_height_m": model.body_height, "walk_speed_mps": model.walk_speed, "gravity_mps2": model.gravity,
		"jump_apex_m": model.jump_apex, "jump_velocity_mps": model.jump_velocity,
		"certain_jump_reach_m": _jump_reach(), "margin_m": MARGIN_M, "climb_grab_radius_m": model.climb_grab_radius,
		"climb_top_grab_radius_m": model.climb_top_grab_radius, "max_jump_down_m": MAX_JUMP_DOWN_M}


## Highest ledge a certain jump lands on, above the take-off (jump apex + step_up - MARGIN_M).
func _jump_reach() -> float:
	return model.jump_apex + model.step_up - MARGIN_M


func _setup_queries() -> void:
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = WorldLayers.PLAYER_MASK
	_ray.hit_back_faces = false
	_ray.hit_from_inside = false
	_ray.exclude = exclude
	_up_ray = PhysicsRayQueryParameters3D.new()
	_up_ray.collision_mask = WorldLayers.PLAYER_MASK
	_up_ray.hit_back_faces = false
	_up_ray.hit_from_inside = false
	_up_ray.exclude = exclude
	# The controller's body: a capsule from step_up to body_height (PlayerController._configure_shapes).
	var cap := CapsuleShape3D.new()
	cap.radius = model.body_radius
	cap.height = maxf(model.body_height - model.step_up, model.body_radius * 2.0)
	_cap_lift = model.body_height - cap.height * 0.5
	_shape_q = PhysicsShapeQueryParameters3D.new()
	_shape_q.shape = cap
	_shape_q.collision_mask = WorldLayers.PLAYER_MASK
	_shape_q.exclude = exclude


# =================================================================================================================
# Scanning
# =================================================================================================================

## The graph of one map of the island, ready to scan(): its footprint and the zones of its trails, kill_y, entries
## (player spawns, every portal's arrival, the authored route points), exits (press-Up portals, the far gates of its
## trails) and climbables. Needs the island built (world.defs grounded).
func map_graph(map_id: String) -> MapGraph:
	var def := world.defs.get_def(map_id)
	var g := MapGraph.new()
	g.map_id = map_id
	g.name = def.map_name
	g.frame = def.frame
	g.kill_y = def.kill_y
	g.polygons.append(def.footprint)
	g.y_top = def.y_max + 2.0
	for t in world.defs.trails_of(map_id):
		if not t.has_geometry():
			continue
		var z := t.zone_polygon()
		if z.size() >= 3:
			g.polygons.append(z)
			g.y_top = maxf(g.y_top, t.y_hi + 2.0)
		var gate := t.gate_into(t.other_map(map_id))
		if gate != null:
			g.exit_gates.append(gate)
	for p in def.canonical_portals():
		if p.has_anchor and p.accepts_press():
			g.exit_portals.append(p)
	for xf in def.player_spawns:
		g.entry_points.append(xf.origin)
	for p in def.portals:
		g.entry_points.append(p.spawn_transform.origin)
	for r in def.sidecar.get("routes", []):
		if not (r is Dictionary):
			continue
		for q in (r as Dictionary).get("points", []):
			if q is Array and (q as Array).size() >= 3:
				g.entry_points.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
	g.climbables = ClimbableDef.list_from_sidecar(def.sidecar.get("climbables", []))
	return g


## Scans one map of the island: scan(map_graph(map_id)).
func scan_map(map_id: String) -> MapGraph:
	return scan(map_graph(map_id))


## Samples, links, searches and groups `g` (no verification; see verify()). Fills g.stats.
func scan(g: MapGraph) -> MapGraph:
	var t0 := Time.get_ticks_msec()
	_n_rays = 0
	_n_shapes = 0
	_n_sweeps = 0
	g.cell = cell
	_grid(g)
	_sample(g)
	var t_sample := Time.get_ticks_msec() - t0
	_ladders(g)
	_edges(g)
	var t_edges := Time.get_ticks_msec() - t0 - t_sample
	_ends(g)
	_reverse(g)
	g.fwd = _bfs_forward(g)
	g.bwd = _bfs_backward(g)
	var flagged0 := _count_flagged(g)
	_refine(g)
	_group(g)
	var reach := 0
	var esc := 0
	for i in g.node_count():
		reach += g.fwd[i]
		esc += g.bwd[i]
	g.stats = {"nodes": g.node_count(), "certain_edges": g.e_dst.size(), "into_edges": g.i_dst.size(),
		"refined_jumps": _count_extra(g), "entries": g.entries.size(), "exits": g.exits.size(), "reachable": reach,
		"escapable": esc, "flagged_before_refine": flagged0, "flagged": _count_flagged(g),
		"components": g.components.size(), "fall_outs": g.fall_outs, "sample_ms": t_sample, "edges_ms": t_edges,
		"ms": Time.get_ticks_msec() - t0, "rays": _n_rays, "shape_queries": _n_shapes, "sweeps": _n_sweeps}
	return g


## A world-aligned grid (cells at multiples of `cell`, so every scan of a map samples the same columns) over the
## graph's polygons, and the bottom of its columns.
func _grid(g: MapGraph) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for poly in g.polygons:
		for v in poly:
			lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
			hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	g.origin = Vector2(floor(lo.x / cell) * cell, floor(lo.y / cell) * cell)
	g.nx = int(ceil((hi.x - g.origin.x) / cell)) + 1
	g.nz = int(ceil((hi.y - g.origin.y) / cell)) + 1
	g.y_bottom = g.kill_y - 0.5 if is_finite(g.kill_y) else g.y_top - 100.0


func _sample(g: MapGraph) -> void:
	var cols := g.nx * g.nz
	g.col_first.resize(cols)
	g.col_first.fill(-1)
	g.col_count.resize(cols)
	g.col_count.fill(0)
	var rects: Array[Rect2] = []
	for poly in g.polygons:
		var r := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			r = r.expand(v)
		rects.append(r)
	var kill_y := g.kill_y
	for ix in g.nx:
		var x := g.origin.x + ix * cell
		for iz in g.nz:
			var z := g.origin.y + iz * cell
			var p2 := Vector2(x, z)
			var inside := false
			for k in g.polygons.size():
				if rects[k].has_point(p2) and Geometry2D.is_point_in_polygon(p2, g.polygons[k]):
					inside = true
					break
			if not inside:
				continue
			var c := ix * g.nz + iz
			g.col_first[c] = g.surf_y.size()
			var y := g.y_top
			var n := 0
			while n < MAX_SURFACES:
				_n_rays += 1
				_ray.from = Vector3(x, y, z)
				_ray.to = Vector3(x, g.y_bottom, z)
				var hit := space.intersect_ray(_ray)
				if hit.is_empty():
					break
				var hy: float = (hit.position as Vector3).y
				var fl := _is_floor(hit.normal as Vector3)
				var node := -1
				var feet := Vector3(x, hy, z)
				if fl and hy >= kill_y and _clear(feet) and _open_above(feet, n, g.y_top):
					node = g.node_pos.size()
					g.node_pos.append(feet)
					g.node_col.append(c)
				g.surf_y.append(hy)
				g.surf_node.append(node)
				g.surf_floor.append(1 if fl else 0)
				n += 1
				y = hy - SURFACE_GAP_M
			g.col_count[c] = n


func _is_floor(n: Vector3) -> bool:
	return n.y > 0.0 and n.angle_to(Vector3.UP) <= model.floor_max_angle + 0.001


## The body capsule at `feet` overlaps nothing the player collides with.
func _clear(feet: Vector3) -> bool:
	_n_shapes += 1
	_shape_q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * _cap_lift)
	_shape_q.motion = Vector3.ZERO
	return space.intersect_shape(_shape_q, 1).is_empty()


## The capsule moves from feet `a` to feet `b` without touching anything.
func _sweep(a: Vector3, b: Vector3) -> bool:
	_n_sweeps += 1
	_shape_q.transform = Transform3D(Basis.IDENTITY, a + Vector3.UP * _cap_lift)
	_shape_q.motion = b - a
	var r := space.cast_motion(_shape_q)
	_shape_q.motion = Vector3.ZERO
	return r.size() > 0 and r[0] >= 0.9999


## Open air over the feet: the feet are not inside a closed solid. A capsule inside a hollow trimesh overlaps no triangle
## and tests clear, and Jolt reports no back faces (neither to rays nor to point queries), so this counts faces: going
## down the column, every surface met above the feet (tops_above: faces facing up) enters a solid; going up from
## the feet, every face met (they face down) is the bottom of a solid. A solid wholly above the feet adds one of each; a
## solid around the feet adds only its top. More tops than bottoms: buried. Under a one-sided sheet (a plinth skirt, a
## trail's shell) counts as buried too, which is right: the body passes such sheets only from below.
func _open_above(feet: Vector3, tops_above: int, y_top: float) -> bool:
	if tops_above == 0:
		return true
	var bottoms := 0
	var y := feet.y + SURFACE_GAP_M
	while bottoms < tops_above:
		_n_rays += 1
		_up_ray.from = Vector3(feet.x, y, feet.z)
		_up_ray.to = Vector3(feet.x, y_top, feet.z)
		var h := space.intersect_ray(_up_ray)
		if h.is_empty():
			break
		bottoms += 1
		y = (h.position as Vector3).y + SURFACE_GAP_M
	return bottoms >= tops_above


## The first surface of column c (top down) at or below height y; -1 if none.
func _first_at_or_below(g: MapGraph, c: int, y: float) -> int:
	var first := g.col_first[c]
	if first < 0:
		return -1
	for k in g.col_count[c]:
		if g.surf_y[first + k] <= y:
			return first + k
	return -1


## Ladders, ropes and vines (the map's sidecar climbables), every node in their grab bands:
##   from the line   feet within climb_grab_radius of the climb line and between bottom - 0.6 and top - exit (the
##                   controller's _find_climbable), not descend_only: Up grabs, climbing reaches top_exit or the foot
##   by jumping      feet below that band but a jump apex inside it (Up held in the air grabs; descend_only too)
##   from the top    feet within climb_top_grab_radius of top_exit or the line and within 0.6 of the top: Down grabs
func _ladders(g: MapGraph) -> void:
	var list := g.climbables
	var grab := model.climb_grab_radius
	var top_grab := model.climb_top_grab_radius
	var reach := model.jump_apex - MARGIN_M
	for c in list:
		var top_node := g.node_near(c.top_exit, model.step_up, SNAP_DOWN_M, 2)
		var foot_node := -1
		if c.has_foot_ground:
			foot_node = g.node_near(c.foot_ground, model.step_up, SNAP_DOWN_M, 2)
		else:
			# Letting go at the bottom: a fall onto the first surface under the climb position.
			var cp := c.climb_position(c.bottom.y, model.climb_standoff)
			var col := g.column_at(cp.x, cp.z)
			if col >= 0:
				var s := _first_at_or_below(g, col, c.bottom.y)
				if s >= 0 and g.surf_node[s] >= 0:
					foot_node = g.surf_node[s]
		var lo := c.bottom.y - 0.6
		var hi := c.top.y - model.climb_exit_below_top - 0.05
		var r_cells := int(ceil(maxf(grab, top_grab) / cell)) + 1
		var c0 := g.column_at(c.bottom.x, c.bottom.z)
		if c0 < 0:
			continue
		var ix0 := g.col_ix(c0)
		var iz0 := c0 % g.nz
		for dx in range(-r_cells, r_cells + 1):
			for dz in range(-r_cells, r_cells + 1):
				var ix := ix0 + dx
				var iz := iz0 + dz
				if ix < 0 or iz < 0 or ix >= g.nx or iz >= g.nz:
					continue
				var col := ix * g.nz + iz
				var first := g.col_first[col]
				if first < 0:
					continue
				for k in g.col_count[col]:
					var n := g.surf_node[first + k]
					if n < 0:
						continue
					var p := g.node_pos[n]
					var targets := PackedInt32Array()
					var on_line := c.line_distance_xz(p) <= grab
					# Grabbed from the ground inside the band, or by a jump (Up held) from below it; a descend_only rope
					# only in the air, and only down.
					if on_line and p.y <= hi and p.y + reach >= lo:
						if not c.descend_only:
							targets.append(top_node)
						targets.append(foot_node)
					var dt := minf(c.top_exit_distance_xz(p), c.line_distance_xz(p))
					if dt <= top_grab and absf(p.y - c.top.y) <= 0.6:
						targets.append(foot_node)
						targets.append(top_node)
					for t in targets:
						if t >= 0 and t != n:
							var cur: PackedInt32Array = g.ladder_out.get(n, PackedInt32Array())
							if not (t in cur):
								cur.append(t)
								g.ladder_out[n] = cur


## Certain and into edges of every node, in node order (CSR).
func _edges(g: MapGraph) -> void:
	var count := g.node_count()
	g.e_off.resize(count + 1)
	g.i_off.resize(count + 1)
	var step := model.step_up
	var snap := model.snap_down
	var hop_top := model.jump_apex + model.step_up
	var kill_y := g.kill_y
	var nz := g.nz
	for a in count:
		g.e_off[a] = g.e_dst.size()
		g.i_off[a] = g.i_dst.size()
		var pa := g.node_pos[a]
		var ca := g.node_col[a]
		var ix := g.col_ix(ca)
		var iz := ca % nz
		var boundary := false
		for d in 8:
			var dv: Vector2i = DIRS[d]
			var jx := ix + dv.x
			var jz := iz + dv.y
			if jx < 0 or jz < 0 or jx >= g.nx or jz >= nz:
				continue
			var cn := jx * nz + jz
			if g.col_first[cn] < 0:
				continue
			var s := _first_at_or_below(g, cn, pa.y + step + RAY_HEADROOM_M)
			if s >= 0 and g.surf_y[s] >= pa.y - snap:
				# Within the feet's step band: walk there, if the feet can stand on it.
				var b := g.surf_node[s]
				if b >= 0:
					g.e_dst.append(b)
					g.e_kind.append(Edge.WALK)
				else:
					boundary = true
				continue
			boundary = true
			# Walking off an edge: the body falls onto the first surface under the feet.
			if s < 0 or g.surf_y[s] < kill_y:
				g.fall_outs += 1
				if g.fall_out_samples.size() < 16:
					g.fall_out_samples.append(pa)
				continue
			var land := g.surf_node[s]
			if land >= 0:
				var lp := g.node_pos[land]
				var over := Vector3(lp.x, pa.y, lp.z)
				if _sweep(pa, over):
					if _sweep(over, lp):
						g.e_dst.append(land)
						g.e_kind.append(Edge.DROP)
					else:
						# The fall brushes a wall or a lip: the body slides down it, landing somewhere near.
						g.i_dst.append(land)
						g.i_kind.append(Edge.SLIDE)
			else:
				_slides(g, pa, cn, g.surf_y[s])
			# Momentum carries a walk-off further than one column: into edges to the surfaces further along.
			_long_drops(g, a, pa, ix, iz, dv)
		if g.ladder_out.has(a):
			for t: int in g.ladder_out[a]:
				g.e_dst.append(t)
				g.e_kind.append(Edge.LADDER)
		if boundary:
			_hops(g, a, pa, ix, iz, hop_top)
	g.e_off[count] = g.e_dst.size()
	g.i_off[count] = g.i_dst.size()


## Into edges for a walk-off at node a in direction dv: columns 2..DROP_CELLS away whose first surface below the feet
## a falling body at walk speed can reach (horizontal travel = walk_speed x fall time), swept.
func _long_drops(g: MapGraph, a: int, pa: Vector3, ix: int, iz: int, dv: Vector2i) -> void:
	var step_len := cell * Vector2(dv).length()
	for k in range(2, DROP_CELLS + 1):
		var jx := ix + dv.x * k
		var jz := iz + dv.y * k
		if jx < 0 or jz < 0 or jx >= g.nx or jz >= g.nz:
			return
		var cm := jx * g.nz + jz
		if g.col_first[cm] < 0:
			return
		var s := _first_at_or_below(g, cm, pa.y + model.step_up + RAY_HEADROOM_M)
		if s < 0:
			continue
		var fall := pa.y - g.surf_y[s]
		if fall < model.snap_down:
			return  # the ground comes back up: a later column is no longer a drop
		var reach := model.walk_speed * sqrt(2.0 * fall / model.gravity) + model.foot_radius
		if step_len * k > reach:
			continue
		var b := g.surf_node[s]
		if b < 0:
			continue
		var lp := g.node_pos[b]
		if _sweep(pa, Vector3(lp.x, pa.y, lp.z)):
			g.i_dst.append(b)
			g.i_kind.append(Edge.LONG_DROP)


## Into edges for a walk-off whose landing surface (height y in column c) has no room for the body (a narrow gap
## beside a cliff or a wall): the falling capsule is pushed off the walls onto the standable surfaces around it (the
## nodes of the 8 neighbouring columns within step_up of y), when the way over them at the take-off height is clear.
func _slides(g: MapGraph, pa: Vector3, c: int, y: float) -> void:
	var ix := g.col_ix(c)
	var iz := c % g.nz
	for d in 8:
		var dv: Vector2i = DIRS[d]
		var jx := ix + dv.x
		var jz := iz + dv.y
		if jx < 0 or jz < 0 or jx >= g.nx or jz >= g.nz:
			continue
		var cm := jx * g.nz + jz
		var first := g.col_first[cm]
		if first < 0:
			continue
		for k in g.col_count[cm]:
			var b := g.surf_node[first + k]
			if b < 0 or absf(g.surf_y[first + k] - y) > model.step_up:
				continue
			var lp := g.node_pos[b]
			if _sweep(pa, Vector3(lp.x, pa.y, lp.z)):
				g.i_dst.append(b)
				g.i_kind.append(Edge.SLIDE)


## Into edges for jumps from a boundary node: in each direction, the top surface of the columns 1..HOP_CELLS away that
## a jump could land on (at most jump_apex + step_up above the feet, at most MAX_JUMP_DOWN_M below; a lower landing is
## a drop). Swept as an L (up to the apex, across, down onto it) rather than along the arc: generous, but never
## through a wall or into a solid.
func _hops(g: MapGraph, a: int, pa: Vector3, ix: int, iz: int, hop_top: float) -> void:
	var top := pa + Vector3.UP * model.jump_apex
	if not _sweep(pa, top):
		return
	for d in 8:
		var dv: Vector2i = DIRS[d]
		for k in range(1, HOP_CELLS + 1):
			var jx := ix + dv.x * k
			var jz := iz + dv.y * k
			if jx < 0 or jz < 0 or jx >= g.nx or jz >= g.nz:
				break
			var cm := jx * g.nz + jz
			if g.col_first[cm] < 0:
				break
			var s := _first_at_or_below(g, cm, pa.y + hop_top + RAY_HEADROOM_M)
			if s < 0:
				continue
			var b := g.surf_node[s]
			if b < 0:
				continue
			var lp := g.node_pos[b]
			if k == 1 and lp.y <= pa.y + model.step_up:
				continue  # a walk or a drop, already an edge
			if lp.y < pa.y - MAX_JUMP_DOWN_M:
				continue
			var over := Vector3(lp.x, top.y, lp.z)
			if not _sweep(top, over):
				break
			if not _sweep(over, lp):
				continue
			g.i_dst.append(b)
			g.i_kind.append(Edge.HOP)


## Entries (forward seeds) and exits (backward seeds).
func _ends(g: MapGraph) -> void:
	var seen := {}
	for p in g.entry_points:
		var n := g.node_near(p, SNAP_UP_M, SNAP_DOWN_M, 2)
		if n >= 0 and not seen.has(n):
			seen[n] = true
			g.entries.append(n)
	for n in g.node_count():
		if exit_reason(g, g.node_pos[n]) != "":
			g.exits.append(n)


## Why feet at `p` have left this map's play: "portal <id>" inside a press-Up trigger, "map <id>" past the gate of a
## trail into another map (inside its corridor and height band: the GateMonitor's arm rule), "exit <i>" inside a
## hand-made graph's exit box, else "".
func exit_reason(g: MapGraph, p: Vector3) -> String:
	var probe := p + Vector3.UP * 0.1
	for portal in g.exit_portals:
		if portal.trigger_contains(probe):
			return "portal " + portal.portal_id
	for gate in g.exit_gates:
		if gate.signed_distance(p) > 0.0 and gate.in_box(p):
			return "map " + gate.map_id
	for i in g.exit_boxes.size():
		if g.exit_boxes[i].has_point(probe):
			return "exit %d" % i
	return ""


## The reverse of the certain edges (CSR).
func _reverse(g: MapGraph) -> void:
	var count := g.node_count()
	var deg := PackedInt32Array()
	deg.resize(count + 1)
	deg.fill(0)
	for k in g.e_dst.size():
		deg[g.e_dst[k] + 1] += 1
	for i in count:
		deg[i + 1] += deg[i]
	g.r_off = deg.duplicate()
	g.r_src.resize(g.e_dst.size())
	var fill := deg
	for a in count:
		for k in range(g.e_off[a], g.e_off[a + 1]):
			var b := g.e_dst[k]
			g.r_src[fill[b]] = a
			fill[b] += 1


func _bfs_forward(g: MapGraph) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(g.node_count())
	seen.fill(0)
	var queue := PackedInt32Array()
	for s in g.entries:
		if seen[s] == 0:
			seen[s] = 1
			queue.append(s)
	var head := 0
	while head < queue.size():
		var u := queue[head]
		head += 1
		for k in range(g.e_off[u], g.e_off[u + 1]):
			var v := g.e_dst[k]
			if seen[v] == 0:
				seen[v] = 1
				queue.append(v)
		for k in range(g.i_off[u], g.i_off[u + 1]):
			var v := g.i_dst[k]
			if seen[v] == 0:
				seen[v] = 1
				queue.append(v)
	return seen


func _bfs_backward(g: MapGraph) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(g.node_count())
	seen.fill(0)
	var queue := PackedInt32Array()
	for s in g.exits:
		if seen[s] == 0:
			seen[s] = 1
			queue.append(s)
	_propagate_back(g, seen, queue)
	return seen


## Backward search from `queue` (already marked in `seen`) over the reversed certain and refined edges.
func _propagate_back(g: MapGraph, seen: PackedByteArray, queue: PackedInt32Array) -> void:
	var head := 0
	while head < queue.size():
		var u := queue[head]
		head += 1
		for k in range(g.r_off[u], g.r_off[u + 1]):
			var v := g.r_src[k]
			if seen[v] == 0:
				seen[v] = 1
				queue.append(v)
		if g.extra_rev.has(u):
			for v: int in g.extra_rev[u]:
				if seen[v] == 0:
					seen[v] = 1
					queue.append(v)


func _count_flagged(g: MapGraph) -> int:
	var n := 0
	for i in g.node_count():
		if g.fwd[i] == 1 and g.bwd[i] == 0:
			n += 1
	return n


func _count_extra(g: MapGraph) -> int:
	var n := 0
	for k in g.extra:
		n += (g.extra[k] as PackedInt32Array).size()
	return n


## Certain jumps, computed only for flagged nodes (they are the expensive edges): from each flagged node to the
## escapable or flagged nodes a running jump lands on along a capsule-swept arc. A jump that reaches an escapable node
## makes the node escapable, and the backward search continues from it at once.
func _refine(g: MapGraph) -> void:
	var cands := PackedInt32Array()
	for i in g.node_count():
		if g.fwd[i] == 1 and g.bwd[i] == 0:
			cands.append(i)
	if cands.is_empty():
		return
	var cand_set := PackedByteArray()
	cand_set.resize(g.node_count())
	cand_set.fill(0)
	for i in cands:
		cand_set[i] = 1
	var v0 := model.jump_velocity
	var grav := model.gravity
	var reach_up := _jump_reach()
	var t_far := (v0 + sqrt(v0 * v0 + 2.0 * grav * MAX_JUMP_DOWN_M)) / grav
	var r_cells := int(ceil(model.walk_speed * t_far / cell))
	var ring := _ring_offsets(r_cells)
	for a in cands:
		if g.bwd[a] == 1:
			continue
		var pa := g.node_pos[a]
		var ca := g.node_col[a]
		var ix := g.col_ix(ca)
		var iz := ca % g.nz
		var found := PackedInt32Array()
		var escaped := false
		for off: Vector2i in ring:
			var jx := ix + off.x
			var jz := iz + off.y
			if jx < 0 or jz < 0 or jx >= g.nx or jz >= g.nz:
				continue
			var cm := jx * g.nz + jz
			var first := g.col_first[cm]
			if first < 0:
				continue
			for k in g.col_count[cm]:
				var b := g.surf_node[first + k]
				if b < 0 or b == a:
					continue
				var useful := g.bwd[b] == 1 or cand_set[b] == 1
				if not useful:
					continue
				var pb := g.node_pos[b]
				var dy := pb.y - pa.y
				if dy > reach_up or dy < -MAX_JUMP_DOWN_M:
					continue
				# A flagged target only helps when it is higher (same-level flagged nodes are walked between).
				if g.bwd[b] == 0 and dy <= model.step_up:
					continue
				if not _jump_lands(g, pa, pb):
					continue
				found.append(b)
				if g.bwd[b] == 1:
					escaped = true
					break
			if escaped:
				break
		if found.is_empty():
			continue
		g.extra[a] = found
		for b in found:
			var rev: PackedInt32Array = g.extra_rev.get(b, PackedInt32Array())
			rev.append(a)
			g.extra_rev[b] = rev
		if escaped:
			g.bwd[a] = 1
			_propagate_back(g, g.bwd, PackedInt32Array([a]))


## Cell offsets within r cells, nearest first.
func _ring_offsets(r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if (dx != 0 or dz != 0) and dx * dx + dz * dz <= r * r:
				out.append(Vector2i(dx, dz))
	out.sort_custom(func(u: Vector2i, w: Vector2i) -> bool: return u.length_squared() < w.length_squared())
	return out


## A running jump from feet pa lands on pb: the controller lands only while descending, with its feet within step_up
## below the surface (MARGIN_M less here), so the landing time is the descending root of the arc at pb's height (or
## the apex when pb is above the apex) and the horizontal speed it needs must not exceed the walk speed. The capsule
## must sweep clear along the arc, and the feet must not meet another surface on the way down first.
func _jump_lands(g: MapGraph, pa: Vector3, pb: Vector3) -> bool:
	var v0 := model.jump_velocity
	var grav := model.gravity
	var dy := pb.y - pa.y
	var dist := Vector2(pb.x - pa.x, pb.z - pa.z).length()
	if dist < cell * 0.5:
		return false
	var t_apex := v0 / grav
	var t_land := t_apex
	if dy <= model.jump_apex:
		var disc := v0 * v0 - 2.0 * grav * dy
		if disc < 0.0:
			return false
		t_land = (v0 + sqrt(disc)) / grav
	var vh := dist / t_land
	if vh > model.walk_speed:
		return false
	var dir := Vector3(pb.x - pa.x, 0.0, pb.z - pa.z) / dist
	var prev := pa
	for k in range(1, ARC_SAMPLES + 1):
		var t := t_land * k / ARC_SAMPLES
		var y := pa.y + v0 * t - 0.5 * grav * t * t
		var p := pa + dir * (vh * t)
		p.y = maxf(y, pb.y) if k == ARC_SAMPLES else y
		if not _sweep(prev, p):
			return false
		# Descending over another surface within the landing band: the body lands there first.
		if t > t_apex and k < ARC_SAMPLES:
			var col := g.column_at(p.x, p.z)
			if col >= 0:
				var s := _first_at_or_below(g, col, p.y + model.step_up + RAY_HEADROOM_M)
				if s >= 0 and g.surf_y[s] >= p.y - 0.01 and g.surf_floor[s] == 1 and absf(g.surf_y[s] - pb.y) > 0.1:
					return false
		prev = p
	return true


## Groups the flagged nodes into components (connected through any edge between them, either way) and summarises
## each, largest first.
func _group(g: MapGraph) -> void:
	var count := g.node_count()
	# Union-find over every edge (certain, into, refined jumps) between flagged nodes, either way.
	var parent := PackedInt32Array()
	parent.resize(count)
	for i in count:
		parent[i] = i
	for u in count:
		if g.fwd[u] == 0 or g.bwd[u] == 1:
			continue
		for e: Array in g.out_edges(u):
			var v: int = e[0]
			if g.fwd[v] == 1 and g.bwd[v] == 0:
				var ru := _root(parent, u)
				var rv := _root(parent, v)
				if ru != rv:
					parent[maxi(ru, rv)] = mini(ru, rv)
	var by_root := {}
	for u in count:
		if g.fwd[u] == 0 or g.bwd[u] == 1:
			continue
		var r := _root(parent, u)
		if not by_root.has(r):
			by_root[r] = PackedInt32Array()
		var m: PackedInt32Array = by_root[r]
		m.append(u)
		by_root[r] = m
	var groups: Array[PackedInt32Array] = []
	for r in by_root:
		groups.append(by_root[r])
	groups.sort_custom(func(x: PackedInt32Array, y: PackedInt32Array) -> bool: return x.size() > y.size())
	var comp_of := PackedInt32Array()
	comp_of.resize(count)
	comp_of.fill(-1)
	for i in groups.size():
		for u in groups[i]:
			comp_of[u] = i
	# The ways in: edges from escapable reachable nodes onto each component (one pass over the graph).
	var ins: Array = []
	for i in groups.size():
		ins.append([])
	for v in count:
		if g.fwd[v] == 0 or g.bwd[v] == 0:
			continue
		for e: Array in g.out_edges(v):
			var ci := comp_of[int(e[0])]
			if ci >= 0 and (ins[ci] as Array).size() < IN_EDGES * 16:
				(ins[ci] as Array).append(_edge_info(g, v, int(e[0]), int(e[1])))
	for i in groups.size():
		g.components.append(_component_summary(g, i, groups[i], ins[i]))


func _root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


func _edge_info(g: MapGraph, v: int, u: int, kind: int) -> Dictionary:
	var pv := g.node_pos[v]
	var pu := g.node_pos[u]
	return {"from": v, "to": u, "kind": EDGE_NAMES[kind], "from_local": _r3(g.to_local(pv)), "to_local": _r3(g.to_local(pu)),
		"dy": snappedf(pu.y - pv.y, 0.01)}


## What a component is: its nodes, area, centre and height span in map-local and Blender-local coordinates, what the
## floor is, and the ways in (in_edges: up to IN_EDGES edges from escapable reachable nodes, the likeliest first:
## walks and drops, then slides, longer drops and hops, each by the smallest height change).
func _component_summary(g: MapGraph, index: int, members: PackedInt32Array, ins: Array) -> Dictionary:
	var c := Vector3.ZERO
	var y_lo := INF
	var y_hi := -INF
	for u in members:
		var p := g.node_pos[u]
		c += p
		y_lo = minf(y_lo, p.y)
		y_hi = maxf(y_hi, p.y)
	c /= float(members.size())
	# The member nearest the centre is the component's anchor point (the centre itself may be in the air).
	var anchor := members[0]
	var best := INF
	for u in members:
		var d := g.node_pos[u].distance_squared_to(c)
		if d < best:
			best = d
			anchor = u
	var ap := g.node_pos[anchor]
	var local := g.to_local(ap)
	var member_set := {}
	for u in members:
		member_set[u] = true
	ins.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var kx := _kind_rank(String(x.kind))
		var ky := _kind_rank(String(y.kind))
		return kx < ky or (kx == ky and absf(float(x.dy)) < absf(float(y.dy))))
	var in_edges := ins.slice(0, IN_EDGES)
	var drop := -float(in_edges[0].dy) if not in_edges.is_empty() else 0.0
	return {"id": "%s#%d" % [g.map_id, index], "map_id": g.map_id, "nodes": members.size(),
		"area_m2": snappedf(members.size() * cell * cell, 0.01), "anchor": anchor, "anchor_world": ap,
		"local": _r3(local), "blender_local_xy": [snappedf(local.x, 0.01), snappedf(-local.z, 0.01)],
		"y_local": [snappedf(y_lo - g.frame.origin.y, 0.01), snappedf(y_hi - g.frame.origin.y, 0.01)],
		"floor": _floor_kinds(g, members), "in_edges": in_edges, "drop_m": snappedf(maxf(drop, 0.0), 0.01),
		"entries_inside": _count_in(g.entries, member_set), "members": members, "verdict": "", "allowlisted": ""}


## How many of `nodes` are in `member_set` (entries inside a component: a route point or a spawn there).
func _count_in(nodes: PackedInt32Array, member_set: Dictionary) -> int:
	var n := 0
	for u in nodes:
		if member_set.has(u):
			n += 1
	return n


## How likely an edge kind is the way a player gets in (lower first).
func _kind_rank(kind: String) -> int:
	return ["walk", "drop", "slide", "long drop", "hop", "ladder", "jump"].find(kind)


## What the component's floor is: collider names (chunk/body) with how many sampled nodes stand on each.
func _floor_kinds(g: MapGraph, members: PackedInt32Array) -> Dictionary:
	var kinds := {}
	var step := maxi(1, int(members.size() / 40.0))
	for mi in range(0, members.size(), step):
		var p := g.node_pos[members[mi]]
		_ray.from = p + Vector3.UP * 0.1
		_ray.to = p + Vector3.DOWN * 0.2
		var h := space.intersect_ray(_ray)
		var what := "?"
		if not h.is_empty():
			var col: Object = h.get("collider")
			if col is Node:
				var nd := col as Node
				var parent := nd.get_parent()
				what = "%s/%s" % [String(parent.name) if parent != null else "", String(nd.name)]
				if col is CollisionObject3D:
					what += " (%s)" % WorldLayers.NAMES.get((col as CollisionObject3D).collision_layer, str((col as CollisionObject3D).collision_layer))
		kinds[what] = int(kinds.get(what, 0)) + 1
	return kinds


func _r3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


# =================================================================================================================
# Verification with the real controller
# =================================================================================================================

## Labels every component of `g` CONFIRMED, CLEARED or UNENTERABLE with the game's PlayerController.
func verify(g: MapGraph) -> void:
	if g.components.is_empty():
		return
	var pw := PlayerTestWorld.create(db, host)
	var p := pw.spawn_player(g.node_pos[g.components[0].anchor] + Vector3.UP * 0.05)
	p.collision_mask = WorldLayers.PLAYER_MASK
	p.set_climbables(g.climbables.duplicate())
	p.kill_y = g.kill_y
	for comp in g.components:
		_verify_component(g, pw, comp)
	pw.free_all()


func _verify_component(g: MapGraph, pw: PlayerTestWorld, comp: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	var members: PackedInt32Array = comp.members
	var member_set := {}
	for u in members:
		member_set[u] = true
	# 1. Can the controller get in? Replay the in-edges.
	var entered := false
	var enter_how := ""
	for e: Dictionary in comp.in_edges:
		var r := _try_enter(g, pw, int(e.from), int(e.to), String(e.kind), member_set)
		if r != "":
			entered = true
			enter_how = "%s (%s edge from local %s)" % [r, e.kind, e.from_local]
			break
	# 2. Can it get out? From up to SAMPLES members.
	var samples := _samples(g, members)
	var results: Array[Dictionary] = []
	var all_out := true
	for s in samples:
		var r := _escape(g, pw, s)
		results.append(r)
		if not bool(r.escaped):
			all_out = false
	var verdict := VERDICT_CLEARED
	if not all_out:
		# Entered by replaying a way in, or reachable from an entry inside it (a spawn or a route point).
		verdict = VERDICT_CONFIRMED if entered or int(comp.entries_inside) > 0 else VERDICT_UNENTERABLE
	comp["verdict"] = verdict
	comp["entered"] = entered
	comp["enter_how"] = enter_how
	comp["samples"] = results
	comp["verify_ms"] = Time.get_ticks_msec() - t0


## The anchor, then the members farthest from it (up to SAMPLES).
func _samples(g: MapGraph, members: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c := Vector3.ZERO
	for u in members:
		c += g.node_pos[u]
	c /= float(members.size())
	var anchor := members[0]
	var best := INF
	for u in members:
		var d := g.node_pos[u].distance_squared_to(c)
		if d < best:
			best = d
			anchor = u
	out.append(anchor)
	while out.size() < mini(SAMPLES, members.size()):
		var far := -1
		var far_d := -1.0
		for u in members:
			var d := INF
			for s in out:
				d = minf(d, g.node_pos[u].distance_squared_to(g.node_pos[s]))
			if d > far_d:
				far_d = d
				far = u
		if far < 0 or far_d < 1.0:
			break
		out.append(far)
	return out


## Replays an in-edge: stand on `from`, move toward `to` (walking at full and at low speed, or hopping for a jump
## edge). Returns how it got in ("" when it never ended up on the component).
func _try_enter(g: MapGraph, pw: PlayerTestWorld, from: int, to: int, kind: String, member_set: Dictionary) -> String:
	var a := g.node_pos[from]
	var b := g.node_pos[to]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if dir.length_squared() < 1e-6:
		return ""
	dir = dir.normalized()
	for mode in ["walk", "creep", "hop"]:
		var p := _place(pw, a)
		pw.bot.release_all()
		for t in ENTER_TICKS:
			pw.bot.world_dir = dir * (0.3 if mode == "creep" else 1.0)
			if mode == "hop" and t == 2:
				pw.bot.hold(&"jump", true)
			pw.run(1)
			if p.is_grounded() and t > 6:
				var n := g.node_near(p.global_position, 0.3, 0.3, 1)
				if n >= 0 and member_set.has(n):
					pw.bot.release_all()
					return mode
		pw.bot.release_all()
		pw.run(30)
		if p.is_grounded():
			var n2 := g.node_near(p.global_position, 0.3, 0.3, 1)
			if n2 >= 0 and member_set.has(n2):
				return mode
	return ""


## Teleports the controller onto feet `at` and lets it settle.
func _place(pw: PlayerTestWorld, at: Vector3) -> PlayerController:
	var p := pw.player
	pw.bot.release_all()
	p.teleport(Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.05))
	pw.run(4)
	return p


## Tries to get from member `start` back to escapable ground: toward the nearest escapable nodes (walking, hopping, a
## run-up), then in SWEEP_DIRECTIONS directions (walking, hopping), with Up pressed for ladders. A try whose end is a
## new flagged place more than RESTART_M away becomes another start (up to MAX_STARTS). Returns {escaped, how, tries,
## best_rise_m, start_local, end_local}.
func _escape(g: MapGraph, pw: PlayerTestWorld, start: int) -> Dictionary:
	var starts: Array[Vector3] = [g.node_pos[start]]
	var tries := 0
	var best_rise := 0.0
	var origin_y := g.node_pos[start].y
	var out := {"escaped": false, "how": "", "tries": 0, "start_local": _r3(g.to_local(g.node_pos[start]))}
	var si := 0
	while si < starts.size() and tries < MAX_TRIES:
		var s := starts[si]
		si += 1
		var plans: Array[Dictionary] = []
		for target in nearest_escapable(g, s, TARGETS):
			var tp := g.node_pos[target]
			plans.append({"to": tp, "jump": "none", "ticks": TRY_TICKS})
			plans.append({"to": tp, "jump": "hold", "ticks": TRY_TICKS})
			plans.append({"to": tp, "jump": "runup", "ticks": TRY_TICKS})
		for k in SWEEP_DIRECTIONS:
			var d := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / SWEEP_DIRECTIONS)
			plans.append({"dir": d, "jump": "none", "ticks": SWEEP_TICKS})
			plans.append({"dir": d, "jump": "hold", "ticks": SWEEP_TICKS})
		for plan in plans:
			if tries >= MAX_TRIES:
				break
			tries += 1
			var r := _try(g, pw, s, plan)
			best_rise = maxf(best_rise, float(r.best_y) - origin_y)
			if bool(r.escaped):
				out["escaped"] = true
				out["how"] = "%s from local %s: %s" % [_plan_text(plan, g), _r3(g.to_local(s)), r.why]
				out["tries"] = tries
				out["best_rise_m"] = snappedf(best_rise, 0.01)
				return out
			var e: Vector3 = r.end
			if bool(r.grounded) and starts.size() < MAX_STARTS and Vector2(e.x - s.x, e.z - s.z).length() > RESTART_M:
				var far := true
				for q in starts:
					if q.distance_to(e) < RESTART_M:
						far = false
				if far:
					starts.append(e)
	out["tries"] = tries
	out["best_rise_m"] = snappedf(best_rise, 0.01)
	return out


func _plan_text(plan: Dictionary, g: MapGraph) -> String:
	var what := "toward local %s" % [_r3(g.to_local(plan.to))] if plan.has("to") else "direction %s" % [_r3(plan.dir)]
	return "%s, jump %s" % [what, plan.jump]


## One scripted try from feet `s`. plan: to (steer toward it) or dir; jump: none, hold (hop on every landing) or
## runup (back off 0.3 s, then hop toward it). Up (portal_enter) is held, re-pressed every 12 ticks, so ladders and
## ropes are grabbed and climbed. Returns {escaped, why, end, grounded, best_y}.
func _try(g: MapGraph, pw: PlayerTestWorld, s: Vector3, plan: Dictionary) -> Dictionary:
	var p := _place(pw, s)
	var best_y := p.global_position.y
	var why := escape_reason(g, p.global_position, p.is_grounded())
	if why != "":
		return {"escaped": true, "why": why, "end": p.global_position, "grounded": p.is_grounded(), "best_y": best_y}
	var fell := [false]
	var on_fell := func(_at: Vector3) -> void: fell[0] = true
	p.fell_out_of_world.connect(on_fell)
	var ticks: int = plan.ticks
	var runup := 18 if plan.jump == "runup" else 0
	for t in ticks + runup:
		var d := Vector3.ZERO
		if plan.has("to"):
			var tp: Vector3 = plan.to
			d = Vector3(tp.x - p.global_position.x, 0.0, tp.z - p.global_position.z)
			if d.length() < 0.15:
				d = Vector3.ZERO
			else:
				d = d.normalized()
		else:
			d = plan.dir
		if t < runup:
			d = -d
		pw.bot.world_dir = d
		var jumping: bool = plan.jump == "hold" or (plan.jump == "runup" and t >= runup)
		pw.bot.hold(&"jump", jumping and t >= 1)
		pw.bot.hold(&"portal_enter", t % 12 != 0)
		pw.run(1)
		if fell[0]:
			break
		if p.is_grounded() or p.is_climbing():
			best_y = maxf(best_y, p.global_position.y)
		why = escape_reason(g, p.global_position, p.is_grounded())
		if why != "":
			break
	pw.bot.release_all()
	if why == "" and not fell[0]:
		pw.run(30)
		why = escape_reason(g, p.global_position, p.is_grounded())
	p.fell_out_of_world.disconnect(on_fell)
	return {"escaped": why != "", "why": why if why != "" else ("fell below kill_y" if fell[0] else ""),
		"end": p.global_position, "grounded": p.is_grounded(), "best_y": best_y}


## Why a body with feet `at` is out of the trap: grounded on an escapable node, in a press-Up trigger, or past a gate
## into another map; "" otherwise (trap_probe uses it on the live game).
func escape_reason(g: MapGraph, at: Vector3, grounded: bool) -> String:
	var ex := exit_reason(g, at)
	if ex != "":
		return "reached " + ex
	if grounded:
		var n := g.node_near(at, 0.3, 0.3, 1)
		if n >= 0 and g.bwd[n] == 1:
			return "stands on escapable ground at local %s" % [_r3(g.to_local(at))]
	return ""


## The `count` escapable nodes nearest to feet `p` (horizontal distance, spread over different directions).
func nearest_escapable(g: MapGraph, p: Vector3, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c0 := g.column_at(p.x, p.z)
	if c0 < 0:
		return out
	var ix0 := g.col_ix(c0)
	var iz0 := c0 % g.nz
	var max_r := int(30.0 / cell)
	var dirs: Array[Vector2] = []
	for r in range(1, max_r + 1):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var ix := ix0 + dx
				var iz := iz0 + dz
				if ix < 0 or iz < 0 or ix >= g.nx or iz >= g.nz:
					continue
				var col := ix * g.nz + iz
				var first := g.col_first[col]
				if first < 0:
					continue
				for k in g.col_count[col]:
					var n := g.surf_node[first + k]
					if n < 0 or g.bwd[n] == 0:
						continue
					var dv := Vector2(dx, dz).normalized()
					var distinct := true
					for o in dirs:
						if o.dot(dv) > 0.7:
							distinct = false
					if not distinct:
						continue
					dirs.append(dv)
					out.append(n)
					if out.size() >= count:
						return out
	return out


# =================================================================================================================
# Whole-island run and the report
# =================================================================================================================

## Scans (and verifies) `maps` (MeowDB ids; empty = every map) and returns the report document
## (docs/runtime/stuck_report.json). Components are matched against the allowlist. `png_dir` (optional): writes a
## top-down picture of each map there (heatmap()).
func run(maps: PackedStringArray = PackedStringArray(), do_verify: bool = true, png_dir: String = "") -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var ids := maps if not maps.is_empty() else world.defs.ids()
	var per_map := {}
	var totals := {"maps": 0, "nodes": 0, "certain_edges": 0, "into_edges": 0, "reachable": 0, "flagged": 0,
		"components": 0, "confirmed": 0, "cleared": 0, "unenterable": 0, "unverified": 0, "allowlisted": 0,
		"new_traps": 0, "fall_outs": 0}
	var traps: Array[Dictionary] = []
	for id in ids:
		if not world.defs.has_map(id):
			continue
		var g := scan_map(id)
		if do_verify:
			verify(g)
		if png_dir != "":
			heatmap(g, 5).save_png(png_dir.path_join("stuck_%s.png" % id))
		var comps: Array = []
		for comp in g.components:
			var entry := report_component(g, comp)
			comps.append(entry)
			var verdict := String(comp.verdict)
			match verdict:
				VERDICT_CONFIRMED:
					totals.confirmed += 1
				VERDICT_CLEARED:
					totals.cleared += 1
				VERDICT_UNENTERABLE:
					totals.unenterable += 1
				_:
					totals.unverified += 1
			if String(comp.allowlisted) != "":
				totals.allowlisted += 1
			elif verdict == VERDICT_CONFIRMED:
				totals.new_traps += 1
				traps.append(entry)
		var row := g.stats.duplicate()
		row["name"] = g.name
		row["kill_y_local"] = snappedf(g.kill_y - g.frame.origin.y, 0.01)
		var fo: Array = []
		for q in g.fall_out_samples:
			fo.append(_r3(g.to_local(q)))
		row["fall_out_samples_local"] = fo
		row["components"] = comps
		per_map[id] = row
		totals.maps += 1
		totals.nodes += int(g.stats.nodes)
		totals.certain_edges += int(g.stats.certain_edges)
		totals.into_edges += int(g.stats.into_edges)
		totals.reachable += int(g.stats.reachable)
		totals.flagged += int(g.stats.flagged)
		totals.components += g.components.size()
		totals.fall_outs += g.fall_outs
	totals["ms"] = Time.get_ticks_msec() - t0
	return {"params": params(), "totals": totals, "traps": traps, "maps": per_map}


## The JSON-ready summary of a component (with its allowlist match, if any).
func report_component(g: MapGraph, comp: Dictionary) -> Dictionary:
	var hit := _allowlisted(g, comp)
	comp["allowlisted"] = hit
	var out := {}
	for k in ["id", "nodes", "area_m2", "local", "blender_local_xy", "y_local", "drop_m", "entries_inside", "floor", "verdict",
			"entered", "enter_how", "verify_ms"]:
		if comp.has(k):
			out[k] = comp[k]
	var edges: Array = []
	for e: Dictionary in comp.in_edges:
		if edges.size() < 3:
			edges.append({"kind": e.kind, "from_local": e.from_local, "to_local": e.to_local, "dy": e.dy})
	out["in_edges"] = edges
	if comp.has("samples"):
		out["samples"] = comp.samples
	if hit != "":
		out["allowlisted"] = hit
	return out


## The allowlist entry's reason when the component holds a node within the entry's radius of its map-local point.
func _allowlisted(g: MapGraph, comp: Dictionary) -> String:
	for e in allowlist:
		if not (e is Dictionary) or String((e as Dictionary).get("map_id", "")) != g.map_id:
			continue
		var l: Array = (e as Dictionary).get("local", [])
		if l.size() < 3:
			continue
		var at := g.to_world(Vector3(float(l[0]), float(l[1]), float(l[2])))
		var radius := float((e as Dictionary).get("radius_m", 1.0))
		for u: int in comp.members:
			if g.node_pos[u].distance_to(at) <= radius:
				return String((e as Dictionary).get("reason", "allowlisted"))
	return ""


## A top-down picture of the graph in map-local (Blender) axes, x right and y (= -z) up, one pixel per cell: for each
## column its top node, green by height when it is escapable, red when flagged (CONFIRMED: bright, else dull), grey
## when nothing reaches it; white entries, yellow exits, black where no node stands. For inspection only.
func heatmap(g: MapGraph, scale: int = 2) -> Image:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for poly in g.polygons.slice(0, 1):
		for v in poly:
			var l := g.to_local(Vector3(v.x, g.frame.origin.y, v.y))
			lo = Vector2(minf(lo.x, l.x), minf(lo.y, -l.z))
			hi = Vector2(maxf(hi.x, l.x), maxf(hi.y, -l.z))
	lo -= Vector2(2.0, 2.0)
	hi += Vector2(2.0, 2.0)
	var w := int(ceil((hi.x - lo.x) / cell))
	var h := int(ceil((hi.y - lo.y) / cell))
	var img := Image.create(w * scale, h * scale, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	var confirmed := {}
	for comp in g.components:
		if String(comp.get("verdict", "")) == VERDICT_CONFIRMED:
			for u in (comp.members as PackedInt32Array):
				confirmed[u] = true
	var y_span := maxf(g.y_top - g.frame.origin.y, 1.0)
	var marks := {}
	for n in g.entries:
		marks[n] = Color.WHITE
	for n in g.exits:
		marks[n] = Color.YELLOW
	for px in w:
		for py in h:
			var local := Vector3(lo.x + (px + 0.5) * cell, 0.0, -(hi.y - (py + 0.5) * cell))
			var wp := g.to_world(local)
			var c := g.column_at(wp.x, wp.z)
			if c < 0 or g.col_first[c] < 0:
				continue
			var top := -1
			for k in g.col_count[c]:
				var n := g.surf_node[g.col_first[c] + k]
				if n >= 0:
					top = n
					break
			if top < 0:
				continue
			var t := clampf((g.node_pos[top].y - g.frame.origin.y + 6.0) / (y_span + 6.0), 0.0, 1.0)
			var col := Color(0.15, 0.25 + 0.75 * t, 0.15)
			if g.fwd[top] == 0:
				col = Color(0.25 + 0.4 * t, 0.25 + 0.4 * t, 0.25 + 0.4 * t)
			elif g.bwd[top] == 0:
				col = Color(1.0, 0.1, 0.1) if confirmed.has(top) else Color(0.6, 0.2, 0.5)
			if marks.has(top):
				col = marks[top]
			img.fill_rect(Rect2i(px * scale, py * scale, scale, scale), col)
	return img
