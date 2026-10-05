class_name DamageResult
extends RefCounted
## One resolved outgoing hit (player -> monster), with the value after every pipeline stage.
##
## Stages follow MeowDB's documented order: hit check, raw roll, defense, element, level gap, critical,
## skill-specific modifiers, final clamp. Damage numbers read `final`, `critical` and `missed`; the debug overlay
## reads stages() / to_dict(). Values stay fractional until `final` (MeowDB truncates once, at the end).

## "physical", "magic" or "fixed".
var kind: String = "physical"
var missed: bool = false
## "" when the hit landed, "accuracy" (hit roll failed) or "darkness" (the separate Darkness check failed).
var miss_reason: String = ""
## Probability (0-1) that the hit check passes, and whether the automatic-hit shortcut applied.
var hit_chance: float = 1.0
var auto_hit: bool = false
## The drawn hit spread R (0 when the hit was decided without a roll: no avoid, automatic hit or ACC 0).
var hit_roll: float = 0.0
## Damage action ("swing", "stab", "shoot", "crouch", "magic", "fixed") and the hit-box presentation played.
var action: String = ""
var presentation: String = ""
## The raw window of this action before defense (MIN and MAX of the raw roll).
var range_min: float = 0.0
var range_max: float = 0.0
## The two independent unit draws of the physical roll (B and Q in unit form), or the single magic draw.
var base_roll_u: float = 0.0
var stat_roll_u: float = 0.0
var raw: float = 0.0
var effective_def: int = 0
var defense_bypassed: bool = false
var after_defense: float = 0.0
var element_multiplier: float = 1.0
var after_element: float = 0.0
var level_scale: float = 1.0
var after_level: float = 0.0
var critical: bool = false
var crit_multiplier: float = 1.0
var after_critical: float = 0.0
var skill_multiplier: float = 1.0
var after_skill: float = 0.0
## The integer damage applied: trunc(clamp(after_skill, 1, 99999)); 0 when missed.
var final: int = 0
## True when `final` reaches the target's KB threshold (the monster staggers; see CombatFormula.monster_staggers).
var knockback: bool = false


## Stage-by-stage view for the debug overlay: [{"stage": String, "value": float}, ...] in pipeline order.
func stages() -> Array:
	var out: Array = [{"stage": "hit_check", "value": hit_chance}]
	if missed:
		return out
	out.append({"stage": "raw_roll", "value": raw})
	out.append({"stage": "defense", "value": after_defense})
	out.append({"stage": "element", "value": after_element})
	out.append({"stage": "level_gap", "value": after_level})
	out.append({"stage": "critical", "value": after_critical})
	out.append({"stage": "skill_modifiers", "value": after_skill})
	out.append({"stage": "final_clamp", "value": float(final)})
	return out


func to_dict() -> Dictionary:
	return {
		"kind": kind, "missed": missed, "miss_reason": miss_reason, "hit_chance": hit_chance, "auto_hit": auto_hit,
		"hit_roll": hit_roll,
		"action": action, "presentation": presentation, "range_min": range_min, "range_max": range_max,
		"base_roll_u": base_roll_u, "stat_roll_u": stat_roll_u, "raw": raw, "effective_def": effective_def,
		"defense_bypassed": defense_bypassed, "after_defense": after_defense,
		"element_multiplier": element_multiplier, "after_element": after_element, "level_scale": level_scale,
		"after_level": after_level, "critical": critical, "crit_multiplier": crit_multiplier,
		"after_critical": after_critical, "skill_multiplier": skill_multiplier, "after_skill": after_skill,
		"final": final, "knockback": knockback,
	}
