extends TestCase
## The save position model (MAP_ARCHITECTURE.md §4.9) at the save boundary: a loaded location is sanitized before
## MapSession sees it (entry and resume shapes, re-floated resume numbers), and without MapSession.save_world() the
## world block follows MapSession.current_map / last_arrival instead of a stale character copy.

var root := ""
var svc: SaveService
var bus: Node
var _fake_session_script: GDScript


func before_each() -> void:
	root = "user://_tests/save_loc_%d_%d" % [Time.get_ticks_usec(), randi()]
	bus = load("res://scripts/autoload/events.gd").new()
	svc = SaveService.new()
	svc.save_dir = root
	svc.db = db()
	svc.event_bus = bus
	svc.log_failures = false


func after_each() -> void:
	if svc.map_session_node != null:
		svc.map_session_node.free()
	svc.free()
	bus.free()
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


## A stand-in for the MapSession autoload with only the contract's data members (MAP_ARCHITECTURE.md §4.3), so the
## test does not depend on the world runtime's implementation or state.
func _fake_session(current: String, arrival: Variant, respawn: String = "") -> Node:
	if _fake_session_script == null:
		_fake_session_script = GDScript.new()
		_fake_session_script.source_code = "extends Node\nvar current_map: String = \"\"\n" \
			+ "var respawn_reference: String = \"\"\nvar last_arrival: Variant = null\n"
		_fake_session_script.reload()
	var ms: Node = _fake_session_script.new()
	ms.set("current_map", current)
	ms.set("respawn_reference", respawn)
	ms.set("last_arrival", arrival)
	return ms


## Two maps that differ, each with at least one portal (field maps).
func _two_maps() -> PackedStringArray:
	var out: PackedStringArray = []
	for id in db().ids("maps"):
		if not (db().map(id).get("portals", []) as Array).is_empty():
			out.append(id)
		if out.size() == 2:
			break
	return out


func _portal_of(map_id: String, i: int = 0) -> String:
	var portals: Array = db().map(map_id).get("portals", [])
	return String((portals[mini(i, portals.size() - 1)] as Dictionary).get("name", ""))


func _character_at(location: Dictionary) -> CharacterState:
	var c := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	c.location = location
	return c


func _load_location(location: Dictionary) -> SaveLoadResult:
	var c := _character_at(location)
	assert_eq(svc.save_character("loc", c, SaveDocument.world_from_character(c)), OK, "save")
	return svc.read_save("loc")


# --- sanitizing on load -------------------------------------------------------------------------------------

func test_malformed_entry_and_resume_are_replaced_not_passed_on() -> void:
	var map_id := _two_maps()[0]
	var r := _load_location({"map_id": map_id, "entry": "west00",
		"resume": {"local_pos": "oops", "facing_deg": [1]}, "custom": {"kept": true}})
	assert_eq(r.error, OK, "still loads: %s" % r.message)
	var loc := r.character.location
	assert_eq(loc["entry"], {"map_id": map_id, "spawn_index": 0}, "a string entry becomes player spawn 0")
	assert_false(loc.has("resume"), "a malformed resume is dropped")
	assert_eq(loc.get("custom"), {"kept": true}, "keys MapSession may add are kept")
	assert_true(r.warnings.size() >= 2, "both corrections reported: %s" % ", ".join(r.warnings))
	assert_eq(r.world["location"], loc, "the world block carries the same location")


func test_entry_for_another_map_or_a_missing_spawn_is_replaced() -> void:
	var maps := _two_maps()
	var here := maps[0]
	var spawns: Array = db().map(here)["player_spawns"]
	var cases := {
		"other map": {"map_id": maps[1], "portal_id": _portal_of(maps[1])},
		"spawn past the map's player spawns": {"map_id": here, "spawn_index": spawns.size()},
		"negative spawn": {"map_id": here, "spawn_index": -1},
		"text spawn": {"map_id": here, "spawn_index": "0"},
		"empty portal and no spawn": {"map_id": here, "portal_id": ""},
	}
	for label in cases:
		var r := _load_location({"map_id": here, "entry": cases[label]})
		assert_eq(r.error, OK, label)
		if r.ok():
			assert_eq(r.character.location["entry"], {"map_id": here, "spawn_index": 0}, label)


func test_valid_entries_are_kept() -> void:
	var here := _two_maps()[0]
	var spawns: Array = db().map(here)["player_spawns"]
	for entry: Dictionary in [{"map_id": here, "portal_id": _portal_of(here)},
			{"map_id": here, "spawn_index": spawns.size() - 1}]:
		var r := _load_location({"map_id": here, "entry": entry})
		assert_eq(r.character.location["entry"], entry, "kept: %s" % JSON.stringify(entry))
		assert_eq(r.warnings.size(), 0, "no warning for a valid entry: %s" % ", ".join(r.warnings))


func test_resume_numbers_come_back_as_floats() -> void:
	var here := _two_maps()[0]
	var r := _load_location({"map_id": here, "entry": {"map_id": here, "spawn_index": 0},
		"resume": {"local_pos": [31.0, 4.0, -17.0], "facing_deg": 90.0, "map_content_hash": "9f1c"}})
	var resume: Dictionary = r.character.location["resume"]
	for i in 3:
		assert_eq(typeof(resume["local_pos"][i]), TYPE_FLOAT, "local_pos[%d] is a float after JSON" % i)
	assert_eq(resume["local_pos"], [31.0, 4.0, -17.0])
	assert_eq(typeof(resume["facing_deg"]), TYPE_FLOAT, "facing_deg is a float after JSON")
	assert_eq(resume["map_content_hash"], "9f1c", "diagnostic hash kept")


func test_resume_with_wrong_arity_or_non_finite_values_is_dropped() -> void:
	var here := _two_maps()[0]
	var warnings: PackedStringArray = []
	var base := {"map_id": here, "entry": {"map_id": here, "spawn_index": 0}}
	for bad: Variant in [{"local_pos": [1.0, 2.0]}, {"local_pos": [1.0, 2.0, "3"]}, {"local_pos": [1.0, 2.0, 3.0],
			"facing_deg": "north"}, [1.0, 2.0, 3.0], {"facing_deg": 0.0}]:
		var loc := base.duplicate(true)
		loc["resume"] = bad
		var out := SaveDocument.sanitize_location(loc, warnings, db())
		assert_false(out.has("resume"), "dropped: %s" % JSON.stringify(bad))
	assert_eq(warnings.size(), 5, "one warning each")
	var nan_loc := base.duplicate(true)
	nan_loc["resume"] = {"local_pos": [NAN, 0.0, 0.0]}
	assert_false(SaveDocument.sanitize_location(nan_loc, warnings).has("resume"), "NaN position dropped")


# --- the world block without MapSession.save_world() -----------------------------------------------------------

func test_capture_world_keeps_the_character_location_before_the_world_starts() -> void:
	var here := _two_maps()[0]
	var loc := {"map_id": here, "entry": {"map_id": here, "spawn_index": 0}, "resume": {"local_pos": [1.0, 2.0, 3.0]}}
	svc.map_session_node = _fake_session("", null)
	var w := svc.capture_world(_character_at(loc))
	assert_eq(w["location"], loc, "no current_map yet: the character's location is used as is")


func test_capture_world_uses_last_arrival_when_the_map_changed() -> void:
	var maps := _two_maps()
	var there := maps[1]
	var arrival := ArrivalRef.at_portal(there, _portal_of(there))
	svc.map_session_node = _fake_session(there, arrival, String(db().map(there)["return_map_id"]))
	var c := _character_at({"map_id": maps[0], "entry": {"map_id": maps[0], "spawn_index": 0},
		"resume": {"local_pos": [1.0, 2.0, 3.0]}})
	var w := svc.capture_world(c)
	assert_eq(w["location"], {"map_id": there, "entry": arrival.to_dict()}, "entry is MapSession.last_arrival (§4.9)")
	assert_eq(w["respawn_reference"], String(db().map(there)["return_map_id"]), "respawn from MapSession")


func test_capture_world_without_last_arrival_uses_spawn_zero() -> void:
	var maps := _two_maps()
	svc.map_session_node = _fake_session(maps[1], null)
	var w := svc.capture_world(_character_at({"map_id": maps[0], "entry": {"map_id": maps[0], "spawn_index": 0}}))
	assert_eq(w["location"], {"map_id": maps[1], "entry": {"map_id": maps[1], "spawn_index": 0}})


func test_capture_world_drops_a_stale_entry_and_resume_in_the_same_map() -> void:
	var here := _two_maps()[0]
	var loc := {"map_id": here, "entry": {"map_id": here, "spawn_index": 0}, "resume": {"local_pos": [1.0, 2.0, 3.0]}}
	# The player arrived through a portal since the character's location was written.
	var arrival := ArrivalRef.at_portal(here, _portal_of(here))
	svc.map_session_node = _fake_session(here, arrival)
	var w := svc.capture_world(_character_at(loc))
	assert_eq(w["location"], {"map_id": here, "entry": arrival.to_dict()}, "stale location replaced, no resume")
	# When last_arrival is the character's entry, the location (and its resume) is current and kept.
	svc.map_session_node.free()
	svc.map_session_node = _fake_session(here, ArrivalRef.at_spawn(here, 0))
	assert_eq(svc.capture_world(_character_at(loc))["location"], loc, "matching entry keeps the resume")
	# A Dictionary last_arrival works the same way.
	svc.map_session_node.free()
	svc.map_session_node = _fake_session(here, {"map_id": here, "spawn_index": 0.0})
	assert_eq(svc.capture_world(_character_at(loc))["location"], loc, "numbers compare by value")


func test_save_game_writes_the_map_session_location() -> void:
	var maps := _two_maps()
	var game := GameState.new()
	game.db = db()
	game.save_service = svc
	game.event_bus = bus
	game.log_warnings = false
	svc.game_node = game
	svc.can_save_override = func() -> bool: return true
	assert_eq(game.new_game({"save": false, "slot": "ms"}), OK)
	var arrival := ArrivalRef.at_portal(maps[1], _portal_of(maps[1]))
	svc.map_session_node = _fake_session(maps[1], arrival)
	assert_eq(game.save_game("ms"), OK)
	assert_eq(game.character.location, {"map_id": maps[1], "entry": arrival.to_dict()}, "live copy follows MapSession")
	var r := svc.read_save("ms")
	assert_eq(r.character.location, {"map_id": maps[1], "entry": arrival.to_dict()}, "saved and loaded")
	assert_eq(r.character.respawn_reference, String(db().map(maps[1])["return_map_id"]), "canonical respawn")
	game.free()


func test_map_session_save_world_is_used_verbatim() -> void:
	var here := _two_maps()[0]
	var s := GDScript.new()
	s.source_code = "extends Node\nvar current_map := \"\"\nfunc save_world() -> Dictionary:\n" \
		+ "\treturn {\"location\": {\"map_id\": current_map, \"entry\": {\"map_id\": current_map, \"portal_id\": \"p\"}," \
		+ " \"resume\": {\"local_pos\": [1.5, 2.0, 3.0]}}, \"respawn_reference\": \"r\", \"extra\": 1}\n"
	s.reload()
	var ms: Node = s.new()
	ms.set("current_map", here)
	svc.map_session_node = ms
	var w := svc.capture_world(_character_at({}))
	assert_eq(w["location"]["entry"], {"map_id": here, "portal_id": "p"})
	assert_eq(w["extra"], 1, "MapSession's own keys are kept")
