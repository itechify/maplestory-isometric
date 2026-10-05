extends TestCase
## Presentation pieces: damage numbers (styles, stacking, lifetime), attack FX sized from the canonical hit box, and
## the monster visual (proxy fit to the canonical sprite height, the labelled placeholder, HP bar, death fade).

var host: Node3D


func before_each() -> void:
	host = Node3D.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(host)


func after_each() -> void:
	host.free()


func test_damage_numbers_styles_stack_and_expire() -> void:
	var fx := DamageNumbers.new()
	host.add_child(fx)
	var target := Node.new()
	var a := fx.dealt(Vector3(0, 1, 0), 23, false, target)
	var b := fx.dealt(Vector3(0, 1, 0), 31, true, target)
	var c := fx.taken(Vector3(5, 2, 0), 4)
	var d := fx.miss(Vector3(-5, 1, 0))
	assert_eq(fx.live_texts(), PackedStringArray(["23", "31", "4", "MISS"]))
	assert_true(a.modulate.is_equal_approx(DamageNumbers.STYLES[DamageNumbers.STYLE_DEALT].fill), "dealt colour")
	assert_true(b.modulate.is_equal_approx(DamageNumbers.STYLES[DamageNumbers.STYLE_CRIT].fill), "critical colour")
	assert_true(c.modulate.is_equal_approx(DamageNumbers.STYLES[DamageNumbers.STYLE_TAKEN].fill), "taken colour")
	assert_true(a.no_depth_test and a.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "drawn over terrain, facing the camera")
	assert_true(a.outline_size > 0, "outlined")
	assert_true(b.global_position.y > a.global_position.y + 0.1, "a second hit on the same target stacks above")
	assert_true(b.pixel_size > a.pixel_size, "a critical is bigger")
	assert_eq(d.text, "MISS")
	fx.advance(DamageNumbers.LIFE_S * 0.5)
	assert_true(a.global_position.y > 1.0, "numbers rise")
	fx.advance(DamageNumbers.LIFE_S)
	assert_eq(fx.live_count(), 0, "and expire")
	target.free()


func test_numbers_of_nearby_targets_do_not_overlap() -> void:
	var fx := DamageNumbers.new()
	host.add_child(fx)
	var a := fx.dealt(Vector3(0, 1.0, 0), 12, false, "monster")
	var b := fx.taken(Vector3(0.1, 1.1, 0), 3, "player")
	assert_true(b.global_position.y - a.global_position.y > a.pixel_size * DamageNumbers.FONT_SIZE * 0.8, "moved a line up")


func test_attack_fx_are_sized_from_the_hit_box_and_expire() -> void:
	var db_ := db()
	var fx := AttackFx.new()
	host.add_child(fx)
	var sword := WeaponProfile.for_weapon_id("541", db_)
	var box := CombatReach.attack_box_px(sword, "swingO1", true, 1)
	var s := fx.swing(Vector3.ZERO, Vector3.RIGHT, box) as MeshInstance3D
	var aabb := s.mesh.get_aabb()
	assert_near(maxf(aabb.end.z, -aabb.position.z), WorldScale.actor(box.end.x), 0.05, "the slash reaches the box's far edge")
	var t := fx.stab(Vector3.ZERO, Vector3.RIGHT, CombatReach.attack_box_px(sword, "stabO1", true, 1))
	assert_true(t != null)
	var p := fx.punch(Vector3.ZERO, Vector3.RIGHT, CombatReach.attack_box_px(WeaponProfile.bare_hands(db_), "stabO1", true, 1))
	assert_near(p.global_position.x, WorldScale.actor(64.0), 0.01, "the punch lands at the canonical 64 px reach")
	fx.spark(Vector3.UP)
	assert_eq(fx.live_count(), 4)
	fx.advance(1.0)
	assert_eq(fx.live_count(), 0, "all effects are short-lived")


func test_monster_visual_fits_the_canonical_sprite_and_labels_placeholders() -> void:
	var lib := ProxyLibrary.load_from()
	var snail := MonsterDef.from_id("2", db())
	var v := MonsterVisual.new()
	host.add_child(v)
	v.build(snail, lib)
	if lib.has("Mob_Snail"):
		assert_false(v.is_placeholder, "Snail uses the Iteration One proxy")
		assert_near(v.height_m, snail.sprite_size_m.y, 1e-3, "fitted to the canonical sprite height")
	else:
		print("SKIP proxy fit: assets/world/_library.glb not present (INCLUDE_WORLD=1)")
	var sentinel := MonsterDef.from_id("1", db())
	assert_eq(sentinel.model, "Mob_TutorialJrSentinel", "the Tutorial Jr. Sentinel has a proxy model")
	var s := MonsterVisual.new()
	host.add_child(s)
	s.build(sentinel, lib)
	if lib.has("Mob_TutorialJrSentinel"):
		assert_false(s.is_placeholder, "Tutorial Jr. Sentinel uses its proxy")
		assert_near(s.height_m, sentinel.sprite_size_m.y, 1e-3, "fitted to the canonical sprite height")
	else:
		print("SKIP Sentinel proxy fit: assets/world/_library.glb not present (INCLUDE_WORLD=1)")
	# Without a library: the stone fallback body, named, at the canonical sprite size, never called a placeholder.
	var f := MonsterVisual.new()
	host.add_child(f)
	f.build(sentinel, null)
	assert_true(f.is_placeholder, "no library: the fallback body")
	var tag := f.model.find_child("PlaceholderTag", true, false) as Label3D
	assert_true(tag != null and tag.text == "Tutorial Jr. Sentinel", "named: %s" % (tag.text if tag != null else "no tag"))
	assert_false(tag != null and tag.text.to_lower().contains("placeholder"), "no player-visible 'placeholder'")
	assert_near(f.height_m, sentinel.sprite_size_m.y, 1e-6, "at the canonical sprite size")
	lib.free_templates()


func test_hp_bar_shows_when_damaged_and_the_body_fades_over_the_die_time() -> void:
	var def := MonsterDef.from_id("4", db())
	var v := MonsterVisual.new()
	var mon := Node3D.new()
	host.add_child(mon)
	mon.add_child(v)
	v.monster = mon
	v.build(def, null)
	assert_false(v.hp_bar.visible, "no bar at full HP")
	v.on_hit(0.5)
	assert_true(v.hp_bar.visible, "bar once damaged")
	var faded := [false]
	v.faded_out.connect(func() -> void: faded[0] = true)
	v.start_death_fade(def.die_fade_s)
	assert_false(v.hp_bar.visible, "no bar while dying")
	v.advance(def.die_fade_s * 0.5)
	assert_false(faded[0], "still fading halfway")
	v.advance(def.die_fade_s * 0.5 + 0.01)
	assert_true(faded[0], "faded out after the canonical %.2f s" % def.die_fade_s)
