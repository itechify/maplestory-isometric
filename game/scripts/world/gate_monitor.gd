class_name GateMonitor
extends Node
## Walk-through gate commits (MAP_ARCHITECTURE.md section 4.4 "Gates", milestone M2).
##
## Each physics tick while MapSession is IDLE, the far-end gates of the edge-mode trails touching current_map
## (MapDefinitions.far_gates: the gate into the OTHER map of each trail, at most 8) run GateDef.step() on the
## player's feet position (previous tick -> this tick): an inward crossing arms a gate, also mid-jump or under
## knockback; the first grounded tick after hit-stun with the feet inside commits it through
## MapSession.transition(via "gate") with the trail's source portal and that portal's arrival (so a walk and a
## press-Up record the same last_arrival). The trail belongs to the map the player came from: the gates of
## current_map itself are never tested, so turning back on a trail changes nothing and nothing ping-pongs.
## A gate whose map cannot be entered from current_map (PortalGraph.has_direction false: the 000000030 end of the
## one-way trail) reports one error; containment makes it unreachable.
##
## It runs after the player and PortalInteractor (physics priority 150) and before MapSession (200). A tick that
## moves the feet farther than gates.teleport_step_m is a teleport (warp, recovery, load), never a crossing; so is
## the first tick after any transition.

## After the player (0) and PortalInteractor (100), before MapSession (200). Structural ordering.
const PHYSICS_PRIORITY := 150

## A gate committed (after MapSession accepted the transition).
signal gate_committed(gate: GateDef)

var world: Node = null
## Gate commits accepted by MapSession (for tests and the traversal bot).
var commits: int = 0
## Errors reported (a gate without a link, a rejected commit).
var errors: PackedStringArray = []
var last_commit: GateDef = null

var _prev: Vector3 = Vector3.INF
var _map: String = ""
var _gates: Array[GateDef] = []
var _reported: Dictionary = {}


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY


## Forgets the previous position and disarms every gate (after a teleport, a transition or a recovery).
func reset() -> void:
	_prev = Vector3.INF
	for g in _gates:
		g.armed = false


## The gates tested while `current_map` is current (edge-mode trails only), with their armed state.
func active_gates() -> Array[GateDef]:
	return _gates.duplicate()


## Maps of the gates armed right now (RegionMonitor allows the player's ground point in them).
func armed_maps() -> PackedStringArray:
	var out := PackedStringArray()
	for g in _gates:
		if g.armed and not (g.map_id in out):
			out.append(g.map_id)
	return out


## Re-reads the active gates (call when link modes change; the monitor also refreshes on every map change).
func refresh() -> void:
	_map = ""


func _physics_process(_delta: float) -> void:
	if world == null:
		return
	var session: Node = world.call("session_node")
	var p: Node3D = world.get("player")
	var defs: MapDefinitions = world.get("defs")
	if session == null or p == null or defs == null or not is_instance_valid(p):
		return
	if not bool(session.call("is_idle")):
		_prev = Vector3.INF
		return
	var cur := String(session.get("current_map"))
	if cur != _map:
		for g in _gates:
			g.armed = false
		_map = cur
		_gates = defs.far_gates(cur)
		_prev = Vector3.INF
	var now := p.global_position
	var tuning: WorldTuning = defs.tuning
	if _prev == Vector3.INF or now.distance_to(_prev) > tuning.portal_num("gates", "teleport_step_m"):
		_prev = now
		return
	var on_floor := bool(p.call("is_on_floor")) if p.has_method("is_on_floor") else true
	var hitstun := "in_hitstun" in p and bool(p.get("in_hitstun"))
	for g in _gates:
		if not defs.graph.is_edge(g.link_id):
			g.armed = false
			continue
		if g.step(_prev, now, on_floor, hitstun):
			_prev = now
			_commit(g, session, defs, cur)
			return
	_prev = now


func _commit(g: GateDef, session: Node, defs: MapDefinitions, cur: String) -> void:
	var src := g.source_portal
	if src == null or src.source_map_id != cur or not defs.graph.has_direction(cur, g.map_id):
		_report("gate %s: no link %s -> %s; containment should make this gate unreachable" % [g.key(), cur, g.map_id])
		return
	var req := TransitionRequest.make(g.map_id, defs.arrival_for(src), "gate", src)
	var err: int = session.call("transition", req)
	if err != OK:
		_report("gate %s: MapSession rejected the commit (%s)" % [g.key(), String(session.get("last_error"))])
		return
	commits += 1
	last_commit = g
	gate_committed.emit(g)
	reset()


func _report(msg: String) -> void:
	errors.append(msg)
	if _reported.has(msg):
		return
	_reported[msg] = true
	push_error("[GateMonitor] " + msg)
