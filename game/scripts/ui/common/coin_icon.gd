class_name MisoCoinIcon
extends Control
## A small procedurally drawn gold coin, shown next to meso amounts (HUD, inventory, shop).


func _init(side: float = 18.0) -> void:
	custom_minimum_size = Vector2(side, side)
	mouse_filter = MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - 1.0
	var c := size * 0.5
	draw_circle(c, r, Color(0.78, 0.50, 0.08))
	draw_circle(c + Vector2(-0.6, -0.6), r * 0.82, MisoTheme.GOLD)
	draw_arc(c, r * 0.55, 0.0, TAU, 20, Color(0.80, 0.55, 0.10), 1.4, true)
	draw_circle(c + Vector2(-r * 0.35, -r * 0.38), r * 0.18, Color(1, 1, 1, 0.8))
	draw_arc(c, r, 0.0, TAU, 24, Color(0.35, 0.20, 0.02, 0.9), 1.2, true)
