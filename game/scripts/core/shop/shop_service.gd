class_name ShopService
extends RefCounted
## NPC shops, data only: stock, buy prices and bundle sizes come from data/canonical/shops/<shop id>.json (MeowDB
## /npc-shops), sell-back from each item's canonical sell_price_mesos. No shop content lives in code or UI.
##
##   ShopService.stock("maple-road-lucy", db)                       rows for the shop window
##   ShopService.buy(character, "maple-road-lucy", "270", 10, db, Events)
##   ShopService.sell(character, "maple-road-lucy", "348", 5, db, Events)
##   ShopService.sell_slot(character, "maple-road-sid", "equip", 3, 1, db, Events)
##
## Every call returns {"ok", "code", ...} (ItemCodes); failures change nothing. Mutations go through ItemService, so
## mesos_changed / item_gained / item_lost / inventory_changed fire on the bus passed in (null = silent).
##
## Rules (shops.md): `price_mesos` buys `quantity_per_purchase` units (1 on every Maple Island row), so `quantity`
## here counts purchases (bundles) and the cost is quantity x price. MeowDB documents no per-purchase cap, no stock
## limit and no sell restrictions; what a 0-value sale does is an adaptation (inventory.json shop section).

const INT64_MAX := 9223372036854775807


## True if the shop exists in canonical data.
static func exists(shop_id: String, db: ContentDB) -> bool:
	return db.has("shops", shop_id)


## The shop's rows in display order: {"position", "item_id", "name", "price", "quantity_per_purchase",
## "max_per_stack", "sell_price", "sell_basis", "citizen_req", "stock_limit"} (prices in mesos, ints; -1 = none).
static func stock(shop_id: String, db: ContentDB) -> Array:
	var out: Array = []
	for row in db.shop(shop_id).get("items", []):
		out.append(_row(row))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.position) < int(b.position))
	return out


## The first row selling `item_id`, or {}.
static func row_for(shop_id: String, item_id: String, db: ContentDB) -> Dictionary:
	for row in stock(shop_id, db):
		if String(row.item_id) == item_id:
			return row
	return {}


## Ids of the shops an NPC runs (canonical npc_id).
static func shops_for_npc(npc_id: String, db: ContentDB) -> PackedStringArray:
	var out: PackedStringArray = []
	for id in db.ids("shops"):
		if String(db.shop(id).get("npc_id", "")) == npc_id:
			out.append(id)
	return out


## Mesos one purchase of `row` costs this character. Hook for the citizenship discount (MeowDB /citizenship: only in
## the active citizenship town, Henesys or Kerning City); no Maple Island row is eligible, so it is the base price.
static func price_for(row: Dictionary, _character: CharacterState, _shop_id: String, _db: ContentDB) -> int:
	return int(row.get("price", 0))


## Checks a purchase without changing anything. Same result shape and codes as buy().
static func quote_buy(character: CharacterState, shop_id: String, item_id: String, quantity: int,
		db: ContentDB) -> Dictionary:
	if not exists(shop_id, db):
		return ItemCodes.result(ItemCodes.UNKNOWN_SHOP, {"shop_id": shop_id})
	var row := row_for(shop_id, item_id, db)
	if row.is_empty():
		return ItemCodes.result(ItemCodes.NOT_SOLD_HERE, {"shop_id": shop_id, "item_id": item_id})
	if not db.has("items", item_id):
		return ItemCodes.result(ItemCodes.UNKNOWN_ITEM, {"shop_id": shop_id, "item_id": item_id})
	var limit: Variant = ItemsConfig.shop_rule("max_bundles_per_purchase", db)
	if quantity < 1 or (limit != null and quantity > int(limit)):
		return ItemCodes.result(ItemCodes.INVALID_QUANTITY, {"shop_id": shop_id, "item_id": item_id,
			"quantity": quantity})
	# Saturating products: an absurd quantity must read as unaffordable / not fitting, never wrap to a small cost.
	var units := _mul_sat(quantity, int(row.quantity_per_purchase))
	var price := maxi(0, price_for(row, character, shop_id, db))
	var cost := _mul_sat(quantity, price)
	var details := {"shop_id": shop_id, "item_id": item_id, "quantity": quantity, "units": units, "price": price,
		"cost": cost, "mesos": character.mesos}
	if row.citizen_req != null:
		details["required"] = row.citizen_req
		return ItemCodes.result(ItemCodes.CITIZENSHIP_REQUIRED, details)
	if not Mesos.can_afford(character, cost):
		return ItemCodes.result(ItemCodes.INSUFFICIENT_MESOS, details)
	if not character.inventory.can_add(item_id, units, db):
		return ItemCodes.result(ItemCodes.INVENTORY_FULL, details)
	return ItemCodes.result(ItemCodes.OK, details)


## Buys `quantity` purchases of a row: spends quantity x price and adds quantity x quantity_per_purchase units.
## Result: {"ok", "code", "shop_id", "item_id", "quantity", "units", "price", "cost", "mesos"}. Codes: unknown_shop,
## not_sold_here, unknown_item, invalid_quantity, citizenship_required, insufficient_mesos, inventory_full.
## Equipment bought from an NPC is clean (MeowDB: "NPC shop copies always roll clean"): empty instance data.
static func buy(character: CharacterState, shop_id: String, item_id: String, quantity: int, db: ContentDB,
		bus: Object = null) -> Dictionary:
	var res := quote_buy(character, shop_id, item_id, quantity, db)
	if not res.ok:
		if res.code == ItemCodes.INVENTORY_FULL and bus != null and bus.has_signal(&"inventory_full"):
			bus.emit_signal(&"inventory_full", item_id)
		return res
	var items := ItemService.new(character, db, bus)
	items.spend_mesos(int(res.cost))
	items.gain(item_id, int(res.units))
	res["mesos"] = character.mesos
	return res


## Canonical NPC sell-back of one unit (per_unit) or one item (per_item), or -1 when MeowDB has no value.
static func sell_price(item_id: String, db: ContentDB) -> int:
	var def := ItemDef.of(item_id, db)
	return -1 if def == null else def.sell_price


## Checks a sale of `quantity` units of `item_id` from the inventory without changing anything.
static func quote_sell(character: CharacterState, shop_id: String, item_id: String, quantity: int,
		db: ContentDB) -> Dictionary:
	if not exists(shop_id, db):
		return ItemCodes.result(ItemCodes.UNKNOWN_SHOP, {"shop_id": shop_id})
	var def := ItemDef.of(item_id, db)
	if def == null:
		return ItemCodes.result(ItemCodes.UNKNOWN_ITEM, {"shop_id": shop_id, "item_id": item_id})
	if quantity < 1:
		return ItemCodes.result(ItemCodes.INVALID_QUANTITY, {"shop_id": shop_id, "item_id": item_id,
			"quantity": quantity})
	var details := {"shop_id": shop_id, "item_id": item_id, "quantity": quantity, "price": def.sell_price,
		"basis": def.sell_basis, "total": 0, "mesos": character.mesos}
	if character.inventory.count(item_id) < quantity:
		return ItemCodes.result(ItemCodes.NOT_ENOUGH_ITEMS, details)
	if def.sell_price < 0:
		return ItemCodes.result(ItemCodes.NO_SELL_PRICE, details)
	if def.sell_price == 0 and ItemsConfig.shop_rule("sell_zero_value_items", db) != true:
		return ItemCodes.result(ItemCodes.ZERO_VALUE_REFUSED, details)
	# per_unit: price per unit of a stack; per_item: price per (unstackable) item. Either way one unit = one price.
	var total := _mul_sat(def.sell_price, quantity)
	details["total"] = total
	if not Mesos.can_add(character, total, db):
		return ItemCodes.result(ItemCodes.MESO_CAP, details)
	return ItemCodes.result(ItemCodes.OK, details)


## Sells `quantity` units of `item_id` (taken last slot first, clean copies before ones with instance data).
## Result: {"ok", "code", "shop_id", "item_id", "quantity", "price", "basis", "total", "mesos"}. Codes: unknown_shop,
## unknown_item, invalid_quantity, not_enough_items, no_sell_price, zero_value_refused, meso_cap.
static func sell(character: CharacterState, shop_id: String, item_id: String, quantity: int, db: ContentDB,
		bus: Object = null) -> Dictionary:
	var res := quote_sell(character, shop_id, item_id, quantity, db)
	if not res.ok:
		return res
	var items := ItemService.new(character, db, bus)
	items.lose(item_id, quantity)
	items.gain_mesos(int(res.total))
	res["mesos"] = character.mesos
	return res


## Sells from one inventory slot (the shop window's selected slot; keeps the right equipment instance).
static func sell_slot(character: CharacterState, shop_id: String, tab: String, index: int, quantity: int,
		db: ContentDB, bus: Object = null) -> Dictionary:
	var slot := character.inventory.get_slot(tab, index)
	if slot.is_empty():
		return ItemCodes.result(ItemCodes.NOT_ENOUGH_ITEMS, {"shop_id": shop_id, "tab": tab, "index": index})
	var item_id := String(slot.item_id)
	var res := quote_sell(character, shop_id, item_id, quantity, db)
	if res.ok and int(slot.qty) < quantity:
		res = ItemCodes.result(ItemCodes.NOT_ENOUGH_ITEMS, res)
	if not res.ok:
		return res
	var items := ItemService.new(character, db, bus)
	items.lose_at(tab, index, quantity)
	items.gain_mesos(int(res.total))
	res["mesos"] = character.mesos
	return res


## a x b for non-negative ints, clamped at the int64 maximum instead of wrapping.
static func _mul_sat(a: int, b: int) -> int:
	if a <= 0 or b <= 0:
		return 0
	if a > INT64_MAX / b:
		return INT64_MAX
	return a * b


static func _row(row: Dictionary) -> Dictionary:
	return {
		"position": int(row.get("position", 0)),
		"item_id": String(row.get("item_id", "")),
		"name": String(row.get("name", "")),
		"price": int(row.get("price_mesos", 0)),
		"quantity_per_purchase": maxi(1, int(row.get("quantity_per_purchase", 1) if row.get("quantity_per_purchase") != null else 1)),
		"max_per_stack": -1 if row.get("max_per_stack") == null else int(row.get("max_per_stack")),
		"sell_price": -1 if row.get("sell_price_mesos") == null else int(row.get("sell_price_mesos")),
		"sell_basis": "" if row.get("sell_price_basis") == null else String(row.get("sell_price_basis")),
		"citizen_req": row.get("citizen_req"),
		"stock_limit": row.get("stock_limit"),
	}
