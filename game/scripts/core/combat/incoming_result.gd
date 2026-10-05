class_name IncomingResult
extends RefCounted
## One resolved monster attack on the player (touch or skill, physical or magic), every stage exposed.
##
## Order (MeowDB /formulas/damage-taken): hit chance with the 8% minimum-hit rescue (physical only), Shield/Claw
## guard (regular physical attacks only), damage roll Roll = 1.1 + 0.4U, the DEF curve, elemental resistance (only
## for attacks with an element), then trunc(clamp(Taken, 1, 50,000,000)). The player becomes invincible for
## `invincibility_s` after a hit, a miss or a guard.

## "touch", "physical" or "magic".
var kind: String = "touch"
var missed: bool = false
var guarded: bool = false
## True when the monster has no attack of this kind (attack <= 0): no damage at all (oracles.md discrepancy 2).
var no_attack: bool = false
## Probability (0-1) that the attack lands, after the minimum-hit rescue; and the candidate chance before it.
var hit_chance: float = 1.0
var candidate_chance: float = 1.0
## The candidate draw (the spread R, or the chance draw in the far-miss branch) and whether the 8% rescue landed it.
var hit_roll: float = 0.0
var rescued: bool = false
var guard_chance: float = 0.0
## EffectiveMobAttack = trunc(MobAttack x AttackRatio / 100).
var effective_attack: int = 0
## Roll = 1.1 + 0.4 x U (and the unit draw U).
var roll: float = 0.0
var roll_u: float = 0.0
var raw: float = 0.0
## The player's WDEF (physical) or MDEF (magic) used by the curve.
var def: int = 0
var after_defense: float = 0.0
var resist_pct: float = 0.0
var after_resist: float = 0.0
## HP the player loses (0 when missed, guarded or no attack).
var final: int = 0
## Seconds of post-hit invincibility this attack grants (also after a miss or a guard).
var invincibility_s: float = 0.0
## True when the hit pushes the player back (MisoStory adaptation, data/misostory/combat.json player_knockback).
var knockback: bool = false


func landed() -> bool:
	return not missed and not guarded and final > 0


func to_dict() -> Dictionary:
	return {
		"kind": kind, "missed": missed, "guarded": guarded, "no_attack": no_attack, "hit_chance": hit_chance,
		"candidate_chance": candidate_chance, "hit_roll": hit_roll, "rescued": rescued, "guard_chance": guard_chance,
		"effective_attack": effective_attack,
		"roll": roll, "roll_u": roll_u, "raw": raw, "def": def, "after_defense": after_defense,
		"resist_pct": resist_pct, "after_resist": after_resist, "final": final,
		"invincibility_s": invincibility_s, "knockback": knockback,
	}
