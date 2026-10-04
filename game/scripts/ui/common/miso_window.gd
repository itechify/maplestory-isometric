class_name MisoWindow
extends PanelContainer
## A non-modal MisoStory window: a rounded blue-grey panel with a gold title strip, a key hint and a close button.
## Draggable by its title strip, closable (button, its toggle key, or Esc through the shell's window stack), and
## clamped to the screen. It registers with the GameContext window stack when it opens and when it closes, so the
## "menu" action (Esc) closes the newest window first. It never takes the keyboard: the player can walk with it open.
##
## Subclasses build their content into `body` in _build() and redraw it in refresh(). The window's env (MisoUiEnv)
## is assigned by the owning root before the first open.

signal opened(window: MisoWindow)
signal closed(window: MisoWindow)

## Stable name ("inventory", "equipment", "stats", "quests").
var window_name: String = ""
## Input action that toggles the window ("toggle_inventory"); shown as a key hint.
var toggle_action: String = ""
var env: MisoUiEnv = null
## Content container for subclasses.
var body: VBoxContainer
var title_label: Label
var key_hint: Label
var close_button: Button
var _title_bar: PanelContainer
var _dragging := false
var _drag_offset := Vector2.ZERO
var _built := false
var _status: Label = null
var _focused_frame := -1


func _init(p_name: String = "", p_title: String = "", p_action: String = "", min_size: Vector2 = Vector2(300, 200)) -> void:
	window_name = p_name
	toggle_action = p_action
	name = (p_name.capitalize().replace(" ", "") + "Window") if p_name != "" else "MisoWindow"
	theme_type_variation = &"MisoWindow"
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_NONE
	custom_minimum_size = min_size
	visible = false
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	outer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(outer)
	_title_bar = PanelContainer.new()
	_title_bar.theme_type_variation = &"MisoTitleBar"
	_title_bar.mouse_filter = MOUSE_FILTER_STOP
	_title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_title_bar.gui_input.connect(_on_title_input)
	outer.add_child(_title_bar)
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	_title_bar.add_child(row)
	title_label = Label.new()
	title_label.text = p_title
	title_label.theme_type_variation = &"MisoTitle"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(title_label)
	key_hint = Label.new()
	key_hint.theme_type_variation = &"MisoDim"
	key_hint.mouse_filter = MOUSE_FILTER_IGNORE
	key_hint.text = ""
	row.add_child(key_hint)
	close_button = Button.new()
	close_button.text = "x"
	close_button.theme_type_variation = &"MisoCloseButton"
	close_button.custom_minimum_size = Vector2(22, 22)
	close_button.focus_mode = FOCUS_NONE
	close_button.tooltip_text = "Close"
	close_button.pressed.connect(close)
	row.add_child(close_button)
	var margin := MarginContainer.new()
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 4)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(margin)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.mouse_filter = MOUSE_FILTER_IGNORE
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(body)


## Builds the content once (subclasses override _build) and refreshes it.
func ensure_built() -> void:
	if _built:
		return
	_built = true
	if toggle_action != "":
		var k := MisoUiEnv.key_label(toggle_action)
		key_hint.text = "[%s]" % k if k != "" else ""
	_build()


## Opens the window (or brings it to the front when already open) and registers it as the newest window.
func open() -> void:
	ensure_built()
	var was_open := visible
	show()
	move_to_front()
	if not was_open:
		refresh()
		_clamp_to_screen.call_deferred()
	if env != null:
		env.window_opened(self)
	if not was_open:
		opened.emit(self)


## Closes the window and unregisters it. Safe to call when already closed (the shell's close_top_window calls it).
func close() -> void:
	if not visible:
		if env != null:
			env.window_closed(self)
		return
	hide()
	_dragging = false
	_on_closed()
	if env != null:
		env.window_closed(self)
	closed.emit(self)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func is_open() -> bool:
	return visible


## Redraws the content from the live state. Subclasses override.
func refresh() -> void:
	pass


## Subclass hook: build the content into `body`.
func _build() -> void:
	pass


## Subclass hook: the window just closed (drop selections, hide tooltips).
func _on_closed() -> void:
	pass


## Brings an open window to the front and makes it the newest one in the window stack (the first Esc closes).
## Called on any mouse press inside the window; once per frame at most.
func focus_window() -> void:
	if not visible or _focused_frame == Engine.get_process_frames():
		return
	_focused_frame = Engine.get_process_frames()
	move_to_front()
	if env != null:
		env.window_opened(self)


func _input(event: InputEvent) -> void:
	# A press anywhere on the window (its slots and buttons included: they stop the event before _gui_input would
	# see it) brings it to the front.
	var mb := event as InputEventMouseButton
	if not _is_click(mb) or not visible or not is_inside_tree():
		return
	if is_frontmost_at(mb.position):
		focus_window()


## True when a press at `point` (viewport coordinates) lands on this window: the hovered control (the frontmost one
## under the pointer, whatever UI root it belongs to) is this window or inside it. Without hover information (no
## pointer motion yet), this is the frontmost visible window among its siblings that contains the point. Either way a
## click on a region another window covers raises that other window, not this one.
func is_frontmost_at(point: Vector2) -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null:
		return hovered == self or is_ancestor_of(hovered)
	var parent := get_parent()
	if parent == null:
		return false
	for i in range(parent.get_child_count() - 1, -1, -1):
		var w := parent.get_child(i) as MisoWindow
		if w != null and w.visible and w.get_global_rect().has_point(point):
			return w == self
	return false


func _gui_input(event: InputEvent) -> void:
	if _is_click(event as InputEventMouseButton):
		focus_window()


## A left or right button press (the wheel also arrives as pressed buttons; scrolling never raises a window).
static func _is_click(mb: InputEventMouseButton) -> bool:
	return mb != null and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT)


## Title-strip dragging. Positions come from the event (in _gui_input, InputEventMouse.global_position is in the
## coordinates of the CanvasLayer the window lives in), not from a separate cursor query.
func _on_title_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_dragging = true
			_drag_offset = mb.global_position - global_position
			focus_window()
			# Clamped at a screen edge, the pointer can leave the window over the world with the left (attack) button
			# held. That never swings: this press is consumed, and PlayerCombat counts only unconsumed presses
			# (MouseAttackGate); an attack key held meanwhile (J) keeps repeating.
		else:
			_dragging = false
		_title_bar.accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _dragging:
		global_position = mm.global_position - _drag_offset
		_clamp_to_screen()
		_title_bar.accept_event()


## Keeps the whole title strip on screen (the window may hang off the bottom edge, never above or sideways).
func _clamp_to_screen() -> void:
	if not is_inside_tree():
		return
	var area := get_viewport_rect().size
	var sz := size if size != Vector2.ZERO else get_combined_minimum_size()
	var p := position
	p.x = clampf(p.x, 0.0, maxf(0.0, area.x - sz.x))
	p.y = clampf(p.y, 0.0, maxf(0.0, area.y - 40.0))
	position = p


## Adds a status line (a dark pill so short messages stay readable on the light frame) to the bottom of `body`.
## Returns its Label; set_status() writes to it.
func add_status_line(text: String = "") -> Label:
	var pill := PanelContainer.new()
	pill.theme_type_variation = &"MisoNotice"
	pill.mouse_filter = MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.theme_type_variation = &"MisoSmall"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(maxf(120.0, custom_minimum_size.x - 40.0), 0)
	l.text = text
	pill.add_child(l)
	body.add_child(pill)
	_status = l
	return l


## Shows a message in the status line (red when bad).
func set_status(text: String, bad: bool = false) -> void:
	if _status == null:
		return
	_status.text = text
	_status.theme_type_variation = &"MisoBad" if bad else &"MisoSmall"


## A Button styled for windows that never steals keyboard focus (Space must keep jumping, not re-press it).
static func make_button(text: String, variation: StringName = &"", min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = FOCUS_NONE
	if variation != &"":
		b.theme_type_variation = variation
	if min_width > 0.0:
		b.custom_minimum_size = Vector2(min_width, 0)
	return b
