class_name MisoSandboxBackdrop
extends Control
## A procedural stand-in for the game world behind the UI sandbox: a bright sky, layered green hills, a path and a
## few round trees, in Maple Island colours. It exists so HUD and window readability is judged over a busy, bright
## scene rather than a flat colour.


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	# Sky gradient.
	var steps := 24
	for i in steps:
		var t := float(i) / float(steps)
		var c := Color(0.53, 0.80, 0.98).lerp(Color(0.88, 0.95, 1.0), t)
		draw_rect(Rect2(0, h * 0.62 * t, w, h * 0.62 / steps + 1.0), c)
	# Clouds.
	for p: Vector3 in [Vector3(0.15, 0.14, 1.0), Vector3(0.48, 0.09, 0.8), Vector3(0.82, 0.18, 1.2)]:
		var cx := w * p.x
		var cy := h * p.y
		var s := 40.0 * p.z
		for o: Vector3 in [Vector3(-1.1, 0.2, 0.8), Vector3(0, 0, 1.0), Vector3(1.0, 0.25, 0.75), Vector3(0.4, -0.4, 0.7)]:
			draw_circle(Vector2(cx + o.x * s, cy + o.y * s), s * o.z, Color(1, 1, 1, 0.92))
	# Hills.
	_hill(h * 0.50, 0.9, Color(0.47, 0.76, 0.42), 0.0)
	_hill(h * 0.58, 1.3, Color(0.38, 0.69, 0.33), 1.7)
	_hill(h * 0.68, 0.8, Color(0.33, 0.62, 0.28), 3.1)
	draw_rect(Rect2(0, h * 0.74, w, h * 0.26), Color(0.42, 0.70, 0.30))
	# Dirt path.
	var path := PackedVector2Array([Vector2(w * 0.38, h), Vector2(w * 0.50, h * 0.74), Vector2(w * 0.56, h * 0.74),
		Vector2(w * 0.70, h)])
	draw_colored_polygon(path, Color(0.80, 0.66, 0.44))
	# Trees.
	for p: Vector2 in [Vector2(0.08, 0.66), Vector2(0.22, 0.72), Vector2(0.86, 0.64), Vector2(0.93, 0.74),
			Vector2(0.65, 0.60), Vector2(0.30, 0.58)]:
		var base := Vector2(w * p.x, h * p.y)
		draw_rect(Rect2(base.x - 7, base.y - 10, 14, 46), Color(0.50, 0.33, 0.20))
		draw_circle(base + Vector2(0, -30), 42, Color(0.24, 0.55, 0.24))
		draw_circle(base + Vector2(-20, -18), 30, Color(0.28, 0.60, 0.27))
		draw_circle(base + Vector2(16, -44), 26, Color(0.32, 0.66, 0.30))
	# A stand-in player marker in the middle of the screen.
	var me := Vector2(w * 0.5, h * 0.66)
	draw_circle(me + Vector2(0, 6), 18, Color(0, 0, 0, 0.18))
	draw_rect(Rect2(me.x - 12, me.y - 46, 24, 40), Color(0.95, 0.95, 0.92))
	draw_circle(me + Vector2(0, -60), 16, Color(1.0, 0.86, 0.72))


func _hill(base_y: float, freq: float, color: Color, phase: float) -> void:
	var w := size.x
	var pts := PackedVector2Array()
	pts.append(Vector2(0, size.y))
	var n := 48
	for i in n + 1:
		var x := w * float(i) / float(n)
		pts.append(Vector2(x, base_y - 40.0 * sin(x / w * TAU * freq + phase) - 20.0 * sin(x / w * TAU * freq * 2.3)))
	pts.append(Vector2(w, size.y))
	draw_colored_polygon(pts, color)
