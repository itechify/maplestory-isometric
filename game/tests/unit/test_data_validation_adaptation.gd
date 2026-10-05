extends DataValidationTestCase
## Negative tests for MisoStory adaptation data: the reason/verified convention, typed references inside adaptation
## files, domain folders, the crosswalk (bijective, complete, Blender slugs present) and the file-specific schemas.
## Test files are injected under names no real adaptation file uses ("zz_test_*"), so they cannot clash.


## Every MisoStory adaptation is explained and flagged (brief: "no canonical value is silently guessed").
func parity_keys() -> Dictionary:
	var explained := ["canon:adaptations-explained"]
	return {
		"test_value_without_reason_or_verified": explained,
		"test_every_accepted_reason_spelling": explained,
		"test_verified_true_must_say_against_what": explained,
		"test_sibling_verified_flag_needs_its_own_verified_against": explained,
		"test_owner_natural_regen_rule_is_accepted": explained + ["canon:provenance-per-property"],
	}


func _with_file(c: ContentDB, name: String, data: Variant, folder: String = "") -> ContentDB:
	if not c.miso.has(folder):
		c.miso[folder] = {}
	c.miso[folder][name] = data
	return c


func test_unbroken_copy_has_no_crosswalk_errors() -> void:
	assert_eq(baseline().matching("crosswalk", "", "", "error").size(), 0, "crosswalk errors in the unbroken copy")


func test_value_without_reason_or_verified() -> void:
	var c := _with_file(clone_db(), "zz_test_tuning", {"id": "zz_test_tuning", "speed_mps": 3.0, "nested": {"delay_s": 0.5}})
	var r := run_validator(c)
	expect_new(r, "error", "adaptation", "misostory", "zz_test_tuning", "without a reason: nested.delay_s, speed_mps")
	expect_new(r, "error", "adaptation", "misostory", "zz_test_tuning", "without a verified flag: nested.delay_s, speed_mps")


func test_every_accepted_reason_spelling() -> void:
	var c := clone_db()
	_with_file(c, "zz_test_top", {"reason": "one reason for the file", "verified": false, "a": 1, "b": {"c": [1, 2]}})
	_with_file(c, "zz_test_sibling", {"verified": false, "walk_mps": 3.0, "walk_mps_reason": "why"})
	_with_file(c, "zz_test_prefix", {"verified": false, "horizontal_px_to_m": 0.02, "horizontal_reason": "why"})
	_with_file(c, "zz_test_map", {"verified": false, "reasons": {"a": "why a"}, "a": 1})
	_with_file(c, "zz_test_entries", {"rows": [{"x": 1, "reason": "why", "verified": false}], "rows_reason": "why rows", "verified": false})
	_with_file(c, "zz_test_sibling_verified", {"reason": "why", "x": 1, "x_verified": false})
	expect_no_new(run_validator(c), "adaptation")


func test_reason_and_verified_must_be_well_typed() -> void:
	var c := clone_db()
	_with_file(c, "zz_test_types", {"reason": "", "verified": "no", "a": 1, "a_reason": 5, "reasons": {"a": ""}})
	var r := run_validator(c)
	expect_new(r, "error", "adaptation", "misostory", "zz_test_types", "reason must be a non-empty string")
	expect_new(r, "error", "adaptation", "misostory", "zz_test_types", "verified must be true or false")
	expect_new(r, "error", "adaptation", "misostory", "zz_test_types", "a_reason must be a non-empty string")
	expect_new(r, "error", "adaptation", "misostory", "zz_test_types", "reasons.a must be a non-empty string")


func test_verified_true_must_say_against_what() -> void:
	var c := _with_file(clone_db(), "zz_test_verified", {"reason": "why", "verified": true, "a": 1})
	expect_new(run_validator(c), "error", "adaptation", "misostory", "zz_test_verified", "verified is true but has no verified_against")
	# Only verified_against says what a value was checked against; the older free-form keys are not accepted.
	for other in ["verification", "verified_by", "source_url"]:
		var o := _with_file(clone_db(), "zz_test_verified", {"reason": "why", "verified": true, "a": 1, other: "test: checked"})
		expect_new(run_validator(o), "error", "adaptation", "misostory", "zz_test_verified", "verified is true but has no verified_against")
	for bad in ["", "  ", [], [""], {"page": "x"}, 3]:
		var b := _with_file(clone_db(), "zz_test_verified", {"reason": "why", "verified": true, "a": 1, "verified_against": bad})
		expect_new(run_validator(b), "error", "adaptation", "misostory", "zz_test_verified", "verified_against must be a non-empty string")
	c.miso[""]["zz_test_verified"]["verified_against"] = "test: game/data/canonical/maps/000000040.json"
	expect_no_new(run_validator(c), "adaptation")
	c.miso[""]["zz_test_verified"]["verified_against"] = ["a canonical record", "https://meowdb.com/msclassic/maps/000000040"]
	expect_no_new(run_validator(c), "adaptation")


func test_sibling_verified_flag_needs_its_own_verified_against() -> void:
	var c := _with_file(clone_db(), "zz_test_sib", {"reason": "why", "verified": false, "walk_mps": 3.0, "walk_mps_verified": true})
	expect_new(run_validator(c), "error", "adaptation", "misostory", "zz_test_sib", "walk_mps_verified is true but has no walk_mps_verified_against")
	c.miso[""]["zz_test_sib"]["walk_mps_verified_against"] = "test: a canonical movement record"
	expect_no_new(run_validator(c), "adaptation")


## The shape the mechanics package writes for the project owner's natural-regen rule (game/data/misostory/recovery.json,
## brief "Resolve Iteration Two Placeholder: Natural HP Regeneration", contract C4): a Project owner provenance block and
## verified: true against the brief section.
func test_owner_natural_regen_rule_is_accepted() -> void:
	var recovery := {
		"id": "recovery", "kind": "misostory_adaptation",
		"natural_recovery": {
			"hp": {"amount": 10, "interval_s": 10.0, "eligible_activities": ["still", "seated"]},
			"mp": null,
			"reason": "The project owner's rule: 10 HP per 10 s of eligible time; walking, jumping and attacking pause the clock. MP has no natural recovery because MeowDB documents none.",
			"verified": true,
			"verified_against": "docs/ITERATION_THREE_BRIEF.md: Resolve Iteration Two Placeholder: Natural HP Regeneration",
		},
		"provenance": {"natural_recovery": {"authority": ProvenanceAuthorities.PROJECT_OWNER,
			"decision": "ITERATION_THREE_BRIEF: Natural HP Regeneration"}},
	}
	var c := _with_file(clone_db(), "zz_test_recovery", recovery)
	var r := run_validator(c)
	expect_no_new(r, "adaptation")
	expect_no_new(r, "provenance")
	# Without the brief citation the flag is not accepted, and a Project owner source still needs its decision.
	c.miso[""]["zz_test_recovery"]["natural_recovery"].erase("verified_against")
	c.miso[""]["zz_test_recovery"]["provenance"]["natural_recovery"].erase("decision")
	r = run_validator(c)
	expect_new(r, "error", "adaptation", "misostory", "zz_test_recovery", "natural_recovery.verified is true but has no natural_recovery.verified_against")
	expect_new(r, "error", "provenance", "misostory", "zz_test_recovery", "needs decision")


func test_typed_reference_inside_adaptation_file() -> void:
	var c := _with_file(clone_db(), "zz_test_refs", adapted({"start": {"map_id": BOGUS}, "reward": {"item_id": BOGUS + "-item"}}))
	var r := run_validator(c)
	expect_new(r, "error", "reference", "misostory", "zz_test_refs", "start.map_id references maps '%s'" % BOGUS)
	expect_new(r, "error", "reference", "misostory", "zz_test_refs", "reward.item_id references items '%s-item'" % BOGUS)


func test_typed_reference_wrapped_in_a_value_object() -> void:
	# The adaptation house style: {"value": ..., "reason": ..., "verified": ...} on a typed key.
	var c := _with_file(clone_db(), "zz_test_wrapped", adapted({
		"respawn_map_id": {"value": BOGUS, "reason": "test", "verified": false},
		"start_map_id": {"value": c_first_map(), "reason": "test", "verified": false},
	}))
	var r := run_validator(c)
	expect_new(r, "error", "reference", "misostory", "zz_test_wrapped", "respawn_map_id.value references maps '%s'" % BOGUS)
	assert_eq(new_findings(r).size(), 1, "only the broken wrapped reference is reported")


func test_npc_adaptation_disabled_behaviors() -> void:
	var c := clone_db()
	var transporter := first_id_where(c, "npcs", func(r: Dictionary) -> bool: return r.get("transport", null) is Dictionary and not arr(r.transport, "routes").is_empty(), "with transport routes")
	var shopless := first_id_where(c, "npcs", func(r: Dictionary) -> bool: return not (r.get("shop", null) is Dictionary), "without a shop")
	_with_file(c, transporter, adapted({"id": transporter, "npc_id": transporter, "disabled_behaviors": ["transprot", "transport"]}), "npcs")
	_with_file(c, shopless, adapted({"id": shopless, "npc_id": shopless, "disabled_behaviors": ["shop"]}), "npcs")
	var r := run_validator(c)
	expect_new(r, "error", "adaptation", "misostory/npcs", transporter, "disabled_behaviors entry \"transprot\" is not an NPC behaviour")
	expect_new(r, "warning", "adaptation", "misostory/npcs", shopless, "disables 'shop', which NPC %s does not have" % shopless)
	assert_eq(new_findings(r).filter(func(f: Dictionary) -> bool: return f.id == transporter).size(), 1, "the real 'transport' entry is accepted")


func c_first_map() -> String:
	return db().ids("maps")[0]


func test_domain_folder_basename_must_be_a_canonical_id() -> void:
	var c := clone_db()
	var quest_id := c.ids("quests")[0]
	_with_file(c, BOGUS, adapted({}), "quests")
	_with_file(c, quest_id, adapted({"quest_id": BOGUS + "-other"}), "quests")
	var r := run_validator(c)
	expect_new(r, "error", "adaptation", "misostory/quests", BOGUS, "adapts quests '%s', which is not in canonical data" % BOGUS)
	expect_new(r, "error", "adaptation", "misostory/quests", quest_id, "quest_id \"%s-other\" differs from the file basename" % BOGUS)


func test_shared_table_in_a_domain_folder_is_not_an_entity_file() -> void:
	# misostory/<domain>/_<name>.json (AdaptationChecks.SHARED_TABLE_PREFIX) holds values the folder's entity files
	# share, so its basename is not matched against canonical ids; every other adaptation check still applies.
	var c := clone_db()
	var domain_name := "monsters"
	_with_file(c, "_zz_test_shared", adapted({"id": "not-a-%s-id" % domain_name, "probe_m": 0.5}), domain_name)
	_with_file(c, "_zz_test_unexplained", {"probe_m": 0.5, "drop": {"item_id": BOGUS}}, domain_name)
	var r := run_validator(c)
	var label := "misostory/" + domain_name
	assert_true(AdaptationChecks.is_shared_table("_zz_test_shared"), "a leading underscore marks a shared table")
	assert_eq(r.matching("adaptation", label, "_zz_test_shared").size(), 0, "a shared table is not matched against canonical ids")
	expect_new(r, "error", "adaptation", label, "_zz_test_unexplained", "without a reason: drop.item_id, probe_m")
	expect_new(r, "error", "adaptation", label, "_zz_test_unexplained", "without a verified flag")
	expect_new(r, "error", "reference", label, "_zz_test_unexplained", "drop.item_id references items '%s'" % BOGUS)
	assert_eq(r.matching("adaptation", label, "_zz_test_unexplained").filter(
		func(f: Dictionary) -> bool: return "not in canonical data" in f.message or "differs from the file basename" in f.message).size(),
		0, "no entity-file check on a shared table")


func test_external_list_in_adaptation_file() -> void:
	var c := _with_file(clone_db(), "zz_test_external", adapted({"external": [{"field": "x"}]}))
	expect_new(run_validator(c), "error", "external", "misostory", "zz_test_external", "needs a source_url")


func test_crosswalk_must_be_bijective_and_complete() -> void:
	var c := clone_db()
	var rows: Array = c.miso[""]["map_id_crosswalk"]
	var dropped: Dictionary = rows.pop_back()
	rows[1].iteration_one_slug = rows[0].iteration_one_slug
	rows[2].meowdb_id = rows[0].meowdb_id
	rows[3].gms_v8_id = rows[0].gms_v8_id
	var r := run_validator(c)
	var first: String = rows[0].meowdb_id
	expect_new(r, "error", "crosswalk", "crosswalk", dropped.meowdb_id, "has no crosswalk row")
	expect_new(r, "error", "crosswalk", "crosswalk", "map_id_crosswalk", "rows but there are")
	expect_new(r, "error", "crosswalk", "crosswalk", rows[1].meowdb_id, "Blender slug %s appears in more than one row" % rows[0].iteration_one_slug)
	expect_new(r, "error", "crosswalk", "crosswalk", first, "MeowDB id %s appears in more than one row" % first)
	expect_new(r, "error", "crosswalk", "crosswalk", rows[3].meowdb_id, "gms_v8_id %d appears in more than one row" % int(rows[0].gms_v8_id))


func test_crosswalk_row_for_unknown_map_and_missing_basis() -> void:
	var c := clone_db()
	var rows: Array = c.miso[""]["map_id_crosswalk"]
	rows[0].meowdb_id = BOGUS
	rows[1].erase("match_basis")
	var r := run_validator(c)
	expect_new(r, "error", "crosswalk", "crosswalk", BOGUS, "not a canonical map")
	expect_new(r, "error", "crosswalk", "crosswalk", rows[1].meowdb_id, "has no match_basis")


func test_crosswalk_is_required() -> void:
	var c := clone_db()
	c.miso[""].erase("map_id_crosswalk")
	expect_new(run_validator(c, {"world_sidecars": {}}), "error", "adaptation", "misostory", "map_id_crosswalk", "required adaptation file")


func test_blender_slug_without_sidecar_and_map_id_mismatch() -> void:
	var c := clone_db()
	var sidecars := sidecars_for(c)
	var slugs: Array = sidecars.keys()
	slugs.sort()
	sidecars.erase(slugs[0])
	sidecars[slugs[1]].map_id = -1
	var r := run_validator(c, {"world_sidecars": sidecars})
	expect_new(r, "error", "crosswalk", "crosswalk", slugs[0], "has no gameplay sidecar")
	expect_new(r, "error", "crosswalk", "crosswalk", slugs[1], "has map_id -1")


func test_sidecar_without_map_id_is_an_error() -> void:
	var c := clone_db()
	var sidecars := sidecars_for(c)
	var slugs: Array = sidecars.keys()
	slugs.sort()
	sidecars[slugs[0]] = {"kind": "map"}
	expect_new(run_validator(c, {"world_sidecars": sidecars}), "error", "crosswalk", "crosswalk", slugs[0], "has no numeric map_id")


func test_exported_map_chunk_without_crosswalk_row_warns() -> void:
	var c := clone_db()
	var sidecars := sidecars_for(c)
	sidecars["ZzUnlistedMap_999999"] = {"map_id": 999999}
	sidecars["ZzScenery"] = {"kind": "world"}  # no map_id: scenery chunks are not maps
	var r := run_validator(c, {"world_sidecars": sidecars})
	expect_new(r, "warning", "crosswalk", "crosswalk", "ZzUnlistedMap_999999", "no crosswalk row names it")
	assert_eq(r.matching("crosswalk", "crosswalk", "ZzScenery").size(), 0, "a chunk without map_id is not a map")


func test_export_on_disk_sidecars_and_index() -> void:
	# The disk path (no injected sidecars): <world_dir>/<slug>.json sidecars plus index.json. A per-process directory
	# under user:// keeps concurrent test runs apart.
	var dir := "user://zz_validation_export_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var c := clone_db()
	var sidecars := sidecars_for(c)
	var slugs: Array = sidecars.keys()
	slugs.sort()
	var chunks := {"ZzExtra_777": {"kind": "map", "map_id": 777}, "ZzScenery": {"kind": "world"}}
	for slug in slugs:
		if slug != slugs[0]:  # the first slug has no sidecar file
			_write_json(dir.path_join(slug + ".json"), sidecars[slug])
		if slug != slugs[1]:  # the second has a sidecar but no chunk in index.json
			chunks[slug] = {"kind": "map", "map_id": sidecars[slug].map_id}
	_write_json(dir.path_join("index.json"), {"chunks": chunks})
	var r := run_validator(c, {"world_dir": dir})
	expect_new(r, "error", "crosswalk", "crosswalk", slugs[0], "has no gameplay sidecar")
	expect_new(r, "error", "crosswalk", "crosswalk", slugs[1], "has no chunk in %s/index.json" % dir)
	expect_new(r, "warning", "crosswalk", "crosswalk", "ZzExtra_777", "no crosswalk row names it")
	assert_eq(r.matching("crosswalk", "crosswalk", "ZzScenery").size(), 0, "scenery chunks are not maps")
	assert_eq(int(r.stats.get("sidecars_checked", 0)), slugs.size(), "every slug checked on disk")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


static func _write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func test_absent_blender_export_is_only_a_warning() -> void:
	var r := DataValidator.validate(clone_db(), {"world_dir": "res://zz_no_such_export"})
	assert_eq(r.matching("crosswalk", "crosswalk", "world_assets", "warning").size(), 1, "one warning for the absent export")
	assert_eq(r.matching("crosswalk", "", "", "error").size(), 0, "no crosswalk errors without an export")


func test_world_scale_factors() -> void:
	var c := _with_file(clone_db(), "world_scale", adapted({"horizontal_px_to_m": 0.02, "vertical_px_to_m": -1.0}))
	var r := run_validator(c)
	expect_new(r, "error", "adaptation", "misostory", "world_scale", "vertical_px_to_m must be a positive number")
	expect_new(r, "error", "adaptation", "misostory", "world_scale", "actor_px_to_m must be a positive number")


## drop_rates.json is the v2 interpretations file (contract C1): the shipped file passes; each interpretation the drop
## runtime applies must be there with a string value; Iteration Two's placeholder tables are refused by the drop policy
## (DropRates.validate through DropChecks), not checked as if they still supplied rates.
func test_drop_rates_is_the_v2_interpretations_file() -> void:
	assert_eq(baseline().matching("adaptation", "misostory", "drop_rates").size(), 0, "the shipped file passes")
	var c := clone_db()
	var rates: Dictionary = (c.miso[""]["drop_rates"] as Dictionary)
	rates.erase("meso_amount_distribution")
	(rates["quest_gate_rule"] as Dictionary)["value"] = 5
	var r := run_validator(c)
	expect_new(r, "error", "adaptation", "misostory", "drop_rates", "meso_amount_distribution must be an object")
	expect_new(r, "error", "adaptation", "misostory", "drop_rates", "quest_gate_rule.value must be a non-empty string")
	var old := _with_file(clone_db(), "drop_rates", adapted({
		"meso_amount_distribution": {"value": DropRates.MESO_DISTRIBUTION, "reason": "test", "verified": false},
		"quest_gate_rule": {"value": "test rule", "reason": "test", "verified": false},
		"item_overrides": {BOGUS: {"chance": 0.5}},
		"mesos": {"per_level": {"min": 3, "max": 1}},
	}))
	var r2 := run_validator(old)
	expect_new(r2, "error", "drop_policy", "misostory", "drop_rates", "item_overrides: a chance, quantity or meso value outside the canonical drop records")
	expect_new(r2, "error", "drop_policy", "misostory", "drop_rates", "mesos.per_level")
	for f in new_findings(r2):
		assert_ne(String(f.check), "reference", "a placeholder table is not resolved as if it still applied: %s" % f.message)
	assert_eq(r2.matching("adaptation", "misostory", "drop_rates").size(), 0, "both interpretations present")


func test_new_character_start_spawn_index() -> void:
	var c := clone_db()
	var map_id := c.ids("maps")[0]
	_with_file(c, "new_character", adapted({"start_location": {"map_id": map_id, "spawn_index": 999}, "quick_start": {"weapon_id": BOGUS}}))
	var r := run_validator(c)
	expect_new(r, "error", "adaptation", "misostory", "new_character", "spawn_index 999 is not one of map %s's" % map_id)
	expect_new(r, "error", "reference", "misostory", "new_character", "quick_start.weapon_id references items '%s'" % BOGUS)


func test_inventory_must_classify_every_canonical_weapon() -> void:
	var c := clone_db()
	var weapon := first_id_where(c, "items", func(r: Dictionary) -> bool: return r.get("weapon", null) is Dictionary, "that is a weapon")
	_with_file(c, "inventory", adapted({"weapon_subtypes": {}}))
	expect_new(run_validator(c), "error", "adaptation", "misostory", "inventory", "canonical weapon item %s" % weapon)


func test_combat_skill_keys_are_canonical_skills() -> void:
	var c := _with_file(clone_db(), "combat", adapted({"fixed_damage_skills": {BOGUS: {"hit_check": true}}}))
	expect_new(run_validator(c), "error", "adaptation", "misostory", "combat", "fixed_damage_skills.%s is not a canonical skill id" % BOGUS)


func test_portal_adaptations_name_real_portals() -> void:
	var c := clone_db()
	var from := first_id_where(c, "maps", func(r: Dictionary) -> bool: return not arr(r, "portals").is_empty() and not arr(r, "player_spawns").is_empty(), "with a portal")
	var portal: Dictionary = c.map(from).portals[0]
	var to: String = portal.to_map_id
	_with_file(c, "portal_adaptations", adapted({
		"link_modes": {"overrides": {"T_%s_nope__%s" % [from, to]: {"mode": "edge"}, "bad-link": {}}},
		"destination_overrides": {"overrides": {"%s.nope" % from: {}, "%s.%s" % [from, portal.name]: {"destination_portal_id": "nope", "destination_spawn_index": 999}}},
		"arrival_gates": {"gates": [{"map_id": from, "source_portal": "%s.%s" % [from, portal.name], "spawn_index": 0}]},
		"one_way_allowlist": {"links": [{"from": to, "to": BOGUS}, {"from": from, "to": to}]},
	}))
	var r := run_validator(c)
	expect_new(r, "error", "adaptation", "misostory", "portal_adaptations", "%s has no portal 'nope'" % from)
	expect_new(r, "error", "adaptation", "misostory", "portal_adaptations", "key 'bad-link' is not a link id")
	expect_new(r, "error", "adaptation", "misostory", "portal_adaptations", "map %s has no portal 'nope'" % from)
	expect_new(r, "error", "adaptation", "misostory", "portal_adaptations", "destination_portal_id 'nope' is not a portal of %s" % to)
	expect_new(r, "error", "adaptation", "misostory", "portal_adaptations", "destination_spawn_index 999")
	expect_new(r, "error", "adaptation", "misostory", "portal_adaptations", "leads to %s, not to the gate's map %s" % [to, from])
	expect_new(r, "error", "reference", "misostory", "portal_adaptations", "one_way_allowlist.links key '%s'" % BOGUS)
	if c.map(to).get("portals", []).any(func(p: Dictionary) -> bool: return p.get("to_map_id", "") == from):
		expect_new(r, "warning", "adaptation", "misostory", "portal_adaptations", "the entry is stale")


func test_dialogue_files_reuse_existing_lines() -> void:
	var c := clone_db()
	var npc_id := first_id_where(c, "npcs", func(r: Dictionary) -> bool: return not arr(r, "idle_chatter").is_empty(), "with idle chatter")
	var count := arr(c.npc(npc_id), "idle_chatter").size()
	_with_file(c, BOGUS, adapted({}), "dialogue")
	_with_file(c, npc_id, adapted({"npc_id": npc_id, "nodes": {
		"a": {"type": "say", "line": {"npc": npc_id, "field": "idle_chatter", "line": count}},
		"b": {"type": "say", "line": {"npc": npc_id, "field": "idle_chatter", "line": count - 1}},
		"c": {"type": "say", "line": {"quest": BOGUS + "-quest", "section": "on_accept", "line": 0}},
	}}), "dialogue")
	_with_file(c, "_zz_test_system", adapted({"lines": {}}), "dialogue")
	var r := run_validator(c)
	expect_new(r, "error", "adaptation", "misostory/dialogue", BOGUS, "dialogue file for NPC '%s'" % BOGUS)
	expect_new(r, "error", "adaptation", "misostory/dialogue", npc_id, "line %d does not exist" % count)
	expect_new(r, "error", "reference", "misostory/dialogue", npc_id, "quest '%s-quest'" % BOGUS)
	assert_eq(new_findings(r).filter(func(f: Dictionary) -> bool: return f.id == npc_id).size(), 2, "only the two broken specs are reported")
	assert_eq(r.matching("", "misostory/dialogue", "_zz_test_system").size(), 0, "a _system file needs no NPC")


func test_schema_lookup_prefers_exact_file_over_folder_wildcard() -> void:
	assert_eq(AdaptationChecks.schema_for("", "map_id_crosswalk").get("check", ""), "_check_crosswalk", "crosswalk schema")
	assert_eq(AdaptationChecks.schema_for("dialogue", "zz_any").get("check", ""), "_check_dialogue", "folder wildcard")
	assert_true(AdaptationChecks.schema_for("zz_folder", "zz_unknown").is_empty(), "unknown files use the defaults")
	assert_true(AdaptationChecks.is_meta_key("tuning_note"), "*_note is metadata")
	assert_false(AdaptationChecks.is_meta_key("speed_mps"), "a value key is not metadata")
