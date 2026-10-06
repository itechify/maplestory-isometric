class_name DropRates
extends RefCounted
## Reads the canonical drop records (data/canonical/drops/<owner id>.json, schema 3, contract C1) and the project
## owner's two drop rule files for the roller: which entries may roll and at what chance, under which quest gate, and
## the meso bag. Plus the ground rules in data/misostory/drops.json (lifetime, ownership, scatter) and the canonical
## pickup box.
##
## Where each number comes from:
##   membership     the record's entries: MeowDB's community list "Drops (MS Classic)" (decision D3-11)
##   chance         data/misostory/drop_rates.json chance_table[entry.chance_category][entry.rarity.label]
##                  (the owner-approved table, D3-11); rarity is Henesys.gg's label in the record
##   quantity       drop_rates.json quantity_per_drop (1)
##   quest gate     the record's quest_gate (D3-9); rolls only while the quest is in progress (contract C2)
##   meso amount    the record's meso.amount_source (MeowDB's player report) when there is one, else a uniform integer
##                  in [level x min multiplier, level x max multiplier] of the monster's canonical level
##                  (data/misostory/meso_rules.json, D3-12)
##   meso chance    meso_rules.json chance (D3-12); owners in meso_rules.json no_mesos never drop mesos
## A member whose item, rarity or category is unresolved stays visible with chance 0 and the reason in "excluded", and
## never rolls. A table that is not schema 3 supplies no chances at all.
##
## Pure and read-only. Each row says where its chance came from ("source"), so debug output and tests can show why an
## item drops at the rate it does.

## Why an entry never rolls (DropRates.effective_entries "excluded").
const UNRESOLVED_ITEM := "unresolved_item"
const UNRESOLVED_RARITY := "unresolved_rarity"
const UNRESOLVED_CATEGORY := "unresolved_category"
const UNKNOWN_ITEM := "unknown_item"
const NO_TABLE_CHANCE := "no_table_chance"
const NOT_V3 := "not_v3"

## Why the meso bag never rolls (DropRates.meso_rule "excluded").
const NO_TABLE := "no_table"
const NO_MESOS := "no_mesos"
const NO_LEVEL := "no_level"
const INVALID_RULE := "invalid_meso_rule"

## The canonical drop record schema the runtime reads (contract C1).
const SCHEMA_VERSION := 3

## Henesys.gg's rarity labels, the drop chance table's columns (decision D3-11).
const RARITIES := ["Common", "Rare", "Very Rare", "Extremely Rare"]
## The drop chance table's rows (decision D3-11; tools/sources/drops_merge.mjs CHANCE_CATEGORIES derives them).
const CATEGORIES := ["etc_own_leftover", "etc_quest_gated", "etc_other", "use_consumable", "use_scroll", "equip", "setup"]

## The rule files (data/misostory/<name>.json).
const RATES_FILE := "drop_rates"
const MESO_FILE := "meso_rules"
const RATES_DECISION := "D3-11"
const MESO_DECISION := "D3-12"

## The context key DropRoller.roll reads (contract C2).
const CTX_QUESTS := "quests_in_progress"

## The meso amount distribution the roller implements; meso_rules.json must name it.
const MESO_DISTRIBUTION := "uniform_integer_inclusive"


static func _ground(db: ContentDB) -> Dictionary:
	var t: Variant = db.miso_table("drops")
	return t if t is Dictionary else {}


static func _rates(db: ContentDB) -> Dictionary:
	var t: Variant = db.miso_table(RATES_FILE)
	return t if t is Dictionary else {}


static func _meso_rules(db: ContentDB) -> Dictionary:
	var t: Variant = db.miso_table(MESO_FILE)
	return t if t is Dictionary else {}


## True if a canonical drop table exists for this owner (monster id or breakable id).
static func has_table(owner_id: String, db: ContentDB) -> bool:
	return db.has("drops", owner_id)


## "monster", "breakable" or "" (read from the table's owner block, never from the id).
static func owner_kind(owner_id: String, db: ContentDB) -> String:
	return String(db.drop_table(owner_id).get("owner", {}).get("kind", ""))


## True when a drop record is schema 3 (contract C1).
static func is_v3_record(rec: Dictionary) -> bool:
	return ValidationUtil.same(rec.get("schema_version", null), SCHEMA_VERSION)


## True when the owner's table is a schema 3 record.
static func is_v3(owner_id: String, db: ContentDB) -> bool:
	return is_v3_record(db.drop_table(owner_id))


## The chance of `category` x `rarity` in data/misostory/drop_rates.json, or -1.0 when the cell is missing or not a
## number in [0, 1] (DropChecks reports that; the runtime never rolls such an entry).
static func table_chance(db: ContentDB, category: String, rarity: String) -> float:
	var table: Variant = _rates(db).get("chance_table", null)
	if not (table is Dictionary):
		return -1.0
	var row: Variant = table.get(category, null)
	if not (row is Dictionary):
		return -1.0
	var v: Variant = row.get(rarity, null)
	if not ValidationUtil.is_number(v) or v is bool or is_nan(float(v)) or float(v) < 0.0 or float(v) > 1.0:
		return -1.0
	return float(v)


## Items per successful roll (drop_rates.json quantity_per_drop; 1 when missing or not a whole number >= 1).
static func quantity_per_drop(db: ContentDB) -> int:
	var q: Variant = _rates(db).get("quantity_per_drop", null)
	if ValidationUtil.is_number(q) and not (q is bool) and float(q) == floorf(float(q)) and int(q) >= 1:
		return int(q)
	return 1


## Every member of the owner's table in canonical order, with what the roller may do with it:
##   {"key", "name", "item_id" ("" when unresolved), "chance" (0 when it never rolls), "min_quantity", "max_quantity",
##    "quest_gate" (MeowDB quest id, or ""), "excluded" ("" when it may roll, else UNRESOLVED_ITEM / UNKNOWN_ITEM /
##    UNRESOLVED_RARITY / UNRESOLVED_CATEGORY / NO_TABLE_CHANCE / NOT_V3), "source" (where the chance came from:
##    "drop_rates.json equip x Common = 0.001 (D3-11)"), "item_state" (item_resolution.state), "rarity" (label or ""),
##    "category" (chance_category or "")}
## A gated entry is not excluded: whether it rolls depends on the quests in progress (DropRoller.roll's context).
static func effective_entries(owner_id: String, db: ContentDB) -> Array:
	var out: Array = []
	var table := db.drop_table(owner_id)
	var v3 := is_v3_record(table)
	var qty := quantity_per_drop(db)
	for e in ValidationUtil.as_array(table.get("entries", [])):
		if not (e is Dictionary):
			continue
		var raw_id: Variant = e.get("item_id", null)
		var item_id := "" if raw_id == null else str(raw_id)
		var res: Variant = e.get("item_resolution", null)
		var gate: Variant = e.get("quest_gate", null)
		var rarity_block: Variant = e.get("rarity", null)
		var rarity := str(rarity_block.get("label", "")) if rarity_block is Dictionary else ""
		var cat_v: Variant = e.get("chance_category", null)
		var category := str(cat_v) if cat_v is String else ""
		var row := {"key": str(e.get("key", item_id)), "name": str(e.get("name", "")), "item_id": item_id,
			"chance": 0.0, "min_quantity": qty, "max_quantity": qty, "quest_gate": "", "excluded": "", "source": "",
			"item_state": str(res.get("state", "")) if res is Dictionary else "", "rarity": rarity, "category": category}
		if gate is Dictionary and gate.get("quest_id", null) != null:
			row.quest_gate = str(gate.quest_id)
		var chance := table_chance(db, category, rarity) if category != "" and rarity != "" else -1.0
		if chance >= 0.0:
			row.source = "drop_rates.json %s x %s = %s (%s); rarity Henesys.gg" % [category, rarity, str(chance), RATES_DECISION]
		if not v3:
			row.excluded = NOT_V3
		elif raw_id == null:
			row.excluded = UNRESOLVED_ITEM
		elif not db.has("items", item_id):
			row.excluded = UNKNOWN_ITEM
		elif rarity == "" or not (rarity in RARITIES):
			row.excluded = UNRESOLVED_RARITY
		elif category == "" or not (category in CATEGORIES):
			row.excluded = UNRESOLVED_CATEGORY
		elif chance < 0.0:
			row.excluded = NO_TABLE_CHANCE
		if row.excluded == "":
			row.chance = chance
		out.append(row)
	return out


## The meso rule for an owner: {"chance", "min", "max", "source", "excluded", "amount_kind"}. chance is 0 (and
## "excluded" says why) when the owner never drops mesos: no table (NO_TABLE), not schema 3 (NOT_V3), listed in
## meso_rules.json no_mesos (NO_MESOS), no MeowDB report and no canonical level (NO_LEVEL), or a meso rule file that
## does not validate (INVALID_RULE). amount_kind is "meowdb_report" (the record's meso.amount_source) or
## "level_formula"; the amount is a uniform integer in [min, max].
static func meso_rule(owner_id: String, db: ContentDB) -> Dictionary:
	var out := {"chance": 0.0, "min": 0, "max": 0, "source": "", "excluded": "", "amount_kind": ""}
	var table := db.drop_table(owner_id)
	if table.is_empty():
		out.excluded = NO_TABLE
		return out
	if not is_v3_record(table):
		out.excluded = NOT_V3
		return out
	var rules := _meso_rules(db)
	var none: Variant = rules.get("no_mesos", {})
	if none is Dictionary and none.has(owner_id):
		out.excluded = NO_MESOS
		var why: Variant = none[owner_id]
		out.source = "meso_rules.json no_mesos: %s" % (str(why.get("reason", "")) if why is Dictionary else str(why))
		return out
	if not validate_meso_rules(db, PackedStringArray()).is_empty():
		out.excluded = INVALID_RULE
		return out
	var p := float(rules.chance)
	var meso: Variant = table.get("meso", null)
	var src: Variant = meso.get("amount_source", null) if meso is Dictionary else null
	var lo: Variant = meso.get("min", null) if meso is Dictionary else null
	var hi: Variant = meso.get("max", null) if meso is Dictionary else null
	if src is Dictionary and ValidationUtil.is_number(lo) and ValidationUtil.is_number(hi) and int(lo) >= 1 and int(hi) >= int(lo):
		out.amount_kind = "meowdb_report"
		out.min = int(lo)
		out.max = int(hi)
		out.source = "amount %s '%s'; chance meso_rules.json %s (%s)" % [str(src.get("authority", "")),
			str(src.get("raw_value", "")), str(p), MESO_DECISION]
	else:
		var level := owner_level(owner_id, db)
		if level < 1:
			out.excluded = NO_LEVEL
			return out
		out.amount_kind = "level_formula"
		out.min = level * int(rules.amount_level_multiplier_min)
		out.max = level * int(rules.amount_level_multiplier_max)
		out.source = "amount level formula [%d x %d, %d x %d] (level %d); chance meso_rules.json %s (%s)" % [level,
			int(rules.amount_level_multiplier_min), level, int(rules.amount_level_multiplier_max), level, str(p), MESO_DECISION]
	out.chance = p
	return out


## The canonical level of a monster owner (data/canonical/monsters/<id>.json level), or 0 for a breakable or an owner
## without one.
static func owner_level(owner_id: String, db: ContentDB) -> int:
	if owner_kind(owner_id, db) != "monster" or not db.has("monsters", owner_id):
		return 0
	var lv: Variant = db.monster(owner_id).get("level", null)
	return int(lv) if ValidationUtil.is_number(lv) and not (lv is bool) else 0


## The members that never roll because a source leaves them unresolved, for validation, debug and the parity report:
## [{"owner", "key", "name", "what" ("item" | "rarity" | "category" | "chance"), "reason"}]. Gated entries are not
## listed (they roll while their quest is in progress); neither is a meso bag the rules switch off on purpose.
static func unresolved(owner_id: String, db: ContentDB) -> Array:
	var out: Array = []
	for row in effective_entries(owner_id, db):
		if row.excluded == "":
			continue
		var what := "chance"
		var reason := str(row.excluded)
		match row.excluded:
			UNRESOLVED_ITEM:
				what = "item"
				reason = "item %s" % row.item_state
			UNKNOWN_ITEM:
				what = "item"
			UNRESOLVED_RARITY:
				what = "rarity"
				reason = "no Henesys.gg rarity"
			UNRESOLVED_CATEGORY:
				what = "category"
		out.append({"owner": owner_id, "key": row.key, "name": row.name, "what": what, "reason": reason})
	var meso := meso_rule(owner_id, db)
	if meso.excluded in [NO_LEVEL, INVALID_RULE]:
		out.append({"owner": owner_id, "key": "mesos", "name": "mesos", "what": "meso amount", "reason": meso.excluded})
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


## True when `item_id` can come out of a roll of `owner_id` under the roll context `ctx` (contract C2): some member
## of the owner's record resolves to that item, is not excluded (its item, rarity and category resolved, a table cell
## above 0) and may roll under the context's quests (DropRates.may_roll). For checks of what really dropped.
static func rolls_item(owner_id: String, item_id: String, db: ContentDB, ctx: Dictionary = {}) -> bool:
	if item_id == "" or not has_table(owner_id, db):
		return false
	var quests := quests_in_progress(ctx)
	for row: Dictionary in effective_entries(owner_id, db):
		if String(row.get("item_id", "")) == item_id and may_roll(row, quests):
			return true
	return false


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


## Problems in the two rule files the runtime applies (data/misostory/drop_rates.json, decision D3-11, and
## data/misostory/meso_rules.json, D3-12). Empty when both are complete and consistent.
static func validate(db: ContentDB) -> PackedStringArray:
	var errors: PackedStringArray = []
	validate_chance_table(db, errors)
	validate_meso_rules(db, errors)
	return errors


## drop_rates.json: decision D3-11, verified false, a reason; chance_table holds exactly CATEGORIES x RARITIES, every
## cell a number in [0, 1]; rarities lists RARITIES; category_rules names every category; quantity_per_drop is 1 (no
## source gives another); provenance.chance_table cites the project owner. Appends to `errors` and returns it.
static func validate_chance_table(db: ContentDB, errors: PackedStringArray) -> PackedStringArray:
	var t: Variant = db.miso_table(RATES_FILE)
	if not (t is Dictionary):
		errors.append("data/misostory/drop_rates.json is missing (the drop chance table, decision %s)" % RATES_DECISION)
		return errors
	var rates: Dictionary = t
	if not ValidationUtil.same(rates.get("decision", null), RATES_DECISION):
		errors.append("drop_rates.json decision must be \"%s\", got %s" % [RATES_DECISION, var_to_str(rates.get("decision", null))])
	if rates.get("verified") != false:
		errors.append("drop_rates.json must say verified: false (an owner-approved adaptation, not a sourced value)")
	if String(rates.get("reason", "")).strip_edges() == "":
		errors.append("drop_rates.json needs a reason")
	if not ValidationUtil.same(rates.get("rarities", null), RARITIES):
		errors.append("drop_rates.json rarities must be %s (Henesys.gg's labels), got %s" % [str(RARITIES), var_to_str(rates.get("rarities", null))])
	var table: Variant = rates.get("chance_table", null)
	if not (table is Dictionary):
		errors.append("drop_rates.json chance_table must be an object {category: {rarity: chance}}")
	else:
		for cat in CATEGORIES:
			var row: Variant = table.get(cat, null)
			if not (row is Dictionary):
				errors.append("drop_rates.json chance_table.%s is missing" % cat)
				continue
			for r in RARITIES:
				var v: Variant = row.get(r, null)
				if not ValidationUtil.is_number(v) or v is bool or is_nan(float(v)) or float(v) < 0.0 or float(v) > 1.0:
					errors.append("drop_rates.json chance_table.%s.%s must be a chance in [0, 1], got %s" % [cat, r, var_to_str(v)])
			for r in row:
				if not (str(r) in RARITIES):
					errors.append("drop_rates.json chance_table.%s.%s is not a rarity (%s)" % [cat, str(r), ", ".join(RARITIES)])
		for cat in table:
			if not (str(cat) in CATEGORIES):
				errors.append("drop_rates.json chance_table.%s is not a category (%s)" % [str(cat), ", ".join(CATEGORIES)])
	var rules: Variant = rates.get("category_rules", null)
	for cat in CATEGORIES:
		if not (rules is Dictionary) or not ValidationUtil.non_empty(rules.get(cat, null)):
			errors.append("drop_rates.json category_rules.%s must say which items the row covers" % cat)
	if not ValidationUtil.same(rates.get("quantity_per_drop", null), 1):
		errors.append("drop_rates.json quantity_per_drop must be 1 (decision %s; no source gives another), got %s" % [RATES_DECISION,
			var_to_str(rates.get("quantity_per_drop", null))])
	var prov: Variant = rates.get("provenance", null)
	var cite: Variant = prov.get("chance_table", null) if prov is Dictionary else null
	if not (cite is Dictionary) or not ValidationUtil.same(cite.get("authority", null), ProvenanceAuthorities.PROJECT_OWNER) \
			or not String(cite.get("decision", "")).contains(RATES_DECISION):
		errors.append("drop_rates.json provenance.chance_table must cite {\"authority\": \"%s\", \"decision\": \"%s ...\"}" % [
			ProvenanceAuthorities.PROJECT_OWNER, RATES_DECISION])
	return errors


## meso_rules.json: decision D3-12, verified false, a reason; amount_distribution is MESO_DISTRIBUTION; the level
## multipliers are whole numbers 1 <= min <= max; chance is a number in [0, 1]; no_mesos maps drop owner ids to
## {name, reason}; provenance.chance cites the project owner. Appends to `errors` and returns it.
static func validate_meso_rules(db: ContentDB, errors: PackedStringArray) -> PackedStringArray:
	var t: Variant = db.miso_table(MESO_FILE)
	if not (t is Dictionary):
		errors.append("data/misostory/meso_rules.json is missing (the meso rule, decision %s)" % MESO_DECISION)
		return errors
	var rules: Dictionary = t
	if not ValidationUtil.same(rules.get("decision", null), MESO_DECISION):
		errors.append("meso_rules.json decision must be \"%s\", got %s" % [MESO_DECISION, var_to_str(rules.get("decision", null))])
	if rules.get("verified") != false:
		errors.append("meso_rules.json must say verified: false (an owner-approved adaptation, not a sourced value)")
	if String(rules.get("reason", "")).strip_edges() == "":
		errors.append("meso_rules.json needs a reason")
	if not ValidationUtil.same(rules.get("amount_distribution", null), MESO_DISTRIBUTION):
		errors.append("meso_rules.json amount_distribution must be \"%s\" (what DropRoller implements)" % MESO_DISTRIBUTION)
	var lo: Variant = rules.get("amount_level_multiplier_min", null)
	var hi: Variant = rules.get("amount_level_multiplier_max", null)
	if not _whole(lo) or not _whole(hi) or int(lo) < 1 or int(hi) < int(lo):
		errors.append("meso_rules.json amount_level_multiplier_min / _max must be whole numbers 1 <= min <= max, got %s, %s" % [
			var_to_str(lo), var_to_str(hi)])
	var p: Variant = rules.get("chance", null)
	if not ValidationUtil.is_number(p) or p is bool or is_nan(float(p)) or float(p) < 0.0 or float(p) > 1.0:
		errors.append("meso_rules.json chance must be a number in [0, 1], got %s" % var_to_str(p))
	var none: Variant = rules.get("no_mesos", {})
	if not (none is Dictionary):
		errors.append("meso_rules.json no_mesos must be an object {owner id: {name, reason}}")
	else:
		for k in none:
			var row: Variant = none[k]
			if not (row is Dictionary) or not ValidationUtil.non_empty(row.get("reason", null)):
				errors.append("meso_rules.json no_mesos.%s must be {name, reason}" % str(k))
			if not db.has("drops", str(k)):
				errors.append("meso_rules.json no_mesos.%s names no drop owner (data/canonical/drops/%s.json)" % [str(k), str(k)])
	var prov: Variant = rules.get("provenance", null)
	var cite: Variant = prov.get("chance", null) if prov is Dictionary else null
	if not (cite is Dictionary) or not ValidationUtil.same(cite.get("authority", null), ProvenanceAuthorities.PROJECT_OWNER) \
			or not String(cite.get("decision", "")).contains(MESO_DECISION):
		errors.append("meso_rules.json provenance.chance must cite {\"authority\": \"%s\", \"decision\": \"%s ...\"}" % [
			ProvenanceAuthorities.PROJECT_OWNER, MESO_DECISION])
	return errors


static func _whole(v: Variant) -> bool:
	return ValidationUtil.is_number(v) and not (v is bool) and float(v) == floorf(float(v))
