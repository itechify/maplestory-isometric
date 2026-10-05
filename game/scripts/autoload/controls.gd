extends Node
## Autoload "Controls": the game's input actions, registered in code so the key map is documented in one place.
##
## Action names are the contract every system uses (Input.is_action_pressed("jump") ...). Keyboard is mandatory and
## complete; gamepad bindings are optional extras. Classic MapleStory habits are kept where they do not fight WASD:
## Up arrow enters portals and grabs ladders/ropes, Z picks up, Ctrl attacks, Alt jumps, I/E/Q/K open windows.

## action -> Array of bindings: Key constants, "mouse:<button>" strings, or "joy:<button>" / "axis:<axis>:<sign>".
const BINDINGS := {
	"move_up": [KEY_W],
	"move_down": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE, KEY_ALT],
	"attack": [KEY_J, KEY_CTRL, "mouse:1"],
	"interact": [KEY_F],
	"portal_enter": [KEY_UP],
	"climb_down": [KEY_DOWN],
	"pickup": [KEY_Z],
	"sit": [KEY_X],
	"toggle_inventory": [KEY_I],
	"toggle_equipment": [KEY_E],
	"toggle_stats": [KEY_C],
	"toggle_quests": [KEY_Q, KEY_L],
	"toggle_skills": [KEY_K],
	"toggle_minimap": [KEY_M],
	"quickslot_1": [KEY_1],
	"quickslot_2": [KEY_2],
	"quickslot_3": [KEY_3],
	"quickslot_4": [KEY_4],
	"quickslot_5": [KEY_5],
	"quickslot_6": [KEY_6],
	"quickslot_7": [KEY_7],
	"quickslot_8": [KEY_8],
	"menu": [KEY_ESCAPE],
	"debug_console": [KEY_QUOTELEFT],
	"debug_overlay": [KEY_F3],
}

## Human-readable labels for help screens and the key-config panel.
const LABELS := {
	"move_up": "Move up", "move_down": "Move down", "move_left": "Move left", "move_right": "Move right",
	"jump": "Jump", "attack": "Attack", "interact": "Talk / use", "portal_enter": "Enter portal / climb",
	"climb_down": "Climb down", "pickup": "Pick up", "sit": "Sit", "toggle_inventory": "Inventory",
	"toggle_equipment": "Equipment", "toggle_stats": "Character stats", "toggle_quests": "Quests",
	"toggle_skills": "Skills", "toggle_minimap": "Minimap", "menu": "Menu / close",
	"debug_console": "Debug console", "debug_overlay": "Debug overlay",
}


func _enter_tree() -> void:
	register()


## Idempotent: (re)creates every action with its default bindings.
static func register() -> void:
	for action in BINDINGS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.2)
		for b in BINDINGS[action]:
			var ev := _event_for(b)
			if ev:
				InputMap.action_add_event(action, ev)


static func _event_for(b: Variant) -> InputEvent:
	if typeof(b) == TYPE_INT:
		var k := InputEventKey.new()
		k.physical_keycode = b
		return k
	var s := String(b)
	if s.begins_with("mouse:"):
		var m := InputEventMouseButton.new()
		m.button_index = int(s.get_slice(":", 1))
		return m
	if s.begins_with("joy:"):
		var j := InputEventJoypadButton.new()
		j.button_index = int(s.get_slice(":", 1))
		return j
	return null


## Display string for an action's first keyboard binding ("Space", "F" ...).
static func key_label(action: String) -> String:
	for b in BINDINGS.get(action, []):
		if typeof(b) == TYPE_INT:
			return OS.get_keycode_string(b)
	return "?"
