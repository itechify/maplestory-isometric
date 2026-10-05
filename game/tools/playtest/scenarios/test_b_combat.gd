extends PlaytestScenario
## test_b_combat: brief Test B (combat) and the Combat Review, played on the real main scene with the attack key.
## A Sword Beginner (STR 4+9) fights every implemented species in a canonical map where it spawns: Tutorial Jr.
## Sentinel (000000030), Snail (000000040), Blue Snail, Shroom and Red Snail (000000050), Orange Mushroom
## (000001020). Console commands are setup only: the warps between hunting grounds and `heal` between fights (so a
## Lv 1-5 body survives Orange Mushroom touches). Everything verified happens by real play: walking, facing with the
## move keys, the attack key, standing in monsters.
##
## Recorders on PlayerCombat, MonsterSystem, the map view, the loot system and Events, plus a per-tick monitor, check
## every event against oracles computed in this file from canonical data (damage.json, accuracy.json,
## attack_styles.json, spawn_rate.json, movement.json, monsters/<id>.json, drops/<id>.json) and cross-check them with
## CombatFormula: per-hit damage windows (level gap, criticals), the two-draw distribution (Monte Carlo with a private
## RNG; Game.rng is never touched), reach (the canonical swordOL boxes mirrored, 60 px isometric depth, strict
## overlap), touch damage, invulnerability gating, player and monster knockback, death fade, EXP, drops and the
## 7.56 s respawn tick. Probes add real-play cases the fights rarely produce: attacks with the monster behind or out of
## reach, the Peace rule, input latency and the held-key repeat, and a touch probe per species (standing in monsters).
##
## Run: `ISOLATE=<name> bash scripts/playtest.sh test_b_combat [--seed n]` (headless, full: 30 landed hits per species).
## Windowed runs default to quick targets (6 hits, fewer probes) and take the review screenshots; PLAYB_FULL=1 forces
## the full targets windowed, PLAYB_QUICK=1 forces quick ones headless. Raw samples go to <out>/combat_samples.json.
## Console heals are nested under fight_species / probes (setup only; the "console heals" note counts them).

const WEAPON := "541"
const AP := {"str": 9}
const PLAN: Array = [
	{"mob": "1", "map": "000000030"},
	{"mob": "2", "map": "000000040"},
	{"mob": "3", "map": "000000050"},
	{"mob": "4", "map": "000000050"},
	{"mob": "5", "map": "000000050"},
	{"mob": "9", "map": "000001020"},
]
const HITS_FULL := 30
const HITS_QUICK := 6
const SPECIES_BUDGET_S := 420.0
const FIGHT_CALL_S := 4.0
const MC_SAMPLES := 6000

var d: PlaytestDriver = null
var db: ContentDB = null
var quick: bool = false
var windowed: bool = false
var hit_target: int = HITS_FULL
var mc_rng := RandomNumberGenerator.new()

# canonical tables (read once)
var dmg_f: Dictionary = {}
var acc_f: Dictionary = {}
var styles_f: Dictionary = {}
var spawn_f: Dictionary = {}
var move_f: Dictionary = {}
var combat_m: Dictionary = {}
var move_m: Dictionary = {}
var weapon_row: Dictionary = {}

# recorders
var _snap: Dictionary = {}
var _press_frame: int = -1
var _probe_tag: String = ""
var attacks: Array = []
var hits: Array = []
var whiffs: Array = []
var target_mismatch: Array = []
var range_fail: Array = []
var formula_disagree: Array = []
var touches: Array = []
var touch_fail: Array = []
var kills: Array = []
var exp_events: Array = []
var exp_bad: Array = []
var loot_events: Array = []
var loot_bad: Array = []
var ground_nodes: Array = []
var spawn_refills: Array = []
var _pending_deaths: Dictionary = {}
var _visit_ready_t: float = INF
var _cap: Dictionary = {"map": "", "k": -1, "due": -1, "due_k": -1}
var capacity_checks: Array = []
var capacity_bad: Array = []
var kb_interrupted: int = 0
## The knockback tracks a warp, a teleport or a death interrupted: {t, mob, step_m, session}.
var kb_interrupts: Array = []
var unreachable: Array = []
var _fresh: Dictionary = {}
var kb_player: Array = []
var kb_monster: Array = []
var _kbp: Dictionary = {}
var _kbm: Array = []
var fades: Array = []
var _check_fading: Array = []
var monitor := {"ticks": 0, "suppressed": 0, "unexplained": 0, "peace_ticks": 0, "unexplained_samples": []}
var stat_bad: Array = []
var visual_fit: Dictionary = {}
var screen_px: Dictionary = {}
var _view: Node = null
var _last_touch_clock: float = -1.0
var _touch_gaps: Array = []
var _hold_frames: Array = []
var _latency: Array = []
var probes: Array = []
var peace := {}
var deaths_of_player: int = 0
var heals: int = 0
var _last_killed: String = ""


func description() -> String:
	return "Test B: every species (1, 2, 3, 4, 5, 9) in a canonical spawn map with the attack key; hit detection, misses, damage windows and distribution, touch damage, knockback, invulnerability, death, EXP, drops, respawn tick, latency"


func max_seconds() -> float:
	return 2400.0


func run(driver: PlaytestDriver) -> void:
	d = driver
	db = d.db()
	windowed = DisplayServer.get_name() != "headless"
	quick = OS.get_environment("PLAYB_QUICK") == "1" or (windowed and OS.get_environment("PLAYB_FULL") != "1")
	hit_target = HITS_QUICK if quick else HITS_FULL
	mc_rng.seed = 424242
	_load_tables()
	d.note("mode: %s, %d hits per species target" % ["quick" if quick else "full", hit_target])

	var ng: Dictionary = await d.new_game("FighterB", "male", WEAPON, AP)
	if not d.check("new game through the creation screen (Sword 541, STR +9)", bool(ng["ok"]), String(ng["why"])):
		return
	_check_character_stats()
	_connect_all()

	for i in PLAN.size():
		var step: Dictionary = PLAN[i]
		var mob := String(step["mob"])
		var map := String(step["map"])
		if d.current_map() != map:
			await _warp(map)
			if not d.check("arrived in %s for species %s" % [map, mob], d.current_map() == map, d.current_map()):
				continue
		_check_spawns_here(mob, map)
		_measure_visual(mob)
		if mob == "1":
			await _peace_probe()
		if mob == "2":
			await _latency_probe()
			await _reach_probes()
		if mob == "9" and windowed:
			await _touch_shot()
		await _fight_species(mob, map)
		if mob != "1":
			await _touch_probe(mob, 2 if quick else 5, 45.0)
		if windowed:
			_measure_screen(mob)
			await d.screenshot("after_%s_%s" % [mob, _mob_name(mob).replace(" ", "_")])
	# let pending respawns, fades and knockback tracks finish
	await d.wait(14.0)
	_disconnect_all()
	_evaluate()
	_write_samples()


# =================================================================================================================
# Setup helpers
# =================================================================================================================

func _load_tables() -> void:
	dmg_f = db.formula("damage")
	acc_f = db.formula("accuracy")
	styles_f = db.formula("attack_styles")
	spawn_f = db.formula("spawn_rate")
	move_f = db.formula("movement")
	var cm: Variant = db.miso_table("combat")
	combat_m = cm if cm is Dictionary else {}
	var mm: Variant = db.miso_table("movement")
	move_m = mm if mm is Dictionary else {}
	for row: Dictionary in styles_f.get("beginner_weapons", []):
		if String(row.get("item_id", "")) == WEAPON:
			weapon_row = row


func _mob_name(mob: String) -> String:
	return String(db.monster(mob).get("name", mob))


func _warp(map: String) -> void:
	_visit_ready_t = INF
	await d.console("warp " + map)
	await d.wait_idle(20.0)
	await d.wait(1.5)
	_pending_deaths.clear()
	_reconnect_view()
	_visit_ready_t = d.game_s()


func _check_character_stats() -> void:
	var c := d.character()
	var bon: Dictionary = c.equipment.total_bonuses(db)
	var stats := PlayerCombatStats.from_character(c, db)
	var str_t := int(c.base_stats.get("str", 0)) + int(bon.get("str", 0))
	var dex_t := int(c.base_stats.get("dex", 0)) + int(bon.get("dex", 0))
	var item_watk := int((db.item(WEAPON).get("stats", {}) as Dictionary).get("watk", 0))
	var wdef_c := int(floor(str_t / 4.0)) + int(bon.get("wdef", 0))
	d.check("character: STR %d DEX %d (4 + 9 creation AP), Sword W.ATK %d in the pool" % [str_t, dex_t, item_watk],
		str_t == 13 and dex_t == 4 and int(bon.get("watk", 0)) == item_watk and stats.total_watk == item_watk,
		"base %s, gear %s, PlayerCombatStats totals %s watk %d wdef %d (canonical floor(STR/4)+gear = %d)" % [
			c.base_stats, bon, stats.totals, stats.total_watk, stats.wdef, wdef_c])
	if stats.wdef != wdef_c:
		stat_bad.append("WDEF %d vs canonical %d" % [stats.wdef, wdef_c])


func _check_spawns_here(mob: String, map: String) -> void:
	var canon_maps: Array = []
	for s: Dictionary in db.monster(mob).get("spawns", []):
		if bool(s.get("maple_island", false)):
			canon_maps.append(String(s.get("map_id", "")))
	var live := 0
	for m: Monster in d.monsters().live_monsters():
		if m.def.id == mob:
			live += 1
	d.check("%s (%s) canonically spawns in %s, %d live here" % [_mob_name(mob), mob, map, live],
		map in canon_maps and live > 0, "canonical Maple Island maps %s" % [canon_maps])


# =================================================================================================================
# Signal wiring
# =================================================================================================================

func _connect_all() -> void:
	var pc := d.combat()
	pc.connect(&"attack_started", _on_attack_started)
	pc.connect(&"attack_resolved", _on_attack_resolved)
	var ms := d.monsters()
	ms.connect(&"player_touched", _on_touched)
	ms.connect(&"monster_died", _on_died)
	d.events().connect(&"exp_gained", _on_exp)
	d.events().connect(&"loot_dropped", _on_loot)
	d.events().connect(&"monster_killed", _on_killed)
	d.loot().connect(&"drop_spawned", _on_drop_spawned)
	d.get_tree().physics_frame.connect(_tick)
	_reconnect_view()


func _disconnect_all() -> void:
	# A knockback track still open when the recorders stop (the run ended inside it, or a death paused the game in
	# it) cannot be measured: it counts as interrupted, with the player's state, rather than as a lost knockback.
	if not _kbp.is_empty():
		kb_interrupted += 1
		kb_interrupts.append({"t": _kbp["t"], "mob": _kbp["mob"], "step_m": 0.0, "session": "open at the end of the run",
			"dead": d.game().is_character_dead(), "hp": d.character().hp})
		_kbp = {}
	var pc := d.combat()
	if pc != null:
		pc.disconnect(&"attack_started", _on_attack_started)
		pc.disconnect(&"attack_resolved", _on_attack_resolved)
	var ms := d.monsters()
	if ms != null:
		ms.disconnect(&"player_touched", _on_touched)
		ms.disconnect(&"monster_died", _on_died)
	d.events().disconnect(&"exp_gained", _on_exp)
	d.events().disconnect(&"loot_dropped", _on_loot)
	d.events().disconnect(&"monster_killed", _on_killed)
	d.loot().disconnect(&"drop_spawned", _on_drop_spawned)
	d.get_tree().physics_frame.disconnect(_tick)
	if _view != null and is_instance_valid(_view) and _view.is_connected(&"monster_spawned", _on_view_spawned):
		_view.disconnect(&"monster_spawned", _on_view_spawned)


func _reconnect_view() -> void:
	var v: Node = d.monsters().get("view")
	if v == _view:
		return
	if _view != null and is_instance_valid(_view) and _view.is_connected(&"monster_spawned", _on_view_spawned):
		_view.disconnect(&"monster_spawned", _on_view_spawned)
	_view = v
	if _view != null:
		_view.connect(&"monster_spawned", _on_view_spawned)


func _clock() -> float:
	return float(d.game().clock)


# =================================================================================================================
# Recorders
# =================================================================================================================

func _on_attack_started(action: String, pres: String, lockout_s: float) -> void:
	var p := d.player()
	var c := d.character()
	var feet := p.global_position
	var facing := p.facing
	var cands: Array = []
	for m: Monster in d.monsters().live_monsters():
		var g := _geom(feet, facing, m.global_position)
		g["iid"] = m.get_instance_id()
		g["mob"] = m.def.id
		g["order"] = m.spawn_order
		g["overlap"] = _oracle_overlap(pres, c.level, g, m.def.id)
		cands.append(g)
	_snap = {"frame": Engine.get_physics_frames(), "t": d.game_s(), "action": action, "pres": pres,
		"lockout_s": lockout_s, "feet": feet, "facing": facing, "level": c.level, "map": d.current_map(),
		"stats": PlayerCombatStats.from_character(c, db), "bonuses": c.equipment.total_bonuses(db),
		"base": c.base_stats.duplicate(), "cands": cands, "press_frame": _press_frame, "probe": _probe_tag,
		"airborne": not p.is_on_floor()}
	if _press_frame >= 0:
		_latency.append(Engine.get_physics_frames() - _press_frame)
		_press_frame = -1
	_hold_frames.append(Engine.get_physics_frames())


func _on_attack_resolved(target: Node, res: DamageResult) -> void:
	var s := _snap
	var expected_iid := 0
	var best := INF
	var best_order := 1 << 30
	for g: Dictionary in s.get("cands", []):
		if not bool(g["overlap"]):
			continue
		var dist := Vector2(float(g["fwd_px"]), float(g["lat_px"])).length()
		if dist < best - 1e-6 or (absf(dist - best) <= 1e-6 and int(g["order"]) < best_order):
			best = dist
			best_order = int(g["order"])
			expected_iid = int(g["iid"])
	var rec := {"t": snappedf(float(s.get("t", 0.0)), 0.001), "map": s.get("map", ""), "action": s.get("action", ""),
		"pres": s.get("pres", ""), "level": int(s.get("level", 0)), "probe": s.get("probe", "")}
	var actual_iid := target.get_instance_id() if target != null else 0
	# Which monster the attack hit (0 = a whiff): the reach probes classify by identity, never by "something was hit".
	rec["iid"] = actual_iid
	if actual_iid != expected_iid:
		target_mismatch.append({"t": rec["t"], "map": rec["map"], "pres": rec["pres"], "actual": actual_iid,
			"expected": expected_iid, "cands": _cand_summary(s.get("cands", []))})
	if target == null:
		rec["nearest"] = _nearest_summary(s.get("cands", []))
		whiffs.append(rec)
		attacks.append({"t": rec["t"], "hit": false, "probe": rec["probe"]})
		return
	var mob := String(target.get("def").get("id"))
	var g_t: Dictionary = {}
	for g: Dictionary in s.get("cands", []):
		if int(g["iid"]) == actual_iid:
			g_t = g
	rec["mob"] = mob
	rec["missed"] = res.missed
	rec["final"] = res.final
	rec["critical"] = res.critical
	rec["res_action"] = res.action
	rec["fwd_m"] = snappedf(float(g_t.get("fwd_px", 0.0)) * WorldScale.actor(1.0), 0.001)
	rec["lat_m"] = snappedf(float(g_t.get("lat_px", 0.0)) * WorldScale.actor(1.0), 0.001)
	rec["up_m"] = snappedf(float(g_t.get("up_px", 0.0)) * WorldScale.actor(1.0), 0.001)
	rec["kb"] = res.knockback
	attacks.append({"t": rec["t"], "hit": true, "probe": rec["probe"]})
	if not res.missed:
		var w := _oracle_window(mob, String(s["action"]), int(s["level"]), res.critical, s.get("base", {}), s.get("bonuses", {}))
		rec["lo"] = w.x
		rec["hi"] = w.y
		if res.final < w.x or res.final > w.y:
			range_fail.append(rec.duplicate())
		var cf := CombatFormula.damage_window(s["stats"], target.get("def").stats, db,
			{"action": String(s["action"]), "critical": res.critical})
		if int(cf["min"]) != w.x or int(cf["max"]) != w.y:
			formula_disagree.append({"mob": mob, "action": s["action"], "level": s["level"], "crit": res.critical,
				"oracle": [w.x, w.y], "combat_formula": [cf["min"], cf["max"]]})
		var m := target as Monster
		if res.knockback and m.is_alive():
			var away := Vector3(m.global_position.x - (s["feet"] as Vector3).x, 0.0, m.global_position.z - (s["feet"] as Vector3).z)
			var dir := away.normalized() if away.length() > 1e-4 else -(s["facing"] as Vector3)
			_kbm.append({"iid": actual_iid, "mob": mob, "m0": m.global_position, "away": dir, "ticks": 0,
				"blocked_at_hit": m.probe(m.brain.push_dir), "t": rec["t"], "airborne": m.airborne,
				"mode_at_hit": MonsterBrain.Mode.keys()[m.brain.mode], "push_m": 0.0, "cut_short": false})
		rec["target_airborne"] = m.airborne
	hits.append(rec)


func _on_touched(m: Monster, res: IncomingResult) -> void:
	var p := d.player()
	var c := d.character()
	var stats := PlayerCombatStats.from_character(c, db)
	var bon: Dictionary = c.equipment.total_bonuses(db)
	var str_t := int(c.base_stats.get("str", 0)) + int(bon.get("str", 0))
	var wdef_c := int(floor(str_t / 4.0)) + int(bon.get("wdef", 0))
	var now := _clock()
	var rec := {"t": snappedf(d.game_s(), 0.001), "clock": snappedf(now, 0.001), "map": d.current_map(), "mob": m.def.id,
		"level": c.level, "wdef": stats.wdef, "landed": res.landed(), "missed": res.missed, "guarded": res.guarded,
		"final": res.final, "knockback": res.knockback, "hp_after": c.hp, "invuln_left": snappedf(p.invulnerable_time_left(), 0.0001),
		"hit_chance": snappedf(CombatFormula.incoming_hit_chance(float(m.def.stats.acc), float(stats.avoid), c.level,
			m.def.stats.level, db), 0.0001),
		"dist_m": snappedf(Vector2(p.global_position.x - m.global_position.x, p.global_position.z - m.global_position.z).length(), 0.001),
		"overlap_oracle": _touch_overlap_oracle(m, p.global_position)}
	var r := _oracle_touch(m.def.id, c.level, wdef_c)
	rec["lo"] = r.x
	rec["hi"] = r.y
	var kr := CombatFormula.incoming_damage_range(float(m.def.stats.pdmg), float(stats.wdef), c.level, db)
	rec["cf_lo"] = int(kr["taken_min"])
	rec["cf_hi"] = int(kr["taken_max"])
	if res.landed() and (res.final < r.x or res.final > r.y):
		touch_fail.append(rec.duplicate())
	if _last_touch_clock >= 0.0:
		_touch_gaps.append(snappedf(now - _last_touch_clock, 0.0001))
	_last_touch_clock = now
	touches.append(rec)
	if res.knockback:
		var away := Vector3(p.global_position.x - m.global_position.x, 0.0, p.global_position.z - m.global_position.z)
		var dir := away.normalized() if away.length() > 1e-4 else -p.facing
		_kbp = {"p0": p.global_position, "away": dir, "ticks": 0, "max_rise": 0.0, "mob": m.def.id,
			"t": rec["t"], "offset_m": snappedf(away.length(), 0.0001),
			"at_touch": {"in_hitstun": p.in_hitstun, "on_floor": p.is_on_floor(), "climbing": p.is_climbing(),
				"attacking": bool(d.combat().call("is_attacking")), "hitstun_t": snappedf(float(p.get("_hitstun_t")), 0.001)}}


func _on_died(m: Monster) -> void:
	var now := _clock()
	var rec := {"t": snappedf(d.game_s(), 0.001), "clock": now, "map": m.map_id, "mob": m.def.id, "slot": m.slot_index,
		"hp": m.hp, "alive": m.is_alive(), "targetable": d.monsters().live_monsters().has(m),
		"fade_expected_s": float(db.monster(m.def.id).get("die_fade_ms", 0)) / 1000.0, "iid": m.get_instance_id()}
	kills.append(rec)
	if m.slot_index >= 0:
		_pending_deaths["%s#%d" % [m.map_id, m.slot_index]] = now
	_check_fading.append({"iid": m.get_instance_id(), "t0": d.game_s(), "mob": m.def.id})
	m.tree_exiting.connect(_on_monster_exit.bind(m.get_instance_id(), d.game_s(), float(rec["fade_expected_s"]), m.def.id),
		CONNECT_ONE_SHOT)


func _on_monster_exit(iid: int, t0: float, expected: float, mob: String) -> void:
	fades.append({"iid": iid, "mob": mob, "fade_s": snappedf(d.game_s() - t0, 0.001), "expected_s": expected})


func _on_exp(amount: int, source: String) -> void:
	if not source.begins_with("monster:"):
		return
	var mob := source.substr(8)
	var canon := int(db.monster(mob).get("exp", -1))
	exp_events.append({"mob": mob, "amount": amount, "canonical": canon})
	if amount != canon:
		exp_bad.append({"mob": mob, "amount": amount, "canonical": canon})


## Events.monster_killed comes before Events.loot_dropped in MonsterSystem.on_monster_died (MonsterSystem.monster_died
## comes after both), so the species of a drop is the last monster_killed.
func _on_killed(mob: String, _map_id: String) -> void:
	_last_killed = mob


func _on_loot(list: Array, at: Vector3, map_id: String) -> void:
	var mob := _last_killed
	var table := {}
	for e: Dictionary in db.drop_table(mob).get("entries", []):
		table[String(e.get("item_id", ""))] = String(e.get("status", ""))
	var meso := DropRates.meso_rule(mob, db)
	var rec := {"mob": mob, "map": map_id, "drops": list.duplicate(true), "at": at}
	for dr: Dictionary in list:
		if String(dr.get("kind", "")) == "mesos":
			var amt := int(dr.get("amount", 0))
			if float(meso.get("chance", 0.0)) <= 0.0 or amt < int(meso.get("min", 0)) or amt > int(meso.get("max", 0)):
				loot_bad.append({"mob": mob, "drop": dr, "why": "mesos outside the rule %s" % [meso]})
		else:
			var id := String(dr.get("item_id", ""))
			if not table.has(id):
				loot_bad.append({"mob": mob, "drop": dr, "why": "item not in drops/%s.json" % mob})
	loot_events.append(rec)


func _on_drop_spawned(node: Node) -> void:
	var r: Dictionary = node.get("record")
	ground_nodes.append({"kind": String(r.get("kind", "")), "item_id": String(r.get("item_id", "")),
		"amount": int(r.get("amount", 0))})


## A slot monster appeared. After the arrival's realize queue (_visit_ready_t) every appearance is a respawn: the
## canonical model (spawn_rate.json) says it must come on a global tick boundary (k x 7.56 s of the game clock) and
## only from a slot whose death + wave cooldown is at or before that boundary. Which eligible slot refills is the
## game's seeded pick (capacity < spawn points), so a refill is checked per boundary, not per killed slot.
func _on_view_spawned(node: Node3D, slot: SpawnSlot) -> void:
	_fresh[node.get_instance_id()] = true
	if slot == null or _view == null or d.game_s() < _visit_ready_t:
		return
	var map := String(node.get_meta("map_id", d.current_map()))
	var key := "%s#%d" % [map, slot.index]
	var tick := float(spawn_f.get("global_respawn_tick_s", 0.0))
	var cool := float(spawn_f.get("wave_point_cooldown_s", 0.0)) if slot.mob_time_s <= 0.0 else slot.mob_time_s
	var now := _clock()
	var k := floori(now / tick + 1e-9)
	var boundary := k * tick
	var died_at: float = _pending_deaths.get(key, -1.0)
	_pending_deaths.erase(key)
	# A respawn the view held back while the player stood on its slot (presentation.json
	# spawns.respawn_player_clearance_m) came back in the state on its tick and appears late by design.
	var waited := bool(_view.call("respawn_waited", slot.index)) if _view.has_method("respawn_waited") else false
	spawn_refills.append({"map": map, "slot": slot.index, "mob": slot.mob_id, "clock": snappedf(now, 0.001),
		"boundary": snappedf(boundary, 0.001), "delay": snappedf(now - boundary, 0.0001), "waited_for_player": waited,
		"died_at": snappedf(died_at, 0.001), "killed_this_visit": died_at >= 0.0,
		"eligible": died_at < 0.0 or died_at + cool <= boundary + 1e-6,
		"same_slot_since_death": snappedf(now - died_at, 0.001) if died_at >= 0.0 else -1.0})


## Per boundary: one frame or more after each tick boundary, the instance must be at capacity unless no dead slot is
## eligible (death + cooldown after the boundary). Also checks the capacity against spawn_rate.json (solo scalar).
func _check_capacity(p: Node3D) -> void:
	var st: MapInstanceState = _view.get("state") if _view != null else null
	var s := d.session()
	if st == null or s == null or String(s.call("state_name")) != "IDLE" or d.game_s() < _visit_ready_t:
		_cap["map"] = ""
		return
	var tick := float(spawn_f.get("global_respawn_tick_s", 0.0))
	var k := floori(_clock() / tick + 1e-9)
	if String(_cap["map"]) != st.map_id:
		_cap = {"map": st.map_id, "k": k, "due": -1, "due_k": -1}
		return
	if k > int(_cap["k"]):
		_cap["k"] = k
		_cap["due"] = Engine.get_physics_frames() + 3
		_cap["due_k"] = k
	if int(_cap["due"]) >= 0 and Engine.get_physics_frames() >= int(_cap["due"]):
		_cap["due"] = -1
		var boundary := int(_cap["due_k"]) * tick
		var cool := float(spawn_f.get("wave_point_cooldown_s", 0.0))
		var eligible_left := 0
		for i in st.slots.size():
			var sl: Dictionary = st.slots[i]
			if bool(sl.get("alive", false)):
				continue
			var c := cool if st.mob_times[i] <= 0.0 else st.mob_times[i]
			if float(sl.get("died_at", -1.0)) + c <= boundary + 1e-6:
				eligible_left += 1
		var pts := (db.map(st.map_id).get("spawns", []) as Array).size()
		var scalar := 0
		for row: Dictionary in (spawn_f.get("capacity", {}) as Dictionary).get("player_scalar_table", []):
			if String(row.get("players", "")) == "1":
				scalar = int(row.get("scalar_pct", 0))
		var canon_cap := pts * scalar / 100
		# kills between the boundary and this check (3 frames) lower the count legitimately
		var died_since := 0
		for kr: Dictionary in kills:
			if String(kr["map"]) == st.map_id and float(kr["clock"]) > boundary + 1e-9:
				died_since += 1
		var rec := {"map": st.map_id, "boundary": snappedf(boundary, 0.001), "alive": st.alive_count(), "capacity": st.capacity,
			"canonical_capacity": canon_cap, "eligible_left": eligible_left, "died_since": died_since}
		capacity_checks.append(rec)
		if st.capacity != canon_cap or (st.alive_count() + died_since < st.capacity and eligible_left > 0):
			capacity_bad.append(rec)


func _tick() -> void:
	var p := d.player()
	if p == null or not is_instance_valid(p):
		return
	monitor["ticks"] = int(monitor["ticks"]) + 1
	_check_capacity(p)
	# player knockback arc (abandoned when a warp or a teleport interrupts it)
	if not _kbp.is_empty():
		_kbp["ticks"] = int(_kbp["ticks"]) + 1
		_kbp["max_rise"] = maxf(float(_kbp["max_rise"]), p.global_position.y - (_kbp["p0"] as Vector3).y)
		if int(_kbp["ticks"]) == 1:
			_kbp["first_tick"] = {"in_hitstun": p.in_hitstun, "on_floor": p.is_on_floor(),
				"moved_m": snappedf(p.global_position.distance_to(_kbp["p0"]), 0.0001), "session": String(d.session().call("state_name"))}
		var step_m := p.global_position.distance_to(_kbp.get("last", _kbp["p0"]))
		_kbp["last"] = p.global_position
		if step_m > 1.0 or String(d.session().call("state_name")) != "IDLE":
			kb_interrupted += 1
			kb_interrupts.append({"t": _kbp["t"], "mob": _kbp["mob"], "step_m": snappedf(step_m, 0.001), "session": String(d.session().call("state_name"))})
			_kbp = {}
		elif not p.in_hitstun or int(_kbp["ticks"]) > 120:
			var disp := p.global_position - (_kbp["p0"] as Vector3)
			var flat := Vector3(disp.x, 0.0, disp.z)
			kb_player.append({"mob": _kbp["mob"], "t": _kbp["t"], "airtime_s": snappedf((int(_kbp["ticks"]) - 1) / 60.0, 0.001),
				"rise_m": snappedf(float(_kbp["max_rise"]), 0.001), "dist_m": snappedf(flat.length(), 0.001),
				"dy_m": snappedf(disp.y, 0.001), "cos_away": snappedf(flat.normalized().dot(_kbp["away"]) if flat.length() > 1e-3 else 0.0, 0.001),
				"timeout": int(_kbp["ticks"]) > 120, "offset_m": _kbp["offset_m"], "at_touch": _kbp["at_touch"],
				"first_tick": _kbp.get("first_tick", {})})
			_kbp = {}
	# monster stagger push
	var keep: Array = []
	for tr: Dictionary in _kbm:
		var o := instance_from_id(int(tr["iid"]))
		var m := o as Monster
		if m == null or not is_instance_valid(m) or not m.is_alive():
			continue
		tr["ticks"] = int(tr["ticks"]) + 1
		if m.brain.mode != MonsterBrain.Mode.STAGGER:
			var row: Dictionary = db.monster(String(tr["mob"]))
			# The canonical stagger time: the record's STAGGER field when it has one, else its hit1 clip.
			var hit1 := MonsterDef.canonical_stagger_s(row)
			if hit1 <= 0.0:
				hit1 = float(((row.get("animations", {}) as Dictionary).get("hit1", {}) as Dictionary).get("duration_ms", 0)) / 1000.0
			# push_m: the displacement along `away` at the last tick still staggered (the push alone, before the chase)
			kb_monster.append({"mob": tr["mob"], "t": tr["t"], "stagger_s": snappedf(int(tr["ticks"]) / 60.0, 0.001),
				"expected_s": hit1, "push_m": snappedf(float(tr["push_m"]), 0.001), "blocked_at_hit": tr["blocked_at_hit"],
				"cut_short": tr["cut_short"], "airborne": tr["airborne"], "mode_at_hit": tr["mode_at_hit"],
				"staggered": int(tr["ticks"]) > 1})
			continue
		var disp := m.global_position - (tr["m0"] as Vector3)
		tr["push_m"] = Vector3(disp.x, 0.0, disp.z).dot(tr["away"])
		if m.brain.push_left <= 0.0 and m.brain.timer > 1.5 / 60.0:
			tr["cut_short"] = true
		keep.append(tr)
	_kbm = keep
	# death fade started
	for f: Dictionary in _check_fading:
		var mo := instance_from_id(int(f["iid"])) as Monster
		if mo != null and is_instance_valid(mo) and mo.visual != null and not mo.visual.is_fading():
			stat_bad.append("monster %s killed at %.2f s is not fading on the next tick" % [f["mob"], float(f["t0"])])
	_check_fading.clear()
	# touch gating: overlaps of a touch-active monster with a vulnerable, alive, idle player must have touched
	var s := d.session()
	if p.is_dead() or s == null or String(s.call("state_name")) != "IDLE":
		return
	var body: Vector2 = d.monsters().call("_player_body")
	var fresh := _fresh
	_fresh = {}
	for m: Monster in d.monsters().live_monsters():
		if not MeleeQuery.touch_overlaps(m.global_position, m.facing, m.def.touch_size_m, p.global_position, body.x, body.y):
			continue
		if fresh.has(m.get_instance_id()):
			monitor["spawned_on_player"] = int(monitor.get("spawned_on_player", 0)) + 1
		elif not m.touch_active():
			monitor["peace_ticks"] = int(monitor["peace_ticks"]) + 1
		elif p.is_invulnerable():
			monitor["suppressed"] = int(monitor["suppressed"]) + 1
		else:
			monitor["unexplained"] = int(monitor["unexplained"]) + 1
			if (monitor["unexplained_samples"] as Array).size() < 10:
				(monitor["unexplained_samples"] as Array).append({"t": snappedf(d.game_s(), 0.001), "mob": m.def.id,
					"map": d.current_map(), "dist": snappedf(Vector2(p.global_position.x - m.global_position.x,
						p.global_position.z - m.global_position.z).length(), 0.001)})


# =================================================================================================================
# Oracles (canonical data, computed here)
# =================================================================================================================

## Player-frame geometry of a point, in px (actor scale): forward along the facing, up, lateral.
func _geom(feet: Vector3, facing: Vector3, pos: Vector3) -> Dictionary:
	var f := Vector3(facing.x, 0.0, facing.z)
	f = f.normalized() if f.length_squared() > 1e-8 else Vector3.FORWARD
	var lat := Vector3.UP.cross(f)
	var rel := pos - feet
	var k := WorldScale.actor(1.0)
	return {"fwd_px": rel.dot(f) / k, "up_px": rel.y / k, "lat_px": rel.dot(lat) / k}


## The canonical box of a Sword presentation (attack_styles.json, facing LEFT: [left, top, right, bottom], y down).
func _box_px(pres: String, level: int) -> Array:
	var set_name := String(weapon_row.get("hitzone_set", ""))
	var hz: Dictionary = (styles_f.get("hitzone_sets", {}) as Dictionary).get(set_name, {})
	if level >= 100 and (hz.get("level100", {}) as Dictionary).has(pres):
		return hz["level100"][pres]["box_px"]
	return ((hz.get("ordinary", {}) as Dictionary).get(pres, {}) as Dictionary).get("box_px", [0, 0, 0, 0])


## Strict overlap of the mirrored canonical box (depth from combat.json isometric_reach) with the monster's canonical
## touch zone (depth = width), all in px relative to the attacker's feet.
func _oracle_overlap(pres: String, level: int, g: Dictionary, mob: String) -> bool:
	var box := _box_px(pres, level)
	var a_f0 := -float(box[2])
	var a_f1 := -float(box[0])
	var a_u0 := -float(box[3])
	var a_u1 := -float(box[1])
	var tz: Array = db.monster(mob).get("touch_zone_px", [0, 0])
	var w := float(tz[0])
	var h := float(tz[1])
	var depth := float((combat_m.get("isometric_reach", {}) as Dictionary).get("attack_box_depth_px", 0.0))
	var fwd := float(g["fwd_px"])
	var up := float(g["up_px"])
	var lat := float(g["lat_px"])
	if a_f0 == a_f1:
		return false
	return maxf(a_f0, fwd - w / 2.0) < minf(a_f1, fwd + w / 2.0) \
		and maxf(a_u0, up) < minf(a_u1, up + h) \
		and maxf(-depth / 2.0, lat - w / 2.0) < minf(depth / 2.0, lat + w / 2.0)


## Why the nearest monster was not hit: behind / too_far / near_gap / lateral / height.
func _whiff_reason(pres: String, level: int, g: Dictionary) -> String:
	var box := _box_px(pres, level)
	var a_f0 := -float(box[2])
	var a_f1 := -float(box[0])
	var a_u0 := -float(box[3])
	var a_u1 := -float(box[1])
	var tz: Array = db.monster(String(g["mob"])).get("touch_zone_px", [0, 0])
	var w := float(tz[0])
	var h := float(tz[1])
	var depth := float((combat_m.get("isometric_reach", {}) as Dictionary).get("attack_box_depth_px", 0.0))
	var fwd := float(g["fwd_px"])
	if not (maxf(-depth / 2.0, float(g["lat_px"]) - w / 2.0) < minf(depth / 2.0, float(g["lat_px"]) + w / 2.0)):
		return "lateral"
	if fwd + w / 2.0 <= a_f0:
		return "behind" if fwd < 0.0 else "near_gap"
	if fwd - w / 2.0 >= a_f1:
		return "too_far"
	if not (maxf(a_u0, float(g["up_px"])) < minf(a_u1, float(g["up_px"]) + h)):
		return "height"
	return "overlaps?"


## The per-hit damage window from damage.json (no AP term, no mastery for a Beginner, WDEF from the monster record,
## neutral element, level gap, critical x (1 + d)), trunc(clamp()).
func _oracle_window(mob: String, action: String, level: int, crit: bool, base: Dictionary, bon: Dictionary) -> Vector2i:
	var k := _raw_ctx(mob, action, level, base, bon)
	var c := 1.0 + float((dmg_f.get("critical", {}) as Dictionary).get("base_damage_d", 0.0)) if crit else 1.0
	return Vector2i(_finalize(_raw(k, 0.0, 0.0) * float(k["post"]) * c), _finalize(_raw(k, 1.0, 1.0) * float(k["post"]) * c))


func _raw_ctx(mob: String, action: String, level: int, base: Dictionary, bon: Dictionary) -> Dictionary:
	var phys: Dictionary = dmg_f.get("physical", {})
	var mult := float(weapon_row.get("swing_mult" if action == "swing" else "stab_mult", 0.0))
	var mon := db.monster(mob)
	var def := float(mon.get("physical_defense", 0))
	var gap := int(mon.get("level", 1)) - level
	var scale := 1.0
	var br: Array = (dmg_f.get("level_gap", {}) as Dictionary).get("branches", [])
	if gap >= 1 and gap <= 9:
		scale = 1.0 / (1.0 + gap * gap * float(br[1].get("coefficient", 0.0)))
	elif gap >= 10:
		scale = 1.0 / (1.0 + gap * float(br[2].get("coefficient", 0.0)))
	return {
		"watk": float(bon.get("watk", 0)),
		"P": float(int(base.get("str", 0)) + int(bon.get("str", 0))),
		"S": float(int(base.get("dex", 0)) + int(bon.get("dex", 0))),
		"M": float((phys.get("mastery", {}) as Dictionary).get("no_mastery_factor", 0.0)),
		"mult": mult,
		"bmin": float((phys.get("base_roll", {}) as Dictionary).get("min", 0.0)),
		"bmax": float((phys.get("base_roll", {}) as Dictionary).get("max", 0.0)),
		"div": float((phys.get("ordinary_divisors", {}) as Dictionary).get("stat_div", 1.0)),
		"post": 100.0 / (def + 100.0) * scale,
	}


func _raw(k: Dictionary, bu: float, su: float) -> float:
	var b := float(k["bmin"]) + (float(k["bmax"]) - float(k["bmin"])) * bu
	var q := float(k["P"]) * (float(k["M"]) + su * (1.0 - float(k["M"])))
	return float(k["watk"]) * (b + (q * float(k["mult"]) + float(k["S"])) / float(k["div"]))


func _finalize(v: float) -> int:
	var fc: Dictionary = dmg_f.get("final_clamp", {})
	return int(clampf(v, float(fc.get("min", 1)), float(fc.get("max", 99999))))


## Touch damage window from accuracy.json incoming_damage: trunc(MobPDMG x ratio/100), roll 1.1-1.5, the DEF curve.
func _oracle_touch(mob: String, level: int, wdef: int) -> Vector2i:
	var inc: Dictionary = acc_f.get("incoming_damage", {})
	var atk := int(float(db.monster(mob).get("physical_damage", 0)) * float(inc.get("touch_attack_ratio", 100)) / 100.0)
	var roll: Dictionary = inc.get("roll", {})
	var curve: Dictionary = inc.get("defense_curve", {})
	var cl: Dictionary = inc.get("clamp", {})
	var out: Array = []
	for r in [float(roll.get("min", 0.0)), float(roll.get("max", 0.0))]:
		var raw: float = atk * r
		var taken := raw * (1.0 - wdef / (wdef + float(curve.get("def_level_multiplier", 0)) * (level + float(curve.get("def_level_offset", 0)))
			+ float(curve.get("raw_coefficient", 0)) * raw))
		out.append(int(clampf(taken, float(cl.get("min", 1)), float(cl.get("max", 5e7)))))
	return Vector2i(out[0], out[1])


## The canonical touch zone (px x WorldScale.actor, depth = width) at the monster's feet along its facing, against
## the player's body capsule (player.tscn Hurtbox).
func _touch_overlap_oracle(m: Monster, feet: Vector3) -> bool:
	var tz: Array = db.monster(m.def.id).get("touch_zone_px", [0, 0])
	var size := Vector3(WorldScale.actor(float(tz[0])), WorldScale.actor(float(tz[1])), WorldScale.actor(float(tz[0])))
	var body: Vector2 = d.monsters().call("_player_body")
	return MeleeQuery.touch_overlaps(m.global_position, m.facing, size, feet, body.x, body.y)


func _cand_summary(cands: Array) -> Array:
	var out: Array = []
	for g: Dictionary in cands:
		var dist := Vector2(float(g["fwd_px"]), float(g["lat_px"])).length()
		if dist < 160.0:
			out.append({"mob": g["mob"], "fwd_px": snappedf(float(g["fwd_px"]), 0.1), "lat_px": snappedf(float(g["lat_px"]), 0.1),
				"up_px": snappedf(float(g["up_px"]), 0.1), "overlap": g["overlap"], "iid": g["iid"]})
	return out


func _nearest_summary(cands: Array) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for g: Dictionary in cands:
		var dist := Vector2(float(g["fwd_px"]), float(g["lat_px"])).length()
		if dist < bd:
			bd = dist
			best = g
	if best.is_empty():
		return {}
	return {"mob": best["mob"], "fwd_m": snappedf(float(best["fwd_px"]) * WorldScale.actor(1.0), 0.001),
		"lat_m": snappedf(float(best["lat_px"]) * WorldScale.actor(1.0), 0.001),
		"up_m": snappedf(float(best["up_px"]) * WorldScale.actor(1.0), 0.001),
		"dist_m": snappedf(bd * WorldScale.actor(1.0), 0.001),
		"reason": _whiff_reason(String(_snap.get("pres", "")), int(_snap.get("level", 1)), best)}


# =================================================================================================================
# Play
# =================================================================================================================

func _hits_on(mob: String) -> int:
	var n := 0
	for h: Dictionary in hits:
		if String(h.get("mob", "")) == mob and not bool(h.get("missed", false)):
			n += 1
	return n


func _kills_of(mob: String) -> int:
	var n := 0
	for k: Dictionary in kills:
		if String(k["mob"]) == mob:
			n += 1
	return n


func _max_touch_here() -> int:
	var hi := 1
	var c := d.character()
	for m: Monster in d.monsters().live_monsters():
		hi = maxi(hi, _oracle_touch(m.def.id, c.level, 0).y)
	return hi


func _heal_if_low() -> void:
	var c := d.character()
	var max_hp := StatCalculator.max_hp(c, db)
	if c.hp <= mini(max_hp - 1, 3 * _max_touch_here() + 1) and not d.game().is_character_dead():
		heals += 1
		await d.console("heal")


func _recover_if_dead(map: String) -> void:
	if not d.game().is_character_dead() and not d.player().is_dead():
		return
	deaths_of_player += 1
	d.note("the player died at %.1f s in %s (HP %d)" % [d.game_s(), map, d.character().hp])
	await d.wait(3.0)
	await d.console("respawn")
	await d.wait_idle(20.0)
	await _warp(map)


func _fight_species(mob: String, map: String) -> void:
	var i := d._begin(PlaytestReport.KIND_PLAY, "fight_species", "%s in %s until %d hits and 2 kills" % [_mob_name(mob), map, hit_target])
	var t0 := d.game_s()
	var excluded_at := {}
	var zero_on := {}
	while d.game_s() - t0 < SPECIES_BUDGET_S:
		if _hits_on(mob) >= hit_target and _kills_of(mob) >= 2:
			break
		await _recover_if_dead(map)
		await _heal_if_low()
		# a skipped monster is tried again after 30 s: it wanders
		var exclude := {}
		for k: int in excluded_at.keys():
			if d.game_s() - float(excluded_at[k]) < 30.0:
				exclude[k] = true
		var target := d.nearest_monster({"mob_id": mob, "exclude": exclude, "max_dist_m": 80.0})
		if target == null:
			await d.wait(1.0)
			continue
		var tid := target.get_instance_id()
		var a0 := attacks.size()
		var r: Dictionary = await d.face_and_attack_nearest(FIGHT_CALL_S, {"mob_id": mob, "exclude": exclude, "max_dist_m": 80.0})
		if attacks.size() > a0 or not is_instance_valid(target) or not bool(target.call("is_alive")):
			zero_on.erase(tid)
			continue
		# No attack on this target in the call. The driver only swings inside 0.6 x the shortest presentation's reach;
		# when a prop holds the player farther out, swing from where it stands if the longest presentation reaches.
		var swung: int = await _edge_attack(target as Monster)
		if swung > 0:
			zero_on.erase(tid)
			continue
		zero_on[tid] = int(zero_on.get(tid, 0)) + 1
		if int(zero_on[tid]) >= 2 or String(r["why"]).begins_with("could not reach"):
			excluded_at[tid] = d.game_s()
			zero_on.erase(tid)
			var p := d.player()
			var to := target.global_position - p.global_position
			unreachable.append({"mob": mob, "map": map, "t": snappedf(d.game_s(), 0.01),
				"monster_local": _local(target.global_position), "player_local": _local(p.global_position),
				"flat_m": snappedf(Vector2(to.x, to.z).length(), 0.01), "dy_m": snappedf(to.y, 0.01), "why": String(r["why"])})
	var ok := _hits_on(mob) >= hit_target and _kills_of(mob) >= 2
	d._end(i, ok, "%d hits, %d kills in %.1f s" % [_hits_on(mob), _kills_of(mob), d.game_s() - t0])
	d.check("%s: at least %d landed hits and 2 kills by real attacks" % [_mob_name(mob), hit_target], ok,
		"%d hits, %d kills in %.1f s game time" % [_hits_on(mob), _kills_of(mob), d.game_s() - t0])


## Faces `m` and taps the attack key up to 3 times when it stands within the longest Sword presentation's reach
## (attack_styles.json) at about the same height. Returns the attacks made (the oracle judges each one).
func _edge_attack(m: Monster) -> int:
	if m == null or not is_instance_valid(m) or not m.is_alive():
		return 0
	var p := d.player()
	var far_px := 0.0
	for pres: String in ["swingO1", "swingO2", "swingO3", "stabO1", "stabO2"]:
		far_px = maxf(far_px, -float(_box_px(pres, d.character().level)[0]))
	var tz: Array = db.monster(m.def.id).get("touch_zone_px", [0, 0])
	var reach := WorldScale.actor(far_px + float(tz[0]) / 2.0)
	var n := 0
	for _k in 3:
		if not is_instance_valid(m) or not m.is_alive():
			break
		var to := m.global_position - p.global_position
		if Vector2(to.x, to.z).length() > reach - 0.05 or absf(to.y) > 0.8:
			break
		await d.wait_until(func() -> bool: return bool(d.combat().call("can_attack")), 1.0)
		d.input.set_move_world(Vector3(to.x, 0.0, to.z).normalized() * 0.2, p.view_right, p.view_forward)
		await d.get_tree().physics_frame
		await d.get_tree().process_frame
		d.input.release_movement()
		var rec := await _tap_attack("edge")
		if not rec.is_empty():
			n += 1
	return n


func _local(pos: Vector3) -> Vector3:
	var w := d.world()
	if w == null or w.defs == null or not w.defs.has_map(d.current_map()):
		return pos
	var l: Vector3 = w.defs.get_def(d.current_map()).to_local(pos)
	return Vector3(snappedf(l.x, 0.01), snappedf(l.y, 0.01), snappedf(l.z, 0.01))


## Stands in monsters of `mob` without attacking (walking into the nearest one again after each knockback) until `n`
## touches from that species or `max_s`: contact-damage samples that do not depend on the fight's geometry. A monster
## a finished walk could not bring within reach (it paces a terrace above or below the player and stays on its floor)
## is skipped for the next nearest one; a walk that only ran out of time keeps the target. The skips are forgotten when
## no other monster of the species is left.
func _touch_probe(mob: String, n: int, max_s: float) -> void:
	var i := d._begin(PlaytestReport.KIND_PLAY, "touch_probe", "walk into %s without attacking until %d touches" % [_mob_name(mob), n])
	var p := d.player()
	var from_mob := func() -> int:
		var c := 0
		for t: Dictionary in touches:
			if String(t["mob"]) == mob:
				c += 1
		return c
	var out_of_reach := func(m: Monster) -> bool:
		var v := m.global_position - p.global_position
		return Vector2(v.x, v.z).length() > 4.0 or absf(v.y) > 0.8
	var c0: int = from_mob.call()
	var t0 := d.game_s()
	var skip := {}
	var skipped := 0
	while (from_mob.call() as int) - c0 < n and d.game_s() - t0 < max_s:
		await _heal_if_low()
		var m := d.nearest_monster({"mob_id": mob, "max_dist_m": 40.0, "exclude": skip}) as Monster
		if m == null:
			skip.clear()
			await d.wait(1.0)
			continue
		if out_of_reach.call(m):
			var w: Dictionary = await d.walk_to(m.global_position, {"within_m": 1.0, "max_s": 6.0, "retries": 0})
			# Only a walk that ended (stopped next to it, stalled, fell) and still left it out of reach skips it; a walk
			# that ran out of time on a long route made progress, and the next pass walks on toward the nearest one.
			if is_instance_valid(m) and m.is_alive() and out_of_reach.call(m) and String(w.get("result", "")) != "TIMEOUT":
				skip[m.get_instance_id()] = true
				skipped += 1
			continue
		var t1 := d.game_s()
		var k0: int = from_mob.call()
		while is_instance_valid(m) and m.is_alive() and (from_mob.call() as int) == k0 and d.game_s() - t1 < 3.0:
			await d.get_tree().process_frame
			d.input.reassert()
			var v := m.global_position - p.global_position
			if Vector2(v.x, v.z).length() > 0.1 and not p.in_hitstun:
				d.input.set_move_world(Vector3(v.x, 0.0, v.z).normalized(), p.view_right, p.view_forward)
			else:
				d.input.release_movement()
		d.input.release_movement()
		await d.wait_until(func() -> bool: return not p.in_hitstun, 1.0)
	var got: int = from_mob.call() - c0
	d._end(i, got >= n, "%d touches in %.1f s; %d monsters out of reach skipped" % [got, d.game_s() - t0, skipped])


## Walks within `lo..hi` m (flat) of `m`, by real walking, then faces `toward` (true) or away from it with a slow step.
func _stand_at(m: Monster, lo: float, hi: float, toward: bool, max_s: float = 5.0) -> bool:
	var p := d.player()
	var flat := func() -> Vector3:
		var v := m.global_position - p.global_position
		return Vector3(v.x, 0.0, v.z)
	if (flat.call() as Vector3).length() > 5.0:
		await d.walk_to(m.global_position, {"within_m": 2.5, "max_s": 12.0, "retries": 0})
	var t0 := d.game_s()
	while d.game_s() - t0 < max_s:
		if not is_instance_valid(m) or not m.is_alive():
			d.input.release_movement()
			return false
		await d.get_tree().process_frame
		d.input.reassert()
		var to: Vector3 = flat.call()
		var dist := to.length()
		if p.in_hitstun:
			d.input.release_movement()
			continue
		if dist < lo:
			d.input.set_move_world(-to.normalized() if dist > 1e-3 else -p.facing, p.view_right, p.view_forward)
		elif dist > hi:
			d.input.set_move_world(to.normalized(), p.view_right, p.view_forward)
		else:
			break
	d.input.release_movement()
	await d.wait_until(func() -> bool: return bool(d.combat().call("can_attack")) and p.is_on_floor(), 2.0)
	if not is_instance_valid(m) or not m.is_alive():
		return false
	var to2: Vector3 = flat.call()
	var dir := to2.normalized() if toward else -to2.normalized()
	d.input.set_move_world(dir * 0.2, p.view_right, p.view_forward)
	await d.get_tree().physics_frame
	await d.get_tree().process_frame
	d.input.release_movement()
	await d.get_tree().physics_frame
	await d.get_tree().process_frame
	var dist2 := (flat.call() as Vector3).length()
	return dist2 >= lo - 0.15 and dist2 <= hi + 0.15


## One attack-key tap now, returning the attack record it produced ({} when none).
func _tap_attack(tag: String) -> Dictionary:
	_probe_tag = tag
	var n0 := attacks.size()
	var h0 := hits.size()
	var w0 := whiffs.size()
	_press_frame = Engine.get_physics_frames()
	await d.input.tap_action(&"attack")
	await d.wait_until(func() -> bool: return attacks.size() > n0, 0.5)
	_probe_tag = ""
	_press_frame = -1
	if attacks.size() == n0:
		return {}
	if hits.size() > h0:
		return hits.back()
	if whiffs.size() > w0:
		return whiffs.back()
	return {}


## Reach probes: the player stands 0.75-1.4 m in front of a probe Snail facing away ("behind"), or 3.2-3.9 m
## ("far") / 2.25-2.55 m ("edge") from it facing it, and taps attack once. Each probe is classified by the identity
## of what the attack hit (_classify_probe): the probe Snail ("target_hit"), another monster ("bystander_hit") or
## nothing ("whiff"). Before every tap the front must be clear (_front_clear): no other live monster may overlap any of
## the Sword's standing presentations, because a provoked bystander walks back into reach between taps. The baseline
## failure counted a bystander Snail 2.1 m in front of the player as a hit "behind" (ITERATION_LOG Phase B3).
func _reach_probes() -> void:
	var i := d._begin(PlaytestReport.KIND_PLAY, "reach_probes", "Snails behind the player (0.75-1.4 m) and in front beyond reach (3.2-3.9 m)")
	var kinds := [["behind", 0.75, 1.4, false], ["far", 3.2, 3.9, true], ["edge", 2.25, 2.55, true]]
	var want := 3 if quick else 6
	var skipped_bystander := 0
	for k: Array in kinds:
		var got := 0
		var tries := 0
		var skip := {}
		while got < want and tries < want * 6:
			tries += 1
			await _heal_if_low()
			var m := d.nearest_monster({"mob_id": "2", "max_dist_m": 40.0, "exclude": skip}) as Monster
			if m == null:
				skip.clear()
				await d.wait(1.0)
				continue
			var placed: bool = await _stand_at(m, float(k[1]), float(k[2]), bool(k[3]))
			if not placed or not is_instance_valid(m) or not m.is_alive():
				continue
			var target_iid := m.get_instance_id()
			if not _front_clear(_cands_now(), d.character().level, target_iid):
				# Another monster is in reach in front: this spot cannot tell a probe hit from a bystander hit. Try the
				# next Snail (or this one again once the others have moved on).
				skipped_bystander += 1
				skip[target_iid] = true
				await d.wait(0.5)
				continue
			var rec := await _tap_attack("probe_" + String(k[0]))
			if rec.is_empty():
				continue
			got += 1
			var g := _geom(d.player().global_position, d.player().facing, m.global_position) if is_instance_valid(m) else {}
			var outcome := _classify_probe(rec, target_iid)
			probes.append({"kind": k[0], "outcome": outcome, "hit": outcome == "target_hit", "mob": rec.get("mob", ""),
				"pres": rec.get("pres", ""), "nearest": rec.get("nearest", {}), "target_iid": target_iid,
				"hit_iid": int(rec.get("iid", 0)), "fwd_m": rec.get("fwd_m", snappedf(float(g.get("fwd_px", 0.0)) * WorldScale.actor(1.0), 0.001)),
				"target_fwd_m": snappedf(float(g.get("fwd_px", 0.0)) * WorldScale.actor(1.0), 0.001)})
			await d.wait(0.8)
	var counts := {}
	for p: Dictionary in probes:
		var key := "%s_%s" % [p["kind"], String(p.get("outcome", "whiff"))]
		counts[key] = int(counts.get(key, 0)) + 1
	d._end(i, true, "%s; %d spots skipped (another monster in reach in front)" % [counts, skipped_bystander])


## The Sword's standing presentations (every swing and stab the weapon's ordinary attack can draw).
func _standing_presentations() -> PackedStringArray:
	var w := WeaponProfile.for_weapon_id(WEAPON, db)
	var out := PackedStringArray()
	if w == null:
		return out
	for action: String in ["swing", "stab"]:
		out.append_array(w.presentations_for(action))
	return out


## Player-frame geometry of every live monster now: [{"iid", "mob", "fwd_px", "up_px", "lat_px"}].
func _cands_now() -> Array:
	var out: Array = []
	var p := d.player()
	for m: Monster in d.monsters().live_monsters():
		var g := _geom(p.global_position, p.facing, m.global_position)
		g["iid"] = m.get_instance_id()
		g["mob"] = m.def.id
		out.append(g)
	return out


## True when no candidate other than `exclude_iid` overlaps any of the Sword's standing presentations (the canonical
## oracle, _oracle_overlap): a tap from here can only hit the probe target or nothing. `cands` as _cands_now().
func _front_clear(cands: Array, level: int, exclude_iid: int) -> bool:
	var pres_list := _standing_presentations()
	for g: Dictionary in cands:
		if int(g.get("iid", 0)) == exclude_iid:
			continue
		for pres: String in pres_list:
			if _oracle_overlap(pres, level, g, String(g["mob"])):
				return false
	return true


## How a reach probe's attack ended: "target_hit" (the probe Snail itself was hit), "bystander_hit" (another monster
## was) or "whiff" (nothing). `rec` is the attack record (_on_attack_resolved: "mob" and "iid" on a hit).
static func _classify_probe(rec: Dictionary, target_iid: int) -> String:
	if not rec.has("mob"):
		return "whiff"
	return "target_hit" if int(rec.get("iid", 0)) == target_iid else "bystander_hit"


func _latency_probe() -> void:
	var i := d._begin(PlaytestReport.KIND_PLAY, "latency_probe", "J press to attack tick; J held 3 s")
	var lat0 := _latency.size()
	var n := 0
	var tries := 0
	while n < (3 if quick else 8) and tries < 30:
		tries += 1
		await _heal_if_low()
		var m := d.nearest_monster({"mob_id": "2", "max_dist_m": 40.0}) as Monster
		if m == null:
			await d.wait(1.0)
			continue
		var reach := d.attack_reach(m)
		var placed: bool = await _stand_at(m, 0.2, float(reach["ideal_m"]), true)
		if not placed:
			continue
		var rec := await _tap_attack("latency")
		if not rec.is_empty():
			n += 1
		if windowed and n == 1 and rec.has("mob"):
			await d.screenshot("swing_and_number_snail")
		await d.wait(0.2)
	var lat: Array = _latency.slice(lat0)
	# held key: the attack repeats at the lockout
	var m2 := d.nearest_monster({"mob_id": "2", "max_dist_m": 40.0}) as Monster
	if m2 != null:
		await _stand_at(m2, 0.2, float(d.attack_reach(m2)["ideal_m"]), true)
	var f0 := _hold_frames.size()
	_probe_tag = "hold"
	await d.input.hold_action(&"attack", 3.0)
	_probe_tag = ""
	var frames: Array = _hold_frames.slice(f0)
	var gaps: Array = []
	for j in range(1, frames.size()):
		gaps.append(int(frames[j]) - int(frames[j - 1]))
	var tier := -1
	for row: Dictionary in (db.formula("beginner").get("starter_weapons", {}) as Dictionary).get("items", []):
		if String(row.get("item_id", "")) == WEAPON:
			tier = int(row.get("attack_speed_tier", -1))
	var canon_ms := 0
	for row: Dictionary in db.formula("attack_speed").get("speed_tiers", []):
		if int(row.get("tier", -1)) == tier:
			canon_ms = int(row.get("ordinary_attack_ms", 0))
	peace["latency_ticks"] = lat
	peace["hold_gaps_ticks"] = gaps
	peace["canon_attack_ms_tier4"] = canon_ms
	d._end(i, not lat.is_empty(), "latency ticks %s; held repeat gaps %s (tier %s canonical %d ms)" % [lat, gaps, tier, canon_ms])
	d.check("responsiveness: a J press attacks on the next physics tick", not lat.is_empty() and lat.max() <= 1,
		"press-to-attack ticks %s (1 tick = 16.7 ms)" % [lat])
	var expect_ticks := ceili(canon_ms / 1000.0 * 60.0 - 1e-6)
	var gaps_ok := not gaps.is_empty()
	for g: int in gaps:
		gaps_ok = gaps_ok and absi(g - expect_ticks) <= 1
	d.check("held J repeats at the canonical tier-%d cycle (%d ms = %d ticks at 60 Hz)" % [tier, canon_ms, expect_ticks], gaps_ok,
		"gaps between attacks %s ticks = %s ms" % [gaps, gaps.map(func(g: int) -> int: return roundi(g * 1000.0 / 60.0))])


func _peace_probe() -> void:
	var i := d._begin(PlaytestReport.KIND_PLAY, "peace_probe", "walk into an unprovoked Tutorial Jr. Sentinel for 4 s, then provoke it and stand still")
	var p := d.player()
	var m := d.nearest_monster({"mob_id": "1", "max_dist_m": 80.0}) as Monster
	if m == null:
		d._end(i, false, "no Sentinel")
		d.check("Peace rule probe found a Tutorial Jr. Sentinel", false)
		return
	await d.walk_to(m.global_position, {"within_m": 1.2, "max_s": 15.0, "retries": 1})
	var t_from_1 := func() -> int:
		var n := 0
		for t: Dictionary in touches:
			if String(t["mob"]) == "1":
				n += 1
		return n
	var touch0: int = t_from_1.call()
	var peace0 := int(monitor["peace_ticks"])
	var t0 := d.game_s()
	while d.game_s() - t0 < 4.0 and is_instance_valid(m) and m.is_alive():
		await d.get_tree().process_frame
		d.input.reassert()
		var to := m.global_position - p.global_position
		to.y = 0.0
		if to.length() > 0.12:
			d.input.set_move_world(to.normalized(), p.view_right, p.view_forward)
		else:
			d.input.release_movement()
	d.input.release_movement()
	var overlap_ticks := int(monitor["peace_ticks"]) - peace0
	var unprovoked_touches: int = t_from_1.call() - touch0
	peace["unprovoked_overlap_ticks"] = overlap_ticks
	peace["unprovoked_touches"] = unprovoked_touches
	d.check("Peace rule: walking into an unprovoked Tutorial Jr. Sentinel deals nothing", overlap_ticks >= 30 and unprovoked_touches == 0,
		"%d ticks overlapping its touch zone, %d touches" % [overlap_ticks, unprovoked_touches])
	# provoke: hit it once, then stand still while it chases
	var provoked := false
	var tries := 0
	while not provoked and tries < 8 and is_instance_valid(m) and m.is_alive():
		tries += 1
		var placed: bool = await _stand_at(m, 0.3, float(d.attack_reach(m)["ideal_m"]), true)
		if not placed:
			continue
		var rec := await _tap_attack("provoke")
		provoked = rec.has("mob") and String(rec["mob"]) == "1"
	var touch1: int = t_from_1.call()
	await d.wait(5.0)
	var provoked_touches: Array = []
	for t: Dictionary in touches:
		if String(t["mob"]) == "1":
			provoked_touches.append(t)
	provoked_touches = provoked_touches.slice(touch1)
	peace["provoked_touches"] = provoked_touches.map(func(t: Dictionary) -> int: return int(t["final"]))
	if windowed:
		await d.screenshot("sentinel_provoked")
	d._end(i, provoked, "unprovoked: %d overlap ticks, %d touches; provoked: %d touches %s" % [overlap_ticks,
		unprovoked_touches, provoked_touches.size(), peace["provoked_touches"]])
	var r1 := _oracle_touch("1", d.character().level, 0)
	var all_ok := not provoked_touches.is_empty()
	for t: Dictionary in provoked_touches:
		all_ok = all_ok and bool(t["landed"]) and int(t["final"]) >= r1.x and int(t["final"]) <= r1.y
	d.check("Peace rule: once hit, the Sentinel's touch deals its canonical touch damage", provoked and all_ok,
		"provoked %s, touches %s, canonical window %d-%d" % [provoked, peace["provoked_touches"], r1.x, r1.y])


## Windowed only: stand in an Orange Mushroom without attacking and capture the touch (violet number, knockback).
func _touch_shot() -> void:
	var m := d.nearest_monster({"mob_id": "9", "max_dist_m": 80.0}) as Monster
	if m == null:
		return
	await _heal_if_low()
	await d.walk_to(m.global_position, {"within_m": 1.5, "max_s": 15.0, "retries": 0})
	var n0 := touches.size()
	var t0 := d.game_s()
	var p := d.player()
	while touches.size() == n0 and d.game_s() - t0 < 6.0 and is_instance_valid(m) and m.is_alive():
		await d.get_tree().process_frame
		d.input.reassert()
		var to := m.global_position - p.global_position
		to.y = 0.0
		if to.length() > 0.1:
			d.input.set_move_world(to.normalized(), p.view_right, p.view_forward)
	d.input.release_movement()
	if touches.size() > n0:
		await d.frames(6)
		await d.screenshot("orange_mushroom_touch_knockback")


# =================================================================================================================
# Visual measurements
# =================================================================================================================

func _measure_visual(mob: String) -> void:
	var best: Monster = null
	var bd := INF
	var p := d.player()
	for m: Monster in d.monsters().live_monsters():
		if m.def.id != mob or m.visual == null or m.visual.model == null or m.brain.mode == MonsterBrain.Mode.STAGGER or m.airborne:
			continue
		var dd := m.global_position.distance_to(p.global_position)
		if dd < bd:
			bd = dd
			best = m
	if best == null:
		return
	# In the model's own frame (the Visual node turns toward the facing over time, so the facing at this instant may
	# not be where the model points): x = forward (its +Z), y = up, z = lateral (its X).
	var inv := best.visual.global_transform.affine_inverse()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for n: Node in best.visual.model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or not mi.is_visible_in_tree() or String(mi.name).contains("SeeThrough"):
			continue
		var ab := mi.get_aabb()
		for k in 8:
			var r := inv * (mi.global_transform * ab.get_endpoint(k))
			var c := Vector3(r.z, r.y, r.x)
			lo = lo.min(c)
			hi = hi.max(c)
	if lo.x == INF:
		return
	var tz: Array = db.monster(mob).get("touch_zone_px", [0, 0])
	var sp: Array = db.monster(mob).get("sprite_size_px", [0, 0])
	visual_fit[mob] = {"visual_fwd_m": snappedf(hi.x - lo.x, 0.001), "visual_lat_m": snappedf(hi.z - lo.z, 0.001),
		"visual_h_m": snappedf(hi.y - maxf(lo.y, 0.0), 0.001), "visual_base_m": snappedf(lo.y, 0.001),
		"touch_w_m": snappedf(WorldScale.actor(float(tz[0])), 0.001), "touch_h_m": snappedf(WorldScale.actor(float(tz[1])), 0.001),
		"sprite_px": sp, "touch_px": tz, "placeholder": best.visual.is_placeholder}


func _measure_screen(mob: String) -> void:
	var cam := d.get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := d.player()
	var best: Monster = null
	var bd := INF
	for m: Monster in d.monsters().live_monsters():
		if m.def.id != mob:
			continue
		var dd := m.global_position.distance_to(p.global_position)
		if dd < bd:
			bd = dd
			best = m
	if best == null:
		return
	var tz: Array = db.monster(mob).get("touch_zone_px", [0, 0])
	var hgt := WorldScale.actor(float(tz[1]))
	var a := cam.unproject_position(best.global_position)
	var b := cam.unproject_position(best.global_position + Vector3.UP * hgt)
	var pa := cam.unproject_position(p.global_position)
	var pb := cam.unproject_position(p.global_position + Vector3.UP * 1.5)
	screen_px[mob] = {"monster_h_px": snappedf(a.distance_to(b), 0.1), "player_h_px": snappedf(pa.distance_to(pb), 0.1),
		"viewport": [d.get_viewport().get_visible_rect().size.x, d.get_viewport().get_visible_rect().size.y],
		"distance_m": snappedf(bd, 0.01)}


# =================================================================================================================
# Evaluation
# =================================================================================================================

func _evaluate() -> void:
	var species := ["1", "2", "3", "4", "5", "9"]
	# --- hit detection -------------------------------------------------------------------------------------------
	var n_att := attacks.size()
	d.check("hit detection: every attack's target is the oracle's (nearest monster overlapping the canonical box)",
		n_att > 0 and target_mismatch.is_empty(),
		"%d attacks, %d hits, %d whiffs, %d mismatches %s" % [n_att, hits.size(), whiffs.size(), target_mismatch.size(),
			JSON.stringify(target_mismatch.slice(0, 3))])
	var reasons := {}
	for w: Dictionary in whiffs:
		var r := String((w.get("nearest", {}) as Dictionary).get("reason", "none"))
		reasons[r] = int(reasons.get(r, 0)) + 1
	var fwd_min := INF
	var fwd_max := -INF
	var lat_max := 0.0
	var behind_hits := 0
	for h: Dictionary in hits:
		fwd_min = minf(fwd_min, float(h.get("fwd_m", 0.0)))
		fwd_max = maxf(fwd_max, float(h.get("fwd_m", 0.0)))
		lat_max = maxf(lat_max, absf(float(h.get("lat_m", 0.0))))
		if float(h.get("fwd_m", 0.0)) < 0.0:
			behind_hits += 1
	d.note("hit geometry: target feet %.2f..%.2f m along the facing, |lateral| <= %.2f m; %d hits with the feet behind the player (swingO2 reaches 5 px behind); whiff reasons %s" % [
		fwd_min, fwd_max, lat_max, behind_hits, reasons])
	# Classified by the identity of what was hit: only a hit on the probe Snail itself counts; a bystander hit is
	# neither (check #22 above still verifies that every hit, bystanders included, is the oracle's target).
	var pk := {}
	for pr: Dictionary in probes:
		var key := "%s_%s" % [pr["kind"], String(pr.get("outcome", "whiff"))]
		pk[key] = int(pk.get(key, 0)) + 1
	d.check("reach probes: the probe Snail 0.75-1.4 m behind and the one 3.2-3.9 m in front are never hit",
		int(pk.get("behind_target_hit", 0)) == 0 and int(pk.get("far_target_hit", 0)) == 0 \
			and int(pk.get("behind_whiff", 0)) >= 1 and int(pk.get("far_whiff", 0)) >= 1,
		"%s" % [pk])
	# --- misses ---------------------------------------------------------------------------------------------------
	var miss_out := 0
	for h: Dictionary in hits:
		if bool(h.get("missed", false)):
			miss_out += 1
	var avoid := {}
	for s: String in species:
		avoid[s] = int(db.monster(s).get("avoidability", -1))
	d.check("misses: no player attack MISSes (canonical AVOID of every species is 0: EVA 0 always hits)", miss_out == 0,
		"%d MISS of %d landed-or-missed attacks; AVOID %s" % [miss_out, hits.size(), avoid])
	var miss_in := 0
	var min_chance := 1.0
	var exp_miss := 0.0
	for t: Dictionary in touches:
		if bool(t["missed"]):
			miss_in += 1
		min_chance = minf(min_chance, float(t["hit_chance"]))
		exp_miss += 1.0 - float(t["hit_chance"])
	d.check("misses: monster touches MISS as often as the canonical incoming hit chance predicts",
		not touches.is_empty() and float(miss_in) <= exp_miss + 3.0 * sqrt(exp_miss) + 1e-6,
		"%d MISS of %d touches; expected %.2f (lowest hit chance %.4f)" % [miss_in, touches.size(), exp_miss, min_chance])
	# --- damage ---------------------------------------------------------------------------------------------------
	var per := {}
	for s: String in species:
		per[s] = {"n": 0, "min": 99999, "max": 0, "crit": 0, "lo": 99999, "hi": 0}
	for h: Dictionary in hits:
		if bool(h.get("missed", false)) or not per.has(String(h["mob"])):
			continue
		var e: Dictionary = per[String(h["mob"])]
		e["n"] = int(e["n"]) + 1
		e["min"] = mini(int(e["min"]), int(h["final"]))
		e["max"] = maxi(int(e["max"]), int(h["final"]))
		e["lo"] = mini(int(e["lo"]), int(h["lo"]))
		e["hi"] = maxi(int(e["hi"]), int(h["hi"]))
		if bool(h["critical"]):
			e["crit"] = int(e["crit"]) + 1
	for s: String in species:
		var e: Dictionary = per[s]
		d.check("damage: %s, %d hits all inside the canonical per-hit window" % [_mob_name(s), int(e["n"])],
			int(e["n"]) >= hit_target and _range_fails_of(s) == 0,
			"observed %d-%d, windows (by level/action/crit) span %d-%d, %d criticals, %d outside" % [int(e["min"]),
				int(e["max"]), int(e["lo"]), int(e["hi"]), int(e["crit"]), _range_fails_of(s)])
	d.check("damage: the oracle from damage.json agrees with CombatFormula.damage_window", formula_disagree.is_empty(),
		JSON.stringify(formula_disagree.slice(0, 3)))
	var crit_n := 0
	var landed := 0
	for h: Dictionary in hits:
		if not bool(h.get("missed", false)):
			landed += 1
			if bool(h["critical"]):
				crit_n += 1
	var c_rate := float((dmg_f.get("critical", {}) as Dictionary).get("base_rate_c", 0.0))
	var sd := sqrt(c_rate * (1.0 - c_rate) / maxf(landed, 1))
	d.soft_check("criticals: rate near the canonical base %.0f%%" % (c_rate * 100.0),
		absf(float(crit_n) / maxf(landed, 1) - c_rate) <= 3.0 * sd,
		"%d of %d = %.1f%% (3 sigma = %.1f%%)" % [crit_n, landed, 100.0 * crit_n / maxf(landed, 1), 300.0 * sd])
	_evaluate_distribution()
	# --- damage taken ---------------------------------------------------------------------------------------------
	var tper := {}
	for t: Dictionary in touches:
		var key := String(t["mob"])
		if not tper.has(key):
			tper[key] = {"n": 0, "vals": {}, "win": {}}
		var e: Dictionary = tper[key]
		e["n"] = int(e["n"]) + 1
		(e["vals"] as Dictionary)[int(t["final"])] = int((e["vals"] as Dictionary).get(int(t["final"]), 0)) + 1
		(e["win"] as Dictionary)["%d-%d" % [int(t["lo"]), int(t["hi"])]] = true
	var cf_dis := 0
	for t: Dictionary in touches:
		if int(t["cf_lo"]) != int(t["lo"]) or int(t["cf_hi"]) != int(t["hi"]):
			cf_dis += 1
	var no_overlap := 0
	for t: Dictionary in touches:
		if not bool(t["overlap_oracle"]):
			no_overlap += 1
	d.check("damage taken: every landed touch inside the canonical touch window (accuracy.json, the player's level and WDEF)",
		not touches.is_empty() and touch_fail.is_empty() and cf_dis == 0,
		"%d touches, %d outside, %d CombatFormula disagreements; per species %s" % [touches.size(), touch_fail.size(), cf_dis,
			JSON.stringify(tper)])
	var few: Array = []
	for s: String in species:
		var need := 1 if s == "1" else (2 if quick else 3)
		if not tper.has(s) or int((tper[s] as Dictionary)["n"]) < need:
			few.append(s)
	d.check("damage taken: touch samples from every species (Sentinel only once provoked)", few.is_empty(),
		"species short of samples: %s" % [few])
	var est := {}
	for s: String in species:
		est[s] = db.monster(s).get("touch_damage_estimate_at_0_wdef", {})
	d.note("MeowDB touch estimates at 0 WDEF: %s" % [JSON.stringify(est)])
	d.check("contact: every touch happened with the canonical touch zone overlapping the player's body", no_overlap == 0,
		"%d of %d touches without overlap" % [no_overlap, touches.size()])
	# --- invulnerability ------------------------------------------------------------------------------------------
	var inv_s := float((acc_f.get("after_hit", {}) as Dictionary).get("post_hit_invincibility_s", 0.0))
	var inv_bad := 0
	for t: Dictionary in touches:
		if absf(float(t["invuln_left"]) - inv_s) > 0.001:
			inv_bad += 1
	var gap_min := INF
	for g: float in _touch_gaps:
		gap_min = minf(gap_min, g)
	d.check("post-hit invulnerability: %.1f s after every touch, next touch never sooner" % inv_s,
		inv_bad == 0 and (gap_min == INF or gap_min >= inv_s - 1.0 / 60.0 - 1e-4),
		"%d touches, %d with another timer; shortest gap between touches %.3f s; %d overlap ticks suppressed" % [
			touches.size(), inv_bad, gap_min, int(monitor["suppressed"])])
	d.check("contact is predictable: no tick where a touch-active monster overlapped a vulnerable idle player without touching",
		int(monitor["unexplained"]) == 0, "%d ticks %s; %d ticks where a monster realized since the last tick (a respawn) overlapped the player before its first step (it touches on that step)" % [
			int(monitor["unexplained"]), JSON.stringify(monitor["unexplained_samples"]), int(monitor.get("spawned_on_player", 0))])
	# --- knockback ------------------------------------------------------------------------------------------------
	var kb_up := float(move_f.get("knockback_airtime", {}).get("upward_speed_px_per_s", 0.0))
	var kb_g := float(move_f.get("knockback_airtime", {}).get("gravity_px_per_s2", 0.0))
	var air := 2.0 * kb_up / kb_g if kb_g > 0.0 else 0.0
	var rise := WorldScale.v(kb_up * kb_up / (2.0 * kb_g)) if kb_g > 0.0 else 0.0
	var hspeed := float(move_m.get("knockback_horizontal_speed_mps", 0.0))
	var clean_kb: Array = kb_player.filter(func(k: Dictionary) -> bool: return float(k["offset_m"]) >= 0.05 and float(k["dist_m"]) >= 0.9 * hspeed * float(k["airtime_s"]) and not bool(k["timeout"]))
	var degenerate: Array = kb_player.filter(func(k: Dictionary) -> bool: return float(k["offset_m"]) < 0.05)
	var obstructed: Array = kb_player.filter(func(k: Dictionary) -> bool: return float(k["offset_m"]) >= 0.05 and (float(k["dist_m"]) < 0.9 * hspeed * float(k["airtime_s"]) or bool(k["timeout"])))
	var flat_kb: Array = clean_kb.filter(func(k: Dictionary) -> bool: return absf(float(k["dy_m"])) < 0.05)
	var away_ok := 0
	for k: Dictionary in clean_kb:
		if float(k["cos_away"]) >= 0.9:
			away_ok += 1
	var airs: Array = flat_kb.map(func(k: Dictionary) -> float: return float(k["airtime_s"]))
	var rises: Array = flat_kb.map(func(k: Dictionary) -> float: return float(k["rise_m"]))
	var dists: Array = flat_kb.map(func(k: Dictionary) -> float: return float(k["dist_m"]))
	d.check("player knockback: every landed touch knocks the player back, straight away from the monster when nothing blocks it",
		not clean_kb.is_empty() and away_ok == clean_kb.size() and kb_player.size() + kb_interrupted == _landed_touches(),
		"%d landed touches, %d knockbacks tracked (%d interrupted by a warp); %d unobstructed, %d of them within 26 deg of straight away; %d obstructed (wall or slope: %s); %d with the monster within 5 cm of the player's feet (direction from a sub-5 cm offset: %s)" % [
			_landed_touches(), kb_player.size(), kb_interrupted, clean_kb.size(), away_ok, obstructed.size(),
			JSON.stringify(obstructed.slice(0, 3)), degenerate.size(), JSON.stringify(degenerate.slice(0, 3))])
	d.soft_check("player knockback arc on level ground matches the canonical model (%.3f s airtime, %.3f m rise) and %.1f m/s push" % [air, rise, hspeed],
		not flat_kb.is_empty() and absf(_median(airs) - air) <= 0.05 and absf(_median(rises) - rise) <= 0.05,
		"%d level-ground knockbacks: airtime median %.3f s (range %.3f-%.3f), rise median %.3f m, distance median %.3f m (expected ~%.2f m)" % [
			flat_kb.size(), _median(airs), _amin(airs), _amax(airs), _median(rises), _median(dists), hspeed * air])
	var kb_px := float((combat_m.get("monster_knockback", {}) as Dictionary).get("knockback_distance_px", 0.0))
	var push_m := WorldScale.h(kb_px)
	var st_bad := 0
	var air_hits := 0
	var air_bad: Array = []
	var free_push: Array = []
	var cut := 0
	for k: Dictionary in kb_monster:
		if bool(k["airborne"]):
			air_hits += 1
			# combat.json monster_knockback.airborne_hit: the hop is cancelled and the push runs; it never carries on
			# toward the attacker (Iteration Two: +0.54 / -1.38 / -1.01 m) nor past the push distance.
			if not bool(k["staggered"]) or float(k["push_m"]) < -0.05 or float(k["push_m"]) > push_m + 0.05:
				air_bad.append(k)
			continue
		if not bool(k["staggered"]) or absf(float(k["stagger_s"]) - float(k["expected_s"])) > 2.0 / 60.0 + 1e-4:
			st_bad += 1
		if String(k["blocked_at_hit"]) == "" and not bool(k["cut_short"]):
			free_push.append(float(k["push_m"]))
		else:
			cut += 1
	var stagger_hits := 0
	for h: Dictionary in hits:
		if not bool(h.get("missed", false)):
			stagger_hits += 1 if bool(h["kb"]) else 0
	d.check("monster knockback: KB 1, so every landed hit on a grounded monster staggers it for its canonical stagger time (the record's STAGGER, else its hit1 clip)",
		not kb_monster.is_empty() and st_bad == 0 and stagger_hits == landed,
		"%d of %d landed hits flagged knockback; %d stagger tracks on grounded monsters, %d off the canonical stagger time; durations %s" % [stagger_hits,
			landed, kb_monster.size() - air_hits, st_bad, _uniq(kb_monster.filter(func(k: Dictionary) -> bool: return not bool(k["airborne"])).map(
				func(k: Dictionary) -> String: return "%s:%.3f" % [k["mob"], float(k["stagger_s"])]))])
	d.check("monster knockback: a hit in mid-hop cancels the hop, staggers it and pushes it away from the attacker, never toward it",
		air_bad.is_empty(), "%d of %d knockback hits landed on an airborne monster; %d moved toward the attacker or past %.2f m: %s" % [
			air_hits, kb_monster.size(), air_bad.size(), push_m, JSON.stringify(air_bad.slice(0, 4))])
	d.soft_check("monster knockback: an unblocked push carries it %.2f m (20 px x WorldScale.h) away from the attacker" % push_m,
		not free_push.is_empty() and absf(_median(free_push) - push_m) <= 0.02,
		"%d unblocked pushes: median %.3f m, range %.3f-%.3f m; %d pushes stopped by a ledge, wall or region edge" % [
			free_push.size(), _median(free_push), _amin(free_push), _amax(free_push), cut])
	# --- death, EXP, drops ----------------------------------------------------------------------------------------
	var still_live := 0
	for k: Dictionary in kills:
		if bool(k["alive"]) or bool(k["targetable"]) or int(k["hp"]) != 0:
			still_live += 1
	var fade_bad := 0
	for f: Dictionary in fades:
		if absf(float(f["fade_s"]) - float(f["expected_s"])) > 4.0 / 60.0 + 1e-4:
			fade_bad += 1
	d.check("monster death: HP 0, untargetable at once, body fades over the canonical die time", kills.size() > 0
		and still_live == 0 and fade_bad == 0 and stat_bad.filter(func(s: String) -> bool: return s.contains("fading")).is_empty(),
		"%d kills, %d still live, %d fades measured (%d off), fade times %s" % [kills.size(), still_live, fades.size(), fade_bad,
			_uniq(fades.map(func(f: Dictionary) -> String: return "%s:%.2f/%.2f" % [f["mob"], float(f["fade_s"]), float(f["expected_s"])]))])
	var kill_counts := {}
	for k: Dictionary in kills:
		kill_counts[k["mob"]] = int(kill_counts.get(k["mob"], 0)) + 1
	var exp_per := {}
	for e: Dictionary in exp_events:
		exp_per[e["mob"]] = "%d x %d" % [int(exp_per.get(e["mob"], "0 x 0").split(" x ")[0]) + 1, int(e["amount"])]
	d.check("EXP: every kill awarded exactly its species' canonical EXP", exp_events.size() == kills.size() and exp_bad.is_empty(),
		"%d kills %s, %d EXP events %s, %d wrong" % [kills.size(), kill_counts, exp_events.size(), exp_per, exp_bad.size()])
	var drop_items := 0
	var with_drop := 0
	for l: Dictionary in loot_events:
		drop_items += (l["drops"] as Array).size()
		with_drop += 1
	d.check("drops: every dropped item is in the killed species' canonical drop table, every drop appears on the ground",
		with_drop > 0 and loot_bad.is_empty() and ground_nodes.size() == drop_items,
		"%d of %d kills dropped %d things, %d ground nodes, %d outside the table %s" % [with_drop, kills.size(), drop_items,
			ground_nodes.size(), loot_bad.size(), JSON.stringify(loot_bad.slice(0, 3))])
	var by_species := {}
	for l: Dictionary in loot_events:
		var s := String(l["mob"])
		if not by_species.has(s):
			by_species[s] = {}
		for dr: Dictionary in l["drops"]:
			var key := "mesos" if String(dr.get("kind", "")) == "mesos" else String(dr.get("item_id", ""))
			(by_species[s] as Dictionary)[key] = int((by_species[s] as Dictionary).get(key, 0)) + 1
	d.note("drops by species (item id -> times): %s" % [JSON.stringify(by_species)])
	# --- respawn --------------------------------------------------------------------------------------------------
	var tick_s := float(spawn_f.get("global_respawn_tick_s", 0.0))
	var cool_s := float(spawn_f.get("wave_point_cooldown_s", 0.0))
	var off_tick := 0
	var not_eligible := 0
	var held := 0
	var delays: Array = []
	var same_slot: Array = []
	for r: Dictionary in spawn_refills:
		if bool(r.get("waited_for_player", false)):
			held += 1
		else:
			delays.append(float(r["delay"]))
			if float(r["delay"]) < -1e-3 or float(r["delay"]) > 0.1:
				off_tick += 1
		if not bool(r["eligible"]):
			not_eligible += 1
		if bool(r["killed_this_visit"]):
			same_slot.append(float(r["same_slot_since_death"]))
	d.check("respawn: every refill appears on a %.2f s global tick, only from a slot whose death + %.0f s cooldown has passed" % [
		tick_s, cool_s], spawn_refills.size() >= 3 and off_tick == 0 and not_eligible == 0,
		"%d refills while in the map, %d off a tick boundary (delay after the boundary %.4f..%.4f s), %d from a slot not yet eligible; %d refilled a slot killed on this visit, %.2f..%.2f s after its death; %d held back until the player left the slot (respawn clearance)" % [
			spawn_refills.size(), off_tick, _amin(delays), _amax(delays), not_eligible, same_slot.size(), _amin(same_slot), _amax(same_slot), held])
	var caps := {}
	for c: Dictionary in capacity_checks:
		caps[c["map"]] = "%d/%d (canonical %d)" % [int(c["capacity"]), (db.map(String(c["map"])).get("spawns", []) as Array).size(), int(c["canonical_capacity"])]
	d.check("respawn: after every tick boundary the map is back at its canonical solo capacity (75% of spawn points) whenever an eligible slot is dead",
		capacity_checks.size() >= 10 and capacity_bad.is_empty(),
		"%d boundaries checked, %d short; capacity/points %s; %s" % [capacity_checks.size(), capacity_bad.size(), caps,
			JSON.stringify(capacity_bad.slice(0, 3))])
	d.soft_check("every targeted monster could be reached on foot and attacked", unreachable.is_empty(),
		"%d monsters skipped after two 4 s approaches without an attack: %s" % [unreachable.size(), JSON.stringify(unreachable.slice(0, 6))])
	d.check("no stat bookkeeping anomalies", stat_bad.is_empty(), JSON.stringify(stat_bad.slice(0, 5)))
	d.note("player deaths: %d (recovered during the fights), dead at the end: %s, console heals: %d; interrupted knockback tracks: %s" % [deaths_of_player,
		d.game().is_character_dead(), heals, JSON.stringify(kb_interrupts)])
	d.note("visual fit (model extents vs canonical touch zone, m): %s" % [JSON.stringify(visual_fit)])
	# The body you see is the body you hit: every species shows its proxy (the Tutorial Jr. Sentinel's too), stands on
	# its feet (a bouncing walker's bob is up to 6% of its height) and spans about its touch zone (1.35x allows the
	# crawl's squash and stretch and the ink outline).
	var fit_bad: Array = []
	for mob: String in visual_fit:
		var v: Dictionary = visual_fit[mob]
		var w := float(v["touch_w_m"])
		if bool(v["placeholder"]) or float(v["visual_fwd_m"]) > w * 1.35 or float(v["visual_lat_m"]) > w * 1.35 \
				or float(v["visual_base_m"]) > float(v["visual_h_m"]) * 0.06 + 0.03 or float(v["visual_base_m"]) < -0.05:
			fit_bad.append(mob)
	d.check("monster visuals: every species shows its proxy on its feet, within about its canonical touch zone",
		visual_fit.size() == species.size() and fit_bad.is_empty(), "%d species measured; off: %s" % [visual_fit.size(), fit_bad])
	if not screen_px.is_empty():
		d.note("on-screen heights at 1600x900 (px): %s" % [JSON.stringify(screen_px)])
	d.note("latency/peace: %s" % [JSON.stringify(peace)])


func _evaluate_distribution() -> void:
	# Contexts: (mob, action, level) for non-critical hits.
	var ctx := {}
	for h: Dictionary in hits:
		if bool(h.get("missed", false)) or bool(h.get("critical", false)):
			continue
		var key := "%s|%s|%d" % [h["mob"], h["action"], int(h["level"])]
		if not ctx.has(key):
			ctx[key] = []
		(ctx[key] as Array).append(int(h["final"]))
	var c := d.character()
	var base := c.base_stats.duplicate()
	var bon: Dictionary = c.equipment.total_bonuses(db)
	var obs := 0.0
	var exp_two := 0.0
	var var_two := 0.0
	var exp_one := 0.0
	var var_one := 0.0
	var n := 0
	var bins := [0, 0, 0, 0, 0]
	var pit_bins := [0.0, 0.0, 0.0, 0.0, 0.0]
	var uni_bins := [0.0, 0.0, 0.0, 0.0, 0.0]
	for key: String in ctx:
		var parts := key.split("|")
		var k := _raw_ctx(parts[0], parts[1], int(parts[2]), base, bon)
		var lo := _finalize(_raw(k, 0.0, 0.0) * float(k["post"]))
		var hi := _finalize(_raw(k, 1.0, 1.0) * float(k["post"]))
		var mid := (lo + hi) / 2.0
		var half := maxf((hi - lo) / 2.0, 0.5)
		var s2 := 0.0
		var s4 := 0.0
		var u2 := 0.0
		var u4 := 0.0
		var hist2 := {}
		var hist1 := {}
		for _i in MC_SAMPLES:
			var v2 := _finalize(_raw(k, mc_rng.randf(), mc_rng.randf()) * float(k["post"]))
			var z2 := (v2 - mid) / half
			s2 += z2 * z2
			s4 += z2 * z2 * z2 * z2
			hist2[v2] = int(hist2.get(v2, 0)) + 1
			var u := mc_rng.randf()
			var v1 := _finalize(_raw(k, u, u) * float(k["post"]))
			var z1 := (v1 - mid) / half
			u2 += z1 * z1
			u4 += z1 * z1 * z1 * z1
			hist1[v1] = int(hist1.get(v1, 0)) + 1
		var m2 := s2 / MC_SAMPLES
		var m1 := u2 / MC_SAMPLES
		for v: int in ctx[key]:
			var z := (v - mid) / half
			obs += z * z
			exp_two += m2
			var_two += s4 / MC_SAMPLES - m2 * m2
			exp_one += m1
			var_one += u4 / MC_SAMPLES - m1 * m1
			n += 1
			var b := clampi(int(floor((v - lo) / maxf(hi - lo + 1, 1) * 5.0)), 0, 4)
			bins[b] += 1
		# expected bin shares for this context's hit count
		for v: int in hist2:
			var b2 := clampi(int(floor((v - lo) / maxf(hi - lo + 1, 1) * 5.0)), 0, 4)
			pit_bins[b2] += float(hist2[v]) / MC_SAMPLES * (ctx[key] as Array).size()
		for v: int in hist1:
			var b1 := clampi(int(floor((v - lo) / maxf(hi - lo + 1, 1) * 5.0)), 0, 4)
			uni_bins[b1] += float(hist1[v]) / MC_SAMPLES * (ctx[key] as Array).size()
	if n == 0:
		d.check("damage distribution measured", false, "no non-critical hits")
		return
	var se := sqrt(var_two) / n
	var se1 := sqrt(var_one) / n
	var o := obs / n
	var e2 := exp_two / n
	var e1 := exp_one / n
	d.check("damage distribution: centre-heavy as two independent draws (mean squared normalised offset vs Monte Carlo)",
		absf(o - e2) <= 3.0 * se and (e1 - o) >= 3.0 * se1,
		"%d non-critical hits: observed %.4f, two-draw model %.4f +- %.4f, single-draw (uniform) model %.4f +- %.4f (%.1f sigma away); quintiles observed %s, two-draw expected %s, uniform expected %s" % [
			n, o, e2, se, e1, se1, (e1 - o) / maxf(se1, 1e-9), bins, pit_bins.map(func(x: float) -> float: return snappedf(x, 0.1)),
			uni_bins.map(func(x: float) -> float: return snappedf(x, 0.1))])


func _range_fails_of(mob: String) -> int:
	var n := 0
	for r: Dictionary in range_fail:
		if String(r.get("mob", "")) == mob:
			n += 1
	return n


func _write_samples() -> void:
	var out := {"hits": hits, "whiffs": whiffs, "target_mismatch": target_mismatch, "range_fail": range_fail,
		"formula_disagree": formula_disagree, "touches": touches, "touch_fail": touch_fail, "touch_gaps": _touch_gaps,
		"kills": kills, "exp": exp_events, "loot": loot_events.map(func(l: Dictionary) -> Dictionary:
			return {"mob": l["mob"], "map": l["map"], "drops": l["drops"]}),
		"ground_nodes": ground_nodes.size(), "refills": spawn_refills, "capacity_checks": capacity_checks, "capacity_bad": capacity_bad, "kb_interrupted": kb_interrupted, "kb_interrupts": kb_interrupts, "unreachable": unreachable, "kb_player": kb_player, "kb_monster": kb_monster,
		"fades": fades, "monitor": monitor, "probes": probes, "visual_fit": visual_fit, "screen_px": screen_px,
		"peace": peace, "latency_ticks": _latency, "stat_bad": stat_bad}
	var f := FileAccess.open(d.out_dir.path_join("combat_samples.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, " ", false))
		f.close()


static func _median(a: Array) -> float:
	if a.is_empty():
		return NAN
	var s := a.duplicate()
	s.sort()
	var n := s.size()
	return float(s[n / 2]) if n % 2 == 1 else (float(s[n / 2 - 1]) + float(s[n / 2])) / 2.0


static func _amin(a: Array) -> float:
	var m := INF
	for v: Variant in a:
		m = minf(m, float(v))
	return m


static func _amax(a: Array) -> float:
	var m := -INF
	for v: Variant in a:
		m = maxf(m, float(v))
	return m


static func _uniq(a: Array) -> Dictionary:
	var out := {}
	for v: Variant in a:
		out[str(v)] = int(out.get(str(v), 0)) + 1
	return out


func _landed_touches() -> int:
	var n := 0
	for t: Dictionary in touches:
		if bool(t["landed"]) and int(t["final"]) > 0:
			n += 1
	return n
