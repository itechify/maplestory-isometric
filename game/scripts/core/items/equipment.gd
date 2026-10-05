class_name Equipment
extends RefCounted
## Equipped items by slot (weapon, hat, top, bottom, overall, shoes, gloves, cape, shield, earrings, and the remaining
## classic slots listed in data/misostory/inventory.json). CONTRACT: the class name, BONUS_KEYS and the signatures of
## item_in / total_bonuses / weapon_id / to_dict / from_dict are fixed (other systems call them).
##
## Each occupied slot holds {"item_id", "data"}: the same per-instance data the item had in the inventory, so a future
## scroll result survives equip/unequip. Requirements (level, job, total STR/DEX/INT/LUK, fame, gender) and slot
## conflicts (overall <-> top/bottom, two-handed weapon <-> shield) come from canonical item data plus the conflict
## rules in inventory.json. Pure: ItemService emits Events.equipment_changed.

## The stat-line keys every bonus dictionary uses (equipment totals, effects, the stat calculator).
const BONUS_KEYS: PackedStringArray = ["str", "dex", "int", "luk", "max_hp", "max_mp", "watk", "matk", "wdef",
	"mdef", "acc", "avoid", "speed", "jump"]
const SAVE_VERSION := 1

## slot -> {"item_id": String, "data": Dictionary}; only occupied slots are present.
var _slots: Dictionary = {}


# --- the fixed contract ---------------------------------------------------------------------------------------

## Canonical item id in a slot, or "" if empty.
func item_in(slot: String) -> String:
	return String(_slots[slot].item_id) if _slots.has(slot) else ""


## Sum of every equipped item's stat lines: every BONUS_KEYS key (missing = 0), plus the canonical stat rows outside
## BONUS_KEYS ("crit_rate_pct", "knockback_pct"; ItemDef.EXTRA_STAT_KEYS) only when an equipped piece has them, so
## StatCalculator (whose EXTRA_BONUS_KEYS include crit_rate_pct) picks up glove CRIT%. A piece whose per-instance data
## has "stats" (a future scroll result) uses those instead of the clean canonical stats.
func total_bonuses(db: ContentDB) -> Dictionary:
	var out := {}
	for k in BONUS_KEYS:
		out[k] = 0
	for slot in _slots:
		var stats := _piece_stats(slot, db)
		var b := ItemDef.bonuses_from_stats(stats)
		for k in BONUS_KEYS:
			out[k] = int(out[k]) + int(b.get(k, 0))
		for k in ItemDef.EXTRA_STAT_KEYS:
			if stats.has(k) and int(stats[k]) != 0:
				out[k] = int(out.get(k, 0)) + int(stats[k])
	return out


## The equipped weapon's item id, or "" when bare-handed.
func weapon_id() -> String:
	return item_in("weapon")


func to_dict() -> Dictionary:
	var slots := {}
	for slot in _slots:
		var e := {"item_id": _slots[slot].item_id}
		if not (_slots[slot].data as Dictionary).is_empty():
			e["data"] = (_slots[slot].data as Dictionary).duplicate(true)
		slots[slot] = e
	return {"version": SAVE_VERSION, "slots": slots}


static func from_dict(d: Dictionary) -> Equipment:
	var eq := Equipment.new()
	var slots: Variant = d.get("slots", {})
	if not (slots is Dictionary):
		return eq
	for slot in slots:
		var e: Variant = slots[slot]
		var item_id := ItemDef.id_of(e.get("item_id", "")) if e is Dictionary else ""
		if item_id == "":
			push_warning("[Equipment] skipping invalid saved slot '%s': %s" % [str(slot), str(e)])
			continue
		var data: Dictionary = Inventory.normalize_data(e.get("data", {}))
		eq._slots[str(slot)] = {"item_id": item_id, "data": data}
	return eq


# --- queries --------------------------------------------------------------------------------------------------

## Copy of a slot's piece: {"item_id", "data"}, or {} if empty.
func instance_in(slot: String) -> Dictionary:
	return (_slots[slot] as Dictionary).duplicate(true) if _slots.has(slot) else {}


## slot -> item id for every occupied slot.
func equipped() -> Dictionary:
	var out := {}
	for slot in _slots:
		out[slot] = String(_slots[slot].item_id)
	return out


func is_empty() -> bool:
	return _slots.is_empty()


## Every equipment slot name (data/misostory/inventory.json).
func all_slots(db: ContentDB = null) -> PackedStringArray:
	return ItemsConfig.equipment_slots(db)


## Bonuses outside BONUS_KEYS summed over equipped pieces, every ItemDef.EXTRA_STAT_KEYS key present (0 default).
func extra_bonuses(db: ContentDB) -> Dictionary:
	var out := {}
	var totals := total_bonuses(db)
	for k in ItemDef.EXTRA_STAT_KEYS:
		out[k] = int(totals.get(k, 0))
	return out


## The equipped weapon's typed view, or null when bare-handed.
func weapon_def(db: ContentDB) -> ItemDef:
	var w := weapon_id()
	return null if w == "" else ItemDef.of(w, db)


# --- requirements ---------------------------------------------------------------------------------------------

## True if the character meets every requirement of the item (see equip_check).
func can_equip(character: CharacterState, item_id: String, db: ContentDB) -> bool:
	return bool(equip_check(character, item_id, db).ok)


## Requirement check for wearing an item: {"ok", "code", ...details}. Codes: not_equipment, unknown_item,
## level_too_low {required, actual}, job_mismatch {required}, stat_too_low {stat, required, actual},
## fame_too_low {required, actual}, gender_mismatch {required}. Stats are TOTAL stats (StatCalculator.total_stat:
## base + equipment + effects), per MeowDB derived_stats ("Total stats include assigned Ability Points, equipment,
## and active effects. Equipment requirements only decide whether you can equip an item.").
func equip_check(character: CharacterState, item_id: String, db: ContentDB) -> Dictionary:
	var def := ItemDef.of(item_id, db)
	if def == null:
		return ItemCodes.result(ItemCodes.UNKNOWN_ITEM, {"item_id": item_id})
	if not def.is_equipment():
		return ItemCodes.result(ItemCodes.NOT_EQUIPMENT, {"item_id": item_id})
	if character.level < def.req_level:
		return ItemCodes.result(ItemCodes.LEVEL_TOO_LOW, {"item_id": item_id, "required": def.req_level,
			"actual": character.level})
	if not def.req_jobs.is_empty():
		var tags := ItemsConfig.job_item_tags(character.job, db)
		var ok := false
		for j in def.req_jobs:
			if j in tags:
				ok = true
		if not ok:
			return ItemCodes.result(ItemCodes.JOB_MISMATCH, {"item_id": item_id, "required": def.req_jobs})
	for stat in ItemDef.REQ_STAT_KEYS:
		var need := int(def.req_stats.get(stat, 0))
		if need <= 0:
			continue
		var have := StatCalculator.total_stat(character, stat, db)
		if have < need:
			return ItemCodes.result(ItemCodes.STAT_TOO_LOW, {"item_id": item_id, "stat": stat, "required": need,
				"actual": have})
	if def.req_fame > 0 and character.fame < def.req_fame:
		return ItemCodes.result(ItemCodes.FAME_TOO_LOW, {"item_id": item_id, "required": def.req_fame,
			"actual": character.fame})
	var gender := character_gender(character)
	if def.gender != "" and gender != "" and gender != def.gender:
		return ItemCodes.result(ItemCodes.GENDER_MISMATCH, {"item_id": item_id, "required": def.gender})
	return ItemCodes.result(ItemCodes.OK, {"item_id": item_id})


## The character's gender ("male" / "female"), or "" when unknown: CharacterState.gender, else the legacy
## flags["gender"]. Unknown skips the gender check.
static func character_gender(character: CharacterState) -> String:
	var g := character.gender
	if g == "":
		g = str(character.flags.get("gender", ""))
	return g.to_lower()


# --- equip / unequip ------------------------------------------------------------------------------------------

## Equips an item from the character's inventory (the slot at `inv_index` of the equip tab, else the first one
## holding `item_id`). The previous occupant and any conflicting pieces go back to the inventory; the first of them
## takes the slot the new item left. Result: {"ok", "code", "slot", "item_id", "unequipped": [item ids],
## "changed_slots": [slots]}; failures leave everything untouched.
func equip(character: CharacterState, item_id: String, db: ContentDB, inv_index: int = -1) -> Dictionary:
	var kind := ItemDef.of(item_id, db)
	if kind == null:
		return ItemCodes.result(ItemCodes.UNKNOWN_ITEM, {"item_id": item_id})
	if not kind.is_equipment():
		return ItemCodes.result(ItemCodes.NOT_EQUIPMENT, {"item_id": item_id})
	var inv := character.inventory
	var idx := inv_index
	if idx < 0:
		var at := inv.find(item_id)
		idx = int(at.get("index", -1)) if String(at.get("tab", "")) == "equip" else -1
	var stack := inv.get_slot("equip", idx)
	if stack.is_empty() or String(stack.item_id) != item_id:
		return ItemCodes.result(ItemCodes.NOT_ENOUGH_ITEMS, {"item_id": item_id})
	var check := equip_check(character, item_id, db)
	if not check.ok:
		return check
	var def := ItemDef.of(item_id, db)
	var slot := _target_slot(def.equip_slot, db)
	if slot == "":
		return ItemCodes.result(ItemCodes.UNKNOWN_SLOT, {"item_id": item_id, "slot": def.equip_slot})

	var vacate: PackedStringArray = []
	if _slots.has(slot):
		vacate.append(slot)
	for rule in ItemsConfig.slot_conflicts(db):
		if String(rule.get("slot", "")) != slot:
			continue
		if rule.get("if_two_handed") == true and not def.two_handed:
			continue
		for other in rule.get("removes", []):
			var o := String(other)
			if not _slots.has(o) or o in vacate:
				continue
			if rule.get("only_two_handed_occupant") == true:
				var occ := ItemDef.of(item_in(o), db)
				if occ == null or not occ.two_handed:
					continue
			vacate.append(o)
	# The incoming item frees its own inventory slot (when it is the last unit there; equipment is unstackable by
	# default, but the stack size is data), so N displaced pieces need N - 1 other free slots.
	var frees_own_slot := int(stack.get("qty", 1)) <= 1
	if vacate.size() > inv.free_slots("equip") + (1 if frees_own_slot else 0):
		return ItemCodes.result(ItemCodes.INVENTORY_FULL, {"item_id": item_id, "needed": vacate.size()})

	var taken := inv.remove_at("equip", idx, 1)
	var unequipped: Array = []
	for o in vacate:
		var piece: Dictionary = _slots[o]
		_slots.erase(o)
		var back := {"item_id": piece.item_id, "qty": 1, "data": piece.data}
		# The first displaced piece takes the slot the new item left; the rest take the first empty slots.
		var target := idx if inv.get_slot("equip", idx).is_empty() else inv.first_empty("equip")
		if not inv.put_at("equip", target, back):
			push_error("[Equipment] lost track of a free slot while unequipping %s" % piece.item_id)
		unequipped.append(str(piece.item_id))
	_slots[slot] = {"item_id": item_id, "data": (taken.get("data", {}) as Dictionary).duplicate(true)}
	var changed: Array = [slot]
	for o in vacate:
		if not (o in changed):
			changed.append(o)
	return ItemCodes.result(ItemCodes.OK, {"item_id": item_id, "slot": slot, "unequipped": unequipped,
		"changed_slots": changed})


## Unequips a slot into the first empty equip-tab slot. Result: {"ok", "code", "slot", "item_id", "index"};
## slot_empty or inventory_full on failure.
func unequip(character: CharacterState, slot: String, db: ContentDB = null) -> Dictionary:
	if not _slots.has(slot):
		var known := slot in ItemsConfig.equipment_slots(db)
		return ItemCodes.result(ItemCodes.SLOT_EMPTY if known else ItemCodes.UNKNOWN_SLOT, {"slot": slot})
	var inv := character.inventory
	var idx := inv.first_empty("equip")
	if idx < 0:
		return ItemCodes.result(ItemCodes.INVENTORY_FULL, {"slot": slot, "item_id": item_in(slot)})
	var piece: Dictionary = _slots[slot]
	inv.put_at("equip", idx, {"item_id": piece.item_id, "qty": 1, "data": piece.data})
	_slots.erase(slot)
	return ItemCodes.result(ItemCodes.OK, {"slot": slot, "item_id": String(piece.item_id), "index": idx})


## Puts an item straight into a slot without the inventory or requirement checks (new-character setup, debug,
## tests). Returns false for an unknown item or slot.
func force_equip(slot: String, item_id: String, db: ContentDB = null, data: Dictionary = {}) -> bool:
	if not (slot in ItemsConfig.equipment_slots(db)):
		return false
	if db != null and not db.has("items", item_id):
		return false
	_slots[slot] = {"item_id": item_id, "data": data.duplicate(true)}
	return true


func _target_slot(equip_slot: String, db: ContentDB) -> String:
	var known := ItemsConfig.equipment_slots(db)
	var options := ItemsConfig.slots_for(equip_slot, db)
	var first := ""
	for s in options:
		if not (s in known):
			continue
		if first == "":
			first = s
		if not _slots.has(s):
			return s
	return first


## The stat rows a piece contributes: its instance data's "stats" when present, else the clean canonical stats.
func _piece_stats(slot: String, db: ContentDB) -> Dictionary:
	var piece: Dictionary = _slots[slot]
	var data: Dictionary = piece.data
	if data.get("stats") is Dictionary:
		return data.stats
	var rec: Dictionary = db.item(String(piece.item_id)) if db != null else {}
	return rec.get("stats", {}) if rec.get("stats") is Dictionary else {}
