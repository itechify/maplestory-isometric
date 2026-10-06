extends TestCase
## Conversations generated from canonical data, driven end to end through NpcInteraction + QuestService on a private
## Events bus: offers, accept / decline, in-progress reminders, turn-ins with rewards, quizzes, the Sera chain with a
## lost item, shops and townsfolk.

var bus: Node
var events: Array = []
var character: CharacterState
var service: QuestService
var talk: NpcInteraction
var shops: Array = []


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	events = []
	for s: Dictionary in bus.get_script().get_script_signal_list():
		_record(String(s["name"]), (s["args"] as Array).size())
	character = CharacterState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	service = QuestService.create(bus, db(), character, rng, func() -> float: return 7.0)
	service.attach()
	talk = NpcInteraction.new(service)
	shops = []
	talk.shop_requested.connect(func(shop_id: String, npc_id: String) -> void: shops.append([shop_id, npc_id]))


func after_each() -> void:
	service.detach()
	bus.free()


func _record(sname: String, arity: int) -> void:
	match arity:
		0:
			bus.connect(sname, func() -> void: events.append([sname]))
		1:
			bus.connect(sname, func(a: Variant) -> void: events.append([sname, a]))
		2:
			bus.connect(sname, func(a: Variant, b: Variant) -> void: events.append([sname, a, b]))
		3:
			bus.connect(sname, func(a: Variant, b: Variant, c: Variant) -> void: events.append([sname, a, b, c]))


func _emitted(sname: String) -> Array:
	var out: Array = []
	for e: Array in events:
		if e[0] == sname:
			out.append(e.slice(1))
	return out


## Presses Next/OK until the conversation closes; returns the texts seen (including the current one).
func _read_to_end(v: Dictionary) -> PackedStringArray:
	var seen := PackedStringArray()
	for k in 30:
		if not bool(v.get("open", false)):
			break
		seen.append(String(v["text"]))
		if "next" in v["buttons"]:
			v = talk.press("next")
		elif "ok" in v["buttons"]:
			v = talk.press("ok")
		else:
			break
	return seen


func _starts(text: String, prefix: String) -> bool:
	return text.begins_with(prefix)


# --- all NPCs ------------------------------------------------------------------------------------------------

func test_every_npc_conversation_validates() -> void:
	var errs := NpcDialogueBuilder.new(db()).validate_all()
	assert_eq(errs.size(), 0, "\n".join(errs))
	for nid in NpcCatalog.new(db()).ids():
		var v := talk.talk(nid)
		assert_true(bool(v["open"]), "npc %s says something" % nid)
		assert_true(not String(v["text"]).is_empty(), "npc %s text" % nid)
		talk.close()


# --- Sam's Suggestion via dialogue ------------------------------------------------------------------------------

func test_sam_offer_accept_reminder_and_mai_turn_in() -> void:
	var v := talk.talk("9")
	assert_eq(v["type"], "yes_no", "1006 has one On accept line: it is the Yes/No prompt")
	assert_eq(v["title"], "Sam's Suggestion")
	assert_eq(v["speaker_name"], "Sam")
	assert_eq(v["portrait"], "npc_9")
	assert_true(_starts(v["text"], "Hello, I'm Sam."))
	var bold_sam := false
	for s: Dictionary in v["segments"]:
		if s["text"] == "Sam" and bool(s["bold"]) and s.get("ref", {}).get("kind") == "npc" and s["ref"]["id"] == "9":
			bold_sam = true
	assert_true(bold_sam, "segments keep bold + npc ref")
	assert_eq(_emitted("npc_talked"), [["9"]])
	assert_eq(_emitted("dialogue_opened"), [["9"]])
	v = talk.press("yes")
	assert_eq(character.quests.status("1006"), QuestLog.IN_PROGRESS)
	assert_eq(_emitted("quest_started"), [["1006"]])
	assert_true(_starts(v["text"], "Mai is one of the very best fighters"))
	var red_snails := false
	for s: Dictionary in v["segments"]:
		if s["text"] == "Snails" and s["color"] == "red":
			red_snails = true
	assert_true(red_snails, "red monster name")
	assert_false("back" in v["buttons"], "no Back across the accept")
	var rest := _read_to_end(v)
	assert_eq(rest.size(), 2)
	assert_eq(_emitted("dialogue_closed"), [["9"]])

	# Back at Sam while in progress: the canonical "wrong_npc" reminder.
	assert_true(_starts(talk.talk("9")["text"], "Have you not gone to Mai yet?"))
	talk.close()
	# At Mai without the kills: "missing_kills".
	assert_true(_starts(talk.talk("11")["text"], "I'm sure I told you to defeat 10 Snails"))
	talk.close()
	# Kills arrive through Events.monster_killed.
	for k in 10:
		bus.emit_signal("monster_killed", "2", "000000040")
	bus.emit_signal("monster_killed", "3", "000000040")
	assert_eq(_emitted("quest_progressed").size(), 10)
	v = talk.talk("11")
	assert_true(_starts(v["text"], "Are you the one that Sam mentioned?"))
	v = talk.press("next")
	assert_eq(character.quests.status("1006"), QuestLog.COMPLETED, "completed on entering the success lines")
	assert_true(_starts(v["text"], "Well, defeating 10 Snails is a piece of cake!"))
	_read_to_end(v)
	assert_eq(character.inventory.count("237"), 3, "3 Eggs")
	assert_has(_emitted("exp_gained"), [30, "quest:1006"])
	assert_has(_emitted("item_gained"), ["237", 3])
	assert_eq(_emitted("quest_completed"), [["1006"]])
	assert_true(_emitted("inventory_changed").size() >= 1)


func test_sam_decline() -> void:
	var v := talk.talk("9")
	v = talk.press("no")
	assert_true(_starts(v["text"], "Trust me. You'll want to prepare yourself"))
	assert_eq(character.quests.status("1006"), QuestLog.NOT_STARTED)
	assert_eq(talk.press("back")["type"], "yes_no", "Back to the question after declining")


func test_mai_turn_in_refused_when_inventory_full() -> void:
	talk.talk("9")
	talk.press("yes")
	talk.close()
	for k in 10:
		bus.emit_signal("monster_killed", "2", "000000040")
	for k in 2000:
		if character.inventory.add("270", 100, db()) < 100:
			break
	var v := talk.talk("11")
	v = talk.press("next")
	assert_eq(v["speaker_kind"], "system")
	assert_eq(v["node_id"], "sys.inventory_full")
	assert_eq(character.quests.status("1006"), QuestLog.IN_PROGRESS)
	assert_eq(_emitted("inventory_full"), [["237"]])
	assert_eq(_emitted("exp_gained").size(), 0)


# --- Roger's Apple via dialogue --------------------------------------------------------------------------------

func test_roger_apple_full_conversation() -> void:
	var v := talk.talk("3")
	assert_eq(v["node_id"], "q1002.offer.0")
	assert_eq(v["type"], "yes_no")
	assert_eq(v["speaker_kind"], "journal", "no canonical On accept: a quest card, not NPC speech")
	assert_eq(v["speaker_name"], "Roger")
	assert_eq(v["title"], "Roger's Apple")
	assert_eq(v["text"], "Talk to Roger.\n\nAccept this quest?",
		"the canonical journal summary, then the generic system prompt (not the item instructions)")
	assert_eq(v["source"], "canonical/quests/1002.json#journal.lines[0] + misostory/dialogue/_system.json#offer_prompt")
	assert_eq(v["buttons"], ["yes", "no"])
	v = talk.press("yes")
	assert_eq(character.quests.status("1002"), QuestLog.IN_PROGRESS)
	assert_eq(character.inventory.count("235"), 1, "apple handed over")
	assert_has(_emitted("item_gained"), ["235", 1])
	assert_eq(v["node_id"], "q1002.brief.0", "after accepting: the canonical instructions")
	assert_eq(v["speaker_kind"], "journal")
	assert_eq(v["title"], "Roger's Apple")
	assert_eq(v["text"], "Press the hotkey I to open your inventory, navigate to the Use tab, and double-click Roger's"
		+ " Apple to consume it. Then, talk to Roger.")
	assert_eq(v["source"], "canonical/quests/1002.json#journal.lines[1]")
	assert_eq(v["buttons"], ["ok"], "no Back across the accept")
	v = talk.press("ok")
	assert_false(bool(v["open"]), "the instructions are the last page")
	v = talk.talk("3")
	assert_true(_starts(v["text"], "Eat the Roger's Apple I gave you"), "stopItem while the apple is unused")
	var apple_ref := false
	for s: Dictionary in v["segments"]:
		if s.get("ref", {}).get("kind") == "item" and s["ref"]["id"] == "235" and bool(s["ref"]["known"]):
			apple_ref = true
	assert_true(apple_ref, "item ref for the UI")
	talk.close()
	# The items system uses the apple and announces it.
	character.inventory.remove("235", 1)
	bus.emit_signal("item_used", "235")
	assert_has(_emitted("quest_progressed"), ["1002"])
	v = talk.talk("3")
	assert_eq(character.quests.status("1002"), QuestLog.COMPLETED, "talking to Roger completes it")
	assert_eq(v["text"], "Was my information helpful? Farewell, my dear Mapler!", "then Roger's after-quest line")
	assert_eq(_emitted("quest_completed"), [["1002"]])
	assert_eq(_emitted("exp_gained").size(), 0, "0 EXP")
	assert_eq(character.exp, 0)
	assert_eq(character.mesos, 0)


func test_roger_offer_declined_then_offered_again() -> void:
	var v := talk.talk("3")
	v = talk.press("no")
	assert_false(bool(v["open"]), "MeowDB has no decline lines for 1002: the chat ends")
	assert_eq(character.quests.status("1002"), QuestLog.NOT_STARTED)
	assert_eq(character.inventory.count("235"), 0, "no apple without accepting")
	v = talk.talk("3")
	assert_eq(v["node_id"], "q1002.offer.0", "the card is offered again")


# --- offers of every quest -------------------------------------------------------------------------------------

## Scans all quests: a quest with canonical "On accept" lines is offered in its NPC's words, and its Yes/No prompt is
## its last canonical line with no MisoStory text; only a quest without them (Maple Island: 1002 alone) is offered as
## a quest card, and the card's text is its journal summary + the system prompt, never its in-progress instructions.
func test_every_offer_is_canonical_speech_or_a_quest_card() -> void:
	var builder := NpcDialogueBuilder.new(db())
	var cards: Array = []
	var catalog := QuestCatalog.new(db())
	for qid in catalog.ids():
		var d := catalog.get_def(qid)
		var g := builder.build(d.start_npc_id)
		var lines := d.section_lines("on_accept").size()
		var last := "q%s.offer.%d" % [qid, maxi(lines - 1, 0)]
		var n := g.node(last)
		assert_eq(n.get("type"), "yes_no", "%s: the offer ends in a Yes/No" % qid)
		assert_false(g.has_node("q%s.offer.%d" % [qid, maxi(lines, 1)]), "%s: no page after the question" % qid)
		var text := String(DialogueText.resolve(n["line"], db())["text"])
		assert_false(text.is_empty(), "%s: the question has text" % qid)
		if lines > 0:
			assert_eq(String(n.get("speaker", "npc")), "npc", "%s: canonical offers are NPC speech" % qid)
			assert_eq(n["line"], {"quest": qid, "section": "on_accept", "line": lines - 1})
			assert_false(text.contains("Accept this quest?"), "%s: no system text in a canonical offer" % qid)
			assert_false(g.has_node("q%s.brief.0" % qid), "%s: canonical accept lines only" % qid)
			continue
		cards.append(qid)
		assert_eq(n.get("speaker"), "journal", "%s: a quest card" % qid)
		assert_eq(n.get("title"), d.name)
		assert_true(text.begins_with(d.journal_lines[0] if not d.journal_lines.is_empty() else d.name), text)
		assert_true(text.ends_with("\n\nAccept this quest?"), text)
		for i in range(1, d.journal_lines.size() - 1):
			assert_false(text.contains(d.journal_lines[i]), "%s: the instructions follow the accept" % qid)
			var brief := g.node("q%s.brief.%d" % [qid, i - 1])
			assert_eq(brief.get("speaker"), "journal")
			assert_eq(brief.get("line"), {"quest": qid, "journal": i})
	assert_eq(cards, ["1002"], "every other Maple Island quest has canonical On accept lines")


func test_sam_offer_has_no_system_text() -> void:
	var v := talk.talk("9")
	assert_eq(v["node_id"], "q1006.offer.0")
	assert_eq(v["speaker_kind"], "npc", "canonical On accept: Sam speaks")
	assert_eq(v["source"], "canonical/quests/1006.json#dialogue.on_accept.lines[0]")
	assert_true(String(v["text"]).ends_with("What do you think?"), "the canonical line is the question: %s" % v["text"])
	v = talk.press("yes")
	assert_eq(v["node_id"], "q1006.accepted.0", "Sam's canonical accept lines, not the journal")
	assert_eq(v["speaker_kind"], "npc")


## A quest added as data with no "On accept" text, started by Robin (8). `journal` = journal lines, `on_accept` =
## MeowDB's on_accept section (null when MeowDB has none).
func _card_quest_talk(journal: Array, on_accept: Variant = null) -> Array:
	var q := {"id": "9995", "name": "Synthetic Errand", "start_npc": {"npc_id": "8", "name": "Robin"},
		"end_npc": {"npc_id": "8", "name": "Robin"}, "min_level": 0, "job_restriction": null,
		"prerequisites": {"quests": []}, "repeatable": false,
		"objectives": {"npc_talk": [{"npc_id": "8", "purpose": "turn_in"}]},
		"rewards": {"exp": 0, "mesos": 0, "fame": 0, "items": [], "random": [], "selection": []},
		"items_given_on_accept": [], "items_removed_on_completion": {"items": []}, "followup_quests": [],
		"next_quest_grants": [], "journal": {"lines": journal},
		"dialogue": {"on_accept": on_accept, "on_completion": null}}
	var d := ContentDB.new()
	d.canonical = db().canonical.duplicate(false)
	var qs: Dictionary = (db().canonical["quests"] as Dictionary).duplicate(false)
	qs["9995"] = q
	d.canonical["quests"] = qs
	d.miso = db().miso
	d.loaded = true
	var c := CharacterState.new()
	var t := NpcInteraction.new(QuestService.create(null, d, c, RandomNumberGenerator.new()))
	var errs := t.graph_for("8").validate(d)
	assert_eq(errs.size(), 0, "\n".join(errs))
	return [t, c]


func test_card_offer_with_two_instruction_lines() -> void:
	var tc := _card_quest_talk(["Robin needs a hand.", "Find the thing.", "Bring it to Robin.", "Robin thanked me."])
	var t: NpcInteraction = tc[0]
	var c: CharacterState = tc[1]
	var v := t.talk("8")
	assert_eq(v["type"], "yes_no")
	assert_eq(v["speaker_kind"], "journal")
	assert_eq(v["text"], "Robin needs a hand.\n\nAccept this quest?", "line 0 is the question, not a middle line")
	v = t.press("yes")
	assert_eq(c.quests.status("9995"), QuestLog.IN_PROGRESS)
	assert_eq(v["node_id"], "q9995.brief.0")
	assert_eq(v["text"], "Find the thing.")
	assert_eq(v["buttons"], ["next"])
	v = t.press("next")
	assert_eq(v["text"], "Bring it to Robin.", "every in-progress line, in order")
	assert_eq(v["buttons"], ["back", "ok"], "Back within the instructions, never across the accept")
	assert_eq(t.press("back")["text"], "Find the thing.")
	t.press("next")
	assert_false(bool(t.press("ok")["open"]))


func test_card_offer_with_a_two_line_journal_ends_after_the_accept() -> void:
	# 2-line journals (1001, 1004, 1008): line 0 is both the start and the in-progress text, so it is not repeated.
	var tc := _card_quest_talk(["Take this to Robin now.", "Robin got it."])
	var t: NpcInteraction = tc[0]
	var v := t.talk("8")
	assert_eq(v["text"], "Take this to Robin now.\n\nAccept this quest?")
	v = t.press("yes")
	assert_false(bool(v["open"]), "nothing left to say")
	assert_eq((tc[1] as CharacterState).quests.status("9995"), QuestLog.IN_PROGRESS)


func test_card_offer_without_a_journal_asks_with_the_quest_name() -> void:
	var tc := _card_quest_talk([])
	var v := (tc[0] as NpcInteraction).talk("8")
	assert_eq(v["text"], "Synthetic Errand\n\nAccept this quest?")
	assert_eq(v["source"], "canonical/quests/9995.json#name + misostory/dialogue/_system.json#offer_prompt")


func test_card_offer_keeps_canonical_accept_and_decline_lines() -> void:
	# MeowDB could have accept / decline branches without main On accept lines: those canonical lines win.
	var oa := {"lines": [], "branches": [{"state": "accepted", "lines": [{"text": "Off you go."}]},
		{"state": "declined", "lines": [{"text": "Maybe later."}]}]}
	var tc := _card_quest_talk(["Robin needs a hand.", "Find the thing.", "Robin thanked me."], oa)
	var t: NpcInteraction = tc[0]
	var v := t.talk("8")
	assert_eq(v["speaker_kind"], "journal")
	assert_eq(t.press("no")["text"], "Maybe later.")
	t.close()
	t.talk("8")
	v = t.press("yes")
	assert_eq(v["node_id"], "q9995.accepted.0")
	assert_eq(v["text"], "Off you go.")
	assert_eq(v["speaker_kind"], "npc")
	assert_false(t.graph_for("8").has_node("q9995.brief.0"), "the canonical accept lines replace the journal brief")


# --- Rain's quizzes --------------------------------------------------------------------------------------------

func test_rain_quiz_1013_wrong_and_right() -> void:
	character.level = 5
	var v := talk.talk("19")
	assert_true(_starts(v["text"], "Hello! How're you liking Maple World so far?"), "offer: %s" % v)
	v = talk.press("yes")
	assert_eq(_read_to_end(v).size(), 5, "five accepted lines")
	v = talk.talk("19")
	assert_eq(v["type"], "menu")
	assert_eq(v["text"], "What key should you press in front of a ladder or rope to hang from it?")
	assert_eq(v["choices"].size(), 4)
	assert_eq(v["choices"][2]["text"], "up arrow key")
	v = talk.choose(0)
	assert_true(_starts(v["text"], "The left arrow key is for moving left."), "wrong answer 1")
	assert_eq(character.quests.status("1013"), QuestLog.IN_PROGRESS)
	assert_false("back" in v["buttons"])
	_read_to_end(v)
	v = talk.talk("19")
	v = talk.choose(3)
	assert_true(_starts(v["text"], "Huh? The down arrow key is used to crouch"), "wrong answers pair in order")
	_read_to_end(v)
	v = talk.talk("19")
	v = talk.choose(2)
	assert_true(_starts(v["text"], "That's right! If you press the up arrow"), "right answer: %s" % v)
	assert_eq(character.quests.status("1013"), QuestLog.COMPLETED)
	assert_has(_emitted("exp_gained"), [20, "quest:1013"])
	_read_to_end(v)
	# Next quiz is offered at once (no decline branch in MeowDB for quizzes 2-7: Yes/No on the main line).
	v = talk.talk("19")
	assert_eq(v["type"], "yes_no")
	assert_eq(v["title"], "Rain's Maple Quiz 2")


func test_rain_quiz_1018_inferred_answer() -> void:
	character.level = 5
	for q in ["1013", "1014", "1015", "1016", "1017"]:
		character.quests.start(q, 0.0)
		character.quests.complete(q, 0.0)
	talk.talk("19")
	talk.press("yes")
	talk.close()
	var v := talk.talk("19")
	assert_eq(v["choices"].size(), 3)
	assert_eq(v["choices"][2]["text"], "5 points", "reconstructed third option")
	v = talk.choose(1)
	assert_eq(v["text"], "Nope, not 2 points. Think again.")
	talk.close()
	v = talk.talk("19")
	v = talk.choose(2)
	assert_true(_starts(v["text"], "That's right. You get 5 AP with each level"))
	assert_eq(character.quests.status("1018"), QuestLog.COMPLETED)


## Rain's quiz 4 (1016) tells the player to sit on chairs and benches around the map; MisoStory has no map seats.
## Its canonical wrong-answer and right-answer lines stay exactly as MeowDB has them, and each is followed by the
## marked [MisoStory] system page about X and owned chairs (misostory/dialogue/19.json).
func test_rain_quiz_1016_keeps_its_lines_and_adds_the_chair_hint() -> void:
	character.level = 5
	for q in ["1013", "1014", "1015"]:
		character.quests.start(q, 0.0)
		character.quests.complete(q, 0.0)
	talk.talk("19")
	talk.press("yes")
	talk.close()
	var quiz: Dictionary = db().quest("1016")["dialogue"]["on_completion"]["quiz"]
	var v := talk.talk("19")
	v = talk.choose(0)
	assert_eq(v["text"], String(quiz["wrong_answer_responses"][0]["text"]), "the canonical wrong-answer line, unchanged")
	v = talk.press("next")
	assert_true(String(v.get("text", "")).begins_with("[MisoStory] Press X to sit on a chair you own"), "then the hint: %s"
		% v.get("text", ""))
	talk.close()
	assert_true(character.quests.is_in_progress("1016"), "a wrong answer leaves the quiz in progress")
	v = talk.talk("19")
	v = talk.choose(int(quiz["correct_choice_index"]))
	assert_eq(v["text"], String(quiz["correct_answer_response"]["text"]), "the canonical right-answer line, unchanged")
	v = talk.press("next")
	assert_true(String(v.get("text", "")).begins_with("[MisoStory] Press X"), "then the hint: %s" % v.get("text", ""))
	assert_eq(character.quests.status("1016"), QuestLog.COMPLETED)
	talk.close()


# --- Heena / Sera chain with a lost mirror ---------------------------------------------------------------------

func test_heena_sera_chain_with_lost_mirror() -> void:
	var v := talk.talk("1")
	assert_eq(v["title"], "Borrowing Sera's Mirror")
	var pages := 1
	var hints := 0
	while v["type"] == "say":
		v = talk.press("next")
		pages += 1
		hints += 1 if String(v.get("text", "")).begins_with("[MisoStory]") else 0
	assert_eq(pages, 5, "four On accept lines, the last is the Yes/No, and the MisoStory controls page after line 1 "
		+ "(misostory/dialogue/1.json)")
	assert_eq(hints, 1, "one marked [MisoStory] page")
	v = talk.press("yes")
	assert_true(_starts(v["text"], "Thank you. Sera is on the hill to the east"))
	_read_to_end(v)
	assert_true(_starts(talk.talk("1")["text"], "Haven't met up with Sera yet?"), "Heena's reminder")
	talk.close()
	# Sera: 1000 completes silently (no completion text in MeowDB) and flows into her 1001 offer.
	v = talk.talk("2")
	assert_eq(character.quests.status("1000"), QuestLog.COMPLETED)
	assert_true(_starts(v["text"], "How am I going to hang all these up?"))
	assert_eq(v["title"], "Bringing a Mirror to Heena")
	v = talk.press("next")
	assert_eq(v["type"], "yes_no")
	v = talk.press("yes")
	assert_false(bool(v["open"]))
	assert_eq(character.inventory.count("438"), 1, "Sera's Mirror once")
	# Lose the mirror: Sera re-issues it with her canonical "lost" lines.
	character.inventory.remove("438", 1)
	v = talk.talk("2")
	assert_true(_starts(v["text"], "How am I going to hang all these up?"))
	_read_to_end(v)
	assert_eq(character.inventory.count("438"), 1, "mirror re-issued")
	# With the mirror, Sera only reminds.
	assert_true(_starts(talk.talk("2")["text"], "It looks like you haven't delivered the mirror to Heena yet."))
	talk.close()
	v = talk.talk("1")
	assert_true(_starts(v["text"], "Oh wow! You brought Sera's mirror!"))
	v = talk.press("next")
	assert_true(_starts(v["text"], "If you go right, you will see a shiny aura."))
	assert_eq(character.quests.status("1001"), QuestLog.COMPLETED)
	assert_eq(character.inventory.count("438"), 0, "mirror handed in")
	assert_has(_emitted("exp_gained"), [2, "quest:1001"])
	_read_to_end(v)
	assert_eq(talk.talk("1")["text"], "Now I can examine my face with this mirror. Phew! Not sunburnt.", "Heena's after-quest line")


# --- Pio's live counters (1012) --------------------------------------------------------------------------------

func test_pio_accept_line_shows_live_item_counts() -> void:
	character.level = 5
	character.inventory.add("441", 2, db())
	var v := talk.talk("18")
	assert_eq(v["title"], "Pio's Collecting Recycled Goods")
	v = talk.press("yes")
	assert_eq(character.quests.status("1012"), QuestLog.IN_PROGRESS)
	v = talk.press("next")
	assert_eq(v["node_id"], "q1012.accepted.1")
	assert_true(String(v["text"]).contains("Rusty Screw 2/3"), "live count of Rusty Screws: %s" % v["text"])
	assert_true(String(v["text"]).contains("Old Wooden Board 0/3"), "none held yet")
	assert_eq(v["segments"][11]["text"], "2")
	assert_true(bool(v["segments"][11]["bold"]), "styling kept")
	assert_eq(v["source"], "canonical/quests/1012.json#dialogue.on_accept.branches[accepted].lines[1]")
	character.inventory.add("442", 3, db())
	assert_true(String(talk.view()["text"]).contains("Old Wooden Board 3/3"), "evaluated live on every view")


# --- a quest added as data only: quiz + selection reward --------------------------------------------------------

func test_quiz_with_selection_reward_is_completable_from_data_alone() -> void:
	var q := {"id": "9996", "name": "Synthetic Quiz", "start_npc": {"npc_id": "8", "name": "Robin"},
		"end_npc": {"npc_id": "8", "name": "Robin"}, "min_level": 0, "job_restriction": null,
		"prerequisites": {"quests": []}, "repeatable": false,
		"objectives": {"npc_talk": [{"npc_id": "8", "purpose": "turn_in"}], "other": [{"type": "quiz"}]},
		"rewards": {"exp": 5, "mesos": 0, "fame": 0, "items": [], "random": [],
			"selection": [{"job_name": "Any Class", "items": [{"item_id": "558", "count": 1}, {"item_id": "559", "count": 1}]}]},
		"items_given_on_accept": [], "items_removed_on_completion": {"items": []}, "followup_quests": [],
		"next_quest_grants": [], "journal": {"lines": ["a", "b", "c"]},
		"dialogue": {"on_accept": null, "on_completion": {"lines": [{"text": "Main line"}],
			"branches": [{"state": "ready", "lines": [{"text": "Thanks!"}]}],
			"quiz": {"question": {"text": "Q?"}, "choices": [{"text": "A"}, {"text": "B"}], "correct_choice_index": 1,
				"wrong_answer_responses": [{"text": "Not A."}], "correct_answer_response": {"text": "Right!"}}}}}
	var d := ContentDB.new()
	d.canonical = db().canonical.duplicate(false)
	var qs: Dictionary = (db().canonical["quests"] as Dictionary).duplicate(false)
	qs["9996"] = q
	d.canonical["quests"] = qs
	d.miso = db().miso
	d.loaded = true
	var c := CharacterState.new()
	var svc := QuestService.create(null, d, c, RandomNumberGenerator.new())
	var t := NpcInteraction.new(svc)
	assert_eq(t.graph_for("8").validate(d).size(), 0, "\n".join(t.graph_for("8").validate(d)))
	assert_true(bool(svc.accept("9996", "8")["ok"]))
	var v := t.talk("8")
	assert_eq(v["text"], "Main line", "main completion lines come before the quiz")
	v = t.press("next")
	assert_eq(v["type"], "menu")
	assert_eq(v["text"], "Q?")
	v = t.choose(0)
	assert_eq(v["text"], "Not A.")
	assert_eq(c.quests.status("9996"), QuestLog.IN_PROGRESS)
	t.close()
	t.talk("8")
	t.press("next")
	v = t.choose(1)
	assert_eq(v["text"], "Right!", "the right answer is graded without completing")
	assert_eq(c.quests.status("9996"), QuestLog.IN_PROGRESS)
	v = t.press("next")
	assert_eq(v["node_id"], "q9996.select")
	assert_eq(v["choices"].size(), 2)
	v = t.choose(1)
	assert_eq(v["text"], "Thanks!")
	assert_eq(c.quests.status("9996"), QuestLog.COMPLETED)
	assert_eq(c.inventory.count("559"), 1, "the picked reward")
	assert_eq(c.inventory.count("558"), 0)


# --- refs, shops, townsfolk ------------------------------------------------------------------------------------

func test_dialogue_item_refs_use_the_quest_item() -> void:
	var v := talk.talk("7")
	v = talk.press("yes")
	var ids: Array = []
	for s: Dictionary in v["segments"]:
		if s.has("ref") and s["ref"]["kind"] == "item":
			ids.append(s["ref"]["id"])
	assert_eq(ids, ["347"], "MeowDB's dialogue link 2584 is mapped to the quest's item 347")


func test_shop_greeting_then_open_shop() -> void:
	var v := talk.talk("21")
	assert_eq(v["text"], "You definitely need potions to travel.", "greeting chosen by the dialogue override")
	v = talk.press("next")
	assert_false(bool(v["open"]))
	assert_eq(shops, [["maple-road-lucy", "21"]])
	v = talk.talk("16")
	assert_eq(v["text"], "Listen up, everyone! I've got goods here for sale!")


func test_townsfolk_pages_and_back() -> void:
	var v := talk.talk("8")
	assert_eq(v["text"], "Hello! I'm Robin.")
	v = talk.press("next")
	assert_true(_starts(v["text"], "Gathering information before starting your travels"))
	assert_eq(v["buttons"], ["back", "ok"])
	assert_eq(talk.press("back")["text"], "Hello! I'm Robin.")


## Shanks offers the voyage (Iteration Three departure boundary); the whole flow is in test_npc_shanks_departure.gd.
func test_shanks_greets_with_his_voyage_line() -> void:
	var v := talk.talk("15")
	assert_eq(v["text"], "I'll take you anywhere you want to go.", "canonical idle line 1, chosen by dialogue/15.json")
	assert_eq(v["source"], "canonical/npcs/15.json#idle_chatter[1]")
	assert_eq(v["buttons"], ["next"])


## Contract C6: the canonical requirements these tests prove.
func parity_keys() -> Dictionary:
	return {
		"test_sam_offer_accept_reminder_and_mai_turn_in": ["quest:1006", "npc:9", "npc:11"],
		"test_roger_apple_full_conversation": ["quest:1002", "npc:3"],
		"test_rain_quiz_1013_wrong_and_right": ["quest:1013", "npc:19"],
		"test_rain_quiz_1018_inferred_answer": ["quest:1018"],
		"test_heena_sera_chain_with_lost_mirror": ["quest:1000", "quest:1001", "npc:1", "npc:2"],
		"test_pio_accept_line_shows_live_item_counts": ["quest:1012", "npc:18"],
		"test_shop_greeting_then_open_shop": ["shop:maple-road-lucy", "shop:maple-road-pan"],
	}
