extends TestCase
## QuestEngine against the shipped canonical quests: availability, objective tracking, completion, rewards,
## persistence and validation. Assertions that need the real Inventory / Progression skip (with a printed reason)
## only while those modules are still contract stubs; everything else always runs.

const ROGER := "3"
const SAM := "9"
const MAI := "11"
const MARIA := "10"
const LUCAS := "17"
const BIGGS := "12"
const RAIN := "19"


# --- helpers --------------------------------------------------------------------------------------------------

func _engine(level: int = 1, seed_value: int = 1, character: CharacterState = null) -> QuestEngine:
	var c := character if character != null else CharacterState.new()
	if character == null:
		c.level = level
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return QuestEngine.new(c, db(), r, func() -> float: return 42.0)


## True while scripts/core/items/inventory.gd is still the contract stub (add() stores nothing).
func _inventory_is_stub() -> bool:
	var inv := Inventory.new()
	return inv.add("237", 1, db()) != 1 or inv.count("237") != 1


## True while scripts/core/character/progression.gd is still the contract stub.
func _progression_is_stub() -> bool:
	return Progression.exp_to_next(1, db()) <= 0


func _skip(why: String) -> void:
	print("SKIP %s: %s" % [current_test, why])


func _kill(e: QuestEngine, mob_id: String, n: int) -> void:
	for k in n:
		e.on_monster_killed(mob_id)


## Fills an item's tab with full stacks of that item until nothing more fits.
func _fill_tab(c: CharacterState, item_id: String) -> void:
	var stack := maxi(1, int(db().item(item_id).get("max_stack", 1)))
	for k in 2000:
		if c.inventory.add(item_id, stack, db()) < stack:
			break


## A ContentDB sharing the shipped data plus synthetic quests (never mutates the shared db()).
func _db_with_quests(extra: Dictionary) -> ContentDB:
	var d := ContentDB.new()
	d.canonical = db().canonical.duplicate(false)
	var qs: Dictionary = (db().canonical["quests"] as Dictionary).duplicate(false)
	for k: String in extra:
		qs[k] = extra[k]
	d.canonical["quests"] = qs
	d.miso = db().miso
	d.loaded = true
	return d


func _synthetic_quest(qid: String, objectives: Dictionary, rewards: Dictionary) -> Dictionary:
	var obj := {"monster_kills": [], "item_collection": [], "item_usage": [], "npc_talk": [], "map_visit": [], "other": []}
	obj.merge(objectives, true)
	var rw := {"exp": 0, "mesos": 0, "fame": 0, "items": [], "selection": [], "random": []}
	rw.merge(rewards, true)
	return {"id": qid, "name": "Synthetic " + qid, "start_npc": {"npc_id": SAM, "name": "Sam"},
		"end_npc": {"npc_id": SAM, "name": "Sam"}, "min_level": 0, "max_level": null, "job_restriction": null,
		"prerequisites": {"quests": [], "items": [], "fame_min": null, "skills": [], "citizenship": null,
			"acceptance_meso_cost": null, "must_not_have_items": [], "unresolved": []},
		"repeatable": false, "objectives": obj, "rewards": rw, "items_given_on_accept": [],
		"items_removed_on_completion": {"items": []}, "followup_quests": [], "next_quest_grants": [],
		"journal": {"lines": ["a", "b", "c"]}, "dialogue": {"on_accept": null, "on_completion": null}}


# --- data validation ------------------------------------------------------------------------------------------

func test_shipped_quest_data_validates() -> void:
	var errs := QuestCatalog.new(db()).validate()
	assert_eq(errs.size(), 0, "validation errors: %s" % "\n".join(errs))
	assert_eq(QuestCatalog.new(db()).ids().size(), 20, "20 Maple Island quests")


func test_unsupported_other_objective_is_reported_and_never_completes() -> void:
	var d := _db_with_quests({"9999": _synthetic_quest("9999", {"other": [{"type": "escort", "description": "x"}]}, {"exp": 5})})
	var errs := QuestCatalog.new(d).validate()
	var found := false
	for e in errs:
		if "9999" in e and "unsupported 'other'" in e and "escort" in e:
			found = true
	assert_true(found, "validation names the unsupported other type: %s" % "\n".join(errs))
	var c := CharacterState.new()
	var e := QuestEngine.new(c, d, RandomNumberGenerator.new())
	assert_true(bool(e.accept("9999")["ok"]), "accepts")
	e.on_npc_talk(SAM)
	assert_false(e.can_complete("9999", SAM), "unsupported objective never passes")
	var r := e.complete("9999", {"at_npc_id": SAM})
	assert_false(bool(r["ok"]))
	assert_eq(r["reason"], "objectives_incomplete")
	assert_has(r["blockers"], "other:escort")
	assert_eq(e.status("9999"), QuestLog.IN_PROGRESS)


func test_unknown_objective_kind_is_reported() -> void:
	var q := _synthetic_quest("9997", {}, {})
	q["objectives"]["escort_npc"] = [{"npc_id": "1"}]
	var errs := QuestCatalog.new(_db_with_quests({"9997": q})).validate()
	var found := false
	for e in errs:
		if "9997" in e and "unknown objective kind 'escort_npc'" in e:
			found = true
	assert_true(found, "unknown kind reported: %s" % "\n".join(errs))


func test_adaptation_accept_item_for_rogers_apple() -> void:
	var def := QuestCatalog.new(db()).get_def("1002")
	assert_eq(def.accept_items.size(), 1)
	assert_eq(def.accept_items[0]["item_id"], "235")
	assert_eq(def.accept_items[0]["count"], 1)
	assert_eq(def.accept_items[0]["origin"], "misostory")
	assert_true(not String(def.accept_items[0]["reason"]).is_empty(), "adaptation has a reason")
	var miso := db().miso_entity("quests", "1002")
	assert_eq(miso.get("verified"), false, "marked unverified")


func test_next_quest_grants_are_not_granted_twice() -> void:
	var cat := QuestCatalog.new(db())
	assert_eq(cat.get_def("1001").accept_items.size(), 1, "Sera's Mirror once, despite 1000's next_quest_grants")
	assert_eq(cat.get_def("1008").accept_items.size(), 1, "Lucas's Letter once")


# --- availability, chains, gating ------------------------------------------------------------------------------

func test_level_gating() -> void:
	var e := _engine(1)
	var av := e.availability("1007")
	assert_false(bool(av["ok"]), "1007 needs level 2")
	assert_has(av["reasons"], "level_too_low")
	e.character.level = 2
	assert_true(e.is_available("1007"))
	e.character.level = 4
	assert_false(e.is_available("1012"), "1012 needs level 5")
	e.character.level = 5
	assert_true(e.is_available("1012"))


func test_prerequisite_chain_1007_to_1008() -> void:
	var e := _engine(2)
	var av := e.availability("1008")
	assert_false(bool(av["ok"]))
	assert_has(av["reasons"], "prerequisite:1007")
	e.quest_log().start("1007", 0.0)
	assert_false(e.is_available("1008"), "1007 in progress is not enough")
	assert_false(e.is_available("1007"), "already in progress")
	e.quest_log().complete("1007", 1.0)
	assert_true(e.is_available("1008"), "1008 opens after 1007")
	assert_false(e.is_available("1007"), "not repeatable")


func test_job_restriction_uses_class_record() -> void:
	var e := _engine(1)
	assert_true(e.is_available("1000"), "Beginner quest for a beginner")
	e.character.job = "warrior"
	assert_has(e.availability("1000")["reasons"], "wrong_job")
	e.quest_log().start("1000", 0.0)
	e.quest_log().complete("1000", 0.0)
	assert_true(e.is_available("1001"), "1001 has no job restriction (null in MeowDB)")


func test_accept_checks_start_npc() -> void:
	var e := _engine(1)
	assert_eq(e.accept("1006", MAI)["reason"], "wrong_npc")
	assert_eq(e.status("1006"), QuestLog.NOT_STARTED)
	var r := e.accept("1006", SAM)
	assert_true(bool(r["ok"]))
	assert_eq(r["effects"][0], {"type": "quest_started", "quest_id": "1006"})
	assert_near(e.quest_log().started_at("1006"), 42.0, 1e-6, "started_at from the game clock")
	assert_eq(e.accept("1006", SAM)["reason"], "not_available", "cannot accept twice")


# --- Sam's Suggestion (1006) ----------------------------------------------------------------------------------

func test_1006_counts_only_snails_and_only_while_in_progress() -> void:
	var e := _engine(1)
	assert_eq(e.on_monster_killed("2").size(), 0, "kills before accepting do not count")
	assert_true(bool(e.accept("1006", SAM)["ok"]))
	assert_eq(e.on_monster_killed("3").size(), 0, "Blue Snail ignored")
	assert_eq(e.on_monster_killed("1").size(), 0, "Jr. Sentinel ignored")
	for k in 9:
		assert_eq(e.on_monster_killed("2"), PackedStringArray(["1006"]))
	assert_eq(e.quest_log().kills("1006", "2"), 9)
	assert_false(e.can_complete("1006", MAI))
	assert_eq(e.on_monster_killed("2"), PackedStringArray(["1006"]))
	assert_eq(e.on_monster_killed("2").size(), 0, "no progress past 10/10")
	assert_eq(e.quest_log().kills("1006", "2"), 10)
	assert_true(e.can_complete("1006", MAI), "complete at Mai")
	assert_false(e.can_complete("1006", SAM), "not at Sam")
	var rows := e.objective_status("1006")
	var kills_row: Dictionary = rows[0]
	assert_eq(kills_row["key"], "monster_kills:2")
	assert_eq(kills_row["current"], 10)
	assert_eq(kills_row["required"], 10)
	assert_true(bool(kills_row["done"]))


func test_1006_complete_grants_exactly_canonical_rewards() -> void:
	if _inventory_is_stub():
		_skip("Inventory is still a contract stub (scripts/core/items/inventory.gd)")
		return
	var e := _engine(1)
	e.accept("1006", SAM)
	_kill(e, "2", 10)
	var mesos_before := e.character.mesos
	var total_before := Progression.total_exp_at(e.character.level, e.character.exp, db())
	var r := e.complete("1006", {"at_npc_id": MAI})
	assert_true(bool(r["ok"]), "completes: %s" % r.get("reason"))
	assert_eq(r["exp"], 30, "30 EXP per canonical")
	assert_eq(r["items_given"], [{"item_id": "237", "count": 3}], "3 Eggs per canonical")
	assert_eq(e.character.inventory.count("237"), 3)
	assert_eq(e.character.mesos, mesos_before, "no mesos")
	assert_eq(e.status("1006"), QuestLog.COMPLETED)
	assert_near(e.quest_log().completed_at("1006"), 42.0)
	if _progression_is_stub():
		_skip("Progression is still a contract stub; EXP application not asserted")
	else:
		assert_eq(r["exp_added"], 30, "Progression received exactly 30 EXP")
		var total_after := Progression.total_exp_at(e.character.level, e.character.exp, db())
		assert_eq(total_after - total_before, 30, "the character's total EXP grew by exactly 30 (across the level-up)")
	assert_eq(e.character.inventory.count("237"), 3, "exactly 3 Eggs, nothing else")
	assert_eq(e.character.inventory.item_ids(), PackedStringArray(["237"]))
	var types: Array = []
	for fx: Dictionary in r["effects"]:
		types.append(fx["type"])
	assert_has(types, "exp_gained")
	assert_has(types, "item_gained")
	assert_eq(types[types.size() - 1], "quest_completed")
	assert_eq(e.complete("1006", {"at_npc_id": MAI})["reason"], "not_in_progress", "cannot complete twice")


func test_1006_refused_when_inventory_full() -> void:
	if _inventory_is_stub():
		_skip("Inventory is still a contract stub (scripts/core/items/inventory.gd)")
		return
	var e := _engine(1)
	e.accept("1006", SAM)
	_kill(e, "2", 10)
	_fill_tab(e.character, "270")
	assert_false(e.character.inventory.can_add_all([{"item_id": "237", "qty": 3}], db()), "precondition: Use tab full")
	var level_before := e.character.level
	var exp_before := e.character.exp
	var r := e.complete("1006", {"at_npc_id": MAI})
	assert_false(bool(r["ok"]))
	assert_eq(r["reason"], "inventory_full")
	assert_eq(e.status("1006"), QuestLog.IN_PROGRESS, "still in progress")
	assert_eq(e.quest_log().kills("1006", "2"), 10, "kills kept")
	assert_eq(e.character.exp, exp_before, "no EXP granted")
	assert_eq(e.character.level, level_before)
	assert_eq(e.character.inventory.count("237"), 0, "no Eggs")
	e.character.inventory.remove("270", 100)
	assert_true(bool(e.complete("1006", {"at_npc_id": MAI})["ok"]), "completes once a slot is free")


# --- Roger's Apple (1002) -------------------------------------------------------------------------------------

func test_1002_end_to_end() -> void:
	if _inventory_is_stub():
		_skip("Inventory is still a contract stub (scripts/core/items/inventory.gd)")
		return
	var e := _engine(1)
	assert_true(e.is_available("1002"))
	var r := e.accept("1002", ROGER)
	assert_true(bool(r["ok"]), "accept: %s" % r.get("reason"))
	assert_eq(e.character.inventory.count("235"), 1, "Roger hands over one apple (MisoStory adaptation)")
	assert_eq(r["items_given"], [{"item_id": "235", "count": 1}])
	# Talking to Roger before eating: not done, and the turn-in talk is not recorded yet.
	assert_eq(e.on_npc_talk(ROGER).size(), 0)
	assert_false(e.can_complete("1002", ROGER))
	assert_has(e.completion_blockers("1002", ROGER), "item_usage:235")
	# The consumable system removes the apple and emits item_used.
	e.character.inventory.remove("235", 1)
	assert_eq(e.on_item_used("235"), PackedStringArray(["1002"]))
	assert_eq(e.on_item_used("235").size(), 0, "one use is enough")
	assert_eq(e.on_npc_talk(ROGER), PackedStringArray(["1002"]), "then talk to Roger")
	assert_true(e.can_complete("1002"))
	var exp_before := e.character.exp
	var level_before := e.character.level
	var mesos_before := e.character.mesos
	var done := e.complete("1002", {"at_npc_id": ROGER})
	assert_true(bool(done["ok"]), "complete: %s" % done.get("reason"))
	assert_eq(done["exp"], 0, "0 EXP per canonical")
	assert_eq(done["mesos"], 0)
	assert_eq(done["items_given"], [], "no items per canonical")
	assert_eq(e.character.exp, exp_before)
	assert_eq(e.character.level, level_before)
	assert_eq(e.character.mesos, mesos_before)
	assert_true(e.quest_log().is_completed("1002"))
	assert_false(e.is_available("1002"))


func test_1002_usage_before_accept_does_not_count() -> void:
	var e := _engine(1)
	assert_eq(e.on_item_used("235").size(), 0)
	e.quest_log().start("1002", 0.0)
	assert_eq(e.quest_log().uses("1002", "235"), 0)
	assert_false(e.can_complete("1002", ROGER))


# --- collection quests (1011, 1012) and random rewards --------------------------------------------------------

func test_1011_hand_in_removes_items_and_random_reward_is_deterministic() -> void:
	if _inventory_is_stub():
		_skip("Inventory is still a contract stub (scripts/core/items/inventory.gd)")
		return
	var picks: Array = []
	for run in 2:
		var e := _engine(3, 7)
		assert_true(bool(e.accept("1011", BIGGS)["ok"]))
		e.character.inventory.add("349", 12, db())
		assert_eq(e.on_item_gained("349", 12), PackedStringArray(["1011"]))
		assert_false(e.can_complete("1011", BIGGS), "Orange Mushroom Cap still missing")
		e.character.inventory.add("356", 1, db())
		assert_true(e.can_complete("1011", BIGGS))
		var r := e.complete("1011", {"at_npc_id": BIGGS})
		assert_true(bool(r["ok"]), "complete: %s" % r.get("reason"))
		assert_eq(e.character.inventory.count("349"), 2, "10 shells handed in, 2 kept")
		assert_eq(e.character.inventory.count("356"), 0, "cap handed in")
		assert_eq(r["exp"], 70)
		assert_eq((r["random_picks"] as Array).size(), 1, "exactly one random item")
		var pick: String = r["random_picks"][0]["item_id"]
		assert_true(pick in ["558", "559"], "Razor or Fruit Knife")
		assert_eq(e.character.inventory.count(pick), 1)
		picks.append(pick)
	assert_eq(picks[0], picks[1], "same seed, same reward")


func test_random_reward_weights_follow_chance_pct() -> void:
	var e := _engine(3, 12345)
	e.quest_log().start("1011", 0.0)
	var counts := {"558": 0, "559": 0}
	for k in 2000:
		var r := e.resolve_rewards("1011")
		var id: String = r["random_picks"][0]["item_id"]
		counts[id] = int(counts[id]) + 1
	assert_between(float(counts["558"]) / 2000.0, 0.45, 0.55, "50% Razor")
	var hats := {}
	var e2 := _engine(1, 99)
	for k in 700:
		hats[e2.resolve_rewards("1008")["random_picks"][0]["item_id"]] = true
	assert_eq(hats.size(), 7, "all 7 hats reachable")
	var a := _engine(1, 5)
	var b := _engine(1, 5)
	for k in 20:
		assert_eq(a.resolve_rewards("1008")["random_picks"], b.resolve_rewards("1008")["random_picks"], "deterministic per seed")


func test_selection_rewards_need_a_pick() -> void:
	var q := _synthetic_quest("9998", {}, {"selection": [{"job_name": "Any Class", "items": [
		{"item_id": "558", "count": 1}, {"item_id": "559", "count": 1}]}]})
	var d := _db_with_quests({"9998": q})
	var e := QuestEngine.new(CharacterState.new(), d, RandomNumberGenerator.new())
	assert_eq(e.resolve_rewards("9998")["reason"], "selection_required")
	assert_eq(e.resolve_rewards("9998", {"selection_index": 5})["reason"], "invalid_selection")
	var r := e.resolve_rewards("9998", {"selection_index": 1})
	assert_true(bool(r["ok"]))
	assert_eq(r["items"], [{"item_id": "559", "count": 1}])


func test_1012_hand_in_and_rewards() -> void:
	if _inventory_is_stub():
		_skip("Inventory is still a contract stub (scripts/core/items/inventory.gd)")
		return
	var e := _engine(5)
	assert_true(bool(e.accept("1012", "18")["ok"]))
	e.character.inventory.add("441", 3, db())
	e.character.inventory.add("442", 3, db())
	var r := e.complete("1012", {"at_npc_id": "18"})
	assert_true(bool(r["ok"]), "complete: %s" % r.get("reason"))
	assert_eq(r["exp"], 100)
	assert_eq(r["mesos"], 150)
	assert_eq(e.character.mesos, 150)
	assert_eq(r["items_given"], [{"item_id": "522", "count": 1}])
	assert_eq(e.character.inventory.count("441"), 0)
	assert_eq(e.character.inventory.count("442"), 0)


# --- chain 1007 -> 1008 end to end ----------------------------------------------------------------------------

func test_chain_1007_1008_end_to_end() -> void:
	if _inventory_is_stub():
		_skip("Inventory is still a contract stub (scripts/core/items/inventory.gd)")
		return
	var e := _engine(2, 3)
	assert_true(bool(e.accept("1007", MARIA)["ok"]))
	assert_eq(e.character.inventory.count("439"), 1, "Maria's Letter on accept")
	assert_false(e.is_available("1008"))
	var r := e.complete("1007", {"at_npc_id": LUCAS})
	assert_true(bool(r["ok"]), "complete 1007: %s" % r.get("reason"))
	assert_eq(e.character.inventory.count("439"), 0, "letter handed in")
	assert_eq(r["followups_available"], PackedStringArray(["1008"]))
	assert_true(bool(e.accept("1008", LUCAS)["ok"]))
	assert_eq(e.character.inventory.count("440"), 1, "Lucas's Letter once, not twice")
	var r2 := e.complete("1008", {"at_npc_id": MARIA})
	assert_true(bool(r2["ok"]), "complete 1008: %s" % r2.get("reason"))
	assert_eq(r2["exp"], 50)
	assert_eq(e.character.inventory.count("440"), 0)
	var hat: String = r2["random_picks"][0]["item_id"]
	assert_true(hat in ["708", "709", "711", "712", "713", "714", "715"])
	assert_eq(e.character.inventory.count(hat), 1)


func test_lost_letter_is_reissued() -> void:
	if _inventory_is_stub():
		_skip("Inventory is still a contract stub (scripts/core/items/inventory.gd)")
		return
	var e := _engine(2)
	e.accept("1007", MARIA)
	assert_eq(e.lost_items("1007").size(), 0)
	e.character.inventory.remove("439", 1)
	assert_eq(e.lost_items("1007"), [{"item_id": "439", "count": 1}])
	assert_true(bool(e.reissue_lost_items("1007")["ok"]))
	assert_eq(e.character.inventory.count("439"), 1)
	assert_eq(e.reissue_lost_items("1007")["reason"], "nothing_lost")


# --- quizzes --------------------------------------------------------------------------------------------------

func test_quiz_1013_wrong_then_right() -> void:
	var e := _engine(5)
	assert_true(bool(e.accept("1013", RAIN)["ok"]))
	assert_true(e.ready_to_turn_in("1013", RAIN), "quiz is answered in the turn-in talk")
	assert_false(e.can_complete("1013", RAIN), "but not completable before answering")
	var wrong := e.complete("1013", {"at_npc_id": RAIN, "quiz_choice": 0})
	assert_false(bool(wrong["ok"]))
	assert_eq(wrong["reason"], "wrong_answer")
	assert_eq(e.status("1013"), QuestLog.IN_PROGRESS, "a wrong answer changes nothing")
	var right := e.complete("1013", {"at_npc_id": RAIN, "quiz_choice": 2})
	assert_true(bool(right["ok"]), "up arrow key: %s" % right.get("reason"))
	assert_eq(right["exp"], 20)
	assert_eq(right["followups_available"], PackedStringArray(["1014"]))
	if not _progression_is_stub():
		assert_eq(right["exp_added"], 20)


func test_refused_quiz_completion_changes_nothing() -> void:
	if _inventory_is_stub():
		_skip("Inventory is still a contract stub (scripts/core/items/inventory.gd)")
		return
	var e := _engine(5)
	for q in ["1013", "1014", "1015", "1016", "1017", "1018"]:
		e.quest_log().start(q, 0.0)
		e.quest_log().complete(q, 0.0)
	assert_true(bool(e.accept("1019", RAIN)["ok"]))
	var right := QuestJson.i(e.definition("1019").quiz.get("correct_choice_index"), -1)
	_fill_tab(e.character, "270")
	var r := e.complete("1019", {"at_npc_id": RAIN, "quiz_choice": right})
	assert_eq(r["reason"], "inventory_full", "10 Oranges do not fit")
	assert_eq(r["effects"], [], "no effects on a refusal")
	assert_eq(e.quest_log().other_value("1019", "quiz"), null, "the right answer is not kept by a refused completion")
	assert_false(e.can_complete("1019", RAIN))
	assert_eq(e.status("1019"), QuestLog.IN_PROGRESS)
	# An answer earned in an earlier call survives a refused completion.
	assert_true(bool(e.answer_quiz("1019", right)["ok"]))
	assert_eq(e.complete("1019", {"at_npc_id": RAIN})["reason"], "inventory_full")
	assert_eq(e.quest_log().other_value("1019", "quiz"), true)
	e.character.inventory.remove("270", 100)
	var done := e.complete("1019", {"at_npc_id": RAIN, "quiz_choice": right})
	assert_true(bool(done["ok"]), "completes once a slot is free: %s" % done.get("reason"))
	assert_eq(done["exp"], 50)
	assert_eq(done["items_given"], [{"item_id": "239", "count": 10}], "canonical 10 Oranges")


func test_quiz_1018_uses_inferred_answer() -> void:
	var e := _engine(5)
	for q in ["1013", "1014", "1015", "1016", "1017"]:
		e.quest_log().start(q, 0.0)
		e.quest_log().complete(q, 0.0)
	assert_true(bool(e.accept("1018", RAIN)["ok"]))
	assert_eq(e.answer_quiz("1018", 0)["reason"], "wrong_answer")
	assert_eq(e.answer_quiz("1018", 1)["reason"], "wrong_answer")
	assert_true(bool(e.answer_quiz("1018", 2)["ok"]), "5 points (correct_choice_index, inferred per docs)")
	assert_true(e.can_complete("1018", RAIN))


# --- persistence ----------------------------------------------------------------------------------------------

func test_save_mid_quest_then_continue() -> void:
	var e := _engine(1)
	e.accept("1006", SAM)
	_kill(e, "2", 4)
	var saved := JSON.stringify(e.character.to_dict())
	var restored := CharacterState.from_dict(JSON.parse_string(saved))
	var e2 := _engine(1, 1, restored)
	assert_eq(e2.status("1006"), QuestLog.IN_PROGRESS)
	assert_eq(e2.quest_log().kills("1006", "2"), 4)
	assert_near(e2.quest_log().started_at("1006"), 42.0)
	_kill(e2, "2", 6)
	assert_eq(e2.quest_log().kills("1006", "2"), 10)
	assert_true(e2.can_complete("1006", MAI))


# --- forfeit, markers, journal --------------------------------------------------------------------------------

func test_forfeit_resets_and_allows_reaccept() -> void:
	var e := _engine(1)
	e.accept("1006", SAM)
	_kill(e, "2", 3)
	var r := e.forfeit("1006")
	assert_true(bool(r["ok"]))
	assert_eq(r["effects"][r["effects"].size() - 1], {"type": "quest_forfeited", "quest_id": "1006"})
	assert_eq(e.status("1006"), QuestLog.NOT_STARTED)
	assert_true(e.is_available("1006"))
	assert_eq(e.forfeit("1006")["reason"], "not_in_progress")
	e.accept("1006", SAM)
	assert_eq(e.quest_log().kills("1006", "2"), 0, "fresh progress")


func test_forfeit_takes_back_accept_items() -> void:
	if _inventory_is_stub():
		_skip("Inventory is still a contract stub (scripts/core/items/inventory.gd)")
		return
	var e := _engine(1)
	e.accept("1002", ROGER)
	assert_eq(e.character.inventory.count("235"), 1)
	e.forfeit("1002")
	assert_eq(e.character.inventory.count("235"), 0, "apple taken back")
	e.accept("1002", ROGER)
	assert_eq(e.character.inventory.count("235"), 1, "re-accepting gives exactly one again")


func test_npc_markers_follow_quest_state() -> void:
	var e := _engine(1)
	assert_eq(e.npc_marker(SAM), "available")
	assert_eq(e.npc_marker(MAI), "", "1009 needs 1006 and level 3")
	assert_eq(e.npc_marker("8"), "", "Robin has no quests")
	e.accept("1006", SAM)
	assert_eq(e.npc_marker(SAM), "in_progress")
	assert_eq(e.npc_marker(MAI), "in_progress")
	_kill(e, "2", 10)
	assert_eq(e.npc_marker(MAI), "completable")
	var e5 := _engine(5)
	assert_eq(e5.npc_marker(RAIN), "available")
	e5.accept("1013", RAIN)
	assert_eq(e5.npc_marker(RAIN), "completable", "quiz quests are ready to turn in at once")


func test_journal_text_by_state() -> void:
	var e := _engine(1)
	var lines := e.definition("1006").journal_lines
	assert_eq(e.journal_text("1006"), lines[0])
	e.accept("1006", SAM)
	assert_eq(e.journal_text("1006"), lines[1])
	e.quest_log().complete("1006", 0.0)
	assert_eq(e.journal_text("1006"), lines[2])
	var two := e.definition("1001").journal_lines
	assert_eq(two.size(), 2)
	assert_eq(e.journal_text("1001"), two[0])


func test_quest_summary_for_the_quest_window() -> void:
	var e := _engine(1)
	e.accept("1006", SAM)
	_kill(e, "2", 4)
	var s := e.quest_summary("1006")
	assert_eq(s["name"], "Sam's Suggestion")
	assert_eq(s["status"], QuestLog.IN_PROGRESS)
	assert_eq(s["end_npc_name"], "Mai")
	assert_false(bool(s["can_complete"]))
	var rows: Array = s["objectives"]
	assert_eq(rows.size(), 2, "kill Snails + return to Mai")
	assert_eq([rows[0]["name"], rows[0]["current"], rows[0]["required"]], ["Snail", 4, 10])
	assert_eq([rows[1]["kind"], rows[1]["purpose"], rows[1]["done"]], ["npc_talk", "turn_in", false])
	assert_eq(e.quest_summaries().size(), 1)
	assert_eq(e.quest_summaries(PackedStringArray([QuestLog.COMPLETED])).size(), 0)
