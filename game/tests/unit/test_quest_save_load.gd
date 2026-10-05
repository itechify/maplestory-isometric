extends TestCase
## Brief Test E / Phase 21 "Quest: persistence": from a clean new character, accept a quest, progress halfway, save
## through the real save envelope (SaveDocument.build -> JSON text -> SaveDocument.decode, what SaveService writes and
## reads), drop the whole session, reload into a fresh session, finish the quest and verify the exact canonical reward.
## Everything runs through the integration seam (QuestService + NpcInteraction + ItemService on a private Events bus).

const SAVED_AT := "2026-10-04T12:00:00Z"

var _buses: Array = []


func after_each() -> void:
	for b: Variant in _buses:
		(b as Node).free()
	_buses.clear()


## A session = one Events bus + the quest seam + the item seam around `c`.
func _session(c: CharacterState, seed_value: int = 1) -> Dictionary:
	var bus: Node = load("res://scripts/autoload/events.gd").new()
	_buses.append(bus)
	var completed: Array = []
	bus.connect("quest_completed", func(q: String) -> void: completed.append(q))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var service := QuestService.create(bus, db(), c, rng, func() -> float: return 3.0)
	service.attach()
	return {"bus": bus, "service": service, "talk": NpcInteraction.new(service),
		"items": ItemService.new(c, db(), bus), "completed": completed}


func _new_character() -> CharacterState:
	var creation := CharacterFactory.create(CharacterFactory.default_params(db()), db())
	assert_true(creation.ok, "clean new character: %s" % "; ".join(creation.errors))
	return creation.character


## Saves `c` to JSON text and loads it back the way SaveService does. Returns the loaded character (or null).
func _save_and_reload(c: CharacterState) -> CharacterState:
	var doc := SaveDocument.build(c, {}, SAVED_AT, db())
	assert_eq(SaveStore.find_unsupported_value(doc), "", "the quest log is JSON-safe")
	var text := JSON.stringify(doc)
	var raw: Variant = JSON.parse_string(text)
	assert_true(raw is Dictionary, "save text parses")
	var res := SaveDocument.decode(raw, SaveMigrations.new(), db())
	assert_true(res.ok(), "save decodes: %s" % res.message)
	return res.character


func _total_exp(c: CharacterState) -> int:
	return Progression.total_exp_at(c.level, c.exp, db())


func _press_until_closed(talk: NpcInteraction, v: Dictionary) -> void:
	for k in 30:
		if not bool(v.get("open", false)):
			return
		if "next" in v["buttons"]:
			v = talk.press("next")
		elif "ok" in v["buttons"]:
			v = talk.press("ok")
		else:
			return


func test_sams_suggestion_saved_halfway_then_completed_after_reload() -> void:
	var c := _new_character()
	var s := _session(c)
	var talk: NpcInteraction = s["talk"]
	var v := talk.talk("9")
	assert_eq(v["title"], "Sam's Suggestion")
	_press_until_closed(talk, talk.press("yes"))
	assert_eq(c.quests.status("1006"), QuestLog.IN_PROGRESS, "accepted")
	for k in 5:
		(s["bus"] as Node).emit_signal("monster_killed", "2", "000000040")
	assert_eq(c.quests.kills("1006", "2"), 5, "halfway")
	(s["service"] as QuestService).detach()

	# Quit and reload: a fresh character object in a fresh session.
	var c2 := _save_and_reload(c)
	assert_true(c2 != null and c2 != c)
	assert_eq(c2.quests.status("1006"), QuestLog.IN_PROGRESS, "still in progress after reload")
	assert_eq(c2.quests.kills("1006", "2"), 5, "kills survive the save")
	assert_eq(typeof(c2.quests.kills("1006", "2")), TYPE_INT)
	assert_near(c2.quests.started_at("1006"), 3.0, 1e-6, "started_at survives")
	var s2 := _session(c2)
	for k in 6:
		(s2["bus"] as Node).emit_signal("monster_killed", "2", "000000040")
	assert_eq(c2.quests.kills("1006", "2"), 10, "capped at the canonical 10")

	var exp_before := _total_exp(c2)
	var eggs_before := c2.inventory.count("237")
	var mesos_before := c2.mesos
	var fame_before := c2.fame
	var talk2: NpcInteraction = s2["talk"]
	v = talk2.talk("11")
	assert_eq(v["title"], "Sam's Suggestion")
	_press_until_closed(talk2, v)
	assert_eq(c2.quests.status("1006"), QuestLog.COMPLETED)
	assert_eq(s2["completed"], ["1006"])
	assert_eq(_total_exp(c2) - exp_before, 30, "exactly the canonical 30 EXP")
	assert_eq(c2.inventory.count("237") - eggs_before, 3, "exactly the canonical 3 Eggs")
	assert_eq(c2.mesos, mesos_before, "no mesos")
	assert_eq(c2.fame, fame_before, "no fame")

	# The completion itself persists.
	var c3 := _save_and_reload(c2)
	assert_true(c3.quests.is_completed("1006"))
	assert_eq(c3.quests.completions("1006"), 1)
	assert_near(c3.quests.completed_at("1006"), 3.0)
	var s3 := _session(c3)
	assert_false((s3["service"] as QuestService).engine.is_available("1006"), "not offered again")
	assert_true(c3.inventory.count("237") == eggs_before + 3)


func test_rogers_apple_saved_with_the_apple_unused_then_completed_after_reload() -> void:
	var c := _new_character()
	var s := _session(c)
	var talk: NpcInteraction = s["talk"]
	var apples_before := c.inventory.count("235")
	var v := talk.talk("3")
	assert_eq(v["title"], "Roger's Apple")
	_press_until_closed(talk, talk.press("yes"))
	assert_eq(c.quests.status("1002"), QuestLog.IN_PROGRESS)
	assert_eq(c.inventory.count("235") - apples_before, 1, "Roger hands over one apple (adaptation)")
	(s["service"] as QuestService).detach()

	var c2 := _save_and_reload(c)
	assert_eq(c2.quests.status("1002"), QuestLog.IN_PROGRESS)
	assert_eq(c2.quests.uses("1002", "235"), 0)
	assert_eq(c2.inventory.count("235"), apples_before + 1, "the apple survives the save")
	var s2 := _session(c2)
	var talk2: NpcInteraction = s2["talk"]
	# Talking before eating: Roger's canonical "If you don't have the items yet" line, quest unchanged.
	v = talk2.talk("3")
	assert_true(String(v["text"]).begins_with("Eat the Roger's Apple I gave you"))
	talk2.close()
	assert_eq(c2.quests.status("1002"), QuestLog.IN_PROGRESS)

	# Eat it through the real consumable path (ItemService emits item_used on the bus).
	var exp_before := _total_exp(c2)
	var mesos_before := c2.mesos
	var used := (s2["items"] as ItemService).use_item("235")
	assert_true(bool(used["ok"]), "the apple is usable: %s" % used.get("code"))
	assert_eq(c2.quests.uses("1002", "235"), 1, "item_used reached the quest")
	v = talk2.talk("3")
	assert_eq(c2.quests.status("1002"), QuestLog.COMPLETED, "use the apple, then talk to Roger")
	assert_eq(s2["completed"], ["1002"])
	assert_eq(_total_exp(c2), exp_before, "canonical 0 EXP")
	assert_eq(c2.mesos, mesos_before, "canonical 0 mesos")
	assert_eq(c2.inventory.count("235"), apples_before, "no item reward, the apple was eaten")
	assert_true(_save_and_reload(c2).quests.is_completed("1002"))
