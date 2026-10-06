extends TestCase
## Drop data (contract C1; decisions D3-11, D3-12): every canonical drop record is schema 3 and holds only sourced facts
## (no probability), every member names a real item, every rolling chance is the owner's table cell for its category
## and rarity, the two rule files are complete labelled adaptations, the meso rule follows MeowDB's reports and the
## level formula, and every item a Maple Island quest asks the player to collect can actually drop (under that quest)
## or be bought.


func parity_keys() -> Dictionary:
	return {
		"test_every_drop_item_exists_or_is_unresolved": ["mechanic:drop-item-ids-resolve"],
		"test_every_record_is_schema_3_and_passes_the_drop_policy": ["mechanic:drop-membership-and-rarity-sources",
			"canon:no-probability-in-canonical"],
		"test_the_rule_files_are_complete_labelled_adaptations": ["mechanic:no-placeholder-drop-rates", "mechanic:drop-chance-bounds"],
		"test_every_rolling_chance_is_the_table_cell": ["mechanic:drop-chance-table"],
		"test_quest_items_are_obtainable": ["quest:1005", "quest:1011", "quest:1012"],
		"test_three_snails_shells_are_obtainable": ["skill:0001000"],
		"test_meso_rules_follow_meowdb_and_the_formula": ["meso:1", "meso:2", "meso:3", "meso:4", "meso:5", "meso:9",
			"mechanic:meso-amount-source", "mechanic:meso-chance-source"],
		"test_rolling_entries_by_owner": ["drop:1/jr-sentinel-shellpiece", "drop:2/snail-shell", "drop:3/blue-snail-shell",
			"drop:4/mushroom-spore", "drop:5/red-snail-shell", "drop:9/orange-mushroom-cap", "drop:0000001/old-wooden-board",
			"drop:0000001/rusty-screw", "drop:0000001/apple", "drop:0000001/egg", "drop:5/overall-armor-def-scroll-intermediate"],
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


func test_every_monster_has_its_drop_table() -> void:
	for monster_id in db().ids("monsters"):
		assert_true(DropRates.has_table(monster_id, db()), "monster %s has drops/%s.json" % [monster_id, monster_id])
		assert_eq(DropRates.owner_kind(monster_id, db()), "monster")
	assert_eq(DropRates.owner_kind("0000001", db()), "breakable", "Wooden Box is a breakable, not monster 1")


## Every key at any depth of a record (outside commentary).
static func _keys(node: Variant, out: Dictionary) -> void:
	if node is Dictionary:
		for k in node:
			if str(k) in DropRecordChecks.COMMENT_KEYS:
				continue
			out[str(k)] = true
			_keys(node[k], out)
	elif node is Array:
		for x in node:
			_keys(x, out)


func test_every_record_is_schema_3_and_passes_the_drop_policy() -> void:
	for owner_id in db().ids("drops"):
		assert_true(DropRates.is_v3(owner_id, db()), "drops/%s is schema 3" % owner_id)
		var keys := {}
		_keys(db().drop_table(owner_id), keys)
		for bad in DropRecordChecks.NO_PROBABILITY_KEYS:
			assert_false(keys.has(bad), "drops/%s holds no '%s' (canonical data has no made-up probability)" % [owner_id, bad])
	var r := DataValidator.validate(db(), {"world_sidecars": {}})
	for check in ["drop_record", "drop_policy"]:
		assert_eq(r.matching(check, "", "", "error").size(), 0, "%s errors: %s" % [check, str(r.matching(check, "", "", "error"))])
	assert_eq(int(r.stats.get("drop_policy_records_checked", 0)), db().ids("drops").size(), "every record held to the policy")
	assert_eq(int(r.stats.get("drop_membership_lists_checked", 0)), db().ids("drops").size(), "every membership checked against its capture")


func test_the_rule_files_are_complete_labelled_adaptations() -> void:
	var errors := DropRates.validate(db())
	assert_eq(errors.size(), 0, "\n".join(errors))
	var rates: Dictionary = db().miso_table("drop_rates")
	assert_eq([rates.get("decision"), rates.get("verified")], ["D3-11", false])
	assert_eq(rates.provenance.chance_table.authority, "Project owner")
	for cat in DropRates.CATEGORIES:
		for r in DropRates.RARITIES:
			assert_between(float(rates.chance_table[cat][r]), 0.0, 1.0, "%s x %s" % [cat, r])
	assert_eq(DropRates.quantity_per_drop(db()), 1)
	var meso: Dictionary = db().miso_table("meso_rules")
	assert_eq([meso.get("decision"), meso.get("verified"), meso.get("amount_distribution")], ["D3-12", false, DropRates.MESO_DISTRIBUTION])
	assert_eq(meso.provenance.chance.authority, "Project owner")
	# Broken copies are refused, each with its reason.
	var cases := [
		["drop_rates", func(t: Dictionary) -> void: (t.chance_table.equip as Dictionary).erase("Rare"), "chance_table.equip.Rare must be a chance"],
		["drop_rates", func(t: Dictionary) -> void: t.chance_table.etc_other.Common = -0.1, "chance_table.etc_other.Common must be a chance"],
		["drop_rates", func(t: Dictionary) -> void: t.chance_table["gems"] = {}, "chance_table.gems is not a category"],
		["drop_rates", func(t: Dictionary) -> void: t.verified = true, "must say verified: false"],
		["drop_rates", func(t: Dictionary) -> void: t.decision = "D3-1", "decision must be \"D3-11\""],
		["drop_rates", func(t: Dictionary) -> void: t.quantity_per_drop = 2, "quantity_per_drop must be 1"],
		["meso_rules", func(t: Dictionary) -> void: t.chance = 1.5, "chance must be a number in [0, 1]"],
		["meso_rules", func(t: Dictionary) -> void: t.amount_level_multiplier_max = 0, "amount_level_multiplier_min / _max"],
		["meso_rules", func(t: Dictionary) -> void: t.no_mesos["zz"] = {"name": "x", "reason": "y"}, "no_mesos.zz names no drop owner"],
		["meso_rules", func(t: Dictionary) -> void: t.decision = "D3-2", "decision must be \"D3-12\""],
	]
	for case in cases:
		var c := ContentDB.new()
		c.canonical = db().canonical
		c.miso = db().miso.duplicate()
		var singles: Dictionary = (db().miso[""] as Dictionary).duplicate()
		var copy: Dictionary = (singles[case[0]] as Dictionary).duplicate(true)
		(case[1] as Callable).call(copy)
		singles[case[0]] = copy
		c.miso[""] = singles
		c.loaded = true
		var got := DropRates.validate(c)
		assert_true(Array(got).any(func(m: String) -> bool: return m.contains(case[2])), "%s: expected '%s' in %s" % [case[0], case[2], str(got)])
	assert_eq(float(db().miso_table("meso_rules").chance), 0.6, "shared db untouched")


func test_ground_rules_are_labelled_adaptations() -> void:
	var t: Dictionary = db().miso_table("drops")
	assert_eq(t.get("verified"), false)
	for key in ["ground_lifetime", "owner_exclusive", "scatter_spacing"]:
		assert_true(String(t.get(key + "_reason", "")).length() > 20, "%s_reason" % key)
	assert_true(DropRates.ground_lifetime_s(db()) > 0.0)
	assert_true(DropRates.owner_exclusive_s(db()) >= 0.0)
	assert_true(DropRates.scatter_spacing_px(db()) > 0.0)


func test_every_rolling_chance_is_the_table_cell() -> void:
	var rates: Dictionary = db().miso_table("drop_rates")
	for owner_id in db().ids("drops"):
		var table := db().drop_table(owner_id)
		var rows := DropRates.effective_entries(owner_id, db())
		assert_eq(rows.size(), table.entries.size(), "every member is a row, rolling or not")
		for i in rows.size():
			var row: Dictionary = rows[i]
			var e: Dictionary = table.entries[i]
			assert_eq(row.excluded, "", "drops/%s %s rolls (item, rarity and category resolved)" % [owner_id, row.key])
			assert_eq([row.category, row.rarity], [e.chance_category, e.rarity.label], "%s/%s" % [owner_id, row.key])
			assert_eq(float(row.chance), float(rates.chance_table[e.chance_category][e.rarity.label]),
				"%s/%s chance is drop_rates.json %s x %s, unchanged" % [owner_id, row.key, e.chance_category, e.rarity.label])
			assert_eq([int(row.min_quantity), int(row.max_quantity)], [1, 1], "one item per drop")
			assert_true(String(row.source).begins_with("drop_rates.json %s x %s" % [e.chance_category, e.rarity.label]), row.source)


func test_rolling_entries_by_owner() -> void:
	# The members that roll and at what chance (table cell for category x Henesys.gg rarity). Changing one means a
	# capture or the owner's table changed.
	var c := 0.03  # etc_other / Common
	var u := 0.02  # use_consumable / Common
	var q := 0.001  # equip / Common
	var expected := {
		"1": {"347": 1.0},
		"2": {"413": c, "348": 1.0, "320": c, "213": u, "209": u, "270": u, "541": q, "709": q, "713": q, "939": q, "940": q, "933": q},
		"3": {"349": 1.0, "414": c, "321": c, "483": c, "324": c, "417": c, "270": u, "209": u, "213": u, "960": q, "1181": q,
			"963": q, "937": q, "558": q, "715": q, "1157": q, "1440": q, "945": q, "939": q, "934": q, "935": q},
		"4": {"350": 1.0, "322": c, "415": c, "270": u, "209": u, "213": u, "934": q, "1157": q, "1308": q, "1175": q, "576": q,
			"1195": q, "1163": q, "714": q},
		"5": {"351": 1.0, "417": c, "324": c, "321": c, "270": u, "209": u, "213": u, "143": 0.0003, "589": q, "1305": q, "1168": q,
			"608": q, "1440": q, "1325": q, "651": q, "711": q, "710": q, "940": q, "541": q, "938": q},
		"9": {"356": 1.0, "413": c, "327": c, "270": u, "213": u, "209": u, "577": q, "543": q, "633": q, "724": q, "1327": q,
			"1317": q, "1314": q, "731": q},
		"0000001": {"442": 1.0, "441": 1.0, "236": u, "237": u},
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


func test_meso_rules_follow_meowdb_and_the_formula() -> void:
	# The Snail has MeowDB's player report (2 per kill); the others take [level, 2 x level] of their canonical level.
	var expected := {"2": [2, 2, "meowdb_report"], "3": [2, 4, "level_formula"], "4": [3, 6, "level_formula"],
		"5": [4, 8, "level_formula"], "9": [8, 16, "level_formula"]}
	for owner_id in expected:
		var rule := DropRates.meso_rule(owner_id, db())
		var level := int(db().monster(owner_id).level)
		assert_eq([rule.min, rule.max, rule.amount_kind], expected[owner_id], "drops/%s meso amount (level %d)" % [owner_id, level])
		assert_near(float(rule.chance), 0.6, 1e-15, "drops/%s meso chance (D3-12)" % owner_id)
		assert_eq(rule.excluded, "")
		var meso: Dictionary = db().drop_table(owner_id).meso
		if owner_id == "2":
			assert_eq([meso.amount_state, meso.amount_source.authority, meso.amount_source.raw_value],
				["reported", "MeowDB MS Classic", "Mesos: 2 per kill | 1 report"])
		else:
			assert_eq([meso.amount_state, meso.amount_source, meso.min, meso.max], ["not_reported", null, null, null],
				"drops/%s: MeowDB has no report, the record says so and holds no made-up amount" % owner_id)
			assert_eq([int(rule.min), int(rule.max)], [level, 2 * level])
	# The Tutorial Jr. Sentinel (owner's choice) and the box drop none.
	for owner_id in ["1", "0000001"]:
		var rule := DropRates.meso_rule(owner_id, db())
		assert_eq([rule.chance, rule.excluded], [0.0, DropRates.NO_MESOS], "drops/%s: no mesos (meso_rules.json no_mesos)" % owner_id)
	assert_eq(db().drop_table("0000001").meso, null, "a breakable record has no meso block")
	assert_eq(DropRates.meso_rule("no-such-owner", db()).chance, 0.0)


func test_an_edited_table_cell_reaches_the_runtime_unchanged() -> void:
	# The owner tunes a drop by editing one cell of drop_rates.json: every member of that category and rarity rolls at
	# the new value, read as is (no rounding, no scaling), and nothing else changes.
	var c := ContentDB.new()
	c.canonical = db().canonical
	c.miso = db().miso.duplicate()
	var singles: Dictionary = (db().miso[""] as Dictionary).duplicate()
	var rates: Dictionary = (singles["drop_rates"] as Dictionary).duplicate(true)
	rates.chance_table.equip.Common = 0.0123456789
	rates.chance_table.use_scroll.Rare = 0.25
	singles["drop_rates"] = rates
	c.miso[""] = singles
	c.loaded = true
	assert_eq(DropRates.validate(c).size(), 0, "the edited table is still complete")
	for owner_id in db().ids("drops"):
		var before := DropRates.effective_entries(owner_id, db())
		var after := DropRates.effective_entries(owner_id, c)
		for i in after.size():
			var want := float(before[i].chance)
			if after[i].category == "equip" and after[i].rarity == "Common":
				want = 0.0123456789
			elif after[i].category == "use_scroll" and after[i].rarity == "Rare":
				want = 0.25
			assert_eq(float(after[i].chance), want, "drops/%s %s" % [owner_id, after[i].key])
	var scroll: Array = DropRates.effective_entries("5", c).filter(func(r: Dictionary) -> bool: return r.item_id == "143")
	assert_eq(float(scroll[0].chance), 0.25, "the Red Snail's Rare scroll follows its cell")
	assert_eq(float(db().miso_table("drop_rates").chance_table.equip.Common), 0.001, "shared db untouched")
