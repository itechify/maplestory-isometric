extends PlaytestScenario
## trap_probe: is a spot a trap? Places the player on the surface a falling player lands on over a map-local point (an
## API teleport: setup for the diagnosis), then tries to get out with real input. A try escapes only when it reaches
## the map's main traversal graph: the player stands on ground the stuck-region scan marks escapable (StuckScan, run on
## the live island for that map: from there the player can walk, drop, jump or climb to a portal), stands in a press-Up
## portal trigger, or crosses a trail gate into the next map. Moving along the floor of a pit is not an escape: the old
## rule (4 m of flat distance, or a 1 m rise) passed a 2.5 m deep corner slot in 000001010 (Iteration Three audit).
## Tries: toward the nearest escapable ground the scan knows, then in 8 directions; each walking and hopping, with Up
## held so a ladder or rope is grabbed. The probe of a spot stops at the first escape.
## The spot comes from the environment so any finding can be probed without editing the scenario:
##   TRAP_MAP=000001000 TRAP_LOCAL="12.6,0,-33.6" bash scripts/playtest.sh trap_probe
## Without TRAP_MAP / TRAP_LOCAL it probes every KNOWN_TRAPS entry: former traps fixed in the Blender source, kept as a
## regression (tests/unit/test_playtest_traps.gd).

## [map, map-local spot, what it was] of every trap the playtests or the stuck-region scan found and the source world
## fixed. The spot is where a player landed in the old trap; the probe stands on whatever surface is over it now.
const KNOWN_TRAPS := [
	["000000050", Vector3(60.8, 0.0, -22.4), "A Split Road: pocket beside T4_Ramp (Iteration Two, fix round F1)"],
	["000001000", Vector3(12.6, 0.0, -33.6), "The Field West of Amherst: gap between P17/P20/P21/P25 (Iteration Two, F1)"],
]
## Frames of one try, and the settle time before it.
const TRY_FRAMES := 150
const SETTLE_S := 0.5
## Escapable targets tried first (the scan's nearest, in different directions).
const TARGETS := 3


func description() -> String:
	return "probe a map-local spot for a trap (TRAP_MAP, TRAP_LOCAL); escape = reach the main traversal graph"


func max_seconds() -> float:
	return 120.0 + 100.0 * KNOWN_TRAPS.size()


func run(d: PlaytestDriver) -> void:
	var spots: Array = []
	var parts := OS.get_environment("TRAP_LOCAL").split(",")
	if OS.get_environment("TRAP_MAP") != "" and parts.size() == 3:
		spots.append([OS.get_environment("TRAP_MAP"), Vector3(float(parts[0]), float(parts[1]), float(parts[2])), "TRAP_LOCAL"])
	else:
		spots = KNOWN_TRAPS
	var ng: Dictionary = await d.new_game("Prober", "male", "585", {"str": 9})
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	var graphs := {}
	for entry: Array in spots:
		await _probe(d, String(entry[0]), entry[1] as Vector3, graphs)


func _probe(d: PlaytestDriver, map: String, local: Vector3, graphs: Dictionary) -> void:
	await d.console("warp " + map)
	await d.console("god on")
	var p := d.player()
	var w := d.world()
	var def := w.defs.get_def(map)
	# The map's walkability graph on the live island (the player's own body excluded from the queries).
	var scan := StuckScan.create(w, d.db(), {"exclude": [p.get_rid()]})
	if not graphs.has(map):
		var t0 := Time.get_ticks_msec()
		graphs[map] = scan.scan_map(map)
		var st: Dictionary = (graphs[map] as StuckScan.MapGraph).stats
		d.note("stuck scan of %s: %d nodes, %d escapable, %d flagged in %d components (%d ms)" % [map, int(st.nodes),
			int(st.escapable), int(st.flagged), int(st.components), Time.get_ticks_msec() - t0])
	var g: StuckScan.MapGraph = graphs[map]
	var spot := def.to_world(local)
	# Stand on the surface a falling player would land on (the first hit from above), not inside whatever solid now
	# fills the old floor: a filled pocket is then probed from its fill.
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 20.0, spot + Vector3.DOWN * 5.0, WorldLayers.PLAYER_MASK, [p.get_rid()])
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		d.note("landing surface over the spot: local y %.2f (the given spot is local y %.2f)" % [
			def.to_local(hit.position as Vector3).y, local.y])
		spot = hit.position
	var plans: Array[Dictionary] = []
	for n in scan.nearest_escapable(g, spot, TARGETS):
		plans.append({"to": g.node_pos[n], "jump": false})
		plans.append({"to": g.node_pos[n], "jump": true})
	for k in 8:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(45.0 * k))
		plans.append({"dir": dir, "jump": false})
		plans.append({"dir": dir, "jump": true})
	var escaped := ""
	var best_y := -INF
	var tries := 0
	for plan in plans:
		tries += 1
		w.place_player(Transform3D(p.global_transform.basis, spot + Vector3.UP * 0.05))
		await d.wait(SETTLE_S)
		var why := scan.escape_reason(g, p.global_position, p.is_grounded())
		var f0 := Engine.get_physics_frames()
		while why == "" and Engine.get_physics_frames() - f0 < TRY_FRAMES:
			var dir: Vector3 = plan.get("dir", Vector3.ZERO)
			if plan.has("to"):
				var to: Vector3 = plan.to
				dir = Vector3(to.x - p.global_position.x, 0.0, to.z - p.global_position.z)
				dir = dir.normalized() if dir.length() > 0.15 else Vector3.ZERO
			d.input.set_move_world(dir, p.view_right, p.view_forward)
			d.input.set_action_strength(&"jump", 1.0 if bool(plan.jump) and Engine.get_physics_frames() - f0 > 6 else 0.0)
			await d.get_tree().process_frame
			d.input.reassert()
			if p.is_grounded():
				best_y = maxf(best_y, p.global_position.y)
			why = scan.escape_reason(g, p.global_position, p.is_grounded())
		d.input.release_movement()
		d.input.set_action_strength(&"jump", 0.0)
		await d.wait(0.3)
		if why == "":
			why = scan.escape_reason(g, p.global_position, p.is_grounded())
		var at := def.to_local(p.global_position)
		d.note("try %d (%s%s): %s, at local (%.2f, %.2f, %.2f)" % [tries, ("toward local %s" % [def.to_local(plan.to)]) if plan.has("to")
			else "direction %s" % [plan.dir], " + jump" if bool(plan.jump) else "", why if why != "" else "still trapped", at.x, at.y, at.z])
		if why != "":
			escaped = why
			break
	var best_local := (best_y - def.frame.origin.y) if best_y > -INF else NAN
	d.check("the spot at local %s in %s is not a trap" % [local, map], escaped != "",
		"%s after %d tries; best grounded local y %.2f" % [escaped if escaped != "" else "no try reached escapable ground, a portal or a gate", tries, best_local])
