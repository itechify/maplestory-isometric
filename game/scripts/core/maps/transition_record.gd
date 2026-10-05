class_name TransitionRecord
extends RefCounted
## One committed map change (MAP_ARCHITECTURE.md section 4.3 `last_transition`): {from, to, via, portal_id, arrival,
## t_game}. MapSession keeps the last 64 in a ring buffer for the debug overlay and the bot assertions.

var from_map: String = ""
var to_map: String = ""
var via: String = ""
var portal_id: String = ""
var arrival: ArrivalRef = null
## Game.clock when the swap happened.
var t_game: float = 0.0
## The world transform the player was placed at (warps); identity for gates and headless sessions.
var arrival_xform: Transform3D = Transform3D.IDENTITY
## Physics frames between the end of the fade-in and the first grounded frame (-1 until known; counted again from
## the re-placement when `replaced`).
var frames_to_ground: int = -1
## True when the player found no floor within transition.arrive_replace_frames and was re-placed at
## player_spawns[0] (MAP_ARCHITECTURE section 4.5 step 14: the traversal bot fails on this).
var replaced: bool = false
## Load fallback step used ("" for non-load transitions).
var load_step: String = ""


func to_dict() -> Dictionary:
	return {
		"from": from_map,
		"to": to_map,
		"via": via,
		"portal_id": portal_id,
		"arrival": arrival.to_dict() if arrival != null else {},
		"t_game": t_game,
		"frames_to_ground": frames_to_ground,
		"replaced": replaced,
		"load_step": load_step,
	}


func _to_string() -> String:
	return "%s -> %s via %s%s" % [from_map, to_map, via, (" (%s)" % portal_id) if portal_id != "" else ""]
