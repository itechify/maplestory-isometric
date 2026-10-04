extends TestCase
## Drop data: every canonical drop references a real item, the placeholder table (drop_rates.json) is consistent and
## fully labelled as unverified, and every item a Maple Island quest asks the player to collect can actually drop.


func test_every_drop_item_exists() -> void:
	for owner_id in db().ids("drops"):
		var table := db().drop_table(owner_id)
		assert_has(["monster", "breakable"], String(table.owner.kind), "%s owner kind" % owner_id)
		assert_eq(table.get("rates_canonical"), false, "%s rates are not canonical" % owner_id)
		for e in table.entries:
			assert_true(db().has("items", String(e.item_id)), "drops/%s lists unknown item %s" % [owner_id, e.item_id])


func test_every_monster_has_its_drop_table() -> void:
	for monster_id in db().ids("monsters"):
		assert_true(DropRates.has_table(monster_id, db()), "monster %s has drops/%s.json" % [monster_id, monster_id])
		assert_eq(DropRates.owner_kind(monster_id, db()), "monster")
	assert_eq(DropRates.owner_kind("0000001", db()), "breakable", "Wooden Box is a breakable, not monster 1")


func test_placeholder_table_is_consistent_and_labelled() -> void:
	var errors := DropRates.validate(db())
	assert_eq(errors.size(), 0, "\n".join(errors))
	var rates: Dictionary = db().miso_table("drop_rates")
	assert_eq(rates.get("canonical"), false)
	assert_eq(rates.get("verified"), false)
	assert_true(String(rates.get("reason", "")).contains("MeowDB"), "file-level reason names the gap")


func test_ground_rules_are_labelled_adaptations() -> void:
	var t: Dictionary = db().miso_table("drops")
	assert_eq(t.get("verified"), false)
	for key in ["ground_lifetime", "owner_exclusive", "scatter_spacing"]:
		assert_true(String(t.get(key + "_reason", "")).length() > 20, "%s_reason" % key)
	assert_true(DropRates.ground_lifetime_s(db()) > 0.0)
	assert_true(DropRates.owner_exclusive_s(db()) >= 0.0)
	assert_true(DropRates.scatter_spacing_px(db()) > 0.0)


func test_every_resolved_rate_names_its_source() -> void:
	for owner_id in db().ids("drops"):
		for e in DropRates.effective_entries(owner_id, db()):
			assert_between(float(e.chance), 0.0, 1.0, "%s/%s chance" % [owner_id, e.item_id])
			assert_true(int(e.min_quantity) >= 1 and int(e.max_quantity) >= int(e.min_quantity), "%s/%s qty" % [owner_id, e.item_id])
			if e.excluded == "":
				assert_ne(String(e.source), "", "%s/%s source" % [owner_id, e.item_id])


func test_unconfirmed_and_disputed_entries_are_off_by_default() -> void:
	var rates: Dictionary = db().miso_table("drop_rates")
	var overrides: Dictionary = rates.owner_item_overrides
	for owner_id in db().ids("drops"):
		for e in DropRates.effective_entries(owner_id, db()):
			var overridden: bool = overrides.get(owner_id, {}).has(e.item_id) or rates.item_overrides.has(e.item_id)
			if overridden:
				continue
			if e.status == "msea_reference" and not bool(rates.status_rules.msea_reference.enabled):
				assert_eq(e.chance, 0.0, "MSEA-only %s/%s" % [owner_id, e.item_id])
			if e.disputed and not bool(rates.disputed_entries.enabled):
				assert_eq(e.chance, 0.0, "disputed %s/%s" % [owner_id, e.item_id])


func test_owner_overrides_win() -> void:
	var rates: Dictionary = db().miso_table("drop_rates")
	for owner_id in rates.owner_item_overrides:
		for e in DropRates.effective_entries(owner_id, db()):
			var o: Variant = rates.owner_item_overrides[owner_id].get(e.item_id)
			if o is Dictionary and o.has("chance"):
				assert_near(float(e.chance), clampf(float(o.chance) * float(rates.global_rate_multiplier), 0.0, 1.0), 1e-9,
					"%s/%s" % [owner_id, e.item_id])
				assert_true(String(e.source).begins_with("owner_item_overrides"))


## Items a quest asks the player to collect (minus those the quest itself hands out on accept).
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


func _obtainable(item_id: String) -> bool:
	for owner_id in db().ids("drops"):
		for e in DropRates.effective_entries(owner_id, db()):
			if e.item_id == item_id and float(e.chance) > 0.0:
				return true
	for shop_id in db().ids("shops"):
		if not ShopService.row_for(shop_id, item_id, db()).is_empty():
			return true
	return false


func test_quest_items_are_obtainable() -> void:
	var needed := _quest_collect_items()
	assert_true(needed.size() > 0, "Maple Island quests ask for items")
	for item_id in needed:
		assert_true(_obtainable(item_id), "quest %s needs item %s, which nothing drops or sells" % [needed[item_id], item_id])


func test_three_snails_shells_are_obtainable() -> void:
	for skill in db().formula("beginner").skills:
		for lv in skill.get("levels", []):
			if lv.get("item_cost_id") != null:
				assert_true(_obtainable(String(lv.item_cost_id)), "skill %s cost item %s" % [skill.skill_id, lv.item_cost_id])


func test_meso_rules() -> void:
	# Snail: the one player report (canonical drops/2.json meso) is used as is.
	var snail: Dictionary = db().drop_table("2").meso
	var rule := DropRates.meso_rule("2", db())
	assert_eq(rule.min, int(snail.median_min))
	assert_eq(rule.max, int(snail.median_max))
	assert_true(String(rule.source).contains("player reports"))
	# A monster without reports uses the per-level placeholder and always drops at least 1 meso.
	var om := DropRates.meso_rule("9", db())
	assert_true(String(om.source).contains("per_level"))
	assert_true(int(om.min) >= 1 and int(om.max) >= int(om.min))
	assert_true(int(om.min) > int(rule.max), "a level-8 monster drops more than a level-1 one")
	# Breakables have no meso data (status not_applicable) and drop none.
	assert_eq(DropRates.meso_rule("0000001", db()).chance, 0.0)
	assert_eq(DropRates.meso_rule("no-such-owner", db()).chance, 0.0)
