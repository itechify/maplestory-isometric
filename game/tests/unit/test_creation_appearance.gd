extends TestCase
## Character creation picks hair style, face and skin (#67): the model offers each gender's default look until the
## player picks, new_game() puts the look on the character and into its save, a look out of range is refused like a
## bad gender, and paths without a creation screen (quick start) get the gender's default. Gender, weapon and AP are
## test_shell_creation.gd's.

var root := ""


func before_each() -> void:
	root = "user://_tests/creation_look_%d_%d" % [Time.get_ticks_usec(), randi()]


func after_each() -> void:
	var d := DirAccess.open(root)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(root.path_join(f))
	DirAccess.remove_absolute(root)


## [GameState, SaveService, bus]: a Game node saving into `root`.
func _game() -> Array:
	var svc := SaveService.new()
	svc.save_dir = root
	svc.db = db()
	svc.log_failures = false
	svc.can_save_override = func() -> bool: return true
	var bus: Node = load("res://scripts/autoload/events.gd").new()
	svc.event_bus = bus
	var g := GameState.new()
	g.db = db()
	g.save_service = svc
	g.event_bus = bus
	g.log_warnings = false
	svc.game_node = g
	return [g, svc, bus]


func _free(parts: Array) -> void:
	for n: Node in parts:
		n.free()


func test_the_model_shows_the_gender_default_until_the_player_picks() -> void:
	var m := CreationModel.new(db())
	m.gender = "male"
	assert_eq(m.look(), {"hair_style": 3, "face": 0, "skin": 0}, "male default")
	m.gender = "female"
	assert_eq(m.look(), {"hair_style": 2, "face": 0, "skin": 3}, "switching gender shows the female default")
	assert_true(m.pick(CharacterAppearance.FACE, 2), "face 2")
	assert_true(m.pick(CharacterAppearance.SKIN, 1), "skin 1")
	assert_false(m.pick(CharacterAppearance.HAIR_STYLE, 6), "there is no seventh hair style")
	assert_false(m.pick("hat", 0), "not an appearance choice")
	assert_eq(m.look(), {"hair_style": 2, "face": 2, "skin": 1}, "picked choices replace the default")
	m.gender = "male"
	assert_eq(m.look(), {"hair_style": 3, "face": 2, "skin": 1}, "picks survive a gender switch; the rest follows it")
	assert_eq(m.params()["appearance"], {"hair_style": 3, "face": 2, "skin": 1}, "Start carries the whole look")


func test_recommended_keeps_the_look() -> void:
	var m := CreationModel.new(db())
	m.pick(CharacterAppearance.HAIR_STYLE, 5)
	m.use_defaults()
	assert_eq(int(m.look()[CharacterAppearance.HAIR_STYLE]), 5, "Recommended is about stats and the weapon")


func test_a_new_character_keeps_its_look_through_save_and_load() -> void:
	var parts := _game()
	var g: GameState = parts[0]
	var svc: SaveService = parts[1]
	var m := CreationModel.new(db())
	m.name = "Looker"
	m.gender = "female"
	m.pick(CharacterAppearance.HAIR_STYLE, 0)
	m.pick(CharacterAppearance.FACE, 2)
	m.pick(CharacterAppearance.SKIN, 2)
	var p := m.params()
	p["slot"] = "look"
	assert_eq(g.new_game(p), OK, ", ".join(g.last_creation_errors))
	assert_eq(g.character.appearance, {"hair_style": 0, "face": 2, "skin": 2}, "the live character")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("look.json")))
	assert_eq(raw["character"]["appearance"], {"hair_style": 0.0, "face": 2.0, "skin": 2.0}, "the save file")
	g.close_game()
	assert_eq(g.load_game("look"), OK, "load")
	assert_eq(g.character.appearance, {"hair_style": 0, "face": 2, "skin": 2}, "loaded back")
	assert_eq(svc.read_save("look").character.appearance, {"hair_style": 0, "face": 2, "skin": 2})
	_free(parts)


func test_a_look_out_of_range_is_refused() -> void:
	var parts := _game()
	var g: GameState = parts[0]
	var m := CreationModel.new(db())
	m.name = "Looker"
	var p := m.params()
	p["save"] = false
	p["appearance"] = {"hair_style": 6, "face": 0, "skin": 0}
	assert_eq(g.new_game(p), ERR_INVALID_PARAMETER, "hair style 6 does not exist")
	assert_true(", ".join(g.last_creation_errors).contains("hair_style"), ", ".join(g.last_creation_errors))
	_free(parts)


func test_quick_start_gets_the_gender_default() -> void:
	var parts := _game()
	var g: GameState = parts[0]
	assert_eq(g.new_game({"save": false}), OK)
	assert_eq(g.character.gender, "", "the quick start has no gender")
	assert_eq(g.character.appearance, {"hair_style": 3, "face": 0, "skin": 0}, "so the male default")
	var p := CharacterFactory.default_params(db())
	p["gender"] = "female"
	p["save"] = false
	assert_eq(g.new_game(p), OK, ", ".join(g.last_creation_errors))
	assert_eq(g.character.appearance, {"hair_style": 2, "face": 0, "skin": 3}, "no look given: the female default")
	_free(parts)
