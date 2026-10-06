extends Node
## Drives the real main scene (res://scenes/main.tscn) through the game shell's flows with real frames, physics and
## autoloads, printing one line per check. Run by res://scenes/ui/screens/shell_checks.tscn:
##
##   godot --headless --fixed-fps 60 --path <project> res://scenes/ui/screens/shell_checks.tscn -- --scenario flow
##   godot --headless --fixed-fps 60 --path <project> res://scenes/ui/screens/shell_checks.tscn -- --scenario death
##   godot --resolution 1600x900 --path <project> res://scenes/ui/screens/shell_checks.tscn -- --scenario shots --out <dir>
##
## flow   the acceptance flow: title -> new game -> world ready -> player at 000000001 player_spawns[0] -> walk ->
##        save -> pause/resume, Esc closes a window first, modals and the world -> quit to title (MapSession back in
##        BOOT) -> continue -> same map, position, stats -> quit to title -> a second new game
## death  brief Test F: die in 000000040 and 000001014 (HP 0 through Game.change_hp) and once by another system's
##        Events.player_died: the loss taken and saved at the death, notice, the HUD under it (EXP bar already
##        dropped, HP 0), the jump keys pressed for real leave it up, OK only travels to the returnMap, death.json
##        HP/MP, revive, valid save,
##        inventory/equipment/quests untouched; a death mid-warp, by monster touch, with a dialogue open and while
##        paused; then quit to title and continue from that save, a load from the death screen, and closing the
##        window while dead
## death_quit    brief Test F as a real quit, one link of a chain of processes sharing --save-dir (with --keep-saves):
##        start (a new game; or, when the directory holds the previous link's expectations, Continue and verify that
##        death first), die in --map, check the loss was taken and saved at the death, write the expectations, close
##        the window (NOTIFICATION_WM_CLOSE_REQUEST through the tree) and exit
## death_reload  the last link: Continue and verify the previous death (test_death_quit_reload.gd runs the chain)
## shots  windowed screenshots of the title, creation (and a tooltip on it), the game after spawning, the death notice,
##        the pause menu, its Controls panel and the title's slot list
##
## Output: "SHELL_CHECK PASS|FAIL <name>[: detail]", "SHELL_INFO ...", "SHELL_SHOT <path>", and finally
## "SHELL_CHECKS_DONE <passed> <failed>"; exit code 0 when nothing failed. Saves go to a private user://_tests/
## directory (the project's user:// is shared with the real game), which is deleted at the end unless --keep-saves.

const MAIN_SCENE := "res://scenes/main.tscn"
const TIMEOUT_FRAMES := CheckWait.DEFAULT_FRAMES
## The death_quit chain's expectations, next to the saves (not a .json file, so it is never listed as a slot).
const EXPECT_FILE := "test_f_expect.txt"
## The quest and the item Test F carries through its deaths.
const TEST_F_QUEST := "1000"
const TEST_F_ITEM_NAME := "Red Potion"

var scenario := "flow"
var out_dir := ""
var main: MainShell = null
var save_dir := ""
var keep_saves := false
## death_quit: the map to die in.
var map_arg := ""
var passed := 0
var failed := 0
var _shot_index := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	scenario = _arg(args, "--scenario", "flow")
	out_dir = _arg(args, "--out", "user://shell_shots")
	save_dir = _arg(args, "--save-dir", "")
	keep_saves = "--keep-saves" in args
	map_arg = _arg(args, "--map", "000000040")
	_run.call_deferred()


func _run() -> void:
	var saves := get_node("/root/Saves")
	if save_dir == "":
		save_dir = "user://_tests/shell_%s_%d" % [scenario, Time.get_ticks_usec()]
	saves.set("save_dir", save_dir)
	var game := get_node("/root/Game") as GameState
	game.autosave_enabled = true
	main = (load(MAIN_SCENE) as PackedScene).instantiate() as MainShell
	main.use_command_line = false
	add_child(main)
	await _frames(2)
	match scenario:
		"flow":
			await _flow()
		"death":
			await _death()
		"death_quit":
			await _death_quit()
		"death_reload":
			await _death_reload()
		"shots":
			await _shots()
		_:
			_check("scenario", false, "unknown scenario '%s'" % scenario)
	if not keep_saves:
		_remove_tree(save_dir)
	print("SHELL_CHECKS_DONE %d %d" % [passed, failed])
	get_tree().paused = false
	get_tree().quit(0 if failed == 0 else 1)


# --- the acceptance flow -----------------------------------------------------------------------------------------

func _flow() -> void:
	var game := get_node("/root/Game") as GameState
	var session := get_node("/root/MapSession")
	_check("boot shows the title", main.flow.is_in(ShellFlow.State.TITLE) and main.title.visible)
	var miso := ScreenKit.theme()
	_check("the root window wears MisoTheme (tooltips and popups share the look)", miso != null
		and get_tree().root.theme == miso, "root theme %s, MisoTheme %s" % [get_tree().root.theme, miso])
	_check("MapSession waits in BOOT", String(session.call("state_name")) == "BOOT", String(session.call("state_name")))
	_check("no Continue without a save", not main.title.continue_button.visible)
	_check("open creation", main.open_creation() and main.flow.is_in(ShellFlow.State.CREATE) and main.creation != null)
	var model := main.creation.model
	model.name = "Tester"
	model.gender = "female"
	model.clear_ap()
	model.add_ap("str", 5)
	model.add_ap("dex", 4)
	model.weapon_id = "541"
	main.creation.refresh()
	_check("creation is valid", model.is_valid(), ", ".join(model.errors()))
	_check("creation Start button enabled", not main.creation.start_button.disabled)
	var t0 := Time.get_ticks_msec()
	main.creation.submit()
	_check("loading screen shown", main.flow.is_in(ShellFlow.State.LOADING) and main.loading.visible)
	var ok := await _until(func() -> bool: return not main.flow.is_in(ShellFlow.State.LOADING))
	_check("new game reaches PLAYING", ok and main.flow.is_in(ShellFlow.State.PLAYING), main.last_error_message)
	if not main.flow.is_in(ShellFlow.State.PLAYING):
		return
	_info("new game ready in %d ms" % (Time.get_ticks_msec() - t0))
	var gs := main.game_session
	var c := main.ctx()
	_check("loading screen hidden", not main.loading.visible)
	_check("context complete", c != null and c.world == gs.world and c.player == gs.player and c.camera == gs.camera
		and c.ui_root != null and c.systems != null and c.main == main)
	_check("one installer row per subsystem", gs.installer.report.size() == SubsystemInstaller.DEFAULT_SUBSYSTEMS.size())
	var failed_rows: PackedStringArray = []
	for row in gs.installer.report:
		if row["status"] == SubsystemInstaller.STATUS_FAILED:
			failed_rows.append("%s (%s, owned by that system): %s" % [row["name"], row["scene"], row["error"]])
	_check("no subsystem failed", failed_rows.is_empty(), "; ".join(failed_rows))
	_info("subsystems: " + gs.installer.summary())
	_check("quest system wired", game.quests != null and game.npc_talk != null and game.quests.is_attached())
	var hook := session.get("death_commit") as Callable
	_check("death commit hook installed", hook.is_valid() and hook.get_object() == gs.death
		and hook.get_method() == &"commit_rules" and not (session.get("death_rules") as Callable).is_valid())
	_check("MapSession idle in 000000001", session.call("is_idle") and String(session.get("current_map")) == "000000001",
		"%s %s" % [session.call("state_name"), session.get("current_map")])
	var def: MapDefinition = (session.call("get_defs") as MapDefinitions).get_def("000000001")
	var spawn := def.player_spawn(0).origin
	var p := gs.player
	_check("player placed at player_spawns[0]", _flat(p.global_position - spawn) < 0.3,
		"at %s, spawn %s" % [p.global_position, spawn])
	_check("player on the floor", p.is_on_floor())
	_check("character created as chosen", game.character.name == "Tester" and game.character.gender == "female"
		and game.character.equipment.weapon_id() == "541" and game.character.get_base_stat("str") == 9
		and game.character.get_base_stat("dex") == 8)
	_check("initial save written", (get_node("/root/Saves").call("has_save", main.target_slot) as bool), main.target_slot)
	_check("player input on", (p as PlayerController).is_input_enabled())
	await _modal_and_world(gs, session)

	# Walk a little so the save holds a resume point that is not the spawn.
	var bot := BotInput.new()
	(p as PlayerController).set_input_source(bot)
	bot.world_dir = (gs.camera as CameraRig).ground_right
	await _physics(40)
	bot.release_all()
	await _until(func() -> bool: return (p as PlayerController).is_grounded() and p.velocity.length() < 0.05, 120)
	await _physics(10)
	_check("walked away from the spawn", _flat(p.global_position - spawn) > 0.8, "moved %.2f m" % _flat(p.global_position - spawn))
	game.gain_exp(7)
	var err := main.save_now()
	_check("save", err == OK, error_string(err))
	var saved_pos: Vector3 = (gs.world.call("safe_point") as Dictionary).get("position", Vector3.ZERO)
	var saved_map := String(session.get("current_map"))
	var saved_char := _comparable(game.character.to_dict())
	_check("save holds a resume point", (game.character.location as Dictionary).has("resume"))

	# Pause menu and Esc.
	_check("pause", main.pause() and main.flow.is_in(ShellFlow.State.PAUSED) and get_tree().paused and main.pause_menu.visible)
	_check("pause takes the keyboard", c.is_modal_active() and not (p as PlayerController).is_input_enabled())
	_check("save from the pause menu", main.save_now() == OK)
	_check("resume", main.resume() and not get_tree().paused and main.flow.is_in(ShellFlow.State.PLAYING)
		and not c.is_modal_active() and (p as PlayerController).is_input_enabled())
	var w := Control.new()
	c.ui_root.add_child(w)
	c.window_opened(w)
	_check("Esc closes the newest window first", main.handle_menu_action() and not w.visible
		and main.flow.is_in(ShellFlow.State.PLAYING))
	w.queue_free()
	_check("Esc with no window opens the pause menu", main.handle_menu_action() and main.flow.is_in(ShellFlow.State.PAUSED))
	_check("Esc in the pause menu resumes", main.handle_menu_action() and main.flow.is_in(ShellFlow.State.PLAYING))
	await _frames(2)

	# Quit to title, then continue.
	err = main.quit_to_title()
	_check("quit to title", err == OK and main.flow.is_in(ShellFlow.State.TITLE) and main.title.visible, error_string(err))
	await _frames(2)
	_check("session gone", main.game_session == null and not is_instance_valid(gs) and not game.has_active_game()
		and not get_tree().paused)
	_check_session_reset(session)
	_check("Continue offered", main.title.continue_button.visible and main.title.continue_slot == main.target_slot)
	var entry := SaveSlotIndex.entry(get_node("/root/Saves").call("list_saves"), main.target_slot)
	var meta: Dictionary = entry.get("meta", {})
	_check("slot list shows name, level, map, play time", String(meta.get("name", "")) == "Tester"
		and int(meta.get("level", 0)) == 1 and String(meta.get("map_id", "")) == saved_map
		and String(meta.get("map_name", "")) != "" and meta.has("play_time_s"), str(meta))
	await _frames(30)
	t0 = Time.get_ticks_msec()
	main.continue_game()
	ok = await _until(func() -> bool: return not main.flow.is_in(ShellFlow.State.LOADING))
	_check("continue reaches PLAYING", ok and main.flow.is_in(ShellFlow.State.PLAYING), main.last_error_message)
	if not main.flow.is_in(ShellFlow.State.PLAYING):
		return
	_info("continue ready in %d ms" % (Time.get_ticks_msec() - t0))
	gs = main.game_session
	p = gs.player
	await _until(func() -> bool: return p.is_on_floor(), 60)
	_check("same map", String(session.get("current_map")) == saved_map, String(session.get("current_map")))
	_check("same position", _flat(p.global_position - saved_pos) < 0.1 and absf(p.global_position.y - saved_pos.y) < 0.3,
		"at %s, saved %s" % [p.global_position, saved_pos])
	_check("resumed from the resume point", session.get("last_transition") != null
		and String((session.get("last_transition") as TransitionRecord).load_step) == ArrivalResolver.STEP_RESUME,
		String((session.get("last_transition") as TransitionRecord).load_step) if session.get("last_transition") != null else "")
	var first_rec := (session.get("transition_log") as Array)[0] as TransitionRecord if not (session.get("transition_log") as Array).is_empty() else null
	_check("the continued session starts clean (its first entry leaves no old map)", first_rec != null
		and first_rec.from_map == "" and first_rec.via == "load", str(first_rec.to_dict()) if first_rec != null else "no record")
	var diff := _diff(saved_char, _comparable(game.character.to_dict()))
	_check("same stats, inventory, equipment and quests", diff == "", diff)
	var data_db := get_node("/root/Data").get("db") as ContentDB
	_check("player stats synced", is_equal_approx((p as PlayerController).model.speed_stat,
		float(StatCalculator.speed(game.character, data_db))))
	_check("game active again", game.has_active_game() and game.current_slot == main.target_slot)

	# Quit to title, then New Game: MapSession is back in BOOT, so the new game enters through start_new_game() at
	# new_character.json's start, exactly like the first one, and nothing of the last session leaks in.
	var first_slot := main.target_slot
	var first_save := _comparable((get_node("/root/Saves").call("read_save", first_slot) as SaveLoadResult).character.to_dict())
	_check("quit to title again", main.quit_to_title() == OK)
	await _frames(5)
	_check_session_reset(session)
	_check("open creation again", main.open_creation())
	main.creation.model.name = "Second"
	main.creation.refresh()
	main.creation.submit()
	ok = await _until(func() -> bool: return not main.flow.is_in(ShellFlow.State.LOADING))
	_check("second new game reaches PLAYING", ok and main.flow.is_in(ShellFlow.State.PLAYING), main.last_error_message)
	if not main.flow.is_in(ShellFlow.State.PLAYING):
		return
	p = main.game_session.player
	await _until(func() -> bool: return p.is_on_floor(), 120)
	var rec := session.get("last_transition") as TransitionRecord
	_check("second game in a new slot", main.target_slot != first_slot and game.current_slot == main.target_slot
		and game.character.name == "Second" and game.character.level == 1, "%s / %s" % [main.target_slot, first_slot])
	_check("second game at 000000001 player_spawns[0]", String(session.get("current_map")) == "000000001"
		and _flat(p.global_position - spawn) < 0.3 and rec != null and rec.load_step == ArrivalResolver.STEP_ENTRY,
		"%s at %s via %s" % [session.get("current_map"), p.global_position, rec.load_step if rec != null else "?"])
	var first_now := _comparable((get_node("/root/Saves").call("read_save", first_slot) as SaveLoadResult).character.to_dict())
	_check("the first slot is untouched", _diff(first_save, first_now) == "", _diff(first_save, first_now))


## GameSession hands its context to the world (world.set_context): the world asks THAT context whether a modal owns
## the keyboard (checked with GameSession.ctx hidden, so the parent fallback cannot answer), a warp that completes
## under a modal leaves the input off, and closing the last modal gives it back.
func _modal_and_world(gs: GameSession, session: Node) -> void:
	var c := gs.ctx
	var w := gs.world
	var p := gs.player as PlayerController
	var probe := RefCounted.new()
	gs.ctx = null
	var before := bool(w.call("is_modal_active"))
	c.push_modal(probe)
	var during := bool(w.call("is_modal_active"))
	gs.ctx = c
	_check("the world asks the context it was given", not before and during, "before %s during %s" % [before, during])
	var err: Error = session.call("debug_warp", String(session.get("current_map")))
	var ok := await _until(func() -> bool: return bool(session.call("is_idle")))
	await _frames(2)
	_check("a warp ending under a modal leaves the input off", err == OK and ok and not p.is_input_enabled()
		and c.is_modal_active(), "warp %s idle %s input %s" % [error_string(err), ok, p.is_input_enabled()])
	c.pop_modal(probe)
	_check("closing the modal gives the input back", p.is_input_enabled() and not bool(w.call("is_modal_active"))
		and String(w.call("player_input_block")) == "", String(w.call("player_input_block")))
	await _until(func() -> bool: return p.is_on_floor(), 60)


## After quit to title MapSession is back in BOOT with nothing of the last session (MapSession.reset() through
## IslandWorld._exit_tree -> detach_world, and GameSession.teardown), and the death hook is gone.
func _check_session_reset(session: Node) -> void:
	var cache := session.get("cache") as MapStateCache
	_check("MapSession reset to BOOT", String(session.call("state_name")) == "BOOT" and String(session.get("current_map")) == ""
		and cache != null and cache.keys().is_empty() and (session.get("transition_log") as Array).is_empty()
		and session.get("instance_state") == null and session.get("world") == null and session.get("last_transition") == null,
		"%s map '%s' cached %s log %d" % [session.call("state_name"), session.get("current_map"),
			cache.keys() if cache != null else [], (session.get("transition_log") as Array).size()])
	_check("the death hook left with the session", not (session.get("death_commit") as Callable).is_valid())


# --- Test F -----------------------------------------------------------------------------------------------------

func _death() -> void:
	var game := get_node("/root/Game") as GameState
	var session := get_node("/root/MapSession")
	var saves := get_node("/root/Saves")
	var db := (get_node("/root/Data").get("db") as ContentDB)
	main.start_new_game({"name": "Mortal", "gender": "male", "ap": {"str": 9}, "weapon_id": "585"})
	var ok := await _until(func() -> bool: return not main.flow.is_in(ShellFlow.State.LOADING))
	_check("new game reaches PLAYING", ok and main.flow.is_in(ShellFlow.State.PLAYING), main.last_error_message)
	if not main.flow.is_in(ShellFlow.State.PLAYING):
		return
	var c := game.character
	game.gain_exp(10)
	var accepted := game.quests.accept("1000")
	_check("quest 1000 accepted", bool(accepted.get("ok", false)), str(accepted.get("reason", "")))
	var potion := _item_named(db, "Red Potion")
	_check("potions added", potion != "" and c.inventory.add(potion, 3, db) == 3, potion)
	game.change_mp(-2)
	var keep := {"inventory": c.inventory.to_dict(), "equipment": c.equipment.to_dict(), "quests": c.quests.to_dict()}
	var rules := DeathRules.from_db(db)
	_check("death.json rules valid", rules.errors.is_empty(), "; ".join(rules.errors))
	var spawn_index := (session.call("get_defs") as MapDefinitions).tuning.count("respawn", "player_spawn_index")
	for case in [["000000040", "hp"], ["000001014", "hp"], ["000000001", "event"]]:
		var map_id := String(case[0])
		var expected_return := String(db.map(map_id).get("return_map_id", ""))
		var err: Error = session.call("debug_warp", map_id)
		_check("%s: warp" % map_id, err == OK, String(session.get("last_error")))
		await _until(func() -> bool: return bool(session.call("is_idle")) and main.game_session.player.is_on_floor())
		await _physics(5)
		var p := main.game_session.player as PlayerController
		var exp_before := c.exp
		var mp_before := c.mp
		var loss := Progression.death_exp_loss(c.level, c.get_base_stat("luk"), db)
		var vit := rules.respawn_vitals()
		var want_hp := maxi(1, DeathRules.vital_value(vit["hp"], 0, StatCalculator.max_hp(c, db)))
		var want_mp := DeathRules.vital_value(vit["mp"], mp_before, StatCalculator.max_mp(c, db))
		var commits: Array = []
		var count_commit := func(m: String, _r: Variant) -> void: commits.append(m)
		session.connect("death_committed", count_commit)
		if String(case[1]) == "hp":
			game.change_hp(-c.hp)
		else:
			get_node("/root/Events").emit_signal("player_died", map_id)
		await _frames(3)
		var notice := main.game_session.death.notice
		_check("%s: dead" % map_id, session.call("state_name") == "DEAD" and p.is_dead() and main.flow.is_in(ShellFlow.State.DEAD),
			"%s dead=%s flow=%s" % [session.call("state_name"), p.is_dead(), ShellFlow.state_name(main.flow.state)])
		_check("%s: death notice shown as a modal" % map_id, notice != null and notice.visible and main.ctx().is_modal_active())
		_check("%s: Esc does not close the notice or pause" % map_id, not main.handle_menu_action() and notice.visible)
		# Space is Godot's default ui_accept and OK holds the focus, but Space and Alt are the jump keys: as real key
		# presses they must leave the notice up (only a click or Enter confirms).
		var focused_ok := notice.ok_button.has_focus()
		for key: Key in [KEY_SPACE, KEY_ALT]:
			await _tap_key(key)
		await _frames(3)
		_check("%s: the jump keys (Space, Alt) do not confirm the notice" % map_id, focused_ok and notice.visible
			and not notice.ok_button.disabled and session.call("state_name") == "DEAD" and main.flow.is_in(ShellFlow.State.DEAD),
			"OK focused %s, notice %s, session %s, flow %s" % [focused_ok, notice.visible, session.call("state_name"),
				ShellFlow.state_name(main.flow.state)])
		_check("%s: the death is committed once, at the death" % map_id, commits == [map_id]
			and bool(session.call("is_death_committed")), str(commits))
		# The HUD under the notice: the EXP bar already dropped (Events.exp_gained(-exp_lost, "death")); the HP gauge
		# keeps the killing blow's 0 (the character already holds its respawn HP). A death announced by another system
		# never sent an HP 0, so only its EXP bar is checked.
		var gauges := _hud_gauges()
		_check("%s: the HUD shows the EXP loss at the death%s" % [map_id, ", HP 0" if String(case[1]) == "hp" else ""],
			not gauges.is_empty() and int(gauges["exp"]) == c.exp and (String(case[1]) != "hp" or int(gauges["hp"]) == 0),
			"HUD %s, character exp %d hp %d" % [gauges, c.exp, c.hp])
		_check("%s: Game.is_character_dead() while the respawn HP is held" % map_id, game.is_character_dead() and c.hp > 0)
		_check("%s: EXP penalty %d at the moment of death" % [map_id, loss], loss > 0 and c.exp == maxi(0, exp_before - loss),
			"%d -> %d" % [exp_before, c.exp])
		_check("%s: HP/MP per death.json set at the death" % map_id, c.hp == want_hp and c.mp == want_mp,
			"hp %d (want %d) mp %d (want %d)" % [c.hp, want_hp, c.mp, want_mp])
		var at_death: SaveLoadResult = saves.call("read_save", main.target_slot)
		_check("%s: saved at the death: the loss, in %s at player spawn %d" % [map_id, expected_return, spawn_index],
			at_death.ok() and at_death.character.exp == c.exp and at_death.character.hp == want_hp
			and String(at_death.character.location.get("map_id", "")) == expected_return
			and at_death.character.location.get("entry", {}) == {"map_id": expected_return, "spawn_index": spawn_index}
			and not (at_death.character.location as Dictionary).has("resume"),
			str(at_death.character.location) if at_death.ok() else at_death.message)
		_check("%s: saving while dead stores the committed death" % map_id, game.save_game() == OK)
		if map_id == "000000040":
			await _shot_if_windowed("death_notice")
		var exp_at_death := c.exp
		notice.confirm()
		ok = await _until(func() -> bool: return main.flow.is_in(ShellFlow.State.PLAYING) and bool(session.call("is_idle")))
		session.disconnect("death_committed", count_commit)
		_check("%s: respawned" % map_id, ok)
		var arrival: ArrivalRef = session.get("last_arrival")
		_check("%s: respawn map = canonical returnMap %s" % [map_id, expected_return],
			String(session.get("current_map")) == expected_return and expected_return != "", String(session.get("current_map")))
		_check("%s: respawn arrival is player spawn %d" % [map_id, spawn_index], arrival != null and arrival.to_dict() ==
			{"map_id": expected_return, "spawn_index": spawn_index}, str(arrival.to_dict() if arrival != null else {}))
		_check("%s: OK only travels (EXP, HP and MP as at the death)" % map_id, c.exp == exp_at_death
			and c.hp == want_hp and c.mp == want_mp and commits.size() == 1,
			"exp %d (at death %d) hp %d mp %d commits %d" % [c.exp, exp_at_death, c.hp, c.mp, commits.size()])
		_check("%s: player revived with input" % map_id, not p.is_dead() and p.is_input_enabled()
			and not main.ctx().is_modal_active() and not notice.visible)
		var r: SaveLoadResult = saves.call("read_save", main.target_slot)
		_check("%s: save valid after respawn" % map_id, r.ok() and r.character.exp == c.exp and r.character.hp == c.hp
			and String(r.character.location.get("map_id", "")) == expected_return, r.message)
		for k in keep:
			var now: Dictionary = {"inventory": c.inventory.to_dict(), "equipment": c.equipment.to_dict(),
				"quests": c.quests.to_dict()}[k]
			var d := _diff(keep[k], now)
			_check("%s: %s not corrupted" % [map_id, k], d == "", d)
			if r.ok():
				var saved_d: Dictionary = {"inventory": r.character.inventory.to_dict(), "equipment": r.character.equipment.to_dict(),
					"quests": r.character.quests.to_dict()}[k]
				d = _diff(keep[k], saved_d)
				_check("%s: saved %s not corrupted" % [map_id, k], d == "", d)
	# A death during a warp: announced at once, MapSession enters DEAD only when the warp completes, so OK is queued
	# and the respawn starts (deferred) on the state change.
	var warp_map := "000000041"
	var warp_return := String(db.map(warp_map).get("return_map_id", ""))
	var exp_w := c.exp
	var loss_w := Progression.death_exp_loss(c.level, c.get_base_stat("luk"), db)
	session.call("debug_warp", warp_map)
	var mid_warp := String(session.call("state_name")) != "IDLE"
	game.change_hp(-c.hp)
	await _frames(1)
	var dc := main.game_session.death
	_check("mid-warp: the death is announced during the warp", mid_warp and dc.is_dead()
		and main.flow.is_in(ShellFlow.State.DEAD), "warping=%s state=%s" % [mid_warp, session.call("state_name")])
	dc.notice.confirm()
	_check("mid-warp: OK is queued until MapSession is DEAD", dc.is_waiting_for_session(), String(session.call("state_name")))
	var respawned_ok := func() -> bool:
		return main.flow.is_in(ShellFlow.State.PLAYING) and bool(session.call("is_idle")) and not dc.is_dead()
	ok = await _until(respawned_ok)
	_check("mid-warp: respawned at %s's returnMap %s" % [warp_map, warp_return],
		ok and String(session.get("current_map")) == warp_return, String(session.get("current_map")))
	_check("mid-warp: the penalty applied once", c.exp == maxi(0, exp_w - loss_w), "%d -> %d" % [exp_w, c.exp])
	var pc := main.game_session.player as PlayerController
	_check("mid-warp: alive with input", not pc.is_dead() and pc.is_input_enabled() and not main.ctx().is_modal_active())
	await _monster_touch_death(game, session, db)
	await _death_with_dialogue_open(game, session, db)
	await _death_while_paused(game, session)
	# Reload the post-death save.
	var after := _comparable(c.to_dict())
	var map_after := String(session.get("current_map"))
	_check("quit to title", main.quit_to_title() == OK)
	await _frames(2)
	main.continue_game()
	ok = await _until(func() -> bool: return not main.flow.is_in(ShellFlow.State.LOADING))
	_check("continue after deaths", ok and main.flow.is_in(ShellFlow.State.PLAYING), main.last_error_message)
	if main.flow.is_in(ShellFlow.State.PLAYING):
		_check("continued in %s" % map_after, String(session.get("current_map")) == map_after)
		var d := _diff(after, _comparable(game.character.to_dict()))
		_check("state after deaths survives the reload", d == "", d)
		await _load_out_of_death(game, session)


## A monster's touch kills exactly the way MonsterSystem.monster_touch does it: StatCalculator.change_hp, then
## hp_changed (ContactDamage.apply), then ContactDamage.announce_death. Events.player_died must fire once (the HP
## watch used to kill synchronously inside hp_changed, so announce_death found MapSession DEAD and emitted again).
func _monster_touch_death(game: GameState, session: Node, db: ContentDB) -> void:
	var ev := get_node("/root/Events")
	var c := game.character
	var map_id := "000000040"
	session.call("debug_warp", map_id)
	await _until(func() -> bool: return bool(session.call("is_idle")) and main.game_session.player.is_on_floor())
	await _physics(5)
	var deaths: Array = []
	var count := func(m: String) -> void: deaths.append(m)
	ev.connect("player_died", count)
	var p := main.game_session.player
	StatCalculator.change_hp(c, -c.hp, db)
	ev.emit_signal("player_damaged", 1, "100100")
	ev.emit_signal("hp_changed", c.hp, StatCalculator.max_hp(c, db))
	ContactDamage.announce_death(p, session, ev, map_id)
	await _frames(3)
	ev.disconnect("player_died", count)
	_check("monster touch: Events.player_died fires once", deaths == [map_id], str(deaths))
	_check("monster touch: dead with the notice", main.game_session.death.is_dead() and main.flow.is_in(ShellFlow.State.DEAD)
		and String(session.call("state_name")) == "DEAD" and main.game_session.death.notice.visible)
	main.game_session.death.notice.confirm()
	_check("monster touch: the notice hides as the respawn starts", not main.game_session.death.notice.visible
		and main.ctx().is_modal_active())
	var ok := await _until(func() -> bool: return main.flow.is_in(ShellFlow.State.PLAYING) and bool(session.call("is_idle")))
	_check("monster touch: respawned at %s" % String(db.map(map_id).get("return_map_id", "")), ok
		and String(session.get("current_map")) == String(db.map(map_id).get("return_map_id", "")))


## Dying with an NPC conversation open: the conversation is closed at the death (it held the keyboard over the
## notice and stayed open after the respawn, as a modal, while MapSession had turned the player's input back on).
func _death_with_dialogue_open(game: GameState, session: Node, db: ContentDB) -> void:
	var map_id := String(session.get("current_map"))
	var npcs: Array = db.map(map_id).get("npcs", [])
	if npcs.is_empty():
		_check("dialogue death: an NPC in %s" % map_id, false)
		return
	var npc_id := String((npcs[0] as Dictionary).get("id", "")) if npcs[0] is Dictionary else String(npcs[0])
	game.npc_talk.talk(npc_id)
	await _frames(3)
	var c := main.ctx()
	_check("dialogue death: conversation with %s open as a modal" % npc_id, game.npc_talk.is_open() and c.is_modal_active()
		and c.has_open_windows())
	game.change_hp(-game.character.hp)
	await _frames(3)
	var dc := main.game_session.death
	_check("dialogue death: the conversation closed at the death", dc.is_dead() and not game.npc_talk.is_open()
		and dc.notice.visible)
	dc.notice.confirm()
	var ok := await _until(func() -> bool: return main.flow.is_in(ShellFlow.State.PLAYING) and bool(session.call("is_idle")))
	var pc := main.game_session.player as PlayerController
	_check("dialogue death: after the respawn no modal is left and the player has input", ok and not c.is_modal_active()
		and not game.npc_talk.is_open() and pc.is_input_enabled())
	_check("dialogue death: Esc opens the pause menu", main.handle_menu_action() and main.flow.is_in(ShellFlow.State.PAUSED))
	main.resume()


## ShellFlow allows PAUSED --died--> DEAD. No gameplay path kills a paused player today (the world is paused), but a
## death announced then must not leave the tree paused under the menu, with Resume and Quit to Title refused in DEAD:
## the menu closes and the tree unpauses before the notice opens, and OK respawns as usual.
func _death_while_paused(game: GameState, session: Node) -> void:
	await _until(func() -> bool: return bool(session.call("is_idle")) and main.game_session.player.is_on_floor())
	var map_id := String(session.get("current_map"))
	_check("paused death: paused", main.pause() and main.flow.is_in(ShellFlow.State.PAUSED) and get_tree().paused)
	get_node("/root/Events").emit_signal("player_died", map_id)
	await _frames(3)
	var dc := main.game_session.death
	_check("paused death: the menu closed and the world runs again", not main.pause_menu.visible
		and not get_tree().paused and not game.paused, "menu %s tree paused %s" % [main.pause_menu.visible, get_tree().paused])
	_check("paused death: dead, the notice up as a modal", main.flow.is_in(ShellFlow.State.DEAD) and dc.is_dead()
		and dc.notice.visible and main.ctx().is_modal_active() and String(session.call("state_name")) == "DEAD",
		"flow %s session %s" % [ShellFlow.state_name(main.flow.state), session.call("state_name")])
	dc.notice.confirm()
	var respawned := func() -> bool:
		return main.flow.is_in(ShellFlow.State.PLAYING) and bool(session.call("is_idle")) and not dc.is_dead()
	var ok := await _until(respawned)
	_check("paused death: respawned, no modal left, input on", ok and not main.ctx().is_modal_active()
		and (main.game_session.player as PlayerController).is_input_enabled())


## A load out of DEAD (the debug console's "load", the death screen's only load) ends the death without a respawn:
## the shell must leave DEAD, or Esc and Quit to Title stay refused for the rest of the session. The slot it loads
## was written at the death, so the loaded character is in the return town with the penalty taken once.
func _load_out_of_death(game: GameState, session: Node) -> void:
	await _until(func() -> bool: return bool(session.call("is_idle")) and main.game_session.player.is_on_floor())
	var db := get_node("/root/Data").get("db") as ContentDB
	var map_id := String(session.get("current_map"))
	var town := String(db.map(map_id).get("return_map_id", ""))
	var c := game.character
	var exp_before := c.exp
	var loss := Progression.death_exp_loss(c.level, c.get_base_stat("luk"), db)
	game.change_hp(-c.hp)
	await _frames(3)
	_check("console load while dead: dead first", main.flow.is_in(ShellFlow.State.DEAD))
	var exp_at_death := game.character.exp
	var hp_at_death := game.character.hp
	var out := String(get_node("/root/Debug").call("run", "load"))
	var ok := await _until(func() -> bool: return bool(session.call("is_idle")) and not main.game_session.death.is_dead())
	await _frames(3)
	_check("console load while dead: the shell leaves DEAD", ok and main.flow.is_in(ShellFlow.State.PLAYING), "%s; flow %s" % [
		out, ShellFlow.state_name(main.flow.state)])
	c = game.character
	_check("console load while dead: the save of the death (penalty once, in %s, alive)" % town,
		c.exp == maxi(0, exp_before - loss) and c.exp == exp_at_death and c.hp == hp_at_death and c.hp > 0
		and String(session.get("current_map")) == town and not (main.game_session.player as PlayerController).is_dead(),
		"exp %d (before %d, loss %d) hp %d map %s" % [c.exp, exp_before, loss, c.hp, session.get("current_map")])
	_check("console load while dead: no modal, notice hidden", not main.ctx().is_modal_active()
		and not main.game_session.death.notice.visible)
	_check("console load while dead: Esc opens the pause menu", main.handle_menu_action() and main.flow.is_in(ShellFlow.State.PAUSED))
	main.resume()
	await _quit_while_dead(game, session)


## Closing the window while dead (before OK): the window-close notification goes through the whole tree as it does
## when the OS closes the window (Game first, then the shell). The save written at the death already holds it, and
## the saves on close keep it: the canonical EXP penalty once, death.json HP, the respawn point of the returnMap.
## (test_death_quit_reload.gd does the real thing: the process exits and the next one continues.)
func _quit_while_dead(game: GameState, session: Node) -> void:
	var db := get_node("/root/Data").get("db") as ContentDB
	var saves := get_node("/root/Saves")
	var map_id := "000000040"
	session.call("debug_warp", map_id)
	await _until(func() -> bool: return bool(session.call("is_idle")) and main.game_session.player.is_on_floor())
	game.gain_exp(5)
	_check("quit while dead: a save before the death", game.save_game() == OK)
	var c := game.character
	var exp_before := c.exp
	var loss := Progression.death_exp_loss(c.level, c.get_base_stat("luk"), db)
	game.change_hp(-c.hp)
	await _frames(3)
	_check("quit while dead: dead", main.flow.is_in(ShellFlow.State.DEAD))
	var to := String(db.map(map_id).get("return_map_id", ""))
	var r: SaveLoadResult = saves.call("read_save", game.current_slot)
	_check("quit while dead: the save at the death holds the penalty", r.ok() and r.character.exp == maxi(0, exp_before - loss)
		and String(r.character.location.get("map_id", "")) == to, "%d -> %d (loss %d)" % [exp_before,
		r.character.exp if r.ok() else -1, loss])
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	r = saves.call("read_save", game.current_slot)
	_check("quit while dead: after the close the save holds the penalty once", r.ok()
		and r.character.exp == maxi(0, exp_before - loss), "%d -> %d (loss %d)" % [exp_before,
		r.character.exp if r.ok() else -1, loss])
	_check("quit while dead: saved at the returnMap's respawn point with HP above 0", r.ok()
		and String(r.character.location.get("map_id", "")) == to and r.character.hp > 0, str(r.character.location if r.ok() else {}))
	_check("quit while dead: the shell is quitting", main.flow.is_in(ShellFlow.State.QUITTING))


# --- Test F as a real quit: a chain of processes ------------------------------------------------------------------

## One link of the death -> quit -> reload chain (see the header). The death of each link is verified by the next.
func _death_quit() -> void:
	var game := get_node("/root/Game") as GameState
	var session := get_node("/root/MapSession")
	var saves := get_node("/root/Saves")
	var db := get_node("/root/Data").get("db") as ContentDB
	var expect := _read_expect()
	if expect.is_empty():
		main.start_new_game({"name": "Phoenix", "gender": "female", "ap": {"str": 9}, "weapon_id": "585"})
		if not await _until_playing("new game"):
			return
		game.gain_exp(10)
		var accepted := game.quests.accept(TEST_F_QUEST)
		_check("quest %s accepted" % TEST_F_QUEST, bool(accepted.get("ok", false)), str(accepted.get("reason", "")))
		var potion := _item_named(db, TEST_F_ITEM_NAME)
		_check("potions added", potion != "" and game.character.inventory.add(potion, 3, db) == 3, potion)
		game.change_mp(-2)
		_check("a save before the death", game.save_game() == OK)
	elif not await _verify_reload(expect):
		return
	var map_id := map_arg
	var err: Error = session.call("debug_warp", map_id)
	_check("%s: warp" % map_id, err == OK, String(session.get("last_error")))
	await _until(func() -> bool: return bool(session.call("is_idle")) and main.game_session.player.is_on_floor())
	await _physics(5)
	var c := game.character
	var town := String(db.map(map_id).get("return_map_id", ""))
	var loss := Progression.death_exp_loss(c.level, c.get_base_stat("luk"), db)
	var vit := DeathRules.from_db(db).respawn_vitals()
	var next := {"slot": game.current_slot, "died_in": map_id, "town": town, "exp_before": c.exp, "loss": loss,
		"spawn_index": (session.call("get_defs") as MapDefinitions).tuning.respawn_spawn_index(),
		"level": c.level, "exp": maxi(0, c.exp - loss),
		"hp": maxi(1, DeathRules.vital_value(vit["hp"], 0, StatCalculator.max_hp(c, db))),
		"mp": DeathRules.vital_value(vit["mp"], c.mp, StatCalculator.max_mp(c, db)),
		"keep": {"inventory": c.inventory.to_dict(), "equipment": c.equipment.to_dict(), "quests": c.quests.to_dict()}}
	_check("%s: this death costs EXP" % map_id, loss > 0 and c.exp > 0, "exp %d loss %d" % [c.exp, loss])
	game.change_hp(-c.hp)
	await _frames(3)
	_check("%s: dead and committed" % map_id, main.flow.is_in(ShellFlow.State.DEAD) and main.game_session.death.is_dead()
		and bool(session.call("is_death_committed")), String(session.call("state_name")))
	_check("%s: the loss taken at the death" % map_id, c.exp == int(next["exp"]) and c.hp == int(next["hp"])
		and c.mp == int(next["mp"]), "exp %d hp %d mp %d, want %s" % [c.exp, c.hp, c.mp, [next["exp"], next["hp"], next["mp"]]])
	var r: SaveLoadResult = saves.call("read_save", game.current_slot)
	_check("%s: saved at the death, in %s" % [map_id, town], r.ok() and r.character.exp == int(next["exp"])
		and String(r.character.location.get("map_id", "")) == town, str(r.character.location) if r.ok() else r.message)
	_write_expect(next)
	# The window closes: the notification goes through the whole tree as when the OS closes it (Game first, as an
	# autoload, then the shell). The process exits after this; the next link continues.
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	r = saves.call("read_save", String(next["slot"]))
	_check("%s: after the close the save holds the loss once" % map_id, r.ok() and r.character.exp == int(next["exp"])
		and r.character.hp == int(next["hp"]) and String(r.character.location.get("map_id", "")) == town,
		("exp %d hp %d at %s" % [r.character.exp, r.character.hp, r.character.location]) if r.ok() else r.message)
	_check("%s: the shell is quitting" % map_id, main.flow.is_in(ShellFlow.State.QUITTING))


## The last link: Continue and verify the previous link's death.
func _death_reload() -> void:
	var expect := _read_expect()
	_check("the previous link left its expectations", not expect.is_empty(), save_dir.path_join(EXPECT_FILE))
	if expect.is_empty():
		return
	if await _verify_reload(expect):
		_check("quit to title after the reload", main.quit_to_title() == OK)
		await _frames(2)


## A fresh process continues from the save the previous one quit with while dead: the return town at the respawn
## spawn (entry, no resume), the EXP penalty exactly once, death.json HP/MP, inventory, equipment and quests intact,
## alive and playing, and still so once the death watch has been armed for a while.
func _verify_reload(expect: Dictionary) -> bool:
	var game := get_node("/root/Game") as GameState
	var session := get_node("/root/MapSession")
	var died := String(expect["died_in"])
	var town := String(expect["town"])
	_check("%s: Continue offered" % died, main.title.continue_button.visible
		and main.title.continue_slot == String(expect["slot"]), main.title.continue_slot)
	main.continue_game()
	if not await _until_playing("%s: reload" % died):
		return false
	var p := main.game_session.player as PlayerController
	await _until(func() -> bool: return p.is_on_floor(), 120)
	var def: MapDefinition = (session.call("get_defs") as MapDefinitions).get_def(town)
	var spawn := def.player_spawn(int(expect["spawn_index"])).origin if def != null else Vector3.INF
	var rec := session.get("last_transition") as TransitionRecord
	_check("%s: reloaded in the return town %s" % [died, town], String(session.get("current_map")) == town,
		String(session.get("current_map")))
	_check("%s: at the respawn spawn %d (entry, no resume)" % [died, int(expect["spawn_index"])], rec != null
		and rec.load_step == ArrivalResolver.STEP_ENTRY and rec.from_map == "" and _flat(p.global_position - spawn) < 0.3,
		"%s at %s, spawn %s" % [rec.load_step if rec != null else "?", p.global_position, spawn])
	var c := game.character
	_check("%s: the EXP penalty taken exactly once" % died, c.exp == int(expect["exp"]) and c.level == int(expect["level"]),
		"exp %d, want %d (before %d, loss %d)" % [c.exp, int(expect["exp"]), int(expect["exp_before"]), int(expect["loss"])])
	_check("%s: HP/MP per death.json" % died, c.hp == int(expect["hp"]) and c.mp == int(expect["mp"]),
		"hp %d mp %d, want %d %d" % [c.hp, c.mp, int(expect["hp"]), int(expect["mp"])])
	var keep: Dictionary = expect["keep"]
	var now := {"inventory": c.inventory.to_dict(), "equipment": c.equipment.to_dict(), "quests": c.quests.to_dict()}
	for k: String in ["inventory", "equipment", "quests"]:
		var d := _diff(keep.get(k, {}), now[k])
		_check("%s: %s intact" % [died, k], d == "", d)
	_check("%s: quest %s still in progress" % [died, TEST_F_QUEST], c.quests.status(TEST_F_QUEST) == QuestLog.IN_PROGRESS)
	var dc := main.game_session.death
	_check("%s: alive and playing" % died, main.flow.is_in(ShellFlow.State.PLAYING) and bool(session.call("is_idle"))
		and not dc.is_dead() and not p.is_dead() and p.is_input_enabled() and not main.ctx().is_modal_active())
	await _physics(30)
	_check("%s: still once with the death watch armed" % died, dc.armed and c.exp == int(expect["exp"]) and not dc.is_dead()
		and main.flow.is_in(ShellFlow.State.PLAYING))
	return true


func _until_playing(label: String) -> bool:
	var ok := await _until(func() -> bool: return not main.flow.is_in(ShellFlow.State.LOADING))
	_check("%s reaches PLAYING" % label, ok and main.flow.is_in(ShellFlow.State.PLAYING), main.last_error_message)
	return main.flow.is_in(ShellFlow.State.PLAYING)


func _read_expect() -> Dictionary:
	var path := save_dir.path_join(EXPECT_FILE)
	if not FileAccess.file_exists(path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


func _write_expect(d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var f := FileAccess.open(save_dir.path_join(EXPECT_FILE), FileAccess.WRITE)
	if f == null:
		_check("write the expectations", false, error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(d))
	f.close()


# --- screenshots ------------------------------------------------------------------------------------------------

func _shots() -> void:
	if DisplayServer.get_name() == "headless":
		_check("shots need a window", false, "run without --headless")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("user://") or out_dir.begins_with("res://") else out_dir)
	await _frames(20)
	await _shot("title")
	main.open_creation()
	var model := main.creation.model
	model.name = "Maple"
	model.gender = "female"
	model.clear_ap()
	model.add_ap("str", 6)
	model.add_ap("dex", 3)
	model.weapon_id = "541"
	main.creation.refresh()
	await _frames(10)
	await _shot("creation")
	# A tooltip is a popup window of its own: it wears MisoTheme only through the root window's theme.
	var rec := _find_button(main.creation, "Recommended")
	if rec != null and rec.tooltip_text != "":
		var at := rec.get_global_rect().get_center()
		get_viewport().warp_mouse(at)
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		get_viewport().push_input(motion)
		await _seconds(1.5)
		await _shot("creation_tooltip")
	main.creation.submit()
	await _until(func() -> bool: return not main.flow.is_in(ShellFlow.State.LOADING))
	if not main.flow.is_in(ShellFlow.State.PLAYING):
		_check("game started", false, main.last_error_message)
		return
	await _seconds(2.0)
	await _shot("game")
	(get_node("/root/Game") as GameState).change_hp(-9999)
	await _seconds(0.8)
	await _shot("death_notice")
	main.game_session.death.notice.confirm()
	await _until(func() -> bool: return main.flow.is_in(ShellFlow.State.PLAYING))
	await _seconds(1.0)
	main.pause()
	await _frames(5)
	await _shot("pause_menu")
	main.pause_menu.show_controls()
	await _frames(5)
	await _shot("pause_controls")
	main.pause_menu.show_main()
	main.quit_to_title()
	await _frames(20)
	main.title.show_slots()
	await _frames(5)
	await _shot("title_load")


func _shot_if_windowed(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await _shot(label)


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_shot_index += 1
	var path := out_dir.path_join("%02d_%s.png" % [_shot_index, label])
	var err := img.save_png(path)
	print("SHELL_SHOT %s %s" % [ProjectSettings.globalize_path(path), error_string(err)])


# --- helpers ----------------------------------------------------------------------------------------------------

func _check(check_name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("SHELL_CHECK PASS %s" % check_name)
	else:
		failed += 1
		print("SHELL_CHECK FAIL %s%s" % [check_name, (": " + detail) if detail != "" else ""])


func _info(text: String) -> void:
	print("SHELL_INFO " + text)


## Waits until `cond` holds: `max_frames` frames, and a default wait at least CheckWait.DEFAULT_MIN_MS of wall time
## (a headless frame can take under a millisecond; CheckWait).
func _until(cond: Callable, max_frames: int = TIMEOUT_FRAMES) -> bool:
	var n := 0
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()) and CheckWait.keep_waiting(n, max_frames, Time.get_ticks_msec() - t0):
		await get_tree().process_frame
		n += 1
	return bool(cond.call())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


## A real key press and release (keycode and physical_keycode, like the keyboard), one frame apart. Await it.
func _tap_key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await get_tree().process_frame


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## to_dict() without the fields that legitimately change between two moments (play time, the live location).
static func _comparable(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	out.erase("play_time_s")
	out.erase("location")
	return out


## "" when equal; numbers compare with tolerance (a save turns integral floats into ints).
static func _diff(a: Variant, b: Variant, path: String = "$") -> String:
	var a_num := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var b_num := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if a_num and b_num:
		return "" if is_equal_approx(float(a), float(b)) else "%s: %s != %s" % [path, str(a), str(b)]
	if typeof(a) != typeof(b):
		return "%s: %s != %s" % [path, str(a), str(b)]
	if a is Dictionary:
		for k in a:
			if not (b as Dictionary).has(k):
				return "%s.%s missing" % [path, str(k)]
			var d := _diff(a[k], b[k], "%s.%s" % [path, str(k)])
			if d != "":
				return d
		for k in b:
			if not (a as Dictionary).has(k):
				return "%s.%s appeared" % [path, str(k)]
		return ""
	if a is Array:
		if (a as Array).size() != (b as Array).size():
			return "%s: size %d != %d" % [path, (a as Array).size(), (b as Array).size()]
		for i in (a as Array).size():
			var d := _diff(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s != %s" % [path, str(a), str(b)]


## The HUD's HP and EXP gauges ({"hp", "exp"}: the values they show), found by shape under the session's ui_root
## (the HUD is another system's scene: no class reference, so these checks still compile without it); {} without one.
func _hud_gauges() -> Dictionary:
	var c := main.ctx()
	if c == null or c.ui_root == null:
		return {}
	for n in c.ui_root.find_children("*", "", true, false):
		var status: Variant = n.get("status")
		if status is Object and (status as Object).get("hp_gauge") is Object and (status as Object).get("exp_gauge") is Object:
			return {"hp": int(((status as Object).get("hp_gauge") as Object).get("current")),
				"exp": int(((status as Object).get("exp_gauge") as Object).get("current"))}
	return {}


static func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var b := _find_button(child, text)
		if b != null:
			return b
	return null


static func _item_named(db: ContentDB, item_name: String) -> String:
	var items := db.domain("items")
	for id in items:
		if String((items[id] as Dictionary).get("name", "")) == item_name:
			return String(id)
	return ""


static func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var i := args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)
