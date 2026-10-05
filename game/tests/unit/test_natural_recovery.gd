extends TestCase
## Natural HP recovery (NaturalRecoveryRule, combat.json natural_recovery): the adaptation for MeowDB's qualitative
## "standing still will slowly restore your HP" (recovery.json natural_regeneration, documented_values false).


func _rule() -> NaturalRecoveryRule:
	return NaturalRecoveryRule.from_config({"hp_per_tick": 10, "tick_s": 10.0, "delay_s": 5.0,
		"requires_standing_still": true})


## Runs `seconds` of 60 Hz ticks and returns the total HP the rule hands out (HP is advanced as it heals).
func _run(r: NaturalRecoveryRule, seconds: float, can_rest: bool, hp: int, max_hp: int) -> int:
	var healed := 0
	for _i in int(round(seconds * 60.0)):
		var h := r.step(1.0 / 60.0, can_rest, hp + healed, max_hp)
		healed += h
	return healed


func test_shipped_config_is_an_unverified_adaptation_over_a_canonical_gap() -> void:
	var cfg: Dictionary = (db().miso_table("combat") as Dictionary)["natural_recovery"]
	assert_eq(bool(cfg["verified"]), false, "natural recovery is a MisoStory adaptation")
	assert_true(String(cfg["reason"]).length() > 40, "the adaptation carries its reason")
	var canon: Dictionary = db().formula("recovery")["natural_regeneration"]
	assert_eq(bool(canon["documented_values"]), false, "MeowDB publishes no regen numbers")
	assert_true(NaturalRecoveryRule.from_db(db()) != null, "the shipped config builds a rule")


func test_resting_heals_one_tick_every_tick_s() -> void:
	var r := _rule()
	assert_eq(_run(r, 9.9, true, 20, 50), 0, "nothing before the first 10 s of rest")
	assert_eq(_run(r, 0.2, true, 20, 50), 10, "the first tick at 10 s")
	assert_eq(_run(r, 10.0, true, 30, 50), 10, "then one tick per 10 s")


func test_never_above_max_hp_and_not_at_full_or_dead() -> void:
	var r := _rule()
	assert_eq(_run(r, 10.1, true, 46, 50), 4, "clamped to max HP")
	assert_eq(_run(r, 30.0, true, 50, 50), 0, "full HP: nothing")
	assert_eq(_run(r, 30.0, true, 0, 50), 0, "HP 0 (dead): nothing")


func test_moving_or_combat_restarts_the_rest() -> void:
	var r := _rule()
	_run(r, 8.0, true, 20, 50)
	assert_eq(_run(r, 0.5, false, 20, 50), 0, "walking")
	assert_eq(_run(r, 9.0, true, 20, 50), 0, "the rest started over after moving")
	r.note_combat()
	assert_eq(_run(r, 14.9, true, 20, 50), 0, "combat: the 5 s delay, then a full 10 s rest")
	assert_eq(_run(r, 0.2, true, 20, 50), 10, "heals once 5 s + 10 s have passed")


func test_missing_config_is_a_data_error_not_a_default() -> void:
	assert_true(NaturalRecoveryRule.from_config({"hp_per_tick": 10, "tick_s": 10.0}) == null,
		"no invented values for missing keys")
