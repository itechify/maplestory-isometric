extends TestCase
## Forfeit from the Quest Log (owner ruling #10): an in-progress quest's detail has a Forfeit button, completed and
## available quests have none; the button asks first (MisoForfeitPrompt), Cancel changes nothing, Forfeit goes
## through Game.quests' QuestService.forfeit (the console's path: quest_forfeited, the accept items taken back) and
## the log updates; the quest is then offered again by its NPC. Mouse (real presses through Viewport.push_input) and
## keyboard (Delete, focus on Cancel, Left/Right, Enter, Y, N, Esc; Space and key repeat never press a button).

const HEENA := "1"
const SERA := "2"
const SAM := "9"
const MIRROR := "438"

var bus: Node
var nodes: Array = []
var game: GameState = null
var ctx: GameContext = null
var talk: NpcInteraction = null
var forfeited: Array = []


func parity_keys() -> Dictionary:
	return {
		"test_confirm_forfeits_and_the_quest_is_offered_again": ["quest:1001"],
	}


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	forfeited = []
	bus.connect("quest_forfeited", func(q: String) -> void: forfeited.append(q))


func after_each() -> void:
	nodes.reverse()
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	if game != null and game.quests != null:
		game.quests.detach()
	game = null
	bus.free()


func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root


## The windows scene on `c` with a GameState whose quests is an attached QuestService on a private bus, and a
## GameContext (modal and window stack).
func _root(c: CharacterState) -> MisoWindowsRoot:
	var qs := QuestService.create(bus, db(), c, RandomNumberGenerator.new(), func() -> float: return 4.0)
	game = GameState.new()
	game.db = db()
	game.event_bus = bus
	game.log_warnings = false
	game.character = c
	game.quests = qs
	qs.attach()
	nodes.append(game)
	talk = NpcInteraction.new(qs)
	ctx = GameContext.new()
	var root: MisoWindowsRoot = load("res://scenes/ui/windows.tscn").instantiate()
	root.configure(MisoUiEnv.isolated(c, db(), bus, ctx, game))
	_parent().add_child(root)
	nodes.append(root)
	root.open_window("quests")
	return root


## A character with 1000 done and 1001 accepted from Sera (she hands over the mirror).
func _with_1001(c: CharacterState = null) -> CharacterState:
	if c == null:
		c = CharacterState.new()
	c.quests.start("1000", 0.0)
	c.quests.complete("1000", 0.0)
	return c


func _accept_1001(root: MisoWindowsRoot) -> void:
	assert_true(bool(game.quests.accept("1001", SERA)["ok"]))
	root.quests.select_tab(MisoQuestWindow.TAB_IN_PROGRESS)
	root.quests.select_quest("1001")


func _layout(c: Control) -> void:
	c.reset_size()
	c.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)


func _click(vp: Viewport, b: Control, frame: Control) -> void:
	_layout(frame)
	var at := b.get_global_rect().get_center()
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	vp.push_input(m, true)
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = at
		e.global_position = at
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		vp.push_input(e, true)


func _key(vp: Viewport, code: Key, echo: bool = false) -> void:
	for pressed: bool in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		k.echo = echo and pressed
		vp.push_input(k, true)


func _listed(w: MisoQuestWindow) -> PackedStringArray:
	var out: PackedStringArray = []
	for e: Dictionary in w.entries:
		out.append(String(e["quest_id"]))
	return out


func test_only_an_in_progress_quest_has_the_button() -> void:
	var c := _with_1001()
	var root := _root(c)
	var w := root.quests
	w.select_tab(MisoQuestWindow.TAB_AVAILABLE)
	w.select_quest("1001")
	assert_eq(w.selected_quest, "1001")
	assert_true(w.forfeit_button == null, "an available (not started) quest has no Forfeit button")
	assert_false(w.request_forfeit(), "and Delete does not ask")
	w.select_tab(MisoQuestWindow.TAB_COMPLETED)
	w.select_quest("1000")
	assert_true(w.forfeit_button == null, "a completed quest has none")
	assert_false(w.request_forfeit())
	_accept_1001(root)
	assert_true(w.forfeit_button != null, "an in-progress quest has one")
	assert_eq(w.forfeit_button.text, "Forfeit")
	assert_true(w.forfeit_button.is_visible_in_tree())
	assert_eq(w.forfeit_button.focus_mode, Control.FOCUS_NONE, "like every window button, it never takes the keyboard")


func test_cancel_changes_nothing() -> void:
	var c := _with_1001()
	var root := _root(c)
	_accept_1001(root)
	var w := root.quests
	var vp := root.get_viewport()
	var before := c.quests.to_dict()
	_click(vp, w.forfeit_button, w)
	var p := root.forfeit_prompt
	assert_true(p.is_open(), "the button asks first")
	assert_eq(p.quest_id, "1001")
	assert_true(p.message_label.text.begins_with("Forfeit Bringing a Mirror to Heena?"), p.message_label.text)
	assert_true(p.message_label.text.contains("accept it again from Sera"), p.message_label.text)
	assert_true(ctx.is_modal_active(), "the prompt is modal")
	assert_eq(c.quests.status("1001"), QuestLog.IN_PROGRESS, "asking changes nothing")
	_click(vp, p.cancel_button, p)
	assert_false(p.is_open())
	assert_false(ctx.is_modal_active(), "the modal is released")
	assert_eq(c.quests.to_dict(), before, "Cancel changes nothing")
	assert_eq(c.inventory.count(MIRROR), 1, "the mirror stays")
	assert_eq(forfeited, [])
	assert_eq(_listed(w), PackedStringArray(["1001"]))


func test_confirm_forfeits_and_the_quest_is_offered_again() -> void:
	var c := _with_1001()
	var root := _root(c)
	_accept_1001(root)
	var w := root.quests
	var vp := root.get_viewport()
	assert_eq(c.inventory.count(MIRROR), 1)
	_click(vp, w.forfeit_button, w)
	_click(vp, root.forfeit_prompt.confirm_button, root.forfeit_prompt)
	assert_false(root.forfeit_prompt.is_open())
	assert_false(ctx.is_modal_active())
	assert_eq(c.quests.status("1001"), QuestLog.NOT_STARTED, "forfeited")
	assert_eq(forfeited, ["1001"], "announced once, as the console's forfeit does")
	assert_eq(c.inventory.count(MIRROR), 0, "the accept item is taken back")
	assert_eq(_listed(w), PackedStringArray(), "the log updates: nothing in progress")
	assert_true(w.forfeit_button == null, "no button")
	w.select_tab(MisoQuestWindow.TAB_AVAILABLE)
	assert_true("1001" in _listed(w), "1001 is available again")
	# Sera offers it again, and accepting hands the mirror over once more.
	var v := talk.talk(SERA)
	assert_eq(String(v.get("node_id", "")).get_slice(".", 0) + "." + String(v.get("node_id", "")).get_slice(".", 1), "q1001.offer", str(v))
	for k in 10:
		if v.get("type") == "yes_no":
			break
		v = talk.press("next")
	v = talk.press("yes")
	assert_eq(c.quests.status("1001"), QuestLog.IN_PROGRESS, "accepted again from Sera")
	assert_eq(c.inventory.count(MIRROR), 1)


func test_keyboard_delete_asks_cancel_has_focus_and_enter_presses_it() -> void:
	var c := _with_1001()
	var root := _root(c)
	_accept_1001(root)
	var vp := root.get_viewport()
	var p := root.forfeit_prompt
	_key(vp, KEY_DELETE)
	assert_true(p.is_open(), "Delete asks while the log is open")
	_layout(p)
	assert_true(p.cancel_button.has_focus(), "Cancel holds the focus")
	_key(vp, KEY_ENTER)
	assert_false(p.is_open(), "Enter on Cancel cancels")
	assert_eq(c.quests.status("1001"), QuestLog.IN_PROGRESS)
	_key(vp, KEY_DELETE)
	_layout(p)
	_key(vp, KEY_LEFT)
	assert_true(p.confirm_button.has_focus(), "Left moves to Forfeit")
	_key(vp, KEY_RIGHT)
	assert_true(p.cancel_button.has_focus(), "Right moves back to Cancel")
	_key(vp, KEY_LEFT)
	_key(vp, KEY_SPACE)
	_key(vp, KEY_ENTER, true)
	assert_true(p.is_open(), "Space (jump) and key repeat never press a button")
	_key(vp, KEY_ENTER)
	assert_false(p.is_open())
	assert_eq(c.quests.status("1001"), QuestLog.NOT_STARTED, "Enter on Forfeit forfeits")
	assert_eq(forfeited, ["1001"])
	assert_true(vp.gui_get_focus_owner() == null, "the keyboard is handed back")


func test_y_n_and_esc() -> void:
	var c := _with_1001()
	var root := _root(c)
	_accept_1001(root)
	var vp := root.get_viewport()
	var p := root.forfeit_prompt
	_key(vp, KEY_DELETE)
	_key(vp, KEY_N)
	assert_false(p.is_open(), "N cancels")
	_key(vp, KEY_DELETE)
	_key(vp, KEY_ESCAPE)
	assert_false(p.is_open(), "Esc cancels")
	assert_true(root.is_open("quests"), "and leaves the log open")
	root.quests.request_forfeit()
	assert_true(ctx.close_top_window(), "the shell's Esc (the window stack) reaches the prompt first")
	assert_false(p.is_open())
	assert_true(root.is_open("quests"))
	assert_eq(c.quests.status("1001"), QuestLog.IN_PROGRESS, "nothing changed so far")
	_key(vp, KEY_DELETE)
	_key(vp, KEY_Y)
	assert_eq(c.quests.status("1001"), QuestLog.NOT_STARTED, "Y forfeits")


func test_quiet_under_another_modal_and_closing_the_log_cancels() -> void:
	var c := _with_1001()
	var root := _root(c)
	_accept_1001(root)
	var vp := root.get_viewport()
	var p := root.forfeit_prompt
	var other := Node.new()
	nodes.append(other)
	ctx.push_modal(other)
	_key(vp, KEY_DELETE)
	assert_false(p.is_open(), "Delete does nothing while a dialogue or shop owns the keyboard")
	ctx.pop_modal(other)
	root.quests.request_forfeit()
	root.quests.close()
	assert_false(p.is_open(), "closing the log cancels the question")
	assert_false(ctx.is_modal_active())
	assert_eq(c.quests.status("1001"), QuestLog.IN_PROGRESS)


func test_without_a_quest_service_nothing_changes() -> void:
	var c := _with_1001()
	var root := _root(c)
	_accept_1001(root)
	game.quests.detach()
	game.quests = null
	var notices: Array = []
	bus.connect("notice", func(t: String) -> void: notices.append(t))
	var r := root.quests.forfeit("1001")
	assert_false(bool(r["ok"]))
	assert_eq(c.quests.status("1001"), QuestLog.IN_PROGRESS)
	assert_eq(notices.size(), 1, "the HUD says it could not")
