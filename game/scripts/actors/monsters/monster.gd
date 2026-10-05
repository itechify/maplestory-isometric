class_name Monster
extends CharacterBody3D
## One live monster (scenes/actors/monster.tscn): a platform walker on WorldLayers.MONSTERS that wanders, turns at
## ledges, walls and its map's mob region, hops if it is a jumper, takes hits with the canonical knockback rule,
## touches the player, and dies over its canonical die time. Built by MonsterSystem's factory for MapInstanceView.
##
## Movement is kinematic and advanced one physics tick at a time by step(delta) (like PlayerController), with
## physics queries only: before every step it probes probe_ahead_m ahead for walkable ground within
## +/- ledge_tolerance_m (else: a ledge) and casts wall rays at wall_probe_height_m (centre and both sides of the
## body; a surface steeper than the ledge slope is a wall), and asks its MobRegion whether the step is allowed
## (MAP_ARCHITECTURE.md section 4.7.4). It then moves and sits on the ground found under its new position. Monsters
## never collide with each other or with the player (classic: bodies overlap); the capsule is for the kill plane.
##
## Contract with MapInstanceView: `hp` (survivor HP is written back on release), metadata spawn_slot/mob_id/map_id
## set by the view, and the `died` signal (the view connects it and records the kill in MapInstanceState).
## A monster without a slot (`slot_index` -1: a debug-console spawn, or a free spawn from MonsterSystem.spawn_monster)
## dies the same way, but nothing reports it to MapInstanceView, so it never frees or respawns a slot.
## The debug console kills through debug_kill() (DEBUG_TOOLS.md "Kill").

signal died(monster: Monster)
## A resolved player attack reached this monster (hit or miss).
signal attacked(monster: Monster, result: DamageResult)

## The `slot_index` of a monster that fills no spawn slot (a debug or free spawn).
const NO_SLOT := -1

var def: MonsterDef = null
## Its spawn slot (set by MonsterSystem.make_monster from the SpawnSlot); NO_SLOT for debug and free spawns.
var slot_index: int = NO_SLOT
## The MonsterSystem that owns the shared services (player, FX, events); null in bare tests.
var system: Node = null
var hp: int = 0
var brain: MonsterBrain = null
var visual: MonsterVisual = null
## Horizontal unit vector the monster faces (the model turns toward it).
var facing: Vector3 = Vector3.BACK
var region: MobRegion = null
var ground: PhysicsGroundQuery = null
## Appearance order on the map (basic attacks break distance ties in favour of the monster that appeared first).
var spawn_order: int = 0
var map_id: String = ""
## Where it spawned (fall recovery returns it here).
var home: Transform3D = Transform3D.IDENTITY
## Below this height while airborne it returns home (the map's kill_y; -INF = never).
var kill_y: float = -INF
## The node that provoked it (its chase target).
var attacker: Node3D = null
## Run step() from _physics_process (tests turn it off and call step() themselves).
var autostep: bool = true
var airborne: bool = false
var vertical_speed: float = 0.0
## settle() searches for ground this far above / below the feet (MonsterSystem sets them from presentation.json
## grounding.probe_up_m / probe_down_m, the world's own grounding probe).
var settle_up_m: float = 1.0
var settle_down_m: float = 3.0

# --- counters for tests and the debug overlay ----------------------------------------------------------------------
var distance_walked: float = 0.0
var hops: int = 0
var recoveries: int = 0
var blocked_by: Dictionary = {"ledge": 0, "wall": 0, "region": 0}

var _hop: Dictionary = {}
var _dying: bool = false
var _walking: bool = false
var _wall_cos: float = 0.0
var _shape: CollisionShape3D = null


func _init() -> void:
	collision_layer = WorldLayers.MONSTERS
	collision_mask = WorldLayers.MONSTER_MASK
	# After the player (0) so touches read this tick's player position; before PortalInteractor (100).
	process_physics_priority = 20


## Configures the monster before it enters the tree. `xform` is the spawn slot transform (feet, facing +Z).
func setup(d: MonsterDef, sys: Node, xform: Transform3D, rng_seed: int, p_region: MobRegion,
		p_ground: PhysicsGroundQuery, library: ProxyLibrary, start_hp: int = -1) -> void:
	def = d
	system = sys
	name = "Mob_%s_%d" % [d.id, spawn_order]
	hp = d.max_hp if start_hp < 0 or start_hp > d.max_hp else start_hp
	region = p_region
	ground = p_ground
	home = xform
	transform = xform
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	brain = MonsterBrain.new(d, rng)
	var f := Vector3(xform.basis.z.x, 0.0, xform.basis.z.z)
	facing = f.normalized() if f.length_squared() > 1e-6 else Vector3.BACK
	brain.start(facing)
	_wall_cos = cos(atan2(d.ledge_tolerance_m, maxf(d.probe_ahead_m, 0.01)))
	_build_body()
	visual = MonsterVisual.new()
	visual.name = "Visual"
	visual.monster = self
	add_child(visual)
	visual.build(d, library)
	visual.snap_facing(facing)
	visual.set_hp_ratio(float(hp) / maxf(d.max_hp, 1))
	visual.faded_out.connect(_on_faded_out)


func _ready() -> void:
	settle()


func _physics_process(delta: float) -> void:
	if autostep:
		step(delta)


## Puts the monster on the ground under it (within settle_up_m above / settle_down_m below); airborne if there is
## none.
func settle() -> void:
	if ground == null or not is_inside_tree():
		return
	var g := ground.ground_at(global_position, settle_up_m, settle_down_m)
	if bool(g.ok):
		global_position.y = float(g.y)
		airborne = false
	else:
		airborne = true
		vertical_speed = 0.0


# =================================================================================================================
# Public API
# =================================================================================================================

## One simulation tick: AI, movement with terrain probes, stagger push, hops/falls, then the touch check.
func step(delta: float) -> void:
	if def == null or _dying or delta <= 0.0:
		return
	_walking = false
	# The stagger push runs before the brain's tick: the tick that ends the stagger zeroes push_left, so pushing after
	# it lost the last tick (35 of 36 ticks, playtest finding monster-push-one-tick-short).
	if not airborne and brain.mode == MonsterBrain.Mode.STAGGER:
		_step_push(delta)
	brain.tick(delta)
	if airborne:
		_step_air(delta)
	else:
		match brain.mode:
			MonsterBrain.Mode.WALK, MonsterBrain.Mode.CHASE:
				_step_walk(delta)
	if system != null and is_instance_valid(system) and system.has_method("monster_touch"):
		system.call("monster_touch", self)


func is_alive() -> bool:
	return not _dying and hp > 0


func is_dying() -> bool:
	return _dying


## Moved (or hopped) this tick, for the walk animation.
func is_walking() -> bool:
	return _walking or not _hop.is_empty()


## True when walking into it hurts the player now (alive, and for a Peace monster, provoked).
func touch_active() -> bool:
	return is_alive() and def != null and def.touch_active(brain.provoked)


## Above the head: where damage numbers and the HP bar go.
func head_position() -> Vector3:
	var h := visual.height_m if visual != null else (def.sprite_size_m.y if def != null else 1.0)
	return global_position + Vector3.UP * (h + 0.15)


## The centre of the body (hit sparks).
func body_center() -> Vector3:
	var h := def.touch_size_m.y if def != null else 0.5
	return global_position + Vector3.UP * (h * 0.5)


## Applies a resolved player attack. A miss changes nothing but is announced; a hit takes HP, staggers the monster
## when the damage reaches its KB threshold (DamageResult.knockback, CombatFormula.monster_staggers), provokes it,
## and kills it at 0 HP.
func receive_hit(res: DamageResult, from: Node3D) -> void:
	if not is_alive() or res == null:
		return
	attacked.emit(self, res)
	if res.missed:
		return
	hp = maxi(0, hp - res.final)
	if from != null and is_instance_valid(from):
		attacker = from
	var from_pos := from.global_position if from != null and is_instance_valid(from) else global_position - facing
	# A hit mid-hop staggers too (the canonical KB rule has no airborne exception: playtest finding
	# airborne-hit-no-stagger). The hop still lands where it was going; the push then runs for the stagger time left.
	brain.on_hit(global_position, from_pos, res.knockback)
	facing = brain.heading
	if visual != null:
		visual.on_hit(float(hp) / maxf(def.max_hp, 1))
	if hp <= 0:
		die()


## Death: no more touches or hits, the owner awards EXP and loot at once (MeowDB: "Loot drops as soon as the mob
## dies"), `died` fires (MapInstanceView records the kill for the respawn tick), then the body fades over the
## canonical die time and frees itself.
func die() -> void:
	if _dying:
		return
	_dying = true
	hp = 0
	if brain != null:
		brain.die()
	_hop = {}
	collision_layer = 0
	if _shape != null:
		_shape.set_deferred("disabled", true)
	if system != null and is_instance_valid(system) and system.has_method("on_monster_died"):
		system.call("on_monster_died", self)
	died.emit(self)
	if visual != null and def != null:
		visual.start_death_fade(def.die_fade_s)


## The debug console's kill (DEBUG_TOOLS.md "Kill"; zero arguments by contract): the normal death path, exactly as a
## killing blow runs it. The owner grants the canonical EXP, rolls the drops (Events.loot_dropped) and announces
## Events.monster_killed; `died` then reports a slot monster to MapInstanceView (the slot respawns on its tick), while
## a debug spawn has no slot and nothing reports it. Returns false when the monster was already dead or dying.
func debug_kill() -> bool:
	if _dying or def == null:
		return false
	die()
	return true


## True when this monster fills a spawn slot of its map (debug and free spawns do not).
func has_slot() -> bool:
	return slot_index >= 0


## True for a debug-console spawn (DebugCommands sets the metadata debug_spawn = true).
func is_debug_spawn() -> bool:
	return bool(get_meta("debug_spawn", false))


## Returns home (fell off the world).
func recover() -> void:
	recoveries += 1
	airborne = false
	vertical_speed = 0.0
	_hop = {}
	global_transform = home
	settle()


# =================================================================================================================
# Movement
# =================================================================================================================

func _step_walk(delta: float) -> void:
	var target := attacker.global_position if attacker != null and is_instance_valid(attacker) else global_position
	var dir := brain.move_dir(global_position, target)
	if dir == Vector3.ZERO:
		return
	facing = dir
	if def.is_jumper() and brain.take_hop() and _try_hop(dir):
		return
	var why := probe(dir)
	if why == "" and _advance(dir, def.move_speed_mps * delta):
		return
	if why == "":
		why = "ledge"
	if def.is_jumper() and _try_hop(dir):
		return
	blocked_by[why] = int(blocked_by.get(why, 0)) + 1
	brain.on_blocked()
	if brain.mode == MonsterBrain.Mode.WALK:
		facing = brain.heading


func _step_push(delta: float) -> void:
	if brain.push_left <= 0.0:
		return
	var d := minf(brain.push_speed() * delta, brain.push_left)
	brain.push_left -= d
	if probe(brain.push_dir) != "" or not _advance(brain.push_dir, d):
		brain.push_left = 0.0


## What stops a step in `dir`: "" (free), "region", "wall" or "ledge".
func probe(dir: Vector3) -> String:
	var pos := global_position
	var ahead := pos + dir * def.probe_ahead_m
	if region != null and not region.allows_step(pos, ahead):
		return "region"
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space != null:
		var h := Vector3.UP * def.wall_probe_height_m
		var side := Vector3.UP.cross(dir).normalized() * def.capsule_radius_m
		for off in [Vector3.ZERO, side, -side]:
			var q := PhysicsRayQueryParameters3D.create(pos + h + off, ahead + h + off, WorldLayers.MONSTER_MASK, [get_rid()])
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and (hit.normal as Vector3).y < _wall_cos:
				return "wall"
	if ground != null:
		var g := ground.ground_at(ahead, def.ledge_tolerance_m, def.ledge_tolerance_m)
		if not bool(g.ok):
			return "ledge"
	return ""


## Moves `dist` along `dir` onto the ground found there (within the ledge tolerance). False when there is none.
func _advance(dir: Vector3, dist: float) -> bool:
	var to := global_position + dir * dist
	var y := to.y
	if ground != null:
		var g := ground.ground_at(to, def.ledge_tolerance_m, def.ledge_tolerance_m)
		if not bool(g.ok):
			return false
		y = float(g.y)
	global_position = Vector3(to.x, y, to.z)
	distance_walked += dist
	_walking = true
	return true


## A jumper's hop in `dir`: a ballistic arc with the character's canonical base apex and the canonical gravity,
## landing one walk-speed airtime ahead on walkable ground up to hop_max_rise_apex_fraction of the apex above or
## hop_max_drop_m below (both from the species adaptation, monsters/_shared.json unless the species overrides them),
## inside the mob region, with a clear path. False (and nothing changes) when any of that fails.
func _try_hop(dir: Vector3) -> bool:
	var g := def.gravity_mps2
	var h := def.hop_apex_m
	if g <= 0.0 or h <= 0.0 or ground == null:
		return false
	var t_up := sqrt(2.0 * h / g)
	var pos := global_position
	var dist := def.move_speed_mps * 2.0 * t_up
	var land := pos + dir * dist
	if region != null and not region.allows_step(pos, land):
		return false
	var rise := h * def.hop_max_rise_apex_fraction
	var gq := ground.ground_at(Vector3(land.x, pos.y, land.z), rise, def.hop_max_drop_m)
	if not bool(gq.ok):
		return false
	var y1 := float(gq.y)
	var dy := y1 - pos.y
	if dy > rise:
		return false
	land.y = y1
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space != null:
		var lift := Vector3.UP * def.wall_probe_height_m
		var peak := (pos + land) * 0.5
		peak.y = pos.y + h + def.wall_probe_height_m
		for seg in [[pos + lift, peak], [peak, land + lift]]:
			var q := PhysicsRayQueryParameters3D.create(seg[0], seg[1], WorldLayers.MONSTER_MASK, [get_rid()])
			if not space.intersect_ray(q).is_empty():
				return false
	var t_down := sqrt(2.0 * maxf(h - dy, 0.0) / g)
	_hop = {"from": pos, "to": land, "t": 0.0, "T": t_up + t_down, "v0": g * t_up}
	airborne = true
	hops += 1
	facing = dir
	return true


func _step_air(delta: float) -> void:
	var g := def.gravity_mps2
	if not _hop.is_empty():
		_hop.t = float(_hop.t) + delta
		var t := minf(float(_hop.t), float(_hop.T))
		var s := t / maxf(float(_hop.T), 1e-4)
		var from: Vector3 = _hop.from
		var to: Vector3 = _hop.to
		var p := from.lerp(to, s)
		p.y = from.y + float(_hop.v0) * t - 0.5 * g * t * t
		global_position = p
		if float(_hop.t) >= float(_hop.T):
			global_position = to
			distance_walked += Vector2(to.x - from.x, to.z - from.z).length()
			_hop = {}
			airborne = false
		return
	# Falling (no ground under it: spawned in the air, or knocked over an edge the probes could not see).
	vertical_speed -= g * delta
	var start := global_position
	var drop := -vertical_speed * delta
	var end := start + Vector3.DOWN * drop
	if ground != null:
		var tol := def.fall_landing_tolerance_m
		var gq := ground.ground_at(Vector3(start.x, start.y, start.z), tol, drop + tol)
		if bool(gq.ok) and float(gq.y) >= end.y - tol:
			global_position.y = float(gq.y)
			airborne = false
			vertical_speed = 0.0
			return
	global_position = end
	if global_position.y < kill_y:
		recover()


func _build_body() -> void:
	if _shape != null:
		return
	_shape = CollisionShape3D.new()
	_shape.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = maxf(def.capsule_radius_m, 0.05)
	cap.height = maxf(def.capsule_height_m, cap.radius * 2.0)
	_shape.shape = cap
	_shape.position = Vector3.UP * (cap.height * 0.5)
	add_child(_shape)


func _on_faded_out() -> void:
	queue_free()
