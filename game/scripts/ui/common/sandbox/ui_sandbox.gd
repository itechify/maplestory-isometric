extends Node
## UI sandbox: the HUD and the character windows over a procedural Maple-Island-ish backdrop, wired exactly as the
## game shell wires them (a GameContext whose ui_root is a CanvasLayer, then setup(ctx)), with a populated character:
## potions, food, etc items, equipment worn and carried, mesos, a few levels with unspent AP, quickslot bindings,
## Sam's Suggestion in progress and one quest completed.
##
##   bash scripts/godot.sh --path <isolated copy>/game --resolution 1600x900 --disable-vsync \
##       res://scripts/ui/common/sandbox/ui_sandbox.tscn [-- --shots <dir>] [-- --quit]
##
## The character is assigned to Game.character directly (Game.new_game is NOT called), so no save is ever written and
## autosave stays inactive. Keyboard: I / E / C / Q open the windows, 1-8 use quickslots, Esc closes the newest
## window, F1 levels up (flourish), F2 shows a map banner, F4 adds a notice.
## --shots <dir> saves hud.png, windows_a.png (inventory + equipment + tooltip) and windows_b.png (stats + quests),
## then quits.

var ctx: GameContext
var ui_layer: CanvasLayer
var hud: MisoHud
var windows: MisoWindowsRoot
var character: CharacterState


func _ready() -> void:
	var backdrop_layer := CanvasLayer.new()
	backdrop_layer.layer = -1
	add_child(backdrop_layer)
	var backdrop := MisoSandboxBackdrop.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop_layer.add_child(backdrop)

	ui_layer = CanvasLayer.new()
	ui_layer.name = "UiRoot"
	add_child(ui_layer)
	ctx = GameContext.new()
	ctx.main = self
	ctx.ui_root = ui_layer

	_populate()
	hud = load("res://scenes/ui/hud.tscn").instantiate()
	ui_layer.add_child(hud)
	hud.setup(ctx)
	windows = load("res://scenes/ui/windows.tscn").instantiate()
	ui_layer.add_child(windows)
	windows.setup(ctx)
	_play_events()

	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0:
		var dir := args[i + 1] if i + 1 < args.size() else "user://ui_shots"
		await _shots(dir)
		get_tree().quit(0)
	elif "--quit" in args:
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)


func _populate() -> void:
	var db: ContentDB = Data.db
	var cr := CharacterFactory.create({"name": "Mapler", "ap": {"str": 5, "dex": 4}, "weapon_id": "541"}, db)
	character = cr.character
	Game.autosave_enabled = false
	Game.autosave_on_quit = false
	Game.character = character
	var items := ItemService.new(character, db, null)
	for e: Array in [["270", 37], ["271", 12], ["273", 8], ["236", 6], ["237", 3], ["348", 23], ["349", 7], ["350", 5],
			["439", 1], ["522", 1], ["1157", 1], ["933", 1], ["1305", 1], ["711", 1], ["551", 1], ["666", 1],
			["543", 1], ["709", 1], ["900", 1], ["59", 2]]:
		items.gain(String(e[0]), int(e[1]))
	items.gain_mesos(12345)
	# Levels 1 -> 5 through the real progression (canonical EXP table), plus part of level 5.
	while character.level < 5:
		Progression.gain_exp(character, Progression.exp_to_next(character.level, db) - character.exp, db)
	Progression.gain_exp(character, int(Progression.exp_to_next(character.level, db) * 0.42), db)
	for id in ["933", "1157", "1305", "711"]:
		items.equip(id)
	character.hp = int(StatCalculator.max_hp(character, db) * 0.7)
	character.mp = int(StatCalculator.max_mp(character, db) * 0.55)
	character.quickslots = {"1": "270", "2": "271", "3": "273", "5": "236"}
	# Quests through the game's own QuestService (Game.quests follows Game.character).
	if Game.quests != null:
		Game.quests.accept("1000")
		Game.quests.complete("1000", {"at_npc_id": Game.quests.engine.definition("1000").end_npc_id})
		Game.quests.accept("1006")


func _play_events() -> void:
	# Live events, as the game would emit them: kills, a pickup, mesos, a map arrival.
	for i in 7:
		Events.monster_killed.emit("2", "000000040")
	ItemService.new(character, Data.db, Events).gain("348", 2)
	ItemService.new(character, Data.db, Events).gain_mesos(4)
	Events.exp_gained.emit(3, "monster:2")
	Events.map_entered.emit("000000040", "000000030")


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_ESCAPE:
			ctx.close_top_window()
		KEY_F1:
			Game.gain_exp(Progression.exp_to_next(character.level, Data.db) - character.exp)
		KEY_F2:
			Events.map_entered.emit("000001000", "000000040")
		KEY_F4:
			Events.notice.emit("This is a notice.")


func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _frames(20)
	# Level-up flourish mid-pop for the HUD shot.
	Game.gain_exp(Progression.exp_to_next(character.level, Data.db) - character.exp)
	Progression.gain_exp(character, int(Progression.exp_to_next(character.level, Data.db) * 0.31), Data.db)
	Events.exp_gained.emit(0, "")
	await _wait(0.45)
	await _save(dir.path_join("hud.png"))

	await _wait(3.0)
	windows.open_window("inventory")
	windows.open_window("equipment")
	await _frames(4)
	var tab := "equip" if "--equip-tab" in OS.get_cmdline_user_args() else "use"
	windows.inventory.select_tab(tab)
	await _frames(4)
	if tab == "equip":
		var gladius := windows.inventory.visible_item_ids().find("551")
		if gladius >= 0:
			windows.inventory.select_slot(gladius)
			windows.show_item_tooltip("551", {"hint": "Double-click to equip"}, windows.inventory.slots[gladius])
	else:
		windows.inventory.select_slot(0)
		var hat: MisoItemSlot = windows.equipment.slot_controls["hat"]
		windows.show_item_tooltip(hat.item_id, {"equipped": true, "hint": "Double-click to take off"}, hat)
	await _frames(6)
	await _save(dir.path_join("windows_a.png"))

	windows.hide_item_tooltip()
	windows.close_window("inventory")
	windows.close_window("equipment")
	windows.open_window("stats")
	windows.open_window("quests")
	await _frames(6)
	await _save(dir.path_join("windows_b.png"))
	print("UI_SANDBOX_SHOTS ", dir)


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
