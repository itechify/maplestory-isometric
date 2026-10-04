class_name ProvenanceChecks
extends RefCounted
## Identity and provenance of canonical records.
##
##   ids          every record has a string `id` equal to its file basename, unique within its domain
##   schema       the minimum fields each domain's consumers rely on (REQUIRED_FIELDS)
##   provenance   source.authority is MeowDB MS Classic, source.url is a MeowDB MS Classic page, MeowDB data file or
##                MeowDB API, source.retrieved_at is ISO 8601; every field_sources URL is on meowdb.com unless an
##                `external` entry declares it
##   external     every `external` entry (a value taken from outside MeowDB) has field, source_url, reason and
##                verified: false
##   sources_index  canonical_sources.json lists every record exactly as tools/meowdb/build_sources_index.mjs would
##                write it today (same files, URLs, external entries and counts), so "where did this value come from?"
##                stays answerable
##   root files   game/data/canonical/ holds only domain folders plus canonical_sources.json: a loose JSON file there
##                has no domain, so no id, provenance or index check would ever see it

const AUTHORITY := "MeowDB MS Classic"
## A record's own source must be one of these (prefix match on a path boundary).
const SOURCE_URL_PREFIXES := ["https://meowdb.com/msclassic", "https://meowdb.com/_data/", "https://meowdb.com/api/"]
## Field-level sources may cite any meowdb.com page (the site's own JS chunks hold some formulas and labels).
const FIELD_SOURCE_PREFIX := "https://meowdb.com/"
const SOURCES_INDEX := "canonical_sources"
const REBUILD_HINT := "rerun node tools/meowdb/build_sources_index.mjs"
## Groups: 1 year, 2 month, 3 day, 4 hour, 5 minute, 6 second (optional), 7/8 zone offset hours/minutes (optional).
const ISO_8601 := "^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2})(?::(\\d{2})(?:\\.\\d+)?)?(?:Z|[+-](\\d{2}):(\\d{2}))$"

## domain -> {field: expected Variant.Type}. TYPE_FLOAT accepts any JSON number.
const REQUIRED_FIELDS := {
	"maps": {"name": TYPE_STRING, "return_map_id": TYPE_STRING, "portals": TYPE_ARRAY, "player_spawns": TYPE_ARRAY,
		"npcs": TYPE_ARRAY, "monsters": TYPE_ARRAY, "spawns": TYPE_ARRAY},
	"monsters": {"name": TYPE_STRING, "level": TYPE_FLOAT, "hp": TYPE_FLOAT, "exp": TYPE_FLOAT},
	"items": {"name": TYPE_STRING, "type": TYPE_STRING},
	"npcs": {"name": TYPE_STRING, "locations": TYPE_ARRAY},
	"quests": {"name": TYPE_STRING, "start_npc": TYPE_DICTIONARY, "end_npc": TYPE_DICTIONARY,
		"objectives": TYPE_DICTIONARY, "rewards": TYPE_DICTIONARY},
	"shops": {"npc_id": TYPE_STRING, "map_id": TYPE_STRING, "items": TYPE_ARRAY},
	"drops": {"owner": TYPE_DICTIONARY, "entries": TYPE_ARRAY},
	"breakables": {"name": TYPE_STRING},
	"formulas": {"name": TYPE_STRING},
}

var db: ContentDB
var report: ValidationReport
var _iso := RegEx.new()


func _init(content: ContentDB, into: ValidationReport) -> void:
	db = content
	report = into
	_iso.compile(ISO_8601)


## Runs every identity and provenance check over the canonical data.
func run() -> void:
	for domain_name in ValidationUtil.canonical_domains(db):
		_check_ids(domain_name)
		for key in db.ids(domain_name):
			var rec: Dictionary = db.get_entity(domain_name, key)
			report.count("records_checked")
			_check_required(domain_name, key, rec)
			_check_source(domain_name, key, rec)
			check_external(domain_name, key, rec.get("external", null))
	_check_root_files()
	_check_sources_index()


## True when `text` is an ISO 8601 date-time with an explicit zone ("2026-10-04T09:56:36.674Z") that names a real
## calendar date and time (no month 13, February 30 or hour 24).
func is_iso_timestamp(text: Variant) -> bool:
	if not (text is String):
		return false
	var m := _iso.search(text)
	if m == null:
		return false
	var year := m.get_string(1).to_int()
	var month := m.get_string(2).to_int()
	var day := m.get_string(3).to_int()
	if month < 1 or month > 12 or day < 1 or day > _days_in_month(year, month):
		return false
	if m.get_string(4).to_int() > 23 or m.get_string(5).to_int() > 59:
		return false
	if m.get_string(6) != "" and m.get_string(6).to_int() > 60:  # 60 = leap second
		return false
	if m.get_string(7) != "" and (m.get_string(7).to_int() > 23 or m.get_string(8).to_int() > 59):
		return false
	return true


static func _days_in_month(year: int, month: int) -> int:
	if month == 2:
		var leap := (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
		return 29 if leap else 28
	return 30 if month in [4, 6, 9, 11] else 31


## Checks an `external` value list (canonical or adaptation): each entry needs field, source_url, reason and
## verified: false. `external` may be absent (null) or an empty array.
func check_external(domain_label: String, id: String, external: Variant) -> void:
	if external == null:
		return
	if not (external is Array):
		report.error("external", domain_label, id, "external must be an array of {field, source_url, reason, verified: false}")
		return
	var i := 0
	for e in external:
		var where := "external[%d]" % i
		i += 1
		if not (e is Dictionary):
			report.error("external", domain_label, id, "%s is not an object" % where)
			continue
		if not ValidationUtil.non_empty(e.get("field", null)):
			report.error("external", domain_label, id, "%s has no field (which value came from outside MeowDB)" % where)
		var url: Variant = e.get("source_url", null)
		if not ValidationUtil.non_empty(url) or not (String(url).begins_with("https://") or String(url).begins_with("http://")):
			report.error("external", domain_label, id, "%s needs a source_url (http(s) link to where the value came from)" % where)
		if not ValidationUtil.non_empty(e.get("reason", null)):
			report.error("external", domain_label, id, "%s needs a reason (why MeowDB could not supply it)" % where)
		if not ValidationUtil.same(e.get("verified", null), false):
			report.error("external", domain_label, id, "%s must carry verified: false (an outside value is never verified against MeowDB)" % where)


# --- ids ----------------------------------------------------------------------------------------------------

func _check_ids(domain_name: String) -> void:
	var by_id := {}  # id -> [keys]
	for key in db.ids(domain_name):
		var rec: Dictionary = db.get_entity(domain_name, key)
		var id: Variant = rec.get("id", null)
		if not (id is String) or id == "":
			report.error("ids", domain_name, key, "record has no string id (got %s); ids are strings exactly as MeowDB writes them" % var_to_str(id))
			continue
		var basename := key.get_file()
		if id != basename:
			report.error("ids", domain_name, key, "id '%s' differs from the file basename '%s'" % [id, basename])
		if not by_id.has(id):
			by_id[id] = PackedStringArray()
		by_id[id].append(key)
	for id in by_id:
		var keys: PackedStringArray = by_id[id]
		if keys.size() > 1:
			report.error("ids", domain_name, str(id), "duplicate canonical id in %d files: %s" % [keys.size(), ", ".join(keys)])


func _check_required(domain_name: String, key: String, rec: Dictionary) -> void:
	var fields: Dictionary = REQUIRED_FIELDS.get(domain_name, {})
	for field in fields:
		var want: int = fields[field]
		var have: Variant = rec.get(field, null)
		var ok := typeof(have) == want or (want == TYPE_FLOAT and typeof(have) == TYPE_INT)
		if not ok:
			report.error("schema", domain_name, key, "field '%s' must be %s, got %s" % [field, type_string(want), type_string(typeof(have))])


# --- source blocks ------------------------------------------------------------------------------------------

func _check_source(domain_name: String, key: String, rec: Dictionary) -> void:
	var src: Variant = rec.get("source", null)
	if not (src is Dictionary):
		report.error("provenance", domain_name, key, "record has no source {authority, url, retrieved_at}")
		return
	if not ValidationUtil.same(src.get("authority", null), AUTHORITY):
		report.error("provenance", domain_name, key, "source.authority must be \"%s\", got %s" % [AUTHORITY, var_to_str(src.get("authority", null))])
	var url: Variant = src.get("url", null)
	if not _is_source_url(url):
		report.error("provenance", domain_name, key, "source.url %s is not a MeowDB MS Classic page, MeowDB data file or MeowDB API (%s)" % [
			var_to_str(url), ", ".join(PackedStringArray(SOURCE_URL_PREFIXES))])
	if not is_iso_timestamp(src.get("retrieved_at", null)):
		report.error("provenance", domain_name, key, "source.retrieved_at %s is not an ISO 8601 timestamp" % var_to_str(src.get("retrieved_at", null)))
	var declared := _external_urls(rec.get("external", null))
	var field_sources: Variant = rec.get("field_sources", null)
	if field_sources == null:
		return
	if not (field_sources is Dictionary):
		report.error("provenance", domain_name, key, "field_sources must be an object")
		return
	for field in field_sources:
		for u in _field_source_urls(field_sources[field]):
			if not u.begins_with(FIELD_SOURCE_PREFIX) and not declared.has(u):
				report.error("provenance", domain_name, key,
					"field_sources.%s cites %s, which is not on meowdb.com and has no external entry" % [field, u])


static func _is_source_url(url: Variant) -> bool:
	if not (url is String):
		return false
	for prefix in SOURCE_URL_PREFIXES:
		var p: String = prefix
		if url == p or String(url).begins_with(p if p.ends_with("/") else p + "/") \
				or String(url).begins_with(p + "?") or String(url).begins_with(p + "#"):
			return true
	return false


## Every URL a field_sources value cites: url, fallback_url, pages[].url, urls[] (strings or {url}).
static func _field_source_urls(v: Variant) -> PackedStringArray:
	var out: PackedStringArray = []
	if not (v is Dictionary):
		return out
	for k in ["url", "fallback_url"]:
		if v.get(k, null) is String:
			out.append(v[k])
	for list_key in ["pages", "urls"]:
		var list: Variant = v.get(list_key, null)
		if list is Array:
			for p in list:
				if p is String:
					out.append(p)
				elif p is Dictionary and p.get("url", null) is String:
					out.append(p.url)
	return out


static func _external_urls(external: Variant) -> Dictionary:
	var out := {}
	if external is Array:
		for e in external:
			if e is Dictionary and e.get("source_url", null) is String:
				out[e.source_url] = true
	return out


# --- root-level files ---------------------------------------------------------------------------------------

func _check_root_files() -> void:
	var root: Dictionary = db.canonical.get("", {})
	var keys: Array = root.keys()
	keys.sort()
	for k in keys:
		if str(k) == SOURCES_INDEX:
			continue
		report.error("provenance", "canonical", str(k),
			"game/data/canonical/%s.json is not in a domain folder, so no id, provenance or index check covers it; canonical records live at <domain>/<id>.json (adaptation values belong in game/data/misostory)" % k)


# --- canonical_sources.json ---------------------------------------------------------------------------------

## Recomputes what build_sources_index.mjs writes for each record and compares it with the shipped index.
func _check_sources_index() -> void:
	var index: Variant = db.canonical.get("", {}).get(SOURCES_INDEX, null)
	if not (index is Dictionary):
		report.error("sources_index", SOURCES_INDEX, SOURCES_INDEX, "game/data/canonical/canonical_sources.json is missing or not an object; %s" % REBUILD_HINT)
		return
	var rows: Variant = index.get("records", null)
	if not (rows is Array):
		report.error("sources_index", SOURCES_INDEX, SOURCES_INDEX, "canonical_sources.json has no records array; %s" % REBUILD_HINT)
		return
	var listed := {}  # "domain/id" -> row
	for row in rows:
		if not (row is Dictionary):
			report.error("sources_index", SOURCES_INDEX, SOURCES_INDEX, "a records entry is not an object")
			continue
		var k := "%s/%s" % [str(row.get("domain", "")), str(row.get("id", ""))]
		if listed.has(k):
			report.error("sources_index", SOURCES_INDEX, k, "listed twice; %s" % REBUILD_HINT)
		listed[k] = row
	var all_urls := {}
	var record_count := 0
	var external_count := 0
	for domain_name in ValidationUtil.canonical_domains(db):
		for key in db.ids(domain_name):
			if "/" in key:
				continue  # the index builder only reads top-level files; nested records are reported below
			record_count += 1
			var rec: Dictionary = db.get_entity(domain_name, key)
			var expected := _expected_row(domain_name, key, rec)
			external_count += int(expected.external_count)
			for u in expected.urls:
				all_urls[u] = true
			var k := "%s/%s" % [domain_name, str(expected.id)]
			if not listed.has(k):
				report.error("sources_index", SOURCES_INDEX, k, "record is not in canonical_sources.json; %s" % REBUILD_HINT)
				continue
			_compare_row(k, listed[k], expected)
			listed.erase(k)
	for domain_name in ValidationUtil.canonical_domains(db):
		for key in db.ids(domain_name):
			if "/" in key:
				report.error("sources_index", domain_name, key, "nested canonical folders are not indexed by build_sources_index.mjs; keep one record per file at <domain>/<id>.json")
	for k in listed:
		report.error("sources_index", SOURCES_INDEX, k, "lists a record that no longer exists; %s" % REBUILD_HINT)
	var totals: Variant = index.get("totals", null)
	if not (totals is Dictionary):
		report.error("sources_index", SOURCES_INDEX, SOURCES_INDEX, "canonical_sources.json has no totals; %s" % REBUILD_HINT)
		return
	_compare_total(totals, "records", record_count)
	if ValidationUtil.is_number(totals.get("records", null)) and int(totals.records) != rows.size():
		report.error("sources_index", SOURCES_INDEX, SOURCES_INDEX, "totals.records is %d but the records array lists %d; %s" % [
			int(totals.records), rows.size(), REBUILD_HINT])
	_compare_total(totals, "external_values", external_count)
	_compare_total(totals, "distinct_source_urls", all_urls.size())


func _expected_row(domain_name: String, key: String, rec: Dictionary) -> Dictionary:
	var src: Dictionary = rec.get("source", {}) if rec.get("source", null) is Dictionary else {}
	var extra := {}
	var fs: Variant = rec.get("field_sources", {})
	if fs is Dictionary:
		for f in fs:
			var v: Variant = fs[f]
			if v is Dictionary:
				if v.get("url", null) is String and v.url != "":
					extra[v.url] = true
				if v.get("pages", null) is Array:
					for p in v.pages:
						if p is Dictionary and p.get("url", null) is String and p.url != "":
							extra[p.url] = true
	var urls := extra.duplicate()
	if src.get("url", null) is String and src.url != "":
		urls[src.url] = true
	var external: Variant = rec.get("external", [])
	# The builder writes external as [{field, source_url, verified: !!e.verified}] (JSON drops undefined fields).
	var external_rows: Array = []
	if external is Array:
		for e in external:
			var ed: Dictionary = e if e is Dictionary else {}
			external_rows.append({"field": ed.get("field", null), "source_url": ed.get("source_url", null),
				"verified": _js_truthy(ed.get("verified", null))})
	var id_value: Variant = rec.get("id", null)
	return {
		"id": str(id_value) if id_value != null else key,
		"name": rec.get("name", null),
		"file": "res://data/canonical/%s/%s.json" % [domain_name, key],
		"authority": src.get("authority", null),
		"url": src.get("url", null),
		"retrieved_at": src.get("retrieved_at", null),
		"field_source_urls": extra.keys(),
		"external_count": external_rows.size(),
		"external": external_rows,
		"gap_count": rec.get("gaps", []).size() if rec.get("gaps", null) is Array else 0,
		"discrepancy_count": rec.get("discrepancies", []).size() if rec.get("discrepancies", null) is Array else 0,
		"urls": urls.keys(),
	}


func _compare_row(k: String, row: Dictionary, expected: Dictionary) -> void:
	var stale: PackedStringArray = []
	for field in ["name", "file", "authority", "url", "retrieved_at"]:
		if not ValidationUtil.same(row.get(field, null), expected[field]):
			stale.append(field)
	var listed_urls := {}
	if row.get("field_source_urls", null) is Array:
		for u in row.field_source_urls:
			listed_urls[str(u)] = true
	var expected_urls := {}
	for u in expected.field_source_urls:
		expected_urls[str(u)] = true
	if listed_urls.size() != expected_urls.size() or not listed_urls.has_all(expected_urls.keys()):
		stale.append("field_source_urls")
	if not _same_external(row.get("external", null), expected.external):
		stale.append("external")
	for field in ["gap_count", "discrepancy_count"]:
		var have: Variant = row.get(field, null)
		if not (have is float or have is int) or int(have) != int(expected[field]):
			stale.append(field)
	if not stale.is_empty():
		report.error("sources_index", SOURCES_INDEX, k, "entry is stale (%s differ from the record); %s" % [", ".join(stale), REBUILD_HINT])


## The index row's external list matches the record's, entry by entry (field, source_url, verified).
static func _same_external(listed: Variant, expected: Array) -> bool:
	if not (listed is Array) or listed.size() != expected.size():
		return false
	for i in expected.size():
		var have: Variant = listed[i]
		if not (have is Dictionary):
			return false
		for field in ["field", "source_url", "verified"]:
			if not ValidationUtil.same(have.get(field, null), expected[i][field]):
				return false
	return true


## JavaScript truthiness, for the values the builder converts with !!.
static func _js_truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return float(v) != 0.0 and not is_nan(float(v))
		TYPE_STRING:
			return String(v) != ""
	return true


func _compare_total(totals: Dictionary, field: String, expected: int) -> void:
	var have: Variant = totals.get(field, null)
	if not (have is float or have is int) or int(have) != expected:
		report.error("sources_index", SOURCES_INDEX, SOURCES_INDEX, "totals.%s is %s but the data has %d; %s" % [
			field, var_to_str(have), expected, REBUILD_HINT])


