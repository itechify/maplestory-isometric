class_name SpawnModel
extends RefCounted
## MeowDB's MS Classic spawn engine (game/data/canonical/formulas/spawn_rate.json; MAP_ARCHITECTURE.md section 3.2):
##   - one global respawn tick (global_respawn_tick_s, 7.56 s), anchored at game-clock 0;
##   - a dead point is ready at death + cooldown (wave points: wave_point_cooldown_s, 5 s; timed points: their own
##     mobTime) and its mob reappears on the first tick at or after that moment;
##   - capacity = floor(spawn points x PlayerScalar), PlayerScalar from capacity.player_scalar_table (75% solo);
##   - the map mobRate: MeowDB's pages disagree on it, so whether it multiplies capacity is a MisoStory switch,
##     data/misostory/presentation.json map_mob_rate.apply (false: ignored, MeowDB's mechanics pages). When on,
##     capacity_for_map() multiplies by the map's canonical mob_rate, capped at the spawn-point count (one monster per
##     MeowDB spawn point).
## Every number is read from the canonical record and the adaptation switch; nothing is hard-coded here. Pure.

## Seconds between global respawn ticks.
var tick_s: float = 0.0
## Cooldown of a wave point (mobTime 0).
var wave_cooldown_s: float = 0.0
## Rows {players: int, pct: int, and_more: bool} from capacity.player_scalar_table ("6+" -> and_more).
var scalar_rows: Array[Dictionary] = []
## MisoStory's mob-rate decision (presentation.json map_mob_rate.apply; from_db). False: capacity never multiplies by
## the map's mobRate.
var uses_map_mob_rate: bool = false
## What MeowDB's spawn-engine guide says (formulas/spawn_rate.json map_spawn_rate_multiplier.applied_by_msc): kept as
## the canonical statement, never used as the switch (MeowDB's map pages say otherwise).
var canonical_applied_by_msc: bool = false
## map id -> MeowDB mob rate (maps/<id>.json mob_rate; from_db).
var map_mob_rates: Dictionary = {}
var errors: PackedStringArray = []
## Capacities the switch would have pushed past the spawn-point count (capped; one line per map).
var warnings: PackedStringArray = []

## Float slack when comparing times against tick boundaries (sub-microsecond; boundaries are k x tick_s).
const _EPS := 1e-7


## Builds the model from formulas/spawn_rate (Data.db at runtime, TestCase.db() in tests), the MisoStory mob-rate
## switch (presentation.json map_mob_rate.apply) and every map's canonical mob_rate.
static func from_db(db: ContentDB) -> SpawnModel:
	var m := SpawnModel.from_record(db.formula("spawn_rate"))
	var p: Variant = db.miso_table("presentation")
	var sw: Variant = (p as Dictionary).get("map_mob_rate", null) if p is Dictionary else null
	if sw is Dictionary and (sw as Dictionary).get("apply", null) is bool:
		m.uses_map_mob_rate = bool(sw["apply"])
	else:
		m.errors.append("data/misostory/presentation.json map_mob_rate.apply is missing")
	for id in db.ids("maps"):
		var rate: Variant = db.map(id).get("mob_rate", null)
		m.map_mob_rates[id] = float(rate) if typeof(rate) in [TYPE_INT, TYPE_FLOAT] else 1.0
	return m


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
	m.canonical_applied_by_msc = bool(mult.get("applied_by_msc", false))
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


## Maximum concurrent mobs: floor(points x PlayerScalar), in integer math so 45 x 80% is exactly 36. With the
## mob-rate switch on (uses_map_mob_rate), floor(that x mob_rate), never more than `points`: the runtime keeps one
## monster per MeowDB spawn point.
func capacity(points: int, players: int = 1, mob_rate: float = 1.0) -> int:
	var cap := (maxi(points, 0) * scalar_pct(players)) / 100
	if uses_map_mob_rate:
		cap = mini(int(floor(cap * mob_rate)), maxi(points, 0))
	return cap


## capacity() for map `map_id` with its canonical mob rate (map_mob_rates; 1.0 for an unknown map). The game's one
## entry point: MapInstanceState and MapDefinitions.capacity_of call it.
func capacity_for_map(map_id: String, points: int, players: int = 1) -> int:
	var rate := float(map_mob_rates.get(map_id, 1.0))
	var cap := capacity(points, players, rate)
	if uses_map_mob_rate:
		var wanted := int(floor(((maxi(points, 0) * scalar_pct(players)) / 100) * rate))
		if wanted > cap:
			var w := "%s: mob rate %.2f asks for %d monsters but the map has %d spawn points (capped)" % [map_id, rate, wanted, points]
			if not (w in warnings):
				warnings.append(w)
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
