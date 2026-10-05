extends TestCase
## The shell's screens built headless (no frames needed): the title's Continue/Load from save entries, the slot
## list text (name, level, map, play time), the creation screen's Start gating and +/- buttons, the controls list
## (working actions only), the pause menu's sub-panels, the death notice's single confirmation (a click or Enter,
## never a jump key or key echo) and the root window's theme.

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


func test_controls_list_covers_every_working_binding() -> void:
	var rows := ControlsPanel.rows()
	var by_action := {}
	for r in rows:
		by_action[r["action"]] = r
	for action: String in ["toggle_minimap"]:
		assert_true(ControlsPanel.BINDINGS.has(action), "%s stays reserved in Controls.BINDINGS" % action)
		assert_true(ControlsPanel.NOT_AVAILABLE.has(action), "%s is listed as not available yet" % action)
		assert_false(by_action.has(action), "the panel does not advertise %s: nothing handles it yet" % action)
	for action: String in ControlsPanel.BINDINGS:
		if not ControlsPanel.NOT_AVAILABLE.has(action):
			assert_true(by_action.has(action), "%s has a row" % action)
	for action: String in ControlsPanel.NOT_AVAILABLE:
		assert_true(ControlsPanel.BINDINGS.has(action), "%s: hidden actions are Controls actions" % action)
	assert_eq(rows.size(), ControlsPanel.BINDINGS.size() - ControlsPanel.NOT_AVAILABLE.size(), "one row per working action")
	var shown := PackedStringArray()
	var panel := ControlsPanel.new()
	holder.add_child(panel)
	for l: Node in panel.find_children("*", "Label", true, false):
		shown.append((l as Label).text)
	for label: String in ["Minimap"]:
		assert_false(shown.has(label), "no '%s' row on the panel: %s" % [label, ", ".join(shown)])
	# The Skills window handles K (Iteration Three): its row is listed.
	assert_true(shown.has("Skills"), "a 'Skills' row on the panel")
	assert_true(by_action.has("toggle_skills"), "toggle_skills has a row")
	assert_true(shown.has("Jump"), "the working rows are drawn")
	assert_true(shown.has("Sit"), "sitting works (PlayerController, X): its row is drawn")
	assert_eq(by_action["jump"]["label"], ControlsPanel.LABELS["jump"], "labels from Controls.LABELS")
	assert_true(String(by_action["jump"]["keys"]).contains("Space"), "Space jumps: %s" % by_action["jump"]["keys"])
	assert_true(String(by_action["attack"]["keys"]).contains("Left click"), "mouse binding named")
	assert_true(String(by_action["menu"]["keys"]).contains("Escape"), "Esc opens the menu")


## Keeps NOT_AVAILABLE honest: a hidden action is one no script reads. When a feature starts handling one (a Minimap
## reading "toggle_minimap"), this fails until it is taken off the list, so the panel never hides a working key.
func test_hidden_controls_have_no_handler_yet() -> void:
	# The key map itself and the panel that lists it.
	var skip := ["res://scripts/autoload/controls.gd", "res://scripts/ui/screens/controls_panel.gd"]
	var files := _scripts_under("res://scripts")
	assert_true(files.size() > 50, "the game's scripts were found (%d)" % files.size())
	for path: String in files:
		if skip.has(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		for action: String in ControlsPanel.NOT_AVAILABLE:
			assert_false(text.contains("\"%s\"" % action) or text.contains("'%s'" % action),
				"%s names the hidden action '%s': if it handles it now, take it off ControlsPanel.NOT_AVAILABLE" % [path, action])


func _scripts_under(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for sub in dir.get_directories():
		out.append_array(_scripts_under(dir_path.path_join(sub)))
	return out


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


## One key event, with keycode and physical_keycode both set (Godot's ui_accept matches on keycode, the Controls
## actions on physical_keycode), through the real GUI dispatch: the focused control sees it like a keyboard press.
func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	ev.echo = echo
	holder.get_viewport().push_input(ev)


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)


## Space is Godot's default ui_accept and also the jump key, which players hold (hold_to_rejump) and mash at a death:
## on the focused OK it must not confirm. Alt (the other jump key) and key echo do not either; Enter does. The fix is
## scoped to the notice: the global ui_accept is untouched, so Space still presses the pause menu's Resume.
func test_death_notice_ignores_the_jump_keys_and_echo() -> void:
	var p := PauseMenu.new()
	holder.add_child(p)
	p.open()
	var resumed: Array = []
	p.resume_pressed.connect(func() -> void: resumed.append(1))
	assert_true(p.resume_button.has_focus(), "Resume has the focus")
	_tap(KEY_SPACE)
	assert_eq(resumed.size(), 1, "Space is still ui_accept elsewhere (the global map is untouched): Resume pressed")
	p.hide()

	var n := DeathNotice.new()
	holder.add_child(n)
	var count: Array = []
	n.confirmed.connect(func() -> void: count.append(1))
	n.open("Returns you to Southperry")
	assert_true(n.ok_button.has_focus(), "OK has the focus (so Enter lands on it and nothing else takes the keys)")
	_tap(KEY_SPACE)
	assert_eq(count.size(), 0, "Space (the jump key) does not confirm the death notice")
	n.open()
	count.clear()
	_tap(KEY_ALT)
	assert_eq(count.size(), 0, "Alt (the other jump key) does not confirm")
	n.open()
	count.clear()
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, true, true)
	_key(KEY_SPACE, false)
	assert_eq(count.size(), 0, "a held Space with key repeat does not confirm")
	n.open()
	count.clear()
	_key(KEY_ENTER, true, true)
	_key(KEY_ENTER, false)
	assert_eq(count.size(), 0, "key repeat (Enter held from before the death, then let go) does not confirm")
	assert_true(n.ok_button.has_focus() and n.visible and not n.ok_button.disabled, "the notice is still up, OK enabled")
	_tap(KEY_ENTER)
	assert_eq(count.size(), 1, "Enter confirms")
	n.open()
	count.clear()
	_tap(KEY_KP_ENTER)
	assert_eq(count.size(), 1, "keypad Enter confirms")


## Where the Controls autoload has not registered its actions, the notice reads the jump keys from Controls.BINDINGS.
func test_death_notice_knows_the_jump_keys_without_the_input_map() -> void:
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	assert_true(DeathNotice.ignores_key(space) and not DeathNotice.ignores_key(enter), "with the InputMap")
	if InputMap.has_action(&"jump"):
		InputMap.erase_action(&"jump")
	var alt := InputEventKey.new()
	alt.physical_keycode = KEY_ALT
	alt.pressed = true
	assert_true(DeathNotice.ignores_key(space) and DeathNotice.ignores_key(alt), "Space and Alt from Controls.BINDINGS")
	assert_false(DeathNotice.ignores_key(enter), "Enter still confirms")
	DeathNotice.CONTROLS_SCRIPT.register()
	assert_true(InputMap.has_action(&"jump"), "the key map is restored")


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
