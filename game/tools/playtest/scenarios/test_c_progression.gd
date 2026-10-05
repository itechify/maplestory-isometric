extends PlaytestScenario
## test_c_progression (brief "Test C - Progression", playtester play-C): a CLEAN Beginner levels ONLY by killing
## monsters with the attack key. New game through the real title and creation screens (Wooden Club 585, the 9 creation
## AP as 5 STR + 4 DEX, so base 9/8/4/4), no console EXP, levels or warps. The character walks from the start map
## (000000001) over the trails to the Snail hunting grounds and hunts its way up: 000000040 to level 2, 000000041 to 3,
## 000000042 to 5, then 000000050 and 000001000. Every kill's EXP is checked against the canonical monster EXP
## (monsters/<id>.json exp), an independent EXP model built from formulas/exp_table.json is compared with the character
## and the HUD's EXP gauge after every fight, and every level-up against formulas/beginner.json (+5 AP, +1 SP at 2-10,
## the hp_mp.by_level_1_to_10 table) and the full-heal adaptation (misostory/combat.json level_up.heal). AP goes in
## through the REAL Character Stats window (C, then a mouse click on each "+"), and after every click the window's
## ACC, AVOID, W.DEF, M.DEF, Magic, Speed, Jump, HP/MP and damage range are compared with values computed here from
## the canonical formula data (accuracy.json, derived_stats.json, damage.json, items/585.json, movement.json). At
## levels 1, 5, 8 and 10 the window is compared with MeowDB's character-builder vectors
## (tests/data/parity_vectors.json beginner_lv<N>_synthetic_str_dex_split_wooden_club, whose STR/DEX the AP plan
## meets); the window's STR/DEX/INT/LUK rows are also checked for layout (each value on its name's row). Every landed
## hit is checked against the per-action damage window with the canonical level-gap scale and critical factor, every
## hit must take exactly its damage off the monster's HP (canonical max HP), and every monster touch against
## accuracy.json incoming_damage (bounds cross-checked with MeowDB's avoidability-sim vectors). Like a player, the
## hunter picks up drops with Z (PlaytestKit.pickup: the precise last step into the canonical pickup box) and drinks a
## Red Potion through the Item window (I, Use tab, slot, Use) below 40% HP; without one it rests (PlaytestKit.rest:
## away from the monsters, standing still for natural HP recovery) to 80%. A death is handled as a player does: OK on
## the notice, the canonical EXP penalty is checked, and the character walks back from town. The
## scenario reloads the process after level 5 (persistence check, then the stat window is re-verified) and keeps
## hunting in later phases until PLAYC_TARGET (env, default 10), the per-phase budget or MAX_PHASE. Travel, deaths,
## potions, pickups and screenshots are PlaytestKit's. Run it with
##   ISOLATE=play-C bash scripts/playtest.sh test_c_progression --out _scratch/play-C/<dir> --seed 1

const WEAPON := "585"
const CREATION_AP := {"str": 5, "dex": 4}
const CHAR_NAME := "ProgC"
## Where to hunt while the level is below `until` (the canonical spawns: 40 Snails; 41 Snail/Blue Snail; 42 adds a Red
## Snail; 50 Blue Snail/Shroom/Red Snail; 1000 adds Orange Mushrooms).
const HUNT_PLAN := [
	{"map": "000000040", "until": 2},
	{"map": "000000041", "until": 3},
	{"map": "000000042", "until": 5},
	{"map": "000000050", "until": 7},
	{"map": "000001000", "until": 101},
]
## The 5 AP of each level, clicked in this order. 3/2 and 2/3 STR/DEX splits whose totals meet MeowDB's
## synthetic_str_dex_split vectors: 19/18 at level 5, 26/26 at level 8, 31/31 at level 10.
const AP_PLAN := {
	2: ["str", "dex", "str", "dex", "str"],
	3: ["dex", "str", "dex", "str", "dex"],
	4: ["str", "dex", "str", "dex", "str"],
	5: ["dex", "str", "dex", "str", "dex"],
	6: ["dex", "str", "dex", "str", "dex"],
	7: ["str", "dex", "str", "dex", "str"],
	8: ["dex", "str", "dex", "str", "dex"],
	9: ["str", "dex", "str", "dex", "str"],
	10: ["dex", "str", "dex", "str", "dex"],
}
const PARITY_LEVELS := [1, 5, 8, 10]
const PHASE0_TARGET := 5
const MAX_PHASE := 2
const PHASE_BUDGET_S := 2900.0
const HUNT_BUDGET_S := 2650.0
const SEARCH_M := 60.0
const PARITY_FILE := "res://tests/data/parity_vectors.json"
## A player drinks a Red Potion (picked up from kills) through the Item window below this share of Max HP.
const POTION := "270"
const POTION_AT := 0.4

var d: PlaytestDriver = null
var db: ContentDB = null
var kit: PlaytestKit = null
var final_target := 10

# --- the independent model -------------------------------------------------------------------------------------
var model_level := 1
var model_exp := 0
var base_model := {}
var allocated_through := 1
var prev := {}
var last_hp := 0

# --- what this phase saw ---------------------------------------------------------------------------------------
var exp_events := 0
var exp_total := 0
var exp_mismatch: Array = []
var other_exp: Array = []
var death_exp: Array = []
var kills := 0
var kills_by_id := {}
var level_kills := {}
var level_exp := 0
var level_deaths := 0
var levelup_issues: Array = []
var levelups_checked := 0
var ui_pending: Array = []
var ui_issues: Array = []
var progress_checks := 0
var progress_issues: Array = []
var window_checks := 0
var window_issues: Array = []
var layout_reads := 0
var layout_issues: Array = []
var snapshot_issues: Array = []
var clicks := 0
var click_issues: Array = []
var click_rows: Array = []
var hits_checked := 0
var hits_out: Array = []
var misses := 0
var crits := 0
var whiffs := 0
var per_target := {}
var kills_hp_checked := 0
var hits_per_kill := {}
var hp_issues: Array = []
var level_travel_s := 0.0
var touches := 0
var dodges := 0
var touch_by_id := {}
var touch_out: Array = []
var hp_snap := {}
var fresh_kills := 0
var survivor_kills := 0
var loot_pending := false
var pickups := 0
var pickup_steps := 0
var potions_used := 0
var potion_issues: Array = []
var potion_rows: Array = []
## Rests below 40% HP without a potion, and their game seconds.
var rests := 0
var rest_s := 0.0
## Where the player stood (map-local, rounded to 1 m) when a target could not be reached: cell -> count, plus samples.
var unreachable_cells := {}
var unreachable_samples: Array = []
var attack_ctx := {}
var deaths: Array = []
## How many of PlaytestKit.deaths this phase already took into `deaths`.
var deaths_seen := 0
var fights := 0
var fight_fail := {}
var timeline: Array = []
var parity_rows: Array = []
var exp_vector_issues: Array = []

# --- clocks ----------------------------------------------------------------------------------------------------
var play_offset_s := 0.0
var wall_offset_s := 0.0
var phase_play0 := 0.0
var wall0_ms := 0
var level_t0 := 0.0

var _vectors: Array = []
var _bus: Node = null
var _mon: Node = null
var _pc: Node = null


func description() -> String:
	return "Test C: a clean Beginner levels only by killing monsters (real attacks, real trails), AP through the real Character Stats window, every number against canonical data and MeowDB vectors"


func max_seconds() -> float:
	return PHASE_BUDGET_S + 200.0


func run(p_d: PlaytestDriver) -> void:
	d = p_d
	db = d.db()
	kit = PlaytestKit.new(d)
	final_target = int(OS.get_environment("PLAYC_TARGET")) if OS.get_environment("PLAYC_TARGET") != "" else 10
	wall0_ms = Time.get_ticks_msec()
	if d.phase == 0:
		if not await _start_new():
			return
	else:
		if not await _resume():
			return
	var target := mini(final_target, PHASE0_TARGET) if d.phase == 0 else final_target
	await _hunt(target)
	if d.character().ap > 0 and not kit.is_dead():
		await _allocate()
	_phase_checks()
	var c := d.character()
	if c.level < final_target and d.phase < MAX_PHASE:
		_save_carry()
		d.note("phase %d ends at level %d (%d / %d EXP) after %.0f s of play: reloading the process (Quit Game, Continue)"
			% [d.phase, c.level, c.exp, _need(c.level), _play_s()])
		await d.reload_process()
		return
	_final_report()


# =================================================================================================================
# Phase starts
# =================================================================================================================

func _start_new() -> bool:
	var ng: Dictionary = await d.new_game(CHAR_NAME, "male", WEAPON, CREATION_AP)
	if not d.check("new game through the real screens (no api fallback)", bool(ng["ok"]) and String(ng["via"]) == "screen",
			"%s via %s %s" % [ng["map"], ng["via"], ng["why"]]):
		if not bool(ng["ok"]):
			return false
	var c := d.character()
	var beg := db.formula("beginner")
	var start: Dictionary = beg["starting_stats"]
	base_model = {}
	for k in ["str", "dex", "int", "luk"]:
		base_model[k] = int(start[k]) + int(CREATION_AP.get(k, 0))
	var hm := _hp_mp_row(1)
	d.check("a clean level-1 Beginner (canonical beginner.json: level, 0 EXP, 0 SP, every creation AP placed, HP/MP row 1)",
		c.level == int(beg["starting_level"]) and c.exp == 0 and c.sp == 0 and c.ap == 0 and c.job == "beginner"
		and _same_stats(c.base_stats, base_model) and c.base_max_hp == int(hm["hp"]) and c.base_max_mp == int(hm["mp"])
		and c.hp == int(hm["hp"]) and c.mp == int(hm["mp"]) and c.equipment.weapon_id() == WEAPON,
		"lv %d exp %d ap %d sp %d stats %s HP %d/%d MP %d/%d weapon %s" % [c.level, c.exp, c.ap, c.sp, c.base_stats, c.hp,
			c.base_max_hp, c.mp, c.base_max_mp, c.equipment.weapon_id()])
	d.check("starts in the canonical start map 000000001", d.current_map() == "000000001", d.current_map())
	model_level = 1
	model_exp = 0
	allocated_through = 1
	_snap_prev()
	last_hp = c.hp
	phase_play0 = d.game_s()
	level_t0 = 0.0
	_connect()
	_verify_progress("start")
	# Level 1: the stat window before anything happens.
	if await d.open_window("stats"):
		await d.frames(2)
		var win := kit.stats_window()
		_verify_window(win, "L1 at creation")
		var any_plus := false
		for s: String in win.plus_buttons:
			any_plus = any_plus or (win.plus_buttons[s] as Control).is_visible_in_tree()
		d.check("no '+' buttons with 0 AP at level 1", not any_plus)
		_parity(win, 1)
		_touch_parity(1)
		await kit.shot("L1_stats_window")
		await d.close_window("stats")
	else:
		window_issues.append("C did not open the stats window at level 1")
	# The trip to the hunting ground on foot.
	var t0 := d.game_s()
	var ok := await _travel(String(HUNT_PLAN[0]["map"]))
	d.check("walked from 000000001 to Snail Hunting Ground I over the trails", ok,
		"%.1f s; %s" % [d.game_s() - t0, kit.travel_text()])
	timeline.append({"event": "arrived 000000040", "play_s": snappedf(_play_s(), 0.1), "wall_s": snappedf(_wall_s(), 0.1)})
	return true


func _resume() -> bool:
	var cg: Dictionary = await d.continue_game()
	if not d.check("Continue loads the hunter (phase %d)" % d.phase, bool(cg["ok"]), str(cg)):
		return false
	_restore()
	var c := d.character()
	var saved: Dictionary = d.carry.get("character", {})
	d.check("level, EXP, AP, SP, base stats and base HP/MP survive Quit Game + Continue",
		c.level == int(saved.get("level", -1)) and c.exp == int(saved.get("exp", -1)) and c.ap == int(saved.get("ap", -1))
		and c.sp == int(saved.get("sp", -1)) and _same_stats(c.base_stats, saved.get("stats", {}))
		and c.base_max_hp == int(saved.get("base_max_hp", -1)) and c.base_max_mp == int(saved.get("base_max_mp", -1)),
		"now lv %d exp %d ap %d sp %d stats %s HP %d MP %d; saved %s" % [c.level, c.exp, c.ap, c.sp, c.base_stats,
			c.base_max_hp, c.base_max_mp, saved])
	d.soft_check("the hunter resumes in the map it left", d.current_map() == String(d.carry.get("map", "")),
		"%s, left %s" % [d.current_map(), d.carry.get("map", "")])
	_snap_prev()
	last_hp = c.hp
	phase_play0 = d.game_s()
	_connect()
	_verify_progress("resume")
	# The reloaded character's stat window: every derived number from the saved base stats and level.
	if await d.open_window("stats"):
		await d.frames(2)
		_verify_window(kit.stats_window(), "L%d after Continue" % c.level)
		await d.close_window("stats")
	else:
		window_issues.append("C did not open the stats window after Continue")
	return true


# =================================================================================================================
# Hunting
# =================================================================================================================

func _hunt(target: int) -> void:
	var exclude := {}
	var idle := 0
	var slot_i := 0
	var last_map := ""
	while d.character().level < target and d.game_s() - phase_play0 < HUNT_BUDGET_S:
		_ensure_connected()
		if kit.is_dead():
			await _handle_death()
			continue
		var want := _hunt_map(d.character().level)
		if d.current_map() != want:
			await _travel(want)
			continue
		if d.current_map() != last_map:
			last_map = d.current_map()
			exclude.clear()
		if d.character().ap > 0:
			await _allocate()
			continue
		var c := d.character()
		if c.hp < POTION_AT * StatCalculator.max_hp(c, db) and c.inventory.count(POTION) > 0 and potion_issues.size() < 5:
			await _drink()
			continue
		if c.hp < POTION_AT * StatCalculator.max_hp(c, db) and c.inventory.count(POTION) == 0:
			# No potion: rest as a player does (PlaytestKit.rest: away from the monsters, standing still for natural
			# recovery, fighting back what it can beat) until 80% of Max HP.
			var rs := await kit.rest(PlaytestKit.HP_RESUME)
			rests += 1
			rest_s += rs
			continue
		var opts := {"max_dist_m": SEARCH_M, "exclude": exclude}
		var target_node := d.nearest_monster(opts)
		if target_node == null:
			idle += 1
			if idle % 4 == 0:
				var slots: Array = d.world().defs.get_def(d.current_map()).monster_spawn_definitions
				if not slots.is_empty():
					slot_i = (slot_i + 7) % slots.size()
					await d.walk_to("slot:%d" % slot_i, {"max_s": 20.0})
				exclude.clear()
			else:
				await d.wait(1.0)
			continue
		idle = 0
		var lv0 := d.character().level
		var r: Dictionary = await d.face_and_attack_nearest(20.0, opts)
		fights += 1
		whiffs += int(r["whiffs"])
		if not bool(r["ok"]):
			var why := String(r["why"]).get_slice(" (", 0)
			fight_fail[why] = int(fight_fail.get(why, 0)) + 1
			if why.begins_with("could not reach"):
				_log_unreachable(target_node, String(r["why"]))
			if why.begins_with("could not reach") or why.begins_with("still alive"):
				if is_instance_valid(target_node):
					exclude[target_node.get_instance_id()] = true
		if exclude.size() > 25:
			exclude.clear()
		if bool(r["ok"]) and loot_pending and not kit.is_dead():
			loot_pending = false
			var pk: Dictionary = await kit.pickup(4.0, 8.0)
			pickups += int(pk["picked"])
			pickup_steps += 1
		await d.frames(1)
		_verify_progress("fight %d" % fights)
		_check_ui_pending()
		if d.character().level > lv0 and kit.shots < 2:
			await kit.shot("levelup_L%d_hud" % d.character().level)
		if d.character().level == 3 and d.character().exp * 2 >= _need(3) and not d.carry.has("shot_mid"):
			d.carry["shot_mid"] = true
			await kit.shot("L3_exp_bar_half")


func _log_unreachable(target_node: Node3D, why: String) -> void:
	var st := d.state()
	var loc: Vector3 = st.get("local", Vector3.ZERO)
	var cell := "%s (%d, %d, %d)" % [d.current_map(), roundi(loc.x), roundi(loc.y), roundi(loc.z)]
	unreachable_cells[cell] = int(unreachable_cells.get(cell, 0)) + 1
	if unreachable_samples.size() < 12:
		var mloc := Vector3.ZERO
		if is_instance_valid(target_node) and d.world() != null:
			mloc = d.world().defs.get_def(d.current_map()).to_local(target_node.global_position)
		unreachable_samples.append("%s player local (%.1f, %.1f, %.1f) on_floor %s, target local (%.1f, %.1f, %.1f): %s" % [
			d.current_map(), loc.x, loc.y, loc.z, st.get("on_floor", false), mloc.x, mloc.y, mloc.z, why])


func _hunt_map(level: int) -> String:
	for row: Dictionary in HUNT_PLAN:
		if level < int(row["until"]):
			return String(row["map"])
	return String(HUNT_PLAN[HUNT_PLAN.size() - 1]["map"])


## Walks map by map (PlaytestKit.travel_to: the canonical portals, walk_trail, the survival policy on the way). A hop
## that fails twice is a soft failure and a console warp (setup, flagged) so the run can go on.
func _travel(to_map: String) -> bool:
	var t0 := d.game_s()
	var ok := await kit.travel_to(to_map, {"fallback_warp": true})
	level_travel_s += d.game_s() - t0
	_absorb_deaths()
	return ok


## A death as a player handles it (PlaytestKit.respawn: the notice's OK, the respawn), then this phase's bookkeeping.
func _handle_death() -> void:
	await kit.respawn({"shot": "death_notice"})
	_absorb_deaths()


## Takes the deaths the kit handled (in a hunt or on a trail) into this phase's rows.
func _absorb_deaths() -> void:
	while deaths_seen < kit.deaths.size():
		var row: Dictionary = (kit.deaths[deaths_seen] as Dictionary).duplicate()
		deaths_seen += 1
		row["play_s"] = snappedf(_play_s(), 0.1)
		row["kills_so_far"] = kills
		deaths.append(row)
		level_deaths += 1
		last_hp = d.character().hp
		if not bool(row.get("respawned", false)):
			ui_issues.append("death %d: no respawn after OK (notice %s, clicked %s)" % [deaths.size(), row.get("notice"),
				row.get("ok_clicked")])


# =================================================================================================================
# AP through the Character Stats window
# =================================================================================================================

func _allocate() -> void:
	var c := d.character()
	if c.ap <= 0 or kit.is_dead():
		return
	if not await d.open_window("stats"):
		window_issues.append("L%d: C did not open the stats window" % c.level)
		return
	await d.frames(2)
	var win := kit.stats_window()
	# Right after the level-up, before any click: only the level term of ACC (2 x Level) and HP/MP have moved.
	_verify_window(win, "L%d before AP" % c.level)
	var attacks0 := int(d.combat().get("attacks"))
	while c.ap > 0 and allocated_through < c.level:
		var lv := allocated_through + 1
		var seq: Array = AP_PLAN.get(lv, ["str", "dex", "str", "dex", "str"])
		var row := PackedStringArray()
		for stat: String in seq:
			if c.ap <= 0:
				break
			var ap0 := c.ap
			var before := _window_numbers(win)
			var r: Dictionary = await kit.click_plus(stat)
			clicks += 1
			if bool(r["click"]):
				base_model[stat] = int(base_model[stat]) + 1
			if not bool(r["click"]) or c.ap != ap0 - 1 or c.get_base_stat(stat) != int(base_model[stat]):
				click_issues.append("L%d '+' %s: click %s, AP %d -> %d, %s %d (model %d)" % [lv, stat, r["click"], ap0, c.ap,
					stat, c.get_base_stat(stat), int(base_model[stat])])
			var after := _window_numbers(win)
			_verify_window(win, "L%d after +%s" % [lv, stat])
			row.append("+%s: %s %s->%s, ACC %s->%s, AVOID %s->%s, DMG %s->%s" % [stat.to_upper(), stat.to_upper(),
				before[stat], after[stat], before["acc"], after["acc"], before["avoid"], after["avoid"], before["damage"],
				after["damage"]])
			if lv == 2 and clicks == 2:
				await kit.shot("L2_stats_mid_allocation")
		click_rows.append("L%d: %s" % [lv, "; ".join(row)])
		allocated_through = lv
	var any_plus := false
	for s: String in win.plus_buttons:
		any_plus = any_plus or (win.plus_buttons[s] as Control).is_visible_in_tree()
	if c.ap == 0 and any_plus:
		click_issues.append("L%d: a '+' is still visible at 0 AP" % c.level)
	if int(d.combat().get("attacks")) != attacks0:
		click_issues.append("L%d: the '+' clicks swung the weapon (%d attacks)" % [c.level, int(d.combat().get("attacks")) - attacks0])
	if c.level in PARITY_LEVELS:
		_parity(win, c.level)
		_touch_parity(c.level)
		if c.level == 5:
			await kit.shot("L5_stats_after_AP")
	await d.close_window("stats")
	_snap_prev()


## A Red Potion through the real Item window (PlaytestKit.drink: I, the Use tab, a click on the potion's slot, the
## Use button): one used, HP + the canonical restore, capped at Max HP.
func _drink() -> void:
	var c := d.character()
	var r: Dictionary = await kit.drink(POTION)
	potions_used += 1
	potion_rows.append(String(r["row"]))
	if not bool(r["ok"]) or int(r["hp1"]) != int(r["want_hp"]):
		potion_issues.append("%s%s" % [r["row"], "" if bool(r["ok"]) else " (%s)" % r["status"]])


func _window_numbers(win: MisoStatsWindow) -> Dictionary:
	var out := {}
	for key in ["str", "dex", "int", "luk", "acc", "avoid", "damage", "wdef", "mdef", "magic", "hp", "mp", "level", "exp"]:
		out[key] = win.value_text(key)
	return out


## Every number the window shows against the independent expectation (and the game's own StatCalculator).
func _verify_window(win: MisoStatsWindow, tag: String) -> void:
	window_checks += 1
	var c := d.character()
	var e := _expect(c.level, base_model)
	var need := _need(c.level)
	var want := {
		"level": str(c.level), "str": str(base_model["str"]), "dex": str(base_model["dex"]), "int": str(base_model["int"]),
		"luk": str(base_model["luk"]), "acc": str(e["acc"]), "avoid": str(e["avoid"]), "wdef": str(e["wdef"]),
		"mdef": str(e["mdef"]), "magic": str(e["magic"]), "speed": "%d%%" % int(e["speed"]), "jump": "%d%%" % int(e["jump"]),
		"damage": "%s ~ %s" % [MisoTheme.thousands(int(e["damage_min"])), MisoTheme.thousands(int(e["damage_max"]))],
		"hp": "%s / %s" % [MisoTheme.thousands(c.hp), MisoTheme.thousands(int(e["max_hp"]))],
		"mp": "%s / %s" % [MisoTheme.thousands(c.mp), MisoTheme.thousands(int(e["max_mp"]))],
		"exp": "%s / %s  (%.2f%%)" % [MisoTheme.thousands(c.exp), MisoTheme.thousands(need), 100.0 * float(c.exp) / float(need)],
	}
	var bad := PackedStringArray()
	for k: String in want:
		if win.value_text(k) != String(want[k]):
			bad.append("%s shows '%s', expected '%s'" % [k, win.value_text(k), want[k]])
	if win.ap_label.text != str(c.ap):
		bad.append("AP shows '%s', character %d" % [win.ap_label.text, c.ap])
	for s in ["str", "dex", "int", "luk"]:
		var vis := (win.plus_buttons[s] as Control).is_visible_in_tree()
		if vis != (c.ap > 0):
			bad.append("'+' %s visible=%s with %d AP" % [s, vis, c.ap])
	if not bad.is_empty():
		window_issues.append("%s: %s" % [tag, "; ".join(bad)])
	# Layout: each stat's name label must sit on the row of its value (the label before it in the 3-column grid).
	var rows := PackedStringArray()
	for st in ["str", "dex", "int", "luk"]:
		var v := win.values[st] as Label
		var grid := v.get_parent()
		var name_l := grid.get_child(v.get_index() - 1) as Control
		var dy := absf(name_l.get_global_rect().position.y - v.get_global_rect().position.y)
		var right := v.get_global_rect().position.x > name_l.get_global_rect().position.x
		if dy > 2.0 or not right:
			rows.append("%s: name '%s' at (%.0f, %.0f), value '%s' at (%.0f, %.0f)" % [st, name_l.get("text"),
				name_l.get_global_rect().position.x, name_l.get_global_rect().position.y, v.text, v.get_global_rect().position.x,
				v.get_global_rect().position.y])
	layout_reads += 1
	if not rows.is_empty():
		layout_issues.append("%s (AP %d): %s" % [tag, c.ap, "; ".join(rows)])
	# The game's own calculator against the independent numbers (a rules bug, not a UI one).
	var snap := StatCalculator.snapshot(c, db)
	var sbad := PackedStringArray()
	for k in ["acc", "avoid", "wdef", "mdef", "damage_min", "damage_max", "max_hp", "max_mp", "speed", "jump"]:
		if int(snap[k]) != int(e[k]):
			sbad.append("%s %d vs %d" % [k, int(snap[k]), int(e[k])])
	if int(snap["matk"]) != int(e["magic"]):
		sbad.append("magic %d vs %d" % [int(snap["matk"]), int(e["magic"])])
	if not sbad.is_empty():
		snapshot_issues.append("%s: StatCalculator %s" % [tag, ", ".join(sbad)])


## The stat window against MeowDB's character builder (parity_vectors.json), when the base stats match its inputs.
func _parity(win: MisoStatsWindow, level: int) -> void:
	var case_id := "beginner_lv%d_synthetic_str_dex_split_wooden_club" % level
	var v := _vector(case_id, "character_stats_and_damage_window")
	if v.is_empty():
		d.soft_check("parity vector %s exists" % case_id, false)
		return
	var ap_in: Dictionary = v["inputs"]["ap"]
	var same_inputs := int(v["inputs"]["level"]) == d.character().level and _same_stats(ap_in, base_model) \
		and String(v["inputs"]["weapon_item_id"]) == WEAPON
	var st: Dictionary = v["outputs"]["stats"]
	var dm: Dictionary = v["outputs"]["beginnerDamage"]
	var want := {
		"acc": str(int(st["acc"])), "avoid": str(int(st["avoid"])), "wdef": str(int(st["wdef"])), "mdef": str(int(st["mdef"])),
		"magic": str(int(st["matk"])), "speed": "%d%%" % int(st["speed"]), "jump": "%d%%" % int(st["jump"]),
		"damage": "%d ~ %d" % [int(dm["min"]), int(dm["max"])],
		"str": str(int(st["str"])), "dex": str(int(st["dex"])), "int": str(int(st["int"])), "luk": str(int(st["luk"])),
	}
	var bad := PackedStringArray()
	for k: String in want:
		if win.value_text(k) != String(want[k]):
			bad.append("%s '%s' vs MeowDB '%s'" % [k, win.value_text(k), want[k]])
	var c := d.character()
	var mx_hp := StatCalculator.max_hp(c, db)
	var mx_mp := StatCalculator.max_mp(c, db)
	if mx_hp != int(st["hp"]) or mx_mp != int(st["mp"]):
		bad.append("max HP/MP %d/%d vs MeowDB %d/%d" % [mx_hp, mx_mp, int(st["hp"]), int(st["mp"])])
	parity_rows.append("L%d %s: ACC %s AVOID %s DMG %s W.DEF %s M.DEF %s Magic %s HP %d MP %d (MeowDB acc %d avoid %d dmg %d-%d hp %d mp %d)"
		% [level, case_id, win.value_text("acc"), win.value_text("avoid"), win.value_text("damage"), win.value_text("wdef"),
			win.value_text("mdef"), win.value_text("magic"), mx_hp, mx_mp, int(st["acc"]), int(st["avoid"]), int(dm["min"]),
			int(dm["max"]), int(st["hp"]), int(st["mp"])])
	d.check("L%d: the stat window equals MeowDB's character builder (%s)" % [level, case_id], same_inputs and bad.is_empty(),
		("inputs differ: vector %s, model %s; " % [ap_in, base_model] if not same_inputs else "") + "; ".join(bad))


## The contact-damage bounds used above against MeowDB's avoidability-sim vectors for this build at this level.
func _touch_parity(level: int) -> void:
	var bad := PackedStringArray()
	var n := 0
	for id in ["1", "2", "3", "4", "5", "9"]:
		var v := _vector("beginner_lv%d_synthetic_str_dex_split_vs_%s" % [level, id], "avoid_and_incoming_damage_vs_monster")
		if v.is_empty():
			continue
		n += 1
		var b := _touch_bounds(id, level, base_model)
		var ph: Dictionary = v["outputs"]["physical"]
		if int(b["min"]) != int(ph["takenMin"]) or int(b["max"]) != int(ph["takenMax"]):
			bad.append("%s: %d-%d vs MeowDB %d-%d" % [id, int(b["min"]), int(b["max"]), int(ph["takenMin"]), int(ph["takenMax"])])
	d.check("L%d: contact damage bounds = MeowDB avoidability-sim for every Maple Island monster" % level, n > 0 and bad.is_empty(),
		"%d monsters; %s" % [n, "; ".join(bad)])


# =================================================================================================================
# Signals: EXP, level-ups, hits
# =================================================================================================================

func _connect() -> void:
	_bus = d.events()
	_bus.connect(&"exp_gained", _on_exp)
	_bus.connect(&"leveled_up", _on_level)
	_bus.connect(&"hp_changed", _on_hp)
	_bus.connect(&"player_damaged", _on_player_damaged)
	_bus.connect(&"player_missed_by", _on_player_missed_by)
	_bus.connect(&"loot_dropped", _on_loot)
	_ensure_connected()


func _ensure_connected() -> void:
	var m := d.monsters()
	if m != _mon and m != null:
		_mon = m
		m.connect(&"monster_died", _on_monster_died)
	var pc := d.combat()
	if pc != _pc and pc != null:
		_pc = pc
		pc.connect(&"attack_started", _on_attack_started)
		pc.connect(&"attack_resolved", _on_attack_resolved)


func _on_exp(amount: int, source: String) -> void:
	if source.begins_with("monster:"):
		var id := source.substr(8)
		var want := int(db.monster(id).get("exp", -1))
		exp_events += 1
		exp_total += amount
		level_exp += amount
		kills_by_id[id] = int(kills_by_id.get(id, 0)) + 1
		level_kills[id] = int(level_kills.get(id, 0)) + 1
		if amount != want and exp_mismatch.size() < 20:
			exp_mismatch.append("monster %s gave %d, canonical %d" % [id, amount, want])
		_model_add(amount)
	elif source == "death":
		var c := d.character()
		var pen: Dictionary = db.formula("death")["exp_penalty"]
		var clamp_r: Array = pen.get("calculator_luk_clamp", [4, 999])
		var luk := clampi(int(base_model["luk"]), int(clamp_r[0]), int(clamp_r[1]))
		var loss := floori(float(_need(model_level)) * (float(pen["base_loss_pct"]) + float(pen["luk_term_numerator"]) / luk) / 100.0)
		var expected := mini(loss, model_exp)
		death_exp.append({"level": c.level, "lost": -amount, "expected": expected, "exp_before": model_exp})
		model_exp = maxi(0, model_exp + amount)
	else:
		other_exp.append("%s %+d" % [source, amount])
		_model_add(amount)


func _model_add(amount: int) -> void:
	model_exp += amount
	while model_level < Progression.level_cap(db) and model_exp >= _need(model_level):
		model_exp -= _need(model_level)
		model_level += 1


func _on_hp(hp: int, _max_hp: int) -> void:
	last_hp = hp


## A landed touch against accuracy.json incoming_damage: Raw = trunc(P.DMG x ratio / 100) x uniform(1.1, 1.5),
## Taken = Raw x (1 - WDEF / (WDEF + 5 (Lv + 40) + 1.2 Raw)), trunc(clamp(...)). WDEF = floor(STR / 4) (no gear).
func _on_player_damaged(amount: int, mob_id: String) -> void:
	var c := d.character()
	var b := _touch_bounds(mob_id, c.level, base_model)
	touches += 1
	var t: Dictionary = touch_by_id.get(mob_id, {"n": 0, "min": 1 << 30, "max": 0, "sum": 0})
	t["n"] = int(t["n"]) + 1
	t["min"] = mini(int(t["min"]), amount)
	t["max"] = maxi(int(t["max"]), amount)
	t["sum"] = int(t["sum"]) + amount
	touch_by_id[mob_id] = t
	if (amount < int(b["min"]) or amount > int(b["max"])) and touch_out.size() < 20:
		touch_out.append("L%d touched by %s for %d, canonical %d-%d" % [c.level, mob_id, amount, int(b["min"]), int(b["max"])])


func _on_player_missed_by(_mob_id: String) -> void:
	dodges += 1


func _on_loot(_drops: Array, _at: Vector3, _map_id: String) -> void:
	loot_pending = true


func _touch_bounds(mob_id: String, level: int, base: Dictionary) -> Dictionary:
	var inc: Dictionary = db.formula("accuracy")["incoming_damage"]
	var der: Dictionary = db.formula("derived_stats")["formulas"]
	var wdef := float(floori(int(base["str"]) / float(der["wdef"]["divisor"])))
	var eff := float(int(float(db.monster(mob_id)["physical_damage"]) * float(inc["touch_attack_ratio"]) / 100.0))
	var dc: Dictionary = inc["defense_curve"]
	var out := {}
	for k in ["min", "max"]:
		var raw := eff * float(inc["roll"][k])
		var taken := raw * (1.0 - wdef / (wdef + float(dc["def_level_multiplier"]) * (level + float(dc["def_level_offset"]))
			+ float(dc["raw_coefficient"]) * raw))
		out[k] = int(clampf(taken, float(inc["clamp"]["min"]), float(inc["clamp"]["max"])))
	return out


## Game.gain_exp has already applied every level of the award when the first leveled_up arrives; check the batch at
## its last level against the character as it was before (prev).
func _on_level(lv: int) -> void:
	var c := d.character()
	if lv != c.level:
		return
	levelups_checked += 1
	var beg := db.formula("beginner")
	var n := c.level - int(prev["level"])
	var ap_want := int(prev["ap"]) + n * int(beg["ap"]["ap_per_level"])
	var sp_levels: Array = beg["sp"]["sp_levels"]
	var sp_want := int(prev["sp"])
	for l in range(int(prev["level"]) + 1, c.level + 1):
		if l >= int(sp_levels[0]) and l <= int(sp_levels[1]):
			sp_want += int(beg["sp"]["sp_per_level"])
	var rates: Dictionary = db.formula("hp_mp_gain")["per_class"]["beginner"]
	var hm := _hp_mp_row(c.level)
	var bad := PackedStringArray()
	if c.ap != ap_want:
		bad.append("AP %d, expected %d" % [c.ap, ap_want])
	if c.sp != sp_want:
		bad.append("SP %d, expected %d" % [c.sp, sp_want])
	if c.base_max_hp != int(prev["base_max_hp"]) + n * int(rates["max_hp_per_level"]) or c.base_max_hp != int(hm["hp"]):
		bad.append("base max HP %d (was %d), expected +%d = %d (by_level table %d)" % [c.base_max_hp, int(prev["base_max_hp"]),
			n * int(rates["max_hp_per_level"]), int(prev["base_max_hp"]) + n * int(rates["max_hp_per_level"]), int(hm["hp"])])
	if c.base_max_mp != int(prev["base_max_mp"]) + n * int(rates["max_mp_per_level"]) or c.base_max_mp != int(hm["mp"]):
		bad.append("base max MP %d (was %d), expected %d" % [c.base_max_mp, int(prev["base_max_mp"]), int(hm["mp"])])
	var heal := String((db.miso_table("combat") as Dictionary)["level_up"]["heal"])
	if heal == "full" and (c.hp != StatCalculator.max_hp(c, db) or c.mp != StatCalculator.max_mp(c, db)):
		bad.append("not fully healed: HP %d/%d MP %d/%d" % [c.hp, StatCalculator.max_hp(c, db), c.mp, StatCalculator.max_mp(c, db)])
	var ev := _vector("level_%d" % c.level, "exp_requirement")
	if not ev.is_empty() and int(ev["outputs"]["exp_to_next_level"]) != _need(c.level):
		exp_vector_issues.append("L%d: canonical exp_to_next %d, MeowDB calculator %d" % [c.level, _need(c.level),
			int(ev["outputs"]["exp_to_next_level"])])
	if not bad.is_empty():
		levelup_issues.append("L%d: %s" % [c.level, "; ".join(bad)])
	var prev_ev := _vector("level_%d" % (c.level - 1), "exp_requirement")
	var meow_kills: Dictionary = prev_ev["outputs"]["kills_lv_to_next_by_monster"] if not prev_ev.is_empty() else {}
	timeline.append({
		"event": "level %d" % c.level, "play_s": snappedf(_play_s(), 0.1), "wall_s": snappedf(_wall_s(), 0.1),
		"char_play_time_s": snappedf(c.play_time_s, 0.1), "level_s": snappedf(_play_s() - level_t0, 0.1),
		"map": d.current_map(), "kills": level_kills.duplicate(), "exp_from_kills": level_exp, "deaths": level_deaths,
		"travel_s": snappedf(level_travel_s, 0.1), "exp_carried": c.exp,
		"hp_before_heal": last_hp, "hp_after": c.hp, "max_hp": StatCalculator.max_hp(c, db), "mp_after": c.mp,
		"ap": c.ap, "sp": c.sp, "meowdb_kills_from_0": meow_kills,
	})
	level_t0 = _play_s()
	level_travel_s = 0.0
	level_kills = {}
	level_exp = 0
	level_deaths = 0
	ui_pending.append({"level": c.level, "ap": c.ap})
	prev["level"] = c.level
	prev["ap"] = c.ap
	prev["sp"] = c.sp
	prev["base_max_hp"] = c.base_max_hp
	prev["base_max_mp"] = c.base_max_mp


## Counts deaths only: MonsterSystem emits monster_died after Game.gain_exp (after a level-up), so kills per level are
## counted from the EXP awards instead.
func _on_monster_died(_m: Node) -> void:
	kills += 1


func _on_attack_started(_action: String, _presentation: String, _lockout: float) -> void:
	var c := d.character()
	attack_ctx = {"level": c.level, "base": c.base_stats.duplicate()}
	# Every live monster's HP just before the swing: a hit must take exactly its damage off.
	hp_snap.clear()
	var ms := d.monsters()
	if ms != null:
		for m: Node in ms.call("live_monsters"):
			if is_instance_valid(m):
				hp_snap[m.get_instance_id()] = int(m.get("hp"))


## A landed hit against its action's window: MIN/MAX of damage.json's published formulas, the level-gap scale, the
## critical factor, then trunc(clamp(...)). Maple Island monsters have P.DEF 0, no element and AVOID 0.
func _on_attack_resolved(target: Node, res: DamageResult) -> void:
	if target == null or res == null:
		return
	if res.missed:
		misses += 1
		return
	var def: Variant = target.get("def")
	if def == null or int(def.stats.pdef) != 0:
		return
	var ctx := attack_ctx if not attack_ctx.is_empty() else {"level": d.character().level, "base": d.character().base_stats}
	var raw := _raw_range(ctx["base"], res.action)
	if raw.is_empty():
		return
	var scale := _level_scale(int(def.stats.level) - int(ctx["level"]))
	var crit := 1.0
	if res.critical:
		crits += 1
		crit = 1.0 + float(db.formula("damage")["critical"]["base_damage_d"])
	var lo := _final(float(raw["min"]) * scale * crit - 1e-9)
	var hi := _final(float(raw["max"]) * scale * crit + 1e-9)
	hits_checked += 1
	var key := target.get_instance_id()
	var pre := int(hp_snap.get(key, -1))
	if pre >= 0:
		var canon := int(db.monster(def.id).get("hp", -1))
		var hp_now := int(target.get("hp"))
		var alive := bool(target.call("is_alive"))
		var after_want := maxi(0, pre - res.final)
		var rec: Dictionary = per_target.get(key, {"start": pre, "hits": 0})
		rec["hits"] = int(rec["hits"]) + 1
		if (hp_now != after_want or alive != (after_want > 0) or pre > canon or int(def.max_hp) != canon) and hp_issues.size() < 20:
			hp_issues.append("%s: HP %d - hit %d left %d (alive %s), expected %d; canonical HP %d, def max_hp %d" % [def.id, pre,
				res.final, hp_now, alive, after_want, canon, int(def.max_hp)])
		if alive:
			per_target[key] = rec
		else:
			per_target.erase(key)
			kills_hp_checked += 1
			if int(rec["start"]) == canon:
				fresh_kills += 1
				var hist: Dictionary = hits_per_kill.get(def.id, {})
				hist[int(rec["hits"])] = int(hist.get(int(rec["hits"]), 0)) + 1
				hits_per_kill[def.id] = hist
			else:
				survivor_kills += 1
	if (res.final < lo or res.final > hi) and hits_out.size() < 20:
		hits_out.append("L%d %s vs %s (lv %d): %d outside %d-%d%s" % [int(ctx["level"]), res.action, def.id, int(def.stats.level),
			res.final, lo, hi, " crit" if res.critical else ""])


# =================================================================================================================
# The independent formulas (canonical data only)
# =================================================================================================================

func _need(level: int) -> int:
	var levels: Array = db.formula("exp_table")["levels"]
	for row: Dictionary in levels:
		if int(row["level"]) == level:
			return int(row["exp_to_next"])
	return 0


func _hp_mp_row(level: int) -> Dictionary:
	var hm: Dictionary = db.formula("beginner")["hp_mp"]
	for row: Dictionary in hm["by_level_1_to_10"]:
		if int(row["level"]) == level:
			return {"hp": int(row["hp"]), "mp": int(row["mp"])}
	return {"hp": int(hm["base_hp"]) + int(hm["hp_per_level"]) * (level - 1),
		"mp": int(hm["base_mp"]) + int(hm["mp_per_level"]) * (level - 1)}


func _expect(level: int, base: Dictionary) -> Dictionary:
	var acc_f: Dictionary = db.formula("accuracy")
	var spec: Dictionary = acc_f["derived_accuracy"]["by_job"]["beginner"]
	var co: Dictionary = acc_f["derived_accuracy"]["stat_coefficients"]
	var eva: Dictionary = acc_f["avoidability"]
	var der: Dictionary = db.formula("derived_stats")["formulas"]
	var mv: Dictionary = db.formula("movement")
	var s := int(base["str"])
	var x := int(base["dex"])
	var i := int(base["int"])
	var l := int(base["luk"])
	var common := float(co["dex"]) * x + float(co["level"]) * level + float(co["luk"]) * l
	var raw := _raw_range(base, "")
	var hm := _hp_mp_row(level)
	return {
		"acc": floori(common / float(spec["divisor"]) + float(spec["constant"])),
		"avoid": floori(l / float(eva["luk_divisor"])) + floori(x / float(eva["dex_divisor"])) + int(eva["constant"]),
		"wdef": floori(s / float(der["wdef"]["divisor"])),
		"mdef": floori(i / float(der["mdef"]["divisor"])),
		"magic": floori(i / float(der["magic"]["divisor"])),
		"speed": int(mv["base_speed"]), "jump": int(mv["base_jump"]),
		"damage_min": _final(float(raw["min"])), "damage_max": _final(float(raw["max"])),
		"max_hp": int(hm["hp"]), "max_mp": int(hm["mp"]),
	}


## Raw MIN / MAX of a basic attack with the Wooden Club, before defense, level gap and crits (damage.json physical:
## MIN = WATK x (0.8 + (Primary x M x WeaponMult + Secondary) / 100), MAX = WATK x (1.0 + (Primary x WeaponMult +
## Secondary) / 100), M = 0.08 with no mastery). action "" = the stat window: the lowest MIN and highest MAX over the
## weapon's basic actions (items/585.json weapon.basic_attack_mix_pct).
func _raw_range(base: Dictionary, action: String) -> Dictionary:
	var ph: Dictionary = db.formula("damage")["physical"]
	var item := db.item(WEAPON)
	var wpn: Dictionary = item["weapon"]
	var watk := float(item["stats"]["watk"])
	var fam := {}
	for f: Dictionary in ph["weapon_families"]:
		if String(f["label"]).contains("Blunt"):
			fam = f
	var primary := float(base[String(fam["primary"]).to_lower()])
	var secondary := float(base[String(fam["secondary"]).to_lower()])
	var m := float(ph["mastery"]["no_mastery_factor"])
	var b0 := float(ph["base_roll"]["min"])
	var b1 := float(ph["base_roll"]["max"])
	var sd := float(ph["ordinary_divisors"]["stat_div"])
	var lo := INF
	var hi := -INF
	for a: String in wpn["basic_attack_mix_pct"]:
		if wpn["basic_attack_mix_pct"][a] == null or float(wpn["basic_attack_mix_pct"][a]) <= 0.0:
			continue
		if action != "" and a != action:
			continue
		var wm := float(wpn["multipliers"][a])
		lo = minf(lo, watk * (b0 + (primary * m * wm + secondary) / sd))
		hi = maxf(hi, watk * (b1 + (primary * wm + secondary) / sd))
	if lo == INF:
		return {}
	return {"min": lo, "max": hi}


func _level_scale(gap: int) -> float:
	var br: Array = db.formula("damage")["level_gap"]["branches"]
	if gap <= 0:
		return 1.0
	if gap < 10:
		return 1.0 / (1.0 + gap * gap * float(br[1]["coefficient"]))
	return 1.0 / (1.0 + gap * float(br[2]["coefficient"]))


func _final(v: float) -> int:
	var fc: Dictionary = db.formula("damage")["final_clamp"]
	return int(clampf(v, float(fc["min"]), float(fc["max"])))


func _vector(case_id: String, mechanic: String = "") -> Dictionary:
	if _vectors.is_empty():
		var f := FileAccess.open(PARITY_FILE, FileAccess.READ)
		if f == null:
			return {}
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			_vectors = (j as Dictionary).get("vectors", [])
	for v: Dictionary in _vectors:
		if String(v.get("case_id", "")) == case_id and (mechanic == "" or String(v.get("mechanic", "")) == mechanic):
			return v
	return {}


# =================================================================================================================
# Per-fight verification
# =================================================================================================================

func _verify_progress(tag: String) -> void:
	progress_checks += 1
	var c := d.character()
	var hud := d.hud() as MisoHud
	var bad := PackedStringArray()
	if c.level != model_level or c.exp != model_exp:
		bad.append("character lv %d %d EXP, canonical model lv %d %d EXP" % [c.level, c.exp, model_level, model_exp])
	var need := _need(c.level)
	var g := hud.status.exp_gauge
	if g.current != c.exp or g.maximum != need:
		bad.append("EXP gauge %d/%d, expected %d/%d" % [g.current, g.maximum, c.exp, need])
	var txt := "%s / %s   [%.2f%%]" % [MisoTheme.thousands(c.exp), MisoTheme.thousands(need), 100.0 * float(c.exp) / float(need)]
	if g.value_label.text != txt:
		bad.append("EXP text '%s', expected '%s'" % [g.value_label.text, txt])
	if absf(g.ratio() - float(c.exp) / float(need)) > 1e-6:
		bad.append("EXP fill %.4f, expected %.4f" % [g.ratio(), float(c.exp) / float(need)])
	if hud.status.level_label.text != str(c.level):
		bad.append("Lv label '%s'" % hud.status.level_label.text)
	if not bad.is_empty() and progress_issues.size() < 20:
		progress_issues.append("%s: %s" % [tag, "; ".join(bad)])


## After a level-up: the HUD log's two lines and the orange Stat button with the AP count.
func _check_ui_pending() -> void:
	if ui_pending.is_empty():
		return
	var hud := d.hud() as MisoHud
	var lines := hud.log_panel.texts()
	for p: Dictionary in ui_pending:
		var lv := int(p["level"])
		var key := MisoUiEnv.key_label("toggle_stats")
		var congrats := "Congratulations! You have reached level %d." % lv
		var ap_line := "You have %d AP to distribute (press %s)." % [int(p["ap"]), key]
		if not (congrats in lines):
			ui_issues.append("L%d: no '%s' in the HUD log" % [lv, congrats])
		if not (ap_line in lines):
			ui_issues.append("L%d: no '%s' in the HUD log" % [lv, ap_line])
	var c := d.character()
	var btn: Button = hud.status.menu_buttons["stats"]
	if c.ap > 0 and not btn.text.ends_with("+%d" % c.ap):
		ui_issues.append("L%d: the Stat button reads '%s' with %d AP" % [c.level, btn.text, c.ap])
	ui_pending.clear()


# =================================================================================================================
# Reports
# =================================================================================================================

func _phase_checks() -> void:
	var c := d.character()
	d.check("phase %d: levels gained only by killing monsters (no quest or other EXP source)" % d.phase,
		other_exp.is_empty(), ", ".join(other_exp))
	d.check("phase %d: every kill gave its canonical monster EXP" % d.phase, exp_events > 0 and exp_mismatch.is_empty(),
		"%d EXP events, %d EXP, %d kills %s; %s" % [exp_events, exp_total, kills, kills_by_id, "; ".join(exp_mismatch)])
	d.check("phase %d: one EXP award per monster death" % d.phase, exp_events == kills, "%d awards, %d deaths" % [exp_events, kills])
	d.check("phase %d: level, EXP and the HUD EXP gauge follow the canonical EXP table after every fight" % d.phase,
		progress_issues.is_empty(), "%d fights checked; %s" % [progress_checks, "; ".join(progress_issues)])
	d.check("phase %d: every level-up gives +AP, +SP, the canonical HP/MP and the full heal" % d.phase,
		levelup_issues.is_empty(), "%d level-ups; %s" % [levelups_checked, "; ".join(levelup_issues)])
	d.check("phase %d: canonical EXP to next level = MeowDB's EXP calculator for each level reached" % d.phase,
		exp_vector_issues.is_empty(), "; ".join(exp_vector_issues))
	d.check("phase %d: the HUD announces each level-up (log lines, Stat button +AP)" % d.phase, ui_issues.is_empty(),
		"; ".join(ui_issues))
	if clicks > 0:
		d.check("phase %d: AP spent through the stats window's '+' buttons (mouse), one point per click, no swing" % d.phase,
			click_issues.is_empty(), "%d clicks; %s" % [clicks, "; ".join(click_issues)])
	d.check("phase %d: the stats window's numbers equal the canonical formulas after every click" % d.phase,
		window_issues.is_empty() and window_checks > 0, "%d window reads; %s" % [window_checks, "; ".join(window_issues)])
	d.check("phase %d: the stats window shows each stat's value on its name's row (STR/DEX/INT/LUK grid)" % d.phase,
		layout_issues.is_empty(), "%d reads, %d misaligned; first: %s" % [layout_reads, layout_issues.size(),
			"; ".join(layout_issues.slice(0, 2))])
	d.check("phase %d: StatCalculator agrees with the independent formulas" % d.phase, snapshot_issues.is_empty(),
		"; ".join(snapshot_issues))
	if hits_checked > 0:
		d.check("phase %d: every landed hit lies in its action's canonical damage window (level gap, crit)" % d.phase,
			hits_out.is_empty(), "%d hits (%d crits); %s" % [hits_checked, crits, "; ".join(hits_out)])
	if kills_hp_checked > 0:
		d.check("phase %d: monster HP is canonical and every hit takes exactly its damage off (the killing hit crosses 0)" % d.phase,
			hp_issues.is_empty(), "%d kills (%d from full canonical HP, %d survivors met again with their HP kept); hits per fresh kill %s; %s"
				% [kills_hp_checked, fresh_kills, survivor_kills, hits_per_kill, "; ".join(hp_issues)])
	if touches > 0:
		d.check("phase %d: every monster touch dealt the canonical contact damage (accuracy.json incoming_damage)" % d.phase,
			touch_out.is_empty(), "%d touches, %d dodged; per monster %s; %s" % [touches, dodges, touch_by_id, "; ".join(touch_out)])
	d.check("phase %d: no MISS against AVOID-0 monsters (MeowDB accuracy-sim hitRate 100)" % d.phase, misses == 0,
		"%d misses in %d hits" % [misses, hits_checked])
	var dbad := PackedStringArray()
	for x: Dictionary in death_exp:
		if int(x["lost"]) != int(x["expected"]):
			dbad.append("L%d lost %d, canonical %d" % [int(x["level"]), int(x["lost"]), int(x["expected"])])
	if not death_exp.is_empty():
		d.check("phase %d: each death took the canonical EXP penalty" % d.phase, dbad.is_empty(), "%s" % [death_exp])
	if potions_used > 0:
		d.soft_check("phase %d: Red Potions drunk through the Item window restore the canonical 100 HP" % d.phase,
			potion_issues.is_empty(), "%d potions; %s" % [potions_used, "; ".join(potion_issues)])
	d.soft_check("phase %d: the hunter never died (below 40%% HP it drinks a Red Potion, or rests for natural recovery)"
		% d.phase, deaths.is_empty(), "%d deaths, %d rests (%.0f s): %s" % [deaths.size(), rests, rest_s, deaths])
	d.soft_check("phase %d: every trail walked on foot (no console fallback)" % d.phase, kit.fallbacks.is_empty(),
		", ".join(kit.fallbacks))
	d.note("phase %d: %d fights, %d kills %s, %d EXP from kills, %d landed hits checked (%d crits), %d whiffs, fight failures %s"
		% [d.phase, fights, kills, kills_by_id, exp_total, hits_checked, crits, whiffs, fight_fail])
	d.note("phase %d travel: %s; survival on the trails %s" % [d.phase, kit.travel_text(), kit.survival])
	d.note("phase %d loot and potions: %d pickups in %d stops, %d mesos, %d Red Potions drunk, %d in the bag; %s" % [d.phase, pickups,
		pickup_steps, d.character().mesos, potions_used, d.character().inventory.count(POTION), " | ".join(potion_rows.slice(0, 6))])
	d.note("phase %d incoming: %d touches, %d dodged, per monster %s" % [d.phase, touches, dodges, touch_by_id])
	if not unreachable_cells.is_empty():
		var cells := unreachable_cells.keys()
		cells.sort_custom(func(a: Variant, b: Variant) -> bool: return int(unreachable_cells[a]) > int(unreachable_cells[b]))
		var top := PackedStringArray()
		for k: Variant in cells.slice(0, 8):
			top.append("%s x%d" % [k, int(unreachable_cells[k])])
		d.note("phase %d unreachable targets: %d, where the player stood (map-local, 1 m cells): %s" % [d.phase,
			int(fight_fail.get("could not reach the monster", 0)), ", ".join(top)])
		for x: String in unreachable_samples:
			d.note("unreachable sample: " + x)
	var lost := 0
	var maps := {}
	var resp := PackedStringArray()
	for x: Dictionary in death_exp:
		lost += int(x["lost"])
	for x: Dictionary in deaths:
		var k := "%s L%d" % [x["map"], int(x["level"])]
		maps[k] = int(maps.get(k, 0)) + 1
		resp.append("%s %d HP" % [x["respawn_map"], int(x["hp_after"])])
	d.note("phase %d deaths: %d (%s), %d EXP lost to the death penalty against %d EXP from kills; respawns %s"
		% [d.phase, deaths.size(), maps, lost, exp_total, ", ".join(resp.slice(0, 4))])
	for r: String in click_rows:
		d.note("AP " + r)
	for r: String in parity_rows:
		d.note("parity " + r)
	d.note("phase %d ends: level %d, %d / %d EXP, AP %d, SP %d, stats %s, HP %d/%d, MP %d/%d, play %.1f s, wall %.1f s"
		% [d.phase, c.level, c.exp, _need(c.level), c.ap, c.sp, c.base_stats, c.hp, StatCalculator.max_hp(c, db), c.mp,
			StatCalculator.max_mp(c, db), _play_s(), _wall_s()])


func _final_report() -> void:
	var all: Array = d.carry.get("timeline_all", []).duplicate()
	all.append_array(timeline)
	var c := d.character()
	d.check("reached level 5 or more by killing monsters only", c.level >= 5, "level %d" % c.level)
	for row: Dictionary in all:
		if String(row["event"]).begins_with("level"):
			d.note("PACE %s at %.1f s of play (+%.1f s for this level, %.1f s of it on trails; game's play_time %.1f s; wall %.1f s) in %s: kills %s = %d EXP (%d carried over), deaths %d, HP %d -> %d/%d; MeowDB kills from 0 EXP %s"
				% [row["event"], float(row["play_s"]), float(row["level_s"]), float(row.get("travel_s", 0.0)),
					float(row["char_play_time_s"]), float(row["wall_s"]), row["map"], row["kills"], int(row["exp_from_kills"]),
					int(row.get("exp_carried", 0)), int(row["deaths"]), int(row["hp_before_heal"]), int(row["hp_after"]),
					int(row["max_hp"]), row["meowdb_kills_from_0"]])
		else:
			d.note("PACE %s at %.1f s of play (wall %.1f s)" % [row["event"], float(row["play_s"]), float(row["wall_s"])])
	d.carry["timeline_all"] = all
	d.carry["deaths_all"] = (d.carry.get("deaths_all", []) as Array) + deaths
	d.note("final: level %d, %d / %d EXP after %.1f s of play over %d phase(s); deaths overall %d"
		% [c.level, c.exp, _need(c.level), _play_s(), d.phase + 1, (d.carry["deaths_all"] as Array).size()])


func _save_carry() -> void:
	var c := d.character()
	var all: Array = d.carry.get("timeline_all", []).duplicate()
	all.append_array(timeline)
	d.carry["timeline_all"] = all
	d.carry["deaths_all"] = (d.carry.get("deaths_all", []) as Array) + deaths
	d.carry["model"] = {"level": model_level, "exp": model_exp, "base": base_model.duplicate(), "allocated_through": allocated_through}
	d.carry["character"] = {"level": c.level, "exp": c.exp, "ap": c.ap, "sp": c.sp, "stats": c.base_stats.duplicate(),
		"base_max_hp": c.base_max_hp, "base_max_mp": c.base_max_mp}
	d.carry["map"] = d.current_map()
	d.carry["play_s"] = _play_s()
	d.carry["wall_s"] = _wall_s()
	d.carry["level_t0"] = level_t0
	d.carry["level_acc"] = {"kills": level_kills.duplicate(), "exp": level_exp, "deaths": level_deaths, "travel_s": level_travel_s}


func _restore() -> void:
	var m: Dictionary = d.carry.get("model", {})
	model_level = int(m.get("level", 1))
	model_exp = int(m.get("exp", 0))
	base_model = (m.get("base", {}) as Dictionary).duplicate()
	allocated_through = int(m.get("allocated_through", 1))
	play_offset_s = float(d.carry.get("play_s", 0.0))
	wall_offset_s = float(d.carry.get("wall_s", 0.0))
	level_t0 = float(d.carry.get("level_t0", 0.0))
	var acc: Dictionary = d.carry.get("level_acc", {})
	level_kills = (acc.get("kills", {}) as Dictionary).duplicate()
	level_exp = int(acc.get("exp", 0))
	level_deaths = int(acc.get("deaths", 0))
	level_travel_s = float(acc.get("travel_s", 0.0))


func _snap_prev() -> void:
	var c := d.character()
	prev = {"level": c.level, "ap": c.ap, "sp": c.sp, "base_max_hp": c.base_max_hp, "base_max_mp": c.base_max_mp}


func _play_s() -> float:
	return play_offset_s + (d.game_s() - phase_play0)


func _wall_s() -> float:
	return wall_offset_s + (Time.get_ticks_msec() - wall0_ms) / 1000.0


static func _same_stats(a: Dictionary, b: Dictionary) -> bool:
	for k in ["str", "dex", "int", "luk"]:
		if int(a.get(k, -1)) != int(b.get(k, -2)):
			return false
	return true
