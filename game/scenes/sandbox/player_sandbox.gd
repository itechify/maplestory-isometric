extends Node3D
## Player/camera sandbox: one exported map chunk (visual + collision glb from res://assets/world), the player at
## the sidecar player_start, and the gameplay camera. Seeds the L2 traversal bot (MAP_ARCHITECTURE section 4.13).
##
##   bash scripts/godot.sh --path game res://scenes/sandbox/player_sandbox.tscn [-- options]
##
## Options (after --):
##   --map <slug>          map chunk to load (default SnailHuntingGround1_40000)
##   --context             also load the island scenery chunks (visual only) around the map
##   --bot <route|all>     walk sidecar routes in real time with BotInput (--both: also reversed); prints BOT lines
##   --sweep [a,b|all]     headless-friendly: every route of the given maps (both directions), synchronously; prints
##                         BOT lines and a BOT_SUMMARY; no visuals are loaded
##   --showcase <dir>      scripted input sequence that saves screenshots to <dir> (needs a window)
##   --quit                quit when the bot/showcase finishes
##   --world [--all]       integration smoke test: the real island (scenes/world/world.tscn) with this player and
##                         camera registered through IslandWorld.set_player() / MapSession.attach_camera(); starts a
##                         new game, then (--all) debug-warps to every map and checks is_on_floor() after arrival
## Keyboard play otherwise: WASD move, Space/Alt jump, Up grabs ladders/ropes, Down grabs from the top, F interact,
## F3 toggles the debug label, R returns to SafeGround, F5 respawns at player_start.
##
## For screenshots run windowed from an ISOLATE copy with --disable-vsync --resolution 1600x900 (background windows
## are vsync-throttled to ~4 fps).

const WORLD := "res://assets/world"
const DEFAULT_MAP := "SnailHuntingGround1_40000"
const CONTEXT_CHUNKS := ["World_IslandBody", "World_Plinths", "World_Trails", "World_Scenery", "World_Forest", "World_SkyAndSea"]

var player: PlayerController = null
var rig: CameraRig = null
var sidecar: Dictionary = {}
var slug: String = DEFAULT_MAP
var bot_input: BotInput = null
var falls: int = 0
var floor_mismatch_ticks: int = 0
var physics_ticks: int = 0

var _args: PackedStringArray = PackedStringArray()
var _label: Label = null
var _bots: Array[RouteBot] = []
var _bot_index: int = -1
var _bot_results: PackedStringArray = PackedStringArray()
var _showcasing: bool = false


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	slug = _arg("--map", DEFAULT_MAP)
	if _has("--sweep"):
		await get_tree().process_frame
		_run_sweep(_arg("--sweep", slug))
		get_tree().quit(0 if _bot_results.is_empty() else 1)
		return
	if _has("--world"):
		await _world_mode()
		return
	if not _load_map(slug):
		push_error("[sandbox] cannot load map chunk %s from %s (run the Blender export first)" % [slug, WORLD])
		get_tree().quit(2)
		return
	_setup_environment()
	_spawn_player()
	_setup_camera()
	_setup_label()
	if _has("--bot"):
		_start_bots(_arg("--bot", "all"), _has("--both"))
	elif _has("--showcase"):
		_showcase(_arg("--showcase", "user://shots"))


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	physics_ticks += 1
	# Only while the player simulates (MapSession freezes it during warps; is_on_floor() then holds its last value).
	if physics_ticks > 2 and player.can_process() and player.is_on_floor() != player.is_grounded():
		floor_mismatch_ticks += 1
		if _has("--verbose"):
			print("FLOOR_MISMATCH tick %d is_on_floor=%s state=%s pos=%s vy=%.2f" % [physics_ticks, player.is_on_floor(), PlayerController.State.keys()[player.state], player.global_position, player.vertical_speed])
			var body := player.get_node("CollisionShape3D") as CollisionShape3D
			var sensor := player.get_node("FloorSensor") as CollisionShape3D
			body.disabled = true
			sensor.disabled = false
			var c := player.move_and_collide(Vector3.DOWN * 0.5, true, player.safe_margin, true, 6)
			if c == null:
				print("   probe: no collision")
			else:
				for k in c.get_collision_count():
					print("   probe: n=%s angle=%.1f depth=%.4f travel=%s collider=%s" % [c.get_normal(k), rad_to_deg(c.get_angle(k)), c.get_depth(), c.get_travel(), (c.get_collider(k) as Node).name])
			sensor.disabled = true
			body.disabled = false
			print("   last floor normal=%s wall=%s ceiling=%s slides=%d" % [player.get_floor_normal(), player.is_on_wall(), player.is_on_ceiling(), player.get_slide_collision_count()])
	if _bot_index >= 0 and _bot_index < _bots.size():
		_tick_bot()


func _process(_delta: float) -> void:
	if _label != null and _label.visible and player != null:
		var p := player.global_position
		var where := slug
		if slug == "world":
			var session := get_tree().root.get_node_or_null(^"MapSession")
			where = "map %s" % (session.get("current_map") if session != null else "?")
		_label.text = "%s  fps %d\npos (%.2f, %.2f, %.2f)  %s%s%s\nspeed %.2f m/s  vy %.2f  on_floor %s  mismatches %d\nfalls %d  ortho %.1f  faded %d" % [
			where, Engine.get_frames_per_second(), p.x, p.y, p.z, PlayerController.State.keys()[player.state],
			"  HITSTUN" if player.in_hitstun else "", "  DEAD" if player.is_dead() else "",
			player.actual_velocity.length(), player.vertical_speed, player.is_on_floor(), floor_mismatch_ticks,
			falls, rig.ortho_size, rig.fader.active_count() if rig.fader else 0]


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.physical_keycode:
		KEY_F3:
			_label.visible = not _label.visible
		KEY_R:
			player.teleport(player.safe_ground.transform())
			rig.snap()
		KEY_F5:
			player.teleport(_start_xform())
			rig.snap()
		KEY_K:
			player.apply_knockback(-player.facing)


# --- loading -----------------------------------------------------------------------------------------------------

func _load_map(map_slug: String) -> bool:
	sidecar = _read_json("%s/%s.json" % [WORLD, map_slug])
	if sidecar.is_empty():
		return false
	var vis_path := "%s/%s.glb" % [WORLD, map_slug]
	var col_path := "%s/%s.collision.glb" % [WORLD, map_slug]
	if not ResourceLoader.exists(col_path):
		return false
	var col: PackedScene = load(col_path)
	add_child(col.instantiate())
	if ResourceLoader.exists(vis_path) and DisplayServer.get_name() != "headless":
		var vis: PackedScene = load(vis_path)
		var v := vis.instantiate()
		v.name = "Visual_" + map_slug
		add_child(v)
	if _has("--context") and DisplayServer.get_name() != "headless":
		for chunk in CONTEXT_CHUNKS:
			var p := "%s/%s.glb" % [WORLD, chunk]
			if ResourceLoader.exists(p):
				add_child((load(p) as PackedScene).instantiate())
	return true


func _setup_environment() -> void:
	var index := _read_json(WORLD + "/index.json")
	var env_info: Dictionary = index.get("environment", {})
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	var sun_info: Dictionary = env_info.get("sun", {})
	if sun_info.get("xform") is Array:
		var a: Array = sun_info["xform"]
		sun.transform = Transform3D(CameraMath.basis_from_xform_array(a), Vector3.ZERO)
	else:
		sun.rotation_degrees = Vector3(-50, -135, 0)
	if sun_info.get("color") is Array:
		var c: Array = sun_info["color"]
		sun.light_color = Color(float(c[0]), float(c[1]), float(c[2]))
	sun.light_energy = float(sun_info.get("strength", 5.5)) / PI
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#B9DCFF")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#B9DCFF")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	add_child(we)


func _start_xform() -> Transform3D:
	var ps: Dictionary = sidecar.get("player_start", {})
	if ps.get("xform") is Array:
		var a: Array = ps["xform"]
		return Transform3D(CameraMath.basis_from_xform_array(a), Vector3(float(a[9]), float(a[10]), float(a[11])))
	if ps.get("position") is Array:
		var p: Array = ps["position"]
		return Transform3D(Basis.IDENTITY, Vector3(float(p[0]), float(p[1]), float(p[2])))
	return Transform3D.IDENTITY


func _spawn_player() -> void:
	player = (load("res://scenes/actors/player.tscn") as PackedScene).instantiate() as PlayerController
	add_child(player)
	player.add_climbables_from_sidecar(sidecar.get("climbables", []))
	player.kill_y = float(sidecar.get("footprint", {}).get("base_y", 0.0)) - 6.0
	player.fell_out_of_world.connect(_on_fell)
	player.teleport(_start_xform())


func _setup_camera() -> void:
	rig = (load("res://scenes/actors/camera_rig.tscn") as PackedScene).instantiate() as CameraRig
	add_child(rig)
	var cams: Dictionary = sidecar.get("cameras", {})
	if cams.get("gameplay") is Dictionary:
		rig.configure_from_sidecar(cams["gameplay"])
	var fp: Dictionary = sidecar.get("footprint", {})
	rig.set_bounds(fp.get("outline_xz", []))
	rig.set_target(player)
	rig.scan_occluders(self)


func _setup_label() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)


func _on_fell(at: Vector3) -> void:
	falls += 1
	print("FALL at (%.2f, %.2f, %.2f); recovering to SafeGround" % [at.x, at.y, at.z])
	if _bot_index >= 0 and _bot_index < _bots.size():
		_bots[_bot_index].notify_fall()
	player.teleport(player.safe_ground.transform())
	rig.snap()


# --- real-time bot -----------------------------------------------------------------------------------------------

func _make_bots(side: Dictionary, which: String, both: bool, climbs: Array[ClimbableDef], movement: MovementModel, map_slug: String) -> Array[RouteBot]:
	var out: Array[RouteBot] = []
	for r in side.get("routes", []):
		if which != "all" and String(r["name"]) != which:
			continue
		var rb := RouteBot.create(r["points"], climbs, movement, "%s/%s" % [map_slug, r["name"]])
		out.append(rb)
		if both and not bool(r.get("one_way", false)):
			out.append(rb.reversed())
	return out


func _start_bots(which: String, both: bool) -> void:
	bot_input = BotInput.new()
	player.set_input_source(bot_input)
	_bots = _make_bots(sidecar, which, both, player.climbables, player.model, slug)
	print("BOT %d route runs on %s" % [_bots.size(), slug])
	_bot_index = -1
	_next_bot()


func _next_bot() -> void:
	_bot_index += 1
	if _bot_index >= _bots.size():
		print("BOT_SUMMARY map=%s runs=%d failed=%d falls=%d floor_mismatch_ticks=%d/%d" % [slug, _bots.size(), _bot_results.size(), falls, floor_mismatch_ticks, physics_ticks])
		for f in _bot_results:
			print("BOT_FAIL " + f)
		if _has("--quit") and not _showcasing:
			get_tree().quit(0 if _bot_results.is_empty() else 1)
		return
	var rb := _bots[_bot_index]
	var f := rb.start_facing()
	bot_input.release_all()
	player.teleport(Transform3D(Basis(Vector3.UP.cross(f).normalized(), Vector3.UP, f), rb.start_point() + Vector3.UP * 0.3))
	rig.snap()


func _tick_bot() -> void:
	var rb := _bots[_bot_index]
	if rb.tick(player, bot_input, get_physics_process_delta_time()) != RouteBot.Result.RUNNING:
		print("BOT " + rb.report())
		if rb.result != RouteBot.Result.DONE:
			_bot_results.append(rb.report())
		_next_bot()


# --- synchronous sweep (headless) ---------------------------------------------------------------------------------

func _run_sweep(spec: String) -> void:
	var slugs := PackedStringArray()
	if spec == "all":
		for f in DirAccess.get_files_at(WORLD):
			if f.ends_with(".json") and not f.begins_with("_") and not f.begins_with("World_") and f != "index.json":
				slugs.append(f.get_basename())
	else:
		slugs = spec.split(",", false)
	var db := ContentDB.new().load_all()
	var total := 0
	var t0 := Time.get_ticks_msec()
	for s in slugs:
		var side := _read_json("%s/%s.json" % [WORLD, s])
		var col_path := "%s/%s.collision.glb" % [WORLD, s]
		if side.is_empty() or not ResourceLoader.exists(col_path):
			print("BOT skip %s (no sidecar/collision)" % s)
			continue
		var w := PlayerTestWorld.create(db, self)
		w.add_node((load(col_path) as PackedScene).instantiate())
		var p := w.spawn_player(Vector3.ZERO)
		p.add_climbables_from_sidecar(side.get("climbables", []))
		p.kill_y = float(side.get("footprint", {}).get("base_y", 0.0)) - 6.0
		var current: Array = [null]
		p.fell_out_of_world.connect(func(_at: Vector3) -> void:
			if current[0] != null:
				(current[0] as RouteBot).notify_fall())
		for rb in _make_bots(side, "all", true, p.climbables, p.model, s):
			current[0] = rb
			total += 1
			w.bot.release_all()
			var f := rb.start_facing()
			p.teleport(Transform3D(Basis(Vector3.UP.cross(f).normalized(), Vector3.UP, f), rb.start_point() + Vector3.UP * 0.3))
			for i in int(rb.max_time_s * 60.0) + 60:
				if rb.tick(p, w.bot, PlayerTestWorld.TICK) != RouteBot.Result.RUNNING:
					break
				p.step(PlayerTestWorld.TICK)
			print("BOT " + rb.report())
			if rb.result != RouteBot.Result.DONE:
				_bot_results.append(rb.report())
				for e in rb.events:
					print("    " + e)
		w.free_all()
	print("BOT_SUMMARY maps=%d runs=%d failed=%d (%d ms)" % [slugs.size(), total, _bot_results.size(), Time.get_ticks_msec() - t0])
	for f in _bot_results:
		print("BOT_FAIL " + f)


# --- scripted showcase (screenshots) ------------------------------------------------------------------------------

func _showcase(dir: String) -> void:
	_showcasing = true
	DirAccess.make_dir_recursive_absolute(dir)
	bot_input = BotInput.new()
	player.set_input_source(bot_input)
	await _wait(1.0)
	await _shot(dir, "01_spawn")
	bot_input.move = Vector2(-1, 0)  # A: screen left
	await _wait(0.6)
	await _shot(dir, "02_walk_left")
	bot_input.move = Vector2.ZERO
	await _wait(0.3)
	bot_input.press(&"jump")  # standing jump: the blob shadow marks the landing spot
	await _wait_until(func() -> bool: return player.vertical_speed <= 0.0 and not player.is_grounded(), 2.0)
	await _shot(dir, "03_jump_apex")
	await _wait(0.8)
	# A ladder route: walk it with the bot and capture the climb.
	var ladder_route := ""
	for r in sidecar.get("routes", []):
		var rb := RouteBot.create(r["points"], player.climbables, player.model)
		for i in range(1, rb.points.size()):
			if rb.points[i].y - rb.points[i - 1].y > 2.0:
				ladder_route = String(r["name"])
				break
		if ladder_route != "":
			break
	if ladder_route != "":
		_bots = _make_bots(sidecar, ladder_route, false, player.climbables, player.model, slug)
		_bot_index = -1
		_next_bot()
		var climbed_shot := false
		while _bot_index < _bots.size():
			await get_tree().physics_frame
			if player.is_climbing() and not climbed_shot:
				await _wait(1.0)
				await _shot(dir, "04_climbing")
				climbed_shot = true
		await _wait(0.5)
		await _shot(dir, "05_route_end")
	# Occlusion: stand the player on the ground right behind (camera-wise) a tree, so the canopy hides them.
	var spot := _spot_behind_tree()
	if spot != Vector3.INF:
		player.teleport(Transform3D(Basis.IDENTITY, spot))
		rig.snap()
		await _wait(0.6)
		await _shot(dir, "06_behind_tree")
	print("SHOWCASE_DONE %s floor_mismatch_ticks=%d/%d falls=%d" % [dir, floor_mismatch_ticks, physics_ticks, falls])
	if _has("--quit"):
		get_tree().quit()


## A ground point just behind a tree (away from the camera) at the tree's own base height, or Vector3.INF.
func _spot_behind_tree() -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	for tree in _trees():
		var box := tree.global_transform * tree.get_aabb()
		var c := box.get_center()
		var p := c + rig.ground_forward * (maxf(box.size.x, box.size.z) * 0.5 + 0.7)
		q.from = Vector3(p.x, box.end.y, p.z)
		q.to = Vector3(p.x, box.position.y - 1.0, p.z)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and absf((hit["position"] as Vector3).y - box.position.y) < 0.6 and (hit["normal"] as Vector3).y > 0.8:
			return hit["position"]
	return Vector3.INF


func _trees() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var root := get_node_or_null(NodePath("Visual_" + slug))
	var stack: Array[Node] = [root if root != null else self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi != null and mi.has_meta(&"extras"):
			var ex: Variant = mi.get_meta(&"extras")
			if ex is Dictionary and String((ex as Dictionary).get("category", "")) == "Trees" and mi.get_aabb().size.y > 2.0:
				out.append(mi)
	return out


func _nearest_tree(at: Vector3) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_d := INF
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or not mi.has_meta(&"extras"):
			continue
		var ex: Variant = mi.get_meta(&"extras")
		if ex is Dictionary and String((ex as Dictionary).get("category", "")) == "Trees":
			var d := (mi.global_transform * mi.get_aabb()).get_center().distance_to(at)
			if d < best_d:
				best_d = d
				best = mi
	return best


func _wait_until(cond: Callable, timeout_s: float) -> void:
	var end := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await get_tree().physics_frame


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var frames := 0
	while Time.get_ticks_msec() < end or frames < int(seconds * 30.0):
		await get_tree().physics_frame
		frames += 1


func _shot(dir: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(label + ".png")
	img.save_png(path)
	print("SHOT %s" % path)


# --- integration with the world runtime ----------------------------------------------------------------------

func _world_mode() -> void:
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	var session := get_tree().root.get_node_or_null(^"MapSession")
	if scene == null or session == null:
		push_error("[sandbox] --world needs scenes/world/world.tscn and the MapSession autoload")
		get_tree().quit(2)
		return
	slug = "world"
	var world := scene.instantiate()
	# Headless runs load collision only (the threaded visual load crashes Godot's dummy renderer).
	if DisplayServer.get_name() == "headless" and "load_visuals" in world:
		world.set("load_visuals", false)
	var t0 := Time.get_ticks_msec()
	add_child(world)
	await world.world_ready
	print("WORLD ready in %d ms" % (Time.get_ticks_msec() - t0))
	player = (load("res://scenes/actors/player.tscn") as PackedScene).instantiate() as PlayerController
	add_child(player)
	world.call("set_player", player)
	rig = (load("res://scenes/actors/camera_rig.tscn") as PackedScene).instantiate() as CameraRig
	add_child(rig)
	rig.set_target(player)
	rig.scan_occluders(world)
	session.call("attach_camera", rig)
	_setup_label()
	session.call("start_new_game")
	var ok := await _check_arrival(session, "new game")
	var failures := 0 if ok else 1
	if _has("--all"):
		var defs: Object = world.get("defs")
		for id in defs.call("ids"):
			session.call("debug_warp", id)
			if not await _check_arrival(session, String(id)):
				failures += 1
	if _has("--shot"):
		await _wait(1.0)
		await _shot(_arg("--shot", "user://").get_base_dir(), _arg("--shot", "user://world.png").get_file().get_basename())
	print("WORLD_SUMMARY failures=%d floor_mismatch_ticks=%d/%d" % [failures, floor_mismatch_ticks, physics_ticks])
	if _has("--quit"):
		get_tree().quit(0 if failures == 0 else 1)


## Waits for MapSession to be idle, then for is_on_floor() (MAP_ARCHITECTURE 4.5: within 10 physics frames).
func _check_arrival(session: Node, label: String) -> bool:
	var frames := 0
	while not bool(session.call("is_idle")) and frames < 600:
		await get_tree().physics_frame
		frames += 1
	var floor_frames := 0
	while not player.is_on_floor() and floor_frames < 30:
		await get_tree().physics_frame
		floor_frames += 1
	var ok := player.is_on_floor() and player.is_grounded() and floor_frames <= 10 and rig.bounds_rect().size != Vector2.ZERO
	print("WORLD %s %s map=%s idle_after=%d on_floor_after=%d pos=(%.2f, %.2f, %.2f) ortho=%.2f bounds=%s" % ["ok  " if ok else "FAIL", label,
		session.get("current_map"), frames, floor_frames, player.global_position.x, player.global_position.y, player.global_position.z,
		rig.ortho_size, rig.bounds_rect().size])
	return ok


# --- helpers -----------------------------------------------------------------------------------------------------

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _has(flag: String) -> bool:
	return flag in _args


func _arg(flag: String, fallback: String) -> String:
	var i := _args.find(flag)
	if i >= 0 and i + 1 < _args.size() and not _args[i + 1].begins_with("--"):
		return _args[i + 1]
	return fallback
