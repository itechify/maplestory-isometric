class_name TestRunner
extends Node
## Headless unit test runner. Discovers res://tests/unit/test_*.gd (TestCase subclasses) and runs every test_* method.
##
##   bash scripts/test.sh                       # import + run everything
##   bash scripts/test.sh combat inventory      # only files whose name contains one of the filters
##   TEST_EVIDENCE_OUT=out.json bash scripts/test.sh   # also write the machine-readable test evidence (contract C6)
##
## Exit code 0 = all passed, 1 = failures. Output: one line per failing assertion plus a summary.
##
## Test evidence (docs/runtime/ITERATION_THREE_CONTRACTS.md C6). With TEST_EVIDENCE_OUT set to a file path the runner
## also writes {format, run_at, commit, dirty, world_present, filters, totals, tests: [{file, name, ok, failures,
## parity, needs_world}]}: one entry per test (a file that does not compile is one entry named "(load)"). world_present
## says whether the run saw the Blender export (WorldSidecars.exists(): INCLUDE_WORLD=1 in an ISOLATE run); a test
## needs_world when its file names INCLUDE_WORLD (WORLD_MARKER: the convention of every test that prints SKIP and
## passes without the export), so tools/parity/build_parity.mjs refuses its keys from a run without the world. A test
## file declares the parity keys its tests prove with an optional
##
##   func parity_keys() -> Dictionary:
##       return {"test_sam_to_mai_full_flow": ["quest:1006", "npc:9"]}
##
## mapping test method names to "<category>:<id>" keys (tools/parity/build_parity.mjs reads them). A parity_keys()
## that names a method the file does not have, or a malformed key, is a failure ("<file>::parity_keys"), so evidence
## cannot silently go missing. TEST_EVIDENCE_COMMIT (scripts/test.sh sets it to the checked-out commit) and
## TEST_EVIDENCE_DIRTY ("1" when game/, tools/ or scripts/ differ from it, "0" when not, "" unknown) are recorded.

const UNIT_DIR := "res://tests/unit"
const EVIDENCE_ENV := "TEST_EVIDENCE_OUT"
const COMMIT_ENV := "TEST_EVIDENCE_COMMIT"
const DIRTY_ENV := "TEST_EVIDENCE_DIRTY"
## Format 2 adds dirty, world_present and the entries' needs_world.
const EVIDENCE_FORMAT := 2
## A test file whose source names this needs the exported world (its SKIP line says "run with INCLUDE_WORLD=1").
const WORLD_MARKER := "INCLUDE_WORLD"
## The optional per-file method that maps test names to parity keys.
const PARITY_METHOD := "parity_keys"
## A parity key: "<category>:<id>" with a lowercase category (contract C6: "quest:1005", "drop:2/snail-shell").
const PARITY_KEY_PATTERN := "^[a-z][a-z0-9-]*:\\S+$"
## The evidence entry name of a file that does not load, and of a broken parity_keys().
const LOAD_ENTRY := "(load)"


func _ready() -> void:
	var filters: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		filters.append(a)
	var code := run(filters)
	get_tree().quit(code)


func run(filters: PackedStringArray) -> int:
	var files := _discover(filters)
	var t0 := Time.get_ticks_msec()
	var result := run_files(files)
	var ms := Time.get_ticks_msec() - t0
	var total: int = result.total
	var failed: int = result.failed
	print("\n%d tests, %d failed, %d files (%d ms)" % [total, failed, files.size(), ms])
	var evidence_path := OS.get_environment(EVIDENCE_ENV)
	if evidence_path != "":
		var doc := evidence_document(result.entries, filters, files.size(), ms, OS.get_environment(COMMIT_ENV),
			OS.get_environment(DIRTY_ENV), WorldSidecars.exists())
		if write_evidence(evidence_path, doc):
			print("test evidence written to %s" % evidence_path)
		else:
			print("FAIL test evidence: cannot write %s (%s)" % [evidence_path, error_string(FileAccess.get_open_error())])
			failed += 1
	print("TESTS_PASSED" if failed == 0 else "TESTS_FAILED")
	return 0 if failed == 0 else 1


## Runs every test_* method of the given test scripts and returns {total, failed, entries}, where entries are the
## evidence entries {file, name, ok, failures, parity}. Failures are printed unless `quiet` (tests of the runner).
func run_files(files: PackedStringArray, quiet: bool = false) -> Dictionary:
	var total := 0
	var failed := 0
	var entries: Array = []
	# A GDScript runtime error only aborts the current function, so a test that errors before recording a failure
	# would "pass". The guard records script errors per test and turns them into failures.
	var guard := ScriptErrorGuard.new()
	guard.attach()
	for path in files:
		var file := path.get_file()
		var script: GDScript = load(path) if ResourceLoader.exists(path) else null
		if script == null or not script.can_instantiate():
			# A parse error leaves the script uninstantiable; count the whole file as a failure, never as 0 tests.
			var msg := "FAIL %s: script failed to load or compile" % path
			if not quiet:
				print(msg)
			failed += 1
			total += 1
			entries.append(_entry(file, LOAD_ENTRY, false, [msg.trim_prefix("FAIL ")], []))
			continue
		var world := needs_world(script.source_code)
		var methods: Array = []
		var has_parity := false
		for m in script.get_script_method_list():
			if String(m.name).begins_with("test_") and not (m.name in methods):
				methods.append(m.name)
			elif String(m.name) == PARITY_METHOD:
				has_parity = true
		methods.sort()
		var parity := {}
		if has_parity:
			guard.clear()
			var declared: Variant = (script.new() as TestCase).call(PARITY_METHOD)
			var problems := parity_problems(declared, methods)
			for e in guard.errors():
				problems.append("script error: " + e)
			if problems.is_empty():
				for name in declared:
					parity[String(name)] = Array(declared[name])
			else:
				var label := "%s::%s" % [file.get_basename(), PARITY_METHOD]
				var lines: Array = []
				for p in problems:
					lines.append("%s: %s" % [label, p])
					if not quiet:
						print("FAIL %s: %s" % [label, p])
				failed += 1
				total += 1
				entries.append(_entry(file, PARITY_METHOD, false, lines, [], world))
		for m in methods:
			var tc: TestCase = script.new()
			tc.current_test = "%s::%s" % [file.get_basename(), m]
			guard.clear()
			tc.before_each()
			tc.call(m)
			tc.after_each()
			total += 1
			for e in guard.errors():
				tc.fail("script error: " + e)
			var keys: Array = Array(parity.get(String(m), []))
			entries.append(_entry(file, String(m), tc.failures.is_empty(), Array(tc.failures), keys, world))
			if tc.failures.is_empty():
				continue
			failed += 1
			if not quiet:
				for f in tc.failures:
					print("FAIL " + f)
	guard.detach()
	return {"total": total, "failed": failed, "entries": entries}


## The problems with what a file's parity_keys() returned (empty = valid): it must be a Dictionary whose keys are
## test methods of the file (`methods`) and whose values are arrays of "<category>:<id>" strings.
static func parity_problems(declared: Variant, methods: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	if not (declared is Dictionary):
		out.append("must return a Dictionary {test name: [parity keys]}, got %s" % type_string(typeof(declared)))
		return out
	var pattern := RegEx.create_from_string(PARITY_KEY_PATTERN)
	var known := {}
	for m in methods:
		known[String(m)] = true
	for name in declared:
		if not (name is String or name is StringName) or not known.has(String(name)):
			out.append("names %s, which is not a test_* method of this file" % var_to_str(name))
			continue
		var keys: Variant = declared[name]
		if not (keys is Array or keys is PackedStringArray) or keys.size() == 0:
			out.append("%s: needs a non-empty array of parity keys, got %s" % [name, var_to_str(keys)])
			continue
		for k in keys:
			if not (k is String) or pattern.search(k) == null:
				out.append("%s: %s is not a parity key \"<category>:<id>\" (e.g. \"quest:1005\")" % [name, var_to_str(k)])
	return out


## The evidence document written to TEST_EVIDENCE_OUT. `commit` "" is recorded as null; `dirty` "1" / "0" as true /
## false and anything else as null (unknown); `world_present` is whether the run saw the exported world.
static func evidence_document(entries: Array, filters: PackedStringArray, file_count: int, ms: int, commit: String,
		dirty: String = "", world_present: bool = false) -> Dictionary:
	var failed := 0
	for e in entries:
		if not bool(e.ok):
			failed += 1
	return {
		"format": EVIDENCE_FORMAT,
		"run_at": Time.get_datetime_string_from_system(true) + "Z",
		"commit": commit if commit != "" else null,
		"dirty": true if dirty == "1" else (false if dirty == "0" else null),
		"world_present": world_present,
		"filters": Array(filters),
		"totals": {"tests": entries.size(), "failed": failed, "files": file_count, "ms": ms},
		"tests": entries,
	}


## True when a test file's source names WORLD_MARKER: it needs the exported world and passes with a SKIP line
## without it, so its keys prove nothing from a run without the world.
static func needs_world(source: String) -> bool:
	return source.contains(WORLD_MARKER)


static func write_evidence(path: String, doc: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(doc, " ") + "\n")
	f.close()
	return true


static func _entry(file: String, test_name: String, ok: bool, failures: Array, parity: Array,
		world: bool = false) -> Dictionary:
	return {"file": file, "name": test_name, "ok": ok, "failures": failures, "parity": parity, "needs_world": world}


func _discover(filters: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(UNIT_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		f = f.trim_suffix(".remap")
		if not (f.begins_with("test_") and f.get_extension() == "gd"):
			continue
		if not filters.is_empty():
			var keep := false
			for flt in filters:
				if flt in f:
					keep = true
			if not keep:
				continue
		out.append(UNIT_DIR.path_join(f))
	out.sort()
	return out
