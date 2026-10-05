extends PlaytestScenario
## test_feel_ledges: "Does jumping feel useful? Are jumps readable from the isometric camera?" on the routes that need a
## jump (RouteBot jumped on them in test_feel_routes). Setup (console, counted apart): `god on` and a `warp` per map.
## Play: walk the route with real input and record where the walk jumped (the takeoff and the ledge it landed on);
## then, at each ledge, try it as a player would, with real keys:
##   pressed   walk into the face until stopped, then Space with the direction still held;
##   running   from 1.3 m back, Space when the feet are 0.6 m from the takeoff point;
##   late      the same, Space at the takeoff point itself (the bot's spot);
## and whether the landing is on the ledge. Windowed runs write a frame sheet of one attempt per ledge.
## FEEL_LEDGES="000000042:Main,..." picks the routes (default: 000000042:Main).

const Lib := preload("res://tools/playtest/scenarios/test_feel_common.gd")
const TPS := 60.0

var S: Lib.Sampler = null
var results: Array = []


func description() -> String:
	return "the ledges the routes jump: a player's pressed, running and late jumps onto each, with real keys"


func max_seconds() -> float:
	return 1500.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Ledges", "female", "541", {})
	if not d.check("new game through the title and creation screens", bool(ng["ok"]), String(ng["why"])):
		return
	S = Lib.Sampler.new()
	S.setup(d)
	S.monsters_on = false
	d.add_child(S)
	await d.console("god on")
	var pairs := OS.get_environment("FEEL_LEDGES")
	if pairs == "":
		pairs = "000000042:Main"
	var frames: Array = []
	var notes: Array = []
	for pair: String in pairs.split(","):
		var map_id := pair.get_slice(":", 0)
		var route := pair.get_slice(":", 1)
		if d.current_map() != map_id:
			await d.console("warp %s" % map_id)
		await d.wait(0.5)
		var ev0 := S.events.size()
		S.rows.clear()
		S.record = true
		var w: Dictionary = await d.walk_route(map_id, route)
		S.record = false
		d.check("walked %s %s" % [map_id, route], bool(w["ok"]), "; ".join(PackedStringArray(w.get("issues", []))))
		var ledges := _ledges_from(S.rows, S.events.slice(ev0))
		d.note("%s %s: the walk jumped %d time(s): %s" % [map_id, route, ledges.size(), str(ledges.map(func(l: Dictionary) -> String: return "%.2f m at %s" % [l["rise"], Lib.Util.fmt_v(l["take"])]))])
		for l: Dictionary in ledges:
			var res := {"map": map_id, "route": route, "rise_m": snappedf(float(l["rise"]), 0.01), "takeoff": Lib.Util.fmt_v(d.world().defs.get_def(map_id).to_local(l["take"]))}
			for mode: String in ["pressed", "running", "late"]:
				var shoot := frames.size() < 8 and mode == "running"
				if shoot:
					S.start_capture(7, 4, 520)
				var ok := await _attempt(d, l, mode)
				if shoot:
					var got := S.stop_capture()
					frames.append_array(got)
					for k in got.size():
						notes.append("%s rise %.2f m (%s)" % [map_id, float(l["rise"]), mode])
				res[mode] = ok
			results.append(res)
			d.note("LEDGE %s" % str(res))
	var n := results.size()
	var count := func(mode: String) -> int: return results.filter(func(r: Dictionary) -> bool: return bool(r[mode])).size()
	d.soft_check("a player's running jump makes every ledge the routes jump (%d of %d)" % [count.call("running"), n], count.call("running") == n, str(results))
	d.soft_check("a jump pressed against the face makes every ledge (%d of %d)" % [count.call("pressed"), n], count.call("pressed") == n, str(results))
	d.note("ledges: %d; pressed %d, running %d, late %d made it" % [n, count.call("pressed"), count.call("running"), count.call("late")])
	if not frames.is_empty():
		Lib.Util.save_shot(d, Lib.Util.sheet(frames, 4, Vector2i(400, 400)), "feel_ledges_sheet",
			"running jumps onto the ledges, 4 frames 7 ticks apart from 1.3 m back (520 px crops): " + "; ".join(notes))


## The jumps of a walk: [{take (feet before the jump), land (feet on landing), rise, dir}] for jumps that landed higher.
func _ledges_from(rows: Array, events: Array) -> Array:
	var out: Array = []
	for e: Array in events:
		if e[1] != "jumped":
			continue
		var fj := int(e[0])
		var take := Vector3.INF
		var land := Vector3.INF
		var airborne := false
		for row: Dictionary in rows:
			var f := int(row["f"])
			if f < fj:
				take = row["pos"]
			elif String(row["st"]) == "air":
				airborne = true
			elif airborne and String(row["st"]) == "ground":
				land = row["pos"]
				break
		if take == Vector3.INF or land == Vector3.INF or land.y - take.y < 0.3:
			continue
		var dir := Vector3(land.x - take.x, 0.0, land.z - take.z)
		if dir.length() < 0.05:
			continue
		out.append({"take": take, "land": land, "rise": land.y - take.y, "dir": dir.normalized()})
	return out


## One attempt at a ledge. Returns true when the player stands on it (within 0.15 m of the landing height) after.
func _attempt(d: PlaytestDriver, l: Dictionary, mode: String) -> bool:
	var p := d.player()
	var take: Vector3 = l["take"]
	var dir: Vector3 = l["dir"]
	var land_y := float((l["land"] as Vector3).y)
	var start := take - dir * (0.8 if mode == "pressed" else 1.3)
	await d.walk_to(start, {"within_m": 0.25, "max_s": 60.0})
	await d.walker.nudge_until(start, func() -> bool: return Vector2(d.player().global_position.x - start.x, d.player().global_position.z - start.z).length() < 0.12)
	await d.wait(0.4)
	if absf(p.global_position.y - take.y) > 0.3:
		d.note("ledge %s: could not stand below it (at %s)" % [mode, Lib.Util.fmt_v(p.global_position)])
		return false
	var i := d._begin(PlaytestReport.KIND_PLAY, "feel_ledge", "%s jump onto a %.2f m ledge" % [mode, float(l["rise"])])
	d.input.set_move_world(dir, p.view_right, p.view_forward)
	if mode == "pressed":
		# Into the face until the body stops.
		await d.wait(0.2)
		await d.wait_until(func() -> bool: return p.actual_velocity.length() < 0.2, 2.0)
	else:
		var lead := 0.6 if mode == "running" else 0.0
		await d.wait(0.1)
		await d.wait_until(func() -> bool:
			var v := d.player().global_position - take
			return Vector2(v.x, v.z).dot(Vector2(dir.x, dir.z)) >= -lead or d.player().actual_velocity.length() < 0.2, 3.0)
	await d.input.tap_key(PlaytestInput.key_for_action(&"jump"))
	await d.wait_until(func() -> bool: return not p.is_grounded(), 0.3)
	await d.wait_until(func() -> bool: return p.is_grounded(), 2.0)
	# Judged on the first landing (a narrow step can be overrun afterwards); the keys are let go on landing.
	var first_y := p.global_position.y
	d.input.release_movement()
	await d.wait(0.4)
	var ok := absf(first_y - land_y) < 0.15
	d._end(i, ok, "%s: first landing at %.2f m (ledge %.2f m), feet at %.2f m after" % ["made it" if ok else "missed", first_y, land_y, p.global_position.y])
	return ok
