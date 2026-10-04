class_name DebugConsole
extends PanelContainer
## The debug console panel (built in code): a scrolling output and an input line with history (Up/Down), Tab
## completion (command names, then map / item / monster / quest ids and other argument kinds), PageUp/PageDown
## scrolling and Ctrl+L to clear. Every line goes through Debug.run(); the console holds no command logic.
## Commands run by code (tests, bots) are mirrored dimmed, and Debug.message lines (screenshots) appear in yellow.

signal opened()
signal closed()

const HEIGHT_FRACTION := 0.46
const MAX_PARAGRAPHS := 3000
const FONT_SIZE := 15
const C_ECHO := "#8fd3ff"
const C_CODE := "#7f8a99"
const C_ERROR := "#ffb27a"
const C_MESSAGE := "#ffe27a"
const C_HINT := "#a8b3c2"

var output: RichTextLabel = null
var input: LineEdit = null
var hint: Label = null
## The Debug autoload (or an injected DebugTools for sandboxes).
var dbg: DebugTools = null

var _history_index: int = -1
var _draft: String = ""
var _from_console: bool = false


func _init() -> void:
	name = "Console"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = HEIGHT_FRACTION
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.035, 0.045, 0.065, 0.9)
	bg.border_color = Color(0.35, 0.75, 1.0, 0.85)
	bg.border_width_bottom = 2
	bg.content_margin_left = 12
	bg.content_margin_right = 12
	bg.content_margin_top = 8
	bg.content_margin_bottom = 8
	add_theme_stylebox_override("panel", bg)
	var font := DebugConsole.mono_font()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	hint = Label.new()
	hint.text = "MisoStory debug console   help: commands   Tab: complete   Up/Down: history   PgUp/PgDn: scroll   Ctrl+L: clear   Esc / `: close"
	hint.add_theme_font_override("font", font)
	hint.add_theme_font_size_override("font_size", FONT_SIZE - 3)
	hint.add_theme_color_override("font_color", Color(C_HINT))
	box.add_child(hint)
	output = RichTextLabel.new()
	output.bbcode_enabled = true
	output.scroll_following = true
	output.selection_enabled = true
	output.context_menu_enabled = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.focus_mode = Control.FOCUS_NONE
	output.add_theme_font_override("normal_font", font)
	output.add_theme_font_override("mono_font", font)
	output.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	output.add_theme_color_override("default_color", Color(0.86, 0.89, 0.93))
	box.add_child(output)
	var row := HBoxContainer.new()
	box.add_child(row)
	var prompt := Label.new()
	prompt.text = ">"
	prompt.add_theme_font_override("font", font)
	prompt.add_theme_font_size_override("font_size", FONT_SIZE + 1)
	prompt.add_theme_color_override("font_color", Color(C_ECHO))
	row.add_child(prompt)
	input = LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.placeholder_text = "type a command (help)"
	input.caret_blink = true
	input.keep_editing_on_text_submit = true
	input.add_theme_font_override("font", font)
	input.add_theme_font_size_override("font_size", FONT_SIZE + 1)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	field.content_margin_left = 6
	field.content_margin_right = 6
	field.content_margin_top = 3
	field.content_margin_bottom = 3
	input.add_theme_stylebox_override("normal", field)
	input.add_theme_stylebox_override("focus", field)
	row.add_child(input)
	input.text_submitted.connect(_on_submit)
	input.gui_input.connect(_on_input_key)


## Uses `d` for commands, history and completion, and mirrors its command_ran / message / clear_requested.
func bind(d: DebugTools) -> void:
	if dbg != null and is_instance_valid(dbg):
		for pair in [["command_ran", _on_command_ran], ["message", _on_message], ["clear_requested", clear]]:
			if dbg.is_connected(pair[0], pair[1]):
				dbg.disconnect(pair[0], pair[1])
	dbg = d
	if d != null:
		d.command_ran.connect(_on_command_ran)
		d.message.connect(_on_message)
		d.clear_requested.connect(clear)


func _on_message(text: String) -> void:
	print_line(text, C_MESSAGE)


## A monospace system font (no font file is shipped; the OS supplies one).
static func mono_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "DejaVu Sans Mono", "Menlo", "Courier New", "monospace"])
	return f


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	_history_index = -1
	input.grab_focus()
	if input.has_method("edit"):
		input.call("edit")  # Godot 4.4+: focus alone does not start editing
	opened.emit()


## Closes the console (also the window stack's close()).
func close() -> void:
	if not visible:
		return
	visible = false
	if input.is_inside_tree():  # closed by DebugUI._exit_tree, after its children left the tree
		input.release_focus()
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func clear() -> void:
	output.clear()


## Runs a line through Debug.run() and prints it with its output (the console's own submit path).
func submit(line: String) -> String:
	var l := line.strip_edges()
	if l == "":
		return ""
	if dbg == null:
		print_line("no Debug autoload", C_ERROR)
		return ""
	dbg.add_history(l)
	_history_index = -1
	print_line("> " + l, C_ECHO)
	_from_console = true
	var out := dbg.run(l)
	_from_console = false
	if out != "":
		print_line(out, C_ERROR if DebugConsole.looks_like_error(out) else "")
	return out


func print_line(text: String, color: String = "") -> void:
	var safe := text.replace("[", "[lb]")
	output.append_text(("[color=%s]%s[/color]\n" % [color, safe]) if color != "" else safe + "\n")
	while output.get_paragraph_count() > MAX_PARAGRAPHS:
		output.remove_paragraph(0)


static func looks_like_error(out: String) -> bool:
	var first := out.get_slice("\n", 0)
	for marker in ["unknown command", "usage:", "failed", "refused", "cannot", ": no ", "needs ", "unavailable", "must be", "no room"]:
		if first.contains(marker):
			return true
	return false


func _on_submit(text: String) -> void:
	input.clear()
	submit(text)


func _on_command_ran(line: String, out: String) -> void:
	if _from_console:
		return
	print_line("(code) > " + line, C_CODE)
	if out != "":
		print_line(out, C_CODE)


func _on_input_key(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	match k.keycode:
		KEY_UP:
			_history_step(-1)
			input.accept_event()
		KEY_DOWN:
			_history_step(1)
			input.accept_event()
		KEY_TAB:
			_complete()
			input.accept_event()
		KEY_PAGEUP:
			output.get_v_scroll_bar().value -= output.size.y * 0.8
			input.accept_event()
		KEY_PAGEDOWN:
			output.get_v_scroll_bar().value += output.size.y * 0.8
			input.accept_event()
		KEY_L:
			if k.ctrl_pressed:
				clear()
				input.accept_event()


func _history_step(dir: int) -> void:
	var h := dbg.history if dbg != null else PackedStringArray()
	if h.is_empty():
		return
	if _history_index == -1:
		if dir > 0:
			return
		_draft = input.text
		_history_index = h.size() - 1
	else:
		_history_index += dir
	if _history_index >= h.size():
		_history_index = -1
		input.text = _draft
	else:
		_history_index = clampi(_history_index, 0, h.size() - 1)
		input.text = h[_history_index]
	input.caret_column = input.text.length()


func _complete() -> void:
	if dbg == null:
		return
	var r := dbg.complete(input.text)
	input.text = String(r.line)
	input.caret_column = input.text.length()
	var c: PackedStringArray = r.candidates
	if not c.is_empty():
		print_line("  ".join(c), C_HINT)
