extends Node3D
## M0 performance gate (MAP_ARCHITECTURE.md §4.12): load every exported chunk (AllResident), then look through the
## worst gameplay views and an island overview, sampling frame time, GPU time, draw calls and primitives.
##
##   bash scripts/godot.sh --path game --resolution 1920x1080 --disable-vsync res://tools/perf_probe.tscn [-- --shots <dir>] [--no-shadows] [--skip a,b] [--quick]
##
## Prints one PERF line per view and PERF_DONE. Needs a real window (GPU timings are meaningless headless).

const WORLD_DIR := "res://assets/world"
const VIEWS := ["FieldWestOfAmherst_1000000", "Southperry_60000", "ASplitRoad_50000", "Amherst_1010000", "SnailHuntingGround2_40001"]

var _cam: Camera3D
var _shots_dir := ""
var _args: PackedStringArray = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_args = args
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		_shots_dir = args[i + 1]
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_setup_environment()
	var t0 := Time.get_ticks_msec()
	var count := 0
	for f in DirAccess.get_files_at(WORLD_DIR):
		if f.ends_with(".glb") and not f.ends_with(".collision.glb") and not f.begins_with("_library") and not _skipped(f):
			var scene: PackedScene = load(WORLD_DIR.path_join(f))
			if scene:
				add_child(scene.instantiate())
				count += 1
	print("PERF load: %d chunks in %d ms, %d nodes" % [count, Time.get_ticks_msec() - t0, _count_nodes(self)])
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 1.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.make_current()
	await _run()
	print("PERF_DONE")
	get_tree().quit()


func _setup_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -135, 0)
	sun.shadow_enabled = not ("--no-shadows" in _args)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#B9DCFF")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#B9DCFF")
	env.environment.ambient_light_energy = 0.5
	add_child(env)


func _run() -> void:
	for slug in VIEWS:
		var side: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WORLD_DIR.path_join(slug + ".json")))
		var cam: Dictionary = side.cameras.gameplay
		_apply_cam(cam.xform, float(cam.godot_size_keep_height))
		await _measure("gameplay:" + slug)
	var ov: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WORLD_DIR.path_join("FieldWestOfAmherst_1000000.json"))).cameras.overview
	_apply_cam(ov.xform, float(ov.godot_size_keep_height) * 3.2)
	await _measure("island_overview")


func _apply_cam(x: Array, size: float) -> void:
	_cam.transform = Transform3D(Basis(Vector3(x[0], x[1], x[2]), Vector3(x[3], x[4], x[5]), Vector3(x[6], x[7], x[8])), Vector3(x[9], x[10], x[11]))
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = size


func _measure(label: String) -> void:
	for _i in 30:
		await get_tree().process_frame
	var frames := 20 if "--quick" in _args else 90
	var cpu_ms := 0.0
	var gpu_ms := 0.0
	var draws := 0.0
	var prims := 0.0
	var worst := 0.0
	var vp := get_viewport().get_viewport_rid()
	var wall0 := Time.get_ticks_usec()
	for _i in frames:
		await get_tree().process_frame
		cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(vp) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var g := RenderingServer.viewport_get_measured_render_time_gpu(vp)
		gpu_ms += g
		worst = maxf(worst, g)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var frame_ms := (Time.get_ticks_usec() - wall0) / 1000.0 / frames
	print("PERF %s frame_ms=%.2f fps=%.0f cpu_ms=%.2f gpu_ms=%.2f gpu_worst_ms=%.2f draws=%d prims=%d" % [label,
		frame_ms, 1000.0 / frame_ms, cpu_ms / frames, gpu_ms / frames, worst, int(draws / frames), int(prims / frames)])
	if _shots_dir != "":
		DirAccess.make_dir_recursive_absolute(_shots_dir)
		get_viewport().get_texture().get_image().save_png(_shots_dir.path_join(label.replace(":", "_") + ".png"))


func _skipped(f: String) -> bool:
	var i := _args.find("--skip")
	if i < 0 or i + 1 >= _args.size():
		return false
	for pat in _args[i + 1].split(","):
		if pat != "" and pat in f:
			return true
	return false


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c
