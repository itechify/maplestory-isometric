extends TestCase
## A character's appearance (#67: hair style, face and skin, an Adaptation chosen at creation only) without the art
## pack: each gender's default is its Beginner preset's look, unknown or missing values fall back to that default one
## by one, and the character keeps its appearance through to_dict / from_dict.


func test_each_gender_defaults_to_its_beginner_preset_look() -> void:
	# The pack's characters/manifest.json base_recipe of Beginner_Male and Beginner_Female.
	assert_eq(CharacterAppearance.default_for("male"), {"hair_style": 3, "face": 0, "skin": 0}, "Beginner_Male")
	assert_eq(CharacterAppearance.default_for("female"), {"hair_style": 2, "face": 0, "skin": 3}, "Beginner_Female")


func test_an_unknown_gender_gets_the_male_default_like_the_player_model() -> void:
	assert_eq(CharacterAppearance.default_for(""), {"hair_style": 3, "face": 0, "skin": 0}, "quick start")
	assert_eq(CharacterAppearance.default_for("robot"), {"hair_style": 3, "face": 0, "skin": 0}, "anything else")
	assert_eq(PlayerVisual.preset_for(""), "Beginner_Male", "the model shown for no gender is the male preset")


func test_the_choices_are_six_hair_styles_three_faces_and_four_skins() -> void:
	assert_eq(CharacterAppearance.choices(CharacterAppearance.HAIR_STYLE), 6)
	assert_eq(CharacterAppearance.choices(CharacterAppearance.FACE), 3)
	assert_eq(CharacterAppearance.choices(CharacterAppearance.SKIN), 4)


func test_resolve_keeps_valid_choices_and_replaces_each_bad_one_with_the_default() -> void:
	assert_eq(CharacterAppearance.resolve({"hair_style": 5, "face": 2, "skin": 1}, "female"),
		{"hair_style": 5, "face": 2, "skin": 1}, "valid choices are kept")
	assert_eq(CharacterAppearance.resolve({"hair_style": 5.0, "face": 1.0, "skin": 2.0}, "male"),
		{"hair_style": 5, "face": 1, "skin": 2}, "whole numbers from JSON are choices")
	assert_eq(CharacterAppearance.resolve({"hair_style": 9, "face": "sleepy", "skin": 1.5}, "female"),
		{"hair_style": 2, "face": 0, "skin": 3}, "out of range, not a number, not whole: the female default")
	assert_eq(CharacterAppearance.resolve({"skin": 2}, "male"), {"hair_style": 3, "face": 0, "skin": 2},
		"missing keys: the default")
	assert_eq(CharacterAppearance.resolve(null, "female"), {"hair_style": 2, "face": 0, "skin": 3}, "nothing at all")
	assert_eq(CharacterAppearance.resolve({"hair_style": -1, "face": 0, "skin": 0, "hat": 3}, "male"),
		{"hair_style": 3, "face": 0, "skin": 0}, "negative is out of range; unknown keys are dropped")


func test_problems_name_every_choice_out_of_range() -> void:
	assert_eq(CharacterAppearance.problems({"hair_style": 0, "face": 2, "skin": 3}), PackedStringArray(), "valid")
	assert_eq(CharacterAppearance.problems(null), PackedStringArray(), "none given: the gender's default")
	assert_eq(CharacterAppearance.problems({}), PackedStringArray(), "empty: the gender's default")
	var bad := CharacterAppearance.problems({"hair_style": 6, "face": "x", "skin": -1})
	assert_eq(bad.size(), 3, str(bad))
	assert_true(", ".join(bad).contains("hair_style"), str(bad))
	assert_false(CharacterAppearance.problems("hair 3").is_empty(), "not an object")


func test_the_character_keeps_its_appearance_through_to_dict_and_from_dict() -> void:
	var c := CharacterState.new()
	c.gender = "female"
	c.appearance = {"hair_style": 4, "face": 2, "skin": 1}
	var d := c.to_dict()
	assert_eq(d["appearance"], {"hair_style": 4, "face": 2, "skin": 1}, "saved")
	var back := CharacterState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(back.appearance, {"hair_style": 4, "face": 2, "skin": 1}, "loaded back as whole numbers")


func test_a_character_without_an_appearance_gets_its_gender_default() -> void:
	assert_eq(CharacterState.from_dict({"gender": "female"}).appearance, {"hair_style": 2, "face": 0, "skin": 3})
	assert_eq(CharacterState.from_dict({"gender": ""}).appearance, {"hair_style": 3, "face": 0, "skin": 0})
	assert_eq(CharacterState.from_dict({"gender": "male", "appearance": {"face": 7}}).appearance,
		{"hair_style": 3, "face": 0, "skin": 0}, "a bad value falls back")
