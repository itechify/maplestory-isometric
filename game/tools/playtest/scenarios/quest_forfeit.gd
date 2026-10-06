extends PlaytestScenario
## quest_forfeit: forfeiting a quest from the Quest Log in the real game (owner ruling #10), strict from character
## creation (no console, no api step). A new character talks to Heena on the start map (000000001) and accepts
## Borrowing Sera's Mirror (1000) with the dialogue's keys. Q opens the Quest Log: the in-progress quest shows a
## Forfeit button, an available quest none. Clicking Forfeit asks first; Cancel (clicked) changes nothing, and Delete
## then Esc (real keys) ask and cancel again. Clicking Forfeit, then the prompt's Forfeit, forfeits the quest through
## the game's QuestService: quest_forfeited on the bus, the HUD's "Quest forfeited" line, the log's In Progress tab
## empty and 1000 back under Available. Heena then offers 1000 again and it is accepted again.

const START_MAP := "000000001"
const HEENA := "1"
const QUEST := "1000"

var d: PlaytestDriver = null
var k: PlaytestKit = null
var forfeited: Array = []


func description() -> String:
	return "Forfeit from the Quest Log: Heena's 1000 accepted, the button only on an in-progress quest, Cancel and " \
		+ "Esc change nothing, Forfeit forfeits (log, HUD, bus), Heena offers it again"


func max_seconds() -> float:
	return 300.0


func run(p_d: PlaytestDriver) -> void:
	d = p_d
	k = PlaytestKit.new(d)
	var ng: Dictionary = await d.new_game("Forfeiter", "female", "", {})
	if not d.check("new game through the title and creation screens", bool(ng["ok"]) and ng["via"] == "screen", str(ng)):
		return
	d.begin_strict("after character creation")
	k.connect_bus()
	d.events().connect("quest_forfeited", func(q: String) -> void: forfeited.append(q))
	if not d.check("the new character starts on %s, Heena's map" % START_MAP, d.current_map() == START_MAP, d.current_map()):
		return

	# --- accept 1000 from Heena ---------------------------------------------------------------------------------------
	if not await _accept_from_heena("first"):
		return

	# --- the Quest Log: the button only on an in-progress quest -------------------------------------------------------
	var wr := d.windows() as MisoWindowsRoot
	var qw := wr.quests
	var prompt := wr.forfeit_prompt
	var avail: Dictionary = await k.quest_window("", MisoQuestWindow.TAB_AVAILABLE)
	var first_available := ""
	for b in qw.list_box.get_children():
		if b is Button:
			first_available = String(b.get_meta("quest_id", ""))
			await d.click(b)
			await d.frames(2)
			break
	d.check("an available quest (%s) has no Forfeit button" % first_available, first_available != ""
		and qw.selected_quest == first_available and qw.forfeit_button == null, "%s; list %s" % [qw.selected_quest, avail["list"]])
	var ql: Dictionary = await k.quest_window(QUEST, MisoQuestWindow.TAB_IN_PROGRESS)
	d.check("the Quest Log lists %s under In Progress and shows its detail" % k.qname(QUEST), bool(ql["listed"])
		and String(ql["selected"]) == QUEST, str(ql["list"]))
	d.check("the in-progress quest shows a Forfeit button", qw.forfeit_button != null and qw.forfeit_button.is_visible_in_tree(),
		"%s" % [ql["detail"]], ["quest:" + QUEST])
	await d.screenshot("forfeit_button")

	# --- Cancel (mouse), then Delete and Esc (keys): nothing changes ---------------------------------------------------
	var before := d.character().quests.to_dict()
	var r := await d.click(qw.forfeit_button)
	await d.frames(2)
	d.check("clicking Forfeit asks first", bool(r["ok"]) and prompt.is_open() and d.character().quests.status(QUEST) == QuestLog.IN_PROGRESS,
		"%s; prompt %s: '%s'" % [r["why"], prompt.is_open(), prompt.message_label.text])
	d.check("the question names the quest and who offers it again", prompt.message_label.text.contains(k.qname(QUEST))
		and prompt.message_label.text.contains("from Heena"), prompt.message_label.text)
	d.check("the question is modal (the player stands still)", bool(d.state().get("modal", false)), str(d.state().get("modal")))
	await d.screenshot("forfeit_prompt")
	r = await d.click(prompt.cancel_button)
	await d.frames(2)
	d.check("Cancel closes the question and changes nothing", bool(r["ok"]) and not prompt.is_open()
		and d.character().quests.to_dict() == before and forfeited.is_empty() and qw.is_open(),
		"%s; prompt %s, status %s, forfeited %s" % [r["why"], prompt.is_open(), d.character().quests.status(QUEST), forfeited])
	await d.tap_key(KEY_DELETE)
	await d.frames(2)
	d.check("Delete asks too (keyboard)", prompt.is_open(), "")
	d.check("Cancel holds the keyboard focus", prompt.cancel_button.has_focus(), "")
	await d.tap_key(KEY_ESCAPE)
	await d.frames(2)
	d.check("Esc cancels and leaves the Quest Log open", not prompt.is_open() and qw.is_open()
		and d.character().quests.to_dict() == before and forfeited.is_empty(), "prompt %s, log %s" % [prompt.is_open(), qw.is_open()])

	# --- Forfeit (mouse) ----------------------------------------------------------------------------------------------
	var clock0 := k.log_clock()
	await d.click(qw.forfeit_button)
	await d.frames(2)
	r = await d.click(prompt.confirm_button)
	await d.frames(3)
	d.check("clicking Forfeit in the question forfeits %s" % k.qname(QUEST), bool(r["ok"]) and not prompt.is_open()
		and d.character().quests.status(QUEST) == QuestLog.NOT_STARTED and forfeited == [QUEST],
		"%s; status %s, quest_forfeited %s" % [r["why"], d.character().quests.status(QUEST), forfeited], ["quest:" + QUEST])
	d.check("the HUD logs 'Quest forfeited: %s'" % k.qname(QUEST), k.log_since(clock0).has("Quest forfeited: %s" % k.qname(QUEST)),
		str(k.log_since(clock0)))
	d.check("the Quest Log updates: nothing in progress, no Forfeit button", qw.entries.is_empty() and qw.forfeit_button == null
		and String((qw.tab_buttons[MisoQuestWindow.TAB_IN_PROGRESS] as Button).text).contains("(0)"),
		String((qw.tab_buttons[MisoQuestWindow.TAB_IN_PROGRESS] as Button).text))
	avail = await k.quest_window(QUEST, MisoQuestWindow.TAB_AVAILABLE)
	d.check("%s is listed under Available again" % k.qname(QUEST), bool(avail["listed"]), str(avail["list"]))
	d.check("the player has the keyboard back", not bool(d.state().get("modal", true)), str(d.state().get("modal")))
	await d.screenshot("forfeited")
	await d.close_window("quests")

	# --- Heena offers it again ----------------------------------------------------------------------------------------
	await _accept_from_heena("again")


## Talks to Heena on foot and accepts 1000 with the dialogue's keys. True when it is in progress.
func _accept_from_heena(when: String) -> bool:
	var mk: Dictionary = await k.marker(HEENA)
	d.check("Heena's marker shows the quest is available (%s)" % when, String(mk.get("state", "")) == "available", str(mk))
	var v: Dictionary = await k.talk(HEENA)
	if not d.check("Heena can be talked to on foot (%s)" % when, bool(v.get("open", false)), String(v.get("why", ""))):
		return false
	var conv: Dictionary = await k.converse({QUEST: "accept"})
	return d.check("%s accepted from Heena (%s)" % [k.qname(QUEST), when],
		d.character().quests.status(QUEST) == QuestLog.IN_PROGRESS, str(conv["pages"]), ["quest:" + QUEST])
