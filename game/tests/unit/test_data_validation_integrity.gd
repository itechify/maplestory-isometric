extends DataValidationTestCase
## The Phase 16 cross-reference rules beyond plain id lookups (brief "Content Cross-Reference Validation"): skill
## references resolve, a chair is a Setup item with setup data, no placeholder names, no id defined twice, every
## reference category is counted (so none silently drops to zero), and out-of-scope skips are listed in every report.


func parity_keys() -> Dictionary:
	return {
		"test_every_phase16_category_counts_references": ["xref:quest-reward-item", "xref:quest-objective-item",
			"xref:quest-monster", "xref:quest-npc", "xref:monster-drop", "xref:shop-item", "xref:map-monster",
			"xref:map-npc", "xref:portal-destination", "xref:skill-reference", "xref:chair-item", "xref:breakable-drop",
			"xref:no-silent-missing-refs"],
		"test_breakable_and_monster_drop_items_resolve": ["xref:breakable-drop", "xref:monster-drop"],
		"test_skill_reference_must_resolve": ["xref:skill-reference"],
		"test_skill_defined_twice": ["xref:skill-reference", "xref:no-duplicate-ids"],
		"test_shipped_chairs_are_usable": ["xref:chair-item"],
		"test_chair_must_be_a_setup_item_with_setup_data": ["xref:chair-item"],
		"test_setup_block_on_another_item_type": ["xref:chair-item"],
		"test_placeholder_names_are_errors": ["xref:no-placeholder-names"],
		"test_placeholder_name_patterns": ["xref:no-placeholder-names"],
		"test_shipped_data_has_no_placeholder_names": ["xref:no-placeholder-names"],
		"test_duplicate_entries_are_errors": ["xref:no-duplicate-ids"],
		"test_repeated_placements_and_shared_names_are_not_duplicates": ["xref:no-duplicate-ids"],
		"test_out_of_scope_skips_are_listed_without_verbose": ["xref:no-silent-missing-refs"],
	}


func test_every_phase16_category_counts_references() -> void:
	var stats := baseline().stats
	for category in ReferenceChecks.PHASE16_CATEGORIES:
		assert_true(int(stats.get("refs." + category, 0)) > 0, "Phase 16 category %s resolved no reference (stats %s)" % [
			category, str(stats)])
	assert_eq(baseline().error_count(), 0, "the unbroken copy has no errors")


func test_breakable_and_monster_drop_items_resolve() -> void:
	var c := clone_db()
	var box := first_id_where(c, "drops", func(r: Dictionary) -> bool: return r.get("owner", {}).get("kind", "") == "breakable" and not arr(r, "entries").is_empty(), "owned by a breakable")
	var mob := first_id_where(c, "drops", func(r: Dictionary) -> bool: return r.get("owner", {}).get("kind", "") == "monster" and not arr(r, "entries").is_empty(), "owned by a monster")
	c.drop_table(box).entries[0].item_id = BOGUS
	c.drop_table(mob).entries[0].item_id = BOGUS + "-m"
	var r := run_validator(c)
	expect_new(r, "error", "reference", "drops", box, "items '%s'" % BOGUS)
	expect_new(r, "error", "reference", "drops", mob, "items '%s-m'" % BOGUS)
	# The counters keep the two Phase 16 categories apart.
	var counted := ReferenceChecks.new(db(), ValidationReport.new())
	assert_eq(counted.phase16_category({"domain": "drops", "record": db().drop_table(box)}, "entries[].item_id", "items"), "breakable-drop", "box table")
	assert_eq(counted.phase16_category({"domain": "drops", "record": db().drop_table(mob)}, "entries[].item_id", "items"), "monster-drop", "monster table")


func test_skill_reference_must_resolve() -> void:
	var c := clone_db()
	var formula := first_id_where(c, "formulas", func(r: Dictionary) -> bool: return not arr(r, "skills").is_empty(), "with skills")
	var known: String = c.formula(formula).skills[0].skill_id
	c.formula(formula)["zz_test_uses"] = {"skill_id": BOGUS, "skill_ids": [known, BOGUS + "-2"]}
	_with_miso(c, "zz_test_skill_refs", adapted({"bind": {"skill_id": BOGUS + "-3"}}))
	var r := run_validator(c)
	expect_new(r, "error", "reference", "formulas", formula, "zz_test_uses.skill_id references skills '%s'" % BOGUS)
	expect_new(r, "error", "reference", "formulas", formula, "zz_test_uses.skill_ids[] references skills '%s-2'" % BOGUS)
	expect_new(r, "error", "reference", "misostory", "zz_test_skill_refs", "bind.skill_id references skills '%s-3'" % BOGUS)
	# The definitions themselves (formulas skills[].skill_id) are not references.
	for f in new_findings(r):
		assert_false("skills[].skill_id" in f.message, "a skill definition was swept as a reference: %s" % f.message)


func test_skill_defined_twice() -> void:
	var c := clone_db()
	var formula := first_id_where(c, "formulas", func(r: Dictionary) -> bool: return not arr(r, "skills").is_empty(), "with skills")
	var skill: Dictionary = c.formula(formula).skills[0].duplicate(true)
	var other := first_id_where(c, "formulas", func(r: Dictionary) -> bool: return r.get("id", "") != formula, "other than %s" % formula)
	c.formula(other)["skills"] = [skill]
	var r := run_validator(c)
	var found := false
	for f in new_findings(r):
		if f.check == "duplicate" and f.severity == "error" and f.domain == "formulas" \
				and ("skill %s is defined 2 times" % skill.skill_id) in f.message:
			found = true
	assert_true(found, "a duplicate skill definition is an error")


func test_shipped_chairs_are_usable() -> void:
	var chairs := 0
	for formula_id in db().ids("formulas"):
		for chair in arr(db().formula(formula_id), IntegrityChecks.CHAIRS):
			chairs += 1
			var item := db().item(str(chair.get("item_id", "")))
			assert_eq(IntegrityChecks.chair_problems(item), PackedStringArray(), "chair %s" % chair.get("item_id", ""))
	assert_true(chairs > 0, "the shipped formulas list chairs")
	assert_eq(int(baseline().stats.get("refs.chair-item", 0)), chairs, "every chair counted")
	assert_eq(baseline().matching("chair").size(), 0, "no chair findings on the shipped data")


func test_chair_must_be_a_setup_item_with_setup_data() -> void:
	var c := clone_db()
	var formula := first_id_where(c, "formulas", func(r: Dictionary) -> bool: return not arr(r, IntegrityChecks.CHAIRS).is_empty(), "with chairs")
	var chairs: Array = c.formula(formula).chairs
	var first: String = chairs[0].item_id
	c.item(first)["type"] = "Etc"
	c.item(first).erase("setup")
	var r := run_validator(c)
	expect_new(r, "error", "chair", "formulas", formula, "item %s" % first)
	expect_new(r, "error", "chair", "formulas", formula, "its type is \"Etc\", not Setup")
	expect_new(r, "error", "chair", "formulas", formula, "no setup block")
	var d := clone_db()
	d.item(first)["setup"] = {"hp_recovery_bonus": -1, "interval_s": 0}
	r = run_validator(d)
	expect_new(r, "error", "chair", "formulas", formula, "setup.hp_recovery_bonus must be a number >= 0")
	expect_new(r, "error", "chair", "formulas", formula, "setup.interval_s must be a number > 0")
	var e := clone_db()
	e.formula(formula).chairs[0]["additional_hp_per_tick"] = 999
	expect_new(run_validator(e), "warning", "chair", "formulas", formula, "additional_hp_per_tick is 999")


func test_setup_block_on_another_item_type() -> void:
	var c := clone_db()
	var item := first_id_where(c, "items", func(r: Dictionary) -> bool: return r.get("type", "") == "Etc", "of type Etc")
	c.item(item)["setup"] = {"hp_recovery_bonus": 30, "interval_s": 10}
	expect_new(run_validator(c), "error", "chair", "items", item, "has a setup block but its type is \"Etc\"")


func test_placeholder_names_are_errors() -> void:
	var c := clone_db()
	var item := first_id_where(c, "items", func(r: Dictionary) -> bool: return r.get("name", null) is String, "with a name")
	var quest := first_id_where(c, "quests", func(r: Dictionary) -> bool: return r.get("start_npc", null) is Dictionary, "with a start NPC")
	c.item(item)["name"] = "Item 4031"
	c.quest(quest).start_npc["name"] = "TODO"
	_with_miso(c, "zz_test_names", adapted({"label_name": "Placeholder shop", "rows": [{"npc_name": "Unknown NPC"}]}))
	var r := run_validator(c)
	expect_new(r, "error", "name", "items", item, "name \"Item 4031\" is a placeholder")
	expect_new(r, "error", "name", "quests", quest, "start_npc.name \"TODO\" is a placeholder")
	expect_new(r, "error", "name", "misostory", "zz_test_names", "label_name \"Placeholder shop\"")
	expect_new(r, "error", "name", "misostory", "zz_test_names", "rows[].npc_name \"Unknown NPC\"")


func test_placeholder_name_patterns() -> void:
	var checks := IntegrityChecks.new(db(), ValidationReport.new())
	for bad in ["", "   ", "?", "??", "placeholder", "Placeholder Hat", "TODO", "Shop (TODO)", "TBD", "FIXME later",
			"Unknown", "unknown item", "Item 4031", "item #12", "ITEM 7"]:
		assert_true(checks.is_placeholder_name(bad), "%s is a placeholder" % var_to_str(bad))
	for good in ["Todd", "Red Cloth Pants", "Snail Shell", "The Green Relaxer", "Mushroom Town - West Entrance",
			"Rain's Maple Quiz 7", "Itemizer", "Toad", "Old Wooden Board", "Tutorial Jr. Sentinel"]:
		assert_false(checks.is_placeholder_name(good), "%s is a real name" % var_to_str(good))


func test_shipped_data_has_no_placeholder_names() -> void:
	assert_eq(baseline().matching("name").size(), 0, "placeholder names in the shipped data")
	assert_true(int(baseline().stats.get("names_checked", 0)) > 1000, "names were checked: %s" % baseline().stats.get("names_checked", 0))


func test_duplicate_entries_are_errors() -> void:
	var c := clone_db()
	var shop := first_id_where(c, "shops", func(r: Dictionary) -> bool: return not arr(r, "items").is_empty(), "with stock")
	var town := first_id_where(c, "maps", func(r: Dictionary) -> bool: return not arr(r, "npcs").is_empty(), "with NPCs")
	var quest := first_id_where(c, "quests", func(r: Dictionary) -> bool: return not arr(r.get("objectives", {}), "item_collection").is_empty(), "collecting items")
	c.shop(shop).items.append(c.shop(shop).items[0].duplicate(true))
	c.map(town).npcs.append(c.map(town).npcs[0].duplicate(true))
	c.quest(quest).objectives.item_collection.append(c.quest(quest).objectives.item_collection[0].duplicate(true))
	var r := run_validator(c)
	expect_new(r, "error", "duplicate", "shops", shop, "items lists item_id %s twice" % c.shop(shop).items[0].item_id)
	expect_new(r, "error", "duplicate", "maps", town, "npcs lists id %s twice" % c.map(town).npcs[0].id)
	expect_new(r, "error", "duplicate", "quests", quest, "objectives.item_collection lists item_id")


func test_repeated_placements_and_shared_names_are_not_duplicates() -> void:
	# Map reactors[] are placements (five Wooden Boxes on one map), and two records may share a name (Red Cloth Pants,
	# male and female): neither is a duplicate id.
	assert_eq(baseline().matching("duplicate").size(), 0, "duplicate findings on the shipped data")
	var reactor_maps := 0
	for map_id in db().ids("maps"):
		var ids := {}
		for r in arr(db().map(map_id), "reactors"):
			if ids.has(r.get("id", "")):
				reactor_maps += 1
				break
			ids[r.get("id", "")] = true
	assert_true(reactor_maps > 0, "the shipped maps repeat a reactor placement (the case this test guards)")


func test_out_of_scope_skips_are_listed_without_verbose() -> void:
	var r := baseline()
	assert_true(r.out_of_scope.size() > 0, "the shipped data has out-of-scope references")
	var text := r.format_text(false)
	var listed := 0
	for line in text.split("\n"):
		var m := RegEx.create_from_string("^SKIPPED \\(out of scope\\) (\\d+) x (.+)$").search(line)
		if m != null:
			listed += m.get_string(1).to_int()
			assert_has(r.out_of_scope_by_rule, m.get_string(2), "rule line")
	assert_eq(listed, r.out_of_scope.size(), "the grouped lines account for every skipped reference")
	assert_false(r.out_of_scope[0] in text, "the individual lines need --verbose")
	assert_true(r.format_text(true).contains(r.out_of_scope[0]), "--verbose lists them")
	assert_true(r.to_dict().get("out_of_scope_by_rule", {}) is Dictionary, "the JSON report has the per-rule counts")


func _with_miso(c: ContentDB, name: String, data: Dictionary) -> void:
	if not c.miso.has(""):
		c.miso[""] = {}
	c.miso[""][name] = data
