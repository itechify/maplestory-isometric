extends Node
## The monster system and the player's attack checked in the real game: res://scenes/main.tscn with real frames,
## physics, autoloads, every subsystem the shell installs, and real input events. Run by
## res://scenes/actors/monster_game_checks.tscn (test_monster_game.gd runs it headless in a child process):
##
##   godot --headless --fixed-fps 60 --path <project> res://scenes/actors/monster_game_checks.tscn
##   godot --resolution 1600x900 --disable-vsync --path <project> res://scenes/actors/monster_game_checks.tscn -- --out <dir>
##
## debug   the console's monster commands, end to end: Debug.run("warp 000000040"), Debug.run("spawn 2 3") makes three
##         real Monsters with no slot, Debug.run("kill all") kills every monster through Monster.debug_kill(): the EXP
##         gained is exactly the canonical EXP of the kills, every drop is from the monster's canonical table and
##         lands on the ground (LootSystem), every slot is dead, no debug spawn is reported to the view, and on the
##         respawn tick the slots (and only the slots) come back
## see     the see-through silhouette as the shell runs it (MonsterSystem._process every frame): a Snail spawned next
##         to the player gets it, fades in and its fills draw; every live monster inside see_through_radius_m has it,
##         every one beyond radius + hysteresis has none and draws no fill; "kill nearest" drops it in the same frame
##         and the system never turns the dying monster back on
## mouse   real mouse and key events (Input.parse_input_event): a click on a HUD button opens its window and never
##         swings, a click shorter than a frame neither; a click on the world swings once; J swings; a click shorter
##         than a frame on the pause menu's Resume (landing while the tree is paused) never swings, and one on the
##         world injected between frames swings once
##
## Output: "MONSTER_CHECK PASS|FAIL <name>[: detail]", "MONSTER_INFO ...", "MONSTER_SHOT <path>" (windowed with
## --out), and finally "MONSTER_CHECKS_DONE <passed> <failed>"; exit code 0 when nothing failed. Saves go to a private
## user://_tests/ directory (user:// is shared with the real game), deleted at the end.

const MAIN_SCENE := "res://scenes/main.tscn"
const MAP := "000000040"
const TIMEOUT_FRAMES := CheckWait.DEFAULT_FRAMES

var main: MainShell = null
var out_dir := ""
var save_dir := ""
var passed := 0
var failed := 0

var _exp_events: Array = []
var _killed: Array = []
var _loot: Array = []
var _spawned_drops: int = 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	out_dir = args[i + 1] if i >= 0 and i + 1 < args.size() else ""
	_run.call_deferred()


func _run() -> void:
	save_dir = "user://_tests/monster_checks_%d" % Time.get_ticks_usec()
	get_node("/root/Saves").set("save_dir", save_dir)
	(get_node("/root/Game") as GameState).autosave_enabled = false
	main = (load(MAIN_SCENE) as PackedScene).instantiate() as MainShell
	main.use_command_line = false
	add_child(main)
	await _frames(2)
	main.start_new_game({"name": "Hunter", "gender": "male", "ap": {"str": 9}, "weapon_id": "541"})
	var ok := await _until(func() -> bool: return not main.flow.is_in(ShellFlow.State.LOADING))
	_check("new game reaches PLAYING", ok and main.flow.is_in(ShellFlow.State.PLAYING), main.last_error_message)
	if main.flow.is_in(ShellFlow.State.PLAYING):
		await _debug_commands()
		await _see_through()
		await _mouse()
	_remove_tree(save_dir)
	print("MONSTER_CHECKS_DONE %d %d" % [passed, failed])
	get_tree().paused = false
	get_tree().quit(0 if failed == 0 else 1)


# --- the console's spawn and kill ---------------------------------------------------------------------------------

func _debug_commands() -> void:
	var dbg := get_node("/root/Debug")
	var session := get_node("/root/MapSession")
	var game := get_node("/root/Game") as GameState
	var db := get_node("/root/Data").get("db") as ContentDB
	var bus := get_node("/root/Events")
	var ms := _monster_system()
	_check("the shell installed the MonsterSystem", ms != null)
	if ms == null:
		return
	var p := main.game_session.player as PlayerController
	_check("the player has its PlayerCombat", p.get_node_or_null(^"PlayerCombat") is PlayerCombat)
	dbg.call("run", "god on")
	var out := String(dbg.call("run", "warp " + MAP))
	_check("warp " + MAP, out.begins_with("warped to " + MAP) or out.begins_with("warping to " + MAP), out)
	await _until(func() -> bool: return bool(session.call("is_idle")) and p.is_on_floor())
	var view := ms.view
	await _until(func() -> bool: return view != null and view.pending_count() == 0 and view.live_count() > 0)
	var inst: MapInstanceState = session.get("instance_state")
	var live := view.live_count()
	_check("%s realized with real monsters" % MAP, live > 0 and live == inst.alive_count(), "%d live, %d alive slots" % [live, inst.alive_count()])

	bus.connect("exp_gained", func(amount: int, source: String) -> void: _exp_events.append([amount, source]))
	bus.connect("monster_killed", func(id: String, map_id: String) -> void: _killed.append([id, map_id]))
	bus.connect("loot_dropped", func(drops: Array, _at: Vector3, map_id: String) -> void: _loot.append([drops, map_id]))
	var loot_system := _loot_system()
	if loot_system != null:
		loot_system.connect("drop_spawned", func(_n: Node) -> void: _spawned_drops += 1)
	var released: Array = []
	view.monster_released.connect(func(n: Node3D, slot_index: int) -> void: released.append([n, slot_index]))

	out = String(dbg.call("run", "spawn 2 3"))
	_check("spawn 2 3", out.begins_with("spawned 3 x Snail (2) in " + MAP), out)
	var builtins: Variant = dbg.get("builtins")
	var spawns: Array = (builtins.get("debug_spawns") as Array).duplicate() if builtins != null else []
	var real := spawns.size() == 3
	for m in spawns:
		real = real and m is Monster and not (m as Monster).has_slot() and (m as Monster).is_debug_spawn() \
			and not (m in view.nodes.values()) and (m as Monster) in ms.live_monsters()
	_check("three real Monsters with no slot, attackable, not tracked by the view", real)
	_check("the spawn leaves the slots alone", inst.alive_count() == live and view.live_count() == live)

	var c := game.character
	var total_before := Progression.total_exp_at(c.level, c.exp, db)
	var kills_before := ms.kills
	# The roll context the kills roll under (contract C2), taken before them: a quest that changed state during the
	# kills must not decide which drops were legal.
	var ctx := DropRoller.context_for(c)
	out = String(dbg.call("run", "kill all"))
	# Read the slots at once: the global spawn tick (7.56 s) may legitimately refill them during the frames awaited below
	# (a flaky failure under full-suite load before this was taken here).
	var alive_after_kill := inst.alive_count()
	var tick_at_kill := inst.last_tick_index
	_check("kill all", out.begins_with("killed %d in %s" % [live + 3, MAP]) and out.contains("through the monster's own death")
		and not out.contains("no EXP/drops"), out)
	_check("every monster died through debug_kill()", ms.kills - kills_before == live + 3, "%d deaths" % (ms.kills - kills_before))
	_check("one monster_killed per kill", _killed.size() == live + 3, "%d" % _killed.size())
	var expected_exp := 0
	for k in _killed:
		expected_exp += int(db.monster(String(k[0]))["exp"])
	var gained := 0
	var from_kills := true
	for e in _exp_events:
		gained += int(e[0])
		from_kills = from_kills and String(e[1]).begins_with("monster:")
	_check("EXP gained = the canonical EXP of the kills", gained == expected_exp and from_kills,
		"gained %d, expected %d" % [gained, expected_exp])
	var total_after := Progression.total_exp_at(c.level, c.exp, db)
	_check("the character holds exactly that much more EXP", total_after - total_before == expected_exp,
		"%d -> %d (Lv %d)" % [total_before, total_after, c.level])
	_info("kill all: %d kills (%d slot monsters + 3 debug Snails), %d EXP, Lv %d" % [_killed.size(), live, gained, c.level])
	var records := 0
	var canonical := true
	for e in _loot:
		records += (e[0] as Array).size()
		canonical = canonical and String(e[1]) == MAP
		for d in e[0]:
			var item := String((d as Dictionary).get("item_id", ""))
			if item != "" and not _in_table(db, _killed, item, ctx):
				canonical = false
	_check("drops announced (loot_dropped)", _loot.size() > 0, "%d kills" % _killed.size())
	_check("every dropped item is a rolling member of a killed monster's canonical drop record, on %s" % MAP, canonical)
	await _frames(3)
	_check("the loot system put every drop on the ground", loot_system != null and _spawned_drops == records,
		"%d records, %d ground drops" % [records, _spawned_drops])
	_info("drops: %d loot_dropped events, %d ground drops" % [_loot.size(), _spawned_drops])
	_check("every slot dead after the kills", alive_after_kill == 0, "%d alive right after kill all" % alive_after_kill)
	if inst.alive_count() > 0:
		_check("slots alive again only through a spawn tick", inst.last_tick_index > tick_at_kill,
			"%d alive, tick %d -> %d" % [inst.alive_count(), tick_at_kill, inst.last_tick_index])
	var debug_released := 0
	for r in released:
		if r[0] in spawns or int(r[1]) < 0:
			debug_released += 1
	_check("the view released only slot monsters", released.size() == live and debug_released == 0,
		"%d released, %d debug" % [released.size(), debug_released])
	await _shot("after_kill_all")

	# The respawn tick: the slots come back, the debug spawns do not.
	await _until_game_time(func() -> bool: return inst.alive_count() >= inst.capacity and view.pending_count() == 0, 30.0)
	var debug_back := 0
	for n in view.nodes.values():
		if (n as Node).has_meta("debug_spawn"):
			debug_back += 1
	for m in ms.live_monsters():
		if m.is_debug_spawn():
			debug_back += 1
	_check("the slots respawn on their tick, and no debug spawn comes back",
		inst.alive_count() == inst.capacity and view.live_count() == inst.capacity and debug_back == 0,
		"%d alive / %d capacity, %d live, %d debug" % [inst.alive_count(), inst.capacity, view.live_count(), debug_back])


## True when `item` can drop from one of the `killed` monsters ([monster id, map id] pairs) under the roll context
## `ctx`: a rolling member of its canonical drop record (DropRates.rolls_item), not merely a member, since a member the
## sources leave unresolved never rolls and a quest-gated one rolls only while its quest is in progress.
static func _in_table(db: ContentDB, killed: Array, item: String, ctx: Dictionary = {}) -> bool:
	for k in killed:
		if DropRates.rolls_item(String(k[0]), item, db, ctx):
			return true
	return false


# --- the see-through silhouette ----------------------------------------------------------------------------------

## Monsters keep walking between the system's update and these reads (~1 m/s, one frame apart), so a monster this
## close to a threshold is left out of the radius checks.
const SEE_MARGIN_M := 0.3


func _see_through() -> void:
	var dbg := get_node("/root/Debug")
	var ms := _monster_system()
	var p := main.game_session.player as Node3D
	if ms == null or p == null:
		return
	var before: Array[Monster] = ms.live_monsters()
	var out := String(dbg.call("run", "spawn 2 1"))
	_check("spawn 2 1 (a Snail next to the player)", out.begins_with("spawned 1 x Snail (2) in " + MAP), out)
	var snail: Monster = null
	for m in ms.live_monsters():
		if not (m in before) and m.is_debug_spawn():
			snail = m
	if snail == null:
		_check("the spawned Snail is live", false)
		return
	var radius := snail.def.see_through_radius_m
	var keep := radius + snail.def.see_through_hysteresis_m
	# No call from here: the shell's own frames run MonsterSystem.update_see_through and MonsterVisual's fade.
	await _until(func() -> bool: return snail.visual.see_through_amount >= 1.0, 120)
	var d := snail.global_position.distance_to(p.global_position)
	_check("the system gave the Snail next to the player its silhouette", snail.visual.is_see_through() and d < radius,
		"%.1f m, on=%s" % [d, snail.visual.is_see_through()])
	var fills := snail.visual.see_through_fills()
	_check("it faded in and its fills draw", snail.visual.see_through_amount >= 1.0 and not fills.is_empty()
		and fills.all(func(f: MeshInstance3D) -> bool: return f.visible),
		"amount %.2f, %d fills" % [snail.visual.see_through_amount, fills.size()])
	# Every live monster follows the radius (and a far one draws no fill once its fade is over).
	await _frames(int(ceil(snail.def.see_through_fade_s * 60.0)) + 2)
	var near := 0
	var far := 0
	var wrong: PackedStringArray = []
	for m in ms.live_monsters():
		var dm := m.global_position.distance_to(p.global_position)
		var on := m.visual.is_see_through()
		var drawn := m.visual.see_through_fills().any(func(f: MeshInstance3D) -> bool: return f.visible)
		if dm < radius - SEE_MARGIN_M:
			near += 1
			if not on:
				wrong.append("%s at %.1f m is off" % [m.name, dm])
		elif dm > keep + SEE_MARGIN_M:
			far += 1
			if on or drawn:
				wrong.append("%s at %.1f m is on (drawn %s)" % [m.name, dm, drawn])
	_check("inside %.0f m every monster has it, beyond %.0f m none draws one" % [radius, keep],
		wrong.is_empty() and near >= 1 and far >= 1, "%d near, %d far: %s" % [near, far, ", ".join(wrong)])
	_info("see-through: %d of %d live monsters within %.0f m, %d beyond %.0f m" % [near, ms.live_monsters().size(), radius, far, keep])
	# The console's kill: the nearest monster dies through its own death path and loses the silhouette at once.
	var live := ms.live_monsters()
	var target: Monster = null
	for m in live:
		if target == null or m.global_position.distance_squared_to(p.global_position) < target.global_position.distance_squared_to(p.global_position):
			target = m
	var had := target != null and target.visual.is_see_through()
	out = String(dbg.call("run", "kill nearest"))
	var dead: Array[Monster] = []
	for m in live:
		if is_instance_valid(m) and not m.is_alive():
			dead.append(m)
	var gone := dead.size() == 1 and dead[0] == target
	_check("kill nearest drops the silhouette in the same frame", gone and had and not target.visual.is_see_through()
		and target.visual.see_through_amount == 0.0
		and target.visual.see_through_fills().all(func(f: MeshInstance3D) -> bool: return not f.visible),
		"%s; %d dead, had %s" % [out, dead.size(), had])
	await _frames(5)
	_check("and the system never turns the dying monster back on", gone and is_instance_valid(target)
		and not target.visual.is_see_through() and target.visual.see_through_fills().all(func(f: MeshInstance3D) -> bool: return not f.visible))
	if is_instance_valid(snail) and snail.is_alive():
		snail.debug_kill()


# --- mouse and keys ----------------------------------------------------------------------------------------------

func _mouse() -> void:
	var hud := _child_of_type(main.ctx().ui_root, "MisoHud")
	var windows := _child_of_type(main.ctx().ui_root, "MisoWindowsRoot")
	var pc := main.game_session.player.get_node_or_null(^"PlayerCombat") as PlayerCombat
	if hud == null or windows == null or pc == null:
		_check("HUD, windows and PlayerCombat present", false)
		return
	var button := (hud.get("status") as MisoStatusBar).menu_buttons.get("inventory") as Button
	var on_button := button.get_global_rect().get_center()
	await _physics(70)
	var before := pc.attacks
	_motion(on_button)
	_click(on_button, true)
	await _physics(4)
	_click(on_button, false)
	await _physics(4)
	_check("a click on the HUD's Item button opens the inventory", bool(windows.call("is_open", "inventory")))
	_check("and never swings", pc.attacks == before, "%d attacks" % (pc.attacks - before))
	_click(on_button, true)
	_click(on_button, false)
	await _physics(4)
	_check("a click shorter than a frame on the button closes it", not bool(windows.call("is_open", "inventory")))
	_check("and never swings either", pc.attacks == before, "%d attacks" % (pc.attacks - before))
	var world := _world_point()
	_check("a point of the screen no control covers", world.x >= 0.0, str(world))
	if world.x < 0.0:
		return
	_click(world, true)
	await _physics(3)
	_click(world, false)
	await _physics(3)
	_check("a click on the world swings once", pc.attacks == before + 1, "%d attacks" % (pc.attacks - before))
	await _physics(70)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = true
	Input.parse_input_event(ev)
	await _physics(3)
	ev = ev.duplicate() as InputEventKey
	ev.pressed = false
	Input.parse_input_event(ev)
	await _physics(3)
	_check("J swings", pc.attacks == before + 2, "%d attacks" % (pc.attacks - before))
	# From here events are injected on a process frame, the normal input path (flushed between iterations, so Input
	# reports a press on the next physics tick).
	# The pause menu's Resume is clicked while the tree, and with it PlayerCombat, is paused; Input still marks
	# "attack" pressed. A click shorter than a frame on it once swung on the first tick after the unpause.
	await _physics(70)
	await _frames(1)
	before = pc.attacks
	_check("the pause menu opens", main.pause())
	await _frames(3)
	var resume := main.pause_menu.resume_button
	var at := resume.get_global_rect().get_center()
	_motion(at)
	await _frames(2)
	_click(at, true)
	_click(at, false)
	await _physics(4)
	_check("a click shorter than a frame on Resume resumes the game", not get_tree().paused)
	_check("and never swings", pc.attacks == before, "%d attacks" % (pc.attacks - before))
	await _physics(70)
	await _frames(1)
	before = pc.attacks
	_motion(world)
	_click(world, true)
	_click(world, false)
	await _physics(4)
	_check("a click shorter than a frame on the world, between frames, swings once", pc.attacks == before + 1,
		"%d attacks" % (pc.attacks - before))


func _world_point() -> Vector2:
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	for fy in [0.42, 0.3, 0.55, 0.65]:
		for fx in [0.5, 0.35, 0.65, 0.25, 0.75]:
			var at := size * Vector2(fx, fy)
			_motion(at)
			if vp.gui_get_hovered_control() == null:
				return at
	return Vector2(-1, -1)


func _click(at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ev.position = get_viewport().get_final_transform() * at
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _motion(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = get_viewport().get_final_transform() * at
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


# --- helpers ----------------------------------------------------------------------------------------------------

func _monster_system() -> MonsterSystem:
	var c := main.ctx()
	if c == null or c.systems == null:
		return null
	for n in c.systems.get_children():
		if n is MonsterSystem:
			return n
	return null


func _loot_system() -> Node:
	var c := main.ctx()
	for n in c.systems.get_children():
		if n is LootSystem:
			return n
		for m in n.get_children():
			if m is LootSystem:
				return m
	return null


static func _child_of_type(root: Node, cls: String) -> Node:
	if root == null:
		return null
	for n in root.get_children():
		var s: Script = n.get_script()
		if s != null and s.get_global_name() == cls:
			return n
	return null


func _shot(label: String) -> void:
	if out_dir == "" or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _frames(30)
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("monster_%s.png" % label)
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("MONSTER_SHOT %s %s" % [path, error_string(err)])


func _check(check_name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("MONSTER_CHECK PASS %s" % check_name)
	else:
		failed += 1
		print("MONSTER_CHECK FAIL %s%s" % [check_name, (": " + detail) if detail != "" else ""])


func _info(text: String) -> void:
	print("MONSTER_INFO " + text)


## Waits until `cond` holds: `max_frames` frames, and a default wait at least CheckWait.DEFAULT_MIN_MS of wall time
## (a headless frame can take under a millisecond; CheckWait).
func _until(cond: Callable, max_frames: int = TIMEOUT_FRAMES) -> bool:
	var n := 0
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()) and CheckWait.keep_waiting(n, max_frames, Time.get_ticks_msec() - t0):
		await get_tree().process_frame
		n += 1
	return bool(cond.call())


## Waits until `cond` holds or `seconds` of game time (Game.clock, what the respawn ticks run on) have passed.
func _until_game_time(cond: Callable, seconds: float) -> bool:
	var game := get_node("/root/Game")
	var until := float(game.get("clock")) + seconds
	while not bool(cond.call()) and float(game.get("clock")) < until:
		await get_tree().process_frame
	return bool(cond.call())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)
