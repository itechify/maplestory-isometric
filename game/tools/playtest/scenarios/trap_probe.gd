extends PlaytestScenario
## trap_probe: is a spot a trap? Places the player at a map-local point (an API teleport: setup for the diagnosis): on
## the old floor when it is still open ground (the live scan has a node at the spot's height), else on the surface a
## falling player lands on over it (a fill, a terrace that now reaches the ground); then tries to get out with real
## input. A try escapes only when it reaches
## the map's main traversal graph: the player stands on ground the stuck-region scan marks escapable (StuckScan, run on
## the live island for that map: from there the player can walk, drop, jump or climb to a portal), stands in a press-Up
## portal trigger, or crosses a trail gate into the next map. Moving along the floor of a pit is not an escape: the old
## rule (4 m of flat distance, or a 1 m rise) passed a 2.5 m deep corner slot in 000001010 (Iteration Three audit).
## A spot whose fix is a way up (a rope, a vine, a stepping stone) rather than a fill also names the height the player
## must climb (`rise`): only escapable ground at least that high above the landing counts, so the probe really climbs.
## Tries: toward the nearest escapable ground the scan knows (high enough), then in 8 directions; each walking and
## hopping, with Up held (re-pressed every 12 frames) so a ladder, rope or vine is grabbed and climbed. The probe of a
## spot stops at the first escape.
## The spot comes from the environment so any finding can be probed without editing the scenario:
##   TRAP_MAP=000001000 TRAP_LOCAL="12.6,0,-33.6" [TRAP_RISE=5.0] bash scripts/playtest.sh trap_probe
## Without TRAP_MAP / TRAP_LOCAL it probes every KNOWN_TRAPS entry: former traps fixed in the Blender source, kept as a
## regression (tests/unit/test_playtest_traps.gd).

## [map, map-local spot, what it was, rise (m, optional)] of every trap the playtests or the stuck-region scan
## (docs/runtime/STUCK_SCAN.md) found and the source world fixed. The spot is where a player landed in the old trap
## (for the scan's finds, the map-local point of the CONFIRMED component in the first full scans); the probe stands on
## whatever surface is over it now.
const KNOWN_TRAPS := [
	["000000050", Vector3(60.8, 0.0, -22.4), "A Split Road: pocket beside T4_Ramp (Iteration Two, fix round F1)"],
	["000001000", Vector3(12.6, 0.0, -33.6), "The Field West of Amherst: gap between P17/P20/P21/P25 (Iteration Two, F1)"],
	# Iteration Three: map-corner slots between the rounded plinth top and the containment ring (world.py corner rule)
	["000000041", Vector3(64.70, -2.32, 0.17), "Snail Hunting Ground II: south-east corner slot (audit, trap_probe FAIL)"],
	["000000041", Vector3(-0.70, -2.54, -44.70), "Snail Hunting Ground II: north-west corner slot"],
	["000000041", Vector3(64.59, -2.39, -44.25), "Snail Hunting Ground II: north-east corner slot (and T0's end)"],
	["000000050", Vector3(-0.66, -2.44, 0.59), "A Split Road: south-west corner slot"],
	["000001000", Vector3(80.70, -2.60, -2.22), "The Field West of Amherst: south-east corner slot beside in03"],
	["000001001", Vector3(-0.37, -2.41, 0.56), "In a Small Forest: south-west corner slot"],
	["000001010", Vector3(76.70, -2.50, -37.57), "Amherst: north-east corner slot (the old rule passed it)"],
	["000001010", Vector3(-0.57, -2.43, 0.70), "Amherst: south-west corner slot"],
	["000001010", Vector3(0.62, -2.69, -39.71), "Amherst: north-west corner slot"],
	["000001010", Vector3(76.59, -2.53, 0.63), "Amherst: south-east corner slot"],
	["000001012", Vector3(24.70, -2.48, 0.63), "Amherst Townstreet: south-east corner slot"],
	["000001012", Vector3(1.85, -2.55, 0.09), "Amherst Townstreet: south-west corner slot"],
	# Iteration Three: plinth-level pockets walled in by terraces (map modules)
	["000000041", Vector3(62.81, 0.0, -34.86), "Snail Hunting Ground II: east slot behind T22 (rope)", 5.0],
	["000000041", Vector3(1.03, 0.0, -31.73), "Snail Hunting Ground II: crack between T23 and T13 (fill)"],
	["000000041", Vector3(37.44, 5.4, -40.50), "Snail Hunting Ground II: notch between the summit, T12 and the arch (fill)"],
	["000000041", Vector3(54.07, 0.0, -30.69), "Snail Hunting Ground II: gap between T31, T22 and T12 (fill)"],
	["000000042", Vector3(38.45, 5.2, -33.53), "Snail Hunting Ground III: courtyard on T15 (stepping stone)", 1.8],
	["000000042", Vector3(11.48, 8.0, -40.72), "Snail Hunting Ground III: pit behind chimney step T5 (fill)"],
	["000000060", Vector3(82.59, 0.0, -46.69), "Southperry: pocket in the ring corner behind the harbour quarter"],
	["000001000", Vector3(72.13, 0.0, -32.45), "The Field West of Amherst: slot between P12 and P26c (fill)"],
	["000001000", Vector3(22.56, 0.0, -38.92), "The Field West of Amherst: pit behind P21 and P24, before P29 (fill)"],
	["000001000", Vector3(29.0, 0.0, -40.6), "The Field West of Amherst: same pit, the harness package's spot (fill)"],
	["000001000", Vector3(62.88, 0.0, -37.75), "The Field West of Amherst: notch by P26b and P26c (fill)"],
	["000001000", Vector3(62.5, 0.0, -37.5), "The Field West of Amherst: same notch, where the harness probe FAILed"],
	["000001000", Vector3(61.99, 0.0, -29.63), "The Field West of Amherst: gap between P08, P11b, P26b and P12 (fill)"],
	["000001001", Vector3(36.53, 0.0, -29.12), "In a Small Forest: strip behind P14 (fill)"],
	["000001002", Vector3(13.61, 7.6, -35.11), "Dangerous Forest: back yard behind the battlements (vine)", 4.0],
	["000001003", Vector3(28.15, 0.0, -25.37), "Mushroom Garden: cavern under the upper terraces (solid now)"],
	["000001003", Vector3(27.12, 5.18, -18.40), "Mushroom Garden: corner of P03 by P07 and P10 (fill)"],
	["000001003", Vector3(26.86, 0.0, -19.86), "Mushroom Garden: the same corner at plinth level (fill)"],
	["000001004", Vector3(23.31, 0.0, -28.12), "Snail Garden: cavern under the summit (solid now)"],
	["000001004", Vector3(0.66, 2.25, -18.35), "Snail Garden: back lane behind the door block (turf step)"],
	["000001004", Vector3(4.07, 2.25, -23.22), "Snail Garden: pocket between T8, T11, T6 and the carrot bed (fill)"],
	["000001004", Vector3(18.69, 0.0, -17.26), "Snail Garden: nook behind the west posts (fill)"],
	["000001004", Vector3(19.47, 0.0, -25.69), "Snail Garden: sliver between the shelf, T9 and the summit (fill)"],
	["000001005", Vector3(18.77, 0.0, -42.60), "Hunting Ground Middle of the Forest I: strip behind the top row"],
	["000001014", Vector3(12.91, 0.0, -20.38), "Snail Field of Flowers: sliver between the knolls (fill)"],
	["000001014", Vector3(0.04, 0.0, -20.38), "Snail Field of Flowers: sliver by the bowl rim under T9 (fill)"],
	["000001014", Vector3(25.04, 0.0, -21.12), "Snail Field of Flowers: sliver by knoll T8 (fill)"],
	["000001020", Vector3(4.81, 0.0, -23.47), "The Field East of Amherst: west hollow behind the plateau (step)"],
	["000001020", Vector3(45.98, 0.0, -22.88), "The Field East of Amherst: hollow by the east plateau (fill)"],
	["000001020", Vector3(13.83, 0.0, -21.47), "The Field East of Amherst: nook between T18, T19 and T13 (fill)"],
	["000001020", Vector3(17.55, 0.0, -28.47), "The Field East of Amherst: strip behind the berry shelf (fill)"],
	["000001020", Vector3(27.62, 0.0, -19.47), "The Field East of Amherst: sliver behind the stepping stones (fill)"],
	# Iteration Three: rooms and shafts the real controller could not get into (UNENTERABLE), closed anyway
	["000000041", Vector3(47.70, 0.0, -20.95), "Snail Hunting Ground II: crevice between T30, T29 and T31 (fill)"],
	["000000042", Vector3(63.69, 0.0, -46.65), "Snail Hunting Ground III: hole in the ring corner under T3 (fill)"],
	["000001004", Vector3(35.44, 0.0, -27.75), "Snail Garden: room under the upper ledges (solid now)"],
	["000001004", Vector3(30.65, 0.0, -26.40), "Snail Garden: slot between stone T7 and ledge T4 (fill)"],
	["000001005", Vector3(27.66, 0.0, -24.93), "Hunting Ground Middle of the Forest I: shaft by the T8/T6 ladder (fill)"],
	# Iteration Three review: traps entered by a running jump the first scanner did not model (fill)
	["000001021", Vector3(-0.67, 1.2, -15.72), "Tomato Field: slot behind the west hedges, by the gate (fill)"],
	["000001021", Vector3(-0.69, 1.2, -16.5), "Tomato Field: slot behind the west hedges (fill)"],
	["000001021", Vector3(-0.57, 1.2, -17.6), "Tomato Field: slot behind the west hedges (fill)"],
]
## Frames of one try, the extra frames a try keeps going while the player climbs, and the settle time before it.
const TRY_FRAMES := 180
const CLIMB_FRAMES := 600
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
		spots.append([OS.get_environment("TRAP_MAP"), Vector3(float(parts[0]), float(parts[1]), float(parts[2])), "TRAP_LOCAL",
			float(OS.get_environment("TRAP_RISE")) if OS.get_environment("TRAP_RISE") != "" else 0.0])
	else:
		spots = KNOWN_TRAPS
	var ng: Dictionary = await d.new_game("Prober", "male", "585", {"str": 9})
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	var graphs := {}
	for entry: Array in spots:
		await _probe(d, String(entry[0]), entry[1] as Vector3, float(entry[3]) if entry.size() > 3 else 0.0, graphs)


func _probe(d: PlaytestDriver, map: String, local: Vector3, rise: float, graphs: Dictionary) -> void:
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
	# Where to stand. When the old trap floor is still open ground (a node of the live graph within SNAP of the spot's
	# height: a pocket whose fix is a way up, or a fix that came undone), on it. Otherwise (the floor is buried in a
	# fill, a terrace that now reaches the ground, the plinth), on the surface a falling player would land on over the
	# spot (the first hit from above), not inside the solid: a filled pocket is then probed from its fill. Landing
	# from above alone would stand on the terrace over a cavern that reopened under it, and pass.
	var open := g.node_near(spot, StuckScan.SNAP_UP_M, StuckScan.SNAP_DOWN_M, 1)
	if open >= 0:
		d.note("the old floor is open ground: probing from local y %.2f (the given spot is local y %.2f)" % [
			def.to_local(g.node_pos[open]).y, local.y])
		spot = g.node_pos[open]
	else:
		var space := p.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 20.0, spot + Vector3.DOWN * 5.0, WorldLayers.PLAYER_MASK, [p.get_rid()])
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			d.note("the old floor is closed; landing surface over the spot: local y %.2f (the given spot is local y %.2f)" % [
				def.to_local(hit.position as Vector3).y, local.y])
			spot = hit.position
	var need_y := spot.y + rise - 0.1 if rise > 0.0 else -INF
	var plans: Array[Dictionary] = []
	for n in scan.nearest_escapable(g, spot, TARGETS, need_y):
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
		var why := _escape(scan, g, p, need_y)
		var f0 := Engine.get_physics_frames()
		# (a climb under way finishes, up to CLIMB_FRAMES: a tall ladder takes longer than a try)
		while why == "" and (Engine.get_physics_frames() - f0 < TRY_FRAMES
				or (p.is_climbing() and Engine.get_physics_frames() - f0 < TRY_FRAMES + CLIMB_FRAMES)):
			var frame := Engine.get_physics_frames() - f0
			var dir: Vector3 = plan.get("dir", Vector3.ZERO)
			if plan.has("to"):
				var to: Vector3 = plan.to
				dir = Vector3(to.x - p.global_position.x, 0.0, to.z - p.global_position.z)
				dir = dir.normalized() if dir.length() > 0.15 else Vector3.ZERO
			# On a ladder or rope only Up is held, as a player climbs: a direction toward the camera would read as
			# Down and cancel the climb.
			if p.is_climbing():
				dir = Vector3.ZERO
			d.input.set_move_world(dir, p.view_right, p.view_forward)
			d.input.set_action_strength(&"jump", 1.0 if bool(plan.jump) and frame > 6 else 0.0)
			d.input.set_action_strength(&"portal_enter", 1.0 if frame % 12 != 0 else 0.0)
			await d.get_tree().process_frame
			d.input.reassert()
			if p.is_grounded():
				best_y = maxf(best_y, p.global_position.y)
			why = _escape(scan, g, p, need_y)
		d.input.release_movement()
		d.input.set_action_strength(&"jump", 0.0)
		d.input.set_action_strength(&"portal_enter", 0.0)
		await d.wait(0.3)
		if why == "":
			why = _escape(scan, g, p, need_y)
		var at := def.to_local(p.global_position)
		d.note("try %d (%s%s): %s, at local (%.2f, %.2f, %.2f)" % [tries, ("toward local %s" % [def.to_local(plan.to)]) if plan.has("to")
			else "direction %s" % [plan.dir], " + jump" if bool(plan.jump) else "", why if why != "" else "still trapped", at.x, at.y, at.z])
		if why != "":
			escaped = why
			break
	var best_local := (best_y - def.frame.origin.y) if best_y > -INF else NAN
	d.check("the spot at local %s in %s is not a trap" % [local, map], escaped != "",
		"%s after %d tries; best grounded local y %.2f%s" % [escaped if escaped != "" else "no try reached escapable ground, a portal or a gate",
			tries, best_local, (", needed %.2f m of climb" % rise) if rise > 0.0 else ""])


## Why the player is out: StuckScan.escape_reason, with escapable ground counted only at or above `need_y` (a spot
## whose fix is a way up must be climbed out of); a portal or a gate always counts.
func _escape(scan: StuckScan, g: StuckScan.MapGraph, p: PlayerController, need_y: float) -> String:
	var why := scan.escape_reason(g, p.global_position, p.is_grounded())
	if why.begins_with("stands on") and p.global_position.y < need_y:
		return ""
	return why
