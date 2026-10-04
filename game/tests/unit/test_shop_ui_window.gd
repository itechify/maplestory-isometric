extends TestCase
## The NPC shop window through its UI handlers (row selection, quantity picker, Buy/Sell, keys): canonical stock in
## order, prices and owned counts, buying with the meso check, insufficient mesos, a full inventory, selling from the
## inventory tabs at the canonical sell-back price, the modal/window contract, and opening from a shopkeeper's
## dialogue and from Events.shop_open_requested (NpcUi).

class FakePlayer:
	extends Node3D
	var input_on := true

	func set_input_enabled(on: bool) -> void:
		input_on = on


var bus: Node
var character: CharacterState
var win: ShopWindow
var events: Array = []


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	events = []
	for sname in ["mesos_changed", "item_gained", "item_lost", "inventory_full", "shop_opened", "shop_closed"]:
		var n: String = sname
		var arity := 0
		for s: Dictionary in bus.get_signal_list():
			if s["name"] == n:
				arity = (s["args"] as Array).size()
		match arity:
			1:
				bus.connect(n, func(a: Variant) -> void: events.append([n, a]))
			2:
				bus.connect(n, func(a: Variant, b: Variant) -> void: events.append([n, a, b]))
	character = CharacterState.new()
	win = _make_window()


func after_each() -> void:
	if is_instance_valid(win):
		win.free()
	bus.free()


func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root


func _make_window() -> ShopWindow:
	var w := ShopWindow.new()
	w.db = db()
	w.bus = bus
	w.character_provider = func() -> CharacterState: return character
	_parent().add_child(w)
	return w


func _key(k: Key, shift: bool = false) -> bool:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.shift_pressed = shift
	e.pressed = true
	return win.handle_key(e)


func _emitted(sname: String) -> Array:
	var out: Array = []
	for e: Array in events:
		if e[0] == sname:
			out.append(e.slice(1))
	return out


func _price(shop: String, item: String) -> int:
	return int(ShopService.row_for(shop, item, db())["price"])


# --- buy -----------------------------------------------------------------------------------------------------------

func test_buy_tab_lists_the_canonical_stock_in_order() -> void:
	assert_true(win.open_shop("maple-road-lucy", "21"))
	assert_true(win.is_open() and win.visible)
	var canon: Array = db().shop("maple-road-lucy")["items"]
	assert_eq(win.buy_rows.size(), canon.size())
	for i in canon.size():
		assert_eq(win.buy_rows[i]["item_id"], String(canon[i]["item_id"]), "row %d in canonical order" % i)
		assert_eq(win.buy_rows[i]["price"], int(canon[i]["price_mesos"]), "canonical price")
	assert_eq(win._rows.size(), canon.size(), "one list row per stock row")
	assert_eq(win.title_label.text, "Lucy's Shop")
	assert_true(win.subtitle_label.text.contains("Grocer"), win.subtitle_label.text)
	assert_eq(_emitted("shop_opened"), [["maple-road-lucy"]])
	assert_true(win.open_shop("maple-road-lucy"), "opening the open shop again is harmless")
	assert_eq(_emitted("shop_opened").size(), 1)


func test_buying_spends_mesos_and_fills_the_inventory() -> void:
	character.mesos = 1000
	win.open_shop("maple-road-lucy")
	assert_true(win.select_buy_item("270"))
	win.set_quantity(5)
	assert_eq(win.quantity, 5)
	var price := _price("maple-road-lucy", "270")
	assert_eq(win.total_label.text, "Total: %d mesos" % (price * 5))
	var r := win.confirm()
	assert_true(bool(r["ok"]), str(r))
	assert_eq(character.mesos, 1000 - price * 5)
	assert_eq(character.inventory.count("270"), 5)
	assert_eq(win.status_text, "Bought Red Potion x5 for %d mesos." % (price * 5))
	assert_eq(win.meso_label.text, DialogueWindow._thousands(1000 - price * 5), "meso display follows")
	assert_eq(win.owned("270"), 5)
	assert_true(win.detail_owned.text.ends_with("5"), "owned count in the detail panel")
	assert_has(_emitted("mesos_changed"), [1000 - price * 5, -price * 5])
	assert_has(_emitted("item_gained"), ["270", 5])


func test_insufficient_mesos_is_refused_with_the_numbers() -> void:
	var price := _price("maple-road-lucy", "270")
	character.mesos = price - 10
	win.open_shop("maple-road-lucy")
	win.select_buy_item("270")
	assert_eq(win.check_label.text, ItemCodes.message(ItemCodes.INSUFFICIENT_MESOS), "the meso check shows before buying")
	var r := win.confirm()
	assert_false(bool(r["ok"]))
	assert_eq(r["code"], ItemCodes.INSUFFICIENT_MESOS)
	assert_eq(win.status_text, "%s (costs %d, you have %d)" % [ItemCodes.message(r), price, price - 10])
	assert_eq(character.mesos, price - 10, "nothing spent")
	assert_eq(character.inventory.count("270"), 0)


func test_full_inventory_is_refused() -> void:
	character.mesos = 100000
	for k in 4000:
		if character.inventory.add("273", 100, db()) < 100:
			break
	assert_eq(character.inventory.room_for("270", db()), 0, "Use tab full")
	win.open_shop("maple-road-lucy")
	win.select_buy_item("270")
	var r := win.confirm()
	assert_eq(r["code"], ItemCodes.INVENTORY_FULL)
	assert_eq(win.status_text, ItemCodes.message(r))
	assert_eq(character.mesos, 100000, "nothing spent")
	assert_has(_emitted("inventory_full"), ["270"])


func test_quantity_picker_respects_mesos_and_space() -> void:
	var price := _price("maple-road-lucy", "270")
	character.mesos = price * 2 + 10
	win.open_shop("maple-road-lucy")
	win.select_buy_item("270")
	assert_eq(win.max_quantity(), 2, "what the mesos pay for")
	win.set_quantity(99)
	assert_eq(win.quantity, 2)
	win.change_quantity(-5)
	assert_eq(win.quantity, 1, "never below 1")
	character.mesos = 0
	assert_eq(win.max_quantity(), 1, "1 so a click still explains why it fails")


# --- sell ----------------------------------------------------------------------------------------------------------

func test_sell_tab_lists_slots_with_canonical_sell_back_prices() -> void:
	character.inventory.add("348", 5, db())
	character.inventory.add("270", 3, db())
	win.open_shop("maple-road-lucy")
	win.set_sell_tab("etc")
	assert_eq(win.mode, "sell")
	assert_eq(win.sell_rows.size(), 1)
	var sp := ShopService.sell_price("348", db())
	assert_eq(win.sell_rows[0]["item_id"], "348")
	assert_eq(win.sell_rows[0]["price"], sp, "canonical sell_price_mesos")
	assert_eq(win.sell_rows[0]["qty"], 5)
	assert_true(win.select_sell_slot("etc", int(win.sell_rows[0]["index"])))
	win.set_quantity(4)
	var r := win.confirm()
	assert_true(bool(r["ok"]), str(r))
	assert_eq(character.mesos, sp * 4)
	assert_eq(character.inventory.count("348"), 1)
	assert_eq(win.status_text, "Sold Snail Shell x4 for %d mesos." % (sp * 4))
	win.set_quantity(9)
	assert_eq(win.quantity, 1, "at most the slot's quantity")
	win.confirm()
	assert_eq(win.sell_rows.size(), 0, "the emptied slot leaves the list")
	win.set_sell_tab("use")
	assert_eq(win.sell_rows.size(), 1)


func test_selling_an_equipment_slot() -> void:
	character.inventory.add("541", 1, db())
	win.open_shop("maple-road-sid")
	win.set_sell_tab("equip")
	assert_eq(win.sell_rows.size(), 1)
	win.select(0)
	var r := win.confirm()
	assert_true(bool(r["ok"]), str(r))
	assert_eq(character.mesos, ShopService.sell_price("541", db()))
	assert_eq(character.inventory.count("541"), 0)


func test_every_shop_renders_from_data() -> void:
	for shop_id in db().ids("shops"):
		assert_true(win.open_shop(shop_id), shop_id)
		assert_eq(win._rows.size(), ShopService.stock(shop_id, db()).size(), shop_id)
		for i in win.buy_rows.size():
			win.select(i)
			assert_false(win.detail_name.text.is_empty(), "%s row %d has a name" % [shop_id, i])
		win.close()
	assert_false(win.open_shop("no-such-shop"), "unknown shops are refused")
	assert_false(win.is_open())


# --- keys, modal, opening paths ------------------------------------------------------------------------------------

func test_space_never_buys_and_enter_waits_for_the_arm_time() -> void:
	character.mesos = 1000
	# A long arm so the test cannot outrun it; then the arm is lifted.
	win.confirm_arm_s = 3600.0
	win.open_shop("maple-road-lucy")
	var item := String(win.buy_rows[0]["item_id"])
	assert_true(_key(KEY_ENTER), "Enter is swallowed while the shop is arming")
	assert_eq(character.inventory.count(item), 0, "an Enter right after opening (mashing through the greeting) buys nothing")
	assert_eq(character.mesos, 1000)
	assert_false(win.confirm_key_armed())
	win.confirm_arm_s = 0.0
	assert_true(win.confirm_key_armed())
	assert_true(_key(KEY_SPACE), "Space is swallowed (it never reaches a button or the world)")
	assert_eq(character.inventory.count(item), 0, "Space never buys")
	assert_eq(character.mesos, 1000)
	character.inventory.add("237", 3, db())
	win.set_sell_tab("use")
	assert_eq(String(win.sell_rows[win.selected]["item_id"]), "237")
	assert_true(_key(KEY_SPACE))
	assert_eq(character.mesos, 1000, "Space never sells either")
	assert_eq(character.inventory.count("237"), 3)
	win.set_mode("buy")
	assert_true(_key(KEY_ENTER))
	assert_eq(character.inventory.count(item), 1, "Enter buys once armed")
	# The mouse is never delayed.
	win.close()
	win.confirm_arm_s = 3600.0
	win.open_shop("maple-road-lucy")
	win.action_button.pressed.emit()
	assert_eq(character.inventory.count(item), 2, "the Buy button works at once")


func test_keyboard_controls() -> void:
	character.mesos = 1000
	win.confirm_arm_s = 0.0
	win.open_shop("maple-road-lucy")
	assert_eq(win.selected, 0)
	assert_true(_key(KEY_DOWN))
	assert_eq(win.selected, 1)
	assert_true(_key(KEY_UP))
	assert_true(_key(KEY_RIGHT))
	assert_true(_key(KEY_RIGHT))
	assert_eq(win.quantity, 3)
	assert_true(_key(KEY_LEFT, true), "Shift = 10")
	assert_eq(win.quantity, 1)
	assert_true(_key(KEY_ENTER))
	assert_eq(character.inventory.count(String(win.buy_rows[0]["item_id"])), 1, "Enter buys")
	assert_true(_key(KEY_TAB))
	assert_eq(win.mode, "sell")
	assert_true(_key(KEY_2), "2 = the Use tab")
	assert_eq(win.sell_tab, "use")
	assert_true(_key(KEY_ESCAPE))
	assert_false(win.is_open(), "Esc leaves (standalone)")
	assert_eq(_emitted("shop_closed"), [["maple-road-lucy"]])


func test_modal_and_window_stack_with_a_game_context() -> void:
	var ctx := GameContext.new()
	var p := FakePlayer.new()
	ctx.player = p
	win.ctx = ctx
	win.handle_escape = false
	win.open_shop("maple-road-pan")
	assert_true(ctx.is_modal_active())
	assert_false(p.input_on)
	assert_false(_key(KEY_ESCAPE), "Esc is the shell's")
	assert_true(ctx.close_top_window())
	assert_false(win.is_open())
	assert_false(ctx.is_modal_active())
	p.free()


func test_npc_ui_opens_the_shop_from_the_dialogue_and_from_events() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var service := QuestService.create(bus, db(), character, rng, func() -> float: return 0.0)
	service.attach()
	var talk := NpcInteraction.new(service)
	var ui := NpcUi.new()
	ui.bus = bus
	ui.talk_provider = func() -> NpcInteraction: return talk
	ui.bind_talk(talk)
	ui.shop.db = db()
	ui.shop.bus = bus
	ui.shop.character_provider = func() -> CharacterState: return character
	ui.dialogue.db = db()
	var ctx := GameContext.new()
	_parent().add_child(ui)
	ui.setup(ctx)
	talk.talk("21")
	assert_true(ui.dialogue.is_open(), "Lucy's greeting")
	ui.dialogue.press("next")
	assert_true(ui.shop.is_open(), "the open_shop action opened the window")
	assert_eq(ui.shop.shop_id, "maple-road-lucy")
	assert_false(ui.dialogue.is_open(), "the greeting closed")
	assert_true(ctx.is_modal_active(), "the shop keeps the keyboard")
	ui.shop.close()
	assert_false(ctx.is_modal_active())
	bus.emit_signal("shop_open_requested", "maple-road-pan", "16")
	assert_true(ui.shop.is_open())
	assert_eq(ui.shop.title_label.text, "Pan's Shop")
	ui.shop.close()
	service.detach()
	ui.free()
