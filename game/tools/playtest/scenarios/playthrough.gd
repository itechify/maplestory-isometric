extends PlaytestScenario
## playthrough: the clean-character end-to-end playthrough of Maple Island (brief Phase 15, "Full Quest Playthrough
## Requirement", "Clean-Character Progression Audit", Definition of Done "Gameplay"). ONE run: a brand-new character
## through the real title and creation screens (New Game, a typed name, Recommended, Start), then STRICT from the
## step after character creation to the end: no console command, no api fallback, no change to the character the
## event bus did not announce, and reloads only through the pause menu's Quit Game and the title's Continue.
##
## The route follows the island: Mushroom Town's tutorial quests (1000-1005), the Snail Hunting Grounds (1006, the
## first SP and Three Snails), A Split Road (1007 and 1009 accepted, Mai's training hunted), Southperry (Biggs 1011,
## Yoona, Bari, Shanks refusing a low level, Pan's shop), back to A Split Road (1009 done, 1010 accepted, Recovery and
## Nimble Feet cast), The Field West of Amherst (1010's Orange Mushroom and 1011's drops, and a death among the
## Orange Mushrooms unless one already happened), Amherst (1007 done, 1008, Rain's seven quizzes, Pio's Wooden Boxes,
## The Green Relaxer sat on), Sid's and Lucy's shops, every other map (Townstreet, Snail Field of Flowers, The Field
## East of Amherst, Tomato Field, the six forest maps), back to A Split Road and Southperry for the last turn-ins, the
## quest hat and knife equipped, and Shanks: the End of Maple Island screen. Every quest is played through
## PlaytestQuestRunner (the every-quest scenario's play, with canonical expectations); everything else through the
## kit. The process is restarted (Save, Quit Game, Continue) at planned points and in the middle of 1009 and 1012.
##
## A step that cannot be completed stops the run with a failed check and a finding row (map, map-local position,
## what happened, what was expected) in d.carry["findings"]. The progression audit is in d.carry: "checkpoints"
## (level, EXP, mesos, equipment, ETC items, quest states, play time), "exp_by_source", "kills_by_mob",
## "visited_maps", "deaths", "level_at", "shops", "skills_cast", "totals". Nothing is hard-coded that canonical data
## gives: rewards, prices, levels, routes and the death penalty are read from ContentDB.
##
## Development: PLAYTHROUGH_STOP=<step> ends the run after that step; with scripts/playtest.sh's PLAYTEST_STOP_PHASE
## and --resume a later phase can be replayed from a copy of an --out directory.

const CHAR_NAME := "Islander"
const GENDER := "female"
## AP goes into the stats window in this order (the Wooden Club warrior's split the hunters use).
const AP_PLAN := ["str", "dex"]
## The Beginner skills, the order SP is spent in (one point each first), and their keys.
const THREE_SNAILS := "0001000"
const RECOVERY := "0001001"
const NIMBLE_FEET := "0001002"
const SKILL_ORDER := [THREE_SNAILS, RECOVERY, NIMBLE_FEET]
const SKILL_KEYS := {THREE_SNAILS: "1", RECOVERY: "2", NIMBLE_FEET: "3"}
const CHAIR := "522"
const SHANKS := "15"
const SOUTHPERRY := "000000060"
const FLAG := "maple_island_departure_ready_at"
## Shops: the shopkeeper, the shop's map and what is bought there (cheapest useful buys; affordability-gated).
const PAN := "16"
const SID := "20"
const LUCY := "21"
## The Snail Shells kept for Three Snails throws when selling.
const KEEP_SHELLS := 6
## Game-second budget of the top-up hunts (level 7 and the fare before Shanks, level 8 for a Fruit Knife).
const TOPUP_BUDGET_S := 2400.0

## The route, in order. "reload:<why>" saves through the pause menu and restarts the process (Quit Game, Continue).
const STEPS := [
	"heena_sera", "roger", "nina_sen", "todd_peter", "save_title_continue", "reload:Mushroom Town done",
	"robin", "sam", "first_skill", "to_split_road", "mai_maria", "southperry", "pan_first", "reload:Southperry",
	"mai_training", "more_skills", "field_west", "amherst_letters", "pio", "death", "chair", "rain",
	"sid", "lucy", "explore_amherst", "reload:Amherst done",
	"explore_forests", "split_road_turn_ins", "biggs", "equip_rewards", "pan_last", "ready_to_sail",
	"reload:before boarding", "shanks", "save_after_departure", "reload:after the departure", "after_departure",
]

var d: PlaytestDriver = null
var db: ContentDB = null
var k: PlaytestKit = null
var qr: PlaytestQuestRunner = null
var _step := ""


func description() -> String:
	return "Clean-character playthrough: creation to Southperry's departure boundary, strict from creation, every quest, map, monster, shop, skill, the chair, a death and process restarts"


## Game seconds per phase (each phase holds a few steps; the longest are the hunts).
func max_seconds() -> float:
	return 6000.0


func run(p_d: PlaytestDriver) -> void:
	d = p_d
	db = d.db()
	k = PlaytestKit.new(d)
	qr = PlaytestQuestRunner.new(d, k)
	qr.ap_plan = AP_PLAN
	qr.mid_reload_policy = "listed"
	qr.mid_reload_quests = {"1009": true, "1012": true}
	if d.phase == 0:
		if not await _create():
			return
	elif not await _resume():
		return
	var stop := OS.get_environment("PLAYTHROUGH_STOP")
	for s: String in STEPS:
		if _done(s):
			continue
		_step = s
		if s.begins_with("reload:"):
			_mark(s)
			await _save_and_restart(s.trim_prefix("reload:"))
			return
		var ok: bool = await _play(s)
		if not ok:
			d.check("step '%s' completed" % s, false, "map %s at %s; see the findings" % [d.current_map(), k.local_pos()])
			_finish(false)
			return
		_mark(s)
		if stop == s:
			# The stop flag: a run ended here never reaches the departure boundary, so it is not a clean-character run
			# (tools/parity/parity.mjs cleanRun reads this carry key and the note).
			d.carry["stopped_after"] = s
			d.note("PLAYTHROUGH_STOP=%s: stopping after this step" % s)
			_finish(false)
			return
	_finish(true)


func _done(s: String) -> bool:
	return (d.carry.get("steps_done", {}) as Dictionary).has(s)


func _mark(s: String) -> void:
	var m: Dictionary = d.carry.get("steps_done", {})
	m[s] = {"phase": d.phase, "play_s": snappedf(k.play_s(), 0.1)}
	d.carry["steps_done"] = m


func _play(s: String) -> bool:
	match s:
		"heena_sera":
			return await _quests(["1000", "1001"])
		"roger":
			return await _quests(["1002"])
		"nina_sen":
			return await _quests(["1003", "1004"])
		"todd_peter":
			var ok := await _quests(["1005"])
			k.checkpoint("Mushroom Town's tutorial quests done (1000-1005)")
			return ok
		"save_title_continue":
			return await _save_title_continue()
		"robin":
			return await _talk_townsfolk("8", "000000040")
		"sam":
			var ok := await _offers(["1006"])
			if ok:
				ok = await _objectives(["1006"])
			await _allocate_ap()
			return ok
		"first_skill":
			return await _first_skill()
		"to_split_road":
			return await _travel("000000050")
		"mai_maria":
			if not await _turn_ins(["1006"]):
				return false
			k.checkpoint("Sam's Suggestion (1006) done")
			return await _offers(["1007", "1009"])
		"southperry":
			return await _southperry()
		"pan_first":
			return await _shop(PAN, "000000061", [{"item": "1305", "qty": 1}], "first visit")
		"mai_training":
			if not await _quests(["1009"]):
				return false
			k.checkpoint("Mai's Training (1009) done")
			return await _offers(["1010"])
		"more_skills":
			return await _more_skills()
		"field_west":
			var ok := await _objectives(["1010", "1011"])
			k.checkpoint("1010's Orange Mushroom and 1011's items")
			return ok
		"death":
			return await _death()
		"amherst_letters":
			if not await _turn_ins(["1007"]):
				return false
			return await _offers(["1008"])
		"rain":
			var ok := await _quests(["1013", "1014", "1015", "1016", "1017", "1018", "1019"])
			k.checkpoint("Rain's seven quizzes done (1013-1019)")
			return ok
		"pio":
			var ok := await _quests(["1012"])
			k.checkpoint("Pio's Collecting Recycled Goods (1012) done: The Green Relaxer")
			return ok
		"chair":
			return await _chair()
		"sid":
			return await _shop(SID, "000001011", [{"item": "541", "qty": 1}], "")
		"lucy":
			var ok := await _shop(LUCY, "000001013", [{"item": "270", "qty": 2}], "")
			await _drink_mp()
			return ok
		"explore_amherst":
			var ok := await _visit(["000001012", "000001014", "000001012", "000001010", "000001020", "000001021", "000001020",
				"000001010"])
			k.checkpoint("Amherst and its neighbours explored")
			return ok
		"explore_forests":
			return await _visit(["000001000", "000001001", "000001000", "000001002", "000001000", "000001003", "000001000",
				"000001004", "000001000", "000001005", "000001000", "000001006", "000001000"])
		"split_road_turn_ins":
			var ok := await _turn_ins(["1010", "1008"])
			k.checkpoint("Mai's Final Training (1010) and Lucas's Reply (1008) done")
			return ok
		"biggs":
			var ok := await _turn_ins(["1011"])
			k.checkpoint("Biggs's Collection of Items (1011) done")
			return ok
		"equip_rewards":
			return await _equip_rewards()
		"pan_last":
			return await _shop(PAN, "000000061", [{"item": "1305", "qty": 1}], "last visit")
		"ready_to_sail":
			return await _ready_to_sail()
		"shanks":
			return await _shanks()
		"save_after_departure":
			var saved: Dictionary = await d.save_game()
			return d.check("saved through the pause menu after the departure screen", bool(saved["ok"]) and saved["via"] == "screen",
				str(saved), ["mechanic:save-load"])
		"after_departure":
			return await _after_departure()
	d.check("a known step '%s'" % s, false)
	return false


# =================================================================================================================
# Creation and the process restarts
# =================================================================================================================

## The new character through the real title and creation screens, then strict mode on.
func _create() -> bool:
	var ng: Dictionary = await d.new_game(CHAR_NAME, GENDER, "", {})
	if not d.check("a brand-new character through the title and creation screens (New Game, the name typed, Recommended, Start)",
			bool(ng["ok"]) and ng["via"] == "screen", "%s in %s via %s %s" % [ng["slot"], ng["map"], ng["via"], ng["why"]]):
		return false
	d.begin_strict("after character creation")
	k.track()
	var c := d.character()
	d.carry["created"] = {"name": c.name, "slot": String(ng["slot"]), "map": d.current_map(), "weapon": c.equipment.weapon_id(),
		"stats": c.base_stats.duplicate(), "level": c.level, "exp": c.exp, "mesos": c.mesos}
	d.check("a new Beginner: level 1, 0 EXP, 0 mesos, no quest, in Maple Island's first map %s" % d.current_map(),
		c.level == 1 and c.exp == 0 and c.mesos == 0 and c.quests.completed_ids().is_empty()
		and c.quests.active_ids().is_empty() and d.current_map() == "000000001",
		"level %d exp %d mesos %d map %s weapon %s stats %s" % [c.level, c.exp, c.mesos, d.current_map(),
			c.equipment.weapon_id(), c.base_stats], ["map:000000001"])
	k.checkpoint("a new character")
	return true


## A later phase: Continue on the title screen, then the saved state is checked (planned restarts here, mid-quest
## restarts through the quest runner).
func _resume() -> bool:
	var cont: Dictionary = await d.continue_game()
	if not d.check("Continue loads the run's save (phase %d)" % d.phase, bool(cont["ok"]) and cont["via"] == "screen"
			and String(cont["slot"]) == String((d.carry.get("created", {}) as Dictionary).get("slot", cont["slot"])),
			str(cont), ["mechanic:save-load"]):
		return false
	k.track()
	await qr.verify_mid()
	var pe: Dictionary = d.carry.get("phase_end", {})
	if not pe.is_empty():
		d.carry.erase("phase_end")
		var c := d.character()
		var log_diff := PlaytestDriver.diff(pe["log"], c.quests.to_dict())
		var bag_diff := PlaytestDriver.diff(pe["bag"], k.snapshot()["bag"])
		var eq_diff := PlaytestDriver.diff(pe["equipment"], c.equipment.equipped())
		d.check("after Quit Game and Continue (%s) the character is the saved one: level, EXP, mesos, AP, SP, skills, bag, equipment, quests"
			% pe["why"], c.level == int(pe["level"]) and c.exp == int(pe["exp"]) and c.mesos == int(pe["mesos"])
			and c.ap == int(pe["ap"]) and c.sp == int(pe["sp"]) and PlaytestDriver.diff(pe["skills"], c.skills) == ""
			and log_diff == "" and bag_diff == "" and eq_diff == "",
			"level %d/%d exp %d/%d mesos %d/%d ap %d/%d sp %d/%d; quests %s; bag %s; equipment %s" % [c.level, int(pe["level"]),
				c.exp, int(pe["exp"]), c.mesos, int(pe["mesos"]), c.ap, int(pe["ap"]), c.sp, int(pe["sp"]), log_diff, bag_diff,
				eq_diff], ["mechanic:save-load"])
		d.check("Continue resumes in the map it was saved in (%s)" % pe["map"], d.current_map() == String(pe["map"]),
			d.current_map(), ["mechanic:save-load"])
		d.check("the play time survives the restart (%.0f s saved)" % float(pe["play_time_s"]),
			absf(float(c.play_time_s) - float(pe["play_time_s"])) < 30.0, "%.1f s now" % c.play_time_s, ["mechanic:save-load"])
	return true


## Saves through the pause menu, keeps what must come back, and ends the process with Quit Game. Never returns.
func _save_and_restart(why: String) -> void:
	var c := d.character()
	var saved: Dictionary = await d.save_game()
	d.check("saved through the pause menu (%s)" % why, bool(saved["ok"]) and saved["via"] == "screen", str(saved),
		["mechanic:save-load"])
	d.carry["phase_end"] = {"why": why, "map": d.current_map(), "level": c.level, "exp": c.exp, "mesos": c.mesos, "ap": c.ap,
		"sp": c.sp, "skills": c.skills.duplicate(), "log": c.quests.to_dict(), "bag": k.snapshot()["bag"],
		"equipment": c.equipment.equipped(), "play_time_s": c.play_time_s}
	k.checkpoint("before the restart: %s" % why)
	k.carry_totals()
	await d.reload_process()


## In-process: Save, Quit to Title, Continue (the shell's own reload, no process restart).
func _save_title_continue() -> bool:
	var c := d.character()
	var before := {"level": c.level, "exp": c.exp, "mesos": c.mesos, "log": c.quests.to_dict(), "bag": k.snapshot()["bag"],
		"map": d.current_map()}
	var saved: Dictionary = await d.save_game()
	d.check("saved through the pause menu", bool(saved["ok"]) and saved["via"] == "screen", str(saved), ["mechanic:save-load"])
	var q: Dictionary = await d.quit_to_title()
	if not d.check("Quit to Title", bool(q["ok"]) and q["via"] == "screen", str(q)):
		return false
	var cont: Dictionary = await d.continue_game()
	if not d.check("Continue from the title", bool(cont["ok"]) and cont["via"] == "screen", str(cont), ["mechanic:save-load"]):
		return false
	k.track()
	c = d.character()
	return d.check("after Quit to Title and Continue: the same map, level, EXP, mesos, bag and quests",
		d.current_map() == String(before["map"]) and c.level == int(before["level"]) and c.exp == int(before["exp"])
		and c.mesos == int(before["mesos"]) and PlaytestDriver.diff(before["log"], c.quests.to_dict()) == ""
		and PlaytestDriver.diff(before["bag"], k.snapshot()["bag"]) == "", "", ["mechanic:save-load"])


# =================================================================================================================
# Quests, travel, NPCs
# =================================================================================================================

## Accepts quests through the runner, in order (each at its NPC). A refusal is a finding.
func _offers(ids: Array) -> bool:
	for qid: String in ids:
		if d.character().quests.status(qid) != QuestLog.NOT_STARTED:
			continue
		if not await qr.offer(qid):
			_finding("quest", "quest %s (%s) could not be accepted" % [qid, qr.plan(qid)["name"]], "the quest is offered and accepted")
			return false
	return true


## Plays the objectives of accepted quests through the runner, in order.
func _objectives(ids: Array) -> bool:
	for qid: String in ids:
		if d.character().quests.is_completed(qid):
			continue
		if not await qr.objectives(qid):
			_finding("quest", "the objectives of %s (%s) were not met" % [qid, qr.plan(qid)["name"]], "the objectives can be met by play")
			return false
		await _allocate_ap()
	return true


## Turns quests in through the runner (and checks their follow-ups), in order.
func _turn_ins(ids: Array) -> bool:
	for qid: String in ids:
		if d.character().quests.is_completed(qid):
			continue
		if not await qr.turn_in(qid):
			_finding("quest", "%s (%s) could not be turned in" % [qid, qr.plan(qid)["name"]], "the turn-in completes the quest")
			return false
		await qr.after(qid)
		await _allocate_ap()
	return true


## Plays quests through the runner, in order; AP is spent after each (a quest's EXP can level up).
func _quests(ids: Array) -> bool:
	for qid: String in ids:
		if not await qr.play(qid):
			_finding("quest", "quest %s (%s) stopped at %s" % [qid, qr.plan(qid)["name"], d.character().quests.status(qid)],
				"the quest completes through play")
			return false
		await _allocate_ap()
	return true


func _travel(map_id: String) -> bool:
	if await k.travel_to(map_id):
		return true
	_finding("travel", "could not walk from %s to %s (%s)" % [d.current_map(), map_id, k.travel_text().right(300)],
		"every map is reachable on foot over its canonical portals")
	return false


## Walks through the maps in order (each a canonical portal hop or more).
func _visit(maps: Array) -> bool:
	for m: String in maps:
		if not await _travel(m):
			return false
	return true


## Talks to an NPC that gives no quest (the island's guides and townsfolk) and pages its lines.
func _talk_townsfolk(npc: String, map_id: String) -> bool:
	if not await _travel(map_id):
		return false
	var t: Dictionary = await k.talk(npc)
	if not d.check("talked to %s on foot in %s" % [k.npc_name(npc), map_id], bool(t.get("open", false)),
			String(t.get("why", "")), ["npc:" + npc]):
		_finding("npc", "%s could not be talked to (%s)" % [k.npc_name(npc), t.get("why", "")], "every NPC can be talked to")
		return false
	var conv: Dictionary = await k.converse({})
	d.note("%s: %s" % [k.npc_name(npc), " | ".join(conv["pages"])])
	var talked: Dictionary = d.carry.get("npcs_talked", {})
	talked[npc] = (conv["pages"] as PackedStringArray).size()
	d.carry["npcs_talked"] = talked
	return true


## Southperry, first visit: Yoona and Bari, Biggs's quest, and Shanks, who refuses a character below his level.
func _southperry() -> bool:
	if not await _talk_townsfolk("13", SOUTHPERRY):
		return false
	if not await _talk_townsfolk("14", SOUTHPERRY):
		return false
	if not await qr.offer("1011"):
		return false
	var route := _route()
	var c := d.character()
	if c.level < int(route.get("min_level", 0)):
		var pages := await _shanks_pages(false)
		d.check("Shanks refuses level %d with the canonical level %d" % [c.level, int(route["min_level"])],
			PlaytestKit.any_contains(pages["texts"], "at least level %d" % int(route["min_level"])) and String(pages["offer"]) == "",
			str(pages["texts"]), ["npc:" + SHANKS])
	k.checkpoint("Southperry, first visit")
	return true


# =================================================================================================================
# Skills
# =================================================================================================================

## Spends every unspent SP through the Skills window: one point in each Beginner skill first (in SKILL_ORDER), then the
## rest round the same order up to each skill's max level. A newly learned skill is put on its key.
func _learn_skills() -> void:
	var c := d.character()
	var guard := 0
	while c.sp > 0 and guard < 12:
		guard += 1
		var pick := ""
		for sid: String in SKILL_ORDER:
			if SkillBook.level_of(c, sid) == 0:
				pick = sid
				break
		if pick == "":
			var best := 99
			for sid: String in SKILL_ORDER:
				var def := SkillDef.of(sid, db)
				var lv := SkillBook.level_of(c, sid)
				if def != null and lv < def.max_level and lv < best:
					best = lv
					pick = sid
		if pick == "":
			break
		var r: Dictionary = await k.learn_skill(pick)
		d.check("'+' in the Skills window (K) raises %s to level %d with 1 SP" % [_skill_name(pick), int(r["level0"]) + 1],
			bool(r["ok"]), str(r), ["skill:" + pick, "mechanic:skill-window"])
		if not bool(r["ok"]):
			return
		if int(r["level0"]) == 0:
			var b: Dictionary = await k.bind_skill(pick, String(SKILL_KEYS[pick]))
			d.check("%s put on key %s with the Skills window's Set key" % [_skill_name(pick), SKILL_KEYS[pick]], bool(b["ok"]),
				str(b), ["skill:" + pick, "mechanic:skill-window"])


## The first SP (a level-up from hunting) goes into Three Snails, which is thrown at a Snail with its key.
func _first_skill() -> bool:
	var c := d.character()
	if c.sp <= 0 and SkillBook.level_of(c, THREE_SNAILS) == 0:
		d.note("no SP yet at level %d: Three Snails waits" % c.level)
		return true
	await _learn_skills()
	if SkillBook.level_of(c, THREE_SNAILS) == 0:
		return true
	return await _throw_three_snails(["2"])


## Throws Three Snails at the nearest monster of `mobs` until a throw lands; checks the canonical fixed damage, the MP
## and the Snail Shell spent per cast.
func _throw_three_snails(mobs: Array) -> bool:
	var c := d.character()
	var def := SkillDef.of(THREE_SNAILS, db)
	var lv := SkillBook.level_of(c, THREE_SNAILS)
	var shell := String(def.item_cost(lv)["item_id"])
	if c.inventory.count(shell) < 1 or c.mp < def.mp_cost(lv):
		d.soft_check("a Snail Shell and %d MP to throw Three Snails" % def.mp_cost(lv), false, "shells %d, MP %d" % [
			c.inventory.count(shell), c.mp], ["skill:" + THREE_SNAILS])
		return true
	# A target on the player's own tier; one the walk cannot get level with (a ledge above) is passed over.
	var skip := {}
	var r: Dictionary = {}
	var target: Node3D = null
	for attempt in 4:
		target = k.same_tier_monster(mobs, skip)
		for i in 10:
			if target != null:
				break
			await d.wait(1.0)
			target = k.same_tier_monster(mobs, skip)
		if target == null:
			break
		r = await k.throw_at(target, {"casts": 3, "max_s": 40.0})
		if bool(r["ok"]) or int(r["casts"]) > 0:
			break
		d.note("Three Snails: %s passed over (%s)" % [k.mob_name(String(target.get("def").get("id"))) if is_instance_valid(target)
			else "a target", r["why"]])
		if is_instance_valid(target):
			skip[target.get_instance_id()] = true
	if target == null and r.is_empty():
		d.soft_check("a %s in sight to throw Three Snails at" % k.mob_name(String(mobs[0])), false, d.current_map(), ["skill:" + THREE_SNAILS])
		return true
	var fixed := int(def.fixed_damage(lv))
	var exact := true
	for v: Variant in r["damage"]:
		exact = exact and int(v) == fixed
	d.check("key %s throws Three Snails at a %s: it hits for the canonical fixed damage %d" % [SKILL_KEYS[THREE_SNAILS],
		k.mob_name(String(target.get("def").get("id")) if is_instance_valid(target) else String(mobs[0])), fixed],
		bool(r["ok"]) and exact, str(r), ["skill:" + THREE_SNAILS])
	d.check("each throw spent the level's MP and one Snail Shell", int(r["casts"]) > 0
		and int(r["shells0"]) - int(r["shells1"]) == int(r["casts"]) and int(r["mp0"]) - int(r["mp1"]) == int(r["casts"]) * def.mp_cost(lv),
		"%d casts: shells %d -> %d, MP %d -> %d" % [int(r["casts"]), int(r["shells0"]), int(r["shells1"]), int(r["mp0"]), int(r["mp1"])],
		["skill:" + THREE_SNAILS])
	_cast_row(THREE_SNAILS, {"casts": int(r["casts"]), "hits": int(r["hits"]), "damage": r["damage"], "killed": bool(r["killed"])})
	if bool(r["killed"]):
		await k.pickup(5.0, 8.0)
	return true


## After Mai's training: the SP of the level-ups, Recovery and Nimble Feet cast with their keys.
func _more_skills() -> bool:
	var c := d.character()
	await _learn_skills()
	# A first throw that never left the hand (no target in its band) gets a second chance here.
	if SkillBook.level_of(c, THREE_SNAILS) > 0 and _casts(THREE_SNAILS) == 0:
		await _throw_three_snails(["3", "4", "5"])
	for sid: String in [RECOVERY, NIMBLE_FEET]:
		if SkillBook.level_of(c, sid) == 0:
			continue
		var def := SkillDef.of(sid, db)
		var lv := SkillBook.level_of(c, sid)
		var mp0 := c.mp
		var r: Dictionary = await k.cast_skill(sid)
		var eff := EffectBook.has(c, PlayerSkills.effect_id(sid))
		d.check("key %s casts %s (level %d): its effect starts and it costs %d MP" % [SKILL_KEYS[sid], _skill_name(sid), lv,
			def.mp_cost(lv)], bool(r["ok"]) and eff and c.mp == mp0 - def.mp_cost(lv), "%s; MP %d -> %d; effects %s" % [r, mp0,
			c.mp, c.effects], ["skill:" + sid])
		_cast_row(sid, {"casts": 1 if bool(r["ok"]) else 0, "effect": eff, "mp": mp0 - c.mp})
	return true


## The real casts recorded for a skill (0 when it was tried and nothing went off).
func _casts(sid: String) -> int:
	return int(((d.carry.get("skills_cast", {}) as Dictionary).get(sid, {}) as Dictionary).get("casts", 0))


func _cast_row(sid: String, row: Dictionary) -> void:
	var m: Dictionary = d.carry.get("skills_cast", {})
	row["level"] = SkillBook.level_of(d.character(), sid)
	row["play_s"] = snappedf(k.play_s(), 0.1)
	m[sid] = row
	d.carry["skills_cast"] = m


func _skill_name(sid: String) -> String:
	var def := SkillDef.of(sid, db)
	return def.name if def != null else sid


# =================================================================================================================
# AP, consumables, equipment
# =================================================================================================================

## Spends unspent AP through the stats window (the hunts do it too), and unspent SP through the Skills window once
## Three Snails is learned (the first SP waits for the first_skill step).
func _allocate_ap() -> void:
	var c := d.character()
	if c.sp > 0 and SkillBook.level_of(c, THREE_SNAILS) > 0:
		await _learn_skills()
	if c.ap <= 0:
		return
	var ap0 := c.ap
	var r: Dictionary = await k.allocate_ap(AP_PLAN)
	d.check("%d AP spent with the stats window's '+' at level %d" % [ap0, c.level], bool(r["ok"]) and c.ap == 0, str(r),
		["mechanic:ap-allocation"])
	var a: Dictionary = d.carry.get("ap_spent", {})
	a["window"] = int(a.get("window", 0)) + int(r["spent"])
	d.carry["ap_spent"] = a


## An HP item eaten with a double-click when HP is low enough for its whole restore.
func _eat_hp_item() -> void:
	var c := d.character()
	var mx := StatCalculator.max_hp(c, db)
	for id: String in ["237", "236", "270", "242"]:
		var restore := k.hp_restore(id)
		if c.inventory.count(id) > 0 and restore > 0 and c.hp + restore <= mx:
			var r: Dictionary = await k.use_item(id)
			d.check("%s eaten with a double-click: HP +%d (canonical)" % [k.item_name(id), restore], bool(r["ok"])
				and int(r["hp1"]) - int(r["hp0"]) == restore, "HP %d -> %d" % [int(r["hp0"]), int(r["hp1"])], ["item:" + id])
			return


## An Orange (MP, 1019's reward) drunk with a double-click. With MP full, Nimble Feet is cast first (its MP cost:
## a faster walk through Amherst), so the restore shows; the game caps it at Max MP.
func _drink_mp() -> void:
	var c := d.character()
	var cons: Variant = db.item("239").get("consumable")
	var restore := int((cons as Dictionary).get("mp_restore", 0)) if cons is Dictionary else 0
	if c.inventory.count("239") <= 0 or restore <= 0:
		d.note("no Orange to drink (%d held)" % c.inventory.count("239"))
		return
	var mx := StatCalculator.max_mp(c, db)
	if c.mp >= mx and SkillBook.level_of(c, NIMBLE_FEET) > 0:
		var mp_c := c.mp
		var r0: Dictionary = await k.cast_skill(NIMBLE_FEET)
		d.check("key %s casts Nimble Feet again in Amherst (MP %d -> %d)" % [SKILL_KEYS[NIMBLE_FEET], mp_c, c.mp], bool(r0["ok"])
			and c.mp < mp_c, str(r0), ["skill:" + NIMBLE_FEET])
	if c.mp >= mx:
		d.note("MP %d of %d: no Orange needed" % [c.mp, mx])
		return
	var mp0 := c.mp
	var r: Dictionary = await k.use_item("239")
	var want := mini(restore, mx - mp0)
	d.check("an Orange drunk with a double-click: MP +%d (canonical %d, capped at Max MP %d)" % [want, restore, mx],
		bool(r["ok"]) and c.mp - mp0 == want, "MP %d -> %d" % [mp0, c.mp], ["item:239"])


## Equips a held piece with a double-click; below its canonical level the game refuses and says so.
func _equip(id: String, why: String) -> bool:
	var c := d.character()
	var req := int((db.item(id).get("requirements", {}) as Dictionary).get("level", 0))
	if c.level < req:
		var r0: Dictionary = await k.equip(id)
		d.check("%s (%s) is refused below its canonical level %d (level %d)" % [k.item_name(id), why, req, c.level],
			not bool(r0["ok"]), str(r0), ["item:" + id])
		return false
	var r: Dictionary = await k.equip(id)
	d.check("%s (%s) equipped with a double-click in the Equip tab" % [k.item_name(id), why], bool(r["ok"]), str(r),
		["item:" + id])
	if bool(r["ok"]):
		var e: Dictionary = d.carry.get("equipped", {})
		e[id] = {"why": why, "slot": String(r["slot"]), "level": c.level, "play_s": snappedf(k.play_s(), 0.1)}
		d.carry["equipped"] = e
	return bool(r["ok"])


## The quest hat (1008) and knife (1011) and the shop pieces still in the bag.
func _equip_rewards() -> bool:
	var c := d.character()
	for qid: String in ["1008", "1011"]:
		for id: String in _picked(qid):
			if c.inventory.count(id) > 0:
				await _equip(id, "%s's random reward" % qid)
	await _eat_hp_item()
	k.checkpoint("quest hat and knife")
	return true


## The item ids a quest's random reward gave (quest evidence).
func _picked(qid: String) -> PackedStringArray:
	var out := PackedStringArray()
	var ev: Dictionary = (d.carry.get("quest_evidence", {}) as Dictionary).get(qid, {})
	var pick := String((ev.get("rewards", {}) as Dictionary).get("random_pick", ""))
	for part in pick.split(", ", false):
		out.append(part.get_slice(" ", 0))
	return out


# =================================================================================================================
# Shops
# =================================================================================================================

## A shop by talking: buys each {item, qty} at its canonical price when the mesos allow it (else the refusal is
## checked and the buy waits for a later visit), sells loot the open quests do not need at its canonical sell
## price, and equips what it bought. Records it in d.carry["shops"].
func _shop(npc: String, map_id: String, buys: Array, visit: String) -> bool:
	if not await _travel(map_id):
		return false
	if not d.check("talking to %s opens the shop" % k.npc_name(npc), await k.open_shop(npc), "", ["npc:" + npc]):
		_finding("shop", "%s's shop did not open" % k.npc_name(npc), "talking to a shopkeeper opens the shop")
		return false
	# No NPC speech bubble over (or under) the open shop window (the acceptance review saw Lucy's cut off by it).
	await d.wait(0.2)
	var talking := PackedStringArray()
	var presenters: Variant = d.interaction().get("presenters") if d.interaction() != null else null
	if presenters is Dictionary:
		for id: String in presenters:
			var p: Variant = presenters[id]
			if p is NpcPresenter and is_instance_valid(p) and (p as NpcPresenter).bubble != null \
					and (p as NpcPresenter).bubble.visible:
				talking.append(k.npc_name(id))
	d.check("no NPC speech bubble shows while %s's shop is open" % k.npc_name(npc), talking.is_empty(), ", ".join(talking))
	await k.shot("shop_" + k.npc_name(npc).to_lower())
	var c := d.character()
	var shop_id := String(d.shop().get("shop_id"))
	var row: Dictionary = (d.carry.get("shops", {}) as Dictionary).get(npc, {"bought": [], "sold": [], "refused": []})
	var bought := PackedStringArray()
	for b: Dictionary in buys:
		var id := String(b["item"])
		var qty := int(b["qty"])
		if (row["bought"] as Array).any(func(x: Dictionary) -> bool: return String(x["item"]) == id):
			continue
		var price := int(ShopService.row_for(shop_id, id, db).get("price", -1))
		if c.mesos >= price * qty:
			var r: Dictionary = await k.buy(id, qty)
			d.check("%s: bought %d %s at the canonical price %d" % [k.npc_name(npc), qty, k.item_name(id), price], bool(r["ok"])
				and int(r["count_delta"]) == qty and int(r["mesos_delta"]) == -price * qty, str(r), ["shop:" + shop_id, "item:" + id])
			if bool(r["ok"]):
				(row["bought"] as Array).append({"item": id, "qty": qty, "price": price, "visit": visit})
				bought.append(id)
		else:
			var r2: Dictionary = await k.buy(id, qty)
			d.check("%s: buying %d %s for %d with %d mesos is refused and changes nothing" % [k.npc_name(npc), qty, k.item_name(id),
				price * qty, c.mesos], not bool(r2["ok"]) and int(r2["count_delta"]) == 0 and int(r2["mesos_delta"]) == 0,
				str(r2), ["shop:" + shop_id, "mechanic:insufficient-mesos-warning"])
			(row["refused"] as Array).append({"item": id, "qty": qty, "price": price, "mesos": c.mesos, "message": String(r2["message"]),
				"visit": visit})
	for s: Dictionary in _sellable():
		if (row["sold"] as Array).size() >= 2:
			break
		var id := String(s["item"])
		var qty := int(s["qty"])
		var each := ShopService.sell_price(id, db)
		var r3: Dictionary = await k.sell(id, qty)
		d.check("%s: sold %d %s at the canonical sell price %d" % [k.npc_name(npc), qty, k.item_name(id), each], bool(r3["ok"])
			and int(r3["count_delta"]) == -qty and int(r3["mesos_delta"]) == each * qty, str(r3), ["shop:" + shop_id, "item:" + id])
		if bool(r3["ok"]):
			(row["sold"] as Array).append({"item": id, "qty": qty, "price": each, "visit": visit})
	await k.close_shop()
	var shops: Dictionary = d.carry.get("shops", {})
	shops[npc] = row
	d.carry["shops"] = shops
	for id in bought:
		if String(db.item(id).get("inventory_tab", "")) == "equip":
			await _equip(id, "bought from %s" % k.npc_name(npc))
		elif k.hp_restore(id) > 0:
			var b2: Dictionary = await k.bind_quickslot(id, "4")
			d.soft_check("%s put on key 4 with a mouse drag" % k.item_name(id), bool(b2["ok"]), str(b2), ["item:" + id])
	k.checkpoint("%s's shop%s" % [k.npc_name(npc), (" (" + visit + ")") if visit != "" else ""])
	return true


## Loot to sell: ETC items with a sell price that no unfinished quest needs (canonical item objectives), keeping
## KEEP_SHELLS Snail Shells for Three Snails. [{item, qty}], most valuable first, at most 5 of each.
func _sellable() -> Array:
	var c := d.character()
	var need := {}
	for qid: String in db.ids("quests"):
		if c.quests.is_completed(qid):
			continue
		for it: Dictionary in (db.quest(qid).get("objectives", {}) as Dictionary).get("item_collection", []):
			var id := String(it.get("item_id", ""))
			need[id] = maxi(int(need.get(id, 0)), int(it.get("count", 1)))
	var shell := String(SkillDef.of(THREE_SNAILS, db).item_cost(1)["item_id"]) if SkillDef.of(THREE_SNAILS, db) != null else "348"
	need[shell] = maxi(int(need.get(shell, 0)), KEEP_SHELLS)
	var out: Array = []
	for row: Dictionary in (d.inventory_summary().get("etc", []) as Array):
		var id := String(row["item_id"])
		var item := db.item(id)
		var spare := c.inventory.count(id) - int(need.get(id, 0))
		if spare <= 0 or ShopService.sell_price(id, db) <= 0 or not QuestJson.b(item.get("tradeable"), true) \
				or out.any(func(x: Dictionary) -> bool: return String(x["item"]) == id):
			continue
		out.append({"item": id, "qty": mini(spare, 5), "value": ShopService.sell_price(id, db)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["value"]) > int(b["value"]))
	return out


# =================================================================================================================
# The chair, the death, the departure
# =================================================================================================================

## The Green Relaxer (1012's reward): sat on with a double-click in the Set-up tab and with X; the chair's own HP bonus
## is heard while seated (when HP is below Max HP); a step stands up.
func _chair() -> bool:
	var c := d.character()
	if not d.check("The Green Relaxer is in the Set-up tab (1012's reward)", c.inventory.count(CHAIR) > 0,
			"held %d" % c.inventory.count(CHAIR), ["chair:" + CHAIR]):
		return false
	# Right after the respawn (the death step comes first) HP is low: the player sits where it stands (Amherst is a
	# town; a walk with the survival policy would drink a potion first).
	var hp0 := c.hp
	var r: Dictionary = await k.use_chair(CHAIR)
	d.check("a double-click on The Green Relaxer seats the player", bool(r["ok"]), str(r), ["chair:" + CHAIR, "mechanic:sitting"])
	var setup: Dictionary = db.item(CHAIR).get("setup", {}) if db.item(CHAIR).get("setup") is Dictionary else {}
	var interval := float(setup.get("interval_s", 10.0))
	var bonus := int(setup.get("hp_recovery_bonus", 0))
	var seated_s := interval + 1.0
	var mx := StatCalculator.max_hp(c, db)
	await d.wait(seated_s)
	var healed := c.hp - hp0
	var still := k.activity() == &"seated"
	d.check("seated for %.0f s: still seated, HP %d -> %d of %d" % [seated_s, hp0, c.hp, mx], still,
		"activity %s" % k.activity(), ["chair:" + CHAIR, "mechanic:sitting"])
	# What a player sees: the HUD's seated cue above the HP gauge names the chair's bonus (the chair itself, green on
	# grass, is easy to miss).
	var cue := String((d.hud() as MisoHud).status.seat_label.text)
	d.check("while seated the HUD's cue shows the chair's +%d HP" % bonus, cue.begins_with("Seated") and cue.contains("+%d HP" % bonus),
		cue, ["chair:" + CHAIR, "mechanic:sitting"])
	await k.shot("seated_on_the_green_relaxer")
	# One interval seated: the chair's own clock starts at the sit (one bonus tick), natural recovery's clock is the
	# saved one (one or two ticks of misostory/recovery.json natural_hp in 11 s). With room for all of it, HP rises by
	# the bonus plus one or two natural ticks; otherwise it reaches Max HP.
	var rec: Variant = db.miso_table("recovery")
	var natural: Dictionary = ((rec as Dictionary).get("natural_hp", {}) as Dictionary) if rec is Dictionary else {}
	var nat_tick := int(natural.get("hp_per_tick", 10))
	var want_min := bonus + nat_tick
	if mx - hp0 >= want_min + nat_tick:
		d.check("seated %.0f s at HP %d of %d: HP +%d = the chair's %d plus natural recovery's %d per tick (one or two ticks)"
			% [seated_s, hp0, mx, healed, bonus, nat_tick], healed >= want_min and healed <= want_min + nat_tick,
			"HP %d -> %d" % [hp0, c.hp], ["chair:" + CHAIR, "mechanic:chair-regen"])
	elif hp0 < mx:
		d.soft_check("HP rose while seated (the chair's %d HP per %.0f s plus natural recovery)" % [bonus, interval],
			healed > 0, "HP %d -> %d of %d" % [hp0, c.hp, mx], ["mechanic:chair-regen"])
	else:
		d.note("HP was full (%d) when the player sat down: the chair's bonus had nothing to heal" % hp0)
	var up: Dictionary = await k.stand()
	d.check("a step stands the player up from the chair", bool(up["ok"]), str(up), ["mechanic:sitting"])
	d.check("standing up clears the HUD's seated cue", not (d.hud() as MisoHud).status.is_seated_shown(),
		String((d.hud() as MisoHud).status.seat_label.text), ["mechanic:sitting"])
	var x: Dictionary = await k.sit()
	d.check("X sits on the first chair the character owns", bool(x["ok"]), str(x), ["chair:" + CHAIR, "mechanic:sitting"])
	var up2: Dictionary = await k.stand()
	d.check("and a step stands up again", bool(up2["ok"]), str(up2), ["mechanic:sitting"])
	d.carry["chair"] = {"double_click": bool(r["ok"]), "x_key": bool(x["ok"]), "hp": "%d -> %d" % [hp0, hp0 + healed],
		"seated_s": seated_s, "play_s": snappedf(k.play_s(), 0.1)}
	return true


## At least one death: when none has happened by now, the player stops defending among the Orange Mushrooms of The
## Field West of Amherst until they win (real contact damage), then clicks the notice's OK and respawns at the map's
## canonical return map (Amherst). The EXP penalty is checked against formulas/death.json.
func _death() -> bool:
	if not (d.carry.get("deaths", []) as Array).is_empty():
		d.note("a death already happened (%s): no deliberate one" % str(d.carry["deaths"]))
		return await _travel("000001010")
	if not await _travel("000001000"):
		return false
	var c := d.character()
	var map0 := d.current_map()
	var level0 := c.level
	var exp0 := c.exp
	var want_loss := mini(exp0, _death_loss(level0, c.get_base_stat("luk")))
	var r: Dictionary = await k.let_monsters_win(["9", "5", "4"], {"max_s": 400.0})
	if not d.check("the player stopped defending among Orange Mushrooms in %s and died to their contact damage" % map0,
			bool(r["ok"]), str(r), ["mechanic:death-respawn"]):
		_finding("death", "no death after %s s among the monsters (%s)" % [r["time_s"], r["why"]], "monster contact kills a player who does not defend")
		return false
	var notice := await d.wait_until(func() -> bool: return k.death_notice() != null, 15.0)
	# The penalty is committed when MapSession enters DEAD (misostory/death.json order).
	await d.wait_until(func() -> bool: return c.exp != exp0 or want_loss == 0, 5.0)
	d.check("the death notice shows", notice, "", ["mechanic:death-respawn"])
	d.check("the canonical EXP penalty: floor(EXP to next level x (5 + 20 / LUK) / 100) = %d at level %d (EXP %d -> %d)" % [
		want_loss, level0, exp0, c.exp], c.exp == exp0 - want_loss and c.level == level0, "EXP %d -> %d" % [exp0, c.exp],
		["mechanic:death-respawn"])
	var row := await k.respawn({"shot": "death_notice"})
	var ret := String(db.map(map0).get("return_map_id", ""))
	d.check("the notice's OK respawns the player at %s's canonical return map %s" % [map0, ret], bool(row["respawned"])
		and bool(row["ok_clicked"]) and d.current_map() == ret and not k.is_dead(), str(row), ["mechanic:death-respawn"])
	d.carry["deliberate_death"] = {"map": map0, "pos": String(r["pos"]), "touches": int(r["touches"]), "damage": int(r["damage"]),
		"time_s": float(r["time_s"]), "exp_lost": exp0 - c.exp, "respawn_map": d.current_map(), "hp_after": c.hp}
	k.checkpoint("after the death (respawned in %s)" % d.current_map())
	return d.current_map() == ret


## formulas/death.json exp_penalty: floor(exp_to_next x (base + numerator / LUK) / 100), LUK clamped.
func _death_loss(level: int, luk: int) -> int:
	var pen: Dictionary = db.formula("death").get("exp_penalty", {})
	var clamp: Array = pen.get("calculator_luk_clamp", [4, 999])
	var l := clampi(luk, int(clamp[0]), int(clamp[1]))
	return floori(float(Progression.exp_to_next(level, db)) * (float(pen.get("base_loss_pct", 5)) + float(pen.get("luk_term_numerator", 20))
		/ float(l)) / 100.0)


## Before boarding: every unspent AP spent, then hunting until the canonical boarding level and fare (and level 8
## when the quest knife needs it), the knife equipped once its level is reached.
func _ready_to_sail() -> bool:
	var c := d.character()
	var route := _route()
	await _allocate_ap()
	var knife := ""
	for id in _picked("1011"):
		if not c.equipment.equipped().values().has(id) and c.inventory.count(id) > 0:
			knife = id
	var want_level := int(route.get("min_level", 7))
	if knife != "":
		want_level = maxi(want_level, int((db.item(knife).get("requirements", {}) as Dictionary).get("level", 0)))
	var fare := int(route.get("fare_mesos", 0))
	if c.level < want_level or c.mesos < fare:
		d.note("before boarding: level %d (want %d), %d mesos (fare %d): hunting at A Split Road" % [c.level, want_level, c.mesos, fare])
		if not await _travel("000000050"):
			return false
		var h: Dictionary = await k.hunt(["5", "4", "3"], func() -> bool: return c.level >= want_level and c.mesos >= fare,
			{"map": "000000050", "ap_plan": AP_PLAN, "max_s": TOPUP_BUDGET_S})
		d.note("top-up hunt: %s" % h)
		await _allocate_ap()
		k.checkpoint("after the top-up hunt")
	if knife != "" and c.level >= int((db.item(knife).get("requirements", {}) as Dictionary).get("level", 0)):
		await _equip(knife, "1011's random reward, now that the level allows it")
	d.check("level %d or more (Shanks' canonical level %d%s) reached by play" % [want_level, int(route.get("min_level", 7)),
		", and the quest knife's" if want_level > int(route.get("min_level", 7)) else ""], c.level >= want_level,
		"level %d" % c.level, ["npc:" + SHANKS])
	d.check("the canonical fare %d mesos held" % fare, c.mesos >= fare, "%d mesos" % c.mesos, ["npc:" + SHANKS])
	if c.level < int(route.get("min_level", 7)) or c.mesos < fare:
		_finding("progression", "level %d and %d mesos after a %.0f s top-up hunt" % [c.level, c.mesos, TOPUP_BUDGET_S],
			"Shanks' canonical level and fare reached by play")
		return false
	return await _travel(SOUTHPERRY)


## Shanks' canonical route (npcs/15.json transport.routes[0]).
func _route() -> Dictionary:
	var t: Variant = db.npc(SHANKS).get("transport")
	var routes: Array = (t as Dictionary).get("routes", []) if t is Dictionary else []
	return routes[0] if not routes.is_empty() and routes[0] is Dictionary else {}


## Talks to Shanks and pages until the chat ends or (stop_at_offer) the Yes/No. {"open", "texts", "offer"}.
func _shanks_pages(stop_at_offer: bool) -> Dictionary:
	var v: Dictionary = await k.talk(SHANKS)
	var texts := PackedStringArray()
	var out := {"open": bool(v.get("open", false)), "texts": texts, "offer": ""}
	var r := d.read_dialogue()
	var guard := 0
	while bool(r["open"]) and guard < 12:
		guard += 1
		texts.append(String(r["text"]))
		out["texts"] = texts
		if String(r["type"]) == "yes_no":
			out["offer"] = String(r["text"])
			if stop_at_offer:
				return out
			r = await d.choose("no")
			continue
		if "next" in r["buttons"] or "ok" in r["buttons"]:
			r = await d.next()
		else:
			break
	if d.dialogue_open():
		await d.close_dialogue()
	return out


## Shanks with every quest done: the offer, Yes, and the End of Maple Island screen.
func _shanks() -> bool:
	if not await _travel(SOUTHPERRY):
		return false
	var c := d.character()
	var route := _route()
	var pages := await _shanks_pages(true)
	if not d.check("Shanks can be talked to on foot", bool(pages["open"]), str(pages["texts"]), ["npc:" + SHANKS]):
		_finding("departure", "Shanks could not be talked to", "Shanks can be talked to")
		return false
	d.check("no unfinished Maple Island quest is listed (all %d done)" % c.quests.completed_ids().size(),
		not PlaytestKit.any_contains(pages["texts"], "unfinished"), str(pages["texts"]), ["npc:" + SHANKS])
	if not d.check("Shanks offers the voyage: '%s'" % pages["offer"], String(pages["offer"]).contains("The fare is %d mesos." %
			int(route.get("fare_mesos", 0))), str(pages["texts"]), ["npc:" + SHANKS]):
		_finding("departure", "no Yes/No offer at level %d with %d mesos: %s" % [c.level, c.mesos, pages["texts"]],
			"Shanks offers the voyage at his canonical level and fare")
		return false
	var mesos0 := c.mesos
	await d.choose("yes")
	await d.frames(5)
	var s := _departure_screen()
	var open := s != null and bool(s.call("is_open"))
	if not d.check("Yes opens the End of Maple Island screen", open, "", ["npc:" + SHANKS]):
		_finding("departure", "the End of Maple Island screen did not open", "Yes to Shanks shows the departure boundary")
		return false
	var texts: PackedStringArray = s.call("texts")
	d.note("the departure screen: %s" % " | ".join(texts))
	await k.shot("departure_screen")
	d.check("it says every Maple Island quest is done", " ".join(texts).contains("Every Maple Island quest is done.")
		and " ".join(texts).contains("quests completed: %d of %d" % [db.ids("quests").size(), db.ids("quests").size()]),
		" | ".join(texts), ["npc:" + SHANKS])
	d.check("the departure flag is set, no mesos taken, still in Southperry", c.flags.has(FLAG) and c.mesos == mesos0
		and d.current_map() == SOUTHPERRY, "flags %s, mesos %d -> %d, map %s" % [c.flags, mesos0, c.mesos, d.current_map()],
		["npc:" + SHANKS])
	d.carry["departure"] = {"texts": texts, "level": c.level, "mesos": c.mesos, "play_s": snappedf(k.play_s(), 0.1),
		"flag": c.flags.get(FLAG)}
	await d.tap_key(KEY_ENTER)
	await d.frames(3)
	d.check("Enter on 'Stay on Maple Island' closes it", not bool(s.call("is_open")))
	k.checkpoint("at the departure boundary")
	return true


func _departure_screen() -> Node:
	var cx := d.ctx()
	var main: Node = cx.main if cx != null else null
	return main.get_node_or_null("Screens/DepartureScreen") if main != null else null


## After the last restart: the flag survives, then the playthrough's summary checks (Definition of Done "Gameplay").
func _after_departure() -> bool:
	var c := d.character()
	d.check("the departure flag survives Quit Game and Continue", c.flags.has(FLAG), str(c.flags), ["npc:" + SHANKS, "mechanic:save-load"])
	return true


# =================================================================================================================
# The end: summary checks and the findings
# =================================================================================================================

func _finding(kind: String, what: String, expected: String) -> void:
	var f := {"phase": d.phase, "step": _step, "kind": kind, "map": d.current_map(), "pos": k.local_pos(),
		"play_s": snappedf(k.play_s(), 0.1), "level": d.character().level if d.character() != null else -1, "what": what,
		"expected": expected}
	var all: Array = d.carry.get("findings", [])
	all.append(f)
	d.carry["findings"] = all
	d.note("FINDING [%s] %s in %s at %s: %s (expected: %s)" % [kind, _step, f["map"], f["pos"], what, expected])


## The summary checks (complete = every step ran) and the run's audit rows.
func _finish(complete: bool) -> void:
	var c := d.character()
	k.checkpoint("end of the run" if complete else "the run stopped")
	k.carry_totals()
	var ids := PackedStringArray(db.ids("quests"))
	ids.sort()
	qr.results(ids)
	if not complete:
		return
	var tot: Dictionary = (d.carry.get("totals", {}) as Dictionary).get("sum", {})
	# Every quest.
	var done := Array(ids).filter(func(q: String) -> bool: return c.quests.is_completed(q))
	d.check("every Maple Island quest completed through play (%d of %d)" % [done.size(), ids.size()], done.size() == ids.size(),
		str(Array(ids).filter(func(q: String) -> bool: return not c.quests.is_completed(q))))
	# Every map.
	var visited: Dictionary = d.carry.get("visited_maps", {})
	for m in db.ids("maps"):
		d.check("map %s %s visited on foot" % [m, db.map(m).get("name", "")], visited.has(m), "first at %s s" % visited.get(m, "-"),
			["map:" + m])
	# Every NPC.
	var talked: Dictionary = d.carry.get("talked_to", {})
	for npc in db.ids("npcs"):
		d.check("%s (NPC %s) talked to on foot" % [k.npc_name(npc), npc], talked.has(npc), "%d conversations" % int(talked.get(npc, 0)),
			["npc:" + npc])
	# Every monster type.
	var kills: Dictionary = d.carry.get("kills_by_mob", {})
	for mob in db.ids("monsters"):
		d.check("%s fought and killed (%d kills)" % [k.mob_name(mob), int(kills.get(mob, 0))], int(kills.get(mob, 0)) > 0, "",
			["monster:" + mob])
	# Drops and mesos from monsters.
	d.check("monster drops picked up with Z (%d items)" % int(tot.get("picked_items", 0)), int(tot.get("picked_items", 0)) > 0, str(tot),
		["mechanic:loot-pickup"])
	d.check("mesos from monster meso bags picked up (%d mesos in %d bags)" % [int(tot.get("picked_mesos", 0)),
		int(tot.get("picked_bags", 0))], int(tot.get("picked_mesos", 0)) > 0, str(tot), ["mechanic:meso-pickup"])
	# The progression audit against canonical data: every kill gave its monster's canonical EXP, and every quest its
	# canonical rewards.exp (both heard on the event bus over the whole run).
	var srcs: Dictionary = d.carry.get("exp_by_source", {})
	for mob in db.ids("monsters"):
		var mdef := MonsterDef.from_id(mob, db)
		var per := mdef.exp_reward if mdef != null else -1
		d.check("%s: %d kills gave %d EXP, the canonical %d each" % [k.mob_name(mob), int(kills.get(mob, 0)),
			int(srcs.get("monster:" + mob, 0)), per], int(srcs.get("monster:" + mob, 0)) == per * int(kills.get(mob, 0)), "",
			["monster:" + mob])
	var quest_exp := 0
	var quest_bad := PackedStringArray()
	for qid in ids:
		var want := int((db.quest(qid).get("rewards", {}) as Dictionary).get("exp", 0))
		quest_exp += want
		if int(srcs.get("quest:" + qid, 0)) != want:
			quest_bad.append("%s: %d (canonical %d)" % [qid, int(srcs.get("quest:" + qid, 0)), want])
	d.check("the 20 quests gave their canonical %d EXP in all" % quest_exp, quest_bad.is_empty(), ", ".join(quest_bad))
	# Natural levelling: every EXP award came from a monster kill, a quest reward or a death.
	var odd := (srcs.keys() as Array).filter(func(s: String) -> bool: return not (s.begins_with("monster:") or s.begins_with("quest:") or s == "death"))
	d.check("level %d reached naturally: EXP only from kills, quest rewards and the death penalty" % c.level, odd.is_empty()
		and c.level >= int(_route().get("min_level", 7)), "sources %s" % srcs)
	# AP: every point the levels gave is in the stats.
	var created: Dictionary = d.carry.get("created", {})
	var base0 := 0
	for v: Variant in (created.get("stats", {}) as Dictionary).values():
		base0 += int(v)
	var base1 := 0
	for v: Variant in c.base_stats.values():
		base1 += int(v)
	var per_level := int((db.formula("beginner").get("ap", {}) as Dictionary).get("ap_per_level", 5))
	d.check("every AP spent through the stats window (%d points over %d levels)" % [base1 - base0, c.level - 1], c.ap == 0
		and base1 - base0 == per_level * (c.level - 1), "stats %s -> %s, AP %d" % [created.get("stats", {}), c.base_stats, c.ap],
		["mechanic:ap-allocation"])
	# Skills: learned and really cast (at least one cast that went off; a buff's effect started or its MP spent).
	var cast: Dictionary = d.carry.get("skills_cast", {})
	for sid: String in SKILL_ORDER:
		var row: Dictionary = cast.get(sid, {})
		var went_off := _casts(sid) > 0 and (sid == THREE_SNAILS or bool(row.get("effect", false)) or int(row.get("mp", 0)) > 0)
		d.check("%s learned and cast (%d casts)" % [_skill_name(sid), _casts(sid)], SkillBook.level_of(c, sid) > 0 and went_off,
			str(row), ["skill:" + sid])
	# Shops.
	var shops: Dictionary = d.carry.get("shops", {})
	for npc: String in [PAN, SID, LUCY]:
		var row: Dictionary = shops.get(npc, {})
		var sid := String((db.npc(npc).get("shop", {}) as Dictionary).get("shop_id", ""))
		d.check("%s's shop used: bought and sold" % k.npc_name(npc), not (row.get("bought", []) as Array).is_empty()
			and not (row.get("sold", []) as Array).is_empty(), str(row), ["shop:" + sid])
	# Consumables, equipment, the chair, the death.
	var used: Dictionary = d.carry.get("items_used", {})
	d.check("consumables used (%s)" % str(used), not used.is_empty(), "")
	var eq: Dictionary = d.carry.get("equipped", {})
	d.check("gear equipped (%s)" % str(eq.keys()), not eq.is_empty(), str(eq))
	d.check("The Green Relaxer obtained and sat on", c.inventory.count(CHAIR) > 0 and (d.carry.get("sat", {}) as Dictionary).has(CHAIR),
		str(d.carry.get("sat", {})), ["chair:" + CHAIR])
	var deaths: Array = d.carry.get("deaths", [])
	var resp: Array = d.carry.get("respawns", [])
	d.check("died and respawned (%d deaths, %d respawns)" % [deaths.size(), resp.size()], deaths.size() >= 1 and resp.size() >= deaths.size(),
		str(deaths), ["mechanic:death-respawn"])
	# The final boundary check: tools/parity/parity.mjs DEPARTURE_BOUNDARY_CHECK names it (keep the text in step), and
	# only a report where it passed counts as a clean-character run for the playthrough:* parity rows.
	d.check("ready to depart: the End of Maple Island screen reached in Southperry", c.flags.has(FLAG), "")
	var phases := d.report.phases.size() + 1
	d.check("saved and reloaded during progression (%d processes)" % phases, phases >= 3, "", ["mechanic:save-load"])
	d.note("findings: %s" % str(d.carry.get("findings", [])))
