class_name DialogueWindow
extends PanelContainer
## The NPC dialogue window: renders every VIEW NpcInteraction produces (DialogueRunner: say, yes_no, menu; speaker
## kinds npc, journal, system) and forwards the player's answers. A MapleStory-inspired chat box built in code: the
## speaker's portrait and name plate on the left, the quest title, the text (canonical segments: bold, red, item /
## monster / NPC references highlighted) and the choices on a parchment body, buttons along the bottom.
##
## Input: Enter/Space = Next/OK (or the highlighted choice / Yes-No button), Backspace = Back, Y/N = Yes/No,
## Up/Down (W/S) move through choices, Left/Right (A/D) between Yes and No, 1-9 pick a choice directly, Esc ends the
## chat (in the game the shell's window stack calls close(); standalone the window handles Esc itself). Every button
## is clickable; End Chat is always offered, because closing at any point is safe: display nodes never run actions,
## so nothing half-done is lost, and accepted/completed quests stay accepted/completed.
##
## Feedback the VIEW does not carry is added from data and the event bus: an offer shows the quest's canonical rewards;
## accepting shows "Quest accepted" with the items handed over; completing shows "Quest complete" with the EXP, mesos
## and items actually gained (random rewards included). If the chat ends right after, that summary goes to
## Events.notice instead.
##
## Modal: push_modal/pop_modal and window_opened/window_closed on the GameContext (null ctx = standalone).

signal opened()
signal closed()
## The window rendered a view (tests and the sandbox use it).
signal view_rendered(view: Dictionary)

const WIDTH := 860.0
## Width of the text column (window width minus the portrait column, paddings and gaps).
const TEXT_WIDTH := 640.0
## Space under the window when nothing else sits at the bottom of the screen, and above a bottom bar that does.
const BOTTOM_GAP := 28.0
const INSET_GAP := 12.0
const BUTTON_TEXT := {"back": "Back", "next": "Next", "ok": "OK", "yes": "Yes", "no": "No", "end": "End Chat"}
const TAG_BADGES := {
	"offer": {"glyph": "!", "fill": Color("#f7b733"), "ink": Color("#4a2a02")},
	"turnin": {"glyph": "?", "fill": Color("#43b25a"), "ink": Color("#ffffff")},
	"turnin_wait": {"glyph": "...", "fill": Color("#aab0ba"), "ink": Color("#ffffff")},
	"reminder": {"glyph": "...", "fill": Color("#aab0ba"), "ink": Color("#ffffff")},
	"lost": {"glyph": "!", "fill": Color("#e2683c"), "ink": Color("#ffffff")},
}

var ctx: GameContext = null
var talk: NpcInteraction = null
var db: ContentDB = null
## (npc_id: String) -> Node3D model to render in the portrait, or null (badge).
var model_provider: Callable = Callable()
## () -> float: pixels at the bottom of the screen taken by another UI layer's bar (NpcUi.bottom_inset); empty = 0.
var bottom_inset_provider: Callable = Callable()
## Handle Esc here (standalone). In the game the shell's window stack closes the window instead.
var handle_escape: bool = true
## Event bus for the notice fallback; null = the talk's QuestService bus.
var bus: Object = null

## The view on screen ({"open": false} when closed).
var view: Dictionary = {"open": false}
## Highlight: menu = position in view.choices; yes_no = 0 Yes / 1 No.
var selected: int = 0

var portrait: NpcPortrait = null
var name_label: Label = null
var title_label: Label = null
var kind_label: Label = null
var kind_panel: PanelContainer = null
var banner: PanelContainer = null
var banner_label: Label = null
var body: RichTextLabel = null
var reward_label: RichTextLabel = null
var choice_box: VBoxContainer = null
var hint_label: Label = null
var buttons: Dictionary = {}

var _open := false
var _closing := false
## True while _input is handling a real key event (see _release_modal_after_key).
var _key_driven := false
## The context whose modal a key-driven close still holds (null when nothing is pending).
var _held_ctx: GameContext = null
## Engine.get_physics_frames() when the key-driven close happened.
var _held_since: int = 0
var _buffer: Array = []
var _bus_connected: Object = null
var _choice_rows: Array[PanelContainer] = []
var _pending_quest: Dictionary = {}


func _init() -> void:
	name = "DialogueWindow"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


# --- wiring ----------------------------------------------------------------------------------------------------

## Connects the window to a conversation controller (the shared NpcInteraction). Safe to call again with another.
func bind_talk(p_talk: NpcInteraction) -> void:
	if talk == p_talk:
		return
	if talk != null and talk.view_changed.is_connected(show_view):
		talk.view_changed.disconnect(show_view)
	talk = p_talk
	if talk != null:
		talk.view_changed.connect(show_view)
		if db == null:
			db = talk.service.engine.db
		_connect_bus(talk.service.bus)


func _connect_bus(b: Object) -> void:
	if b == _bus_connected:
		return
	_disconnect_bus()
	if b == null:
		return
	var handlers := {"exp_gained": _on_exp, "item_gained": _on_item_gained, "mesos_changed": _on_mesos,
		"quest_started": _on_quest_started, "quest_completed": _on_quest_completed}
	for sig: String in handlers:
		if b.has_signal(sig) and not b.is_connected(sig, handlers[sig]):
			b.connect(sig, handlers[sig])
	_bus_connected = b


func _disconnect_bus() -> void:
	if _bus_connected == null or not is_instance_valid(_bus_connected):
		_bus_connected = null
		return
	for pair in [["exp_gained", _on_exp], ["item_gained", _on_item_gained], ["mesos_changed", _on_mesos],
			["quest_started", _on_quest_started], ["quest_completed", _on_quest_completed]]:
		if _bus_connected.has_signal(pair[0]) and _bus_connected.is_connected(pair[0], pair[1]):
			_bus_connected.disconnect(pair[0], pair[1])
	_bus_connected = null


func _exit_tree() -> void:
	if _open:
		close()
	# Never leave a modal behind (a key-driven close may still hold it).
	_release_held_modal()


# --- public handlers (buttons, keys and tests go through these) ------------------------------------------------

## True while a conversation is on screen.
func is_open() -> bool:
	return _open


## Presses a button of the current view: "next", "ok", "back", "yes", "no" or "end". Returns the new view.
func press(button: String) -> Dictionary:
	if not _open or talk == null:
		return {"open": false}
	if button == "end":
		close()
		return {"open": false}
	if not (button in visible_buttons()):
		return view
	return talk.press(button)


## Picks the choice at `position` in the visible list (0-based). Returns the new view.
func choose_position(position: int) -> Dictionary:
	var cs: Array = view.get("choices", [])
	if not _open or talk == null or position < 0 or position >= cs.size():
		return view
	return talk.choose(int((cs[position] as Dictionary).get("index", -1)))


## The primary action: Next/OK on a line, the highlighted button on Yes/No, the highlighted choice on a menu.
func activate() -> Dictionary:
	match String(view.get("type", "")):
		"menu":
			return choose_position(selected)
		"yes_no":
			return press("yes" if selected == 0 else "no")
		_:
			for b in ["next", "ok"]:
				if b in visible_buttons():
					return press(b)
	return view


## Ends the conversation (End Chat, Esc, the window stack). Safe at any point.
func close() -> void:
	if _closing:
		return
	_closing = true
	if talk != null and talk.is_open():
		talk.close()
	_hide()
	_closing = false


## The buttons shown now: the view's own (back/next/ok/yes/no/end) plus End Chat, which is always offered.
func visible_buttons() -> PackedStringArray:
	var out := PackedStringArray()
	for b: Variant in view.get("buttons", []):
		out.append(String(b))
	if bool(view.get("open", false)) and not ("end" in out):
		out.append("end")
	return out


## The body text as plain text (what is on screen, without markup).
func body_text() -> String:
	return body.get_parsed_text() if body != null else ""


## Visible choice texts in order.
func choice_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for c: Variant in view.get("choices", []):
		out.append(String((c as Dictionary).get("text", "")))
	return out


## Handles a key. Returns true when the key was used.
func handle_key(event: InputEventKey) -> bool:
	if not _open or not event.pressed:
		return false
	var t := String(view.get("type", ""))
	var k := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if event.echo and not (k in [KEY_UP, KEY_DOWN, KEY_W, KEY_S]):
		return false
	match k:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			activate()
			return true
		KEY_BACKSPACE:
			if "back" in visible_buttons():
				press("back")
			return true
		KEY_ESCAPE:
			if handle_escape:
				close()
				return true
			return false
		KEY_Y:
			if t == "yes_no":
				press("yes")
				return true
		KEY_N:
			if t == "yes_no":
				press("no")
				return true
		KEY_UP, KEY_W:
			if t == "menu":
				_move_selection(-1)
				return true
		KEY_DOWN, KEY_S:
			if t == "menu":
				_move_selection(1)
				return true
		KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D:
			if t == "yes_no":
				selected = 1 - clampi(selected, 0, 1)
				_refresh_highlight()
				return true
	if t == "menu":
		var n := -1
		if k >= KEY_1 and k <= KEY_9:
			n = k - KEY_1
		elif k >= KEY_KP_1 and k <= KEY_KP_9:
			n = k - KEY_KP_1
		if n >= 0:
			if n < (view.get("choices", []) as Array).size():
				choose_position(n)
			return true
	# Keys this window uses are swallowed even when they do nothing in this view (digits would otherwise reach the
	# quickslots, WASD/arrows the world); everything else (I, E, Q, the console key, F3) passes through.
	return (k >= KEY_0 and k <= KEY_9) or (k >= KEY_KP_0 and k <= KEY_KP_9) \
		or k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_Y, KEY_N]


func _input(event: InputEvent) -> void:
	if not (_open and visible and event is InputEventKey):
		return
	_key_driven = true
	var used := handle_key(event as InputEventKey)
	_key_driven = false
	if used:
		get_viewport().set_input_as_handled()


# --- rendering -------------------------------------------------------------------------------------------------

## Renders a VIEW (connected to NpcInteraction.view_changed). {"open": false} hides the window.
func show_view(v: Dictionary) -> void:
	if not bool(v.get("open", false)):
		view = {"open": false}
		_hide()
		return
	var same_node := _open and String(v.get("node_id", "")) == String(view.get("node_id", ""))
	view = v
	if not same_node:
		selected = 0
	_render()
	_buffer.clear()
	if not _open:
		_show()
	view_rendered.emit(v)


func _render() -> void:
	var kind := String(view.get("speaker_kind", "npc"))
	var npc_id := String(view.get("speaker_id", view.get("npc_id", "")))
	var speaker := String(view.get("speaker_name", ""))
	var model: Node3D = null
	if kind != "system" and model_provider.is_valid():
		var m: Variant = model_provider.call(npc_id)
		model = m if m is Node3D else null
	portrait.show_speaker(npc_id, speaker, model, kind)
	name_label.text = "Notice" if kind == "system" else speaker
	var title := String(view.get("title", ""))
	title_label.text = title
	title_label.visible = not title.is_empty()
	var tag := ""
	if kind == "journal":
		tag = "QUEST"
	elif kind == "system":
		tag = "SYSTEM"
	elif String(view.get("node_id", "")).ends_with(".quiz"):
		tag = "QUIZ"
	elif not title.is_empty():
		tag = "QUEST"
	kind_label.text = tag
	kind_panel.visible = not tag.is_empty()
	# Banner: the reward / accept summary from the events of the last step.
	var banner_text := pending_banner()
	var banner_kind := pending_banner_kind()
	_pending_quest = {}
	banner.visible = not banner_text.is_empty()
	banner_label.text = banner_text
	var bstyle := NpcUiStyle.box(Color("#e3f4e1") if banner_kind == "complete" else Color("#e2ecf8"),
		Color("#5aa564") if banner_kind == "complete" else Color("#6d8fc2"), 1, 5, 10, 5)
	banner.add_theme_stylebox_override("panel", bstyle)
	# Text.
	var segs: Array = view.get("segments", [])
	body.text = DialogueRichText.to_bbcode(segs, String(view.get("text", "")))
	# Offer rewards.
	var rewards := offer_reward_text()
	reward_label.text = rewards
	reward_label.visible = not rewards.is_empty()
	_render_choices()
	_render_buttons()
	_refresh_highlight()
	reset_size()
	_layout.call_deferred()


func _render_choices() -> void:
	for r in _choice_rows:
		choice_box.remove_child(r)
		r.queue_free()
	_choice_rows.clear()
	var cs: Array = view.get("choices", [])
	choice_box.visible = not cs.is_empty()
	for i in cs.size():
		var c: Dictionary = cs[i]
		# A panel row (not a Button) so long quiz answers wrap and the row grows with them.
		var row := PanelContainer.new()
		row.name = "Choice_%d" % i
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 8)
		row.add_child(h)
		var num := NpcUiStyle.label("%d." % (i + 1), NpcUiStyle.INK_SOFT, 15, true)
		num.custom_minimum_size = Vector2(22, 0)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(num)
		var badge_key := _badge_for(c)
		if not badge_key.is_empty():
			h.add_child(_mini_badge(badge_key))
		var lbl := RichTextLabel.new()
		lbl.bbcode_enabled = true
		lbl.fit_content = true
		lbl.scroll_active = false
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Wrapping text needs a width before its first layout, or its minimum height explodes.
		lbl.custom_minimum_size = Vector2(TEXT_WIDTH - 70.0, 0)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		NpcUiStyle.style_rich(lbl, 16)
		lbl.text = DialogueRichText.to_bbcode(c.get("segments", []), String(c.get("text", "")))
		h.add_child(lbl)
		var pos := i
		row.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
					and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				# Deferred: choosing re-renders (frees) this row, which is still handling the click.
				choose_position.call_deferred(pos))
		row.mouse_entered.connect(func() -> void:
			selected = pos
			_refresh_highlight())
		choice_box.add_child(row)
		_choice_rows.append(row)


func _render_buttons() -> void:
	var shown := visible_buttons()
	for b: String in buttons:
		(buttons[b] as Button).visible = b in shown
	var hints := PackedStringArray()
	match String(view.get("type", "")):
		"menu":
			hints.append("1-9 / Up-Down + Enter: choose")
		"yes_no":
			hints.append("Y / N or Left-Right + Enter")
		_:
			hints.append("Enter / Space: %s" % ("Next" if "next" in shown else "OK"))
	if "back" in shown:
		hints.append("Backspace: Back")
	hints.append("Esc: End Chat")
	hint_label.text = "   ".join(hints)


func _refresh_highlight() -> void:
	var t := String(view.get("type", ""))
	for i in _choice_rows.size():
		var on := t == "menu" and i == selected
		var st := NpcUiStyle.box(NpcUiStyle.SELECT if on else Color(1, 1, 1, 0.0),
			Color("#d9a440") if on else Color(0, 0, 0, 0.0), 1, 5, 6, 3)
		_choice_rows[i].add_theme_stylebox_override("panel", st)
	for pair in [["yes", 0], ["no", 1]]:
		var b: Button = buttons[pair[0]]
		var hot := t == "yes_no" and selected == int(pair[1])
		NpcUiStyle.style_button(b, "primary" if hot else "secondary")


func _move_selection(d: int) -> void:
	var n := (view.get("choices", []) as Array).size()
	if n == 0:
		return
	selected = wrapi(selected + d, 0, n)
	_refresh_highlight()


## The badge for a quest-entry choice (offer "!", ready turn-in "?", waiting "...", lost item "!").
func _badge_for(c: Dictionary) -> String:
	var tag := String(c.get("tag", ""))
	if tag == "turnin":
		var qid := String(c.get("quest_id", ""))
		var ready := talk != null and talk.service.engine.ready_to_turn_in(qid, String(view.get("npc_id", "")))
		return "turnin" if ready else "turnin_wait"
	return tag if TAG_BADGES.has(tag) else ""


func _mini_badge(key: String) -> Control:
	var st: Dictionary = TAG_BADGES[key]
	var c := Control.new()
	c.custom_minimum_size = Vector2(20, 20)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.draw.connect(func() -> void:
		var center := c.size * 0.5
		c.draw_circle(center, 9.5, (st["fill"] as Color).darkened(0.35))
		c.draw_circle(center, 8.0, st["fill"])
		var font := NpcUiStyle.bold_font()
		var g: String = st["glyph"]
		var fs := 14 if g.length() == 1 else 10
		var w := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		c.draw_string(font, Vector2(center.x - w * 0.5, center.y + font.get_ascent(fs) * 0.36), g,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, st["ink"]))
	return c


## "Rewards: 30 EXP, Egg x3" for the quest of an offer view (canonical QuestDef rewards), "" otherwise.
func offer_reward_text() -> String:
	var qid := _offer_quest_id(String(view.get("node_id", "")))
	if qid.is_empty() or talk == null:
		return ""
	var d := talk.service.engine.definition(qid)
	if d == null:
		return ""
	var parts := PackedStringArray()
	if d.reward_exp > 0:
		parts.append("[b]%d EXP[/b]" % d.reward_exp)
	if d.reward_mesos > 0:
		parts.append("[b]%s mesos[/b]" % _thousands(d.reward_mesos))
	if d.reward_fame != 0:
		parts.append("[b]%+d Fame[/b]" % d.reward_fame)
	for it: Dictionary in d.reward_items:
		parts.append(_item_bb(String(it.get("item_id", "")), int(it.get("count", 1))))
	for g: Dictionary in d.reward_random:
		var names := PackedStringArray()
		for it: Dictionary in g.get("items", []):
			names.append(_item_bb(String(it.get("item_id", "")), int(it.get("count", 1))))
		if not names.is_empty():
			parts.append("one of: " + ", ".join(names))
	for g: Dictionary in d.reward_selection:
		var names := PackedStringArray()
		for it: Dictionary in g.get("items", []):
			names.append(_item_bb(String(it.get("item_id", "")), int(it.get("count", 1))))
		if not names.is_empty():
			parts.append("your choice of: " + ", ".join(names))
	if parts.is_empty():
		return ""
	return "[color=#6b6255]Rewards:[/color] " + "  ·  ".join(parts)


static func _offer_quest_id(node_id: String) -> String:
	# Offer nodes are "q<id>.offer.<n>" (NpcDialogueBuilder).
	if not node_id.begins_with("q") or not node_id.contains(".offer."):
		return ""
	return node_id.substr(1, node_id.find(".") - 1)


func _item_bb(item_id: String, count: int) -> String:
	var n := String(db.item(item_id).get("name", item_id)) if db != null else item_id
	var s := "[color=%s][b]%s[/b][/color]" % [DialogueRichText.REF_COLORS["item"], DialogueRichText.escape(n)]
	return s if count <= 1 else "%s x%d" % [s, count]


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# --- quest feedback (events) -----------------------------------------------------------------------------------

## True while a conversation runs (the runner is open even before the first view reaches the window).
func _in_conversation() -> bool:
	return _open or (talk != null and talk.is_open())


func _on_exp(amount: int, source: String) -> void:
	if _in_conversation():
		_buffer.append({"type": "exp", "amount": amount, "source": source})


func _on_item_gained(item_id: String, qty: int) -> void:
	if _in_conversation():
		_buffer.append({"type": "item", "item_id": item_id, "qty": qty})


func _on_mesos(_mesos: int, delta: int) -> void:
	if delta > 0 and _in_conversation():
		_buffer.append({"type": "mesos", "delta": delta})


func _on_quest_started(quest_id: String) -> void:
	if not _in_conversation():
		_buffer.clear()
		return
	# Accept items arrive after quest_started: the text is composed when the step's view renders (or the chat ends).
	_pending_quest = {"kind": "accepted", "quest_id": quest_id}


func _on_quest_completed(quest_id: String) -> void:
	if not _in_conversation():
		_buffer.clear()
		return
	_pending_quest = {"kind": "complete", "quest_id": quest_id}


## The summary of the last quest step from the events buffered since the previous view:
## "Quest accepted: <name>   ·   Received <items>" or "Quest complete: <name>   ·   +30 EXP, +Egg x3". "" if none.
func pending_banner() -> String:
	if _pending_quest.is_empty():
		return ""
	var qid := String(_pending_quest["quest_id"])
	var parts := PackedStringArray()
	if _pending_quest["kind"] == "accepted":
		for e: Dictionary in _buffer:
			if e["type"] == "item":
				parts.append(_item_name(String(e["item_id"]), int(e["qty"])))
		var text := "Quest accepted: %s" % _quest_name(qid)
		return text if parts.is_empty() else text + "   ·   Received " + ", ".join(parts)
	for e: Dictionary in _buffer:
		match String(e["type"]):
			"exp":
				if String(e["source"]) == "quest:" + qid:
					parts.append("+%d EXP" % int(e["amount"]))
			"mesos":
				parts.append("+%s mesos" % _thousands(int(e["delta"])))
			"item":
				parts.append("+%s" % _item_name(String(e["item_id"]), int(e["qty"])))
	var done := "Quest complete: %s" % _quest_name(qid)
	return done if parts.is_empty() else done + "   ·   " + ", ".join(parts)


## The kind of the pending summary ("accepted", "complete" or "").
func pending_banner_kind() -> String:
	return String(_pending_quest.get("kind", ""))


## The summary rendered in the current view ("" if none).
func shown_banner() -> String:
	return banner_label.text if banner.visible else ""


func _quest_name(qid: String) -> String:
	return String(db.quest(qid).get("name", qid)) if db != null else qid


func _item_name(item_id: String, qty: int) -> String:
	var n := String(db.item(item_id).get("name", item_id)) if db != null else item_id
	return n if qty <= 1 else "%s x%d" % [n, qty]


# --- open / close ----------------------------------------------------------------------------------------------

func _show() -> void:
	_open = true
	visible = true
	# A new chat right after a key-driven close keeps the modal it still holds (push_modal is idempotent).
	_cancel_held_modal()
	if ctx != null:
		ctx.push_modal(self)
		ctx.window_opened(self)
	_layout()
	opened.emit()


func _hide() -> void:
	if not _open:
		return
	_open = false
	visible = false
	var banner_text := pending_banner()
	_pending_quest = {}
	if not banner_text.is_empty():
		# The chat ended right after a quest step: the summary would never render, so announce it instead.
		var b := bus if bus != null else (talk.service.bus if talk != null else null)
		WorldUiServices.emit(b, &"notice", [banner_text])
	_buffer.clear()
	if ctx != null:
		if _key_driven and is_inside_tree():
			_release_modal_after_key()
		else:
			ctx.pop_modal(self)
		ctx.window_closed(self)
	closed.emit()


## A key that closes the chat (Enter/Space on the last line, Y on an offer, a digit) is still "just pressed" for the
## gameplay code that polls Input in this physics step, and Space is also the jump key: popping the modal at once
## would hand the player the keyboard in time to jump on the same press. So a key-driven close keeps the modal until
## a physics step has run after the key event; every other close (End Chat, Esc through the window stack, a death,
## tests) releases it at once.
func _release_modal_after_key() -> void:
	_held_ctx = ctx
	_held_since = Engine.get_physics_frames()
	var tree := get_tree()
	if not tree.process_frame.is_connected(_on_held_modal_frame):
		tree.process_frame.connect(_on_held_modal_frame)


func _on_held_modal_frame() -> void:
	if Engine.get_physics_frames() <= _held_since:
		return
	_release_held_modal()


## Pops the modal a key-driven close kept (no-op when nothing is held or the chat reopened meanwhile).
func _release_held_modal() -> void:
	var c := _held_ctx
	_cancel_held_modal()
	if c != null and not _open:
		c.pop_modal(self)


func _cancel_held_modal() -> void:
	_held_ctx = null
	if is_inside_tree() and get_tree().process_frame.is_connected(_on_held_modal_frame):
		get_tree().process_frame.disconnect(_on_held_modal_frame)


## True while a key-driven close still holds the modal (one physics step at most).
func is_holding_modal() -> bool:
	return _held_ctx != null


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_VISIBILITY_CHANGED:
		_layout.call_deferred()


## Bottom-centre of the parent area, above the bottom bar other UI layers keep there (the HUD's status bar; see
## NpcUi.bottom_inset), so the chat never covers the HP/MP/EXP gauges.
func _layout() -> void:
	if not is_inside_tree():
		return
	var area := get_parent_area_size()
	var sz := get_combined_minimum_size()
	size = Vector2(maxf(sz.x, WIDTH), sz.y)
	var inset := float(bottom_inset_provider.call()) if bottom_inset_provider.is_valid() else 0.0
	var gap := maxf(BOTTOM_GAP, inset + INSET_GAP) if inset > 0.0 else BOTTOM_GAP
	position = Vector2(roundf((area.x - size.x) * 0.5), maxf(8.0, roundf(area.y - size.y - gap)))


# --- construction ----------------------------------------------------------------------------------------------

func _build() -> void:
	add_theme_stylebox_override("panel", NpcUiStyle.window_frame())
	custom_minimum_size = Vector2(WIDTH, 0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)
	# Left column: portrait + name plate.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	top.add_child(left)
	portrait = NpcPortrait.new()
	left.add_child(portrait)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", NpcUiStyle.inset())
	left.add_child(plate)
	name_label = NpcUiStyle.label("", NpcUiStyle.NPC_NAME, 16, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(NpcPortrait.PORTRAIT_SIZE.x - 16, 0)
	plate.add_child(name_label)
	# Right column: title row + parchment body.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	top.add_child(right)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	right.add_child(title_row)
	kind_label = NpcUiStyle.label("", Color("#2a1a04"), 11, true)
	kind_panel = PanelContainer.new()
	kind_panel.add_theme_stylebox_override("panel", NpcUiStyle.box(NpcUiStyle.chrome("accent"), NpcUiStyle.chrome("accent").darkened(0.3), 1, 4, 6, 1))
	kind_panel.add_child(kind_label)
	title_row.add_child(kind_panel)
	title_label = NpcUiStyle.label("", NpcUiStyle.chrome("title"), 18, true)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_label)
	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", NpcUiStyle.body_panel())
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.custom_minimum_size = Vector2(0, 150)
	right.add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	page.add_child(col)
	banner = PanelContainer.new()
	banner.visible = false
	col.add_child(banner)
	banner_label = NpcUiStyle.label("", Color("#1f3b22"), 14, true)
	banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_label.custom_minimum_size = Vector2(TEXT_WIDTH - 24.0, 0)
	banner.add_child(banner_label)
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.selection_enabled = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NpcUiStyle.style_rich(body, 17)
	col.add_child(body)
	reward_label = RichTextLabel.new()
	reward_label.bbcode_enabled = true
	reward_label.fit_content = true
	reward_label.scroll_active = false
	reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward_label.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	reward_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	NpcUiStyle.style_rich(reward_label, 15)
	reward_label.visible = false
	col.add_child(reward_label)
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 2)
	choice_box.visible = false
	col.add_child(choice_box)
	# Bottom bar.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	buttons["end"] = _make_button("end", "secondary")
	bar.add_child(buttons["end"])
	hint_label = NpcUiStyle.label("", NpcUiStyle.chrome("dim"), 12)
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(hint_label)
	for b in ["back", "no", "yes", "next", "ok"]:
		buttons[b] = _make_button(b, "secondary" if b in ["back", "no"] else "primary")
		bar.add_child(buttons[b])


func _make_button(key: String, kind: String) -> Button:
	var b := Button.new()
	b.name = "Btn_" + key
	b.text = BUTTON_TEXT[key]
	b.custom_minimum_size = Vector2(92, 34)
	NpcUiStyle.style_button(b, kind)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(func() -> void: press(key))
	b.visible = false
	return b
