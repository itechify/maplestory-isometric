class_name NpcPlacement
extends RefCounted
## A MeowDB NPC placed in 3D (MAP_ARCHITECTURE.md sections 3.3 and 4.7.5).
##
## The runtime creates NPCs only from MeowDB's per-map npc lists (npc_id is the MeowDB id, "8" = Robin). The
## transform comes from the Blender NPC marker with the same name; when the export has no marker yet, a
## deterministic fallback next to player_spawns[0] is used and from_marker is false (a warning is logged).

var npc_id: String = ""
var npc_name: String = ""
var map_id: String = ""
var transform: Transform3D = Transform3D.IDENTITY
## _library.glb asset for the static proxy ("NPC_Robin"); may not exist in the library (fallback visual then).
var proxy: String = ""
var from_marker: bool = false
var grounded: bool = false


func to_dict() -> Dictionary:
	var o := transform.origin
	return {"npc_id": npc_id, "name": npc_name, "map_id": map_id, "proxy": proxy, "from_marker": from_marker,
		"grounded": grounded, "position": [o.x, o.y, o.z]}
