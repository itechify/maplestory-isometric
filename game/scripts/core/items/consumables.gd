class_name Consumables
extends RefCounted
## Using a Use-tab item (potions, food): restores the canonical HP/MP (items domain consumable.hp_restore /
## mp_restore, flat; percentage effects are supported for future items), clamped to StatCalculator.max_hp / max_mp,
## and consumes one unit from the inventory. Buff effects are carried as data on ItemDef.buffs; no Maple Island item
## has one, so they are returned for the effect system rather than applied here.
##
## Pure: ItemService.use_item wraps this and emits Events.item_used, item_lost, inventory_changed, hp/mp_changed.
## Classic behaviour kept: a potion used at full HP is still consumed (it restores 0).


## Uses one `item_id` from the character's inventory. Result: {"ok", "code", "item_id", "hp_gained", "mp_gained",
## "hp", "mp", "max_hp", "max_mp", "buffs"}. Codes: unknown_item, not_enough_items, not_usable (not an HP/MP/buff
## consumable, e.g. Pet Food without a pet, scrolls, equipment), dead (HP is 0).
static func use(character: CharacterState, item_id: String, db: ContentDB) -> Dictionary:
	var def := ItemDef.of(item_id, db)
	if def == null:
		return ItemCodes.result(ItemCodes.UNKNOWN_ITEM, {"item_id": item_id})
	if not def.is_consumable():
		return ItemCodes.result(ItemCodes.NOT_USABLE, {"item_id": item_id})
	if character.inventory.count(item_id) <= 0:
		return ItemCodes.result(ItemCodes.NOT_ENOUGH_ITEMS, {"item_id": item_id})
	if character.hp <= 0:
		return ItemCodes.result(ItemCodes.DEAD, {"item_id": item_id})
	var max_hp := StatCalculator.max_hp(character, db)
	var max_mp := StatCalculator.max_mp(character, db)
	var gain := preview(def, character, max_hp, max_mp)
	character.inventory.remove(item_id, 1)
	character.hp += int(gain.hp)
	character.mp += int(gain.mp)
	return ItemCodes.result(ItemCodes.OK, {"item_id": item_id, "hp_gained": int(gain.hp), "mp_gained": int(gain.mp),
		"hp": character.hp, "mp": character.mp, "max_hp": max_hp, "max_mp": max_mp, "buffs": def.buffs.duplicate(true)})


## What the item would restore right now: {"hp": int, "mp": int}, already clamped to the maxima.
static func preview(def: ItemDef, character: CharacterState, max_hp: int, max_mp: int) -> Dictionary:
	var hp_amount := def.hp_flat + int(floor(max_hp * def.hp_pct / 100.0))
	var mp_amount := def.mp_flat + int(floor(max_mp * def.mp_pct / 100.0))
	return {
		"hp": clampi(hp_amount, 0, maxi(0, max_hp - character.hp)),
		"mp": clampi(mp_amount, 0, maxi(0, max_mp - character.mp)),
	}
