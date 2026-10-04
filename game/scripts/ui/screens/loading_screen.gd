class_name LoadingScreen
extends Control
## Shown while a game session starts: the island loads (IslandWorld.load_progress drives the bar), the player and
## the subsystems are put in place, and MapSession places the character. The shell maps the stages onto one bar
## (GameSession.progress).

var bar: ProgressBar = null
var stage_label: Label = null
var title_label: Label = null
var tip_label: Label = null


func _init() -> void:
	name = "LoadingScreen"
	ScreenKit.full_rect(self)
	ScreenKit.apply(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.10, 0.17)
	ScreenKit.full_rect(bg)
	add_child(bg)
	var v := ScreenKit.vbox(14)
	v.custom_minimum_size = Vector2(620, 0)
	title_label = ScreenKit.outlined("Maple Island", 40, Color(1.0, 0.86, 0.40), 8)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title_label)
	bar = ScreenKit.gauge()
	bar.custom_minimum_size = Vector2(620, 20)
	v.add_child(bar)
	stage_label = ScreenKit.label("Loading", 15, ScreenKit.TEXT_DIM, "MisoDim")
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stage_label)
	tip_label = ScreenKit.label(_tip(), 13, ScreenKit.TEXT_DIM, "MisoSmall")
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tip_label)
	add_child(ScreenKit.centered(v))


## Sets the bar (0..1) and the stage text.
func set_progress(fraction: float, stage: String) -> void:
	bar.value = clampf(fraction, 0.0, 1.0)
	stage_label.text = stage.capitalize() if stage != "" else ""


## A controls reminder built from the Controls autoload's key map.
static func _tip() -> String:
	var pairs: PackedStringArray = []
	for action in ["jump", "attack", "interact", "portal_enter", "pickup", "menu"]:
		pairs.append("%s: %s" % [String(ControlsPanel.LABELS.get(action, action)), ControlsPanel.keys_text(action)])
	return "  ·  ".join(pairs)
