class_name QuestMarker
extends Control
## The quest indicator above an NPC's head, from NpcInteraction.marker(npc_id) (QuestEngine.npc_marker):
##   "available"    a gold badge with "!" that bounces gently        (a quest can be accepted here)
##   "in_progress"  a grey badge with "..." and no motion             (a quest started here is under way)
##   "completable"  a green badge with "?" and a pulsing ring        (a quest can be turned in here)
## Colour, glyph and motion all differ, so the three states read apart even for colour-blind players. Drawn in code
## (no art), in screen space.

const SIZE := Vector2(40, 40)
const STYLES := {
	"available": {"fill": Color("#f7b733"), "edge": Color("#8a5a0a"), "glyph": "!", "ink": Color("#4a2a02")},
	"in_progress": {"fill": Color("#8e98a8"), "edge": Color("#4a5260"), "glyph": "...", "ink": Color("#ffffff")},
	"completable": {"fill": Color("#43b25a"), "edge": Color("#1d5e2a"), "glyph": "?", "ink": Color("#ffffff")},
}

## "", "available", "in_progress" or "completable".
var state: String = ""
var _t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE
	visible = false


func set_state(s: String) -> void:
	if s == state:
		return
	state = s if STYLES.has(s) else ""
	visible = state != ""
	queue_redraw()


## Advances the animation (called by NpcPresenter).
func advance(delta: float) -> void:
	_t += delta
	if state == "available" or state == "completable":
		queue_redraw()


## Centres the marker above a screen point (the NPC's head).
func place_above(screen_pos: Vector2) -> void:
	position = (screen_pos - Vector2(SIZE.x * 0.5, SIZE.y)).round()


func _draw() -> void:
	if state == "":
		return
	var st: Dictionary = STYLES[state]
	var c := SIZE * 0.5
	if state == "available":
		c.y -= absf(sin(_t * 3.2)) * 5.0
	var r := SIZE.x * 0.42
	if state == "completable":
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		draw_circle(c, r + 3.0 + pulse * 3.0, Color(0.36, 0.9, 0.48, 0.25 + 0.25 * (1.0 - pulse)))
	draw_circle(c + Vector2(0, 2), r, Color(0, 0, 0, 0.3))
	draw_circle(c, r, st["edge"])
	draw_circle(c, r - 2.5, st["fill"])
	draw_circle(c + Vector2(-r * 0.3, -r * 0.35), r * 0.28, Color(1, 1, 1, 0.28))
	var font := NpcUiStyle.bold_font()
	var glyph: String = st["glyph"]
	var fs := 26 if glyph.length() == 1 else 19
	var w := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := font.get_ascent(fs)
	var base := Vector2(c.x - w * 0.5, c.y + asc * 0.36 + (2.0 if glyph.length() > 1 else 0.0))
	draw_string_outline(font, base, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.35))
	draw_string(font, base, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, st["ink"])
