class_name DropRates
extends RefCounted
## Resolves the placeholder drop chances, quantities and meso amounts in data/misostory/drop_rates.json against the
## canonical drop tables (data/canonical/drops/<owner id>.json), plus the ground rules in data/misostory/drops.json.
## MeowDB publishes the drop LISTS only; every chance/quantity/meso number resolved here is a labelled placeholder.
##
## Pure and read-only. Every resolved value carries a "source" string saying which level of drop_rates.json it came
## from, so debug overlays and tests can show exactly why an item drops at a given rate.


static func _rates(db: ContentDB) -> Dictionary:
	var t: Variant = db.miso_table("drop_rates")
	return t if t is Dictionary else {}


static func _ground(db: ContentDB) -> Dictionary:
	var t: Variant = db.miso_table("drops")
	return t if t is Dictionary else {}


## True if a canonical drop table exists for this owner (monster id or breakable id).
static func has_table(owner_id: String, db: ContentDB) -> bool:
	return db.has("drops", owner_id)


## "monster", "breakable" or "" (read from the table's owner block, never from the id).
static func owner_kind(owner_id: String, db: ContentDB) -> String:
	return String(db.drop_table(owner_id).get("owner", {}).get("kind", ""))


## Every canonical entry of the owner's table with its resolved rate, in canonical order:
## {"item_id", "status", "disputed", "chance", "min_quantity", "max_quantity", "excluded" (reason or ""),
##  "source" (where chance came from)}. Excluded entries have chance 0 and are never rolled.
static func effective_entries(owner_id: String, db: ContentDB) -> Array:
	var out: Array = []
	var rates := _rates(db)
	var table := db.drop_table(owner_id)
	var overrides: Dictionary = rates.get("owner_item_overrides", {}).get(owner_id, {})
	var item_overrides: Dictionary = rates.get("item_overrides", {})
	var status_rules: Dictionary = rates.get("status_rules", {})
	var disputed_rule: Dictionary = rates.get("disputed_entries", {})
	var global_mult := float(rates.get("global_rate_multiplier", 1.0))
	for e in table.get("entries", []):
		var item_id := String(e.get("item_id", ""))
		var status := String(e.get("status", ""))
		var disputed: bool = e.get("disputed") == true
		var row := {"item_id": item_id, "status": status, "disputed": disputed, "chance": 0.0, "min_quantity": 1,
			"max_quantity": 1, "excluded": "", "source": ""}
		var rec := db.item(item_id)
		if rec.is_empty():
			row.excluded = "unknown_item"
			out.append(row)
			continue
		var chain: Array = []
		var names: PackedStringArray = []
		var override_level: Variant = overrides.get(item_id, null)
		if override_level is Dictionary:
			chain.append(override_level)
			names.append("owner_item_overrides.%s.%s" % [owner_id, item_id])
		var item_level: Variant = item_overrides.get(item_id, null)
		if item_level is Dictionary:
			chain.append(item_level)
			names.append("item_overrides.%s" % item_id)
		var type_name := String(rec.get("type", "")) if rec.get("type") != null else ""
		var subtype_name := String(rec.get("subtype", "")) if rec.get("subtype") != null else ""
		var sub_key := "%s/%s" % [type_name, subtype_name]
		var sub_level: Variant = rates.get("subtype_rates", {}).get(sub_key, null)
		if sub_level is Dictionary:
			chain.append(sub_level)
			names.append("subtype_rates.%s" % sub_key)
		var type_level: Variant = rates.get("type_rates", {}).get(type_name, null)
		if type_level is Dictionary:
			chain.append(type_level)
			names.append("type_rates.%s" % type_name)
		chain.append(rates.get("default_rate", {}))
		names.append("default_rate")

		var chance := 0.0
		for i in chain.size():
			if (chain[i] as Dictionary).has("chance"):
				chance = float(chain[i].chance)
				row.source = names[i]
				break
		for field in ["min_quantity", "max_quantity"]:
			for level in chain:
				if (level as Dictionary).has(field):
					row[field] = maxi(1, int(level[field]))
					break
		row.max_quantity = maxi(int(row.min_quantity), int(row.max_quantity))

		var is_override := override_level is Dictionary or item_level is Dictionary
		if not is_override:
			var rule: Dictionary = status_rules.get(status, {})
			if rule.get("enabled") != true:
				row.excluded = "status:%s" % status
			elif disputed and disputed_rule.get("enabled") != true:
				row.excluded = "disputed"
			else:
				chance *= float(rule.get("rate_multiplier", 1.0))
		row.chance = 0.0 if row.excluded != "" else clampf(chance * global_mult, 0.0, 1.0)
		out.append(row)
	return out


## The meso rule for an owner: {"chance", "min", "max", "source"}; chance 0 when the owner drops no mesos.
static func meso_rule(owner_id: String, db: ContentDB) -> Dictionary:
	var cfg: Dictionary = _rates(db).get("mesos", {})
	var table := db.drop_table(owner_id)
	var canon: Dictionary = table.get("meso", {}) if table.get("meso") is Dictionary else {}
	var out := {"chance": 0.0, "min": 0, "max": 0, "source": ""}
	if table.is_empty() or owner_kind(owner_id, db) != "monster" or String(canon.get("status", "")) == "not_applicable":
		out.source = "no_mesos"
		return out
	out.chance = float(cfg.get("chance", 0.0))
	var sources: PackedStringArray = ["mesos.chance"]
	if cfg.get("use_player_reports") == true and str(canon.get("status", "")) == "player_reports" \
			and canon.get("median_min") != null and canon.get("median_max") != null:
		out.min = int(canon.median_min)
		out.max = int(canon.median_max)
		sources.append("canonical player reports")
	else:
		var level := int(db.monster(owner_id).get("level", 1))
		var per: Dictionary = cfg.get("per_level", {})
		out.min = maxi(1, int(floor(level * float(per.get("min", 0.0)))))
		out.max = maxi(int(out.min), int(ceil(level * float(per.get("max", 0.0)))))
		sources.append("mesos.per_level")
	var by_owner: Variant = cfg.get("by_owner", {}).get(owner_id, null)
	if by_owner is Dictionary:
		for k in ["chance", "min", "max"]:
			if by_owner.has(k):
				out[k] = float(by_owner[k]) if k == "chance" else int(by_owner[k])
		sources.append("mesos.by_owner.%s" % owner_id)
	out.chance = clampf(float(out.chance), 0.0, 1.0)
	out.max = maxi(int(out.min), int(out.max))
	out.source = ", ".join(sources)
	return out


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


## Problems in drop_rates.json: overrides naming an unknown owner or an item not on that owner's table, missing
## reasons / verified flags, chances outside [0, 1]. Empty when everything is consistent.
static func validate(db: ContentDB) -> PackedStringArray:
	var errors: PackedStringArray = []
	var rates := _rates(db)
	if rates.is_empty():
		errors.append("data/misostory/drop_rates.json is missing")
		return errors
	if rates.get("verified") != false:
		errors.append("drop_rates.json must say verified: false")
	var levels: Array = [["default_rate", rates.get("default_rate", {})]]
	for key in ["type_rates", "subtype_rates", "item_overrides"]:
		var section: Dictionary = rates.get(key, {})
		for k in section:
			levels.append(["%s.%s" % [key, k], section[k]])
	var owners: Dictionary = rates.get("owner_item_overrides", {})
	for owner_id in owners:
		if not has_table(owner_id, db):
			errors.append("owner_item_overrides.%s: no canonical drop table" % owner_id)
			continue
		var listed := {}
		for e in db.drop_table(owner_id).get("entries", []):
			listed[String(e.get("item_id", ""))] = true
		for item_id in owners[owner_id]:
			if not listed.has(item_id):
				errors.append("owner_item_overrides.%s.%s: item not on that drop table" % [owner_id, item_id])
			levels.append(["owner_item_overrides.%s.%s" % [owner_id, item_id], owners[owner_id][item_id]])
	for item_id in rates.get("item_overrides", {}):
		if not db.has("items", item_id):
			errors.append("item_overrides.%s: unknown item" % item_id)
	var by_owner: Dictionary = rates.get("mesos", {}).get("by_owner", {})
	for owner_id in by_owner:
		if not has_table(owner_id, db):
			errors.append("mesos.by_owner.%s: no canonical drop table" % owner_id)
		levels.append(["mesos.by_owner.%s" % owner_id, by_owner[owner_id]])
	levels.append(["mesos", rates.get("mesos", {})])
	levels.append(["mesos.per_level", rates.get("mesos", {}).get("per_level", {})])
	for s in rates.get("status_rules", {}):
		levels.append(["status_rules.%s" % s, rates.status_rules[s]])
	levels.append(["disputed_entries", rates.get("disputed_entries", {})])
	for pair in levels:
		var where: String = pair[0]
		var level: Variant = pair[1]
		if not (level is Dictionary):
			errors.append("%s: not an object" % where)
			continue
		if String(level.get("reason", "")).strip_edges() == "":
			errors.append("%s: missing reason" % where)
		if level.get("verified") != false:
			errors.append("%s: must say verified: false" % where)
		if level.has("chance") and (float(level.chance) < 0.0 or float(level.chance) > 1.0):
			errors.append("%s: chance outside [0, 1]" % where)
	return errors
