class_name PlaytestInput
extends RefCounted
## Real input for the playtest harness (docs/runtime/PLAYTEST_HARNESS.md "Input"): every press is an InputEvent sent
## through Input.parse_input_event and flushed at once, so the game reads it exactly like the keyboard and mouse:
## Input's action state (KeyboardInput, PlayerCombat, LootSystem, PortalInteractor, InteractionSystem all read the
## player's KeyboardInput), and the viewport's _input / _gui_input / _unhandled_input (dialogue and shop keys, GUI
## buttons, Esc through the shell). The player's input source is never swapped.
##
##   keys     InputEventKey with keycode and physical_keycode (and unicode when typing)
##   actions  an action is pressed through its first keyboard binding in the InputMap (Controls.BINDINGS)
##   analog   movement while walking a path: InputEventAction move_* with a strength (DEVICE), so the walker can
##            steer in any direction; KeyboardInput reads Input.get_action_strength, so this is the same code path
##   mouse    InputEventMouseMotion / InputEventMouseButton at a canvas point, mapped through the viewport's final
##            transform (the project stretches canvas_items from 1600x900)
##
## Timing: send from a process-frame context (after `await get_tree().process_frame`). An action press is reported to
## the physics tick that starts after the event, so a tap is "down, one physics tick, up". Every send uses a fresh
## event object (Godot drops an event object re-sent in the same frame).
##
## Focus: a window that loses OS focus makes Godot release every pressed key and action. reassert() (called by the
## driver every frame) sends the held keys and strengths again and counts it in `reasserts`.

## Device id of the walker's analog movement events, so they never share Input's per-device state with key presses.
const DEVICE := 7
const MOVE_ACTIONS: Array[StringName] = [&"move_right", &"move_left", &"move_up", &"move_down"]

var host: Node = null
## keycode (int) -> true while held down by the harness.
var held_keys: Dictionary = {}
## action (StringName) -> strength while held through InputEventAction.
var held_actions: Dictionary = {}
var reasserts: int = 0
var events_sent: int = 0
var _last_mouse: Vector2 = Vector2.ZERO
var _mouse_buttons: int = 0


func _init(p_host: Node) -> void:
	host = p_host


func tree() -> SceneTree:
	return host.get_tree()


func viewport() -> Viewport:
	return host.get_viewport()


# --- keys ---------------------------------------------------------------------------------------------------------

## Sends one key event now.
func key_event(code: Key, pressed: bool, unicode: int = 0, shift: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.unicode = unicode
	ev.pressed = pressed
	ev.shift_pressed = shift
	_send(ev)
	if pressed:
		held_keys[int(code)] = true
	else:
		held_keys.erase(int(code))


func key_down(code: Key) -> void:
	key_event(code, true)


func key_up(code: Key) -> void:
	key_event(code, false)


## Down, one physics tick, up (then one more tick so the release is seen). Await it.
func tap_key(code: Key, shift: bool = false) -> void:
	key_event(code, true, 0, shift)
	await tree().physics_frame
	await tree().process_frame
	key_event(code, false, 0, shift)
	await tree().physics_frame
	await tree().process_frame


## Holds a key for `seconds` of game time (at least one physics tick). Await it.
func hold_key(code: Key, seconds: float) -> void:
	key_event(code, true)
	var ticks := maxi(1, roundi(seconds * Engine.physics_ticks_per_second))
	var end := Engine.get_physics_frames() + ticks
	while Engine.get_physics_frames() < end:
		await tree().process_frame
		reassert()
	key_event(code, false)
	await tree().physics_frame
	await tree().process_frame


## Types `text` into whatever has the keyboard focus (one press and release per character, with its unicode).
func type_text(text: String) -> void:
	for i in text.length():
		var ch := text.substr(i, 1)
		var code := OS.find_keycode_from_string(ch.to_upper())
		var upper := ch != ch.to_lower()
		key_event(code, true, ch.unicode_at(0), upper)
		key_event(code, false, 0, upper)
		await tree().process_frame


# --- actions ------------------------------------------------------------------------------------------------------

## The first keyboard key bound to `action` in the InputMap (KEY_NONE when it has none).
static func key_for_action(action: StringName) -> Key:
	if not InputMap.has_action(action):
		return KEY_NONE
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	return KEY_NONE


## Taps an action through its keyboard binding (an InputEventAction when it has none). Await it.
func tap_action(action: StringName) -> void:
	var k := key_for_action(action)
	if k != KEY_NONE:
		await tap_key(k)
		return
	set_action_strength(action, 1.0)
	await tree().physics_frame
	await tree().process_frame
	set_action_strength(action, 0.0)
	await tree().physics_frame
	await tree().process_frame


## Holds an action for `seconds` of game time through its keyboard binding. Await it.
func hold_action(action: StringName, seconds: float) -> void:
	var k := key_for_action(action)
	if k != KEY_NONE:
		await hold_key(k, seconds)
		return
	set_action_strength(action, 1.0)
	var end := Engine.get_physics_frames() + maxi(1, roundi(seconds * Engine.physics_ticks_per_second))
	while Engine.get_physics_frames() < end:
		await tree().process_frame
		reassert()
	set_action_strength(action, 0.0)
	await tree().physics_frame
	await tree().process_frame


## Presses (strength > 0) or releases (0) an action with an InputEventAction on DEVICE. Repeating the same strength
## sends nothing.
func set_action_strength(action: StringName, strength: float) -> void:
	strength = clampf(strength, 0.0, 1.0)
	var was := float(held_actions.get(action, 0.0))
	if is_equal_approx(was, strength):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = strength > 0.0
	ev.strength = strength
	ev.device = DEVICE
	_send(ev)
	if strength > 0.0:
		held_actions[action] = strength
	else:
		held_actions.erase(action)


## Walks in world direction `dir` (length <= 1) for a camera whose ground axes are `right` and `forward` (the
## player's view_right / view_forward): the move_* strengths KeyboardInput turns back into exactly `dir`.
func set_move_world(dir: Vector3, right: Vector3, forward: Vector3) -> void:
	var mv := screen_move_for(dir, right, forward)
	set_action_strength(&"move_right", maxf(mv.x, 0.0))
	set_action_strength(&"move_left", maxf(-mv.x, 0.0))
	set_action_strength(&"move_up", maxf(mv.y, 0.0))
	set_action_strength(&"move_down", maxf(-mv.y, 0.0))


## Screen-relative intent (x right, y up the screen) that KeyboardInput.world_move maps onto `dir`: solves
## right * x + forward * y = dir on the ground plane.
static func screen_move_for(dir: Vector3, right: Vector3, forward: Vector3) -> Vector2:
	var d := Vector2(dir.x, dir.z)
	if d.length_squared() < 1e-8:
		return Vector2.ZERO
	var a := right.x
	var b := right.z
	var c := forward.x
	var e := forward.z
	var det := a * e - c * b
	var mv: Vector2
	if absf(det) < 1e-4:
		mv = Vector2(d.dot(Vector2(a, b)), d.dot(Vector2(c, e)))
	else:
		mv = Vector2((d.x * e - c * d.y) / det, (a * d.y - b * d.x) / det)
	return mv.limit_length(1.0)


func release_movement() -> void:
	for a in MOVE_ACTIONS:
		set_action_strength(a, 0.0)


# --- mouse --------------------------------------------------------------------------------------------------------

## A canvas point (Control.get_global_rect() space) in the window's pixels.
func to_window(at: Vector2) -> Vector2:
	return viewport().get_final_transform() * at


func mouse_move(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = to_window(at)
	ev.global_position = ev.position
	ev.relative = ev.position - _last_mouse
	ev.button_mask = _mouse_buttons
	_last_mouse = ev.position
	_send(ev)


func mouse_button(at: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var mask := 1 << (int(button) - 1)
	_mouse_buttons = (_mouse_buttons | mask) if pressed else (_mouse_buttons & ~mask)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.button_mask = _mouse_buttons
	ev.position = to_window(at)
	ev.global_position = ev.position
	_send(ev)


## Moves to `at`, presses and releases the button one frame apart. Returns the control the pointer hovered when it
## pressed (null over the world). Await it.
func click_at(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> Control:
	var hovered := await hover(at)
	await press_release(at, button)
	return hovered


## Moves the pointer to `at` and returns the control the GUI now finds under it (the frontmost one that takes the
## mouse, across every canvas layer; null over the world). Await it.
func hover(at: Vector2) -> Control:
	mouse_move(at)
	await tree().process_frame
	return viewport().gui_get_hovered_control()


## One notch of the mouse wheel at `at` (down: toward the end of a list), as a wheel sends it: a press and a release
## of the wheel button. Await it.
func wheel(at: Vector2, down: bool) -> void:
	mouse_move(at)
	var b := MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = b
		ev.pressed = pressed
		ev.factor = 1.0
		ev.button_mask = _mouse_buttons
		ev.position = to_window(at)
		ev.global_position = ev.position
		_send(ev)
	await tree().process_frame


## Presses and releases the button at `at`, one frame apart (the pointer is already there: hover()). Await it.
func press_release(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	mouse_button(at, true, button)
	await tree().process_frame
	mouse_button(at, false, button)
	await tree().process_frame


# --- state --------------------------------------------------------------------------------------------------------

## Re-sends what the harness holds when Input no longer reports it (focus loss). Returns how many were re-sent.
func reassert() -> int:
	var n := 0
	for code: int in held_keys.keys():
		var k := code as Key
		if not Input.is_physical_key_pressed(k) and not Input.is_key_pressed(k):
			var ev := InputEventKey.new()
			ev.keycode = k
			ev.physical_keycode = k
			ev.pressed = true
			_send(ev)
			n += 1
	for a: StringName in held_actions.keys():
		if InputMap.has_action(a) and Input.get_action_strength(a) + 0.001 < float(held_actions[a]):
			var ev := InputEventAction.new()
			ev.action = a
			ev.pressed = true
			ev.strength = float(held_actions[a])
			ev.device = DEVICE
			_send(ev)
			n += 1
	reasserts += n
	return n


## Releases every key, action and mouse button the harness holds.
func release_all() -> void:
	for code: int in held_keys.keys():
		key_event(code as Key, false)
	for a: StringName in held_actions.keys():
		set_action_strength(a, 0.0)
	if _mouse_buttons != 0:
		for b in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if _mouse_buttons & (1 << (int(b) - 1)):
				mouse_button(viewport().get_final_transform().affine_inverse() * _last_mouse, false, b)


func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	events_sent += 1
