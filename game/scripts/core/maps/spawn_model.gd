class_name SpawnModel
extends RefCounted
## MeowDB's MS Classic spawn engine (game/data/canonical/formulas/spawn_rate.json; MAP_ARCHITECTURE.md section 3.2):
##   - one global respawn tick (global_respawn_tick_s, 7.56 s), anchored at game-clock 0;
##   - a dead point is ready at death + cooldown (wave points: wave_point_cooldown_s, 5 s; timed points: their own
##     mobTime) and its mob reappears on the first tick at or after that moment;
##   - capacity = floor(spawn points x PlayerScalar), PlayerScalar from capacity.player_scalar_table (75% solo);
##   - the map mobRate is ignored (map_spawn_rate_multiplier.applied_by_msc = false).
## Every number is read from the canonical record; nothing is hard-coded here. Pure.

## Seconds between global respawn ticks.
var tick_s: float = 0.0
## Cooldown of a wave point (mobTime 0).
var wave_cooldown_s: float = 0.0
## Rows {players: int, pct: int, and_more: bool} from capacity.player_scalar_table ("6+" -> and_more).
var scalar_rows: Array[Dictionary] = []
## False in MS Classic: capacity never multiplies by the map's mobRate.
var uses_map_mob_rate: bool = false
var errors: PackedStringArray = []

## Float slack when comparing times against tick boundaries (sub-microsecond; boundaries are k x tick_s).
const _EPS := 1e-7


## Builds the model from formulas/spawn_rate (Data.db at runtime, TestCase.db() in tests).
static func from_db(db: ContentDB) -> SpawnModel:
	return SpawnModel.from_record(db.formula("spawn_rate"))


static func from_record(rec: Dictionary) -> SpawnModel:
	var m := SpawnModel.new()
	if rec.is_empty():
		m.errors.append("formulas/spawn_rate.json is missing")
		return m
	m.tick_s = float(rec.get("global_respawn_tick_s", 0.0))
	m.wave_cooldown_s = float(rec.get("wave_point_cooldown_s", 0.0))
	var cap: Dictionary = rec.get("capacity", {})
	for row in cap.get("player_scalar_table", []):
		if not (row is Dictionary):
			continue
		var players_text := str(row.get("players", "")).strip_edges()
		var r := {"players": players_text.trim_suffix("+").to_int(), "pct": int(row.get("scalar_pct", 0)),
			"and_more": players_text.ends_with("+")}
		m.scalar_rows.append(r)
	m.scalar_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.players) < int(b.players))
	var mult: Dictionary = rec.get("map_spawn_rate_multiplier", {})
	m.uses_map_mob_rate = bool(mult.get("applied_by_msc", false))
	if m.tick_s <= 0.0:
		m.errors.append("spawn_rate.global_respawn_tick_s must be positive")
	if m.scalar_rows.is_empty():
		m.errors.append("spawn_rate.capacity.player_scalar_table is empty")
	return m


## PlayerScalar in whole percent for `players` on the map (75 solo).
func scalar_pct(players: int = 1) -> int:
	var n := maxi(players, 1)
	var best := 0
	for r in scalar_rows:
		if int(r.players) == n or (bool(r.and_more) and n >= int(r.players)):
			return int(r.pct)
		if int(r.players) <= n:
			best = int(r.pct)
	return best


## Maximum concurrent mobs: floor(points x PlayerScalar), in integer math so 45 x 80% is exactly 36. mob_rate is
## accepted only to make the rule explicit: MS Classic ignores it (uses_map_mob_rate is false in MeowDB's model).
func capacity(points: int, players: int = 1, mob_rate: float = 1.0) -> int:
	var cap := (maxi(points, 0) * scalar_pct(players)) / 100
	if uses_map_mob_rate:
		cap = int(floor(cap * mob_rate))
	return cap


## Cooldown of a spawn point: its own mobTime when timed, else the wave cooldown.
func cooldown_for(mob_time_s: float) -> float:
	return mob_time_s if mob_time_s > 0.0 else wave_cooldown_s


## Index of the first tick boundary at or after t (boundary k is at k x tick_s).
func boundary_index_at_or_after(t: float) -> int:
	if tick_s <= 0.0:
		return 0
	return int(ceil(t / tick_s - _EPS))


## Index of the last tick boundary at or before t.
func boundary_index_at_or_before(t: float) -> int:
	if tick_s <= 0.0:
		return 0
	return int(floor(t / tick_s + _EPS))


func boundary_time(k: int) -> float:
	return k * tick_s


## When a mob that died at `died_at` reappears: the first tick at or after died_at + cooldown.
func respawn_time(died_at: float, mob_time_s: float = 0.0) -> float:
	return boundary_time(boundary_index_at_or_after(died_at + cooldown_for(mob_time_s)))
