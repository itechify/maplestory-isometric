extends PlaytestScenario
## test_f_death: brief Test F (death), by play-F. The character dies to real monster contact in three areas (Snail
## Hunting Ground I 000000040, A Split Road 000000050, The Field West of Amherst 000001000), each time quitting while
## dead and reloading in a new process, then dies three more times through the death notice's OK: with Maria's
## conversation open (000000050), on the walkable trail 000000050 -> 000001000, and mid-jump (000001020). Every death
## checks the death state (input off through real keys, the notice, the HUD HP gauge at 0), the EXP penalty computed by
## this scenario from formulas/death.json and formulas/exp_table.json (base LUK varied between deaths: 4, 7, 13, 23),
## the respawn at the canonical returnMap's spawn (misostory/death.json respawn_player_spawn_index), the respawn HP/MP
## (misostory/death.json respawn_vitals), the save written at the death (read from disk while dead), the penalty taken
## exactly once across a quit and a reload, and inventory, equipment, mesos and quest state diffed before and after.
##
## Setup (marked): console warps, level/EXP/AP, items, mesos and quests; HP lowered to 1 (and MP below max) through
## Game.change_hp/change_mp as an api step, because the console has no command that sets HP. The killing blow is
## always a real MonsterSystem touch while the player walks (or hops) into a monster with real input.

const SHG1 := "000000040"
const SPLIT := "000000050"
const FIELD_W := "000001000"
const FIELD_E := "000001020"
const MARIA := "10"
const LETTER_QUEST := "1007"
const LETTER_ITEM := "439"
const KILL_QUEST := "1006"
const DONE_QUEST := "1000"
const SNAIL := "2"
const DEATH_CANON := "res://data/canonical/formulas/death.json"
const EXP_TABLE := "res://data/canonical/formulas/exp_table.json"
const DEATH_MISO := "res://data/misostory/death.json"
const DIFF_KEYS := ["name", "gender", "job", "level", "base_stats", "ap", "sp", "fame", "mesos", "skills",
	"inventory", "equipment", "quests", "quickslots", "base_max_hp", "base_max_mp"]
const MAX_JUMP_TRIES := 3
const TRAIL_STOP_M := 5.0
const SPAWN_TOLERANCE_M := 1.0

var _canon_death: Dictionary = {}
var _exp_rows: Array = []
var _miso_death: Dictionary = {}


func description() -> String:
	return "Test F: real monster-touch deaths in 000000040, 000000050, 000001000 (quit while dead + reload each), " \
		+ "then with a dialogue open, on a trail and mid-jump (OK on the notice)"


func max_seconds() -> float:
	return 1500.0


func run(d: PlaytestDriver) -> void:
	_load_tables()
	match d.phase:
		0:
			await _phase0(d)
		1, 2:
			await _phase_after_quit(d)
		3:
			await _phase3(d)
		4:
			await _phase4(d)


# =================================================================================================================
# Phases
# =================================================================================================================

func _phase0(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Mortal", "female", "585", {"str": 9})
	if not d.check("new game through the screens", bool(ng["ok"]) and ng["via"] == "screen",
			"%s via %s %s" % [ng["slot"], ng["via"], ng["why"]]):
		return
	var parity: Dictionary = _canon_death.get("exp_penalty", {}).get("parity_example", {})
	var pl := _expected_loss(int(parity.get("level", 0)), int(parity.get("base_luk", 0)))
	d.check("the scenario's penalty formula reproduces MeowDB's parity example",
		int(pl["loss"]) == int(parity.get("loss", -1)),
		"Lv %d LUK %d: loss %d, MeowDB %d" % [int(parity.get("level", 0)), int(parity.get("base_luk", 0)), int(pl["loss"]),
			int(parity.get("loss", -1))])
	await d.console("warp " + SHG1)
	if not d.check("in Snail Hunting Ground I", d.current_map() == SHG1, d.current_map()):
		return
	await d.console("quest accept " + KILL_QUEST)
	await d.console("quest accept " + DONE_QUEST)
	await d.console("quest complete %s force" % DONE_QUEST)
	await d.console("give red potion 5")
	await d.console("mesos 777")
	await d.wait(1.0)
	var kills := [0]
	var on_kill := func(mob_id: String, _map_id: String) -> void:
		if mob_id == SNAIL:
			kills[0] += 1
	d.events().connect(&"monster_killed", on_kill)
	var f: Dictionary = await d.fight_until(func() -> bool: return kills[0] >= 2, 180.0, {"mob_id": SNAIL})
	d.events().disconnect(&"monster_killed", on_kill)
	d.check("two Snails killed with the attack key (quest %s kill progress)" % KILL_QUEST, kills[0] >= 2,
		"%d kills, %d attacks, %d hits" % [kills[0], int(f["attacks"]), int(f["hits"])])
	await d.pickup_all_nearby(8.0, 40.0)
	await d.console("level 10")
	await d.console("exp 1500")
	var s := d.state()
	var q: Dictionary = s["quests"]
	d.check("setup: level 10 with EXP, a quest in progress, a quest completed, items and mesos",
		int(s["level"]) == 10 and int(s["exp"]) > 0 and KILL_QUEST in q["in_progress"] and DONE_QUEST in q["completed"]
			and not (s["inventory"] as Dictionary).is_empty() and int(s["mesos"]) > 0,
		"Lv %d, EXP %d, quests %s, mesos %d, inventory %s" % [int(s["level"]), int(s["exp"]), str(q), int(s["mesos"]),
			str(s["inventory"])])
	d.note("quest %s progress before the deaths: %s" % [KILL_QUEST, str(d.character().quests.progress(KILL_QUEST))])
	var rec := await _die(d, "D1", {"mode": "walk"})
	if rec.is_empty():
		return
	await _quit_while_dead(d, rec)


## Phases 1 and 2: Continue after a quit while dead, verify, then the next area's death and another quit.
func _phase_after_quit(d: PlaytestDriver) -> void:
	var prev: Dictionary = d.carry.get("pending", {})
	if not await _verify_reload(d, prev):
		return
	var label := "D2" if d.phase == 1 else "D3"
	var map_id := SPLIT if d.phase == 1 else FIELD_W
	await d.console("ap luk %d" % (3 if d.phase == 1 else 6))
	await d.console("warp " + map_id)
	if not d.check("[%s] in %s" % [label, map_id], d.current_map() == map_id, d.current_map()):
		return
	await d.wait(1.0)
	var rec := await _die(d, label, {"mode": "walk"})
	if rec.is_empty():
		return
	await _quit_while_dead(d, rec)


func _phase3(d: PlaytestDriver) -> void:
	var prev: Dictionary = d.carry.get("pending", {})
	if not await _verify_reload(d, prev):
		return
	await d.console("ap luk 10")

	# D4: a conversation open at the death (Maria, A Split Road).
	await d.console("warp " + SPLIT)
	await d.wait(0.5)
	var t: Dictionary = await d.talk_to(MARIA)
	if d.check("[D4] Maria's conversation is open (walked to and talked to with F)", bool(t.get("open", false)),
			"%s %s" % [str(t.get("type", "")), str(t.get("why", ""))]):
		var r4 := await _die(d, "D4", {"mode": "dialogue"})
		if not r4.is_empty():
			await _respawn_ok(d, r4)
			var s := d.state()
			d.check("[D4] Maria's quest was not accepted by the death or the keys pressed while dead",
				not (LETTER_QUEST in (s["quests"] as Dictionary)["in_progress"]) and d.character().inventory.count(LETTER_ITEM) == 0,
				"in progress %s, Maria's Letter x%d" % [str((s["quests"] as Dictionary)["in_progress"]),
					d.character().inventory.count(LETTER_ITEM)])

	var probed := false
	# D5: on the walkable trail A Split Road -> The Field West of Amherst.
	await d.console("warp " + SPLIT)
	await d.wait(0.5)
	var src := TraversalTour.portal_between(d.world().defs, SPLIT, FIELD_W)
	if d.check("[D5] the trail %s -> %s exists" % [SPLIT, FIELD_W], src != null):
		var anchor := src.anchor_ground
		var on_trail := func() -> bool:
			var p := d.player()
			var v := p.global_position - anchor
			v.y = 0.0
			return String(d.session().get("trail_link_id")) != "" and v.length() >= TRAIL_STOP_M
		var w: Dictionary = await d.walk_trail(SPLIT, FIELD_W, {"stop_when": on_trail})
		var link := String(d.session().get("trail_link_id"))
		var on_it: bool = d.check("[D5] stopped on the trail, short of the far gate", link != "" and d.current_map() == SPLIT,
			"map %s, trail %s -> %s, %.1f m past the portal (walk %s)" % [d.current_map(), link,
				String(d.session().get("trail_destination")), _flat(d.player().global_position - anchor), str(w.get("issues", []))])
		if on_it:
			var r5 := await _die(d, "D5", {"mode": "trail"})
			if not r5.is_empty():
				probed = true
				var via5 := await _probe_jump_key(d, r5)
				await _respawn_ok(d, r5, via5)

	# D6: mid-jump (The Field East of Amherst), up to MAX_JUMP_TRIES deaths until the killing touch lands in the air.
	await d.console("level 11")
	await d.console("exp 1000")
	var airborne := false
	var tries := 0
	for k in MAX_JUMP_TRIES:
		tries = k + 1
		await d.console("warp " + FIELD_E)
		await d.wait(0.5)
		var r6 := await _die(d, "D6.%d" % tries, {"mode": "jump"})
		if r6.is_empty():
			break
		airborne = not bool((r6.get("kill_touch", {}) as Dictionary).get("on_floor", true))
		var via_jump := false
		if not probed:
			probed = true
			via_jump = await _probe_jump_key(d, r6)
		await _respawn_ok(d, r6, via_jump)
		if airborne:
			break
	d.soft_check("[D6] a death whose killing touch landed mid-jump", airborne, "%d tries" % tries)

	# The OK path's saves: quit normally (alive) and check the last state in a new process.
	var c := d.character()
	d.carry["final"] = {"map": d.current_map(), "position": d.player().global_position, "exp": c.exp, "level": c.level,
		"hp": c.hp, "mp": c.mp, "char": _char_subset(c)}
	await d.reload_process()


func _phase4(d: PlaytestDriver) -> void:
	var fin: Dictionary = d.carry.get("final", {})
	var cg: Dictionary = await d.continue_game()
	if not d.check("[final] Continue after the OK-path deaths", bool(cg["ok"]) and cg["via"] == "screen", str(cg)):
		return
	await d.wait(0.5)
	var c := d.character()
	var s := d.state()
	d.check("[final] the same town after the reload", d.current_map() == String(fin.get("map", "")),
		"%s, saved %s" % [d.current_map(), fin.get("map", "")])
	d.check("[final] the same place", (s["position"] as Vector3).distance_to(fin.get("position", Vector3.INF)) < 1.0,
		"%.2f m" % (s["position"] as Vector3).distance_to(fin.get("position", Vector3.INF)))
	d.check("[final] EXP, level, HP and MP as saved after the last respawn",
		c.exp == int(fin.get("exp", -1)) and c.level == int(fin.get("level", -1)) and c.hp == int(fin.get("hp", -1))
			and c.mp == int(fin.get("mp", -1)),
		"EXP %d/%d, Lv %d/%d, HP %d/%d, MP %d/%d" % [c.exp, int(fin.get("exp", -1)), c.level, int(fin.get("level", -1)),
			c.hp, int(fin.get("hp", -1)), c.mp, int(fin.get("mp", -1))])
	_diff_char(d, "[final]", fin.get("char", {}), _char_subset(c))
	d.check("[final] alive with input", not bool(s["dead_state"]) and bool(s["input_enabled"]) and not bool(s["modal"]),
		"dead %s, input %s, modal %s" % [s["dead_state"], s["input_enabled"], s["modal"]])


# =================================================================================================================
# One death
# =================================================================================================================

## Lowers HP to 1 (setup), walks (or hops) into a monster until its touch kills the player, and checks the death
## state. Returns the record (pre-death snapshot, expectations, observations); {} when no death happened.
func _die(d: PlaytestDriver, label: String, opts: Dictionary) -> Dictionary:
	var mode := String(opts.get("mode", "walk"))
	var c := d.character()
	var db := d.db()
	var map_id := d.current_map()
	if not d.check("[%s] alive and idle in %s %s" % [label, map_id, _map_name(d, map_id)],
			c != null and not d.game().is_character_dead() and bool(d.session().call("is_idle")),
			String(d.session().call("state_name"))):
		return {}
	var max_mp := StatCalculator.max_mp(c, db)
	var mp_target := clampi(int(max_mp * 0.5) - int(label.substr(1, 1)), 1, maxi(1, max_mp - 1))
	var i := d._begin(PlaytestReport.KIND_API, "Game.change_hp / change_mp", "%s: HP %d -> 1, MP %d -> %d" % [label,
		c.hp, c.mp, mp_target])
	d._fallback(i, "setup: no console command sets HP or MP (DEBUG_TOOLS.md: heal and god only); the killing blow is a real touch")
	d.game().change_hp(1 - c.hp)
	d.game().change_mp(mp_target - c.mp)
	d._end(i, c.hp == 1 and c.mp == mp_target, "HP %d, MP %d" % [c.hp, c.mp])

	var pre := {"map": map_id, "slot": String(d.game().current_slot), "level": c.level, "exp": c.exp,
		"luk": int(c.base_stats.get("luk", 0)), "hp": c.hp, "mp": c.mp, "max_hp": StatCalculator.max_hp(c, db),
		"max_mp": max_mp, "char": _char_subset(c)}
	var rec := {"label": label, "mode": mode, "pre": pre, "died": 0, "died_map": "", "death_exp": [], "touches": [],
		"kill_touch": {}}
	var ev := d.events()
	var ms := d.monsters()
	var on_died := func(m: String) -> void:
		rec["died"] = int(rec["died"]) + 1
		if String(rec["died_map"]) == "":
			rec["died_map"] = m
			rec["died_at"] = d.game_s()
			rec["death_pos"] = d.player().global_position
			rec["on_floor_at_death"] = d.player().is_on_floor()
			rec["trail_at_death"] = String(d.session().get("trail_link_id"))
			rec["trail_dest_at_death"] = String(d.session().get("trail_destination"))
	var on_exp := func(amount: int, source: String) -> void:
		if source == "death":
			(rec["death_exp"] as Array).append(amount)
	var on_touch := func(m: Node, res: IncomingResult) -> void:
		var p := d.player()
		(rec["touches"] as Array).append({"mob": String(m.get("def").get("id")), "debug": m.has_meta("debug_spawn"),
			"landed": res.landed(), "final": res.final, "hp_after": d.character().hp, "on_floor": p.is_on_floor(),
			"vy": snappedf(p.velocity.y, 0.01), "pos": p.global_position, "at": snappedf(d.game_s(), 0.01)})
	ev.connect(&"player_died", on_died)
	ev.connect(&"exp_gained", on_exp)
	ms.connect(&"player_touched", on_touch)
	var log_before := _died_lines(d)

	match mode:
		"dialogue":
			await _wait_touch_in_dialogue(d, rec)
		"trail":
			await d.console("spawn snail 3")
			await _walk_into_monster(d, label, 60.0, false, true)
		"jump":
			await _walk_into_monster(d, label, 90.0, true, false)
		_:
			await _walk_into_monster(d, label, 90.0, false, false)
	var dead := await d.wait_until(func() -> bool: return _session_dead(d), 3.0)
	# 1.5 s: the save at the death, the deferred HP watch and any second announcement land here; meanwhile the first
	# frame the body stands on the ground again is recorded (a death in the air must fall, not hang).
	var t_land := -1.0
	var t_end := d.game_s() + 1.5
	while d.game_s() < t_end:
		if t_land < 0.0 and d.player().is_on_floor():
			t_land = d.game_s()
		await d.get_tree().process_frame
		d.input.reassert()
	rec["landed_after_s"] = snappedf(t_land - float(rec.get("died_at", t_land)), 0.01) if t_land >= 0.0 else -1.0

	var touches: Array = rec["touches"]
	var kill: Dictionary = {}
	for tch: Dictionary in touches:
		if bool(tch["landed"]) and int(tch["hp_after"]) <= 0:
			kill = tch
			break
	rec["kill_touch"] = kill
	var e := _expect(d, pre, String(rec["died_map"]) if String(rec["died_map"]) != "" else map_id)
	rec["expect"] = e
	var canon_mobs := _map_monsters(d, map_id)
	var real_ok := dead and not kill.is_empty() and (mode == "trail" or mode == "dialogue" or not bool(kill["debug"]))
	if not d.check("[%s] died to a real monster touch in %s" % [label, map_id], real_ok,
			"%s; touches %d; killing touch: %s" % ["dead" if dead else "NOT dead (" + String(d.session().call("state_name")) + ")",
				touches.size(), _touch_text(d, kill)]):
		ev.disconnect(&"player_died", on_died)
		ev.disconnect(&"exp_gained", on_exp)
		ms.disconnect(&"player_touched", on_touch)
		return {}
	if not bool(kill["debug"]):
		d.check("[%s] the killer is one of the map's canonical monsters" % label, String(kill["mob"]) in canon_mobs,
			"%s in %s" % [kill["mob"], str(canon_mobs)])
	else:
		d.note("[%s] the killer is a debug spawn (%s): no canonical monster lives here" % [label, kill["mob"]])
	d.check("[%s] the death happened in the map the player was in" % label, String(rec["died_map"]) == map_id,
		"player_died(%s), map %s" % [rec["died_map"], map_id])

	# --- the death state ---
	var p := d.player()
	var death := d.main.game_session.death
	var notice: DeathNotice = death.notice
	var st := d.state()
	d.check("[%s] death state: MapSession DEAD, player dead, input off, a modal holds the keyboard, shell DEAD" % label,
		String(st["session"]) == "DEAD" and bool(st["dead"]) and not bool(st["input_enabled"]) and bool(st["modal"])
			and bool(st["dead_state"]) and d.main.flow.is_in(ShellFlow.State.DEAD),
		"session %s, dead %s, input %s, modal %s, shell %s" % [st["session"], st["dead"], st["input_enabled"], st["modal"],
			ShellFlow.state_name(d.main.flow.state)])
	var notice_ok := notice != null and notice.visible and notice.message.text == DeathNotice.TEXT \
		and notice.detail.text.contains(String(e["return_name"]))
	d.check("[%s] the death notice is up and names %s" % [label, e["return_name"]], notice_ok,
		"'%s' / '%s'" % [notice.message.text if notice != null else "-", notice.detail.text if notice != null else "-"])
	var status: Variant = d.hud().get("status")
	var hp_g: MisoGauge = status.get("hp_gauge")
	var exp_g: MisoGauge = status.get("exp_gauge")
	d.check("[%s] HUD HP gauge reads 0" % label, hp_g.current == 0, "gauge %d/%d '%s' (character HP already %d)" % [
		hp_g.current, hp_g.maximum, hp_g.value_label.text, c.hp])
	if mode == "dialogue":
		d.check("[%s] the conversation was closed at the death; the notice is the only modal" % label,
			not d.dialogue_open() and notice.visible and d.ctx().is_modal_active(),
			"dialogue open %s, notice %s, natural touch %s" % [d.dialogue_open(), notice.visible, rec.get("natural_touch", "?")])
	d.check("[%s] the death was announced once" % label, int(rec["died"]) == 1 and _died_lines(d) - log_before == 1,
		"player_died x%d, HUD 'You have died.' x%d" % [int(rec["died"]), _died_lines(d) - log_before])

	# --- the EXP penalty ---
	d.check("[%s] canonical EXP penalty: Lv %d, base LUK %d, %d to next -> loss %d, EXP %d -> %d" % [label, int(pre["level"]),
		int(pre["luk"]), int(e["exp_to_next"]), int(e["loss"]), int(pre["exp"]), int(e["exp_after"])],
		c.exp == int(e["exp_after"]) and c.level == int(pre["level"]),
		"EXP %d (lost %d), Lv %d" % [c.exp, int(pre["exp"]) - c.exp, c.level])
	d.check("[%s] the loss was announced once to the HUD" % label,
		(rec["death_exp"] as Array).size() == 1 and int((rec["death_exp"] as Array)[0]) == -int(e["loss"]),
		"exp_gained(..., death): %s" % str(rec["death_exp"]))
	d.check("[%s] HUD EXP gauge shows the penalised EXP" % label, exp_g.current == int(e["exp_after"]),
		"gauge %d/%d '%s'" % [exp_g.current, exp_g.maximum, exp_g.value_label.text])
	d.check("[%s] the character holds death.json's respawn vitals while dead (HP %d, MP %d)" % [label, int(e["hp"]),
		int(e["mp"])], c.hp == int(e["hp"]) and c.mp == int(e["mp"]), "HP %d, MP %d" % [c.hp, c.mp])

	# --- the save written at the death ---
	var save := _read_save(d, String(pre["slot"]))
	var sc: Dictionary = save.get("character", {})
	var loc: Dictionary = (save.get("world", {}) as Dictionary).get("location", {})
	var entry: Dictionary = loc.get("entry", {})
	d.check("[%s] the save on disk already holds the death: EXP %d, HP %d, %s spawn %d, no resume point" % [label,
		int(e["exp_after"]), int(e["hp"]), e["return_map"], int(e["spawn_index"])],
		int(sc.get("exp", -1)) == int(e["exp_after"]) and int(sc.get("hp", -1)) == int(e["hp"])
			and String(loc.get("map_id", "")) == String(e["return_map"]) and int(entry.get("spawn_index", -1)) == int(e["spawn_index"])
			and not loc.has("resume"),
		"exp %s, hp %s, mp %s, location %s" % [str(sc.get("exp")), str(sc.get("hp")), str(sc.get("mp")), JSON.stringify(loc)])

	await d.screenshot("%s_dead_%s" % [label, map_id])
	# --- real input while dead (each key on its own; Space and Enter are probed apart: see _probe_jump_key) ---
	d.check("[%s] the body is on the ground after the death" % label, float(rec.get("landed_after_s", -1.0)) >= 0.0,
		"on floor %.2f s after the death (airborne at the death: %s), local %s" % [float(rec.get("landed_after_s", -1.0)),
			not bool(rec.get("on_floor_at_death", true)), str(d.state().get("local"))])
	var p0 := p.global_position
	await d.press(&"move_right", 0.5)
	await d.press(&"move_up", 0.3)
	await d.wait(0.2)
	var moved := _flat(p.global_position - p0)
	var pc := d.combat()
	var atk0 := int(pc.get("attacks"))
	await d.tap(&"attack")
	await d.wait(0.3)
	var atk1 := int(pc.get("attacks"))
	await d.tap_key(KEY_Y)
	await d.tap_key(KEY_N)
	await d.tap_key(KEY_ESCAPE)
	await d.frames(3)
	d.check("[%s] real keys do nothing while dead (move, attack, Y, N, Esc)" % label,
		moved < 0.05 and atk1 == atk0 and d.main.flow.is_in(ShellFlow.State.DEAD) and not d.main.pause_menu.visible
			and notice.visible and String(d.session().call("state_name")) == "DEAD",
		"moved %.3f m, attacks %d -> %d, shell %s, pause menu %s, notice %s, session %s" % [moved, atk0, atk1,
			ShellFlow.state_name(d.main.flow.state), d.main.pause_menu.visible, notice.visible, d.session().call("state_name")])
	d.check("[%s] still one death and one loss after the keys" % label,
		int(rec["died"]) == 1 and (rec["death_exp"] as Array).size() == 1 and c.exp == int(e["exp_after"]),
		"player_died x%d, losses %s, EXP %d" % [int(rec["died"]), str(rec["death_exp"]), c.exp])
	ev.disconnect(&"player_died", on_died)
	ev.disconnect(&"exp_gained", on_exp)
	ms.disconnect(&"player_touched", on_touch)
	d.note("[%s] died in %s %s at local %s; killing touch %s; trail at death '%s' (-> %s); EXP %d -> %d" % [label, map_id,
		_map_name(d, map_id), str(_local(d, rec.get("death_pos", Vector3.ZERO), map_id)), _touch_text(d, kill),
		rec.get("trail_at_death", ""), rec.get("trail_dest_at_death", ""), int(pre["exp"]), c.exp])
	return rec


## Walks into the nearest monster with real input until a touch kills the player (HP 1). `hop` holds the jump key
## while steering in (holding it re-jumps on every landing), so the touch can land mid-air. `debug_ok` allows debug
## spawns as targets (the trail has no canonical monsters).
func _walk_into_monster(d: PlaytestDriver, label: String, max_s: float, hop: bool, debug_ok: bool) -> void:
	var i := d._begin(PlaytestReport.KIND_PLAY, "walk_into_monster", "%s%s" % [label, " (hopping)" if hop else ""])
	var p := d.player()
	var t0 := d.game_s()
	var exclude := {}
	var target: Node3D = null
	var best := INF
	var best_t := t0
	var hopping := false
	while d.game_s() - t0 < max_s and not _is_dead(d):
		if target == null or not is_instance_valid(target) or not bool(target.call("is_alive")):
			target = _pick_monster(d, exclude, debug_ok)
			best = INF
			best_t = d.game_s()
			if target == null:
				await d.wait(0.5)
				continue
		var to := target.global_position - p.global_position
		var dy := absf(to.y)
		to.y = 0.0
		var dist := to.length()
		if dist < best - 0.05:
			best = dist
			best_t = d.game_s()
		if d.game_s() - best_t > 4.0:
			exclude[target.get_instance_id()] = true
			target = null
			continue
		if dist > 4.0 or dy > 0.8:
			if hopping:
				d.input.key_up(KEY_SPACE)
				hopping = false
			d.input.release_movement()
			var tgt := target
			await d.walk_to(d.walker.grounded(tgt.global_position), {"max_s": 6.0, "retries": 0, "within_m": 1.5,
				"stop_when": func() -> bool:
					return _is_dead(d) or not is_instance_valid(tgt) or (_flat(tgt.global_position - p.global_position) < 3.0
						and absf(tgt.global_position.y - p.global_position.y) < 0.8)})
			best = INF
			best_t = d.game_s()
			continue
		if hop and not hopping and dist < 3.0:
			d.input.key_down(KEY_SPACE)
			hopping = true
		d.input.set_move_world(to.normalized() if dist > 0.01 else p.facing, p.view_right, p.view_forward)
		await d.get_tree().process_frame
		d.input.reassert()
	if hopping:
		d.input.key_up(KEY_SPACE)
	d.input.release_movement()
	d._end(i, _is_dead(d), "%s after %.1f s" % ["dead" if _is_dead(d) else "alive", d.game_s() - t0])


## The conversation is open (input off): wait for a monster to wander into the player; after 20 s, debug-spawn
## Blue Snails around the player (they face it) and wait again.
func _wait_touch_in_dialogue(d: PlaytestDriver, rec: Dictionary) -> void:
	var i := d._begin(PlaytestReport.KIND_PLAY, "wait_for_touch_in_dialogue", String(rec["label"]))
	var natural := await d.wait_until(func() -> bool: return _is_dead(d) or not d.dialogue_open(), 20.0)
	rec["natural_touch"] = _is_dead(d)
	if not _is_dead(d) and d.dialogue_open():
		d.note("[%s] no monster touched the player in 20 s of conversation: debug-spawning Blue Snails" % rec["label"])
		await d.console("spawn blue snail 6")
		await d.wait_until(func() -> bool: return _is_dead(d) or not d.dialogue_open(), 40.0)
	d._end(i, _is_dead(d), "dead %s, dialogue open %s, natural %s" % [_is_dead(d), d.dialogue_open(), natural])


## OK on the notice (a mouse click), the respawn, and the checks in town. `started`: the respawn was already started
## by another key (the jump-key probe), so there is nothing to click.
func _respawn_ok(d: PlaytestDriver, rec: Dictionary, started: bool = false) -> bool:
	var label := String(rec["label"])
	var death := d.main.game_session.death
	var exp_events: Array = []
	var on_exp := func(amount: int, source: String) -> void:
		if source == "death":
			exp_events.append(amount)
	d.events().connect(&"exp_gained", on_exp)
	var how := "after OK"
	if started:
		how = "after the jump key"
	else:
		var r: Dictionary = await d.click(death.notice.ok_button)
		d.check("[%s] OK on the death notice (mouse click)" % label, bool(r["ok"]), str(r))
	var back := await d.wait_until(func() -> bool:
		return not d.game().is_character_dead() and bool(d.session().call("is_idle")) and not d.player().is_dead(), 20.0)
	await d.wait_idle()
	await d.wait(0.5)
	d.events().disconnect(&"exp_gained", on_exp)
	d.check("[%s] the respawn finished" % label, back, String(d.session().call("state_name")))
	d.check("[%s] %s: the respawn took nothing more" % [label, how], exp_events.is_empty(),
		"exp_gained(death) during the respawn: %s" % str(exp_events))
	_check_alive_in_town(d, rec, how)
	await d.screenshot("%s_town_%s" % [label, d.current_map()])
	return back


## A player mashing keys at the moment of death: J (attack) then Space (jump) while the notice is up. Returns true
## when Space confirmed the notice (the respawn started); then also whether the J press fired an attack in town.
func _probe_jump_key(d: PlaytestDriver, rec: Dictionary) -> bool:
	var label := String(rec["label"])
	var notice: DeathNotice = d.main.game_session.death.notice
	var pc := d.combat()
	var atk0 := int(pc.get("attacks"))
	var focus := d.get_viewport().gui_get_focus_owner()
	await d.tap(&"attack")
	await d.tap(&"jump")
	var went := await d.wait_until(func() -> bool:
		return not notice.visible or String(d.session().call("state_name")) != "DEAD", 1.0)
	d.soft_check("[%s] the jump key (Space) does not confirm the death notice" % label, not went,
		"after J then Space while dead: notice visible %s, session %s, focus on '%s'" % [notice.visible,
			d.session().call("state_name"), focus.name if focus != null else "-"])
	if went:
		# Poll every frame: when (and in which state) does an attack fire, and when does the respawn end?
		var t_space := d.game_s()
		var attack_at := {}
		var idle_at := -1.0
		var t_end := t_space + 20.0
		while d.game_s() < t_end:
			if attack_at.is_empty() and int(pc.get("attacks")) > atk0:
				attack_at = {"after_s": snappedf(d.game_s() - t_space, 0.001), "session": d.session().call("state_name"),
					"dead": d.player().is_dead(), "input": d.player().is_input_enabled(), "map": d.current_map()}
			if idle_at < 0.0 and not d.game().is_character_dead() and bool(d.session().call("is_idle")):
				idle_at = d.game_s() - t_space
			if idle_at >= 0.0 and d.game_s() - t_space > idle_at + 0.5:
				break
			await d.get_tree().process_frame
			d.input.reassert()
		var atk1 := int(pc.get("attacks"))
		d.soft_check("[%s] the attack key pressed while dead does not fire after the respawn" % label, atk1 == atk0,
			"attacks %d -> %d; J tapped 2 ticks before Space (attack buffer 0.15 s); respawn idle %.3f s after Space; attack %s" % [
				atk0, atk1, idle_at, str(attack_at)])
	return went


## Quit while dead (the window's close request: Esc cannot open the pause menu in DEAD), then a new process.
func _quit_while_dead(d: PlaytestDriver, rec: Dictionary) -> void:
	d.note("[%s] quitting while dead: the pause menu is refused in DEAD, so the window is closed as a player would (WM close request -> MainShell.commit_death_on_quit)" % rec["label"])
	await d.wait(0.5)
	d.carry["pending"] = rec
	await d.reload_process()


## Continue after a quit while dead: the save holds the death exactly once.
func _verify_reload(d: PlaytestDriver, rec: Dictionary) -> bool:
	var label := String(rec.get("label", "?"))
	if not d.check("[%s] a death was carried from the previous process" % label, not rec.is_empty()):
		return false
	var cg: Dictionary = await d.continue_game()
	if not d.check("[%s] Continue after quitting while dead" % label, bool(cg["ok"]) and cg["via"] == "screen", str(cg)):
		return false
	await d.wait(0.5)
	var e: Dictionary = rec["expect"]
	var pre: Dictionary = rec["pre"]
	var c := d.character()
	var once := int(e["exp_after"])
	var none := int(pre["exp"])
	var twice := maxi(0, int(pre["exp"]) - 2 * int(e["loss"]))
	d.check("[%s] after the reload the penalty is taken exactly once" % label, c.exp == once and c.level == int(pre["level"]),
		"EXP %d: once %d, never %d, twice %d (Lv %d)" % [c.exp, once, none, twice, c.level])
	_check_alive_in_town(d, rec, "after the reload")
	await d.screenshot("%s_reloaded_%s" % [label, d.current_map()])
	return true


## The checks shared by both respawn paths: the canonical returnMap at its respawn spawn, death.json HP/MP, the EXP
## of the death, alive with input, the HUD, and the character diffed against the pre-death snapshot.
func _check_alive_in_town(d: PlaytestDriver, rec: Dictionary, how: String) -> void:
	var label := String(rec["label"])
	var e: Dictionary = rec["expect"]
	var pre: Dictionary = rec["pre"]
	var c := d.character()
	var s := d.state()
	d.check("[%s] %s: in the canonical returnMap %s (%s)" % [label, how, e["return_map"], e["return_name"]],
		d.current_map() == String(e["return_map"]), "%s %s" % [d.current_map(), _map_name(d, d.current_map())])
	var spawn: Dictionary = d.resolve_target("spawn:%d" % int(e["spawn_index"]))
	var off := _flat((s["position"] as Vector3) - (spawn.get("position", Vector3.INF) as Vector3)) if bool(spawn.get("ok", false)) else INF
	d.check("[%s] %s: at the respawn spawn %d" % [label, how, int(e["spawn_index"])], off <= SPAWN_TOLERANCE_M,
		"%.2f m from it, local %s" % [off, str(s.get("local"))])
	d.check("[%s] %s: HP %d and MP %d per death.json" % [label, how, int(e["hp"]), int(e["mp"])],
		c.hp == int(e["hp"]) and c.mp == int(e["mp"]),
		"HP %d/%d, MP %d/%d" % [c.hp, int(s["max_hp"]), c.mp, int(s["max_mp"])])
	d.check("[%s] %s: EXP %d (the death's, nothing more)" % [label, how, int(e["exp_after"])],
		c.exp == int(e["exp_after"]) and c.level == int(pre["level"]), "EXP %d, Lv %d" % [c.exp, c.level])
	var death := d.main.game_session.death
	d.check("[%s] %s: alive, input on, no modal, no dialogue, notice gone, shell PLAYING" % [label, how],
		not bool(s["dead_state"]) and not bool(s["dead"]) and bool(s["input_enabled"]) and not bool(s["modal"])
			and not bool(s["dialogue_open"]) and String(s["session"]) == "IDLE" and d.main.flow.is_in(ShellFlow.State.PLAYING)
			and (death.notice == null or not death.notice.visible),
		"dead %s/%s, input %s, modal %s, dialogue %s, session %s, shell %s" % [s["dead_state"], s["dead"], s["input_enabled"],
			s["modal"], s["dialogue_open"], s["session"], ShellFlow.state_name(d.main.flow.state)])
	var status: Variant = d.hud().get("status")
	var hp_g: MisoGauge = status.get("hp_gauge")
	var mp_g: MisoGauge = status.get("mp_gauge")
	var exp_g: MisoGauge = status.get("exp_gauge")
	d.check("[%s] %s: the HUD shows HP %d, MP %d, EXP %d" % [label, how, c.hp, c.mp, c.exp],
		hp_g.current == c.hp and mp_g.current == c.mp and exp_g.current == c.exp,
		"HP '%s', MP '%s', EXP '%s'" % [hp_g.value_label.text, mp_g.value_label.text, exp_g.value_label.text])
	_diff_char(d, "[%s] %s:" % [label, how], pre["char"], _char_subset(c))


func _diff_char(d: PlaytestDriver, prefix: String, before: Dictionary, now: Dictionary) -> void:
	var bad: PackedStringArray = []
	for key: String in DIFF_KEYS:
		var df := PlaytestDriver.diff(before.get(key), now.get(key), "$." + key)
		if df != "":
			bad.append(df)
	d.check("%s inventory, equipment, mesos, quests, stats unchanged" % prefix, bad.is_empty(),
		"; ".join(bad) if not bad.is_empty() else "%d keys equal; mesos %s; quests %s" % [DIFF_KEYS.size(),
			str(now.get("mesos")), _quest_text(now)])


# =================================================================================================================
# Expectations (canonical data, read by the scenario itself)
# =================================================================================================================

func _load_tables() -> void:
	_canon_death = _json(DEATH_CANON)
	_miso_death = _json(DEATH_MISO)
	_exp_rows = _json(EXP_TABLE).get("levels", [])


## MeowDB's calculator: loss = floor(a * (5 + 20 / l) / 100), l = base LUK clamped, a = EXP to the next level.
func _expected_loss(level: int, luk: int) -> Dictionary:
	var ep: Dictionary = _canon_death.get("exp_penalty", {})
	var clamp_r: Array = ep.get("calculator_luk_clamp", [4, 999])
	var l := clampi(luk, int(clamp_r[0]), int(clamp_r[1]))
	var a := 0
	for row: Dictionary in _exp_rows:
		if int(row.get("level", 0)) == level:
			a = int(row.get("exp_to_next", 0))
	var pct := float(ep.get("base_loss_pct", 0)) + float(ep.get("luk_term_numerator", 0)) / float(l)
	return {"exp_to_next": a, "loss": int(floor(float(a) * pct / 100.0)), "luk_used": l}


func _expect(d: PlaytestDriver, pre: Dictionary, died_map: String) -> Dictionary:
	var lo := _expected_loss(int(pre["level"]), int(pre["luk"]))
	var m: Dictionary = d.db().map(died_map)
	var ret := String(m.get("return_map_id", ""))
	var hp_rule: Dictionary = _miso_death.get("respawn_vitals", {}).get("hp", {})
	var mp_rule: Dictionary = _miso_death.get("respawn_vitals", {}).get("mp", {})
	return {"loss": int(lo["loss"]), "exp_to_next": int(lo["exp_to_next"]),
		"exp_after": maxi(0, int(pre["exp"]) - int(lo["loss"])), "return_map": ret,
		"return_name": String(d.db().map(ret).get("name", "")),
		"spawn_index": int(_miso_death.get("respawn_player_spawn_index", {}).get("value", 0)),
		"hp": maxi(1, _vital(hp_rule, int(pre["hp"]), int(pre["max_hp"]))),
		"mp": _vital(mp_rule, int(pre["mp"]), int(pre["max_mp"]))}


## death.json's vital modes: fixed (value, capped at the maximum), fraction_of_max, full, keep.
static func _vital(rule: Dictionary, current: int, maximum: int) -> int:
	match String(rule.get("mode", "keep")):
		"fixed":
			return mini(int(rule.get("value", 0)), maximum)
		"fraction_of_max":
			return int(floor(float(rule.get("value", 0.0)) * maximum))
		"full":
			return maximum
	return current


# =================================================================================================================
# Helpers
# =================================================================================================================

func _pick_monster(d: PlaytestDriver, exclude: Dictionary, debug_ok: bool) -> Node3D:
	var p := d.player()
	var best: Node3D = null
	var best_d := 40.0
	for m: Node3D in d.monsters().call("live_monsters"):
		if not is_instance_valid(m) or exclude.has(m.get_instance_id()):
			continue
		if m.has_meta("debug_spawn") and not debug_ok:
			continue
		var dd := _flat(m.global_position - p.global_position) + 3.0 * absf(m.global_position.y - p.global_position.y)
		if dd < best_d:
			best_d = dd
			best = m
	return best


static func _is_dead(d: PlaytestDriver) -> bool:
	return d.game().is_character_dead() or (d.player() != null and d.player().is_dead())


static func _session_dead(d: PlaytestDriver) -> bool:
	return String(d.session().call("state_name")) == "DEAD"


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


static func _char_subset(c: CharacterState) -> Dictionary:
	var all := c.to_dict()
	var out := {}
	for key: String in DIFF_KEYS:
		out[key] = all.get(key)
	return out


static func _quest_text(sub: Dictionary) -> String:
	var q: Variant = sub.get("quests")
	var entries: Variant = (q as Dictionary).get("quests", {}) if q is Dictionary else {}
	return JSON.stringify(entries).left(300)


static func _died_lines(d: PlaytestDriver) -> int:
	var hud := d.hud()
	var log_panel: Variant = hud.get("log_panel") if hud != null else null
	if log_panel == null:
		return -1
	var n := 0
	for t: String in log_panel.call("texts"):
		if t == "You have died.":
			n += 1
	return n


static func _read_save(d: PlaytestDriver, slot: String) -> Dictionary:
	var path := d.save_dir.path_join(slot + ".json")
	if not FileAccess.file_exists(path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


static func _json(path: String) -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


static func _map_name(d: PlaytestDriver, map_id: String) -> String:
	return String(d.db().map(map_id).get("name", "")) if d.db() != null else ""


static func _map_monsters(d: PlaytestDriver, map_id: String) -> Array:
	var out: Array = []
	for m: Variant in d.db().map(map_id).get("monsters", []):
		if m is Dictionary:
			out.append(String((m as Dictionary).get("id", "")))
	return out


static func _local(d: PlaytestDriver, pos: Vector3, map_id: String) -> Vector3:
	var w := d.world()
	if w == null or not w.defs.has_map(map_id):
		return pos
	var v: Vector3 = w.defs.get_def(map_id).to_local(pos)
	return Vector3(snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01))


static func _touch_text(d: PlaytestDriver, t: Dictionary) -> String:
	if t.is_empty():
		return "none"
	return "%s (%s)%s for %d, HP -> %d, %s (vy %.2f) at %.2f s" % [String(d.db().monster(String(t["mob"])).get("name", "?"))
		if d.db() != null else "?", t["mob"], " [debug spawn]" if bool(t["debug"]) else "", int(t["final"]),
		int(t["hp_after"]), "on the ground" if bool(t["on_floor"]) else "IN THE AIR", float(t["vy"]), float(t["at"])]
