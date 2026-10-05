class_name BreakablePlacement
extends RefCounted
## One breakable placement in 3D (contract C8): canonical maps/<id>.json reactors[index] placed on the map by
## BreakablePlacementPlanner.
##
## index, breakable_id and respawn_s are canonical and never change; transform, region and placement are the
## adaptation (data/misostory/breakables.json placement).

const UNPLACED := "unplaced"

var map_id: String = ""
## Index into the map's canonical reactors[] (the placement index; MapInstanceState.breakables[index]).
var index: int = -1
## MeowDB breakable id ("0000001", the Wooden Box).
var breakable_id: String = ""
## Seconds until a broken box comes back (canonical reactors[index].respawn_s).
var respawn_s: float = 0.0
## Feet on the ground, with a seeded yaw (presentation).
var transform: Transform3D = Transform3D.IDENTITY
## Where it was sampled: an exported spawn area's name, or "floor" (the mob region and region extensions).
var region: String = ""
## "area" (on its spawn area's own tier), "area_relaxed" (any walkable top surface in the area), "floor" (on the
## map's base floor tier), "floor_relaxed" (any walkable top surface of the floor) or "unplaced" (nothing passed;
## logged).
var placement: String = UNPLACED
var grounded: bool = false


func position() -> Vector3:
	return transform.origin


## "<map_id>:<index>" (BreakableRules.placement_key).
func key() -> String:
	return BreakableRules.placement_key(map_id, index)


func is_placed() -> bool:
	return placement != UNPLACED


func to_dict() -> Dictionary:
	var o := transform.origin
	return {"key": key(), "index": index, "breakable_id": breakable_id, "respawn_s": respawn_s, "region": region,
		"placement": placement, "grounded": grounded, "position": [o.x, o.y, o.z]}
