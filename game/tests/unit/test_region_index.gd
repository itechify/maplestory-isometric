extends TestCase
## RegionIndex (MAP_ARCHITECTURE.md section 4.3) with trail zones, pure: map footprints take precedence over trail
## zones; a trail zone is the ribbon plus zone_margin within zone_band of the centreline height; the identity
## invariant allows current_map, a trail touching it (outside every footprint) and the map of an armed gate, and
## nothing else. With the export: every trail between its gates is in no map region and in its own zone.

## Two square maps A (x 0..10) and B (x 20..30), z -5..5, joined by a straight trail at z = 0 from x 9 to 21
## (half-width 1.9), y = 0; and a third map C far away with its own trail C-D.
func index() -> RegionIndex:
	var a := PackedVector2Array([Vector2(0, -5), Vector2(10, -5), Vector2(10, 5), Vector2(0, 5)])
	var b := PackedVector2Array([Vector2(20, -5), Vector2(30, -5), Vector2(30, 5), Vector2(20, 5)])
	var c := PackedVector2Array([Vector2(100, -5), Vector2(110, -5), Vector2(110, 5), Vector2(100, 5)])
	var maps: Array[Dictionary] = [{"id": "A", "polygon": a, "y_lo": -5.0, "y_hi": 20.0}, {"id": "B", "polygon": b, "y_lo": -5.0, "y_hi": 20.0},
		{"id": "C", "polygon": c, "y_lo": -5.0, "y_hi": 20.0}]
	var trails: Array[TrailDef] = [trail("T_AB", "A", "B", 9.0, 21.0, 0.0), trail("T_CD", "C", "D", 109.0, 121.0, 0.0)]
	return RegionIndex.make(maps, trails)


func trail(id: String, a: String, b: String, x0: float, x1: float, y: float) -> TrailDef:
	var t := TrailDef.new()
	t.link_id = id
	t.maps = PackedStringArray([a, b])
	t.zone_margin = 1.0
	t.zone_band = 5.0
	var c := PackedVector3Array()
	var l := PackedVector3Array()
	var r := PackedVector3Array()
	var h := PackedFloat32Array()
	var x := x0
	while x <= x1 + 1e-6:
		c.append(Vector3(x, y, 0))
		l.append(Vector3(x, y, 1.9))
		r.append(Vector3(x, y, -1.9))
		h.append(1.9)
		x += 0.5
	t.set_ribbon(c, l, r, h)
	return t


func test_map_footprints_win_over_trail_zones() -> void:
	var ri := index()
	assert_eq(ri.region_of(Vector3(5, 0, 0)), {"kind": "map", "id": "A", "maps": PackedStringArray(["A"])}, "inside A")
	assert_eq(String(ri.region_of(Vector3(9.5, 0, 0)).kind), "map", "the trail mouth inside A's footprint is A's")
	var mid := ri.region_of(Vector3(15, 0.5, 0), "A")
	assert_eq(String(mid.kind), "trail", "between the maps: the trail")
	assert_eq(String(mid.id), "T_AB", "trail id")
	assert_eq(mid.maps, PackedStringArray(["A", "B"]), "the trail's maps")
	assert_eq(String(ri.region_of(Vector3(15, 0, 3.4)).kind), "void", "beyond half-width + margin")
	assert_eq(String(ri.region_of(Vector3(15, 0, 2.8)).kind), "trail", "within half-width + margin")
	assert_eq(String(ri.region_of(Vector3(15, 6.0, 0)).kind), "void", "above the zone band")
	assert_eq(String(ri.region_of(Vector3(50, 0, 0)).kind), "void", "nowhere")
	assert_eq(ri.trail_zone_count(), 2, "two trail zones")
	assert_eq(ri.map_zone_count(), 3, "three map zones")


func test_identity_invariant() -> void:
	var ri := index()
	assert_true(ri.allowed(Vector3(5, 0, 0), "A"), "in the current map")
	assert_true(ri.allowed(Vector3(15, 0, 0), "A"), "on a trail touching the current map (the trail is A's)")
	assert_true(ri.allowed(Vector3(15, 0, 0), "B"), "the same trail belongs to B when B is current")
	assert_false(ri.allowed(Vector3(25, 0, 0), "A"), "in B while A is current")
	assert_true(ri.allowed(Vector3(25, 0, 0), "A", PackedStringArray(["B"])), "in B with B's gate armed")
	assert_false(ri.allowed(Vector3(115, 0, 0), "A"), "on a trail of other maps")
	assert_false(ri.allowed(Vector3(50, 0, 0), "A"), "in the void")
	assert_true(ri.in_map_or_its_trails(Vector3(15, 0, 0), "B"), "SafeGround on B's trail")
	assert_false(ri.in_map_or_its_trails(Vector3(25, 0, 0), "A"), "never SafeGround in another map, armed or not")


func test_trail_zone_geometry() -> void:
	var t := trail("T", "A", "B", 0.0, 10.0, 2.0)
	assert_near(t.length(), 10.0, 1e-4, "length")
	assert_true(t.zone_contains(Vector3(5, 2, 2.8)), "half-width + margin")
	assert_false(t.zone_contains(Vector3(5, 2, 3.0)), "past the margin")
	assert_true(t.zone_contains(Vector3(5, 6.9, 0)), "within the band")
	assert_false(t.zone_contains(Vector3(5, 7.1, 0)), "above the band")
	assert_eq(t.other_map("A"), "B", "other map")
	assert_eq(t.other_map("C"), "", "not an end")
	var poly := t.zone_polygon()
	assert_true(Geometry2D.is_point_in_polygon(Vector2(5, 2.8), poly), "zone polygon covers the margin")
	assert_eq(t.centreline_from("B")[0], Vector3(10, 2, 0), "centreline from B starts at B's end")


## With the export: between its gates every trail lies in no map region, and inside its own zone; its mouths lie in
## its maps' regions.
func test_trails_of_the_export() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_trails_of_the_export: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var side := WorldSidecars.load_dir()
	var d := MapDefinitions.build(db(), side)
	TrailLoader.attach(d, side)
	d.finish_trails()
	var ri := RegionIndex.from_defs(d)
	assert_eq(ri.trail_zone_count(), 20, "20 trail zones")
	for t in d.trail_list():
		var first := t.centre[0] + Vector3.UP * 0.1
		var last := t.centre[t.centre.size() - 1] + Vector3.UP * 0.1
		if t.gates[0].signed_distance(first) > 0.05:
			assert_true(t.maps[0] in ri.maps_at(first), "%s mouth in %s" % [t.link_id, t.maps[0]])
		if t.gates[1].signed_distance(last) > 0.05:
			assert_true(t.maps[1] in ri.maps_at(last), "%s mouth in %s" % [t.link_id, t.maps[1]])
		var mid := t.point_at(t.length() * 0.5) + Vector3.UP * 0.1
		var r := ri.region_of(mid, t.maps[0])
		assert_eq(String(r.kind), "trail", "%s middle is trail (%s)" % [t.link_id, str(r)])
		assert_true(ri.allowed(mid, t.maps[0]) and ri.allowed(mid, t.maps[1]), "%s belongs to both its maps" % t.link_id)
