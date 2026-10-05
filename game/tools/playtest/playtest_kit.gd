class_name PlaytestKit
extends RefCounted
## Composite play helpers shared by the scenarios (docs/runtime/PLAYTEST_HARNESS.md "PlaytestKit"). Everything here
## plays through PlaytestDriver's real input (keys, mouse, the walker) and reads the live game; nothing writes game
## state, so a kit call is legal in strict mode. The one exception is the opt-in console warp of travel_to(), which
## only a non-strict scenario can ask for (and it is a logged "console" step).
##
##   var k := PlaytestKit.new(d)
##   k.connect_bus()                                    # EXP, quest, damage and death bookkeeping
##   await k.travel_to("000000050")                     # map by map over the canonical portals, walking the trails
##   var t := await k.talk("11")                        # talk_to, retried after a death on the way
##   await k.converse({"1009": "accept"})               # menus, Yes/No, pages; quizzes by the canonical answer
##   await k.hunt(["3", "4"], func() -> bool: ..., {}) # fights with the survival policy, picks up precisely
##
##   travel    travel_to(map, opts)  portal_path(db, from, to)  walk_safely(target, opts)
##   NPCs      approach(npc)  talk(npc)  converse(goals, opts)  marker(npc)  quest_window(qid, tab)  open_shop(npc)
##   quiz      quiz_answer(db, qid)  (static: the canonical correct choice and the paired wrong-answer lines)
##   items     use_item(id, via)  equip(id)  drink(id)  bind_quickslot(id, key)  double_click(c)  drag(a, b)
##   AP        stats_window()  click_plus(stat)  allocate_ap(plan)
##   shop      open_shop(npc)  buy(id, qty)  sell(id, qty)  close_shop()
##   combat    hunt(mob_ids, cond, opts)  survive(opts)  threat(opts)  pickup(radius, max_s)
##   death     is_dead()  respawn(opts)
##   contracts activity()  sit()  stand()  use_chair(id)  cast_skill(id)  breakables()  break_box(box, opts)
##   skills    learn_skill(id)  bind_skill(id, key)  throw_at(target, opts)  (the Skills window, K; Three Snails)
##   record    snapshot()  bag_delta(a, b, skip)  total_exp()  checkpoint(tag)  log_clock()  log_since(t)
##             track()  carry_totals()  play_s()  local_pos()   (the progression audit, kept in d.carry)
##   death     let_monsters_win(mob_ids, opts)  (stand among monsters without fighting until the player dies)
##
## The contract helpers (sit, chairs, skills, Wooden Boxes) are written against docs/runtime/
## ITERATION_THREE_CONTRACTS.md C4/C5/C3/C8. Those features are all built (wave 1); on a build without one, its
## helper still answers {"ok": false, "why": "... is not built"} instead of failing.

## Horizontal distance (m) inside which a live monster counts as a threat to a walk (it is about to touch).
const THREAT_M := 2.2
## Height difference (m) beyond which a monster is on another tier and no threat.
const THREAT_DY_M := 1.2
## A walk that is interrupted more often than this gives up (a monster pinned on the path, a death spiral).
const MAX_INTERRUPTS := 12
## How long (game s) a touch keeps its monster a threat to a walk.
const TOUCH_MEMORY_S := 1.5
## A monster more than this many levels above the player is not fought back on a walk or a rest (it is walked away
## from); a hunt's wanted species is fought whatever its level.
const FIGHT_LEVEL_GAP := 3
## Below this share of Max HP a walk never stops to fight back: the player walks on, and below HP_FLOOR it heals or
## rests instead.
const FIGHT_BACK_HP := 0.55
## Default survival policy: drink or rest below this share of Max HP, and rest until this share.
const HP_FLOOR := 0.4
const HP_RESUME := 0.8
## Rest budget (game s) of one survive() call.
const REST_MAX_S := 150.0
## How far (m) from every live monster a resting spot should be, and the longest walk (m) to one.
const REST_CLEAR_M := 9.0
const REST_WALK_MAX_M := 25.0
## How many times one rest walks away from a monster that comes close before it fights back instead.
const REST_MOVES := 4
## unstick(): a walk that ends closer than UNSTICK_STALLED_M (m) to where it began "stalled where it began"; each push
## lasts at most UNSTICK_PUSH_S (game s) and succeeds once the feet stand UNSTICK_M (m) from the start.
const UNSTICK_STALLED_M := 1.0
const UNSTICK_PUSH_S := 1.5
const UNSTICK_M := 2.5
## A monster a fight back could not reach without a chase (on a ledge just above or below) stops counting as a threat
## for this long (game s): otherwise a walk it touched is interrupted again at once, and the fight back fails again,
## faster than the touch is forgotten (seed 2 of the every-quest set spun 24 times in 2 s on Snail Hunting Ground I).
const SHUN_S := 4.0
## Three Snails: where to stand from the target for a throw, well inside the canonical 50-300 px band (px, actor
## scale), as test_skills does.
const THROW_FROM_PX := 150.0
## break_box (test_box's approach): stand at this share of the weapon's reach, on approach spots in this many
## directions within this height (m) of the box's feet; attack only within BOX_ATTACK_DY_M (m) of its height; try at
## most BOX_SPOTS spots; stand closer after BOX_WHIFF_RUN whiffs in a row.
const BOX_REACH_SHARE := 0.6
const BOX_APPROACH_DIRS := 8
const BOX_APPROACH_DY_M := 0.3
const BOX_ATTACK_DY_M := 0.8
const BOX_SPOTS := 6
const BOX_WHIFF_RUN := 3
## The planners break_box walks to its approach spots with, in turn (the routes first: they lead down a terrace the
## grid would walk along the top of), and how many boxes break_box(null) tries before giving up.
const BOX_PLANNERS := ["routes", "auto", "grid"]
const BOX_CANDIDATES := 3

var d: PlaytestDriver = null
var db: ContentDB = null

# --- what the kit heard on the bus (connect_bus) ----------------------------------------------------------------
## [amount, source, game_s] for every Events.exp_gained.
var exp_log: Array = []
## [quest_id, kind, game_s] for quest_started / quest_progressed / quest_completed.
var quest_events: Array = []
var damage_taken: int = 0
## "mob:damage@map" for every player_damaged.
var touches: PackedStringArray = []
## The game second of the last touch (a monster damaged the player), and the monster.
var last_touch_s: float = -100.0
var last_touch_mob: String = ""

# --- what the kit did -----------------------------------------------------------------------------------------
## {map, level, play_s, notice, ok_clicked, respawned, respawn_map, hp_after} per death respawn() handled.
var deaths: Array = []
## {from, to, ok, how, via, time_s, issues} per trail hop of travel_to.
var travel_rows: Array = []
## Hops that ended in a console warp (non-strict scenarios only).
var fallbacks: PackedStringArray = []
## Survival policy counters: potions drunk, rests, rest seconds, fights back, interrupts of a walk.
var survival := {"drinks": 0, "rests": 0, "rest_s": 0.0, "fights_back": 0, "interrupts": 0, "unsticks": 0}
## The HUD log lines on screen the moment a converse() goal quest completed.
var on_screen_at_complete: PackedStringArray = []
var shots: int = 0
## Mesos and items picked up from the ground with Z this process (pickup()): the meso bags are monster drops (the
## Wooden Box drops no mesos, drops/0000001.json).
var picked_mesos: int = 0
var picked_bags: int = 0
var picked_items: int = 0
## Monster instance id -> game second until which threat() skips it (SHUN_S).
var _shunned := {}
var _connected := false
var _tracking := false


func _init(p_d: PlaytestDriver) -> void:
	d = p_d
	db = d.db()
	# The survival policy needs the touches from the start (a kit made after boot always has the bus).
	if d.events() != null:
		connect_bus()


# =================================================================================================================
# Bus bookkeeping
# =================================================================================================================

## Listens to the bus (EXP, quests, damage). Idempotent; the Events autoload outlives a new game, so once is enough.
func connect_bus() -> void:
	if _connected:
		return
	_connected = true
	var ev := d.events()
	ev.connect(&"exp_gained", func(amount: int, source: String) -> void: exp_log.append([amount, source, d.game_s()]))
	ev.connect(&"quest_started", func(qid: String) -> void: quest_events.append([qid, "started", d.game_s()]))
	ev.connect(&"quest_progressed", func(qid: String) -> void: quest_events.append([qid, "progressed", d.game_s()]))
	ev.connect(&"quest_completed", func(qid: String) -> void: quest_events.append([qid, "completed", d.game_s()]))
	ev.connect(&"player_damaged", func(amount: int, mob: String) -> void:
		damage_taken += amount
		last_touch_s = d.game_s()
		last_touch_mob = mob
		touches.append("%s:%d@%s" % [mob, amount, d.current_map().right(4)]))


## [amount, source] of every EXP award heard at or after game second t0.
func exp_since(t0: float) -> Array:
	var out: Array = []
	for e: Array in exp_log:
		if float(e[2]) >= t0:
			out.append([e[0], e[1]])
	return out


# =================================================================================================================
# The progression audit: what the whole run did, kept in d.carry (survives reload_process)
# =================================================================================================================

## Records the run's progression into d.carry as it happens (a long scenario's audit; idempotent): "visited_maps"
## {map: play_s at first arrival}, "kills_by_mob" {mob: n}, "exp_by_source" {"monster:<id>" | "quest:<id>" | "death":
## sum}, "level_at" {level: play_s}, "deaths" [{map, play_s}], "respawns" [{map, play_s}], "mesos_flow" {in, out},
## "items_gained" {item: n}, "items_lost" {item: n}, "items_used" {item: n}, "skills_used" {skill: n}, "sat" {chair: n},
## "talked_to" {npc: conversations opened}.
## The current map counts as visited. Call it after every new_game / continue_game.
func track() -> void:
	_visit(d.current_map(), "")
	if _tracking:
		return
	_tracking = true
	var ev := d.events()
	ev.connect(&"map_entered", func(map_id: String, _prev: String) -> void: _visit(map_id, _prev))
	ev.connect(&"monster_killed", func(mob: String, _map: String) -> void: _bump("kills_by_mob", mob, 1))
	ev.connect(&"exp_gained", func(amount: int, source: String) -> void: _bump("exp_by_source", source if source != "" else "(none)", amount))
	ev.connect(&"leveled_up", func(lv: int) -> void:
		var at: Dictionary = d.carry.get("level_at", {})
		at[str(lv)] = snappedf(play_s(), 0.1)
		d.carry["level_at"] = at)
	ev.connect(&"player_died", func(map_id: String) -> void: _append("deaths", {"map": map_id, "play_s": snappedf(play_s(), 0.1),
		"level": d.character().level, "pos": local_pos()}))
	ev.connect(&"player_respawned", func(map_id: String) -> void: _append("respawns", {"map": map_id, "play_s": snappedf(play_s(), 0.1)}))
	ev.connect(&"mesos_changed", func(_m: int, delta: int) -> void: _bump("mesos_flow", "in" if delta > 0 else "out", absi(delta)))
	ev.connect(&"item_gained", func(id: String, n: int) -> void: _bump("items_gained", id, n))
	ev.connect(&"item_lost", func(id: String, n: int) -> void: _bump("items_lost", id, n))
	ev.connect(&"item_used", func(id: String) -> void: _bump("items_used", id, 1))
	ev.connect(&"skill_used", func(id: String, _lv: int) -> void: _bump("skills_used", id, 1))
	ev.connect(&"player_sat_down", func(id: String) -> void: _bump("sat", id if id != "" else "(ground)", 1))
	ev.connect(&"dialogue_opened", func(npc: String) -> void: _bump("talked_to", npc, 1))


func _visit(map_id: String, _prev: String) -> void:
	if map_id == "":
		return
	var v: Dictionary = d.carry.get("visited_maps", {})
	if not v.has(map_id):
		v[map_id] = snappedf(play_s(), 0.1)
	d.carry["visited_maps"] = v


func _bump(key: String, sub: String, n: int) -> void:
	var m: Dictionary = d.carry.get(key, {})
	m[sub] = int(m.get(sub, 0)) + n
	d.carry[key] = m


func _append(key: String, row: Dictionary) -> void:
	var a: Array = d.carry.get(key, [])
	a.append(row)
	d.carry[key] = a


## Adds this process's pickup and survival counters into d.carry["totals"] (call before reload_process; the counters
## start again at 0 in the next process). Idempotent within a process.
func carry_totals() -> void:
	var t: Dictionary = d.carry.get("totals", {})
	var mine := {"picked_mesos": picked_mesos, "picked_bags": picked_bags, "picked_items": picked_items,
		"damage_taken": damage_taken, "touches": touches.size(), "kit_deaths": deaths.size(),
		"drinks": int(survival["drinks"]), "rests": int(survival["rests"]), "rest_s": float(survival["rest_s"]),
		"fights_back": int(survival["fights_back"]), "unsticks": int(survival.get("unsticks", 0)),
		"travel_hops": travel_rows.size(), "travel_failed": travel_rows.filter(func(r: Dictionary) -> bool: return not bool(r["ok"])).size()}
	var per: Dictionary = t.get("per_phase", {})
	per[str(d.phase)] = mine
	t["per_phase"] = per
	var sum := {}
	for ph: Variant in per:
		for key: String in (per[ph] as Dictionary):
			sum[key] = float(sum.get(key, 0.0)) + float((per[ph] as Dictionary)[key])
	t["sum"] = sum
	d.carry["totals"] = t


## Game seconds played in this run so far: the earlier phases' game time (report.phases) plus this phase's.
func play_s() -> float:
	var s := d.game_s()
	if d.report != null:
		for ph: Dictionary in d.report.phases:
			s += float(ph.get("game_s", 0.0))
	return s


## The player's map-local position, rounded to 0.1 m (a finding's "where").
func local_pos() -> String:
	var p := d.player()
	return _local(p.global_position) if p != null and is_instance_valid(p) else "?"


# =================================================================================================================
# Canonical lookups
# =================================================================================================================

func qname(qid: String) -> String:
	return String(db.quest(qid).get("name", qid))


func item_name(id: String) -> String:
	return String(db.item(id).get("name", id))


func npc_name(id: String) -> String:
	return String(db.npc(id).get("name", id))


func mob_name(id: String) -> String:
	return String(db.monster(id).get("name", id))


## EXP from level 1 at 0 EXP (every level below plus the bar).
func total_exp() -> int:
	return PlaytestLedger.total_exp(d.character(), db)


# =================================================================================================================
# Snapshots
# =================================================================================================================

## {total_exp, level, exp, mesos, bag {item: count}, counts (a copy)} of the live character.
func snapshot() -> Dictionary:
	var c := d.character()
	var bag := {}
	for tab in Inventory.TABS:
		for i in c.inventory.capacity(tab):
			var s := c.inventory.get_slot(tab, i)
			if not s.is_empty():
				var id := String(s.get("item_id", ""))
				bag[id] = int(bag.get(id, 0)) + int(s.get("qty", 1))
	return {"total_exp": total_exp(), "level": c.level, "exp": c.exp, "mesos": c.mesos, "bag": bag, "counts": bag.duplicate()}


static func count_in(bag: Dictionary, id: String) -> int:
	return int(bag.get(id, 0))


## Bag changes other than the listed items ({item_id} dictionaries): {item_id: delta}.
static func bag_delta(a: Dictionary, b: Dictionary, skip: Array) -> Dictionary:
	var skip_ids := {}
	for it: Dictionary in skip:
		skip_ids[String(it.get("item_id", ""))] = true
	var out := {}
	for id: String in a:
		if not skip_ids.has(id) and int(b.get(id, 0)) != int(a[id]):
			out[id] = int(b.get(id, 0)) - int(a[id])
	for id: String in b:
		if not skip_ids.has(id) and not a.has(id):
			out[id] = int(b[id])
	return out


## A progression checkpoint (the brief's clean-character progression audit): level, EXP, mesos, equipment, the
## important ETC items, quest states and position. Appended to d.carry["checkpoints"] (survives reloads) and noted.
func checkpoint(tag: String) -> Dictionary:
	var c := d.character()
	var etc := {}
	for row: Dictionary in (d.inventory_summary().get("etc", []) as Array):
		etc[String(row["item_id"])] = int(etc.get(String(row["item_id"]), 0)) + int(row["qty"])
	var use := {}
	for r2: Dictionary in (d.inventory_summary().get("use", []) as Array):
		use[String(r2["item_id"])] = int(use.get(String(r2["item_id"]), 0)) + int(r2["qty"])
	var row := {"tag": tag, "phase": d.phase, "game_s": snappedf(d.game_s(), 0.1), "play_s": snappedf(play_s(), 0.1),
		"play_time_s": snappedf(float(c.get("play_time_s")) if c.get("play_time_s") != null else -1.0, 0.1),
		"map": d.current_map(), "level": c.level, "exp": c.exp, "total_exp": total_exp(), "mesos": c.mesos, "ap": c.ap,
		"sp": c.sp, "hp": c.hp, "max_hp": StatCalculator.max_hp(c, db), "mp": c.mp, "stats": c.base_stats.duplicate(),
		"equipment": c.equipment.equipped(), "etc": etc, "use": use,
		"skills": (c.get("skills") as Dictionary).duplicate() if c.get("skills") is Dictionary else {},
		"deaths": (d.carry.get("deaths", []) as Array).size(),
		"quests": {"in_progress": Array(c.quests.active_ids()), "completed": Array(c.quests.completed_ids())}}
	var all: Array = d.carry.get("checkpoints", [])
	all.append(row)
	d.carry["checkpoints"] = all
	d.note("checkpoint %s: L%d %d EXP (total %d), %d mesos, equipment %s, ETC %s, quests done %s, play %.0f s" % [tag, c.level,
		c.exp, int(row["total_exp"]), c.mesos, row["equipment"], etc, row["quests"]["completed"], float(row["play_s"])])
	return row


func shot(shot_name: String) -> void:
	shots += 1
	await d.screenshot(shot_name)


# =================================================================================================================
# Travel
# =================================================================================================================

## The maps from `from` to `to` over the canonical portals (breadth first; [] when there is no way). The canonical
## portal lists already encode one-way links (000000030 -> 000000040 has no way back).
static func portal_path(content: ContentDB, from: String, to: String) -> Array:
	var prev_of := {from: ""}
	var queue: Array = [from]
	while not queue.is_empty():
		var m: String = queue.pop_front()
		if m == to:
			break
		for p: Dictionary in content.map(m).get("portals", []):
			var n := String(p.get("to_map_id", ""))
			if n != "" and not prev_of.has(n) and content.has("maps", n):
				prev_of[n] = m
				queue.append(n)
	if not prev_of.has(to):
		return []
	var path: Array = [to]
	while String(path[0]) != from:
		path.push_front(prev_of[path[0]])
	return path


## Walks map by map to `to_map` (portal_path, walk_trail per hop, one retry per hop), handling deaths (respawn and
## carry on from the respawn map) and, with opts "safe" (default true), monsters and HP on the way (walk_safely's
## policy). A hop that fails twice: with opts "fallback_warp" (non-strict scenarios only) a WARN and a console warp
## (logged setup); otherwise a failed check, and false. Rows go to travel_rows. Returns true in `to_map`. Await it.
func travel_to(to_map: String, opts: Dictionary = {}) -> bool:
	var guard := 0
	var fallback := bool(opts.get("fallback_warp", false)) and not d.is_strict()
	while d.current_map() != to_map and guard < 20:
		guard += 1
		if is_dead():
			await respawn()
			continue
		var path := portal_path(db, d.current_map(), to_map)
		if path.size() < 2:
			d.check("a way from %s to %s over the canonical portals" % [d.current_map(), to_map], false, "no portal path")
			return false
		var cur := d.current_map()
		var hop := String(path[1])
		var t0 := d.game_s()
		var at0 := d.player().global_position
		var r: Dictionary = await _trail_safely(cur, hop, opts)
		if d.current_map() == cur and not is_dead():
			r = await _trail_safely(cur, hop, opts)
		if d.current_map() == cur and not is_dead() and _flat_m(d.player().global_position, at0) < UNSTICK_STALLED_M:
			# Both walks stalled where they began (a ledge corner whose way off the planners do not take): step off it as a
			# player would, then walk the trail once more.
			if bool((await unstick()).get("ok", false)):
				r = await _trail_safely(cur, hop, opts)
		var ok := d.current_map() == hop
		travel_rows.append({"from": cur, "to": hop, "ok": ok, "how": String(r.get("how", "")), "via": String(r.get("via", "")),
			"time_s": snappedf(d.game_s() - t0, 0.1), "issues": ", ".join(r.get("issues", PackedStringArray()))})
		if ok or is_dead():
			continue
		var why := "ended in %s: %s" % [d.current_map(), ", ".join(r.get("issues", PackedStringArray()))]
		if fallback:
			d.soft_check("walked the trail %s -> %s" % [cur, hop], false, why)
			fallbacks.append("%s -> %s" % [cur, hop])
			await _setup_warp_fallback(hop)
		else:
			d.check("walked the trail %s -> %s" % [cur, hop], false, why)
			return false
	return d.current_map() == to_map


## Rows of travel_rows as one line ("0040->0041 ok walk 12.5s, ...").
func travel_text() -> String:
	var parts := PackedStringArray()
	for t: Dictionary in travel_rows:
		parts.append("%s->%s %s %s %.1fs%s" % [String(t["from"]).right(4), String(t["to"]).right(4),
			"ok" if bool(t["ok"]) else "FAIL", t.get("how", ""), float(t.get("time_s", 0.0)),
			(" (" + String(t["issues"]) + ")") if String(t.get("issues", "")) != "" else ""])
	return ", ".join(parts)


## The non-strict travel fallback: a console warp (a logged setup step). Never called in strict mode.
func _setup_warp_fallback(map_id: String) -> void:
	await d.console("warp " + map_id)


## One walk_trail with the survival policy: a threat or low HP stops the walk, survive() handles it, and the trail
## is walked again (from wherever the player stands). opts "safe" false: a plain walk_trail.
func _trail_safely(from_map: String, to_map: String, opts: Dictionary) -> Dictionary:
	if not bool(opts.get("safe", true)):
		return await d.walk_trail(from_map, to_map)
	var r: Dictionary = {}
	var guard := interrupt_when(opts)
	# Whether the guard stopped the walk: by the time the walk returns, a knockback may have pushed the monster out of
	# reach, so the guard is not asked again.
	var fired := [false]
	var stop := func() -> bool:
		if bool(guard.call()):
			fired[0] = true
			return true
		return false
	for _k in MAX_INTERRUPTS:
		fired[0] = false
		r = await d.walk_trail(from_map, to_map, {"stop_when": stop})
		if d.current_map() != from_map or is_dead() or not bool(fired[0]):
			return r
		survival["interrupts"] = int(survival["interrupts"]) + 1
		await survive(opts)
		if d.current_map() != from_map or is_dead():
			return r
	return r


## Walks to `target` (any walk_to target) in the current map with the survival policy: a monster about to touch the
## player (threat()) is fought when opts "on_threat" is "fight" (default) or ignored ("ignore"), and below opts
## "hp_floor" (HP_FLOOR) of Max HP the player drinks or rests (survive()). With opts "unstick" (false), a walk that
## stalls where it began is followed by unstick() and one more walk. Other opts go to walk_to. Returns the last
## walk_to result plus "interrupts". Await it.
func walk_safely(target: Variant, opts: Dictionary = {}) -> Dictionary:
	var r: Dictionary = {}
	var n := 0
	var map0 := d.current_map()
	var at0 := d.player().global_position
	var orig: Callable = opts.get("stop_when", Callable())
	var interrupt := interrupt_when(opts)
	var fired := [false]
	var o := opts.duplicate()
	o.erase("unstick")
	o["stop_when"] = func() -> bool:
		if orig.is_valid() and bool(orig.call()):
			return true
		if bool(interrupt.call()):
			fired[0] = true
			return true
		return false
	for _k in MAX_INTERRUPTS:
		fired[0] = false
		r = await d.walk_to(target, o)
		if d.current_map() != map0 or is_dead() or not bool(fired[0]):
			break
		n += 1
		survival["interrupts"] = int(survival["interrupts"]) + 1
		await survive(opts)
	if bool(opts.get("unstick", false)) and not bool(r.get("ok", false)) and d.current_map() == map0 and not is_dead() \
			and _flat_m(d.player().global_position, at0) < UNSTICK_STALLED_M:
		if bool((await unstick()).get("ok", false)):
			r = await d.walk_to(target, o)
	r["interrupts"] = n
	return r


## Gets the player off a spot where every planned walk stalls at once (a ledge corner whose way off neither the
## routes nor the grid takes, though a player just steps off or jumps): straight real-input pushes in 8 directions,
## then with a jump, each for at most UNSTICK_PUSH_S, until the feet stand UNSTICK_M from where they began. A logged
## "kit.unstick" step. Returns {"ok", "moved_m", "dir", "jump", "from", "to"} (map-local). Await it.
func unstick() -> Dictionary:
	var step := d._begin(PlaytestReport.KIND_PLAY, "kit.unstick", d.current_map())
	var p := d.player()
	var start := p.global_position
	var out := {"ok": false, "moved_m": 0.0, "dir": -1, "jump": false, "from": _local(start), "to": ""}
	for jump: bool in [false, true]:
		for k in 8:
			if is_dead() or d.dialogue_open():
				break
			var dir := Vector3(cos(TAU * k / 8.0), 0.0, sin(TAU * k / 8.0))
			var a := p.global_position
			var f0 := Engine.get_physics_frames()
			var jumped := false
			while Engine.get_physics_frames() - f0 < int(UNSTICK_PUSH_S * Engine.physics_ticks_per_second):
				d.input.set_move_world(dir, p.view_right, p.view_forward)
				if jump and not jumped and Engine.get_physics_frames() - f0 > 10:
					jumped = true
					await d.input.tap_action(&"jump")
				await d.get_tree().process_frame
				d.input.reassert()
				if _flat_m(p.global_position, start) >= UNSTICK_M:
					break
			d.input.release_movement()
			await d.wait_idle(3.0)
			var moved := _flat_m(p.global_position, start)
			out["moved_m"] = snappedf(maxf(float(out["moved_m"]), moved), 0.01)
			if moved >= UNSTICK_M:
				out["ok"] = true
				out["dir"] = k
				out["jump"] = jump
				break
			if _flat_m(p.global_position, a) > 0.3:
				# A push that moved a little but not far enough: back toward the start for the next direction.
				await d.walk_to(start, {"max_s": 3.0, "retries": 0, "within_m": 0.3, "planner": "grid"})
		if bool(out["ok"]):
			break
	out["to"] = _local(p.global_position)
	survival["unsticks"] = int(survival.get("unsticks", 0)) + 1
	d.note("unstick in %s: %s" % [d.current_map(), out])
	d._end(step, bool(out["ok"]), "%s -> %s, %.1f m (dir %d%s)" % [out["from"], out["to"], float(out["moved_m"]),
		int(out["dir"]), ", jump" if bool(out["jump"]) else ""])
	return out


static func _flat_m(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The walk interrupt of the survival policy, as a stop_when Callable for any walk (scenarios that walk with the
## driver directly pass it too): HP below the floor, or (on_threat "fight") a monster the player can beat that
## touched it in the last TOUCH_MEMORY_S and is still next to it. A monster merely passing by never stops a walk (a
## player walks past snails and only turns on the one that keeps hitting), and neither does one far above the
## player's level (FIGHT_LEVEL_GAP): the player walks on and heals or rests when HP runs low.
func interrupt_when(opts: Dictionary = {}) -> Callable:
	var floor_frac := float(opts.get("hp_floor", HP_FLOOR))
	var fight := String(opts.get("on_threat", "fight")) == "fight"
	var o := opts.duplicate()
	o["beatable_only"] = true
	return func() -> bool:
		if is_dead() or d.character() == null:
			return false
		if hp_frac() < floor_frac:
			return true
		return fight and hp_frac() >= FIGHT_BACK_HP and touched_recently() and threat(o) != null


## True when the player can fight `m` (a live monster node): its canonical level is at most FIGHT_LEVEL_GAP above
## the player's.
func beatable(m: Node3D) -> bool:
	var def: Variant = m.get("def") if is_instance_valid(m) else null
	var st: Variant = def.get("stats") if def != null else null
	var lv := int(st.get("level")) if st != null and st.get("level") != null else 0
	return lv <= d.character().level + FIGHT_LEVEL_GAP


## True when a monster damaged the player in the last TOUCH_MEMORY_S (connect_bus() hears it).
func touched_recently() -> bool:
	return d.game_s() - last_touch_s < TOUCH_MEMORY_S


func hp_frac() -> float:
	var c := d.character()
	var mx := StatCalculator.max_hp(c, db)
	return float(c.hp) / float(mx) if mx > 0 else 1.0


## The live monster about to touch the player: within THREAT_M horizontally on the same tier, or the one that
## touched the player in the last second. null when none. opts "ignore_mobs": species never treated as threats;
## "beatable_only": only monsters the player can fight (beatable()).
func threat(opts: Dictionary = {}) -> Node3D:
	var ms := d.monsters()
	var p := d.player()
	if ms == null or p == null:
		return null
	var ignore: Array = opts.get("ignore_mobs", [])
	var only_beatable := bool(opts.get("beatable_only", false))
	var best: Node3D = null
	var best_d := float(opts.get("threat_m", THREAT_M))
	var touched := d.game_s() - last_touch_s < 1.0
	for m: Node3D in ms.call("live_monsters"):
		if not is_instance_valid(m) or not bool(m.call("is_alive")):
			continue
		var id := String(m.get("def").get("id"))
		if ignore.has(id) or (only_beatable and not beatable(m)) or shunned(m):
			continue
		var dy := absf(m.global_position.y - p.global_position.y)
		var dd := Vector2(m.global_position.x - p.global_position.x, m.global_position.z - p.global_position.z).length()
		var reach := best_d if not (touched and id == last_touch_mob) else maxf(best_d, 4.0)
		if dy <= THREAT_DY_M and dd < reach:
			best_d = dd
			best = m
	return best


# =================================================================================================================
# Survival policy
# =================================================================================================================

## Keeps the player alive (the policy the walks and hunts share): below opts "hp_floor" (HP_FLOOR) it drinks the
## best HP consumable held (the Item window: Use tab, slot, Use); with nothing to drink it walks away from the
## monsters and rests (stands still: natural recovery) until opts "hp_resume" (HP_RESUME) or REST_MAX_S, fighting
## back whatever comes close. Above the floor, a threat is fought (opts "on_threat" "fight"). Returns {"drank",
## "rested_s", "fought"}. Await it.
func survive(opts: Dictionary = {}) -> Dictionary:
	var out := {"drank": 0, "rested_s": 0.0, "fought": 0}
	var floor_frac := float(opts.get("hp_floor", HP_FLOOR))
	var resume := float(opts.get("hp_resume", HP_RESUME))
	if is_dead():
		return out
	var guard := 0
	while hp_frac() < floor_frac and guard < 6 and not is_dead():
		guard += 1
		var potion := best_heal_item()
		if potion == "":
			break
		var r: Dictionary = await drink(potion)
		if not bool(r.get("ok", false)):
			break
		out["drank"] = int(out["drank"]) + 1
		survival["drinks"] = int(survival["drinks"]) + 1
	if hp_frac() < floor_frac and not is_dead():
		out["rested_s"] = await rest(resume, opts)
	elif String(opts.get("on_threat", "fight")) == "fight" and hp_frac() >= FIGHT_BACK_HP:
		var o := opts.duplicate()
		o["beatable_only"] = true
		var t := threat(o)
		if t != null and not is_dead():
			# That monster, not the nearest of its species (horizontally nearest can be one on another tier).
			var f: Dictionary = await d.face_and_attack_nearest(15.0, {"target": t, "max_dist_m": 6.0, "chase": false})
			out["fought"] = int(out["fought"]) + 1
			survival["fights_back"] = int(survival["fights_back"]) + 1
			if bool(f.get("ok", false)):
				await pickup(4.0, 6.0)
			elif is_instance_valid(t) and String(f.get("why", "")).contains("out of reach"):
				# On a ledge just above or below: not a threat the player can answer; walk on (SHUN_S).
				shun(t)
	return out


## Stops counting a monster as a threat for SHUN_S game seconds (a fight back could not reach it).
func shun(m: Node3D) -> void:
	_shunned[m.get_instance_id()] = d.game_s() + SHUN_S
	survival["shunned"] = int(survival.get("shunned", 0)) + 1


func shunned(m: Node3D) -> bool:
	return float(_shunned.get(m.get_instance_id(), -1.0)) > d.game_s()


## The HP consumable to drink: the held one that restores the most HP ("" when none).
func best_heal_item() -> String:
	var c := d.character()
	var best := ""
	var best_hp := 0
	for row: Dictionary in (d.inventory_summary().get("use", []) as Array):
		var id := String(row["item_id"])
		var hp := hp_restore(id)
		if hp > best_hp and c.inventory.count(id) > 0:
			best_hp = hp
			best = id
	return best


## The canonical HP an item restores (items/<id>.json consumable.hp_restore; 0 for anything else, arrows included).
func hp_restore(item_id: String) -> int:
	var cons: Variant = db.item(item_id).get("consumable")
	return int((cons as Dictionary).get("hp_restore", 0)) if cons is Dictionary and (cons as Dictionary).get("hp_restore") != null else 0


## Rests: walks to the player spawn or portal arrival farthest from the live monsters (when one is closer than
## REST_CLEAR_M), then stands still (sits when C5's sitting exists and opts "sit" is set) until HP reaches `until`
## of Max HP or REST_MAX_S passes. A monster that comes close is walked away from (to the quietest spot, a few times);
## only a cornered player fights back, and only a monster it can beat. Returns the game seconds rested. Await it.
func rest(until: float, opts: Dictionary = {}) -> float:
	var t0 := d.game_s()
	survival["rests"] = int(survival["rests"]) + 1
	var spot := _rest_spot()
	# A far spot means a long walk at low HP past the same monsters: rest where the player is instead. On the way, a
	# new touch ends the walk (resting there beats walking on through the monsters).
	if spot != Vector3.INF and spot.distance_to(d.player().global_position) <= REST_WALK_MAX_M:
		await d.walk_to(spot, {"max_s": 25.0, "retries": 0, "within_m": 1.5, "stop_when": _new_touch_or_death()})
	if bool(opts.get("sit", false)):
		await sit()
	var moves := 0
	var ignored := {}
	while hp_frac() < until and d.game_s() - t0 < float(opts.get("rest_max_s", REST_MAX_S)) and not is_dead():
		var t := threat({"threat_m": 3.0})
		if t != null and moves < REST_MOVES:
			# Move to the quietest spot and rest there.
			moves += 1
			var away := _rest_spot()
			if away != Vector3.INF and away.distance_to(d.player().global_position) <= REST_WALK_MAX_M \
					and away.distance_to(d.player().global_position) > 2.0:
				await d.walk_to(away, {"max_s": 25.0, "retries": 0, "within_m": 1.5, "stop_when": _new_touch_or_death()})
				continue
		if t != null and beatable(t) and not ignored.has(t.get_instance_id()) and touched_recently():
			# Cornered and being hit: fight back what it can beat.
			var f: Dictionary = await d.face_and_attack_nearest(15.0, {"target": t, "max_dist_m": 6.0, "chase": false})
			survival["fights_back"] = int(survival["fights_back"]) + 1
			if hp_frac() < 0.2 and best_heal_item() != "":
				await drink(best_heal_item())
			if not bool(f.get("ok", false)):
				# Out of reach without a chase (a ledge just above): leave it be for this rest.
				ignored[t.get_instance_id()] = true
			continue
		await d.wait(0.5)
	var s := d.game_s() - t0
	survival["rest_s"] = float(survival["rest_s"]) + s
	return s


## A stop_when for a walk at low HP: the player died, or a monster touched it after the walk began.
func _new_touch_or_death() -> Callable:
	var since := last_touch_s
	return func() -> bool: return is_dead() or last_touch_s > since


## The player spawn or portal arrival of the current map farthest from the nearest live monster, when the player
## stands closer than REST_CLEAR_M to one; Vector3.INF to rest where the player is.
func _rest_spot() -> Vector3:
	var w := d.world()
	var p := d.player()
	var ms := d.monsters()
	if w == null or p == null or ms == null or not w.defs.has_map(d.current_map()):
		return Vector3.INF
	var mobs: Array = []
	for m: Node3D in ms.call("live_monsters"):
		if is_instance_valid(m) and bool(m.call("is_alive")):
			mobs.append(m.global_position)
	var clear := func(at: Vector3) -> float:
		var best := INF
		for q: Vector3 in mobs:
			best = minf(best, Vector2(q.x - at.x, q.z - at.z).length())
		return best
	if float(clear.call(p.global_position)) >= REST_CLEAR_M:
		return Vector3.INF
	var def := w.defs.get_def(d.current_map())
	var cands: Array = []
	for t: Transform3D in def.player_spawns:
		cands.append(t.origin)
	for pd: PortalDef in def.canonical_portals():
		cands.append(pd.spawn_transform.origin)
	var best_at := Vector3.INF
	var best_c := -1.0
	for at: Vector3 in cands:
		var cl := float(clear.call(at))
		if cl > best_c:
			best_c = cl
			best_at = at
	return best_at


# =================================================================================================================
# Death
# =================================================================================================================

func is_dead() -> bool:
	var p := d.player()
	return d.game().is_character_dead() or (p != null and is_instance_valid(p) and p.is_dead())


## The death notice on screen, or null.
func death_notice() -> DeathNotice:
	var gs := d.main.game_session if d.main != null else null
	if gs == null or gs.death == null:
		return null
	var n: DeathNotice = gs.death.notice
	return n if n != null and is_instance_valid(n) and n.is_visible_in_tree() else null


## As a player does after dying: waits for the death notice, clicks its OK, waits for the respawn. opts "shot":
## a screenshot name for the notice (once per run, d.carry flag). Returns the row appended to `deaths`. Await it.
func respawn(opts: Dictionary = {}) -> Dictionary:
	var c := d.character()
	var row := {"map": d.current_map(), "level": c.level, "game_s": snappedf(d.game_s(), 0.1)}
	var shown := await d.wait_until(func() -> bool: return death_notice() != null, 15.0)
	var shot_name := String(opts.get("shot", ""))
	if shown and shot_name != "" and not d.carry.has("shot_" + shot_name):
		d.carry["shot_" + shot_name] = true
		await shot(shot_name)
	var n := death_notice()
	var clicked := false
	if n != null:
		var r: Dictionary = await d.click(n.ok_button)
		clicked = bool(r["ok"])
	var back := await d.wait_until(func() -> bool: return not is_dead() and bool(d.session().call("is_idle")), 30.0)
	await d.wait_idle()
	row["notice"] = shown
	row["ok_clicked"] = clicked
	row["respawned"] = back
	row["respawn_map"] = d.current_map()
	row["hp_after"] = d.character().hp
	deaths.append(row)
	d.note("died in %s (L%d), respawned in %s (OK %s)" % [row["map"], int(row["level"]), d.current_map(), clicked])
	return row


# =================================================================================================================
# NPCs and conversations
# =================================================================================================================

## talk_to, as a player keeps trying: a death on the way is a WARN (play, not a quest failure), the notice's OK, the
## walk back to the NPC's map and another approach (at most 3). When no approach point can be planned from where the
## player stands (below a perch whose stairs start elsewhere), the player walks back to the map's arrival (player
## spawn 0), where every NPC's way starts (the npcs survey), and tries once more from there; a player whose walk to
## the arrival stalls where it began steps off the spot first (unstick()). The result carries
## "pre": a snapshot taken right before the approach that opened the chat ("t", "clock", "notices" too), the
## baseline of a reward check: a quest with no completion text completes the moment the chat opens. Await it.
func talk(npc_id: String) -> Dictionary:
	var map := d.current_map()
	var v: Dictionary = {}
	var from_spawn := false
	for attempt in 4:
		var hp0 := d.character().hp
		var dmg0 := damage_taken
		var tc0 := touches.size()
		var pre := snapshot()
		pre["t"] = d.game_s()
		pre["clock"] = log_clock()
		pre["notices"] = d.notices.size()
		on_screen_at_complete = []
		v = await d.talk_to(npc_id)
		v["pre"] = pre
		if bool(v.get("open", false)):
			return v
		if not is_dead():
			if from_spawn or d.current_map() != map:
				return v
			from_spawn = true
			d.note("%s cannot be reached from here (%s): walking back to the map's arrival and trying again" % [
				npc_name(npc_id), String(v.get("why", "")).left(120)])
			await walk_safely("spawn:0", {"max_s": 60.0, "unstick": true})
			continue
		d.soft_check("the walk up to %s (%s) ends alive" % [npc_name(npc_id), map], false,
			"died on the approach (attempt %d): HP %d at the start, %d damage from %d touches since (%s)" % [attempt + 1, hp0,
				damage_taken - dmg0, touches.size() - tc0, ", ".join(touches.slice(tc0))])
		await respawn()
		if not await travel_to(map):
			return v
	return v


## Walks up to a few metres of an NPC (real input, the survival policy on the way), as a player does before talking,
## so its quest marker is on screen when it is read. A death on the way: OK, the walk back, one more try. Await it.
func approach(npc_id: String) -> void:
	var map := d.current_map()
	for attempt in 2:
		var hp0 := d.character().hp
		var dmg0 := damage_taken
		var tc0 := touches.size()
		await walk_safely("npc:" + npc_id, {"within_m": 3.5, "max_s": 45.0})
		if not is_dead():
			return
		d.soft_check("the walk up to %s (%s) ends alive" % [npc_name(npc_id), map], false,
			"died on the approach (walk %d): HP %d at the start, %d damage from %d touches since (%s)" % [attempt + 1, hp0,
				damage_taken - dmg0, touches.size() - tc0, ", ".join(touches.slice(tc0))])
		await respawn()
		if not await travel_to(map):
			return


## Plays the open conversation with the window's keys. goals: quest id -> "accept" | "decline" | "complete" |
## "quiz_wrong" (answer the quiz with its first wrong choice) | "quiz_wrong:<rank>". A menu picks the entry of a goal
## not met yet (else End Chat); a quiz menu (node q<id>.quiz) is answered with the canonical correct choice
## (quiz_answer) or the requested wrong one; a Yes/No answers Y for a goal "accept" of a quest not started and N
## otherwise; a line is paged with Enter. opts "shot_on_complete": a screenshot when a goal quest completes.
## Returns {"pages", "banners", "quiz": [{quest, picked, correct, choice, response}]}. Await it.
func converse(goals: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var c := d.character()
	var pages: PackedStringArray = []
	var banners: PackedStringArray = []
	var quiz: Array = []
	var guard := 0
	var done_before := {}
	var answered := {}
	for qid: String in goals:
		done_before[qid] = c.quests.is_completed(qid)
	var v := d.read_dialogue()
	while bool(v["open"]) and guard < 60:
		guard += 1
		var view: Dictionary = v["view"]
		var node := String(view.get("node_id", ""))
		var t := String(v["type"])
		var b := String(v.get("banner", ""))
		if b != "" and (banners.is_empty() or banners[banners.size() - 1] != b):
			banners.append(b)
		pages.append("%s[%s] %s" % [node, t, String(v.get("text", "")).replace("\n", " ").left(70)])
		await _note_completion(goals, done_before, bool(opts.get("shot_on_complete", false)))
		if t == "menu" and node.ends_with(".quiz"):
			var qid := node_quest(node)
			if answered.has(qid):
				v = await d.choose("end")
				break
			answered[qid] = true
			var key := quiz_answer(db, qid)
			var goal := String(goals.get(qid, "complete"))
			var pick := int(key.get("index", -1))
			var want_wrong := goal.begins_with("quiz_wrong")
			if want_wrong:
				var rank := int(goal.get_slice(":", 1)) if goal.contains(":") else 0
				var wrong: Array = key.get("wrong", [])
				if not wrong.is_empty():
					pick = int((wrong[mini(rank, wrong.size() - 1)] as Dictionary)["index"])
			var picked_text := String(((view.get("choices", []) as Array)[pick] as Dictionary).get("text", "")) \
				if pick >= 0 and pick < (view.get("choices", []) as Array).size() else ""
			v = await d.choose(pick)
			quiz.append({"quest": qid, "picked": pick, "correct": pick == int(key.get("index", -2)), "choice": picked_text,
				"response": String(v.get("text", "")) if bool(v.get("open", false)) else ""})
			continue
		if t == "menu":
			var pick := -1
			var choices: Array = view.get("choices", [])
			for k in choices.size():
				var qid := String((choices[k] as Dictionary).get("quest_id", ""))
				if goals.has(qid) and not _goal_met(qid, String(goals[qid])) and not answered.has(qid):
					pick = k
					break
			if pick < 0:
				v = await d.choose("end")
				break
			v = await d.choose(pick)
		elif t == "yes_no":
			var qid := node_quest(node)
			var yes := String(goals.get(qid, "")) == "accept" and c.quests.status(qid) == QuestLog.NOT_STARTED
			v = await d.choose("yes" if yes else "no")
		elif "next" in v["buttons"] or "ok" in v["buttons"]:
			v = await d.next()
		else:
			break
	await _note_completion(goals, done_before, false)
	if d.dialogue_open():
		await d.close_dialogue()
	await d.frames(2)
	return {"pages": pages, "banners": banners, "quiz": quiz}


func _note_completion(goals: Dictionary, done_before: Dictionary, take_shot: bool) -> void:
	var c := d.character()
	for qid: String in goals:
		if not bool(done_before[qid]) and c.quests.is_completed(qid) and on_screen_at_complete.is_empty():
			on_screen_at_complete = log_on_screen()
			if take_shot:
				await shot("reward_%s" % qid)


func _goal_met(qid: String, goal: String) -> bool:
	var c := d.character()
	if goal == "accept":
		return c.quests.status(qid) != QuestLog.NOT_STARTED
	if goal == "decline":
		return false
	return c.quests.is_completed(qid)


## The quest of a dialogue node id ("q1013.quiz" -> "1013"), "" for others.
static func node_quest(node: String) -> String:
	if not node.begins_with("q"):
		return ""
	return node.substr(1).get_slice(".", 0)


## The canonical answer key of a quiz quest (quests/<id>.json dialogue.on_completion.quiz): {"ok", "index" (the
## canonical correct_choice_index), "text", "basis" (meowdb_marker | inferred_from_meowdb_responses), "question",
## "choices" [text], "wrong" [{index, text, response}] (MeowDB lists one wrong-answer line per wrong choice in choice
## order; the game pairs them in that order), "right_response"}. {"ok": false} for a quest without a quiz.
static func quiz_answer(content: ContentDB, qid: String) -> Dictionary:
	var dlg: Dictionary = content.quest(qid).get("dialogue", {})
	var quiz: Variant = (dlg.get("on_completion", {}) as Dictionary).get("quiz")
	if not (quiz is Dictionary) or (quiz as Dictionary).is_empty():
		return {"ok": false, "quest": qid}
	var z: Dictionary = quiz
	var choices: Array = z.get("choices", [])
	var idx := int(z.get("correct_choice_index", -1)) if z.get("correct_choice_index") != null else -1
	var texts := PackedStringArray()
	for ch: Dictionary in choices:
		texts.append(String(ch.get("text", "")))
	var wrong_lines: Array = z.get("wrong_answer_responses", [])
	var wrong: Array = []
	var rank := 0
	for i in choices.size():
		if i == idx:
			continue
		var line := ""
		if not wrong_lines.is_empty():
			line = String((wrong_lines[mini(rank, wrong_lines.size() - 1)] as Dictionary).get("text", ""))
		wrong.append({"index": i, "text": texts[i], "response": line})
		rank += 1
	var q: Variant = z.get("question")
	var right: Variant = z.get("correct_answer_response")
	return {"ok": idx >= 0 and idx < choices.size(), "quest": qid, "index": idx,
		"text": texts[idx] if idx >= 0 and idx < texts.size() else "", "basis": String(z.get("correct_choice_basis", "")),
		"question": String((q as Dictionary).get("text", "")) if q is Dictionary else "", "choices": texts,
		"wrong": wrong, "right_response": String((right as Dictionary).get("text", "")) if right is Dictionary else ""}


## The quest marker the HUD draws over an NPC (its NpcPresenter's QuestMarker), after its own refresh tick, and the
## engine's answer for comparison: {"npc", "state", "visible", "engine", "dist_m"}. Await it.
func marker(npc_id: String) -> Dictionary:
	await d.wait(0.5)
	var inter := d.interaction()
	var pres: Dictionary = inter.get("presenters") if inter != null else {}
	var p: Variant = pres.get(npc_id)
	var out := {"npc": npc_id, "state": "(no presenter)", "visible": false, "engine": d.game().npc_talk.marker(npc_id)}
	if p is NpcPresenter and is_instance_valid(p):
		var mk := (p as NpcPresenter).marker
		if mk != null and is_instance_valid(mk):
			out["state"] = mk.state
			out["visible"] = mk.visible
		var npc := (p as NpcPresenter).npc
		if npc != null and is_instance_valid(npc) and d.player() != null:
			out["dist_m"] = snappedf(npc.global_position.distance_to(d.player().global_position), 0.01)
	# Windowed, a marker with a state over an NPC the player stands next to must be drawn.
	if DisplayServer.get_name() != "headless" and String(out["state"]) not in ["", "(no presenter)"] \
			and float(out.get("dist_m", 99.0)) < 6.0:
		d.soft_check("the '%s' marker over %s is drawn (the player stands %.1f m away)" % [out["state"], npc_name(npc_id),
			float(out["dist_m"])], bool(out["visible"]), str(out))
	return out


## Opens the Quest Log with its key (if closed), clicks the tab and the quest's row with the mouse, and reads it:
## {"open", "tab", "tab_text", "listed", "selected", "list", "rows", "detail"}. Await it.
func quest_window(qid: String, tab: String) -> Dictionary:
	var wr := d.windows() as MisoWindowsRoot
	var qw := wr.quests
	if not bool(wr.call("is_open", "quests")):
		await d.open_window("quests")
	if qw.current_tab != tab:
		await d.click(qw.tab_buttons[tab])
		await d.frames(2)
	var btn: Button = null
	var names: PackedStringArray = []
	for b in qw.list_box.get_children():
		if b is Button:
			names.append((b as Button).text)
			if String(b.get_meta("quest_id", "")) == qid:
				btn = b
	if btn != null and qw.selected_quest != qid:
		await d.click(btn)
		await d.frames(2)
	return {"open": bool(wr.call("is_open", "quests")), "tab": qw.current_tab, "tab_text": (qw.tab_buttons[tab] as Button).text,
		"listed": btn != null, "selected": qw.selected_quest, "list": names, "rows": qw.objective_rows(),
		"detail": qw.detail_texts()}


static func row_has(rows: Array, text: String, done: bool) -> bool:
	for r: Dictionary in rows:
		if String(r.get("text", "")) == text and (not done or bool(r.get("done", false))):
			return true
	return false


## True when a row's text contains `needle` (the turn-in row names the NPC whatever its verb: "Return to Mai").
static func row_contains(rows: Array, needle: String) -> bool:
	for r: Dictionary in rows:
		if String(r.get("text", "")).contains(needle):
			return true
	return false


static func rows_text(rows: Array) -> String:
	var out: PackedStringArray = []
	for r: Dictionary in rows:
		out.append("%s%s" % [r.get("text", ""), " [x]" if bool(r.get("done", false)) else ""])
	return "; ".join(out)


static func any_contains(list: Variant, needle: String) -> bool:
	for s: Variant in list:
		if String(s).contains(needle):
			return true
	return false


# =================================================================================================================
# The HUD log
# =================================================================================================================

func hud() -> MisoHud:
	return d.hud() as MisoHud


func log_clock() -> float:
	var h := hud()
	return float(h.log_panel.get("_clock")) if h != null else 0.0


## HUD log lines added at or after `clock0` (the log's own clock).
func log_since(clock0: float) -> PackedStringArray:
	var out: PackedStringArray = []
	var h := hud()
	if h == null:
		return out
	for e: Dictionary in h.log_panel.history:
		if float(e.get("time", -1.0)) >= clock0:
			out.append(String(e.get("text", "")))
	return out


## The log lines on screen now (not faded out).
func log_on_screen() -> PackedStringArray:
	var out: PackedStringArray = []
	var h := hud()
	if h == null:
		return out
	for ch in h.log_panel.get_children():
		if ch.is_queued_for_deletion() or not (ch as Control).visible or (ch as Control).modulate.a <= 0.05:
			continue
		for l in ch.find_children("*", "Label", true, false):
			out.append((l as Label).text)
	return out


## The log lines that are not EXP lines.
static func quest_lines(lines: PackedStringArray) -> String:
	var out: PackedStringArray = []
	for l in lines:
		if not l.begins_with("You have gained"):
			out.append(l)
	return " / ".join(out)


# =================================================================================================================
# Items: the Item window and quickslots
# =================================================================================================================

static func center(c: Control) -> Vector2:
	return c.get_global_transform_with_canvas() * (c.size * 0.5)


## A real double-click: press, release, then the second press with double_click set (the flag the OS sets), release.
## `probe` is read right before and right after the second press (dispatch is synchronous): {"before", "after",
## "why"}. A control a player cannot click (off the screen or covered: PlaytestDriver.pointer_onto) is not pressed:
## "why" says so and a failed check records it.
func double_click(c: Control, probe: Callable = Callable()) -> Dictionary:
	var why := await d.pointer_onto(c)
	if why != "":
		d.check("a player can double-click %s" % (String(c.name) if is_instance_valid(c) else "a control"), false, why)
		return {"before": null, "after": null, "why": why}
	var at := center(c)
	await d.frames(1)
	d.input.mouse_button(at, true)
	await d.frames(1)
	d.input.mouse_button(at, false)
	await d.frames(1)
	var before: Variant = probe.call() if probe.is_valid() else null
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = true
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = d.input.to_window(at)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	var after: Variant = probe.call() if probe.is_valid() else null
	await d.frames(1)
	d.input.mouse_button(at, false)
	await d.frames(1)
	return {"before": before, "after": after, "why": ""}


## A real GUI drag: press on `from`, move past the drag threshold, glide onto `to`, release. Both ends must be where a
## player can point at them (PlaytestDriver.pointer_onto: on the screen, not covered); otherwise nothing is pressed,
## "why" says which end and a failed check records it. {"dragging", "target_topmost", "why"}.
func drag(from: Control, to: Control) -> Dictionary:
	var vp := d.get_viewport()
	var a := center(from)
	var b := center(to)
	var why_to := await d.pointer_onto(to)
	var why_from := await d.pointer_onto(from) if why_to == "" else ""
	if why_to != "" or why_from != "":
		var why := "drop target: " + why_to if why_to != "" else "drag source: " + why_from
		d.check("a player can drag %s onto %s" % [String(from.name) if is_instance_valid(from) else "a control",
			String(to.name) if is_instance_valid(to) else "a control"], false, why)
		return {"dragging": false, "target_topmost": false, "why": why}
	d.input.mouse_move(b)
	await d.frames(1)
	var hov := vp.gui_get_hovered_control()
	var topmost := hov != null and (hov == to or to.is_ancestor_of(hov))
	d.input.mouse_move(a)
	await d.frames(1)
	d.input.mouse_button(a, true)
	await d.frames(1)
	d.input.mouse_move(a + Vector2(12, 0))
	await d.frames(1)
	d.input.mouse_move(a + Vector2(24, 0))
	await d.frames(1)
	var dragging := vp.gui_is_dragging()
	for k in range(1, 7):
		d.input.mouse_move(a.lerp(b, k / 6.0))
		await d.frames(1)
	d.input.mouse_button(b, false)
	await d.frames(2)
	return {"dragging": dragging, "target_topmost": topmost, "why": ""}


func inventory_window() -> MisoInventoryWindow:
	return (d.windows() as MisoWindowsRoot).inventory


## The slot index of an item in an inventory tab (-1 when not held there).
func slot_index(tab: String, item_id: String) -> int:
	var c := d.character()
	for i in c.inventory.capacity(tab):
		if String(c.inventory.get_slot(tab, i).get("item_id", "")) == item_id:
			return i
	return -1


## Opens the Item window on the item's tab (I, then a click on the tab). Returns the slot index (-1: not held).
func _open_on_item(item_id: String) -> int:
	var wr := d.windows() as MisoWindowsRoot
	var tab := String(db.item(item_id).get("inventory_tab", "use"))
	await d.open_window("inventory")
	await d.click(wr.inventory.tab_buttons[tab])
	await d.frames(2)
	return slot_index(tab, item_id)


## Uses one of an item the way a player does: via "double_click" (default: I, the item's tab, a double-click on its
## slot), "button" (I, the slot, the window's Use button) or "quickslot" (the key it is bound to; bind_quickslot).
## Returns {"ok" (one used), "status", "hp0", "hp1", "n0", "n1", "via"}. Await it.
func use_item(item_id: String, via: String = "double_click") -> Dictionary:
	var c := d.character()
	var out := {"ok": false, "status": "", "hp0": c.hp, "hp1": c.hp, "n0": c.inventory.count(item_id), "n1": 0, "via": via}
	# hp0 / n0 and hp1 / n1 are read right around the input that uses the item (dispatch is synchronous), so a touch
	# while the window opens or closes does not blur the effect.
	var probe := func() -> Dictionary: return {"hp": c.hp, "n": c.inventory.count(item_id)}
	var around: Dictionary = {}
	if via == "quickslot":
		var key := quickslot_of(item_id)
		if key == "":
			out["status"] = "%s is on no quickslot" % item_id
			return out
		var code := PlaytestInput.key_for_action(StringName("quickslot_%s" % key))
		var b0: Dictionary = probe.call()
		d.input.key_event(code, true)
		around = {"before": b0, "after": probe.call()}
		d.input.key_event(code, false)
		await d.frames(2)
	else:
		var idx := await _open_on_item(item_id)
		var win := inventory_window()
		if idx < 0 or idx >= win.slots.size():
			await d.close_window("inventory")
			out["status"] = "no slot for %s" % item_id
			return out
		if via == "button":
			await d.click(win.slots[idx])
			await d.frames(1)
			var b1: Dictionary = probe.call()
			await d.click(win.action_button)
			around = {"before": b1, "after": probe.call()}
		else:
			around = await double_click(win.slots[idx], probe)
		await d.frames(2)
		out["status"] = win.status_label.text
		await d.close_window("inventory")
	var before: Dictionary = around.get("before", {}) if around.get("before") is Dictionary else {}
	var after: Dictionary = around.get("after", {}) if around.get("after") is Dictionary else {}
	out["hp0"] = int(before.get("hp", out["hp0"]))
	out["n0"] = int(before.get("n", out["n0"]))
	out["hp1"] = int(after.get("hp", c.hp))
	out["n1"] = int(after.get("n", c.inventory.count(item_id)))
	out["ok"] = int(out["n1"]) == int(out["n0"]) - 1
	return out


## Drinks an HP/MP consumable through the Item window (I, the Use tab, a click on the slot, the Use button), as
## test_c's hunter does. Returns use_item()'s result plus "want_hp" (the canonical restore, capped at Max HP) and
## "row" (a readable line). Await it.
func drink(item_id: String) -> Dictionary:
	var c := d.character()
	var restore := hp_restore(item_id)
	var mx := StatCalculator.max_hp(c, db)
	var r := await use_item(item_id, "button")
	r["want_hp"] = mini(mx, int(r["hp0"]) + restore)
	r["row"] = "L%d HP %d -> %d/%d (canonical +%d -> %d), %s %d -> %d" % [c.level, int(r["hp0"]), int(r["hp1"]), mx,
		restore, int(r["want_hp"]), item_name(item_id), int(r["n0"]), int(r["n1"])]
	return r


## Equips a held piece by double-clicking it in the Item window's Equip tab. Returns {"ok" (now equipped), "slot",
## "status"}. Await it.
func equip(item_id: String) -> Dictionary:
	var c := d.character()
	var idx := await _open_on_item(item_id)
	var win := inventory_window()
	if idx < 0 or idx >= win.slots.size():
		await d.close_window("inventory")
		return {"ok": false, "slot": "", "status": "no slot for %s" % item_id}
	await double_click(win.slots[idx])
	await d.frames(2)
	var status := win.status_label.text
	await d.close_window("inventory")
	var eq := c.equipment.equipped()
	for slot: Variant in eq:
		if String(eq[slot]) == item_id:
			return {"ok": true, "slot": String(slot), "status": status}
	return {"ok": false, "slot": "", "status": status}


## The quickslot key ("1".."8") an item is bound to ("" when none). Reads both quickslot shapes: the bare item id
## and contract C3's {"kind": "item", "id"}.
func quickslot_of(item_id: String) -> String:
	return quickslot_key(d.character().quickslots, "item", item_id)


## The key of `quickslots` (CharacterState.quickslots) bound to an item or a skill ("" when none). An entry is a bare
## item id (Iteration Two saves) or contract C3's {"kind": "item" | "skill", "id"}.
static func quickslot_key(quickslots: Dictionary, kind: String, id: String) -> String:
	for key: Variant in quickslots:
		var v: Variant = quickslots[key]
		if kind == "item" and v is String and String(v) == id:
			return String(key)
		if v is Dictionary and String((v as Dictionary).get("kind", "item")) == kind \
				and String((v as Dictionary).get("id", (v as Dictionary).get("item_id", ""))) == id:
			return String(key)
	return ""


## Binds a held consumable to a quickslot key by dragging its Item window slot onto the HUD's quickslot. Returns
## {"ok", "dragging"}. Await it.
func bind_quickslot(item_id: String, key: String) -> Dictionary:
	var idx := await _open_on_item(item_id)
	var win := inventory_window()
	var bar: Variant = hud().status.quickslots
	if idx < 0 or idx >= win.slots.size() or bar == null:
		await d.close_window("inventory")
		return {"ok": false, "dragging": false}
	var qs: Control = (bar.get("slots") as Dictionary).get(key)
	var dr := await drag(win.slots[idx], qs)
	await d.close_window("inventory")
	return {"ok": quickslot_of(item_id) == key, "dragging": dr["dragging"]}


# =================================================================================================================
# AP through the Character Stats window
# =================================================================================================================

func stats_window() -> MisoStatsWindow:
	return (d.windows() as MisoWindowsRoot).window_by_name("stats") as MisoStatsWindow


## One mouse click on the stats window's "+" of a stat (the window must be open). {"ok" (one AP spent on it), "ap0",
## "ap1", "stat0", "stat1"}. Await it.
func click_plus(stat: String) -> Dictionary:
	var c := d.character()
	var win := stats_window()
	var ap0 := c.ap
	var s0 := c.get_base_stat(stat)
	var r: Dictionary = await d.click(win.plus_buttons[stat] as Button)
	await d.frames(1)
	return {"ok": bool(r["ok"]) and c.ap == ap0 - 1 and c.get_base_stat(stat) == s0 + 1, "click": bool(r["ok"]),
		"ap0": ap0, "ap1": c.ap, "stat0": s0, "stat1": c.get_base_stat(stat)}


## Spends the unspent AP through the real stats window (C, then a click on "+" per point), cycling through `plan`
## (stat names, e.g. ["str", "dex"]). Returns {"ok", "spent", "issues"}. Await it.
func allocate_ap(plan: Array = ["str", "dex"]) -> Dictionary:
	var c := d.character()
	var out := {"ok": true, "spent": 0, "issues": PackedStringArray()}
	if c.ap <= 0 or is_dead() or plan.is_empty():
		return out
	if not await d.open_window("stats"):
		out["ok"] = false
		(out["issues"] as PackedStringArray).append("C did not open the stats window")
		return out
	await d.frames(2)
	var k := 0
	var guard := 0
	while c.ap > 0 and guard < 200:
		guard += 1
		var stat := String(plan[k % plan.size()])
		k += 1
		var r := await click_plus(stat)
		if bool(r["ok"]):
			out["spent"] = int(out["spent"]) + 1
		else:
			out["ok"] = false
			(out["issues"] as PackedStringArray).append("'+' %s: %s" % [stat, r])
			break
	await d.close_window("stats")
	return out


# =================================================================================================================
# Shops
# =================================================================================================================

## Talks to a shopkeeper and pages the greeting until the shop window opens. Returns true when it is open. Await it.
func open_shop(npc_id: String) -> bool:
	var t := await talk(npc_id)
	if not bool(t.get("open", false)):
		return false
	var guard := 0
	while not d.shop_open() and d.dialogue_open() and guard < 10:
		guard += 1
		var v := d.read_dialogue()
		if "next" in v["buttons"] or "ok" in v["buttons"]:
			await d.next()
		else:
			break
		await d.frames(2)
	return await d.wait_until(func() -> bool: return d.shop_open(), 2.0)


func buy(item_id: String, qty: int = 1) -> Dictionary:
	return await d.shop_buy(item_id, qty)


func sell(item_id: String, qty: int = 1) -> Dictionary:
	return await d.shop_sell(item_id, qty)


func close_shop() -> bool:
	return await d.close_shop()


# =================================================================================================================
# Loot: the precise pickup
# =================================================================================================================

## Picks up every landed drop within `radius_m` with Z, walking onto each one. Unlike the driver's
## pickup_all_nearby, the last step is precise: RouteBot stops about 0.75 m short, outside the canonical pickup box
## (formulas/loot_rules.json player_pickup_box_px, 25 px = 0.625 m with WorldScale.actor), so the player then steps
## straight onto the landing point with half-strength input until the drop is inside the box. Returns {"ok" (none
## left in reach), "picked", "records", "refused", "left"}. Await it.
func pickup(radius_m: float = 6.0, max_s: float = 30.0) -> Dictionary:
	# A logged step (as the driver's pickup_all_nearby is): its walks move the player, and the report must show where
	# to (a walk onto a drop below a ledge can end in a pocket).
	var step := d._begin(PlaytestReport.KIND_PLAY, "kit.pickup", "%.1f m" % radius_m)
	var out := {"ok": false, "picked": 0, "records": [], "refused": 0, "left": 0}
	var ls := d.loot()
	var p := d.player()
	if ls == null or p == null:
		d._end(step, false, "no loot system")
		return out
	var from := _local(p.global_position)
	var refused := {}
	var on_picked := func(rec: Dictionary, _res: Dictionary) -> void: (out["records"] as Array).append(rec)
	var on_refused := func(rec: Dictionary, _res: Dictionary) -> void: refused[String(rec.get(LootPickupRules.UID_KEY, ""))] = true
	ls.connect(&"drop_picked_up", on_picked)
	ls.connect(&"pickup_refused", on_refused)
	var t0 := d.game_s()
	var tried := {}
	var in_box := func() -> bool: return not (ls.call("pickup_target", p.global_position, refused) as Dictionary).is_empty()
	while d.game_s() - t0 < max_s and not is_dead():
		await d.get_tree().process_frame
		if bool(in_box.call()):
			await d.input.tap_action(&"pickup")
			await d.frames(2)
			continue
		var best: Node3D = null
		var best_d := radius_m
		var tossing := false
		for n: Node3D in (ls.call("nodes") as Dictionary).values():
			var uid := String(n.get("uid"))
			if refused.has(uid) or int(tried.get(uid, 0)) >= 2:
				continue
			var landing: Vector3 = n.get("landing")
			var dd := Vector2(landing.x - p.global_position.x, landing.z - p.global_position.z).length()
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
		var landing_at: Vector3 = best.get("landing")
		await d.walker.walk_to(landing_at, "to drop %s" % buid, {"max_s": 8.0, "retries": 0, "stop_when": in_box})
		if not bool(in_box.call()):
			await step_onto(landing_at, in_box)
	ls.disconnect(&"drop_picked_up", on_picked)
	ls.disconnect(&"pickup_refused", on_refused)
	var left := 0
	for n: Node3D in (ls.call("nodes") as Dictionary).values():
		var at: Vector3 = n.get("landing")
		if Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length() <= radius_m and not refused.has(String(n.get("uid"))):
			left += 1
	out["picked"] = (out["records"] as Array).size()
	out["refused"] = refused.size()
	out["left"] = left
	out["ok"] = left == 0
	var bag_mesos := 0
	for rec: Dictionary in out["records"]:
		if String(rec.get("kind", "")) == "mesos":
			picked_bags += 1
			bag_mesos += int(rec.get("amount", 0))
		else:
			picked_items += int(rec.get("amount", 1))
	picked_mesos += bag_mesos
	out["mesos"] = bag_mesos
	d._end(step, bool(out["ok"]), "%d picked, %d refused, %d left; map-local %s -> %s" % [int(out["picked"]),
		int(out["refused"]), left, from, _local(p.global_position)])
	return out


## A world point in the current map's frame, rounded to 0.1 m (for step results).
func _local(at: Vector3) -> String:
	var w := d.world()
	if w == null or not w.defs.has_map(d.current_map()):
		return str(at.snappedf(0.1))
	return str(w.defs.get_def(d.current_map()).to_local(at).snappedf(0.1))


## The precise final approach: half-strength steps straight at `landing` for at most a second, until `done` holds
## (the drop is inside the pickup box) or the feet stand within 8 cm of it.
func step_onto(landing: Vector3, done: Callable) -> void:
	var p := d.player()
	var f0 := Engine.get_physics_frames()
	while Engine.get_physics_frames() - f0 < Engine.physics_ticks_per_second:
		if bool(done.call()):
			break
		var to := landing - p.global_position
		to.y = 0.0
		if to.length() < 0.08:
			break
		d.input.set_move_world(to.normalized() * 0.5, p.view_right, p.view_forward)
		await d.get_tree().process_frame
		d.input.reassert()
	d.input.release_movement()
	await d.get_tree().physics_frame
	await d.get_tree().process_frame


# =================================================================================================================
# Hunting
# =================================================================================================================

## The nearest live monster of any of `mob_ids` (any species when empty) within opts "max_dist_m" (60), not in
## opts "exclude" (instance id -> true). null when none.
func nearest_of(mob_ids: Array, opts: Dictionary = {}) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var p := d.player()
	if mob_ids.is_empty():
		return d.nearest_monster(opts)
	for id: Variant in mob_ids:
		var o := opts.duplicate()
		o["mob_id"] = String(id)
		var m := d.nearest_monster(o)
		if m != null and p != null:
			var dd := Vector2(m.global_position.x - p.global_position.x, m.global_position.z - p.global_position.z).length()
			if dd < best_d:
				best_d = dd
				best = m
	return best


## Hunts monsters of `mob_ids` in the current map until cond() holds or opts "max_s" (600) pass, as a player does:
## the survival policy first (drink, rest, fight back what touches), the nearest wanted monster with the attack key,
## the drops picked up precisely after every kill (opts "pickup" true), unspent AP into opts "ap_plan" (["str",
## "dex"]; [] keeps it) through the stats window, a death answered with OK and the walk back (opts "map", default
## the current map), and a tour of the spawn slots when nothing is in sight. Returns {"ok" (cond met), "kills",
## "fights", "deaths", "picked", "time_s", "why"}. Await it.
func hunt(mob_ids: Array, cond: Callable, opts: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "kills": 0, "fights": 0, "deaths": 0, "picked": 0, "time_s": 0.0, "why": ""}
	var map := String(opts.get("map", d.current_map()))
	var t0 := d.game_s()
	var max_s := float(opts.get("max_s", 600.0))
	var exclude := {}
	var idle := 0
	var slot_i := 0
	var ap_plan: Array = opts.get("ap_plan", ["str", "dex"])
	var search := float(opts.get("max_dist_m", 60.0))
	while not bool(cond.call()) and d.game_s() - t0 < max_s:
		if is_dead():
			await respawn()
			out["deaths"] = int(out["deaths"]) + 1
			continue
		if d.current_map() != map:
			if not await travel_to(map, opts):
				out["why"] = "could not get back to %s" % map
				break
			exclude.clear()
			continue
		if d.character().ap > 0 and not ap_plan.is_empty():
			await allocate_ap(ap_plan)
		if hp_frac() < float(opts.get("hp_floor", HP_FLOOR)):
			await survive(opts)
			continue
		# Something that is touching the player is fought first: a wanted species, or any the player can beat.
		var t := threat({"threat_m": 1.6})
		if t != null and not beatable(t) and not mob_ids.has(String(t.get("def").get("id"))):
			t = null
		var target_node := t if t != null else nearest_of(mob_ids, {"max_dist_m": search, "exclude": exclude})
		if target_node == null:
			idle += 1
			if idle % 4 == 0:
				var slots: Array = d.world().defs.get_def(d.current_map()).monster_spawn_definitions
				if not slots.is_empty():
					slot_i = (slot_i + 7) % slots.size()
					await walk_safely("slot:%d" % slot_i, {"max_s": 20.0, "unstick": true})
				exclude.clear()
			else:
				await d.wait(1.0)
			continue
		idle = 0
		# The chosen monster itself (a namesake nearer on the map's plan view can stand on another tier).
		var r: Dictionary = await d.face_and_attack_nearest(20.0, {"target": target_node, "mob_id": String(target_node.get("def").get("id")),
			"max_dist_m": search, "exclude": exclude})
		out["fights"] = int(out["fights"]) + 1
		if bool(r["ok"]):
			out["kills"] = int(out["kills"]) + 1
			if bool(opts.get("pickup", true)) and not is_dead():
				await d.wait(0.6)
				var pk := await pickup(5.0, 10.0)
				out["picked"] = int(out["picked"]) + int(pk["picked"])
		else:
			var why := String(r["why"])
			if (why.begins_with("could not reach") or why.begins_with("still alive")) and is_instance_valid(target_node):
				exclude[target_node.get_instance_id()] = true
		if exclude.size() > 25:
			exclude.clear()
	out["ok"] = bool(cond.call())
	out["time_s"] = snappedf(d.game_s() - t0, 0.1)
	if not bool(out["ok"]) and String(out["why"]) == "":
		out["why"] = "not done after %.0f s" % float(out["time_s"])
	return out


# =================================================================================================================
# Contract helpers: sitting and chairs (C4, C5), skills (C3), Wooden Boxes (C8)
# =================================================================================================================

## PlayerController.activity() (contract C4): still, walking, jumping, climbing, attacking, seated, hitstun, dead,
## other. &"" until the mechanics package builds it.
func activity() -> StringName:
	var p := d.player()
	if p == null or not p.has_method("activity"):
		return &""
	return StringName(p.call("activity"))


## Sits down with the sit key (X), which sits on the first chair the character owns (C5, an adaptation). The player
## must be grounded, still, alive and without a modal window. Returns {"ok" (seated), "activity", "why"}. Await it.
func sit() -> Dictionary:
	if not d.player().has_method("activity"):
		return {"ok": false, "activity": "", "why": "PlayerController.activity() (contract C4) is not built"}
	d.input.release_movement()
	await d.wait(0.2)
	await d.tap(&"sit")
	var ok := await d.wait_until(func() -> bool: return activity() == &"seated", 1.0)
	return {"ok": ok, "activity": String(activity()), "why": "" if ok else "the sit key did not seat the player (%s)" % activity()}


## Stands up the way C5 says any movement does: a short step. Returns {"ok" (no longer seated), "activity"}. Await it.
func stand() -> Dictionary:
	await d.press(&"move_left", 0.1)
	await d.wait(0.1)
	return {"ok": activity() != &"seated", "activity": String(activity())}


## Sits on a chair item (a Setup item with setup data, C5) by double-clicking it in the Item window's Set-up tab.
## Returns {"ok" (seated), "activity", "why"}. Await it.
func use_chair(item_id: String) -> Dictionary:
	if not d.player().has_method("activity"):
		return {"ok": false, "activity": "", "why": "PlayerController.activity() (contract C4) is not built"}
	if d.character().inventory.count(item_id) <= 0:
		return {"ok": false, "activity": String(activity()), "why": "%s is not held" % item_id}
	d.input.release_movement()
	await d.wait(0.2)
	var idx := await _open_on_item(item_id)
	var win := inventory_window()
	if idx < 0 or idx >= win.slots.size():
		await d.close_window("inventory")
		return {"ok": false, "activity": String(activity()), "why": "no slot for %s" % item_id}
	await double_click(win.slots[idx])
	await d.frames(2)
	var status := win.status_label.text
	await d.close_window("inventory")
	var ok := await d.wait_until(func() -> bool: return activity() == &"seated", 1.0)
	return {"ok": ok, "activity": String(activity()), "why": "" if ok else "not seated (status '%s')" % status}


## The quickslot key a skill is bound to (contract C3: quickslots {key: {"kind": "skill", "id"}}), "" when none.
func skill_key(skill_id: String) -> String:
	return quickslot_key(d.character().quickslots, "skill", skill_id)


## Casts a Beginner skill with its quickslot key (contract C3; the skills package binds skills to quickslots). The
## cast is judged by what C3 persists: a cooldown entry for the skill, an effect whose source is "skill:<id>", or
## the player's activity becoming attacking. Returns {"ok", "key", "why", "cooldown", "effect"}. Await it.
func cast_skill(skill_id: String) -> Dictionary:
	var c := d.character()
	var key := skill_key(skill_id)
	if key == "":
		return {"ok": false, "key": "", "why": "skill %s is on no quickslot (C3 {\"kind\": \"skill\"})" % skill_id}
	var cd0 := _cooldown(skill_id)
	await d.tap(StringName("quickslot_%s" % key))
	var cast := await d.wait_until(func() -> bool:
		return _cooldown(skill_id) > cd0 or _has_effect(skill_id) or activity() == &"attacking", 1.0)
	return {"ok": cast, "key": key, "why": "" if cast else "no cooldown, effect or attack after the key",
		"cooldown": _cooldown(skill_id), "effect": _has_effect(skill_id), "sp": c.sp}


## The Skills window (K), or null.
func skills_window() -> Node:
	return d.windows().call("window_by_name", "skills") if d.windows() != null and d.windows().has_method("window_by_name") else null


## Spends one SP on a skill with the mouse: K opens the Skills window, a click on the skill's "+" (test_skills' way).
## Returns {"ok" (the level rose by one), "level0", "level1", "sp0", "sp1", "why"}. Await it.
func learn_skill(skill_id: String) -> Dictionary:
	var c := d.character()
	var lv0 := SkillBook.level_of(c, skill_id)
	var out := {"ok": false, "level0": lv0, "level1": lv0, "sp0": c.sp, "sp1": c.sp, "why": ""}
	if not await d.open_window("skills"):
		out["why"] = "K did not open the Skills window"
		return out
	var w := skills_window()
	var plus: Variant = (w.get("plus_buttons") as Dictionary).get(skill_id) if w != null else null
	if not (plus is Button):
		out["why"] = "no '+' for %s in the Skills window" % skill_id
		await d.close_window("skills")
		return out
	await d.click(plus as Button)
	await d.frames(2)
	out["level1"] = SkillBook.level_of(c, skill_id)
	out["sp1"] = c.sp
	out["ok"] = int(out["level1"]) == lv0 + 1 and c.sp == int(out["sp0"]) - 1
	if not bool(out["ok"]):
		out["why"] = "'+' did not raise the level (status: %s)" % d.window_text("skills").left(160).replace("\n", " | ")
	await d.close_window("skills")
	return out


## Puts a learned skill on a quickslot key with the Skills window's Set key picker (K, the skill's row, Set key, the
## key). Returns {"ok" (bound), "key", "why"}. Await it.
func bind_skill(skill_id: String, key: String) -> Dictionary:
	var c := d.character()
	if not await d.open_window("skills"):
		return {"ok": false, "key": key, "why": "K did not open the Skills window"}
	var w := skills_window()
	var row: Variant = (w.get("rows") as Dictionary).get(skill_id) if w != null else null
	if not (row is Dictionary):
		await d.close_window("skills")
		return {"ok": false, "key": key, "why": "no row for %s" % skill_id}
	await d.click((row as Dictionary)["panel"])
	await d.click(w.get("key_button"))
	var kb: Variant = (w.get("key_buttons") as Dictionary).get(key)
	if kb is Button:
		await d.click(kb as Button)
	await d.frames(2)
	await d.close_window("skills")
	var ok := MisoQuickslots.skill_for(c, key) == skill_id
	return {"ok": ok, "key": key, "why": "" if ok else "key %s holds %s" % [key, str(c.quickslots.get(key))]}


## Throws Three Snails (the skill's quickslot key) at `target` from inside its canonical band (THROW_FROM_PX), as
## test_skills does: walks to about 150 px from it, faces it and taps the key once per throw until opts "casts" (1)
## throws resolved on it, the target died, or opts "max_s" (40) passed. Every hit is heard on PlayerSkills.cast_resolved.
## `target` may also be a Wooden Box (a node of breakables(), contract C8): a throw that picks it is heard as
## cast_resolved(skill, box, null) and lands one hit (breakables.json hit_rule), and "killed" means it broke.
## Returns {"ok" (a throw hit it), "casts", "hits", "damage" [final; empty for a box], "killed", "mp0", "mp1",
## "shells0", "shells1", "why"}. Await it.
func throw_at(target: Node3D, opts: Dictionary = {}) -> Dictionary:
	var snails := "0001000"
	var c := d.character()
	var p := d.player()
	var key := skill_key(snails)
	var def := SkillDef.of(snails, db)
	var shell := String(def.item_cost(maxi(1, SkillBook.level_of(c, snails)))["item_id"]) if def != null else ""
	var out := {"ok": false, "casts": 0, "hits": 0, "damage": [], "killed": false, "mp0": c.mp, "mp1": c.mp,
		"shells0": c.inventory.count(shell), "shells1": 0, "why": ""}
	if key == "" or target == null or not is_instance_valid(target):
		out["why"] = "Three Snails is on no quickslot" if key == "" else "no target"
		return out
	var skills: Node = p.get_node_or_null(^"PlayerSkills")
	if skills == null:
		out["why"] = "the player has no PlayerSkills node"
		return out
	var box := target.is_in_group(&"miso_breakables")
	var died := [false]
	var on_died := func(m: Node) -> void:
		if m == target:
			died[0] = true
	d.monsters().connect(&"monster_died", on_died)
	var hits := [0]
	var damage: Array = []
	var on_cast := func(sid: String, t: Node, res: DamageResult) -> void:
		if sid != snails or t != target:
			return
		if box and res == null:
			hits[0] += 1
		elif res != null and not res.missed:
			hits[0] += 1
			damage.append(res.final)
	skills.connect(&"cast_resolved", on_cast)
	var casts0 := int(skills.get("casts"))
	var want := int(opts.get("casts", 1))
	var ideal := WorldScale.actor(THROW_FROM_PX)
	var t0 := d.game_s()
	var stuck := 0
	while not died[0] and int(skills.get("casts")) - casts0 < want and d.game_s() - t0 < float(opts.get("max_s", 40.0)):
		await d.get_tree().process_frame
		d.input.reassert()
		if not is_instance_valid(target) or is_dead():
			break
		var gone := bool(target.call("is_broken")) if box else not bool(target.call("is_alive"))
		if gone:
			break
		var to := target.global_position - p.global_position
		var dy := to.y
		to.y = 0.0
		var dist := to.length()
		if dist > 6.0 or absf(dy) > 1.0:
			d.input.release_movement()
			if stuck >= 3:
				out["why"] = "no way to it from here (%.1f m away, %.1f m up/down)" % [dist, dy]
				break
			var tgt := target
			var wr: Dictionary = await d.walk_to(d.walker.grounded(target.global_position), {"max_s": 6.0, "within_m": ideal,
				"stop_when": func() -> bool: return not is_instance_valid(tgt) or (_flat_m(tgt.global_position, p.global_position) <= ideal
					and absf(tgt.global_position.y - p.global_position.y) <= 1.0)})
			stuck = stuck + 1 if float(wr.get("distance_m", 0.0)) < 0.2 else 0
			continue
		var dir := to.normalized() if dist > 0.01 else p.facing
		if dist > ideal + 1.0:
			d.input.set_move_world(dir, p.view_right, p.view_forward)
			continue
		if dist < ideal - 1.5:
			d.input.set_move_world(-dir, p.view_right, p.view_forward)
			continue
		d.input.release_movement()
		if p.facing.dot(dir) < cos(deg_to_rad(12.0)):
			d.input.set_move_world(dir * 0.2, p.view_right, p.view_forward)
			await d.get_tree().physics_frame
			await d.get_tree().process_frame
			d.input.release_movement()
			continue
		if not p.is_grounded() or bool(d.combat().call("is_attacking")):
			continue
		await d.tap(StringName("quickslot_%s" % key))
		await d.wait(0.1)
	d.input.release_movement()
	if d.monsters().is_connected(&"monster_died", on_died):
		d.monsters().disconnect(&"monster_died", on_died)
	skills.disconnect(&"cast_resolved", on_cast)
	out["casts"] = int(skills.get("casts")) - casts0
	out["hits"] = hits[0]
	out["damage"] = damage
	out["killed"] = died[0] or (box and is_instance_valid(target) and bool(target.call("is_broken")))
	out["mp1"] = c.mp
	out["shells1"] = c.inventory.count(shell)
	out["ok"] = hits[0] > 0
	if not bool(out["ok"]) and String(out["why"]) == "":
		out["why"] = "no throw hit it in %.0f s (%d casts)" % [d.game_s() - t0, int(out["casts"])]
	return out


## Lets monsters win, the way a player who stops defending dies: walks into the nearest live monster of `mob_ids`
## (any species when empty) again and again with real input, never attacking, never drinking, until the player dies
## or opts "max_s" (300) pass. No game state is touched: every hit is the monster's contact damage. Returns {"ok"
## (died), "touches", "damage", "map", "pos", "time_s", "why"}. Await it.
func let_monsters_win(mob_ids: Array, opts: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "touches": 0, "damage": 0, "map": d.current_map(), "pos": local_pos(), "time_s": 0.0, "why": ""}
	var t0 := d.game_s()
	var tc0 := touches.size()
	var dmg0 := damage_taken
	var p := d.player()
	var skip := {}
	while not is_dead() and d.game_s() - t0 < float(opts.get("max_s", 300.0)):
		var m := same_tier_monster(mob_ids, skip)
		if m == null:
			skip.clear()
			await d.wait(1.0)
			continue
		var tgt := m
		var since := last_touch_s
		# The planned walk ends about 0.75 m short (RouteBot's arrival), so the last step is straight at the monster's
		# live position with real input until it touches the player (or 3 s pass).
		await d.walk_to(d.walker.grounded(m.global_position), {"max_s": 6.0, "retries": 0, "within_m": 1.2,
			"stop_when": func() -> bool: return is_dead() or last_touch_s > since or not is_instance_valid(tgt)})
		var f0 := Engine.get_physics_frames()
		while is_instance_valid(tgt) and bool(tgt.call("is_alive")) and not is_dead() and last_touch_s <= since \
				and Engine.get_physics_frames() - f0 < 3 * Engine.physics_ticks_per_second:
			var to := tgt.global_position - p.global_position
			to.y = 0.0
			if to.length() > 4.0:
				break
			d.input.set_move_world(to.normalized() if to.length() > 0.05 else p.facing, p.view_right, p.view_forward)
			await d.get_tree().process_frame
			d.input.reassert()
		d.input.release_movement()
		if last_touch_s <= since and is_instance_valid(tgt):
			skip[tgt.get_instance_id()] = true
		await d.wait(0.2)
	out["ok"] = is_dead()
	out["touches"] = touches.size() - tc0
	out["damage"] = damage_taken - dmg0
	out["pos"] = local_pos()
	out["time_s"] = snappedf(d.game_s() - t0, 0.1)
	if not bool(out["ok"]):
		out["why"] = "still alive after %.0f s (%d touches, %d damage)" % [float(out["time_s"]), int(out["touches"]), int(out["damage"])]
	return out


## The nearest live monster of `mob_ids` (any species when empty) on the player's tier (within 1 m of height), not in
## `skip` (instance id -> true); null when none.
func same_tier_monster(mob_ids: Array, skip: Dictionary) -> Node3D:
	var p := d.player()
	var ms := d.monsters()
	if p == null or ms == null:
		return null
	var best: Node3D = null
	var best_d := 40.0
	for m: Node3D in ms.call("live_monsters"):
		if not is_instance_valid(m) or not bool(m.call("is_alive")) or skip.has(m.get_instance_id()):
			continue
		if not mob_ids.is_empty() and not mob_ids.has(String(m.get("def").get("id"))):
			continue
		if absf(m.global_position.y - p.global_position.y) > 1.0:
			continue
		var dd := _flat_m(m.global_position, p.global_position)
		if dd < best_d:
			best_d = dd
			best = m
	return best


func _cooldown(skill_id: String) -> float:
	var cds: Variant = d.character().get("cooldowns")
	return float((cds as Dictionary).get(skill_id, 0.0)) if cds is Dictionary else 0.0


func _has_effect(skill_id: String) -> bool:
	var fx: Variant = d.character().get("effects")
	if not (fx is Array):
		return false
	for e: Variant in fx:
		if e is Dictionary and String((e as Dictionary).get("source", "")) == "skill:" + skill_id:
			return true
	return false


## The Wooden Boxes of the current map (contract C8: nodes in group &"miso_breakables" with placement_key(),
## is_broken() and hits_left()), nearest first. [] until the breakables package builds them.
func breakables(include_broken: bool = false) -> Array:
	var out: Array = []
	var p := d.player()
	if p == null:
		return out
	for n in d.get_tree().get_nodes_in_group(&"miso_breakables"):
		if not (n is Node3D) or not is_instance_valid(n) or not (n as Node3D).is_inside_tree():
			continue
		if not n.has_method("is_broken") or not n.has_method("hits_left"):
			continue
		if not include_broken and bool(n.call("is_broken")):
			continue
		var key := String(n.call("placement_key")) if n.has_method("placement_key") else ""
		if key != "" and key.contains(":") and not key.begins_with(d.current_map()):
			continue
		out.append(n)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(p.global_position) < b.global_position.distance_to(p.global_position))
	return out


## Breaks a Wooden Box (C8: it breaks after hits_to_break landed hits and drops through DropRoller), the way test_box
## proved on every Amherst box: walks to a spot beside it on the box's own ground (approach spots in BOX_APPROACH_DIRS
## directions at BOX_REACH_SHARE of the weapon's reach, within BOX_APPROACH_DY_M of the box's feet, the body
## fitting; the survival policy on the way), steps back out of a box it stands in, faces it, presses the attack key,
## and stands closer after BOX_WHIFF_RUN whiffs in a row; then picks up what it dropped. A walk that ends beside the
## box but on another tier (a ledge, a prop top) is not attacked from: the next approach spot is tried, at most
## BOX_SPOTS, each with the next planner of BOX_PLANNERS. `box`: a node from breakables(), or null for the nearest
## unbroken one; then a box the player cannot stand beside (on the far side of a terrace from where the walks start)
## is passed over for the next nearest, at most BOX_CANDIDATES (the result lists them in "passed_over"). Returns
## {"ok" (broken), "key", "hits" (hits_left() steps seen), "attacks", "whiffs", "picked", "spots", "why", "pos" (box,
## map-local), "passed_over"}. Await it.
func break_box(box: Node3D = null, opts: Dictionary = {}) -> Dictionary:
	if box != null:
		return await _break_one(box, opts)
	var all := breakables()
	if all.is_empty():
		return {"ok": false, "key": "", "hits": 0, "attacks": 0, "whiffs": 0, "picked": 0, "spots": 0, "pos": "", "passed_over": [],
			"why": "no unbroken Wooden Box in %s (group miso_breakables, contract C8)" % d.current_map()}
	var passed: Array = []
	var r: Dictionary = {}
	for cand: Node3D in all.slice(0, BOX_CANDIDATES):
		if not is_instance_valid(cand) or bool(cand.call("is_broken")):
			continue
		r = await _break_one(cand, opts)
		if bool(r["ok"]) or not String(r["why"]).begins_with("could not stand"):
			break
		passed.append("%s: %s" % [r["key"], r["why"]])
	r["passed_over"] = passed
	return r


func _break_one(box: Node3D, opts: Dictionary) -> Dictionary:
	var out := {"ok": false, "key": "", "hits": 0, "attacks": 0, "whiffs": 0, "picked": 0, "spots": 0, "why": "", "pos": ""}
	out["key"] = String(box.call("placement_key")) if box.has_method("placement_key") else ""
	out["pos"] = _local(box.global_position)
	var p := d.player()
	var pc := d.combat()
	var stand := float(opts.get("reach_m", box_reach_m() * BOX_REACH_SHARE))
	var spots: Array = []
	var tried := 0
	var whiff_run := 0
	var t0 := d.game_s()
	var last_left := int(box.call("hits_left"))
	while is_instance_valid(box) and not bool(box.call("is_broken")) and d.game_s() - t0 < float(opts.get("max_s", 60.0)):
		if is_dead():
			out["why"] = "the player died"
			break
		await d.get_tree().process_frame
		d.input.reassert()
		var to := box.global_position - p.global_position
		var dy := absf(to.y)
		to.y = 0.0
		var dist := to.length()
		if dist > 2.5 or dy > BOX_ATTACK_DY_M:
			if tried == 0:
				spots = box_spots(box, stand)
			if tried >= mini(BOX_SPOTS, spots.size()):
				out["why"] = "could not stand beside the box (%.1f m away, %.1f m up/down after %d approach spots)" % [dist, dy, tried]
				break
			var spot: Vector3 = spots[tried]
			tried += 1
			d.input.release_movement()
			await walk_safely(spot, {"within_m": 0.35, "max_s": 40.0, "retries": 1,
				"planner": BOX_PLANNERS[(tried - 1) % BOX_PLANNERS.size()]})
			continue
		if dist > stand + 0.2:
			d.input.set_move_world(to.normalized(), p.view_right, p.view_forward)
			continue
		if dist < 0.25:
			# Standing in the (walk-through) box: step back out of it.
			d.input.set_move_world(-p.facing, p.view_right, p.view_forward)
			continue
		d.input.release_movement()
		var dir := to.normalized()
		if p.facing.dot(dir) < cos(deg_to_rad(15.0)):
			d.input.set_move_world(dir * 0.2, p.view_right, p.view_forward)
			await d.get_tree().physics_frame
			await d.get_tree().process_frame
			d.input.release_movement()
			continue
		if pc == null or not bool(pc.call("can_attack")):
			continue
		var swings := int(pc.get("attacks"))
		await d.input.tap_action(&"attack")
		if int(pc.get("attacks")) == swings:
			continue
		out["attacks"] = int(out["attacks"]) + 1
		await d.frames(1)
		var left := int(box.call("hits_left")) if is_instance_valid(box) else 0
		if left < last_left or (is_instance_valid(box) and bool(box.call("is_broken"))):
			out["hits"] = int(out["hits"]) + maxi(1, last_left - left)
			last_left = left
			whiff_run = 0
		else:
			out["whiffs"] = int(out["whiffs"]) + 1
			whiff_run += 1
			if whiff_run >= BOX_WHIFF_RUN:
				stand = maxf(0.4, stand * 0.8)
				whiff_run = 0
	d.input.release_movement()
	out["spots"] = tried
	out["ok"] = is_instance_valid(box) and bool(box.call("is_broken"))
	if bool(out["ok"]):
		await d.wait(0.8)
		var pk := await pickup(4.0, 10.0)
		out["picked"] = int(pk["picked"])
	elif String(out["why"]) == "":
		out["why"] = "not broken after %d attacks (%d whiffs), %.0f s" % [int(out["attacks"]), int(out["whiffs"]), d.game_s() - t0]
	return out


## How far (m) the equipped weapon's ordinary attack reaches a box: the nearest far edge of its canonical attack boxes
## (CombatReach) plus half the box's touch width (misostory/breakables.json), at actor scale (test_box's rule).
func box_reach_m() -> float:
	var c := d.character()
	var stats := PlayerCombatStats.from_character(c, db)
	var weapon := stats.weapon if stats.weapon != null else WeaponProfile.bare_hands(db)
	var far := INF
	for action: Variant in weapon.ordinary_actions().keys():
		for pres in weapon.presentations_for(String(action)):
			far = minf(far, CombatReach.attack_box_px(weapon, pres, true, c.level).end.x)
	return WorldScale.actor((0.0 if far == INF else far) + BreakableRules.touch_px(db).x * 0.5)


## Spots `stand` m around `box` in BOX_APPROACH_DIRS directions whose ground is the box's own (within
## BOX_APPROACH_DY_M) and where the body fits, nearest to the player first.
func box_spots(box: Node3D, stand: float) -> Array:
	var p := d.player()
	var feet := box.global_position
	var away := p.global_position - feet
	away.y = 0.0
	var base := away.normalized() if away.length() > 0.01 else Vector3.BACK
	var out: Array = []
	for k in BOX_APPROACH_DIRS:
		var spot: Vector3 = d.walker.grounded(feet + base.rotated(Vector3.UP, TAU * k / BOX_APPROACH_DIRS) * stand)
		if absf(spot.y - feet.y) <= BOX_APPROACH_DY_M and d.walker.standable(spot):
			out.append(spot)
	var from := p.global_position
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(from) < b.distance_to(from))
	if out.is_empty():
		out.append(d.walker.grounded(feet + base * stand))
	return out
