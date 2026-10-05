extends Node3D
## Developer preview of the world runtime (not the game; wave 2 owns the main scene, player and camera rig).
##
##   bash scripts/godot.sh --path game --disable-vsync res://scenes/world/world_preview.tscn -- [--map <id>] [--portal <name>] [--shot <png>] [--quit]
##
## Loads scenes/world/world.tscn asynchronously (printing load_progress), drops the world's test capsule (with the
## Player_Proxy model) into MapSession's start map or --map, and frames each entered map with its Blender gameplay
## camera (cameras.gameplay). --shot saves a screenshot after the monsters have spawned; --quit exits afterwards.
## Keys while running: Up enters a portal (when inside one), F interacts, Space respawns at the next map in id order.

var world: IslandWorld = null
var player: WorldTestPlayer = null
var camera: Camera3D = null
var _args: PackedStringArray = []


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.far = 2000.0
	add_child(camera)
	camera.make_current()
	world = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	world.load_progress.connect(func(f: float, stage: String) -> void: print("LOAD %3d%% %s" % [int(f * 100.0), stage]))
	var t0 := Time.get_ticks_msec()
	add_child(world)
	await world.world_ready
	print("WORLD READY in %d ms: %s, %d warnings" % [Time.get_ticks_msec() - t0, str(world.stats), world.build_warnings.size()])
	player = WorldTestPlayer.new()
	player.configure(world.tuning.num("grounding", "capsule_radius_m"), world.tuning.num("grounding", "capsule_height_m"))
	var model := world.library.instance("Player_Proxy")
	if model != null:
		player.add_child(model)
	add_child(player)
	world.set_player(player)
	MapSession.attach_camera(self)
	var map_id := _arg("--map")
	if map_id != "":
		MapSession.debug_warp(map_id, _arg("--portal"))
	else:
		MapSession.start_new_game()
	if _arg("--shot") != "" or "--quit" in _args:
		for _i in 90:
			await get_tree().process_frame
		if _arg("--shot") != "":
			get_viewport().get_texture().get_image().save_png(_arg("--shot"))
			print("SHOT %s" % _arg("--shot"))
		print("INFO %s" % JSON.stringify(MapSession.debug_info()))
		if "--quit" in _args:
			get_tree().quit()


## Camera duck-typing for MapSession.attach_camera(): frame the map with its Blender gameplay camera.
func set_bounds(_bounds: PackedVector2Array, ortho_size: float, _blend_s: float) -> void:
	var def := world.defs.get_def(MapSession.current_map)
	if def == null:
		return
	camera.global_transform = def.environment_configuration.get("camera_xform", Transform3D.IDENTITY)
	camera.size = ortho_size


func snap() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_SPACE:
		var ids := world.defs.ids()
		var next := ids[(ids.find(MapSession.current_map) + 1) % ids.size()]
		MapSession.debug_warp(next)


func _arg(flag: String) -> String:
	var i := _args.find(flag)
	return _args[i + 1] if i >= 0 and i + 1 < _args.size() else ""
