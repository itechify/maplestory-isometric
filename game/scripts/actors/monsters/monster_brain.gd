class_name MonsterBrain
extends RefCounted
## The classic simple monster loop as pure state (MAP_ARCHITECTURE.md section 4.7.4): stand, pace back and forth,
## turn around when the body reports a ledge, a wall, the mob-region edge or the edge of its floor, stagger when hit,
## then follow the attacker for a while.
## No physics and no scene tree: Monster asks it where to go each tick and reports what the terrain said. Every
## timing comes from the species' MonsterDef (canonical clip lengths, adaptation timings); randomness comes from
## the RNG passed in, so tests are deterministic.
##
## Pacing (MeowDB 'Walks back and forth on the floor it spawns on'): the monster walks one line, `axis` (its spawn
## facing). It walks along it (+axis or -axis), turns around exactly when blocked, and after a stand turns around with
## pace_reverse_chance. When it is blocked twice in a row after less than pace_min_run_m each, the line itself turns by
## about 90 degrees (turn_jitter_deg), so a monster in a corner finds a line it can walk. A chase faces the attacker;
## when the chase ends the monster goes back to its line.

enum Mode { IDLE, WALK, STAGGER, CHASE, DEAD }

var def: MonsterDef = null
var rng: RandomNumberGenerator = null
var mode: Mode = Mode.IDLE
## Horizontal unit heading used while wandering: +axis or -axis.
var heading: Vector3 = Vector3.RIGHT
## The pacing line (horizontal unit vector).
var axis: Vector3 = Vector3.RIGHT
## Metres walked since the last turn (Monster reports them through walked()), and how many turns in a row came after
## less than pace_min_run_m.
var run_m: float = 0.0
var short_runs: int = 0
## Seconds left in the current IDLE / WALK / STAGGER.
var timer: float = 0.0
## Seconds left of following the attacker (after the stagger).
var chase_left: float = 0.0
## Seconds until a jumper's next ambient hop (counts while it moves).
var hop_timer: float = 0.0
## True once the player has hit this monster (the Peace touch rule reads it).
var provoked: bool = false
## Direction the stagger push moves the body (away from the attacker), and how much push is left (m).
var push_dir: Vector3 = Vector3.ZERO
var push_left: float = 0.0
## Turns taken (ledges, walls, region edge); for tests and the debug overlay.
var turns: int = 0


func _init(p_def: MonsterDef = null, p_rng: RandomNumberGenerator = null) -> void:
	def = p_def
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()


## Starts in a stand facing `initial_heading`, which is also its pacing line.
func start(initial_heading: Vector3) -> void:
	heading = _flat(initial_heading, Vector3.RIGHT)
	axis = heading
	run_m = 0.0
	short_runs = 0
	_enter_idle()
	if def != null and def.is_jumper():
		hop_timer = _roll(def.hop_interval_s)


## Advances the timers by `dt` and runs the mode transitions.
func tick(dt: float) -> void:
	if mode == Mode.DEAD:
		return
	timer -= dt
	match mode:
		Mode.IDLE:
			if timer <= 0.0:
				_enter_walk()
		Mode.WALK:
			hop_timer -= dt
			if timer <= 0.0:
				_enter_idle()
		Mode.STAGGER:
			if timer <= 0.0:
				push_left = 0.0
				if chase_left > 0.0:
					mode = Mode.CHASE
				else:
					_enter_idle()
		Mode.CHASE:
			hop_timer -= dt
			chase_left -= dt
			if chase_left <= 0.0:
				_enter_idle()


## The horizontal direction the monster wants to walk this tick (zero = stand). `me` and `target` are positions;
## the target (the attacker) only matters while chasing.
func move_dir(me: Vector3, target: Vector3) -> Vector3:
	match mode:
		Mode.WALK:
			return heading
		Mode.CHASE:
			var to := Vector3(target.x - me.x, 0.0, target.z - me.z)
			# Close enough to overlap: stand on the attacker (classic monsters walk into you, then stop).
			if to.length() < maxf(def.touch_size_m.x * 0.25 if def != null else 0.2, 0.05):
				return Vector3.ZERO
			return to.normalized()
	return Vector3.ZERO


func is_moving() -> bool:
	return mode == Mode.WALK or mode == Mode.CHASE


## The body could not continue (ledge, wall, region edge or the edge of its floor). Pacing turns around exactly, or
## turns its line when this is the second short run in a row; chasing stops at the edge facing the attacker, as
## classic monsters stop at the end of their foothold.
func on_blocked() -> void:
	turns += 1
	if mode == Mode.CHASE:
		return
	var min_run := def.pace_min_run_m if def != null else 0.0
	short_runs = short_runs + 1 if run_m < min_run else 0
	run_m = 0.0
	if short_runs >= 2:
		short_runs = 0
		axis = _new_axis()
		heading = axis
	else:
		heading = -heading


## The body moved `dist` metres along its line (a step or a hop while pacing).
func walked(dist: float) -> void:
	run_m += maxf(dist, 0.0)


## A hit landed: stagger (when the damage reached the KB threshold), become provoked, then follow the attacker.
func on_hit(me: Vector3, attacker: Vector3, staggers: bool) -> void:
	if mode == Mode.DEAD:
		return
	provoked = true
	chase_left = def.provoked_chase_s if def != null else 0.0
	var away := Vector3(me.x - attacker.x, 0.0, me.z - attacker.z)
	if staggers and def != null and def.stagger_s > 0.0:
		mode = Mode.STAGGER
		timer = def.stagger_s
		push_dir = _flat(away, -heading)
		push_left = def.knockback_m
	elif mode != Mode.STAGGER:
		mode = Mode.CHASE if chase_left > 0.0 else mode
	# Face the attacker (the heading resumes from there when the chase ends).
	var toward := -away
	if toward.length_squared() > 1e-6:
		heading = _flat(toward, heading)


## Push speed (m/s) while staggered: the knockback distance spread over the stagger.
func push_speed() -> float:
	if def == null or def.stagger_s <= 0.0:
		return 0.0
	return def.knockback_m / def.stagger_s


## A jumper's ambient hop is due (and resets its timer). The body still checks the landing.
func take_hop() -> bool:
	if def == null or not def.is_jumper() or not is_moving() or hop_timer > 0.0:
		return false
	hop_timer = _roll(def.hop_interval_s)
	return true


func die() -> void:
	mode = Mode.DEAD
	push_left = 0.0


func is_dead() -> bool:
	return mode == Mode.DEAD


## A stand. The heading goes back onto the pacing line (a chase or a hit left it facing the attacker).
func _enter_idle() -> void:
	mode = Mode.IDLE
	timer = _roll(def.idle_s) if def != null else 1.0
	heading = axis if heading.dot(axis) >= 0.0 else -axis


## A walk along the line: on, or turned around with pace_reverse_chance.
func _enter_walk() -> void:
	mode = Mode.WALK
	timer = _roll(def.walk_s) if def != null else 1.0
	if def != null and rng.randf() < def.pace_reverse_chance:
		heading = -heading


## A new pacing line: the current heading turned 90 degrees left or right, plus up to turn_jitter_deg either way.
func _new_axis() -> Vector3:
	var j := def.turn_jitter_rad if def != null else 0.0
	var a := PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)
	if j > 0.0:
		a += rng.randf_range(-j, j)
	return _flat(heading.rotated(Vector3.UP, a), Vector3.RIGHT)


func _roll(r: Vector2) -> float:
	return rng.randf_range(r.x, r.y) if r.y > r.x else r.x


static func _flat(v: Vector3, fallback: Vector3) -> Vector3:
	var f := Vector3(v.x, 0.0, v.z)
	return f.normalized() if f.length_squared() > 1e-8 else fallback
