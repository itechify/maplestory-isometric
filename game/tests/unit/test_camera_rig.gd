extends TestCase
## CameraRig with a real PlayerController: sidecar configuration, dead-zone follow, no bob on jumps, bounds
## clamping, snap(), the view axes handed to the player, per-map view sizes, and the occlusion fader's alpha
## fallback. The occlusion selection itself is in test_camera_occlusion.gd, the silhouette in test_camera_silhouette.gd.

var w: PlayerTestWorld
var rig: CameraRig

const SIDECAR_CAM := {
	"xform": [0.70711, 0, 0.70711, 0.45452, 0.76604, -0.45452, -0.54168, 0.64279, 0.54168, -171.9796, 273.315, 273.7231],
	"godot_size_keep_height": 16.875, "pitch_down_deg": 40, "forward": [0.5417, -0.6428, -0.5417],
}


func before_each() -> void:
	w = PlayerTestWorld.create(db())
	w.add_box(Vector3(0, -0.5, 0), Vector3(400, 1, 400))
	rig = CameraRig.new()
	rig.follow_in_physics = false
	rig.auto_aspect = false
	w.add_node(rig)
	rig.set_process(false)
	rig.set_physics_process(false)
	rig.aspect = 16.0 / 9.0


func after_each() -> void:
	w.free_all()


func _tick(n: int) -> void:
	for i in n:
		w.player.step(PlayerTestWorld.TICK)
		rig.update_camera(PlayerTestWorld.TICK)


func test_configures_from_sidecar_and_hands_axes_to_player() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	p.set_view_axes(Vector3.RIGHT, Vector3.FORWARD)
	rig.configure_from_sidecar(SIDECAR_CAM)
	rig.set_target(p)
	var cfg: Dictionary = db().miso_table("camera")
	var expected := clampf(16.875 * float(cfg["ortho_size_scale"]), float(cfg["min_ortho_size_m"]), float(cfg["max_ortho_size_m"]))
	assert_near(rig.ortho_size, expected, 1e-4, "ortho size = sidecar keep-height x camera.json scale")
	assert_near(rig.camera.size, expected, 1e-4, "applied to the Camera3D")
	assert_eq(rig.camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "orthographic")
	assert_near((-rig.camera.global_transform.basis.z).dot(Vector3(0.5417, -0.6428, -0.5417).normalized()), 1.0, 1e-3, "looks along the sidecar forward")
	assert_near(p.view_forward.dot(Vector3(1, 0, -1).normalized()), 1.0, 1e-3, "player W axis = camera ground forward")
	# The player is centred and the camera sits far back along the view axis (no terrain clipping).
	var to_player := p.global_position - rig.camera.global_position
	assert_true(to_player.length() > 100.0, "camera far behind the focus")
	var screen := rig.camera.global_transform.basis.inverse() * to_player
	assert_near(screen.x, 0.0, 0.01, "player centred horizontally")


func test_dead_zone_and_smooth_follow() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	rig.configure_from_sidecar(SIDECAR_CAM)
	rig.set_target(p)
	var c0 := rig.focus_point()
	# A small step inside the dead zone does not move the camera.
	w.bot.world_dir = p.view_right
	_tick(10)
	assert_near(rig.focus_point().distance_to(c0), 0.0, 1e-4, "inside the dead zone")
	# Walking on: the camera follows, lagging no more than the dead zone plus a little.
	_tick(240)
	var lag := CameraMath.to_plane(p.global_position, rig.ground_right, rig.ground_forward) - CameraMath.to_plane(rig.focus_point(), rig.ground_right, rig.ground_forward)
	var zone := rig.view_half_extents() * 0.15
	assert_true(rig.focus_point().distance_to(c0) > 5.0, "camera followed")
	assert_true(absf(lag.x) <= zone.x + 0.6, "lag %.2f within the dead zone + smoothing" % lag.x)


func test_jumps_do_not_bob_the_camera() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	rig.configure_from_sidecar(SIDECAR_CAM)
	rig.set_target(p)
	var y0 := rig.camera.global_position.y
	w.bot.press(&"jump")
	var max_dy := 0.0
	for i in 40:
		_tick(1)
		max_dy = maxf(max_dy, absf(rig.camera.global_position.y - y0))
	assert_near(max_dy, 0.0, 1e-4, "camera height unchanged by a jump")


func test_vertical_follow_tracks_ground_height() -> void:
	w.add_box(Vector3(12, 1.0, 0), Vector3(12, 2.0, 12))  # a 2 m terrace
	var p := w.spawn_player(Vector3(9, 2.0, 0))
	rig.configure_from_sidecar(SIDECAR_CAM)
	rig.set_target(p)
	assert_near(rig.focus_point().y, 2.0, 0.01, "snapped to the terrace height")
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(-5, 0, 0)))
	_tick(90)
	assert_near(rig.focus_point().y, 0.0, 0.05, "eased down to the new ground height")


func test_bounds_clamp_with_overscan() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	rig.configure_from_sidecar(SIDECAR_CAM)
	rig.set_target(p)
	var outline := [[-20, -20], [20, -20], [20, 20], [-20, 20]]
	rig.set_bounds(outline)
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(150, 0, 0)))
	rig.snap()
	var rect := rig.bounds_rect()
	var c := CameraMath.to_plane(rig.focus_point(), rig.ground_right, rig.ground_forward)
	var half := rig.view_half_extents()
	var o := float(db().miso_table("camera")["overscan_m"])
	for axis in 2:
		var inside := c[axis] - half[axis] >= rect.position[axis] - o - 1e-3 and c[axis] + half[axis] <= rect.end[axis] + o + 1e-3
		var centred := absf(c[axis] - (rect.position[axis] + rect.size[axis] * 0.5)) < 1e-3
		assert_true(inside or centred, "axis %d clamped (c=%.2f half=%.2f rect=%s)" % [axis, c[axis], half[axis], rect])
	rig.clear_bounds()
	rig.snap()
	assert_near(CameraMath.to_plane(rig.focus_point(), rig.ground_right, rig.ground_forward).distance_to(CameraMath.to_plane(p.global_position, rig.ground_right, rig.ground_forward)), 0.0, 1e-3, "unbounded: centred on the player")


func test_set_bounds_blend_and_size() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	rig.configure_from_sidecar(SIDECAR_CAM)
	rig.set_target(p)
	var s0 := rig.ortho_size
	# MapSession passes MapDefinition.ortho_size = the sidecar frame WIDTH (KEEP_WIDTH) x the map's scale.
	var cfg: Dictionary = db().miso_table("camera")
	var aspect_ref := float(cfg["sidecar_reference_aspect"])
	assert_near(rig.view_size_for_frame_width(float(SIDECAR_CAM["godot_size_keep_height"]) * aspect_ref), s0, 1e-3, "frame width maps to the same view as configure_from_sidecar")
	var wider := 22.0 * aspect_ref  # a 22 m KEEP_HEIGHT frame
	var s1 := rig.view_size_for_frame_width(wider)
	assert_true(s1 > s0, "a wider map frame gives a larger view")
	rig.set_bounds([[-100, -100], [100, -100], [100, 100]], wider, 0.35)
	_tick(10)
	assert_true(rig.ortho_size > s0 and rig.ortho_size < s1, "size blending")
	_tick(30)
	assert_near(rig.ortho_size, s1, 1e-4, "blend done after 0.35 s")
	rig.set_bounds([[-100, -100], [100, 100]], float(SIDECAR_CAM["godot_size_keep_height"]) * aspect_ref, 0.0)
	assert_near(rig.ortho_size, s0, 1e-3, "warp: size cut immediately")
	assert_true(rig.view_size_for_frame_width(500.0) <= float(cfg["max_ortho_size_m"]) + 1e-6, "clamped to camera.json max")


func test_occlusion_fader_scans_extras_and_fades() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	rig.configure_from_sidecar(SIDECAR_CAM)
	rig.set_target(p)
	var holder := Node3D.new()
	var tree_mesh := MeshInstance3D.new()
	tree_mesh.mesh = BoxMesh.new()
	(tree_mesh.mesh as BoxMesh).size = Vector3(2, 3, 2)
	tree_mesh.set_meta(&"extras", {"group": "Vegetation", "category": "Trees", "asset": "Tree_Test"})
	tree_mesh.position = Vector3(0, 1.5, 0) - Vector3(0.5417, 0.0, -0.5417).normalized() * 2.5
	holder.add_child(tree_mesh)
	var bush := MeshInstance3D.new()
	bush.mesh = BoxMesh.new()
	bush.set_meta(&"extras", {"group": "Vegetation", "category": "Foliage"})
	holder.add_child(bush)
	w.add_node(holder)
	rig.scan_occluders(holder)
	assert_eq(rig.fader.candidate_count(), 1, "only the tree is an occluder candidate")
	_tick(30)
	# A BoxMesh without a material has nothing to dither: it fades by transparency (the fallback).
	assert_near(tree_mesh.transparency, float(db().miso_table("camera")["occluder_transparency"]), 1e-4, "tree between camera and player faded to occluder_transparency")
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(30, 0, 30)))
	rig.snap()
	_tick(30)
	assert_near(tree_mesh.transparency, 0.0, 1e-4, "restored when clear")


func test_map_overrides_replace_the_view_size() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	rig.configure_from_sidecar(SIDECAR_CAM)
	rig.set_target(p)
	var cfg: Dictionary = db().miso_table("camera")
	assert_true(cfg.get("map_overrides") is Dictionary, "camera.json has map_overrides")
	for id in (cfg["map_overrides"] as Dictionary):
		var ov: Dictionary = cfg["map_overrides"][id]
		assert_true(String(ov.get("reason", "")) != "", "map override %s has a reason" % id)
		assert_between(float(ov.get("ortho_size_m", 0.0)), float(cfg["min_ortho_size_m"]), float(cfg["max_ortho_size_m"]), "map override %s within min/max" % id)
		assert_false(db().map(String(id)).is_empty(), "map override %s is a MeowDB map id" % id)
	rig.config = rig.config.duplicate(true)
	rig.config["map_overrides"] = {"000000040": {"ortho_size_m": 13.25, "reason": "test"}, "000000060": {"ortho_size_m": 99.0, "reason": "test"}}
	assert_near(rig.map_view_size("000000040"), 13.25, 1e-6, "override size")
	assert_near(rig.map_view_size("000000060"), float(cfg["max_ortho_size_m"]), 1e-6, "clamped to the max")
	assert_near(rig.map_view_size("000000010"), -1.0, 1e-6, "no override")
	assert_eq(rig.session_map_id(), "", "a rig that is not MapSession's camera reads no map")
