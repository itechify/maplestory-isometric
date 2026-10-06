class_name PlayerController
extends CharacterBody3D
## The player's body: isometric 8-direction movement, jumping, step-up, ladders/ropes, hit reactions and death.
##
## A kinematic controller advanced one physics tick at a time by step(delta). _physics_process calls step();
## tests and the traversal bot call it directly, so the same code runs headless and synchronously
## (move_and_slide() reads the engine's frame delta and cannot). Intent comes only from an InputSource
## (KeyboardInput in play, BotInput for the bot and tests). Numbers come from a MovementModel (canonical MeowDB
## values x WorldScale, plus data/misostory/movement.json).
##
## Body model ("floating capsule"): the collision capsule covers the body from step_up (0.45 m) to the full
## height (1.5 m); the band below it is sensed by the feet, a disc of downward rays. The player stands on the
## highest walkable hit under the disc, so stairs, ledges, roots and stones up to step_up are walked over without
## snagging (the capsule never touches them), and the player drops off an edge when the feet leave it. Anything
## that reaches the capsule while grounded is a wall (never climbed). Slopes up to floor_max_angle are walkable.
## A separate 1.5 m Hurtbox Area3D in player.tscn is the volume monsters touch.
##
## Feel is MapleStory-like: full walk speed within 3 ticks, stops in 2, momentum kept in the air with limited
## steering, a short 2000 px/s^2 jump arc, coyote time and a jump buffer.
##
## Contract used by other systems (keep these names):
##   teleport(xform)                         world runtime: arrival placement (MAP_ARCHITECTURE section 4.5 step 9)
##   is_on_floor()                           kept truthful in-game (synced each physics tick); is_grounded() everywhere
##   in_hitstun, safe_ground, kill_y         GateMonitor / fall recovery / saves (sections 4.4, 4.6, 4.9)
##   apply_knockback(from_dir, ...)          combat (wave 2); apply_knockback_from_point(source_pos, ...)
##   set_invulnerable(s), is_invulnerable()  combat
##   die(), revive(), is_dead()              death flow (section 4.8); also driven by Events.player_died/respawned
##   set_input_enabled(bool)                 UI windows, transitions
##   input_source                            read it to see the same presses the player sees (bot-friendly)
##   set_climbables(list) / add_climbables_from_sidecar(arr)   world runtime / sandbox
##   follow_anchor()                         camera focus: feet x/z at ground height (no jump bob; a ladder-top exit glides)
##   activity()                              what the player is doing (contract C4): natural recovery, skills, HUD
##   sit(chair_id), stand_up(reason), is_seated(), seated_chair_id(), can_sit(), sit_key()   chairs (C5, Chairs)
##
## Sitting (contract C5): seated is a flag on GROUND, not a state of its own. The player sits only when grounded,
## still, alive and with input enabled (no modal window); while seated it cannot walk, jump or climb. A move or jump
## press stands it up (that press does not also move or jump), and so do an attack or skill (PlayerCombat attacking),
## the sit key, knockback, death, teleport (warps, respawns, loads), a MapSession transition starting, the character
## being replaced, losing the chair item, and leaving the ground. The seated state is never saved.

signal jumped
## Emitted on touching walkable ground after being airborne; fall_speed is the downward speed at impact (m/s).
signal landed(fall_speed: float)
signal climb_started(climbable: ClimbableDef)
## how: &"top", &"bottom", &"jump", &"hit", &"teleport", &"death"
signal climb_ended(climbable: ClimbableDef, how: StringName)
signal knocked_back(push_dir: Vector3)
signal died
signal revived
signal teleported(xform: Transform3D)
## Airborne below kill_y. Recovery belongs to MapSession (teleport to safe_ground.transform()); emitted once
## until the next teleport().
signal fell_out_of_world(at: Vector3)
## Sat down on the chair item `chair_id` (also Events.player_sat_down).
signal sat_down(chair_id: String)
## Stood up; reason: &"move", &"jump", &"attack", &"sit_key", &"chair", &"knockback", &"death", &"climb", &"teleport",
## &"warp", &"chair_lost", &"character", &"fall", or what the caller of stand_up() passed (also Events.player_stood_up).
signal stood_up(reason: StringName)

enum State { GROUND, AIR, CLIMB }

## Horizontal speed (m/s) under which a grounded player with no movement input counts as standing still (activity()).
## An engineering threshold for "about zero" (ground_decel stops the body within 2 ticks), not a gameplay value.
const STILL_SPEED := 0.05

const MAX_SLIDES := 4
## Ticks of "falling without falling" (resting on the capsule, e.g. wedged between steep faces) before that
## resting point counts as ground.
const WEDGE_TICKS := 6
## Probe distance of the "is the capsule still resting on something" test that keeps wedged ground latched.
const WEDGE_SUPPORT_PROBE := 0.03
## The feet rays start this far above the step band, so a surface exactly at step height is still seen.
const RAY_HEADROOM := 0.05
## Radius of the sphere used only to sync CharacterBody3D.is_on_floor().
const FLOOR_SENSOR_RADIUS := 0.02

## Movement numbers. Built from Data.db in _ready() when not injected before entering the tree.
var model: MovementModel = null
## Intent source; KeyboardInput unless replaced (BotInput for the bot/tests).
var input_source: InputSource = KeyboardInput.new()
## Ground-projected camera axes used to turn screen-relative input into world directions. The CameraRig sets
## them (set_view_axes); the defaults are Iteration One's fixed isometric view (W walks toward Godot +X -Z).
var view_right: Vector3 = Vector3(1.0, 0.0, 1.0).normalized()
var view_forward: Vector3 = Vector3(1.0, 0.0, -1.0).normalized()
## Ladders/ropes/vines the player may grab (world space). See set_climbables().
var climbables: Array[ClimbableDef] = []
## Airborne below this height emits fell_out_of_world once. -INF disables the check.
var kill_y: float = -INF
## Optional extra condition for recording SafeGround: func(pos: Vector3) -> bool, or func(pos: Vector3,
## collider: Object) -> bool to also see the floor collider. The world runtime (FallRecovery) installs its
## RegionIndex check here (MAP_ARCHITECTURE section 4.6).
var safe_ground_filter: Callable = Callable()
## When true, _ready() connects Events.stats_changed / player_died / player_respawned and reads Game/Data.
@export var use_autoloads: bool = true

# --- state other systems read ----------------------------------------------------------------------------------
var state: State = State.AIR
## Horizontal unit vector the character faces (MODEL_FRONT convention: the model's +Z points along it).
var facing: Vector3 = Vector3(1.0, 0.0, -1.0).normalized()
## True while a knockback is in flight: no input, no air control. GateMonitor waits for it to clear.
var in_hitstun: bool = false
var safe_ground: SafeGround = SafeGround.new()
## Normal of the walkable surface under the feet (last ground contact).
var floor_normal: Vector3 = Vector3.UP
var current_climbable: ClimbableDef = null
## Horizontal velocity the controller is trying to move with (m/s).
var move_velocity: Vector3 = Vector3.ZERO
## Vertical speed (m/s, + up).
var vertical_speed: float = 0.0
## Presentation-only offset the visual applies after instant snaps (steps, ladder grab/exit); decays to 0.
var presentation_offset: Vector3 = Vector3.ZERO
## Horizontal displacement of the last tick divided by delta (what actually happened, after collisions).
var actual_velocity: Vector3 = Vector3.ZERO
## The chair item the player sits on ("" = standing). See sit() / stand_up().
var seated_chair: String = ""
## Injection seam (tests): the character whose Set-up tab the sit key reads. null = Game.character.
var chair_owner: CharacterState = null

var _dead: bool = false
var _input_enabled: bool = true
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _invuln: float = 0.0
var _hitstun_t: float = 0.0
var _regrab_cooldown: float = 0.0
var _grounded_ticks: int = 0
var _wedge_ticks: int = 0
## Grounded on the capsule alone (wedged between steep faces; no feet ray supports the body). Latched while the
## capsule stays supported, so a wedged player does not flicker between GROUND and AIR.
var _wedged: bool = false
var _anchor_y: float = 0.0
## Horizontal offset of the camera's follow point from the feet after a ladder-top exit (follow_anchor()); shrinks to
## zero at walking speed.
var _follow_glide: Vector3 = Vector3.ZERO
var _fell_reported: bool = false
var _settle_pending: bool = false
var _floor_collider_id: int = 0
var _floor_collider: Object = null
## Horizontal offset (from the feet) of the ray that found the current floor.
var _support_offset: Vector3 = Vector3.ZERO
var _jump_released_since_jump: bool = true
## The movement intent of the last tick (after input gating): activity() tells "walking" from "still" by it.
var _last_wish: Vector3 = Vector3.ZERO
## The jump key was held on the last tick (after input gating): a held jump re-hops on landing (hold_to_rejump).
var _last_jump_held: bool = false
var _foot_offsets: PackedVector3Array = PackedVector3Array()
var _ray: PhysicsRayQueryParameters3D = null
var _body_shape: CollisionShape3D = null
var _floor_sensor: CollisionShape3D = null


func _init() -> void:
	# The world's shared layer table (docs/runtime/WORLD_RUNTIME.md "Collision layers"): the player body sits on
	# the player layer and collides with walkable, blocking, containment and scenery. Scenes may override.
	collision_layer = WorldLayers.PLAYER
	collision_mask = WorldLayers.PLAYER_MASK


func _ready() -> void:
	if model == null:
		var db := _data_db()
		if db != null:
			model = MovementModel.from_db(db)
		else:
			push_error("[PlayerController] no MovementModel (Data autoload missing?)")
	_configure_shapes()
	_anchor_y = global_position.y
	if use_autoloads:
		# The live player: item code (Chairs.seat_for) finds the seated-state owner through this group.
		add_to_group(Chairs.SEAT_GROUP)
		_connect_autoloads()


func _physics_process(delta: float) -> void:
	step(delta)
	_sync_engine_floor_state(delta)


# =================================================================================================================
# Public API
# =================================================================================================================

## One simulation tick. Reads the InputSource once, moves the body, updates SafeGround and timers.
func step(delta: float) -> void:
	if model == null or delta <= 0.0 or not is_inside_tree():
		return
	var start_pos := global_position
	input_source.begin_tick()
	_tick_timers(delta)
	if _settle_pending:
		_settle_pending = false
		_settle(model.teleport_settle)
	var intent := _read_intent()
	_last_wish = intent.wish
	_last_jump_held = intent.jump_held
	if is_seated():
		# Seated: no walking, jumping or climbing. A move, jump or sit press (or PlayerCombat attacking) stands the player
		# up, and that press does nothing else this tick (a held key walks from the next tick on).
		_step_seated(intent)
		intent = Intent.new()
	elif intent.sit:
		sit_key()
		if is_seated():
			intent = Intent.new()
	if state == State.CLIMB:
		_step_climb(delta, intent)
	else:
		_step_move(delta, intent)
	# Seated is a flag on GROUND: a seat never leaves the ground (the floor gone under it, a push off a ledge).
	if is_seated() and state != State.GROUND:
		stand_up(&"fall")
	_post_step(delta, start_pos)


## True when standing on walkable ground (this controller's own floor state; use it in code and tests).
func is_grounded() -> bool:
	return state == State.GROUND


func is_climbing() -> bool:
	return state == State.CLIMB


func is_dead() -> bool:
	return _dead


func is_input_enabled() -> bool:
	return _input_enabled


## What the player is doing now (contract C4), one of:
##   &"dead"; &"seated" (&"attacking" on the tick an attack starts from the chair); &"hitstun" (a knockback in
##   flight); &"climbing"; &"attacking" (PlayerCombat.is_attacking(): a basic attack's or a skill cast's lockout);
##   &"jumping" (any airborne state: a jump, a fall; also the landing
##   ticks between the hops of a held jump); &"walking" (movement input, or still moving faster than STILL_SPEED, also
##   input pushing into a wall); &"still" (grounded, no movement input, horizontal speed about zero; input disabled by
##   a dialogue counts as no input); &"other" (no movement model, not in the tree, or not processing: frozen for a
##   warp, the game paused).
## Natural HP recovery runs only while &"still" or &"seated" (data/misostory/recovery.json natural_hp).
func activity() -> StringName:
	if model == null or not is_inside_tree() or not can_process():
		return &"other"
	if _dead:
		return &"dead"
	if is_seated():
		# An attack or a skill cast started from the chair (PlayerCombat runs after this body) stands the player up on the
		# next tick (_step_seated); the swing itself is never resting time.
		return &"attacking" if _combat_attacking() else &"seated"
	if in_hitstun:
		return &"hitstun"
	if state == State.CLIMB:
		return &"climbing"
	if _combat_attacking():
		return &"attacking"
	# A held jump re-hops on the tick after landing (hold_to_rejump): that landing is part of the jumping.
	if state == State.AIR or (model.hold_to_rejump and _last_jump_held and not _jump_released_since_jump):
		return &"jumping"
	if _last_wish.length_squared() > 0.0001 or move_velocity.length() > STILL_SPEED \
			or actual_velocity.length() > STILL_SPEED:
		return &"walking"
	return &"still"


func is_seated() -> bool:
	return seated_chair != ""


## The chair item the player sits on, or "" when standing.
func seated_chair_id() -> String:
	return seated_chair


## "" when the player may sit down now (contract C5: alive, input enabled so no modal window or warp holds the
## keyboard, standing, grounded and still), else why not: "dead", "input", "seated", or the activity in the way
## ("walking", "jumping", "climbing", "attacking", "hitstun", "other").
func can_sit() -> String:
	if _dead:
		return "dead"
	if not _input_enabled:
		return "input"
	if is_seated():
		return "seated"
	var a := activity()
	return "" if a == &"still" else String(a)


## Sits down on the chair item `chair_id` (Chairs checks the item; this checks the body, see can_sit()). Returns false
## (and changes nothing) when sitting is not allowed now.
func sit(chair_id: String) -> bool:
	if chair_id == "" or can_sit() != "":
		return false
	seated_chair = chair_id
	move_velocity = Vector3.ZERO
	_jump_buffer = 0.0
	sat_down.emit(chair_id)
	_emit_event(&"player_sat_down", [chair_id])
	return true


## Stands up (no-op, false, when not seated). `reason` is reported with stood_up / Events.player_stood_up.
func stand_up(reason: StringName = &"stand") -> bool:
	if not is_seated():
		return false
	seated_chair = ""
	stood_up.emit(reason)
	_emit_event(&"player_stood_up", [String(reason)])
	return true


## The sit key (X): stands up when seated, else sits on the first chair in the Set-up tab of chair_owner
## (Game.character by default); see Chairs.sit_key. A refusal is announced with Events.notice. Returns the result.
func sit_key() -> Dictionary:
	var res := Chairs.sit_key(_chair_character(), _data_db(), self)
	if not bool(res.get("ok", false)):
		_emit_event(&"notice", [ItemCodes.message(res)])
	return res


## Places the player at `xform` (origin = feet). Facing comes from the basis' +Z (MODEL_FRONT, the sidecar and
## kit convention). Zeroes velocity, clears jump buffer / coyote / hit-stun, leaves any ladder, resets SafeGround
## to the arrival point and settles onto ground within teleport_settle below it (or step_up above), so
## is_grounded() holds at once and, in-game, is_on_floor() from the next physics tick. Does not change the dead
## flag. Stands the player up (a warp never carries a seat along). Called by MapSession on warps and respawns.
func teleport(xform: Transform3D) -> void:
	stand_up(&"teleport")
	if state == State.CLIMB and current_climbable != null:
		var c := current_climbable
		current_climbable = null
		climb_ended.emit(c, &"teleport")
	global_position = xform.origin
	var f := Vector3(xform.basis.z.x, 0.0, xform.basis.z.z)
	if f.length_squared() > 0.0001:
		facing = f.normalized()
	move_velocity = Vector3.ZERO
	vertical_speed = 0.0
	velocity = Vector3.ZERO
	actual_velocity = Vector3.ZERO
	_coyote = 0.0
	_jump_buffer = 0.0
	in_hitstun = false
	_hitstun_t = 0.0
	_regrab_cooldown = 0.0
	_wedge_ticks = 0
	_wedged = false
	_fell_reported = false
	presentation_offset = Vector3.ZERO
	_follow_glide = Vector3.ZERO
	state = State.AIR
	# The feet rays query the space directly, so this works while MapSession has the body frozen (disabled).
	if model != null and is_inside_tree():
		_settle(model.teleport_settle)
	else:
		_settle_pending = true
	safe_ground.reset(global_position, facing)
	_anchor_y = global_position.y
	if is_inside_tree():
		reset_physics_interpolation()  # a warp never streaks across the map if physics interpolation is enabled
	if is_inside_tree() and can_process():
		_sync_engine_floor_state(get_physics_process_delta_time())
	teleported.emit(xform)


## Knocks the player back (combat, wave 2). `from_dir` points FROM the damage source TOWARD the player: the
## player is pushed along its horizontal part (zero = pushed backwards, opposite to facing). The vertical launch
## and gravity are MeowDB's knockback model (270 px/s up, 2000 px/s^2, x WorldScale.v); the horizontal push is an
## adaptation (movement.json). Starts hit-stun (until landing, at most knockback_max_hitstun) and invulnerability
## for `invulnerability_s` seconds (negative = the combat data's post-hit invincibility, see
## default_invulnerability_seconds()). Knocks the player off a ladder/rope, or off a chair.
func apply_knockback(from_dir: Vector3, strength: float = 1.0, invulnerability_s: float = -1.0) -> void:
	if _dead or model == null:
		return
	stand_up(&"knockback")
	if state == State.CLIMB:
		_leave_climb(&"hit")
	var push := Vector3(from_dir.x, 0.0, from_dir.z)
	if push.length_squared() < 0.0001:
		push = -facing
	push = push.normalized()
	move_velocity = push * model.knockback_speed * strength
	vertical_speed = model.knockback_up_speed
	state = State.AIR
	_grounded_ticks = 0
	_coyote = 0.0
	_jump_buffer = 0.0
	in_hitstun = true
	_hitstun_t = model.knockback_max_hitstun
	set_invulnerable(invulnerability_s if invulnerability_s >= 0.0 else default_invulnerability_seconds())
	knocked_back.emit(push)


## apply_knockback() with the push direction taken from a source position (e.g. the monster's).
func apply_knockback_from_point(source_pos: Vector3, strength: float = 1.0, invulnerability_s: float = -1.0) -> void:
	apply_knockback(global_position - source_pos, strength, invulnerability_s)


## Starts (or extends) invulnerability for `seconds`.
func set_invulnerable(seconds: float) -> void:
	_invuln = maxf(_invuln, seconds)


func is_invulnerable() -> bool:
	return _invuln > 0.0


## Seconds of invulnerability left.
func invulnerable_time_left() -> float:
	return maxf(_invuln, 0.0)


## Post-hit invincibility in seconds, resolved by MovementModel from the combat data: the isometric override in
## data/misostory/combat.json (post_hit_invincibility.override_s) when set, else MeowDB's canonical value
## (formulas/accuracy.json after_hit.post_hit_invincibility_s, 1.5 s).
func default_invulnerability_seconds() -> float:
	return model.default_invulnerability if model != null else 0.0


## Enters the death state: input disabled, horizontal motion stopped, off any ladder or chair; gravity still applies.
func die() -> void:
	if _dead:
		return
	stand_up(&"death")
	_dead = true
	if state == State.CLIMB:
		_leave_climb(&"death")
	move_velocity = Vector3.ZERO
	in_hitstun = false
	_hitstun_t = 0.0
	_jump_buffer = 0.0
	died.emit()


## Leaves the death state (after the respawn transition placed the player).
func revive() -> void:
	if not _dead:
		return
	_dead = false
	_invuln = 0.0
	revived.emit()


## Enables or disables player intent (dialogue windows, transitions). Physics keeps running.
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled:
		_jump_buffer = 0.0


func set_input_source(source: InputSource) -> void:
	input_source = source if source != null else KeyboardInput.new()


## Applies the character's total Speed and Jump.
func set_stats(speed: float, jump: float) -> void:
	if model != null:
		model.set_stats(speed, jump)


## Reads total Speed/Jump through StatCalculator (falls back to the canonical base 100 while the calculator does
## not provide them).
func refresh_stats(character: CharacterState, db: ContentDB) -> void:
	if model == null or character == null or db == null:
		return
	var snap: Dictionary = StatCalculator.snapshot(character, db)
	set_stats(float(snap.get("speed", model.base_speed())), float(snap.get("jump", model.base_jump())))


## Sets the camera's ground-projected axes (CameraRig calls this; W walks along `forward`).
func set_view_axes(right: Vector3, forward: Vector3) -> void:
	var r := Vector3(right.x, 0.0, right.z)
	var f := Vector3(forward.x, 0.0, forward.z)
	if r.length_squared() > 0.0001 and f.length_squared() > 0.0001:
		view_right = r.normalized()
		view_forward = f.normalized()


func set_climbables(list: Array[ClimbableDef]) -> void:
	climbables = list


## Appends the climbables of one sidecar (`<chunk>.json` climbables[]).
func add_climbables_from_sidecar(entries: Array) -> void:
	climbables.append_array(ClimbableDef.list_from_sidecar(entries))


## The point the camera follows: feet x/z, and the ground height while airborne (jumps never bob the camera;
## falling below the last ground height is followed immediately). After a ladder-top exit, which moves the body onto
## top_exit in one tick, the x/z glide from the climbing spot to the feet at walking speed, so the camera follows the
## exit as if the player had walked onto the top.
func follow_anchor() -> Vector3:
	return Vector3(global_position.x + _follow_glide.x, _anchor_y, global_position.z + _follow_glide.z)


## Grabs `c` directly (tests, scripted sequences). at_top starts at the top, as when pressing Down at a ladder top.
func grab_climbable(c: ClimbableDef, at_top: bool = false) -> bool:
	if c == null or _dead or model == null:
		return false
	stand_up(&"climb")
	var high := maxf(c.bottom.y, c.top.y - model.climb_exit_below_top - 0.05)
	var y := maxf(c.bottom.y, c.top.y - model.body_height * 0.6) if at_top else clampf(global_position.y, c.bottom.y, high)
	_start_climb(c, y)
	return true


## The climbable the player could grab right now with interact/Up/Down (null if none). Useful for prompts.
func grabbable_climbable() -> ClimbableDef:
	var c := _find_climbable(true, false)
	return c if c != null else _find_climbable(false, true)


# =================================================================================================================
# Tick
# =================================================================================================================

## One tick of player intent, after input gating (dead, disabled, hit-stun read as no input).
class Intent:
	var wish: Vector3 = Vector3.ZERO
	var jump_pressed: bool = false
	var jump_held: bool = false
	var climb_axis: float = 0.0
	var grab_up: bool = false
	var grab_up_held: bool = false
	var grab_down: bool = false
	var interact: bool = false
	## The sit key (X) went down.
	var sit: bool = false


func _read_intent() -> Intent:
	var i := Intent.new()
	if _dead or not _input_enabled or in_hitstun:
		return i
	i.wish = input_source.world_move(view_right, view_forward)
	i.jump_pressed = input_source.just_pressed(&"jump")
	i.jump_held = input_source.is_held(&"jump")
	i.climb_axis = input_source.climb_axis()
	i.grab_up = input_source.just_pressed(&"portal_enter")
	i.grab_up_held = input_source.is_held(&"portal_enter")
	i.grab_down = input_source.just_pressed(&"climb_down")
	i.interact = input_source.just_pressed(&"interact")
	i.sit = input_source.just_pressed(&"sit")
	return i


## One seated tick: what stands the player up. A move, jump or sit press does nothing else this tick. An attack is
## PlayerCombat's (it runs after this body and filters the mouse: a click on a window, such as the double-click on the
## chair, is never an attack): once it attacks, or a skill casts, PlayerCombat is attacking and the player stands up.
func _step_seated(intent: Intent) -> void:
	if intent.sit:
		stand_up(&"sit_key")
	elif intent.jump_pressed:
		stand_up(&"jump")
	elif intent.wish.length_squared() > 0.0001:
		stand_up(&"move")
	elif _combat_attacking():
		stand_up(&"attack")


func _tick_timers(delta: float) -> void:
	_coyote = maxf(_coyote - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_invuln = maxf(_invuln - delta, 0.0)
	_regrab_cooldown = maxf(_regrab_cooldown - delta, 0.0)
	_follow_glide = _follow_glide.move_toward(Vector3.ZERO, model.walk_speed * delta)
	if in_hitstun:
		_hitstun_t -= delta
		if _hitstun_t <= 0.0:
			in_hitstun = false
	safe_ground.tick()
	if model.visual_step_smoothing > 0.0 and presentation_offset != Vector3.ZERO:
		presentation_offset *= exp(-delta / (model.visual_step_smoothing / 3.0))
		if presentation_offset.length() < 0.002:
			presentation_offset = Vector3.ZERO
	else:
		presentation_offset = Vector3.ZERO


func _step_move(delta: float, intent: Intent) -> void:
	if intent.jump_pressed:
		_jump_buffer = model.jump_buffer
	if not intent.jump_held:
		_jump_released_since_jump = true
	# Grab a ladder/rope: Up (portal_enter) or interact near its line, Down (climb_down) or interact near its
	# top, or Up held while airborne (catching a rope mid-jump, as in classic).
	if _regrab_cooldown <= 0.0 and not in_hitstun:
		var c: ClimbableDef = null
		var at_top := false
		if intent.grab_up or intent.interact or (intent.grab_up_held and state == State.AIR):
			c = _find_climbable(true, false)
		if c == null and (intent.grab_down or intent.interact):
			c = _find_climbable(false, true)
			at_top = c != null
		if c != null:
			grab_climbable(c, at_top)
			return
	var grounded := state == State.GROUND
	# Horizontal: immediate on the ground, momentum + limited steering in the air, frozen during hit-stun.
	var target := intent.wish * model.walk_speed
	if grounded:
		var stopping := target.length_squared() < 0.0001 or target.dot(move_velocity) < 0.0
		move_velocity = move_velocity.move_toward(target, (model.ground_decel if stopping else model.ground_accel) * delta)
	elif not in_hitstun and target.length_squared() > 0.0001:
		move_velocity = move_velocity.move_toward(target, model.air_accel * delta)
	if intent.wish.length_squared() > 0.01:
		facing = intent.wish.normalized()
	# Jump: buffered press, coyote time after walking off an edge, or (classic) hold to keep hopping.
	var can_jump := not in_hitstun and not _dead and (grounded or _coyote > 0.0)
	var rejump := model.hold_to_rejump and intent.jump_held and grounded and _grounded_ticks >= 1 and not _jump_released_since_jump
	if can_jump and (_jump_buffer > 0.0 or rejump):
		vertical_speed = model.jump_velocity
		state = State.AIR
		grounded = false
		_coyote = 0.0
		_jump_buffer = 0.0
		_grounded_ticks = 0
		_jump_released_since_jump = false
		jumped.emit()
	if grounded:
		_ground_move(delta)
	else:
		_air_move(delta)


func _post_step(delta: float, start_pos: Vector3) -> void:
	var moved := global_position - start_pos
	actual_velocity = Vector3(moved.x, 0.0, moved.z) / delta
	if state == State.GROUND:
		_grounded_ticks += 1
		_coyote = model.coyote_time
		_wedge_ticks = 0
		_anchor_y = global_position.y
		# Wedged ground is not walkable floor (MAP_ARCHITECTURE section 4.6): never a recovery or save point.
		if not in_hitstun and not _dead and not _wedged and _safe_ground_ok():
			safe_ground.record(global_position, floor_normal, _floor_collider_id, facing)
	elif state == State.CLIMB:
		_anchor_y = global_position.y
	else:
		_grounded_ticks = 0
		_anchor_y = minf(_anchor_y, global_position.y)
		if global_position.y < kill_y and not _fell_reported:
			_fell_reported = true
			fell_out_of_world.emit(global_position)
	velocity = move_velocity + Vector3.UP * vertical_speed


func _safe_ground_ok() -> bool:
	if not safe_ground_filter.is_valid():
		return true
	if safe_ground_filter.get_argument_count() >= 2:
		return bool(safe_ground_filter.call(global_position, _floor_collider))
	return bool(safe_ground_filter.call(global_position))


# --- grounded movement -------------------------------------------------------------------------------------------

func _ground_move(delta: float) -> void:
	var start := global_position
	var h := move_velocity * delta
	if h.length_squared() > 1e-10:
		_slide(h, true)
	# The feet follow the ground: up steps/ledges within step_up, down stairs/ramps within snap_down.
	var g := _sense_ground(global_position.y + model.step_up, global_position.y - model.snap_down)
	if g == null:
		if _wedged and _capsule_supported():
			return  # still wedged: stay grounded where the capsule rests (jump or walk out)
		_wedged = false
		state = State.AIR
		vertical_speed = 0.0
		_coyote = model.coyote_time
		return
	_wedged = false
	if not _lift_feet_to(g.y):
		# Something overhead keeps the body from rising onto that step: stay where we were.
		global_position = start
		var back := _sense_ground(start.y + model.step_up, start.y - model.snap_down)
		if back != null:
			_lift_feet_to(back.y)
			_apply_ground(back)
		return
	_apply_ground(g)


## Collide-and-slide of the body capsule. While `grounded`, every contact acts as a vertical wall (the capsule
## starts at step height, so anything it touches is too tall to walk onto); ceilings only stop upward motion.
## Returns true if a wall blocked the motion.
func _slide(motion: Vector3, grounded: bool) -> bool:
	var remaining := motion
	var blocked := false
	var planes: Array[Vector3] = []
	for _i in MAX_SLIDES:
		if remaining.length_squared() < 1e-10:
			break
		var col := move_and_collide(remaining, false, safe_margin, false, 4)
		if col == null:
			break
		remaining = col.get_remainder()
		for k in col.get_collision_count():
			var n := col.get_normal(k)
			var plane := n
			if grounded:
				plane = Vector3(n.x, 0.0, n.z)
				if plane.length_squared() < 0.0025:
					remaining.y = minf(remaining.y, 0.0) if n.y < 0.0 else remaining.y
					continue
				plane = plane.normalized()
				blocked = true
			remaining = _clip(remaining, plane, planes)
			planes.append(plane)
	return blocked


## Removes the part of `v` going into `plane`; along a crease with an earlier plane when both oppose it.
func _clip(v: Vector3, plane: Vector3, planes: Array[Vector3]) -> Vector3:
	var out := v.slide(plane) if v.dot(plane) < 0.0 else v
	for p in planes:
		if out.dot(p) < -1e-6 and not p.is_equal_approx(plane):
			var crease := p.cross(plane)
			if crease.length_squared() < 1e-6:
				return Vector3.ZERO
			crease = crease.normalized()
			out = crease * out.dot(crease)
	return out


# --- airborne movement -------------------------------------------------------------------------------------------

func _air_move(delta: float) -> void:
	var v0 := vertical_speed
	vertical_speed = maxf(vertical_speed - model.gravity * delta, -model.max_fall_speed)
	# Exact for constant acceleration: samples the true parabola, so the apex is hit within a millimetre.
	var dy := (v0 + vertical_speed) * 0.5 * delta
	var start_y := global_position.y
	var impact_speed := -vertical_speed
	var remaining := move_velocity * delta + Vector3.UP * dy
	var planes: Array[Vector3] = []
	for _i in MAX_SLIDES:
		if remaining.length_squared() < 1e-10:
			break
		var col := move_and_collide(remaining, false, safe_margin, false, 4)
		if col == null:
			break
		remaining = col.get_remainder()
		for k in col.get_collision_count():
			var n := col.get_normal(k)
			if n.y < -0.3 and vertical_speed > 0.0:
				vertical_speed = 0.0
			# A walkable contact on the capsule alone is not a landing: only the feet stand (classic: you land when
			# your feet are over the foothold). A capsule resting on a ledge edge outside the feet disc slides off
			# along the contact; one that truly rests (wedged) becomes ground through the wedge rule below.
			var nh := Vector3(n.x, 0.0, n.z)
			if nh.length_squared() > 0.0001 and not _is_floor(n):
				# Walls and steep slopes absorb the horizontal velocity pushing into them (no climbing them by
				# sliding, no sticking); walkable surfaces under the capsule keep it.
				nh = nh.normalized()
				var into := move_velocity.dot(nh)
				if into < 0.0:
					move_velocity -= nh * into
			remaining = _clip(remaining, n, planes)
			planes.append(n)
	if vertical_speed > 0.0:
		return
	var feet := global_position.y
	var g := _sense_ground(feet + model.step_up + RAY_HEADROOM, feet - 0.01)
	var wedged := false
	if g == null:
		# Resting on the capsule without falling (wedged between steep faces): accept it as ground, where the body
		# rests (no lift), after a while. _ground_move keeps it latched while the capsule stays supported.
		if global_position.y > start_y + dy * 0.1 - 0.0005 and dy < -0.001:
			_wedge_ticks += 1
			if _wedge_ticks >= WEDGE_TICKS:
				g = GroundHit.new()
				g.y = global_position.y
				g.normal = Vector3.UP
				g.offset = _support_offset
				wedged = true
		else:
			_wedge_ticks = 0
	if g == null:
		return
	if not _lift_feet_to(g.y):
		return
	_apply_ground(g)
	_enter_ground()
	_wedged = wedged
	landed.emit(maxf(impact_speed, 0.0))


func _enter_ground() -> void:
	state = State.GROUND
	vertical_speed = 0.0
	_wedge_ticks = 0
	_wedged = false
	if in_hitstun:
		in_hitstun = false
		_hitstun_t = 0.0
		move_velocity = Vector3.ZERO


# --- the feet: ground sensing ------------------------------------------------------------------------------------

## A walkable surface found under the feet disc.
class GroundHit:
	var y: float = 0.0
	var offset: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP
	var collider: Object = null
	var collider_id: int = 0


func _is_floor(n: Vector3) -> bool:
	return n.y > 0.0 and n.angle_to(Vector3.UP) <= model.floor_max_angle + 0.001


## The highest walkable surface under the feet disc with top_y >= y >= bottom_y (null if none). Rays start a
## little above top_y so a surface exactly at top_y is found; steep hits are ignored.
func _sense_ground(top_y: float, bottom_y: float) -> GroundHit:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return null
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
		_ray.hit_back_faces = false
		_ray.hit_from_inside = false
	_ray.exclude = [get_rid()]
	_ray.collision_mask = collision_mask
	if _foot_offsets.is_empty():
		_build_foot_offsets()
	var best: GroundHit = null
	var p := global_position
	for off in _foot_offsets:
		_ray.from = Vector3(p.x + off.x, top_y + RAY_HEADROOM, p.z + off.z)
		_ray.to = Vector3(p.x + off.x, bottom_y, p.z + off.z)
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if not _is_floor(n):
			continue
		var y: float = (hit["position"] as Vector3).y
		if y > top_y + 0.0005:
			continue
		var centre := off == Vector3.ZERO
		if best == null or y > best.y + 0.002 or (centre and y > best.y - 0.002):
			best = GroundHit.new()
			best.y = y
			best.offset = off
			best.normal = n
			best.collider = hit.get("collider")
			best.collider_id = int(hit.get("collider_id", 0))
	return best


func _build_foot_offsets() -> void:
	_foot_offsets = PackedVector3Array([Vector3.ZERO])
	for i in 8:
		var a := TAU * i / 8.0
		_foot_offsets.append(Vector3(cos(a), 0.0, sin(a)) * model.foot_radius)


## Moves the feet to height y: upward through the body capsule (so a ceiling stops it; returns false when
## blocked), downward directly (the capsule sits a full step above the feet, so a drop of at most snap_down
## cannot push it into anything it was not already clear of).
func _lift_feet_to(y: float) -> bool:
	var dy := y - global_position.y
	if dy > 0.0005:
		var from := global_position.y
		move_and_collide(Vector3.UP * dy, false, safe_margin)
		if global_position.y < y - 0.01:
			global_position.y = from
			return false
		global_position.y = y
	elif dy < -0.0005:
		global_position.y = y
	_note_vertical_snap(dy)
	return true


func _apply_ground(g: GroundHit) -> void:
	floor_normal = g.normal
	_support_offset = g.offset
	_floor_collider = g.collider
	_floor_collider_id = g.collider_id


## Teleport settle: stand on ground within `depth` below (or step_up above) the current point.
func _settle(depth: float) -> void:
	var g := _sense_ground(global_position.y + model.step_up, global_position.y - depth)
	if g != null:
		global_position.y = g.y
		_apply_ground(g)
		_enter_ground()


## True while the body capsule rests on something (a short downward test move collides): keeps wedged ground.
func _capsule_supported() -> bool:
	return test_move(global_transform, Vector3.DOWN * WEDGE_SUPPORT_PROBE, null, safe_margin)


func _note_vertical_snap(dy: float) -> void:
	if absf(dy) > 0.03:
		presentation_offset.y -= dy


# --- climbing ----------------------------------------------------------------------------------------------------

func _find_climbable(from_line: bool, from_top: bool) -> ClimbableDef:
	var best: ClimbableDef = null
	var best_d := INF
	var feet := global_position
	for c in climbables:
		if from_line:
			var d := c.line_distance_xz(feet)
			if d > model.climb_grab_radius:
				continue
			if feet.y < c.bottom.y - 0.6 or feet.y > c.top.y - model.climb_exit_below_top - 0.05:
				continue
			if c.descend_only and state != State.AIR:
				continue
			if d < best_d:
				best_d = d
				best = c
		if from_top:
			var dt := minf(c.top_exit_distance_xz(feet), c.line_distance_xz(feet))
			if dt > model.climb_top_grab_radius or absf(feet.y - c.top.y) > 0.6:
				continue
			if dt < best_d:
				best_d = dt
				best = c
	return best


func _start_climb(c: ClimbableDef, y: float) -> void:
	var before := global_position
	current_climbable = c
	state = State.CLIMB
	move_velocity = Vector3.ZERO
	vertical_speed = 0.0
	_jump_buffer = 0.0
	_coyote = 0.0
	facing = c.facing
	global_position = c.climb_position(y, model.climb_standoff)
	presentation_offset += before - global_position
	climb_started.emit(c)


func _step_climb(delta: float, intent: Intent) -> void:
	var c := current_climbable
	if c == null:
		state = State.AIR
		return
	# Jump off sideways: jump plus a direction that is not into the wall (classic: jump alone does nothing).
	if intent.jump_pressed and intent.wish.length_squared() > 0.09 and intent.wish.normalized().dot(c.facing) < 0.5:
		_leave_climb(&"jump")
		facing = intent.wish.normalized()
		move_velocity = intent.wish.normalized() * model.walk_speed
		vertical_speed = model.climb_jump_off_velocity
		jumped.emit()
		return
	var axis := intent.climb_axis
	if c.descend_only:
		axis = minf(axis, 0.0)
	var y := global_position.y + axis * model.climb_speed * delta
	if axis > 0.0 and y >= c.top.y - model.climb_exit_below_top:
		# Over the top: step onto the probed standing point of the upper cap.
		var before := global_position
		current_climbable = null
		global_position = c.top_exit
		state = State.AIR
		_settle(0.6)
		presentation_offset += before - global_position
		# The camera glides over the same step (follow_anchor()); the body is already where it ends.
		_follow_glide += Vector3(before.x - global_position.x, 0.0, before.z - global_position.z)
		climb_ended.emit(c, &"top")
		return
	if axis < 0.0 and y <= c.bottom.y:
		# At the foot: stand on the ground there, or let go over a pit (no foot_ground).
		current_climbable = null
		global_position = c.climb_position(c.bottom.y, model.climb_standoff)
		state = State.AIR
		vertical_speed = 0.0
		_regrab_cooldown = model.climb_regrab_cooldown
		if c.has_foot_ground:
			_settle(0.6)
		climb_ended.emit(c, &"bottom")
		return
	global_position = c.climb_position(y, model.climb_standoff)
	facing = c.facing


func _leave_climb(how: StringName) -> void:
	var c := current_climbable
	current_climbable = null
	state = State.AIR
	vertical_speed = 0.0
	_regrab_cooldown = model.climb_regrab_cooldown if model != null else 0.3
	if c != null:
		climb_ended.emit(c, how)


# =================================================================================================================
# Engine glue
# =================================================================================================================

## The body capsule (step_up .. body_height) and the disabled floor sensor used by _sync_engine_floor_state().
func _configure_shapes() -> void:
	if model == null:
		return
	_body_shape = get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if _body_shape == null:
		_body_shape = CollisionShape3D.new()
		_body_shape.name = "CollisionShape3D"
		add_child(_body_shape)
	var cap := _body_shape.shape as CapsuleShape3D
	if cap == null:
		cap = CapsuleShape3D.new()
	else:
		cap = cap.duplicate() as CapsuleShape3D
	cap.radius = model.body_radius
	cap.height = maxf(model.body_height - model.step_up, model.body_radius * 2.0)
	_body_shape.shape = cap
	_body_shape.position = Vector3(0.0, model.body_height - cap.height * 0.5, 0.0)
	_body_shape.rotation = Vector3.ZERO
	_floor_sensor = get_node_or_null(^"FloorSensor") as CollisionShape3D
	if _floor_sensor == null:
		_floor_sensor = CollisionShape3D.new()
		_floor_sensor.name = "FloorSensor"
		add_child(_floor_sensor)
	# A tiny sphere placed (each sync) right above the feet ray that found the floor: it lands on exactly the face
	# that ray validated as walkable and reads that face's normal. A shape the size of the feet meets stair
	# nosings (45 degree chamfers) and the gaps between planks, and reports no floor there.
	var sensor := SphereShape3D.new()
	sensor.radius = FLOOR_SENSOR_RADIUS
	_floor_sensor.shape = sensor
	_floor_sensor.position = Vector3(0.0, FLOOR_SENSOR_RADIUS + 0.015, 0.0)
	_floor_sensor.disabled = true
	floor_max_angle = model.floor_max_angle
	floor_snap_length = 0.0
	floor_stop_on_slope = true
	floor_block_on_wall = false
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	_build_foot_offsets()


## Keeps CharacterBody3D.is_on_floor() (which other systems call) in step with this controller's floor state.
## Only inside a physics frame: move_and_slide() divides by the engine delta. A tiny sphere over the supporting
## feet ray replaces the capsule for one short straight-down move_and_slide(), then the position, velocity and
## shapes are restored.
func _sync_engine_floor_state(delta: float) -> void:
	if not Engine.is_in_physics_frame() or delta <= 0.0 or _floor_sensor == null or _body_shape == null:
		return
	var keep := velocity
	var before := global_position
	# Wedged ground has no walkable floor under the feet: is_on_floor() stays false there (is_grounded() is true
	# so the player can still jump out).
	if state == State.GROUND and not _wedged:
		_floor_sensor.position = _support_offset + Vector3.UP * (FLOOR_SENSOR_RADIUS + 0.015)
		_body_shape.disabled = true
		_floor_sensor.disabled = false
		velocity = Vector3.DOWN * (0.06 / delta)
	else:
		velocity = Vector3.UP * (0.0001 / delta)
	move_and_slide()
	_floor_sensor.disabled = true
	_body_shape.disabled = false
	global_position = before
	velocity = keep


func _data_db() -> ContentDB:
	var data := _autoload(&"Data")
	if data != null and data.get("db") is ContentDB:
		return data.get("db")
	return null


func _autoload(autoload_name: StringName) -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null(NodePath(String(autoload_name)))


func _connect_autoloads() -> void:
	var events := _autoload(&"Events")
	if events != null:
		if events.has_signal(&"stats_changed"):
			events.connect(&"stats_changed", _on_stats_changed)
		if events.has_signal(&"player_died"):
			events.connect(&"player_died", func(_map_id: String) -> void: die())
		if events.has_signal(&"player_respawned"):
			events.connect(&"player_respawned", func(_map_id: String) -> void: revive())
		if events.has_signal(&"item_lost"):
			events.connect(&"item_lost", _on_item_lost)
	# Map-transition safety (contract C5): a warp stands the player up before its fade starts; teleport() does it again
	# on arrival, and a replaced character (load, new game) never inherits the old one's seat.
	var session := _autoload(&"MapSession")
	if session != null and session.has_signal(&"transition_started"):
		session.connect(&"transition_started", func(_req: Variant) -> void: stand_up(&"warp"))
	var game := _autoload(&"Game")
	if game != null and game.has_signal(&"character_replaced"):
		game.connect(&"character_replaced", func(_reason: String) -> void: stand_up(&"character"))
	_on_stats_changed()


## Selling, dropping or handing in the last copy of the chair the player sits on stands it up.
func _on_item_lost(item_id: String, _qty: int) -> void:
	if not is_seated() or item_id != seated_chair:
		return
	var c := _chair_character()
	if c == null or c.inventory.count(item_id) <= 0:
		stand_up(&"chair_lost")


## True while PlayerCombat (child "PlayerCombat", added by MonsterSystem) is in a basic attack's or a skill cast's
## lockout (PlayerCombat.is_attacking()).
func _combat_attacking() -> bool:
	var pc := get_node_or_null(^"PlayerCombat")
	return pc != null and pc.has_method("is_attacking") and bool(pc.call("is_attacking"))


## The character whose chairs the sit key uses: chair_owner, else Game.character.
func _chair_character() -> CharacterState:
	if chair_owner != null:
		return chair_owner
	var game := _autoload(&"Game")
	return game.get("character") as CharacterState if game != null and game.get("character") is CharacterState else null


## Emits `sig` on the Events autoload (only the live player, use_autoloads, talks to the bus).
func _emit_event(sig: StringName, args: Array = []) -> void:
	if not use_autoloads:
		return
	var events := _autoload(&"Events")
	if events != null and events.has_signal(sig):
		events.callv(&"emit_signal", [sig] + args)


func _on_stats_changed() -> void:
	var game := _autoload(&"Game")
	if game != null and game.get("character") is CharacterState:
		refresh_stats(game.get("character"), _data_db())
