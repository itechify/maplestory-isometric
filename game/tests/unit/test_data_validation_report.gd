extends DataValidationTestCase
## The provenance validation report (brief Phase 17; ProvenanceReport, written by `validate_data.sh --report`): every
## canonical record and property with its authority, URL, read time and capture; every unresolved value; every
## adaptation with its verified flag and reason; counts that add up; and the same output for the same data.

const FIXTURE := "res://tests/data/drops_v2/fixture_2.json"


func parity_keys() -> Dictionary:
	return {
		"test_every_record_and_property_is_reported": ["canon:provenance-per-property"],
		"test_v2_drop_sources_and_unresolved_members_are_reported": ["canon:provenance-per-property",
			"canon:unresolved-visible", "canon:membership-chance-separate"],
		"test_gaps_are_reported_as_unresolved_values": ["canon:unresolved-visible"],
		"test_adaptations_are_listed_with_flag_and_reason": ["canon:adaptations-explained"],
	}


func _doc(c: ContentDB = null) -> Dictionary:
	var content := c if c != null else clone_db()
	return ProvenanceReport.build(content, run_validator(content))


func test_every_record_and_property_is_reported() -> void:
	var doc := _doc()
	var total := 0
	for domain_name in ValidationUtil.canonical_domains(db()):
		total += db().ids(domain_name).size()
	assert_eq(doc.counts.records, total, "one entry per canonical record")
	assert_eq(doc.records.size(), total, "records listed")
	var rows := 0
	var by_authority := {}
	for r in doc.records:
		var own: Dictionary = r.properties[0]
		assert_eq(own.property, ProvenanceReport.RECORD_PROPERTY, "%s/%s starts with its own source" % [r.domain, r.id])
		assert_false(own.urls.is_empty(), "%s/%s source URL" % [r.domain, r.id])
		assert_true(own.read_at is String, "%s/%s read time" % [r.domain, r.id])
		var rec := db().get_entity(r.domain, r.id)
		var fields: int = rec.get("field_sources", {}).size() if rec.get("field_sources", null) is Dictionary else 0
		assert_eq(r.properties.size(), 1 + fields + ProvenanceChecks.source_objects(r.domain, rec).size(),
			"%s/%s: source + field_sources + per-property sources" % [r.domain, r.id])
		for p in r.properties:
			rows += 1
			by_authority[p.authority] = int(by_authority.get(p.authority, 0)) + 1
	assert_eq(doc.counts.property_rows, rows, "property row count")
	assert_eq(doc.counts.property_rows_by_authority, by_authority, "rows by authority add up")
	# The quest tracker tags are per-property MeowDB sources read from a dated capture.
	var quest: Dictionary = doc.records.filter(func(r: Dictionary) -> bool: return r.domain == "quests")[0]
	var missable: Array = quest.properties.filter(func(p: Dictionary) -> bool: return p.property == "missable")
	assert_eq(missable.size(), 1, "quest %s missable row" % quest.id)
	if missable.size() == 1:
		assert_eq(missable[0].capture, "tools/meowdb/captures/quest_tracker_maple_island.txt", "capture")
		assert_eq(missable[0].via, "provenance", "via the provenance block")
	assert_has(doc.capture_files, "tools/meowdb/captures/items_api.json", "captures cited")


func test_v2_drop_sources_and_unresolved_members_are_reported() -> void:
	var c := clone_db()
	c.canonical.drops["2"] = load_fixture(FIXTURE)
	reindex(c)
	var doc := _doc(c)
	var record: Dictionary = doc.records.filter(func(r: Dictionary) -> bool: return r.domain == "drops" and r.id == "2")[0]
	assert_has(record.authorities, ProvenanceAuthorities.KURODB, "KuroDB chances")
	assert_has(record.authorities, ProvenanceAuthorities.HIDDEN_STREET, "Hidden Street membership")
	var kinds := {}
	for p in record.properties:
		kinds[p.property] = p.authority
	assert_eq(kinds.get("membership", ""), ProvenanceAuthorities.HIDDEN_STREET, "membership authority")
	assert_eq(kinds.get("probability", ""), ProvenanceAuthorities.KURODB, "probability authority")
	assert_true(kinds.has("mesos.amount") and kinds.has("mesos.probability"), "meso sources: %s" % str(kinds.keys()))
	var open: Array = doc.unresolved.drops.filter(func(u: Dictionary) -> bool: return u.record == "drops/2" and u.get("entry", "") == "wooden-buckler")
	var open_kinds := open.map(func(u: Dictionary) -> String: return u.kind)
	assert_has(open_kinds, "probability", "the member without a KuroDB chance is listed")
	assert_has(open_kinds, "item", "and so is its unresolved item")
	assert_eq(doc.unresolved.drops.filter(func(u: Dictionary) -> bool: return u.record == "drops/2" and u.get("entry", "") == "snail-shell").size(), 0, "a resolved entry is not listed")


func test_gaps_are_reported_as_unresolved_values() -> void:
	var doc := _doc()
	var gaps := 0
	for domain_name in ValidationUtil.canonical_domains(db()):
		for key in db().ids(domain_name):
			gaps += ValidationUtil.as_array(db().get_entity(domain_name, key).get("gaps", null)).size()
	var listed := 0
	var total := 0
	for d in doc.unresolved:
		total += doc.unresolved[d].size()
		listed += doc.unresolved[d].filter(func(u: Dictionary) -> bool: return u.kind == "gap").size()
	assert_eq(listed, gaps, "every gap is an unresolved value")
	assert_eq(doc.counts.unresolved, total, "unresolved count")
	for r in doc.records:
		var mine := 0
		for u in doc.unresolved.get(r.domain, []):
			if u.record == "%s/%s" % [r.domain, r.id]:
				mine += 1
		assert_eq(r.unresolved_count, mine, "%s/%s unresolved count" % [r.domain, r.id])


func test_adaptations_are_listed_with_flag_and_reason() -> void:
	var doc := _doc()
	assert_true(doc.adaptations.size() > 50, "adaptations listed: %d" % doc.adaptations.size())
	var verified := 0
	for a in doc.adaptations:
		assert_true(a.verified is bool, "%s %s flag" % [a.file, a.path])
		assert_true(ValidationUtil.non_empty(a.reason), "%s %s has a reason" % [a.file, a.path])
		if a.verified:
			verified += 1
			assert_true(ValidationUtil.non_empty(a.verified_against) or a.verified_against is Array, "%s %s verified against" % [a.file, a.path])
	assert_eq(doc.counts.adaptations_verified, verified, "verified count")
	var sp: Array = doc.adaptations.filter(func(a: Dictionary) -> bool: return a.file.ends_with("new_character.json") and a.path == "starting_sp")
	assert_eq(sp.size(), 1, "new_character starting_sp listed")


func test_same_data_same_report() -> void:
	var c := clone_db()
	var a := ProvenanceReport.build(c, run_validator(c))
	var b := ProvenanceReport.build(c, run_validator(c))
	assert_eq(JSON.stringify(a), JSON.stringify(b), "deterministic JSON")
	var md := ProvenanceReport.to_markdown(a)
	assert_eq(md, ProvenanceReport.to_markdown(b), "deterministic markdown")
	for heading in ["# Provenance validation report", "## Summary", "## Records", "## Properties", "## Unresolved values", "## Adaptations"]:
		assert_true(md.contains("\n" + heading + "\n") or md.begins_with(heading + "\n"), "heading %s" % heading)


func test_findings_are_attached_to_their_record() -> void:
	var c := clone_db()
	var shop := first_id_where(c, "shops", func(r: Dictionary) -> bool: return not arr(r, "items").is_empty(), "with stock")
	c.shop(shop).items[0].item_id = BOGUS
	var doc := _doc(c)
	var record: Dictionary = doc.records.filter(func(r: Dictionary) -> bool: return r.domain == "shops" and r.id == shop)[0]
	assert_true(record.findings.any(func(f: Dictionary) -> bool: return f.severity == "error" and BOGUS in f.message), "the record lists its error: %s" % str(record.findings))
	assert_true(doc.validation.errors > 0, "the run's error count")
