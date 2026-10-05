extends TestCase
## CameraMath: ground axes of the fixed isometric view, view extents, the bounds clamp with overscan and
## centring (MAP_ARCHITECTURE section 4.11), the dead zone and the per-map ortho size.

const ASPECT := 16.0 / 9.0


func _iso_basis() -> Basis:
	# Iteration One's gameplay camera, exactly as a sidecar exports it (cameras.gameplay.xform).
	return CameraMath.basis_from_xform_array([0.70711, 0, 0.70711, 0.45452, 0.76604, -0.45452, -0.54168, 0.64279, 0.54168, 0, 0, 0])


func test_iso_axes_and_pitch() -> void:
	var b := _iso_basis()
	var axes := CameraMath.ground_axes(b)
	assert_near(axes[0].x, 0.7071, 1e-3, "right x")
	assert_near(axes[0].z, 0.7071, 1e-3, "right z")
	assert_near(axes[1].x, 0.7071, 1e-3, "forward x (toward Godot +X)")
	assert_near(axes[1].z, -0.7071, 1e-3, "forward z (toward Godot -Z)")
	assert_near(rad_to_deg(CameraMath.pitch_down(b)), 40.0, 0.01, "pitch 40 down")


func test_angles_reproduce_sidecar_basis() -> void:
	var b := CameraMath.basis_from_angles(40.0, -45.0)
	var fwd := -b.z
	assert_near(fwd.x, 0.5417, 1e-3, "forward x")
	assert_near(fwd.y, -0.6428, 1e-3, "forward y")
	assert_near(fwd.z, -0.5417, 1e-3, "forward z")


func test_view_half_extents_on_ground() -> void:
	var half := CameraMath.view_half_extents(18.0, ASPECT, deg_to_rad(40.0))
	assert_near(half.x, 18.0 * ASPECT * 0.5, 1e-4, "horizontal half width")
	assert_near(half.y, 9.0 / sin(deg_to_rad(40.0)), 1e-4, "ground depth is foreshortened by sin(pitch)")


func test_plane_round_trip() -> void:
	var axes := CameraMath.ground_axes(_iso_basis())
	var p := Vector3(12.5, 3.0, -7.25)
	var rf := CameraMath.to_plane(p, axes[0], axes[1])
	var back := CameraMath.from_plane(rf, 3.0, axes[0], axes[1])
	assert_near(back.distance_to(p), 0.0, 1e-4, "round trip")


func test_bounds_forms() -> void:
	assert_eq(CameraMath.bounds_points(PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])).size(), 2, "packed")
	assert_eq(CameraMath.bounds_points([[0, 0], [10, 0], [10, 10]]).size(), 3, "array of pairs (sidecar outline_xz)")
	assert_eq(CameraMath.bounds_points(Rect2(0, 0, 10, 5)).size(), 4, "Rect2")
	var from_aabb := CameraMath.bounds_points(AABB(Vector3(1, 0, 2), Vector3(4, 9, 6)))
	assert_eq(from_aabb.size(), 4, "AABB")
	assert_eq(from_aabb[2], Vector2(5, 8), "AABB x/z extent")
	assert_eq(CameraMath.bounds_points(null).size(), 0, "null -> unbounded")


func test_clamp_inside_bounds_with_overscan() -> void:
	var bounds := Rect2(0, 0, 100, 60)
	var half := Vector2(10, 7)
	# Far outside on both axes: the view edge lands exactly on bounds + overscan.
	var c := CameraMath.clamp_focus(Vector2(-50, 500), bounds, half, 6.0)
	assert_near(c.x, -6.0 + 10.0, 1e-6, "left edge at -overscan")
	assert_near(c.y, 60.0 + 6.0 - 7.0, 1e-6, "far edge at +overscan")
	# Inside: unchanged.
	assert_eq(CameraMath.clamp_focus(Vector2(40, 30), bounds, half, 6.0), Vector2(40, 30), "inside untouched")


func test_clamp_centres_axis_smaller_than_view() -> void:
	var bounds := Rect2(10, 20, 8, 100)  # 8 m wide (+12 overscan = 20) but the view is 30 m wide
	var c := CameraMath.clamp_focus(Vector2(100, 50), bounds, Vector2(15, 7), 6.0)
	assert_near(c.x, 14.0, 1e-6, "centred on the narrow axis")
	assert_near(c.y, 50.0, 1e-6, "other axis untouched")


func test_clamp_with_projected_map_footprint() -> void:
	# A real sidecar footprint (MushroomTown_10000 outline_xz) under the iso camera, 16:9, the shipped size scale.
	var outline := [[16.9349, 36.5377], [27.8053, 77.1066], [62.5787, 67.7891], [51.7083, 27.2202]]
	var axes := CameraMath.ground_axes(_iso_basis())
	var rect := CameraMath.bounds_rect(CameraMath.bounds_points(outline), axes[0], axes[1])
	assert_true(rect.size.x > 30.0 and rect.size.y > 30.0, "footprint projected to a plane rect")
	var half := CameraMath.view_half_extents(13.5, ASPECT, deg_to_rad(40.0))
	var far := CameraMath.to_plane(Vector3(500, 0, -500), axes[0], axes[1])
	var c := CameraMath.clamp_focus(far, rect, half, 6.0)
	assert_true(c.x + half.x <= rect.end.x + 6.0 + 1e-4, "view stays within bounds + overscan (r)")
	assert_true(c.y + half.y <= rect.end.y + 6.0 + 1e-4, "view stays within bounds + overscan (f)")
	assert_true(c.x - half.x >= rect.position.x - 6.0 - 1e-4 or rect.size.x + 12.0 < half.x * 2.0, "left edge")


func test_dead_zone() -> void:
	var zone := Vector2(2, 1)
	assert_eq(CameraMath.dead_zone_follow(Vector2.ZERO, Vector2(1.5, -0.5), zone), Vector2.ZERO, "inside: no move")
	assert_eq(CameraMath.dead_zone_follow(Vector2.ZERO, Vector2(5, 0), zone), Vector2(3, 0), "pushed by the edge")
	assert_eq(CameraMath.dead_zone_follow(Vector2.ZERO, Vector2(0, -4), zone), Vector2(0, -3), "other axis")


func test_ortho_size_from_sidecar_and_camera_json() -> void:
	var cfg: Dictionary = db().miso_table("camera")
	var scale := float(cfg["ortho_size_scale"])
	var lo := float(cfg["min_ortho_size_m"])
	var hi := float(cfg["max_ortho_size_m"])
	assert_near(CameraMath.ortho_size(16.875, scale, 1.0, lo, hi), clampf(16.875 * scale, lo, hi), 1e-6, "Mushroom Town")
	assert_near(CameraMath.ortho_size(28.125, scale, 1.0, lo, hi), clampf(28.125 * scale, lo, hi), 1e-6, "Southperry")
	assert_near(CameraMath.ortho_size(100.0, 1.0, 1.0, lo, hi), hi, 1e-6, "clamped to max")
	assert_near(CameraMath.ortho_size(1.0, 1.0, 1.0, lo, hi), lo, 1e-6, "clamped to min")


func test_smoothing_is_frame_rate_independent() -> void:
	var two := 1.0 - (1.0 - CameraMath.smoothing(7.0, 1.0 / 120.0)) * (1.0 - CameraMath.smoothing(7.0, 1.0 / 120.0))
	assert_near(two, CameraMath.smoothing(7.0, 1.0 / 60.0), 1e-6, "two half steps == one step")
