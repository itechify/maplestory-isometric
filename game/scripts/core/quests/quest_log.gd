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
##     "completions":  int           # times completed (repeatable quests can exceed 1)
##   }
## Item collection is never stored: it is checked against live inventory counts, as in classic MapleStory.
## A quest with no entry is "not_started". The contract (class name, to_dict, from_dict) is fixed.

const NOT_STARTED := "not_started"
const IN_PROGRESS := "in_progress"
const COMPLETED := "completed"
const STATUSES: PackedStringArray = [NOT_STARTED, IN_PROGRESS, COMPLETED]
## Bump with a migration in from_dict when the entry format changes meaning.
const FORMAT_VERSION := 1

## quest_id -> entry (see the class comment).
var entries: Dictionary = {}


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


# --- transitions (called by QuestEngine) ----------------------------------------------------------------------

## Marks the quest accepted at game-clock time `now`, with fresh progress.
func start(quest_id: String, now: float) -> void:
	var e := _entry(quest_id)
	e["status"] = IN_PROGRESS
	e["progress"] = _empty_progress()
	e["started_at"] = now


## Marks the quest completed at game-clock time `now`.
func complete(quest_id: String, now: float) -> void:
	var e := _entry(quest_id)
	e["status"] = COMPLETED
	e["completed_at"] = now
	e["completions"] = int(e.get("completions", 0)) + 1


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
	return {"format": FORMAT_VERSION, "quests": entries.duplicate(true)}


## Rebuilds a log from to_dict() output, including after a JSON round trip (floats become ints where meant).
## An empty or missing dictionary gives an empty log.
static func from_dict(d: Dictionary) -> QuestLog:
	var ql := QuestLog.new()
	var quests: Variant = d.get("quests", {})
	if not (quests is Dictionary):
		return ql
	for raw_id: Variant in quests:
		var raw: Variant = quests[raw_id]
		if not (raw is Dictionary):
			continue
		var src: Dictionary = raw
		var st := QuestJson.s(src.get("status"), NOT_STARTED)
		if not (st in STATUSES) or st == NOT_STARTED:
			continue
		var e := {
			"status": st,
			"progress": _clean_progress(src.get("progress", {})),
			"started_at": QuestJson.f(src.get("started_at"), -1.0),
			"completed_at": QuestJson.f(src.get("completed_at"), -1.0),
			"completions": QuestJson.i(src.get("completions"), 1 if st == COMPLETED else 0),
		}
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


static func _clean_progress(v: Variant) -> Dictionary:
	var p := _empty_progress()
	var src := QuestJson.dict(v)
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
