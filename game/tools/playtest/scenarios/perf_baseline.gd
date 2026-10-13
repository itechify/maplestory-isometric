extends PlaytestScenario
## perf_baseline: the performance baseline of the real game (#62, gating every #59 art ticket). New game -> the island
## load time -> in each of the busiest maps (warped to its spawn, the gameplay camera, its monsters spawned) the frame
## rate, CPU and GPU frame time, draw calls, primitives, memory and node count over a few seconds of play.
## Writes <out>/perf.json and prints one PERF line per map. Needs a real window at the target size, without vsync
## and in real time (fixed-fps would cap the frame rate):
##
##   PLAYTEST_RESOLUTION=1920x1080 bash scripts/playtest.sh perf_baseline --windowed --realtime --out <dir>
##   PERF_EQUIP=1 ...                                  # the same with a fully equipped player (#68)
##
## The committed baseline is docs/runtime/PERF_BASELINE.md (with docs/runtime/perf_baseline.json).

## The busiest maps: the perf gate's gameplay views (MAP_ARCHITECTURE.md 4.12) plus the densest hunting ground.
## MeowDB ids: The Field West of Amherst, Southperry, A Split Road, Amherst, Snail Hunting Ground II.
const MAPS := ["000001000", "000000060", "000000050", "000001010", "000000041"]
const SETTLE_S := 5.0
const SAMPLE_FRAMES := 300
## With PERF_EQUIP=1 the (female) player wears these on top of the starter sword: a hat, a top, a bottom, shoes and
## earrings.
const FULL_KIT := ["708", "937", "1160", "1306", "900"]


func description() -> String:
	return "load time, then fps, frame time, draw calls, primitives and memory in %s" % [", ".join(MAPS)]


func max_seconds() -> float:
	return 600.0


func run(d: PlaytestDriver) -> void:
	var vp := d.main.get_viewport()
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var t0 := Time.get_ticks_msec()
	var ng: Dictionary = await d.new_game("Perf", "female", "541")
	var new_game_ms := Time.get_ticks_msec() - t0
	if not d.check("the game started", bool(ng["ok"]), str(ng["why"])):
		return
	var gs: GameSession = d.main.game_session
	# PERF_EQUIP=1: the player fully equipped (#68's gate), by the Item window as a player does (setup only).
	var equipped := {}
	if OS.get_environment("PERF_EQUIP") == "1":
		await d.console("level 15")
		var kit := PlaytestKit.new(d)
		for id: String in FULL_KIT:
			await d.console("give %s 1" % id)
			d.soft_check("equip %s" % id, bool((await kit.equip(id))["ok"]))
		equipped = d.character().equipment.equipped()
	var result := {
		"equipped": equipped,
		"windowed": DisplayServer.get_name() != "headless",
		"window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"vsync": DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
		"gpu": RenderingServer.get_video_adapter_name(),
		"world_load_ms": gs.world_load_ms if gs != null else -1,
		"new_game_ms": new_game_ms,
		"maps": [],
	}
	d.note("PERF load world_load_ms=%d new_game_ms=%d" % [result.world_load_ms, new_game_ms])
	for map_id in MAPS:
		await d.console("warp %s" % map_id)
		var landed := d.current_map()
		d.check("warped to %s" % map_id, landed == map_id, landed)
		await d.wait(SETTLE_S)
		var m := await _sample(d, vp)
		m["map"] = landed
		result.maps.append(m)
		var line := "PERF %s fps=%.1f frame_ms=%.2f cpu_ms=%.2f gpu_ms=%.2f draws=%d prims=%d static_mb=%.0f video_mb=%.0f nodes=%d" % [
			landed, m.fps, m.frame_ms, m.cpu_ms, m.gpu_ms, m.draws, m.prims, m.static_mb, m.video_mb, m.nodes]
		print(line)
		d.note(line)
	var f := FileAccess.open(d.out_dir.path_join("perf.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result, "  ") + "\n")
		f.close()
	d.check("perf.json written", f != null, d.out_dir)


func _sample(d: PlaytestDriver, vp: Viewport) -> Dictionary:
	var rid := vp.get_viewport_rid()
	var cpu := 0.0
	var gpu := 0.0
	var draws := 0.0
	var prims := 0.0
	var worst := 0.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	for _i in SAMPLE_FRAMES:
		await d.frames(1)
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var frame_ms := (Time.get_ticks_usec() - t0) / 1000.0 / SAMPLE_FRAMES
	return {
		"fps": 1000.0 / frame_ms, "frame_ms": frame_ms, "worst_frame_ms": worst,
		"cpu_ms": cpu / SAMPLE_FRAMES, "gpu_ms": gpu / SAMPLE_FRAMES,
		"draws": int(draws / SAMPLE_FRAMES), "prims": int(prims / SAMPLE_FRAMES),
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"monsters": _live_monsters(d),
	}


func _live_monsters(d: PlaytestDriver) -> int:
	var ms := d.monsters()
	return (ms.call("live_monsters") as Array).size() if ms != null and ms.has_method("live_monsters") else -1
