extends TestCase
## The content loader itself: data roots load cleanly and every canonical record carries provenance. The full
## provenance policy (allowed URL prefixes, ISO timestamps) is enforced by tests/unit/test_data_validation*.gd.


func test_loads_without_errors() -> void:
	var d := ContentDB.new().load_all()
	assert_eq(d.load_errors.size(), 0, "load errors: %s" % ", ".join(d.load_errors))


func test_every_canonical_record_has_meowdb_source() -> void:
	for domain_name in db().canonical:
		if domain_name == "":
			continue
		for id in db().canonical[domain_name]:
			var rec: Dictionary = db().canonical[domain_name][id]
			var src: Dictionary = rec.get("source", {})
			assert_true(not src.is_empty(), "%s/%s has no source block" % [domain_name, id])
			if not src.is_empty():
				assert_eq(src.get("authority", ""), "MeowDB MS Classic", "%s/%s authority" % [domain_name, id])
				assert_true(String(src.get("url", "")).begins_with("https://meowdb.com/"), "%s/%s url" % [domain_name, id])
