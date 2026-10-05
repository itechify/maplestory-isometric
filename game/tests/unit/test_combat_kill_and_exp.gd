extends TestCase
## The combat rules end to end, on canonical Maple Island data (brief Phase 21 "Combat": monster death and EXP award;
## Phase 9 player death): seeded basic attacks bring a Snail's canonical HP to 0, its canonical EXP levels a Beginner
## at the published threshold, and Orange Mushroom contact damage kills a level-1 Beginner, who then pays the death
## EXP penalty. Monster HP bookkeeping belongs to the monster runtime; here it is a plain int so the pure rules can be
## checked together.


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## A level-1 Beginner as MeowDB's Beginner guide builds it (13/4/4/4) holding `weapon_id`, through the real
## CharacterState -> Equipment -> StatCalculator path.
func _beginner(weapon_id: String) -> CharacterState:
	var c := CharacterState.new()
	Progression.init_new_character(c, db())
	assert_true(Progression.allocate_ap(c, "str", 9, db()), "creation AP into STR")
	if weapon_id != "":
		assert_true(c.equipment.force_equip("weapon", weapon_id, db()), "equip %s" % weapon_id)
	return c


## Hits until the monster's HP reaches 0; returns the hit count (every hit lands: Maple Island monsters have AVOID 0).
func _hits_to_kill(stats: PlayerCombatStats, target: MonsterCombatStats, rng: RandomNumberGenerator) -> int:
	var hp := target.hp
	var hits := 0
	while hp > 0 and hits < 1000:
		var pick := CombatFormula.choose_ordinary_action(stats.weapon, rng)
		var res := CombatFormula.resolve_physical_hit(stats, target, String(pick["action"]), rng, db(),
			{"presentation": pick["presentation"]})
		assert_false(res.missed, "AVOID 0: every basic attack lands")
		assert_true(res.final >= 1, "a landed hit deals at least 1")
		hp -= res.final
		hits += 1
	return hits


func test_snail_dies_within_the_beginner_guide_hit_counts() -> void:
	# Beginner's guide (13 STR, Sword vs a 45 HP Snail): 4 hits at MIN, 3 at the average and at MAX.
	var stats := PlayerCombatStats.from_character(_beginner("541"), db())
	assert_near(stats.crit_rate, CombatFormula.base_crit_rate(db()), 1e-12, "base crit rate from the stat path")
	# The guide's table (and MeowDB's character builder) excludes criticals: with crits two 25-damage hits could end
	# the fight. 14-21 per hit then bounds a 45 HP kill to exactly 3 or 4 hits for every seed.
	stats.crit_rate = 0.0
	var snail := MonsterCombatStats.from_id("2", db())
	assert_eq(snail.hp, 45, "canonical Snail HP")
	var rng := _rng(20261004)
	var counts := {}
	for i in 300:
		var n := _hits_to_kill(stats, snail, rng)
		assert_between(float(n), 3.0, 4.0, "Sword kills a Snail in 3-4 hits")
		counts[n] = int(counts.get(n, 0)) + 1
	# Four hits need three rolls averaging under 15 (MIN 14): the two-draw roll is centre-heavy, so that is rare.
	assert_true(int(counts.get(3, 0)) > int(counts.get(4, 0)), "3 hits (the average) is the common case: %s" % str(counts))
	# Deterministic per seed.
	assert_eq(_hits_to_kill(stats, snail, _rng(7)), _hits_to_kill(stats, snail, _rng(7)), "same seed, same fight")


func test_bare_hands_need_one_hit_per_hp() -> void:
	# The bare-hands adaptation (combat.json): W.ATK 0, so every landed punch deals the clamp minimum of 1.
	var stats := PlayerCombatStats.from_character(_beginner(""), db())
	assert_true(stats.weapon.is_bare_hands, "no weapon")
	var jr := MonsterCombatStats.from_id("1", db())
	assert_eq(_hits_to_kill(stats, jr, _rng(3)), jr.hp, "Tutorial Jr. Sentinel: one punch per HP")


func test_kill_exp_levels_a_beginner_at_the_published_threshold() -> void:
	var c := _beginner("541")
	var snail := MonsterCombatStats.from_id("2", db())
	assert_eq(snail.exp, int(db().monster("2")["exp"]), "kill EXP is the canonical monster EXP")
	var need := Progression.exp_to_next(1, db())
	var kills := Progression.kills_needed(need, snail.exp)
	assert_eq(kills, 8, "15 EXP / 2 per Snail (MeowDB EXP calculator)")
	for i in kills - 1:
		Progression.gain_exp(c, snail.exp, db())
	assert_eq([c.level, c.exp], [1, (kills - 1) * snail.exp], "one kill short of level 2")
	var r := Progression.gain_exp(c, snail.exp, db())
	assert_eq(r["levels_gained"], 1, "the eighth Snail levels up")
	assert_eq([c.level, c.exp], [2, kills * snail.exp - need], "excess EXP carries")
	assert_eq(c.ap, 5, "+5 AP after the 9 creation AP were placed")


func test_orange_mushroom_contact_kills_a_level_1_beginner() -> void:
	var c := _beginner("541")
	var mush := MonsterCombatStats.from_id("9", db())
	var rng := _rng(99)
	var touches := 0
	while not Progression.is_dead(c, db()) and touches < 100:
		var player := PlayerCombatStats.from_character(c, db())
		var res := CombatFormula.resolve_monster_touch(mush, player, rng, db())
		assert_true(res.landed(), "a level-1 Beginner (AVOID 6) never dodges an Orange Mushroom")
		assert_between(float(res.final), 18.0, 25.0, "Touch DMG 18-25 against WDEF 3 (oracles.md)")
		StatCalculator.change_hp(c, -res.final, db())
		touches += 1
	assert_eq(c.hp, 0, "HP stops at 0")
	assert_between(float(touches), 2.0, 3.0, "50 HP lasts two or three touches")
	# The death EXP penalty: base LUK 4 -> 10% of the level's requirement, never below 0 EXP.
	c.exp = 10
	var lost := Progression.apply_death_penalty(c, db())
	assert_eq(lost, Progression.death_exp_loss(1, 4, db()), "floor(15 x 10 / 100)")
	assert_eq([c.level, c.exp], [1, 10 - lost], "level kept, EXP reduced")
