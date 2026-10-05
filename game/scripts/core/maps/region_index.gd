class_name RegionIndex
extends RefCounted
## Which region a world point lies in (MAP_ARCHITECTURE.md section 4.3). Pure.
##
## Regions:
##   map    every map footprint + ring offset in XZ (MapDefinition.footprint, the containment ring line, with the
##          map's authored region extensions such as Southperry's ship), with the ring's vertical span: the map
##          chunk's bounds from containment.margin_below_m below to margin_above_m above. Interiors are maps on the
##          interior stage; their footprint is the room box.
##   trail  every trail with geometry (TrailDef): within half-width + zone_margin of its centreline, within
##          zone_band of the centreline height (section 4.3: ribbon + 1 m, +-5 m).
## Map footprints take precedence over trail zones (a trail mouth inside a footprint is that map's).
##
## Uses:
##   - the identity invariant (allowed()): the player's last ground point must lie in current_map, a trail touching
##     current_map, or the map of an armed gate (RegionMonitor samples it ten times a second);
##   - the SafeGround filter and save snapping (a resume point only inside current_map; on a trail the save keeps
##     the trail's portal, section 4.9);
##   - the HUD line on trails (MapSession.trail_changed), the debug overlay.
## current_map itself is never inferred from a region: MapSession owns it.

const KIND_MAP := "map"
const KIND_TRAIL := "trail"
const KIND_VOID := "void"

var _zones: Array[Dictionary] = []
var _trails: Array[TrailDef] = []


static func from_defs(defs: MapDefinitions) -> RegionIndex:
	var r := RegionIndex.new()
	var below := defs.tuning.num("containment", "margin_below_m")
	var above := defs.tuning.num("containment", "margin_above_m")
	for id in defs.ids():
		var def := defs.get_def(id)
		if def.footprint.size() < 3:
			continue
		r._zones.append({"kind": KIND_MAP, "id": id, "polygon": def.footprint, "y_lo": def.y_min - below, "y_hi": def.y_max + above})
	for t in defs.trail_list():
		if t.has_geometry():
			r._trails.append(t)
	return r


## An index over explicit regions (tests, tools): `maps` = [{id, polygon (world XZ), y_lo, y_hi}], `trails` with
## geometry.
static func make(maps: Array[Dictionary], trails: Array[TrailDef]) -> RegionIndex:
	var r := RegionIndex.new()
	for m in maps:
		r._zones.append({"kind": KIND_MAP, "id": String(m.id), "polygon": m.polygon, "y_lo": float(m.get("y_lo", -INF)),
			"y_hi": float(m.get("y_hi", INF))})
	for t in trails:
		if t.has_geometry():
			r._trails.append(t)
	return r


## {"kind": "map" | "trail" | "void", "id": map id or trail link id or "", "maps": the maps the region belongs to}.
## When several regions contain the point, `prefer` (the current map) wins: its own footprint, else a trail
## touching it; otherwise the first map by id, then the first trail.
func region_of(pos: Vector3, prefer: String = "") -> Dictionary:
	var found := maps_at(pos)
	if not found.is_empty():
		var id := prefer if prefer != "" and prefer in found else found[0]
		return {"kind": KIND_MAP, "id": id, "maps": PackedStringArray([id])}
	var trails := trails_at(pos)
	if trails.is_empty():
		return {"kind": KIND_VOID, "id": "", "maps": PackedStringArray()}
	var pick: TrailDef = trails[0]
	for t in trails:
		if prefer != "" and t.touches(prefer):
			pick = t
			break
	return {"kind": KIND_TRAIL, "id": pick.link_id, "maps": pick.maps.duplicate()}


## Every map region containing the point, sorted by id.
func maps_at(pos: Vector3) -> PackedStringArray:
	var out: PackedStringArray = []
	var xz := Vector2(pos.x, pos.z)
	for z in _zones:
		if pos.y < float(z.y_lo) or pos.y > float(z.y_hi):
			continue
		if Geometry2D.is_point_in_polygon(xz, z.polygon):
			out.append(String(z.id))
	return out


## Every trail zone containing the point (map precedence is not applied here).
func trails_at(pos: Vector3) -> Array[TrailDef]:
	var out: Array[TrailDef] = []
	for t in _trails:
		if t.zone_contains(pos):
			out.append(t)
	return out


## The identity invariant (section 4.3): `pos` lies in `current_map`, in a trail touching it (outside every map
## footprint), or in the region of a map listed in `armed_maps` (the maps of armed gates).
func allowed(pos: Vector3, current_map: String, armed_maps: PackedStringArray = PackedStringArray()) -> bool:
	var found := maps_at(pos)
	if not found.is_empty():
		if current_map in found:
			return true
		for m in armed_maps:
			if m in found:
				return true
		return false
	for t in trails_at(pos):
		if t.touches(current_map):
			return true
	return false


## True when `pos` is a valid standing point for `current_map` alone: its footprint, or a trail touching it.
func in_map_or_its_trails(pos: Vector3, current_map: String) -> bool:
	return allowed(pos, current_map)


func zone_count() -> int:
	return _zones.size() + _trails.size()


func map_zone_count() -> int:
	return _zones.size()


func trail_zone_count() -> int:
	return _trails.size()
