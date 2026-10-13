extends PlaytestScenario
## test_effects: the art pack's effect meshes at gameplay scale (#71), for screenshots (run it --windowed; headless,
## the checks still run and the captures are skipped). In Snail Hunting Ground I a level-10 Beginner (setup: the
## console's "level" and "give", and the three skill levels written straight onto the character, so the run needs
## no Skills window) casts Recovery and Nimble Feet (both shown at the feet while they run), jumps (dust at the take-off
## and the landing), throws Three Snails at a Snail (the shell in flight and the hit spark) and throws one at nothing
## (a whiff). Each step checks that the effect it captures is on screen: the pack's mesh with the pack installed,
## the procedural shell and spark without it. Not a strict scenario.

const FIELD := "000000040"
const SNAIL := "2"
const SNAILS := "0001000"
const RECOVERY := "0001001"
const NIMBLE := "0001002"
## Where to stand from the Snail for a throw: inside the canonical 50-300 px band (px, actor scale).
const THROW_FROM_PX := 150.0


func description() -> String:
	return "Effect meshes (#71): Three Snails' shell and the hit spark, a whiff, Recovery and Nimble Feet, jump dust; windowed for captures"


func max_seconds() -> float:
	return 300.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Sparkle", "female", "541", {})
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	var pack := EffectMeshes.shared().has(EffectMeshes.HIT_SPARK)
	d.note("art pack effect meshes: %s" % ("installed" if pack else "absent (procedural shell and spark only)"))
	await d.console("level 10")
	for shell in ["348", "349", "351"]:
		await d.console("give %s 10" % shell)
	var c := d.character()
	c.skills = {SNAILS: 3, RECOVERY: 3, NIMBLE: 3}
	await d.console("mp max")
	await d.console("warp " + FIELD)
	if not d.check("in Snail Hunting Ground I", d.current_map() == FIELD, d.current_map()):
		return
	await d.wait(1.5)
	await d.press(&"move_right", 1.0)
	await _auras(d, pack)
	await _dust(d, pack)
	await _three_snails(d, pack)


func _three_snails(d: PlaytestDriver, pack: bool) -> void:
	var p := d.player()
	var skills: PlayerSkills = p.get_node(^"PlayerSkills")
	var target := d.nearest_monster({"mob_id": SNAIL, "max_dist_m": 40.0})
	if not d.check("a Snail to throw at", target != null):
		return
	var ideal := WorldScale.actor(THROW_FROM_PX)
	await d.walk_to(d.walker.grounded(target.global_position), {"max_s": 8.0, "within_m": ideal,
		"stop_when": func() -> bool: return not is_instance_valid(target) or _flat(target.global_position - p.global_position) <= ideal})
	var hit := false
	for attempt in 12:
		if not is_instance_valid(target) or not bool(target.call("is_alive")):
			target = d.nearest_monster({"mob_id": SNAIL, "max_dist_m": 40.0})
			if target == null:
				break
		await _face(d, target.global_position)
		await d.wait(0.3)
		var res := skills.cast(SNAILS)
		if bool(res.get("ok", false)) and res.get("target") != null:
			hit = true
			await d.screenshot("three_snails_shell_and_hit_spark")
			d.check("the thrown shell is %s" % ("the pack's ThreeSnails" if pack else "the procedural sphere"),
				_holds(skills.last_shell, EffectMeshes.THREE_SNAILS) == pack, str(skills.last_shell))
			break
		d.note("cast %d: %s" % [attempt, str(res)])
		await d.wait(1.0)
	d.check("Three Snails hit a Snail", hit)
	await d.wait(1.0)
	# A whiff: thrown away from every monster, straight ahead to its reach or the first wall.
	var away := p.global_position - (target.global_position if is_instance_valid(target) else p.global_position + p.facing)
	await _face(d, p.global_position + Vector3(away.x, 0.0, away.z).normalized())
	await d.wait(0.3)
	var whiff := skills.cast(SNAILS)
	if bool(whiff.get("ok", false)) and whiff.get("target") == null:
		await d.screenshot("three_snails_whiff")
	d.note("whiff: %s, shell to %s (stopped by a wall: %s)" % [str(whiff.get("ok")), skills.last_shell_to, skills.last_shell_stopped])
	await d.wait(1.0)


func _auras(d: PlaytestDriver, pack: bool) -> void:
	var p := d.player()
	var skills: PlayerSkills = p.get_node(^"PlayerSkills")
	var fx: PlayerFx = p.get_node(^"PlayerFx")
	d.check("Recovery cast", bool(skills.cast(RECOVERY).ok))
	await d.wait(0.6)
	d.check("Recovery shows %s" % ("its mesh" if pack else "nothing (no pack)"),
		(fx.aura(PlayerSkills.effect_id(RECOVERY)) != null) == pack, str(fx.aura_ids()))
	await d.screenshot("recovery")
	await d.wait(0.6)
	d.check("Nimble Feet cast", bool(skills.cast(NIMBLE).ok))
	await d.wait(0.6)
	d.check("Nimble Feet shows %s" % ("its mesh" if pack else "nothing (no pack)"),
		(fx.aura(PlayerSkills.effect_id(NIMBLE)) != null) == pack, str(fx.aura_ids()))
	await d.screenshot("recovery_and_nimble_feet")
	await d.press(&"move_right", 1.0)
	await d.screenshot("recovery_and_nimble_feet_walking")


func _dust(d: PlaytestDriver, pack: bool) -> void:
	var p := d.player()
	var fx: PlayerFx = p.get_node(^"PlayerFx")
	await d.wait(0.6)
	var landed := [false]
	var on_land := func(_s: float) -> void: landed[0] = true
	p.landed.connect(on_land)
	await d.tap(&"jump")
	d.check("dust at the take-off" + ("" if pack else " (none without the pack)"), (fx.dust_count() > 0) == pack,
		"%d puffs" % fx.dust_count())
	await d.screenshot("jump_dust_takeoff")
	var t0 := d.game_s()
	while not landed[0] and d.game_s() - t0 < 3.0:
		await d.get_tree().physics_frame
	p.landed.disconnect(on_land)
	d.check("landed", landed[0])
	await d.screenshot("jump_dust_landing")


## Turns the player toward `at` with a short nudge of real input.
func _face(d: PlaytestDriver, at: Vector3) -> void:
	var p := d.player()
	var to := at - p.global_position
	to.y = 0.0
	if to.length_squared() < 1e-4:
		return
	var dir := to.normalized()
	for i in 6:
		if p.facing.dot(dir) >= cos(deg_to_rad(10.0)):
			break
		d.input.set_move_world(dir * 0.2, p.view_right, p.view_forward)
		await d.get_tree().physics_frame
		await d.get_tree().process_frame
		d.input.release_movement()
	d.input.release_movement()


static func _holds(n: Node, effect: String) -> bool:
	return n != null and is_instance_valid(n) and n.find_child(effect, true, false) != null


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
