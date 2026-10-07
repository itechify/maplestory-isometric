class_name PlaytestLedger
extends RefCounted
## The strict mode's bookkeeping (docs/runtime/PLAYTEST_HARNESS.md "Strict mode"): from a baseline on, it listens to
## the game's own event bus and, when asked, reconciles the live character against what the bus announced:
##
##   EXP      total EXP (every level below plus the bar) - baseline == the sum of Events.exp_gained
##            (monster kills, quest rewards, the death penalty's negative award)
##   mesos    mesos - baseline == the sum of Events.mesos_changed deltas (pickups, shops, quest rewards)
##   items    per item, inventory + equipment - baseline == item_gained - item_lost (pickups, shops, quest hand-ins and
##            rewards, use; equipping moves an item between the two and changes neither)
##   quests   every quest whose status changed has a quest_started / quest_completed / quest_forfeited for its new
##            status
##   level    level - baseline == the leveled_up events, and the level is the last one announced
##   AP and   AP + the base stats - baseline == the AP the announced level-ups grant (Progression.level_up_gains): the
##   stats    AP a stat gained was spent, no stat fell, only allocatable stats (beginner.json) rose, and AP and the
##            stats are what they were at the last Events.stats_changed (the AP spend announces one)
##   SP and   SP - baseline == the level-ups' SP - one per skill_leveled; every skill's level is the last one its
##   skills   skill_leveled announced, one event per level
##   Max HP/MP  base Max HP and MP - baseline == the level-ups' gains
##   HP, MP   step by step: every hp_changed / mp_changed must be explained by what the bus said since the one before
##            (player_damaged: down by the damage, never below 0; item_used: up by the item's canonical restore, never
##            above the max; leveled_up: the level-up heal of combat.json; player_died: death.json's respawn vitals;
##            equipment_changed: down to a smaller max; skill_used, heard right after its mp_changed: down by the
##            skill's canonical MP cost), or, for an HP rise with no cause, be one recovery tick (recovery.json's
##            natural tick, the bonus of the chair a player_sat_down named, a tick of a heal-over-time effect such as
##            Recovery: EffectBook.heal_for_tick; less only when it fills HP). The live HP and MP must be the last
##            announced ones (the death's respawn vitals while a death is pending)
##
## A change that no event explains (a scenario writing c.mesos or c.ap, adding to the inventory, completing a quest or
## healing behind the game's back) is a mismatch, and a mismatch fails a strict run. Console commands are counted
## separately (DebugTools.commands_run); a scenario calling a game service directly is caught by the api step kind and
## by the static test of the harness files and the strict scenarios (test_playtest_strict.gd), and so is a teleport:
## the ledger does not follow the player's position.

const VITALS: Array[String] = ["hp", "mp"]

var _bus: Node = null
var _db: ContentDB = null
var _c: CharacterState = null
var _exp0: int = 0
var _mesos0: int = 0
var _items0: Dictionary = {}
var _quests0: Dictionary = {}
var _level0: int = 1
var _ap0: int = 0
var _sp0: int = 0
var _stats0: Dictionary = {}
var _skills0: Dictionary = {}
var _max0: Dictionary = {}
var exp_sum: int = 0
var mesos_sum: int = 0
## item id -> gained - lost
var item_delta: Dictionary = {}
## quest id -> the status its last event announced
var quest_last: Dictionary = {}
## The levels Events.leveled_up announced, in order.
var levels: Array[int] = []
## skill id -> the levels Events.skill_leveled announced for it, in order.
var skill_levels: Dictionary = {}
## {"ap", "stats"} when Events.stats_changed was last heard (the baseline until then).
var _stats_seen: Dictionary = {}
## "hp" / "mp" -> {"seen" (the last announced value), "max", "damage", "items", "level_up", "equip", "died",
## "owed" (an MP drop waiting for the skill_used that paid it)}.
var _vital: Dictionary = {}
## HP and MP steps no event explained (judged as they were announced, returned by reconcile()).
var step_mismatches: PackedStringArray = []
## The chair the player sits on (Events.player_sat_down; "" standing).
var _chair: String = ""
## Heal-over-time effects active since the last HP announcement: effect id -> {"total", "n"}.
var _heals: Dictionary = {}
var _natural_tick: int = 0
var _level_up_heals: bool = false
var _respawn: Dictionary = {}
## Events heard since the baseline (for the report).
var heard: int = 0
## HP and MP announcements explained, by cause (for the report).
var vital_steps: Dictionary = {}
var armed: bool = false


## Starts (or restarts) the ledger on `character` now: the baseline is the character as it is, and every later
## event counts.
func baseline(bus: Node, character: CharacterState, db: ContentDB) -> void:
	disarm()
	_bus = bus
	_db = db
	_c = character
	if _bus == null or _c == null or _db == null:
		return
	_exp0 = total_exp(_c, _db)
	_mesos0 = _c.mesos
	_items0 = holdings(_c)
	_quests0 = statuses(_c)
	_level0 = _c.level
	_ap0 = _c.ap
	_sp0 = _c.sp
	_stats0 = base_stats(_c)
	_skills0 = _c.skills.duplicate()
	_max0 = {"hp": _c.base_max_hp, "mp": _c.base_max_mp}
	exp_sum = 0
	mesos_sum = 0
	item_delta = {}
	quest_last = {}
	levels = []
	skill_levels = {}
	_stats_seen = {"ap": _c.ap, "stats": base_stats(_c)}
	_vital = {}
	for v in VITALS:
		_vital[v] = {"seen": _now(_c, v), "max": _max_now(_c, v), "owed": {}}
		_clear_causes(v)
	step_mismatches = []
	_chair = ""
	_heals = {}
	_scan_heals()
	var rule := NaturalRecoveryRule.from_db(_db)
	_natural_tick = rule.hp_per_tick if rule != null else 0
	_level_up_heals = String(CombatRules.of(_db).adaptation("level_up").get("heal", "")) == "full"
	_respawn = DeathRules.from_db(_db).respawn_vitals()
	heard = 0
	vital_steps = {}
	for pair in _signals():
		_bus.connect(pair[0], pair[1])
	armed = true


func disarm() -> void:
	if _bus != null and is_instance_valid(_bus):
		for pair in _signals():
			if _bus.is_connected(pair[0], pair[1]):
				_bus.disconnect(pair[0], pair[1])
	armed = false


func _signals() -> Array:
	return [[&"exp_gained", _on_exp], [&"mesos_changed", _on_mesos], [&"item_gained", _on_gained],
		[&"item_lost", _on_lost], [&"quest_started", _on_started], [&"quest_completed", _on_completed],
		[&"quest_forfeited", _on_forfeited], [&"leveled_up", _on_leveled], [&"stats_changed", _on_stats],
		[&"skill_leveled", _on_skill_leveled], [&"skill_used", _on_skill_used], [&"effects_changed", _on_effects],
		[&"hp_changed", _on_hp], [&"mp_changed", _on_mp], [&"player_damaged", _on_damaged], [&"item_used", _on_item_used],
		[&"equipment_changed", _on_equipment], [&"player_died", _on_died], [&"player_sat_down", _on_sat],
		[&"player_stood_up", _on_stood]]


## The mismatches between the live character and the events heard since the baseline ([] when every change is
## explained). `character` is the live one (a Continue or a new game replaces the object: rebaseline then).
func reconcile(character: CharacterState = null) -> PackedStringArray:
	var out := PackedStringArray()
	var c := character if character != null else _c
	if not armed or c == null or _db == null:
		return out
	var dexp := total_exp(c, _db) - _exp0
	if dexp != exp_sum:
		out.append("EXP changed by %+d, the bus announced %+d" % [dexp, exp_sum])
	var dmesos := c.mesos - _mesos0
	if dmesos != mesos_sum:
		out.append("mesos changed by %+d, the bus announced %+d" % [dmesos, mesos_sum])
	var now := holdings(c)
	var ids := {}
	for id: String in now:
		ids[id] = true
	for id: String in _items0:
		ids[id] = true
	for id: String in item_delta:
		ids[id] = true
	for id: String in ids:
		var d := int(now.get(id, 0)) - int(_items0.get(id, 0))
		if d != int(item_delta.get(id, 0)):
			out.append("item %s changed by %+d, the bus announced %+d" % [id, d, int(item_delta.get(id, 0))])
	var st := statuses(c)
	var qids := {}
	for q: String in st:
		qids[q] = true
	for q: String in _quests0:
		qids[q] = true
	for q: String in qids:
		var a := String(_quests0.get(q, QuestLog.NOT_STARTED))
		var b := String(st.get(q, QuestLog.NOT_STARTED))
		if a != b and String(quest_last.get(q, "")) != b:
			out.append("quest %s went %s -> %s with no event for it (last event: %s)" % [q, a, b, quest_last.get(q, "none")])
	out.append_array(_reconcile_growth(c))
	out.append_array(_reconcile_vitals(c))
	return out


## What the ledger saw, for the report: {"heard", "exp", "mesos", "items", "levels", "skills", "vital_steps"}.
func summary() -> Dictionary:
	return {"heard": heard, "exp": exp_sum, "mesos": mesos_sum, "items": item_delta.duplicate(), "levels": levels.duplicate(),
		"skills": skill_levels.duplicate(true), "vital_steps": vital_steps.duplicate()}


## EXP from level 1 at 0 EXP: the EXP to next level of every level below plus the bar.
static func total_exp(c: CharacterState, db: ContentDB) -> int:
	var t := c.exp
	for l in range(1, c.level):
		t += Progression.exp_to_next(l, db)
	return t


## item id -> count over the inventory and the equipped pieces.
static func holdings(c: CharacterState) -> Dictionary:
	var out := {}
	for tab in Inventory.TABS:
		for i in c.inventory.capacity(tab):
			var s := c.inventory.get_slot(tab, i)
			if not s.is_empty():
				var id := String(s.get("item_id", ""))
				out[id] = int(out.get(id, 0)) + int(s.get("qty", 1))
	var eq := c.equipment.equipped()
	for slot: Variant in eq:
		var id := String(eq[slot])
		if id != "":
			out[id] = int(out.get(id, 0)) + 1
	return out


## quest id -> status for every quest the log knows.
static func statuses(c: CharacterState) -> Dictionary:
	var out := {}
	for q in c.quests.active_ids():
		out[String(q)] = QuestLog.IN_PROGRESS
	for q in c.quests.completed_ids():
		out[String(q)] = QuestLog.COMPLETED
	return out


## stat key -> base value (CharacterState.STAT_KEYS and any other key the character holds).
static func base_stats(c: CharacterState) -> Dictionary:
	var out := {}
	for k in CharacterState.STAT_KEYS:
		out[k] = c.get_base_stat(k)
	for k: Variant in c.base_stats:
		out[String(k)] = c.get_base_stat(String(k))
	return out


# --- level, AP, stats, SP, skills, base Max HP/MP -------------------------------------------------------------

func _reconcile_growth(c: CharacterState) -> PackedStringArray:
	var out := PackedStringArray()
	if c.level - _level0 != levels.size() or (not levels.is_empty() and levels.back() != c.level):
		out.append("level went %d -> %d, the bus announced level-ups %s" % [_level0, c.level, levels])
	var gains := {"ap": 0, "sp": 0, "max_hp": 0, "max_mp": 0}
	for lv in levels:
		var g := Progression.level_up_gains(c.job, lv, _db)
		for k: String in gains:
			gains[k] = int(gains[k]) + int(g.get(k, 0))
	var stats := base_stats(c)
	var allowed := PackedStringArray((_db.formula("beginner").get("ap", {}) as Dictionary).get("allocatable_stats", []))
	var spent := 0
	for k: String in stats:
		var d := int(stats[k]) - int(_stats0.get(k, 0))
		spent += d
		if d < 0:
			out.append("base %s fell %d -> %d (AP is never taken back)" % [k.to_upper(), int(_stats0.get(k, 0)), int(stats[k])])
		elif d > 0 and not allowed.has(k):
			out.append("base %s rose %+d, but AP may only go into %s" % [k.to_upper(), d, ", ".join(allowed)])
	if (c.ap - _ap0) + spent != int(gains["ap"]):
		out.append("AP changed by %+d and the base stats by %+d, but the announced level-ups %s grant %d AP"
			% [c.ap - _ap0, spent, levels, int(gains["ap"])])
	if c.ap != int(_stats_seen["ap"]) or _stats_seen["stats"] != stats:
		out.append("AP or a base stat changed after the last stats_changed: AP %d -> %d, stats %s -> %s"
			% [int(_stats_seen["ap"]), c.ap, _stats_seen["stats"], stats])
	var learned := 0
	var sids := {}
	for id: Variant in c.skills:
		sids[String(id)] = true
	for id: Variant in _skills0:
		sids[String(id)] = true
	for id: String in skill_levels:
		sids[id] = true
	for id: String in sids:
		var a := int(_skills0.get(id, 0))
		var b := int(c.skills.get(id, 0))
		var said: Array = skill_levels.get(id, [])
		learned += said.size()
		if b - a != said.size() or (not said.is_empty() and int(said.back()) != b):
			out.append("skill %s went level %d -> %d, the bus announced %s" % [id, a, b, said])
	if c.sp - _sp0 != int(gains["sp"]) - learned:
		out.append("SP changed by %+d, but the announced level-ups grant %d SP and %d skill levels were bought"
			% [c.sp - _sp0, int(gains["sp"]), learned])
	for v in VITALS:
		var cur := c.base_max_hp if v == "hp" else c.base_max_mp
		if cur - int(_max0[v]) != int(gains["max_" + v]):
			out.append("base Max %s changed by %+d, the announced level-ups grant %+d" % [v.to_upper(), cur - int(_max0[v]),
				int(gains["max_" + v])])
	return out


# --- HP and MP ------------------------------------------------------------------------------------------------

func _reconcile_vitals(c: CharacterState) -> PackedStringArray:
	var out := PackedStringArray(step_mismatches)
	for v in VITALS:
		var s: Dictionary = _vital[v]
		if not (s["owed"] as Dictionary).is_empty():
			out.append(_owed_text(v, s["owed"]))
		var live := _now(c, v)
		if live == int(s["seen"]):
			continue
		if bool(s["died"]) and live == _respawn_value(v, int(s["seen"]), _max_now(c, v)):
			continue
		out.append("%s is %d, the bus last announced %d (nothing announced the change)" % [v.to_upper(), live, int(s["seen"])])
	return out


## One announcement of a vital: the step from the last announced value must have a cause.
func _step(v: String, value: int, mx: int) -> void:
	var s: Dictionary = _vital[v]
	if not (s["owed"] as Dictionary).is_empty():
		step_mismatches.append(_owed_text(v, s["owed"]))
		s["owed"] = {}
	var from := int(s["seen"])
	var cause := _explain(v, from, value, mx, s)
	if cause != "":
		vital_steps[cause] = int(vital_steps.get(cause, 0)) + 1
	elif v == "mp" and value < from:
		# PlayerSkills pays the MP and then announces skill_used: the cast that explains this drop comes next.
		s["owed"] = {"from": from, "to": value, "max": mx}
	else:
		step_mismatches.append("%s went %d -> %d (max %d) with nothing to explain it (heard since the last announcement: %s)"
			% [v.to_upper(), from, value, mx, _causes_text(v, s)])
	s["seen"] = value
	s["max"] = mx
	_clear_causes(v)
	if v == "hp":
		_prune_heals()


## The cause of a step ("" when nothing heard explains it).
func _explain(v: String, from: int, to: int, mx: int, s: Dictionary) -> String:
	if to == from:
		return "unchanged"
	if bool(s["died"]):
		return "respawn" if to == _respawn_value(v, from, mx) else ""
	var expect := from
	var causes := PackedStringArray()
	if int(s["damage"]) > 0:
		expect = maxi(0, expect - int(s["damage"]))
		causes.append("damage")
	for id: String in s["items"]:
		expect = mini(mx, expect + _restore(id, v, mx))
		causes.append("item")
	if bool(s["level_up"]):
		if _level_up_heals:
			expect = mx
		causes.append("level-up")
	if bool(s["equip"]) and expect > mx:
		# A piece taken off with a Max HP/MP bonus clamps the value (only then does ItemService announce it).
		expect = mx
		causes.append("equipment")
	if not causes.is_empty():
		return "+".join(causes) if to == expect else ""
	if v != "hp" or to < from:
		return ""
	var sizes := _tick_sizes()
	var d := to - from
	if sizes.has(d) or (to == mx and not sizes.is_empty() and d < sizes.max()):
		return "recovery tick"
	return ""


## The HP one recovery tick can restore now: the natural tick, the seated chair's bonus (alone or with the natural
## tick: NaturalRecovery heals both in one step) and every tick of a heal-over-time effect.
func _tick_sizes() -> Array:
	var out := []
	if _natural_tick > 0:
		out.append(_natural_tick)
	var chair := int(Chairs.bonus(_chair, _db).get("hp", 0)) if _chair != "" else 0
	if chair > 0:
		out.append(chair)
		out.append(chair + _natural_tick)
	for id: String in _heals:
		var h: Dictionary = _heals[id]
		for k in range(1, int(h["n"]) + 1):
			var t := EffectBook.heal_for_tick(int(h["total"]), int(h["n"]), k)
			if t > 0 and not out.has(t):
				out.append(t)
	return out


## What one `item_id` restores of a vital at max `mx` (Consumables.preview before the clamp).
func _restore(item_id: String, v: String, mx: int) -> int:
	var def := ItemDef.of(item_id, _db)
	if def == null:
		return 0
	if v == "hp":
		return def.hp_flat + int(floor(mx * def.hp_pct / 100.0))
	return def.mp_flat + int(floor(mx * def.mp_pct / 100.0))


## A vital after a death's respawn (death.json respawn_vitals; HP at least 1, as DeathRules sets it).
func _respawn_value(v: String, at_death: int, mx: int) -> int:
	var spec: Variant = _respawn.get(v, {})
	var value := DeathRules.vital_value(spec if spec is Dictionary else {}, at_death, mx)
	return maxi(1, value) if v == "hp" and mx > 0 else value


func _scan_heals() -> void:
	if _c == null:
		return
	for e: Variant in _c.effects:
		if not (e is Dictionary) or not ((e as Dictionary).get("data", null) is Dictionary):
			continue
		var data: Dictionary = (e as Dictionary)["data"]
		if data.has("hp_total"):
			_heals[String((e as Dictionary).get("id", ""))] = {"total": int(data.get("hp_total", 0)),
				"n": EffectBook.tick_count(float(data.get("duration_s", 0.0)), float(data.get("tick_s", 0.0)))}


## Drops the heal effects that have ended (after the announcement of their last tick was judged).
func _prune_heals() -> void:
	var live := {}
	for e: Variant in _c.effects:
		if e is Dictionary:
			live[String((e as Dictionary).get("id", ""))] = true
	for id: String in _heals.keys():
		if not live.has(id):
			_heals.erase(id)


func _clear_causes(v: String) -> void:
	var s: Dictionary = _vital[v]
	s["damage"] = 0
	s["items"] = []
	s["level_up"] = false
	s["equip"] = false
	s["died"] = false


func _causes_text(v: String, s: Dictionary) -> String:
	var parts := PackedStringArray()
	if int(s["damage"]) > 0:
		parts.append("damage %d" % int(s["damage"]))
	if not (s["items"] as Array).is_empty():
		parts.append("items used %s" % [s["items"]])
	for k in ["level_up", "equip", "died"]:
		if bool(s[k]):
			parts.append(k)
	if v == "hp":
		parts.append("recovery ticks %s" % [_tick_sizes()])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func _owed_text(v: String, owed: Dictionary) -> String:
	return "%s went %d -> %d (max %d) and no skill_used paid it" % [v.to_upper(), int(owed["from"]), int(owed["to"]),
		int(owed["max"])]


static func _now(c: CharacterState, v: String) -> int:
	return c.hp if v == "hp" else c.mp


func _max_now(c: CharacterState, v: String) -> int:
	return StatCalculator.max_hp(c, _db) if v == "hp" else StatCalculator.max_mp(c, _db)


# --- the bus --------------------------------------------------------------------------------------------------

func _on_exp(amount: int, _source: String) -> void:
	heard += 1
	exp_sum += amount


func _on_mesos(_mesos: int, delta: int) -> void:
	heard += 1
	mesos_sum += delta


func _on_gained(item_id: String, qty: int) -> void:
	heard += 1
	item_delta[item_id] = int(item_delta.get(item_id, 0)) + qty


func _on_lost(item_id: String, qty: int) -> void:
	heard += 1
	item_delta[item_id] = int(item_delta.get(item_id, 0)) - qty


func _on_started(qid: String) -> void:
	heard += 1
	quest_last[qid] = QuestLog.IN_PROGRESS


func _on_completed(qid: String) -> void:
	heard += 1
	quest_last[qid] = QuestLog.COMPLETED


func _on_forfeited(qid: String) -> void:
	heard += 1
	quest_last[qid] = QuestLog.NOT_STARTED


func _on_leveled(new_level: int) -> void:
	heard += 1
	levels.append(new_level)
	for v in VITALS:
		_vital[v]["level_up"] = true


func _on_stats() -> void:
	heard += 1
	_stats_seen = {"ap": _c.ap, "stats": base_stats(_c)}


func _on_skill_leveled(skill_id: String, level: int) -> void:
	heard += 1
	var said: Array = skill_levels.get(skill_id, [])
	said.append(level)
	skill_levels[skill_id] = said


func _on_skill_used(skill_id: String, level: int) -> void:
	heard += 1
	_scan_heals()
	var owed: Dictionary = _vital["mp"]["owed"]
	var def := SkillDef.of(skill_id, _db)
	if not owed.is_empty() and def != null and int(owed["from"]) - int(owed["to"]) == def.mp_cost(level):
		vital_steps["skill cost"] = int(vital_steps.get("skill cost", 0)) + 1
		_vital["mp"]["owed"] = {}


func _on_effects() -> void:
	heard += 1
	_scan_heals()


func _on_hp(hp: int, max_hp: int) -> void:
	heard += 1
	_step("hp", hp, max_hp)


func _on_mp(mp: int, max_mp: int) -> void:
	heard += 1
	_step("mp", mp, max_mp)


func _on_damaged(amount: int, _source: String) -> void:
	heard += 1
	_vital["hp"]["damage"] = int(_vital["hp"]["damage"]) + maxi(0, amount)


func _on_item_used(item_id: String) -> void:
	heard += 1
	for v in VITALS:
		# Only when the item restores something now: ItemService announces no unchanged vital (a potion leaves MP
		# alone, a potion drunk at full HP restores 0), and a cause nobody announces must not linger into a later step.
		var s: Dictionary = _vital[v]
		if _restore(item_id, v, int(s["max"])) > 0 and int(s["seen"]) < int(s["max"]):
			(s["items"] as Array).append(item_id)


func _on_equipment(_slot: String) -> void:
	heard += 1
	for v in VITALS:
		_vital[v]["equip"] = true


func _on_died(_map_id: String) -> void:
	heard += 1
	for v in VITALS:
		_vital[v]["died"] = true


func _on_sat(chair_id: String) -> void:
	heard += 1
	_chair = chair_id


func _on_stood(_reason: String) -> void:
	heard += 1
	_chair = ""
