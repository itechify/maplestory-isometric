extends TestCase
## QuestService: Events in (kills, item use, pickups, talks, maps) -> engine; engine results -> Events out.

var bus: Node
var events: Array = []
var character: CharacterState
var service: QuestService


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	events = []
	for s: Dictionary in bus.get_script().get_script_signal_list():
		var sname := String(s["name"])
		match (s["args"] as Array).size():
			0:
				bus.connect(sname, func() -> void: events.append([sname]))
			1:
				bus.connect(sname, func(a: Variant) -> void: events.append([sname, a]))
			2:
				bus.connect(sname, func(a: Variant, b: Variant) -> void: events.append([sname, a, b]))
	character = CharacterState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	service = QuestService.create(bus, db(), character, rng, func() -> float: return 5.0)
	service.attach()


func after_each() -> void:
	service.detach()
	bus.free()


func _emitted(sname: String) -> Array:
	var out: Array = []
	for e: Array in events:
		if e[0] == sname:
			out.append(e.slice(1))
	return out


func test_accept_emits_quest_started() -> void:
	var r := service.accept("1006", "9")
	assert_true(bool(r["ok"]))
	assert_eq(_emitted("quest_started"), [["1006"]])
	assert_eq(service.accept("1006", "9")["ok"], false)
	assert_eq(_emitted("quest_started").size(), 1, "a refused accept emits nothing")


func test_monster_kills_progress_and_completion_events() -> void:
	service.accept("1006", "9")
	bus.emit_signal("monster_killed", "3", "000000040")
	assert_eq(_emitted("quest_progressed").size(), 0, "Blue Snail ignored")
	for k in 12:
		bus.emit_signal("monster_killed", "2", "000000040")
	assert_eq(_emitted("quest_progressed").size(), 10, "progress events stop at 10/10")
	events.clear()
	var r := service.complete("1006", {"at_npc_id": "11"})
	assert_true(bool(r["ok"]), "complete: %s" % r.get("reason"))
	assert_has(_emitted("exp_gained"), [30, "quest:1006"])
	assert_has(_emitted("item_gained"), ["237", 3])
	assert_eq(_emitted("quest_completed"), [["1006"]])
	assert_eq(_emitted("inventory_changed").size(), 1, "one inventory_changed per dispatch")
	# 30 EXP at level 1 crosses canonical exp_to_next(1): the level-up is announced like Game.gain_exp() does it.
	assert_true(Progression.exp_to_next(1, db()) <= 30, "precondition: 1006's 30 EXP levels a level-1 character")
	assert_eq(character.level, 2)
	assert_eq(_emitted("leveled_up"), [[2]], "one leveled_up per level")
	assert_eq(_emitted("hp_changed"), [[character.hp, StatCalculator.max_hp(character, db())]],
		"HUD learns the new max HP (and the level-up heal)")
	assert_eq(_emitted("mp_changed"), [[character.mp, StatCalculator.max_mp(character, db())]])
	assert_eq(_emitted("stats_changed").size(), 1)


func test_multi_level_quest_reward_announces_every_level() -> void:
	# 1010 (100 EXP) for a level-1 character: Progression carries the excess over several levels.
	for q in ["1006", "1009"]:
		character.quests.start(q, 0.0)
		character.quests.complete(q, 0.0)
	var probe := CharacterState.from_dict(character.to_dict())
	var expect: Dictionary = Progression.gain_exp(probe, 100, db())
	assert_true(int(expect["levels_gained"]) >= 2, "precondition: canonical 100 EXP is at least two levels from level 1")
	assert_true(bool(service.accept("1010", "11")["ok"]))
	bus.emit_signal("monster_killed", "9", "000000050")
	events.clear()
	var r := service.complete("1010", {"at_npc_id": "11"})
	assert_true(bool(r["ok"]), "complete: %s" % r.get("reason"))
	var levels: Array = []
	for lv in range(2, int(expect["new_level"]) + 1):
		levels.append([lv])
	assert_eq(_emitted("leveled_up"), levels, "one leveled_up per level, in order")
	assert_eq(character.level, int(expect["new_level"]))
	assert_eq(_emitted("exp_gained"), [[int(expect["exp_added"]), "quest:1010"]])
	assert_eq(_emitted("hp_changed").size(), 1)
	assert_eq(_emitted("mesos_changed"), [[150, 150]], "canonical 150 mesos")


func test_item_use_and_talk_complete_rogers_apple() -> void:
	service.accept("1002", "3")
	assert_has(_emitted("item_gained"), ["235", 1])
	bus.emit_signal("npc_talked", "3")
	assert_false(character.quests.has_talked("1002", "3"), "talk before eating is not the turn-in")
	character.inventory.remove("235", 1)
	bus.emit_signal("item_used", "235")
	assert_eq(character.quests.uses("1002", "235"), 1)
	bus.emit_signal("npc_talked", "3")
	assert_true(character.quests.has_talked("1002", "3"))
	assert_true(bool(service.complete("1002")["ok"]))
	assert_eq(_emitted("quest_completed"), [["1002"]])


func test_item_pickups_report_collection_progress() -> void:
	character.level = 3
	service.accept("1011", "12")
	events.clear()
	character.inventory.add("349", 1, db())
	bus.emit_signal("item_gained", "349", 1)
	bus.emit_signal("item_gained", "237", 1)
	assert_eq(_emitted("quest_progressed"), [["1011"]])
	bus.emit_signal("item_lost", "349", 1)
	assert_eq(_emitted("quest_progressed").size(), 2)


func test_map_entered_is_wired() -> void:
	# No Maple Island quest has a map_visit objective; the hook must still be connected and harmless.
	service.accept("1006", "9")
	bus.emit_signal("map_entered", "000000050", "000000040")
	assert_eq(_emitted("quest_progressed").size(), 0)


func test_inventory_full_refusal_is_announced() -> void:
	service.accept("1006", "9")
	for k in 10:
		bus.emit_signal("monster_killed", "2", "000000040")
	for k in 2000:
		if character.inventory.add("270", 100, db()) < 100:
			break
	var r := service.complete("1006", {"at_npc_id": "11"})
	assert_eq(r["reason"], "inventory_full")
	assert_eq(_emitted("inventory_full"), [["237"]])
	assert_eq(_emitted("quest_completed").size(), 0)


func test_character_provider_follows_a_loaded_character() -> void:
	var current: Array = [character]
	service.character_provider = func() -> CharacterState: return current[0]
	service.accept("1006", "9")
	bus.emit_signal("monster_killed", "2", "000000040")
	var loaded := CharacterState.from_dict(JSON.parse_string(JSON.stringify(character.to_dict())))
	current[0] = loaded
	bus.emit_signal("monster_killed", "2", "000000040")
	assert_eq(loaded.quests.kills("1006", "2"), 2, "the loaded character keeps counting")
	assert_eq(character.quests.kills("1006", "2"), 1, "the old one is left alone")


func test_detach_stops_listening() -> void:
	service.accept("1006", "9")
	service.detach()
	bus.emit_signal("monster_killed", "2", "000000040")
	assert_eq(character.quests.kills("1006", "2"), 0)
	service.attach()
	service.attach()
	bus.emit_signal("monster_killed", "2", "000000040")
	assert_eq(character.quests.kills("1006", "2"), 1, "attach is idempotent")


func test_forfeit_emits_quest_forfeited() -> void:
	service.accept("1006", "9")
	service.forfeit("1006")
	assert_eq(_emitted("quest_forfeited"), [["1006"]])


func test_debug_commands() -> void:
	var debug: Node = load("res://scripts/autoload/debug_tools.gd").new()
	service.register_debug_commands(debug)
	assert_true("accepted" in String(debug.call("run", "quest_accept 1006")))
	assert_true("monster_kills:2 0/10" in String(debug.call("run", "quest 1006")))
	assert_true("refused" in String(debug.call("run", "quest_complete 1006")))
	assert_eq(String(debug.call("run", "quest_complete 1006 force")), "completed")
	assert_true(character.quests.is_completed("1006"))
	assert_true("1006" in String(debug.call("run", "quests")))
	debug.call("run", "quest_reset 1006")
	assert_eq(character.quests.status("1006"), QuestLog.NOT_STARTED)
	debug.free()


## Contract C6: the canonical requirements these tests prove.
func parity_keys() -> Dictionary:
	return {
		"test_monster_kills_progress_and_completion_events": ["quest:1006"],
		"test_multi_level_quest_reward_announces_every_level": ["quest:1010"],
		"test_item_use_and_talk_complete_rogers_apple": ["quest:1002"],
	}
