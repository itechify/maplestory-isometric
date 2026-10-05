extends TestCase
## Quest-critical items (Iteration Three adaptations): a shop will not buy a quest item an in-progress quest still
## needs, and says why (data/misostory/quests/_quest_items.json, QuestItemGuard); Roger re-issues Roger's Apple when
## 1002 is in progress and the apple is gone (data/misostory/quests/1002.json reissue_lost_accept_items; MeowDB has
## no "lost" branch for 1002).

const LUCY := "maple-road-lucy"
const ROGER := "3"
const TODD := "7"
const SERA := "2"
const HEENA := "1"
const BIGGS := "12"

var bus: Node
var character: CharacterState
var service: QuestService
var talk: NpcInteraction
var events: Array = []


func parity_keys() -> Dictionary:
	return {
		"test_rogers_apple_cannot_be_sold_during_1002": ["quest:1002", "shop:maple-road-lucy"],
		"test_rogers_apple_is_reissued_at_roger_and_1002_completes": ["quest:1002", "npc:3"],
		"test_shellpiece_extra_copies_sell_during_1005": ["quest:1005", "shop:maple-road-pan"],
	}


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	events = []
	bus.connect("item_gained", func(item_id: String, qty: int) -> void: events.append(["item_gained", item_id, qty]))
	character = CharacterState.new()
	service = QuestService.create(bus, db(), character, RandomNumberGenerator.new(), func() -> float: return 3.0)
	service.attach()
	talk = NpcInteraction.new(service)


func after_each() -> void:
	service.detach()
	bus.free()


func _read_to_end(v: Dictionary) -> PackedStringArray:
	var seen := PackedStringArray()
	for k in 20:
		if not bool(v.get("open", false)):
			break
		seen.append(String(v["text"]))
		if "next" in v["buttons"]:
			v = talk.press("next")
		elif "ok" in v["buttons"]:
			v = talk.press("ok")
		else:
			break
	return seen


# --- the sell guard ---------------------------------------------------------------------------------------------

func test_rogers_apple_cannot_be_sold_during_1002() -> void:
	assert_true(bool(service.accept("1002", ROGER)["ok"]))
	assert_eq(character.inventory.count("235"), 1, "Roger hands the apple over (1002 adaptation)")
	var r := ShopService.sell(character, LUCY, "235", 1, db(), bus)
	assert_eq(r["code"], ShopService.QUEST_ITEM_NEEDED)
	assert_eq(r["quest_id"], "1002")
	assert_eq(int(r["needed"]), 1)
	assert_eq(character.inventory.count("235"), 1, "nothing sold")
	assert_eq(MisoUiText.result_message(r, db()),
		"Roger's Apple is needed for Roger's Apple (keep 1). The shop will not buy it while the quest is in progress.")
	# A second apple is not needed: it sells.
	character.inventory.add("235", 1, db())
	assert_true(bool(ShopService.sell(character, LUCY, "235", 1, db(), bus)["ok"]), "an extra copy sells")
	assert_eq(ShopService.quote_sell(character, LUCY, "235", 1, db())["code"], ShopService.QUEST_ITEM_NEEDED)
	# Once eaten, the quest needs no apple: a new one sells.
	service.engine.on_item_used("235")
	character.inventory.remove("235", 1)
	character.inventory.add("235", 1, db())
	assert_true(bool(ShopService.quote_sell(character, LUCY, "235", 1, db())["ok"]), "the usage objective is done")


func test_shellpiece_extra_copies_sell_during_1005() -> void:
	character.level = 1
	assert_true(bool(service.accept("1005", TODD)["ok"]))
	character.inventory.add("347", 5, db())
	assert_true(bool(ShopService.quote_sell(character, "maple-road-pan", "347", 2, db())["ok"]), "5 held, 3 needed")
	var r := ShopService.quote_sell(character, "maple-road-pan", "347", 3, db())
	assert_eq(r["code"], ShopService.QUEST_ITEM_NEEDED, "selling 3 of 5 would leave 2 of 3")
	assert_eq(int(r["needed"]), 3)
	character.quests.forfeit("1005")
	assert_true(bool(ShopService.quote_sell(character, "maple-road-pan", "347", 5, db())["ok"]), "no quest, no guard")


func test_tradeable_drops_a_quest_collects_stay_sellable() -> void:
	character.level = 3
	assert_true(bool(service.accept("1011", BIGGS)["ok"]))
	character.inventory.add("349", 10, db())
	character.inventory.add("356", 1, db())
	assert_true(bool(ShopService.quote_sell(character, LUCY, "349", 10, db())["ok"]), "Blue Snail Shell is tradeable")
	assert_true(bool(ShopService.quote_sell(character, LUCY, "356", 1, db())["ok"]), "Orange Mushroom Cap too")


func test_sera_mirror_is_held_during_1001() -> void:
	character.quests.start("1000", 0.0)
	character.quests.complete("1000", 0.0)
	assert_true(bool(service.accept("1001", SERA)["ok"]))
	assert_eq(character.inventory.count("438"), 1)
	assert_eq(ShopService.quote_sell(character, LUCY, "438", 1, db())["code"], ShopService.QUEST_ITEM_NEEDED)


func test_the_guard_follows_its_adaptation_switch() -> void:
	var d := ContentDB.new()
	d.canonical = db().canonical
	d.miso = db().miso.duplicate(false)
	var qs: Dictionary = (db().miso["quests"] as Dictionary).duplicate(false)
	qs["_quest_items"] = {"reason": "test", "verified": false,
		"block_selling_needed_quest_items": {"value": false, "reason": "test", "verified": false}}
	d.miso["quests"] = qs
	d.loaded = true
	character.quests.start("1002", 0.0)
	character.inventory.add("235", 1, db())
	assert_true(bool(ShopService.quote_sell(character, LUCY, "235", 1, d)["ok"]), "switched off")
	assert_eq(ShopService.quote_sell(character, LUCY, "235", 1, db())["code"], ShopService.QUEST_ITEM_NEEDED)


func test_shop_window_says_why() -> void:
	assert_true(bool(service.accept("1002", ROGER)["ok"]))
	var win := ShopWindow.new()
	win.db = db()
	win.bus = bus
	win.character_provider = func() -> CharacterState: return character
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(win)
	win.open_shop(LUCY)
	win.set_sell_tab("use")
	assert_eq(win.sell_rows.size(), 1)
	assert_true(win.select_sell_slot("use", int(win.sell_rows[0]["index"])))
	assert_true(win.check_label.text.begins_with("Roger's Apple is needed for Roger's Apple"), win.check_label.text)
	var r := win.confirm()
	assert_eq(r["code"], ShopService.QUEST_ITEM_NEEDED)
	assert_true(win.status_text.contains("The shop will not buy it while the quest is in progress."), win.status_text)
	assert_eq(character.inventory.count("235"), 1)
	win.free()


# --- Roger's Apple re-issue ---------------------------------------------------------------------------------------

func test_rogers_apple_is_reissued_at_roger_and_1002_completes() -> void:
	var v := talk.talk(ROGER)
	v = talk.press("yes")
	_read_to_end(v)
	assert_eq(character.quests.status("1002"), QuestLog.IN_PROGRESS)
	assert_eq(character.inventory.count("235"), 1)
	character.inventory.remove("235", 1)
	assert_eq(service.engine.lost_items("1002"), [{"item_id": "235", "count": 1}])
	events.clear()
	v = talk.talk(ROGER)
	assert_eq(character.inventory.count("235"), 1, "Roger hands another apple over")
	assert_has(events, ["item_gained", "235", 1])
	assert_true(String(v["text"]).begins_with("Eat the Roger's Apple I gave you"), "canonical missing-items line: %s" % v)
	assert_eq(v["source"], "canonical/quests/1002.json#dialogue.on_completion.branches[missing_items].lines[0]")
	assert_eq(v["buttons"], ["ok"], "one page, then the chat ends")
	_read_to_end(v)
	# Holding the apple: Roger repeats his line and gives nothing more.
	v = talk.talk(ROGER)
	assert_true(String(v["text"]).begins_with("Eat the Roger's Apple I gave you"))
	assert_eq(character.inventory.count("235"), 1, "no duplicate while the apple is held")
	talk.close()
	# Eat it, talk: 1002 completes.
	service.engine.on_item_used("235")
	character.inventory.remove("235", 1)
	assert_eq(service.engine.lost_items("1002"), [], "an eaten apple is not lost")
	v = talk.talk(ROGER)
	_read_to_end(v)
	assert_eq(character.quests.status("1002"), QuestLog.COMPLETED)
	assert_eq(character.inventory.count("235"), 0, "no apple after completion")


func test_reissue_needs_room() -> void:
	assert_true(bool(service.accept("1002", ROGER)["ok"]))
	character.inventory.remove("235", 1)
	var stack := maxi(1, int(db().item("237").get("max_stack", 1)))
	for k in 2000:
		if character.inventory.add("237", stack, db()) < stack:
			break
	var v := talk.talk(ROGER)
	assert_eq(v["speaker_kind"], "system")
	assert_true(String(v["text"]).begins_with("Your inventory is full."), v["text"])
	assert_eq(character.inventory.count("235"), 0)


func test_roger_has_one_entry_only() -> void:
	assert_true(bool(service.accept("1002", ROGER)["ok"]))
	character.inventory.remove("235", 1)
	var g := talk.graph_for(ROGER)
	var start: Dictionary = g.node("start")
	var tags: Array = []
	for c: Dictionary in start["choices"]:
		tags.append(c["tag"])
	assert_eq(tags, ["turnin", "offer"], "the re-issue goes through the turn-in, not a second menu entry")
	assert_true(g.has_node("q1002.reissue"))
	assert_true(QuestCatalog.new(db()).get_def("1002").reissues_lost_items())
	assert_false(QuestCatalog.new(db()).get_def("1006").reissues_lost_items())
