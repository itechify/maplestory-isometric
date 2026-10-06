class_name PlaytestLedger
extends RefCounted
## The strict mode's bookkeeping (docs/runtime/PLAYTEST_HARNESS.md "Strict mode"): from a baseline on, it listens to
## the game's own event bus and, when asked, reconciles the live character against what the bus announced:
##
##   EXP      total EXP (every level below plus the bar) - baseline == the sum of Events.exp_gained
##            (monster kills, quest rewards, the death penalty's negative award)
##   mesos    mesos - baseline == the sum of Events.mesos_changed deltas (pickups, shops, quest rewards)
##   items    per item, inventory + equipment - baseline == item_gained - item_lost (pickups, shops, quest hand-ins and
##            rewards, use; equipping moves an item between the two and changes neither)
##   quests   every quest whose status changed has a quest_started / quest_completed / quest_forfeited for its new
##            status
##
## A change that no event explains (a scenario writing c.mesos, adding to the inventory or completing a quest behind
## the game's back) is a mismatch, and a mismatch fails a strict run. Console commands are counted separately
## (DebugTools.commands_run); a scenario calling a game service directly is caught by the api step kind and by the
## static test of strict scenarios (test_playtest_strict.gd).

var _bus: Node = null
var _db: ContentDB = null
var _c: CharacterState = null
var _exp0: int = 0
var _mesos0: int = 0
var _items0: Dictionary = {}
var _quests0: Dictionary = {}
var exp_sum: int = 0
var mesos_sum: int = 0
## item id -> gained - lost
var item_delta: Dictionary = {}
## quest id -> the status its last event announced
var quest_last: Dictionary = {}
## Events heard since the baseline (for the report).
var heard: int = 0
var armed: bool = false


## Starts (or restarts) the ledger on `character` now: the baseline is the character as it is, and every later
## event counts.
func baseline(bus: Node, character: CharacterState, db: ContentDB) -> void:
	disarm()
	_bus = bus
	_db = db
	_c = character
	if _bus == null or _c == null or _db == null:
		return
	_exp0 = total_exp(_c, _db)
	_mesos0 = _c.mesos
	_items0 = holdings(_c)
	_quests0 = statuses(_c)
	exp_sum = 0
	mesos_sum = 0
	item_delta = {}
	quest_last = {}
	heard = 0
	_bus.connect(&"exp_gained", _on_exp)
	_bus.connect(&"mesos_changed", _on_mesos)
	_bus.connect(&"item_gained", _on_gained)
	_bus.connect(&"item_lost", _on_lost)
	_bus.connect(&"quest_started", _on_started)
	_bus.connect(&"quest_completed", _on_completed)
	_bus.connect(&"quest_forfeited", _on_forfeited)
	armed = true


func disarm() -> void:
	if _bus != null and is_instance_valid(_bus):
		for pair: Array in [[&"exp_gained", _on_exp], [&"mesos_changed", _on_mesos], [&"item_gained", _on_gained],
				[&"item_lost", _on_lost], [&"quest_started", _on_started], [&"quest_completed", _on_completed],
				[&"quest_forfeited", _on_forfeited]]:
			if _bus.is_connected(pair[0], pair[1]):
				_bus.disconnect(pair[0], pair[1])
	armed = false


## The mismatches between the live character and the events heard since the baseline ([] when every change is
## explained). `character` is the live one (a Continue or a new game replaces the object: rebaseline then).
func reconcile(character: CharacterState = null) -> PackedStringArray:
	var out := PackedStringArray()
	var c := character if character != null else _c
	if not armed or c == null or _db == null:
		return out
	var dexp := total_exp(c, _db) - _exp0
	if dexp != exp_sum:
		out.append("EXP changed by %+d, the bus announced %+d" % [dexp, exp_sum])
	var dmesos := c.mesos - _mesos0
	if dmesos != mesos_sum:
		out.append("mesos changed by %+d, the bus announced %+d" % [dmesos, mesos_sum])
	var now := holdings(c)
	var ids := {}
	for id: String in now:
		ids[id] = true
	for id: String in _items0:
		ids[id] = true
	for id: String in item_delta:
		ids[id] = true
	for id: String in ids:
		var d := int(now.get(id, 0)) - int(_items0.get(id, 0))
		if d != int(item_delta.get(id, 0)):
			out.append("item %s changed by %+d, the bus announced %+d" % [id, d, int(item_delta.get(id, 0))])
	var st := statuses(c)
	var qids := {}
	for q: String in st:
		qids[q] = true
	for q: String in _quests0:
		qids[q] = true
	for q: String in qids:
		var a := String(_quests0.get(q, QuestLog.NOT_STARTED))
		var b := String(st.get(q, QuestLog.NOT_STARTED))
		if a != b and String(quest_last.get(q, "")) != b:
			out.append("quest %s went %s -> %s with no event for it (last event: %s)" % [q, a, b, quest_last.get(q, "none")])
	return out


## What the ledger saw, for the report: {"heard", "exp", "mesos", "items"}.
func summary() -> Dictionary:
	return {"heard": heard, "exp": exp_sum, "mesos": mesos_sum, "items": item_delta.duplicate()}


## EXP from level 1 at 0 EXP: the EXP to next level of every level below plus the bar.
static func total_exp(c: CharacterState, db: ContentDB) -> int:
	var t := c.exp
	for l in range(1, c.level):
		t += Progression.exp_to_next(l, db)
	return t


## item id -> count over the inventory and the equipped pieces.
static func holdings(c: CharacterState) -> Dictionary:
	var out := {}
	for tab in Inventory.TABS:
		for i in c.inventory.capacity(tab):
			var s := c.inventory.get_slot(tab, i)
			if not s.is_empty():
				var id := String(s.get("item_id", ""))
				out[id] = int(out.get(id, 0)) + int(s.get("qty", 1))
	var eq := c.equipment.equipped()
	for slot: Variant in eq:
		var id := String(eq[slot])
		if id != "":
			out[id] = int(out.get(id, 0)) + 1
	return out


## quest id -> status for every quest the log knows.
static func statuses(c: CharacterState) -> Dictionary:
	var out := {}
	for q in c.quests.active_ids():
		out[String(q)] = QuestLog.IN_PROGRESS
	for q in c.quests.completed_ids():
		out[String(q)] = QuestLog.COMPLETED
	return out


func _on_exp(amount: int, _source: String) -> void:
	heard += 1
	exp_sum += amount


func _on_mesos(_mesos: int, delta: int) -> void:
	heard += 1
	mesos_sum += delta


func _on_gained(item_id: String, qty: int) -> void:
	heard += 1
	item_delta[item_id] = int(item_delta.get(item_id, 0)) + qty


func _on_lost(item_id: String, qty: int) -> void:
	heard += 1
	item_delta[item_id] = int(item_delta.get(item_id, 0)) - qty


func _on_started(qid: String) -> void:
	heard += 1
	quest_last[qid] = QuestLog.IN_PROGRESS


func _on_completed(qid: String) -> void:
	heard += 1
	quest_last[qid] = QuestLog.COMPLETED


func _on_forfeited(qid: String) -> void:
	heard += 1
	quest_last[qid] = QuestLog.NOT_STARTED
