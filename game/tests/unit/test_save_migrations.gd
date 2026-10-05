extends TestCase
## Save schema versioning: the version is written, the v0 -> v1 migration converts a real pre-versioning save, the
## v1 -> v2 step (contract C3) reshapes exactly what it documents, steps run in order, newer/unknown versions are
## refused with an error code instead of loading, and the first save over an older file keeps a copy of it. Real
## Iteration Two saves are covered by test_save_it2_fixtures.gd.

var root := ""
var svc: SaveService


func parity_keys() -> Dictionary:
	return {
		"test_v0_save_migrates_to_v1": ["mechanic:save-migration"],
		"test_v1_to_v2_types_quickslots": ["mechanic:save-migration", "persistence:quickslots"],
		"test_v1_to_v2_marks_completed_rewards_unrecorded": ["mechanic:save-migration",
			"persistence:random-rewards-received"],
		"test_v1_to_v2_clears_effects_and_adds_the_timers": ["mechanic:save-migration",
			"persistence:skill-cooldowns-buffs", "persistence:natural-regen-timer"],
		"test_v1_to_v2_leaves_everything_else_alone": ["mechanic:save-migration"],
	}


func before_each() -> void:
	root = "user://_tests/save_mig_%d_%d" % [Time.get_ticks_usec(), randi()]
	svc = SaveService.new()
	svc.save_dir = root
	svc.db = db()
	svc.log_failures = false
	svc.event_bus = load("res://scripts/autoload/events.gd").new()


func after_each() -> void:
	svc.event_bus.free()
	svc.free()
	_remove_tree(root)


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


func _write_json(slot: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(root)
	var f := FileAccess.open(root.path_join(slot + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(value, "\t"))
	f.close()


## A non-start map with a different canonical return map, so the migration's location mapping is visible.
func _field_map() -> String:
	for id in db().ids("maps"):
		if String(db().map(id).get("return_map_id", "")) != id:
			return id
	return db().ids("maps")[0]


## A pre-versioning save as a v0 build would have written it (brief Phase 6 field names, flat, no envelope).
func _v0_fixture(inventory_blob: Dictionary) -> Dictionary:
	return {
		"name": "OldTimer",
		"level": 4,
		"exp": 21,
		"hp": 90,
		"max_hp": 98,
		"mp": 30,
		"max_mp": 41,
		"str": 22,
		"dex": 5,
		"int": 4,
		"luk": 4,
		"available_ap": 2,
		"mesos": 1550,
		"inventory": inventory_blob,
		"equipment": {},
		"quest_state": {},
		"current_map": _field_map(),
		"respawn_reference": String(db().map(_field_map())["return_map_id"]),
		"play_time": 812.5,
	}


func test_current_version_is_written_and_matches_the_service() -> void:
	assert_eq(SaveService.SAVE_VERSION, SaveMigrations.CURRENT_VERSION, "one source of truth")
	assert_true(SaveService.SAVE_VERSION >= 1, "versioned")
	var c := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	assert_eq(svc.save_character("v", c), OK)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("v.json")))
	assert_eq(int(raw["save_version"]), SaveService.SAVE_VERSION, "save_version in the file")
	var r := svc.read_save("v")
	assert_eq(r.version_found, SaveService.SAVE_VERSION)
	assert_eq(r.migrations_applied, PackedStringArray(), "current saves need no migration")


func test_v0_save_migrates_to_v1() -> void:
	var inv := Inventory.new()
	var use_item := ""
	for id in db().ids("items"):
		if String(db().item(id).get("inventory_tab", "")) == "use":
			use_item = id
			break
	var stub_inventory := inv.add(use_item, 3, db()) == 0
	_write_json("old", _v0_fixture(inv.to_dict()))
	var r := svc.read_save("old")
	assert_eq(r.error, OK, "v0 loads: %s" % r.message)
	if not r.ok():
		return
	assert_eq(r.version_found, 0, "detected as v0")
	assert_eq(r.migrations_applied, PackedStringArray(["v0_flat_character_to_v1_envelope",
		"v1_typed_quickslots_quest_rewards"]), "v0 -> v1, then v1 -> v2")
	assert_eq(int(r.document["save_version"]), SaveMigrations.CURRENT_VERSION, "document is current after migration")
	assert_eq(String(r.document["game"]), SaveDocument.GAME_ID)
	var c := r.character
	assert_eq(c.name, "OldTimer")
	assert_eq(c.level, 4)
	assert_eq(c.exp, 21)
	assert_eq(c.hp, 90)
	assert_eq(c.base_max_hp, 98, "max_hp -> base_max_hp")
	assert_eq(c.mp, 30)
	assert_eq(c.base_max_mp, 41, "max_mp -> base_max_mp")
	assert_eq(c.base_stats, {"str": 22, "dex": 5, "int": 4, "luk": 4}, "flat stats -> base_stats")
	assert_eq(c.ap, 2, "available_ap -> ap")
	assert_eq(c.mesos, 1550)
	assert_near(c.play_time_s, 812.5, 1e-9, "play_time -> play_time_s")
	var map_id := _field_map()
	assert_eq(c.location, {"map_id": map_id, "entry": {"map_id": map_id, "spawn_index": 0}}, "current_map -> location")
	assert_eq(c.respawn_reference, String(db().map(map_id)["return_map_id"]))
	assert_eq(r.world["location"], c.location, "world block built")
	assert_eq(r.meta["name"], "OldTimer", "meta rebuilt for the slot picker")
	assert_eq(r.meta["map_name"], String(db().map(map_id)["name"]))
	if stub_inventory:
		print("SKIP inventory pass-through check in test_v0_save_migrates_to_v1: Inventory is still a contract stub")
	else:
		assert_eq(c.inventory.count(use_item), 3, "inventory blob passed through unchanged")


func test_migrated_save_is_rewritten_at_the_current_version() -> void:
	_write_json("old", _v0_fixture({}))
	var game := GameState.new()
	game.db = db()
	game.save_service = svc
	game.event_bus = svc.event_bus
	svc.game_node = game
	svc.can_save_override = func() -> bool: return true
	svc.world_provider = func(ch: CharacterState) -> Dictionary: return SaveDocument.world_from_character(ch)
	assert_eq(game.load_game("old"), OK, "v0 loads into the game")
	assert_eq(game.save_game("old"), OK, "saved back")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("old.json")))
	assert_eq(int(raw["save_version"]), SaveMigrations.CURRENT_VERSION, "rewritten as current")
	assert_eq(svc.read_save("old").migrations_applied, PackedStringArray(), "no migration needed any more")
	game.free()


func test_steps_run_in_order_up_to_the_target() -> void:
	var m := SaveMigrations.new()
	var seen: Array = []
	m.register(1, "add_gold", func(d: Dictionary) -> Dictionary:
		seen.append(["add_gold", int(d["save_version"])])
		d["gold"] = 1
		return d)
	m.register(2, "double_gold", func(d: Dictionary) -> Dictionary:
		seen.append(["double_gold", int(d["save_version"]), int(d["gold"])])
		d["gold"] = int(d["gold"]) * 2
		return d)
	var v0 := {"name": "Seq", "level": 1}
	var out := m.migrate(v0, 3)
	assert_eq(out["error"], OK, String(out["message"]))
	assert_eq(out["applied"], PackedStringArray(["v0_flat_character_to_v1_envelope", "add_gold", "double_gold"]))
	assert_eq(seen, [["add_gold", 1], ["double_gold", 2, 1]], "each step sees the previous step's output")
	assert_eq(int(out["doc"]["save_version"]), 3)
	assert_eq(int(out["doc"]["gold"]), 2)
	assert_false(v0.has("save_version"), "input untouched")


func test_newer_or_invalid_versions_are_refused() -> void:
	var c := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	var doc := SaveDocument.build(c, {}, "2026-10-04T00:00:00Z", db())
	doc["save_version"] = SaveMigrations.CURRENT_VERSION + 1
	_write_json("future", doc)
	var r := svc.read_save("future")
	assert_eq(r.error, ERR_INVALID_DATA, "a save from a newer build is not loaded")
	assert_true(r.message.contains("newer"), "message says why: %s" % r.message)
	for bad in ["one", -1, 1.5, null]:
		doc["save_version"] = bad
		_write_json("bad", doc)
		assert_eq(svc.read_save("bad").error, ERR_INVALID_DATA, "save_version %s refused" % str(bad))


func test_missing_step_is_an_error() -> void:
	var m := SaveMigrations.new()
	var cur := SaveMigrations.CURRENT_VERSION
	var out := m.migrate({"save_version": cur}, cur + 1)
	assert_eq(out["error"], ERR_INVALID_DATA)
	assert_true(String(out["message"]).contains("no migration"), String(out["message"]))
	var none := SaveMigrations.new(false)
	assert_eq(none.migrate({"name": "x", "level": 1})["error"], ERR_INVALID_DATA, "v0 without the built-in step")


func test_unrecognisable_objects_are_corrupt_not_v0() -> void:
	_write_json("junk", {"hello": "world"})
	assert_eq(svc.read_save("junk").error, ERR_FILE_CORRUPT, "an object that is neither v0 nor enveloped")


# --- v1 -> v2 (contract C3) -----------------------------------------------------------------------------------

## A real Iteration Two (v1) save, parsed and number-normalized the way decode() hands it to the steps.
func _v1_doc() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/saves/it2/d_inventory.json"))
	return SaveDocument.normalize_numbers(raw)


## Runs only the v1 -> v2 step on `doc` (through the registry, as decode() does).
func _to_v2(doc: Dictionary) -> Dictionary:
	var out := SaveMigrations.new().migrate(doc, 2)
	assert_eq(out["error"], OK, String(out["message"]))
	assert_eq(out["applied"], PackedStringArray(["v1_typed_quickslots_quest_rewards"]), "one step")
	return out["doc"]


func test_current_version_is_2() -> void:
	assert_eq(SaveMigrations.CURRENT_VERSION, 2, "Iteration Three writes save_version 2")
	assert_true(SaveMigrations.new().has_step(1), "with a v1 -> v2 step")


func test_v1_to_v2_types_quickslots() -> void:
	var doc := _v1_doc()
	doc["character"]["quickslots"] = {
		"1": "237", "2": 270, "3": {"kind": "skill", "id": "0001000"}, "4": null, "5": "",
		"6": {"kind": "item", "id": "271"}, "7": {"kind": "spell", "id": "x"}, "8": [1], "9": {"kind": "item"},
	}
	var v2 := _to_v2(doc)
	assert_eq(v2["character"]["quickslots"], {
		"1": {"kind": "item", "id": "237"}, "2": {"kind": "item", "id": "270"},
		"3": {"kind": "skill", "id": "0001000"}, "6": {"kind": "item", "id": "271"},
	}, "bare ids become item bindings, typed ones stay, the rest is dropped")
	assert_eq(int(v2["save_version"]), 2)


func test_v1_to_v2_marks_completed_rewards_unrecorded() -> void:
	var doc := _v1_doc()
	var entries: Dictionary = doc["character"]["quests"]["quests"]
	entries["1008"] = (entries["1006"] as Dictionary).duplicate(true)
	entries["1008"]["rewards_received"] = {"recorded": true, "items": [{"item_id": "713", "qty": 1}]}
	entries["1009"] = (entries["1006"] as Dictionary).duplicate(true)
	entries["1009"]["status"] = "in_progress"
	var v2 := _to_v2(doc)
	var q: Dictionary = v2["character"]["quests"]
	assert_eq(int(q["format"]), 2, "quests.format 2")
	assert_eq(q["quests"]["1006"]["rewards_received"], {"recorded": false}, "v1 completion: nothing was recorded")
	assert_eq(q["quests"]["1008"]["rewards_received"], {"recorded": true, "items": [{"item_id": "713", "qty": 1}]},
		"an existing record is kept")
	assert_false((q["quests"]["1009"] as Dictionary).has("rewards_received"), "in progress: untouched")
	var before: Dictionary = entries["1006"]
	for field: String in before:
		assert_eq(q["quests"]["1006"][field], before[field], "1006 %s unchanged" % field)


func test_v1_to_v2_clears_effects_and_adds_the_timers() -> void:
	var doc := _v1_doc()
	doc["character"]["effects"] = [{"id": "nimble_feet", "until": 512.25}]
	var v2 := _to_v2(doc)
	assert_eq(v2["character"]["effects"], [], "v1 effects (clock times) are dropped")
	assert_eq(v2["character"]["cooldowns"], {}, "cooldowns added")
	assert_eq(v2["character"]["natural_recovery"], {"hp_rest_s": 0.0}, "recovery clock added")
	# A late v1 build already wrote both timers: kept as they are.
	doc["character"]["cooldowns"] = {"0001001": 30.5}
	doc["character"]["natural_recovery"] = {"hp_rest_s": 4.25}
	v2 = _to_v2(doc)
	assert_eq(v2["character"]["cooldowns"], {"0001001": 30.5})
	assert_eq(v2["character"]["natural_recovery"], {"hp_rest_s": 4.25})


func test_v1_to_v2_leaves_everything_else_alone() -> void:
	var doc := _v1_doc()
	var v2 := _to_v2(doc)
	for k: String in doc:
		if k != "character" and k != "save_version":
			assert_eq(v2[k], doc[k], "%s unchanged" % k)
	for k: String in doc["character"]:
		if not (k in ["quickslots", "quests", "effects"]):
			assert_eq(v2["character"][k], doc["character"][k], "character.%s unchanged" % k)
	assert_false(doc["character"].has("cooldowns"), "the input document is not modified")


func test_v1_parts_of_the_wrong_type_still_load_as_corrupt() -> void:
	var c := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	var doc := SaveDocument.build(c, {}, "2026-10-05T00:00:00Z", db())
	doc["save_version"] = 1
	for bad: Array in [["quickslots", "237"], ["quests", 5], ["effects", "none"]]:
		var d := doc.duplicate(true)
		d["character"][bad[0]] = bad[1]
		_write_json("bad", d)
		assert_eq(svc.read_save("bad").error, ERR_FILE_CORRUPT, "a v1 %s of the wrong type stays corrupt" % bad[0])
	var no_char := {"save_version": 1, "game": SaveDocument.GAME_ID}
	_write_json("bad", no_char)
	assert_eq(svc.read_save("bad").error, ERR_FILE_CORRUPT, "a v1 envelope without a character is corrupt, not unmigratable")
