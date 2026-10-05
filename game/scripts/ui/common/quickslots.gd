class_name MisoQuickslots
extends RefCounted
## Quickslot bindings: key ("1".."8", the suffix of the quickslot_N input actions) -> consumable item id, stored in
## CharacterState.quickslots so they persist with the save. Only consumables can be bound (ItemDef.is_consumable);
## a binding stays when its stack runs out (the slot greys out and refills on the next pickup). Using a slot goes
## through ItemService.use_item, so the inventory, HP/MP, Events and quests all see it.
##
## The HUD bar and the inventory window share these helpers; after a binding changes, every node in GROUP gets
## refresh_quickslots() so separate scenes stay in sync without knowing each other.

## Drag-and-drop payload kind for items dragged out of MisoStory UI ({"kind", "source", "item_id", ...}).
const DRAG_KIND := "miso_item"
const ACTION_PREFIX := "quickslot_"
## The number of quickslot actions in the input contract (ARCHITECTURE.md: quickslot_1..8); used only when the
## InputMap has none registered (Controls not loaded).
const CONTRACT_COUNT := 8
## Nodes that redraw when a binding changes (they implement refresh_quickslots()).
const GROUP := &"miso_quickslot_listeners"


## The quickslot keys in order: one per registered quickslot_N action ("1".."8").
static func keys() -> PackedStringArray:
	var out: PackedStringArray = []
	var n := 1
	while InputMap.has_action(ACTION_PREFIX + str(n)):
		out.append(str(n))
		n += 1
	if out.is_empty():
		for i in CONTRACT_COUNT:
			out.append(str(i + 1))
	return out


static func action_for(key: String) -> String:
	return ACTION_PREFIX + key


## The keyboard label of a quickslot key ("1"), falling back to the key itself.
static func key_text(key: String) -> String:
	var k := MisoUiEnv.key_label(action_for(key))
	return k if k != "" else key


## True if an item may sit in a quickslot (an HP/MP/buff consumable).
static func can_bind(item_id: String, db: ContentDB) -> bool:
	var def := ItemDef.of(item_id, db) if db != null else null
	return def != null and def.is_consumable()


## The item bound to a key ("" when none).
static func item_for(c: CharacterState, key: String) -> String:
	if c == null:
		return ""
	return ItemDef.id_of(c.quickslots.get(key, ""))


## Binds a consumable to a key. Returns false (and changes nothing) for anything else.
static func bind(env: MisoUiEnv, key: String, item_id: String) -> bool:
	var c := env.character() if env != null else null
	if c == null or key == "" or not can_bind(item_id, env.get_db()):
		return false
	c.quickslots[key] = item_id
	notify()
	env.request_autosave("quickslot")
	return true


## Clears a key. Returns false when it was already empty.
static func unbind(env: MisoUiEnv, key: String) -> bool:
	var c := env.character() if env != null else null
	if c == null or not c.quickslots.has(key):
		return false
	c.quickslots.erase(key)
	notify()
	env.request_autosave("quickslot")
	return true


## Moves a binding from one key to another (swapping with whatever was there).
static func move(env: MisoUiEnv, from_key: String, to_key: String) -> bool:
	var c := env.character() if env != null else null
	if c == null or from_key == to_key or not c.quickslots.has(from_key):
		return false
	var a: Variant = c.quickslots[from_key]
	var b: Variant = c.quickslots.get(to_key, null)
	c.quickslots[to_key] = a
	if b == null:
		c.quickslots.erase(from_key)
	else:
		c.quickslots[from_key] = b
	notify()
	env.request_autosave("quickslot")
	return true


## Uses the item bound to a key through ItemService. Result as ItemService.use_item, or {"ok": false, "code":
## "slot_empty"} when nothing is bound. Failures are announced with Events.notice.
static func use(env: MisoUiEnv, key: String) -> Dictionary:
	var c := env.character() if env != null else null
	var item_id := item_for(c, key)
	if item_id == "":
		return {"ok": false, "code": ItemCodes.SLOT_EMPTY, "key": key}
	var items := env.items()
	if items == null:
		return {"ok": false, "code": "unavailable"}
	var res := items.use_item(item_id)
	if not res.get("ok", false):
		if String(res.get("code", "")) == ItemCodes.NOT_ENOUGH_ITEMS:
			env.notice("You have no %s left." % env.item_name(item_id))
		else:
			env.notice(MisoUiText.result_message(res, env.get_db()))
	return res


## Asks every listener (HUD quickslot bar, inventory window) to redraw its quickslot view.
static func notify() -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		(loop as SceneTree).call_group(GROUP, &"refresh_quickslots")
