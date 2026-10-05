class_name NpcCatalog
extends RefCounted
## Every NPC of a ContentDB as an NpcDef, keyed by MeowDB NPC id, plus lookups and validation.
##
##   var npcs := NpcCatalog.new(Data.db)
##   npcs.get_def("3").name          # "Roger"
##   npcs.on_map("000000060")        # ["12", "13", "14", "15"]

## A misostory/npcs file named "_<name>" is a shared table, not an NPC adaptation (AdaptationChecks.SHARED_TABLE_PREFIX).
const SHARED_TABLE_PREFIX := "_"

var db: ContentDB
var _defs: Dictionary = {}
var _built := false


func _init(p_db: ContentDB = null) -> void:
	db = p_db


## The NPC definition, or null when the id is unknown.
func get_def(npc_id: String) -> NpcDef:
	_build()
	return _defs.get(npc_id, null)


func has(npc_id: String) -> bool:
	_build()
	return _defs.has(npc_id)


## Every NPC id, sorted numerically.
func ids() -> PackedStringArray:
	_build()
	var keys: Array = _defs.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return a.to_int() < b.to_int() if a.is_valid_int() and b.is_valid_int() else a < b)
	return PackedStringArray(keys)


## NPC ids standing on a map, sorted numerically.
func on_map(map_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for nid in ids():
		if get_def(nid).map_id == map_id:
			out.append(nid)
	return out


## Data problems: unknown maps/quests/shops, adaptation files without a reason or for unknown NPCs, NPCs listed on a
## map page but missing (and the reverse). Empty = valid.
func validate() -> PackedStringArray:
	_build()
	var errs := PackedStringArray()
	for nid in ids():
		var n: NpcDef = _defs[nid]
		var at := "npc %s (%s)" % [nid, n.name]
		if n.name.is_empty():
			errs.append("%s: no name" % at)
		if n.map_id.is_empty() or not db.has("maps", n.map_id):
			errs.append("%s: map %s not in canonical maps" % [at, n.map_id])
		for q in n.quests_started + n.quests_completed:
			if not db.has("quests", q):
				errs.append("%s: quest %s not in canonical quests" % [at, q])
		for q in n.quests_started:
			if QuestJson.s(QuestJson.dict(db.quest(q).get("start_npc")).get("npc_id")) != nid:
				errs.append("%s: starts quest %s but the quest names another start NPC" % [at, q])
		for q in n.quests_completed:
			var qrec := db.quest(q)
			var start_id := QuestJson.s(QuestJson.dict(qrec.get("start_npc")).get("npc_id"))
			if QuestJson.s(QuestJson.dict(qrec.get("end_npc")).get("npc_id"), start_id) != nid:
				errs.append("%s: completes quest %s but the quest names another end NPC" % [at, q])
		if not n.shop_id.is_empty() and not db.has("shops", n.shop_id):
			errs.append("%s: shop %s not in canonical shops" % [at, n.shop_id])
		if n.has_behavior("transport") and NpcTransport.boundary(nid, db).is_empty():
			errs.append("%s: transport is enabled but misostory/npcs/%s.json has no departure boundary (travel itself is not built)" % [at, nid])
		if n.dialogue_lines.is_empty() and n.idle_chatter.is_empty():
			errs.append("%s: no dialogue and no idle chatter (nothing to say)" % at)
		# The map page must list this NPC.
		var listed := false
		for m: Variant in QuestJson.arr(db.map(n.map_id).get("npcs")):
			if QuestJson.s(QuestJson.dict(m).get("id")) == nid:
				listed = true
		if not listed:
			errs.append("%s: not listed on map %s" % [at, n.map_id])
	# The reverse direction: every quest's start / end NPC lists it (the quest records drive the dialogue).
	for qid in db.ids("quests"):
		var qrec := db.quest(qid)
		var sid := QuestJson.s(QuestJson.dict(qrec.get("start_npc")).get("npc_id"))
		var eid := QuestJson.s(QuestJson.dict(qrec.get("end_npc")).get("npc_id"), sid)
		if _defs.has(sid) and not (qid in (_defs[sid] as NpcDef).quests_started):
			errs.append("quest %s: start npc %s does not list it in quests.started_here" % [qid, sid])
		if _defs.has(eid) and not (qid in (_defs[eid] as NpcDef).quests_completed):
			errs.append("quest %s: end npc %s does not list it in quests.completed_here" % [qid, eid])
	for aid: String in db.miso.get("npcs", {}):
		var a: Dictionary = db.miso["npcs"][aid]
		# "_" files are shared tables (e.g. _speech_bubbles.json), not NPC adaptations.
		if not aid.begins_with(SHARED_TABLE_PREFIX) and not _defs.has(aid):
			errs.append("misostory/npcs/%s.json: no canonical npc %s" % [aid, aid])
		if QuestJson.s(a.get("reason")).is_empty():
			errs.append("misostory/npcs/%s.json: missing top-level reason" % aid)
		if not a.has("verified"):
			errs.append("misostory/npcs/%s.json: missing top-level verified flag" % aid)
	return errs


func _build() -> void:
	if _built:
		return
	_built = true
	_defs.clear()
	if db == null:
		return
	var records: Dictionary = db.domain("npcs")
	for nid: String in records:
		_defs[nid] = NpcDef.from_records(QuestJson.dict(records[nid]), db.miso_entity("npcs", nid))
