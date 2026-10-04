class_name MobRegion
extends RefCounted
## Where a map's monsters may walk (MAP_ARCHITECTURE.md section 4.7.4): the map's mob region, which is the layout
## footprint inset by spawns.mob_region_inset_m (SpawnSlotPlanner.mob_region), minus a disc of
## spawns.slot_portal_clearance_m around every portal arrival and arrival gate (the same clearance spawn slots keep).
## Pure XZ geometry. Trails lie outside every footprint and portals sit inside their discs, so a monster that obeys
## this never enters a trail or crosses a portal.
##
## A step is judged by allows_step(from, to): it is allowed when `to` is inside, or when it does not make a bad
## position worse (a monster restored or knocked slightly outside walks back in instead of freezing).

var polygon: PackedVector2Array = PackedVector2Array()
## {"center": Vector2, "radius": float}
var discs: Array[Dictionary] = []


## The region of `def` with the world's tuning. Unbounded (allows everything) without a footprint.
static func from_def(def: MapDefinition, tuning: WorldTuning) -> MobRegion:
	var r := MobRegion.new()
	if def == null:
		return r
	if tuning != null:
		r.polygon = SpawnSlotPlanner.mob_region(def, tuning)
	else:
		r.polygon = def.footprint_layout
	var radius := tuning.num("spawns", "slot_portal_clearance_m") if tuning != null else 0.0
	if radius > 0.0:
		for p in def.portals:
			var o := p.spawn_transform.origin
			if p.spawn_transform == Transform3D.IDENTITY and not p.has_anchor:
				continue  # never placed (no export): no disc at the world origin
			r.discs.append({"center": Vector2(o.x, o.z), "radius": radius})
	return r


## A region from raw parts (tests, sandboxes).
static func make(poly: PackedVector2Array, disc_list: Array[Dictionary] = []) -> MobRegion:
	var r := MobRegion.new()
	r.polygon = poly
	r.discs = disc_list
	return r


func is_bounded() -> bool:
	return polygon.size() >= 3 or not discs.is_empty()


## True when the point lies inside the polygon (or there is none) and outside every disc.
func contains(p: Vector3) -> bool:
	return _in_polygon(Vector2(p.x, p.z)) and _disc_violation(Vector2(p.x, p.z)) < 0.0


## Whether a monster at `from` may move to `to`.
func allows_step(from: Vector3, to: Vector3) -> bool:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	if polygon.size() >= 3 and not _in_polygon(b):
		# Outside: only moves that get closer to the polygon are allowed.
		if _in_polygon(a) or _outside_distance(b) >= _outside_distance(a):
			return false
	for d in discs:
		var c: Vector2 = d.center
		var r := float(d.radius)
		var db := b.distance_to(c)
		if db < r and db <= a.distance_to(c):
			return false
	return true


## Signed distance (m) from a point to the region's border: negative inside, positive outside. Discs count.
func outside_distance(p: Vector3) -> float:
	var q := Vector2(p.x, p.z)
	var d := -INF
	if polygon.size() >= 3:
		d = _outside_distance(q) if not _in_polygon(q) else -_edge_distance(q)
	return maxf(d, _disc_violation(q))


func _in_polygon(q: Vector2) -> bool:
	if polygon.size() < 3:
		return true
	return Geometry2D.is_point_in_polygon(q, polygon)


func _outside_distance(q: Vector2) -> float:
	return _edge_distance(q)


func _edge_distance(q: Vector2) -> float:
	var best := INF
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		best = minf(best, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
	return best


## How deep the point is inside the worst disc (positive = inside a disc), -INF without discs.
func _disc_violation(q: Vector2) -> float:
	var worst := -INF
	for d in discs:
		worst = maxf(worst, float(d.radius) - q.distance_to(d.center))
	return worst
