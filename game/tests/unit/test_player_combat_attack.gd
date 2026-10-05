extends TestCase
## PlayerCombat: the basic attack in the world. Attack lockout per weapon (canonical attack-speed ladder), held and
## buffered attacks, the ground root, the canonical hit box in front of the facing (MeleeQuery over CombatReach),
## nearest-target selection, never a target behind, the isometric depth tolerance, bare hands, and the damage path
## (CombatFormula.resolve_physical_hit with the same seeded RNG).

var rig: MonsterTestRig


func before_each() -> void:
	rig = MonsterTestRig.create(db(), 99)
	rig.floor(40.0)


func after_each() -> void:
	rig.free_all()


func _press_attack() -> void:
	rig.w.bot.press(&"attack")


func _expected_lockout_s(weapon_id: String, action: String) -> float:
	var w := WeaponProfile.bare_hands(db()) if weapon_id == "" else WeaponProfile.for_weapon_id(weapon_id, db())
	return w.attack_duration_ms(action, db()) / 1000.0


# --- lockout --------------------------------------------------------------------------------------------------------

func test_lockout_follows_the_weapon_speed() -> void:
	# Wooden Club (tier 5, 750 ms), Sword (tier 4, 720 ms) and bare hands (adaptation tier 6, 810 ms) from the ladder.
	for weapon in ["585", "541", ""]:
		var r := MonsterTestRig.create(db(), 5)
		r.floor(20.0)
		r.set_weapon(weapon)
		r.spawn_player(Vector3.ZERO, Vector3.RIGHT)
		var pc := r.system.player_combat
		r.w.bot.press(&"attack")
		r.tick()
		assert_eq(pc.attacks, 1, "%s: attacked" % weapon)
		var expected := _expected_lockout_s(weapon, pc.last_action)
		assert_near(pc.last_lockout_s, expected, 1e-9, "%s: lockout = attack_duration_ms(%s)" % [weapon, pc.last_action])
		assert_true(expected > 0.5 and expected < 1.1, "%s: plausible cycle %.3f s" % [weapon, expected])
		# Presses during the lockout do nothing (and are not buffered when they come too early).
		var ticks_locked := int(floor(expected / MonsterTestRig.TICK)) - int(ceil(pc.input_buffer_s / MonsterTestRig.TICK)) - 1
		for i in ticks_locked:
			if i % 5 == 0:
				r.w.bot.press(&"attack")
			r.tick()
		assert_eq(pc.attacks, 1, "%s: locked out" % weapon)
		r.run(int(ceil(pc.input_buffer_s / MonsterTestRig.TICK)) + 3)
		r.w.bot.press(&"attack")
		r.tick()
		assert_eq(pc.attacks, 2, "%s: attacks again after the lockout" % weapon)
		r.free_all()


func test_holding_attack_repeats_at_the_lockout_rate() -> void:
	rig.set_weapon("541")
	rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var pc := rig.system.player_combat
	rig.w.bot.hold(&"attack")
	var tick_of_attack: Array[int] = []
	var last := 0
	for i in 60 * 4:
		rig.tick()
		if pc.attacks != last:
			last = pc.attacks
			tick_of_attack.append(i)
	assert_true(tick_of_attack.size() >= 4, "several attacks in 4 s (%d)" % tick_of_attack.size())
	var cycle := _expected_lockout_s("541", "swing")
	for k in range(1, tick_of_attack.size()):
		var gap := (tick_of_attack[k] - tick_of_attack[k - 1]) * MonsterTestRig.TICK
		assert_near(gap, cycle, MonsterTestRig.TICK * 1.01, "held attack repeats every %.3f s" % cycle)


func test_held_attack_averages_the_canonical_cadence() -> void:
	# The Sword's ordinary cycle is 720 ms = 43.2 ticks: rounding every cycle up gave 733 ms (playtest finding
	# held-attack-cadence). Carrying the sub-tick overshoot makes 20 held swings take 20 x 720 ms within one tick.
	rig.set_weapon("541")
	rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var pc := rig.system.player_combat
	rig.w.bot.hold(&"attack")
	var first := -1
	var tick_of_21st := -1
	for i in 60 * 20:
		var before := pc.attacks
		rig.tick()
		if pc.attacks != before:
			if first < 0:
				first = i
			if pc.attacks == 21:
				tick_of_21st = i
				break
	assert_true(tick_of_21st > 0, "21 attacks while holding")
	var cycle := _expected_lockout_s("541", pc.last_action)
	var span := (tick_of_21st - first) * MonsterTestRig.TICK
	assert_near(span / 20.0, cycle, MonsterTestRig.TICK / 20.0 + 1e-6, "average held cycle over 20 swings")


func test_a_press_while_dead_is_not_buffered_into_the_respawn() -> void:
	rig.set_weapon("541")
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var pc := rig.system.player_combat
	p.die()
	_press_attack()
	rig.tick()
	assert_eq(pc.attacks, 0, "no attack while dead")
	p.revive()
	rig.run(3)
	assert_eq(pc.attacks, 0, "the press made while dead does not fire after the revive")


func test_a_press_just_before_the_lockout_ends_is_buffered() -> void:
	rig.set_weapon("541")
	rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var pc := rig.system.player_combat
	_press_attack()
	rig.tick()
	var cycle := pc.last_lockout_s
	var ticks := int(round(cycle / MonsterTestRig.TICK))
	rig.run(ticks - 4)
	_press_attack()  # 4 ticks early: inside the buffer window
	rig.run(6)
	assert_eq(pc.attacks, 2, "the early press fired when the lockout ended")


func test_no_attack_while_dead_disabled_or_in_hitstun() -> void:
	rig.set_weapon("541")
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var pc := rig.system.player_combat
	p.set_input_enabled(false)
	_press_attack()
	rig.tick()
	assert_eq(pc.attacks, 0, "input disabled (dialogue, warp)")
	p.set_input_enabled(true)
	p.apply_knockback(Vector3.LEFT, 1.0, 0.1)
	_press_attack()
	rig.tick()
	assert_eq(pc.attacks, 0, "in knockback hit-stun")
	rig.run(60)
	p.die()
	_press_attack()
	rig.tick()
	assert_eq(pc.attacks, 0, "dead")


func test_a_ground_attack_roots_the_player_and_an_air_attack_does_not() -> void:
	rig.set_weapon("541")
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var pc := rig.system.player_combat
	rig.w.bot.world_dir = Vector3.RIGHT
	rig.run(20)
	_press_attack()
	rig.tick()
	var x0 := p.global_position.x
	rig.run(int(pc.last_lockout_s / MonsterTestRig.TICK) - 2)
	assert_near(p.global_position.x, x0, 0.05, "planted during the ground attack")
	assert_true(p.input_source is AttackLockInput, "the lock wraps the bot")
	rig.run(10)
	assert_true(p.global_position.x > x0 + 0.1, "walks again after the lockout")
	# In the air: jump, attack at the top, keep drifting.
	rig.w.bot.press(&"jump")
	rig.run(8)
	assert_false(p.is_grounded(), "airborne")
	var xa := p.global_position.x
	_press_attack()
	rig.run(8)
	assert_true(p.global_position.x > xa + 0.1, "an air attack keeps the jump's momentum")


# --- hit box and targets ----------------------------------------------------------------------------------------------

func test_hits_the_nearest_monster_in_front_never_one_behind() -> void:
	rig.set_weapon("541")
	rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var behind := rig.spawn("2", Vector3(-1.0, 0, 0))
	var near := rig.spawn("2", Vector3(1.2, 0, 0))
	var far := rig.spawn("2", Vector3(1.9, 0, 0.1))
	for m in [behind, near, far]:
		m.brain.mode = MonsterBrain.Mode.IDLE
		m.brain.timer = 1000.0
	var pc := rig.system.player_combat
	var hit := {}
	for i in 30:
		var t := pc.attack()
		if t != null:
			hit[t.name] = int(hit.get(t.name, 0)) + 1
		pc.lockout_left = 0.0
		near.hp = near.def.max_hp
		far.hp = far.def.max_hp
	assert_false(hit.has(behind.name), "never the monster behind (1 m back)")
	assert_true(hit.has(near.name), "the nearest monster in front is hit")
	assert_false(hit.has(far.name), "only one target per basic attack, the nearest")


func test_target_selection_rules_in_isolation() -> void:
	var sword := WeaponProfile.for_weapon_id("541", db())
	var hands := WeaponProfile.bare_hands(db())
	var weapon := sword
	var depth := CombatReach.attack_box_depth_px(db())
	var stats := MonsterCombatStats.from_id("2", db())
	var tz := stats.touch_zone_px
	var tzd := CombatReach.touch_zone_depth_px(stats, db())
	var origin := Vector3(5, 1, -3)
	var facing := Vector3(1, 0, 1).normalized()
	var lat := Vector3.UP.cross(facing)
	var cases: Array = []
	for pres in sword.presentations_for("swing") + sword.presentations_for("stab"):
		cases.append([sword, pres])
	for pres in hands.presentations_for("stab"):
		cases.append([hands, pres])
	assert_eq(cases.size(), 7, "3 swings + 2 thrusts (Sword) + 2 punches")
	for case in cases:
		var pres: String = case[1]
		var box := CombatReach.attack_box_px(case[0], pres, true, 1)
		var cands := [
			{"node": "behind", "feet": origin - facing * 1.0, "touch_px": tz, "depth_px": tzd, "spawn_order": 1},
			{"node": "front_far", "feet": origin + facing * 1.6, "touch_px": tz, "depth_px": tzd, "spawn_order": 2},
			{"node": "front_near", "feet": origin + facing * 1.1, "touch_px": tz, "depth_px": tzd, "spawn_order": 3},
			{"node": "twin_a", "feet": origin + facing * 1.1 + lat * 0.4, "touch_px": tz, "depth_px": tzd, "spawn_order": 5},
			{"node": "wide", "feet": origin + facing * 1.1 + lat * 3.0, "touch_px": tz, "depth_px": tzd, "spawn_order": 0},
			{"node": "above", "feet": origin + facing * 1.1 + Vector3.UP * 3.0, "touch_px": tz, "depth_px": tzd, "spawn_order": 0},
		]
		var picked := MeleeQuery.pick(origin, facing, box, depth, cands, 1)
		assert_eq(picked.size(), 1, "%s hits one" % pres)
		if picked.size() == 1:
			assert_eq(String(picked[0]["node"]), "front_near", "%s picks the nearest in front" % pres)
		var all := MeleeQuery.pick(origin, facing, box, depth, cands, 10)
		var names := []
		for e in all:
			names.append(String(e["node"]))
		assert_false("behind" in names, "%s: nothing 1 m behind" % pres)
		assert_false("wide" in names, "%s: 3 m to the side is out of the depth tolerance" % pres)
		assert_false("above" in names, "%s: 3 m above is out of reach" % pres)
	# A distance tie goes to the monster that appeared first.
	var box2 := CombatReach.attack_box_px(weapon, "stabO1", true, 1)
	var tie := [
		{"node": "late", "feet": origin + facing * 1.2, "touch_px": tz, "depth_px": tzd, "spawn_order": 9},
		{"node": "early", "feet": origin + facing * 1.2, "touch_px": tz, "depth_px": tzd, "spawn_order": 2},
	]
	assert_eq(String(MeleeQuery.pick(origin, facing, box2, depth, tie, 1)[0]["node"]), "early", "tie: first to appear")


func test_depth_tolerance_lets_a_monster_slightly_off_the_facing_line_be_hit() -> void:
	var weapon := WeaponProfile.bare_hands(db())
	var depth := CombatReach.attack_box_depth_px(db())
	var stats := MonsterCombatStats.from_id("2", db())
	var tz := stats.touch_zone_px
	var tzd := CombatReach.touch_zone_depth_px(stats, db())
	var box := CombatReach.attack_box_px(weapon, "stabO1", true, 1)
	var reach_mid := WorldScale.actor((box.position.x + box.end.x) * 0.5)
	var half_depth := WorldScale.actor((depth + tzd) * 0.5)
	var inside := MeleeQuery.local_px(Vector3.ZERO, Vector3.RIGHT, Vector3(reach_mid, 0, half_depth * 0.9))
	var outside := MeleeQuery.local_px(Vector3.ZERO, Vector3.RIGHT, Vector3(reach_mid, 0, half_depth * 1.1))
	assert_true(MeleeQuery.attack_hits(box, depth, inside, tz, tzd), "within the isometric depth")
	assert_false(MeleeQuery.attack_hits(box, depth, outside, tz, tzd), "beyond it")


func test_bare_hands_punch_deals_one_and_a_weapon_deals_the_formula() -> void:
	rig.set_weapon("")
	rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var m := rig.spawn("2", Vector3(1.0, 0, 0))
	m.brain.timer = 1000.0
	var pc := rig.system.player_combat
	var t := pc.attack()
	assert_eq(t, m, "a punch reaches a monster 1 m ahead")
	assert_eq(pc.last_action, "stab", "bare hands stab (canonical odds)")
	assert_eq(pc.last_result.final, 1, "bare hands deal the final-clamp minimum (combat.json bare_hands)")
	assert_eq(m.hp, m.def.max_hp - 1, "1 HP off")
	# With a sword, the same seeded RNG reproduces the formula result.
	rig.set_weapon("541")
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = 4242
	rig.rng.seed = 4242
	pc.lockout_left = 0.0
	var before := m.hp
	pc.attack()
	var stats := PlayerCombatStats.from_character(rig.character(), db())
	var pick := CombatFormula.choose_ordinary_action(stats.weapon, seed_rng)
	var expected := CombatFormula.resolve_physical_hit(stats, m.def.stats, pick["action"], seed_rng, db(), {"presentation": pick["presentation"]})
	assert_eq(pc.last_action, String(pick["action"]), "same action draw")
	assert_eq(pc.last_result.final, expected.final, "same damage as CombatFormula with the same seed")
	assert_eq(m.hp, maxi(0, before - expected.final), "applied to the monster")
	assert_true(expected.final >= 1, "a landed hit")


func test_a_whiff_hits_nothing_and_still_locks_out() -> void:
	rig.set_weapon("541")
	rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var m := rig.spawn("2", Vector3(5.0, 0, 0))
	var pc := rig.system.player_combat
	assert_eq(pc.attack(), null, "nothing in reach")
	assert_true(pc.lockout_left > 0.0, "a whiff still takes the attack's time")
	assert_eq(m.hp, m.def.max_hp)
	assert_eq(rig.events_named("monster_hit").size(), 0)


func test_hits_and_misses_are_announced_and_shown() -> void:
	rig.set_weapon("541")
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var m := rig.spawn("9", Vector3(1.3, 0, 0))
	m.brain.timer = 1000.0
	var pc := rig.system.player_combat
	pc.attack()
	var hits := rig.events_named("monster_hit")
	assert_eq(hits.size(), 1, "Events.monster_hit")
	assert_eq(String(hits[0][1]), "9")
	assert_eq(int(hits[0][2]), pc.last_result.final)
	assert_true(rig.system.damage_numbers.live_texts().has(str(pc.last_result.final)), "a damage number shows")
	# Every Maple Island monster has AVOID 0, so misses need a monster with avoidability: give this one a lot.
	m.def = MonsterDef.build("9", db())
	m.def.stats.avoid = 999
	var missed := false
	for i in 20:
		pc.lockout_left = 0.0
		pc.attack()
		if pc.last_result != null and pc.last_result.missed:
			missed = true
			break
	assert_true(missed, "a miss happens against high avoidability")
	assert_true(rig.events_named("monster_missed").size() >= 1, "Events.monster_missed")
	assert_true(rig.system.damage_numbers.live_texts().has("MISS"), "MISS shows")
	assert_true(p != null)


# --- integration seam ------------------------------------------------------------------------------------------------

func test_setup_gives_the_player_one_player_combat_and_owns_the_fx() -> void:
	var p := rig.w.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var ctx := GameContext.new()
	ctx.player = p
	rig.system.setup(ctx)
	rig.system.setup(ctx)
	var count := 0
	for c in p.get_children():
		if c is PlayerCombat:
			count += 1
	assert_eq(count, 1, "one PlayerCombat child, even after a second setup")
	assert_eq(rig.system.player_combat, p.get_node(^"PlayerCombat"))
	assert_eq(rig.system.player_combat.system, rig.system, "wired to the system")
	assert_true(rig.system.damage_numbers is DamageNumbers and rig.system.damage_numbers.get_parent() == rig.system, "numbers layer")
	assert_true(rig.system.attack_fx is AttackFx and rig.system.attack_fx.get_parent() == rig.system, "attack FX layer")
	assert_true(rig.system.view == null, "no world in the context: no factory, no crash")


func test_monster_system_scene_is_the_system() -> void:
	var scene := load("res://scenes/systems/monster_system.tscn") as PackedScene
	assert_true(scene != null, "scenes/systems/monster_system.tscn exists")
	var n := scene.instantiate()
	assert_true(n is MonsterSystem and n.has_method("setup"), "its root implements setup(ctx)")
	n.free()
	var m := (load("res://scenes/actors/monster.tscn") as PackedScene).instantiate()
	assert_true(m is Monster, "scenes/actors/monster.tscn is a Monster")
	assert_eq((m as Monster).collision_layer, WorldLayers.MONSTERS, "on the monsters layer")
	assert_eq((m as Monster).collision_mask, WorldLayers.MONSTER_MASK, "with MONSTER_MASK")
	m.free()


func test_removing_player_combat_mid_attack_never_leaves_the_player_planted() -> void:
	rig.set_weapon("541")
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var pc := rig.system.player_combat
	_press_attack()
	rig.tick()
	assert_true(p.input_source is AttackLockInput and (p.input_source as AttackLockInput).locked, "planted")
	p.remove_child(pc)
	assert_true(p.input_source == rig.w.bot, "the bot is handed back")
	rig.w.bot.world_dir = Vector3.RIGHT
	var x0 := p.global_position.x
	for i in 20:
		p.step(MonsterTestRig.TICK)
	assert_true(p.global_position.x > x0 + 0.3, "walks again")
	pc.free()
	rig.system.player_combat = null


func test_a_swapped_source_put_back_by_its_owner_is_the_original_again() -> void:
	# The pattern other systems use (debug sandbox walk, checks): save the source, put a bot in, put the saved one back.
	# The re-wrap must never mutate the decorator the caller saved, or the caller gets the bot back, not the keyboard.
	rig.set_weapon("541")
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var original := rig.w.bot
	rig.tick()
	var before: InputSource = p.input_source
	assert_true(before is AttackLockInput and (before as AttackLockInput).inner == original, "wrapped once")
	var other := BotInput.new()
	p.set_input_source(other)
	rig.tick()
	assert_true(p.input_source is AttackLockInput and (p.input_source as AttackLockInput).inner == other,
		"the new source is wrapped")
	assert_true((before as AttackLockInput).inner == original, "the saved decorator still wraps the original source")
	p.set_input_source(before)
	rig.tick()
	assert_true(p.input_source == before and (before as AttackLockInput).inner == original, "the original is back")
	# And it still drives the player and the attack.
	original.press(&"attack")
	var n := rig.system.player_combat.attacks
	rig.tick()
	assert_eq(rig.system.player_combat.attacks, n + 1, "the restored source attacks")


func test_a_rewrap_mid_attack_keeps_the_player_planted() -> void:
	rig.set_weapon("541")
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	rig.w.bot.press(&"attack")
	rig.tick()
	assert_true((p.input_source as AttackLockInput).locked, "planted by the attack")
	var other := BotInput.new()
	other.world_dir = Vector3.RIGHT
	p.set_input_source(other)
	rig.tick()
	assert_true(p.input_source is AttackLockInput and (p.input_source as AttackLockInput).locked,
		"the new wrapper inherits the lock while the lockout runs")
	rig.run(int(ceil(rig.system.player_combat.last_lockout_s / MonsterTestRig.TICK)) + 2)
	assert_false((p.input_source as AttackLockInput).locked, "released when the lockout ends")


func test_the_target_count_is_one_and_data_can_raise_it() -> void:
	rig.set_weapon("541")
	rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var near := rig.spawn("2", Vector3(1.0, 0, 0))
	var far := rig.spawn("2", Vector3(1.3, 0, 0.05))
	for m in [near, far]:
		m.brain.mode = MonsterBrain.Mode.IDLE
		m.brain.timer = 1000.0
	var pc := rig.system.player_combat
	var feel: Dictionary = db().miso_table("combat")["player_attack"]
	assert_eq(pc.basic_attack_targets, int(feel["basic_attack_targets"]), "the count comes from combat.json player_attack")
	assert_eq(pc.basic_attack_targets, 1, "a classic basic attack hits one monster")
	# Every presentation of the Sword must reach both for this check; retry until a swing does.
	var both := false
	pc.basic_attack_targets = 2
	for i in 20:
		pc.lockout_left = 0.0
		near.hp = near.def.max_hp
		far.hp = far.def.max_hp
		var t := pc.attack()
		if near.hp < near.def.max_hp and far.hp < far.def.max_hp:
			both = true
			assert_eq(t, near, "the nearest is returned first")
			break
	assert_true(both, "a raised count (combat.json player_attack.basic_attack_targets) hits each target with its own roll")
