class_name NaturalRecoveryRule
extends RefCounted
## Natural HP recovery: the project owner's rule (docs/ITERATION_THREE_BRIEF.md "Natural HP Regeneration", contract C4),
## configured from data/misostory/recovery.json natural_hp (authority Project owner, verified against the brief).
## MeowDB documents natural regeneration only qualitatively (formulas/recovery.json natural_regeneration). Pure: the
## NaturalRecovery node feeds it the player's activity each physics tick.
##
## Rules:
##   - hp_per_tick HP for every tick_s seconds of ELIGIBLE time. Eligible activities (PlayerController.activity()) are
##     natural_hp.eligible_activities: "still" and "seated";
##   - every other activity (walking, jumping, attacking, climbing, hitstun, dead, other) PAUSES the clock: rest_s keeps
##     its value and the next eligible second continues from it. Nothing resets it, and there is no combat delay;
##   - while HP is full (or 0) the clock holds; HP never goes above Max HP;
##   - while seated on a chair, the chair's canonical bonus (items/<id>.json setup.hp_recovery_bonus every
##     setup.interval_s) runs on its own clock (chair_rest_s, contract C5), added on top. recovery.json chair_bonus says
##     whether standing up resets that clock and whether full HP holds it (both MisoStory adaptations);
##   - MP does not recover on its own: MeowDB documents no natural MP recovery (recovery.json natural_mp, a source gap).
##
## The natural clock is CharacterState.natural_recovery.hp_rest_s (contract C3): the node loads rest_s from the live
## character before each step and stores it after, so a save keeps the paused time and every character has its own.

## Tolerance on a tick boundary: 600 physics ticks of 1/60 s add up to 10 s only up to floating-point rounding.
const EPSILON_S := 1e-6
## The activity that sits on a chair (PlayerController.activity(), contract C4).
const SEATED := &"seated"

var hp_per_tick: int = 0
var tick_s: float = 10.0
## PlayerController.activity() values during which the natural clock runs.
var eligible: PackedStringArray = []
## recovery.json chair_bonus: the chair clock starts again at each sit / holds while HP is full.
var chair_stand_resets_clock: bool = true
var chair_full_hp_holds_clock: bool = true

## Eligible seconds accumulated toward the next natural tick, in [0, tick_s) between steps.
var rest_s: float = 0.0
## Seated seconds accumulated toward the next chair bonus (never saved: the seated state is not saved).
var chair_rest_s: float = 0.0


## The rule configured from data/misostory/recovery.json (natural_hp and chair_bonus; every key required: a missing
## value is a data error, so this returns null rather than inventing a number).
static func from_db(db: ContentDB) -> NaturalRecoveryRule:
	var table: Variant = db.miso_table("recovery") if db != null else null
	if not (table is Dictionary):
		push_error("[NaturalRecoveryRule] data/misostory/recovery.json is missing")
		return null
	return from_config(table)


## `cfg` is the recovery.json table: {"natural_hp": {hp_per_tick, tick_s, eligible_activities}, "chair_bonus":
## {stand_resets_clock, full_hp_holds_clock}}.
static func from_config(cfg: Dictionary) -> NaturalRecoveryRule:
	var hp: Variant = cfg.get("natural_hp", null)
	var chair: Variant = cfg.get("chair_bonus", null)
	if not (hp is Dictionary) or not (chair is Dictionary):
		push_error("[NaturalRecoveryRule] recovery.json needs the natural_hp and chair_bonus sections")
		return null
	for k in ["hp_per_tick", "tick_s", "eligible_activities"]:
		if hp.get(k, null) == null:
			push_error("[NaturalRecoveryRule] recovery.json natural_hp.%s is missing" % k)
			return null
	for k in ["stand_resets_clock", "full_hp_holds_clock"]:
		if not (chair.get(k, null) is bool):
			push_error("[NaturalRecoveryRule] recovery.json chair_bonus.%s must be true or false" % k)
			return null
	if not (hp["eligible_activities"] is Array) or float(hp["tick_s"]) <= EPSILON_S or int(hp["hp_per_tick"]) < 0:
		push_error("[NaturalRecoveryRule] recovery.json natural_hp: hp_per_tick >= 0, tick_s > 0, eligible_activities a list")
		return null
	var r := NaturalRecoveryRule.new()
	r.hp_per_tick = int(hp["hp_per_tick"])
	r.tick_s = float(hp["tick_s"])
	r.eligible = PackedStringArray(hp["eligible_activities"])
	r.chair_stand_resets_clock = chair["stand_resets_clock"]
	r.chair_full_hp_holds_clock = chair["full_hp_holds_clock"]
	return r


## True when the natural clock runs during `activity` (a PlayerController.activity() value).
func is_eligible(activity: StringName) -> bool:
	return eligible.has(String(activity))


## Advances `dt` seconds spent in `activity` and returns the HP to restore now (0 most ticks), never more than
## max_hp - hp. `chair_hp` / `chair_interval_s`: the bonus of the chair the player sits on (Chairs.bonus(); 0 when not
## seated on a chair).
func step(dt: float, activity: StringName, hp: int, max_hp: int, chair_hp: int = 0, chair_interval_s: float = 0.0) -> int:
	if dt <= 0.0:
		return 0
	var room := maxi(0, max_hp - hp)
	var alive := hp > 0
	var heal := 0
	# Natural: only eligible time below Max HP counts; anything else leaves rest_s as it is (pause / hold).
	if alive and room > 0 and is_eligible(activity):
		rest_s += dt
		while rest_s >= tick_s - EPSILON_S and heal < room:
			rest_s = maxf(0.0, rest_s - tick_s)
			heal += hp_per_tick
		# A tick of this step filled HP: from that tick on the clock holds (full HP), so the time after it does not
		# count. Without this a step longer than a tick would leave rest_s past tick_s (contract C3: [0, interval)).
		if heal >= room:
			rest_s = 0.0
	# The chair's own clock, only while seated on a chair.
	if activity != SEATED or chair_hp <= 0 or chair_interval_s <= EPSILON_S:
		if chair_stand_resets_clock:
			chair_rest_s = 0.0
	elif alive and (room > 0 or not chair_full_hp_holds_clock):
		chair_rest_s += dt
		while chair_rest_s >= chair_interval_s - EPSILON_S:
			chair_rest_s = maxf(0.0, chair_rest_s - chair_interval_s)
			heal += chair_hp
	return mini(heal, room)
