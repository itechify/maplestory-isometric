extends DataValidationTestCase
## Negative tests: duplicate or mismatched canonical ids, missing or foreign provenance, malformed external entries,
## a stale canonical_sources.json, missing required fields and loader errors are all caught.

const INDEX := "canonical_sources"


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


func test_empty_content_is_an_error() -> void:
	var r := DataValidator.validate(ContentDB.new())
	assert_true(r.has_errors(), "an empty ContentDB fails validation")
	assert_eq(r.matching("load").size(), 1, "one load error for empty content")
