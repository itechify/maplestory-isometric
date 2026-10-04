class_name TrailDef
extends RefCounted
## One walkable trail between two maps (MAP_ARCHITECTURE.md sections 4.1, 4.3, 4.4, 4.6). Pure.
##
## A trail is the adaptation geometry of a trail link (PortalGraph kind "trail"): MeowDB says the two maps are
## linked, Iteration One built the ribbon of ground between their edge portals. The definition holds:
##   ends      the link's two portal ends ([0] = the sidecar's from end, [1] = its to end), their maps, and the
##             two gates (GateDef, one into each map, on that map's ring line)
##   ribbon    the walkable top of the trail as rows from end 0 to end 1: centreline points, the left and right
##             edge points and the half-width per row (TrailGeometry derives them from the export)
##   zone      RegionIndex's trail zone: XZ points within half-width + zone_margin of the centreline whose height
##             lies within zone_band of the centreline height there (section 4.3: ribbon + 1 m, band +-5 m)
## The trail belongs to the map the player came from: while current_map is either end, its zone is part of that
## map's region set, and only the gate into the OTHER map can commit.

## PortalGraph link id (T_<mapA>_<portalA>__<mapB>_<portalB>; the one-way link T_000000030_out00__000000040).
var link_id: String = ""
## [from map, to map] in the sidecar's order (the ribbon runs from maps[0] to maps[1]).
var maps: PackedStringArray = []
## "<map>.<portal>" of each end (the 000000040 end of the one-way trail is its arrival gate).
var portal_keys: PackedStringArray = []
var one_way: bool = false
## An end is a hidden portal (MeowDB type 1: the 000001020 in00 hedge lane). The lane is walked like any other.
var hidden: bool = false
## Ribbon rows, end 0 -> end 1 (world space). All four arrays have the same size.
var centre: PackedVector3Array = PackedVector3Array()
var left: PackedVector3Array = PackedVector3Array()
var right: PackedVector3Array = PackedVector3Array()
var half_widths: PackedFloat32Array = PackedFloat32Array()
## The walkable top's own side edges from end 0 to end 1 (the export's outline; rows' left/right are the idealized
## edges at the centre +- half-width). The side walls follow these.
var side_a: PackedVector3Array = PackedVector3Array()
var side_b: PackedVector3Array = PackedVector3Array()
## Cumulative XZ arc length of `centre`.
var arc: PackedFloat32Array = PackedFloat32Array()
## Where the ribbon came from: "sidecar" (the export's centreline), "mesh" (derived from the visual glb), "" (none).
var source: String = ""
## Extraction notes (warnings), e.g. a bridge deck appended to the ribbon.
var notes: PackedStringArray = []
## [gate into maps[0], gate into maps[1]] (null where an end has no anchor).
var gates: Array[GateDef] = [null, null]
## Trail zone: margin around the ribbon (XZ) and the vertical band around the centreline.
var zone_margin: float = 1.0
var zone_band: float = 5.0
## Lowest / highest centreline height (kill_y of the maps it touches; the zone's coarse vertical bounds).
var y_lo: float = 0.0
var y_hi: float = 0.0
## XZ bounding rectangle of the zone (fast reject).
var bounds: Rect2 = Rect2()


## True once the ribbon geometry is known.
func has_geometry() -> bool:
	return centre.size() >= 2


func touches(map_id: String) -> bool:
	return map_id in maps


## The map at the other end ("" when `map_id` is not an end).
func other_map(map_id: String) -> String:
	if maps.size() < 2:
		return ""
	if maps[0] == map_id:
		return maps[1]
	if maps[1] == map_id:
		return maps[0]
	return ""


## Index (0 or 1) of `map_id`'s end, -1 when not an end.
func end_of(map_id: String) -> int:
	return maps.find(map_id)


## The portal key of `map_id`'s end ("" when not an end).
func portal_key_of(map_id: String) -> String:
	var i := end_of(map_id)
	return portal_keys[i] if i >= 0 and i < portal_keys.size() else ""


## The gate leading into `map_id` (null when none).
func gate_into(map_id: String) -> GateDef:
	var i := end_of(map_id)
	return gates[i] if i >= 0 and i < gates.size() else null


## Sets the ribbon rows and recomputes arc length, height range and bounds.
func set_ribbon(c: PackedVector3Array, l: PackedVector3Array, r: PackedVector3Array, h: PackedFloat32Array) -> void:
	centre = c
	left = l
	right = r
	half_widths = h
	arc = PackedFloat32Array()
	var acc := 0.0
	y_lo = INF
	y_hi = -INF
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var widest := 0.0
	for i in centre.size():
		if i > 0:
			acc += Vector2(centre[i].x - centre[i - 1].x, centre[i].z - centre[i - 1].z).length()
		arc.append(acc)
		y_lo = minf(y_lo, centre[i].y)
		y_hi = maxf(y_hi, centre[i].y)
		lo = Vector2(minf(lo.x, centre[i].x), minf(lo.y, centre[i].z))
		hi = Vector2(maxf(hi.x, centre[i].x), maxf(hi.y, centre[i].z))
		widest = maxf(widest, half_widths[i] if i < half_widths.size() else 0.0)
	if centre.is_empty():
		y_lo = 0.0
		y_hi = 0.0
		bounds = Rect2()
		return
	var pad := widest + zone_margin
	bounds = Rect2(lo - Vector2(pad, pad), hi - lo + Vector2(pad, pad) * 2.0)


func length() -> float:
	return arc[arc.size() - 1] if not arc.is_empty() else 0.0


## The centreline point nearest `p` in XZ: {"distance" (XZ), "index" (segment start), "t", "point" (Vector3, with
## the interpolated centreline height), "half" (interpolated half-width), "s" (arc length)}. {} without geometry.
func nearest(p: Vector3) -> Dictionary:
	if centre.size() < 2:
		return {}
	var q := Vector2(p.x, p.z)
	var best := {}
	var best_d := INF
	for i in range(centre.size() - 1):
		var a := Vector2(centre[i].x, centre[i].z)
		var b := Vector2(centre[i + 1].x, centre[i + 1].z)
		var ab := b - a
		var t := 0.0 if ab.length_squared() < 1e-12 else clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := q.distance_to(a + ab * t)
		if d < best_d:
			best_d = d
			best = {"distance": d, "index": i, "t": t, "point": centre[i].lerp(centre[i + 1], t),
				"half": lerpf(half_widths[i], half_widths[i + 1], t), "s": lerpf(arc[i], arc[i + 1], t)}
	return best


## True when `p` lies in the trail zone: within half-width + zone_margin of the centreline (XZ) and within
## zone_band of the centreline height there.
func zone_contains(p: Vector3) -> bool:
	if centre.size() < 2 or not bounds.has_point(Vector2(p.x, p.z)):
		return false
	var n := nearest(p)
	return float(n.distance) <= float(n.half) + zone_margin and absf(p.y - (n.point as Vector3).y) <= zone_band


## The zone's outline in XZ (ribbon edges pushed out by zone_margin), for camera bounds and debug drawing.
func zone_polygon() -> PackedVector2Array:
	var out := PackedVector2Array()
	if centre.size() < 2:
		return out
	var l := PackedVector2Array()
	var r := PackedVector2Array()
	for i in centre.size():
		var c := Vector2(centre[i].x, centre[i].z)
		var side := Vector2(left[i].x, left[i].z) - c
		side = side.normalized() if side.length_squared() > 1e-9 else _row_normal(i)
		var reach := half_widths[i] + zone_margin
		l.append(c + side * reach)
		r.append(c - side * reach)
	out.append_array(l)
	r.reverse()
	out.append_array(r)
	return out


## Point at arc length s along the centreline (clamped).
func point_at(s: float) -> Vector3:
	if centre.is_empty():
		return Vector3.ZERO
	s = clampf(s, 0.0, length())
	for i in range(1, centre.size()):
		if arc[i] >= s:
			var seg := arc[i] - arc[i - 1]
			var t := 0.0 if seg <= 1e-6 else (s - arc[i - 1]) / seg
			return centre[i - 1].lerp(centre[i], t)
	return centre[centre.size() - 1]


## The centreline from `from_map`'s end to the other end (reversed when from_map is end 1).
func centreline_from(from_map: String) -> PackedVector3Array:
	var pts := centre.duplicate()
	if end_of(from_map) == 1:
		pts.reverse()
	return pts


func to_dict() -> Dictionary:
	return {"link_id": link_id, "maps": maps, "portals": portal_keys, "one_way": one_way, "hidden": hidden,
		"source": source, "rows": centre.size(), "length_m": snappedf(length(), 0.01),
		"half_width_m": [snappedf(_min_half(), 0.01), snappedf(_max_half(), 0.01)], "y": [snappedf(y_lo, 0.01), snappedf(y_hi, 0.01)],
		"notes": notes}


func _row_normal(i: int) -> Vector2:
	var a := centre[maxi(i - 1, 0)]
	var b := centre[mini(i + 1, centre.size() - 1)]
	var d := Vector2(b.x - a.x, b.z - a.z)
	return Vector2(-d.y, d.x).normalized() if d.length_squared() > 1e-9 else Vector2.RIGHT


func _min_half() -> float:
	var m := INF
	for h in half_widths:
		m = minf(m, h)
	return m if m != INF else 0.0


func _max_half() -> float:
	var m := 0.0
	for h in half_widths:
		m = maxf(m, h)
	return m


func _to_string() -> String:
	return "Trail(%s %s, %d rows, %.1f m)" % [link_id, "->".join(maps), centre.size(), length()]
