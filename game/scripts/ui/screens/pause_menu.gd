class_name PauseMenu
extends Control
## The in-game menu (Esc when no window is open): Resume, Save, Load, Controls, Quit to Title and Quit Game. It
## runs while the tree is paused (process_mode ALWAYS); the shell pauses the world and pushes it as a modal. Esc
## inside the menu goes back from a sub-panel, else resumes (handled by the shell through back()).

signal resume_pressed
signal save_pressed
signal load_chosen(slot: String)
signal quit_to_title_pressed
signal quit_game_pressed
## The Load panel opened: the shell answers with set_saves(Saves.list_saves()).
signal load_requested

var panel: PanelContainer = null
var buttons: VBoxContainer = null
var status_label: Label = null
var slots: SlotList = null
var controls: ControlsPanel = null
var resume_button: Button = null
var save_button: Button = null
var load_button: Button = null


func _init() -> void:
	name = "PauseMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	ScreenKit.full_rect(self)
	ScreenKit.apply(self)
	add_child(ScreenKit.dim())
	panel = ScreenKit.window_panel()
	panel.custom_minimum_size = Vector2(320, 0)
	buttons = ScreenKit.vbox(9)
	panel.add_child(ScreenKit.margin(buttons, 6))
	var t := ScreenKit.title("Menu", 22)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	buttons.add_child(t)
	resume_button = _add("Resume", func() -> void: resume_pressed.emit(), true)
	save_button = _add("Save", func() -> void: save_pressed.emit())
	load_button = _add("Load", show_load)
	_add("Controls", show_controls)
	_add("Quit to Title", func() -> void: quit_to_title_pressed.emit())
	_add("Quit Game", func() -> void: quit_game_pressed.emit())
	status_label = ScreenKit.label("", 13, ScreenKit.TEXT_DIM, "MisoDim")
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(280, 0)
	buttons.add_child(status_label)
	add_child(ScreenKit.centered(panel))

	slots = SlotList.new()
	slots.visible = false
	slots.slot_chosen.connect(func(s: String) -> void: load_chosen.emit(s))
	slots.closed.connect(show_main)
	add_child(ScreenKit.centered(slots))
	controls = ControlsPanel.new()
	controls.visible = false
	controls.closed.connect(show_main)
	add_child(ScreenKit.centered(controls))


## Opens on the main button list with an empty status line.
func open() -> void:
	show()
	show_main()
	set_status("")


func show_main() -> void:
	slots.visible = false
	controls.visible = false
	panel.visible = true
	resume_button.grab_focus()


func show_load() -> void:
	panel.visible = false
	controls.visible = false
	slots.visible = true
	load_requested.emit()
	slots.focus_first()


func show_controls() -> void:
	panel.visible = false
	slots.visible = false
	controls.visible = true
	controls.focus_default()


## Feeds the Load panel (Saves.list_saves() entries).
func set_saves(entries: Array) -> void:
	slots.set_entries(entries)


func set_status(text: String, bad: bool = false) -> void:
	status_label.text = text
	status_label.visible = text != ""
	status_label.add_theme_color_override("font_color", ScreenKit.BAD if bad else ScreenKit.TEXT_DIM)


## True while a sub-panel (Load, Controls) is open.
func in_sub_panel() -> bool:
	return slots.visible or controls.visible


## Esc inside the menu: closes a sub-panel and returns true, or returns false (the shell then resumes).
func back() -> bool:
	if in_sub_panel():
		show_main()
		return true
	return false


func _add(text: String, cb: Callable, accent: bool = false) -> Button:
	var b := ScreenKit.button(text, accent)
	b.name = text.replace(" ", "")
	b.pressed.connect(cb)
	buttons.add_child(b)
	return b
