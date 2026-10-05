class_name MisoGauge
extends Control
## A HUD gauge: a rounded MisoTheme bar with a short tag on the left ("HP") and an outlined value text centred on
## top ("50 / 50"). Reusable for HP, MP, EXP, monster or cast bars.
##
##   var hp := MisoGauge.new("HP", MisoTheme.HP)
##   hp.set_values(37, 50)                 # text "37 / 50"
##   exp.set_values(12, 15, "12 / 15  (80.00%)")

var bar: ProgressBar
var tag_label: Label
var value_label: Label
var current: int = 0
var maximum: int = 0


func _init(tag: String = "", fill: Color = MisoTheme.EXP, height: float = 20.0) -> void:
	custom_minimum_size = Vector2(120, height)
	mouse_filter = MOUSE_FILTER_IGNORE
	bar = ProgressBar.new()
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	MisoTheme.style_gauge(bar, fill)
	add_child(bar)
	tag_label = MisoTheme.make_label(tag, 12, MisoTheme.GOLD, 4, MisoTheme.WEIGHT_BLACK)
	tag_label.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	tag_label.offset_left = 7
	tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(tag_label)
	value_label = MisoTheme.make_label("", 13, MisoTheme.TEXT, 4, MisoTheme.WEIGHT_BLACK)
	value_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(value_label)


## Sets the fill (current / maximum, clamped) and the text ("current / maximum" unless `text` is given).
func set_values(p_current: int, p_maximum: int, text: String = "") -> void:
	current = p_current
	maximum = p_maximum
	bar.max_value = float(maxi(1, p_maximum))
	bar.value = clampf(float(p_current), 0.0, bar.max_value) if p_maximum > 0 else 0.0
	value_label.text = text if text != "" else "%s / %s" % [MisoTheme.thousands(p_current), MisoTheme.thousands(p_maximum)]


## The fill ratio in [0, 1].
func ratio() -> float:
	return 0.0 if maximum <= 0 else clampf(float(current) / float(maximum), 0.0, 1.0)
