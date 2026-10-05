extends TestCase
## Every built-in console command, success and failure paths, run headless through Debug.run() on a private
## DebugHarness (its own Debug, MapSession, Game, Saves and Events; no world, so warps complete synchronously).

var h: DebugHarness = null


func before_each() -> void:
	h = DebugHarness.create(db())


func after_each() -> void:
	Engine.time_scale = 1.0
	h.free_all()


func _c() -> CharacterState:
	return h.game.character


# --- maps -----------------------------------------------------------------------------------------------------

func test_warp_reaches_every_one_of_the_25_maps_through_the_command() -> void:
	var defs: MapDefinitions = h.session.call("get_defs")
	assert_eq(defs.ids().size(), 25, "25 maps")
	for id in defs.ids():
		var out := h.run("warp " + id)
		assert_eq(out, "warped to %s %s at player_spawns[0]" % [id, defs.get_def(id).map_name], "warp %s" % id)
		assert_eq(String(h.session.get("current_map")), id, "current map %s" % id)
		assert_eq(String(h.session.call("state_name")), "IDLE", "idle after %s" % id)
		assert_eq((h.session.get("last_transition") as TransitionRecord).via, "debug", "via debug")
		assert_true(h.run("where").begins_with(id), "where names %s" % id)


func test_warp_accepts_v8_ids_names_and_portals() -> void:
	assert_true(h.run("warp 40000").begins_with("warped to 000000040"), "v8 id")
	assert_true(h.run("warp 1").begins_with("warped to 000000001"), "short MeowDB id")
	var tomato: String = (h.session.call("get_defs") as MapDefinitions).id_of_v8["1020001"]
	assert_true(h.run("warp tomato field").begins_with("warped to " + tomato), "multi-word name")
	var def: MapDefinition = (h.session.call("get_defs") as MapDefinitions).get_def("000000040")
	var portal := def.canonical_portals()[0].portal_id
	var out := h.run("warp 000000040 " + portal)
	assert_eq(out, "warped to 000000040 %s at %s's arrival" % [def.map_name, portal], "portal arrival")
	assert_eq((h.session.get("last_arrival") as ArrivalRef).portal_id, portal, "arrived at the portal")
	assert_true(h.run("tp 000000041").begins_with("warped to 000000041"), "tp alias")


func test_warp_failures_change_nothing() -> void:
	h.run("warp 000000040")
	assert_true(h.run("warp").begins_with("usage"), "usage")
	assert_true(h.run("warp atlantis").begins_with("warp: no map matches"), "unknown name")
	assert_true(h.run("warp mushroom town").contains("matches"), "ambiguous name lists candidates")
	assert_true(h.run("warp 000000040 nope").contains("has no portal 'nope'"), "unknown portal")
	h.session.call("enter_dead")
	assert_true(h.run("warp 000000041").begins_with("warp failed:"), "no warp while dead")
	assert_eq(String(h.session.get("current_map")), "000000040", "still in 40")


func test_portals_where_maps_reload_linkmode() -> void:
	assert_true(h.run("portals").contains("no current map"), "portals before any map")
	assert_true(h.run("where").begins_with("no current map"), "where in BOOT")
	h.run("warp 000000040")
	var p := h.run("portals")
	var def: MapDefinition = (h.session.call("get_defs") as MapDefinitions).get_def("000000040")
	assert_true(p.begins_with("000000040 %s: %d portals" % [def.map_name, def.portals.size()]), p)
	for portal in def.portals:
		assert_true(p.contains("  %s -> " % portal.portal_id), "lists %s" % portal.portal_id)
	assert_true(p.contains("arrival gate, walk-only"), "the arrival gate")
	assert_true(h.run("portals 000001020").contains("hidden"), "type-1 portal marked hidden")
	assert_true(h.run("portals nowhere").begins_with("portals: "), "unknown map")
	assert_eq(h.run("maps").split("\n").size(), 25, "maps lists 25")
	var inst: MapInstanceState = h.session.get("instance_state")
	inst.kill(inst.alive_indices()[0], 0.0)
	var r := h.run("reload")
	assert_true(r.begins_with("reloaded 000000040"), r)
	var fresh: MapInstanceState = h.session.get("instance_state")
	assert_eq(fresh.alive_count(), fresh.capacity, "fresh instance full")
	assert_true(h.run("linkmode").contains("links"), "linkmode summary")
	assert_true(h.run("linkmode warp").begins_with("link mode warp for all"), "warp ok")
	assert_true(h.run("linkmode edge").begins_with("link mode edge for all"), "edge for every trail link (M2)")
	assert_true(h.run("linkmode warp T_nope").contains("unknown link"), "unknown link")
	assert_true(h.run("linkmode fly").contains("must be warp or edge"), "bad mode")


func test_reload_and_respawn_failures() -> void:
	assert_true(h.run("reload").begins_with("reload: needs an idle session"), "reload in BOOT")
	h.run("warp 000000040")
	assert_true(h.run("respawn").contains("not dead"), "respawn while alive")
	h.session.call("enter_dead")
	var out := h.run("respawn")
	assert_true(out.begins_with("respawning in"), out)
	assert_eq(String(h.session.call("state_name")), "IDLE", "alive again")


# --- monsters without a world ---------------------------------------------------------------------------------

func test_kill_without_a_world_kills_slots_and_announces_them() -> void:
	assert_true(h.run("kill").contains("no current map"), "no map")
	h.run("warp 000000040")
	var inst: MapInstanceState = h.session.get("instance_state")
	var alive := inst.alive_count()
	var out := h.run("kill nearest")
	assert_true(out.begins_with("killed 1 slot(s) in 000000040"), out)
	assert_eq(inst.alive_count(), alive - 1, "one slot dead")
	assert_eq(h.count("monster_killed"), 1, "monster_killed emitted")
	out = h.run("kill all")
	assert_eq(inst.alive_count(), 0, "all dead")
	assert_eq(h.count("monster_killed"), alive, "one event per kill")
	assert_true(h.run("kill all").contains("no live monsters"), "nothing left")
	assert_true(h.run("kill everyone").begins_with("usage"), "bad mode")


func test_spawn_needs_the_world_and_validates_its_input() -> void:
	h.run("warp 000000040")
	assert_true(h.run("spawn").begins_with("usage"), "usage")
	assert_true(h.run("spawn dragon").contains("no monster matches"), "unknown monster")
	assert_true(h.run("spawn 2 0").contains("n must be"), "count bounds")
	assert_true(h.run("spawn snail 3").contains("needs the world"), "no world")
	var out := h.run("drops 2 200")
	assert_true(out.begins_with("Snail (2), 200 kills"), out)
	assert_eq(out, h.run("drops snail 200"), "deterministic with the default seed")
	assert_true(h.run("drops 2 200 5").contains("seed 5"), "seed argument")
	assert_true(h.run("drops nobody").contains("no monster matches"), "unknown")


# --- character ------------------------------------------------------------------------------------------------

func test_exp_levels_up_through_game() -> void:
	var c := _c()
	assert_true(h.run("exp").begins_with("usage"), "usage")
	assert_true(h.run("exp -5").contains("positive"), "negative refused")
	var need := Progression.exp_to_next(1, db())
	var out := h.run("exp %d" % need)
	assert_eq(c.level, 2, "level 2")
	assert_true(out.contains("level 1 -> 2"), out)
	assert_eq(h.count("leveled_up"), 1, "leveled_up announced")
	assert_true(h.count("exp_gained") >= 1, "exp_gained announced")


func test_level_up_matches_progression_and_level_down_reverses_it() -> void:
	var c := _c()
	var ap0 := c.ap
	var sp0 := c.sp
	var hp0 := c.base_max_hp
	var mp0 := c.base_max_mp
	var out := h.run("level 8")
	assert_eq(c.level, 8, out)
	assert_eq(c.exp, 0, "exactly the EXP of each level")
	var ap := 0
	var sp := 0
	var mhp := 0
	var mmp := 0
	for lv in range(2, 9):
		var g := Progression.level_up_gains(c.job, lv, db())
		ap += int(g.ap)
		sp += int(g.sp)
		mhp += int(g.max_hp)
		mmp += int(g.max_mp)
	assert_eq(c.ap - ap0, ap, "AP from Progression")
	assert_eq(c.sp - sp0, sp, "SP from Progression")
	assert_eq(c.base_max_hp - hp0, mhp, "base max HP")
	assert_eq(c.base_max_mp - mmp, mp0, "base max MP")
	assert_eq(c.base_max_hp, int(Progression.base_max_hp_mp(c.job, 8, db()).max_hp), "matches MeowDB's job HP total")
	assert_eq(h.count("leveled_up"), 7, "one leveled_up per level")
	out = h.run("level 3")
	assert_eq(c.level, 3, out)
	assert_eq(c.base_max_hp, int(Progression.base_max_hp_mp(c.job, 3, db()).max_hp), "HP total back at level 3")
	assert_eq(c.ap - ap0, ap - _sum_gain(c.job, 4, 8, "ap"), "AP taken back")
	assert_true(c.hp <= StatCalculator.max_hp(c, db()), "HP clamped")
	assert_true(h.run("level 3").contains("already 3"), "same level")
	assert_true(h.run("level 0").contains("must be 1.."), "range")
	assert_true(h.run("level x").begins_with("usage"), "usage")


func test_level_down_refuses_when_ap_was_spent() -> void:
	var c := _c()
	h.run("level 5")
	assert_true(h.run("ap str %d" % c.ap).contains("STR"), "spend all AP")
	assert_eq(c.ap, 0, "no AP left")
	var out := h.run("level 2")
	assert_true(out.begins_with("level: cannot go down"), out)
	assert_eq(c.level, 5, "unchanged")
	assert_true(h.run("ap luk 1").begins_with("ap: refused"), "no AP to spend")
	assert_true(h.run("ap hp 1").begins_with("ap: refused"), "HP is not an AP stat")


func test_heal_and_god_mode() -> void:
	var c := _c()
	var mx := StatCalculator.max_hp(c, db())
	c.hp = 1
	c.mp = 0
	assert_true(h.run("heal").begins_with("healed: HP %d/%d" % [mx, mx]), "heal")
	assert_eq(c.hp, mx, "full HP")
	assert_eq(c.mp, StatCalculator.max_mp(c, db()), "full MP")
	assert_true(h.run("god on").begins_with("god mode on"), "god on")
	StatCalculator.change_hp(c, -10, db())
	h.bus.emit_signal("hp_changed", c.hp, mx)
	assert_eq(c.hp, mx, "HP locked at max while god mode is on")
	assert_true(h.run("god off").begins_with("god mode off"), "god off")
	StatCalculator.change_hp(c, -10, db())
	h.bus.emit_signal("hp_changed", c.hp, mx)
	assert_eq(c.hp, mx - 10, "damage sticks again")
	assert_true(h.run("god maybe").begins_with("usage"), "bad toggle")
	h.run("warp 000000040")
	h.session.call("enter_dead")
	assert_true(h.run("heal").contains("dead"), "no heal while dead")


func test_char_and_inv_reports() -> void:
	assert_true(h.run("char").contains("Lv 1"), "char")
	h.run("give 270 3")
	var inv := h.run("inv")
	assert_true(inv.contains("270 Red Potion x3"), inv)
	assert_true(inv.contains("weapon="), "the starter weapon is worn: " + inv)


# --- items ----------------------------------------------------------------------------------------------------

func test_give_by_id_and_name_with_quantities() -> void:
	var c := _c()
	assert_eq(h.run("give 270 5"), "gave 5 x Red Potion (270): 5 in the use tab", "id + qty")
	assert_eq(c.inventory.count("270"), 5, "in the inventory")
	assert_true(h.run("give red potion 2").begins_with("gave 2 x Red Potion"), "name + qty")
	assert_true(h.run("give \"Red Potion\"").begins_with("gave 1 x Red Potion"), "quoted name, default qty 1")
	assert_eq(c.inventory.count("270"), 8, "8 total")
	assert_true(h.count("item_gained") >= 3, "item_gained announced")
	assert_true(h.run("give").begins_with("usage"), "usage")
	assert_true(h.run("give potion").contains("matches"), "ambiguous")
	assert_true(h.run("give unobtainium").contains("no item matches"), "unknown")
	assert_true(h.run("give 270 0").contains("at least 1"), "qty 0")


func test_give_reports_a_full_tab() -> void:
	var c := _c()
	var cap := c.inventory.capacity("equip")
	var free := c.inventory.free_slots("equip")
	var out := h.run("give 541 %d" % (free + 2))
	assert_true(out.contains("of %d" % (free + 2)) and out.contains("full"), out)
	assert_eq(c.inventory.free_slots("equip"), 0, "tab filled (%d slots)" % cap)
	assert_true(h.run("give 541").begins_with("give: no room"), "nothing fits")


func test_mesos_add_spend_and_refuse() -> void:
	var c := _c()
	assert_eq(h.run("mesos 500"), "mesos +500 -> 500", "add")
	assert_eq(h.run("mesos -200"), "mesos -200 -> 300", "spend")
	assert_true(h.run("mesos -1000").begins_with("mesos: cannot spend 1000 (have 300)"), "insufficient")
	assert_eq(c.mesos, 300, "unchanged by the refusal")
	assert_eq(h.run("mesos"), "mesos: 300", "show")
	assert_true(h.run("mesos lots").begins_with("usage"), "usage")
	assert_eq(h.count("mesos_changed") >= 2, true, "mesos_changed announced")


func test_clearinv_one_tab_or_all() -> void:
	var c := _c()
	h.run("give 270 5")
	h.run("give 541 1")
	assert_true(h.run("clearinv use").begins_with("cleared 5 items (1 kinds) from use"), "one tab")
	assert_eq(c.inventory.count("270"), 0, "potions gone")
	assert_eq(c.inventory.count("541"), 1, "equip tab kept")
	h.run("give 270 2")
	assert_true(h.run("clearinv").contains("from every tab"), "all")
	assert_true(c.inventory.is_empty(), "empty")
	assert_false(c.equipment.is_empty(), "equipment untouched")
	assert_true(h.run("clearinv pockets").contains("unknown tab"), "bad tab")


# --- quests ---------------------------------------------------------------------------------------------------

func test_quest_accept_complete_forfeit_reset_through_the_fallback_service() -> void:
	var c := _c()
	assert_true(h.dbg.builtins.fallback_quests != null, "no Game.quests in the harness: the console's own service")
	var out := h.run("quest accept 1006")
	assert_true(out.begins_with("accept 1006 Sam's Suggestion: accepted"), out)
	assert_true(out.contains("fallback"), "the fallback is labelled")
	assert_eq(c.quests.status("1006"), QuestLog.IN_PROGRESS, "in progress")
	assert_true(h.run("quest 1006").contains("monster_kills:2 0/10"), "status through QuestService's own command")
	assert_true(h.run("quest status sam's suggestion").contains("monster_kills:2"), "status by name")
	assert_true(h.run("quest complete 1006").contains("refused"), "objectives not met")
	var exp0 := c.exp
	out = h.run("quest complete 1006 force")
	assert_true(out.begins_with("complete 1006 Sam's Suggestion: completed"), out)
	assert_true(c.quests.is_completed("1006"), "completed")
	assert_true(_heard_with("exp_gained", int(db().quest("1006").rewards.exp)), "canonical EXP reward announced")
	assert_true(c.exp != exp0 or c.level > 1, "EXP applied")
	assert_eq(c.inventory.count("237"), 3, "canonical item reward (3 Eggs)")
	assert_true(h.run("quests").contains("1006"), "quests lists it")
	assert_true(h.run("quest reset 1006").contains("reset 1006"), "reset")
	assert_eq(c.quests.status("1006"), QuestLog.NOT_STARTED, "forgotten")
	h.run("quest accept 1006")
	assert_true(h.run("quest forfeit 1006").begins_with("forfeited 1006"), "forfeit")
	assert_eq(c.quests.status("1006"), QuestLog.NOT_STARTED, "forfeited")
	assert_true(h.run("quest forfeit 1006").contains("refused"), "nothing to forfeit")
	assert_true(h.run("quest accept 99999").contains("no quest matches"), "unknown quest")
	assert_true(h.run("quest accept").begins_with("usage"), "usage")
	assert_true(h.run("quest").begins_with("usage"), "usage")


func test_quest_commands_use_the_games_live_service_when_wired() -> void:
	var w := DebugHarness.create(db(), true)
	if w.game.get("quests") == null:
		print("SKIP test_quest_commands_use_the_games_live_service_when_wired: Game has no wire_quests() yet")
		w.free_all()
		return
	assert_eq(w.dbg.builtins.fallback_quests, null, "no fallback")
	assert_eq(w.dbg.builtins.quest_service(), w.game.get("quests"), "Game.quests")
	var out := w.run("quest accept 1006")
	assert_true(out.contains("accepted") and not out.contains("fallback"), out)
	assert_eq(w.game.character.quests.status("1006"), QuestLog.IN_PROGRESS, "in progress")
	w.free_all()


# --- saves (reused from Game) ---------------------------------------------------------------------------------

func test_save_load_and_reset_reuse_the_games_commands() -> void:
	h.run("warp 000000040")
	h.run("give 270 4")
	assert_eq(h.run("save"), "saved slot1", "Game's save")
	h.run("clearinv")
	assert_eq(h.run("load"), "loaded slot1", "Game's load")
	assert_eq(h.game.character.inventory.count("270"), 4, "loaded inventory")
	var out := h.run("reset")
	assert_true(out.begins_with("reset slot1: new character"), "reset is reset_save: " + out)
	assert_eq(h.game.character.inventory.count("270"), 0, "clean character")
	assert_eq(h.dbg.resolve_name("reset"), "reset_save", "an alias, not a second implementation")


# --- engine ---------------------------------------------------------------------------------------------------

func test_timescale_seed_and_screenshot() -> void:
	assert_eq(h.run("timescale"), "time scale 1.00", "show")
	assert_true(h.run("timescale 0.5").begins_with("time scale 0.50 (was 1.00)"), "set")
	assert_eq(Engine.time_scale, 0.5, "applied")
	assert_true(h.run("timescale 0").contains("must be"), "lower bound")
	assert_true(h.run("timescale 99").contains("must be"), "upper bound")
	assert_true(h.run("timescale fast").begins_with("usage"), "usage")
	Engine.time_scale = 1.0
	assert_true(h.run("seed 1234").contains("seeded with 1234"), "seed")
	assert_eq(h.game.rng.seed, 1234, "Game.rng reseeded")
	var a := h.game.rng.randi()
	h.run("seed 1234")
	assert_eq(h.game.rng.randi(), a, "the same seed replays the same rolls")
	assert_true(h.run("seed").contains("seed 1234"), "show")
	assert_true(h.run("seed x").begins_with("usage"), "usage")
	assert_true(h.run("screenshot").begins_with("screenshot: "), "screenshot answers headless")


# --- overlay and layers without a world -----------------------------------------------------------------------

func test_overlay_text_names_the_map_and_toggles() -> void:
	h.run("warp 000000040")
	var text := h.dbg.overlay_text()
	assert_true(text.contains("MAP  000000040  Snail Hunting Ground I"), text)
	assert_true(text.contains("SESSION IDLE"), "session state")
	assert_true(text.contains("via debug"), "last transition")
	assert_true(text.contains("MOBS live - (capacity"), "monsters without a world")
	assert_true(text.contains("next tick in"), "next spawn tick")
	assert_true(text.contains("PLAYER") and text.contains("HP "), "player line")
	assert_true(h.run("overlay on").contains("000000040"), "overlay on prints it")
	assert_true(h.dbg.overlay_enabled, "on")
	assert_true(h.run("showmap").begins_with("overlay off\n000000040"), "showmap toggles and names the map")
	assert_true(h.run("coords on").contains("POS  (no player)"), "coords without a player")
	assert_true(h.run("overlay sideways").begins_with("usage"), "bad toggle")


func test_layers_toggle_without_a_world() -> void:
	h.run("warp 000000040")
	for pair in [["collision", "collision"], ["spawns", "spawns"], ["portaldata", "portals"], ["npcs", "npcs"],
			["bounds", "camera"], ["mobregion", "mobregion"], ["rings", "rings"], ["safeground", "safeground"]]:
		var out := h.run("%s on" % pair[0])
		assert_true(out.begins_with("%s layer on (no world loaded" % pair[1]), out)
		assert_true(h.dbg.is_layer_on(pair[1]), "%s on" % pair[1])
		assert_eq(h.run("%s off" % pair[0]), "%s layer off" % pair[1], "%s off" % pair[0])
	assert_true(h.run("draw").begins_with("layers: collision off"), "draw lists")
	assert_true(h.run("draw all on").contains("safeground on"), "draw all")
	assert_true(h.run("draw lasers on").contains("unknown layer"), "unknown layer")


func _sum_gain(job: String, from_level: int, to_level: int, key: String) -> int:
	var n := 0
	for lv in range(from_level, to_level + 1):
		n += int(Progression.level_up_gains(job, lv, db())[key])
	return n


## True when `sig` was heard with `first` as its first argument.
func _heard_with(sig: String, first: Variant) -> bool:
	for e in h.heard:
		if e[0] == sig and e[1][0] == first:
			return true
	return false
