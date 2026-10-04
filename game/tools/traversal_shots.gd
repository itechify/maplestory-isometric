extends Node
## Windowed visual check of walking the island (MAP_ARCHITECTURE.md section 4.13, milestone M2), scene
## res://tools/traversal_shots.tscn. Boots the real game (res://scenes/main.tscn: shell, HUD, camera, monsters),
## starts a new game and drives the game's PlayerController with a BotInput (RouteBot along the trail centreline,
## TraversalPaths around props), taking screenshots:
##   1. on the 000000040 -> 000000041 trail just before the far gate (still Snail Hunting Ground I)
##   2. just after the gate commit (the map name banner of Snail Hunting Ground II)
##   3. on the 000000030 -> 000000040 trail at the top of the one-way ledge
##   4. after dropping down the ledge (committed into 000000040)
##   5. from 000000040's landing, pushing into the ledge face (40 -> 30 is blocked)
##
##   bash scripts/godot.sh --path <game copy> --resolution 1600x900 --disable-vsync res://tools/traversal_shots.tscn -- --out <dir>
##
## Prints "TRAVERSAL_SHOT <path>" per screenshot and "TRAVERSAL_SHOTS_DONE <taken> <problems>".

const MAIN_SCENE := "res://scenes/main.tscn"
## Before the bot (-10 is the walker's): RouteBot decides before the player steps.
const PHYSICS_PRIORITY := -10
## Seconds after a commit before the "after" shot (the banner fades in).
const BANNER_WAIT_S := 0.7

var out_dir := "user://traversal_shots"
var main: MainShell = null
var session: Node = null
var player: PlayerController = null
var world: IslandWorld = null
var bot := BotInput.new()
var taken := 0
var problems := 0
var _rb: RouteBot = null


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir) if out_dir.contains("://") else out_dir)
	(get_node("/root/Saves") as Node).set("save_dir", "user://_tests/traversal_shots_%d" % Time.get_ticks_usec())
	main = (load(MAIN_SCENE) as PackedScene).instantiate() as MainShell
	main.use_command_line = false
	add_child(main)
	await _frames(5)
	main.open_creation()
	await _frames(5)
	main.start_new_game({"name": "Walker", "gender": "female", "ap": {"str": 9}, "weapon_id": "541"})
	await _until(func() -> bool: return main.game_session != null and main.flow.is_in(ShellFlow.State.PLAYING), 1800)
	if main.game_session == null:
		_problem("the game did not start: %s" % main.last_error_message)
		_done()
		return
	session = get_node("/root/MapSession")
	world = main.game_session.world as IslandWorld
	player = main.game_session.player as PlayerController
	player.set_input_source(bot)
	var d := world.defs
	# 1-2: across the 40 -> 41 gate.
	await _warp("000000040", "east00")
	var src := d.portal("000000040", "east00")
	var g41 := d.trail(src.link_id).gate_into("000000041")
	_walk(TraversalTrails.trail_path(d, src))
	await _until(func() -> bool: return g41.signed_distance(player.global_position) > -1.6 or _rb == null, 1200)
	await _shot("trail_40_41_before_gate")
	await _until(func() -> bool: return String(session.get("current_map")) == "000000041" or _rb == null, 600)
	await _seconds(BANNER_WAIT_S)
	await _shot("trail_40_41_after_gate")
	_check(String(session.get("current_map")) == "000000041", "walked into 000000041 (in %s)" % String(session.get("current_map")))
	await _until(func() -> bool: return _rb == null, 600)
	# 3-4: down the one-way ledge.
	await _warp("000000030", "out00")
	var out00 := d.portal("000000030", "out00")
	var ledge := d.trail(out00.link_id)
	var g40 := ledge.gate_into("000000040")
	_walk(TraversalTrails.trail_path(d, out00))
	await _until(func() -> bool: return g40.signed_distance(player.global_position) > -2.5 or _rb == null, 2400)
	await _shot("ledge_30_40_top")
	await _until(func() -> bool: return String(session.get("current_map")) == "000000040" or _rb == null, 600)
	await _seconds(BANNER_WAIT_S)
	await _shot("ledge_30_40_landed")
	_check(String(session.get("current_map")) == "000000040", "dropped into 000000040 (in %s)" % String(session.get("current_map")))
	await _until(func() -> bool: return _rb == null, 600)
	# 5: 40 -> 30 blocked: push into the ledge face and jump.
	await _warp("000000040")
	bot.world_dir = -g40.normal
	for f in 150:
		if f % 12 == 0:
			bot.press(&"jump")
		await get_tree().physics_frame
	await _shot("ledge_40_blocked")
	bot.release_all()
	_check(String(session.get("current_map")) == "000000040", "40 -> 30 stayed in 000000040")
	_done()


func _physics_process(delta: float) -> void:
	if _rb == null or player == null:
		return
	if _rb.tick(player, bot, delta) != RouteBot.Result.RUNNING:
		if _rb.result != RouteBot.Result.DONE:
			_problem(_rb.report())
		_rb = null
		bot.release_all()


func _walk(path: PackedVector3Array) -> void:
	var pts := PackedVector3Array([player.global_position])
	for k in range(1, path.size()):
		pts.append(path[k])
	pts = TraversalPaths.resample(pts, 0.5)
	pts = TraversalPaths.with_clearance(world, pts, 2.0).path
	_rb = RouteBot.create(pts, player.climbables, player.model, "shots")


func _warp(map_id: String, portal_id: String = "") -> void:
	_rb = null
	bot.release_all()
	session.call("debug_warp", map_id, portal_id)
	await _until(func() -> bool: return bool(session.call("is_idle")), 300)
	await _seconds(1.5)


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	taken += 1
	var path := out_dir.path_join("%02d_%s.png" % [taken, label])
	var err := img.save_png(path)
	print("TRAVERSAL_SHOT %s %s map=%s pos=%s" % [ProjectSettings.globalize_path(path), error_string(err),
		String(session.get("current_map")) if session != null else "", player.global_position if player != null else Vector3.ZERO])


func _check(cond: bool, what: String) -> void:
	if not cond:
		_problem(what)


func _problem(what: String) -> void:
	problems += 1
	print("TRAVERSAL_SHOT_PROBLEM " + what)


func _done() -> void:
	print("TRAVERSAL_SHOTS_DONE %d %d" % [taken, problems])
	get_tree().quit(0 if problems == 0 else 1)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _until(cond: Callable, max_frames: int) -> void:
	for _i in max_frames:
		if bool(cond.call()):
			return
		await get_tree().physics_frame
