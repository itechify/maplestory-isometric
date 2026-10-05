extends PlaytestScenario
## test_feel_camera: the brief's Camera Review in the real game, windowed (1600x900), with real input. Setup (console,
## counted apart): `level 30` so a walk through hunting grounds survives contact damage with god mode off (god mode
## blinks the player, which would hide it in frames), and one `warp` per stop. Play:
##   1. trail     walk_trail 000000040 -> 000000041 (M2 edge mode): framing on the trail, the gate commit (view size,
##                the player's jump on screen, the camera blend), frames across the gate;
##   2. door      Southperry -> the Armor Store and back out with Up: transition time, framing on arrival, frames;
##   3. edges     four outer maps: walk to the route point nearest a footprint corner, a full frame each (void,
##                missing backsides, holes), the bounds clamp and the player's place on screen;
##   4. canopy    Dangerous Forest routes: frames whenever a faded occluder or terrain covers the player;
##   5. cliffs    hunting-ground routes: frames whenever terrain hides a monster within 8 m (CameraRig has no monster
##                X-ray), with the monster and where.
## The Sampler (test_feel_common.gd) measures every tick. Results: notes, sheets in <out>/shots, <out>/feel_camera.json.

const Lib := preload("res://tools/playtest/scenarios/test_feel_common.gd")
const TPS := 60.0

var S: Lib.Sampler = null
var results: Dictionary = {}


func description() -> String:
	return "Camera Review: trail framing and gate commit, door transition, map edges, canopy occlusion, cliffs hiding monsters (windowed)"


func max_seconds() -> float:
	return 2400.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Camera", "female", "541", {})
	if not d.check("new game through the title and creation screens", bool(ng["ok"]), String(ng["why"])):
		return
	S = Lib.Sampler.new()
	S.setup(d)
	d.add_child(S)
	await d.console("level 30")
	await d.console("heal")
	# FEEL_CAMERA_PARTS="cliffs,snags" (environment) runs only those parts; default: all.
	var parts := OS.get_environment("FEEL_CAMERA_PARTS")
	var all := parts == ""
	if all or parts.contains("trail"):
		await _trail(d)
	if all or parts.contains("door"):
		await _door(d)
	if all or parts.contains("edges"):
		await _edges(d)
	if all or parts.contains("canopy"):
		await _canopy(d)
	if all or parts.contains("cliffs"):
		await _cliffs(d)
	if all or parts.contains("snags"):
		await _snags(d)
	var path := d.out_dir.path_join("feel_camera.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_jsonable(results), " "))
		f.close()
	d.note("results: %s" % path)


# =================================================================================================================
# 1. Trail and gate
# =================================================================================================================

func _trail(d: PlaytestDriver) -> void:
	var from := "000000040"
	var to := "000000041"
	await d.console("warp %s" % from)
	await d.wait(0.5)
	var p := d.player()
	var w := d.world()
	var src := TraversalTour.portal_between(w.defs, from, to)
	var t := w.defs.trail(src.link_id) if src != null else null
	var trail_len := t.length() if t != null else 30.0
	# Walk to the portal first (not the trail), so the frames cover the trail itself.
	await d.walk_to(src.anchor_ground, {"max_s": 60.0})
	var src_def := w.defs.get_def(from)
	var every := maxi(10, int(trail_len / 3.0 * TPS / 6.0))
	S.start_capture(every, 6, 0)
	S.rows.clear()
	S.record = true
	S.begin("trail %s -> %s" % [from, to])
	var r: Dictionary = await d.walk_trail(from, to)
	await d.wait(1.0)
	var seg := S.end()
	S.record = false
	var frames := S.stop_capture()
	var notes := S.capture_notes.duplicate()
	d.check("walked the trail %s -> %s across the gate" % [from, to], bool(r["ok"]), "%s via %s" % [r.get("map", ""), r.get("via", "")])
	# The gate commit: the tick the map changed.
	var commit := {}
	var prev: Dictionary = {}
	var after: Array = []
	for row: Dictionary in S.rows:
		if not prev.is_empty() and String(row["map"]) != String(prev["map"]) and commit.is_empty():
			var jump_px := ((row["scr_feet"] as Vector2) - (prev["scr_feet"] as Vector2)).length() if row.has("scr_feet") else -1.0
			commit = {"tick": int(row["f"]), "view_before": float(prev["view"]), "focus_step_m": (row["focus"] as Vector3).distance_to(prev["focus"]),
				"player_screen_jump_px": jump_px, "feet_before": prev.get("scr_feet", Vector2.ZERO), "feet_after": row.get("scr_feet", Vector2.ZERO)}
		if not commit.is_empty():
			after.append(row)
		prev = row
	if not commit.is_empty():
		var settle := -1
		var max_step := 0.0
		var view_after := float((after[after.size() - 1] as Dictionary)["view"])
		for k in range(1, after.size()):
			var st := ((after[k] as Dictionary)["focus"] as Vector3).distance_to((after[k - 1] as Dictionary)["focus"])
			if k < 30:
				max_step = maxf(max_step, st)
			if settle < 0 and absf(float((after[k] as Dictionary)["view"]) - view_after) < 0.01:
				settle = k
		commit["view_after"] = view_after
		commit["view_blend_ticks"] = settle
		commit["max_focus_step_after_m"] = max_step
	results["trail"] = {"walk": "%s via %s, %.1f s, %.1f m" % [r.get("map", ""), r.get("via", ""), float(r.get("time_s", 0.0)), float(r.get("distance_m", 0.0))],
		"trail_length_m": trail_len, "commit": commit, "camera": Lib.Sampler.camera_text(seg), "move": Lib.Sampler.move_text(seg),
		"frames": notes}
	d.note("TRAIL %s -> %s: %s" % [from, to, results["trail"]["walk"]])
	d.note("TRAIL CAMERA %s" % Lib.Sampler.camera_text(seg))
	d.note("TRAIL gate commit: %s" % str(commit))
	d.soft_check("the player stays in the play rect on the trail (%d of %d camera ticks)" % [int(seg["cam_in_frame"]), int(seg["cam_ticks"])],
		int(seg["cam_in_frame"]) == int(seg["cam_ticks"]))
	if not commit.is_empty():
		d.soft_check("the gate commit does not jump the player on screen (%.0f px in one tick)" % float(commit["player_screen_jump_px"]),
			float(commit["player_screen_jump_px"]) < 20.0)
	if not frames.is_empty():
		Lib.Util.save_shot(d, Lib.Util.sheet(frames, 3, Vector2i(640, 360)), "cam_trail_sheet",
			"trail %s -> %s, full frames every %.2f s from the portal (row-major): %s" % [from, to, every / TPS, ", ".join(notes)])


# =================================================================================================================
# 2. Door
# =================================================================================================================

func _door(d: PlaytestDriver) -> void:
	var town := "000000060"
	var shop := "000000061"
	await d.console("warp %s" % town)
	await d.wait(0.5)
	var src := d.find_portal(shop)
	if not d.check("a door from %s to %s" % [town, shop], src != null):
		return
	await d.walk_to(src.anchor_ground, {"max_s": 90.0})
	var frames: Array = []
	S.start_capture(9, 4, 0)
	S.rows.clear()
	S.record = true
	var f0 := Engine.get_physics_frames()
	var e: Dictionary = await d.enter_portal(shop)
	var f_in := Engine.get_physics_frames()
	await d.wait(0.6)
	frames.append_array(S.stop_capture())
	d.check("entered the %s door with Up" % shop, bool(e["ok"]), str(e.get("issues", "")))
	var inside := _framing(d)
	# Back out.
	var out_portal := d.find_portal(town)
	var back := {}
	if out_portal != null:
		await d.walk_to(out_portal.anchor_ground, {"max_s": 30.0})
		S.start_capture(9, 2, 0)
		back = await d.enter_portal(town)
		await d.wait(0.6)
		frames.append_array(S.stop_capture())
	S.record = false
	var outside := _framing(d)
	# Transition timing from the rows: input blocked / session not idle.
	var busy := 0
	for row: Dictionary in S.rows:
		if not bool(row["idle"]):
			busy += 1
	results["door"] = {"enter": "%s via %s" % [e.get("to", ""), e.get("via", "")], "enter_game_s": (f_in - f0) / TPS,
		"busy_ticks_both_ways": busy, "inside": inside, "back": "%s via %s" % [back.get("to", ""), back.get("via", "")], "outside": outside}
	d.note("DOOR %s -> %s and back: %s" % [town, shop, str(results["door"])])
	d.soft_check("on arrival through a door the player is near the screen centre (inside %.2f, outside %.2f of the half-screen)" % [
		float(inside["off_max"]), float(outside["off_max"])], float(inside["off_max"]) < 0.35 and float(outside["off_max"]) < 0.35)
	if not frames.is_empty():
		Lib.Util.save_shot(d, Lib.Util.sheet(frames, 3, Vector2i(640, 360)), "cam_door_sheet",
			"Southperry -> Armor Store with Up (4 frames, 0.15 s apart, from the walk into the door), then the way back out (2 frames)")


## Where the player is on screen right now: {"off" (fraction of the half-screen), "off_max", "view_m", "map"}.
func _framing(d: PlaytestDriver) -> Dictionary:
	var rig := d.ctx().camera as CameraRig
	var p := d.player()
	var vp := d.get_viewport().get_visible_rect().size
	var c := rig.camera.unproject_position(p.global_position + Vector3.UP * 0.75)
	var off := (c - vp * 0.5) / (vp * 0.5)
	return {"map": d.current_map(), "off": "(%.2f, %.2f)" % [off.x, off.y], "off_max": maxf(absf(off.x), absf(off.y)),
		"view_m": snappedf(rig.camera.size, 0.01)}


# =================================================================================================================
# 3. Map edges
# =================================================================================================================

func _edges(d: PlaytestDriver) -> void:
	var frames: Array = []
	var notes: Array = []
	var edges := {}
	for map_id: String in ["000000060", "000000042", "000001000", "000001020"]:
		await d.console("warp %s" % map_id)
		await d.wait(0.5)
		var def := d.world().defs.get_def(map_id)
		# The route point nearest a footprint corner (the far end of the map from its middle).
		var best := Vector3.INF
		var best_d := INF
		var corner := Vector2.ZERO
		for r: Variant in def.sidecar.get("routes", []):
			for pt: Variant in (r as Dictionary).get("points", []):
				var q := Vector3(float(pt[0]), float(pt[1]), float(pt[2]))
				for v: Vector2 in def.footprint:
					var dd := Vector2(q.x - v.x, q.z - v.y).length()
					if dd < best_d:
						best_d = dd
						best = q
						corner = v
		S.begin("edge %s" % map_id)
		var w: Dictionary = await d.walk_to(best, {"max_s": 120.0})
		await d.wait(1.5)
		var seg := S.end()
		var img: Image = await Lib.Util.grab(d)
		if img != null:
			frames.append(img)
		var fr := _framing(d)
		var rig := d.ctx().camera as CameraRig
		edges[map_id] = {"walk": "%s via %s, %.1f s" % [w.get("result", "?"), w.get("how", "?"), float(w.get("time_s", 0.0))],
			"corner_dist_m": snappedf(best_d, 0.01), "at": Lib.Util.fmt_v(def.to_local(d.player().global_position)), "framing": fr,
			"clamped_ticks": int(seg["cam_clamped"]), "camera_ticks": int(seg["cam_ticks"]), "camera": Lib.Sampler.camera_text(seg),
			"bounds": str(rig.bounds_rect())}
		notes.append("%s at local %s, %.1f m from the footprint corner, player off-centre %s" % [map_id, edges[map_id]["at"], best_d, fr["off"]])
		d.note("EDGE %s: %s" % [map_id, str(edges[map_id])])
	results["edges"] = edges
	if not frames.is_empty():
		Lib.Util.save_shot(d, Lib.Util.sheet(frames, 2, Vector2i(800, 450)), "cam_edges_sheet",
			"full frames at the route point nearest a footprint corner (row-major): " + "; ".join(notes))


# =================================================================================================================
# 4. Canopy occlusion
# =================================================================================================================

func _canopy(d: PlaytestDriver) -> void:
	var map_id := "000001002"
	await d.console("warp %s" % map_id)
	await d.console("heal")
	await d.wait(0.5)
	var rig := d.ctx().camera as CameraRig
	S.start_capture(150, 4, 0, func() -> bool: return rig.player_occluded())
	var segs: Array = []
	for route: String in ["ShelfWest", "EastGlade", "Descent", "WestHollow"]:
		if S.captures.size() >= 4:
			break
		S.begin("canopy %s %s" % [map_id, route])
		await d.walk_route(map_id, route)
		segs.append(S.end())
		await d.console("heal")
	var frames := S.stop_capture()
	var m := Lib.Sampler.merge("canopy %s" % map_id, segs)
	results["canopy"] = {"camera": Lib.Sampler.camera_text(m), "frames": Array(S.capture_notes)}
	d.note("CANOPY CAMERA %s" % Lib.Sampler.camera_text(m))
	if not frames.is_empty():
		Lib.Util.save_shot(d, Lib.Util.sheet(frames, 2, Vector2i(800, 450)), "cam_canopy_sheet",
			"Dangerous Forest: full frames while the outline is on (a faded occluder or terrain covers the player): " + ", ".join(S.capture_notes))


# =================================================================================================================
# 5. Cliffs hiding monsters
# =================================================================================================================

func _cliffs(d: PlaytestDriver) -> void:
	var frames: Array = []
	var notes: Array = []
	var segs: Array = []
	# The routes where terrain (ground, walls) hid nearby monsters most often in test_feel_routes.
	for pair: Array in [["000001001", "Crown_to_Ridge_to_Arrival"], ["000001006", "WestGrove"], ["000000040", "WestLadders"], ["000000050", "Maria_Ladder77"], ["000001001", "To_P19"]]:
		if frames.size() >= 4:
			break
		var map_id: String = pair[0]
		await d.console("warp %s" % map_id)
		await d.console("heal")
		await d.wait(0.5)
		S.start_capture(150, 4 - frames.size(), 560, func() -> bool: return S.last_hidden_monster != "")
		S.capture_center = func() -> Vector2: return S.last_hidden_monster_screen
		S.begin("cliffs %s %s" % [map_id, pair[1]])
		await d.walk_route(map_id, pair[1])
		segs.append(S.end())
		for k in S.captures.size():
			notes.append(S.capture_notes[k])
		frames.append_array(S.stop_capture())
	var m := Lib.Sampler.merge("cliffs", segs)
	results["cliffs"] = {"camera": Lib.Sampler.camera_text(m), "hidden_where": m["mon_hidden_where"], "frames": notes}
	d.note("CLIFFS CAMERA %s" % Lib.Sampler.camera_text(m))
	d.note("CLIFFS hidden monsters: %s" % str(m["mon_hidden_where"]))
	if not frames.is_empty():
		Lib.Util.save_shot(d, Lib.Util.sheet(frames, 2, Vector2i(800, 450)), "cam_cliffs_sheet",
			"560 px crops centred on a monster within 8 m that terrain (ground, walls) hides from the camera: " + "; ".join(notes))


# =================================================================================================================
# 6. Snag spots (found by test_feel_routes)
# =================================================================================================================

func _snags(d: PlaytestDriver) -> void:
	var spec := OS.get_environment("FEEL_SNAG_ROUTES")
	if spec == "":
		spec = "000000060:LedgeRopes_Belvedere,000000060:Main"
	await d.console("god on")
	S.start_capture(20, 4, 600, func() -> bool: return S.snag_now)
	var segs: Array = []
	for pair: String in spec.split(","):
		var map_id := pair.get_slice(":", 0)
		var route := pair.get_slice(":", 1)
		if d.current_map() != map_id:
			await d.console("warp %s" % map_id)
			await d.wait(0.5)
		S.begin("snags %s %s" % [map_id, route])
		await d.walk_route(map_id, route)
		var sg := S.end()
		segs.append(sg)
		d.note("SNAGS %s" % Lib.Sampler.move_text(sg))
		d.note("SNAGS where %s / %s" % [str(sg["snag_where"]), str(sg["deflect_where"])])
	var frames := S.stop_capture()
	results["snags"] = {"segments": segs.map(func(x: Dictionary) -> String: return Lib.Sampler.move_text(x)), "frames": Array(S.capture_notes)}
	if not frames.is_empty():
		Lib.Util.save_shot(d, Lib.Util.sheet(frames, 2, Vector2i(600, 600)), "cam_snags_sheet",
			"600 px crops around the player while a snag or deflection is in progress (20 frames apart): " + ", ".join(S.capture_notes))


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
	if v is Vector3 or v is Vector2 or v is Rect2:
		return str(v)
	if v is float and (is_inf(v) or is_nan(v)):
		return str(v)
	return v
