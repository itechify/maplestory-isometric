extends TestCase
## Drop data (contract C1): every canonical drop record is schema v2, every member names a real item or stays visibly
## unresolved, every rolling chance comes from KuroDB, nothing outside the records supplies a chance, quantity or meso
## amount (drop_rates.json documents rules only), and every item a Maple Island quest asks the player to collect can
## actually drop (under that quest) or be bought.


func parity_keys() -> Dictionary:
	return {
		"test_every_drop_item_exists_or_is_unresolved": ["mechanic:drop-item-ids-resolve"],
		"test_every_record_is_v2_and_passes_the_drop_policy": ["mechanic:drop-membership-and-chance-sources"],
		"test_drop_rates_json_supplies_no_values": ["mechanic:no-placeholder-drop-rates"],
		"test_every_rolling_chance_names_its_kurodb_source": ["mechanic:drop-chance-from-kurodb"],
		"test_quest_items_are_obtainable": ["quest:1005", "quest:1011", "quest:1012"],
		"test_three_snails_shells_are_obtainable": ["skill:0001000"],
		"test_meso_rules_follow_the_records": ["drop:2/mesos", "drop:3/mesos", "drop:4/mesos", "drop:5/mesos", "drop:9/mesos",
			"mechanic:meso-amount-source", "mechanic:meso-chance-source"],
		"test_rolling_entries_by_owner": ["drop:1/jr-sentinel-shellpiece", "drop:2/snail-shell", "drop:3/blue-snail-shell",
			"drop:4/mushroom-spore", "drop:5/red-snail-shell", "drop:9/orange-mushroom-cap", "drop:0000001/old-wooden-board",
			"drop:0000001/rusty-screw", "drop:0000001/apple"],
	}


func test_every_drop_item_exists_or_is_unresolved() -> void:
	for owner_id in db().ids("drops"):
		var table := db().drop_table(owner_id)
		assert_has(["monster", "breakable"], String(table.owner.kind), "%s owner kind" % owner_id)
		for e in table.entries:
			if e.item_resolution.state == "resolved":
				assert_true(e.item_id is String and db().has("items", e.item_id), "drops/%s %s: resolved item %s exists" % [owner_id, e.key, str(e.item_id)])
			else:
				assert_eq(e.item_id, null, "drops/%s %s: an unresolved member has no item id (it never rolls)" % [owner_id, e.key])


func test_v2_fixture_items_exist_or_are_unresolved() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/drops_v2/fixture_2.json"))
	assert_true(fixture is Dictionary and DropRecordChecks.is_v2(fixture), "fixture loads as v2")
	for e in fixture.entries:
		if e.item_resolution.state == "resolved":
			assert_true(db().has("items", e.item_id), "fixture %s" % e.key)
		else:
			assert_eq(e.item_id, null)


func test_every_monster_has_its_drop_table() -> void:
	for monster_id in db().ids("monsters"):
		assert_true(DropRates.has_table(monster_id, db()), "monster %s has drops/%s.json" % [monster_id, monster_id])
		assert_eq(DropRates.owner_kind(monster_id, db()), "monster")
	assert_eq(DropRates.owner_kind("0000001", db()), "breakable", "Wooden Box is a breakable, not monster 1")


func test_every_record_is_v2_and_passes_the_drop_policy() -> void:
	for owner_id in db().ids("drops"):
		assert_true(DropRates.is_v2(owner_id, db()), "drops/%s is schema v2" % owner_id)
	var r := DataValidator.validate(db(), {"world_sidecars": {}})
	for check in ["drop_record", "drop_policy"]:
		assert_eq(r.matching(check, "", "", "error").size(), 0, "%s errors: %s" % [check, str(r.matching(check, "", "", "error"))])
	assert_eq(int(r.stats.get("drop_policy_records_checked", 0)), db().ids("drops").size(), "every record held to the policy")


func test_drop_rates_json_supplies_no_values() -> void:
	var errors := DropRates.validate(db())
	assert_eq(errors.size(), 0, "\n".join(errors))
	var rates: Dictionary = db().miso_table("drop_rates")
	assert_eq(rates.get("verified"), false)
	assert_eq(String(rates.meso_amount_distribution.value), DropRates.MESO_DISTRIBUTION)
	# Any rate, quantity or meso number (or any number at all) put back into the file is refused.
	for bad in [{"chance": 0.4}, {"owner_item_overrides": {"3": {"349": {"reason": "x", "verified": false}}}},
			{"mesos": {"per_level": {"min": 1.5}}}, {"note_value": 3}]:
		var c := ContentDB.new()
		c.canonical = db().canonical
		c.miso = db().miso.duplicate()
		var singles: Dictionary = (db().miso[""] as Dictionary).duplicate()
		var copy: Dictionary = rates.duplicate(true)
		copy.merge(bad, true)
		singles["drop_rates"] = copy
		c.miso[""] = singles
		c.loaded = true
		assert_true(DropRates.validate(c).size() > 0, "drop_rates.json with %s is refused" % str(bad))
	assert_false((db().miso_table("drop_rates") as Dictionary).has("chance"), "shared db untouched")


func test_ground_rules_are_labelled_adaptations() -> void:
	var t: Dictionary = db().miso_table("drops")
	assert_eq(t.get("verified"), false)
	for key in ["ground_lifetime", "owner_exclusive", "scatter_spacing"]:
		assert_true(String(t.get(key + "_reason", "")).length() > 20, "%s_reason" % key)
	assert_true(DropRates.ground_lifetime_s(db()) > 0.0)
	assert_true(DropRates.owner_exclusive_s(db()) >= 0.0)
	assert_true(DropRates.scatter_spacing_px(db()) > 0.0)


func test_every_rolling_chance_names_its_kurodb_source() -> void:
	for owner_id in db().ids("drops"):
		var table := db().drop_table(owner_id)
		var rows := DropRates.effective_entries(owner_id, db())
		assert_eq(rows.size(), table.entries.size(), "every member is a row, rolling or not")
		for i in rows.size():
			var row: Dictionary = rows[i]
			var e: Dictionary = table.entries[i]
			assert_between(float(row.chance), 0.0, 1.0, "%s/%s chance" % [owner_id, row.key])
			assert_true(int(row.min_quantity) >= 1 and int(row.max_quantity) >= int(row.min_quantity), "%s/%s qty" % [owner_id, row.key])
			if row.excluded == "":
				assert_true(String(row.source).begins_with("KuroDB '"), "%s/%s source %s" % [owner_id, row.key, row.source])
				assert_eq(float(row.chance), float(e.probability), "%s/%s chance is the record's probability" % [owner_id, row.key])
				assert_eq(e.chance_source.authority, "KuroDB")
			else:
				assert_eq(float(row.chance), 0.0, "%s/%s never rolls" % [owner_id, row.key])
				assert_true(e.chance_state != "resolved" or e.item_id == null, "%s/%s excluded only when unresolved" % [owner_id, row.key])


func test_rolling_entries_by_owner() -> void:
	# The members that roll under the C1 rule (chance and item resolved), from the dated captures. Changing one of
	# these means a source changed: re-read the capture, then the crosswalk.
	var expected := {
		"1": {"347": 1.0},
		"2": {"348": 1.0, "270": 0.02, "242": 0.02},
		"3": {"349": 1.0, "270": 0.02, "242": 0.02},
		"4": {"350": 1.0, "270": 0.02, "242": 0.02},
		"5": {"351": 1.0, "1325": 0.0008, "270": 0.02, "242": 0.02},
		"9": {"356": 1.0, "1314": 0.0008, "1327": 0.0008, "270": 0.02},
		"0000001": {"442": 1.0, "441": 1.0, "236": 0.25},
	}
	for owner_id in expected:
		var got := {}
		for row in DropRates.effective_entries(owner_id, db()):
			if row.excluded == "":
				got[row.item_id] = row.chance
		assert_eq(got.size(), (expected[owner_id] as Dictionary).size(), "drops/%s rolling members %s" % [owner_id, str(got)])
		for item_id in expected[owner_id]:
			assert_near(float(got.get(item_id, -1.0)), float(expected[owner_id][item_id]), 1e-15, "drops/%s item %s" % [owner_id, item_id])


## Items a quest asks the player to collect (minus those the quest itself hands out on accept) -> quest id.
func _quest_collect_items() -> Dictionary:
	var out := {}
	for qid in db().ids("quests"):
		var q := db().quest(qid)
		var given := {}
		for g in q.get("items_given_on_accept", []):
			given[String(g.item_id)] = true
		for it in q.get("objectives", {}).get("item_collection", []):
			var id := String(it.item_id)
			if not given.has(id):
				out[id] = qid
	return out


## True when the item rolls somewhere while `quest_id` (if any) is in progress, or a shop sells it.
func _obtainable(item_id: String, quest_id: String = "") -> bool:
	var quests := PackedStringArray([quest_id]) if quest_id != "" else PackedStringArray()
	for owner_id in db().ids("drops"):
		for row in DropRates.effective_entries(owner_id, db()):
			if row.item_id == item_id and DropRates.may_roll(row, quests):
				return true
	for shop_id in db().ids("shops"):
		if not ShopService.row_for(shop_id, item_id, db()).is_empty():
			return true
	return false


func test_quest_items_are_obtainable() -> void:
	var needed := _quest_collect_items()
	assert_true(needed.size() > 0, "Maple Island quests ask for items")
	for item_id in needed:
		assert_true(_obtainable(item_id, needed[item_id]), "quest %s needs item %s, which nothing drops (while the quest is in progress) or sells" % [needed[item_id], item_id])
	assert_false(_obtainable("441"), "Rusty Screw drops only while Pio's quest is in progress (C1 gate)")


func test_three_snails_shells_are_obtainable() -> void:
	for skill in db().formula("beginner").skills:
		for lv in skill.get("levels", []):
			if lv.get("item_cost_id") != null:
				assert_true(_obtainable(String(lv.item_cost_id)), "skill %s cost item %s" % [skill.skill_id, lv.item_cost_id])


func test_meso_rules_follow_the_records() -> void:
	var expected := {"2": [2, 2, "MeowDB MS Classic"], "3": [4, 4, "Hidden Street"], "4": [4, 6, "Hidden Street"],
		"5": [8, 12, "Hidden Street"], "9": [9, 13, "Hidden Street"]}
	for owner_id in expected:
		var meso: Dictionary = db().drop_table(owner_id).meso
		var rule := DropRates.meso_rule(owner_id, db())
		assert_eq([rule.min, rule.max], [int(expected[owner_id][0]), int(expected[owner_id][1])], "drops/%s meso amount" % owner_id)
		assert_eq(meso.amount_source.authority, expected[owner_id][2], "drops/%s meso amount authority" % owner_id)
		assert_eq(meso.chance_source.authority, "KuroDB", "drops/%s meso chance authority" % owner_id)
		assert_eq(meso.chance_source.raw_value, "40% base | Meso drop")
		assert_near(float(rule.chance), 0.4, 1e-15, "drops/%s meso chance" % owner_id)
		assert_eq(rule.excluded, "")
	# The Tutorial Jr. Sentinel (no KuroDB meso row, Hidden Street "?") and the box drop none.
	for owner_id in ["1", "0000001"]:
		assert_eq(db().drop_table(owner_id).meso, null, "drops/%s meso null" % owner_id)
		assert_eq(DropRates.meso_rule(owner_id, db()).chance, 0.0)
	assert_eq(DropRates.meso_rule("no-such-owner", db()).chance, 0.0)
