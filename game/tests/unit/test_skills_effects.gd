extends TestCase
## Timed effects and cooldowns (EffectBook over CharacterState.effects / cooldowns, contract C3): remaining seconds of
## game time, a speed bonus that StatCalculator counts (capped at the canonical 140) until it expires, a heal over
## time that heals exactly its total in equal ticks, cooldowns that count down and clear, malformed save entries that
## are dropped instead of crashing, and a save round trip that keeps both mid-way (no tick healed twice).

const TICK := 1.0 / 60.0


func parity_keys() -> Dictionary:
	return {
		"test_a_speed_bonus_counts_until_it_expires": ["mechanic:timed-effects", "skill:0001002"],
		"test_speed_bonuses_stop_at_the_canonical_cap": ["mechanic:timed-effects"],
		"test_a_heal_over_time_heals_exactly_its_total_in_equal_ticks": ["mechanic:timed-effects", "skill:0001001"],
		"test_cooldowns_count_down_and_clear": ["mechanic:timed-effects"],
		"test_effects_and_cooldowns_survive_a_save_mid_way": ["mechanic:skill-persistence"],
	}


func _character() -> CharacterState:
	var cr := CharacterFactory.create(CharacterFactory.default_params(db()), db())
	assert_true(cr.ok, "factory character")
	return cr.character


func _run(c: CharacterState, seconds: float) -> Dictionary:
	var heal := 0
	var heals: Array = []
	var expired: Array = []
	var changed := false
	for i in int(round(seconds / TICK)):
		var r := EffectBook.tick(c, TICK)
		if int(r.heal) > 0:
			heals.append(int(r.heal))
		heal += int(r.heal)
		expired.append_array(r.expired)
		changed = changed or bool(r.bonuses_changed)
	return {"heal": heal, "heals": heals, "expired": expired, "bonuses_changed": changed}


## The character after a real save: SaveDocument.build -> JSON text -> SaveDocument.decode (normalize_numbers too).
func _through_save(c: CharacterState) -> CharacterState:
	var doc := SaveDocument.build(c, SaveDocument.world_from_character(c), "2026-10-05T00:00:00Z", db())
	var raw: Variant = JSON.parse_string(JSON.stringify(doc))
	assert_true(raw is Dictionary, "the save is JSON")
	var res := SaveDocument.decode(raw, SaveMigrations.new(), db())
	assert_true(res.ok(), "the save decodes: %s" % res.message)
	return res.character


func test_a_speed_bonus_counts_until_it_expires() -> void:
	var c := _character()
	var base := StatCalculator.speed(c, db())
	assert_eq(base, int(db().formula("movement")["base_speed"]), "base Speed 100")
	var e := EffectBook.add(c, "skill:0001002", "skill:0001002", 10.0, {"bonuses": {"speed": 10}})
	assert_eq(e["remaining_s"], 10.0, "remaining seconds, not a clock time")
	assert_eq(StatCalculator.speed(c, db()), base + 10, "+10 while active")
	assert_eq(int(StatCalculator.snapshot(c, db())["speed"]), base + 10, "the stat window sees it")
	var first := _run(c, 9.9)
	assert_true(first.expired.is_empty(), "still active at 9.9 s")
	assert_near(EffectBook.remaining(c, "skill:0001002"), 0.1, 1e-6, "0.1 s left")
	var second := _run(c, 0.2)
	assert_eq(second.expired.size(), 1, "expired at 10 s")
	assert_true(second.bonuses_changed, "an expiring bonus says so (the runtime refreshes the stats)")
	assert_false(EffectBook.has(c, "skill:0001002"), "gone")
	assert_eq(StatCalculator.speed(c, db()), base, "back to base")
	# A re-add replaces the active entry instead of stacking.
	EffectBook.add(c, "skill:0001002", "skill:0001002", 5.0, {"bonuses": {"speed": 10}})
	EffectBook.add(c, "skill:0001002", "skill:0001002", 8.0, {"bonuses": {"speed": 10}})
	assert_eq(c.effects.size(), 1, "one entry per id")
	assert_eq(StatCalculator.speed(c, db()), base + 10, "not stacked")


func test_speed_bonuses_stop_at_the_canonical_cap() -> void:
	var c := _character()
	EffectBook.add(c, "a", "test", 30.0, {"bonuses": {"speed": 10}})
	EffectBook.add(c, "b", "test", 30.0, {"bonuses": {"speed": 50}})
	assert_eq(StatCalculator.speed(c, db()), int(db().formula("movement")["speed_cap"]), "Speed cap 140")
	# An old entry with a top-level "bonuses" still counts.
	c.effects = [{"id": "old", "source": "test", "remaining_s": 3.0, "bonuses": {"jump": 5}}]
	assert_eq(StatCalculator.jump(c, db()), int(db().formula("movement")["base_jump"]) + 5, "legacy shape")


func test_a_heal_over_time_heals_exactly_its_total_in_equal_ticks() -> void:
	var c := _character()
	var tick_s := SkillRules.of(db()).recovery_tick_s
	for total in [24, 48, 72]:
		c.effects = []
		EffectBook.add(c, "skill:0001001", "skill:0001001", 30.0, {"hp_total": total, "duration_s": 30.0, "tick_s": tick_s})
		var r := _run(c, 31.0)
		assert_eq(int(r.heal), total, "heals exactly %d over 30 s" % total)
		assert_eq((r.heals as Array).size(), EffectBook.tick_count(30.0, tick_s), "one heal per tick")
		for h in r.heals:
			assert_eq(int(h), total / EffectBook.tick_count(30.0, tick_s), "equal ticks of %d" % total)
		assert_eq(r.expired.size(), 1, "and then ends")
	# The ticks fall at 5, 10 ... 30 s: none before the first interval.
	c.effects = []
	EffectBook.add(c, "h", "skill:0001001", 30.0, {"hp_total": 24, "duration_s": 30.0, "tick_s": 5.0})
	assert_eq(int(_run(c, 4.9).heal), 0, "nothing in the first 4.9 s")
	assert_eq(int(_run(c, 0.2).heal), 4, "the first tick at 5 s")
	# A total that does not divide evenly still sums exactly.
	var sum := 0
	for k in range(1, 7):
		sum += EffectBook.heal_for_tick(25, 6, k)
	assert_eq(sum, 25, "floor-difference ticks sum to the total")
	# No tick interval: the whole total when the effect ends.
	c.effects = []
	EffectBook.add(c, "h0", "test", 2.0, {"hp_total": 9, "duration_s": 2.0, "tick_s": 0.0})
	var once := _run(c, 2.1)
	assert_eq(once.heals, [9], "one heal at the end")


func test_cooldowns_count_down_and_clear() -> void:
	var c := _character()
	EffectBook.start_cooldown(c, "0001001", 120.0)
	assert_eq(EffectBook.cooldown_left(c, "0001001"), 120.0, "120 s")
	_run(c, 60.0)
	assert_near(EffectBook.cooldown_left(c, "0001001"), 60.0, 1e-6, "half way")
	_run(c, 60.1)
	assert_eq(EffectBook.cooldown_left(c, "0001001"), 0.0, "ready")
	assert_false(c.cooldowns.has("0001001"), "cleared from CharacterState.cooldowns")
	EffectBook.start_cooldown(c, "x", 0.0)
	assert_true(c.cooldowns.is_empty(), "a zero cooldown stores nothing")


func test_malformed_entries_are_dropped_not_fatal() -> void:
	var c := _character()
	c.effects = [{"id": "old", "until": 512.25}, "junk", {"id": "x", "source": "s", "remaining_s": "soon"},
		{"id": "ok", "source": "s", "remaining_s": 5}]
	c.cooldowns = {"0001001": "later", "0001002": 4}
	var r := EffectBook.tick(c, TICK)
	assert_eq(int(r.dropped), 3, "the three malformed entries")
	assert_eq(c.effects.size(), 1, "the valid one stays")
	assert_false(c.cooldowns.has("0001001"), "a non-numeric cooldown clears")
	assert_near(EffectBook.cooldown_left(c, "0001002"), 4.0 - TICK, 1e-9, "an int cooldown (JSON) counts down")


func test_clear_by_source() -> void:
	var c := _character()
	EffectBook.add(c, "a", "skill:0001001", 10.0)
	EffectBook.add(c, "b", "skill:0001002", 10.0)
	EffectBook.add(c, "c", "item:2022", 10.0)
	assert_eq(EffectBook.clear(c, "skill:").size(), 2, "both skill effects")
	assert_eq(c.effects.size(), 1, "the item effect stays")


func test_effects_and_cooldowns_survive_a_save_mid_way() -> void:
	var c := _character()
	EffectBook.add(c, "skill:0001001", "skill:0001001", 30.0, {"hp_total": 24, "duration_s": 30.0, "tick_s": 5.0,
		"skill_id": "0001001", "level": 1})
	EffectBook.add(c, "skill:0001002", "skill:0001002", 30.0, {"bonuses": {"speed": 10}, "skill_id": "0001002", "level": 3})
	EffectBook.start_cooldown(c, "0001001", 120.0)
	EffectBook.start_cooldown(c, "0001002", 180.0)
	var before := _run(c, 11.5)
	assert_eq(int(before.heal), 8, "two ticks (5 s, 10 s) before the save")
	var loaded := _through_save(c)
	assert_near(EffectBook.remaining(loaded, "skill:0001001"), 18.5, 1e-6, "Recovery: 18.5 s left after the load")
	assert_near(EffectBook.remaining(loaded, "skill:0001002"), 18.5, 1e-6, "Nimble Feet: 18.5 s left")
	assert_near(EffectBook.cooldown_left(loaded, "0001001"), 108.5, 1e-6, "Recovery cooldown kept")
	assert_near(EffectBook.cooldown_left(loaded, "0001002"), 168.5, 1e-6, "Nimble Feet cooldown kept")
	assert_eq(StatCalculator.speed(loaded, db()), StatCalculator.speed(c, db()), "the speed bonus is back")
	var after := _run(loaded, 20.0)
	assert_eq(int(after.heal), 16, "the 4 remaining ticks: 24 in total, none healed twice")
	assert_eq(after.expired.size(), 2, "both end on time")
	# A whole-number remaining time comes back from JSON as an int and still counts down.
	var whole := _character()
	EffectBook.add(whole, "w", "test", 7.0, {"bonuses": {"speed": 10}})
	var w2 := _through_save(whole)
	assert_eq(_run(w2, 7.1).expired.size(), 1, "an int remaining_s from the file expires on time")
