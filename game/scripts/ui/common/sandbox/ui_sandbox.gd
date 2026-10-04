extends Node
## UI sandbox: the HUD and the character windows over a procedural Maple-Island-ish backdrop, wired as the game shell
## wires them (a GameContext whose ui_root is a CanvasLayer; the windows get setup(ctx), the HUD what setup(ctx) does,
## configure(MisoUiEnv.from_ctx(ctx)), with a private map session injected for the trail line), with a populated character:
## potions, food, etc items, equipment worn and carried, mesos, a few levels with unspent AP, quickslot bindings,
## Sam's Suggestion in progress and one quest completed.
##
##   bash scripts/godot.sh --path <isolated copy>/game --resolution 1600x900 --disable-vsync \
##       res://scripts/ui/common/sandbox/ui_sandbox.tscn [-- --shots <dir>] [-- --quit]
##
## The character is assigned to Game.character directly (Game.new_game is NOT called), so no save is ever written and
## autosave stays inactive. Keyboard: I / E / C / Q open the windows, 1-8 use quickslots, Esc closes the newest
## window, F1 levels up (flourish), F2 shows a map banner, F3 toggles the trail line (000000040 -> 000000041), F4 adds
## a notice, F5 toggles a death (HP gauge at 0 until the "respawn").
## --shots <dir> saves hud.png, windows_a.png (inventory + equipment + tooltip), windows_b.png (stats + quests) and
## trail.png (the trail line, with the HUD of a death), then quits.
##
## The trail line comes from a private map_session.gd instance (not the MapSession autoload, which stays untouched).

const TRAIL_FROM := "000000040"
const TRAIL_TO := "000000041"
const TRAIL_LINK := "T_000000040_east00__000000041_west00"

var ctx: GameContext
var ui_layer: CanvasLayer
var hud: MisoHud
var windows: MisoWindowsRoot
var character: CharacterState
## A private MapSession standing on TRAIL_FROM: drives the HUD's trail line.
var session: Node
var _dead := false


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
	session = load("res://scripts/autoload/map_session.gd").new()
	session.current_map = TRAIL_FROM
	hud = load("res://scenes/ui/hud.tscn").instantiate()
	ui_layer.add_child(hud)
	# What setup(ctx) does, with the private session in place of the MapSession autoload.
	var hud_env := MisoUiEnv.from_ctx(ctx)
	hud_env.map_session = session
	hud.configure(hud_env)
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
		KEY_F3:
			_toggle_trail()
		KEY_F4:
			Events.notice.emit("This is a notice.")
		KEY_F5:
			_toggle_death()


## The HUD (a descendant) has already left the tree and disconnected from the session.
func _exit_tree() -> void:
	if session != null:
		session.free()
		session = null


## The player steps onto (or off) the trail from TRAIL_FROM to TRAIL_TO.
func _toggle_trail() -> void:
	if String(session.trail_destination) == "":
		session.set_trail(TRAIL_LINK, TRAIL_TO)
	else:
		session.set_trail("", "")


## A death (the HP gauge reads 0 while the character holds HP) and its respawn. Only the HUD hears these: the
## events go to the HUD's handlers directly, so the Events autoload's other listeners (MapSession) stay out of it.
func _toggle_death() -> void:
	_dead = not _dead
	if _dead:
		hud._on_player_died(TRAIL_FROM)
	else:
		hud._on_player_respawned(TRAIL_FROM)


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

	windows.close_all()
	_toggle_trail()
	_toggle_death()
	await _wait(MisoMapBanner.FADE_IN_S + 0.2)
	await _save(dir.path_join("trail.png"))
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
