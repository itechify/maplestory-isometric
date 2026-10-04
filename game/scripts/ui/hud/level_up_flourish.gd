class_name MisoLevelUpFlourish
extends Control
## The level-up flourish (Events.leveled_up): a gold "LEVEL UP!" that pops in over the player with a burst of
## procedural stars, holds, then floats up and fades. Purely visual; it never blocks input.

const DURATION_S := 2.6
const POP_S := 0.3
const FADE_S := 0.7
const STARS := 14

var title: Label
var sub: Label
var _t := -1.0


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	title = MisoTheme.make_label("LEVEL UP!", 54, MisoTheme.GOLD, 10, MisoTheme.WEIGHT_BLACK)
	title.add_theme_color_override("font_outline_color", Color(0.45, 0.18, 0.0, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(title)
	sub = MisoTheme.make_label("", 22, Color.WHITE, 6, MisoTheme.WEIGHT_BLACK)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(sub)


## Starts the flourish for a new level.
func play(new_level: int) -> void:
	sub.text = "Level %d" % new_level
	_t = 0.0
	visible = true
	_layout(0.0)
	queue_redraw()


func is_playing() -> bool:
	return _t >= 0.0


func _process(delta: float) -> void:
	advance(delta)


## Advances the animation (tests call it directly).
func advance(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	if _t >= DURATION_S:
		_t = -1.0
		visible = false
		return
	_layout(_t)
	queue_redraw()


func _layout(t: float) -> void:
	var w := size.x if size.x > 0.0 else 1600.0
	var h := size.y if size.y > 0.0 else 900.0
	var pop := clampf(t / POP_S, 0.0, 1.0)
	var scale_v := lerpf(0.4, 1.0, pop) + 0.15 * sin(pop * PI)
	var rise := 0.0
	var alpha := 1.0
	if t > DURATION_S - FADE_S:
		var f := (t - (DURATION_S - FADE_S)) / FADE_S
		alpha = 1.0 - f
		rise = 40.0 * f
	var cy := h * 0.34 - rise
	title.reset_size()
	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(scale_v, scale_v)
	title.position = Vector2(roundf((w - title.size.x) * 0.5), cy - title.size.y * 0.5)
	sub.reset_size()
	sub.position = Vector2(roundf((w - sub.size.x) * 0.5), cy + title.size.y * 0.42)
	modulate.a = alpha


func _draw() -> void:
	if _t < 0.0:
		return
	var w := size.x if size.x > 0.0 else 1600.0
	var h := size.y if size.y > 0.0 else 900.0
	var center := Vector2(w * 0.5, h * 0.34)
	var spread := clampf(_t / 0.9, 0.0, 1.0)
	for i in STARS:
		var ang := TAU * float(i) / float(STARS) + _t * 0.6
		var dist := lerpf(40.0, 250.0, spread) * (0.75 + 0.25 * float(i % 3))
		var p := center + Vector2(cos(ang) * dist, sin(ang) * dist * 0.45)
		var r := lerpf(9.0, 4.0, spread)
		var col := MisoTheme.GOLD if i % 2 == 0 else MisoTheme.ACCENT_LIGHT
		col.a = 1.0 - spread * 0.6
		draw_colored_polygon(_star(p, r, r * 0.42, ang), col)


static func _star(c: Vector2, outer: float, inner: float, rot: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 10:
		var rr := outer if i % 2 == 0 else inner
		var a := rot - PI / 2.0 + PI * float(i) / 5.0
		out.append(c + Vector2(cos(a), sin(a)) * rr)
	return out
