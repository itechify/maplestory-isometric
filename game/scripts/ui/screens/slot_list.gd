class_name SlotList
extends PanelContainer
## The save-slot picker (title "Load" and the pause menu's "Load"): one row per slot from Saves.list_saves() with the
## character's name, level, map and play time, and a Load button. An unreadable save is listed with its error and,
## when its backup exists, a "Restore backup" button. Entries are passed in (set_entries), so the list never reads
## files itself.

signal slot_chosen(slot: String)
signal restore_requested(slot: String)
signal closed

var heading := "Load game"
var _rows: VBoxContainer = null
var _empty: Label = null
var _buttons: Dictionary = {}


func _init() -> void:
	if ScreenKit.has_miso_theme():
		theme_type_variation = "MisoWindow"
	else:
		add_theme_stylebox_override("panel", ScreenKit.box(ScreenKit.FALLBACK_PANEL, ScreenKit.FALLBACK_BORDER, 2, 10, 14))
	custom_minimum_size = Vector2(620, 0)
	var v := ScreenKit.vbox(10)
	add_child(v)
	v.add_child(ScreenKit.title(heading))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_rows = ScreenKit.vbox(6)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_empty = ScreenKit.label("No saved games yet.", 0, ScreenKit.TEXT_DIM, "MisoDim")
	v.add_child(_empty)
	var back := ScreenKit.button("Back", false, 120)
	back.name = "Back"
	back.pressed.connect(func() -> void: closed.emit())
	var foot := ScreenKit.hbox()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_child(back)
	v.add_child(foot)


## Rebuilds the rows from Saves.list_saves() entries.
func set_entries(entries: Array) -> void:
	for c in _rows.get_children():
		c.queue_free()
	_buttons.clear()
	_empty.visible = entries.is_empty()
	for e: Variant in entries:
		if e is Dictionary:
			_rows.add_child(_row(e))


## The Load button of a slot (null when the slot is not listed or not loadable).
func load_button(slot: String) -> Button:
	return _buttons.get(slot, null)


## Focuses the first Load button (keyboard navigation), else Back.
func focus_first() -> void:
	for slot in _buttons:
		(_buttons[slot] as Button).grab_focus()
		return
	var back := find_child("Back", true, false) as Button
	if back != null:
		back.grab_focus()


func _row(e: Dictionary) -> Control:
	var slot := String(e.get("slot", ""))
	var panel := ScreenKit.inset_panel()
	var h := ScreenKit.hbox(12)
	panel.add_child(h)
	var info := ScreenKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var text := SlotList.describe(e)
	info.add_child(ScreenKit.label(text["line1"], 17, Color(0, 0, 0, 0), "MisoHeading"))
	info.add_child(ScreenKit.label(text["line2"], 13, ScreenKit.TEXT_DIM if bool(e.get("ok", false)) else ScreenKit.BAD,
		"MisoDim" if bool(e.get("ok", false)) else "MisoBad"))
	if bool(e.get("ok", false)):
		var b := ScreenKit.button("Load", true, 96)
		b.pressed.connect(func() -> void: slot_chosen.emit(slot))
		h.add_child(b)
		_buttons[slot] = b
	elif bool(e.get("has_backup", false)):
		var r := ScreenKit.button("Restore backup", false, 150)
		r.pressed.connect(func() -> void: restore_requested.emit(slot))
		h.add_child(r)
	return panel


## Display text for a list_saves() entry: {"line1": "Maple  Lv 3", "line2": "The Field West of Amherst · 1:02:03 ·
## slot1 · saved 2026-10-04 12:00"}.
static func describe(e: Dictionary) -> Dictionary:
	var slot := String(e.get("slot", ""))
	if not bool(e.get("ok", false)):
		return {"line1": "%s: unreadable save" % slot, "line2": "%s%s" % [String(e.get("error_text", "")),
			" (a backup exists)" if bool(e.get("has_backup", false)) else ""]}
	var m: Dictionary = e.get("meta", {})
	var saved := String(e.get("saved_at", "")).replace("T", " ").trim_suffix("Z")
	if saved.length() > 16:
		saved = saved.left(16)
	var parts: PackedStringArray = [String(m.get("map_name", m.get("map_id", ""))),
		"played " + GameState.format_play_time(float(m.get("play_time_s", 0.0))), slot]
	if saved != "":
		parts.append("saved " + saved)
	if String(e.get("source", "main")) == "backup":
		parts.append("from backup")
	return {"line1": "%s   Lv %d" % [String(m.get("name", "?")), int(m.get("level", 0))], "line2": "  ·  ".join(parts)}
