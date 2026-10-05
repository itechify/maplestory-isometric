extends TestCase
## The game shell's boot/screen state machine (ShellFlow, pure) and the save-slot helpers behind Continue and New
## Game (SaveSlotIndex). The flow with real screens and frames is test_shell_acceptance.gd.

const S := ShellFlow.State


func _flow_at(events: Array) -> ShellFlow:
	var f := ShellFlow.new()
	for e: String in events:
		assert_true(f.fire(e), "setup event %s from %s" % [e, ShellFlow.state_name(f.state)])
	return f


func test_boot_goes_to_the_title() -> void:
	var f := ShellFlow.new()
	assert_eq(f.state, S.BOOT, "starts in BOOT")
	assert_false(f.fire(ShellFlow.EV_NEW_GAME), "nothing but boot in BOOT")
	assert_eq(f.state, S.BOOT, "refused events change nothing")
	assert_eq(f.last_refused, ShellFlow.EV_NEW_GAME, "the refusal is recorded")
	assert_true(f.fire(ShellFlow.EV_BOOT), "boot")
	assert_eq(f.state, S.TITLE, "title")


func test_new_game_path() -> void:
	var f := _flow_at([ShellFlow.EV_BOOT])
	assert_true(f.fire(ShellFlow.EV_NEW_GAME), "New Game")
	assert_eq(f.state, S.CREATE, "creation screen")
	assert_true(f.fire(ShellFlow.EV_BACK), "Back")
	assert_eq(f.state, S.TITLE, "back to the title")
	f.fire(ShellFlow.EV_NEW_GAME)
	assert_true(f.fire(ShellFlow.EV_START), "Start")
	assert_eq(f.state, S.LOADING, "loading")
	assert_true(f.fire(ShellFlow.EV_READY), "world ready")
	assert_eq(f.state, S.PLAYING, "playing")
	assert_true(f.in_game(), "in game")


func test_continue_load_and_quick_start_from_the_title() -> void:
	for e in [ShellFlow.EV_CONTINUE, ShellFlow.EV_LOAD, ShellFlow.EV_START]:
		var f := _flow_at([ShellFlow.EV_BOOT])
		assert_true(f.fire(e), "%s from the title" % e)
		assert_eq(f.state, S.LOADING, "%s loads" % e)


func test_a_failed_start_returns_to_the_title() -> void:
	var f := _flow_at([ShellFlow.EV_BOOT, ShellFlow.EV_CONTINUE])
	assert_true(f.fire(ShellFlow.EV_FAILED), "failed")
	assert_eq(f.state, S.TITLE, "title again")
	assert_false(f.in_game(), "not in game")


func test_pause_resume_load_and_quit_to_title() -> void:
	var f := _flow_at([ShellFlow.EV_BOOT, ShellFlow.EV_CONTINUE, ShellFlow.EV_READY])
	assert_true(f.fire(ShellFlow.EV_PAUSE), "pause")
	assert_eq(f.state, S.PAUSED, "paused")
	assert_false(f.fire(ShellFlow.EV_PAUSE), "cannot pause twice")
	assert_true(f.fire(ShellFlow.EV_RESUME), "resume")
	assert_eq(f.state, S.PLAYING, "playing")
	f.fire(ShellFlow.EV_PAUSE)
	assert_true(f.fire(ShellFlow.EV_LOAD), "load in the pause menu")
	assert_eq(f.state, S.PLAYING, "a load in place keeps playing")
	f.fire(ShellFlow.EV_PAUSE)
	assert_true(f.fire(ShellFlow.EV_QUIT_TO_TITLE), "quit to title")
	assert_eq(f.state, S.TITLE, "title")
	var g := _flow_at([ShellFlow.EV_BOOT, ShellFlow.EV_CONTINUE, ShellFlow.EV_READY])
	assert_true(g.fire(ShellFlow.EV_QUIT_TO_TITLE), "quit to title straight from play")


func test_death_and_respawn() -> void:
	var f := _flow_at([ShellFlow.EV_BOOT, ShellFlow.EV_START, ShellFlow.EV_READY])
	assert_true(f.fire(ShellFlow.EV_DIED), "died")
	assert_eq(f.state, S.DEAD, "dead")
	for e in [ShellFlow.EV_PAUSE, ShellFlow.EV_QUIT_TO_TITLE, ShellFlow.EV_LOAD, ShellFlow.EV_RESUME]:
		assert_false(f.can(e), "%s refused while dead" % e)
	assert_true(f.fire(ShellFlow.EV_RESPAWNED), "respawned")
	assert_eq(f.state, S.PLAYING, "playing again")


func test_quit_is_accepted_everywhere_once() -> void:
	for events: Array in [[], [ShellFlow.EV_BOOT], [ShellFlow.EV_BOOT, ShellFlow.EV_NEW_GAME],
			[ShellFlow.EV_BOOT, ShellFlow.EV_CONTINUE, ShellFlow.EV_READY, ShellFlow.EV_DIED]]:
		var f := _flow_at(events)
		assert_true(f.fire(ShellFlow.EV_QUIT), "quit from %s" % ShellFlow.state_name(f.state))
		assert_eq(f.state, S.QUITTING, "quitting")
		assert_false(f.fire(ShellFlow.EV_QUIT), "only once")


func test_changed_signal_and_history() -> void:
	var f := ShellFlow.new()
	var seen: Array = []
	f.changed.connect(func(n: int, o: int, e: String) -> void: seen.append([o, n, e]))
	f.fire(ShellFlow.EV_BOOT)
	f.fire(ShellFlow.EV_NEW_GAME)
	assert_eq(seen, [[S.BOOT, S.TITLE, "boot"], [S.TITLE, S.CREATE, "new_game"]], "changed(new, old, event)")
	assert_eq(f.history.size(), 2, "history")
	assert_eq(f.history[1], {"event": "new_game", "from": "TITLE", "to": "CREATE"}, "history entry")


func test_every_table_target_is_a_state() -> void:
	for from: int in ShellFlow.TRANSITIONS:
		for e: String in ShellFlow.TRANSITIONS[from]:
			var to: int = ShellFlow.TRANSITIONS[from][e]
			assert_true(to >= 0 and to < S.size(), "%s --%s--> valid" % [ShellFlow.state_name(from), e])
	# Every state but QUITTING has a way out.
	for s: int in S.values():
		if s != S.QUITTING:
			assert_false((ShellFlow.TRANSITIONS[s] as Dictionary).is_empty(), "%s has transitions" % ShellFlow.state_name(s))


# --- SaveSlotIndex ----------------------------------------------------------------------------------------------

func _entry(slot: String, ok: bool, t: int) -> Dictionary:
	return {"slot": slot, "ok": ok, "modified_unix": t, "meta": {"name": slot}}


func test_continue_is_the_newest_loadable_slot() -> void:
	assert_eq(SaveSlotIndex.continue_slot([]), "", "no saves, no Continue")
	var entries := [_entry("slot1", true, 100), _entry("slot2", true, 300), _entry("slot3", false, 900)]
	assert_eq(SaveSlotIndex.continue_slot(entries), "slot2", "newest loadable (an unreadable save is skipped)")
	assert_eq(SaveSlotIndex.continue_slot([_entry("b", true, 5), _entry("a", true, 5)]), "a", "ties by name")
	assert_true(SaveSlotIndex.is_loadable(entries, "slot1"), "loadable")
	assert_false(SaveSlotIndex.is_loadable(entries, "slot3"), "unreadable")
	assert_eq(SaveSlotIndex.entry(entries, "slot2")["modified_unix"], 300, "entry")
	assert_eq(SaveSlotIndex.entry(entries, "nope"), {}, "missing entry")


func test_new_games_never_reuse_a_slot() -> void:
	assert_eq(SaveSlotIndex.next_free_slot([]), "slot1", "first slot")
	assert_eq(SaveSlotIndex.next_free_slot([_entry("slot1", true, 1), _entry("slot3", false, 1)]), "slot2", "gap")
	assert_eq(SaveSlotIndex.next_free_slot([_entry("slot1", true, 1), _entry("slot2", false, 1)]), "slot3",
		"an unreadable save still occupies its slot")
	assert_true(SaveStore.is_valid_slot(SaveSlotIndex.next_free_slot([])), "a valid slot name")
