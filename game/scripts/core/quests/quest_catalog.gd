class_name QuestCatalog
extends RefCounted
## Every quest of a ContentDB as a QuestDef, plus lookups by NPC and the data validation for the quest domain.
##
## Sources: canonical `quests` (MeowDB) and adaptation `misostory/quests/<id>.json`. Adding a quest means adding
## those files; nothing in code names a quest.

## A misostory/quests file named "_<name>" is a shared table, not a quest adaptation (AdaptationChecks.SHARED_TABLE_PREFIX).
const SHARED_TABLE_PREFIX := "_"

var db: ContentDB
var _defs: Dictionary = {}
var _built := false


func _init(p_db: ContentDB = null) -> void:
	db = p_db


## The definition of a quest, or null when the id is unknown.
func get_def(quest_id: String) -> QuestDef:
	_build()
	return _defs.get(quest_id, null)


func has(quest_id: String) -> bool:
	_build()
	return _defs.has(quest_id)


## Every quest id, sorted.
func ids() -> PackedStringArray:
	_build()
	var out := PackedStringArray(_defs.keys())
	out.sort()
	return out


## Quests whose start NPC is `npc_id`, sorted.
func started_by(npc_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for qid in ids():
		if get_def(qid).start_npc_id == npc_id:
			out.append(qid)
	return out


## Quests whose turn-in NPC is `npc_id`, sorted.
func completed_by(npc_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for qid in ids():
		if get_def(qid).end_npc_id == npc_id:
			out.append(qid)
	return out


## One quest's definition built straight from `content` (its next_quest_grants included), without building the whole
## catalog: for callers that hold no catalog and need a few quests (QuestItemGuard). Null for an unknown quest.
static func single(content: ContentDB, quest_id: String) -> QuestDef:
	if content == null or not content.has("quests", quest_id):
		return null
	var grants: Array = []
	var records: Dictionary = content.domain("quests")
	for pid: String in records:
		for g: Variant in QuestJson.arr(QuestJson.dict(records[pid]).get("next_quest_grants")):
			var gd := QuestJson.dict(g)
			if QuestJson.s(gd.get("quest_id")) == quest_id:
				grants.append_array(QuestJson.arr(gd.get("items")))
	return QuestDef.from_records(QuestJson.dict(records[quest_id]), content.miso_entity("quests", quest_id), grants)


## Drops the cache (after the ContentDB was changed, e.g. in tests that add a synthetic quest).
func invalidate() -> void:
	_defs.clear()
	_built = false


## Data problems that would make a quest unplayable or silently wrong. Empty = valid.
func validate() -> PackedStringArray:
	_build()
	var errs := PackedStringArray()
	for qid in ids():
		var d: QuestDef = _defs[qid]
		var at := "quest %s" % qid
		if d.name.is_empty():
			errs.append("%s: no name" % at)
		_check_ref(errs, at, "npcs", d.start_npc_id, "start npc")
		_check_ref(errs, at, "npcs", d.end_npc_id, "end npc")
		for k in d.unknown_objective_kinds:
			errs.append("%s: unknown objective kind '%s' (supported: %s)" % [at, k, ", ".join(QuestDef.OBJECTIVE_KINDS)])
		for p in d.unsupported_prereqs:
			errs.append("%s: prerequisite kind '%s' is not supported by QuestEngine" % [at, p])
		for p in d.prereq_quests:
			if not _defs.has(p):
				errs.append("%s: prerequisite quest %s does not exist" % [at, p])
		for f in d.followups:
			if not _defs.has(f):
				errs.append("%s: follow-up quest %s does not exist" % [at, f])
		for o: Dictionary in d.objectives:
			var okey := "%s objective %s" % [at, o["key"]]
			match String(o["kind"]):
				"monster_kills":
					_check_ref(errs, okey, "monsters", o["id"], "monster")
				"item_collection", "item_usage":
					_check_ref(errs, okey, "items", o["id"], "item")
				"npc_talk":
					_check_ref(errs, okey, "npcs", o["id"], "npc")
					if not (String(o["purpose"]) in QuestDef.TALK_PURPOSES):
						errs.append("%s: unknown npc_talk purpose '%s'" % [okey, o["purpose"]])
				"map_visit":
					_check_ref(errs, okey, "maps", o["id"], "map")
				"other":
					if not bool(o["supported"]):
						errs.append("%s: unsupported 'other' objective type '%s' (supported: %s); the quest can never complete" % [okey, o["type"], ", ".join(QuestDef.SUPPORTED_OTHER_TYPES)])
					elif o["type"] == "quiz":
						_check_quiz(errs, okey, d)
		for it: Dictionary in d.reward_items:
			_check_ref(errs, at + " reward", "items", it["item_id"], "item")
		for g: Dictionary in d.reward_random + d.reward_selection:
			if (g["items"] as Array).is_empty():
				errs.append("%s: empty random/selection reward group" % at)
			for it: Dictionary in g["items"]:
				_check_ref(errs, at + " reward", "items", it["item_id"], "item")
				if it.has("weight") and float(it["weight"]) <= 0.0:
					errs.append("%s: random reward %s has no positive chance" % [at, it["item_id"]])
		for it: Dictionary in d.accept_items:
			_check_ref(errs, at + " accept item", "items", it["item_id"], "item")
			if it["origin"] == "misostory" and String(it["reason"]).is_empty():
				errs.append("%s: adaptation accept item %s has no reason" % [at, it["item_id"]])
		for it: Dictionary in d.removed_on_completion:
			_check_ref(errs, at + " hand-in", "items", it["item_id"], "item")
	# Adaptation files must belong to a canonical quest and say why they exist.
	for aid: String in db.miso.get("quests", {}):
		var a: Dictionary = db.miso["quests"][aid]
		# "_" files are shared tables (e.g. _quest_items.json), not quest adaptations.
		if not aid.begins_with(SHARED_TABLE_PREFIX) and not _defs.has(aid):
			errs.append("misostory/quests/%s.json: no canonical quest %s" % [aid, aid])
		if QuestJson.s(a.get("reason")).is_empty():
			errs.append("misostory/quests/%s.json: missing top-level reason" % aid)
		if not a.has("verified"):
			errs.append("misostory/quests/%s.json: missing top-level verified flag" % aid)
	return errs


# --- internals ------------------------------------------------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	_defs.clear()
	if db == null:
		return
	var records: Dictionary = db.domain("quests")
	# next_quest_grants of quest P list items that follow-up quest X hands over when X starts.
	var grants: Dictionary = {}
	for pid: String in records:
		for g: Variant in QuestJson.arr(QuestJson.dict(records[pid]).get("next_quest_grants")):
			var gd := QuestJson.dict(g)
			var target := QuestJson.s(gd.get("quest_id"))
			if target.is_empty():
				continue
			if not grants.has(target):
				grants[target] = []
			(grants[target] as Array).append_array(QuestJson.arr(gd.get("items")))
	for qid: String in records:
		var rec := QuestJson.dict(records[qid])
		_defs[qid] = QuestDef.from_records(rec, db.miso_entity("quests", qid), QuestJson.arr(grants.get(qid)))


func _check_ref(errs: PackedStringArray, at: String, domain_name: String, ref_id: Variant, what: String) -> void:
	var rid := QuestJson.s(ref_id)
	if rid.is_empty():
		errs.append("%s: empty %s id" % [at, what])
	elif not db.has(domain_name, rid):
		errs.append("%s: %s %s not in canonical %s" % [at, what, rid, domain_name])


func _check_quiz(errs: PackedStringArray, at: String, d: QuestDef) -> void:
	if d.quiz.is_empty():
		errs.append("%s: quiz objective but dialogue.on_completion.quiz is missing" % at)
		return
	var choices := QuestJson.arr(d.quiz.get("choices"))
	var correct := QuestJson.i(d.quiz.get("correct_choice_index"), -1)
	if choices.size() < 2:
		errs.append("%s: quiz has fewer than 2 choices" % at)
	if correct < 0 or correct >= choices.size():
		errs.append("%s: quiz correct_choice_index %d out of range" % [at, correct])
	if QuestJson.dict(d.quiz.get("question")).is_empty():
		errs.append("%s: quiz has no question" % at)
