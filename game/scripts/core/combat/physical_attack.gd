class_name PhysicalAttack
extends RefCounted
## Every input of the physical raw roll for one action (MeowDB "explaining the damage formula"):
##
##   Raw = S x TotalWATK x (B + (Q x WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)
##   B = uniform(base_roll_min, base_roll_max), Q = uniform(Primary x M, Primary)
##
## Built by CombatFormula.physical_attack(), which resolves the weapon family, the action multiplier and the special
## branches (projectile, close-range ranged hit, crouched attack, Lucky Seven) from data. Plain record: no rules here.

## Damage action: "swing", "stab", "shoot", "mixed" or "crouch".
var action: String = ""
## Which damage.json branch supplied the divisors ("ordinary" or a special_branches key).
var branch: String = "ordinary"
## S = SkillDamage / 100 (1.0 for a basic attack).
var skill_scale: float = 1.0
var total_watk: float = 0.0
var primary: float = 0.0
var secondary: float = 0.0
var weapon_mult: float = 0.0
## M, the mastery factor (already resolved from MasteryLevel, or forced by a branch such as Lucky Seven).
var mastery: float = 0.0
var stat_div: float = 0.0
var ap_div: float = 0.0
var attack_power: float = 0.0
var base_roll_min: float = 0.0
var base_roll_max: float = 0.0


func to_dict() -> Dictionary:
	return {
		"action": action, "branch": branch, "skill_scale": skill_scale, "total_watk": total_watk,
		"primary": primary, "secondary": secondary, "weapon_mult": weapon_mult, "mastery": mastery,
		"stat_div": stat_div, "ap_div": ap_div, "attack_power": attack_power,
		"base_roll_min": base_roll_min, "base_roll_max": base_roll_max,
	}
