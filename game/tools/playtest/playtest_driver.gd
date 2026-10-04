class_name PlaytestDriver
extends Node
## Drives the REAL game for automated playthroughs (docs/runtime/PLAYTEST_HARNESS.md): it boots res://scenes/main.tscn
## (title -> creation -> world) as its child, with a private save directory, and plays it through real input
## (PlaytestInput: keys, mouse, actions). Every high-level call is a coroutine that logs one step into the
## PlaytestReport and returns a result Dictionary; check() records PASS/FAIL lines.
##
## Step kinds (PlaytestReport): "play" (real input, or waiting on the game), "console" (console(): setup only),
## "api" (a shell or system method called because the UI could not be driven; the reason is logged), "observe".
## A call made inside another (walk_to inside talk_to) is a nested step; only top-level steps are counted.
##
##   shell     new_game(name, gender, weapon_id, ap)  continue_game()  quit_to_title()  save_game()  reload_process()
##   input     press(action, s)  tap(action)  press_key(key, s)  tap_key(key)  type_text(t)  click(target)
##   world     walk_to(target, opts)  walk_route(map, route)  walk_trail(from, to)  enter_portal(name)  wait_idle()
##   combat    nearest_monster(opts)  face_and_attack_nearest(max_s, opts)  fight_until(cond, max_s, opts)
##             pickup_all_nearby(radius, max_s)
##   NPCs      talk_to(npc_id)  talk_gap(npc, feet)  read_dialogue()  choose(choice)  next()  close_dialogue()
##   windows   open_window(name)  close_window(name)  window_text(name)
##   shop      shop_buy(item_id, qty)  shop_sell(item_id, qty)  close_shop()
##   setup     console(cmd)
##   record    screenshot(name)  state()  check(name, cond, details)  soft_check(...)  note(text)  diff(a, b)
##   time      frames(n)  wait(s)  wait_until(cond, max_s)  game_s()
##
## Times are game time: physics frames / Engine.physics_ticks_per_second (the runner uses --fixed-fps 60).
## Results and pitfalls are documented in docs/runtime/PLAYTEST_HARNESS.md.

## Emitted by reload_process() once the phase is over; the runner writes the report before the process quits.
signal reload_requested
signal _never

const MAIN_SCENE := "res://scenes/main.tscn"
## Budgets (game seconds).
const LOAD_TIMEOUT_S := 90.0
const IDLE_TIMEOUT_S := 20.0
const UI_TIMEOUT_S := 2.0
## Rings (m, horizontal from the NPC's feet) of the approach points around an NPC, walked front first. The game's talk
## rule (WorldNpc.in_range) is its talk Area3D (a sphere of interaction_radius_m, raised by half of it) overlapping
## the player's body capsule, so a player pressed against a counter about 1.9 m away can still talk: see talk_gap().
const TALK_APPROACH_M: Array[float] = [1.0, 0.75, 1.3, 1.7, 2.1, 2.5]
## An approach point counts when the body standing there is at most this far (m) outside the talk zone: the lean
## (TALK_LEAN_S of walking straight at the NPC, as a player presses into a counter) closes the rest.
const TALK_LEAN_M := 0.7
const TALK_LEAN_S := 1.5
## Approach points walked at most, and planned at most (points with no path from where the player stands are planned
## but not walked), before talk_to gives up.
const TALK_MAX_TRIES := 4
const TALK_MAX_PLANS := 12
## Monsters farther than this (m) are not targets for face_and_attack_nearest by default.
const FIGHT_MAX_DIST_M := 30.0
## Beyond this (m), or above / below by more than FIGHT_TIER_DY_M, the fight walks over the routes; closer it steers
## straight at the monster.
const FIGHT_DIRECT_M := 6.0
const FIGHT_TIER_DY_M := 0.8
## Seconds without getting closer to a target before the fight walks over the routes instead (then gives up on it).
const FIGHT_STUCK_S := 2.0

var report: PlaytestReport = null
var input: PlaytestInput = null
var walker: PlaytestWalker = null
var main: MainShell = null
## Which process of the run this is (0, then +1 after each reload_process()).
var phase: int = 0
var out_dir: String = ""
var save_dir: String = ""
## Kept across reload_process() (saved in the report).
var carry: Dictionary = {}
## Every Events.notice line heard this phase (the HUD log's sentences).
var notices: PackedStringArray = []
## Print a PLAYTEST STEP line per step.
var log_steps: bool = true
## True once reload_process() ended this phase.
var reloading: bool = false

var _f0: int = 0
var _open_steps: Array[int] = []


## Indices (into report.steps) of the steps still running, outermost first.
func open_steps() -> Array[int]:
	return _open_steps.duplicate()


## Called by the runner before boot().
func setup(p_report: PlaytestReport, p_phase: int, p_out_dir: String) -> void:
	report = p_report
	phase = p_phase
	out_dir = p_out_dir
	save_dir = out_dir.path_join("saves")
	carry = report.carry
	name = "PlaytestDriver"
	process_mode = Node.PROCESS_MODE_ALWAYS
	input = PlaytestInput.new(self)
	walker = PlaytestWalker.new(self)


## Boots the real main scene with saves in `save_dir` (never the player's own). Returns true at the title.
func boot() -> bool:
	_f0 = Engine.get_physics_frames()
	DirAccess.make_dir_recursive_absolute(save_dir)
	saves().set("save_dir", save_dir)
	var ev := events()
	if ev != null and not ev.is_connected(&"notice", _on_notice):
		ev.connect(&"notice", _on_notice)
	main = (load(MAIN_SCENE) as PackedScene).instantiate() as MainShell
	main.use_command_line = false
	add_child(main)
	await frames(3)
	return main.flow.is_in(ShellFlow.State.TITLE)


# =================================================================================================================
# Accessors (null when not available)
# =================================================================================================================

func ctx() -> GameContext:
	return main.ctx() if main != null and is_instance_valid(main) else null


func world() -> IslandWorld:
	var c := ctx()
	return c.world as IslandWorld if c != null else null


func player() -> PlayerController:
	var c := ctx()
	return c.player as PlayerController if c != null else null


func session() -> Node:
	return get_node_or_null(^"/root/MapSession")


func game() -> GameState:
	return get_node_or_null(^"/root/Game") as GameState


func saves() -> Node:
	return get_node_or_null(^"/root/Saves")


func events() -> Node:
	return get_node_or_null(^"/root/Events")


func debug() -> Node:
	return get_node_or_null(^"/root/Debug")


func db() -> ContentDB:
	var d := get_node_or_null(^"/root/Data")
	return d.get("db") as ContentDB if d != null else null


func character() -> CharacterState:
	var g := game()
	return g.character if g != null else null


func current_map() -> String:
	var s := session()
	return String(s.get("current_map")) if s != null else ""


## A subsystem root by its installer name (MonsterSystem, LootSystem, InteractionSystem, HUD, Windows, NpcUI, DebugUI).
func system(subsystem_name: String) -> Node:
	if main == null or main.game_session == null:
		return null
	return main.game_session.installer.node_of(subsystem_name)


func monsters() -> Node:
	return system("MonsterSystem")


func loot() -> Node:
	return system("LootSystem")


func interaction() -> Node:
	return system("InteractionSystem")


func npc_ui() -> Node:
	return system("NpcUI")


func windows() -> Node:
	return system("Windows")


func hud() -> Node:
	return system("HUD")


func combat() -> Node:
	var p := player()
	return p.get_node_or_null(^"PlayerCombat") if p != null else null


func dialogue() -> Node:
	var ui := npc_ui()
	return ui.get("dialogue") as Node if ui != null else null


func shop() -> Node:
	var ui := npc_ui()
	return ui.get("shop") as Node if ui != null else null


# =================================================================================================================
# Recording
# =================================================================================================================

## Game seconds since this phase booted.
func game_s() -> float:
	return (Engine.get_physics_frames() - _f0) / float(Engine.physics_ticks_per_second)


## Records a PASS/FAIL check. Returns `cond`.
func check(check_name: String, cond: bool, details: String = "") -> bool:
	report.add_check(phase, check_name, cond, details, game_s(), _open_steps[-1] if not _open_steps.is_empty() else -1)
	print("PLAYTEST CHECK %s %s%s" % ["PASS" if cond else "FAIL", check_name, (": " + details) if details != "" else ""])
	return cond


## A soft check: PASS, or a WARN line that never fails the run (a known issue to surface without blocking on it).
## Returns `cond`.
func soft_check(check_name: String, cond: bool, details: String = "") -> bool:
	report.add_check(phase, check_name, cond, details, game_s(), _open_steps[-1] if not _open_steps.is_empty() else -1, true)
	print("PLAYTEST CHECK %s %s%s" % ["PASS" if cond else "WARN", check_name, (": " + details) if details != "" else ""])
	return cond


## "" when `a` and `b` hold the same values, else where they first differ ("$.inventory.slots.use[0].qty: 3 != 2").
## Numbers compare with tolerance and an int equals the same float (a save turns integral floats into ints).
static func diff(a: Variant, b: Variant, path: String = "$") -> String:
	var a_num := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var b_num := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if a_num and b_num:
		return "" if is_equal_approx(float(a), float(b)) else "%s: %s != %s" % [path, str(a), str(b)]
	if a is Dictionary and b is Dictionary:
		for k: Variant in a:
			if not (b as Dictionary).has(k):
				return "%s.%s missing" % [path, str(k)]
			var d := diff(a[k], b[k], "%s.%s" % [path, str(k)])
			if d != "":
				return d
		for k: Variant in b:
			if not (a as Dictionary).has(k):
				return "%s.%s appeared" % [path, str(k)]
		return ""
	if (a is Array or a is PackedStringArray) and (b is Array or b is PackedStringArray):
		var aa := Array(a)
		var ba := Array(b)
		if aa.size() != ba.size():
			return "%s: size %d != %d" % [path, aa.size(), ba.size()]
		for i in aa.size():
			var d := diff(aa[i], ba[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	if typeof(a) != typeof(b) and not ((a is String or a is StringName) and (b is String or b is StringName)):
		return "%s: %s != %s" % [path, str(a), str(b)]
	return "" if a == b else "%s: %s != %s" % [path, str(a), str(b)]


## A free-form line in the report.
func note(text: String) -> void:
	report.notes.append("[phase %d, %.1f s] %s" % [phase, game_s(), text])
	print("PLAYTEST NOTE " + text)


## Everything a scenario usually asserts on, read from the live game (never changes it).
func state() -> Dictionary:
	var out := {"phase": phase, "game_s": snappedf(game_s(), 0.001)}
	if main != null:
		out["flow"] = ShellFlow.state_name(main.flow.state)
	var s := session()
	if s != null:
		out["map"] = String(s.get("current_map"))
		out["session"] = String(s.call("state_name"))
		var rec: Variant = s.get("last_transition")
		if rec is TransitionRecord:
			out["last_transition"] = (rec as TransitionRecord).to_dict()
	var d := db()
	if d != null and String(out.get("map", "")) != "":
		out["map_name"] = String(d.map(String(out["map"])).get("name", ""))
	var p := player()
	var w := world()
	if p != null and is_instance_valid(p):
		out["position"] = p.global_position
		out["on_floor"] = p.is_on_floor()
		out["climbing"] = p.is_climbing()
		out["dead"] = p.is_dead()
		out["input_enabled"] = p.is_input_enabled()
		out["facing"] = p.facing
		if w != null and w.defs != null and w.defs.has_map(current_map()):
			out["local"] = w.defs.get_def(current_map()).to_local(p.global_position)
			out["region"] = w.region_index.region_of(p.global_position, current_map()) if w.region_index != null else {}
	var c := character()
	var g := game()
	if c != null and g != null and g.has_active_game():
		out["slot"] = g.current_slot
		out["name"] = c.name
		out["level"] = c.level
		out["exp"] = c.exp
		out["hp"] = c.hp
		out["mp"] = c.mp
		if d != null:
			out["max_hp"] = StatCalculator.max_hp(c, d)
			out["max_mp"] = StatCalculator.max_mp(c, d)
		out["ap"] = c.ap
		out["sp"] = c.sp
		out["mesos"] = c.mesos
		out["stats"] = c.base_stats.duplicate()
		out["inventory"] = inventory_summary()
		out["equipment"] = c.equipment.to_dict()
		out["quests"] = {"in_progress": Array(c.quests.active_ids()), "completed": Array(c.quests.completed_ids())}
		out["dead_state"] = g.is_character_dead()
	var cx := ctx()
	if cx != null:
		out["modal"] = cx.is_modal_active()
		out["windows_open"] = cx.has_open_windows()
	var dw := dialogue()
	out["dialogue_open"] = dw != null and bool(dw.call("is_open"))
	var sw := shop()
	out["shop_open"] = sw != null and bool(sw.call("is_open"))
	return out


## {tab: [{item_id, name, qty}]} for the non-empty slots of the live inventory.
func inventory_summary() -> Dictionary:
	var c := character()
	var out := {}
	if c == null:
		return out
	var d := db()
	for tab in Inventory.TABS:
		var rows: Array = []
		for i in c.inventory.capacity(tab):
			var slot := c.inventory.get_slot(tab, i)
			if slot.is_empty():
				continue
			var id := String(slot.get("item_id", ""))
			rows.append({"item_id": id, "name": String(d.item(id).get("name", "")) if d != null else "",
				"qty": int(slot.get("qty", 1)), "index": i})
		if not rows.is_empty():
			out[tab] = rows
	return out


## Saves the next rendered frame as <out>/shots/NN_<name>.png. Headless runs have no frames: the shot is recorded as
## skipped (never a failure). Returns the path ("" when skipped). Await it.
func screenshot(shot_name: String) -> String:
	var i := _begin(PlaytestReport.KIND_OBSERVE, "screenshot", shot_name)
	if DisplayServer.get_name() == "headless":
		report.screenshots.append({"name": shot_name, "phase": phase, "skipped": true, "reason": "headless run"})
		_end(i, true, "skipped (headless)")
		return ""
	var dir := out_dir.path_join("shots")
	DirAccess.make_dir_recursive_absolute(dir)
	await frames(2)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join("%02d_p%d_%s.png" % [report.screenshots.size() + 1, phase, shot_name.validate_filename()])
	var err := img.save_png(path) if img != null else ERR_CANT_CREATE
	report.screenshots.append({"name": shot_name, "phase": phase, "path": path, "skipped": false, "error": error_string(err)})
	_end(i, err == OK, path)
	return path if err == OK else ""


# =================================================================================================================
# Time
# =================================================================================================================

func frames(n: int = 1) -> void:
	for _i in n:
		await get_tree().process_frame


## Waits `seconds` of game time (physics frames), re-asserting held input.
func wait(seconds: float) -> void:
	var end := Engine.get_physics_frames() + maxi(1, roundi(seconds * Engine.physics_ticks_per_second))
	while Engine.get_physics_frames() < end:
		await get_tree().process_frame
		input.reassert()


## Waits until cond() is true or `max_s` game seconds pass. Returns cond().
func wait_until(cond: Callable, max_s: float = 10.0) -> bool:
	var end := Engine.get_physics_frames() + maxi(1, roundi(max_s * Engine.physics_ticks_per_second))
	while not bool(cond.call()) and Engine.get_physics_frames() < end:
		await get_tree().process_frame
		input.reassert()
	return bool(cond.call())


## Waits until MapSession is IDLE and the player stands on the floor (a warp, a load or a respawn has finished).
func wait_idle(max_s: float = IDLE_TIMEOUT_S) -> bool:
	return await wait_until(func() -> bool:
		var s := session()
		var p := player()
		return s != null and bool(s.call("is_idle")) and p != null and is_instance_valid(p) and p.is_on_floor(), max_s)


# =================================================================================================================
# Shell: title, creation, continue, save, quit
# =================================================================================================================

## A new game through the real title and creation screens: New Game, the name typed into the name field, the gender
## and weapon buttons, Clear and "+" for every point of `ap` (or Recommended when `ap` is empty), Start. If any
## control does not respond, the rest goes through MainShell.start_new_game (the step becomes "api" with the reason).
## `weapon_id` "" keeps the screen's choice. Returns {"ok", "via" ("screen" | "api"), "slot", "map", "why"}. Await it.
func new_game(char_name: String = "Tester", gender: String = "female", weapon_id: String = "", ap: Dictionary = {}) -> Dictionary:
	var i := _begin(PlaytestReport.KIND_PLAY, "new_game", "%s, %s, weapon %s, ap %s" % [char_name, gender,
		weapon_id if weapon_id != "" else "(screen)", ap if not ap.is_empty() else "(Recommended)"])
	var out := {"ok": false, "via": "screen", "slot": "", "map": "", "why": ""}
	if main == null or not main.flow.is_in(ShellFlow.State.TITLE):
		out["why"] = "not on the title screen (%s)" % (ShellFlow.state_name(main.flow.state) if main != null else "no main")
		_end(i, false, out["why"])
		return out
	var why := ""
	if not await _click_control(main.title.new_button):
		why = "the title's New Game button did not respond"
	elif not await wait_until(func() -> bool: return main.creation != null and is_instance_valid(main.creation), UI_TIMEOUT_S):
		why = "New Game opened no creation screen"
	else:
		why = await _fill_creation(char_name, gender, weapon_id, ap)
		if why == "" and not await _click_control(main.creation.start_button):
			why = "the creation screen's Start button did not respond"
	if why != "":
		out["via"] = "api"
		_fallback(i, why)
		var params := CharacterFactory.default_params(db())
		params["name"] = char_name
		params["gender"] = gender
		if weapon_id != "":
			params["weapon_id"] = weapon_id
		if not ap.is_empty():
			params["ap"] = ap.duplicate()
		params.erase("slot")
		if main.flow.is_in(ShellFlow.State.TITLE):
			main.open_creation()
		var j := _begin(PlaytestReport.KIND_API, "MainShell.start_new_game", str(params))
		main.start_new_game(params)
		_end(j, true)
	var ok := await _wait_playing(LOAD_TIMEOUT_S)
	out["ok"] = ok
	out["why"] = why if ok else (main.last_error_message if main.last_error_message != "" else "the game did not start")
	out["slot"] = main.target_slot
	out["map"] = current_map()
	_end(i, ok, "%s in %s via %s" % [out["slot"], out["map"], out["via"]])
	return out


## Continue on the title screen (the newest loadable save). Returns {"ok", "via", "slot", "map"}. Await it.
func continue_game() -> Dictionary:
	var i := _begin(PlaytestReport.KIND_PLAY, "continue_game")
	var out := {"ok": false, "via": "screen", "slot": "", "map": ""}
	if main == null or not main.flow.is_in(ShellFlow.State.TITLE):
		_end(i, false, "not on the title screen")
		return out
	out["slot"] = main.title.continue_slot
	var clicked := false
	if main.title.continue_button.visible:
		clicked = await _click_control(main.title.continue_button)
	if not clicked:
		out["via"] = "api"
		_fallback(i, "the title's Continue button is %s" % ("hidden (no loadable save)" if not main.title.continue_button.visible else "not responding"))
		var j := _begin(PlaytestReport.KIND_API, "MainShell.continue_game")
		main.continue_game()
		_end(j, true)
	var ok := await _wait_playing(LOAD_TIMEOUT_S)
	out["ok"] = ok
	out["map"] = current_map()
	_end(i, ok, "%s in %s" % [out["slot"], out["map"]])
	return out


## Esc (closing windows first) until the pause menu is open, then its Quit to Title button (the shell saves first).
## Returns {"ok", "via"}. Await it.
func quit_to_title() -> Dictionary:
	var i := _begin(PlaytestReport.KIND_PLAY, "quit_to_title")
	var out := {"ok": false, "via": "screen"}
	if main == null or not (main.flow.is_in(ShellFlow.State.PLAYING) or main.flow.is_in(ShellFlow.State.PAUSED)):
		_end(i, false, "no game running")
		return out
	var clicked := false
	if await _open_pause_menu():
		clicked = await _click_control(_find_text(main.pause_menu, "Quit to Title"))
	if not clicked:
		out["via"] = "api"
		_fallback(i, "the pause menu's Quit to Title could not be used")
		var j := _begin(PlaytestReport.KIND_API, "MainShell.quit_to_title")
		main.quit_to_title()
		_end(j, true)
	var ok := await wait_until(func() -> bool:
		return main.flow.is_in(ShellFlow.State.TITLE) and String(session().call("state_name")) == "BOOT", 10.0)
	out["ok"] = ok
	_end(i, ok, ShellFlow.state_name(main.flow.state))
	return out


## The pause menu's Save button (Esc, Save, Esc). Returns {"ok", "via", "slot", "status"}. Await it.
func save_game() -> Dictionary:
	var i := _begin(PlaytestReport.KIND_PLAY, "save_game")
	var out := {"ok": false, "via": "screen", "slot": "", "status": ""}
	var saved: Array[String] = []
	var on_saved := func(slot: String) -> void: saved.append(slot)
	events().connect(&"game_saved", on_saved)
	var clicked := false
	if await _open_pause_menu():
		clicked = await _click_control(main.pause_menu.save_button)
	await frames(2)
	if main.pause_menu.status_label != null:
		out["status"] = main.pause_menu.status_label.text
	if not clicked:
		out["via"] = "api"
		_fallback(i, "the pause menu's Save could not be used")
		var j := _begin(PlaytestReport.KIND_API, "MainShell.save_now")
		var err := main.save_now()
		_end(j, err == OK, error_string(err))
	if main.flow.is_in(ShellFlow.State.PAUSED):
		await input.tap_key(KEY_ESCAPE)
		await wait_until(func() -> bool: return main.flow.is_in(ShellFlow.State.PLAYING), UI_TIMEOUT_S)
	events().disconnect(&"game_saved", on_saved)
	out["ok"] = not saved.is_empty()
	out["slot"] = saved[0] if not saved.is_empty() else ""
	_end(i, bool(out["ok"]), "%s %s" % [out["slot"], out["status"]])
	return out


## Ends this process the way a player does (the pause menu's Quit Game: the shell saves, the application quits) and
## lets the runner start the next phase with the same save directory. The scenario's run() is called again in the
## new process with `phase` + 1, so branch on `phase` and keep values in `carry`. Never returns. Await it.
func reload_process() -> void:
	var i := _begin(PlaytestReport.KIND_PLAY, "reload_process", "phase %d -> %d" % [phase, phase + 1])
	report.carry = carry
	reloading = true
	var opened := await _open_pause_menu()
	var btn := _find_text(main.pause_menu, "Quit Game") if opened else null
	if btn == null:
		_fallback(i, "the pause menu's Quit Game could not be used: closing the window instead")
	_end(i, true, "via %s" % ("Quit Game" if btn != null else "the window's close request"))
	# The runner writes the report now: the click below ends the process.
	reload_requested.emit()
	if btn != null:
		await _click_control(btn)
		await frames(10)
	# Still here: the click did not quit. Close the window as the OS does (Game saves on the close request).
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().paused = false
	get_tree().quit(0)
	await _never


# =================================================================================================================
# Input
# =================================================================================================================

## Holds an action's key for `seconds` of game time. Await it.
func press(action: StringName, seconds: float) -> void:
	var i := _begin(PlaytestReport.KIND_PLAY, "press", "%s %.2f s" % [action, seconds])
	if not InputMap.has_action(action):
		_end(i, false, "unknown action")
		return
	await input.hold_action(action, seconds)
	_end(i, true)


## One press and release of an action's key. Await it.
func tap(action: StringName) -> void:
	var i := _begin(PlaytestReport.KIND_PLAY, "tap", String(action))
	if not InputMap.has_action(action):
		_end(i, false, "unknown action")
		return
	await input.tap_action(action)
	_end(i, true)


## Holds a raw key (Enter, Y, Tab, digits: keys the windows read that are not actions). Await it.
func press_key(code: Key, seconds: float) -> void:
	var i := _begin(PlaytestReport.KIND_PLAY, "press_key", "%s %.2f s" % [OS.get_keycode_string(code), seconds])
	await input.hold_key(code, seconds)
	_end(i, true)


func tap_key(code: Key) -> void:
	var i := _begin(PlaytestReport.KIND_PLAY, "tap_key", OS.get_keycode_string(code))
	await input.tap_key(code)
	_end(i, true)


## Types into the focused control. Await it.
func type_text(text: String) -> void:
	var i := _begin(PlaytestReport.KIND_PLAY, "type_text", text)
	await input.type_text(text)
	_end(i, true)


## Clicks a Control with the mouse: a Control, a node path ("/root/...", or "./..." relative to the main scene) or a
## text (the topmost visible control whose text is exactly it, else contains it, buttons first). Returns {"ok", "control"}.
## Await it.
func click(target: Variant) -> Dictionary:
	var i := _begin(PlaytestReport.KIND_PLAY, "click", str(target))
	var c := find_control(target)
	if c == null:
		_end(i, false, "no visible control matches")
		return {"ok": false, "control": ""}
	var path := str(c.get_path())
	var ok := await _click_control(c)
	_end(i, ok, path)
	return {"ok": ok, "control": path}


## The control `target` names (see click()), or null.
func find_control(target: Variant) -> Control:
	if target is Control:
		return target if is_instance_valid(target) and (target as Control).is_visible_in_tree() else null
	var s := str(target)
	if target is NodePath or s.begins_with("/root") or s.begins_with("./") or s.begins_with("%"):
		var n := get_node_or_null(NodePath(s)) if s.begins_with("/") else (main.get_node_or_null(NodePath(s.trim_prefix("./"))) if main != null else null)
		return n as Control if n is Control and (n as Control).is_visible_in_tree() else null
	var exact: Array[Control] = []
	var partial: Array[Control] = []
	for n in get_tree().root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or not ("text" in c):
			continue
		var t := str(c.get("text"))
		if t == s:
			exact.append(c)
		elif s != "" and t.to_lower().contains(s.to_lower()):
			partial.append(c)
	for group in [exact, partial]:
		var best: Control = null
		for c: Control in group:
			if best == null or (c is BaseButton and not (best is BaseButton)) \
					or ((c is BaseButton) == (best is BaseButton) and _layer_of(c) >= _layer_of(best)):
				best = c
		if best != null:
			return best
	return null


# =================================================================================================================
# World: walking, trails, portals
# =================================================================================================================

## Walks to `target` in the current map (PlaytestWalker.plan: the map's routes, else the grid planner on the real
## collision), with stall detection, one re-plan, and a timeout. Targets: a world Vector3; a map-local
## {"local": Vector3} or "local:x,y,z"; "world:x,y,z"; markers "portal:<id>", "npc:<id>" (1 m in front), "spawn:<n>",
## "slot:<n>", "route:<name>[:end]". opts: "max_s", "within_m", "stop_when" (Callable), "retries", "clearance_m",
## "planner" ("auto", "grid", "routes"). Returns PlaytestWalker.walk_to()'s result plus "target". Await it.
func walk_to(target: Variant, opts: Dictionary = {}) -> Dictionary:
	var i := _begin(PlaytestReport.KIND_PLAY, "walk_to", _target_text(target))
	var t := resolve_target(target)
	if not bool(t["ok"]):
		_end(i, false, String(t["why"]))
		return {"ok": false, "result": "NO_TARGET", "issues": PackedStringArray([t["why"]])}
	var r := await walker.walk_to(t["position"], _target_text(target), opts)
	r["target"] = t["position"]
	_end(i, bool(r["ok"]), _walk_text(r))
	return r


## Where `target` (see walk_to) is in the current map: {"ok", "position", "why"}.
func resolve_target(target: Variant) -> Dictionary:
	var w := world()
	if w == null or player() == null:
		return {"ok": false, "why": "no game running"}
	var map_id := current_map()
	var def := w.defs.get_def(map_id) if w.defs.has_map(map_id) else null
	if def == null:
		return {"ok": false, "why": "no map definition for '%s'" % map_id}
	if target is Vector3:
		return {"ok": true, "position": walker.grounded(target)}
	if target is Dictionary and (target as Dictionary).has("local"):
		return {"ok": true, "position": walker.grounded(def.to_world((target as Dictionary)["local"]))}
	var s := str(target)
	var kind := s.get_slice(":", 0)
	var rest := s.substr(kind.length() + 1) if s.contains(":") else ""
	match kind:
		"local", "world":
			var parts := rest.split(",")
			if parts.size() != 3:
				return {"ok": false, "why": "expected %s:x,y,z" % kind}
			var v := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
			return {"ok": true, "position": walker.grounded(def.to_world(v) if kind == "local" else v)}
		"portal":
			var pd := w.defs.portal(map_id, rest)
			return {"ok": true, "position": pd.anchor_ground} if pd != null else {"ok": false, "why": "no portal %s in %s" % [rest, map_id]}
		"npc":
			var npc := w.npc_nodes.get(rest) as Node3D
			if npc == null:
				return {"ok": false, "why": "no NPC %s" % rest}
			var front := Vector3(npc.global_transform.basis.z.x, 0.0, npc.global_transform.basis.z.z)
			front = front.normalized() if front.length() > 0.01 else Vector3.FORWARD
			return {"ok": true, "position": walker.grounded(npc.global_position + front * TALK_APPROACH_M[0])}
		"spawn":
			return {"ok": true, "position": def.player_spawn(int(rest)).origin}
		"slot":
			var slots: Array = def.monster_spawn_definitions
			var n := int(rest)
			if n < 0 or n >= slots.size():
				return {"ok": false, "why": "no spawn slot %d in %s (%d slots)" % [n, map_id, slots.size()]}
			return {"ok": true, "position": (slots[n] as SpawnSlot).transform.origin}
		"route":
			var rn := rest.get_slice(":", 0)
			var pts := route_points(map_id, rn)
			if pts.is_empty():
				return {"ok": false, "why": "no route %s in %s" % [rn, map_id]}
			return {"ok": true, "position": pts[pts.size() - 1] if rest.ends_with(":end") else pts[0]}
	return {"ok": false, "why": "unknown target '%s' (Vector3, {local}, local:, world:, portal:, npc:, spawn:, slot:, route:)" % s}


## The points of an exported route of `map_id` (world space; empty when there is no such route).
func route_points(map_id: String, route_name: String) -> PackedVector3Array:
	var w := world()
	var out := PackedVector3Array()
	if w == null or not w.defs.has_map(map_id):
		return out
	for r: Variant in w.defs.get_def(map_id).sidecar.get("routes", []):
		if r is Dictionary and String((r as Dictionary).get("name", "")) == route_name:
			for pt: Variant in (r as Dictionary).get("points", []):
				if pt is Array and (pt as Array).size() >= 3:
					out.append(Vector3(float(pt[0]), float(pt[1]), float(pt[2])))
	return out


## True when the exported route is one_way (walkable in its own direction only).
func route_is_one_way(map_id: String, route_name: String) -> bool:
	var w := world()
	if w == null or not w.defs.has_map(map_id):
		return false
	for r: Variant in w.defs.get_def(map_id).sidecar.get("routes", []):
		if r is Dictionary and String((r as Dictionary).get("name", "")) == route_name:
			return bool((r as Dictionary).get("one_way", false))
	return false


## Walks to the start of an exported route of the current map, then along it (opts "reverse": end to start, refused
## for a one_way route). Returns {"ok", "legs", "time_s", "distance_m", "issues"}. Await it.
func walk_route(map_id: String, route_name: String, opts: Dictionary = {}) -> Dictionary:
	var reverse := bool(opts.get("reverse", false))
	var i := _begin(PlaytestReport.KIND_PLAY, "walk_route", "%s %s%s" % [map_id, route_name, " (reverse)" if reverse else ""])
	var issues := PackedStringArray()
	var out := {"ok": false, "legs": [], "time_s": 0.0, "distance_m": 0.0, "issues": issues}
	if current_map() != map_id:
		issues.append("in %s, not %s" % [current_map(), map_id])
		return _end_with(i, out, issues)
	var pts := route_points(map_id, route_name)
	if pts.size() < 2:
		issues.append("no route %s in %s" % [route_name, map_id])
		return _end_with(i, out, issues)
	if reverse:
		if route_is_one_way(map_id, route_name):
			issues.append("%s is one-way: it cannot be walked in reverse" % route_name)
			return _end_with(i, out, issues)
		pts.reverse()
	var legs: Array = []
	var leg1 := await walker.walk_to(pts[0], "to the start of %s" % route_name, opts)
	legs.append(leg1)
	var ok := bool(leg1["ok"])
	if ok:
		var leg2 := await walker.follow(pts, "route %s/%s" % [map_id, route_name], opts)
		legs.append(leg2)
		ok = bool(leg2["ok"])
	issues.append_array(_sum_legs(out, legs))
	out["ok"] = ok
	return _end_with(i, out, issues, "%.1f s, %.1f m" % [float(out["time_s"]), float(out["distance_m"])])


## Walks out of `from_map` along the trail to `to_map` and across the far gate (edge mode, M2): to the portal over the
## map's routes, then the trail's centreline to the destination portal's arrival. A link that is not an edge trail
## (a door, or a trail kept warp-only) is entered with Up instead, and the step says so. Returns {"ok", "how"
## ("walk" | "press_up"), "via", "map", "time_s", "distance_m", "issues"}. Await it.
func walk_trail(from_map: String, to_map: String, opts: Dictionary = {}) -> Dictionary:
	var i := _begin(PlaytestReport.KIND_PLAY, "walk_trail", "%s -> %s" % [from_map, to_map])
	var issues := PackedStringArray()
	var out := {"ok": false, "how": "walk", "via": "", "map": current_map(), "time_s": 0.0, "distance_m": 0.0,
		"legs": [], "issues": issues}
	var w := world()
	if w == null or current_map() != from_map:
		issues.append("in %s, not %s" % [current_map(), from_map])
		return _end_with(i, out, issues)
	var d := w.defs
	var src := TraversalTour.portal_between(d, from_map, to_map)
	if src == null:
		issues.append("no portal %s -> %s" % [from_map, to_map])
		return _end_with(i, out, issues)
	if not d.graph.is_edge(src.link_id):
		note("%s -> %s is not an edge trail (%s): entering %s with Up" % [from_map, to_map, src.link_id, src.key()])
		out["how"] = "press_up"
		var e := await enter_portal(src.portal_id)
		issues.append_array(e.get("issues", PackedStringArray()))
		out["ok"] = bool(e["ok"])
		out["via"] = String(e.get("via", ""))
		out["map"] = current_map()
		return _end_with(i, out, issues, "entered with Up: %s via %s" % [out["map"], out["via"]])
	var legs: Array = []
	var leg1 := await walker.walk_to(src.anchor_ground, "to %s" % src.key(), opts)
	legs.append(leg1)
	if bool(leg1["ok"]):
		var t := d.trail(src.link_id)
		var dst := d.graph.portals.get(t.portal_key_of(to_map), null) as PortalDef
		var path := PackedVector3Array([player().global_position, src.anchor_ground])
		path.append_array(t.centreline_from(from_map))
		if dst != null:
			path.append(dst.anchor_ground)
			path.append(dst.spawn_transform.origin)
		var o := opts.duplicate()
		o["allow_map_change"] = true
		legs.append(await walker.follow(path, "trail %s -> %s" % [src.key(), to_map], o))
	issues.append_array(_sum_legs(out, legs))
	var rec: Variant = session().get("last_transition")
	out["via"] = (rec as TransitionRecord).via if rec is TransitionRecord else ""
	out["map"] = current_map()
	if current_map() != to_map:
		issues.append("ended in %s" % current_map())
	elif out["via"] != "gate":
		issues.append("entered %s via %s, not the gate" % [to_map, out["via"]])
	out["ok"] = legs.size() == 2 and bool((legs[1] as Dictionary)["ok"]) and current_map() == to_map and out["via"] == "gate"
	return _end_with(i, out, issues, "%s via %s, %.1f s, %.1f m" % [out["map"], out["via"], float(out["time_s"]),
		float(out["distance_m"])])


## Walks into a portal of the current map and presses Up. `portal_name`: the portal id ("out00"), or a destination
## map id or name. A portal that only works by walking (an edge trail) is walked with walk_trail. Returns {"ok",
## "from", "to", "via", "portal", "issues"}. Await it.
func enter_portal(portal_name: String) -> Dictionary:
	var i := _begin(PlaytestReport.KIND_PLAY, "enter_portal", portal_name)
	var issues := PackedStringArray()
	var out := {"ok": false, "from": current_map(), "to": "", "via": "", "portal": "", "issues": issues}
	var src := find_portal(portal_name)
	var w := world()
	if src == null or w == null:
		issues.append("no portal '%s' in %s" % [portal_name, current_map()])
		return _end_with(i, out, issues)
	out["portal"] = src.key()
	if not src.accepts_press():
		if w.defs.graph.is_edge(src.link_id):
			var t := await walk_trail(current_map(), src.destination_map_id)
			issues.append_array(t.get("issues", PackedStringArray()))
			out["ok"] = bool(t["ok"])
			out["to"] = current_map()
			out["via"] = t["via"]
			return _end_with(i, out, issues, "walked the trail to %s" % out["to"])
		issues.append("%s does not accept Up" % src.key())
		return _end_with(i, out, issues)
	var leg := await walker.walk_to(src.anchor_ground, "to %s" % src.key())
	var node := w.portal_node(src.source_map_id, src.portal_id)
	var inside := await walker.nudge_until(src.anchor_ground, func() -> bool: return w.portal_under_player() == node)
	if not inside:
		issues.append("not inside %s's trigger" % src.key())
		issues.append_array(leg.get("issues", PackedStringArray()))
		return _end_with(i, out, issues)
	var from := current_map()
	var s := session()
	await input.tap_action(&"portal_enter")
	var started := await wait_until(func() -> bool: return not bool(s.call("is_idle")) or current_map() != from, 0.5)
	if not started:
		issues.append("Up in %s started no transition (%s)" % [src.key(), w.interactor.last_block])
		return _end_with(i, out, issues)
	var ok := await wait_idle()
	var rec: Variant = s.get("last_transition")
	out["via"] = (rec as TransitionRecord).via if rec is TransitionRecord else ""
	out["to"] = current_map()
	out["ok"] = ok and current_map() == src.destination_map_id
	if not out["ok"]:
		issues.append("ended in %s (%s), expected %s" % [current_map(), String(s.call("state_name")), src.destination_map_id])
	return _end_with(i, out, issues, "%s via %s" % [out["to"], out["via"]])


## A portal of the current map by id, else by destination map id or name (canonical portals first).
func find_portal(portal_name: String) -> PortalDef:
	var w := world()
	if w == null or not w.defs.has_map(current_map()):
		return null
	var def := w.defs.get_def(current_map())
	var p := def.portal(portal_name)
	if p != null:
		return p
	var d := db()
	for q: PortalDef in def.canonical_portals():
		var dest := q.destination_map_id
		if dest == portal_name or (d != null and String(d.map(dest).get("name", "")).to_lower() == portal_name.to_lower()):
			return q
	return null


# =================================================================================================================
# Combat and loot
# =================================================================================================================

## The nearest live monster in the current map (horizontal distance), or null. opts: "mob_id", "max_dist_m"
## (FIGHT_MAX_DIST_M), "exclude" (instance id -> true).
func nearest_monster(opts: Dictionary = {}) -> Node3D:
	var ms := monsters()
	var p := player()
	if ms == null or p == null:
		return null
	var best: Node3D = null
	var best_d := float(opts.get("max_dist_m", FIGHT_MAX_DIST_M))
	var exclude: Dictionary = opts.get("exclude", {})
	for m: Node3D in ms.call("live_monsters"):
		if not is_instance_valid(m) or not bool(m.call("is_alive")) or exclude.has(m.get_instance_id()):
			continue
		if opts.has("mob_id") and String(m.get("def").get("id")) != String(opts["mob_id"]):
			continue
		var dd := _flat(m.global_position - p.global_position)
		if dd < best_d:
			best_d = dd
			best = m
	return best


## Picks the nearest live monster, walks up to it (over the routes when it is far or on another tier, straight at it
## when close), faces it and attacks with the attack key until it dies or `max_s` pass. Reach comes from the weapon's
## canonical hit boxes and the monster's touch box (CombatReach, WorldScale.actor). opts: see nearest_monster.
## Returns {"ok" (killed), "target" (mob id), "attacks", "hits", "misses" (rolled MISS), "whiffs" (nothing in reach),
## "damage", "time_s", "why"}. Await it.
func face_and_attack_nearest(max_s: float = 15.0, opts: Dictionary = {}) -> Dictionary:
	var target := nearest_monster(opts)
	var i := _begin(PlaytestReport.KIND_PLAY, "face_and_attack_nearest", "%.0f s%s" % [max_s,
		(" " + str(opts.get("mob_id"))) if opts.has("mob_id") else ""])
	var out := {"ok": false, "target": "", "attacks": 0, "hits": 0, "misses": 0, "whiffs": 0, "damage": 0, "time_s": 0.0,
		"why": ""}
	var ms := monsters()
	var pc := combat()
	var p := player()
	if target == null or ms == null or pc == null:
		out["why"] = "no live monster in reach" if target == null else "no combat system"
		_end(i, false, String(out["why"]))
		return out
	out["target"] = String(target.get("def").get("id"))
	var died := [false]
	var on_died := func(m: Node) -> void:
		if m == target:
			died[0] = true
	ms.connect(&"monster_died", on_died)
	var on_resolved := func(t: Node, res: Variant) -> void:
		if t == null:
			out["whiffs"] = int(out["whiffs"]) + 1
		elif t == target and res != null:
			if bool(res.get("missed")):
				out["misses"] = int(out["misses"]) + 1
			else:
				out["hits"] = int(out["hits"]) + 1
				out["damage"] = int(out["damage"]) + int(res.get("final"))
	pc.connect(&"attack_resolved", on_resolved)
	var reach := attack_reach(target)
	var ideal := float(reach["ideal_m"])
	var t0 := game_s()
	var best_d := INF
	var best_t := t0
	var routed := 0
	while not died[0] and game_s() - t0 < max_s:
		await get_tree().process_frame
		input.reassert()
		if not is_instance_valid(target) or not bool(target.call("is_alive")):
			break
		if p.is_dead() or game().is_character_dead():
			out["why"] = "the player died"
			break
		var to := target.global_position - p.global_position
		var dy := absf(to.y)
		to.y = 0.0
		var dist := to.length()
		if dist < best_d - 0.05:
			best_d = dist
			best_t = game_s()
		var stuck := game_s() - best_t > FIGHT_STUCK_S and dist > ideal
		if dist > FIGHT_DIRECT_M or dy > FIGHT_TIER_DY_M or stuck:
			if routed >= 3:
				out["why"] = "could not reach the monster (%.1f m away, %.1f m up/down)" % [dist, dy]
				break
			routed += 1
			input.release_movement()
			var tgt := target
			await walker.walk_to(walker.grounded(target.global_position), "to monster %s" % out["target"], {"max_s": 6.0,
				"retries": 0, "stop_when": func() -> bool:
					return not is_instance_valid(tgt) or not bool(tgt.call("is_alive")) \
						or (_flat(tgt.global_position - p.global_position) <= ideal and absf(tgt.global_position.y - p.global_position.y) <= FIGHT_TIER_DY_M)})
			best_d = INF
			best_t = game_s()
			continue
		if dist > ideal:
			input.set_move_world(to.normalized(), p.view_right, p.view_forward)
			continue
		input.release_movement()
		var dir := to.normalized() if dist > 0.01 else p.facing
		if p.facing.dot(dir) < cos(deg_to_rad(20.0)):
			# Turn toward it: the facing follows the walking direction (a tick of a slow step).
			input.set_move_world(dir * 0.2, p.view_right, p.view_forward)
			await get_tree().physics_frame
			await get_tree().process_frame
			input.release_movement()
			continue
		if bool(pc.call("can_attack")):
			var before := int(pc.get("attacks"))
			await input.tap_action(&"attack")
			out["attacks"] = int(out["attacks"]) + (int(pc.get("attacks")) - before)
			if not is_instance_valid(pc.get("last_target")) and int(pc.get("attacks")) > before:
				ideal = maxf(float(reach["min_m"]), ideal * 0.8)
	input.release_movement()
	ms.disconnect(&"monster_died", on_died)
	pc.disconnect(&"attack_resolved", on_resolved)
	out["ok"] = bool(died[0])
	out["time_s"] = snappedf(game_s() - t0, 0.001)
	if not bool(out["ok"]) and String(out["why"]) == "":
		out["why"] = "still alive after %.1f s" % max_s if is_instance_valid(target) and bool(target.call("is_alive")) else "it died to something else"
	_end(i, bool(out["ok"]), "%s: %d attacks, %d hits, %d damage%s" % [out["target"], int(out["attacks"]), int(out["hits"]),
		int(out["damage"]), "" if bool(out["ok"]) else " (" + String(out["why"]) + ")"])
	return out


## Fights the nearest monsters (face_and_attack_nearest) until cond() is true or `max_s` pass. Returns {"ok"
## (cond met), "kills", "attacks", "hits", "time_s", "fights"}. Await it.
func fight_until(cond: Callable, max_s: float = 60.0, opts: Dictionary = {}) -> Dictionary:
	var i := _begin(PlaytestReport.KIND_PLAY, "fight_until", "%.0f s" % max_s)
	var out := {"ok": false, "kills": 0, "attacks": 0, "hits": 0, "time_s": 0.0, "fights": []}
	var t0 := game_s()
	var exclude: Dictionary = (opts.get("exclude", {}) as Dictionary).duplicate()
	while not bool(cond.call()) and game_s() - t0 < max_s:
		if player() == null or game().is_character_dead():
			break
		var o := opts.duplicate()
		o["exclude"] = exclude
		var target := nearest_monster(o)
		if target == null:
			await wait(0.5)
			continue
		var r := await face_and_attack_nearest(minf(20.0, max_s - (game_s() - t0)), o)
		(out["fights"] as Array).append(r)
		out["attacks"] = int(out["attacks"]) + int(r["attacks"])
		out["hits"] = int(out["hits"]) + int(r["hits"])
		if bool(r["ok"]):
			out["kills"] = int(out["kills"]) + 1
		elif is_instance_valid(target) and String(r["why"]).begins_with("could not reach"):
			exclude[target.get_instance_id()] = true
	out["ok"] = bool(cond.call())
	out["time_s"] = snappedf(game_s() - t0, 0.001)
	_end(i, bool(out["ok"]), "%d kills, %d attacks, %d hits in %.1f s" % [int(out["kills"]), int(out["attacks"]),
		int(out["hits"]), float(out["time_s"])])
	return out


## Distances (m, feet to feet, horizontal) at which the current weapon's basic attack reaches `monster`: the nearest
## far edge of its hit boxes (every ordinary action and presentation, CombatReach.attack_box_px) plus half the
## monster's canonical touch box, through WorldScale.actor. {"max_m", "ideal_m" (0.6 of it), "min_m"}.
func attack_reach(monster: Node) -> Dictionary:
	var c := character()
	var d := db()
	var stats := PlayerCombatStats.from_character(c, d)
	var weapon := stats.weapon if stats.weapon != null else WeaponProfile.bare_hands(d)
	var far := INF
	for action: Variant in weapon.ordinary_actions().keys():
		for pres in weapon.presentations_for(String(action)):
			far = minf(far, CombatReach.attack_box_px(weapon, pres, true, c.level).end.x)
	if far == INF:
		far = 0.0
	var half := 0.0
	var def: Variant = monster.get("def") if monster != null else null
	if def != null and def.get("stats") != null:
		var tz: Variant = def.get("stats").get("touch_zone_px")
		half = float(tz.x) / 2.0
	var max_m := WorldScale.actor(far + half)
	return {"max_m": max_m, "ideal_m": maxf(0.15, max_m * 0.6), "min_m": maxf(0.1, max_m * 0.25)}


## Picks up every landed drop within `radius_m` with the pickup key (Z), walking to each one. Drops the game refuses
## (a full inventory) are left. Returns {"ok" (none left in reach), "picked", "records", "refused", "left"}. Await it.
func pickup_all_nearby(radius_m: float = 6.0, max_s: float = 30.0) -> Dictionary:
	var i := _begin(PlaytestReport.KIND_PLAY, "pickup_all_nearby", "%.1f m" % radius_m)
	var out := {"ok": false, "picked": 0, "records": [], "refused": 0, "left": 0}
	var ls := loot()
	var p := player()
	if ls == null or p == null:
		_end(i, false, "no loot system")
		return out
	var refused := {}
	var on_picked := func(rec: Dictionary, _res: Dictionary) -> void: (out["records"] as Array).append(rec)
	var on_refused := func(rec: Dictionary, _res: Dictionary) -> void: refused[String(rec.get(LootPickupRules.UID_KEY, ""))] = true
	ls.connect(&"drop_picked_up", on_picked)
	ls.connect(&"pickup_refused", on_refused)
	var t0 := game_s()
	var tried := {}
	while game_s() - t0 < max_s:
		await get_tree().process_frame
		var here: Dictionary = ls.call("pickup_target", p.global_position, refused)
		if not here.is_empty():
			await input.tap_action(&"pickup")
			await frames(2)
			continue
		var best: Node3D = null
		var best_d := radius_m
		var tossing := false
		for n: Node3D in (ls.call("nodes") as Dictionary).values():
			var uid := String(n.get("uid"))
			if refused.has(uid) or int(tried.get(uid, 0)) >= 2:
				continue
			var landing: Vector3 = n.get("landing")
			var dd := _flat(landing - p.global_position)
			if dd > radius_m or absf(landing.y - p.global_position.y) > 2.5:
				continue
			if not bool(n.call("is_landed")):
				tossing = true
				continue
			if dd <= best_d:
				best_d = dd
				best = n
		if best == null:
			if tossing:
				continue
			break
		var buid := String(best.get("uid"))
		tried[buid] = int(tried.get(buid, 0)) + 1
		await walker.walk_to(best.get("landing"), "to drop %s" % buid, {"max_s": 8.0, "retries": 0,
			"stop_when": func() -> bool: return not (ls.call("pickup_target", p.global_position, refused) as Dictionary).is_empty()})
	ls.disconnect(&"drop_picked_up", on_picked)
	ls.disconnect(&"pickup_refused", on_refused)
	var left := 0
	for n: Node3D in (ls.call("nodes") as Dictionary).values():
		if _flat((n.get("landing") as Vector3) - p.global_position) <= radius_m and not refused.has(String(n.get("uid"))):
			left += 1
	out["picked"] = (out["records"] as Array).size()
	out["refused"] = refused.size()
	out["left"] = left
	out["ok"] = left == 0
	_end(i, bool(out["ok"]), "%d picked, %d refused, %d left" % [int(out["picked"]), int(out["refused"]), left])
	return out


# =================================================================================================================
# NPCs and dialogue
# =================================================================================================================

## Walks up to an NPC of the current map until the prompt offers to talk to it ("[F] Talk to ..."), presses the
## interact key and returns read_dialogue() plus "reached_over_props". Approach points lie on rings around the NPC
## (TALK_APPROACH_M, the front first) where the body can stand within TALK_LEAN_M of the talk zone (talk_gap()). Each
## is walked to (routes, then the grid) and, when the walk ends short of the zone (a counter in between), the player
## leans in: up to TALK_LEAN_S of walking straight at the NPC. Other sides are tried when a portal or ladder takes the
## prompt. A point with no path from where the player stands is skipped, and so is every later point at its ground
## height (the same perch, terrace or pocket). On failure: {"open": false, "talk_gap" (m: the closest the body came to
## the talk zone), "why"}. Await it.
func talk_to(npc_id: String) -> Dictionary:
	var i := _begin(PlaytestReport.KIND_PLAY, "talk_to", npc_id)
	var w := world()
	var npc := w.npc_nodes.get(npc_id) as Node3D if w != null else null
	if npc == null or String(npc.call("map_id")) != current_map():
		_end(i, false, "NPC %s is not in %s" % [npc_id, current_map()])
		return {"open": false, "why": "NPC %s is not in %s" % [npc_id, current_map()]}
	if dialogue_open():
		_end(i, false, "a conversation is already open")
		return read_dialogue()
	var talks := func() -> bool: return _prompt_talks_to(npc_id)
	var front := Vector3(npc.global_transform.basis.z.x, 0.0, npc.global_transform.basis.z.z)
	front = front.normalized() if front.length() > 0.01 else Vector3.FORWARD
	var candidates := 0
	var planned := 0
	var unreachable := 0
	var tried := 0
	var leaned := 0
	var props := 0
	var best_gap := talk_gap(npc, player().global_position)
	# Ground heights of approach points with no path from here: the rest of that perch, terrace or pocket is skipped.
	var dead_heights: Array[float] = []
	if not talks.call():
		for dist in TALK_APPROACH_M:
			for k in [0, 1, 7, 2, 6, 3, 5, 4]:
				if tried >= TALK_MAX_TRIES or planned >= TALK_MAX_PLANS:
					break
				var off := front.rotated(Vector3.UP, deg_to_rad(45.0 * k)) * dist
				var goal := walker.grounded(npc.global_position + off + Vector3.UP * 0.5)
				if talk_gap(npc, goal) > TALK_LEAN_M or not walker.standable(goal):
					continue
				candidates += 1
				if dead_heights.any(func(y: float) -> bool: return absf(y - goal.y) < 0.15):
					unreachable += 1
					continue
				planned += 1
				# No way there on the routes or the grid, and not on this tier: walking straight at it cannot work.
				var pl := walker.plan(goal)
				if pl["how"] == "straight" and absf(goal.y - player().global_position.y) > player().model.step_up:
					unreachable += 1
					dead_heights.append(goal.y)
					continue
				tried += 1
				var wr := await walk_to(goal, {"max_s": 25.0, "stop_when": talks})
				props = int(wr.get("props", 0))
				best_gap = minf(best_gap, talk_gap(npc, player().global_position))
				if not talks.call() and talk_gap(npc, player().global_position) <= TALK_LEAN_M:
					leaned += 1
					best_gap = minf(best_gap, await _lean_toward(npc, talks))
				await wait_until(talks, 0.3)
				if talks.call():
					break
			if talks.call() or tried >= TALK_MAX_TRIES or planned >= TALK_MAX_PLANS:
				break
	if not talks.call():
		var inter := interaction()
		var shown := String((inter.get("current") as Dictionary).get("text", "")) if inter != null else ""
		var why := ("the prompt never offered to talk: %d approach points within %.1f m of the talk zone, %d with no path"
			+ " from here, %d walked, %d leaned in; the body came within %.2f m of the talk zone (prompt '%s', %.2f m"
			+ " from the NPC, input block '%s')") % [candidates, TALK_LEAN_M, unreachable, tried, leaned,
			maxf(best_gap, 0.0), shown, player().global_position.distance_to(npc.global_position), w.player_input_block()]
		_end(i, false, why)
		return {"open": false, "talk_gap": snappedf(best_gap, 0.001), "why": why}
	await input.tap_action(&"interact")
	var ok := await wait_until(dialogue_open, UI_TIMEOUT_S)
	var v := read_dialogue()
	v["reached_over_props"] = props
	v["leaned"] = leaned > 0
	_end(i, ok, String(v.get("text", "")).left(80) + (" (reached over %d prop-top cells)" % props if props > 0 else "")
		+ (" (after leaning in)" if leaned > 0 else ""))
	return v


## How far (m) the player's body standing at `feet` is from `npc`'s talk zone; <= 0 inside it. This is the game's rule
## (WorldNpc.in_range): the NPC's talk Area3D (a sphere of interaction_radius_m centred half of it above the NPC's
## feet) overlapping the body capsule, or else the feet within interaction_radius_m of the NPC's feet.
func talk_gap(npc: Node3D, feet: Vector3) -> float:
	var w := world()
	var p := player()
	var radius := w.tuning.num("npc", "interaction_radius_m") if w != null else 0.0
	var fallback := feet.distance_to(npc.global_position) - radius
	var area := npc.get("talk_area") as Area3D
	var zone: CollisionShape3D = null
	if area != null:
		for c in area.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is SphereShape3D:
				zone = c
				break
	var body := p.get_node_or_null(^"CollisionShape3D") as CollisionShape3D if p != null else null
	if zone == null or body == null or not (body.shape is CapsuleShape3D):
		return fallback
	var cap := body.shape as CapsuleShape3D
	var mid := feet + (body.global_position - p.global_position)
	var half := Vector3.UP * maxf(0.0, cap.height * 0.5 - cap.radius)
	var centre := zone.global_position
	var near := Geometry3D.get_closest_point_to_segment(centre, mid - half, mid + half)
	return minf(centre.distance_to(near) - (zone.shape as SphereShape3D).radius - cap.radius, fallback)


## Walks straight at `npc` with real movement input, as a player pressing into a counter: at most TALK_LEAN_S, and
## only while the body keeps getting closer (0.5 s without a gain ends it) and until `talks` holds. Returns the
## smallest talk_gap() reached.
func _lean_toward(npc: Node3D, talks: Callable) -> float:
	var p := player()
	var best := talk_gap(npc, p.global_position)
	var tps := Engine.physics_ticks_per_second
	var f0 := Engine.get_physics_frames()
	var last_gain := f0
	while not bool(talks.call()) and Engine.get_physics_frames() - f0 < roundi(TALK_LEAN_S * tps) \
			and Engine.get_physics_frames() - last_gain < tps / 2:
		var to := npc.global_position - p.global_position
		to.y = 0.0
		if to.length() < 0.05 or p.is_dead() or not bool(session().call("is_idle")):
			break
		input.set_move_world(to.normalized(), p.view_right, p.view_forward)
		await get_tree().process_frame
		input.reassert()
		var g := talk_gap(npc, p.global_position)
		if g < best - 0.005:
			best = g
			last_gain = Engine.get_physics_frames()
	input.release_movement()
	await get_tree().physics_frame
	await get_tree().process_frame
	return minf(best, talk_gap(npc, p.global_position))


func dialogue_open() -> bool:
	var dw := dialogue()
	return dw != null and bool(dw.call("is_open"))


## The conversation on screen: {"open", "type", "npc_id", "text", "buttons", "choices", "selected", "banner",
## "view"}. {"open": false} when none.
func read_dialogue() -> Dictionary:
	var dw := dialogue()
	if dw == null or not bool(dw.call("is_open")):
		return {"open": false}
	var v: Dictionary = dw.get("view")
	return {"open": true, "type": String(v.get("type", "")), "npc_id": String(v.get("npc_id", "")),
		"text": String(dw.call("body_text")), "buttons": Array(dw.call("visible_buttons")),
		"choices": Array(dw.call("choice_texts")), "selected": int(dw.get("selected")),
		"banner": String(dw.call("shown_banner")), "view": v.duplicate(true)}


## Answers the conversation with the window's own keys: a menu choice (its 0-based position, or text it contains:
## the digit key 1-9, else Up/Down + Enter); "yes" / "no" on a Yes/No (Y / N); a button "next" / "ok" (Enter),
## "back" (Backspace) or "end" (the End Chat button). Returns read_dialogue() after it. Await it.
func choose(choice: Variant) -> Dictionary:
	var i := _begin(PlaytestReport.KIND_PLAY, "choose", str(choice))
	var v := read_dialogue()
	if not bool(v["open"]):
		_end(i, false, "no conversation open")
		return v
	var t := String(v["type"])
	var s := str(choice).to_lower()
	var used := ""
	if s in ["end", "end chat"]:
		var dw := dialogue()
		var btn: Variant = (dw.get("buttons") as Dictionary).get("end") if dw.get("buttons") is Dictionary else null
		var clicked := false
		if btn is Control:
			clicked = await _click_control(btn)
		if clicked:
			used = "End Chat (mouse)"
		else:
			await input.tap_key(KEY_ESCAPE)
			used = "Esc"
	elif t == "yes_no" and s in ["yes", "no", "y", "n", "0", "1"]:
		var yes := s in ["yes", "y", "0"]
		await input.tap_key(KEY_Y if yes else KEY_N)
		used = "Y" if yes else "N"
	elif t == "menu":
		var pos := int(choice) if (choice is int or (choice is String and (choice as String).is_valid_int())) else -1
		if pos < 0:
			var texts: Array = v["choices"]
			for k in texts.size():
				if String(texts[k]).to_lower().contains(s):
					pos = k
					break
		if pos < 0 or pos >= (v["choices"] as Array).size():
			_end(i, false, "no choice '%s' in %s" % [choice, v["choices"]])
			return v
		if pos < 9:
			await input.tap_key((KEY_1 + pos) as Key)
			used = str(pos + 1)
		else:
			var steps := pos - int(v["selected"])
			for _k in absi(steps):
				await input.tap_key(KEY_DOWN if steps > 0 else KEY_UP)
			await input.tap_key(KEY_ENTER)
			used = "arrows + Enter"
	elif s in ["next", "ok"] and s in v["buttons"]:
		await input.tap_key(KEY_ENTER)
		used = "Enter"
	elif s == "back" and "back" in v["buttons"]:
		await input.tap_key(KEY_BACKSPACE)
		used = "Backspace"
	else:
		_end(i, false, "'%s' does not answer a %s view (buttons %s)" % [choice, t, v["buttons"]])
		return v
	await frames(2)
	var after := read_dialogue()
	_end(i, true, "%s -> %s" % [used, String(after.get("text", "(closed)")).left(80) if bool(after["open"]) else "(closed)"])
	return after


## Next / OK on a line (Enter). Refused on a Yes/No or a menu (Enter would answer it: use choose()). Await it.
func next() -> Dictionary:
	var v := read_dialogue()
	if bool(v["open"]) and not ("next" in v["buttons"] or "ok" in v["buttons"]):
		var i := _begin(PlaytestReport.KIND_PLAY, "next")
		_end(i, false, "a %s view has no Next/OK: use choose()" % v["type"])
		return v
	return await choose("next" if "next" in v.get("buttons", []) else "ok")


## Closes the conversation with Esc (through the shell's window stack). Returns true when it is closed. Await it.
func close_dialogue() -> bool:
	var i := _begin(PlaytestReport.KIND_PLAY, "close_dialogue")
	if not dialogue_open():
		_end(i, true, "none open")
		return true
	await input.tap_key(KEY_ESCAPE)
	var ok := await wait_until(func() -> bool: return not dialogue_open(), UI_TIMEOUT_S)
	_end(i, ok)
	return ok


# =================================================================================================================
# Windows and shop
# =================================================================================================================

## Opens a character window ("inventory", "equipment", "stats", "quests") with its toggle key. Await it.
func open_window(window_name: String) -> bool:
	return await _toggle_window(window_name, true)


func close_window(window_name: String) -> bool:
	return await _toggle_window(window_name, false)


## Every visible text in a window (labels, rich text, buttons), one per line; "" when it is not open.
func window_text(window_name: String) -> String:
	var wr := windows()
	var w: Node = wr.call("window_by_name", window_name) if wr != null else null
	var i := _begin(PlaytestReport.KIND_OBSERVE, "window_text", window_name)
	if w == null or not bool(w.call("is_open")):
		_end(i, false, "not open")
		return ""
	var t := texts_under(w)
	_end(i, true, "%d chars" % t.length())
	return t


## Visible texts under `root` in tree order, one per line.
func texts_under(root: Node) -> String:
	var lines := PackedStringArray()
	for n in root.find_children("*", "", true, false):
		if not (n is Control) or not (n as Control).is_visible_in_tree():
			continue
		var t := ""
		if n is RichTextLabel:
			t = (n as RichTextLabel).get_parsed_text()
		elif n is Label or n is Button or n is LineEdit:
			t = str(n.get("text"))
		if t.strip_edges() != "":
			lines.append(t.strip_edges())
	return "\n".join(lines)


## Buys `qty` of an item in the open shop with the shop's keys (Tab to Buy, Up/Down to the row, Right/Left to the
## quantity, Enter once the shop's confirm key is armed). Returns {"ok", "message", "mesos_delta", "count_delta",
## "quantity", "result"}. Await it.
func shop_buy(item_id: String, qty: int = 1) -> Dictionary:
	return await _shop_trade("buy", item_id, qty)


## Sells `qty` of an item from its inventory tab in the open shop (Tab to Sell, the tab's digit, Up/Down, Right/Left,
## Enter). Returns like shop_buy. Await it.
func shop_sell(item_id: String, qty: int = 1) -> Dictionary:
	return await _shop_trade("sell", item_id, qty)


func shop_open() -> bool:
	var sw := shop()
	return sw != null and bool(sw.call("is_open"))


func close_shop() -> bool:
	var i := _begin(PlaytestReport.KIND_PLAY, "close_shop")
	if not shop_open():
		_end(i, true, "none open")
		return true
	await input.tap_key(KEY_ESCAPE)
	var ok := await wait_until(func() -> bool: return not shop_open(), UI_TIMEOUT_S)
	_end(i, ok)
	return ok


# =================================================================================================================
# Console (setup only)
# =================================================================================================================

## Runs a debug console command (Debug.run, the console's own path) and waits for a warp it started. Logged as a
## "console" step: setup, never play. Returns the console's answer. Await it.
func console(cmd: String) -> String:
	var i := _begin(PlaytestReport.KIND_CONSOLE, "console", cmd)
	var dbg := debug()
	if dbg == null:
		_end(i, false, "no Debug autoload")
		return ""
	var out := str(dbg.call("run", cmd))
	await frames(1)
	var s := session()
	if s != null and not bool(s.call("is_idle")) and String(s.call("state_name")) != "BOOT":
		await wait_idle()
	_end(i, not out.begins_with("unknown command"), out.left(200).replace("\n", " / "))
	return out


# =================================================================================================================
# Internals
# =================================================================================================================

func _begin(kind: String, step_name: String, detail: String = "") -> int:
	var i := report.begin_step(phase, kind, step_name, detail, game_s(), Time.get_ticks_msec())
	(report.steps[i] as Dictionary)["depth"] = _open_steps.size()
	if log_steps:
		print("PLAYTEST STEP %s[%s] %s%s" % ["  ".repeat(_open_steps.size()), kind, step_name, (" " + detail) if detail != "" else ""])
	_open_steps.append(i)
	return i


func _end(i: int, ok: bool, result: String = "") -> void:
	report.end_step(i, ok, result, game_s(), Time.get_ticks_msec())
	_open_steps.erase(i)
	if log_steps:
		var s: Dictionary = report.steps[i]
		print("PLAYTEST STEP %s  -> %s%s (%.2f s)" % ["  ".repeat(_open_steps.size()), "ok" if ok else "FAILED",
			(" " + result) if result != "" else "", float(s["game_s"])])


## Ends step i with out["issues"] = issues and a summary (plus the issues when it failed). Returns out.
func _end_with(i: int, out: Dictionary, issues: PackedStringArray, summary: String = "") -> Dictionary:
	out["issues"] = issues
	var ok := bool(out.get("ok", false))
	var text := summary
	if not ok and not issues.is_empty():
		text += (" (" if text != "" else "") + "; ".join(issues) + (")" if text != "" else "")
	_end(i, ok, text)
	return out


## Adds the legs' times and distances into out (and keeps the legs). Returns the legs' issues.
func _sum_legs(out: Dictionary, legs: Array) -> PackedStringArray:
	out["legs"] = legs
	var issues := PackedStringArray()
	var t := 0.0
	var dist := 0.0
	for leg: Dictionary in legs:
		t += float(leg.get("time_s", 0.0))
		dist += float(leg.get("distance_m", 0.0))
		issues.append_array(leg.get("issues", PackedStringArray()))
	out["time_s"] = snappedf(t, 0.001)
	out["distance_m"] = snappedf(dist, 0.01)
	return issues


## The UI could not be driven: the outermost open step becomes "api" (shell fallback) with the reason.
func _fallback(i: int, why: String) -> void:
	var top: int = _open_steps[0] if not _open_steps.is_empty() else i
	var s: Dictionary = report.steps[top]
	s["kind"] = PlaytestReport.KIND_API
	s["fallback"] = why
	print("PLAYTEST FALLBACK %s: %s" % [s["name"], why])


## Clicks a control with the mouse; true when it reacted (a button's `pressed`, else the pointer was over it).
func _click_control(c: Control) -> bool:
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		return false
	# Decided before the click: a button often frees itself (and its screen) when pressed, and a freed object
	# compares equal to null afterwards.
	var is_button := c is BaseButton
	var button := c as BaseButton
	if is_button and button.disabled:
		return false
	var fired := [false]
	var cb := func() -> void: fired[0] = true
	if is_button:
		button.pressed.connect(cb)
	var at := c.get_global_transform_with_canvas() * (c.size * 0.5)
	var hovered := await input.click_at(at)
	if is_button:
		if is_instance_valid(button) and button.pressed.is_connected(cb):
			button.pressed.disconnect(cb)
		return fired[0]
	return is_instance_valid(c) and is_instance_valid(hovered) and (hovered == c or c.is_ancestor_of(hovered))


func _fill_creation(char_name: String, gender: String, weapon_id: String, ap: Dictionary) -> String:
	var cs := main.creation
	var model := cs.model
	if not await _click_control(cs.name_edit):
		return "the name field did not take the click"
	if cs.name_edit.text != "":
		await input.tap_key(KEY_END)
		for _k in cs.name_edit.text.length():
			await input.tap_key(KEY_BACKSPACE)
	await input.type_text(char_name)
	if model.name != char_name:
		return "typing the name gave '%s'" % model.name
	if ap.is_empty():
		if not await _click_control(_find_text(cs, "Recommended")):
			return "Recommended did not respond"
	else:
		if not await _click_control(_find_text(cs, "Clear")):
			return "Clear did not respond"
		for stat: String in ap:
			var plus := cs.find_child("Plus_%s" % stat, true, false) as Control
			for _k in int(ap[stat]):
				if not await _click_control(plus):
					return "+ %s did not respond" % stat
	if gender != "":
		# The button that shows the gender's label (CreationScreen.GENDER_LABELS), as a player finds it.
		var gb := _find_text(cs, String(CreationScreen.GENDER_LABELS.get(gender, gender.capitalize())))
		var clicked := await _click_control(gb)
		if not clicked:
			return "the %s button did not respond" % gender
	if weapon_id != "":
		if not await _click_control(cs.find_child("Weapon_%s" % weapon_id, true, false) as Control):
			return "the weapon %s button did not respond" % weapon_id
	if gender != "" and model.gender != gender:
		return "gender is %s" % model.gender
	if weapon_id != "" and model.weapon_id != weapon_id:
		return "weapon is %s" % model.weapon_id
	if not ap.is_empty() and not _same_ap(model.params()["ap"], ap):
		return "AP placed %s, wanted %s" % [model.params()["ap"], ap]
	if not model.is_valid():
		return "the creation is not valid: %s" % ", ".join(model.errors())
	return ""


func _wait_playing(max_s: float) -> bool:
	await wait_until(func() -> bool:
		return not main.flow.is_in(ShellFlow.State.LOADING) and not main.flow.is_in(ShellFlow.State.CREATE), max_s)
	if not main.flow.is_in(ShellFlow.State.PLAYING):
		return false
	return await wait_idle()


func _open_pause_menu() -> bool:
	for _k in 8:
		if main.flow.is_in(ShellFlow.State.PAUSED) and main.pause_menu.visible:
			if bool(main.pause_menu.call("in_sub_panel")):
				main.pause_menu.call("show_main")
			return true
		if not main.flow.is_in(ShellFlow.State.PLAYING):
			return false
		await input.tap_key(KEY_ESCAPE)
		await frames(2)
	return main.flow.is_in(ShellFlow.State.PAUSED)


func _find_text(root: Node, text: String) -> Control:
	if root == null:
		return null
	for n in root.find_children("*", "BaseButton", true, false):
		if str(n.get("text")) == text and (n as Control).is_visible_in_tree():
			return n as Control
	return null


func _prompt_talks_to(npc_id: String) -> bool:
	var inter := interaction()
	if inter == null:
		return false
	var cur: Dictionary = inter.get("current")
	return String(cur.get("kind", "")) == "npc" and String(cur.get("target_id", "")) == npc_id


func _toggle_window(window_name: String, want_open: bool) -> bool:
	var i := _begin(PlaytestReport.KIND_PLAY, "open_window" if want_open else "close_window", window_name)
	var wr := windows()
	if wr == null or wr.call("window_by_name", window_name) == null:
		_end(i, false, "no window '%s'" % window_name)
		return false
	if bool(wr.call("is_open", window_name)) == want_open:
		_end(i, true, "already %s" % ("open" if want_open else "closed"))
		return true
	var action := StringName("toggle_%s" % window_name)
	if not InputMap.has_action(action):
		_end(i, false, "no action %s" % action)
		return false
	await input.tap_action(action)
	var ok := await wait_until(func() -> bool: return bool(wr.call("is_open", window_name)) == want_open, UI_TIMEOUT_S)
	_end(i, ok)
	return ok


func _shop_trade(mode: String, item_id: String, qty: int) -> Dictionary:
	var i := _begin(PlaytestReport.KIND_PLAY, "shop_" + mode, "%s x%d" % [item_id, qty])
	var out := {"ok": false, "message": "", "mesos_delta": 0, "count_delta": 0, "quantity": 0, "result": {}}
	var sw := shop()
	var c := character()
	if sw == null or not bool(sw.call("is_open")) or c == null:
		_end(i, false, "no shop open")
		return out
	if String(sw.get("mode")) != mode:
		await input.tap_key(KEY_TAB)
	var rows: Array = sw.get("buy_rows")
	if mode == "sell":
		var where := c.inventory.find(item_id)
		if where.is_empty():
			_end(i, false, "%s is not in the inventory" % item_id)
			return out
		await input.tap_key((KEY_1 + Inventory.TABS.find(String(where["tab"]))) as Key)
		rows = sw.get("sell_rows")
	var row := -1
	for k in rows.size():
		if String((rows[k] as Dictionary).get("item_id", "")) == item_id:
			row = k
			break
	if row < 0:
		_end(i, false, "%s is not in the %s list" % [item_id, mode])
		return out
	var guard := 0
	while int(sw.get("selected")) != row and guard < 60:
		await input.tap_key(KEY_DOWN if int(sw.get("selected")) < row else KEY_UP)
		guard += 1
	guard = 0
	while int(sw.get("quantity")) != qty and guard < 200:
		var before := int(sw.get("quantity"))
		await input.tap_key(KEY_RIGHT if before < qty else KEY_LEFT)
		guard += 1
		if int(sw.get("quantity")) == before:
			break
	out["quantity"] = int(sw.get("quantity"))
	await wait_until(func() -> bool: return bool(sw.call("confirm_key_armed")), UI_TIMEOUT_S)
	var mesos0 := c.mesos
	var count0 := c.inventory.count(item_id)
	await input.tap_key(KEY_ENTER)
	await frames(2)
	out["result"] = (sw.get("last_result") as Dictionary).duplicate(true)
	out["ok"] = bool((out["result"] as Dictionary).get("ok", false))
	out["message"] = String(sw.get("status_text"))
	out["mesos_delta"] = c.mesos - mesos0
	out["count_delta"] = c.inventory.count(item_id) - count0
	_end(i, bool(out["ok"]), "%s (mesos %+d, count %+d)" % [out["message"], int(out["mesos_delta"]), int(out["count_delta"])])
	return out


func _on_notice(text: String) -> void:
	notices.append(text)


## Two AP spreads place the same points ({} entries of 0 do not count).
static func _same_ap(a: Dictionary, b: Dictionary) -> bool:
	for k: Variant in a:
		if int(a[k]) != int(b.get(k, 0)):
			return false
	for k: Variant in b:
		if int(b[k]) != int(a.get(k, 0)):
			return false
	return true


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


static func _layer_of(c: Node) -> int:
	var n := c.get_parent()
	while n != null:
		if n is CanvasLayer:
			return (n as CanvasLayer).layer
		n = n.get_parent()
	return 0


static func _target_text(target: Variant) -> String:
	if target is Vector3:
		var v := target as Vector3
		return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
	if target is Dictionary and (target as Dictionary).has("local"):
		return "local %s" % str((target as Dictionary)["local"])
	return str(target)


static func _walk_text(r: Dictionary) -> String:
	var s := "%s via %s, %.1f s, %.1f m" % [r.get("result", "?"), r.get("how", "?"), float(r.get("time_s", 0.0)), float(r.get("distance_m", 0.0))]
	if int(r.get("props", 0)) > 0:
		s += ", %d path cells on prop tops" % int(r["props"])
	var issues := PackedStringArray(r.get("issues", PackedStringArray()))
	if not issues.is_empty():
		s += " (" + "; ".join(issues) + ")"
	return s
