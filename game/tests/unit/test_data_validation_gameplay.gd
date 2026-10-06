extends DataValidationTestCase
## The headless data validation runs the game's own quest, NPC and dialogue validation (QuestCatalog.validate,
## NpcCatalog.validate, NpcDialogueBuilder.validate_all) as checks quest_data, npc_data and dialogue_data
## (GameplayDataChecks), so scripts/validate_data.sh reports what would make a quest or a conversation unplayable.


func parity_keys() -> Dictionary:
	return {
		"test_shipped_data_passes_the_gameplay_validation": ["xref:quest-npc", "xref:map-npc"],
		"test_npc_missing_from_its_map_is_reported": ["xref:map-npc"],
	}


func test_shipped_data_passes_the_gameplay_validation() -> void:
	var r := baseline()
	assert_eq(int(r.stats.get("gameplay_checks_run", 0)), 1, "the gameplay validation ran on the shipped data")
	for check in [GameplayDataChecks.QUEST_CHECK, GameplayDataChecks.NPC_CHECK, GameplayDataChecks.DIALOGUE_CHECK]:
		for f in r.matching(check):
			fail("[%s] %s/%s: %s" % [f.check, f.domain, f.id, f.message])


func test_unsupported_quest_objective_is_reported() -> void:
	var c := clone_db()
	var qid := first_id_where(c, "quests", func(q: Dictionary) -> bool: return q.get("objectives", null) is Dictionary, "with objectives")
	var objectives: Dictionary = c.get_entity("quests", qid).objectives
	if not (objectives.get("other", null) is Array):
		objectives["other"] = []
	objectives.other.append({"type": "zz_test_teleport", "description": "test: a type the engine cannot evaluate"})
	var r := run_validator(c)
	expect_new(r, "error", GameplayDataChecks.QUEST_CHECK, "quests", qid, "unsupported 'other' objective type 'zz_test_teleport'")


func test_dangling_dialogue_target_is_reported() -> void:
	var c := clone_db()
	var files: Dictionary = c.miso.get("dialogue", {})
	var npc_id := ""
	for k in files:
		if not AdaptationChecks.is_shared_table(str(k)) and files[k].get("nodes", null) is Dictionary and not files[k].nodes.is_empty():
			npc_id = str(k)
			break
	if npc_id == "":
		fail("no dialogue override file with nodes (the shipped data changed shape?)")
		return
	var nodes: Dictionary = files[npc_id].nodes
	var node_id: String = nodes.keys()[0]
	nodes[node_id]["next"] = "zz_test_missing_node"
	var r := run_validator(c)
	var found := false
	for f in new_findings(r):
		if f.check == GameplayDataChecks.DIALOGUE_CHECK and f.severity == "error" and f.domain == "npcs" \
				and "target 'zz_test_missing_node' does not exist" in f.message:
			found = true
	assert_true(found, "a dialogue_data error names the dangling target")


func test_npc_missing_from_its_map_is_reported() -> void:
	var c := clone_db()
	var map_id := first_id_where(c, "maps", func(m: Dictionary) -> bool: return not arr(m, "npcs").is_empty(), "with NPCs")
	var placed: Array = c.get_entity("maps", map_id).npcs
	var npc_id := str(placed[0].get("id", ""))
	placed.remove_at(0)
	var r := run_validator(c)
	# The reference checks see only a one-sided placement (a consistency warning), so the run has no error and the
	# NPC catalog's own rule reports the NPC the game could not place.
	expect_new(r, "error", GameplayDataChecks.NPC_CHECK, "npcs", npc_id, "not listed on map %s" % map_id)


func test_gameplay_validation_waits_for_structurally_valid_data() -> void:
	var c := clone_db()
	var qid := first_id_where(c, "quests", func(q: Dictionary) -> bool: return q.get("objectives", null) is Dictionary, "with objectives")
	var objectives: Dictionary = c.get_entity("quests", qid).objectives
	if not (objectives.get("other", null) is Array):
		objectives["other"] = []
	objectives.other.append({"type": "zz_test_teleport"})
	c.get_entity("quests", qid)["start_npc"]["npc_id"] = BOGUS
	var r := run_validator(c)
	expect_new(r, "error", "reference", "quests", qid, "references npcs '%s'" % BOGUS)
	assert_eq(r.matching(GameplayDataChecks.QUEST_CHECK).size(), 0, "no quest_data findings over broken data")
	assert_eq(int(r.stats.get("gameplay_checks_skipped", 0)), 1, "the skip is counted")


func test_message_prefix_names_the_record() -> void:
	var g := GameplayDataChecks.new(db(), ValidationReport.new())
	assert_eq(g.locate("quest 1002 objective other:x: unsupported", "quests"), ["quests", "1002"], "quest prefix")
	assert_eq(g.locate("npc 7 (Todd): not listed on map 000000030", "npcs"), ["npcs", "7"], "npc prefix")
	assert_eq(g.locate("misostory/quests/1002.json: missing top-level reason", "quests"), ["misostory/quests", "1002"], "adaptation file")
	assert_eq(g.locate("dialogue 16 node 'start': target 'x' does not exist", "dialogue"), ["npcs", "16"], "dialogue graph")
	assert_eq(g.locate("something else", "dialogue"), ["dialogue", ""], "no prefix")
