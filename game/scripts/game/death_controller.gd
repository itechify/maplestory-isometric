class_name DeathController
extends Node
## Phase 9 death and respawn (MAP_ARCHITECTURE.md section 4.8), owned by the game shell. Classic MapleStory takes a
## death's loss when the character dies, not when the player answers the prompt, so the death is committed and saved
## at once: quitting while dead never dodges the penalty, and a reload starts in the return town.
##
##   1. HP reaches 0: Events.hp_changed with Progression.is_dead(character) (Game.change_hp / damage_player emit
##      it), or another system announces Events.player_died. kill(): player.die(), then MapSession.enter_dead(). In
##      the game the HP watch kills one idle step later (deferred), so a system that announces the death itself
##      right after its hp_changed (MonsterSystem's ContactDamage.announce_death) goes first and Events.player_died
##      is emitted once, not twice.
##   2. MapSession enters DEAD and calls its death_commit hook, which is commit_rules(): DeathRules (the canonical EXP
##      penalty, death.json's HP/MP for the respawn) on the live character, once per death. MapSession then moves the
##      character's location to the respawn point (the canonical returnMap's player_spawns[death.json
##      respawn_player_spawn_index]) and emits death_committed; this controller saves the game right there
##      (Game.save_game: MapSession allows saving while DEAD once the death is committed).
##   3. Events.player_died: a modal conversation, shop or console still open is closed (it would hold the keyboard
##      over the notice and survive the respawn), then the DeathNotice opens as a modal ("You have died. Return to
##      the nearest town?"). Once the death is both committed and announced, Events.exp_gained(-exp_lost, "death")
##      lets the HUD's EXP bar drop at the death; its HP gauge keeps the killing blow's 0 until the respawn.
##   4. OK (confirm()): once MapSession is DEAD (a death during a warp enters DEAD, and commits, when the warp ends),
##      MapSession.respawn() warps to the returnMap. OK changes nothing else: the loss was taken at the death. The
##      notice hides as the warp starts (the modal stays until the end). Nothing blocks or awaits: signals carry it.
##   5. When the warp is done: player.revive(), the modal is released (input comes back), the refresh signals fire,
##      and the game is saved again (now with the town's resume point).
##   A load (or a new game) out of DEAD ends the death without a respawn: death_cleared. Quitting while dead needs
##   nothing for a committed death (the save at the death holds it); commit_death_for_quit() covers the one death
##   that is not committed yet (it happened during a warp and the game closes before that warp ends).
##
## Collaborators are injected (configure()) so tests drive it with a private MapSession, GameState and bus; in the
## game GameSession wires the autoloads. Everything works with a null player or context.

signal died(map_id: String)
signal respawned(map_id: String, report: Dictionary)
## The death ended without a respawn: a load or a new game out of DEAD (MapSession emits player_respawned for it).
signal death_cleared(map_id: String)
## The respawn could not start (MapSession refused it); the notice stays open so OK can be pressed again.
signal respawn_failed(error: Error)
## MapSession committed this death (the loss is taken) and the save at the death ran: `report` is last_report.
signal committed(map_id: String, report: Dictionary)

## Upper bound on the windows closed at a death (close_top_window() pops one per call; this only guards a window
## that re-registers itself while closing).
const MAX_WINDOWS_CLOSED_AT_DEATH := 32
## Events.exp_gained source of the death's EXP loss (amount = -exp_lost): the HUD redraws its EXP bar at the death.
const EXP_LOSS_SOURCE := "death"

## MapSession (or a private instance): state_name(), enter_dead(), respawn(), is_idle(), death_commit,
## death_committed, is_death_committed(), commit_death(), respawn_location(), respawn_reference_of(), state_changed,
## transition_finished, current_map.
var session: Node = null
## GameState (or a private instance): character, save_game(), save_as_is(), has_active_game().
var game: Node = null
## The Events bus (or a private events.gd).
var bus: Node = null
var db: ContentDB = null
var player: Node = null
var ctx: GameContext = null
## Parent for the DeathNotice (a CanvasLayer in the game); null = no notice UI (tests call confirm() directly).
var notice_parent: Node = null
var rules: DeathRules = null
## The HP watch acts only while armed (the shell arms it once the session is playing; loading emits hp_changed).
var armed: bool = false
## Save when the death is committed (the brief: quitting while dead must not dodge the loss).
var save_on_commit: bool = true
## Save after every respawn (the town's resume point; the brief: the death must leave a valid save).
var save_after_respawn: bool = true

var notice: DeathNotice = null
## The last death: DeathRules' report ("applied", "exp_before", "exp_lost", "hp", "mp", ...) plus "map_id" (died
## in), "death_save_error" (the save at the death), "returned_to" and "save_error" (the save after the respawn).
var last_report: Dictionary = {}
## The map the player died in ("" while alive).
var died_in: String = ""

var _dead := false
var _respawning := false
var _awaiting_dead := false
## A deferred kill from the HP watch is pending.
var _kill_queued := false
## This death's rules have run (commit_rules). Set by the first commit of a death, cleared when the death ends (the
## respawn is done, a load ended it, detach). It keeps the penalty to one per death whatever the order of the hook,
## the quit fallback and the respawn.
var _committed := false
## This death's EXP loss was announced (Events.exp_gained(-exp_lost, "death")); cleared with _committed.
var _loss_shown := false
var _connected := false
var _hooked := false


func configure(p_session: Node, p_game: Node, p_bus: Node, p_db: ContentDB, p_player: Node = null,
		p_ctx: GameContext = null, p_notice_parent: Node = null) -> void:
	session = p_session
	game = p_game
	bus = p_bus
	db = p_db
	player = p_player
	ctx = p_ctx
	notice_parent = p_notice_parent
	if rules == null:
		rules = DeathRules.from_db(db)
		for e in rules.errors:
			push_error("[DeathController] " + e)


## Connects the bus and installs commit_rules as MapSession's death_commit hook (the loss at the moment of death).
## Attached while MapSession is already DEAD without a commit, it commits that death now.
func attach() -> void:
	if bus != null and not _connected:
		bus.connect(&"hp_changed", _on_hp_changed)
		bus.connect(&"player_died", _on_player_died)
		bus.connect(&"player_respawned", _on_player_respawned)
		_connected = true
	if session != null and rules != null and not _hooked:
		session.set(&"death_commit", Callable(self, &"commit_rules"))
		if session.has_signal(&"death_committed") and not session.is_connected(&"death_committed", _on_death_committed):
			session.connect(&"death_committed", _on_death_committed)
		_hooked = true
		if _session_dead() and session.has_method("is_death_committed") and not bool(session.call("is_death_committed")):
			session.call("commit_death")


## Undoes attach() (the shell calls it before the session is torn down).
func detach() -> void:
	if bus != null and _connected:
		for pair in [[&"hp_changed", _on_hp_changed], [&"player_died", _on_player_died],
				[&"player_respawned", _on_player_respawned]]:
			if bus.is_connected(pair[0], pair[1]):
				bus.disconnect(pair[0], pair[1])
		_connected = false
	_stop_waiting()
	if session != null and is_instance_valid(session):
		if session.is_connected(&"transition_finished", _on_respawn_finished):
			session.disconnect(&"transition_finished", _on_respawn_finished)
		if session.has_signal(&"death_committed") and session.is_connected(&"death_committed", _on_death_committed):
			session.disconnect(&"death_committed", _on_death_committed)
		if _hooked:
			var hook: Variant = session.get(&"death_commit")
			if hook is Callable and (hook as Callable).get_object() == self:
				session.set(&"death_commit", Callable())
	_hooked = false
	_committed = false
	_loss_shown = false
	_close_notice()


func _exit_tree() -> void:
	detach()


func is_dead() -> bool:
	return _dead


func is_respawning() -> bool:
	return _respawning


## True once this death's loss has been taken (commit_rules ran for it); false again when the death ends.
func is_committed() -> bool:
	return _committed


## The player dies now: player.die(), then MapSession.enter_dead() (which commits the death and announces
## Events.player_died).
func kill() -> Error:
	if _dead:
		return ERR_ALREADY_IN_USE
	if player != null and player.has_method("die"):
		player.call("die")
	if session == null:
		return ERR_UNCONFIGURED
	var err: Error = session.call("enter_dead")
	if err != OK:
		push_warning("[DeathController] MapSession refused enter_dead (%s, state %s)" % [error_string(err),
			session.call("state_name") if session.has_method("state_name") else "?"])
	return err


## MapSession's death_commit hook: the death rules (the canonical EXP penalty, death.json's HP/MP for the respawn)
## applied to the character at the moment of death, in death.json's order. Once per death: a second call for the same
## death (the quit fallback ran first, the hook fires again) changes nothing and returns the first report.
func commit_rules(c: CharacterState) -> Dictionary:
	if _committed:
		return last_report
	_committed = true
	var report: Dictionary = rules.apply(c) if rules != null and c != null else {}
	last_report = report.duplicate(true)
	last_report["map_id"] = String(session.get(&"current_map")) if session != null else ""
	return last_report


## OK on the death notice: the respawn warp to the return map, then revive and save. The loss was taken at the
## death, so OK applies nothing. Never blocks: returns OK once the respawn has started or is queued, and `respawned`
## fires when the player stands in town. A death during a warp is announced at once, but MapSession enters DEAD (and
## commits) only when that warp completes; OK then queues the respawn until MapSession reports DEAD.
func confirm() -> Error:
	if not _dead:
		return ERR_UNAVAILABLE
	if _respawning or _awaiting_dead:
		return ERR_BUSY
	if _session_dead():
		return _respawn_now()
	if _session_busy():
		_awaiting_dead = true
		if not session.is_connected(&"state_changed", _on_session_state):
			session.connect(&"state_changed", _on_session_state)
		return OK
	push_warning("[DeathController] cannot respawn: MapSession is %s, not DEAD" % session.call("state_name"))
	respawn_failed.emit(ERR_UNAVAILABLE)
	return ERR_UNAVAILABLE


## True while OK waits for MapSession to finish the warp the player died in.
func is_waiting_for_session() -> bool:
	return _awaiting_dead


## The game is closing while the player is dead. A committed death was saved at the death (and Game saves it again on
## the window's close notification), so this only saves once more. The one death that is not committed yet happened
## during a warp: MapSession enters DEAD, and commits, only when that warp ends, and refuses to save until then. For
## it the rules run here (through commit_rules, so never twice) and the character is written with Game.save_as_is()
## at the respawn location of MapSession's current map, where MapSession's own commit would have put it. Returns the
## save error; ERR_UNAVAILABLE when the player is not dead or nothing can be saved.
func commit_death_for_quit() -> Error:
	if not _dead or game == null or not bool(game.call("has_active_game")) or session == null:
		return ERR_UNAVAILABLE
	if bool(session.call("is_death_committed")):
		return game.call("save_game", "")
	var c: Variant = game.get(&"character")
	if not (c is CharacterState):
		return ERR_UNAVAILABLE
	var loc: Dictionary = session.call("respawn_location", "")
	if loc.is_empty():
		return ERR_UNAVAILABLE
	commit_rules(c)
	(c as CharacterState).location = loc.duplicate(true)
	(c as CharacterState).respawn_reference = String(session.call("respawn_reference_of", String(loc["map_id"])))
	var err: Error = game.call("save_as_is", "")
	last_report["death_save_error"] = err
	if err != OK:
		push_warning("[DeathController] could not commit the death on quit: %s" % error_string(err))
	return err


func _respawn_now() -> Error:
	_respawning = true
	if not _committed and game != null and game.get(&"character") is CharacterState:
		# MapSession entered DEAD without the hook installed: take the loss now, still once.
		commit_rules(game.get(&"character"))
	var err: Error = session.call("respawn")
	if err != OK:
		_respawning = false
		if notice != null:
			notice.open(_return_text(died_in))
		respawn_failed.emit(err)
		return err
	# The notice goes as the screen fades out; otherwise it would sit over the town during the fade-in (the fader
	# draws above the notice layer). The modal stays until _finish(): MapSession holds the input until then anyway.
	if notice != null and is_instance_valid(notice):
		notice.hide()
	_announce_vitals()
	if bool(session.call("is_idle")):
		_finish()  # no world: the transition completed synchronously
	else:
		session.connect(&"transition_finished", _on_respawn_finished, CONNECT_ONE_SHOT)
	return OK


func _on_respawn_finished(_record: Variant) -> void:
	_finish()


## MapSession's state while OK waits for DEAD (IDLE comes first inside the same completion, then DEAD).
func _on_session_state(_new_state: int, _old_state: int) -> void:
	if not _awaiting_dead or not _session_dead():
		return
	_stop_waiting()
	# MapSession is still inside its completion (it sets DEAD last, then turns input off); respawning from inside
	# that call would be re-entrant, so in the game the respawn starts on the next idle step. Without a tree (pure
	# tests) there are no frames, and with no world nothing in that tail matters.
	_respawning = true
	if is_inside_tree():
		_respawn_now.call_deferred()
	else:
		_respawn_now()


func _stop_waiting() -> void:
	_awaiting_dead = false
	if session != null and is_instance_valid(session) and session.is_connected(&"state_changed", _on_session_state):
		session.disconnect(&"state_changed", _on_session_state)


# --- internals ------------------------------------------------------------------------------------------------

## MapSession committed the death (DEAD, the hook ran, the location is the respawn point): save now, so that a quit,
## a crash or a load from the death screen all find the loss taken and the character in town.
func _on_death_committed(map_id: String, _report: Variant) -> void:
	last_report["map_id"] = map_id
	last_report["death_save_error"] = OK
	if save_on_commit and game != null and game.has_method("save_game") and bool(game.call("has_active_game")):
		var err: Error = game.call("save_game", "")
		last_report["death_save_error"] = err
		if err != OK:
			push_warning("[DeathController] save at the death failed: %s" % error_string(err))
	committed.emit(map_id, last_report)
	_show_exp_loss()  # a death during a warp: announced first, committed only now


func _on_hp_changed(hp: int, _max_hp: int) -> void:
	if not armed or _dead or hp > 0 or _kill_queued:
		return
	if not _character_dead():
		return
	if not is_inside_tree():
		kill()  # pure tests: no idle step to defer to
		return
	# One idle step later: MonsterSystem emits hp_changed and then announces the death itself
	# (ContactDamage.announce_death -> MapSession.enter_dead). Killing here, synchronously, would make MapSession
	# DEAD first, so ContactDamage would emit Events.player_died a second time (the HUD logs "You have died."
	# twice). Deferred, whoever announces first wins and the other sees the death already in place.
	_kill_queued = true
	_kill_if_still_dead.call_deferred()


func _kill_if_still_dead() -> void:
	_kill_queued = false
	if not armed or _dead or session == null or not is_instance_valid(session) or not _character_dead():
		return
	kill()


## The character is at the canonical death trigger (true when there is no character to ask: the hp_changed value
## already said 0).
func _character_dead() -> bool:
	if game != null and game.get(&"character") is CharacterState and db != null:
		return Progression.is_dead(game.get(&"character"), db)
	return true


func _on_player_died(map_id: String) -> void:
	if _dead:
		return
	_dead = true
	died_in = map_id
	if player != null and player.has_method("die"):
		player.call("die")
	_close_modal_windows()
	_open_notice(map_id)
	_show_exp_loss()  # committed first (enter_dead, or MapSession heard another system's announcement first)
	died.emit(map_id)


## A respawn or a load out of DEAD (MapSession emits player_respawned for both). A load (or a new game) from DEAD,
## or the console's respawn, that did not go through confirm() ends the death too: death_cleared tells the shell to
## leave its DEAD state. The HUD still shows the killing blow (the refresh waits for the respawn), so it is refreshed
## here as well.
func _on_player_respawned(map_id: String) -> void:
	if _respawning:
		return  # our own respawn: _finish() ends the death
	_committed = false
	_loss_shown = false
	if _dead:
		_stop_waiting()
		_dead = false
		died_in = ""
		_close_notice()
		if player != null and player.has_method("revive"):
			player.call("revive")
		_announce_vitals()
		death_cleared.emit(map_id)


## A dialogue, shop or console open at the death is closed from the top of the window stack until no modal is left:
## it would keep the keyboard over the death notice and outlive the respawn (a shop of the map died in, still open
## in town, with player input back on). Non-modal windows (inventory, stats) stay open, as in classic.
func _close_modal_windows() -> void:
	if ctx == null:
		return
	var n := 0
	while ctx.is_modal_active() and n < MAX_WINDOWS_CLOSED_AT_DEATH and ctx.close_top_window():
		n += 1


func _finish() -> void:
	if player != null and player.has_method("revive"):
		player.call("revive")
	_dead = false
	_respawning = false
	_committed = false
	_loss_shown = false
	died_in = ""
	_close_notice()
	var to_map := String(session.get(&"current_map"))
	last_report["returned_to"] = to_map
	last_report["save_error"] = OK
	if save_after_respawn and game != null and game.has_method("save_game") and bool(game.call("has_active_game")):
		var err: Error = game.call("save_game", "")
		last_report["save_error"] = err
		if err != OK:
			push_warning("[DeathController] save after respawn failed: %s" % error_string(err))
	respawned.emit(to_map, last_report)


## The EXP loss shows at the death, as in classic: Events.exp_gained(-exp_lost, "death") once per death, as soon as the
## death is both committed (the loss taken) and announced (modal windows closed, notice up), whichever comes last. The
## HUD redraws only its EXP bar for it (it logs positive gains only), so the HP gauge keeps the killing blow's 0 under
## the notice; a stats_changed now would show the respawn HP the character already holds.
func _show_exp_loss() -> void:
	if _loss_shown or not _dead or not _committed or bus == null:
		return
	_loss_shown = true
	bus.emit_signal(&"exp_gained", -int(last_report.get("exp_lost", 0)), EXP_LOSS_SOURCE)


## The death rules changed EXP, HP and MP: tell the HUD (no new signal: stats/hp/mp refresh). Sent as the respawn
## starts, not at the commit: until then the HUD keeps the killing blow's HP 0 under the notice instead of the HP the
## character will wake up with (the EXP bar already dropped at the death: _show_exp_loss).
func _announce_vitals() -> void:
	if bus == null or game == null or not (game.get(&"character") is CharacterState):
		return
	var c: CharacterState = game.get(&"character")
	bus.emit_signal(&"stats_changed")
	bus.emit_signal(&"hp_changed", c.hp, StatCalculator.max_hp(c, db))
	bus.emit_signal(&"mp_changed", c.mp, StatCalculator.max_mp(c, db))


func _open_notice(map_id: String) -> void:
	if notice_parent == null:
		if ctx != null:
			ctx.push_modal(self)
		return
	if notice == null or not is_instance_valid(notice):
		notice = DeathNotice.new()
		notice.confirmed.connect(_on_notice_confirmed)
		notice_parent.add_child(notice)
	notice.open(_return_text(map_id))
	if ctx != null:
		ctx.push_modal(notice)


func _close_notice() -> void:
	if notice != null and is_instance_valid(notice):
		notice.hide()
		if ctx != null:
			ctx.pop_modal(notice)
	elif ctx != null:
		ctx.pop_modal(self)


func _on_notice_confirmed() -> void:
	var err := confirm()
	if err != OK and err != ERR_BUSY and notice != null and is_instance_valid(notice):
		notice.open(_return_text(died_in))  # let the player press OK again


func _session_dead() -> bool:
	return session != null and String(session.call("state_name")) == "DEAD"


func _session_busy() -> bool:
	return session != null and not bool(session.call("is_idle")) and not _session_dead()


## "Returns you to <town>": the canonical return map of the map the player died in.
func _return_text(map_id: String) -> String:
	if db == null or map_id == "":
		return ""
	var to := String(db.map(map_id).get("return_map_id", ""))
	var town := String(db.map(to).get("name", "")) if to != "" else ""
	return "Returns you to %s" % town if town != "" else ""
