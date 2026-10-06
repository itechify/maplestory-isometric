class_name ItemDef
extends RefCounted
## Typed, read-only view of one canonical item (data/canonical/items/<id>.json, MeowDB MS Classic).
##
## Every number comes from the canonical record; the only adaptation values (equipment stack size, the fallback stack
## for an unpublished max_stack, weapon two-handedness and formula keys) come from data/misostory/inventory.json via
## ItemsConfig. Build one with ItemDef.of(item_id, db); it returns null for an unknown id.

## Canonical stat-row key -> Equipment.BONUS_KEYS key. Canonical "hp"/"mp" are Max HP/Max MP bonuses.
const STAT_TO_BONUS := {
	"str": "str", "dex": "dex", "int": "int", "luk": "luk", "hp": "max_hp", "mp": "max_mp", "watk": "watk",
	"matk": "matk", "wdef": "wdef", "mdef": "mdef", "acc": "acc", "avoid": "avoid", "speed": "speed", "jump": "jump",
}
## Canonical stat rows that are real bonuses but not BONUS_KEYS (exposed through extra_stats).
const EXTRA_STAT_KEYS: PackedStringArray = ["crit_rate_pct", "knockback_pct"]
const REQ_STAT_KEYS: PackedStringArray = ["str", "dex", "int", "luk"]

var id: String = ""
var name: String = ""
## MeowDB type ("Equip", "Use", "Setup", "Etc") and subtype ("Potion", "One-Handed Sword", ...; "" when none).
var type: String = ""
var subtype: String = ""
## Inventory tab (Inventory.TABS), from the canonical inventory_tab.
var tab: String = ""
## Canonical equip slot ("weapon", "hat", ...), "" for non-equipment.
var equip_slot: String = ""
var max_stack: int = 1
var quest_item: bool = false
var tradeable: bool = true
## "male", "female" or "" (any / not equipment).
var gender: String = ""
var description: String = ""

## Requirements: level (0 = none), allowed job strings (empty = any job, Beginner included), stats, fame.
var req_level: int = 0
var req_jobs: PackedStringArray = []
var req_stats: Dictionary = {"str": 0, "dex": 0, "int": 0, "luk": 0}
var req_fame: int = 0

## Every Equipment.BONUS_KEYS key -> int (0 when the item gives none).
var bonuses: Dictionary = {}
## Bonuses outside BONUS_KEYS: {"crit_rate_pct", "knockback_pct"} (only keys the item has).
var extra_stats: Dictionary = {}
var upgrade_slots: int = 0

## Consumable effects. Flat HP/MP, percentage HP/MP (no item in the current set), pet fullness, buffs as data.
var hp_flat: int = 0
var mp_flat: int = 0
var hp_pct: float = 0.0
var mp_pct: float = 0.0
var pet_fullness: int = 0
var buffs: Array = []

## Cheapest NPC price anywhere (-1 = not sold by NPCs). Shop rows carry the per-shop price.
var buy_price: int = -1
## NPC sell-back in mesos (-1 = MeowDB has no value); "per_unit" or "per_item".
var sell_price: int = -1
var sell_basis: String = ""

## Weapon data ("" / 0 / {} for non-weapons).
var weapon_type: String = ""
## Keys into formulas/damage.json: physical.weapon_families, weapon_action_multipliers, ordinary_action_odds.
var damage_family: String = ""
var multiplier_key: String = ""
var action_odds_key: String = ""
var two_handed: bool = false
## Speed tier (lower is faster) and MeowDB's label.
var attack_speed: int = 0
var attack_speed_name: String = ""
## Per-action weapon multipliers ({"swing": 1.8, "stab": 1.8} or bow {"firing", "close_range"}).
var multipliers: Dictionary = {}
## Chance of each basic-attack action ({"swing": 60, "stab": 40}); {} when MeowDB gives none (bow).
var action_mix_pct: Dictionary = {}
var attack_cycle_ms: int = 0
var basic_attacks: Array = []

## Chair data (Setup items): the canonical setup block. A Setup item with one is a chair (is_chair(), contract C5):
## sitting on it restores an extra setup_hp_bonus HP every setup_interval_s seconds (Chairs, NaturalRecoveryRule).
var setup_hp_bonus: int = 0
var setup_interval_s: float = 0.0
var has_setup: bool = false

## Scroll block, verbatim (no scroll system yet).
var scroll: Dictionary = {}
## The canonical record itself (read-only by convention).
var raw: Dictionary = {}


## The item's typed view, or null when the id is not in the canonical items domain.
static func of(item_id: String, db: ContentDB) -> ItemDef:
	if db == null or not db.has("items", item_id):
		return null
	return from_record(db.item(item_id), db)


## Builds the view from a canonical record (db is only used for the adaptation table).
static func from_record(rec: Dictionary, db: ContentDB = null) -> ItemDef:
	var d := ItemDef.new()
	d.raw = rec
	d.id = id_of(rec.get("id", ""))
	d.name = _s(rec.get("name", ""))
	d.type = _s(rec.get("type"))
	d.subtype = _s(rec.get("subtype"))
	d.tab = _s(rec.get("inventory_tab"))
	d.equip_slot = _s(rec.get("equip_slot"))
	d.quest_item = rec.get("quest_item") == true
	d.tradeable = rec.get("tradeable") != false
	d.description = _s(rec.get("description"))
	var g := _s(rec.get("gender"))
	d.gender = "" if g == "any" else g

	if d.tab == "equip":
		d.max_stack = ItemsConfig.equipment_max_stack(db)
	elif rec.get("max_stack") != null:
		d.max_stack = maxi(1, int(rec.get("max_stack")))
	else:
		d.max_stack = ItemsConfig.unpublished_max_stack(db)

	var req: Dictionary = _dict(rec.get("requirements"))
	d.req_level = int(_n(req.get("level")))
	d.req_fame = int(_n(req.get("fame")))
	d.req_stats = {}
	for k in REQ_STAT_KEYS:
		d.req_stats[k] = int(_n(req.get(k)))
	var jobs: Variant = req.get("job")
	d.req_jobs = PackedStringArray(jobs) if jobs is Array else PackedStringArray()

	var stats: Dictionary = _dict(rec.get("stats"))
	d.bonuses = bonuses_from_stats(stats)
	d.extra_stats = {}
	for k in EXTRA_STAT_KEYS:
		if stats.has(k):
			d.extra_stats[k] = int(_n(stats[k]))
	d.upgrade_slots = int(_n(stats.get("upgrade_slots")))

	var cons: Dictionary = _dict(rec.get("consumable"))
	d.hp_flat = int(_n(cons.get("hp_restore")))
	d.mp_flat = int(_n(cons.get("mp_restore")))
	d.hp_pct = float(_n(cons.get("hp_restore_pct")))
	d.mp_pct = float(_n(cons.get("mp_restore_pct")))
	d.pet_fullness = int(_n(cons.get("pet_fullness_restore")))
	var b: Variant = cons.get("buffs")
	d.buffs = (b as Array).duplicate(true) if b is Array else []

	d.buy_price = -1 if rec.get("npc_buy_price_mesos") == null else int(rec.get("npc_buy_price_mesos"))
	d.sell_price = -1 if rec.get("sell_price_mesos") == null else int(rec.get("sell_price_mesos"))
	d.sell_basis = _s(rec.get("sell_price_basis"))

	var w: Dictionary = _dict(rec.get("weapon"))
	if not w.is_empty():
		d.weapon_type = _s(w.get("weapon_type"))
		if d.weapon_type == "":
			d.weapon_type = d.subtype
		var meta := ItemsConfig.weapon_subtype(d.weapon_type, db)
		d.damage_family = String(meta.get("damage_family", ""))
		d.multiplier_key = String(meta.get("multiplier_key", ""))
		d.action_odds_key = String(meta.get("action_odds_key", ""))
		d.two_handed = meta.get("two_handed") == true
		d.attack_speed = int(_n(w.get("attack_speed")))
		d.attack_speed_name = _s(w.get("attack_speed_name"))
		d.multipliers = _dict(w.get("multipliers")).duplicate()
		d.action_mix_pct = _dict(w.get("basic_attack_mix_pct")).duplicate()
		d.attack_cycle_ms = int(_n(w.get("attack_cycle_ms")))
		var atk: Variant = w.get("basic_attacks")
		d.basic_attacks = (atk as Array).duplicate(true) if atk is Array else []

	var st: Dictionary = _dict(rec.get("setup"))
	d.setup_hp_bonus = int(_n(st.get("hp_recovery_bonus")))
	d.setup_interval_s = float(_n(st.get("interval_s")))
	d.has_setup = not st.is_empty()
	d.scroll = _dict(rec.get("scroll")).duplicate(true)
	return d


## Maps a canonical stat dictionary ({"watk": 17, "hp": 5, ...}) to every BONUS_KEYS key (0 when absent).
static func bonuses_from_stats(stats: Dictionary) -> Dictionary:
	var out := {}
	for k in Equipment.BONUS_KEYS:
		out[k] = 0
	for k in stats:
		var bk: String = STAT_TO_BONUS.get(k, "")
		if bk != "":
			out[bk] = int(out[bk]) + int(_n(stats[k]))
	return out


func is_equipment() -> bool:
	return tab == "equip" and equip_slot != ""


func is_weapon() -> bool:
	return equip_slot == "weapon"


func is_stackable() -> bool:
	return max_stack > 1


## True for items the consumable system can use (HP/MP restore or a buff). Pet food needs a pet and is excluded.
func is_consumable() -> bool:
	return tab == "use" and (hp_flat > 0 or mp_flat > 0 or hp_pct > 0.0 or mp_pct > 0.0 or not buffs.is_empty())


## True for chairs: Setup-tab items with canonical setup data (The Green Relaxer, 522). Using one sits the player down.
func is_chair() -> bool:
	return tab == "setup" and has_setup


func untradeable() -> bool:
	return not tradeable


## Non-zero bonus lines only ({"watk": 17}), for tooltips.
func stat_lines() -> Dictionary:
	var out := {}
	for k in bonuses:
		if int(bonuses[k]) != 0:
			out[k] = bonuses[k]
	for k in extra_stats:
		out[k] = extra_stats[k]
	return out


## A canonical item id from an untrusted Variant (a save file, a quest/shop entry, a drop record). null gives "", a
## whole-number float (JSON's only number type) gives "541", anything else str(v). Never fails on a non-String, so a
## hand-edited or migrated save with numeric ids still loads.
static func id_of(v: Variant) -> String:
	if v == null:
		return ""
	if v is String or v is StringName:
		return String(v)
	if v is float:
		var f: float = v
		if is_finite(f) and f == floorf(f) and absf(f) < 9.0e15:
			return str(int(f))
	return str(v)


static func _s(v: Variant) -> String:
	return "" if v == null else str(v)


static func _n(v: Variant) -> float:
	return 0.0 if v == null else float(v)


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}
