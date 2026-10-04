extends PlaytestScenario
## npcs: a reachability survey (a world review, not a brief test). For every NPC of the 25 maps: a console warp to
## its map (setup), then talk_to() on foot from the map's arrival, over the routes and the grid planner. Each NPC is a
## soft check, so the report lists the ones a player cannot talk to (WARN) without failing; the run fails only if a
## conversation that was reached does not open. Sorted by map id.


func description() -> String:
	return "talk to every NPC of the island on foot from its map's arrival; the unreachable ones are WARN lines"


func max_seconds() -> float:
	return 1800.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Surveyor", "female")
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	var w := d.world()
	var by_map := {}
	for npc_id: String in w.npc_nodes:
		var m := String((w.npc_nodes[npc_id] as Node).call("map_id"))
		if not by_map.has(m):
			by_map[m] = []
		(by_map[m] as Array).append(npc_id)
	var maps := by_map.keys()
	maps.sort()
	var reached := 0
	var total := 0
	for map_id: String in maps:
		var ids: Array = by_map[map_id]
		ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
		for npc_id: String in ids:
			total += 1
			await d.console("warp " + map_id)
			var npc_name := String(d.db().npc(npc_id).get("name", npc_id)) if d.db().has_method("npc") else npc_id
			var v: Dictionary = await d.talk_to(npc_id)
			var details := "" if bool(v["open"]) else "the body came within %.2f m of the talk zone" % float(v.get("talk_gap", -1.0))
			if d.soft_check("%s (%s) can be talked to on foot in %s" % [npc_name, npc_id, map_id], bool(v["open"]), details):
				reached += 1
				var props := int(v.get("reached_over_props", 0))
				if props > 0:
					d.note("%s (%s) in %s was reached over %d prop-top cells (jumping onto scenery)" % [npc_name, npc_id, map_id, props])
				if bool(v.get("leaned", false)):
					d.note("%s (%s) in %s was reached by leaning in (pressing into the scenery between)" % [npc_name, npc_id, map_id])
				d.check("%s's conversation closes" % npc_name, await d.close_dialogue())
	d.note("%d of %d NPCs reached on foot" % [reached, total])
	d.check("the survey covered every NPC", total == w.npc_nodes.size(), "%d of %d" % [total, w.npc_nodes.size()])
