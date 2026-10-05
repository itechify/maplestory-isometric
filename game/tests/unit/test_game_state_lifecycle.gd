extends TestCase
## The Game node's lifecycle on a private instance: new game, load with wholesale replacement and refresh signals,
## the debounced autosave gated by can_save, play-time tracking, reset_save and start_or_continue.

var root := ""
var bus: Node
var svc: SaveService
var game: GameState
var allow_save := true
## signal name -> Array of argument arrays
var heard: Dictionary = {}

const WATCHED: PackedStringArray = ["stats_changed", "hp_changed", "mp_changed", "mesos_changed", "inventory_changed",
	"equipment_changed", "game_loaded", "game_saved", "exp_gained", "leveled_up", "notice"]


func parity_keys() -> Dictionary:
	return {
		"test_autosave_is_debounced": ["mechanic:autosave"],
		"test_autosave_is_not_starved_by_a_stream_of_requests": ["mechanic:autosave"],
		"test_autosave_waits_for_can_save": ["mechanic:autosave"],
		"test_progress_milestones_on_the_bus_request_an_autosave": ["mechanic:autosave"],
		"test_quest_progress_autosaves_debounced": ["mechanic:autosave", "persistence:quest-progress-kills"],
		"test_missing_save_with_a_backup_loads_the_backup_instead_of_starting_over": ["mechanic:atomic-save-backup"],
		"test_a_corrupt_save_is_not_silently_replaced_by_its_backup": ["mechanic:atomic-save-backup"],
		"test_play_time_counts_unpaused_game_time": ["persistence:play-time-flags"],
	}


func before_each() -> void:
	root = "user://_tests/game_state_%d_%d" % [Time.get_ticks_usec(), randi()]
	allow_save = true
	heard = {}
	bus = load("res://scripts/autoload/events.gd").new()
	for sig in WATCHED:
		var s := sig
		bus.connect(s, func(a: Variant = null, b: Variant = null) -> void: _record(s, [a, b]))
	svc = SaveService.new()
	svc.save_dir = root
	svc.db = db()
	svc.event_bus = bus
	svc.log_failures = false
	svc.can_save_override = func() -> bool: return allow_save
	svc.world_provider = func(ch: CharacterState) -> Dictionary: return SaveDocument.world_from_character(ch)
	game = _new_game_node(svc)


func after_each() -> void:
	game.free()
	svc.free()
	bus.free()
	_remove_tree(root)


func _new_game_node(service: SaveService) -> GameState:
	var g := GameState.new()
	g.db = db()
	g.save_service = service
	g.event_bus = bus
	g.log_warnings = false
	service.game_node = g
	return g


func _record(sig: String, args: Array) -> void:
	if not heard.has(sig):
		heard[sig] = []
	heard[sig].append(args)


func _count(sig: String) -> int:
	return (heard.get(sig, []) as Array).size()


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


## Advances the node's timers like the engine would.
func _tick(seconds: float, step: float = 0.25) -> void:
	var t := 0.0
	while t < seconds - 1e-9:
		game._process(step)
		t += step


func test_new_game_installs_a_character_and_writes_a_clean_save() -> void:
	var replaced: Array = []
	game.character_replaced.connect(func(reason: String) -> void: replaced.append(reason))
	assert_false(game.has_active_game(), "no game before new_game")
	assert_eq(game.new_game({"slot": "fresh"}), OK)
	assert_true(game.has_active_game())
	assert_eq(game.current_slot, "fresh")
	assert_eq(replaced, [GameState.REASON_NEW_GAME], "character_replaced once")
	var q := CharacterFactory.default_params(db())
	assert_eq(game.character.name, String(q["name"]), "quick-start name")
	assert_true(svc.has_save("fresh"), "clean save written")
	var r := svc.read_save("fresh")
	assert_eq(r.error, OK)
	assert_eq(r.character.to_dict(), game.character.to_dict(), "the save is the new character")
	for sig in ["stats_changed", "hp_changed", "mp_changed", "mesos_changed", "inventory_changed", "equipment_changed"]:
		assert_eq(_count(sig), 1, "%s fired once" % sig)
	assert_eq(heard["hp_changed"][0][0], game.character.hp, "hp_changed carries the new HP")
	assert_eq(heard["mesos_changed"][0], [game.character.mesos, 0], "mesos_changed(mesos, 0)")
	assert_eq(_count("game_loaded"), 0, "a new game is not a load")


func test_new_game_with_bad_params_changes_nothing() -> void:
	var before := game.character
	var err := game.new_game({"name": "x", "ap": {}, "weapon_id": "nope"})
	assert_eq(err, ERR_INVALID_PARAMETER)
	assert_true(game.last_creation_errors.size() >= 3, "every problem reported: %s" % ", ".join(game.last_creation_errors))
	assert_true(game.character == before, "live character untouched")
	assert_false(game.has_active_game())
	assert_eq(svc.list_saves().size(), 0, "nothing written")
	assert_eq(game.new_game({"slot": "../x"}), ERR_INVALID_PARAMETER, "bad slot refused")


func test_load_replaces_the_character_wholesale_with_signals() -> void:
	game.new_game({"slot": "slot1"})
	game.character.mesos = 4321
	game.save_game("slot1")
	var saved_name := game.character.name
	# A fresh node (as after a restart) loads it.
	var game2 := _new_game_node(svc)
	var old_obj := game2.character
	var old_inventory := game2.character.inventory
	var replaced: Array = []
	game2.character_replaced.connect(func(reason: String) -> void: replaced.append(reason))
	heard = {}
	assert_eq(game2.load_game("slot1"), OK)
	assert_true(game2.character != old_obj, "new CharacterState object")
	assert_true(game2.character.inventory != old_inventory, "new composed objects")
	assert_eq(game2.character.name, saved_name)
	assert_eq(game2.character.mesos, 4321)
	assert_eq(game2.current_slot, "slot1", "the loaded slot becomes current")
	assert_true(game2.has_active_game())
	assert_eq(replaced, [GameState.REASON_LOAD])
	assert_eq(heard.get("game_loaded", []), [["slot1", null]], "Events.game_loaded(slot)")
	assert_eq(heard["mesos_changed"][0], [4321, 0], "refresh carries loaded values")
	for sig in ["stats_changed", "hp_changed", "mp_changed", "inventory_changed", "equipment_changed"]:
		assert_eq(_count(sig), 1, "%s fired" % sig)
	svc.game_node = game
	game2.free()


func test_autosave_is_debounced() -> void:
	game.new_game({"slot": "auto", "save": false})
	game.autosave_debounce_s = 2.0
	game.autosave_max_delay_s = 30.0
	assert_true(game.request_autosave("map"), "accepted")
	_tick(1.5)
	assert_true(game.request_autosave("map"), "a second request restarts the wait")
	_tick(1.5)
	assert_false(svc.has_save("auto"), "not yet: 1.5 s since the last request")
	assert_true(game.is_autosave_pending())
	_tick(1.0)
	assert_true(svc.has_save("auto"), "saved 2 s after the last request")
	assert_eq(_count("game_saved"), 1, "exactly one save for the burst")
	assert_false(game.is_autosave_pending())
	_tick(5.0)
	assert_eq(_count("game_saved"), 1, "no further saves without requests")


func test_autosave_is_not_starved_by_a_stream_of_requests() -> void:
	game.new_game({"slot": "auto", "save": false})
	game.autosave_debounce_s = 2.0
	game.autosave_max_delay_s = 5.0
	for i in 12:
		game.request_autosave("spam")
		_tick(0.5)
	assert_true(_count("game_saved") >= 1, "saved by the max delay despite constant requests")


func test_autosave_waits_for_can_save() -> void:
	game.new_game({"slot": "auto", "save": false})
	game.autosave_debounce_s = 1.0
	game.autosave_retry_s = 0.5
	allow_save = false
	game.request_autosave("transition")
	_tick(3.0)
	assert_false(svc.has_save("auto"), "blocked while can_save is false")
	assert_true(game.is_autosave_pending(), "still pending")
	allow_save = true
	_tick(0.5)
	assert_true(svc.has_save("auto"), "saved once allowed")
	assert_false(game.is_autosave_pending())


func test_progress_milestones_on_the_bus_request_an_autosave() -> void:
	game.new_game({"slot": "auto", "save": false})
	game.autosave_debounce_s = 1.0
	game.connect_autosave_triggers(bus)
	game.connect_autosave_triggers(bus)  # safe twice
	bus.emit_signal("stats_changed")
	bus.emit_signal("hp_changed", 1, 2)
	assert_false(game.is_autosave_pending(), "ordinary changes do not save")
	bus.emit_signal("map_entered", "000000010", "000000001")
	assert_true(game.is_autosave_pending(), "a map arrival requests an autosave")
	_tick(1.0)
	assert_true(svc.has_save("auto"), "saved after the debounce")
	assert_eq(_count("game_saved"), 1, "once")
	for sig in ["leveled_up", "quest_started", "quest_progressed", "quest_completed", "quest_forfeited"]:
		bus.emit_signal(sig, 2 if sig == "leveled_up" else "1000")
		assert_true(game.is_autosave_pending(), "%s requests an autosave" % sig)
		_tick(1.0)
	assert_eq(_count("game_saved"), 6, "one save per milestone burst")
	bus.emit_signal("skill_leveled", "0001001", 1)
	assert_true(game.is_autosave_pending(), "spending SP on a skill requests an autosave")
	_tick(1.0)
	assert_eq(_count("game_saved"), 7, "saved")
	# MapSession requests its post-transition autosave through the Saves autoload (no arguments).
	assert_true(svc.request_autosave(), "Saves.request_autosave() forwards to the Game node")
	assert_true(game.is_autosave_pending())
	_tick(1.0)
	assert_eq(_count("game_saved"), 8, "and it saves like any other request")


## Quest progress (C3 package, saves): a run of kills keeps pushing the debounce, but the burst still saves within
## autosave_max_delay_s, and the saved file holds the progress made so far.
func test_quest_progress_autosaves_debounced() -> void:
	game.new_game({"slot": "auto", "save": false})
	game.autosave_debounce_s = 2.0
	game.autosave_max_delay_s = 5.0
	game.connect_autosave_triggers(bus)
	game.character.quests.start("1006", 0.0)
	for k in 8:
		game.character.quests.add_kills("1006", "2")
		bus.emit_signal("quest_progressed", "1006")
		_tick(1.0)
	assert_eq(_count("game_saved"), 1, "a kill every second saves once, at the max delay, not eight times")
	var saved := svc.read_save("auto")
	assert_true(saved.ok(), saved.message)
	if saved.ok():
		assert_between(saved.character.quests.progress("1006")["kills"].get("2", 0), 5, 6, "the kills so far are in the file")


func test_debug_console_commands() -> void:
	assert_true(game._cmd_saves(PackedStringArray()).contains("no saves"), "empty list")
	assert_true(game._cmd_reset(PackedStringArray(["dbg"])).begins_with("reset dbg"), "reset_save dbg")
	assert_true(svc.has_save("dbg"))
	game.character.mesos = 31
	assert_true(game._cmd_save(PackedStringArray()).begins_with("saved dbg"), "save to the current slot")
	game.character.mesos = 0
	assert_true(game._cmd_load(PackedStringArray(["dbg"])).begins_with("loaded dbg"), "load")
	assert_eq(game.character.mesos, 31)
	var listing := game._cmd_saves(PackedStringArray())
	assert_true(listing.contains("dbg:") and listing.contains(game.character.name), "listing: %s" % listing)
	assert_true(game._cmd_load(PackedStringArray(["nope"])).begins_with("load failed"), "missing slot reported")
	assert_true(game._cmd_save(PackedStringArray(["../x"])).begins_with("save failed"), "bad slot reported")
	assert_eq(game._cmd_delete(PackedStringArray()), "usage: delete_save <slot>")
	assert_true(game._cmd_delete(PackedStringArray(["dbg"])).begins_with("deleted"), "delete")
	assert_false(svc.has_save("dbg"))


func test_autosave_needs_a_game() -> void:
	assert_false(game.request_autosave("boot"), "ignored before new_game")
	game.new_game({"slot": "auto", "save": false})
	game.autosave_enabled = false
	assert_false(game.request_autosave("x"), "ignored when disabled")


func test_play_time_counts_unpaused_game_time() -> void:
	var clock0 := game.clock
	_tick(2.0)
	assert_eq(game.character.play_time_s, 0.0, "no play time before a game starts")
	assert_eq(game.clock, clock0, "no game time either: the title screen and the island load do not count")
	game.new_game({"save": false})
	_tick(3.0)
	assert_near(game.character.play_time_s, 3.0, 1e-6, "3 s played")
	assert_near(game.session_play_time_s, 3.0, 1e-6, "session time")
	game.paused = true
	var clock_before := game.clock
	_tick(5.0)
	assert_near(game.character.play_time_s, 3.0, 1e-6, "paused time does not count")
	assert_eq(game.clock, clock_before, "the game clock stops while paused")
	game.paused = false
	_tick(1.0)
	assert_near(game.character.play_time_s, 4.0, 1e-6)
	game.save_game("pt")
	var r := svc.read_save("pt")
	assert_near(r.character.play_time_s, 4.0, 1e-6, "play time persists")
	assert_near(float(r.meta["play_time_s"]), 4.0, 1e-6, "and is in the slot meta")
	assert_near(game.clock, clock0 + 4.0, 1e-6, "the game clock ran exactly the unpaused active time")
	game.close_game()
	_tick(3.0)
	assert_near(game.clock, clock0 + 4.0, 1e-6, "back at the title the clock stands still")
	assert_eq(GameState.format_play_time(3725.9), "1:02:05")


func test_reset_save_starts_a_clean_game_in_the_slot() -> void:
	game.new_game({"slot": "slot1"})
	game.character.mesos = 999
	game.character.level = 5
	game.save_game("slot1")
	var replaced: Array = []
	game.character_replaced.connect(func(reason: String) -> void: replaced.append(reason))
	assert_eq(game.reset_save(), OK, "reset the current slot")
	assert_eq(replaced, [GameState.REASON_RESET])
	assert_eq(game.character.level, int(db().formula("beginner")["starting_level"]), "fresh level")
	var r := svc.read_save("slot1")
	assert_eq(r.character.to_dict(), game.character.to_dict(), "the slot holds the clean character")
	assert_false(svc.store().has_backup("slot1"), "old progress and its backup are gone")
	game.save_game("slot1")
	var kept := FileAccess.get_file_as_string(svc.store().path_of("slot1"))
	assert_eq(game.reset_save("slot1", {"name": "x"}), ERR_INVALID_PARAMETER, "bad params refused")
	assert_eq(FileAccess.get_file_as_string(svc.store().path_of("slot1")), kept, "and the slot is not wiped")
	assert_true(svc.store().has_backup("slot1"), "backup kept too")


func test_start_or_continue() -> void:
	assert_eq(game.start_or_continue("boot"), OK, "no save -> new game")
	assert_true(svc.has_save("boot"))
	game.character.mesos = 777
	game.save_game("boot")
	var game2 := _new_game_node(svc)
	assert_eq(game2.start_or_continue("boot"), OK, "save exists -> load")
	assert_eq(game2.character.mesos, 777)
	DirAccess.make_dir_recursive_absolute(root)
	var f := FileAccess.open(root.path_join("broken.json"), FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	assert_eq(game2.start_or_continue("broken"), ERR_PARSE_ERROR, "a corrupt save is reported")
	assert_eq(FileAccess.get_file_as_string(root.path_join("broken.json")), "{broken", "and never overwritten")
	svc.game_node = game
	game2.free()


func test_missing_save_with_a_backup_loads_the_backup_instead_of_starting_over() -> void:
	# A crash between "remove the old save" and "move the new one in" (DirAccess.rename on Windows) leaves only the
	# backup. Booting must continue from it, and the next saves must not overwrite it with a fresh character.
	game.new_game({"slot": "slot1"})
	game.character.mesos = 5555
	game.save_game("slot1")
	game.character.mesos = 6666
	game.save_game("slot1")  # the backup now holds the 5555 save
	DirAccess.remove_absolute(svc.store().path_of("slot1"))
	var listed := svc.list_saves()
	assert_eq(listed.size(), 1, "the slot is still offered")
	assert_true(bool(listed[0]["ok"]), "and loadable")
	assert_eq(listed[0]["source"], "backup", "from its backup")
	assert_true(int(listed[0]["modified_unix"]) > 0, "dated by the backup file")
	assert_eq(int(listed[0]["meta"]["level"]), game.character.level, "with the backup's meta")
	var game2 := _new_game_node(svc)
	var replaced: Array = []
	game2.character_replaced.connect(func(reason: String) -> void: replaced.append(reason))
	heard = {}
	assert_eq(game2.start_or_continue("slot1"), OK)
	assert_eq(replaced, [GameState.REASON_LOAD], "continued, not a new game")
	assert_eq(game2.character.mesos, 5555, "the backup's progress")
	assert_eq(_count("notice"), 1, "the player is told the backup was used")
	assert_eq(heard.get("game_loaded", []), [["slot1", null]])
	game2.character.mesos = 7777
	assert_eq(game2.save_game("slot1"), OK)
	assert_eq(svc.read_save("slot1").character.mesos, 7777, "the new save")
	assert_eq(svc.read_save("slot1", true).character.mesos, 5555, "the backup was not replaced by a missing save")
	svc.game_node = game
	game2.free()


func test_a_corrupt_save_is_not_silently_replaced_by_its_backup() -> void:
	game.new_game({"slot": "slot1"})
	game.save_game("slot1")
	var f := FileAccess.open(svc.store().path_of("slot1"), FileAccess.WRITE)
	f.store_string("{\"save_version\": 1, \"gam")
	f.close()
	var live := game.character
	assert_eq(game.load_game("slot1"), ERR_PARSE_ERROR, "the corrupt save is reported")
	assert_true(game.character == live, "live game untouched")
	assert_eq(game.start_or_continue("slot1"), ERR_PARSE_ERROR, "boot does not start over either")
	var listed := svc.list_saves()
	assert_false(bool(listed[0]["ok"]), "listed as unreadable")
	assert_true(bool(listed[0]["has_backup"]), "with a backup the UI can restore")
	assert_eq(svc.restore_backup("slot1"), OK)
	assert_eq(game.load_game("slot1"), OK, "loads after an explicit restore")


func test_allocate_ap_uses_the_canonical_stats_and_announces() -> void:
	game.new_game({"save": false})
	game.character.ap = 2
	var allowed: Array = db().formula("beginner")["ap"]["allocatable_stats"]
	var stat := String(allowed[0])
	var before := game.character.get_base_stat(stat)
	assert_true(game.allocate_ap(stat, 1), "allowed stat")
	assert_eq(game.character.get_base_stat(stat), before + 1)
	assert_eq(game.character.ap, 1)
	assert_true(_count("stats_changed") >= 2, "stats_changed after the allocation")
	assert_false(game.allocate_ap("max_hp", 1), "AP never goes into Max HP (not an allocatable stat)")
	assert_false(game.allocate_ap(stat, 2), "not more than the unspent AP")
	assert_eq(game.character.ap, 1, "refusals change nothing")


func test_gain_exp_announces_level_ups() -> void:
	game.new_game({"save": false})
	var need := Progression.exp_to_next(game.character.level, db())
	if need <= 0:
		print("SKIP test_gain_exp_announces_level_ups: Progression is still a contract stub")
		return
	var level := game.character.level
	game.gain_exp(need, "test")
	assert_eq(game.character.level, level + 1, "leveled")
	assert_eq(_count("exp_gained"), 1, "exp_gained")
	assert_eq(heard.get("leveled_up", []), [[level + 1, null]], "leveled_up(new level)")
	assert_true(game.is_autosave_pending(), "a level-up requests an autosave")
