class_name PlaytestQuestPlan
extends RefCounted
## How to play a quest, derived from canonical data only (docs/runtime/PLAYTEST_HARNESS.md "Quest plans"), so the
## every-quest scenario (scenarios/quest.gd) hard-codes no quest knowledge. Pure: ContentDB in, Dictionaries out.
##
##   var p := PlaytestQuestPlan.plan("1005", db)
##   p.start          {"npc", "npc_name", "map"}       quests/<id>.json start_npc + start_maps
##   p.end            {"npc", "npc_name", "map"}       end_npc + end_maps
##   p.min_level, p.prerequisites, p.chain {group, steps, position, total}, p.followups
##   p.accept_items   canonical items_given_on_accept, plus MisoStory accept_items adaptations (flagged)
##   p.kills          [{mob_id, name, count, maps (spawning it), hunt_map}]       canonical maps/*.json spawns
##   p.items          [{item_id, name, count, from_accept, sources, obtainable}]  drop tables (resolved chances
##                    only) and breakables (the Wooden Box), each source with its maps
##   p.uses, p.talks, p.quiz (PlaytestKit.quiz_answer), p.rewards, p.blocked (why it cannot be played now)
##   p.hand_ins       [{item_id, count}]   items_removed_on_completion: what the turn-in takes from the bag
##
## An objective that only an unresolved drop (no item id, rarity or table category) could supply is reported in
## `blocked` as a source-data gap; it is never faked. Drop chances are the runtime's own (DropRates.effective_entries
## over the schema 3 records and the owner's chance table, contract C1), called by name at run time so this file
## compiles whatever DropRates becomes.

const DROP_RATES_SCRIPT := "res://scripts/core/drops/drop_rates.gd"


## The play plan of one quest. {"ok": false, "blocked": [...]} for an unknown quest.
static func plan(qid: String, db: ContentDB) -> Dictionary:
	var q := db.quest(qid)
	if q.is_empty():
		return {"ok": false, "id": qid, "blocked": PackedStringArray(["no canonical quest %s" % qid])}
	var obj: Dictionary = q.get("objectives", {})
	var blocked := PackedStringArray()
	var start := _npc_at(q.get("start_npc"), q.get("start_maps", []), db)
	var end := _npc_at(q.get("end_npc"), q.get("end_maps", []), db)
	if String(end["npc"]) == "":
		end = start.duplicate()
	var accept: Array = []
	for it: Dictionary in q.get("items_given_on_accept", []):
		accept.append({"item_id": String(it.get("item_id", "")), "count": int(it.get("count", 1)), "adaptation": false})
	for it: Dictionary in db.miso_entity("quests", qid).get("accept_items", []):
		accept.append({"item_id": String(it.get("item_id", "")), "count": int(it.get("count", 1)), "adaptation": true})
	var kills: Array = []
	for k: Dictionary in obj.get("monster_kills", []):
		var mob := String(k.get("mob_id", ""))
		var maps := spawn_maps(mob, db)
		var hunt := hunt_map(mob, String(start["map"]), String(end["map"]), db)
		kills.append({"mob_id": mob, "name": String(db.monster(mob).get("name", k.get("name", mob))),
			"count": int(k.get("count", 1)), "maps": maps, "hunt_map": hunt})
		if hunt == "":
			blocked.append("no map spawns monster %s" % mob)
	var items: Array = []
	for it: Dictionary in obj.get("item_collection", []):
		var id := String(it.get("item_id", ""))
		var from_accept := _given(accept, id)
		var sources := item_sources(id, db, qid)
		var usable := sources.filter(func(s: Dictionary) -> bool: return bool(s.get("obtainable", false)))
		var row := {"item_id": id, "name": String(db.item(id).get("name", it.get("name", id))), "count": int(it.get("count", 1)),
			"from_accept": from_accept, "sources": sources, "obtainable": from_accept or not usable.is_empty()}
		if not bool(row["obtainable"]):
			blocked.append("item %s (%s) has no obtainable source: %s" % [id, row["name"], _source_gaps(sources)])
		elif not from_accept:
			var best := best_source(sources, String(end["map"]), db)
			row["hunt"] = best
		items.append(row)
	var uses: Array = []
	for it: Dictionary in obj.get("item_usage", []):
		var id := String(it.get("item_id", ""))
		uses.append({"item_id": id, "name": String(db.item(id).get("name", it.get("name", id))), "count": int(it.get("count", 1)),
			"from_accept": _given(accept, id)})
		if not _given(accept, id) and item_sources(id, db, qid).is_empty():
			blocked.append("item %s to use has no source" % id)
	var talks: Array = []
	for t: Dictionary in obj.get("npc_talk", []):
		talks.append({"npc": String(t.get("npc_id", "")), "purpose": String(t.get("purpose", ""))})
	var quiz := {}
	for o: Dictionary in obj.get("other", []):
		if String(o.get("type", "")) == "quiz":
			quiz = PlaytestKit.quiz_answer(db, qid)
			if not bool(quiz.get("ok", false)):
				blocked.append("quiz without a canonical correct choice")
		else:
			blocked.append("unsupported objective '%s'" % o.get("type", "?"))
	for v: Variant in obj.get("map_visit", []):
		blocked.append("map_visit objective %s is not planned" % str(v))
	var pre := PackedStringArray()
	for p: Dictionary in (q.get("prerequisites", {}) as Dictionary).get("quests", []):
		pre.append(String(p.get("quest_id", "")))
	var line: Dictionary = q.get("quest_line", {}) if q.get("quest_line") is Dictionary else {}
	var steps := PackedStringArray()
	for s: Dictionary in line.get("steps", []):
		steps.append(String(s.get("quest_id", "")))
	var follow := PackedStringArray()
	for f: Dictionary in q.get("followup_quests", []):
		follow.append(String(f.get("quest_id", "")))
	var rew: Dictionary = q.get("rewards", {})
	var random: Array = []
	for g: Dictionary in rew.get("random", []):
		var ids := PackedStringArray()
		for it: Dictionary in g.get("items", []):
			ids.append(String(it.get("item_id", "")))
		random.append(ids)
	var fixed: Array = []
	for it: Dictionary in rew.get("items", []):
		fixed.append({"item_id": String(it.get("item_id", "")), "count": int(it.get("count", 1))})
	# What the turn-in takes: canonical items_removed_on_completion (the list the quest engine removes), not the item
	# objectives (an objective may be a "hold" without a hand-in).
	var hand_ins: Array = []
	var removed: Variant = q.get("items_removed_on_completion")
	for it: Variant in ((removed as Dictionary).get("items", []) if removed is Dictionary else []):
		if it is Dictionary:
			hand_ins.append({"item_id": String((it as Dictionary).get("item_id", "")), "count": int((it as Dictionary).get("count", 1))})
	return {
		"ok": blocked.is_empty(), "id": qid, "name": String(q.get("name", qid)), "start": start, "end": end,
		"min_level": maxi(1, int(q.get("min_level", 0)) if q.get("min_level") != null else 1),
		"prerequisites": pre, "chain": {"group": String(q.get("quest_group", "")) if q.get("quest_group") != null else "",
			"steps": steps, "position": int(line.get("position", 1)), "total": int(line.get("total", 1))},
		"followups": follow, "accept_items": accept, "kills": kills, "items": items, "uses": uses, "talks": talks,
		"quiz": quiz, "rewards": {"exp": int(rew.get("exp", 0)), "mesos": int(rew.get("mesos", 0)), "items": fixed,
			"random": random}, "hand_ins": hand_ins, "blocked": blocked,
	}


## The quests of a chain as quest.gd takes them: "1013-1019" (a range), "1006,1009,1010", or one id; [] when an id
## is not a canonical quest.
static func parse_ids(spec: String, db: ContentDB) -> PackedStringArray:
	var out := PackedStringArray()
	for part in spec.replace(" ", "").split(",", false):
		if part.contains("-"):
			var a := int(part.get_slice("-", 0))
			var b := int(part.get_slice("-", 1))
			for n in range(a, b + 1):
				out.append(str(n))
		else:
			out.append(part)
	for id in out:
		if not db.has("quests", id):
			return PackedStringArray()
	return out


## The every-quest set: one chain per canonical quest line (quest_line steps), and each standalone quest alone, in
## quest id order. Each chain is a PackedStringArray of quest ids.
static func chains(db: ContentDB) -> Array:
	var ids := Array(db.ids("quests"))
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	var seen := {}
	var out: Array = []
	for id: String in ids:
		if seen.has(id):
			continue
		var line: Variant = db.quest(id).get("quest_line")
		var steps := PackedStringArray()
		if line is Dictionary:
			for s: Dictionary in (line as Dictionary).get("steps", []):
				steps.append(String(s.get("quest_id", "")))
		if steps.size() < 2 or not steps.has(id):
			steps = PackedStringArray([id])
		for s in steps:
			seen[s] = true
		out.append(steps)
	return out


## A chain as quest.gd and playtest_quests.sh name it: "1013-1019" for consecutive ids, else "1006,1009,1010".
static func chain_spec(ids: PackedStringArray) -> String:
	if ids.size() == 1:
		return ids[0]
	var consecutive := true
	for i in range(1, ids.size()):
		consecutive = consecutive and int(ids[i]) == int(ids[i - 1]) + 1
	return "%s-%s" % [ids[0], ids[ids.size() - 1]] if consecutive else ",".join(ids)


## What a chain needs before its first quest can be played (the setup quest.gd does with logged console commands):
## {"level" (the first quest's min_level), "complete" (prerequisite quests outside the chain, prerequisites first),
## "map" (the first quest's start map), "levels" {quest id: min_level} for the later steps}.
static func setup_for(ids: PackedStringArray, db: ContentDB) -> Dictionary:
	var first := plan(ids[0], db) if not ids.is_empty() else {}
	var complete := PackedStringArray()
	for id in ids:
		_prereq_closure(id, db, ids, complete)
	var levels := {}
	for id in ids:
		levels[id] = int(plan(id, db).get("min_level", 1))
	return {"level": int(first.get("min_level", 1)), "complete": complete,
		"map": String((first.get("start", {}) as Dictionary).get("map", "")), "levels": levels}


static func _prereq_closure(id: String, db: ContentDB, chain: PackedStringArray, out: PackedStringArray) -> void:
	for p: Dictionary in (db.quest(id).get("prerequisites", {}) as Dictionary).get("quests", []):
		var pid := String(p.get("quest_id", ""))
		if pid == "" or chain.has(pid) or out.has(pid):
			continue
		_prereq_closure(pid, db, chain, out)
		out.append(pid)


## The maps whose canonical spawns include `mob_id`: [{"map", "count"}], most spawns first.
static func spawn_maps(mob_id: String, db: ContentDB) -> Array:
	var out: Array = []
	for m in db.ids("maps"):
		var n := 0
		for s: Variant in db.map(m).get("spawns", []):
			if s is Dictionary and String((s as Dictionary).get("mob_id", "")) == mob_id:
				n += 1
		if n > 0:
			out.append({"map": m, "count": n})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["count"]) > int(b["count"]) or (int(a["count"]) == int(b["count"]) and String(a["map"]) < String(b["map"])))
	return out


## Where to hunt `mob_id` between `from_map` (where the quest is taken) and `to_map` (where it is turned in): the
## spawning map with the fewest portal hops from -> hunt -> to (both ways walkable over canonical portals), then the
## most spawns. "" when no reachable map spawns it.
static func hunt_map(mob_id: String, from_map: String, to_map: String, db: ContentDB) -> String:
	var best := ""
	var best_cost := 1 << 30
	var best_n := -1
	for row: Dictionary in spawn_maps(mob_id, db):
		var m := String(row["map"])
		var a := hops(from_map, m, db) if from_map != "" else 0
		var b := hops(m, to_map, db) if to_map != "" else 0
		if a < 0 or b < 0:
			continue
		var cost := a + b
		if cost < best_cost or (cost == best_cost and int(row["count"]) > best_n):
			best_cost = cost
			best_n = int(row["count"])
			best = m
	return best


## Portal hops from one map to another over the canonical portals (-1: no way; 0: the same map).
static func hops(from: String, to: String, db: ContentDB) -> int:
	var path := PlaytestKit.portal_path(db, from, to)
	return path.size() - 1 if not path.is_empty() else -1


## Every source of an item: monster and breakable drop tables that list it, with the chance the runtime would roll
## ({"kind" (monster | breakable), "owner", "owner_name", "chance" (null when unresolved), "chance_state", "quest_gate"
## (a quest id or ""), "maps" [map ids], "obtainable" (resolved, an item id, a chance above 0, and the gate open for
## `for_quest`), "why"}).
static func item_sources(item_id: String, db: ContentDB, for_quest: String = "") -> Array:
	var out: Array = []
	for owner in db.ids("drops"):
		var table := db.drop_table(owner)
		var kind := String((table.get("owner", {}) as Dictionary).get("kind", ""))
		var row := _source_row(owner, table, item_id, db)
		if row.is_empty():
			continue
		row["kind"] = kind
		var name := String((table.get("owner", {}) as Dictionary).get("name", owner))
		row["owner"] = owner
		row["owner_name"] = name
		if kind == "breakable":
			var maps := PackedStringArray()
			for m: Dictionary in db.get_entity("breakables", owner).get("maps", []):
				if bool(m.get("maple_island", true)) and db.has("maps", String(m.get("map_id", ""))):
					maps.append(String(m.get("map_id", "")))
			row["maps"] = maps
		else:
			var maps := PackedStringArray()
			for s: Dictionary in spawn_maps(owner, db):
				maps.append(String(s["map"]))
			row["maps"] = maps
		var why := source_why(row, for_quest)
		row["obtainable"] = why == ""
		row["why"] = why
		out.append(row)
	return out


## Why a source row cannot supply its item for `for_quest` ("" when it can): an unresolved chance (contract C1: it
## never rolls), a chance of 0, a quest gate to another quest (C1/C2: it rolls only while that quest is in progress),
## or no map holding the owner.
static func source_why(row: Dictionary, for_quest: String) -> String:
	var gate := String(row.get("quest_gate", ""))
	if row.get("chance") == null:
		return "unresolved chance"
	if float(row["chance"]) <= 0.0:
		return "chance 0"
	if gate != "" and gate != for_quest:
		return "gated to quest %s" % gate
	if (row.get("maps", PackedStringArray()) as PackedStringArray).is_empty():
		return "no map has the owner"
	return ""


## The source to farm for a quest: an obtainable one, the highest chance, then the fewest hops from `near_map`.
static func best_source(sources: Array, near_map: String, db: ContentDB) -> Dictionary:
	var best := {}
	var best_key := [-1.0, 1 << 30]
	for s: Dictionary in sources:
		if not bool(s.get("obtainable", false)):
			continue
		var near := 1 << 30
		var at := ""
		for m: Variant in s.get("maps", []):
			var h := hops(near_map, String(m), db) if near_map != "" else 0
			var back := hops(String(m), near_map, db) if near_map != "" else 0
			if h >= 0 and back >= 0 and h < near:
				near = h
				at = String(m)
		if at == "":
			continue
		var chance := float(s["chance"])
		if chance > float(best_key[0]) or (is_equal_approx(chance, float(best_key[0])) and near < int(best_key[1])):
			best_key = [chance, near]
			best = s.duplicate()
			best["map"] = at
	return best


## The entry of `item_id` in one drop table with the runtime's chance (DropRates.effective_entries): {"chance" (null
## when the entry never rolls), "chance_state" ("resolved" | "unresolved"), "quest_gate", "schema", "key" (the entry's
## stable slug, the parity key drop:<owner>/<key>)}; {} when the table does not list the item.
static func _source_row(owner: String, table: Dictionary, item_id: String, db: ContentDB) -> Dictionary:
	var rates: Variant = load(DROP_RATES_SCRIPT)
	if not (rates is GDScript and _has_static(rates as GDScript, "effective_entries")):
		return {}
	for e: Variant in (rates as GDScript).call("effective_entries", owner, db):
		if not (e is Dictionary) or String((e as Dictionary).get("item_id", "")) != item_id:
			continue
		var row: Dictionary = e
		var resolved := String(row.get("excluded", "")) == ""
		return {"chance": float(row.get("chance", 0.0)) if resolved else null, "chance_state": "resolved" if resolved else "unresolved",
			"quest_gate": String(row.get("quest_gate", "")), "schema": int(table.get("schema_version", 1)), "key": String(row.get("key", ""))}
	return {}


static func _has_static(script: GDScript, method: String) -> bool:
	for m: Dictionary in script.get_script_method_list():
		if String(m.get("name", "")) == method:
			return true
	return false


static func _npc_at(npc: Variant, maps: Variant, db: ContentDB) -> Dictionary:
	var id := String((npc as Dictionary).get("npc_id", "")) if npc is Dictionary else ""
	var map := ""
	if maps is Array and not (maps as Array).is_empty():
		map = String(((maps as Array)[0] as Dictionary).get("map_id", ""))
	return {"npc": id, "npc_name": String(db.npc(id).get("name", id)) if id != "" else "", "map": map}


static func _given(accept: Array, item_id: String) -> bool:
	for a: Dictionary in accept:
		if String(a["item_id"]) == item_id:
			return true
	return false


static func _source_gaps(sources: Array) -> String:
	if sources.is_empty():
		return "no drop table lists it"
	var parts := PackedStringArray()
	for s: Dictionary in sources:
		parts.append("%s %s: %s" % [s.get("kind", ""), s.get("owner_name", ""), s.get("why", "")])
	return "; ".join(parts)
