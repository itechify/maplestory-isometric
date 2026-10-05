extends TestCase
## Phase 14 "Quest availability persists": what a character may accept is the same before a save and after loading
## it, for every canonical quest and each reason the engine gives (QuestEngine.availability). The interesting case is
## a quest the character has NOT accepted yet: its availability is not stored anywhere, so it must come back from the
## saved prerequisites, level and quest log alone. Saved through the real envelope (SaveDocument.build -> JSON text ->
## SaveDocument.decode, what SaveService writes and reads).

const SAVED_AT := "2026-10-05T12:00:00Z"


func parity_keys() -> Dictionary:
	return {
		"test_not_yet_accepted_quests_stay_available_after_a_reload": ["persistence:quest-availability"],
		"test_every_quests_availability_is_the_same_after_a_reload": ["persistence:quest-availability"],
	}


## A level-3 Beginner who completed 1000 (so 1001 is open and not accepted), has 1006 in progress (so 1009 waits for
## it) and is below 1012's level 5.
func _character() -> CharacterState:
	var creation := CharacterFactory.create(CharacterFactory.default_params(db()), db())
	assert_true(creation.ok, "clean new character: %s" % "; ".join(creation.errors))
	var c := creation.character
	c.level = 3
	c.quests.start("1000", 1.0)
	c.quests.complete("1000", 2.0)
	c.quests.start("1006", 3.0)
	return c


func _reload(c: CharacterState) -> CharacterState:
	var raw: Variant = JSON.parse_string(JSON.stringify(SaveDocument.build(c, {}, SAVED_AT, db())))
	assert_true(raw is Dictionary, "the save text parses")
	var res := SaveDocument.decode(raw, SaveMigrations.new(), db())
	assert_true(res.ok(), "the save decodes: %s" % res.message)
	return res.character


func _availability(c: CharacterState) -> Dictionary:
	var engine := QuestEngine.new(c, db())
	var out := {}
	for qid in engine.catalog.ids():
		var a := engine.availability(qid)
		out[qid] = {"ok": bool(a["ok"]), "reasons": Array(a["reasons"])}
	return out


func test_not_yet_accepted_quests_stay_available_after_a_reload() -> void:
	var before := _character()
	var after := _reload(before)
	var engine := QuestEngine.new(after, db())
	assert_eq(after.quests.status("1001"), QuestLog.NOT_STARTED, "1001 was never accepted: the log has no entry for it")
	assert_false((after.quests.to_dict()["quests"] as Dictionary).has("1001"), "nothing about 1001 is saved")
	assert_true((after.quests.to_dict()["quests"] as Dictionary).has("1000"), "the completed 1000 is saved")
	assert_true(engine.is_available("1001"), "1001 (its prerequisite 1000 completed) is still offered after the reload: %s" % engine.availability("1001"))
	assert_true(engine.is_available("1003"), "a level-1 quest nobody started is still offered: %s" % engine.availability("1003"))
	assert_eq(Array(engine.availability("1000")["reasons"]), ["already_completed"], "the completed 1000 is not offered again")
	assert_eq(Array(engine.availability("1006")["reasons"]), ["in_progress"], "1006 is still in progress, not offered")
	assert_eq(Array(engine.availability("1009")["reasons"]), ["prerequisite:1006"], "1009 still waits for 1006")
	assert_eq(Array(engine.availability("1012")["reasons"]), ["level_too_low"], "1012 still needs level 5")
	assert_true(engine.available_quests().has("1001"), "1001 is among the quests on offer")


func test_every_quests_availability_is_the_same_after_a_reload() -> void:
	var before := _character()
	var a := _availability(before)
	var b := _availability(_reload(before))
	assert_eq(b.keys().size(), db().ids("quests").size(), "every canonical quest is judged")
	for qid in a:
		assert_eq(b[qid], a[qid], "quest %s: availability after the reload" % qid)
	var offered := 0
	for qid in a:
		if bool(a[qid]["ok"]):
			offered += 1
	assert_true(offered >= 2 and offered < a.size(), "a mix of offered and refused quests (%d of %d offered)" % [offered, a.size()])
