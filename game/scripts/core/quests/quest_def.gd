class_name QuestDef
extends RefCounted
## One quest, normalized from its canonical MeowDB record (data/canonical/quests/<id>.json) plus its optional
## MisoStory adaptation (data/misostory/quests/<id>.json). Built by QuestCatalog; read by QuestEngine and the NPC
## dialogue builder. Nothing here is quest-specific: every rule is a field of the record.
##
## Objectives are flattened into one list of dictionaries:
##   {key, kind, id, name, count, purpose, type, supported}
## where kind is one of OBJECTIVE_KINDS, id is the mob / item / npc / map id ("" for "other"), key is
## "<kind>:<id>" ("other:<type>" for other), and supported is false for an "other" type the engine cannot evaluate
## (such a quest can never complete, and QuestCatalog.validate() reports it).

## Objective kinds the canonical schema can express (docs/canonical/quests.md §3).
const OBJECTIVE_KINDS: PackedStringArray = ["monster_kills", "item_collection", "item_usage", "npc_talk", "map_visit", "other"]
## "other" objective types the engine knows how to evaluate.
const SUPPORTED_OTHER_TYPES: PackedStringArray = ["quiz"]
## Objectives resolved inside the turn-in conversation itself (the quiz is answered at the end NPC), so an NPC can
## show the quest as ready to turn in before they are satisfied.
const DIALOGUE_RESOLVED_KEYS: PackedStringArray = ["other:quiz"]
## npc_talk purposes: "turn_in" = talking to the end NPC (the completion act itself); "talk" = visit an NPC en route.
const TALK_PURPOSES: PackedStringArray = ["turn_in", "talk"]
## MeowDB's label for a random/selection reward group that applies to every class.
const ANY_CLASS_LABELS: PackedStringArray = ["", "Any Class"]

var id: String = ""
var name: String = ""
var start_npc_id: String = ""
var end_npc_id: String = ""
## 0 = MeowDB lists no requirement.
var min_level: int = 0
## 0 = no maximum (MeowDB has none).
var max_level: int = 0
## Level needed to turn in; 0 = none.
var completion_min_level: int = 0
## Display names or slugs ("Beginner"); empty = any job.
var job_restriction: PackedStringArray = []
var prereq_quests: PackedStringArray = []
## [{item_id, count}]
var prereq_items: Array = []
## [{item_id, count}]
var must_not_have_items: Array = []
var fame_min: int = 0
var acceptance_meso_cost: int = 0
## Prerequisite kinds present in the record that the engine cannot evaluate (skills, citizenship, unresolved).
var unsupported_prereqs: PackedStringArray = []
var repeatable: bool = false
var objectives: Array = []
## Keys of record.objectives that are not in OBJECTIVE_KINDS (validation error).
var unknown_objective_kinds: PackedStringArray = []
var reward_exp: int = 0
var reward_mesos: int = 0
var reward_fame: int = 0
## [{item_id, count}]
var reward_items: Array = []
## [{job_name, items: [{item_id, count, weight}]}]: one item per applicable group, weighted by MeowDB chance_pct.
var reward_random: Array = []
## [{job_name, items: [{item_id, count}]}]: the player picks one item of the applicable group.
var reward_selection: Array = []
## [{item_id, count, origin: "canonical" | "next_quest_grants" | "misostory", reason}]
var accept_items: Array = []
## [{item_id, count}]
var removed_on_completion: Array = []
var followups: PackedStringArray = []
## dialogue.on_completion.quiz, or {} when the quest has no quiz.
var quiz: Dictionary = {}
## The canonical dialogue block {on_accept, on_completion} (either may be {}).
var dialogue: Dictionary = {}
var journal_lines: PackedStringArray = []
## The raw canonical record and adaptation record ({} when none).
var record: Dictionary = {}
var adaptation: Dictionary = {}


## Builds a definition. `grants_from_previous` are the item lists other quests' next_quest_grants hand to this quest
## when it starts ([{item_id, count, ...}]); they are merged into accept_items without granting an item twice.
static func from_records(rec: Dictionary, adapt: Dictionary = {}, grants_from_previous: Array = []) -> QuestDef:
	var d := QuestDef.new()
	d.record = rec
	d.adaptation = adapt
	d.id = QuestJson.s(rec.get("id"))
	d.name = QuestJson.s(rec.get("name"))
	d.start_npc_id = QuestJson.s(QuestJson.dict(rec.get("start_npc")).get("npc_id"))
	d.end_npc_id = QuestJson.s(QuestJson.dict(rec.get("end_npc")).get("npc_id"), d.start_npc_id)
	d.min_level = QuestJson.i(rec.get("min_level"))
	d.max_level = QuestJson.i(rec.get("max_level"))
	d.completion_min_level = QuestJson.i(rec.get("completion_min_level"))
	d.job_restriction = QuestJson.strings(rec.get("job_restriction"))
	d.repeatable = QuestJson.b(rec.get("repeatable"))

	var pre := QuestJson.dict(rec.get("prerequisites"))
	for p: Variant in QuestJson.arr(pre.get("quests")):
		var pid := QuestJson.s(QuestJson.dict(p).get("quest_id")) if p is Dictionary else QuestJson.s(p)
		if not pid.is_empty():
			d.prereq_quests.append(pid)
	d.prereq_items = _item_list(pre.get("items"))
	d.must_not_have_items = _item_list(pre.get("must_not_have_items"))
	d.fame_min = QuestJson.i(pre.get("fame_min"))
	d.acceptance_meso_cost = QuestJson.i(pre.get("acceptance_meso_cost"))
	if not QuestJson.arr(pre.get("skills")).is_empty():
		d.unsupported_prereqs.append("skills")
	if pre.get("citizenship") != null:
		d.unsupported_prereqs.append("citizenship")
	if not QuestJson.arr(pre.get("unresolved")).is_empty():
		d.unsupported_prereqs.append("unresolved")
	if _item_list(pre.get("items")).size() != QuestJson.arr(pre.get("items")).size():
		d.unsupported_prereqs.append("items (unknown shape)")

	var obj := QuestJson.dict(rec.get("objectives"))
	for kind: Variant in obj:
		if not (String(kind) in OBJECTIVE_KINDS):
			d.unknown_objective_kinds.append(String(kind))
	for o: Variant in QuestJson.arr(obj.get("monster_kills")):
		d._add_objective("monster_kills", QuestJson.s(QuestJson.dict(o).get("mob_id")), o)
	for o: Variant in QuestJson.arr(obj.get("item_collection")):
		d._add_objective("item_collection", QuestJson.s(QuestJson.dict(o).get("item_id")), o)
	for o: Variant in QuestJson.arr(obj.get("item_usage")):
		d._add_objective("item_usage", QuestJson.s(QuestJson.dict(o).get("item_id")), o)
	for o: Variant in QuestJson.arr(obj.get("npc_talk")):
		d._add_objective("npc_talk", QuestJson.s(QuestJson.dict(o).get("npc_id")), o)
	for o: Variant in QuestJson.arr(obj.get("map_visit")):
		d._add_objective("map_visit", QuestJson.s(QuestJson.dict(o).get("map_id")), o)
	for o: Variant in QuestJson.arr(obj.get("other")):
		d._add_objective("other", "", o)

	var rw := QuestJson.dict(rec.get("rewards"))
	d.reward_exp = QuestJson.i(rw.get("exp"))
	d.reward_mesos = QuestJson.i(rw.get("mesos"))
	d.reward_fame = QuestJson.i(rw.get("fame"))
	d.reward_items = _item_list(rw.get("items"))
	for g: Variant in QuestJson.arr(rw.get("random")):
		var gd := QuestJson.dict(g)
		var items: Array = []
		for it: Variant in QuestJson.arr(gd.get("items")):
			var itd := QuestJson.dict(it)
			var item_id := QuestJson.s(itd.get("item_id"))
			if item_id.is_empty():
				continue
			# MeowDB publishes only rounded chance_pct per item; it is used as the relative weight.
			items.append({"item_id": item_id, "count": maxi(1, QuestJson.i(itd.get("count"), 1)),
				"weight": QuestJson.f(itd.get("chance_pct"), 1.0)})
		d.reward_random.append({"job_name": QuestJson.s(gd.get("job_name")), "items": items})
	for g: Variant in QuestJson.arr(rw.get("selection")):
		var gd := QuestJson.dict(g)
		d.reward_selection.append({"job_name": QuestJson.s(gd.get("job_name")), "items": _item_list(gd.get("items"))})

	for a: Dictionary in _item_list(rec.get("items_given_on_accept")):
		a["origin"] = "canonical"
		a["reason"] = ""
		d.accept_items.append(a)
	for a: Dictionary in _item_list(grants_from_previous):
		if d._accept_item_index(String(a["item_id"])) < 0:
			a["origin"] = "next_quest_grants"
			a["reason"] = "MeowDB nextQuestGrants of the previous quest"
			d.accept_items.append(a)
	for a: Variant in QuestJson.arr(adapt.get("accept_items")):
		var ad := QuestJson.dict(a)
		var item_id := QuestJson.s(ad.get("item_id"))
		if item_id.is_empty() or d._accept_item_index(item_id) >= 0:
			continue
		d.accept_items.append({"item_id": item_id, "count": maxi(1, QuestJson.i(ad.get("count"), 1)),
			"origin": "misostory", "reason": QuestJson.s(ad.get("reason"))})

	d.removed_on_completion = _item_list(QuestJson.dict(rec.get("items_removed_on_completion")).get("items"))
	for f: Variant in QuestJson.arr(rec.get("followup_quests")):
		var fid := QuestJson.s(QuestJson.dict(f).get("quest_id")) if f is Dictionary else QuestJson.s(f)
		if not fid.is_empty():
			d.followups.append(fid)

	var dlg := QuestJson.dict(rec.get("dialogue"))
	d.dialogue = {"on_accept": QuestJson.dict(dlg.get("on_accept")), "on_completion": QuestJson.dict(dlg.get("on_completion"))}
	d.quiz = QuestJson.dict(d.dialogue["on_completion"].get("quiz"))
	d.journal_lines = QuestJson.strings(QuestJson.dict(rec.get("journal")).get("lines"))
	return d


## Objectives of one kind.
func objectives_of(kind: String) -> Array:
	var out: Array = []
	for o: Dictionary in objectives:
		if o["kind"] == kind:
			out.append(o)
	return out


## The objective with this key ("monster_kills:2"), or {}.
func objective(key: String) -> Dictionary:
	for o: Dictionary in objectives:
		if o["key"] == key:
			return o
	return {}


## Dialogue section "on_accept" / "on_completion" ({} when MeowDB has none).
func section(section_name: String) -> Dictionary:
	return QuestJson.dict(dialogue.get(section_name))


## Main lines of a section (before any branch).
func section_lines(section_name: String) -> Array:
	return QuestJson.arr(section(section_name).get("lines"))


## Lines of the branch with this `state` ("accepted", "declined", "ready", "missing_items", "missing_kills",
## "wrong_npc", "lost_items") in a section, or [] when MeowDB has no such branch.
func branch_lines(section_name: String, state: String) -> Array:
	for br: Variant in QuestJson.arr(section(section_name).get("branches")):
		var b := QuestJson.dict(br)
		if QuestJson.s(b.get("state")) == state:
			return QuestJson.arr(b.get("lines"))
	return []


func has_branch(section_name: String, state: String) -> bool:
	return not branch_lines(section_name, state).is_empty()


## True if the quest's reward group applies to a class (job slug and display name).
static func group_applies(job_name: String, job_slug: String, job_display: String) -> bool:
	if job_name in ANY_CLASS_LABELS:
		return true
	return job_name == job_slug or job_name == job_display or job_name.to_lower() == job_slug.to_lower()


# --- internals ------------------------------------------------------------------------------------------------

func _add_objective(kind: String, target_id: String, raw: Variant) -> void:
	var o := QuestJson.dict(raw)
	var entry := {
		"kind": kind,
		"id": target_id,
		"name": QuestJson.s(o.get("name")),
		"count": 1,
		"purpose": "",
		"type": "",
		"supported": true,
		"key": "",
	}
	match kind:
		"monster_kills", "item_collection", "item_usage":
			entry["count"] = maxi(1, QuestJson.i(o.get("count"), 1))
		"npc_talk":
			entry["purpose"] = QuestJson.s(o.get("purpose"), "talk")
		"other":
			entry["type"] = QuestJson.s(o.get("type"))
			entry["name"] = QuestJson.s(o.get("description"))
			entry["supported"] = entry["type"] in SUPPORTED_OTHER_TYPES
	entry["key"] = "other:%s" % entry["type"] if kind == "other" else "%s:%s" % [kind, target_id]
	objectives.append(entry)


func _accept_item_index(item_id: String) -> int:
	for idx in accept_items.size():
		if String(accept_items[idx]["item_id"]) == item_id:
			return idx
	return -1


## [{item_id, count}] from a canonical item array (entries without an item_id are dropped).
static func _item_list(v: Variant) -> Array:
	var out: Array = []
	for e: Variant in QuestJson.arr(v):
		var ed := QuestJson.dict(e)
		var item_id := QuestJson.s(ed.get("item_id"))
		if item_id.is_empty():
			continue
		out.append({"item_id": item_id, "count": maxi(1, QuestJson.i(ed.get("count"), 1))})
	return out
