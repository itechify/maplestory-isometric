class_name MisoHud
extends Control
## Root of res://scenes/ui/hud.tscn: the gameplay HUD.
##   - bottom bar (MisoStatusBar): level, job, name; HP / MP gauges with current / max; EXP gauge with percent;
##     mesos; buttons that open the character windows and fold the minimap ("Map [M]"); the quickslot bar;
##   - map name banner on Events.map_entered (street + map name, fades); on a trail (MapSession.trail_changed) the
##     current map's name with "-> <destination map name>" under it, held while the player is on the trail;
##   - message log: "You have gained ..." lines for items, mesos and EXP, quest updates, warnings, notices; on a
##     level-up the unspent AP and SP;
##   - level-up flourish;
##   - quickslots 1-8: keys use the bound consumable through ItemService (MisoQuickslots), or cast the bound skill;
##     a held skill key casts again whenever the lockout and the cooldown end (#20, poll_held_skills);
##   - active timed effects (MisoEffectsBar, right on top of the status bar over the quickslots): Nimble Feet,
##     Recovery, with the time left;
##   - while the player sits on a chair (Events.player_sat_down / player_stood_up), the seated cue above the HP
##     gauge with what sitting recovers (seated_text: the natural rate and the chair's bonus, from data).
## Everything is event-driven: hp_changed, mp_changed, exp_gained, leveled_up, mesos_changed, stats_changed,
## inventory_changed, equipment_changed, game_loaded (plus Game.character_replaced); values are read from the live
## character (re-resolved every time, never cached). Between Events.player_died and Events.player_respawned the HP
## gauge reads 0: a committed death already holds the respawn HP (GAME_SHELL.md "Death and respawn"). A replaced
## character (Game.character_replaced: a load) ends that early unless Game.is_character_dead() still says dead.
##
## Integration: the shell instantiates this scene under ctx.ui_root and calls setup(ctx). Without setup() it runs
## standalone against the autoloads. Tests call configure(MisoUiEnv.isolated(...)).

## MapSession signal -> handler.
const SESSION_HANDLERS := {
	"trail_changed": "_on_trail_changed",
}
## Bus signal -> handler.
const BUS_HANDLERS := {
	"hp_changed": "_on_hp_changed",
	"mp_changed": "_on_mp_changed",
	"exp_gained": "_on_exp_gained",
	"leveled_up": "_on_leveled_up",
	"mesos_changed": "_on_mesos_changed",
	"stats_changed": "_on_stats_changed",
	"inventory_changed": "_on_inventory_changed",
	"equipment_changed": "_on_equipment_changed",
	"item_gained": "_on_item_gained",
	"inventory_full": "_on_inventory_full",
	"quest_started": "_on_quest_started",
	"quest_progressed": "_on_quest_progressed",
	"quest_completed": "_on_quest_completed",
	"quest_forfeited": "_on_quest_forfeited",
	"map_entered": "_on_map_entered",
	"player_died": "_on_player_died",
	"player_respawned": "_on_player_respawned",
	"notice": "_on_notice",
	"game_loaded": "_on_game_loaded",
	"effects_changed": "_on_effects_changed",
	"player_sat_down": "_on_player_sat_down",
	"player_stood_up": "_on_player_stood_up",
}
const LOG_WIDTH := 560.0
## The effects row sits on the status bar's top edge, right-aligned over the quickslots: EFFECTS_GAP above the bar and
## EFFECTS_INSET in from its right end (presentation).
const EFFECTS_GAP := 6.0
const EFFECTS_INSET := 10.0

var env: MisoUiEnv = null
var status: MisoStatusBar
var log_panel: MisoNoticeLog
var banner: MisoMapBanner
var flourish: MisoLevelUpFlourish
var tooltip: MisoItemTooltip
var effects: MisoEffectsBar
## True between Events.player_died and Events.player_respawned (or a Game.character_replaced after which the game no
## longer says dead): the HP gauge then reads 0 whatever HP the character holds (the death commit sets the respawn HP
## while the death notice is up).
var dead: bool = false
## quest id -> {objective key: current} as last announced (to say which objective a quest_progressed moved).
var _quest_progress: Dictionary = {}
## Skill quickslot keys held down (#20): key -> {"skill_id", "announced": a refusal notice shown during this hold}.
var _held_skills: Dictionary = {}


func _init() -> void:
	name = "Hud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	theme = MisoTheme.get_theme()

	status = MisoStatusBar.new()
	status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	status.offset_left = 6
	status.offset_right = -6
	status.offset_bottom = -4
	status.window_requested.connect(request_window)
	status.minimap_requested.connect(request_minimap)
	status.quickslots.use_requested.connect(use_quickslot)
	status.quickslots.hover_changed.connect(_on_quickslot_hover)
	add_child(status)

	log_panel = MisoNoticeLog.new()
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	log_panel.offset_left = 10
	log_panel.offset_right = 10 + LOG_WIDTH
	log_panel.offset_bottom = -112
	add_child(log_panel)

	banner = MisoMapBanner.new()
	add_child(banner)
	effects = MisoEffectsBar.new()
	effects.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	effects.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	effects.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(effects)
	status.resized.connect(_place_effects)
	_place_effects()
	flourish = MisoLevelUpFlourish.new()
	add_child(flourish)
	tooltip = MisoItemTooltip.new()
	tooltip.top_level = true
	add_child(tooltip)


func _ready() -> void:
	add_to_group(MisoQuickslots.GROUP)
	if env == null:
		configure(MisoUiEnv.standalone())


## Re-entering the tree (a reparent) reconnects what _exit_tree disconnected (connections are idempotent) and
## redraws whatever changed meanwhile.
func _enter_tree() -> void:
	if env != null:
		_bind()
		refresh_all()


func _exit_tree() -> void:
	_unbind()


## The shell's integration call (GameContext contract).
func setup(ctx: GameContext) -> void:
	configure(MisoUiEnv.from_ctx(ctx))


## Points the HUD at an environment (setup, standalone and tests all end here) and redraws it.
func configure(e: MisoUiEnv) -> void:
	_unbind()
	env = e
	status.quickslots.env = e
	effects.env = e
	dead = e != null and e.is_character_dead(false)
	_bind()
	_snapshot_quests()
	refresh_all()


## Redraws every value from the live character, and the trail line from the map session.
func refresh_all() -> void:
	_sync_trail()
	var c := env.character() if env != null else null
	var db := env.get_db() if env != null else null
	if c == null or db == null:
		status.set_identity(0, "", "")
		status.set_hp(0, 0)
		status.set_mp(0, 0)
		status.set_exp(0, 0)
		status.set_mesos(0)
		status.set_ap(0)
		status.set_sp(0)  # skills package hook (Iteration Three): the SP badge
		status.quickslots.refresh()
		effects.refresh()
		return
	status.set_identity(c.level, c.name, env.job_name(c))
	_show_hp(c.hp, StatCalculator.max_hp(c, db))
	status.set_mp(c.mp, StatCalculator.max_mp(c, db))
	_refresh_exp()
	status.set_mesos(c.mesos)
	status.set_ap(c.ap)
	status.set_sp(c.sp)  # skills package hook (Iteration Three): the SP badge
	status.quickslots.refresh()
	effects.refresh()


## Keeps the effects row right on top of the status bar, over its right end (the quickslots), whatever height the bar
## lays out to: the row grows left and up from that corner, so it covers no gauge, button or quickslot.
func _place_effects() -> void:
	effects.offset_right = status.offset_right - EFFECTS_INSET
	effects.offset_left = effects.offset_right
	effects.offset_bottom = status.offset_bottom - status.size.y - EFFECTS_GAP
	effects.offset_top = effects.offset_bottom


## MisoQuickslots group hook.
func refresh_quickslots() -> void:
	status.quickslots.refresh()


## Uses the consumable bound to a quickslot key ("1".."8"). Returns the ItemService result.
func use_quickslot(key: String) -> Dictionary:
	var res := MisoQuickslots.use(env, key)
	status.quickslots.refresh()
	return res


## Opens/closes a character window by name ("inventory", "equipment", "stats", "quests"): through the windows root
## when one is in the tree, else by sending its toggle action.
func request_window(window_name: String) -> void:
	if is_inside_tree() and get_tree().get_first_node_in_group(MisoWindowsRoot.GROUP) != null:
		get_tree().call_group(MisoWindowsRoot.GROUP, &"toggle_window", window_name)
		return
	for action: String in MisoWindowsRoot.ACTIONS:
		if MisoWindowsRoot.ACTIONS[action] == window_name:
			_send_action(action)


## Folds or unfolds the minimap (the status bar's "Map [M]" button), as M does: through the minimap root when one is
## in the tree, else by sending its toggle action.
func request_minimap() -> void:
	if is_inside_tree() and get_tree().get_first_node_in_group(MisoMinimap.GROUP) != null:
		get_tree().call_group(MisoMinimap.GROUP, &"toggle")
		return
	_send_action(MisoMinimap.ACTION)


func _send_action(action: String) -> void:
	if InputMap.has_action(action):
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = true
		Input.parse_input_event(ev)


func _unhandled_input(event: InputEvent) -> void:
	if env == null or env.is_modal_active():
		return
	if not (event is InputEventKey or event is InputEventAction or event is InputEventJoypadButton):
		return
	for key in MisoQuickslots.keys():
		var action := MisoQuickslots.action_for(key)
		if InputMap.has_action(action) and event.is_action_pressed(action):
			var res := use_quickslot(key)
			_hold_skill_key(key, res)
			get_viewport().set_input_as_handled()
			return


## A skill quickslot key that was pressed starts a hold (#20, the owner's decision of 2026-10-06): while the key stays
## down it casts again as soon as the lockout and any cooldown have ended (poll_held_skills), with no input buffer
## beyond holding it. A refusal with a notice (no MP, no shell, ...) is announced once per hold: the press's own counts.
## Consumable keys start no hold: one press, one use, as before.
func _hold_skill_key(key: String, res: Dictionary) -> void:
	var skill_id := MisoQuickslots.skill_for(env.character(), key)
	if skill_id == "":
		_held_skills.erase(key)
		return
	_held_skills[key] = {"skill_id": skill_id, "announced": String(res.get("notice", "")) != ""}


## One step of the held skill keys (called every physics tick; tests call it between rig ticks): a hold ends when its
## key is up, a window or the console holds the input, or the key no longer holds that skill; otherwise the skill is
## cast again once PlayerSkills.ready_to_cast says the lockout and the cooldown are over. Returns the casts made.
func poll_held_skills() -> int:
	var cast_now := 0
	for key: String in _held_skills.keys():
		var hold: Dictionary = _held_skills[key]
		var action := MisoQuickslots.action_for(key)
		if env == null or env.is_modal_active() or not InputMap.has_action(action) or not Input.is_action_pressed(action) \
				or MisoQuickslots.skill_for(env.character(), key) != String(hold["skill_id"]):
			_held_skills.erase(key)
			continue
		var skills := MisoQuickslots.player_skills(env)
		if skills == null or not skills.ready_to_cast(String(hold["skill_id"])):
			continue
		var res := MisoQuickslots.use_skill(env, String(hold["skill_id"]), not bool(hold["announced"]))
		if bool(res.get("ok", false)):
			cast_now += 1
		elif String(res.get("notice", "")) != "":
			hold["announced"] = true
		status.quickslots.refresh()
	return cast_now


## The skill keys held down now (key -> skill id).
func held_skill_keys() -> Dictionary:
	var out := {}
	for key: String in _held_skills:
		out[key] = String((_held_skills[key] as Dictionary)["skill_id"])
	return out


func _physics_process(_delta: float) -> void:
	if not _held_skills.is_empty():
		poll_held_skills()


# --- events ---------------------------------------------------------------------------------------------------

func _bind() -> void:
	if env == null:
		return
	for sig: String in BUS_HANDLERS:
		env.connect_bus(sig, Callable(self, BUS_HANDLERS[sig]))
	for sig: String in SESSION_HANDLERS:
		env.connect_session(sig, Callable(self, SESSION_HANDLERS[sig]))
	env.connect_character_replaced(_on_character_replaced)


func _unbind() -> void:
	if env == null:
		return
	for sig: String in BUS_HANDLERS:
		env.disconnect_bus(sig, Callable(self, BUS_HANDLERS[sig]))
	for sig: String in SESSION_HANDLERS:
		env.disconnect_session(sig, Callable(self, SESSION_HANDLERS[sig]))
	env.disconnect_character_replaced(_on_character_replaced)


func _on_hp_changed(hp: int, max_hp: int) -> void:
	_show_hp(hp, max_hp)


func _on_mp_changed(mp: int, max_mp: int) -> void:
	status.set_mp(mp, max_mp)


## The EXP bar follows every amount; only a gain (amount > 0) is logged. Amounts <= 0 are refreshes: the death
## penalty arrives as exp_gained(-lost, "death"), and the bar drops with no "+" line.
func _on_exp_gained(amount: int, _source: String) -> void:
	_refresh_exp()
	if amount > 0:
		log_panel.add_line(MisoUiText.exp_gained_line(amount), "exp")


func _on_leveled_up(new_level: int) -> void:
	flourish.play(new_level)
	refresh_all()
	log_panel.add_line("Congratulations! You have reached level %d." % new_level, "exp")
	var c := env.character() if env != null else null
	if c != null and c.ap > 0:
		var key := MisoUiEnv.key_label("toggle_stats")
		log_panel.add_line("You have %d AP to distribute%s." % [c.ap, " (press %s)" % key if key != "" else ""], "info")
	# skills package hook (Iteration Three): unspent SP after a level-up.
	if c != null and c.sp > 0:
		var skey := MisoUiEnv.key_label("toggle_skills")
		log_panel.add_line("You have %d SP to spend%s." % [c.sp, " (press %s)" % skey if skey != "" else ""], "info")


func _on_mesos_changed(mesos: int, delta: int) -> void:
	status.set_mesos(mesos)
	if delta > 0:
		log_panel.add_line(MisoUiText.mesos_gained_line(delta), "mesos")
	elif delta < 0:
		log_panel.add_line("You have spent %s mesos." % MisoTheme.thousands(-delta), "spend")


func _on_stats_changed() -> void:
	refresh_all()


func _on_effects_changed() -> void:
	effects.refresh()


func _on_inventory_changed() -> void:
	status.quickslots.refresh()


func _on_equipment_changed(_slot: String) -> void:
	refresh_all()


func _on_item_gained(item_id: String, qty: int) -> void:
	log_panel.add_line(MisoUiText.item_gained_line(env.item_name(item_id) if env != null else item_id, qty), "item")


func _on_inventory_full(_item_id: String) -> void:
	log_panel.add_line("Your inventory is full.", "warn")


func _on_quest_started(quest_id: String) -> void:
	log_panel.add_line("Quest started: %s" % _quest_name(quest_id), "quest")
	_snapshot_quest(quest_id)


## Logs what a quest_progressed moved (quest_progress_line). A turn-in talk logs nothing: "Quest complete" follows.
func _on_quest_progressed(quest_id: String) -> void:
	var engine := env.quest_engine() if env != null else null
	if engine == null:
		log_panel.add_line("Quest updated: %s" % _quest_name(quest_id), "quest")
		return
	var before: Dictionary = _quest_progress.get(quest_id, {})
	var line := quest_progress_line(_quest_name(quest_id), before, engine.objective_status(quest_id))
	_snapshot_quest(quest_id)
	if line != "":
		log_panel.add_line(line, "quest")


## The log line for a quest's progress: "<quest>: " + every objective row whose count differs from `before`
## ({objective key: current}; a key it lacks counts as changed), comma-separated: "Snail 7/10", "Visit ...", and
## "spoke to <npc>" for an NPC talked to en route. A turn-in talk (npc_talk purpose "turn_in") is the completion act
## itself, announced by "Quest complete", so it names nothing. "" when nothing nameable moved.
static func quest_progress_line(quest_name: String, before: Dictionary, rows: Array) -> String:
	var changed: PackedStringArray = []
	for row: Dictionary in rows:
		var k := String(row.get("key", ""))
		if int(row.get("current", 0)) == int(before.get(k, -1)):
			continue
		if String(row.get("kind", "")) == "npc_talk":
			if String(row.get("purpose", "")) != "turn_in" and int(row.get("current", 0)) > 0:
				changed.append("spoke to %s" % String(row.get("name", row.get("id", ""))))
			continue
		changed.append(MisoUiText.objective_text(row))
	return "" if changed.is_empty() else "%s: %s" % [quest_name, ", ".join(changed)]


func _on_quest_completed(quest_id: String) -> void:
	log_panel.add_line("Quest complete: %s" % _quest_name(quest_id), "quest")
	_quest_progress.erase(quest_id)


func _on_quest_forfeited(quest_id: String) -> void:
	log_panel.add_line("Quest forfeited: %s" % _quest_name(quest_id), "warn")
	_quest_progress.erase(quest_id)


func _on_map_entered(map_id: String, _previous: String) -> void:
	banner.show_map(map_id, env.get_db() if env != null else null)


func _on_player_died(_map_id: String) -> void:
	log_panel.add_line("You have died.", "warn")
	dead = true
	_show_hp(0, status.hp_gauge.maximum)


## The death is over (the respawn finished, or a load / the console's respawn out of DEAD): the HP gauge shows the
## character's HP again.
func _on_player_respawned(_map_id: String) -> void:
	dead = false
	refresh_all()


## MapSession.trail_changed: the trail line under the map name ("" off trails, and on every map change).
func _on_trail_changed(dest_map_id: String) -> void:
	banner.show_trail(env.current_map_id() if env != null else "", dest_map_id, env.get_db() if env != null else null)


func _on_notice(text: String) -> void:
	log_panel.add_line(text, "info")


func _on_game_loaded(_slot: String) -> void:
	_snapshot_quests()
	status.set_seated("")  # the seated state is not saved: a load stands the player up (contract C3)
	refresh_all()


## Events.player_sat_down (contract C5): the seated cue above the HP gauge says what sitting recovers, from data:
## the natural rate while seated (recovery.json natural_hp, the owner's rule) and the chair's canonical bonus
## (items/<id>.json setup, Chairs.bonus). A green chair on green grass is hard to see; the cue is not.
func _on_player_sat_down(chair_id: String) -> void:
	status.set_seated(seated_text(chair_id, env.get_db() if env != null else null), "Seated: natural recovery keeps "
		+ "running and the chair adds its bonus. Any move, jump, attack or skill stands you up.")


func _on_player_stood_up(_reason: String) -> void:
	status.set_seated("")


## "Seated  +10 HP / 10 s  ·  The Green Relaxer +30 HP / 10 s" (numbers from data; a part with no data is left out).
static func seated_text(chair_id: String, db: ContentDB) -> String:
	var parts: PackedStringArray = ["Seated"]
	var rule := NaturalRecoveryRule.from_db(db) if db != null else null
	if rule != null and rule.hp_per_tick > 0 and NaturalRecoveryRule.SEATED in rule.eligible:
		parts.append("+%d HP / %s s" % [rule.hp_per_tick, _num(rule.tick_s)])
	var bonus := Chairs.bonus(chair_id, db) if db != null and chair_id != "" else {}
	if int(bonus.get("hp", 0)) > 0:
		var chair_name := String(db.item(chair_id).get("name", chair_id))
		parts.append("%s +%d HP / %s s" % [chair_name, int(bonus.hp), _num(float(bonus.interval_s))])
	return "  ·  ".join(parts) if parts.size() > 1 else "Seated"


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


## A replaced character is not the one that died, so the dead reading is re-taken from Game.is_character_dead(). A
## load out of a death shows the loaded character's HP from the start of the load: MapSession hears
## character_replaced first and has already left DEAD for the load's warp. The gauge stays at 0 only while the game
## still says dead (a load MapSession refused, a character at HP 0). Never keep `dead` regardless: a load queued
## behind a warp the player died in runs from IDLE, and no player_respawned would ever clear it.
func _on_character_replaced(_reason: String) -> void:
	tooltip.visible = false
	status.set_seated("")
	dead = env.is_character_dead(dead) if env != null else false
	_snapshot_quests()
	refresh_all()


func _on_quickslot_hover(slot: MisoItemSlot, inside: bool) -> void:
	if not inside or slot.is_empty() or env == null:
		tooltip.visible = false
		return
	tooltip.show_item(slot.item_id, env.character(), env.get_db(), {"qty": slot.qty,
		"hint": "Key %s  ·  right-click to clear" % slot.key_label.text})
	var bounds := get_viewport_rect() if is_inside_tree() else Rect2(Vector2.ZERO, Vector2(1600, 900))
	tooltip.reset_size()
	var sz := tooltip.get_combined_minimum_size()
	tooltip.place_near(slot.global_position + Vector2(slot.size.x * 0.5 - sz.x * 0.5 - 18.0, -sz.y - 22.0), bounds)


# --- internals ------------------------------------------------------------------------------------------------

## The HP gauge: `hp` / `max_hp`, or 0 / `max_hp` while dead.
func _show_hp(hp: int, max_hp: int) -> void:
	status.set_hp(0 if dead else hp, max_hp)


## Shows or clears the trail line from the map session's current value (idempotent: an unchanged line is left alone).
func _sync_trail() -> void:
	var dest := env.trail_destination() if env != null else ""
	if dest == "":
		banner.clear_trail()
	else:
		banner.show_trail(env.current_map_id(), dest, env.get_db())


func _refresh_exp() -> void:
	var c := env.character() if env != null else null
	var db := env.get_db() if env != null else null
	if c == null or db == null:
		status.set_exp(0, 0)
		return
	status.set_exp(c.exp, Progression.exp_to_next(c.level, db))


func _quest_name(quest_id: String) -> String:
	return env.quest_name(quest_id) if env != null else quest_id


func _snapshot_quests() -> void:
	_quest_progress.clear()
	var engine := env.quest_engine() if env != null else null
	if engine == null:
		return
	for qid in engine.active_quests():
		_snapshot_quest(qid)


func _snapshot_quest(quest_id: String) -> void:
	var engine := env.quest_engine() if env != null else null
	if engine == null:
		return
	var m := {}
	for row: Dictionary in engine.objective_status(quest_id):
		m[String(row.get("key", ""))] = int(row.get("current", 0))
	_quest_progress[quest_id] = m
