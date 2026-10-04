class_name RouteBot
extends RefCounted
## Walks a PlayerController along a sidecar route polyline through a BotInput: the seed of the L2 traversal bot
## (MAP_ARCHITECTURE.md section 4.13). It drives the identical controller the keyboard drives.
##
## Steering is pure pursuit with a 1 m lookahead along the route. Where the route rises by more than step_up
## between consecutive points, the bot climbs if a climbable spans that rise within Iteration One's 2.2 m
## CLIMB_RADIUS (walks to it, presses Up, climbs until the controller exits at the top), and otherwise jumps when
## the rise blocks it. Drops are walked off. Progress is the 3D arc length of the closest route point (searched
## in a window around the current progress, so the bot is never credited for a parallel stretch it has not
## reached); no progress for stall_time_s is a stall.
##
##   var rb := RouteBot.create(sidecar_route["points"], player.climbables, player.model)
##   each physics tick:  rb.tick(player, bot_input, delta); player.step(delta)
##   player.fell_out_of_world.connect(func(_at): rb.notify_fall())
##   rb.result is DONE, STALLED, FELL or TIMEOUT when finished; rb.report() describes the run.

enum Result { RUNNING, DONE, STALLED, FELL, TIMEOUT }

const CLIMB_RADIUS := 2.2

var name: String = ""
var points: PackedVector3Array = PackedVector3Array()
## Cumulative 3D arc length at each point.
var cum: PackedFloat32Array = PackedFloat32Array()
var length: float = 0.0
var climbables: Array[ClimbableDef] = []
var model: MovementModel = null
var lookahead: float = 1.0
var stall_time_s: float = 2.0
## A run longer than this (walk time x factor + climbs) is a timeout.
var max_time_s: float = 0.0

var result: Result = Result.RUNNING
## Arc length reached so far (monotonic).
var progress: float = 0.0
var elapsed: float = 0.0
var jumps: int = 0
var climbs: int = 0
var falls: int = 0
var stalled_at: Vector3 = Vector3.ZERO
var events: PackedStringArray = PackedStringArray()

var _since_progress: float = 0.0
var _was_climbing: bool = false
## +1 / -1: the direction chosen when the bot grabbed (kept until the controller lets go, so the bot never
## dithers at the foot or the top); 0 = decide from the route.
var _climb_dir: float = 0.0


## A bot for `route_points` (sidecar `points`: Array of [x, y, z], or a PackedVector3Array).
static func create(route_points: Variant, route_climbables: Array[ClimbableDef], movement: MovementModel, route_name: String = "") -> RouteBot:
	var rb := RouteBot.new()
	rb.name = route_name
	rb.model = movement
	rb.climbables = route_climbables
	var pts := PackedVector3Array()
	if route_points is PackedVector3Array:
		pts = route_points
	else:
		for e in route_points:
			if e is Vector3:
				pts.append(e)
			elif e is Array and (e as Array).size() >= 3:
				pts.append(Vector3(float(e[0]), float(e[1]), float(e[2])))
	rb._set_points(pts)
	return rb


## The same route walked backwards.
func reversed() -> RouteBot:
	var pts := points.duplicate()
	pts.reverse()
	var rb := RouteBot.create(pts, climbables, model, name + " (reverse)")
	rb.lookahead = lookahead
	rb.stall_time_s = stall_time_s
	return rb


func _set_points(pts: PackedVector3Array) -> void:
	points = pts
	cum = PackedFloat32Array()
	var acc := 0.0
	for i in points.size():
		if i > 0:
			acc += points[i].distance_to(points[i - 1])
		cum.append(acc)
	length = acc
	var climb_total := 0.0
	for i in range(1, points.size()):
		climb_total += maxf(0.0, absf(points[i].y - points[i - 1].y) - 0.5)
	# Speeds come only from the MovementModel (canonical data); without one the bot cannot budget a run.
	if model == null or model.walk_speed <= 0.0 or model.climb_speed <= 0.0:
		push_error("[RouteBot] %s: no MovementModel speeds; the run times out at once" % name)
		max_time_s = 0.0
		return
	max_time_s = length / model.walk_speed * 1.6 + climb_total / model.climb_speed * 1.5 + 5.0


func start_point() -> Vector3:
	return points[0] if not points.is_empty() else Vector3.ZERO


## Facing along the first segment (for the spawn transform).
func start_facing() -> Vector3:
	if points.size() < 2:
		return Vector3.BACK
	var d := points[1] - points[0]
	d.y = 0.0
	return d.normalized() if d.length_squared() > 1e-6 else Vector3.BACK


## Call when the player fell out of the world (fell_out_of_world): the run fails.
func notify_fall() -> void:
	falls += 1
	if result == Result.RUNNING:
		result = Result.FELL
		events.append("fell at %.1fs" % elapsed)


## Decides this tick's input. Call before player.step(delta). Returns the (possibly final) result.
func tick(p: PlayerController, bot: BotInput, delta: float) -> Result:
	if result != Result.RUNNING:
		bot.release_all()
		return result
	elapsed += delta
	var pos := p.global_position
	var s := closest_arc(pos, progress - 1.5, progress + 3.0)
	if s > progress + 0.05:
		progress = s
		_since_progress = 0.0
	else:
		_since_progress += delta
	var end := points[-1]
	var near_end := Vector2(end.x - pos.x, end.z - pos.z).length() < 0.75 and absf(end.y - pos.y) < 0.5
	if (progress >= length - 0.35 and pos.distance_to(end) < 1.2) or (near_end and progress >= length - 1.0):
		result = Result.DONE
		bot.release_all()
		return result
	if _since_progress > stall_time_s:
		result = Result.STALLED
		stalled_at = pos
		events.append("stalled at %s (progress %.1f / %.1f m)" % [_fmt(pos), progress, length])
		bot.release_all()
		return result
	if elapsed > max_time_s:
		result = Result.TIMEOUT
		stalled_at = pos
		events.append("timeout at %s (progress %.1f / %.1f m)" % [_fmt(pos), progress, length])
		bot.release_all()
		return result
	bot.climb = 0.0
	if p.is_climbing():
		if not _was_climbing:
			climbs += 1
			events.append("climb %s at %.1fs" % [p.current_climbable.name, elapsed])
		_was_climbing = true
		bot.world_dir = Vector3.ZERO
		if _climb_dir == 0.0:
			_climb_dir = 1.0 if point_at(progress + 1.0).y > pos.y else -1.0
		# Climbing down to ground that lies above the climbable's foot (a ledge beside a ladder in a trench):
		# jump off sideways once level with it, as a player would.
		var off := _ground_after_climb(p.current_climbable)
		if _climb_dir < 0.0 and off.size() > 0:
			var exit_pt: Vector3 = off["point"]
			if exit_pt.y > p.current_climbable.bottom.y + model.step_up and pos.y <= exit_pt.y + 0.35:
				bot.world_dir = _dir_to(pos, exit_pt)
				bot.press(&"jump")
				events.append("jump off %s at %.1fs" % [p.current_climbable.name, elapsed])
				return result
		bot.climb = _climb_dir
		return result
	_was_climbing = false
	_climb_dir = 0.0
	var rise := _next_rise(s, 2.5, pos)
	if rise.size() > 0:
		var up := float(rise["dy"]) > 0.0
		# A rise within jump reach (apex + step band, with a margin) is jumped, ladder or not.
		var jumpable := up and float(rise["dy"]) <= model.jump_apex + model.step_up - 0.1
		var c := null if jumpable else _climbable_for(rise, up)
		if c != null and up:
			# Climb up: walk to the foot of the ladder/rope and press Up.
			if c.line_distance_xz(pos) <= model.climb_grab_radius * 0.9 and pos.y <= c.top.y - 0.5:
				bot.world_dir = Vector3.ZERO
				_tap(bot, &"portal_enter")
				_climb_dir = 1.0
				return result
			bot.world_dir = _dir_to(pos, c.climb_position(c.bottom.y, model.climb_standoff))
			return result
		if c != null:
			# Climb down: walk to its top exit and press Down.
			var near_top := minf(c.top_exit_distance_xz(pos), c.line_distance_xz(pos)) <= model.climb_top_grab_radius * 0.9
			if near_top and absf(pos.y - c.top.y) < 0.5:
				bot.world_dir = Vector3.ZERO
				_tap(bot, &"climb_down")
				_climb_dir = -1.0
				return result
			bot.world_dir = _dir_to(pos, c.top_exit)
			return result
		if up:
			var start: Vector3 = rise["start"]
			var near := Vector2(start.x - pos.x, start.z - pos.z).length() < 1.2
			if near and p.is_grounded() and (_since_progress > 0.2 or p.actual_velocity.length() < model.walk_speed * 0.5):
				bot.press(&"jump")
				jumps += 1
	bot.world_dir = _dir_to(pos, _steer_target(pos, s))
	return result


## One-line summary of the run.
func report() -> String:
	return "route=%s result=%s progress=%.1f/%.1fm time=%.1fs jumps=%d climbs=%d falls=%d%s" % [
		name, Result.keys()[result], progress, length, elapsed, jumps, climbs, falls,
		(" at " + _fmt(stalled_at)) if result in [Result.STALLED, Result.TIMEOUT] else ""]


# --- route geometry ------------------------------------------------------------------------------------------------

## Point at arc length s (clamped).
func point_at(s: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	s = clampf(s, 0.0, length)
	for i in range(1, points.size()):
		if cum[i] >= s:
			var seg := cum[i] - cum[i - 1]
			var t := 0.0 if seg <= 1e-6 else (s - cum[i - 1]) / seg
			return points[i - 1].lerp(points[i], t)
	return points[-1]


## Arc length of the route point closest to `pos` (3D), searched only where arc length is in [lo, hi].
func closest_arc(pos: Vector3, lo: float, hi: float) -> float:
	var best_s := clampf(lo, 0.0, length)
	var best_d := INF
	for i in range(1, points.size()):
		if cum[i] < lo or cum[i - 1] > hi:
			continue
		var a := points[i - 1]
		var b := points[i]
		var ab := b - a
		var t := 0.0 if ab.length_squared() < 1e-9 else clampf((pos - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var s := cum[i - 1] + (cum[i] - cum[i - 1]) * t
		if s < lo or s > hi:
			s = clampf(s, lo, hi)
			t = 0.0 if cum[i] - cum[i - 1] < 1e-6 else (s - cum[i - 1]) / (cum[i] - cum[i - 1])
		var d := pos.distance_squared_to(a.lerp(b, clampf(t, 0.0, 1.0)))
		if d < best_d:
			best_d = d
			best_s = s
	return best_s


## The first segment within `horizon` meters of arc after s that rises or drops more than a step and that the
## player at `pos` has not already got past (above a rise's top, below a drop's bottom): {index, dy, start, end}.
func _next_rise(s: float, horizon: float, pos: Vector3) -> Dictionary:
	var limit := model.step_up + 0.05
	for i in range(1, points.size()):
		if cum[i] <= s:
			continue
		if cum[i - 1] > s + horizon:
			break
		var dy := points[i].y - points[i - 1].y
		if absf(dy) <= limit:
			continue
		if (dy > 0.0 and pos.y >= points[i].y - 0.3) or (dy < 0.0 and pos.y <= points[i].y + 0.3):
			continue
		return {"index": i, "dy": dy, "start": points[i - 1], "end": points[i]}
	return {}


## The first route point ahead that is off the climb line (> 0.6 m away horizontally): {point} or {}.
func _ground_after_climb(c: ClimbableDef) -> Dictionary:
	if c == null:
		return {}
	for i in points.size():
		if cum[i] <= progress:
			continue
		if c.line_distance_xz(points[i]) > 0.6:
			return {"point": points[i]}
	return {}


## Pure-pursuit target: the route point lookahead meters ahead, pushed further along the route until it is at
## least 0.5 m away horizontally (vertical route segments - drops - give no direction of their own).
func _steer_target(pos: Vector3, s: float) -> Vector3:
	var a := s + lookahead
	var t := point_at(a)
	while a < length and Vector2(t.x - pos.x, t.z - pos.z).length() < 0.5:
		a += 0.25
		t = point_at(a)
	return t


## The climbable spanning a rise (Iteration One's _near_climb rule: within CLIMB_RADIUS of the rise, covering
## its heights).
func _climbable_for(rise: Dictionary, up: bool) -> ClimbableDef:
	var a: Vector3 = rise["start"]
	var b: Vector3 = rise["end"]
	var mid := (a + b) * 0.5
	var lo := minf(a.y, b.y)
	var hi := maxf(a.y, b.y)
	var best: ClimbableDef = null
	var best_d := INF
	for c in climbables:
		var d := Vector2(c.bottom.x - mid.x, c.bottom.z - mid.z).length()
		if d > CLIMB_RADIUS:
			continue
		if c.bottom.y > lo + 0.6 or c.top.y < hi - 0.6:
			continue
		if c.descend_only and up:
			continue
		if d < best_d:
			best_d = d
			best = c
	return best


## Presses `action` as a fresh tap: never on two ticks in a row (that would read as one held key, and a press
## swallowed by the controller - e.g. during its re-grab cooldown - would never repeat).
func _tap(bot: BotInput, action: StringName) -> void:
	if not bot.is_held(action):
		bot.press(action)


func _dir_to(from: Vector3, to: Vector3) -> Vector3:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return d.normalized() if d.length_squared() > 1e-6 else Vector3.ZERO


func _fmt(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
