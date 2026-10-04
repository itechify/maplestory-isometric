class_name Consumables
extends RefCounted
## Using a Use-tab item (potions, food): restores the canonical HP/MP (items domain consumable.hp_restore /
## mp_restore, flat; percentage effects are supported for future items), clamped to StatCalculator.max_hp / max_mp,
## and consumes one unit from the inventory. Buff effects are carried as data on ItemDef.buffs; no Maple Island item
## has one, so they are returned for the effect system rather than applied here.
##
## ItemService.use_item wraps this and emits Events.item_used, item_lost, inventory_changed, hp/mp_changed.
## Classic behaviour kept: a potion used at full HP is still consumed (it restores 0).
##
## Dead characters cannot use items, and "dead" is not "HP 0": the game shell takes a death's loss at the moment of
## death (GAME_SHELL.md "Death and respawn"), so while the death notice is up the character already holds its
## respawn HP. The check (is_dead) is the canonical HP trigger (Progression.is_dead) OR a dead-check Callable. Inject
## one to stay pure (tests, tools); without one, default_dead_check asks the Game autoload's is_character_dead()
## (which also reads MapSession's DEAD state), but only for the live character, Game.character.


## Uses one `item_id` from the character's inventory. Result: {"ok", "code", "item_id", "hp_gained", "mp_gained",
## "hp", "mp", "max_hp", "max_mp", "buffs"}. Codes: unknown_item, not_enough_items, not_usable (not an HP/MP/buff
## consumable, e.g. Pet Food without a pet, scrolls, equipment), dead (see is_dead).
## `dead_check`: a zero-argument Callable returning true while the character is dead (Game.is_character_dead fits
## as is); an invalid Callable (the default) means default_dead_check(character), resolved at call time.
static func use(character: CharacterState, item_id: String, db: ContentDB,
		dead_check: Callable = Callable()) -> Dictionary:
	var def := ItemDef.of(item_id, db)
	if def == null:
		return ItemCodes.result(ItemCodes.UNKNOWN_ITEM, {"item_id": item_id})
	if not def.is_consumable():
		return ItemCodes.result(ItemCodes.NOT_USABLE, {"item_id": item_id})
	if character.inventory.count(item_id) <= 0:
		return ItemCodes.result(ItemCodes.NOT_ENOUGH_ITEMS, {"item_id": item_id})
	if is_dead(character, db, dead_check):
		return ItemCodes.result(ItemCodes.DEAD, {"item_id": item_id})
	var max_hp := StatCalculator.max_hp(character, db)
	var max_mp := StatCalculator.max_mp(character, db)
	var gain := preview(def, character, max_hp, max_mp)
	character.inventory.remove(item_id, 1)
	character.hp += int(gain.hp)
	character.mp += int(gain.mp)
	return ItemCodes.result(ItemCodes.OK, {"item_id": item_id, "hp_gained": int(gain.hp), "mp_gained": int(gain.mp),
		"hp": character.hp, "mp": character.mp, "max_hp": max_hp, "max_mp": max_mp, "buffs": def.buffs.duplicate(true)})


## True while `character` may not use items: HP at the canonical death trigger (Progression.is_dead, formulas/
## death.json), or `dead_check` says so. An invalid `dead_check` is replaced by default_dead_check(character). The HP
## trigger always counts, so a check that only knows MapSession's DEAD state still covers the moment between HP 0 and
## DEAD (and a death during a warp, which enters DEAD only when the warp completes).
static func is_dead(character: CharacterState, db: ContentDB, dead_check: Callable = Callable()) -> bool:
	if Progression.is_dead(character, db):
		return true
	var check := dead_check if dead_check.is_valid() else default_dead_check(character)
	return check.is_valid() and bool(check.call())


## The dead check used when none is injected: `game`'s is_character_dead() (`game` null = the Game autoload, looked up
## through the SceneTree root, so this also works off-tree) when `character` IS that game's live character, else an
## invalid Callable (only the HP trigger applies). The identity test matters: Game.is_character_dead() reads
## Game.character, never the character passed here, so any other CharacterState (a test fixture, a sandbox) must not
## inherit the live game's death.
static func default_dead_check(character: CharacterState, game: Object = null) -> Callable:
	var g: Object = game if game != null else _game_autoload()
	if g == null or character == null or not g.has_method("is_character_dead"):
		return Callable()
	if g.get("character") != character:
		return Callable()
	return Callable(g, "is_character_dead")


## The Game autoload, or null (no SceneTree, or not registered).
static func _game_autoload() -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Game") if tree != null and tree.root != null else null


## What the item would restore right now: {"hp": int, "mp": int}, already clamped to the maxima.
static func preview(def: ItemDef, character: CharacterState, max_hp: int, max_mp: int) -> Dictionary:
	var hp_amount := def.hp_flat + int(floor(max_hp * def.hp_pct / 100.0))
	var mp_amount := def.mp_flat + int(floor(max_mp * def.mp_pct / 100.0))
	return {
		"hp": clampi(hp_amount, 0, maxi(0, max_hp - character.hp)),
		"mp": clampi(mp_amount, 0, maxi(0, max_mp - character.mp)),
	}
