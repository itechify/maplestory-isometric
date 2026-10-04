class_name PortalDef
extends RefCounted
## One portal (MAP_ARCHITECTURE.md section 4.4): a canonical MeowDB portal, or an adaptation arrival gate.
##
## MeowDB decides what it is and where it leads (portal_id, source/destination map, canonical_type); the Blender
## sidecar decides where it stands (anchor_transform, inward); PortalGraph resolves the destination portal;
## the world grounds spawn_transform on collision. There is no per-map portal script: portal.tscn renders any
## PortalDef.

const TYPE_EDGE := "edge"
const TYPE_DOOR := "door"
const TYPE_ARRIVAL := "arrival"
const INTERACT_PRESS_UP := "press_up"
const INTERACT_PRESS_UP_OR_WALK := "press_up_or_walk"
const INTERACT_WALK_ONLY := "walk_only"
const LINK_EDGE := "edge"
const LINK_WARP := "warp"

## MeowDB portal name ("east00"), or "arrival:<trail_id>" for an adaptation arrival gate.
var portal_id: String = ""
var source_map_id: String = ""
## MeowDB toMapId ("" for arrival-only gates).
var destination_map_id: String = ""
## Resolved destination portal; "" means arrive at destination_spawn_index.
var destination_portal_id: String = ""
var destination_spawn_index: int = -1
## Where a traveller ARRIVING at this portal appears: the anchor + inset along `inward`, facing inward, grounded.
var spawn_transform: Transform3D = Transform3D.IDENTITY
## "edge", "door" or "arrival".
var portal_type: String = TYPE_EDGE
## MeowDB portal type (1 hidden, 2 visible), -1 for an adaptation.
var canonical_type: int = -1
## "press_up", "press_up_or_walk" or "walk_only".
var interaction_type: String = INTERACT_PRESS_UP
## "edge" or "warp" (portal_adaptations.json).
var link_mode: String = LINK_WARP
## Link this portal is an end of (T_<mapA>_<portalA>__<mapB>_<portalB>); doubles as trail_id for edges.
var link_id: String = ""
var trail_id: String = ""
## {meowdb_url, v8_name_match: bool, v8_to_portal, resolution: "override"|"reciprocal"|"player_spawn", override_reason?}
var provenance: Dictionary = {}

# --- adaptation geometry (sidecar) -------------------------------------------------------------------------
## The sidecar marker transform (identity when the sidecar has no marker for this portal).
var anchor_transform: Transform3D = Transform3D.IDENTITY
var has_anchor: bool = false
## Unit ground direction pointing into the map: -anchor_normal for edges, the door's facing for doors.
var inward: Vector3 = Vector3.BACK
## Library asset shown at the anchor ("" = nothing, e.g. hidden type-1 portals and arrival gates).
var visual: String = ""
## True for hidden canonical types (portal_adaptations.json hidden_portal_types): no swirl, no prompt.
var hidden: bool = false
## Trigger box size: x = width (lateral), y = height, z = depth (along inward).
var trigger_size: Vector3 = Vector3.ONE
## The anchor point snapped to the ground (where a player stands inside the trigger).
var anchor_ground: Vector3 = Vector3.ZERO
## Set by MapDefinitions.ground_all(): spawn_transform sits on walkable collision.
var grounded: bool = false
var ground_note: String = ""


## "<map_id>.<portal_id>", unique across the island.
func key() -> String:
	return "%s.%s" % [source_map_id, portal_id]


func is_canonical() -> bool:
	return canonical_type >= 0


## True when pressing Up (or interact) can use this portal.
func accepts_press() -> bool:
	return interaction_type != INTERACT_WALK_ONLY


## Trigger box centre and orientation: basis x = lateral, y = up, z = inward; origin at mid-height on the anchor.
func trigger_transform() -> Transform3D:
	var z := Vector3(inward.x, 0.0, inward.z)
	if z.length_squared() < 0.0001:
		z = Vector3.BACK
	z = z.normalized()
	var x := Vector3.UP.cross(z).normalized()
	var base := anchor_ground if has_anchor else anchor_transform.origin
	return Transform3D(Basis(x, Vector3.UP, z), base + Vector3.UP * (trigger_size.y * 0.5))


## Pure point-in-trigger test (static L1 checks; the live node uses its Area3D as well).
func trigger_contains(p: Vector3) -> bool:
	var local := trigger_transform().affine_inverse() * p
	var half := trigger_size * 0.5
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z


func to_dict() -> Dictionary:
	return {
		"portal_id": portal_id,
		"source_map_id": source_map_id,
		"destination_map_id": destination_map_id,
		"destination_portal_id": destination_portal_id,
		"destination_spawn_index": destination_spawn_index,
		"portal_type": portal_type,
		"canonical_type": canonical_type,
		"interaction_type": interaction_type,
		"link_mode": link_mode,
		"link_id": link_id,
		"trail_id": trail_id,
		"hidden": hidden,
		"has_anchor": has_anchor,
		"grounded": grounded,
		"spawn": [spawn_transform.origin.x, spawn_transform.origin.y, spawn_transform.origin.z],
		"provenance": provenance.duplicate(true),
	}


func _to_string() -> String:
	var dest := destination_portal_id if destination_portal_id != "" else "sp%d" % destination_spawn_index
	return "%s -> %s.%s" % [key(), destination_map_id, dest]
