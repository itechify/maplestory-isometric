extends TestCase
## CharacterFactory: a new character's exact values (canonical formulas/beginner.json + new_character.json
## adaptations), creation-AP validation, name rules and the starter-weapon choice. Expected numbers are read from
## the same data the factory uses, never typed in here.


func _beginner() -> Dictionary:
	return db().formula("beginner")


func _rules() -> Dictionary:
	return CharacterFactory.rules_table(db())


func _params(ap: Variant = null, weapon: Variant = null, char_name: Variant = "Tester") -> Dictionary:
	var weapons := CharacterFactory.creation_weapon_ids(db())
	var allocatable: Array = _beginner()["ap"]["allocatable_stats"]
	return {
		"name": char_name,
		"ap": ap if ap != null else {String(allocatable[0]): int(_beginner()["creation_ap"])},
		"weapon_id": weapon if weapon != null else weapons[0],
	}


func test_new_character_exact_values() -> void:
	var b := _beginner()
	var rules := _rules()
	var creation_ap := int(b["creation_ap"])
	var placed := {"str": creation_ap - 3, "dex": 3}
	var result := CharacterFactory.create(_params(placed), db())
	assert_true(result.ok, "creation failed: %s" % ", ".join(result.errors))
	var c := result.character
	assert_eq(c.name, "Tester")
	assert_eq(c.job, String(b["class_slug"]), "job")
	assert_eq(c.level, int(b["starting_level"]), "level")
	assert_eq(c.exp, int(rules["starting_exp"]["value"]), "exp")
	assert_eq(c.base_max_hp, int(b["hp_mp"]["base_hp"]), "base max HP")
	assert_eq(c.base_max_mp, int(b["hp_mp"]["base_mp"]), "base max MP")
	assert_eq(c.hp, c.base_max_hp, "starts at full HP")
	assert_eq(c.mp, c.base_max_mp, "starts at full MP")
	# MeowDB's level-1 row of the HP/MP table agrees with base_hp/base_mp.
	var row: Dictionary = b["hp_mp"]["by_level_1_to_10"][0]
	assert_eq(c.base_max_hp, int(row["hp"]), "by_level row 1 HP")
	assert_eq(c.base_max_mp, int(row["mp"]), "by_level row 1 MP")
	var start: Dictionary = b["starting_stats"]
	assert_eq(c.base_stats["str"], int(start["str"]) + creation_ap - 3, "STR = start + placed")
	assert_eq(c.base_stats["dex"], int(start["dex"]) + 3, "DEX = start + placed")
	assert_eq(c.base_stats["int"], int(start["int"]), "INT untouched")
	assert_eq(c.base_stats["luk"], int(start["luk"]), "LUK untouched")
	var stat_total := 0
	for k in CharacterState.STAT_KEYS:
		stat_total += int(c.base_stats[k])
	assert_eq(stat_total, int(b["ap"]["total_ap_at_level_1"]), "every level-1 AP is placed (Total AP at Lv 1)")
	assert_eq(c.ap, 0, "0 free AP after creation")
	assert_eq(c.ap, int(b["ap"]["free_ap_at_level_1"]) - creation_ap, "free AP = canonical free AP - creation AP")
	assert_eq(c.sp, int(rules["starting_sp"]["value"]), "SP")
	assert_eq(c.sp, 0, "a Beginner has 0 SP at level 1 (beginner.json sp.calculator_caveat)")
	assert_eq(c.mesos, int(rules["starting_mesos"]["value"]), "mesos")
	assert_eq(c.mesos, 0, "mesos 0 (MeowDB documents no starting mesos)")
	assert_eq(c.fame, int(rules["starting_fame"]["value"]), "fame")
	assert_eq(c.skills, {}, "no skills")
	assert_eq(c.effects, [], "no effects")
	assert_eq(c.quickslots, {}, "no quickslots")
	assert_eq(c.flags, {}, "no flags")
	assert_eq(c.play_time_s, 0.0, "play time")
	assert_eq(c.quests.to_dict(), QuestLog.new().to_dict(), "empty quest log")


## Golden values as MeowDB publishes them (formulas/leveling, the Beginner's guide, item-db 541/576/585):
## "Every character starts with 4 STR, 4 DEX, 4 INT and 4 LUK", "You place your first 9 AP on the character creation
## screen", "BeginnerHP = 50 + 16 x (Level - 1)" / "BeginnerMP = 5 + 12 x (Level - 1)" at level 1, and the 50-meso
## starter trio Sword / Hand Axe / Wooden Club. Pinned literally so a regression in the factory OR in the extracted
## data is caught (the other tests read their expectations from the data).
func test_new_character_matches_meowdb_golden_values() -> void:
	var c := CharacterFactory.create({"name": "Golden", "ap": {"str": 5, "dex": 2, "int": 1, "luk": 1},
		"weapon_id": "585"}, db()).character
	assert_true(c != null, "created")
	if c == null:
		return
	assert_eq(c.level, 1, "level 1")
	assert_eq(c.exp, 0)
	assert_eq([c.hp, c.base_max_hp], [50, 50], "HP 50 / 50")
	assert_eq([c.mp, c.base_max_mp], [5, 5], "MP 5 / 5")
	assert_eq(c.base_stats, {"str": 9, "dex": 6, "int": 5, "luk": 5}, "4/4/4/4 + the 9 creation AP")
	assert_eq(c.ap, 0, "every level-1 AP placed")
	assert_eq(c.sp, 0)
	assert_eq(c.mesos, 0)
	assert_eq(c.job, "beginner")
	assert_eq(c.equipment.weapon_id(), "585", "Wooden Club in hand")
	assert_eq(CharacterFactory.creation_weapon_ids(db()), PackedStringArray(["541", "576", "585"]), "the trio")
	assert_eq(c.location["map_id"], "000000001", "start map (adaptation)")


func test_every_creation_weapon_is_equipped_for_every_build() -> void:
	var b := _beginner()
	var creation_ap := int(b["creation_ap"])
	for weapon in CharacterFactory.creation_weapon_ids(db()):
		for stat in b["ap"]["allocatable_stats"]:
			var r := CharacterFactory.create(_params({String(stat): creation_ap}, weapon), db())
			assert_true(r.ok, "%s with all AP in %s: %s" % [weapon, stat, ", ".join(r.errors)])
			if not r.ok:
				continue
			assert_eq(r.weapon_placement, CharacterFactory.PLACED_EQUIPPED, "%s / %s placement" % [weapon, stat])
			assert_eq(r.character.equipment.weapon_id(), weapon, "%s / %s equipped" % [weapon, stat])
			assert_true(r.character.inventory.is_empty(), "%s / %s: nothing else in the bag" % [weapon, stat])
			assert_eq(r.warnings.size(), 0, "%s / %s: no warnings %s" % [weapon, stat, ", ".join(r.warnings)])


func test_a_broken_start_location_is_refused() -> void:
	# A private ContentDB sharing the canonical data, with its own copy of the adaptation tables.
	var broken := ContentDB.new()
	broken.canonical = db().canonical
	broken.miso = db().miso.duplicate(true)
	var start: Dictionary = broken.miso[""]["new_character"]["start_location"]
	start["map_id"] = "999999999"
	assert_false(CharacterFactory.create(_params(), broken).ok, "an unknown start map is refused")
	assert_false(CharacterFactory.validate_start_location(broken).is_empty(), "with a reason")
	start["map_id"] = String(_rules()["start_location"]["map_id"])
	start["spawn_index"] = (db().map(start["map_id"])["player_spawns"] as Array).size()
	assert_false(CharacterFactory.create(_params(), broken).ok, "a spawn index past the map's player spawns is refused")
	assert_true(CharacterFactory.validate_start_location(db()).is_empty(), "the shipped start location is valid")


func test_new_character_starts_at_the_adapted_start_map() -> void:
	var start: Dictionary = _rules()["start_location"]
	var map_id := String(start["map_id"])
	assert_true(db().has("maps", map_id), "start map %s exists in canonical maps" % map_id)
	var spawns: Array = db().map(map_id)["player_spawns"]
	assert_between(int(start["spawn_index"]), 0, spawns.size() - 1, "start spawn index is a real player spawn")
	assert_eq(start.get("verified"), false, "the start map is an unverified adaptation")
	assert_true(String(start.get("reason", "")).length() > 20, "start map has a reason")
	var c := CharacterFactory.create(_params(), db()).character
	assert_eq(c.location, {"map_id": map_id, "entry": {"map_id": map_id, "spawn_index": int(start["spawn_index"])}},
		"location")
	assert_eq(c.respawn_reference, String(db().map(map_id)["return_map_id"]), "respawn = canonical return map")


func test_creation_ap_may_be_split_across_all_stats() -> void:
	var b := _beginner()
	var creation_ap := int(b["creation_ap"])
	var allocatable: Array = b["ap"]["allocatable_stats"]
	var placed := {}
	var left := creation_ap
	for i in allocatable.size():
		var pts := left if i == allocatable.size() - 1 else mini(left, i + 1)
		placed[String(allocatable[i])] = pts
		left -= pts
	var result := CharacterFactory.create(_params(placed), db())
	assert_true(result.ok, "split AP rejected: %s" % ", ".join(result.errors))
	for k in placed:
		assert_eq(result.character.base_stats[k], int(b["starting_stats"][k]) + int(placed[k]), "stat %s" % k)


func test_creation_ap_must_be_exactly_the_canonical_amount() -> void:
	var creation_ap := int(_beginner()["creation_ap"])
	var too_few := CharacterFactory.create(_params({"str": creation_ap - 1}), db())
	assert_false(too_few.ok, "fewer than creation AP rejected")
	var too_many := CharacterFactory.create(_params({"str": creation_ap, "luk": 1}), db())
	assert_false(too_many.ok, "more than creation AP rejected")
	var none := CharacterFactory.create(_params({}), db())
	assert_false(none.ok, "no AP placed rejected")
	assert_true(too_few.character == null and too_many.character == null, "no character on failure")


func test_creation_ap_rejects_bad_entries() -> void:
	var creation_ap := int(_beginner()["creation_ap"])
	var cases := {
		"negative": {"str": creation_ap + 1, "dex": -1},
		"fraction": {"str": creation_ap - 0.5, "dex": 0.5},
		"unknown stat": {"str": creation_ap - 1, "hp": 1},
		"string points": {"str": str(creation_ap)},
	}
	for label in cases:
		var r := CharacterFactory.create(_params(cases[label]), db())
		assert_false(r.ok, "%s accepted" % label)
		assert_true(r.errors.size() > 0, "%s has an error message" % label)
	var not_a_dict := CharacterFactory.create(_params([creation_ap]), db())
	assert_false(not_a_dict.ok, "array AP rejected")
	# JSON-parsed numbers arrive as floats; whole floats are fine.
	var from_json := CharacterFactory.create(_params({"str": float(creation_ap)}), db())
	assert_true(from_json.ok, "whole-number float AP accepted: %s" % ", ".join(from_json.errors))


func test_name_rules() -> void:
	var rules: Dictionary = _rules()["name_rules"]
	var min_len := int(rules["min_length"])
	var max_len := int(rules["max_length"])
	assert_true(CharacterFactory.validate_name("A".repeat(min_len), db()).is_empty(), "min length ok")
	assert_true(CharacterFactory.validate_name("Z9".repeat(max_len / 2) + "x".repeat(max_len % 2), db()).is_empty(),
		"max length ok")
	assert_false(CharacterFactory.validate_name("A".repeat(min_len - 1), db()).is_empty(), "too short")
	assert_false(CharacterFactory.validate_name("A".repeat(max_len + 1), db()).is_empty(), "too long")
	for bad in ["Bad Name", "Bad_Name", "Ünïcode", "Semi;colon", "../../x", "", "Tester\n", "Tester\r\n", "\nTester"]:
		assert_false(CharacterFactory.validate_name(bad, db()).is_empty(), "'%s' rejected" % bad)
	assert_false(CharacterFactory.validate_name(1234, db()).is_empty(), "non-string rejected")
	assert_false(CharacterFactory.create(_params(null, null, "x"), db()).ok, "create rejects a bad name")
	assert_eq(rules.get("verified"), false, "name rules are an unverified adaptation")


func test_creation_weapons_are_the_canonical_trio() -> void:
	var ids := CharacterFactory.creation_weapon_ids(db())
	assert_true(ids.size() > 0, "creation weapons found")
	# Cross-check two canonical sources: the item flag and beginner.json's starter list (no level requirement).
	var from_formula: PackedStringArray = []
	for w in _beginner()["starter_weapons"]["items"]:
		if int(w["level_req"]) == 0:
			from_formula.append(String(w["item_id"]))
	from_formula.sort()
	assert_eq(ids, from_formula, "flagged items == level-0 starter weapons")
	for id in ids:
		var item := db().item(id)
		assert_eq(String(item.get("equip_slot", "")), "weapon", "%s is a weapon" % id)
		assert_eq(int(item["requirements"]["level"]), 0, "%s has no level requirement" % id)
		assert_true(CharacterFactory.create(_params(null, id), db()).ok, "weapon %s accepted" % id)


func test_non_creation_weapons_are_rejected() -> void:
	var creation := CharacterFactory.creation_weapon_ids(db())
	var other_weapon := ""
	for w in _beginner()["starter_weapons"]["items"]:
		if not (String(w["item_id"]) in creation):
			other_weapon = String(w["item_id"])
	assert_ne(other_weapon, "", "beginner.json lists a non-creation starter weapon (Razor)")
	assert_false(CharacterFactory.create(_params(null, other_weapon), db()).ok, "%s rejected" % other_weapon)
	assert_false(CharacterFactory.create(_params(null, "no-such-item"), db()).ok, "unknown id rejected")
	assert_false(CharacterFactory.create(_params(null, 585), db()).ok, "non-string id rejected")


func test_starter_weapon_is_equipped_or_carried() -> void:
	var weapon := CharacterFactory.creation_weapon_ids(db())[0]
	var r := CharacterFactory.create(_params(null, weapon), db())
	assert_true(r.ok)
	var c := r.character
	var placement := String(_rules()["starter_weapon"]["placement"])
	var can_equip := Equipment.new().has_method("equip")
	var probe := Inventory.new()
	var inventory_real := probe.add(weapon, 1, db()) == 1
	if can_equip and placement == CharacterFactory.PLACED_EQUIPPED:
		assert_eq(r.weapon_placement, CharacterFactory.PLACED_EQUIPPED, "placement")
		assert_eq(c.equipment.weapon_id(), weapon, "weapon equipped")
		assert_eq(c.inventory.count(weapon), 0, "not also in the bag")
	elif inventory_real:
		assert_eq(r.weapon_placement, CharacterFactory.PLACED_INVENTORY, "placement (Equipment.equip not available)")
		assert_eq(c.inventory.count(weapon), 1, "weapon carried in the inventory")
	else:
		print("SKIP test_starter_weapon_is_equipped_or_carried: Inventory.add and Equipment.equip are still contract stubs")
		assert_eq(r.weapon_placement, CharacterFactory.PLACED_NONE, "reported as not placed")


func test_quick_start_params_are_valid() -> void:
	var p := CharacterFactory.default_params(db())
	assert_true(CharacterFactory.validate(p, db()).is_empty(), "quick start invalid: %s"
		% ", ".join(CharacterFactory.validate(p, db())))


func test_adaptation_table_marks_every_entry() -> void:
	var rules := _rules()
	assert_false(rules.is_empty(), "new_character.json loaded")
	for key in rules:
		if rules[key] is Dictionary:
			var entry: Dictionary = rules[key]
			assert_true(String(entry.get("reason", "")).length() > 0, "%s has a reason" % key)
			assert_true(entry.has("verified"), "%s states verified" % key)
