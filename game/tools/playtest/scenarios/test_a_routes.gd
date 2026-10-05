extends PlaytestScenario
## test_a_routes (play-A): brief Test A "verify every route", the Iteration One routes of all 25 maps walked with
## real input. For each map (sorted by id) a console warp to the map's spawn is the setup; then every exported route
## of the map's sidecar is walked with walk_route (to its start over the routes or the grid, then along it). Each
## route is a soft check (a bad route never stops the survey) with its time, distance and issues as a note; the run
## fails only if a route could not be attempted. A walk that fails leaves the walker where it stopped, so the next
## route starts with a warp back to the map's spawn (setup). God mode is on (setup): this survey is about the world's
## walkways, and test_a_traversal measures what monsters do to a walk.
##
## Env options: PLAYA_MAPS=<id,id,...> limits the maps; PLAYA_REVERSE=1 also walks every two-way route end to start.


func description() -> String:
	return "Test A routes: every exported Iteration One route of the 25 maps walked with real input"


func max_seconds() -> float:
	return 9000.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Surveyor", "female")
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	await d.console("god on")
	var w := d.world()
	var maps := PackedStringArray()
	for f in DirAccess.get_files_at("res://data/canonical/maps"):
		if f.ends_with(".json"):
			maps.append(f.get_basename())
	maps.sort()
	var only := OS.get_environment("PLAYA_MAPS")
	var reverse_too := OS.get_environment("PLAYA_REVERSE") == "1"
	var total := 0
	var walked := 0
	var attempted := 0
	var per_map := {}
	var rows: Array = []
	for map_id in maps:
		if only != "" and not (map_id in only.split(",")):
			continue
		var def := w.defs.get_def(map_id)
		var routes: Array = def.sidecar.get("routes", [])
		var ok_n := 0
		var t_sum := 0.0
		var m_sum := 0.0
		await d.console("warp " + map_id)
		var dirty := false
		for r: Variant in routes:
			var rn := String((r as Dictionary).get("name", ""))
			var dirs: Array = [false]
			if reverse_too and not d.route_is_one_way(map_id, rn):
				dirs.append(true)
			for rev: bool in dirs:
				total += 1
				if dirty or d.current_map() != map_id:
					# A walk that crossed a gate may still be settling: wait for IDLE, then warp (setup), twice at most.
					for _k in 2:
						await d.wait_idle(10.0)
						await d.console("warp " + map_id)
						await d.wait_idle(10.0)
						if d.current_map() == map_id:
							break
					dirty = false
				if d.current_map() != map_id:
					continue
				attempted += 1
				# Diagnostic: does the planned path to the route's start (or the route itself) leave the map's region?
				var pts := d.route_points(map_id, rn)
				var start: Vector3 = pts[pts.size() - 1] if rev else pts[0]
				var plan: Dictionary = d.walker.plan(start)
				var outside := PackedStringArray()
				for set_name: String in ["plan", "route"]:
					var arr: PackedVector3Array = plan["path"] if set_name == "plan" else pts
					for q in arr:
						var reg: Dictionary = w.region_index.region_of(q, map_id)
						if String(reg.get("kind", "")) != "map" or String(reg.get("id", "")) != map_id:
							outside.append("%s (%.1f, %.1f, %.1f) in %s %s" % [set_name, q.x, q.y, q.z, reg.get("kind", ""), reg.get("id", "")])
				if not outside.is_empty():
					d.note("ROUTE %s %s: %d planned/route points outside %s's region, first: %s" % [map_id, rn, outside.size(), map_id,
						"; ".join(outside.slice(0, 3))])
				var res: Dictionary = await d.walk_route(map_id, rn, {"reverse": rev, "max_s": 150.0})
				var legs: Array = res.get("legs", [])
				var approach: Dictionary = legs[0] if legs.size() >= 1 else {}
				var along: Dictionary = legs[1] if legs.size() >= 2 else {}
				var ok := bool(res.get("ok", false))
				var label := "%s %s%s" % [map_id, rn, " (reverse)" if rev else ""]
				var row := {"map": map_id, "route": rn, "reverse": rev, "ok": ok,
					"points": d.route_points(map_id, rn).size(), "one_way": d.route_is_one_way(map_id, rn),
					"approach_s": float(approach.get("time_s", 0.0)), "approach_how": String(approach.get("how", "")),
					"approach_props": int(approach.get("props", 0)),
					"along_s": float(along.get("time_s", 0.0)), "along_m": float(along.get("distance_m", 0.0)),
					"along_result": String(along.get("result", "")), "issues": Array(res.get("issues", PackedStringArray()))}
				rows.append(row)
				d.soft_check("route %s walks end to end" % label, ok, "; ".join(res.get("issues", PackedStringArray())))
				d.note("ROUTE %s %s: start via %s %.1f s%s; along %.1f s / %.1f m (%s)%s" % [label, "ok" if ok else "FAIL",
					row["approach_how"], row["approach_s"], (" over %d prop cells" % row["approach_props"]) if int(row["approach_props"]) > 0 else "",
					row["along_s"], row["along_m"], row["along_result"],
					"" if ok else "; " + "; ".join(res.get("issues", PackedStringArray()))])
				if ok:
					walked += 1
					ok_n += 1
					t_sum += float(row["along_s"])
					m_sum += float(row["along_m"])
				else:
					dirty = true
					var s := d.state()
					var at: Vector3 = s.get("position", Vector3.ZERO)
					d.note("ROUTE %s stopped in %s at (%.2f, %.2f, %.2f), region %s, on_floor %s, last transition %s; the route starts at %s" % [label,
						d.current_map(), at.x, at.y, at.z, str(s.get("region", {})), str(s.get("on_floor", false)), str(s.get("last_transition", {})),
						str(d.route_points(map_id, rn)[0] if not rev else d.route_points(map_id, rn)[d.route_points(map_id, rn).size() - 1])])
					await d.screenshot("route_fail_%s_%s%s" % [map_id, rn, "_rev" if rev else ""])
		per_map[map_id] = {"routes": routes.size(), "ok": ok_n, "along_s": snappedf(t_sum, 0.1), "along_m": snappedf(m_sum, 0.1)}
		d.note("MAP %s: %d of %d route walks ok, %.1f s / %.1f m along the routes" % [map_id, ok_n, routes.size() * (2 if reverse_too else 1), t_sum, m_sum])
	d.check("every route was attempted (%d of %d)" % [attempted, total], attempted == total)
	d.note("ROUTES %d of %d walked end to end" % [walked, total])
	d.carry["routes"] = rows
	d.carry["per_map"] = per_map
