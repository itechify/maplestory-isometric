extends TestCase
## The game shell's additions to the Game autoload (GameState) on a private instance: the HP/MP helpers every
## system calls (and the signals the death watch listens to), close_game() for "quit to title", and the quest
## wiring QUESTS_AND_DIALOGUE.md describes (Game.quests, Game.npc_talk, debug commands).

var root := ""
var bus: Node
var svc: SaveService
var game: GameState
var heard: Array = []


func before_each() -> void:
	root = "user://_tests/shell_game_%d_%d" % [Time.get_ticks_usec(), randi()]
	heard = []
	bus = load("res://scripts/autoload/events.gd").new()
	for sig in ["hp_changed", "mp_changed", "player_damaged", "quest_started", "item_gained"]:
		var s: String = sig
		bus.connect(s, func(a: Variant = null, b: Variant = null) -> void: heard.append([s, a, b]))
	svc = SaveService.new()
	svc.save_dir = root
	svc.db = db()
	svc.event_bus = bus
	svc.log_failures = false
	svc.can_save_override = func() -> bool: return true
	svc.world_provider = func(ch: CharacterState) -> Dictionary: return SaveDocument.world_from_character(ch)
	game = GameState.new()
	game.db = db()
	game.save_service = svc
	game.event_bus = bus
	game.log_warnings = false
	svc.game_node = game
	game.new_game({"slot": "s1"})
	heard.clear()


func after_each() -> void:
	game.free()
	svc.free()
	bus.free()
	var d := DirAccess.open(root)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(root.path_join(f))
	DirAccess.remove_absolute(root)


func _heard(sig: String) -> Array:
	return heard.filter(func(h: Array) -> bool: return h[0] == sig)


func test_change_hp_clamps_and_announces() -> void:
	var max_hp := StatCalculator.max_hp(game.character, db())
	assert_eq(game.change_hp(-20), -20, "applied")
	assert_eq(game.character.hp, max_hp - 20, "HP")
	assert_eq(_heard("hp_changed").back(), ["hp_changed", max_hp - 20, max_hp], "hp_changed(hp, max)")
	assert_eq(game.change_hp(1000), 20, "capped at max HP")
	assert_eq(game.change_hp(-100000), -max_hp, "floored at 0")
	assert_true(game.is_character_dead(), "HP 0 is the canonical death trigger")
	heard.clear()
	assert_eq(game.change_hp(0), 0, "no change")
	assert_eq(_heard("hp_changed").size(), 1, "still announced (the HUD and death watch see the value)")


func test_change_mp() -> void:
	var max_mp := StatCalculator.max_mp(game.character, db())
	assert_eq(game.change_mp(-3), -3, "applied")
	assert_eq(_heard("mp_changed").back(), ["mp_changed", max_mp - 3, max_mp], "mp_changed")
	assert_eq(game.change_mp(99), 3, "capped")


func test_damage_player() -> void:
	var hp := game.character.hp
	assert_eq(game.damage_player(7, "100100"), 7, "HP lost")
	assert_eq(game.character.hp, hp - 7, "HP")
	assert_eq(_heard("player_damaged"), [["player_damaged", 7, "100100"]], "player_damaged(amount, source)")
	heard.clear()
	assert_eq(game.damage_player(0, "x"), 0, "0 damage (a miss)")
	assert_eq(_heard("player_damaged").size(), 0, "no player_damaged for 0")
	assert_eq(game.damage_player(9999), hp - 7, "overkill loses only the HP left")
	assert_eq(game.character.hp, 0, "dead")


func test_close_game_deactivates_without_touching_the_save() -> void:
	game.request_autosave("test")
	assert_true(game.is_autosave_pending(), "pending")
	var before := FileAccess.get_file_as_string(root.path_join("s1.json"))
	game.paused = true
	game.close_game()
	assert_false(game.has_active_game(), "inactive")
	assert_false(game.is_autosave_pending(), "autosave dropped")
	assert_false(game.paused, "unpaused")
	assert_eq(game.current_slot, "s1", "the slot is remembered")
	game._process(30.0)
	assert_eq(FileAccess.get_file_as_string(root.path_join("s1.json")), before, "no autosave after close_game")
	assert_eq(game.save_game(), ERR_UNCONFIGURED, "saving needs an active game")
	assert_false(game.request_autosave("x"), "autosave requests are ignored")
	var t := game.character.play_time_s
	game._process(5.0)
	assert_eq(game.character.play_time_s, t, "play time stops")
	assert_eq(game.load_game("s1"), OK, "a load reactivates")
	assert_true(game.has_active_game(), "active again")


func test_quest_wiring() -> void:
	assert_eq(game.quests, null, "not wired before _ready / wire_quests")
	game.wire_quests(bus)
	assert_true(game.quests != null and game.npc_talk != null, "Game.quests and Game.npc_talk")
	assert_true(game.quests.is_attached(), "attached to the bus")
	var first := game.quests
	game.wire_quests(bus)
	assert_true(game.quests == first, "wiring twice keeps the first service")
	var r := game.quests.accept("1000")
	assert_true(bool(r["ok"]), "accept 1000: %s" % r.get("reason", ""))
	assert_eq(game.character.quests.status("1000"), QuestLog.IN_PROGRESS, "on the live character")
	assert_eq(_heard("quest_started").size(), 1, "quest_started on the bus")
	# A new game replaces the character; the service follows it through character_provider.
	game.new_game({"slot": "s2"})
	assert_eq(game.character.quests.status("1000"), QuestLog.NOT_STARTED, "fresh character")
	assert_true(bool(game.quests.accept("1000")["ok"]), "accepting again works on the new character")
	assert_eq(game.character.quests.status("1000"), QuestLog.IN_PROGRESS, "the new character got it")
	var view := game.npc_talk.talk(String((db().quest("1000").get("start_npc", {}) as Dictionary).get("npc_id", "")))
	assert_true(bool(view.get("open", false)), "npc_talk opens a conversation")
	game.quests.detach()


func test_quest_debug_commands_registered() -> void:
	game.wire_quests(bus)
	var dbg: Node = load("res://scripts/autoload/debug_tools.gd").new()
	game.quests.register_debug_commands(dbg)
	assert_true(String(dbg.call("run", "quests")).begins_with("active:"), "quests command")
	dbg.free()
	game.quests.detach()
