extends TestCase
## PlaytestKit's pure parts (docs/runtime/PLAYTEST_HARNESS.md "PlaytestKit"): the quiz answer key read from the
## canonical quest records (the correct choice by correct_choice_index, the wrong-answer lines paired in choice order),
## travel over the canonical portals (the 000000030 -> 000000040 link is one-way), the dialogue node parser, the bag
## bookkeeping the reward checks use, the row readers, unstick()'s push directions and the monster pick of the walks
## into monsters. The kit's live helpers are checked in the real game by the `kit` scenario.

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


func test_quickslot_keys_read_both_save_shapes() -> void:
	# Iteration Two saves bind a bare item id; contract C3 binds {"kind": "item" | "skill", "id"}.
	var qs := {"1": "270", "2": {"kind": "item", "id": "237"}, "3": {"kind": "skill", "id": "0001000"}}
	assert_eq(PlaytestKit.quickslot_key(qs, "item", "270"), "1", "a bare item id")
	assert_eq(PlaytestKit.quickslot_key(qs, "item", "237"), "2", "a C3 item entry")
	assert_eq(PlaytestKit.quickslot_key(qs, "skill", "0001000"), "3", "a C3 skill entry (Three Snails)")
	assert_eq(PlaytestKit.quickslot_key(qs, "skill", "270"), "", "an item is not a skill")
	assert_eq(PlaytestKit.quickslot_key(qs, "item", "0001000"), "", "a skill is not an item")
	assert_eq(PlaytestKit.quickslot_key({}, "skill", "0001001"), "", "nothing bound")


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
	# Item tooltip rows: the texts in order, empty rows (spacers) left out.
	var tip := [{"text": "Egg"}, {"text": ""}, {"text": "Recovers 50 HP", "tone": "good"}, {"tone": "dim"}]
	assert_eq(PlaytestKit.row_texts(tip), PackedStringArray(["Egg", "Recovers 50 HP"]))
	assert_true(PlaytestKit.row_contains(tip, "50 HP"), "a row contains the needle")
	assert_false(PlaytestKit.row_contains(tip, "Sells for"), "no row does")
	assert_eq(PlaytestKit.flat_m(Vector3(0, 5, 0), Vector3(3, -2, 4)), 5.0, "only the flat distance counts")


## unstick(): without a target the pushes go round from +X every 45 degrees; with one ("toward", test_b_combat's
## wedges) toward it first, then its sides, straight away, and the diagonals, the front ones first.
func test_unstick_pushes_toward_the_target_first() -> void:
	var ring := PlaytestKit.unstick_dirs(Vector3.ZERO)
	assert_eq(ring.size(), 8)
	assert_true((ring[0] as Vector3).is_equal_approx(Vector3(1, 0, 0)), "from +X: %s" % ring[0])
	assert_true((ring[2] as Vector3).is_equal_approx(Vector3(0, 0, 1)), "90 degrees on: %s" % ring[2])
	var to := PlaytestKit.unstick_dirs(Vector3(0, 3, -2))
	assert_eq(to.size(), 8)
	assert_true((to[0] as Vector3).is_equal_approx(Vector3(0, 0, -1)), "toward it, flat: %s" % to[0])
	assert_true(is_equal_approx(absf((to[1] as Vector3).dot(to[0] as Vector3)), 0.0), "then a side")
	assert_true(is_equal_approx((to[2] as Vector3).dot(to[1] as Vector3), -1.0), "then the other side")
	assert_true((to[3] as Vector3).is_equal_approx(Vector3(0, 0, 1)), "then straight away")
	for k in range(4, 6):
		assert_true(is_equal_approx((to[k] as Vector3).dot(to[0] as Vector3), cos(PI * 0.25)), "front diagonal %d" % k)
	for k in range(6, 8):
		assert_true(is_equal_approx((to[k] as Vector3).dot(to[0] as Vector3), cos(PI * 0.75)), "back diagonal %d" % k)
	var seen := {}
	for v: Vector3 in to:
		assert_true(is_equal_approx(v.length(), 1.0) and is_zero_approx(v.y), "a flat unit push: %s" % v)
		seen[v.snappedf(0.01)] = true
	assert_eq(seen.size(), 8, "eight different directions")


## The monster a walk into monsters goes for (let_monsters_win, test_b_combat's touch probes and fights,
## test_f_death's deaths): the nearest on the player's tier; other tiers only with opts "other_tiers", by flat
## distance plus three times the height difference.
func test_monster_pick_prefers_the_players_tier() -> void:
	var feet := Vector3(0, 0, 0)
	var cands := [
		{"id": "2", "iid": 1, "pos": Vector3(8, 0.4, 0), "debug": false},     # Snail, own tier, 8 m
		{"id": "2", "iid": 2, "pos": Vector3(3, 2.0, 0), "debug": false},     # Snail on a terrace 2 m up, 3 m away
		{"id": "3", "iid": 3, "pos": Vector3(5, 0.0, 0), "debug": false},     # Blue Snail, own tier, 5 m
		{"id": "2", "iid": 4, "pos": Vector3(2, 0.0, 0), "debug": true},      # a console-spawned Snail, 2 m
		{"id": "2", "iid": 5, "pos": Vector3(0, -4.0, 6), "debug": false},    # Snail 4 m below, 6 m away
	]
	assert_eq(PlaytestKit.pick_index(cands, feet, [], {}), 3, "any species: the nearest on the tier, a debug spawn too")
	assert_eq(PlaytestKit.pick_index(cands, feet, ["2"], {}, {"debug_spawns": false}), 0, "no debug spawns: the 8 m Snail")
	assert_eq(PlaytestKit.pick_index(cands, feet, ["2"], {4: true, 1: true}), -1, "no Snail left on the tier")
	assert_eq(PlaytestKit.pick_index(cands, feet, ["2"], {4: true, 1: true}, {"other_tiers": true}), 1,
		"other tiers: 3 + 3 x 2 = 9 beats 6 + 3 x 4 = 18")
	assert_eq(PlaytestKit.pick_index(cands, feet, ["2"], {4: true, 1: true}, {"max_dy_m": 2.5}), 1, "a taller tier band")
	assert_eq(PlaytestKit.pick_index(cands, feet, ["3"], {}, {"max_dist_m": 4.0}), -1, "beyond max_dist_m")
	assert_eq(PlaytestKit.pick_index(cands, feet, ["2"], {}, {"max_dy_m": 0.3, "debug_spawns": false}), -1,
		"a 0.3 m band leaves out the Snail 0.4 m up")
	assert_eq(PlaytestKit.pick_index([], feet, [], {}, {"other_tiers": true}), -1, "no monsters")


## travel_to unsticks a hop whose retry stalled where it began, wherever the hop began: seed 2 of the every-quest set
## (1006, Snail Hunting Ground I) walked 10 m of the trail, stalled at a ledge corner, and the retry stalled at once;
## the old rule measured from the hop's start (9.3 m away), never unstuck, and failed the chain.
func test_a_retry_that_stalled_where_it_began_is_unstuck() -> void:
	var hop_start := Vector3(64.918, 11.0, 227.772)
	var retry_start := Vector3(58.753, 12.0, 234.760)
	var after_retry := Vector3(58.497, 12.0, 234.730)
	assert_true(PlaytestKit.retry_stalled(retry_start, after_retry), "the retry moved 0.26 m: stalled where it began")
	assert_false(PlaytestKit.retry_stalled(hop_start, after_retry), "measured from the hop's start it looks like progress")
	assert_false(PlaytestKit.retry_stalled(retry_start, retry_start + Vector3(1.5, 0.0, 0.0)), "a retry that moved 1.5 m")
	assert_true(PlaytestKit.retry_stalled(retry_start, retry_start + Vector3(0.0, 3.0, 0.0)), "only the flat distance counts")
