class_name MovementModel
extends RefCounted
## Every number the player controller moves by, in meters and seconds. Pure: no scene tree, no autoloads.
##
## Canonical inputs come from MeowDB (data/canonical/formulas/movement.json) and are converted only through
## WorldScale: walk/climb speed (px/s) with WorldScale.h, jump heights and the knockback arc with WorldScale.v.
## Feel values MeowDB does not publish (acceleration, air control, step height, coyote time ...) come from
## data/misostory/movement.json, each with a reason there. Build it with from_db(); set_stats() recomputes the
## stat-dependent values (Speed and Jump) without reloading anything.

## The canonical record (formulas/movement) and the adaptation table (misostory/movement), kept for reference.
var canonical: Dictionary = {}
var tuning: Dictionary = {}

# --- stat-dependent (set_stats) ----------------------------------------------------------------------------
## Total Speed and Jump stats currently applied (clamped to the canonical caps).
var speed_stat: float = 100.0
var jump_stat: float = 100.0
## Ground speed in m/s (canonical walk speed px/s x WorldScale.h).
var walk_speed: float = 0.0
## Ladder/rope speed in m/s (canonical climb speed px/s; vertical, so x WorldScale.v).
var climb_speed: float = 0.0
## Jump apex above the take-off point in meters (canonical jump table px x WorldScale.v).
var jump_apex: float = 0.0
## Launch speed in m/s that reaches jump_apex under gravity.
var jump_velocity: float = 0.0

# --- constant for a session ---------------------------------------------------------------------------------
## m/s^2, MeowDB's knockback-model gravity (2000 px/s^2) x WorldScale.v; used for jumps, falls and knockback.
var gravity: float = 0.0
## m/s upward launch of a knockback (MeowDB 270 px/s x WorldScale.v).
var knockback_up_speed: float = 0.0
var knockback_speed: float = 0.0
var knockback_max_hitstun: float = 0.0
## m, horizontal: a knockback source this close to the player pushes it backwards from its facing (#17).
var knockback_point_blank: float = 0.0
## Post-hit invincibility (s): combat.json override, else canonical accuracy.after_hit (set by from_db()).
var default_invulnerability: float = 0.0
var max_fall_speed: float = 0.0
var ground_accel: float = 0.0
var ground_decel: float = 0.0
var air_accel: float = 0.0
var coyote_time: float = 0.0
var jump_buffer: float = 0.0
var hold_to_rejump: bool = true
var step_up: float = 0.0
var snap_down: float = 0.0
var floor_max_angle: float = 0.0
var teleport_settle: float = 0.0
var body_height: float = 1.5
var body_radius: float = 0.3
## Radius of the ray disc that senses the ground under the feet.
var foot_radius: float = 0.15
var climb_grab_radius: float = 0.0
var climb_top_grab_radius: float = 0.0
var climb_standoff: float = 0.0
var climb_exit_below_top: float = 0.0
var climb_jump_off_velocity: float = 0.0
var climb_regrab_cooldown: float = 0.0
var visual_step_smoothing: float = 0.0
var facing_turn_rate: float = 0.0

## Missing canonical keys already reported (one error per key, not one per call).
var _reported: Dictionary = {}


## Builds the model from a loaded ContentDB (Data.db at runtime, TestCase.db() in tests). Speed/Jump start at
## the canonical base (100); call set_stats() with the character's totals.
static func from_db(db: ContentDB) -> MovementModel:
	var tuning_table: Variant = db.miso_table("movement")
	var m := from_tables(db.formula("movement"), tuning_table if tuning_table is Dictionary else {})
	var combat: Variant = db.miso_table("combat")
	m.default_invulnerability = post_hit_invincibility(db.formula("accuracy"), combat if combat is Dictionary else {})
	return m


## Post-hit invincibility (s). The duration belongs to the combat data: data/misostory/combat.json
## post_hit_invincibility.override_s when it is set, else MeowDB's canonical formulas/accuracy.json
## after_hit.post_hit_invincibility_s. 0 (with an error) when neither exists.
static func post_hit_invincibility(canonical_accuracy: Dictionary, combat: Dictionary) -> float:
	var block: Variant = combat.get("post_hit_invincibility")
	if block is Dictionary and (block as Dictionary).get("override_s") != null:
		return float(block["override_s"])
	var after_hit: Variant = canonical_accuracy.get("after_hit")
	if after_hit is Dictionary and (after_hit as Dictionary).has("post_hit_invincibility_s"):
		return float(after_hit["post_hit_invincibility_s"])
	push_error("[MovementModel] no post-hit invincibility in combat.json or canonical accuracy.after_hit")
	return 0.0


## Same as from_db() but from the raw tables (tests can pass edited copies).
static func from_tables(canonical_movement: Dictionary, movement_tuning: Dictionary) -> MovementModel:
	var m := MovementModel.new()
	m.canonical = canonical_movement
	m.tuning = movement_tuning
	m._load_constants()
	m.set_stats(m.base_speed(), m.base_jump())
	return m


func _num(key: String, fallback: float) -> float:
	if not tuning.has(key):
		push_error("[MovementModel] data/misostory/movement.json has no '%s'" % key)
		return fallback
	return float(tuning[key])


func _load_constants() -> void:
	var kb: Dictionary = canonical.get("knockback_airtime", {})
	gravity = WorldScale.v(float(kb.get("gravity_px_per_s2", 0.0)))
	knockback_up_speed = WorldScale.v(float(kb.get("upward_speed_px_per_s", 0.0)))
	if gravity <= 0.0:
		push_error("[MovementModel] canonical movement.knockback_airtime.gravity_px_per_s2 missing")
	knockback_speed = _num("knockback_horizontal_speed_mps", 2.0)
	knockback_max_hitstun = _num("knockback_max_hitstun_s", 0.6)
	knockback_point_blank = _num("knockback_point_blank_m", 0.05)
	max_fall_speed = _num("max_fall_speed_mps", 12.0)
	ground_accel = _num("ground_accel_mps2", 60.0)
	ground_decel = _num("ground_decel_mps2", 90.0)
	air_accel = _num("air_accel_mps2", 6.0)
	coyote_time = _num("coyote_time_s", 0.08)
	jump_buffer = _num("jump_buffer_s", 0.12)
	hold_to_rejump = bool(tuning.get("hold_to_rejump", true))
	step_up = _num("step_up_m", 0.45)
	snap_down = _num("snap_down_m", step_up)
	floor_max_angle = deg_to_rad(_num("floor_max_angle_deg", 38.0))
	teleport_settle = _num("teleport_settle_m", 0.6)
	body_height = _num("body_height_m", 1.5)
	body_radius = _num("body_radius_m", 0.3)
	foot_radius = _num("foot_radius_m", 0.15)
	climb_grab_radius = _num("climb_grab_radius_m", 0.8)
	climb_top_grab_radius = _num("climb_top_grab_radius_m", 0.9)
	climb_standoff = _num("climb_standoff_m", 0.3)
	climb_exit_below_top = _num("climb_exit_below_top_m", 0.25)
	climb_regrab_cooldown = _num("climb_regrab_cooldown_s", 0.35)
	visual_step_smoothing = _num("visual_step_smoothing_s", 0.08)
	facing_turn_rate = deg_to_rad(_num("facing_turn_rate_deg_per_s", 1440.0))


## Applies the character's total Speed and Jump (StatCalculator totals). Values are clamped to the canonical
## caps (Speed 140, Jump 120); MeowDB: "Speed above 140 does nothing".
func set_stats(speed: float, jump: float) -> void:
	speed_stat = minf(speed, speed_cap())
	jump_stat = clampf(jump, _jump_table_min(), jump_cap())
	walk_speed = WorldScale.h(walk_px_per_s(speed_stat))
	climb_speed = WorldScale.v(climb_px_per_s(speed_stat))
	jump_apex = WorldScale.v(jump_height_px(jump_stat))
	jump_velocity = sqrt(2.0 * gravity * jump_apex) if gravity > 0.0 else 0.0
	var fraction := _num("climb_jump_off_apex_fraction", 0.5)
	climb_jump_off_velocity = sqrt(2.0 * gravity * jump_apex * fraction) if gravity > 0.0 else 0.0


# --- canonical formulas (px) --------------------------------------------------------------------------------

## Canonical stat constants are read from data only (no canonical number is restated in code); a missing key is
## reported once and reads as 0, which zeroes the dependent speeds instead of inventing a value.
func base_speed() -> float:
	return _canon_num("base_speed")


func base_jump() -> float:
	return _canon_num("base_jump")


func speed_cap() -> float:
	return _canon_num("speed_cap")


func jump_cap() -> float:
	return _canon_num("jump_cap")


func _canon_num(key: String) -> float:
	if not canonical.has(key) or canonical[key] == null:
		if not _reported.has(key):
			_reported[key] = true
			push_error("[MovementModel] data/canonical/formulas/movement.json has no '%s'" % key)
		return 0.0
	return float(canonical[key])


## Slope of MeowDB's walk line in px/s per Speed point (published base and cap points); 0 if the data is missing.
func _walk_slope() -> float:
	var ws: Dictionary = canonical.get("walk_speed", {})
	var span := speed_cap() - base_speed()
	if span <= 0.0:
		return 0.0
	return (float(ws.get("cap_px_per_s", 0.0)) - float(ws.get("base_px_per_s", 0.0))) / span


## Walk speed in px/s for a total Speed stat. MeowDB publishes the base (Speed 100 -> 150 px/s) and the cap
## (Speed 140 -> 200 px/s) of a linear formula ("125 x (Speed + 20) / 100"); the line through those two
## published points is that formula, so no constant of it is restated in code.
func walk_px_per_s(speed: float) -> float:
	var ws: Dictionary = canonical.get("walk_speed", {})
	var base_px := float(ws.get("base_px_per_s", 0.0))
	return maxf(0.0, base_px + _walk_slope() * (minf(speed, speed_cap()) - base_speed()))


## Climb speed in px/s. MeowDB: "Climb speed = Speed + 20 px/s" (120 at Speed 100). It scales with the same
## hidden Speed offset as walking; the offset is recovered from the walk line (base_px / slope - base_speed).
func climb_px_per_s(speed: float) -> float:
	var ws: Dictionary = canonical.get("walk_speed", {})
	var cs: Dictionary = canonical.get("climb_speed", {})
	var climb_base := float(cs.get("base_px_per_s", 0.0))
	var slope := _walk_slope()
	if slope <= 0.0:
		return climb_base
	var offset := float(ws.get("base_px_per_s", 0.0)) / slope - base_speed()
	if base_speed() + offset <= 0.0:
		return climb_base
	var s := minf(speed, speed_cap())
	return maxf(0.0, climb_base * (s + offset) / (base_speed() + offset))


## Jump apex in px for a total Jump stat: piecewise-linear in MeowDB's jump_height_px_by_jump table, clamped
## to the table's range (Jump 100..120).
func jump_height_px(jump: float) -> float:
	var rows: Array = canonical.get("jump_height_px_by_jump", [])
	if rows.is_empty():
		return 0.0
	var j := clampf(jump, float(rows[0].get("jump", 0)), float(rows[-1].get("jump", 0)))
	for i in range(1, rows.size()):
		var a: Dictionary = rows[i - 1]
		var b: Dictionary = rows[i]
		var ja := float(a.get("jump", 0))
		var jb := float(b.get("jump", 0))
		if j <= jb:
			var t := 0.0 if jb == ja else (j - ja) / (jb - ja)
			return lerpf(float(a.get("height_px", 0)), float(b.get("height_px", 0)), t)
	return float(rows[-1].get("height_px", 0))


func _jump_table_min() -> float:
	var rows: Array = canonical.get("jump_height_px_by_jump", [])
	return float(rows[0].get("jump", base_jump())) if not rows.is_empty() else base_jump()


## Same-height airtime of a full jump in seconds (2 v / g).
func jump_airtime() -> float:
	return 2.0 * jump_velocity / gravity if gravity > 0.0 else 0.0


## The apex at the Jump cap in meters (what MAP_ARCHITECTURE calls jump_apex_m_at_cap), derived from data.
func jump_apex_at_cap() -> float:
	return WorldScale.v(jump_height_px(jump_cap()))
