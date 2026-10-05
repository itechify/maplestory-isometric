class_name Chairs
extends RefCounted
## Chairs and sitting (contract C5). A chair is a Setup item with canonical setup data (ItemDef.is_chair(): The Green
## Relaxer, 522, setup.hp_recovery_bonus 30 every setup.interval_s 10). Using one sits the player down; while seated,
## natural recovery is eligible and the chair's bonus runs on its own clock (NaturalRecoveryRule).
##
##   Chairs.use(character, "522", db)      ItemService.use_item for a chair: the Set-up tab, a quickslot
##   Chairs.sit_key(character, db)         the sit key (X): stand up, or sit on the first chair owned (an adaptation)
##   Chairs.bonus("522", db)               {"hp": 30, "interval_s": 10.0}
##
## The seated state itself lives on the player (PlayerController.sit / stand_up / is_seated / can_sit). These rules
## reach it through a "seat": anything with is_seated() -> bool, seated_chair_id() -> String, can_sit() -> String
## ("" when allowed, else why not), sit(chair_id) -> bool and stand_up(reason) -> bool. Callers may pass one (tests);
## otherwise seat_for() finds the live player, but only for the Game autoload's own character, so a test fixture's
## ItemService never moves the real player. Nothing here emits events: the player announces sat_down / stood_up
## (Events.player_sat_down / player_stood_up), and a chair never leaves the inventory.
##
## Result: {"ok", "code", "item_id", "action": "sit" | "stand"} (ItemCodes). Codes: unknown_item, not_usable (not a
## chair), not_enough_items (not owned), level_too_low (+ "required"), dead, cannot_sit (+ "reason": the seat's
## can_sit() answer, or "no_player"), no_chair (the sit key with no chair in the Set-up tab).

## The group the live player joins (PlayerController, in the game) so item code can find the seated-state owner.
const SEAT_GROUP := &"miso_seat"
## The inventory tab chairs live in (canonical inventory_tab "setup").
const TAB := "setup"


## True if `def` is a chair (a Setup item with canonical setup data).
static func is_chair(def: ItemDef) -> bool:
	return def != null and def.is_chair()


## The chair's recovery bonus while seated on it: {"hp": int, "interval_s": float} from its canonical setup data, or {}
## when `item_id` is not a chair.
static func bonus(item_id: String, db: ContentDB) -> Dictionary:
	var def := ItemDef.of(item_id, db) if db != null and item_id != "" else null
	if not is_chair(def):
		return {}
	return {"hp": def.setup_hp_bonus, "interval_s": def.setup_interval_s}


## The first chair in `c`'s Set-up tab, slot by slot ("" when there is none). The sit key sits on it (recovery.json
## sitting.sit_key_chair "first_owned").
static func first_owned(c: CharacterState, db: ContentDB) -> String:
	if c == null or db == null:
		return ""
	for s: Variant in c.inventory.slots(TAB):
		if s is Dictionary and not (s as Dictionary).is_empty():
			var id := ItemDef.id_of(s.get("item_id", ""))
			if is_chair(ItemDef.of(id, db)):
				return id
	return ""


## Uses a chair: sits on it, stands up when already seated on it, or moves over from another chair. Refused (nothing
## changes) when the item is not a chair, is not owned, needs a higher level, the character is dead (Consumables.is_dead
## with `dead_check`), or the player cannot sit now (the seat's can_sit()). Moving over stands up from the old chair
## first, so a refusal at that point (cannot_sit) leaves the player standing.
static func use(c: CharacterState, item_id: String, db: ContentDB, seat: Object = null,
		dead_check: Callable = Callable()) -> Dictionary:
	var def := ItemDef.of(item_id, db)
	if def == null:
		return ItemCodes.result(ItemCodes.UNKNOWN_ITEM, {"item_id": item_id})
	if not is_chair(def):
		return ItemCodes.result(ItemCodes.NOT_USABLE, {"item_id": item_id})
	if c == null or c.inventory.count(item_id) <= 0:
		return ItemCodes.result(ItemCodes.NOT_ENOUGH_ITEMS, {"item_id": item_id})
	if def.req_level > 0 and c.level < def.req_level:
		return ItemCodes.result(ItemCodes.LEVEL_TOO_LOW, {"item_id": item_id, "required": def.req_level})
	if Consumables.is_dead(c, db, dead_check):
		return ItemCodes.result(ItemCodes.DEAD, {"item_id": item_id})
	var s := seat_for(c, seat)
	if s == null:
		return ItemCodes.result(ItemCodes.CANNOT_SIT, {"item_id": item_id, "reason": "no_player"})
	if bool(s.call("is_seated")):
		if String(s.call("seated_chair_id")) == item_id:
			s.call("stand_up", &"chair")
			return ItemCodes.result(ItemCodes.OK, {"item_id": item_id, "action": "stand"})
		s.call("stand_up", &"chair")
	var why := String(s.call("can_sit"))
	if why != "" or not bool(s.call("sit", item_id)):
		return ItemCodes.result(ItemCodes.CANNOT_SIT, {"item_id": item_id, "reason": why})
	return ItemCodes.result(ItemCodes.OK, {"item_id": item_id, "action": "sit"})


## The sit key (X): seated, it stands the player up; standing, it uses the first chair in the Set-up tab (no_chair when
## there is none). An adaptation: MeowDB has no sitting without a chair (recovery.json sitting).
static func sit_key(c: CharacterState, db: ContentDB, seat: Object = null, dead_check: Callable = Callable()) -> Dictionary:
	var s := seat_for(c, seat)
	if s != null and bool(s.call("is_seated")):
		var id := String(s.call("seated_chair_id"))
		s.call("stand_up", &"sit_key")
		return ItemCodes.result(ItemCodes.OK, {"item_id": id, "action": "stand"})
	var chair := first_owned(c, db)
	if chair == "":
		return ItemCodes.result(ItemCodes.NO_CHAIR, {"item_id": ""})
	return use(c, chair, db, s, dead_check)


## The seated-state owner for `c`: `seat` when given; else the live player (the first node in SEAT_GROUP), but only
## when `c` is the Game autoload's character. Null when there is none.
static func seat_for(c: CharacterState, seat: Object = null) -> Object:
	if seat != null:
		return seat
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or c == null:
		return null
	var game := tree.root.get_node_or_null(^"Game")
	if game == null or game.get("character") != c:
		return null
	return tree.get_first_node_in_group(SEAT_GROUP)
