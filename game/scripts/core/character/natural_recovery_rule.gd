class_name NaturalRecoveryRule
extends RefCounted
## Natural HP recovery while resting: MeowDB documents only that "When you're not in combat, just standing still will
## slowly restore your HP" (formulas/recovery.json natural_regeneration, documented_values false). The amount, the
## interval and the out-of-combat delay are MisoStory adaptations in data/misostory/combat.json natural_recovery
## (reason + verified false). Pure: the NaturalRecovery node feeds it the player's state each physics tick.
##
## Rules:
##   - "not in combat": at least delay_s since the last attack made or monster touch (hit, miss or guard);
##   - "standing still": the caller reports can_rest (alive, grounded, not moving, not climbing, not knocked back,
##     not warping); any tick where it is false, or HP is full, starts the rest over;
##   - every tick_s of uninterrupted rest restores hp_per_tick, never above max HP. MP does not recover (MeowDB names
##     HP only and documents no natural MP recovery).

var hp_per_tick: int = 0
var tick_s: float = 10.0
var delay_s: float = 5.0
var requires_standing_still: bool = true

## Seconds since the last combat action (starts out of combat).
var since_combat: float = INF
## Seconds of uninterrupted rest toward the next tick.
var rest: float = 0.0


## The rule configured from combat.json natural_recovery (all keys required: a missing value is a data error, so this
## returns null rather than inventing a number).
static func from_db(db: ContentDB) -> NaturalRecoveryRule:
	var table: Variant = db.miso_table("combat") if db != null else null
	var cfg: Variant = (table as Dictionary).get("natural_recovery", null) if table is Dictionary else null
	if not (cfg is Dictionary):
		push_error("[NaturalRecoveryRule] data/misostory/combat.json has no natural_recovery section")
		return null
	return from_config(cfg)


static func from_config(cfg: Dictionary) -> NaturalRecoveryRule:
	for k in ["hp_per_tick", "tick_s", "delay_s", "requires_standing_still"]:
		if not cfg.has(k) or cfg[k] == null:
			push_error("[NaturalRecoveryRule] combat.json natural_recovery.%s is missing" % k)
			return null
	var r := NaturalRecoveryRule.new()
	r.hp_per_tick = int(cfg["hp_per_tick"])
	r.tick_s = maxf(0.01, float(cfg["tick_s"]))
	r.delay_s = maxf(0.0, float(cfg["delay_s"]))
	r.requires_standing_still = bool(cfg["requires_standing_still"])
	return r


## Something combat-like happened (an attack made, a touch taken): resting starts over after delay_s.
func note_combat() -> void:
	since_combat = 0.0
	rest = 0.0


## Advances `dt` seconds and returns the HP to restore now (0 most ticks). `can_rest` is the caller's "standing still,
## alive and free" test; with requires_standing_still false only aliveness matters, which the caller folds in too.
func step(dt: float, can_rest: bool, hp: int, max_hp: int) -> int:
	since_combat += dt
	if hp <= 0 or hp >= max_hp or (requires_standing_still and not can_rest) or since_combat < delay_s:
		rest = 0.0
		return 0
	rest += dt
	if rest < tick_s:
		return 0
	rest -= tick_s
	return mini(hp_per_tick, max_hp - hp)
