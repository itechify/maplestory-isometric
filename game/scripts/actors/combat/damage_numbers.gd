class_name DamageNumbers
extends Node3D
## MapleStory-style floating combat numbers (scenes/fx/damage_numbers.tscn). Presentation only.
##
## Each number is a billboarded Label3D drawn over everything (no depth test), with a thick dark outline, sized in
## screen pixels from the gameplay camera's orthographic size so it reads the same on every map (12-19.5 m views).
## It pops in, rises and fades. Several hits on the same target within STACK_WINDOW_S stack upward instead of
## overlapping. Styles:
##   dealt   big orange-yellow digits (damage the player deals)
##   crit    larger pink-red digits over a starburst (a critical hit)
##   taken   violet digits (damage the player takes)
##   miss    "MISS" in pale blue (an attack that missed, either way)
##   guard   "GUARD" in pale gold (a touch the player blocked)
##
##   fx.dealt(monster.head_position(), 23, false, monster)
##   fx.taken(player.global_position + Vector3.UP * 1.8, 4, player)
##   fx.miss(pos, monster)

const STYLE_DEALT := &"dealt"
const STYLE_CRIT := &"crit"
const STYLE_TAKEN := &"taken"
const STYLE_MISS := &"miss"
const STYLE_GUARD := &"guard"

## Presentation constants (not gameplay values): on-screen glyph height in px at 900 px viewport height, colours,
## outline, motion. The pixel heights scale with the viewport so the numbers keep their proportion of the screen.
const STYLES := {
	STYLE_DEALT: {"px": 56.0, "fill": Color(1.0, 0.74, 0.16), "outline": Color(0.33, 0.12, 0.0), "outline_px": 22},
	STYLE_CRIT: {"px": 70.0, "fill": Color(1.0, 0.33, 0.47), "outline": Color(0.28, 0.0, 0.12), "outline_px": 24},
	STYLE_TAKEN: {"px": 50.0, "fill": Color(0.78, 0.44, 1.0), "outline": Color(0.17, 0.0, 0.28), "outline_px": 20},
	STYLE_MISS: {"px": 40.0, "fill": Color(0.74, 0.92, 1.0), "outline": Color(0.05, 0.13, 0.3), "outline_px": 18},
	STYLE_GUARD: {"px": 40.0, "fill": Color(1.0, 0.93, 0.62), "outline": Color(0.27, 0.2, 0.0), "outline_px": 18},
}
const REFERENCE_VIEWPORT_H := 900.0
## Font raster size; the label is scaled to the on-screen size, so this only sets crispness.
const FONT_SIZE := 96
const LIFE_S := 1.05
const POP_S := 0.09
const POP_SCALE := 1.45
const FADE_S := 0.3
## Rise over the life, in on-screen glyph heights.
const RISE_GLYPHS := 1.6
## A number spawned on the same target within this time sits one line above the previous one.
const STACK_WINDOW_S := 0.45
const STACK_LINE := 0.92
const MAX_STACK := 5
## Fallback ortho size (m) when no camera is available (tests, tools).
const FALLBACK_VIEW_M := 15.0

## The camera whose orthographic size sets the scale (null = the viewport's current camera).
var camera: Camera3D = null
var _live: Array[Dictionary] = []
## stack key -> {"t": spawn time, "n": stack depth}
var _stacks: Dictionary = {}
var _clock: float = 0.0


func dealt(world_pos: Vector3, amount: int, critical: bool, key: Variant = null) -> Label3D:
	return popup(world_pos, str(amount), STYLE_CRIT if critical else STYLE_DEALT, key)


func taken(world_pos: Vector3, amount: int, key: Variant = null) -> Label3D:
	return popup(world_pos, str(amount), STYLE_TAKEN, key)


func miss(world_pos: Vector3, key: Variant = null) -> Label3D:
	return popup(world_pos, "MISS", STYLE_MISS, key)


func guard(world_pos: Vector3, key: Variant = null) -> Label3D:
	return popup(world_pos, "GUARD", STYLE_GUARD, key)


## Spawns one number. `key` (any object or id) groups numbers that should stack (the same target).
func popup(world_pos: Vector3, text: String, style: StringName, key: Variant = null) -> Label3D:
	var st: Dictionary = STYLES.get(style, STYLES[STYLE_DEALT])
	var m_per_px := _meters_per_screen_px()
	var glyph_m := float(st.px) * m_per_px
	var depth := 0
	var k: Variant = _key_of(key)
	if k != null:
		var prev: Dictionary = _stacks.get(k, {})
		if not prev.is_empty() and _clock - float(prev.t) <= STACK_WINDOW_S:
			depth = mini(int(prev.n) + 1, MAX_STACK)
		_stacks[k] = {"t": _clock, "n": depth}
	var label := Label3D.new()
	label.text = text
	label.font_size = FONT_SIZE
	label.outline_size = int(st.outline_px)
	label.modulate = st.fill
	label.outline_modulate = st.outline
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.double_sided = true
	label.shaded = false
	label.render_priority = 10 + depth
	label.outline_render_priority = 9 + depth
	label.pixel_size = glyph_m / float(FONT_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.name = "Num_%s" % text
	add_child(label)
	var base := _free_spot(world_pos + Vector3.UP * (depth * glyph_m * STACK_LINE), glyph_m)
	label.global_position = base
	var burst: MeshInstance3D = null
	if style == STYLE_CRIT:
		burst = AttackFx.make_burst(glyph_m * 1.5, Color(1.0, 0.82, 0.25, 1.0), 12, true, false)
		add_child(burst)
		burst.global_position = base + Vector3.UP * glyph_m * 0.5
	_live.append({"label": label, "burst": burst, "t": 0.0, "base": base, "rise": glyph_m * RISE_GLYPHS,
		"style": style})
	_animate(_live[_live.size() - 1], 0.0)
	return label


## Number of numbers on screen.
func live_count() -> int:
	return _live.size()


## Texts currently shown (tests and the sandbox report).
func live_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for e in _live:
		out.append((e.label as Label3D).text)
	return out


func _process(delta: float) -> void:
	advance(delta)


## Advances every number by `delta` seconds (called by _process; tests call it directly).
func advance(delta: float) -> void:
	_clock += delta
	var keep: Array[Dictionary] = []
	for e in _live:
		e.t = float(e.t) + delta
		if float(e.t) >= LIFE_S:
			(e.label as Node).queue_free()
			if e.burst != null:
				(e.burst as Node).queue_free()
			continue
		_animate(e, float(e.t))
		keep.append(e)
	_live = keep


func _animate(e: Dictionary, t: float) -> void:
	var label: Label3D = e.label
	var k := clampf(t / LIFE_S, 0.0, 1.0)
	var rise := float(e.rise) * (1.0 - pow(1.0 - k, 3.0))
	label.global_position = (e.base as Vector3) + Vector3.UP * rise
	var pop := lerpf(POP_SCALE, 1.0, clampf(t / POP_S, 0.0, 1.0))
	label.scale = Vector3.ONE * pop
	var alpha := clampf((LIFE_S - t) / FADE_S, 0.0, 1.0)
	label.modulate.a = alpha
	label.outline_modulate.a = alpha
	var burst: MeshInstance3D = e.burst
	if burst != null:
		var bk := clampf(t / 0.3, 0.0, 1.0)
		burst.scale = Vector3.ONE * lerpf(0.45, 1.2, sqrt(bk))
		burst.transparency = clampf((t - 0.3) / 0.3, 0.0, 1.0)
		burst.global_position = label.global_position + Vector3.UP * (label.pixel_size * FONT_SIZE * 0.5)


## Moves a new number up, a line at a time, until it does not cover a number still on screen (the same target
## stacks through its key; this also separates numbers of different targets standing close, e.g. a monster
## overlapping the player). Compared in the camera's screen axes when there is a camera.
func _free_spot(base: Vector3, glyph_m: float) -> Vector3:
	var cam := camera
	if cam == null and is_inside_tree():
		cam = get_viewport().get_camera_3d()
	var right := cam.global_basis.x if cam != null else Vector3.RIGHT
	var up := cam.global_basis.y if cam != null else Vector3.UP
	var lift := glyph_m * STACK_LINE / maxf(Vector3.UP.dot(up), 0.3)
	var p := base
	for i in MAX_STACK:
		var clear := true
		for e in _live:
			var other: Vector3 = (e.label as Label3D).global_position
			var d := p - other
			if absf(d.dot(right)) < glyph_m * 1.4 and absf(d.dot(up)) < glyph_m * 0.85:
				clear = false
				break
		if clear:
			break
		p += Vector3.UP * lift
	return p


func _meters_per_screen_px() -> float:
	var cam := camera
	if cam == null and is_inside_tree():
		cam = get_viewport().get_camera_3d()
	var view_m := FALLBACK_VIEW_M
	if cam != null and cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		view_m = cam.size
		if cam.keep_aspect == Camera3D.KEEP_WIDTH and is_inside_tree():
			var vs := get_viewport().get_visible_rect().size
			if vs.x > 0.0:
				view_m = cam.size * vs.y / vs.x
	var vh := REFERENCE_VIEWPORT_H
	# Glyph heights are authored for a 900 px tall view; px per meter follows the view height in meters.
	return view_m / vh


func _key_of(key: Variant) -> Variant:
	if key == null:
		return null
	if key is Object:
		return (key as Object).get_instance_id() if is_instance_valid(key) else null
	return key
