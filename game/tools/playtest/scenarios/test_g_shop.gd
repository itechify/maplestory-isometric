extends PlaytestScenario
## test_g_shop: brief Test G (shop), played in the real main scene with real input. A new male Beginner visits the
## three Maple Island shops: Pan (16, Southperry Armor Store 000000061), Sid (20, Amherst Weapon Store 000001011) and
## Lucy (21, Amherst Department Store 000001013). Each store is entered on foot through its door with Up (a console
## warp to the town is the setup for Pan and Sid; Lucy is reached by walking out of Sid's store and along Amherst),
## the shopkeeper is talked to on foot (F) and the greeting's Enter opens the shop window. Everything after that is
## the shop's own keys (Tab, the tab digits, Up/Down, Left/Right with and without Shift, Enter) and the Max button.
##
## Expectations come from the canonical records, never from the code under test: the buy list, order and prices from
## data/canonical/shops/<shop>.json, the sell-back from data/canonical/items/<id>.json sell_price_mesos (cross-checked
## against the shop record), stack sizes from the item's max_stack (equipment: inventory.json equipment_max_stack).
## A ledger of the expected mesos is kept from those prices and compared with the character, the shop's meso display
## and the HUD's after every trade. Checked: the canonical stock and prices on screen; buying with exact meso and
## inventory changes and stacking (5 + 3 into one slot, an overflow past the stack into [100, 3], Pet Food's 200
## stack); selling at the canonical sell-back (0-value equipment too, from another shop); insufficient mesos with a
## new character's empty purse and at 499 for a 500-meso Razor (the message, nothing changes); a full Equip tab and a
## full Use tab, both filled by buying with the Max button (refused with a message, nothing changes; a partial stack
## still accepts its item); the quantity picker's limits (room-limited, meso-limited, the sell slot's quantity, at
## least 1); The Green Relaxer, a protected item (owner ruling #7), refused by Lucy with its message and nothing
## changed. `mesos` and `give` console commands are setup only (the report marks them).

const PAN_TOWN := "000000060"
const PAN_STORE := "000000061"
const AMHERST := "000001010"
const SID_STORE := "000001011"
const LUCY_STORE := "000001013"
const PAN := "16"
const SID := "20"
const LUCY := "21"
const PAN_SHOP := "maple-road-pan"
const SID_SHOP := "maple-road-sid"
const LUCY_SHOP := "maple-road-lucy"
const WEAPON := "585"

# Representative items (ids only: every number expected about them is read from the canonical records).
const WHITE_UNDERSHIRT := "933"
const TUBE_TOP := "937"
const JEAN_SHORTS := "1157"
const SANDALS := "1305"
const BOOTS := "1306"
const SWORD := "541"
const HAND_AXE := "576"
const WOODEN_CLUB := "585"
const RAZOR := "558"
const RED_POTION := "270"
const ORANGE_POTION := "271"
const APPLE := "236"
const EGG := "237"
const ORANGE := "239"
const PET_FOOD := "269"
## The Green Relaxer, a protected item (owner ruling #7): given by the console as setup, then offered to Lucy.
const RELAXER := "522"

## Expected mesos, from the canonical prices of every trade and the console's setup amounts.
var ledger: int = 0
## Event counters (Events): mesos_changed, item_gained, item_lost, inventory_full (+ the ids), and the shop window's
## result_shown (one per Enter that bought or sold, ok or not).
var sig := {"mesos": 0, "gained": 0, "lost": 0, "full": 0, "full_ids": [], "shown": 0}
## Per shopkeeper: how the conversation was reached.
var talk_log := {}
var _shop_hooked := false


func description() -> String:
	return "Test G: Pan, Sid and Lucy on foot; canonical prices, meso and inventory changes, stacking, sell-back, " \
		+ "insufficient mesos, full Equip and Use tabs, quantity picker limits"


func max_seconds() -> float:
	return 900.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Shopper", "male", WEAPON, {"str": 9})
	if not d.check("new game through the title and creation screens", bool(ng["ok"]), "%s via %s %s" % [ng["map"], ng["via"], ng["why"]]):
		return
	var c := d.character()
	var rules := CharacterFactory.rules_table(d.db())
	var start_mesos := int((rules.get("starting_mesos", {}) as Dictionary).get("value", -1))
	ledger = c.mesos
	d.check("the new character starts with new_character.json's mesos and an empty inventory",
		c.mesos == start_mesos and c.inventory.is_empty(), "mesos %d (data %d), empty %s" % [c.mesos, start_mesos, c.inventory.is_empty()])
	_hook_events(d)
	d.note("The quantity picker's 9999 clamp cannot be reached on Maple Island: the largest room in one tab is 24 slots x 200 (Pet Food) = 4800.")

	if await _visit(d, "Pan", PAN_TOWN, PAN_STORE, PAN, PAN_SHOP, true):
		await _pan(d)
		await _leave_shop(d, "Pan")
	if await _visit(d, "Sid", AMHERST, SID_STORE, SID, SID_SHOP, true):
		await _sid(d)
		await _leave_shop(d, "Sid")
	# Lucy: out of Sid's store through its door and along Amherst to the Department Store, on foot.
	var lucy_ok := false
	if d.current_map() == SID_STORE:
		if bool(talk_log.get(SID, {}).get("goto", false)):
			await d.console("warp " + SID_STORE)  # out of the pocket behind the counter a goto may have left the player in
		var out: Dictionary = await d.enter_portal(AMHERST)
		d.soft_check("Sid's store door leads back to Amherst (Up)", bool(out["ok"]) and d.current_map() == AMHERST,
			"%s via %s (%s)" % [out["to"], out["via"], "; ".join(out["issues"])])
		if d.current_map() == AMHERST:
			lucy_ok = await _visit(d, "Lucy", AMHERST, LUCY_STORE, LUCY, LUCY_SHOP, false)
	if not lucy_ok and d.current_map() != LUCY_STORE:
		lucy_ok = await _visit(d, "Lucy", AMHERST, LUCY_STORE, LUCY, LUCY_SHOP, true)
	if lucy_ok:
		await _lucy(d)
		await _leave_shop(d, "Lucy")

	d.check("the final mesos equal the canonical ledger", d.character().mesos == ledger,
		"have %d, ledger %d" % [d.character().mesos, ledger])
	d.check("the HUD shows the final mesos", _hud_mesos(d) == _th(ledger), "HUD '%s', ledger %s" % [_hud_mesos(d), _th(ledger)])
	# The inventory window (I) after the visits: the purse and the Use tab's goods.
	if await d.open_window("inventory"):
		var t := d.window_text("inventory")
		d.check("the inventory window shows the final mesos", t.contains(_th(ledger)), t.left(160).replace("\n", " / "))
		d.note("inventory window text: " + t.left(400).replace("\n", " / "))
		await d.close_window("inventory")
	d.carry["talk"] = talk_log
	d.carry["final_inventory"] = d.inventory_summary()
	d.carry["final_mesos"] = d.character().mesos


# =================================================================================================================
# Pan: armour (equipment, 0-value sell-back), the purse at 0, the Equip tab filled with Max
# =================================================================================================================

func _pan(d: PlaytestDriver) -> void:
	var c := d.character()
	_check_stock(d, PAN_SHOP, "Pan")
	# A female-only top shown to a male character: the inventory tooltip (ItemTooltip) says "For female characters";
	# the shop's detail panel should tell a buyer before he spends mesos on something he cannot wear.
	await _select_buy(d, TUBE_TOP)
	var g := String(d.db().item(TUBE_TOP).get("gender", ""))
	var detail := _detail_text(d)
	d.soft_check("Pan: the detail panel tells a %s character that the %s is for %s characters" % [d.character().gender,
		_name(d, TUBE_TOP), g], detail.to_lower().contains(g), "detail: '%s'" % detail.replace("\n", " / "))
	await d.screenshot("pan_open")

	# Insufficient mesos with the new character's empty purse (no setup): the picker stays at 1, Enter is refused.
	await _select_buy(d, WHITE_UNDERSHIRT)
	var price := _price(d, PAN_SHOP, WHITE_UNDERSHIRT)
	var q := await _qty_to(d, 3)
	d.check("Pan: with %d mesos the picker stays at 1 (Right x2 does nothing)" % c.mesos, q == 1 and int(d.shop().call("max_quantity")) == 1,
		"quantity %d, max %d" % [q, int(d.shop().call("max_quantity"))])
	_check_live_warning(d, "Pan: the detail panel warns before Enter", "not have enough mesos")
	var r := await _enter(d, WHITE_UNDERSHIRT)
	_check_refused(d, "Pan: buying a %d-meso White Undershirt with %d mesos" % [price, c.mesos], r, ItemCodes.INSUFFICIENT_MESOS,
		["not have enough mesos", "costs %s" % _th(price), "you have %s" % _th(c.mesos)])

	# Setup: mesos for the visit. The shop's meso display follows the change while it is open.
	await _give_mesos(d, 2000)
	d.check("Pan: the open shop's meso display follows a meso change", _shop_mesos(d) == _th(ledger),
		"shows '%s', ledger %s" % [_shop_mesos(d), _th(ledger)])

	# Buy 1 and 2 (equipment never stacks: one slot each).
	await _buy(d, PAN_SHOP, "Pan", WHITE_UNDERSHIRT, 1)
	await _buy(d, PAN_SHOP, "Pan", JEAN_SHORTS, 2)
	_check_row_owned(d, "Pan", JEAN_SHORTS)

	# Room-limited picker: the Max button on Leather Sandals with mesos for more than the free Equip slots.
	await _select_buy(d, SANDALS)
	var exp_max := _expected_max_buy(d, PAN_SHOP, SANDALS)
	var room := _room(d, SANDALS)
	var afford := c.mesos / _price(d, PAN_SHOP, SANDALS)
	var mx := await _click_max(d)
	var after_right := await _press(d, KEY_RIGHT, 3)
	d.check("Pan: Max sets the picker to the free Equip slots (room-limited), Right cannot pass it",
		mx == exp_max and after_right == exp_max and room < afford,
		"Max -> %d, Right x3 -> %d; free slots %d, affordable %d" % [mx, after_right, room, afford])
	var fill := await _enter(d, SANDALS)
	_check_bought(d, PAN_SHOP, "Pan: bought the Max of Leather Sandals, filling the Equip tab", SANDALS, exp_max, fill)
	d.check("Pan: the Equip tab is full", c.inventory.free_slots("equip") == 0,
		"%d / %d used" % [_used(d, "equip"), c.inventory.capacity("equip")])

	# Full Equip tab: the purchase is refused with a message, nothing changes.
	await _select_buy(d, BOOTS)
	var bq := await _qty_to(d, 2)
	d.check("Pan: with a full tab the picker stays at 1", bq == 1, "quantity %d" % bq)
	_check_live_warning(d, "Pan: the detail panel warns that the tab is full", "inventory is full")
	var full := await _enter(d, BOOTS)
	_check_refused(d, "Pan: Red Rubber Boots with a full Equip tab", full, ItemCodes.INVENTORY_FULL, ["inventory is full"])
	d.check("Pan: the refusal announces inventory_full for the item once", int(full["sig_full"]) == 1 and (sig["full_ids"] as Array).back() == BOOTS,
		"%d inventory_full, last id %s" % [int(full["sig_full"]), str((sig["full_ids"] as Array).back() if not (sig["full_ids"] as Array).is_empty() else "")])
	await d.screenshot("pan_full_tab")

	# Sell tab: the canonical sell-back of every listed slot, then a 0-meso sale that frees a slot.
	await _select_sell(d, "equip", _first_slot(d, SANDALS))
	_check_sell_prices(d, "Pan")
	var sq := await _press(d, KEY_RIGHT, 2)
	d.check("Pan: the sell picker stops at the slot's quantity (1 for equipment)", sq == 1, "quantity %d" % sq)
	var sold := await _enter(d, SANDALS)
	_check_sold(d, "Pan: sold a Leather Sandals at the canonical sell-back", SANDALS, 1, sold)
	d.check("Pan: the sale freed one Equip slot", c.inventory.free_slots("equip") == 1, "%d free" % c.inventory.free_slots("equip"))

	# The freed slot takes the purchase that was refused.
	await _buy(d, PAN_SHOP, "Pan", BOOTS, 1)
	d.check("Pan: the Equip tab is full again", c.inventory.free_slots("equip") == 0, "%d free" % c.inventory.free_slots("equip"))


# =================================================================================================================
# Sid: weapons; the full Equip tab carried in, sales of Pan's goods, 499 vs 500 for the Razor, a meso-limited picker
# =================================================================================================================

func _sid(d: PlaytestDriver) -> void:
	var c := d.character()
	_check_stock(d, SID_SHOP, "Sid")

	# The Equip tab is still full from Pan's: Sid refuses too.
	if c.inventory.free_slots("equip") == 0:
		await _select_buy(d, SWORD)
		var full := await _enter(d, SWORD)
		_check_refused(d, "Sid: a Sword with the Equip tab still full", full, ItemCodes.INVENTORY_FULL, ["inventory is full"])

	# Pan's goods sell at Sid's too (MeowDB: no sell restrictions), at their canonical 0.
	for item_id in [WHITE_UNDERSHIRT, JEAN_SHORTS, JEAN_SHORTS, SANDALS, SANDALS, SANDALS]:
		var at := _first_slot(d, item_id)
		if at < 0:
			continue
		await _select_sell(d, "equip", at)
		var s := await _enter(d, item_id)
		_check_sold(d, "Sid: sold Pan's %s at the canonical sell-back" % _name(d, item_id), item_id, 1, s)
	_check_sell_prices(d, "Sid")

	# 499 mesos for a 500-meso Razor (setup sets the purse), then exactly 500.
	var razor := _price(d, SID_SHOP, RAZOR)
	await _give_mesos(d, (razor - 1) - c.mesos)
	await _select_buy(d, RAZOR)
	var req := int((d.db().item(RAZOR).get("requirements", {}) as Dictionary).get("level", 0))
	var detail := _detail_text(d)
	d.check("Sid: the Razor's detail shows its canonical level requirement (%d)" % req, detail.contains("Req. Level %d" % req),
		"detail: '%s'" % detail.replace("\n", " / "))
	_check_live_warning(d, "Sid: the detail panel warns at %d mesos" % c.mesos, "not have enough mesos")
	var r := await _enter(d, RAZOR)
	_check_refused(d, "Sid: a %d-meso Razor with %d mesos" % [razor, c.mesos], r, ItemCodes.INSUFFICIENT_MESOS,
		["not have enough mesos", "costs %s" % _th(razor), "you have %s" % _th(c.mesos)])
	await d.screenshot("sid_insufficient")
	await _give_mesos(d, 1)
	await _buy(d, SID_SHOP, "Sid", RAZOR, 1)
	d.check("Sid: exactly the price buys it, leaving 0 mesos", c.mesos == 0, "%d mesos" % c.mesos)
	await _select_sell(d, "equip", _first_slot(d, RAZOR))
	var s2 := await _enter(d, RAZOR)
	_check_sold(d, "Sid: sold the Razor back at the canonical sell-back", RAZOR, 1, s2)

	# Meso-limited picker: Swords with more free slots than the mesos pay for.
	await _select_buy(d, SWORD)
	var exp_max := _expected_max_buy(d, SID_SHOP, SWORD)
	var room := _room(d, SWORD)
	var afford := c.mesos / _price(d, SID_SHOP, SWORD)
	var mx := await _click_max(d)
	var after_right := await _press(d, KEY_RIGHT, 2)
	d.check("Sid: Max sets the picker to what the mesos pay for (meso-limited), Right cannot pass it",
		mx == exp_max and after_right == exp_max and afford < room,
		"Max -> %d, Right x2 -> %d; affordable %d, free slots %d" % [mx, after_right, afford, room])
	var down := await _press(d, KEY_LEFT, 2)
	d.check("Sid: Left lowers the picker", down == exp_max - 2, "quantity %d" % down)
	var b := await _enter(d, SWORD)
	_check_bought(d, SID_SHOP, "Sid: bought %d Swords (one slot each)" % down, SWORD, down, b)
	await _buy(d, SID_SHOP, "Sid", HAND_AXE, 1)
	await _buy(d, SID_SHOP, "Sid", WOODEN_CLUB, 1)
	await d.screenshot("sid_shop")


# =================================================================================================================
# Lucy: potions and food; stacking, sell-back per unit, the Use tab filled with Max, a partial stack in a full tab
# =================================================================================================================

func _lucy(d: PlaytestDriver) -> void:
	var c := d.character()
	_check_stock(d, LUCY_SHOP, "Lucy")
	if c.mesos == 0:
		await _select_buy(d, RED_POTION)
		var r := await _enter(d, RED_POTION)
		_check_refused(d, "Lucy: a Red Potion with 0 mesos", r, ItemCodes.INSUFFICIENT_MESOS,
			["not have enough mesos", "costs %s" % _th(_price(d, LUCY_SHOP, RED_POTION)), "you have 0"])
	await _give_mesos(d, 50000)

	# Space (jump, the dialogue's Next) never buys.
	await _select_buy(d, RED_POTION)
	await d.wait_until(func() -> bool: return bool(d.shop().call("confirm_key_armed")), 2.0)
	var m0 := c.mesos
	await d.tap_key(KEY_SPACE)
	await d.frames(2)
	d.check("Lucy: Space in the shop buys nothing", c.mesos == m0 and c.inventory.count(RED_POTION) == 0 and d.shop_open(),
		"mesos %d -> %d, Red Potions %d" % [m0, c.mesos, c.inventory.count(RED_POTION)])

	# Stacking: 5, then 3 into the same slot, then past the stack size into a second slot.
	await _buy(d, LUCY_SHOP, "Lucy", RED_POTION, 5)
	await _buy(d, LUCY_SHOP, "Lucy", RED_POTION, 3)
	var q0 := int(d.shop().get("quantity"))
	var i := d._begin(PlaytestReport.KIND_PLAY, "shop_quantity", "Shift+Right")
	await d.input.tap_key(KEY_RIGHT, true)
	d._end(i, true, str(int(d.shop().get("quantity"))))
	d.check("Lucy: Shift+Right steps the picker by 10", int(d.shop().get("quantity")) == q0 + 10, "%d -> %d" % [q0, int(d.shop().get("quantity"))])
	await _buy(d, LUCY_SHOP, "Lucy", RED_POTION, 95)
	await _buy(d, LUCY_SHOP, "Lucy", PET_FOOD, 150)
	await _buy(d, LUCY_SHOP, "Lucy", ORANGE_POTION, 2)
	await _buy(d, LUCY_SHOP, "Lucy", APPLE, 1)
	await _buy(d, LUCY_SHOP, "Lucy", EGG, 1)
	await _buy(d, LUCY_SHOP, "Lucy", ORANGE, 1)
	_check_row_owned(d, "Lucy", RED_POTION)

	# Sell-back per unit, from the slot the window shows.
	await _select_sell(d, "use", _first_slot(d, RED_POTION))
	_check_sell_prices(d, "Lucy")
	await _qty_to(d, 3)
	var s1 := await _enter(d, RED_POTION)
	_check_sold(d, "Lucy: sold 3 Red Potions from the first stack", RED_POTION, 3, s1)
	await _select_sell(d, "use", _first_slot(d, ORANGE_POTION))
	var slot_qty := int(c.inventory.get_slot("use", _first_slot(d, ORANGE_POTION)).get("qty", 0))
	var smx := await _click_max(d)
	var sr := await _press(d, KEY_RIGHT, 3)
	d.check("Lucy: the sell picker's Max is the slot's quantity, Right cannot pass it", smx == slot_qty and sr == slot_qty,
		"Max -> %d, Right x3 -> %d, slot %d" % [smx, sr, slot_qty])
	var sl := await _press(d, KEY_LEFT, 1)
	var s2 := await _enter(d, ORANGE_POTION)
	_check_sold(d, "Lucy: sold %d of %d Orange Potions" % [sl, slot_qty], ORANGE_POTION, sl, s2)
	await _select_sell(d, "use", _first_slot(d, PET_FOOD))
	await _qty_to(d, 10)
	var s3 := await _enter(d, PET_FOOD)
	_check_sold(d, "Lucy: sold 10 Pet Food", PET_FOOD, 10, s3)
	var used0 := _used(d, "use")
	await _select_sell(d, "use", _first_slot(d, EGG))
	var s4 := await _enter(d, EGG)
	_check_sold(d, "Lucy: sold the only Egg", EGG, 1, s4)
	d.check("Lucy: selling a slot's last unit frees the slot", _used(d, "use") == used0 - 1 and c.inventory.count(EGG) == 0,
		"%d -> %d used" % [used0, _used(d, "use")])
	await d.screenshot("lucy_sell")

	# The Green Relaxer is a protected item (owner ruling #7, inventory.json shop.protected_items): no shop buys it.
	await _give_item(d, RELAXER)
	if await _select_sell(d, "setup", _first_slot(d, RELAXER)):
		_check_live_warning(d, "Lucy: the detail panel says The Green Relaxer cannot be sold, before Enter", "cannot be obtained again")
		var gr := await _enter(d, RELAXER)
		_check_refused(d, "Lucy: The Green Relaxer (protected item)", gr, ShopService.PROTECTED_ITEM,
			["The Green Relaxer cannot be obtained again", "The shop will not buy it"])
		await d.screenshot("lucy_protected")

	# Fill the Use tab by buying Apples with Max (room-limited: the open Apple stack plus every free slot).
	await _select_buy(d, APPLE)
	var exp_max := _expected_max_buy(d, LUCY_SHOP, APPLE)
	var room := _room(d, APPLE)
	var afford := c.mesos / _price(d, LUCY_SHOP, APPLE)
	var mx := await _click_max(d)
	d.check("Lucy: Max on Apples is the room left (open stack + free slots x stack), below the mesos' limit",
		mx == exp_max and room < afford, "Max -> %d; room %d, affordable %d" % [mx, room, afford])
	var fill := await _enter(d, APPLE)
	_check_bought(d, LUCY_SHOP, "Lucy: bought the Max of Apples, filling the Use tab", APPLE, exp_max, fill)
	d.check("Lucy: the Use tab is full", c.inventory.free_slots("use") == 0, "%d / %d used" % [_used(d, "use"), c.inventory.capacity("use")])

	# A full tab still takes an item with room in its own stack.
	await _select_buy(d, RED_POTION)
	var rp_max := _expected_max_buy(d, LUCY_SHOP, RED_POTION)
	var rq := await _qty_to(d, 200)
	d.check("Lucy: with the Use tab full, the Red Potion picker stops at min(open stack room %d, affordable %d)" % [
		_room(d, RED_POTION), c.mesos / _price(d, LUCY_SHOP, RED_POTION)], rq == rp_max, "quantity %d, expected %d" % [rq, rp_max])
	var minus := await _click_button(d, "-")
	var plus := await _click_button(d, "+")
	var plus2 := await _click_button(d, "+")
	d.check("Lucy: the picker's - and + buttons step by 1 and + stops at the limit", minus == rp_max - 1 and plus == rp_max
		and plus2 == rp_max, "- -> %d, + -> %d, + -> %d (limit %d)" % [minus, plus, plus2, rp_max])
	await _qty_to(d, 1)
	var p := await _enter(d, RED_POTION)
	_check_bought(d, LUCY_SHOP, "Lucy: a Red Potion still fits a full tab (into its open stack, no new slot)", RED_POTION, 1, p)

	# Refused: Apples (every stack at its size) and an Egg (no slot) with the tab full.
	for item_id in [APPLE, EGG]:
		await _select_buy(d, item_id)
		var f := await _enter(d, item_id)
		_check_refused(d, "Lucy: %s with a full Use tab" % _name(d, item_id), f, ItemCodes.INVENTORY_FULL, ["inventory is full"])
	await d.screenshot("lucy_full_tab")


# =================================================================================================================
# Visiting a shop: the door, the shopkeeper on foot, the greeting, the shop window
# =================================================================================================================

func _visit(d: PlaytestDriver, label: String, town: String, store: String, npc_id: String, shop_id: String,
		warp_town: bool) -> bool:
	if warp_town:
		await d.console("warp " + town)
		if not d.check("%s: in %s (setup warp)" % [label, town], d.current_map() == town, d.current_map()):
			return false
	var door: Dictionary = await d.enter_portal(store)
	var walked := bool(door["ok"]) and d.current_map() == store
	if not d.soft_check("%s: walked to the store door in %s and entered with Up" % [label, town], walked,
			"%s via %s (%s)" % [door["to"], door["via"], "; ".join(door["issues"])]):
		await d.console("warp " + store)
		if not d.check("%s: in %s (fallback warp)" % [label, store], d.current_map() == store, d.current_map()):
			return false
	var npc := d.world().npc_nodes.get(npc_id) as Node3D
	if not d.check("%s: the shopkeeper stands in %s" % [label, store], npc != null, ""):
		return false
	var v: Dictionary = await d.talk_to(npc_id)
	var info := {"on_foot": bool(v["open"]), "goto": false, "door": walked}
	var p := d.player()
	if bool(v["open"]):
		info["talk_gap"] = snappedf(d.talk_gap(npc, p.global_position), 0.001)
		info["feet_m"] = snappedf(p.global_position.distance_to(npc.global_position), 0.001)
		info["leaned"] = bool(v.get("leaned", false))
		info["profile"] = String(npc.get("talk_profile")) if "talk_profile" in npc else "?"
	else:
		info["talk_gap"] = float(v.get("talk_gap", -1.0))
		info["why"] = String(v.get("why", ""))
	d.soft_check("%s: talked to on foot (F from the shop floor)" % label, bool(v["open"]),
		("body %.3f m inside the talk zone, %.2f m feet to feet%s" % [-float(info["talk_gap"]), float(info["feet_m"]),
			" after leaning in" if bool(info["leaned"]) else ""]) if bool(v["open"]) else String(info.get("why", "")))
	if not bool(v["open"]):
		info["goto"] = true
		await d.console("goto npc " + npc_id)
		v = await d.talk_to(npc_id)
	talk_log[npc_id] = info
	if not d.check("%s: the greeting opens" % label, bool(v["open"]), str(v).left(200)):
		return false
	var idle: Array = d.db().npc(npc_id).get("idle_chatter", [])
	var said := String(v.get("text", ""))
	var canon_line := false
	for line in idle:
		if said.contains(String((line as Dictionary).get("text", "")).strip_edges()):
			canon_line = true
	d.check("%s: the greeting is one of the NPC's canonical lines" % label, canon_line, said.left(100))
	await d.next()
	var opened := await d.wait_until(func() -> bool: return d.shop_open(), 2.0)
	var sw := d.shop()
	if not d.check("%s: Enter on the greeting opens the shop window" % label, opened and String(sw.get("shop_id")) == shop_id
			and not d.dialogue_open(), "open %s, shop '%s', dialogue %s" % [opened, String(sw.get("shop_id")), d.dialogue_open()]):
		return false
	if not _shop_hooked:
		sw.connect("result_shown", func(_r: Dictionary, _m: String) -> void: sig["shown"] += 1)
		_shop_hooked = true
	var rec := d.db().shop(shop_id)
	var title := String((sw.get("title_label") as Label).text)
	var subtitle := String((sw.get("subtitle_label") as Label).text)
	d.check("%s: the window is titled from the shop record" % label, title == "%s's Shop" % String(rec.get("npc_name", ""))
		and subtitle.contains(String(rec.get("npc_function", ""))) and subtitle.contains(String(rec.get("map_display_name", ""))),
		"'%s' / '%s'" % [title, subtitle])
	d.check("%s: the shop window is modal" % label, bool(d.state().get("modal", false)), "")
	return true


func _leave_shop(d: PlaytestDriver, label: String) -> void:
	d.check("%s: the shop's meso display matches the ledger" % label, _shop_mesos(d) == _th(ledger),
		"'%s' vs %s" % [_shop_mesos(d), _th(ledger)])
	d.check("%s: Esc leaves the shop" % label, await d.close_shop() and not bool(d.state().get("modal", true)),
		"modal %s" % d.state().get("modal"))


# =================================================================================================================
# Trades
# =================================================================================================================

## Buys `qty` of `item_id` with the keys (row, Right/Left, Enter) and checks the canonical cost and inventory change.
func _buy(d: PlaytestDriver, shop_id: String, label: String, item_id: String, qty: int) -> void:
	await _select_buy(d, item_id)
	var q := await _qty_to(d, qty)
	if not d.check("%s: the picker reaches %d for %s" % [label, qty, _name(d, item_id)], q == qty, "quantity %d" % q):
		return
	var r := await _enter(d, item_id)
	_check_bought(d, shop_id, "%s: bought %s x%d" % [label, _name(d, item_id), qty], item_id, qty, r)


func _check_bought(d: PlaytestDriver, shop_id: String, what: String, item_id: String, qty: int, r: Dictionary) -> void:
	var row := _canon_row(d, shop_id, item_id)
	var per := maxi(1, int(row.get("quantity_per_purchase", 1)) if row.get("quantity_per_purchase") != null else 1)
	var cost := int(row.get("price_mesos", -1)) * qty
	var units := qty * per
	var exp_stacks := _expected_stacks(r["slots_before"], item_id, units, _max_stack(d, item_id))
	var new_slots := exp_stacks.size() - (r["stacks_before"] as Array).size()
	var msg := "Bought %s for %s mesos." % [_name(d, item_id) if units <= 1 else "%s x%d" % [_name(d, item_id), units], _th(cost)]
	var total_line := "Total: %s mesos" % _th(cost)
	var ok: bool = bool(r["ok"]) and int(r["mesos_delta"]) == -cost and int(r["count_delta"]) == units \
		and r["stacks_after"] == exp_stacks and int(r["used_delta"]) == new_slots and String(r["message"]) == msg \
		and int(r["sig_mesos"]) == 1 and int(r["sig_full"]) == 0 and String(r["total_text"]) == total_line
	if bool(r["ok"]):
		ledger -= cost
	d.check(what, ok and d.character().mesos == ledger, ("%s | mesos %+d (canonical %d x %d = -%d), count %+d, stacks %s -> %s (expected %s), "
		+ "slots %+d, '%s', mesos %d (ledger %d); before Enter '%s'; HUD %s") % [r["code"], int(r["mesos_delta"]), int(row.get("price_mesos", -1)), qty, cost,
		int(r["count_delta"]), r["stacks_before"], r["stacks_after"], exp_stacks, int(r["used_delta"]), r["message"],
		d.character().mesos, ledger, r["total_text"], r["hud_new"]])
	if bool(r["ok"]):
		_check_hud(d, what, r, PackedStringArray(["You have spent %s mesos." % _th(cost),
			"You have gained an item (%s%s)" % [_name(d, item_id), (" x%d" % units) if units > 1 else ""]]))


func _check_sold(d: PlaytestDriver, what: String, item_id: String, qty: int, r: Dictionary) -> void:
	var unit := int(d.db().item(item_id).get("sell_price_mesos", -1))
	var total := unit * qty
	var msg := "Sold %s for %s mesos." % [_name(d, item_id) if qty <= 1 else "%s x%d" % [_name(d, item_id), qty], _th(total)]
	var total_line := "Total: %s mesos" % _th(total)
	var ok: bool = bool(r["ok"]) and int(r["quantity"]) == qty and int(r["mesos_delta"]) == total and int(r["count_delta"]) == -qty \
		and String(r["message"]) == msg and String(r["total_text"]) == total_line and int(r["sig_lost"]) == 1
	if bool(r["ok"]):
		ledger += int(r["mesos_delta"])
	d.check(what, ok and d.character().mesos == ledger, "%s | qty %d, mesos %+d (canonical %d x %d = %d), count %+d, '%s', mesos %d (ledger %d); before Enter '%s'; HUD %s" % [
		r["code"], int(r["quantity"]), int(r["mesos_delta"]), unit, qty, total, int(r["count_delta"]), r["message"],
		d.character().mesos, ledger, r["total_text"], r["hud_new"]])
	if bool(r["ok"]) and total > 0:
		_check_hud(d, what, r, PackedStringArray(["You have gained mesos (+%s)" % _th(total)]))
	elif bool(r["ok"]):
		d.check(what + ": the HUD logs no meso line for a 0-meso sale", not ",".join(PackedStringArray(r["hud_new"])).contains("mesos"),
			"new %s" % [r["hud_new"]])


## The HUD message log after a trade: every expected line is new. A line missing because the log does not repeat an
## identical line within MisoNoticeLog.DEDUPE_S is a WARN (the log then under-reports a second, separate gain).
func _check_hud(d: PlaytestDriver, what: String, r: Dictionary, expected: PackedStringArray) -> void:
	var hud: PackedStringArray = r["hud_new"]
	var missing := PackedStringArray()
	var ages := PackedStringArray()
	for e in expected:
		if hud.has(e):
			continue
		missing.append(e)
		var hist: Array = r["hud_hist"]
		for k in range(hist.size() - 1, -1, -1):
			if String((hist[k] as Dictionary).get("text", "")) == e:
				ages.append("'%s' already logged %.2f s earlier" % [e, float(r["hud_clock"]) - float((hist[k] as Dictionary).get("time", 0.0))])
				break
	if missing.is_empty():
		d.check(what + ": the HUD log lists it", true, "%s" % [hud])
	else:
		d.soft_check(what + ": the HUD log lists every line of it", false, "missing %s; new %s; %s (an identical line within %.1f s is not repeated)" % [
			missing, hud, "; ".join(ages), MisoNoticeLog.DEDUPE_S])


## A refused trade: the code, the message on screen (with `needles`), and no change at all.
func _check_refused(d: PlaytestDriver, what: String, r: Dictionary, code: String, needles: Array) -> void:
	var msg := String(r["message"]).to_lower()
	var missing: Array = []
	for n in needles:
		if not msg.contains(String(n).to_lower()):
			missing.append(n)
	var shown := d.texts_under(d.shop()).contains(String(r["message"]))
	var hud: PackedStringArray = r["hud_new"]
	if code == ItemCodes.INVENTORY_FULL:
		# The HUD log repeats an identical line only after DEDUPE_S, so a second refusal may add none: the last line counts.
		d.check(what + ": the HUD log says the inventory is full", String(r["hud_last"]) == "Your inventory is full.",
			"new %s, last '%s'" % [hud, r["hud_last"]])
	d.check(what + ": the HUD logs no meso or item gain", not ",".join(hud).contains("mesos") and not ",".join(hud).contains("gained"),
		"new %s" % [hud])
	d.check(what + ": refused with the message on screen", not bool(r["ok"]) and String(r["code"]) == code and missing.is_empty()
		and shown and int(r["shown"]) == 1, "%s, '%s'%s, on screen %s" % [r["code"], r["message"],
			(" missing %s" % [missing]) if not missing.is_empty() else "", shown])
	d.check(what + ": nothing changes", int(r["mesos_delta"]) == 0 and int(r["count_delta"]) == 0 and int(r["used_delta"]) == 0
		and r["stacks_after"] == r["stacks_before"] and int(r["sig_mesos"]) == 0 and int(r["sig_gained"]) == 0
		and int(r["sig_lost"]) == 0 and d.character().mesos == ledger,
		"mesos %+d, count %+d, slots %+d, mesos_changed %d, item_gained %d, item_lost %d, mesos %d (ledger %d)" % [
			int(r["mesos_delta"]), int(r["count_delta"]), int(r["used_delta"]), int(r["sig_mesos"]), int(r["sig_gained"]),
			int(r["sig_lost"]), d.character().mesos, ledger])


## Enter in the open shop once the confirm key is armed; what changed.
func _enter(d: PlaytestDriver, item_id: String) -> Dictionary:
	var sw := d.shop()
	await d.wait_until(func() -> bool: return bool(sw.call("confirm_key_armed")), 2.0)
	var before := _snap(d, item_id)
	var qty := int(sw.get("quantity"))
	var total_text := String((sw.get("total_label") as Label).text)
	var hist0: Array = _hud_log(d)
	var last0: Variant = hist0.back() if not hist0.is_empty() else null
	await d.tap_key(KEY_ENTER)
	await d.frames(2)
	var after := _snap(d, item_id)
	var hist1: Array = _hud_log(d)
	var start := 0
	for k in range(hist1.size() - 1, -1, -1):
		if last0 != null and is_same(hist1[k], last0):
			start = k + 1
			break
	var hud_new := PackedStringArray()
	for k in range(start, hist1.size()):
		hud_new.append(String((hist1[k] as Dictionary).get("text", "")))
	var res: Dictionary = (sw.get("last_result") as Dictionary).duplicate(true)
	return {"ok": bool(res.get("ok", false)) and int(after["shown"]) > int(before["shown"]), "code": String(res.get("code", "")),
		"result": res, "message": String(sw.get("status_text")), "quantity": qty,
		"mesos_delta": int(after["mesos"]) - int(before["mesos"]), "count_delta": int(after["count"]) - int(before["count"]),
		"used_delta": int(after["used"]) - int(before["used"]), "slots_before": before["slots"],
		"stacks_before": before["stacks"], "stacks_after": after["stacks"],
		"sig_mesos": int(after["sig_mesos"]) - int(before["sig_mesos"]), "sig_gained": int(after["sig_gained"]) - int(before["sig_gained"]),
		"sig_lost": int(after["sig_lost"]) - int(before["sig_lost"]), "sig_full": int(after["sig_full"]) - int(before["sig_full"]),
		"shown": int(after["shown"]) - int(before["shown"]), "total_text": total_text, "hud_new": hud_new,
		"hud_last": String((hist1.back() as Dictionary).get("text", "")) if not hist1.is_empty() else "",
		"hud_hist": hist1.duplicate(true), "hud_clock": _hud_clock(d)}


func _snap(d: PlaytestDriver, item_id: String) -> Dictionary:
	var c := d.character()
	var tab := _tab(d, item_id)
	return {"mesos": c.mesos, "count": c.inventory.count(item_id), "used": _used(d, tab), "slots": _tab_slots(d, tab),
		"stacks": _stacks(d, item_id), "sig_mesos": sig["mesos"], "sig_gained": sig["gained"], "sig_lost": sig["lost"],
		"sig_full": sig["full"], "shown": sig["shown"]}


## Setup: `mesos <n>` through the console; the ledger follows.
func _give_mesos(d: PlaytestDriver, n: int) -> void:
	if n == 0:
		return
	var m0 := d.character().mesos
	await d.console("mesos %d" % n)
	ledger += n
	d.check("setup: mesos %+d" % n, d.character().mesos == m0 + n and d.character().mesos == ledger,
		"%d -> %d" % [m0, d.character().mesos])


## Setup: `give <item>` through the console (one unit).
func _give_item(d: PlaytestDriver, item_id: String) -> void:
	var n0 := d.character().inventory.count(item_id)
	await d.console("give %s" % item_id)
	d.check("setup: give %s" % _name(d, item_id), d.character().inventory.count(item_id) == n0 + 1,
		"%d -> %d" % [n0, d.character().inventory.count(item_id)])


# =================================================================================================================
# The shop's keys
# =================================================================================================================

func _select_buy(d: PlaytestDriver, item_id: String) -> bool:
	var sw := d.shop()
	var i := d._begin(PlaytestReport.KIND_PLAY, "shop_select", "buy " + item_id)
	if String(sw.get("mode")) != "buy":
		await d.input.tap_key(KEY_TAB)
	var rows: Array = sw.get("buy_rows")
	var want := -1
	for k in rows.size():
		if String((rows[k] as Dictionary).get("item_id", "")) == item_id:
			want = k
			break
	var guard := 0
	while want >= 0 and int(sw.get("selected")) != want and guard < 40:
		await d.input.tap_key(KEY_DOWN if int(sw.get("selected")) < want else KEY_UP)
		guard += 1
	var ok := want >= 0 and String(sw.get("mode")) == "buy" and int(sw.get("selected")) == want
	d._end(i, ok, "row %d of %d (%d keys)" % [want, rows.size(), guard])
	return ok


## Sell mode (Tab), the tab's digit, then Up/Down to the row of slot `index`.
func _select_sell(d: PlaytestDriver, tab: String, index: int) -> bool:
	var sw := d.shop()
	var i := d._begin(PlaytestReport.KIND_PLAY, "shop_select", "sell %s slot %d" % [tab, index])
	if String(sw.get("mode")) != "sell":
		await d.input.tap_key(KEY_TAB)
	await d.input.tap_key((KEY_1 + Inventory.TABS.find(tab)) as Key)
	var rows: Array = sw.get("sell_rows")
	var want := -1
	for k in rows.size():
		if int((rows[k] as Dictionary).get("index", -1)) == index:
			want = k
			break
	var guard := 0
	while want >= 0 and int(sw.get("selected")) != want and guard < 40:
		await d.input.tap_key(KEY_DOWN if int(sw.get("selected")) < want else KEY_UP)
		guard += 1
	var ok := want >= 0 and String(sw.get("mode")) == "sell" and String(sw.get("sell_tab")) == tab and int(sw.get("selected")) == want
	d._end(i, ok, "row %d of %d (%d keys)" % [want, rows.size(), guard])
	return ok


## Right / Left (with Shift for steps of 10) toward `n`; stops when the picker no longer moves. The quantity.
func _qty_to(d: PlaytestDriver, n: int) -> int:
	var sw := d.shop()
	var i := d._begin(PlaytestReport.KIND_PLAY, "shop_quantity", "to %d" % n)
	var keys := 0
	while keys < 400:
		var q := int(sw.get("quantity"))
		if q == n:
			break
		var diff := n - q
		await d.input.tap_key(KEY_RIGHT if diff > 0 else KEY_LEFT, absi(diff) >= 10)
		keys += 1
		if int(sw.get("quantity")) == q:
			break
	d._end(i, true, "%d (%d keys)" % [int(sw.get("quantity")), keys])
	return int(sw.get("quantity"))


func _press(d: PlaytestDriver, key: Key, times: int) -> int:
	var sw := d.shop()
	var i := d._begin(PlaytestReport.KIND_PLAY, "shop_quantity", "%s x%d" % [OS.get_keycode_string(key), times])
	for _k in times:
		await d.input.tap_key(key)
	d._end(i, true, str(int(sw.get("quantity"))))
	return int(sw.get("quantity"))


## The shop's Max button, with the mouse. The quantity after it.
func _click_max(d: PlaytestDriver) -> int:
	return await _click_button(d, "Max")


## A button of the shop window by its exact text, with the mouse. The picker's quantity after it.
func _click_button(d: PlaytestDriver, text: String) -> int:
	var sw := d.shop()
	var btn: Control = null
	for n in (sw as Node).find_children("*", "Button", true, false):
		if String((n as Button).text) == text and (n as Control).is_visible_in_tree():
			btn = n
			break
	var r: Dictionary = {"ok": false, "why": "no visible '%s' button" % text}
	if btn != null:
		r = await d.click(btn)
	d.check("the shop's '%s' button reacts to a click" % text, bool(r["ok"]), str(r.get("why", "")))
	await d.frames(1)
	return int(sw.get("quantity"))


# =================================================================================================================
# Checks on the window
# =================================================================================================================

## The Buy list: the canonical stock in position order with the canonical prices, on screen.
func _check_stock(d: PlaytestDriver, shop_id: String, label: String) -> void:
	var sw := d.shop()
	var canon := _canon(d, shop_id)
	var rows: Array = sw.get("buy_rows")
	var bad: Array = []
	if rows.size() != canon.size():
		bad.append("%d rows, canonical %d" % [rows.size(), canon.size()])
	for k in mini(rows.size(), canon.size()):
		var w: Dictionary = rows[k]
		var cr: Dictionary = canon[k]
		if String(w.get("item_id")) != String(cr.get("item_id")) or int(w.get("price")) != int(cr.get("price_mesos")):
			bad.append("#%d %s %d vs canonical %s %d" % [k + 1, w.get("item_id"), int(w.get("price")), cr.get("item_id"), int(cr.get("price_mesos"))])
	var listed := PackedStringArray()
	for cr: Dictionary in canon:
		listed.append("%s %d" % [cr.get("name"), int(cr.get("price_mesos"))])
	var bad_s := PackedStringArray()
	for x in bad:
		bad_s.append(str(x))
	d.check("%s: the Buy list is the canonical stock in order with the canonical prices (%d rows)" % [label, canon.size()],
		bad.is_empty(), "; ".join(bad_s) if not bad.is_empty() else ", ".join(listed))
	# On screen: each row's name line followed by its price line, in order.
	var lines := d.texts_under(sw).split("\n")
	var at := 0
	var missing: Array = []
	for cr: Dictionary in canon:
		var nm := _name(d, String(cr.get("item_id")))
		var price_line := "%s mesos" % _th(int(cr.get("price_mesos")))
		var found := -1
		for k in range(at, lines.size() - 1):
			if lines[k] == nm and lines[k + 1] == price_line:
				found = k
				break
		if found < 0:
			missing.append("%s / %s" % [nm, price_line])
		else:
			at = found + 2
	d.check("%s: every row shows its name and canonical price on screen, in order" % label, missing.is_empty(),
		("missing %s" % [missing]) if not missing.is_empty() else "%d rows" % canon.size())
	var names_differ: Array = []
	for cr: Dictionary in canon:
		if String(cr.get("shop_list_name", cr.get("name"))) != _name(d, String(cr.get("item_id"))):
			names_differ.append("%s: shop '%s', item '%s'" % [cr.get("item_id"), cr.get("shop_list_name"), _name(d, String(cr.get("item_id")))])
		var item_buy: Variant = d.db().item(String(cr.get("item_id"))).get("npc_buy_price_mesos")
		if item_buy != null and int(item_buy) != int(cr.get("price_mesos")):
			d.note("%s: canonical records disagree on %s's buy price: shops/%s.json price_mesos %d, items/%s.json npc_buy_price_mesos %d (the game charges the shop's)" % [
				label, cr.get("name"), shop_id, int(cr.get("price_mesos")), cr.get("item_id"), int(item_buy)])
	if not names_differ.is_empty():
		d.note("%s: shop list names differ from item names: %s" % [label, names_differ])


## The Sell list of the current tab: each row's price is the canonical sell-back (items/<id>.json, and the shop
## record where the item is in one).
func _check_sell_prices(d: PlaytestDriver, label: String) -> void:
	var sw := d.shop()
	var rows: Array = sw.get("sell_rows")
	var bad: Array = []
	var seen := {}
	for r: Dictionary in rows:
		var id := String(r.get("item_id"))
		var canon := int(d.db().item(id).get("sell_price_mesos", -1))
		if int(r.get("price")) != canon:
			bad.append("%s %d vs %d" % [id, int(r.get("price")), canon])
		for sid in [PAN_SHOP, SID_SHOP, LUCY_SHOP]:
			var sr := _canon_row(d, sid, id)
			if not sr.is_empty() and int(sr.get("sell_price_mesos", -1)) != canon:
				bad.append("%s: shop %s says %d, item says %d" % [id, sid, int(sr.get("sell_price_mesos", -1)), canon])
		seen[id] = canon
	var text := d.texts_under(sw)
	d.check("%s: the Sell tab lists %d slots at the canonical sell-back" % [label, rows.size()], bad.is_empty() and not rows.is_empty()
		and text.contains("Sells for"), ("%s" % [bad]) if not bad.is_empty() else str(seen))


## The detail panel's live warning (red) before Enter.
func _check_live_warning(d: PlaytestDriver, what: String, needle: String) -> void:
	var sw := d.shop()
	var cl := sw.get("check_label") as Label
	var t := cl.text if cl != null and cl.is_visible_in_tree() else ""
	d.check(what, t.to_lower().contains(needle), "'%s'" % t)


## The detail panel's visible text (name, type, description, stat and requirement lines, price, owned).
func _detail_text(d: PlaytestDriver) -> String:
	var sw := d.shop()
	var parts := PackedStringArray()
	for key in ["detail_name", "detail_type", "detail_desc", "detail_stats", "detail_price", "detail_owned"]:
		var l := sw.get(key) as Label
		if l != null and l.is_visible_in_tree() and l.text != "":
			parts.append(l.text)
	return "\n".join(parts)


func _check_row_owned(d: PlaytestDriver, label: String, item_id: String) -> void:
	var lines := d.texts_under(d.shop()).split("\n")
	var nm := _name(d, item_id)
	var owned := "Owned %d" % d.character().inventory.count(item_id)
	var ok := false
	for k in range(lines.size() - 2):
		if lines[k] == nm and lines[k + 2] == owned:
			ok = true
			break
	d.check("%s: the %s row shows '%s'" % [label, nm, owned], ok, "")


func _shop_mesos(d: PlaytestDriver) -> String:
	var l := d.shop().get("meso_label") as Label
	return l.text if l != null else ""


## The HUD message log's history ({text, tone, time}, oldest first); [] without a HUD.
func _hud_log(d: PlaytestDriver) -> Array:
	var h := d.hud()
	var lp: Variant = h.get("log_panel") if h != null else null
	return (lp as Node).get("history") if lp is Node else []


func _hud_clock(d: PlaytestDriver) -> float:
	var h := d.hud()
	var lp: Variant = h.get("log_panel") if h != null else null
	return float((lp as Node).get("_clock")) if lp is Node else 0.0


func _hud_mesos(d: PlaytestDriver) -> String:
	var h := d.hud()
	var st: Variant = h.get("status") if h != null else null
	var l: Variant = (st as Node).get("mesos_label") if st is Node else null
	return (l as Label).text if l is Label else ""


func _hook_events(d: PlaytestDriver) -> void:
	var ev := d.events()
	ev.connect("mesos_changed", func(_m: int, _dl: int) -> void: sig["mesos"] += 1)
	ev.connect("item_gained", func(_id: String, _q: int) -> void: sig["gained"] += 1)
	ev.connect("item_lost", func(_id: String, _q: int) -> void: sig["lost"] += 1)
	var on_full := func(id: String) -> void:
		sig["full"] += 1
		(sig["full_ids"] as Array).append(id)
	ev.connect("inventory_full", on_full)


# =================================================================================================================
# Canonical data and inventory bookkeeping (independent of ShopService / Inventory.room_for)
# =================================================================================================================

func _canon(d: PlaytestDriver, shop_id: String) -> Array:
	var items: Array = (d.db().shop(shop_id).get("items", []) as Array).duplicate()
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("position", 0)) < int(b.get("position", 0)))
	return items


func _canon_row(d: PlaytestDriver, shop_id: String, item_id: String) -> Dictionary:
	for r: Dictionary in d.db().shop(shop_id).get("items", []):
		if String(r.get("item_id")) == item_id:
			return r
	return {}


func _price(d: PlaytestDriver, shop_id: String, item_id: String) -> int:
	return int(_canon_row(d, shop_id, item_id).get("price_mesos", -1))


func _name(d: PlaytestDriver, item_id: String) -> String:
	return String(d.db().item(item_id).get("name", item_id))


func _tab(d: PlaytestDriver, item_id: String) -> String:
	return String(d.db().item(item_id).get("inventory_tab", ""))


## Stack size: the item's canonical max_stack; equipment from inventory.json (MeowDB publishes none).
func _max_stack(d: PlaytestDriver, item_id: String) -> int:
	var it := d.db().item(item_id)
	var inv: Dictionary = d.db().miso_table("inventory")
	if _tab(d, item_id) == "equip":
		return int(inv.get("equipment_max_stack", 1))
	return int(it.get("max_stack")) if it.get("max_stack") != null else int(inv.get("unpublished_max_stack", 1))


func _used(d: PlaytestDriver, tab: String) -> int:
	var c := d.character()
	return c.inventory.capacity(tab) - c.inventory.free_slots(tab)


## Quantities of the slots holding `item_id`, in slot order.
func _stacks(d: PlaytestDriver, item_id: String) -> Array:
	var c := d.character()
	var tab := _tab(d, item_id)
	var out: Array = []
	for i in c.inventory.capacity(tab):
		var s := c.inventory.get_slot(tab, i)
		if not s.is_empty() and String(s.get("item_id")) == item_id:
			out.append(int(s.get("qty", 1)))
	return out


func _first_slot(d: PlaytestDriver, item_id: String) -> int:
	var c := d.character()
	var tab := _tab(d, item_id)
	for i in c.inventory.capacity(tab):
		var s := c.inventory.get_slot(tab, i)
		if not s.is_empty() and String(s.get("item_id")) == item_id:
			return i
	return -1


## How many more units fit: open stacks of the item (clean ones) plus every free slot, at the canonical stack size.
func _room(d: PlaytestDriver, item_id: String) -> int:
	var c := d.character()
	var tab := _tab(d, item_id)
	var ms := _max_stack(d, item_id)
	var room := 0
	for i in c.inventory.capacity(tab):
		var s := c.inventory.get_slot(tab, i)
		if s.is_empty():
			room += ms
		elif String(s.get("item_id")) == item_id and (s.get("data", {}) as Dictionary).is_empty():
			room += maxi(0, ms - int(s.get("qty", 1)))
	return room


## The picker's limit as the shop documents it: what fits and what the mesos pay for, at least 1.
func _expected_max_buy(d: PlaytestDriver, shop_id: String, item_id: String) -> int:
	var row := _canon_row(d, shop_id, item_id)
	var per := maxi(1, int(row.get("quantity_per_purchase", 1)) if row.get("quantity_per_purchase") != null else 1)
	var price := int(row.get("price_mesos", 0))
	var room := _room(d, item_id) / per
	var afford := d.character().mesos / price if price > 0 else room
	return clampi(mini(room, afford), 1, 9999)


## Every slot of a tab: {} when empty, else {"id", "qty", "clean" (no instance data)}.
func _tab_slots(d: PlaytestDriver, tab: String) -> Array:
	var c := d.character()
	var out: Array = []
	for i in c.inventory.capacity(tab):
		var s := c.inventory.get_slot(tab, i)
		if s.is_empty():
			out.append({})
		else:
			out.append({"id": String(s.get("item_id")), "qty": int(s.get("qty", 1)),
				"clean": (s.get("data", {}) as Dictionary).is_empty()})
	return out


## The item's stacks (in slot order) after adding `units` by the documented rule (ITEMS.md, Inventory.add): open
## clean stacks of the item topped up in slot order, then empty slots in slot order, `ms` per slot.
func _expected_stacks(slots: Array, item_id: String, units: int, ms: int) -> Array:
	var sim: Array = slots.duplicate(true)
	var left := units
	for s: Dictionary in sim:
		if left > 0 and not s.is_empty() and String(s["id"]) == item_id and bool(s["clean"]):
			var add := mini(left, maxi(0, ms - int(s["qty"])))
			s["qty"] = int(s["qty"]) + add
			left -= add
	for k in sim.size():
		if left > 0 and (sim[k] as Dictionary).is_empty():
			sim[k] = {"id": item_id, "qty": mini(left, ms), "clean": true}
			left -= mini(left, ms)
	var out: Array = []
	for s: Dictionary in sim:
		if not s.is_empty() and String(s["id"]) == item_id:
			out.append(int(s["qty"]))
	return out


static func _th(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
