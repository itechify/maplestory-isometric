extends PlaytestScenario
## trap_probe: is a spot a trap? Places the player at a map-local point (an API teleport: setup for the diagnosis),
## then tries to walk out with real input in 8 directions, with and without jumping, and reports the best escape.
## The spot comes from the environment so any finding can be probed without editing the scenario:
##   TRAP_MAP=000001000 TRAP_LOCAL="12.6,0,-33.6" bash scripts/playtest.sh trap_probe
## A spot is a trap when no try gets more than ESCAPE_M of flat distance away from it or gains real height.
## Without TRAP_MAP / TRAP_LOCAL it probes every KNOWN_TRAPS entry: former traps fixed in the Blender source, kept as a
## regression (tests/unit/test_playtest_traps.gd).

const ESCAPE_M := 4.0
## [map, map-local spot] of every trap the playtests found and the source world fixed.
const KNOWN_TRAPS := [
	["000000050", Vector3(60.8, 0.0, -22.4)],   # A Split Road: pocket beside T4_Ramp (fix round F1)
	["000001000", Vector3(12.6, 0.0, -33.6)],   # The Field West of Amherst: gap between P17/P20/P21/P25 (F1)
]


func description() -> String:
	return "probe a map-local spot for a trap (TRAP_MAP, TRAP_LOCAL)"


func max_seconds() -> float:
	return 240.0


func run(d: PlaytestDriver) -> void:
	var spots: Array = []
	var parts := OS.get_environment("TRAP_LOCAL").split(",")
	if OS.get_environment("TRAP_MAP") != "" and parts.size() == 3:
		spots.append([OS.get_environment("TRAP_MAP"), Vector3(float(parts[0]), float(parts[1]), float(parts[2]))])
	else:
		spots = KNOWN_TRAPS
	var ng: Dictionary = await d.new_game("Prober", "male", "585", {"str": 9})
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	for entry: Array in spots:
		await _probe(d, String(entry[0]), entry[1] as Vector3)


func _probe(d: PlaytestDriver, map: String, local: Vector3) -> void:
	await d.console("warp " + map)
	await d.console("god on")
	var p := d.player()
	var w := d.world()
	var def := w.defs.get_def(map)
	var spot := def.to_world(local)
	# Stand on the surface a falling player would land on (the first hit from above), not inside whatever solid now
	# fills the old floor: a filled pocket is then probed from its fill.
	var space := p.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 20.0, spot + Vector3.DOWN * 5.0))
	if not hit.is_empty():
		d.note("landing surface over the spot: y %.2f (the given spot is y %.2f)" % [(hit.position as Vector3).y, spot.y])
		spot = hit.position
	var best := 0.0
	var best_rise := 0.0
	for k in 8:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(45.0 * k))
		for jump in [false, true]:
			w.place_player(Transform3D(p.global_transform.basis, spot + Vector3.UP * 0.05))
			await d.wait(0.5)
			var a := p.global_position
			var f0 := Engine.get_physics_frames()
			var jumped := false
			while Engine.get_physics_frames() - f0 < 150:
				d.input.set_move_world(dir, p.view_right, p.view_forward)
				if jump and not jumped and Engine.get_physics_frames() - f0 > 10:
					jumped = true
					await d.input.tap_action(&"jump")
				await d.get_tree().process_frame
				d.input.reassert()
			d.input.release_movement()
			await d.wait(0.3)
			var b := p.global_position
			var moved := Vector2(b.x - spot.x, b.z - spot.z).length()
			best = maxf(best, moved)
			best_rise = maxf(best_rise, b.y - a.y)
			d.note("dir %d%s: %.2f m from the spot, rise %.2f, at local %s" % [k, " + jump" if jump else "", moved,
				b.y - a.y, def.to_local(b)])
	d.check("the spot at local %s in %s is not a trap" % [local, map],
		best > ESCAPE_M or best_rise > 1.0, "best escape %.2f m, best rise %.2f m" % [best, best_rise])
