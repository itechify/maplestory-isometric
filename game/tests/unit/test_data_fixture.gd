class_name DataValidationTestCase
extends TestCase
## Shared fixture for the test_data_validation_* negative tests (this file has no tests of its own).
##
## Each test deep-copies the shipped ContentDB, breaks one thing, validates, and asserts that a finding appears that
## the unbroken copy does not have. Comparing against the unbroken copy (the baseline) keeps these tests about the
## validator, independent of whatever the shipped data currently contains. Victims are picked from the data
## (the first map with a portal, the first quest with a kill objective, ...), never hard-coded canonical ids;
## the only literal ids are the injected broken ones.

## An id no domain uses.
const BOGUS := "zz-not-a-real-id"

static var _baseline: ValidationReport = null


## A deep copy of the shipped content that a test may mutate freely.
func clone_db() -> ContentDB:
	var c := ContentDB.new()
	c.canonical = db().canonical.duplicate(true)
	c.miso = db().miso.duplicate(true)
	c.load_errors = db().load_errors.duplicate()
	c.loaded = true
	return c


## Sidecars matching the crosswalk (slug -> {map_id: gms_v8_id}), so the slug check runs without the Blender export.
func sidecars_for(c: ContentDB) -> Dictionary:
	var out := {}
	var rows: Variant = c.miso_table("map_id_crosswalk")
	for row in ValidationUtil.as_array(rows):
		if row is Dictionary and row.get("iteration_one_slug", null) is String:
			out[row.iteration_one_slug] = {"map_id": row.get("gms_v8_id", null)}
	return out


## Validates `c` with injected sidecars unless `opts` says otherwise. Fails the test when the validator raised a
## script error: the report is then incomplete, and a negative test could pass for the wrong reason.
func run_validator(c: ContentDB, opts: Dictionary = {}) -> ValidationReport:
	var o := opts.duplicate()
	if not o.has("world_dir") and not o.has("world_sidecars"):
		o["world_sidecars"] = sidecars_for(c)
	var r := DataValidator.validate(c, o)
	for f in r.matching(DataValidator.VALIDATOR_CHECK):
		fail("the validator crashed on this data: %s" % f.message)
	return r


## The report for the unbroken copy.
func baseline() -> ValidationReport:
	if _baseline == null:
		_baseline = run_validator(clone_db())
	return _baseline


## Findings in `r` that the unbroken copy does not have.
func new_findings(r: ValidationReport) -> Array[Dictionary]:
	var known := {}
	for f in baseline().findings:
		known[_key(f)] = true
	var out: Array[Dictionary] = []
	for f in r.findings:
		if not known.has(_key(f)):
			out.append(f)
	return out


## Asserts that `r` has a new finding with this severity, check, domain and id whose message contains `contains`.
func expect_new(r: ValidationReport, severity: String, check: String, domain: String, id: String, contains: String = "") -> void:
	for f in new_findings(r):
		if f.severity == severity and f.check == check and f.domain == domain and f.id == id and (contains == "" or contains in f.message):
			return
	fail("expected a new %s [%s] %s/%s containing '%s'; new findings were:\n    %s" % [
		severity, check, domain, id, contains, _describe(new_findings(r))])


## Asserts that `r` has no new finding (optionally: none of this check slug, or none of this severity).
func expect_no_new(r: ValidationReport, check: String = "", severity: String = "") -> void:
	var bad: Array[Dictionary] = []
	for f in new_findings(r):
		if (check == "" or f.check == check) and (severity == "" or f.severity == severity):
			bad.append(f)
	if not bad.is_empty():
		fail("expected no new %s %s findings, got:\n    %s" % [severity, check, _describe(bad)])


## The first record id in `domain` for which `pred.call(record)` is true; fails the test when there is none.
func first_id_where(c: ContentDB, domain_name: String, pred: Callable, what: String) -> String:
	for id in c.ids(domain_name):
		if pred.call(c.get_entity(domain_name, id)):
			return id
	fail("no %s record %s (the shipped data changed shape?)" % [domain_name, what])
	return ""


## The first non-empty Array at `key` in the record (empty when missing).
static func arr(rec: Dictionary, key: String) -> Array:
	var v: Variant = rec.get(key, null)
	return v if v is Array else []


## The first dialogue link object ({kind|type, id}) anywhere under `node`, or {}.
static func first_link(node: Variant) -> Dictionary:
	if node is Dictionary:
		if node.get("ref", null) is Dictionary and node.ref.has("id"):
			return node.ref
		for k in node:
			if str(k) in ["source", "field_sources", "discrepancies"]:
				continue
			var found := first_link(node[k])
			if not found.is_empty():
				return found
	elif node is Array:
		for e in node:
			var found := first_link(e)
			if not found.is_empty():
				return found
	return {}


## A minimal adaptation file body that satisfies the reason/verified convention, merged with `extra`.
static func adapted(extra: Dictionary) -> Dictionary:
	var d := {"id": "test", "reason": "test fixture", "verified": false}
	d.merge(extra, true)
	return d


static func _key(f: Dictionary) -> String:
	return "%s|%s|%s|%s|%s" % [f.severity, f.check, f.domain, f.id, f.message]


static func _describe(list: Array[Dictionary]) -> String:
	if list.is_empty():
		return "(none)"
	var lines: PackedStringArray = []
	for f in list:
		lines.append("%s [%s] %s/%s: %s" % [f.severity, f.check, f.domain, f.id, f.message])
	return "\n    ".join(lines)
