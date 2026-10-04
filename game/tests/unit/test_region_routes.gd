extends TestCase
## The identity invariant along every authored path (MAP_ARCHITECTURE.md section 4.3; RegionMonitor samples
## RegionIndex.allowed ten times a second). With the export:
##   - every point of every exported route of every map, every climbable's foot, top and top exit, every player
##     spawn, portal anchor and NPC marker lies in its own map's region: region_of(p, map) is that map and
##     allowed(p, map) holds, so walking any route never logs "identity invariant ... lies in void";
##   - Southperry's ship (the end of Main, ShipDecks, ShipForecastle, ClimbMast, the MastRope) lies outside the layout
##     ring (MapDefinition.footprint_base) and inside the map's region only through its authored region extension
##     (data/misostory/maps/000000060.json);
##   - every trail centreline row lies in one of the trail's two maps or in the trail's own zone: never in the void,
##     never in a third map.
## Pure (no physics): MapDefinitions from the sidecars, trail ribbons from the trail meshes (TrailLoader).

## Up from a route point to the probed feet height (the sidecar points sit on the walkable top).
const LIFT := 0.1


func defs(test_name: String, with_trails: bool = false) -> MapDefinitions:
	if not WorldSidecars.exists():
		print("SKIP %s: game/assets/world not present (run with INCLUDE_WORLD=1)" % test_name)
		return null
	var side := WorldSidecars.load_dir()
	var d := MapDefinitions.build(db(), side)
	if with_trails:
		TrailLoader.attach(d, side)
		d.finish_trails()
	return d


## {what, p} for every authored point of `def`'s sidecar: route points, climbable ends, player spawns, portal anchors,
## NPC markers.
func authored_points(def: MapDefinition) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sc := def.sidecar
	for r in sc.get("routes", []):
		if not (r is Dictionary):
			continue
		var i := 0
		for pt in r.get("points", []):
			out.append({"what": "route %s[%d]" % [String(r.get("name", "?")), i], "p": WorldSidecars.vec3(pt)})
			i += 1
	for c in sc.get("climbables", []):
		if not (c is Dictionary):
			continue
		for key in ["bottom", "top", "top_exit", "foot_ground"]:
			if c.get(key, null) is Array:
				out.append({"what": "climbable %s.%s" % [String(c.get("name", "?")), key], "p": WorldSidecars.vec3(c[key])})
	for key in ["player_spawns", "portals", "npcs"]:
		for m in sc.get(key, []):
			if m is Dictionary and (m.has("xform") or m.has("position")):
				out.append({"what": "%s %s" % [key, str(m.get("name", m.get("index", "?")))], "p": WorldSidecars.marker_xform(m).origin})
	if sc.get("player_start", null) is Dictionary:
		out.append({"what": "player_start", "p": WorldSidecars.marker_xform(sc.player_start).origin})
	return out


func test_every_route_point_lies_in_its_own_map() -> void:
	var d := defs("test_every_route_point_lies_in_its_own_map")
	if d == null:
		return
	assert_eq(d.errors.size(), 0, "errors: %s" % "; ".join(d.errors))
	var ri := RegionIndex.from_defs(d)
	var points := 0
	var routes := 0
	var wrong := PackedStringArray()
	for id in d.ids():
		var def := d.get_def(id)
		routes += (def.sidecar.get("routes", []) as Array).size()
		for a in authored_points(def):
			var p: Vector3 = a.p + Vector3.UP * LIFT
			points += 1
			var r := ri.region_of(p, id)
			if String(r.kind) != RegionIndex.KIND_MAP or String(r.id) != id or not ri.allowed(p, id):
				wrong.append("%s %s at %s lies in %s %s" % [id, String(a.what), a.p, String(r.kind), String(r.id)])
	assert_true(routes >= 25, "routes walked: %d" % routes)
	assert_true(points > 2000, "authored points walked: %d" % points)
	assert_eq(wrong.size(), 0, "%d points outside their map's region; first: %s" % [wrong.size(), "; ".join(wrong.slice(0, 5))])


func test_the_southperry_ship_is_in_the_region_through_its_extension() -> void:
	var d := defs("test_the_southperry_ship_is_in_the_region_through_its_extension")
	if d == null:
		return
	var def := d.get_def("000000060")
	assert_eq(def.region_extensions.size(), 1, "one authored region extension (the ship)")
	assert_eq(String(def.region_extensions[0].name), "ship_victoria", "the ship extension")
	assert_true(def.footprint.size() > def.footprint_base.size(), "the merged footprint has the ship's outline (%d vertices)" % def.footprint.size())
	var ri := RegionIndex.from_defs(d)
	var outside_layout := 0
	var by_route := {}
	for r in def.sidecar.get("routes", []):
		for pt in r.get("points", []):
			var p := WorldSidecars.vec3(pt) + Vector3.UP * LIFT
			if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), def.footprint_base):
				continue
			outside_layout += 1
			by_route[String(r.name)] = int(by_route.get(String(r.name), 0)) + 1
			assert_true(def.footprint_contains(p), "%s point %s inside the extended footprint" % [String(r.name), p])
			assert_true(ri.allowed(p, "000000060"), "%s point %s allowed in 000000060" % [String(r.name), p])
	var names := PackedStringArray(by_route.keys())
	names.sort()
	assert_eq(names, PackedStringArray(["ClimbMast", "Main", "ShipDecks", "ShipForecastle"]), "the routes that board the ship")
	assert_true(outside_layout >= 30, "ship route points beyond the layout ring: %d" % outside_layout)
	# The ship is the map's own: no other map's region reaches it.
	for r in def.sidecar.get("routes", []):
		for pt in r.get("points", []):
			var maps := ri.maps_at(WorldSidecars.vec3(pt) + Vector3.UP * LIFT)
			assert_eq(maps, PackedStringArray(["000000060"]), "%s point in %s" % [String(r.name), str(maps)])


func test_every_trail_row_lies_in_its_maps_or_its_zone() -> void:
	var d := defs("test_every_trail_row_lies_in_its_maps_or_its_zone", true)
	if d == null:
		return
	var ri := RegionIndex.from_defs(d)
	var rows := 0
	var wrong := PackedStringArray()
	for t in d.trail_list():
		if not t.has_geometry():
			wrong.append("%s has no ribbon" % t.link_id)
			continue
		for c in t.centre:
			var p := c + Vector3.UP * LIFT
			rows += 1
			var r := ri.region_of(p, t.maps[0])
			var ok := String(r.kind) != RegionIndex.KIND_VOID
			for m in (r.maps as PackedStringArray):
				ok = ok and m in t.maps
			if not ok:
				wrong.append("%s row %s lies in %s %s" % [t.link_id, c, String(r.kind), String(r.id)])
	assert_true(rows > 1000, "trail rows walked: %d" % rows)
	assert_eq(wrong.size(), 0, "%d trail rows outside their maps and zone; first: %s" % [wrong.size(), "; ".join(wrong.slice(0, 5))])
