class_name MisoMapBanner
extends PanelContainer
## The map name banner, from the canonical map record (street_name, name):
##   - on arrival (Events.map_entered): the street name in gold above the map name. Fades in, holds, fades out.
##   - on a trail (MapSession.trail_changed, MAP_ARCHITECTURE §4.11): the current map's street and name with a third
##     line under the name, "-> <destination map name>". The banner holds for as long as the player is on the trail;
##     leaving it (the trail line cleared) hides the line and lets the banner fade out.
## Centred at the top of its parent (the HUD), and kept centred when the parent resizes: the trail line may hold the
## banner for minutes, and with stretch aspect "expand" a window wider than 16:9 widens the HUD.

const FADE_IN_S := 0.35
const HOLD_S := 2.6
const FADE_OUT_S := 0.9
## The trail line's prefix. ASCII on purpose: Nunito (the MisoTheme font) has no U+2192 arrow.
const TRAIL_PREFIX := "-> "

var street_label: Label
var name_label: Label
var trail_label: Label
## The map at the other end of the trail while the trail line shows; "" otherwise.
var trail_map_id: String = ""
var _t := -1.0
## The parent whose `resized` recentres the banner (kept to disconnect it: NOTIFICATION_UNPARENTED has no parent).
var _watched: Control = null


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
	trail_label = MisoTheme.make_label("", 17, MisoTheme.ACCENT_LIGHT, 4, MisoTheme.WEIGHT_BLACK)
	trail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trail_label.visible = false
	box.add_child(trail_label)


## The canonical display name of a map ("Snail Hunting Ground I"); the id when the map is unknown.
static func map_name(map_id: String, db: ContentDB) -> String:
	return String(_record(map_id, db).get("name", map_id))


## Shows a banner for a canonical map id (street + name). Unknown ids show the id.
func show_map(map_id: String, db: ContentDB) -> void:
	var rec := _record(map_id, db)
	show_text(String(rec.get("street_name", "")), String(rec.get("name", map_id)))


func show_text(street: String, map_name_text: String) -> void:
	street_label.text = street
	street_label.visible = street != ""
	name_label.text = map_name_text
	_t = 0.0
	modulate.a = 0.0
	visible = true
	reset_size()
	_recentre()


## Shows the trail line: `map_id` is the map the trail belongs to (MapSession.current_map), `dest_map_id` the map at
## its other end. The banner shows `map_id`'s street and name with "-> <destination name>" under them and holds while
## the trail lasts. Calling it again for the same destination while it shows changes nothing; "" clears it.
func show_trail(map_id: String, dest_map_id: String, db: ContentDB) -> void:
	if dest_map_id == "":
		clear_trail()
		return
	if dest_map_id == trail_map_id and is_showing():
		return
	trail_map_id = dest_map_id
	var rec := _record(map_id, db)
	var street := String(rec.get("street_name", ""))
	street_label.text = street
	street_label.visible = street != ""
	name_label.text = String(rec.get("name", map_id))
	trail_label.text = TRAIL_PREFIX + map_name(dest_map_id, db)
	trail_label.visible = true
	if not is_showing():
		_t = 0.0
		modulate.a = 0.0
		visible = true
	elif _t > FADE_IN_S + HOLD_S:
		# Fading out (the player stepped off and back on): fade back in from the current opacity.
		_t = modulate.a * FADE_IN_S
	reset_size()
	_recentre()


## Hides the trail line. A banner held for the trail then fades out; an arrival banner still in its hold finishes it.
func clear_trail() -> void:
	if trail_map_id == "":
		return
	trail_map_id = ""
	trail_label.text = ""
	trail_label.visible = false
	reset_size()
	_recentre()


func is_showing() -> bool:
	return visible and _t >= 0.0


## True while the trail line is up.
func is_trail_showing() -> bool:
	return trail_map_id != "" and is_showing()


func _process(delta: float) -> void:
	advance(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED:
		_watch(get_parent() as Control)
	elif what == NOTIFICATION_UNPARENTED:
		_watch(null)


## Follows `parent`'s resized signal (null stops following).
func _watch(parent: Control) -> void:
	if _watched != null and is_instance_valid(_watched) and _watched.resized.is_connected(_on_parent_resized):
		_watched.resized.disconnect(_on_parent_resized)
	_watched = parent
	if parent != null and not parent.resized.is_connected(_on_parent_resized):
		parent.resized.connect(_on_parent_resized)


func _on_parent_resized() -> void:
	if visible:
		_recentre()


## Advances the fade timeline (tests call it directly). While the trail line is up the banner holds at full opacity.
func advance(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	if trail_map_id != "":
		_t = minf(_t, FADE_IN_S + HOLD_S)
	if _t < FADE_IN_S:
		modulate.a = _t / FADE_IN_S
	elif _t <= FADE_IN_S + HOLD_S:
		modulate.a = 1.0
	elif _t < FADE_IN_S + HOLD_S + FADE_OUT_S:
		modulate.a = 1.0 - (_t - FADE_IN_S - HOLD_S) / FADE_OUT_S
	else:
		_t = -1.0
		visible = false


static func _record(map_id: String, db: ContentDB) -> Dictionary:
	return db.map(map_id) if db != null and map_id != "" and db.has("maps", map_id) else {}


func _recentre() -> void:
	var parent := get_parent() as Control
	var w := parent.size.x if parent != null and parent.size.x > 0.0 else 1600.0
	var sz := get_combined_minimum_size()
	position = Vector2(roundf((w - sz.x) * 0.5), 64.0)
