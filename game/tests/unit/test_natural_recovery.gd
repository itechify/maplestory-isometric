extends TestCase
## Natural HP recovery: the project owner's rule (docs/ITERATION_THREE_BRIEF.md "Natural HP Regeneration";
## data/misostory/recovery.json natural_hp): 10 HP per 10 s of eligible time, eligible = standing still or seated, every
## other activity pauses the clock without resetting it, never above Max HP, the clock holds at full HP, and the clock
## lives in CharacterState.natural_recovery.hp_rest_s so a save keeps it. The brief's test list: 10 continuous eligible
## seconds, 9.9 seconds, partial accumulation, movement pause, jump pause, attack pause, resume after pause, sitting,
## full HP, save/load. Plus the chair's own bonus clock (contract C5), the MP source gap, and the NaturalRecovery node on
## a real PlayerController (PlayerTestWorld) reading activity() (contract C4).

const TICK := 1.0 / 60.0
const RELAXER := "522"

var w: PlayerTestWorld = null


func parity_keys() -> Dictionary:
	var regen := ["mechanic:natural-hp-regen"]
	return {
		"test_shipped_rule_is_the_owners_rule_verified_against_the_brief": regen,
		"test_mp_has_no_natural_recovery_and_the_gap_is_recorded": ["mechanic:natural-mp-regen"],
		"test_ten_continuous_eligible_seconds_heal_one_tick": regen,
		"test_nine_point_nine_seconds_heal_nothing": regen,
		"test_partial_accumulation_six_still_five_moving_four_still_reaches_the_tick": regen + ["mechanic:natural-hp-regen-pause-walking"],
		"test_movement_pauses_the_clock_without_resetting_it": ["mechanic:natural-hp-regen-pause-walking"],
		"test_jumping_pauses_the_clock_without_resetting_it": ["mechanic:natural-hp-regen-pause-jumping"],
		"test_attacking_pauses_the_clock_without_resetting_it": ["mechanic:natural-hp-regen-pause-attacking"],
		"test_resume_after_pause_counts_only_eligible_time": regen,
		"test_sitting_is_eligible": ["mechanic:natural-hp-regen-sitting"],
		"test_full_hp_holds_the_clock_and_never_exceeds_max_hp": regen,
		"test_save_and_load_keep_the_paused_clock": regen,
		"test_chair_bonus_runs_on_its_own_clock_while_seated": ["chair:522", "mechanic:chair-hp-bonus"],
		"test_node_pauses_for_real_walking_jumping_and_attacking": regen + ["mechanic:natural-hp-regen-pause-walking",
			"mechanic:natural-hp-regen-pause-jumping", "mechanic:natural-hp-regen-pause-attacking"],
		"test_node_heals_a_seated_player_with_the_chair_bonus": ["chair:522", "mechanic:natural-hp-regen-sitting",
			"mechanic:chair-hp-bonus"],
	}


## A stand-in for the Game autoload: the live character, has_active_game, is_character_dead and change_hp.
class FakeGame:
	extends Node
	var character: CharacterState = CharacterState.new()
	var content: ContentDB = null
	var dead: bool = false
	var healed: int = 0

	func has_active_game() -> bool:
		return true

	func is_character_dead() -> bool:
		return dead

	func change_hp(delta: int) -> int:
		var applied := StatCalculator.change_hp(character, delta, content)
		healed += applied
		return applied


## A stand-in for MapSession: idle unless a warp is in flight.
class FakeSession:
	extends Node
	var idle: bool = true

	func is_idle() -> bool:
		return idle


## A stand-in for PlayerCombat: is_attacking() as set.
class FakeCombat:
	extends Node
	var attacking: bool = false

	func is_attacking() -> bool:
		return attacking


## A player that only ever stands still.
class StillPlayer:
	extends Node3D

	func activity() -> StringName:
		return &"still"


func after_each() -> void:
	if w != null:
		w.free_all()
		w = null


func _rule() -> NaturalRecoveryRule:
	return NaturalRecoveryRule.from_config({
		"natural_hp": {"hp_per_tick": 10, "tick_s": 10.0, "eligible_activities": ["still", "seated"]},
		"chair_bonus": {"stand_resets_clock": true, "full_hp_holds_clock": true},
	})


## Runs `seconds` of 60 Hz ticks in `activity` and returns the HP handed out (HP is advanced as it heals).
func _run(r: NaturalRecoveryRule, seconds: float, activity: StringName, hp: int, max_hp: int, chair_hp: int = 0,
		chair_s: float = 0.0) -> int:
	var healed := 0
	for _i in int(round(seconds * 60.0)):
		healed += r.step(TICK, activity, hp + healed, max_hp, chair_hp, chair_s)
	return healed


func test_shipped_rule_is_the_owners_rule_verified_against_the_brief() -> void:
	var table: Dictionary = db().miso_table("recovery")
	var hp: Dictionary = table["natural_hp"]
	assert_eq(int(hp["hp_per_tick"]), 10, "10 HP")
	assert_eq(float(hp["tick_s"]), 10.0, "per 10 s")
	assert_eq(PackedStringArray(hp["eligible_activities"]), PackedStringArray(["still", "seated"]),
		"eligible: standing still and sitting")
	assert_eq(hp["verified"], true, "the owner's rule, verified against the brief")
	assert_true(String(hp["verified_against"]).contains("ITERATION_THREE_BRIEF"), "verified against the brief")
	var prov: Dictionary = table["provenance"]["natural_hp"]
	assert_eq(prov["authority"], "Project owner", "authority")
	assert_true(String(prov["decision"]).contains("ITERATION_THREE_BRIEF"), "names the brief as the decision")
	assert_false((db().miso_table("combat") as Dictionary).has("natural_recovery"),
		"the Iteration Two adaptation (combat delay, reset) is gone from combat.json")
	var canon: Dictionary = db().formula("recovery")["natural_regeneration"]
	assert_eq(bool(canon["documented_values"]), false, "MeowDB publishes no regen numbers")
	var r := NaturalRecoveryRule.from_db(db())
	assert_true(r != null, "the shipped table builds a rule")
	assert_eq(r.hp_per_tick, 10)
	assert_eq(r.tick_s, 10.0)
	for a: StringName in [&"walking", &"jumping", &"attacking", &"climbing", &"hitstun", &"dead", &"other"]:
		assert_false(r.is_eligible(a), "%s is not eligible" % a)


func test_mp_has_no_natural_recovery_and_the_gap_is_recorded() -> void:
	var mp: Dictionary = db().miso_table("recovery")["natural_mp"]
	assert_eq(mp["mp_per_tick"], null, "no MP amount")
	assert_eq(mp["tick_s"], null, "no MP interval")
	assert_eq(mp["status"], "unresolved_source_gap", "an explicit source gap")
	assert_eq(mp["verified"], false)
	assert_eq(db().formula("recovery")["natural_regeneration"]["mp_per_tick"], null, "MeowDB documents none")
	assert_true(String(mp["reason"]).contains("not stated"), "the reason quotes the canonical gap")


func test_ten_continuous_eligible_seconds_heal_one_tick() -> void:
	var r := _rule()
	assert_eq(_run(r, 10.0, &"still", 20, 50), 10, "600 ticks of 1/60 s standing still give exactly one tick")
	assert_near(r.rest_s, 0.0, 1e-4, "the clock starts over after the tick")
	assert_eq(_run(r, 10.0, &"still", 30, 50), 10, "then one tick per 10 s")


func test_nine_point_nine_seconds_heal_nothing() -> void:
	var r := _rule()
	assert_eq(_run(r, 9.9, &"still", 20, 50), 0, "nothing before 10 s")
	assert_near(r.rest_s, 9.9, 1e-4, "9.9 s banked")
	assert_eq(_run(r, 0.1, &"still", 20, 50), 10, "the tick at 10.0 s")


func test_partial_accumulation_six_still_five_moving_four_still_reaches_the_tick() -> void:
	var r := _rule()
	assert_eq(_run(r, 6.0, &"still", 20, 50), 0, "6 s still")
	assert_eq(_run(r, 5.0, &"walking", 20, 50), 0, "5 s moving: no tick")
	assert_near(r.rest_s, 6.0, 1e-4, "the 6 s are kept (paused, not reset)")
	assert_eq(_run(r, 3.9, &"still", 20, 50), 0, "3.9 s more: 9.9 s eligible")
	assert_eq(_run(r, 0.1, &"still", 20, 50), 10, "4 s more still reaches the 10 s tick (the brief's example)")


func test_movement_pauses_the_clock_without_resetting_it() -> void:
	var r := _rule()
	_run(r, 8.0, &"still", 20, 50)
	assert_eq(_run(r, 30.0, &"walking", 20, 50), 0, "30 s of walking: no tick")
	assert_near(r.rest_s, 8.0, 1e-4, "walking pauses")
	assert_eq(_run(r, 2.0, &"still", 20, 50), 10, "2 s more still: the tick")


func test_jumping_pauses_the_clock_without_resetting_it() -> void:
	var r := _rule()
	_run(r, 7.0, &"still", 20, 50)
	assert_eq(_run(r, 20.0, &"jumping", 20, 50), 0, "20 s airborne: no tick")
	assert_near(r.rest_s, 7.0, 1e-4, "jumping pauses")
	assert_eq(_run(r, 3.0, &"still", 20, 50), 10)


func test_attacking_pauses_the_clock_without_resetting_it() -> void:
	var r := _rule()
	_run(r, 5.0, &"still", 20, 50)
	assert_eq(_run(r, 20.0, &"attacking", 20, 50), 0, "20 s attacking (planted, speed 0): no tick")
	assert_near(r.rest_s, 5.0, 1e-4, "attacking pauses, and there is no combat delay afterwards")
	assert_eq(_run(r, 5.0, &"still", 20, 50), 10)


func test_resume_after_pause_counts_only_eligible_time() -> void:
	var r := _rule()
	var healed := 0
	var still := 0.0
	# 2 s still, then something else, five times over: 10 s eligible in total, 25 s ineligible in between.
	for a: StringName in [&"walking", &"jumping", &"attacking", &"climbing", &"hitstun"]:
		healed += _run(r, 2.0, &"still", 20, 50)
		still += 2.0
		healed += _run(r, 5.0, a, 20, 50)
		if still < 10.0:
			assert_eq(healed, 0, "%.0f s eligible after %s: no tick yet" % [still, a])
	assert_eq(healed, 10, "the fifth 2 s still segment completes 10 eligible seconds")
	assert_near(r.rest_s, 0.0, 1e-4)


func test_sitting_is_eligible() -> void:
	var r := _rule()
	assert_eq(_run(r, 10.0, &"seated", 20, 50), 10, "10 s seated (no chair bonus given): one natural tick")
	_run(r, 4.0, &"seated", 30, 50)
	assert_eq(_run(r, 6.0, &"still", 30, 50), 10, "seated and standing still time add up on the same clock")


func test_full_hp_holds_the_clock_and_never_exceeds_max_hp() -> void:
	var r := _rule()
	assert_eq(_run(r, 10.0, &"still", 46, 50), 4, "clamped to Max HP")
	_run(r, 5.0, &"still", 20, 50)
	assert_eq(_run(r, 60.0, &"still", 50, 50), 0, "full HP: nothing")
	assert_near(r.rest_s, 5.0, 1e-4, "the clock holds while HP is full")
	assert_eq(_run(r, 5.0, &"still", 40, 50), 10, "after damage it continues from 5 s")
	assert_eq(_run(r, 30.0, &"still", 0, 50), 0, "HP 0: nothing")
	assert_eq(_run(r, 30.0, &"dead", 50, 60), 0, "dead (respawn HP already set): nothing")


func test_save_and_load_keep_the_paused_clock() -> void:
	var g := _fake_game(20)
	var nr := _detached_node(g)
	nr.player = null  # no player: the node reports "other"
	assert_eq(nr.activity(), &"other")
	# Accumulate 6 s through the rule as the node does, on the live character's clock.
	var c := g.character
	var r := nr.rule
	r.rest_s = c.natural_recovery["hp_rest_s"]
	_run(r, 6.0, &"still", c.hp, StatCalculator.max_hp(c, db()))
	c.natural_recovery["hp_rest_s"] = r.rest_s
	var saved: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	var loaded := CharacterState.from_dict(saved)
	assert_near(float(loaded.natural_recovery["hp_rest_s"]), 6.0, 1e-4, "the save holds the 6 s")
	assert_eq(loaded.natural_recovery.keys(), ["hp_rest_s"], "only the clock: no seated state is saved")
	r.rest_s = 0.0  # the rule's own copy is irrelevant: the node reads the live character every tick
	g.character = loaded
	nr.player = _still_stub()
	var healed := 0
	for _i in int(round(3.9 * 60.0)):
		healed += nr.step(TICK)
	assert_eq(healed, 0, "after the load, 3.9 s more: 9.9 s")
	for _i in 6:
		healed += nr.step(TICK)
	assert_eq(healed, 10, "4 s after the load the saved 6 s complete the tick")
	assert_eq(loaded.hp, 30, "healed the loaded character")
	g.character = CharacterState.new()
	g.character.hp = 20
	assert_eq(float(g.character.natural_recovery["hp_rest_s"]), 0.0, "a new character starts at 0")
	for _i in int(round(9.9 * 60.0)):
		healed += nr.step(TICK)
	assert_eq(g.character.hp, 20, "a replaced character does not inherit the old clock")
	g.free()
	nr.player.free()
	nr.free()


func test_chair_bonus_runs_on_its_own_clock_while_seated() -> void:
	var bonus := Chairs.bonus(RELAXER, db())
	assert_eq(bonus, {"hp": int(db().item(RELAXER)["setup"]["hp_recovery_bonus"]),
		"interval_s": float(db().item(RELAXER)["setup"]["interval_s"])}, "the canonical setup data")
	var hp_bonus := int(bonus["hp"])
	var every := float(bonus["interval_s"])
	var r := _rule()
	assert_eq(_run(r, 10.0, &"seated", 20, 500, hp_bonus, every), 10 + hp_bonus, "10 s on The Green Relaxer: 10 + 30")
	# A natural clock already at 4 s: the natural tick comes 6 s after sitting, the chair's 10 s after sitting.
	r = _rule()
	_run(r, 4.0, &"still", 20, 500)
	assert_eq(_run(r, 6.0, &"seated", 20, 500, hp_bonus, every), 10, "natural tick at 6 s seated")
	assert_eq(_run(r, 4.0, &"seated", 30, 500, hp_bonus, every), hp_bonus, "chair tick at 10 s seated")
	# Standing up starts the chair's clock again (recovery.json chair_bonus.stand_resets_clock).
	r = _rule()
	_run(r, 6.0, &"seated", 20, 500, hp_bonus, every)
	_run(r, 0.5, &"still", 20, 500)
	assert_eq(r.chair_rest_s, 0.0, "standing resets the chair clock")
	assert_eq(_run(r, 6.0, &"seated", 20, 500, hp_bonus, every), 10, "6 s seated again: only the natural tick (12.5 s)")
	# Never above Max HP; and the chair clock holds at full HP.
	r = _rule()
	assert_eq(_run(r, 10.0, &"seated", 30, 50, hp_bonus, every), 20, "40 HP clamped to the 20 missing")
	_run(r, 3.0, &"seated", 50, 50, hp_bonus, every)
	assert_near(r.chair_rest_s, 0.0, 1e-4, "full HP holds the chair clock too (3 s seated at full HP did not count)")


func test_missing_config_is_a_data_error_not_a_default() -> void:
	assert_true(NaturalRecoveryRule.from_config({"natural_hp": {"hp_per_tick": 10, "tick_s": 10.0},
		"chair_bonus": {"stand_resets_clock": true, "full_hp_holds_clock": true}}) == null,
		"no invented eligible list")
	assert_true(NaturalRecoveryRule.from_config({"natural_hp": {"hp_per_tick": 10, "tick_s": 10.0,
		"eligible_activities": ["still"]}}) == null, "no chair_bonus section: an error")
	assert_true(NaturalRecoveryRule.from_config({"natural_hp": {"tick_s": 10.0, "eligible_activities": ["still"]},
		"chair_bonus": {"stand_resets_clock": true, "full_hp_holds_clock": true}}) == null, "no invented amount")


# --- the node on a real PlayerController ----------------------------------------------------------------------

func test_node_pauses_for_real_walking_jumping_and_attacking() -> void:
	var g := _fake_game(20)
	var p := _spawn()
	var nr := _attach(p, g)
	var combat := FakeCombat.new()
	combat.name = "PlayerCombat"
	p.add_child(combat)
	_tick(p, nr, 6.0)
	assert_near(_clock(g), 6.0, 0.02, "6 s standing still")
	assert_eq(nr.last_activity, &"still")
	w.bot.world_dir = Vector3.RIGHT
	_tick(p, nr, 5.0)
	assert_eq(nr.last_activity, &"walking")
	assert_near(_clock(g), 6.0, 0.02, "5 s walking: paused")
	w.bot.world_dir = Vector3.ZERO
	w.bot.hold(&"jump")
	_tick(p, nr, 4.0)
	w.bot.release(&"jump")
	assert_near(_clock(g), 6.0, 1e-4, "4 s of hopping: paused (the landing ticks between hops are jumping too)")
	_tick(p, nr, 1.0)
	var before_attack := _clock(g)
	combat.attacking = true
	_tick(p, nr, 5.0)
	assert_eq(nr.last_activity, &"attacking")
	assert_near(_clock(g), before_attack, 1e-6, "5 s attacking (planted): paused")
	combat.attacking = false
	assert_eq(g.character.hp, 20, "no tick so far")
	_tick(p, nr, 10.0 - before_attack + 0.05)
	assert_eq(g.character.hp, 30, "the tick once 10 eligible seconds are reached")
	# Standing in a dialogue (input disabled) with a direction held is still standing still.
	p.set_input_enabled(false)
	w.bot.world_dir = Vector3.RIGHT
	_tick(p, nr, 1.0)
	assert_eq(nr.last_activity, &"still", "a modal window holds the keys: standing still")
	p.set_input_enabled(true)
	# A warp in flight pauses.
	(nr.session as FakeSession).idle = false
	var before_warp := _clock(g)
	w.bot.world_dir = Vector3.ZERO
	_tick(p, nr, 2.0)
	assert_eq(nr.last_activity, &"other")
	assert_near(_clock(g), before_warp, 1e-6, "a warp pauses")
	g.free()


func test_node_heals_a_seated_player_with_the_chair_bonus() -> void:
	var g := _fake_game(20)
	g.character.base_max_hp = 500
	g.character.inventory.add(RELAXER, 1, db())
	var p := _spawn()
	p.chair_owner = g.character
	var nr := _attach(p, g)
	_tick(p, nr, 0.2)
	var res := Chairs.use(g.character, RELAXER, db(), p)
	assert_true(res.ok, str(res))
	assert_true(p.is_seated(), "seated on The Green Relaxer")
	var clock0 := _clock(g)
	var hp0 := g.character.hp
	_tick(p, nr, 10.0 - clock0 + 0.02)
	assert_eq(nr.last_activity, &"seated")
	assert_eq(g.character.hp, hp0 + 10, "the natural tick (the clock already held %.2f s)" % clock0)
	_tick(p, nr, clock0 + 0.02)
	assert_eq(g.character.hp, hp0 + 10 + int(Chairs.bonus(RELAXER, db())["hp"]), "the chair's tick 10 s after sitting")
	g.free()


# --- helpers ----------------------------------------------------------------------------------------------------

func _fake_game(hp: int) -> FakeGame:
	var g := FakeGame.new()
	g.content = db()
	g.character.hp = hp
	return g


func _detached_node(g: FakeGame) -> NaturalRecovery:
	var nr := NaturalRecovery.new()
	nr.game = g
	nr.db = db()
	nr.autostep = false
	nr.rule = NaturalRecoveryRule.from_db(db())
	return nr


## A player that answers activity() with &"still" (for the save/load test without physics).
func _still_stub() -> Node3D:
	return StillPlayer.new()


func _spawn() -> PlayerController:
	w = PlayerTestWorld.create(db())
	w.add_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))
	return w.spawn_player(Vector3.ZERO)


func _attach(p: PlayerController, g: FakeGame) -> NaturalRecovery:
	var nr := _detached_node(g)
	nr.player = p
	var s := FakeSession.new()
	w.host.add_child(s)
	nr.session = s
	p.add_child(nr)
	w.host.add_child(g)
	return nr


## `seconds` of physics: the player steps, then the node (its process priority order in the game).
func _tick(p: PlayerController, nr: NaturalRecovery, seconds: float) -> void:
	for _i in int(round(seconds * 60.0)):
		p.step(TICK)
		nr.step(TICK)


func _clock(g: FakeGame) -> float:
	return float(g.character.natural_recovery["hp_rest_s"])
