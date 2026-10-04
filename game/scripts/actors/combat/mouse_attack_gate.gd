class_name MouseAttackGate
extends RefCounted
## Keeps clicks that belong to the UI from swinging the weapon. The "attack" action is bound to keys (J, Ctrl) and to
## the left mouse button (Controls), and Godot's Input marks the action pressed for every press, including one a
## GUI control consumes. So the mouse's share of the action is taken from the viewport's event routing instead:
##
##   observe(event)        Observer._input (an internal child of PlayerCombat that processes even while the tree is
##                         paused): every attack mouse press (GUI or world) and every release
##   world_press(event)    PlayerCombat._unhandled_input: a press no GUI control consumed, outside a GUI drag
##   filter(...)           once per physics tick: the attack reading the keyboard player really meant
##
## When no attack mouse button took part recently, filter() returns the input source's reading unchanged, so keys,
## pads and Input.action_press behave exactly as before. When the mouse took part, the mouse counts only through world
## presses, and the keys count through their own bindings (polled: Input cannot say which binding pressed an action).
## A press and release that both fall between two physics ticks are still seen: a short click on a window never
## swings, and a short click on the world swings once.
##
## "Recently" is in physics frames. Input reports an action press on the first physics frame that starts after the
## event (Input.is_action_just_pressed): an event flushed between frames shows on the next frame, but one that arrives
## during physics frame N (agile input flushing, or events injected from a physics_frame callback) shows on frame N + 1,
## one tick after PlayerCombat already saw it. So a mouse event keeps the mouse involved through frame N + 1.

## Feeds every input event to a gate's observe() before the GUI sees it, and keeps doing so while the scene tree is
## paused (PROCESS_MODE_ALWAYS). The pause menu's Resume button is clicked while the player (and its PlayerCombat) is
## paused; Input still marks "attack" pressed, and a click shorter than a frame reads as an attack press on the first
## tick after the unpause unless the gate saw it. Never consumes an event.
class Observer extends Node:
	var gate: MouseAttackGate = null

	func _init(p_gate: MouseAttackGate = null) -> void:
		gate = p_gate
		name = "MouseAttackObserver"
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _input(event: InputEvent) -> void:
		if gate != null:
			gate.observe(event)


## The last physics frame whose input-source reading may still show an attack mouse press or release seen earlier.
var mouse_until_frame: int = -1
## A world press (no GUI control took it, no GUI drag running) not yet reported by filter().
var world_pressed: bool = false
## A world press whose button is still down (cleared by its release, or when a GUI drag runs).
var world_held: bool = false
## Test seam: the physics frame to use instead of Engine.get_physics_frames() (-1 = the engine's).
var frame_override: int = -1


## Every input event, before the GUI (Observer._input, paused or not). Never consumes it.
func observe(event: InputEvent, action: StringName = &"attack") -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not is_attack_button(mb, action):
		return
	_touch()
	if not mb.pressed:
		world_held = false


## An event no GUI control consumed (PlayerCombat._unhandled_input). gui_dragging: Viewport.gui_is_dragging(), and a
## press during a GUI drag never counts. Never consumes the event.
func world_press(event: InputEvent, gui_dragging: bool, action: StringName = &"attack") -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or not is_attack_button(mb, action):
		return
	_touch()
	if gui_dragging:
		return
	world_pressed = true
	world_held = true


## True while the mouse counts as part of the attack action's state (see the class doc).
func mouse_involved(action: StringName = &"attack") -> bool:
	return _frame() <= mouse_until_frame or world_held or attack_buttons_down(action)


## The attack reading for this physics tick, given the input source's own reading (src_pressed, src_held). Reports a
## world press once. Returns [pressed, held].
func filter(src_pressed: bool, src_held: bool, gui_dragging: bool, action: StringName = &"attack") -> Array[bool]:
	var pressed := src_pressed
	var held := src_held
	if mouse_involved(action):
		world_held = world_held and attack_buttons_down(action) and not gui_dragging
		var keys := attack_keys_down(action)
		pressed = world_pressed or (src_pressed and keys)
		held = world_held or (src_held and keys)
	world_pressed = false
	return [pressed, held]


## Forgets everything (the player changed hands, the node left the tree).
func clear() -> void:
	mouse_until_frame = -1
	world_pressed = false
	world_held = false


func _touch() -> void:
	mouse_until_frame = _frame() + 1


func _frame() -> int:
	return frame_override if frame_override >= 0 else Engine.get_physics_frames()


## True when `mb` is a mouse button bound to `action` (modifiers ignored: Ctrl is itself an attack key).
static func is_attack_button(mb: InputEventMouseButton, action: StringName = &"attack") -> bool:
	return InputMap.has_action(action) and mb.is_action(action)


## True while a mouse button bound to `action` is down.
static func attack_buttons_down(action: StringName = &"attack") -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton and Input.is_mouse_button_pressed((ev as InputEventMouseButton).button_index):
			return true
	return false


## True while a non-mouse binding of `action` (a key, a pad button or axis) is down.
static func attack_keys_down(action: StringName = &"attack") -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			if k.physical_keycode != KEY_NONE and Input.is_physical_key_pressed(k.physical_keycode):
				return true
			if k.keycode != KEY_NONE and Input.is_key_pressed(k.keycode):
				return true
			if k.key_label != KEY_NONE and Input.is_key_label_pressed(k.key_label):
				return true
		elif ev is InputEventJoypadButton:
			var jb := ev as InputEventJoypadButton
			for dev in _devices(jb.device):
				if Input.is_joy_button_pressed(dev, jb.button_index):
					return true
		elif ev is InputEventJoypadMotion:
			var jm := ev as InputEventJoypadMotion
			var dz := InputMap.action_get_deadzone(action)
			for dev in _devices(jm.device):
				if Input.get_joy_axis(dev, jm.axis) * signf(jm.axis_value) > dz:
					return true
	return false


static func _devices(device: int) -> Array[int]:
	if device >= 0:
		return [device]
	var out: Array[int] = []
	for d in Input.get_connected_joypads():
		out.append(int(d))
	return out
