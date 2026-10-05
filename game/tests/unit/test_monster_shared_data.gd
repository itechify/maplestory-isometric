extends DataValidationTestCase
## The validator's shared-table exception (AdaptationChecks.SHARED_TABLE_PREFIX): a file whose basename starts with
## "_" in a canonical-domain folder of data/misostory (monsters/_shared.json) is a shared adaptation table, not an
## entity file, so it is not matched against canonical ids. Everything else still applies to it: the reason/verified
## convention, the typed-reference sweep and the external rule. Any other basename in such a folder must still be a
## canonical id.


func _with_file(c: ContentDB, folder: String, name: String, data: Variant) -> ContentDB:
	if not c.miso.has(folder):
		c.miso[folder] = {}
	c.miso[folder][name] = data
	return c


func test_the_shipped_shared_monster_table_validates_cleanly() -> void:
	assert_false(db().miso_entity("monsters", MonsterDef.SHARED_TABLE).is_empty(), "monsters/_shared.json ships")
	var found := baseline().matching("", "misostory/monsters", MonsterDef.SHARED_TABLE)
	assert_eq(found.size(), 0, "no finding for monsters/_shared.json: %s" % str(found))
	var monsters := baseline().matching("", "misostory/monsters", "", "error")
	assert_eq(monsters.size(), 0, "no error in data/misostory/monsters: %s" % str(monsters))


func test_a_shared_table_is_not_an_entity_but_still_follows_the_convention() -> void:
	assert_true(AdaptationChecks.is_shared_table("_shared"), "leading underscore")
	assert_false(AdaptationChecks.is_shared_table("2"), "an entity file")
	var c := clone_db()
	for folder: String in ["monsters", "quests"]:
		_with_file(c, folder, "_zz_test_shared", {"verified": false, "delay_s": 0.5})
	var r := run_validator(c)
	for folder: String in ["monsters", "quests"]:
		var label := "misostory/" + folder
		expect_new(r, "error", "adaptation", label, "_zz_test_shared", "without a reason: delay_s")
		for f in new_findings(r):
			assert_false(f.id == "_zz_test_shared" and String(f.message).contains("not in canonical data"),
				"%s: a shared table is not matched against canonical ids (%s)" % [label, f.message])


func test_a_shared_table_is_still_swept_for_references() -> void:
	var c := _with_file(clone_db(), "monsters", "_zz_test_refs", adapted({"home": {"map_id": BOGUS}}))
	expect_new(run_validator(c), "error", "reference", "misostory/monsters", "_zz_test_refs", "home.map_id references maps '%s'" % BOGUS)


func test_other_basenames_in_a_domain_folder_must_still_be_canonical_ids() -> void:
	var c := _with_file(clone_db(), "monsters", "zz_test_shared", adapted({}))
	expect_new(run_validator(c), "error", "adaptation", "misostory/monsters", "zz_test_shared",
		"adapts monsters 'zz_test_shared', which is not in canonical data")
	# A file outside the canonical domains keeps its own rules (no id check at all), underscore or not.
	c = _with_file(clone_db(), "", "_zz_test_table", adapted({"a": 1}))
	expect_no_new(run_validator(c), "adaptation")
