class_name MisoUiEnv
extends RefCounted
## What a MisoStory UI root (HUD, windows) talks to, resolved once so the same widget code runs in three settings:
##
##   - in the game: MisoUiEnv.from_ctx(ctx) (the shell's GameContext plus the Game / Data / Events autoloads);
##   - standalone (sandbox scenes, no setup() call): MisoUiEnv.standalone(), the autoloads with a private, empty
##     GameContext so windows still have a stack to register with;
##   - in tests: MisoUiEnv.isolated(character, db, bus) with every field injected and no autoload lookups at all.
##
## The character is never cached: Game replaces it wholesale on new game / load / reset, so character() re-resolves
## on every call (an injected character or provider wins). Null fields mean "not available" and every accessor is
## null-safe, so a UI built on this never errors when part of the game is missing.

## The shell's context (window stack, modal stack). from_ctx / standalone always set one.
var ctx: GameContext = null
## True when this env made its own private ctx (standalone): the UI root then handles Esc itself.
var owns_ctx: bool = false
## Content; null = Data.db.
var db: ContentDB = null
## Event bus (anything with the Events signals); null = the Events autoload.
var bus: Object = null
## The Game autoload or a stand-in with allocate_ap(stat, n), character, and optionally character_replaced,
## request_autosave(reason) and quests (a QuestService). null = the Game autoload.
var game: Object = null
## Fixed character (tests); wins over everything else.
var character_override: CharacterState = null
## () -> CharacterState; used when set and no override is given.
var character_provider: Callable = Callable()
## Quest engine to read (tests may pass the attached QuestService's engine). null = a cached read-only engine.
var quest_engine_override: QuestEngine = null
## () -> String: the current map id (null-safe default: MapSession.current_map).
var map_id_provider: Callable = Callable()
## The MapSession autoload or a stand-in with current_map, trail_destination and the trail_changed(dest_map_id)
## signal (tests inject a private map_session.gd instance). null = the MapSession autoload.
var map_session: Object = null
## false = never look up autoloads (tests).
var use_autoloads: bool = true

var _local_engine: QuestEngine = null
var _local_engine_db: ContentDB = null


## The in-game environment: the shell's ctx plus the autoloads.
static func from_ctx(p_ctx: GameContext) -> MisoUiEnv:
	var e := MisoUiEnv.new()
	e.ctx = p_ctx
	if e.ctx == null:
		e.ctx = GameContext.new()
		e.owns_ctx = true
	return e


## Standalone (no shell): autoloads plus a private GameContext.
static func standalone() -> MisoUiEnv:
	return from_ctx(null)


## Tests: everything injected, no autoload lookups. `game` may be a GameState instance that is not in the tree (its
## allocate_ap emits on its injected event_bus) or null (AP then goes through Progression directly).
static func isolated(p_character: CharacterState, p_db: ContentDB, p_bus: Object, p_ctx: GameContext = null,
		p_game: Object = null) -> MisoUiEnv:
	var e := MisoUiEnv.new()
	e.use_autoloads = false
	e.character_override = p_character
	e.db = p_db
	e.bus = p_bus
	e.game = p_game
	e.ctx = p_ctx
	if e.ctx == null:
		e.ctx = GameContext.new()
		e.owns_ctx = true
	return e


# --- resolution -----------------------------------------------------------------------------------------------

func get_db() -> ContentDB:
	if db != null:
		return db
	var data := autoload("Data")
	if data != null:
		var d: Variant = data.get("db")
		if d is ContentDB:
			return d
	return null


func get_bus() -> Object:
	if bus != null:
		return bus
	return autoload("Events")


func get_game() -> Object:
	if game != null:
		return game
	return autoload("Game")


## The live character, or null when none is available.
func character() -> CharacterState:
	if character_override != null:
		return character_override
	if character_provider.is_valid():
		var c: Variant = character_provider.call()
		if c is CharacterState:
			return c
	var g := get_game()
	if g != null:
		var gc: Variant = g.get("character")
		if gc is CharacterState:
			return gc
	return null


## An ItemService on the live character (every item change the UI makes goes through it, so Events fire).
## null when there is no character or content.
func items() -> ItemService:
	var c := character()
	var d := get_db()
	if c == null or d == null:
		return null
	return ItemService.new(c, d, get_bus())


## The QuestService the game wired (Game.quests), or null.
func quest_service() -> QuestService:
	var g := get_game()
	if g == null:
		return null
	var q: Variant = g.get("quests")
	return q if q is QuestService else null


## A quest engine pointed at the live character, for reading (summaries, availability, rewards). Uses the injected
## engine when given; otherwise a cached read-only engine (sharing Game.quests' catalog when one exists). Null when
## no character or content is available.
func quest_engine() -> QuestEngine:
	var c := character()
	if quest_engine_override != null:
		if c != null:
			quest_engine_override.character = c
		return quest_engine_override
	var d := get_db()
	if c == null or d == null:
		return null
	if _local_engine == null or _local_engine_db != d:
		var svc := quest_service()
		var catalog: QuestCatalog = svc.engine.catalog if svc != null and svc.engine != null else null
		_local_engine = QuestEngine.new(c, d, null, Callable(), catalog)
		_local_engine_db = d
	_local_engine.character = c
	return _local_engine


## The map session (current map, the trail under the player), or null.
func get_map_session() -> Object:
	if map_session != null:
		return map_session
	return autoload("MapSession")


## The current map id ("" when unknown).
func current_map_id() -> String:
	if map_id_provider.is_valid():
		return String(map_id_provider.call())
	var ms := get_map_session()
	if ms != null:
		var m: Variant = ms.get("current_map")
		if m != null:
			return String(m)
	var c := character()
	if c != null:
		return String(c.location.get("map_id", ""))
	return ""


## The map at the other end of the trail the player is on (MapSession.trail_destination), or "" off trails.
func trail_destination() -> String:
	var ms := get_map_session()
	if ms == null:
		return ""
	var t: Variant = ms.get("trail_destination")
	return String(t) if t != null else ""


## True while the character is dead: Game.is_character_dead() (MapSession DEAD, or HP at the death trigger).
## `fallback` without a game that can tell. Never `hp <= 0`: a committed death already holds the respawn HP
## (GAME_SHELL.md "Death and respawn").
func is_character_dead(fallback: bool = false) -> bool:
	var g := get_game()
	if g == null or not g.has_method("is_character_dead"):
		return fallback
	return bool(g.call("is_character_dead"))


# --- actions --------------------------------------------------------------------------------------------------

## Spends AP through Game.allocate_ap (which announces it); without a game, through Progression plus the same
## signals on the bus. Returns false when refused.
func allocate_ap(stat: String, amount: int = 1) -> bool:
	var g := get_game()
	if g != null and g.has_method("allocate_ap"):
		return bool(g.call("allocate_ap", stat, amount))
	var c := character()
	var d := get_db()
	if c == null:
		return false
	var ok := Progression.allocate_ap(c, stat, amount, d)
	if ok and d != null:
		emit("stats_changed")
		emit("hp_changed", [c.hp, StatCalculator.max_hp(c, d)])
		emit("mp_changed", [c.mp, StatCalculator.max_mp(c, d)])
	return ok


## Asks the game for a (debounced) autosave, when the game supports it.
func request_autosave(reason: String) -> void:
	var g := get_game()
	if g != null and g.has_method("request_autosave"):
		g.call("request_autosave", reason)


## Emits a signal on the bus (no-op when unavailable or unknown).
func emit(sig: String, args: Array = []) -> void:
	var b := get_bus()
	if b == null or not b.has_signal(sig):
		return
	b.callv(&"emit_signal", [StringName(sig)] + args)


## Shows a line in the HUD message log (Events.notice).
func notice(text: String) -> void:
	emit("notice", [text])


## Connects `cb` to the bus signal `sig` (idempotent). Returns false when unavailable.
func connect_bus(sig: String, cb: Callable) -> bool:
	var b := get_bus()
	if b == null or not b.has_signal(sig):
		return false
	if not b.is_connected(sig, cb):
		b.connect(sig, cb)
	return true


func disconnect_bus(sig: String, cb: Callable) -> void:
	var b := get_bus()
	if b != null and b.has_signal(sig) and b.is_connected(sig, cb):
		b.disconnect(sig, cb)


## Connects `cb` to the map session's signal `sig` (trail_changed; idempotent). Returns false when unavailable.
func connect_session(sig: String, cb: Callable) -> bool:
	var ms := get_map_session()
	if ms == null or not ms.has_signal(sig):
		return false
	if not ms.is_connected(sig, cb):
		ms.connect(sig, cb)
	return true


func disconnect_session(sig: String, cb: Callable) -> void:
	var ms := get_map_session()
	if ms != null and ms.has_signal(sig) and ms.is_connected(sig, cb):
		ms.disconnect(sig, cb)


## Connects to Game.character_replaced when the game has it.
func connect_character_replaced(cb: Callable) -> void:
	var g := get_game()
	if g != null and g.has_signal("character_replaced") and not g.is_connected("character_replaced", cb):
		g.connect("character_replaced", cb)


func disconnect_character_replaced(cb: Callable) -> void:
	var g := get_game()
	if g != null and g.has_signal("character_replaced") and g.is_connected("character_replaced", cb):
		g.disconnect("character_replaced", cb)


func window_opened(w: Control) -> void:
	if ctx != null:
		ctx.window_opened(w)


func window_closed(w: Control) -> void:
	if ctx != null:
		ctx.window_closed(w)


## True while a dialogue, shop, console or menu owns the keyboard (UI hotkeys stay quiet then).
func is_modal_active() -> bool:
	return ctx != null and ctx.is_modal_active()


## An autoload node by name, or null (always null when use_autoloads is false).
func autoload(autoload_name: String) -> Node:
	if not use_autoloads:
		return null
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null(NodePath(autoload_name))


# --- display helpers shared by the HUD and the windows ---------------------------------------------------------

## Pixels at the bottom of `ui`'s area taken by another UI root's bottom-wide bar (the HUD's status bar), so a window
## or a chat sits above the gauges instead of covering them. Found by layout, not by name: any visible direct child
## of a sibling UI root (the other subsystems under ctx.ui_root) that is anchored across the bottom edge. 0 without
## one (standalone, tests without a HUD). NpcUi (dialogue, shop) and MisoWindowsRoot (the character windows) use it.
static func bottom_bar_inset(ui: Control) -> float:
	var root: Node = ui.get_parent() if ui != null else null
	if root == null or not ui.is_inside_tree():
		return 0.0
	var area_bottom := ui.get_global_rect().end.y
	var top := area_bottom
	for sibling in root.get_children():
		if sibling == ui or not (sibling is Control) or not (sibling as Control).is_visible_in_tree():
			continue
		for c in sibling.get_children():
			if c is Control and (c as Control).visible and is_bottom_bar(c as Control):
				top = minf(top, (c as Control).get_global_rect().position.y)
	return maxf(0.0, area_bottom - top)


## True for a control anchored across the whole bottom edge (a bottom-wide bar such as the HUD's status bar).
static func is_bottom_bar(c: Control) -> bool:
	return c.anchor_top >= 0.99 and c.anchor_bottom >= 0.99 and c.anchor_left <= 0.01 and c.anchor_right >= 0.99 \
		and not c.top_level


## The first keyboard key bound to an input action ("I", "1"), read from the InputMap (Controls registers it), or
## "" when the action does not exist.
static func key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		var k := ev as InputEventKey
		if k != null:
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			return OS.get_keycode_string(code)
	return ""


## The display name of the character's job ("Beginner"), from canonical formulas/<slug>.json "name".
func job_name(c: CharacterState) -> String:
	if c == null:
		return ""
	var d := get_db()
	if d != null and d.has("formulas", c.job):
		var n: Variant = d.formula(c.job).get("name")
		if n != null and String(n) != "":
			return String(n)
	return c.job.capitalize()


## An item's display name ("" when unknown).
func item_name(item_id: String) -> String:
	var d := get_db()
	if d == null or not d.has("items", item_id):
		return item_id
	return String(d.item(item_id).get("name", item_id))


## A quest's display name.
func quest_name(quest_id: String) -> String:
	var d := get_db()
	if d == null or not d.has("quests", quest_id):
		return quest_id
	return String(d.quest(quest_id).get("name", quest_id))
