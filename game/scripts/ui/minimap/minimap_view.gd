class_name MisoMinimapView
extends Control
## The minimap picture of one MinimapModel, fitted into this control with one uniform scale (MinimapProjection.fit).
## Two layers, so the player moving never re-submits the ground:
##   - ground (redrawn only when the model or the size changes): the projected ground triangles, one mesh per height
##     tier drawn lowest first, each over a darker copy shifted down by one tier's projected height (the terrace's
##     front face, as the gameplay camera sees it); grass tones outdoors, floor tones in interiors; the footprint
##     fallback with the authored routes; climbables; the trail stubs leaving the map (dashed);
##   - markers (redrawn on every update): portal glyphs (swirl for an edge, door for a door) with an outward chevron,
##     a coin when a shopkeeper is behind the door, and the destination name where it fits; NPC dots carrying the
##     quest-marker state (QuestMarker's colours and glyph) and the shop or transport icon; the player arrow, kept on
##     the edge when the player is off the picture, tagged "-> <destination>" while the player walks a trail.
## Hovering a portal or an NPC shows its full description (Control._get_tooltip), so a label that does not fit is
## never lost. Presentation constants (sizes, colours; the refresh rate lives in MisoMinimap) are cosmetic and live
## here.

## Largest size of the picture (px) and the most px per minimap metre (small interiors are not blown up).
const MAX_SIZE := Vector2(330, 215)
const MIN_WIDTH := 230.0
const MAX_PX_PER_M := 9.0
const MARGIN := 10.0
## Ground colours by tier (index = tier - TIER_LOWEST, clamped): low and deep to high and light.
const TIER_LOWEST := -1
const TIER_COLORS := [Color("#3f6b4c"), Color("#4f8a55"), Color("#62a05c"), Color("#77b263"), Color("#8cc06c"),
	Color("#a1cc78"), Color("#b4d686"), Color("#c5df96"), Color("#d3e6a7"), Color("#dfecb8"), Color("#e9f1c9")]
## Interior floors (MinimapModel.interior): wood and stone instead of grass.
const INTERIOR_COLORS := [Color("#6b5640"), Color("#8a6f52"), Color("#a08462"), Color("#b39874"), Color("#c3aa88"),
	Color("#d1ba9a")]
## The darker copy under each tier (multiplied with its colours) and its shift, clamped to these px.
const CLIFF := Color(0.42, 0.40, 0.38, 1.0)
const CLIFF_MIN_PX := 1.5
const CLIFF_MAX_PX := 6.0
const BACKGROUND := Color(0.07, 0.10, 0.15, 0.82)
const OUTLINE := Color(0.85, 0.92, 1.0, 0.35)
const ROUTE := Color(0.95, 0.88, 0.62, 0.55)
const CLIMBABLE := Color("#c99a5b")
const TRAIL := Color(0.98, 0.90, 0.60, 0.85)
const NPC_DOT := Color("#ffd84a")
const PLAYER := Color("#ff8f2b")
const LABEL := Color(0.97, 0.98, 1.0)
const LABEL_SIZE := 11
const PORTAL_R := 5.0
const NPC_R := 3.5
const MARKER_R := 6.0
const ICON_R := 4.5
const PLAYER_R := 6.5
## Prefix of the trail tag: ASCII on purpose (Nunito has no U+2192), like the map banner's trail line.
const TRAIL_PREFIX := "-> "
## Hover text of the quest-marker states.
const MARKER_TEXT := {"available": "Quest available", "in_progress": "Quest in progress",
	"completable": "Quest ready to turn in"}

var model: MinimapModel = null
## Minimap metres -> px.
var xf: Transform2D = Transform2D.IDENTITY
## The player: world position and facing; has_player false hides the arrow.
var has_player: bool = false
var player_world: Vector3 = Vector3.ZERO
var player_facing: Vector3 = Vector3.ZERO
## The canonical name of the map at the other end of the trail the player walks ("" off trails): the arrow's tag.
var trail_dest_name: String = ""
## npc id -> "available" | "in_progress" | "completable" | "".
var marker_states: Dictionary = {}

var ground_layer: Control = null
var marker_layer: Control = null
## One mesh per tier, lowest first.
var _meshes: Array[ArrayMesh] = []
var _font: Font = null


func _init() -> void:
	name = "MinimapView"
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP
	tooltip_text = " "
	ground_layer = _Layer.new(self, &"_draw_ground")
	ground_layer.name = "Ground"
	add_child(ground_layer)
	marker_layer = _Layer.new(self, &"_draw_markers")
	marker_layer.name = "Markers"
	add_child(marker_layer)
	resized.connect(_on_resized)


## Shows `m` (null clears): sizes the control to the map's shape and rebuilds the ground meshes.
func set_model(m: MinimapModel) -> void:
	model = m
	_meshes = build_meshes(m)
	custom_minimum_size = preferred_size(m)
	size = custom_minimum_size
	_refit()


## The size this control wants for `m`: the map's bounds scaled to fit MAX_SIZE (at most MAX_PX_PER_M), never
## narrower than MIN_WIDTH.
static func preferred_size(m: MinimapModel) -> Vector2:
	if m == null or m.bounds.size == Vector2.ZERO:
		return Vector2(MIN_WIDTH, 120.0)
	var avail := MAX_SIZE - Vector2(MARGIN, MARGIN) * 2.0
	var s := minf(minf(avail.x / maxf(m.bounds.size.x, 0.01), avail.y / maxf(m.bounds.size.y, 0.01)), MAX_PX_PER_M)
	var want := (m.bounds.size * s + Vector2(MARGIN, MARGIN) * 2.0).round()
	return Vector2(maxf(want.x, MIN_WIDTH), want.y)


## The dynamic state (MisoMinimap calls it a few times a second); redraws the marker layer only.
func update_dynamic(p_has_player: bool, world_pos: Vector3, facing: Vector3, p_trail_dest_name: String,
		states: Dictionary) -> void:
	has_player = p_has_player
	player_world = world_pos
	player_facing = facing
	trail_dest_name = p_trail_dest_name
	marker_states = states
	marker_layer.queue_redraw()


## A minimap-metre point in this control's px.
func to_px(q: Vector2) -> Vector2:
	return xf * q


## The player's arrow as the next draw places it: {"pos", "clamped", "in_view", "angle"} ({} without a player).
func player_marker() -> Dictionary:
	if model == null or not has_player:
		return {}
	var raw := to_px(model.project(player_world))
	var c := MinimapProjection.clamp_to_rect(raw, _inner_rect())
	c["in_view"] = not bool(c["clamped"])
	return c


## Tooltip under the pointer: the nearest portal or NPC within a few px ("" when none).
func _get_tooltip(at_position: Vector2) -> String:
	return describe_at(at_position)


## The description of the portal or NPC nearest `px` within 9 px: "Portal to <name> (<street>)" plus "Shop: Pan" behind
## a shop door; "<NPC>, <function title or role>" plus its quest state.
func describe_at(px: Vector2) -> String:
	if model == null:
		return ""
	var best := ""
	var best_d := 9.0
	for p: Dictionary in model.portals:
		var d := to_px(p["pos"]).distance_to(px)
		if d < best_d:
			best_d = d
			best = "Portal to %s" % String(p["dest_name"])
			if String(p["dest_street"]) != "":
				best += " (%s)" % String(p["dest_street"])
			if bool(p["dest_shop"]):
				best += "\nShop: %s" % ", ".join(p["dest_shop_npcs"])
	for n: Dictionary in model.npcs:
		var d := to_px(n["pos"]).distance_to(px)
		if d < best_d:
			best_d = d
			best = String(n["name"])
			var what := String(n["function_title"])
			if what == "" and String(n["role"]) == MapIcons.ROLE_TRANSPORT:
				what = MapIcons.TRANSPORT_ROLE
			if what != "":
				best += ", %s" % what
			var st := String(marker_states.get(n["npc_id"], ""))
			if st != "":
				best += "\n%s" % MARKER_TEXT.get(st, st)
	return best


## Where the destination names go: [{id, text, rect}], nearest portal to the player first, each where it fits
## (beside its glyph, outward first, then above, below, right, left) without overlapping an earlier label or leaving
## the picture. A name that fits nowhere is left out: hovering its portal still shows it (describe_at).
func label_layout() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var font := _label_font()
	if model == null or font == null:
		return out
	var order: Array[Dictionary] = []
	for p: Dictionary in model.portals:
		order.append(p)
	if has_player:
		var me := model.project(player_world)
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["pos"] as Vector2).distance_squared_to(me) < (b["pos"] as Vector2).distance_squared_to(me))
	var area := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	for p in order:
		var text := String(p["dest_name"])
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE) + Vector2(4, 0)
		var at := to_px(p["pos"])
		var dir: Vector2 = p["out_dir"]
		var gap := PORTAL_R + 3.0
		var candidates := [at + dir * (gap + sz.x * 0.5 * absf(dir.x) + sz.y * 0.5 * absf(dir.y)) - sz * 0.5,
			at + Vector2(-sz.x * 0.5, -gap - sz.y), at + Vector2(-sz.x * 0.5, gap),
			at + Vector2(gap, -sz.y * 0.5), at + Vector2(-gap - sz.x, -sz.y * 0.5)]
		for corner: Vector2 in candidates:
			var r := Rect2(corner.round(), sz)
			if not area.encloses(r) or out.any(func(o: Dictionary) -> bool: return (o["rect"] as Rect2).intersects(r)):
				continue
			out.append({"id": String(p["id"]), "text": text, "rect": r})
			break
	return out


## The ground colour of a tier (interior floors use their own tones).
static func tier_color(tier: int, interior: bool = false) -> Color:
	var ramp: Array = INTERIOR_COLORS if interior else TIER_COLORS
	return ramp[clampi(tier - TIER_LOWEST, 0, ramp.size() - 1)]


## One mesh per ground tier of `m`, lowest first, its triangles coloured by tier ([] without ground).
static func build_meshes(m: MinimapModel) -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	if m == null or m.ground.size() < 3:
		return out
	var start := 0
	var n := m.ground_tiers.size()
	while start < n:
		var tier := m.ground_tiers[start]
		var end := start
		while end < n and m.ground_tiers[end] == tier:
			end += 1
		var verts := m.ground.slice(start * 3, end * 3)
		var colors := PackedColorArray()
		colors.resize(verts.size())
		colors.fill(tier_color(tier, m.interior))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.append(mesh)
		start = end
	return out


# --- drawing --------------------------------------------------------------------------------------------------

func _on_resized() -> void:
	_refit()


func _refit() -> void:
	xf = MinimapProjection.fit(model.bounds, size, MARGIN, MAX_PX_PER_M) if model != null else Transform2D.IDENTITY
	ground_layer.queue_redraw()
	marker_layer.queue_redraw()


func _inner_rect() -> Rect2:
	return Rect2(Vector2(PLAYER_R, PLAYER_R), size - Vector2(PLAYER_R, PLAYER_R) * 2.0)


## The on-screen height of one tier step (px): what the gameplay camera shows of a terrace's front face.
func _cliff_px() -> float:
	if model == null or model.projection == null:
		return CLIFF_MIN_PX
	var h := MinimapModel.TIER_M * absf(model.projection.up.y) * MinimapProjection.scale_of(xf)
	return clampf(h, CLIFF_MIN_PX, CLIFF_MAX_PX)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)


func _draw_ground(ci: Control) -> void:
	if model == null:
		return
	var shade := xf.translated(Vector2(0.0, _cliff_px()))
	for mesh in _meshes:
		ci.draw_mesh(mesh, null, shade, CLIFF)
		ci.draw_mesh(mesh, null, xf)
	if model.ground_source == MinimapModel.SOURCE_FOOTPRINT:
		for line in model.outline:
			ci.draw_polyline(xf * line, OUTLINE, 1.0, true)
		for line in model.routes:
			ci.draw_polyline(xf * line, ROUTE, 1.5, true)
	for t: Dictionary in model.trails:
		var pts: PackedVector2Array = xf * (t["points"] as PackedVector2Array)
		for i in range(pts.size() - 1):
			ci.draw_dashed_line(pts[i], pts[i + 1], TRAIL, 2.0, 4.0, false)
	for c: Dictionary in model.climbables:
		ci.draw_line(to_px(c["bottom"]), to_px(c["top"]), CLIMBABLE, 2.0, true)


func _draw_markers(ci: Control) -> void:
	if model == null:
		return
	var font := _label_font()
	for p: Dictionary in model.portals:
		var at := to_px(p["pos"])
		var out: Vector2 = p["out_dir"]
		if String(p["kind"]) == PortalDef.TYPE_DOOR:
			MapIcons.draw_door(ci, at, PORTAL_R)
		else:
			MapIcons.draw_swirl(ci, at, PORTAL_R)
		MapIcons.draw_chevron(ci, at + out * (PORTAL_R + 4.0), out, 3.5, MapIcons.PORTAL_CORE)
		if bool(p["dest_shop"]):
			MapIcons.draw_coin(ci, at + Vector2(PORTAL_R + 1.0, -PORTAL_R - 1.0), ICON_R)
	for n: Dictionary in model.npcs:
		var at := to_px(n["pos"])
		var st := String(marker_states.get(n["npc_id"], ""))
		if st != "":
			MapIcons.draw_marker_dot(ci, st, at, MARKER_R, font)
		else:
			ci.draw_circle(at, NPC_R + 1.0, MapIcons.ICON_EDGE)
			ci.draw_circle(at, NPC_R, NPC_DOT)
		MapIcons.draw_role(ci, String(n["role"]), at + Vector2(MARKER_R + 2.0, -MARKER_R), ICON_R)
	if font != null:
		for l: Dictionary in label_layout():
			_text(ci, font, l["rect"].position + Vector2(2.0, font.get_ascent(LABEL_SIZE)), l["text"], LABEL)
	_draw_player(ci, font)


func _draw_player(ci: Control, font: Font) -> void:
	var pm := player_marker()
	if pm.is_empty():
		return
	var pos: Vector2 = pm["pos"]
	var dir := Vector2.from_angle(float(pm["angle"])) if bool(pm["clamped"]) else model.projection.project_dir(player_facing)
	MapIcons.draw_arrow(ci, pos, dir, PLAYER_R, PLAYER)
	if trail_dest_name == "" or font == null:
		return
	# On a trail: "-> <destination>" beside the arrow, on the picture's side of it.
	var text := TRAIL_PREFIX + trail_dest_name
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
	var inward := (size * 0.5 - pos).normalized() if (size * 0.5 - pos).length_squared() > 1.0 else Vector2.UP
	var centre := pos + inward * (PLAYER_R + 4.0 + sz.x * 0.5 * absf(inward.x) + sz.y * 0.5 * absf(inward.y))
	var base := centre + Vector2(-sz.x * 0.5, font.get_ascent(LABEL_SIZE) * 0.5)
	base = base.clamp(Vector2(2, font.get_ascent(LABEL_SIZE) + 2), size - Vector2(sz.x + 2, 2))
	_text(ci, font, base, text, MisoTheme.ACCENT_LIGHT)


func _text(ci: Control, font: Font, base: Vector2, text: String, color: Color) -> void:
	ci.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 3, MisoTheme.OUTLINE)
	ci.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, color)


func _label_font() -> Font:
	if _font == null:
		_font = MisoTheme.font(MisoTheme.WEIGHT_BOLD)
	return _font


## A drawing layer: forwards its _draw to one of the view's methods.
class _Layer extends Control:
	var view: Control = null
	var method: StringName = &""

	func _init(p_view: Control, p_method: StringName) -> void:
		view = p_view
		method = p_method
		mouse_filter = MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		view.call(method, self)
