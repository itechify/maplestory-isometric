class_name DropRecordChecks
extends RefCounted
## Schema 3 canonical drop records (Iteration Three contract C1, docs/runtime/ITERATION_THREE_CONTRACTS.md; decisions
## D3-9, D3-11, D3-12): who drops what (MeowDB's community list), each member's item, rarity (Henesys.gg) and table
## category, its quest gate, and MeowDB's meso reports. Only sourced facts: a record holds no probability, quantity or
## made-up meso amount (those are the project owner's rules in game/data/misostory, read at runtime by DropRates).
##
##   drop_record  the C1 shape below
##   provenance   every per-entry and meso source object, through ProvenanceChecks.check_source_object and the authority
##                registry (ProvenanceAuthorities): MeowDB for membership and meso amounts, Henesys.gg only for rarity,
##                every non-MeowDB value with url + read_at + capture
## Item and quest references (entries[].item_id, quest_gate.quest_id) are resolved by the ReferenceChecks sweep, which
## skips a null item_id (an unresolved member). The policy against the captures, the item data and the rule files is
## DropChecks.
##
## Per record: schema_version 3; owner {kind: monster | breakable, id: the record id, name}; membership_authority is a
## registered authority allowed to supply "membership"; membership_list "Drops (MS Classic)"; no key anywhere in the
## record names a chance or quantity (NO_PROBABILITY_KEYS).
## Per entry:
##   - key (unique, the slug of the name) and name are non-empty strings
##   - item_resolution {state, method, candidates, evidence}: item_id is a string exactly when the state is "resolved";
##     "exact_name" lists only the item, "meowdb_drop_entry" lists two or more local items including the one chosen;
##     no two entries resolve to the same item
##   - membership_source: a source object for "membership" with the record's membership_authority, list, raw_value
##     "<name>\n<subtype>\n▲\n<up>\n▼\n<down>" naming the entry, and votes {up, down, score = up - down} matching it
##   - rarity: null (unresolved: the entry never drops) or {label: one of DropRates.RARITIES, source: a source object
##     for "rarity" whose row ends with the label}
##   - category_inputs {item_type, item_subtype, quest_gated, item}; chance_category null or one of DropRates.CATEGORIES
##   - quest_gate null or {quest_id, basis, decision: "D3-9", verified: false}
## Meso: a monster record's meso is {amount_state: "reported" | "not_reported", min, max, amount_source, gaps}; reported
## needs whole numbers 1 <= min <= max and an amount_source for "mesos.amount" whose "Mesos: a[-b] per kill" raw value
## (when it has that form) gives them; not_reported needs min, max and amount_source null. A breakable's meso is null.

const SCHEMA_VERSION := DropRates.SCHEMA_VERSION
const RESOLUTION_STATES := ["resolved", "ambiguous", "not_in_snapshot"]
const RESOLUTION_METHODS := ["exact_name", "meowdb_drop_entry", "none"]
const MESO_STATES := ["reported", "not_reported"]
const MEMBERSHIP_LIST := "Drops (MS Classic)"
const GATE_DECISION := "D3-9"
## Keys that would put a chance or quantity into canonical data (contract C1: the records hold sourced facts only).
const NO_PROBABILITY_KEYS := ["probability", "chance", "chance_source", "chance_state", "normalized_probability",
	"quantity", "rate", "drop_chance"]
## Subtrees whose text may mention chances (commentary).
const COMMENT_KEYS := ["notes", "gaps", "discrepancies", "reason", "note", "basis", "evidence"]

var db: ContentDB
var report: ValidationReport
var provenance: ProvenanceChecks
var _meso_amount := RegEx.new()


func _init(content: ContentDB, into: ValidationReport, provenance_checks: ProvenanceChecks) -> void:
	db = content
	report = into
	provenance = provenance_checks
	_meso_amount.compile("^\\s*Mesos:\\s*(\\d+)(?:\\s*-\\s*(\\d+))?\\s+per kill")


## True when the record is schema 3.
static func is_v3(rec: Dictionary) -> bool:
	return DropRates.is_v3_record(rec)


## The entry key the builder gives a name (tools/sources/parse.mjs entryKey): lower case, apostrophes dropped, every
## other run of non-alphanumerics one "-", trimmed.
static func entry_key(name: String) -> String:
	var s := name.to_lower().replace("'", "").replace("’", "")
	var out := ""
	var dash := false
	for ch in s:
		var c := ch.unicode_at(0)
		if (c >= 97 and c <= 122) or (c >= 48 and c <= 57):
			out += ch
			dash = false
		elif not dash:
			out += "-"
			dash = true
	return out.trim_prefix("-").trim_suffix("-")


func run() -> void:
	for id in db.ids("drops"):
		var rec: Dictionary = db.drop_table(id)
		if not is_v3(rec):
			report.error("drop_record", "drops", id, "schema_version must be %d (contract C1), got %s" % [SCHEMA_VERSION,
				var_to_str(rec.get("schema_version", null))])
			continue
		report.count("drop_records_checked")
		check_record(id, rec)


func check_record(id: String, rec: Dictionary) -> void:
	var owner_kind := ProvenanceChecks.drop_owner_kind("drops", rec)
	var owner: Variant = rec.get("owner", null)
	if not (owner is Dictionary) or not (owner_kind in ["monster", "breakable"]) or not ValidationUtil.same(owner.get("id", null), id) \
			or not ValidationUtil.non_empty(owner.get("name", null)):
		_error(id, "owner must be {kind: monster | breakable, id: \"%s\", name}" % id)
	var membership: Variant = rec.get("membership_authority", null)
	if not ProvenanceAuthorities.has(membership):
		report.error("provenance", "drops", id, "membership_authority %s is not a registered authority (%s)" % [
			var_to_str(membership), ProvenanceAuthorities.names_text()])
		membership = null
	elif not ProvenanceAuthorities.allows(membership, "membership"):
		report.error("provenance", "drops", id, "membership_authority %s may not supply 'membership' (it may supply: %s)" % [
			membership, ProvenanceAuthorities.allowed_text(membership)])
	if not ValidationUtil.same(rec.get("membership_list", null), MEMBERSHIP_LIST):
		_error(id, "membership_list must be \"%s\" (MeowDB's community list, decision D3-11), got %s" % [MEMBERSHIP_LIST,
			var_to_str(rec.get("membership_list", null))])
	_check_no_probability(id, rec, "")
	var keys := {}
	var item_ids := {}
	var entries: Array = ValidationUtil.as_array(rec.get("entries", null))
	if not (rec.get("entries", null) is Array):
		_error(id, "entries must be a list")
	for i in entries.size():
		var e: Variant = entries[i]
		if not (e is Dictionary):
			_error(id, "entries[%d] is not an object" % i)
			continue
		report.count("drop_entries_checked")
		var where := "entries[%d] '%s'" % [i, str(e.get("key", e.get("name", "?")))]
		_check_entry(id, e, where, membership, owner_kind)
		var key: Variant = e.get("key", null)
		if key is String:
			if keys.has(key):
				_error(id, "%s: key '%s' is used twice" % [where, key])
			keys[key] = true
		var item_id: Variant = e.get("item_id", null)
		if item_id is String:
			if item_ids.has(item_id):
				_error(id, "%s: item %s is also entry %s (one item, one roll)" % [where, item_id, item_ids[item_id]])
			else:
				item_ids[item_id] = where
	var meso: Variant = rec.get("meso", null)
	if owner_kind == "breakable":
		if meso != null:
			_error(id, "meso must be null for a breakable (MeowDB has no meso reports for breakables)")
	elif meso is Dictionary:
		_check_meso(id, meso, owner_kind)
	else:
		_error(id, "meso must be an object {amount_state, min, max, amount_source, gaps} for a monster")


# --- entries ------------------------------------------------------------------------------------------------

func _check_entry(id: String, e: Dictionary, where: String, membership: Variant, owner_kind: String) -> void:
	for field in ["key", "name"]:
		if not ValidationUtil.non_empty(e.get(field, null)):
			_error(id, "%s: %s must be a non-empty string" % [where, field])
	var entry_name: String = e.name if e.get("name", null) is String else ""
	if entry_name != "" and e.get("key", null) is String and e.key != entry_key(entry_name):
		_error(id, "%s: key must be the slug of the name, '%s'" % [where, entry_key(entry_name)])
	_check_resolution(id, e, where)
	# Membership: MeowDB's community list says this item drops.
	var ms: Variant = e.get("membership_source", null)
	if not (ms is Dictionary):
		_error(id, "%s: membership_source is missing (every member names the list that has it)" % where)
	else:
		provenance.check_source_object("drops", id, "membership", ms, where + ".membership_source", owner_kind)
		if membership is String and ProvenanceAuthorities.has(ms.get("authority", null)) and ms.authority != membership:
			_error(id, "%s: membership_source.authority %s differs from the record's membership_authority %s" % [where, ms.authority, membership])
		if not ValidationUtil.same(ms.get("list", null), MEMBERSHIP_LIST):
			_error(id, "%s: membership_source.list must be \"%s\"" % [where, MEMBERSHIP_LIST])
		var raw: Variant = ms.get("raw_value", null)
		var lines := String(raw).split("\n") if raw is String else PackedStringArray()
		if lines.size() != 6 or lines[2] != "▲" or lines[4] != "▼":
			_error(id, "%s: membership_source.raw_value must be the list's block \"name, subtype, ▲, up, ▼, down\", got %s" % [where, var_to_str(raw)])
		else:
			if entry_name != "" and lines[0] != entry_name:
				_error(id, "%s: membership_source.raw_value names %s, not '%s'" % [where, var_to_str(lines[0]), entry_name])
			var votes: Variant = ms.get("votes", null)
			if not (votes is Dictionary) or not _whole(votes.get("up", null)) or not _whole(votes.get("down", null)) \
					or not ValidationUtil.same(votes.get("score", null), float(votes.get("up", 0)) - float(votes.get("down", 0))) \
					or str(int(votes.get("up", -1))) != lines[3] or str(int(votes.get("down", -1))) != lines[5]:
				_error(id, "%s: membership_source.votes must be {up, down, score = up - down} as the raw value shows (%s up, %s down)" % [
					where, lines[3], lines[5]])
	# Rarity: Henesys.gg's label, or null (unresolved: never drops).
	var rarity: Variant = e.get("rarity", null)
	if rarity != null:
		if not (rarity is Dictionary) or not (str(rarity.get("label", "")) in DropRates.RARITIES):
			_error(id, "%s: rarity must be null or {label: one of %s, source}" % [where, str(DropRates.RARITIES)])
		else:
			var src: Variant = rarity.get("source", null)
			if not (src is Dictionary):
				_error(id, "%s: rarity.source is missing (the capture row the label was read from)" % where)
			else:
				provenance.check_source_object("drops", id, "rarity", src, where + ".rarity.source", owner_kind)
				var row := str(src.get("row", ""))
				var parts := row.split("  /  ")
				if row == "" or not String(parts[0]).strip_edges().ends_with("| " + str(rarity.label)):
					_error(id, "%s: rarity.source.row %s does not end with the label '%s'" % [where, var_to_str(src.get("row", null)), str(rarity.label)])
	# Category.
	var inputs: Variant = e.get("category_inputs", null)
	if not (inputs is Dictionary) or not inputs.has("item_type") or not inputs.has("item_subtype") or not (inputs.get("quest_gated", null) is bool):
		_error(id, "%s: category_inputs must be {item_type, item_subtype, quest_gated, item}" % where)
	var cat: Variant = e.get("chance_category", null)
	if cat != null and not (str(cat) in DropRates.CATEGORIES):
		_error(id, "%s: chance_category must be null or one of %s, got %s" % [where, str(DropRates.CATEGORIES), var_to_str(cat)])
	var gate: Variant = e.get("quest_gate", null)
	if gate != null:
		if not (gate is Dictionary) or not (gate.get("quest_id", null) is String) or not ValidationUtil.non_empty(gate.get("basis", null)):
			_error(id, "%s: quest_gate must be null or {quest_id, basis, decision, verified}" % where)
		else:
			if not ValidationUtil.same(gate.get("decision", null), GATE_DECISION):
				_error(id, "%s: quest_gate.decision must be \"%s\" (the quest-gate rule)" % [where, GATE_DECISION])
			if not ValidationUtil.same(gate.get("verified", null), false):
				_error(id, "%s: quest_gate is a MisoStory derivation (decision %s) and must say verified: false" % [where, GATE_DECISION])
	if e.has("notes") and not (e.notes is Array):
		_error(id, "%s: notes must be a list" % where)


func _check_resolution(id: String, e: Dictionary, where: String) -> void:
	var res: Variant = e.get("item_resolution", null)
	var item_id: Variant = e.get("item_id", null)
	if not (res is Dictionary):
		_error(id, "%s: item_resolution {state, method, candidates, evidence} is missing" % where)
		return
	var state: Variant = res.get("state", null)
	var method: Variant = res.get("method", null)
	var cands: Variant = res.get("candidates", null)
	if not (state is String) or not (state in RESOLUTION_STATES):
		_error(id, "%s: item_resolution.state must be one of %s, got %s" % [where, str(RESOLUTION_STATES), var_to_str(state)])
	if not (method is String) or not (method in RESOLUTION_METHODS):
		_error(id, "%s: item_resolution.method must be one of %s, got %s" % [where, str(RESOLUTION_METHODS), var_to_str(method)])
	if not (cands is Array):
		_error(id, "%s: item_resolution.candidates must be a list of MeowDB ids" % where)
		cands = []
	if not ValidationUtil.non_empty(res.get("evidence", null)):
		_error(id, "%s: item_resolution.evidence must say how the item was found" % where)
	if ValidationUtil.same(state, "resolved"):
		if not (item_id is String):
			_error(id, "%s: item_resolution.state is resolved but item_id is not an id" % where)
		elif ValidationUtil.same(method, "exact_name") and not ValidationUtil.same(cands, [item_id]):
			_error(id, "%s: exact_name means the one local item with the name, so candidates must be [\"%s\"]" % [where, item_id])
		elif ValidationUtil.same(method, "meowdb_drop_entry") and ((cands as Array).size() < 2 or not (item_id in cands)):
			_error(id, "%s: meowdb_drop_entry decides between two or more local items with the name; candidates must list them, %s among them" % [where, item_id])
		elif ValidationUtil.same(method, "none"):
			_error(id, "%s: a resolved item needs the method that found it" % where)
	elif state is String and item_id != null:
		_error(id, "%s: item_id must be null while item_resolution.state is %s, got %s" % [where, state, var_to_str(item_id)])


# --- meso ---------------------------------------------------------------------------------------------------

func _check_meso(id: String, meso: Dictionary, owner_kind: String) -> void:
	var state: Variant = meso.get("amount_state", null)
	var src: Variant = meso.get("amount_source", null)
	var lo: Variant = meso.get("min", null)
	var hi: Variant = meso.get("max", null)
	if not (state is String) or not (state in MESO_STATES):
		_error(id, "meso.amount_state must be one of %s, got %s" % [str(MESO_STATES), var_to_str(state)])
	elif state == "reported":
		if not _whole(lo) or not _whole(hi) or float(lo) < 1.0 or float(lo) > float(hi):
			_error(id, "meso: a reported amount needs whole numbers 1 <= min <= max, got min %s, max %s" % [var_to_str(lo), var_to_str(hi)])
		if not (src is Dictionary):
			_error(id, "meso: amount_state is reported but there is no amount_source (MeowDB's player report)")
		else:
			provenance.check_source_object("drops", id, "mesos.amount", src, "meso.amount_source", owner_kind)
			var m := _meso_amount.search(str(src.get("raw_value", "")))
			if m != null and _whole(lo) and _whole(hi):
				var raw_lo := m.get_string(1).to_int()
				var raw_hi := m.get_string(2).to_int() if m.get_string(2) != "" else raw_lo
				if raw_lo != int(lo) or raw_hi != int(hi):
					_error(id, "meso: min %d, max %d differ from amount_source.raw_value %s" % [int(lo), int(hi), var_to_str(src.raw_value)])
	else:
		if lo != null or hi != null or src != null:
			_error(id, "meso: min, max and amount_source must be null while amount_state is not_reported (the meso rule supplies the amount at runtime)")
	if not (meso.get("gaps", null) is Array):
		_error(id, "meso.gaps must be a list")


# --- helpers ------------------------------------------------------------------------------------------------

## Any key at any depth that would hold a chance or quantity (outside commentary) is an error: the chance table and the
## meso rule live in game/data/misostory, never in a canonical record.
func _check_no_probability(id: String, node: Variant, path: String) -> void:
	if node is Dictionary:
		for k in node:
			var key := str(k)
			if key in COMMENT_KEYS:
				continue
			var child := key if path == "" else "%s.%s" % [path, key]
			if key in NO_PROBABILITY_KEYS:
				_error(id, "%s: a canonical drop record holds no probability or quantity (contract C1; the chance table is data/misostory/drop_rates.json)" % child)
			_check_no_probability(id, node[k], child)
	elif node is Array:
		for i in node.size():
			_check_no_probability(id, node[i], "%s[%d]" % [path, i])


func _error(id: String, message: String) -> void:
	report.error("drop_record", "drops", id, message)


static func _whole(v: Variant) -> bool:
	return ValidationUtil.is_number(v) and not (v is bool) and float(v) == floorf(float(v))
