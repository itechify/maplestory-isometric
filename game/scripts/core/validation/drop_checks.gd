class_name DropChecks
extends RefCounted
## The drop policy over the shipped canonical drop records (Iteration Three brief "Drop Pass" and "Probability
## Handling"; contracts C1 and C2; decisions D3-3 to D3-9). DropRecordChecks checks each schema v2 record's shape and
## sources; these checks hold the records to the policy and re-read every raw value exactly (DropChance):
##
##   drop_policy (errors)
##     - every drop record is schema v2: a v1 record (MeowDB community lists) supplies no chance, so it cannot ship
##     - membership authority by owner kind: Hidden Street for monsters (D3-6), MeowDB MS Classic for breakables (D3-7)
##     - every resolved item chance and every meso chance comes from KuroDB; a meso amount from MeowDB or Hidden Street
##       (never MeowDB's report-form dropChancePct, which is not a chance)
##     - raw re-parse: normalized_probability and probability equal DropChance's exact reading of raw_value (p% -> p/100
##       from the digits as written, "Chance value N" -> 1/N), the conversion text matches, the quantity equals the
##       raw "Qty" (a reactor row has none: its quantity must be a labelled adaptation with verified: false), KuroDB's
##       "| Quest N" equals kuro_quest_condition, a meso row is a "Meso drop" row and an item row is not; meso min/max
##       equal the amount_source raw value
##     - bounds: every chance in [0, 1] (a resolved 0 is a warning: it never drops)
##     - a resolved item exists in the local items
##     - quest gates follow the C1 rule: an entry is gated exactly when its item is a quest item (MeowDB subtype "Quest
##       Item", or the membership source lists it so) that a Maple Island quest objective asks for, and the gate is
##       that quest; the gate says verified: false (a MisoStory derivation, D3-9)
##     - no KuroDB-only row (excluded_kuro_only) is also an entry's chance source
##     - an unresolved member whose item a Maple Island quest objective asks for is a progression blocker (brief
##       "Missing KuroDB Probability")
##   drop_unresolved (warnings): each member or meso value that never rolls because a source leaves it unresolved, so
##     unknown probabilities stay visible (brief "Missing KuroDB Probability"); an unresolved member whose MeowDB
##     candidate is now a local item asks for a crosswalk review

## Relative tolerance for "the stored number equals the exact reading" (JSON doubles vs an exact integer division).
const EPSILON := 1e-12
const MEMBERSHIP_BY_KIND := {"monster": ProvenanceAuthorities.HIDDEN_STREET, "breakable": ProvenanceAuthorities.MEOWDB}
const MESO_AMOUNT_AUTHORITIES := [ProvenanceAuthorities.MEOWDB, ProvenanceAuthorities.HIDDEN_STREET]
const QUEST_SUBTYPE := "Quest Item"

var db: ContentDB
var report: ValidationReport
var _quest_items: Dictionary = {}  # item id -> [quest ids whose objectives.item_collection asks for it]


func _init(content: ContentDB, into: ValidationReport) -> void:
	db = content
	report = into
	for qid in db.ids("quests"):
		var q: Dictionary = db.quest(qid)
		var region: Variant = q.get("region", "Maple Island")
		if region != null and str(region) != "Maple Island":
			continue
		var objectives: Variant = q.get("objectives", {})
		if not (objectives is Dictionary):
			continue
		for need in ValidationUtil.as_array(objectives.get("item_collection", [])):
			if need is Dictionary and need.get("item_id", null) != null:
				var id := str(need.item_id)
				if not _quest_items.has(id):
					_quest_items[id] = []
				if not (qid in _quest_items[id]):
					_quest_items[id].append(qid)


func run() -> void:
	for id in db.ids("drops"):
		var rec: Dictionary = db.drop_table(id)
		if not DropRecordChecks.is_v2(rec):
			_error(id, "not a schema v2 record (contract C1): a v1 record holds MeowDB's community lists and no chance, so it cannot supply drops")
			continue
		report.count("drop_policy_records_checked")
		check_record(id, rec)


func check_record(id: String, rec: Dictionary) -> void:
	var kind := ProvenanceChecks.drop_owner_kind("drops", rec)
	var want: Variant = MEMBERSHIP_BY_KIND.get(kind, null)
	if want != null and not ValidationUtil.same(rec.get("membership_authority", null), want):
		_error(id, "membership_authority must be %s for a %s (decisions D3-6, D3-7), got %s" % [want, kind,
			var_to_str(rec.get("membership_authority", null))])
	var claimed := {}
	for e in ValidationUtil.as_array(rec.get("entries", [])):
		if e is Dictionary:
			report.count("drop_policy_entries_checked")
			_check_entry(id, e)
			var cs: Variant = e.get("chance_source", null)
			if cs is Dictionary:
				claimed["%s|%s" % [str(cs.get("kuro_item_id", "")), str(cs.get("kuro_name", ""))]] = str(e.get("key", ""))
	for x in ValidationUtil.as_array(rec.get("excluded_kuro_only", [])):
		if x is Dictionary:
			var key := "%s|%s" % [str(x.get("kuro_item_id", "")), str(x.get("name", ""))]
			if claimed.has(key):
				_error(id, "excluded_kuro_only row %s (%s) is also the chance source of entry '%s'" % [str(x.get("name", "")),
					str(x.get("kuro_item_id", "")), claimed[key]])
	var meso: Variant = rec.get("meso", null)
	if meso is Dictionary:
		_check_meso(id, meso)


# --- entries ------------------------------------------------------------------------------------------------

func _check_entry(id: String, e: Dictionary) -> void:
	var where := "entry '%s'" % str(e.get("key", e.get("name", "?")))
	var item_id: Variant = e.get("item_id", null)
	var res: Variant = e.get("item_resolution", {})
	var state: String = str(res.get("state", "")) if res is Dictionary else ""
	if item_id != null and not db.has("items", str(item_id)):
		_error(id, "%s: item %s is not a local MeowDB item" % [where, str(item_id)])
	var resolved := str(e.get("chance_state", "")) == "resolved"
	var cs: Variant = e.get("chance_source", null)
	var p: Variant = e.get("probability", null)
	if resolved and cs is Dictionary:
		if not ValidationUtil.same(cs.get("authority", null), ProvenanceAuthorities.KURODB):
			_error(id, "%s: a drop chance comes from KuroDB only (MeowDB publishes none), got %s" % [where, var_to_str(cs.get("authority", null))])
		_check_raw(id, where, cs, p, e.get("quantity", null), false)
		if ValidationUtil.is_number(p) and float(p) == 0.0:
			report.warning("drop_policy", "drops", id, "%s: resolved chance 0 (never drops)" % where)
	_check_gate(id, where, e, item_id)
	# Visible unresolved members (warnings; the candidates are in the record's item_resolution).
	var never: PackedStringArray = []
	if not resolved:
		never.append("chance unresolved (no KuroDB value for this member)")
	if item_id == null:
		never.append("item unresolved (%s)" % state)
		var cands: Array = ValidationUtil.as_array(res.get("candidates", [])) if res is Dictionary else []
		for c in cands:
			if db.has("items", str(c)) and state == "not_in_snapshot":
				report.warning("drop_unresolved", "drops", id, "%s: MeowDB candidate %s is now a local item; review its row in tools/sources/crosswalk/drop_items.json" % [where, str(c)])
	if not never.is_empty():
		report.count("drop_entries_unresolved")
		report.warning("drop_unresolved", "drops", id, "'%s' never rolls: %s" % [str(e.get("name", "?")), "; ".join(never)])
		# Brief: an unresolved drop that Maple Island progression needs is a blocker.
		if item_id != null and _quest_items.has(str(item_id)):
			_error(id, "%s: item %s is needed by quest %s but never rolls here (%s): a progression blocker unless another source gives it" % [
				where, str(item_id), str(_quest_items[str(item_id)]), "; ".join(never)])


## Re-reads a chance source's raw_value exactly and compares every stored number with the reading.
func _check_raw(id: String, where: String, cs: Dictionary, p: Variant, qty: Variant, meso: bool) -> void:
	var raw: Variant = cs.get("raw_value", null)
	var parsed := DropChance.parse_by_format(cs.get("format", null), raw)
	if not bool(parsed.ok):
		_error(id, "%s.chance_source: raw_value does not read as %s: %s" % [where, str(cs.get("format", "")), parsed.error])
		return
	var exact := float(parsed.probability)
	for pair in [["normalized_probability", cs.get("normalized_probability", null)], ["probability", p]]:
		var v: Variant = pair[1]
		if not ValidationUtil.is_number(v) or is_nan(float(v)) or float(v) < 0.0 or float(v) > 1.0:
			_error(id, "%s: %s %s is not a probability in [0, 1]" % [where, pair[0], var_to_str(v)])
		elif absf(float(v) - exact) > EPSILON * maxf(1.0, exact):
			_error(id, "%s: %s %s is not the exact reading of %s (%s)" % [where, pair[0], str(v), var_to_str(raw), str(exact)])
	if str(cs.get("conversion", "")) != str(parsed.conversion):
		_error(id, "%s.chance_source: conversion %s should be %s" % [where, var_to_str(cs.get("conversion", null)), var_to_str(parsed.conversion)])
	var quest := str(parsed.get("quest", ""))
	var stored: Variant = cs.get("kuro_quest_condition", null)
	if not meso and quest != (str(stored) if stored != null else ""):
		_error(id, "%s.chance_source: kuro_quest_condition %s differs from the raw value's quest flag %s" % [where, var_to_str(stored), var_to_str(quest)])
	if parsed.format == "percent_base":
		if bool(parsed.meso) != meso:
			_error(id, "%s.chance_source: raw_value %s is %s" % [where, var_to_str(raw), "an item row, not a \"Meso drop\" row" if meso else "a meso row, not an item row"])
		if not meso:
			if not (qty is Dictionary) or not bool(parsed.has_qty) or int(qty.get("min", -1)) != int(parsed.qty_min) \
					or int(qty.get("max", -1)) != int(parsed.qty_max):
				_error(id, "%s: quantity %s differs from the raw value's %s" % [where, var_to_str(qty), var_to_str(raw)])
	elif not meso:
		# A reactor row carries no quantity: the one in the record is a labelled MisoStory adaptation.
		var adaptation: Variant = qty.get("adaptation", null) if qty is Dictionary else null
		if not (adaptation is Dictionary) or not ValidationUtil.same(adaptation.get("verified", null), false) \
				or not ValidationUtil.non_empty(adaptation.get("reason", null)):
			_error(id, "%s: KuroDB reactor rows give no quantity, so quantity must carry adaptation {reason, verified: false}" % where)


## The C1 quest-gate rule: gated exactly when the item is a quest item a Maple Island quest objective asks for.
func _check_gate(id: String, where: String, e: Dictionary, item_id: Variant) -> void:
	var gate: Variant = e.get("quest_gate", null)
	var expected := ""
	if item_id != null:
		var is_quest_item := str(db.item(str(item_id)).get("subtype", "")) == QUEST_SUBTYPE or _membership_marks_quest(e)
		var asking: Array = _quest_items.get(str(item_id), [])
		if is_quest_item and asking.size() > 1:
			_error(id, "%s: quest item %s is asked for by quests %s; the C1 gate rule needs exactly one" % [where, str(item_id), str(asking)])
		elif is_quest_item and asking.size() == 1:
			expected = str(asking[0])
	var actual := str(gate.get("quest_id", "")) if gate is Dictionary else ""
	if actual != expected:
		_error(id, "%s: the C1 quest-gate rule gives %s, the record says %s" % [where,
			"quest %s" % expected if expected != "" else "no gate", "quest %s" % actual if actual != "" else "no gate"])
	if gate is Dictionary and not ValidationUtil.same(gate.get("verified", null), false):
		_error(id, "%s: quest_gate is a MisoStory derivation (decision D3-9) and must say verified: false" % where)


## True when the membership source itself lists the member as a quest item (MeowDB's breakable list: the line after
## the name is its subtype).
func _membership_marks_quest(e: Dictionary) -> bool:
	var ms: Variant = e.get("membership_source", null)
	if not (ms is Dictionary) or not ValidationUtil.same(ms.get("authority", null), ProvenanceAuthorities.MEOWDB):
		return false
	var lines := str(ms.get("raw_value", "")).split("\n")
	return lines.size() > 1 and lines[1].strip_edges() == QUEST_SUBTYPE


# --- meso ---------------------------------------------------------------------------------------------------

func _check_meso(id: String, meso: Dictionary) -> void:
	var a: Variant = meso.get("amount_source", null)
	if str(meso.get("amount_state", "")) == "resolved" and a is Dictionary:
		if not (a.get("authority", null) in MESO_AMOUNT_AUTHORITIES):
			_error(id, "meso.amount_source: a meso amount comes from MeowDB or Hidden Street (D3-5), got %s" % var_to_str(a.get("authority", null)))
		var parsed := DropChance.parse_meso_amount(a.get("raw_value", null))
		if not bool(parsed.ok) or parsed.state != "resolved":
			_error(id, "meso.amount_source: raw_value %s does not read as a meso amount%s" % [var_to_str(a.get("raw_value", null)),
				": " + str(parsed.error) if not bool(parsed.ok) else ""])
		elif int(parsed.min) != int(meso.get("min", -1)) or int(parsed.max) != int(meso.get("max", -1)):
			_error(id, "meso: min %s, max %s are not the amount_source's %d-%d" % [_num(meso.get("min", null)), _num(meso.get("max", null)),
				int(parsed.min), int(parsed.max)])
	elif str(meso.get("amount_state", "")) != "resolved":
		report.warning("drop_unresolved", "drops", id, "meso amount unresolved: the meso bag never rolls")
	var cs: Variant = meso.get("chance_source", null)
	if str(meso.get("chance_state", "")) == "resolved" and cs is Dictionary:
		if not ValidationUtil.same(cs.get("authority", null), ProvenanceAuthorities.KURODB):
			_error(id, "meso.chance_source: the meso chance comes from KuroDB only; MeowDB's report form value dropChancePct is not a chance (D3-5), got %s" % var_to_str(cs.get("authority", null)))
		_check_raw(id, "meso", cs, meso.get("probability", null), null, true)
	elif str(meso.get("chance_state", "")) != "resolved":
		report.warning("drop_unresolved", "drops", id, "meso chance unresolved: the meso bag never rolls")


func _error(id: String, message: String) -> void:
	report.error("drop_policy", "drops", id, message)


## A JSON number for a message: whole numbers without ".0".
static func _num(v: Variant) -> String:
	if ValidationUtil.is_number(v) and float(v) == floorf(float(v)):
		return str(int(v))
	return var_to_str(v)
