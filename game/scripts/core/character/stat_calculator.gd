class_name StatCalculator
extends RefCounted
## CONTRACT, owned by the character/combat rules system (signatures of total_stat / max_hp / max_mp / snapshot are
## fixed; everything else is additive).
##
## Derived character numbers, always computed from base values + equipment bonuses + active effects, never stored.
## Bonus dictionaries use Equipment.BONUS_KEYS plus the EXTRA_BONUS_KEYS below. Formulas (MeowDB MS Classic):
##   totals    = base + Equipment.total_bonuses + effect bonuses         (formulas/accuracy.json inputs_note)
##   ACC       = floor(Common / divisor + constant) per job class, Common = 1.2 DEX + 2 Level + 0.6 LUK
##               (Magician: floor((1.2 INT + 2 Level + 0.6 LUK) / 5.1 + 20)); + equipment/effect ACC afterward
##   EVA       = floor(LUK / 3) + floor(DEX / 6) + 5 (+ bonuses);  Magic = floor(INT / 2)
##   WDEF/MDEF = floor(STR / 4) / floor(INT / 4) (+ bonuses, x (1 + pct / 100))
##   Max HP    = trunc(base_max_hp x (1 + MaxHP% / 100)) + equipment HP (same for MP)
##   damage    = the stat-window range: one ordinary basic attack before defense, level gap and crits; split-action
##               weapons show the lowest MIN and highest MAX (CombatFormula.damage_window)
## Job formulas plug in through JOBS (slug -> base class + advancements) and the per-class tables in canonical data
## (accuracy.json by_job, hp_mp_gain.json per_class); nothing assumes a Beginner.
##
## Effects: each entry of CharacterState.effects may carry "bonuses": {key: number} with BONUS_KEYS / EXTRA_BONUS_KEYS.

## Bonus keys beyond Equipment.BONUS_KEYS that equipment or effects may carry.
const EXTRA_BONUS_KEYS: PackedStringArray = ["attack_power", "crit_rate_pct", "crit_damage_pct", "max_hp_pct",
	"max_mp_pct", "wdef_pct", "mdef_pct", "darkness_pct", "shield_wdef"]
## Job slug -> the class whose formula rows it uses and how many job advancements it has taken. Add 2nd/3rd jobs
## here (e.g. "fighter": {"class": "warrior", "advancements": 2}) when they are implemented.
const JOBS: Dictionary = {
	"beginner": {"class": "beginner", "advancements": 0},
	"warrior": {"class": "warrior", "advancements": 1},
	"magician": {"class": "magician", "advancements": 1},
	"bowman": {"class": "bowman", "advancements": 1},
	"thief": {"class": "thief", "advancements": 1},
}


# --- the fixed contract ---------------------------------------------------------------------------------------

## Total of a primary stat ("str", "dex", "int", "luk"): base + equipment + effects.
static func total_stat(c: CharacterState, stat: String, db: ContentDB) -> int:
	return c.get_base_stat(stat) + int(bonuses(c, db).get(stat, 0))


## TotalHP = trunc(base_max_hp x (1 + MaxHP% / 100)) + EquipmentHP.
static func max_hp(c: CharacterState, db: ContentDB) -> int:
	return hp_mp_total(c.base_max_hp, bonuses(c, db), "max_hp")


static func max_mp(c: CharacterState, db: ContentDB) -> int:
	return hp_mp_total(c.base_max_mp, bonuses(c, db), "max_mp")


## Everything the stat window shows: {"str","dex","int","luk","max_hp","max_mp","watk","matk","wdef","mdef",
## "acc","avoid","magic","speed","jump","damage_min","damage_max"} plus "damage_avg", "attack_power",
## "crit_rate_pct", "crit_damage_pct", "primary", "secondary", "shield_guard_chance", "job", "level", "weapon_id".
## "magic" is the derived floor(INT / 2); "matk" is MagicTotal (derived magic + equipment/effect MATK).
static func snapshot(c: CharacterState, db: ContentDB) -> Dictionary:
	return compute(c.job, c.level, c.base_stats, c.base_max_hp, c.base_max_mp, bonuses(c, db), _weapon_id(c), db)


# --- additions ------------------------------------------------------------------------------------------------

## The pure core of snapshot(): every derived number from explicit inputs (used by tests and tools too).
static func compute(job: String, level: int, base_stats: Dictionary, base_max_hp: int, base_max_mp: int,
		b: Dictionary, weapon_id: String, db: ContentDB) -> Dictionary:
	var r := CombatRules.of(db)
	var weapon := WeaponProfile.for_weapon_id(weapon_id, db)
	var totals := {}
	for k in CharacterState.STAT_KEYS:
		totals[k] = int(base_stats.get(k, 0)) + int(b.get(k, 0))
	var out := totals.duplicate()
	out["job"] = job
	out["level"] = level
	out["weapon_id"] = weapon_id
	out["max_hp"] = hp_mp_total(base_max_hp, b, "max_hp")
	out["max_mp"] = hp_mp_total(base_max_mp, b, "max_mp")
	# Total Weapon Attack pools every equipped W.ATK line (derived_stats.json total_weapon_attack_rule). An equipped
	# weapon's line is already in the equipment bonuses; an empty weapon slot contributes the bare-hands line
	# (misostory/combat.json bare_hands.weapon_watk, an adaptation).
	out["watk"] = int(b.get("watk", 0)) + (weapon.watk if weapon.is_bare_hands else 0)
	out["attack_power"] = int(b.get("attack_power", 0))
	out["magic"] = derived_magic(totals["int"], db)
	out["matk"] = int(out["magic"]) + int(b.get("matk", 0))
	out["wdef"] = int((derived_wdef(totals["str"], db) + float(b.get("wdef", 0))) * (1.0 + float(b.get("wdef_pct", 0)) / 100.0))
	out["mdef"] = int((derived_mdef(totals["int"], db) + float(b.get("mdef", 0))) * (1.0 + float(b.get("mdef_pct", 0)) / 100.0))
	out["acc"] = derived_accuracy(job, level, totals["dex"], totals["int"], totals["luk"], db) + int(b.get("acc", 0))
	out["avoid"] = derived_avoid(totals["dex"], totals["luk"], db) + int(b.get("avoid", 0))
	out["speed"] = clampi(r.base_speed + int(b.get("speed", 0)), 0, r.speed_cap)
	out["jump"] = clampi(r.base_jump + int(b.get("jump", 0)), 0, r.jump_cap)
	out["crit_rate_pct"] = clampf(r.crit_rate_base * 100.0 + float(b.get("crit_rate_pct", 0)), 0.0, 100.0)
	out["crit_damage_pct"] = maxf(0.0, r.crit_damage_base * 100.0 + float(b.get("crit_damage_pct", 0)))
	out["shield_wdef"] = int(b.get("shield_wdef", 0))
	out["shield_guard_chance"] = CombatFormula.shield_guard_chance(float(out["shield_wdef"]))
	out["darkness_pct"] = float(b.get("darkness_pct", 0))
	out["mastery_level"] = mastery_level(job, weapon_id, db)
	out["primary"] = int(WeaponProfile.sum_stats(weapon.primary_stats, totals))
	out["secondary"] = int(WeaponProfile.sum_stats(weapon.secondary_stats, totals))
	var window := CombatFormula.damage_window(player_stats_from(out, weapon), null, db)
	out["damage_min"] = window["min"]
	out["damage_max"] = window["max"]
	out["damage_avg"] = window["avg"]
	return out


## The player's combat record (offense and defense) for CombatFormula.
static func combat_stats(c: CharacterState, db: ContentDB) -> PlayerCombatStats:
	var snap := snapshot(c, db)
	return player_stats_from(snap, WeaponProfile.for_weapon_id(String(snap["weapon_id"]), db))


## Builds a PlayerCombatStats from a snapshot()/compute() dictionary and the weapon it was computed with.
static func player_stats_from(snap: Dictionary, weapon: WeaponProfile) -> PlayerCombatStats:
	var s := PlayerCombatStats.new()
	s.job = String(snap.get("job", "beginner"))
	s.level = int(snap.get("level", 1))
	s.totals = {"str": int(snap["str"]), "dex": int(snap["dex"]), "int": int(snap["int"]), "luk": int(snap["luk"])}
	s.total_watk = int(snap.get("watk", 0))
	s.attack_power = int(snap.get("attack_power", 0))
	s.magic_total = int(snap.get("matk", 0))
	s.acc = int(snap.get("acc", 0))
	s.avoid = int(snap.get("avoid", 0))
	s.wdef = int(snap.get("wdef", 0))
	s.mdef = int(snap.get("mdef", 0))
	s.crit_rate = float(snap.get("crit_rate_pct", 0.0)) / 100.0
	s.crit_damage = float(snap.get("crit_damage_pct", 0.0)) / 100.0
	s.mastery_level = int(snap.get("mastery_level", 0))
	s.shield_wdef = int(snap.get("shield_wdef", 0))
	s.darkness_pct = float(snap.get("darkness_pct", 0.0))
	s.weapon = weapon
	return s


## Sum of equipment bonuses (Equipment.total_bonuses) and effect bonuses, plus "shield_wdef" for Shield Guard.
static func bonuses(c: CharacterState, db: ContentDB) -> Dictionary:
	var out := {}
	if c.equipment != null:
		_merge(out, c.equipment.total_bonuses(db))
		var shield_id := c.equipment.item_in("shield")
		if shield_id != "":
			out["shield_wdef"] = int(shield_stats(c.equipment, shield_id, db).get("wdef", 0))
	_merge(out, effect_bonuses(c.effects))
	return out


## The stat lines of the equipped shield: the piece's own per-instance "stats" (a scroll result) when it has them,
## else its clean canonical stats, the same rule Equipment.total_bonuses applies.
static func shield_stats(equipment: Equipment, shield_id: String, db: ContentDB) -> Dictionary:
	var inst: Dictionary = equipment.instance_in("shield")
	var data: Variant = inst.get("data", {})
	if data is Dictionary and (data as Dictionary).get("stats", null) is Dictionary:
		return data["stats"]
	return db.item(shield_id).get("stats", {})


## Sums the "bonuses" dictionaries of active effects.
static func effect_bonuses(effects: Array) -> Dictionary:
	var out := {}
	for e in effects:
		if e is Dictionary and (e as Dictionary).get("bonuses", null) is Dictionary:
			_merge(out, e["bonuses"])
	return out


## TotalHP/MP = trunc(base x (1 + pct / 100)) + flat (key "max_hp" or "max_mp"; pct key "<key>_pct").
static func hp_mp_total(base: int, b: Dictionary, key: String) -> int:
	return int(base * (1.0 + float(b.get(key + "_pct", 0)) / 100.0)) + int(b.get(key, 0))


## The class whose formula rows a job uses ("beginner", "warrior", "magician", "bowman", "thief").
static func job_class(job: String) -> String:
	var j: Dictionary = JOBS.get(job, {})
	if j.is_empty():
		push_warning("[StatCalculator] job '%s' is not in StatCalculator.JOBS; using it as its own class" % job)
		return job
	return String(j["class"])


## Job advancements taken by a job slug (0 for a Beginner).
static func job_advancements(job: String) -> int:
	return int((JOBS.get(job, {}) as Dictionary).get("advancements", 0))


## Stat-derived ACC for a job: floor(Common / divisor + constant) with Common = 1.2 DEX + 2 Level + 0.6 LUK, or the
## Magician's INT-based numerator, all from formulas/accuracy.json derived_accuracy.
static func derived_accuracy(job: String, level: int, dex: int, int_total: int, luk: int, db: ContentDB) -> int:
	var r := CombatRules.of(db)
	var spec: Dictionary = r.acc_by_job.get(job_class(job), {})
	if spec.is_empty():
		push_error("[StatCalculator] no ACC formula for job '%s'" % job)
		return 0
	var lvl := maxi(1, level)
	var luk_term := r.acc_luk_coefficient * maxi(0, luk)
	var numerator := 0.0
	if bool(spec["uses_common_term"]):
		numerator = r.acc_dex_coefficient * maxi(0, dex) + r.acc_level_coefficient * lvl + luk_term
	else:
		numerator = r.acc_magician_int_coefficient * maxi(0, int_total) + r.acc_level_coefficient * lvl + luk_term
	return floori(numerator / float(spec["divisor"]) + float(spec["constant"]))


## EVA = floor(LUK / 3) + floor(DEX / 6) + 5 (each term floored separately).
static func derived_avoid(dex: int, luk: int, db: ContentDB) -> int:
	var r := CombatRules.of(db)
	return floori(luk / r.eva_luk_divisor) + floori(dex / r.eva_dex_divisor) + int(r.eva_constant)


## Magic = floor(INT / 2).
static func derived_magic(int_total: int, db: ContentDB) -> int:
	return floori(int_total / CombatRules.of(db).magic_int_divisor)


## WDEF = floor(STR / 4).
static func derived_wdef(str_total: int, db: ContentDB) -> int:
	return floori(str_total / CombatRules.of(db).wdef_str_divisor)


## MDEF = floor(INT / 4).
static func derived_mdef(int_total: int, db: ContentDB) -> int:
	return floori(int_total / CombatRules.of(db).mdef_int_divisor)


## Weapon mastery level for the damage formula. A Beginner has no mastery skill (MasteryLevel 0, M = 0.08); job
## mastery skills (Sword Mastery ...) plug in here once skill data exists.
static func mastery_level(_job: String, _weapon_id: String, _db: ContentDB) -> int:
	return 0


## The stat-window damage range of the character: {"min", "max", "avg"}.
static func damage_range(c: CharacterState, db: ContentDB) -> Dictionary:
	var snap := snapshot(c, db)
	return {"min": snap["damage_min"], "max": snap["damage_max"], "avg": snap["damage_avg"]}


## Total Speed for movement (base 100 + bonuses, capped at 140).
static func speed(c: CharacterState, db: ContentDB) -> int:
	var r := CombatRules.of(db)
	return clampi(r.base_speed + int(bonuses(c, db).get("speed", 0)), 0, r.speed_cap)


## Total Jump for movement (base 100 + bonuses, capped at 120).
static func jump(c: CharacterState, db: ContentDB) -> int:
	var r := CombatRules.of(db)
	return clampi(r.base_jump + int(bonuses(c, db).get("jump", 0)), 0, r.jump_cap)


## Changes HP by delta within [0, max HP]; returns the change actually applied. Callers emit Events.hp_changed.
static func change_hp(c: CharacterState, delta: int, db: ContentDB) -> int:
	var before := c.hp
	c.hp = clampi(c.hp + delta, 0, max_hp(c, db))
	return c.hp - before


## Changes MP by delta within [0, max MP]; returns the change actually applied.
static func change_mp(c: CharacterState, delta: int, db: ContentDB) -> int:
	var before := c.mp
	c.mp = clampi(c.mp + delta, 0, max_mp(c, db))
	return c.mp - before


## Pulls HP/MP back under their maxima (e.g. after unequipping an HP item).
static func clamp_vitals(c: CharacterState, db: ContentDB) -> void:
	c.hp = clampi(c.hp, 0, max_hp(c, db))
	c.mp = clampi(c.mp, 0, max_mp(c, db))


static func _weapon_id(c: CharacterState) -> String:
	return c.equipment.weapon_id() if c.equipment != null else ""


static func _merge(into: Dictionary, add: Dictionary) -> void:
	for k in add:
		var v: Variant = add[k]
		if v is int or v is float:
			into[k] = into.get(k, 0) + v
