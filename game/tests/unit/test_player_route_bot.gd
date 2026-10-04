extends TestCase
## The route bot (L2 seed) drives the real PlayerController along Iteration One's exported routes on the real
## exported collision (game/assets/world). Needs INCLUDE_WORLD=1:
##   ISOLATE=<name> INCLUDE_WORLD=1 bash scripts/test.sh player_route
## Without the exported world the tests print SKIP and pass; with it, any stall, timeout or fall fails.

const WORLD := "res://assets/world"
## Snail Hunting Ground I: stairs, ramps, terraces, 10 ladders/ropes. Every route, both directions.
const MAP_A := "SnailHuntingGround1_40000"
## Mushroom Town: town ground, steps and props.
const MAP_B := "MushroomTown_10000"


func _available(slug: String) -> bool:
	return ResourceLoader.exists("%s/%s.collision.glb" % [WORLD, slug]) and FileAccess.file_exists("%s/%s.json" % [WORLD, slug])


func _sidecar(slug: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [WORLD, slug]))
	return parsed if parsed is Dictionary else {}


## Runs every route of `slug` (both directions unless one_way) and returns the failure reports.
func _run_map(slug: String, both_directions: bool) -> PackedStringArray:
	var failures := PackedStringArray()
	var side := _sidecar(slug)
	var w := PlayerTestWorld.create(db())
	var col: PackedScene = load("%s/%s.collision.glb" % [WORLD, slug])
	w.add_node(col.instantiate())
	var p := w.spawn_player(Vector3.ZERO)
	p.add_climbables_from_sidecar(side.get("climbables", []))
	p.kill_y = float(side.get("footprint", {}).get("base_y", 0.0)) - 6.0
	var bots: Array[RouteBot] = []
	for r in side.get("routes", []):
		var rb := RouteBot.create(r["points"], p.climbables, p.model, "%s/%s" % [slug, r["name"]])
		bots.append(rb)
		if both_directions and not bool(r.get("one_way", false)):
			bots.append(rb.reversed())
	var current: Array = [null]
	p.fell_out_of_world.connect(func(_at: Vector3) -> void:
		if current[0] != null:
			(current[0] as RouteBot).notify_fall())
	for rb in bots:
		current[0] = rb
		w.bot.release_all()
		var start := rb.start_point()
		var f := rb.start_facing()
		p.teleport(Transform3D(Basis(Vector3.UP.cross(f).normalized(), Vector3.UP, f), start + Vector3.UP * 0.3))
		var max_ticks := int(rb.max_time_s * 60.0) + 60
		for i in max_ticks:
			if rb.tick(p, w.bot, PlayerTestWorld.TICK) != RouteBot.Result.RUNNING:
				break
			p.step(PlayerTestWorld.TICK)
		print("    BOT " + rb.report())
		if rb.result != RouteBot.Result.DONE:
			failures.append(rb.report())
	w.free_all()
	return failures


func test_bot_walks_every_route_of_snail_hunting_ground_1() -> void:
	if not _available(MAP_A):
		print("SKIP test_bot_walks_every_route_of_snail_hunting_ground_1: no exported world (run with INCLUDE_WORLD=1)")
		return
	var failures := _run_map(MAP_A, true)
	assert_eq(failures.size(), 0, "route failures:\n  " + "\n  ".join(failures))


func test_bot_walks_mushroom_town_routes() -> void:
	if not _available(MAP_B):
		print("SKIP test_bot_walks_mushroom_town_routes: no exported world (run with INCLUDE_WORLD=1)")
		return
	var failures := _run_map(MAP_B, true)
	assert_eq(failures.size(), 0, "route failures:\n  " + "\n  ".join(failures))


func test_route_geometry_helpers() -> void:
	var m := MovementModel.from_db(db())
	var rb := RouteBot.create([[0, 0, 0], [3, 0, 0], [3, 0, 4]], [] as Array[ClimbableDef], m, "L")
	assert_near(rb.length, 7.0, 1e-5, "arc length")
	assert_eq(rb.point_at(5.0), Vector3(3, 0, 2), "point at arc 5")
	assert_near(rb.closest_arc(Vector3(2.0, 0, 0.5), 0.0, 7.0), 2.0, 1e-4, "closest arc")
	assert_near(rb.closest_arc(Vector3(3.5, 0, 3.0), 0.0, 4.0), 4.0, 1e-4, "window caps the search")
	var back := rb.reversed()
	assert_eq(back.start_point(), Vector3(3, 0, 4), "reversed start")


## Runs `rb` on a synthetic world until it finishes; returns the bot.
func _drive(w: PlayerTestWorld, rb: RouteBot) -> RouteBot:
	var p := w.player
	var start := rb.start_point()
	var f := rb.start_facing()
	w.bot.release_all()
	p.teleport(Transform3D(Basis(Vector3.UP.cross(f).normalized(), Vector3.UP, f), start + Vector3.UP * 0.3))
	for i in int(rb.max_time_s * 60.0) + 60:
		if rb.tick(p, w.bot, PlayerTestWorld.TICK) != RouteBot.Result.RUNNING:
			break
		p.step(PlayerTestWorld.TICK)
	return rb


func test_bot_jumps_a_rise_above_step_height() -> void:
	# No ladder: a 0.8 m ledge (above step_up, within the jump apex) on the route must be jumped.
	var w := PlayerTestWorld.create(db())
	w.add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 20))
	w.add_box(Vector3(8, 0.4, 0), Vector3(8, 0.8, 6))  # top 0.8, face at x = 4
	var p := w.spawn_player(Vector3.ZERO)
	var pts := [[0, 0, 0], [3.8, 0, 0], [4.3, 0.8, 0], [9, 0.8, 0]]
	var rb := _drive(w, RouteBot.create(pts, p.climbables, p.model, "synthetic_rise"))
	assert_eq(rb.result, RouteBot.Result.DONE, rb.report())
	assert_true(rb.jumps >= 1, "jumped the rise (%s)" % rb.report())
	assert_near(p.global_position.y, 0.8, 0.02, "on the upper level")
	# Walking it backwards is a drop: no jump needed.
	var back := _drive(w, rb.reversed())
	assert_eq(back.result, RouteBot.Result.DONE, back.report())
	w.free_all()


func test_bot_climbs_a_ladder_up_and_down() -> void:
	var w := PlayerTestWorld.create(db())
	w.add_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	w.add_box(Vector3(5, 1.5, 0), Vector3(6, 3, 12))  # cliff x 2..8, top y = 3
	var p := w.spawn_player(Vector3.ZERO)
	p.add_climbables_from_sidecar([{
		"name": "Synthetic_Ladder", "kind": "ladder", "descend_only": false,
		"bottom": [1.85, 0.0, 0.0], "top": [1.85, 3.0, 0.0], "foot_ground": [1.85, 0.0, 0.0],
		"top_exit": [2.35, 3.0, 0.0], "facing_xz": [0.5, 0.0],
	}])
	var pts := [[-3, 0, 0], [1.5, 0, 0], [1.6, 3.0, 0], [5, 3.0, 0]]
	var up := _drive(w, RouteBot.create(pts, p.climbables, p.model, "synthetic_ladder"))
	assert_eq(up.result, RouteBot.Result.DONE, up.report())
	assert_eq(up.climbs, 1, "climbed once going up")
	assert_near(p.global_position.y, 3.0, 0.02, "on the cliff top")
	var down := _drive(w, up.reversed())
	assert_eq(down.result, RouteBot.Result.DONE, down.report())
	assert_eq(down.climbs, 1, "climbed down once")
	assert_near(p.global_position.y, 0.0, 0.02, "back on the floor")
	w.free_all()


func test_bot_reports_a_stall() -> void:
	# A wall across the route: the bot must stop and report STALLED with its position, not run forever.
	var w := PlayerTestWorld.create(db())
	w.add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	w.add_box(Vector3(5, 1.5, 0), Vector3(0.4, 3, 30))
	var p := w.spawn_player(Vector3.ZERO)
	var rb := _drive(w, RouteBot.create([[0, 0, 0], [10, 0, 0]], p.climbables, p.model, "walled"))
	assert_eq(rb.result, RouteBot.Result.STALLED, rb.report())
	assert_true(rb.stalled_at.x < 5.0, "stalled before the wall (%s)" % rb.report())
	w.free_all()
