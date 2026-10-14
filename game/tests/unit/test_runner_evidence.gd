extends TestCase
## The unit runner's machine-readable test evidence (contract C6): one entry per test with its outcome and the parity
## keys its file declares through parity_keys(), and a failure when parity_keys() names a missing test or a malformed
## key, so evidence cannot silently go missing. The fixture test files live in tests/data/test_evidence/ (outside
## tests/unit, so the runner never discovers them).

const FIXTURES := "res://tests/data/test_evidence"


## Tooling, not a canonical or brief requirement: no parity keys.
func parity_keys() -> Dictionary:
	return {}


func _run(files: Array) -> Dictionary:
	var paths := PackedStringArray()
	for f in files:
		paths.append(f if String(f).begins_with("res://") else FIXTURES.path_join(f))
	var runner := TestRunner.new()
	var result := runner.run_files(paths, true)
	runner.free()
	return result


func _entry(result: Dictionary, test_name: String) -> Dictionary:
	for e in result.entries:
		if e.name == test_name:
			return e
	return {}


func test_entries_carry_outcome_failures_and_parity() -> void:
	var r := _run(["fixture_tagged.gd"])
	assert_eq(r.total, 3, "tests run")
	assert_eq(r.failed, 1, "failed tests")
	assert_eq(r.entries.size(), 3, "one entry per test")
	var passes := _entry(r, "test_passes")
	assert_eq(passes.get("file", ""), "fixture_tagged.gd", "file")
	assert_eq(passes.get("ok", null), true, "passing test")
	assert_eq(passes.get("parity", []), ["quest:1005", "mechanic:natural-hp-regen"], "parity keys of the passing test")
	assert_eq(passes.get("failures", null), [], "no failures")
	var fails := _entry(r, "test_fails")
	assert_eq(fails.get("ok", null), false, "failing test")
	assert_eq(fails.get("parity", []), ["drop:2/snail-shell"], "a failing test keeps its keys (it is evidence against them)")
	assert_eq(fails.get("failures", []).size(), 1, "the failure is recorded")
	assert_true(String(fails.failures[0]).contains("deliberate fixture failure"), "failure text: %s" % str(fails.failures))
	assert_eq(_entry(r, "test_untagged").get("parity", null), [], "an untagged test has no keys")


func test_a_file_without_parity_keys_has_empty_parity() -> void:
	var r := _run(["fixture_untagged.gd"])
	assert_eq(r.failed, 0, "no failures")
	assert_eq(r.entries.size(), 1, "entries")
	assert_eq(_entry(r, "test_ok").get("parity", null), [], "no keys")


func test_a_broken_parity_keys_is_a_failure_and_its_keys_are_dropped() -> void:
	var r := _run(["fixture_bad_parity.gd"])
	assert_eq(r.total, 2, "the test plus one parity_keys entry")
	assert_eq(r.failed, 1, "parity_keys counts as one failure")
	var broken := _entry(r, TestRunner.PARITY_METHOD)
	assert_eq(broken.get("ok", null), false, "parity_keys entry fails")
	var text := "\n".join(PackedStringArray(broken.get("failures", [])))
	assert_true(text.contains("test_renamed_long_ago"), "names the missing test: %s" % text)
	assert_true(text.contains("Quest 1002"), "names the malformed key: %s" % text)
	assert_eq(_entry(r, "test_ok").get("ok", null), true, "the file's tests still run")
	assert_eq(_entry(r, "test_ok").get("parity", null), [], "keys from a broken map are not recorded")


func test_a_file_that_does_not_load_is_one_failed_entry() -> void:
	var r := _run([FIXTURES.path_join("does_not_exist.gd")])
	assert_eq(r.total, 1, "counted as one test")
	assert_eq(r.failed, 1, "and as a failure")
	assert_eq(r.entries[0].get("name", ""), TestRunner.LOAD_ENTRY, "entry name")
	assert_eq(r.entries[0].get("ok", null), false, "not ok")


func test_parity_problems() -> void:
	var methods := [&"test_a", &"test_b"]
	assert_eq(TestRunner.parity_problems({"test_a": ["quest:1005"], "test_b": PackedStringArray(["item:348"])}, methods).size(), 0, "valid map")
	assert_eq(TestRunner.parity_problems({}, methods).size(), 0, "an empty map is valid")
	assert_eq(TestRunner.parity_problems(["quest:1005"], methods).size(), 1, "not a Dictionary")
	assert_eq(TestRunner.parity_problems({"test_a": []}, methods).size(), 1, "empty key list")
	assert_eq(TestRunner.parity_problems({"test_a": "quest:1005"}, methods).size(), 1, "a bare string instead of a list")
	for bad in ["quest", "quest:", "Quest:1005", "quest: 1005", ":1005", 1005]:
		assert_eq(TestRunner.parity_problems({"test_a": [bad]}, methods).size(), 1, "malformed key %s" % var_to_str(bad))
	for good in ["quest:1005", "drop:2/snail-shell", "portal:000000010/out00", "mechanic:natural-hp-regen", "xref:quest-npc"]:
		assert_eq(TestRunner.parity_problems({"test_a": [good]}, methods).size(), 0, "key %s" % good)


func test_evidence_document_round_trips_through_json() -> void:
	var r := _run(["fixture_tagged.gd", "fixture_untagged.gd"])
	var doc := TestRunner.evidence_document(r.entries, PackedStringArray(["fixture"]), 2, 12, "")
	assert_eq(doc.get("format", null), TestRunner.EVIDENCE_FORMAT, "format")
	assert_eq(doc.get("commit", 0), null, "no commit recorded as null")
	assert_eq(doc.totals, {"tests": 4, "failed": 1, "files": 2, "ms": 12}, "totals")
	assert_true(String(doc.run_at).ends_with("Z"), "run_at is UTC: %s" % doc.run_at)
	var path := "user://test_runner_evidence.json"
	assert_true(TestRunner.write_evidence(path, doc), "written")
	var back: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_true(back is Dictionary, "parses back")
	if back is Dictionary:
		assert_eq(back.tests.size(), 4, "every entry written")
		var fields: Array = back.tests[0].keys()
		fields.sort()
		assert_eq(fields, ["failures", "file", "name", "needs_world", "ok", "parity"], "entry fields")
		assert_eq(TestRunner.evidence_document(r.entries, PackedStringArray(), 1, 0, "abc").commit, "abc", "commit kept")


func test_evidence_records_the_dirty_flag_and_whether_the_world_was_present() -> void:
	var r := _run(["fixture_untagged.gd"])
	var unknown := TestRunner.evidence_document(r.entries, PackedStringArray(), 1, 0, "abc")
	assert_eq(unknown.get("dirty", 0), null, "no TEST_EVIDENCE_DIRTY: unknown")
	assert_eq(unknown.get("world_present", null), false, "no world unless the run saw it")
	assert_eq(TestRunner.evidence_document(r.entries, PackedStringArray(), 1, 0, "abc", "1", true).dirty, true, "dirty")
	assert_eq(TestRunner.evidence_document(r.entries, PackedStringArray(), 1, 0, "abc", "0", true).dirty, false, "clean")
	assert_eq(TestRunner.evidence_document(r.entries, PackedStringArray(), 1, 0, "abc", "0", true).world_present, true, "world")
	assert_eq(TestRunner.EVIDENCE_FORMAT, 2, "format 2: dirty, world_present, needs_world")


## The art pack decides which code paths the pack tests took (they SKIP without it), so the evidence says whether the
## run had it (NO_ART_PACK=1 runs without it).
func test_evidence_records_whether_the_art_pack_was_present() -> void:
	var r := _run(["fixture_untagged.gd"])
	assert_eq(TestRunner.evidence_document(r.entries, PackedStringArray(), 1, 0, "abc").get("art_pack_present", null),
		false, "no pack unless the run had it")
	assert_eq(TestRunner.evidence_document(r.entries, PackedStringArray(), 1, 0, "abc", "0", true, true).get(
		"art_pack_present", null), true, "the pack")


func test_a_test_file_that_names_the_world_switch_needs_the_world() -> void:
	var r := _run(["fixture_world.gd", "fixture_untagged.gd"])
	assert_eq(_entry(r, "test_on_the_world").get("needs_world", null), true, "a file naming %s needs the world" % TestRunner.WORLD_MARKER)
	assert_eq(_entry(r, "test_on_the_world").get("parity", []), ["map:000000040"], "its keys are still recorded (build_parity decides)")
	assert_eq(_entry(r, "test_ok").get("needs_world", null), false, "a logic-only file does not")
	assert_true(TestRunner.needs_world("print(\"SKIP x: run with %s=1\")" % TestRunner.WORLD_MARKER))
	assert_false(TestRunner.needs_world("func test_x() -> void:\n\tpass"))
