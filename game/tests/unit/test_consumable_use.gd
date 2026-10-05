extends TestCase
## Consumables: canonical HP/MP restore, clamped to StatCalculator.max_hp / max_mp, one unit consumed, persisted, and
## Events.item_used emitted through ItemService. Amounts are read from the canonical items, never typed in.

const RED_POTION := "270"
const ORANGE := "239"
const ROGERS_APPLE := "235"


func _char(hp: int = 10, mp: int = 0) -> CharacterState:
	var c := CharacterState.new()
	c.base_max_hp = 1000
	c.base_max_mp = 1000
	c.hp = hp
	c.mp = mp
	return c


func _restore(item_id: String, key: String) -> int:
	return int(db().item(item_id).consumable.get(key, 0))


func test_potion_restores_documented_hp_and_decrements() -> void:
	var c := _char(10)
	c.inventory.add(RED_POTION, 3, db())
	var res := Consumables.use(c, RED_POTION, db())
	assert_true(res.ok, str(res))
	assert_eq(res.hp_gained, _restore(RED_POTION, "hp_restore"))
	assert_eq(c.hp, 10 + _restore(RED_POTION, "hp_restore"))
	assert_eq(c.inventory.count(RED_POTION), 2)


func test_hp_is_clamped_to_max_hp() -> void:
	var c := _char()
	var max_hp := StatCalculator.max_hp(c, db())
	c.hp = max_hp - 7
	c.inventory.add(RED_POTION, 1, db())
	var res := Consumables.use(c, RED_POTION, db())
	assert_true(res.ok)
	assert_eq(c.hp, max_hp)
	assert_eq(res.hp_gained, 7)
	assert_eq(res.max_hp, max_hp)
	assert_eq(c.inventory.count(RED_POTION), 0, "the last one is used up")


func test_full_hp_still_consumes_the_potion() -> void:
	var c := _char()
	c.hp = StatCalculator.max_hp(c, db())
	c.inventory.add(RED_POTION, 1, db())
	var res := Consumables.use(c, RED_POTION, db())
	assert_true(res.ok)
	assert_eq(res.hp_gained, 0)
	assert_eq(c.inventory.count(RED_POTION), 0)


func test_mp_item_restores_mp_and_respects_max_mp() -> void:
	var c := _char(10, 0)
	c.inventory.add(ORANGE, 2, db())
	assert_true(Consumables.use(c, ORANGE, db()).ok)
	assert_eq(c.mp, _restore(ORANGE, "mp_restore"))
	assert_eq(c.hp, 10, "an MP item leaves HP alone")
	c.mp = StatCalculator.max_mp(c, db()) - 1
	assert_true(Consumables.use(c, ORANGE, db()).ok)
	assert_eq(c.mp, StatCalculator.max_mp(c, db()))


func test_rogers_apple_works() -> void:
	var c := _char(1)
	c.inventory.add(ROGERS_APPLE, 1, db())
	var res := Consumables.use(c, ROGERS_APPLE, db())
	assert_true(res.ok, str(res))
	assert_eq(c.hp, 1 + _restore(ROGERS_APPLE, "hp_restore"))
	assert_eq(c.inventory.count(ROGERS_APPLE), 0)


func test_every_potion_and_food_lucy_sells_works() -> void:
	var rows: Array = db().shop("maple-road-lucy").items
	var checked := 0
	for row in rows:
		if not (String(row.item_subtype) in ["Potion", "Food"]):
			continue
		var id := String(row.item_id)
		var c := _char(1, 0)
		c.inventory.add(id, 1, db())
		var res := Consumables.use(c, id, db())
		assert_true(res.ok, "%s: %s" % [id, res])
		assert_eq(res.hp_gained, _restore(id, "hp_restore"), "%s hp" % id)
		assert_eq(res.mp_gained, _restore(id, "mp_restore"), "%s mp" % id)
		assert_true(int(res.hp_gained) + int(res.mp_gained) > 0, "%s restores something" % id)
		assert_eq(c.inventory.count(id), 0)
		checked += 1
	assert_true(checked > 0, "Lucy sells potions and food")


func test_items_that_cannot_be_used() -> void:
	var c := _char()
	for id in ["269", "59", "541", "348", "522"]:   # pet food, scroll, weapon, etc, chair
		c.inventory.add(id, 1, db())
		var res := Consumables.use(c, id, db())
		assert_eq(res.code, ItemCodes.NOT_USABLE, id)
		assert_eq(c.inventory.count(id), 1, "%s not consumed" % id)
	# The chair is not a consumable, but it is usable: ItemService.use_item sits on it (Chairs.use, test_chairs_use.gd)
	# instead of refusing it, and never consumes it.
	assert_true(ItemDef.of("522", db()).is_chair(), "522 is a chair")
	var chair_use := ItemService.new(c, db()).use_item("522")
	assert_ne(chair_use.code, ItemCodes.NOT_USABLE, "ItemService does not refuse the chair as unusable: %s" % chair_use)
	assert_eq(c.inventory.count("522"), 1, "the chair is never consumed")
	assert_eq(Consumables.use(c, RED_POTION, db()).code, ItemCodes.NOT_ENOUGH_ITEMS)
	assert_eq(Consumables.use(c, "nope", db()).code, ItemCodes.UNKNOWN_ITEM)


func test_dead_characters_cannot_use_items() -> void:
	var c := _char(0)
	c.inventory.add(RED_POTION, 1, db())
	assert_eq(Consumables.use(c, RED_POTION, db()).code, ItemCodes.DEAD)
	assert_eq(c.inventory.count(RED_POTION), 1)


func test_use_persists_through_save_round_trip() -> void:
	var c := _char(10)
	c.inventory.add(RED_POTION, 5, db())
	Consumables.use(c, RED_POTION, db())
	var back := CharacterState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_eq(back.inventory.count(RED_POTION), 4)
	assert_eq(back.hp, c.hp)


func test_service_emits_item_used() -> void:
	var bus: Node = load("res://scripts/autoload/events.gd").new()
	var seen: Array = []
	bus.item_used.connect(func(id: String) -> void: seen.append(["item_used", id]))
	bus.item_lost.connect(func(id: String, q: int) -> void: seen.append(["item_lost", id, q]))
	bus.inventory_changed.connect(func() -> void: seen.append(["inventory_changed"]))
	bus.hp_changed.connect(func(hp: int, max_hp: int) -> void: seen.append(["hp_changed", hp, max_hp]))
	bus.mp_changed.connect(func(mp: int, max_mp: int) -> void: seen.append(["mp_changed", mp, max_mp]))
	var c := _char(10)
	c.inventory.add(RED_POTION, 1, db())
	var s := ItemService.new(c, db(), bus)
	var res := s.use_item(RED_POTION)
	assert_true(res.ok)
	assert_eq(seen, [["item_used", RED_POTION], ["item_lost", RED_POTION, 1], ["inventory_changed"],
		["hp_changed", c.hp, StatCalculator.max_hp(c, db())]])
	seen.clear()
	assert_false(s.use_item(RED_POTION).ok)
	assert_eq(seen, [], "a failed use emits nothing")
	bus.free()
