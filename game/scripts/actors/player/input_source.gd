class_name InputSource
extends RefCounted
## Where the player's intent comes from (MAP_ARCHITECTURE.md section 4.13, L2 "InputSource").
##
## The PlayerController reads intent only through this interface, so the keyboard (KeyboardInput) and the
## scriptable traversal bot (BotInput) drive the identical CharacterBody3D with identical parameters. Action
## names are the Controls autoload's (jump, attack, interact, portal_enter, climb_down, pickup ...). Other systems
## that react to player input (portals, NPC talk, combat) should read `player.input_source` too, so the bot can
## press their keys.
##
## Per physics tick the controller calls begin_tick() once, then reads. State read after begin_tick() stays
## valid for the rest of that physics frame, so systems running after the player see the same presses.

## Called by the controller at the start of each physics tick, before anything reads this source.
func begin_tick() -> void:
	pass


## Screen-relative movement intent: x = right (D), y = up the screen (W). Length <= 1.
func move_vector() -> Vector2:
	return Vector2.ZERO


## World-space ground direction (length <= 1) for a camera whose ground-projected right/forward axes are given.
## The default maps move_vector() onto those axes, so W walks "screen up" on the ground plane.
func world_move(right: Vector3, forward: Vector3) -> Vector3:
	var mv := move_vector()
	var w := right * mv.x + forward * mv.y
	w.y = 0.0
	return w.limit_length(1.0)


## True while the action is held.
func is_held(_action: StringName) -> bool:
	return false


## True on the tick the action went down.
func just_pressed(_action: StringName) -> bool:
	return false


## Ladder/rope intent: +1 climbs up, -1 climbs down, 0 holds.
func climb_axis() -> float:
	return 0.0
