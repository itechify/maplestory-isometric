extends TestCase
## Every Maple Island quest, data-driven: quest markers through each quest's states (hidden below its level,
## available, in progress, ready to turn in, gone once completed) for all 20 quests; every Rain quiz (1013-1019)
## answered wrong (each wrong choice shows its paired canonical line, the quest stays in progress) and right (the
## canonical correct line, the exact EXP, 1019's Oranges) through the real conversation; quest-specific runs of 1003 ->
## 1004 (Nina and Sen) and 1005 (Todd's How-to-Hunt).

const NINA := "4"
const SEN := "5"
const PETER := "6"
const TODD := "7"
const RAIN := "19"
const QUIZ_EXP := {"1013": 20, "1014": 25, "1015": 30, "1016": 35, "1017": 40, "1018": 45, "1019": 50}

var bus: Node
var events: Array = []
var character: CharacterState
var service: QuestService
var talk: NpcInteraction


func parity_keys() -> Dictionary:
	var markers: Array = []
	for k in 20:
		markers.append("quest:%d" % (1000 + k))
	var quizzes: Array = []
	for q: String in QUIZ_EXP:
		quizzes.append("quest:" + q)
	return {
		"test_markers_follow_every_quest_through_its_states": markers,
		"test_every_rain_quiz_wrong_then_right_through_the_conversation": quizzes,
		"test_1003_then_1004_nina_and_sen": ["quest:1003", "quest:1004"],
		"test_1005_todds_how_to_hunt": ["quest:1005"],
	}


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	events = []
	bus.connect("exp_gained", func(amount: int, source: String) -> void: events.append(["exp_gained", amount, source]))
	bus.connect("item_gained", func(item_id: String, qty: int) -> void: events.append(["item_gained", item_id, qty]))
	bus.connect("item_lost", func(item_id: String, qty: int) -> void: events.append(["item_lost", item_id, qty]))
	character = CharacterState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	service = QuestService.create(bus, db(), character, rng, func() -> float: return 1.0)
	service.attach()
	talk = NpcInteraction.new(service)


func after_each() -> void:
	if talk.is_open():
		talk.close()
	service.detach()
	bus.free()


func _emitted(sname: String) -> Array:
	var out: Array = []
	for e: Array in events:
		if e[0] == sname:
			out.append(e.slice(1))
	return out


## Presses Next/OK until the conversation closes; returns the texts seen.
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


## Presses Next until a Yes/No or a menu shows (or the chat ends).
func _to_question(v: Dictionary) -> Dictionary:
	for k in 30:
		if not bool(v.get("open", false)) or v["type"] in ["yes_no", "menu"]:
			return v
		v = talk.press("next")
	return v


# --- markers for all 20 quests ----------------------------------------------------------------------------------

## Every prerequisite of a quest, transitively.
func _prereqs(cat: QuestCatalog, qid: String) -> PackedStringArray:
	var out := PackedStringArray()
	for p in cat.get_def(qid).prereq_quests:
		for pp in _prereqs(cat, p):
			if not (pp in out):
				out.append(pp)
		if not (p in out):
			out.append(p)
	return out


## The state of `qid` among an NPC's entries ("" when the NPC shows nothing for it).
func _state_at(e: QuestEngine, npc_id: String, qid: String) -> String:
	for en: Dictionary in e.npc_entries(npc_id):
		if en["quest_id"] == qid:
			return String(en["state"])
	return ""


## True when nothing but talking to the end NPC, the quiz and items handed over on accept stand between accepting and
## turning in: worked out from the record, independently of QuestEngine.
func _ready_at_accept(d: QuestDef) -> bool:
	var given := {}
	for a: Dictionary in d.accept_items:
		given[String(a["item_id"])] = int(a["count"])
	for o: Dictionary in d.objectives:
		match String(o["kind"]):
			"npc_talk":
				if o["purpose"] != "turn_in":
					return false
			"other":
				if o["type"] != "quiz":
					return false
			"item_collection":
				if int(given.get(String(o["id"]), 0)) < int(o["count"]):
					return false
			_:
				return false
	return true


func test_markers_follow_every_quest_through_its_states() -> void:
	var cat := QuestCatalog.new(db())
	assert_eq(cat.ids().size(), 20, "the Maple Island quest set")
	for qid in cat.ids():
		var d := cat.get_def(qid)
		var c := CharacterState.new()
		c.level = maxi(1, d.min_level)
		var e := QuestEngine.new(c, db(), RandomNumberGenerator.new(), Callable(), cat)
		for p in _prereqs(cat, qid):
			c.quests.start(p, 0.0)
			c.quests.complete(p, 0.0)
		var at := "quest %s" % qid
		if d.min_level > 1:
			c.level = d.min_level - 1
			assert_eq(_state_at(e, d.start_npc_id, qid), "", "%s: no marker below level %d" % [at, d.min_level])
			c.level = d.min_level
		assert_eq(_state_at(e, d.start_npc_id, qid), "available", at)
		assert_eq(e.npc_marker(d.start_npc_id), "available", "%s: the start NPC shows '!'" % at)
		assert_true(bool(e.accept(qid, d.start_npc_id)["ok"]), "%s accepted" % at)
		var ready := _ready_at_accept(d)
		var end_state := "completable" if ready else "in_progress"
		assert_eq(_state_at(e, d.end_npc_id, qid), end_state, "%s: the turn-in NPC right after accepting" % at)
		assert_eq(e.npc_marker(d.end_npc_id), end_state, "%s: turn-in marker" % at)
		if d.end_npc_id != d.start_npc_id:
			assert_eq(_state_at(e, d.start_npc_id, qid), "in_progress", "%s: '...' at the start NPC" % at)
		# Do the objectives the way the game does: kills, pick-ups, item uses.
		for o: Dictionary in d.objectives:
			match String(o["kind"]):
				"monster_kills":
					for k in int(o["count"]) - 1:
						e.on_monster_killed(String(o["id"]))
					assert_eq(_state_at(e, d.end_npc_id, qid), "in_progress", "%s: one kill short" % at)
					e.on_monster_killed(String(o["id"]))
				"item_collection":
					var short := int(o["count"]) - c.inventory.count(String(o["id"]))
					if short > 0:
						c.inventory.add(String(o["id"]), short, db())
				"item_usage":
					for k in int(o["count"]):
						if c.inventory.count(String(o["id"])) <= 0:
							c.inventory.add(String(o["id"]), 1, db())
						c.inventory.remove(String(o["id"]), 1)
						e.on_item_used(String(o["id"]))
		assert_eq(_state_at(e, d.end_npc_id, qid), "completable", "%s: objectives done" % at)
		assert_eq(e.npc_marker(d.end_npc_id), "completable", "%s: '?' at the turn-in NPC" % at)
		var opts := {"at_npc_id": d.end_npc_id}
		if not d.quiz.is_empty():
			opts["quiz_choice"] = QuestJson.i(d.quiz.get("correct_choice_index"))
		var r := e.complete(qid, opts)
		assert_true(bool(r["ok"]), "%s completes: %s %s" % [at, r.get("reason"), r.get("blockers", "")])
		assert_eq(_state_at(e, d.end_npc_id, qid), "", "%s: no marker once completed" % at)
		assert_eq(_state_at(e, d.start_npc_id, qid), "", "%s: none at the start NPC either" % at)


# --- Rain's quizzes -------------------------------------------------------------------------------------------

func test_every_rain_quiz_wrong_then_right_through_the_conversation() -> void:
	character.level = 5
	var total := 0
	for qid: String in QUIZ_EXP:
		var rec := db().quest(qid)
		var quiz := QuestJson.dict(QuestJson.dict(QuestJson.dict(rec.get("dialogue")).get("on_completion")).get("quiz"))
		var choices := QuestJson.arr(quiz.get("choices"))
		var correct := QuestJson.i(quiz.get("correct_choice_index"))
		var wrong_lines := QuestJson.arr(quiz.get("wrong_answer_responses"))
		var right_text := QuestJson.s(QuestJson.dict(quiz.get("correct_answer_response")).get("text"))
		# Accept at Rain.
		var v := _to_question(talk.talk(RAIN))
		assert_eq(v["type"], "yes_no", "%s offered" % qid)
		assert_eq(v["title"], String(rec.get("name")))
		_read_to_end(talk.press("yes"))
		assert_eq(character.quests.status(qid), QuestLog.IN_PROGRESS, "%s accepted" % qid)
		# Every wrong choice: its paired canonical line, the quest stays in progress, talk again to retry.
		var rank := 0
		for i in choices.size():
			if i == correct:
				continue
			v = _to_question(talk.talk(RAIN))
			assert_eq(v["type"], "menu", "%s: the quiz" % qid)
			assert_eq(v["text"], QuestJson.s(QuestJson.dict(quiz.get("question")).get("text")), "%s question" % qid)
			assert_eq(v["choices"].size(), choices.size())
			v = talk.choose(i)
			var want := QuestJson.s(QuestJson.dict(wrong_lines[mini(rank, wrong_lines.size() - 1)]).get("text"))
			assert_eq(v["text"], want, "%s wrong choice %d shows wrong line %d" % [qid, i, rank])
			assert_eq(character.quests.status(qid), QuestLog.IN_PROGRESS, "%s still in progress after a wrong answer" % qid)
			_read_to_end(v)
			rank += 1
		assert_eq(rank, wrong_lines.size(), "%s: one canonical line per wrong choice" % qid)
		# The right choice.
		events.clear()
		v = _to_question(talk.talk(RAIN))
		v = talk.choose(correct)
		assert_eq(v["text"], right_text, "%s right answer line" % qid)
		assert_eq(character.quests.status(qid), QuestLog.COMPLETED, "%s completed" % qid)
		assert_eq(_emitted("exp_gained"), [[int(QUIZ_EXP[qid]), "quest:" + qid]], "%s EXP" % qid)
		total += int(QUIZ_EXP[qid])
		_read_to_end(v)
	assert_eq(total, 245, "Rain's chain: 245 EXP in all")
	assert_eq(character.inventory.count("239"), 10, "1019: 10 Oranges")
	assert_eq(service.engine.npc_marker(RAIN), "", "Rain has nothing left")


# --- 1003 -> 1004 ----------------------------------------------------------------------------------------------

func test_1003_then_1004_nina_and_sen() -> void:
	var v := _to_question(talk.talk(NINA))
	assert_eq(v["title"], "What Sen wants to eat")
	assert_eq(v["text"], "That's my little brother, Sen. Will you please ask him what he wants for dinner?",
		"the last On accept line is the Yes/No")
	v = talk.press("yes")
	assert_false(bool(v["open"]), "1003 has no accept lines")
	assert_eq(character.quests.status("1003"), QuestLog.IN_PROGRESS)
	# Nina reminds (canonical wrong_npc line) until Sen is asked.
	v = talk.talk(NINA)
	assert_eq(v["text"], "You didn't talk to Sen yet? Please, open your eyes!")
	talk.close()
	# Sen: 1003 completes silently (no completion text), then he asks for 1004 in the same chat.
	v = _to_question(talk.talk(SEN))
	assert_eq(character.quests.status("1003"), QuestLog.COMPLETED, "talking to Sen completes 1003")
	assert_eq(v["title"], "Returning to Nina")
	assert_eq(v["text"], "Please tell my sister I really, really want mushroom soup for dinner!")
	v = talk.press("yes")
	assert_false(bool(v["open"]))
	assert_eq(character.quests.status("1004"), QuestLog.IN_PROGRESS)
	events.clear()
	v = talk.talk(NINA)
	assert_eq(v["text"], "He wants mushroom soup? I guess that's our dinner then. Thanks for helping me out.")
	_read_to_end(v)
	assert_eq(character.quests.status("1004"), QuestLog.COMPLETED)
	assert_eq(_emitted("exp_gained"), [[3, "quest:1004"]], "+3 EXP (canonical)")
	assert_eq(service.engine.npc_marker(NINA), "")
	assert_eq(service.engine.npc_marker(SEN), "")


# --- 1005 ------------------------------------------------------------------------------------------------------

func test_1005_todds_how_to_hunt() -> void:
	var v := talk.talk(TODD)
	assert_eq(v["type"], "yes_no", "one On accept line: the Yes/No")
	v = talk.press("yes")
	assert_true(String(v["text"]).begins_with("Look at your mini map (M)"), "accepted line")
	_read_to_end(v)
	assert_eq(character.quests.status("1005"), QuestLog.IN_PROGRESS)
	# Peter before any kill: the canonical missing-kills line (the main completion lines come only once ready).
	v = talk.talk(PETER)
	assert_true(String(v["text"]).begins_with("Hmm, you should have seen a small Tutorial Jr. Sentinel"), v["text"])
	talk.close()
	# Only Tutorial Jr. Sentinels (mob 1) count, at most 3.
	for k in 5:
		bus.emit_signal("monster_killed", "2", "000000030")
	assert_eq(character.quests.kills("1005", "1"), 0, "Snails do not count")
	for k in 5:
		bus.emit_signal("monster_killed", "1", "000000030")
	assert_eq(character.quests.kills("1005", "1"), 3, "capped at 3")
	# Kills done, Shellpieces missing: the canonical missing-items line.
	character.inventory.add("347", 2, db())
	v = talk.talk(PETER)
	assert_true(String(v["text"]).begins_with("Huh? You're not carrying 3 Jr. Sentinel Shellpiece."), v["text"])
	talk.close()
	character.inventory.add("347", 2, db())
	events.clear()
	v = talk.talk(PETER)
	var seen := _read_to_end(v)
	assert_eq(seen[0], "Are you the one Todd is training? He mentioned you... Let's see if you've trained correctly.")
	assert_true(seen[seen.size() - 1].begins_with("Someday, long after you leave this place"), "the ready line: %s" % seen)
	assert_eq(character.quests.status("1005"), QuestLog.COMPLETED)
	assert_eq(_emitted("exp_gained"), [[10, "quest:1005"]], "+10 EXP (canonical)")
	assert_has(_emitted("item_lost"), ["347", 3], "3 Shellpieces handed in")
	assert_eq(character.inventory.count("347"), 1, "the fourth is kept")
	assert_eq(character.quests.rewards_received("1005"), {"exp": 10, "mesos": 0, "items": [], "random_picks": []})
