extends PlaytestScenario
## test_a_probe_trap (play-A): a focused probe behind a test_a_traversal stall in 000001000 (The Field West of Amherst).
## Walking the direct (grid) way from the Snail Garden door's arrival (in03) toward the in04 door (Hunting Ground Middle
## of the Forest I), the walker stopped at about (158.2, 6.2, 536.0) and could then not move at all: the routes, a
## straight line and the grid all made 0.0 m of progress. Here the same walk is repeated (a console warp to in03's
## arrival is the setup; the walk is real input), then the player tries to get out as a person would: each of 8
## directions held for 1.2 s, each with a jump, and Up / Down. Every attempt's displacement is recorded.

const FIELD := "000001000"


func description() -> String:
	return "probe: a possible collision trap in 000001000 on the direct way from in03 to in04"


func max_seconds() -> float:
	return 600.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Trapper", "female")
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	await d.console("god on")
	await d.console("warp %s in03" % FIELD)
	var w: Dictionary = await d.walk_to("portal:in04", {"planner": "grid", "max_s": 60.0, "retries": 0})
	var p := d.player()
	var s := d.state()
	var at := p.global_position
	d.note("the grid walk to in04: %s, %.1f s / %.1f m; stopped at %s (local %s), region %s, on_floor %s; issues: %s" % [
		w.get("result", ""), float(w.get("time_s", 0.0)), float(w.get("distance_m", 0.0)), _v(at), _v(s.get("local")),
		str(s.get("region")), str(s.get("on_floor")), "; ".join(w.get("issues", PackedStringArray()))])
	await d.screenshot("trap_stop")
	var best := 0.0
	var rows := PackedStringArray()
	for k in 8:
		for jump: bool in [false, true]:
			var a := TAU * k / 8.0
			var dir := Vector3(cos(a), 0.0, sin(a))
			var p0 := p.global_position
			var frames := roundi(1.2 * Engine.physics_ticks_per_second)
			for f in frames:
				d.input.set_move_world(dir, p.view_right, p.view_forward)
				if jump and f == 2:
					await d.tap(&"jump")
				await d.frames(1)
			d.input.release_movement()
			await d.wait(0.6)
			var moved := Vector2(p.global_position.x - p0.x, p.global_position.z - p0.z).length()
			best = maxf(best, moved)
			rows.append("dir %d%s: %.2f m (dy %.2f)" % [k * 45, "+jump" if jump else "", moved, p.global_position.y - p0.y])
			# Back to the stop point for the next try only if the player got out (so each try starts in the same place).
			if moved > 0.5:
				await d.console("goto %.2f %.2f" % [at.x, at.z])
	d.note("escape tries from %s: %s" % [_v(at), "; ".join(rows)])
	d.soft_check("the player can walk away from where the direct way stopped (best %.2f m in 1.2 s)" % best, best > 1.0, "; ".join(rows))
	var r: Dictionary = await d.walk_to("portal:in04", {"max_s": 90.0})
	d.note("then the routes to in04: %s %.1f s / %.1f m; %s" % [r.get("result", ""), float(r.get("time_s", 0.0)),
		float(r.get("distance_m", 0.0)), "; ".join(r.get("issues", PackedStringArray()))])
	d.check("probe finished", true)


static func _v(v: Variant) -> String:
	if v is Vector3:
		var u := v as Vector3
		return "(%.2f, %.2f, %.2f)" % [u.x, u.y, u.z]
	return str(v)
