extends TestCase
## Occlusion: the pure selection rules (OcclusionMath), the dithered stand-in materials (OccluderDither) and the
## fader on real meshes in front of / beside / behind the player and nearby monsters (OcclusionFader through the
## CameraRig).

const SIDECAR_CAM := {
	"xform": [0.70711, 0, 0.70711, 0.45452, 0.76604, -0.45452, -0.54168, 0.64279, 0.54168, -171.9796, 273.315, 273.7231],
	"godot_size_keep_height": 16.875, "pitch_down_deg": 40, "forward": [0.5417, -0.6428, -0.5417],
}
## The gameplay camera looks along this direction; toward the camera on the ground is -FWD_GROUND.
const VIEW := Vector3(0.5417, -0.6428, -0.5417)

var w: PlayerTestWorld
var rig: CameraRig
var rules: Dictionary


func before_each() -> void:
	rules = db().miso_table("camera")["occluders"]
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


func _cam() -> Basis:
	return CameraMath.basis_from_xform_array(SIDECAR_CAM["xform"])


## Unit ground vector from the player toward the camera.
func _toward_cam() -> Vector3:
	return -Vector3(VIEW.x, 0.0, VIEW.z).normalized()


func _right() -> Vector3:
	var r := _cam().x
	return Vector3(r.x, 0.0, r.z).normalized()


func _tick(n: int) -> void:
	for i in n:
		w.player.step(PlayerTestWorld.TICK)
		rig.update_camera(PlayerTestWorld.TICK)


func _setup_player(at: Vector3 = Vector3.ZERO) -> PlayerController:
	var p := w.spawn_player(at)
	rig.configure_from_sidecar(SIDECAR_CAM)
	rig.set_target(p)
	return p


## A box "mesh" with glTF-like extras, its base on the ground at `base` (feet level), under `parent`.
func _box(parent: Node3D, node_name: String, base: Vector3, size: Vector3, extras: Dictionary, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat if mat != null else _plain()
	mi.mesh = bm
	mi.set_meta(&"extras", extras)
	mi.position = base + Vector3.UP * (size.y * 0.5)
	parent.add_child(mi)
	return mi


func _plain() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _holder() -> Node3D:
	var h := Node3D.new()
	w.add_node(h)
	return h


const TREE := {"group": "Vegetation", "category": "Trees", "asset": "Tree_Test"}


# =================================================================================================================
# OcclusionMath (pure)
# =================================================================================================================

func test_occluder_rules_from_camera_json() -> void:
	assert_true(OcclusionMath.is_occluder(TREE, 0.5, rules), "trees fade at any height")
	assert_true(OcclusionMath.is_occluder({"group": "World_Forest", "category": "Trees"}, 9.0, rules), "island forest trees too")
	assert_true(OcclusionMath.is_occluder({"group": "Architecture", "category": "Architecture"}, 6.0, rules), "buildings and roofs")
	assert_true(OcclusionMath.is_occluder({"group": "Architecture"}, 6.6, rules), "architecture without a category (eaves, frames)")
	assert_false(OcclusionMath.is_occluder({"group": "Vegetation", "category": "Foliage"}, 1.0, rules), "a bush never fades")
	assert_true(OcclusionMath.is_occluder({"group": "Vegetation", "category": "Foliage", "asset": "Mushroom_Giant_Red"}, 3.8, rules), "a giant mushroom canopy does")
	assert_true(OcclusionMath.is_occluder({"group": "Props", "category": "Props", "asset": "Lamp_Post"}, 3.1, rules), "a tall prop does")
	assert_false(OcclusionMath.is_occluder({"group": "Props", "category": "Props", "asset": "Crate"}, 1.0, rules), "a crate does not")
	assert_true(OcclusionMath.is_occluder({"group": "Vegetation"}, 6.0, rules), "a giant mushroom stem (Vegetation, no category) does")
	assert_false(OcclusionMath.is_occluder({"group": "Terrain"}, 8.0, rules), "terrain never fades")
	assert_false(OcclusionMath.is_occluder({"group": "World_Scenery", "category": "Terrain"}, 50.0, rules), "scenery terrain never fades")
	assert_false(OcclusionMath.is_occluder({"group": "Plinth"}, 12.0, rules), "plinth cliff skirts never fade")
	assert_false(OcclusionMath.is_occluder({"group": "Props", "category": "Rocks"}, 3.8, rules), "rocks never fade")
	assert_false(OcclusionMath.is_occluder({"group": "Architecture", "category": "Architecture", "walkable": true}, 4.0, rules), "walkable roofs are ground")
	assert_false(OcclusionMath.is_occluder({"group": "Architecture", "climbable": "rope"}, 4.0, rules), "ropes and ladders never fade")
	assert_true(OcclusionMath.is_occluder({"group": "Architecture", "climbable": "", "walkable": false}, 4.0, rules), "unset flags do not block")


func test_room_rule_only_for_architecture() -> void:
	var room := AABB(Vector3(-5, 0, -5), Vector3(10, 6, 10))
	var chest := Vector3(0, 0.8, 0)
	assert_true(OcclusionMath.is_room({"group": "Architecture"}, room, chest, rules), "the shell the player stands in")
	assert_false(OcclusionMath.is_room({"group": "Architecture"}, room, Vector3(20, 0.8, 0), rules), "outside it: not its room")
	assert_false(OcclusionMath.is_room(TREE, room, chest, rules), "a tree the player stands in is no room")
	assert_false(OcclusionMath.is_room({"group": "Vegetation", "category": "Foliage", "asset": "Hedge_Tunnel"}, room, chest, rules), "nor a hedge tunnel")
	# Regression (review): any Architecture box holding the chest used to count, so the Amherst town gate (7.1 x 4 m)
	# hid a player walking through it and never faded; arches, signs and door frames too.
	var min_size := float(rules["room_min_size_m"])
	assert_between(min_size, 7.2, 10.0, "camera.json room_min_size_m sits between the gates (<= 7.1 m) and the shells (>= 10 m)")
	var gate := AABB(Vector3(-3.55, 0, -2), Vector3(7.1, 6.2, 4.0))
	assert_false(OcclusionMath.is_room({"group": "Architecture", "asset": "X1010000_TownGate"}, gate, chest, rules), "a town gate the player walks through is no room")
	var gazebo := AABB(Vector3(-2.85, -0.2, -2.85), Vector3(5.7, 2.8, 5.7))
	assert_false(OcclusionMath.is_room({"group": "Architecture", "asset": "X60000_Gazebo"}, gazebo, chest, rules), "nor a gazebo")
	var shell := AABB(Vector3(-5.7, -0.5, -7.7), Vector3(11.4, 9.1, 15.4))
	assert_true(OcclusionMath.is_room({"group": "Architecture"}, shell, chest, rules), "an interior shell (11.4 x 15.4 m) is")


func test_unit_key_groups_instance_parts() -> void:
	var a := OcclusionMath.unit_key("Map_Tree_Round_C__Tree_Round_C_Trunk", 7)
	var b := OcclusionMath.unit_key("Map_Tree_Round_C__Tree_Round_C_Canopy", 7)
	assert_eq(a, b, "trunk and canopy of one instance are one unit")
	assert_ne(OcclusionMath.unit_key("Map_Tree_Round_C_03__Tree_Round_C_Trunk", 7), a, "another instance is another unit")
	assert_ne(OcclusionMath.unit_key("Map_Tree_Round_C__Tree_Round_C_Trunk", 8), a, "same name under another parent too")
	assert_eq(OcclusionMath.unit_key("Lamp_Post_02", 7), "7/Lamp_Post_02", "a single-mesh asset is its own unit")


func test_body_samples_cover_the_whole_silhouette() -> void:
	var cam := _cam()
	var feet := Vector3(3, 1, -2)
	var pts := OcclusionMath.body_samples(feet, 1.5, 0.4, cam)
	assert_eq(pts.size(), 15, "5 heights x 3 columns")
	var lo := INF
	var hi := -INF
	var side := 0.0
	for p in pts:
		lo = minf(lo, p.y - feet.y)
		hi = maxf(hi, p.y - feet.y)
		side = maxf(side, absf((p - feet).dot(_right())))
		assert_near((p - feet).dot(Vector3(VIEW.x, 0, VIEW.z).normalized()), 0.0, 1e-4, "columns spread along the screen's right axis only")
	assert_between(lo, 0.1, 0.2, "from just above the feet")
	assert_between(hi, 1.35, 1.5, "to the top of the head")
	assert_near(side, 0.4, 1e-4, "both silhouette edges")


func test_disc_samples_lie_on_the_screen_plane() -> void:
	var cam := _cam()
	var c := Vector3(1, 2, 3)
	var pts := OcclusionMath.disc_samples(c, 2.4, cam)
	assert_eq(pts.size(), 17, "centre + 2 rings of 8")
	var depth := OcclusionMath.to_view(c, cam).z
	var far := 0.0
	for p in pts:
		var v := OcclusionMath.to_view(p, cam)
		assert_near(v.z, depth, 1e-4, "same depth as the centre")
		far = maxf(far, Vector2(v.x, v.y).distance_to(Vector2(OcclusionMath.to_view(c, cam).x, OcclusionMath.to_view(c, cam).y)))
	assert_near(far, 2.4, 1e-4, "out to the hole radius on screen")


func test_view_box_in_front_behind_and_aside() -> void:
	var cam := _cam()
	var chest := Vector3(0, 0.8, 0)
	var pv := OcclusionMath.to_view(chest, cam)
	var front := OcclusionMath.view_box(AABB(_toward_cam() * 2.5 + Vector3(-1, 0, -1), Vector3(2, 3, 2)), cam)
	var behind := OcclusionMath.view_box(AABB(-_toward_cam() * 4.0 + Vector3(-1, 0, -1), Vector3(2, 3, 2)), cam)
	var aside := OcclusionMath.view_box(AABB(_toward_cam() * 2.5 + _right() * 6.0 + Vector3(-1, 0, -1), Vector3(2, 3, 2)), cam)
	assert_true(OcclusionMath.may_cover(front, pv), "a box between the camera and the chest")
	assert_false(OcclusionMath.may_cover(behind, pv), "a box behind the player")
	assert_false(OcclusionMath.may_cover(aside, pv), "a box beside it on screen")
	assert_true(front.position.z < pv.z, "the front box is nearer the camera")
	var r := OcclusionMath.screen_rect(PackedVector3Array([Vector3(0, 0, 5), Vector3(2, 1, 5)]), 0.5)
	assert_eq(r, Rect2(-0.5, -0.5, 3, 2), "screen rect of view points, grown")


func test_holes_and_cut_mirror_the_shader() -> void:
	var cam_xf := Transform3D(_cam(), Vector3(-80, 100, 80))
	var chest := Vector3(0, 0.8, 0)
	var h := OcclusionMath.hole(chest, 2.0, 0.8, cam_xf)
	var v := cam_xf.affine_inverse() * chest
	assert_near(h.x, v.x, 1e-4, "view-space x")
	assert_near(h.y, v.y, 1e-4, "view-space y")
	assert_near(h.z, 2.0, 1e-6, "radius")
	assert_near(h.w, -v.z + 0.8, 1e-4, "cuts up to the target's depth + margin")
	var holes := PackedVector4Array([h])
	var nearer := v + Vector3(0, 0, 3.0)  # 3 m toward the camera (view space +Z)
	assert_near(OcclusionMath.hole_cut(nearer, holes, 0.35), 1.0, 1e-6, "full cut at the centre, in front")
	assert_near(OcclusionMath.hole_cut(nearer + Vector3(2.5, 0, 0), holes, 0.35), 0.0, 1e-6, "nothing outside the radius")
	var mid := OcclusionMath.hole_cut(nearer + Vector3(1.8, 0, 0), holes, 0.35)
	assert_between(mid, 0.05, 0.95, "a soft rim")
	assert_near(OcclusionMath.hole_cut(v - Vector3(0, 0, 2.0), holes, 0.35), 0.0, 1e-6, "behind the target stays solid")
	assert_near(OcclusionMath.hole_cut(nearer, PackedVector4Array(), 0.35), 0.0, 1e-6, "no holes, no cut")


func test_hole_floor_keeps_what_the_target_stands_on() -> void:
	# Regression (review): a dithered mesh that also carries the floor (the Southperry gazebo's deck and posts are
	# one mesh) got a hole in the deck in front of the player. A hole now cuts nothing below its target's feet.
	var cam := _cam()
	var cam_xf := Transform3D(cam, Vector3(-80, 100, 80))
	var feet := Vector3(0, 2.0, 0)
	var margin := float(db().miso_table("camera")["occluder_hole_floor_margin_m"])
	assert_between(margin, 0.02, 0.15, "camera.json occluder_hole_floor_margin_m: just above the feet")
	var floors := PackedFloat32Array([OcclusionMath.hole_floor(feet, margin)])
	assert_near(floors[0], feet.y + margin, 1e-6, "the floor is the feet + margin")
	var holes := PackedVector4Array([OcclusionMath.hole(feet + Vector3.UP * 0.8, 2.4, 0.8, cam_xf)])
	var deck := feet + _toward_cam() * 1.2  # the deck in front of the player, at its feet
	var v_deck := cam_xf.affine_inverse() * deck
	assert_true(OcclusionMath.hole_cut(v_deck, holes, 0.35) > 0.5, "without a floor the deck in front would be cut")
	assert_near(OcclusionMath.hole_cut(v_deck, holes, 0.35, deck.y, floors), 0.0, 1e-6, "with it the deck stays")
	var canopy := feet + _toward_cam() * 1.2 + Vector3.UP * 1.6
	assert_true(OcclusionMath.hole_cut(cam_xf.affine_inverse() * canopy, holes, 0.35, canopy.y, floors) > 0.5, "a canopy in front above the feet is still cut")
	# Why the floor costs the body nothing: every body sample is above the floor, and the selection segment from a
	# sample toward the camera only rises (the camera looks down), so whatever hides the body is above the floor.
	assert_true(cam.z.y > 0.5, "toward the camera is upward")
	for q in OcclusionMath.body_samples(feet, 1.5, 0.4, cam):
		assert_true(q.y > floors[0], "body sample above the floor")


func test_fade_step_and_ellipsoid() -> void:
	assert_near(OcclusionMath.fade_step(0.0, 1.0, 0.05, 0.2), 0.25, 1e-6, "a quarter of the way in 1/4 of the fade time")
	assert_near(OcclusionMath.fade_step(0.9, 1.0, 0.1, 0.2), 1.0, 1e-6, "clamped at the goal")
	assert_near(OcclusionMath.fade_step(0.3, 0.0, 0.1, 0.2), 0.0, 1e-6, "fades out")
	assert_true(OcclusionMath.ray_hits_ellipsoid(Vector3(0, 0, -5), Vector3.BACK, Vector3.ZERO, Vector3.ONE), "through the centre")
	assert_false(OcclusionMath.ray_hits_ellipsoid(Vector3(0.9, 0.9, -5), Vector3.BACK, Vector3.ZERO, Vector3.ONE), "past the round body (box corner)")
	assert_false(OcclusionMath.ray_hits_ellipsoid(Vector3(0, 0, 5), Vector3.BACK, Vector3.ZERO, Vector3.ONE), "behind the origin")


# =================================================================================================================
# OccluderDither
# =================================================================================================================

func test_dither_stand_ins_copy_the_material() -> void:
	var d := OccluderDither.new()
	var lit := StandardMaterial3D.new()
	lit.resource_name = "M_Leaf"
	lit.vertex_color_use_as_albedo = true
	lit.albedo_color = Color(0.9, 0.8, 0.7)
	lit.roughness = 0.6
	lit.metallic_specular = 0.4
	lit.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.cull_mode = BaseMaterial3D.CULL_BACK
	var a := d.clone_for(lit)
	assert_true(a != null, "a plain lit material converts")
	assert_eq(d.clone_for(lit), a, "one stand-in per material")
	assert_eq(a.get_shader_parameter(&"albedo"), Color(0.9, 0.8, 0.7), "albedo")
	assert_near(float(a.get_shader_parameter(&"roughness")), 0.6, 1e-6, "roughness")
	assert_near(float(a.get_shader_parameter(&"specular")), 0.4, 1e-6, "specular")
	assert_eq(a.get_shader_parameter(&"use_vertex_color"), true, "vertex colour albedo")
	assert_true(a.shader.code.contains("cull_disabled") and not a.shader.code.contains("unshaded"), "double-sided lit variant")
	var b := d.clone_for(ink)
	assert_true(b.shader.code.contains("unshaded") and b.shader.code.contains("cull_back"), "single-sided unshaded ink variant")
	assert_true(b.shader.code.contains("instance uniform float occlusion_fade"), "per-mesh fade")
	assert_true(b.shader.code.contains("INV_VIEW_MATRIX") and b.shader.code.contains("view_forward"), "shadow-pass gate")
	var tex := StandardMaterial3D.new()
	tex.albedo_texture = PlaceholderTexture2D.new()
	assert_eq(d.clone_for(tex), null, "textured: not convertible")
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	assert_false(OccluderDither.convertible(glass), "transparent: not convertible")
	assert_eq(d.clone_count(), 2, "two converted")
	d.update(PackedVector4Array([Vector4(1, 2, 3, 4), Vector4(5, 6, 7, 8)]), Vector3(0, 0, -1))
	assert_eq(int(a.get_shader_parameter(&"hole_count")), 2, "holes handed to every stand-in")
	assert_eq((a.get_shader_parameter(&"holes") as PackedVector4Array)[1], Vector4(5, 6, 7, 8), "hole values")
	assert_true(b.shader.code.contains("hole_floor"), "the shader reads the hole floors")
	assert_true((a.get_shader_parameter(&"hole_floor") as PackedFloat32Array)[0] < -1.0e8, "no floors given: no floor")
	d.update(PackedVector4Array([Vector4(1, 2, 3, 4)]), Vector3(0, 0, -1), PackedFloat32Array([2.1]))
	assert_near((a.get_shader_parameter(&"hole_floor") as PackedFloat32Array)[0], 2.1, 1e-6, "floors handed out")
	assert_eq((a.get_shader_parameter(&"hole_floor") as PackedFloat32Array).size(), OccluderDither.MAX_HOLES, "one per hole slot")


# =================================================================================================================
# OcclusionFader on meshes
# =================================================================================================================

func test_tree_in_front_dithers_and_restores() -> void:
	var p := _setup_player()
	var h := _holder()
	var tree := _box(h, "Tree_A", _toward_cam() * 2.5, Vector3(2, 3, 2), TREE)
	var original := tree.get_active_material(0)
	rig.scan_occluders(h)
	assert_eq(rig.fader.candidate_count(), 1, "the tree is a candidate")
	rig.scan_occluders(h)
	assert_eq(rig.fader.candidate_count(), 1, "scanning the same chunk again adds nothing")
	_tick(30)
	assert_near(rig.fader.fade_of(tree), 1.0, 1e-6, "faded in")
	assert_true(rig.fader.is_dithered(tree), "with the dither stand-in, not alpha")
	var sm := tree.get_surface_override_material(0) as ShaderMaterial
	assert_true(sm != null and sm.shader.code.contains("occlusion_fade"), "the stand-in renders the tree")
	assert_near(tree.transparency, 0.0, 1e-6, "no alpha blending")
	assert_true(rig.fader.player_covered, "the tree hides the player's body")
	assert_true(rig.player_occluded(), "the rig reports the player occluded")
	assert_eq(rig.fader.holes.size(), 1, "one hole: the player")
	assert_eq(rig.fader.hole_floors.size(), 1, "with its floor")
	assert_near(rig.fader.hole_floors[0], p.global_position.y + float(db().miso_table("camera")["occluder_hole_floor_margin_m"]), 1e-4, "at the player's feet + margin")
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(40, 0, 40)))
	rig.snap()
	_tick(30)
	assert_near(rig.fader.fade_of(tree), 0.0, 1e-6, "faded out")
	assert_true(tree.get_surface_override_material(0) == null, "its own material is back")
	assert_eq(tree.get_active_material(0), original, "the original material")
	assert_eq(rig.fader.active_count(), 0, "nothing faded")
	assert_false(rig.player_occluded(), "clear")


func test_fade_takes_the_configured_time() -> void:
	_setup_player()
	var h := _holder()
	var tree := _box(h, "Tree_A", _toward_cam() * 2.5, Vector3(2, 3, 2), TREE)
	rig.scan_occluders(h)
	var fade_s := float(db().miso_table("camera")["occluder_fade_s"])
	var ticks := int(round(fade_s * 0.5 * 60.0))
	_tick(ticks)
	assert_near(rig.fader.fade_of(tree), ticks / 60.0 / fade_s, 0.02, "half way after half the fade time")


func test_occluder_beside_the_player_inside_the_hole_radius() -> void:
	_setup_player()
	var h := _holder()
	# In front, but 1.9 m to the side on screen: misses the 0.4 m half-wide body, inside the 2.4 m disc.
	var near := _box(h, "Tree_Near", _toward_cam() * 2.5 + _right() * 1.9, Vector3(1.0, 3, 1.0), TREE)
	var far := _box(h, "Tree_Far", _toward_cam() * 2.5 + _right() * 5.0, Vector3(1.0, 3, 1.0), TREE)
	var behind := _box(h, "Tree_Behind", -_toward_cam() * 3.0, Vector3(2, 3, 2), TREE)
	rig.scan_occluders(h)
	_tick(30)
	assert_true(rig.fader.fade_of(near) > 0.99, "inside the readability disc: dithered")
	assert_false(rig.fader.player_covered, "but it does not hide the body itself")
	assert_false(rig.player_occluded(), "so no see-through outline")
	assert_near(rig.fader.fade_of(far), 0.0, 1e-6, "outside the disc: solid")
	assert_near(rig.fader.fade_of(behind), 0.0, 1e-6, "behind the player: solid")


func test_whole_body_is_tested_not_one_ray() -> void:
	_setup_player()
	var h := _holder()
	# A low wall-like prop in front that hides only the legs, offset to the body's edge: the old three centre rays
	# (feet, chest, head) missed it; the body grid does not.
	var low := _box(h, "Fence_Tall", _toward_cam() * 1.0 + _right() * 0.35, Vector3(0.2, 2.0, 0.2), {"group": "Props", "category": "Props"})
	rig.scan_occluders(h)
	_tick(20)
	assert_true(rig.fader.fade_of(low) > 0.99, "edge of the body covered: faded")
	assert_true(rig.fader.player_covered, "counts as hiding the body")


func test_trunk_and_canopy_fade_together() -> void:
	_setup_player()
	var h := _holder()
	var inst := Node3D.new()
	h.add_child(inst)
	# The canopy hangs over the view ray; the trunk stands aside of it but belongs to the same tree.
	var canopy := _box(inst, "Map_Tree_X__Tree_X_Canopy", _toward_cam() * 2.5 + Vector3.UP * 1.5, Vector3(2.4, 2.0, 2.4), TREE)
	var trunk := _box(inst, "Map_Tree_X__Tree_X_Trunk", _toward_cam() * 2.5 + _right() * 6.0, Vector3(0.4, 1.5, 0.4), TREE)
	var other := _box(inst, "Map_Tree_Y__Tree_Y_Trunk", _toward_cam() * 2.5 + _right() * 6.0 + Vector3(0, 0, 0.8), Vector3(0.4, 1.5, 0.4), TREE)
	rig.scan_occluders(h)
	assert_eq(rig.fader.unit_count(), 2, "two trees")
	_tick(30)
	assert_true(rig.fader.fade_of(canopy) > 0.99, "the canopy covers the player")
	assert_true(rig.fader.fade_of(trunk) > 0.99, "its trunk fades with it")
	assert_near(rig.fader.fade_of(other), 0.0, 1e-6, "another tree's trunk does not")


func test_tall_rule_reads_the_whole_instance() -> void:
	# Regression (review): the tall rule read each part's own height, so a giant red mushroom's 1.5 m cap on its
	# 2.0 m stem (both Vegetation/Foliage) never faded while the stem did; lily of the valley bells and flag pennants
	# likewise (12 instances split on the island).
	var h := _holder()
	var inst := Node3D.new()
	h.add_child(inst)
	var foliage := {"group": "Vegetation", "category": "Foliage", "asset": "Mushroom_Giant_Red"}
	var stem := _box(inst, "Map_Mushroom_Giant_Red__Mushroom_Giant_Red_Stem", Vector3(10, 0, 0), Vector3(0.6, 2.0, 0.6), foliage)
	var cap := _box(inst, "Map_Mushroom_Giant_Red__Mushroom_Giant_Red_Cap", Vector3(10, 1.8, 0), Vector3(2.6, 1.5, 2.6), foliage)
	var lone := _box(inst, "Map_Mushroom_Small", Vector3(14, 0, 0), Vector3(1.0, 1.5, 1.0), foliage)
	var roof := _box(inst, "Map_Mushroom_House__Cap_Walk", Vector3(18, 0, 0), Vector3(1.0, 1.0, 1.0), foliage.merged({"walkable": true}))
	var roof_stem := _box(inst, "Map_Mushroom_House__Stem", Vector3(18, 0, 0), Vector3(1.0, 3.0, 1.0), foliage)
	rig.scan_occluders(h)
	var fader := rig.fader
	assert_true(fader.is_candidate(stem), "the 2.0 m stem is a candidate")
	assert_true(fader.is_candidate(cap), "and so is the 1.5 m cap: the instance is 3.3 m tall")
	assert_false(fader.is_candidate(lone), "a lone 1.5 m mushroom is not")
	assert_true(fader.is_candidate(roof_stem), "a tall instance's stem")
	assert_false(fader.is_candidate(roof), "but never its walkable cap (never_flags still apply per part)")
	assert_eq(fader.unit_count(), 2, "the giant mushroom and the house stem: two units")


func test_nearby_monster_is_a_target() -> void:
	var p := _setup_player()
	var h := _holder()
	var spot := _right() * 5.0
	var tree := _box(h, "Tree_M", spot + _toward_cam() * 2.0, Vector3(1.6, 3, 1.6), TREE)
	rig.scan_occluders(h)
	_tick(20)
	assert_near(rig.fader.fade_of(tree), 0.0, 1e-6, "no monster there: the tree stays")
	var mob := StaticBody3D.new()
	mob.collision_layer = WorldLayers.MONSTERS
	mob.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.0
	cs.shape = shape
	cs.position = Vector3.UP * 0.5
	mob.add_child(cs)
	mob.position = spot
	h.add_child(mob)
	var found := rig.nearby_monsters(p.global_position)
	assert_eq(found.size(), 1, "the monster layer query finds it")
	assert_near(float(found[0].height), float(db().miso_table("camera")["occluder_monster_default_height_m"]), 1e-6, "default size without a MonsterDef")
	_tick(20)
	assert_true(rig.fader.fade_of(tree) > 0.99, "a tree hiding a nearby monster dithers out")
	assert_false(rig.fader.player_covered, "it does not hide the player")
	assert_eq(rig.fader.holes.size(), 2, "a hole for the player and one for the monster")
	assert_near(rig.fader.hole_floors[1], mob.global_position.y + float(db().miso_table("camera")["occluder_hole_floor_margin_m"]), 1e-4, "the monster's hole floor is at its feet")
	mob.free()
	_tick(20)
	assert_near(rig.fader.fade_of(tree), 0.0, 1e-6, "monster gone: the tree is back")


func test_room_and_walkable_never_fade() -> void:
	var p := _setup_player()
	var h := _holder()
	var shell := _box(h, "Room_Shell_Walls", Vector3(-4, 0, -4) + Vector3(4, 0, 4), Vector3(10, 5, 10), {"group": "Architecture"})
	var roof := _box(h, "Roof_Walk", _toward_cam() * 3.0 + Vector3.UP * 0.0, Vector3(2, 3, 2), {"group": "Architecture", "category": "Architecture", "walkable": true})
	var canopy := _box(h, "Big_Canopy", Vector3.ZERO, Vector3(6, 4, 6), TREE)
	rig.scan_occluders(h)
	assert_eq(rig.fader.candidate_count(), 2, "the walkable roof is not even a candidate")
	_tick(20)
	assert_near(rig.fader.fade_of(shell), 0.0, 1e-6, "the room the player stands in stays")
	assert_near(roof.transparency + rig.fader.fade_of(roof), 0.0, 1e-6, "walkable roof stays")
	assert_true(rig.fader.fade_of(canopy) > 0.99, "a tree the player stands inside still fades")
	assert_true(p.global_position.length() < 0.5, "player in place")


func test_unconvertible_material_falls_back_to_transparency() -> void:
	_setup_player()
	var h := _holder()
	var tex := StandardMaterial3D.new()
	tex.albedo_texture = PlaceholderTexture2D.new()
	var tree := _box(h, "Tree_Tex", _toward_cam() * 2.5, Vector3(2, 3, 2), TREE, tex)
	rig.scan_occluders(h)
	_tick(30)
	assert_false(rig.fader.is_dithered(tree), "not dithered")
	assert_near(tree.transparency, float(db().miso_table("camera")["occluder_transparency"]), 1e-4, "alpha fade instead")
	rig.fader.clear()
	assert_near(tree.transparency, 0.0, 1e-6, "clear() restores it")
	assert_eq(rig.fader.candidate_count(), 0, "and forgets the meshes")
