extends Node
## Headless runner for the traversal tools (MAP_ARCHITECTURE.md section 4.13), scene res://tools/traversal_bot.tscn:
##
##   bash scripts/godot.sh --headless --fixed-fps 60 --path <game copy> res://tools/traversal_bot.tscn -- \
##       [--only l1,routes,trails,tour] [--map <id|slug>[,...]] [--links <link id>[,...]] [--tour edge|warp|both] \
##       [--legs <from>-<to>] [--out <file>]
##
## Sections (all by default):
##   l1      the island (collision only) through IslandWorld.build_now(): its errors and warnings (a settled arrival,
##           player spawn or NPC, a forced or unplaced spawn slot, a trail without a ribbon)
##   routes  L2 per map: TraversalBot.sweep() over every route of the chosen maps (--map), both directions
##   trails  L2 per link (TraversalTrails): every trail walked in each allowed direction in edge mode and pressed in
##           warp mode (doors: pressed both ways), walk/press-Up equivalence, and 40 -> 30 blocked by the ledge
##           (--links restricts the links)
##   tour    L3 (TraversalTour): the Test A tour from a new game, in edge mode and in force-warp mode (--tour picks
##           one; --legs runs a segment of the route's legs)
## Prints TRAVERSAL lines and a TRAVERSAL_SUMMARY, writes the report as JSON to --out (default
## user://traversal_report.json; docs/runtime/traversal_report.json is this file, regenerated at milestones), and
## exits 0 only when every section that ran is clean. Run it with --fixed-fps 60: the trail and tour sections run on
## real physics frames.

const SECTIONS := ["l1", "routes", "trails", "tour"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var maps := PackedStringArray()
	var links := PackedStringArray()
	var only := PackedStringArray()
	var tour_modes := PackedStringArray(["edge", "warp"])
	var legs := Vector2i(0, -1)
	var out_path := "user://traversal_report.json"
	var i := 0
	while i < args.size():
		var has_value := i + 1 < args.size()
		match args[i]:
			"--map":
				if has_value:
					maps.append_array(args[i + 1].split(",", false))
					i += 1
			"--links":
				if has_value:
					links.append_array(args[i + 1].split(",", false))
					i += 1
			"--only":
				if has_value:
					only.append_array(args[i + 1].split(",", false))
					i += 1
			"--tour":
				if has_value:
					tour_modes = PackedStringArray(["edge", "warp"]) if args[i + 1] == "both" else PackedStringArray([args[i + 1]])
					i += 1
			"--legs":
				if has_value:
					var parts := args[i + 1].split("-")
					legs = Vector2i(int(parts[0]), int(parts[1]) if parts.size() > 1 else -1)
					i += 1
			"--out":
				if has_value:
					out_path = args[i + 1]
					i += 1
		i += 1
	if only.is_empty():
		only = PackedStringArray(SECTIONS)
	await get_tree().process_frame
	var db := ContentDB.new().load_all()
	var report := {"generated_by": "game/tools/traversal_bot.tscn", "generated_at": Time.get_datetime_string_from_system(true) + "Z",
		"engine": Engine.get_version_info().get("string", ""), "sections": only,
		"maps_requested": maps if not maps.is_empty() else PackedStringArray(["all"])}
	var clean := true
	var summary := PackedStringArray()
	if "l1" in only:
		var l1 := _build(db)
		report["l1_build"] = l1
		clean = clean and (l1.errors as Array).is_empty() and (l1.warnings as Array).is_empty()
		summary.append("build errors=%d warnings=%d" % [(l1.errors as Array).size(), (l1.warnings as Array).size()])
	if "routes" in only:
		var sweep := TraversalBot.sweep(db, maps, self)
		report["l2_routes"] = sweep
		for r: Dictionary in sweep.get("failures", []):
			print("TRAVERSAL FAIL " + String(r.report))
		clean = clean and int(sweep.get("failed", 1)) == 0 and int(sweep.get("runs", 0)) > 0
		summary.append("routes maps=%d runs=%d failed=%d (%d ms)" % [int(sweep.get("maps", 0)), int(sweep.get("runs", 0)),
			int(sweep.get("failed", 0)), int(sweep.get("ms", 0))])
	if "trails" in only or "tour" in only:
		var w := TraversalWalker.new()
		w.name = "Walker"
		add_child(w)
		if not await w.setup():
			report["walker_error"] = w.setup_error
			clean = false
			summary.append("walker setup failed: %s" % w.setup_error)
		else:
			report["trails"] = _trail_summary(w.defs())
			if "trails" in only:
				var t0 := Time.get_ticks_msec()
				var trails: Dictionary = await TraversalTrails.run(w, links)
				trails["ms"] = Time.get_ticks_msec() - t0
				report["l2_links"] = trails
				clean = clean and int(trails.failed) == 0 and int(trails.runs) > 0
				summary.append("links runs=%d failed=%d (%d ms)" % [int(trails.runs), int(trails.failed), int(trails.ms)])
			if "tour" in only:
				var tours := {}
				for mode in tour_modes:
					var t1 := Time.get_ticks_msec()
					var tour: Dictionary = await TraversalTour.run(w, mode, legs.x, legs.y)
					tour["ms"] = Time.get_ticks_msec() - t1
					tours[mode] = tour
					clean = clean and bool(tour.ok)
					summary.append("tour %s ok=%s legs=%d time=%.0fs distance=%.0fm recoveries=%d stalls=%d violations=%d teleports=%d (%d ms)" % [
						mode, str(tour.ok), (tour.legs as Array).size(), float(tour.time_s), float(tour.distance_m), int(tour.recoveries),
						int(tour.stalls), int(tour.violations), int(tour.teleports), int(tour.ms)])
				report["l3_tour"] = tours
	print("TRAVERSAL_SUMMARY " + " | ".join(summary))
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_plain(report), "  ", false) + "\n")
		f.close()
		print("TRAVERSAL_REPORT " + ProjectSettings.globalize_path(out_path))
	else:
		push_error("[traversal_bot] cannot write %s" % out_path)
	get_tree().quit(0 if clean else 1)


## Builds the island (collision only) under this node and returns {"ms", "errors", "warnings", "stats"}.
func _build(db: ContentDB) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var world := IslandWorld.new()
	world.build_on_ready = false
	world.load_visuals = false
	world.attach_to_session = false
	add_child(world)
	world.build_now(db)
	var out := {"ms": Time.get_ticks_msec() - t0, "errors": Array(world.build_errors), "warnings": Array(world.build_warnings),
		"stats": world.stats.duplicate()}
	for w in world.build_warnings:
		print("TRAVERSAL BUILD_WARNING " + w)
	remove_child(world)
	world.free()
	return out


## Every trail's ribbon summary (length, width, heights, how it was derived).
func _trail_summary(d: MapDefinitions) -> Dictionary:
	var out := {}
	for t in d.trail_list():
		out[t.link_id] = t.to_dict()
	return out


## The report as JSON-safe values (Vector3 -> [x, y, z], packed arrays -> arrays, "state" blobs dropped).
func _plain(v: Variant) -> Variant:
	if v is Dictionary:
		var o := {}
		for k in v:
			if String(k) == "state":
				continue
			o[k] = _plain(v[k])
		return o
	if v is Array or v is PackedStringArray or v is PackedFloat32Array or v is PackedInt32Array:
		var a: Array = []
		for e in v:
			a.append(_plain(e))
		return a
	if v is Vector3:
		return [snappedf((v as Vector3).x, 0.01), snappedf((v as Vector3).y, 0.01), snappedf((v as Vector3).z, 0.01)]
	if v is float:
		return snappedf(v, 0.001)
	return v
