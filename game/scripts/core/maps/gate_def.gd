class_name GateDef
extends RefCounted
## A walk-through commit plane at one end of a trail (MAP_ARCHITECTURE.md section 4.4 "Gates"). Pure.
##
## A gate is a vertical plane on a map's containment ring line (footprint + containment.ring_offset_m), across the
## trail mouth, with `normal` pointing INTO `map_id`. It is the same line as the map's RegionIndex boundary and the
## ring gap (sections 4.3, 4.6). Crossing it inward arms it (also mid-jump or under knockback); the first grounded
## tick after hit-stun with the feet still inside commits the trail's link: MapSession.transition(via gate) from
## the map on the other end of the trail into `map_id`. Walking back out onto the trail (more than `disarm_back`
## behind the plane) disarms it. GateMonitor runs step() each physics tick for the far-end gates of the trails
## touching current_map, and only on edge-mode links.
##
##   d_prev = dot(p_prev - origin, normal); d_now = dot(p_now - origin, normal)
##   in_box = |dot(p_now - origin, lateral)| <= half_width and -below <= p_now.y - origin.y <= height
##   d_prev <= 0 < d_now and in_box          -> armed
##   d_now < -disarm_back                    -> disarmed
##   armed and d_now > 0 and on_floor and not in_hitstun -> commit (and disarm)

## The link (trail) this gate belongs to.
var link_id: String = ""
## The map this gate leads into: its region lies on the +normal side of the plane.
var map_id: String = ""
## The map at the trail's other end (where a traveller through this gate comes from).
var from_map_id: String = ""
## The PortalDef of map_id at this trail end (a canonical edge portal, or the 000000040 arrival gate).
var portal: PortalDef = null
## The PortalDef of from_map_id at the trail's other end: the source portal of a commit through this gate. Null
## when from_map_id has no portal into map_id (the 000000030 end of the one-way 30 -> 40 trail).
var source_portal: PortalDef = null
## A point of the plane on the ring line, at the height of the ground just inside map_id.
var origin: Vector3 = Vector3.ZERO
## Unit, horizontal, pointing into map_id (the portal's inward direction).
var normal: Vector3 = Vector3.BACK
## Unit, horizontal, along the plane (UP x normal).
var lateral: Vector3 = Vector3.RIGHT
var half_width: float = 2.25
var height: float = 3.0
var below: float = 1.0
var disarm_back: float = 0.25
## True between an inward crossing and the commit (or a walk back out).
var armed: bool = false


## Builds a gate on the plane through `at` (ring line) with inward `inward`; sizes from portal_adaptations.json gates.
static func make(link: String, into_map: String, from_map: String, at: Vector3, inward: Vector3, sizes: Dictionary) -> GateDef:
	var g := GateDef.new()
	g.link_id = link
	g.map_id = into_map
	g.from_map_id = from_map
	g.origin = at
	var n := Vector3(inward.x, 0.0, inward.z)
	g.normal = n.normalized() if n.length_squared() > 1e-9 else Vector3.BACK
	g.lateral = Vector3.UP.cross(g.normal).normalized()
	g.half_width = float(sizes.get("half_width_m", g.half_width))
	g.height = float(sizes.get("height_m", g.height))
	g.below = float(sizes.get("below_m", g.below))
	g.disarm_back = float(sizes.get("disarm_back_m", g.disarm_back))
	return g


## "<link_id>><map_id>": unique per gate.
func key() -> String:
	return "%s>%s" % [link_id, map_id]


## Signed distance of `p` from the plane; positive inside map_id.
func signed_distance(p: Vector3) -> float:
	return (p - origin).dot(normal)


## Lateral offset of `p` along the plane from the origin.
func lateral_offset(p: Vector3) -> float:
	return (p - origin).dot(lateral)


## True when `p` lies within the gate's box (lateral half-width, `below` under to `height` above the origin).
func in_box(p: Vector3) -> bool:
	var dy := p.y - origin.y
	return absf(lateral_offset(p)) <= half_width and dy >= -below and dy <= height


## One physics tick of the arm/commit rule (class doc). Returns true when the gate commits this tick; it is then
## disarmed. The caller decides whether the link may be travelled (PortalGraph.has_direction) and transitions.
func step(p_prev: Vector3, p_now: Vector3, on_floor: bool, in_hitstun: bool) -> bool:
	var d_prev := signed_distance(p_prev)
	var d_now := signed_distance(p_now)
	if d_prev <= 0.0 and d_now > 0.0 and in_box(p_now):
		armed = true
	if d_now < -disarm_back:
		armed = false
	if armed and d_now > 0.0 and on_floor and not in_hitstun:
		armed = false
		return true
	return false


func to_dict() -> Dictionary:
	return {"link_id": link_id, "map_id": map_id, "from_map_id": from_map_id,
		"portal": portal.key() if portal != null else "", "source_portal": source_portal.key() if source_portal != null else "",
		"origin": [origin.x, origin.y, origin.z], "normal": [normal.x, normal.z], "half_width": half_width, "armed": armed}


func _to_string() -> String:
	return "Gate(%s into %s at %s)" % [link_id, map_id, origin]
