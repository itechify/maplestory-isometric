extends DataValidationTestCase
## Negative tests: broken cross-record references are caught (items, monsters, maps, portals, NPCs, quests, shops,
## drop tables, formulas), dialogue links never fail (a canonical link outside the dataset is skipped, an adaptation
## one warns), and deliberately out-of-scope references are skipped.


func parity_keys() -> Dictionary:
	var portal := ["xref:portal-destination"]
	return {
		"test_drop_entry_with_missing_item": ["xref:monster-drop"],
		"test_drop_table_owner_and_monster_drop_table_ref": ["xref:monster-drop"],
		"test_quest_kill_objective_with_missing_monster": ["xref:quest-monster"],
		"test_quest_item_objective_reward_and_accept_items": ["xref:quest-objective-item", "xref:quest-reward-item"],
		"test_quest_npcs_maps_and_prerequisites": ["xref:quest-npc"],
		"test_shop_stock_npc_and_map": ["xref:shop-item"],
		"test_map_spawns_npcs_reactors_and_return_map": ["xref:map-monster", "xref:map-npc"],
		"test_portal_destination_map_missing": portal,
		"test_portal_destination_portal_missing": portal,
		"test_reverse_lookup_portal_must_lead_back": portal,
		"test_portal_without_to_portal_needs_player_spawns": portal,
		"test_map_unreachable_from_the_start_map": portal,
		"test_one_way_link_must_be_allowlisted": portal,
		"test_shipped_portal_graph_is_connected_and_one_way_links_are_allowlisted": portal,
		"test_quest_starting_on_a_map_must_exist_whatever_its_region": ["xref:no-silent-missing-refs"],
		"test_out_of_region_progress_quest_is_skipped_but_in_region_is_an_error": ["xref:no-silent-missing-refs"],
		"test_off_island_monster_spawn_is_skipped_unless_flagged_on_island": ["xref:no-silent-missing-refs"],
	}


func test_unbroken_copy_matches_shipped_report() -> void:
	# The fixture's baseline is the shipped data plus injected sidecars; it must not invent reference errors.
	assert_eq(baseline().matching("reference", "", "", "error").size(), 0, "reference errors in the unbroken copy")
	assert_eq(baseline().matching("portal").size(), 0, "portal findings in the unbroken copy")


func test_drop_entry_with_missing_item() -> void:
	var c := clone_db()
	var id := first_id_where(c, "drops", func(r: Dictionary) -> bool: return not arr(r, "entries").is_empty(), "with entries")
	c.drop_table(id).entries[0].item_id = BOGUS
	expect_new(run_validator(c), "error", "reference", "drops", id, "items '%s'" % BOGUS)


func test_numeric_id_is_an_error() -> void:
	var c := clone_db()
	var id := first_id_where(c, "drops", func(r: Dictionary) -> bool: return not arr(r, "entries").is_empty(), "with entries")
	c.drop_table(id).entries[0].item_id = 12.0
	expect_new(run_validator(c), "error", "reference", "drops", id, "must be a string id")


func test_quest_kill_objective_with_missing_monster() -> void:
	var c := clone_db()
	var id := first_id_where(c, "quests", func(r: Dictionary) -> bool: return not arr(r.get("objectives", {}), "monster_kills").is_empty(), "with a kill objective")
	c.quest(id).objectives.monster_kills[0].mob_id = BOGUS
	expect_new(run_validator(c), "error", "reference", "quests", id, "objectives.monster_kills[].mob_id references monsters '%s'" % BOGUS)


func test_quest_item_objective_reward_and_accept_items() -> void:
	var c := clone_db()
	var collect := first_id_where(c, "quests", func(r: Dictionary) -> bool: return not arr(r.get("objectives", {}), "item_collection").is_empty(), "with an item objective")
	var reward := first_id_where(c, "quests", func(r: Dictionary) -> bool: return not arr(r.get("rewards", {}), "items").is_empty(), "with an item reward")
	var random := first_id_where(c, "quests", func(r: Dictionary) -> bool: return not arr(r.get("rewards", {}), "random").is_empty(), "with a random reward")
	var accept := first_id_where(c, "quests", func(r: Dictionary) -> bool: return not arr(r, "items_given_on_accept").is_empty(), "with accept items")
	c.quest(collect).objectives.item_collection[0].item_id = BOGUS
	c.quest(reward).rewards.items[0].item_id = BOGUS + "-reward"
	c.quest(random).rewards.random[0].items[0].item_id = BOGUS + "-random"
	c.quest(accept).items_given_on_accept[0].item_id = BOGUS + "-accept"
	var r := run_validator(c)
	expect_new(r, "error", "reference", "quests", collect, "objectives.item_collection[].item_id references items '%s'" % BOGUS)
	expect_new(r, "error", "reference", "quests", reward, "rewards.items[].item_id references items '%s-reward'" % BOGUS)
	expect_new(r, "error", "reference", "quests", random, "rewards.random[].items[].item_id references items '%s-random'" % BOGUS)
	expect_new(r, "error", "reference", "quests", accept, "items_given_on_accept[].item_id references items '%s-accept'" % BOGUS)


func test_quest_npcs_maps_and_prerequisites() -> void:
	var c := clone_db()
	var id := first_id_where(c, "quests", func(r: Dictionary) -> bool: return not arr(r.get("prerequisites", {}), "quests").is_empty(), "with a prerequisite")
	var q := c.quest(id)
	q.start_npc.npc_id = BOGUS + "-start"
	q.end_npc.npc_id = BOGUS + "-end"
	q.start_maps[0].map_id = BOGUS + "-map"
	q.end_maps[0].map_id = BOGUS + "-endmap"
	q.prerequisites.quests[0].quest_id = BOGUS + "-pre"
	var r := run_validator(c)
	expect_new(r, "error", "reference", "quests", id, "start_npc.npc_id references npcs '%s-start'" % BOGUS)
	expect_new(r, "error", "reference", "quests", id, "end_npc.npc_id references npcs '%s-end'" % BOGUS)
	expect_new(r, "error", "reference", "quests", id, "start_maps[].map_id references maps '%s-map'" % BOGUS)
	expect_new(r, "error", "reference", "quests", id, "end_maps[].map_id references maps '%s-endmap'" % BOGUS)
	expect_new(r, "error", "reference", "quests", id, "prerequisites.quests[].quest_id references quests '%s-pre'" % BOGUS)


func test_shop_stock_npc_and_map() -> void:
	var c := clone_db()
	var id := c.ids("shops")[0]
	c.shop(id).items[0].item_id = BOGUS
	c.shop(id).npc_id = BOGUS + "-npc"
	c.shop(id).map_id = BOGUS + "-map"
	var r := run_validator(c)
	expect_new(r, "error", "reference", "shops", id, "items[].item_id references items '%s'" % BOGUS)
	expect_new(r, "error", "reference", "shops", id, "npc_id references npcs '%s-npc'" % BOGUS)
	expect_new(r, "error", "reference", "shops", id, "map_id references maps '%s-map'" % BOGUS)


func test_npc_shop_block_location_and_quests() -> void:
	var c := clone_db()
	var shopkeeper := first_id_where(c, "npcs", func(r: Dictionary) -> bool: return r.get("shop", null) is Dictionary, "with a shop")
	var giver := first_id_where(c, "npcs", func(r: Dictionary) -> bool: return not arr(r.get("quests", {}), "given").is_empty(), "that gives a quest")
	c.npc(shopkeeper).shop.item_ids.append(BOGUS)
	c.npc(shopkeeper).shop.shop_id = BOGUS + "-shop"
	c.npc(shopkeeper).locations[0].map_id = BOGUS + "-map"
	c.npc(giver).quests.given[0].id = BOGUS + "-quest"
	var r := run_validator(c)
	expect_new(r, "error", "reference", "npcs", shopkeeper, "shop.item_ids[] references items '%s'" % BOGUS)
	expect_new(r, "error", "reference", "npcs", shopkeeper, "shop.shop_id references shops '%s-shop'" % BOGUS)
	expect_new(r, "error", "reference", "npcs", shopkeeper, "locations[].map_id references maps '%s-map'" % BOGUS)
	expect_new(r, "error", "reference", "npcs", giver, "quests.given[].id references quests '%s-quest'" % BOGUS)


func test_map_spawns_npcs_reactors_and_return_map() -> void:
	var c := clone_db()
	var hunting := first_id_where(c, "maps", func(r: Dictionary) -> bool: return not arr(r, "spawns").is_empty() and not arr(r, "reactors").is_empty(), "with spawns and reactors")
	var town := first_id_where(c, "maps", func(r: Dictionary) -> bool: return not arr(r, "npcs").is_empty(), "with NPCs")
	c.map(hunting).spawns[0].mob_id = BOGUS
	c.map(hunting).monsters[0].id = BOGUS + "-species"
	c.map(hunting).reactors[0].id = BOGUS + "-box"
	c.map(town).npcs[0].id = BOGUS + "-npc"
	c.map(town).return_map_id = BOGUS + "-return"
	var r := run_validator(c)
	expect_new(r, "error", "reference", "maps", hunting, "spawns[].mob_id references monsters '%s'" % BOGUS)
	expect_new(r, "error", "reference", "maps", hunting, "monsters[].id references monsters '%s-species'" % BOGUS)
	expect_new(r, "error", "reference", "maps", hunting, "reactors[].id references breakables '%s-box'" % BOGUS)
	expect_new(r, "error", "reference", "maps", town, "npcs[].id references npcs '%s-npc'" % BOGUS)
	expect_new(r, "error", "reference", "maps", town, "return_map_id references maps '%s-return'" % BOGUS)


func test_portal_destination_map_missing() -> void:
	var c := clone_db()
	var id := first_id_where(c, "maps", func(r: Dictionary) -> bool: return not arr(r, "portals").is_empty(), "with a portal")
	var portal: Dictionary = c.map(id).portals[0]
	portal.to_map_id = BOGUS
	expect_new(run_validator(c), "error", "portal", "maps", id, "leads to map '%s', which does not exist" % BOGUS)


func test_portal_destination_portal_missing() -> void:
	var c := clone_db()
	var id := first_id_where(c, "maps", func(r: Dictionary) -> bool: return _derived_portal_index(r) >= 0, "with a derived to_portal")
	var portal: Dictionary = c.map(id).portals[_derived_portal_index(c.map(id))]
	portal.to_portal = BOGUS
	expect_new(run_validator(c), "error", "portal", "maps", id, "arrives at portal '%s'" % BOGUS)


func test_reverse_lookup_portal_must_lead_back() -> void:
	var c := clone_db()
	var id := first_id_where(c, "maps", func(r: Dictionary) -> bool: return _derived_portal_index(r) >= 0, "with a derived to_portal")
	var portal: Dictionary = c.map(id).portals[_derived_portal_index(c.map(id))]
	var back := ReferenceChecks.find_portal(c.map(portal.to_map_id), portal.to_portal)
	var elsewhere := ""
	for m in c.ids("maps"):
		if m != id:
			elsewhere = m
			break
	back.to_map_id = elsewhere
	expect_new(run_validator(c), "error", "portal", "maps", id, "is derived by reverse lookup but leads to %s" % elsewhere)


func test_portal_without_to_portal_needs_player_spawns() -> void:
	var c := clone_db()
	var id := first_id_where(c, "maps", func(r: Dictionary) -> bool: return not arr(r, "portals").is_empty(), "with a portal")
	var portal: Dictionary = c.map(id).portals[0]
	portal.to_portal = null
	portal.to_portal_derivation = "none"
	c.map(portal.to_map_id).player_spawns = []
	expect_new(run_validator(c), "error", "portal", "maps", id, "arrival point is undefined")


func test_unknown_portal_derivation() -> void:
	var c := clone_db()
	var id := first_id_where(c, "maps", func(r: Dictionary) -> bool: return _derived_portal_index(r) >= 0, "with a derived to_portal")
	c.map(id).portals[_derived_portal_index(c.map(id))].to_portal_derivation = "zz_guess"
	expect_new(run_validator(c), "error", "portal", "maps", id, "to_portal_derivation \"zz_guess\"")


func test_none_derivation_with_a_portal_back_is_stale() -> void:
	# A derived portal whose destination does have a portal back, relabelled "none" (as a stale extract would be).
	var c := clone_db()
	var id := first_id_where(c, "maps", func(r: Dictionary) -> bool: return _derived_portal_index(r) >= 0, "with a derived to_portal")
	var portal: Dictionary = c.map(id).portals[_derived_portal_index(c.map(id))]
	portal.to_portal_derivation = "none"
	var r := run_validator(c)
	expect_new(r, "error", "portal", "maps", id, "says to_portal_derivation none but names to_portal")
	portal.to_portal = null
	r = run_validator(c)
	expect_new(r, "error", "portal", "maps", id, "the derivation is stale")
	expect_no_new(r, "", "warning")


func test_reverse_lookup_must_be_unique() -> void:
	var c := clone_db()
	var id := first_id_where(c, "maps", func(r: Dictionary) -> bool: return _derived_portal_index(r) >= 0, "with a derived to_portal")
	var portal: Dictionary = c.map(id).portals[_derived_portal_index(c.map(id))]
	var second_back: Dictionary = ReferenceChecks.find_portal(c.map(portal.to_map_id), portal.to_portal).duplicate(true)
	second_back.name = "zz_second_back"
	c.map(portal.to_map_id).portals.append(second_back)
	expect_new(run_validator(c), "error", "portal", "maps", id, "the reverse lookup is ambiguous")


func test_shipped_one_way_portal_passes() -> void:
	# The shipped "none" portals (000000030 out00 today) have no way back and no to_portal: no portal finding.
	for map_id in db().ids("maps"):
		for p in arr(db().map(map_id), "portals"):
			if p is Dictionary and p.get("to_portal_derivation", "") == "none":
				assert_eq(p.get("to_portal", "x"), null, "%s %s: none means no to_portal" % [map_id, p.name])
				assert_eq(ReferenceChecks.portals_leading_to(db().map(p.to_map_id), map_id).size(), 0, "%s %s: no portal back" % [map_id, p.name])
	assert_eq(baseline().matching("portal").size(), 0, "portal findings in the shipped data")


func test_map_unreachable_from_the_start_map() -> void:
	var c := clone_db()
	var nc: Variant = c.miso_table("new_character")
	if not (nc is Dictionary and nc.get("start_location", null) is Dictionary):
		fail("new_character.json has no start_location; the reachability check starts there")
		return
	var start: String = nc.start_location.map_id
	var victim := ""
	for m in c.ids("maps"):
		if m != start:
			victim = m
			break
	for m in c.ids("maps"):  # cut every portal into the victim
		var kept: Array = []
		for p in arr(c.map(m), "portals"):
			if not (p is Dictionary and p.get("to_map_id", "") == victim):
				kept.append(p)
		c.map(m).portals = kept
	expect_new(run_validator(c), "error", "portal", "maps", victim, "cannot be reached through portals from the start map %s" % start)


func test_one_way_link_must_be_allowlisted() -> void:
	var c := clone_db()
	var id := first_id_where(c, "maps", func(r: Dictionary) -> bool: return _derived_portal_index(r) >= 0, "with a derived to_portal")
	var portal: Dictionary = c.map(id).portals[_derived_portal_index(c.map(id))]
	var dest: Dictionary = c.map(portal.to_map_id)
	var kept: Array = []
	for p in arr(dest, "portals"):
		if not (p is Dictionary and p.get("to_map_id", "") == id):
			kept.append(p)
	dest.portals = kept  # the destination loses every way back
	expect_new(run_validator(c), "error", "portal", "maps", id, "the link %s -> %s is one-way" % [id, portal.to_map_id])


func test_shipped_portal_graph_is_connected_and_one_way_links_are_allowlisted() -> void:
	assert_eq(baseline().matching("portal", "maps").filter(func(f: Dictionary) -> bool: return "one-way" in f.message or "cannot be reached" in f.message).size(), 0,
		"portal graph findings in the shipped data")


func test_duplicate_portal_names() -> void:
	var c := clone_db()
	var id := first_id_where(c, "maps", func(r: Dictionary) -> bool: return not arr(r, "portals").is_empty(), "with a portal")
	c.map(id).portals.append(c.map(id).portals[0].duplicate(true))
	expect_new(run_validator(c), "error", "portal", "maps", id, "is used twice")


func test_drop_table_owner_and_monster_drop_table_ref() -> void:
	var c := clone_db()
	var table := first_id_where(c, "drops", func(r: Dictionary) -> bool: return r.get("owner", {}).get("kind", "") == "monster", "owned by a monster")
	var monster := first_id_where(c, "monsters", func(r: Dictionary) -> bool: return r.get("drop_table", null) is String, "with a drop table")
	c.drop_table(table).owner.id = BOGUS
	c.monster(monster).drop_table = "drops/%s.json" % (BOGUS + "-table")
	var r := run_validator(c)
	expect_new(r, "error", "drop_owner", "drops", table, "owner monster '%s' does not exist" % BOGUS)
	expect_new(r, "error", "drop_table", "monsters", monster, "does not exist")


func test_beginner_starter_weapons_and_recovery_examples() -> void:
	var c := clone_db()
	var beginner := first_id_where(c, "formulas", func(r: Dictionary) -> bool: return r.get("starter_weapons", null) is Dictionary, "with starter_weapons")
	var recovery := first_id_where(c, "formulas", func(r: Dictionary) -> bool: return r.get("consumables", null) is Dictionary and r.consumables.get("beginners_guide_examples", null) is Array, "with recovery examples")
	c.formula(beginner).starter_weapons.items[0].item_id = BOGUS
	c.formula(recovery).consumables.beginners_guide_examples[0].item_id = BOGUS + "-potion"
	var r := run_validator(c)
	expect_new(r, "error", "reference", "formulas", beginner, "starter_weapons.items[].item_id references items '%s'" % BOGUS)
	expect_new(r, "error", "reference", "formulas", recovery, "consumables.beginners_guide_examples[].item_id references items '%s-potion'" % BOGUS)


func test_canonical_dialogue_link_outside_the_dataset_is_skipped() -> void:
	# A canonical link is MeowDB's raw href; MeowDB covers the whole game, so the target is off-island content.
	var c := clone_db()
	var id := first_id_where(c, "quests", func(r: Dictionary) -> bool: return not first_link(r.get("dialogue", {})).is_empty(), "with a dialogue link")
	first_link(c.quest(id).dialogue).id = BOGUS
	var r := run_validator(c)
	expect_no_new(r)
	assert_true(_skipped(r, "quests/%s: dialogue." % id, BOGUS), "the off-dataset link is listed as skipped")


func test_malformed_canonical_dialogue_link_warns() -> void:
	var c := clone_db()
	var id := first_id_where(c, "quests", func(r: Dictionary) -> bool: return not first_link(r.get("dialogue", {})).is_empty(), "with a dialogue link")
	var link := first_link(c.quest(id).dialogue)
	link["kind"] = "zz-not-a-kind"
	var r := run_validator(c)
	expect_new(r, "warning", "dialogue_link", "quests", id, "unknown link kind \"zz-not-a-kind\"")
	expect_no_new(r, "", "error")
	link.erase("kind")
	link.erase("type")
	link["kind"] = ReferenceChecks.LINK_KINDS.keys()[0]
	link.id = 7
	expect_new(run_validator(c), "warning", "dialogue_link", "quests", id, "link has no string id")


func test_adaptation_dialogue_link_outside_the_dataset_warns() -> void:
	# An adaptation file's link was written by hand, so an unknown id is a mistake, not off-island content.
	var c := clone_db()
	c.miso[""]["zz_test_link"] = adapted({"line": {"segments": [{"text": "Hello", "ref": {"kind": "npc", "id": BOGUS}}]}})
	var r := run_validator(c)
	expect_new(r, "warning", "dialogue_link", "misostory", "zz_test_link", "dialogue links to npcs '%s'" % BOGUS)
	expect_no_new(r, "", "error")
	assert_false(_skipped(r, "zz_test_link", BOGUS), "an adaptation link is never skipped as out of scope")


func test_quest_dialogue_link_is_checked_as_the_npc_corrected_id() -> void:
	# Quest dialogue keeps MeowDB's raw link; an NPC's quest_dialogue block for the same quest may correct it
	# (ref.meowdb_link_id = raw, ref.id = corrected), and the game (DialogueText) links the corrected id.
	var c := clone_db()
	var quest_id := first_id_where(c, "quests", func(r: Dictionary) -> bool: return not first_link(r.get("dialogue", {})).is_empty(), "with a dialogue link")
	var link := first_link(c.quest(quest_id).dialogue)
	var kind: String = link.get("kind", link.get("type", ""))
	var target: String = ReferenceChecks.LINK_KINDS[kind]
	var corrected := {"kind": kind, "id": c.ids(target)[0], "meowdb_link_id": BOGUS}
	link.id = BOGUS
	var npc: Dictionary = c.npc(c.ids("npcs")[0])
	var blocks: Array = arr(npc, "quest_dialogue").duplicate()
	blocks.append({"quest_id": quest_id, "lines": [{"text": "x", "segments": [{"text": "x", "ref": corrected}]}]})
	npc["quest_dialogue"] = blocks
	var r := run_validator(c)
	expect_no_new(r)
	assert_false(_skipped(r, "quests/%s:" % quest_id, BOGUS), "the corrected link resolves, so nothing is skipped")
	# A correction to an id outside the dataset is skipped like any canonical link, naming both ids.
	corrected.id = BOGUS + "-corrected"
	r = run_validator(c)
	expect_no_new(r)
	assert_true(_skipped(r, "quests/%s:" % quest_id, "%s/%s-corrected (MeowDB link %s, corrected" % [target, BOGUS, BOGUS]),
		"the corrected id is the one reported")
	# Corrections apply only to that quest's NPC blocks.
	blocks[-1].quest_id = BOGUS + "-other-quest"
	assert_true(_skipped(run_validator(c), "quests/%s:" % quest_id, "%s/%s (MeowDB link to content" % [target, BOGUS]),
		"another quest's correction does not apply")


func test_link_remap_reads_odd_corrections_like_the_game() -> void:
	# The validator reads a correction's ids exactly as DialogueText._remap_for does (QuestJson.s: null -> "", any
	# other value -> str()), so a null id cannot make the two disagree about which id the game links.
	var c := clone_db()
	var quest_id: String = c.ids("quests")[0]
	var npc: Dictionary = c.npc(c.ids("npcs")[0])
	var blocks: Array = arr(npc, "quest_dialogue").duplicate()
	blocks.append({"quest_id": quest_id, "lines": [{"text": "abc", "segments": [
		{"text": "a", "ref": {"kind": "item", "id": null, "meowdb_link_id": BOGUS + "-raw"}},
		{"text": "b", "ref": {"kind": "item", "id": BOGUS + "-from-null", "meowdb_link_id": null}},
		{"text": "c", "ref": {"kind": "item", "id": BOGUS + "-from-number", "meowdb_link_id": 7.0}}]}]})
	npc["quest_dialogue"] = blocks
	var game_remap: Dictionary = DialogueText._remap_for(c, quest_id)
	assert_eq(game_remap.get(BOGUS + "-raw", null), "", "the game reads a null corrected id as \"\"")
	assert_eq(ReferenceChecks.new(c, ValidationReport.new())._link_remap(quest_id), game_remap,
		"validator remap vs DialogueText._remap_for")


func test_quest_starting_on_a_map_must_exist_whatever_its_region() -> void:
	var c := clone_db()
	var id := first_id_where(c, "maps", func(r: Dictionary) -> bool: return not arr(r.get("quests", {}), "starts_here").is_empty(), "where a quest starts")
	var entry: Dictionary = c.map(id).quests.starts_here[0]
	entry.id = BOGUS
	entry.area_label = "Another Region (test)"
	expect_new(run_validator(c), "error", "reference", "maps", id, "quests.starts_here[].id references quests '%s'" % BOGUS)


func test_out_of_region_progress_quest_is_skipped_but_in_region_is_an_error() -> void:
	var c := clone_db()
	var id := first_id_where(c, "maps", func(r: Dictionary) -> bool: return not arr(r.get("quests", {}), "progress_here").is_empty(), "where a quest progresses")
	var region: String = c.quest(c.ids("quests")[0]).region
	var entry: Dictionary = c.map(id).quests.progress_here[0]
	entry.id = BOGUS
	entry.area_label = region
	expect_new(run_validator(c), "error", "reference", "maps", id, "quests.progress_here[].id references quests '%s'" % BOGUS)
	entry.area_label = "Another Region (test)"
	var r := run_validator(c)
	expect_no_new(r, "reference")
	assert_true(_skipped(r, BOGUS), "the out-of-region quest is listed as skipped")


func test_off_island_monster_spawn_is_skipped_unless_flagged_on_island() -> void:
	var c := clone_db()
	var id := first_id_where(c, "monsters", func(r: Dictionary) -> bool: return not arr(r, "spawns").is_empty(), "with spawns")
	var row: Dictionary = c.monster(id).spawns[0]
	row.map_id = BOGUS
	row.maple_island = false
	var r := run_validator(c)
	expect_no_new(r, "reference")
	assert_true(_skipped(r, BOGUS), "the off-island spawn map is listed as skipped")
	row.maple_island = true
	expect_new(run_validator(c), "error", "reference", "monsters", id, "spawns[].map_id references maps '%s'" % BOGUS)


func test_consistency_warnings_for_one_sided_npc_placement() -> void:
	var c := clone_db()
	var town := first_id_where(c, "maps", func(r: Dictionary) -> bool: return not arr(r, "npcs").is_empty(), "with NPCs")
	var npc_id: String = c.map(town).npcs[0].id
	c.map(town).npcs.remove_at(0)
	var r := run_validator(c)
	expect_new(r, "warning", "consistency", "npcs", npc_id, "does not place this NPC")
	# For the reference checks it is one-sided (a warning); the NPC catalog the game uses cannot place the NPC, which
	# GameplayDataChecks reports as its only error (test_data_validation_gameplay.gd).
	expect_no_new(r, "reference", "error")
	expect_no_new(r, "consistency", "error")
	expect_new(r, "error", GameplayDataChecks.NPC_CHECK, "npcs", npc_id, "not listed on map %s" % town)


static func _derived_portal_index(rec: Dictionary) -> int:
	var portals := arr(rec, "portals")
	for i in portals.size():
		if portals[i] is Dictionary and portals[i].get("to_portal_derivation", "") == "reverse_lookup" and portals[i].get("to_portal", null) is String:
			return i
	return -1


## True when some out-of-scope line contains `needle` (and `also`, when given).
static func _skipped(r: ValidationReport, needle: String, also: String = "") -> bool:
	for s in r.out_of_scope:
		if needle in s and (also == "" or also in s):  # GDScript: "" in s is false
			return true
	return false
