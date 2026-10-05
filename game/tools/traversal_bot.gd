class_name TraversalBot
extends RefCounted
## L2 route runs (MAP_ARCHITECTURE.md section 4.13, "Per map"): every exported route of a map, in both directions
## (a one_way route once), walked by the player system's RouteBot driving the game's PlayerController
## (PlayerTestWorld) on that map's exported collision, synchronously at 60 ticks/s. A run fails on a stall, a fall
## below the map's kill_y or a timeout (RouteBot.Result). It is the player sandbox's `--sweep all`
## (PLAYER_AND_CAMERA.md "Route sweep") as a reusable, headless tool: tests/unit/test_traversal_routes.gd asserts
## it has no failure, and tools/traversal_bot.tscn writes it into docs/runtime/traversal_report.json.
##
##   var report := TraversalBot.sweep(db)                  # every map with an export
##   var report := TraversalBot.sweep(db, ["000000040"])   # MeowDB ids or Blender slugs
##   report = {"maps", "runs", "failed", "ms", "failures": [run], "per_map": {map_id: {slug, routes, runs, failed}}}
##   run    = {"map_id", "route", "result" (DONE|STALLED|FELL|TIMEOUT), "report" (RouteBot.report())}
##
## kill_y is the world runtime's own (MapDefinition.kill_y: the sidecar's, else the lowest walkable height minus
## presentation.json fall_recovery.kill_y_margin_m), so a run fails exactly where the game's fall recovery fires.

## Height above a route's first point the player is dropped from (it settles onto the ground on its first ticks).
## Structural, the same as the player sandbox.
const START_DROP_M := 0.3
## Extra ticks past a route's own time budget before the loop gives up (RouteBot times out by itself first).
const SLACK_TICKS := 60


## Runs the routes of `maps` (MeowDB ids or slugs; empty = every map the export has). `parent` hosts the physics
## world (default: the running scene). Needs the export (WorldSidecars.exists()); returns an empty sweep without it.
static func sweep(db: ContentDB, maps: PackedStringArray = PackedStringArray(), parent: Node = null) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var out := {"maps": 0, "runs": 0, "failed": 0, "ms": 0, "failures": [], "per_map": {}}
	if not WorldSidecars.exists():
		out["error"] = "no export in %s" % WorldSidecars.DEFAULT_DIR
		return out
	var side := WorldSidecars.load_dir()
	var defs := MapDefinitions.build(db, side)
	for id in _resolve(defs, maps):
		var def := defs.get_def(id)
		var sc := side.chunk(def.slug)
		var col := side.file_path(def.slug, "collision")
		if sc.is_empty() or col == "" or not ResourceLoader.exists(col):
			continue
		var runs := run_map(db, def, sc, load(col) as PackedScene, parent)
		var failed := 0
		for r: Dictionary in runs:
			if String(r.result) != "DONE":
				failed += 1
				(out.failures as Array).append(r)
		(out.per_map as Dictionary)[id] = {"slug": def.slug, "routes": (sc.get("routes", []) as Array).size(), "runs": runs.size(), "failed": failed}
		out["maps"] = int(out.maps) + 1
		out["runs"] = int(out.runs) + runs.size()
		out["failed"] = int(out.failed) + failed
	out["ms"] = Time.get_ticks_msec() - t0
	return out


## Every route of one map (both directions unless one_way) on its collision scene. Returns one run dict per route
## run (see the class doc), in sidecar order (forward, then reverse).
static func run_map(db: ContentDB, def: MapDefinition, sidecar: Dictionary, collision: PackedScene, parent: Node = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var w := PlayerTestWorld.create(db, parent)
	w.add_node(collision.instantiate())
	var p := w.spawn_player(Vector3.ZERO)
	p.add_climbables_from_sidecar(sidecar.get("climbables", []))
	p.kill_y = def.kill_y
	var bots: Array[RouteBot] = []
	for r in sidecar.get("routes", []):
		if not (r is Dictionary):
			continue
		var rb := RouteBot.create(r["points"], p.climbables, p.model, "%s/%s" % [def.slug, String(r.get("name", "?"))])
		bots.append(rb)
		if not bool(r.get("one_way", false)):
			bots.append(rb.reversed())
	var current: Array = [null]
	p.fell_out_of_world.connect(func(_at: Vector3) -> void:
		if current[0] != null:
			(current[0] as RouteBot).notify_fall())
	for rb in bots:
		current[0] = rb
		w.bot.release_all()
		p.teleport(Transform3D(MapDefinitions.facing_basis(rb.start_facing()), rb.start_point() + Vector3.UP * START_DROP_M))
		for _i in int(rb.max_time_s * 60.0) + SLACK_TICKS:
			if rb.tick(p, w.bot, PlayerTestWorld.TICK) != RouteBot.Result.RUNNING:
				break
			p.step(PlayerTestWorld.TICK)
		out.append({"map_id": def.map_id, "route": rb.name, "result": String(RouteBot.Result.keys()[rb.result]), "report": rb.report()})
	w.free_all()
	return out


## MeowDB ids for `maps` (ids or slugs; empty = all maps, sorted).
static func _resolve(defs: MapDefinitions, maps: PackedStringArray) -> PackedStringArray:
	if maps.is_empty():
		return defs.ids()
	var out := PackedStringArray()
	for m in maps:
		if defs.has_map(m):
			out.append(m)
		elif defs.id_of_slug.has(m):
			out.append(String(defs.id_of_slug[m]))
		else:
			push_warning("[TraversalBot] unknown map %s" % m)
	return out
