extends DataValidationTestCase
## Negative tests: duplicate or mismatched canonical ids, missing or foreign provenance, malformed external entries,
## a stale canonical_sources.json, missing required fields and loader errors are all caught. Provenance v2 (contract
## C7): per-property sources from the authority registry are accepted, and every misuse of an authority is caught.

const INDEX := "canonical_sources"

## Real citations from the dated captures (tools/kurodb/captures/100101.json, tools/hiddenstreet/captures/monsters.json).
const KURO_SRC := {"authority": "KuroDB", "url": "https://playkuro.com/database/#monsters/100101",
	"read_at": "2026-10-05T07:44:50.614Z", "capture": "tools/kurodb/captures/100101.json", "decision": "D3-3"}
const HS_SRC := {"authority": "Hidden Street", "url": "https://bc.hidden-street.net/monster/blue-snail",
	"read_at": "2026-10-05T08:03:36.825Z", "capture": "tools/hiddenstreet/captures/monsters.json", "decision": "D3-6"}


## Brief Phase 17 (one record, several authorities per property) and Phase 16 (no duplicate canonical ids).
func parity_keys() -> Dictionary:
	var per_property := ["canon:provenance-per-property"]
	return {
		"test_duplicate_id_across_files": ["xref:no-duplicate-ids"],
		"test_per_property_kurodb_and_hidden_street_sources_are_accepted": per_property,
		"test_kurodb_may_not_supply_membership": per_property + ["canon:membership-chance-separate"],
		"test_hidden_street_may_not_supply_a_probability": per_property + ["canon:membership-chance-separate"],
		"test_non_meowdb_source_needs_read_at_and_capture": per_property,
		"test_unknown_authority": per_property,
		"test_urls_must_belong_to_the_authority": per_property,
		"test_project_owner_needs_a_decision": per_property,
		"test_sources_index_lists_capture_files_and_property_sources": per_property,
		"test_quest_tracker_tags_cite_the_capture": per_property,
	}


## Decision D3-2: the live quest tracker (a dated capture) flags all 20 Maple Island quests "Missable" (tag "COT2" too).
## extract_quests.mjs records both per quest with provenance citing the capture, and the validator accepts them.
func test_quest_tracker_tags_cite_the_capture() -> void:
	const CAPTURE := "tools/meowdb/captures/quest_tracker_maple_island.txt"
	var ids := db().ids("quests")
	assert_eq(ids.size(), 20, "the Maple Island quest set")
	for qid in ids:
		var q := db().quest(qid)
		assert_eq(q.get("missable", null), true, "quest %s missable" % qid)
		assert_eq(q.get("tracker_tags", null), ["COT2", "Missable"], "quest %s tracker tags" % qid)
		for field in ["missable", "tracker_tags"]:
			var src: Dictionary = q.get("provenance", {}).get(field, {})
			assert_eq(src.get("authority", null), ProvenanceAuthorities.MEOWDB, "quest %s %s authority" % [qid, field])
			assert_eq(src.get("capture", null), CAPTURE, "quest %s %s capture" % [qid, field])
			assert_true(String(src.get("raw_value", "")).contains("Missable"), "quest %s %s raw row: %s" % [qid, field, src.get("raw_value", "")])
			var row_name := String(src.get("raw_value", "")).split("  ")[0]
			if src.has("note"):  # a collapsed chain row: "Rain's Maple Quiz 1 … 7"
				assert_true(row_name.begins_with(String(q.name).rsplit(" ", true, 1)[0]), "quest %s collapsed row: %s" % [qid, row_name])
			else:
				assert_eq(row_name, q.name, "quest %s row name" % qid)
	assert_eq(baseline().matching("provenance", "quests").size(), 0, "the validator accepts the tracker provenance")


func test_unbroken_copy_has_no_provenance_errors() -> void:
	for check in ["ids", "provenance", "external", "sources_index", "schema", "load"]:
		assert_eq(baseline().matching(check, "", "", "error").size(), 0, "%s errors in the unbroken copy" % check)


func test_id_must_equal_file_basename() -> void:
	var c := clone_db()
	var id := c.ids("monsters")[0]
	c.monster(id).id = BOGUS
	expect_new(run_validator(c), "error", "ids", "monsters", id, "differs from the file basename")


func test_duplicate_id_across_files() -> void:
	var c := clone_db()
	var id := c.ids("items")[0]
	c.canonical.items[BOGUS] = c.item(id).duplicate(true)  # a second file whose id field repeats an existing id
	var r := run_validator(c)
	expect_new(r, "error", "ids", "items", id, "duplicate canonical id in 2 files")
	expect_new(r, "error", "ids", "items", BOGUS, "differs from the file basename")


func test_id_must_be_a_string() -> void:
	var c := clone_db()
	var id := c.ids("npcs")[0]
	c.npc(id).id = 7.0
	expect_new(run_validator(c), "error", "ids", "npcs", id, "no string id")


func test_missing_source_block() -> void:
	var c := clone_db()
	var id := c.ids("quests")[0]
	c.quest(id).erase("source")
	expect_new(run_validator(c), "error", "provenance", "quests", id, "has no source")


func test_wrong_authority_url_and_timestamp() -> void:
	var c := clone_db()
	var id := c.ids("maps")[0]
	c.map(id).source.authority = "Some Wiki"
	c.map(id).source.url = "https://example.com/maps/1"
	c.map(id).source.retrieved_at = "October 4th"
	var r := run_validator(c)
	expect_new(r, "error", "provenance", "maps", id, "source.authority must be")
	expect_new(r, "error", "provenance", "maps", id, "is not a MeowDB MS Classic page")
	expect_new(r, "error", "provenance", "maps", id, "is not an ISO 8601 timestamp")


func test_meowdb_data_and_api_urls_are_accepted_but_lookalikes_are_not() -> void:
	var c := clone_db()
	var ids := c.ids("items")
	c.item(ids[0]).source.url = "https://meowdb.com/_data/safe-to-sell.json"
	c.item(ids[1]).source.url = "https://meowdb.com/msclassic/api/items/1?locale=en"
	c.item(ids[2]).source.url = "https://meowdb.com/msclassicfake/items/1"
	c.item(ids[3]).source.url = "https://meowdb.com.evil.example/msclassic/items/1"
	var r := run_validator(c)
	for i in 2:
		assert_eq(r.matching("provenance", "items", ids[i]).size(), 0, "url of %s accepted" % ids[i])
	expect_new(r, "error", "provenance", "items", ids[2], "is not a MeowDB MS Classic page")
	expect_new(r, "error", "provenance", "items", ids[3], "is not a MeowDB MS Classic page")


func test_field_source_outside_meowdb_needs_an_external_entry() -> void:
	var c := clone_db()
	var id := first_id_where(c, "items", func(r: Dictionary) -> bool: return r.get("field_sources", null) is Dictionary, "with field_sources")
	c.item(id).field_sources["test_field"] = {"url": "https://example.com/wiki/item", "retrieved_at": "2026-10-04T00:00:00Z"}
	expect_new(run_validator(c), "error", "provenance", "items", id, "not on meowdb.com and has no external entry")
	c.item(id)["external"] = [{"field": "test_field", "source_url": "https://example.com/wiki/item",
		"reason": "test: MeowDB does not publish it", "verified": false}]
	assert_eq(run_validator(c).matching("provenance", "items", id).size(), 0, "declared external field source accepted")


func test_external_entry_needs_field_url_reason_and_verified_false() -> void:
	var c := clone_db()
	var id := c.ids("monsters")[0]
	c.monster(id)["external"] = [{"source_url": "not a url", "verified": true}]
	var r := run_validator(c)
	expect_new(r, "error", "external", "monsters", id, "has no field")
	expect_new(r, "error", "external", "monsters", id, "needs a source_url")
	expect_new(r, "error", "external", "monsters", id, "needs a reason")
	expect_new(r, "error", "external", "monsters", id, "must carry verified: false")


func test_sources_index_missing_record() -> void:
	var c := clone_db()
	var index: Dictionary = c.canonical[""][INDEX]
	var removed: Dictionary = index.records.pop_back()
	var key := "%s/%s" % [removed.domain, removed.id]
	var r := run_validator(c)
	expect_new(r, "error", "sources_index", INDEX, key, "not in canonical_sources.json")
	expect_new(r, "error", "sources_index", INDEX, INDEX, "totals.records")


func test_sources_index_lists_a_deleted_record() -> void:
	var c := clone_db()
	var id := c.ids("shops")[0]
	c.canonical.shops.erase(id)
	expect_new(run_validator(c), "error", "sources_index", INDEX, "shops/%s" % id, "no longer exists")


func test_sources_index_stale_entry() -> void:
	var c := clone_db()
	var id := c.ids("npcs")[0]
	c.npc(id).source.retrieved_at = "2030-01-01T00:00:00Z"
	c.npc(id)["gaps"] = arr(c.npc(id), "gaps") + ["a new gap"]
	expect_new(run_validator(c), "error", "sources_index", INDEX, "npcs/%s" % id, "retrieved_at, gap_count")


func test_sources_index_external_entries_are_compared_by_content() -> void:
	var c := clone_db()
	var id := c.ids("monsters")[0]
	var external := [{"field": "zz_field", "source_url": "https://example.com/a", "reason": "test", "verified": false}]
	c.monster(id)["external"] = external
	var row := _index_row(c, "monsters", id)
	row["external"] = [{"field": "zz_field", "source_url": "https://example.com/b", "verified": false}]
	expect_new(run_validator(c), "error", "sources_index", INDEX, "monsters/%s" % id, "external")
	row["external"] = [{"field": "zz_field", "source_url": "https://example.com/a", "verified": false}]
	assert_eq(run_validator(c).matching("sources_index", INDEX, "monsters/%s" % id).size(), 0, "a matching external row is current")


func test_root_level_canonical_file_is_an_error() -> void:
	var c := clone_db()
	c.canonical[""]["zz_loose_table"] = {"id": "zz_loose_table", "chance": 0.5}
	expect_new(run_validator(c), "error", "provenance", "canonical", "zz_loose_table", "not in a domain folder")


func test_retrieved_at_must_be_a_real_date_and_time() -> void:
	var p := ProvenanceChecks.new(ContentDB.new(), ValidationReport.new())
	for good in ["2026-10-04T09:56:36.674Z", "2026-10-04T09:56Z", "2024-02-29T23:59:60+09:00", "2026-10-04T00:00:00-05:30"]:
		assert_true(p.is_iso_timestamp(good), "%s is accepted" % good)
	for bad in ["2026-13-04T00:00:00Z", "2026-02-29T00:00:00Z", "2026-04-31T00:00:00Z", "2026-10-04T24:00:00Z",
			"2026-10-04T23:60:00Z", "2026-10-04T23:00:00+25:00", "2026-10-04T09:56:36", "2026-10-04", 20261004]:
		assert_false(p.is_iso_timestamp(bad), "%s is rejected" % str(bad))


func test_sources_index_missing_entirely() -> void:
	var c := clone_db()
	c.canonical[""].erase(INDEX)
	expect_new(run_validator(c), "error", "sources_index", INDEX, INDEX, "missing")


func test_required_field_missing_or_wrong_type() -> void:
	var c := clone_db()
	var map_id := c.ids("maps")[0]
	var monster_id := c.ids("monsters")[0]
	c.map(map_id).erase("portals")
	c.monster(monster_id).hp = "lots"
	var r := run_validator(c)
	expect_new(r, "error", "schema", "maps", map_id, "field 'portals' must be Array")
	expect_new(r, "error", "schema", "monsters", monster_id, "field 'hp' must be float")


func test_loader_errors_are_errors() -> void:
	var c := clone_db()
	c.load_errors.append("res://data/canonical/maps/broken.json:3: Unexpected character")
	expect_new(run_validator(c), "error", "load", "load", "res://data/canonical/maps/broken.json", "Unexpected character")


## The canonical_sources.json row for <domain>/<id> (fails the test when there is none).
func _index_row(c: ContentDB, domain_name: String, id: String) -> Dictionary:
	for row in c.canonical[""][INDEX].records:
		if row is Dictionary and row.get("domain", "") == domain_name and str(row.get("id", "")) == id:
			return row
	fail("canonical_sources.json has no row for %s/%s" % [domain_name, id])
	return {}


# --- provenance v2: the authority registry (contract C7) -------------------------------------------------------

## A clone with `block` as the `provenance` of the first monster-owned drop record (its index rebuilt); [clone, id].
func _with_drop_provenance(block: Dictionary, keep_index: bool = false) -> Array:
	var c := clone_db()
	var id := first_id_where(c, "drops", func(t: Dictionary) -> bool: return t.owner.kind == "monster", "owned by a monster")
	c.drop_table(id)["provenance"] = block
	if not keep_index:
		reindex(c)
	return [c, id]


func _src(base: Dictionary, changes: Dictionary = {}) -> Dictionary:
	var d := base.duplicate(true)
	for k in changes:
		if changes[k] == null:
			d.erase(k)
		else:
			d[k] = changes[k]
	return d


func test_per_property_kurodb_and_hidden_street_sources_are_accepted() -> void:
	var cid := _with_drop_provenance({"membership": _src(HS_SRC), "probability": _src(KURO_SRC),
		"mesos.amount": _src(HS_SRC), "mesos.probability": _src(KURO_SRC),
		"owner_level": {"authority": "MeowDB MS Classic", "url": "https://meowdb.com/msclassic/monsters/3", "retrieved_at": "2026-10-04T09:57:41Z"}})
	var r := run_validator(cid[0])
	expect_no_new(r)
	# [drops package] The shipped drop records are v2 and carry their own sources: count the replaced block's change.
	var replaced := (db().drop_table(cid[1]).get("provenance", {}) as Dictionary).size()
	assert_eq(int(r.stats.get("provenance_sources_checked", 0)) - int(baseline().stats.get("provenance_sources_checked", 0)),
		5 - replaced, "every property source was checked")


func test_kurodb_may_not_supply_membership() -> void:
	var cid := _with_drop_provenance({"membership": _src(KURO_SRC)})
	expect_new(run_validator(cid[0]), "error", "provenance", "drops", cid[1],
		"provenance.membership: KuroDB may not supply 'membership' (it may supply: probability, mesos.probability)")


func test_hidden_street_may_not_supply_a_probability() -> void:
	var cid := _with_drop_provenance({"probability": _src(HS_SRC), "mesos.probability": _src(HS_SRC)})
	var r := run_validator(cid[0])
	expect_new(r, "error", "provenance", "drops", cid[1], "provenance.probability: Hidden Street may not supply 'probability'")
	expect_new(r, "error", "provenance", "drops", cid[1], "provenance.mesos.probability: Hidden Street may not supply 'mesos.probability'")


func test_non_meowdb_source_needs_read_at_and_capture() -> void:
	var cid := _with_drop_provenance({"probability": _src(KURO_SRC, {"read_at": null}),
		"membership": _src(HS_SRC, {"capture": null}), "mesos.amount": _src(HS_SRC, {"read_at": "2026-10-05T08:0x"})})
	var r := run_validator(cid[0])
	expect_new(r, "error", "provenance", "drops", cid[1], "provenance.probability: needs read_at, an ISO 8601 timestamp")
	expect_new(r, "error", "provenance", "drops", cid[1], "provenance.membership: Hidden Street values need capture")
	expect_new(r, "error", "provenance", "drops", cid[1], "provenance.mesos.amount: needs read_at")


func test_missing_capture_file() -> void:
	var cid := _with_drop_provenance({"probability": _src(KURO_SRC, {"capture": "tools/kurodb/captures/zz_missing.json"})})
	expect_new(run_validator(cid[0]), "error", "provenance", "drops", cid[1],
		"provenance.probability.capture names tools/kurodb/captures/zz_missing.json, which does not exist")


func test_capture_path_must_be_a_repo_path_under_tools_captures() -> void:
	for bad in ["../tools/kurodb/captures/100101.json", "game/data/canonical/items/242.json",
			"tools/kurodb/captures/../../../README.md", "C:/repo/tools/kurodb/captures/100101.json",
			"tools\\kurodb\\captures\\100101.json", "tools/kurodb/100101.json"]:
		var cid := _with_drop_provenance({"probability": _src(KURO_SRC, {"capture": bad})})
		expect_new(run_validator(cid[0]), "error", "provenance", "drops", cid[1], "is not a capture path")


func test_unknown_authority() -> void:
	var cid := _with_drop_provenance({"probability": {"authority": "Some Wiki", "url": "https://example.com/snail",
		"read_at": "2026-10-05T00:00:00Z"}})
	expect_new(run_validator(cid[0]), "error", "provenance", "drops", cid[1], "authority \"Some Wiki\" is not registered")


func test_urls_must_belong_to_the_authority() -> void:
	var cid := _with_drop_provenance({
		"probability": _src(KURO_SRC, {"url": "https://playkuro.com.evil/database/#monsters/100101"}),
		"membership": _src(HS_SRC, {"url": "https://meowdb.com/msclassic/monsters/3"}),
		"mesos.probability": _src(KURO_SRC, {"url": null}),
	})
	var r := run_validator(cid[0])
	expect_new(r, "error", "provenance", "drops", cid[1], "is not a KuroDB page")
	expect_new(r, "error", "provenance", "drops", cid[1], "provenance.membership: url \"https://meowdb.com/msclassic/monsters/3\" is not a Hidden Street page")
	expect_new(r, "error", "provenance", "drops", cid[1], "provenance.mesos.probability: KuroDB needs a url")
	# Several pages of one site (the Wooden Box chances come from four KuroDB item pages): `urls`.
	var ok := _with_drop_provenance({"probability": _src(KURO_SRC, {"url": null,
		"urls": ["https://playkuro.com/database/#items/2010000", "https://playkuro.com/database/#items/4031161"]})})
	expect_no_new(run_validator(ok[0]))


func test_project_owner_needs_a_decision() -> void:
	var c := clone_db()
	var combat: Dictionary = c.miso[""]["combat"]
	combat["provenance"] = {"natural_recovery": {"authority": "Project owner"}}
	expect_new(run_validator(c), "error", "provenance", "misostory", "combat", "provenance.natural_recovery: needs decision")
	combat["provenance"] = {"natural_recovery": {"authority": "Project owner",
		"decision": "docs/ITERATION_THREE_BRIEF.md: Resolve Iteration Two Placeholder: Natural HP Regeneration"}}
	expect_no_new(run_validator(c))
	combat["provenance"] = {"natural_recovery": {"authority": "Project owner", "decision": "D3-5"}}
	expect_no_new(run_validator(c))
	combat["provenance"] = {"natural_recovery": {"authority": "KuroDB", "url": "https://playkuro.com/database/#x",
		"read_at": "2026-10-05T07:44:50.614Z", "capture": "tools/kurodb/captures/100101.json"}}
	expect_new(run_validator(c), "error", "provenance", "misostory", "combat", "KuroDB may not supply 'natural_recovery'")


func test_v1_records_keep_the_v1_rules() -> void:
	# No provenance block, no schema_version: exactly the old checks. A foreign authority in `source` still fails,
	# and a KuroDB field source still needs an external entry; the registry does not loosen v1.
	assert_eq(baseline().matching("provenance", "", "", "error").size(), 0, "the shipped data has no provenance errors")
	# [drops package] The shipped drop records are v2 now; every other domain is still v1.
	var c := clone_db()
	var item_id := c.ids("items")[0]
	c.item(item_id).source.authority = "KuroDB"
	c.item(item_id).source.url = "https://playkuro.com/database/#items/2000000"
	var r := run_validator(c)
	expect_new(r, "error", "provenance", "items", item_id, "source.authority must be \"MeowDB MS Classic\"")
	expect_new(r, "error", "provenance", "items", item_id, "is not a MeowDB MS Classic page")
	var c2 := clone_db()
	var mon := c2.ids("monsters")[0]
	c2.monster(mon)["field_sources"] = {"zz": {"url": "https://playkuro.com/database/#monsters/100100"}}
	expect_new(run_validator(c2), "error", "provenance", "monsters", mon, "not on meowdb.com and has no external entry")


func test_capture_lookup_is_live_on_the_shipped_data() -> void:
	# Item 242 (Green Apple) is built from the item API capture; with an empty injected capture list its citations fail.
	var c := clone_db()
	var id := first_id_where(c, "items", func(r: Dictionary) -> bool: return r.get("source", {}).has("capture"), "built from a capture")
	var r := run_validator(c, {"capture_files": {}})
	expect_new(r, "error", "provenance", "items", id, "source.capture names tools/meowdb/captures/items_api.json, which does not exist (looked under the injected capture_files)")
	var cited := {}  # every capture the shipped data cites (items_api.json, the quest tracker, ...)
	for domain_name in ValidationUtil.canonical_domains(c):
		for key in c.ids(domain_name):
			for f in ProvenanceChecks._capture_files(c.get_entity(domain_name, key)):
				cited[f] = true
	assert_has(cited, "tools/meowdb/captures/items_api.json", "the shipped data cites the item API capture")
	expect_no_new(run_validator(c, {"capture_files": cited}))


func test_sources_index_lists_capture_files_and_property_sources() -> void:
	# [drops package] The shipped drop records already cite every KuroDB capture, so the injected block cites a capture
	# file no record cites (it exists: the folder's README) to move totals.capture_files.
	var cid := _with_drop_provenance({"probability": _src(KURO_SRC, {"capture": "tools/kurodb/captures/README.md"})}, true)
	var r := run_validator(cid[0])
	expect_new(r, "error", "sources_index", INDEX, "drops/%s" % cid[1], "capture_files, property_sources")
	expect_new(r, "error", "sources_index", INDEX, INDEX, "totals.capture_files")
	var row := _index_row(db(), "items", first_id_where(db(), "items",
		func(rec: Dictionary) -> bool: return rec.get("source", {}).has("capture"), "built from a capture"))
	assert_eq(row.get("capture_files", []), ["tools/meowdb/captures/items_api.json"], "the shipped index lists the capture")
	var p := ProvenanceChecks.new(cid[0], ValidationReport.new())
	var expected := p.index_row("drops", cid[1], cid[0].drop_table(cid[1]))
	# [drops package] The v2 record's own entries add their KuroDB page to "probability".
	var urls := [KURO_SRC.url]
	for e in cid[0].drop_table(cid[1]).entries:
		if e.chance_source is Dictionary and not (e.chance_source.url in urls):
			urls.append(e.chance_source.url)
	urls.sort()
	assert_eq(expected.property_sources.probability, {"authorities": ["KuroDB"], "urls": urls})


func test_source_object_rules() -> void:
	var p := ProvenanceChecks.new(ContentDB.new(), ValidationReport.new(), {"capture_files": {}})
	var cases := [
		# [property, source, owner kind, expected problem substring or "" for valid]
		["probability", KURO_SRC, "", ""],
		["probability", _src(KURO_SRC, {"decision": null}), "", ""],
		["membership", HS_SRC, "monster", ""],
		["membership", HS_SRC, "breakable", "does not describe breakable drop owners"],
		["anything", {"authority": "MeowDB MS Classic", "url": "https://meowdb.com/msclassic/monsters/2", "retrieved_at": "2026-10-04T09:57:41Z"}, "", ""],
		["anything", {"authority": "MeowDB MS Classic", "url": "https://meowdb.com/msclassic/monsters/2"}, "", "needs read_at"],
		["anything", {"authority": "MeowDB MS Classic", "url": "https://meowdb.com/msclassicfake/2", "read_at": "2026-10-04T09:57:41Z"}, "", "is not a MeowDB MS Classic page"],
		["probability", _src(KURO_SRC, {"url": "https://playkuro.com/database/#"}), "", "is not a KuroDB page"],
		["probability", _src(KURO_SRC, {"urls": []}), "", "urls must be a non-empty list"],
		["mesos.amount", _src(KURO_SRC), "", "KuroDB may not supply 'mesos.amount'"],
		["quantity", _src(KURO_SRC), "", "KuroDB may not supply 'quantity'"],
		["natural_recovery", {"authority": "Project owner", "decision": "D3"}, "", "needs decision"],
		["natural_recovery", {"authority": "Project owner", "decision": "owner rule, see D3-7"}, "", ""],
		["natural_recovery", {"authority": "Project owner", "decision": "D3-7", "read_at": "yesterday"}, "", "needs read_at"],
		["probability", _src(KURO_SRC, {"decision": "decided"}), "", "needs decision"],
		["probability", "KuroDB", "", "must be an object"],
		["probability", {"authority": null}, "", "is not registered"],
	]
	for case in cases:
		var problems := p.source_object_problems(case[0], case[1], case[2])
		var want: String = case[3]
		if want == "":
			assert_eq(problems.size(), 0, "%s %s: %s" % [case[0], str(case[1]), str(problems)])
		else:
			assert_true(problems.size() > 0 and want in "\n".join(problems), "%s %s: expected '%s', got %s" % [case[0], str(case[1]), want, str(problems)])


func test_registry_rules() -> void:
	assert_true(ProvenanceAuthorities.allows("KuroDB", "probability"))
	assert_true(ProvenanceAuthorities.allows("KuroDB", "mesos.probability"))
	assert_false(ProvenanceAuthorities.allows("KuroDB", "membership"))
	assert_true(ProvenanceAuthorities.allows("Hidden Street", "membership"))
	assert_true(ProvenanceAuthorities.allows("Hidden Street", "mesos.amount"))
	assert_false(ProvenanceAuthorities.allows("Hidden Street", "probability"))
	assert_true(ProvenanceAuthorities.allows("MeowDB MS Classic", "membership"))
	assert_true(ProvenanceAuthorities.allows("Project owner", "natural_recovery"))
	assert_false(ProvenanceAuthorities.has("Hidden Street (Before Chaos)"))
	assert_true(ProvenanceAuthorities.url_allowed("Hidden Street", "https://bc.hidden-street.net/monster/snail"))
	assert_false(ProvenanceAuthorities.url_allowed("Hidden Street", "https://bc.hidden-street.net.evil/monster/snail"))
	assert_false(ProvenanceAuthorities.url_allowed("KuroDB", "https://playkuro.com/database/"))


func test_empty_content_is_an_error() -> void:
	var r := DataValidator.validate(ContentDB.new())
	assert_true(r.has_errors(), "an empty ContentDB fails validation")
	assert_eq(r.matching("load").size(), 1, "one load error for empty content")
