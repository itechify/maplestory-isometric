class_name TitleBackdrop
extends Control
## The title screen's painted background, drawn procedurally (no MapleStory art): a morning sky, drifting clouds, a
## calm sea and a small green island with mushroom-cap houses and round trees, plus falling maple-leaf shapes.
## Presentation only; `animate` false freezes it (screenshots, tests).

const SKY_TOP := Color(0.36, 0.64, 0.95)
const SKY_BOTTOM := Color(0.86, 0.94, 1.0)
const SEA := Color(0.31, 0.62, 0.86)
const SEA_LIGHT := Color(0.55, 0.80, 0.95)
const HILL_BACK := Color(0.42, 0.70, 0.40)
const HILL_FRONT := Color(0.33, 0.62, 0.30)
const HILL_EDGE := Color(0.62, 0.84, 0.46)
const CLIFF := Color(0.55, 0.42, 0.30)
const CAP := Color(0.96, 0.52, 0.18)
const CAP_SPOT := Color(1.0, 0.93, 0.80)
const STEM := Color(0.98, 0.92, 0.78)
const DOOR := Color(0.45, 0.30, 0.20)
const TREE := Color(0.24, 0.52, 0.26)
const TRUNK := Color(0.46, 0.32, 0.20)
const LEAF_COLORS := [Color(0.95, 0.42, 0.15), Color(0.98, 0.62, 0.20), Color(0.86, 0.26, 0.16)]
const CLOUD_COUNT := 7
const LEAF_COUNT := 14

var animate: bool = true
var _t: float = 0.0
var _clouds: Array[Dictionary] = []
var _leaves: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004
	for i in CLOUD_COUNT:
		_clouds.append({"x": rng.randf(), "y": rng.randf_range(0.06, 0.34), "s": rng.randf_range(0.7, 1.4),
			"v": rng.randf_range(0.004, 0.012)})
	for i in LEAF_COUNT:
		_leaves.append({"x": rng.randf(), "y": rng.randf(), "s": rng.randf_range(7.0, 13.0),
			"v": rng.randf_range(0.03, 0.06), "sway": rng.randf_range(0.6, 1.6), "phase": rng.randf() * TAU,
			"c": rng.randi_range(0, LEAF_COLORS.size() - 1)})
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	if not animate or not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	# Sky.
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.62), Vector2(0, h * 0.62)]),
		PackedColorArray([SKY_TOP, SKY_TOP, SKY_BOTTOM, SKY_BOTTOM]))
	# Sun glow.
	var sun := Vector2(w * 0.78, h * 0.16)
	for i in 6:
		draw_circle(sun, h * (0.16 - i * 0.022), Color(1.0, 0.97, 0.82, 0.10 + i * 0.05))
	# Clouds.
	for c in _clouds:
		var cx := fposmod(float(c["x"]) + float(c["v"]) * _t, 1.2) * w - 0.1 * w
		_cloud(Vector2(cx, float(c["y"]) * h), float(c["s"]) * h * 0.05)
	# Sea.
	draw_rect(Rect2(0, h * 0.60, w, h * 0.40), SEA)
	for i in 5:
		var y := h * (0.64 + i * 0.07)
		var off := sin(_t * 0.6 + i) * 20.0
		draw_line(Vector2(w * 0.05 + off, y), Vector2(w * 0.95 + off, y), Color(SEA_LIGHT, 0.35), 2.0)
	# The island: a back hill, a front hill with a cliff face.
	_hill(w * 0.10, w * 0.62, h * 0.60, h * 0.22, HILL_BACK)
	_hill(w * 0.38, w * 0.98, h * 0.62, h * 0.16, HILL_BACK.darkened(0.05))
	var front := _hill(w * 0.02, w * 0.80, h * 0.72, h * 0.20, HILL_FRONT)
	draw_rect(Rect2(w * 0.02, h * 0.72, w * 0.78, h * 0.05), CLIFF)
	draw_polyline(front, HILL_EDGE, 3.0)
	# Trees and mushroom houses along the front hill.
	for p in [[0.12, 0.9], [0.22, 1.1], [0.58, 1.0], [0.70, 0.8]]:
		_tree(Vector2(w * float(p[0]), _hill_y(front, w * float(p[0]))), h * 0.045 * float(p[1]))
	_house(Vector2(w * 0.34, _hill_y(front, w * 0.34)), h * 0.11)
	_house(Vector2(w * 0.47, _hill_y(front, w * 0.47)), h * 0.08)
	# Falling leaves.
	for lf in _leaves:
		var ly := fposmod(float(lf["y"]) + float(lf["v"]) * _t, 1.1) * h - 0.05 * h
		var lx := float(lf["x"]) * w + sin(_t * float(lf["sway"]) + float(lf["phase"])) * 30.0
		_leaf(Vector2(lx, ly), float(lf["s"]), _t * float(lf["sway"]) + float(lf["phase"]), LEAF_COLORS[int(lf["c"])])


func _cloud(at: Vector2, r: float) -> void:
	var col := Color(1, 1, 1, 0.92)
	for o in [Vector2(-1.4, 0.3), Vector2(-0.5, -0.3), Vector2(0.5, -0.45), Vector2(1.4, 0.2), Vector2(0, 0.35)]:
		draw_circle(at + o * r, r * (1.0 if o.y < 0 else 0.85), col)


## Fills a smooth hill from x0 to x1 whose base is at base_y and top `height` above it; returns its top edge.
func _hill(x0: float, x1: float, base_y: float, height: float, color: Color) -> PackedVector2Array:
	var top := PackedVector2Array()
	var steps := 32
	for i in steps + 1:
		var f := float(i) / steps
		var x := lerpf(x0, x1, f)
		var y := base_y - height * sin(f * PI) * (0.85 + 0.15 * sin(f * TAU * 2.0))
		top.append(Vector2(x, y))
	var poly := top.duplicate()
	poly.append(Vector2(x1, base_y))
	poly.append(Vector2(x0, base_y))
	draw_colored_polygon(poly, color)
	return top


static func _hill_y(top: PackedVector2Array, x: float) -> float:
	for i in top.size() - 1:
		if x >= top[i].x and x <= top[i + 1].x:
			return lerpf(top[i].y, top[i + 1].y, (x - top[i].x) / maxf(top[i + 1].x - top[i].x, 0.001))
	return top[top.size() - 1].y if not top.is_empty() else 0.0


func _tree(base: Vector2, r: float) -> void:
	draw_rect(Rect2(base.x - r * 0.15, base.y - r * 1.4, r * 0.3, r * 1.5), TRUNK)
	draw_circle(base + Vector2(0, -r * 1.8), r, TREE)
	draw_circle(base + Vector2(-r * 0.6, -r * 1.4), r * 0.7, TREE.lightened(0.08))
	draw_circle(base + Vector2(r * 0.6, -r * 1.5), r * 0.7, TREE.darkened(0.08))


func _house(base: Vector2, s: float) -> void:
	# Stem with a door, then a mushroom cap with spots.
	draw_rect(Rect2(base.x - s * 0.32, base.y - s * 0.75, s * 0.64, s * 0.78), STEM)
	draw_rect(Rect2(base.x - s * 0.10, base.y - s * 0.38, s * 0.20, s * 0.40), DOOR)
	var cap := PackedVector2Array()
	for i in 25:
		var a := PI + PI * i / 24.0
		cap.append(base + Vector2(cos(a) * s * 0.75, -s * 0.70 + sin(a) * s * 0.62))
	draw_colored_polygon(cap, CAP)
	for o in [Vector2(-0.35, -1.0), Vector2(0.15, -1.15), Vector2(0.45, -0.88)]:
		draw_circle(base + o * s, s * 0.09, CAP_SPOT)


## A five-pointed leaf silhouette (not MapleStory's sprite): a star with a short stem.
func _leaf(at: Vector2, r: float, angle: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := angle + TAU * i / 10.0 - PI / 2.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(at + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, color)
	draw_line(at, at + Vector2(cos(angle + PI / 2.0), sin(angle + PI / 2.0)) * r * 0.9, color.darkened(0.3), 1.5)
