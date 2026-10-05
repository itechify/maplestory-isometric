extends Node
## Headless unit test runner. Discovers res://tests/unit/test_*.gd (TestCase subclasses) and runs every test_* method.
##
##   bash scripts/test.sh                       # import + run everything
##   bash scripts/test.sh combat inventory      # only files whose name contains one of the filters
##
## Exit code 0 = all passed, 1 = failures. Output: one line per failing assertion plus a summary.

const UNIT_DIR := "res://tests/unit"


func _ready() -> void:
	var filters: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		filters.append(a)
	var code := run(filters)
	get_tree().quit(code)


func run(filters: PackedStringArray) -> int:
	var files := _discover(filters)
	var total := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	# A GDScript runtime error only aborts the current function, so a test that errors before recording a failure
	# would "pass". The guard records script errors per test and turns them into failures.
	var guard := ScriptErrorGuard.new()
	guard.attach()
	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			# A parse error leaves the script uninstantiable; count the whole file as a failure, never as 0 tests.
			print("FAIL %s: script failed to load or compile" % path)
			failed += 1
			total += 1
			continue
		var methods: Array = []
		for m in script.get_script_method_list():
			if String(m.name).begins_with("test_") and not (m.name in methods):
				methods.append(m.name)
		methods.sort()
		for m in methods:
			var tc: TestCase = script.new()
			tc.current_test = "%s::%s" % [path.get_file().get_basename(), m]
			guard.clear()
			tc.before_each()
			tc.call(m)
			tc.after_each()
			total += 1
			for e in guard.errors():
				tc.fail("script error: " + e)
			if tc.failures.is_empty():
				continue
			failed += 1
			for f in tc.failures:
				print("FAIL " + f)
	guard.detach()
	var ms := Time.get_ticks_msec() - t0
	print("\n%d tests, %d failed, %d files (%d ms)" % [total, failed, files.size(), ms])
	print("TESTS_PASSED" if failed == 0 else "TESTS_FAILED")
	return 0 if failed == 0 else 1


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
