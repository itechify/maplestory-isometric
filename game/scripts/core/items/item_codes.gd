class_name ItemCodes
extends RefCounted
## Result codes returned by the items, equipment, consumable, meso and shop rules. Every operation returns a
## Dictionary with at least {"ok": bool, "code": String}; the UI turns `code` (plus the details in the result) into a
## message, e.g. with ItemCodes.message(result).

const OK := "ok"
const UNKNOWN_ITEM := "unknown_item"
const UNKNOWN_SHOP := "unknown_shop"
const INVALID_QUANTITY := "invalid_quantity"
const INVENTORY_FULL := "inventory_full"
const NOT_ENOUGH_ITEMS := "not_enough_items"
const INSUFFICIENT_MESOS := "insufficient_mesos"
const MESO_CAP := "meso_cap"
const NOT_SOLD_HERE := "not_sold_here"
const CITIZENSHIP_REQUIRED := "citizenship_required"
const NO_SELL_PRICE := "no_sell_price"
const ZERO_VALUE_REFUSED := "zero_value_refused"
const NOT_EQUIPMENT := "not_equipment"
const UNKNOWN_SLOT := "unknown_slot"
const SLOT_EMPTY := "slot_empty"
const LEVEL_TOO_LOW := "level_too_low"
const JOB_MISMATCH := "job_mismatch"
const STAT_TOO_LOW := "stat_too_low"
const FAME_TOO_LOW := "fame_too_low"
const GENDER_MISMATCH := "gender_mismatch"
const NOT_USABLE := "not_usable"
const DEAD := "dead"

const _MESSAGES := {
	OK: "Done.",
	UNKNOWN_ITEM: "That item does not exist.",
	UNKNOWN_SHOP: "That shop does not exist.",
	INVALID_QUANTITY: "Please enter a valid quantity.",
	INVENTORY_FULL: "Your inventory is full.",
	NOT_ENOUGH_ITEMS: "You do not have enough of that item.",
	INSUFFICIENT_MESOS: "You do not have enough mesos.",
	MESO_CAP: "You cannot hold any more mesos.",
	NOT_SOLD_HERE: "This shop does not sell that item.",
	CITIZENSHIP_REQUIRED: "You need a higher citizenship grade to buy that.",
	NO_SELL_PRICE: "The shop will not buy that item.",
	ZERO_VALUE_REFUSED: "That item is worth nothing to the shop.",
	NOT_EQUIPMENT: "That item cannot be equipped.",
	UNKNOWN_SLOT: "There is no such equipment slot.",
	SLOT_EMPTY: "Nothing is equipped there.",
	LEVEL_TOO_LOW: "Your level is too low to equip that.",
	JOB_MISMATCH: "Your job cannot equip that.",
	STAT_TOO_LOW: "Your stats are too low to equip that.",
	FAME_TOO_LOW: "Your fame is too low to equip that.",
	GENDER_MISMATCH: "That item is for the other gender.",
	NOT_USABLE: "That item cannot be used.",
	DEAD: "You cannot do that while dead.",
}


## A result Dictionary: {"ok": code == OK, "code": code} merged with `details`.
static func result(code: String, details: Dictionary = {}) -> Dictionary:
	var out := details.duplicate()
	out["ok"] = code == OK
	out["code"] = code
	return out


## Plain-English default message for a result (or a bare code string).
static func message(res: Variant) -> String:
	var code: String = String(res.get("code", "")) if res is Dictionary else String(res)
	return String(_MESSAGES.get(code, code))
