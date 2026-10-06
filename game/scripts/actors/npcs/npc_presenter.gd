class_name NpcPresenter
extends Node3D
## Presentation for one world NPC (a WorldNpc from the world runtime), attached as a child at setup time so
## world_npc.gd stays untouched:
##   - a MapleStory-style name tag under the feet and the quest marker above the head (screen-space Controls in the
##     interaction system's overlay layer; the marker in its MarkerClip, which cuts it at the HUD's status bar), shown
##     only for NPCs of the current map that are on screen;
##   - a subtle idle bob of the NPC's model;
##   - facing the player while the player talks to this NPC, then turning back;
##   - now and then a speech bubble with one of the NPC's canonical idle-chatter lines (NpcSpeechBubble), timed by
##     NpcBubbleSchedule from data/misostory/npcs/_speech_bubbles.json (MeowDB gives the lines, not the timing), only
##     while the NPC is on the current map, on screen, not in a conversation and no modal window is open.
## The marker state comes from NpcInteraction.marker(npc_id), refreshed a few times a second (cheap: only current-map
## NPCs ask). Presentation constants (bob, turn rate, refresh period) are cosmetic and live here.

const NODE_NAME := "Presenter"
const BOB_AMPLITUDE_M := 0.025
const BOB_PERIOD_S := 2.6
const TURN_RATE := 8.0
const MARKER_REFRESH_S := 0.3
const MARKER_GAP_M := 0.25
const DEFAULT_HEIGHT_M := 1.5

var npc: Node3D = null
var npc_id: String = ""
var npc_name: String = ""
var title: String = ""
## The name tag's role icon (MapIcons.npc_role of the canonical record: shop coin, transport boat, or "").
var role: String = ""
var tag: NpcNameTag = null
var marker: QuestMarker = null
var bubble: NpcSpeechBubble = null
## When the next bubble shows and which line (null without content).
var bubbles: NpcBubbleSchedule = null
## The NPC's canonical definition (idle lines for the bubbles); null without content.
var def: NpcDef = null
## () -> NpcInteraction (null allowed: no markers, no facing).
var talk_provider: Callable = Callable()
## () -> Node3D player (null allowed).
var player_provider: Callable = Callable()
## () -> Camera3D (null allowed: no tags).
var camera_provider: Callable = Callable()
## () -> bool: true while a modal is open (a dialogue, a shop, the pause menu, the console). Empty = the
## GameContext of the interaction system (InteractionSystem.GROUP), else never.
var modal_provider: Callable = Callable()
## Height of the model's top above the NPC origin (from its meshes).
var height: float = DEFAULT_HEIGHT_M

var _visual: Node3D = null
var _base_pos: Vector3 = Vector3.ZERO
var _base_yaw: float = 0.0
var _yaw: float = 0.0
var _t: float = 0.0
var _phase: float = 0.0
var _refresh: float = 0.0


## Attaches a presenter to `p_npc` (idempotent: returns the existing one, with fresh tag and marker controls in
## `overlay` if its old ones were freed with an earlier overlay). `overlay` is the Control layer they go into.
static func attach(p_npc: Node3D, overlay: Control, db: ContentDB) -> NpcPresenter:
	var existing := p_npc.get_node_or_null(NODE_NAME)
	if existing is NpcPresenter:
		var p0 := existing as NpcPresenter
		if p0.tag == null or not is_instance_valid(p0.tag) or p0.marker == null or not is_instance_valid(p0.marker) \
				or p0.bubble == null or not is_instance_valid(p0.bubble):
			p0._make_overlay_controls(overlay)
		return p0
	var p := NpcPresenter.new()
	p.name = NODE_NAME
	p_npc.add_child(p)
	p.setup(p_npc, overlay, db)
	return p


func setup(p_npc: Node3D, overlay: Control, db: ContentDB) -> void:
	npc = p_npc
	npc_id = String(npc.get_meta("npc_id", ""))
	npc_name = String(npc.get_meta("npc_name", ""))
	var rec: Dictionary = db.npc(npc_id) if db != null else {}
	if npc_name.is_empty():
		npc_name = String(rec.get("name", npc_id))
	title = String(rec.get("function_title", "")) if rec.get("function_title") is String else ""
	role = MapIcons.npc_role(rec)
	if not rec.is_empty():
		def = NpcDef.from_records(rec, db.miso_entity("npcs", npc_id))
		bubbles = NpcBubbleSchedule.for_npc(npc_id, db)
	_phase = float(absi(hash(npc_id)) % 997) / 997.0 * TAU
	_visual = npc.get_node_or_null("Visual") as Node3D
	if _visual != null:
		_base_pos = _visual.position
		_base_yaw = _visual.rotation.y
		_yaw = _base_yaw
		height = _measure_height(_visual)
		if _visual.has_meta("placeholder"):
			# The world's placeholder carries its own Label3D name; the tag below replaces it.
			for c in _visual.get_children():
				if c is Label3D:
					(c as Label3D).visible = false
	_make_overlay_controls(overlay)


func _make_overlay_controls(overlay: Control) -> void:
	tag = NpcNameTag.new()
	tag.name = "Tag_%s" % npc_id
	tag.set_texts(npc_name, title)
	tag.set_role(role)
	tag.visible = false
	marker = QuestMarker.new()
	marker.name = "Marker_%s" % npc_id
	bubble = NpcSpeechBubble.new()
	bubble.name = "Bubble_%s" % npc_id
	if overlay != null:
		overlay.add_child(tag)
		# The interaction system's overlay clips markers to the screen above the HUD's status bar (MARKER_LAYER).
		var clip := overlay.get_node_or_null(InteractionSystem.MARKER_LAYER)
		(clip if clip is Control else overlay).add_child(marker)
		overlay.add_child(bubble)


func _exit_tree() -> void:
	for c in [tag, marker, bubble]:
		if c != null and is_instance_valid(c):
			c.queue_free()


func _process(delta: float) -> void:
	update(delta)


## One frame of presentation (tests call it directly).
func update(delta: float) -> void:
	_t += delta
	var active := is_active()
	_animate_model(delta, active)
	if tag == null or not is_instance_valid(tag) or marker == null or not is_instance_valid(marker):
		return
	var cam := _camera()
	var on_screen := active and cam != null and not cam.is_position_behind(npc.global_position)
	if on_screen:
		var feet := cam.unproject_position(npc.global_position)
		var head := cam.unproject_position(npc.global_position + Vector3.UP * (height + MARKER_GAP_M))
		var vp := cam.get_viewport().get_visible_rect().size
		on_screen = Rect2(Vector2(-80, -80), vp + Vector2(160, 160)).has_point(feet)
		tag.place_below(feet)
		marker.place_above(head)
	tag.visible = on_screen
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = MARKER_REFRESH_S
		refresh_marker()
	marker.visible = on_screen and marker.state != ""
	marker.advance(delta)
	_update_bubble(delta, on_screen, cam)


## Ticks the bubble schedule; shows a new canonical line when one falls due and keeps the bubble above the head (and
## above the quest marker when it shows). A conversation with this NPC hides it at once, and so does any modal
## window (a shop or another NPC's dialogue, the pause menu): a bubble never peeks over or under an open window.
func _update_bubble(delta: float, on_screen: bool, cam: Camera3D) -> void:
	if bubble == null or not is_instance_valid(bubble) or bubbles == null or def == null:
		return
	var quiet := is_talking() or is_modal_open()
	if quiet:
		bubbles.hide_now()
	var line := bubbles.tick(delta, on_screen and not quiet)
	if line >= 0:
		bubble.set_line(def.idle_line(line), line)
	bubble.visible = on_screen and not quiet and bubbles.is_showing() and bubble.text != ""
	if bubble.visible and cam != null:
		var lift := height + MARKER_GAP_M
		var head := cam.unproject_position(npc.global_position + Vector3.UP * lift)
		if marker.visible:
			head.y -= QuestMarker.SIZE.y + 2.0
		bubble.place_above(head)


## True while the NPC belongs to the current map (WorldNpc.interaction_enabled).
func is_active() -> bool:
	if npc == null or not is_instance_valid(npc):
		return false
	var v: Variant = npc.get("interaction_enabled")
	return bool(v) if v != null else true


## Re-reads the quest marker now (also called on quest events).
func refresh_marker() -> void:
	if marker == null or not is_instance_valid(marker):
		return
	var talk := _talk()
	marker.set_state(talk.marker(npc_id) if talk != null and is_active() else "")


## True while the player is in a conversation with this NPC.
func is_talking() -> bool:
	var talk := _talk()
	return talk != null and talk.is_open() and talk.npc_id == npc_id


## True while a modal window is open (modal_provider, else the interaction system's GameContext).
func is_modal_open() -> bool:
	if modal_provider.is_valid():
		return bool(modal_provider.call())
	if not is_inside_tree():
		return false
	var sys := get_tree().get_first_node_in_group(InteractionSystem.GROUP)
	var c: Variant = sys.get("ctx") if sys != null else null
	return c is GameContext and (c as GameContext).is_modal_active()


func _animate_model(delta: float, active: bool) -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	var bob := sin(_t * TAU / BOB_PERIOD_S + _phase) * BOB_AMPLITUDE_M if active else 0.0
	_visual.position = _base_pos + Vector3(0, bob, 0)
	var target := _base_yaw
	var p := _player()
	if active and p != null and is_talking():
		var local := npc.global_transform.basis.inverse() * (p.global_position - npc.global_position)
		if Vector2(local.x, local.z).length_squared() > 0.0001:
			target = atan2(local.x, local.z)
	_yaw = lerp_angle(_yaw, target, clampf(delta * TURN_RATE, 0.0, 1.0))
	_visual.rotation.y = _yaw


## The yaw the model faces now (radians, in the NPC's frame).
func model_yaw() -> float:
	return _yaw


func _talk() -> NpcInteraction:
	if talk_provider.is_valid():
		var v: Variant = talk_provider.call()
		return v if v is NpcInteraction else null
	return null


func _player() -> Node3D:
	if player_provider.is_valid():
		var v: Variant = player_provider.call()
		return v if v is Node3D and is_instance_valid(v) else null
	return null


func _camera() -> Camera3D:
	if camera_provider.is_valid():
		var v: Variant = camera_provider.call()
		if v is Camera3D and is_instance_valid(v):
			return v
	return get_viewport().get_camera_3d() if is_inside_tree() else null


static func _measure_height(root: Node3D) -> float:
	var top := 0.0
	var found := false
	var inv := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := (inv * mi.global_transform) if root.is_inside_tree() else _relative(root, mi)
		var box := xf * mi.get_aabb()
		top = maxf(top, box.end.y) if found else box.end.y
		found = true
	return top + root.position.y if found and top > 0.2 else DEFAULT_HEIGHT_M


static func _relative(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
