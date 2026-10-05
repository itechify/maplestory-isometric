extends PlaytestScenario
## test_feel_gate: reproduces the unexpected map change test_feel_routes met in Hunting Ground Middle of the Forest I
## (000001005): walking on foot from the end of route Floor to the start of route JumpTower over the map's own routes
## left the map for The Field West of Amherst (000001000) through a gate. Lists the far gates of 000001005 and how
## close each route point comes to them, then walks the same legs with real input and reports where the map changed.
## Setup (console, counted apart): `god on` and `warp 000001005`.

const Lib := preload("res://tools/playtest/scenarios/test_feel_common.gd")
const MAP := "000001005"


func description() -> String:
	return "HGMF I: does walking the map's routes cross a far gate into another map?"


func max_seconds() -> float:
	return 600.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Gate", "female", "541", {})
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	await d.console("god on")
	await d.console("warp %s" % MAP)
	var w := d.world()
	var def := w.defs.get_def(MAP)
	for g: GateDef in w.defs.far_gates(MAP):
		var near_pts := PackedStringArray()
		for r: Variant in def.sidecar.get("routes", []):
			for pt: Variant in (r as Dictionary).get("points", []):
				var q := Vector3(float(pt[0]), float(pt[1]), float(pt[2]))
				var sd := g.signed_distance(q)
				if absf(sd) < 1.5 and absf(g.lateral_offset(q)) <= g.half_width:
					near_pts.append("%s %s sd %.2f lat %.2f in_box %s" % [(r as Dictionary)["name"], Lib.Util.fmt_v(def.to_local(q)), sd, g.lateral_offset(q), g.in_box(q)])
		d.note("far gate %s into %s: origin %s (local %s), normal %s, half width %.2f; route points within 1.5 m of its plane and inside its width: %s" % [
			g.key(), g.map_id, Lib.Util.fmt_v(g.origin), Lib.Util.fmt_v(def.to_local(g.origin)), Lib.Util.fmt_v(g.normal), g.half_width,
			"none" if near_pts.is_empty() else "; ".join(near_pts)])
	# The legs of the sweep: route Floor, then on foot to the start of JumpTower.
	var commits: Array = []
	var on_commit := func(rec: Variant) -> void:
		var p := d.player()
		commits.append("%s via %s at %s" % [d.current_map(), (rec as TransitionRecord).via if rec is TransitionRecord else "?", Lib.Util.fmt_v(p.global_position)])
	d.session().connect(&"transition_finished", on_commit)
	var a: Dictionary = await d.walk_route(MAP, "Floor")
	d.note("route Floor: ok %s, now in %s at %s" % [a["ok"], d.current_map(), Lib.Util.fmt_v(d.player().global_position)])
	if d.current_map() == MAP:
		var plan: Dictionary = d.walker.plan(d.resolve_target("route:JumpTower")["position"])
		var pts := PackedStringArray()
		for q: Vector3 in plan["path"]:
			pts.append(Lib.Util.fmt_v(def.to_local(q)))
		d.note("planned path (%s) from the end of Floor to the start of JumpTower, local: %s" % [plan["how"], ", ".join(pts)])
		var S := Lib.Sampler.new()
		S.setup(d)
		S.monsters_on = false
		d.add_child(S)
		S.record = true
		var b: Dictionary = await d.walk_to("route:JumpTower", {"max_s": 60.0})
		S.record = false
		d.note("to JumpTower: %s, now in %s; last transition %s" % [b.get("result", "?"), d.current_map(), str(d.state().get("last_transition", {}))])
		var prev: Dictionary = {}
		var tail: Array = []
		for row: Dictionary in S.rows:
			if String(row["map"]) != MAP and not prev.is_empty():
				d.note("map changed at tick %d: before %s local %s (%s, idle %s), after %s %s (%s)" % [int(row["f"]), MAP,
					Lib.Util.fmt_v(def.to_local(prev["pos"])), prev["st"], prev["idle"], row["map"], Lib.Util.fmt_v(row["pos"]), row["st"]])
				commits.append("%s at local %s" % [row["map"], Lib.Util.fmt_v(def.to_local(prev["pos"]))])
				break
			tail.append("%s %s%s" % [Lib.Util.fmt_v(def.to_local(row["pos"])), row["st"], "" if bool(row["idle"]) else " busy"])
			if tail.size() > 40:
				tail.pop_front()
			prev = row
		d.note("the last 40 ticks before the change (every tick, local): %s" % ", ".join(tail))
		for e: Array in S.events:
			d.note("event %s" % str(e))
	d.session().disconnect(&"transition_finished", on_commit)
	d.note("map changes while walking: %s" % str(commits))
	d.soft_check("walking the routes of %s never leaves the map" % MAP, commits.is_empty(), str(commits))
