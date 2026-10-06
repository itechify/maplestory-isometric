class_name DropChecks
extends RefCounted
## The drop policy over the shipped canonical drop records (Iteration Three brief "Drop Pass"; contracts C1 and C2;
## decisions D3-9, D3-11 and D3-12). DropRecordChecks checks each schema 3 record's shape and sources; these checks
## hold the records to the dated captures, the item data and the project owner's rule files:
##
##   drop_policy (errors)
##     - data/misostory/drop_rates.json is the complete chance table (every category x rarity a chance in [0, 1],
##       decision D3-11, verified: false, quantity 1) and data/misostory/meso_rules.json a valid meso rule (D3-12)
##       (DropRates.validate)
##     - every drop record is schema 3 and its membership authority is MeowDB MS Classic
##     - membership equals MeowDB's community list "Drops (MS Classic)" on the record's capture exactly: the same names
##       in the same order, each entry's raw block and votes as the page shows them; no MSEA-only item is a member
##     - every rarity is Henesys.gg's label from tools/henesys/captures/item_rarity.json (the same label and row), and
##       a member the capture has no row for has rarity null
##     - a resolved item exists in the local items; category_inputs are that item's MeowDB type and subtype, and the
##       chance_category follows the rule (DropRates.CATEGORIES; tools/sources/drops_merge.mjs deriveChanceCategory)
##     - quest gates follow the D3-9 rule: an entry is gated exactly when its item's MeowDB subtype is "Quest Item"
##       and one Maple Island quest objective asks for it, and the gate is that quest
##     - a monster's reported meso amount comes from MeowDB; meso_rules.json no_mesos names drop owners
##     - an unresolved member whose item a Maple Island quest objective asks for is a progression blocker
##   drop_unresolved (warnings): each member that never rolls because its item, rarity or category is unresolved, so
##     unknown values stay visible
## The capture comparisons need the capture files (DataValidator options repo_root; scripts/test.sh and
## scripts/validate_data.sh mirror tools/*/captures). With injected capture_files (fixture tests) they are skipped.

const QUEST_SUBTYPE := "Quest Item"

var db: ContentDB
var report: ValidationReport
var provenance: ProvenanceChecks
var _quest_items: Dictionary = {}  # item id -> [quest ids whose objectives.item_collection asks for it]
var _rarity: Dictionary = {}  # DropSourceCaptures.rarity_capture result, read once
var _lists: Dictionary = {}  # capture path -> DropSourceCaptures.community_list result


func _init(content: ContentDB, into: ValidationReport, provenance_checks: ProvenanceChecks = null) -> void:
	db = content
	report = into
	provenance = provenance_checks if provenance_checks != null else ProvenanceChecks.new(content, ValidationReport.new())
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


## True when the capture comparisons can run (no injected capture list: the files are on disk under repo_root()).
func reads_captures() -> bool:
	return not (provenance.options.get("capture_files", null) is Dictionary)


func run() -> void:
	# The rule files the runtime applies: checked here so the data validator (scripts/validate_data.sh) refuses an
	# incomplete table or a broken meso rule, not only a unit test.
	for message in DropRates.validate(db):
		report.error("drop_policy", "misostory", "drop_rates" if message.begins_with("drop_rates") or message.contains("drop_rates.json") else "meso_rules", message)
	for id in db.ids("drops"):
		var rec: Dictionary = db.drop_table(id)
		if not DropRates.is_v3_record(rec):
			_error(id, "not a schema 3 record (contract C1): the runtime reads only schema 3")
			continue
		report.count("drop_policy_records_checked")
		check_record(id, rec)


func check_record(id: String, rec: Dictionary) -> void:
	if not ValidationUtil.same(rec.get("membership_authority", null), ProvenanceAuthorities.MEOWDB):
		_error(id, "membership_authority must be %s (MeowDB's community list, decision D3-11), got %s" % [ProvenanceAuthorities.MEOWDB,
			var_to_str(rec.get("membership_authority", null))])
	var entries: Array = ValidationUtil.as_array(rec.get("entries", []))
	if reads_captures():
		_check_membership(id, rec, entries)
		_check_rarity(id, entries)
	for e in entries:
		if e is Dictionary:
			report.count("drop_policy_entries_checked")
			_check_entry(id, e)
	var meso: Variant = rec.get("meso", null)
	if meso is Dictionary:
		var src: Variant = meso.get("amount_source", null)
		if src is Dictionary and not ValidationUtil.same(src.get("authority", null), ProvenanceAuthorities.MEOWDB):
			_error(id, "meso.amount_source: a meso amount comes from MeowDB's player reports only (D3-12), got %s" % var_to_str(src.get("authority", null)))


# --- membership and rarity against the captures --------------------------------------------------------------

## The record's membership capture path: the one its entries' membership sources cite, else provenance.membership's.
static func membership_capture(rec: Dictionary) -> String:
	for e in ValidationUtil.as_array(rec.get("entries", [])):
		if e is Dictionary and e.get("membership_source", null) is Dictionary and e.membership_source.get("capture", null) is String:
			return e.membership_source.capture
	var prov: Variant = rec.get("provenance", null)
	var m: Variant = prov.get("membership", null) if prov is Dictionary else null
	if m is Dictionary and m.get("capture", null) is String:
		return m.capture
	return ""


func _list_for(capture: String) -> Dictionary:
	if not _lists.has(capture):
		_lists[capture] = DropSourceCaptures.community_list(provenance.repo_root().path_join(capture))
	return _lists[capture]


func _check_membership(id: String, rec: Dictionary, entries: Array) -> void:
	var capture := membership_capture(rec)
	if capture == "":
		_error(id, "no membership capture (provenance.membership.capture): the membership cannot be checked against MeowDB's list")
		return
	var list := _list_for(capture)
	if not bool(list.ok):
		_error(id, "membership capture %s: %s" % [capture, list.error])
		return
	report.count("drop_membership_lists_checked")
	var want := PackedStringArray()
	for x in list.entries:
		want.append(str(x.name))
	var have := PackedStringArray()
	for e in entries:
		have.append(str(e.get("name", "")) if e is Dictionary else "")
	if have != want:
		var missing := PackedStringArray()
		for n in want:
			if not have.has(n):
				missing.append(n)
		var extra := PackedStringArray()
		for n in have:
			if not want.has(n):
				extra.append(n)
		_error(id, "membership is not MeowDB's community list on %s exactly (decision D3-11): missing %s, not on the list %s%s" % [capture,
			str(missing), str(extra), "" if not missing.is_empty() or not extra.is_empty() else ", order differs"])
	for e in entries:
		if not (e is Dictionary):
			continue
		var name := str(e.get("name", ""))
		var on_list := want.has(name)
		if not on_list and (list.msea as PackedStringArray).has(name):
			_error(id, "'%s' is only on MeowDB's MSEA reference list, which is never membership (decision D3-11)" % name)
		if on_list:
			var x: Dictionary = list.entries[want.find(name)]
			var ms: Variant = e.get("membership_source", null)
			if ms is Dictionary and (str(ms.get("raw_value", "")) != str(x.raw) or not ValidationUtil.same(ms.get("list_group", null), x.group)):
				_error(id, "'%s': membership_source.raw_value / list_group differ from %s (%s, %s)" % [name, capture, var_to_str(x.raw), str(x.group)])


func _rarity_capture() -> Dictionary:
	if _rarity.is_empty():
		_rarity = DropSourceCaptures.rarity_capture(provenance.repo_root().path_join(DropSourceCaptures.RARITY_CAPTURE))
	return _rarity


func _check_rarity(id: String, entries: Array) -> void:
	var cap := _rarity_capture()
	if not bool(cap.ok):
		_error(id, "rarity capture: %s" % cap.error)
		return
	for e in entries:
		if not (e is Dictionary):
			continue
		var name := str(e.get("name", ""))
		var rarity: Variant = e.get("rarity", null)
		var row: Variant = cap.items.get(name, null)
		if row == null:
			if rarity != null:
				_error(id, "'%s': rarity %s, but %s has no row for it (it must stay null: unresolved)" % [name, var_to_str(rarity), DropSourceCaptures.RARITY_CAPTURE])
			continue
		report.count("drop_rarities_checked")
		var label := str(rarity.get("label", "")) if rarity is Dictionary else ""
		var src: Variant = rarity.get("source", null) if rarity is Dictionary else null
		if label != str(row.rarity):
			_error(id, "'%s': rarity %s, Henesys.gg's capture says %s (decision D3-11)" % [name, var_to_str(label), str(row.rarity)])
		elif not (src is Dictionary) or str(src.get("row", "")) != str(row.row) or str(src.get("read_at", "")) != str(cap.read_at) \
				or str(src.get("url", "")) != str(cap.url) or str(src.get("capture", "")) != DropSourceCaptures.RARITY_CAPTURE:
			_error(id, "'%s': rarity.source must quote %s (url, read_at, row)" % [name, DropSourceCaptures.RARITY_CAPTURE])


# --- entries ------------------------------------------------------------------------------------------------

func _check_entry(id: String, e: Dictionary) -> void:
	var where := "entry '%s'" % str(e.get("key", e.get("name", "?")))
	var item_id: Variant = e.get("item_id", null)
	var item := {}
	if item_id != null:
		if not db.has("items", str(item_id)):
			_error(id, "%s: item %s is not a local MeowDB item" % [where, str(item_id)])
		else:
			item = db.item(str(item_id))
	var expected_gate := _check_gate(id, where, e, item_id, item)
	# Category: the item's MeowDB type and subtype, and the rule.
	var inputs: Variant = e.get("category_inputs", null)
	var cat: Variant = e.get("chance_category", null)
	if not item.is_empty():
		if inputs is Dictionary and (not ValidationUtil.same(inputs.get("item_type", null), item.get("type", null))
				or not ValidationUtil.same(inputs.get("item_subtype", null), item.get("subtype", null))
				or not ValidationUtil.same(inputs.get("quest_gated", null), expected_gate != "")):
			_error(id, "%s: category_inputs must be item %s's MeowDB type %s, subtype %s and quest_gated %s" % [where, str(item_id),
				var_to_str(item.get("type", null)), var_to_str(item.get("subtype", null)), str(expected_gate != "")])
		var want := expected_category(item, expected_gate != "")
		if not ValidationUtil.same(cat, want if want != "" else null):
			_error(id, "%s: chance_category %s, the rule gives %s (item %s: %s / %s)" % [where, var_to_str(cat),
				var_to_str(want if want != "" else null), str(item_id), str(item.get("type", "")), str(item.get("subtype", ""))])
	elif cat != null:
		_error(id, "%s: chance_category must be null while the item is unresolved" % where)
	# Visible unresolved members (warnings), and a blocker when a quest needs the item.
	var never: PackedStringArray = []
	if item_id == null:
		var res: Variant = e.get("item_resolution", {})
		never.append("item unresolved (%s)" % (str(res.get("state", "")) if res is Dictionary else "?"))
	if e.get("rarity", null) == null:
		never.append("rarity unresolved (no Henesys.gg row)")
	if item_id != null and cat == null:
		never.append("category unresolved (the drop chance table has no row for this item type)")
	if not never.is_empty():
		report.count("drop_entries_unresolved")
		report.warning("drop_unresolved", "drops", id, "'%s' never rolls: %s" % [str(e.get("name", "?")), "; ".join(never)])
		if item_id != null and _quest_items.has(str(item_id)):
			_error(id, "%s: item %s is needed by quest %s but never rolls here (%s): a progression blocker unless another source gives it" % [
				where, str(item_id), str(_quest_items[str(item_id)]), "; ".join(never)])


## The table category the rule gives an item (DropRates.CATEGORIES), or "" for a type the table has no row for.
static func expected_category(item: Dictionary, gated: bool) -> String:
	match str(item.get("type", "")):
		"Etc":
			if gated:
				return "etc_quest_gated"
			return "etc_own_leftover" if str(item.get("subtype", "")) == "Monster Drop" else "etc_other"
		"Use":
			return "use_scroll" if str(item.get("subtype", "")) == "Scroll" else "use_consumable"
		"Equip":
			return "equip"
		"Setup":
			return "setup"
	return ""


## The D3-9 quest-gate rule: gated exactly when the item's MeowDB subtype is "Quest Item" and one Maple Island quest
## objective asks for it. Returns the expected gate quest ("" for none).
func _check_gate(id: String, where: String, e: Dictionary, item_id: Variant, item: Dictionary) -> String:
	var gate: Variant = e.get("quest_gate", null)
	var expected := ""
	if item_id != null and not item.is_empty():
		var is_quest_item := str(item.get("subtype", "")) == QUEST_SUBTYPE
		var asking: Array = _quest_items.get(str(item_id), [])
		if is_quest_item and asking.size() > 1:
			_error(id, "%s: quest item %s is asked for by quests %s; the gate rule (D3-9) needs exactly one" % [where, str(item_id), str(asking)])
		elif is_quest_item and asking.size() == 1:
			expected = str(asking[0])
	var actual := str(gate.get("quest_id", "")) if gate is Dictionary else ""
	if actual != expected:
		_error(id, "%s: the quest-gate rule (D3-9) gives %s, the record says %s" % [where,
			"quest %s" % expected if expected != "" else "no gate", "quest %s" % actual if actual != "" else "no gate"])
	return expected


func _error(id: String, message: String) -> void:
	report.error("drop_policy", "drops", id, message)
