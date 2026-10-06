extends PlaytestScenario
## test_d_inventory: brief Test D (inventory), played in the real main scene with real input. A new male Beginner
## (Wooden Club) is warped once to Snail Hunting Ground I (setup: "start near the content"). Everything after that
## is play: Sam's Suggestion (1006) is accepted from Sam on foot, 10 Snails are killed with the attack key, the
## trails 000000040 -> 041 -> 042 -> 050 are walked to Mai, and her canonical reward (3 Eggs) is the consumable: its
## tooltip is checked and it is bound to quickslot 1 by a mouse drag. A Split Road is hunted for mesos (and any potion
## or equipment that drops); every drop is taken with Z (the harness's pickup_all_nearby, then a step onto each drop it
## left). When HP is down by a full restore, an Egg is used by double-clicking it in the inventory, the next time with
## the 1 key (if the hunt never needs them, they are used after it). A trap with no way out is reported as a WARN and
## left by a console warp. The trail to Southperry and the store door lead to Pan, whose shop sells a top and a bottom
## at the canonical price. The top is equipped by double-clicking it in the inventory, the bottom by dragging it onto
## the Equipment window's doll; W.DEF in the Character Stats window must rise by exactly the canonical wdef, the
## Equipment window must list the canonical bonuses, the tooltips must show the canonical item facts, and the Damage
## range must be the canonical stat-window range (also for a dropped Sword / Axe / Blunt, swapped in and out). Dropped
## armour for an empty slot goes on; a dropped piece the character may not wear is refused with the reason. Pause-menu
## Save, Quit to Title and Continue, then Quit Game and a new process (Continue): the inventory, equipment, mesos,
## quickslots, stats and the HUD must persist exactly. Phase 1 uses the quickslot again, fills the Equip tab (console
## give: setup) to show a full tab refusing an unequip and a purchase, sells a piece back to Pan, and the unequip works.

const SNAIL_MAP := "000000040"
const ROUTE_TO_MAI: Array[String] = ["000000040", "000000041", "000000042", "000000050"]
const HUNT_MAP := "000000050"
const TOWN := "000000060"
const STORE := "000000061"
const SAM := "9"
const MAI := "11"
const PAN := "16"
const SHOP := "maple-road-pan"
const QUEST := "1006"
const SNAIL := "2"
const WEAPON := "585"
## Filler for the full Equip tab (Leather Sandals, sold by Pan: it can be sold back to him).
const FILLER := "1305"
const KEY := "1"
## Game seconds spent hunting A Split Road for mesos at most. The Snail drops MeowDB's reported 2 mesos at the owner's
## 60% meso chance (decision D3-12, data/misostory/meso_rules.json). With the earlier 40% chance, seed 1 took 66 kills /
## 548 s for 151 mesos in one run and 94 kills / 1011 s for 158 mesos in another (one death); at 60% the same mesos come
## after about two thirds of the kills. Runs of one seed differ, so the hunt may stop at the budget short of its
## 150-meso goal; the check needs only 2 x Pan's price (100).
const HUNT_BUDGET_S := 1100.0
const PICK_RADIUS_M := 10.0


func description() -> String:
	return "Test D: drops picked with Z, an Egg used by double-click and by quickslot, Pan's top and bottom equipped " \
		+ "through both windows, W.DEF against canonical stats, save / title / continue / process reload, a full tab"


func max_seconds() -> float:
	return 2400.0


func run(d: PlaytestDriver) -> void:
	if d.phase == 0:
		await _phase0(d)
	else:
		await _phase1(d)


# =================================================================================================================
# Phase 0: obtain, pick up, use, equip, verify, save / title / continue, then Quit Game
# =================================================================================================================

func _phase0(d: PlaytestDriver) -> void:
	var db := d.db()
	var ng: Dictionary = await d.new_game("Inventor", "male", WEAPON, {"str": 9})
	if not d.check("new game through the title and creation screens", bool(ng["ok"]) and ng["via"] == "screen",
			"%s via %s %s" % [ng["map"], ng["via"], ng["why"]]):
		return
	var c := d.character()
	var rules := CharacterFactory.rules_table(db)
	var start_mesos := int((rules.get("starting_mesos", {}) as Dictionary).get("value", -1))
	var start_items: Array = (rules.get("starting_inventory", {}) as Dictionary).get("items", [])
	d.check("the new character holds the canonical starting kit", c.mesos == start_mesos and start_items.is_empty()
		and c.inventory.is_empty() and c.equipment.item_in("weapon") == WEAPON,
		"mesos %d (new_character.json %d), inventory empty %s, weapon %s" % [c.mesos, start_mesos, c.inventory.is_empty(),
			c.equipment.item_in("weapon")])

	var acct := _new_account()
	_connect_account(d, acct)

	# --- Setup: start near the content (Sam stands in Snail Hunting Ground I) --------------------------------------
	await d.console("warp " + SNAIL_MAP)
	if not d.check("in Snail Hunting Ground I (setup warp)", d.current_map() == SNAIL_MAP, d.current_map()):
		return

	# --- Sam's Suggestion: accept on foot ----------------------------------------------------------------------------
	var qdef := db.quest(QUEST)
	var need_kills := 0
	for o: Variant in (qdef.get("objectives", {}) as Dictionary).get("monster_kills", []):
		if String((o as Dictionary).get("mob_id", "")) == SNAIL:
			need_kills = int((o as Dictionary).get("count", 0))
	var sam: Dictionary = await d.talk_to(SAM)
	if not d.check("Sam can be talked to on foot", bool(sam["open"]), String(sam.get("why", ""))):
		return
	await _converse(d, "accept")
	if not d.check("Sam's Suggestion (1006) accepted through the dialogue", c.quests.is_in_progress(QUEST),
			"status %s" % c.quests.status(QUEST)):
		return

	# --- 10 Snails with the attack key, every drop taken with Z ------------------------------------------------------
	var snails: Dictionary = await _hunt(d, acct, SNAIL_MAP, func() -> bool: return c.quests.kills(QUEST, SNAIL) >= need_kills,
		300.0, {"mob_id": SNAIL})
	d.check("the canonical %d Snails killed for 1006" % need_kills, c.quests.kills(QUEST, SNAIL) >= need_kills,
		"%d kills counted, %d fights won in %.0f s" % [c.quests.kills(QUEST, SNAIL), int(snails["kills"]), float(snails["time_s"])])

	# --- Walk the trails to Mai (A Split Road) -------------------------------------------------------------------
	for k in range(1, ROUTE_TO_MAI.size()):
		if d.current_map() != ROUTE_TO_MAI[k - 1]:
			break
		var t: Dictionary = await d.walk_trail(ROUTE_TO_MAI[k - 1], ROUTE_TO_MAI[k])
		if not bool(t["ok"]) and d.current_map() == ROUTE_TO_MAI[k - 1]:
			t = await d.walk_trail(ROUTE_TO_MAI[k - 1], ROUTE_TO_MAI[k])
		d.soft_check("walked the trail %s -> %s" % [ROUTE_TO_MAI[k - 1], ROUTE_TO_MAI[k]], bool(t["ok"]),
			"%s via %s; %s" % [t.get("map", ""), t.get("via", ""), "; ".join(t.get("issues", PackedStringArray()))])
	if d.current_map() != HUNT_MAP:
		d.soft_check("reached A Split Road on foot", false, "stuck in %s: warping (setup fallback)" % d.current_map())
		await d.console("warp " + HUNT_MAP)
	if not d.check("in A Split Road", d.current_map() == HUNT_MAP, d.current_map()):
		return

	# --- Mai's turn-in: the canonical reward is the consumable ----------------------------------------------------
	var reward_id := ""
	var reward_qty := 0
	for it: Variant in (qdef.get("rewards", {}) as Dictionary).get("items", []):
		reward_id = String((it as Dictionary).get("item_id", ""))
		reward_qty = int((it as Dictionary).get("count", 0))
	var reward_mesos := int((qdef.get("rewards", {}) as Dictionary).get("mesos", 0))
	var before_reward := c.inventory.count(reward_id)
	var mai: Dictionary = await d.talk_to(MAI)
	if not bool(mai["open"]) and d.game().is_character_dead():
		# A death on the way to Mai (a seed's rolls can leave A Split Road's monsters in the way) is answered as the
		# hunts answer one: the notice's OK, the walk back, then the talk once more.
		d.note("died on the way to Mai: %s" % String(mai.get("why", "")))
		await _respawn(d, acct, HUNT_MAP)
		mai = await d.talk_to(MAI)
	if d.check("Mai can be talked to on foot", bool(mai["open"]), String(mai.get("why", ""))):
		await _converse(d, "complete")
	d.check("1006 completed at Mai: the canonical %d x %s" % [reward_qty, _name(d, reward_id)],
		c.quests.is_completed(QUEST) and c.inventory.count(reward_id) - before_reward == reward_qty,
		"status %s, %s %d -> %d" % [c.quests.status(QUEST), reward_id, before_reward, c.inventory.count(reward_id)])
	acct["reward"] = {"item_id": reward_id, "qty": reward_qty if c.quests.is_completed(QUEST) else 0,
		"mesos": reward_mesos if c.quests.is_completed(QUEST) else 0}

	# --- The consumable: its tooltip, and quickslot 1 bound by a mouse drag, before the hunt --------------------------
	var use_id := _best_consumable(d)
	if not d.check("a consumable in the Use tab (at least 2 to use twice)", use_id != "" and c.inventory.count(use_id) >= 2,
			"%s x%d" % [use_id, c.inventory.count(use_id) if use_id != "" else 0]):
		return
	await _consumable_setup(d, use_id)
	acct["use_id"] = use_id
	acct["use_stage"] = 0

	# --- Hunt A Split Road for mesos (the consumable is used when hurt: double-click first, then the quickslot) ------
	var price := int(ShopService.row_for(SHOP, _pick_piece(d, "top"), db).get("price", 0))
	var goal := price * 3  # a top and a bottom, and one more purchase for the full-tab check in phase 1
	var hunt: Dictionary = await _hunt(d, acct, HUNT_MAP, func() -> bool: return c.mesos >= goal, HUNT_BUDGET_S, {})
	d.note("hunted %s: %d kills in %.0f s, %d deaths, %d traps %s; mesos %d (goal %d = 3 x Pan's %d)" % [HUNT_MAP, int(hunt["kills"]),
		float(hunt["time_s"]), int(acct["deaths"]), (acct["traps"] as Array).size(), acct["traps"], c.mesos, goal, price])
	d.check("mesos for two pieces earned by hunting", c.mesos >= price * 2, "%d mesos, %d needed" % [c.mesos, price * 2])
	_check_pickups(d, acct, start_mesos)
	# A use the hunt never needed (HP never fell by a full restore) happens now; the restore may then be capped.
	if int(acct["use_stage"]) < 1:
		await _use_by_double_click(d, acct, "after the hunt")
	if int(acct["use_stage"]) < 2:
		await _use_by_quickslot(d, acct, "after the hunt")

	# --- Southperry, the store door, Pan's shop ----------------------------------------------------------------------
	var tr: Dictionary = await d.walk_trail(HUNT_MAP, TOWN)
	if not bool(tr["ok"]) and d.current_map() == HUNT_MAP:
		await _unstick(d, acct, HUNT_MAP)
		tr = await d.walk_trail(HUNT_MAP, TOWN)
	if not d.check("walked the trail to Southperry", d.current_map() == TOWN, "%s; %s" % [d.current_map(),
			"; ".join(tr.get("issues", PackedStringArray()))]):
		return
	var door: Dictionary = await d.enter_portal(STORE)
	if not d.check("Up at the store door leads into the Southperry Armor Store", d.current_map() == STORE,
			"%s via %s %s" % [door.get("to", ""), door.get("via", ""), "; ".join(door.get("issues", PackedStringArray()))]):
		return
	var top := _pick_piece(d, "top")
	var bottom := _pick_piece(d, "bottom")
	if not await _open_pan(d):
		return
	var rows: Array = d.shop().get("buy_rows")
	var canon_ok := true
	var canon_txt := PackedStringArray()
	for raw: Variant in db.shop(SHOP).get("items", []):
		var cr := raw as Dictionary
		for r: Variant in rows:
			if String((r as Dictionary).get("item_id", "")) == String(cr.get("item_id", "")):
				var ok := int((r as Dictionary).get("price", -1)) == int(cr.get("price_mesos", -2))
				canon_ok = canon_ok and ok
				if not ok:
					canon_txt.append("%s %s != %s" % [cr.get("item_id"), (r as Dictionary).get("price"), cr.get("price_mesos")])
	d.check("Pan's shop lists the canonical stock and prices", canon_ok and rows.size() == (db.shop(SHOP).get("items", []) as Array).size(),
		"%d rows; %s" % [rows.size(), ", ".join(canon_txt)])
	for piece in [top, bottom]:
		var m0 := c.mesos
		var b: Dictionary = await d.shop_buy(piece, 1)
		var cost := int(ShopService.row_for(SHOP, piece, db).get("price", 0))
		d.check("bought %s for the canonical %d mesos" % [_name(d, piece), cost], bool(b["ok"]) and int(b["mesos_delta"]) == -cost
			and int(b["count_delta"]) == 1 and c.mesos == m0 - cost, "%s (mesos %+d, count %+d)" % [b["message"],
				int(b["mesos_delta"]), int(b["count_delta"])])
	await d.close_shop()

	await _equip_section(d, top, bottom)
	await _dropped_equipment_section(d, [top, bottom])

	# Observation (not Test D): standing still in town with HP below the maximum. Natural recovery is the project
	# owner's rule (misostory/recovery.json natural_hp: 10 HP per 10 s of standing still or sitting; MeowDB publishes
	# no rate), so 60 s still must heal.
	var hp_a := d.character().hp
	var max_a := StatCalculator.max_hp(d.character(), db)
	if hp_a < max_a:
		await d.wait(60.0)
		d.soft_check("HP recovers while standing still (natural recovery, misostory/recovery.json natural_hp)",
			d.character().hp > hp_a, "HP %d / %d before and %d / %d after 60 s standing in %s" % [hp_a, max_a, d.character().hp,
				StatCalculator.max_hp(d.character(), db), d.current_map()])
	else:
		d.note("HP is full (%d): natural recovery not observable here" % hp_a)

	# --- Save, Quit to Title, Continue ------------------------------------------------------------------------------
	var saved: Dictionary = await d.save_game()
	d.check("the pause menu's Save writes the slot", bool(saved["ok"]), "%s %s" % [saved["slot"], saved["status"]])
	var snap: Dictionary = await _capture(d)
	var q: Dictionary = await d.quit_to_title()
	if not d.check("Quit to Title", bool(q["ok"]), str(q)):
		return
	var cont: Dictionary = await d.continue_game()
	if not d.check("Continue loads the game", bool(cont["ok"]) and cont["via"] == "screen", "%s in %s via %s" % [cont["slot"],
			cont["map"], cont["via"]]):
		return
	var after: Dictionary = await _capture(d)
	_compare(d, "after Quit to Title and Continue", snap, after)
	d.carry["snap"] = after
	d.carry["top"] = top
	d.carry["bottom"] = bottom
	d.carry["use_id"] = use_id
	d.carry["phase0_map"] = d.current_map()
	await d.reload_process()


# =================================================================================================================
# Phase 1: a new process, Continue, everything persists; the quickslot after the reload; a full Equip tab
# =================================================================================================================

func _phase1(d: PlaytestDriver) -> void:
	var db := d.db()
	var cont: Dictionary = await d.continue_game()
	if not d.check("Continue in a new process", bool(cont["ok"]) and cont["via"] == "screen", "%s in %s" % [cont["slot"], cont["map"]]):
		return
	var snap: Dictionary = d.carry.get("snap", {})
	var after: Dictionary = await _capture(d)
	_compare(d, "after Quit Game and a new process", snap, after)
	d.check("the game resumes in the map it was saved in", d.current_map() == String(d.carry.get("phase0_map", "")),
		"%s, saved in %s" % [d.current_map(), d.carry.get("phase0_map", "")])
	var c := d.character()
	var top := String(d.carry.get("top", ""))
	var use_id := String(d.carry.get("use_id", ""))

	# The quickslot binding still works after the reload.
	if c.inventory.count(use_id) > 0:
		var r := _press_quickslot(d, use_id)
		d.check("quickslot %s still uses %s after the reload" % [KEY, _name(d, use_id)], bool(r["ok"]), String(r["why"]))
		await d.frames(2)

	# --- A full Equip tab ---------------------------------------------------------------------------------------------
	var free := c.inventory.free_slots("equip")
	var cap := c.inventory.capacity("equip")
	d.note("setup: the Equip tab has %d of %d slots free; filling them with console give (24 purchases would cost %d mesos)"
		% [free, cap, cap * int(ShopService.row_for(SHOP, FILLER, db).get("price", 0))])
	if free > 0:
		await d.console("give %s %d" % [FILLER, free])
	d.check("the Equip tab is full", c.inventory.is_full("equip"), "%d free of %d" % [c.inventory.free_slots("equip"), cap])
	var filler_slots := 0
	for i in cap:
		if String(c.inventory.get_slot("equip", i).get("item_id", "")) == FILLER:
			filler_slots += 1
	d.check("equipment never stacks: %d %s take %d slots" % [c.inventory.count(FILLER), _name(d, FILLER), filler_slots],
		filler_slots == c.inventory.count(FILLER) and filler_slots >= free, "inventory.json equipment_max_stack (adaptation) = %s" %
			str((db.miso_table("inventory") as Dictionary).get("equipment_max_stack", "?")) if db.miso_table("inventory") is Dictionary else "")
	var wr := d.windows() as MisoWindowsRoot
	await d.open_window("inventory")
	await d.click(wr.inventory.tab_buttons["equip"])
	await d.frames(2)
	d.check("the inventory window shows every Equip slot filled", not ("" in Array(wr.inventory.visible_item_ids()))
		and wr.inventory.visible_item_ids().size() == cap, "%d slots shown" % wr.inventory.visible_item_ids().size())
	await d.open_window("equipment")
	await d.open_window("stats")
	await d.frames(2)
	var wdef0 := int(_stat_texts(d).get("wdef", "-1"))
	var inv0 := c.inventory.to_dict()
	var top_slot: MisoItemSlot = wr.equipment.slot_controls["top"]
	await _double_click(d, top_slot)
	await d.frames(2)
	var status := String(wr.equipment.status_label.text)
	d.check("double-clicking the equipped top with a full Equip tab is refused and it stays on",
		c.equipment.item_in("top") == top and PlaytestDriver.diff(inv0, c.inventory.to_dict()) == ""
		and int(_stat_texts(d).get("wdef", "-2")) == wdef0, "top %s, W.DEF %s (was %d), status '%s'" % [
			c.equipment.item_in("top"), _stat_texts(d).get("wdef", "?"), wdef0, status])
	d.check("the Equipment window says why", status.to_lower().contains("full"), status)
	await d.screenshot("full_tab_refused")

	# Pan: a purchase into the full tab is refused (when the mesos are there: mesos are checked before space).
	await d.close_window("stats")
	await d.close_window("equipment")
	await d.close_window("inventory")
	if not await _open_pan(d):
		return
	var price := int(ShopService.row_for(SHOP, FILLER, db).get("price", 0))
	if c.mesos >= price:
		var m0 := c.mesos
		var b: Dictionary = await d.shop_buy(FILLER, 1)
		d.check("buying into a full Equip tab is refused and costs nothing", not bool(b["ok"])
			and String((b["result"] as Dictionary).get("code", "")) == ItemCodes.INVENTORY_FULL and c.mesos == m0
			and int(b["count_delta"]) == 0, "%s (code %s, mesos %+d)" % [b["message"], (b["result"] as Dictionary).get("code", ""),
				c.mesos - m0])
	else:
		d.soft_check("mesos left for the full-tab purchase check", false, "%d mesos, a purchase costs %d" % [c.mesos, price])
	var m1 := c.mesos
	var s: Dictionary = await d.shop_sell(FILLER, 1)
	var sell_price := ShopService.sell_price(FILLER, db)
	d.check("sold one %s back to Pan at the canonical price" % _name(d, FILLER), bool(s["ok"]) and int(s["count_delta"]) == -1
		and c.mesos - m1 == sell_price, "%s (mesos %+d, canonical %d)" % [s["message"], c.mesos - m1, sell_price])
	await d.close_shop()

	# One free slot: the unequip now works, then the top goes back on from the (again full) tab.
	await d.open_window("inventory")
	await d.open_window("equipment")
	await d.open_window("stats")
	await d.frames(2)
	var n_top := c.inventory.count(top)
	await _double_click(d, wr.equipment.slot_controls["top"])
	await d.frames(2)
	var wdef_top := _wdef(d, top)
	d.check("with a free slot the top comes off into the Equip tab", c.equipment.item_in("top") == "" and c.inventory.count(top) == n_top + 1
		and c.inventory.is_full("equip") and int(_stat_texts(d).get("wdef", "-1")) == wdef0 - wdef_top,
		"top '%s', %s x%d, W.DEF %s (was %d, canonical wdef %d)" % [c.equipment.item_in("top"), top, c.inventory.count(top),
			_stat_texts(d).get("wdef", "?"), wdef0, wdef_top])
	await d.click(wr.inventory.tab_buttons["equip"])
	await d.frames(2)
	var idx := _slot_index(d, "equip", top)
	if idx >= 0:
		await _double_click(d, wr.inventory.slots[idx])
		await d.frames(2)
	d.check("and goes back on from the full tab by double-click", c.equipment.item_in("top") == top
		and int(_stat_texts(d).get("wdef", "-1")) == wdef0, "top '%s', W.DEF %s" % [c.equipment.item_in("top"),
			_stat_texts(d).get("wdef", "?")])
	var saved: Dictionary = await d.save_game()
	d.check("saved at the end", bool(saved["ok"]), String(saved["slot"]))
	var errs := PackedStringArray()
	for e: Variant in d.report.engine_errors:
		if errs.size() < 4:
			errs.append(String((e as Dictionary).get("message", "")).left(140))
	d.soft_check("no engine errors or warnings during the run", d.report.engine_errors.is_empty(),
		"%d: %s" % [d.report.engine_errors.size(), " | ".join(errs)])


# =================================================================================================================
# Sections
# =================================================================================================================

## The consumable before the hunt: shown in the Use tab, its tooltip against canonical data, and bound to quickslot 1
## by a real mouse drag from the inventory onto the HUD.
func _consumable_setup(d: PlaytestDriver, use_id: String) -> void:
	var c := d.character()
	var db := d.db()
	var wr := d.windows() as MisoWindowsRoot
	var item := db.item(use_id)
	var restore := _restore(d, use_id)
	await d.open_window("inventory")
	await d.click(wr.inventory.tab_buttons["use"])
	await d.frames(2)
	var idx := _slot_index(d, "use", use_id)
	if not d.check("the inventory window shows %s x%d in one Use slot" % [_name(d, use_id), c.inventory.count(use_id)], idx >= 0
			and wr.inventory.slots[idx].item_id == use_id and wr.inventory.slots[idx].qty == c.inventory.count(use_id),
			"slot %d" % idx):
		return
	var slot: MisoItemSlot = wr.inventory.slots[idx]
	var tip: Array = await _tooltip_rows(d, slot)
	var price := int(item.get("sell_price_mesos", -1))
	d.check("the tooltip shows %s's canonical name, effect, description and price" % _name(d, use_id),
		_has_row(tip, String(item.get("name", "?"))) and _has_row(tip, "Recovers %d HP" % restore)
		and _has_row(tip, String(item.get("description", "?")).strip_edges().left(30)) and _has_row(tip, "Sells for %d mesos" % price),
		" / ".join(_row_texts(tip)))
	await d.screenshot("inventory_tooltip_use")
	var qs: MisoItemSlot = _hud(d).status.quickslots.slots[KEY]
	var dr: Dictionary = await _drag(d, slot, qs)
	d.check("a mouse drag from the inventory binds %s to quickslot %s" % [_name(d, use_id), KEY], bool(dr["dragging"])
		and MisoQuickslots.item_for(c, KEY) == use_id, "drag ran %s, target topmost %s, binding '%s'" % [dr["dragging"],
			dr["target_topmost"], MisoQuickslots.item_for(c, KEY)])
	await d.frames(2)
	d.check("quickslot %s shows the inventory count" % KEY, _hud(d).status.quickslots.count_text(KEY) == str(c.inventory.count(use_id)),
		"'%s' vs %d" % [_hud(d).status.quickslots.count_text(KEY), c.inventory.count(use_id)])
	var tipq: Array = await _tooltip_rows(d, qs)
	d.check("hovering the quickslot shows the item's tooltip", _has_row(tipq, String(item.get("name", "?"))),
		" / ".join(_row_texts(tipq)))
	await d.screenshot("quickslot_bound")
	await d.close_window("inventory")


## During the hunt: once HP is down by at least a full canonical restore, the consumable is used, by double-click
## in the inventory the first time and by the quickslot key the second time (one is kept for after the reload).
func _maybe_use(d: PlaytestDriver, acct: Dictionary) -> void:
	var id := String(acct.get("use_id", ""))
	var c := d.character()
	if id == "" or int(acct.get("use_stage", 2)) >= 2 or d.game().is_character_dead() or c.inventory.count(id) < 2:
		return
	if c.hp > StatCalculator.max_hp(c, d.db()) - _restore(d, id):
		return
	if int(acct["use_stage"]) == 0:
		await _use_by_double_click(d, acct, "while hurt")
	else:
		await _use_by_quickslot(d, acct, "while hurt")


## Opens the inventory's Use tab and double-clicks the consumable: one used, HP + the canonical restore (capped).
func _use_by_double_click(d: PlaytestDriver, acct: Dictionary, when: String) -> void:
	var id := String(acct["use_id"])
	var c := d.character()
	var db := d.db()
	var wr := d.windows() as MisoWindowsRoot
	var restore := _restore(d, id)
	await d.open_window("inventory")
	await d.click(wr.inventory.tab_buttons["use"])
	await d.frames(2)
	var idx := _slot_index(d, "use", id)
	acct["use_stage"] = 1
	if not d.check("%s is in the Use tab to double-click (%s)" % [_name(d, id), when], idx >= 0, "slot %d" % idx):
		return
	var max_hp := StatCalculator.max_hp(c, db)
	var dc: Dictionary = await _double_click(d, wr.inventory.slots[idx], func() -> Dictionary: return {"hp": c.hp, "n": c.inventory.count(id)})
	var b: Dictionary = dc["before"]
	var a: Dictionary = dc["after"]
	_count_used(acct, id, int(b["n"]) - int(a["n"]))
	d.check("double-clicking %s in the inventory (%s) uses one: HP %d + canonical %d (Max HP %d)" % [_name(d, id), when,
		int(b["hp"]), restore, max_hp], int(a["n"]) == int(b["n"]) - 1 and int(a["hp"]) == mini(max_hp, int(b["hp"]) + restore),
		"HP %d -> %d, count %d -> %d, status '%s'" % [int(b["hp"]), int(a["hp"]), int(b["n"]), int(a["n"]), wr.inventory.status_label.text])
	await d.frames(2)
	var j := _slot_index(d, "use", id)
	d.check("the slot and quickslot %s show the stack after the use" % KEY, j >= 0 and wr.inventory.slots[j].qty == c.inventory.count(id)
		and _hud(d).status.quickslots.count_text(KEY) == str(c.inventory.count(id)), "bag %d, slot %s, quickslot '%s'" % [
			c.inventory.count(id), str(wr.inventory.slots[j].qty) if j >= 0 else "-", _hud(d).status.quickslots.count_text(KEY)])
	await d.close_window("inventory")


## Presses the quickslot key: one used, HP + the canonical restore (capped), the HUD count follows.
func _use_by_quickslot(d: PlaytestDriver, acct: Dictionary, when: String) -> void:
	var id := String(acct["use_id"])
	var c := d.character()
	acct["use_stage"] = 2
	var r := _press_quickslot(d, id)
	_count_used(acct, id, int(r["used"]))
	d.check("the %s key (%s) uses %s from the quickslot" % [KEY, when, _name(d, id)], bool(r["ok"]), String(r["why"]))
	await d.frames(2)
	d.check("quickslot %s's count follows" % KEY, _hud(d).status.quickslots.count_text(KEY) == str(c.inventory.count(id)),
		"'%s' vs %d" % [_hud(d).status.quickslots.count_text(KEY), c.inventory.count(id)])


static func _count_used(acct: Dictionary, id: String, n: int) -> void:
	var used: Dictionary = acct.get("used", {})
	used[id] = int(used.get(id, 0)) + n
	acct["used"] = used


func _restore(d: PlaytestDriver, id: String) -> int:
	return int((d.db().item(id).get("consumable", {}) as Dictionary).get("hp_restore", 0))


## Equips the top by double-click in the inventory and the bottom by a drag onto the Equipment window, checking the
## Stats and Equipment windows and the tooltips against canonical item stats.
func _equip_section(d: PlaytestDriver, top: String, bottom: String) -> void:
	var c := d.character()
	var db := d.db()
	var wr := d.windows() as MisoWindowsRoot
	var wdef_top := _wdef(d, top)
	var wdef_bottom := _wdef(d, bottom)
	var watk := int((db.item(WEAPON).get("stats", {}) as Dictionary).get("watk", -1))
	await d.open_window("stats")
	await d.open_window("inventory")
	await d.click(wr.inventory.tab_buttons["equip"])
	await d.frames(2)
	var st0 := _stat_texts(d)
	var wdef0 := int(st0.get("wdef", "-1"))
	d.check("the stats window's W.DEF is the calculator's before equipping", wdef0 == int(StatCalculator.snapshot(c, db)["wdef"]),
		"window %d" % wdef0)

	# Tooltip of the top, in the Equip tab.
	var idx := _slot_index(d, "equip", top)
	if not d.check("the inventory window shows %s in the Equip tab" % _name(d, top), idx >= 0, "slot %d" % idx):
		return
	var it := db.item(top)
	var tip: Array = await _tooltip_rows(d, wr.inventory.slots[idx])
	var upg := int((it.get("stats", {}) as Dictionary).get("upgrade_slots", 0))
	var g := String(it.get("gender", ""))
	d.check("the tooltip shows %s's canonical name, W.DEF %d, %d upgrades and price" % [_name(d, top), wdef_top, upg],
		_has_row(tip, String(it.get("name", "?"))) and _has_row(tip, "Weapon Def.: +%d" % wdef_top)
		and _has_row(tip, "upgrades available: %d" % upg) and _has_row(tip, "Sells for %d mesos" % int(it.get("sell_price_mesos", -1)))
		and (g in ["", "any"] or _has_row(tip, "For %s characters" % g)), " / ".join(_row_texts(tip)))

	# Double-click: equipped. (Counts are relative: the same piece may also have dropped.)
	var n_top := c.inventory.count(top)
	var n_bottom := c.inventory.count(bottom)
	await _double_click(d, wr.inventory.slots[idx])
	await d.frames(3)
	var st1 := _stat_texts(d)
	d.check("double-clicking %s in the inventory equips it" % _name(d, top), c.equipment.item_in("top") == top
		and c.inventory.count(top) == n_top - 1, "top '%s', %s in the bag %d -> %d, status '%s'" % [c.equipment.item_in("top"), top,
			n_top, c.inventory.count(top), wr.inventory.status_label.text])
	d.check("Character Stats: W.DEF %d + canonical %d" % [wdef0, wdef_top], int(st1.get("wdef", "-1")) == wdef0 + wdef_top,
		"W.DEF %s" % st1.get("wdef", "?"))
	d.check("Character Stats: STR/DEX/INT/LUK and Damage unchanged by armour", _same_keys(st0, st1, ["str", "dex", "int", "luk", "damage", "acc", "avoid"]),
		"before %s / after %s" % [st0, st1])

	# Drag the bottom onto the Equipment window's doll.
	await d.open_window("equipment")
	await d.frames(2)
	idx = _slot_index(d, "equip", bottom)
	var target: MisoItemSlot = wr.equipment.slot_controls.get("bottom")
	if not d.check("the bottom is in the Equip tab and the doll has a bottom slot", idx >= 0 and target != null, "slot %d" % idx):
		return
	var dr: Dictionary = await _drag(d, wr.inventory.slots[idx], target)
	await d.frames(3)
	var st2 := _stat_texts(d)
	d.check("dragging %s onto the Equipment window's bottom slot equips it" % _name(d, bottom), bool(dr["dragging"])
		and c.equipment.item_in("bottom") == bottom and c.inventory.count(bottom) == n_bottom - 1, "drag %s, topmost %s, bottom '%s', %s in the bag %d -> %d, status '%s'" % [
			dr["dragging"], dr["target_topmost"], c.equipment.item_in("bottom"), bottom, n_bottom, c.inventory.count(bottom),
			wr.equipment.status_label.text])
	d.check("Character Stats: W.DEF %d + %d + %d (canonical)" % [wdef0, wdef_top, wdef_bottom],
		int(st2.get("wdef", "-1")) == wdef0 + wdef_top + wdef_bottom, "W.DEF %s" % st2.get("wdef", "?"))
	var bonus: Dictionary = wr.equipment.bonus_lines()
	d.check("Equipment bonuses: W.ATK %d (Wooden Club) and W.DEF %d (top + bottom), canonical" % [watk, wdef_top + wdef_bottom],
		int(bonus.get("watk", -1)) == watk and int(bonus.get("wdef", -1)) == wdef_top + wdef_bottom, str(bonus))
	var tip_eq: Array = await _tooltip_rows(d, wr.equipment.slot_controls["top"])
	d.check("the equipped top's tooltip says Equipped", _has_row(tip_eq, "Equipped") and _has_row(tip_eq, String(it.get("name", "?"))),
		" / ".join(_row_texts(tip_eq)))
	await d.screenshot("equipped_windows")

	# Take the bottom off from the doll and put it back from the bag.
	await _double_click(d, wr.equipment.slot_controls["bottom"])
	await d.frames(3)
	d.check("double-clicking the bottom on the doll takes it off", c.equipment.item_in("bottom") == "" and c.inventory.count(bottom) == n_bottom
		and int(_stat_texts(d).get("wdef", "-1")) == wdef0 + wdef_top, "bottom '%s', W.DEF %s" % [c.equipment.item_in("bottom"),
			_stat_texts(d).get("wdef", "?")])
	idx = _slot_index(d, "equip", bottom)
	if idx >= 0:
		await _double_click(d, wr.inventory.slots[idx])
		await d.frames(3)
	d.check("and double-clicking it in the bag puts it back on", c.equipment.item_in("bottom") == bottom
		and int(_stat_texts(d).get("wdef", "-1")) == wdef0 + wdef_top + wdef_bottom, "bottom '%s', W.DEF %s" % [
			c.equipment.item_in("bottom"), _stat_texts(d).get("wdef", "?")])
	await d.close_window("equipment")
	await d.close_window("inventory")


## The Wooden Club's Damage range against the canonical formula, then the equipment that dropped: a Sword / Axe /
## Blunt weapon is swapped in by double-click (W.ATK and the Damage range against canonical data), then the club goes
## back on; an armour piece for an empty slot goes on by double-click (W.DEF + its canonical wdef).
func _dropped_equipment_section(d: PlaytestDriver, bought: Array) -> void:
	var c := d.character()
	var db := d.db()
	var wr := d.windows() as MisoWindowsRoot
	await d.open_window("stats")
	await d.open_window("inventory")
	await d.open_window("equipment")
	await d.click(wr.inventory.tab_buttons["equip"])
	await d.frames(2)
	var club := _canonical_window(d, WEAPON, WEAPON)
	d.check("Character Stats: the Wooden Club's Damage is the canonical stat-window range %d ~ %d" % [int(club["min"]), int(club["max"])],
		String(_stat_texts(d).get("damage", "")) == "%d ~ %d" % [int(club["min"]), int(club["max"])],
		"window '%s'; %s" % [_stat_texts(d).get("damage", ""), club.get("why", "")])
	var weapon_done := false
	var refused_seen := {}
	var dropped := PackedStringArray()
	for i in c.inventory.capacity("equip"):
		var id := String(c.inventory.get_slot("equip", i).get("item_id", ""))
		if id == "" or id in bought:
			continue
		dropped.append(id)
	for id in dropped:
		var def := ItemDef.of(id, db)
		if def == null or not c.equipment.can_equip(c, id, db):
			var code := String(c.equipment.equip_check(c, id, db).get("code", ""))
			d.note("dropped %s %s is not wearable now: %s" % [id, _name(d, id), code])
			var ri := _slot_index(d, "equip", id)
			if def != null and ri >= 0 and not refused_seen.has(code):
				refused_seen[code] = true
				var eq0 := c.equipment.to_dict()
				var inv0 := c.inventory.to_dict()
				await _double_click(d, wr.inventory.slots[ri])
				await d.frames(2)
				var msg := String(wr.inventory.status_label.text)
				var want := "level %d" % def.req_level if code == ItemCodes.LEVEL_TOO_LOW else ("gender" if code == ItemCodes.GENDER_MISMATCH else "")
				d.check("double-clicking the dropped %s is refused (%s): nothing changes and the window says why" % [def.name, code],
					PlaytestDriver.diff(eq0, c.equipment.to_dict()) == "" and PlaytestDriver.diff(inv0, c.inventory.to_dict()) == ""
					and msg != "" and msg.to_lower().contains(want.to_lower()), "status '%s' (expected to mention '%s')" % [msg, want])
			continue
		if def.is_weapon() and not weapon_done:
			var w := _canonical_window(d, id, id)
			if w.is_empty():
				d.note("dropped weapon %s %s: no canonical stat-window rule covered here (%s)" % [id, def.name, def.subtype])
				continue
			weapon_done = true
			var n_w := c.inventory.count(id)
			var idx := _slot_index(d, "equip", id)
			await _double_click(d, wr.inventory.slots[idx])
			await d.frames(3)
			var watk := int((db.item(id).get("stats", {}) as Dictionary).get("watk", -1))
			d.check("double-clicking the dropped %s equips it: W.ATK %d and Damage %d ~ %d (canonical)" % [def.name, watk,
				int(w["min"]), int(w["max"])], c.equipment.item_in("weapon") == id and int(wr.equipment.bonus_lines().get("watk", -1)) == watk
				and String(_stat_texts(d).get("damage", "")) == "%d ~ %d" % [int(w["min"]), int(w["max"])],
				"weapon %s, bonuses %s, Damage '%s'; %s" % [c.equipment.item_in("weapon"), wr.equipment.bonus_lines(),
					_stat_texts(d).get("damage", ""), w.get("why", "")])
			var ci := _slot_index(d, "equip", WEAPON)
			if ci >= 0:
				await _double_click(d, wr.inventory.slots[ci])
				await d.frames(3)
			d.check("the Wooden Club goes back on from the bag (the %s returns to it)" % def.name, c.equipment.item_in("weapon") == WEAPON
				and c.inventory.count(id) == n_w and String(_stat_texts(d).get("damage", "")) == "%d ~ %d" % [int(club["min"]), int(club["max"])],
				"weapon %s, %s in bag %d, Damage '%s'" % [c.equipment.item_in("weapon"), id, c.inventory.count(id), _stat_texts(d).get("damage", "")])
		elif not def.is_weapon() and def.equip_slot in ["hat", "top", "bottom", "overall", "shoes", "gloves", "cape"] \
				and c.equipment.item_in(def.equip_slot) == "":
			var w0 := int(_stat_texts(d).get("wdef", "-1"))
			var idx := _slot_index(d, "equip", id)
			await _double_click(d, wr.inventory.slots[idx])
			await d.frames(3)
			d.check("double-clicking the dropped %s equips it: W.DEF %d + canonical %d" % [def.name, w0, _wdef(d, id)],
				c.equipment.item_in(def.equip_slot) == id and int(_stat_texts(d).get("wdef", "-1")) == w0 + _wdef(d, id),
				"%s '%s', W.DEF %s" % [def.equip_slot, c.equipment.item_in(def.equip_slot), _stat_texts(d).get("wdef", "?")])
	if dropped.is_empty():
		d.note("no equipment dropped in this run (Maple Island equipment drops at the owner's table chance, 0.1% for a Common equip, decision D3-11): Pan's pieces are the equipment")
	await d.close_window("equipment")
	await d.close_window("inventory")
	await d.close_window("stats")


## The canonical stat-window Damage range (formulas/damage.json physical: MIN / MAX, stat_window_range's split-action
## rule, no mastery, final clamp) for the character holding `weapon_id` (its canonical watk replacing the worn weapon's).
## {} when the weapon's family is not Sword / Axe / Blunt (STR primary, DEX secondary).
func _canonical_window(d: PlaytestDriver, weapon_id: String, _label: String) -> Dictionary:
	var c := d.character()
	var db := d.db()
	var phys: Dictionary = db.formula("damage").get("physical", {})
	var it := db.item(weapon_id)
	# The canonical item subtype -> the canonical multiplier table's row (its own labels: "1H Sword", "1H Axe / Blunt").
	var rows := {"One-Handed Sword": "one_handed_sword", "One-Handed Axe": "one_handed_axe_or_blunt",
		"One-Handed Blunt Weapon": "one_handed_axe_or_blunt"}
	var key := String(rows.get(String(it.get("subtype", "")), ""))
	if key == "":
		return {}
	var mults: Dictionary = (phys.get("weapon_action_multipliers", {}) as Dictionary).get(key, {})
	var lo := INF
	var hi := -INF
	for a in ["swing", "stab"]:
		if mults.get(a) != null:
			lo = minf(lo, float(mults[a]))
			hi = maxf(hi, float(mults[a]))
	var watk := float((it.get("stats", {}) as Dictionary).get("watk", 0))
	for slot: String in c.equipment.equipped():
		if slot != "weapon":
			watk += float((db.item(c.equipment.item_in(slot)).get("stats", {}) as Dictionary).get("watk", 0))
	var roll: Dictionary = phys.get("base_roll", {})
	var m := float((phys.get("mastery", {}) as Dictionary).get("no_mastery_factor", 0.0))
	var div := float((phys.get("ordinary_divisors", {}) as Dictionary).get("stat_div", 100))
	var clamp_d: Dictionary = db.formula("damage").get("final_clamp", {})
	var p := float(StatCalculator.total_stat(c, "str", db))
	var s := float(StatCalculator.total_stat(c, "dex", db))
	var mn := watk * (float(roll.get("min", 0)) + (p * m * lo + s) / div)
	var mx := watk * (float(roll.get("max", 0)) + (p * hi + s) / div)
	var cmin := float(clamp_d.get("min", 1))
	var cmax := float(clamp_d.get("max", 99999))
	return {"min": int(clampf(mn, cmin, cmax)), "max": int(clampf(mx, cmin, cmax)),
		"why": "W.ATK %d x (%.1f + (STR %d x %.2f x %.1f + DEX %d) / %d) .. W.ATK %d x (%.1f + (STR %d x %.1f + DEX %d) / %d) = %.3f .. %.3f"
			% [watk, float(roll.get("min", 0)), p, m, lo, s, div, watk, float(roll.get("max", 0)), p, hi, s, div, mn, mx]}


# =================================================================================================================
# Hunting and pickup
# =================================================================================================================

func _new_account() -> Dictionary:
	return {"kills": 0, "deaths": 0, "dropped": [], "picked": [], "refused": {}, "expired": 0, "lean_pickups": 0,
		"killed_mobs": {}, "shot": false, "exclude": {}, "reward": {}, "traps": []}


func _connect_account(d: PlaytestDriver, acct: Dictionary) -> void:
	d.events().connect(&"loot_dropped", func(list: Array, _at: Vector3, map: String) -> void:
		for e: Variant in list:
			var rec := (e as Dictionary).duplicate()
			rec["map"] = map
			(acct["dropped"] as Array).append(rec))
	d.events().connect(&"monster_killed", func(mob: String, _map: String) -> void:
		acct["killed_mobs"][mob] = int((acct["killed_mobs"] as Dictionary).get(mob, 0)) + 1)
	d.events().connect(&"player_died", func(_map: String) -> void: acct["deaths"] = int(acct["deaths"]) + 1)
	d.loot().connect(&"drop_picked_up", func(_rec: Dictionary, res: Dictionary) -> void:
		var r := res.duplicate()
		r["map"] = d.current_map()
		(acct["picked"] as Array).append(r))
	d.loot().connect(&"pickup_refused", func(rec: Dictionary, _res: Dictionary) -> void:
		acct["refused"][String(rec.get(LootPickupRules.UID_KEY, ""))] = true)
	d.loot().connect(&"drop_expired", func(_uid: String) -> void: acct["expired"] = int(acct["expired"]) + 1)


## Fights the nearest monsters (opts as nearest_monster) until until() or `budget_s`, sweeping the drops with Z
## after every kill. A death is answered with the notice's OK and the walk back.
func _hunt(d: PlaytestDriver, acct: Dictionary, map_id: String, until: Callable, budget_s: float, opts: Dictionary) -> Dictionary:
	var t0 := d.game_s()
	var k0 := int(acct["kills"])
	var excl_at := d.game_s()
	var fails := 0
	while not bool(until.call()) and d.game_s() - t0 < budget_s:
		if d.game().is_character_dead():
			await _respawn(d, acct, map_id)
			continue
		if d.current_map() != map_id:
			if not await _return_to(d, map_id):
				break
			continue
		if d.game_s() - excl_at > 60.0:
			(acct["exclude"] as Dictionary).clear()
			excl_at = d.game_s()
		var o := opts.duplicate()
		o["exclude"] = acct["exclude"]
		var target := d.nearest_monster(o)
		if target == null:
			await d.wait(1.0)
			continue
		var r: Dictionary = await d.face_and_attack_nearest(20.0, o)
		fails = 0 if bool(r["ok"]) else fails + 1
		if fails >= 3:
			fails = 0
			await _unstick(d, acct, map_id)
		if bool(r["ok"]):
			acct["kills"] = int(acct["kills"]) + 1
			if not bool(acct["shot"]) and DisplayServer.get_name() != "headless":
				await d.wait(0.8)
				if not (d.loot().call("nodes") as Dictionary).is_empty():
					acct["shot"] = true
					await d.screenshot("drops_on_ground")
			await _sweep(d, acct)
			await _maybe_use(d, acct)
		elif is_instance_valid(target) and String(r["why"]).begins_with("could not reach"):
			acct["exclude"][target.get_instance_id()] = true
	if not d.game().is_character_dead() and d.current_map() == map_id:
		await _sweep(d, acct)
	return {"ok": bool(until.call()), "kills": int(acct["kills"]) - k0, "time_s": d.game_s() - t0}


## After three fights in a row that could not reach their monster: a walk to the map's spawn. When even that cannot
## leave the spot, the player is trapped (a world finding, reported as a WARN with the place) and a console warp to
## the map's spawn is the only way on (setup fallback, logged).
func _unstick(d: PlaytestDriver, acct: Dictionary, map_id: String) -> void:
	var p := d.player()
	var a := p.global_position
	var r: Dictionary = await d.walk_to("spawn:0", {"max_s": 25.0})
	var moved := Vector2(p.global_position.x - a.x, p.global_position.z - a.z).length()
	if bool(r["ok"]) or moved > 4.0 or d.current_map() != map_id:
		return
	var def := d.world().defs.get_def(d.current_map())
	(acct["traps"] as Array).append({"map": d.current_map(), "world": a, "local": def.to_local(a), "at_s": d.game_s()})
	d.soft_check("the hunting player is never trapped", false, ("no walk leaves world %s (map-local %s) in %s: %s via %s, moved %.2f m;"
		+ " warping to the map's spawn (setup fallback)") % [a, def.to_local(a), d.current_map(), r.get("result", ""),
			r.get("how", ""), moved])
	await d.console("warp " + map_id)


func _respawn(d: PlaytestDriver, acct: Dictionary, map_id: String) -> void:
	await d.wait(0.5)
	var ok: Dictionary = await d.click("OK")
	await d.wait_until(func() -> bool: return not d.game().is_character_dead(), 30.0)
	await d.wait_idle(30.0)
	d.note("died (death %d) after %d kills: OK %s, respawned in %s" % [int(acct["deaths"]), int(acct["kills"]), ok["ok"], d.current_map()])
	await _return_to(d, map_id)


func _return_to(d: PlaytestDriver, map_id: String) -> bool:
	if d.current_map() == map_id:
		return true
	if TraversalTour.portal_between(d.world().defs, d.current_map(), map_id) != null:
		var t: Dictionary = await d.walk_trail(d.current_map(), map_id)
		if d.current_map() == map_id:
			return true
		d.soft_check("walked back to %s" % map_id, false, "; ".join(t.get("issues", PackedStringArray())))
	await d.console("warp " + map_id)
	return d.current_map() == map_id


## Every landed drop within PICK_RADIUS_M taken with Z: the harness's pickup_all_nearby first, then each drop it
## left is walked onto (it stops about 0.7 m short; the canonical pickup box is narrower) and Z is pressed again.
func _sweep(d: PlaytestDriver, acct: Dictionary) -> void:
	await d.pickup_all_nearby(PICK_RADIUS_M, 25.0)
	var tried := {}
	for _k in 10:
		if d.game().is_character_dead():
			return
		var left := _left_nodes(d, acct, tried)
		if left.is_empty():
			return
		var n: Node3D = left[0]
		tried[String(n.get("uid"))] = true
		var landing: Vector3 = n.get("landing")
		await d.walk_to(landing, {"within_m": 0.3, "max_s": 8.0, "retries": 0})
		await _step_onto(d, landing)
		var before := (acct["picked"] as Array).size()
		await d.pickup_all_nearby(1.5, 4.0)
		if (acct["picked"] as Array).size() > before:
			acct["lean_pickups"] = int(acct["lean_pickups"]) + 1


## Landed drops within PICK_RADIUS_M (and 2.5 m up or down) not refused and not tried yet, nearest first.
func _left_nodes(d: PlaytestDriver, acct: Dictionary, tried: Dictionary) -> Array:
	var p := d.player().global_position
	var out: Array = []
	for n: Node3D in (d.loot().call("nodes") as Dictionary).values():
		if not is_instance_valid(n) or not bool(n.call("is_landed")):
			continue
		var uid := String(n.get("uid"))
		if tried.has(uid) or (acct["refused"] as Dictionary).has(uid):
			continue
		var l: Vector3 = n.get("landing")
		# Another tier counts when the planners know a way there (a drop thrown onto the ledge the monster stood on).
		if Vector2(l.x - p.x, l.z - p.z).length() <= PICK_RADIUS_M and (absf(l.y - p.y) <= 2.5
				or String(d.walker.plan(l).get("how", "straight")) != "straight"):
			out.append(n)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var la: Vector3 = a.get("landing")
		var lb: Vector3 = b.get("landing")
		return Vector2(la.x - p.x, la.z - p.z).length() < Vector2(lb.x - p.x, lb.z - p.z).length())
	return out


## Real movement input straight at `landing` (half speed) until the pickup key would take a drop, at most 1 s.
func _step_onto(d: PlaytestDriver, landing: Vector3) -> void:
	var p := d.player()
	var ls := d.loot()
	var f0 := Engine.get_physics_frames()
	while Engine.get_physics_frames() - f0 < Engine.physics_ticks_per_second:
		if not (ls.call("pickup_target", p.global_position, {}) as Dictionary).is_empty():
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


## The pickup bookkeeping after the hunts: every item and meso the character holds came through a Z pickup (plus
## the quest reward), every picked item is on a killed monster's canonical drop table, stacks merged, and how many
## drops were left on the ground.
func _check_pickups(d: PlaytestDriver, acct: Dictionary, start_mesos: int) -> void:
	var c := d.character()
	var db := d.db()
	var picked: Array = acct["picked"]
	var picked_items := {}
	var picked_mesos := 0
	var bags := 0
	for r: Dictionary in picked:
		if String(r.get("kind", "")) == "mesos":
			picked_mesos += int(r.get("amount", 0))
			bags += 1
		else:
			var id := String(r.get("item_id", ""))
			picked_items[id] = int(picked_items.get(id, 0)) + int(r.get("qty", 1))
	var dropped_bags := 0
	var dropped_items := 0
	for e: Dictionary in acct["dropped"]:
		if String(e.get("kind", "")) == "mesos" or not e.has("item_id"):
			dropped_bags += 1
		else:
			dropped_items += 1
	var reward: Dictionary = acct["reward"]
	d.check("every meso came from a meso bag picked up with Z (+ the canonical quest reward)",
		c.mesos == start_mesos + picked_mesos + int(reward.get("mesos", 0)) and bags > 0,
		"%d mesos = %d + %d from %d bags + %d reward" % [c.mesos, start_mesos, picked_mesos, bags, int(reward.get("mesos", 0))])
	var holds := {}
	for tab in Inventory.TABS:
		for i in c.inventory.capacity(tab):
			var s := c.inventory.get_slot(tab, i)
			if not s.is_empty():
				holds[String(s["item_id"])] = int(holds.get(String(s["item_id"]), 0)) + int(s.get("qty", 1))
	var expect := picked_items.duplicate()
	if String(reward.get("item_id", "")) != "" and int(reward.get("qty", 0)) > 0:
		expect[reward["item_id"]] = int(expect.get(reward["item_id"], 0)) + int(reward["qty"])
	var used: Dictionary = acct.get("used", {})
	for id: String in used:
		expect[id] = int(expect.get(id, 0)) - int(used[id])
		if int(expect[id]) == 0:
			expect.erase(id)
	d.check("every item held came from a Z pickup or the quest reward (less the ones used)", PlaytestDriver.diff(expect, holds) == "",
		"held %s, picked %s + reward %s - used %s" % [holds, picked_items, reward, used])
	# The rolling members of the killed monsters' canonical drop records (contract C1: chance and item resolved). A
	# member the sources leave unresolved is on the record but must never drop.
	var allowed := {}
	for mob: String in (acct["killed_mobs"] as Dictionary):
		for row: Dictionary in DropRates.effective_entries(mob, db):
			if String(row.get("excluded", "")) == "":
				allowed[String(row.item_id)] = true
	var off_table := PackedStringArray()
	for id: String in picked_items:
		if not allowed.has(id):
			off_table.append(id)
	d.check("every picked item is a rolling member of a killed monster's canonical drop record", off_table.is_empty(),
		"killed %s; picked %s; not rolling there %s; rolling %s" % [acct["killed_mobs"], picked_items.keys(), off_table, allowed.keys()])
	# Stacking: each stackable id sits in as few slots as its max stack allows.
	var bad := PackedStringArray()
	var merged := PackedStringArray()
	for id: String in holds:
		var def := ItemDef.of(id, db)
		if def == null or not def.is_stackable():
			continue
		var slots := 0
		for i in c.inventory.capacity(def.tab):
			if String(c.inventory.get_slot(def.tab, i).get("item_id", "")) == id:
				slots += 1
		var need := ceili(float(holds[id]) / float(maxi(1, def.max_stack)))
		if slots != need:
			bad.append("%s: %d in %d slots (max stack %d)" % [id, holds[id], slots, def.max_stack])
		elif int(holds[id]) > 1:
			merged.append("%s x%d in %d slot" % [id, holds[id], slots])
	d.check("stackable pickups merge into stacks (canonical max_stack)", bad.is_empty() and not merged.is_empty(),
		"merged %s; wrong %s" % [", ".join(merged), ", ".join(bad)])
	var equips := PackedStringArray()
	for id: String in holds:
		var def := ItemDef.of(id, db)
		if def != null and def.is_equipment():
			equips.append("%s %s" % [id, def.name])
	d.note("equipment from drops: %s" % (", ".join(equips) if not equips.is_empty() else "none"))
	var on_ground := (d.loot().call("nodes") as Dictionary).size()
	var by_map := {}
	for e: Dictionary in acct["dropped"]:
		var m := String(e.get("map", "?"))
		by_map[m] = [int((by_map.get(m, [0, 0]) as Array)[0]) + 1, int((by_map.get(m, [0, 0]) as Array)[1])]
	for r: Dictionary in picked:
		var m := String(r.get("map", "?"))
		by_map[m] = [int((by_map.get(m, [0, 0]) as Array)[0]), int((by_map.get(m, [0, 0]) as Array)[1]) + 1]
	d.note("drops per map [dropped, picked]: %s; trap warps: %d" % [by_map, (acct["traps"] as Array).size()])
	var p := d.player()
	var def := d.world().defs.get_def(d.current_map())
	for n: Node3D in (d.loot().call("nodes") as Dictionary).values():
		var l: Vector3 = n.get("landing")
		var rec: Dictionary = n.get("record")
		var pl: Dictionary = d.walker.plan(l)
		d.note("left on the ground in %s: %s at world %s (map-local %s), %.1f m from the player, %+.2f m up; plan %s; ground under it: %s" % [
			d.current_map(), String(rec.get("item_id", "mesos")), l, def.to_local(l), Vector2(l.x - p.global_position.x,
				l.z - p.global_position.z).length(), l.y - p.global_position.y, pl.get("how", "?"), _ground_name(d, l)])
	d.soft_check("every drop was picked up", picked.size() == (acct["dropped"] as Array).size(),
		"%d dropped (%d bags, %d items), %d picked, %d expired, %d still on the ground here, %d refused; %d needed a step onto the drop after pickup_all_nearby"
		% [(acct["dropped"] as Array).size(), dropped_bags, dropped_items, picked.size(), int(acct["expired"]), on_ground,
			(acct["refused"] as Dictionary).size(), int(acct["lean_pickups"])])


# =================================================================================================================
# Dialogue and shop
# =================================================================================================================

## Answers the open conversation: "accept" says yes to the offer of QUEST; "complete" takes the turn-in and declines
## anything offered after it. Menus pick the choice naming QUEST, else the first.
func _converse(d: PlaytestDriver, goal: String) -> void:
	var c := d.character()
	var qname := String(d.db().quest(QUEST).get("name", ""))
	var v := d.read_dialogue()
	var guard := 0
	while bool(v["open"]) and guard < 24:
		guard += 1
		var t := String(v["type"])
		if t == "menu":
			var pick := 0
			var choices: Array = v["choices"]
			for k in choices.size():
				if String(choices[k]).to_lower().contains(qname.to_lower()):
					pick = k
			if c.quests.is_completed(QUEST) and guard > 1:
				break
			v = await d.choose(pick)
		elif t == "yes_no":
			var yes := goal == "accept" and not c.quests.is_in_progress(QUEST) and not c.quests.is_completed(QUEST)
			v = await d.choose("yes" if yes else "no")
		elif "next" in v["buttons"] or "ok" in v["buttons"]:
			v = await d.next()
		else:
			break
	if bool(d.read_dialogue()["open"]):
		await d.close_dialogue()


func _open_pan(d: PlaytestDriver) -> bool:
	var v: Dictionary = await d.talk_to(PAN)
	if not d.check("Pan can be talked to on foot", bool(v["open"]), String(v.get("why", ""))):
		return false
	var guard := 0
	while not d.shop_open() and bool(d.read_dialogue()["open"]) and guard < 6:
		guard += 1
		var dv := d.read_dialogue()
		if String(dv["type"]) == "menu":
			await d.choose(0)
		else:
			await d.next()
		await d.wait(0.2)
	return d.check("Pan's shop opens from his greeting", d.shop_open(), str(d.read_dialogue()).left(160))


## Pan's first row for an equip slot that the character's gender may wear.
func _pick_piece(d: PlaytestDriver, slot: String) -> String:
	var db := d.db()
	var g := d.character().gender
	for row: Dictionary in ShopService.stock(SHOP, db):
		var it := db.item(String(row["item_id"]))
		var ig := String(it.get("gender", ""))
		if String(it.get("equip_slot", "")) == slot and (ig in ["", "any", "unisex"] or ig == g):
			return String(row["item_id"])
	return ""


# =================================================================================================================
# Real mouse and key input helpers
# =================================================================================================================

static func _center(c: Control) -> Vector2:
	return c.get_global_transform_with_canvas() * (c.size * 0.5)


## A real double-click (PlaytestKit.double_click: refused, with a failed check, when a player cannot click the
## control). `probe` is read right before and right after the second press (dispatch is synchronous).
func _double_click(d: PlaytestDriver, c: Control, probe: Callable = Callable()) -> Dictionary:
	return await PlaytestKit.new(d).double_click(c, probe)


## A real GUI drag (PlaytestKit.drag: refused, with a failed check, when a player cannot point at either end).
func _drag(d: PlaytestDriver, from: Control, to: Control) -> Dictionary:
	return await PlaytestKit.new(d).drag(from, to)


## Hovers a slot and returns the tooltip's rows ([] when none shows).
func _tooltip_rows(d: PlaytestDriver, slot: Control) -> Array:
	var away := _center(slot) + Vector2(0, -400)
	d.input.mouse_move(away)
	await d.frames(1)
	d.input.mouse_move(_center(slot))
	await d.frames(2)
	var tip: MisoItemTooltip = (d.windows() as MisoWindowsRoot).tooltip
	var hud_tip: Variant = _hud(d).tooltip
	if tip.visible:
		return tip.rows.duplicate(true)
	if hud_tip is MisoItemTooltip and (hud_tip as MisoItemTooltip).visible:
		return (hud_tip as MisoItemTooltip).rows.duplicate(true)
	return []


## Presses the quickslot key (a real key event; the HUD reads it in _unhandled_input, synchronously) and checks the
## count and HP change against the canonical restore. {"ok", "why"}.
func _press_quickslot(d: PlaytestDriver, item_id: String) -> Dictionary:
	var c := d.character()
	var db := d.db()
	var restore := int((db.item(item_id).get("consumable", {}) as Dictionary).get("hp_restore", 0))
	var max_hp := StatCalculator.max_hp(c, db)
	var n0 := c.inventory.count(item_id)
	var hp0 := c.hp
	var code := (KEY_0 + int(KEY)) as Key
	d.input.key_event(code, true)
	var n1 := c.inventory.count(item_id)
	var hp1 := c.hp
	d.input.key_event(code, false)
	var ok := n1 == n0 - 1 and hp1 == mini(max_hp, hp0 + restore)
	return {"ok": ok, "used": n0 - n1, "why": "count %d -> %d, HP %d -> %d (canonical +%d, Max HP %d)" % [n0, n1, hp0, hp1, restore, max_hp]}


# =================================================================================================================
# State capture and comparison
# =================================================================================================================

func _capture(d: PlaytestDriver) -> Dictionary:
	var c := d.character()
	await d.open_window("stats")
	await d.frames(2)
	var texts := _stat_texts(d)
	await d.close_window("stats")
	return {
		"inventory": c.inventory.to_dict(),
		"equipment": c.equipment.to_dict(),
		"mesos": c.mesos,
		"quickslots": c.quickslots.duplicate(),
		"base_stats": c.base_stats.duplicate(),
		"progress": {"level": c.level, "exp": c.exp, "ap": c.ap, "sp": c.sp, "fame": c.fame,
			"base_max_hp": c.base_max_hp, "base_max_mp": c.base_max_mp, "gender": c.gender},
		"vitals": {"hp": c.hp, "mp": c.mp},
		"derived": StatCalculator.snapshot(c, d.db()),
		"stats_window": texts,
		"hud": {"mesos": _hud(d).status.mesos_label.text, "quickslot": _hud(d).status.quickslots.count_text(KEY)},
	}


func _compare(d: PlaytestDriver, when: String, a: Dictionary, b: Dictionary) -> void:
	for k: String in ["inventory", "equipment", "mesos", "quickslots", "base_stats", "progress", "vitals", "derived",
			"stats_window", "hud"]:
		var df := PlaytestDriver.diff(a.get(k), b.get(k), "$." + k)
		d.check("%s: %s persists exactly" % [when, k], a.has(k) and df == "", df if df != "" else _short(a.get(k)))


static func _short(v: Variant) -> String:
	return str(v).left(220)


func _stat_texts(d: PlaytestDriver) -> Dictionary:
	var out := {}
	var vals: Dictionary = (d.windows() as MisoWindowsRoot).stats.values
	for k: String in vals:
		out[k] = (vals[k] as Label).text
	return out


static func _same_keys(a: Dictionary, b: Dictionary, keys: Array) -> bool:
	for k: Variant in keys:
		if String(a.get(k, "?")) != String(b.get(k, "!")):
			return false
	return true


# =================================================================================================================
# Small lookups
# =================================================================================================================

static func _ground_name(d: PlaytestDriver, at: Vector3) -> String:
	var space := d.player().get_world_3d().direct_space_state
	var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 1.0))
	if h.is_empty():
		return "nothing"
	var col: Object = h.get("collider")
	return "%s (layer %d) at y %.2f" % [(col as Node).name if col is Node else "?",
		(col as CollisionObject3D).collision_layer if col is CollisionObject3D else -1, (h.position as Vector3).y]


static func _hud(d: PlaytestDriver) -> MisoHud:
	return d.hud() as MisoHud


func _best_consumable(d: PlaytestDriver) -> String:
	var c := d.character()
	var best := ""
	for i in c.inventory.capacity("use"):
		var s := c.inventory.get_slot("use", i)
		if s.is_empty():
			continue
		var id := String(s["item_id"])
		var def := ItemDef.of(id, d.db())
		if def != null and def.is_consumable() and def.hp_flat > 0 and (best == "" or c.inventory.count(id) > c.inventory.count(best)):
			best = id
	return best


func _slot_index(d: PlaytestDriver, tab: String, item_id: String) -> int:
	var c := d.character()
	for i in c.inventory.capacity(tab):
		if String(c.inventory.get_slot(tab, i).get("item_id", "")) == item_id:
			return i
	return -1


func _wdef(d: PlaytestDriver, item_id: String) -> int:
	return int((d.db().item(item_id).get("stats", {}) as Dictionary).get("wdef", 0))


func _name(d: PlaytestDriver, item_id: String) -> String:
	return String(d.db().item(item_id).get("name", item_id))


static func _row_texts(rows: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for r: Variant in rows:
		var t := String((r as Dictionary).get("text", ""))
		if t != "":
			out.append(t)
	return out


static func _has_row(rows: Array, needle: String) -> bool:
	for t in _row_texts(rows):
		if t.contains(needle):
			return true
	return false
