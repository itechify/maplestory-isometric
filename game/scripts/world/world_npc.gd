class_name WorldNpc
extends Node3D
## A resident NPC (MAP_ARCHITECTURE.md section 4.7.5): instantiated once at world load at its NpcPlacement, a static
## proxy from _library.glb (or a labelled placeholder), and an Area3D talk zone for the NPC/dialogue system.
##
## Metadata for other systems: npc_id (MeowDB id, the key quests and dialogue use), npc_name, map_id. Group "npcs".
## Interaction is enabled only while npc.map_id == MapSession.current_map: the talk Area3D then monitors the player
## layer and is monitorable on the interactables layer; otherwise both are off and `interaction_enabled` is false.

var placement: NpcPlacement = null
var interaction_enabled: bool = false
var talk_area: Area3D = null
var visual: Node3D = null
## The talk zone (WorldTuning.talk_zone): a sphere of talk_radius_m centred talk_centre_height_m above the feet.
var talk_radius_m: float = 0.0
var talk_centre_height_m: float = 0.0
## The npc.talk_zones profile the zone came from ("default" when none lists this NPC).
var talk_profile: String = "default"


## Configures the node (call after it is in the tree). `radius` and `centre_height` describe the talk zone, a sphere
## centred `centre_height` above the NPC's feet (WorldTuning.talk_zone: presentation.json npc.interaction_radius_m
## and npc.talk_centre_height_m, or a npc.talk_zones profile such as the shopkeepers' "across_counter"). A NAN
## centre_height keeps the old rule, half the radius.
func setup(pl: NpcPlacement, library: ProxyLibrary, radius: float, centre_height: float = NAN,
		profile: String = "default") -> void:
	talk_radius_m = radius
	talk_centre_height_m = radius * 0.5 if is_nan(centre_height) else centre_height
	talk_profile = profile
	placement = pl
	name = ("NPC_%s_%s" % [pl.npc_id, pl.npc_name]).validate_node_name()
	global_transform = pl.transform
	set_meta("npc_id", pl.npc_id)
	set_meta("npc_name", pl.npc_name)
	set_meta("map_id", pl.map_id)
	add_to_group(&"npcs")
	if library != null:
		visual = library.instance_or_placeholder(pl.proxy, pl.npc_name, "Player_Proxy")
		visual.name = "Visual"
		add_child(visual)
	talk_area = Area3D.new()
	talk_area.name = "TalkArea"
	talk_area.collision_layer = WorldLayers.INTERACTABLES
	talk_area.collision_mask = WorldLayers.PLAYER
	talk_area.set_meta("npc_id", pl.npc_id)
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	cs.shape = sphere
	cs.position = Vector3.UP * talk_centre_height_m
	talk_area.add_child(cs)
	add_child(talk_area)
	set_interaction_enabled(false)


func npc_id() -> String:
	return placement.npc_id if placement != null else ""


func map_id() -> String:
	return placement.map_id if placement != null else ""


func set_interaction_enabled(on: bool) -> void:
	interaction_enabled = on
	set_meta("interactable", on)
	if talk_area != null:
		talk_area.monitoring = on
		talk_area.monitorable = on


## True when `body` is within talk range (Area3D overlap, or distance as a fallback for off-layer bodies).
func in_range(body: Node3D, radius: float) -> bool:
	if not interaction_enabled or body == null:
		return false
	if body is CollisionObject3D and talk_area != null and talk_area.overlaps_body(body):
		return true
	return body.global_position.distance_to(global_position) <= radius
