extends Node
## Headless runner of the stuck-region scan (StuckScan, docs/runtime/STUCK_SCAN.md), scene
## res://tools/stuck_scan_tool.tscn:
##
##   bash scripts/godot.sh --headless --path game res://tools/stuck_scan_tool.tscn -- \
##       [--map <id>[,...]] [--no-verify] [--cell <m>] [--out <file>] [--png <dir>]
##
## Builds the island (collision only) through IslandWorld.build_now(), scans every map (or --map), verifies every
## flagged component with the real PlayerController (unless --no-verify), matches them against
## data/misostory/stuck_allowlist.json, prints STUCK lines and a STUCK_SUMMARY, and writes the report as JSON to --out
## (default: docs/runtime/stuck_report.json next to the project, the committed copy). Exits 0 only when no
## CONFIRMED component is missing from the allowlist. Run it on the real game/ directory (not an ISOLATE copy) when
## the default --out should land in the repository's docs. --png writes a top-down picture of each map into <dir>
## (StuckScan.heatmap(): green escapable, red flagged, grey unreachable) for inspection.


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var maps := PackedStringArray()
	var do_verify := true
	var cell := StuckScan.DEFAULT_CELL_M
	var out_path := ProjectSettings.globalize_path("res://").path_join("../docs/runtime/stuck_report.json").simplify_path()
	var png_dir := ""
	var i := 0
	while i < args.size():
		var has_value := i + 1 < args.size()
		match args[i]:
			"--map":
				if has_value:
					maps.append_array(args[i + 1].split(",", false))
					i += 1
			"--no-verify":
				do_verify = false
			"--cell":
				if has_value:
					cell = float(args[i + 1])
					i += 1
			"--out":
				if has_value:
					out_path = args[i + 1]
					i += 1
			"--png":
				if has_value:
					png_dir = args[i + 1]
					i += 1
		i += 1
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var db := ContentDB.new().load_all()
	var world := IslandWorld.new()
	world.name = "StuckScanWorld"
	world.build_on_ready = false
	world.load_visuals = false
	world.attach_to_session = false
	add_child(world)
	world.build_now(db)
	var build_ms := Time.get_ticks_msec() - t0
	if not world.build_errors.is_empty():
		push_error("[stuck_scan] island build errors: %s" % "; ".join(world.build_errors))
	var scan := StuckScan.create(world, db, {"cell": cell, "host": self})
	var doc := scan.run(maps, do_verify, png_dir)
	var report := {"generated_by": "game/tools/stuck_scan_tool.tscn", "generated_at": Time.get_datetime_string_from_system(true) + "Z",
		"engine": Engine.get_version_info().get("string", ""), "verified": do_verify,
		"maps_requested": maps if not maps.is_empty() else PackedStringArray(["all"]), "build_ms": build_ms,
		"allowlist": "game/data/misostory/stuck_allowlist.json"}
	report.merge(doc)
	for id: String in (doc.maps as Dictionary):
		var row: Dictionary = doc.maps[id]
		print("STUCK map %s nodes=%d reachable=%d flagged=%d components=%d (%d ms)" % [id, int(row.nodes), int(row.reachable),
			int(row.flagged), (row.components as Array).size(), int(row.ms)])
		for c: Dictionary in row.components:
			print("STUCK   %s %s %d nodes (%.2f m2) local %s blender-local xy %s drop %.2f m%s" % [c.id, c.get("verdict", "unverified"),
				int(c.nodes), float(c.area_m2), c.local, c.blender_local_xy, float(c.drop_m),
				(" [allowlisted: %s]" % c.allowlisted) if c.has("allowlisted") else ""])
	var t: Dictionary = doc.totals
	print("STUCK_SUMMARY maps=%d nodes=%d flagged=%d components=%d confirmed=%d cleared=%d unenterable=%d allowlisted=%d new_traps=%d (%d ms)" % [
		int(t.maps), int(t.nodes), int(t.flagged), int(t.components), int(t.confirmed), int(t.cleared), int(t.unenterable),
		int(t.allowlisted), int(t.new_traps), int(t.ms)])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_plain(report), "  ", false) + "\n")
		f.close()
		print("STUCK_REPORT " + out_path)
	else:
		push_error("[stuck_scan] cannot write %s" % out_path)
	get_tree().quit(0 if int(t.new_traps) == 0 else 1)


## The report as JSON-safe values (vectors -> [x, y, z], packed arrays -> arrays, floats rounded).
func _plain(v: Variant) -> Variant:
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _plain(v[k])
		return o
	if v is Array or v is PackedStringArray or v is PackedFloat32Array or v is PackedInt32Array or v is PackedVector3Array:
		var a: Array = []
		for e in v:
			a.append(_plain(e))
		return a
	if v is Vector3:
		return [snappedf((v as Vector3).x, 0.01), snappedf((v as Vector3).y, 0.01), snappedf((v as Vector3).z, 0.01)]
	if v is float:
		return snappedf(v, 0.001)
	return v
