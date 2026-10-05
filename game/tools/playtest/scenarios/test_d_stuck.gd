extends PlaytestScenario
## test_d_stuck: diagnostic for a Test D finding (not a brief test). In A Split Road (000000050) the hunting player
## ended at world (114.59, 4.00, 506.22) and could not walk anywhere for 300+ game seconds (every walk STALLED with
## 0.0 m progress). This places the player there (an API teleport: setup for the diagnosis) and tries to walk out
## with real input in 8 directions, with and without jumping; it notes what is above and around the body.

const MAP := "000000050"
const SPOT := Vector3(114.59, 4.0, 506.22)


func description() -> String:
	return "diagnose the A Split Road pocket at %s" % SPOT


func max_seconds() -> float:
	return 240.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Stuck", "male", "585", {"str": 9})
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	await d.console("warp " + MAP)
	await d.console("god on")
	var p := d.player()
	var w := d.world()
	var def := w.defs.get_def(MAP)
	d.note("spot local %s, region %s" % [def.to_local(SPOT), w.region_index.region_of(SPOT, MAP) if w.region_index != null else {}])
	_probe_columns(d, SPOT)
	w.place_player(Transform3D(p.global_transform.basis, SPOT + Vector3.UP * 0.05))
	await d.wait(1.0)
	d.note("after placing: at %s on_floor %s local %s" % [p.global_position, p.is_on_floor(), def.to_local(p.global_position)])
	await d.screenshot("pocket")
	var escaped := 0
	for k in 8:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(45.0 * k))
		for jump in [false, true]:
			w.place_player(Transform3D(p.global_transform.basis, SPOT + Vector3.UP * 0.05))
			await d.wait(0.5)
			var a := p.global_position
			var f0 := Engine.get_physics_frames()
			var jumped := false
			while Engine.get_physics_frames() - f0 < 90:
				d.input.set_move_world(dir, p.view_right, p.view_forward)
				if jump and not jumped and Engine.get_physics_frames() - f0 > 10:
					jumped = true
					await d.input.tap_action(&"jump")
				await d.get_tree().process_frame
				d.input.reassert()
			d.input.release_movement()
			await d.wait(0.3)
			var b := p.global_position
			var moved := Vector2(b.x - a.x, b.z - a.z).length()
			if moved > 1.0:
				escaped += 1
			d.note("dir %d (%s)%s: moved %.2f m flat, dy %.2f, to %s, on_floor %s" % [k, dir, " + jump" if jump else "", moved,
				b.y - a.y, b, p.is_on_floor()])
	_height_map(d, SPOT, 7.0, 0.5)
	# The planners from the pocket to the map's spawn and portals, then a real walk to each.
	for target: String in ["spawn:0", "portal:east01", "portal:west00"]:
		w.place_player(Transform3D(p.global_transform.basis, SPOT + Vector3.UP * 0.05))
		await d.wait(0.5)
		var t := d.resolve_target(target)
		if not bool(t["ok"]):
			d.note("%s: %s" % [target, t["why"]])
			continue
		var pl: Dictionary = d.walker.plan(t["position"])
		var pts: PackedVector3Array = pl["path"]
		d.note("plan to %s: %s, %d points, first %s" % [target, pl["how"], pts.size(), Array(pts.slice(0, mini(6, pts.size())))])
		var r: Dictionary = await d.walk_to(target, {"max_s": 30.0})
		d.note("walk to %s: %s via %s, now at %s (%s)" % [target, r.get("result", ""), r.get("how", ""), p.global_position,
			"; ".join(r.get("issues", PackedStringArray())).left(300)])
	# Does Save + Quit to Title + Continue get a trapped player out?
	w.place_player(Transform3D(p.global_transform.basis, SPOT + Vector3.UP * 0.05))
	await d.wait(1.0)
	await d.console("god off")
	var sv: Dictionary = await d.save_game()
	var qt: Dictionary = await d.quit_to_title()
	var ct: Dictionary = await d.continue_game()
	var p2 := d.player()
	d.note("save %s, quit %s, continue %s: resumed in %s at %s (%.2f m from the pocket's centre)" % [sv["ok"], qt["ok"], ct["ok"],
		d.current_map(), p2.global_position, p2.global_position.distance_to(SPOT)])
	d.check("probe finished", true, "%d of 16 tries moved more than 1 m" % escaped)


static func _height_map(d: PlaytestDriver, at: Vector3, half: float, step: float) -> void:
	var space := d.player().get_world_3d().direct_space_state
	var n := int(half / step)
	d.note("height map around %s (rows: world z from %.1f to %.1f; columns: world x from %.1f to %.1f; top Ground surface y, '##' = none)" % [
		at, at.z - half, at.z + half, at.x - half, at.x + half])
	for iz in range(-n, n + 1):
		var row := PackedStringArray()
		for ix in range(-n, n + 1):
			var x := at.x + ix * step
			var z := at.z + iz * step
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, at.y + 20.0, z), Vector3(x, at.y - 3.0, z), 1)
			var h := space.intersect_ray(q)
			row.append("##" if h.is_empty() else ("%2d" % roundi(((h.position as Vector3).y - at.y) * 10.0)).replace(" ", "+") if (h.position as Vector3).y - at.y < 9.95 else "^^")
		d.note("z %.1f: %s" % [at.z + iz * step, " ".join(row)])


static func _probe_columns(d: PlaytestDriver, at: Vector3) -> void:
	var space := d.player().get_world_3d().direct_space_state
	for off: Vector3 in [Vector3.ZERO, Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var hits := PackedStringArray()
		var from := at + off + Vector3.UP * 20.0
		var to := at + off + Vector3.DOWN * 5.0
		var ex: Array[RID] = []
		for _i in 6:
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.exclude = ex
			var h := space.intersect_ray(q)
			if h.is_empty():
				break
			var col: Object = h.get("collider")
			hits.append("y %.2f %s (layer %s)" % [(h.position as Vector3).y, (col as Node).name if col is Node else str(col),
				(col as CollisionObject3D).collision_layer if col is CollisionObject3D else -1])
			ex.append(h.get("rid"))
		d.note("column at %s: %s" % [at + off, "; ".join(hits)])
