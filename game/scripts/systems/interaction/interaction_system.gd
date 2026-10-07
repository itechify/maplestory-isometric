class_name InteractionSystem
extends Node
## The interaction system (res://scenes/systems/interaction_system.tscn): every frame it finds the one thing the player
## can interact with in the current map and shows a single context prompt for it ("[F] Talk to Roger",
## "[Up] Enter portal", "[Up] Climb", "[Z] Pick up Snail Shell"); the interact key (F) talks to an NPC through
## NpcInteraction.talk(npc_id). It also attaches the NPC presentation (NpcPresenter: name tags, quest markers, idle
## bob, facing the player in dialogue) to the world's NPC nodes.
##
## Who acts on which key (no double handling):
##   interact (F)   the player controller grabs a ladder/rope in reach (it runs first, priority 0); PortalInteractor
##                  (priority 100) enters the portal when world.nearest_interactable() is a portal; this system
##                  (priority 110) talks when the resolver's choice is an NPC, and never while the player is climbing,
##                  a warp runs or a modal is open. InteractionResolver applies the same precedence to the prompt.
##   portal_enter   the controller (ladders) and PortalInteractor (portals); the prompt only names them.
##   pickup (Z)     LootSystem; the prompt asks it which drop the key would take (LootSystem.pickup_target).
## While any modal is open (dialogue, shop, console) nothing here acts and the prompt is empty. The world's
## PortalInteractor applies the same rule itself (PortalInteractor.blocked: input off or a modal open), so Up in a
## dialogue menu moves the highlight and never enters a portal.
##
## setup(ctx) wires it; world, player, loot, talk_provider, session and db are also injectable for tests and
## sandboxes (null = not available).

signal prompt_changed(prompt: Dictionary)
## A conversation was started with interact.
signal talk_started(npc_id: String)

const GROUP := &"interaction_system"
const PHYSICS_PRIORITY := 110
## Screen-space lift of the prompt above an NPC that shows a quest marker (the marker's height plus a gap).
const MARKER_CLEARANCE_PX := 44.0
## Name of the overlay child that holds (and clips) the quest markers; NpcPresenter puts markers there when present.
const MARKER_LAYER := "MarkerClip"

var ctx: GameContext = null
## IslandWorld (duck-typed: nearest_interactable, portal_under_player, npc_nodes, defs).
var world: Node = null
## PlayerController (duck-typed: global_position, input_source, is_climbing, grabbable_climbable, model).
var player: Node3D = null
## LootSystem (duck-typed: pickup_target()); null = found through its group.
var loot: Node = null
## () -> NpcInteraction; empty = WorldUiServices.npc_talk(ctx).
var talk_provider: Callable = Callable()
## MapSession (duck-typed is_idle()); null + use_session = the autoload.
var session: Object = null
var use_session: bool = true
var db: ContentDB = null
## Read the interact key in _physics_process (tests call handle_interact() directly).
var read_input: bool = true

var overlay_layer: CanvasLayer = null
## Screen-space layer for name tags, quest markers and the prompt.
var overlay: Control = null
## The quest markers' parent inside the overlay (MARKER_LAYER): it clips them to the screen above the HUD's status
## bar, so a marker over an NPC low on the screen is cut at the bar's top edge instead of showing through the
## translucent bar (issue #14). Everywhere else a marker draws exactly as before.
var marker_clip: Control = null
var prompt: InteractionPrompt = null
## The resolver result shown now.
var current: Dictionary = {}
## npc_id -> NpcPresenter
var presenters: Dictionary = {}

var _connected_bus: Object = null
var _last_snapshot: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	process_physics_priority = PHYSICS_PRIORITY
	_ensure_overlay()


func _exit_tree() -> void:
	_disconnect_bus()


## GameContext seam: world, player, overlay layer under ctx.ui_root, NPC presenters, quest-marker refresh.
func setup(p_ctx: GameContext) -> void:
	ctx = p_ctx
	if ctx != null:
		if ctx.world != null:
			world = ctx.world
		if ctx.player is Node3D:
			player = ctx.player
	if db == null:
		db = WorldUiServices.content()
	_ensure_overlay()
	attach_presenters()
	_connect_bus(WorldUiServices.events())


# --- presentation ------------------------------------------------------------------------------------------------

func _ensure_overlay() -> void:
	var ui_root: CanvasLayer = ctx.ui_root if ctx != null else null
	if overlay != null:
		# Under the HUD and the windows (ui_root), above the 3D world.
		overlay_layer.layer = ui_root.layer - 1 if ui_root != null else 0
		return
	overlay_layer = CanvasLayer.new()
	overlay_layer.name = "WorldOverlay"
	overlay_layer.layer = ui_root.layer - 1 if ui_root != null else 0
	add_child(overlay_layer)
	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_layer.add_child(overlay)
	NpcUiStyle.apply_base(overlay)
	prompt = InteractionPrompt.new()
	overlay.add_child(prompt)
	marker_clip = Control.new()
	marker_clip.name = MARKER_LAYER
	marker_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker_clip.clip_contents = true
	overlay.add_child(marker_clip)
	update_marker_clip()


## Sizes the markers' clip to the screen above the HUD's status bar (MisoUiEnv.bottom_bar_top over ctx.ui_root's UI
## roots; the whole overlay without a bar). The bar is found by layout every frame, so it follows a resize.
func update_marker_clip() -> void:
	if marker_clip == null:
		return
	var area := overlay.size
	var top := MisoUiEnv.bottom_bar_top(ctx.ui_root if ctx != null else null)
	marker_clip.position = Vector2.ZERO
	marker_clip.size = Vector2(area.x, clampf(top, 0.0, area.y))


## Attaches an NpcPresenter to every NPC node of the world (idempotent).
func attach_presenters() -> void:
	if world == null:
		return
	var nodes: Variant = world.get("npc_nodes")
	if not (nodes is Dictionary):
		return
	for id: Variant in nodes:
		var n: Variant = nodes[id]
		if n is Node3D and is_instance_valid(n):
			attach_presenter(n)


## Attaches (or returns) the presenter of one NPC node.
func attach_presenter(npc: Node3D) -> NpcPresenter:
	_ensure_overlay()
	var p := NpcPresenter.attach(npc, overlay, db)
	p.talk_provider = _talk
	p.player_provider = func() -> Node3D: return player
	p.camera_provider = _camera
	presenters[p.npc_id] = p
	return p


## Re-reads every presenter's quest marker (quest events call this).
func refresh_markers() -> void:
	for id: String in presenters:
		var p: NpcPresenter = presenters[id]
		if is_instance_valid(p):
			p.refresh_marker()


# --- frame ---------------------------------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if read_input and player != null and is_instance_valid(player) and WorldUiServices.pressed(player, &"interact"):
		handle_interact()


func _process(_delta: float) -> void:
	update_marker_clip()
	update_prompt()


## Resolves and shows the prompt for this frame. Returns the resolver result.
func update_prompt() -> Dictionary:
	var snap := snapshot()
	var p := InteractionResolver.resolve(snap)
	if p.get("text", "") != current.get("text", "") or p.get("target_id", "") != current.get("target_id", ""):
		current = p
		prompt_changed.emit(p)
	current = p
	if prompt != null:
		prompt.show_prompt(p)
		if not p.is_empty():
			_place_prompt(p, snap)
	return p


## The interact key was pressed: talks to the NPC when that is what the prompt says the key does. Returns true when a
## conversation started.
func handle_interact() -> bool:
	var snap := snapshot()
	if not InteractionResolver.interact_talks(snap):
		return false
	var npc_id := String(_dict(snap.get("nearest")).get("id", ""))
	return not talk_to(npc_id).is_empty()


## Starts a conversation (Game.npc_talk.talk) and returns its first view ({} when no conversation could start).
func talk_to(npc_id: String) -> Dictionary:
	var t := _talk()
	if t == null or npc_id.is_empty():
		return {}
	var v := t.talk(npc_id)
	if not bool(v.get("open", false)):
		return {}
	talk_started.emit(npc_id)
	if presenters.has(npc_id):
		(presenters[npc_id] as NpcPresenter).refresh_marker()
	return v


## The candidates the resolver chooses from (see InteractionResolver), gathered from the world, player and loot.
func snapshot() -> Dictionary:
	var snap := {}
	if player == null or not is_instance_valid(player):
		snap["blocked"] = true
		_last_snapshot = snap
		return snap
	snap["blocked"] = not WorldUiServices.player_can_act(player, ctx, _session())
	snap["climbing"] = player.has_method("is_climbing") and bool(player.call("is_climbing"))
	if bool(snap["blocked"]) or bool(snap["climbing"]):
		_last_snapshot = snap
		return snap
	var feet := player.global_position
	if player.has_method("grabbable_climbable"):
		var c: Variant = player.call("grabbable_climbable")
		if c is ClimbableDef:
			snap["climbable"] = {"id": (c as ClimbableDef).name, "at_top": _grabs_from_top(c),
				"anchor": feet + Vector3.UP * 1.9}
	if world != null and world.has_method("nearest_interactable"):
		var near: Dictionary = world.call("nearest_interactable", feet)
		if not near.is_empty():
			snap["nearest"] = _describe(near)
	if world != null and world.has_method("portal_under_player"):
		var wp: Variant = world.call("portal_under_player")
		if wp is Node and is_instance_valid(wp):
			snap["portal"] = _describe({"kind": "portal", "node": wp, "id": _portal_key(wp)})
	var l := _loot()
	if l != null and l.has_method("pickup_target"):
		var t: Dictionary = l.call("pickup_target", feet)
		if not t.is_empty():
			snap["drop"] = {"uid": t.get("uid", ""), "label": t.get("label", ""),
				"anchor": (t.get("position", feet) as Vector3) + Vector3.UP * 0.7}
	_last_snapshot = snap
	return snap


# --- collaborators -------------------------------------------------------------------------------------------------

func _describe(near: Dictionary) -> Dictionary:
	var out := {"kind": String(near.get("kind", "")), "id": String(near.get("id", "")),
		"distance": float(near.get("distance", 0.0))}
	var node: Variant = near.get("node")
	if out["kind"] == "npc" and node is Node3D:
		var n := node as Node3D
		out["name"] = String(n.get_meta("npc_name", out["id"]))
		var pres: NpcPresenter = presenters.get(out["id"])
		var h := pres.height if pres != null else NpcPresenter.DEFAULT_HEIGHT_M
		out["anchor"] = n.global_position + Vector3.UP * (h + NpcPresenter.MARKER_GAP_M)
		out["has_marker"] = pres != null and pres.marker != null and pres.marker.state != ""
	elif out["kind"] == "portal" and node is Node:
		var wp := node as Node
		out["shows_prompt"] = bool(wp.call("shows_prompt")) if wp.has_method("shows_prompt") else true
		var pdef: Variant = wp.get("def")
		if pdef is PortalDef and db != null:
			var dest := String(db.map((pdef as PortalDef).destination_map_id).get("name", ""))
			out["name"] = dest
			out["detail"] = dest
		var anchor: Variant = wp.get("prompt_anchor")
		out["anchor"] = (anchor as Node3D).global_position if anchor is Node3D and (anchor as Node3D).is_inside_tree() \
			else (wp as Node3D).global_position if wp is Node3D else Vector3.ZERO
	return out


func _portal_key(wp: Node) -> String:
	var pdef: Variant = wp.get("def")
	return (pdef as PortalDef).key() if pdef is PortalDef else String(wp.name)


## True when grabbable_climbable() came from the top (Down grabs it), false when from the line (Up grabs it).
func _grabs_from_top(c: ClimbableDef) -> bool:
	var exit_below := 0.6
	var m: Variant = player.get("model")
	if m is Object and "climb_exit_below_top" in m:
		exit_below = float(m.get("climb_exit_below_top")) + 0.05
	return player.global_position.y > c.top.y - exit_below


func _place_prompt(p: Dictionary, snap: Dictionary) -> void:
	var cam := _camera()
	if cam == null:
		return
	var anchor: Variant = null
	match String(p.get("kind", "")):
		InteractionResolver.KIND_NPC:
			anchor = _dict(snap.get("nearest")).get("anchor")
		InteractionResolver.KIND_PORTAL:
			anchor = _dict(snap.get("portal")).get("anchor", _dict(snap.get("nearest")).get("anchor"))
		InteractionResolver.KIND_CLIMB:
			anchor = _dict(snap.get("climbable")).get("anchor")
		InteractionResolver.KIND_DROP:
			anchor = _dict(snap.get("drop")).get("anchor")
	if not (anchor is Vector3) or cam.is_position_behind(anchor):
		anchor = player.global_position + Vector3.UP * 1.9
	var sp := cam.unproject_position(anchor)
	if String(p.get("kind", "")) == InteractionResolver.KIND_NPC and bool(_dict(snap.get("nearest")).get("has_marker", false)):
		sp.y -= MARKER_CLEARANCE_PX
	prompt.place_above(sp, cam.get_viewport().get_visible_rect().size)


func _talk() -> NpcInteraction:
	if talk_provider.is_valid():
		var v: Variant = talk_provider.call()
		return v if v is NpcInteraction else null
	return WorldUiServices.npc_talk(ctx)


func _session() -> Object:
	if session != null:
		return session
	return WorldUiServices.session() if use_session else null


func _loot() -> Node:
	if loot != null and is_instance_valid(loot):
		return loot
	if is_inside_tree():
		return get_tree().get_first_node_in_group(LootSystem.GROUP)
	return null


func _camera() -> Camera3D:
	var cam: Variant = ctx.camera if ctx != null else null
	if cam is Object and is_instance_valid(cam):
		var inner: Variant = cam.get("camera")
		if inner is Camera3D:
			return inner
		if cam is Camera3D:
			return cam
	return get_viewport().get_camera_3d() if is_inside_tree() else null


# --- events --------------------------------------------------------------------------------------------------------

func _connect_bus(b: Object) -> void:
	if b == null or b == _connected_bus:
		return
	_disconnect_bus()
	for sig in _marker_signals():
		if b.has_signal(sig):
			var n := _arity(b, sig)
			b.connect(sig, _on_quest_event.unbind(n) if n > 0 else _on_quest_event)
	_connected_bus = b


func _disconnect_bus() -> void:
	if _connected_bus == null or not is_instance_valid(_connected_bus):
		_connected_bus = null
		return
	for sig in _marker_signals():
		if not _connected_bus.has_signal(sig):
			continue
		for c: Dictionary in _connected_bus.get_signal_connection_list(sig):
			var cb: Callable = c["callable"]
			if cb.get_object() == self:
				_connected_bus.disconnect(sig, cb)
	_connected_bus = null


static func _marker_signals() -> PackedStringArray:
	return ["quest_started", "quest_progressed", "quest_completed", "quest_forfeited", "item_gained", "item_lost",
		"leveled_up", "dialogue_closed"]


static func _arity(b: Object, sig: String) -> int:
	for s: Dictionary in b.get_signal_list():
		if String(s["name"]) == sig:
			return (s["args"] as Array).size()
	return 0


func _on_quest_event() -> void:
	refresh_markers()


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}
