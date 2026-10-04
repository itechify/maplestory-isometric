class_name QuestService
extends RefCounted
## The thin, node-free seam between the Events bus and the pure QuestEngine.
##
## In:  monster_killed, item_used, item_gained, item_lost, npc_talked, map_entered  -> engine progress hooks
## Out: quest_started, quest_progressed, quest_completed, quest_forfeited, plus the facts a quest causes:
##      item_gained / item_lost / inventory_changed (accept items, hand-ins, rewards); the EXP reward exactly as
##      Game.gain_exp() announces EXP: exp_gained(added, "quest:<id>"), one leveled_up(lv) per level gained,
##      hp_changed / mp_changed after a level-up, stats_changed (Progression.gain_exp is pure, so nobody else announces
##      quest level-ups); mesos_changed(mesos, delta); inventory_full(item_id) when a quest action is refused for a
##      full inventory.
##
## Wire it once in the Game autoload (wave 2):
##   var quests := QuestService.create(Events, Data.db, character, rng, func() -> float: return clock)
##   quests.character_provider = func() -> CharacterState: return character   # follows new game / load
##   quests.attach()
##   quests.register_debug_commands(Debug)                                    # optional console commands
## and talk to NPCs through NpcInteraction.new(quests).
##
## `bus` is any Object with the Events signals: the Events autoload in the game, a private events.gd instance in
## tests, or null (silent). The service never looks the bus up itself.

## Events signal -> handler method.
const INPUTS := {
	"monster_killed": "_on_monster_killed",
	"item_used": "_on_item_used",
	"item_gained": "_on_item_gained",
	"item_lost": "_on_item_lost",
	"npc_talked": "_on_npc_talked",
	"map_entered": "_on_map_entered",
}

var engine: QuestEngine
var bus: Object
## Optional () -> CharacterState. When set, the engine follows it before every call (Game.character is replaced on
## new game and load).
var character_provider: Callable
var _attached := false


func _init(p_engine: QuestEngine, p_bus: Object = null) -> void:
	engine = p_engine
	bus = p_bus


## Builds the engine and the service in one call.
static func create(p_bus: Object, db: ContentDB, character: CharacterState, rng: RandomNumberGenerator = null,
		clock: Callable = Callable()) -> QuestService:
	return QuestService.new(QuestEngine.new(character, db, rng, clock), p_bus)


## Connects the input signals of `bus`. Safe to call twice.
func attach() -> void:
	if _attached or bus == null:
		return
	for sig: String in INPUTS:
		if bus.has_signal(sig):
			var cb := Callable(self, String(INPUTS[sig]))
			if not bus.is_connected(sig, cb):
				bus.connect(sig, cb)
	_attached = true


func detach() -> void:
	if not _attached or bus == null:
		return
	for sig: String in INPUTS:
		var cb := Callable(self, String(INPUTS[sig]))
		if bus.has_signal(sig) and bus.is_connected(sig, cb):
			bus.disconnect(sig, cb)
	_attached = false


func is_attached() -> bool:
	return _attached


## Points the engine at another character (e.g. after loading a save).
func set_character(c: CharacterState) -> void:
	engine.character = c


# --- actions (engine call + Events) ---------------------------------------------------------------------------

func accept(quest_id: String, at_npc_id: String = "") -> Dictionary:
	_sync()
	var r := engine.accept(quest_id, at_npc_id)
	dispatch_result(r)
	return r


func complete(quest_id: String, options: Dictionary = {}) -> Dictionary:
	_sync()
	var r := engine.complete(quest_id, options)
	dispatch_result(r)
	return r


func forfeit(quest_id: String) -> Dictionary:
	_sync()
	var r := engine.forfeit(quest_id)
	dispatch_result(r)
	return r


## Runs the NPC-talk hook directly (NpcInteraction uses it when the service is not attached to a bus).
func handle_npc_talked(npc_id: String) -> void:
	_on_npc_talked(npc_id)


## Emits the Events for a result's effects, plus inventory_full when it failed for a full inventory.
func dispatch_result(r: Dictionary) -> void:
	dispatch(QuestJson.arr(r.get("effects")))
	if not bool(r.get("ok", true)) and QuestJson.s(r.get("reason")) == "inventory_full":
		_emit("inventory_full", [QuestJson.s(r.get("item_id"))])


## Emits the Events for a list of engine / dialogue effects (see QuestEngine). Unknown effect types are ignored.
func dispatch(effects: Array) -> void:
	var inventory_touched := false
	for fx: Variant in effects:
		var e := QuestJson.dict(fx)
		match QuestJson.s(e.get("type")):
			"quest_started", "quest_progressed", "quest_completed", "quest_forfeited":
				_emit(QuestJson.s(e.get("type")), [QuestJson.s(e.get("quest_id"))])
			"item_gained", "item_lost":
				_emit(QuestJson.s(e.get("type")), [QuestJson.s(e.get("item_id")), QuestJson.i(e.get("qty"))])
				inventory_touched = true
			"exp_gained":
				_dispatch_exp(e)
			"mesos_changed":
				_emit("mesos_changed", [QuestJson.i(e.get("mesos")), QuestJson.i(e.get("delta"))])
			"fame_changed":
				_emit("stats_changed", [])
			"action_failed":
				if QuestJson.s(e.get("reason")) == "inventory_full":
					_emit("inventory_full", [QuestJson.s(e.get("item_id"))])
	if inventory_touched:
		_emit("inventory_changed", [])


## Announces a quest EXP reward exactly as the Game autoload's gain_exp() does (scripts/autoload/game_state.gd):
## exp_gained(added, source) when EXP was added, one leveled_up(lv) per level gained, hp_changed / mp_changed with the
## derived maxima after a level-up (Progression raises base max HP/MP and may heal), and stats_changed always.
func _dispatch_exp(e: Dictionary) -> void:
	# The EXP Progression actually added (less than the reward only at the level cap).
	var added := QuestJson.i(e.get("exp_added"))
	if added != 0:
		_emit("exp_gained", [added, QuestJson.s(e.get("source"))])
	var gained := QuestJson.i(e.get("levels_gained"))
	var c := engine.character
	if gained > 0:
		var new_level := QuestJson.i(e.get("new_level"), c.level)
		for lv in range(new_level - gained + 1, new_level + 1):
			_emit("leveled_up", [lv])
		_emit("hp_changed", [c.hp, StatCalculator.max_hp(c, engine.db)])
		_emit("mp_changed", [c.mp, StatCalculator.max_mp(c, engine.db)])
	_emit("stats_changed", [])


# --- debug console (Phase 20) ---------------------------------------------------------------------------------

## Registers quest console commands on the Debug autoload (any object with register_command(name, help, handler)).
func register_debug_commands(debug: Object) -> void:
	if debug == null or not debug.has_method("register_command"):
		return
	debug.call("register_command", "quests", "quests: list active and completed quests", _cmd_list)
	debug.call("register_command", "quest", "quest <id>: status, objectives and journal text", _cmd_status)
	debug.call("register_command", "quest_accept", "quest_accept <id>: accept if available (anywhere)", _cmd_accept)
	debug.call("register_command", "quest_complete", "quest_complete <id> [force]: complete; force first satisfies kill/use/talk/visit/quiz objectives", _cmd_complete)
	debug.call("register_command", "quest_reset", "quest_reset <id>: forget the quest entirely", _cmd_reset)


func _cmd_list(_argv: Variant) -> String:
	_sync()
	return "active: %s\ncompleted: %s" % [", ".join(engine.active_quests()), ", ".join(engine.completed_quests())]


func _cmd_status(argv: Variant) -> String:
	var args := QuestJson.strings(argv)
	_sync()
	if args.is_empty():
		return "usage: quest <id>"
	var q := String(args[0])
	var d := engine.definition(q)
	if d == null:
		return "unknown quest %s" % q
	var lines := PackedStringArray(["%s %s: %s" % [q, d.name, engine.status(q)]])
	for row: Dictionary in engine.objective_status(q):
		lines.append("  [%s] %s %d/%d" % ["x" if row["done"] else " ", row["key"], row["current"], row["required"]])
	lines.append("  " + engine.journal_text(q))
	return "\n".join(lines)


func _cmd_accept(argv: Variant) -> String:
	var args := QuestJson.strings(argv)
	if args.is_empty():
		return "usage: quest_accept <id>"
	var r := accept(String(args[0]))
	return "accepted" if bool(r["ok"]) else "refused: %s %s" % [r["reason"], r.get("reasons", "")]


func _cmd_complete(argv: Variant) -> String:
	var args := QuestJson.strings(argv)
	if args.is_empty():
		return "usage: quest_complete <id> [force]"
	_sync()
	var q := String(args[0])
	var d := engine.definition(q)
	if d == null:
		return "unknown quest %s" % q
	if args.size() > 1 and String(args[1]) == "force" and engine.status(q) == QuestLog.IN_PROGRESS:
		for o: Dictionary in d.objectives:
			match String(o["kind"]):
				"monster_kills":
					engine.quest_log().add_kills(q, o["id"], int(o["count"]), int(o["count"]))
				"item_usage":
					engine.quest_log().add_uses(q, o["id"], int(o["count"]), int(o["count"]))
				"map_visit":
					engine.quest_log().mark_visited(q, o["id"])
				"other":
					engine.quest_log().set_other(q, String(o["type"]), true)
	var r := complete(q, {"at_npc_id": d.end_npc_id})
	return "completed" if bool(r["ok"]) else "refused: %s %s" % [r["reason"], r.get("blockers", "")]


func _cmd_reset(argv: Variant) -> String:
	var args := QuestJson.strings(argv)
	_sync()
	if args.is_empty():
		return "usage: quest_reset <id>"
	engine.quest_log().entries.erase(String(args[0]))
	_emit("quest_forfeited", [String(args[0])])
	return "reset %s" % args[0]


# --- input handlers -------------------------------------------------------------------------------------------

func _on_monster_killed(monster_id: String, _map_id: String = "") -> void:
	_sync()
	_progressed(engine.on_monster_killed(monster_id))


func _on_item_used(item_id: String) -> void:
	_sync()
	_progressed(engine.on_item_used(item_id))


func _on_item_gained(item_id: String, quantity: int = 1) -> void:
	_sync()
	_progressed(engine.on_item_gained(item_id, quantity))


func _on_item_lost(item_id: String, quantity: int = 1) -> void:
	_sync()
	_progressed(engine.on_item_lost(item_id, quantity))


func _on_npc_talked(npc_id: String) -> void:
	_sync()
	_progressed(engine.on_npc_talk(npc_id))


func _on_map_entered(map_id: String, _previous_map_id: String = "") -> void:
	_sync()
	_progressed(engine.on_map_entered(map_id))


func _progressed(ids: PackedStringArray) -> void:
	for q in ids:
		_emit("quest_progressed", [q])


func _sync() -> void:
	if character_provider.is_valid():
		var c: Variant = character_provider.call()
		if c is CharacterState and c != engine.character:
			engine.character = c


func _emit(sig: String, args: Array) -> void:
	if bus == null or not bus.has_signal(sig):
		return
	bus.callv("emit_signal", [sig] + args)
