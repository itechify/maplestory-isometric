extends TestCase
## ContainmentBuilder rings on concave footprints and MapDefinitions.apply_region_extensions, pure (shapes are
## checked by their transforms; no physics, no export):
##   - outward_side / edge_outward follow the winding, so every wall stands outside a concave ring (an L shape) in
##     either winding; convex_corners marks the convex corners only;
##   - wall pieces are lengthened only at convex corners: the concave corner gets no pillar inside the region, the
##     convex corners stay closed;
##   - add_kept_ring puts the layout's own ring line back where an extension opened it, up to the given height;
##   - region extensions: ring_line_local in the map frame is merged into the footprint, footprint_base keeps the
##     layout ring, and an entry without a reason, with too few points or that does not overlap is refused.

const T := 0.5


## L shape: 10 x 10 with the quadrant x 5..10, y 5..10 cut away (the concave corner at (5, 5)).
func l_shape(ccw: bool = true) -> PackedVector2Array:
	var p := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 5), Vector2(5, 5), Vector2(5, 10), Vector2(0, 10)])
	if not ccw:
		p.reverse()
	return p


## True when the XZ point (at the shapes' mid height) lies inside one of the body's boxes.
func in_wall(body: StaticBody3D, p: Vector2, y: float = 5.0) -> bool:
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var local := cs.transform.affine_inverse() * Vector3(p.x, y, p.y)
		var half := (cs.shape as BoxShape3D).size * 0.5
		if absf(local.x) <= half.x + 1e-4 and absf(local.y) <= half.y + 1e-4 and absf(local.z) <= half.z + 1e-4:
			return true
	return false


func test_outward_side_and_convex_corners_follow_the_winding() -> void:
	for ccw in [true, false]:
		var poly := l_shape(ccw)
		var side := ContainmentBuilder.outward_side(poly)
		for i in poly.size():
			var mid := (poly[i] + poly[(i + 1) % poly.size()]) * 0.5
			var n := ContainmentBuilder.edge_outward(poly, i, side)
			assert_false(Geometry2D.is_point_in_polygon(mid + n * 0.1, poly), "edge %d normal points out (ccw %s)" % [i, str(ccw)])
			assert_true(Geometry2D.is_point_in_polygon(mid - n * 0.1, poly), "edge %d inside is inward (ccw %s)" % [i, str(ccw)])
		var convex := ContainmentBuilder.convex_corners(poly)
		var concave := 0
		for i in poly.size():
			if convex[i] == 0:
				concave += 1
				assert_eq(poly[i], Vector2(5, 5), "the only concave corner (ccw %s)" % str(ccw))
		assert_eq(concave, 1, "one concave corner (ccw %s)" % str(ccw))


func test_a_concave_ring_stands_outside_and_is_closed() -> void:
	for ccw in [true, false]:
		var body := ContainmentBuilder.build_ring(l_shape(ccw), 0.0, 10.0, T)
		# Every piece's centre lies outside the region.
		for c in body.get_children():
			var o := (c as Node3D).transform.origin
			assert_false(Geometry2D.is_point_in_polygon(Vector2(o.x, o.z), l_shape()), "%s stands outside (ccw %s)" % [c.name, str(ccw)])
		# No pillar inside the region at the concave corner (5, 5), walls just outside it on both of its edges.
		assert_false(in_wall(body, Vector2(4.8, 4.8)), "nothing inside the concave corner (ccw %s)" % str(ccw))
		assert_false(in_wall(body, Vector2(4.6, 5.2)), "the wall on edge y = 5 does not run past the corner (ccw %s)" % str(ccw))
		assert_true(in_wall(body, Vector2(7.0, 5.25)), "wall outside edge y = 5 (ccw %s)" % str(ccw))
		assert_true(in_wall(body, Vector2(5.25, 7.0)), "wall outside edge x = 5 (ccw %s)" % str(ccw))
		assert_true(in_wall(body, Vector2(5.25, 5.25)), "the concave corner is closed (ccw %s)" % str(ccw))
		# Convex corners are closed diagonally.
		for corner in [Vector2(-0.25, -0.25), Vector2(10.25, -0.25), Vector2(10.25, 5.25), Vector2(5.25, 10.25), Vector2(-0.25, 10.25)]:
			assert_true(in_wall(body, corner), "convex corner %s closed (ccw %s)" % [corner, str(ccw)])
		body.free()


func test_kept_ring_restores_the_layout_line_under_an_extension() -> void:
	var base := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	# An extension below the edge y = 0 between x 4 and 7, overlapping the base.
	var ext := PackedVector2Array([Vector2(4, 1), Vector2(4, -6), Vector2(7, -6), Vector2(7, 1)])
	var body := StaticBody3D.new()
	var n := ContainmentBuilder.add_kept_ring(body, base, ext, -2.0, 3.0, T)
	assert_eq(n, 1, "one kept piece (the base edge inside the extension)")
	assert_true(in_wall(body, Vector2(5.5, -0.25), 0.0), "the kept wall stands outside the base line under the extension")
	assert_false(in_wall(body, Vector2(5.5, -0.25), 3.5), "and only up to its top")
	assert_false(in_wall(body, Vector2(3.0, -0.25), 0.0), "not beyond the extension")
	assert_eq(ContainmentBuilder.add_kept_ring(body, base, ext, 3.0, 3.0, T), 0, "no wall when the top is not above the foot")
	body.free()


func frame_def() -> MapDefinition:
	var def := MapDefinition.new()
	def.map_id = "X"
	# Map frame: yawed 90 degrees, origin (100, 1, 200); local (x, y) -> world frame * (x, 0, -y).
	def.frame = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(100, 1, 200))
	var layout := PackedVector2Array()
	for c in [Vector2(0, 0), Vector2(20, 0), Vector2(20, 10), Vector2(0, 10)]:
		var w := def.frame * Vector3(c.x, 0.0, -c.y)
		layout.append(Vector2(w.x, w.z))
	def.footprint_layout = layout
	var grown := Geometry2D.offset_polygon(layout, 1.0, Geometry2D.JOIN_MITER)
	def.footprint = grown[0]
	def.footprint_base = def.footprint.duplicate()
	return def


func world_xz(def: MapDefinition, x: float, y: float) -> Vector3:
	return def.frame * Vector3(x, 0.0, -y)


func test_region_extensions_merge_in_the_map_frame() -> void:
	var def := frame_def()
	var outside := world_xz(def, 10.0, -4.0)
	assert_false(def.footprint_contains(outside), "4 m in front of the layout is outside before the extension")
	var errs := MapDefinitions.apply_region_extensions(def, [{"name": "pier", "ring_line_local": [[8, -0.5], [8, -6], [12, -6], [12, -0.5]],
		"keep_footprint_ring_below_y": 2.5, "reason": "test", "verified": false}])
	assert_eq(errs.size(), 0, "errors: %s" % "; ".join(errs))
	assert_true(def.footprint_contains(outside), "inside after the extension")
	assert_false(def.footprint_contains(world_xz(def, 14.0, -4.0)), "beside the extension stays outside")
	assert_true(def.footprint_contains(world_xz(def, 10.0, 5.0)), "the layout stays inside")
	assert_false(Geometry2D.is_point_in_polygon(Vector2(outside.x, outside.z), def.footprint_base), "footprint_base keeps the layout ring")
	assert_eq(def.region_extensions.size(), 1, "the extension is recorded")
	assert_eq(float(def.region_extensions[0].keep_ring_below_y), 2.5, "its kept-ring height")
	var corner := world_xz(def, 8.0, -6.0)
	assert_true(Vector2(corner.x, corner.z).distance_to((def.region_extensions[0].ring_line as PackedVector2Array)[1]) < 0.001, "ring line in world XZ")


func test_bad_region_extensions_are_refused() -> void:
	var def := frame_def()
	var before := def.footprint.duplicate()
	var errs := MapDefinitions.apply_region_extensions(def, [
		{"name": "no_reason", "ring_line_local": [[8, -0.5], [8, -6], [12, -6]], "verified": false},
		{"name": "two_points", "ring_line_local": [[8, -0.5], [8, -6]], "reason": "test", "verified": false},
		{"name": "detached", "ring_line_local": [[8, -5], [8, -9], [12, -9], [12, -5]], "reason": "test", "verified": false},
	])
	assert_eq(errs.size(), 3, "three refusals: %s" % "; ".join(errs))
	assert_eq(def.footprint, before, "the footprint is unchanged")
	assert_eq(def.region_extensions.size(), 0, "nothing recorded")
	var no_keep := MapDefinitions.apply_region_extensions(def, [{"name": "ok", "ring_line_local": [[8, -0.5], [8, -3], [12, -3], [12, -0.5]],
		"reason": "test", "verified": false}])
	assert_eq(no_keep.size(), 0, "a valid extension merges")
	assert_true(is_nan(float(def.region_extensions[0].keep_ring_below_y)), "no kept ring without keep_footprint_ring_below_y")
	# No export geometry (no footprint): nothing to extend, nothing reported.
	var bare := MapDefinition.new()
	bare.map_id = "Y"
	assert_eq(MapDefinitions.apply_region_extensions(bare, [{"name": "pier", "ring_line_local": [[0, 0], [1, 0], [1, 1]],
		"reason": "test", "verified": false}]).size(), 0, "no footprint: no error")
	assert_eq(bare.region_extensions.size(), 0, "no footprint: nothing recorded")
	assert_eq(bare.footprint.size(), 0, "no footprint: none made up")
