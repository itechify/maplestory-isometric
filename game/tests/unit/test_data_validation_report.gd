extends DataValidationTestCase
## The provenance validation report (brief Phase 17; ProvenanceReport, written by `validate_data.sh --report`): every
## canonical record and property with its authority, URL, read time and capture; every unresolved value; every
## adaptation with its verified flag and reason; every icon pack from its pack.json; counts that add up; and the same
## output for the same data.

func parity_keys() -> Dictionary:
	return {
		"test_every_record_and_property_is_reported": ["canon:provenance-per-property"],
		"test_drop_sources_and_unresolved_members_are_reported": ["canon:provenance-per-property",
			"canon:unresolved-visible", "canon:membership-rarity-separate"],
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
	assert_has(doc.capture_files, "tools/meowdb/captures/quest_tracker_maple_island.txt", "captures cited")
	assert_has(doc.capture_files, "tools/henesys/captures/item_rarity.json", "captures cited")


func test_drop_sources_and_unresolved_members_are_reported() -> void:
	# The Snail's record with one member Henesys.gg has no row for (rarity null) and one with no local item.
	var c := clone_db()
	var rec: Dictionary = c.canonical.drops["2"]
	for e in rec.entries:
		if e.key == "sword":
			e.rarity = null
		elif e.key == "white-undershirt":
			e.item_id = null
			e.item_resolution = {"state": "not_in_snapshot", "method": "none", "candidates": [], "evidence": "test: no local item"}
			e.chance_category = null
			e.category_inputs = {"item_type": null, "item_subtype": null, "quest_gated": false, "item": null}
	reindex(c)
	var doc := _doc(c)
	var record: Dictionary = doc.records.filter(func(r: Dictionary) -> bool: return r.domain == "drops" and r.id == "2")[0]
	assert_has(record.authorities, ProvenanceAuthorities.MEOWDB, "MeowDB membership")
	assert_has(record.authorities, ProvenanceAuthorities.HENESYS, "Henesys.gg rarity")
	var kinds := {}
	for p in record.properties:
		kinds[p.property] = p.authority
	assert_eq(kinds.get("membership", ""), ProvenanceAuthorities.MEOWDB, "membership authority")
	assert_eq(kinds.get("rarity", ""), ProvenanceAuthorities.HENESYS, "rarity authority")
	assert_eq(kinds.get("mesos.amount", ""), ProvenanceAuthorities.MEOWDB, "the Snail's meso report")
	assert_false(kinds.has("probability"), "no chance is a sourced property: %s" % str(kinds.keys()))
	var open_of := func(key: String) -> Array:
		return doc.unresolved.drops.filter(func(u: Dictionary) -> bool: return u.record == "drops/2" and u.get("entry", "") == key).map(func(u: Dictionary) -> String: return u.kind)
	assert_eq(open_of.call("sword"), ["rarity"], "the member without a Henesys.gg rarity is listed")
	assert_eq(open_of.call("white-undershirt"), ["item"], "and the member without a local item")
	assert_eq(open_of.call("snail-shell"), [], "a resolved entry is not listed")
	var meso_gaps: Array = doc.unresolved.drops.filter(func(u: Dictionary) -> bool: return u.record == "drops/3" and u.kind == "meso")
	assert_eq(meso_gaps.size(), 2, "the Blue Snail's meso gaps (no MeowDB report; no MeowDB chance) are listed: %s" % str(meso_gaps))


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
	for heading in ["# Provenance validation report", "## Summary", "## Records", "## Properties", "## Unresolved values", "## Adaptations",
			"## Icon packs"]:
		assert_true(md.contains("\n" + heading + "\n") or md.begins_with(heading + "\n"), "heading %s" % heading)


func test_findings_are_attached_to_their_record() -> void:
	var c := clone_db()
	var shop := first_id_where(c, "shops", func(r: Dictionary) -> bool: return not arr(r, "items").is_empty(), "with stock")
	c.shop(shop).items[0].item_id = BOGUS
	var doc := _doc(c)
	var record: Dictionary = doc.records.filter(func(r: Dictionary) -> bool: return r.domain == "shops" and r.id == shop)[0]
	assert_true(record.findings.any(func(f: Dictionary) -> bool: return f.severity == "error" and BOGUS in f.message), "the record lists its error: %s" % str(record.findings))
	assert_true(doc.validation.errors > 0, "the run's error count")


func test_icon_packs_are_reported_from_pack_json_alone() -> void:
	# A folder of this process's own (user:// is shared by every checkout and copy that runs the suite) with a fake
	# pack, a pack.json that does not parse, one that is not an object and a folder without one.
	var dir := "user://zz_icon_packs_report_%d" % OS.get_process_id()
	var variant := func(id: String, v: String, fetched: String) -> Dictionary:
		return {"url": "https://example.test/item/%s/%s" % [id, v], "sha256": "ab", "size": [26, 27], "origin": [-4, 27], "fetched": fetched}
	_write_text(dir.path_join("zz_fake/pack.json"), JSON.stringify({
		"format": 1, "name": "zz_fake", "source": {"service": "example.test", "region": "R", "version": "V1"},
		"items": {
			"4000001": {"icon": variant.call("4000001", "icon", "2026-10-09")},
			"2000000": {"icon": variant.call("2000000", "icon", "2026-10-09"), "iconRaw": variant.call("2000000", "iconRaw", "2026-10-01")},
			"1002000": {"icon": {}},
		},
		"skills": {"0001000": {"icon": variant.call("0001000", "icon", "2026-10-09")}},
		"missing": [{"kind": "item", "id": "4000001", "variant": "iconRaw", "reason": "http 404"}],
	}))
	_write_text(dir.path_join("zz_broken/pack.json"), "{not json")
	_write_text(dir.path_join("zz_list/pack.json"), "[1, 2]")
	DirAccess.make_dir_recursive_absolute(dir.path_join("zz_none"))
	var c := clone_db()
	var doc := ProvenanceReport.build(c, run_validator(c), dir)
	assert_eq(doc.icon_packs.map(func(p: Dictionary) -> String: return p.name), ["zz_broken", "zz_fake", "zz_list"],
		"packs by name; a folder without pack.json is none")
	assert_eq(doc.counts.icon_packs, 3, "count")
	if doc.icon_packs.size() != 3:
		_remove_tree(dir)
		return
	var fake: Dictionary = doc.icon_packs[1]
	assert_eq([fake.format, fake.problem, fake.source.version], [1, null, "V1"], "format, no problem, source")
	assert_eq(fake.items.map(func(e: Dictionary) -> String: return e.id), ["2000000", "4000001"], "numeric order; an empty record covers nothing")
	if fake.items.size() == 2:
		assert_eq(fake.items[0].variants, ["icon", "iconRaw"], "the recorded variants")
		assert_eq(fake.items[0].fetched, ["2026-10-01", "2026-10-09"], "their fetch dates")
	assert_eq(fake.skills.map(func(e: Dictionary) -> String: return e.id), ["0001000"], "skills")
	assert_eq(fake.missing, [{"kind": "item", "id": "4000001", "variant": "iconRaw", "reason": "http 404"}], "the miss and its reason")
	assert_true(str(doc.icon_packs[0].problem).begins_with("pack.json does not parse (line "),
		"a broken manifest is a row with its problem: %s" % doc.icon_packs[0].problem)
	assert_eq(doc.icon_packs[2].problem, "pack.json is not a JSON object", "and so is one that is not an object")
	var md := ProvenanceReport.to_markdown(doc)
	var section := md.substr(md.find("\n## Icon packs\n"))
	for line in ["### zz_fake", "Source: example.test, region R, version V1. Manifest: `%s`, format 1." % dir.path_join("zz_fake/pack.json"),
			"Covered: 2 items and 1 skills. Missing: 1 variants.", "| item | 2000000 | icon, iconRaw | 2026-10-01, 2026-10-09 |",
			"| skill | 0001000 | icon | 2026-10-09 |", "| item | 4000001 | iconRaw | http 404 |",
			"The manifest cannot be read: pack.json is not a JSON object.", "### zz_broken"]:
		assert_true(section.contains("\n" + line + "\n"), "markdown line: %s" % line)
	assert_true(md.contains("| Icon packs (covered IDs, missing variants) | zz_broken: 0 items, 0 skills covered, 0 variants missing; " +
		"zz_fake: 2 items, 1 skills covered, 1 variants missing; zz_list: 0 items, 0 skills covered, 0 variants missing |"),
		"summary row")
	for image in [".png", "![", "<img", "example.test/item"]:
		assert_false(section.contains(image), "no image or icon URL in the section: %s" % image)
	# PNGs in the pack folder change nothing: the report reads pack.json alone.
	_write_text(dir.path_join("zz_fake/items/2000000/icon.png"), "not read")
	_write_text(dir.path_join("zz_fake/items/9999999/icon.png"), "not read")
	assert_eq(JSON.stringify(ProvenanceReport.icon_pack_rows(dir)), JSON.stringify(doc.icon_packs), "the same rows with PNGs present")
	_remove_tree(dir)
	# The bundled maplestory.io pack (tools/icons/) is listed from its tracked pack.json.
	var bundled: Array = ProvenanceReport.icon_pack_rows(ProvenanceReport.ICON_PACKS_DIR).filter(func(p: Dictionary) -> bool: return p.name == "maplestory_io")
	assert_eq(bundled.size(), 1, "the maplestory_io pack")
	if bundled.size() == 1:
		assert_eq([bundled[0].problem, bundled[0].source.get("service", null)], [null, "maplestory.io"], "readable, from maplestory.io")


static func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


static func _remove_tree(dir: String) -> void:
	for d in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
