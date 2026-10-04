class_name WorldScale
extends RefCounted
## The only sanctioned MapleStory-px -> meters conversions (data/misostory/world_scale.json).
##
## Canonical MeowDB values stay in px; systems convert at the point of use:
##   WorldScale.h(150.0)    ground distances and speeds (walk speed, monster movement, ranges)
##   WorldScale.v(77.0)     heights (jump apex, knockback rise)
##   WorldScale.actor(37.0) sizes relative to a body (hit boxes, touch zones, pickup box, reach)

const _DEFAULTS := {"horizontal_px_to_m": 0.02, "vertical_px_to_m": 0.0117, "actor_px_to_m": 0.025}
static var _table: Dictionary = {}


static func _factor(key: String) -> float:
	if _table.is_empty():
		var text := FileAccess.get_file_as_string("res://data/misostory/world_scale.json")
		var parsed: Variant = JSON.parse_string(text) if text != "" else null
		_table = parsed if parsed is Dictionary else _DEFAULTS.duplicate()
	return float(_table.get(key, _DEFAULTS[key]))


static func h(px: float) -> float:
	return px * _factor("horizontal_px_to_m")


static func v(px: float) -> float:
	return px * _factor("vertical_px_to_m")


static func actor(px: float) -> float:
	return px * _factor("actor_px_to_m")
