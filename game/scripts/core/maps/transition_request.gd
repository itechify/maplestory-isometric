class_name TransitionRequest
extends RefCounted
## Input of MapSession.transition() (MAP_ARCHITECTURE.md section 4.5): {to_map, arrival, via, source_portal}.
##
## `arrival` is an ArrivalRef (a portal or a player spawn of to_map); a load may instead carry an explicit,
## already validated world transform (`arrival_xform` with has_xform = true) plus the ArrivalRef recorded as
## last_arrival. `via` is one of MapSession.VIA_* ("gate", "press_up", "door", "respawn", "load", "debug").

var to_map: String = ""
var arrival: ArrivalRef = null
var arrival_xform: Transform3D = Transform3D.IDENTITY
var has_xform: bool = false
var via: String = ""
## The portal used (press_up, door, gate); null otherwise.
var source_portal: PortalDef = null
## For loads: which step of the fallback chain produced the arrival ("resume", "entry", "player_spawn", "fallback_map").
var load_step: String = ""


static func make(p_to_map: String, p_arrival: ArrivalRef, p_via: String, p_source: PortalDef = null) -> TransitionRequest:
	var r := TransitionRequest.new()
	r.to_map = p_to_map
	r.arrival = p_arrival
	r.via = p_via
	r.source_portal = p_source
	return r


## A request whose arrival is an explicit transform (a validated save `resume` point).
static func make_xform(p_to_map: String, xform: Transform3D, recorded: ArrivalRef, p_via: String) -> TransitionRequest:
	var r := TransitionRequest.make(p_to_map, recorded, p_via)
	r.arrival_xform = xform
	r.has_xform = true
	return r


func source_portal_id() -> String:
	return source_portal.portal_id if source_portal != null else ""
