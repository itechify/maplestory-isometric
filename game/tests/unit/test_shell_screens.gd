extends TestCase
## The shell's screens built headless (no frames needed): the title's Continue/Load from save entries, the slot
## list text (name, level, map, play time), the creation screen's Start gating and +/- buttons, the controls list,
## the pause menu's sub-panels, the death notice's single confirmation and the root window's theme.

var holder: Node = null


func before_each() -> void:
	holder = Control.new()
	_parent().add_child(holder)


## The test runner scene (the root is still busy adding it while tests run).
func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root.get_child(tree.root.get_child_count() - 1)


func after_each() -> void:
	holder.free()


func _entry(slot: String, ok: bool, t: int, level: int = 3) -> Dictionary:
	return {"slot": slot, "ok": ok, "modified_unix": t, "has_backup": not ok, "error_text": "" if ok else "not JSON",
		"saved_at": "2026-10-04T12:34:56Z", "source": "main",
		"meta": {"name": "Maple", "level": level, "map_id": "000000040", "map_name": "Snail Hunting Ground I",
			"play_time_s": 3725.0} if ok else {}}


func test_title_continue_follows_the_saves() -> void:
	var t := TitleScreen.new()
	holder.add_child(t)
	t.set_saves([])
	assert_false(t.continue_button.visible, "no Continue without a save")
	assert_true(t.load_button.disabled, "nothing to load")
	t.set_saves([_entry("slot1", true, 10), _entry("slot2", true, 20), _entry("slot3", false, 30)])
	assert_true(t.continue_button.visible, "Continue with a save")
	assert_eq(t.continue_slot, "slot2", "Continue = the newest loadable save")
	assert_true(t.continue_info.text.contains("Maple") and t.continue_info.text.contains("Lv 3"), t.continue_info.text)
	assert_false(t.load_button.disabled, "Load enabled")
	var chosen: Array = []
	t.continue_pressed.connect(func(s: String) -> void: chosen.append(s))
	t.continue_button.pressed.emit()
	assert_eq(chosen, ["slot2"], "Continue emits its slot")
	t.show_slots()
	assert_true(t.slots_open(), "the slot list opens")
	assert_true(t.slots.load_button("slot1") != null and t.slots.load_button("slot3") == null, "only loadable slots load")
	var loaded: Array = []
	t.load_pressed.connect(func(s: String) -> void: loaded.append(s))
	t.slots.load_button("slot1").pressed.emit()
	assert_eq(loaded, ["slot1"], "Load emits the slot")
	t.hide_slots()
	assert_false(t.slots_open(), "closed")
	t.show_message("Cannot load")
	assert_true(t.message.visible, "error message")


func test_slot_rows_describe_name_level_map_and_play_time() -> void:
	var d := SlotList.describe(_entry("slot4", true, 1, 7))
	assert_eq(d["line1"], "Maple   Lv 7", "name and level")
	assert_true(String(d["line2"]).contains("Snail Hunting Ground I"), "map name")
	assert_true(String(d["line2"]).contains("1:02:05"), "play time")
	assert_true(String(d["line2"]).contains("slot4"), "slot")
	var bad := SlotList.describe(_entry("slot5", false, 1))
	assert_true(String(bad["line1"]).contains("unreadable"), "unreadable save")
	assert_true(String(bad["line2"]).contains("backup"), "backup mentioned")


func test_creation_screen_gates_start() -> void:
	var m := CreationModel.new(db())
	var s := CreationScreen.new(m)
	holder.add_child(s)
	assert_true(s.start_button.disabled, "no name, no Start")
	s.name_edit.text = "Maple"
	s.name_edit.text_changed.emit("Maple")
	assert_eq(m.name, "Maple", "the field feeds the model")
	assert_false(s.start_button.disabled, "valid with the default spread: %s" % s.errors_label.text)
	var minus := s.find_child("Minus_str", true, false) as Button
	minus.pressed.emit()
	assert_eq(m.ap_remaining(), 1, "- takes one AP back")
	assert_true(s.start_button.disabled, "Start disabled with AP left")
	assert_true(s.errors_label.text.contains("1 AP"), s.errors_label.text)
	var plus := s.find_child("Plus_luk", true, false) as Button
	plus.pressed.emit()
	assert_eq(m.stat_total("luk"), m.starting_stat("luk") + int(CharacterFactory.default_params(db())["ap"].get("luk", 0)) + 1,
		"+ places one AP")
	assert_true((s.find_child("Plus_dex", true, false) as Button).disabled, "+ disabled with no AP left")
	var weapon := s.find_child("Weapon_541", true, false) as Button
	weapon.pressed.emit()
	assert_eq(m.weapon_id, "541", "weapon choice")
	var started: Array = []
	s.start_pressed.connect(func(p: Dictionary) -> void: started.append(p))
	assert_true(s.submit(), "Start")
	assert_eq(started.size(), 1, "start_pressed(params)")
	assert_eq(started[0]["weapon_id"], "541", "params carry the weapon")
	s.name_edit.text_changed.emit("ab")
	assert_false(s.submit(), "an invalid name cannot start")


func test_controls_list_covers_every_binding() -> void:
	var rows := ControlsPanel.rows()
	assert_eq(rows.size(), ControlsPanel.BINDINGS.size(), "one row per action")
	var by_action := {}
	for r in rows:
		by_action[r["action"]] = r
	assert_eq(by_action["jump"]["label"], ControlsPanel.LABELS["jump"], "labels from Controls.LABELS")
	assert_true(String(by_action["jump"]["keys"]).contains("Space"), "Space jumps: %s" % by_action["jump"]["keys"])
	assert_true(String(by_action["attack"]["keys"]).contains("Left click"), "mouse binding named")
	assert_true(String(by_action["menu"]["keys"]).contains("Escape"), "Esc opens the menu")


func test_pause_menu_sub_panels() -> void:
	var p := PauseMenu.new()
	holder.add_child(p)
	p.open()
	assert_false(p.in_sub_panel(), "opens on the buttons")
	var asked: Array = []
	p.load_requested.connect(func() -> void: asked.append(true))
	p.show_load()
	assert_true(p.in_sub_panel() and asked.size() == 1, "Load asks for the save list")
	assert_true(p.back(), "Esc closes the sub-panel")
	assert_false(p.back(), "Esc on the buttons means resume (the shell resumes)")
	p.show_controls()
	assert_true(p.controls.visible, "controls")
	p.set_status("Saved")
	assert_true(p.status_label.visible, "status shown")
	p.set_status("")
	assert_false(p.status_label.visible, "empty status hidden")
	assert_eq(p.process_mode, Node.PROCESS_MODE_ALWAYS, "the menu runs while the tree is paused")


func test_death_notice_confirms_once() -> void:
	var n := DeathNotice.new()
	holder.add_child(n)
	var count: Array = []
	n.confirmed.connect(func() -> void: count.append(1))
	n.open("Returns you to Southperry")
	assert_true(n.visible and n.detail.visible, "open with the return town")
	assert_eq(n.message.text, DeathNotice.TEXT, "the classic question")
	n.ok_button.pressed.emit()
	n.confirm()
	assert_eq(count.size(), 1, "OK confirms once")
	n.open()
	n.confirm()
	assert_eq(count.size(), 2, "a new death can be confirmed again")
	assert_false(n.detail.visible, "no detail line without text")


## MainShell gives the root window MisoTheme at boot, so tooltips and popups (their own windows) share the look. It is
## loaded by path: the shell compiles and runs with Godot's default theme when MisoTheme is absent.
func test_ui_theme_goes_on_the_root_window() -> void:
	var w := Window.new()
	assert_true(ResourceLoader.exists(ScreenKit.MISO_THEME_PATH), "MisoTheme ships with the game")
	var miso := load(ScreenKit.MISO_THEME_PATH) as GDScript
	assert_true(MainShell.apply_ui_theme(w), "applied")
	assert_true(w.theme != null and w.theme == miso.call("get_theme"), "MisoTheme.get_theme() on the window")
	assert_false(MainShell.apply_ui_theme(null), "no window: nothing to do")
	w.free()
