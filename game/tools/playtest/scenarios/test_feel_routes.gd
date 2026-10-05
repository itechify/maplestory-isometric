extends PlaytestScenario
## test_feel_routes: the Movement and Camera Reviews over every exported route of the 25 maps, walked with real input.
## Setup (console, counted apart): `god on` (no contact damage, so no knockback in the counts) and one `warp` per map.
## Play: for each route, walk_to its start (the map's routes, then the grid planner), then walk_route along it.
## A Sampler (test_feel_common.gd) reads every physics tick and counts, per route:
##   movement  snags (input held, grounded, speed < 50% of walk for >= 0.15 s), deflections (moving > 0.3 m/s at
##             > 25 deg from the input for >= 0.15 s: sliding along clutter), walk-off drops and their height,
##             step-ups, slope speed, RouteBot jumps and climbs, ladder/rope exits;
##   camera    the player inside the play rect (viewport minus the HUD status bar), fully visible (in frame and not
##             occluded: CameraRig.player_occluded(): a faded occluder over the body or terrain on a ray to the camera),
##             off-centre, bounds clamping, follow lag, pops and jerks; monsters within 8 m (and 8-12 m) in frame or
##             hidden by terrain (two rays toward the camera, as CameraRig.terrain_hides).
## Run it windowed (1600x900): headless the viewport is 1600x1600, so the camera numbers would not be the game's.
## FEEL_MAPS="000000040,000000041" (environment) limits the maps. Results: notes, and <out>/feel_routes.json.

const Lib := preload("res://tools/playtest/scenarios/test_feel_common.gd")

var S: Lib.Sampler = null
var rows: Array = []
var maps_out: Dictionary = {}


func description() -> String:
	return "every route of every map walked with real input: snags, deflections, drops, steps, climbs; camera framing, occlusion, monsters in frame"


func max_seconds() -> float:
	return 6500.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Routes", "female", "541", {})
	if not d.check("new game through the title and creation screens", bool(ng["ok"]), String(ng["why"])):
		return
	S = Lib.Sampler.new()
	S.setup(d)
	d.add_child(S)
	await d.console("god on")
	var maps := Array(d.world().defs.ids())
	maps.sort()
	var env := OS.get_environment("FEEL_MAPS")
	if env != "":
		maps = Array(env.split(","))
	d.note("maps: %s; viewport %s; play rect %s" % [",".join(maps), str(d.get_viewport().get_visible_rect().size), str(Lib.Util.play_rect(d))])
	var walked := 0
	var total := 0
	for map_id: String in maps:
		if d.current_map() != map_id:
			await d.console("warp %s" % map_id)
		await d.wait_idle()
		await d.wait(0.5)
		if not d.check("in %s" % map_id, d.current_map() == map_id, d.current_map()):
			continue
		var def := d.world().defs.get_def(map_id)
		var segs: Array = []
		var approaches: Array = []
		var route_list: Array = def.sidecar.get("routes", [])
		var map_ok := 0
		for r: Dictionary in route_list:
			var rn := String(r.get("name", ""))
			total += 1
			var row := await _walk_one(d, map_id, rn)
			rows.append(row)
			segs.append(row["seg"])
			approaches.append(row["aseg"])
			if bool(row["ok"]):
				walked += 1
				map_ok += 1
			_save(d)
		var m := Lib.Sampler.merge(map_id, segs)
		m["map"] = map_id
		# Off the routes: the grid planner (A* on the real collision) to three monster slots, as a player cuts
		# across a field instead of following the exported walkways.
		var off: Array = []
		var slots: Array = def.monster_spawn_definitions
		if slots.size() >= 2:
			# From one slot, on foot (routes, then the grid), to up to three others on the same tier 5-15 m away,
			# with the grid planner only: the field walking a player does between monsters.
			var a_idx := slots.size() / 2
			var a_pos: Vector3 = (slots[a_idx] as SpawnSlot).transform.origin
			var reach: Dictionary = await d.walk_to("slot:%d" % a_idx, {"max_s": 60.0})
			var near: Array = []
			for k in slots.size():
				var q: Vector3 = (slots[k] as SpawnSlot).transform.origin
				var dd := Vector2(q.x - a_pos.x, q.z - a_pos.z).length()
				if k != a_idx and absf(q.y - a_pos.y) < 0.5 and dd >= 5.0 and dd <= 15.0:
					near.append(k)
			if not bool(reach.get("ok", false)):
				d.note("OFFROUTE %s: slot %d not reached on foot (%s)" % [map_id, a_idx, reach.get("result", "?")])
				near.clear()
			var walked_off := 0
			for k: int in near:
				if walked_off >= 3:
					break
				var tgt := d.resolve_target("slot:%d" % k)
				var pl: Dictionary = d.walker.plan(tgt["position"], "grid")
				if String(pl["how"]) != "grid":
					continue
				walked_off += 1
				S.begin("%s slot %d (grid)" % [map_id, k])
				var g: Dictionary = await d.walk_to("slot:%d" % k, {"planner": "grid", "max_s": 30.0, "retries": 0})
				var gs := S.end()
				gs["walk"] = "%s via %s, %.1f s, %.1f m" % [g.get("result", "?"), g.get("how", "?"), float(g.get("time_s", 0.0)), float(g.get("distance_m", 0.0))]
				off.append(gs)
				d.note("OFFROUTE %s slot %d -> %d: %s | %s" % [map_id, a_idx, k, gs["walk"], Lib.Sampler.move_text(gs)])
				if not bool(g.get("ok", false)):
					await d.walk_to("slot:%d" % a_idx, {"max_s": 30.0})
		var offm := Lib.Sampler.merge(map_id + " off-route", off)
		var appm := Lib.Sampler.merge(map_id + " approaches", approaches)
		maps_out[map_id] = {"routes": route_list.size(), "ok": map_ok, "seg": m, "offroute": offm, "approaches": appm, "view_m": snappedf((d.ctx().camera as CameraRig).ortho_size, 0.01),
			"name": String(d.db().map(map_id).get("name", ""))}
		d.note("MAP %s %s (%d/%d routes walked, view %.1f m) MOVE %s" % [map_id, maps_out[map_id]["name"], map_ok, route_list.size(),
			float(maps_out[map_id]["view_m"]), Lib.Sampler.move_text(m)])
		d.note("MAP %s CAMERA %s" % [map_id, Lib.Sampler.camera_text(m)])
		d.note("MAP %s APPROACHES %s" % [map_id, Lib.Sampler.move_text(appm)])
		d.note("MAP %s OFFROUTE %s" % [map_id, Lib.Sampler.move_text(offm)])
		_save(d)
	var all := Lib.Sampler.merge("all maps", maps_out.values().map(func(x: Dictionary) -> Dictionary: return x["seg"]))
	d.note("ALL MOVE %s" % Lib.Sampler.move_text(all))
	d.note("ALL CAMERA %s" % Lib.Sampler.camera_text(all))
	var all_app := Lib.Sampler.merge("all approaches", maps_out.values().map(func(x: Dictionary) -> Dictionary: return x["approaches"]))
	var all_off := Lib.Sampler.merge("all off-route", maps_out.values().map(func(x: Dictionary) -> Dictionary: return x["offroute"]))
	d.note("ALL APPROACHES %s" % Lib.Sampler.move_text(all_app))
	d.note("ALL APPROACHES CAMERA %s" % Lib.Sampler.camera_text(all_app))
	d.note("ALL OFFROUTE %s" % Lib.Sampler.move_text(all_off))
	d.check("walked every route of every map (%d of %d)" % [walked, total], walked == total, _failed_text())
	var ct := maxi(1, int(all["cam_ticks"]))
	d.soft_check("the player is inside the play rect on every camera tick (%.2f%%)" % (100.0 * int(all["cam_in_frame"]) / ct),
		int(all["cam_in_frame"]) == ct, str(all["cam_out_where"]))
	d.soft_check("no snags on any route (%d)" % int(all["snags"]), int(all["snags"]) == 0, str(all["snag_where"]))
	d.soft_check("no camera pops outside transitions (%d)" % int(all["cam_pops"]), int(all["cam_pops"]) == 0)
	_save(d)


## Walks to the start of `route` and along it; returns the row (with the route's Sampler segment).
func _walk_one(d: PlaytestDriver, map_id: String, route: String) -> Dictionary:
	var row := {"map": map_id, "route": route, "ok": false, "approach": "", "setup_goto": false}
	S.begin("%s %s approach" % [map_id, route])
	var a: Dictionary = await d.walk_to("route:%s" % route, {"max_s": 60.0})
	var aseg := S.end()
	row["approach"] = "%s via %s, %.1f s" % [a.get("result", "?"), a.get("how", "?"), float(a.get("time_s", 0.0))]
	row["approach_snags"] = int(aseg["snags"])
	row["approach_deflects"] = int(aseg["deflects"])
	row["aseg"] = aseg
	if not bool(a.get("ok", false)):
		# Setup: the route's start could not be reached on foot from where the last route ended.
		var pts := d.route_points(map_id, route)
		if not pts.is_empty():
			await d.console("goto %.3f %.3f" % [pts[0].x, pts[0].z])
			row["setup_goto"] = true
	if d.current_map() != map_id:
		await d.console("warp %s" % map_id)
		var pts2 := d.route_points(map_id, route)
		if not pts2.is_empty():
			await d.console("goto %.3f %.3f" % [pts2[0].x, pts2[0].z])
		row["setup_goto"] = true
	S.begin("%s %s" % [map_id, route])
	var w: Dictionary = await d.walk_route(map_id, route)
	var seg := S.end()
	row["ok"] = bool(w["ok"])
	row["time_s"] = float(w.get("time_s", 0.0))
	row["distance_m"] = float(w.get("distance_m", 0.0))
	row["issues"] = "; ".join(PackedStringArray(w.get("issues", PackedStringArray())))
	var legs: Array = w.get("legs", [])
	var rep := String((legs[legs.size() - 1] as Dictionary).get("report", "")) if not legs.is_empty() else ""
	row["bot"] = rep
	row["bot_jumps"] = _field(rep, "jumps")
	row["bot_climbs"] = _field(rep, "climbs")
	row["result"] = String((legs[legs.size() - 1] as Dictionary).get("result", "")) if not legs.is_empty() else "NONE"
	row["seg"] = seg
	if not bool(row["ok"]) or int(seg["snags"]) > 0 or int(seg["deflects"]) > 0 or int(seg["drops"]) > 0:
		d.note("ROUTE %s %s: %s | %s | %s" % [map_id, route, row["result"], row["issues"], Lib.Sampler.move_text(seg)])
	return row


static func _field(rep: String, key: String) -> int:
	var at := rep.find(key + "=")
	if at < 0:
		return -1
	return int(rep.substr(at + key.length() + 1).get_slice(" ", 0))


func _failed_text() -> String:
	var parts := PackedStringArray()
	for r: Dictionary in rows:
		if not bool(r["ok"]):
			parts.append("%s %s (%s: %s)" % [r["map"], r["route"], r.get("result", ""), r.get("issues", "")])
	return "; ".join(parts)


func _save(d: PlaytestDriver) -> void:
	var path := d.out_dir.path_join("feel_routes.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_jsonable({"maps": maps_out, "routes": rows}), " "))
		f.close()


static func _jsonable(v: Variant) -> Variant:
	if v is Dictionary:
		var o := {}
		for k: Variant in v:
			o[str(k)] = _jsonable(v[k])
		return o
	if v is Array:
		var a := []
		for e: Variant in v:
			a.append(_jsonable(e))
		return a
	if v is Vector3 or v is Vector2:
		return str(v)
	if v is float and (is_inf(v) or is_nan(v)):
		return str(v)
	return v
