extends TestCase
## Real save_version 2 saves (game/tests/data/saves/v2/, provenance in the README there), written before characters
## had an appearance (#67), still load through the current code: each migrates to the current schema with its
## gender's default Beginner look (no gender: the male one), keeps every other value it had, and the first save over
## it keeps a copy of the v2 file.

const DIR := "res://tests/data/saves/v2"
## Fixture -> sha256 of the file as promoted (the README lists the same). The fixtures are evidence: never edit them.
const SHA256 := {
	"female": "1698f43f97471fceabaae3ac39458fb45d6f18aec6e86ba8ce2f6ec86f13bf20",
	"male": "7e2fdc1735a723aaa2c1c93871458997efae076665a0d30c15e957e76738321b",
	"no_gender": "72675e93ec9296e28be4006e9fd788fd1ad572e50014468d465a204f0483f580",
}
## The migration steps a save_version 2 file goes through to reach the current schema.
const V2_STEPS: PackedStringArray = ["v2_appearance_default_preset"]
## What each fixture holds (read from the file by hand) and the look it must get: the pack's base_recipe of
## Beginner_Female / Beginner_Male (hair style, face, skin).
const PINS := {
	"female": {"name": "Mira", "gender": "female", "weapon": "541",
		"appearance": {"hair_style": 2, "face": 0, "skin": 3}},
	"male": {"name": "Tomas", "gender": "male", "weapon": "576",
		"appearance": {"hair_style": 3, "face": 0, "skin": 0}},
	"no_gender": {"name": "Beginner", "gender": "", "weapon": "585",
		"appearance": {"hair_style": 3, "face": 0, "skin": 0}},
}

var root := ""


func parity_keys() -> Dictionary:
	return {
		"test_each_fixture_gets_its_gender_default_look": ["mechanic:save-migration"],
		"test_first_save_over_a_v2_save_keeps_a_pre_migration_copy": ["mechanic:save-migration"],
	}


func before_each() -> void:
	root = "user://_tests/save_v2_%d_%d" % [Time.get_ticks_usec(), randi()]


func after_each() -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(root.path_join(f))
	DirAccess.remove_absolute(root)


func _path(fixture: String) -> String:
	return DIR.path_join(fixture + ".json")


func _raw(fixture: String) -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path(fixture)))
	if not (v is Dictionary):
		fail("%s does not parse as a JSON object" % _path(fixture))
		return {}
	return v


## A value as sorted JSON with every number in one form (JSON has one number type).
static func _canon(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)), "", true)


func _decode(fixture: String) -> SaveLoadResult:
	return SaveDocument.decode(_raw(fixture), SaveMigrations.new(), db())


func test_fixtures_are_unedited_v2_saves() -> void:
	for fixture: String in SHA256:
		assert_eq(FileAccess.get_sha256(_path(fixture)), String(SHA256[fixture]), "%s is byte-identical" % fixture)
		var raw := _raw(fixture)
		assert_eq(SaveMigrations.version_of(SaveDocument.normalize_numbers(raw)), 2, "%s is a save_version 2 file" % fixture)
		assert_false((raw.get("character", {}) as Dictionary).has("appearance"), "%s predates appearance" % fixture)
	assert_eq(PINS.keys().size(), SHA256.keys().size(), "every fixture is pinned")


func test_each_fixture_gets_its_gender_default_look() -> void:
	for fixture: String in PINS:
		var p: Dictionary = PINS[fixture]
		var r := _decode(fixture)
		assert_eq(r.error, OK, "%s loads: %s" % [fixture, r.message])
		if not r.ok():
			continue
		assert_eq(r.version_found, 2, fixture)
		assert_eq(r.migrations_applied, V2_STEPS, "%s migration steps" % fixture)
		assert_eq(int(r.document["save_version"]), SaveMigrations.CURRENT_VERSION, "%s is current" % fixture)
		assert_eq(r.warnings, PackedStringArray(), "%s loads without corrections" % fixture)
		assert_eq(r.document["character"]["appearance"], p["appearance"], "%s: the migrated document" % fixture)
		var c := r.character
		assert_eq([c.name, c.gender, c.equipment.weapon_id()], [p["name"], p["gender"], p["weapon"]], fixture)
		assert_eq(c.appearance, p["appearance"], "%s: the character's look" % fixture)


## Every character value in the file comes back unchanged: the step only adds the look.
func test_each_fixture_keeps_every_saved_value() -> void:
	for fixture: String in PINS:
		var r := _decode(fixture)
		if not r.ok():
			fail("%s does not load: %s" % [fixture, r.message])
			continue
		var saved: Dictionary = SaveDocument.normalize_numbers(_raw(fixture)["character"])
		var loaded := r.character.to_dict()
		for k: String in saved:
			assert_eq(_canon(loaded.get(k)), _canon(saved[k]),
				"%s: %s unchanged" % [fixture, k])
		var migrated: Dictionary = r.document["character"]
		for k: String in saved:
			assert_eq(_canon(migrated.get(k)), _canon(saved[k]),
				"%s: the step leaves %s alone" % [fixture, k])


## Through the file layer and the Game node, as a player's Continue would: the first save writes save_version 3 with
## the look and keeps the v2 file byte for byte as <slot>.json.pre-v2.
func test_first_save_over_a_v2_save_keeps_a_pre_migration_copy() -> void:
	for fixture: String in PINS:
		DirAccess.make_dir_recursive_absolute(root)
		var f := FileAccess.open(root.path_join("v2.json"), FileAccess.WRITE)
		var original := FileAccess.get_file_as_bytes(_path(fixture))
		f.store_buffer(original)
		f.close()
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
		assert_eq(game.load_game("v2"), OK, "%s continues: %s" % [fixture, svc.last_error_message])
		assert_eq(game.character.appearance, PINS[fixture]["appearance"], "%s: the live look" % fixture)
		assert_eq(game.save_game("v2"), OK, "%s saves back" % fixture)
		assert_eq(FileAccess.get_file_as_bytes(root.path_join("v2.json.pre-v2")), original,
			"%s: the v2 file is kept byte for byte" % fixture)
		var again := svc.read_save("v2")
		assert_eq(again.version_found, SaveMigrations.CURRENT_VERSION, "%s rewritten at the current version" % fixture)
		assert_eq(again.migrations_applied, PackedStringArray(), "%s needs no migration any more" % fixture)
		if again.ok():
			assert_eq(again.character.appearance, PINS[fixture]["appearance"], "%s: the look is saved" % fixture)
		game.free()
		svc.free()
		bus.free()
		after_each()
