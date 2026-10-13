extends TestCase
## The player's readability through geometry: PlayerVisual's stencil X-ray fill and see-through outline (materials,
## smoothed outline hull, toggling and its fade), CameraRig turning the outline on while a faded occluder or terrain
## hides the player, and the library proxy lookup.

const SIDECAR_CAM := {
	"xform": [0.70711, 0, 0.70711, 0.45452, 0.76604, -0.45452, -0.54168, 0.64279, 0.54168, -171.9796, 273.315, 273.7231],
	"godot_size_keep_height": 16.875, "pitch_down_deg": 40, "forward": [0.5417, -0.6428, -0.5417],
}
const VIEW := Vector3(0.5417, -0.6428, -0.5417)

var w: PlayerTestWorld
var rig: CameraRig
var cfg: Dictionary


func before_each() -> void:
	cfg = db().miso_table("camera")
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


func _toward_cam() -> Vector3:
	return -Vector3(VIEW.x, 0.0, VIEW.z).normalized()


## A player with a PlayerVisual ("Visual", the procedural placeholder model, no blob shadow) followed by the rig.
func _player_with_visual() -> Array:
	var p := w.spawn_player(Vector3.ZERO)
	var vis := PlayerVisual.new()
	vis.name = "Visual"
	vis.use_library_model = false
	vis.blob_shadow = false
	p.add_child(vis)
	vis.set_process(false)
	rig.configure_from_sidecar(SIDECAR_CAM)
	rig.set_target(p)
	return [p, vis]


func _tick(n: int, vis: PlayerVisual = null) -> void:
	for i in n:
		w.player.step(PlayerTestWorld.TICK)
		rig.update_camera(PlayerTestWorld.TICK)
		if vis != null:
			vis.step_see_through(PlayerTestWorld.TICK)


func test_lit_surfaces_write_the_stencil_and_chain_the_fill() -> void:
	var vis: PlayerVisual = _player_with_visual()[1]
	var mats := vis.silhouette_materials()
	var fill := mats.fill as StandardMaterial3D
	var outline := mats.outline as StandardMaterial3D
	assert_true(fill != null and outline != null, "both passes built")
	var lit := 0
	var stack: Array[Node] = [vis.model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.name == PlayerVisual.OUTLINE_NAME:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m == null or m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				continue
			lit += 1
			assert_eq(m.stencil_mode, BaseMaterial3D.STENCIL_MODE_CUSTOM, "custom stencil on %s" % mi.name)
			assert_eq(m.stencil_flags, BaseMaterial3D.STENCIL_FLAG_WRITE, "writes where visible")
			assert_eq(m.stencil_compare, BaseMaterial3D.STENCIL_COMPARE_ALWAYS, "always")
			assert_eq(m.stencil_reference, PlayerVisual.STENCIL_REF, "the player's reference")
			assert_eq(m.next_pass, fill, "X-ray fill as the next pass")
	assert_true(lit >= 4, "every lit part of the placeholder (%d)" % lit)
	# Fill: hidden parts only (stencil != ref), over everything, then marks them.
	assert_true(fill.no_depth_test, "fill ignores depth")
	assert_eq(fill.cull_mode, BaseMaterial3D.CULL_BACK, "fill blends each hidden part once (front faces)")
	assert_eq(fill.stencil_compare, BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL, "fill where the body was not drawn")
	assert_eq(fill.stencil_flags, BaseMaterial3D.STENCIL_FLAG_READ, "fill reads")
	var mark := mats.mark as StandardMaterial3D
	assert_eq(fill.next_pass, mark, "then the mark pass")
	assert_eq(mark.stencil_flags, BaseMaterial3D.STENCIL_FLAG_WRITE, "mark writes")
	assert_eq(mark.stencil_compare, BaseMaterial3D.STENCIL_COMPARE_ALWAYS, "over the whole silhouette")
	assert_true(mark.no_depth_test, "hidden parts too")
	assert_near(mark.albedo_color.a, 0.0, 1e-6, "invisible")
	assert_true(fill.render_priority < mark.render_priority and mark.render_priority < outline.render_priority, "fill, mark, outline")
	assert_eq(fill.albedo_color, PlayerVisual._color(cfg["xray_color"], Color.BLACK), "fill colour from camera.json")
	# Outline: a grown hull on top of everything, never over the silhouette itself, drawn last.
	assert_true(outline.no_depth_test, "outline: depth test off")
	assert_true(outline.grow and outline.grow_amount > 0.0, "outline: grown hull")
	assert_eq(outline.stencil_flags, BaseMaterial3D.STENCIL_FLAG_READ, "outline only reads")
	assert_eq(outline.stencil_compare, BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL, "outline outside the marked silhouette")
	assert_eq(outline.render_priority, PlayerVisual.OUTLINE_PRIORITY, "drawn after everything")
	assert_true(fill.render_priority < outline.render_priority, "fill before outline")
	assert_true(fill.render_priority > 100, "after faded occluders and FX")
	assert_eq(outline.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED, "flat player colour")


func test_ink_shell_writes_the_stencil_without_fill_or_hull() -> void:
	# Regression (review): the Player_Proxy's unshaded inverted-hull ink (M_Outline) draws contour lines in front of
	# the body at creases. It wrote no stencil, so the X-ray fill painted those lines blue on an unoccluded player
	# (360 px around the hair, the ear and the feet on Snail Hunting Ground I).
	var vis := PlayerVisual.new()
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var body := BoxMesh.new()
	var arrays := body.get_mesh_arrays()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var lit := StandardMaterial3D.new()
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color.BLACK
	am.surface_set_material(0, lit)
	am.surface_set_material(1, ink)
	mi.mesh = am
	root.add_child(mi)
	vis._apply_silhouette(root)
	var m_lit := mi.get_active_material(0) as BaseMaterial3D
	var m_ink := mi.get_active_material(1) as BaseMaterial3D
	assert_ne(m_ink, ink, "the ink gets a copy (the library material stays untouched)")
	assert_eq(ink.stencil_mode, BaseMaterial3D.STENCIL_MODE_DISABLED, "the shared original is unchanged")
	assert_eq(m_ink.stencil_mode, BaseMaterial3D.STENCIL_MODE_CUSTOM, "the ink writes the stencil")
	assert_eq(m_ink.stencil_flags, BaseMaterial3D.STENCIL_FLAG_WRITE, "writes")
	assert_eq(m_ink.stencil_reference, PlayerVisual.STENCIL_REF, "the player's reference")
	assert_true(m_ink.next_pass == null, "no X-ray fill on the ink")
	assert_eq(m_lit.next_pass, vis.silhouette_materials().fill, "the lit body keeps its fill")
	assert_eq(vis.outline_meshes().size(), 1, "one outline hull")
	var hull_tris := (vis.outline_meshes()[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	assert_eq(hull_tris, (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), "built from the lit surface only (the ink is not grown again)")
	root.free()
	vis.free()


func test_outline_meshes_are_hidden_player_layer_shadowless() -> void:
	var vis: PlayerVisual = _player_with_visual()[1]
	var outs := vis.outline_meshes()
	assert_eq(outs.size(), 4, "one outline per placeholder part")
	for o in outs:
		assert_false(o.visible, "hidden until something hides the player")
		assert_eq(o.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow")
		assert_eq(o.layers, PlayerVisual.PLAYER_LAYER, "on the player layer (no blob shadow on it)")
		assert_eq(o.material_override, vis.silhouette_materials().outline, "the shared outline material")


func test_smoothed_hull_averages_split_normals() -> void:
	var box := BoxMesh.new()  # flat shaded: 3 split normals per corner
	var hull := PlayerVisual.smoothed_hull(box, [0])
	assert_true(hull != null, "built")
	var arr := hull.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	assert_eq(v.size(), (box.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "same vertices")
	var corner := Vector3(0.5, 0.5, 0.5)
	for i in v.size():
		assert_near(n[i].length(), 1.0, 1e-4, "unit normals")
		if v[i].is_equal_approx(corner):
			assert_near(n[i].dot(corner.normalized()), 1.0, 1e-3, "a corner's normals agree (diagonal): no crack when grown")
	assert_eq((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), (box.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), "same triangles")


func test_see_through_toggles_with_a_fade() -> void:
	var vis: PlayerVisual = _player_with_visual()[1]
	var fade_s := float(cfg["silhouette_fade_s"])
	var full_a := PlayerVisual._color(cfg["silhouette_color"], Color.BLACK).a
	vis.set_see_through(true)
	assert_true(vis.is_see_through(), "requested")
	vis.step_see_through(fade_s * 0.5)
	assert_near(vis.see_through_amount, 0.5, 1e-4, "half way after half the fade")
	assert_near(vis.silhouette_materials().outline.albedo_color.a, full_a * 0.5, 1e-4, "outline alpha follows")
	for o in vis.outline_meshes():
		assert_true(o.visible, "outline shown while fading in")
	vis.step_see_through(fade_s)
	assert_near(vis.see_through_amount, 1.0, 1e-6, "fully on")
	vis.set_see_through(false)
	vis.step_see_through(fade_s * 0.25)
	assert_near(vis.see_through_amount, 0.75, 1e-4, "fading out")
	vis.step_see_through(fade_s)
	assert_near(vis.see_through_amount, 0.0, 1e-6, "off")
	for o in vis.outline_meshes():
		assert_false(o.visible, "hidden again")


## #18: the post-hit blink hid the body, its X-ray fill and its outline together, so under a canopy the player
## vanished at the moment a monster touched them. While something hides the player (any occluder or terrain), a
## blink-off slice still draws the silhouette as a ghost at the X-ray opacity; in the open the blink is unchanged.
func test_the_silhouette_survives_the_blink_while_hidden() -> void:
	var vis: PlayerVisual = _player_with_visual()[1]
	assert_true(PlayerVisual.blink_off_at(PlayerVisual.BLINK_MS) and not PlayerVisual.blink_off_at(0), "slices alternate")
	assert_false(PlayerVisual.blink_off_at(PlayerVisual.BLINK_MS * 2 + 5), "on again")
	for o in vis.outline_meshes():
		assert_false(vis.model.is_ancestor_of(o), "the outline is not under the body (hiding the body leaves it)")
	# In the open: a blink-off slice draws nothing.
	vis.apply_blink(true)
	vis.step_see_through(1.0)
	assert_false(vis.model.is_visible_in_tree(), "the body blinks off")
	for o in vis.outline_meshes():
		assert_false(o.is_visible_in_tree(), "nothing drawn in the open")
	# Hidden (a canopy, a building, terrain): the ghost on the blink-off slice, the ring on the blink-on slice.
	vis.set_see_through(true)
	vis.step_see_through(1.0)
	for o in vis.outline_meshes():
		assert_true(o.is_visible_in_tree(), "the silhouette is drawn while the body blinks off")
	var mats := vis.silhouette_materials()
	assert_near((mats.outline as StandardMaterial3D).albedo_color.a, vis.xray_color.a, 1e-4, "as a ghost at the X-ray opacity")
	vis.apply_blink(false)
	vis.step_see_through(0.016)
	assert_true(vis.model.is_visible_in_tree(), "the body is back")
	assert_near((mats.outline as StandardMaterial3D).albedo_color.a, vis.silhouette_color.a, 1e-4, "and the outline is a ring again")
	# The outline follows the model (PlayerCombat lunges the Model node).
	vis.model.position = Vector3(0, 0, 0.14)
	vis.step_see_through(0.016)
	for o in vis.outline_meshes():
		var on_a_part := false
		for c in vis.model.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).global_transform.is_equal_approx(o.global_transform):
				on_a_part = true
		assert_true(on_a_part, "each outline sits on its part, lunge included")


func test_rig_turns_the_outline_on_behind_a_tree() -> void:
	var pair := _player_with_visual()
	var p: PlayerController = pair[0]
	var vis: PlayerVisual = pair[1]
	var tree := MeshInstance3D.new()
	tree.name = "Tree_T"
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 3, 2)
	bm.material = StandardMaterial3D.new()
	tree.mesh = bm
	tree.set_meta(&"extras", {"group": "Vegetation", "category": "Trees"})
	tree.position = _toward_cam() * 2.5 + Vector3.UP * 1.5
	var holder := Node3D.new()
	holder.add_child(tree)
	w.add_node(holder)
	rig.scan_occluders(holder)
	_tick(20, vis)
	assert_true(rig.player_occluded(), "the tree hides the player")
	assert_true(vis.is_see_through(), "the rig turned the outline on")
	assert_near(vis.see_through_amount, 1.0, 1e-6, "fully faded in")
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(40, 0, 40)))
	rig.snap()
	_tick(20, vis)
	assert_false(rig.player_occluded(), "in the open")
	assert_false(vis.is_see_through(), "outline off")
	assert_near(vis.see_through_amount, 0.0, 1e-6, "faded out")


func test_rig_turns_the_outline_on_behind_terrain() -> void:
	var vis: PlayerVisual = _player_with_visual()[1]
	_tick(5, vis)
	assert_false(rig.player_occluded(), "open ground: nothing hides the player")
	assert_false(rig.terrain_hides(Vector3.ZERO), "the floor under the feet does not count")
	# A 4 m cliff block between the camera and the player (terrain never fades; only the outline can help).
	w.add_box(_toward_cam() * 3.0 + Vector3.UP * 2.0, Vector3(2, 4, 2))
	_tick(5, vis)
	assert_true(rig.terrain_hides(Vector3.ZERO), "a ray toward the camera hits the cliff")
	assert_true(rig.player_occluded(), "so the player counts as hidden")
	assert_true(vis.is_see_through(), "and the outline shows")
	assert_eq(rig.fader.active_count(), 0, "terrain itself never fades")


func test_finds_the_library_proxy_by_asset_name() -> void:
	var lib := Node3D.new()
	var other := Node3D.new()
	other.name = "NPC_Robin_001"
	lib.add_child(other)
	var proxy := Node3D.new()
	proxy.name = "Player_Proxy_001"
	lib.add_child(proxy)
	assert_eq(PlayerVisual.find_proxy(lib), proxy, "Blender's numeric suffix is ignored (the export names it Player_Proxy_001)")
	proxy.name = "Player_Proxy"
	assert_eq(PlayerVisual.find_proxy(lib), proxy, "an exact name works too")
	lib.remove_child(proxy)
	proxy.free()
	assert_true(PlayerVisual.find_proxy(lib) == null, "no proxy: null (the visual builds the placeholder)")
	lib.free()
	if not ResourceLoader.exists(PlayerVisual.LIBRARY):
		return  # no world export: the real-library check needs INCLUDE_WORLD=1
	var p := w.spawn_player(Vector3.ZERO)
	var vis := PlayerVisual.new()
	vis.blob_shadow = false
	p.add_child(vis)
	if vis.rigged():
		# With the art pack installed the real game shows the rigged Beginner before the proxy (#63); its surfaces,
		# fill and skinned outline hulls are pinned in test_player_rig.gd. Run with NO_ART_PACK=1 for the proxy.
		assert_true(vis.outline_meshes().size() >= 1, "the rig has outline hulls")
		return
	var placeholder_parts := 0
	for c in vis.model.get_children():
		if c is MeshInstance3D and ((c as MeshInstance3D).mesh is CapsuleMesh or (c as MeshInstance3D).mesh is SphereMesh):
			placeholder_parts += 1
	assert_eq(placeholder_parts, 0, "the real game shows the exported Player_Proxy, not the placeholder")
	assert_true(vis.outline_meshes().size() >= 1, "and gives it an outline hull")
	# Every surface of the real proxy, its unshaded ink shell (M_Outline) included, writes the player's stencil;
	# only lit surfaces carry the X-ray fill.
	var surfaces := 0
	var unshaded := 0
	for n in vis.model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.name == PlayerVisual.OUTLINE_NAME:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m == null:
				continue
			surfaces += 1
			assert_eq(m.stencil_flags, BaseMaterial3D.STENCIL_FLAG_WRITE, "%s writes the stencil" % m.resource_name)
			assert_eq(m.stencil_reference, PlayerVisual.STENCIL_REF, "%s: the player's reference" % m.resource_name)
			if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				unshaded += 1
				assert_true(m.next_pass == null, "%s (ink) has no fill" % m.resource_name)
			else:
				assert_eq(m.next_pass, vis.silhouette_materials().fill, "%s carries the fill" % m.resource_name)
	assert_true(surfaces >= 2, "the proxy's surfaces were checked (%d)" % surfaces)
	assert_true(unshaded >= 1, "including its ink shell")
