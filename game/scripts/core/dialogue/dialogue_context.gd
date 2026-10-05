class_name DialogueContext
extends RefCounted
## What a running conversation can see and do: conditions are evaluated against the character and quest state, and
## actions are executed through QuestEngine. Pure; every change is reported as effect dictionaries (see QuestEngine)
## to `sink` (QuestService.dispatch in the game) and kept in `effects`.
##
## Conditions ({"type": ...}; an empty or missing condition is true):
##   quest_status        {"quest", "is": "not_started" | "in_progress" | "completed" | [..]}
##   quest_available     {"quest"}                     QuestEngine.is_available
##   quest_ready         {"quest"}                     ready to turn in here (the quiz may still be pending)
##   quest_can_complete  {"quest"}                     every objective done (turn-in talk = this NPC)
##   quest_items_lost    {"quest"}                     an accept item an unfinished objective needs is gone
##   objective           {"quest", "kind", "id"?, "done"?: bool = true}
##   level               {"min"?, "max"?}
##   job                 {"is": "beginner" | [..]}     slug or MeowDB display name
##   item_count          {"item", "min"?, "max"?}
##   flag                {"flag", "equals"?: value = true}   CharacterState.flags
##   mesos               {"min"?, "max"?}
##   unfinished_quests   {"region"?}                   a quest of the region (canonical record "region") is not completed
##   all / any           {"of": [Condition]}
##   not                 {"of": Condition}
## Actions ({"type": ...}); a failing action stops the list and the node's on_fail decides where to go:
##   accept_quest        {"quest"}                     at this NPC
##   complete_quest      {"quest", "quiz_choice"?, "selection_index"?}   at this NPC
##   answer_quiz         {"quest", "choice"}           grades a quiz answer without completing (fails "wrong_answer")
##   forfeit_quest       {"quest"}
##   reissue_quest_items {"quest"}                     the canonical "If you lost the items" re-issue
##   open_shop           {"shop"}                      emits an {"type": "open_shop"} request the UI handles
##   give_item           {"item", "qty"?: 1}
##   take_item           {"item", "qty"?: 1}
##   set_flag            {"flag", "value"?: true}
##   depart              {"route"}                     boards the NPC's transport route at the departure boundary
##                                                     (NpcTransport.depart; fails level_too_low, not_enough_mesos,
##                                                     not_built, no_route) and emits a "departure_requested" effect
## Live values ({"type": ...}) fill a line's "live" args at view time (DialogueRunner):
##   unfinished_quests   {"region"?}                   NpcTransport.unfinished_text: the quests still to do, chains grouped

const CONDITION_TYPES: PackedStringArray = ["quest_status", "quest_available", "quest_ready", "quest_can_complete",
	"quest_items_lost", "objective", "level", "job", "item_count", "flag", "mesos", "unfinished_quests", "all", "any",
	"not"]
const ACTION_TYPES: PackedStringArray = ["accept_quest", "complete_quest", "answer_quiz", "forfeit_quest",
	"reissue_quest_items", "open_shop", "give_item", "take_item", "set_flag", "depart"]
const LIVE_TYPES: PackedStringArray = ["unfinished_quests"]

var engine: QuestEngine
## The NPC being talked to.
var npc_id: String = ""
## func(effects: Array) -> void, called after every successful action. Optional.
var sink: Callable
## Every effect produced in this conversation, in order.
var effects: Array = []
## The result of the last action list ({"ok", "reason", ...}).
var last_result: Dictionary = {}


func _init(p_engine: QuestEngine = null, p_npc_id: String = "", p_sink: Callable = Callable()) -> void:
	engine = p_engine
	npc_id = p_npc_id
	sink = p_sink


func character() -> CharacterState:
	return engine.character


# --- conditions -----------------------------------------------------------------------------------------------

## Evaluates a condition (null / {} = true). Unknown types are false (and reported by validate_condition).
func check(cond: Variant) -> bool:
	if cond == null:
		return true
	if not (cond is Dictionary):
		return false
	var c: Dictionary = cond
	if c.is_empty():
		return true
	var q := QuestJson.s(c.get("quest"))
	match QuestJson.s(c.get("type")):
		"all":
			for sub: Variant in QuestJson.arr(c.get("of")):
				if not check(sub):
					return false
			return true
		"any":
			for sub: Variant in QuestJson.arr(c.get("of")):
				if check(sub):
					return true
			return false
		"not":
			return not check(c.get("of"))
		"quest_status":
			return engine.status(q) in QuestJson.strings(c.get("is"))
		"quest_available":
			return engine.is_available(q)
		"quest_ready":
			return engine.ready_to_turn_in(q, npc_id)
		"quest_can_complete":
			return engine.can_complete(q, npc_id)
		"quest_items_lost":
			return not engine.lost_items(q).is_empty()
		"objective":
			return engine.objective_done(q, QuestJson.s(c.get("kind")), QuestJson.s(c.get("id"))) == QuestJson.b(c.get("done"), true)
		"level":
			return _in_range(character().level, c)
		"job":
			return engine.job_matches(QuestJson.strings(c.get("is")))
		"item_count":
			return _in_range(character().inventory.count(QuestJson.s(c.get("item"))), c)
		"flag":
			return _same(character().flags.get(QuestJson.s(c.get("flag")), null), c.get("equals", true))
		"mesos":
			return _in_range(character().mesos, c)
		"unfinished_quests":
			return not engine.unfinished_quests(QuestJson.s(c.get("region"))).is_empty()
	return false


## A live value for a line's "live" args (see the class comment); "" for an unknown type.
func live_value(query: Dictionary) -> String:
	match QuestJson.s(query.get("type")):
		"unfinished_quests":
			return NpcTransport.unfinished_text(engine, QuestJson.s(query.get("region")))
	return ""


# --- actions --------------------------------------------------------------------------------------------------

## Runs actions in order; stops at the first failure. Returns the failing result, or {"ok": true} with all effects.
func run(actions: Array) -> Dictionary:
	var all_effects: Array = []
	for a: Variant in actions:
		var r := run_action(QuestJson.dict(a))
		all_effects.append_array(QuestJson.arr(r.get("effects")))
		if not bool(r.get("ok", false)):
			last_result = r
			return r
	last_result = {"ok": true, "reason": "", "effects": all_effects}
	return last_result


## Runs one action and forwards its effects to `sink`.
func run_action(a: Dictionary) -> Dictionary:
	var q := QuestJson.s(a.get("quest"))
	var r: Dictionary = {}
	match QuestJson.s(a.get("type")):
		"accept_quest":
			r = engine.accept(q, npc_id)
		"complete_quest":
			var opts := {"at_npc_id": npc_id}
			if a.has("quiz_choice"):
				opts["quiz_choice"] = QuestJson.i(a.get("quiz_choice"), -1)
			if a.has("selection_index"):
				opts["selection_index"] = QuestJson.i(a.get("selection_index"), -1)
			r = engine.complete(q, opts)
		"answer_quiz":
			r = engine.answer_quiz(q, QuestJson.i(a.get("choice"), -1))
		"forfeit_quest":
			r = engine.forfeit(q)
		"reissue_quest_items":
			r = engine.reissue_lost_items(q)
		"open_shop":
			var shop := QuestJson.s(a.get("shop"))
			r = {"ok": not shop.is_empty(), "reason": "" if not shop.is_empty() else "no_shop",
				"effects": [{"type": "open_shop", "shop_id": shop, "npc_id": npc_id}] if not shop.is_empty() else []}
		"give_item":
			r = engine.give_items([{"item_id": QuestJson.s(a.get("item")), "count": maxi(1, QuestJson.i(a.get("qty"), 1))}])
		"take_item":
			r = engine.take_items([{"item_id": QuestJson.s(a.get("item")), "count": maxi(1, QuestJson.i(a.get("qty"), 1))}])
		"set_flag":
			r = engine.set_flag(QuestJson.s(a.get("flag")), a.get("value", true))
		"depart":
			r = NpcTransport.depart(engine, npc_id, QuestJson.i(a.get("route"), -1))
		_:
			r = {"ok": false, "reason": "unknown_action", "effects": []}
	var fx := QuestJson.arr(r.get("effects"))
	if not fx.is_empty():
		effects.append_array(fx)
		if sink.is_valid():
			sink.call(fx)
	if not bool(r.get("ok", false)) and sink.is_valid():
		# Failures are reported too, so the service can surface them (e.g. Events.inventory_full).
		sink.call([{"type": "action_failed", "action": QuestJson.s(a.get("type")), "quest_id": q,
			"reason": QuestJson.s(r.get("reason")), "item_id": QuestJson.s(r.get("item_id"))}])
	return r


# --- validation -----------------------------------------------------------------------------------------------

static func validate_condition(cond: Variant, where: String = "") -> PackedStringArray:
	var errs := PackedStringArray()
	if cond == null:
		return errs
	if not (cond is Dictionary):
		errs.append("%s: condition is not an object" % where)
		return errs
	var c: Dictionary = cond
	if c.is_empty():
		return errs
	var t := QuestJson.s(c.get("type"))
	if not (t in CONDITION_TYPES):
		errs.append("%s: unknown condition type '%s'" % [where, t])
		return errs
	match t:
		"all", "any":
			for sub: Variant in QuestJson.arr(c.get("of")):
				errs.append_array(validate_condition(sub, where))
		"not":
			errs.append_array(validate_condition(c.get("of"), where))
		"quest_status", "quest_available", "quest_ready", "quest_can_complete", "quest_items_lost", "objective":
			if QuestJson.s(c.get("quest")).is_empty():
				errs.append("%s: condition %s needs 'quest'" % [where, t])
			if t == "objective" and not (QuestJson.s(c.get("kind")) in QuestDef.OBJECTIVE_KINDS):
				errs.append("%s: objective condition with unknown kind '%s'" % [where, c.get("kind")])
		"item_count":
			if QuestJson.s(c.get("item")).is_empty():
				errs.append("%s: item_count needs 'item'" % where)
		"flag":
			if QuestJson.s(c.get("flag")).is_empty():
				errs.append("%s: flag condition needs 'flag'" % where)
	return errs


static func validate_action(a: Variant, where: String = "") -> PackedStringArray:
	var errs := PackedStringArray()
	if not (a is Dictionary):
		errs.append("%s: action is not an object" % where)
		return errs
	var ad: Dictionary = a
	var t := QuestJson.s(ad.get("type"))
	if not (t in ACTION_TYPES):
		errs.append("%s: unknown action type '%s'" % [where, t])
		return errs
	var need := {"accept_quest": "quest", "complete_quest": "quest", "answer_quiz": "quest", "forfeit_quest": "quest",
		"reissue_quest_items": "quest", "open_shop": "shop", "give_item": "item", "take_item": "item", "set_flag": "flag",
		"depart": "route"}
	var key := String(need[t])
	if QuestJson.s(ad.get(key)).is_empty():
		errs.append("%s: action %s needs '%s'" % [where, t, key])
	if t == "answer_quiz" and typeof(ad.get("choice")) not in [TYPE_INT, TYPE_FLOAT]:
		errs.append("%s: action answer_quiz needs 'choice'" % where)
	if t == "depart" and typeof(ad.get("route")) not in [TYPE_INT, TYPE_FLOAT]:
		errs.append("%s: action depart needs a route index" % where)
	return errs


## Problems with a line spec's "live" args (unknown live types), including those of its parts. Empty = valid.
static func validate_live(spec: Variant, where: String = "") -> PackedStringArray:
	var errs := PackedStringArray()
	if not (spec is Dictionary):
		return errs
	var sd: Dictionary = spec
	for k: Variant in QuestJson.dict(sd.get("live")):
		var t := QuestJson.s(QuestJson.dict(sd["live"][k]).get("type"))
		if not (t in LIVE_TYPES):
			errs.append("%s: live arg '%s' has unknown type '%s'" % [where, k, t])
	for p: Variant in QuestJson.arr(sd.get("parts")):
		errs.append_array(validate_live(p, where))
	return errs


## Type-safe equality (JSON numbers are floats; never compares unrelated types with ==).
static func _same(a: Variant, b: Variant) -> bool:
	var num := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in num and typeof(b) in num:
		return is_equal_approx(float(a), float(b))
	if typeof(a) != typeof(b):
		return false
	return a == b


func _in_range(v: int, c: Dictionary) -> bool:
	if c.get("min") != null and v < QuestJson.i(c.get("min")):
		return false
	if c.get("max") != null and v > QuestJson.i(c.get("max")):
		return false
	return true
