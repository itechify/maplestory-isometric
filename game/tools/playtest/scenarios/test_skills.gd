extends PlaytestScenario
## test_skills: the Beginner skills in the real game. A new game hunts Snails in Snail Hunting Ground I with the
## attack key to level 2 (the first canonical SP, shown on the HUD's Skill button), then a console "exp" grant (setup)
## brings the character to level 4. The SP is spent with the "+" buttons of the Skills window (K) by mouse, and the
## three skills are put on keys 1-3 with the window's Set key picker. Key 1 (Three Snails) kills a full-HP Snail with
## thrown shells only (MP and one Snail Shell per cast, the canonical fixed damage per hit); in Mushroom Town key 2
## (Recovery) heals exactly its canonical total over 30 s while the player walks (walking pauses natural recovery) and
## starts its 2 min cooldown, and key 3 (Nimble Feet) raises the walk speed by the canonical Speed bonus. Quit Game and
## Continue: the skill levels, the quickslot bindings and the running cooldowns come back, and the restored cooldown
## still refuses key 2; once it runs out key 2 casts Recovery again, and a death (an api setup step) ends that heal while
## the cooldowns keep counting. Every number is read from canonical data (SkillDef), never written here.

const FIELD := "000000040"
const TOWN := "000000010"
const SNAIL := "2"
const SNAILS := "0001000"
const RECOVERY := "0001001"
const NIMBLE := "0001002"
## The keys the scenario binds (quickslot_1..3).
const KEYS := {SNAILS: "1", RECOVERY: "2", NIMBLE: "3"}
## Where to stand from the Snail for a throw: well inside the canonical 50-300 px band (px, actor scale).
const THROW_FROM_PX := 150.0


func description() -> String:
	return "Beginner skills: SP from a level-up, '+' in the Skills window, keys 1-3, a Three Snails kill, Recovery's heal, Nimble Feet's speed, save/reload, a death ends the effects"


func max_seconds() -> float:
	return 900.0


func run(d: PlaytestDriver) -> void:
	if d.phase == 0:
		await _phase_play(d)
	else:
		await _phase_reload(d)


func _phase_play(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Skiller", "female", "541", {})
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	var c := d.character()
	var db := d.db()
	d.check("a new Beginner has 0 SP", c.sp == 0, "SP %d" % c.sp)

	# --- the first SP, earned: Snails to level 2 ---------------------------------------------------------------
	await d.console("warp " + FIELD)
	if not d.check("in Snail Hunting Ground I", d.current_map() == FIELD, d.current_map()):
		return
	await d.wait(1.0)
	var f: Dictionary = await d.fight_until(func() -> bool: return d.character().level >= 2, 300.0, {"mob_id": SNAIL})
	var per_level := int(db.formula("beginner")["sp"]["sp_per_level"])
	d.check("level 2 by hunting Snails", c.level >= 2, "%d kills, level %d" % [int(f["kills"]), c.level])
	d.check("the level-up granted the canonical SP", c.sp == per_level * (c.level - 1), "SP %d at level %d" % [c.sp, c.level])
	var hud: Node = d.hud()
	var skill_button: Button = hud.get("status").get("menu_buttons")["skills"]
	d.check("the HUD's Skill button shows the SP", ("+%d" % c.sp) in skill_button.text, skill_button.text)
	await d.pickup_all_nearby(8.0, 40.0)

	# --- setup: level 4 (3 SP) -------------------------------------------------------------------------------
	var need := 0
	for lv in range(c.level, 4):
		need += Progression.exp_to_next(lv, db)
	await d.console("exp %d" % (need - c.exp))
	d.check("level 4 with 3 SP (setup)", c.level == 4 and c.sp == 3, "level %d, SP %d" % [c.level, c.sp])

	# --- spend SP through the window, bind keys 1-3 --------------------------------------------------------------
	if not d.check("K opens the Skills window", await d.open_window("skills")):
		return
	var w: Node = d.windows().call("window_by_name", "skills")
	for sid: String in [NIMBLE, SNAILS, RECOVERY]:
		var r: Dictionary = await d.click(w.get("plus_buttons")[sid])
		d.check("'+' on %s" % _name(d, sid), bool(r["ok"]) and SkillBook.level_of(c, sid) == 1, "Lv %d" % SkillBook.level_of(c, sid))
	d.check("3 SP spent, 0 left", c.sp == 0, "SP %d" % c.sp)
	var text := d.window_text("skills")
	d.check("the window shows the new levels", text.count("Lv. 1 / 3") == 3, text.replace("\n", " | "))
	for sid: String in [SNAILS, RECOVERY, NIMBLE]:
		await d.click(w.get("rows")[sid]["panel"])
		await d.click(w.get("key_button"))
		var kr: Dictionary = await d.click(w.get("key_buttons")[KEYS[sid]])
		d.check("%s set to key %s in the window" % [_name(d, sid), KEYS[sid]], bool(kr["ok"])
			and MisoQuickslots.skill_for(c, KEYS[sid]) == sid, str(c.quickslots.get(KEYS[sid])))
	await d.close_window("skills")
	var bar: Node = hud.get("status").get("quickslots")
	d.check("the HUD shows the three skills on keys 1-3", bar.call("skill_on", "1") == SNAILS
		and bar.call("skill_on", "2") == RECOVERY and bar.call("skill_on", "3") == NIMBLE, "")

	# --- Three Snails kills a Snail -------------------------------------------------------------------------------
	var def3 := SkillDef.of(SNAILS, db)
	var shell := String(def3.item_cost(1)["item_id"])
	if c.inventory.count(shell) < 8:
		d.note("%d %s picked up from the hunt; topping up for the throws" % [c.inventory.count(shell), _item(d, shell)])
		await d.console("give %s %d" % [shell, 8 - c.inventory.count(shell)])
	await _kill_with_three_snails(d, def3)

	# --- Recovery and Nimble Feet in town --------------------------------------------------------------------------
	await d.console("warp " + TOWN)
	d.check("in Mushroom Town", d.current_map() == TOWN, d.current_map())
	await d.wait(1.0)
	await _recovery(d)
	await _nimble_feet(d)

	# --- reload --------------------------------------------------------------------------------------------------
	d.carry["skills"] = c.skills.duplicate()
	d.carry["quickslots"] = c.quickslots.duplicate(true)
	d.carry["cooldowns"] = c.cooldowns.duplicate()
	d.carry["sp"] = c.sp
	d.carry["game_s"] = d.game_s()
	d.note("before Quit Game: cooldowns %s" % str(c.cooldowns))
	await d.reload_process()


func _kill_with_three_snails(d: PlaytestDriver, def: SkillDef) -> void:
	var c := d.character()
	var p := d.player()
	var skills: PlayerSkills = p.get_node(^"PlayerSkills")
	var target: Node3D = null
	for attempt in 6:
		var m := d.nearest_monster({"mob_id": SNAIL, "max_dist_m": 40.0})
		if m != null and int(m.get("hp")) == int(m.get("def").get("max_hp")):
			target = m
			break
		await d.wait(2.0)
	if not d.check("a full-HP Snail to throw at", target != null):
		return
	var died := [false]
	var on_died := func(m: Node) -> void:
		if m == target:
			died[0] = true
	d.monsters().connect(&"monster_died", on_died)
	var hits := [0]
	var damage: Array = []
	var on_cast := func(sid: String, t: Node, res: DamageResult) -> void:
		if sid == SNAILS and t == target and res != null and not res.missed:
			hits[0] += 1
			damage.append(res.final)
	skills.cast_resolved.connect(on_cast)
	var casts0 := skills.casts
	var mp0 := c.mp
	var shells0 := c.inventory.count(String(def.item_cost(1)["item_id"]))
	var ideal := WorldScale.actor(THROW_FROM_PX)
	var t0 := d.game_s()
	while not died[0] and d.game_s() - t0 < 120.0:
		await d.get_tree().process_frame
		d.input.reassert()
		if not is_instance_valid(target) or not bool(target.call("is_alive")) or p.is_dead():
			break
		var to := target.global_position - p.global_position
		var dy := to.y
		to.y = 0.0
		var dist := to.length()
		if dist > 6.0 or absf(dy) > 1.0:
			d.input.release_movement()
			var tgt := target
			await d.walk_to(d.walker.grounded(target.global_position), {"max_s": 6.0, "within_m": ideal,
				"stop_when": func() -> bool: return not is_instance_valid(tgt) or _flat(tgt.global_position - p.global_position) <= ideal})
			continue
		var dir := to.normalized() if dist > 0.01 else p.facing
		if dist > ideal + 1.0:
			d.input.set_move_world(dir, p.view_right, p.view_forward)
			continue
		if dist < ideal - 1.5:
			d.input.set_move_world(-dir, p.view_right, p.view_forward)
			continue
		d.input.release_movement()
		if p.facing.dot(dir) < cos(deg_to_rad(12.0)):
			d.input.set_move_world(dir * 0.2, p.view_right, p.view_forward)
			await d.get_tree().physics_frame
			await d.get_tree().process_frame
			d.input.release_movement()
			continue
		if not p.is_grounded() or d.combat().call("is_attacking"):
			continue
		await d.tap(&"quickslot_1")
		await d.wait(0.1)
	d.input.release_movement()
	d.monsters().disconnect(&"monster_died", on_died)
	skills.cast_resolved.disconnect(on_cast)
	var casts := skills.casts - casts0
	d.check("key 1 (Three Snails) killed a Snail", died[0], "%d casts, %d hits in %.1f s" % [casts, hits[0], d.game_s() - t0])
	var fixed := int(def.fixed_damage(1))
	var exact := true
	for v in damage:
		exact = exact and int(v) == fixed
	d.check("every hit dealt the canonical fixed damage", hits[0] > 0 and exact, "hits %s, Lv1 damage %d" % [str(damage), fixed])
	d.check("each cast spent the level's MP and one shell", c.inventory.count(String(def.item_cost(1)["item_id"])) == shells0 - casts
		and c.mp == mp0 - casts * def.mp_cost(1), "%d casts: shells %d -> %d, MP %d -> %d" % [casts, shells0,
		c.inventory.count(String(def.item_cost(1)["item_id"])), mp0, c.mp])
	await d.screenshot("three_snails_kill")


func _recovery(d: PlaytestDriver) -> void:
	var c := d.character()
	var db := d.db()
	var def := SkillDef.of(RECOVERY, db)
	var ticker: EffectTicker = d.player().get_node(^"EffectTicker")
	var i := d._begin(PlaytestReport.KIND_API, "Game.change_hp", "setup: HP %d -> 20 (no console HP setter)" % c.hp)
	d.game().change_hp(20 - c.hp)
	d._end(i, true, "HP %d / %d" % [c.hp, StatCalculator.max_hp(c, db)])
	var mp0 := c.mp
	var hp0 := c.hp
	var healed0 := ticker.healed
	await d.tap(&"quickslot_2")
	d.check("key 2 cast Recovery", EffectBook.has(c, PlayerSkills.effect_id(RECOVERY)), str(c.effects))
	d.check("Recovery cost its MP", c.mp == mp0 - def.mp_cost(1), "MP %d -> %d" % [mp0, c.mp])
	d.check("Recovery's cooldown started", absf(EffectBook.cooldown_left(c, RECOVERY) - def.cooldown_s(1)) < 1.0,
		"%.1f s" % EffectBook.cooldown_left(c, RECOVERY))
	# Walk back and forth for the whole effect: walking pauses natural recovery, Recovery heals anyway.
	for leg in 8:
		await d.press(&"move_right" if leg % 2 == 0 else &"move_left", 4.0)
	var by_skill := ticker.healed - healed0
	d.check("Recovery healed exactly its canonical total over %d s" % int(def.duration_s(1)), by_skill == def.hp_total(1),
		"%d HP by the skill (%d expected), HP %d -> %d" % [by_skill, def.hp_total(1), hp0, c.hp])
	d.check("the HP gauge followed", c.hp >= hp0 + def.hp_total(1), "HP %d -> %d" % [hp0, c.hp])
	d.check("the effect ended", not EffectBook.has(c, PlayerSkills.effect_id(RECOVERY)), str(c.effects))
	await d.tap(&"quickslot_2")
	d.check("a second Recovery is refused while cooling down", _noticed(d, "not ready"), str(d.notices.slice(-3)))


func _nimble_feet(d: PlaytestDriver) -> void:
	var c := d.character()
	var db := d.db()
	var def := SkillDef.of(NIMBLE, db)
	var p := d.player()
	var base_speed := p.model.walk_speed
	var base_stat := StatCalculator.speed(c, db)
	var measured0 := await _measure_walk(d)
	await d.tap(&"quickslot_3")
	d.check("key 3 cast Nimble Feet", EffectBook.has(c, PlayerSkills.effect_id(NIMBLE)), str(c.effects))
	d.check("Speed +%d" % def.speed_bonus(1), StatCalculator.speed(c, db) == base_stat + def.speed_bonus(1),
		"Speed %d -> %d" % [base_stat, StatCalculator.speed(c, db)])
	# movement.json: walk px/s = 125 x (Speed + 20) / 100.
	var ratio := float(base_stat + def.speed_bonus(1) + 20) / float(base_stat + 20)
	d.check("the controller walks %.4fx faster" % ratio, absf(p.model.walk_speed / base_speed - ratio) < 0.001,
		"%.3f -> %.3f m/s" % [base_speed, p.model.walk_speed])
	var measured := await _measure_walk(d)
	d.check("measured with real input", measured0 > 0.0 and absf(measured / measured0 - ratio) < 0.03,
		"%.3f -> %.3f m/s (x%.3f)" % [measured0, measured, measured / maxf(0.001, measured0)])
	await d.wait(def.duration_s(1))
	d.check("Nimble Feet ended after %d s" % int(def.duration_s(1)), not EffectBook.has(c, PlayerSkills.effect_id(NIMBLE))
		and absf(p.model.walk_speed - base_speed) < 1e-6, "walk %.3f m/s" % p.model.walk_speed)


## The player's horizontal speed over 1 s of holding a direction (after 0.3 s to get going), m/s.
func _measure_walk(d: PlaytestDriver) -> float:
	var p := d.player()
	var best := 0.0
	for action: StringName in [&"move_right", &"move_left"]:
		d.input.set_action_strength(action, 1.0)
		await d.wait(0.3)
		var a := p.global_position
		await d.wait(1.0)
		var b := p.global_position
		d.input.set_action_strength(action, 0.0)
		await d.wait(0.2)
		best = maxf(best, _flat(b - a))
	return best


func _phase_reload(d: PlaytestDriver) -> void:
	var cg: Dictionary = await d.continue_game()
	if not d.check("Continue after Quit Game", bool(cg["ok"]), str(cg)):
		return
	var c := d.character()
	d.check("skill levels survive the reload", PlaytestDriver.diff(d.carry["skills"], c.skills) == "",
		PlaytestDriver.diff(d.carry["skills"], c.skills))
	d.check("the typed quickslot bindings survive", PlaytestDriver.diff(d.carry["quickslots"], c.quickslots) == "",
		PlaytestDriver.diff(d.carry["quickslots"], c.quickslots))
	d.check("SP survives", c.sp == int(d.carry["sp"]), "SP %d" % c.sp)
	var saved: Dictionary = d.carry["cooldowns"]
	for sid: String in [RECOVERY, NIMBLE]:
		var before := float(saved.get(sid, 0.0))
		var now := EffectBook.cooldown_left(c, sid)
		d.check("%s's cooldown survives as remaining seconds" % _name(d, sid), before > 0.0 and now > 0.0 and now <= before
			and now > before - 30.0, "%.1f s before Quit Game, %.1f s after Continue" % [before, now])
	await d.wait(1.0)
	var later := EffectBook.cooldown_left(c, RECOVERY)
	d.check("the restored cooldown keeps counting down", later < float(saved.get(RECOVERY, 0.0)), "%.1f s" % later)
	var mp0 := c.mp
	await d.tap(&"quickslot_2")
	d.check("key 2 is still refused by the restored cooldown", c.mp == mp0 and not EffectBook.has(c, PlayerSkills.effect_id(RECOVERY)),
		"MP %d -> %d" % [mp0, c.mp])
	if await d.open_window("skills"):
		var text := d.window_text("skills")
		d.check("the Skills window shows the levels after the reload", text.count("Lv. 1 / 3") == 3, text.replace("\n", " | "))
		await d.close_window("skills")
	var bar: Node = d.hud().get("status").get("quickslots")
	d.check("the HUD shows the skills on keys 1-3 after the reload", bar.call("skill_on", "1") == SNAILS
		and bar.call("skill_on", "2") == RECOVERY and bar.call("skill_on", "3") == NIMBLE, "")
	await _death_ends_effects(d)


## After the restored cooldown runs out key 2 casts Recovery again; a death then ends the running effect and keeps the
## cooldowns (misostory/skills.json effects_on_death), through the game's own Events bus and death flow.
func _death_ends_effects(d: PlaytestDriver) -> void:
	var c := d.character()
	var def := SkillDef.of(RECOVERY, d.db())
	var ticker: EffectTicker = d.player().get_node(^"EffectTicker")
	await d.wait(EffectBook.cooldown_left(c, RECOVERY) + 0.5)
	d.check("the restored Recovery cooldown ran out", EffectBook.cooldown_left(c, RECOVERY) == 0.0,
		"%.1f s" % EffectBook.cooldown_left(c, RECOVERY))
	var mp0 := c.mp
	await d.tap(&"quickslot_2")
	d.check("key 2 casts Recovery again once its cooldown is over", EffectBook.has(c, PlayerSkills.effect_id(RECOVERY))
		and c.mp == mp0 - def.mp_cost(1), "MP %d -> %d, %s" % [mp0, c.mp, str(c.effects)])
	var nimble_left := EffectBook.cooldown_left(c, NIMBLE)
	var i := d._begin(PlaytestReport.KIND_API, "Game.damage_player", "setup: a death with Recovery running (no console command kills the player)")
	d.game().damage_player(c.hp)
	d._end(i, true, "HP %d" % c.hp)
	await d.wait(1.0)
	d.check("the player died", bool(d.game().is_character_dead()), "HP %d" % c.hp)
	d.check("the death ended Recovery's heal", not EffectBook.has(c, PlayerSkills.effect_id(RECOVERY)), str(c.effects))
	d.check("the cooldowns kept counting through the death", EffectBook.cooldown_left(c, RECOVERY) > def.cooldown_s(1) - 5.0
		and EffectBook.cooldown_left(c, NIMBLE) > 0.0 and EffectBook.cooldown_left(c, NIMBLE) < nimble_left,
		"Recovery %.1f s, Nimble Feet %.1f s" % [EffectBook.cooldown_left(c, RECOVERY), EffectBook.cooldown_left(c, NIMBLE)])
	var healed0 := ticker.healed
	await d.wait(def.duration_s(1) / 4.0)
	d.check("no Recovery tick heals the dead character", ticker.healed == healed0, "%d HP" % (ticker.healed - healed0))


static func _name(d: PlaytestDriver, sid: String) -> String:
	var def := SkillDef.of(sid, d.db())
	return def.name if def != null else sid


static func _item(d: PlaytestDriver, item_id: String) -> String:
	return String(d.db().item(item_id).get("name", item_id))


static func _noticed(d: PlaytestDriver, part: String) -> bool:
	for t in d.notices:
		if part in t:
			return true
	return false


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
