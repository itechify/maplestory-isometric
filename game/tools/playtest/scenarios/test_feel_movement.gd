extends PlaytestScenario
## test_feel_movement: the brief's Movement Review, measured in the real game (main.tscn) with real key events
## (W A S D, Space, Up, Down through Input.parse_input_event; the player keeps its KeyboardInput). A Sampler
## (test_feel_common.gd) reads the player and the camera after every physics tick (--fixed-fps 60: 1 tick = 1/60 s).
##
## On a flat, clear disc found on foot in the start map (000000001; Mushroom Town or Southperry when it has none):
##   - start and stop: hold one key 0.7 s, release: ticks from the key press to motion and to >= 99% of the walk speed,
##     plateau speed, stop ticks and distance after the release, on-screen speed and direction (8 directions);
##   - diagonal vs cardinal plateau speed; 180, 90 and 45 degree turns (ticks to full speed the new way, and the
##     model's visual turn);
##   - standing jump (apex, airtime, on-screen rise, camera height during it), held jump (hold-to-rejump), running
##     jump length, air control (reverse mid-air, standing drift, no input), jump buffer;
##   - the ladder on the bluff (Up to grab, climb, top exit, Down from the top, foot exit, jump off sideways).
## Expectations come from the data: MeowDB walk/climb speed, jump table and gravity (formulas/movement.json, through
## WorldScale) and the adaptation values (misostory/movement.json). Windowed runs also write frame sheets of the
## jumps and the ladder. Results: report notes and <out>/feel_movement.json.

const Lib := preload("res://tools/playtest/scenarios/test_feel_common.gd")
const START_MAP := "000000001"
const TOWN := "000000010"
const FALLBACK_MAP := "000000060"
const LADDER := "WestEntranceMushroomTown_0_Ladder_Bluff"
const DISC_M := 3.0
const RUN_S := 0.7
const TPS := 60.0

var S: Lib.Sampler = null
var E: Dictionary = {}
var center: Vector3 = Vector3.ZERO
var results: Dictionary = {}
var K_UP: Key = KEY_W
var K_DOWN: Key = KEY_S
var K_LEFT: Key = KEY_A
var K_RIGHT: Key = KEY_D
var K_JUMP: Key = KEY_SPACE
var K_CLIMB_UP: Key = KEY_UP
var K_CLIMB_DOWN: Key = KEY_DOWN


func description() -> String:
	return "Movement Review: start/stop, 8 directions, turns, jumps, air control, jump buffer, ladder (real keys, per-tick sampling)"


func max_seconds() -> float:
	return 900.0


func run(d: PlaytestDriver) -> void:
	K_UP = PlaytestInput.key_for_action(&"move_up")
	K_DOWN = PlaytestInput.key_for_action(&"move_down")
	K_LEFT = PlaytestInput.key_for_action(&"move_left")
	K_RIGHT = PlaytestInput.key_for_action(&"move_right")
	K_JUMP = PlaytestInput.key_for_action(&"jump")
	K_CLIMB_UP = PlaytestInput.key_for_action(&"portal_enter")
	K_CLIMB_DOWN = PlaytestInput.key_for_action(&"climb_down")
	var ng: Dictionary = await d.new_game("Feel", "female", "541", {})
	if not d.check("new game through the title and creation screens", bool(ng["ok"]) and ng["via"] == "screen", String(ng["why"])):
		return
	E = Lib.Util.expectations(d)
	var ex := E.duplicate()
	ex.erase("reasons")
	results["expect"] = ex
	d.note("expectations (canonical through WorldScale; adaptation from movement.json): %s" % JSON.stringify(ex))
	S = Lib.Sampler.new()
	S.setup(d)
	S.monsters_on = false
	d.add_child(S)
	var p := d.player()
	var canon: Dictionary = d.db().formula("movement")
	d.check("the new character has the canonical base Speed and Jump", int(E["speed_stat"]) == int(canon.get("base_speed", -1))
		and int(E["jump_stat"]) == int(canon.get("base_jump", -1)), "Speed %d, Jump %d" % [int(E["speed_stat"]), int(E["jump_stat"])])

	if not await _find_flat(d):
		return
	await _axes(d)
	await _turns(d)
	await _jumps(d)
	await _air_control(d)
	await _jump_buffer(d)
	await _ladder(d)
	_write(d)


# =================================================================================================================
# Flat ground
# =================================================================================================================

func _find_flat(d: PlaytestDriver) -> bool:
	var p := d.player()
	var spot := Lib.Util.flat_spot(d, DISC_M, p.global_position)
	if not bool(spot["ok"]):
		d.note("no flat %.1f m disc in %s (%d route points checked): walking to %s" % [DISC_M, d.current_map(), int(spot["checked"]), TOWN])
		var t: Dictionary = await d.walk_trail(START_MAP, TOWN)
		if bool(t["ok"]):
			spot = Lib.Util.flat_spot(d, DISC_M, p.global_position)
	if not bool(spot["ok"]):
		await d.console("warp %s" % FALLBACK_MAP)
		spot = Lib.Util.flat_spot(d, DISC_M, d.player().global_position)
	if not d.check("a flat, clear %.1f m disc to measure on" % DISC_M, bool(spot["ok"]), "%s, %d candidates" % [d.current_map(), int(spot["checked"])]):
		return false
	center = spot["center"]
	results["flat_spot"] = {"map": d.current_map(), "world": Lib.Util.fmt_v(center),
		"local": Lib.Util.fmt_v(d.world().defs.get_def(d.current_map()).to_local(center))}
	var w: Dictionary = await d.walk_to(center, {"within_m": 0.4, "max_s": 60.0})
	d.check("walked to the measuring spot", bool(w["ok"]), "%s %s" % [d.current_map(), Lib.Util.fmt_v(center)])
	await _recenter(d)
	return true


func _recenter(d: PlaytestDriver) -> void:
	var p := d.player()
	if _flat(p.global_position - center) > 0.6:
		await d.walk_to(center, {"within_m": 0.4, "max_s": 15.0})
	if _flat(p.global_position - center) > 0.12:
		await d.walker.nudge_until(center, func() -> bool: return _flat(d.player().global_position - center) < 0.12)
	await d.wait(0.3)


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


# =================================================================================================================
# Start, stop, directions
# =================================================================================================================

func _axes(d: PlaytestDriver) -> void:
	var pairs := [
		["right (D)", [K_RIGHT], Vector2(1, 0), "left (A)", [K_LEFT], Vector2(-1, 0)],
		["up (W)", [K_UP], Vector2(0, 1), "down (S)", [K_DOWN], Vector2(0, -1)],
		["up-right (W+D)", [K_UP, K_RIGHT], Vector2(1, 1), "down-left (S+A)", [K_DOWN, K_LEFT], Vector2(-1, -1)],
		["up-left (W+A)", [K_UP, K_LEFT], Vector2(-1, 1), "down-right (S+D)", [K_DOWN, K_RIGHT], Vector2(1, -1)],
	]
	var moves := {}
	for pr: Array in pairs:
		await _recenter(d)
		moves[pr[0]] = await _measure_move(d, pr[0], pr[1], pr[2])
		moves[pr[3]] = await _measure_move(d, pr[3], pr[4], pr[5])
	results["moves"] = moves
	var walk := float(E["walk_mps"])
	var card := []
	var diag := []
	for k: String in moves:
		var m: Dictionary = moves[k]
		(diag if k.contains("+") else card).append(float(m["plateau_mps"]))
	var card_mean := _mean(card)
	var diag_mean := _mean(diag)
	results["cardinal_mps"] = card_mean
	results["diagonal_mps"] = diag_mean
	var r: Dictionary = moves["right (D)"]
	d.check("walk speed = MeowDB %.0f px/s x WorldScale.h = %.3f m/s (measured %.3f m/s, all 8 directions within 1%%)" % [
		float(E["walk_px"]), walk, card_mean], _all_within(moves, "plateau_mps", walk, 0.01), _list(moves, "plateau_mps"))
	d.check("diagonals walk as fast as cardinals (normalized): %.3f vs %.3f m/s" % [diag_mean, card_mean],
		absf(diag_mean - card_mean) <= 0.01 * card_mean)
	var accel_ticks := ceili(walk / (float(E["ground_accel"]) / TPS) - 0.001)
	var decel_ticks := ceili(walk / (float(E["ground_decel"]) / TPS) - 0.001)
	d.check("full speed %d ticks after the key press (movement.json ground_accel %.0f m/s2: %d ticks)" % [int(r["full_ticks"]),
		float(E["ground_accel"]), accel_ticks], _all_eq(moves, "full_ticks", accel_ticks), _list(moves, "full_ticks"))
	d.check("stopped %d ticks after the key release (movement.json ground_decel %.0f m/s2: %d ticks)" % [int(r["stop_ticks"]),
		float(E["ground_decel"]), decel_ticks], _all_le(moves, "stop_ticks", decel_ticks + 1), _list(moves, "stop_ticks"))
	d.soft_check("stop distance after release <= 0.10 m in every direction", _all_le(moves, "stop_m", 0.10), _list(moves, "stop_m"))
	d.soft_check("D walks straight across the screen and W straight up it (screen direction within 3 deg)",
		absf(float((moves["right (D)"] as Dictionary)["screen_deg"])) <= 3.0 and absf(float((moves["up (W)"] as Dictionary)["screen_deg"]) - 90.0) <= 3.0,
		_list(moves, "screen_deg"))
	d.note("on-screen walk speed (camera-fixed projection): %s; screen directions %s; character height on screen %.0f px; view %s m tall at %s" % [
		_list(moves, "screen_pxps"), _list(moves, "screen_deg"), float((moves["right (D)"] as Dictionary)["char_px"]),
		str((moves["right (D)"] as Dictionary)["view_size_m"]), str((moves["right (D)"] as Dictionary)["viewport"])])


func _measure_move(d: PlaytestDriver, label: String, keys: Array, mv: Vector2) -> Dictionary:
	var p := d.player()
	var want := p.view_right * mv.x + p.view_forward * mv.y
	want.y = 0.0
	want = want.normalized()
	var i := d._begin(PlaytestReport.KIND_PLAY, "feel_move", "%s: hold %.2f s, release" % [label, RUN_S])
	S.rows.clear()
	S.record = true
	await d.wait(0.1)
	var f0 := Engine.get_physics_frames()
	for k: Key in keys:
		d.input.key_down(k)
	await d.wait(RUN_S)
	var f1 := Engine.get_physics_frames()
	for k: Key in keys:
		d.input.key_up(k)
	await d.wait(0.8)
	S.record = false
	var r := _analyze_move(S.rows, f0, f1, want, mv)
	r["label"] = label
	_screen_motion(d, r)
	d._end(i, int(r["full_ticks"]) > 0, String(r["text"]))
	d.note("move %s" % r["text"])
	return r


func _analyze_move(rows: Array, f0: int, f1: int, want: Vector3, mv: Vector2) -> Dictionary:
	var walk := float(E["walk_mps"])
	var lat := -1
	var full := -1
	var stop := -1
	var plateau: Array = []
	var dir_sum := Vector3.ZERO
	var pos_f1 := Vector3.INF
	var pos_stop := Vector3.INF
	var scr0 := Vector2.INF
	var scr1 := Vector2.INF
	var fs0 := 0
	var fs1 := 0
	var air := 0
	var settle := -1
	var prev_focus := Vector3.INF
	var lag_f1 := 0.0
	var char_px := 0.0
	var focus_f1 := Vector3.ZERO
	for row: Dictionary in rows:
		var f := int(row["f"])
		if f <= f0:
			char_px = absf((row["scr_feet"] as Vector2).y - (row["scr_head"] as Vector2).y) if row.has("scr_feet") else 0.0
			prev_focus = row["focus"]
			continue
		if String(row["st"]) != "ground":
			air += 1
		var spd := float(row["spd"])
		if f <= f1:
			if lat < 0 and spd > 0.01:
				lat = f - f0
			if full < 0 and spd >= 0.99 * walk:
				full = f - f0
			if f > f0 + 10:
				plateau.append(spd)
				dir_sum += row["hv"]
				if row.has("scr_feet"):
					if scr0 == Vector2.INF:
						scr0 = row["scr_feet"]
						fs0 = f
					scr1 = row["scr_feet"]
					fs1 = f
			if f == f1:
				pos_f1 = row["pos"]
				focus_f1 = row["focus"]
		else:
			if stop < 0 and spd < 0.01:
				stop = f - f1
				pos_stop = row["pos"]
			if stop >= 0 and settle < 0 and prev_focus != Vector3.INF and (row["focus"] as Vector3).distance_to(prev_focus) < 0.0005:
				settle = f - (f1 + stop)
		prev_focus = row["focus"]
	var plateau_mps := _mean(plateau)
	var dir_err := rad_to_deg(dir_sum.angle_to(want)) if dir_sum.length() > 0.01 else 180.0
	var stop_m := _flat(pos_stop - pos_f1) if pos_stop != Vector3.INF and pos_f1 != Vector3.INF else -1.0
	var screen_deg := 0.0
	var screen_pxps := 0.0
	if scr0 != Vector2.INF and fs1 > fs0:
		var dv := scr1 - scr0
		screen_deg = rad_to_deg(atan2(-dv.y, dv.x))
		screen_pxps = dv.length() / ((fs1 - fs0) / TPS)
	var plateau_d := Vector3.ZERO
	var pd0 := Vector3.INF
	for row: Dictionary in rows:
		if int(row["f"]) > f0 + 10 and int(row["f"]) <= f1:
			if pd0 == Vector3.INF:
				pd0 = row["pos"]
			plateau_d = (row["pos"] as Vector3) - pd0
	var out := {"plateau_disp": plateau_d, "plateau_ticks": maxi(1, f1 - f0 - 11), "latency_ticks": lat, "full_ticks": full, "full_s": full / TPS, "plateau_mps": snappedf(plateau_mps, 0.0001),
		"dir_err_deg": snappedf(dir_err, 0.01), "stop_ticks": stop, "stop_m": snappedf(stop_m, 0.001), "air_ticks": air,
		"screen_rel_deg": snappedf(screen_deg, 0.1), "screen_rel_pxps": snappedf(screen_pxps, 0.1), "char_px": snappedf(char_px, 0.1),
		"cam_settle_ticks": settle, "focus_f1": Lib.Util.fmt_v(focus_f1)}
	out["text"] = "first motion %d tick(s) after the press, >=99%% speed after %d ticks (%.3f s), plateau %.3f m/s (%.1f%% of %.3f), direction error %.2f deg, stop %d ticks / %.3f m after release, relative to the following camera %.0f px/s at %.1f deg, airborne ticks %d, camera settles %d ticks after the stop" % [
		lat, full, full / TPS, plateau_mps, 100.0 * plateau_mps / walk, walk, dir_err, stop, stop_m, screen_pxps, screen_deg, air, settle]
	return out


## Adds the walk direction and speed as drawn by the (fixed-orientation) camera: the plateau displacement projected
## on the camera's right and up axes, in pixels of the current view (KEEP_HEIGHT: camera.size m = viewport height).
func _screen_motion(d: PlaytestDriver, r: Dictionary) -> void:
	var rig := d.ctx().camera as CameraRig
	var b := rig.camera.global_transform.basis
	var vp := d.get_viewport().get_visible_rect().size
	var px_per_m := vp.y / rig.camera.size
	var disp: Vector3 = r["plateau_disp"]
	var sv := Vector2(disp.dot(b.x), disp.dot(b.y)) * px_per_m / (int(r["plateau_ticks"]) / TPS)
	r["screen_deg"] = snappedf(rad_to_deg(atan2(sv.y, sv.x)), 0.1)
	r["screen_pxps"] = snappedf(sv.length(), 0.1)
	r["view_size_m"] = snappedf(rig.camera.size, 0.01)
	r["viewport"] = "%dx%d" % [int(vp.x), int(vp.y)]
	r.erase("plateau_disp")
	r["text"] = String(r["text"]) + "; on screen %.0f px/s at %.1f deg (view %.2f m tall, %s px)" % [float(r["screen_pxps"]), float(r["screen_deg"]), rig.camera.size, r["viewport"]]


# =================================================================================================================
# Turns
# =================================================================================================================

func _turns(d: PlaytestDriver) -> void:
	var turns := {}
	await _recenter(d)
	turns["180 (D -> A)"] = await _measure_turn(d, "180 (D -> A)", [K_RIGHT], [K_LEFT], Vector2(-1, 0))
	await _recenter(d)
	turns["90 (D -> W)"] = await _measure_turn(d, "90 (D -> W)", [K_RIGHT], [K_UP], Vector2(0, 1))
	await _recenter(d)
	turns["45 (D -> W+D)"] = await _measure_turn(d, "45 (D -> W+D)", [K_RIGHT], [K_UP, K_RIGHT], Vector2(1, 1))
	results["turns"] = turns
	var walk := float(E["walk_mps"])
	var acc := float(E["ground_accel"]) / TPS
	var dec := float(E["ground_decel"]) / TPS
	# 180: decelerate to 0 (decel), then accelerate (accel); 90 and 45: the velocity vector moves at accel.
	var exp180 := ceili(walk / dec - 0.001) + ceili(walk / acc - 0.001)
	d.soft_check("a 180 degree reversal reaches full speed the new way in <= %d ticks (decel + accel)" % (exp180 + 1),
		int((turns["180 (D -> A)"] as Dictionary)["turn_ticks"]) <= exp180 + 1, _list(turns, "turn_ticks"))
	d.note("visual turn (model yaw, facing_turn_rate %.0f deg/s): %s ticks" % [float(E["facing_turn_deg_s"]), _list(turns, "visual_ticks")])


func _measure_turn(d: PlaytestDriver, label: String, k_from: Array, k_to: Array, mv_to: Vector2) -> Dictionary:
	var p := d.player()
	var want := p.view_right * mv_to.x + p.view_forward * mv_to.y
	want.y = 0.0
	want = want.normalized()
	var i := d._begin(PlaytestReport.KIND_PLAY, "feel_turn", "%s: 0.45 s, switch keys in one frame, 0.45 s" % label)
	S.rows.clear()
	S.record = true
	await d.wait(0.1)
	for k: Key in k_from:
		d.input.key_down(k)
	await d.wait(0.45)
	var fsw := Engine.get_physics_frames()
	for k: Key in k_from:
		if not k_to.has(k):
			d.input.key_up(k)
	for k: Key in k_to:
		if not k_from.has(k):
			d.input.key_down(k)
	await d.wait(0.45)
	for k: Key in k_to:
		d.input.key_up(k)
	await d.wait(0.4)
	S.record = false
	var walk := float(E["walk_mps"])
	var want_yaw := atan2(want.x, want.z)
	var turn := -1
	var vis := -1
	var min_spd := INF
	var path_dev := 0.0
	var p_sw := Vector3.INF
	for row: Dictionary in S.rows:
		var f := int(row["f"])
		if f == fsw:
			p_sw = row["pos"]
		if f <= fsw:
			continue
		var along := (row["hv"] as Vector3).dot(want)
		if turn < 0:
			min_spd = minf(min_spd, float(row["spd"]))
			if along >= 0.99 * walk:
				turn = f - fsw
		if vis < 0 and row.has("yaw") and absf(wrapf(float(row["yaw"]) - want_yaw, -PI, PI)) < deg_to_rad(5.0):
			vis = f - fsw
	var r := {"turn_ticks": turn, "turn_s": turn / TPS, "visual_ticks": vis, "min_speed_mps": snappedf(min_spd, 0.001)}
	r["text"] = "%s: full speed the new way after %d ticks (%.3f s), lowest speed in the turn %.2f m/s, model faces the new way after %d ticks" % [
		label, turn, turn / TPS, min_spd, vis]
	d._end(i, turn > 0, String(r["text"]))
	d.note("turn %s" % r["text"])
	return r


# =================================================================================================================
# Jumps
# =================================================================================================================

func _jumps(d: PlaytestDriver) -> void:
	var p := d.player()
	var jumps := {}
	var frames: Array = []
	# Standing jump.
	await _recenter(d)
	S.start_capture(6, 4, 360)
	var sj := await _jump_run(d, "standing jump", [], 0.0, [])
	frames.append_array(S.stop_capture())
	jumps["standing"] = sj
	var apex_ok := absf(float(sj["apex_m"]) - float(E["apex_m"])) <= 0.015
	d.check("standing jump apex = MeowDB %.0f px x WorldScale.v = %.3f m (measured %.3f m)" % [float(E["apex_px"]),
		float(E["apex_m"]), float(sj["apex_m"])], apex_ok)
	var air_ticks_exp := float(E["airtime_s"]) * TPS
	d.check("standing jump airtime = 2 sqrt(2 apex / g) = %.3f s with MeowDB gravity %.0f px/s2 (measured %.3f s, +-1 tick)" % [
		float(E["airtime_s"]), float(E["gravity_px"]), float(sj["airtime_s"])], absf(int(sj["air_ticks"]) - air_ticks_exp) <= 1.5)
	d.soft_check("the camera does not bob with the jump (focus height change <= 1 cm)", float(sj["cam_dy_m"]) <= 0.01,
		"%.3f m" % float(sj["cam_dy_m"]))
	# Held jump: hold-to-rejump.
	await _recenter(d)
	var ev0 := S.events.size()
	var i := d._begin(PlaytestReport.KIND_PLAY, "feel_jump", "held jump 2.0 s (hold_to_rejump)")
	await d.press(&"jump", 2.0)
	await d.wait_until(func() -> bool: return p.is_grounded(), 1.5)
	var jf: Array = []
	for e: Array in S.events.slice(ev0):
		if e[1] == "jumped":
			jf.append(int(e[0]))
	var gaps: Array = []
	for k in range(1, jf.size()):
		gaps.append(jf[k] - jf[k - 1])
	jumps["held"] = {"jumps": jf.size(), "gap_ticks": gaps}
	d._end(i, jf.size() >= 2, "%d jumps in 2.0 s held, %s ticks apart" % [jf.size(), str(gaps)])
	d.note("held jump: %d jumps in 2.0 s held, %s ticks apart" % [jf.size(), str(gaps)])
	# Running jump (D held through it).
	await _recenter(d)
	await _back_off(d, [K_LEFT], 1.2)
	S.start_capture(6, 4, 360)
	var rj := await _jump_run(d, "running jump (D held)", [K_RIGHT], 0.3, [K_RIGHT])
	frames.append_array(S.stop_capture())
	jumps["running"] = rj
	d.check("running jump length = walk x airtime = %.3f m (measured %.3f m, +-0.06)" % [float(E["run_jump_m"]), float(rj["length_m"])],
		absf(float(rj["length_m"]) - float(E["run_jump_m"])) <= 0.06)
	results["jumps"] = jumps
	if not frames.is_empty():
		Lib.Util.save_shot(d, Lib.Util.sheet(frames, 4, Vector2i(400, 400)), "feel_jumps_sheet",
			"row 1: standing jump every 6 frames from the press; row 2: running jump (D held) every 6 frames from the press; 360 px crops around the player")


## Holds `pre` keys for `lead_s`, taps jump, keeps `hold` keys held until landing. Returns the jump's numbers.
func _jump_run(d: PlaytestDriver, label: String, pre: Array, lead_s: float, hold: Array, on_air: Callable = Callable()) -> Dictionary:
	var p := d.player()
	var i := d._begin(PlaytestReport.KIND_PLAY, "feel_jump", label)
	S.rows.clear()
	S.record = true
	await d.wait(0.1)
	for k: Key in pre:
		d.input.key_down(k)
	if lead_s > 0.0:
		await d.wait(lead_s)
	var f0 := Engine.get_physics_frames()
	await d.input.tap_key(K_JUMP)
	if on_air.is_valid():
		await d.wait_until(func() -> bool: return not p.is_grounded(), 0.5)
		await on_air.call()
	await d.wait_until(func() -> bool: return p.is_grounded() and Engine.get_physics_frames() > f0 + 6, 2.0)
	var fl := Engine.get_physics_frames()
	for k: Key in hold:
		d.input.key_up(k)
	for k: Key in pre:
		if not hold.has(k):
			d.input.key_up(k)
	await d.wait(0.3)
	S.record = false
	var r := _analyze_jump(S.rows, f0)
	r["label"] = label
	r["landed_frame_delta"] = fl - f0
	d._end(i, int(r["air_ticks"]) > 0, String(r["text"]))
	d.note("jump %s: %s" % [label, r["text"]])
	return r


func _analyze_jump(rows: Array, f0: int) -> Dictionary:
	var y0 := INF
	var apex := -INF
	var air := 0
	var first_air := -1
	var takeoff := Vector3.INF
	var landing := Vector3.INF
	var prev: Dictionary = {}
	var scr_take := Vector2.INF
	var scr_apex := Vector2.INF
	var char_px := 0.0
	var fy_min := INF
	var fy_max := -INF
	var land_v := Vector3.ZERO
	for row: Dictionary in rows:
		var f := int(row["f"])
		var pos: Vector3 = row["pos"]
		var focus: Vector3 = row["focus"]
		if f <= f0:
			y0 = pos.y
			prev = row
			if row.has("scr_feet"):
				char_px = absf((row["scr_feet"] as Vector2).y - (row["scr_head"] as Vector2).y)
			continue
		fy_min = minf(fy_min, focus.y)
		fy_max = maxf(fy_max, focus.y)
		if String(row["st"]) == "air":
			air += 1
			if first_air < 0:
				first_air = f - f0
				takeoff = (prev["pos"] as Vector3) if not prev.is_empty() else pos
				if not prev.is_empty() and prev.has("scr_feet"):
					scr_take = prev["scr_feet"]
			if pos.y - y0 > apex:
				apex = pos.y - y0
				if row.has("scr_feet"):
					scr_apex = row["scr_feet"]
			land_v = row["hv"]
		elif first_air >= 0 and landing == Vector3.INF:
			landing = pos
		prev = row
	var length := _flat(landing - takeoff) if landing != Vector3.INF and takeoff != Vector3.INF else 0.0
	var rise_px := scr_take.y - scr_apex.y if scr_take != Vector2.INF and scr_apex != Vector2.INF else 0.0
	var out := {"apex_m": snappedf(apex, 0.0001), "air_ticks": air, "airtime_s": snappedf(air / TPS, 0.0001),
		"press_to_takeoff_ticks": first_air, "length_m": snappedf(length, 0.001), "rise_px": snappedf(rise_px, 0.1),
		"char_px": snappedf(char_px, 0.1), "cam_dy_m": snappedf(fy_max - fy_min, 0.0001) if fy_max > -INF else 0.0,
		"landing_speed_mps": snappedf(Vector2(land_v.x, land_v.z).length(), 0.001),
		"takeoff": Lib.Util.fmt_v(takeoff), "landing": Lib.Util.fmt_v(landing)}
	out["text"] = "takeoff %d tick(s) after the press, apex %.3f m, airtime %d ticks (%.3f s), horizontal length %.3f m, horizontal speed at landing %.2f m/s, on-screen rise %.0f px (character %.0f px tall), camera height change %.3f m" % [
		first_air, apex, air, air / TPS, length, Vector2(land_v.x, land_v.z).length(), rise_px, char_px, fy_max - fy_min]
	return out


## Walks a little away from the centre (so a run has room ahead of it).
func _back_off(d: PlaytestDriver, keys: Array, seconds: float) -> void:
	for k: Key in keys:
		d.input.key_down(k)
	await d.wait(seconds * 0.5)
	for k: Key in keys:
		d.input.key_up(k)
	await d.wait(0.3)


# =================================================================================================================
# Air control and the jump buffer
# =================================================================================================================

func _air_control(d: PlaytestDriver) -> void:
	var air := {}
	# Running jump, released at takeoff: momentum alone.
	await _recenter(d)
	await _back_off(d, [K_LEFT], 1.2)
	air["running, no input in the air"] = await _jump_run(d, "running jump, keys released at takeoff", [K_RIGHT], 0.3, [],
		func() -> void:
			d.input.key_up(K_RIGHT))
	# Running jump, reversed at takeoff.
	await _recenter(d)
	await _back_off(d, [K_LEFT], 1.2)
	air["running, reversed in the air"] = await _jump_run(d, "running jump, A instead of D at takeoff", [K_RIGHT], 0.3, [K_LEFT],
		func() -> void:
			d.input.key_up(K_RIGHT)
			d.input.key_down(K_LEFT))
	# Standing jump, D pressed at takeoff: the drift.
	await _recenter(d)
	await _back_off(d, [K_LEFT], 0.6)
	air["standing, D in the air"] = await _jump_run(d, "standing jump, D pressed at takeoff", [], 0.0, [K_RIGHT],
		func() -> void:
			d.input.key_down(K_RIGHT))
	results["air"] = air
	var run_len := float((results["jumps"]["running"] as Dictionary)["length_m"])
	var keep := float((air["running, no input in the air"] as Dictionary)["length_m"])
	var rev := float((air["running, reversed in the air"] as Dictionary)["length_m"])
	var drift := float((air["standing, D in the air"] as Dictionary)["length_m"])
	var t := float(E["airtime_s"])
	var a := float(E["air_accel"])
	var walk := float(E["walk_mps"])
	var rev_exp := walk * t - 0.5 * a * t * t
	var drift_exp := 0.5 * a * t * t
	results["air_summary"] = {"running_m": run_len, "no_input_m": keep, "reversed_m": rev, "lateral_change_m": run_len - rev,
		"standing_drift_m": drift, "reversed_expected_m": rev_exp, "drift_expected_m": drift_exp}
	d.soft_check("momentum is kept with no input in the air (%.3f m vs %.3f m held)" % [keep, run_len], absf(keep - run_len) <= 0.05)
	d.soft_check("reversing in the air shortens a running jump to %.2f m (air_accel %.0f m/s2: %.2f m expected), it does not turn it around" % [
		rev, a, rev_exp], absf(rev - rev_exp) <= 0.08 and rev > 0.0)
	d.soft_check("a standing jump drifts %.2f m with D held (expected 0.5 a t^2 = %.2f m)" % [drift, drift_exp], absf(drift - drift_exp) <= 0.08)
	d.note("air control: running jump %.2f m; no input %.2f m; reversed %.2f m (lateral change %.2f m, %.0f%% of the jump); standing drift %.2f m" % [
		run_len, keep, rev, run_len - rev, 100.0 * (run_len - rev) / maxf(run_len, 0.001), drift])


func _jump_buffer(d: PlaytestDriver) -> void:
	var p := d.player()
	await _recenter(d)
	var i := d._begin(PlaytestReport.KIND_PLAY, "feel_jump", "jump buffer: a second Space while falling, just before landing")
	var ev0 := S.events.size()
	S.rows.clear()
	S.record = true
	await d.input.tap_key(K_JUMP)
	await d.wait_until(func() -> bool: return not p.is_grounded(), 0.5)
	var f_take := Engine.get_physics_frames()
	# Press again 6 ticks (0.1 s) before the expected landing: inside the 0.12 s buffer.
	var lead := 6
	var f_at := f_take + int(round(float(E["airtime_s"]) * TPS)) - lead
	await d.wait_until(func() -> bool: return Engine.get_physics_frames() >= f_at, 1.0)
	var f_press := Engine.get_physics_frames()
	await d.input.tap_key(K_JUMP)
	await d.wait(1.2)
	S.record = false
	var jf: Array = []
	var lf: Array = []
	for e: Array in S.events.slice(ev0):
		if e[1] == "jumped":
			jf.append(int(e[0]))
		elif e[1] == "landed":
			lf.append(int(e[0]))
	var before_land: int = (int(lf[0]) - f_press) if not lf.is_empty() else -1
	var fired := jf.size() >= 2
	var delay: int = (int(jf[1]) - int(lf[0])) if fired and not lf.is_empty() else -1
	results["jump_buffer"] = {"pressed_ticks_before_landing": before_land, "second_jump": fired, "ticks_after_landing": delay}
	d._end(i, fired, "pressed %d ticks before landing; second jump %s (%d ticks after landing)" % [before_land, "fired" if fired else "did NOT fire", delay])
	d.soft_check("a jump pressed %d ticks (%.3f s) before landing fires on landing (jump_buffer %.2f s)" % [before_land,
		before_land / TPS, float(E["jump_buffer_s"])], fired and delay <= 1 if before_land / TPS <= float(E["jump_buffer_s"]) else true,
		"jumps %s, landings %s" % [str(jf), str(lf)])


# =================================================================================================================
# Ladder
# =================================================================================================================

func _ladder(d: PlaytestDriver) -> void:
	var p := d.player()
	if d.current_map() != START_MAP:
		d.note("the ladder test needs %s; warping back (setup)" % START_MAP)
		await d.console("warp %s" % START_MAP)
	var c: ClimbableDef = null
	for cc: ClimbableDef in p.climbables:
		if cc.name == LADDER:
			c = cc
	if not d.check("the bluff ladder %s is loaded" % LADDER, c != null):
		return
	var lad := {"height_m": snappedf(c.top.y - c.bottom.y, 0.001), "kind": String(c.kind)}
	var foot := c.foot_ground if c.has_foot_ground else c.bottom
	var front := foot - c.facing * 0.7
	var w: Dictionary = await d.walk_to(front, {"within_m": 0.35, "max_s": 60.0})
	d.check("walked to the foot of the ladder", bool(w["ok"]) or c.line_distance_xz(p.global_position) < 1.2, String(w.get("result", "")))
	await d.walker.nudge_until(c.bottom, func() -> bool: return c.line_distance_xz(d.player().global_position) < 0.55)
	await d.wait(0.3)
	var frames: Array = []
	# Grab with Up and climb holding Up.
	var i := d._begin(PlaytestReport.KIND_PLAY, "feel_ladder", "Up at the foot, hold Up to the top")
	var climb_s := (c.top.y - c.bottom.y) / float(E["climb_mps"])
	S.start_capture(maxi(4, int(climb_s * TPS / 6.0)), 8, 520)
	S.rows.clear()
	S.record = true
	var ev0 := S.events.size()
	var f_press := Engine.get_physics_frames()
	d.input.key_down(K_CLIMB_UP)
	await d.wait_until(func() -> bool: return p.is_climbing(), 0.5)
	var f_grab := Engine.get_physics_frames()
	await d.wait_until(func() -> bool: return not p.is_climbing(), climb_s + 4.0)
	d.input.key_up(K_CLIMB_UP)
	await d.wait_until(func() -> bool: return p.is_grounded(), 1.0)
	await d.wait(0.5)
	frames.append_array(S.stop_capture())
	S.record = false
	var up := _analyze_climb(S.rows, S.events.slice(ev0), f_press, +1.0)
	lad["up"] = up
	d._end(i, String(up["how"]) == "top", String(up["text"]))
	d.note("ladder up: %s" % up["text"])
	d.check("climb speed = MeowDB %.0f px/s x WorldScale.v = %.3f m/s (measured %.3f m/s, within 2%%)" % [float(E["climb_px"]),
		float(E["climb_mps"]), float(up["speed_mps"])], absf(float(up["speed_mps"]) - float(E["climb_mps"])) <= 0.02 * float(E["climb_mps"]))
	d.check("Up at the foot grabs the ladder and holding Up exits at the top", String(up["how"]) == "top", String(up["text"]))
	# Down from the top.
	i = d._begin(PlaytestReport.KIND_PLAY, "feel_ladder", "Down at the top, hold Down to the foot")
	S.rows.clear()
	S.record = true
	ev0 = S.events.size()
	f_press = Engine.get_physics_frames()
	d.input.key_down(K_CLIMB_DOWN)
	var grabbed := await d.wait_until(func() -> bool: return p.is_climbing(), 0.5)
	if grabbed:
		await d.wait_until(func() -> bool: return not p.is_climbing(), climb_s + 4.0)
	d.input.key_up(K_CLIMB_DOWN)
	await d.wait_until(func() -> bool: return p.is_grounded(), 1.0)
	await d.wait(0.3)
	S.record = false
	var down := _analyze_climb(S.rows, S.events.slice(ev0), f_press, -1.0)
	lad["down"] = down
	d._end(i, String(down["how"]) == "bottom", String(down["text"]))
	d.note("ladder down: %s" % down["text"])
	d.soft_check("Down at the top grabs the ladder and holding Down exits at the foot", String(down["how"]) == "bottom", String(down["text"]))
	# Up pressed again right after the foot exit (inside climb_regrab_cooldown_s), then held.
	i = d._begin(PlaytestReport.KIND_PLAY, "feel_ladder", "Up pressed 0.1 s after the foot exit, then held 1 s")
	d.input.key_down(K_CLIMB_UP)
	var quick := await d.wait_until(func() -> bool: return p.is_climbing(), 1.0)
	d.input.key_up(K_CLIMB_UP)
	lad["regrab_held_up_after_exit"] = quick
	d._end(i, true, "grabbed: %s" % quick)
	d.note("ladder: Up pressed %.2f s after the foot exit and held 1 s %s" % [0.3, "grabbed it" if quick else "did NOT grab it (climb_regrab_cooldown_s; a held Up only grabs in the air)"])
	if quick:
		await d.wait_until(func() -> bool: return not p.is_climbing(), 0.2)
		d.input.key_down(K_CLIMB_DOWN)
		await d.wait_until(func() -> bool: return not p.is_climbing(), 3.0)
		d.input.key_up(K_CLIMB_DOWN)
	# Walking into the ladder with Up already held (a classic habit: hold Up and walk to the rope).
	await d.wait(0.6)
	var back_pt := (c.foot_ground if c.has_foot_ground else c.bottom) - c.facing * 1.8
	await d.walk_to(back_pt, {"within_m": 0.3, "max_s": 15.0})
	await d.wait(0.5)
	i = d._begin(PlaytestReport.KIND_PLAY, "feel_ladder", "hold Up, then walk into the ladder")
	d.input.key_down(K_CLIMB_UP)
	await d.wait(0.2)
	var walked_in := await d.walker.nudge_until(c.bottom, func() -> bool: return p.is_climbing() or c.line_distance_xz(d.player().global_position) < 0.3)
	var held_grab := p.is_climbing()
	if not held_grab:
		await d.wait(0.5)
		held_grab = p.is_climbing()
	d.input.key_up(K_CLIMB_UP)
	lad["walk_in_with_up_held_grabs"] = held_grab
	d._end(i, true, "walked in %s; grabbed while Up was held: %s (line distance %.2f m)" % [walked_in, held_grab, c.line_distance_xz(p.global_position)])
	d.note("ladder: walking into it with Up held %s" % ("grabs it" if held_grab else "does NOT grab it: Up must be pressed again inside the 0.8 m grab radius"))
	if held_grab:
		d.input.key_down(K_CLIMB_DOWN)
		await d.wait_until(func() -> bool: return not p.is_climbing(), 3.0)
		d.input.key_up(K_CLIMB_DOWN)
	# Jump off sideways.
	await d.wait(0.6)
	await d.walker.nudge_until(c.bottom, func() -> bool: return c.line_distance_xz(d.player().global_position) < 0.55)
	await d.wait(0.5)
	i = d._begin(PlaytestReport.KIND_PLAY, "feel_ladder", "Up, climb 0.6 s, then jump + a side key")
	d.input.key_down(K_CLIMB_UP)
	var on_ladder := await d.wait_until(func() -> bool: return p.is_climbing(), 0.5)
	await d.wait(0.6)
	d.input.key_up(K_CLIMB_UP)
	await d.wait(0.1)
	d.check("grabbed the ladder again for the jump-off", on_ladder and p.is_climbing())
	var side := K_RIGHT if p.view_right.dot(c.facing) < (-p.view_right).dot(c.facing) else K_LEFT
	S.rows.clear()
	S.record = true
	ev0 = S.events.size()
	var y_off := p.global_position.y
	var f_j := Engine.get_physics_frames()
	d.input.key_down(side)
	await d.input.tap_key(K_JUMP)
	await d.wait_until(func() -> bool: return p.is_grounded(), 2.0)
	d.input.key_up(side)
	await d.wait(0.3)
	S.record = false
	var how := ""
	for e: Array in S.events.slice(ev0):
		if e[1] == "climb_end":
			how = String(e[2]).get_slice(" ", 1)
	var hop := -INF
	var hdist := 0.0
	var p0 := Vector3.INF
	for row: Dictionary in S.rows:
		if int(row["f"]) <= f_j:
			p0 = row["pos"]
			continue
		hop = maxf(hop, (row["pos"] as Vector3).y - y_off)
		if p0 != Vector3.INF:
			hdist = maxf(hdist, _flat((row["pos"] as Vector3) - p0))
	var hop_exp := float(E["apex_m"]) * float(E["climb_jump_off_fraction"])
	lad["jump_off"] = {"how": how, "hop_m": snappedf(hop, 0.001), "expected_hop_m": snappedf(hop_exp, 0.001), "horizontal_m": snappedf(hdist, 0.01)}
	d._end(i, how == "jump", "ended by %s, hop %.3f m (expected %.3f m: apex x climb_jump_off_apex_fraction), %.2f m sideways" % [how, hop, hop_exp, hdist])
	d.soft_check("jump + side key lets go of the ladder with a half-apex hop (%.3f m, expected %.3f m)" % [hop, hop_exp],
		how == "jump" and absf(hop - hop_exp) <= 0.03)
	lad["coyote"] = await _coyote(d, c, climb_s)
	results["ladder"] = lad
	if not frames.is_empty():
		Lib.Util.save_shot(d, Lib.Util.sheet(frames, 4, Vector2i(400, 400)), "feel_ladder_sheet",
			"%s: Up pressed at the foot then held; 8 frames %.2f s apart (520 px crops around the player)" % [LADDER, maxi(4, int(climb_s * TPS / 6.0)) / TPS])


## Coyote time on the bluff edge above the ladder: climb up, walk off the edge toward the camera, press jump
## `delay` ticks after the feet left the ground. Returns {delay: "fired" | "no jump" | why}.
func _coyote(d: PlaytestDriver, c: ClimbableDef, climb_s: float) -> Dictionary:
	var p := d.player()
	var res := {}
	for delay: int in [3, 8]:
		await d.wait(0.5)
		await d.walker.nudge_until(c.bottom, func() -> bool: return c.line_distance_xz(d.player().global_position) < 0.55)
		await d.wait(0.5)
		d.input.key_down(K_CLIMB_UP)
		await d.wait_until(func() -> bool: return p.is_climbing(), 0.5)
		await d.wait_until(func() -> bool: return not p.is_climbing(), climb_s + 3.0)
		d.input.key_up(K_CLIMB_UP)
		await d.wait_until(func() -> bool: return p.is_grounded(), 1.0)
		if p.global_position.y < c.top.y - 0.7:
			res[str(delay)] = "could not climb back up"
			continue
		await d.wait(0.3)
		var i := d._begin(PlaytestReport.KIND_PLAY, "feel_coyote", "walk off the bluff edge, jump %d ticks after the feet leave it" % delay)
		var away := -c.facing
		away.y = 0.0
		away = away.normalized()
		var ev0 := S.events.size()
		d.input.set_move_world(away, p.view_right, p.view_forward)
		var off := await d.wait_until(func() -> bool: return not p.is_grounded() and not p.is_climbing(), 2.0)
		if not off:
			d.input.release_movement()
			res[str(delay)] = "never left the ground walking off the edge"
			d._end(i, false, String(res[str(delay)]))
			continue
		var f_off := Engine.get_physics_frames()
		var y_off := p.global_position.y
		await d.wait_until(func() -> bool: return Engine.get_physics_frames() >= f_off + delay - 1, 0.5)
		var jumped_before := 0
		for e: Array in S.events.slice(ev0):
			if e[1] == "jumped":
				jumped_before += 1
		await d.input.tap_key(K_JUMP)
		await d.wait(0.05)
		var vy := p.vertical_speed
		d.input.release_movement()
		await d.wait_until(func() -> bool: return p.is_grounded(), 3.0)
		var jumped := 0
		for e: Array in S.events.slice(ev0):
			if e[1] == "jumped":
				jumped += 1
		var fired := jumped > jumped_before
		res[str(delay)] = "fired" if fired else "no jump"
		d._end(i, true, "%s (vertical speed after the press %.2f m/s, fell %.2f m)" % [res[str(delay)], vy, y_off - p.global_position.y])
	var coyote_ticks := float(E["coyote_s"]) * TPS
	d.soft_check("coyote time: a jump %d ticks after walking off an edge fires, %d ticks after does not (coyote_time_s %.2f s = %.1f ticks)" % [
		3, 8, float(E["coyote_s"]), coyote_ticks], res.get("3") == "fired" and res.get("8") == "no jump", str(res))
	return res


func _analyze_climb(rows: Array, events: Array, f_press: int, dir: float) -> Dictionary:
	var f_start := -1
	var f_end := -1
	var how := ""
	for e: Array in events:
		if e[1] == "climb_start" and f_start < 0:
			f_start = int(e[0])
		elif e[1] == "climb_end" and f_end < 0:
			f_end = int(e[0])
			how = String(e[2]).get_slice(" ", 1)
	var speeds: Array = []
	var prev: Dictionary = {}
	var grab_snap := 0.0
	var exit_snap := Vector3.ZERO
	var ground_after := -1
	for row: Dictionary in rows:
		var f := int(row["f"])
		if not prev.is_empty():
			if f == f_start:
				grab_snap = _flat((row["pos"] as Vector3) - (prev["pos"] as Vector3))
			if f == f_end:
				exit_snap = (row["pos"] as Vector3) - (prev["pos"] as Vector3)
			if f_start > 0 and f > f_start + 3 and (f_end < 0 or f < f_end - 3) and bool(row["climbing"]) and bool(prev["climbing"]):
				speeds.append(((row["pos"] as Vector3).y - (prev["pos"] as Vector3).y) * TPS * dir)
			if f_end > 0 and f > f_end and ground_after < 0 and String(row["st"]) == "ground":
				ground_after = f - f_end
		prev = row
	speeds.sort()
	var med := float(speeds[speeds.size() / 2]) if not speeds.is_empty() else 0.0
	var out := {"grab_ticks": (f_start - f_press) if f_start > 0 else -1, "climb_ticks": (f_end - f_start) if f_end > 0 and f_start > 0 else -1,
		"speed_mps": snappedf(med, 0.0001), "how": how, "grab_snap_m": snappedf(grab_snap, 0.001),
		"exit_snap": Lib.Util.fmt_v(exit_snap), "ground_ticks_after_exit": ground_after}
	out["text"] = "grabbed %d tick(s) after the key press (body moved %.2f m sideways onto the line), climbed %d ticks (%.2f s) at %.3f m/s, ended by '%s' (exit moved the body %s), grounded %d tick(s) after the exit" % [
		int(out["grab_ticks"]), grab_snap, int(out["climb_ticks"]), int(out["climb_ticks"]) / TPS, med, how, out["exit_snap"], ground_after]
	return out


# =================================================================================================================
# Output
# =================================================================================================================

func _write(d: PlaytestDriver) -> void:
	var path := d.out_dir.path_join("feel_movement.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_jsonable(results), "  "))
		f.close()
	d.note("results: %s" % path)


static func _jsonable(v: Variant) -> Variant:
	if v is Dictionary:
		var o := {}
		for k: Variant in v:
			o[str(k)] = _jsonable(v[k])
		return o
	if v is Array:
		var a := []
		for e: Variant in v:
			a.append(_jsonable(e))
		return a
	if v is Vector3 or v is Vector2:
		return str(v)
	if v is float and (is_inf(v) or is_nan(v)):
		return str(v)
	return v


static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x: Variant in a:
		s += float(x)
	return s / a.size()


static func _list(m: Dictionary, key: String) -> String:
	var parts := PackedStringArray()
	for k: String in m:
		parts.append("%s %s" % [k, str((m[k] as Dictionary).get(key))])
	return ", ".join(parts)


static func _all_within(m: Dictionary, key: String, want: float, frac: float) -> bool:
	for k: String in m:
		if absf(float((m[k] as Dictionary)[key]) - want) > frac * want:
			return false
	return true


static func _all_eq(m: Dictionary, key: String, want: int) -> bool:
	for k: String in m:
		if int((m[k] as Dictionary)[key]) != want:
			return false
	return true


static func _all_le(m: Dictionary, key: String, limit: float) -> bool:
	for k: String in m:
		var v := float((m[k] as Dictionary)[key])
		if v < 0.0 or v > limit:
			return false
	return true
