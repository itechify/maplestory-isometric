class_name TitleScreen
extends Control
## Boot screen: New Game, Continue (only when a loadable save exists; it continues the most recently saved slot),
## Load (the slot list) and Quit, over the procedural TitleBackdrop. The screen only reads save entries it is given
## (set_saves); the shell decides what each button does.

signal new_game_pressed
signal continue_pressed(slot: String)
signal load_pressed(slot: String)
signal restore_pressed(slot: String)
signal quit_pressed

var backdrop: TitleBackdrop = null
var menu: VBoxContainer = null
var new_button: Button = null
var continue_button: Button = null
var load_button: Button = null
var quit_button: Button = null
var continue_info: Label = null
var message: Label = null
var slots: SlotList = null
## The slot Continue loads ("" when there is none).
var continue_slot: String = ""

var _menu_panel: Control = null


func _init() -> void:
	name = "TitleScreen"
	ScreenKit.full_rect(self)
	ScreenKit.apply(self)
	backdrop = TitleBackdrop.new()
	ScreenKit.full_rect(backdrop)
	add_child(backdrop)

	var logo := ScreenKit.vbox(0)
	logo.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	logo.offset_top = 56
	logo.offset_bottom = 230
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := ScreenKit.outlined("MisoStory", 96, Color(1.0, 0.86, 0.40), 14)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_child(t)
	var sub := ScreenKit.outlined("Maple Island", 30, ScreenKit.TEXT, 8)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_child(sub)
	add_child(logo)

	var panel := ScreenKit.window_panel()
	panel.custom_minimum_size = Vector2(340, 0)
	menu = ScreenKit.vbox(10)
	panel.add_child(ScreenKit.margin(menu, 6))
	new_button = ScreenKit.button("New Game", true)
	new_button.name = "NewGame"
	new_button.pressed.connect(func() -> void: new_game_pressed.emit())
	continue_button = ScreenKit.button("Continue", true)
	continue_button.name = "Continue"
	continue_button.pressed.connect(func() -> void: continue_pressed.emit(continue_slot))
	continue_info = ScreenKit.label("", 13, ScreenKit.TEXT_DIM, "MisoDim")
	continue_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	load_button = ScreenKit.button("Load")
	load_button.name = "Load"
	load_button.pressed.connect(show_slots)
	quit_button = ScreenKit.button("Quit")
	quit_button.name = "Quit"
	quit_button.pressed.connect(func() -> void: quit_pressed.emit())
	for c in [continue_button, continue_info, new_button, load_button, quit_button]:
		menu.add_child(c)
	message = ScreenKit.label("", 14, ScreenKit.BAD, "MisoBad")
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(300, 0)
	message.visible = false
	menu.add_child(message)
	_menu_panel = panel
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var center := ScreenKit.centered(panel)
	center.offset_top = 170
	holder.add_child(center)

	slots = SlotList.new()
	slots.visible = false
	slots.slot_chosen.connect(func(s: String) -> void: load_pressed.emit(s))
	slots.restore_requested.connect(func(s: String) -> void: restore_pressed.emit(s))
	slots.closed.connect(hide_slots)
	var slot_center := ScreenKit.centered(slots)
	slot_center.offset_top = 120
	add_child(slot_center)

	var foot := ScreenKit.outlined("Gameplay data: MeowDB MS Classic (meowdb.com). An isometric fan interpretation.", 13,
		ScreenKit.TEXT_DIM, 4)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -30
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(foot)


## Updates the buttons from Saves.list_saves() entries: Continue = the most recently saved loadable slot.
func set_saves(entries: Array) -> void:
	continue_slot = SaveSlotIndex.continue_slot(entries)
	continue_button.visible = continue_slot != ""
	continue_info.visible = continue_slot != ""
	if continue_slot != "":
		var e := SaveSlotIndex.entry(entries, continue_slot)
		var d := SlotList.describe(e)
		continue_info.text = "%s  ·  %s" % [d["line1"], String((e.get("meta", {}) as Dictionary).get("map_name", ""))]
	load_button.disabled = entries.is_empty()
	slots.set_entries(entries)


## Shows an error under the menu ("" hides it).
func show_message(text: String) -> void:
	message.text = text
	message.visible = text != ""


func show_slots() -> void:
	_menu_panel.visible = false
	slots.visible = true
	slots.focus_first()


func hide_slots() -> void:
	slots.visible = false
	_menu_panel.visible = true
	focus_default()


func slots_open() -> bool:
	return slots.visible


## Focuses Continue when shown, else New Game.
func focus_default() -> void:
	if continue_button.visible:
		continue_button.grab_focus()
	else:
		new_button.grab_focus()
