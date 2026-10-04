extends TestCase
## PlayerCombat and the mouse: the left button is an attack binding (Controls), but a click that belongs to the UI
## never swings. Events go through Input.parse_input_event, exactly the game's path: Input marks the "attack" action
## pressed for every press, and the viewport routes the same event to the GUI first, then to _unhandled_input (which
## a press a Button consumed never reaches). Positions are viewport points mapped to window coordinates through the
## root's final transform (headless scales the window), and every case checks that the Button really got its press.
##
## The whole suite runs inside one process frame, where Input.is_action_just_pressed stays true for the rest of the
## run once "attack" was pressed. So every case counts attacks relative to its own start, and the negative cases are
## ones where the mouse took part (the input source's stale "just pressed" alone would swing).

const BUTTON_POS := Vector2(200, 200)
const BUTTON_SIZE := Vector2(240, 80)

var rig: MonsterTestRig
var layer: CanvasLayer
var button: Button
var downs: int = 0


func before_each() -> void:
	_release_all()
	rig = MonsterTestRig.create(db(), 7)
	rig.floor(40.0)
	rig.set_weapon("541")
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	p.set_input_source(KeyboardInput.new())
	rig.tick()  # PlayerCombat wraps the keyboard in its AttackLockInput
	layer = CanvasLayer.new()
	layer.name = "MouseTestUI"
	rig.w.host.add_child(layer)
	button = Button.new()
	button.text = "Item [I]"
	button.position = BUTTON_POS
	button.size = BUTTON_SIZE
	button.button_down.connect(func() -> void: downs += 1)
	layer.add_child(button)
	downs = 0
	_ready_to_attack()


func after_each() -> void:
	(Engine.get_main_loop() as SceneTree).paused = false
	var vp := _vp()
	if vp.gui_is_dragging():
		vp.gui_cancel_drag()
	_release_all()
	rig.free_all()


func _pc() -> PlayerCombat:
	return rig.system.player_combat


func _vp() -> Viewport:
	return (Engine.get_main_loop() as SceneTree).root


func _on_button() -> Vector2:
	return BUTTON_POS + BUTTON_SIZE * 0.5


## A point of the viewport no control covers.
func _on_world() -> Vector2:
	return _vp().get_visible_rect().size * Vector2(0.75, 0.7)


func _mouse(at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ev.position = _vp().get_final_transform() * at
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _motion(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _vp().get_final_transform() * at
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _release_all() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_mouse(_on_world(), false)
	for k: Key in [KEY_J, KEY_CTRL]:
		if Input.is_physical_key_pressed(k):
			_key(k, false)
	if InputMap.has_action(&"attack"):
		Input.action_release(&"attack")


## No lockout running and nothing buffered: the next tick attacks only if the input says so.
func _ready_to_attack() -> void:
	_pc().lockout_left = 0.0
	rig.system.player_combat.set("_buffered", 0.0)


func test_a_click_on_a_button_over_the_world_does_not_swing() -> void:
	var pc := _pc()
	var before := pc.attacks
	_mouse(_on_button(), true)
	assert_eq(downs, 1, "the Button got the press (the coordinates reach it)")
	assert_true(Input.is_action_pressed(&"attack"), "Input marks the attack action pressed, as in the game")
	rig.tick()
	assert_eq(pc.attacks, before, "a press on a button never swings")
	rig.run(5)
	assert_eq(pc.attacks, before, "nor does holding it there")
	_mouse(_on_button(), false)
	rig.tick()
	assert_eq(pc.attacks, before, "nor its release")


func test_a_click_shorter_than_a_tick_on_a_button_does_not_swing() -> void:
	# UI.md "Known gaps": press and release both fell between two physics ticks, so polling saw "just pressed" with
	# the button already up and swung once.
	var pc := _pc()
	var before := pc.attacks
	_mouse(_on_button(), true)
	_mouse(_on_button(), false)
	assert_eq(downs, 1, "the Button got the press")
	rig.tick()
	assert_eq(pc.attacks, before, "a quick click on a window never swings")


func test_a_quick_click_on_a_resume_button_while_paused_does_not_swing() -> void:
	# The pause menu's Resume (seen in the real game): the click lands while the tree is paused, so PlayerCombat itself
	# gets no input callbacks, yet Input marks "attack" pressed; the button's release unpauses. A click shorter than a
	# frame then reads as an attack press on the first tick after the unpause.
	var pc := _pc()
	var tree := Engine.get_main_loop() as SceneTree
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	button.pressed.connect(func() -> void: tree.paused = false)
	tree.paused = true
	var before := pc.attacks
	_mouse(_on_button(), true)
	_mouse(_on_button(), false)
	assert_eq(downs, 1, "the Button got the press while the tree was paused")
	assert_false(tree.paused, "its release resumed the game")
	rig.tick()
	assert_eq(pc.attacks, before, "the click that resumed the game never swings")
	rig.run(3)
	assert_eq(pc.attacks, before, "nor later")


func test_a_click_on_the_world_swings_once_and_holding_repeats() -> void:
	var pc := _pc()
	var before := pc.attacks
	_mouse(_on_world(), true)
	assert_eq(downs, 0, "the press missed the Button")
	rig.tick()
	assert_eq(pc.attacks, before + 1, "a click on the world attacks")
	rig.run(int(ceil(pc.last_lockout_s / MonsterTestRig.TICK)) + 2)
	assert_eq(pc.attacks, before + 2, "holding the button in the world repeats at the lockout rate")
	_mouse(_on_world(), false)
	_ready_to_attack()
	before = pc.attacks
	_mouse(_on_world(), true)
	_mouse(_on_world(), false)
	rig.tick()
	assert_eq(pc.attacks, before + 1, "a click shorter than a tick on the world still swings once")


func test_j_attacks_with_the_pointer_over_a_button_and_while_a_button_is_held() -> void:
	var pc := _pc()
	_motion(_on_button())
	assert_eq(_vp().gui_get_hovered_control(), button, "the pointer is over the Button")
	var before := pc.attacks
	_key(KEY_J, true)
	rig.tick()
	assert_eq(pc.attacks, before + 1, "J attacks whatever the pointer hovers")
	_key(KEY_J, false)
	# The left button held on a control (a window being dragged by its title) while J is pressed: the keys still count.
	_ready_to_attack()
	before = pc.attacks
	_mouse(_on_button(), true)
	rig.tick()
	assert_eq(pc.attacks, before, "the held UI press alone does not swing")
	_key(KEY_J, true)
	rig.tick()
	assert_eq(pc.attacks, before + 1, "J held next to a UI press attacks")
	rig.run(int(ceil(pc.last_lockout_s / MonsterTestRig.TICK)) + 2)
	assert_eq(pc.attacks, before + 2, "and repeats while J is held")
	_key(KEY_J, false)
	_mouse(_on_button(), false)


func test_ctrl_attacks_and_a_later_click_on_a_button_does_not() -> void:
	var pc := _pc()
	var before := pc.attacks
	_key(KEY_CTRL, true)
	rig.tick()
	assert_eq(pc.attacks, before + 1, "Ctrl attacks")
	_key(KEY_CTRL, false)
	_ready_to_attack()
	before = pc.attacks
	_mouse(_on_button(), true)
	_mouse(_on_button(), false)
	rig.tick()
	assert_eq(pc.attacks, before, "the click on the Button does not")


func test_no_mouse_attack_during_a_gui_drag() -> void:
	var pc := _pc()
	var preview := Control.new()
	button.force_drag({"item": "test"}, preview)
	assert_true(_vp().gui_is_dragging(), "a GUI drag runs")
	var before := pc.attacks
	_mouse(_on_world(), true)
	rig.tick()
	assert_eq(pc.attacks, before, "a press while dragging never swings")
	_vp().gui_cancel_drag()
	_mouse(_on_world(), false)


func test_the_mouse_is_ignored_when_a_bot_drives_the_player() -> void:
	var pc := _pc()
	var bot := BotInput.new()
	(rig.w.player as PlayerController).set_input_source(bot)
	rig.tick()
	_ready_to_attack()
	var before := pc.attacks
	_mouse(_on_world(), true)
	_mouse(_on_world(), false)
	rig.tick()
	assert_eq(pc.attacks, before, "a world click does not attack for a bot-driven player")
	bot.press(&"attack")
	rig.tick()
	assert_eq(pc.attacks, before + 1, "the bot's own attack works")


# --- MouseAttackGate in isolation (explicit physics frames) -----------------------------------------------------------

func _press_event(pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	return ev


func _gate(frame: int) -> MouseAttackGate:
	var g := MouseAttackGate.new()
	g.frame_override = frame
	return g


func test_gate_passes_the_source_reading_through_when_the_mouse_took_no_part() -> void:
	var g := _gate(100)
	assert_eq(g.filter(true, true, false), [true, true] as Array[bool], "keys and API presses unchanged")
	assert_eq(g.filter(false, false, false), [false, false] as Array[bool], "nothing")


func test_gate_counts_only_world_presses_outside_a_drag() -> void:
	var g := _gate(100)
	g.observe(_press_event(true))
	assert_eq(g.filter(true, true, false)[0], false, "a press the GUI consumed (seen, never unhandled) does not count")
	g.frame_override = 110
	g.observe(_press_event(true))
	g.world_press(_press_event(true), false)
	assert_eq(g.filter(true, false, false)[0], true, "a world press counts")
	assert_eq(g.filter(false, false, false), [false, false] as Array[bool], "once")
	g.frame_override = 120
	g.observe(_press_event(true))
	g.world_press(_press_event(true), true)
	assert_eq(g.filter(true, true, true)[0], false, "a press during a GUI drag does not count")
	g.world_press(_press_event(true), false)
	assert_true(g.world_held, "a world press holds")
	g.observe(_press_event(false))
	assert_false(g.world_held, "its release ends the hold")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	g.clear()
	g.world_press(right, false)
	assert_false(g.world_pressed, "only the buttons bound to attack count")


func test_gate_covers_the_frame_input_reports_a_press_on() -> void:
	# A click that arrives during physics frame N is reported by Input.is_action_just_pressed on frame N + 1 (seen in
	# the real game: events injected from a physics_frame callback, or agile input flushing). The source's stale
	# "just pressed" on N + 1 must still be blocked; from N + 2 the source is trusted again.
	var g := _gate(200)
	g.observe(_press_event(true))
	g.observe(_press_event(false))
	assert_eq(g.filter(false, false, false), [false, false] as Array[bool], "frame N: Input does not show it yet")
	g.frame_override = 201
	assert_true(g.mouse_involved(), "frame N + 1: the mouse is still involved")
	assert_eq(g.filter(true, false, false), [false, false] as Array[bool], "frame N + 1: the UI click never swings")
	g.frame_override = 202
	assert_false(g.mouse_involved(), "frame N + 2: no longer")
	assert_eq(g.filter(true, false, false), [true, false] as Array[bool], "a later key press passes through")
