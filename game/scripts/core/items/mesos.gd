class_name Mesos
extends RefCounted
## Meso rules on CharacterState.mesos: never negative, never past the cap in data/misostory/inventory.json (MeowDB
## documents no cap; see meso_cap_reason). Pure: ItemService emits Events.mesos_changed.


## The meso cap, or -1 for none.
static func cap(db: ContentDB = null) -> int:
	return ItemsConfig.meso_cap(db)


## How many mesos can still be added before the cap.
static func room(character: CharacterState, db: ContentDB = null) -> int:
	var c := cap(db)
	return 0x7FFFFFFFFFFFFFFF if c < 0 else maxi(0, c - character.mesos)


static func can_afford(character: CharacterState, amount: int) -> bool:
	return amount >= 0 and character.mesos >= amount


## True if `amount` can be added without passing the cap.
static func can_add(character: CharacterState, amount: int, db: ContentDB = null) -> bool:
	return amount >= 0 and amount <= room(character, db)


## Adds mesos, clamped at the cap. Returns how many were added (0 for a negative amount).
static func add(character: CharacterState, amount: int, db: ContentDB = null) -> int:
	if amount <= 0:
		return 0
	var added := mini(amount, room(character, db))
	character.mesos += added
	return added


## Spends exactly `amount`. Result: {"ok", "code", "spent", "mesos"}; invalid_quantity for a negative amount,
## insufficient_mesos when the character cannot afford it (nothing is spent).
static func spend(character: CharacterState, amount: int) -> Dictionary:
	if amount < 0:
		return ItemCodes.result(ItemCodes.INVALID_QUANTITY, {"spent": 0, "mesos": character.mesos})
	if character.mesos < amount:
		return ItemCodes.result(ItemCodes.INSUFFICIENT_MESOS, {"spent": 0, "mesos": character.mesos,
			"required": amount})
	character.mesos -= amount
	return ItemCodes.result(ItemCodes.OK, {"spent": amount, "mesos": character.mesos})
