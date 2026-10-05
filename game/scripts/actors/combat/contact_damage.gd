class_name ContactDamage
extends RefCounted
## Monster contact (touch) damage on the player, end to end: the canonical touch formula
## (CombatFormula.resolve_monster_touch: hit roll, guard, 1.1-1.5 roll, WDEF curve, clamp), the HP change through
## StatCalculator with the Events the HUD listens to, the knockback and the canonical post-hit invincibility on the
## PlayerController, and the death announcement when HP reaches 0. Pure static functions over injected collaborators
## (the player node, the character, ContentDB, the RNG, the event bus, MapSession), so tests drive it directly.
##
##   if ContactDamage.can_be_touched(player, session):
##       var res := ContactDamage.resolve(def.stats, Game.character, Data.db, Game.rng)
##       ContactDamage.apply(res, "2", monster.global_position, player, Game.character, Data.db, Events)
##       if Game.character.hp <= 0: ContactDamage.announce_death(player, MapSession, Events, map_id)

## MapSession states (by name) in which the player is mid-warp or dead: no contact is resolved then.
const NO_TOUCH_STATES := ["WARP_OUT", "SWAP", "WARP_IN", "ARRIVING", "DEAD"]


## True when a monster may hurt the player now: alive, not invulnerable (the canonical 1.5 s after any monster
## attack, landed, missed or guarded) and not in the middle of a map transition.
static func can_be_touched(player: Node, session: Node = null) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.has_method("is_dead") and bool(player.call("is_dead")):
		return false
	if player.has_method("is_invulnerable") and bool(player.call("is_invulnerable")):
		return false
	if session != null and session.has_method("state_name") and String(session.call("state_name")) in NO_TOUCH_STATES:
		return false
	return true


## Rolls the canonical touch attack of `monster` on the character (physical, attack ratio 100, no element).
static func resolve(monster: MonsterCombatStats, character: CharacterState, db: ContentDB,
		rng: RandomNumberGenerator) -> IncomingResult:
	return CombatFormula.resolve_monster_touch(monster, PlayerCombatStats.from_character(character, db), rng, db)


## Applies a resolved touch: HP down by res.final (StatCalculator.change_hp, clamped at 0), Events.player_damaged +
## hp_changed on a landed hit, Events.player_missed_by on a miss or a guard; then the reaction on the player:
## apply_knockback_from_point(mob_pos, 1, res.invincibility_s) when res.knockback, else set_invulnerable(that same
## canonical duration). A monster with no attack (P.DMG 0) changes nothing. Returns the HP actually lost.
static func apply(res: IncomingResult, mob_id: String, mob_pos: Vector3, player: Node, character: CharacterState,
		db: ContentDB, events: Node) -> int:
	if res == null or res.no_attack:
		return 0
	var lost := 0
	if res.landed():
		lost = -StatCalculator.change_hp(character, -res.final, db)
		_emit(events, &"player_damaged", [res.final, mob_id])
		_emit(events, &"hp_changed", [character.hp, StatCalculator.max_hp(character, db)])
	else:
		_emit(events, &"player_missed_by", [mob_id])
	if player != null and is_instance_valid(player):
		if res.knockback and player.has_method("apply_knockback_from_point"):
			player.call("apply_knockback_from_point", mob_pos, 1.0, res.invincibility_s)
		elif res.invincibility_s > 0.0 and player.has_method("set_invulnerable"):
			player.call("set_invulnerable", res.invincibility_s)
	return lost


## HP reached 0: announce the death the way MapSession expects (MAP_ARCHITECTURE.md section 4.8). MapSession's
## enter_dead() sets DEAD, turns input off and emits Events.player_died (which the PlayerController and the death UI
## listen to). When the session cannot take it (no session, BOOT in a sandbox, or a warp in flight) the death is
## emitted on the bus directly and MapSession's own listener enters DEAD (at once or after the warp). The player
## node is put into its death state as well when it does not listen to the bus itself.
static func announce_death(player: Node, session: Node, events: Node, map_id: String) -> void:
	var announced := false
	if session != null and session.has_method("enter_dead") and session.has_method("is_idle") and bool(session.call("is_idle")):
		announced = int(session.call("enter_dead")) == OK
	if not announced:
		_emit(events, &"player_died", [map_id])
	if player != null and is_instance_valid(player) and player.has_method("die"):
		if not (player.has_method("is_dead") and bool(player.call("is_dead"))):
			player.call("die")


static func _emit(events: Node, sig: StringName, args: Array) -> void:
	if events != null and events.has_signal(sig):
		events.callv(&"emit_signal", [sig] + args)
