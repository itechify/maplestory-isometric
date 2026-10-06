extends TestCase
## Every canonical item against the runtime that uses it (brief Phase 4, "For every item validate"; contract C6 keys
## item:<id>). The expected side is the canonical record read straight from res://data/canonical/items/<id>.json, not
## through ContentDB, so a loader that dropped or changed a field is caught too. The runtime side is what the game
## calls: ItemDef.of, Inventory.add, ItemService.equip / use_item (Equipment, Consumables, Chairs), Equipment.equip_check
## and total_bonuses, StatCalculator, ShopService.quote_buy / quote_sell / sell_price, WeaponProfile (damage rows, hit
## boxes) and CombatFormula timings, and CharacterFactory's creation weapons.
##
## One comparator per field family returns its problems as text. Each family test runs it on every item; each
## mutation test feeds it an expected record with one field changed, and the runtime a changed record (or a changed
## shop or hit-zone table) with the true one expected, so every comparison is shown to fail when the two sides differ
## (a changed expected record alone can trip the record's own derivation checks instead of the comparison). Documented
## adaptations are asserted as documented: equipment stacks by data/misostory/inventory.json equipment_max_stack, an
## unpublished max_stack by unpublished_max_stack, and only when the record's gaps and that table's reason both say so
## (no shipped item has one: the stack comparison's mutation test shows the fallback on a private copy of the content,
## where Apple's record has lost its max_stack).

const ITEMS_DIR := "res://data/canonical/items"
## The canonical stat rows the runtime turns into Equipment.BONUS_KEYS, written from docs/canonical/items.md ("hp" is
## Max HP +, "mp" is Max MP +), not from ItemDef.STAT_TO_BONUS, so the mapping itself is under test.
const STAT_BONUS := {
	"str": "str", "dex": "dex", "int": "int", "luk": "luk", "hp": "max_hp", "mp": "max_mp", "watk": "watk",
	"matk": "matk", "wdef": "wdef", "mdef": "mdef", "acc": "acc", "avoid": "avoid", "speed": "speed", "jump": "jump",
}
## Stat rows the runtime keeps outside the bonus keys (ItemDef.extra_stats; Equipment.total_bonuses when non-zero).
const STAT_EXTRA: PackedStringArray = ["crit_rate_pct", "knockback_pct"]
## items.md "Derived fields": MeowDB type -> inventory tab, and Equip subtype -> equip slot.
const TYPE_TAB := {"Equip": "equip", "Use": "use", "Setup": "setup", "Etc": "etc"}
const SUBTYPE_SLOT := {
	"One-Handed Sword": "weapon", "One-Handed Axe": "weapon", "One-Handed Blunt Weapon": "weapon",
	"Two-Handed Sword": "weapon", "Two-Handed Axe": "weapon", "Two-Handed Blunt Weapon": "weapon", "Dagger": "weapon",
	"Spear": "weapon", "Polearm": "weapon", "Bow": "weapon", "Crossbow": "weapon", "Wand": "weapon", "Staff": "weapon",
	"Claw": "weapon", "Hat": "hat", "Top": "top", "Bottom": "bottom", "Overall": "overall", "Shoes": "shoes",
	"Gloves": "gloves", "Cape": "cape", "Shield": "shield", "Earring": "earrings",
}
## Every requirement field items.md documents; any other key would be a requirement nothing enforces.
const REQUIREMENT_KEYS: PackedStringArray = ["level", "job", "job_raw", "str", "dex", "int", "luk", "fame"]
const REQ_STATS: PackedStringArray = ["str", "dex", "int", "luk"]
## Every consumable field items.md and ItemDef know; any other key would be an effect nothing applies.
const CONSUMABLE_KEYS: PackedStringArray = ["hp_restore", "mp_restore", "hp_restore_pct", "mp_restore_pct",
	"pet_fullness_restore", "buffs"]
## The family tests: each one runs its comparator on every item and proves item:<id> for all of them.
const FAMILY_TESTS: PackedStringArray = [
	"test_every_item_file_is_loaded_by_the_game",
	"test_identity_and_flags_match_for_every_item",
	"test_tab_and_stack_match_for_every_item",
	"test_equip_slot_matches_for_every_item",
	"test_requirements_match_for_every_item",
	"test_stats_match_for_every_item",
	"test_weapon_data_matches_for_every_item",
	"test_consumable_effects_match_for_every_item",
	"test_setup_data_matches_for_every_item",
	"test_prices_match_for_every_item",
]
## Plenty of mesos for any quote (Maple Island prices are at most 22,000).
const RICH := 10000000


## Contract C6: every family test compares one field family of every canonical item with the runtime, so each proves
## every item:<id> key (all-or-nothing: one failing family fails every key). The setup family also proves the chair
## keys of the items that carry setup data. The mutation tests prove the comparators, not the items: no keys.
func parity_keys() -> Dictionary:
	var keys: Array = []
	var chairs: Array = []
	for id in _item_ids():
		keys.append("item:" + id)
		if _canonical(id).get("setup") is Dictionary:
			chairs.append("chair:" + id)
	var out := {}
	for t in FAMILY_TESTS:
		out[t] = keys.duplicate()
	out["test_setup_data_matches_for_every_item"] = keys + chairs
	return out


# --- the family tests ---------------------------------------------------------------------------------------------

func test_every_item_file_is_loaded_by_the_game() -> void:
	var ids := _item_ids()
	assert_true(ids.size() > 0, "the canonical items folder is not empty")
	assert_eq(Array(db().ids("items")), Array(ids), "ContentDB loads exactly the item files")
	for id in ids:
		var rec := _canonical(id)
		assert_eq(String(rec.get("id", "")), id, "%s.json names its own id" % id)
		assert_true(_same(db().item(id), rec), "ContentDB's record of %s is the file, field for field" % id)


func test_identity_and_flags_match_for_every_item() -> void:
	_run_family("identity", _identity_problems)


func test_tab_and_stack_match_for_every_item() -> void:
	_run_family("stack", _stack_problems)


func test_equip_slot_matches_for_every_item() -> void:
	_run_family("slot", _slot_problems)


func test_requirements_match_for_every_item() -> void:
	_run_family("requirements", _requirement_problems)


func test_stats_match_for_every_item() -> void:
	_run_family("stats", _stat_problems)


func test_weapon_data_matches_for_every_item() -> void:
	_run_family("weapon", _weapon_problems)


func test_consumable_effects_match_for_every_item() -> void:
	_run_family("consumable", _consumable_problems)


func test_setup_data_matches_for_every_item() -> void:
	_run_family("setup", _setup_problems)


func test_prices_match_for_every_item() -> void:
	_run_family("prices", _price_problems)


# --- the mutation tests: each comparison can fail -----------------------------------------------------------------

func test_identity_comparison_can_fail() -> void:
	_expect_caught(_identity_problems, "270", "name", "Red Potion (wrong)", "name")
	_expect_caught(_identity_problems, "270", "type", "Etc", "type")
	_expect_caught(_identity_problems, "270", "subtype", "Food", "subtype")
	_expect_caught(_identity_problems, "270", "description", "", "description")
	_expect_caught(_identity_problems, "348", "quest_item", true, "quest_item")
	_expect_caught(_identity_problems, "270", "tradeable", false, "tradeable")
	_expect_caught(_identity_problems, "441", "tradeable", true, "tradeable")
	_expect_caught(_identity_problems, "541", "beginner_creation_weapon", false, "beginner_creation_weapon")
	_expect_caught(_identity_problems, "543", "beginner_creation_weapon", true, "beginner_creation_weapon")
	# The runtime side: the game reads a different name, quest flag or creation-weapon flag than the canonical file says.
	assert_true(_mentions(_identity_problems("270", _canonical("270"), _db_with("270", "name", "Blue Potion")), "name"),
		"a runtime Red Potion named Blue Potion is caught")
	assert_true(_mentions(_identity_problems("348", _canonical("348"), _db_with("348", "quest_item", true)), "quest_item"),
		"a runtime quest flag the file does not set is caught")
	assert_true(_mentions(_identity_problems("541", _canonical("541"), _db_with("541", "beginner_creation_weapon", false)),
		"beginner_creation_weapon"), "a Sword the creation screen no longer offers is caught")


func test_stack_comparison_can_fail() -> void:
	_expect_caught(_stack_problems, "270", "max_stack", 99, "max_stack")
	_expect_caught(_stack_problems, "209", "max_stack", 100, "max_stack")
	_expect_caught(_stack_problems, "270", "inventory_tab", "etc", "tab")
	_expect_caught(_stack_problems, "541", "max_stack", 5, "max_stack")
	_expect_caught(_stack_problems, "236", "max_stack", 30, "max_stack")
	# The unpublished-stack fallback (no shipped item uses it) counts only while the record's gaps and inventory.json's
	# reason both document the missing value: shown on a private copy of the content where Apple's record has no
	# max_stack.
	var unpub := _set_path(_set_path(_canonical("236"), "max_stack", null), "gaps",
		["max_stack: (test) the item page's \"Max per Stack\" row was not read"])
	var inv: Dictionary = (db().miso_table("inventory") as Dictionary).duplicate(true)
	inv["unpublished_max_stack_reason"] = "(test) Apple (236) has no published stack size"
	var fallback := _db_with_miso_table(_db_with_record("items", "236", unpub.duplicate(true)), "inventory", inv)
	var ok := _stack_problems("236", unpub, fallback)
	assert_eq(ok.size(), 0, "a documented unpublished stack holds unpublished_max_stack (%d): %s" % [
		int(inv.get("unpublished_max_stack", -1)), "; ".join(ok)])
	assert_true(_mentions(_stack_problems("236", _set_path(unpub, "gaps", []), fallback), "documented"),
		"a null max_stack the record's gaps do not document is caught")
	var undocumented := inv.duplicate(true)
	undocumented["unpublished_max_stack_reason"] = "(test) names no item"
	assert_true(_mentions(_stack_problems("236", unpub, _db_with_miso_table(fallback, "inventory", undocumented)), "not documented"),
		"a fallback inventory.json's reason does not name is caught")
	assert_true(_mentions(_stack_problems("236", _set_path(unpub, "max_stack", 30), fallback), "max_stack"),
		"a runtime fallback stack other than the record's is caught")
	# The runtime side: the game reads a different stack size than the canonical file says.
	assert_true(_mentions(_stack_problems("270", _canonical("270"), _db_with("270", "max_stack", 7)), "max_stack"),
		"a runtime stack of 7 for Red Potion is caught")
	# The expected-side tab mutation above also trips the record's own type -> tab derivation; this one can only be
	# caught by comparing with the runtime (the game files Red Potion under Etc).
	assert_true(_mentions(_stack_problems("270", _canonical("270"), _db_with("270", "inventory_tab", "etc")), "tab"),
		"a runtime Red Potion in the Etc tab is caught")


func test_slot_comparison_can_fail() -> void:
	_expect_caught(_slot_problems, "711", "equip_slot", "top", "slot")
	_expect_caught(_slot_problems, "900", "equip_slot", "hat", "slot")
	_expect_caught(_slot_problems, "270", "equip_slot", "hat", "slot")
	# The expected-side mutations above also trip the record's own subtype -> slot derivation; these can only be
	# caught by comparing with the runtime (the game wears the Red Headband as a top; Red Potion as a hat).
	assert_true(_mentions(_slot_problems("711", _canonical("711"), _db_with("711", "equip_slot", "top")), "slot"),
		"a runtime Red Headband worn as a top is caught")
	assert_true(_mentions(_slot_problems("270", _canonical("270"), _db_with("270", "equip_slot", "hat")), "slot"),
		"a runtime Red Potion that can be worn is caught")


func test_requirement_comparison_can_fail() -> void:
	_expect_caught(_requirement_problems, "543", "requirements/level", 9, "level")
	_expect_caught(_requirement_problems, "543", "requirements/str", 21, "str")
	_expect_caught(_requirement_problems, "945", "requirements/job", ["Warrior"], "job")
	_expect_caught(_requirement_problems, "541", "requirements/job", ["Warrior"], "job")
	_expect_caught(_requirement_problems, "1195", "requirements/fame", 19, "fame")
	_expect_caught(_requirement_problems, "933", "gender", "female", "gender")
	_expect_caught(_requirement_problems, "541", "gender", "male", "gender")
	_expect_caught(_requirement_problems, "270", "requirements/level", 10, "requirement")
	_expect_caught(_requirement_problems, "543", "requirements/guild_rank", 1, "requirement")
	assert_true(_mentions(_requirement_problems("543", _canonical("543"), _db_with("543", "requirements/level", 12)),
		"level"), "a runtime level requirement of 12 for Long Sword is caught")


func test_stat_comparison_can_fail() -> void:
	_expect_caught(_stat_problems, "711", "stats/wdef", 7, "wdef")
	_expect_caught(_stat_problems, "711", "stats/hp", 6, "max_hp")
	_expect_caught(_stat_problems, "715", "stats/mp", 4, "max_mp")
	_expect_caught(_stat_problems, "1440", "stats/crit_rate_pct", 2, "crit_rate_pct")
	_expect_caught(_stat_problems, "666", "stats/knockback_pct", 10, "knockback_pct")
	_expect_caught(_stat_problems, "711", "stats/upgrade_slots", 5, "upgrade_slots")
	_expect_caught(_stat_problems, "711", "stats/charisma", 1, "no runtime field")
	_expect_caught(_stat_problems, "270", "stats", {"watk": 1}, "non-equipment")
	# The runtime side: the game reads other stat rows than the canonical file says.
	assert_true(_mentions(_stat_problems("711", _canonical("711"), _db_with("711", "stats/wdef", 9)), "wdef"),
		"a runtime Red Headband with W.DEF 9 is caught")
	assert_true(_mentions(_stat_problems("711", _canonical("711"), _db_with("711", "stats/hp", 50)), "max_hp"),
		"a runtime Red Headband with Max HP +50 is caught")


func test_weapon_comparison_can_fail() -> void:
	_expect_caught(_weapon_problems, "541", "weapon/attack_speed", 5, "attack_speed")
	_expect_caught(_weapon_problems, "541", "weapon/attack_speed_name", "Slow", "attack_speed_name")
	_expect_caught(_weapon_problems, "541", "weapon/multipliers", {"swing": 2.0, "stab": 1.8}, "multipliers")
	_expect_caught(_weapon_problems, "666", "weapon/multipliers", {"firing": 2.0, "close_range": 1}, "multipliers")
	_expect_caught(_weapon_problems, "541", "weapon/attack_cycle_ms", 750, "cycle")
	_expect_caught(_weapon_problems, "541", "weapon/basic_attack_mix_pct", {"swing": 50, "stab": 50}, "mix")
	_expect_caught(_weapon_problems, "541", "stats/watk", 18, "watk")
	_expect_caught(_weapon_problems, "541", "subtype", "Dagger", "damage category")
	_expect_caught(_weapon_problems, "270", "weapon", _canonical("541").get("weapon"), "weapon")
	# Hit boxes (basic_attacks is a list, so these records are changed by hand): a different box or an attack combat
	# does not play on the item page side, and a different box in combat's hit-zone set on the runtime side.
	var moved := _canonical("541")
	moved["weapon"]["basic_attacks"][0]["box_px"] = [-120, -50, -22, -10]
	assert_true(_mentions(_weapon_problems("541", moved, db()), "hit box"), "a Sword swing box the game does not use is caught")
	var renamed := _canonical("541")
	renamed["weapon"]["basic_attacks"][0]["action"] = "swingX9"
	assert_true(_mentions(_weapon_problems("541", renamed, db()), "no hit box"), "an item-page attack combat lacks is caught")
	var dropped := _canonical("541")
	(dropped["weapon"]["basic_attacks"] as Array).pop_back()
	assert_true(_mentions(_weapon_problems("541", dropped, db()), "basic attacks in combat"),
		"a basic attack combat plays but the item page does not list is caught")
	var styles: Dictionary = db().formula("attack_styles").duplicate(true)
	var set_name := WeaponProfile.from_item("541", db()).hitzone_set
	styles["hitzone_sets"][set_name]["ordinary"]["swingO3"]["box_px"] = [-130, -50, -22, -10]
	assert_true(_mentions(_weapon_problems("541", _canonical("541"), _db_with_record("formulas", "attack_styles", styles)), "hit box"),
		"a combat hit box (%s swingO3) other than the item page's is caught" % set_name)
	# The runtime side: the game reads a different attack speed than the canonical file says.
	assert_true(_mentions(_weapon_problems("541", _canonical("541"), _db_with("541", "weapon/attack_speed", 6)), "attack_speed"),
		"a runtime Sword at speed 6 is caught")


func test_consumable_comparison_can_fail() -> void:
	_expect_caught(_consumable_problems, "270", "consumable/hp_restore", 101, "hp_restore")
	_expect_caught(_consumable_problems, "239", "consumable/mp_restore", 49, "mp_restore")
	_expect_caught(_consumable_problems, "270", "consumable/hp_restore_pct", 10, "hp_restore_pct")
	_expect_caught(_consumable_problems, "269", "consumable/pet_fullness_restore", 31, "pet_fullness")
	_expect_caught(_consumable_problems, "270", "consumable/sp_restore", 1, "consumable field")
	_expect_caught(_consumable_problems, "348", "consumable", {"hp_restore": 5}, "hp_restore")
	_expect_caught(_consumable_problems, "139", "scroll/success_rate_pct", 60, "scroll")
	assert_true(_mentions(_consumable_problems("270", _canonical("270"), _db_with("270", "consumable/hp_restore", 90)),
		"hp_restore"), "a runtime Red Potion restoring 90 HP is caught")
	# No Maple Island item restores a percentage, so the family tests never use that path: a record that did (Red Potion
	# with 10% HP and 5% MP on top) is applied as it says through ItemService.use_item, and a runtime without it is caught.
	var pct := _set_path(_set_path(_canonical("270"), "consumable/hp_restore_pct", 10), "consumable/mp_restore_pct", 5)
	var pct_problems := _consumable_problems("270", pct, _db_with_record("items", "270", pct.duplicate(true)))
	assert_eq(pct_problems.size(), 0, "a percentage restore is applied as the record says: %s" % "; ".join(pct_problems))
	assert_true(_mentions(_consumable_problems("270", pct, db()), "hp_restore_pct"), "a runtime without the percentage is caught")


func test_setup_comparison_can_fail() -> void:
	_expect_caught(_setup_problems, "522", "setup/hp_recovery_bonus", 31, "hp_recovery_bonus")
	_expect_caught(_setup_problems, "522", "setup/interval_s", 5, "interval_s")
	_expect_caught(_setup_problems, "522", "setup", null, "chair")
	_expect_caught(_setup_problems, "348", "setup", {"hp_recovery_bonus": 30, "interval_s": 10}, "chair")
	# The runtime side: the game's chair restores a different amount than the canonical file says.
	assert_true(_mentions(_setup_problems("522", _canonical("522"), _db_with("522", "setup/hp_recovery_bonus", 40)),
		"hp_recovery_bonus"), "a runtime Green Relaxer restoring 40 HP is caught")


func test_price_comparison_can_fail() -> void:
	_expect_caught(_price_problems, "270", "sell_price_mesos", 6, "sell")
	_expect_caught(_price_problems, "270", "sell_price_basis", "per_item", "basis")
	_expect_caught(_price_problems, "270", "npc_buy_price_mesos", 49, "buy")
	_expect_caught(_price_problems, "348", "sell_price_mesos", null, "sell")
	var lucy := _canonical("270").duplicate(true)
	for s in lucy["sources"]["shops"]:
		if String(s.get("npc_name", "")) == "Lucy":
			s["price_mesos"] = 51
	assert_true(_mentions(_price_problems("270", lucy, db()), "buy"), "a different Lucy price in the record is caught")
	var no_shops := _canonical("270").duplicate(true)
	no_shops["sources"]["shops"] = []
	no_shops["npc_buy_price_mesos"] = null
	assert_true(_mentions(_price_problems("270", no_shops, db()), "buy"), "a shop row the record does not list is caught")
	# The runtime side: the game sells back at a different price, and Lucy's shop charges a different price.
	assert_true(_mentions(_price_problems("270", _canonical("270"), _db_with("270", "sell_price_mesos", 9)), "sell"),
		"a runtime Red Potion selling back for 9 is caught")
	var shop: Dictionary = db().shop("maple-road-lucy").duplicate(true)
	for row in shop["items"]:
		if String(row.get("item_id", "")) == "270":
			row["price_mesos"] = 51
	assert_true(_mentions(_price_problems("270", _canonical("270"), _db_with_record("shops", "maple-road-lucy", shop)), "buy"),
		"Lucy's shop charging 51 for Red Potion is caught")


# --- comparators: (item id, the expected canonical record, the content the runtime reads) -> problems ----------------

func _identity_problems(id: String, rec: Dictionary, d: ContentDB) -> PackedStringArray:
	var p: PackedStringArray = []
	var def := ItemDef.of(id, d)
	if def == null:
		return PackedStringArray(["no runtime definition (ItemDef.of returned null)"])
	_eq(p, "id", def.id, id)
	_eq(p, "name", def.name, rec.get("name"))
	_eq(p, "type", def.type, rec.get("type"))
	_eq(p, "subtype", def.subtype, _s(rec.get("subtype")))
	_eq(p, "description", def.description, _s(rec.get("description")))
	# items.md: quest_item is derived as subtype == "Quest Item".
	_eq(p, "quest_item", def.quest_item, rec.get("quest_item") == true)
	if (rec.get("quest_item") == true) != (_s(rec.get("subtype")) == "Quest Item"):
		p.append("quest_item: the record's flag is not its documented derivation from the subtype")
	# Untradeable only on the record's explicit "Untradeable" tag. A null tag is a value the source did not give: the
	# runtime then treats the item as tradeable, which is accepted only while the record's gaps say so.
	_eq(p, "tradeable", def.untradeable(), rec.get("tradeable") == false)
	if rec.get("tradeable") == null and not _gap_mentions(rec, "tradeable"):
		p.append("tradeable: null without a documented gap")
	# items.md: beginner_creation_weapon marks the three weapons the creation screen offers (CharacterFactory).
	_eq(p, "beginner_creation_weapon: offered at character creation", CharacterFactory.creation_weapon_ids(d).has(id),
		rec.get("beginner_creation_weapon") == true)
	return p


func _stack_problems(id: String, rec: Dictionary, d: ContentDB) -> PackedStringArray:
	var p: PackedStringArray = []
	var def := ItemDef.of(id, d)
	if def == null:
		return PackedStringArray(["no runtime definition"])
	var tab := _s(rec.get("inventory_tab"))
	if TYPE_TAB.get(_s(rec.get("type")), "") != tab:
		p.append("tab: %s is not the documented derivation of type %s" % [tab, rec.get("type")])
	_eq(p, "tab", def.tab, tab)
	var inv: Dictionary = d.miso_table("inventory")
	var expected := 0
	if tab == "equip":
		# MeowDB publishes no equipment stack size; inventory.json equipment_max_stack is the adaptation.
		expected = int(inv.get("equipment_max_stack", -1))
		if rec.get("max_stack") != null:
			p.append("max_stack: the record gives %s but equipment always stacks by equipment_max_stack" % rec.get("max_stack"))
	elif rec.get("max_stack") != null:
		expected = int(rec.get("max_stack"))
	else:
		# The documented consequence of an unpublished stack size (items.md "API-only items"): the fallback, named in
		# the record's gaps and in inventory.json's reason for it.
		expected = int(inv.get("unpublished_max_stack", -1))
		if not _gap_mentions(rec, "max_stack"):
			p.append("max_stack: null without a documented gap")
		if not String(inv.get("unpublished_max_stack_reason", "")).contains("(%s)" % id):
			p.append("max_stack: inventory.json unpublished_max_stack_reason does not name item %s (not documented)" % id)
	_eq(p, "max_stack", def.max_stack, expected)
	if expected < 1:
		return p
	# The game's inventory: one stack more than fits in a slot fills one slot and starts the next, in the record's tab.
	var c := CharacterState.new()
	var n := expected + 1
	var added := c.inventory.add(id, n, d)
	_eq(p, "max_stack: units added", added, n)
	if Inventory.TABS.has(tab):
		var row := c.inventory.slots(tab)
		_eq(p, "max_stack: first slot of the %s tab" % tab, int(row[0].get("qty", 0)) if row.size() > 0 else 0, expected)
		_eq(p, "max_stack: second slot of the %s tab" % tab, int(row[1].get("qty", 0)) if row.size() > 1 else 0, 1)
	else:
		p.append("tab: %s is not an inventory tab" % tab)
	for other in Inventory.TABS:
		if other == tab:
			continue
		for s in c.inventory.slots(other):
			if not (s as Dictionary).is_empty():
				p.append("tab: a unit went to the %s tab instead of %s" % [other, tab])
	return p


func _slot_problems(id: String, rec: Dictionary, d: ContentDB) -> PackedStringArray:
	var p: PackedStringArray = []
	var def := ItemDef.of(id, d)
	if def == null:
		return PackedStringArray(["no runtime definition"])
	var slot := _s(rec.get("equip_slot"))
	if _s(rec.get("type")) == "Equip":
		if SUBTYPE_SLOT.get(_s(rec.get("subtype")), "") != slot:
			p.append("slot: %s is not the documented derivation of subtype %s" % [slot, rec.get("subtype")])
	elif slot != "":
		p.append("slot: a non-equipment record names equip slot %s" % slot)
	_eq(p, "slot", def.equip_slot, slot)
	_eq(p, "slot: is_equipment", def.is_equipment(), slot != "")
	_eq(p, "slot: is_weapon", def.is_weapon(), slot == "weapon")
	var c := _wearer(rec, d)
	var items := _service(c, d)
	c.inventory.add(id, 1, d)
	var res := items.equip(id)
	if slot == "":
		_eq(p, "slot: equipping a non-equipment item", String(res.get("code", "")), ItemCodes.NOT_EQUIPMENT)
		_eq(p, "slot: the item stays in the bag", c.inventory.count(id), 1)
	else:
		_eq(p, "slot: equip result", String(res.get("code", "")), ItemCodes.OK)
		_eq(p, "slot: the slot it went to", _s(res.get("slot")), slot)
		_eq(p, "slot: Equipment.item_in(%s)" % slot, c.equipment.item_in(slot), id)
	return p


func _requirement_problems(id: String, rec: Dictionary, d: ContentDB) -> PackedStringArray:
	var p: PackedStringArray = []
	var def := ItemDef.of(id, d)
	if def == null:
		return PackedStringArray(["no runtime definition"])
	var req: Dictionary = rec.get("requirements") if rec.get("requirements") is Dictionary else {}
	for k in req:
		if not REQUIREMENT_KEYS.has(String(k)):
			p.append("requirement %s: no runtime check enforces it" % k)
	var level := int(_n(req.get("level")))
	var fame := int(_n(req.get("fame")))
	var jobs: Array = req.get("job") if req.get("job") is Array else []
	var gender := _gender_of(rec)
	_eq(p, "level", def.req_level, level)
	_eq(p, "fame", def.req_fame, fame)
	_eq(p, "job", Array(def.req_jobs), jobs)
	for k in REQ_STATS:
		_eq(p, "requirement %s" % k, int(def.req_stats.get(k, 0)), int(_n(req.get(k))))
	_eq(p, "gender", def.gender, gender)
	var tab := _s(rec.get("inventory_tab"))
	if tab == "equip":
		_equip_requirement_problems(p, id, rec, d)
	elif tab == "setup" and rec.get("setup") is Dictionary:
		# A chair enforces its level when the player sits (Chairs.use); nothing else applies to it.
		if not jobs.is_empty() or fame > 0 or _any_stat(req) or gender != "":
			p.append("requirement: a chair requirement other than level is never enforced")
		if level > 0:
			var low := _wearer(rec, d)
			low.level = level - 1
			low.inventory.add(id, 1, d)
			var res := _service(low, d).use_item(id)
			_eq(p, "level: sitting one level short", String(res.get("code", "")), ItemCodes.LEVEL_TOO_LOW)
			_eq(p, "level: the level the refusal names", res.get("required"), level)
	elif level > 0 or not jobs.is_empty() or fame > 0 or _any_stat(req) or gender != "":
		p.append("requirement: the runtime enforces no requirement on a %s item" % tab)
	return p


## Equipment.equip_check, one requirement at a time: everything met is OK, each requirement one short is refused with
## the canonical value named.
func _equip_requirement_problems(p: PackedStringArray, id: String, rec: Dictionary, d: ContentDB) -> void:
	var req: Dictionary = rec.get("requirements") if rec.get("requirements") is Dictionary else {}
	var level := int(_n(req.get("level")))
	var fame := int(_n(req.get("fame")))
	var jobs: Array = req.get("job") if req.get("job") is Array else []
	var gender := _gender_of(rec)
	var ok := _wearer(rec, d)
	_eq(p, "requirements: a character meeting all of them", String(ok.equipment.equip_check(ok, id, d).get("code", "")), ItemCodes.OK)
	if level > 0:
		var w := _wearer(rec, d)
		w.level = level - 1
		var res := w.equipment.equip_check(w, id, d)
		_eq(p, "level: one level short", String(res.get("code", "")), ItemCodes.LEVEL_TOO_LOW)
		_eq(p, "level: the level the refusal names", res.get("required"), level)
	var tags: Dictionary = (d.miso_table("inventory") as Dictionary).get("job_item_tags", {})
	if not jobs.is_empty():
		var beginner := _wearer(rec, d)
		beginner.job = "beginner"
		_eq(p, "job: a Beginner", String(beginner.equipment.equip_check(beginner, id, d).get("code", "")), ItemCodes.JOB_MISMATCH)
		for j in jobs:
			var slug := _job_slug(String(j), tags)
			if slug == "":
				p.append("job: no class wears job %s (inventory.json job_item_tags)" % j)
				continue
			var w := _wearer(rec, d)
			w.job = slug
			_eq(p, "job: a %s" % slug, String(w.equipment.equip_check(w, id, d).get("code", "")), ItemCodes.OK)
		for slug in tags:
			var listed := false
			for t in tags[slug]:
				if jobs.has(t):
					listed = true
			if listed or String(slug) == "beginner":
				continue
			var w := _wearer(rec, d)
			w.job = String(slug)
			_eq(p, "job: a %s (not listed)" % slug, String(w.equipment.equip_check(w, id, d).get("code", "")), ItemCodes.JOB_MISMATCH)
	for k in REQ_STATS:
		var need := int(_n(req.get(k)))
		if need <= 0:
			continue
		var w := _wearer(rec, d)
		w.base_stats[k] = need - 1
		var res := w.equipment.equip_check(w, id, d)
		_eq(p, "requirement %s: one point short" % k, String(res.get("code", "")), ItemCodes.STAT_TOO_LOW)
		_eq(p, "requirement %s: the stat the refusal names" % k, _s(res.get("stat")), k)
		_eq(p, "requirement %s: the value the refusal names" % k, res.get("required"), need)
	if fame > 0:
		var w := _wearer(rec, d)
		w.fame = fame - 1
		var res := w.equipment.equip_check(w, id, d)
		_eq(p, "fame: one short", String(res.get("code", "")), ItemCodes.FAME_TOO_LOW)
		_eq(p, "fame: the value the refusal names", res.get("required"), fame)
	for g in ["male", "female"]:
		var w := _wearer(rec, d)
		w.gender = g
		var want := ItemCodes.OK if gender == "" or gender == g else ItemCodes.GENDER_MISMATCH
		_eq(p, "gender: a %s character" % g, String(w.equipment.equip_check(w, id, d).get("code", "")), want)


func _stat_problems(id: String, rec: Dictionary, d: ContentDB) -> PackedStringArray:
	var p: PackedStringArray = []
	var def := ItemDef.of(id, d)
	if def == null:
		return PackedStringArray(["no runtime definition"])
	var stats: Dictionary = rec.get("stats") if rec.get("stats") is Dictionary else {}
	var bonus := {}
	for k in Equipment.BONUS_KEYS:
		bonus[k] = 0
	var extra := {}
	var slots := 0
	for k in stats:
		var key := String(k)
		if STAT_BONUS.has(key):
			bonus[STAT_BONUS[key]] = int(bonus[STAT_BONUS[key]]) + int(_n(stats[k]))
		elif STAT_EXTRA.has(key):
			extra[key] = int(_n(stats[k]))
		elif key == "upgrade_slots":
			slots = int(_n(stats[k]))
		else:
			p.append("stat %s: no runtime field carries it" % key)
	for k in Equipment.BONUS_KEYS:
		_eq(p, "stat %s" % k, int(def.bonuses.get(k, 0)), int(bonus[k]))
	for k in STAT_EXTRA:
		_eq(p, "stat %s" % k, int(def.extra_stats.get(k, 0)), int(extra.get(k, 0)))
	_eq(p, "stat %s: keys present" % ",".join(STAT_EXTRA), def.extra_stats.keys().size(), extra.keys().size())
	_eq(p, "upgrade_slots", def.upgrade_slots, slots)
	if _s(rec.get("inventory_tab")) != "equip":
		if not stats.is_empty():
			p.append("stats: rows on a non-equipment item are never applied")
		return p
	# Worn, the piece's rows reach the equipment totals and the stat calculator (canonical "hp" is Max HP).
	var c := _wearer(rec, d)
	c.inventory.add(id, 1, d)
	if not bool(_service(c, d).equip(id).get("ok", false)):
		p.append("stats: the piece could not be worn to read its totals")
		return p
	var total := c.equipment.total_bonuses(d)
	for k in Equipment.BONUS_KEYS:
		_eq(p, "stat %s: Equipment.total_bonuses" % k, int(total.get(k, 0)), int(bonus[k]))
	for k in STAT_EXTRA:
		_eq(p, "stat %s: Equipment.total_bonuses" % k, int(total.get(k, 0)), int(extra.get(k, 0)))
	_eq(p, "stat max_hp: StatCalculator.max_hp", StatCalculator.max_hp(c, d), c.base_max_hp + int(bonus["max_hp"]))
	_eq(p, "stat max_mp: StatCalculator.max_mp", StatCalculator.max_mp(c, d), c.base_max_mp + int(bonus["max_mp"]))
	for k in REQ_STATS:
		_eq(p, "stat %s: StatCalculator.total_stat" % k, StatCalculator.total_stat(c, k, d), c.get_base_stat(k) + int(bonus[k]))
	return p


func _weapon_problems(id: String, rec: Dictionary, d: ContentDB) -> PackedStringArray:
	var p: PackedStringArray = []
	var def := ItemDef.of(id, d)
	if def == null:
		return PackedStringArray(["no runtime definition"])
	var w: Variant = rec.get("weapon")
	if not (w is Dictionary):
		if _s(rec.get("equip_slot")) == "weapon":
			p.append("weapon: a weapon-slot record without weapon data")
		_eq(p, "weapon: weapon_type", def.weapon_type, "")
		_eq(p, "weapon: attack_speed", def.attack_speed, 0)
		_eq(p, "weapon: multipliers", def.multipliers.size(), 0)
		return p
	var wd: Dictionary = w
	if _s(rec.get("equip_slot")) != "weapon":
		p.append("weapon: weapon data on a record whose equip slot is %s" % _s(rec.get("equip_slot")))
	if def.weapon_type == "":
		p.append("weapon: the runtime item has no weapon data")
		return p
	var subtype := _s(wd.get("weapon_type")) if _s(wd.get("weapon_type")) != "" else _s(rec.get("subtype"))
	if subtype != _s(rec.get("subtype")):
		p.append("weapon: weapon_type %s is not the subtype %s (items.md: weapon_type = subtype)" % [subtype, rec.get("subtype")])
	_eq(p, "weapon: weapon_type", def.weapon_type, subtype)
	_eq(p, "weapon: attack_speed", def.attack_speed, int(_n(wd.get("attack_speed"))))
	_eq(p, "weapon: attack_speed_name", def.attack_speed_name, _s(wd.get("attack_speed_name")))
	var mults: Dictionary = wd.get("multipliers") if wd.get("multipliers") is Dictionary else {}
	_eq(p, "weapon: multipliers", def.multipliers, mults)
	var mix: Dictionary = wd.get("basic_attack_mix_pct") if wd.get("basic_attack_mix_pct") is Dictionary else {}
	_eq(p, "weapon: basic_attack_mix_pct", def.action_mix_pct, mix)
	_eq(p, "weapon: attack_cycle_ms", def.attack_cycle_ms, int(_n(wd.get("attack_cycle_ms"))))
	_eq(p, "weapon: basic_attacks", def.basic_attacks, wd.get("basic_attacks") if wd.get("basic_attacks") is Array else [])
	# The damage category: the damage.json weapon family the ItemDef path (inventory.json weapon_subtypes) and the
	# combat path (WeaponProfile) both use, whose label names this weapon kind.
	var physical: Dictionary = d.formula("damage").get("physical", {})
	var family_label := ""
	for f in physical.get("weapon_families", []):
		if String(f.get("key", "")) == def.damage_family:
			family_label = String(f.get("label", ""))
	var word := _s(rec.get("subtype")).replace("One-Handed ", "").replace("Two-Handed ", "").replace(" Weapon", "")
	if family_label == "" or not family_label.contains(word):
		p.append("weapon: damage category %s (%s) does not name a %s" % [def.damage_family, family_label, word])
	var profile := WeaponProfile.from_item(id, d)
	_eq(p, "weapon: WeaponProfile resolves", profile.valid, true)
	_eq(p, "weapon: damage category of the combat path", profile.stat_family, def.damage_family)
	var stats: Dictionary = rec.get("stats") if rec.get("stats") is Dictionary else {}
	_eq(p, "weapon: watk in combat", profile.watk, int(_n(stats.get("watk"))))
	_eq(p, "weapon: attack_speed in combat", profile.speed_tier, int(_n(wd.get("attack_speed"))))
	# The multipliers the damage formula uses (damage.json rows reached through both paths) are the item page's.
	var row: Dictionary = (physical.get("weapon_action_multipliers", {}) as Dictionary).get(def.multiplier_key, {})
	if mults.has("swing") or mults.has("stab"):
		for a in ["swing", "stab"]:
			_eq(p, "weapon: multipliers %s in damage.json" % a, _n(row.get(a)), _n(mults.get(a)))
			_eq(p, "weapon: multipliers %s in combat" % a, profile.multiplier(a), _n(mults.get(a)))
	if mults.has("firing"):
		_eq(p, "weapon: multipliers firing in damage.json", _n(row.get("shoot")), _n(mults.get("firing")))
		_eq(p, "weapon: multipliers firing in combat", profile.multiplier("shoot"), _n(mults.get("firing")))
		var close: Dictionary = CombatRules.of(d).special_branches.get("close_range_ranged_swing", {})
		_eq(p, "weapon: multipliers close_range in combat", _n(close.get("weapon_mult")), _n(mults.get("close_range")))
	# The ordinary-attack mix the combat rules use (damage.json ordinary_action_odds) is the item page's.
	if not mix.is_empty():
		var odds: Dictionary = (physical.get("ordinary_action_odds", {}) as Dictionary).get(def.action_odds_key, {})
		_eq(p, "weapon: basic_attack_mix_pct swing in the combat odds", _n(odds.get("swing_pct")), _n(mix.get("swing")))
		_eq(p, "weapon: basic_attack_mix_pct stab in the combat odds", _n(odds.get("stab_pct")), _n(mix.get("stab")))
	# The attack cycle the game plays is the item page's (attack_speed.json ladder at the weapon's tier).
	if wd.get("attack_cycle_ms") != null:
		var action := "shoot" if profile.ranged else "swing"
		_eq(p, "weapon: attack cycle in combat", profile.attack_duration_ms(action, d), int(_n(wd.get("attack_cycle_ms"))))
	if wd.get("attack_cycle_by_kind_ms") is Dictionary:
		for k in wd["attack_cycle_by_kind_ms"]:
			var ms: Variant = (wd["attack_cycle_by_kind_ms"][k] as Dictionary).get("ms")
			_eq(p, "weapon: %s attack cycle in combat" % k, profile.attack_duration_ms(String(k), d), int(_n(ms)))
	# The reach: every basic attack on the item page plays in combat with the item page's hit box (WeaponProfile picks
	# an attack_styles.json hit-zone set; CombatReach swings its box), and combat plays no other basic attack.
	var basics: Array = wd.get("basic_attacks") if wd.get("basic_attacks") is Array else []
	var page_actions: Array = []
	for b in basics:
		var action := String((b as Dictionary).get("action", ""))
		var kind := String((b as Dictionary).get("kind", ""))
		kind = "stab" if kind == "thrust" else kind
		page_actions.append(action)
		if not profile.presentations.has(action):
			p.append("weapon: basic attack %s has no hit box in combat (hit-zone set %s)" % [action, profile.hitzone_set])
			continue
		_eq(p, "weapon: basic attack %s hit box in combat [left, top, right, bottom]" % action,
			_box_of(profile.hit_box_px(action)), (b as Dictionary).get("box_px"))
		if not profile.presentations_for(kind).has(action):
			p.append("weapon: basic attack %s is not one of combat's basic %s attacks %s" % [action, kind, profile.presentations_for(kind)])
	var combat_actions: Array = []
	for kind in profile.basic_presentations:
		for action in profile.basic_presentations[kind]:
			combat_actions.append(String(action))
	page_actions.sort()
	combat_actions.sort()
	if not basics.is_empty():
		_eq(p, "weapon: basic attacks in combat", combat_actions, page_actions)
	return p


func _consumable_problems(id: String, rec: Dictionary, d: ContentDB) -> PackedStringArray:
	var p: PackedStringArray = []
	var def := ItemDef.of(id, d)
	if def == null:
		return PackedStringArray(["no runtime definition"])
	var cons: Dictionary = rec.get("consumable") if rec.get("consumable") is Dictionary else {}
	for k in cons:
		if not CONSUMABLE_KEYS.has(String(k)):
			p.append("consumable field %s: no runtime effect applies it" % k)
	var hp := int(_n(cons.get("hp_restore")))
	var mp := int(_n(cons.get("mp_restore")))
	var hp_pct := float(_n(cons.get("hp_restore_pct")))
	var mp_pct := float(_n(cons.get("mp_restore_pct")))
	var buffs: Array = cons.get("buffs") if cons.get("buffs") is Array else []
	_eq(p, "hp_restore", def.hp_flat, hp)
	_eq(p, "mp_restore", def.mp_flat, mp)
	_eq(p, "hp_restore_pct", def.hp_pct, hp_pct)
	_eq(p, "mp_restore_pct", def.mp_pct, mp_pct)
	_eq(p, "pet_fullness_restore", def.pet_fullness, int(_n(cons.get("pet_fullness_restore"))))
	_eq(p, "buffs", def.buffs, buffs)
	# A scroll's block is carried verbatim (ITEMS.md: scroll application is not built yet).
	_eq(p, "scroll", def.scroll, rec.get("scroll") if rec.get("scroll") is Dictionary else {})
	# Using it the way the inventory window and the quickslots do (ItemService.use_item). Chairs sit instead (the setup
	# family); everything else restores exactly the record's HP and MP and is used up, or is refused when the record
	# gives no HP, MP or buff effect (pet food needs a pet; scrolls, arrows, equipment and Etc items are not usable).
	if rec.get("setup") is Dictionary and _s(rec.get("inventory_tab")) == "setup":
		return p
	var c := CharacterState.new()
	c.base_max_hp = 30000
	c.base_max_mp = 30000
	c.hp = 1
	c.mp = 0
	var held := mini(2, maxi(1, def.max_stack))
	c.inventory.add(id, held, d)
	var res := _service(c, d).use_item(id)
	var restores := hp > 0 or mp > 0 or hp_pct > 0.0 or mp_pct > 0.0 or not buffs.is_empty()
	if _s(rec.get("type")) == "Use" and restores:
		var max_hp := StatCalculator.max_hp(c, d)
		var max_mp := StatCalculator.max_mp(c, d)
		_eq(p, "use: result", String(res.get("code", "")), ItemCodes.OK)
		_eq(p, "hp_restore: HP gained", int(res.get("hp_gained", -1)), hp + int(floor(max_hp * hp_pct / 100.0)))
		_eq(p, "mp_restore: MP gained", int(res.get("mp_gained", -1)), mp + int(floor(max_mp * mp_pct / 100.0)))
		_eq(p, "use: one unit used up", c.inventory.count(id), held - 1)
	else:
		_eq(p, "use: an item with no HP, MP or buff effect", String(res.get("code", "")), ItemCodes.NOT_USABLE)
		_eq(p, "use: nothing used up", c.inventory.count(id), held)
		_eq(p, "hp_restore: HP unchanged", c.hp, 1)
	return p


func _setup_problems(id: String, rec: Dictionary, d: ContentDB) -> PackedStringArray:
	var p: PackedStringArray = []
	var def := ItemDef.of(id, d)
	if def == null:
		return PackedStringArray(["no runtime definition"])
	var st: Dictionary = rec.get("setup") if rec.get("setup") is Dictionary else {}
	var chair := _s(rec.get("inventory_tab")) == "setup" and not st.is_empty()
	if not st.is_empty() and _s(rec.get("inventory_tab")) != "setup":
		p.append("chair: setup data on a %s item" % _s(rec.get("inventory_tab")))
	_eq(p, "chair: is_chair", def.is_chair(), chair)
	_eq(p, "hp_recovery_bonus", def.setup_hp_bonus, int(_n(st.get("hp_recovery_bonus"))))
	_eq(p, "interval_s", def.setup_interval_s, float(_n(st.get("interval_s"))))
	var expected := {"hp": int(_n(st.get("hp_recovery_bonus"))), "interval_s": float(_n(st.get("interval_s")))} if chair else {}
	_eq(p, "chair: Chairs.bonus (hp_recovery_bonus, interval_s)", Chairs.bonus(id, d), expected)
	if not chair:
		return p
	# Sitting on it the way the Set-up tab and the quickslots do: it sits, stands on a second use, and is never used up.
	var c := _wearer(rec, d)
	c.inventory.add(id, 1, d)
	var seat := FakeSeat.new()
	var items := _service(c, d, seat)
	var sat := items.use_item(id)
	_eq(p, "chair: sitting", String(sat.get("code", "")), ItemCodes.OK)
	_eq(p, "chair: sat on it", seat.chair, id)
	var stood := items.use_item(id)
	_eq(p, "chair: a second use stands up", String(stood.get("action", "")), "stand")
	_eq(p, "chair: not used up", c.inventory.count(id), 1)
	return p


func _price_problems(id: String, rec: Dictionary, d: ContentDB) -> PackedStringArray:
	var p: PackedStringArray = []
	var def := ItemDef.of(id, d)
	if def == null:
		return PackedStringArray(["no runtime definition"])
	var buy: Variant = rec.get("npc_buy_price_mesos")
	_eq(p, "buy: npc_buy_price_mesos", def.buy_price, -1 if buy == null else int(buy))
	var listed: Array = []
	var sources: Dictionary = rec.get("sources") if rec.get("sources") is Dictionary else {}
	if sources.get("shops") is Array:
		listed = sources["shops"]
	# items.md: npc_buy_price_mesos is derived as the lowest price of the record's own shop list.
	var lowest: Variant = null
	for s in listed:
		if lowest == null or int(_n(s.get("price_mesos"))) < int(lowest):
			lowest = int(_n(s.get("price_mesos")))
	_eq(p, "buy: npc_buy_price_mesos is the lowest listed price", -1 if buy == null else int(buy), -1 if lowest == null else int(lowest))
	# Buying in the game's shops: every Maple Island shop row of this item costs what the record lists for that NPC, and
	# every NPC the record lists with a Maple Island shop sells it there.
	var shop_npcs := {}
	for sid in d.ids("shops"):
		var shop := d.shop(sid)
		shop_npcs[String(shop.get("npc_id", ""))] = sid
		for row in shop.get("items", []):
			if String(row.get("item_id", "")) != id:
				continue
			var want: Variant = null
			for s in listed:
				if String(s.get("npc_id", "")) == String(shop.get("npc_id", "")):
					want = int(_n(s.get("price_mesos")))
			if want == null:
				p.append("buy: %s sells it but the record lists no price for NPC %s" % [sid, shop.get("npc_id")])
				continue
			var c := CharacterState.new()
			c.mesos = RICH
			var q := ShopService.quote_buy(c, sid, id, 1, d)
			_eq(p, "buy: %s quote" % sid, String(q.get("code", "")), ItemCodes.OK)
			_eq(p, "buy: %s price" % sid, int(q.get("price", -1)), int(want))
			_eq(p, "buy: %s units per purchase" % sid, int(q.get("units", -1)), int(_n(row.get("quantity_per_purchase", 1))))
	for s in listed:
		var npc := String(s.get("npc_id", ""))
		if shop_npcs.has(npc) and ShopService.row_for(shop_npcs[npc], id, d).is_empty():
			p.append("buy: the record lists %s (%s) but that Maple Island shop has no row for it" % [s.get("npc_name"), npc])
	# Selling the way the shop window does (ShopService.quote_sell): the record's sell-back per unit, or refused when
	# the record gives none.
	var sell: Variant = rec.get("sell_price_mesos")
	_eq(p, "sell: sell_price_mesos", def.sell_price, -1 if sell == null else int(sell))
	_eq(p, "sell: sell_price_basis", def.sell_basis, _s(rec.get("sell_price_basis")))
	_eq(p, "sell: the shop window's sell-back price (ShopService.sell_price)", ShopService.sell_price(id, d), -1 if sell == null else int(sell))
	var seller := CharacterState.new()
	var qty := 2 if def.max_stack > 1 else 1
	seller.inventory.add(id, qty, d)
	var any_shop := d.ids("shops")[0] if d.ids("shops").size() > 0 else ""
	var res := ShopService.quote_sell(seller, any_shop, id, qty, d)
	if sell == null:
		_eq(p, "sell: no sell-back value", String(res.get("code", "")), ItemCodes.NO_SELL_PRICE)
	elif not ItemsConfig.protected_item(id, d).is_empty():
		# A protected item (inventory.json shop.protected_items, owner ruling #7) keeps its canonical sell-back value,
		# but no shop buys it.
		_eq(p, "sell: protected item refused", String(res.get("code", "")), ShopService.PROTECTED_ITEM)
	else:
		_eq(p, "sell: quote", String(res.get("code", "")), ItemCodes.OK)
		_eq(p, "sell: total for %d" % qty, int(res.get("total", -1)), int(sell) * qty)
		_eq(p, "sell: basis", _s(res.get("basis")), _s(rec.get("sell_price_basis")))
	return p


# --- helpers ------------------------------------------------------------------------------------------------------

## A seated-state owner for Chairs (contract C5's duck type), so the chair checks need no player or world.
class FakeSeat:
	extends RefCounted
	var chair := ""

	func is_seated() -> bool:
		return chair != ""

	func seated_chair_id() -> String:
		return chair

	func can_sit() -> String:
		return ""

	func sit(chair_id: String) -> bool:
		chair = chair_id
		return true

	func stand_up(_reason: StringName = &"") -> bool:
		var was := chair != ""
		chair = ""
		return was


## Every item id in the canonical folder, sorted (the files, not ContentDB's list).
func _item_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for f in DirAccess.get_files_at(ITEMS_DIR):
		var name := f.trim_suffix(".remap")
		if name.get_extension() == "json":
			out.append(name.get_basename())
	out.sort()
	return out


## The canonical record as the file says (a fresh parse each call, so a caller may change its copy).
func _canonical(id: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_DIR.path_join(id + ".json")))
	return data if data is Dictionary else {}


## Runs one comparator over every item file against the shared game content, one failure per problem.
func _run_family(family: String, comparator: Callable) -> void:
	var ids := _item_ids()
	assert_true(ids.size() > 0, "%s: no item files" % family)
	for id in ids:
		for problem in comparator.call(id, _canonical(id), db()):
			fail("%s %s (%s): %s" % [family, id, _canonical(id).get("name", "?"), problem])


## The comparator finds nothing on the true record of `id` and finds `expect_word` once `path` is set to `value`.
func _expect_caught(comparator: Callable, id: String, path: String, value: Variant, expect_word: String) -> void:
	var clean: PackedStringArray = comparator.call(id, _canonical(id), db())
	assert_eq(clean.size(), 0, "%s: the true record has no problem: %s" % [id, "; ".join(clean)])
	var got: PackedStringArray = comparator.call(id, _set_path(_canonical(id), path, value), db())
	assert_true(_mentions(got, expect_word), "%s with %s = %s is caught (mentioning %s); got %s" % [id, path, var_to_str(value), expect_word, "; ".join(got)])


func _mentions(problems: PackedStringArray, word: String) -> bool:
	for s in problems:
		if s.contains(word):
			return true
	return false


## A copy of `rec` with "a/b" set to `value` (intermediate dictionaries must exist).
func _set_path(rec: Dictionary, path: String, value: Variant) -> Dictionary:
	var out := rec.duplicate(true)
	var parts := path.split("/")
	var cur: Dictionary = out
	for i in parts.size() - 1:
		cur = cur[parts[i]]
	cur[parts[parts.size() - 1]] = value
	return out


## A private copy of the game content whose item record of `id` has `path` set to `value` (the shared db() is untouched).
func _db_with(id: String, path: String, value: Variant) -> ContentDB:
	return _db_with_record("items", id, _set_path(db().item(id), path, value))


## A private copy of the game content whose `domain` record `id` is `rec` (the shared db() is untouched).
func _db_with_record(domain: String, id: String, rec: Dictionary) -> ContentDB:
	var d := ContentDB.new()
	d.canonical = db().canonical.duplicate()
	var records: Dictionary = (db().canonical[domain] as Dictionary).duplicate()
	records[id] = rec
	d.canonical[domain] = records
	d.miso = db().miso
	d.loaded = true
	return d


## A private copy of `base` whose game/data/misostory table `basename` is `table` (`base` is untouched).
func _db_with_miso_table(base: ContentDB, basename: String, table: Dictionary) -> ContentDB:
	var d := ContentDB.new()
	d.canonical = base.canonical
	d.miso = base.miso.duplicate()
	var root: Dictionary = (base.miso.get("", {}) as Dictionary).duplicate()
	root[basename] = table
	d.miso[""] = root
	d.loaded = true
	return d


## A character who meets every requirement of `rec` (its level, first job, stats, fame and gender).
func _wearer(rec: Dictionary, d: ContentDB) -> CharacterState:
	var req: Dictionary = rec.get("requirements") if rec.get("requirements") is Dictionary else {}
	var c := CharacterState.new()
	c.level = maxi(1, int(_n(req.get("level"))))
	c.job = "beginner"
	var jobs: Array = req.get("job") if req.get("job") is Array else []
	if not jobs.is_empty():
		var slug := _job_slug(String(jobs[0]), (d.miso_table("inventory") as Dictionary).get("job_item_tags", {}))
		if slug != "":
			c.job = slug
	for k in REQ_STATS:
		c.base_stats[k] = maxi(c.get_base_stat(k), int(_n(req.get(k))))
	c.fame = int(_n(req.get("fame")))
	var g := _gender_of(rec)
	c.gender = g if g != "" else "male"
	c.hp = 50
	return c


## An ItemService on `c` that never consults the live game: alive, and seated through `seat` when given.
func _service(c: CharacterState, d: ContentDB, seat: Object = null) -> ItemService:
	var items := ItemService.new(c, d, null)
	items.dead_check = func() -> bool: return false
	items.seat = seat if seat != null else FakeSeat.new()
	return items


## The class slug whose item tags (inventory.json job_item_tags) include `job`, or "".
func _job_slug(job: String, tags: Dictionary) -> String:
	var slugs := tags.keys()
	slugs.sort()
	for slug in slugs:
		if (tags[slug] as Array).has(job):
			return String(slug)
	return ""


## The record's gender restriction as the runtime words it: "male", "female", or "" for any / none.
func _gender_of(rec: Dictionary) -> String:
	var g := _s(rec.get("gender"))
	return "" if g == "any" else g


## A hit box as the item page writes it: [left, top, right, bottom] in px.
static func _box_of(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.end.x, r.end.y]


func _any_stat(req: Dictionary) -> bool:
	for k in REQ_STATS:
		if int(_n(req.get(k))) > 0:
			return true
	return false


## True when one of the record's gaps is about `field` (it starts with the field name).
func _gap_mentions(rec: Dictionary, field: String) -> bool:
	for g in rec.get("gaps", []):
		if String(g).begins_with(field):
			return true
	return false


## Appends "label: runtime X, canonical Y" when the two differ (numbers compare by value, containers deeply).
func _eq(p: PackedStringArray, label: String, runtime: Variant, canonical: Variant) -> void:
	if not _same(runtime, canonical):
		p.append("%s: runtime %s, canonical %s" % [label, var_to_str(runtime), var_to_str(canonical)])


static func _same(a: Variant, b: Variant) -> bool:
	var na := a is int or a is float
	var nb := b is int or b is float
	if na or nb:
		return na and nb and is_equal_approx(float(a), float(b))
	if (a is String or a is StringName) and (b is String or b is StringName):
		return String(a) == String(b)
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k in a:
			if not (b as Dictionary).has(k) or not _same(a[k], b[k]):
				return false
		return true
	if (a is Array or a is PackedStringArray) and (b is Array or b is PackedStringArray):
		var aa := Array(a)
		var bb := Array(b)
		if aa.size() != bb.size():
			return false
		for i in aa.size():
			if not _same(aa[i], bb[i]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


static func _s(v: Variant) -> String:
	return "" if v == null else str(v)


static func _n(v: Variant) -> float:
	return 0.0 if v == null or not (v is int or v is float) else float(v)
