class_name CombatFormula
extends RefCounted
## MisoStory's central MapleStory Classic combat mathematics (MeowDB "explaining the damage formula",
## /formulas/damage, /formulas/damage-taken, /formulas/attack-speed).
##
## Every stage is a separate static function so it can be unit-tested and parity-tested against MeowDB's own
## calculators (game/tests/data/parity_vectors.json). Outgoing pipeline, in MeowDB's documented order:
##   1 hit check        calculate_accuracy + roll_hit (+ the separate Darkness check)
##   2 raw roll         physical: TWO independent draws B and Q (roll_physical_damage); magic: one draw
##   3 defense          effective_defense + apply_defense
##   4 element          element_relation + element_multiplier / composition_multiplier + apply_element
##   5 level gap        level_scale + apply_level_scaling
##   6 critical         roll_critical + apply_critical (rate and damage are independent inputs)
##   7 skill modifiers  apply_skill_modifiers
##   8 final clamp      finalize_damage = trunc(clamp(v, 1, 99999))
## resolve_physical_hit / resolve_magic_hit / resolve_fixed_damage run the whole pipeline and return a DamageResult;
## resolve_monster_attack / resolve_monster_touch do the incoming side and return an IncomingResult.
##
## Numbers come from CombatRules (canonical formulas/*.json + data/misostory/combat.json). A few constants exist in
## MeowDB only inside a formula string (the mastery factor's /10 + 0.1 and x 0.8, the defense curve's 100, Shield
## Guard's 0.05 and 500, the timing scale (10 + tier) / 16); they are written here exactly as published, and
## tests/unit/test_combat_formula_pins.gd fails if the published formula text changes.
## Randomness always comes from the caller's RandomNumberGenerator; draw order is documented per function.

## attack_speed.json base action -> the published ladder column that times it (speed_tiers rows).
const LADDER_COLUMN: Dictionary = {
	"swing": "ordinary_attack_ms",
	"stab": "ordinary_attack_ms",
	"bow_shot": "ordinary_attack_ms",
	"spear_polearm_stab": "spear_stab_ms",
	"crossbow_shot": "crossbow_ms",
}


# =================================================================================================================
# Mastery
# =================================================================================================================

## M = (MasteryLevel / 10 + 0.1) x 0.8, MasteryLevel clamped to the published 0-10 (no mastery: M = 0.08).
static func mastery_factor(mastery_level: float, db: ContentDB) -> float:
	var r := CombatRules.of(db)
	var lvl := clampf(mastery_level, float(r.mastery_level_min), float(r.mastery_level_max))
	return (lvl / 10.0 + 0.1) * 0.8


# =================================================================================================================
# Stage 1: hit check (outgoing)
# =================================================================================================================

## Outgoing hit check terms (MeowDB /formulas "Chance to Hit"):
##   L = max(0, MobLevel - PlayerLevel); A = TotalACC x 100 / (10L + 255); D = A - MobEVA
##   f = 0.15 + 0.20 / (1 + exp(D / 12)); hit when A x R >= MobEVA with R = uniform(1 - f, 1 + f)
##   automatic hit when D >= 25 + L x (0.5 x PlayerLevel + 15)
## Edge cases follow MeowDB's calculator: MobEVA <= 0 always hits, TotalACC <= 0 never hits, levels floor at 1.
## Returns {"L", "A", "D", "f", "mob_eva", "auto_hit_threshold", "auto_hit", "always_hit", "never_hit", "chance"}
## (chance 0-1; auto_hit_threshold is the D the automatic hit needs).
static func calculate_accuracy(total_acc: float, player_level: int, mob_level: int, mob_eva: float, db: ContentDB,
		allow_auto_hit: bool = true) -> Dictionary:
	var r := CombatRules.of(db)
	var plv := maxi(1, player_level)
	var gap := maxi(0, maxi(1, mob_level) - plv)
	var acc := maxf(0.0, total_acc)
	var eva := maxf(0.0, mob_eva)
	var a := r.hit_acc_scale * acc / (r.hit_level_gap_coefficient * gap + r.hit_base_divisor)
	var d := a - eva
	var f := r.hit_spread_base + r.hit_spread_extra / (1.0 + exp(d / r.hit_spread_scale))
	var threshold := r.auto_hit_base + gap * (r.auto_hit_player_level_coefficient * plv + r.auto_hit_per_gap_constant)
	var out := {"L": gap, "A": a, "D": d, "f": f, "mob_eva": eva, "auto_hit_threshold": threshold, "auto_hit": false,
		"always_hit": false, "never_hit": false, "chance": 0.0}
	if eva <= 0.0:
		out["always_hit"] = true
		out["chance"] = 1.0
	elif acc <= 0.0:
		out["never_hit"] = true
	elif allow_auto_hit and d >= threshold:
		out["auto_hit"] = true
		out["chance"] = 1.0
	else:
		out["chance"] = clampf(_spread_probability(a, eva, f), 0.0, 1.0)
	return out


## Hit probability (0-1) of an outgoing attack; see calculate_accuracy.
static func outgoing_hit_chance(total_acc: float, player_level: int, mob_level: int, mob_eva: float, db: ContentDB,
		allow_auto_hit: bool = true) -> float:
	return float(calculate_accuracy(total_acc, player_level, mob_level, mob_eva, db, allow_auto_hit)["chance"])


## Rolls the documented hit test for calculate_accuracy() terms: R = uniform(1 - f, 1 + f), hit when A x R >= MobEVA.
## Draws one rng.randf() only when the outcome is not already decided (always/auto/never hit).
static func roll_hit(accuracy: Dictionary, rng: RandomNumberGenerator) -> bool:
	if bool(accuracy["always_hit"]) or bool(accuracy["auto_hit"]):
		return true
	if bool(accuracy["never_hit"]):
		return false
	return hit_succeeds(accuracy, draw_hit_spread(accuracy, rng))


## One draw of the hit spread R = uniform(1 - f, 1 + f).
static func draw_hit_spread(accuracy: Dictionary, rng: RandomNumberGenerator) -> float:
	var f: float = accuracy["f"]
	return (1.0 - f) + 2.0 * f * rng.randf()


## Whether a drawn spread R lands: always/auto hit, never with ACC 0, else A x R >= MobEVA.
static func hit_succeeds(accuracy: Dictionary, spread_r: float) -> bool:
	if bool(accuracy["always_hit"]) or bool(accuracy["auto_hit"]):
		return true
	if bool(accuracy["never_hit"]):
		return false
	return float(accuracy["A"]) * spread_r >= float(accuracy["mob_eva"])


## Darkness: "a separate miss check rolled after the attack hits": d = clamp(Darkness / 100, 0, 1), lands when
## v > d with v = uniform(0, 1). Draws once when darkness_pct > 0.
static func roll_darkness_lands(darkness_pct: float, rng: RandomNumberGenerator) -> bool:
	if darkness_pct <= 0.0:
		return true
	return rng.randf() > clampf(darkness_pct / 100.0, 0.0, 1.0)


## Total ACC needed for an outgoing hit chance of `target_pct` percent (MeowDB accuracy-sim milestones: 64-step
## bisection). 0 when the monster has no avoid; INF when unreachable.
static func acc_needed_for_hit_chance(target_pct: float, player_level: int, mob_level: int, mob_eva: float,
		db: ContentDB) -> float:
	if mob_eva <= 0.0:
		return 0.0
	var fn := func(acc: float) -> float:
		return 100.0 * outgoing_hit_chance(acc, player_level, mob_level, mob_eva, db)
	return _bisect(fn, target_pct, 4.0 * mob_eva)


# =================================================================================================================
# Stage 2: raw roll (physical)
# =================================================================================================================

## The damage.json branch for an action of a weapon: crouched attack, ranged projectile, close-range ranged
## swing/stab, or "ordinary".
static func default_branch(weapon: WeaponProfile, action: String) -> String:
	if action == "crouch":
		return "crouched_attack"
	if weapon != null and weapon.ranged:
		if action == "shoot":
			return "ranged_projectile"
		if action == "swing":
			return "close_range_ranged_swing"
		if action == "stab":
			return "close_range_ranged_stab"
	return "ordinary"


## Every raw-roll input for one action of the player's weapon. `branch` "" picks default_branch(); any key of
## damage.json special_branches (e.g. "lucky_seven", "drain") overrides the multiplier, divisors, base roll or
## mastery the branch publishes. skill_damage_pct is the skill's damage % (100 for a basic attack).
## A stats record without a weapon fights bare-handed (WeaponProfile.bare_hands).
static func physical_attack(stats: PlayerCombatStats, action: String, db: ContentDB, skill_damage_pct: float = 100.0,
		branch: String = "") -> PhysicalAttack:
	var r := CombatRules.of(db)
	var weapon := stats.weapon if stats.weapon != null else WeaponProfile.for_weapon_id("", db)
	var p := PhysicalAttack.new()
	p.action = action
	p.skill_scale = maxf(0.0, skill_damage_pct) / 100.0
	p.total_watk = maxf(0.0, float(stats.total_watk))
	p.primary = WeaponProfile.sum_stats(weapon.primary_stats, stats.totals)
	p.secondary = WeaponProfile.sum_stats(weapon.secondary_stats, stats.totals)
	p.attack_power = maxf(0.0, float(stats.attack_power))
	p.mastery = mastery_factor(stats.mastery_level, db)
	p.stat_div = r.stat_div
	p.ap_div = r.ap_div
	p.base_roll_min = r.base_roll_min
	p.base_roll_max = r.base_roll_max
	p.branch = branch if branch != "" else default_branch(weapon, action)
	var wm := weapon.multiplier(action)
	if p.branch != "ordinary":
		var b: Dictionary = r.special_branches.get(p.branch, {})
		if b.is_empty():
			push_error("[CombatFormula] unknown damage branch '%s'" % p.branch)
		if b.get("weapon_mult", null) != null:
			wm = float(b["weapon_mult"])
		if b.has("stat_div"):
			p.stat_div = float(b["stat_div"])
		if b.has("ap_div"):
			p.ap_div = float(b["ap_div"])
		if b.get("mastery_factor", null) != null:
			p.mastery = float(b["mastery_factor"])
		var roll: Variant = b.get("base_roll", null)
		if roll is Dictionary:
			p.base_roll_min = float(roll["min"])
			p.base_roll_max = float(roll["max"])
	if wm < 0.0:
		push_error("[CombatFormula] action '%s' is not used by %s" % [action, weapon.name])
		wm = 0.0
	p.weapon_mult = wm
	return p


## Raw physical damage for explicit unit draws (0-1) of the two independent rolls:
##   B = uniform(BaseMin, BaseMax) -> BaseMin + (BaseMax - BaseMin) x base_u
##   Q = uniform(Primary x M, Primary) -> Primary x (M + stat_u x (1 - M))
##   Raw = S x TotalWATK x (B + (Q x WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)
## (arithmetic order mirrors MeowDB's kernel J so results match its vectors bit for bit).
static func raw_physical_roll(p: PhysicalAttack, base_u: float, stat_u: float) -> float:
	var bu := clampf(base_u, 0.0, 1.0)
	var su := clampf(stat_u, 0.0, 1.0)
	var b := p.base_roll_min + (p.base_roll_max - p.base_roll_min) * bu
	var stat_term := (p.primary * p.weapon_mult * (p.mastery + su * (1.0 - p.mastery)) + p.secondary) / p.stat_div
	return (b + stat_term + p.attack_power / p.ap_div) * p.total_watk * p.skill_scale


## MIN (both draws at their low end), MAX (both high) and the exact pre-truncation average, before defense:
## {"min", "max", "avg"}. Mastery raises MIN only; W.ATK multiplies everything.
static func calculate_physical_range(p: PhysicalAttack) -> Dictionary:
	var lo := raw_physical_roll(p, 0.0, 0.0)
	var hi := raw_physical_roll(p, 1.0, 1.0)
	return {"min": lo, "max": hi, "avg": (lo + hi) / 2.0}


## One raw physical roll with TWO independent draws, base B first, then Q (never one uniform draw between MIN and
## MAX: the result is concentrated toward the middle of the window).
static func roll_physical_damage(p: PhysicalAttack, rng: RandomNumberGenerator) -> float:
	var base_u := rng.randf()
	var stat_u := rng.randf()
	return raw_physical_roll(p, base_u, stat_u)


# =================================================================================================================
# Stage 2: raw roll (magic)
# =================================================================================================================

## MagicTotal = floor(TotalINT / 2) + EquipmentMATK + ScrollMATK + BuffMATK (pass the MATK lines summed).
static func magic_total(total_int: float, matk_bonus: float, db: ContentDB) -> int:
	return floori(maxf(0.0, total_int) / CombatRules.of(db).magic_int_divisor) + int(matk_bonus)


## Raw spell damage for one unit draw u: S x MagicTotal x (1 + TotalINT x (M + u x (1 - M)) / 100).
## u = 0 gives MIN = S x MagicTotal x (1 + TotalINT x M / 100), u = 1 gives MAX = S x MagicTotal x (1 + TotalINT / 100).
static func raw_magic_roll(skill_power_pct: float, magic_total_value: float, total_int: float, mastery: float,
		u: float) -> float:
	var s := maxf(0.0, skill_power_pct) / 100.0
	return s * maxf(0.0, magic_total_value) * (1.0 + maxf(0.0, total_int) * (mastery + clampf(u, 0.0, 1.0) * (1.0 - mastery)) / 100.0)


## Ordinary spell window {"min", "max", "avg"} (no weapon multiplier, no LUK, no W.ATK).
static func calculate_magic_range(skill_power_pct: float, magic_total_value: float, total_int: float,
		spell_mastery_level: float, db: ContentDB) -> Dictionary:
	var m := mastery_factor(spell_mastery_level, db)
	var lo := raw_magic_roll(skill_power_pct, magic_total_value, total_int, m, 0.0)
	var hi := raw_magic_roll(skill_power_pct, magic_total_value, total_int, m, 1.0)
	return {"min": lo, "max": hi, "avg": (lo + hi) / 2.0}


## "Ordinary magic uses one uniform roll between MIN and MAX": one rng.randf() draw.
static func roll_magic_damage(skill_power_pct: float, magic_total_value: float, total_int: float,
		spell_mastery_level: float, rng: RandomNumberGenerator, db: ContentDB) -> float:
	var m := mastery_factor(spell_mastery_level, db)
	return raw_magic_roll(skill_power_pct, magic_total_value, total_int, m, rng.randf())


# =================================================================================================================
# Stage 3: defense
# =================================================================================================================

## EffectiveDEF = max(0, FlatBonus + trunc((1 + PercentBonus / 100) x BaseDEF)).
static func effective_defense(base_def: float, flat_bonus: float = 0.0, percent_bonus: float = 0.0) -> int:
	return maxi(0, int(flat_bonus) + int((1.0 + percent_bonus / 100.0) * base_def))


## Defended = Raw x 100 / (EffectiveDEF + 100); a full-defense-bypass proc returns Raw unchanged.
## Physical (WDEF) and magic (MDEF) use the same curve with different stats.
static func apply_defense(raw: float, effective_def: float, bypassed: bool = false) -> float:
	if bypassed:
		return raw
	return raw * (100.0 / (maxf(0.0, effective_def) + 100.0))


## Expected defended value with a bypass proc rate g: Raw x ((1 - g) x 100 / (EffectiveDEF + 100) + g).
static func apply_defense_expected(raw: float, effective_def: float, bypass_rate: float) -> float:
	var g := clampf(bypass_rate, 0.0, 1.0)
	return raw * (100.0 / (maxf(0.0, effective_def) + 100.0) * (1.0 - g) + g)


# =================================================================================================================
# Stage 4: element
# =================================================================================================================

## How a monster relates to an attack element: "immune", "resistant", "neutral" or "weak". Uses MeowDB's monster
## element strings ("|"-separated tokens: "<el>-immune", "<el>-strong" = resistant, "<el>" = weak); an attack with no
## element is always neutral.
static func element_relation(monster_element_raw: String, attack_element: String) -> String:
	if attack_element == "" or attack_element == "none":
		return "neutral"
	for token in monster_element_raw.split("|"):
		var t := String(token).strip_edges()
		if not t.begins_with(attack_element):
			continue
		if t.ends_with("-immune"):
			return "immune"
		if t.ends_with("-strong"):
			return "resistant"
		if t == attack_element:
			return "weak"
	return "neutral"


## Single-element multiplier: immune 0, resistant 0.75, neutral 1.0, weak 1.25 (any other result counts as 1.0).
static func element_multiplier(relation: String, db: ContentDB) -> float:
	var r := CombatRules.of(db)
	return float(r.element_single.get(relation, r.element_other_multiplier))


## Two-element composition: 0.25 x (Code(Element1) + Code(Element2)), codes immune 0 / resistant 1 / neutral 2 /
## weak 3. Together with the single multipliers this gives MeowDB's 7 results (0, 0.25, 0.5, 0.75, 1, 1.25, 1.5).
static func composition_multiplier(relation_a: String, relation_b: String, db: ContentDB) -> float:
	var r := CombatRules.of(db)
	if not (r.element_codes.has(relation_a) and r.element_codes.has(relation_b)):
		return r.element_other_multiplier
	return r.element_composition_coefficient * (float(r.element_codes[relation_a]) + float(r.element_codes[relation_b]))


static func apply_element(value: float, multiplier: float) -> float:
	return value * multiplier


# =================================================================================================================
# Stage 5: level gap
# =================================================================================================================

## Gap = MobLevel - PlayerLevel: 1 when Gap <= 0; 1 / (1 + Gap^2 x 0.005) for Gap 1-9; 1 / (1 + Gap x 0.05) for >= 10.
static func level_scale(player_level: int, mob_level: int, db: ContentDB) -> float:
	var r := CombatRules.of(db)
	var gap := mob_level - player_level
	if gap <= 0:
		return 1.0
	if gap < r.level_gap_large_min:
		return 1.0 / (1.0 + gap * gap * r.level_gap_small_coefficient)
	return 1.0 / (1.0 + r.level_gap_large_coefficient * gap)


static func apply_level_scaling(value: float, player_level: int, mob_level: int, db: ContentDB) -> float:
	return value * level_scale(player_level, mob_level, db)


# =================================================================================================================
# Stage 6: critical
# =================================================================================================================

## Base critical rate c and damage d before gear and passives (0.05 and 0.20).
static func base_crit_rate(db: ContentDB) -> float:
	return CombatRules.of(db).crit_rate_base


static func base_crit_damage(db: ContentDB) -> float:
	return CombatRules.of(db).crit_damage_base


## One critical draw: critical when rng.randf() < crit_rate (always one draw, as MeowDB's sampler does).
static func roll_critical(crit_rate: float, rng: RandomNumberGenerator) -> bool:
	return rng.randf() < clampf(crit_rate, 0.0, 1.0)


## Critical hit = Normal x (1 + d). Rate and damage are independent: the rate only decides is_critical.
static func apply_critical(value: float, is_critical: bool, crit_damage: float) -> float:
	return value * (1.0 + maxf(0.0, crit_damage)) if is_critical else value


## Expected with crit = Normal x (1 + c x d).
static func expected_with_critical(value: float, crit_rate: float, crit_damage: float) -> float:
	return value * (1.0 + clampf(crit_rate, 0.0, 1.0) * maxf(0.0, crit_damage))


# =================================================================================================================
# Stage 7-8: skill modifiers, final clamp
# =================================================================================================================

## Skill-specific multipliers applied after the critical step (Iron Arrow falloff, Shadow Partner share ...);
## the skill system computes `multiplier`. 1.0 for a basic attack.
static func apply_skill_modifiers(value: float, multiplier: float = 1.0) -> float:
	return value * maxf(0.0, multiplier)


## Final = trunc(clamp(value, 1, 99999)): a landed hit always deals at least 1.
static func finalize_damage(value: float, db: ContentDB) -> int:
	var r := CombatRules.of(db)
	return int(clampf(value, r.damage_clamp_min, r.damage_clamp_max))


# =================================================================================================================
# Ordinary attack action
# =================================================================================================================

## Picks an ordinary attack: the damage action from the weapon's odds (60% swing / 40% stab for most melee weapons;
## swing if rng.randf() < P(swing), as MeowDB's sampler does), then one of that action's presentations with equal
## odds (rng.randi_range). Draws only when there is a choice. Ranged weapons shoot unless close_range.
## Returns {"action": String, "presentation": String} ("presentation" is "" for a projectile).
static func choose_ordinary_action(weapon: WeaponProfile, rng: RandomNumberGenerator, close_range: bool = true) -> Dictionary:
	if weapon == null:
		push_error("[CombatFormula] choose_ordinary_action needs a WeaponProfile (WeaponProfile.bare_hands for no weapon)")
		return {"action": "", "presentation": ""}
	var actions := weapon.ordinary_actions(close_range)
	var action := ""
	if actions.size() == 1:
		action = String(actions.keys()[0])
	elif actions.size() > 1:
		var u := rng.randf()
		var acc_p := 0.0
		for a in ["swing", "stab"]:
			if not actions.has(a):
				continue
			acc_p += float(actions[a])
			action = a
			if u < acc_p:
				break
	var pres := weapon.presentations_for(action)
	var chosen := ""
	if pres.size() == 1:
		chosen = pres[0]
	elif pres.size() > 1:
		chosen = pres[rng.randi_range(0, pres.size() - 1)]
	return {"action": action, "presentation": chosen}


## The crouched (prone) attack of a weapon: {"action": "crouch", "presentation": "proneStab"}.
static func crouch_action(weapon: WeaponProfile) -> Dictionary:
	var pres := weapon.presentations_for("crouch")
	return {"action": "crouch", "presentation": pres[0] if pres.size() > 0 else ""}


# =================================================================================================================
# Full outgoing pipeline
# =================================================================================================================

## Resolves one physical hit of `action` ("swing", "stab", "shoot", "crouch") on a monster.
## options: "presentation" (hit-box name, recorded), "skill_pct" (100), "branch" ("" = default_branch),
## "allow_auto_hit" (true), "skill_multiplier" (1.0), "attack_element" (stats.physical_element).
## RNG draw order: hit R (only when the hit is not decided), Darkness (only with darkness), B, Q, bypass (only with
## a bypass rate), critical.
static func resolve_physical_hit(stats: PlayerCombatStats, target: MonsterCombatStats, action: String,
		rng: RandomNumberGenerator, db: ContentDB, options: Dictionary = {}) -> DamageResult:
	var res := DamageResult.new()
	res.kind = "physical"
	res.action = action
	res.presentation = String(options.get("presentation", ""))
	if not _hit_check(res, stats, target, rng, db, bool(options.get("allow_auto_hit", true))):
		return res
	var p := physical_attack(stats, action, db, float(options.get("skill_pct", 100.0)), String(options.get("branch", "")))
	var window := calculate_physical_range(p)
	res.range_min = window["min"]
	res.range_max = window["max"]
	res.base_roll_u = rng.randf()
	res.stat_roll_u = rng.randf()
	res.raw = raw_physical_roll(p, res.base_roll_u, res.stat_roll_u)
	_post_raw_stages(res, stats, target, false, String(options.get("attack_element", stats.physical_element)), rng, db,
		float(options.get("skill_multiplier", 1.0)), {})
	return res


## Resolves one spell hit: shared hit check, one uniform roll, MDEF, the spell's element, level gap, critical.
## options: "element" (""), "allow_auto_hit" (true), "skill_multiplier" (1.0).
static func resolve_magic_hit(stats: PlayerCombatStats, target: MonsterCombatStats, skill_power_pct: float,
		rng: RandomNumberGenerator, db: ContentDB, options: Dictionary = {}) -> DamageResult:
	var res := DamageResult.new()
	res.kind = "magic"
	res.action = "magic"
	if not _hit_check(res, stats, target, rng, db, bool(options.get("allow_auto_hit", true))):
		return res
	var window := calculate_magic_range(skill_power_pct, stats.magic_total, float(stats.totals.get("int", 0)), stats.spell_mastery_level, db)
	res.range_min = window["min"]
	res.range_max = window["max"]
	res.base_roll_u = rng.randf()
	res.raw = raw_magic_roll(skill_power_pct, stats.magic_total, float(stats.totals.get("int", 0)),
		mastery_factor(stats.spell_mastery_level, db), res.base_roll_u)
	_post_raw_stages(res, stats, target, true, String(options.get("element", "")), rng, db,
		float(options.get("skill_multiplier", 1.0)), {})
	return res


## Resolves a fixed-damage skill (Three Snails "0001000"): which stages apply comes from
## data/misostory/combat.json fixed_damage_skills[skill_id] (MeowDB documents only that stats, weapon and
## defense do not scale the value).
static func resolve_fixed_damage(stats: PlayerCombatStats, target: MonsterCombatStats, fixed_damage: float,
		skill_id: String, rng: RandomNumberGenerator, db: ContentDB) -> DamageResult:
	var flags: Dictionary = CombatRules.of(db).adaptation("fixed_damage_skills").get(skill_id, {})
	if flags.is_empty():
		push_error("[CombatFormula] no fixed_damage_skills entry for skill %s in misostory/combat.json" % skill_id)
	var res := DamageResult.new()
	res.kind = "fixed"
	res.action = "fixed"
	if bool(flags.get("hit_check", true)):
		if not _hit_check(res, stats, target, rng, db, true):
			return res
	res.raw = fixed_damage
	res.range_min = fixed_damage
	res.range_max = fixed_damage
	_post_raw_stages(res, stats, target, false, "", rng, db, 1.0, flags)
	return res


## MeowDB's per-hit {"min", "max", "avg"} for an attack against a target (null = no target: the character stat
## window). Mirrors the dmg-simulator: an ordinary attack takes the lowest MIN and highest MAX over its possible
## actions; avg is the odds-weighted midpoint taken through the same stages, clamped, untruncated, rounded to 0.1.
## options: "action" ("" = ordinary attack), "skill_pct" (100), "critical" (false: no crit; true: x (1 + d)),
## "close_range" (false: ranged weapons shoot, as MeowDB's window does).
static func damage_window(stats: PlayerCombatStats, target: MonsterCombatStats, db: ContentDB,
		options: Dictionary = {}) -> Dictionary:
	var action := String(options.get("action", ""))
	var weapon := stats.weapon if stats.weapon != null else WeaponProfile.for_weapon_id("", db)
	var actions: Dictionary = {action: 1.0} if action != "" else weapon.ordinary_actions(bool(options.get("close_range", false)))
	var lo := INF
	var hi := -INF
	var avg := 0.0
	for a in ["swing", "stab", "shoot", "mixed", "crouch"]:
		if not actions.has(a):
			continue
		var w := calculate_physical_range(physical_attack(stats, a, db, float(options.get("skill_pct", 100.0))))
		lo = minf(lo, float(w["min"]))
		hi = maxf(hi, float(w["max"]))
		avg += float(actions[a]) * float(w["avg"])
	var crit_d := stats.crit_damage if bool(options.get("critical", false)) else 0.0
	var r := CombatRules.of(db)
	return {
		"min": finalize_damage(_expected_post_raw(lo, stats, target, crit_d, db), db),
		"max": finalize_damage(_expected_post_raw(hi, stats, target, crit_d, db), db),
		"avg": round_tenth(clampf(_expected_post_raw(avg, stats, target, crit_d, db), r.damage_clamp_min, r.damage_clamp_max)),
	}


## Expected damage per hit including criticals, as MeowDB's simulator computes it: avg x (1 - c) + avg_crit x c
## (both averages already rounded to 0.1).
static func expected_damage_with_crit(stats: PlayerCombatStats, target: MonsterCombatStats, db: ContentDB,
		options: Dictionary = {}) -> float:
	var normal_opts := options.duplicate()
	normal_opts["critical"] = false
	var crit_opts := options.duplicate()
	crit_opts["critical"] = true
	var c := clampf(stats.crit_rate, 0.0, 1.0)
	return float(damage_window(stats, target, db, normal_opts)["avg"]) * (1.0 - c) + float(damage_window(stats, target, db, crit_opts)["avg"]) * c


## Math.round(10 x v) / 10 (MeowDB's 0.1 rounding of averages).
static func round_tenth(v: float) -> float:
	return floorf(v * 10.0 + 0.5) / 10.0


# =================================================================================================================
# Incoming: monster -> player
# =================================================================================================================

## Monster hit-chance terms (MeowDB /formulas/damage-taken "Chance a Monster Hits You"):
##   G = max(0, PlayerLevel - MobLevel); A = MobACC x 100 / (5 x (G + 51)); E = EVA / (1 + EVA / 80) / (1 + G / 40)
##   D = A - E; f = 0.15 + 0.20 / (1 + exp(D / 12)); Candidate = P(A x R >= E), R = uniform(1 - f, 1 + f)
##   if E > A x (1 + f): Candidate = clamp(exp((A - E) / 18) x 0.03, 0.02, 0.03)
##   Final = Candidate + (1 - Candidate) x 0.08 (the independent 8% minimum-hit rescue)
## MobACC <= 0 never hits. Returns {"G", "A", "E", "D", "f", "far_miss", "candidate", "chance"} (0-1).
static func incoming_hit(mob_acc: float, player_eva: float, player_level: int, mob_level: int, db: ContentDB) -> Dictionary:
	var r := CombatRules.of(db)
	var g := maxi(0, maxi(1, player_level) - maxi(1, mob_level))
	var a := r.in_acc_scale * maxf(0.0, mob_acc) / (r.in_level_multiplier * (g + r.in_level_base))
	var eva := maxf(0.0, player_eva)
	var e := eva / (1.0 + eva / r.in_eva_soft_cap) / (1.0 + g / r.in_eva_level_divisor)
	var d := a - e
	var f := r.in_spread_base + r.in_spread_extra / (1.0 + exp(d / r.in_spread_scale))
	var out := {"G": g, "A": a, "E": e, "D": d, "f": f, "far_miss": false, "candidate": 0.0, "chance": 0.0}
	if mob_acc <= 0.0:
		return out
	var cand := _spread_probability(a, e, f)
	if e > a * (1.0 + f):
		out["far_miss"] = true
		cand = clampf(r.in_far_miss_max * exp(d / r.in_far_miss_scale), r.in_far_miss_min, r.in_far_miss_max)
	out["candidate"] = cand
	out["chance"] = clampf(cand + (1.0 - cand) * r.in_minimum_hit_rescue, 0.0, 1.0)
	return out


static func incoming_hit_chance(mob_acc: float, player_eva: float, player_level: int, mob_level: int, db: ContentDB) -> float:
	return float(incoming_hit(mob_acc, player_eva, player_level, mob_level, db)["chance"])


## Rolls a monster's hit: the candidate test (R draw, or one chance draw in the far-miss branch), then, after a
## candidate miss, the independent minimum-hit rescue draw.
static func roll_incoming_hit(hit: Dictionary, rng: RandomNumberGenerator, db: ContentDB) -> bool:
	return bool(_roll_incoming(hit, rng, db)["landed"])


## The incoming hit roll with its draws: {"landed", "roll" (R, or the far-miss chance draw), "rescued"}.
static func _roll_incoming(hit: Dictionary, rng: RandomNumberGenerator, db: ContentDB) -> Dictionary:
	var out := {"landed": false, "roll": 0.0, "rescued": false}
	if float(hit["chance"]) <= 0.0:
		return out
	var landed := false
	if bool(hit["far_miss"]):
		out["roll"] = rng.randf()
		landed = float(out["roll"]) < float(hit["candidate"])
	else:
		var f: float = hit["f"]
		out["roll"] = (1.0 - f) + 2.0 * f * rng.randf()
		landed = float(hit["A"]) * float(out["roll"]) >= float(hit["E"])
	if not landed and rng.randf() < CombatRules.of(db).in_minimum_hit_rescue:
		landed = true
		out["rescued"] = true
	out["landed"] = landed
	return out


## Player EVA needed for a dodge rate of `target_pct` percent (MeowDB avoidability-sim milestones). INF when the
## 8% rescue makes it unreachable; 0 for a monster without accuracy.
static func avoid_needed_for_dodge(target_pct: float, mob_acc: float, player_level: int, mob_level: int,
		db: ContentDB) -> float:
	if mob_acc <= 0.0 or target_pct <= 0.0:
		return 0.0
	var fn := func(eva: float) -> float:
		return 100.0 - 100.0 * incoming_hit_chance(mob_acc, eva, player_level, mob_level, db)
	if fn.call(1e9) < target_pct:
		return INF
	return _bisect(fn, target_pct, 4.0 * mob_acc)


## ShieldGuardChance = 0 when ShieldWDEF <= 0, else max(0.05, ShieldWDEF / (ShieldWDEF + 500)).
static func shield_guard_chance(shield_wdef: float) -> float:
	if shield_wdef <= 0.0:
		return 0.0
	return maxf(0.05, shield_wdef / (shield_wdef + 500.0))


## When several guards are available the larger chance applies (Claw Guard etc. come from the skill system).
static func guard_chance(shield_wdef: float, other_guard_chance: float = 0.0) -> float:
	return maxf(shield_guard_chance(shield_wdef), clampf(other_guard_chance, 0.0, 1.0))


## EffectiveMobAttack = trunc(MobAttack x AttackRatio / 100) (touch hits: AttackRatio 100).
static func effective_mob_attack(mob_attack: float, attack_ratio_pct: float) -> int:
	return int(maxf(0.0, mob_attack) * attack_ratio_pct / 100.0)


## Roll = 1.1 + 0.4 x U for a unit draw U.
static func incoming_roll(u: float, db: ContentDB) -> float:
	var r := CombatRules.of(db)
	return r.incoming_roll_min + (r.incoming_roll_max - r.incoming_roll_min) * clampf(u, 0.0, 1.0)


## Taken = Raw x (1 - DEF / (DEF + 5 x (PlayerLevel + 40) + 1.2 x Raw)), Raw = EffectiveMobAttack x Roll.
static func incoming_taken(raw: float, def: float, player_level: int, db: ContentDB) -> float:
	var r := CombatRules.of(db)
	var d := maxf(0.0, def)
	var lvl := maxi(1, player_level)
	return raw * (1.0 - d / (d + r.incoming_def_level_multiplier * (lvl + r.incoming_def_level_offset) + r.incoming_raw_coefficient * raw))


## Elemental resistance (after defense, before the cap): Taken x (1 - Resist / 100).
static func apply_resistance(taken: float, resist_pct: float) -> float:
	return taken * (1.0 - resist_pct / 100.0)


## FinalTaken = trunc(clamp(Taken, 1, 50,000,000)).
static func finalize_incoming(taken: float, db: ContentDB) -> int:
	var r := CombatRules.of(db)
	return int(clampf(taken, r.incoming_clamp_min, r.incoming_clamp_max))


## MeowDB's incomingDamage kernel: raw and taken at U = 0, 0.5, 1 (rolls 1.1, 1.3, 1.5):
## {"raw_min", "raw_avg", "raw_max", "taken_min", "taken_avg", "taken_max", "base_attack"}. Note the kernel clamps a
## zero attack to 1; resolve_monster_attack deals 0 instead (oracles.md discrepancy 2, chosen 0).
static func incoming_damage_range(mob_attack: float, def: float, player_level: int, db: ContentDB) -> Dictionary:
	var atk := maxf(0.0, mob_attack)
	var out := {"base_attack": atk}
	var keys := {"min": 0.0, "avg": 0.5, "max": 1.0}
	for k in keys:
		var raw := atk * incoming_roll(float(keys[k]), db)
		out["raw_" + k] = int(raw)
		out["taken_" + k] = finalize_incoming(incoming_taken(raw, def, player_level, db), db)
	return out


## Resolves one monster attack on the player.
## options: "magic" (false), "attack_ratio" (touch ratio 100), "element" ("" = none), "regular" (true: guards
## apply), "kind" ("touch").
## Physical: hit roll with the 8% rescue -> guard -> roll -> WDEF curve -> resistance -> clamp.
## Magic: no evasion or guard ("magic bypasses the physical evasion and guard path") -> roll -> MDEF curve -> clamp.
## RNG draw order: candidate draw, rescue draw (after a candidate miss), guard draw (with a guard chance), U.
static func resolve_monster_attack(monster: MonsterCombatStats, player: PlayerCombatStats, rng: RandomNumberGenerator,
		db: ContentDB, options: Dictionary = {}) -> IncomingResult:
	var r := CombatRules.of(db)
	var res := IncomingResult.new()
	var magic := bool(options.get("magic", false))
	res.kind = String(options.get("kind", "magic" if magic else "touch"))
	res.effective_attack = effective_mob_attack(float(monster.mdmg if magic else monster.pdmg),
		float(options.get("attack_ratio", r.touch_attack_ratio)))
	if res.effective_attack <= 0:
		res.no_attack = true
		res.hit_chance = 0.0
		return res
	res.invincibility_s = post_hit_invincibility_s(db)
	var after_miss: bool = bool(r.adaptation("post_hit_invincibility").get("applies_after_miss_or_guard", true))
	var push := r.adaptation("player_knockback")
	if not magic:
		var hit := incoming_hit(monster.acc, player.avoid, player.level, monster.level, db)
		res.hit_chance = hit["chance"]
		res.candidate_chance = hit["candidate"]
		var rolled := _roll_incoming(hit, rng, db)
		res.hit_roll = rolled["roll"]
		res.rescued = rolled["rescued"]
		if not bool(rolled["landed"]):
			res.missed = true
			res.knockback = bool(push.get("on_miss_or_guard", false))
			if not after_miss:
				res.invincibility_s = 0.0
			return res
		if bool(options.get("regular", true)):
			res.guard_chance = guard_chance(player.shield_wdef, player.other_guard_chance)
			if res.guard_chance > 0.0 and rng.randf() < res.guard_chance:
				res.guarded = true
				res.knockback = bool(push.get("on_miss_or_guard", false))
				if not after_miss:
					res.invincibility_s = 0.0
				return res
	res.roll_u = rng.randf()
	res.roll = incoming_roll(res.roll_u, db)
	res.raw = res.effective_attack * res.roll
	res.def = player.mdef if magic else player.wdef
	res.after_defense = incoming_taken(res.raw, res.def, player.level, db)
	var element := String(options.get("element", ""))
	res.resist_pct = float(player.element_resist.get(element, 0.0)) if element != "" else 0.0
	res.after_resist = apply_resistance(res.after_defense, res.resist_pct)
	res.final = finalize_incoming(res.after_resist, db)
	res.knockback = bool(push.get("on_landed_hit", false)) and res.final > 0
	return res


## A monster's contact (touch) damage: physical, AttackRatio 100, no element.
static func resolve_monster_touch(monster: MonsterCombatStats, player: PlayerCombatStats, rng: RandomNumberGenerator,
		db: ContentDB) -> IncomingResult:
	return resolve_monster_attack(monster, player, rng, db, {"kind": "touch"})


# =================================================================================================================
# Reactions (canonical where published, MisoStory adaptations from data/misostory/combat.json otherwise)
# =================================================================================================================

## Seconds of player invincibility after a monster attack (canonical 1.5 s unless combat.json overrides it).
static func post_hit_invincibility_s(db: ContentDB) -> float:
	var r := CombatRules.of(db)
	var override: Variant = r.adaptation("post_hit_invincibility").get("override_s", null)
	return float(override) if override != null else r.post_hit_invincibility_canonical_s


## Whether a hit of `damage` staggers a monster with KB threshold `kb` ("a mob with 500 KB needs 500+ damage").
static func monster_staggers(damage: int, kb: int, db: ContentDB) -> bool:
	var rule := String(CombatRules.of(db).adaptation("monster_knockback").get("stagger_rule", ""))
	if rule != "damage_at_least_kb":
		push_error("[CombatFormula] unknown monster stagger rule '%s'" % rule)
		return false
	return damage > 0 and damage >= kb


## How long a staggered monster stays in its hit reaction (s): its canonical hit animation, else the fallback.
static func monster_stagger_s(monster: MonsterCombatStats, db: ContentDB) -> float:
	var mk := CombatRules.of(db).adaptation("monster_knockback")
	if String(mk.get("stagger_duration", "")) == "hit_animation" and monster.hit_animation_ms > 0:
		return monster.hit_animation_ms / 1000.0
	return float(mk.get("fallback_stagger_s", 0.0))


## Distance (px) a staggered monster is pushed away from the attacker (convert with WorldScale.h).
static func monster_knockback_distance_px(db: ContentDB) -> float:
	return float(CombatRules.of(db).adaptation("monster_knockback").get("knockback_distance_px", 0.0))


## The player's knockback: the canonical vertical model (formulas/movement.json knockback_airtime, px; convert with
## WorldScale.v) and the MisoStory horizontal push, whose single owner is the player controller's adaptation table
## (data/misostory/movement.json knockback_horizontal_speed_mps, already in m/s):
## {"horizontal_speed_mps", "upward_speed_px_s", "gravity_px_s2", "airtime_s"}.
static func player_knockback(db: ContentDB) -> Dictionary:
	var kb: Dictionary = db.formula("movement").get("knockback_airtime", {})
	var feel: Variant = db.miso_table("movement")
	var horizontal: Variant = (feel as Dictionary).get("knockback_horizontal_speed_mps", null) if feel is Dictionary else null
	if horizontal == null:
		push_error("[CombatFormula] data/misostory/movement.json knockback_horizontal_speed_mps is missing")
	return {
		"horizontal_speed_mps": float(horizontal) if horizontal != null else 0.0,
		"upward_speed_px_s": float(kb.get("upward_speed_px_per_s", 0.0)),
		"gravity_px_s2": float(kb.get("gravity_px_per_s2", 0.0)),
		"airtime_s": float(kb.get("same_height_airtime_s", 0.0)),
	}


# =================================================================================================================
# Attack timing (formulas/attack_speed.json)
# =================================================================================================================

## MeowDB's timing model applied to a whole base total: trunc(base x (10 + tier) / 16) with the tier clamped to
## 0-10, then rounded up to the 30 ms display step.
static func animation_time_ms(base_ms: float, tier: int, db: ContentDB) -> int:
	var r := CombatRules.of(db)
	var t := clampi(tier, r.timing_tier_min, r.timing_tier_max)
	var native := int(base_ms * (10 + t) / 16.0)
	var step := maxi(1, r.display_rounding_ms)
	return step * ceili(float(native) / step)


## Player-facing duration (ms) of one attack at a weapon speed tier, for an attack_speed.json base action
## ("swing", "stab", "spear_polearm_stab", "bow_shot", "crossbow_shot", "crouched_attack", "rush"). Uses MeowDB's
## published per-tier ladder where one exists (it is authoritative), the timing model otherwise.
static func attack_duration_ms(speed_tier: int, base_action: String, db: ContentDB) -> int:
	var r := CombatRules.of(db)
	var tiers := r.speed_tiers.keys()
	tiers.sort()
	var tier := clampi(speed_tier, int(tiers[0]), int(tiers[tiers.size() - 1]))
	var row: Dictionary = r.speed_tiers.get(tier, {})
	var column := String(LADDER_COLUMN.get(base_action, ""))
	if column != "" and row.get(column, null) != null:
		return int(row[column])
	if not r.base_action_ms.has(base_action):
		push_error("[CombatFormula] unknown base action '%s'" % base_action)
		return 0
	return animation_time_ms(float(r.base_action_ms[base_action]), tier, db)


# =================================================================================================================
# Internals
# =================================================================================================================

## P(A x R >= target) for R = uniform(1 - f, 1 + f) (MeowDB's shared probability helper).
static func _spread_probability(a: float, target: float, f: float) -> float:
	if a <= 0.0:
		return 1.0 if target <= 0.0 else 0.0
	var lo := 1.0 - f
	var hi := 1.0 + f
	var q := target / a
	if q <= lo:
		return 1.0
	if q >= hi:
		return 0.0
	return (hi - q) / (hi - lo)


## MeowDB's milestone search: double the bound until fn reaches target, then 64 bisection steps.
static func _bisect(fn: Callable, target: float, start: float) -> float:
	var hi := maxf(8.0, start)
	while float(fn.call(hi)) < target:
		hi *= 2.0
		if hi > 1e9:
			return INF
	var lo := 0.0
	for _i in 64:
		var mid := (lo + hi) / 2.0
		if float(fn.call(mid)) >= target:
			hi = mid
		else:
			lo = mid
	return hi


## Stage 1 for every outgoing kind. Returns false (and fills the miss) when the hit check fails.
static func _hit_check(res: DamageResult, stats: PlayerCombatStats, target: MonsterCombatStats,
		rng: RandomNumberGenerator, db: ContentDB, allow_auto_hit: bool) -> bool:
	var acc := calculate_accuracy(stats.acc, stats.level, target.level, target.avoid, db, allow_auto_hit)
	res.hit_chance = acc["chance"]
	res.auto_hit = acc["auto_hit"]
	var decided := bool(acc["always_hit"]) or bool(acc["auto_hit"]) or bool(acc["never_hit"])
	if not decided:
		res.hit_roll = draw_hit_spread(acc, rng)
	if not hit_succeeds(acc, res.hit_roll):
		res.missed = true
		res.miss_reason = "accuracy"
		return false
	if not roll_darkness_lands(stats.darkness_pct, rng):
		res.missed = true
		res.miss_reason = "darkness"
		return false
	return true


## Stages 3-8 on res.raw. `flags` (fixed-damage skills) can switch off "defense", "level_gap", "critical".
static func _post_raw_stages(res: DamageResult, stats: PlayerCombatStats, target: MonsterCombatStats, magic: bool,
		attack_element: String, rng: RandomNumberGenerator, db: ContentDB, skill_multiplier: float, flags: Dictionary) -> void:
	if bool(flags.get("defense", true)):
		if magic:
			res.effective_def = effective_defense(target.mdef, target.mdef_flat_bonus, target.mdef_percent_bonus)
		else:
			res.effective_def = effective_defense(target.pdef, target.pdef_flat_bonus, target.pdef_percent_bonus)
			if stats.defense_bypass_rate > 0.0:
				res.defense_bypassed = rng.randf() < stats.defense_bypass_rate
		res.after_defense = apply_defense(res.raw, res.effective_def, res.defense_bypassed)
	else:
		res.after_defense = res.raw
	res.element_multiplier = element_multiplier(element_relation(target.element_raw, attack_element), db)
	res.after_element = apply_element(res.after_defense, res.element_multiplier)
	res.level_scale = level_scale(stats.level, target.level, db) if bool(flags.get("level_gap", true)) else 1.0
	res.after_level = res.after_element * res.level_scale
	if bool(flags.get("critical", true)):
		res.critical = roll_critical(stats.crit_rate, rng)
	res.crit_multiplier = 1.0 + maxf(0.0, stats.crit_damage) if res.critical else 1.0
	res.after_critical = apply_critical(res.after_level, res.critical, stats.crit_damage)
	res.skill_multiplier = skill_multiplier
	res.after_skill = apply_skill_modifiers(res.after_critical, skill_multiplier)
	res.final = finalize_damage(res.after_skill, db)
	res.knockback = monster_staggers(res.final, target.kb, db)


## Stages 3-6 without randomness (no bypass proc, neutral element for a basic attack, crit only when crit_d > 0),
## as MeowDB's window computes them. target null = no defense and no level gap.
static func _expected_post_raw(raw: float, stats: PlayerCombatStats, target: MonsterCombatStats, crit_d: float,
		db: ContentDB) -> float:
	var v := raw
	if target != null:
		v = apply_defense_expected(v, effective_defense(target.pdef, target.pdef_flat_bonus, target.pdef_percent_bonus), stats.defense_bypass_rate)
		v = apply_element(v, element_multiplier(element_relation(target.element_raw, stats.physical_element), db))
		v = apply_level_scaling(v, stats.level, target.level, db)
	return apply_critical(v, crit_d > 0.0, crit_d)
