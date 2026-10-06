extends TestCase
## The monsters' see-through silhouette (MonsterVisual, MonsterSystem.update_see_through): the toggle rule (radius,
## hysteresis, alive), the shared fill (stencil read and write below the player's reference, no depth test, drawn
## before labels, numbers and the HP bar), stencil-writing copies of every model surface (the ink shell too, the
## library's shared materials untouched), the placeholder path, the fade, off at once while dying, no flash or death
## fade on the fill, and the system turning silhouettes on and off by the distance to the player.

var rig: MonsterTestRig


func before_each() -> void:
	rig = MonsterTestRig.create(db())
	rig.floor(80.0)


func after_each() -> void:
	rig.free_all()


func _snail() -> MonsterDef:
	return MonsterDef.from_id("2", db())


## A MonsterVisual of `def` under a bare Node3D standing in for the Monster (null library: the placeholder model).
func _visual(def: MonsterDef) -> MonsterVisual:
	var mon := Node3D.new()
	rig.w.add_node(mon)
	var v := MonsterVisual.new()
	mon.add_child(v)
	v.monster = mon
	v.set_process(false)
	v.build(def, null)
	return v


## Every MeshInstance3D of the model that is not a fill.
func _model_meshes(v: MonsterVisual) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in v.model.find_children("*", "MeshInstance3D", true, false):
		if String(n.name) != MonsterVisual.SEE_THROUGH_NAME:
			out.append(n as MeshInstance3D)
	return out


func _writes_stencil(m: Material) -> bool:
	var b := m as BaseMaterial3D
	return b != null and b.stencil_mode == BaseMaterial3D.STENCIL_MODE_CUSTOM \
		and b.stencil_flags == BaseMaterial3D.STENCIL_FLAG_WRITE \
		and b.stencil_compare == BaseMaterial3D.STENCIL_COMPARE_ALWAYS \
		and b.stencil_reference == MonsterVisual.STENCIL_REF


# =================================================================================================================
# The rule
# =================================================================================================================

func test_the_rule_radius_hysteresis_and_alive() -> void:
	assert_true(MonsterVisual.see_through_wanted(true, 5.0, 12.0, 1.0, false), "inside the radius")
	assert_true(MonsterVisual.see_through_wanted(true, 12.0, 12.0, 1.0, false), "exactly at the radius")
	assert_false(MonsterVisual.see_through_wanted(true, 12.5, 12.0, 1.0, false), "just outside: not turned on")
	assert_true(MonsterVisual.see_through_wanted(true, 12.5, 12.0, 1.0, true), "but one showing keeps it (hysteresis)")
	assert_true(MonsterVisual.see_through_wanted(true, 13.0, 12.0, 1.0, true), "up to radius + hysteresis")
	assert_false(MonsterVisual.see_through_wanted(true, 13.01, 12.0, 1.0, true), "and drops it beyond")
	assert_false(MonsterVisual.see_through_wanted(false, 1.0, 12.0, 1.0, true), "never for a dead monster")
	assert_false(MonsterVisual.see_through_wanted(true, 0.0, 0.0, 1.0, false), "a zero radius turns it off")
	assert_false(MonsterVisual.see_through_wanted(true, 12.5, 12.0, -3.0, true), "a negative hysteresis counts as none")


func test_the_values_come_from_the_shared_table() -> void:
	var shared := db().miso_entity("monsters", MonsterDef.SHARED_TABLE)
	var c: Array = shared["see_through_color"]
	for id in ["1", "2", "3", "4", "5", "9"]:
		var d := MonsterDef.build(id, db())
		assert_eq(d.errors.size(), 0, "; ".join(d.errors))
		assert_near(d.see_through_radius_m, float(shared["see_through_radius_m"]), 1e-9, "%s radius" % id)
		assert_near(d.see_through_hysteresis_m, float(shared["see_through_hysteresis_m"]), 1e-9, "%s hysteresis" % id)
		assert_near(d.see_through_fade_s, float(shared["see_through_fade_s"]), 1e-9, "%s fade" % id)
		assert_near(d.see_through_min_cover_m, float(shared["see_through_min_cover_m"]), 1e-9, "%s minimum cover" % id)
		assert_eq(d.see_through_color, Color(float(c[0]), float(c[1]), float(c[2]), float(c[3])), "%s colour" % id)
	var d2 := _snail()
	assert_true(d2.see_through_radius_m > 0.0 and d2.see_through_hysteresis_m >= 0.0 and d2.see_through_fade_s > 0.0, "usable values")
	assert_true(d2.see_through_min_cover_m > 0.0 and d2.see_through_min_cover_m < d2.sprite_size_m.y, "a cover threshold below a body height")
	assert_true(d2.see_through_color.a > 0.0 and d2.see_through_color.a < 1.0, "a see-through tint, not an opaque one")
	# The reason says the radius reaches past the camera's nearby-monster radius (the trees it dithers for monsters).
	var cam: Dictionary = db().miso_table("camera")
	assert_true(d2.see_through_radius_m >= float(cam.get("occluder_monster_radius_m", 0.0)), "at least the camera's nearby radius")
	# A malformed colour is an error, not a silent default.
	var bad := ContentDB.new()
	bad.canonical = db().canonical
	bad.miso = db().miso.duplicate(true)
	bad.loaded = true
	bad.miso["monsters"]["2"]["see_through_color"] = [1.0, 0.0]
	bad.miso["monsters"]["2"]["reasons"]["see_through_color"] = "test"
	assert_true("; ".join(MonsterDef.build("2", bad).errors).contains("see_through_color"), "a 2-component colour is reported")


# =================================================================================================================
# Materials
# =================================================================================================================

func test_the_fill_reads_and_writes_below_the_players_reference_before_labels() -> void:
	assert_true(MonsterVisual.STENCIL_REF > 0, "a real reference (0 is the cleared buffer)")
	assert_true(MonsterVisual.STENCIL_REF < PlayerVisual.STENCIL_REF,
		"compare_greater draws where stored < ref: the player's %d must stay above it" % PlayerVisual.STENCIL_REF)
	var mat := MonsterVisual.see_through_material()
	assert_eq(MonsterVisual.see_through_material(), mat, "one material shared by every monster")
	var code := mat.shader.code
	assert_true(code.contains("stencil_mode read, write, compare_greater, %d;" % MonsterVisual.STENCIL_REF),
		"reads and writes the monster reference in one pass: %s" % code)
	for mode in ["unshaded", "depth_test_disabled", "depth_draw_never", "cull_disabled", "blend_mix"]:
		assert_true(code.contains(mode), "render mode %s" % mode)
	assert_true(code.contains("instance uniform vec4 see_through_tint") and code.contains("instance uniform float see_through_amount")
		and code.contains("instance uniform float see_through_min_cover"), "tint, fade and minimum cover are per instance")
	assert_true(code.contains("hint_depth_texture") and code.contains("discard"), "skips fragments whose cover is nearer than the minimum")
	assert_eq(mat.render_priority, MonsterVisual.SEE_THROUGH_PRIORITY)
	assert_true(MonsterVisual.SEE_THROUGH_PRIORITY < 0, "before default-priority labels (0), attack FX (8), numbers (10+), HP bar (20)")
	assert_true(MonsterVisual.SEE_THROUGH_PRIORITY < PlayerVisual.FILL_PRIORITY, "and before the player's X-ray")


func test_every_surface_writes_the_stencil_on_shared_copies() -> void:
	# A model mesh like the exported proxies: lit, double-sided surfaces and an unshaded ink shell.
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var arrays := BoxMesh.new().get_mesh_arrays()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var lit := StandardMaterial3D.new()
	lit.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color.BLACK
	am.surface_set_material(0, lit)
	am.surface_set_material(1, ink)
	mi.mesh = am
	root.add_child(mi)
	var v := MonsterVisual.new()
	v.def = _snail()
	v._apply_see_through(root, false)
	var m_lit := mi.get_active_material(0)
	var m_ink := mi.get_active_material(1)
	assert_ne(m_lit, lit, "the lit surface gets a copy")
	assert_ne(m_ink, ink, "the ink shell gets a copy too")
	assert_true(_writes_stencil(m_lit), "lit copy writes the monster reference where visible")
	assert_true(_writes_stencil(m_ink), "ink copy too: no silhouette over the contour lines in front of the body")
	assert_eq(lit.stencil_mode, BaseMaterial3D.STENCIL_MODE_DISABLED, "the shared original is unchanged")
	assert_eq(ink.stencil_mode, BaseMaterial3D.STENCIL_MODE_DISABLED, "the shared ink is unchanged")
	assert_eq((m_lit as BaseMaterial3D).cull_mode, BaseMaterial3D.CULL_DISABLED, "the copy keeps the look")
	assert_true(m_lit.next_pass == null, "no pass chained on the body (the fill is its own mesh)")
	# The fill: one hidden copy of the whole mesh with the shared fill material.
	var fills := v.see_through_fills()
	assert_eq(fills.size(), 1, "one fill per model mesh")
	var f := fills[0]
	assert_eq(f.get_parent(), mi, "under its mesh (follows every pose)")
	assert_eq(f.mesh.get_surface_count(), 1, "one surface: one draw call per model mesh")
	var tri := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	assert_eq((f.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), tri * 2,
		"every surface's triangles: the silhouette has the footprint of the visible model, ink included")
	assert_eq(f.mesh.get_aabb(), am.get_aabb(), "same bounds")
	assert_eq(MonsterVisual.fill_mesh(am), f.mesh, "merged once per source mesh")
	var single := BoxMesh.new()
	assert_eq(MonsterVisual.fill_mesh(single), single, "a one-surface mesh is used as it is")
	assert_eq(f.material_override, MonsterVisual.see_through_material(), "the shared fill")
	assert_false(f.visible, "hidden until the system asks")
	assert_eq(f.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "casts no shadow")
	assert_true(f.ignore_occlusion_culling, "never occlusion-culled: it draws exactly where something hides the monster")
	assert_eq(f.get_instance_shader_parameter(&"see_through_tint"), v.def.see_through_color, "the species tint")
	assert_near(float(f.get_instance_shader_parameter(&"see_through_min_cover")), v.def.see_through_min_cover_m, 1e-6, "the species minimum cover")
	# A second monster of the species uses the same stencil copies (one material each for every monster).
	var root2 := Node3D.new()
	var mi2 := MeshInstance3D.new()
	mi2.mesh = am
	root2.add_child(mi2)
	var v2 := MonsterVisual.new()
	v2.def = _snail()
	v2._apply_see_through(root2, false)
	assert_eq(mi2.get_active_material(0), m_lit, "shared lit copy")
	assert_eq(mi2.get_active_material(1), m_ink, "shared ink copy")
	assert_eq(v2.see_through_fills()[0].mesh, f.mesh, "and the same fill mesh")
	root.free()
	root2.free()
	v.free()
	v2.free()


func test_the_library_proxy_gets_it_on_every_surface() -> void:
	var lib := ProxyLibrary.load_from()
	if not lib.has("Mob_Snail"):
		print("SKIP library proxy: assets/world/_library.glb not present (INCLUDE_WORLD=1)")
		return
	var mon := Node3D.new()
	rig.w.add_node(mon)
	var v := MonsterVisual.new()
	mon.add_child(v)
	v.monster = mon
	v.build(_snail(), lib)
	assert_false(v.is_placeholder, "the real Snail proxy")
	var meshes := _model_meshes(v)
	assert_true(meshes.size() >= 2, "body and shell")
	var ink := 0
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			assert_true(_writes_stencil(m), "%s[%d] writes the monster reference" % [mi.name, s])
			if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				ink += 1
	assert_true(ink >= 1, "the proxy's ink shells are covered (%d)" % ink)
	assert_eq(v.see_through_fills().size(), meshes.size(), "one fill per mesh")
	for f in v.see_through_fills():
		var src := f.get_parent() as MeshInstance3D
		assert_eq(f.mesh.get_surface_count(), 1, "%s: one draw call" % src.name)
		assert_true(f.mesh.get_aabb().is_equal_approx(src.mesh.get_aabb()), "%s: the fill covers the whole mesh" % src.name)
	# The library's own materials stay untouched.
	var fresh := lib.instance("Mob_Snail")
	for n in fresh.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			assert_eq(m.stencil_mode, BaseMaterial3D.STENCIL_MODE_DISABLED, "library %s[%d] unchanged" % [mi.name, s])
	fresh.free()
	lib.free_templates()


func test_the_placeholder_gets_it_in_place() -> void:
	var sentinel := MonsterDef.from_id("1", db())
	var v := _visual(sentinel)
	assert_true(v.is_placeholder, "no library: the fallback body")
	var meshes := _model_meshes(v)
	assert_eq(meshes.size(), 3, "body, head, eye")
	for mi in meshes:
		assert_true(_writes_stencil(mi.material_override), "%s writes the monster reference" % mi.name)
	assert_eq(v.see_through_fills().size(), 3, "a fill under each part")
	for f in v.see_through_fills():
		assert_true(f.get_parent() is MeshInstance3D and not (f.get_parent() is Label3D), "never under the tag")
		assert_eq(f.mesh, (f.get_parent() as MeshInstance3D).mesh, "a one-surface primitive is drawn as it is")


func test_a_rebuild_from_the_placeholder_never_edits_library_materials() -> void:
	var def := _snail()
	var v := _visual(def)
	assert_true(v.is_placeholder, "built without a library: the placeholder")
	# A library holding the Snail's model, whose material is shared like the exported library's.
	var lib := ProxyLibrary.new()
	var tmpl := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var shared := StandardMaterial3D.new()
	mi.material_override = shared
	tmpl.add_child(mi)
	lib._templates[def.model] = tmpl
	lib._heights[def.model] = def.sprite_size_m.y
	v.build(def, lib)
	assert_false(v.is_placeholder, "rebuilt with the library model")
	assert_eq(shared.stencil_mode, BaseMaterial3D.STENCIL_MODE_DISABLED, "the library's shared material is untouched")
	var model_mi: MeshInstance3D = null
	for n in _model_meshes(v):
		model_mi = n
	assert_true(model_mi != null and model_mi.material_override != shared and _writes_stencil(model_mi.material_override),
		"the model draws with a stencil-writing copy")
	tmpl.free()


# =================================================================================================================
# Toggle, fade, death
# =================================================================================================================

func test_toggle_fades_in_and_out() -> void:
	var def := _snail()
	var v := _visual(def)
	var fade := def.see_through_fade_s
	assert_false(v.is_see_through(), "off at spawn")
	v.step_see_through(fade)
	for f in v.see_through_fills():
		assert_false(f.visible, "nothing drawn while off")
	v.set_see_through(true)
	assert_true(v.is_see_through(), "requested")
	v.step_see_through(fade * 0.5)
	assert_near(v.see_through_amount, 0.5, 1e-4, "half way after half the fade")
	for f in v.see_through_fills():
		assert_true(f.visible, "shown while fading in")
		assert_near(float(f.get_instance_shader_parameter(&"see_through_amount")), 0.5, 1e-4, "the fill's alpha follows")
	v.advance(fade)
	assert_near(v.see_through_amount, 1.0, 1e-6, "advance() steps it too: fully on")
	v.set_see_through(false)
	v.step_see_through(fade * 0.25)
	assert_near(v.see_through_amount, 0.75, 1e-4, "fading out")
	v.step_see_through(fade)
	assert_near(v.see_through_amount, 0.0, 1e-6, "off")
	for f in v.see_through_fills():
		assert_false(f.visible, "hidden again (no draw call while off)")


func test_dying_drops_it_at_once_and_the_fill_takes_no_flash_or_fade() -> void:
	var def := _snail()
	var v := _visual(def)
	v.set_see_through(true)
	v.step_see_through(def.see_through_fade_s)
	assert_near(v.see_through_amount, 1.0, 1e-6, "on")
	# The hit flash goes on the body, never on the fill.
	v.on_hit(0.5)
	v.advance(0.01)
	for f in v.see_through_fills():
		assert_true(f.material_overlay == null, "no flash overlay on the fill")
	var flashed := false
	for mi in _model_meshes(v):
		flashed = flashed or mi.material_overlay != null
	assert_true(flashed, "while the body flashes")
	v.start_death_fade(def.die_fade_s)
	assert_false(v.is_see_through(), "dropped at the first frame of the death fade")
	assert_near(v.see_through_amount, 0.0, 1e-6, "no fade-out: the body leaves the opaque pass")
	for f in v.see_through_fills():
		assert_false(f.visible, "hidden at once")
	v.set_see_through(true)
	assert_false(v.is_see_through(), "a dying monster ignores requests")
	v.advance(def.die_fade_s * 0.5)
	for f in v.see_through_fills():
		assert_false(f.visible, "still hidden while fading")
		assert_near(f.transparency, 0.0, 1e-6, "the death fade never touches the fill")


# =================================================================================================================
# MonsterSystem
# =================================================================================================================

func test_the_system_turns_silhouettes_on_by_distance_to_the_player() -> void:
	var def := _snail()
	var r := def.see_through_radius_m
	var h := def.see_through_hysteresis_m
	assert_true(h > 0.2, "the test needs some hysteresis")
	var p := rig.spawn_player(Vector3.ZERO)
	var near := rig.spawn("2", Vector3(r * 0.4, 0, 0))
	var edge := rig.spawn("2", Vector3(r - 0.1, 0, 0))
	var beyond := rig.spawn("2", Vector3(r + h * 0.5, 0, 0))
	var far := rig.spawn("2", Vector3(r + h + 5.0, 0, 0))
	assert_eq(rig.system.update_see_through(), 2, "two within the radius")
	assert_true(near.visual.is_see_through(), "near: on")
	assert_true(edge.visual.is_see_through(), "at the edge: on")
	assert_false(beyond.visual.is_see_through(), "past the radius: off")
	assert_false(far.visual.is_see_through(), "far: off")
	# The player walks toward them: `beyond` enters the radius.
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(h * 0.5 + 0.05, 0, 0)))
	rig.system.update_see_through()
	assert_true(beyond.visual.is_see_through(), "entered the radius: on")
	assert_false(far.visual.is_see_through(), "far still off")
	# Back to the start: `beyond` is past the radius again but within the hysteresis: it stays on.
	p.teleport(Transform3D(Basis.IDENTITY, Vector3.ZERO))
	rig.system.update_see_through()
	assert_true(beyond.visual.is_see_through(), "hysteresis keeps it on")
	# Further back: beyond radius + hysteresis, it goes off; `edge` (now just past the radius) stays on.
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(-h * 0.6, 0, 0)))
	rig.system.update_see_through()
	assert_false(beyond.visual.is_see_through(), "past radius + hysteresis: off")
	assert_true(edge.visual.is_see_through(), "the edge monster is inside its hysteresis")
	assert_true(near.visual.is_see_through(), "near stays on")
	# The visuals fade with their own frames.
	near.visual.advance(def.see_through_fade_s)
	assert_near(near.visual.see_through_amount, 1.0, 1e-6, "faded in")
	for f in near.visual.see_through_fills():
		assert_true(f.visible, "drawn")


func test_a_killed_monster_loses_it_and_no_player_means_none() -> void:
	var p := rig.spawn_player(Vector3.ZERO)
	var a := rig.spawn("2", Vector3(2, 0, 0))
	var b := rig.spawn("2", Vector3(-3, 0, 0))
	rig.system.update_see_through()
	a.visual.advance(a.def.see_through_fade_s)
	assert_true(a.visual.is_see_through() and b.visual.is_see_through(), "both near: on")
	a.die()
	assert_false(a.visual.is_see_through(), "killed: off at once")
	assert_near(a.visual.see_through_amount, 0.0, 1e-6, "no lingering silhouette")
	assert_eq(rig.system.update_see_through(), 1, "only the living one")
	assert_false(a.visual.is_see_through(), "the system never turns a dying monster back on")
	# Without a player (no player attached, or freed), nothing shows.
	rig.system.player = null
	assert_eq(rig.system.update_see_through(), 0, "no player: none")
	assert_false(b.visual.is_see_through(), "turned off")
	rig.system.player = p
	assert_eq(rig.system.update_see_through(), 1, "back with the player")
