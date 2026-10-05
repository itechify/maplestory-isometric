class_name ScreenFader
extends CanvasLayer
## Full-screen black fade used by warps (MAP_ARCHITECTURE.md section 4.5: 0.2 s out, swap, 0.2 s in; durations from
## presentation.json transition). Awaitable: `await fader.fade_out(0.2)`.

signal faded_out
signal faded_in

var rect: ColorRect = null
var _tween: Tween = null


func _ready() -> void:
	layer = 100
	rect = ColorRect.new()
	rect.name = "Black"
	rect.color = Color(0, 0, 0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rect)


func fade_out(duration: float) -> void:
	await _fade_to(1.0, duration)
	faded_out.emit()


func fade_in(duration: float) -> void:
	await _fade_to(0.0, duration)
	faded_in.emit()


func set_black(on: bool) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if rect != null:
		rect.color.a = 1.0 if on else 0.0


func is_black() -> bool:
	return rect != null and rect.color.a >= 0.999


func _fade_to(alpha: float, duration: float) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if rect == null or duration <= 0.0 or not is_inside_tree():
		if rect != null:
			rect.color.a = alpha
		return
	_tween = create_tween()
	_tween.tween_property(rect, "color:a", alpha, duration)
	await _tween.finished
	_tween = null
