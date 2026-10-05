extends TestCase
## Shanks (npc 15) and the Southperry departure boundary (Iteration Three adaptation, data/misostory/npcs/15.json):
## the canonical route (Lith Harbor, 300 mesos, level 7, one-way) is offered, level and fare are checked, unfinished
## Maple Island quests are listed under the beginner guide's own advice, and Yes records
## flags.maple_island_departure_ready_at and asks for the end-of-island screen without charging or travelling.

const SHANKS := "15"
const GUIDE_QUOTE := "Shanks at the dock sails you to Lith Harbor for 300 mesos once you reach level 7. The boat is one-way. Hand in every Maple Island quest before you board."
const FLAG := "maple_island_departure_ready_at"

var bus: Node
var character: CharacterState
var service: QuestService
var talk: NpcInteraction
var departures: Array = []


func parity_keys() -> Dictionary:
	return {
		"test_level_6_is_refused": ["npc:15"],
		"test_level_7_with_299_mesos_is_refused": ["npc:15"],
		"test_ready_character_reaches_the_boundary_without_paying": ["npc:15", "mechanic:southperry-departure"],
		"test_unfinished_quests_are_listed_before_the_offer": ["npc:15", "mechanic:southperry-departure"],
	}


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	character = CharacterState.new()
	service = QuestService.create(bus, db(), character, RandomNumberGenerator.new(), func() -> float: return 77.5)
	service.attach()
	talk = NpcInteraction.new(service)
	departures = []
	talk.departure_requested.connect(func(npc_id: String, d: Dictionary) -> void: departures.append([npc_id, d]))


func after_each() -> void:
	service.detach()
	bus.free()


## Completes every Maple Island quest in the log (a character that has done everything).
func _finish_all_quests() -> void:
	for qid in service.engine.catalog.ids():
		character.quests.start(qid, 0.0)
		character.quests.complete(qid, 0.0)


## Talks to Shanks and presses Next through the greeting and the guide page; returns the view after them.
func _past_the_guide() -> Dictionary:
	var v := talk.talk(SHANKS)
	assert_eq(v["text"], "I'll take you anywhere you want to go.", "greeting")
	v = talk.press("next")
	assert_eq(v["text"], GUIDE_QUOTE, "the beginner guide's canonical sentence")
	assert_eq(v["speaker_kind"], "system", "shown as a notice, not as Shanks' speech")
	assert_eq(v["source"], "canonical/npcs/15.json#transport.routes[0].source_quote")
	return talk.press("next")


func test_level_6_is_refused() -> void:
	character.level = 6
	character.mesos = 5000
	_finish_all_quests()
	var v := _past_the_guide()
	assert_eq(v["text"], "You need to be at least level 7 to sail to Lith Harbor.")
	assert_eq(v["buttons"], ["ok"])
	assert_eq(talk.press("ok")["open"], false)
	assert_false(character.flags.has(FLAG))
	assert_eq(departures.size(), 0)


func test_level_7_with_299_mesos_is_refused() -> void:
	character.level = 7
	character.mesos = 299
	_finish_all_quests()
	var v := _past_the_guide()
	assert_eq(v["text"], "The fare to Lith Harbor is 300 mesos. Come back when you have enough.")
	talk.press("ok")
	assert_false(character.flags.has(FLAG))
	assert_eq(character.mesos, 299)
	assert_eq(departures.size(), 0)


func test_ready_character_reaches_the_boundary_without_paying() -> void:
	character.level = 7
	character.mesos = 300
	_finish_all_quests()
	var where_before := character.location.duplicate(true)
	var v := _past_the_guide()
	assert_eq(v["type"], "yes_no", "nothing unfinished: straight to the offer")
	assert_eq(v["text"], "Sail to Lith Harbor? The fare is 300 mesos.")
	assert_true(String(v["source"]).contains("canonical/npcs/15.json#transport.routes[0]"), v["source"])
	v = talk.press("yes")
	assert_false(bool(v["open"]), "the chat ends; the shell shows the boundary screen")
	assert_eq(departures.size(), 1)
	var d: Dictionary = departures[0][1]
	assert_eq(departures[0][0], SHANKS)
	assert_eq(String(d["route"]["to_map_id"]), "010000000")
	assert_eq(String(d["route"]["to_map_name"]), "Lith Harbor")
	assert_eq(int(d["fare_charged"]), 0)
	assert_eq(d["unfinished_quests"], PackedStringArray())
	assert_eq(d["flag"], FLAG)
	assert_near(float(character.flags.get(FLAG, -1.0)), 77.5, 1e-6, "flag = the game clock at boarding")
	assert_eq(character.mesos, 300, "no mesos charged")
	assert_eq(character.location, where_before, "no travel")
	var back := CharacterState.from_dict(JSON.parse_string(JSON.stringify(character.to_dict())))
	assert_near(float(back.flags.get(FLAG, -1.0)), 77.5, 1e-6, "the flag is saved")


func test_unfinished_quests_are_listed_before_the_offer() -> void:
	character.level = 7
	character.mesos = 1000
	# Done: the Sera chain and Roger. In progress: 1006. Everything else untouched.
	for qid in ["1000", "1001", "1002"]:
		character.quests.start(qid, 0.0)
		character.quests.complete(qid, 0.0)
	character.quests.start("1006", 0.0)
	var v := _past_the_guide()
	assert_eq(v["speaker_kind"], "system")
	var text := String(v["text"])
	assert_true(text.begins_with("You still have unfinished Maple Island quests: "), text)
	assert_false(text.contains("{quests}"), "the live list is filled in")
	assert_false(text.contains("Sera's Mirror") or text.contains("Roger's Apple"), "completed quests are not listed")
	for part in ["Nina and Sen's Dinner Menu (2 of 2 left)", "Todd's How-to-Hunt", "Mai's Training (3 of 3 left)",
			"Please bring this letter to Lucas (2 of 2 left)", "Biggs's Collection of Items",
			"Pio's Collecting Recycled Goods", "Rain's Maple Quiz (7 of 7 left)"]:
		assert_true(text.contains(part), "'%s' in %s" % [part, text])
	v = talk.press("next")
	assert_eq(v["type"], "yes_no", "a warning only: boarding is still offered")
	v = talk.press("no")
	assert_false(bool(v["open"]))
	assert_false(character.flags.has(FLAG), "No leaves nothing behind")
	assert_eq(departures.size(), 0)
	# Yes with quests unfinished still reaches the boundary, listing them.
	_past_the_guide()
	talk.press("next")
	talk.press("yes")
	assert_eq(departures.size(), 1)
	var listed: PackedStringArray = departures[0][1]["unfinished_quests"]
	assert_true("1006" in listed and "1019" in listed and not ("1002" in listed), "%s" % listed)
	assert_eq(listed.size(), 17)


func test_boarding_rechecks_the_fare() -> void:
	character.level = 7
	character.mesos = 300
	_finish_all_quests()
	var v := _past_the_guide()
	assert_eq(v["type"], "yes_no")
	character.mesos = 10
	v = talk.press("yes")
	assert_eq(v["text"], "The fare to Lith Harbor is 300 mesos. Come back when you have enough.")
	assert_false(character.flags.has(FLAG))
	assert_eq(departures.size(), 0)


func test_depart_without_a_boundary_is_refused() -> void:
	var d := ContentDB.new()
	d.canonical = db().canonical
	d.miso = db().miso.duplicate(false)
	var npcs: Dictionary = (db().miso["npcs"] as Dictionary).duplicate(false)
	npcs.erase(SHANKS)
	d.miso["npcs"] = npcs
	d.loaded = true
	var c := CharacterState.new()
	c.level = 10
	c.mesos = 1000
	var e := QuestEngine.new(c, d)
	var r := NpcTransport.depart(e, SHANKS, 0)
	assert_eq(r["reason"], "not_built", "travel itself is not implemented")
	assert_eq(NpcTransport.depart(_engine(10, 1000), SHANKS, 3)["reason"], "no_route")


func test_a_boundary_that_charges_takes_the_fare() -> void:
	var d := ContentDB.new()
	d.canonical = db().canonical
	d.miso = db().miso.duplicate(false)
	var npcs: Dictionary = (db().miso["npcs"] as Dictionary).duplicate(false)
	var shanks: Dictionary = (npcs[SHANKS] as Dictionary).duplicate(true)
	shanks["departure"]["charge_fare"] = true
	npcs[SHANKS] = shanks
	d.miso["npcs"] = npcs
	d.loaded = true
	var c := CharacterState.new()
	c.level = 7
	c.mesos = 450
	var r := NpcTransport.depart(QuestEngine.new(c, d), SHANKS, 0)
	assert_true(bool(r["ok"]))
	assert_eq(c.mesos, 150)
	assert_eq(r["effects"][0], {"type": "mesos_changed", "delta": -300, "mesos": 150})


func _engine(level: int, mesos: int) -> QuestEngine:
	var c := CharacterState.new()
	c.level = level
	c.mesos = mesos
	return QuestEngine.new(c, db())
