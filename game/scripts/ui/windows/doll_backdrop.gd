class_name MisoDollBackdrop
extends Control
## The equipment window's paper-doll area: a faint procedural figure behind the slot grid (head under the hat slot,
## body under top / bottom, feet under the shoes), so the slots read as "worn here". Slots are absolute-positioned
## children; this node only draws the backdrop.

const FIGURE := Color(0.62, 0.74, 0.92, 0.16)
## Must match MisoEquipmentWindow.PITCH (the slot grid pitch).
const PITCH := 52.0


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	var cx := 2.5 * PITCH
	# Head behind the hat slot, neck, torso behind top, hips/legs behind bottom, feet behind shoes.
	draw_circle(Vector2(cx, 0.5 * PITCH), PITCH * 0.62, FIGURE)
	var torso := PackedVector2Array([
		Vector2(cx - PITCH * 1.05, 1.15 * PITCH), Vector2(cx + PITCH * 1.05, 1.15 * PITCH),
		Vector2(cx + PITCH * 0.75, 2.2 * PITCH), Vector2(cx + PITCH * 0.62, 3.95 * PITCH),
		Vector2(cx - PITCH * 0.62, 3.95 * PITCH), Vector2(cx - PITCH * 0.75, 2.2 * PITCH),
	])
	draw_colored_polygon(torso, FIGURE)
	# Arms reaching toward the glove and weapon slots.
	draw_line(Vector2(cx - PITCH * 0.95, 1.3 * PITCH), Vector2(1.5 * PITCH, 2.5 * PITCH), FIGURE, PITCH * 0.32)
	draw_line(Vector2(cx + PITCH * 0.95, 1.3 * PITCH), Vector2(3.5 * PITCH, 2.5 * PITCH), FIGURE, PITCH * 0.32)
