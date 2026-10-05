class_name QuestLog
extends RefCounted
## The character's quest state, keyed by canonical MeowDB quest id ("1002"). Composed by CharacterState and saved
## with it. Pure data: the rules that move quests between states live in QuestEngine.
##
## One entry per quest the character ever touched:
##   {
##     "status": "not_started" | "in_progress" | "completed",
##     "progress": {
##       "kills":   {mob_id: n},      # monster_kills objectives (counted only while in progress)
##       "used":    {item_id: n},     # item_usage objectives
##       "talked":  [npc_id, ...],    # npc_talk objectives
##       "visited": [map_id, ...],    # map_visit objectives
##       "other":   {key: value}      # "other" objectives (e.g. "quiz": true once answered correctly)
##     },
##     "started_at":   float,        # game clock (Game.clock seconds) when accepted, -1 if never
##     "completed_at": float,        # game clock of the last completion, -1 if never
##     "completions":  int,          # times completed (repeatable quests can exceed 1)
##     "rewards_received": {         # completed entries only: what the last completion actually gave (contract C3)
##       "exp": int, "mesos": int,                       # EXP and mesos actually added
##       "items": [{"item_id", "qty"}],                  # every item granted (fixed, random and selected rewards)
##       "random_picks": [{"group", "item_id", "qty"}]   # the weighted draws; group = index into rewards.random
##     }                                                 # or {"recorded": false}: completed before format 2
##   }
## Item collection is never stored: it is checked against live inventory counts, as in classic MapleStory.
## A quest with no entry is "not_started". The contract (class name, to_dict, from_dict) is fixed.
##
## Format 2 (Iteration Three) adds rewards_received. from_dict reads format 1 (a completed entry gains
## {"recorded": false}) and keeps keys it does not know at every level (the log, an entry, its progress), and keeps
## the entries it cannot read (an unknown status, a "not_started" entry, a non-dictionary) as they are, so a save
## written by a newer build loses nothing when this one writes it back.

const NOT_STARTED := "not_started"
const IN_PROGRESS := "in_progress"
const COMPLETED := "completed"
const STATUSES: PackedStringArray = [NOT_STARTED, IN_PROGRESS, COMPLETED]
## Bump with a migration in from_dict when the entry format changes meaning.
const FORMAT_VERSION := 2
## The rewards record of a completion this build did not see (format 1 saves, or complete() without rewards).
const UNRECORDED_REWARDS := {"recorded": false}

## quest_id -> entry (see the class comment).
var entries: Dictionary = {}
## Top-level keys of a loaded log this build does not know, written back unchanged by to_dict.
var extra: Dictionary = {}
## quest_id -> a loaded entry this build cannot read (an unknown status such as a newer build's, a "not_started"
## entry, a non-dictionary). Invisible to the queries; written back unchanged by to_dict unless the quest gets an
## entry of its own (an entry in `entries` wins).
var unread_entries: Dictionary = {}


# --- queries --------------------------------------------------------------------------------------------------

## "not_started", "in_progress" or "completed".
func status(quest_id: String) -> String:
	return String(entries.get(quest_id, {}).get("status", NOT_STARTED))


func is_in_progress(quest_id: String) -> bool:
	return status(quest_id) == IN_PROGRESS


## True when the quest's status is "completed" (a repeatable quest that was re-accepted is "in_progress" again).
func is_completed(quest_id: String) -> bool:
	return status(quest_id) == COMPLETED


## How many times the quest was completed.
func completions(quest_id: String) -> int:
	return int(entries.get(quest_id, {}).get("completions", 0))


## The live progress dictionary of a quest (empty progress when it has no entry). Mutate only through QuestEngine.
func progress(quest_id: String) -> Dictionary:
	var e: Dictionary = entries.get(quest_id, {})
	if e.is_empty():
		return _empty_progress()
	return e["progress"]


func started_at(quest_id: String) -> float:
	return float(entries.get(quest_id, {}).get("started_at", -1.0))


func completed_at(quest_id: String) -> float:
	return float(entries.get(quest_id, {}).get("completed_at", -1.0))


## Quest ids with the given status, sorted.
func ids_with_status(wanted: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in entries:
		if status(id) == wanted:
			out.append(id)
	out.sort()
	return out


func active_ids() -> PackedStringArray:
	return ids_with_status(IN_PROGRESS)


func completed_ids() -> PackedStringArray:
	return ids_with_status(COMPLETED)


## Kill count recorded for a mob in a quest.
func kills(quest_id: String, mob_id: String) -> int:
	return int(progress(quest_id)["kills"].get(mob_id, 0))


## Use count recorded for an item in a quest.
func uses(quest_id: String, item_id: String) -> int:
	return int(progress(quest_id)["used"].get(item_id, 0))


func has_talked(quest_id: String, npc_id: String) -> bool:
	return npc_id in progress(quest_id)["talked"]


func has_visited(quest_id: String, map_id: String) -> bool:
	return map_id in progress(quest_id)["visited"]


func other_value(quest_id: String, key: String) -> Variant:
	return progress(quest_id)["other"].get(key, null)


## What the last completion gave ({exp, mesos, items, random_picks}), {"recorded": false} for a completion this
## build did not see, or {} when the quest was never completed.
func rewards_received(quest_id: String) -> Dictionary:
	return QuestJson.dict(entries.get(quest_id, {}).get("rewards_received")).duplicate(true)


## True when the last completion's rewards were recorded (format 2).
func rewards_recorded(quest_id: String) -> bool:
	var r := rewards_received(quest_id)
	return r.has("exp") and QuestJson.b(r.get("recorded"), true)


# --- transitions (called by QuestEngine) ----------------------------------------------------------------------

## Marks the quest accepted at game-clock time `now`, with fresh progress.
func start(quest_id: String, now: float) -> void:
	var e := _entry(quest_id)
	e["status"] = IN_PROGRESS
	e["progress"] = _empty_progress()
	e["started_at"] = now


## Marks the quest completed at game-clock time `now`. `rewards` is what the completion gave
## ({exp, mesos, items: [{item_id, qty}], random_picks: [{group, item_id, qty}]}, QuestEngine.complete passes it);
## without it the completion's rewards are recorded as {"recorded": false}.
func complete(quest_id: String, now: float, rewards: Dictionary = {}) -> void:
	var e := _entry(quest_id)
	e["status"] = COMPLETED
	e["completed_at"] = now
	e["completions"] = int(e.get("completions", 0)) + 1
	e["rewards_received"] = _clean_rewards(rewards) if rewards.has("exp") else UNRECORDED_REWARDS.duplicate()


## Drops an in-progress quest: back to "completed" if it was completed before (repeatable), else no entry at all.
func forfeit(quest_id: String) -> void:
	if not entries.has(quest_id):
		return
	var e: Dictionary = entries[quest_id]
	if int(e.get("completions", 0)) > 0:
		e["status"] = COMPLETED
		e["progress"] = _empty_progress()
	else:
		entries.erase(quest_id)


## Adds `n` kills of `mob_id`, never above `cap` (cap <= 0 = no cap). Returns the new count.
func add_kills(quest_id: String, mob_id: String, n: int = 1, cap: int = 0) -> int:
	var kills_d: Dictionary = _entry(quest_id)["progress"]["kills"]
	var v := int(kills_d.get(mob_id, 0)) + n
	if cap > 0:
		v = mini(v, cap)
	kills_d[mob_id] = v
	return v


## Adds `n` uses of `item_id`, never above `cap` (cap <= 0 = no cap). Returns the new count.
func add_uses(quest_id: String, item_id: String, n: int = 1, cap: int = 0) -> int:
	var used_d: Dictionary = _entry(quest_id)["progress"]["used"]
	var v := int(used_d.get(item_id, 0)) + n
	if cap > 0:
		v = mini(v, cap)
	used_d[item_id] = v
	return v


## Records a talk with `npc_id`. Returns false if it was already recorded.
func mark_talked(quest_id: String, npc_id: String) -> bool:
	var talked: Array = _entry(quest_id)["progress"]["talked"]
	if npc_id in talked:
		return false
	talked.append(npc_id)
	return true


## Records a visit to `map_id`. Returns false if it was already recorded.
func mark_visited(quest_id: String, map_id: String) -> bool:
	var visited: Array = _entry(quest_id)["progress"]["visited"]
	if map_id in visited:
		return false
	visited.append(map_id)
	return true


## Sets an "other" objective value (e.g. "quiz" -> true).
func set_other(quest_id: String, key: String, value: Variant) -> void:
	_entry(quest_id)["progress"]["other"][key] = value


# --- persistence ----------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out := extra.duplicate(true)
	out["format"] = FORMAT_VERSION
	var quests := unread_entries.duplicate(true)
	for id: String in entries:
		quests[id] = (entries[id] as Dictionary).duplicate(true)
	out["quests"] = quests
	return out


## Rebuilds a log from to_dict() output, including after a JSON round trip (floats become ints where meant).
## An empty or missing dictionary gives an empty log. Reads format 1 (completed entries gain
## rewards_received {"recorded": false} unless the save migration already wrote one) and keeps unknown keys and the
## entries it cannot read (unread_entries).
static func from_dict(d: Dictionary) -> QuestLog:
	var ql := QuestLog.new()
	for k: Variant in d:
		if not (str(k) in ["format", "quests"]):
			ql.extra[str(k)] = d[k]
	var quests: Variant = d.get("quests", {})
	if not (quests is Dictionary):
		return ql
	for raw_id: Variant in quests:
		var raw: Variant = quests[raw_id]
		if not (raw is Dictionary):
			ql.unread_entries[str(raw_id)] = _copy(raw)
			continue
		var src: Dictionary = raw
		var st := QuestJson.s(src.get("status"), NOT_STARTED)
		if not (st in STATUSES) or st == NOT_STARTED:
			# Not a state this build plays (a newer build's status, or nothing started): kept as it is for to_dict.
			ql.unread_entries[str(raw_id)] = src.duplicate(true)
			continue
		# Unknown keys first, so the known ones below always win with their cleaned values.
		var e: Dictionary = src.duplicate(true)
		e["status"] = st
		e["progress"] = _clean_progress(src.get("progress", {}))
		e["started_at"] = QuestJson.f(src.get("started_at"), -1.0)
		e["completed_at"] = QuestJson.f(src.get("completed_at"), -1.0)
		e["completions"] = QuestJson.i(src.get("completions"), 1 if st == COMPLETED else 0)
		if src.get("rewards_received") is Dictionary:
			e["rewards_received"] = _clean_rewards(src["rewards_received"])
		elif st == COMPLETED:
			e["rewards_received"] = UNRECORDED_REWARDS.duplicate()
		ql.entries[str(raw_id)] = e
	return ql


# --- internals ------------------------------------------------------------------------------------------------

func _entry(quest_id: String) -> Dictionary:
	if not entries.has(quest_id):
		entries[quest_id] = {
			"status": NOT_STARTED,
			"progress": _empty_progress(),
			"started_at": -1.0,
			"completed_at": -1.0,
			"completions": 0,
		}
	return entries[quest_id]


static func _empty_progress() -> Dictionary:
	return {"kills": {}, "used": {}, "talked": [], "visited": [], "other": {}}


## A deep copy of a JSON value (containers duplicated, scalars as they are).
static func _copy(v: Variant) -> Variant:
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	if v is Array:
		return (v as Array).duplicate(true)
	return v


## A rewards_received record with JSON floats turned back into ints; unknown keys (and "recorded") are kept.
static func _clean_rewards(v: Variant) -> Dictionary:
	var src := QuestJson.dict(v)
	var r: Dictionary = src.duplicate(true)
	if not src.has("exp") and not src.has("items"):
		# Nothing recorded (a format 1 completion migrated by the save, or a record of unknown shape).
		return r
	r["exp"] = QuestJson.i(src.get("exp"))
	r["mesos"] = QuestJson.i(src.get("mesos"))
	var items: Array = []
	for it: Variant in QuestJson.arr(src.get("items")):
		var itd := QuestJson.dict(it)
		var row: Dictionary = itd.duplicate(true)
		row["item_id"] = QuestJson.s(itd.get("item_id"))
		row["qty"] = QuestJson.i(itd.get("qty"))
		items.append(row)
	r["items"] = items
	var picks: Array = []
	for p: Variant in QuestJson.arr(src.get("random_picks")):
		var pd := QuestJson.dict(p)
		var row: Dictionary = pd.duplicate(true)
		row["group"] = QuestJson.i(pd.get("group"))
		row["item_id"] = QuestJson.s(pd.get("item_id"))
		row["qty"] = QuestJson.i(pd.get("qty"))
		picks.append(row)
	r["random_picks"] = picks
	return r


## Progress with JSON floats turned back into ints; unknown progress keys are kept as they are.
static func _clean_progress(v: Variant) -> Dictionary:
	var src := QuestJson.dict(v)
	var p: Dictionary = src.duplicate(true)
	p.merge(_empty_progress(), true)
	var kills_src := QuestJson.dict(src.get("kills"))
	for k: Variant in kills_src:
		p["kills"][str(k)] = QuestJson.i(kills_src[k])
	var used_src := QuestJson.dict(src.get("used"))
	for k: Variant in used_src:
		p["used"][str(k)] = QuestJson.i(used_src[k])
	for n: Variant in QuestJson.arr(src.get("talked")):
		p["talked"].append(str(n))
	for m: Variant in QuestJson.arr(src.get("visited")):
		p["visited"].append(str(m))
	var other_src := QuestJson.dict(src.get("other"))
	for k: Variant in other_src:
		p["other"][str(k)] = other_src[k]
	return p
