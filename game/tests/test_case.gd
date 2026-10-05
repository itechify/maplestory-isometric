class_name TestCase
extends RefCounted
## Base class for MisoStory unit tests (see tests/test_runner.gd).
##
## A test file is res://tests/unit/test_<topic>.gd extending TestCase; every method named test_* runs once on a
## fresh instance. Assertions record failures and keep going so one run reports everything. Use the shared content
## (`db()`) for canonical-data tests; never depend on autoload state, so tests stay deterministic.
##
## A test file may also declare which canonical or brief requirements its tests prove (contract C6), with an optional
## `func parity_keys() -> Dictionary` mapping test method names to parity keys, e.g.
## `{"test_1006_end_to_end": ["quest:1006"]}`. The runner records them in its test evidence (TEST_EVIDENCE_OUT, see
## tests/test_runner.gd) and fails a parity_keys() that names a missing test or a malformed key.

static var _shared_db: ContentDB = null

var failures: PackedStringArray = []
var current_test := ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


## The real shipped content, loaded once per test run through the same loader the game uses.
func db() -> ContentDB:
	if _shared_db == null:
		_shared_db = ContentDB.new().load_all()
	return _shared_db


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current_test, msg])


func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		fail(msg)


func assert_false(cond: bool, msg: String = "expected false") -> void:
	if cond:
		fail(msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) and not (_is_num(actual) and _is_num(expected)):
		fail("%s expected %s (%s) got %s (%s)" % [msg, var_to_str(expected), type_string(typeof(expected)), var_to_str(actual), type_string(typeof(actual))])
	elif actual != expected:
		fail("%s expected %s got %s" % [msg, var_to_str(expected), var_to_str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, msg: String = "") -> void:
	if actual == unexpected:
		fail("%s expected anything but %s" % [msg, var_to_str(unexpected)])


func assert_near(actual: float, expected: float, eps: float = 1e-6, msg: String = "") -> void:
	if absf(actual - expected) > eps:
		fail("%s expected %s +/- %s got %s" % [msg, expected, eps, actual])


func assert_between(actual: float, lo: float, hi: float, msg: String = "") -> void:
	if actual < lo or actual > hi:
		fail("%s expected in [%s, %s] got %s" % [msg, lo, hi, actual])


func assert_has(container: Variant, key: Variant, msg: String = "") -> void:
	var ok := false
	if container is Dictionary:
		ok = container.has(key)
	elif container is Array or container is PackedStringArray:
		ok = key in container
	if not ok:
		fail("%s missing %s" % [msg, var_to_str(key)])


func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
