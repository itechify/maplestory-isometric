extends TestCase
## The dialogue window driven end to end through its UI layer (keys and buttons), on a private Events bus with a real
## QuestService + NpcInteraction: Roger's Apple and Sam's Suggestion from offer to reward, decline + Back, Rain's quiz
## with number keys and arrows, the system line on a full inventory, every VIEW shape, safe closing at any point, the
## modal + window stack contract, and a walk through every NPC's conversation.

class FakePlayer:
	extends Node3D
	var input_on := true

	func set_input_enabled(on: bool) -> void:
		input_on = on

	func is_input_enabled() -> bool:
		return input_on


var bus: Node
var character: CharacterState
var service: QuestService
var talk: NpcInteraction
var win: DialogueWindow
var events: Array = []


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	events = []
	for s: Dictionary in bus.get_script().get_script_signal_list():
		var sname := String(s["name"])
		match (s["args"] as Array).size():
			0:
				bus.connect(sname, func() -> void: events.append([sname]))
			1:
				bus.connect(sname, func(a: Variant) -> void: events.append([sname, a]))
			2:
				bus.connect(sname, func(a: Variant, b: Variant) -> void: events.append([sname, a, b]))
			3:
				bus.connect(sname, func(a: Variant, b: Variant, c: Variant) -> void: events.append([sname, a, b, c]))
	character = CharacterState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	service = QuestService.create(bus, db(), character, rng, func() -> float: return 3.0)
	service.attach()
	talk = NpcInteraction.new(service)
	win = DialogueWindow.new()
	win.db = db()
	win.bind_talk(talk)
	_parent().add_child(win)


func after_each() -> void:
	service.detach()
	if is_instance_valid(win):
		win.free()
	bus.free()


func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root


func _key(k: Key) -> bool:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = true
	return win.handle_key(e)


func _emitted(sname: String) -> Array:
	var out: Array = []
	for e: Array in events:
		if e[0] == sname:
			out.append(e.slice(1))
	return out


## Presses Enter until the window closes; returns the body texts seen.
func _enter_to_end() -> PackedStringArray:
	var seen := PackedStringArray()
	for i in 30:
		if not win.is_open():
			break
		seen.append(win.body_text())
		_key(KEY_ENTER)
	return seen


# --- Roger's Apple (quest 1002) ------------------------------------------------------------------------------------

func test_roger_apple_from_offer_to_completion_through_the_window() -> void:
	talk.talk("3")
	assert_true(win.is_open(), "the view opened the window")
	assert_true(win.visible)
	assert_eq(win.view["type"], "yes_no")
	assert_eq(win.title_label.text, "Roger's Apple")
	assert_eq(win.kind_label.text, "QUEST", "a quest card (journal speaker)")
	assert_eq(win.name_label.text, "Roger")
	assert_true(win.body_text().begins_with("Press the hotkey I"), win.body_text())
	assert_true(win.buttons["yes"].visible and win.buttons["no"].visible and win.buttons["end"].visible)
	assert_false(win.buttons["next"].visible)
	assert_false(win.reward_label.visible, "1002 gives no rewards (canonical)")
	assert_true(_key(KEY_Y), "Y accepts")
	assert_false(win.is_open(), "no accepted lines: the chat ends")
	assert_eq(character.inventory.count("235"), 1, "Roger's Apple handed over")
	assert_has(_emitted("notice"), ["Quest accepted: Roger's Apple   ·   Received Roger's Apple"],
		"the chat ended right after the accept, so the summary went to the notice log")
	talk.talk("3")
	assert_true(win.body_text().begins_with("Eat the Roger's Apple I gave you"))
	assert_true(win.body.text.contains("[color=%s]" % DialogueRichText.REF_COLORS["item"]), "item ref highlighted")
	assert_true(_key(KEY_ESCAPE), "Esc ends the chat (standalone)")
	assert_false(win.is_open())
	ItemService.new(character, db(), bus).use_item("235")
	talk.talk("3")
	assert_eq(character.quests.status("1002"), QuestLog.COMPLETED, "talking to Roger completes it")
	assert_eq(win.shown_banner(), "Quest complete: Roger's Apple", "0 EXP, 0 mesos: nothing to list")
	assert_eq(win.body_text(), "Was my information helpful? Farewell, my dear Mapler!")
	_key(KEY_ENTER)
	assert_false(win.is_open())
	assert_eq(_emitted("quest_completed"), [["1002"]])


# --- Sam's Suggestion (quest 1006) ---------------------------------------------------------------------------------

func test_sam_suggestion_from_offer_to_reward_through_the_window() -> void:
	talk.talk("9")
	assert_eq(win.view["type"], "yes_no")
	assert_true(win.reward_label.visible, "the offer shows the canonical rewards")
	var rewards := win.reward_label.get_parsed_text()
	assert_true(rewards.contains("30 EXP") and rewards.contains("Egg x3"), rewards)
	assert_true(win.body.text.contains("[b]Sam[/b]"), "bold NPC name kept")
	win.press("yes")
	assert_eq(character.quests.status("1006"), QuestLog.IN_PROGRESS)
	assert_eq(win.shown_banner(), "Quest accepted: Sam's Suggestion")
	assert_true(win.body_text().begins_with("Mai is one of the very best fighters"))
	assert_true(win.body.text.contains("[color=%s]" % DialogueRichText.RED), "red monster name")
	assert_false(win.buttons["back"].visible, "no Back across the accept")
	var lines := _enter_to_end()
	assert_eq(lines.size(), 2, "the two accepted lines (canonical)")
	assert_eq(_emitted("dialogue_closed"), [["9"]])
	for k in 10:
		bus.emit_signal("monster_killed", "2", "000000040")
	talk.talk("11")
	assert_true(win.body_text().begins_with("Are you the one that Sam mentioned?"))
	assert_true(_key(KEY_SPACE), "Space = Next")
	assert_eq(character.quests.status("1006"), QuestLog.COMPLETED)
	var banner := win.shown_banner()
	assert_true(banner.begins_with("Quest complete: Sam's Suggestion"), banner)
	assert_true(banner.contains("+30 EXP") and banner.contains("+Egg x3"), banner)
	_enter_to_end()
	assert_eq(character.inventory.count("237"), 3)
	assert_has(_emitted("exp_gained"), [30, "quest:1006"])


func test_decline_then_back_with_keys() -> void:
	talk.talk("9")
	assert_true(_key(KEY_N), "N declines")
	assert_true(win.body_text().begins_with("Trust me. You'll want to prepare yourself"))
	assert_true(win.buttons["back"].visible)
	assert_true(_key(KEY_BACKSPACE))
	assert_eq(win.view["type"], "yes_no", "Back to the question")
	assert_eq(character.quests.status("1006"), QuestLog.NOT_STARTED)
	# Left/Right move the highlight; Enter presses it.
	assert_eq(win.selected, 0, "Yes highlighted")
	_key(KEY_RIGHT)
	assert_eq(win.selected, 1)
	_key(KEY_ENTER)
	assert_true(win.body_text().begins_with("Trust me."), "Enter on No declines")


# --- Rain's quiz (quest 1013): menu with number keys and arrows --------------------------------------------------

func test_quiz_menu_with_number_keys_and_arrows() -> void:
	character.level = 5
	talk.talk("19")
	_key(KEY_Y)
	_enter_to_end()
	talk.talk("19")
	assert_eq(win.view["type"], "menu")
	assert_eq(win.kind_label.text, "QUIZ")
	assert_eq(win.choice_texts().size(), 4)
	assert_eq(win.choice_texts()[2], "up arrow key")
	assert_eq(win._choice_rows.size(), 4, "one row per choice")
	assert_true(win.buttons["end"].visible)
	assert_true(_key(KEY_1), "1 picks the first choice")
	assert_true(win.body_text().begins_with("The left arrow key is for moving left."))
	assert_eq(character.quests.status("1013"), QuestLog.IN_PROGRESS)
	_enter_to_end()
	talk.talk("19")
	_key(KEY_DOWN)
	_key(KEY_DOWN)
	assert_eq(win.selected, 2)
	_key(KEY_UP)
	_key(KEY_DOWN)
	_key(KEY_ENTER)
	assert_true(win.body_text().begins_with("That's right! If you press the up arrow"), win.body_text())
	assert_eq(character.quests.status("1013"), QuestLog.COMPLETED)
	assert_true(win.shown_banner().contains("+20 EXP"), win.shown_banner())
	assert_true(_key(KEY_9), "a number without a choice is swallowed, not passed to quickslots")


func test_full_inventory_shows_the_system_line() -> void:
	talk.talk("9")
	win.press("yes")
	win.close()
	for k in 10:
		bus.emit_signal("monster_killed", "2", "000000040")
	for k in 4000:
		if character.inventory.add("270", 100, db()) < 100:
			break
	talk.talk("11")
	_key(KEY_ENTER)
	assert_eq(win.view["speaker_kind"], "system")
	assert_eq(win.name_label.text, "Notice")
	assert_eq(win.kind_label.text, "SYSTEM")
	assert_eq(win.portrait.mode, "badge")
	assert_true(win.body_text().begins_with("Your inventory is full."), win.body_text())
	assert_eq(character.quests.status("1006"), QuestLog.IN_PROGRESS)


# --- every VIEW shape ----------------------------------------------------------------------------------------------

func _view(extra: Dictionary) -> Dictionary:
	var v := {"open": true, "node_id": "n", "type": "say", "npc_id": "8", "speaker_id": "8", "speaker_name": "Robin",
		"portrait": "npc_8", "speaker_kind": "npc", "title": "", "text": "", "segments": [], "source": "",
		"choices": [], "buttons": []}
	v.merge(extra, true)
	return v


func test_every_view_shape_renders() -> void:
	var segs := [{"text": "Bring ", "bold": false, "color": ""},
		{"text": "10 Snails", "bold": true, "color": "red", "ref": {"kind": "monster", "id": "2", "known": true}},
		{"text": " and an ", "bold": false, "color": ""},
		{"text": "[Egg]", "bold": false, "color": "", "ref": {"kind": "item", "id": "237", "known": true}}]
	var shapes := [
		_view({"text": "Hello! I'm Robin.", "segments": [{"text": "Hello! I'm Robin.", "bold": false, "color": ""}], "buttons": ["next"]}),
		_view({"text": "Second page", "buttons": ["back", "ok"]}),
		_view({"type": "yes_no", "title": "Sam's Suggestion", "segments": segs, "buttons": ["yes", "no"]}),
		_view({"type": "menu", "text": "What do you need?", "choices": [
			{"index": 0, "text": "Sam's Suggestion", "segments": [], "quest_id": "1006", "tag": "offer"},
			{"index": 2, "text": "Roger's Apple", "segments": [], "quest_id": "1002", "tag": "turnin"},
			{"index": 3, "text": "Borrowing Sera's Mirror", "segments": [], "quest_id": "1000", "tag": "reminder"},
			{"index": 5, "text": "Bringing a Mirror to Heena", "segments": [], "quest_id": "1001", "tag": "lost"},
			{"index": 7, "text": "a very long quiz answer ".repeat(6), "segments": [], "quest_id": "", "tag": ""}],
			"buttons": ["end"]}),
		_view({"speaker_kind": "journal", "type": "yes_no", "title": "Roger's Apple", "text": "Quest card", "buttons": ["yes", "no"]}),
		_view({"speaker_kind": "system", "speaker_id": "", "speaker_name": "", "text": "Your inventory is full.", "buttons": ["ok"]}),
		_view({"text": "", "segments": [], "buttons": ["ok"]}),
		_view({"type": "mystery", "text": "unknown type", "buttons": []}),
		_view({"speaker_kind": "npc", "speaker_id": "3", "speaker_name": "Roger", "text": "[b]not markup[/b]", "buttons": ["ok"]}),
	]
	for v: Dictionary in shapes:
		win.show_view(v)
		assert_true(win.is_open(), "open for %s" % v["type"])
		assert_eq(win.body_text(), DialogueRichText.plain(v["segments"], v["text"]), "text of %s" % v["node_id"])
		for b: String in ["back", "next", "ok", "yes", "no"]:
			assert_eq(win.buttons[b].visible, b in v["buttons"], "%s button for %s" % [b, v["type"]])
		assert_true(win.buttons["end"].visible, "End Chat always offered")
		assert_eq(win._choice_rows.size(), (v["choices"] as Array).size())
	assert_eq(win.body_text(), "[b]not markup[/b]", "canonical brackets are escaped, never markup")
	win.show_view(shapes[2])
	assert_true(win.body.text.contains("[color=%s][b]10 Snails[/b][/color]" % DialogueRichText.RED))
	assert_true(win.body.text.contains("[color=%s][b][lb]Egg[rb][/b][/color]" % DialogueRichText.REF_COLORS["item"]))
	win.show_view({"open": false})
	assert_false(win.is_open())
	assert_false(win.visible)


class RecordingTalk:
	extends NpcInteraction
	var chosen: Array = []

	func choose(index: int) -> Dictionary:
		chosen.append(index)
		return {"open": false}


func test_choice_index_is_the_runner_index_not_the_position() -> void:
	# Menus hide choices whose condition fails, so a choice's visible position and its runner index differ; the
	# window must hand the runner the index.
	var rec := RecordingTalk.new(service)
	win.bind_talk(rec)
	win.show_view(_view({"type": "menu", "choices": [{"index": 4, "text": "a"}, {"index": 9, "text": "b"}], "buttons": ["end"]}))
	win.choose_position(1)
	_key(KEY_1)
	assert_eq(rec.chosen, [9, 4])


# --- closing ---------------------------------------------------------------------------------------------------

func test_closing_mid_dialogue_is_safe_and_announced_once() -> void:
	talk.talk("9")
	win.close()
	assert_false(win.is_open())
	assert_false(talk.is_open(), "the conversation ended too")
	assert_eq(_emitted("dialogue_closed"), [["9"]], "exactly once")
	win.close()
	assert_eq(_emitted("dialogue_closed").size(), 1, "closing twice is harmless")
	assert_eq(character.quests.status("1006"), QuestLog.NOT_STARTED, "nothing accepted by closing")
	# End Chat at a menu.
	character.level = 5
	talk.talk("19")
	win.press("yes")
	win.close()
	talk.talk("19")
	assert_eq(win.view["type"], "menu")
	win.buttons["end"].emit_signal("pressed")
	assert_false(win.is_open())
	assert_eq(character.quests.status("1013"), QuestLog.IN_PROGRESS, "the quiz stays open for a retry")
	# Talking to someone else while a chat is open replaces it cleanly.
	talk.talk("8")
	talk.talk("3")
	assert_true(win.is_open())
	assert_eq(win.name_label.text, "Roger")
	win.close()


func test_modal_and_window_stack_with_a_game_context() -> void:
	var ctx := GameContext.new()
	var p := FakePlayer.new()
	ctx.player = p
	win.ctx = ctx
	win.handle_escape = false
	var modal_events: Array = []
	ctx.modal_changed.connect(func(on: bool) -> void: modal_events.append(on))
	talk.talk("8")
	assert_true(ctx.is_modal_active(), "dialogue is modal")
	assert_false(p.input_on, "the player stops")
	assert_true(ctx.has_open_windows(), "registered on the window stack")
	assert_false(_key(KEY_ESCAPE), "Esc is left to the shell's window stack")
	assert_true(win.is_open())
	assert_true(ctx.close_top_window(), "the shell's Esc")
	assert_false(win.is_open())
	assert_false(talk.is_open())
	assert_false(ctx.is_modal_active())
	assert_false(ctx.has_open_windows())
	# Replacing one conversation with another keeps exactly one modal owner.
	talk.talk("8")
	talk.talk("3")
	assert_true(ctx.is_modal_active())
	win.close()
	assert_false(ctx.is_modal_active())
	assert_eq(modal_events.count(true), modal_events.count(false), "every push popped")
	p.free()


class FakeSession:
	extends Node
	signal transition_started(request: Variant)


func _npc_ui(ctx: GameContext, session: Node) -> NpcUi:
	var ui := NpcUi.new()
	ui.bus = bus
	ui.session = session
	ui.talk_provider = func() -> NpcInteraction: return talk
	ui.bind_talk(talk)
	ui.dialogue.db = db()
	ui.shop.db = db()
	ui.shop.bus = bus
	ui.shop.character_provider = func() -> CharacterState: return character
	_parent().add_child(ui)
	ui.setup(ctx)
	return ui


## Regression (found in the real game): a warp (the console's `warp`) with a chat open left Roger's chat on screen in
## the next map, still answerable, and a shop request during a chat opened the shop over it (two modal windows, the
## shop eating the chat's keys). A map change now closes both windows, and only one NPC window is open at a time.
func test_one_npc_window_at_a_time_and_a_map_change_closes_them() -> void:
	var ctx := GameContext.new()
	var p := FakePlayer.new()
	ctx.player = p
	var session := FakeSession.new()
	_parent().add_child(session)
	var ui := _npc_ui(ctx, session)
	talk.talk("3")
	assert_true(ui.dialogue.is_open())
	# The session starts a transition (debug warp, respawn, any forced move): the chat ends, nothing is accepted.
	session.transition_started.emit(null)
	assert_false(ui.dialogue.is_open(), "the chat does not follow the player into another map")
	assert_false(talk.is_open())
	assert_false(ctx.is_modal_active())
	assert_eq(character.quests.status("1002"), QuestLog.NOT_STARTED)
	# Events.map_left alone (no session signal) does the same, for the shop too.
	bus.emit_signal("shop_open_requested", "maple-road-lucy", "21")
	assert_true(ui.shop.is_open())
	bus.emit_signal("map_left", "000001013")
	assert_false(ui.shop.is_open(), "the shop closes on a map change")
	assert_false(ctx.is_modal_active())
	# A shop request during a chat ends the chat (after the step that asked for it); one modal owner, one window.
	talk.talk("3")
	bus.emit_signal("shop_open_requested", "maple-road-lucy", "21")
	assert_true(ui.shop.is_open())
	assert_true(ui.is_chat_close_queued(), "the chat is ended at the end of the frame")
	_run_deferred_close(ui)
	assert_false(ui.is_chat_close_queued())
	assert_false(ui.dialogue.is_open(), "the shop replaced the chat")
	assert_false(talk.is_open())
	assert_true(ctx.is_modal_active(), "the shop holds the keyboard")
	assert_true(ctx.close_top_window())
	assert_false(ctx.has_open_windows(), "nothing left under the shop")
	assert_false(ctx.is_modal_active())
	# A chat starting while the shop is open closes the shop.
	ui.open_shop("maple-road-lucy")
	talk.talk("8")
	assert_true(ui.dialogue.is_open())
	assert_false(ui.shop.is_open(), "the chat replaced the shop")
	ui.dialogue.close()
	assert_false(ctx.is_modal_active())
	# Lucy's own greeting still opens her shop and ends by itself (the deferred close finds nothing to do).
	talk.talk("21")
	ui.dialogue.press("next")
	assert_true(ui.shop.is_open())
	assert_false(ui.dialogue.is_open())
	assert_true(ui.is_chat_close_queued(), "the greeting was still open when its step opened the shop")
	_run_deferred_close(ui)
	assert_true(ui.shop.is_open(), "the deferred close never touches the shop")
	ui.shop.close()
	assert_false(ctx.is_modal_active())
	ui.free()
	session.free()
	p.free()


## Runs the close NpcUi defers when a shop opens over a chat (the test runner is synchronous: no frame passes).
func _run_deferred_close(ui: NpcUi) -> void:
	ui._end_chat_for_shop()


## Regression (found in the real game): Space on the last line closed the chat inside _input and popped the modal at
## once, so the player controller, which polls Input in the same physics step, saw "jump" just pressed and jumped.
## A key-driven close now leaves the window stack at once but keeps the modal until a physics step has run.
func test_a_key_that_ends_the_chat_holds_the_modal_through_the_physics_step() -> void:
	var ctx := GameContext.new()
	var p := FakePlayer.new()
	ctx.player = p
	win.ctx = ctx
	win.handle_escape = false
	talk.talk("3")
	assert_eq(String(win.view.get("type", "")), "yes_no", "Roger's offer")
	win._input(_key_event(KEY_Y))
	assert_false(win.is_open(), "Y accepted and ended the chat")
	assert_eq(character.quests.status("1002"), QuestLog.IN_PROGRESS)
	assert_false(ctx.has_open_windows(), "off the window stack at once (Esc goes to the next window)")
	assert_true(ctx.is_modal_active(), "the modal holds through the physics step of the key")
	assert_false(p.input_on, "so the player cannot act on the same press")
	assert_true(win.is_holding_modal())
	win._on_held_modal_frame()
	assert_true(ctx.is_modal_active(), "not released while the physics frame has not advanced")
	# A new chat while the modal is held keeps exactly one owner; any other close releases at once.
	talk.talk("8")
	assert_false(win.is_holding_modal())
	assert_true(ctx.is_modal_active())
	win.close()
	assert_false(ctx.is_modal_active(), "End Chat / Esc / a death release at once")
	# Space on the in-progress line (OK), then the window leaves the tree: the held modal is never left behind.
	talk.talk("3")
	assert_true(win.is_open())
	win._input(_key_event(KEY_SPACE))
	assert_false(win.is_open())
	assert_true(win.is_holding_modal())
	var parent := win.get_parent()
	parent.remove_child(win)
	assert_false(ctx.is_modal_active(), "released when the window leaves the tree")
	parent.add_child(win)
	# handle_key (tests, scripted callers) is not a key event: it releases at once, as before.
	talk.talk("3")
	_key(KEY_ENTER)
	assert_false(win.is_open())
	assert_false(ctx.is_modal_active())
	p.free()


## Regression (found in the real game): the chat was placed 28 px above the screen bottom, over the HUD's status bar,
## whose gauges and texts showed through the window's bottom row. Both windows now sit above any bottom-wide bar of
## another UI layer (found by its anchors, not by name).
func test_windows_sit_above_another_layers_bottom_bar() -> void:
	var area := Control.new()
	area.size = Vector2(1600, 900)
	_parent().add_child(area)
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.add_child(hud)
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -96
	bar.offset_bottom = -4
	hud.add_child(bar)
	var log_box := Control.new()
	log_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_box.offset_top = -300
	hud.add_child(log_box)
	var ui := NpcUi.new()
	ui.talk_provider = func() -> NpcInteraction: return talk
	area.add_child(ui)
	ui.dialogue.db = db()
	assert_near(ui.bottom_inset(), 96.0, 0.5, "the bar's top edge; a bottom-left panel is not a bar")
	talk.talk("3")
	assert_true(ui.dialogue.is_open())
	ui.dialogue._layout()
	var d := ui.dialogue.get_global_rect()
	assert_true(d.end.y <= 900.0 - 96.0, "the chat ends above the bar: %s" % d)
	assert_true(d.position.y >= 0.0, "and stays on screen: %s" % d)
	talk.close()
	assert_true(ui.open_shop("maple-road-lucy", "21"))
	ui.shop._layout()
	var s := ui.shop.get_global_rect()
	assert_true(s.end.y <= 900.0 - 96.0 and s.position.y >= 0.0, "the shop too: %s" % s)
	ui.shop.close()
	bar.visible = false
	assert_eq(ui.bottom_inset(), 0.0, "a hidden bar reserves nothing")
	area.free()


func _key_event(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = true
	return e


# --- robustness: every NPC ---------------------------------------------------------------------------------------

func test_every_npc_conversation_walks_through_the_window() -> void:
	character.level = 10
	var ids := NpcCatalog.new(db()).ids()
	assert_eq(ids.size(), 21)
	var shown := 0
	for r in 3:
		for nid in ids:
			talk.talk(nid)
			for step in 40:
				if not win.is_open():
					break
				shown += 1
				assert_eq(win.is_open(), talk.is_open(), "window follows the runner (%s %s)" % [nid, win.view.get("node_id")])
				match String(win.view["type"]):
					"menu":
						var n := win.choice_texts().size()
						if n == 0:
							win.press("end")
						else:
							win.choose_position((step + r) % n)
					"yes_no":
						win.press("yes" if (step + r) % 3 != 2 else "no")
					_:
						win.activate()
			if win.is_open():
				win.close()
			assert_false(talk.is_open(), "closed after %s" % nid)
	assert_true(shown > 60, "walked %d views" % shown)


# --- text and portrait helpers -------------------------------------------------------------------------------------

func test_rich_text_segments() -> void:
	assert_eq(DialogueRichText.to_bbcode([], "a [b] c"), "a [lb]b[rb] c")
	assert_eq(DialogueRichText.segment_bbcode({"text": "x", "bold": true}), "[b]x[/b]")
	assert_eq(DialogueRichText.segment_bbcode({"text": "x", "color": "red"}), "[color=%s]x[/color]" % DialogueRichText.RED)
	assert_eq(DialogueRichText.segment_bbcode({"text": "Mai", "ref": {"kind": "npc", "id": "11"}}),
		"[color=%s][b]Mai[/b][/color]" % DialogueRichText.REF_COLORS["npc"])
	assert_eq(DialogueRichText.segment_bbcode({"text": "Snail", "color": "red", "ref": {"kind": "monster", "id": "2"}}),
		"[color=%s][b]Snail[/b][/color]" % DialogueRichText.RED, "red wins over the ref colour")
	assert_eq(DialogueRichText.segment_bbcode({"text": "?", "ref": {"kind": "weird", "id": "1"}}), "?")
	assert_eq(DialogueRichText.segment_bbcode({"text": "x", "color": "#2457b8"}), "[color=#2457b8]x[/color]")
	assert_eq(DialogueRichText.segment_bbcode({"text": "x", "color": "#fff][url=evil]"}), "x",
		"a colour that is not a colour never reaches the markup")
	assert_eq(DialogueRichText.plain([{"text": "a"}, {"text": "b"}]), "ab")


func test_portrait_badge_and_model() -> void:
	var p := NpcPortrait.new()
	_parent().add_child(p)
	p.show_speaker("3", "Roger")
	assert_eq(p.mode, "badge", "no model: the initial badge")
	var model := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 1.5, 0.4)
	mi.mesh = box
	mi.position = Vector3(0, 0.75, 0)
	model.add_child(mi)
	p.show_speaker("3", "Roger", model)
	assert_eq(p.mode, "model", "the proxy rendered in a SubViewport")
	p.show_speaker("", "", null, "system")
	assert_eq(p.mode, "badge")
	model.free()
	p.free()
