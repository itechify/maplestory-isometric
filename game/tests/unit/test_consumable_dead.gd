extends TestCase
## Consumables and death: "is the player dead?" is Game.is_character_dead() (MapSession's DEAD state included), not
## "HP 0". The game shell takes a death's loss at the moment of death, so while the death notice is up the character
## already holds its respawn HP (death.json) and an HP test alone would let it drink potions (GAME_SHELL.md "Death and
## respawn"). The pure API takes an injected dead check; without one it asks the Game autoload, for the live character
## only. The default is exercised on a private GameState and MapSession; Game and MapSession are only read. The private
## MapSession has no bus seam, so its map_entered / player_died / player_respawned still reach the Events autoload
## (as in test_map_session.gd); the end-to-end test checks the MapSession autoload ignored them.

const RED_POTION := "270"


func _char(hp: int = 10) -> CharacterState:
	var c := CharacterState.new()
	c.base_max_hp = 1000
	c.base_max_mp = 1000
	c.hp = hp
	c.inventory.add(RED_POTION, 3, db())
	return c


func _always(value: bool) -> Callable:
	return func() -> bool: return value


## A GameState whose is_character_dead() reads `session` (a private MapSession or a stand-in) for character `c`.
func _game(c: CharacterState, session: Node = null) -> GameState:
	var g := GameState.new()
	g.db = db()
	g.log_warnings = false
	g.character = c
	g.map_session = session
	return g


## A stand-in MapSession: only state_name(), which is all GameState.is_character_dead() reads.
func _fake_session(state: String) -> Node:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar state := \"%s\"\nfunc state_name() -> String:\n\treturn state\n" % state
	s.reload()
	var n: Node = Node.new()
	n.set_script(s)
	return n


func test_an_injected_dead_check_refuses_use_while_hp_is_positive() -> void:
	var c := _char(10)
	var res := Consumables.use(c, RED_POTION, db(), _always(true))
	assert_eq(res.code, ItemCodes.DEAD, str(res))
	assert_false(res.ok)
	assert_eq(c.inventory.count(RED_POTION), 3, "nothing consumed")
	assert_eq(c.hp, 10, "HP unchanged")


func test_an_injected_alive_check_allows_use() -> void:
	var c := _char(10)
	var res := Consumables.use(c, RED_POTION, db(), _always(false))
	assert_true(res.ok, str(res))
	assert_eq(c.inventory.count(RED_POTION), 2)
	assert_true(c.hp > 10, "restored")


func test_the_canonical_hp_trigger_counts_whatever_the_check_says() -> void:
	# HP 0 before MapSession enters DEAD (or during a warp) is already a death (formulas/death.json).
	var c := _char(0)
	assert_true(Progression.is_dead(c, db()), "HP 0 is the canonical trigger")
	assert_eq(Consumables.use(c, RED_POTION, db(), _always(false)).code, ItemCodes.DEAD)
	assert_eq(c.inventory.count(RED_POTION), 3, "nothing consumed")
	assert_true(Consumables.is_dead(c, db(), _always(false)))


func test_the_check_runs_at_use_time() -> void:
	var c := _char(10)
	var dead := {"now": false}
	var check := func() -> bool: return bool(dead["now"])
	assert_true(Consumables.use(c, RED_POTION, db(), check).ok, "alive")
	dead["now"] = true
	assert_eq(Consumables.use(c, RED_POTION, db(), check).code, ItemCodes.DEAD, "dead")
	dead["now"] = false
	assert_true(Consumables.use(c, RED_POTION, db(), check).ok, "alive again")
	assert_eq(c.inventory.count(RED_POTION), 1)


func test_the_dead_check_comes_after_the_item_checks() -> void:
	var c := _char(10)
	c.inventory.add("348", 1, db())   # an Etc item
	assert_eq(Consumables.use(c, "nope", db(), _always(true)).code, ItemCodes.UNKNOWN_ITEM)
	assert_eq(Consumables.use(c, "348", db(), _always(true)).code, ItemCodes.NOT_USABLE)
	c.inventory.clear()
	assert_eq(Consumables.use(c, RED_POTION, db(), _always(true)).code, ItemCodes.NOT_ENOUGH_ITEMS)


func test_service_passes_its_dead_check_and_stays_silent_when_refused() -> void:
	var bus: Node = load("res://scripts/autoload/events.gd").new()
	var seen: Array = []
	for sig in ["item_used", "item_lost", "inventory_changed", "hp_changed", "mp_changed"]:
		var s: String = sig
		bus.connect(s, func(_a: Variant = null, _b: Variant = null) -> void: seen.append(s))
	var c := _char(10)
	var dead := {"now": true}
	var items := ItemService.new(c, db(), bus)
	assert_false(items.dead_check.is_valid(), "no check injected by default")
	items.dead_check = func() -> bool: return bool(dead["now"])
	var res := items.use_item(RED_POTION)
	assert_eq(res.code, ItemCodes.DEAD, str(res))
	assert_eq(seen, [], "a refused use emits nothing")
	assert_eq(c.inventory.count(RED_POTION), 3)
	assert_eq(c.hp, 10)
	dead["now"] = false
	assert_true(items.use_item(RED_POTION).ok)
	assert_eq(seen, ["item_used", "item_lost", "inventory_changed", "hp_changed"])
	bus.free()


func test_default_check_is_the_live_games_is_character_dead() -> void:
	var c := _char(10)
	var session := _fake_session("DEAD")
	var g := _game(c, session)
	var check := Consumables.default_dead_check(c, g)
	assert_true(check.is_valid(), "the live character uses the game's check")
	assert_eq(check.get_object(), g)
	assert_eq(String(check.get_method()), "is_character_dead")
	assert_true(Consumables.is_dead(c, db(), check), "dead while the session is DEAD, at HP 10")
	session.set("state", "IDLE")
	assert_false(Consumables.is_dead(c, db(), check), "alive in IDLE")
	assert_false(Consumables.default_dead_check(_char(10), g).is_valid(), "another character never inherits it")
	assert_false(Consumables.default_dead_check(null, g).is_valid(), "no character")
	var not_a_game := Node.new()
	assert_false(Consumables.default_dead_check(c, not_a_game).is_valid(), "an object without is_character_dead")
	not_a_game.free()
	g.free()
	session.free()


func test_default_check_uses_the_game_autoload_for_its_character_only() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var autoload: Node = tree.root.get_node_or_null("Game") if tree != null else null
	var fresh := _char(10)
	assert_false(Consumables.default_dead_check(fresh).is_valid(), "a fixture is not the live character")
	assert_true(Consumables.use(fresh, RED_POTION, db()).ok, "so a fixture at positive HP may use items")
	if autoload == null:
		fail("the Game autoload is registered in the test runner")
		return
	var live: Variant = autoload.get("character")
	if not (live is CharacterState):
		fail("Game.character is a CharacterState")
		return
	var check := Consumables.default_dead_check(live)
	assert_true(check.is_valid(), "the live character resolves to the autoload")
	assert_eq(check.get_object(), autoload)
	assert_eq(String(check.get_method()), "is_character_dead")


## The whole death commit: HP 0, MapSession enters DEAD and DeathRules hands the character its respawn HP; potions
## stay refused until the respawn, although HP is no longer 0.
func test_a_committed_death_refuses_items_until_the_respawn() -> void:
	# The private session's Events.player_died also reaches the MapSession autoload, which would enter DEAD itself if
	# it were IDLE, or once its warp completes if it were warping (MapSession._on_player_died), and leave the rest of
	# the run dead. In the test runner it waits in BOOT, where it ignores the announcement.
	var tree := Engine.get_main_loop() as SceneTree
	var real_ms: Node = tree.root.get_node_or_null("MapSession") if tree != null else null
	var real_state := String(real_ms.call("state_name")) if real_ms != null else ""
	if real_ms != null and real_state != "BOOT":
		fail("the MapSession autoload is %s, not BOOT: this test's player_died would reach it" % real_state)
		return
	var c := _char(10)
	var ms: Node = load("res://scripts/autoload/map_session.gd").new()
	ms.defs = MapDefinitions.build(db())
	ms.content = db()
	ms.character = c
	ms.autosave_enabled = false
	var g := _game(c, ms)
	var items := ItemService.new(c, db(), null)
	items.dead_check = Consumables.default_dead_check(c, g)
	assert_eq(ms.start_new_game(), OK, "a private session in the world")
	assert_true(items.use_item(RED_POTION).ok, "alive: a potion works")
	var rules := DeathRules.from_db(db())
	assert_eq(rules.errors, PackedStringArray(), "death.json loads")
	ms.death_commit = func(ch: CharacterState) -> Dictionary: return rules.apply(ch)
	c.hp = 0
	assert_eq(items.use_item(RED_POTION).code, ItemCodes.DEAD, "HP 0, before DEAD: the canonical trigger")
	assert_eq(ms.enter_dead(), OK, "MapSession enters DEAD and commits the death")
	assert_true(ms.is_death_committed(), "committed")
	var respawn_hp := c.hp
	assert_true(respawn_hp > 0, "the committed death already holds the respawn HP (%d)" % respawn_hp)
	var res := items.use_item(RED_POTION)
	assert_eq(res.code, ItemCodes.DEAD, "dead while MapSession is DEAD, whatever the HP: %s" % str(res))
	assert_eq(c.hp, respawn_hp, "no HP restored")
	assert_eq(c.inventory.count(RED_POTION), 2, "no potion consumed")
	assert_eq(ms.respawn(), OK, "respawn")
	assert_eq(ms.state_name(), "IDLE", "respawned (no world: at once)")
	assert_true(items.use_item(RED_POTION).ok, "alive again: the potion works")
	assert_eq(c.inventory.count(RED_POTION), 1)
	if real_ms != null:
		assert_eq(String(real_ms.call("state_name")), real_state, "the MapSession autoload ignored the private death")
	g.map_session = null
	g.free()
	ms.free()
