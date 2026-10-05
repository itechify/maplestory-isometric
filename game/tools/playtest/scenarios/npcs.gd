extends PlaytestScenario
## npcs: every NPC of the island is talked to on foot (brief Phase 14: approach an NPC, see the interaction cue, press
## interact). For each NPC, sorted by map id: a console warp to its map (setup), then talk_to() from the map's arrival
## with real input, over the exported routes (stairs, ladders) and the grid planner, and the interact key; the
## conversation must open (a hard check). Then the margin: with the window closed, the player presses on toward the NPC
## with real movement input, as a player pressing into a counter, and the body must end at least MIN_MARGIN_M inside
## the talk zone (talk_gap <= -MIN_MARGIN_M) with the prompt still offering that NPC. The margins are logged in the
## notes. A test runs it: tests/unit/test_npc_reach_scenario.gd.

## How far inside the talk zone a player pressing toward the NPC must get (m): a talk zone that only touches the body
## at the closest standing point is not one a player finds (docs/runtime/WORLD_RUNTIME.md "NPC talk zones").
const MIN_MARGIN_M := 0.4
## The press toward the NPC: at most PRESS_S of game time, ended early after PRESS_STALL_S without getting closer.
const PRESS_S := 1.5
const PRESS_STALL_S := 0.5


func description() -> String:
	return "talk to every NPC of the island on foot from its map's arrival, then press on toward it: at least %.1f m inside its talk zone" % MIN_MARGIN_M


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
	var margins := {}  # npc id -> the margin record (report.json carry.npc_margins)
	for map_id: String in maps:
		var ids: Array = by_map[map_id]
		ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
		for npc_id: String in ids:
			total += 1
			await d.console("warp " + map_id)
			var npc := w.npc_nodes[npc_id] as WorldNpc
			var npc_name := String(d.db().npc(npc_id).get("name", npc_id))
			var label := "%s (%s)" % [npc_name, npc_id]
			var v: Dictionary = await d.talk_to(npc_id)
			var open := bool(v["open"])
			var details := "" if open else "the body came within %.2f m of the talk zone" % float(v.get("talk_gap", -1.0))
			if not d.check("%s can be talked to on foot in %s" % [label, map_id], open, details):
				margins[npc_id] = {"reached": false, "short_m": snappedf(float(v.get("talk_gap", -1.0)), 0.001)}
				continue
			reached += 1
			var at_talk := d.talk_gap(npc, d.player().global_position)
			var props := int(v.get("reached_over_props", 0))
			if props > 0:
				d.note("%s in %s was reached over %d prop-top cells (jumping onto scenery)" % [label, map_id, props])
			if bool(v.get("leaned", false)):
				d.note("%s in %s was reached by leaning in (pressing into the scenery between)" % [label, map_id])
			d.check("%s's conversation closes" % npc_name, await d.close_dialogue())
			var pressed: Dictionary = await _press_toward(d, npc)
			var gap := float(pressed["gap"])
			d.note("margin %s %s: talk_gap %+.2f m when the prompt appeared, %+.2f m pressed in (feet %.2f m from the NPC, zone %s, r %.1f m)" % [
				label, map_id, at_talk, gap, float(pressed["feet_m"]), npc.talk_profile, npc.talk_radius_m])
			margins[npc_id] = {"reached": true, "at_prompt_m": snappedf(at_talk, 0.001), "pressed_m": snappedf(gap, 0.001),
				"feet_m": snappedf(float(pressed["feet_m"]), 0.001), "profile": npc.talk_profile}
			d.check("%s: a player pressing on is at least %.1f m inside the talk zone" % [label, MIN_MARGIN_M],
				gap <= -MIN_MARGIN_M and bool(pressed["prompt"]),
				"%+.2f m (talk_gap), prompt %s" % [gap, "offers the NPC" if bool(pressed["prompt"]) else "gone"])
	d.carry["npc_margins"] = margins
	d.note("%d of %d NPCs reached on foot (the margin notes: talk_gap, <= 0 inside the zone; report.json carry.npc_margins)" % [
		reached, total])
	d.check("every NPC was talked to on foot", reached == total, "%d of %d" % [reached, total])
	d.check("the survey covered every NPC", total == w.npc_nodes.size(), "%d of %d" % [total, w.npc_nodes.size()])


## Holds real movement input straight at `npc` (as a player pressing toward it, into a counter) for at most PRESS_S,
## ended after PRESS_STALL_S without getting closer or when the feet are within 0.3 m of the NPC's. Measured where the
## player comes to rest: {"gap" (talk_gap there), "best" (the smallest talk_gap on the way), "feet_m" (horizontal feet
## distance to the NPC), "prompt" (the interaction prompt offers this NPC)}.
func _press_toward(d: PlaytestDriver, npc: WorldNpc) -> Dictionary:
	var p := d.player()
	var tps := Engine.physics_ticks_per_second
	var f0 := Engine.get_physics_frames()
	var last_gain := f0
	var best := d.talk_gap(npc, p.global_position)
	while Engine.get_physics_frames() - f0 < roundi(PRESS_S * tps) and Engine.get_physics_frames() - last_gain < roundi(PRESS_STALL_S * tps):
		var to := _flat(npc.global_position - p.global_position)
		if to.length() < 0.3 or p.is_dead() or not bool(d.session().call("is_idle")):
			break
		d.input.set_move_world(to.normalized(), p.view_right, p.view_forward)
		await d.get_tree().process_frame
		d.input.reassert()
		var g := d.talk_gap(npc, p.global_position)
		if g < best - 0.005:
			best = g
			last_gain = Engine.get_physics_frames()
	d.input.release_movement()
	await d.get_tree().physics_frame
	await d.wait(0.2)
	var cur: Dictionary = d.interaction().get("current") if d.interaction() != null else {}
	var prompt := String(cur.get("kind", "")) == "npc" and String(cur.get("target_id", "")) == npc.npc_id()
	return {"gap": d.talk_gap(npc, p.global_position), "best": minf(best, d.talk_gap(npc, p.global_position)),
		"feet_m": _flat(npc.global_position - p.global_position).length(), "prompt": prompt}


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
