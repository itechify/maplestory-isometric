class_name PlayerFx
extends Node3D
## The art pack's effect meshes on the player (#71): a child "PlayerFx" of the PlayerController, made by its
## PlayerCombat (PlayerCombat.ensure_skill_nodes). Presentation only, on events the game already raises; it never
## changes a gameplay value, and without the pack (EffectMeshes empty) it shows nothing, as before the pack.
##
##   Skill auras  while a skill's timed effect runs (EffectMeshes.SKILL_AURAS: Recovery, Nimble Feet), its mesh stands
##                at the player's feet and moves with it. The live character's CharacterState.effects decide, re-read
##                on Events.effects_changed (a cast, an expiry in EffectTicker, death ending the effects, a recast
##                replacing one), Events.game_loaded and Game.character_replaced (a load or a new game), and when this
##                node enters the tree.
##   Dust         JumpDust at the feet on a ground jump (PlayerController.jumped; not a jump off a ladder or rope, whose
##                climb_ended(.., &"jump") comes first) and on a landing (PlayerController.landed). It stays where it
##                was raised and fades over DUST_LIFE_S.
## The pack's effects were authored beside its 1.98 m Beginner, so they get the one character factor
## (ArtPack.character_scale) that fits that figure to the game's 1.5 m body.

## Presentation constant: how long one puff of dust lasts (s).
const DUST_LIFE_S := 0.45

## The PlayerController (its jumped / landed / climb_ended signals).
var player: Node3D = null
## The PlayerCombat whose collaborators (character, Game, event bus) this resolves through.
var combat: PlayerCombat = null
## Where the meshes come from (tests pin a pack or none); null = EffectMeshes.shared().
var effect_meshes: EffectMeshes = null

## Effect id ("skill:0001001") -> its aura node.
var _auras: Dictionary = {}
## Live dust: [{node, t}].
var _dust: Array[Dictionary] = []
var _skip_next_jump := false
var _bus_connected: Object = null
var _game_connected: Object = null


func _ready() -> void:
	if player == null:
		player = get_parent() as Node3D
	if player != null:
		if player.has_signal(&"landed"):
			player.connect(&"landed", _on_landed)
		if player.has_signal(&"jumped"):
			player.connect(&"jumped", _on_jumped)
		if player.has_signal(&"climb_ended"):
			player.connect(&"climb_ended", _on_climb_ended)
	refresh()


func _process(delta: float) -> void:
	advance(delta)


## Advances the dust (called by _process; tests call it directly) and keeps the bus and Game connections current
## (the bus or Game may be set after this node entered the tree).
func advance(delta: float) -> void:
	_connect_sources()
	var keep: Array[Dictionary] = []
	for d in _dust:
		var n: Node3D = d.node
		if not is_instance_valid(n):
			continue
		d.t = float(d.t) + delta
		var k := float(d.t) / DUST_LIFE_S
		if k >= 1.0:
			n.queue_free()
			continue
		n.scale = Vector3.ONE * ArtPack.character_scale() * lerpf(0.8, 1.15, sqrt(k))
		EffectMeshes.fade(n, k * k)
		keep.append(d)
	_dust = keep


## Re-reads the live character's timed effects: an aura for each running effect that has one, none for the rest.
func refresh() -> void:
	_connect_sources()
	var want := {}
	var c := _character()
	if c != null:
		for e: Variant in c.effects:
			if not (e is Dictionary) or EffectBook.remaining_of(e) <= 0.0:
				continue
			var id := String((e as Dictionary).get("id", ""))
			for skill: String in EffectMeshes.SKILL_AURAS:
				if id == PlayerSkills.effect_id(skill):
					want[id] = EffectMeshes.SKILL_AURAS[skill]
	for id: String in _auras.keys():
		if not want.has(id) or not is_instance_valid(_auras[id]):
			if is_instance_valid(_auras[id]):
				(_auras[id] as Node).queue_free()
			_auras.erase(id)
	for id: String in want:
		if _auras.has(id):
			continue
		var n := _meshes().standing(want[id], ArtPack.character_scale())
		if n == null:
			continue
		n.name = want[id]
		add_child(n)
		_auras[id] = n


## The aura shown for an effect id, or null.
func aura(effect_id: String) -> Node3D:
	var n: Variant = _auras.get(effect_id, null)
	return n if n is Node3D and is_instance_valid(n) else null


## The effect ids with an aura showing, sorted.
func aura_ids() -> Array:
	var out := _auras.keys().filter(func(id: String) -> bool: return aura(id) != null)
	out.sort()
	return out


## Puffs of dust still playing.
func dust_count() -> int:
	return _dust.size()


## The last puff of dust raised (null before the first or without the pack).
func last_dust() -> Node3D:
	return _dust.back().node if not _dust.is_empty() else null


func _on_landed(_fall_speed: float) -> void:
	_puff()


func _on_jumped() -> void:
	if _skip_next_jump:
		_skip_next_jump = false
		return
	_puff()


func _on_climb_ended(_climbable: Variant, how: StringName) -> void:
	# A jump off a ladder or rope: PlayerController emits jumped right after, in mid-air; no dust for that one.
	_skip_next_jump = how == &"jump"


func _puff() -> void:
	if player == null or not is_inside_tree():
		return
	var n := _meshes().standing(EffectMeshes.JUMP_DUST, ArtPack.character_scale())
	if n == null:
		return
	n.top_level = true
	add_child(n)
	n.global_position = player.global_position
	_dust.append({"node": n, "t": 0.0})


func _meshes() -> EffectMeshes:
	return effect_meshes if effect_meshes != null else EffectMeshes.shared()


func _connect_sources() -> void:
	var b := _bus()
	if b != _bus_connected:
		_disconnect(_bus_connected, {&"effects_changed": refresh, &"game_loaded": _on_game_loaded})
		_bus_connected = b
		if b != null:
			for sig: StringName in [&"effects_changed", &"game_loaded"]:
				var fn: Callable = refresh if sig == &"effects_changed" else _on_game_loaded
				if b.has_signal(sig) and not b.is_connected(sig, fn):
					b.connect(sig, fn)
	var g := _game()
	if g != _game_connected:
		_disconnect(_game_connected, {&"character_replaced": _on_character_replaced})
		_game_connected = g
		if g != null and g.has_signal(&"character_replaced") and not g.is_connected(&"character_replaced", _on_character_replaced):
			g.connect(&"character_replaced", _on_character_replaced)


## `source` may already be freed (the bus or Game of a torn-down test rig), so it is untyped.
func _disconnect(source: Variant, conns: Dictionary) -> void:
	if not is_instance_valid(source):
		return
	for sig: StringName in conns:
		if source.has_signal(sig) and source.is_connected(sig, conns[sig]):
			source.disconnect(sig, conns[sig])


func _on_game_loaded(_slot: String) -> void:
	refresh()


func _on_character_replaced(_reason: String) -> void:
	refresh()


func _exit_tree() -> void:
	_disconnect(_bus_connected, {&"effects_changed": refresh, &"game_loaded": _on_game_loaded})
	_disconnect(_game_connected, {&"character_replaced": _on_character_replaced})
	_bus_connected = null
	_game_connected = null


func _character() -> CharacterState:
	return combat.live_character() if combat != null and is_instance_valid(combat) else null


func _game() -> Node:
	return combat.game_node() if combat != null and is_instance_valid(combat) else null


func _bus() -> Object:
	return combat.event_bus() if combat != null and is_instance_valid(combat) else null
