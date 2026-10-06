class_name NpcSpeechBubble
extends Control
## The speech bubble above an NPC: one canonical idle-chatter line (NpcDef.idle_line) on a light rounded balloon with a
## tail pointing down at the NPC, MapleStory-style. A screen-space Control in the interaction overlay, placed and timed
## by NpcPresenter (NpcBubbleSchedule). Drawn in code (no art); the wrap width and colours are cosmetic constants.

const MAX_TEXT_WIDTH := 230.0
const PAD := Vector2(10, 6)
const TAIL_H := 9.0
const TAIL_W := 14.0
const FONT_SIZE := 14
const FILL := Color("#fffdf3")
const EDGE := Color("#5b4a2e")
const INK := Color("#2a2418")

## The line shown ("" = none) and its provenance ("canonical/npcs/<id>.json#idle_chatter[i]").
var text: String = ""
var source: String = ""
var line_index: int = -1
var label: Label = null
var _style: StyleBoxFlat = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_style = NpcUiStyle.box(FILL, EDGE, 2, 9, 0, 0)
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", INK)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	var font := NpcUiStyle.regular_font()
	if font != null:
		label.add_theme_font_override("font", font)
	add_child(label)


## Shows a resolved line ({"text", "source"}, NpcDef.idle_line) as the bubble's text and sizes the balloon to it.
func set_line(line: Dictionary, index: int = -1) -> void:
	text = String(line.get("text", ""))
	source = String(line.get("source", ""))
	line_index = index
	label.text = text
	var font := label.get_theme_font("font")
	var w := MAX_TEXT_WIDTH
	var h := 18.0
	if font != null:
		w = minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 2.0, MAX_TEXT_WIDTH)
		h = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, w, FONT_SIZE).y
	label.custom_minimum_size = Vector2(w, h)
	label.position = PAD
	label.size = Vector2(w, h)
	custom_minimum_size = Vector2(w, h) + PAD * 2.0 + Vector2(0, TAIL_H)
	size = custom_minimum_size
	queue_redraw()


## Puts the tail's tip on a screen point (above the NPC's head or its quest marker).
func place_above(screen_pos: Vector2) -> void:
	position = (screen_pos - Vector2(size.x * 0.5, size.y)).round()


func _draw() -> void:
	if text == "":
		return
	var body := Rect2(Vector2.ZERO, size - Vector2(0, TAIL_H))
	draw_style_box(_style, body)
	var cx := size.x * 0.5
	var top := body.end.y - 2.0
	var tail := PackedVector2Array([Vector2(cx - TAIL_W * 0.5, top), Vector2(cx + TAIL_W * 0.5, top),
		Vector2(cx, size.y)])
	draw_colored_polygon(tail, FILL)
	draw_line(Vector2(cx - TAIL_W * 0.5, top), Vector2(cx, size.y), EDGE, 2.0)
	draw_line(Vector2(cx + TAIL_W * 0.5, top), Vector2(cx, size.y), EDGE, 2.0)
