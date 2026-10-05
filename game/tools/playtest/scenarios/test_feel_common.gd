extends PlaytestScenario
## test_feel_common: the measuring library of the play-feel review (test_feel_movement, test_feel_routes,
## test_feel_camera). Sampler is a node that reads the player, the camera and the nearby monsters after every physics
## tick (process_physics_priority 1000: after the player and CameraRig's 100) and sums them per labelled segment
## (one route, one map, one measurement). Nothing here changes the game: it only reads it.
## Run on its own, this scenario only checks that the sampler attaches to the real game and reads ticks.

## Segment counters thresholds (feel review definitions, documented in the scenarios' notes).
const SNAG_MIN_TICKS := 9          ## input held, grounded, speed < SNAG_SPEED_FRACTION x walk for >= 0.15 s
const SNAG_SPEED_FRACTION := 0.5
const DEFLECT_MIN_TICKS := 9       ## moving > 0.3 m/s, velocity > DEFLECT_DEG away from the input for >= 0.15 s
const DEFLECT_DEG := 25.0
const STEP_UP_MIN_M := 0.05        ## a grounded tick that rises more than this is a step-up
const SLOPE_MIN_DEG := 8.0
const CAM_POP_M := 0.25            ## the camera focus moving more than this in one tick (walk: 0.05 m per tick)
const CAM_JERK_MPS := 3.0          ## camera speed changing by more than this in one tick
const POST_TRANSITION_TICKS := 45  ## camera counters skip this long after a map change, warp or teleport
const NEAR_MONSTER_M := 8.0        ## camera.json occluder_monster_radius_m: the "nearby" radius of the camera review
const MID_MONSTER_M := 12.0
const NEAR_MONSTER_DY_M := 3.0     ## "nearby" also means on the player's tier or the next one (height difference)
const WHERE_MAX := 12


func description() -> String:
	return "play-feel library self-check: the sampler reads the real game"


func max_seconds() -> float:
	return 180.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("FeelLib", "female", "541", {})
	if not d.check("new game through the screens", bool(ng["ok"]), String(ng["why"])):
		return
	var s := Sampler.new()
	s.setup(d)
	d.add_child(s)
	s.begin("idle 1 s")
	await d.wait(1.0)
	var seg := s.end()
	d.check("the sampler read every physics tick", int(seg["ticks"]) >= 59, str(int(seg["ticks"])))
	d.check("the player is in frame at rest", int(seg["cam_ticks"]) > 0 and int(seg["cam_in_frame"]) == int(seg["cam_ticks"]), Sampler.camera_text(seg))
	s.queue_free()


# =================================================================================================================
# Helpers
# =================================================================================================================

## Static helpers (an inner class, so Sampler can call them too).
class Util:
	static func expectations(d: PlaytestDriver) -> Dictionary:
		var db := d.db()
		var canon: Dictionary = db.formula("movement")
		var tune_v: Variant = db.miso_table("movement")
		var tune: Dictionary = tune_v if tune_v is Dictionary else {}
		var c := d.character()
		var snap := StatCalculator.snapshot(c, db)
		var speed := float(snap.get("speed", 0))
		var jump := float(snap.get("jump", 0))
		var ws: Dictionary = canon.get("walk_speed", {})
		var base_speed := float(canon.get("base_speed", 0))
		var cap_speed := float(canon.get("speed_cap", 0))
		var base_px := float(ws.get("base_px_per_s", 0))
		var cap_px := float(ws.get("cap_px_per_s", 0))
		# The line through MeowDB's two published points (the formula itself) at the character's total Speed.
		var walk_px := base_px
		if cap_speed > base_speed:
			walk_px = base_px + (clampf(speed, 0.0, cap_speed) - base_speed) * (cap_px - base_px) / (cap_speed - base_speed)
		var climb_px := float((canon.get("climb_speed", {}) as Dictionary).get("base_px_per_s", 0)) + (speed - base_speed)
		var apex_px := 0.0
		for row: Dictionary in canon.get("jump_height_px_by_jump", []):
			if int(row.get("jump", -1)) == int(maxf(jump, float(canon.get("base_jump", 100)))):
				apex_px = float(row.get("height_px", 0))
		var g_px := float((canon.get("knockback_airtime", {}) as Dictionary).get("gravity_px_per_s2", 0))
		var apex := WorldScale.v(apex_px)
		var g := WorldScale.v(g_px)
		var airtime := 2.0 * sqrt(2.0 * apex / g) if g > 0.0 else 0.0
		var walk := WorldScale.h(walk_px)
		return {
			"speed_stat": speed, "jump_stat": jump,
			"walk_px": walk_px, "walk_mps": walk, "climb_px": climb_px, "climb_mps": WorldScale.v(climb_px),
			"apex_px": apex_px, "apex_m": apex, "gravity_px": g_px, "gravity_mps2": g, "airtime_s": airtime,
			"run_jump_m": walk * airtime,
			"ground_accel": float(tune.get("ground_accel_mps2", 0)), "ground_decel": float(tune.get("ground_decel_mps2", 0)),
			"air_accel": float(tune.get("air_accel_mps2", 0)), "coyote_s": float(tune.get("coyote_time_s", 0)),
			"jump_buffer_s": float(tune.get("jump_buffer_s", 0)), "step_up_m": float(tune.get("step_up_m", 0)),
			"floor_max_angle_deg": float(tune.get("floor_max_angle_deg", 0)),
			"climb_jump_off_fraction": float(tune.get("climb_jump_off_apex_fraction", 0)),
			"facing_turn_deg_s": float(tune.get("facing_turn_rate_deg_per_s", 0)),
			"reasons": tune.get("reasons", {}),
		}


	## The screen area the world shows: the viewport minus the HUD's status bar (bottom).
	static func play_rect(d: PlaytestDriver) -> Rect2:
		var vp := d.get_viewport().get_visible_rect().size
		var r := Rect2(Vector2.ZERO, vp)
		var hud := d.hud()
		if hud != null:
			for n in hud.find_children("*", "Control", true, false):
				if n is MisoStatusBar and (n as Control).is_visible_in_tree():
					var b := (n as Control).get_global_rect()
					if b.position.y > vp.y * 0.5:
						r.size.y = minf(r.size.y, b.position.y)
		return r


	## A flat, clear disc of `radius` m in the current map near its routes: {"ok", "center", "checked"}. Every 0.5 m grid
	## point of the disc has walkable ground within 3 cm of the centre's height, with a near-up normal, and room for the
	## body (the planning capsule clear).
	static func flat_spot(d: PlaytestDriver, radius: float, prefer: Vector3 = Vector3.INF) -> Dictionary:
		var w := d.world()
		var map_id := d.current_map()
		var def := w.defs.get_def(map_id)
		var cands: Array[Vector3] = []
		for r: Variant in def.sidecar.get("routes", []):
			var pts: Array = (r as Dictionary).get("points", [])
			for k in range(0, pts.size(), 2):
				var pt: Array = pts[k]
				cands.append(Vector3(float(pt[0]), float(pt[1]), float(pt[2])))
		if prefer != Vector3.INF:
			cands.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(prefer) < b.distance_squared_to(prefer))
		var space := w.ground_query.space
		var checked := 0
		for c in cands:
			checked += 1
			var g0 := _ground(space, w, c + Vector3.UP * 1.0, c - Vector3.UP * 2.0)
			if g0.is_empty():
				continue
			var y0: float = (g0["position"] as Vector3).y
			var ok := true
			var steps := int(ceil(radius / 0.5))
			for ix in range(-steps, steps + 1):
				for iz in range(-steps, steps + 1):
					var off := Vector3(ix * 0.5, 0.0, iz * 0.5)
					if off.length() > radius + 0.01:
						continue
					var q := Vector3(c.x, y0, c.z) + off
					var h := _ground(space, w, q + Vector3.UP * 1.6, q - Vector3.UP * 1.0)
					if h.is_empty() or absf((h["position"] as Vector3).y - y0) > 0.03 or (h["normal"] as Vector3).y < 0.995:
						ok = false
						break
					if not d.walker.standable(Vector3(q.x, y0, q.z)):
						ok = false
						break
				if not ok:
					break
			if ok:
				return {"ok": true, "center": Vector3(c.x, y0, c.z), "checked": checked}
		return {"ok": false, "center": Vector3.ZERO, "checked": checked}


	static func _ground(space: PhysicsDirectSpaceState3D, w: IslandWorld, from: Vector3, to: Vector3) -> Dictionary:
		var ray := PhysicsRayQueryParameters3D.create(from, to, PlaytestGridNav.FLOOR_MASK, w.ground_query.exclude)
		return space.intersect_ray(ray)


	## Composes frames (Images) into a sheet of `cols` columns, each scaled to `cell`. Returns the sheet.
	static func sheet(frames: Array, cols: int, cell: Vector2i) -> Image:
		var valid := frames.filter(func(x: Variant) -> bool: return x is Image)
		var rows := int(ceil(valid.size() / float(cols)))
		var out := Image.create(cols * cell.x, maxi(1, rows) * cell.y, false, Image.FORMAT_RGB8)
		out.fill(Color(0.1, 0.1, 0.1))
		var k := -1
		for fr: Variant in frames:
			if not (fr is Image):
				continue
			k += 1
			var i := k
			var img := (fr as Image).duplicate() as Image
			img.convert(Image.FORMAT_RGB8)
			img.resize(cell.x - 4, cell.y - 4, Image.INTERPOLATE_BILINEAR)
			out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((i % cols) * cell.x + 2, (i / cols) * cell.y + 2))
		return out


	## The last rendered frame, optionally cropped to a square of `crop_px` around the player's chest. Await it.
	static func grab(d: PlaytestDriver, crop_px: int = 0) -> Image:
		if DisplayServer.get_name() == "headless":
			return null
		await RenderingServer.frame_post_draw
		return crop_frame(d, d.get_viewport().get_texture().get_image(), crop_px)


	static func crop_frame(d: PlaytestDriver, img: Image, crop_px: int) -> Image:
		if img == null or crop_px <= 0:
			return img
		var rig := d.ctx().camera as CameraRig
		var p := d.player()
		var c := rig.camera.unproject_position(p.global_position + Vector3.UP * 0.75)
		var sz := img.get_size()
		var x := clampi(int(c.x) - crop_px / 2, 0, maxi(0, sz.x - crop_px))
		var y := clampi(int(c.y) - crop_px / 2, 0, maxi(0, sz.y - crop_px))
		return img.get_region(Rect2i(x, y, mini(crop_px, sz.x), mini(crop_px, sz.y)))


	## Saves `img` as <out>/shots/<name>.png and records it in the report. Returns the path.
	static func save_shot(d: PlaytestDriver, img: Image, shot_name: String, what: String) -> String:
		if img == null:
			d.note("shot %s skipped (headless)" % shot_name)
			return ""
		var dir := d.out_dir.path_join("shots")
		DirAccess.make_dir_recursive_absolute(dir)
		var path := dir.path_join("%s.png" % shot_name.validate_filename())
		var err := img.save_png(path)
		d.report.screenshots.append({"name": shot_name, "phase": d.phase, "path": path, "skipped": false, "error": error_string(err)})
		d.note("shot %s: %s (%s)" % [shot_name, path, what])
		return path


	## True for the collision of a prop (a *_hull* body: tree trunks, rocks, crates) or of the World_Forest chunk,
	## false for ground, walls, plinths and the island body.
	static func is_prop_collider(o: Object) -> bool:
		var n := o as Node
		var depth := 0
		while n != null and depth < 4:
			var nm := String(n.name).to_lower()
			if nm.contains("hull") or nm.begins_with("world_forest"):
				return true
			n = n.get_parent()
			depth += 1
		return false


	static func fmt_v(v: Vector3) -> String:
		return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


# =================================================================================================================
# Sampler
# =================================================================================================================

## Reads the game after every physics tick. begin(label) opens a segment, end() closes it and returns its counters.
## With `record` on, every tick is also kept as a row (rows[]) for the movement measurements.
class Sampler extends Node:
	var d: PlaytestDriver = null
	var walk_speed: float = 3.0
	var record: bool = false
	var rows: Array = []
	var seg: Dictionary = {}
	var segments: Array = []
	var camera_on: bool = true
	var monsters_on: bool = true
	## Frame captures (windowed): every `capture_every` process frames while > 0, cropped when capture_crop > 0.
	var capture_every: int = 0
	var capture_crop: int = 0
	var capture_max: int = 8
	var captures: Array = []
	var capture_times: PackedFloat32Array = []
	## When valid, a capture is taken only on frames where it returns true (and capture_every frames apart).
	var capture_when: Callable = Callable()
	var capture_notes: PackedStringArray = []
	## Set every tick: a monster within the near radius is hidden by terrain (both rays), and where.
	var last_hidden_monster: String = ""
	var last_hidden_monster_screen: Vector2 = Vector2.INF
	## When valid, a crop is centred on the screen point it returns (instead of the player).
	var capture_center: Callable = Callable()
	## True while a snag (see SNAG_MIN_TICKS) or a deflection is in progress.
	var snag_now: bool = false
	var _last_capture_frame: int = -100000
	## Events seen (all segments): [frame, kind, detail].
	var events: Array = []

	var _player: PlayerController = null
	var _session: Node = null
	var _rect: Rect2 = Rect2()
	var _rect_map: String = ""
	var _prev_focus: Vector3 = Vector3.INF
	var _prev_cam_v: Vector3 = Vector3.ZERO
	var _prev_pos: Vector3 = Vector3.INF
	var _prev_state: String = ""
	var _since_transition: int = 1000
	var _jumped_tick: int = -100
	var _climb_end_tick: int = -100
	var _air_start_y: float = 0.0
	var _air_cause: String = ""
	var _snag_run: int = 0
	var _deflect_run: int = 0
	var _frame_counter: int = 0
	var _ray: PhysicsRayQueryParameters3D = null

	func setup(p_d: PlaytestDriver) -> void:
		d = p_d
		name = "FeelSampler"
		process_physics_priority = 1000
		process_priority = 1000
		process_mode = Node.PROCESS_MODE_PAUSABLE
		_session = d.session()
		if _session != null:
			_session.connect(&"transition_finished", func(_r: Variant) -> void:
				_since_transition = 0
				events.append([Engine.get_physics_frames(), "transition", d.current_map()]))

	func _connect_player(p: PlayerController) -> void:
		_player = p
		walk_speed = p.model.walk_speed
		p.jumped.connect(func() -> void:
			_jumped_tick = Engine.get_physics_frames()
			events.append([_jumped_tick, "jumped", Util.fmt_v(p.global_position)])
			if not seg.is_empty():
				seg["jumps"] = int(seg["jumps"]) + 1)
		p.landed.connect(func(fall_speed: float) -> void:
			events.append([Engine.get_physics_frames(), "landed", "%.2f" % fall_speed]))
		p.climb_started.connect(func(c: ClimbableDef) -> void:
			events.append([Engine.get_physics_frames(), "climb_start", c.name])
			if not seg.is_empty():
				seg["climbs"] = int(seg["climbs"]) + 1)
		p.climb_ended.connect(func(c: ClimbableDef, how: StringName) -> void:
			_climb_end_tick = Engine.get_physics_frames()
			events.append([_climb_end_tick, "climb_end", "%s %s" % [c.name, how]])
			if not seg.is_empty():
				var by: Dictionary = seg["climb_ends"]
				by[String(how)] = int(by.get(String(how), 0)) + 1)
		p.teleported.connect(func(_x: Transform3D) -> void:
			_since_transition = 0
			events.append([Engine.get_physics_frames(), "teleported", Util.fmt_v(p.global_position)]))
		p.knocked_back.connect(func(_dir: Vector3) -> void:
			events.append([Engine.get_physics_frames(), "knocked_back", Util.fmt_v(p.global_position)])
			if not seg.is_empty():
				seg["knockbacks"] = int(seg["knockbacks"]) + 1)

	static func new_seg(label: String) -> Dictionary:
		return {"label": label, "map": "", "ticks": 0, "idle_ticks": 0, "ground_ticks": 0, "air_ticks": 0,
			"climb_ticks": 0, "input_ticks": 0, "moving_ticks": 0, "speed_sum": 0.0,
			"snags": 0, "snag_ticks": 0, "snag_where": [], "deflects": 0, "deflect_ticks": 0, "deflect_where": [],
			"drops": 0, "drop_max_m": 0.0, "drop_where": [], "step_ups": 0, "step_up_max_m": 0.0, "step_downs": 0,
			"slope_ticks": 0, "slope_ratio_sum": 0.0, "slope_max_deg": 0.0,
			"jumps": 0, "climbs": 0, "climb_ends": {}, "knockbacks": 0, "hitstun_ticks": 0,
			"cam_ticks": 0, "cam_in_frame": 0, "cam_visible": 0, "cam_occluded": 0, "cam_terrain": 0, "cam_fader": 0,
			"cam_min_margin_px": INF, "cam_near_edge": 0, "cam_max_off": Vector2.ZERO, "cam_off_sum": Vector2.ZERO,
			"cam_clamped": 0, "cam_pops": 0, "cam_max_step_m": 0.0, "cam_jerks": 0, "cam_max_jerk": 0.0,
			"cam_lag_sum": 0.0, "cam_lag_max": 0.0, "cam_out_where": [], "cam_edge_where": [], "cam_jerk_where": [],
			"mon_near": 0, "mon_near_in": 0, "mon_near_partial": 0, "mon_near_terrain": 0, "mon_near_terrain_partial": 0,
			"mon_mid": 0, "mon_mid_in": 0, "mon_hidden_where": [], "mon_out_where": [], "mon_near_prop": 0, "mon_prop_where": []}

	func begin(label: String) -> void:
		if not seg.is_empty():
			end()
		seg = new_seg(label)
		seg["map"] = d.current_map()
		_snag_run = 0
		_deflect_run = 0

	func end() -> Dictionary:
		var s := seg
		seg = {}
		if not s.is_empty():
			segments.append(s)
		return s

	func _process(_delta: float) -> void:
		if capture_every <= 0 or captures.size() >= capture_max or DisplayServer.get_name() == "headless":
			return
		_frame_counter += 1
		if capture_when.is_valid():
			if _frame_counter - _last_capture_frame < capture_every or not bool(capture_when.call()):
				return
		elif _frame_counter % capture_every != 0:
			return
		_last_capture_frame = _frame_counter
		var img := d.get_viewport().get_texture().get_image()
		if capture_center.is_valid() and capture_crop > 0:
			var c: Vector2 = capture_center.call()
			var sz := img.get_size()
			var x := clampi(int(c.x) - capture_crop / 2, 0, maxi(0, sz.x - capture_crop))
			var y := clampi(int(c.y) - capture_crop / 2, 0, maxi(0, sz.y - capture_crop))
			captures.append(img.get_region(Rect2i(x, y, mini(capture_crop, sz.x), mini(capture_crop, sz.y))))
		else:
			captures.append(Util.crop_frame(d, img, capture_crop))
		capture_times.append(d.game_s())
		var pl := d.player()
		capture_notes.append("%.2f s %s %s%s" % [d.game_s(), d.current_map(), Util.fmt_v(_local(pl.global_position)) if pl != null else "",
			(" (monster " + last_hidden_monster + ")") if capture_center.is_valid() else ""])

	func start_capture(every_frames: int, max_frames: int, crop_px: int, when: Callable = Callable()) -> void:
		captures.clear()
		capture_times.clear()
		capture_notes.clear()
		capture_when = when
		_last_capture_frame = -100000
		capture_every = every_frames
		capture_max = max_frames
		capture_crop = crop_px
		_frame_counter = every_frames - 1  # the first capture is the next frame

	func stop_capture() -> Array:
		capture_every = 0
		capture_when = Callable()
		capture_center = Callable()
		return captures.duplicate()

	func _physics_process(_delta: float) -> void:
		var p := d.player()
		if p == null or not is_instance_valid(p) or not p.is_inside_tree():
			return
		if p != _player:
			_connect_player(p)
		_since_transition += 1
		var f := Engine.get_physics_frames()
		var idle := _session != null and bool(_session.call("is_idle"))
		var pos := p.global_position
		var hv := Vector3(p.actual_velocity.x, 0.0, p.actual_velocity.z)
		var spd := hv.length()
		var st := "climb" if p.is_climbing() else ("ground" if p.is_grounded() else "air")
		var mv := Vector2(Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
			Input.get_action_strength(&"move_up") - Input.get_action_strength(&"move_down")).limit_length(1.0)
		var wish := p.view_right * mv.x + p.view_forward * mv.y
		wish.y = 0.0
		var rig := d.ctx().camera as CameraRig if d.ctx() != null else null
		var focus := rig.focus_point() if rig != null else Vector3.ZERO
		if record:
			var row := {"f": f, "pos": pos, "hv": hv, "spd": spd, "st": st, "wish": wish, "vy": p.vertical_speed,
				"facing": p.facing, "idle": idle, "focus": focus, "climbing": p.is_climbing(), "hitstun": p.in_hitstun,
				"map": d.current_map(), "view": rig.camera.size if rig != null else 0.0}
			var vis := p.get_node_or_null(^"Visual") as Node3D
			if vis != null:
				row["yaw"] = vis.rotation.y
			if rig != null:
				row["scr_feet"] = rig.camera.unproject_position(pos)
				row["scr_head"] = rig.camera.unproject_position(pos + Vector3.UP * p.model.body_height)
			rows.append(row)
		if not seg.is_empty():
			_accumulate(p, rig, f, idle, pos, hv, spd, st, wish, focus)
		_prev_state = st
		_prev_pos = pos

	func _accumulate(p: PlayerController, rig: CameraRig, f: int, idle: bool, pos: Vector3, hv: Vector3, spd: float,
			st: String, wish: Vector3, focus: Vector3) -> void:
		var s := seg
		s["ticks"] = int(s["ticks"]) + 1
		if not idle:
			_snag_run = 0
			_deflect_run = 0
			_prev_focus = Vector3.INF
			return
		s["idle_ticks"] = int(s["idle_ticks"]) + 1
		if p.in_hitstun:
			s["hitstun_ticks"] = int(s["hitstun_ticks"]) + 1
		var local := _local(pos)
		# --- movement ---
		s[st + "_ticks"] = int(s[st + "_ticks"]) + 1
		var wl := wish.length()
		if wl > 0.5:
			s["input_ticks"] = int(s["input_ticks"]) + 1
		if st == "ground" and wl > 0.5 and spd > 0.3:
			s["moving_ticks"] = int(s["moving_ticks"]) + 1
			s["speed_sum"] = float(s["speed_sum"]) + spd / walk_speed
		if st == "ground" and not p.in_hitstun and wl > 0.5 and spd < SNAG_SPEED_FRACTION * walk_speed * wl:
			_snag_run += 1
			if _snag_run == SNAG_MIN_TICKS:
				s["snags"] = int(s["snags"]) + 1
				_where(s, "snag_where", local)
			if _snag_run >= SNAG_MIN_TICKS:
				s["snag_ticks"] = int(s["snag_ticks"]) + (SNAG_MIN_TICKS if _snag_run == SNAG_MIN_TICKS else 1)
		else:
			_snag_run = 0
		if st == "ground" and not p.in_hitstun and wl > 0.5 and spd > 0.3 \
				and rad_to_deg(hv.angle_to(wish)) > DEFLECT_DEG:
			_deflect_run += 1
			if _deflect_run == DEFLECT_MIN_TICKS:
				s["deflects"] = int(s["deflects"]) + 1
				_where(s, "deflect_where", local)
			if _deflect_run >= DEFLECT_MIN_TICKS:
				s["deflect_ticks"] = int(s["deflect_ticks"]) + (DEFLECT_MIN_TICKS if _deflect_run == DEFLECT_MIN_TICKS else 1)
		else:
			_deflect_run = 0
		snag_now = _snag_run >= SNAG_MIN_TICKS or _deflect_run >= DEFLECT_MIN_TICKS
		if _prev_pos != Vector3.INF and _since_transition > 2:
			var dy := pos.y - _prev_pos.y
			if st == "ground" and _prev_state == "ground":
				if dy > STEP_UP_MIN_M:
					s["step_ups"] = int(s["step_ups"]) + 1
					s["step_up_max_m"] = maxf(float(s["step_up_max_m"]), dy)
				elif dy < -STEP_UP_MIN_M:
					s["step_downs"] = int(s["step_downs"]) + 1
			if _prev_state == "ground" and st == "air":
				_air_start_y = _prev_pos.y
				if f - _jumped_tick <= 1:
					_air_cause = "jump"
				elif p.in_hitstun:
					_air_cause = "knockback"
				else:
					_air_cause = "walk_off"
			elif _prev_state == "climb" and st == "air":
				_air_start_y = pos.y
				_air_cause = "climb_exit"
			if _prev_state == "air" and st == "ground" and _air_cause == "walk_off":
				var h := _air_start_y - pos.y
				s["drops"] = int(s["drops"]) + 1
				s["drop_max_m"] = maxf(float(s["drop_max_m"]), h)
				_where(s, "drop_where", local, "%.2f m" % h)
		if st == "ground" and wl > 0.9 and spd > 0.3:
			var ang := rad_to_deg(acos(clampf(p.floor_normal.y, -1.0, 1.0)))
			if ang > SLOPE_MIN_DEG:
				s["slope_ticks"] = int(s["slope_ticks"]) + 1
				s["slope_ratio_sum"] = float(s["slope_ratio_sum"]) + spd / (walk_speed * wl)
				s["slope_max_deg"] = maxf(float(s["slope_max_deg"]), ang)
		# --- camera ---
		if rig != null and camera_on and _since_transition > POST_TRANSITION_TICKS:
			_camera(p, rig, pos, focus, local)
		elif rig != null:
			_prev_focus = focus
		if rig != null and monsters_on:
			_monsters(p, rig, pos)

	func _camera(p: PlayerController, rig: CameraRig, pos: Vector3, focus: Vector3, local: Vector3) -> void:
		var s := seg
		var cam := rig.camera
		if _rect_map != d.current_map() or _rect.size == Vector2.ZERO:
			_rect = Util.play_rect(d)
			_rect_map = d.current_map()
		var r := rig.ground_right
		var hgt := p.model.body_height
		var pts := [pos, pos + Vector3.UP * hgt, pos + r * 0.4 + Vector3.UP * 0.75, pos - r * 0.4 + Vector3.UP * 0.75,
			pos + r * 0.4 + Vector3.UP * hgt, pos - r * 0.4 + Vector3.UP * hgt, pos + r * 0.4, pos - r * 0.4]
		var margin := INF
		for q: Vector3 in pts:
			var sp := cam.unproject_position(q)
			margin = minf(margin, minf(minf(sp.x - _rect.position.x, _rect.end.x - sp.x), minf(sp.y - _rect.position.y, _rect.end.y - sp.y)))
		s["cam_ticks"] = int(s["cam_ticks"]) + 1
		var in_frame := margin >= 0.0
		if in_frame:
			s["cam_in_frame"] = int(s["cam_in_frame"]) + 1
		else:
			_where(s, "cam_out_where", local, "%.0f px" % margin)
		s["cam_min_margin_px"] = minf(float(s["cam_min_margin_px"]), margin)
		if margin < 0.1 * minf(_rect.size.x, _rect.size.y):
			s["cam_near_edge"] = int(s["cam_near_edge"]) + 1
			_where(s, "cam_edge_where", local, "%.0f px" % margin)
		var occluded := rig.player_occluded()
		var fader := rig.fader != null and rig.fader.player_covered
		var terrain := rig.terrain_hides(pos)
		if occluded:
			s["cam_occluded"] = int(s["cam_occluded"]) + 1
		if terrain:
			s["cam_terrain"] = int(s["cam_terrain"]) + 1
		if fader:
			s["cam_fader"] = int(s["cam_fader"]) + 1
		if in_frame and not occluded:
			s["cam_visible"] = int(s["cam_visible"]) + 1
		var chest := cam.unproject_position(pos + Vector3.UP * 0.75)
		var full_vp := d.get_viewport().get_visible_rect().size
		var off := (chest - full_vp * 0.5) / (full_vp * 0.5)
		var mo: Vector2 = s["cam_max_off"]
		s["cam_max_off"] = Vector2(maxf(mo.x, absf(off.x)), maxf(mo.y, absf(off.y)))
		s["cam_off_sum"] = (s["cam_off_sum"] as Vector2) + off.abs()
		# Clamped: the bounds moved the focus away from where the dead-zone follow wanted it.
		var center := CameraMath.to_plane(focus, rig.ground_right, rig.ground_forward)
		var anchor := CameraMath.to_plane(p.follow_anchor(), rig.ground_right, rig.ground_forward)
		var half := rig.view_half_extents()
		var want := CameraMath.dead_zone_follow(center, anchor, half * float(rig.config.get("dead_zone_fraction", 0.15)))
		var br := rig.bounds_rect()
		if br.size != Vector2.ZERO:
			var cl := CameraMath.clamp_focus(want, br, half, float(rig.config.get("overscan_m", 6.0)))
			if cl.distance_to(want) > 0.05:
				s["cam_clamped"] = int(s["cam_clamped"]) + 1
		var lag := (anchor - center).length()
		s["cam_lag_sum"] = float(s["cam_lag_sum"]) + lag
		s["cam_lag_max"] = maxf(float(s["cam_lag_max"]), lag)
		if _prev_focus != Vector3.INF:
			var step := focus - _prev_focus
			var cam_v := step * Engine.physics_ticks_per_second
			var stepm := step.length()
			s["cam_max_step_m"] = maxf(float(s["cam_max_step_m"]), stepm)
			if stepm > CAM_POP_M:
				s["cam_pops"] = int(s["cam_pops"]) + 1
			var jerk := (cam_v - _prev_cam_v).length()
			s["cam_max_jerk"] = maxf(float(s["cam_max_jerk"]), jerk)
			if jerk > CAM_JERK_MPS:
				s["cam_jerks"] = int(s["cam_jerks"]) + 1
				_where(s, "cam_jerk_where", local, "%.1f m/s, %s" % [jerk, "climbing" if p.is_climbing() else ("air" if not p.is_grounded() else "ground")])
			_prev_cam_v = cam_v
		_prev_focus = focus

	func _monsters(p: PlayerController, rig: CameraRig, pos: Vector3) -> void:
		var ms := d.monsters()
		if ms == null:
			return
		var s := seg
		var cam := rig.camera
		if _ray == null:
			_ray = PhysicsRayQueryParameters3D.new()
			_ray.collision_mask = WorldLayers.WALKABLE | WorldLayers.BLOCKING | WorldLayers.SCENERY
			_ray.hit_back_faces = true
		last_hidden_monster = ""
		var back := rig.view_basis.z
		var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
		for m: Node3D in ms.call("live_monsters"):
			if not is_instance_valid(m) or not bool(m.call("is_alive")):
				continue
			var mp := m.global_position
			var dist := Vector2(mp.x - pos.x, mp.z - pos.z).length()
			if dist > MID_MONSTER_M or absf(mp.y - pos.y) > 6.0:
				continue
			var size := Vector2(0.8, 1.0)
			var def: Variant = m.get("def")
			if def is Object and (def as Object).get("sprite_size_m") is Vector2:
				size = (def as Object).get("sprite_size_m")
			var r := rig.ground_right * size.x * 0.5
			var pts := [mp, mp + Vector3.UP * size.y, mp + r + Vector3.UP * size.y * 0.5, mp - r + Vector3.UP * size.y * 0.5]
			var inside := 0
			for q: Vector3 in pts:
				var sp := cam.unproject_position(q)
				if _rect.has_point(sp):
					inside += 1
			if dist > NEAR_MONSTER_M or absf(mp.y - pos.y) > NEAR_MONSTER_DY_M:
				s["mon_mid"] = int(s["mon_mid"]) + 1
				if inside == pts.size():
					s["mon_mid_in"] = int(s["mon_mid_in"]) + 1
				continue
			s["mon_near"] = int(s["mon_near"]) + 1
			if inside == pts.size():
				s["mon_near_in"] = int(s["mon_near_in"]) + 1
			elif inside > 0:
				s["mon_near_partial"] = int(s["mon_near_partial"]) + 1
			else:
				_where(s, "mon_out_where", _local(mp), String(m.get("def").get("id")) if def != null else "?")
			var hits := 0
			var props := 0
			var names := PackedStringArray()
			for h: float in [0.5, 0.9]:
				_ray.from = mp + Vector3.UP * size.y * h
				_ray.to = _ray.from + back * 60.0
				var hit := space.intersect_ray(_ray)
				if not hit.is_empty():
					hits += 1
					var cn := String((hit["collider"] as Node).name) if hit["collider"] is Node else "?"
					names.append(cn)
					if Util.is_prop_collider(hit["collider"]):
						props += 1
			if hits == 2 and props == 0:
				# Ground, walls, plinths, the island body: none of them fades, and monsters have no X-ray.
				last_hidden_monster = "%s at %s behind %s" % [String(m.get("def").get("id")) if def != null else "?", Util.fmt_v(_local(mp)), names[0]]
				last_hidden_monster_screen = cam.unproject_position(mp + Vector3.UP * size.y * 0.5)
				s["mon_near_terrain"] = int(s["mon_near_terrain"]) + 1
				_where(s, "mon_hidden_where", _local(mp), "%s at %.1f m behind %s, player %s" % [
					String(m.get("def").get("id")) if def != null else "?", dist, ",".join(names), Util.fmt_v(_local(pos))])
			elif hits == 2:
				# A prop hull (tree trunk, rock, crate) between the monster and the camera: trees fade, rocks do not.
				s["mon_near_prop"] = int(s.get("mon_near_prop", 0)) + 1
				_where(s, "mon_prop_where", _local(mp), ",".join(names))
			elif hits == 1:
				s["mon_near_terrain_partial"] = int(s["mon_near_terrain_partial"]) + 1

	func _local(pos: Vector3) -> Vector3:
		var w := d.world()
		var m := d.current_map()
		if w != null and w.defs.has_map(m):
			return w.defs.get_def(m).to_local(pos)
		return pos

	static func _where(s: Dictionary, key: String, local: Vector3, extra: String = "") -> void:
		var arr: Array = s[key]
		if arr.size() < WHERE_MAX:
			arr.append("%s local %s%s" % [s["map"], Util.fmt_v(local), (" " + extra) if extra != "" else ""])

	## One line of a segment's movement counters.
	static func move_text(s: Dictionary) -> String:
		var mt := maxi(1, int(s["moving_ticks"]))
		return "%s: %d ticks (%.1f s), snags %d (%.2f s), deflections %d (%.2f s), drops %d (max %.2f m), step-ups %d (max %.2f m), slope ticks %d (speed %.1f%% of walk, max %.0f deg), jumps %d, climbs %d %s, knockbacks %d, mean speed while moving %.1f%%" % [
			s["label"], int(s["ticks"]), int(s["ticks"]) / 60.0, int(s["snags"]), int(s["snag_ticks"]) / 60.0,
			int(s["deflects"]), int(s["deflect_ticks"]) / 60.0, int(s["drops"]), float(s["drop_max_m"]),
			int(s["step_ups"]), float(s["step_up_max_m"]), int(s["slope_ticks"]),
			100.0 * float(s["slope_ratio_sum"]) / maxf(1.0, float(s["slope_ticks"])), float(s["slope_max_deg"]),
			int(s["jumps"]), int(s["climbs"]), str(s["climb_ends"]), int(s["knockbacks"]), 100.0 * float(s["speed_sum"]) / mt]

	## One line of a segment's camera counters.
	static func camera_text(s: Dictionary) -> String:
		var ct := maxi(1, int(s["cam_ticks"]))
		var mo: Vector2 = s["cam_max_off"]
		var so: Vector2 = s["cam_off_sum"]
		return "%s: %d camera ticks, in frame %.1f%%, fully visible %.1f%%, occluded %.1f%% (fader %.1f%%, terrain %.1f%%), min margin %.0f px, near edge %d, max off-centre (%.2f, %.2f) of half-screen, mean (%.2f, %.2f), clamped %.1f%%, player offset from the view centre (ground) mean %.2f m max %.2f m, pops %d (max step %.3f m), jerks %d (max %.1f m/s per tick); monsters <= 8 m and <= 3 m up/down: %d samples, in frame %.1f%%, partly %.1f%%, hidden by terrain %.1f%% (+%.1f%% partly), behind a prop hull %.1f%%; farther (8-12 m, or 3-6 m up/down): %d samples, in frame %.1f%%" % [
			s["label"], int(s["cam_ticks"]), 100.0 * int(s["cam_in_frame"]) / ct, 100.0 * int(s["cam_visible"]) / ct,
			100.0 * int(s["cam_occluded"]) / ct, 100.0 * int(s["cam_fader"]) / ct, 100.0 * int(s["cam_terrain"]) / ct,
			float(s["cam_min_margin_px"]), int(s["cam_near_edge"]), mo.x, mo.y, so.x / ct, so.y / ct,
			100.0 * int(s["cam_clamped"]) / ct, float(s["cam_lag_sum"]) / ct, float(s["cam_lag_max"]), int(s["cam_pops"]),
			float(s["cam_max_step_m"]), int(s["cam_jerks"]), float(s["cam_max_jerk"]), int(s["mon_near"]),
			100.0 * int(s["mon_near_in"]) / maxf(1.0, int(s["mon_near"])),
			100.0 * int(s["mon_near_partial"]) / maxf(1.0, int(s["mon_near"])),
			100.0 * int(s["mon_near_terrain"]) / maxf(1.0, int(s["mon_near"])),
			100.0 * int(s["mon_near_terrain_partial"]) / maxf(1.0, int(s["mon_near"])),
			100.0 * int(s.get("mon_near_prop", 0)) / maxf(1.0, int(s["mon_near"])), int(s["mon_mid"]),
			100.0 * int(s["mon_mid_in"]) / maxf(1.0, int(s["mon_mid"]))]

	## Sums segments into one (counts add, maxima take the max, lists concatenate up to WHERE_MAX).
	static func merge(label: String, list: Array) -> Dictionary:
		var out := new_seg(label)
		for s: Dictionary in list:
			for k: String in out:
				if k in ["label", "map"]:
					continue
				var a: Variant = out[k]
				var b: Variant = s.get(k)
				if b == null:
					continue
				if k.ends_with("_max_m") or k.ends_with("_max") or k == "cam_max_step_m" or k == "cam_max_jerk" or k == "slope_max_deg":
					out[k] = maxf(float(a), float(b))
				elif k == "cam_min_margin_px":
					out[k] = minf(float(a), float(b))
				elif k == "cam_max_off":
					out[k] = Vector2(maxf((a as Vector2).x, (b as Vector2).x), maxf((a as Vector2).y, (b as Vector2).y))
				elif a is Array:
					for e: Variant in b:
						if (a as Array).size() < WHERE_MAX:
							(a as Array).append(e)
				elif a is Dictionary:
					for kk: Variant in b:
						(a as Dictionary)[kk] = int((a as Dictionary).get(kk, 0)) + int((b as Dictionary)[kk])
				elif a is Vector2:
					out[k] = (a as Vector2) + (b as Vector2)
				elif a is float:
					out[k] = float(a) + float(b)
				else:
					out[k] = int(a) + int(b)
		return out
