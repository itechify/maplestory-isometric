class_name PlaytestQuestRunner
extends RefCounted
## Plays one canonical quest at a time in the real game, step by step (docs/runtime/PLAYTEST_HARNESS.md "The quest
## runner"): the offer (availability and acceptance), the objectives, the turn-in with the exact canonical rewards,
## and the follow-ups. Everything about a quest comes from PlaytestQuestPlan (canonical data); everything it does goes
## through PlaytestKit's real input, so it is legal in strict mode. The every-quest scenario (scenarios/quest.gd) and
## the clean-character playthrough (scenarios/playthrough.gd) both play their quests through it.
##
##   var qr := PlaytestQuestRunner.new(d, k)
##   qr.mid_reload_policy = "listed"; qr.mid_reload_quests = {"1009": true}   # quest.gd keeps "auto"
##   await qr.verify_mid()                       # after every Continue: the saved progress came back
##   if await qr.offer("1006"):                  # travel, marker, Quest Log, the accept in the dialogue
##       await qr.objectives("1006")             # kills, drops picked up, Wooden Boxes, items used
##       await qr.turn_in("1006")                # the turn-in NPC, quizzes, the exact reward
##       await qr.after("1006")                  # follow-ups offered
##   qr.results(ids)                             # d.carry["quest_results"]
##
## Every check carries the parity key quest:<id> (contract C6). What each quest showed is also kept in
## d.carry["quest_evidence"][qid] (survives reloads) for PlaytestQuestSummary's per-quest report: the offer marker, the
## accept, the objective rows, the completion, the rewards (EXP and mesos deltas, items, the random pick and the C3
## rewards_received record), the follow-ups and the mid-quest save and restart.
##
## The mid-quest save and process restart (mid_reload_policy):
##   "auto"    quest.gd's rule: each quest with objectives once, at half of its first kill or item objective (a monster
##             drop or a Wooden Box item alike), and the first talk-only quest of a run right after its accept
##   "listed"  the same points, only for the quests in mid_reload_quests
##   "off"     never
## A reload saves through the pause menu and ends the process with Quit Game (PlaytestDriver.reload_process); the
## next phase calls verify_mid() after its Continue.

## Game-second budgets of the objective hunts.
const KILL_BUDGET_S := 1200.0
const ITEM_BUDGET_S := 1500.0
const LEVEL_BUDGET_S := 1500.0
## Wooden Box respawns are 90-180 s (maps/<id>.json reactors); the box hunt waits for them up to this long.
const BOX_BUDGET_S := 1500.0

var d: PlaytestDriver = null
var db: ContentDB = null
var k: PlaytestKit = null
## qid -> PlaytestQuestPlan.plan (cached).
var plans: Dictionary = {}
## AP goes into the stats window in this order during the hunts (a Wooden Club warrior's split).
var ap_plan: Array = ["str", "dex"]
## "auto" | "listed" | "off" (see above).
var mid_reload_policy: String = "auto"
## qid -> true: the quests a "listed" policy saves and restarts in the middle of.
var mid_reload_quests: Dictionary = {}


func _init(p_d: PlaytestDriver, p_k: PlaytestKit) -> void:
	d = p_d
	db = d.db()
	k = p_k


## The quest's play plan (PlaytestQuestPlan.plan, cached).
func plan(qid: String) -> Dictionary:
	if not plans.has(qid):
		plans[qid] = PlaytestQuestPlan.plan(qid, db)
	return plans[qid]


## Plays a quest from its live status to the end: the offer when not started, the objectives, the turn-in and the
## follow-ups. Returns true when it is completed. Await it.
func play(qid: String) -> bool:
	var c := d.character()
	if c.quests.is_completed(qid):
		return true
	if c.quests.status(qid) == QuestLog.NOT_STARTED and not await offer(qid):
		return false
	if not await objectives(qid):
		return false
	if not await turn_in(qid):
		return false
	await after(qid)
	return true


# =================================================================================================================
# Availability and acceptance
# =================================================================================================================

## Walks to the quest's NPC, checks the offer (the marker, the engine, the Quest Log's Available tab), accepts it in
## the dialogue (Yes) and checks what the accept changed. A quest above the character's level is first checked to be
## refused, then the level is reached by hunting. Returns true once it is in progress (or done). Await it.
func offer(qid: String) -> bool:
	var p := plan(qid)
	var c := d.character()
	var pq := pq_of(qid)
	var npc := String(p["start"]["npc"])
	var ev := _ev(qid)
	if c.level < int(p["min_level"]):
		# A later quest of the chain above the character's level: refused now, offered once play reaches the level.
		d.check("%s is refused below its canonical level %d (level %d: the engine says unavailable)" % [qid,
			int(p["min_level"]), c.level], not d.game().quests.engine.is_available(qid), "", pq)
		ev["refused_below_level"] = c.level
		if not await reach_level(int(p["min_level"]), String(p["start"]["map"])):
			d.check("%s: level %d reached by play for its canonical min_level" % [qid, int(p["min_level"])], false,
				"level %d" % c.level, pq)
			return false
	if not d.check("%s: walked to %s's map %s" % [qid, p["start"]["npc_name"], p["start"]["map"]],
			await k.travel_to(String(p["start"]["map"])), d.current_map(), pq):
		return false
	await gate_probe(qid)
	await k.approach(npc)
	var m0 := await k.marker(npc)
	var offered: bool = m0["state"] == "available" and m0["engine"] == "available" and d.game().quests.engine.is_available(qid)
	d.check("%s: %s's marker offers it (gold !; the engine agrees)" % [qid, p["start"]["npc_name"]], offered, str(m0),
		pq + ["mechanic:quest-indicators"])
	ev["offer"] = {"npc": String(p["start"]["npc_name"]), "map": d.current_map(), "level": c.level,
		"marker": String(m0["state"]), "engine": String(m0["engine"]), "ok": offered}
	var avail := await k.quest_window(qid, "available")
	d.check("%s: the Quest Log's Available tab lists it before the accept" % qid, bool(avail["listed"]),
		"list %s" % [avail["list"]], pq + ["mechanic:quest-log"])
	ev["offer"]["log_available"] = bool(avail["listed"])
	await d.close_window("quests")
	var bag0 := k.snapshot()
	var talk: Dictionary = await k.talk(npc)
	if not d.check("%s: %s can be talked to on foot" % [qid, p["start"]["npc_name"]], bool(talk.get("open", false)),
			"%s %s" % [talk.get("talk_gap", ""), talk.get("why", "")], pq + ["npc:" + npc]):
		return false
	var clock0 := float((talk["pre"] as Dictionary)["clock"])
	var conv: Dictionary = await k.converse({qid: "accept"})
	d.note("%s accept pages: %s" % [qid, " | ".join(conv["pages"])])
	var accepted := c.quests.is_in_progress(qid) or c.quests.is_completed(qid)
	ev["accept"] = {"ok": accepted, "pages": (conv["pages"] as PackedStringArray).size(), "level": c.level,
		"game_s": snappedf(d.game_s(), 0.1), "phase": d.phase}
	if not d.check("%s: accepted in %s's dialogue (Yes)" % [qid, p["start"]["npc_name"]], accepted, c.quests.status(qid), pq):
		return false
	var given := PackedStringArray()
	var given_ok := true
	for it: Dictionary in p["accept_items"]:
		var id := String(it["item_id"])
		var n := c.inventory.count(id)
		given_ok = given_ok and n >= int(it["count"])
		given.append("%s %s x%d (held %d, was %d)%s" % [id, k.item_name(id), int(it["count"]), n,
			PlaytestKit.count_in(bag0["bag"], id), " (MisoStory adaptation)" if bool(it["adaptation"]) else ""])
	if not (p["accept_items"] as Array).is_empty():
		d.check("%s: the accept items are in the bag: %s" % [qid, ", ".join(given)], given_ok, ", ".join(given), pq)
		ev["accept"]["items"] = ", ".join(given)
		ev["accept"]["items_ok"] = given_ok
	var lines := k.log_since(clock0)
	d.check("%s: the HUD log says 'Quest started: %s'" % [qid, p["name"]], ("Quest started: %s" % p["name"]) in lines,
		" / ".join(lines), pq)
	var m1 := await k.marker(npc)
	d.check("%s: %s's marker after the accept is the engine's ('%s')" % [qid, p["start"]["npc_name"], m1["engine"]],
		m1["state"] == m1["engine"] and (m1["state"] != "available" or _offers_other(npc, qid)), str(m1),
		pq + ["mechanic:quest-indicators"])
	ev["accept"]["marker_after"] = String(m1["state"])
	var qw := await k.quest_window(qid, "in_progress")
	d.check("%s: the Quest Log lists it In Progress (%s)" % [qid, PlaytestKit.rows_text(qw["rows"])], bool(qw["listed"])
		or c.quests.is_completed(qid), "list %s" % [qw["list"]], pq + ["mechanic:quest-log"])
	ev["accept"]["log_rows"] = PlaytestKit.rows_text(qw["rows"])
	await d.close_window("quests")
	# A quest with nothing but a talk, quiz or use objective: the save and restart happen right after the accept.
	if _talk_only(qid) and _may_reload_talk_only(qid):
		await mid_reload(qid, "after the accept")
	return true


## The quest gate in the real game (contracts C1/C2): when the quest's items come from a breakable whose drop entries
## are gated to it, one box broken before the accept must drop none of them.
func gate_probe(qid: String) -> void:
	var gated := PackedStringArray()
	var owner := ""
	for iobj: Dictionary in plan(qid)["items"]:
		for s: Dictionary in iobj["sources"]:
			if String(s["kind"]) == "breakable" and String(s.get("quest_gate", "")) == qid:
				gated.append(String(iobj["item_id"]))
				owner = String(s["owner"])
	if gated.is_empty():
		return
	var pq := pq_of(qid) + ["breakable:%s" % owner]
	if k.breakables().is_empty():
		d.soft_check("%s: a Wooden Box to break before the accept (contract C8)" % qid, false,
			"no unbroken box in %s (group miso_breakables)" % d.current_map(), pq)
		return
	var c := d.character()
	var before := {}
	for id in gated:
		before[id] = c.inventory.count(id)
	var r: Dictionary = await k.break_box(null)
	var got := PackedStringArray()
	for id in gated:
		if c.inventory.count(id) != int(before[id]):
			got.append("%s %+d" % [k.item_name(id), c.inventory.count(id) - int(before[id])])
	d.check("%s: a Wooden Box broken before the accept drops none of %s (gated to the quest)" % [qid, gated],
		bool(r["ok"]) and got.is_empty(), "%s; gained %s" % [r, got], pq)
	_ev(qid)["gate_probe"] = {"broken": bool(r["ok"]), "gained": ", ".join(got), "box": String(r.get("key", ""))}


## True when `m` (a marker read) shows an offer for `qid` at its NPC.
func offers(m: Dictionary, qid: String) -> bool:
	return String(m.get("state", "")) == "available" and d.game().quests.engine.is_available(qid)


## True when the NPC still offers another quest (its marker stays "available" after the accept).
func _offers_other(npc: String, qid: String) -> bool:
	var engine := d.game().quests.engine
	for other in engine.catalog.started_by(npc):
		if other != qid and engine.is_available(other):
			return true
	return false


# =================================================================================================================
# Objectives
# =================================================================================================================

## Plays the quest's objectives from their live progress: kills with the attack key in the hunt map, items from
## their best source (drops picked up with Z, Wooden Boxes broken), items used by a double-click. Returns true when
## they are met. Await it.
func objectives(qid: String) -> bool:
	var p := plan(qid)
	var c := d.character()
	var pq := pq_of(qid)
	var ev := _ev(qid)
	var rows: Array = ev.get("objectives", [])
	for kobj: Dictionary in p["kills"]:
		var mob := String(kobj["mob_id"])
		var need := int(kobj["count"])
		if c.quests.kills(qid, mob) >= need:
			continue
		var map := String(kobj["hunt_map"])
		if not d.check("%s: walked to %s to hunt %s" % [qid, map, kobj["name"]], await k.travel_to(map), d.current_map(), pq):
			return false
		var half := floori(need / 2.0)
		if _may_reload(qid) and c.quests.kills(qid, mob) < half:
			var h0: Dictionary = await k.hunt([mob], func() -> bool: return c.quests.kills(qid, mob) >= half,
				{"map": map, "ap_plan": ap_plan, "max_s": KILL_BUDGET_S})
			d.note("%s: hunted %s to %d/%d (%s)" % [qid, kobj["name"], c.quests.kills(qid, mob), need, h0])
			if c.quests.kills(qid, mob) >= half:
				await mid_reload(qid, "at %d/%d %s" % [c.quests.kills(qid, mob), need, kobj["name"]])
		elif _may_reload(qid) and half < 1:
			await mid_reload(qid, "at 0/%d %s" % [need, kobj["name"]])
		var k0 := c.quests.kills(qid, mob)
		var h: Dictionary = await k.hunt([mob], func() -> bool: return c.quests.kills(qid, mob) >= need,
			{"map": map, "ap_plan": ap_plan, "max_s": KILL_BUDGET_S})
		var qw := await k.quest_window(qid, "in_progress")
		var row := "%s %d/%d" % [kobj["name"], mini(c.quests.kills(qid, mob), need), need]
		await d.close_window("quests")
		var met := c.quests.kills(qid, mob) >= need
		rows.append({"kind": "kill", "what": "%s x%d" % [kobj["name"], need], "where": map, "progress": "%d -> %d of %d"
			% [k0, c.quests.kills(qid, mob), need], "log_row": PlaytestKit.rows_text(qw["rows"]), "ok": met,
			"kills": int(h.get("kills", 0)), "time_s": float(h.get("time_s", 0.0))})
		ev["objectives"] = rows
		if not d.check("%s: %d %s killed with the attack key in %s (%d -> %d of %d)" % [qid, need, kobj["name"], map, k0,
				c.quests.kills(qid, mob), need], met, "%s; Quest Log rows %s" % [h,
				PlaytestKit.rows_text(qw["rows"])], pq + ["monster:" + mob]):
			return false
		d.check("%s: the Quest Log shows '%s'" % [qid, row], PlaytestKit.row_has(qw["rows"], row, true)
			or c.quests.is_completed(qid), PlaytestKit.rows_text(qw["rows"]), pq + ["mechanic:quest-log"])
	for iobj: Dictionary in p["items"]:
		var id := String(iobj["item_id"])
		var need := int(iobj["count"])
		if bool(iobj["from_accept"]):
			continue
		if c.inventory.count(id) >= need:
			if not _has_row(rows, id):
				rows.append({"kind": "item", "what": "%s x%d" % [iobj["name"], need], "item_id": id, "where": d.current_map(),
					"progress": "already held %d" % c.inventory.count(id), "ok": true})
				ev["objectives"] = rows
			continue
		var n0 := c.inventory.count(id)
		var ok := await collect(qid, iobj)
		var src: Dictionary = iobj.get("hunt", {})
		rows.append({"kind": "item", "what": "%s x%d" % [iobj["name"], need], "item_id": id, "where": String(src.get("map", "")),
			"source": "%s %s (chance %s)" % [src.get("kind", "?"), src.get("owner_name", "?"), src.get("chance")],
			"progress": "%d -> %d of %d" % [n0, c.inventory.count(id), need], "ok": ok})
		ev["objectives"] = rows
		if not ok:
			return false
	for uobj: Dictionary in p["uses"]:
		var id := String(uobj["item_id"])
		var need := int(uobj["count"])
		var u0 := c.quests.uses(qid, id)
		while c.quests.uses(qid, id) < need:
			var hp0 := c.hp
			var r: Dictionary = await k.use_item(id)
			if not d.check("%s: %s used by a double-click in the Item window (%d/%d)" % [qid, uobj["name"], c.quests.uses(qid, id),
					need], bool(r["ok"]), "%s; HP %d -> %d" % [r["status"], hp0, c.hp], pq + ["item:" + id]):
				return false
		if u0 < need:
			rows.append({"kind": "use", "what": "%s x%d" % [uobj["name"], need], "item_id": id, "where": d.current_map(),
				"progress": "%d -> %d of %d" % [u0, c.quests.uses(qid, id), need], "ok": true})
			ev["objectives"] = rows
	return true


func _has_row(rows: Array, item_id: String) -> bool:
	for r: Dictionary in rows:
		if String(r.get("item_id", "")) == item_id:
			return true
	return false


## Collects a quest item from its best source: a monster's drop (hunting it and picking up with Z) or the Wooden Box
## (breaking boxes, C8). The source and its chance come from the canonical drop tables (PlaytestQuestPlan).
func collect(qid: String, iobj: Dictionary) -> bool:
	var c := d.character()
	var pq := pq_of(qid)
	var id := String(iobj["item_id"])
	var need := int(iobj["count"])
	var src: Dictionary = iobj.get("hunt", {})
	if src.is_empty():
		d.check("%s: a source for %s" % [qid, iobj["name"]], false, str(iobj["sources"]), pq)
		return false
	var map := String(src["map"])
	if not d.check("%s: walked to %s for %s (%s %s, chance %s)" % [qid, map, iobj["name"], src["kind"], src["owner_name"],
			src["chance"]], await k.travel_to(map), d.current_map(), pq):
		return false
	var n0 := c.inventory.count(id)
	if String(src["kind"]) == "breakable":
		return await collect_from_boxes(qid, iobj, src)
	var half := floori(need / 2.0)
	if _may_reload(qid) and half >= 1 and n0 < half:
		await k.hunt([String(src["owner"])], func() -> bool: return c.inventory.count(id) >= half,
			{"map": map, "ap_plan": ap_plan, "max_s": ITEM_BUDGET_S})
		if c.inventory.count(id) >= half:
			await mid_reload(qid, "at %d/%d %s" % [c.inventory.count(id), need, iobj["name"]])
	var h: Dictionary = await k.hunt([String(src["owner"])], func() -> bool: return c.inventory.count(id) >= need,
		{"map": map, "ap_plan": ap_plan, "max_s": ITEM_BUDGET_S})
	return d.check("%s: %d %s collected from %s drops picked up with Z (%d -> %d)" % [qid, need, iobj["name"],
		src["owner_name"], n0, c.inventory.count(id)], c.inventory.count(id) >= need, str(h),
		pq + ["item:" + id, "drop:%s/%s" % [src["owner"], id]])


## Breaks Wooden Boxes (contract C8) in the source's maps until the bag holds `need`: the attack key on each box,
## the drops picked up with Z, the next map when every box of this one is broken, and a wait for the respawns.
func collect_from_boxes(qid: String, iobj: Dictionary, src: Dictionary) -> bool:
	var c := d.character()
	var pq := pq_of(qid) + ["breakable:%s" % src["owner"]]
	var id := String(iobj["item_id"])
	var need := int(iobj["count"])
	var boxes := k.breakables(true)
	if not d.check("%s: Wooden Boxes stand in %s (group miso_breakables, contract C8)" % [qid, d.current_map()],
			not boxes.is_empty(), ("%d boxes" % boxes.size()) if not boxes.is_empty() else
			"the breakables runtime is not built: %s comes only from the Wooden Box" % iobj["name"], pq):
		return false
	var maps: Array = Array(src["maps"])
	var t0 := d.game_s()
	var broken := 0
	var mi := maps.find(d.current_map())
	var ev := _ev(qid)
	while still_need(qid) and d.game_s() - t0 < BOX_BUDGET_S:
		if k.is_dead():
			await k.respawn()
			continue
		var r: Dictionary = await k.break_box(null)
		if bool(r["ok"]):
			broken += 1
			ev["boxes_broken"] = int(ev.get("boxes_broken", 0)) + 1
			d.check("%s: a Wooden Box broke after %d landed hits (canonical hits_to_break %d)" % [qid, int(r["hits"]),
				int(db.get_entity("breakables", String(src["owner"])).get("hits_to_break", -1))],
				int(r["hits"]) == int(db.get_entity("breakables", String(src["owner"])).get("hits_to_break", -1)), str(r), pq)
			# The save and restart in the middle, as for a monster drop: at half of this item (box state is not
			# persisted, C8, so the next phase finds the boxes whole again and breaks on).
			var half := maxi(1, floori(need / 2.0))
			if _may_reload(qid) and c.inventory.count(id) >= half and still_need(qid):
				await mid_reload(qid, "at %d/%d %s" % [c.inventory.count(id), need, iobj["name"]])
			continue
		# Every box here is broken: the next map that has boxes, or a wait for the respawns.
		mi = (mi + 1) % maps.size()
		if maps.size() > 1 and String(maps[mi]) != d.current_map():
			await k.travel_to(String(maps[mi]))
		else:
			await d.wait(10.0)
	return d.check("%s: %s x%d, %d Wooden Boxes broken in this phase (held %d)" % [qid, iobj["name"], need, broken, c.inventory.count(id)],
		not still_need(qid), "", pq + ["item:" + id])


## True while an item objective of `qid` (other than an accept item) is short in the bag.
func still_need(qid: String) -> bool:
	var c := d.character()
	for iobj: Dictionary in plan(qid)["items"]:
		if not bool(iobj["from_accept"]) and c.inventory.count(String(iobj["item_id"])) < int(iobj["count"]):
			return true
	return false


## Hunts in the nearest map with monsters until the character reaches `level` (a later quest of the chain needs it).
func reach_level(level: int, near_map: String) -> bool:
	var c := d.character()
	var best := ""
	var best_h := 1 << 30
	for m in db.ids("maps"):
		if (db.map(m).get("spawns", []) as Array).is_empty():
			continue
		var h := PlaytestQuestPlan.hops(d.current_map(), m, db)
		var back := PlaytestQuestPlan.hops(m, near_map, db)
		if h >= 0 and back >= 0 and h + back < best_h:
			best_h = h + back
			best = m
	if best == "" or not await k.travel_to(best):
		return false
	var mobs: Array = []
	for s: Dictionary in db.map(best).get("spawns", []):
		if not mobs.has(String(s.get("mob_id", ""))):
			mobs.append(String(s.get("mob_id", "")))
	var h: Dictionary = await k.hunt(mobs, func() -> bool: return c.level >= level, {"map": best, "ap_plan": ap_plan,
		"max_s": LEVEL_BUDGET_S})
	d.note("hunted in %s to level %d for the next quest: %s" % [best, c.level, h])
	return c.level >= level


# =================================================================================================================
# Turn-in
# =================================================================================================================

## Walks to the turn-in NPC, checks the completable marker, answers a quiz (one wrong answer first: its canonical
## line, the quest still in progress; then the canonical answer), completes the quest in the dialogue and checks the
## exact reward, the HUD log and the Quest Log's Completed tab. Returns true when completed. Await it.
func turn_in(qid: String) -> bool:
	var p := plan(qid)
	var c := d.character()
	var pq := pq_of(qid)
	var npc := String(p["end"]["npc"])
	var ev := _ev(qid)
	if c.quests.is_completed(qid):
		return true
	if not d.check("%s: walked to %s's map %s for the turn-in" % [qid, p["end"]["npc_name"], p["end"]["map"]],
			await k.travel_to(String(p["end"]["map"])), d.current_map(), pq):
		return false
	await k.approach(npc)
	var m0 := await k.marker(npc)
	d.check("%s: %s's marker reads 'completable' (green ?)" % [qid, p["end"]["npc_name"]], m0["state"] == "completable"
		and m0["engine"] == "completable", str(m0), pq + ["mechanic:quest-indicators"])
	ev["turn_in"] = {"npc": String(p["end"]["npc_name"]), "map": d.current_map(), "marker": String(m0["state"])}
	var quiz: Dictionary = p["quiz"]
	if not quiz.is_empty():
		# One wrong answer first: the canonical paired line, and the quest stays in progress.
		var wrong: Dictionary = (quiz["wrong"] as Array)[0] if not (quiz["wrong"] as Array).is_empty() else {}
		var tw: Dictionary = await k.talk(npc)
		if not d.check("%s: %s can be talked to for the quiz" % [qid, p["end"]["npc_name"]], bool(tw.get("open", false)),
				String(tw.get("why", "")), pq):
			return false
		var cw: Dictionary = await k.converse({qid: "quiz_wrong"})
		var aw: Dictionary = (cw["quiz"] as Array)[0] if not (cw["quiz"] as Array).is_empty() else {}
		d.check("%s: the quiz '%s' is a menu of the canonical choices" % [qid, quiz["question"]], not aw.is_empty(),
			" | ".join(cw["pages"]), pq + ["mechanic:quiz-quests"])
		var wrong_ok := not aw.is_empty() and not bool(aw["correct"]) and same_text(String(aw["response"]),
			String(wrong.get("response", ""))) and c.quests.is_in_progress(qid)
		d.check("%s: the wrong answer '%s' shows its canonical line and leaves the quest in progress" % [qid, wrong.get("text", "")],
			wrong_ok, "picked '%s'; shown '%s'; canonical '%s'; status %s" % [aw.get("choice", ""),
				String(aw.get("response", "")).left(100), String(wrong.get("response", "")).left(100), c.quests.status(qid)],
			pq + ["mechanic:quiz-quests"])
		ev["quiz"] = {"question": String(quiz["question"]), "wrong": String(aw.get("choice", "")), "wrong_ok": wrong_ok}
	var talk: Dictionary = await k.talk(npc)
	if not d.check("%s: %s can be talked to for the turn-in" % [qid, p["end"]["npc_name"]], bool(talk.get("open", false)),
			"%s %s" % [talk.get("talk_gap", ""), talk.get("why", "")], pq + ["npc:" + npc]):
		return false
	var snap: Dictionary = talk["pre"]
	var t0 := float(snap["t"])
	var conv: Dictionary = await k.converse({qid: "complete"})
	d.note("%s turn-in pages: %s" % [qid, " | ".join(conv["pages"])])
	await d.wait(0.3)
	if not quiz.is_empty():
		var ar: Dictionary = (conv["quiz"] as Array)[0] if not (conv["quiz"] as Array).is_empty() else {}
		var right_ok := not ar.is_empty() and bool(ar["correct"]) and String(ar["choice"]) == String(quiz["text"]) \
			and c.quests.is_completed(qid)
		d.check("%s: the canonical answer '%s' (%s) completes the quiz" % [qid, quiz["text"], quiz["basis"]], right_ok,
			"picked %s; shown '%s'" % [ar, String(ar.get("response", "")).left(100)], pq + ["mechanic:quiz-quests"])
		ev["quiz"]["right"] = String(ar.get("choice", ""))
		ev["quiz"]["right_ok"] = right_ok
		ev["quiz"]["basis"] = String(quiz["basis"])
	var done := c.quests.is_completed(qid)
	ev["turn_in"]["completed"] = done
	ev["turn_in"]["level"] = c.level
	ev["turn_in"]["game_s"] = snappedf(d.game_s(), 0.1)
	ev["turn_in"]["phase"] = d.phase
	if not d.check("%s: completed at %s" % [qid, p["end"]["npc_name"]], done, c.quests.status(qid), pq):
		return false
	check_rewards(qid, snap, t0)
	var lines := k.log_since(float(snap["clock"]))
	d.check("%s: the HUD log says 'Quest complete: %s'" % [qid, p["name"]], ("Quest complete: %s" % p["name"]) in lines,
		" / ".join(lines), pq)
	var tab := await k.quest_window(qid, "completed")
	d.check("%s: the Quest Log's Completed tab lists it" % qid, bool(tab["listed"]), "list %s" % [tab["list"]],
		pq + ["mechanic:quest-log"])
	ev["turn_in"]["log_completed"] = bool(tab["listed"])
	await d.close_window("quests")
	return true


## The exact canonical reward: total EXP + rewards.exp (one EXP event, "quest:<id>"), mesos + rewards.mesos, every
## fixed item, exactly one item of each random group, the hand-in items taken, nothing else in the bag.
func check_rewards(qid: String, snap: Dictionary, t0: float) -> void:
	var p := plan(qid)
	var c := d.character()
	var pq := pq_of(qid)
	var rew: Dictionary = p["rewards"]
	var after_snap := k.snapshot()
	var dexp := int(after_snap["total_exp"]) - int(snap["total_exp"])
	var exp_events := k.exp_since(t0)
	var exp_ok := dexp == int(rew["exp"]) and (exp_events.size() == 1 and int(exp_events[0][0]) == int(rew["exp"])
		and String(exp_events[0][1]) == "quest:" + qid if int(rew["exp"]) > 0 else exp_events.is_empty())
	d.check("%s: EXP exactly +%d (canonical rewards.exp)" % [qid, int(rew["exp"])], exp_ok,
		"total EXP %d -> %d (%+d), level %d -> %d, events %s" % [int(snap["total_exp"]), int(after_snap["total_exp"]), dexp,
			int(snap["level"]), int(after_snap["level"]), exp_events], pq)
	var dmesos := int(after_snap["mesos"]) - int(snap["mesos"])
	d.check("%s: mesos exactly +%d (canonical rewards.mesos)" % [qid, int(rew["mesos"])], dmesos == int(rew["mesos"]),
		"%d -> %d" % [int(snap["mesos"]), int(after_snap["mesos"])], pq)
	# Expected bag changes: fixed rewards in, hand-ins out.
	var want := {}
	for it: Dictionary in rew["items"]:
		want[String(it["item_id"])] = int(want.get(String(it["item_id"]), 0)) + int(it["count"])
	for it: Dictionary in p["hand_ins"]:
		var id := String(it["item_id"])
		want[id] = int(want.get(id, 0)) - int(it["count"])
	var delta := PlaytestKit.bag_delta(snap["bag"], after_snap["bag"], [])
	var picks := PackedStringArray()
	var bad := PackedStringArray()
	for group: Variant in rew["random"]:
		var hits := PackedStringArray()
		for id: String in group:
			if int(delta.get(id, 0)) - int(want.get(id, 0)) == 1:
				hits.append(id)
		if hits.size() == 1:
			want[hits[0]] = int(want.get(hits[0], 0)) + 1
			picks.append("%s %s" % [hits[0], k.item_name(hits[0])])
		else:
			bad.append("random group %s gave %s" % [group, hits])
	for id: String in want:
		if int(delta.get(id, 0)) != int(want[id]):
			bad.append("%s %s %+d, expected %+d" % [id, k.item_name(id), int(delta.get(id, 0)), int(want[id])])
	for id: String in delta:
		if not want.has(id):
			bad.append("%s %s %+d unexpected" % [id, k.item_name(id), int(delta[id])])
	d.check("%s: the bag changed by exactly the canonical rewards and hand-ins%s" % [qid,
		(" (random pick: %s)" % ", ".join(picks)) if not picks.is_empty() else ""], bad.is_empty(),
		"; ".join(bad) if not bad.is_empty() else str(delta), pq + (["mechanic:random-quest-rewards"] if not picks.is_empty() else []))
	var items_text := PackedStringArray()
	for id: String in delta:
		items_text.append("%s %s %+d" % [id, k.item_name(id), int(delta[id])])
	var ev := _ev(qid)
	ev["rewards"] = {"exp": dexp, "exp_canonical": int(rew["exp"]), "exp_ok": exp_ok, "mesos": dmesos,
		"mesos_canonical": int(rew["mesos"]), "bag": ", ".join(items_text), "bag_ok": bad.is_empty(),
		"random_pick": ", ".join(picks), "level": "%d -> %d" % [int(snap["level"]), int(after_snap["level"])]}
	if not (rew["random"] as Array).is_empty():
		d.carry["random_%s" % qid] = picks
		var entry: Dictionary = (c.quests.to_dict().get("quests", {}) as Dictionary).get(qid, {})
		if entry.has("rewards_received"):
			var rr: Dictionary = entry["rewards_received"] if entry["rewards_received"] is Dictionary else {}
			var recorded := PackedStringArray()
			for pick: Variant in rr.get("random_picks", []):
				if pick is Dictionary:
					recorded.append(String((pick as Dictionary).get("item_id", "")))
			var rec_ok := picks.size() == recorded.size() and Array(picks).all(func(s: String) -> bool: return recorded.has(s.get_slice(" ", 0)))
			d.check("%s: the quest log records the random pick it granted (C3 rewards_received)" % qid, rec_ok,
				"granted %s, recorded %s" % [picks, recorded], pq + ["mechanic:random-quest-rewards", "mechanic:save-load"])
			ev["rewards"]["rewards_received"] = str(rr)
			ev["rewards"]["rewards_received_ok"] = rec_ok
		else:
			d.soft_check("%s: the quest log records the random pick it granted (C3 rewards_received)" % qid, false,
				"no rewards_received in the quest entry yet (the saves/quests packages add it)", pq)
			ev["rewards"]["rewards_received"] = "(none)"
			ev["rewards"]["rewards_received_ok"] = false
	else:
		var entry2: Dictionary = (c.quests.to_dict().get("quests", {}) as Dictionary).get(qid, {})
		ev["rewards"]["rewards_received"] = str(entry2.get("rewards_received", "(none)"))


# =================================================================================================================
# After the turn-in
# =================================================================================================================

## Follow-up availability: each canonical follow-up is offered now (when the level allows), and its NPC's marker says
## so when the NPC stands in this map.
func after(qid: String) -> void:
	var p := plan(qid)
	var c := d.character()
	var engine := d.game().quests.engine
	var rows: Array = []
	for f in p["followups"]:
		var fp := plan(f)
		var lvl_ok := c.level >= int(fp.get("min_level", 1))
		var avail := engine.is_available(f)
		d.check("%s: its follow-up %s (%s) is %s at level %d" % [qid, f, fp.get("name", ""), "available" if lvl_ok else
			"level-gated", c.level], avail == lvl_ok, "engine %s, min_level %d" % [avail,
			int(fp.get("min_level", 1))], pq_of(qid) + ["quest:" + f])
		var row := {"quest": f, "available": avail, "level": c.level, "min_level": int(fp.get("min_level", 1)), "ok": avail == lvl_ok}
		var npc := String((fp.get("start", {}) as Dictionary).get("npc", ""))
		if lvl_ok and String((fp.get("start", {}) as Dictionary).get("map", "")) == d.current_map():
			var m := await k.marker(npc)
			d.check("%s: %s's marker offers the follow-up %s" % [qid, k.npc_name(npc), f], m["state"] == "available", str(m),
				pq_of(qid) + ["mechanic:quest-indicators"])
			row["marker"] = String(m["state"])
		rows.append(row)
	_ev(qid)["followups"] = rows


# =================================================================================================================
# The mid-quest save and process restart
# =================================================================================================================

func reloaded(qid: String) -> bool:
	return (d.carry.get("reloaded", {}) as Dictionary).has(qid)


func reloaded_once() -> bool:
	return not (d.carry.get("reloaded", {}) as Dictionary).is_empty()


## True when the policy saves and restarts in the middle of `qid` and has not done so yet.
func _may_reload(qid: String) -> bool:
	if reloaded(qid):
		return false
	match mid_reload_policy:
		"auto":
			return true
		"listed":
			return mid_reload_quests.has(qid)
	return false


## The talk-only rule: "auto" restarts after the accept of the run's first talk-only quest only.
func _may_reload_talk_only(qid: String) -> bool:
	if mid_reload_policy == "auto":
		return not reloaded_once()
	return _may_reload(qid)


## A quest with nothing to hunt or collect (talk, quiz, use, or a hand-in of what the accept gave).
func _talk_only(qid: String) -> bool:
	var p := plan(qid)
	return (p["kills"] as Array).is_empty() and (p["items"] as Array).all(func(it: Dictionary) -> bool: return bool(it["from_accept"]))


## Saves through the pause menu, keeps what must survive, and ends the process with Quit Game. The next phase's
## verify_mid() checks it. `qid` "between" (or any non-quest tag) is a save between quests. Never returns.
func mid_reload(qid: String, when: String) -> void:
	var c := d.character()
	var r: Dictionary = d.carry.get("reloaded", {})
	r[qid] = when
	d.carry["reloaded"] = r
	var saved: Dictionary = await d.save_game()
	var is_quest := db.has("quests", qid)
	d.check("%s: saved through the pause menu %s" % [qid, when], bool(saved["ok"]) and saved["via"] == "screen", str(saved),
		pq_of(qid) + ["mechanic:save-load"] if is_quest else ["mechanic:save-load"])
	d.carry["mid"] = {"quest": qid, "when": when, "map": d.current_map(), "level": c.level, "exp": c.exp, "mesos": c.mesos,
		"log": c.quests.to_dict(), "bag": k.snapshot()["bag"]}
	if is_quest:
		_ev(qid)["mid_reload"] = {"when": when, "map": d.current_map(), "phase": d.phase, "saved": bool(saved["ok"])}
	k.checkpoint("before the restart %s" % when)
	k.carry_totals()
	await d.reload_process()


## After a restart: the quest log, level, EXP, mesos, bag and map are the saved ones, and the Quest Log window shows
## the quest at the same progress. Does nothing when the last phase did not end in mid_reload(). Await it.
func verify_mid() -> void:
	var mid: Dictionary = d.carry.get("mid", {})
	if mid.is_empty():
		return
	d.carry.erase("mid")
	var c := d.character()
	var qid := String(mid["quest"])
	var is_quest := db.has("quests", qid)
	var pq := (pq_of(qid) if is_quest else []) + ["mechanic:save-load"]
	var log_diff := PlaytestDriver.diff(mid["log"], c.quests.to_dict())
	d.check("%s: after Quit Game and a new process the quest log is the saved one (%s)" % [qid, mid["when"]], log_diff == "",
		log_diff, pq)
	var bag_diff := PlaytestDriver.diff(mid["bag"], k.snapshot()["bag"])
	var same := c.level == int(mid["level"]) and c.exp == int(mid["exp"]) and c.mesos == int(mid["mesos"]) and bag_diff == ""
	d.check("%s: level, EXP, mesos and the bag survive the restart" % qid, same,
		"level %d/%d exp %d/%d mesos %d/%d bag %s" % [c.level, int(mid["level"]), c.exp, int(mid["exp"]), c.mesos,
			int(mid["mesos"]), bag_diff], pq)
	d.check("%s: Continue resumes in the map it was saved in (%s)" % [qid, mid["map"]], d.current_map() == String(mid["map"]),
		d.current_map(), pq)
	var row_text := ""
	if is_quest and c.quests.is_in_progress(qid):
		var qw := await k.quest_window(qid, "in_progress")
		row_text = PlaytestKit.rows_text(qw["rows"])
		d.check("%s: the Quest Log still lists it In Progress (%s)" % [qid, row_text], bool(qw["listed"]),
			"list %s" % [qw["list"]], pq + ["mechanic:quest-log"])
		await d.close_window("quests")
	if is_quest:
		var mr: Dictionary = _ev(qid).get("mid_reload", {})
		mr["verified"] = log_diff == "" and same and d.current_map() == String(mid["map"])
		mr["log_row_after"] = row_text
		mr["resumed_phase"] = d.phase
		_ev(qid)["mid_reload"] = mr


# =================================================================================================================
# Results and evidence
# =================================================================================================================

## The per-quest verdict into d.carry["quest_results"] (scripts/playtest_quests.sh and the playthrough read it):
## {id: {"result" (PASS | FAIL | NOT_PLAYED), "completed", "checks", "failed" [names], "warnings", "name"}}.
func results(ids: PackedStringArray) -> Dictionary:
	var c := d.character()
	var out := {}
	for qid in ids:
		var key := "quest:" + qid
		var n := 0
		var failed := PackedStringArray()
		var warned := 0
		for ch: Dictionary in d.report.checks:
			if not (ch.get("parity", []) as Array).has(key):
				continue
			n += 1
			if not bool(ch["ok"]):
				if bool(ch.get("soft", false)):
					warned += 1
				else:
					failed.append(String(ch["name"]))
		var done := c.quests.is_completed(qid)
		out[qid] = {"result": "PASS" if done and failed.is_empty() and n > 0 else ("FAIL" if n > 0 else "NOT_PLAYED"),
			"completed": done, "checks": n, "failed": failed, "warnings": warned, "name": String(plan(qid)["name"])}
	d.carry["quest_results"] = out
	for qid: String in out:
		d.note("QUEST %s %s: %s (%d checks, %d failed, %d warnings)" % [qid, out[qid]["name"], out[qid]["result"],
			int(out[qid]["checks"]), (out[qid]["failed"] as PackedStringArray).size(), int(out[qid]["warnings"])])
	return out


## The evidence row of a quest in d.carry["quest_evidence"] (created on first use; survives reloads).
func _ev(qid: String) -> Dictionary:
	var all: Dictionary = d.carry.get("quest_evidence", {})
	if not all.has(qid):
		all[qid] = {"quest": qid, "name": String(plan(qid).get("name", qid))}
	d.carry["quest_evidence"] = all
	return all[qid]


static func pq_of(qid: String) -> Array:
	return ["quest:" + qid]


## Dialogue text compared as the window shows it: whitespace collapsed.
static func same_text(a: String, b: String) -> bool:
	var norm := func(s: String) -> String: return " ".join(s.strip_edges().split(" ", false)).replace("\n", " ")
	return b != "" and String(norm.call(a)) == String(norm.call(b))
