extends Node
## Integration screenshot check: runs the real game shell (res://scenes/main.tscn) with a quick-start character, so
## the HUD and windows are installed by SubsystemInstaller and set up with the real GameContext, over the real island.
## Saves --shots <dir>/game_hud.png and game_windows.png (all four windows at their default places), then quits.
##
## Starting a game writes a save, so this refuses to run unless the project uses a custom user dir (patch the
## ISOLATE copy's project.godot: application/config/use_custom_user_dir=true, custom_user_dir_name=...). It must
## never touch the player's real saves.
##
##   bash scripts/godot.sh --path <isolated copy>/game --resolution 1600x900 --disable-vsync \
##       res://scripts/ui/common/sandbox/ui_game_check.tscn -- --shots <dir>


func _ready() -> void:
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)):
		push_error("[ui_game_check] refusing to start a game: no custom user dir (it would write a real save)")
		get_tree().quit(2)
		return
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	var dir := args[i + 1] if i >= 0 and i + 1 < args.size() else "user://ui_game_shots"
	DirAccess.make_dir_recursive_absolute(dir)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.set("use_command_line", false)
	add_child(main)
	await get_tree().process_frame
	var err: Error = await main.call("start_new_game", CharacterFactory.default_params(Data.db))
	if err != OK:
		push_error("[ui_game_check] start_new_game failed: %s" % error_string(err))
		get_tree().quit(1)
		return
	await get_tree().create_timer(2.5).timeout
	# Some play: a pickup, mesos, EXP to a level-up, a bound potion, an accepted quest with progress.
	var c: CharacterState = Game.character
	var items := ItemService.new(c, Data.db, Events)
	items.gain("270", 24)
	items.gain("1157", 1)
	items.gain("348", 4)
	items.gain_mesos(250)
	Game.gain_exp(Progression.exp_to_next(c.level, Data.db))
	c.quickslots["1"] = "270"
	MisoQuickslots.notify()
	if Game.quests != null:
		Game.quests.accept("1006")
		for k in 3:
			Events.monster_killed.emit("2", MapSession.current_map)
	await get_tree().create_timer(0.5).timeout
	await _save(dir.path_join("game_hud.png"))
	# All four at their default places: the shot shows whether they fit side by side without overlapping.
	for w in ["stats", "quests", "equipment", "inventory"]:
		get_tree().call_group(MisoWindowsRoot.GROUP, &"open_window", w)
	await get_tree().create_timer(3.0).timeout
	await _save(dir.path_join("game_windows.png"))
	print("UI_GAME_CHECK_SHOTS ", dir)
	get_tree().quit(0)


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
