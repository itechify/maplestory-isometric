class_name ArrivalRef
extends RefCounted
## Where a traveller arrives in a map: one of its portals, or one of its player spawn points
## (MAP_ARCHITECTURE.md section 4.3 `last_arrival`, section 4.9 save `entry`).
##
## Exactly one of portal_id / spawn_index is meaningful: a non-empty portal_id wins, otherwise spawn_index (>= 0).
## Saved as {"map_id", "portal_id"} or {"map_id", "spawn_index"}.

var map_id: String = ""
var portal_id: String = ""
var spawn_index: int = -1


## Arrival at a portal's spawn_transform.
static func at_portal(p_map_id: String, p_portal_id: String) -> ArrivalRef:
	var a := ArrivalRef.new()
	a.map_id = p_map_id
	a.portal_id = p_portal_id
	return a


## Arrival at player_spawns[index].
static func at_spawn(p_map_id: String, index: int = 0) -> ArrivalRef:
	var a := ArrivalRef.new()
	a.map_id = p_map_id
	a.spawn_index = index
	return a


func is_portal() -> bool:
	return portal_id != ""


func duplicate_ref() -> ArrivalRef:
	var a := ArrivalRef.new()
	a.map_id = map_id
	a.portal_id = portal_id
	a.spawn_index = spawn_index
	return a


func equals(other: ArrivalRef) -> bool:
	if other == null:
		return false
	if map_id != other.map_id or is_portal() != other.is_portal():
		return false
	return portal_id == other.portal_id if is_portal() else spawn_index == other.spawn_index


## Save form: {"map_id", "portal_id"} or {"map_id", "spawn_index"}.
func to_dict() -> Dictionary:
	if is_portal():
		return {"map_id": map_id, "portal_id": portal_id}
	return {"map_id": map_id, "spawn_index": maxi(spawn_index, 0)}


## Tolerant inverse of to_dict(); returns null for anything that names no map.
static func from_dict(d: Variant) -> ArrivalRef:
	if not (d is Dictionary):
		return null
	var dict: Dictionary = d
	var m := String(dict.get("map_id", ""))
	if m == "":
		return null
	var portal := String(dict.get("portal_id", "")) if dict.get("portal_id", null) != null else ""
	if portal != "":
		return ArrivalRef.at_portal(m, portal)
	return ArrivalRef.at_spawn(m, int(dict.get("spawn_index", 0)))


func _to_string() -> String:
	return "%s.%s" % [map_id, portal_id] if is_portal() else "%s#sp%d" % [map_id, spawn_index]
