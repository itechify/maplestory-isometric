extends TestCase
## Inventory: tabs from canonical categories, stacking to the canonical max stack, overflow into new slots, full
## tabs, removal, slot moves, and the lossless to_dict/from_dict round trip.

const RED_POTION := "270"   # Use / Potion, max stack 100 (canonical)
const SNAIL_SHELL := "348"  # Etc / Monster Drop, max stack 200
const SWORD := "541"        # Equip / One-Handed Sword, no canonical stack size -> equipment_max_stack
const RELAXER := "522"      # Setup chair, max stack 1


func _stack(item_id: String) -> int:
	return int(db().item(item_id).max_stack)


func test_tabs_match_the_brief() -> void:
	assert_eq(Inventory.TABS, PackedStringArray(["equip", "use", "setup", "etc", "cash"]))


func test_default_capacity_comes_from_adaptation_table() -> void:
	var inv := Inventory.new()
	var slots: Dictionary = db().miso_table("inventory").tab_slots
	for tab in Inventory.TABS:
		assert_eq(inv.capacity(tab), int(slots[tab]), "capacity %s" % tab)
		assert_eq(inv.free_slots(tab), int(slots[tab]), "free %s" % tab)


func test_items_land_in_their_canonical_tab() -> void:
	var inv := Inventory.new()
	for id in [RED_POTION, SNAIL_SHELL, SWORD, RELAXER]:
		assert_eq(inv.add(id, 1, db()), 1, "add %s" % id)
		var at := inv.find(id)
		assert_eq(at.get("tab", ""), String(db().item(id).inventory_tab), "tab of %s" % id)


func test_add_and_count_and_remove() -> void:
	var inv := Inventory.new()
	assert_eq(inv.add(RED_POTION, 5, db()), 5)
	assert_eq(inv.count(RED_POTION), 5)
	assert_eq(inv.remove(RED_POTION, 2), 2)
	assert_eq(inv.count(RED_POTION), 3)
	assert_eq(inv.remove(RED_POTION, 10), 3, "remove more than held removes what there is")
	assert_eq(inv.count(RED_POTION), 0)
	assert_true(inv.is_empty())
	assert_eq(inv.free_slots("use"), inv.capacity("use"), "slot freed when stack empties")


func test_stacking_fills_one_slot_up_to_max_stack() -> void:
	var inv := Inventory.new()
	var max_stack := _stack(RED_POTION)
	inv.add(RED_POTION, 1, db())
	inv.add(RED_POTION, max_stack - 1, db())
	assert_eq(inv.get_slot("use", 0).qty, max_stack, "first stack full")
	assert_eq(inv.free_slots("use"), inv.capacity("use") - 1, "only one slot used")


func test_stack_overflow_opens_new_slots() -> void:
	var inv := Inventory.new()
	var max_stack := _stack(SNAIL_SHELL)
	assert_eq(inv.add(SNAIL_SHELL, max_stack * 2 + 7, db()), max_stack * 2 + 7)
	assert_eq(inv.get_slot("etc", 0).qty, max_stack)
	assert_eq(inv.get_slot("etc", 1).qty, max_stack)
	assert_eq(inv.get_slot("etc", 2).qty, 7)
	assert_eq(inv.count(SNAIL_SHELL), max_stack * 2 + 7)


func test_equipment_never_stacks() -> void:
	var inv := Inventory.new()
	assert_eq(inv.add(SWORD, 3, db()), 3)
	assert_eq(int(db().miso_table("inventory").equipment_max_stack), 1)
	for i in 3:
		assert_eq(inv.get_slot("equip", i).qty, 1, "slot %d" % i)
	assert_eq(inv.free_slots("equip"), inv.capacity("equip") - 3)


func test_full_tab_adds_nothing_and_reports_partial() -> void:
	var inv := Inventory.new()
	inv.set_capacity("use", 2)
	var max_stack := _stack(RED_POTION)
	assert_true(inv.can_add(RED_POTION, max_stack * 2, db()))
	assert_false(inv.can_add(RED_POTION, max_stack * 2 + 1, db()))
	assert_eq(inv.add(RED_POTION, max_stack * 2 + 5, db()), max_stack * 2, "adds only what fits")
	assert_true(inv.is_full("use"))
	assert_eq(inv.add(RED_POTION, 1, db()), 0, "full tab adds nothing")
	assert_false(inv.can_add(RED_POTION, 1, db()))
	assert_true(inv.can_add(SNAIL_SHELL, 1, db()), "other tabs are unaffected")


func test_full_tab_still_tops_up_existing_stack() -> void:
	var inv := Inventory.new()
	inv.set_capacity("use", 1)
	inv.add(RED_POTION, 10, db())
	assert_true(inv.is_full("use"))
	assert_true(inv.can_add(RED_POTION, _stack(RED_POTION) - 10, db()))
	assert_eq(inv.add(RED_POTION, 5, db()), 5)
	assert_eq(inv.count(RED_POTION), 15)


func test_unknown_items_and_bad_quantities() -> void:
	var inv := Inventory.new()
	assert_eq(inv.add("no-such-item", 1, db()), 0)
	assert_false(inv.can_add("no-such-item", 1, db()))
	assert_eq(inv.add(RED_POTION, 0, db()), 0)
	assert_eq(inv.add(RED_POTION, -3, db()), 0)
	assert_false(inv.can_add(RED_POTION, -1, db()))
	assert_eq(inv.remove(RED_POTION, -1), 0)


func test_can_add_all_accepts_qty_and_count_keys() -> void:
	var inv := Inventory.new()
	inv.set_capacity("use", 1)
	var max_stack := _stack(RED_POTION)
	assert_true(inv.can_add_all([{"item_id": RED_POTION, "qty": max_stack}, {"item_id": SNAIL_SHELL, "count": 3}], db()))
	assert_false(inv.can_add_all([{"item_id": RED_POTION, "qty": max_stack}, {"item_id": "237", "count": 3}], db()),
		"two Use items need two slots")
	assert_false(inv.can_add_all([{"item_id": RED_POTION, "qty": max_stack}, {"item_id": RED_POTION, "qty": 1}], db()),
		"entries for the same item accumulate")
	assert_true(inv.is_empty(), "can_add_all never mutates")


func test_move_merge_and_swap() -> void:
	var inv := Inventory.new()
	var max_stack := _stack(RED_POTION)
	inv.add(RED_POTION, max_stack + 30, db())   # slot 0 full, slot 1 = 30
	inv.add("237", 4, db())                      # slot 2 eggs
	assert_true(inv.move("use", 1, 5))
	assert_true(inv.get_slot("use", 1).is_empty())
	assert_eq(inv.get_slot("use", 5).qty, 30)
	inv.remove_at("use", 0, 50)                  # slot 0 = max - 50
	assert_true(inv.move("use", 5, 0, db()), "merge onto the same item")
	assert_eq(inv.get_slot("use", 0).qty, max_stack - 20)
	assert_true(inv.get_slot("use", 5).is_empty())
	assert_true(inv.move("use", 2, 0, db()), "different items swap")
	assert_eq(inv.get_slot("use", 0).item_id, "237")
	assert_eq(inv.get_slot("use", 2).item_id, RED_POTION)
	assert_true(inv.swap("use", 0, 2))
	assert_eq(inv.get_slot("use", 0).item_id, RED_POTION)
	assert_false(inv.move("use", 9, 0), "empty source")
	assert_false(inv.move("use", 0, 999), "out of range")
	assert_eq(inv.count(RED_POTION), max_stack - 20)


func test_instance_data_is_kept_and_never_merged() -> void:
	var inv := Inventory.new()
	var idx := inv.add_instance(SWORD, {"stats": {"watk": 19}}, db())
	assert_eq(idx, 0)
	assert_eq(inv.get_slot("equip", 0).data, {"stats": {"watk": 19}})
	inv.add(SWORD, 1, db())
	assert_eq(inv.remove(SWORD, 1), 1)
	assert_eq(inv.count(SWORD), 1)
	assert_eq(inv.get_slot("equip", 0).data, {"stats": {"watk": 19}}, "clean copies are removed first")


func _populated() -> Inventory:
	var inv := Inventory.new()
	inv.set_capacity("etc", 30)
	inv.add(RED_POTION, 130, db())
	inv.add(SNAIL_SHELL, 7, db())
	inv.add(SWORD, 2, db())
	inv.add_instance("585", {"stats": {"watk": 20}, "upgrades_used": 1}, db())
	inv.add(RELAXER, 1, db())
	inv.move("use", 1, 9)
	return inv


func test_to_dict_round_trip_is_lossless() -> void:
	var inv := _populated()
	var d := inv.to_dict()
	var back := Inventory.from_dict(d)
	assert_eq(back.to_dict(), d)
	assert_eq(back.capacity("etc"), 30)
	assert_eq(back.get_slot("use", 9).qty, 30)
	assert_eq(back.get_slot("equip", 2).data, {"stats": {"watk": 20}, "upgrades_used": 1})


func test_to_dict_survives_json() -> void:
	var inv := _populated()
	var d := inv.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d))
	var back := Inventory.from_dict(parsed)
	assert_eq(JSON.stringify(back.to_dict()), JSON.stringify(d))
	assert_eq(back.count(RED_POTION), 130)
	assert_eq(typeof(back.get_slot("use", 0).qty), TYPE_INT, "JSON floats become ints")


func test_from_empty_dict_is_a_fresh_inventory() -> void:
	var inv := Inventory.from_dict({})
	assert_true(inv.is_empty())
	assert_eq(inv.capacity("use"), Inventory.new().capacity("use"))


func test_from_dict_never_drops_items_past_capacity() -> void:
	var back := Inventory.from_dict({"capacity": {"use": 2}, "slots": {"use": [{"index": 5, "item_id": RED_POTION, "qty": 3}]}})
	assert_eq(back.count(RED_POTION), 3)
	assert_true(back.capacity("use") >= 6)


func test_character_state_round_trip_keeps_inventory() -> void:
	var c := CharacterState.new()
	c.inventory = _populated()
	var back := CharacterState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_eq(back.inventory.to_dict(), c.inventory.to_dict())


func test_id_of_normalizes_untrusted_ids() -> void:
	assert_eq(ItemDef.id_of("270"), "270")
	assert_eq(ItemDef.id_of(270), "270")
	assert_eq(ItemDef.id_of(270.0), "270", "JSON's float form of an id")
	assert_eq(ItemDef.id_of(&"270"), "270")
	assert_eq(ItemDef.id_of(null), "")
	assert_eq(ItemDef.id_of("0000001"), "0000001", "string ids keep their padding")


func test_from_dict_accepts_numeric_ids() -> void:
	var back := Inventory.from_dict(JSON.parse_string('{"slots": {"use": [{"index": 0, "item_id": 270, "qty": 3}]}}'))
	assert_eq(back.count(RED_POTION), 3, "a save with a numeric id still loads")
	assert_eq(back.get_slot("use", 0).item_id, RED_POTION)


func test_from_dict_skips_garbage_without_crashing() -> void:
	var back := Inventory.from_dict({"capacity": {"use": "x"}, "slots": {"use": ["junk", {"item_id": RED_POTION,
		"qty": 0}, {"qty": 4}, {"item_id": RED_POTION, "qty": 2}], "etc": "junk", "bogus": [{"item_id": SNAIL_SHELL,
		"qty": 1}]}})
	assert_eq(back.count(RED_POTION), 2, "only the valid entry is restored")
	assert_eq(back.count(SNAIL_SHELL), 0, "a tab outside TABS cannot hold items")


func test_clear_empties_tabs_and_reports_what_was_removed() -> void:
	var inv := _populated()
	var etc_cap := inv.capacity("etc")
	var removed_use := inv.clear("use")
	assert_eq(removed_use, {RED_POTION: 130})
	assert_eq(inv.count(RED_POTION), 0)
	assert_eq(inv.count(SNAIL_SHELL), 7, "other tabs untouched")
	var removed := inv.clear()
	assert_eq(removed.get(SNAIL_SHELL), 7)
	assert_eq(removed.get(SWORD), 2)
	assert_true(inv.is_empty())
	assert_eq(inv.capacity("etc"), etc_cap, "capacities are kept")
