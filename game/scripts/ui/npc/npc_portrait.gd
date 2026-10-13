class_name NpcPortrait
extends PanelContainer
## The speaker's portrait in the dialogue and shop windows, made in code (MeowDB's NPC art is Nexon's): the world NPC's
## own model rendered live into a small SubViewport (three-quarter view, own lights), or, when no model is available
## (standalone UI, an NPC without a model), a coloured badge with the NPC's initial. System lines get a neutral "i"
## badge.
##
## The model is a copy of the world NPC's "Visual": with the art pack its rigged model (#66), playing its idle clip and
## framed head and shoulders (from just below the shoulder bones to the top of the head, a hat included); otherwise
## Iteration One's proxy, framed on its upper ~70%. The copy is kept while the same speaker talks on (a new line does
## not rebuild it).

const PORTRAIT_SIZE := Vector2(132, 150)
## Head-and-shoulders framing of a rig: the frame's bottom sits this share of the model's height below the shoulder
## bones, and its top this share above the model's top.
const SHOULDER_MARGIN := 0.07
const HEAD_MARGIN := 0.04
## The rig bone whose rest height is the shoulders (the art pack's 17-bone character rig).
const SHOULDER_BONE := "upper_arm.L"
## The eye's rise above the frame's centre, as a share of the frame's height (6 m away: a slight look down).
const EYE_RISE := 0.02 / 0.78

var npc_id: String = ""
var npc_name: String = ""
## "model" or "badge".
var mode: String = "badge"

var _container: SubViewportContainer = null
var _viewport: SubViewport = null
var _pivot: Node3D = null
var _camera: Camera3D = null
var _badge: Control = null
var _badge_text: String = "?"
var _badge_color: Color = Color.GRAY
## The copy shown in model mode, the instance id of the source it was made from, and the frame's bottom and top
## (model-space y).
var _shown: Node3D = null
var _shown_source: int = 0
var _span: Vector2 = Vector2.ZERO


func _init() -> void:
	custom_minimum_size = PORTRAIT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := NpcUiStyle.box(Color("#dfe7f2"), Color("#7f95b5"), 2, 8, 0, 0)
	bg.bg_color = Color("#cfdcec")
	add_theme_stylebox_override("panel", bg)
	_badge = Control.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.draw.connect(_draw_badge)
	add_child(_badge)


## Shows an NPC. `model_source` (e.g. the world NPC's "Visual" node) is duplicated into the portrait viewport; null
## shows the initial badge. kind: "npc", "journal" (a quest card, still the NPC's face) or "system".
func show_speaker(p_npc_id: String, p_name: String, model_source: Node3D = null, kind: String = "npc") -> void:
	npc_id = p_npc_id
	npc_name = p_name
	if kind == "system":
		_show_badge("i", Color("#7f95b5"))
		return
	if model_source != null and is_instance_valid(model_source) and _show_model(model_source):
		return
	var initial := p_name.strip_edges().substr(0, 1).to_upper() if not p_name.strip_edges().is_empty() else "?"
	_show_badge(initial, NpcUiStyle.id_color(p_npc_id))


func _show_badge(text: String, color: Color) -> void:
	mode = "badge"
	_badge_text = text
	_badge_color = color
	if _container != null:
		_container.visible = false
	_badge.visible = true
	_badge.queue_redraw()


func _draw_badge() -> void:
	var sz := _badge.size
	var c := sz * 0.5
	var r := minf(sz.x, sz.y) * 0.36
	_badge.draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.18))
	_badge.draw_circle(c, r, _badge_color.darkened(0.35))
	_badge.draw_circle(c, r - 4.0, _badge_color)
	var font := NpcUiStyle.bold_font()
	var fs := int(r * 1.1)
	var w := font.get_string_size(_badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(c.x - w * 0.5, c.y + font.get_ascent(fs) * 0.36)
	_badge.draw_string_outline(font, base, _badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.3))
	_badge.draw_string(font, base, _badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## The model copy shown in model mode (null before the first one or after a failed one).
func shown_model() -> Node3D:
	return _shown if _shown != null and is_instance_valid(_shown) else null


## The frame's bottom (x) and top (y) heights in the model's space, as last shown.
func framed_span() -> Vector2:
	return _span


func _show_model(source: Node3D) -> bool:
	_ensure_viewport()
	if source.get_instance_id() == _shown_source and shown_model() != null:
		_set_model_mode()
		return true
	for c in _pivot.get_children():
		_pivot.remove_child(c)
		c.queue_free()
	_shown = null
	_shown_source = 0
	var copy := source.duplicate() as Node3D
	if copy == null:
		return false
	copy.transform = Transform3D.IDENTITY
	for l in copy.find_children("*", "Label3D", true, false):
		(l as Node3D).visible = false
	_pivot.add_child(copy)
	var box := _model_aabb(copy)
	if box.size.y < 0.05:
		copy.queue_free()
		return false
	# A rig shows its idle clip (a duplicated AnimationPlayer does not play by itself; the rest pose is a T).
	var ap := copy.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null and ap.has_animation(WorldNpc.CLIP_IDLE):
		ap.play(WorldNpc.CLIP_IDLE)
	_span = frame_span(box, _shoulder_height(copy))
	var h := _span.y - _span.x
	var cy := (_span.x + _span.y) * 0.5
	_pivot.rotation_degrees = Vector3(0, -22, 0)
	_camera.size = h
	# The eye a little above the frame's centre: the slight downward look of a three-quarter portrait.
	var eye := Vector3(box.get_center().x, cy + h * EYE_RISE, 6.0)
	var target := Vector3(box.get_center().x, cy, 0.0)
	_camera.transform = Transform3D(Basis.looking_at(target - eye), eye)
	_shown = copy
	_shown_source = source.get_instance_id()
	_set_model_mode()
	return true


func _set_model_mode() -> void:
	mode = "model"
	_container.visible = true
	_badge.visible = false


## The frame's bottom (x) and top (y) heights for a model with bounds `box`: with a rig's `shoulder_y` (NAN when
## none), head and shoulders, from just below the shoulders to just above the top; without one, Iteration One's
## framing of the proxies, their upper ~70% (head and shoulders to mid-body).
static func frame_span(box: AABB, shoulder_y: float) -> Vector2:
	var h := box.size.y
	if is_nan(shoulder_y) or shoulder_y <= box.position.y or shoulder_y >= box.end.y:
		var c := box.position.y + h * 0.6
		return Vector2(c - h * 0.39, c + h * 0.39)
	return Vector2(shoulder_y - h * SHOULDER_MARGIN, box.end.y + h * HEAD_MARGIN)


## The rest height of the rig's shoulders in `root`'s space, or NAN without a rig.
static func _shoulder_height(root: Node3D) -> float:
	var sk := root.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null:
		return NAN
	var b := sk.find_bone(SHOULDER_BONE)
	if b < 0:
		return NAN
	var xf := Transform3D.IDENTITY
	var cur: Node = sk
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return (xf * sk.get_bone_global_rest(b).origin).y


func _ensure_viewport() -> void:
	if _container != null:
		return
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.size = Vector2i(PORTRAIT_SIZE)
	_container.add_child(_viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#dfe6f0")
	e.ambient_light_energy = 0.65
	env.environment = e
	_viewport.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.1
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -140, 0)
	fill.light_energy = 0.35
	_viewport.add_child(fill)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.current = true
	_viewport.add_child(_camera)


static func _model_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != root:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var b := xf * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
