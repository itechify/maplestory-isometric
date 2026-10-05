class_name ItemService
extends RefCounted
## The one seam between the pure item rules and the event bus. Every gameplay change to a character's items, equipment
## or mesos should go through here so the HUD, quests, saves and UI hear about it:
##
##   var items := ItemService.new(Game.character, Data.db, Events)
##   items.gain("270", 5)          # pickups, quest rewards, debug grants
##   items.use_item("270")         # quickslots, inventory double-click
##   items.equip("541") / items.unequip("weapon")
##   items.gain_mesos(12) / items.spend_mesos(50)
##
## `bus` is any Object with the Events signals (the Events autoload in the game, a fresh events.gd instance in tests,
## or null to stay silent). The service never looks the bus up itself. The one autoload it may consult is Game, and only
## in use_item, to ask whether the live character is dead (Consumables.default_dead_check); set `dead_check` to keep
## it off the scene tree entirely.
##
## Signals emitted (all from scripts/autoload/events.gd):
##   item_gained(item_id, quantity)   after items enter the inventory (quantity actually added)
##   item_lost(item_id, quantity)     after items leave it (used, sold, handed in, discarded)
##   inventory_changed()              after any inventory change
##   inventory_full(item_id)          when an add or pickup did not fit (fully or partly)
##   item_used(item_id)               after a consumable was used
##   equipment_changed(slot)          once per slot that changed on equip/unequip
##   stats_changed()                  after equipment changed (derived stats may differ)
##   hp_changed(hp, max_hp) / mp_changed(mp, max_mp)   after a consumable or an unequip changed them
##   mesos_changed(mesos, delta)      after mesos changed

var character: CharacterState
var db: ContentDB
var bus: Object
## Injection seam for use_item's "is the player dead?" (see Consumables.is_dead): a zero-argument Callable returning
## true while dead. Invalid (the default) = Consumables.default_dead_check: the Game autoload's is_character_dead()
## when `character` is Game.character, else the canonical HP trigger alone.
var dead_check: Callable = Callable()


func _init(c: CharacterState, content: ContentDB, events_bus: Object = null) -> void:
	character = c
	db = content
	bus = events_bus


# --- items ----------------------------------------------------------------------------------------------------

## Adds up to `qty`; returns how many were added. Emits item_gained / inventory_changed, and inventory_full when not
## everything fit. An id that is not a canonical item adds nothing and emits nothing (a data bug, not a full bag).
func gain(item_id: String, qty: int) -> int:
	if qty <= 0:
		return 0
	if not db.has("items", item_id):
		push_warning("[ItemService] gain: unknown item id '%s'" % item_id)
		return 0
	var added := character.inventory.add(item_id, qty, db)
	if added > 0:
		_emit(&"item_gained", [item_id, added])
		_emit(&"inventory_changed")
	if added < qty:
		_emit(&"inventory_full", [item_id])
	return added


## True if `qty` of the item fits.
func can_gain(item_id: String, qty: int) -> bool:
	return character.inventory.can_add(item_id, qty, db)


## Adds every {item_id, qty|count} entry, or nothing at all when they do not all fit (emits inventory_full for the
## first entry that would not fit). Returns true on success; false (nothing added, nothing emitted) for a malformed
## entry or an unknown item id.
func gain_all(items: Array) -> bool:
	if not _all_entries(items):
		return false
	for e in items:
		if not db.has("items", ItemDef.id_of(e.get("item_id", ""))):
			push_warning("[ItemService] gain_all: unknown item id in %s" % str(e))
			return false
	if not character.inventory.can_add_all(items, db):
		var sim := Inventory.from_dict(character.inventory.to_dict())
		for e in items:
			var item_id := ItemDef.id_of(e.get("item_id", ""))
			var qty := Inventory.entry_qty(e)
			if sim.add(item_id, qty, db) != qty:
				_emit(&"inventory_full", [item_id])
				break
		return false
	for e in items:
		gain(ItemDef.id_of(e.get("item_id", "")), Inventory.entry_qty(e))
	return true


## Removes up to `qty`; returns how many were removed. Emits item_lost / inventory_changed.
func lose(item_id: String, qty: int) -> int:
	var removed := character.inventory.remove(item_id, qty)
	if removed > 0:
		_emit(&"item_lost", [item_id, removed])
		_emit(&"inventory_changed")
	return removed


## Removes every {item_id, qty|count} entry, or nothing when any is short (quest hand-ins). Returns true on success;
## false (nothing removed) for a malformed entry or a negative quantity.
func lose_all(items: Array) -> bool:
	if not _all_entries(items):
		return false
	var need := {}
	for e in items:
		var item_id := ItemDef.id_of(e.get("item_id", ""))
		need[item_id] = int(need.get(item_id, 0)) + Inventory.entry_qty(e)
	for item_id in need:
		if int(need[item_id]) < 0 or character.inventory.count(item_id) < int(need[item_id]):
			return false
	for item_id in need:
		lose(item_id, int(need[item_id]))
	return true


## Removes up to `qty` from one inventory slot (all of it when qty < 0); returns the removed stack or {}.
func lose_at(tab: String, index: int, qty: int = -1) -> Dictionary:
	var taken := character.inventory.remove_at(tab, index, qty)
	if not taken.is_empty():
		_emit(&"item_lost", [String(taken.item_id), int(taken.qty)])
		_emit(&"inventory_changed")
	return taken


## Empties one tab, or every tab when `tab` is "" (the debug console's "clear inventory"). Emits item_lost per item
## id and one inventory_changed. Returns {item_id: qty removed}.
func clear_inventory(tab: String = "") -> Dictionary:
	var removed := character.inventory.clear(tab)
	var ids: Array = removed.keys()
	ids.sort()
	for item_id in ids:
		_emit(&"item_lost", [String(item_id), int(removed[item_id])])
	if not removed.is_empty():
		_emit(&"inventory_changed")
	return removed


## Moves/merges/swaps two slots of a tab (the inventory window's drag and drop).
func move(tab: String, from_index: int, to_index: int) -> bool:
	var ok := character.inventory.move(tab, from_index, to_index, db)
	if ok and from_index != to_index:
		_emit(&"inventory_changed")
	return ok


## Picks up a ground drop. Accepts DropRoller output ({"kind": "mesos", "amount": n} / {"kind": "item", "item_id",
## "qty"}), DropRoller.ground_records, and the MapInstanceState record shape ({item_id | mesos, amount, ...}). A drop
## is mesos when its "kind" says so, or (no "kind") when it has a "mesos" key and no item id; an item record that
## also carries a "mesos" key stays an item. Items are all-or-nothing (Roger: "When your Item Inventory is full, you
## won't be able to pick up new items."); mesos add up to the cap. Result: {"ok", "code", ...}; the drop should stay
## on the ground unless ok.
func pickup(drop: Dictionary) -> Dictionary:
	if is_meso_drop(drop):
		var amount := quantity_of(drop.get("amount", drop.get("mesos", 0)))
		if amount <= 0:
			return ItemCodes.result(ItemCodes.INVALID_QUANTITY, {"amount": amount})
		var added := gain_mesos(amount)
		if added <= 0:
			return ItemCodes.result(ItemCodes.MESO_CAP, {"amount": amount})
		return ItemCodes.result(ItemCodes.OK, {"kind": "mesos", "amount": added})
	var item_id := ItemDef.id_of(drop.get("item_id", ""))
	var qty := quantity_of(drop.get("qty", drop.get("amount", 1)))
	if not db.has("items", item_id):
		return ItemCodes.result(ItemCodes.UNKNOWN_ITEM, {"item_id": item_id})
	if qty <= 0:
		return ItemCodes.result(ItemCodes.INVALID_QUANTITY, {"item_id": item_id})
	if not character.inventory.can_add(item_id, qty, db):
		_emit(&"inventory_full", [item_id])
		return ItemCodes.result(ItemCodes.INVENTORY_FULL, {"item_id": item_id, "qty": qty})
	gain(item_id, qty)
	return ItemCodes.result(ItemCodes.OK, {"kind": "item", "item_id": item_id, "qty": qty})


# --- consumables ----------------------------------------------------------------------------------------------

## Uses one consumable (see Consumables.use for the result and codes; `dead` follows dead_check). A refused use
## changes and emits nothing.
func use_item(item_id: String) -> Dictionary:
	var hp_before := character.hp
	var mp_before := character.mp
	var res := Consumables.use(character, item_id, db, dead_check)
	if not res.ok:
		return res
	_emit(&"item_used", [item_id])
	_emit(&"item_lost", [item_id, 1])
	_emit(&"inventory_changed")
	if character.hp != hp_before:
		_emit(&"hp_changed", [character.hp, int(res.max_hp)])
	if character.mp != mp_before:
		_emit(&"mp_changed", [character.mp, int(res.max_mp)])
	return res


# --- equipment ------------------------------------------------------------------------------------------------

## Equips from the inventory (see Equipment.equip).
func equip(item_id: String, inv_index: int = -1) -> Dictionary:
	var res := character.equipment.equip(character, item_id, db, inv_index)
	if res.ok:
		_after_equipment_change(res.changed_slots)
	return res


## Unequips a slot into the inventory (see Equipment.unequip).
func unequip(slot: String) -> Dictionary:
	var res := character.equipment.unequip(character, slot, db)
	if res.ok:
		_after_equipment_change([slot])
	return res


func _after_equipment_change(slots: Array) -> void:
	for s in slots:
		_emit(&"equipment_changed", [String(s)])
	_emit(&"inventory_changed")
	_emit(&"stats_changed")
	# Losing a Max HP/MP bonus clamps the current value.
	var max_hp := StatCalculator.max_hp(character, db)
	var max_mp := StatCalculator.max_mp(character, db)
	if character.hp > max_hp:
		character.hp = max_hp
		_emit(&"hp_changed", [character.hp, max_hp])
	if character.mp > max_mp:
		character.mp = max_mp
		_emit(&"mp_changed", [character.mp, max_mp])


# --- mesos ----------------------------------------------------------------------------------------------------

## Adds mesos up to the cap; returns how many were added. Emits mesos_changed.
func gain_mesos(amount: int) -> int:
	var added := Mesos.add(character, amount, db)
	if added > 0:
		_emit(&"mesos_changed", [character.mesos, added])
	return added


## Spends exactly `amount` (see Mesos.spend). Emits mesos_changed with a negative delta.
func spend_mesos(amount: int) -> Dictionary:
	var res := Mesos.spend(character, amount)
	if res.ok and amount > 0:
		_emit(&"mesos_changed", [character.mesos, -amount])
	return res


## True if a ground drop is a meso bag (see pickup for the rule).
static func is_meso_drop(drop: Dictionary) -> bool:
	var kind: Variant = drop.get("kind", null)
	if kind != null and str(kind) != "":
		return str(kind) == "mesos"
	return drop.has("mesos") and ItemDef.id_of(drop.get("item_id", "")) == ""


## A drop quantity from an untrusted Variant: numbers (JSON floats included) as ints, a numeric String parsed, a
## bool true as 1 (a {"mesos": true, "amount": n} record without its amount), anything else 0.
static func quantity_of(v: Variant) -> int:
	if v is int or v is float or v is bool:
		return int(v)
	if v is String and (v as String).is_valid_int():
		return (v as String).to_int()
	return 0


## True if every entry is a Dictionary (malformed quest/shop data never half-applies).
static func _all_entries(items: Array) -> bool:
	for e in items:
		if not (e is Dictionary):
			return false
	return true


func _emit(sig: StringName, args: Array = []) -> void:
	if bus == null or not bus.has_signal(sig):
		return
	bus.callv(&"emit_signal", [sig] + args)
