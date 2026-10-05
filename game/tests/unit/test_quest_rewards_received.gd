extends TestCase
## QuestLog format 2 (contract C3): every completion records what it actually gave (rewards_received: EXP, mesos,
## items, random draws), the record survives a save and a load, a format 1 log loads (its completions marked
## {"recorded": false}), and keys this build does not know survive a load and a save at every level.

const SAM := "9"
const MAI := "11"
const MARIA := "10"
const LUCAS := "17"
const BIGGS := "12"
const PIO := "18"


func parity_keys() -> Dictionary:
	return {
		"test_1006_records_exp_and_eggs": ["quest:1006", "mechanic:quest-rewards-received"],
		"test_1008_random_hat_is_recorded_and_survives_a_save": ["quest:1008", "mechanic:quest-rewards-received"],
		"test_1011_random_weapon_is_recorded_and_survives_a_save": ["quest:1011", "mechanic:quest-rewards-received"],
		"test_1012_records_mesos_and_the_chair": ["quest:1012", "mechanic:quest-rewards-received"],
		"test_format_1_log_loads_with_unrecorded_rewards": ["mechanic:save-migration"],
		"test_unknown_keys_survive_load_and_save": ["mechanic:save-migration"],
	}


func _engine(level: int, seed_value: int = 1, character: CharacterState = null) -> QuestEngine:
	var c := character if character != null else CharacterState.new()
	c.level = maxi(c.level, level)
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return QuestEngine.new(c, db(), r, func() -> float: return 10.0)


## A save round trip of the whole character, as the game writes and reads it.
func _reload(c: CharacterState) -> CharacterState:
	return CharacterState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))


func test_1006_records_exp_and_eggs() -> void:
	var e := _engine(1)
	assert_true(bool(e.accept("1006", SAM)["ok"]))
	for k in 10:
		e.on_monster_killed("2")
	var r := e.complete("1006", {"at_npc_id": MAI})
	assert_true(bool(r["ok"]), "complete: %s" % r.get("reason"))
	var got := e.quest_log().rewards_received("1006")
	assert_eq(got, {"exp": 30, "mesos": 0, "items": [{"item_id": "237", "qty": 3}], "random_picks": []})
	assert_true(e.quest_log().rewards_recorded("1006"))
	var back := _reload(e.character)
	assert_eq(back.quests.rewards_received("1006"), got, "the record survives a save")
	assert_eq(typeof(back.quests.rewards_received("1006")["exp"]), TYPE_INT, "JSON floats come back as ints")


func test_1008_random_hat_is_recorded_and_survives_a_save() -> void:
	var e := _engine(2, 21)
	e.quest_log().start("1007", 0.0)
	e.quest_log().complete("1007", 0.0)
	assert_true(bool(e.accept("1008", LUCAS)["ok"]))
	var r := e.complete("1008", {"at_npc_id": MARIA})
	assert_true(bool(r["ok"]), "complete: %s" % r.get("reason"))
	var hat := String(r["random_picks"][0]["item_id"])
	var got := e.quest_log().rewards_received("1008")
	assert_eq(got["exp"], 50)
	assert_eq(got["random_picks"], [{"group": 0, "item_id": hat, "qty": 1}], "the draw, with its group")
	assert_has(got["items"], {"item_id": hat, "qty": 1}, "the hat is among the items received")
	assert_eq(e.character.inventory.count(hat), 1, "the recorded hat is the one granted")
	var back := _reload(e.character)
	assert_eq(back.quests.rewards_received("1008"), got)
	# The record follows the draw: other seeds draw (and record) other hats.
	var seen := {}
	for s in 40:
		var e2 := _engine(2, 100 + s)
		e2.quest_log().start("1007", 0.0)
		e2.quest_log().complete("1007", 0.0)
		e2.accept("1008", LUCAS)
		var r2 := e2.complete("1008", {"at_npc_id": MARIA})
		var pick := String(e2.quest_log().rewards_received("1008")["random_picks"][0]["item_id"])
		assert_eq(pick, String(r2["random_picks"][0]["item_id"]))
		assert_eq(e2.character.inventory.count(pick), 1)
		seen[pick] = true
	assert_true(seen.size() > 1, "different seeds record different hats: %s" % str(seen.keys()))


func test_1011_random_weapon_is_recorded_and_survives_a_save() -> void:
	var e := _engine(3, 7)
	assert_true(bool(e.accept("1011", BIGGS)["ok"]))
	e.character.inventory.add("349", 10, db())
	e.character.inventory.add("356", 1, db())
	var r := e.complete("1011", {"at_npc_id": BIGGS})
	assert_true(bool(r["ok"]), "complete: %s" % r.get("reason"))
	var weapon := String(r["random_picks"][0]["item_id"])
	assert_true(weapon in ["558", "559"], "Razor or Fruit Knife")
	var got := e.quest_log().rewards_received("1011")
	assert_eq(got["exp"], 70)
	assert_eq(got["random_picks"], [{"group": 0, "item_id": weapon, "qty": 1}])
	var back := _reload(e.character)
	assert_eq(back.quests.rewards_received("1011")["random_picks"][0]["item_id"], weapon,
		"the random weapon received persists")


func test_1012_records_mesos_and_the_chair() -> void:
	var e := _engine(5)
	assert_true(bool(e.accept("1012", PIO)["ok"]))
	e.character.inventory.add("441", 3, db())
	e.character.inventory.add("442", 3, db())
	var r := e.complete("1012", {"at_npc_id": PIO})
	assert_true(bool(r["ok"]), "complete: %s" % r.get("reason"))
	var got := e.quest_log().rewards_received("1012")
	assert_eq(got["exp"], 100)
	assert_eq(got["mesos"], 150)
	assert_eq(got["items"], [{"item_id": "522", "qty": 1}], "The Green Relaxer")


func test_complete_without_rewards_is_unrecorded() -> void:
	var ql := QuestLog.new()
	ql.start("1000", 1.0)
	ql.complete("1000", 2.0)
	assert_eq(ql.rewards_received("1000"), {"recorded": false})
	assert_false(ql.rewards_recorded("1000"))
	assert_eq(ql.rewards_received("1001"), {}, "never completed: no record")


func test_format_1_log_loads_with_unrecorded_rewards() -> void:
	var v1 := {"format": 1, "quests": {
		"1000": {"status": "completed", "progress": {"kills": {}, "used": {}, "talked": ["2"], "visited": [], "other": {}},
			"started_at": 1.0, "completed_at": 2.0, "completions": 1},
		"1006": {"status": "in_progress", "progress": {"kills": {"2": 4.0}, "used": {}, "talked": [], "visited": [],
			"other": {}}, "started_at": 3.0, "completed_at": -1.0, "completions": 0}}}
	var ql := QuestLog.from_dict(JSON.parse_string(JSON.stringify(v1)))
	assert_true(ql.is_completed("1000"))
	assert_eq(ql.rewards_received("1000"), {"recorded": false}, "a format 1 completion is marked unrecorded")
	assert_false(ql.rewards_recorded("1000"))
	assert_false(ql.entries["1006"].has("rewards_received"), "an in-progress entry gets no record")
	assert_eq(ql.kills("1006", "2"), 4)
	var out := ql.to_dict()
	assert_eq(out["format"], QuestLog.FORMAT_VERSION)
	assert_eq(QuestLog.FORMAT_VERSION, 2)
	# A record the save migration already wrote is kept as it is.
	var migrated := {"format": 2, "quests": {"1000": {"status": "completed", "completions": 1,
		"rewards_received": {"recorded": false, "migrated_from": 1}}}}
	assert_eq(QuestLog.from_dict(migrated).rewards_received("1000"), {"recorded": false, "migrated_from": 1})


func test_unknown_keys_survive_load_and_save() -> void:
	var future := {"format": 3, "season": "winter", "quests": {
		"1006": {"status": "in_progress", "hint_seen": true,
			"progress": {"kills": {"2": 2}, "used": {}, "talked": [], "visited": [], "other": {}, "timers": {"a": 1.5}},
			"started_at": 1.0, "completed_at": -1.0, "completions": 0},
		"1011": {"status": "completed", "completions": 1, "started_at": 1.0, "completed_at": 5.0,
			"progress": {"kills": {}, "used": {}, "talked": [], "visited": [], "other": {}},
			"rewards_received": {"exp": 70, "mesos": 0, "items": [{"item_id": "558", "qty": 1, "slot": 3}],
				"random_picks": [{"group": 0, "item_id": "558", "qty": 1}], "fame": 0}}}}
	var ql := QuestLog.from_dict(JSON.parse_string(JSON.stringify(future)))
	assert_eq(ql.kills("1006", "2"), 2, "known progress still reads")
	var out: Dictionary = JSON.parse_string(JSON.stringify(ql.to_dict()))
	assert_eq(out.get("season"), "winter", "an unknown top-level key survives")
	var e1006: Dictionary = out["quests"]["1006"]
	assert_eq(e1006.get("hint_seen"), true, "an unknown entry key survives")
	assert_eq(e1006["progress"].get("timers"), {"a": 1.5}, "an unknown progress key survives")
	var rw: Dictionary = out["quests"]["1011"]["rewards_received"]
	assert_eq(rw.get("fame"), 0.0, "an unknown rewards key survives")
	assert_eq(rw["items"][0].get("slot"), 3.0, "an unknown item key survives")
	var again := QuestLog.from_dict(out)
	assert_eq(JSON.stringify(again.to_dict()), JSON.stringify(ql.to_dict()), "a second round trip is identical")
	# The quest engine still works on a log loaded from a newer save.
	var c := CharacterState.new()
	c.quests = again
	var e := _engine(1, 1, c)
	for k in 8:
		e.on_monster_killed("2")
	assert_true(e.can_complete("1006", MAI))
	assert_true(bool(e.complete("1006", {"at_npc_id": MAI})["ok"]))
	assert_eq(c.quests.to_dict()["quests"]["1006"].get("hint_seen"), true, "unknown keys outlive a completion")
