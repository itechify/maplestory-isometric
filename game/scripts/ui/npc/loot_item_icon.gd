class_name LootItemIcon
extends Control
## A small procedural item icon (no Nexon art): the same shape family and colours as the item's ground drop
## (LootVisuals: chest, bottle, fruit, scroll, arrows, gem, pouch, coins), drawn in code. Used by the shop window.

var style: Dictionary = {}


func _init(p_style: Dictionary = {}, icon_size: float = 32.0) -> void:
	style = p_style
	custom_minimum_size = Vector2(icon_size, icon_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_style(p_style: Dictionary) -> void:
	style = p_style
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var body: Color = style.get("body", Color(0.7, 0.6, 0.45))
	var accent: Color = style.get("accent", body.darkened(0.3))
	var edge := body.darkened(0.45)
	draw_rect(Rect2(o, Vector2(s, s)), Color(1, 1, 1, 0.0))
	match String(style.get("shape", "pouch")):
		"box", "chair_box":
			var r := Rect2(o + Vector2(s * 0.14, s * 0.34), Vector2(s * 0.72, s * 0.5))
			draw_rect(r.grow(1.5), edge)
			draw_rect(r, body)
			draw_rect(Rect2(o + Vector2(s * 0.1, s * 0.24), Vector2(s * 0.8, s * 0.14)).grow(1.0), edge)
			draw_rect(Rect2(o + Vector2(s * 0.1, s * 0.24), Vector2(s * 0.8, s * 0.14)), body.darkened(0.15))
			draw_rect(Rect2(o + Vector2(s * 0.44, s * 0.24), Vector2(s * 0.12, s * 0.6)), accent)
		"potion":
			draw_circle(o + Vector2(s * 0.5, s * 0.62), s * 0.27, edge)
			draw_circle(o + Vector2(s * 0.5, s * 0.62), s * 0.24, body)
			draw_rect(Rect2(o + Vector2(s * 0.4, s * 0.2), Vector2(s * 0.2, s * 0.22)), edge)
			draw_rect(Rect2(o + Vector2(s * 0.43, s * 0.22), Vector2(s * 0.14, s * 0.2)), body.lightened(0.2))
			draw_rect(Rect2(o + Vector2(s * 0.38, s * 0.1), Vector2(s * 0.24, s * 0.12)), accent.darkened(0.3))
			draw_circle(o + Vector2(s * 0.42, s * 0.55), s * 0.06, Color(1, 1, 1, 0.65))
		"food":
			draw_circle(o + Vector2(s * 0.5, s * 0.58), s * 0.3, edge)
			draw_circle(o + Vector2(s * 0.5, s * 0.58), s * 0.27, body)
			draw_line(o + Vector2(s * 0.5, s * 0.32), o + Vector2(s * 0.53, s * 0.14), Color(0.4, 0.26, 0.14), 2.0)
			draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.54, s * 0.2), o + Vector2(s * 0.78, s * 0.12),
				o + Vector2(s * 0.62, s * 0.3)]), accent)
			draw_circle(o + Vector2(s * 0.4, s * 0.48), s * 0.07, Color(1, 1, 1, 0.45))
		"scroll":
			var r2 := Rect2(o + Vector2(s * 0.12, s * 0.36), Vector2(s * 0.76, s * 0.3))
			draw_rect(r2.grow(1.5), edge)
			draw_rect(r2, body)
			draw_rect(Rect2(o + Vector2(s * 0.44, s * 0.34), Vector2(s * 0.12, s * 0.34)), accent)
		"bundle":
			for i in 3:
				var x := s * (0.36 + 0.14 * i)
				draw_line(o + Vector2(x, s * 0.86), o + Vector2(x, s * 0.24), body.darkened(0.2), 3.0)
				draw_colored_polygon(PackedVector2Array([o + Vector2(x - s * 0.07, s * 0.26), o + Vector2(x + s * 0.07, s * 0.26),
					o + Vector2(x, s * 0.1)]), Color(0.62, 0.64, 0.68))
			draw_rect(Rect2(o + Vector2(s * 0.28, s * 0.56), Vector2(s * 0.44, s * 0.08)), accent)
		"gem":
			var pts := PackedVector2Array([o + Vector2(s * 0.5, s * 0.12), o + Vector2(s * 0.82, s * 0.42),
				o + Vector2(s * 0.5, s * 0.88), o + Vector2(s * 0.18, s * 0.42)])
			draw_colored_polygon(pts, body)
			pts.append(pts[0])
			draw_polyline(pts, edge, 1.5)
			draw_line(o + Vector2(s * 0.18, s * 0.42), o + Vector2(s * 0.82, s * 0.42), body.lightened(0.3), 1.0)
		"meso":
			var coins := maxi(1, int(style.get("coins", 1)))
			if bool(style.get("bag", false)):
				draw_circle(o + Vector2(s * 0.5, s * 0.6), s * 0.3, Color(0.4, 0.27, 0.15))
				draw_circle(o + Vector2(s * 0.5, s * 0.6), s * 0.27, Color(0.58, 0.4, 0.23))
				draw_circle(o + Vector2(s * 0.5, s * 0.62), s * 0.11, body)
				draw_rect(Rect2(o + Vector2(s * 0.38, s * 0.2), Vector2(s * 0.24, s * 0.14)), Color(0.5, 0.34, 0.2))
			else:
				for i in coins:
					var cc := o + Vector2(s * (0.5 + (i - (coins - 1) * 0.5) * 0.18), s * (0.56 - i * 0.06))
					draw_circle(cc, s * 0.26, body.darkened(0.35))
					draw_circle(cc, s * 0.22, body)
					draw_circle(cc, s * 0.12, body.lightened(0.25))
		_:
			draw_circle(o + Vector2(s * 0.5, s * 0.6), s * 0.3, edge)
			draw_circle(o + Vector2(s * 0.5, s * 0.6), s * 0.27, body)
			draw_rect(Rect2(o + Vector2(s * 0.38, s * 0.2), Vector2(s * 0.24, s * 0.16)), body.darkened(0.15))
			draw_rect(Rect2(o + Vector2(s * 0.34, s * 0.3), Vector2(s * 0.32, s * 0.06)), accent)
