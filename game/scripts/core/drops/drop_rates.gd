class_name DropRates
extends RefCounted
## Reads the canonical drop records (data/canonical/drops/<owner id>.json, schema v2, contract C1) for the roller:
## which entries may roll and at what chance, how many, under which quest gate, and the meso bag. Plus the ground rules
## in data/misostory/drops.json (lifetime, ownership, scatter) and the canonical pickup box.
##
## Every chance, quantity and meso amount comes from the record and nowhere else (C1): membership from Hidden Street
## (monsters) or MeowDB (the Wooden Box), chances from KuroDB, meso amounts from MeowDB or Hidden Street. A member the
## sources leave unresolved (no KuroDB chance, or no local MeowDB item) stays visible with chance 0 and the reason in
## "excluded", and never rolls. A table that is not schema v2 supplies no chances at all.
##
## Pure and read-only. Each row says where its chance came from ("source"), so debug output and tests can show why an
## item drops at the rate it does.

## Why an entry never rolls (DropRates.effective_entries "excluded").
const UNRESOLVED_CHANCE := "unresolved_chance"
const UNRESOLVED_ITEM := "unresolved_item"
const UNKNOWN_ITEM := "unknown_item"
const INVALID_CHANCE := "invalid_chance"
const NOT_V2 := "not_v2"

## The context key DropRoller.roll reads (contract C2).
const CTX_QUESTS := "quests_in_progress"

## The meso amount distribution the roller implements; data/misostory/drop_rates.json must name it.
const MESO_DISTRIBUTION := "uniform_integer_inclusive"


static func _ground(db: ContentDB) -> Dictionary:
	var t: Variant = db.miso_table("drops")
	return t if t is Dictionary else {}


## True if a canonical drop table exists for this owner (monster id or breakable id).
static func has_table(owner_id: String, db: ContentDB) -> bool:
	return db.has("drops", owner_id)


## "monster", "breakable" or "" (read from the table's owner block, never from the id).
static func owner_kind(owner_id: String, db: ContentDB) -> String:
	return String(db.drop_table(owner_id).get("owner", {}).get("kind", ""))


## True when the owner's table is a schema v2 record (contract C1).
static func is_v2(owner_id: String, db: ContentDB) -> bool:
	return DropRecordChecks.is_v2(db.drop_table(owner_id))


## Every member of the owner's table in canonical order, with what the roller may do with it:
##   {"key", "name", "item_id" ("" when unresolved), "chance" (0 when it never rolls), "min_quantity", "max_quantity",
##    "quest_gate" (MeowDB quest id, or ""), "excluded" ("" when it may roll, else UNRESOLVED_CHANCE / UNRESOLVED_ITEM /
##    UNKNOWN_ITEM / INVALID_CHANCE / NOT_V2), "source" (where the chance came from: "KuroDB '2.00% base | Qty 1'"),
##    "item_state" (item_resolution.state), "chance_state"}
## A gated entry is not excluded: whether it rolls depends on the quests in progress (DropRoller.roll's context).
static func effective_entries(owner_id: String, db: ContentDB) -> Array:
	var out: Array = []
	var table := db.drop_table(owner_id)
	var v2 := DropRecordChecks.is_v2(table)
	for e in ValidationUtil.as_array(table.get("entries", [])):
		if not (e is Dictionary):
			continue
		var raw_id: Variant = e.get("item_id", null)
		var item_id := "" if raw_id == null else str(raw_id)
		var res: Variant = e.get("item_resolution", null)
		var gate: Variant = e.get("quest_gate", null)
		var qty: Variant = e.get("quantity", null)
		var cs: Variant = e.get("chance_source", null)
		var row := {"key": str(e.get("key", item_id)), "name": str(e.get("name", e.get("item_name", ""))), "item_id": item_id,
			"chance": 0.0, "min_quantity": 1, "max_quantity": 1, "quest_gate": "", "excluded": "", "source": "",
			"item_state": str(res.get("state", "")) if res is Dictionary else "",
			"chance_state": str(e.get("chance_state", ""))}
		if gate is Dictionary and gate.get("quest_id", null) != null:
			row.quest_gate = str(gate.quest_id)
		if cs is Dictionary:
			row.source = "%s '%s'" % [str(cs.get("authority", "")), str(cs.get("raw_value", ""))]
		var p: Variant = e.get("probability", null)
		if not v2:
			row.excluded = NOT_V2
		elif row.chance_state != "resolved" or p == null:
			row.excluded = UNRESOLVED_CHANCE
		elif raw_id == null:
			row.excluded = UNRESOLVED_ITEM
		elif not db.has("items", item_id):
			row.excluded = UNKNOWN_ITEM
		elif not ValidationUtil.is_number(p) or is_nan(float(p)) or float(p) < 0.0 or float(p) > 1.0:
			row.excluded = INVALID_CHANCE
		if qty is Dictionary and ValidationUtil.is_number(qty.get("min", null)) and ValidationUtil.is_number(qty.get("max", null)):
			row.min_quantity = maxi(1, int(qty.min))
			row.max_quantity = maxi(int(row.min_quantity), int(qty.max))
		if row.excluded == "":
			row.chance = float(p)
		out.append(row)
	return out


## The meso rule for an owner: {"chance", "min", "max", "source", "excluded"}. chance is 0 (and "excluded" says why)
## unless the record's meso amount and meso chance are both resolved (C1); the amount is a uniform integer in
## [min, max]. A null meso block means the owner never drops mesos ("no_mesos").
static func meso_rule(owner_id: String, db: ContentDB) -> Dictionary:
	var out := {"chance": 0.0, "min": 0, "max": 0, "source": "", "excluded": ""}
	var table := db.drop_table(owner_id)
	if table.is_empty():
		out.excluded = "no_table"
		return out
	if not DropRecordChecks.is_v2(table):
		out.excluded = NOT_V2
		return out
	var meso: Variant = table.get("meso", null)
	if not (meso is Dictionary):
		out.excluded = "no_mesos"
		return out
	var amount_src: Variant = meso.get("amount_source", null)
	var chance_src: Variant = meso.get("chance_source", null)
	var parts: PackedStringArray = []
	if amount_src is Dictionary:
		parts.append("amount %s '%s'" % [str(amount_src.get("authority", "")), str(amount_src.get("raw_value", ""))])
	if chance_src is Dictionary:
		parts.append("chance %s '%s'" % [str(chance_src.get("authority", "")), str(chance_src.get("raw_value", ""))])
	out.source = ", ".join(parts)
	var lo: Variant = meso.get("min", null)
	var hi: Variant = meso.get("max", null)
	var p: Variant = meso.get("probability", null)
	if str(meso.get("amount_state", "")) != "resolved" or not ValidationUtil.is_number(lo) or not ValidationUtil.is_number(hi):
		out.excluded = "unresolved_amount"
		return out
	if str(meso.get("chance_state", "")) != "resolved" or not ValidationUtil.is_number(p):
		out.excluded = UNRESOLVED_CHANCE
		return out
	if is_nan(float(p)) or float(p) < 0.0 or float(p) > 1.0 or int(lo) < 1 or int(hi) < int(lo):
		out.excluded = INVALID_CHANCE
		return out
	out.chance = float(p)
	out.min = int(lo)
	out.max = int(hi)
	return out


## The members and meso values that never roll because a source leaves them unresolved, for validation, debug and
## the parity report: [{"owner", "key", "name", "what" ("chance" | "item" | "meso amount" | "meso chance"),
## "reason"}]. Gated entries are not listed (they roll while their quest is in progress).
static func unresolved(owner_id: String, db: ContentDB) -> Array:
	var out: Array = []
	for row in effective_entries(owner_id, db):
		if row.excluded == "":
			continue
		var what := "item" if row.excluded in [UNRESOLVED_ITEM, UNKNOWN_ITEM] else "chance"
		var reason := str(row.excluded)
		if row.excluded == UNRESOLVED_ITEM:
			reason = "item %s" % row.item_state
		out.append({"owner": owner_id, "key": row.key, "name": row.name, "what": what, "reason": reason})
	var meso := meso_rule(owner_id, db)
	if meso.excluded == "unresolved_amount" or meso.excluded == UNRESOLVED_CHANCE:
		out.append({"owner": owner_id, "key": "mesos", "name": "mesos",
			"what": "meso amount" if meso.excluded == "unresolved_amount" else "meso chance", "reason": meso.excluded})
	return out


## The quests in progress named by a roll context (contract C2: ctx.quests_in_progress); empty when absent.
static func quests_in_progress(ctx: Dictionary) -> PackedStringArray:
	var q: Variant = ctx.get(CTX_QUESTS, null)
	if q is PackedStringArray:
		return q
	var out := PackedStringArray()
	if q is Array:
		for id in q:
			out.append(str(id))
	return out


## True when a resolved row may roll under the given quests in progress: not excluded, and ungated or its gate quest
## in progress (C1 runtime rule).
static func may_roll(row: Dictionary, quests: PackedStringArray) -> bool:
	if str(row.get("excluded", "")) != "" or float(row.get("chance", 0.0)) <= 0.0:
		return false
	var gate := str(row.get("quest_gate", ""))
	return gate == "" or quests.has(gate)


## Seconds a drop stays on the ground (data/misostory/drops.json, unverified).
static func ground_lifetime_s(db: ContentDB) -> float:
	return float(_ground(db).get("ground_lifetime_s", 0.0))


## Seconds a drop belongs only to its owner before anyone may take it (unverified).
static func owner_exclusive_s(db: ContentDB) -> float:
	return float(_ground(db).get("owner_exclusive_s", 0.0))


## Spacing between drops from one kill, in MapleStory px (convert with WorldScale.h; unverified).
static func scatter_spacing_px(db: ContentDB) -> float:
	return float(_ground(db).get("scatter_spacing_px", 0.0))


## The canonical player pickup box in MapleStory px around the feet (formulas/loot_rules.json player_pickup_box_px:
## {"left", "right", "above", "below"}); missing values are 0.
static func pickup_box_px(db: ContentDB) -> Dictionary:
	var b: Variant = db.formula("loot_rules").get("player_pickup_box_px", {})
	var box: Dictionary = b if b is Dictionary else {}
	var out := {}
	for k in ["left", "right", "above", "below"]:
		out[k] = float(box.get(k, 0.0)) if box.get(k) != null else 0.0
	return out


## The pickup box in meters, converted with WorldScale.actor (ARCHITECTURE.md: actor_px_to_m covers the pickup box).
static func pickup_box_m(db: ContentDB) -> Dictionary:
	var px := pickup_box_px(db)
	var out := {}
	for k in px:
		out[k] = WorldScale.actor(float(px[k]))
	return out


## Keys of data/misostory/drop_rates.json that would supply a chance, quantity or meso amount. The file may hold none
## of them at any depth (C1: nothing outside the canonical records supplies those values).
const RATE_KEYS := ["chance", "probability", "rate", "rate_multiplier", "global_rate_multiplier", "min_quantity",
	"max_quantity", "quantity", "min", "max", "amount", "per_level", "type_rates", "subtype_rates", "default_rate",
	"item_overrides", "owner_item_overrides", "by_owner"]


## Problems in data/misostory/drop_rates.json, the file that documents the drop runtime's MisoStory interpretations:
## it must be labelled (verified: false, a reason), hold no rate, quantity or meso number (RATE_KEYS, or any number at
## all), and name the meso amount distribution the roller implements (MESO_DISTRIBUTION). Empty when consistent.
static func validate(db: ContentDB) -> PackedStringArray:
	var errors: PackedStringArray = []
	var t: Variant = db.miso_table("drop_rates")
	if not (t is Dictionary):
		errors.append("data/misostory/drop_rates.json is missing")
		return errors
	var rates: Dictionary = t
	if rates.get("verified") != false:
		errors.append("drop_rates.json must say verified: false")
	if String(rates.get("reason", "")).strip_edges() == "":
		errors.append("drop_rates.json needs a reason")
	_find_rate_values(rates, "", errors)
	var dist: Variant = rates.get("meso_amount_distribution", null)
	if not (dist is Dictionary) or str(dist.get("value", "")) != MESO_DISTRIBUTION:
		errors.append("drop_rates.json meso_amount_distribution.value must be \"%s\" (what DropRoller implements)" % MESO_DISTRIBUTION)
	return errors


static func _find_rate_values(node: Variant, path: String, errors: PackedStringArray) -> void:
	if node is Dictionary:
		for k in node:
			var key := str(k)
			var child := key if path == "" else "%s.%s" % [path, key]
			if key in RATE_KEYS:
				errors.append("drop_rates.json %s: a chance, quantity or meso value outside the canonical drop records (contract C1)" % child)
			_find_rate_values(node[k], child, errors)
	elif node is Array:
		for i in node.size():
			_find_rate_values(node[i], "%s[%d]" % [path, i], errors)
	elif ValidationUtil.is_number(node) and not (node is bool):
		errors.append("drop_rates.json %s: holds the number %s; the file documents rules, it supplies no values" % [path, str(node)])
