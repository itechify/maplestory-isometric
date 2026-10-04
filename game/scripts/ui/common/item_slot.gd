class_name MisoItemSlot
extends PanelContainer
## One item square (inventory grid, equipment doll, quickslot bar): a procedural icon, a stack count, an optional
## caption for an empty slot ("Hat") and an optional key label ("1"). It reports clicks, double-clicks, right-clicks
## and hover, and supports Godot drag and drop through injectable callbacks, so the owner decides what a drag means.

signal activated(slot: MisoItemSlot)
signal selected(slot: MisoItemSlot)
signal context_requested(slot: MisoItemSlot)
signal hover_changed(slot: MisoItemSlot, inside: bool)

## Owner-defined address of the slot (inventory tab + index, equipment slot name, quickslot key).
var tab: String = ""
var index: int = -1
var slot_name: String = ""

var item_id: String = ""
var qty: int = 0
var data: Dictionary = {}
var is_selected: bool = false
## (slot) -> Variant: drag data for this slot, or null to refuse the drag.
var drag_source: Callable = Callable()
## (slot, data) -> bool: whether a drag may drop here.
var drop_filter: Callable = Callable()
## (slot, data) -> void: performs a drop.
var drop_handler: Callable = Callable()

var icon: MisoItemIcon
var count_label: Label
var key_label: Label
var caption_label: Label
var _hover := false


func _init(slot_size: float = 44.0) -> void:
	theme_type_variation = &"MisoSlot"
	custom_minimum_size = Vector2(slot_size, slot_size)
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_NONE
	var layer := Control.new()
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(layer)
	caption_label = MisoTheme.make_label("", 11, Color(0.62, 0.70, 0.82, 0.85), 0)
	caption_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_label.mouse_filter = MOUSE_FILTER_IGNORE
	layer.add_child(caption_label)
	icon = MisoItemIcon.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 2
	icon.offset_top = 2
	icon.offset_right = -2
	icon.offset_bottom = -2
	layer.add_child(icon)
	count_label = MisoTheme.make_label("", 12, MisoTheme.TEXT, 4, MisoTheme.WEIGHT_BLACK)
	count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	count_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	count_label.offset_right = 1
	count_label.offset_bottom = 3
	count_label.mouse_filter = MOUSE_FILTER_IGNORE
	layer.add_child(count_label)
	key_label = MisoTheme.make_label("", 11, MisoTheme.GOLD, 3, MisoTheme.WEIGHT_BLACK)
	key_label.position = Vector2(-1, -4)
	key_label.mouse_filter = MOUSE_FILTER_IGNORE
	layer.add_child(key_label)
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)


## Shows a stack. qty <= 1 shows no count unless always_count (quickslots show 0 and 1 too).
func set_stack(p_item_id: String, p_qty: int, db: ContentDB, p_data: Dictionary = {}, always_count: bool = false) -> void:
	item_id = p_item_id
	qty = p_qty
	data = p_data
	icon.set_item(item_id, db)
	icon.dim = item_id != "" and qty <= 0
	count_label.text = str(qty) if item_id != "" and (qty > 1 or always_count) else ""
	caption_label.visible = item_id == ""
	_restyle()


func clear() -> void:
	item_id = ""
	qty = 0
	data = {}
	icon.set_item("", null)
	count_label.text = ""
	caption_label.visible = true
	_restyle()


func set_caption(text: String) -> void:
	caption_label.text = text


func set_key_text(text: String) -> void:
	key_label.text = text


func set_selected(on: bool) -> void:
	is_selected = on
	_restyle()


func is_empty() -> bool:
	return item_id == ""


func _restyle() -> void:
	if is_selected:
		add_theme_stylebox_override("panel", MisoTheme.panel_style("slot_selected"))
	elif _hover:
		add_theme_stylebox_override("panel", MisoTheme.panel_style("slot_hover"))
	else:
		remove_theme_stylebox_override("panel")


func _on_enter() -> void:
	_hover = true
	_restyle()
	hover_changed.emit(self, true)


func _on_exit() -> void:
	_hover = false
	_restyle()
	hover_changed.emit(self, false)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.double_click:
			activated.emit(self)
		else:
			selected.emit(self)
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		context_requested.emit(self)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not drag_source.is_valid() or item_id == "":
		return null
	var d: Variant = drag_source.call(self)
	if d == null:
		return null
	# The drag crosses the world on its way to a quickslot or another window with the left (attack) button held.
	MisoUiEnv.release_attack_action()
	var preview := MisoItemIcon.new()
	preview.size = Vector2(40, 40)
	preview.item_id = item_id
	preview.shape = icon.shape
	preview.color = icon.color
	preview.modulate = Color(1, 1, 1, 0.85)
	var holder := Control.new()
	holder.add_child(preview)
	preview.position = Vector2(-20, -20)
	set_drag_preview(holder)
	return d


func _can_drop_data(_at_position: Vector2, d: Variant) -> bool:
	return drop_filter.is_valid() and bool(drop_filter.call(self, d))


func _drop_data(_at_position: Vector2, d: Variant) -> void:
	if drop_handler.is_valid():
		drop_handler.call(self, d)
