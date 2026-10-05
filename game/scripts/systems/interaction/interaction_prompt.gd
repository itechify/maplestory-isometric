class_name InteractionPrompt
extends PanelContainer
## The one context prompt ("[F] Talk to Roger"): a dark pill with a key cap, the verb and an optional detail line
## (a portal's destination). InteractionSystem fills it from InteractionResolver and moves it over the target in
## screen space. Pure presentation: it never reads input.

var key_cap: PanelContainer = null
var key_label: Label = null
var verb_label: Label = null
var detail_label: Label = null
## The resolver result shown now ({} when hidden).
var current: Dictionary = {}


func _init() -> void:
	name = "InteractionPrompt"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", NpcUiStyle.box(Color(0.07, 0.09, 0.13, 0.86), Color(1, 1, 1, 0.22), 1, 14, 8, 4))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	key_cap = PanelContainer.new()
	key_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := NpcUiStyle.box(Color("#f4f1e8"), Color("#9a9384"), 1, 4, 6, 1)
	cap.border_width_bottom = 3
	key_cap.add_theme_stylebox_override("panel", cap)
	key_label = NpcUiStyle.label("", Color("#23324a"), 15, true)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_cap.add_child(key_label)
	row.add_child(key_cap)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", -2)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	verb_label = NpcUiStyle.label("", Color.WHITE, 16, true)
	verb_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	verb_label.add_theme_constant_override("outline_size", 3)
	texts.add_child(verb_label)
	detail_label = NpcUiStyle.label("", Color("#ffe39a"), 13)
	texts.add_child(detail_label)
	visible = false


## Shows a resolver result ({} hides the prompt).
func show_prompt(p: Dictionary) -> void:
	current = p
	if p.is_empty():
		visible = false
		return
	key_label.text = String(p.get("key", "?"))
	verb_label.text = String(p.get("verb", ""))
	var detail := String(p.get("detail", ""))
	detail_label.text = detail
	detail_label.visible = not detail.is_empty()
	visible = true
	reset_size()


## The full prompt text ("[F] Talk to Roger"), "" when hidden.
func text() -> String:
	return String(current.get("text", "")) if visible else ""


## Places the prompt centred above a screen point (clamped to the viewport).
func place_above(screen_pos: Vector2, viewport_size: Vector2) -> void:
	var sz := get_combined_minimum_size()
	size = sz
	var p := screen_pos - Vector2(sz.x * 0.5, sz.y + 6.0)
	p.x = clampf(p.x, 4.0, maxf(4.0, viewport_size.x - sz.x - 4.0))
	p.y = clampf(p.y, 4.0, maxf(4.0, viewport_size.y - sz.y - 4.0))
	position = p.round()
