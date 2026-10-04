class_name DebugOverlay
extends PanelContainer
## The F3 overlay (built in code): Debug.overlay_text() in the top-right corner, refreshed REFRESH_S. The text itself
## (FPS and frame time, map, session, position, player, monsters, camera, layers) comes from DebugReport, so tests
## read exactly what is shown.

const REFRESH_S := 0.25
const FONT_SIZE := 13
const MARGIN := 10.0

var label: Label = null
var dbg: DebugTools = null
var _t: float = 0.0


func _init() -> void:
	name = "Overlay"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -MARGIN
	offset_top = MARGIN
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.03, 0.05, 0.72)
	bg.border_color = Color(0.35, 0.75, 1.0, 0.6)
	bg.border_width_left = 2
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 6
	bg.content_margin_bottom = 6
	add_theme_stylebox_override("panel", bg)
	label = Label.new()
	label.add_theme_font_override("font", DebugConsole.mono_font())
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _ready() -> void:
	if dbg == null:
		dbg = get_node_or_null("/root/Debug") as DebugTools
	refresh()


func refresh() -> void:
	if dbg != null:
		label.text = dbg.overlay_text()


## Moves the overlay below the console while the console is open.
func set_top(y: float) -> void:
	offset_top = y + MARGIN


func _process(delta: float) -> void:
	if not visible:
		return
	# Real time: process delta is scaled by Engine.time_scale, and "timescale 0.01" must not freeze the overlay.
	_t += delta / maxf(Engine.time_scale, 0.0001)
	if _t >= REFRESH_S:
		_t = 0.0
		refresh()
