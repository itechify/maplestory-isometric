extends TestCase
## Contract C3 (docs/runtime/ITERATION_THREE_CONTRACTS.md): natural_recovery.hp_rest_s is the eligible time toward the
## next tick, in [0, tick_s). CharacterState.from_dict() holds a loaded value to that range, so a hand-edited save (or
## one made under a longer tick_s) cannot pay several ticks in the first eligible step: NaturalRecoveryRule.step()
## pays every whole tick it holds in one loop.


func parity_keys() -> Dictionary:
	return {
		"test_a_loaded_clock_is_held_inside_one_tick": ["persistence:natural-regen-timer"],
		"test_an_over_full_saved_clock_pays_exactly_one_tick": ["persistence:natural-regen-timer", "mechanic:natural-hp-regen"],
	}


func _tick_s() -> float:
	return float((db().miso_table("recovery") as Dictionary)["natural_hp"]["tick_s"])


func _loaded(rest: Variant) -> CharacterState:
	var c := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	d["natural_recovery"] = {"hp_rest_s": rest}
	return CharacterState.from_dict(d)


func test_the_bound_is_the_shipped_tick_length() -> void:
	assert_true(_tick_s() > 0.0, "recovery.json natural_hp.tick_s")
	assert_eq(CharacterState.natural_tick_s(), _tick_s(), "from_dict bounds the clock by the rule's own tick_s")


func test_clamp_rest_s_keeps_the_c3_range() -> void:
	var eps := NaturalRecoveryRule.EPSILON_S
	assert_eq(CharacterState.clamp_rest_s(-3.0, 10.0), 0.0, "a negative clock starts at 0")
	assert_eq(CharacterState.clamp_rest_s(0.0, 10.0), 0.0)
	assert_eq(CharacterState.clamp_rest_s(5.5, 10.0), 5.5, "a value inside the range is kept exactly")
	assert_near(CharacterState.clamp_rest_s(10.0, 10.0), 10.0 - eps, 1e-12, "a whole tick is one tick's worth less epsilon")
	assert_near(CharacterState.clamp_rest_s(100.0, 10.0), 10.0 - eps, 1e-12, "ten ticks' worth is held to one")
	assert_true(CharacterState.clamp_rest_s(100.0, 10.0) < 10.0, "strictly below the tick")
	assert_eq(CharacterState.clamp_rest_s(INF, 10.0), 0.0, "a non-finite value starts at 0")
	assert_eq(CharacterState.clamp_rest_s(100.0, 0.0), 100.0, "no tick length known: only the lower bound, no tick invented")


func test_a_loaded_clock_is_held_inside_one_tick() -> void:
	var tick := _tick_s()
	assert_near(float(_loaded(6.5).natural_recovery["hp_rest_s"]), 6.5, 1e-9, "a saved 6.5 s comes back as it was")
	assert_eq(float(_loaded(-4).natural_recovery["hp_rest_s"]), 0.0, "a negative clock starts at 0")
	for over: float in [tick, tick * 10.0, 1e9]:
		var rest := float(_loaded(over).natural_recovery["hp_rest_s"])
		assert_true(rest < tick, "a saved %s s is held below the %s s tick: %s" % [over, tick, rest])
		assert_near(rest, tick - NaturalRecoveryRule.EPSILON_S, 1e-9, "one tick's worth for a saved %s s" % over)


func test_an_over_full_saved_clock_pays_exactly_one_tick() -> void:
	var rule := NaturalRecoveryRule.from_db(db())
	assert_true(rule != null, "the shipped rule")
	var loaded := _loaded(_tick_s() * 10.0)
	rule.rest_s = float(loaded.natural_recovery["hp_rest_s"])
	var heal := rule.step(1.0 / 60.0, &"still", 10, 10000)
	assert_eq(heal, rule.hp_per_tick, "the first eligible step pays one tick (%d HP), not ten" % rule.hp_per_tick)
	assert_true(rule.rest_s >= 0.0 and rule.rest_s < rule.tick_s, "the clock is back inside [0, tick_s): %s" % rule.rest_s)
	var more := 0
	for _i in 60:
		more += rule.step(1.0 / 60.0, &"still", 10 + heal, 10000)
	assert_eq(more, 0, "no second tick a second later")
