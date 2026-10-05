class_name SkillDef
extends RefCounted
## One skill's canonical record, typed: game/data/canonical/formulas/<class>.json "skills" (MeowDB MS Classic skill
## pages), joined with the skill's timing row in formulas/attack_speed.json and its search band in
## formulas/attack_styles.json (both found by skill_id, never by a hard-coded key). Nothing here is a literal gameplay
## number: costs, damage, heal totals, durations, cooldowns, speed bonuses, cast positions and the band come from the
## data, and a missing field is listed in `errors` and leaves that part of the skill off.
##
## The Beginner skills (formulas/beginner.json skills[]):
##   0001000 Three Snails  attack: fixed damage 15/25/40, MP 3/4/5 + one Snail/Blue Snail/Red Snail Shell (348/349/351),
##                         one target, nearest first, stepped search band 50-300 px, ground only, 800 ms action
##   0001001 Recovery      self: MP 5/10/15, HP 24/48/72 over 30 s, 2 min cooldown, ground/air/rope
##   0001002 Nimble Feet   self: MP 4/7/10, Speed +10 for 10/20/30 s, 3 min cooldown, ground/air/rope
## Each has max level 3 and no prerequisites (the records carry none).
##
## Get them with SkillDef.of(id, db) or SkillDef.catalog(job, db); the views are cached per ContentDB.

const KIND_ATTACK := "attack"
const KIND_HEAL := "heal_over_time"
const KIND_BUFF := "buff"
const POSITIONS: PackedStringArray = ["ground", "air", "rope"]
## The class every job keeps the skills of (Beginner skills stay with a character after its advancement).
const BASE_CLASS := "beginner"

static var _cache: Dictionary = {}

var id: String = ""
var name: String = ""
var description: String = ""
var page: String = ""
## "active" for every Beginner skill.
var type: String = ""
## KIND_ATTACK (fixed_damage per level), KIND_HEAL (hp_total) or KIND_BUFF (speed_bonus); "" when unknown.
var kind: String = ""
var max_level: int = 0
## Canonical text ("ground only", "ground, air, or rope") and its parsed positions.
var cast_position: String = ""
var cast_positions: PackedStringArray = []
## "projectile" (Three Snails) or "" for self skills.
var delivery: String = ""
var targets: int = 0
var range_px: float = 0.0
## Canonical per-level rows (level, effect, mp_cost, item_cost_id, item_cost_qty, fixed_damage, hp_total, duration_s,
## cooldown_s, speed_bonus ... as the record has them), index 0 = level 1.
var levels: Array = []
## Skill ids (with levels) that must be learned first: {"skill_id", "level"}. Empty for the Beginner skills.
var prerequisites: Array = []
## Weapon-speed-based base action time (attack_speed.json, the row whose skill_id is this id); 0 = no row.
var base_action_ms: float = 0.0
var weapon_speed_based: bool = false
## Stepped search band (attack_styles.json <...>_targeting with this skill_id, shape from ranged_search_bands):
## {"start_px", "reach_px", "band_px", "aim_px", "divisor", "up_px", "down_px"}; {} when the skill has none.
var band: Dictionary = {}
## Problems found building the view (empty when the record is complete).
var errors: PackedStringArray = []


## The skill's view, or null when no class record lists it.
static func of(skill_id: String, db: ContentDB) -> SkillDef:
	return _index(db).get(skill_id, null)


## Every skill a character of `job` can learn: the Beginner skills, then its class's own skills (MeowDB lists each
## class's skills in formulas/<class>.json; only the Beginner exists in Iteration Three). In record order.
static func catalog(job: String, db: ContentDB) -> Array[SkillDef]:
	var out: Array[SkillDef] = []
	var classes: PackedStringArray = [BASE_CLASS]
	var own := StatCalculator.job_class(job) if job != "" else BASE_CLASS
	if own != BASE_CLASS:
		classes.append(own)
	var idx := _index(db)
	for cls in classes:
		for rec in _records(cls, db):
			var sid := ItemDef.id_of((rec as Dictionary).get("skill_id", ""))
			if idx.has(sid):
				out.append(idx[sid])
	return out


## Builds a view from one canonical skill record (attack_speed / attack_styles looked up in `db` when given).
static func from_record(rec: Dictionary, db: ContentDB = null) -> SkillDef:
	var s := SkillDef.new()
	s.id = ItemDef.id_of(rec.get("skill_id", ""))
	s.name = String(rec.get("name", s.id))
	s.description = String(rec.get("description", ""))
	s.page = String(rec.get("page", ""))
	s.type = String(rec.get("type", ""))
	s.max_level = int(rec.get("max_level", 0)) if (rec.get("max_level") is int or rec.get("max_level") is float) else 0
	if s.max_level <= 0:
		s.errors.append("max_level missing")
	s.cast_position = String(rec.get("cast_position", ""))
	s.cast_positions = parse_positions(s.cast_position)
	if s.cast_positions.is_empty():
		s.errors.append("cast_position '%s' names no position" % s.cast_position)
	s.delivery = String(rec.get("delivery", "")) if rec.get("delivery") != null else ""
	s.targets = int(rec.get("targets", 0)) if (rec.get("targets") is int or rec.get("targets") is float) else 0
	s.range_px = float(rec.get("range_px", 0.0)) if (rec.get("range_px") is int or rec.get("range_px") is float) else 0.0
	var lv: Variant = rec.get("levels", [])
	if lv is Array:
		for row in lv:
			if row is Dictionary:
				s.levels.append(row)
	if s.levels.size() != s.max_level:
		s.errors.append("%d level rows for max_level %d" % [s.levels.size(), s.max_level])
	var pre: Variant = rec.get("prerequisites", [])
	if pre is Array:
		s.prerequisites = (pre as Array).duplicate(true)
	s.kind = _kind_of(s.levels)
	if s.kind == "":
		s.errors.append("no fixed_damage, hp_total or speed_bonus per level")
	if db != null:
		s._join_timing(db)
		s._join_band(db)
	return s


## "ground only" -> ["ground"]; "ground, air, or rope" -> ["ground", "air", "rope"].
static func parse_positions(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var words := text.to_lower().replace(",", " ").split(" ", false)
	for p in POSITIONS:
		if p in words:
			out.append(p)
	return out


func can_cast_from(position: String) -> bool:
	return position in cast_positions


## The canonical row of a level (1-based), or {} outside 1..max_level.
func level_row(level: int) -> Dictionary:
	if level < 1 or level > levels.size():
		return {}
	return levels[level - 1]


func mp_cost(level: int) -> int:
	return int(_num(level, "mp_cost"))


## The item a cast consumes at `level`: {"item_id", "qty"}, or {} when none.
func item_cost(level: int) -> Dictionary:
	var row := level_row(level)
	var item_id := ItemDef.id_of(row.get("item_cost_id", null))
	if item_id == "":
		return {}
	return {"item_id": item_id, "qty": maxi(1, int(_num(level, "item_cost_qty", 1.0)))}


func fixed_damage(level: int) -> float:
	return _num(level, "fixed_damage")


func hp_total(level: int) -> int:
	return int(_num(level, "hp_total"))


func duration_s(level: int) -> float:
	return _num(level, "duration_s")


func cooldown_s(level: int) -> float:
	return _num(level, "cooldown_s")


func speed_bonus(level: int) -> int:
	return int(_num(level, "speed_bonus"))


## MeowDB's effect line for a level ("MP -5; Recover HP 24 in 30 sec. Cooldown: 2 min."), "" outside 1..max.
func effect_text(level: int) -> String:
	return String(level_row(level).get("effect", ""))


## Cast lockout (ms) of an attack skill at a weapon speed tier: MeowDB's timing model on the base action
## (attack_speed.json: 800 ms -> 810 ms at Normal 6), CombatFormula.animation_time_ms. A skill that is not
## weapon-speed based plays at attack_speed.json's neutral tier. 0 when the skill has no timing row (Recovery, Nimble
## Feet: "Timing unavailable").
func action_ms(speed_tier: int, db: ContentDB) -> int:
	if base_action_ms <= 0.0:
		return 0
	var tier := speed_tier
	if not weapon_speed_based:
		tier = int(db.formula("attack_speed").get("neutral_tier", speed_tier))
	return CombatFormula.animation_time_ms(base_action_ms, tier, db)


func _num(level: int, key: String, fallback: float = 0.0) -> float:
	var v: Variant = level_row(level).get(key, null)
	return float(v) if (v is int or v is float) else fallback


func _join_timing(db: ContentDB) -> void:
	var row := _row_with_skill_id(db.formula("attack_speed"), id)
	if row.is_empty():
		return
	var base: Variant = row.get("base_action_ms", null)
	if base is int or base is float:
		base_action_ms = float(base)
	weapon_speed_based = bool(row.get("weapon_speed_based", false))


func _join_band(db: ContentDB) -> void:
	var styles := db.formula("attack_styles")
	var row := _row_with_skill_id(styles, id)
	if row.is_empty() or not row.has("band_start_px"):
		return
	var shape: Variant = styles.get("ranged_search_bands", {})
	var bands: Dictionary = shape if shape is Dictionary else {}
	var vert: Variant = row.get("vertical_reach_px", {})
	var v: Dictionary = vert if vert is Dictionary else {}
	band = {"start_px": float(row.get("band_start_px", 0.0)), "reach_px": float(row.get("horizontal_reach_px", range_px)),
		"band_px": float(bands.get("band_length_px", 0.0)), "aim_px": float(bands.get("aim_height_px", 0.0)),
		"divisor": float(bands.get("half_height_divisor", 0.0)), "up_px": float(v.get("up", 0.0)),
		"down_px": float(v.get("down", 0.0))}
	for k in ["start_px", "reach_px", "band_px", "divisor"]:
		if float(band[k]) <= 0.0:
			errors.append("search band %s missing (attack_styles.json)" % k)
			band = {}
			return


## The first Dictionary value of `table` (one level deep) whose skill_id is `skill_id`.
static func _row_with_skill_id(table: Dictionary, skill_id: String) -> Dictionary:
	for k in table:
		var v: Variant = table[k]
		if v is Dictionary and ItemDef.id_of((v as Dictionary).get("skill_id", null)) == skill_id:
			return v
	return {}


static func _kind_of(rows: Array) -> String:
	if rows.is_empty():
		return ""
	var row: Dictionary = rows[0]
	if row.has("fixed_damage"):
		return KIND_ATTACK
	if row.has("hp_total"):
		return KIND_HEAL
	if row.has("speed_bonus"):
		return KIND_BUFF
	return ""


static func _records(cls: String, db: ContentDB) -> Array:
	if db == null or not db.has("formulas", cls):
		return []
	var skills: Variant = db.formula(cls).get("skills", [])
	return skills if skills is Array else []


## skill id -> SkillDef for every class record in the db (Beginner plus StatCalculator.JOBS classes).
static func _index(db: ContentDB) -> Dictionary:
	if db == null:
		return {}
	var key := db.get_instance_id()
	if _cache.has(key):
		var entry: Dictionary = _cache[key]
		var ref: WeakRef = entry["db"]
		if ref.get_ref() == db:
			return entry["skills"]
	var out := {}
	var classes: PackedStringArray = [BASE_CLASS]
	for job in StatCalculator.JOBS:
		var cls := String((StatCalculator.JOBS[job] as Dictionary).get("class", job))
		if not (cls in classes):
			classes.append(cls)
	for cls in classes:
		for rec in _records(cls, db):
			if rec is Dictionary:
				var s := from_record(rec, db)
				if s.id != "":
					out[s.id] = s
	for k in _cache.keys():
		var old: WeakRef = _cache[k]["db"]
		if old.get_ref() == null:
			_cache.erase(k)
	_cache[key] = {"db": weakref(db), "skills": out}
	return out
