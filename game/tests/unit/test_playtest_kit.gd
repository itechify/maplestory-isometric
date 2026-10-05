extends TestCase
## PlaytestKit's pure parts (docs/runtime/PLAYTEST_HARNESS.md "PlaytestKit"): the quiz answer key read from the
## canonical quest records (the correct choice by correct_choice_index, the wrong-answer lines paired in choice order),
## travel over the canonical portals (the 000000030 -> 000000040 link is one-way), the dialogue node parser, and the
## bag bookkeeping the reward checks use.

## Rain's quizzes: the canonical correct choice text (quests/<id>.json dialogue.on_completion.quiz), read here only to
## name the expectation; the resolver must find it through correct_choice_index.
const QUIZ := ["1013", "1014", "1015", "1016", "1017", "1018", "1019"]


func parity_keys() -> Dictionary:
	return {
		"test_quiz_answer_is_the_canonical_correct_choice": ["mechanic:quiz-quests", "quest:1013", "quest:1014", "quest:1015",
			"quest:1016", "quest:1017", "quest:1018", "quest:1019"],
		"test_wrong_answers_pair_with_the_canonical_lines_in_choice_order": ["mechanic:quiz-quests", "quest:1013"],
		"test_portal_path_follows_canonical_portals_and_one_way_links": ["portal:000000030/out00"],
	}


func test_quiz_answer_is_the_canonical_correct_choice() -> void:
	for qid: String in QUIZ:
		var key := PlaytestKit.quiz_answer(db(), qid)
		var z: Dictionary = db().quest(qid)["dialogue"]["on_completion"]["quiz"]
		var idx := int(z["correct_choice_index"])
		assert_true(bool(key["ok"]), "%s has an answer key" % qid)
		assert_eq(int(key["index"]), idx, "%s: the canonical correct_choice_index" % qid)
		assert_eq(String(key["text"]), String((z["choices"] as Array)[idx]["text"]), "%s: its text" % qid)
		assert_eq((key["choices"] as PackedStringArray).size(), (z["choices"] as Array).size(), "%s: every choice" % qid)
		assert_eq((key["wrong"] as Array).size(), (z["choices"] as Array).size() - 1, "%s: every other choice is wrong" % qid)
		assert_true(String(key["question"]) != "", "%s: the question" % qid)
		assert_true(String(key["right_response"]) != "", "%s: the right-answer line" % qid)
	# The one inferred answer (MeowDB marks no choice of 1018): the basis says so.
	assert_eq(String(PlaytestKit.quiz_answer(db(), "1018")["basis"]), "inferred_from_meowdb_responses", "1018's basis")
	assert_eq(String(PlaytestKit.quiz_answer(db(), "1013")["basis"]), "meowdb_marker", "1013's basis")
	assert_false(bool(PlaytestKit.quiz_answer(db(), "1006")["ok"]), "a quest without a quiz has no key")


func test_wrong_answers_pair_with_the_canonical_lines_in_choice_order() -> void:
	var key := PlaytestKit.quiz_answer(db(), "1013")
	var z: Dictionary = db().quest("1013")["dialogue"]["on_completion"]["quiz"]
	var lines: Array = z["wrong_answer_responses"]
	var wrong: Array = key["wrong"]
	# 1013: choices left / right / up (correct) / down; three wrong lines, in that order.
	assert_eq(int((wrong[0] as Dictionary)["index"]), 0)
	assert_eq(int((wrong[2] as Dictionary)["index"]), 3, "the correct choice is skipped")
	for i in wrong.size():
		assert_eq(String((wrong[i] as Dictionary)["response"]), String((lines[i] as Dictionary)["text"]), "wrong %d" % i)
	assert_true(String((wrong[0] as Dictionary)["response"]).contains("left arrow"), "left pairs with the left-arrow line")
	assert_true(String((wrong[2] as Dictionary)["response"]).contains("down arrow"), "down pairs with the down-arrow line")


func test_portal_path_follows_canonical_portals_and_one_way_links() -> void:
	var path := PlaytestKit.portal_path(db(), "000000001", "000001010")
	assert_eq(String(path[0]), "000000001", "starts where it is")
	assert_eq(String(path[path.size() - 1]), "000001010", "ends in Amherst")
	assert_true(path.has("000000030") and path.has("000000040"), "through the one-way link: %s" % [path])
	for i in range(1, path.size()):
		var linked := false
		for p: Dictionary in db().map(String(path[i - 1])).get("portals", []):
			linked = linked or String(p.get("to_map_id", "")) == String(path[i])
		assert_true(linked, "%s -> %s is a canonical portal" % [path[i - 1], path[i]])
	assert_eq(PlaytestKit.portal_path(db(), "000000040", "000000030"), [], "no way back from 000000040 to 000000030")
	assert_eq(PlaytestKit.portal_path(db(), "000000050", "000000050"), ["000000050"], "already there")


func test_node_quest_and_bag_bookkeeping() -> void:
	assert_eq(PlaytestKit.node_quest("q1013.quiz"), "1013")
	assert_eq(PlaytestKit.node_quest("q1006.offer.0"), "1006")
	assert_eq(PlaytestKit.node_quest("talk.after.0"), "", "not a quest node")
	var a := {"237": 3, "438": 1}
	var b := {"237": 6, "713": 1}
	assert_eq(PlaytestKit.bag_delta(a, b, []), {"237": 3, "438": -1, "713": 1})
	assert_eq(PlaytestKit.bag_delta(a, b, [{"item_id": "237"}]), {"438": -1, "713": 1}, "listed items are skipped")
	assert_eq(PlaytestKit.count_in(a, "237"), 3)
	assert_eq(PlaytestKit.count_in(a, "999"), 0)
	assert_true(PlaytestKit.row_has([{"text": "Snail 3/10", "done": false}], "Snail 3/10", false))
	assert_false(PlaytestKit.row_has([{"text": "Snail 3/10", "done": false}], "Snail 3/10", true), "not ticked")
	assert_eq(PlaytestKit.rows_text([{"text": "a", "done": true}, {"text": "b"}]), "a [x]; b")
