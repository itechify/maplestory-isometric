extends TestCase
## ItemService: the seam that mutates a CharacterState and emits the Events item signals. The bus is a fresh instance
## of the real events.gd (same signal signatures as the autoload), freed after each test.

var bus: Node
var emitted: Array = []


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	emitted = []
	for sig in ["item_gained", "item_lost", "item_used", "inventory_changed", "inventory_full", "equipment_changed",
			"stats_changed", "hp_changed", "mp_changed", "mesos_changed"]:
		bus.connect(sig, _record.bind(sig))


func after_each() -> void:
	if is_instance_valid(bus):
		bus.free()


## Signals pass their own arguments first, then the bound name; unbind the variable part through an Array.
func _record(a0: Variant = null, a1: Variant = null, a2: Variant = null) -> void:
	var args: Array = [a0, a1, a2].filter(func(v: Variant) -> bool: return v != null)
	var sig: String = args.pop_back()
	emitted.append([sig] + args)


func _names() -> Array:
	return emitted.map(func(e: Array) -> String: return e[0])


func _service() -> ItemService:
	return ItemService.new(CharacterState.new(), db(), bus)


func test_gain_emits_item_gained_and_inventory_changed() -> void:
	var s := _service()
	assert_eq(s.gain("270", 3), 3)
	assert_eq(emitted, [["item_gained", "270", 3], ["inventory_changed"]])
	assert_eq(s.character.inventory.count("270"), 3)


func test_gain_into_full_tab_emits_inventory_full() -> void:
	var s := _service()
	s.character.inventory.set_capacity("use", 1)
	var max_stack := int(db().item("270").max_stack)
	assert_eq(s.gain("270", max_stack + 4), max_stack)
	assert_eq(_names(), ["item_gained", "inventory_changed", "inventory_full"])
	assert_eq(emitted[0], ["item_gained", "270", max_stack], "reports the quantity actually added")
	emitted.clear()
	assert_eq(s.gain("270", 1), 0)
	assert_eq(emitted, [["inventory_full", "270"]])


func test_lose_emits_item_lost() -> void:
	var s := _service()
	s.gain("348", 5)
	emitted.clear()
	assert_eq(s.lose("348", 2), 2)
	assert_eq(emitted, [["item_lost", "348", 2], ["inventory_changed"]])
	emitted.clear()
	assert_eq(s.lose("999999", 1), 0)
	assert_eq(emitted, [], "nothing removed, nothing emitted")


func test_gain_all_is_atomic() -> void:
	var s := _service()
	s.character.inventory.set_capacity("use", 1)
	assert_false(s.gain_all([{"item_id": "237", "count": 3}, {"item_id": "270", "count": 1}]))
	assert_true(s.character.inventory.is_empty(), "nothing added when not everything fits")
	assert_eq(_names(), ["inventory_full"])
	emitted.clear()
	assert_true(s.gain_all([{"item_id": "237", "count": 3}, {"item_id": "348", "qty": 2}]))
	assert_eq(s.character.inventory.count("237"), 3)
	assert_eq(s.character.inventory.count("348"), 2)


func test_lose_all_is_atomic() -> void:
	var s := _service()
	s.gain("349", 10)
	s.gain("356", 1)
	assert_false(s.lose_all([{"item_id": "349", "count": 10}, {"item_id": "356", "count": 2}]))
	assert_eq(s.character.inventory.count("349"), 10, "nothing removed when any item is short")
	assert_true(s.lose_all([{"item_id": "349", "count": 10}, {"item_id": "356", "count": 1}]))
	assert_true(s.character.inventory.is_empty())


func test_pickup_items_is_all_or_nothing() -> void:
	var s := _service()
	s.character.inventory.set_capacity("etc", 1)
	var max_stack := int(db().item("348").max_stack)
	assert_true(s.pickup({"kind": "item", "item_id": "348", "qty": max_stack - 1}).ok)
	emitted.clear()
	var res := s.pickup({"kind": "item", "item_id": "348", "qty": 2})
	assert_eq(res.code, ItemCodes.INVENTORY_FULL)
	assert_eq(s.character.inventory.count("348"), max_stack - 1, "a drop that does not fit stays on the ground")
	assert_eq(emitted, [["inventory_full", "348"]])
	assert_eq(s.pickup({"kind": "item", "item_id": "nope", "qty": 1}).code, ItemCodes.UNKNOWN_ITEM)


func test_pickup_mesos() -> void:
	var s := _service()
	var res := s.pickup({"kind": "mesos", "amount": 7})
	assert_true(res.ok)
	assert_eq(s.character.mesos, 7)
	assert_eq(emitted, [["mesos_changed", 7, 7]])


func test_move_emits_inventory_changed() -> void:
	var s := _service()
	s.gain("270", 1)
	emitted.clear()
	assert_true(s.move("use", 0, 4))
	assert_eq(emitted, [["inventory_changed"]])


func test_silent_without_a_bus() -> void:
	var s := ItemService.new(CharacterState.new(), db())
	assert_eq(s.gain("270", 2), 2)
	assert_eq(s.lose("270", 1), 1)
	assert_eq(s.gain_mesos(5), 5)
	assert_eq(emitted, [])


func test_pickup_accepts_every_drop_record_shape() -> void:
	var s := _service()
	# MapInstanceState shape: an item record that also carries a "mesos" key is still an item.
	assert_eq(s.pickup({"item_id": "270", "amount": 2, "mesos": 0}).code, ItemCodes.OK)
	assert_eq(s.character.inventory.count("270"), 2)
	assert_eq(s.character.mesos, 0, "an item record never turns into mesos")
	# Meso records: {"mesos": n}, {"mesos": true, "amount": n}, DropRoller's {"kind": "mesos", "amount": n}.
	assert_true(s.pickup({"mesos": 5}).ok)
	assert_true(s.pickup({"mesos": true, "amount": 7}).ok)
	assert_true(s.pickup({"kind": "mesos", "amount": 3}).ok)
	assert_eq(s.character.mesos, 15)
	# DropRoller item output and JSON-parsed records (float quantities, numeric ids).
	assert_true(s.pickup({"kind": "item", "item_id": "348", "qty": 2}).ok)
	assert_true(s.pickup(JSON.parse_string('{"item_id": 348, "amount": 1}')).ok)
	assert_eq(s.character.inventory.count("348"), 3)
	assert_eq(s.pickup({"mesos": null}).code, ItemCodes.INVALID_QUANTITY, "a malformed bag is refused, not a crash")


func test_unknown_item_is_not_reported_as_a_full_inventory() -> void:
	var s := _service()
	assert_eq(s.gain("no-such-item", 1), 0)
	assert_false(s.gain_all([{"item_id": "no-such-item", "qty": 1}, {"item_id": "270", "qty": 1}]))
	assert_eq(emitted, [], "no inventory_full for a bad id")
	assert_true(s.character.inventory.is_empty())


func test_malformed_entries_change_nothing() -> void:
	var s := _service()
	s.gain("270", 3)
	emitted.clear()
	assert_false(s.gain_all([{"item_id": "270", "qty": 1}, "junk"]))
	assert_false(s.lose_all([{"item_id": "270", "qty": 1}, 42]))
	assert_false(s.lose_all([{"item_id": "270", "qty": -1}]), "a negative hand-in is refused")
	assert_eq(s.character.inventory.count("270"), 3)
	assert_eq(emitted, [])


func test_clear_inventory_emits_item_lost_per_item() -> void:
	var s := _service()
	s.gain("270", 4)
	s.gain("348", 2)
	emitted.clear()
	assert_eq(s.clear_inventory(), {"270": 4, "348": 2})
	assert_eq(emitted, [["item_lost", "270", 4], ["item_lost", "348", 2], ["inventory_changed"]])
	emitted.clear()
	assert_eq(s.clear_inventory(), {})
	assert_eq(emitted, [], "clearing an empty inventory emits nothing")
