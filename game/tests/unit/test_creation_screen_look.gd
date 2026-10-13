extends TestCase
## The creation screen's look (#67): a button per hair style, face and skin feeds CreationModel.pick(), the pressed
## buttons follow the model's look (the gender's default until picked), Start carries the look, and the preview is the
## rigged Beginner wearing it (with the art pack; without it the preview shows the placeholder and nothing breaks).
## None of the new controls reuse the texts or names the playtest driver finds (test_shell_screens.gd covers the rest).

var holder: Node = null


func before_each() -> void:
	holder = Control.new()
	var tree := Engine.get_main_loop() as SceneTree
	var parent := tree.current_scene if tree.current_scene != null else tree.root.get_child(tree.root.get_child_count() - 1)
	parent.add_child(holder)


func after_each() -> void:
	holder.free()


func _screen() -> CreationScreen:
	var s := CreationScreen.new(CreationModel.new(db()))
	holder.add_child(s)
	return s


func _button(s: CreationScreen, key: String, index: int) -> Button:
	return s.find_child("Look_%s_%d" % [key, index], true, false) as Button


func _pressed(s: CreationScreen, key: String) -> Array:
	var out := []
	for i in CharacterAppearance.choices(key):
		var b := _button(s, key, i)
		if b != null and b.button_pressed:
			out.append(i)
	return out


func test_a_button_per_choice() -> void:
	var s := _screen()
	for key in CharacterAppearance.KEYS:
		for i in CharacterAppearance.choices(key):
			assert_true(_button(s, key, i) != null, "Look_%s_%d" % [key, i])
		assert_true(_button(s, key, CharacterAppearance.choices(key)) == null, "no extra %s button" % key)


func test_the_pressed_buttons_follow_the_gender_default_until_picked() -> void:
	var s := _screen()
	s.model.gender = "male"
	s.refresh()
	assert_eq([_pressed(s, "hair_style"), _pressed(s, "face"), _pressed(s, "skin")], [[3], [0], [0]], "male default")
	(s.find_child("Look_skin_2", true, false) as Button).pressed.emit()
	assert_eq(s.model.look()["skin"], 2, "the skin button picks")
	assert_eq(_pressed(s, "skin"), [2], "and shows pressed")
	for b in s.find_children("*", "Button", true, false):
		if (b as Button).text == "Female":
			(b as Button).pressed.emit()
	assert_eq(s.model.gender, "female")
	assert_eq([_pressed(s, "hair_style"), _pressed(s, "face"), _pressed(s, "skin")], [[2], [0], [2]],
		"the female default hair and face; the picked skin stays")
	(s.find_child("Look_hair_style_4", true, false) as Button).pressed.emit()
	(s.find_child("Look_face_1", true, false) as Button).pressed.emit()
	s.name_edit.text = "Looker"
	s.name_edit.text_changed.emit("Looker")
	var started: Array = []
	s.start_pressed.connect(func(p: Dictionary) -> void: started.append(p))
	assert_true(s.submit(), s.errors_label.text)
	assert_eq(started[0]["appearance"], {"hair_style": 4, "face": 1, "skin": 2}, "Start carries the look")


func test_new_controls_never_take_the_driver_texts_or_names() -> void:
	var s := _screen()
	var taken := ["Male", "Female", "Recommended", "Clear", "Back", "Start"]
	for key in CharacterAppearance.KEYS:
		for i in CharacterAppearance.choices(key):
			var b := _button(s, key, i)
			assert_false(b.text in taken, "%s says '%s'" % [b.name, b.text])
			assert_false(String(b.name).begins_with("Plus_") or String(b.name).begins_with("Minus_")
				or String(b.name).begins_with("Weapon_"), String(b.name))


func test_the_preview_wears_the_look() -> void:
	var s := _screen()
	var preview: PlayerVisual = s.preview_visual()
	assert_true(preview != null, "a 3D preview")
	if not ArtPack.load_installed().present():
		print("SKIP test_the_preview_wears_the_look (rig part): no art pack installed (bash scripts/art_pack.sh fetch)")
		assert_false(preview.rigged(), "without the pack: the placeholder")
		return
	assert_true(preview.rigged(), "the rigged Beginner")
	s.model.gender = "female"
	s.refresh()
	assert_eq(preview.preset, "Beginner_Female", "the preview follows the gender")
	(s.find_child("Look_hair_style_0", true, false) as Button).pressed.emit()
	assert_eq(preview.look, {"hair_style": 0, "face": 0, "skin": 3}, "and the look")
	var ap := preview.model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_eq(String(ap.current_animation), "idle", "standing in its idle clip")
