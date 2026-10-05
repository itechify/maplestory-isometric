extends TestCase
## ItemDef: the typed view of canonical items. Expected values are read from the canonical records (never typed in),
## so these tests check the mapping, not MeowDB's numbers.


## Contract C6: only the items whose values a test compares with their canonical record (the whole-set test checks
## that every item builds, not its values, so it proves no item:<id> key).
func parity_keys() -> Dictionary:
	return {
		"test_stat_lines_map_to_bonus_keys": ["item:711", "item:1440"],
		"test_consumable_effects": ["item:270", "item:239", "item:269"],
		"test_weapon_type_family_action_and_speed": ["item:541"],
	}


func test_every_canonical_item_builds() -> void:
	for id in db().ids("items"):
		var def := ItemDef.of(id, db())
		assert_true(def != null, "item %s" % id)
		if def == null:
			continue
		assert_has(Inventory.TABS, def.tab, "tab of %s" % id)
		assert_true(def.max_stack >= 1, "max stack of %s" % id)
		for k in Equipment.BONUS_KEYS:
			assert_has(def.bonuses, k, "bonus key %s on %s" % [k, id])
		if def.tab == "equip":
			assert_ne(def.equip_slot, "", "equip slot of %s" % id)
			assert_has(ItemsConfig.equipment_slots(db()), def.equip_slot, "slot of %s is a known equipment slot" % id)


func test_unknown_item_is_null() -> void:
	assert_eq(ItemDef.of("no-such-item", db()), null)


func test_tab_and_stack_from_canonical_data() -> void:
	var potion := ItemDef.of("270", db())
	assert_eq(potion.tab, String(db().item("270").inventory_tab))
	assert_eq(potion.max_stack, int(db().item("270").max_stack))
	assert_true(potion.is_stackable())
	var sword := ItemDef.of("541", db())
	assert_eq(db().item("541").max_stack, null, "MeowDB has no equipment stack size")
	assert_eq(sword.max_stack, int(db().miso_table("inventory").equipment_max_stack))
	assert_false(sword.is_stackable())


func test_stat_lines_map_to_bonus_keys() -> void:
	var headband := ItemDef.of("711", db())   # Red Headband: W.DEF and Max HP
	var stats: Dictionary = db().item("711").stats
	assert_eq(headband.bonuses.wdef, int(stats.wdef))
	assert_eq(headband.bonuses.max_hp, int(stats.hp), "canonical hp -> max_hp")
	assert_eq(headband.bonuses.str, 0)
	assert_eq(headband.upgrade_slots, int(stats.upgrade_slots))
	var gloves := ItemDef.of("1440", db())    # Brown Duo: CRIT% is not a BONUS_KEY
	assert_eq(gloves.extra_stats.get("crit_rate_pct"), int(db().item("1440").stats.crit_rate_pct))
	assert_false(gloves.bonuses.has("crit_rate_pct"))
	var lines := headband.stat_lines()
	assert_false(lines.has("str"), "stat_lines only lists non-zero lines")


func test_requirements() -> void:
	var gladius := ItemDef.of("551", db())
	var req: Dictionary = db().item("551").requirements
	assert_eq(gladius.req_level, int(req.level))
	assert_eq(gladius.req_jobs, PackedStringArray(req.job))
	assert_eq(gladius.req_stats.str, int(req.str))
	assert_eq(gladius.req_stats.dex, int(req.dex))
	var jeans := ItemDef.of("1195", db())
	assert_eq(jeans.req_fame, int(db().item("1195").requirements.fame))
	assert_eq(ItemDef.of("541", db()).req_jobs.size(), 0, "no job requirement = any job")
	assert_eq(ItemDef.of("933", db()).gender, "male")
	assert_eq(ItemDef.of("1305", db()).gender, "", "Male + Female = any")


func test_consumable_effects() -> void:
	var potion := ItemDef.of("270", db())
	assert_eq(potion.hp_flat, int(db().item("270").consumable.hp_restore))
	assert_eq(potion.mp_flat, 0)
	assert_true(potion.is_consumable())
	var orange := ItemDef.of("239", db())
	assert_eq(orange.mp_flat, int(db().item("239").consumable.mp_restore))
	var pet_food := ItemDef.of("269", db())
	assert_eq(pet_food.pet_fullness, int(db().item("269").consumable.pet_fullness_restore))
	assert_false(pet_food.is_consumable(), "pet food needs a pet")
	assert_false(ItemDef.of("59", db()).is_consumable(), "scrolls are not consumables here")


func test_prices_and_flags() -> void:
	var potion := ItemDef.of("270", db())
	assert_eq(potion.buy_price, int(db().item("270").npc_buy_price_mesos))
	assert_eq(potion.sell_price, int(db().item("270").sell_price_mesos))
	assert_eq(potion.sell_basis, "per_unit")
	assert_eq(ItemDef.of("320", db()).buy_price, -1, "not sold by NPCs")
	var rogers := ItemDef.of("235", db())
	assert_true(rogers.untradeable())
	assert_false(rogers.quest_item)
	var mirror := ItemDef.of("438", db())
	assert_true(mirror.quest_item)
	assert_true(mirror.untradeable())


func test_weapon_type_family_action_and_speed() -> void:
	var sword := ItemDef.of("541", db())
	var w: Dictionary = db().item("541").weapon
	assert_true(sword.is_weapon())
	assert_eq(sword.weapon_type, String(w.weapon_type))
	assert_eq(sword.attack_speed, int(w.attack_speed))
	assert_eq(sword.attack_speed_name, String(w.attack_speed_name))
	assert_eq(sword.attack_cycle_ms, int(w.attack_cycle_ms))
	assert_eq(sword.multipliers, w.multipliers)
	assert_eq(sword.action_mix_pct, w.basic_attack_mix_pct)
	assert_false(sword.two_handed)
	assert_eq(sword.damage_family, "sword_axe_blunt_spear_polearm")
	assert_eq(ItemDef.of("558", db()).damage_family, "dagger_claw")
	assert_true(ItemDef.of("608", db()).two_handed, "Two-Handed Sword")
	assert_false(ItemDef.of("651", db()).two_handed, "Wand")


func test_weapon_formula_keys_exist_in_damage_formulas() -> void:
	var physical: Dictionary = db().formula("damage").physical
	var families := {}
	for f in physical.weapon_families:
		families[String(f.key)] = true
	for id in db().ids("items"):
		var def := ItemDef.of(id, db())
		if not def.is_weapon():
			continue
		assert_true(families.has(def.damage_family), "%s damage_family %s" % [id, def.damage_family])
		assert_has(physical.weapon_action_multipliers, def.multiplier_key, "%s multiplier_key" % id)
		assert_has(physical.ordinary_action_odds, def.action_odds_key, "%s action_odds_key" % id)


func test_adaptation_table_is_marked_unverified_with_reasons() -> void:
	var t: Dictionary = db().miso_table("inventory")
	assert_eq(t.get("verified"), false)
	for key in ["tab_slots", "equipment_max_stack", "unpublished_max_stack", "meso_cap", "equipment_slots",
			"slot_aliases", "slot_conflicts", "weapon_subtypes", "job_item_tags"]:
		assert_true(t.has(key), "inventory.json has %s" % key)
		assert_true(String(t.get(key + "_reason", "")).length() > 20, "%s_reason" % key)
	for rule in t.slot_conflicts:
		assert_true(String(rule.get("reason", "")) != "", "conflict rule reason")
	for key in ["sell_zero_value_items", "max_bundles_per_purchase"]:
		assert_true(String(t.shop.get(key + "_reason", "")).length() > 20, "shop.%s_reason" % key)
	for slot in ["weapon", "hat", "top", "bottom", "overall", "shoes", "gloves", "cape", "shield", "earrings"]:
		assert_has(t.equipment_slots, slot, "brief slot")


func test_weapon_subtypes_agree_with_the_combat_weapon_profile() -> void:
	# inventory.json weapon_subtypes (items) and WeaponProfile.SUBTYPES (combat) both join MeowDB subtypes to
	# damage.json row keys; they must never drift apart.
	var table: Dictionary = db().miso_table("inventory").weapon_subtypes
	for subtype in WeaponProfile.SUBTYPES:
		assert_has(table, subtype, "inventory.json weapon_subtypes")
		if not table.has(subtype):
			continue
		var combat: Dictionary = WeaponProfile.SUBTYPES[subtype]
		var items: Dictionary = table[subtype]
		assert_eq(items.multiplier_key, combat.multipliers, "%s multiplier key" % subtype)
		assert_eq(items.damage_family, combat.family, "%s family" % subtype)
		assert_eq(items.action_odds_key, combat.odds, "%s action odds key" % subtype)
	for subtype in table:
		assert_has(WeaponProfile.SUBTYPES, subtype, "WeaponProfile.SUBTYPES")
