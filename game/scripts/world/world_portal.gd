class_name WorldPortal
extends Area3D
## The node for any PortalDef (scenes/world/portal.tscn; MAP_ARCHITECTURE.md section 4.4): an Area3D press-Up
## trigger (portal_adaptations.json trigger: 4.5 m wide, 3 m tall, 1.6 m deep, centred on the anchor, depth along
## the anchor normal), the library visual at the anchor (Portal_Swirl / Portal_Door; nothing for hidden type-1
## portals) and a prompt anchor for the interaction prompt. There is no per-map portal script.
##
## State: `interaction_enabled` (only the current map's portals), `armed` (false for the portal the player just
## arrived at, until the player has been outside its trigger: the anti ping-pong rule).

signal player_entered(portal: WorldPortal)
signal player_exited(portal: WorldPortal)

var def: PortalDef = null
var armed: bool = true
var interaction_enabled: bool = false
## The body this portal watches (the world's player); set by IslandWorld.
var watched: Node3D = null
var _inside: bool = false

@onready var trigger: CollisionShape3D = $Trigger
@onready var visual_root: Node3D = $Visual
@onready var prompt_anchor: Marker3D = $PromptAnchor


## Configures the node for `p`. Call after the node is in the tree (its parent at the world origin).
func setup(p: PortalDef, library: ProxyLibrary) -> void:
	def = p
	name = ("Portal_%s_%s" % [p.source_map_id, p.portal_id]).validate_node_name()
	global_transform = p.trigger_transform()
	collision_layer = WorldLayers.INTERACTABLES
	collision_mask = WorldLayers.PLAYER
	monitoring = true
	monitorable = true
	set_meta("portal_key", p.key())
	set_meta("map_id", p.source_map_id)
	add_to_group(&"portals")
	var box := BoxShape3D.new()
	box.size = p.trigger_size
	trigger.shape = box
	prompt_anchor.position = Vector3.UP * (p.trigger_size.y * 0.5)
	for c in visual_root.get_children():
		c.queue_free()
	if p.visual != "" and library != null:
		var v := library.instance(p.visual)
		if v != null:
			visual_root.add_child(v)
			v.global_transform = Transform3D(MapDefinitions.facing_basis(-p.inward), p.anchor_ground)
	visual_root.visible = not p.hidden


## True when the prompt should show: this map's portal, armed, visible, and pressable.
func shows_prompt() -> bool:
	return interaction_enabled and armed and def != null and not def.hidden and def.accepts_press()


## True when `body` is inside the trigger (Area3D overlap, or the feet point inside the box as a fallback for
## bodies that are not on the player layer).
func contains(body: Node3D) -> bool:
	if body == null or def == null:
		return false
	if body is CollisionObject3D and overlaps_body(body):
		return true
	return def.trigger_contains(body.global_position + Vector3.UP * 0.1)


func set_interaction_enabled(on: bool) -> void:
	interaction_enabled = on
	if not on:
		_inside = false


## Disarms until the watched body has left the trigger (anti ping-pong).
func disarm() -> void:
	armed = false


func _physics_process(_delta: float) -> void:
	if not interaction_enabled or watched == null or not is_instance_valid(watched):
		return
	var inside := contains(watched)
	if inside != _inside:
		_inside = inside
		if inside:
			player_entered.emit(self)
		else:
			player_exited.emit(self)
	if not armed and not inside:
		armed = true


func is_player_inside() -> bool:
	return _inside
