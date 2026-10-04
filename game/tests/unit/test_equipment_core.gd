extends TestCase
## Equipment: equip from the inventory, swaps, unequip, requirement failures (level, job, total stats, fame, gender),
## overall <-> top/bottom and two-handed <-> shield conflicts, total_bonuses, StatCalculator integration, round trips.
##
## The Maple Island item set has no overall and no shield, so the conflict tests add two clearly synthetic items
## ("test-overall", "test-shield") to a private copy of the content; the shared db() is never modified.

const SWORD := "541"         # One-Handed Sword, no requirements
const CLUB := "585"          # One-Handed Blunt Weapon, no requirements
const RAZOR := "558"         # Dagger, level 5
const LONG_SWORD := "543"    # level 10, STR 20
const WOODEN_SWORD := "608"  # Two-Handed Sword, level 10, Warrior/Bowman/Thief, STR 25
const KOIF := "724"          # hat, level 10, Warrior, STR 10
const HEADBAND := "711"      # hat, level 5, W.DEF + Max HP
const UNDERSHIRT := "933"    # top, male
const TUBE_TOP := "937"      # top, female
const JEAN_SHORTS := "1157"  # bottom, male
const ICE_JEANS := "1195"    # bottom, level 17, fame 20


func _test_db() -> ContentDB:
	var d := ContentDB.new()
	d.canonical = db().canonical.duplicate()
	var items: Dictionary = (db().canonical["items"] as Dictionary).duplicate()
	items["test-overall"] = _synthetic("test-overall", "Overall", "overall", {"wdef": 10, "upgrade_slots": 7})
	items["test-shield"] = _synthetic("test-shield", "Shield", "shield", {"wdef": 5, "upgrade_slots": 7})
	d.canonical["items"] = items
	d.miso = db().miso
	d.loaded = true
	return d


func _synthetic(id: String, subtype: String, slot: String, stats: Dictionary) -> Dictionary:
	return {"id": id, "name": "TEST " + subtype, "type": "Equip", "subtype": subtype, "inventory_tab": "equip",
		"equip_slot": slot, "quest_item": false, "requirements": {"level": 0, "job": null, "str": 0, "dex": 0,
		"int": 0, "luk": 0, "fame": 0}, "stats": stats, "weapon": null, "consumable": null, "max_stack": null,
		"tradeable": true, "gender": "any", "sell_price_mesos": 0, "sell_price_basis": "per_item"}


func _char(level: int = 1, job: String = "beginner") -> CharacterState:
	var c := CharacterState.new()
	c.level = level
	c.job = job
	return c


func _give(c: CharacterState, ids: Array, d: ContentDB = null) -> void:
	for id in ids:
		c.inventory.add(String(id), 1, d if d != null else db())


func test_equip_moves_item_from_inventory() -> void:
	var c := _char()
	_give(c, [SWORD])
	var res := c.equipment.equip(c, SWORD, db())
	assert_true(res.ok, str(res))
	assert_eq(res.slot, "weapon")
	assert_eq(c.equipment.weapon_id(), SWORD)
	assert_eq(c.inventory.count(SWORD), 0)
	assert_eq(c.equipment.total_bonuses(db()).watk, int(db().item(SWORD).stats.watk))


func test_equip_swaps_previous_item_into_the_freed_slot() -> void:
	var c := _char()
	_give(c, [SWORD, "270", CLUB])
	c.equipment.equip(c, SWORD, db())
	var club_index := int(c.inventory.find(CLUB).index)
	var res := c.equipment.equip(c, CLUB, db())
	assert_true(res.ok, str(res))
	assert_eq(res.unequipped, [SWORD])
	assert_eq(c.equipment.weapon_id(), CLUB)
	assert_eq(c.inventory.get_slot("equip", club_index).item_id, SWORD, "old weapon takes the new one's slot")
	assert_eq(c.equipment.total_bonuses(db()).watk, int(db().item(CLUB).stats.watk))


func test_equip_specific_inventory_slot() -> void:
	var c := _char()
	_give(c, [SWORD])
	c.inventory.add_instance(SWORD, {"stats": {"watk": 20}}, db())
	var res := c.equipment.equip(c, SWORD, db(), 1)
	assert_true(res.ok)
	assert_eq(c.equipment.instance_in("weapon").data, {"stats": {"watk": 20}}, "instance data travels with the item")
	assert_eq(c.equipment.total_bonuses(db()).watk, 20, "instance stats override clean stats")


func test_unequip_returns_item() -> void:
	var c := _char()
	_give(c, [SWORD])
	c.equipment.equip(c, SWORD, db())
	var res := c.equipment.unequip(c, "weapon", db())
	assert_true(res.ok, str(res))
	assert_eq(c.equipment.weapon_id(), "")
	assert_eq(c.inventory.count(SWORD), 1)
	assert_eq(c.equipment.total_bonuses(db()).watk, 0)
	assert_eq(c.equipment.unequip(c, "weapon", db()).code, ItemCodes.SLOT_EMPTY)
	assert_eq(c.equipment.unequip(c, "tail", db()).code, ItemCodes.UNKNOWN_SLOT)


func test_unequip_needs_inventory_space() -> void:
	var c := _char()
	_give(c, [SWORD])
	c.equipment.equip(c, SWORD, db())
	c.inventory.set_capacity("equip", 1)
	_give(c, [CLUB])
	var res := c.equipment.unequip(c, "weapon", db())
	assert_eq(res.code, ItemCodes.INVENTORY_FULL)
	assert_eq(c.equipment.weapon_id(), SWORD, "nothing changed")


func test_equip_failures() -> void:
	var c := _char()
	assert_eq(c.equipment.equip(c, SWORD, db()).code, ItemCodes.NOT_ENOUGH_ITEMS, "not in inventory")
	_give(c, ["270"])
	assert_eq(c.equipment.equip_check(c, "270", db()).code, ItemCodes.NOT_EQUIPMENT)
	assert_eq(c.equipment.equip(c, "270", db()).code, ItemCodes.NOT_EQUIPMENT, "a held potion is not equipment")
	assert_eq(c.inventory.count("270"), 1)
	assert_eq(c.equipment.equip_check(c, "nope", db()).code, ItemCodes.UNKNOWN_ITEM)
	assert_eq(c.equipment.equip(c, "nope", db()).code, ItemCodes.UNKNOWN_ITEM)


func test_level_requirement() -> void:
	var c := _char(1)
	_give(c, [RAZOR])
	var res := c.equipment.equip(c, RAZOR, db())
	assert_eq(res.code, ItemCodes.LEVEL_TOO_LOW)
	assert_eq(res.required, int(db().item(RAZOR).requirements.level))
	assert_eq(c.inventory.count(RAZOR), 1, "failed equip leaves the item in the inventory")
	c.level = int(db().item(RAZOR).requirements.level)
	assert_true(c.equipment.equip(c, RAZOR, db()).ok)


func test_job_requirement() -> void:
	var c := _char(10)
	c.base_stats["str"] = 10
	var res := c.equipment.equip_check(c, KOIF, db())
	assert_eq(res.code, ItemCodes.JOB_MISMATCH, "a Beginner cannot wear Warrior gear")
	c.job = "warrior"
	assert_true(c.equipment.can_equip(c, KOIF, db()))
	c.job = "magician"
	assert_eq(c.equipment.equip_check(c, KOIF, db()).code, ItemCodes.JOB_MISMATCH)
	c.base_stats["int"] = 10
	assert_true(c.equipment.can_equip(c, "945", db()), "MeowDB writes the Magician job as 'Mage'")


func test_stat_requirement_uses_total_stats() -> void:
	var c := _char(10)
	var need := int(db().item(LONG_SWORD).requirements.str)
	c.base_stats["str"] = need - 1
	var res := c.equipment.equip_check(c, LONG_SWORD, db())
	assert_eq(res.code, ItemCodes.STAT_TOO_LOW)
	assert_eq(res.stat, "str")
	assert_eq(res.required, need)
	assert_eq(res.actual, StatCalculator.total_stat(c, "str", db()))
	c.base_stats["str"] = need
	assert_true(c.equipment.can_equip(c, LONG_SWORD, db()))


func test_fame_requirement() -> void:
	var c := _char(int(db().item(ICE_JEANS).requirements.level))
	assert_eq(c.equipment.equip_check(c, ICE_JEANS, db()).code, ItemCodes.FAME_TOO_LOW)
	c.fame = int(db().item(ICE_JEANS).requirements.fame)
	assert_true(c.equipment.can_equip(c, ICE_JEANS, db()))


func test_gender_requirement_when_known() -> void:
	var c := _char()
	assert_true(c.equipment.can_equip(c, UNDERSHIRT, db()), "unknown gender skips the check")
	c.gender = "female"
	assert_eq(c.equipment.equip_check(c, UNDERSHIRT, db()).code, ItemCodes.GENDER_MISMATCH)
	c.gender = ""
	c.flags["gender"] = "female"
	assert_eq(c.equipment.equip_check(c, UNDERSHIRT, db()).code, ItemCodes.GENDER_MISMATCH, "legacy flag")
	c.flags.erase("gender")
	c.gender = "female"
	assert_true(c.equipment.can_equip(c, TUBE_TOP, db()))
	assert_true(c.equipment.can_equip(c, "1305", db()), "any-gender shoes")


func test_overall_replaces_top_and_bottom() -> void:
	var d := _test_db()
	var c := _char()
	_give(c, [UNDERSHIRT, JEAN_SHORTS, "test-overall"], d)
	c.equipment.equip(c, UNDERSHIRT, d)
	c.equipment.equip(c, JEAN_SHORTS, d)
	var res := c.equipment.equip(c, "test-overall", d)
	assert_true(res.ok, str(res))
	assert_eq(c.equipment.item_in("overall"), "test-overall")
	assert_eq(c.equipment.item_in("top"), "")
	assert_eq(c.equipment.item_in("bottom"), "")
	assert_eq(c.inventory.count(UNDERSHIRT), 1)
	assert_eq(c.inventory.count(JEAN_SHORTS), 1)
	assert_eq((res.changed_slots as Array).size(), 3)
	assert_eq(c.equipment.total_bonuses(d).wdef, 10)
	# A top over an overall takes the overall off.
	var res2 := c.equipment.equip(c, UNDERSHIRT, d)
	assert_true(res2.ok)
	assert_eq(res2.unequipped, ["test-overall"])
	assert_eq(c.equipment.item_in("overall"), "")
	assert_eq(c.equipment.item_in("top"), UNDERSHIRT)


func test_overall_swap_needs_room_for_both_pieces() -> void:
	var d := _test_db()
	var c := _char()
	_give(c, [UNDERSHIRT, JEAN_SHORTS, "test-overall"], d)
	c.equipment.equip(c, UNDERSHIRT, d)
	c.equipment.equip(c, JEAN_SHORTS, d)
	assert_true(c.inventory.move("equip", int(c.inventory.find("test-overall").index), 0))
	assert_true(c.inventory.set_capacity("equip", 1), "only the overall's own slot")
	var res := c.equipment.equip(c, "test-overall", d)
	assert_eq(res.code, ItemCodes.INVENTORY_FULL)
	assert_eq(c.equipment.item_in("top"), UNDERSHIRT, "nothing changed")
	assert_eq(c.inventory.count("test-overall"), 1)


func test_two_handed_weapon_and_shield() -> void:
	var d := _test_db()
	var c := _char(10, "warrior")
	c.base_stats["str"] = int(db().item(WOODEN_SWORD).requirements.str)
	_give(c, [SWORD, "test-shield", WOODEN_SWORD], d)
	assert_true(c.equipment.equip(c, SWORD, d).ok)
	assert_true(c.equipment.equip(c, "test-shield", d).ok)
	assert_eq(c.equipment.weapon_id(), SWORD, "a one-handed weapon keeps the shield")
	var res := c.equipment.equip(c, WOODEN_SWORD, d)
	assert_true(res.ok, str(res))
	assert_eq(c.equipment.item_in("shield"), "", "two-handed weapon removes the shield")
	assert_eq(c.inventory.count("test-shield"), 1)
	assert_eq(c.inventory.count(SWORD), 1)
	var res2 := c.equipment.equip(c, "test-shield", d)
	assert_true(res2.ok)
	assert_eq(c.equipment.weapon_id(), "", "shield removes a two-handed weapon")
	assert_eq(c.inventory.count(WOODEN_SWORD), 1)


func test_total_bonuses_covers_every_key() -> void:
	var c := _char(5)
	_give(c, [HEADBAND, SWORD, "1305"])
	for id in [HEADBAND, SWORD, "1305"]:
		assert_true(c.equipment.equip(c, id, db()).ok, id)
	var b := c.equipment.total_bonuses(db())
	assert_eq(PackedStringArray(b.keys()), Equipment.BONUS_KEYS)
	assert_eq(b.max_hp, int(db().item(HEADBAND).stats.hp))
	assert_eq(b.wdef, int(db().item(HEADBAND).stats.wdef) + int(db().item("1305").stats.wdef))
	assert_eq(b.watk, int(db().item(SWORD).stats.watk))
	assert_eq(c.equipment.extra_bonuses(db()).crit_rate_pct, 0)


func test_extra_stat_rows_reach_the_bonus_totals() -> void:
	var c := _char()
	assert_true(c.equipment.force_equip("gloves", "1440", db()))   # Brown Duo: CRIT% +1
	var crit := int(db().item("1440").stats.crit_rate_pct)
	var b := c.equipment.total_bonuses(db())
	for k in Equipment.BONUS_KEYS:
		assert_has(b, k)
	assert_eq(b.get("crit_rate_pct"), crit)
	assert_eq(c.equipment.extra_bonuses(db()).crit_rate_pct, crit)
	var snap := StatCalculator.snapshot(c, db())
	var bare := StatCalculator.snapshot(_char(), db())
	assert_near(float(snap.crit_rate_pct), float(bare.crit_rate_pct) + crit, 1e-6, "glove CRIT% reaches the crit rate")


func test_equipment_changes_derived_stats() -> void:
	var c := _char(5)
	var before := StatCalculator.max_hp(c, db())
	_give(c, [HEADBAND])
	assert_true(c.equipment.equip(c, HEADBAND, db()).ok)
	assert_eq(StatCalculator.max_hp(c, db()), before + int(db().item(HEADBAND).stats.hp), "Max HP includes gear")


func test_round_trip() -> void:
	var c := _char(5)
	_give(c, [HEADBAND, SWORD])
	c.equipment.equip(c, HEADBAND, db())
	c.inventory.add_instance(CLUB, {"stats": {"watk": 21}, "upgrades_used": 2}, db())
	c.equipment.equip(c, CLUB, db())
	var d := c.equipment.to_dict()
	assert_eq(Equipment.from_dict(d).to_dict(), d)
	var back := CharacterState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_eq(back.equipment.to_dict(), d)
	assert_eq(back.equipment.total_bonuses(db()), c.equipment.total_bonuses(db()))
	assert_eq(back.inventory.to_dict(), c.inventory.to_dict())
	assert_true(Equipment.from_dict({}).is_empty())


func test_service_emits_equipment_signals() -> void:
	var bus: Node = load("res://scripts/autoload/events.gd").new()
	var seen: Array = []
	bus.equipment_changed.connect(func(slot: String) -> void: seen.append("equipment_changed:" + slot))
	bus.stats_changed.connect(func() -> void: seen.append("stats_changed"))
	bus.inventory_changed.connect(func() -> void: seen.append("inventory_changed"))
	var c := _char()
	var s := ItemService.new(c, db(), bus)
	s.gain(SWORD, 1)
	seen.clear()
	assert_true(s.equip(SWORD).ok)
	assert_eq(seen, ["equipment_changed:weapon", "inventory_changed", "stats_changed"])
	seen.clear()
	assert_true(s.unequip("weapon").ok)
	assert_eq(seen, ["equipment_changed:weapon", "inventory_changed", "stats_changed"])
	seen.clear()
	assert_false(s.unequip("weapon").ok)
	assert_eq(seen, [], "a failed unequip emits nothing")
	bus.free()


func test_stat_requirement_counts_equipment_bonuses() -> void:
	# MeowDB: total stats include equipment, so a worn STR bonus can carry a base stat over a requirement.
	var c := _char(10)
	var need := int(db().item(LONG_SWORD).requirements.str)
	var pants_str := int(db().item("1168").stats.str)   # Red Cloth Pants: STR +1 (forced on, its Thief rule bypassed)
	assert_true(pants_str > 0, "precondition: the pants give STR")
	c.base_stats["str"] = need - pants_str
	assert_eq(c.equipment.equip_check(c, LONG_SWORD, db()).code, ItemCodes.STAT_TOO_LOW, "base alone is short")
	assert_true(c.equipment.force_equip("bottom", "1168", db()))
	assert_eq(StatCalculator.total_stat(c, "str", db()), need)
	assert_true(c.equipment.can_equip(c, LONG_SWORD, db()), "base + equipment meets the requirement")


func test_swap_works_with_a_full_equip_tab() -> void:
	var c := _char()
	c.inventory.set_capacity("equip", 1)
	_give(c, [SWORD])
	assert_true(c.equipment.equip(c, SWORD, db()).ok)
	_give(c, [CLUB])
	assert_true(c.inventory.is_full("equip"), "precondition: the only slot holds the club")
	var res := c.equipment.equip(c, CLUB, db())
	assert_true(res.ok, str(res))
	assert_eq(c.equipment.weapon_id(), CLUB)
	assert_eq(c.inventory.get_slot("equip", 0).item_id, SWORD, "the old weapon takes the club's slot")


func test_weapon_changes_attack_stats() -> void:
	var c := _char()
	var bare := StatCalculator.snapshot(c, db())
	_give(c, [CLUB])
	assert_true(c.equipment.equip(c, CLUB, db()).ok)
	var armed := StatCalculator.snapshot(c, db())
	assert_eq(armed.weapon_id, CLUB)
	assert_eq(int(armed.watk), int(bare.watk) + int(db().item(CLUB).stats.watk), "W.ATK includes the weapon")
	assert_true(int(armed.damage_max) > int(bare.damage_max), "the stat window's damage rises with the weapon")


func test_unequip_clamps_hp_through_the_service() -> void:
	var bus: Node = load("res://scripts/autoload/events.gd").new()
	var hp_events: Array = []
	bus.hp_changed.connect(func(hp: int, max_hp: int) -> void: hp_events.append([hp, max_hp]))
	var c := _char(int(db().item(HEADBAND).requirements.level))
	var s := ItemService.new(c, db(), bus)
	s.gain(HEADBAND, 1)
	var base_max := StatCalculator.max_hp(c, db())
	assert_true(s.equip(HEADBAND).ok)
	var geared_max := StatCalculator.max_hp(c, db())
	assert_eq(geared_max, base_max + int(db().item(HEADBAND).stats.hp))
	c.hp = geared_max
	assert_eq(hp_events, [], "equipping a Max HP bonus does not heal")
	assert_true(s.unequip("hat").ok)
	assert_eq(c.hp, base_max, "HP is clamped to the lower maximum")
	assert_eq(hp_events, [[base_max, base_max]])
	bus.free()


func test_from_dict_tolerates_numeric_ids_and_garbage() -> void:
	var eq := Equipment.from_dict({"slots": {"weapon": {"item_id": 541.0}, "hat": {"item_id": 711}, "top": "junk",
		"shoes": {"item_id": null}}})
	assert_eq(eq.weapon_id(), SWORD, "a JSON float id becomes the canonical string id")
	assert_eq(eq.item_in("hat"), HEADBAND)
	assert_eq(eq.item_in("top"), "")
	assert_eq(eq.item_in("shoes"), "")
