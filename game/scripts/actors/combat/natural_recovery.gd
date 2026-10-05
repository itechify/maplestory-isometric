class_name NaturalRecovery
extends Node
## Natural HP recovery for the live player: NaturalRecoveryRule (data/misostory/recovery.json, the project owner's rule:
## 10 HP per 10 s of time spent standing still or seated, paused by everything else) plus the bonus of the chair the
## player sits on (Chairs.bonus, canonical setup data, on its own clock). The monster system adds it to the player next
## to PlayerCombat. Each physics tick, after the player and PlayerCombat (process_physics_priority), it reads the
## player's activity() (contract C4), steps the rule and heals through Game.change_hp, so the HUD and every HP listener
## see it. MP does not recover on its own (recovery.json natural_mp, a source gap).
##
## The natural clock is the live character's CharacterState.natural_recovery.hp_rest_s (contract C3): read before and
## written after every step, so a save keeps the paused time, a load restores it, and a new character starts at its own.

## After the player body (0) and PlayerCombat (10): activity() sees this tick's movement and attack lockout.
const PHYSICS_PRIORITY := 20

var rule: NaturalRecoveryRule = null
## Injected for tests; default: the parent (the player) and the Game / MapSession / Data autoloads.
var player: Node3D = null
var game: Node = null
var session: Node = null
var db: ContentDB = null
## Run step() from _physics_process (tests turn it off and call step() themselves).
var autostep: bool = true
## The activity the last step() used (debug overlay, tests).
var last_activity: StringName = &""


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY
	if player == null:
		player = get_parent() as Node3D
	if game == null:
		game = get_node_or_null(^"/root/Game")
	if session == null:
		session = get_node_or_null(^"/root/MapSession")
	if rule == null:
		rule = NaturalRecoveryRule.from_db(_db())


func _physics_process(delta: float) -> void:
	if autostep:
		step(delta)


## One tick of `delta` seconds. Returns the HP restored (also applied through Game.change_hp).
func step(delta: float) -> int:
	if rule == null or game == null or not bool(game.call("has_active_game")):
		return 0
	var c: CharacterState = game.get("character")
	if c == null:
		return 0
	var d := _db()
	var act := activity()
	last_activity = act
	var chair: Dictionary = {}
	if act == NaturalRecoveryRule.SEATED and player != null and player.has_method("seated_chair_id"):
		chair = Chairs.bonus(String(player.call("seated_chair_id")), d)
	rule.rest_s = maxf(0.0, float(c.natural_recovery.get("hp_rest_s", 0.0)))
	var heal := rule.step(delta, act, c.hp, StatCalculator.max_hp(c, d), int(chair.get("hp", 0)),
		float(chair.get("interval_s", 0.0)))
	c.natural_recovery["hp_rest_s"] = rule.rest_s
	if heal > 0:
		game.call("change_hp", heal)
	return heal


## The player's activity for the rule: PlayerController.activity() (contract C4), &"dead" while the game says the
## character is dead, &"other" while MapSession is not idle (a warp in flight) or without a player.
func activity() -> StringName:
	if game != null and game.has_method("is_character_dead") and bool(game.call("is_character_dead")):
		return &"dead"
	if session != null and session.has_method("is_idle") and not bool(session.call("is_idle")):
		return &"other"
	if player == null or not player.has_method("activity"):
		return &"other"
	return StringName(player.call("activity"))


func _db() -> ContentDB:
	if db != null:
		return db
	var data := get_node_or_null(^"/root/Data") if is_inside_tree() else null
	return data.get("db") as ContentDB if data != null else null
