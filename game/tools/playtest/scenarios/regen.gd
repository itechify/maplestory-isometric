extends PlaytestScenario
## regen: natural HP recovery in the real game (NaturalRecovery; combat.json natural_recovery, an adaptation over
## MeowDB's qualitative "standing still will slowly restore your HP"). New game -> HP lowered by an api setup step
## (the console has no HP setter) -> walk for 12 s with real input: no recovery while moving -> stand still: the first
## tick after the configured rest, one tick per interval after that, never above max HP. tests/unit/test_playtest_regen.gd
## runs it headless.


func description() -> String:
	return "natural HP recovery: none while walking, one tick per rest interval while standing still"


func max_seconds() -> float:
	return 180.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Rester", "male", "541", {"str": 5, "dex": 4})
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	var cfg: Dictionary = (Data.db.miso_table("combat") as Dictionary)["natural_recovery"]
	var per_tick := int(cfg["hp_per_tick"])
	var tick_s := float(cfg["tick_s"])
	var delay_s := float(cfg["delay_s"])
	var c := d.character()
	var max_hp := StatCalculator.max_hp(c, Data.db)
	var i := d._begin(PlaytestReport.KIND_API, "Game.change_hp", "setup: HP %d -> 10 (no console HP setter)" % c.hp)
	d.game().change_hp(10 - c.hp)
	d._end(i, true, "HP %d / %d" % [c.hp, max_hp])
	await d.wait(0.5)

	# Walking never rests: hold a direction (real input) for longer than one full rest.
	var hp0 := c.hp
	await d.press(&"move_right", 6.0)
	await d.press(&"move_left", 6.0)
	d.check("no recovery while walking", c.hp == hp0, "HP %d -> %d over 12 s of walking" % [hp0, c.hp])

	# Standing still: nothing before the rest interval, then one tick.
	var hp1 := c.hp
	await d.wait(tick_s - 1.0)
	d.check("no recovery before %.0f s of rest" % tick_s, c.hp == hp1, "HP %d -> %d" % [hp1, c.hp])
	await d.wait(2.0)
	d.check("one tick of %d HP after %.0f s standing still" % [per_tick, tick_s], c.hp == mini(hp1 + per_tick, max_hp),
		"HP %d -> %d (max %d)" % [hp1, c.hp, max_hp])
	await d.wait(tick_s)
	d.check("a second tick %.0f s later" % tick_s, c.hp == mini(hp1 + 2 * per_tick, max_hp), "HP %d" % c.hp)

	# Never above max HP.
	await d.wait(ceilf(float(max_hp) / maxf(1.0, per_tick)) * tick_s + 1.0)
	d.check("recovery stops at max HP", c.hp == max_hp, "HP %d / %d" % [c.hp, max_hp])
	d.note("config: %d HP every %.0f s after %.0f s out of combat (verified %s)" % [per_tick, tick_s, delay_s,
		str(cfg.get("verified"))])
