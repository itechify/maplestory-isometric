extends TestCase
## QuestLog: per-quest status, progress and timestamps, and its save format (to_dict / from_dict through JSON).


func test_unknown_quest_is_not_started() -> void:
	var ql := QuestLog.new()
	assert_eq(ql.status("1006"), QuestLog.NOT_STARTED)
	assert_false(ql.is_in_progress("1006"))
	assert_false(ql.is_completed("1006"))
	assert_eq(ql.kills("1006", "2"), 0)
	assert_eq(ql.completions("1006"), 0)


func test_start_progress_complete_records_clock() -> void:
	var ql := QuestLog.new()
	ql.start("1006", 12.5)
	assert_eq(ql.status("1006"), QuestLog.IN_PROGRESS)
	assert_near(ql.started_at("1006"), 12.5)
	assert_eq(ql.add_kills("1006", "2", 1, 10), 1)
	assert_eq(ql.add_kills("1006", "2", 20, 10), 10, "kills cap at the required count")
	assert_true(ql.mark_talked("1006", "11"))
	assert_false(ql.mark_talked("1006", "11"), "a talk is recorded once")
	ql.complete("1006", 99.0)
	assert_true(ql.is_completed("1006"))
	assert_near(ql.completed_at("1006"), 99.0)
	assert_eq(ql.completions("1006"), 1)
	assert_eq(ql.completed_ids(), PackedStringArray(["1006"]))
	assert_eq(ql.active_ids().size(), 0)


func test_forfeit_drops_progress() -> void:
	var ql := QuestLog.new()
	ql.start("1009", 1.0)
	ql.add_kills("1009", "3", 4)
	ql.forfeit("1009")
	assert_eq(ql.status("1009"), QuestLog.NOT_STARTED)
	assert_eq(ql.kills("1009", "3"), 0)
	assert_false(ql.entries.has("1009"))


func test_empty_dict_gives_empty_log() -> void:
	var ql := QuestLog.from_dict({})
	assert_eq(ql.entries.size(), 0)
	assert_eq(ql.status("1000"), QuestLog.NOT_STARTED)


func test_json_round_trip_restores_types() -> void:
	var ql := QuestLog.new()
	ql.start("1006", 3.25)
	ql.add_kills("1006", "2", 4, 10)
	ql.start("1002", 4.0)
	ql.add_uses("1002", "235", 1, 1)
	ql.mark_talked("1002", "3")
	ql.start("1013", 5.0)
	ql.set_other("1013", "quiz", true)
	ql.start("1000", 1.0)
	ql.complete("1000", 2.0)
	var text := JSON.stringify(ql.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "JSON parses")
	var back := QuestLog.from_dict(parsed)
	assert_eq(back.status("1006"), QuestLog.IN_PROGRESS)
	assert_eq(typeof(back.kills("1006", "2")), TYPE_INT, "kills come back as int")
	assert_eq(back.kills("1006", "2"), 4)
	assert_eq(back.uses("1002", "235"), 1)
	assert_true(back.has_talked("1002", "3"))
	assert_eq(back.other_value("1013", "quiz"), true)
	assert_true(back.is_completed("1000"))
	assert_eq(typeof(back.completions("1000")), TYPE_INT)
	assert_eq(back.completions("1000"), 1)
	assert_near(back.started_at("1006"), 3.25)
	assert_near(back.completed_at("1000"), 2.0)
	assert_eq(JSON.stringify(back.to_dict()), text, "second round trip is identical")


func test_from_dict_ignores_garbage() -> void:
	var back := QuestLog.from_dict({"quests": {"1": "nope", "2": {"status": "bogus"}, "3": {"status": "in_progress", "progress": null}}})
	assert_false(back.entries.has("1"))
	assert_false(back.entries.has("2"))
	assert_true(back.is_in_progress("3"))
	assert_eq(back.kills("3", "2"), 0)


func test_character_state_composes_quest_log() -> void:
	var c := CharacterState.new()
	c.quests.start("1006", 1.0)
	c.quests.add_kills("1006", "2", 7, 10)
	var c2 := CharacterState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_eq(c2.quests.kills("1006", "2"), 7)
