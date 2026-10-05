extends Node
## Integration screenshot check: runs the real game shell (res://scenes/main.tscn) with a quick-start character, so
## the HUD and windows are installed by SubsystemInstaller and set up with the real GameContext, over the real island.
## Saves --shots <dir>/game_hud.png, game_trail.png (the player placed mid-trail: RegionMonitor -> MapSession.trail_changed
## -> the HUD's trail line), game_death.png (the HUD under the death notice) and game_windows.png (all four windows at
## their default places), then quits. Prints "UI_GAME_CHECK ok|FAIL: ..." per check; exits 1 when one fails.
##
## Starting a game writes a save, so this refuses to run unless the project uses a custom user dir (patch the
## ISOLATE copy's project.godot: application/config/use_custom_user_dir=true, custom_user_dir_name=...). It must
## never touch the player's real saves.
##
##   bash scripts/godot.sh --path <isolated copy>/game --resolution 1600x900 --disable-vsync \
##       res://scripts/ui/common/sandbox/ui_game_check.tscn -- --shots <dir>

## Checks that failed so far.
var _failed := 0


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
	var hud := _hud(main)
	_check("the HUD is installed", hud != null)
	if hud != null:
		await _trail_line(hud, dir)
		await _death(main, hud, dir)
	# All four at their default places: the shot shows whether they fit side by side without overlapping.
	for w in ["stats", "quests", "equipment", "inventory"]:
		get_tree().call_group(MisoWindowsRoot.GROUP, &"open_window", w)
	await get_tree().create_timer(3.0).timeout
	await _save(dir.path_join("game_windows.png"))
	print("UI_GAME_CHECK_SHOTS ", dir)
	get_tree().quit(1 if _failed > 0 else 0)


## The trail line through the real chain: the player placed in the middle of a trail of the current map, the world's
## RegionMonitor samples it, MapSession.set_trail emits trail_changed, the HUD shows "-> <destination>"; back on the
## map, the line clears.
func _trail_line(hud: MisoHud, dir: String) -> void:
	var here := String(MapSession.current_map)
	var trail: TrailDef = null
	for t: TrailDef in MapSession.get_defs().trails_of(here):
		if t.has_geometry() and not t.hidden and t.centre.size() >= 3:
			trail = t
			break
	_check("%s has a walkable trail" % here, trail != null)
	if trail == null:
		return
	var world: Node = MapSession.world
	var player := world.get("player") as Node3D
	var home := player.global_transform
	world.call("place_player", Transform3D(Basis(), trail.centre[trail.centre.size() / 2] + Vector3(0, 0.3, 0)))
	var dest := trail.other_map(here)
	var shown := await _until(func() -> bool: return hud.banner.is_trail_showing(), 3.0)
	_check("on trail %s: MapSession.trail_destination is %s" % [trail.link_id, dest], MapSession.trail_destination == dest,
		String(MapSession.trail_destination))
	_check("the HUD shows the trail line", shown)
	var want := "-> " + String(Data.db.map(dest).get("name"))
	_check("the line reads \"%s\" under %s" % [want, String(Data.db.map(here).get("name"))],
		hud.banner.trail_label.text == want and hud.banner.name_label.text == String(Data.db.map(here).get("name")),
		"%s / %s" % [hud.banner.name_label.text, hud.banner.trail_label.text])
	await get_tree().create_timer(4.5).timeout
	_check("still held after the arrival banner's time", hud.banner.is_trail_showing() and hud.banner.modulate.a > 0.99)
	await _save(dir.path_join("game_trail.png"))
	world.call("place_player", home)
	_check("back on the map: the line clears", await _until(func() -> bool: return not hud.banner.trail_label.visible, 3.0))
	_check("still on %s" % here, String(MapSession.current_map) == here, String(MapSession.current_map))


## The HP gauge from the death to the respawn through the real shell: 0 under the notice while the character holds
## its respawn HP (whatever refreshes arrive), the character's HP once the respawn finishes.
func _death(main: Node, hud: MisoHud, dir: String) -> void:
	var c: CharacterState = Game.character
	Game.change_hp(-c.hp)
	var dead := await _until(func() -> bool: return _notice(main) != null and _notice(main).visible, 3.0)
	_check("dead: the notice is up", dead)
	if not dead:
		return
	_check("the character holds its respawn HP (%d)" % c.hp, c.hp > 0)
	_check("the HUD's HP gauge reads 0 under the notice", hud.status.hp_gauge.current == 0, hud.status.hp_gauge.value_label.text)
	Events.stats_changed.emit()
	Events.hp_changed.emit(c.hp, StatCalculator.max_hp(c, Data.db))
	_check("a refresh while dead keeps it at 0", hud.status.hp_gauge.current == 0, hud.status.hp_gauge.value_label.text)
	await _save(dir.path_join("game_death.png"))
	_notice(main).call("confirm")
	var back := await _until(func() -> bool: return bool(MapSession.call("is_idle")) and not hud.dead, 6.0)
	_check("respawned", back)
	_check("the HUD's HP gauge shows the character's HP again (%d)" % c.hp, hud.status.hp_gauge.current == c.hp and c.hp > 0,
		hud.status.hp_gauge.value_label.text)


func _hud(main: Node) -> MisoHud:
	for n in (main.call("ctx") as GameContext).ui_root.find_children("*", "", true, false):
		if n is MisoHud:
			return n
	return null


## The shell's death notice (main.game_session.death.notice), or null.
func _notice(main: Node) -> Control:
	var gs: Variant = main.get("game_session")
	var death: Variant = (gs as Object).get("death") if gs is Object else null
	var n: Variant = (death as Object).get("notice") if death is Object else null
	return n as Control


func _check(what: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failed += 1
	print("UI_GAME_CHECK %s: %s%s" % ["ok" if ok else "FAIL", what, "" if ok or detail == "" else " (%s)" % detail])


func _until(cond: Callable, timeout_s: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < end:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
