extends TestCase
## DeathController against a private MapSession (no world: every transition completes synchronously), a private
## GameState and SaveService, on the Events bus MapSession announces deaths on. Brief Test F at the rules level:
## a death in 000000040 and 000001014 takes the loss and saves at the moment of death (the canonical EXP penalty,
## death.json HP/MP, the character at the canonical returnMap's respawn spawn), OK only travels there; and
## death -> quit -> reload applies the penalty exactly once, in the return town, with inventory and quest state
## intact. The same flows through the real main scene, physics and the notice UI are test_death_flow.gd (one
## process) and test_death_quit_reload.gd (a real quit: one process dies and closes, the next one continues).

const SESSION_SCRIPT := "res://scripts/autoload/map_session.gd"
const SLOT := "death1"


## Contract C6: the Test F flows at the rules level.
func parity_keys() -> Dictionary:
	return {
		"test_test_f_deaths_in_40_and_1014": ["mechanic:death-respawn"],
		"test_test_f_death_quit_reload_in_40_and_1014": ["mechanic:death-respawn", "persistence:respawn-information"],
	}

var root := ""
var ms: Node = null
var svc: SaveService = null
var game: GameState = null
var ev: Node = null
var dc: DeathController = null
var t := 0.0


func before_each() -> void:
	root = "user://_tests/death_ctrl_%d_%d" % [Time.get_ticks_usec(), randi()]
	ev = (Engine.get_main_loop() as SceneTree).root.get_node("Events")
	ms = load(SESSION_SCRIPT).new()
	ms.defs = MapDefinitions.build(db())
	ms.content = db()
	var r := RandomNumberGenerator.new()
	r.seed = 7
	ms.rng = r
	ms.autosave_enabled = false
	t = 0.0
	ms.clock_provider = func() -> float: return t
	# The autoload connects this in _ready; the private instance is never added to the tree.
	ev.connect("player_died", ms._on_player_died)
	svc = SaveService.new()
	svc.save_dir = root
	svc.db = db()
	svc.event_bus = ev
	svc.log_failures = false
	svc.map_session_node = ms
	game = GameState.new()
	game.db = db()
	game.save_service = svc
	game.event_bus = ev
	game.log_warnings = false
	svc.game_node = game
	assert_eq(game.new_game({"slot": SLOT}), OK, "new game")
	ms.character = game.character
	assert_eq(ms.start_new_game(), OK, "session started")
	dc = _new_controller()


func after_each() -> void:
	if ev.is_connected("player_died", ms._on_player_died):
		ev.disconnect("player_died", ms._on_player_died)
	dc.detach()
	dc.free()
	game.free()
	svc.free()
	ms.free()
	var d := DirAccess.open(root)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(root.path_join(f))
	DirAccess.remove_absolute(root)


func _new_controller() -> DeathController:
	var d := DeathController.new()
	d.configure(ms, game, ev, db())
	d.attach()
	d.armed = true
	return d


func _spawn_index() -> int:
	return (ms.get_defs() as MapDefinitions).tuning.respawn_spawn_index()


func _town_of(map_id: String) -> String:
	return String(db().map(map_id)["return_map_id"])


func _snapshot(c: CharacterState) -> Dictionary:
	return {"exp": c.exp, "level": c.level, "hp": c.hp, "mp": c.mp, "mesos": c.mesos, "inventory": c.inventory.to_dict(),
		"equipment": c.equipment.to_dict(), "quests": c.quests.to_dict(),
		"loss": Progression.death_exp_loss(c.level, c.get_base_stat("luk"), db())}


## HP/MP death.json gives a character that died with `mp_at_death` MP.
func _want_vitals(c: CharacterState, mp_at_death: int) -> Array:
	var vit := dc.rules.respawn_vitals()
	return [maxi(1, DeathRules.vital_value(vit["hp"], 0, StatCalculator.max_hp(c, db()))),
		DeathRules.vital_value(vit["mp"], mp_at_death, StatCalculator.max_mp(c, db()))]


## Warps to map_id and dies there by HP 0; checks the loss is taken and saved at that moment. Returns the snapshot
## from just before the death.
func _die_in(map_id: String) -> Dictionary:
	assert_eq(ms.debug_warp(map_id), OK, "warp to %s" % map_id)
	var c := game.character
	var before := _snapshot(c)
	assert_true(int(before["loss"]) > 0 and c.exp > 0, "%s: this death costs EXP (%d of %d)" % [map_id, before["loss"], c.exp])
	var applied_before := dc.rules.applied_count
	game.change_hp(-c.hp)
	var town := _town_of(map_id)
	assert_true(dc.is_dead(), "%s: HP 0 is a death" % map_id)
	assert_eq(ms.state_name(), "DEAD", "%s: MapSession DEAD" % map_id)
	assert_eq(dc.died_in, map_id, "%s: died_in" % map_id)
	assert_true(ms.is_death_committed() and dc.is_committed(), "%s: committed at the death" % map_id)
	assert_eq(dc.rules.applied_count, applied_before + 1, "%s: the rules ran once, at the death" % map_id)
	assert_eq(c.exp, maxi(0, int(before["exp"]) - int(before["loss"])), "%s: canonical EXP penalty at the death" % map_id)
	assert_eq([c.hp, c.mp], _want_vitals(c, int(before["mp"])), "%s: death.json HP/MP set at the death" % map_id)
	assert_eq(String(c.location.get("map_id", "")), town, "%s: the location is the return town" % map_id)
	assert_eq(int(dc.last_report.get("exp_lost", -1)), int(before["exp"]) - c.exp, "%s: reported loss" % map_id)
	assert_eq(String(dc.last_report.get("map_id", "")), map_id, "%s: report names the map died in" % map_id)
	assert_eq(int(dc.last_report.get("death_save_error", -1)), OK, "%s: saved at the death" % map_id)
	var r := svc.read_save(SLOT)
	assert_true(r.ok(), "%s: the save written at the death is valid: %s" % [map_id, r.message])
	if r.ok():
		assert_eq([r.character.exp, r.character.hp, r.character.mp], [c.exp, c.hp, c.mp], "%s: the save holds the loss" % map_id)
		assert_eq(String(r.character.location.get("map_id", "")), town, "%s: saved in the return town" % map_id)
		assert_eq(r.character.location.get("entry", {}), {"map_id": town, "spawn_index": _spawn_index()},
			"%s: saved at the respawn spawn" % map_id)
		assert_false((r.character.location as Dictionary).has("resume"), "%s: no resume point in the death map" % map_id)
	assert_eq(game.save_game(), OK, "%s: saving while dead stores the committed death" % map_id)
	return before


func _assert_intact(c: CharacterState, before: Dictionary, label: String) -> void:
	for k in ["inventory", "equipment", "quests", "level", "mesos"]:
		var now: Variant = {"inventory": c.inventory.to_dict(), "equipment": c.equipment.to_dict(),
			"quests": c.quests.to_dict(), "level": c.level, "mesos": c.mesos}[k]
		assert_eq(now, before[k], "%s: %s untouched" % [label, k])


func _prepare_character() -> void:
	game.gain_exp(10)
	var c := game.character
	assert_true(bool(QuestEngine.new(c, db()).accept("1000")["ok"]), "a quest in progress")
	c.inventory.add("270", 5, db())


func test_hook_is_installed_and_removed() -> void:
	var hook: Callable = ms.death_commit
	assert_true(hook.is_valid() and hook.get_object() == dc and hook.get_method() == &"commit_rules",
		"MapSession.death_commit = DeathController.commit_rules")
	assert_false((ms.death_rules as Callable).is_valid(), "the respawn-time hook is not used")
	assert_true(ms.is_connected("death_committed", dc._on_death_committed), "the save at the death is wired")
	dc.detach()
	assert_false((ms.death_commit as Callable).is_valid(), "detach removes the hook")
	assert_false(ms.is_connected("death_committed", dc._on_death_committed), "and the save hook")
	dc.attach()


func test_test_f_deaths_in_40_and_1014() -> void:
	_prepare_character()
	var c := game.character
	var deaths := 0
	for map_id in ["000000040", "000001014"]:
		var before := _die_in(map_id)
		deaths += 1
		var at_death := _snapshot(c)
		assert_eq(dc.confirm(), OK, "%s: OK" % map_id)
		var expected := _town_of(map_id)
		assert_eq(ms.current_map, expected, "%s respawns at its canonical returnMap" % map_id)
		assert_eq(ms.last_transition.via, "respawn", "via respawn")
		assert_eq(ms.last_arrival.to_dict(), {"map_id": expected, "spawn_index": _spawn_index()}, "the respawn player spawn")
		assert_eq([c.exp, c.hp, c.mp], [at_death["exp"], at_death["hp"], at_death["mp"]], "%s: OK only travels" % map_id)
		assert_eq(dc.rules.applied_count, deaths, "%s: the rules ran once for this death" % map_id)
		assert_eq(c.exp, maxi(0, int(before["exp"]) - int(before["loss"])), "%s: canonical EXP penalty, once" % map_id)
		assert_false(dc.is_dead() or dc.is_committed(), "alive, nothing pending")
		assert_eq(String(dc.last_report.get("returned_to", "")), expected, "report: returned_to")
		assert_eq(int(dc.last_report["save_error"]), OK, "saved after the respawn")
		var r := svc.read_save(SLOT)
		assert_true(r.ok(), "%s: the save is valid: %s" % [map_id, r.message])
		assert_eq([r.character.exp, r.character.hp, r.character.mp], [c.exp, c.hp, c.mp], "%s: saved vitals" % map_id)
		assert_eq(String(r.character.location["map_id"]), expected, "%s: saved at the return map" % map_id)
		_assert_intact(c, before, map_id)
		assert_eq(r.character.inventory.count("270"), 5, "%s: saved inventory" % map_id)
		assert_eq(r.character.quests.status("1000"), QuestLog.IN_PROGRESS, "%s: saved quest state" % map_id)


## Brief Test F, death -> quit -> reload: the save made at the death is all a quit leaves behind; the reload enters
## from BOOT at the return town, the EXP penalty taken exactly once, inventory and quests intact.
func test_test_f_death_quit_reload_in_40_and_1014() -> void:
	_prepare_character()
	for map_id in ["000000040", "000001014"]:
		var before := _die_in(map_id)
		var c := game.character
		var at_death := _snapshot(c)
		var town := _town_of(map_id)
		# Quit (the window closes): Game saves on the close notification (allowed: the death is committed), then the
		# shell's commit_death_on_quit; then the process ends.
		assert_eq(game.save_game(), OK, "%s: Game's save on close" % map_id)
		assert_eq(dc.commit_death_for_quit(), OK, "%s: the shell's quit while dead" % map_id)
		assert_eq(dc.rules.applied_count, 1, "%s: quitting applies nothing more" % map_id)
		game.close_game()
		dc.detach()
		dc.free()
		ms.reset()
		# Reload: a fresh controller, Game loads the slot, MapSession enters from BOOT.
		assert_eq(game.load_game(SLOT), OK, "%s: reload" % map_id)
		c = game.character
		ms.character = c
		dc = _new_controller()
		assert_eq(ms.state_name(), "BOOT", "%s: the reset session waits in BOOT" % map_id)
		assert_eq(ms.load_character(c), OK, "%s: enter the world" % map_id)
		assert_eq(ms.state_name(), "IDLE", "%s: alive in the world" % map_id)
		assert_eq(ms.current_map, town, "%s: reloaded in the return town" % map_id)
		assert_eq(ms.last_arrival.to_dict(), {"map_id": town, "spawn_index": _spawn_index()}, "%s: at the respawn spawn" % map_id)
		assert_eq(ms.last_transition.load_step, ArrivalResolver.STEP_ENTRY, "%s: entered through the entry, no resume" % map_id)
		assert_eq(c.exp, maxi(0, int(before["exp"]) - int(before["loss"])), "%s: EXP penalty exactly once" % map_id)
		assert_eq([c.exp, c.hp, c.mp], [at_death["exp"], at_death["hp"], at_death["mp"]], "%s: the state of the death" % map_id)
		assert_true(c.hp > 0, "%s: not dead on arrival" % map_id)
		assert_false(dc.is_dead(), "%s: no death after the reload" % map_id)
		assert_eq(dc.rules.applied_count, 0, "%s: the reload applies no rule" % map_id)
		assert_eq(ms.respawn(), ERR_UNAVAILABLE, "%s: nothing to respawn from" % map_id)
		game.change_hp(0)  # the HUD refresh a load emits: HP above 0 is no death
		assert_false(dc.is_dead(), "%s: the HP watch stays quiet" % map_id)
		_assert_intact(c, before, map_id)
		assert_eq(c.inventory.count("270"), 5, "%s: inventory after the reload" % map_id)
		assert_eq(c.quests.status("1000"), QuestLog.IN_PROGRESS, "%s: quest after the reload" % map_id)


func test_death_announced_by_another_system() -> void:
	game.gain_exp(10)
	var exp_before := game.character.exp
	ms.debug_warp("000001010")
	ev.emit_signal("player_died", "000001010")
	assert_true(dc.is_dead(), "Events.player_died opens the death flow")
	assert_eq(ms.state_name(), "DEAD", "MapSession followed")
	assert_true(dc.is_committed() and game.character.exp < exp_before, "the loss is taken before the controller hears the death")
	assert_eq(String(dc.last_report.get("map_id", "")), "000001010", "report map")
	assert_eq(dc.confirm(), OK, "OK")
	assert_eq(ms.current_map, "000001010", "a town respawns in itself")
	assert_false(dc.is_dead(), "alive")
	assert_eq(dc.rules.applied_count, 1, "once")


func test_disarmed_watch_ignores_hp_zero() -> void:
	dc.armed = false
	game.change_hp(-9999)
	assert_false(dc.is_dead(), "loading / title: no death")
	assert_eq(ms.state_name(), "IDLE", "session untouched")
	assert_eq(dc.rules.applied_count, 0, "no penalty")


func test_confirm_needs_a_death_and_runs_once() -> void:
	assert_eq(dc.confirm(), ERR_UNAVAILABLE, "nothing to confirm")
	game.change_hp(-9999)
	assert_eq(dc.kill(), ERR_ALREADY_IN_USE, "already dead")
	var events: Array = []
	dc.respawned.connect(func(m: String, _r: Dictionary) -> void: events.append(m))
	assert_eq(dc.confirm(), OK, "first OK")
	assert_eq(dc.confirm(), ERR_UNAVAILABLE, "second OK does nothing")
	assert_eq(events.size(), 1, "one respawn")
	assert_eq(dc.rules.applied_count, 1, "one penalty")


func test_commit_signal_reports_after_the_save() -> void:
	game.gain_exp(10)
	var seen: Array = []
	dc.committed.connect(func(m: String, report: Dictionary) -> void:
		seen.append([m, int(report.get("death_save_error", -1)), svc.read_save(SLOT).character.exp]))
	ms.debug_warp("000000040")
	game.change_hp(-9999)
	assert_eq(seen.size(), 1, "committed once")
	if seen.size() == 1:
		assert_eq(seen[0], ["000000040", OK, game.character.exp], "the save is on disk when committed fires")


## The EXP loss shows at the death, as in classic: Events.exp_gained(-exp_lost, "death") exactly once per death, once
## the death is both committed and announced, in every ordering; nothing at OK (the HUD redraws only its EXP bar for
## it, so its HP gauge keeps the killing blow's 0 under the notice).
func test_the_exp_loss_is_announced_once_at_the_death() -> void:
	game.gain_exp(10)
	var seen: Array = []
	var on_exp := func(amount: int, source: String) -> void:
		seen.append([amount, source, dc.is_dead(), dc.is_committed(), game.character.exp])
	ev.connect("exp_gained", on_exp)
	# HP 0 (MapSession.enter_dead: committed, then announced).
	ms.debug_warp("000000040")
	var exp_before := game.character.exp
	game.change_hp(-9999)
	var lost := exp_before - game.character.exp
	assert_true(lost > 0, "this death costs EXP")
	assert_eq(seen, [[-lost, DeathController.EXP_LOSS_SOURCE, true, true, game.character.exp]],
		"once, at the death, after the loss was taken")
	seen.clear()
	assert_eq(dc.confirm(), OK, "OK")
	assert_eq(seen, [], "nothing at OK")
	# Another system announces the death (MapSession commits before the controller hears it).
	ms.debug_warp("000000040")
	exp_before = game.character.exp
	ev.emit_signal("player_died", "000000040")
	assert_eq(seen, [[game.character.exp - exp_before, DeathController.EXP_LOSS_SOURCE, true, true, game.character.exp]],
		"once for a death another system announced")
	seen.clear()
	assert_eq(dc.confirm(), OK, "OK")
	# A death during a warp: announced at once, committed (and shown) when the warp ends.
	ms.debug_warp("000000040")
	ms.state = ms.State.WARP_IN
	exp_before = game.character.exp
	game.change_hp(-9999)
	assert_true(dc.is_dead() and not dc.is_committed(), "dead, not committed during the warp")
	assert_eq(seen, [], "no EXP loss to show before the commit")
	var rec := TransitionRecord.new()
	rec.via = "debug"
	rec.to_map = "000000040"
	ms._complete(rec)
	assert_eq(seen, [[game.character.exp - exp_before, DeathController.EXP_LOSS_SOURCE, true, true, game.character.exp]],
		"once, when the warp ends and the death is committed")
	assert_true(game.character.exp < exp_before, "the loss is real")
	seen.clear()
	assert_eq(dc.confirm(), OK, "OK")
	assert_eq(seen, [], "nothing at OK")
	assert_eq(dc.rules.applied_count, 3, "three deaths, three penalties")
	ev.disconnect("exp_gained", on_exp)


func test_death_during_a_warp_respawns_after_the_warp() -> void:
	game.gain_exp(10)
	var c := game.character
	var exp_before := c.exp
	var loss := Progression.death_exp_loss(c.level, c.get_base_stat("luk"), db())
	ms.debug_warp("000000040")
	ms.state = ms.State.WARP_IN
	game.change_hp(-9999)
	assert_true(dc.is_dead(), "the death is announced at once")
	assert_eq(ms.state_name(), "WARP_IN", "the warp is not interrupted")
	assert_false(dc.is_committed(), "not committed during the warp")
	assert_eq(dc.confirm(), OK, "OK during the warp is queued")
	assert_true(dc.is_waiting_for_session(), "waiting for DEAD")
	assert_eq(dc.confirm(), ERR_BUSY, "a second OK is ignored")
	var rec := TransitionRecord.new()
	rec.via = "debug"
	rec.to_map = "000000040"
	ms._complete(rec)
	assert_false(dc.is_waiting_for_session(), "the queued OK ran when MapSession entered DEAD")
	assert_eq(ms.state_name(), "IDLE", "respawned")
	assert_eq(ms.current_map, "000000060", "respawned at 40's returnMap")
	assert_false(dc.is_dead(), "alive")
	assert_eq(dc.rules.applied_count, 1, "committed once, when the warp ended")
	assert_eq(c.exp, maxi(0, exp_before - loss), "one penalty")


## A death during a warp is committed only when the warp ends; a quit in between commits it through the shell's
## fallback. If the warp then ends after all, MapSession's commit must not take the EXP a second time.
func test_quit_during_the_warp_of_a_death_commits_once() -> void:
	game.gain_exp(10)
	var c := game.character
	var exp_before := c.exp
	var loss := Progression.death_exp_loss(c.level, c.get_base_stat("luk"), db())
	assert_eq(game.save_game(), OK, "a save before the death")
	ms.debug_warp("000000040")
	ms.state = ms.State.ARRIVING
	game.change_hp(-9999)
	assert_true(dc.is_dead() and not ms.is_death_committed(), "dead, not committed (the warp is in flight)")
	assert_eq(game.save_game(), ERR_UNAVAILABLE, "Game cannot save mid-warp")
	assert_eq(dc.commit_death_for_quit(), OK, "the shell commits it on quit")
	var r := svc.read_save(SLOT)
	assert_true(r.ok(), "valid save: %s" % r.message)
	assert_eq(r.character.exp, maxi(0, exp_before - loss), "the penalty is in the save")
	assert_eq(String(r.character.location.get("map_id", "")), "000000060", "saved at 40's returnMap")
	assert_eq(r.character.location.get("entry", {}), {"map_id": "000000060", "spawn_index": _spawn_index()}, "respawn spawn")
	assert_eq(r.character.respawn_reference, _town_of("000000060"), "the town's own respawn reference")
	assert_true(r.character.hp > 0, "saved alive")
	# The warp ends after all: MapSession enters DEAD and calls the hook, which must not apply again.
	var rec := TransitionRecord.new()
	rec.via = "debug"
	rec.to_map = "000000040"
	ms._complete(rec)
	assert_true(ms.is_death_committed(), "MapSession committed at DEAD")
	assert_eq(dc.rules.applied_count, 1, "the rules ran once")
	assert_eq(c.exp, maxi(0, exp_before - loss), "the EXP is taken once")


func test_a_load_out_of_death_clears_the_death_state() -> void:
	ms.debug_warp("000000040")
	game.change_hp(-9999)
	assert_true(dc.is_dead(), "dead")
	assert_eq(ms.load_character(game.character), OK, "a load from DEAD (MapSession emits player_respawned)")
	assert_false(dc.is_dead() or dc.is_committed(), "the death flow is cleared")
	assert_eq(ms.state_name(), "IDLE", "MapSession left DEAD")


func test_a_load_out_of_death_emits_death_cleared_once() -> void:
	# The shell leaves its DEAD state on death_cleared; without it the flow stayed DEAD after a console load, with
	# Esc and Quit to Title refused for the rest of the session.
	var cleared: Array = []
	var respawns: Array = []
	dc.death_cleared.connect(func(m: String) -> void: cleared.append(m))
	dc.respawned.connect(func(m: String, _r: Dictionary) -> void: respawns.append(m))
	ms.debug_warp("000000040")
	game.change_hp(-9999)
	# What MapSession does on Game.character_replaced while DEAD (the console's load; this private session is not
	# connected to the private GameState).
	assert_eq(ms.load_character(game.character), OK, "a load while dead")
	assert_false(dc.is_dead(), "the load ended the death")
	assert_eq(cleared.size(), 1, "death_cleared once")
	assert_eq(respawns.size(), 0, "not a respawn: no report, no save")
	# A normal respawn afterwards emits respawned, not death_cleared.
	game.change_hp(-9999)
	assert_eq(dc.confirm(), OK, "OK")
	assert_eq([cleared.size(), respawns.size()], [1, 1], "a respawn is not a cleared death")
	assert_eq(dc.rules.applied_count, 2, "two deaths, two penalties")


## The console's respawn (MapSession.respawn() without the notice's OK) ends the death without confirm(): the
## controller clears it and refreshes the HUD, which still showed the killing blow's HP 0.
func test_a_respawn_without_ok_clears_the_death_and_refreshes_the_hud() -> void:
	game.gain_exp(10)
	ms.debug_warp("000000040")
	game.change_hp(-9999)
	assert_true(dc.is_dead(), "dead")
	var hp_seen: Array = []
	var on_hp := func(hp: int, _max_hp: int) -> void: hp_seen.append(hp)
	ev.connect("hp_changed", on_hp)
	var cleared: Array = []
	dc.death_cleared.connect(func(m: String) -> void: cleared.append(m))
	assert_eq(ms.respawn(), OK, "the console's respawn")
	ev.disconnect("hp_changed", on_hp)
	assert_eq(cleared, ["000000060"], "death_cleared once, in 40's return town")
	assert_false(dc.is_dead() or dc.is_committed(), "the death is over")
	assert_true(game.character.hp > 0 and hp_seen.has(game.character.hp), "the HUD hears the live HP: %s" % str(hp_seen))
	assert_eq(dc.rules.applied_count, 1, "the penalty once")


## The death screen's load (the console's "load" while the notice is up) loads the save written at the death: the
## character in the return town with the penalty taken once, alive, and no second penalty on the way.
func test_load_from_the_death_screen_finds_the_committed_death() -> void:
	_prepare_character()
	var before := _die_in("000000040")
	var cleared: Array = []
	dc.death_cleared.connect(func(m: String) -> void: cleared.append(m))
	assert_eq(game.load_game(SLOT), OK, "load the current slot while dead")
	var c := game.character
	ms.character = c
	assert_eq(ms.load_character(c), OK, "MapSession loads it (what it does on Game.character_replaced in DEAD)")
	assert_eq(ms.state_name(), "IDLE", "alive")
	assert_eq(ms.current_map, "000000060", "in 40's return town")
	assert_eq(ms.last_arrival.to_dict(), {"map_id": "000000060", "spawn_index": _spawn_index()}, "at the respawn spawn")
	assert_eq(c.exp, maxi(0, int(before["exp"]) - int(before["loss"])), "the penalty, once")
	assert_true(c.hp > 0, "HP above 0")
	assert_false(dc.is_dead() or dc.is_committed(), "the death is over")
	assert_eq(cleared, ["000000060"], "death_cleared once, in town")
	assert_eq(dc.rules.applied_count, 1, "no second penalty")
	_assert_intact(c, before, "load from the death screen")


func test_modal_windows_close_at_death_and_input_is_not_left_to_a_stale_modal() -> void:
	# A conversation or shop open at the death must not outlive it: it would hold the keyboard over the notice and,
	# after the respawn, stay open in town with a modal still registered.
	var ctx := GameContext.new()
	dc.ctx = ctx
	var shop := Control.new()
	var inventory := Control.new()
	ctx.window_opened(inventory)  # non-modal, opened first
	ctx.window_opened(shop)
	ctx.push_modal(shop)
	var closer := func(w: Control, open: bool) -> void:
		if w == shop and not open:
			ctx.pop_modal(shop)  # what DialogueWindow / ShopWindow do in close()
	ctx.window_changed.connect(closer)
	ms.debug_warp("000001010")
	game.change_hp(-9999)
	assert_true(dc.is_dead(), "dead")
	assert_false(shop.visible, "the modal shop was closed at the death")
	assert_true(inventory.visible, "a non-modal window stays open")
	assert_true(ctx.is_modal_active(), "only the death flow holds the keyboard")
	assert_eq(dc.confirm(), OK, "OK")
	assert_false(ctx.is_modal_active(), "no modal left after the respawn")
	ctx.window_changed.disconnect(closer)
	dc.ctx = null
	shop.free()
	inventory.free()


func test_quitting_while_dead_keeps_the_committed_death() -> void:
	game.gain_exp(10)
	var c := game.character
	c.inventory.add("270", 2, db())
	assert_eq(game.save_game(), OK, "a save before the death")
	ms.debug_warp("000000040")
	var exp_before := c.exp
	var loss := Progression.death_exp_loss(c.level, c.get_base_stat("luk"), db())
	game.change_hp(-9999)
	assert_true(dc.is_dead(), "dead")
	assert_eq(dc.commit_death_for_quit(), OK, "quitting while dead saves")
	var expected := _town_of("000000040")
	var r := svc.read_save(SLOT)
	assert_true(r.ok(), "a valid save: %s" % r.message)
	assert_eq(r.character.exp, maxi(0, exp_before - loss), "the canonical EXP penalty is in the save")
	assert_eq(r.character.hp, _want_vitals(c, c.mp)[0], "death.json HP in the save")
	assert_eq(String(r.character.location.get("map_id", "")), expected, "saved at the canonical returnMap")
	assert_eq(r.character.location.get("entry", {}), {"map_id": expected, "spawn_index": _spawn_index()},
		"at the respawn player spawn")
	assert_false((r.character.location as Dictionary).has("resume"), "no resume point in the death map")
	assert_eq(r.character.respawn_reference, _town_of(expected), "respawn reference of the town")
	assert_eq(r.character.inventory.count("270"), 2, "inventory untouched")
	# A second quit (the window close after Quit Game) does not take the EXP twice.
	assert_eq(dc.commit_death_for_quit(), OK, "saved again")
	assert_eq(svc.read_save(SLOT).character.exp, maxi(0, exp_before - loss), "the penalty applies once")
	assert_eq(dc.rules.applied_count, 1, "the rules ran once")
	# OK afterwards (the quit was cancelled) travels without a second penalty.
	assert_eq(dc.confirm(), OK, "OK")
	assert_eq(c.exp, maxi(0, exp_before - loss), "still once")


func test_attached_after_the_death_commits_it() -> void:
	dc.detach()
	game.gain_exp(10)
	var exp_before := game.character.exp
	ms.debug_warp("000000040")
	ms.enter_dead()
	assert_false(ms.is_death_committed(), "no hook: nothing committed")
	dc.attach()
	assert_true(ms.is_death_committed(), "attach commits the death it finds")
	assert_true(game.character.exp < exp_before, "the penalty applied")
	assert_eq(dc.rules.applied_count, 1, "once")


func test_commit_needs_a_death() -> void:
	assert_eq(dc.commit_death_for_quit(), ERR_UNAVAILABLE, "alive: nothing to commit")
