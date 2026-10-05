extends TestCase
## NpcCatalog / NpcDef: canonical identity and relationships of the 21 Maple Island NPCs plus adaptation overrides.


func test_catalog_has_the_21_npcs_and_validates() -> void:
	var cat := NpcCatalog.new(db())
	assert_eq(cat.ids().size(), 21)
	assert_eq(cat.ids()[0], "1", "numeric order")
	assert_eq(cat.ids()[20], "21")
	var errs := cat.validate()
	assert_eq(errs.size(), 0, "\n".join(errs))


func test_roger_definition() -> void:
	var n := NpcCatalog.new(db()).get_def("3")
	assert_eq(n.name, "Roger")
	assert_eq(n.map_id, "000000010")
	assert_eq(n.position_px, Vector2(233, 58))
	assert_eq(n.roles, PackedStringArray(["Quest Giver"]))
	assert_eq(n.quests_started, PackedStringArray(["1002"]))
	assert_eq(n.quests_completed, PackedStringArray(["1002"]))
	assert_eq(n.behaviors, PackedStringArray(["quest", "talk"]))
	assert_eq(n.portrait, "npc_3", "default portrait key")
	assert_eq(n.shop_id, "")
	assert_eq(n.dialogue_lines.size(), 2)
	assert_eq(n.idle_chatter.size(), 9)


func test_shopkeepers_link_their_shops() -> void:
	var cat := NpcCatalog.new(db())
	var expect := {"16": "maple-road-pan", "20": "maple-road-sid", "21": "maple-road-lucy"}
	for nid: String in expect:
		var n := cat.get_def(nid)
		assert_eq(n.shop_id, expect[nid])
		assert_true(n.has_behavior("shop"), "%s sells" % n.name)
		assert_false(n.has_behavior("quest"))
		assert_true(db().has("shops", n.shop_id), "shop record exists")
	assert_eq(cat.get_def("16").function_title, "Armor Seller")


func test_quest_relationships_match_quest_records() -> void:
	var cat := NpcCatalog.new(db())
	var quests := QuestCatalog.new(db())
	for nid in cat.ids():
		var n := cat.get_def(nid)
		var started := quests.started_by(nid)
		var completed := quests.completed_by(nid)
		var ns := n.quests_started.duplicate()
		ns.sort()
		var nc := n.quests_completed.duplicate()
		nc.sort()
		assert_eq(ns, started, "npc %s started" % nid)
		assert_eq(nc, completed, "npc %s completed" % nid)
	assert_eq(cat.get_def("19").all_quests().size(), 7, "Rain's seven quizzes")
	assert_eq(cat.get_def("11").all_quests(), PackedStringArray(["1006", "1009", "1010"]), "Mai")


func test_shanks_transport_enabled_with_a_departure_boundary() -> void:
	var n := NpcCatalog.new(db()).get_def("15")
	assert_false(n.transport.is_empty(), "canonical transport kept")
	assert_true(n.has_behavior("transport"), "Iteration Three: Shanks offers the voyage")
	assert_true(n.has_behavior("talk"))
	assert_true(not String(n.adaptation.get("reason", "")).is_empty())
	var r := NpcTransport.route("15", 0, db())
	assert_eq(r.get("to_map_name"), "Lith Harbor")
	assert_eq(r.get("to_map_id"), "010000000")
	assert_eq(int(r.get("fare_mesos")), 300)
	assert_eq(int(r.get("min_level")), 7)
	assert_eq(r.get("one_way"), true)
	var b := NpcTransport.boundary("15", db())
	assert_eq(b.get("boundary"), true)
	assert_eq(b.get("charge_fare"), false, "no voyage, so no fare is taken")
	assert_eq(b.get("flag"), "maple_island_departure_ready_at")
	assert_eq(NpcTransport.unfinished_region("15", db()), "Maple Island")
	assert_eq(n.adaptation.get("verified"), false)


func test_a_transport_npc_without_a_boundary_is_reported() -> void:
	var d := ContentDB.new()
	d.canonical = db().canonical
	d.miso = db().miso.duplicate(false)
	var npcs: Dictionary = (db().miso["npcs"] as Dictionary).duplicate(false)
	npcs.erase("15")
	d.miso["npcs"] = npcs
	d.loaded = true
	var errs := NpcCatalog.new(d).validate()
	var found := false
	for e in errs:
		found = found or (e.contains("npc 15") and e.contains("departure boundary"))
	assert_true(found, "%s" % "\n".join(errs))


func test_npcs_on_map() -> void:
	var cat := NpcCatalog.new(db())
	assert_eq(cat.on_map("000000060"), PackedStringArray(["12", "13", "14", "15"]))
	assert_eq(cat.on_map("000001010"), PackedStringArray(["17", "18", "19"]))
	assert_eq(cat.on_map("000000041").size(), 0)


func test_townsfolk_only_talk() -> void:
	var cat := NpcCatalog.new(db())
	for nid in ["8", "13", "14"]:
		assert_eq(cat.get_def(nid).behaviors, PackedStringArray(["talk"]), "npc %s" % nid)


func test_idle_line_for_speech_bubbles() -> void:
	var n := NpcCatalog.new(db()).get_def("12")
	var line := n.idle_line(0)
	assert_eq(line["text"], "Heh, looks like I'm still the best looking man in this town.")
	assert_eq(line["segments"].size(), 1)
	assert_eq(line["source"], "canonical/npcs/12.json#idle_chatter[0]")
	assert_eq(n.idle_line(99)["text"], "")


## Contract C6: the canonical requirements these tests prove.
func parity_keys() -> Dictionary:
	var all_npcs: Array = []
	for k in 21:
		all_npcs.append("npc:%d" % (k + 1))
	return {
		"test_catalog_has_the_21_npcs_and_validates": all_npcs,
		"test_shopkeepers_link_their_shops": ["npc:16", "npc:20", "npc:21", "shop:maple-road-pan", "shop:maple-road-sid",
			"shop:maple-road-lucy"],
		"test_shanks_transport_enabled_with_a_departure_boundary": ["npc:15"],
	}
