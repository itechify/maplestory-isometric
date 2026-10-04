class_name GameState
extends Node
## Autoload "Game": owns the live CharacterState, the pausable game clock and the gameplay RNG.
##
## Fixed contract (other systems use these): character, clock, paused, rng.
## On top of that this node runs the game's lifecycle: new_game(), load_game(), save_game(), reset_save(),
## start_or_continue(), a debounced autosave (request_autosave()), play-time tracking, and level/AP wiring that
## emits the Events signals. Whenever the character is replaced (new game, load, reset) it emits
## character_replaced and then the refresh signals (Events.stats_changed, hp_changed, mp_changed, mesos_changed,
## inventory_changed, equipment_changed("")), so every UI rebuilds from the new object. See docs/runtime/SAVES.md.
##
## Game-shell additions (docs/runtime/GAME_SHELL.md): the quest system (quests, npc_talk, wired in _ready as
## QUESTS_AND_DIALOGUE.md describes), the HP/MP helpers every system calls (change_hp, change_mp, damage_player:
## StatCalculator plus the Events announcements the death watch listens to), "gender" in new_game() params, and
## close_game() for "quit to title".

## The live character object was replaced. reason: REASON_NEW_GAME, REASON_LOAD or REASON_RESET. Listeners must
## drop references to the old character (and the old inventory/equipment/quest objects) and re-read Game.character;
## the world runtime places the player at Game.character.location (MAP_ARCHITECTURE.md §4.9, via = load).
signal character_replaced(reason: String)
## An autosave ran (error OK) or failed.
signal autosave_finished(slot: String, error: Error)

const DEFAULT_SLOT := "slot1"
const REASON_NEW_GAME := "new_game"
const REASON_LOAD := "load"
const REASON_RESET := "reset"
## CharacterState.gender values a new game accepts ("" = unknown: quick start, tools).
const GENDERS: PackedStringArray = ["male", "female"]

## The one player character in play. Replaced wholesale on new game / load.
var character: CharacterState = CharacterState.new()
## Seconds of unpaused game time since the session started (spawn ticks, buffs and drop lifetimes use this).
var clock: float = 0.0
var paused: bool = false
## Gameplay randomness (damage rolls, drops, spawns). Seeded once per session; tests use their own RNGs.
var rng := RandomNumberGenerator.new()

## The slot this game saves into ("" before new_game()/load_game()).
var current_slot: String = ""
## Unpaused seconds played in this session (the character's total is character.play_time_s).
var session_play_time_s: float = 0.0
## Autosave: a request saves after autosave_debounce_s without further requests, but never later than
## autosave_max_delay_s after the first request of a burst. While MapSession.can_save() is false the save is retried
## every autosave_retry_s. These are engineering timings, not gameplay values.
var autosave_enabled: bool = true
var autosave_debounce_s: float = 2.0
var autosave_max_delay_s: float = 15.0
var autosave_retry_s: float = 1.0
## Save on window close when allowed.
var autosave_on_quit: bool = true
## Events signals that request an autosave (progress milestones). MapSession also requests one when a transition
## reaches IDLE (MAP_ARCHITECTURE.md §4.5 step 15); requests are debounced, so overlaps cost nothing.
const AUTOSAVE_TRIGGERS: PackedStringArray = ["map_entered", "leveled_up", "quest_started", "quest_completed",
	"quest_forfeited"]
## Errors from the last rejected new_game() (for the creation screen).
var last_creation_errors: PackedStringArray = []
## Injection seams (tests): null = the Saves autoload / Data.db / the Events autoload.
var save_service: SaveService = null
var db: ContentDB = null
var event_bus: Node = null
## Injection seam (tests): the MapSession whose DEAD state is_character_dead() reads; null = the MapSession autoload.
var map_session: Node = null
## push_warning() on rejected or degraded new games (tests switch it off).
var log_warnings: bool = true
## The quest system (QUESTS_AND_DIALOGUE.md "Wiring it into the game"): QuestService on the Events bus, following
## the live character through character_provider. null until wire_quests() (the autoload calls it in _ready).
var quests: QuestService = null
## NPC conversations: the NPC actor calls Game.npc_talk.talk(npc_id); the dialogue UI renders its views.
var npc_talk: NpcInteraction = null

var _active := false
var _autosave_pending := false
var _autosave_first_request_at := 0.0
var _autosave_due_at := 0.0
## Real (unpaused-or-not) seconds this node has processed; the autosave timers run on it.
var _realtime := 0.0


func _ready() -> void:
	rng.randomize()
	connect_autosave_triggers(event_bus if event_bus != null else SaveService._autoload("Events"))
	wire_quests()
	_register_debug_commands.call_deferred()


## Creates the quest system once (QUESTS_AND_DIALOGUE.md): QuestService on `bus` (default: event_bus, else the
## Events autoload) with this node's content, RNG and game clock, following `character` through new game and load,
## plus the NpcInteraction the NPC actors and the dialogue UI use. Safe to call twice.
func wire_quests(bus: Object = null) -> void:
	if quests != null:
		return
	var b: Object = bus if bus != null else (event_bus if event_bus != null else SaveService._autoload("Events"))
	quests = QuestService.create(b, _db(), character, rng, func() -> float: return clock)
	quests.character_provider = func() -> CharacterState: return character
	quests.attach()
	npc_talk = NpcInteraction.new(quests)


## Requests an autosave whenever `bus` emits one of AUTOSAVE_TRIGGERS (called from _ready with the Events
## autoload; tests pass a private bus). Safe to call twice.
func connect_autosave_triggers(bus: Node) -> void:
	if bus == null:
		return
	for info: Dictionary in bus.get_signal_list():
		var sig := String(info["name"])
		if not (sig in AUTOSAVE_TRIGGERS):
			continue
		# Drop the signal's own arguments, then pass its name as the autosave reason.
		var cb := Callable(self, &"request_autosave").bind(sig).unbind((info["args"] as Array).size())
		if not bus.is_connected(sig, cb):
			bus.connect(sig, cb)


func _process(delta: float) -> void:
	if not paused:
		clock += delta
		if _active:
			character.play_time_s += delta
			session_play_time_s += delta
	_realtime += delta
	_tick_autosave()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and autosave_on_quit and _active and current_slot != "":
		if _saves() != null and _saves().can_save():
			_saves().save_game(current_slot)


# --- lifecycle ------------------------------------------------------------------------------------------------

## True once a character has been created or loaded (saving and autosave need it).
func has_active_game() -> bool:
	return _active


## Creates a new character (CharacterFactory) and makes it the live game.
## params: {"name", "ap": {stat: points}, "weapon_id", "gender"?: one of GENDERS or "", "slot"?: String =
## DEFAULT_SLOT, "save"?: bool = true}.
## With none of name/ap/weapon_id, the quick-start parameters of new_character.json are used. Writes the initial
## save into the slot (bypassing can_save(): the character stands at the canonical start, no world state exists yet)
## unless "save" is false. Returns ERR_INVALID_PARAMETER (see last_creation_errors) without touching the live game.
func new_game(params: Dictionary = {}) -> Error:
	return _start_new(params, REASON_NEW_GAME)


## Loads a slot into the live game (character replaced wholesale, Events.game_loaded(slot) fires).
## On error the live game is unchanged. "" = the current slot (or DEFAULT_SLOT).
func load_game(slot: String = "") -> Error:
	return _saves().load_game(_slot_or_current(slot))


## Saves the live game into a slot ("" = the current slot). Blocked (ERR_UNAVAILABLE) while MapSession.can_save()
## is false. The slot becomes the current slot.
func save_game(slot: String = "") -> Error:
	var s := _slot_or_current(slot)
	var err := _saves().save_game(s)
	if err == OK:
		current_slot = s
		_autosave_pending = false
	return err


## Writes the live character into a slot ("" = the current slot) exactly as it is, with the location it carries:
## no MapSession world block and no can_save() check. Only for a state MapSession refuses to save but the caller has
## made consistent itself. The one user is the game shell's DeathController.commit_death_for_quit(): a death during a
## warp is not committed until the warp ends (MapSession refuses saves until then), so when the game closes in that
## window the controller applies the penalty itself, sets the respawn location and writes it here. A committed death
## (every other death) is saved with save_game(), which MapSession allows while DEAD once the death is committed.
func save_as_is(slot: String = "") -> Error:
	if not _active:
		return ERR_UNCONFIGURED
	var s := _slot_or_current(slot)
	var err := _saves().save_character(s, character, SaveDocument.world_from_character(character))
	if err == OK:
		current_slot = s
		_autosave_pending = false
	return err


## Debug: deletes the slot ("" = current) with its backup, then starts a clean new game in it (quick-start params
## unless given) and writes its initial save.
func reset_save(slot: String = "", params: Dictionary = {}) -> Error:
	var s := _slot_or_current(slot)
	var p := _with_defaults(params)
	p["slot"] = s
	# Validate first: bad params must not wipe the slot.
	var problems := CharacterFactory.validate(p, _db())
	if not SaveStore.is_valid_slot(s):
		problems.append("invalid slot name '%s'" % s)
	if not problems.is_empty():
		last_creation_errors = problems
		return ERR_INVALID_PARAMETER
	var del := _saves().delete_save(s)
	if del != OK and del != ERR_FILE_NOT_FOUND:
		return del
	return _start_new(p, REASON_RESET)


## Boot helper: loads `slot` if it has a save (or only its backup, which is then loaded), otherwise starts a
## quick-start new game in it. A save that exists but cannot be loaded is returned as an error and NOT overwritten.
func start_or_continue(slot: String = DEFAULT_SLOT) -> Error:
	if _saves().has_save(slot) or _saves().store().has_backup(slot):
		return load_game(slot)
	return new_game({"slot": slot})


## Called by SaveService.load_game(): installs a decoded save as the live game and fires the refresh signals.
func apply_loaded_save(result: SaveLoadResult) -> Error:
	if result == null or not result.ok() or result.character == null:
		return ERR_INVALID_DATA
	_install(result.character, result.slot, REASON_LOAD)
	if result.source == "backup":
		_emit(&"notice", ["Save %s was loaded from its backup (the save file was missing)." % result.slot])
	_emit(&"game_loaded", [result.slot])
	return OK


# --- autosave -------------------------------------------------------------------------------------------------

## Asks for an autosave (map arrival, level-up, quest turn-in, ...). Debounced; runs only when can_save() holds.
## Returns false when ignored (no active game, autosave disabled).
func request_autosave(_reason: String = "") -> bool:
	if not (_active and autosave_enabled and current_slot != ""):
		return false
	if not _autosave_pending:
		_autosave_pending = true
		_autosave_first_request_at = _realtime
	_autosave_due_at = minf(_realtime + autosave_debounce_s, _autosave_first_request_at + autosave_max_delay_s)
	return true


## True while an autosave is waiting for its debounce or for can_save().
func is_autosave_pending() -> bool:
	return _autosave_pending


func _tick_autosave() -> void:
	if not _autosave_pending or _realtime < _autosave_due_at:
		return
	if not _active or current_slot == "":
		_autosave_pending = false
		return
	if not _saves().can_save():
		_autosave_due_at = _realtime + autosave_retry_s
		return
	_autosave_pending = false
	var err := _saves().save_game(current_slot)
	autosave_finished.emit(current_slot, err)


# --- character wiring -----------------------------------------------------------------------------------------

## Adds EXP through Progression and announces it (exp_gained, one leveled_up per level, hp/mp/stats changed).
## A level-up requests an autosave. Returns Progression.gain_exp()'s result.
func gain_exp(amount: int, source: String = "") -> Dictionary:
	var before := character.level
	var r := Progression.gain_exp(character, amount, _db())
	var added := int(r.get("exp_added", 0))
	if added != 0:
		_emit(&"exp_gained", [added, source])
	if character.level > before:
		for lv in range(before + 1, character.level + 1):
			_emit(&"leveled_up", [lv])
		_emit(&"hp_changed", [character.hp, StatCalculator.max_hp(character, _db())])
		_emit(&"mp_changed", [character.mp, StatCalculator.max_mp(character, _db())])
		request_autosave("level_up")
	_emit(&"stats_changed")
	return r


## Spends AP through Progression (allowed stats: canonical beginner.json ap.allocatable_stats) and announces it.
## Returns false if Progression refused.
func allocate_ap(stat: String, amount: int = 1) -> bool:
	var ok := Progression.allocate_ap(character, stat, amount, _db())
	if ok:
		_emit(&"stats_changed")
		_emit(&"hp_changed", [character.hp, StatCalculator.max_hp(character, _db())])
		_emit(&"mp_changed", [character.mp, StatCalculator.max_mp(character, _db())])
	return ok


## Changes HP by `delta` within [0, max HP] (StatCalculator.change_hp) and announces it (Events.hp_changed), even
## when nothing changed, so the HUD and the death watch always see the current value. Every system that changes
## the player's HP should come through here: the game shell's DeathController treats HP 0 as death. Returns the
## change actually applied.
func change_hp(delta: int) -> int:
	var d := _db()
	var applied := StatCalculator.change_hp(character, delta, d)
	_emit(&"hp_changed", [character.hp, StatCalculator.max_hp(character, d)])
	return applied


## Changes MP by `delta` within [0, max MP] and announces it (Events.mp_changed). Returns the change applied.
func change_mp(delta: int) -> int:
	var d := _db()
	var applied := StatCalculator.change_mp(character, delta, d)
	_emit(&"mp_changed", [character.mp, StatCalculator.max_mp(character, d)])
	return applied


## Damage taken (monster touch or attack, already resolved by CombatFormula): Events.player_damaged(amount, source)
## when amount > 0, then change_hp(-amount). Returns the HP actually lost.
func damage_player(amount: int, source_monster_id: String = "") -> int:
	if amount > 0:
		_emit(&"player_damaged", [amount, source_monster_id])
	return -change_hp(-maxi(amount, 0))


## True while the character is dead: HP at the canonical death trigger (formulas/death.json: HP 0), or MapSession in
## DEAD. The game shell takes a death's loss at the moment of death (GAME_SHELL.md "Death and respawn"), so while the
## death notice is up the character already holds the HP it will respawn with (death.json, 50). A system that asks
## "is the player dead?" must ask this (or MapSession), never `character.hp <= 0`.
func is_character_dead() -> bool:
	if Progression.is_dead(character, _db()):
		return true
	var s: Node = map_session if map_session != null else SaveService._autoload("MapSession")
	return s != null and s.has_method("state_name") and String(s.call("state_name")) == "DEAD"


## Ends the live game without saving (the shell saves first): has_active_game() turns false, a pending autosave is
## dropped, play time stops and the clock is unpaused. The character object stays readable until the next
## new_game() / load_game(); current_slot is kept so the title screen can offer it.
func close_game() -> void:
	_active = false
	_autosave_pending = false
	paused = false
	session_play_time_s = 0.0


## Problems with a creation gender ("" = unknown is allowed; otherwise one of GENDERS).
static func validate_gender(value: Variant) -> PackedStringArray:
	var out: PackedStringArray = []
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		out.append("gender must be a string (one of %s)" % ", ".join(GENDERS))
	elif String(value) != "" and not (String(value) in GENDERS):
		out.append("gender '%s' is not one of %s" % [String(value), ", ".join(GENDERS)])
	return out


## Emits every refresh signal for the current character (after a wholesale change).
func refresh_ui() -> void:
	var d := _db()
	_emit(&"stats_changed")
	_emit(&"hp_changed", [character.hp, StatCalculator.max_hp(character, d)])
	_emit(&"mp_changed", [character.mp, StatCalculator.max_mp(character, d)])
	_emit(&"mesos_changed", [character.mesos, 0])
	_emit(&"inventory_changed")
	_emit(&"equipment_changed", [""])


## "H:MM:SS" for a play-time in seconds (slot picker, stats window).
@warning_ignore("integer_division")
static func format_play_time(seconds: float) -> String:
	var total := maxi(0, int(seconds))
	return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


# --- internals ------------------------------------------------------------------------------------------------

## params plus the quick-start parameters when none of name/ap/weapon_id is given.
func _with_defaults(params: Dictionary) -> Dictionary:
	var p := params.duplicate(true)
	if not (p.has("name") or p.has("ap") or p.has("weapon_id")):
		p.merge(CharacterFactory.default_params(_db()))
	return p


func _start_new(params: Dictionary, reason: String) -> Error:
	var p := _with_defaults(params)
	var slot := SaveDocument.as_text(p.get("slot", DEFAULT_SLOT))
	if not SaveStore.is_valid_slot(slot):
		last_creation_errors = PackedStringArray(["invalid slot name '%s'" % slot])
		return ERR_INVALID_PARAMETER
	var creation := CharacterFactory.create(p, _db())
	var problems := creation.errors.duplicate()
	problems.append_array(validate_gender(p.get("gender", "")))
	if not creation.ok or not problems.is_empty():
		last_creation_errors = problems
		if log_warnings:
			push_warning("[Game] new game rejected: " + "; ".join(problems))
		return ERR_INVALID_PARAMETER
	last_creation_errors = PackedStringArray()
	if log_warnings:
		for w in creation.warnings:
			push_warning("[Game] " + w)
	creation.character.gender = SaveDocument.as_text(p.get("gender", ""))
	_install(creation.character, slot, reason)
	if bool(p.get("save", true)):
		var err := _saves().save_character(slot, character, SaveDocument.world_from_character(character))
		if err != OK:
			_emit(&"notice", ["Could not write the save file (%s)." % error_string(err)])
	return OK


func _install(c: CharacterState, slot: String, reason: String) -> void:
	character = c
	current_slot = slot
	_active = true
	session_play_time_s = 0.0
	_autosave_pending = false
	character_replaced.emit(reason)
	refresh_ui()


func _slot_or_current(slot: String) -> String:
	if slot != "":
		return slot
	return current_slot if current_slot != "" else DEFAULT_SLOT


func _saves() -> SaveService:
	if save_service != null:
		return save_service
	return SaveService._autoload("Saves") as SaveService


func _db() -> ContentDB:
	if db != null:
		return db
	var data := SaveService._autoload("Data")
	return data.get("db") as ContentDB if data != null else null


## Emits a signal on the event bus (the Events autoload unless event_bus is injected).
func _emit(sig: StringName, args: Array = []) -> void:
	var bus := event_bus if event_bus != null else SaveService._autoload("Events")
	if bus != null:
		bus.callv(&"emit_signal", [sig] + args)


func _register_debug_commands() -> void:
	var dbg := SaveService._autoload("Debug")
	if dbg == null or not dbg.has_method("register_command"):
		return
	dbg.call("register_command", "save", "save [slot]: save the game (default: current slot)", _cmd_save)
	dbg.call("register_command", "load", "load [slot]: load a save (default: current slot)", _cmd_load)
	dbg.call("register_command", "saves", "saves: list save slots", _cmd_saves)
	dbg.call("register_command", "delete_save", "delete_save <slot>: delete a save and its backup", _cmd_delete)
	dbg.call("register_command", "reset_save", "reset_save [slot]: wipe the slot and start a clean new game in it",
		_cmd_reset)
	if quests != null:
		quests.register_debug_commands(dbg)


func _cmd_save(args: PackedStringArray) -> String:
	var slot := _slot_or_current(args[0] if args.size() > 0 else "")
	var err := save_game(slot)
	return "saved %s" % slot if err == OK else "save failed: %s (%s)" % [error_string(err), _saves().last_error_message]


func _cmd_load(args: PackedStringArray) -> String:
	var slot := _slot_or_current(args[0] if args.size() > 0 else "")
	var err := load_game(slot)
	return "loaded %s" % slot if err == OK else "load failed: %s (%s)" % [error_string(err), _saves().last_error_message]


func _cmd_saves(_args: PackedStringArray) -> String:
	var lines: PackedStringArray = []
	for e in _saves().list_saves():
		if bool(e["ok"]):
			var m: Dictionary = e["meta"]
			lines.append("%s: %s Lv %d, %s, %s (%s)%s" % [e["slot"], m.get("name", ""), int(m.get("level", 0)),
				m.get("map_name", ""), format_play_time(float(m.get("play_time_s", 0.0))), e["saved_at"],
				" [save file missing; loads its backup]" if e.get("source", "main") == "backup" else ""])
		else:
			lines.append("%s: unreadable (%s)%s" % [e["slot"], e["error_text"], ", backup available" if e["has_backup"] else ""])
	return "no saves" if lines.is_empty() else "\n".join(lines)


func _cmd_delete(args: PackedStringArray) -> String:
	if args.is_empty():
		return "usage: delete_save <slot>"
	var err := _saves().delete_save(args[0])
	return "deleted %s" % args[0] if err == OK else "delete failed: %s" % error_string(err)


func _cmd_reset(args: PackedStringArray) -> String:
	var slot := _slot_or_current(args[0] if args.size() > 0 else "")
	var err := reset_save(slot)
	return "reset %s: new character in %s" % [slot, character.location.get("map_id", "")] if err == OK \
		else "reset failed: %s (%s)" % [error_string(err), "; ".join(last_creation_errors)]
