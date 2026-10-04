class_name BotInput
extends InputSource
## Scriptable intent for the traversal bot and for tests: the same InputSource interface as the keyboard.
##
##   var bot := BotInput.new()
##   player.set_input_source(bot)
##   bot.world_dir = Vector3(1, 0, 0)    # walk along +X (world space), or set bot.move for screen-relative intent
##   bot.press(&"jump")                  # one-tick tap: held and just_pressed on the next tick
##   bot.hold(&"portal_enter")           # held until release(); just_pressed on the first tick only
##   bot.climb = 1.0                     # climb up while on a ladder/rope
##
## Every action name works (jump, attack, portal_enter, interact, climb_down, pickup ...), so the bot can also
## attack, enter portals and talk through systems that read player.input_source.

## Screen-relative intent (x right, y up the screen), used when world_dir is zero.
var move: Vector2 = Vector2.ZERO
## World-space ground direction; overrides `move` when non-zero. Length is clamped to 1.
var world_dir: Vector3 = Vector3.ZERO
## Ladder/rope intent: +1 up, -1 down. When 0, the keyboard rule applies (see climb_axis()).
var climb: float = 0.0

var _held: Dictionary = {}
var _taps: Dictionary = {}
var _cur: Dictionary = {}
var _edge: Dictionary = {}


## Holds (or releases) an action until changed.
func hold(action: StringName, on: bool = true) -> void:
	if on:
		_held[action] = true
	else:
		_held.erase(action)


func release(action: StringName) -> void:
	_held.erase(action)


## A one-tick tap: the action is held and just_pressed during the next tick only.
func press(action: StringName) -> void:
	_taps[action] = true


## Clears every held action, tap and movement intent.
func release_all() -> void:
	_held.clear()
	_taps.clear()
	move = Vector2.ZERO
	world_dir = Vector3.ZERO
	climb = 0.0


func begin_tick() -> void:
	var now := {}
	for a in _held:
		now[a] = true
	for a in _taps:
		now[a] = true
	_edge = {}
	for a in now:
		if not _cur.has(a):
			_edge[a] = true
	_cur = now
	_taps.clear()


## `move`, plus any held move_* actions (the same actions KeyboardInput reads), so a bot can also "hold W".
func move_vector() -> Vector2:
	var v := move + Vector2(float(is_held(&"move_right")) - float(is_held(&"move_left")),
		float(is_held(&"move_up")) - float(is_held(&"move_down")))
	return v.limit_length(1.0)


func world_move(right: Vector3, forward: Vector3) -> Vector3:
	if world_dir.length_squared() > 0.000001:
		return Vector3(world_dir.x, 0.0, world_dir.z).limit_length(1.0)
	return super.world_move(right, forward)


func is_held(action: StringName) -> bool:
	return _cur.has(action)


func just_pressed(action: StringName) -> bool:
	return _edge.has(action)


## `climb` when set; otherwise the keyboard's rule: up = move up or portal_enter (Up arrow) held, down = move down
## or climb_down (Down arrow) held.
func climb_axis() -> float:
	if climb != 0.0:
		return clampf(climb, -1.0, 1.0)
	var mv := move_vector()
	var up := mv.y > 0.0 or is_held(&"portal_enter")
	var down := mv.y < 0.0 or is_held(&"climb_down")
	return float(up) - float(down)
