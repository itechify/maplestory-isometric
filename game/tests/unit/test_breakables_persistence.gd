extends TestCase
## Wooden Box state is never saved (contracts C3 and C8). A private MapSession (no world, every transition completes
## synchronously) enters Amherst, two boxes take hits (one breaks); leaving the map parks the state with it and coming
## back finds the boxes as they were (the in-session map cache). The game is then saved through a private
## SaveService + GameState with the session's real world block: the save file holds nothing of the boxes. After a
## quit to title (MapSession.reset) and a load of that save, every box of the map stands intact again.

const SESSION_SCRIPT := "res://scripts/autoload/map_session.gd"
const AMHERST := "000001010"

var ms: Node = null
var bus: Node = null
var root := ""
var t := 0.0


func parity_keys() -> Dictionary:
	return {"test_box_state_is_parked_with_its_map_but_never_saved": ["breakable:0000001",
		"mechanic:breakable-hit-break-respawn"],
		"test_a_pause_menu_load_does_not_keep_broken_boxes": ["breakable:0000001"]}


func before_each() -> void:
	t = 0.0
	ms = load(SESSION_SCRIPT).new()
	ms.defs = MapDefinitions.build(db())
	ms.content = db()
	ms.character = CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	var r := RandomNumberGenerator.new()
	r.seed = 42
	ms.rng = r
	ms.autosave_enabled = false
	ms.clock_provider = func() -> float: return t
	bus = load("res://scripts/autoload/events.gd").new()
	root = "user://_tests/box_save_%d_%d" % [Time.get_ticks_usec(), randi()]


func after_each() -> void:
	ms.free()
	bus.free()
	var dir := DirAccess.open(root)
	if dir != null:
		for f in dir.get_files():
			DirAccess.remove_absolute(root.path_join(f))
		DirAccess.remove_absolute(root)


func _game() -> GameState:
	var svc := SaveService.new()
	svc.save_dir = root
	svc.db = db()
	svc.event_bus = bus
	svc.log_failures = false
	svc.can_save_override = func() -> bool: return true
	svc.world_provider = func(_ch: CharacterState) -> Dictionary: return ms.save_world()
	var game := GameState.new()
	game.db = db()
	game.save_service = svc
	game.event_bus = bus
	game.log_warnings = false
	svc.game_node = game
	return game


func test_box_state_is_parked_with_its_map_but_never_saved() -> void:
	var n := BreakableRules.hits_to_break("0000001", db())
	assert_eq(ms.start_new_game(), OK, "new game")
	assert_eq(ms.debug_warp(AMHERST), OK, "to Amherst")
	var st: MapInstanceState = ms.instance_state
	assert_eq(st.breakable_count(), BreakableRules.placements_of(db().map(AMHERST)).size(), "Amherst's boxes")
	for k in n:
		st.hit_breakable(2, t, n)
	st.hit_breakable(0, t, n)
	assert_false(st.is_breakable_intact(2), "box 2 broken")
	# Leaving and coming back within the respawn time: the map cache kept them.
	t = 5.0
	ms.debug_warp("000001012")
	assert_true(ms.cache.has(AMHERST), "Amherst parked")
	t = 10.0
	ms.debug_warp(AMHERST)
	assert_false(ms.instance_state.is_breakable_intact(2), "box 2 still broken after the round trip")
	assert_eq(ms.instance_state.breakable_hits(0), 1, "box 0 keeps its hit")
	# Saved through the session's real world block: nothing of the boxes reaches the file.
	var game := _game()
	assert_eq(game.new_game({"save": false}), OK, "a game to save")
	game.character = ms.character
	assert_eq(game.save_game("boxes"), OK, "save")
	var text := FileAccess.get_file_as_string(root.path_join("boxes.json"))
	assert_true(text.length() > 0 and AMHERST in text, "the save holds the character in Amherst")
	for word in ["breakable", "respawn_at", "reactor", "WoodenBox"]:
		assert_false(word in text, "the save file names no '%s'" % word)
	# Quit to title and load: a fresh instance, every box intact.
	ms.reset()
	assert_eq(ms.cache.size(), 0, "the map cache is gone with the session")
	var game2 := _game()
	assert_eq(game2.load_game("boxes"), OK, "load")
	ms.character = game2.character
	t = 20.0
	assert_eq(ms.load_character(game2.character), OK, "enter where the save says")
	assert_eq(ms.current_map, AMHERST, "back in Amherst")
	var fresh: MapInstanceState = ms.instance_state
	for i in fresh.breakable_count():
		assert_true(fresh.is_breakable_intact(i) and fresh.breakable_hits(i) == 0, "box %d intact after the load" % i)
	game.free()
	game2.free()


## The pause menu's Load while the session runs (no quit to title): Game.load_game replaces the character and
## MapSession loads where the save says, into the very map the player stands in. The boxes broken since the save must
## not survive it: the save holds none of them (C3), so the load starts the map fresh instead of taking back the live
## instance it parks.
func test_a_pause_menu_load_does_not_keep_broken_boxes() -> void:
	var n := BreakableRules.hits_to_break("0000001", db())
	assert_eq(ms.start_new_game(), OK, "new game")
	assert_eq(ms.debug_warp(AMHERST), OK, "to Amherst")
	var game := _game()
	assert_eq(game.new_game({"save": false}), OK, "a game to save")
	game.character = ms.character
	assert_eq(game.save_game("pause"), OK, "saved with every box whole")
	var st: MapInstanceState = ms.instance_state
	for k in n:
		st.hit_breakable(1, t, n)
	st.hit_breakable(0, t, n)
	assert_false(st.is_breakable_intact(1), "box 1 broken after the save")
	t = 4.0
	var game2 := _game()
	assert_eq(game2.load_game("pause"), OK, "load from the pause menu")
	ms.character = game2.character
	ms._on_character_replaced("load")
	assert_eq(ms.current_map, AMHERST, "still in Amherst")
	var now: MapInstanceState = ms.instance_state
	assert_ne(now, st, "not the live instance taken back")
	for i in now.breakable_count():
		assert_true(now.is_breakable_intact(i) and now.breakable_hits(i) == 0, "box %d as the save left it: whole" % i)
	game.free()
	game2.free()
