class_name Progression
extends RefCounted
## CONTRACT, owned by the character/combat rules system (signatures of exp_to_next / gain_exp /
## apply_death_penalty / allocate_ap are fixed; everything else is additive).
##
## Levels, EXP, AP/SP gains, HP/MP growth and the death EXP penalty, all from canonical formulas
## (formulas/exp_table.json, formulas/beginner.json, formulas/hp_mp_gain.json, formulas/death.json) plus the
## MisoStory adaptations in data/misostory/combat.json (level_up, beginner_sp_after_level_10, ap_allocation).
## Pure rules: they mutate the CharacterState they are given and never emit signals; callers announce the results
## (Events.exp_gained, leveled_up, stats_changed, hp_changed ...).


## EXP needed to go from `level` to level + 1 (0 at the cap). MeowDB's table is "EXP to next level", not cumulative.
static func exp_to_next(level: int, db: ContentDB) -> int:
	if level < 1 or level >= level_cap(db):
		return 0
	return int(_exp_row(level, db).get("exp_to_next", 0))


## Adds EXP, applying every level-up it causes (one large award can raise several levels; the excess carries into
## the new level, MisoStory adaptation). Returns {"levels_gained": int, "new_level": int, "exp_added": int} plus
## "ap_gained", "sp_gained", "max_hp_gained", "max_mp_gained". At the level cap EXP no longer accumulates.
static func gain_exp(c: CharacterState, amount: int, db: ContentDB) -> Dictionary:
	var out := {"levels_gained": 0, "new_level": c.level, "exp_added": 0, "ap_gained": 0, "sp_gained": 0,
		"max_hp_gained": 0, "max_mp_gained": 0}
	var cap := level_cap(db)
	if amount <= 0 or c.level >= cap:
		return out
	var rules := CombatRules.of(db).adaptation("level_up")
	var carry := String(rules.get("exp_overflow", "carry")) == "carry"
	var multiple := bool(rules.get("multiple_levels_per_gain", true))
	c.exp += amount
	var added := amount
	while c.level < cap:
		var need := exp_to_next(c.level, db)
		if need <= 0 or c.exp < need:
			break
		c.exp = c.exp - need if carry else 0
		var g := apply_level_up(c, db)
		out["levels_gained"] += 1
		out["ap_gained"] += int(g["ap"])
		out["sp_gained"] += int(g["sp"])
		out["max_hp_gained"] += int(g["max_hp"])
		out["max_mp_gained"] += int(g["max_mp"])
		if not multiple:
			var next_need := exp_to_next(c.level, db)
			if next_need > 0 and c.exp >= next_need:
				added -= c.exp - (next_need - 1)
				c.exp = next_need - 1
			break
	if c.level >= cap:
		added -= c.exp
		c.exp = 0
	out["new_level"] = c.level
	out["exp_added"] = added
	return out


## Applies the canonical death EXP penalty. Returns the EXP lost (never more than the character has).
static func apply_death_penalty(c: CharacterState, db: ContentDB) -> int:
	var loss := death_exp_loss(c.level, c.get_base_stat("luk"), db)
	var before := c.exp
	c.exp = maxi(0, c.exp - loss)
	return before - c.exp


## Spends `amount` unspent AP into a base stat ("str", "dex", "int", "luk"). Returns false if not allowed.
## With `db`, the allowed stats come from formulas/beginner.json ap.allocatable_stats; without it,
## CharacterState.STAT_KEYS (the same four). AP never goes into Max HP / Max MP (misostory/combat.json ap_allocation).
static func allocate_ap(c: CharacterState, stat: String, amount: int = 1, db: ContentDB = null) -> bool:
	if amount <= 0 or c.ap < amount:
		return false
	var key := stat.to_lower()
	var allowed: PackedStringArray = CharacterState.STAT_KEYS
	if db != null:
		allowed = PackedStringArray((db.formula("beginner").get("ap", {}) as Dictionary).get("allocatable_stats", []))
	if key not in allowed:
		return false
	c.base_stats[key] = c.get_base_stat(key) + amount
	c.ap -= amount
	return true


# --- additions ------------------------------------------------------------------------------------------------

## The game's level cap (formulas/exp_table.json level_cap: 100).
static func level_cap(db: ContentDB) -> int:
	return int(db.formula("exp_table").get("level_cap", 0))


## Raises the character one level: +AP, +SP, base Max HP/MP gains, then the level-up heal. Returns the gains
## {"ap", "sp", "max_hp", "max_mp"}.
static func apply_level_up(c: CharacterState, db: ContentDB) -> Dictionary:
	c.level += 1
	var g := level_up_gains(c.job, c.level, db)
	c.ap += int(g["ap"])
	c.sp += int(g["sp"])
	c.base_max_hp += int(g["max_hp"])
	c.base_max_mp += int(g["max_mp"])
	if String(CombatRules.of(db).adaptation("level_up").get("heal", "")) == "full":
		c.hp = StatCalculator.max_hp(c, db)
		c.mp = StatCalculator.max_mp(c, db)
	return g


## What reaching `new_level` grants a job: {"ap", "sp", "max_hp", "max_mp"}.
## AP: beginner.json ap.ap_per_level (Total AP = 25 + 5 x (Level - 1) holds for every class).
## SP: a Beginner gets sp_per_level at levels sp_levels[0]..sp_levels[1] (2-10), then the combat.json adaptation.
##     Job SP (1 + 3 per level after an advancement) is not in the canonical JSON yet, so other classes get 0 here.
## HP/MP: hp_mp_gain.json per_class rates (flat, zero variance).
static func level_up_gains(job: String, new_level: int, db: ContentDB) -> Dictionary:
	var beginner := db.formula("beginner")
	var cls := StatCalculator.job_class(job)
	var ap := int((beginner.get("ap", {}) as Dictionary).get("ap_per_level", 0))
	var sp := 0
	if cls == "beginner":
		var sp_rule: Dictionary = beginner.get("sp", {})
		var sp_levels: Array = sp_rule.get("sp_levels", [])
		if sp_levels.size() == 2 and new_level >= int(sp_levels[0]) and new_level <= int(sp_levels[1]):
			sp = int(sp_rule.get("sp_per_level", 0))
		elif sp_levels.size() == 2 and new_level > int(sp_levels[1]):
			sp = int(CombatRules.of(db).adaptation("beginner_sp_after_level_10").get("sp_per_level", 0))
	var rates: Dictionary = (db.formula("hp_mp_gain").get("per_class", {}) as Dictionary).get(cls, {})
	if rates.is_empty():
		push_error("[Progression] no HP/MP growth for class '%s'" % cls)
	return {"ap": ap, "sp": sp, "max_hp": int(rates.get("max_hp_per_level", 0)), "max_mp": int(rates.get("max_mp_per_level", 0))}


## Base Max HP/MP of a job at a level (MeowDB "Total HP and MP" before gear):
##   Beginner: 50 + 16 x (Level - 1), 5 + 12 x (Level - 1)
##   Job: 50 + 16 x B + HPAdv x A + HPPerLevel x C, B = min(Level, 10) - 1, C = max(0, Level - 10),
##        A = 1 + [2nd job at Lv 30+] + [3rd job at Lv 70+] (StatCalculator.job_advancements)
## Returns {"max_hp", "max_mp"}.
static func base_max_hp_mp(job: String, level: int, db: ContentDB) -> Dictionary:
	return class_base_max_hp_mp(StatCalculator.job_class(job), level, StatCalculator.job_advancements(job), db)


## base_max_hp_mp for a class ("beginner", "warrior", ...) that has taken `advancements` job advancements.
static func class_base_max_hp_mp(cls: String, level: int, advancements: int, db: ContentDB) -> Dictionary:
	var gain := db.formula("hp_mp_gain")
	var start: Dictionary = gain.get("starting", {})
	var per_class: Dictionary = gain.get("per_class", {})
	var adv_levels: Dictionary = gain.get("advancement_levels", {})
	var lvl := maxi(1, level)
	var base_hp := int(start.get("base_hp", 0))
	var base_mp := int(start.get("base_mp", 0))
	var beg: Dictionary = per_class.get("beginner", {})
	var first := int(adv_levels.get("first_job", 0))
	if cls == "beginner" or advancements <= 0 or lvl < first:
		return {"max_hp": base_hp + int(beg.get("max_hp_per_level", 0)) * (lvl - 1),
			"max_mp": base_mp + int(beg.get("max_mp_per_level", 0)) * (lvl - 1)}
	var b := mini(lvl, first) - 1
	var cc := maxi(0, lvl - first)
	var adv := advancements
	var a := 1
	if adv >= 2 and lvl >= int(adv_levels.get("second_job", 0)):
		a += 1
	if adv >= 3 and lvl >= int(adv_levels.get("third_job", 0)):
		a += 1
	var rates: Dictionary = per_class.get(cls, {})
	return {
		"max_hp": base_hp + int(beg.get("max_hp_per_level", 0)) * b + int(rates.get("max_hp_per_advancement", 0)) * a + int(rates.get("max_hp_per_level", 0)) * cc,
		"max_mp": base_mp + int(beg.get("max_mp_per_level", 0)) * b + int(rates.get("max_mp_per_advancement", 0)) * a + int(rates.get("max_mp_per_level", 0)) * cc,
	}


## Total AP a character has earned by `level` (Total AP = 25 + 5 x (Level - 1), the starting 16 included).
static func total_ap(level: int, db: ContentDB) -> int:
	var ap: Dictionary = db.formula("beginner").get("ap", {})
	return int(ap.get("total_ap_at_level_1", 0)) + int(ap.get("ap_per_level", 0)) * (maxi(1, level) - 1)


## Sets up a fresh character as MeowDB's Beginner at creation: level 1, 0 EXP, 4/4/4/4, the 9 creation AP unspent,
## 0 SP, base HP/MP 50/5 and full vitals.
static func init_new_character(c: CharacterState, db: ContentDB) -> void:
	var b := db.formula("beginner")
	c.job = String(b.get("class_slug", "beginner"))
	c.level = int(b.get("starting_level", 1))
	c.exp = 0
	var start: Dictionary = b.get("starting_stats", {})
	for k in CharacterState.STAT_KEYS:
		c.base_stats[k] = int(start.get(k, 0))
	c.ap = int(b.get("creation_ap", 0))
	c.sp = 0
	var hm := base_max_hp_mp(c.job, c.level, db)
	c.base_max_hp = int(hm["max_hp"])
	c.base_max_mp = int(hm["max_mp"])
	c.hp = StatCalculator.max_hp(c, db)
	c.mp = StatCalculator.max_mp(c, db)


## Death EXP loss (MeowDB's model): floor(EXP to next level x (5 + 20 / LUK) / 100), LUK = base LUK clamped to the
## calculator's 4..999. 0 at the level cap.
static func death_exp_loss(level: int, base_luk: int, db: ContentDB) -> int:
	var pen: Dictionary = db.formula("death").get("exp_penalty", {})
	var lclamp: Array = pen.get("calculator_luk_clamp", [])
	var luk := base_luk
	if lclamp.size() == 2:
		luk = clampi(base_luk, int(lclamp[0]), int(lclamp[1]))
	if luk <= 0:
		push_error("[Progression] death penalty needs a positive LUK")
		return 0
	var need := float(exp_to_next(level, db))
	var pct := float(pen.get("base_loss_pct", 0)) + float(pen.get("luk_term_numerator", 0)) / luk
	return floori(need * pct / 100.0)


## The character dies when HP reaches 0 (formulas/death.json death_trigger).
static func is_dead(c: CharacterState, db: ContentDB) -> bool:
	return c.hp <= int((db.formula("death").get("death_trigger", {}) as Dictionary).get("dies_when_hp_reaches", 0))


## Total EXP earned from level 1 at (level, exp): sum of exp_to_next over earlier levels + exp (-1 if invalid).
static func total_exp_at(level: int, exp_value: int, db: ContentDB) -> int:
	if level < 1 or level > level_cap(db):
		return -1
	var total := 0
	for l in range(1, level):
		total += exp_to_next(l, db)
	return total + maxi(0, exp_value)


## "Total from Lv 1": all the EXP needed to reach level + 1 from level 1 (exp_table.json total_from_lv1).
static func cumulative_exp_through(level: int, db: ContentDB) -> int:
	return int(_exp_row(clampi(level, 1, level_cap(db) - 1), db).get("total_from_lv1", 0))


## MeowDB's EXP calculator: EXP still needed from (current_level, current_exp) to reach target_level.
## {"ok": true, "result": {"currentLevel", "targetLevel", "currentExp", "currentLevelRequirement", "expRemaining",
## "levelsRemaining", "confidence"}} or {"ok": false, "error": "currentLevel" | "targetLevel" | "currentExp"}.
static func exp_remaining(current_level: int, current_exp: int, target_level: int, db: ContentDB) -> Dictionary:
	var cap := level_cap(db)
	if current_level < 1 or current_level >= cap:
		return {"ok": false, "error": "currentLevel"}
	if target_level <= current_level or target_level > cap:
		return {"ok": false, "error": "targetLevel"}
	var req := exp_to_next(current_level, db)
	if current_exp < 0 or current_exp >= req:
		return {"ok": false, "error": "currentExp"}
	var conf: Dictionary = db.formula("exp_table").get("confidence", {})
	var current_levels: Array = conf.get("current_levels", [1, 0])
	return {"ok": true, "result": {
		"currentLevel": current_level,
		"targetLevel": target_level,
		"currentExp": current_exp,
		"currentLevelRequirement": req,
		"expRemaining": total_exp_at(target_level, 0, db) - total_exp_at(current_level, current_exp, db),
		"levelsRemaining": target_level - current_level,
		# Reaching target_level uses the EXP rows up to target_level - 1.
		"confidence": "current" if target_level - 1 <= int(current_levels[1]) else "historical",
	}}


## Kills of a monster worth `monster_exp` needed for `exp_needed` (no level or party modifiers); -1 if invalid.
static func kills_needed(exp_needed: int, monster_exp: int) -> int:
	if exp_needed < 0 or monster_exp <= 0:
		return -1
	return ceili(float(exp_needed) / monster_exp)


static func _exp_row(level: int, db: ContentDB) -> Dictionary:
	var levels: Array = db.formula("exp_table").get("levels", [])
	if level >= 1 and level <= levels.size():
		var row: Dictionary = levels[level - 1]
		if int(row.get("level", -1)) == level:
			return row
	for row in levels:
		if int((row as Dictionary).get("level", -1)) == level:
			return row
	return {}
