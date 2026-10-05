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
##   provenance (v2, per property)  a record-level `provenance` block {<property>: source object} names a registered
##                authority allowed to supply that property, with the URL, read_at, capture and decision rules of
##                ProvenanceAuthorities.REGISTRY (check_source_object; contract C7). Records without the block are
##                checked exactly as before (v1). Schema v2 drop records' per-entry sources go through the same check
##                (DropRecordChecks)
##   capture      every `capture` key, at any depth, names an existing file under tools/<site>/captures/ (the dated,
##                hand-read capture a value came from)
##   sources_index  canonical_sources.json lists every record exactly as tools/meowdb/build_sources_index.mjs would
##                write it today (same files, URLs, external entries, capture files, per-property authorities and
##                counts), so "where did this value come from?" stays answerable
##   root files   game/data/canonical/ holds only domain folders plus canonical_sources.json: a loose JSON file there
##                has no domain, so no id, provenance or index check would ever see it
##
## Options (DataValidator passes its own): `capture_files` (Dictionary path -> true) replaces the disk lookup for
## captures (tests); `repo_root` (String) is where tools/ lives (default: the folder above res://, as in the repository;
## scripts/test.sh and scripts/validate_data.sh mirror tools/*/captures next to an ISOLATE copy).

const AUTHORITY := ProvenanceAuthorities.MEOWDB
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
var options: Dictionary
var _iso := RegEx.new()
var _capture_path := RegEx.new()
var _decision_id := RegEx.new()
var _capture_exists: Dictionary = {}  # path -> bool (disk lookups, cached per run)


func _init(content: ContentDB, into: ValidationReport, opts: Dictionary = {}) -> void:
	db = content
	report = into
	options = opts
	_iso.compile(ISO_8601)
	_capture_path.compile(ProvenanceAuthorities.CAPTURE_PATH)
	_decision_id.compile(ProvenanceAuthorities.DECISION_ID)


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
			check_provenance_block(domain_name, key, rec.get("provenance", null), drop_owner_kind(domain_name, rec))
			check_capture_paths(domain_name, key, rec)
	_check_root_files()
	_check_sources_index()


## The drop-owner kind of a drops record ("monster" / "breakable"), else "".
static func drop_owner_kind(domain_name: String, rec: Dictionary) -> String:
	if domain_name != "drops" or not (rec.get("owner", null) is Dictionary):
		return ""
	var kind: Variant = rec.owner.get("kind", null)
	return kind if kind is String else ""


# --- per-property provenance (contract C7) ------------------------------------------------------------------

## Checks a record-level `provenance` block: {<property>: source object}. Absent (null) is fine: the record's `source`
## then covers every value, as in v1. `owner_kind` is the drop-owner kind for drops records ("" elsewhere).
func check_provenance_block(domain_label: String, id: String, block: Variant, owner_kind: String = "") -> void:
	if block == null:
		return
	if not (block is Dictionary):
		report.error("provenance", domain_label, id, "provenance must be an object {<property>: {authority, url, read_at, capture, ...}}")
		return
	for property in block:
		check_source_object(domain_label, id, str(property), block[property], "provenance.%s" % str(property), owner_kind)


## Checks one source object for `property` against ProvenanceAuthorities.REGISTRY and reports each problem as a
## "provenance" error naming `where` (e.g. "provenance.membership", "entries[2] 'wooden-buckler'.chance_source").
## A source object is {authority, url | urls, read_at (MeowDB: or retrieved_at), capture, decision, ...}; the rules
## per authority are in the registry. The capture file's existence is checked by check_capture_paths (once per path).
## Returns true when the object passed.
func check_source_object(domain_label: String, id: String, property: String, src: Variant, where: String,
		owner_kind: String = "") -> bool:
	report.count("provenance_sources_checked")
	var problems := source_object_problems(property, src, owner_kind)
	for p in problems:
		report.error("provenance", domain_label, id, "%s: %s" % [where, p])
	return problems.is_empty()


## The problems check_source_object would report (empty when the object is valid).
func source_object_problems(property: String, src: Variant, owner_kind: String = "") -> PackedStringArray:
	var out: PackedStringArray = []
	if not (src is Dictionary):
		out.append("must be an object {authority, url, read_at, capture, ...}, got %s" % var_to_str(src))
		return out
	var authority: Variant = src.get("authority", null)
	if not ProvenanceAuthorities.has(authority):
		out.append("authority %s is not registered (registered: %s)" % [var_to_str(authority), ProvenanceAuthorities.names_text()])
		return out
	var rule := ProvenanceAuthorities.rule(authority)
	if not ProvenanceAuthorities.allows(authority, property):
		out.append("%s may not supply '%s' (it may supply: %s)" % [authority, property, ProvenanceAuthorities.allowed_text(authority)])
	var kinds: Array = rule.get("owner_kinds", [])
	if owner_kind != "" and not kinds.is_empty() and not (owner_kind in kinds):
		out.append("%s does not describe %s drop owners (only %s)" % [authority, owner_kind, ", ".join(PackedStringArray(kinds))])
	# URLs: `url`, or a non-empty `urls` list (a value read from several pages of one site).
	var urls: Array = []
	if src.has("url") and src.url != null:
		urls.append(src.url)
	if src.has("urls"):
		if src.urls is Array and not src.urls.is_empty():
			urls.append_array(src.urls)
		else:
			out.append("urls must be a non-empty list of URLs")
	var prefixes: Array = rule.get("url_prefixes", [])
	if not prefixes.is_empty():
		if urls.is_empty():
			out.append("%s needs a url (%s)" % [authority, ", ".join(PackedStringArray(prefixes))])
		for u in urls:
			if not ProvenanceAuthorities.url_allowed(authority, u):
				out.append("url %s is not a %s page (%s)" % [var_to_str(u), authority, ", ".join(PackedStringArray(prefixes))])
	# read_at: when the value was read (MeowDB's cache stamp may be given as retrieved_at).
	var read_at: Variant = src.get("read_at", null)
	if read_at == null and authority == ProvenanceAuthorities.MEOWDB:
		read_at = src.get("retrieved_at", null)
	if (rule.get("read_at", false) or read_at != null) and not is_iso_timestamp(read_at):
		out.append("needs read_at, an ISO 8601 timestamp with a zone (got %s)" % var_to_str(read_at))
	if rule.get("capture", false) and not ValidationUtil.non_empty(src.get("capture", null)):
		out.append("%s values need capture: the dated file under tools/<site>/captures/ they were read from" % authority)
	var decision: Variant = src.get("decision", null)
	if (rule.get("decision", false) or decision != null) and not is_decision_ref(decision):
		out.append("needs decision: an owner decision id such as D3-5 (docs/ITERATION_LOG.md) or the Iteration Three brief (got %s)" % var_to_str(decision))
	return out


## True for a decision reference: a string naming an ITERATION_LOG decision id ("D3-5") or the Iteration Three brief.
func is_decision_ref(v: Variant) -> bool:
	return v is String and (_decision_id.search(v) != null or String(v).contains(ProvenanceAuthorities.BRIEF))


## Every `capture` key at any depth of `node` must name an existing file under tools/<site>/captures/.
func check_capture_paths(domain_label: String, id: String, node: Variant, path: String = "") -> void:
	if node is Dictionary:
		for k in node:
			var key := str(k)
			var child := key if path == "" else "%s.%s" % [path, key]
			if key == "capture":
				_check_capture_path(domain_label, id, node[k], child)
			else:
				check_capture_paths(domain_label, id, node[k], child)
	elif node is Array:
		for e in node:
			check_capture_paths(domain_label, id, e, path + "[]")


func _check_capture_path(domain_label: String, id: String, value: Variant, where: String) -> void:
	report.count("capture_paths_checked")
	if not (value is String) or _capture_path.search(value) == null or ".." in String(value).split("/") \
			or "." in String(value).split("/"):
		report.error("provenance", domain_label, id,
			"%s %s is not a capture path (repo-relative, under tools/<site>/captures/, forward slashes)" % [where, var_to_str(value)])
		return
	if not capture_exists(value):
		report.error("provenance", domain_label, id, "%s names %s, which does not exist (looked under %s)" % [
			where, value, "the injected capture_files" if options.get("capture_files", null) is Dictionary else repo_root()])


## True when the capture file exists (options.capture_files when given, else the disk under repo_root()).
func capture_exists(capture: String) -> bool:
	var injected: Variant = options.get("capture_files", null)
	if injected is Dictionary:
		return injected.has(capture)
	if not _capture_exists.has(capture):
		_capture_exists[capture] = FileAccess.file_exists(repo_root().path_join(capture))
	return _capture_exists[capture]


## The repository root that holds tools/ (options.repo_root, else the folder above res://).
func repo_root() -> String:
	var root: Variant = options.get("repo_root", null)
	if root is String and root != "":
		return root
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path()


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
	for domain_name in ValidationUtil.canonical_domains(db):
		for key in db.ids(domain_name):
			if "/" in key:
				continue  # the index builder only reads top-level files; nested records are reported below
			var rec: Dictionary = db.get_entity(domain_name, key)
			var expected := _expected_row(domain_name, key, rec)
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
	var expected_totals := index_totals()
	_compare_total(totals, "records", int(expected_totals.records))
	if ValidationUtil.is_number(totals.get("records", null)) and int(totals.records) != rows.size():
		report.error("sources_index", SOURCES_INDEX, SOURCES_INDEX, "totals.records is %d but the records array lists %d; %s" % [
			int(totals.records), rows.size(), REBUILD_HINT])
	_compare_total(totals, "external_values", int(expected_totals.external_values))
	_compare_total(totals, "distinct_source_urls", int(expected_totals.distinct_source_urls))
	_compare_total(totals, "capture_files", int(expected_totals.capture_files))


## The canonical_sources.json row tools/meowdb/build_sources_index.mjs would write for a record (tests use it to keep
## the index of a mutated ContentDB current).
func index_row(domain_name: String, key: String, rec: Dictionary) -> Dictionary:
	var e := _expected_row(domain_name, key, rec)
	var urls: Array = e.field_source_urls.duplicate()
	urls.sort()
	var row := {"domain": domain_name, "id": e.id, "name": e.name, "file": e.file, "authority": e.authority, "url": e.url,
		"retrieved_at": e.retrieved_at, "field_source_urls": urls, "external": e.external, "gap_count": e.gap_count,
		"discrepancy_count": e.discrepancy_count}
	if not e.capture_files.is_empty():
		row["capture_files"] = e.capture_files
	if not e.property_sources.is_empty():
		row["property_sources"] = e.property_sources
	return row


## The totals block build_sources_index.mjs would write for the loaded data:
## {records, distinct_source_urls, external_values, capture_files}.
func index_totals() -> Dictionary:
	var all_urls := {}
	var captures := {}
	var record_count := 0
	var external_count := 0
	for domain_name in ValidationUtil.canonical_domains(db):
		for key in db.ids(domain_name):
			if "/" in key:
				continue
			record_count += 1
			var expected := _expected_row(domain_name, key, db.get_entity(domain_name, key))
			external_count += int(expected.external_count)
			for u in expected.urls:
				all_urls[u] = true
			for c in expected.capture_files:
				captures[c] = true
	return {"records": record_count, "distinct_source_urls": all_urls.size(), "external_values": external_count,
		"capture_files": captures.size()}


## [[property, source object], ...] in a record: its `provenance` block, then (schema v2 drop records) each entry's
## and the meso block's source keys (ProvenanceAuthorities.SOURCE_PROPERTIES). Mirrors build_sources_index.mjs.
static func source_objects(domain_name: String, rec: Dictionary) -> Array:
	var out: Array = []
	var prov: Variant = rec.get("provenance", null)
	if prov is Dictionary:
		for p in prov:
			out.append([str(p), prov[p]])
	if domain_name == "drops" and ValidationUtil.same(rec.get("schema_version", null), 2):
		var entry_keys: Dictionary = ProvenanceAuthorities.SOURCE_PROPERTIES.entries
		for e in ValidationUtil.as_array(rec.get("entries", [])):
			if e is Dictionary:
				for k in entry_keys:
					if e.get(k, null) is Dictionary:
						out.append([entry_keys[k], e[k]])
		var meso: Variant = rec.get("meso", null)
		if meso is Dictionary:
			var meso_keys: Dictionary = ProvenanceAuthorities.SOURCE_PROPERTIES.meso
			for k in meso_keys:
				if meso.get(k, null) is Dictionary:
					out.append([meso_keys[k], meso[k]])
	return out


## {property: {authorities: [sorted], urls: [sorted]}} over source_objects() (sorted keys), as the builder writes it.
static func _property_sources(domain_name: String, rec: Dictionary) -> Dictionary:
	var acc := {}
	for pair in source_objects(domain_name, rec):
		var s: Variant = pair[1]
		if not (s is Dictionary):
			continue
		var p: String = pair[0]
		if not acc.has(p):
			acc[p] = {"authorities": {}, "urls": {}}
		if ValidationUtil.non_empty(s.get("authority", null)):
			acc[p].authorities[s.authority] = true
		if s.get("url", null) is String and s.url != "":
			acc[p].urls[s.url] = true
		for u in ValidationUtil.as_array(s.get("urls", null)):
			if u is String and u != "":
				acc[p].urls[u] = true
	var keys: Array = acc.keys()
	keys.sort()
	var out := {}
	for p in keys:
		var authorities: Array = acc[p].authorities.keys()
		authorities.sort()
		var urls: Array = acc[p].urls.keys()
		urls.sort()
		out[p] = {"authorities": authorities, "urls": urls}
	return out


## Every string under a "capture" key at any depth (sorted), as the builder collects them.
static func _capture_files(node: Variant) -> Array:
	var found := {}
	_collect_captures(node, found)
	var keys: Array = found.keys()
	keys.sort()
	return keys


static func _collect_captures(node: Variant, out: Dictionary) -> void:
	if node is Dictionary:
		for k in node:
			if str(k) == "capture" and node[k] is String:
				out[node[k]] = true
			else:
				_collect_captures(node[k], out)
	elif node is Array:
		for e in node:
			_collect_captures(e, out)


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
	var property_sources := _property_sources(domain_name, rec)
	for p in property_sources:
		for u in property_sources[p].urls:
			urls[u] = true
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
		"capture_files": _capture_files(rec),
		"property_sources": property_sources,
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
	# Written only when non-empty, so an absent key means "none".
	if not _same_string_set(row.get("capture_files", []), expected.capture_files):
		stale.append("capture_files")
	if not _same_property_sources(row.get("property_sources", {}), expected.property_sources):
		stale.append("property_sources")
	if not stale.is_empty():
		report.error("sources_index", SOURCES_INDEX, k, "entry is stale (%s differ from the record); %s" % [", ".join(stale), REBUILD_HINT])


## True when `listed` is an Array holding exactly the strings of `expected` (order ignored).
static func _same_string_set(listed: Variant, expected: Array) -> bool:
	if not (listed is Array) or listed.size() != expected.size():
		return false
	var have := {}
	for v in listed:
		if not (v is String):
			return false
		have[v] = true
	return have.size() == expected.size() and have.has_all(expected)


## The index row's property_sources equal the record's: same properties, authorities and URLs.
static func _same_property_sources(listed: Variant, expected: Dictionary) -> bool:
	if not (listed is Dictionary) or listed.size() != expected.size():
		return false
	for p in expected:
		var row: Variant = listed.get(p, null)
		if not (row is Dictionary):
			return false
		if not _same_string_set(row.get("authorities", null), expected[p].authorities) \
				or not _same_string_set(row.get("urls", null), expected[p].urls):
			return false
	return true


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


