class_name PlayerCombatStats
extends RefCounted
## The player's combat numbers at one moment: offense and defense. Derived, never saved.
##
## Build it with PlayerCombatStats.from_character(c, db) (through StatCalculator, so equipment and effects count),
## or fill the fields directly in tests and tools. CombatFormula's resolve_* functions read only this record and a
## MonsterCombatStats, so the pipeline never reaches into CharacterState.

var job: String = "beginner"
var level: int = 1
## Total primary stats (base + equipment + effects): {"str", "dex", "int", "luk"}.
var totals: Dictionary = {"str": 0, "dex": 0, "int": 0, "luk": 0}
## Total Weapon Attack: the pool of every equipped W.ATK line plus effects.
var total_watk: int = 0
## Attack Power (only from effects explicitly labelled Attack Power; derived_stats.json attack_power_rule).
var attack_power: int = 0
## MagicTotal = floor(TotalINT / 2) + equipment, scroll and buff MATK.
var magic_total: int = 0
var acc: int = 0
var avoid: int = 0
var wdef: int = 0
var mdef: int = 0
## Critical rate c (0-1) and critical damage d (decimal bonus: 0.2 = +20%).
var crit_rate: float = 0.0
var crit_damage: float = 0.0
## Weapon mastery level (0 for a Beginner, M = 0.08) and spell mastery level.
var mastery_level: int = 0
var spell_mastery_level: int = 0
var weapon: WeaponProfile = null
## WDEF of an equipped shield (Shield Guard) and any other guard chance (e.g. a future Claw Guard), 0-1.
var shield_wdef: int = 0
var other_guard_chance: float = 0.0
## Darkness status on the attacker, percent (a separate miss check after the hit roll).
var darkness_pct: float = 0.0
## Rate (0-1) of a full defense-bypass proc on physical hits (none for a Beginner).
var defense_bypass_rate: float = 0.0
## Element of physical attacks ("" = none, e.g. a future White Knight charge).
var physical_element: String = ""
## element -> resistance percent against elemental monster attacks.
var element_resist: Dictionary = {}


static func from_character(c: CharacterState, db: ContentDB) -> PlayerCombatStats:
	return StatCalculator.combat_stats(c, db)


## Primary stat value for the equipped weapon (STR for swords, LUK for daggers ...).
func primary() -> float:
	return WeaponProfile.sum_stats(weapon.primary_stats, totals) if weapon != null else 0.0


## Secondary stat value for the equipped weapon (DEX for swords, STR + DEX for daggers ...).
func secondary() -> float:
	return WeaponProfile.sum_stats(weapon.secondary_stats, totals) if weapon != null else 0.0
