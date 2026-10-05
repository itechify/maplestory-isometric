extends TestCase
## Real Iteration Two saves (game/tests/data/saves/it2/, provenance in the README there) still load through the
## current code: each decodes, migrates to the current schema and keeps every value the player had. They are the
## regression anchor of the save migrations (ITERATION_THREE_CONTRACTS.md C3, docs/runtime/SAVES.md).

const DIR := "res://tests/data/saves/it2"
## Fixture -> sha256 of the file as promoted (the README lists the same). The fixtures are evidence: never edit them.
const SHA256 := {
	"c_progression": "344c6d982dba51a5b006a51b1c518549a6630f79dc41f6e483feee6cccb092fd",
	"d_inventory": "79e134406a76a48376009bae3bef48b5f92f14773a64c5f352a3a7709f1278f8",
	"e_quest_1006_halfway": "beca8c00b6077013eb0ed21cbc25847b466877c5e5f7239d78fa753edaf4ef48",
	"e_quest_1008_done": "b94c22a5e265c673e577761fa5f21bf988340b0b603239ae761639ec65d0ef5e",
	"f_death": "9ea73c96b21bcbdaaa327d9c0f9cc85022f278a64608d25a82ca2e46e66907f1",
	"g_shop": "cf3a1c889e6bc745d05f8972c2c6249154a7430847996f4d0fdbbaabdd312196",
}
## The migration steps an Iteration Two (save_version 1) file goes through to reach the current schema.
const IT2_STEPS: PackedStringArray = ["v1_typed_quickslots_quest_rewards"]
## Character keys whose saved value the migration steps above reshape; every other saved key must come back equal.
## (They are checked one by one in test_each_fixture_keeps_every_saved_value and test_v2_migration_of_each_fixture.)
const RESHAPED_KEYS: PackedStringArray = ["quests", "quickslots"]

## What each fixture holds, read from the file by hand (README): identity, progression, location, quests, items.
## "items" are inventory counts, "equipped" slot -> item id, "in_progress" quest id -> its saved kill counts.
const PINS := {
	"e_quest_1008_done": {
		"name": "QuestE", "gender": "female", "level": 3, "exp": 51, "hp": 17, "mp": 29, "ap": 10, "sp": 2,
		"mesos": 0, "base_max_hp": 82, "base_max_mp": 29, "str": 13,
		"map_id": "000000050", "entry": {"map_id": "000000050", "portal_id": "east00"}, "respawn": "000000060",
		"completed": ["1002", "1006", "1007", "1008"], "in_progress": {},
		"items": {"713": 1, "237": 3}, "equipped": {"weapon": "585"}, "quickslot_items": {},
	},
	"e_quest_1006_halfway": {
		"name": "QuestEtwo", "gender": "male", "level": 2, "exp": 5, "hp": 44, "mp": 17, "ap": 5, "sp": 1,
		"mesos": 0, "base_max_hp": 66, "base_max_mp": 17, "str": 13,
		"map_id": "000000050", "entry": {"map_id": "000000050", "portal_id": "west00"}, "respawn": "000000060",
		"completed": [], "in_progress": {"1006": {"2": 10}},
		"items": {}, "equipped": {"weapon": "585"}, "quickslot_items": {},
	},
	"d_inventory": {
		"name": "Inventor", "gender": "male", "level": 6, "exp": 35, "hp": 130, "mp": 65, "ap": 25, "sp": 5,
		"mesos": 56, "base_max_hp": 130, "base_max_mp": 65, "str": 13,
		"map_id": "000000061", "entry": {"map_id": "000000061", "portal_id": "out00"}, "respawn": "000000060",
		"completed": ["1006"], "in_progress": {},
		"items": {"541": 1, "1195": 1, "1305": 21, "348": 5, "349": 8, "350": 10, "351": 7, "417": 1, "213": 3,
			"270": 1, "237": 0},
		"equipped": {"top": "933", "bottom": "1157", "weapon": "585"}, "quickslot_items": {"1": "237"},
	},
	"f_death": {
		"name": "Mortal", "gender": "female", "level": 11, "exp": 724, "hp": 50, "mp": 56, "ap": 31, "sp": 9,
		"mesos": 779, "base_max_hp": 210, "base_max_mp": 125, "str": 13,
		"map_id": "000001010", "entry": {"map_id": "000001010", "spawn_index": 0}, "respawn": "000001010",
		"completed": ["1000"], "in_progress": {"1006": {"2": 2}},
		"items": {"270": 5}, "equipped": {"weapon": "585"}, "quickslot_items": {},
	},
	"c_progression": {
		"name": "ProgC", "gender": "male", "level": 8, "exp": 616, "hp": 50, "mp": 89, "ap": 0, "sp": 7,
		"mesos": 1042, "base_max_hp": 162, "base_max_mp": 89, "str": 26,
		"map_id": "000001000", "entry": {"map_id": "000001000", "portal_id": "east00"}, "respawn": "000001010",
		"completed": [], "in_progress": {},
		"items": {"321": 1, "413": 1, "415": 1, "417": 1, "348": 15, "349": 40, "350": 31, "351": 25, "356": 7,
			"651": 1, "710": 1, "934": 1, "938": 1, "939": 1, "1305": 1, "608": 1, "711": 1, "714": 1, "715": 1,
			"213": 9, "209": 6},
		"equipped": {"weapon": "585"}, "quickslot_items": {},
	},
	"g_shop": {
		"name": "Shopper", "gender": "male", "level": 1, "exp": 0, "hp": 50, "mp": 5, "ap": 0, "sp": 0,
		"mesos": 0, "base_max_hp": 50, "base_max_mp": 5, "str": 13,
		"map_id": "000001013", "entry": {"map_id": "000001013", "portal_id": "out00"}, "respawn": "000001010",
		"completed": [], "in_progress": {},
		"items": {"541": 3, "1306": 1, "576": 1, "585": 1, "1305": 17}, "equipped": {"weapon": "585"},
		"quickslot_items": {},
	},
}

var root := ""


func parity_keys() -> Dictionary:
	return {
		"test_each_fixture_decodes_with_its_pinned_values": ["mechanic:save-migration", "persistence:character-identity",
			"persistence:level-exp", "persistence:hp-mp", "persistence:ap-stats", "persistence:mesos",
			"persistence:inventory", "persistence:equipment", "persistence:quest-progress-kills",
			"persistence:quest-completion", "persistence:current-map", "persistence:respawn-information"],
		"test_each_fixture_keeps_every_saved_value": ["mechanic:save-migration", "persistence:quickslots"],
		"test_v2_migration_of_each_fixture": ["mechanic:save-migration", "persistence:random-rewards-received",
			"persistence:quest-completion", "persistence:quest-availability"],
		"test_each_fixture_loads_into_the_game_and_saves_back_at_the_current_version": ["mechanic:save-migration"],
		"test_every_item_in_the_fixtures_is_still_defined": ["persistence:inventory", "persistence:equipment"],
	}


func before_each() -> void:
	root = "user://_tests/save_it2_%d_%d" % [Time.get_ticks_usec(), randi()]


func after_each() -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(root.path_join(f))
	DirAccess.remove_absolute(root)


func _path(fixture: String) -> String:
	return DIR.path_join(fixture + ".json")


## The fixture as parsed JSON (numbers still floats), or {} after recording a failure.
func _raw(fixture: String) -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path(fixture)))
	if not (v is Dictionary):
		fail("%s does not parse as a JSON object" % _path(fixture))
		return {}
	return v


## Writes the fixture's exact bytes into `root` as `<slot>.json`, as if a player had it in their save folder.
func _install_slot(fixture: String, slot: String) -> void:
	DirAccess.make_dir_recursive_absolute(root)
	var f := FileAccess.open(root.path_join(slot + ".json"), FileAccess.WRITE)
	f.store_buffer(FileAccess.get_file_as_bytes(_path(fixture)))
	f.close()


func _decode(fixture: String) -> SaveLoadResult:
	return SaveDocument.decode(_raw(fixture), SaveMigrations.new(), db())


## "" when equal; numbers compare by value (JSON has one number type), everything else by type and value.
func _diff(a: Variant, b: Variant, path: String = "$") -> String:
	var a_num := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var b_num := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if a_num and b_num:
		return "" if is_equal_approx(float(a), float(b)) else "%s: %s != %s" % [path, str(a), str(b)]
	if typeof(a) != typeof(b):
		return "%s: %s (%s) != %s (%s)" % [path, str(a), type_string(typeof(a)), str(b), type_string(typeof(b))]
	if a is Dictionary:
		for k in a:
			if not (b as Dictionary).has(k):
				return "%s.%s is missing" % [path, str(k)]
			var d := _diff(a[k], b[k], "%s.%s" % [path, str(k)])
			if d != "":
				return d
		for k in b:
			if not (a as Dictionary).has(k):
				return "%s.%s appeared" % [path, str(k)]
		return ""
	if a is Array:
		if (a as Array).size() != (b as Array).size():
			return "%s: size %d != %d" % [path, (a as Array).size(), (b as Array).size()]
		for i in (a as Array).size():
			var d := _diff(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s != %s" % [path, str(a), str(b)]


func test_fixtures_are_unedited_it2_saves() -> void:
	for fixture: String in SHA256:
		assert_true(FileAccess.file_exists(_path(fixture)), "%s exists" % fixture)
		assert_eq(FileAccess.get_sha256(_path(fixture)), String(SHA256[fixture]), "%s is byte-identical to the promoted save" % fixture)
		var raw := _raw(fixture)
		assert_eq(SaveMigrations.version_of(SaveDocument.normalize_numbers(raw)), 1, "%s is a save_version 1 file" % fixture)
		assert_eq(String(raw.get("game", "")), SaveDocument.GAME_ID, fixture)
	assert_eq(PINS.keys().size(), SHA256.keys().size(), "every fixture is pinned")


func test_each_fixture_decodes_with_its_pinned_values() -> void:
	for fixture: String in PINS:
		var p: Dictionary = PINS[fixture]
		var r := _decode(fixture)
		assert_eq(r.error, OK, "%s loads: %s" % [fixture, r.message])
		if not r.ok():
			continue
		assert_eq(r.version_found, 1, "%s was written as v1" % fixture)
		assert_eq(r.migrations_applied, IT2_STEPS, "%s migration steps" % fixture)
		assert_eq(int(r.document["save_version"]), SaveMigrations.CURRENT_VERSION, "%s is current after migration" % fixture)
		assert_eq(r.warnings, PackedStringArray(), "%s loads without corrections" % fixture)
		var c := r.character
		for k: String in ["name", "gender", "level", "exp", "hp", "mp", "ap", "sp", "mesos", "base_max_hp", "base_max_mp"]:
			assert_eq(c.get(k), p[k], "%s %s" % [fixture, k])
		assert_eq(c.get_base_stat("str"), int(p["str"]), "%s STR" % fixture)
		assert_eq(String(c.location.get("map_id", "")), String(p["map_id"]), "%s map" % fixture)
		assert_eq(_diff(c.location.get("entry", {}), p["entry"]), "", "%s entry" % fixture)
		assert_true(c.location.get("resume", null) is Dictionary, "%s keeps its resume point" % fixture)
		assert_eq(c.respawn_reference, String(p["respawn"]), "%s respawn reference" % fixture)
		assert_eq(c.respawn_reference, String(db().map(String(p["map_id"]))["return_map_id"]),
			"%s respawn reference is the canonical return map" % fixture)
		for q: String in p["completed"]:
			assert_true(c.quests.is_completed(q), "%s: quest %s completed" % [fixture, q])
			assert_eq(c.quests.completions(q), 1, "%s: quest %s completed once" % [fixture, q])
		for q: String in p["in_progress"]:
			assert_true(c.quests.is_in_progress(q), "%s: quest %s in progress" % [fixture, q])
			assert_eq(_diff(c.quests.progress(q)["kills"], p["in_progress"][q]), "", "%s: quest %s kills" % [fixture, q])
		var quest_count := (p["completed"] as Array).size() + (p["in_progress"] as Dictionary).size()
		assert_eq(c.quests.entries.size(), quest_count, "%s: no other quest touched" % fixture)
		var held := 0
		for item_id: String in p["items"]:
			assert_eq(c.inventory.count(item_id), int(p["items"][item_id]), "%s: %s count" % [fixture, item_id])
			held += int(p["items"][item_id])
		var total := 0
		for item_id in c.inventory.item_ids():
			total += c.inventory.count(item_id)
		assert_eq(total, held, "%s: nothing else in the bag" % fixture)
		assert_eq(c.equipment.equipped(), p["equipped"], "%s equipment" % fixture)
		for key: String in p["quickslot_items"]:
			assert_eq(CharacterState.quickslot_item_id(c.quickslots.get(key, null)), String(p["quickslot_items"][key]),
				"%s quickslot %s" % [fixture, key])
		assert_eq(c.quickslots.size(), (p["quickslot_items"] as Dictionary).size(), "%s: no other quickslot" % fixture)


## Every character value in the file comes back unchanged, except the keys the migration reshapes (checked
## separately), so a migration can never drop or alter something silently.
func test_each_fixture_keeps_every_saved_value() -> void:
	for fixture: String in PINS:
		var r := _decode(fixture)
		if not r.ok():
			fail("%s does not load: %s" % [fixture, r.message])
			continue
		var saved: Dictionary = SaveDocument.normalize_numbers(_raw(fixture)["character"])
		var loaded := r.character.to_dict()
		for k: String in saved:
			if k in RESHAPED_KEYS:
				continue
			assert_true(loaded.has(k), "%s: %s still loads" % [fixture, k])
			assert_eq(_diff(saved[k], loaded.get(k)), "", "%s: %s unchanged" % [fixture, k])
		# Quest entries: everything the v1 entry held is still there with the same value.
		var saved_quests: Dictionary = (saved["quests"] as Dictionary)["quests"]
		var loaded_quests: Dictionary = (loaded["quests"] as Dictionary)["quests"]
		assert_eq(loaded_quests.size(), saved_quests.size(), "%s: same quests" % fixture)
		for q: String in saved_quests:
			for field: String in saved_quests[q]:
				assert_eq(_diff(saved_quests[q][field], (loaded_quests.get(q, {}) as Dictionary).get(field)), "",
					"%s: quest %s %s unchanged" % [fixture, q, field])
		# Quickslots: each saved item id is now the same item as a typed binding, under the same key.
		var saved_slots: Dictionary = saved["quickslots"]
		assert_eq(r.character.quickslots.size(), saved_slots.size(), "%s: same quickslot keys" % fixture)
		for key: String in saved_slots:
			assert_eq(r.character.quickslots.get(key), {"kind": "item", "id": String(saved_slots[key])},
				"%s: quickslot %s typed" % [fixture, key])


## What the v1 -> v2 step adds to each real save (the migrated document, as written back): quest format 2, every
## completed quest marked "rewards not recorded", in-progress quests untouched, no effects, fresh timers. The quest
## records are checked on the document because QuestLog owns how it keeps them in memory.
func test_v2_migration_of_each_fixture() -> void:
	for fixture: String in PINS:
		var r := _decode(fixture)
		if not r.ok():
			fail("%s does not load: %s" % [fixture, r.message])
			continue
		var cd: Dictionary = r.document["character"]
		var quests: Dictionary = cd["quests"]
		assert_eq(int(quests["format"]), 2, "%s: quests.format" % fixture)
		var p: Dictionary = PINS[fixture]
		for q: String in p["completed"]:
			assert_eq(quests["quests"][q].get("rewards_received"), {"recorded": false},
				"%s: completed %s says its rewards were not recorded" % [fixture, q])
		for q: String in p["in_progress"]:
			assert_false((quests["quests"][q] as Dictionary).has("rewards_received"), "%s: %s in progress untouched" % [fixture, q])
		assert_eq(cd["effects"], [], "%s: no effects" % fixture)
		assert_eq(cd["cooldowns"], {}, "%s: no cooldowns" % fixture)
		assert_eq(_diff(cd["natural_recovery"], {"hp_rest_s": 0.0}), "", "%s: a fresh recovery clock" % fixture)
		assert_eq(r.character.cooldowns, {}, "%s: character cooldowns" % fixture)
		assert_eq(r.character.natural_recovery, {"hp_rest_s": 0.0}, "%s: character recovery clock" % fixture)
		# Completed quests stay completed for the quest rules: none is offered again.
		var engine := QuestEngine.new(r.character, db())
		for q: String in p["completed"]:
			assert_false(engine.is_available(q), "%s: completed %s is not offered again" % [fixture, q])
		for key: String in p["quickslot_items"]:
			assert_eq(cd["quickslots"][key], {"kind": "item", "id": String(p["quickslot_items"][key])},
				"%s: quickslot %s typed in the document" % [fixture, key])


## Through the file layer and the Game node, as a player's Continue would: the fixture loads into a live game and
## the next save writes the current schema, which then loads with no migration and the same character.
func test_each_fixture_loads_into_the_game_and_saves_back_at_the_current_version() -> void:
	for fixture: String in PINS:
		_install_slot(fixture, "it2")
		var bus: Node = load("res://scripts/autoload/events.gd").new()
		var svc := SaveService.new()
		svc.save_dir = root
		svc.db = db()
		svc.event_bus = bus
		svc.log_failures = false
		svc.can_save_override = func() -> bool: return true
		svc.world_provider = func(ch: CharacterState) -> Dictionary: return SaveDocument.world_from_character(ch)
		var game := GameState.new()
		game.db = db()
		game.save_service = svc
		game.event_bus = bus
		game.log_warnings = false
		svc.game_node = game
		assert_eq(game.load_game("it2"), OK, "%s continues: %s" % [fixture, svc.last_error_message])
		var first := game.character.to_dict()
		assert_eq(game.character.name, String(PINS[fixture]["name"]), "%s is the live character" % fixture)
		assert_eq(game.save_game("it2"), OK, "%s saves back" % fixture)
		var again := svc.read_save("it2")
		assert_eq(again.error, OK, "%s reloads: %s" % [fixture, again.message])
		if again.ok():
			assert_eq(again.version_found, SaveMigrations.CURRENT_VERSION, "%s rewritten at the current version" % fixture)
			assert_eq(again.migrations_applied, PackedStringArray(), "%s needs no migration any more" % fixture)
			assert_eq(_diff(first, again.character.to_dict()), "", "%s: the rewrite is lossless" % fixture)
		game.free()
		svc.free()
		bus.free()
		after_each()


## A tripwire for the item data: an item id an Iteration Two player can hold must stay defined, or loading such a
## save shows it as an unknown item (kept, but unusable). Lists every id the fixtures hold.
func test_every_item_in_the_fixtures_is_still_defined() -> void:
	var missing: PackedStringArray = []
	for fixture: String in PINS:
		var c := _decode(fixture).character
		if c == null:
			fail("%s does not load" % fixture)
			continue
		var ids: PackedStringArray = c.inventory.item_ids()
		ids.append_array(PackedStringArray(c.equipment.equipped().values()))
		for key: String in c.quickslots:
			ids.append(CharacterState.quickslot_item_id(c.quickslots[key]))
		for id in ids:
			if id != "" and not db().has("items", id) and not ("%s:%s" % [fixture, id] in missing):
				missing.append("%s:%s" % [fixture, id])
	assert_eq(missing, PackedStringArray(), "items an Iteration Two save holds are still in the item data")
