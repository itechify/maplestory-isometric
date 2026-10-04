class_name MisoNoticeLog
extends VBoxContainer
## The HUD message log (bottom left, above the bar): classic "You have gained ..." lines for items, mesos and EXP,
## quest updates, warnings and system notices. The newest line is at the bottom; each fades out after LIFETIME_S,
## and at most MAX_VISIBLE lines are on screen. Every line is also kept in `history` (newest last).

const MAX_VISIBLE := 7
const LIFETIME_S := 8.0
const FADE_S := 1.2
const HISTORY_SIZE := 100
## An identical line within this many seconds is not repeated (e.g. a full inventory while holding pickup).
const DEDUPE_S := 1.5

## Every logged line, oldest first: {text, tone, time}.
var history: Array = []
var _lines: Array = []
var _clock := 0.0


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 2)


## Adds a line. tone: "item", "mesos", "exp", "quest", "warn", "info" (MisoTheme.LOG_* colours).
func add_line(text: String, tone: String = "info") -> void:
	if not history.is_empty():
		var last: Dictionary = history[history.size() - 1]
		if String(last["text"]) == text and _clock - float(last["time"]) < DEDUPE_S:
			return
	history.append({"text": text, "tone": tone, "time": _clock})
	if history.size() > HISTORY_SIZE:
		history.pop_front()
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"MisoNotice"
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var l := MisoTheme.make_label(text, 14, color_for(tone), 3, MisoTheme.WEIGHT_BOLD)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(l)
	add_child(panel)
	_lines.append({"node": panel, "born": _clock})
	while _lines.size() > MAX_VISIBLE:
		var old: Dictionary = _lines.pop_front()
		(old["node"] as Node).queue_free()


## The texts of the lines in history (oldest first).
func texts() -> PackedStringArray:
	var out: PackedStringArray = []
	for h: Dictionary in history:
		out.append(String(h["text"]))
	return out


## Lines currently on screen.
func visible_count() -> int:
	return _lines.size()


static func color_for(tone: String) -> Color:
	match tone:
		"item":
			return MisoTheme.LOG_ITEM
		"mesos":
			return MisoTheme.LOG_MESOS
		"exp":
			return MisoTheme.LOG_EXP
		"quest":
			return MisoTheme.LOG_QUEST
		"warn":
			return MisoTheme.LOG_WARN
	return MisoTheme.LOG_INFO


func _process(delta: float) -> void:
	advance(delta)


## Advances the fade clock (called every frame; tests call it directly).
func advance(delta: float) -> void:
	_clock += delta
	var keep: Array = []
	for e: Dictionary in _lines:
		var node := e["node"] as Control
		var age := _clock - float(e["born"])
		if age >= LIFETIME_S + FADE_S:
			node.queue_free()
			continue
		node.modulate.a = 1.0 if age < LIFETIME_S else 1.0 - (age - LIFETIME_S) / FADE_S
		keep.append(e)
	_lines = keep
