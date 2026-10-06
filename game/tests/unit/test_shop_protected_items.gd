extends TestCase
## Protected items (owner ruling #7, an adaptation in data/misostory/inventory.json shop.protected_items): every NPC
## shop refuses to buy The Green Relaxer, untradeable and given once by Pio's quest 1012, with its own reason and a
## message, and nothing changes. Other items sell as before, and the quest-item sell guard behaves as before.

const LUCY := "maple-road-lucy"
const PAN := "maple-road-pan"
const SID := "maple-road-sid"
const RELAXER := "522"
const RED_POTION := "270"
const ROGERS_APPLE := "235"
const ROGER := "3"
const MESSAGE := "The Green Relaxer cannot be obtained again. The shop will not buy it."

var bus: Node


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()


func after_each() -> void:
	bus.free()


func _with_chair() -> CharacterState:
	var c := CharacterState.new()
	c.mesos = 1000
	assert_eq(c.inventory.add(RELAXER, 1, db()), 1)
	return c


func test_the_green_relaxer_is_protected_as_an_adaptation() -> void:
	var e := ItemsConfig.protected_item(RELAXER, db())
	assert_eq(String(e.get("name", "")), "The Green Relaxer")
	assert_eq(e.get("verified"), false, "an adaptation is unverified")
	assert_true(String(e.get("decision", "")).begins_with("#7"), "the owner ruling is the issue: %s" % e)
	assert_true(String(e.get("reason", "")).contains("MeowDB documents no sell restriction"), String(e.get("reason", "")))
	assert_true(ItemsConfig.protected_item(RED_POTION, db()).is_empty())
	# Canonically it does sell (1 meso), so only the adaptation refuses it.
	assert_eq(ShopService.sell_price(RELAXER, db()), 1)


func test_every_shop_refuses_the_green_relaxer_and_nothing_changes() -> void:
	var events: Array = []
	bus.connect("item_lost", func(id: String, q: int) -> void: events.append(["item_lost", id, q]))
	bus.connect("mesos_changed", func(m: int, dl: int) -> void: events.append(["mesos_changed", m, dl]))
	for shop_id in [LUCY, PAN, SID]:
		var c := _with_chair()
		var r := ShopService.sell(c, shop_id, RELAXER, 1, db(), bus)
		assert_false(bool(r["ok"]), shop_id)
		assert_eq(r["code"], ShopService.PROTECTED_ITEM, shop_id)
		assert_eq(c.inventory.count(RELAXER), 1, "%s: the chair stays" % shop_id)
		assert_eq(c.mesos, 1000, "%s: no mesos" % shop_id)
		assert_eq(MisoUiText.result_message(r, db()), MESSAGE)
		var slot := ShopService.sell_slot(c, shop_id, "setup", 0, 1, db(), bus)
		assert_eq(slot["code"], ShopService.PROTECTED_ITEM, "%s: from its slot too" % shop_id)
		assert_eq(c.inventory.count(RELAXER), 1)
	assert_eq(events, [], "no item_lost, no mesos_changed")


func test_other_items_sell_as_before() -> void:
	var c := _with_chair()
	c.inventory.add(RED_POTION, 3, db())
	var r := ShopService.sell(c, LUCY, RED_POTION, 3, db(), bus)
	assert_true(bool(r["ok"]), str(r))
	assert_eq(c.mesos, 1000 + 3 * ShopService.sell_price(RED_POTION, db()))
	assert_eq(c.inventory.count(RED_POTION), 0)


func test_the_quest_item_guard_is_unchanged() -> void:
	var c := CharacterState.new()
	var svc := QuestService.create(bus, db(), c, RandomNumberGenerator.new(), func() -> float: return 1.0)
	svc.attach()
	assert_true(bool(svc.accept("1002", ROGER)["ok"]))
	var r := ShopService.quote_sell(c, LUCY, ROGERS_APPLE, 1, db())
	assert_eq(r["code"], ShopService.QUEST_ITEM_NEEDED, "Roger's Apple is held by 1002, not by the protected list")
	c.inventory.add(ROGERS_APPLE, 1, db())
	assert_true(bool(ShopService.quote_sell(c, LUCY, ROGERS_APPLE, 1, db())["ok"]), "an extra copy sells")
	svc.detach()


func test_the_list_is_data() -> void:
	var d := ContentDB.new()
	d.canonical = db().canonical
	d.miso = db().miso.duplicate(false)
	var root: Dictionary = (db().miso[""] as Dictionary).duplicate(false)
	var inv: Dictionary = (root["inventory"] as Dictionary).duplicate(true)
	(inv["shop"] as Dictionary)["protected_items"] = []
	root["inventory"] = inv
	d.miso[""] = root
	d.loaded = true
	var c := _with_chair()
	var r := ShopService.sell(c, LUCY, RELAXER, 1, d, bus)
	assert_true(bool(r["ok"]), "without the entry it sells at its canonical 1 meso: %s" % r)
	assert_eq(c.mesos, 1001)
	assert_eq(ShopService.quote_sell(_with_chair(), LUCY, RELAXER, 1, db())["code"], ShopService.PROTECTED_ITEM)


func test_shop_window_says_why() -> void:
	var c := _with_chair()
	var win := ShopWindow.new()
	win.db = db()
	win.bus = bus
	win.character_provider = func() -> CharacterState: return c
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(win)
	win.open_shop(LUCY)
	win.set_sell_tab("setup")
	assert_eq(win.sell_rows.size(), 1)
	assert_true(win.select_sell_slot("setup", int(win.sell_rows[0]["index"])))
	assert_eq(win.check_label.text, MESSAGE, "the live check line says it before Enter")
	var r := win.confirm()
	assert_eq(r["code"], ShopService.PROTECTED_ITEM)
	assert_eq(win.status_text, MESSAGE)
	assert_eq(c.inventory.count(RELAXER), 1)
	assert_eq(c.mesos, 1000)
	win.free()
