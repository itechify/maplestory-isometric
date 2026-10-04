extends TestCase
## Camera bounds and kill_y with trails (MAP_ARCHITECTURE.md sections 4.6 and 4.11, milestone M2): a map's
## camera_bounds is its footprint united with the zones of the edge-mode trails touching it (a warp-mode link's
## trail is scenery and stays out), recomputed when a link mode changes; kill_y reaches below the lowest point of
## the map's trails. Needs the export; prints one SKIP line without it.

var defs: MapDefinitions = null


func before_each() -> void:
	if not WorldSidecars.exists() or defs != null:
		return
	var side := WorldSidecars.load_dir()
	defs = MapDefinitions.build(db(), side)
	TrailLoader.attach(defs, side)
	defs.finish_trails()


func test_bounds_reach_along_the_edge_trails() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_bounds_reach_along_the_edge_trails: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	defs.apply_configured_link_modes()
	for id in defs.ids():
		var def := defs.get_def(id)
		for t in defs.trails_of(id):
			var far := t.centreline_from(id)
			var p := far[far.size() - 1]
			var inside := Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), def.camera_bounds)
			var mid := t.point_at(t.length() * 0.5)
			var mid_inside := Geometry2D.is_point_in_polygon(Vector2(mid.x, mid.z), def.camera_bounds)
			if defs.graph.is_edge(t.link_id):
				assert_true(inside and mid_inside, "%s camera bounds reach along %s" % [id, t.link_id])
			else:
				assert_false(mid_inside, "%s camera bounds leave out the warp-mode %s" % [id, t.link_id])
	# 000001000 with eight trails: its bounds are much wider than its footprint.
	var fw := _area(defs.get_def("000001000").footprint)
	var cw := _area(defs.get_def("000001000").camera_bounds)
	assert_true(cw > fw * 1.2, "000001000 bounds %.0f m2 vs footprint %.0f m2" % [cw, fw])


func test_link_modes_change_the_bounds() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_link_modes_change_the_bounds: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	defs.graph.set_link_mode("all", PortalDef.LINK_WARP)
	defs.refresh_camera_bounds()
	for id in defs.ids():
		var def := defs.get_def(id)
		assert_eq(def.camera_bounds, def.footprint, "%s warp mode: the footprint (M1)" % id)
	defs.apply_configured_link_modes()
	defs.refresh_camera_bounds()
	assert_ne(defs.get_def("000000040").camera_bounds, defs.get_def("000000040").footprint, "edge mode widens them again")


func test_kill_y_covers_the_trails() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_kill_y_covers_the_trails: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var margin := defs.tuning.num("fall_recovery", "kill_y_margin_m")
	for t in defs.trail_list():
		for m in t.maps:
			assert_true(defs.get_def(m).kill_y <= t.y_lo - margin + 1e-3, "%s kill_y %.2f vs %s low %.2f" % [m, defs.get_def(m).kill_y, t.link_id, t.y_lo])
	# The 30 -> 40 trail falls 9.8 m below 000000030: its kill_y follows it.
	var t30 := defs.trail("T_000000030_out00__000000040")
	assert_near(defs.get_def("000000030").kill_y, t30.y_lo - margin, 0.01, "000000030 kill_y from its trail")
	defs.finish_trails()
	assert_near(defs.get_def("000000030").kill_y, t30.y_lo - margin, 0.01, "finish_trails is idempotent")


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5
