class_name QuestItemGuard
extends RefCounted
## Which quest-critical items an in-progress quest still needs, so a shop never buys them (adaptation
## data/misostory/quests/_quest_items.json "block_selling_needed_quest_items"; MeowDB documents no sell restriction).
## Pure and static: ShopService.quote_sell asks it with the character and the content.
##
## An item is held back for a quest when the quest is in progress, an unfinished objective names it (item_collection:
## its count; item_usage: the uses still to make) and the item is quest-critical: canonical quest_item true, tradeable
## false, or handed over by that quest on accept. Copies above what the quests need stay sellable.

const RULES_FILE_ID := "_quest_items"


## True when the adaptation switches the guard on (absent file or key: on, the safe default).
static func enabled(db: ContentDB) -> bool:
	if db == null:
		return false
	var rule := QuestJson.dict(db.miso_entity("quests", RULES_FILE_ID).get("block_selling_needed_quest_items"))
	return QuestJson.b(rule.get("value"), true)


## How many of `item_id` the character's in-progress quests still need it to keep:
## {"needed": int, "quest_id": String (the first such quest), "quest_name": String}. needed 0 = nothing held back.
static func needed(character: CharacterState, item_id: String, db: ContentDB) -> Dictionary:
	var out := {"needed": 0, "quest_id": "", "quest_name": ""}
	if character == null or not enabled(db):
		return out
	var item := db.item(item_id)
	var critical_item := QuestJson.b(item.get("quest_item")) or not QuestJson.b(item.get("tradeable"), true)
	for qid in character.quests.active_ids():
		var d := QuestCatalog.single(db, qid)
		if d == null:
			continue
		var handed := false
		for a: Dictionary in d.accept_items:
			handed = handed or String(a["item_id"]) == item_id
		if not critical_item and not handed:
			continue
		var need := 0
		for o: Dictionary in d.objectives:
			if String(o["id"]) != item_id:
				continue
			if o["kind"] == "item_collection":
				need = maxi(need, int(o["count"]))
			elif o["kind"] == "item_usage":
				need = maxi(need, int(o["count"]) - character.quests.uses(qid, item_id))
		if need <= 0:
			continue
		if out["quest_id"] == "":
			out["quest_id"] = qid
			out["quest_name"] = d.name
		out["needed"] = int(out["needed"]) + need
	return out
