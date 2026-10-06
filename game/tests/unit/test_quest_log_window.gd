extends TestCase
## The Quest Log for the complete Maple Island set (brief "Quest Log"): chain progression ("Mai's Training 2/3"), the
## start and turn-in NPCs with their maps, objective quantities, completion state, MeowDB's "Missable" tag, the random
## reward actually received (persisted), and the turn-in wording ("Return to X" only for an NPC already met). Engine
## queries (chain_info, npc_met, quest_summary) and the window itself, on a private events.gd bus.

const HEENA := "1"
const SERA := "2"
const ROGER := "3"
const SAM := "9"
const MAI := "11"
const MARIA := "10"
const LUCAS := "17"
const RAIN := "19"

var bus: Node
var nodes: Array = []
var game: GameState = null


func parity_keys() -> Dictionary:
	return {
		"test_chain_info_for_every_chain": ["quest:1000", "quest:1001", "quest:1003", "quest:1004", "quest:1006",
			"quest:1007", "quest:1008", "quest:1009", "quest:1010", "quest:1013", "quest:1014", "quest:1015",
			"quest:1016", "quest:1017", "quest:1018", "quest:1019"],
		"test_window_shows_mai_training_2_of_3_with_npcs_and_maps": ["quest:1009"],
		"test_window_shows_rain_quiz_4_of_7": ["quest:1016"],
		"test_window_received_random_hat_survives_a_reload": ["quest:1008", "mechanic:quest-rewards-received"],
	}


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()


func after_each() -> void:
	nodes.reverse()
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	game = null
	bus.free()


func _engine(c: CharacterState, content: ContentDB = null, seed_value: int = 1) -> QuestEngine:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return QuestEngine.new(c, content if content != null else db(), r, func() -> float: return 5.0)


func _character(level: int = 1) -> CharacterState:
	var c := CharacterState.new()
	c.level = level
	return c


## Marks quests completed directly in the log (prerequisites of the quest under test).
func _done(c: CharacterState, ids: Array) -> void:
	for q: String in ids:
		c.quests.start(q, 0.0)
		c.quests.complete(q, 0.0)


func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root


## The windows scene on `c`, its quest service on `content` (default: the shipped data).
func _quest_window(c: CharacterState, content: ContentDB = null, seed_value: int = 1) -> MisoQuestWindow:
	var d := content if content != null else db()
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var qs := QuestService.create(bus, d, c, r)
	game = GameState.new()
	game.db = d
	game.event_bus = bus
	game.log_warnings = false
	game.character = c
	game.quests = qs
	qs.attach()
	nodes.append(game)
	var root: MisoWindowsRoot = load("res://scenes/ui/windows.tscn").instantiate()
	root.configure(MisoUiEnv.isolated(c, d, bus, null, game))
	_parent().add_child(root)
	nodes.append(root)
	root.open_window("quests")
	return root.quests


func _has_prefix(ql: MisoQuestWindow, prefix: String) -> bool:
	for t in ql.detail_texts():
		if t.begins_with(prefix):
			return true
	return false


func _texts(ql: MisoQuestWindow) -> String:
	return " | ".join(ql.detail_texts())


func _objective_texts(ql: MisoQuestWindow) -> PackedStringArray:
	var out: PackedStringArray = []
	for r: Dictionary in ql.objective_rows():
		out.append(String(r["text"]))
	return out


# --- engine queries -------------------------------------------------------------------------------------------

func test_chain_info_for_every_chain() -> void:
	var e := _engine(_character())
	var want := {
		"1000": ["Sera's Mirror", 1, 2], "1001": ["Sera's Mirror", 2, 2],
		"1003": ["Nina and Sen's Dinner Menu", 1, 2], "1004": ["Nina and Sen's Dinner Menu", 2, 2],
		"1006": ["Mai's Training", 1, 3], "1009": ["Mai's Training", 2, 3], "1010": ["Mai's Training", 3, 3],
		"1007": ["Please bring this letter to Lucas", 1, 2], "1008": ["Please bring this letter to Lucas", 2, 2],
	}
	for k in 7:
		want[str(1013 + k)] = ["Rain's Maple Quiz", k + 1, 7]
	for qid: String in want:
		var ch := e.chain_info(qid)
		var w: Array = want[qid]
		assert_eq(ch.get("name"), w[0], "chain name of %s" % qid)
		assert_eq(ch.get("position"), w[1], "position of %s" % qid)
		assert_eq(ch.get("total"), w[2], "total of %s" % qid)
		assert_eq((ch.get("steps", []) as Array).size(), w[2], "steps of %s" % qid)
	for qid in ["1002", "1005", "1011", "1012"]:
		assert_eq(e.chain_info(qid), {}, "%s is standalone" % qid)
	assert_eq(MisoQuestWindow.chain_text(e.chain_info("1009")), "Mai's Training 2/3")


func test_chain_steps_follow_quest_state() -> void:
	var c := _character(3)
	var e := _engine(c)
	_done(c, ["1006"])
	assert_true(bool(e.accept("1009", MAI)["ok"]))
	var steps: Array = e.chain_info("1009")["steps"]
	assert_eq(steps[0], {"quest_id": "1006", "name": "Sam's Suggestion", "status": QuestLog.COMPLETED})
	assert_eq(steps[1]["status"], QuestLog.IN_PROGRESS)
	assert_eq(steps[2]["status"], QuestLog.NOT_STARTED)


func test_npc_met_and_turn_in_wording() -> void:
	var c := _character(2)
	var e := _engine(c)
	assert_false(e.npc_met(MAI), "a new Beginner has met nobody through a quest")
	e.accept("1006", SAM)
	assert_true(e.npc_met(SAM), "the start NPC of an accepted quest")
	assert_false(e.npc_met(MAI), "Mai only ends 1006")
	var row := _turn_in_row(e, "1006")
	assert_eq(MisoUiText.objective_text(row), "Talk to Mai", "never met: not 'Return to'")
	e.accept("1002", ROGER)
	assert_eq(MisoUiText.objective_text(_turn_in_row(e, "1002")), "Return to Roger", "Roger gave the quest")
	# The Sera chain: Sera is new for 1000; Heena, who gave 1000, is met for 1001.
	e.accept("1000", HEENA)
	assert_eq(MisoUiText.objective_text(_turn_in_row(e, "1000")), "Talk to Sera")
	assert_true(bool(e.complete("1000", {"at_npc_id": SERA})["ok"]))
	assert_true(e.npc_met(SERA), "the end NPC of a completed quest")
	assert_true(bool(e.accept("1001", SERA)["ok"]))
	assert_eq(MisoUiText.objective_text(_turn_in_row(e, "1001")), "Return to Heena")
	# The letters: Lucas is new for 1007; Maria is met for 1008.
	e.accept("1007", MARIA)
	assert_eq(MisoUiText.objective_text(_turn_in_row(e, "1007")), "Talk to Lucas")
	assert_true(bool(e.complete("1007", {"at_npc_id": LUCAS})["ok"]))
	e.accept("1008", LUCAS)
	assert_eq(MisoUiText.objective_text(_turn_in_row(e, "1008")), "Return to Maria")
	assert_eq(MisoUiText.objective_text({"kind": "npc_talk", "purpose": "turn_in", "name": "Mai"}), "Talk to Mai",
		"a row without 'met' never claims a return")


func _turn_in_row(e: QuestEngine, qid: String) -> Dictionary:
	for r: Dictionary in e.objective_status(qid):
		if r["kind"] == "npc_talk" and r["purpose"] == "turn_in":
			return r
	return {}


func test_quest_summary_carries_npcs_maps_chain_and_missable() -> void:
	var e := _engine(_character())
	var s := e.quest_summary("1006")
	assert_eq(s["start_npc_name"], "Sam")
	assert_eq(s["start_map_name"], "Snail Hunting Ground I")
	assert_eq(s["end_npc_name"], "Mai")
	assert_eq(s["end_map_name"], "A Split Road")
	assert_eq(s["chain"]["name"], "Mai's Training")
	assert_eq(s["missable"], QuestDef.from_records(db().quest("1006")).missable, "the record's flag (default false)")
	assert_eq(s["min_level"], 1)
	assert_eq(MisoQuestWindow.npc_line(s), "From Sam (Snail Hunting Ground I)  ·  turn in to Mai (A Split Road)")
	assert_eq(MisoQuestWindow.npc_line(e.quest_summary("1002")), "From Roger (Mushroom Town)", "same NPC both ends")


func test_missable_flag_is_parsed_with_default_false() -> void:
	var rec: Dictionary = db().quest("1009").duplicate(true)
	rec.erase("missable")
	assert_false(QuestDef.from_records(rec).missable, "no flag: false")
	rec["missable"] = true
	assert_true(QuestDef.from_records(rec).missable)
	rec["missable"] = {"value": true, "source": {"authority": "MeowDB MS Classic"}}
	assert_true(QuestDef.from_records(rec).missable, "a sourced value object")
	rec["missable"] = false
	assert_false(QuestDef.from_records(rec).missable)


# --- the window -----------------------------------------------------------------------------------------------

func test_window_shows_mai_training_2_of_3_with_npcs_and_maps() -> void:
	var c := _character(3)
	_done(c, ["1006"])
	var ql := _quest_window(c)
	var qs: QuestService = game.quests
	assert_true(bool(qs.accept("1009", MAI)["ok"]))
	ql.select_tab(MisoQuestWindow.TAB_IN_PROGRESS)
	ql.select_quest("1009")
	var texts := _texts(ql)
	assert_true("Mai's Training 2/3" in ql.detail_texts(), "chain line: %s" % texts)
	for nm in ["Sam's Suggestion", "Mai's Training", "Mai's Final Training"]:
		assert_true(nm in ql.detail_texts(), "chain step '%s': %s" % [nm, texts])
	assert_true("From Mai (A Split Road)" in ql.detail_texts(), "start NPC with map: %s" % texts)
	assert_true(_has_prefix(ql, "In progress"), "completion state: %s" % texts)
	var objectives := _objective_texts(ql)
	assert_eq(objectives, PackedStringArray(["Blue Snail 0/10", "Shroom 0/10", "Red Snail 0/5", "Return to Mai"]),
		"objective quantities")
	for k in 4:
		bus.emit_signal("monster_killed", "3", "000000050")
	assert_eq(_objective_texts(ql)[0], "Blue Snail 4/10", "live quantities")


func test_window_shows_rain_quiz_4_of_7() -> void:
	var c := _character(5)
	_done(c, ["1013", "1014", "1015"])
	var ql := _quest_window(c)
	assert_true(bool((game.quests as QuestService).accept("1016", RAIN)["ok"]))
	ql.select_tab(MisoQuestWindow.TAB_IN_PROGRESS)
	ql.select_quest("1016")
	assert_true("Rain's Maple Quiz 4/7" in ql.detail_texts(), _texts(ql))
	assert_eq(_objective_texts(ql), PackedStringArray(["Return to Rain", "Answer the quiz"]))
	assert_true(_has_prefix(ql, "Ready to turn in"), "the quiz is answered at Rain: %s" % _texts(ql))


func test_window_wording_for_a_never_met_turn_in_npc() -> void:
	var ql := _quest_window(_character())
	assert_true(bool((game.quests as QuestService).accept("1006", SAM)["ok"]))
	ql.select_tab(MisoQuestWindow.TAB_IN_PROGRESS)
	ql.select_quest("1006")
	assert_true("Talk to Mai" in _objective_texts(ql), "%s" % _objective_texts(ql))
	assert_false("Return to Mai" in _objective_texts(ql))
	assert_true("From Sam (Snail Hunting Ground I)  ·  turn in to Mai (A Split Road)" in ql.detail_texts(), _texts(ql))
	assert_true("Mai's Training 1/3" in ql.detail_texts(), "1006 has no quest_group; its chain still shows")


func test_window_shows_missable_tag_when_the_record_has_it() -> void:
	var d := ContentDB.new()
	d.canonical = db().canonical.duplicate(false)
	var qs: Dictionary = (db().canonical["quests"] as Dictionary).duplicate(false)
	var rec: Dictionary = (qs["1002"] as Dictionary).duplicate(true)
	rec["missable"] = true
	qs["1002"] = rec
	d.canonical["quests"] = qs
	d.miso = db().miso
	d.loaded = true
	var ql := _quest_window(_character(), d)
	assert_true(bool((game.quests as QuestService).accept("1002", ROGER)["ok"]))
	ql.select_tab(MisoQuestWindow.TAB_IN_PROGRESS)
	ql.select_quest("1002")
	assert_true("In progress  ·  Missable" in ql.detail_texts(), _texts(ql))
	assert_false(ql.detail_texts().has("Mai's Training 1/3"))
	for ch in ql.detail_box.get_children():
		assert_false(ch.has_meta("chain"), "a standalone quest shows no chain")


func test_window_received_random_hat_survives_a_reload() -> void:
	var c := _character(2)
	_done(c, ["1007"])
	var ql := _quest_window(c, null, 4)
	var qs: QuestService = game.quests
	assert_true(bool(qs.accept("1008", LUCAS)["ok"]))
	var r := qs.complete("1008", {"at_npc_id": MARIA})
	assert_true(bool(r["ok"]), "complete: %s" % r.get("reason"))
	var hat := String(r["random_picks"][0]["item_id"])
	var hat_name := String(db().item(hat).get("name"))
	ql.select_tab(MisoQuestWindow.TAB_COMPLETED)
	ql.select_quest("1008")
	assert_true("Received: %s" % hat_name in ql.detail_texts(), _texts(ql))
	assert_true(_has_prefix(ql, "Completed"), _texts(ql))
	# Save, load into a fresh window: the received hat is still shown.
	var back := CharacterState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	var ql2 := _quest_window(back)
	ql2.select_tab(MisoQuestWindow.TAB_COMPLETED)
	ql2.select_quest("1008")
	assert_true("Received: %s" % hat_name in ql2.detail_texts(), _texts(ql2))
	# A completion from a format 1 save shows no "Received" line.
	ql2.select_quest("1007")
	for t in ql2.detail_texts():
		assert_false(t.begins_with("Received:"), "unrecorded completion: %s" % t)
