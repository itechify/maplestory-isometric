extends TestCase
## MinimapProjection (pure, no world needed): the minimap is the gameplay camera's own orthographic view, scaled
## down. Against a real orthographic Camera3D with the shared gameplay basis, project() differs from
## unproject_position() by one uniform scale and an offset only; ground further from the camera and raised points sit
## higher; fit() keeps the aspect ratio inside the widget; clamp_to_rect() keeps the direction to the player.

## The gameplay camera basis every sidecar carries (cameras.gameplay.xform: right, up, back), the same as camera.json's
## default pitch 40 / yaw -45. Test input only: the game reads it from the sidecar or the live rig.
const XFORM := [0.70711, 0, 0.70711, 0.45452, 0.76604, -0.45452, -0.54168, 0.64279, 0.54168, 0, 0, 0]

var holder: Node = null


func parity_keys() -> Dictionary:
	return {
		"test_project_matches_the_orthographic_camera": ["ui:minimap-projection"],
		"test_further_and_higher_points_sit_higher": ["ui:minimap-projection"],
	}


func before_each() -> void:
	holder = Node.new()
	_parent().add_child(holder)


func after_each() -> void:
	holder.free()


func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root.get_child(tree.root.get_child_count() - 1)


func _points() -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var out := PackedVector3Array()
	for i in 20:
		out.append(Vector3(rng.randf_range(-30, 30), rng.randf_range(-4, 8), rng.randf_range(-30, 30)))
	return out


func test_project_matches_the_orthographic_camera() -> void:
	var proj := MinimapProjection.from_xform_array(XFORM)
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 900)
	vp.disable_3d = false
	holder.add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = 40.0
	cam.near = 1.0
	cam.far = 1000.0
	vp.add_child(cam)
	var b := CameraMath.basis_from_xform_array(XFORM)
	cam.global_transform = Transform3D(b, Vector3(3, 2, -5) - (-b.z) * 150.0)
	cam.make_current()
	var pts := _points()
	# Scale and offset from the first two points, then every other point must agree.
	var s0 := cam.unproject_position(pts[0])
	var s1 := cam.unproject_position(pts[1])
	var m0 := proj.project(pts[0])
	var m1 := proj.project(pts[1])
	var scale := (s1 - s0).length() / (m1 - m0).length()
	assert_near(scale, 900.0 / 40.0, 0.05, "px per metre = viewport height / ortho size")
	var offset := s0 - m0 * scale
	for p in pts:
		var want := cam.unproject_position(p)
		var got := proj.project(p) * scale + offset
		assert_true(want.distance_to(got) < 0.05, "%s: camera %s, minimap %s" % [p, want, got])


func test_further_and_higher_points_sit_higher() -> void:
	var proj := MinimapProjection.from_xform_array(XFORM)
	var axes := CameraMath.ground_axes(CameraMath.basis_from_xform_array(XFORM))
	var p := Vector3(10, 4, -3)
	assert_true(proj.project(p + axes[1] * 5.0).y < proj.project(p).y, "further along the camera's ground forward = higher (W is up)")
	assert_true(proj.project(p + Vector3.UP * 3.0).y < proj.project(p).y, "a raised tier sits higher, as in the game view")
	assert_true(proj.project(p + axes[0] * 5.0).x > proj.project(p).x, "camera right is minimap right")
	assert_near(proj.project(p + axes[0]).x - proj.project(p).x, 1.0, 1e-4, "one metre right = one minimap metre")
	assert_true(proj.project_dir(axes[1]).dot(Vector2.UP) > 0.9, "the ground forward direction points up")
	assert_eq(proj.project_dir(proj.forward * -1.0), Vector2.ZERO, "straight at the camera has no minimap direction")
	assert_true(proj.depth(p + axes[1] * 5.0) > proj.depth(p), "depth grows away from the camera")


func test_for_map_prefers_the_live_basis() -> void:
	var def := MapDefinition.new()
	def.sidecar = {"cameras": {"gameplay": {"xform": XFORM}}}
	var from_sidecar := MinimapProjection.for_map(def)
	assert_true(from_sidecar != null and from_sidecar.right.is_equal_approx(Vector3(0.70711, 0, 0.70711).normalized()),
		"the sidecar's gameplay camera")
	var live := CameraMath.basis_from_angles(30.0, 10.0)
	assert_true(MinimapProjection.for_map(def, live).right.is_equal_approx(live.x), "the live rig's basis wins")
	assert_eq(MinimapProjection.for_map(MapDefinition.new()), null, "no camera anywhere: null")
	assert_eq(MinimapProjection.sidecar_xform(null), [], "no map")


func test_fit_keeps_the_aspect_and_the_margin() -> void:
	var bounds := Rect2(Vector2(-40, -10), Vector2(80, 30))
	var widget := Vector2(300, 200)
	var xf := MinimapProjection.fit(bounds, widget, 8.0)
	var s := MinimapProjection.scale_of(xf)
	assert_near(s, (300.0 - 16.0) / 80.0, 1e-4, "the wider axis decides the scale")
	assert_near(xf.y.length(), s, 1e-6, "one uniform scale (aspect kept)")
	for corner in [bounds.position, bounds.end, Vector2(bounds.position.x, bounds.end.y), Vector2(bounds.end.x, bounds.position.y)]:
		var q: Vector2 = xf * corner
		assert_true(Rect2(Vector2(8, 8), widget - Vector2(16, 16)).grow(0.01).has_point(q), "%s -> %s inside" % [corner, q])
	assert_near((xf * bounds.get_center()).x, 150.0, 1e-3, "centred")
	assert_near((xf * bounds.get_center()).y, 100.0, 1e-3, "centred")
	assert_near(MinimapProjection.scale_of(MinimapProjection.fit(bounds, widget, 8.0, 2.0)), 2.0, 1e-6, "max_scale caps it")
	assert_eq(MinimapProjection.fit(Rect2(), widget, 8.0), Transform2D.IDENTITY, "empty bounds")


func test_clamp_to_rect_keeps_the_direction() -> void:
	var r := Rect2(Vector2(0, 0), Vector2(200, 100))
	var inside := MinimapProjection.clamp_to_rect(Vector2(50, 50), r)
	assert_false(bool(inside["clamped"]), "inside: unchanged")
	assert_eq(inside["pos"], Vector2(50, 50))
	for pt: Vector2 in [Vector2(400, 50), Vector2(-90, -300), Vector2(150, 260), Vector2(1000, 1000)]:
		var c := MinimapProjection.clamp_to_rect(pt, r)
		var pos: Vector2 = c["pos"]
		assert_true(bool(c["clamped"]), "%s is clamped" % pt)
		assert_true(r.grow(0.001).has_point(pos), "%s -> %s on the rect" % [pt, pos])
		var on_edge := absf(pos.x) < 0.01 or absf(pos.x - 200) < 0.01 or absf(pos.y) < 0.01 or absf(pos.y - 100) < 0.01
		assert_true(on_edge, "%s -> %s on an edge" % [pt, pos])
		assert_near(wrapf((pos - r.get_center()).angle() - (pt - r.get_center()).angle(), -PI, PI), 0.0, 1e-4,
			"%s: same direction from the centre" % pt)
		assert_near(float(c["angle"]), (pt - r.get_center()).angle(), 1e-6, "angle reported")
