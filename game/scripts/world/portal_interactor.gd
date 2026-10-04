class_name PortalInteractor
extends Node
## Reads the portal keys and asks MapSession to travel (MAP_ARCHITECTURE.md section 4.4 "Interaction").
##
##   portal_enter (Up arrow): a fresh press while the player is inside an armed portal trigger of the current map.
##   interact (F): the same, but only when that portal is the nearest interactable (IslandWorld.nearest_interactable),
##                 so talking to an NPC standing next to a portal still talks (portal_adaptations.json interaction).
## Presses are read from the player's InputSource (`player.input_source`, so the traversal bot can press them) and
## fall back to the Input singleton. It runs after the player in the physics frame (process_physics_priority), so
## it sees the same presses the controller saw. "Fresh" means just_pressed: holding Up through an arrival never
## re-triggers, and the arrival portal is disarmed until the player leaves it anyway.
##
## Presses are ignored unless MapSession is IDLE and the player may act: not dead, input enabled
## (player.is_input_enabled(), else its input_enabled property) and no modal open (IslandWorld.is_modal_active(),
## the GameContext's modal stack). A dialogue's arrow keys, a console's history keys and a death notice never warp.

var world: Node = null
## Physics priority after the player controller (default 0) so input_source state is current.
const PHYSICS_PRIORITY := 100
## Why the last press was ignored ("" when none was): "dead", "input off", "modal". For tests and debugging.
var last_block: String = ""


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY


func _physics_process(_delta: float) -> void:
	if world == null:
		return
	var session: Node = world.call("session_node")
	var p: Node3D = world.get("player")
	if session == null or p == null or not bool(session.call("is_idle")):
		return
	var up := _pressed(p, &"portal_enter")
	var interact := not up and _pressed(p, &"interact")
	if not up and not interact:
		return
	var block := blocked(world, p)
	if block != "":
		last_block = block
		return
	last_block = ""
	if up:
		var portal: WorldPortal = world.call("portal_under_player")
		if portal != null:
			session.call("request_portal", portal.def)
		return
	if _interact_enters():
		var near: Dictionary = world.call("nearest_interactable", p.global_position)
		if String(near.get("kind", "")) == "portal":
			session.call("request_portal", (near.node as WorldPortal).def)


## Why the player may not use a portal now ("" when it may): the world's player_input_block() when it has one,
## else the same rules on the duck-typed player (dead, input off) and the world's is_modal_active().
static func blocked(w: Node, p: Node) -> String:
	if w != null and w.has_method("player_input_block"):
		return String(w.call("player_input_block"))
	if p == null:
		return "no player"
	if p.has_method("is_dead") and bool(p.call("is_dead")):
		return "dead"
	if p.has_method("is_input_enabled"):
		if not bool(p.call("is_input_enabled")):
			return "input off"
	elif "input_enabled" in p and not bool(p.get("input_enabled")):
		return "input off"
	if w != null and w.has_method("is_modal_active") and bool(w.call("is_modal_active")):
		return "modal"
	return ""


func _interact_enters() -> bool:
	var tuning: WorldTuning = world.get("tuning")
	return tuning != null and bool(tuning.portal_section("interaction").get("interact_also_enters", false))


static func _pressed(p: Node, action: StringName) -> bool:
	if "input_source" in p:
		var src: Variant = p.get("input_source")
		if src is Object and (src as Object).has_method("just_pressed"):
			return bool((src as Object).call("just_pressed", action))
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)
