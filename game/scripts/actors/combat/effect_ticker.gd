class_name EffectTicker
extends Node
## The character's timed-effect clock in the world: a child "EffectTicker" of the PlayerController, made by its
## PlayerCombat (PlayerCombat.ensure_skill_nodes). Every physics tick of game time (it stops while the tree is paused,
## so the pause menu stops buffs and cooldowns, and while Game.paused) it advances the live character's
## CharacterState.effects and cooldowns through EffectBook.tick:
##   - a heal over time that falls due (Recovery) heals through Game.change_hp, so the HUD and the death watch see it;
##     never while the character is dead;
##   - an effect whose stat bonuses start or end (Nimble Feet) announces Events.stats_changed, so the
##     PlayerController's speed and the stat window follow;
##   - any effect that ends announces Events.effects_changed.
## The character is re-read every tick (Game replaces it on load), so a loaded save's effects and cooldowns carry on
## from their saved remaining seconds. At Events.player_died the skill effects end (misostory/skills.json
## effects_on_death; cooldowns keep counting down).

var player: Node3D = null
## The PlayerCombat whose collaborators this resolves through (and whose autostep it follows).
var combat: PlayerCombat = null
## Injection seams (tests): null = the PlayerCombat's.
var db: ContentDB = null
var game: Node = null
var character: CharacterState = null
var bus: Object = null
## Run step() from _physics_process (also requires the PlayerCombat's autostep; tests turn that off).
var autostep: bool = true

## HP effects actually restored so far (after the Max HP clamp; tests, the sandbox report).
var healed: int = 0
var _bus_connected: Object = null


func _ready() -> void:
	# After the player and its combat: a cast made this tick is counted from the next.
	process_physics_priority = 12
	if player == null:
		player = get_parent() as Node3D
	_connect_bus()


func _physics_process(delta: float) -> void:
	if autostep and (combat == null or not is_instance_valid(combat) or combat.autostep):
		step(delta)


## One tick of game time.
func step(delta: float) -> void:
	_connect_bus()
	var c := _character()
	if c == null or delta <= 0.0:
		return
	var g := _game()
	if g != null and bool(g.get("paused")):
		return
	if c.effects.is_empty() and c.cooldowns.is_empty():
		return
	var r := EffectBook.tick(c, delta)
	var heal := int(r.heal)
	if heal > 0 and not _is_dead():
		if g != null and g.has_method("change_hp"):
			healed += int(g.call("change_hp", heal))
		else:
			var d := _db()
			healed += StatCalculator.change_hp(c, heal, d)
			_emit(&"hp_changed", [c.hp, StatCalculator.max_hp(c, d)])
	if bool(r.bonuses_changed):
		_emit(&"stats_changed")
	if not (r.expired as Array).is_empty() or int(r.dropped) > 0:
		_emit(&"effects_changed")


## Ends the skill effects (death; misostory/skills.json effects_on_death.end_effects). Returns the removed entries.
func end_skill_effects() -> Array:
	var c := _character()
	if c == null:
		return []
	var removed := EffectBook.clear(c, "skill:")
	if removed.is_empty():
		return removed
	for e in removed:
		if EffectBook.has_bonuses(e):
			_emit(&"stats_changed")
			break
	_emit(&"effects_changed")
	return removed


func _on_player_died(_map_id: String) -> void:
	var d := _db()
	if d != null and SkillRules.of(d).end_effects_on_death:
		end_skill_effects()


func _connect_bus() -> void:
	var b := _bus()
	if b == _bus_connected:
		return
	if _bus_connected != null and is_instance_valid(_bus_connected) and _bus_connected.is_connected(&"player_died", _on_player_died):
		_bus_connected.disconnect(&"player_died", _on_player_died)
	_bus_connected = b
	if b != null and b.has_signal(&"player_died") and not b.is_connected(&"player_died", _on_player_died):
		b.connect(&"player_died", _on_player_died)


func _exit_tree() -> void:
	if _bus_connected != null and is_instance_valid(_bus_connected) and _bus_connected.is_connected(&"player_died", _on_player_died):
		_bus_connected.disconnect(&"player_died", _on_player_died)
	_bus_connected = null


func _is_dead() -> bool:
	var g := _game()
	if g != null and g.has_method("is_character_dead"):
		return bool(g.call("is_character_dead"))
	return player != null and player.has_method("is_dead") and bool(player.call("is_dead"))


func _db() -> ContentDB:
	if db != null:
		return db
	if combat != null and is_instance_valid(combat):
		return combat.content_db()
	var data := get_node_or_null(^"/root/Data") if is_inside_tree() else null
	return data.get("db") as ContentDB if data != null else null


func _game() -> Node:
	if game != null:
		return game
	if combat != null and is_instance_valid(combat):
		return combat.game_node()
	return get_node_or_null(^"/root/Game") if is_inside_tree() else null


func _character() -> CharacterState:
	if character != null:
		return character
	if combat != null and is_instance_valid(combat):
		return combat.live_character()
	var g := _game()
	return g.get("character") as CharacterState if g != null else null


func _bus() -> Object:
	if bus != null:
		return bus
	if combat != null and is_instance_valid(combat):
		return combat.event_bus()
	return get_node_or_null(^"/root/Events") if is_inside_tree() else null


func _emit(sig: StringName, args: Array = []) -> void:
	var b := _bus()
	if b != null and b.has_signal(sig):
		b.callv(&"emit_signal", [sig] + args)
