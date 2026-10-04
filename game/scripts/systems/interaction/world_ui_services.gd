class_name WorldUiServices
extends RefCounted
## Finds the runtime services the interaction system, the loot system and the NPC UI share, so each of them can run
## inside the game (GameContext + autoloads) or standalone (sandbox, tests) without crashing. Every lookup returns
## null when the service is not available.
##
## NpcInteraction (the one conversation controller the interaction system talks through and the NPC UI renders):
##   1. ctx.npc_talk                      if the game shell adds that field to GameContext
##   2. Game.npc_talk                     the wiring QUESTS_AND_DIALOGUE.md asks the Game autoload for
##   3. NpcInteraction.new(Game.quests)   when the Game autoload has the QuestService but no NpcInteraction
##   4. a fallback QuestService on Events + Data.db + Game.character (attached once, cached here) so a sandbox
##      without the Game wiring still runs real quests. The game must provide 1-3: a second attached QuestService would
##      count every kill twice. Tests inject their own NpcInteraction instead of using this.
## The result is cached, so every caller in a session gets the same instance.

static var _talk: NpcInteraction = null
static var _fallback_service: QuestService = null


## The autoload node `autoload_name` ("Events", "Game", "Data", "MapSession", "Debug"), or null.
static func autoload(autoload_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(autoload_name) if tree != null else null


## Data.db (the shipped content), or null.
static func content() -> ContentDB:
	var data := autoload("Data")
	var v: Variant = data.get("db") if data != null else null
	return v if v is ContentDB else null


## The Events bus, or null.
static func events() -> Node:
	return autoload("Events")


## Game.character, or null.
static func character() -> CharacterState:
	var game := autoload("Game")
	var c: Variant = game.get("character") if game != null else null
	return c if c is CharacterState else null


## Game.clock (pausable game time), or 0.
static func clock() -> float:
	var game := autoload("Game")
	var c: Variant = game.get("clock") if game != null else null
	return float(c) if c != null else 0.0


## The MapSession autoload, or null.
static func session() -> Node:
	return autoload("MapSession")


## The shared NpcInteraction (see the class comment), or null when nothing can provide one.
static func npc_talk(ctx: GameContext = null) -> NpcInteraction:
	if ctx != null:
		var from_ctx: Variant = ctx.get("npc_talk")
		if from_ctx is NpcInteraction:
			return from_ctx
	var game := autoload("Game")
	if game != null:
		var from_game: Variant = game.get("npc_talk")
		if from_game is NpcInteraction:
			return from_game
		var quests: Variant = game.get("quests")
		if quests is QuestService:
			if _talk == null or _talk.service != quests:
				_talk = NpcInteraction.new(quests)
			return _talk
	if _talk != null:
		return _talk
	var db := content()
	var bus := events()
	if db == null or game == null:
		return null
	var rng: Variant = game.get("rng")
	_fallback_service = QuestService.create(bus, db, character(), rng if rng is RandomNumberGenerator else null,
		func() -> float: return WorldUiServices.clock())
	_fallback_service.character_provider = func() -> CharacterState: return WorldUiServices.character()
	_fallback_service.attach()
	push_warning("[WorldUiServices] Game has no npc_talk/quests; using a fallback QuestService on Events")
	_talk = NpcInteraction.new(_fallback_service)
	return _talk


## True when npc_talk() had to build its own QuestService (the Game autoload is not wired yet).
static func uses_fallback_service() -> bool:
	return _fallback_service != null


## Drops the cached NpcInteraction (and detaches a fallback QuestService). For tests and scene reloads.
static func reset() -> void:
	if _fallback_service != null:
		_fallback_service.detach()
	_fallback_service = null
	if _talk != null and _talk.is_open():
		_talk.close()
	_talk = null


## Emits `sig` with `args` on `bus` if it has that signal.
static func emit(bus: Object, sig: StringName, args: Array = []) -> void:
	if bus != null and bus.has_signal(sig):
		bus.callv(&"emit_signal", [sig] + args)


## True when `action` was pressed this physics frame for `player`: through player.input_source (so the traversal bot
## can press it), else through Input.
static func pressed(player: Object, action: StringName) -> bool:
	if player != null and "input_source" in player:
		var src: Variant = player.get("input_source")
		if src is Object and (src as Object).has_method("just_pressed"):
			return bool((src as Object).call("just_pressed", action))
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


## True while `action` is held for `player` (input_source first, else Input).
static func held(player: Object, action: StringName) -> bool:
	if player != null and "input_source" in player:
		var src: Variant = player.get("input_source")
		if src is Object and (src as Object).has_method("is_held"):
			return bool((src as Object).call("is_held", action))
	return InputMap.has_action(action) and Input.is_action_pressed(action)


## True when the player may act on world keys now: alive, input enabled, no modal open, MapSession idle (when those
## exist). `session` may be null.
static func player_can_act(player: Object, ctx: GameContext, p_session: Object) -> bool:
	if player == null or (player is Node and not is_instance_valid(player)):
		return false
	if ctx != null and ctx.is_modal_active():
		return false
	if player.has_method("is_input_enabled") and not bool(player.call("is_input_enabled")):
		return false
	if player.has_method("is_dead") and bool(player.call("is_dead")):
		return false
	if p_session != null and p_session.has_method("is_idle") and not bool(p_session.call("is_idle")):
		return false
	return true
