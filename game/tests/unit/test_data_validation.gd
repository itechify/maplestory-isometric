extends TestCase
## The shipped data passes canonical-data validation (brief Phase 22): every reference resolves, provenance is
## complete, canonical_sources.json is current and every adaptation file follows the reason/verified convention.
## Broken data fails here exactly like a compile error. Warnings are reported but do not fail.

static var _report: ValidationReport = null


func _shipped() -> ValidationReport:
	if _report == null:
		_report = DataValidator.validate(db())
	return _report


func test_shipped_data_has_no_errors() -> void:
	var report := _shipped()
	for f in report.errors():
		fail("[%s] %s/%s: %s" % [f.check, f.domain, f.id, f.message])
	assert_eq(report.error_count(), 0, "validation errors in shipped data")


func test_every_canonical_record_was_checked() -> void:
	var total := 0
	for domain_name in ValidationUtil.canonical_domains(db()):
		total += db().ids(domain_name).size()
	assert_true(total > 0, "no canonical records loaded")
	assert_eq(int(_shipped().stats.get("records_checked", 0)), total, "records checked")


func test_references_and_portals_were_resolved() -> void:
	var stats := _shipped().stats
	assert_true(int(stats.get("references_checked", 0)) > 0, "no references were checked")
	var portals := 0
	for map_id in db().ids("maps"):
		portals += db().map(map_id).get("portals", []).size()
	assert_eq(int(stats.get("portals_checked", 0)), portals, "portals checked")


func test_every_adaptation_file_was_checked() -> void:
	var files := 0
	for folder in db().miso:
		files += db().miso[folder].size()
	assert_eq(int(_shipped().stats.get("adaptation_files_checked", 0)), files, "adaptation files checked")


func test_warnings_are_well_formed() -> void:
	for f in _shipped().findings:
		assert_has(["error", "warning"], f.severity, "severity of %s" % str(f))
		for k in ["domain", "id", "message", "check"]:
			assert_true(f.get(k, null) is String, "finding field %s is a string in %s" % [k, str(f)])
		assert_true(String(f.message) != "", "finding has a message: %s" % str(f))


func test_validator_did_not_crash_on_shipped_data() -> void:
	# A script error inside a check aborts only that check; validate() turns it into a "validator" error finding.
	for f in _shipped().matching(DataValidator.VALIDATOR_CHECK):
		fail("validator crashed: %s" % f.message)
	assert_false(ScriptErrorGuard.new().is_attached(), "a new guard starts detached")


func test_npc_corrected_quest_links_are_not_reported() -> void:
	# Quest dialogue keeps MeowDB's raw link where an NPC file corrects it (ref.meowdb_link_id = raw, ref.id =
	# corrected); the game links the corrected id (DialogueText), so the raw id must be neither warned nor skipped.
	var report := _shipped()
	var checked := 0
	for npc_id in db().ids("npcs"):
		for block in ValidationUtil.as_array(db().npc(npc_id).get("quest_dialogue", [])):
			if not (block is Dictionary) or not (block.get("quest_id", null) is String):
				continue
			var corrections := {}
			_corrections(block, corrections)
			for raw in corrections:
				var ref: Dictionary = corrections[raw]
				var target: String = ReferenceChecks.LINK_KINDS.get(str(ref.get("kind", ref.get("type", ""))), "")
				if target == "" or not db().has(target, str(ref.get("id", ""))):
					continue  # a correction outside the dataset is skipped like any canonical link
				checked += 1
				var label := "quests/%s" % block.quest_id
				for f in report.findings:
					if "%s/%s" % [f.domain, f.id] == label and "'%s'" % raw in f.message:
						fail("%s: the corrected link %s was reported as %s" % [label, raw, f.message])
				for s in report.out_of_scope:
					if s.begins_with(label + ":") and "/%s (" % raw in s:
						fail("%s: the corrected link %s was skipped: %s" % [label, raw, s])
	# Without this the test passes on data that has no correction at all (it would then check nothing).
	assert_true(checked > 0, "the shipped NPC files correct at least one quest dialogue link (docs/canonical/npcs.md Discrepancies)")


func test_link_remap_matches_the_game_remap() -> void:
	# ReferenceChecks._link_remap mirrors DialogueText._remap_for (the game's correction of quest dialogue links), so
	# the validator checks the id the player is shown. A change to either side without the other fails here.
	var refs := ReferenceChecks.new(db(), ValidationReport.new())
	var corrected := 0
	for quest_id in db().ids("quests"):
		var game_remap: Dictionary = DialogueText._remap_for(db(), quest_id)
		assert_eq(refs._link_remap(quest_id), game_remap, "quest %s: validator remap vs DialogueText._remap_for" % quest_id)
		if not game_remap.is_empty():
			corrected += 1
	assert_true(corrected > 0, "some shipped quest has a corrected dialogue link, so the comparison is not vacuous")


static func _corrections(node: Variant, out: Dictionary) -> void:
	if node is Dictionary:
		if node.get("ref", null) is Dictionary and node.ref.has("meowdb_link_id"):
			out[str(node.ref.meowdb_link_id)] = node.ref
		for k in node:
			_corrections(node[k], out)
	elif node is Array:
		for e in node:
			_corrections(e, out)


func test_script_error_guard_counts_only_script_errors() -> void:
	var guard := ScriptErrorGuard.new()
	var no_backtrace: Array[ScriptBacktrace] = []
	guard._log_error("check_x", "res://zz_test.gd", 7, "Invalid access to key 'nope'", "", false, Logger.ERROR_TYPE_SCRIPT, no_backtrace)
	guard._log_error("parse", "core/io/json.cpp", 1, "Parse JSON failed", "", false, Logger.ERROR_TYPE_ERROR, no_backtrace)
	guard._log_error("x", "core/x.cpp", 1, "a warning", "", false, Logger.ERROR_TYPE_WARNING, no_backtrace)
	assert_eq(guard.count(), 1, "only the script error is recorded")
	assert_true(guard.errors()[0].begins_with("res://zz_test.gd:7 in check_x: Invalid access"), "error line: %s" % guard.errors()[0])
	guard.clear()
	assert_eq(guard.count(), 0, "clear() forgets")


func test_script_error_guard_attach_and_detach_are_idempotent() -> void:
	var guard := ScriptErrorGuard.new()
	guard.attach()
	guard.attach()
	assert_true(guard.is_attached(), "attached")
	guard.detach()
	guard.detach()
	assert_false(guard.is_attached(), "detached")


func test_tool_starts_broken_until_the_run_completes() -> void:
	# A script error aborts tools/validate_data.gd run() before it lowers exit_code, so the process exits 2, never 0.
	var tool_script: GDScript = load("res://tools/validate_data.gd")
	var node: Node = tool_script.new()
	assert_eq(node.get("exit_code"), 2, "exit_code before run()")
	node.free()


func test_tool_rejects_bad_command_lines() -> void:
	var tool_script: GDScript = load("res://tools/validate_data.gd")
	var cases := {
		"": [],
		"unknown argument '--stirct'": ["--stirct"],
		"--json needs a value": ["--verbose", "--json"],
		"--world-dir needs a value": ["--world-dir", "--strict"],
	}
	assert_eq(tool_script.call("_bad_args", PackedStringArray(["--verbose", "--strict", "--json", "x.json", "--world-dir", "res://w"])), "", "every flag")
	for expected in cases:
		assert_eq(tool_script.call("_bad_args", PackedStringArray(cases[expected])), expected, "args %s" % str(cases[expected]))


func test_report_text_ends_with_summary() -> void:
	var text := _shipped().format_text()
	assert_true(text.ends_with(_shipped().summary()), "format_text ends with the summary line")
	assert_true(_shipped().summary().begins_with("%d errors, " % _shipped().error_count()), "summary starts with the error count")
