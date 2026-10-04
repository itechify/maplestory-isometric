extends TestCase
## Character creation (CreationModel, the logic behind the creation screen): name validation through
## CharacterFactory, gender, the creation weapons with their canonical W.ATK and speed, the 9 creation AP over
## STR/DEX/INT/LUK on top of 4/4/4/4, and a live StatCalculator preview that equals the created character. Every
## expected number is read from canonical data, except the literal pins in test_canonical_creation_numbers.


func _model() -> CreationModel:
	return CreationModel.new(db())


func _beginner() -> Dictionary:
	return db().formula("beginner")


func test_canonical_creation_numbers() -> void:
	var m := _model()
	# MeowDB's published values (formulas/beginner.json, items 541/576/585), pinned literally once.
	assert_eq(m.creation_ap(), 9, "9 creation AP")
	assert_eq(m.stat_keys(), PackedStringArray(["str", "dex", "int", "luk"]), "allocatable stats")
	for k in m.stat_keys():
		assert_eq(m.starting_stat(k), 4, "%s starts at 4" % k)
	var by_id := {}
	for w in m.weapons():
		by_id[w["id"]] = w
	assert_eq(by_id.keys().size(), 3, "three creation weapons")
	assert_eq([by_id["541"]["name"], by_id["541"]["watk"], by_id["541"]["speed"]], ["Sword", 17, 4], "Sword")
	assert_eq([by_id["576"]["name"], by_id["576"]["watk"], by_id["576"]["speed"]], ["Hand Axe", 17, 4], "Hand Axe")
	assert_eq([by_id["585"]["name"], by_id["585"]["watk"], by_id["585"]["speed"]], ["Wooden Club", 19, 5], "Wooden Club")


func test_weapons_come_from_the_item_records() -> void:
	for w in _model().weapons():
		var rec := db().item(String(w["id"]))
		assert_true(bool(rec.get("beginner_creation_weapon", false)), "%s is flagged a creation weapon" % w["id"])
		assert_eq(int(w["watk"]), int((rec.get("stats", {}) as Dictionary).get("watk", -1)), "%s W.ATK" % w["id"])
		var wp: Dictionary = rec.get("weapon", {})
		assert_eq(int(w["speed"]), int(wp.get("attack_speed", -1)), "%s speed tier" % w["id"])
		assert_eq(String(w["speed_name"]), String(wp.get("attack_speed_name", "")), "%s speed name" % w["id"])
	assert_eq(_model().weapons().size(), CharacterFactory.creation_weapon_ids(db()).size(), "every creation weapon offered")


func test_defaults_are_the_quick_start_spread_without_a_name() -> void:
	var m := _model()
	var q := CharacterFactory.default_params(db())
	assert_eq(m.name, "", "the player types the name")
	assert_eq(m.weapon_id, String(q["weapon_id"]), "quick-start weapon")
	assert_eq(m.ap_remaining(), 0, "the quick-start spread places all creation AP")
	assert_eq(m.gender, GameState.GENDERS[0], "a gender is preselected")
	assert_false(m.is_valid(), "invalid until named")
	m.name = "Maple"
	assert_true(m.is_valid(), "valid with a name: %s" % ", ".join(m.errors()))


func test_ap_spread_rules() -> void:
	var m := _model()
	m.clear_ap()
	assert_eq(m.ap_remaining(), m.creation_ap(), "all AP to place")
	assert_false(m.remove_ap("str"), "never below the starting value")
	assert_false(m.add_ap("hp"), "only allocatable stats")
	assert_true(m.add_ap("dex", 5), "5 DEX")
	assert_true(m.add_ap("luk", 4), "4 LUK")
	assert_eq(m.ap_remaining(), 0, "all placed")
	assert_false(m.add_ap("str"), "no AP beyond the creation total")
	assert_false(m.can_add("int"), "can_add follows")
	assert_eq(m.stat_total("dex"), m.starting_stat("dex") + 5, "DEX total")
	assert_true(m.remove_ap("dex", 2), "take 2 back")
	assert_eq(m.ap_remaining(), 2, "2 to place again")
	m.name = "Maple"
	assert_false(m.is_valid(), "unplaced AP blocks Start")
	assert_true(m.errors()[0].contains("creation AP"), "CharacterFactory says why: %s" % m.errors()[0])
	m.add_ap("int", 2)
	assert_true(m.is_valid(), "valid again")
	assert_eq(m.params()["ap"], {"dex": 3, "luk": 4, "int": 2}, "params carry only placed stats")


func test_name_validation_uses_the_factory_rules() -> void:
	var rules: Dictionary = CharacterFactory.rules_table(db())["name_rules"]
	var m := _model()
	for bad in ["", "abc", "x".repeat(int(rules["max_length"]) + 1), "Ma ple", "Mäple", "Maple\n", "Ma-ple"]:
		m.name = bad
		assert_false(m.name_errors().is_empty(), "'%s' refused" % bad.c_escape())
		assert_false(m.is_valid(), "'%s' blocks Start" % bad.c_escape())
	for good in ["Mapl", "Maple123", "x".repeat(int(rules["max_length"]))]:
		m.name = good
		assert_true(m.name_errors().is_empty(), "'%s' accepted" % good)


func test_gender_rules() -> void:
	var m := _model()
	m.name = "Maple"
	for g in GameState.GENDERS:
		m.gender = g
		assert_true(m.is_valid(), "%s accepted" % g)
	m.gender = "other"
	assert_false(m.is_valid(), "unknown gender refused")
	assert_eq(GameState.validate_gender(""), PackedStringArray(), "unknown ('') is allowed for quick starts")
	assert_false(GameState.validate_gender(3).is_empty(), "not a string")


func test_unknown_weapon_refused() -> void:
	var m := _model()
	m.name = "Maple"
	m.weapon_id = "558"  # Razor: a level-5 starter weapon, not a creation weapon
	assert_false(m.is_valid(), "Razor refused")
	m.weapon_id = "nope"
	assert_false(m.is_valid(), "unknown id refused")


func test_preview_is_stat_calculator_compute() -> void:
	var m := _model()
	m.clear_ap()
	m.add_ap("dex", 6)
	m.add_ap("luk", 3)
	m.weapon_id = "541"
	var b := _beginner()
	var base := {"str": 4, "dex": 10, "int": 4, "luk": 7}
	var hp_mp: Dictionary = b["hp_mp"]
	var bonuses := ItemDef.of("541", db()).bonuses
	var want := StatCalculator.compute(String(b["class_slug"]), int(b["starting_level"]), base, int(hp_mp["base_hp"]),
		int(hp_mp["base_mp"]), bonuses, "541", db())
	var got := m.preview()
	for k in ["acc", "avoid", "damage_min", "damage_max", "watk", "max_hp", "max_mp", "str", "dex", "int", "luk"]:
		assert_eq(got[k], want[k], "preview %s" % k)


func test_preview_works_with_a_partial_spread() -> void:
	var m := _model()
	m.clear_ap()
	m.add_ap("dex", 2)
	var p := m.preview()
	assert_eq(int(p["dex"]), 6, "partial spread previewed")
	assert_true(int(p["damage_max"]) >= int(p["damage_min"]) and int(p["damage_min"]) >= 1, "a damage range")


func test_preview_equals_the_created_character() -> void:
	for spread: Dictionary in [{"str": 9}, {"dex": 9}, {"str": 3, "dex": 3, "int": 2, "luk": 1}]:
		for wid in CharacterFactory.creation_weapon_ids(db()):
			var m := _model()
			m.name = "Preview"
			m.clear_ap()
			for k in spread:
				m.add_ap(k, int(spread[k]))
			m.weapon_id = wid
			var created := CharacterFactory.create(m.params(), db())
			assert_true(created.ok, "created %s %s" % [spread, wid])
			var snap := StatCalculator.snapshot(created.character, db())
			var p := m.preview()
			for k in ["acc", "avoid", "damage_min", "damage_max", "watk", "max_hp", "max_mp"]:
				assert_eq(p[k], snap[k], "%s %s %s" % [spread, wid, k])


func test_new_game_takes_the_creation_params() -> void:
	var root := "user://_tests/shell_creation_%d" % Time.get_ticks_usec()
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
	var m := _model()
	m.name = "Maple"
	m.gender = "female"
	m.clear_ap()
	m.add_ap("str", 5)
	m.add_ap("dex", 4)
	m.weapon_id = "576"
	var p := m.params()
	p["slot"] = "slot7"
	assert_eq(g.new_game(p), OK, "new game: %s" % ", ".join(g.last_creation_errors))
	var c := g.character
	assert_eq([c.name, c.gender, c.equipment.weapon_id()], ["Maple", "female", "576"], "name, gender, weapon")
	assert_eq([c.get_base_stat("str"), c.get_base_stat("dex"), c.get_base_stat("int"), c.get_base_stat("luk")],
		[9, 8, 4, 4], "4/4/4/4 + the spread")
	assert_eq(g.current_slot, "slot7", "saved into the chosen slot")
	var r := svc.read_save("slot7")
	assert_true(r.ok() and r.character.gender == "female", "gender persists")
	p["gender"] = "robot"
	assert_eq(g.new_game(p), ERR_INVALID_PARAMETER, "bad gender refused")
	assert_true(c == g.character, "a refused new game leaves the live game alone")
	assert_true(", ".join(g.last_creation_errors).contains("gender"), "the reason names the gender")
	g.free()
	svc.free()
	bus.free()
	var d := DirAccess.open(root)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(root.path_join(f))
	DirAccess.remove_absolute(root)
