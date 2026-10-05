class_name NaturalRecovery
extends Node
## Natural HP recovery for the live player (NaturalRecoveryRule; combat.json natural_recovery). The monster system adds
## it to the player next to PlayerCombat. Each physics tick it reports whether the character is resting (alive,
## grounded, not moving, not climbing, not knocked back, the map session idle) and heals through Game.change_hp, so
## the HUD and every HP listener see it. Attacks (PlayerCombat.attack_started) and monster touches
## (Events.player_damaged / player_missed_by) count as combat.

## Horizontal speed (m/s) below which the player counts as standing still.
const STILL_SPEED := 0.05

var rule: NaturalRecoveryRule = null
## Injected for tests; default: the parent (the player) and the Game / MapSession / Events autoloads.
var player: Node3D = null
var game: Node = null
var session: Node = null
var events: Node = null


func _ready() -> void:
	if player == null:
		player = get_parent() as Node3D
	if game == null:
		game = get_node_or_null(^"/root/Game")
	if session == null:
		session = get_node_or_null(^"/root/MapSession")
	if events == null:
		events = get_node_or_null(^"/root/Events")
	if rule == null:
		var data := get_node_or_null(^"/root/Data")
		rule = NaturalRecoveryRule.from_db(data.get("db") if data != null else null)
	if events != null:
		for sig: StringName in [&"player_damaged", &"player_missed_by"]:
			if events.has_signal(sig) and not events.is_connected(sig, _on_combat):
				events.connect(sig, _on_combat)
	var pc := player.get_node_or_null(^"PlayerCombat") if player != null else null
	if pc != null and pc.has_signal("attack_started"):
		pc.connect("attack_started", _on_attack)


func _physics_process(delta: float) -> void:
	if rule == null or game == null or not bool(game.call("has_active_game")):
		return
	var c: CharacterState = game.get("character")
	if c == null:
		return
	var data := get_node_or_null(^"/root/Data")
	var db: ContentDB = data.get("db") if data != null else null
	var heal := rule.step(delta, is_resting(), c.hp, StatCalculator.max_hp(c, db))
	if heal > 0:
		game.call("change_hp", heal)


## True while the character rests: alive, on the ground, standing still, not climbing or knocked back, no warp.
func is_resting() -> bool:
	if game != null and game.has_method("is_character_dead") and bool(game.call("is_character_dead")):
		return false
	if session != null and session.has_method("is_idle") and not bool(session.call("is_idle")):
		return false
	if player == null:
		return false
	if player.has_method("is_grounded") and not bool(player.call("is_grounded")):
		return false
	if player.has_method("is_climbing") and bool(player.call("is_climbing")):
		return false
	if bool(player.get("in_hitstun")):
		return false
	var v: Variant = player.get("velocity")
	if v is Vector3 and Vector2((v as Vector3).x, (v as Vector3).z).length() > STILL_SPEED:
		return false
	return true


func _on_combat(_a: Variant = null, _b: Variant = null) -> void:
	if rule != null:
		rule.note_combat()


func _on_attack(_action: String = "", _presentation: String = "", _lockout: float = 0.0) -> void:
	if rule != null:
		rule.note_combat()
