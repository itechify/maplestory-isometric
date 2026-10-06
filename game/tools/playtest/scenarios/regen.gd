extends PlaytestScenario
## regen: natural HP recovery and sitting in the real game, with real input (contracts C4 and C5; data/misostory/
## recovery.json natural_hp, the project owner's rule: 10 HP per 10 s of time spent standing still or seated; walking,
## jumping and attacking pause the clock and never reset it; never above Max HP).
## Phase 0: a new game, HP lowered by the console's hp command (setup, counted). 6 s still, 5 s walking and 4 s
## still reach exactly one tick (the brief's example). Holding jump (hopping) and holding attack pause the clock, and
## it resumes to the next tick. Sitting: X with no chair says so; The Green Relaxer (522) is granted with the console
## (setup, counted) and double-clicked in the Set-up tab; 10 s seated give the natural tick plus the chair's own +30; a
## move key stands up; X sits on the first chair owned; a warp stands the player up. Finally time is banked on the
## clock, the player sits down, and Quit Game saves.
## Phase 1: Continue. The player arrives standing (the seat is not saved), the chair is still owned, and the banked
## clock is restored and completes the next tick. Last, on 000000001's ladder near its top at 40% HP (setup: HP by the
## console, the grab by an api step, since no console command grabs a ladder): climbing pauses the clock, and
## PlaytestKit.rest() climbs off before it stands still, so natural recovery heals. tests/unit/test_playtest_regen.gd
## runs it headless.

const CHAIR := "522"
const WARP_MAP := "000000010"

## Player stand-up reasons heard (Events.player_stood_up).
var stood: PackedStringArray = []


func description() -> String:
	return "natural HP recovery: walking, jumping and attacking pause the clock; sitting on The Green Relaxer; the clock survives a reload"


func max_seconds() -> float:
	return 400.0


func run(d: PlaytestDriver) -> void:
	d.events().connect(&"player_stood_up", func(reason: String) -> void: stood.append(reason))
	if d.phase == 0:
		await _play(d)
	else:
		await _after_reload(d)


func _play(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Rester", "male", "541", {"str": 5, "dex": 4})
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	var cfg: Dictionary = (d.db().miso_table("recovery") as Dictionary)["natural_hp"]
	var per_tick := int(cfg["hp_per_tick"])
	var tick_s := float(cfg["tick_s"])
	d.note("rule: %d HP per %.0f s of %s time (verified %s against %s)" % [per_tick, tick_s,
		" or ".join(PackedStringArray(cfg["eligible_activities"])), str(cfg["verified"]), String(cfg["verified_against"])])
	var c := d.character()
	var p := d.player()
	await _set_hp(d, 10)

	# --- The brief's example: 6 s still, 5 s moving, 4 s still reach the 10 s tick (pause, not reset). ------------
	var hp := c.hp
	var t0 := _clock(d)
	await d.wait(6.0)
	d.check("6 s standing still bank 6 s", absf(_clock(d) - t0 - 6.0) < 0.1, "clock %.2f -> %.2f s" % [t0, _clock(d)])
	var banked := _clock(d)
	await d.press(&"move_right", 5.0)
	var walked := _clock(d)
	d.check("5 s walking (real input) pause the clock", absf(walked - banked) < 0.1 and c.hp == hp,
		"clock %.2f -> %.2f s, HP %d -> %d" % [banked, walked, hp, c.hp])
	var left := tick_s - walked
	d.check("the walk kept the banked time (a reset would leave %.0f s)" % tick_s, left < tick_s - 5.0,
		"%.2f s of standing left to the tick" % left)
	await d.wait(left - 0.25)
	d.check("no tick before 10 eligible seconds", c.hp == hp, "HP %d -> %d, clock %.2f s" % [hp, c.hp, _clock(d)])
	await d.wait(0.5)
	d.check("6 s still + 5 s walking + %.1f s still: one tick of %d HP" % [left, per_tick], c.hp == hp + per_tick,
		"HP %d -> %d" % [hp, c.hp])

	# --- Jumping and attacking pause the clock; it resumes to the next tick. --------------------------------------
	await d.wait(2.0)
	hp = c.hp
	banked = _clock(d)
	await d.press(&"jump", 5.0)
	await d.wait_until(func() -> bool: return p.is_grounded(), 2.0)
	var jumped := _clock(d)
	# The landing ticks between the hops of a held jump count as jumping; the last landing may add a tick or two.
	d.check("5 s of jumping (Space held, hopping) pause the clock", absf(jumped - banked) < 0.1 and c.hp == hp,
		"clock %.2f -> %.2f s over the hops, HP %d -> %d" % [banked, jumped, hp, c.hp])
	var combat := p.get_node_or_null(^"PlayerCombat")
	var attacks0 := int(combat.get("attacks")) if combat != null else 0
	banked = _clock(d)
	await d.press(&"attack", 5.0)
	await d.wait_until(func() -> bool: return combat == null or not bool(combat.call("is_attacking")), 2.0)
	var attacked := _clock(d)
	var swings := (int(combat.get("attacks")) if combat != null else 0) - attacks0
	d.check("5 s of attacking (J held, planted) pause the clock", swings > 3 and absf(attacked - banked) < 0.1 and c.hp == hp,
		"%d swings, clock %.2f -> %.2f s, HP %d -> %d" % [swings, banked, attacked, hp, c.hp])
	left = tick_s - _clock(d)
	await d.wait(left - 0.25)
	d.check("still no tick %.1f s later" % (left - 0.25), c.hp == hp, "HP %d, clock %.2f s" % [c.hp, _clock(d)])
	await d.wait(0.5)
	d.check("the clock resumes: the next tick after %.1f s more standing" % left, c.hp == hp + per_tick,
		"HP %d -> %d" % [hp, c.hp])

	# --- Sitting. ----------------------------------------------------------------------------------------------------
	await d.tap(&"sit")
	await d.frames(2)
	var no_chair := ItemCodes.message({"code": ItemCodes.NO_CHAIR})
	d.check("X without a chair: '%s'" % no_chair, not p.is_seated() and no_chair in d.notices, "notices: %s" % str(d.notices))
	await d.console("give %s" % CHAIR)
	var where := c.inventory.find(CHAIR)
	d.check("The Green Relaxer is in the Set-up tab", c.inventory.count(CHAIR) == 1
		and String(where.get("tab", "")) == "setup", str(where))
	var opened := await d.open_window("inventory")
	var tab: Dictionary = await d.click("Set-up")
	var inv: MisoInventoryWindow = d.windows().call("window_by_name", "inventory") if d.windows() != null else null
	var idx := inv.visible_item_ids().find(CHAIR) if inv != null else -1
	d.check("the Set-up tab shows the chair", opened and bool(tab["ok"]) and idx >= 0, "slot %d" % idx)
	if idx < 0:
		return
	await _double_click(d, inv.slots[idx])
	d.check("double-click in the Set-up tab sits on The Green Relaxer", p.is_seated() and p.seated_chair_id() == CHAIR,
		"seated %s on '%s', action button '%s'" % [p.is_seated(), p.seated_chair_id(), inv.action_button.text])
	await d.close_window("inventory")
	var max_hp := StatCalculator.max_hp(c, d.db())
	var bonus := Chairs.bonus(CHAIR, d.db())
	await _set_hp(d, maxi(1, max_hp - per_tick - int(bonus["hp"]) - 5))
	hp = c.hp
	var nr := p.get_node_or_null(^"NaturalRecovery") as NaturalRecovery
	var chair_left := float(bonus["interval_s"]) - (nr.rule.chair_rest_s if nr != null else 0.0)
	await d.wait(chair_left - 0.25)
	d.check("seated: activity 'seated'", p.activity() == &"seated", String(p.activity()))
	d.check("no chair bonus before its %.0f s" % float(bonus["interval_s"]), c.hp - hp < int(bonus["hp"]),
		"HP %d -> %d" % [hp, c.hp])
	await d.wait(0.5)
	d.check("10 s seated on The Green Relaxer: the natural %d + the chair's %d HP" % [per_tick, int(bonus["hp"])],
		c.hp == hp + per_tick + int(bonus["hp"]), "HP %d -> %d (max %d)" % [hp, c.hp, max_hp])
	await d.tap(&"move_left")
	await d.frames(2)
	d.check("a move key stands up", not p.is_seated() and stood.has("move"), "stood: %s" % str(stood))
	await d.wait(0.5)
	await d.tap(&"sit")
	await d.frames(2)
	d.check("X sits on the first chair owned", p.is_seated() and p.seated_chair_id() == CHAIR, "seated %s" % p.is_seated())
	await d.console("warp %s" % WARP_MAP)
	d.check("a warp stands the player up first (map-transition safety)", d.current_map() == WARP_MAP
		and not p.is_seated() and stood.has("warp"), "map %s, seated %s, stood: %s" % [d.current_map(), p.is_seated(),
		str(stood)])

	# --- Bank time on the clock, sit down, Quit Game (the shell saves). -------------------------------------------
	await _set_hp(d, 10)
	if _clock(d) > tick_s - 5.0:
		await d.wait(tick_s - _clock(d) + 0.5)  # past the next tick first, so none fires while quitting
	await d.wait(3.0)
	await d.tap(&"sit")
	await d.frames(2)
	d.check("seated before quitting", p.is_seated(), "seated %s" % p.is_seated())
	d.carry["clock"] = _clock(d)
	d.carry["hp"] = c.hp
	d.note("before Quit Game: clock %.2f s, HP %d, seated on %s" % [_clock(d), c.hp, p.seated_chair_id()])
	await d.reload_process()


func _after_reload(d: PlaytestDriver) -> void:
	var cg: Dictionary = await d.continue_game()
	if not d.check("Continue", bool(cg["ok"]), str(cg)):
		return
	await d.wait_idle()
	var c := d.character()
	var p := d.player()
	var cfg: Dictionary = (d.db().miso_table("recovery") as Dictionary)["natural_hp"]
	var per_tick := int(cfg["hp_per_tick"])
	var tick_s := float(cfg["tick_s"])
	d.check("the player arrives standing: the seated state is not saved", not p.is_seated(), "seated %s" % p.is_seated())
	d.check("The Green Relaxer is still owned (Set-up tab)", c.inventory.count(CHAIR) == 1, str(c.inventory.find(CHAIR)))
	var carried := float(d.carry.get("clock", -1.0))
	var restored := _clock(d)
	d.check("the banked regen clock survives Quit Game and Continue", carried > 1.0 and absf(restored - carried) < 0.6,
		"%.2f s before quitting, %.2f s after Continue" % [carried, restored])
	d.check("HP survives", c.hp == int(d.carry.get("hp", -1)), "HP %d (saved %d)" % [c.hp, int(d.carry.get("hp", -1))])
	var hp := c.hp
	var left := tick_s - _clock(d)
	await d.wait(left - 0.25)
	d.check("no tick before the banked clock reaches %.0f s" % tick_s, c.hp == hp, "HP %d, clock %.2f s" % [c.hp, _clock(d)])
	await d.wait(0.5)
	d.check("%.1f s of standing after the reload complete the saved clock's tick" % left, c.hp == hp + per_tick,
		"HP %d -> %d" % [hp, c.hp])
	await d.tap(&"sit")
	await d.frames(2)
	d.check("the chair still works after the reload (X)", p.is_seated() and p.seated_chair_id() == CHAIR,
		"seated %s" % p.is_seated())
	await _ladder(d)


## On a ladder: climbing is not resting time (contract C4: only still and seated count), and PlaytestKit.rest() gets
## off the ladder before it stands still. Test C's hunter once grabbed a ladder chasing a Shroom on A Split Road and
## "rested" on it through 15 rests, 2,250 s of game time, without one tick (the final evidence run of 2026-10-06).
func _ladder(d: PlaytestDriver) -> void:
	await d.console("warp 000000001")
	await d.wait_idle()
	var p := d.player()
	var c := d.character()
	# The nearest ladder with ground at its foot (PlayerController.climbables lists every map's ladders and ropes).
	var ladder: ClimbableDef = null
	for x: ClimbableDef in p.climbables:
		if x.has_foot_ground and not x.descend_only and x.height() > 2.0 and (ladder == null
				or x.line_distance_xz(p.global_position) < ladder.line_distance_xz(p.global_position)):
			ladder = x
	if not d.check("a ladder with ground at its foot in 000000001", ladder != null and ladder.line_distance_xz(p.global_position) < 60.0,
			"%s" % (ladder.name if ladder != null else "none of %d climbables" % p.climbables.size())):
		return
	var max_hp := StatCalculator.max_hp(c, d.db())
	await _set_hp(d, int(max_hp * 0.4))
	var i := d._begin(PlaytestReport.KIND_API, "PlayerController.grab_climbable", "setup: on %s near its top" % ladder.name)
	var grabbed := p.grab_climbable(ladder, true)
	d._end(i, grabbed and p.is_climbing(), "climbing %s" % p.is_climbing())
	var hp := c.hp
	var clock := _clock(d)
	await d.wait(3.0)
	d.check("climbing pauses natural recovery: 3 s on the ladder leave the clock and HP as they were (contract C4)",
		p.is_climbing() and absf(_clock(d) - clock) < 0.05 and c.hp == hp,
		"climbing %s, clock %.2f -> %.2f s, HP %d -> %d" % [p.is_climbing(), clock, _clock(d), hp, c.hp])
	var kit := PlaytestKit.new(d)
	var rested: float = await kit.rest(PlaytestKit.HP_RESUME, {"rest_max_s": 45.0})
	d.check("PlaytestKit.rest() from the ladder: off it first, then natural recovery heals",
		grabbed and not p.is_climbing() and c.hp >= hp + 10,
		"rested %.1f s, HP %d -> %d / %d, climbing %s" % [rested, hp, c.hp, max_hp, p.is_climbing()])


## The live character's natural recovery clock (CharacterState.natural_recovery.hp_rest_s, contract C3).
func _clock(d: PlaytestDriver) -> float:
	return float(d.character().natural_recovery.get("hp_rest_s", 0.0))


## Setup: sets HP with the console's hp command (a counted console step, #39). Await it.
func _set_hp(d: PlaytestDriver, hp: int) -> void:
	await d.console("hp %d" % hp)


## A real mouse double-click on a control (MisoItemSlot activates on a press with double_click set): move, press,
## release, then the second press flagged double_click, release. Logged as a play step. A slot a player cannot click
## (off the screen or covered: PlaytestDriver.pointer_onto) is not pressed, and a failed check says why.
func _double_click(d: PlaytestDriver, target: Control) -> void:
	var i := d._begin(PlaytestReport.KIND_PLAY, "double_click", str(target.get_path()))
	var at := target.get_global_transform_with_canvas() * (target.size * 0.5)
	var why := await d.pointer_onto(target, at)
	if why != "":
		d._end(i, false, why)
		d.check("a player can double-click %s" % String(target.name), false, why)
		return
	d.input.mouse_button(at, true)
	await d.frames(1)
	d.input.mouse_button(at, false)
	await d.frames(1)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = true
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = d.input.to_window(at)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await d.frames(1)
	d.input.mouse_button(at, false)
	await d.frames(1)
	d._end(i, true)
