class_name MisoMapBanner
extends PanelContainer
## The map name banner shown on arrival (Events.map_entered): the street name in gold above the map name, both from
## the canonical map record (street_name, name). Fades in, holds, fades out.

const FADE_IN_S := 0.35
const HOLD_S := 2.6
const FADE_OUT_S := 0.9

var street_label: Label
var name_label: Label
var _t := -1.0


func _init() -> void:
	theme_type_variation = &"MisoBanner"
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", -2)
	box.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(box)
	street_label = MisoTheme.make_label("", 15, MisoTheme.GOLD, 4, MisoTheme.WEIGHT_BOLD)
	street_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(street_label)
	name_label = MisoTheme.make_label("", 28, MisoTheme.TEXT, 6, MisoTheme.WEIGHT_BLACK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)


## Shows a banner for a canonical map id (street + name). Unknown ids show the id.
func show_map(map_id: String, db: ContentDB) -> void:
	var rec: Dictionary = db.map(map_id) if db != null and db.has("maps", map_id) else {}
	show_text(String(rec.get("street_name", "")), String(rec.get("name", map_id)))


func show_text(street: String, map_name: String) -> void:
	street_label.text = street
	street_label.visible = street != ""
	name_label.text = map_name
	_t = 0.0
	modulate.a = 0.0
	visible = true
	reset_size()
	_recentre()


func is_showing() -> bool:
	return visible and _t >= 0.0


func _process(delta: float) -> void:
	advance(delta)


## Advances the fade timeline (tests call it directly).
func advance(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	if _t < FADE_IN_S:
		modulate.a = _t / FADE_IN_S
	elif _t < FADE_IN_S + HOLD_S:
		modulate.a = 1.0
	elif _t < FADE_IN_S + HOLD_S + FADE_OUT_S:
		modulate.a = 1.0 - (_t - FADE_IN_S - HOLD_S) / FADE_OUT_S
	else:
		_t = -1.0
		visible = false


func _recentre() -> void:
	var parent := get_parent() as Control
	var w := parent.size.x if parent != null and parent.size.x > 0.0 else 1600.0
	var sz := get_combined_minimum_size()
	position = Vector2(roundf((w - sz.x) * 0.5), 64.0)
