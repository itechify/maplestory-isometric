class_name RegionMonitor
extends Node
## The map identity invariant and the trail HUD line (MAP_ARCHITECTURE.md sections 4.3 and 4.11, milestone M2).
##
## presentation.json region_invariant.sample_hz times a second while MapSession is IDLE:
##   invariant  the player's last ground point (the feet the last tick it stood on the floor) must lie in
##              current_map, in a trail touching current_map, or in the map of an armed gate
##              (RegionIndex.allowed). violation_samples failing samples in a row are one violation: push_error with
##              the position (dev and test builds fail on it; the traversal bot counts `violations`), and in a
##              release build the player also recovers to SafeGround.
##   trail      the trail under the live position (a zone touching current_map, outside every footprint). Its other
##              map is handed to MapSession.set_trail(), which emits MapSession.trail_changed(destination) for the
##              HUD line "-> <destination map name>" ("" when the player leaves the trail).
## current_map is never changed here: MapSession owns it.

signal violated(position: Vector3, current_map: String, region: Dictionary)

var world: Node = null
## Violations reported (each is violation_samples failing samples in a row).
var violations: int = 0
## Samples taken and failing samples seen (for tests and the bot).
var samples: int = 0
var failed_samples: int = 0
## The last reported violation: {position, current_map, region} ({} before any).
var last_violation: Dictionary = {}

var _acc: float = 0.0
var _consecutive: int = 0
var _last_ground: Vector3 = Vector3.INF
var _map: String = ""


## Forgets the last ground point and the failing streak (after a teleport or a transition).
func reset() -> void:
	_last_ground = Vector3.INF
	_consecutive = 0
	_acc = 0.0


func _physics_process(delta: float) -> void:
	if world == null:
		return
	var session: Node = world.call("session_node")
	var p: Node3D = world.get("player")
	var region: RegionIndex = world.get("region_index")
	var tuning: WorldTuning = world.get("tuning")
	if session == null or p == null or region == null or tuning == null or not is_instance_valid(p):
		return
	if not bool(session.call("is_idle")):
		reset()
		return
	var cur := String(session.get("current_map"))
	if cur == "":
		return
	if cur != _map:
		_map = cur
		reset()
	var on_floor := bool(p.call("is_on_floor")) if p.has_method("is_on_floor") else true
	var climbing := bool(p.call("is_climbing")) if p.has_method("is_climbing") else false
	if on_floor or climbing:
		_last_ground = p.global_position
	_acc += delta
	var period := 1.0 / maxf(tuning.num("region_invariant", "sample_hz"), 0.001)
	if _acc + 1e-6 < period:
		return
	_acc = fmod(_acc, period)
	samples += 1
	_update_trail(session, region, p.global_position, cur)
	var pos := _last_ground if _last_ground != Vector3.INF else p.global_position
	var gates: Node = world.get("gate_monitor")
	var armed: PackedStringArray = gates.call("armed_maps") if gates != null else PackedStringArray()
	if region.allowed(pos, cur, armed):
		_consecutive = 0
		return
	failed_samples += 1
	_consecutive += 1
	if _consecutive != tuning.count("region_invariant", "violation_samples"):
		return
	violations += 1
	var r := region.region_of(pos, cur)
	last_violation = {"position": pos, "current_map": cur, "region": r}
	push_error("[RegionMonitor] identity invariant: the player's ground point %s lies in %s %s, not in %s or its trails (armed gates: %s)" % [
		pos, String(r.kind), String(r.id), cur, ", ".join(armed)])
	violated.emit(pos, cur, r)
	if not OS.is_debug_build():
		var fr: Node = world.get("fall_recovery")
		if fr != null:
			fr.call("recover", "region invariant")
		reset()


func _update_trail(session: Node, region: RegionIndex, pos: Vector3, cur: String) -> void:
	if not session.has_method("set_trail"):
		return
	var r := region.region_of(pos, cur)
	var link := ""
	var dest := ""
	if String(r.kind) == RegionIndex.KIND_TRAIL and cur in (r.maps as PackedStringArray):
		link = String(r.id)
		for m in (r.maps as PackedStringArray):
			if m != cur:
				dest = m
	session.call("set_trail", link, dest)
