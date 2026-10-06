class_name MonsterDef
extends RefCounted
## One monster species as the live game uses it: the canonical MeowDB record (data/canonical/monsters/<id>.json,
## read through MonsterCombatStats and ContentDB) joined with its isometric adaptation. Pure: no scene tree. Built
## once per species and shared by every actor.
##
## The adaptation is two layers: data/misostory/monsters/_shared.json (SHARED_TABLE: the values every species shares,
## such as the terrain probes, the wander rhythm, the hop landing reach and the fall landing tolerance), then the
## species file data/misostory/monsters/<id>.json on top of it. A key the species file names overrides the shared
## value (`adaptation` holds the merged view).
##
## Canonical (never restated here): level, HP, EXP, P.DMG, ACC, AVOID, defences, KB, the speed modifier, the
## movement label, the Peace flag, the touch zone and sprite size (px), and the animation clip lengths (ms).
## Adaptation: the proxy model and how it is scaled, the physics capsule, how the speed modifier becomes m/s, the
## AI timings and probes, the hop rule, the Peace touch rule and the see-through silhouette. Every px value is
## converted through WorldScale.
##
##   var def := MonsterDef.from_id("2", Data.db)
##   def.move_speed_mps      # 0.875 (Snail)
##   def.touch_size_m        # Vector3(width, height, depth) of the contact box
##   def.stats               # MonsterCombatStats for CombatFormula

const MOVEMENT_WALK := "walk"
const MOVEMENT_JUMP := "jump"
const TOUCH_ALWAYS := "always"
const TOUCH_WHEN_PROVOKED := "when_provoked"
const SPEED_MODEL := "walk_line_no_character_bonus"
const HOP_APEX_CHARACTER := "character_base_jump"
const WALK_CRAWL := "crawl"
const WALK_BOUNCE := "bounce"
## monsters/9.json hop_floor_rule: the spawn floor plus one hop above or below it ('Can hop to a floor above or below
## its spawn point').
const HOP_FLOOR_ONE_HOP := "spawn_floor_one_hop"
## combat.json monster_knockback.airborne_hit: a knockback hit cancels the rest of a hop; the push runs while it falls.
const AIRBORNE_CANCEL_HOP := "cancel_hop_then_push"
## hop_floor(): the hop would take the jumper two floors from its spawn point.
const NO_FLOOR := 1 << 30
## The shared adaptation table in data/misostory/monsters/ (a leading "_" marks a shared table, not a monster id).
const SHARED_TABLE := "_shared"

var id: String = ""
var name: String = ""
var stats: MonsterCombatStats = null
var level: int = 1
var max_hp: int = 0
var exp_reward: int = 0
## Canonical speed modifier (Snail -65) and its m/s conversion (see move_speed_px_per_s()).
var speed_modifier: int = 0
var move_speed_mps: float = 0.0
## "walk" ('Stays on its floor') or "jump" ('Jumps between floors').
var movement_kind: String = MOVEMENT_WALK
var movement_label: String = ""
## Canonical Peace attribute (flags.non_aggressive).
var peaceful: bool = false
var touch_rule: String = TOUCH_ALWAYS
## Contact box in meters: x = width (along the monster's facing), y = height, z = depth (isometric adaptation:
## combat.json isometric_reach.touch_zone_depth). Anchored at the feet, centred.
var touch_size_m: Vector3 = Vector3.ZERO
## Sprite size in meters (WorldScale.actor), used to fit the proxy model and the placeholder.
var sprite_size_m: Vector2 = Vector2.ZERO
## Canonical clip lengths in seconds (0 = a held pose or no clip).
var stand_s: float = 0.0
var move_s: float = 0.0
var hit_s: float = 0.0
var die_fade_s: float = 0.0
## Monster stagger (s) and push (m) when a hit reaches its KB threshold. The stagger is the canonical record's own
## stagger time when it has one (MeowDB's STAGGER field; combat.json monster_knockback.stagger_from_canonical_record),
## else CombatFormula.monster_stagger_s (the canonical hit1 clip, then the fallback). stagger_source says which:
## "canonical", "hit_animation" or "fallback".
var stagger_s: float = 0.0
var stagger_source: String = ""
var knockback_m: float = 0.0
## What a knockback hit does to a jumper in mid-hop (combat.json monster_knockback.airborne_hit).
var airborne_hit: String = ""

# --- adaptation (data/misostory/monsters/<id>.json) ---------------------------------------------------------------
## _library.glb asset ("" = procedural placeholder).
var model: String = ""
var model_fit: String = "sprite_height"
var placeholder_color: Color = Color(0.6, 0.64, 0.68)
## Procedural walk cycle: "crawl" (squash and stretch) or "bounce" (a small hop per step).
var walk_style: String = WALK_BOUNCE
var capsule_radius_m: float = 0.0
var capsule_height_m: float = 0.0
var idle_s: Vector2 = Vector2.ZERO
var walk_s: Vector2 = Vector2.ZERO
## Pacing ('Walks back and forth'): the chance to turn around on the pacing line after a stand, the run below which
## two turns in a row turn the line itself, and the random offset (on top of 90 degrees) of that new line.
var pace_reverse_chance: float = 0.0
var pace_min_run_m: float = 0.0
var turn_jitter_rad: float = 0.0
var probe_ahead_m: float = 0.0
var ledge_tolerance_m: float = 0.0
var wall_probe_height_m: float = 0.0
## Half-height of the spawn floor band ('Stays on its floor'; floor_range()). 0 = no floor limit.
var floor_band_m: float = 0.0
var provoked_chase_s: float = 0.0
## Jumpers only.
var hop_interval_s: Vector2 = Vector2.ZERO
var hop_apex_m: float = 0.0
var hop_max_drop_m: float = 0.0
## Which floors a jumper may use (HOP_FLOOR_ONE_HOP: its spawn floor and one hop above or below it).
var hop_floor_rule: String = ""
## A hop may land at most this fraction of hop_apex_m above the feet.
var hop_max_rise_apex_fraction: float = 0.0
## A falling monster lands on ground within this distance of its feet in one tick.
var fall_landing_tolerance_m: float = 0.0
## Canonical gravity (knockback_airtime.gravity_px_per_s2 x WorldScale.v), used for hops and falls.
var gravity_mps2: float = 0.0
## The see-through silhouette (MonsterVisual): shown while the monster is within see_through_radius_m of the player,
## kept until see_through_radius_m + see_through_hysteresis_m; its colour (sRGB, alpha) and fade time.
var see_through_radius_m: float = 0.0
var see_through_hysteresis_m: float = 0.0
var see_through_color: Color = Color(0, 0, 0, 0)
var see_through_fade_s: float = 0.0
## The silhouette draws only where the cover in front is at least this far nearer along the view (m).
var see_through_min_cover_m: float = 0.0
## The merged adaptation (monsters/_shared.json, then monsters/<id>.json on top); `reasons` merged the same way.
var adaptation: Dictionary = {}

## Problems found while building (missing canonical or adaptation fields). Empty when the species is complete.
var errors: PackedStringArray = []

static var _cache: Dictionary = {}


## The species `monster_id`, cached per ContentDB.
static func from_id(monster_id: String, db: ContentDB) -> MonsterDef:
	var key := "%d:%s" % [db.get_instance_id(), monster_id]
	if _cache.has(key):
		return _cache[key]
	var d := build(monster_id, db)
	for e in d.errors:
		push_error("[MonsterDef] %s: %s" % [monster_id, e])
	_cache[key] = d
	return d


## Builds without the cache (tests use it with edited data).
static func build(monster_id: String, db: ContentDB) -> MonsterDef:
	var d := MonsterDef.new()
	d.id = monster_id
	var rec := db.monster(monster_id)
	if rec.is_empty():
		d.errors.append("no canonical record data/canonical/monsters/%s.json" % monster_id)
		return d
	d._load_canonical(rec, db)
	var miso := db.miso_entity("monsters", monster_id)
	if miso.is_empty():
		d.errors.append("no adaptation data/misostory/monsters/%s.json" % monster_id)
	var shared := db.miso_entity("monsters", SHARED_TABLE)
	if shared.is_empty():
		d.errors.append("no shared adaptation data/misostory/monsters/%s.json" % SHARED_TABLE)
	d.adaptation = merged_adaptation(shared, miso)
	d._load_adaptation(d.adaptation, db)
	return d


## The species adaptation `species` laid over the shared table `shared`: every key of `species` wins, and the two
## `reasons` maps merge the same way (a species override carries its own reason). Inputs are not modified.
static func merged_adaptation(shared: Dictionary, species: Dictionary) -> Dictionary:
	if species.is_empty():
		return {}
	var out := shared.duplicate(true)
	for k in ["id", "kind", "description"]:
		out.erase(k)
	var reasons: Dictionary = (out.get("reasons", {}) as Dictionary).duplicate() if out.get("reasons") is Dictionary else {}
	out.merge(species.duplicate(true), true)
	if species.get("reasons") is Dictionary:
		reasons.merge(species["reasons"], true)
	out["reasons"] = reasons
	return out


## MeowDB publishes a speed modifier per monster but no formula; MisoStory reads it the way the character walk line
## reads Speed: px/s = slope x (base Speed + modifier), where slope is the px/s per Speed point of the published
## walk line (two published points: base_px_per_s at base_speed, cap_px_per_s at speed_cap). The character-only
## "+20 Speed behind the scenes" is not applied. Returns 0 (and the caller reports) when the line is missing.
static func move_speed_px_per_s(modifier: int, movement: Dictionary) -> float:
	var ws: Variant = movement.get("walk_speed", {})
	if not (ws is Dictionary):
		return 0.0
	var base_speed := float(movement.get("base_speed", 0.0))
	var span := float(movement.get("speed_cap", 0.0)) - base_speed
	if span <= 0.0:
		return 0.0
	var slope := (float((ws as Dictionary).get("cap_px_per_s", 0.0)) - float((ws as Dictionary).get("base_px_per_s", 0.0))) / span
	return maxf(0.0, slope * (base_speed + modifier))


## Canonical base jump apex in px (jump_height_px_by_jump at base_jump), or 0.
static func base_jump_px(movement: Dictionary) -> float:
	var base := float(movement.get("base_jump", 0.0))
	for row in movement.get("jump_height_px_by_jump", []):
		if row is Dictionary and float((row as Dictionary).get("jump", -1)) == base:
			return float(row["height_px"])
	return 0.0


## The stagger time (s) a canonical monster record publishes (MeowDB's 'STAGGER 0.6 seconds', read from the live
## pages into the record), or 0 when it has none. Accepted fields: `stagger_s` / `stagger_duration_s` (seconds),
## `stagger_ms` / `stagger_duration_ms` (milliseconds), or `stagger` as seconds or {"seconds" | "s" | "ms" |
## "duration_ms"}. Nothing is invented: a record without any of them returns 0 (the caller falls back to the clip).
static func canonical_stagger_s(rec: Dictionary) -> float:
	for k in ["stagger_s", "stagger_duration_s"]:
		if typeof(rec.get(k, null)) in [TYPE_INT, TYPE_FLOAT]:
			return maxf(float(rec[k]), 0.0)
	for k in ["stagger_ms", "stagger_duration_ms"]:
		if typeof(rec.get(k, null)) in [TYPE_INT, TYPE_FLOAT]:
			return maxf(float(rec[k]) / 1000.0, 0.0)
	var st: Variant = rec.get("stagger", null)
	if typeof(st) in [TYPE_INT, TYPE_FLOAT]:
		return maxf(float(st), 0.0)
	if st is Dictionary:
		for k in ["seconds", "s"]:
			if typeof((st as Dictionary).get(k, null)) in [TYPE_INT, TYPE_FLOAT]:
				return maxf(float(st[k]), 0.0)
		for k in ["ms", "duration_ms"]:
			if typeof((st as Dictionary).get(k, null)) in [TYPE_INT, TYPE_FLOAT]:
				return maxf(float(st[k]) / 1000.0, 0.0)
	return 0.0


## Duration in seconds of the canonical clip `clip` (0 when absent or a held pose).
static func clip_s(rec: Dictionary, clip: String) -> float:
	var anims: Variant = rec.get("animations", {})
	if anims is Dictionary and (anims as Dictionary).get(clip) is Dictionary:
		var v: Variant = anims[clip].get("duration_ms", null)
		if v != null:
			return float(v) / 1000.0
	return 0.0


func is_jumper() -> bool:
	return movement_kind == MOVEMENT_JUMP


## The heights a monster that spawned with its feet at `spawn_y` may walk at on its spawn floor, as
## Vector2(lowest, highest): the surface at spawn_y, widened to its spawn region's authored height band
## [region_lo, region_hi] when spawn_y lies on that tier (within floor_band_m of it; a slot placed on another surface
## keeps its own height only), plus floor_band_m either way. Unbounded (-INF, INF) when floor_band_m is 0. Pure: the
## 'Stays on its floor' adaptation (monsters/_shared.json floor_band_m). A jumper's other floors: hop_floor().
func floor_range(spawn_y: float, region_lo: float = NAN, region_hi: float = NAN) -> Vector2:
	if floor_band_m <= 0.0:
		return Vector2(-INF, INF)
	var s_lo := spawn_y
	var s_hi := spawn_y
	if not is_nan(region_lo) and not is_nan(region_hi):
		var rlo := minf(region_lo, region_hi)
		var rhi := maxf(region_lo, region_hi)
		if spawn_y >= rlo - floor_band_m and spawn_y <= rhi + floor_band_m:
			s_lo = minf(s_lo, rlo)
			s_hi = maxf(s_hi, rhi)
	return Vector2(s_lo - floor_band_m, s_hi + floor_band_m)


## The walking band of a floor whose surface is at height `y` (a jumper's floor above or below its spawn floor).
func floor_band_at(y: float) -> Vector2:
	if floor_band_m <= 0.0:
		return Vector2(-INF, INF)
	return Vector2(y - floor_band_m, y + floor_band_m)


## Which floor a jumper standing on floor `index` (0 = its spawn floor, walking band `spawn_band`; +1 / -1 = a floor
## one hop above / below it, walking band `band`) is on after a hop that lands at height `y1`: 0 when y1 is on its
## spawn floor, `index` when y1 is on its current floor, +1 / -1 for a floor above / below its spawn floor reached
## from the spawn floor itself, else NO_FLOOR (the hop would take it two floors from its spawn point). MeowDB 'Can
## hop to a floor above or below its spawn point'; hop_floor_rule HOP_FLOOR_ONE_HOP (monsters/9.json). Without that
## rule only the spawn floor and the current floor count.
func hop_floor(index: int, band: Vector2, spawn_band: Vector2, y1: float) -> int:
	if y1 >= spawn_band.x and y1 <= spawn_band.y:
		return 0
	if y1 >= band.x and y1 <= band.y:
		return index
	if hop_floor_rule == HOP_FLOOR_ONE_HOP and index == 0:
		return 1 if y1 > spawn_band.y else -1
	return NO_FLOOR


func has_model() -> bool:
	return model != ""


## True when walking into this monster can hurt the player (`provoked`: the player has hit it).
func touch_active(provoked: bool) -> bool:
	if touch_rule == TOUCH_WHEN_PROVOKED:
		return provoked
	return true


func _load_canonical(rec: Dictionary, db: ContentDB) -> void:
	stats = MonsterCombatStats.from_id(id, db)
	name = String(rec.get("name", id))
	level = stats.level
	max_hp = stats.hp
	exp_reward = stats.exp
	if max_hp <= 0:
		errors.append("canonical hp missing")
	speed_modifier = int(rec.get("speed", 0)) if rec.get("speed") != null else 0
	if rec.get("speed") == null:
		errors.append("canonical speed modifier missing")
	var mv: Variant = rec.get("movement", {})
	movement_label = String((mv as Dictionary).get("label", "")) if mv is Dictionary else ""
	var flags: Variant = rec.get("flags", {})
	peaceful = bool((flags as Dictionary).get("non_aggressive", false)) if flags is Dictionary else false
	var tz := stats.touch_zone_px
	if tz == Vector2.ZERO:
		errors.append("canonical touch_zone_px missing")
	touch_size_m = Vector3(WorldScale.actor(tz.x), WorldScale.actor(tz.y),
		WorldScale.actor(CombatReach.touch_zone_depth_px(stats, db)))
	var spr: Variant = rec.get("sprite_size_px", [])
	if spr is Array and (spr as Array).size() == 2:
		sprite_size_m = Vector2(WorldScale.actor(float(spr[0])), WorldScale.actor(float(spr[1])))
	else:
		sprite_size_m = Vector2(touch_size_m.x, touch_size_m.y)
	stand_s = clip_s(rec, "stand")
	move_s = clip_s(rec, "move")
	hit_s = clip_s(rec, "hit1")
	var fade: Variant = rec.get("die_fade_ms", null)
	die_fade_s = float(fade) / 1000.0 if fade != null else clip_s(rec, "die1")
	var mk := CombatRules.of(db).adaptation("monster_knockback")
	var canon_stagger := canonical_stagger_s(rec) if bool(mk.get("stagger_from_canonical_record", false)) else 0.0
	if canon_stagger > 0.0:
		stagger_s = canon_stagger
		stagger_source = "canonical"
	else:
		stagger_s = CombatFormula.monster_stagger_s(stats, db)
		stagger_source = "hit_animation" if String(mk.get("stagger_duration", "")) == "hit_animation" \
			and stats.hit_animation_ms > 0 else "fallback"
	airborne_hit = String(mk.get("airborne_hit", ""))
	knockback_m = WorldScale.h(CombatFormula.monster_knockback_distance_px(db))
	var movement := db.formula("movement")
	gravity_mps2 = WorldScale.v(float((movement.get("knockback_airtime", {}) as Dictionary).get("gravity_px_per_s2", 0.0)))
	if gravity_mps2 <= 0.0:
		errors.append("canonical movement.knockback_airtime.gravity_px_per_s2 missing")


func _load_adaptation(a: Dictionary, db: ContentDB) -> void:
	var m: Variant = a.get("model", null)
	model = String(m) if m is String else ""
	# monsters/_shared.json holds it for every species: missing from both layers is an error like any shared value.
	if a.get("model_fit") is String:
		model_fit = String(a["model_fit"])
	elif not a.is_empty():
		errors.append("adaptation 'model_fit' missing")
	if a.get("placeholder_color") is String:
		placeholder_color = Color(String(a["placeholder_color"]))
	walk_style = String(a.get("walk_style", WALK_BOUNCE))
	if not (walk_style in [WALK_CRAWL, WALK_BOUNCE]):
		errors.append("unknown walk_style '%s'" % walk_style)
	capsule_radius_m = _num(a, "capsule_radius_m")
	capsule_height_m = _num(a, "capsule_height_m")
	var speed_model := String(a.get("speed_model", ""))
	if speed_model == SPEED_MODEL:
		move_speed_mps = WorldScale.h(move_speed_px_per_s(speed_modifier, db.formula("movement")))
		if move_speed_mps <= 0.0 and speed_modifier > -100:
			errors.append("canonical walk_speed line missing (formulas/movement.json)")
	else:
		errors.append("unknown speed_model '%s'" % speed_model)
	movement_kind = String(a.get("movement_kind", MOVEMENT_WALK))
	if not (movement_kind in [MOVEMENT_WALK, MOVEMENT_JUMP]):
		errors.append("unknown movement_kind '%s'" % movement_kind)
	idle_s = _range(a, "idle_s")
	walk_s = _range(a, "walk_s")
	pace_reverse_chance = _num(a, "pace_reverse_chance")
	pace_min_run_m = _num(a, "pace_min_run_m")
	turn_jitter_rad = deg_to_rad(_num(a, "turn_jitter_deg"))
	probe_ahead_m = _num(a, "probe_ahead_m")
	ledge_tolerance_m = _num(a, "ledge_tolerance_m")
	wall_probe_height_m = _num(a, "wall_probe_height_m")
	floor_band_m = _num(a, "floor_band_m")
	provoked_chase_s = _num(a, "provoked_chase_s")
	fall_landing_tolerance_m = _num(a, "fall_landing_tolerance_m")
	see_through_radius_m = _num(a, "see_through_radius_m")
	see_through_hysteresis_m = _num(a, "see_through_hysteresis_m")
	see_through_fade_s = _num(a, "see_through_fade_s")
	see_through_min_cover_m = _num(a, "see_through_min_cover_m")
	var tint: Variant = a.get("see_through_color", null)
	if tint is Array and (tint as Array).size() == 4:
		see_through_color = Color(float(tint[0]), float(tint[1]), float(tint[2]), float(tint[3]))
	elif not a.is_empty():
		errors.append("adaptation 'see_through_color' must be [r, g, b, a]")
	touch_rule = String(a.get("touch_rule", TOUCH_ALWAYS))
	if not (touch_rule in [TOUCH_ALWAYS, TOUCH_WHEN_PROVOKED]):
		errors.append("unknown touch_rule '%s'" % touch_rule)
	if is_jumper():
		hop_interval_s = _range(a, "hop_interval_s")
		hop_max_drop_m = _num(a, "hop_max_drop_m")
		hop_max_rise_apex_fraction = _num(a, "hop_max_rise_apex_fraction")
		if a.has("hop_max_rise_apex_fraction") and (hop_max_rise_apex_fraction <= 0.0 or hop_max_rise_apex_fraction > 1.0):
			errors.append("adaptation 'hop_max_rise_apex_fraction' must be in (0, 1]")
		var apex := String(a.get("hop_apex", ""))
		if apex == HOP_APEX_CHARACTER:
			hop_apex_m = WorldScale.v(base_jump_px(db.formula("movement")))
			if hop_apex_m <= 0.0:
				errors.append("canonical jump_height_px_by_jump at base_jump missing")
		else:
			errors.append("unknown hop_apex '%s'" % apex)
		hop_floor_rule = String(a.get("hop_floor_rule", ""))
		if hop_floor_rule != HOP_FLOOR_ONE_HOP:
			errors.append("unknown hop_floor_rule '%s'" % hop_floor_rule)


func _num(a: Dictionary, key: String) -> float:
	var v: Variant = a.get(key, null)
	if v is int or v is float:
		return float(v)
	if not a.is_empty():
		errors.append("adaptation '%s' missing" % key)
	return 0.0


func _range(a: Dictionary, key: String) -> Vector2:
	var v: Variant = a.get(key, null)
	if v is Array and (v as Array).size() == 2:
		return Vector2(float(v[0]), float(v[1]))
	if not a.is_empty():
		errors.append("adaptation '%s' must be [min, max]" % key)
	return Vector2.ZERO
