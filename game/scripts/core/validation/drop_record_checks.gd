class_name DropRecordChecks
extends RefCounted
## Schema v2 canonical drop records (Iteration Three contract C1, docs/runtime/ITERATION_THREE_CONTRACTS.md): drop
## membership from one authority, chances from another, each value with its own source. Records without
## schema_version (v1: MeowDB community lists, chance null) are left to the v1 checks exactly as before.
##
##   drop_record  the C1 shape and the probability rules below
##   provenance   every per-entry and meso source object, through ProvenanceChecks.check_source_object and the authority
##                registry (ProvenanceAuthorities): KuroDB only for probabilities, Hidden Street only for membership
##                and meso amounts, every non-MeowDB value with url + read_at + capture
## Item and quest references (entries[].item_id, quest_gate.quest_id) are resolved by the ReferenceChecks sweep, which
## skips a null item_id (an unresolved member).
##
## Per entry:
##   - key (unique) and name are non-empty strings; item_resolution.state is one of RESOLUTION_STATES and its method
##     one of RESOLUTION_METHODS; item_id is a string exactly when the state is "resolved" (and the method is not
##     "none"); no two entries resolve to the same item
##   - membership_source is a source object for "membership" whose authority is the record's membership_authority and
##     whose raw_value names the entry; an entry may not also be an excluded_kuro_only row (KuroDB never adds members)
##   - chance_state "resolved": probability is a number in [0, 1]; chance_source is a source object for "probability"
##     whose normalized_probability equals the probability and re-derives from its raw_value: format "percent_base"
##     ("<p>% base", p / 100, never a meso row) or "reactor_chance_value" ("Chance value N", 1 / N, with a non-empty
##     interpretation); quantity is {min, max} whole numbers with 1 <= min <= max
##   - chance_state "unresolved": probability is null (the entry never rolls); a chance_source or quantity, if given,
##     is still checked
##   - quest_gate is null or {quest_id, basis}
## pending_kuro_candidates (optional): {kuro_item_id, name, raw_value, member, read, reason}; the member is an entry key
## whose chance stays unresolved with no chance_source; never also an excluded_kuro_only row (_check_pending_candidates).
## Meso (null = the owner never drops mesos):
##   - amount_state "resolved": min/max whole numbers, 1 <= min <= max, an amount_source for "mesos.amount" whose
##     "Mesos: a[-b]" raw_value (when it has that form) gives the same numbers; "unresolved": min and max null
##   - chance_state as for entries, with chance_source for "mesos.probability" whose raw_value is a "Meso drop" row

const SCHEMA_VERSION := 2
const RESOLUTION_STATES := ["resolved", "ambiguous", "not_in_snapshot", "not_in_classic"]
const RESOLUTION_METHODS := ["exact", "normalized", "alias_with_evidence", "none"]
const CHANCE_STATES := ["resolved", "unresolved"]
const CHANCE_FORMATS := ["percent_base", "reactor_chance_value"]
## |normalized - parsed| above this is a conversion error (a truncation, a 1/N vs N% mix-up, a /100 missed).
const PROBABILITY_EPSILON := 1e-12

var db: ContentDB
var report: ValidationReport
var provenance: ProvenanceChecks
var _percent := RegEx.new()
var _reactor := RegEx.new()
var _meso_amount := RegEx.new()


func _init(content: ContentDB, into: ValidationReport, provenance_checks: ProvenanceChecks) -> void:
	db = content
	report = into
	provenance = provenance_checks
	_percent.compile("^\\s*(\\d+(?:\\.\\d+)?)\\s*%\\s*base\\b")
	_reactor.compile("^\\s*Chance value\\s+(\\d+)\\s*(?:\\||$)")
	_meso_amount.compile("^\\s*Mesos:\\s*(\\d+)(?:\\s*-\\s*(\\d+))?(?:\\s|$)")


## v2 when schema_version is 2; v1 when it is absent (or 1).
static func is_v2(rec: Dictionary) -> bool:
	return ValidationUtil.same(rec.get("schema_version", null), SCHEMA_VERSION)


func run() -> void:
	for id in db.ids("drops"):
		var rec: Dictionary = db.drop_table(id)
		var version: Variant = rec.get("schema_version", null)
		if version == null or ValidationUtil.same(version, 1):
			continue
		if not is_v2(rec):
			report.error("drop_record", "drops", id, "schema_version must be %d (contract C1) or absent (v1), got %s" % [SCHEMA_VERSION, var_to_str(version)])
			continue
		report.count("drop_records_v2_checked")
		check_record(id, rec)


func check_record(id: String, rec: Dictionary) -> void:
	var owner_kind := ProvenanceChecks.drop_owner_kind("drops", rec)
	var membership: Variant = rec.get("membership_authority", null)
	if not ProvenanceAuthorities.has(membership):
		report.error("provenance", "drops", id, "membership_authority %s is not a registered authority (%s)" % [
			var_to_str(membership), ProvenanceAuthorities.names_text()])
		membership = null
	elif not ProvenanceAuthorities.allows(membership, "membership"):
		report.error("provenance", "drops", id, "membership_authority %s may not supply 'membership' (it may supply: %s)" % [
			membership, ProvenanceAuthorities.allowed_text(membership)])
	var excluded := _excluded_names(id, rec.get("excluded_kuro_only", null))
	var keys := {}
	var item_ids := {}
	var by_key := {}
	var entries: Array = ValidationUtil.as_array(rec.get("entries", null))
	for i in entries.size():
		var e: Variant = entries[i]
		if not (e is Dictionary):
			report.error("drop_record", "drops", id, "entries[%d] is not an object" % i)
			continue
		report.count("drop_entries_v2_checked")
		var where := "entries[%d] '%s'" % [i, str(e.get("key", e.get("name", "?")))]
		_check_entry(id, e, where, membership, owner_kind, excluded)
		var key: Variant = e.get("key", null)
		if key is String:
			if keys.has(key):
				report.error("drop_record", "drops", id, "%s: key '%s' is used twice" % [where, key])
			keys[key] = true
			by_key[key] = e
		var item_id: Variant = e.get("item_id", null)
		if item_id is String:
			if item_ids.has(item_id):
				report.error("drop_record", "drops", id, "%s: item %s is also entry %s (one item, one roll)" % [where, item_id, item_ids[item_id]])
			else:
				item_ids[item_id] = where
	_check_pending_candidates(id, rec.get("pending_kuro_candidates", null), by_key, rec.get("excluded_kuro_only", null))
	var meso: Variant = rec.get("meso", null)
	if meso != null:
		if meso is Dictionary:
			_check_meso(id, meso, owner_kind)
		else:
			report.error("drop_record", "drops", id, "meso must be an object or null (null = the owner never drops mesos)")


# --- entries ------------------------------------------------------------------------------------------------

func _check_entry(id: String, e: Dictionary, where: String, membership: Variant, owner_kind: String, excluded: Dictionary) -> void:
	for field in ["key", "name"]:
		if not ValidationUtil.non_empty(e.get(field, null)):
			report.error("drop_record", "drops", id, "%s: %s must be a non-empty string" % [where, field])
	var entry_name: String = e.name if e.get("name", null) is String else ""
	_check_resolution(id, e, where)
	# Membership: who says this item drops at all.
	var ms: Variant = e.get("membership_source", null)
	if not (ms is Dictionary):
		report.error("drop_record", "drops", id, "%s: membership_source is missing (every member names the source that lists it)" % where)
	else:
		provenance.check_source_object("drops", id, "membership", ms, where + ".membership_source", owner_kind)
		if membership is String and ProvenanceAuthorities.has(ms.get("authority", null)) and ms.authority != membership:
			report.error("drop_record", "drops", id, "%s: membership_source.authority %s differs from the record's membership_authority %s" % [
				where, ms.authority, membership])
		var raw: Variant = ms.get("raw_value", null)
		if not ValidationUtil.non_empty(raw):
			report.error("drop_record", "drops", id, "%s: membership_source.raw_value must be the membership source's text" % where)
		elif entry_name != "" and not String(raw).contains(entry_name):
			report.error("drop_record", "drops", id, "%s: membership_source.raw_value %s does not name '%s' (a member is read from its membership source)" % [
				where, var_to_str(raw), entry_name])
	if entry_name != "" and excluded.has(_name_key(entry_name)):
		report.error("drop_record", "drops", id, "%s: '%s' is also an excluded_kuro_only row; KuroDB never adds a member (decision D3-6)" % [where, entry_name])
	# Chance.
	var state: Variant = e.get("chance_state", null)
	var p: Variant = e.get("probability", null)
	var cs: Variant = e.get("chance_source", null)
	if not (state is String) or not (state in CHANCE_STATES):
		report.error("drop_record", "drops", id, "%s: chance_state must be one of %s, got %s" % [where, str(CHANCE_STATES), var_to_str(state)])
	elif state == "resolved":
		_check_probability(id, where + ".probability", p)
		if not (cs is Dictionary):
			report.error("drop_record", "drops", id, "%s: chance_state is resolved but there is no chance_source (every resolved chance names its source)" % where)
		else:
			_check_chance_source(id, where + ".chance_source", cs, p, "probability", owner_kind, false)
		_check_quantity(id, where, e.get("quantity", null), true)
	else:
		if p != null:
			report.error("drop_record", "drops", id, "%s: probability must be null while chance_state is unresolved (an unresolved entry never rolls), got %s" % [where, var_to_str(p)])
		if cs is Dictionary:
			provenance.check_source_object("drops", id, "probability", cs, where + ".chance_source", owner_kind)
		elif cs != null:
			report.error("drop_record", "drops", id, "%s: chance_source must be an object or null" % where)
		if e.get("quantity", null) != null:
			_check_quantity(id, where, e.quantity, false)
	var gate: Variant = e.get("quest_gate", null)
	if gate != null:
		if not (gate is Dictionary) or not (gate.get("quest_id", null) is String) or not ValidationUtil.non_empty(gate.get("basis", null)):
			report.error("drop_record", "drops", id, "%s: quest_gate must be null or {quest_id, basis}" % where)
	if e.has("notes") and not (e.notes is Array):
		report.error("drop_record", "drops", id, "%s: notes must be a list" % where)


func _check_resolution(id: String, e: Dictionary, where: String) -> void:
	var res: Variant = e.get("item_resolution", null)
	var item_id: Variant = e.get("item_id", null)
	if not (res is Dictionary):
		report.error("drop_record", "drops", id, "%s: item_resolution {state, method, candidates, note} is missing" % where)
		return
	var state: Variant = res.get("state", null)
	var method: Variant = res.get("method", null)
	if not (state is String) or not (state in RESOLUTION_STATES):
		report.error("drop_record", "drops", id, "%s: item_resolution.state must be one of %s, got %s" % [where, str(RESOLUTION_STATES), var_to_str(state)])
	if not (method is String) or not (method in RESOLUTION_METHODS):
		report.error("drop_record", "drops", id, "%s: item_resolution.method must be one of %s, got %s" % [where, str(RESOLUTION_METHODS), var_to_str(method)])
	if res.has("candidates") and not (res.candidates is Array):
		report.error("drop_record", "drops", id, "%s: item_resolution.candidates must be a list of MeowDB ids" % where)
	if ValidationUtil.same(state, "resolved"):
		if item_id == null:
			report.error("drop_record", "drops", id, "%s: item_resolution.state is resolved but item_id is null" % where)
		if ValidationUtil.same(method, "none"):
			report.error("drop_record", "drops", id, "%s: a resolved item needs a match method other than none" % where)
	elif state is String and item_id != null:
		report.error("drop_record", "drops", id, "%s: item_id must be null while item_resolution.state is %s, got %s" % [where, state, var_to_str(item_id)])


## The chance source of a resolved entry or meso chance: a registered source object, normalized_probability ==
## probability, and the normalized value re-derived from raw_value by its format.
func _check_chance_source(id: String, where: String, cs: Dictionary, p: Variant, property: String, owner_kind: String,
		meso: bool) -> void:
	provenance.check_source_object("drops", id, property, cs, where, owner_kind)
	var normalized: Variant = cs.get("normalized_probability", null)
	if not ValidationUtil.is_number(normalized):
		report.error("drop_record", "drops", id, "%s: normalized_probability must be a number, got %s" % [where, var_to_str(normalized)])
		return
	if ValidationUtil.is_number(p) and absf(float(normalized) - float(p)) > PROBABILITY_EPSILON:
		report.error("drop_record", "drops", id, "%s: normalized_probability %s differs from the probability %s" % [where, str(normalized), str(p)])
	var raw: Variant = cs.get("raw_value", null)
	var format: Variant = cs.get("format", null)
	if not ValidationUtil.non_empty(raw):
		report.error("drop_record", "drops", id, "%s: raw_value must keep the source's text verbatim" % where)
		return
	var parsed: Variant = null
	var fmt: String = format if format is String else ""
	match fmt:
		"percent_base":
			var m := _percent.search(raw)
			if m == null:
				report.error("drop_record", "drops", id, "%s: raw_value %s is not a \"<p>%% base\" value (format percent_base)" % [where, var_to_str(raw)])
				return
			parsed = m.get_string(1).to_float() / 100.0
			var is_meso_row := String(raw).contains("Meso drop")
			if meso and not is_meso_row:
				report.error("drop_record", "drops", id, "%s: raw_value %s is an item row, not a \"Meso drop\" row" % [where, var_to_str(raw)])
			elif not meso and is_meso_row:
				report.error("drop_record", "drops", id, "%s: raw_value %s is a meso row, not an item row" % [where, var_to_str(raw)])
		"reactor_chance_value":
			var m := _reactor.search(raw)
			if m == null or m.get_string(1).to_int() < 1:
				report.error("drop_record", "drops", id, "%s: raw_value %s is not a \"Chance value N\" value with N >= 1 (format reactor_chance_value)" % [where, var_to_str(raw)])
				return
			parsed = 1.0 / float(m.get_string(1).to_int())
			if not ValidationUtil.non_empty(cs.get("interpretation", null)):
				report.error("drop_record", "drops", id, "%s: a reactor \"Chance value N\" read as 1/N is an interpretation; say so in interpretation (decision D3-7)" % where)
		_:
			report.error("drop_record", "drops", id, "%s: format must be one of %s, got %s" % [where, str(CHANCE_FORMATS), var_to_str(format)])
			return
	if absf(float(normalized) - float(parsed)) > PROBABILITY_EPSILON:
		report.error("drop_record", "drops", id, "%s: normalized_probability %s does not follow from raw_value %s (%s gives %s)" % [
			where, str(normalized), var_to_str(raw), format, str(parsed)])


func _check_probability(id: String, where: String, p: Variant) -> void:
	if not ValidationUtil.is_number(p) or is_nan(float(p)) or float(p) < 0.0 or float(p) > 1.0:
		report.error("drop_record", "drops", id, "%s must be a number in [0, 1] when the chance is resolved, got %s" % [where, var_to_str(p)])


func _check_quantity(id: String, where: String, q: Variant, required: bool) -> void:
	if q == null:
		if required:
			report.error("drop_record", "drops", id, "%s: a resolved entry needs quantity {min, max}" % where)
		return
	if not (q is Dictionary) or not _whole(q.get("min", null)) or not _whole(q.get("max", null)) \
			or float(q.min) < 1.0 or float(q.min) > float(q.max):
		report.error("drop_record", "drops", id, "%s: quantity must be {min, max} with whole numbers 1 <= min <= max, got %s" % [where, var_to_str(q)])


# --- meso ---------------------------------------------------------------------------------------------------

func _check_meso(id: String, meso: Dictionary, owner_kind: String) -> void:
	var state: Variant = meso.get("amount_state", null)
	var src: Variant = meso.get("amount_source", null)
	if not (state is String) or not (state in CHANCE_STATES):
		report.error("drop_record", "drops", id, "meso.amount_state must be one of %s, got %s" % [str(CHANCE_STATES), var_to_str(state)])
	elif state == "resolved":
		var lo: Variant = meso.get("min", null)
		var hi: Variant = meso.get("max", null)
		if not _whole(lo) or not _whole(hi) or float(lo) < 1.0 or float(lo) > float(hi):
			report.error("drop_record", "drops", id, "meso: a resolved amount needs whole numbers 1 <= min <= max, got min %s, max %s" % [var_to_str(lo), var_to_str(hi)])
		if not (src is Dictionary):
			report.error("drop_record", "drops", id, "meso: amount_state is resolved but there is no amount_source")
		else:
			provenance.check_source_object("drops", id, "mesos.amount", src, "meso.amount_source", owner_kind)
			var m := _meso_amount.search(str(src.get("raw_value", "")))
			if m != null and _whole(lo) and _whole(hi):
				var raw_lo := m.get_string(1).to_int()
				var raw_hi := m.get_string(2).to_int() if m.get_string(2) != "" else raw_lo
				if raw_lo != int(lo) or raw_hi != int(hi):
					report.error("drop_record", "drops", id, "meso: min %d, max %d differ from amount_source.raw_value %s" % [
						int(lo), int(hi), var_to_str(src.raw_value)])
	else:
		if meso.get("min", null) != null or meso.get("max", null) != null:
			report.error("drop_record", "drops", id, "meso: min and max must be null while amount_state is unresolved")
		if src is Dictionary:
			provenance.check_source_object("drops", id, "mesos.amount", src, "meso.amount_source", owner_kind)
	var cstate: Variant = meso.get("chance_state", null)
	var p: Variant = meso.get("probability", null)
	var cs: Variant = meso.get("chance_source", null)
	if not (cstate is String) or not (cstate in CHANCE_STATES):
		report.error("drop_record", "drops", id, "meso.chance_state must be one of %s, got %s" % [str(CHANCE_STATES), var_to_str(cstate)])
	elif cstate == "resolved":
		_check_probability(id, "meso.probability", p)
		if not (cs is Dictionary):
			report.error("drop_record", "drops", id, "meso: chance_state is resolved but there is no chance_source")
		else:
			_check_chance_source(id, "meso.chance_source", cs, p, "mesos.probability", owner_kind, true)
	else:
		if p != null:
			report.error("drop_record", "drops", id, "meso: probability must be null while chance_state is unresolved, got %s" % var_to_str(p))
		if cs is Dictionary:
			provenance.check_source_object("drops", id, "mesos.probability", cs, "meso.chance_source", owner_kind)


# --- helpers ------------------------------------------------------------------------------------------------

## pending_kuro_candidates (optional; absent = none): KuroDB rows that may be a member under another name, waiting for
## a hand read of their item page (decision D3-8). Each is {kuro_item_id, name, raw_value, member, read, reason} with
## non-empty strings; `member` is the key of an entry whose chance is unresolved and that has no chance_source (a
## pending row never rolls); the row is not also an excluded_kuro_only row, and no two pending rows are the same row.
func _check_pending_candidates(id: String, rows: Variant, by_key: Dictionary, excluded_rows: Variant) -> void:
	if rows == null:
		return
	if not (rows is Array):
		report.error("drop_record", "drops", id, "pending_kuro_candidates must be a list")
		return
	var excluded := {}
	for x in ValidationUtil.as_array(excluded_rows):
		if x is Dictionary:
			excluded["%s|%s" % [str(x.get("kuro_item_id", "")), str(x.get("name", ""))]] = true
	var seen := {}
	for i in rows.size():
		var r: Variant = rows[i]
		var ok: bool = r is Dictionary
		for field in ["kuro_item_id", "name", "raw_value", "member", "read", "reason"]:
			ok = ok and ValidationUtil.non_empty(r.get(field, null))
		if not ok:
			report.error("drop_record", "drops", id, "pending_kuro_candidates[%d] must be {kuro_item_id, name, raw_value, member, read, reason}" % i)
			continue
		var where := "pending_kuro_candidates[%d] %s (%s)" % [i, r.name, r.kuro_item_id]
		var key := "%s|%s" % [r.kuro_item_id, r.name]
		if seen.has(key):
			report.error("drop_record", "drops", id, "%s is listed twice" % where)
		seen[key] = true
		if excluded.has(key):
			report.error("drop_record", "drops", id, "%s is also an excluded_kuro_only row: a row is pending or KuroDB-only, not both" % where)
		var e: Variant = by_key.get(r.member, null)
		if not (e is Dictionary):
			report.error("drop_record", "drops", id, "%s names member '%s', which is no entry key" % [where, r.member])
		elif str(e.get("chance_state", "")) != "unresolved" or e.get("chance_source", null) != null:
			report.error("drop_record", "drops", id, "%s: its member '%s' must stay unresolved with no chance_source while the row is pending (decision D3-8)" % [where, r.member])


## Name keys of the excluded_kuro_only rows; checks their shape.
func _excluded_names(id: String, rows: Variant) -> Dictionary:
	var out := {}
	if rows == null:
		return out
	if not (rows is Array):
		report.error("drop_record", "drops", id, "excluded_kuro_only must be a list")
		return out
	for i in rows.size():
		var r: Variant = rows[i]
		var ok: bool = r is Dictionary
		for field in ["kuro_item_id", "name", "raw_value", "reason"]:
			ok = ok and ValidationUtil.non_empty(r.get(field, null))
		if not ok:
			report.error("drop_record", "drops", id, "excluded_kuro_only[%d] must be {kuro_item_id, name, raw_value, reason}" % i)
			continue
		out[_name_key(r.name)] = true
	return out


## Case and spacing-insensitive name key (enough to catch a KuroDB-only row re-added as a member).
static func _name_key(name: String) -> String:
	return " ".join(name.to_lower().replace(" : ", ": ").split(" ", false))


static func _whole(v: Variant) -> bool:
	return ValidationUtil.is_number(v) and float(v) == floorf(float(v))
