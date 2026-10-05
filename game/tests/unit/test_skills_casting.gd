extends TestCase
## PlayerSkills and EffectTicker on the combat lab (MonsterTestRig: a real PlayerController, MonsterSystem and Snails,
## a private bus and Game): Three Snails throws at the nearest Snail in its canonical band for exactly the level's
## fixed damage, pays the level's MP and shell, locks out for the canonical action time (PlayerCombat.is_attacking(),
## contract C4) and plants the player, never casts from the air or a rope; Recovery heals its total over 30 s, from the
## ground, the air or a rope, then cools down 2 min; Nimble Feet adds its Speed to the walk for its duration; effects
## end at death while cooldowns keep running; every refusal changes nothing; a seated player stands up to cast.

const SNAILS := "0001000"
const RECOVERY := "0001001"
const NIMBLE := "0001002"

var rig: MonsterTestRig


func parity_keys() -> Dictionary:
	return {
		"test_three_snails_hits_the_snail_in_its_band_for_the_fixed_damage": ["skill:0001000"],
		"test_three_snails_pays_mp_and_the_shell_and_locks_out_for_its_action": ["skill:0001000"],
		"test_three_snails_kills_a_snail_and_awards_its_exp": ["skill:0001000", "monster:2"],
		"test_three_snails_is_ground_only": ["skill:0001000"],
		"test_recovery_heals_its_total_over_30_s_and_cools_down": ["skill:0001001"],
		"test_nimble_feet_speeds_up_the_walk_for_its_duration": ["skill:0001002"],
		"test_effects_end_at_death_and_cooldowns_keep_running": ["mechanic:timed-effects"],
	}


func before_each() -> void:
	rig = MonsterTestRig.create(db(), 7)
	rig.floor(60.0)


func after_each() -> void:
	rig.free_all()


func _spawn(skills: Dictionary = {}) -> PlayerSkills:
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var c := rig.character()
	c.skills = skills.duplicate()
	c.base_max_hp = 500
	c.base_max_mp = 500
	c.mp = 500
	var ps: PlayerSkills = p.get_node_or_null(^"PlayerSkills")
	assert_true(ps != null, "PlayerCombat gave the player its PlayerSkills")
	assert_true(p.get_node_or_null(^"EffectTicker") is EffectTicker, "and its EffectTicker")
	assert_true(rig.system.player_combat.skills == ps, "PlayerCombat knows its skills node")
	# Let the body settle on the floor.
	rig.run(5)
	return ps


func _ticker() -> EffectTicker:
	return rig.w.player.get_node(^"EffectTicker")


func _px(px: float) -> float:
	return WorldScale.actor(px)


func _tick_all(n: int) -> void:
	for i in n:
		rig.tick()
		_ticker().step(MonsterTestRig.TICK)


func _give(item_id: String, qty: int) -> void:
	ItemService.new(rig.character(), db(), null).gain(item_id, qty)


func test_three_snails_hits_the_snail_in_its_band_for_the_fixed_damage() -> void:
	var def := SkillDef.of(SNAILS, db())
	for lv in range(1, 4):
		var hits := 0
		for seed_value in range(1, 9):
			rig.free_all()
			rig = MonsterTestRig.create(db(), seed_value)
			rig.floor(60.0)
			var ps := _spawn({SNAILS: lv})
			_give(String(def.item_cost(lv)["item_id"]), 1)
			var m := rig.spawn("2", Vector3(_px(200.0), 0.0, 0.0))
			var hp0 := m.hp
			var res := ps.cast(SNAILS)
			assert_true(res.ok, "Lv%d cast" % lv)
			assert_true(res.target == m, "Lv%d: the Snail 200 px ahead is the target" % lv)
			var dr: DamageResult = res.result
			if dr.missed:
				assert_eq(m.hp, hp0, "a miss deals nothing")
				continue
			hits += 1
			assert_eq(dr.final, int(def.fixed_damage(lv)), "Lv%d: exactly the fixed damage (no level gap, no critical)" % lv)
			assert_false(dr.critical, "never a critical")
			assert_eq(hp0 - m.hp, mini(hp0, dr.final), "applied through MonsterSystem.apply_player_hit")
			assert_true(rig.events_named("monster_hit").size() >= 1, "Events.monster_hit like a basic attack")
		assert_true(hits >= 4, "Lv%d hit in most of 8 seeds (%d)" % [lv, hits])


func test_three_snails_pays_mp_and_the_shell_and_locks_out_for_its_action() -> void:
	var ps := _spawn({SNAILS: 2})
	var c := rig.character()
	var def := SkillDef.of(SNAILS, db())
	_give("349", 3)
	var pc := rig.system.player_combat
	var mp0 := c.mp
	var res := ps.cast(SNAILS)
	assert_true(res.ok, "cast with nothing in range (a whiff)")
	assert_true(res.target == null, "no target")
	assert_eq(c.mp, mp0 - def.mp_cost(2), "MP -4 (Lv2)")
	assert_eq(c.inventory.count("349"), 2, "one Blue Snail Shell spent")
	var lost := rig.events_named("item_lost")
	assert_eq(lost.size(), 1, "Events.item_lost for the shell (quest counts follow)")
	assert_eq([String(lost[0][1]), int(lost[0][2])], ["349", 1], "the shell")
	assert_eq(rig.events_named("skill_used").size(), 1, "Events.skill_used")
	var weapon := PlayerCombatStats.from_character(c, db()).weapon
	var expected := def.action_ms(weapon.speed_tier if weapon != null else 6, db()) / 1000.0
	assert_near(float(res.lockout_s), expected, 1e-9, "the canonical action time at the weapon's speed")
	assert_true(pc.is_attacking(), "is_attacking() during the cast (C4)")
	assert_true(ps.is_casting(), "is_casting()")
	# Planted: walking input does not move the player during the cast; an attack press does not swing.
	var x0 := rig.w.player.global_position.x
	rig.w.bot.world_dir = Vector3.RIGHT
	rig.w.bot.press(&"attack")
	_tick_all(int(expected / MonsterTestRig.TICK) - 2)
	assert_near(rig.w.player.global_position.x, x0, 0.01, "planted for the cast")
	assert_eq(pc.attacks, 0, "no basic attack during the cast")
	var again := ps.cast(SNAILS)
	assert_eq(String(again.code), SkillBook.BUSY, "no second cast during the lockout")
	_tick_all(4)
	assert_false(pc.is_attacking(), "the lockout ended")
	assert_true(ps.cast(SNAILS).ok, "castable again: no cooldown")


func test_three_snails_kills_a_snail_and_awards_its_exp() -> void:
	var ps := _spawn({SNAILS: 3})
	var c := rig.character()
	_give("351", 5)
	var m := rig.spawn("2", Vector3(_px(150.0), 0.0, 0.0))
	var reward := m.def.exp_reward
	var exp0 := c.exp
	var casts := 0
	while m.is_alive() and casts < 5:
		var res := ps.cast(SNAILS)
		if not res.ok:
			_tick_all(1)
			continue
		casts += 1
		_tick_all(int(ceil(float(res.lockout_s) / MonsterTestRig.TICK)) + 1)
	assert_false(m.is_alive(), "the Snail died to Three Snails (%d casts)" % casts)
	assert_eq(rig.system.kills, 1, "a kill")
	assert_eq(c.exp - exp0, reward, "the Snail's canonical EXP")
	assert_true(rig.events_named("monster_killed").size() == 1, "Events.monster_killed")


func test_three_snails_targets_only_the_band() -> void:
	var ps := _spawn({SNAILS: 1})
	_give("348", 10)
	var close := rig.spawn("2", Vector3(_px(25.0), 0.0, 0.0))
	var behind := rig.spawn("2", Vector3(-_px(150.0), 0.0, 0.0))
	var far := rig.spawn("2", Vector3(_px(340.0), 0.0, 0.0))
	var res := ps.cast(SNAILS)
	assert_true(res.ok and res.target == null, "nothing in the band: a whiff")
	for m in [close, behind, far]:
		assert_eq(m.hp, m.def.max_hp, "untouched")
	# Nearest first, one target (a fresh lab: the Snails above wander meanwhile).
	rig.free_all()
	rig = MonsterTestRig.create(db(), 7)
	rig.floor(60.0)
	var ps2 := _spawn({SNAILS: 1})
	_give("348", 1)
	var near := rig.spawn("2", Vector3(_px(260.0), 0.0, 0.0))
	var nearer := rig.spawn("2", Vector3(_px(90.0), 0.0, _px(10.0)))
	var r2 := ps2.cast(SNAILS)
	assert_true(r2.ok and r2.target == nearer, "the nearest in the band")
	assert_eq(near.hp, near.def.max_hp, "one target only")


func test_three_snails_is_ground_only() -> void:
	var ps := _spawn({SNAILS: 1, RECOVERY: 1})
	var c := rig.character()
	_give("348", 2)
	rig.w.bot.press(&"jump")
	_tick_all(6)
	assert_false(rig.w.player.is_grounded(), "airborne")
	var mp0 := c.mp
	var res := ps.cast(SNAILS)
	assert_eq(String(res.code), SkillBook.POSITION, "refused in the air")
	assert_eq(c.mp, mp0, "nothing paid")
	assert_eq(c.inventory.count("348"), 2, "no shell spent")
	assert_true(ps.refusal_text(res, db()).contains("ground"), "the notice says where: %s" % ps.refusal_text(res, db()))
	assert_true(ps.cast(RECOVERY).ok, "Recovery casts in the air")


func test_recovery_heals_its_total_over_30_s_and_cools_down() -> void:
	var def := SkillDef.of(RECOVERY, db())
	for lv in range(1, 4):
		rig.free_all()
		rig = MonsterTestRig.create(db(), lv)
		rig.floor(60.0)
		var ps := _spawn({RECOVERY: lv})
		var c := rig.character()
		c.hp = 10
		var mp0 := c.mp
		var res := ps.cast(RECOVERY)
		assert_true(res.ok, "Lv%d cast" % lv)
		assert_eq(c.mp, mp0 - def.mp_cost(lv), "Lv%d MP cost" % lv)
		assert_eq(float(res.lockout_s), SkillRules.of(db()).buff_lockout_s, "the buff lockout (misostory/skills.json)")
		assert_near(EffectBook.cooldown_left(c, RECOVERY), def.cooldown_s(lv), 1e-9, "2 min cooldown")
		assert_eq(String(ps.cast(RECOVERY).code), SkillBook.COOLDOWN, "not again while cooling down")
		_tick_all(60 * 31)
		assert_eq(c.hp, 10 + def.hp_total(lv), "Lv%d: +%d HP over 30 s" % [lv, def.hp_total(lv)])
		assert_eq(_ticker().healed, def.hp_total(lv), "healed exactly the total")
		assert_false(EffectBook.has(c, PlayerSkills.effect_id(RECOVERY)), "the effect ended")
	# The cooldown runs out after 2 min of game time; Recovery casts from a rope too.
	var c2 := rig.character()
	_tick_all(60 * 90)
	assert_eq(EffectBook.cooldown_left(c2, RECOVERY), 0.0, "ready after 120 s")
	var ladder := ClimbableDef.from_sidecar({"name": "L", "kind": "rope", "bottom": [1.0, 0.0, 0.0], "top": [1.0, 4.0, 0.0],
		"foot_ground": [1.0, 0.0, 0.0], "top_exit": [1.5, 4.0, 0.0], "facing_xz": [1.0, 0.0], "descend_only": false})
	rig.w.player.set_climbables([ladder])
	assert_true(rig.w.player.grab_climbable(ladder), "on a rope")
	var ps2: PlayerSkills = rig.w.player.get_node(^"PlayerSkills")
	assert_eq(ps2.position_now(), "rope", "a rope position")
	assert_true(ps2.cast(RECOVERY).ok, "Recovery casts from a rope")


func test_recovery_never_heals_above_max_hp() -> void:
	var ps := _spawn({RECOVERY: 3})
	var c := rig.character()
	c.hp = StatCalculator.max_hp(c, db()) - 5
	assert_true(ps.cast(RECOVERY).ok, "cast")
	_tick_all(60 * 31)
	assert_eq(c.hp, StatCalculator.max_hp(c, db()), "capped at Max HP")
	assert_eq(_ticker().healed, 5, "the ticker counts only the HP actually restored")


func test_nimble_feet_speeds_up_the_walk_for_its_duration() -> void:
	var def := SkillDef.of(NIMBLE, db())
	var ps := _spawn({NIMBLE: 1})
	var p := rig.w.player
	var c := rig.character()
	# The game's PlayerController re-reads its stats on Events.stats_changed (the test player has no autoloads).
	rig.bus.connect(&"stats_changed", func() -> void: p.refresh_stats(c, db()))
	p.refresh_stats(c, db())
	var walk := func(ticks: int) -> float:
		var x0 := p.global_position.x
		rig.w.bot.world_dir = Vector3.RIGHT
		_tick_all(ticks)
		rig.w.bot.world_dir = Vector3.ZERO
		return (p.global_position.x - x0) / (ticks * MonsterTestRig.TICK)
	walk.call(20)
	var before: float = walk.call(60)
	var speed0 := StatCalculator.speed(c, db())
	assert_true(ps.cast(NIMBLE).ok, "cast")
	assert_eq(StatCalculator.speed(c, db()), speed0 + def.speed_bonus(1), "Speed +10")
	walk.call(20)
	var fast: float = walk.call(60)
	# movement.json: walk px/s = 125 x (Speed + 20) / 100, so the ratio is (110 + 20) / (100 + 20).
	var ratio := float(speed0 + def.speed_bonus(1) + 20) / float(speed0 + 20)
	assert_near(fast / before, ratio, 0.01, "walks %.4fx faster (%.3f -> %.3f m/s)" % [ratio, before, fast])
	assert_near(EffectBook.cooldown_left(c, NIMBLE), def.cooldown_s(1) - 80 * MonsterTestRig.TICK, 1e-6, "3 min cooldown running")
	_tick_all(int(def.duration_s(1) / MonsterTestRig.TICK))
	assert_false(EffectBook.has(c, PlayerSkills.effect_id(NIMBLE)), "ended after 10 s")
	assert_eq(StatCalculator.speed(c, db()), speed0, "back to base Speed")
	walk.call(20)
	assert_near(walk.call(60), before, 0.01, "walks at the base speed again")


func test_effects_end_at_death_and_cooldowns_keep_running() -> void:
	var ps := _spawn({NIMBLE: 2, RECOVERY: 2})
	var c := rig.character()
	assert_true(ps.cast(NIMBLE).ok and ps.cast(RECOVERY).ok, "both cast")
	assert_eq(c.effects.size(), 2, "two effects")
	rig.events.clear()
	rig.bus.emit_signal(&"player_died", "000000040")
	assert_true(c.effects.is_empty(), "the skill effects ended at death (misostory/skills.json)")
	assert_eq(rig.events_named("stats_changed").size(), 1, "the speed bonus left: stats_changed")
	assert_true(EffectBook.cooldown_left(c, NIMBLE) > 0.0 and EffectBook.cooldown_left(c, RECOVERY) > 0.0, "cooldowns kept")
	# Both switches are honoured: a table that keeps the effects and drops the cooldowns does exactly that.
	var table: Dictionary = (db().miso_table("skills") as Dictionary).duplicate(true)
	table["effects_on_death"]["end_effects"] = false
	table["effects_on_death"]["keep_cooldowns"] = false
	var edited := SkillRules.from_table(table)
	assert_eq(edited.errors.size(), 0, "the edited table reads cleanly")
	_ticker().rules = edited
	EffectBook.add(c, PlayerSkills.effect_id(NIMBLE), "skill:" + NIMBLE, 5.0, {"bonuses": {"speed": 10}})
	rig.bus.emit_signal(&"player_died", "000000040")
	assert_true(c.cooldowns.is_empty(), "keep_cooldowns false: the cooldowns cleared at death")
	assert_true(EffectBook.has(c, PlayerSkills.effect_id(NIMBLE)), "end_effects false: the effect stays")


func test_refusals_change_nothing() -> void:
	var ps := _spawn({SNAILS: 1, NIMBLE: 1})
	var c := rig.character()
	var p := rig.w.player
	var snapshot := func() -> String:
		return var_to_str([c.mp, c.inventory.to_dict(), c.cooldowns, c.effects])
	var before: String = snapshot.call()
	assert_eq(String(ps.cast(RECOVERY).code), SkillBook.NOT_LEARNED, "not learned")
	assert_eq(String(ps.cast(SNAILS).code), SkillBook.NO_ITEM, "no shell")
	c.mp = 1
	assert_eq(String(ps.cast(NIMBLE).code), SkillBook.NO_MP, "no MP")
	c.mp = 500
	before = snapshot.call()
	p.set_input_enabled(false)
	assert_eq(String(ps.cast(NIMBLE).code), SkillBook.BUSY, "a modal or warp holds the input")
	p.set_input_enabled(true)
	rig.w.bot.press(&"attack")
	rig.tick()
	assert_eq(rig.system.player_combat.attacks, 1, "a basic attack started")
	assert_eq(String(ps.cast(NIMBLE).code), SkillBook.BUSY, "not during a basic attack")
	p.die()
	_tick_all(60)
	assert_eq(String(ps.cast(NIMBLE).code), SkillBook.DEAD, "not while dead")
	assert_eq(snapshot.call(), before, "no refusal paid anything or started a cooldown")
	assert_eq(rig.events_named("skill_used").size(), 0, "no skill_used")


func test_the_console_cast_passes_only_the_consoles_input_hold() -> void:
	var ps := _spawn({NIMBLE: 1, SNAILS: 1})
	var p := rig.w.player
	var c := rig.character()
	# What the open debug console does (GameContext.push_modal): the player's input is held.
	p.set_input_enabled(false)
	assert_eq(String(ps.cast(NIMBLE).code), SkillBook.BUSY, "a key press is refused while a modal holds the input")
	assert_eq(ps._cmd_cast(PackedStringArray(["nimble", "feet"])), "cast %s" % NIMBLE, "the console's 'cast' still casts")
	assert_true(EffectBook.has(c, PlayerSkills.effect_id(NIMBLE)), "Nimble Feet is active")
	# Only the input hold is skipped: the skill rules and the death check still refuse.
	assert_true(ps._cmd_cast(PackedStringArray([SNAILS])).begins_with("refused: %s" % SkillBook.NO_ITEM), "no shell")
	p.set_input_enabled(true)
	p.die()
	_tick_all(5)
	assert_true(ps._cmd_cast(PackedStringArray([NIMBLE])).begins_with("refused: %s" % SkillBook.DEAD), "not while dead")


func test_casting_stands_a_seated_player_up() -> void:
	var ps := _spawn({NIMBLE: 1})
	var gd := GDScript.new()
	gd.source_code = "\n".join(["extends PlayerController", "var seated := true", "var stood: Array = []",
		"func is_seated() -> bool:", "\treturn seated", "func stand_up(reason: StringName) -> void:",
		"\tseated = false", "\tstood.append(reason)", ""])
	assert_eq(gd.reload(), OK, "stub script")
	var stub := PlayerController.new()
	stub.set_script(gd)
	stub.use_autoloads = false
	stub.model = MovementModel.from_db(db())
	stub.set_input_source(rig.w.bot)
	rig.w.host.add_child(stub)
	ps.player = stub
	stub.state = PlayerController.State.GROUND
	assert_true(ps.cast(NIMBLE).ok, "cast while seated")
	assert_false(bool(stub.get("seated")), "stood up first (C5)")
	assert_eq(stub.get("stood"), [&"skill"], "with the reason 'skill'")
