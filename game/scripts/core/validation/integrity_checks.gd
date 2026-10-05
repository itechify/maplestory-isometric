class_name IntegrityChecks
extends RefCounted
## The Phase 16 rules the reference sweep cannot express (brief "Content Cross-Reference Validation"):
##
##   chair       a chair reference (formulas `chairs[].item_id`, formulas/recovery.json) is a Setup item with a `setup`
##               block {hp_recovery_bonus >= 0, interval_s > 0} (contract C5: a chair is any Setup item that has setup
##               data); any item with a `setup` block is a Setup item; the formulas chair numbers agree with the item's
##               setup block (warning)
##   name        no placeholder names: every `name` / `*_name` string in canonical and adaptation data is non-empty and
##               not a stand-in ("placeholder", "TODO", "TBD", "FIXME", "Unknown ...", "Item 1234", "?")
##   duplicate   no id defined twice: a skill_id in two formulas skills[] entries, and the same id twice in a list where
##               each entry is one distinct thing (DUPLICATE_LISTS: a map's NPCs and species, a shop's stock, a v1 drop
##               table, a quest's objectives and reward items)
##
## Record ids themselves are unique per domain (ProvenanceChecks "ids": id = file basename). Ids may repeat across
## domains (monster "2" and item "2" are different things), and two records may share a name (Red Cloth Pants, items
## 1168 male and 1177 female), so neither is a finding.

## Keys whose string value names something.
const NAME_KEY := "name"
const NAME_SUFFIX := "_name"
## Case-insensitive patterns of a stand-in name.
const PLACEHOLDER_PATTERNS := ["(?i)placeholder", "\\b(TODO|TBD|FIXME)\\b", "(?i)^\\s*unknown\\b", "(?i)^\\s*item\\s*#?\\s*\\d+\\s*$",
	"^\\s*\\?+\\s*$"]

## domain -> [{list: path of an array in the record, key: field (or fields) that identify an entry}]. Entries
## without the key (null) are ignored. Map reactors[] are placements and may repeat; v2 drop tables are checked by
## DropRecordChecks ("no two entries resolve to the same item").
const DUPLICATE_LISTS := {
	"maps": [{"list": "npcs", "key": ["id"]}, {"list": "monsters", "key": ["id"]}],
	"shops": [{"list": "items", "key": ["item_id"]}],
	"drops": [{"list": "entries", "key": ["item_id"], "v1_only": true}],
	"quests": [{"list": "objectives.monster_kills", "key": ["mob_id"]},
		{"list": "objectives.item_collection", "key": ["item_id"]},
		{"list": "objectives.item_usage", "key": ["item_id"]},
		{"list": "objectives.npc_talk", "key": ["npc_id", "purpose"]},
		{"list": "rewards.items", "key": ["item_id"]}],
}

## Where chairs are listed: formulas records, `chairs[].item_id` (formulas/recovery.json).
const CHAIRS := "chairs"
const SETUP_TYPE := "Setup"

var db: ContentDB
var report: ValidationReport
var _placeholders: Array[RegEx] = []


func _init(content: ContentDB, into: ValidationReport) -> void:
	db = content
	report = into
	for p in PLACEHOLDER_PATTERNS:
		_placeholders.append(RegEx.create_from_string(p))


func run() -> void:
	_check_chairs()
	_check_setup_items()
	for domain_name in ValidationUtil.canonical_domains(db):
		for id in db.ids(domain_name):
			_check_names(domain_name, id, db.get_entity(domain_name, id), "")
			_check_duplicate_entries(domain_name, id, db.get_entity(domain_name, id))
	for folder in db.miso:
		var label := "misostory" if str(folder) == "" else "misostory/%s" % folder
		for key in db.miso[folder]:
			_check_names(label, str(key), db.miso[folder][key], "")
	_check_skill_definitions()


# --- chairs -------------------------------------------------------------------------------------------------

func _check_chairs() -> void:
	for formula_id in db.ids("formulas"):
		var i := 0
		for chair in ValidationUtil.as_array(db.formula(formula_id).get(CHAIRS, [])):
			var where := "%s[%d]" % [CHAIRS, i]
			i += 1
			var item_id: Variant = chair.get("item_id", null) if chair is Dictionary else null
			if not (item_id is String) or not db.has("items", item_id):
				continue  # the reference sweep reports a missing or malformed item_id
			var item: Dictionary = db.item(item_id)
			var problems := chair_problems(item)
			for p in problems:
				report.error("chair", "formulas", formula_id, "%s: item %s (%s) is not a usable chair: %s" % [
					where, item_id, str(item.get("name", "?")), p])
			if not problems.is_empty():
				continue
			report.count("refs.chair-item")
			var setup: Dictionary = item.setup
			for pair in [["additional_hp_per_tick", "hp_recovery_bonus"], ["tick_interval_s", "interval_s"]]:
				if chair.has(pair[0]) and not ValidationUtil.same(chair[pair[0]], setup.get(pair[1], null)):
					report.warning("chair", "formulas", formula_id, "%s.%s is %s but item %s setup.%s is %s" % [
						where, pair[0], var_to_str(chair[pair[0]]), item_id, pair[1], var_to_str(setup.get(pair[1], null))])


## Why `item` cannot be used as a chair (contract C5), or an empty list.
static func chair_problems(item: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	if not ValidationUtil.same(item.get("type", null), SETUP_TYPE):
		out.append("its type is %s, not %s" % [var_to_str(item.get("type", null)), SETUP_TYPE])
	var setup: Variant = item.get("setup", null)
	if not (setup is Dictionary):
		out.append("it has no setup block {hp_recovery_bonus, interval_s}")
		return out
	var bonus: Variant = setup.get("hp_recovery_bonus", null)
	if not ValidationUtil.is_number(bonus) or float(bonus) < 0.0:
		out.append("setup.hp_recovery_bonus must be a number >= 0, got %s" % var_to_str(bonus))
	var interval: Variant = setup.get("interval_s", null)
	if not ValidationUtil.is_number(interval) or float(interval) <= 0.0:
		out.append("setup.interval_s must be a number > 0, got %s" % var_to_str(interval))
	return out


## An item with setup data is used as a chair, so it must be a Setup item (the Set-up inventory tab holds chairs).
func _check_setup_items() -> void:
	for item_id in db.ids("items"):
		var item: Dictionary = db.item(item_id)
		if item.get("setup", null) != null and not ValidationUtil.same(item.get("type", null), SETUP_TYPE):
			report.error("chair", "items", item_id, "has a setup block but its type is %s, not %s" % [
				var_to_str(item.get("type", null)), SETUP_TYPE])


# --- placeholder names --------------------------------------------------------------------------------------

func _check_names(domain_label: String, id: String, node: Variant, path: String) -> void:
	if node is Dictionary:
		for k in node:
			var key := str(k)
			if key in ReferenceChecks.EXCLUDED_KEYS:
				continue
			var child := key if path == "" else "%s.%s" % [path, key]
			var value: Variant = node[k]
			if (key == NAME_KEY or key.ends_with(NAME_SUFFIX)) and value is String:
				report.count("names_checked")
				if is_placeholder_name(value):
					report.error("name", domain_label, id, "%s %s is a placeholder, not a name (names come from the source data or are written for the player)" % [
						child, var_to_str(value)])
			else:
				_check_names(domain_label, id, value, child)
	elif node is Array:
		for e in node:
			_check_names(domain_label, id, e, path + "[]")


## True for an empty or stand-in name (PLACEHOLDER_PATTERNS).
func is_placeholder_name(value: String) -> bool:
	if value.strip_edges() == "":
		return true
	for re in _placeholders:
		if re.search(value) != null:
			return true
	return false


# --- duplicates ---------------------------------------------------------------------------------------------

func _check_duplicate_entries(domain_name: String, id: String, rec: Dictionary) -> void:
	for rule in DUPLICATE_LISTS.get(domain_name, []):
		if rule.get("v1_only", false) and ValidationUtil.same(rec.get("schema_version", null), 2):
			continue
		var seen := {}
		for e in ValidationUtil.as_array(_at(rec, rule.list)):
			if not (e is Dictionary):
				continue
			var parts: PackedStringArray = []
			var complete := true
			for field in rule.key:
				var v: Variant = e.get(field, null)
				if v == null:
					complete = false
				parts.append(str(v))
			if not complete:
				continue
			var key := "/".join(parts)
			if seen.has(key):
				report.error("duplicate", domain_name, id, "%s lists %s %s twice" % [
					rule.list, "/".join(PackedStringArray(rule.key)), key])
			seen[key] = true


static func _at(rec: Dictionary, dotted: String) -> Variant:
	var node: Variant = rec
	for part in dotted.split("."):
		if not (node is Dictionary):
			return null
		node = node.get(part, null)
	return node


func _check_skill_definitions() -> void:
	var defs := ReferenceChecks.skill_definitions(db)
	var ids: Array = defs.keys()
	ids.sort()
	for skill_id in ids:
		var where: PackedStringArray = defs[skill_id]
		if where.size() > 1:
			report.error("duplicate", "formulas", where[0], "skill %s is defined %d times (formulas %s skills[]); a canonical id is defined once" % [
				skill_id, where.size(), ", ".join(where)])
