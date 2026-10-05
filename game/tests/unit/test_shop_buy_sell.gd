extends TestCase
## Shops: canonical stock and prices, buying (price x quantity, bundles), insufficient mesos, purchase into a full
## inventory, selling at the canonical sell-back price, and the Events emitted through ItemService. Prices are read
## from data/canonical/shops and data/canonical/items, never typed in.

const LUCY := "maple-road-lucy"
const PAN := "maple-road-pan"
const SID := "maple-road-sid"
const RED_POTION := "270"


func _price(shop_id: String, item_id: String) -> int:
	for row in db().shop(shop_id).items:
		if String(row.item_id) == item_id:
			return int(row.price_mesos)
	return -1


func _rich(mesos: int = 100000) -> CharacterState:
	var c := CharacterState.new()
	c.mesos = mesos
	return c


func test_stock_is_canonical_data_in_display_order() -> void:
	for shop_id in db().ids("shops"):
		var rows := ShopService.stock(shop_id, db())
		var raw: Array = db().shop(shop_id).items
		assert_eq(rows.size(), raw.size(), shop_id)
		for i in rows.size():
			assert_eq(rows[i].position, i + 1, "%s position" % shop_id)
			var id := String(rows[i].item_id)
			assert_true(db().has("items", id), "%s sells unknown item %s" % [shop_id, id])
			assert_eq(rows[i].price, _price(shop_id, id), "%s %s price" % [shop_id, id])
			assert_eq(rows[i].sell_price, int(db().item(id).sell_price_mesos), "%s %s sell-back" % [shop_id, id])
			assert_true(int(rows[i].quantity_per_purchase) >= 1)
	assert_eq(ShopService.shops_for_npc(String(db().shop(LUCY).npc_id), db()), PackedStringArray([LUCY]))


func test_buy_charges_price_times_quantity() -> void:
	var c := _rich(1000)
	var price := _price(LUCY, RED_POTION)
	var res := ShopService.buy(c, LUCY, RED_POTION, 7, db())
	assert_true(res.ok, str(res))
	assert_eq(res.cost, 7 * price)
	assert_eq(res.units, 7)
	assert_eq(c.mesos, 1000 - 7 * price)
	assert_eq(res.mesos, c.mesos)
	assert_eq(c.inventory.count(RED_POTION), 7)


func test_buy_exactly_affordable() -> void:
	var price := _price(SID, "558")
	var c := _rich(price)
	assert_true(ShopService.buy(c, SID, "558", 1, db()).ok)
	assert_eq(c.mesos, 0)


func test_insufficient_mesos_changes_nothing() -> void:
	var price := _price(LUCY, RED_POTION)
	var c := _rich(price * 3 - 1)
	var res := ShopService.buy(c, LUCY, RED_POTION, 3, db())
	assert_eq(res.code, ItemCodes.INSUFFICIENT_MESOS)
	assert_eq(c.mesos, price * 3 - 1)
	assert_true(c.inventory.is_empty())
	assert_eq(ItemCodes.message(res), "You do not have enough mesos.")


func test_purchase_into_full_inventory_changes_nothing() -> void:
	var c := _rich()
	c.inventory.set_capacity("use", 1)
	c.inventory.add("237", 1, db())
	var bus: Node = load("res://scripts/autoload/events.gd").new()
	var full: Array = []
	bus.inventory_full.connect(func(id: String) -> void: full.append(id))
	var res := ShopService.buy(c, LUCY, RED_POTION, 1, db(), bus)
	assert_eq(res.code, ItemCodes.INVENTORY_FULL)
	assert_eq(c.mesos, 100000, "no mesos taken")
	assert_eq(c.inventory.count(RED_POTION), 0)
	assert_eq(full, [RED_POTION])
	# A stack that would overflow the last slot is refused too.
	c.inventory.remove("237", 1)
	var max_stack := int(db().item(RED_POTION).max_stack)
	assert_eq(ShopService.buy(c, LUCY, RED_POTION, max_stack + 1, db()).code, ItemCodes.INVENTORY_FULL)
	assert_true(ShopService.buy(c, LUCY, RED_POTION, max_stack, db()).ok)
	bus.free()


func test_equipment_purchases_are_clean_and_unstacked() -> void:
	var c := _rich()
	var top := String(db().shop(PAN).items[0].item_id)
	var res := ShopService.buy(c, PAN, top, 2, db())
	assert_true(res.ok, str(res))
	assert_eq(c.inventory.count(top), 2)
	assert_eq(c.inventory.free_slots("equip"), c.inventory.capacity("equip") - 2)
	assert_eq(c.inventory.get_slot("equip", 0).data, {}, "NPC shop copies always roll clean")


func test_bad_requests() -> void:
	var c := _rich()
	assert_eq(ShopService.buy(c, "nope", RED_POTION, 1, db()).code, ItemCodes.UNKNOWN_SHOP)
	assert_eq(ShopService.buy(c, PAN, RED_POTION, 1, db()).code, ItemCodes.NOT_SOLD_HERE)
	assert_eq(ShopService.buy(c, LUCY, RED_POTION, 0, db()).code, ItemCodes.INVALID_QUANTITY)
	assert_eq(ShopService.buy(c, LUCY, RED_POTION, -2, db()).code, ItemCodes.INVALID_QUANTITY)
	assert_eq(ShopService.sell(c, LUCY, RED_POTION, 0, db()).code, ItemCodes.INVALID_QUANTITY)
	assert_eq(ShopService.sell(c, "nope", RED_POTION, 1, db()).code, ItemCodes.UNKNOWN_SHOP)
	assert_eq(c.mesos, 100000)


func test_quote_buy_does_not_mutate() -> void:
	var c := _rich(500)
	var q := ShopService.quote_buy(c, LUCY, RED_POTION, 2, db())
	assert_true(q.ok)
	assert_eq(c.mesos, 500)
	assert_true(c.inventory.is_empty())


func test_selling_pays_the_canonical_sell_back() -> void:
	var c := _rich(0)
	c.inventory.add("348", 10, db())
	var each := int(db().item("348").sell_price_mesos)
	var res := ShopService.sell(c, LUCY, "348", 4, db())
	assert_true(res.ok, str(res))
	assert_eq(res.total, 4 * each)
	assert_eq(c.mesos, 4 * each)
	assert_eq(c.inventory.count("348"), 6)


func test_sell_back_is_not_the_buy_price() -> void:
	var c := _rich(1000)
	assert_true(ShopService.buy(c, LUCY, RED_POTION, 1, db()).ok)
	var after_buy := c.mesos
	assert_true(ShopService.sell(c, LUCY, RED_POTION, 1, db()).ok)
	assert_eq(c.mesos, after_buy + int(db().item(RED_POTION).sell_price_mesos))
	assert_true(c.mesos < 1000, "buying and selling back loses mesos")


func test_selling_more_than_held_fails() -> void:
	var c := _rich(0)
	c.inventory.add("348", 2, db())
	assert_eq(ShopService.sell(c, LUCY, "348", 3, db()).code, ItemCodes.NOT_ENOUGH_ITEMS)
	assert_eq(c.inventory.count("348"), 2)
	assert_eq(c.mesos, 0)


func test_zero_value_items_follow_the_adaptation_rule() -> void:
	var c := _rich(0)
	c.inventory.add("541", 1, db())
	assert_eq(int(db().item("541").sell_price_mesos), 0)
	var res := ShopService.sell(c, SID, "541", 1, db())
	if bool(db().miso_table("inventory").shop.sell_zero_value_items):
		assert_true(res.ok, str(res))
		assert_eq(c.mesos, 0)
		assert_eq(c.inventory.count("541"), 0)
	else:
		assert_eq(res.code, ItemCodes.ZERO_VALUE_REFUSED)


func test_sale_past_the_meso_cap_is_refused() -> void:
	var c := _rich(Mesos.cap(db()))
	c.inventory.add("348", 1, db())
	assert_eq(ShopService.sell(c, LUCY, "348", 1, db()).code, ItemCodes.MESO_CAP)
	assert_eq(c.inventory.count("348"), 1)


func test_sell_slot_sells_that_instance() -> void:
	var c := _rich(0)
	c.inventory.add("558", 1, db())
	c.inventory.add_instance("558", {"stats": {"watk": 25}}, db())
	var res := ShopService.sell_slot(c, SID, "equip", 1, 1, db())
	assert_true(res.ok, str(res))
	assert_eq(c.mesos, int(db().item("558").sell_price_mesos))
	assert_eq(c.inventory.get_slot("equip", 0).data, {}, "the other copy stays")
	assert_true(c.inventory.get_slot("equip", 1).is_empty())
	assert_eq(ShopService.sell_slot(c, SID, "equip", 5, 1, db()).code, ItemCodes.NOT_ENOUGH_ITEMS)


func test_buy_and_sell_emit_events() -> void:
	var bus: Node = load("res://scripts/autoload/events.gd").new()
	var seen: Array = []
	bus.mesos_changed.connect(func(m: int, d: int) -> void: seen.append(["mesos_changed", m, d]))
	bus.item_gained.connect(func(id: String, q: int) -> void: seen.append(["item_gained", id, q]))
	bus.item_lost.connect(func(id: String, q: int) -> void: seen.append(["item_lost", id, q]))
	var c := _rich(1000)
	var price := _price(LUCY, RED_POTION)
	var sell_back := int(db().item(RED_POTION).sell_price_mesos)
	ShopService.buy(c, LUCY, RED_POTION, 2, db(), bus)
	ShopService.sell(c, LUCY, RED_POTION, 1, db(), bus)
	assert_eq(seen, [
		["mesos_changed", 1000 - 2 * price, -2 * price],
		["item_gained", RED_POTION, 2],
		["item_lost", RED_POTION, 1],
		["mesos_changed", 1000 - 2 * price + sell_back, sell_back],
	])
	bus.free()


func test_huge_quantity_never_wraps_the_cost() -> void:
	# 368934881474191033 x 50 wraps a 64-bit int to 34; the cost must saturate instead, so it is never affordable.
	var price := _price(LUCY, RED_POTION)
	var c := _rich(100)
	var quantity := ShopService.INT64_MAX / price + 1
	var res := ShopService.buy(c, LUCY, RED_POTION, quantity, db())
	assert_eq(res.code, ItemCodes.INSUFFICIENT_MESOS)
	assert_eq(res.cost, ShopService.INT64_MAX)
	assert_eq(c.mesos, 100)
	assert_true(c.inventory.is_empty())


## Contract C6: the canonical requirements these tests prove.
func parity_keys() -> Dictionary:
	var shops: Array = ["shop:maple-road-pan", "shop:maple-road-sid", "shop:maple-road-lucy"]
	return {
		"test_stock_is_canonical_data_in_display_order": shops,
		"test_selling_pays_the_canonical_sell_back": shops,
		"test_buy_charges_price_times_quantity": shops,
	}
