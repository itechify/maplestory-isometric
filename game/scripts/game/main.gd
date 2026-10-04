class_name MainShell
extends Node
## The main scene (res://scenes/main.tscn, the project's run/main_scene): boots to the title screen and owns the flow
## between screens (ShellFlow), the running game (GameSession), the pause menu and quitting. See
## docs/runtime/GAME_SHELL.md.
##
##   title --New Game--> creation --Start--> loading --> playing        title --Continue / Load--> loading --> playing
##   playing --Esc (no window open)--> pause menu: Resume, Save, Load, Controls, Quit to Title, Quit Game
##   playing --HP 0--> death (loss taken and saved at once) + notice --OK--> respawn at the return map --> playing
##   quit to title: the session is torn down and MapSession reset to BOOT, so Continue / Load start clean
##
## At boot the root window gets MisoTheme (apply_ui_theme), so tooltips and popups share the screens' look.
##
## The shell never touches canonical numbers: creation rules are CharacterFactory's, death rules DeathRules', saving
## Game's and Saves'. Every action is a public method, so the checks scene (shell_checks.tscn) drives exactly what the
## buttons do.
##
## Command line (after `--`): --quick-start  skip the title: a quick-start character in a new slot
##                            --continue     skip the title: continue the most recent save

signal session_started
signal session_ended
## A start/continue/load failed; the title shows `message`.
signal session_failed(message: String)

const SCREEN_LAYER := 110

var flow: ShellFlow = ShellFlow.new()
var game_session: GameSession = null
var screens: CanvasLayer = null
var title: TitleScreen = null
var creation: CreationScreen = null
var loading: LoadingScreen = null
var pause_menu: PauseMenu = null
## Load the island's visual chunks (forced off when headless).
var load_visuals: bool = true
## Read the command line in _ready (the checks scene switches it off).
var use_command_line: bool = true
## The slot a running new game was written to.
var target_slot: String = ""
var last_error_message: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply_ui_theme(get_tree().root)
	screens = CanvasLayer.new()
	screens.name = "Screens"
	screens.layer = SCREEN_LAYER
	screens.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(screens)
	title = TitleScreen.new()
	title.new_game_pressed.connect(open_creation)
	title.continue_pressed.connect(func(slot: String) -> void: load_slot(slot, ShellFlow.EV_CONTINUE))
	title.load_pressed.connect(func(slot: String) -> void: load_slot(slot))
	title.restore_pressed.connect(_restore_backup)
	title.quit_pressed.connect(quit_game)
	screens.add_child(title)
	loading = LoadingScreen.new()
	loading.visible = false
	screens.add_child(loading)
	pause_menu = PauseMenu.new()
	pause_menu.visible = false
	pause_menu.resume_pressed.connect(resume)
	pause_menu.save_pressed.connect(_on_pause_save)
	pause_menu.load_requested.connect(func() -> void: pause_menu.set_saves(_saves_list()))
	pause_menu.load_chosen.connect(func(slot: String) -> void: load_in_game(slot))
	pause_menu.quit_to_title_pressed.connect(quit_to_title)
	pause_menu.quit_game_pressed.connect(quit_game)
	screens.add_child(pause_menu)
	flow.changed.connect(_on_flow_changed)
	# Connected at boot, so before any session's DeathController (signals run in connection order).
	var ev := _autoload("Events")
	if ev != null and ev.has_signal(&"player_died") and not ev.is_connected(&"player_died", _on_player_died):
		ev.connect(&"player_died", _on_player_died)
	flow.fire(ShellFlow.EV_BOOT)
	show_title()
	if use_command_line:
		_apply_command_line.call_deferred()


## The whole UI's theme: MisoTheme.get_theme() on the root window, so every Control without a theme of its own,
## tooltips and popups included, shares the look. MisoTheme is loaded by path (ScreenKit.theme()); without it the
## window keeps Godot's default theme and this returns false.
static func apply_ui_theme(window: Window) -> bool:
	var t := ScreenKit.theme()
	if t == null or window == null:
		return false
	window.theme = t
	return true


## Closing the window: Game saves on its own when saving is allowed (it is notified first, as an autoload), and that
## includes a death, which is committed (and saved) the moment it happens. The shell only covers a death that is not
## committed yet (see commit_death_on_quit).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		commit_death_on_quit()
		flow.fire(ShellFlow.EV_QUIT)


## Quitting while dead: a committed death is saved again; a death during a warp, not committed yet, is committed here
## (penalty applied once, saved at the respawn point), so closing the game never skips it. Returns the save error, or
## ERR_UNAVAILABLE when the player is not dead.
func commit_death_on_quit() -> Error:
	if game_session == null or game_session.death == null or not game_session.death.is_dead():
		return ERR_UNAVAILABLE
	return game_session.death.commit_death_for_quit()


# --- screens --------------------------------------------------------------------------------------------------

## Shows the title with the current save list.
func show_title(message: String = "") -> void:
	_hide_screens()
	title.set_saves(_saves_list())
	title.show_message(message)
	title.hide_slots()
	title.show()
	title.focus_default()


## Title -> character creation.
func open_creation() -> bool:
	if not flow.fire(ShellFlow.EV_NEW_GAME):
		return false
	_hide_screens()
	creation = CreationScreen.new(CreationModel.new(_db()))
	creation.start_pressed.connect(func(params: Dictionary) -> void: start_new_game(params))
	creation.back_pressed.connect(back_to_title)
	screens.add_child(creation)
	creation.set_target_slot(SaveSlotIndex.next_free_slot(_saves_list()))
	creation.focus_default()
	return true


## Creation -> title.
func back_to_title() -> bool:
	if not flow.fire(ShellFlow.EV_BACK):
		return false
	show_title()
	return true


# --- starting a game ----------------------------------------------------------------------------------------------

## Starts a new game with creation params (CreationModel.params()) in the first free slot. From the title (quick
## start) or the creation screen. Returns OK once the player stands in the world.
func start_new_game(params: Dictionary) -> Error:
	if not flow.can(ShellFlow.EV_START):
		return ERR_UNAVAILABLE
	var p := params.duplicate(true)
	if not p.has("slot"):
		p["slot"] = SaveSlotIndex.next_free_slot(_saves_list())
	target_slot = String(p["slot"])
	flow.fire(ShellFlow.EV_START)
	return await _run_session(GameSession.MODE_NEW, p)


## Continues the most recent loadable save.
func continue_game() -> Error:
	var slot := SaveSlotIndex.continue_slot(_saves_list())
	if slot == "":
		return ERR_FILE_NOT_FOUND
	return await load_slot(slot, ShellFlow.EV_CONTINUE)


## Title: loads a slot into a fresh session (event: EV_LOAD from the slot list, EV_CONTINUE from Continue).
func load_slot(slot: String, event: String = ShellFlow.EV_LOAD) -> Error:
	if not flow.is_in(ShellFlow.State.TITLE) or not flow.can(event):
		return ERR_UNAVAILABLE
	var saves := _autoload("Saves")
	if saves != null:
		var r: SaveLoadResult = saves.call("read_for_load", slot)
		if not r.ok():
			show_title("Cannot load %s: %s" % [slot, r.message])
			return r.error
	target_slot = slot
	flow.fire(event)
	return await _run_session(GameSession.MODE_LOAD, slot)


func _run_session(mode: String, arg: Variant) -> Error:
	_hide_screens()
	loading.set_progress(0.0, "loading")
	loading.show()
	if game_session != null:
		_end_session()
	game_session = GameSession.new()
	game_session.main = self
	game_session.load_visuals = load_visuals
	game_session.progress.connect(loading.set_progress)
	add_child(game_session)
	var err: Error = await game_session.start(mode, arg)
	if err != OK:
		last_error_message = game_session.error_message if game_session != null else error_string(err)
		_end_session()
		flow.fire(ShellFlow.EV_FAILED)
		show_title(last_error_message)
		session_failed.emit(last_error_message)
		return err
	game_session.death.died.connect(func(_map_id: String) -> void: flow.fire(ShellFlow.EV_DIED))
	game_session.death.respawned.connect(func(_map_id: String, _report: Dictionary) -> void:
		flow.fire(ShellFlow.EV_RESPAWNED))
	# A load or new game out of DEAD (the debug console's load / reset_save) ends the death without a respawn.
	game_session.death.death_cleared.connect(func(_map_id: String) -> void: flow.fire(ShellFlow.EV_RESPAWNED))
	flow.fire(ShellFlow.EV_READY)
	loading.hide()
	session_started.emit()
	return OK


# --- in game ------------------------------------------------------------------------------------------------------

## The running game's context (null outside a game).
func ctx() -> GameContext:
	return game_session.ctx if game_session != null else null


## Opens the pause menu: the world pauses (SceneTree.paused, Game.paused) and the menu is a modal.
func pause() -> bool:
	if not flow.is_in(ShellFlow.State.PLAYING) or not _session_idle():
		return false
	var c := ctx()
	if c != null and c.is_modal_active():
		return false
	flow.fire(ShellFlow.EV_PAUSE)
	get_tree().paused = true
	_set_game_paused(true)
	if c != null:
		c.push_modal(pause_menu)
	pause_menu.open()
	return true


## Closes the pause menu and unpauses.
func resume() -> bool:
	if not flow.is_in(ShellFlow.State.PAUSED):
		return false
	_unpause()
	flow.fire(ShellFlow.EV_RESUME)
	return true


## Saves the running game into its slot (Game.save_game; refused while MapSession.can_save() is false).
func save_now() -> Error:
	var game := _autoload("Game") as GameState
	if game == null or not game.has_active_game():
		return ERR_UNCONFIGURED
	return game.save_game()


## Pause menu: loads `slot` in place (MapSession re-enters the world where the save says).
func load_in_game(slot: String) -> Error:
	if not flow.is_in(ShellFlow.State.PAUSED):
		return ERR_UNAVAILABLE
	var saves := _autoload("Saves")
	if saves != null:
		var r: SaveLoadResult = saves.call("read_for_load", slot)
		if not r.ok():
			pause_menu.set_status("Cannot load %s: %s" % [slot, r.message], true)
			return r.error
	_unpause()
	flow.fire(ShellFlow.EV_LOAD)
	var game := _autoload("Game") as GameState
	var err := game.load_game(slot) if game != null else ERR_UNCONFIGURED
	if err == OK:
		target_slot = slot
	return err


## Saves (when allowed), ends the game and shows the title.
func quit_to_title() -> Error:
	if not flow.is_in(ShellFlow.State.PAUSED) and not flow.is_in(ShellFlow.State.PLAYING):
		return ERR_UNAVAILABLE
	var err := save_now()
	if err != OK and err != ERR_UNCONFIGURED:
		push_warning("[MainShell] quit to title without saving: %s" % error_string(err))
	_unpause()
	_end_session()
	flow.fire(ShellFlow.EV_QUIT_TO_TITLE)
	show_title()
	return err


## Saves (when a game runs and saving is allowed; while dead through commit_death_on_quit) and quits the application.
func quit_game() -> void:
	var dead := game_session != null and game_session.death != null and game_session.death.is_dead()
	if dead:
		commit_death_on_quit()
	elif game_session != null:
		var err := save_now()
		if err != OK and err != ERR_UNCONFIGURED:
			push_warning("[MainShell] quitting without saving: %s" % error_string(err))
	flow.fire(ShellFlow.EV_QUIT)
	_unpause()
	get_tree().quit()


# --- input --------------------------------------------------------------------------------------------------------

## Esc ("menu"): the newest window closes first (GameContext.close_top_window); with none open the pause menu opens.
## Never while a modal (dialogue, shop, console, death notice) owns the keyboard or a map transition runs.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"menu") or event.is_echo():
		return
	if handle_menu_action():
		get_viewport().set_input_as_handled()


## What Esc does in the current state; true when it was used.
func handle_menu_action() -> bool:
	match flow.state:
		ShellFlow.State.PLAYING:
			var c := ctx()
			if c != null and c.close_top_window():
				return true
			return pause()
		ShellFlow.State.PAUSED:
			if pause_menu.back():
				return true
			return resume()
		ShellFlow.State.CREATE:
			return back_to_title()
		ShellFlow.State.TITLE:
			if title.slots_open():
				title.hide_slots()
				return true
	return false


# --- internals ----------------------------------------------------------------------------------------------------

## A death announced while the pause menu is open (ShellFlow allows PAUSED --died--> DEAD; no gameplay path does it
## today, the world is paused): the menu closes and the tree unpauses before the DeathController hears the death, so
## the notice is the only modal and the game is never left paused under a Resume and a Quit to Title that DEAD refuses.
func _on_player_died(_map_id: String) -> void:
	if flow.is_in(ShellFlow.State.PAUSED):
		_unpause()


func _on_pause_save() -> void:
	var err := save_now()
	var game := _autoload("Game") as GameState
	if err == OK:
		pause_menu.set_status("Saved to %s." % (game.current_slot if game != null else target_slot))
	else:
		var saves := _autoload("Saves")
		var why := String(saves.get("last_error_message")) if saves != null else error_string(err)
		pause_menu.set_status("Could not save: %s" % why, true)


func _restore_backup(slot: String) -> void:
	var saves := _autoload("Saves")
	var err: Error = saves.call("restore_backup", slot) if saves != null else ERR_UNCONFIGURED
	show_title("" if err == OK else "Could not restore the backup of %s (%s)." % [slot, error_string(err)])


func _unpause() -> void:
	get_tree().paused = false
	_set_game_paused(false)
	if pause_menu.visible:
		pause_menu.hide()
		var c := ctx()
		if c != null:
			c.pop_modal(pause_menu)


func _set_game_paused(on: bool) -> void:
	var game := _autoload("Game")
	if game != null:
		game.set("paused", on)


## Tears the running game down (no save: callers save first) and deactivates Game.
func _end_session() -> void:
	var game := _autoload("Game") as GameState
	if game != null:
		game.close_game()
	if game_session != null:
		game_session.teardown()
		game_session = null
		session_ended.emit()


func _hide_screens() -> void:
	title.hide()
	loading.hide()
	pause_menu.hide()
	if creation != null and is_instance_valid(creation):
		creation.queue_free()
		creation = null


func _on_flow_changed(new_state: ShellFlow.State, old_state: ShellFlow.State, event: String) -> void:
	print("[MainShell] %s -> %s (%s)" % [ShellFlow.state_name(old_state), ShellFlow.state_name(new_state), event])


func _session_idle() -> bool:
	var session := _autoload("MapSession")
	return session != null and bool(session.call("is_idle"))


func _saves_list() -> Array:
	var saves := _autoload("Saves")
	return saves.call("list_saves") if saves != null else []


func _apply_command_line() -> void:
	var args := OS.get_cmdline_user_args()
	if "--continue" in args and flow.is_in(ShellFlow.State.TITLE):
		continue_game()
	elif "--quick-start" in args and flow.is_in(ShellFlow.State.TITLE):
		start_new_game(CharacterFactory.default_params(_db()))


func _db() -> ContentDB:
	var data := _autoload("Data")
	return data.get("db") as ContentDB if data != null else null


static func _autoload(autoload_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(autoload_name) if tree != null else null
