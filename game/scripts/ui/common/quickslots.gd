class_name MisoQuickslots
extends RefCounted
## Quickslot bindings: key ("1".."8", the suffix of the quickslot_N input actions) -> a typed binding
## {"kind": "item" | "skill", "id": String}, stored in CharacterState.quickslots so they persist with the save
## (contract C3). A bare item id (an Iteration Two save before its migration) still reads as {"kind": "item", "id"}.
##
## What can be bound:
##   - an HP/MP/buff consumable (ItemDef.is_consumable); a binding stays when its stack runs out (the slot greys out
##     and refills on the next pickup); using it goes through ItemService.use_item, so the inventory, HP/MP, Events
##     and quests all see it;
##   - a chair (a Setup item with setup data, contract C5); using it also goes through ItemService.use_item, which
##     sits the player down on it (or stands it up) through Chairs.use;
##   - a learned skill; using it casts through the player's PlayerSkills (skill rules, costs and cooldown there).
##
## The HUD bar, the inventory window and the skill window share these helpers; after a binding changes, every node in
## GROUP gets refresh_quickslots() so separate scenes stay in sync without knowing each other.

## Drag-and-drop payload kind for items dragged out of MisoStory UI ({"kind", "source", "item_id", ...}).
const DRAG_KIND := "miso_item"
## Drag-and-drop payload kind for skills ({"kind", "source", "skill_id", "key"?}): the skill window's icons and the
## skill quickslots.
const SKILL_DRAG_KIND := "miso_skill"
const KIND_ITEM := "item"
const KIND_SKILL := "skill"
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


## A stored value as a typed binding: {"kind", "id"}, or {} when empty or unreadable. A bare id (String or number) is
## an item binding.
static func binding_of(v: Variant) -> Dictionary:
	if v is Dictionary:
		var kind := String((v as Dictionary).get("kind", ""))
		var id := ItemDef.id_of((v as Dictionary).get("id", ""))
		if (kind == KIND_ITEM or kind == KIND_SKILL) and id != "":
			return {"kind": kind, "id": id}
		return {}
	var item_id := ItemDef.id_of(v)
	return {"kind": KIND_ITEM, "id": item_id} if item_id != "" else {}


## The typed binding of a key ({} when none).
static func binding(c: CharacterState, key: String) -> Dictionary:
	if c == null:
		return {}
	return binding_of(c.quickslots.get(key, null))


## True if an item may sit in a quickslot: an HP/MP/buff consumable or a chair.
static func can_bind(item_id: String, db: ContentDB) -> bool:
	var def := ItemDef.of(item_id, db) if db != null else null
	return def != null and (def.is_consumable() or is_chair(def))


## A chair (contract C5): a Setup item whose record has setup data (The Green Relaxer, 522).
static func is_chair(def: ItemDef) -> bool:
	return def != null and def.tab == "setup" and def.raw.get("setup", null) is Dictionary


## True if a skill may sit in a quickslot: a canonical skill the character has learned.
static func can_bind_skill(c: CharacterState, skill_id: String, db: ContentDB) -> bool:
	return c != null and db != null and SkillDef.of(skill_id, db) != null and SkillBook.level_of(c, skill_id) > 0


## The item bound to a key ("" when none, or when the key holds a skill).
static func item_for(c: CharacterState, key: String) -> String:
	var b := binding(c, key)
	return String(b["id"]) if b.get("kind", "") == KIND_ITEM else ""


## The skill bound to a key ("" when none, or when the key holds an item).
static func skill_for(c: CharacterState, key: String) -> String:
	var b := binding(c, key)
	return String(b["id"]) if b.get("kind", "") == KIND_SKILL else ""


## Binds a consumable or a chair to a key. Returns false (and changes nothing) for anything else.
static func bind(env: MisoUiEnv, key: String, item_id: String) -> bool:
	var c := env.character() if env != null else null
	if c == null or key == "" or not can_bind(item_id, env.get_db()):
		return false
	_store(env, c, key, {"kind": KIND_ITEM, "id": item_id})
	return true


## Binds a learned skill to a key. Returns false (and changes nothing) for an unknown or unlearned skill.
static func bind_skill(env: MisoUiEnv, key: String, skill_id: String) -> bool:
	var c := env.character() if env != null else null
	if c == null or key == "" or not can_bind_skill(c, skill_id, env.get_db()):
		return false
	_store(env, c, key, {"kind": KIND_SKILL, "id": skill_id})
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


## Moves a binding from one key to another (swapping with whatever was there). Values are stored as fresh typed
## dictionaries (a save's shallow copy never shares one with the live state).
static func move(env: MisoUiEnv, from_key: String, to_key: String) -> bool:
	var c := env.character() if env != null else null
	if c == null or from_key == to_key or not c.quickslots.has(from_key):
		return false
	var a := binding(c, from_key)
	var b := binding(c, to_key)
	c.quickslots.erase(from_key)
	c.quickslots.erase(to_key)
	if not a.is_empty():
		c.quickslots[to_key] = a.duplicate()
	if not b.is_empty():
		c.quickslots[from_key] = b.duplicate()
	notify()
	env.request_autosave("quickslot")
	return true


## Uses what a key holds. An item: ItemService.use_item's result (a chair sits the player down or stands it up
## through Chairs.use, contract C5). A skill: PlayerSkills.cast's result ({"ok": false, "code": "unavailable"} without a
## player). {"ok": false, "code": "slot_empty"} when nothing is bound. Failures are announced with Events.notice.
static func use(env: MisoUiEnv, key: String) -> Dictionary:
	var c := env.character() if env != null else null
	var b := binding(c, key)
	if b.is_empty():
		return {"ok": false, "code": ItemCodes.SLOT_EMPTY, "key": key}
	if b["kind"] == KIND_SKILL:
		return use_skill(env, String(b["id"]))
	var item_id := String(b["id"])
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


## Casts a skill through the player's PlayerSkills (the GameContext player's, else the one in PlayerSkills.GROUP).
## A refusal with something to say (cooldown, MP, shell, position) is announced with Events.notice, unless `announce`
## is false (a held key's repeat that already announced one, #20). A refusal's result carries that line as "notice"
## ("" for the silent ones).
static func use_skill(env: MisoUiEnv, skill_id: String, announce: bool = true) -> Dictionary:
	var skills := player_skills(env)
	if skills == null:
		return {"ok": false, "code": SkillBook.UNAVAILABLE, "skill_id": skill_id}
	var res := skills.cast(skill_id)
	if not res.get("ok", false):
		var line := PlayerSkills.refusal_text(res, env.get_db())
		if line != "" and announce:
			env.notice(line)
		res["notice"] = line
	return res


## The PlayerSkills node to cast with, or null.
static func player_skills(env: MisoUiEnv) -> PlayerSkills:
	if env != null and env.ctx != null and env.ctx.player != null and is_instance_valid(env.ctx.player):
		var n := (env.ctx.player as Node).get_node_or_null(^"PlayerSkills")
		if n is PlayerSkills:
			return n
	if env != null and not env.use_autoloads:
		return null
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).get_first_node_in_group(PlayerSkills.GROUP) as PlayerSkills
	return null


## Asks every listener (HUD quickslot bar, inventory window) to redraw its quickslot view.
static func notify() -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		(loop as SceneTree).call_group(GROUP, &"refresh_quickslots")


static func _store(env: MisoUiEnv, c: CharacterState, key: String, value: Dictionary) -> void:
	c.quickslots[key] = value
	notify()
	env.request_autosave("quickslot")
