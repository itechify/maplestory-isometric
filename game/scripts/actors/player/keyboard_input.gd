class_name KeyboardInput
extends InputSource
## Player intent from the Controls actions (keyboard, plus any gamepad events bound to the same actions).
##
## WASD move relative to the fixed isometric camera (W = up the screen). Up arrow (portal_enter) grabs ladders
## and ropes and climbs; Down arrow (climb_down) grabs from the top and climbs down; W/S also climb while on one.
## Input.is_action_just_pressed() is physics-frame aware in Godot 4, so reading it from the controller's
## _physics_process reports a press on exactly one tick.


func move_vector() -> Vector2:
	var v := Vector2(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_up") - Input.get_action_strength(&"move_down"))
	return v.limit_length(1.0)


func is_held(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


func just_pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func climb_axis() -> float:
	var up := is_held(&"move_up") or is_held(&"portal_enter")
	var down := is_held(&"move_down") or is_held(&"climb_down")
	return float(up) - float(down)
