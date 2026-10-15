extends TestCase
## The character look is an Adaptation (#67, decision #59): data/misostory/appearance.json records it, unverified,
## and agrees with the code that saves and migrates it (CharacterAppearance, which has no ContentDB) and with the
## model the game shows (PlayerVisual's presets). With the art pack installed it also agrees with the pack's
## customization.json and the Beginner presets' base_recipe; those tests print SKIP without the pack.

var art: ArtPack


func before_each() -> void:
	art = ArtPack.load_installed()


func _table() -> Dictionary:
	var t: Variant = db().miso_table("appearance")
	if not (t is Dictionary):
		fail("data/misostory/appearance.json is missing")
		return {}
	return t


func test_the_look_is_an_unverified_adaptation_decided_in_59() -> void:
	var t := _table()
	assert_eq(String(t.get("kind", "")), "misostory_adaptation")
	assert_true(String(t.get("decision", "")).begins_with("#59"), "decision cites #59: %s" % t.get("decision"))
	assert_eq(t.get("verified"), false, "unverified")
	assert_eq(t.get("change_after_creation"), false, "chosen at creation only: Maple Island has no salon")


func test_the_data_agrees_with_the_code() -> void:
	var t := _table()
	var choices: Dictionary = t.get("choices", {})
	for key in CharacterAppearance.KEYS:
		assert_eq(int(choices.get(key, -1)), CharacterAppearance.choices(key), "%s choices" % key)
	assert_eq((t.get("face_styles", []) as Array).size(), CharacterAppearance.choices(CharacterAppearance.FACE),
		"one face style per face choice")
	var defaults: Dictionary = t.get("defaults", {})
	for gender in ["male", "female"]:
		var d: Dictionary = defaults.get(gender, {})
		var look := {}
		for key in CharacterAppearance.KEYS:
			look[key] = int(d.get(key, -1))
		assert_eq(look, CharacterAppearance.default_for(gender), "%s default" % gender)
		assert_eq(String(d.get("preset", "")), PlayerVisual.preset_for(gender), "%s preset" % gender)
	assert_eq(String(t.get("no_gender_default", "")), CharacterAppearance.DEFAULT_GENDER)
	assert_eq(SaveMigrations.V3_DEFAULT_LOOKS, CharacterAppearance.DEFAULTS, "the v2 -> v3 step gave today's defaults")


func _skip(test: String) -> bool:
	if art.present():
		return false
	print("SKIP %s: no art pack installed (bash scripts/art_pack.sh fetch)" % test)
	return true


func test_the_choices_are_the_pack_customization() -> void:
	if _skip("test_the_choices_are_the_pack_customization"):
		return
	assert_eq(art.ids(ArtPack.HAIR).size(), CharacterAppearance.choices(CharacterAppearance.HAIR_STYLE), "hair files")
	assert_eq(art.face_styles(), PackedStringArray(_table().get("face_styles", [])), "faces, in the pack's order")
	assert_eq(art.skin_count(), CharacterAppearance.choices(CharacterAppearance.SKIN), "skin palette")
	for i in CharacterAppearance.choices(CharacterAppearance.HAIR_STYLE):
		assert_ne(art.model(ArtPack.HAIR, str(i)), "", "hair %d has a module" % i)
	for style in art.face_styles():
		assert_ne(art.model(ArtPack.FACE, style), "", "face %s has a module" % style)


func test_each_default_is_its_preset_base_recipe() -> void:
	if _skip("test_each_default_is_its_preset_base_recipe"):
		return
	for gender in ["male", "female"]:
		var r := art.base_recipe(PlayerVisual.preset_for(gender))
		assert_eq({"hair_style": int(r.get("hair_style", -1)), "face": int(r.get("face", -1)), "skin": int(r.get("skin", -1))},
			CharacterAppearance.default_for(gender), "%s: %s" % [gender, r])
