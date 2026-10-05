class_name ItemsConfig
extends RefCounted
## Reads the items adaptation table, data/misostory/inventory.json (tab sizes, equipment stack size, equipment slots
## and conflicts, weapon-subtype metadata, job tags, meso cap, shop behaviour). Every value there is a MisoStory
## adaptation with a reason, because MeowDB publishes none of it.
##
## Callers that have a ContentDB pass it, so tests and the game read the same loaded table. Callers that do not
## (Inventory.new() inside CharacterState) fall back to a cached read of the same file, the way WorldScale does.

const PATH := "res://data/misostory/inventory.json"

static var _file_table: Dictionary = {}


## The whole inventory.json table: from `db` when it has it, else from the file (cached).
static func table(db: ContentDB = null) -> Dictionary:
	if db != null:
		var t: Variant = db.miso_table("inventory")
		if t is Dictionary:
			return t
	if _file_table.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var parsed: Variant = JSON.parse_string(text) if text != "" else null
		if parsed is Dictionary:
			_file_table = parsed
		else:
			push_error("[ItemsConfig] cannot read %s" % PATH)
	return _file_table


## Default slot count per inventory tab (tab -> int).
static func tab_slots(db: ContentDB = null) -> Dictionary:
	var out := {}
	var src: Dictionary = table(db).get("tab_slots", {})
	for tab in Inventory.TABS:
		out[tab] = int(src.get(tab, 0))
	return out


static func equipment_max_stack(db: ContentDB = null) -> int:
	return int(table(db).get("equipment_max_stack", 1))


static func unpublished_max_stack(db: ContentDB = null) -> int:
	return int(table(db).get("unpublished_max_stack", 1))


## Meso cap, or -1 when the table sets none.
static func meso_cap(db: ContentDB = null) -> int:
	var v: Variant = table(db).get("meso_cap", null)
	return -1 if v == null else int(v)


## Every equipment slot name, in display order.
static func equipment_slots(db: ContentDB = null) -> PackedStringArray:
	return PackedStringArray(table(db).get("equipment_slots", []))


## Equipment slots a canonical equip_slot may go into (aliases such as "ring", else the slot itself).
static func slots_for(equip_slot: String, db: ContentDB = null) -> PackedStringArray:
	var aliases: Dictionary = table(db).get("slot_aliases", {})
	if aliases.has(equip_slot):
		return PackedStringArray(aliases[equip_slot])
	return PackedStringArray([equip_slot])


## Slot-conflict rules (see inventory.json slot_conflicts_reason).
static func slot_conflicts(db: ContentDB = null) -> Array:
	return table(db).get("slot_conflicts", [])


## Metadata for a MeowDB weapon subtype: {damage_family, multiplier_key, action_odds_key, two_handed}; {} if unknown.
static func weapon_subtype(subtype: String, db: ContentDB = null) -> Dictionary:
	return table(db).get("weapon_subtypes", {}).get(subtype, {})


## Item job strings ("Warrior", "Mage", ...) a job slug satisfies. A slug the table does not list (a later
## advancement such as "fighter") uses its base class from StatCalculator.JOBS, the one job registry.
static func job_item_tags(job_slug: String, db: ContentDB = null) -> PackedStringArray:
	var tags: Dictionary = table(db).get("job_item_tags", {})
	if tags.has(job_slug):
		return PackedStringArray(tags[job_slug])
	if StatCalculator.JOBS.has(job_slug):
		return PackedStringArray(tags.get(StatCalculator.job_class(job_slug), []))
	return PackedStringArray()


## A key of the "shop" section.
static func shop_rule(key: String, db: ContentDB = null) -> Variant:
	return table(db).get("shop", {}).get(key, null)
