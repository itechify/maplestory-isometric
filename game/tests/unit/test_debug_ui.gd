extends TestCase
## The debug UI scene (res://scenes/debug/debug_ui.tscn) headless, on a private DebugHarness: setup(ctx) wires the
## context into Debug; the backtick and F3 actions toggle the console and the overlay; the console is modal while open
## (push_modal / window_opened, popped on close and on Esc); lines go through Debug.run(); history and Tab completion;
## commands run by code are mirrored; the overlay shows Debug.overlay_text().

const SCENE := "res://scenes/debug/debug_ui.tscn"

var h: DebugHarness = null
var ui: DebugUI = null
var ctx: FakeContext = null


## The GameContext surface the debug UI uses.
class FakeContext:
	extends RefCounted
	var world: Node = null
	var player: Node = null
	var camera: Object = null
	var ui_root: Node = null
	var systems: Node = null
	var modals: Array = []
	var windows: Array = []

	func push_modal(owner: Object) -> void:
		modals.append(owner)

	func pop_modal(owner: Object) -> void:
		modals.erase(owner)

	func window_opened(w: Control) -> void:
		windows.append(w)

	func window_closed(w: Control) -> void:
		windows.erase(w)


func before_each() -> void:
	h = DebugHarness.create(db())
	ui = (load(SCENE) as PackedScene).instantiate() as DebugUI
	ui.dbg = h.dbg
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(ui)
	ctx = FakeContext.new()
	ui.setup(ctx)


func after_each() -> void:
	ui.free()
	h.free_all()


func _key(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	ui.get_viewport().push_input(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	ui.get_viewport().push_input(up)


func test_scene_root_and_setup() -> void:
	assert_true(ui is CanvasLayer, "a CanvasLayer root")
	assert_true(ui.has_method("setup"), "setup(ctx)")
	assert_eq(h.dbg.ctx, ctx, "setup hands the context to Debug")
	assert_false(ui.console.visible, "console starts closed")
	assert_false(ui.overlay.visible, "overlay starts hidden")
	# The console must draw over the world's ScreenFader (100) and the shell's screens (loading, pause menu), or every
	# warp typed into it darkens it and Esc-then-` puts it under the pause menu.
	assert_eq(ui.layer, DebugUI.CANVAS_LAYER, "the scene's layer is the script's")
	var fader := ScreenFader.new()
	ui.add_child(fader)  # ScreenFader sets its layer in _ready
	assert_true(ui.layer > fader.layer, "above the world's ScreenFader (%d)" % fader.layer)
	fader.free()
	assert_true(ui.layer > MainShell.SCREEN_LAYER, "above the shell's screens (%d)" % MainShell.SCREEN_LAYER)


func test_backtick_opens_a_modal_console_and_escape_closes_it() -> void:
	_key(KEY_QUOTELEFT)
	assert_true(ui.console.is_open(), "` opens the console")
	assert_eq(ctx.modals, [ui], "modal pushed")
	assert_eq(ctx.windows, [ui.console], "registered as the newest window")
	assert_eq(ui.console.input.text, "", "the backtick is not typed into the input")
	_key(KEY_ESCAPE)
	assert_false(ui.console.is_open(), "Esc closes it")
	assert_eq(ctx.modals.size(), 0, "modal popped")
	assert_eq(ctx.windows.size(), 0, "window closed")
	_key(KEY_QUOTELEFT)
	_key(KEY_QUOTELEFT)
	assert_false(ui.console.is_open(), "` toggles it closed again")
	assert_eq(ctx.modals.size(), 0, "balanced push/pop")


func test_f3_toggles_the_overlay() -> void:
	_key(KEY_F3)
	assert_true(ui.overlay.visible and h.dbg.overlay_enabled, "F3 shows the overlay")
	h.run("warp 000000040")
	ui.overlay.refresh()
	assert_true(ui.overlay.label.text.contains("MAP  000000040"), ui.overlay.label.text)
	_key(KEY_F3)
	assert_false(ui.overlay.visible, "F3 hides it")
	h.run("overlay on")
	assert_true(ui.overlay.visible, "the overlay command shows it too")


func test_console_runs_lines_through_debug_with_history_and_completion() -> void:
	ui.open_console()
	var out := ui.console.submit("help")
	assert_true(out.contains("warp <map> [portal]"), "help output returned")
	assert_true(ui.console.output.get_parsed_text().contains("> help"), "echoed")
	assert_true(ui.console.output.get_parsed_text().contains("warp <map> [portal]"), "printed")
	ui.console.submit("give 270 2")
	assert_eq(h.game.character.inventory.count("270"), 2, "the command ran")
	assert_eq(Array(h.dbg.history.slice(-2)), ["help", "give 270 2"], "history")
	ui.console.input.text = "draft"
	ui.console._history_step(-1)
	assert_eq(ui.console.input.text, "give 270 2", "Up: newest")
	ui.console._history_step(-1)
	assert_eq(ui.console.input.text, "help", "Up again: older")
	ui.console._history_step(1)
	ui.console._history_step(1)
	assert_eq(ui.console.input.text, "draft", "Down past the newest restores the draft")
	ui.console.input.text = "warp tomat"
	ui.console._complete()
	var tomato: String = (h.session.call("get_defs") as MapDefinitions).id_of_v8["1020001"]
	assert_eq(ui.console.input.text, "warp %s " % tomato, "Tab completes a map name to its id")
	ui.console.input.text = "spaw"
	ui.console._complete()
	assert_eq(ui.console.input.text, "spawn", "Tab: common prefix of spawn / spawns")
	assert_true(ui.console.output.get_parsed_text().contains("spawns"), "candidates listed")
	h.run("where")
	assert_true(ui.console.output.get_parsed_text().contains("(code) > where"), "commands run by code are mirrored")
	h.run("clear")
	assert_false(ui.console.output.get_parsed_text().contains("(code) > where"), "clear empties the output")
	assert_true(DebugConsole.looks_like_error("unknown command: x"), "errors are coloured")


## The player surface the console touches: its InputSource is swapped for an idle one while the console is open, so
## systems that read player.input_source (PortalInteractor) never see the history keys as Up/Down presses.
class FakePlayer:
	extends Node3D
	var input_source: InputSource = KeyboardInput.new()
	var input_enabled := true

	func set_input_source(s: InputSource) -> void:
		input_source = s

	func set_input_enabled(on: bool) -> void:
		input_enabled = on


func test_console_mutes_the_players_input_source_while_open() -> void:
	var p := FakePlayer.new()
	ctx.player = p
	var keyboard := p.input_source
	ui.open_console()
	assert_true(p.input_source is BotInput, "an idle BotInput while typing")
	assert_true(p.input_source != keyboard, "keyboard source parked")
	ui.close_console()
	assert_eq(p.input_source, keyboard, "keyboard source restored")
	p.free()


## What PlayerCombat._ensure_lock does every physics tick: whatever the player's source is, it becomes the inner of
## the AttackLockInput, and the lock goes back on the player.
static func _rewrap_like_player_combat(p: FakePlayer, lock: AttackLockInput) -> void:
	if p.input_source is AttackLockInput:
		return
	lock.inner = p.input_source
	p.set_input_source(lock)


## The real game: PlayerCombat wraps the keyboard in an AttackLockInput and re-wraps a swapped source on its next
## tick. Closing the console must hand the keyboard back through the decorator (it used to leave the lock wrapping the
## idle source, so the player could not move again until the game restarted).
func test_console_restores_the_keyboard_through_player_combats_attack_lock() -> void:
	var p := FakePlayer.new()
	ctx.player = p
	var keyboard := p.input_source
	var lock := AttackLockInput.new(keyboard)
	p.set_input_source(lock)
	ui.open_console()
	assert_eq(p.input_source, lock, "the decorator stays on the player")
	assert_true(lock.inner is BotInput, "the innermost (keyboard) source is parked behind the lock")
	_rewrap_like_player_combat(p, lock)
	ui.close_console()
	assert_eq(p.input_source, lock, "the lock is still the player's source")
	assert_eq(lock.inner, keyboard, "the keyboard is back inside the lock")
	p.free()


## The other order: the console swaps the player's whole source (a decorator-less player), PlayerCombat then wraps the
## idle source, and the console closes: the keyboard must come back inside the lock.
func test_console_restores_the_keyboard_when_a_decorator_wraps_the_idle_source() -> void:
	var p := FakePlayer.new()
	ctx.player = p
	var keyboard := p.input_source
	ui.open_console()
	assert_true(p.input_source is BotInput, "idle source while open")
	var lock := AttackLockInput.new()
	_rewrap_like_player_combat(p, lock)
	assert_true(lock.inner is BotInput, "the lock now wraps the idle source")
	ui.close_console()
	assert_eq(p.input_source, lock, "the lock stays")
	assert_eq(lock.inner, keyboard, "the keyboard replaced the idle source inside the lock")
	# Opening and closing again keeps working.
	ui.open_console()
	ui.close_console()
	assert_eq(lock.inner, keyboard, "a second console session restores it too")
	p.free()


## A UI node that, like DialogueWindow / ShopWindow, takes keys in _input (before GUI focus).
class KeyEater:
	extends Node
	var got: int = 0
	## Mark the key handled (a dialogue does), or only count it.
	var consume: bool = true

	func _input(event: InputEvent) -> void:
		if event is InputEventKey and (event as InputEventKey).pressed:
			got += 1
			if consume:
				get_viewport().set_input_as_handled()


## A window that gets its _input from a base script (a shared window class), not its own.
class InheritedEater:
	extends KeyEater
	var extra: int = 0


## The console is the newest modal and owns the keyboard: another UI's _input handler (an open NPC dialogue) must not
## take the keys typed into it (it used to eat Enter, digits and WASD, so "mesos 25" arrived as "meo" and Enter
## advanced the dialogue). The fence covers the context's ui_root and systems and is lifted on close.
func test_console_fences_other_ui_key_handlers_while_open() -> void:
	var ui_root := Node.new()
	ui_root.name = "FakeUIRoot"
	var systems := Node.new()
	systems.name = "FakeSystems"
	var tree_root := (Engine.get_main_loop() as SceneTree).current_scene
	tree_root.add_child(ui_root)
	tree_root.add_child(systems)
	var dialogue := KeyEater.new()
	ui_root.add_child(dialogue)
	var system_keys := KeyEater.new()
	system_keys.consume = false
	systems.add_child(system_keys)
	var plain := Node.new()  # no script: never touched
	ui_root.add_child(plain)
	var inherited := InheritedEater.new()
	inherited.consume = false
	ui_root.add_child(inherited)
	ctx.ui_root = ui_root
	ctx.systems = systems
	assert_true(dialogue.is_processing_input(), "the dialogue reads keys before the console opens")
	ui.open_console()
	assert_false(dialogue.is_processing_input(), "fenced under ui_root while the console is open")
	assert_false(system_keys.is_processing_input(), "fenced under systems too")
	assert_false(inherited.is_processing_input(), "fenced when _input comes from a base script")
	assert_false(plain.is_processing_input(), "a node without a script has no input processing to fence")
	assert_true(ui.is_processing_input(), "the console's own keys (`, F3, Esc) still work")
	_key(KEY_ENTER)
	_key(KEY_5)
	assert_eq(dialogue.got + system_keys.got, 0, "no key reached the fenced handlers")
	_key(KEY_ESCAPE)
	assert_false(ui.console.is_open(), "Esc still closes the console")
	assert_true(dialogue.is_processing_input() and system_keys.is_processing_input(), "handlers restored on close")
	assert_true(inherited.is_processing_input(), "the inherited handler too")
	_key(KEY_ENTER)
	assert_eq(dialogue.got, 1, "the dialogue takes its keys again")
	assert_eq(system_keys.got, 1, "and so do the systems")
	ui_root.free()
	systems.free()


## The debug UI leaving the tree with the console open (the session ends) hands everything back: modal and window
## popped, the keyboard source restored, fenced handlers on again.
func test_leaving_the_tree_with_the_console_open_hands_everything_back() -> void:
	var p := FakePlayer.new()
	ctx.player = p
	var keyboard := p.input_source
	var ui_root := Node.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(ui_root)
	var dialogue := KeyEater.new()
	ui_root.add_child(dialogue)
	ctx.ui_root = ui_root
	ui.open_console()
	assert_false(dialogue.is_processing_input(), "fenced while open")
	ui.get_parent().remove_child(ui)
	assert_eq(ctx.modals.size(), 0, "modal popped")
	assert_eq(ctx.windows.size(), 0, "window closed")
	assert_eq(p.input_source, keyboard, "keyboard restored")
	assert_true(dialogue.is_processing_input(), "fence lifted")
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(ui)  # after_each frees it
	ui_root.free()
	p.free()
