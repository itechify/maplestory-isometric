class_name MisoForfeitPrompt
extends Control
## The Quest Log's confirmation before a quest is forfeited (owner ruling #10): "Forfeit <quest>?", what is lost, and
## who offers it again, with Forfeit and Cancel. Modal while open (the player stands still and the window hotkeys stay
## quiet) and registered on the window stack, so Esc cancels it first, like DepartureScreen.
##
## Mouse: the two buttons. Keyboard: Cancel holds the focus when it opens, Left/Right (Tab) move between the buttons
## and Enter presses the focused one; Y forfeits, N or Esc cancels. Space and Alt are the jump keys, which players
## hold and mash, so they never press a button here, and neither does key repeat (DeathNotice.ignores_key).
##
## The prompt changes nothing itself: `confirmed(quest_id)` asks its owner (MisoQuestWindow) to forfeit, `cancelled`
## says nothing happened. MisoWindowsRoot puts it above the windows; MisoQuestWindow opens it.

signal confirmed(quest_id: String)
signal cancelled(quest_id: String)

const TITLE := "Forfeit quest?"
const CONFIRM_TEXT := "Forfeit"
const CANCEL_TEXT := "Cancel"

var env: MisoUiEnv = null
## The quest asked about ("" when closed).
var quest_id: String = ""
var title_label: Label
var message_label: Label
var confirm_button: Button
var cancel_button: Button
var _ctx: GameContext = null


func _init() -> void:
	name = "ForfeitPrompt"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.12, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"MisoWindow"
	panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	title_label = Label.new()
	title_label.text = TITLE
	title_label.theme_type_variation = &"MisoTitle"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title_label)
	message_label = Label.new()
	message_label.theme_type_variation = &"MisoSmall"
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size = Vector2(360, 0)
	v.add_child(message_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	confirm_button = _button(CONFIRM_TEXT, &"MisoAccentButton")
	confirm_button.pressed.connect(confirm)
	row.add_child(confirm_button)
	cancel_button = _button(CANCEL_TEXT, &"")
	cancel_button.pressed.connect(cancel)
	row.add_child(cancel_button)


## Asks about `p_quest_id`: `quest_name` in the question, `npc_name` (who offers it again) in the explanation.
func open(p_quest_id: String, quest_name: String, npc_name: String = "") -> void:
	quest_id = p_quest_id
	message_label.text = message_for(quest_name, npc_name)
	show()
	move_to_front()
	if _ctx == null:
		_ctx = env.ctx if env != null else null
		if _ctx != null:
			_ctx.push_modal(self)
	if env != null:
		env.window_opened(self)
	if is_inside_tree():
		cancel_button.grab_focus()


## The explanation under the title (static, so it is testable without a scene).
static func message_for(quest_name: String, npc_name: String) -> String:
	var again := "You can accept it again from %s." % npc_name if npc_name != "" else "You can accept it again later."
	return "Forfeit %s? Its progress is lost, and items the quest gave you are taken back. %s" % [quest_name, again]


func is_open() -> bool:
	return visible


## Forfeit: closes the prompt, then emits `confirmed` once.
func confirm() -> void:
	if not visible:
		return
	var q := quest_id
	_close()
	confirmed.emit(q)


## Cancel (the button, N, Esc, or the window stack's close()): nothing changes.
func cancel() -> void:
	if not visible:
		return
	var q := quest_id
	_close()
	cancelled.emit(q)


## The window stack's hook (Esc through GameContext.close_top_window): cancels.
func close() -> void:
	cancel()


func _close() -> void:
	# Hand the keyboard back: a focused button would keep Enter and the arrows away from the game.
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()
	hide()
	quest_id = ""
	if _ctx != null:
		_ctx.pop_modal(self)
	_ctx = null
	if env != null:
		env.window_closed(self)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if not visible or k == null or not k.pressed or k.echo:
		return
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	match code:
		KEY_Y:
			confirm()
		KEY_N, KEY_ESCAPE:
			cancel()
		_:
			return
	get_viewport().set_input_as_handled()


func _button(text: String, variation: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = FOCUS_ALL
	b.custom_minimum_size = Vector2(110, 0)
	if variation != &"":
		b.theme_type_variation = variation
	b.gui_input.connect(_filter_button_input.bind(b))
	return b


## Runs first on every event a focused button receives: jump keys and key repeat never press it.
func _filter_button_input(event: InputEvent, b: Button) -> void:
	if event is InputEventKey and DeathNotice.ignores_key(event as InputEventKey):
		b.accept_event()
