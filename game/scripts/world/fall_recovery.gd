class_name FallRecovery
extends Node
## Fall recovery (MAP_ARCHITECTURE.md section 4.6): an airborne player below the current map's kill_y (which
## includes the lowest point of its trails), or one that reaches the sea kill plane, returns to the last SafeGround
## point with no damage. MeowDB documents fall damage (canonical formulas/movement.json fall_damage); MisoStory
## applies none, an adaptation (presentation.json fall_recovery; parity row mechanic:fall-damage).
## Each recovery logs one line and counts in `recoveries` (the traversal tour requires zero).
##
## SafeGround (scripts/actors/player/safe_ground.gd) is recorded by the player controller; when the player exposes
## `safe_ground: SafeGround`, that record is used, and the world installs its region check as the controller's
## `safe_ground_filter` (Callable(pos: Vector3) -> bool) when the player has one. A player without its own record
## (e.g. the world's test capsule) is tracked here with the same rules: on the floor, not in hit-stun, on walkable
## collision, inside the current map's region.

signal recovered(reason: String, position: Vector3)

var world: Node = null
var recoveries: int = 0
var _own: SafeGround = SafeGround.new()


## Hooks the SafeGround filter into a controller that supports it. The two-argument form (position, floor collider)
## is installed, which the controller calls when it accepts two arguments.
func attach_player(p: Node3D) -> void:
	_own = SafeGround.new()
	if p != null and "safe_ground_filter" in p:
		p.set("safe_ground_filter", is_safe_standing)


## The SafeGround record in use: the player's own, else this node's.
func safe_ground() -> SafeGround:
	var p: Node3D = world.get("player") if world != null else null
	if p != null and "safe_ground" in p:
		var sg: Variant = p.get("safe_ground")
		if sg is SafeGround:
			return sg
	return _own


func uses_own_record() -> bool:
	return safe_ground() == _own


## The region filter: inside the current map's footprint region, or on a trail touching the current map (the trail
## belongs to the map the player came from, MAP_ARCHITECTURE section 4.4).
func is_safe_point(pos: Vector3) -> bool:
	var def := _current_def()
	if def == null:
		return false
	var region: RegionIndex = world.get("region_index")
	return region != null and region.allowed(pos, def.map_id)


## The controller's SafeGround filter (MAP_ARCHITECTURE section 4.6): the feet stand on walkable collision (a
## blocking slab within the coplanar tolerance of walkable ground counts, as for every ground probe) inside the
## current map's region or on one of its trails. A controller whose feet also sense blocking or scenery tops (a hull, a fence, a rock) never
## records a safe point there, so fall recovery and save resume points always land on walkable ground.
func is_safe_standing(pos: Vector3, _floor_collider: Variant) -> bool:
	return is_safe_point(pos) and _walkable_under(pos)


func _walkable_under(pos: Vector3) -> bool:
	var q: PhysicsGroundQuery = world.get("ground_query") if world != null else null
	var tuning: WorldTuning = world.get("tuning") if world != null else null
	if q == null or tuning == null:
		return false
	return bool(q.walkable_below(pos, tuning.num("grounding", "grounded_tolerance_m")).get("ok", false))


## Forces the safe point (after a teleport/arrival); the real controller resets its own in teleport().
func reset_to(xform: Transform3D) -> void:
	_own.reset(xform.origin, xform.basis.z)


## Returns the player to the last safe point (or player_spawns[0] of the current map when there is none).
func recover(reason: String) -> void:
	var def := _current_def()
	var sg := safe_ground()
	var xf: Transform3D = sg.transform() if sg.valid else (def.player_spawn(0) if def != null else Transform3D.IDENTITY)
	recoveries += 1
	print("[FallRecovery] %s in %s: back to %s" % [reason, def.map_id if def != null else "?", xf.origin])
	world.call("place_player", xf)
	recovered.emit(reason, xf.origin)


func _physics_process(_delta: float) -> void:
	if world == null:
		return
	var p: Node3D = world.get("player")
	var session: Node = world.call("session_node")
	if p == null or session == null or not bool(session.call("is_idle")):
		return
	var def := _current_def()
	if def == null:
		return
	if uses_own_record():
		_track(p)
	if p.global_position.y < def.kill_y:
		recover("below kill_y %.1f" % def.kill_y)


func _track(p: Node3D) -> void:
	if not (p.has_method("is_on_floor") and bool(p.call("is_on_floor"))):
		return
	if "in_hitstun" in p and bool(p.get("in_hitstun")):
		return
	if not is_safe_standing(p.global_position, null):
		return
	_own.record(p.global_position, Vector3.UP, 0, p.global_transform.basis.z)


func _current_def() -> MapDefinition:
	if world == null:
		return null
	var session: Node = world.call("session_node")
	var defs: MapDefinitions = world.get("defs")
	if session == null or defs == null:
		return null
	return defs.get_def(String(session.get("current_map")))
