class_name MisoSkillIcon
extends Control
## A skill icon: the skill's picture from the first icon pack that has one (MisoIconResolver), else a procedurally
## drawn one on a round badge, the base layer under every pack: three snail shells for Three Snails, a heart with a
## plus for Recovery, a winged boot for Nimble Feet, a star for any other skill. Two states draw the pack's variants:
## `dim` (greyed: not learned, or not enough MP / no shell for a quickslot) draws "iconDisabled", and `hover` (the
## pointer is over the icon in the Skills window or a quickslot) draws "iconMouseOver"; a greyed icon stays greyed
## under the pointer. A state whose variant no pack has draws the plain "icon" instead: greyed by the procedural dim
## while `dim`, unchanged while `hover`. `cooldown` (0..1 of the cooldown left) is drawn over any of them as a dark
## sweep with the seconds left in `cooldown_text`, since the art has no cooldown frames. Presentation only.
##
##   var icon := MisoSkillIcon.new()
##   icon.skill_id = "0001002"
##   icon.dim = true                 # Nimble Feet's iconDisabled, else its icon or badge under the procedural dim
##
## Pack art (32 x 32) fills the cell, drawn at whole multiples with nearest filtering, or with `fill` stretched over
## the whole box (the effects bar); the procedural badge fills the box as before.

## Skill to draw ("" = nothing).
var skill_id: String = "":
	set(v):
		skill_id = v
		art = _resolve(MisoIconResolver.ICON)
		disabled_art = _resolve(MisoIconResolver.ICON_DISABLED)
		hover_art = _resolve(MisoIconResolver.ICON_MOUSE_OVER)
		_redraw()
## Pack art fills the whole box (scaled to its shorter side) instead of whole multiples of the cell: the effects bar.
var fill: bool = false:
	set(v):
		fill = v
		queue_redraw()
## The pack picture drawn instead of the badge (null: no pack has one, so the procedural badge draws).
var art: MisoIconResolver.Art = null
## The pack's pictures of the two states, iconDisabled and iconMouseOver (null: no pack has one, so `art` or the
## badge draws in that state).
var disabled_art: MisoIconResolver.Art = null
var hover_art: MisoIconResolver.Art = null
## Greyed out.
var dim: bool = false:
	set(v):
		dim = v
		_redraw()
## The pointer is over the icon (the Skills window's icon cells and the quickslots set it).
var hover: bool = false:
	set(v):
		hover = v
		_redraw()
## Share of the cooldown still to run (0 = ready, 1 = just cast).
var cooldown: float = 0.0:
	set(v):
		cooldown = clampf(v, 0.0, 1.0)
		queue_redraw()
## Seconds left, drawn over the sweep ("" = none).
var cooldown_text: String = "":
	set(v):
		cooldown_text = v
		queue_redraw()

## Per-skill badge colours (presentation).
const BADGES := {
	"0001000": Color(0.42, 0.62, 0.38),
	"0001001": Color(0.86, 0.36, 0.40),
	"0001002": Color(0.95, 0.72, 0.25),
}
const OUTLINE := Color(0.06, 0.07, 0.10, 0.95)
const SHELLS := [Color(0.80, 0.56, 0.30), Color(0.25, 0.52, 0.95), Color(0.90, 0.20, 0.18)]
## The plain pack art greyed when no pack has the iconDisabled, as the procedural dim greys the badge (darkened by
## 0.5, half opaque).
const DIM_ART := Color(0.5, 0.5, 0.5, 0.5)


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(32, 32)


## The pack picture drawn now (null: the procedural badge): iconDisabled while `dim`, else iconMouseOver while
## `hover`, else the plain icon, which also stands in for a state's missing variant.
func shown_art() -> MisoIconResolver.Art:
	if dim:
		return disabled_art if disabled_art != null else art
	if hover and hover_art != null:
		return hover_art
	return art


## Whether the procedural dim greys the picture: `dim` with no iconDisabled to draw.
func procedural_dim() -> bool:
	return dim and disabled_art == null


## The rect the pack art drawn now covers in this icon's box (Rect2() without art): a whole multiple of the 32 px
## cell, or the box's shorter side with `fill`.
func art_rect() -> Rect2:
	var shown := shown_art()
	return shown.rect_in(size, fill) if shown != null else Rect2()


## The skill's picture of `variant` from the packs (null without a skill, or when no pack has one).
func _resolve(variant: String) -> MisoIconResolver.Art:
	return MisoIconResolver.shared().art(MisoIconResolver.SKILLS, skill_id, variant) if skill_id != "" else null


func _redraw() -> void:
	# Nearest filtering only under pack art, so the cooldown seconds keep today's look on the badge.
	texture_filter = TEXTURE_FILTER_NEAREST if shown_art() != null else TEXTURE_FILTER_PARENT_NODE
	queue_redraw()


func _draw() -> void:
	if skill_id == "":
		return
	var side := minf(size.x, size.y)
	var shown := shown_art()
	if shown != null:
		draw_texture_rect(shown.texture, art_rect(), false, DIM_ART if procedural_dim() else Color.WHITE)
		# The cooldown sweep below covers the art's cell.
		var xf := MisoIconResolver.cell_transform(size, fill)
		draw_set_transform(xf.origin, 0.0, xf.get_scale())
	else:
		var s := side / 32.0
		draw_set_transform(Vector2((size.x - side) * 0.5, (size.y - side) * 0.5), 0.0, Vector2(s, s))
		_draw_badge()
	if cooldown > 0.0:
		var pts := PackedVector2Array([Vector2(16, 16)])
		var steps := 24
		for i in steps + 1:
			var ang := -PI / 2.0 + TAU * cooldown * float(i) / steps
			pts.append(Vector2(16, 16) + Vector2(cos(ang), sin(ang)) * 15.0)
		if pts.size() >= 3:
			draw_colored_polygon(pts, Color(0.02, 0.03, 0.06, 0.62))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if cooldown > 0.0 and cooldown_text != "":
		var font := get_theme_default_font()
		var fs := int(maxf(9.0, side * 0.36))
		var tw := font.get_string_size(cooldown_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := Vector2((size.x - tw) * 0.5, size.y * 0.5 + fs * 0.35)
		draw_string_outline(font, p, cooldown_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, OUTLINE)
		draw_string(font, p, cooldown_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))


## The procedural badge on the 32 x 32 grid.
func _draw_badge() -> void:
	var a := 0.5 if dim else 1.0
	var badge: Color = BADGES.get(skill_id, Color(0.55, 0.60, 0.80))
	if dim:
		badge = badge.darkened(0.5)
	draw_circle(Vector2(16, 16), 15.0, OUTLINE)
	draw_circle(Vector2(16, 16), 13.5, Color(badge, a))
	draw_circle(Vector2(12, 11), 5.0, Color(1, 1, 1, 0.18 * a))
	match skill_id:
		"0001000":
			for i in 3:
				var at: Vector2 = [Vector2(10, 20), Vector2(22, 20), Vector2(16, 10)][i]
				_shell(at, SHELLS[i], a)
		"0001001":
			_heart(Vector2(16, 17), Color(0.98, 0.95, 0.95, a))
			draw_rect(Rect2(14.5, 11.5, 3, 10), Color(0.90, 0.20, 0.25, a))
			draw_rect(Rect2(11, 15, 10, 3), Color(0.90, 0.20, 0.25, a))
		"0001002":
			_boot(Color(0.55, 0.32, 0.18, a), Color(1, 1, 1, a))
		_:
			_star(Vector2(16, 16), Color(1, 1, 1, a))


func _shell(at: Vector2, c: Color, a: float) -> void:
	draw_circle(at, 5.6, OUTLINE)
	draw_circle(at, 4.6, Color(c, a))
	var pts := PackedVector2Array()
	for i in 12:
		var t := float(i) / 11.0
		var ang := t * TAU * 1.2
		pts.append(at + Vector2(cos(ang), sin(ang)) * (0.6 + 3.4 * t))
	draw_polyline(pts, Color(1, 1, 1, 0.75 * a), 1.0)


func _heart(at: Vector2, c: Color) -> void:
	draw_circle(at + Vector2(-4, -3), 5.0, c)
	draw_circle(at + Vector2(4, -3), 5.0, c)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-8.6, -1.2), at + Vector2(8.6, -1.2), at + Vector2(0, 9)]), c)


func _boot(c: Color, wing: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(12, 7), Vector2(18, 7), Vector2(18, 19), Vector2(25, 21),
		Vector2(25, 25), Vector2(11, 25)]), c)
	draw_colored_polygon(PackedVector2Array([Vector2(18, 10), Vector2(26, 6), Vector2(24, 11), Vector2(28, 11),
		Vector2(19, 15)]), wing)
	for y in [13.0, 17.0, 21.0]:
		draw_line(Vector2(4, y), Vector2(9, y), Color(wing, 0.8), 1.5)


func _star(at: Vector2, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var r := 9.0 if i % 2 == 0 else 4.0
		var ang := -PI / 2.0 + TAU * float(i) / 10.0
		pts.append(at + Vector2(cos(ang), sin(ang)) * r)
	draw_colored_polygon(pts, c)
