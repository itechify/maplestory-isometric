extends TestCase
## SaveService end to end through a private Game node: save -> load gives a deep-equal CharacterState.to_dict()
## (inventory, equipment, quests, location, flags ...), the file envelope, can_save blocking, corrupt files, map
## validation, list_saves and delete. Uses the real Inventory/Equipment/QuestLog through their public APIs only.

var root := ""
var bus: Node
var allow_save := true


func parity_keys() -> Dictionary:
	return {
		"test_save_load_round_trip_is_deep_equal": ["persistence:character-identity", "persistence:level-exp",
			"persistence:hp-mp", "persistence:ap-stats", "persistence:mesos", "persistence:inventory",
			"persistence:setup-tab", "persistence:equipment", "persistence:current-map", "persistence:play-time-flags"],
		"test_v2_fields_round_trip_with_their_types": ["persistence:skills", "persistence:sp",
			"persistence:skill-cooldowns-buffs", "persistence:natural-regen-timer", "persistence:quickslots",
			"persistence:chairs"],
		"test_seated_state_is_not_persisted": ["persistence:seated-state"],
		"test_breakable_state_is_not_persisted": ["persistence:breakable-state"],
		"test_respawn_reference_is_recomputed_from_canonical_data": ["persistence:respawn-information"],
	}


func before_each() -> void:
	root = "user://_tests/save_rt_%d_%d" % [Time.get_ticks_usec(), randi()]
	bus = load("res://scripts/autoload/events.gd").new()
	allow_save = true


func after_each() -> void:
	bus.free()
	_remove_tree(root)


## A SaveService + GameState pair wired to each other, a private directory and a private event bus.
func _pair() -> Array:
	var svc := SaveService.new()
	svc.save_dir = root
	svc.db = db()
	svc.event_bus = bus
	svc.log_failures = false
	svc.can_save_override = func() -> bool: return allow_save
	svc.world_provider = func(ch: CharacterState) -> Dictionary: return SaveDocument.world_from_character(ch)
	var game := GameState.new()
	game.db = db()
	game.save_service = svc
	game.event_bus = bus
	game.log_warnings = false
	svc.game_node = game
	return [svc, game]


func _free_pair(pair: Array) -> void:
	for n in pair:
		(n as Node).free()


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


func _write_raw(slot: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(root)
	var f := FileAccess.open(root.path_join(slot + ".json"), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _first_item(tab: String) -> String:
	for id in db().ids("items"):
		if String(db().item(id).get("inventory_tab", "")) == tab:
			return id
	return ""


## A map other than the start map, whose canonical return map differs from itself.
func _field_map() -> String:
	for id in db().ids("maps"):
		if String(db().map(id).get("return_map_id", "")) != id:
			return id
	return db().ids("maps")[0]


## "" when equal; numbers compare by value (JSON has one number type), everything else by type and value.
func _diff(a: Variant, b: Variant, path: String = "$") -> String:
	var a_num := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var b_num := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if a_num and b_num:
		return "" if is_equal_approx(float(a), float(b)) else "%s: %s != %s" % [path, str(a), str(b)]
	if typeof(a) != typeof(b):
		return "%s: %s (%s) != %s (%s)" % [path, str(a), type_string(typeof(a)), str(b), type_string(typeof(b))]
	if a is Dictionary:
		var da: Dictionary = a
		var dbb: Dictionary = b
		for k in da:
			if not dbb.has(k):
				return "%s.%s missing after load" % [path, str(k)]
			var d := _diff(da[k], dbb[k], "%s.%s" % [path, str(k)])
			if d != "":
				return d
		for k in dbb:
			if not da.has(k):
				return "%s.%s appeared after load" % [path, str(k)]
		return ""
	if a is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return "%s: size %d != %d" % [path, aa.size(), ab.size()]
		for i in aa.size():
			var d := _diff(aa[i], ab[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s != %s" % [path, str(a), str(b)]


## A character with every part of the state populated (values are arbitrary game state, not canonical numbers).
func _rich_character() -> CharacterState:
	var c := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	c.name = "RoundTrip"
	c.level = 7
	c.exp = 123
	c.hp = 77
	c.mp = 33
	c.base_max_hp = 146
	c.base_max_mp = 77
	c.base_stats = {"str": 20, "dex": 8, "int": 4, "luk": 5}
	c.ap = 3
	c.sp = 6
	c.fame = 2
	c.mesos = 12345
	c.skills = {"0001000": 2, "0001002": 3}
	# The C3 shapes: remaining seconds, never clock times.
	c.effects = [{"id": "nimble_feet", "source": "skill:0001002", "remaining_s": 30.0, "data": {"speed": 10}}]
	c.cooldowns = {"0001001": 81.25, "0001002": 12.0}
	c.natural_recovery = {"hp_rest_s": 6.5}
	var map_id := _field_map()
	var portals: Array = db().map(map_id).get("portals", [])
	var portal_name := String((portals[0] as Dictionary).get("name", "")) if not portals.is_empty() else ""
	c.location = {
		"map_id": map_id,
		"entry": {"map_id": map_id, "portal_id": portal_name},
		"resume": {"local_pos": [31.2, 4.05, -17.8], "facing_deg": 135.5, "map_content_hash": "9f1c"},
	}
	c.respawn_reference = String(db().map(map_id)["return_map_id"])
	c.quickslots = {"1": {"kind": "item", "id": _first_item("use")}, "4": {"kind": "item", "id": _first_item("etc")},
		"5": {"kind": "skill", "id": "0001000"}}
	c.flags = {"tutorial_seen": true, "visits": 3, "nested": {"list": [1, 2.5, "three"]}}
	c.play_time_s = 3725.125
	c.inventory.add(_first_item("use"), 37, db())
	c.inventory.add(_first_item("etc"), 5, db())
	c.inventory.add(_first_item("setup"), 1, db())
	var quests := db().ids("quests")
	if c.quests.has_method("start") and quests.size() >= 2:
		c.quests.call("start", quests[0], 12.5)
		if c.quests.has_method("add_kills"):
			c.quests.call("add_kills", quests[0], "2", 3)
		if c.quests.has_method("mark_talked"):
			c.quests.call("mark_talked", quests[0], "1")
		c.quests.call("start", quests[1], 20.0)
		if c.quests.has_method("complete"):
			c.quests.call("complete", quests[1], 99.75)
	return c


func test_save_load_round_trip_is_deep_equal() -> void:
	var a := _pair()
	var game: GameState = a[1]
	assert_eq(game.new_game({"save": false}), OK)
	var before := _rich_character()
	game.character = before
	assert_eq(game.save_game("slot1"), OK, "save")
	var expected := before.to_dict()
	# A second, independent service + game reads the file back.
	var b := _pair()
	var game2: GameState = b[1]
	assert_eq(game2.load_game("slot1"), OK, "load")
	var after := game2.character.to_dict()
	assert_eq(_diff(expected, after), "", "round trip")
	assert_true(game2.character != before, "a new object, not the saved one")
	# Every composed part actually carried data (so the equality above is not vacuous).
	assert_false(_diff(before.inventory.to_dict(), Inventory.new().to_dict()) == "", "inventory populated")
	assert_eq(game2.character.inventory.count(_first_item("use")), 37, "inventory count survives")
	if Equipment.new().has_method("equip"):
		assert_eq(game2.character.equipment.weapon_id(), before.equipment.weapon_id(), "equipped weapon survives")
		assert_ne(game2.character.equipment.weapon_id(), "", "a weapon was equipped")
	else:
		print("SKIP equipment content check: Equipment is still a contract stub")
	if before.quests.has_method("start"):
		assert_false(_diff(before.quests.to_dict(), QuestLog.new().to_dict()) == "", "quest log populated")
	else:
		print("SKIP quest content check: QuestLog is still a contract stub")
	# Types consumers rely on after JSON (numbers are normalized back to int where integral).
	var loc: Dictionary = game2.character.location
	assert_eq(typeof(loc["resume"]["local_pos"][0]), TYPE_FLOAT, "positions stay floats")
	assert_eq(typeof(game2.character.flags["visits"]), TYPE_INT, "integral numbers come back as int")
	assert_eq(typeof(game2.character.play_time_s), TYPE_FLOAT)
	_free_pair(a)
	_free_pair(b)


## Every save_version 2 field (contract C3) survives a save and a load with its type: timers in remaining seconds as
## floats (even whole ones, which JSON writes as integers), typed quickslot bindings (an item and a skill), the
## natural-recovery clock, skills and SP.
func test_v2_fields_round_trip_with_their_types() -> void:
	var a := _pair()
	var game: GameState = a[1]
	game.new_game({"save": false})
	game.character = _rich_character()
	assert_eq(game.save_game("v2"), OK, "save")
	var b := _pair()
	var game2: GameState = b[1]
	assert_eq(game2.load_game("v2"), OK, "load")
	var c := game2.character
	assert_eq(c.cooldowns, {"0001001": 81.25, "0001002": 12.0}, "cooldowns")
	assert_eq(typeof(c.cooldowns.get("0001002")), TYPE_FLOAT, "a whole-second cooldown is still a float")
	assert_eq(c.effects.size(), 1, "one effect")
	if c.effects.size() == 1:
		var e: Dictionary = c.effects[0]
		assert_eq(typeof(e["remaining_s"]), TYPE_FLOAT, "effect time is a float")
		assert_eq(e["remaining_s"], 30.0, "remaining seconds")
		assert_eq(e["source"], "skill:0001002", "source")
		assert_eq(e["data"], {"speed": 10}, "data")
	assert_eq(c.natural_recovery, {"hp_rest_s": 6.5}, "recovery clock")
	assert_eq(c.quickslots.get("5"), {"kind": "skill", "id": "0001000"}, "a skill binding")
	assert_eq(c.quickslots.get("1"), {"kind": "item", "id": _first_item("use")}, "an item binding")
	assert_eq(CharacterState.quickslot_item_id(c.quickslots.get("1")), _first_item("use"), "reads as its item")
	assert_eq(CharacterState.quickslot_item_id(c.quickslots.get("5")), "", "a skill binding is not an item")
	assert_eq(c.skills, {"0001000": 2, "0001002": 3}, "skill levels")
	assert_eq(c.sp, 6, "unspent SP")
	assert_eq(c.inventory.count(_first_item("setup")), 1, "the Set-up (chair) item")
	_free_pair(a)
	_free_pair(b)


## The persisted character is exactly this list of fields. A new one must be added here on purpose (and to
## docs/runtime/SAVES.md), so state that is not persisted by design (seated / chair in use, breakables, monsters,
## ground drops, the game clock, the RNG) cannot slip into the save.
func test_persisted_character_fields_are_exactly_the_schema() -> void:
	var keys := PackedStringArray(CharacterState.new().to_dict().keys())
	keys.sort()
	assert_eq(keys, PackedStringArray(["ap", "base_max_hp", "base_max_mp", "base_stats", "cooldowns", "effects",
		"equipment", "exp", "fame", "flags", "gender", "hp", "inventory", "job", "level", "location", "mesos", "mp",
		"name", "natural_recovery", "play_time_s", "quests", "quickslots", "respawn_reference", "skills", "sp"]),
		"save_version 2 character fields")
	var world := SaveDocument.build(CharacterState.new(), {}, "2026-10-05T00:00:00Z", db())["world"] as Dictionary
	var wkeys := PackedStringArray(world.keys())
	wkeys.sort()
	assert_eq(wkeys, PackedStringArray(["location", "respawn_reference"]), "the world block holds no map instance state")


## The seated state is not persisted (C3): a file that carries one (a hand edit, or a future build) loads standing,
## with the chair still in the Set-up tab, and the next save does not write it back.
func test_seated_state_is_not_persisted() -> void:
	var a := _pair()
	var game: GameState = a[1]
	game.new_game({"save": false})
	var chair := _first_item("setup")
	game.character.inventory.add(chair, 1, db())
	assert_eq(game.save_game("sit"), OK)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("sit.json")))
	doc["character"]["seated"] = true
	doc["character"]["chair_in_use"] = chair
	_write_raw("sit", JSON.stringify(doc))
	var b := _pair()
	var game2: GameState = b[1]
	assert_eq(game2.load_game("sit"), OK, "loads")
	assert_false(game2.character.to_dict().has("seated"), "no seated state in the loaded character")
	assert_eq(game2.character.inventory.count(chair), 1, "the chair is still owned")
	assert_eq(game2.save_game("sit"), OK)
	var again: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("sit.json")))
	assert_false((again["character"] as Dictionary).has("seated"), "not written back")
	assert_false((again["character"] as Dictionary).has("chair_in_use"), "not written back")
	_free_pair(a)
	_free_pair(b)


## Breakables, monsters and ground drops are not persisted (C3, §4.7.3): a world block that carries them loads
## without them reaching the character, and a save never writes them from the character.
func test_breakable_state_is_not_persisted() -> void:
	var a := _pair()
	var game: GameState = a[1]
	game.new_game({"save": false})
	assert_eq(game.save_game("box"), OK)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("box.json")))
	doc["character"]["breakables"] = {"0000001": {"hits": 3}}
	doc["character"]["ground_drops"] = [{"item_id": "348"}]
	_write_raw("box", JSON.stringify(doc))
	var b := _pair()
	var game2: GameState = b[1]
	assert_eq(game2.load_game("box"), OK, "loads")
	var cd := game2.character.to_dict()
	assert_false(cd.has("breakables") or cd.has("ground_drops"), "nothing of the map instance reaches the character")
	_free_pair(a)
	_free_pair(b)


func test_save_file_envelope() -> void:
	var a := _pair()
	var game: GameState = a[1]
	game.new_game({"save": false})
	game.character = _rich_character()
	assert_eq(game.save_game("env"), OK)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("env.json")))
	assert_true(raw is Dictionary, "the file is a JSON object")
	var doc: Dictionary = raw
	for key in ["save_version", "game", "saved_at", "character", "world", "meta"]:
		assert_has(doc, key, "envelope")
	assert_eq(int(doc["save_version"]), SaveService.SAVE_VERSION, "schema version")
	assert_eq(doc["game"], "MisoStory")
	var iso := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
	assert_true(iso.search(String(doc["saved_at"])) != null, "saved_at is ISO 8601 UTC: %s" % doc["saved_at"])
	assert_eq(_diff(game.character.to_dict(), doc["character"]), "", "character block is CharacterState.to_dict()")
	var world: Dictionary = doc["world"]
	assert_eq(_diff(world["location"], game.character.location), "", "world.location")
	assert_eq(world["respawn_reference"], game.character.respawn_reference, "world.respawn_reference")
	var meta: Dictionary = doc["meta"]
	assert_eq(meta["name"], "RoundTrip")
	assert_eq(int(meta["level"]), 7)
	assert_eq(meta["map_id"], _field_map())
	assert_eq(meta["map_name"], String(db().map(_field_map())["name"]), "map name from canonical data")
	assert_near(float(meta["play_time_s"]), 3725.125, 1e-9, "play time")
	_free_pair(a)


func test_saving_is_blocked_unless_can_save() -> void:
	var a := _pair()
	var svc: SaveService = a[0]
	var game: GameState = a[1]
	game.new_game({"save": false})
	allow_save = false
	assert_eq(game.save_game("slot1"), ERR_UNAVAILABLE, "blocked")
	assert_false(svc.has_save("slot1"), "nothing written")
	assert_eq(svc.last_error, ERR_UNAVAILABLE)
	allow_save = true
	assert_eq(game.save_game("slot1"), OK, "allowed again")
	_free_pair(a)


func test_without_map_session_can_save_saving_is_allowed() -> void:
	var a := _pair()
	var svc: SaveService = a[0]
	svc.can_save_override = Callable()
	svc.map_session_node = Node.new()  # a MapSession without can_save()
	assert_true(svc.can_save(), "no can_save() -> allowed (documented fallback)")
	svc.map_session_node.free()
	svc.map_session_node = null
	_free_pair(a)


func test_saving_needs_an_active_game() -> void:
	var a := _pair()
	var game: GameState = a[1]
	assert_eq(game.save_game("slot1"), ERR_UNCONFIGURED, "nothing to save before new_game/load_game")
	_free_pair(a)


func test_corrupt_or_missing_save_fails_and_keeps_the_live_game() -> void:
	var a := _pair()
	var game: GameState = a[1]
	game.new_game({"save": false})
	var live := game.character
	assert_eq(game.load_game("missing"), ERR_FILE_NOT_FOUND, "missing")
	_write_raw("garbage", "{\"save_version\": 1, \"game\": \"MisoSto")
	assert_eq(game.load_game("garbage"), ERR_PARSE_ERROR, "truncated JSON")
	_write_raw("empty", "")
	assert_eq(game.load_game("empty"), ERR_PARSE_ERROR, "empty file")
	assert_eq(game.load_game("../etc"), ERR_INVALID_PARAMETER, "bad slot name")
	assert_true(game.character == live, "live character untouched after every failure")
	_free_pair(a)


func test_wrong_shapes_are_corrupt_not_crashes() -> void:
	var a := _pair()
	var svc: SaveService = a[0]
	var c := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	var good := SaveDocument.build(c, {}, "2026-10-04T00:00:00Z", db())
	var cases := {
		"other_game": ["game", "SomeOtherGame"],
		"no_character": ["character", null],
		"character_list": ["character", [1, 2]],
		"world_string": ["world", "nowhere"],
		"game_number": ["game", 5],
		"game_null": ["game", null],
	}
	for slot in cases:
		var doc := good.duplicate(true)
		doc[cases[slot][0]] = cases[slot][1]
		_write_raw(slot, JSON.stringify(doc))
		assert_eq(svc.read_save(slot).error, ERR_FILE_CORRUPT, slot)
	var field_cases := {
		"stats_string": ["base_stats", "oops"],
		"level_string": ["level", "high"],
		"inventory_list": ["inventory", [1]],
		"effects_dict": ["effects", {"a": 1}],
		"name_number": ["name", 7],
		"stat_value_dict": ["base_stats", {"str": {"x": 1}}],
	}
	for slot in field_cases:
		var doc := good.duplicate(true)
		doc["character"][field_cases[slot][0]] = field_cases[slot][1]
		_write_raw(slot, JSON.stringify(doc))
		var r := svc.read_save(slot)
		assert_eq(r.error, ERR_FILE_CORRUPT, slot)
		assert_true(r.message.length() > 0, "%s explains: %s" % [slot, r.message])
	_free_pair(a)


func test_unknown_map_falls_back_to_the_start_location() -> void:
	var a := _pair()
	var svc: SaveService = a[0]
	var c := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	c.location = {"map_id": "999999999", "entry": {"map_id": "999999999", "spawn_index": 0}}
	c.respawn_reference = "999999999"
	assert_eq(svc.save_character("lost", c), OK)
	var r := svc.read_save("lost")
	assert_eq(r.error, OK, "still loads")
	assert_eq(r.character.location, CharacterFactory.start_location(db()), "start location used")
	var start_id := String(CharacterFactory.start_location(db())["map_id"])
	assert_eq(r.character.respawn_reference, String(db().map(start_id)["return_map_id"]), "respawn recomputed")
	assert_true(r.warnings.size() > 0, "the correction is reported")
	_free_pair(a)


func test_odd_location_values_fall_back_instead_of_crashing() -> void:
	var a := _pair()
	var svc: SaveService = a[0]
	var c := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	var doc := SaveDocument.build(c, {}, "2026-10-04T00:00:00Z", db())
	for bad in [12345, null, [1], {"x": 1}]:
		doc["world"]["location"] = {"map_id": bad}
		_write_raw("odd", JSON.stringify(doc))
		var r := svc.read_save("odd")
		assert_eq(r.error, OK, "map_id %s still loads" % str(bad))
		if r.ok():
			assert_eq(r.character.location, CharacterFactory.start_location(db()), "map_id %s -> start" % str(bad))
	_free_pair(a)


func test_respawn_reference_is_recomputed_from_canonical_data() -> void:
	var a := _pair()
	var svc: SaveService = a[0]
	var c := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	var map_id := _field_map()
	c.location = {"map_id": map_id, "entry": {"map_id": map_id, "spawn_index": 0}}
	c.respawn_reference = map_id  # wrong on purpose: the canonical return map differs
	svc.save_character("respawn", c)
	var r := svc.read_save("respawn")
	assert_eq(r.character.respawn_reference, String(db().map(map_id)["return_map_id"]), "canonical wins")
	assert_eq(r.world["respawn_reference"], r.character.respawn_reference, "world block agrees")
	_free_pair(a)


func test_list_saves_for_a_slot_picker() -> void:
	var a := _pair()
	var svc: SaveService = a[0]
	var game: GameState = a[1]
	game.new_game({"slot": "slot2"})
	game.new_game({"name": "Second", "ap": {"luk": int(db().formula("beginner")["creation_ap"])},
		"weapon_id": CharacterFactory.creation_weapon_ids(db())[0], "slot": "slot1"})
	game.save_game("slot1")  # second write -> slot1 has a backup
	_write_raw("slot3", "not json at all")
	var list := svc.list_saves()
	var slots: Array = list.map(func(e: Dictionary) -> String: return String(e["slot"]))
	assert_eq(slots, ["slot1", "slot2", "slot3"], "sorted by slot")
	var s1: Dictionary = list[0]
	assert_true(s1["ok"], "slot1 readable")
	assert_eq(s1["meta"]["name"], "Second")
	assert_eq(int(s1["meta"]["level"]), int(db().formula("beginner")["starting_level"]))
	var start_id := String(CharacterFactory.start_location(db())["map_id"])
	assert_eq(s1["meta"]["map_name"], String(db().map(start_id)["name"]), "map name for display")
	assert_true(s1["meta"].has("play_time_s"), "play time for display")
	assert_eq(int(s1["save_version"]), SaveService.SAVE_VERSION)
	assert_true(s1["has_backup"], "slot1 kept a backup")
	assert_true(int(s1["modified_unix"]) > 0, "modified time")
	var s3: Dictionary = list[2]
	assert_false(s3["ok"], "slot3 unreadable but listed")
	assert_eq(int(s3["error"]), ERR_PARSE_ERROR)
	assert_eq(s3["meta"], {}, "no meta for an unreadable save")
	_free_pair(a)


func test_has_and_delete_save() -> void:
	var a := _pair()
	var svc: SaveService = a[0]
	var game: GameState = a[1]
	assert_false(svc.has_save("slot1"))
	game.new_game({"slot": "slot1"})
	assert_true(svc.has_save("slot1"), "new game wrote a save")
	game.save_game("slot1")
	assert_eq(svc.delete_save("slot1"), OK)
	assert_false(svc.has_save("slot1"), "deleted")
	assert_eq(svc.list_saves().size(), 0, "backup deleted too")
	assert_eq(svc.delete_save("slot1"), ERR_FILE_NOT_FOUND, "nothing left to delete")
	_free_pair(a)


func test_failed_save_keeps_the_previous_save_loadable() -> void:
	var a := _pair()
	var svc: SaveService = a[0]
	var game: GameState = a[1]
	game.new_game({"slot": "slot1"})
	var original_mesos := game.character.mesos
	game.character.mesos = original_mesos + 999
	DirAccess.make_dir_recursive_absolute(svc.store().tmp_path_of("slot1"))
	var blocker := FileAccess.open(svc.store().tmp_path_of("slot1").path_join("blocker"), FileAccess.WRITE)
	blocker.store_string("x")
	blocker.close()
	assert_ne(game.save_game("slot1"), OK, "the write fails")
	assert_true(svc.last_error_message.length() > 0, "with a reason")
	var r := svc.read_save("slot1")
	assert_eq(r.error, OK, "previous save intact")
	assert_eq(r.character.mesos, original_mesos, "previous contents")
	_free_pair(a)
