class_name WorldNpc
extends Node3D
## A resident NPC (MAP_ARCHITECTURE.md section 4.7.5): instantiated once at world load at its NpcPlacement, its model
## (the "Visual" child) and an Area3D talk zone for the NPC/dialogue system.
##
## Model, first found (feet at y = 0, front +Z):
##   1. the art pack's rigged model for the canonical NPC id (#66; `art`, looked up by id through ArtPack, never by
##      name), already at the character scale on its rig node, playing its looping idle clip from a phase of its own
##      (so the NPCs of a map do not breathe in step). NPCs only idle: they never walk or fight;
##   2. the static NPC_<name> proxy from _library.glb (NpcPlacement.proxy);
##   3. a labelled placeholder as tall as the player's proxy.
## Without the pack (a fresh clone, unit tests, the headless world tools) 2 and 3 stay as before. NpcPresenter adds the
## name tag, the quest marker, the bubbles, the turn toward the player, and the bob where no idle clip plays.
##
## Metadata for other systems: npc_id (MeowDB id, the key quests and dialogue use), npc_name, map_id. Group "npcs".
## Interaction is enabled only while npc.map_id == MapSession.current_map: the talk Area3D then monitors the player
## layer and is monitorable on the interactables layer; otherwise both are off and `interaction_enabled` is false.

## The rig's clip NPCs play (ArtImport makes it loop).
const CLIP_IDLE := "idle"

var placement: NpcPlacement = null
var interaction_enabled: bool = false
var talk_area: Area3D = null
var visual: Node3D = null
## The talk zone (WorldTuning.talk_zone): a sphere of talk_radius_m centred talk_centre_height_m above the feet.
var talk_radius_m: float = 0.0
var talk_centre_height_m: float = 0.0
## The npc.talk_zones profile the zone came from ("default" when none lists this NPC).
var talk_profile: String = "default"
## The art pack the model comes from (set before setup(); IslandWorld hands it its own). Null: the proxy.
var art: ArtPack = null
## Where the model came from: the pack model's res:// path, the library asset name, or "" for the placeholder.
var model_source: String = ""

var _anim: AnimationPlayer = null


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
	visual = _pack_model(pl.npc_id)
	if visual == null and library != null:
		visual = library.instance_or_placeholder(pl.proxy, pl.npc_name, "Player_Proxy")
		model_source = pl.proxy if not visual.has_meta("placeholder") else ""
	if visual != null:
		visual.name = "Visual"
		add_child(visual)
		_start_idle(pl.npc_id)
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


## The pack's model for canonical NPC `id`, or null (no pack, or no model for that id).
func _pack_model(id: String) -> Node3D:
	if art == null or not art.present():
		return null
	var inst := art.instance(ArtPack.NPC, id)
	if inst != null:
		model_source = art.model(ArtPack.NPC, id)
	return inst


## Plays the rig's idle clip from a phase derived from the NPC id (none on a proxy or the placeholder).
func _start_idle(id: String) -> void:
	_anim = visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not has_clip(CLIP_IDLE):
		return
	_anim.play(CLIP_IDLE)
	var length := _anim.current_animation_length
	if length > 0.0:
		_anim.seek(float(absi(hash(id)) % 1000) / 1000.0 * length, true)


## The rig's AnimationPlayer, or null (a proxy or the placeholder).
func animation_player() -> AnimationPlayer:
	return _anim


## True when the model is a rig with clip `clip_name` (idle: NpcPresenter's bob then does not run).
func has_clip(clip_name: String) -> bool:
	return _anim != null and _anim.has_animation(clip_name)


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


## True when `body` is within talk range: the TalkArea overlaps it, or else (an off-layer body, a frame before the
## physics server has reported the overlap) its origin lies within `radius` of the NPC's feet. `radius` defaults
## (NAN) to this NPC's own zone, talk_radius_m, so the fallback reaches as far as the sphere: 2.4 m for the
## across_counter shopkeepers, not the global npc.interaction_radius_m.
func in_range(body: Node3D, radius: float = NAN) -> bool:
	if not interaction_enabled or body == null:
		return false
	if body is CollisionObject3D and talk_area != null and talk_area.overlaps_body(body):
		return true
	var r := talk_radius_m if is_nan(radius) else radius
	return body.global_position.distance_to(global_position) <= r
