class_name DeathRules
extends RefCounted
## The penalties of a death, applied in order at the moment of death, as classic MapleStory does (MAP_ARCHITECTURE.md
## section 4.8; MapSession's death_commit hook calls them through DeathController.commit_rules, once per death, and
## the game is saved right after). Pure rules: no scene tree, no signals; the DeathController announces the result.
##
## A rule is a Callable(character: CharacterState, report: Dictionary) -> void. It changes the character and records
## what it did in `report`. The order comes from data/misostory/death.json rules.order; each name there must be a
## registered rule. Built in:
##   exp_penalty     Progression.apply_death_penalty (MeowDB's model, canonical formulas/death.json)
##   respawn_vitals  HP/MP after the respawn (death.json respawn_vitals, an adaptation: MeowDB gap)
## Later penalties (items, buffs, a Safety Charm that cancels the EXP loss) register a rule with register_rule()
## and add its name to rules.order; nothing else changes.
##
##   var rules := DeathRules.from_db(Data.db)
##   rules.apply(character)                        # MapSession.death_commit -> DeathController.commit_rules
##   rules.last_report                             # {"applied", "exp_before", "exp_lost", "hp", "mp", ...}

const TABLE := "death"
const RULE_EXP_PENALTY := "exp_penalty"
const RULE_RESPAWN_VITALS := "respawn_vitals"
## Ways respawn_vitals can set HP or MP (death.json respawn_vitals.hp/mp.mode).
const MODE_FIXED := "fixed"
const MODE_FRACTION := "fraction_of_max"
const MODE_FULL := "full"
const MODE_KEEP := "keep"
const VITAL_MODES: PackedStringArray = [MODE_FIXED, MODE_FRACTION, MODE_FULL, MODE_KEEP]

var db: ContentDB = null
## Rule names in the order they run.
var order: PackedStringArray = []
## Problems found in the table or while applying (unknown rule, bad mode, missing table).
var errors: PackedStringArray = []
## The report of the last apply().
var last_report: Dictionary = {}
## How many times apply() has run (tests use it to check a death's penalty is applied exactly once).
var applied_count: int = 0

var _rules: Dictionary = {}


## Rules from data/misostory/death.json (order and respawn vitals) with the built-in rules registered.
static func from_db(p_db: ContentDB) -> DeathRules:
	var r := DeathRules.new(p_db)
	var t := r.table()
	if t.is_empty():
		r.errors.append("data/misostory/death.json is not loaded")
		return r
	var o: Variant = (t.get("rules", {}) as Dictionary).get("order", [])
	if o is Array:
		for n: Variant in o:
			r.order.append(str(n))
	r.errors.append_array(r.validate())
	return r


func _init(p_db: ContentDB = null) -> void:
	db = p_db
	register_rule(RULE_EXP_PENALTY, _exp_penalty, false)
	register_rule(RULE_RESPAWN_VITALS, _respawn_vitals, false)


## Registers (or replaces) a rule. append_to_order adds its name to the end of `order` when it is not there yet.
func register_rule(rule_name: String, rule: Callable, append_to_order: bool = true) -> void:
	_rules[rule_name] = rule
	if append_to_order and not (rule_name in order):
		order.append(rule_name)


func has_rule(rule_name: String) -> bool:
	return _rules.has(rule_name)


## Applies every rule in `order` to the character and returns the report:
## {"applied": [names], "exp_before", "level_before", "hp_before", "mp_before", plus what each rule adds:
##  exp_penalty -> "exp_lost"; respawn_vitals -> "hp", "mp"}.
func apply(c: CharacterState) -> Dictionary:
	var report := {"applied": [], "exp_before": c.exp, "level_before": c.level, "hp_before": c.hp, "mp_before": c.mp}
	for rule_name in order:
		var rule: Callable = _rules.get(rule_name, Callable())
		if not rule.is_valid():
			var why := "death rule '%s' is not registered" % rule_name
			if not (why in errors):
				errors.append(why)
			push_error("[DeathRules] " + why)
			continue
		rule.call(c, report)
		(report["applied"] as Array).append(rule_name)
	last_report = report
	applied_count += 1
	return report


## Problems in the table: unknown rule names, bad vital modes or values.
func validate() -> PackedStringArray:
	var out: PackedStringArray = []
	for rule_name in order:
		if not _rules.has(rule_name):
			out.append("death.json rules.order names an unknown rule '%s'" % rule_name)
	var vitals := respawn_vitals()
	for key in ["hp", "mp"]:
		var spec: Variant = vitals.get(key, null)
		if not (spec is Dictionary):
			out.append("death.json respawn_vitals.%s is missing" % key)
			continue
		var mode := str((spec as Dictionary).get("mode", ""))
		if not (mode in VITAL_MODES):
			out.append("death.json respawn_vitals.%s.mode '%s' is not one of %s" % [key, mode, ", ".join(VITAL_MODES)])
		elif mode in [MODE_FIXED, MODE_FRACTION] and not _is_number((spec as Dictionary).get("value", null)):
			out.append("death.json respawn_vitals.%s.value must be a number for mode %s" % [key, mode])
	return out


## data/misostory/death.json ({} when missing).
func table() -> Dictionary:
	if db == null:
		return {}
	var t: Variant = db.miso_table(TABLE)
	return t if t is Dictionary else {}


## death.json respawn_vitals ({} when missing).
func respawn_vitals() -> Dictionary:
	var v: Variant = table().get("respawn_vitals", {})
	return v if v is Dictionary else {}


## A vital after the respawn: `spec` is {"mode", "value"?}, `current` the value at death, `maximum` the derived max.
static func vital_value(spec: Dictionary, current: int, maximum: int) -> int:
	var value := current
	match str(spec.get("mode", MODE_KEEP)):
		MODE_FIXED:
			value = mini(int(spec.get("value", 0)), maximum)
		MODE_FRACTION:
			value = int(floor(float(spec.get("value", 0.0)) * maximum))
		MODE_FULL:
			value = maximum
		_:
			value = current
	return clampi(value, 0, maxi(maximum, 0))


# --- built-in rules -------------------------------------------------------------------------------------------

## Canonical EXP loss (MeowDB's model): floor(EXP to next level x (5 + 20 / base LUK) / 100), EXP never below 0.
func _exp_penalty(c: CharacterState, report: Dictionary) -> void:
	report["exp_lost"] = Progression.apply_death_penalty(c, db)


## HP/MP after the respawn (adaptation). HP is at least 1, so the player never respawns dead.
func _respawn_vitals(c: CharacterState, report: Dictionary) -> void:
	var vitals := respawn_vitals()
	var max_hp := StatCalculator.max_hp(c, db)
	var max_mp := StatCalculator.max_mp(c, db)
	var hp_spec: Dictionary = vitals.get("hp", {}) if vitals.get("hp", {}) is Dictionary else {}
	var mp_spec: Dictionary = vitals.get("mp", {}) if vitals.get("mp", {}) is Dictionary else {}
	c.hp = maxi(1, vital_value(hp_spec, c.hp, max_hp)) if max_hp > 0 else c.hp
	c.mp = vital_value(mp_spec, c.mp, max_mp)
	report["hp"] = c.hp
	report["mp"] = c.mp


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
