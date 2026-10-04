class_name CombatRules
extends RefCounted
## Typed snapshot of every number the combat and character rules use, read once per ContentDB.
##
## Canonical values come from game/data/canonical/formulas/*.json (MeowDB MS Classic); MisoStory adaptations come
## from game/data/misostory/combat.json. Nothing here is a literal gameplay number: a missing field is reported with
## push_error (and listed in `errors`) instead of being replaced by a remembered value.
##
## Get it with CombatRules.of(db); the instance is cached per ContentDB, so stage functions can call it freely.

static var _cache: Dictionary = {}

## Fields that were missing or malformed in the data (empty when the data is complete).
var errors: PackedStringArray = []

# --- physical damage (formulas/damage.json "physical") ---------------------------------------------------------
var base_roll_min: float = 0.0
var base_roll_max: float = 0.0
var stat_div: float = 0.0
var ap_div: float = 0.0
var mastery_level_min: int = 0
var mastery_level_max: int = 0
## Published M for MasteryLevel 0; pins the mastery formula (see CombatFormula.mastery_factor).
var no_mastery_factor: float = 0.0
## family key -> {"primary": PackedStringArray, "secondary": PackedStringArray} (lower-case stat keys).
var weapon_families: Dictionary = {}
## multiplier row key -> {"swing": float or null, "stab": ..., "shoot": ..., "mixed": ...}.
var action_multipliers: Dictionary = {}
## odds row key -> {"swing": float, "stab": float} as probabilities 0-1 (MeowDB null = 0).
var action_odds: Dictionary = {}
## special branch key -> its damage.json dictionary (lucky_seven, ranged_projectile, crouched_attack ...).
var special_branches: Dictionary = {}

# --- magic -------------------------------------------------------------------------------------------------------
## Magic derived from INT: floor(INT / magic_int_divisor) (derived_stats.json formulas.magic).
var magic_int_divisor: float = 0.0

# --- defense, elements, level gap, critical, clamp -------------------------------------------------------------
var element_single: Dictionary = {}
var element_codes: Dictionary = {}
var element_composition_coefficient: float = 0.0
var element_other_multiplier: float = 1.0
## Level gap: gap <= 0 -> 1; small_min..small_max -> 1 / (1 + gap^2 * small_coef); >= large_min -> 1 / (1 + gap * large_coef).
var level_gap_small_min: int = 0
var level_gap_small_max: int = 0
var level_gap_small_coefficient: float = 0.0
var level_gap_large_min: int = 0
var level_gap_large_coefficient: float = 0.0
var crit_rate_base: float = 0.0
var crit_damage_base: float = 0.0
var damage_clamp_min: float = 0.0
var damage_clamp_max: float = 0.0

# --- outgoing hit check (formulas/accuracy.json "outgoing_hit") -----------------------------------------------
var hit_acc_scale: float = 0.0
var hit_level_gap_coefficient: float = 0.0
var hit_base_divisor: float = 0.0
var hit_spread_base: float = 0.0
var hit_spread_extra: float = 0.0
var hit_spread_scale: float = 0.0
var auto_hit_base: float = 0.0
var auto_hit_player_level_coefficient: float = 0.0
var auto_hit_per_gap_constant: float = 0.0

# --- incoming (formulas/accuracy.json "incoming_hit", "incoming_damage", after_hit) ------------------------------
var in_acc_scale: float = 0.0
var in_level_base: float = 0.0
var in_level_multiplier: float = 0.0
var in_eva_soft_cap: float = 0.0
var in_eva_level_divisor: float = 0.0
var in_spread_base: float = 0.0
var in_spread_extra: float = 0.0
var in_spread_scale: float = 0.0
var in_far_miss_scale: float = 0.0
var in_far_miss_min: float = 0.0
var in_far_miss_max: float = 0.0
var in_minimum_hit_rescue: float = 0.0
var touch_attack_ratio: float = 0.0
var incoming_roll_min: float = 0.0
var incoming_roll_max: float = 0.0
var incoming_def_level_offset: float = 0.0
var incoming_def_level_multiplier: float = 0.0
var incoming_raw_coefficient: float = 0.0
var incoming_clamp_min: float = 0.0
var incoming_clamp_max: float = 0.0
var post_hit_invincibility_canonical_s: float = 0.0

# --- derived stats (formulas/accuracy.json, derived_stats.json) -------------------------------------------------
## job class -> {"divisor", "constant", "uses_common_term"} (accuracy.json derived_accuracy.by_job).
var acc_by_job: Dictionary = {}
var acc_dex_coefficient: float = 0.0
var acc_level_coefficient: float = 0.0
var acc_luk_coefficient: float = 0.0
var acc_magician_int_coefficient: float = 0.0
var eva_luk_divisor: float = 0.0
var eva_dex_divisor: float = 0.0
var eva_constant: float = 0.0
var wdef_str_divisor: float = 0.0
var mdef_int_divisor: float = 0.0

# --- attack timing (formulas/attack_speed.json) -----------------------------------------------------------------
var timing_tier_min: int = 0
var timing_tier_max: int = 0
var display_rounding_ms: int = 0
## base action key -> base_ms (swing, stab, spear_polearm_stab, bow_shot, crossbow_shot, crouched_attack, rush).
var base_action_ms: Dictionary = {}
## tier -> speed tier row (ordinary_attack_ms, spear_stab_ms, crossbow_ms ...).
var speed_tiers: Dictionary = {}

# --- movement caps (formulas/movement.json) ---------------------------------------------------------------------
var base_speed: int = 0
var base_jump: int = 0
var speed_cap: int = 0
var jump_cap: int = 0

## The raw adaptation table (data/misostory/combat.json); read through adaptation().
var adaptations: Dictionary = {}
## item id ("" = bare hands) -> WeaponProfile, filled by WeaponProfile.for_weapon_id (shared, treat as read-only).
var weapon_cache: Dictionary = {}


## The rules for a ContentDB (built on first use, then cached for that instance).
static func of(db: ContentDB) -> CombatRules:
	var key := db.get_instance_id()
	if _cache.has(key):
		var entry: Dictionary = _cache[key]
		var ref: WeakRef = entry["db"]
		if ref.get_ref() == db:
			return entry["rules"]
	var rules := CombatRules.new()
	rules._load(db)
	for k in _cache.keys():
		var old: WeakRef = _cache[k]["db"]
		if old.get_ref() == null:
			_cache.erase(k)
	_cache[key] = {"db": weakref(db), "rules": rules}
	return rules


## A section of data/misostory/combat.json (empty Dictionary when absent; the error is recorded).
func adaptation(section: String) -> Dictionary:
	var v: Variant = adaptations.get(section, null)
	if v is Dictionary:
		return v
	_fail("misostory/combat.json: missing section '%s'" % section)
	return {}


# --- loading ---------------------------------------------------------------------------------------------------

func _load(db: ContentDB) -> void:
	var dmg := db.formula("damage")
	var acc := db.formula("accuracy")
	var derived := db.formula("derived_stats")
	var speed := db.formula("attack_speed")
	var movement := db.formula("movement")
	var miso: Variant = db.miso_table("combat")
	adaptations = miso if miso is Dictionary else {}
	if adaptations.is_empty():
		_fail("misostory/combat.json is missing or empty")

	var phys: Dictionary = _dict(dmg, "physical")
	var roll: Dictionary = _dict(phys, "base_roll")
	base_roll_min = _num(roll, "min", "damage.physical.base_roll")
	base_roll_max = _num(roll, "max", "damage.physical.base_roll")
	var divs: Dictionary = _dict(phys, "ordinary_divisors")
	stat_div = _num(divs, "stat_div", "damage.physical.ordinary_divisors")
	ap_div = _num(divs, "ap_div", "damage.physical.ordinary_divisors")
	var mastery: Dictionary = _dict(phys, "mastery")
	var mclamp: Array = mastery.get("mastery_level_clamp", [])
	if mclamp.size() == 2:
		mastery_level_min = int(mclamp[0])
		mastery_level_max = int(mclamp[1])
	else:
		_fail("damage.physical.mastery.mastery_level_clamp")
	no_mastery_factor = _num(mastery, "no_mastery_factor", "damage.physical.mastery")
	for fam in phys.get("weapon_families", []):
		var f: Dictionary = fam
		weapon_families[String(f.get("key", ""))] = {
			"primary": _stat_list(f.get("primary", null)),
			"secondary": _stat_list(f.get("secondary", null)),
		}
	action_multipliers = _dict(phys, "weapon_action_multipliers").duplicate(true)
	for row_key in _dict(phys, "ordinary_action_odds"):
		var row: Dictionary = phys["ordinary_action_odds"][row_key]
		var swing_pct: Variant = row.get("swing_pct", null)
		var stab_pct: Variant = row.get("stab_pct", null)
		action_odds[row_key] = {
			"swing": 0.0 if swing_pct == null else float(swing_pct) / 100.0,
			"stab": 0.0 if stab_pct == null else float(stab_pct) / 100.0,
		}
	special_branches = _dict(phys, "special_branches").duplicate(true)

	var magic_f: Dictionary = _dict(_dict(derived, "formulas"), "magic")
	magic_int_divisor = _num(magic_f, "divisor", "derived_stats.formulas.magic")
	wdef_str_divisor = _num(_dict(_dict(derived, "formulas"), "wdef"), "divisor", "derived_stats.formulas.wdef")
	mdef_int_divisor = _num(_dict(_dict(derived, "formulas"), "mdef"), "divisor", "derived_stats.formulas.mdef")

	var elements: Dictionary = _dict(dmg, "elements")
	element_single = _dict(elements, "single_element_multiplier").duplicate()
	element_codes = _dict(elements, "composition_codes").duplicate()
	element_composition_coefficient = _num(elements, "composition_multiplier_coefficient", "damage.elements")
	element_other_multiplier = _num(elements, "other_result_multiplier", "damage.elements")

	for branch in _dict(dmg, "level_gap").get("branches", []):
		var b: Dictionary = branch
		var gap := String(b.get("gap", "")).strip_edges()
		if not b.has("coefficient"):
			continue
		var coef := float(b["coefficient"])
		if gap.begins_with(">="):
			level_gap_large_min = int(gap.trim_prefix(">=").strip_edges())
			level_gap_large_coefficient = coef
		elif "-" in gap:
			var parts := gap.split("-")
			level_gap_small_min = int(parts[0])
			level_gap_small_max = int(parts[1])
			level_gap_small_coefficient = coef
	if level_gap_small_coefficient == 0.0 or level_gap_large_coefficient == 0.0:
		_fail("damage.level_gap.branches")

	var crit: Dictionary = _dict(dmg, "critical")
	crit_rate_base = _num(crit, "base_rate_c", "damage.critical")
	crit_damage_base = _num(crit, "base_damage_d", "damage.critical")
	var fclamp: Dictionary = _dict(dmg, "final_clamp")
	damage_clamp_min = _num(fclamp, "min", "damage.final_clamp")
	damage_clamp_max = _num(fclamp, "max", "damage.final_clamp")

	var out_hit: Dictionary = _dict(acc, "outgoing_hit")
	var oc: Dictionary = _dict(out_hit, "constants")
	hit_acc_scale = _num(oc, "acc_scale", "accuracy.outgoing_hit.constants")
	hit_level_gap_coefficient = _num(oc, "level_gap_coefficient", "accuracy.outgoing_hit.constants")
	hit_base_divisor = _num(oc, "base_divisor", "accuracy.outgoing_hit.constants")
	hit_spread_base = _num(oc, "spread_base", "accuracy.outgoing_hit.constants")
	hit_spread_extra = _num(oc, "spread_extra", "accuracy.outgoing_hit.constants")
	hit_spread_scale = _num(oc, "spread_scale", "accuracy.outgoing_hit.constants")
	var ac: Dictionary = _dict(_dict(out_hit, "automatic_hit"), "constants")
	auto_hit_base = _num(ac, "base", "accuracy.outgoing_hit.automatic_hit.constants")
	auto_hit_player_level_coefficient = _num(ac, "player_level_coefficient", "accuracy.outgoing_hit.automatic_hit.constants")
	auto_hit_per_gap_constant = _num(ac, "per_gap_constant", "accuracy.outgoing_hit.automatic_hit.constants")

	var ic: Dictionary = _dict(_dict(acc, "incoming_hit"), "constants")
	in_acc_scale = _num(ic, "acc_scale", "accuracy.incoming_hit.constants")
	in_level_base = _num(ic, "level_base", "accuracy.incoming_hit.constants")
	in_level_multiplier = _num(ic, "level_multiplier", "accuracy.incoming_hit.constants")
	in_eva_soft_cap = _num(ic, "eva_soft_cap", "accuracy.incoming_hit.constants")
	in_eva_level_divisor = _num(ic, "eva_level_divisor", "accuracy.incoming_hit.constants")
	in_spread_base = _num(ic, "spread_base", "accuracy.incoming_hit.constants")
	in_spread_extra = _num(ic, "spread_extra", "accuracy.incoming_hit.constants")
	in_spread_scale = _num(ic, "spread_scale", "accuracy.incoming_hit.constants")
	in_far_miss_scale = _num(ic, "far_miss_scale", "accuracy.incoming_hit.constants")
	in_far_miss_min = _num(ic, "far_miss_min", "accuracy.incoming_hit.constants")
	in_far_miss_max = _num(ic, "far_miss_max", "accuracy.incoming_hit.constants")
	in_minimum_hit_rescue = _num(ic, "minimum_hit_rescue", "accuracy.incoming_hit.constants")
	var idmg: Dictionary = _dict(acc, "incoming_damage")
	touch_attack_ratio = _num(idmg, "touch_attack_ratio", "accuracy.incoming_damage")
	incoming_roll_min = _num(_dict(idmg, "roll"), "min", "accuracy.incoming_damage.roll")
	incoming_roll_max = _num(_dict(idmg, "roll"), "max", "accuracy.incoming_damage.roll")
	var curve: Dictionary = _dict(idmg, "defense_curve")
	incoming_def_level_offset = _num(curve, "def_level_offset", "accuracy.incoming_damage.defense_curve")
	incoming_def_level_multiplier = _num(curve, "def_level_multiplier", "accuracy.incoming_damage.defense_curve")
	incoming_raw_coefficient = _num(curve, "raw_coefficient", "accuracy.incoming_damage.defense_curve")
	incoming_clamp_min = _num(_dict(idmg, "clamp"), "min", "accuracy.incoming_damage.clamp")
	incoming_clamp_max = _num(_dict(idmg, "clamp"), "max", "accuracy.incoming_damage.clamp")
	post_hit_invincibility_canonical_s = _num(_dict(acc, "after_hit"), "post_hit_invincibility_s", "accuracy.after_hit")

	var dacc: Dictionary = _dict(acc, "derived_accuracy")
	for job in _dict(dacc, "by_job"):
		var j: Dictionary = dacc["by_job"][job]
		acc_by_job[job] = {
			"divisor": float(j.get("divisor", 0.0)),
			"constant": float(j.get("constant", 0.0)),
			"uses_common_term": bool(j.get("uses_common_term", true)),
		}
	var coefs: Dictionary = _dict(dacc, "stat_coefficients")
	acc_dex_coefficient = _num(coefs, "dex", "accuracy.derived_accuracy.stat_coefficients")
	acc_level_coefficient = _num(coefs, "level", "accuracy.derived_accuracy.stat_coefficients")
	acc_luk_coefficient = _num(coefs, "luk", "accuracy.derived_accuracy.stat_coefficients")
	acc_magician_int_coefficient = _num(coefs, "magician_int", "accuracy.derived_accuracy.stat_coefficients")
	var eva: Dictionary = _dict(acc, "avoidability")
	eva_luk_divisor = _num(eva, "luk_divisor", "accuracy.avoidability")
	eva_dex_divisor = _num(eva, "dex_divisor", "accuracy.avoidability")
	eva_constant = _num(eva, "constant", "accuracy.avoidability")

	var tclamp: Array = speed.get("timing_tier_clamp", [])
	if tclamp.size() == 2:
		timing_tier_min = int(tclamp[0])
		timing_tier_max = int(tclamp[1])
	else:
		_fail("attack_speed.timing_tier_clamp")
	display_rounding_ms = int(_num(speed, "display_rounding_ms", "attack_speed"))
	for k in _dict(speed, "base_action_times_ms"):
		base_action_ms[k] = int(speed["base_action_times_ms"][k].get("base_ms", 0))
	for row in speed.get("speed_tiers", []):
		var r: Dictionary = row
		speed_tiers[int(r.get("tier", -1))] = r
	if speed_tiers.is_empty():
		_fail("attack_speed.speed_tiers")

	base_speed = int(_num(movement, "base_speed", "movement"))
	base_jump = int(_num(movement, "base_jump", "movement"))
	speed_cap = int(_num(movement, "speed_cap", "movement"))
	jump_cap = int(_num(movement, "jump_cap", "movement"))


func _dict(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key, null)
	if v is Dictionary:
		return v
	_fail("missing object '%s'" % key)
	return {}


func _num(d: Dictionary, key: String, where: String) -> float:
	var v: Variant = d.get(key, null)
	if v is float or v is int:
		return float(v)
	_fail("%s.%s is not a number" % [where, key])
	return 0.0


## "STR + DEX" -> ["str", "dex"]; null -> [].
static func _stat_list(v: Variant) -> PackedStringArray:
	var out: PackedStringArray = []
	if v == null:
		return out
	for part in String(v).split("+"):
		var s := part.strip_edges().to_lower()
		if s != "":
			out.append(s)
	return out


func _fail(msg: String) -> void:
	errors.append(msg)
	push_error("[CombatRules] " + msg)
