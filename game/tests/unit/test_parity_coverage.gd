extends ParityTestCase
## Every mechanic in parity_vectors.json is replayed by a parity test; a new mechanic from a refreshed oracle run
## fails here until a test consumes it.

## mechanic -> the test that replays it.
const COVERED: Dictionary = {
	"character_stats_and_damage_window": "test_parity_stats::test_character_stats_and_damage_window",
	"beginner_damage_vs_monster": "test_parity_damage::test_beginner_damage_vs_monster",
	"physical_roll_explicit": "test_parity_damage::test_physical_roll_explicit",
	"accuracy_hit_chance_vs_monster": "test_parity_accuracy::test_accuracy_vs_monster",
	"accuracy_acc_milestones": "test_parity_accuracy::test_acc_milestones",
	"accuracy_hit_chance_grid": "test_parity_accuracy::test_accuracy_grid",
	"avoid_and_incoming_damage_vs_monster": "test_parity_accuracy::test_avoid_and_incoming_vs_monster",
	"mob_hit_danger": "test_parity_accuracy::test_mob_hit_danger",
	"monster_touch_damage_display": "test_parity_accuracy::test_monster_touch_damage_display",
	"incoming_hit_chance_grid": "test_parity_accuracy::test_incoming_hit_grid",
	"incoming_damage_curve": "test_parity_accuracy::test_incoming_damage_curve",
	"shield_guard_chance": "test_parity_accuracy::test_shield_guard_chance",
	"level_gap_scale": "test_parity_damage::test_level_gap_scale",
	"defense_curve_and_final_clamp": "test_parity_damage::test_defense_curve_and_final_clamp",
	"defense_ignore": "test_parity_damage::test_defense_ignore",
	"magic_defense_curve": "test_parity_damage::test_magic_defense_curve",
	"final_clamp": "test_parity_damage::test_final_clamp",
	"crit_expectation": "test_parity_damage::test_crit_expectation",
	"guide_example_lv30_warrior_stats": "test_parity_stats::test_guide_lv30_warrior_stats",
	"guide_example_lv30_warrior_damage_window": "test_parity_damage::test_guide_lv30_warrior_damage_window",
	"guide_example_beginner_starter_weapon_hits": "test_parity_damage::test_guide_beginner_starter_weapon_hits",
	"exp_requirement": "test_parity_exp::test_exp_requirement",
	"exp_calculator_validation": "test_parity_exp::test_exp_calculator_validation",
}


## Contract C6 (Definition of Done: MeowDB parity tests still pass, coverage intact).
func parity_keys() -> Dictionary:
	return {"test_every_mechanic_is_covered": ["canon:meowdb-formula-parity"], "test_vectors_agree_with_guide": ["canon:meowdb-formula-parity"]}


func test_every_mechanic_is_covered() -> void:
	var seen := {}
	for v in parity_doc().get("vectors", []):
		seen[String(v["mechanic"])] = true
	for m in seen:
		assert_has(COVERED, m, "parity mechanic without a test:")
	assert_eq(parity_doc().get("vectors", []).size(), 818, "vector count (oracles.md)")


## The oracle's own guide agreement flags stay true (a refreshed oracle disagreeing with the guide needs review).
func test_vectors_agree_with_guide() -> void:
	for v in parity_doc().get("vectors", []):
		if (v as Dictionary).has("agrees_with_guide"):
			assert_true(bool(v["agrees_with_guide"]), "%s/%s disagrees with the guide" % [v["mechanic"], v["case_id"]])
