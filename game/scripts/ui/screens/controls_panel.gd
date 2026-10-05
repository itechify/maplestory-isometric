class_name ControlsPanel
extends PanelContainer
## The key-binding list of the pause menu: every action of the Controls autoload (BINDINGS / LABELS) that the game
## handles, with all its keyboard and mouse bindings. Read-only for now (rebinding is a later feature). The actions
## in NOT_AVAILABLE are reserved in Controls.BINDINGS (an ARCHITECTURE.md contract) but nothing reads them yet, so
## the panel does not advertise their keys.

signal closed

## The Controls autoload's script, read by path so this panel also works where the autoload is not running.
const CONTROLS_SCRIPT := preload("res://scripts/autoload/controls.gd")
const BINDINGS: Dictionary = CONTROLS_SCRIPT.BINDINGS
const LABELS: Dictionary = CONTROLS_SCRIPT.LABELS
## Reserved actions with no handler yet (no skills window, no minimap): hidden from the list. Take one off when its
## feature lands; test_shell_screens fails while a hidden action is named by another script.
const NOT_AVAILABLE: PackedStringArray = ["toggle_skills", "toggle_minimap"]
## Mouse button names for "mouse:<n>" bindings.
const MOUSE_NAMES := {1: "Left click", 2: "Right click", 3: "Middle click"}


func _init() -> void:
	name = "ControlsPanel"
	if ScreenKit.has_miso_theme():
		theme_type_variation = "MisoWindow"
	else:
		add_theme_stylebox_override("panel", ScreenKit.box(ScreenKit.FALLBACK_PANEL, ScreenKit.FALLBACK_BORDER, 2, 10, 14))
	custom_minimum_size = Vector2(520, 0)
	var v := ScreenKit.vbox(10)
	add_child(v)
	v.add_child(ScreenKit.title("Controls"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for row in rows():
		var a := ScreenKit.label(String(row["label"]), 15)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(a)
		grid.add_child(ScreenKit.label(String(row["keys"]), 15, ScreenKit.GOLD, "MisoGold"))
	var foot := ScreenKit.hbox()
	foot.alignment = BoxContainer.ALIGNMENT_END
	var back := ScreenKit.button("Back", false, 120)
	back.name = "Back"
	back.pressed.connect(func() -> void: closed.emit())
	foot.add_child(back)
	v.add_child(foot)


func focus_default() -> void:
	var back := find_child("Back", true, false) as Button
	if back != null:
		back.grab_focus()


## [{"action", "label", "keys"}] in the key map's order, without the NOT_AVAILABLE actions.
static func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for action: String in BINDINGS:
		if NOT_AVAILABLE.has(action):
			continue
		out.append({"action": action, "label": String(LABELS.get(action, action.capitalize())), "keys": keys_text(action)})
	return out


## "Space / Alt" for an action's bindings (keyboard keys and mouse buttons; gamepad bindings are skipped).
static func keys_text(action: String) -> String:
	var parts: PackedStringArray = []
	for b: Variant in BINDINGS.get(action, []):
		if typeof(b) == TYPE_INT:
			parts.append(OS.get_keycode_string(int(b)))
		elif str(b).begins_with("mouse:"):
			parts.append(String(MOUSE_NAMES.get(int(str(b).get_slice(":", 1)), "Mouse %s" % str(b).get_slice(":", 1))))
	return " / ".join(parts) if not parts.is_empty() else "-"
