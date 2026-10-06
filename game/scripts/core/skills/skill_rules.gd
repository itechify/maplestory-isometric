class_name SkillRules
extends RefCounted
## The MisoStory values the skill system needs and MeowDB does not publish: data/misostory/skills.json, read once per
## ContentDB (SkillRules.of(db), cached like CombatRules). Every canonical skill number lives in SkillDef instead.
##
## A missing or malformed value is reported in `errors` (and push_error) and its feature falls back to "off": no
## heal ticks (the whole Recovery total lands when the effect ends), no projectile, effects kept at death. There is no
## remembered tuning number in code.

const TABLE := "skills"

static var _cache: Dictionary = {}

## Problems found reading the table (empty when it is complete).
var errors: PackedStringArray = []

## Recovery: seconds between heal ticks (recovery_heal.tick_s); 0 = one heal when the effect ends.
var recovery_tick_s: float = 0.0
## Recovery and Nimble Feet: the cast lockout (buff_cast.lockout_s).
var buff_lockout_s: float = 0.0
## Three Snails: a cast with no target still spends the shell and MP (three_snails.whiff_consumes_costs).
var whiff_consumes_costs: bool = true
## Three Snails: walls and platforms block the search (three_snails.terrain_check). Only false is supported: no such
## test exists, so true is reported in `errors` and read as false.
var terrain_check: bool = false
## Three Snails presentation: the shell's flight speed (m/s) and size (m); 0 = no projectile drawn.
var projectile_speed_mps: float = 0.0
var projectile_size_m: float = 0.0
## Skill effects end when the character dies (effects_on_death.end_effects).
var end_effects_on_death: bool = false
## Skill cooldowns keep counting down through a death (effects_on_death.keep_cooldowns).
var keep_cooldowns_on_death: bool = true


## The rules for a ContentDB (built on first use, then cached for that instance).
static func of(db: ContentDB) -> SkillRules:
	var key := db.get_instance_id() if db != null else 0
	if _cache.has(key):
		var entry: Dictionary = _cache[key]
		var ref: WeakRef = entry["db"]
		if db != null and ref.get_ref() == db:
			return entry["rules"]
	var rules := SkillRules.new()
	rules._load(db)
	for k in _cache.keys():
		var old: WeakRef = _cache[k]["db"]
		if old.get_ref() == null:
			_cache.erase(k)
	if db != null:
		_cache[key] = {"db": weakref(db), "rules": rules}
	return rules


## Builds the rules from a table (tests pass an edited copy of skills.json).
static func from_table(table: Variant) -> SkillRules:
	var rules := SkillRules.new()
	rules._read(table)
	return rules


func _load(db: ContentDB) -> void:
	_read(db.miso_table(TABLE) if db != null else null)


func _read(table: Variant) -> void:
	errors = PackedStringArray()
	if not (table is Dictionary):
		_fail("the table is missing")
		return
	var t: Dictionary = table
	var heal := _section(t, "recovery_heal")
	recovery_tick_s = _num(heal, "recovery_heal", "tick_s", 0.0)
	var dist: Variant = heal.get("distribution", null)
	if not heal.is_empty() and dist != "equal_ticks":
		_fail("recovery_heal.distribution must be \"equal_ticks\"")
	var buff := _section(t, "buff_cast")
	buff_lockout_s = _num(buff, "buff_cast", "lockout_s", 0.0)
	var snails := _section(t, "three_snails")
	whiff_consumes_costs = _flag(snails, "three_snails", "whiff_consumes_costs", true)
	terrain_check = _flag(snails, "three_snails", "terrain_check", false)
	if terrain_check:
		# Recorded so the choice is visible, but there is no wall/platform test to switch on (canonical: "not
		# confirmed"). A true value would silently do nothing, so it is an error and the search stays unblocked.
		_fail("three_snails.terrain_check true is not supported: no wall or platform test exists")
		terrain_check = false
	projectile_speed_mps = _num(snails, "three_snails", "projectile_speed_mps", 0.0)
	projectile_size_m = _num(snails, "three_snails", "projectile_size_m", 0.0)
	var death := _section(t, "effects_on_death")
	end_effects_on_death = _flag(death, "effects_on_death", "end_effects", false)
	keep_cooldowns_on_death = _flag(death, "effects_on_death", "keep_cooldowns", true)


func _section(t: Dictionary, name: String) -> Dictionary:
	var v: Variant = t.get(name, null)
	if v is Dictionary:
		return v
	_fail("missing section '%s'" % name)
	return {}


func _num(section: Dictionary, name: String, key: String, off: float) -> float:
	if section.is_empty():
		return off
	var v: Variant = section.get(key, null)
	if (v is int or v is float) and float(v) >= 0.0:
		return float(v)
	_fail("%s.%s must be a number >= 0" % [name, key])
	return off


func _flag(section: Dictionary, name: String, key: String, off: bool) -> bool:
	if section.is_empty():
		return off
	var v: Variant = section.get(key, null)
	if v is bool:
		return v
	_fail("%s.%s must be true or false" % [name, key])
	return off


func _fail(msg: String) -> void:
	var line := "misostory/%s.json: %s" % [TABLE, msg]
	errors.append(line)
	push_error("[SkillRules] " + line)
