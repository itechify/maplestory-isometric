class_name MisoUiText
extends RefCounted
## Player-facing wording shared by the HUD and the windows: item/equipment result messages with their details,
## stat names, the classic "You have gained ..." log lines and quest objective rows. Presentation only.

## Stat-window names of base stats.
const STAT_NAMES := {"str": "STR", "dex": "DEX", "int": "INT", "luk": "LUK"}


## A message for an ItemService / Equipment / Consumables result, with its details where they help.
static func result_message(res: Dictionary, db: ContentDB = null) -> String:
	var code := String(res.get("code", ""))
	match code:
		ItemCodes.LEVEL_TOO_LOW:
			if bool(res.get("chair", false)):
				return "You need to be level %d to sit on that chair." % int(res.get("required", 0))
			return "You need to be level %d to equip that." % int(res.get("required", 0))
		ItemCodes.STAT_TOO_LOW:
			return "You need %d %s to equip that (you have %d)." % [int(res.get("required", 0)),
				STAT_NAMES.get(String(res.get("stat", "")), String(res.get("stat", "")).to_upper()), int(res.get("actual", 0))]
		ItemCodes.FAME_TOO_LOW:
			return "You need %d fame to equip that." % int(res.get("required", 0))
		ItemCodes.JOB_MISMATCH:
			var req: Variant = res.get("required", [])
			var jobs := ", ".join(PackedStringArray(req)) if req is Array or req is PackedStringArray else str(req)
			return "Only a %s can equip that." % jobs if jobs != "" else ItemCodes.message(res)
		ItemCodes.INVENTORY_FULL:
			return "Your Equip inventory is full." if res.has("slot") else ItemCodes.message(res)
		ItemCodes.NOT_USABLE:
			var id := String(res.get("item_id", ""))
			if db != null and db.has("items", id):
				return "%s cannot be used." % String(db.item(id).get("name", id))
		ShopService.QUEST_ITEM_NEEDED:
			var qid := String(res.get("item_id", ""))
			var item_name := String(db.item(qid).get("name", qid)) if db != null else qid
			return "%s is needed for %s (keep %d). The shop will not buy it while the quest is in progress." % [
				item_name, String(res.get("quest_name", res.get("quest_id", "a quest"))), int(res.get("needed", 1))]
		ShopService.PROTECTED_ITEM:
			var pid := String(res.get("item_id", ""))
			var protected_name := String(db.item(pid).get("name", pid)) if db != null else pid
			return "%s cannot be obtained again. The shop will not buy it." % protected_name
	return ItemCodes.message(res)


## "You have gained an item (Red Potion)" / "(Snail Shell x3)".
static func item_gained_line(item_name: String, qty: int) -> String:
	return "You have gained an item (%s%s)" % [item_name, " x%d" % qty if qty > 1 else ""]


static func exp_gained_line(amount: int) -> String:
	return "You have gained experience (+%s)" % MisoTheme.thousands(amount)


static func mesos_gained_line(amount: int) -> String:
	return "You have gained mesos (+%s)" % MisoTheme.thousands(amount)


## One quest objective row as the quest log shows it ("Snail 7/10", "Talk to Mai", "Return to Roger"). A turn-in
## talk says "Return to" only when the row's "met" is true (QuestEngine.npc_met: the player has dealt with that NPC
## before); 1006 sends a new Beginner from Sam to Mai, whom they have never met, so it reads "Talk to Mai".
static func objective_text(row: Dictionary) -> String:
	var name := String(row.get("name", row.get("id", "")))
	var cur := int(row.get("current", 0))
	var req := int(row.get("required", 0))
	match String(row.get("kind", "")):
		"monster_kills", "item_collection":
			return "%s %d/%d" % [name, mini(cur, req), req]
		"item_usage":
			return "Use %s %d/%d" % [name, mini(cur, req), req]
		"npc_talk":
			if String(row.get("purpose", "")) == "turn_in" and bool(row.get("met", false)):
				return "Return to %s" % name
			return "Talk to %s" % name
		"map_visit":
			return "Visit %s" % name
		"other":
			if String(row.get("type", "")) == "quiz":
				return "Answer the quiz"
			return name if name != "" else String(row.get("type", "Objective"))
	return name
