class_name NpcTransport
extends RefCounted
## An NPC's canonical transport routes (data/canonical/npcs/<id>.json "transport": Shanks sails from Southperry to
## Lith Harbor for 300 mesos from level 7, one-way, per the cached MeowDB beginner guide) and the MisoStory departure
## boundary (data/misostory/npcs/<id>.json "departure"). Pure: works on a QuestEngine (character, content, clock).
##
## Iteration Three builds Maple Island only, so a route whose NPC carries a departure boundary never travels. Boarding
## re-checks the canonical level and fare, records the character flag the boundary names with the game clock
## (flags.maple_island_departure_ready_at), charges the fare only if the boundary says so (Maple Island: no), and
## returns a "departure_requested" effect; NpcInteraction re-emits it and the shell shows the end-of-island screen.
##
## The departure block: {"boundary": true, "charge_fare": false, "flag": "<character flag>",
##                       "unfinished_quests_region": "<quest record region>", reason, verified}.
## Failure reasons: no_route, not_built (no departure boundary: travel itself is not implemented), level_too_low,
## not_enough_mesos.


## The NPC's canonical routes ([] when none).
static func routes(npc_id: String, db: ContentDB) -> Array:
	if db == null:
		return []
	return QuestJson.arr(QuestJson.dict(db.npc(npc_id).get("transport")).get("routes"))


## One route ({} when out of range).
static func route(npc_id: String, index: int, db: ContentDB) -> Dictionary:
	var rs := routes(npc_id, db)
	return QuestJson.dict(rs[index]) if index >= 0 and index < rs.size() else {}


## The NPC's departure boundary adaptation ({} when the NPC has none).
static func boundary(npc_id: String, db: ContentDB) -> Dictionary:
	if db == null:
		return {}
	var b := QuestJson.dict(db.miso_entity("npcs", npc_id).get("departure"))
	return b if QuestJson.b(b.get("boundary")) else {}


## The quest region whose unfinished quests the boundary warns about ("" = none).
static func unfinished_region(npc_id: String, db: ContentDB) -> String:
	return QuestJson.s(boundary(npc_id, db).get("unfinished_quests_region"))


## Why the character cannot board route `index` now ("" = it can): no_route, not_built, level_too_low,
## not_enough_mesos.
static func check(character: CharacterState, npc_id: String, index: int, db: ContentDB) -> String:
	var r := route(npc_id, index, db)
	if r.is_empty():
		return "no_route"
	if boundary(npc_id, db).is_empty():
		return "not_built"
	if character.level < QuestJson.i(r.get("min_level")):
		return "level_too_low"
	if character.mesos < QuestJson.i(r.get("fare_mesos")):
		return "not_enough_mesos"
	return ""


## Boards route `index` of `npc_id` at the departure boundary (see the class comment). Result:
## {"ok", "reason", "effects": [mesos_changed?, flag_set, departure_requested]}. The departure_requested effect:
## {"type", "npc_id", "route_index", "route" (the canonical route), "flag", "at" (game clock), "fare_charged",
##  "region", "unfinished_quests": [quest ids]}.
static func depart(engine: QuestEngine, npc_id: String, index: int) -> Dictionary:
	var c := engine.character
	var why := check(c, npc_id, index, engine.db)
	if why != "":
		return {"ok": false, "reason": why, "effects": []}
	var r := route(npc_id, index, engine.db)
	var b := boundary(npc_id, engine.db)
	var effects: Array = []
	var charged := 0
	if QuestJson.b(b.get("charge_fare")):
		var fare := QuestJson.i(r.get("fare_mesos"))
		if not bool(Mesos.spend(c, fare).get("ok", false)):
			return {"ok": false, "reason": "not_enough_mesos", "effects": []}
		charged = fare
		effects.append({"type": "mesos_changed", "delta": -fare, "mesos": c.mesos})
	var now := engine.now()
	var flag := QuestJson.s(b.get("flag"))
	if not flag.is_empty():
		effects.append_array(QuestJson.arr(engine.set_flag(flag, now).get("effects")))
	var region := QuestJson.s(b.get("unfinished_quests_region"))
	effects.append({"type": "departure_requested", "npc_id": npc_id, "route_index": index, "route": r.duplicate(true),
		"flag": flag, "at": now, "fare_charged": charged, "region": region,
		"unfinished_quests": engine.unfinished_quests(region)})
	return {"ok": true, "reason": "", "effects": effects}


## The unfinished quests of a region for a warning line, chains grouped: "Roger's Apple, Mai's Training (2 of 3
## left), Rain's Maple Quiz (7 of 7 left)". "" when every quest of the region is completed.
static func unfinished_text(engine: QuestEngine, region: String) -> String:
	var order: PackedStringArray = []
	var left := {}
	var totals := {}
	for qid in engine.unfinished_quests(region):
		var chain := engine.chain_info(qid)
		var key := String(chain.get("name", "")) if not chain.is_empty() else engine.definition(qid).name
		if not left.has(key):
			order.append(key)
			left[key] = 0
			totals[key] = int(chain.get("total", 0))
		left[key] = int(left[key]) + 1
	var parts: PackedStringArray = []
	for key in order:
		parts.append(key if int(totals[key]) <= 1 else "%s (%d of %d left)" % [key, int(left[key]), int(totals[key])])
	return ", ".join(parts)
