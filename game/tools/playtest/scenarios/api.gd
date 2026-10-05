extends PlaytestScenario
## api: every PlaytestDriver call at least once, as a working reference for scenario authors (not a brief test).
## New game with the screen's Recommended spread -> held and tapped keys -> the inventory and stats windows by their
## keys -> walking to off-route points (the grid planner) and talking to Heena -> a console warp into the Amherst
## Department Store -> Lucy's greeting and shop: buy two of her first item and sell one back at the canonical prices ->
## out through the door with Up -> Rain's conversation ended with the End Chat button -> Sam's conversation answered
## page by page (next(), "no" on his offer) -> pickup with nothing around -> a mouse click on the pause menu's Resume ->
## state() and screenshots.

const START := "000000001"
const STORE := "000001013"
const AMHERST := "000001010"
const HEENA := "1"
const LUCY := "21"
const RAIN := "19"
const HUNTING := "000000040"
const SAM := "9"


func description() -> String:
	return "a reference run of every driver call: windows, keys, the grid planner, Lucy's shop, a door, Rain's chat"


func max_seconds() -> float:
	return 420.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Tourist", "female")
	if not d.check("new game with the Recommended spread", bool(ng["ok"]) and ng["via"] == "screen", String(ng["why"])):
		return
	var p := d.player()

	# Keys and actions.
	var x0 := p.global_position
	await d.press(&"move_right", 0.5)
	await d.wait(0.3)
	d.check("holding move_right walks", p.global_position.distance_to(x0) > 0.5, "%.2f m" % p.global_position.distance_to(x0))
	var jumps := [0]
	var on_jump := func() -> void: jumps[0] += 1
	p.jumped.connect(on_jump)
	await d.tap(&"jump")
	await d.wait(1.0)
	p.jumped.disconnect(on_jump)
	d.check("tapping jump jumps once", jumps[0] == 1, "%d jumps" % jumps[0])

	# Windows.
	d.check("the inventory opens with its key", await d.open_window("inventory"))
	var inv_text := d.window_text("inventory")
	d.check("the inventory window shows text", inv_text != "", inv_text.left(80).replace("\n", " / "))
	d.check("the inventory closes with its key", await d.close_window("inventory"))
	d.check("the stats window opens", await d.open_window("stats"))
	var stats_text := d.window_text("stats")
	d.check("the stats window shows the level", stats_text.contains(str(d.character().level)), stats_text.left(120).replace("\n", " / "))
	await d.tap_key(KEY_ESCAPE)
	await d.frames(3)
	d.check("Esc closes the newest window first", not bool(d.windows().call("is_open", "stats")) and d.main.flow.is_in(ShellFlow.State.PLAYING))

	# Walking off the routes (the grid planner) and an NPC of the start map.
	var w: Dictionary = await d.walk_to("route:ToHouseDoor:end", {"planner": "grid"})
	d.check("the grid planner walks to the house door", bool(w["ok"]) and w.get("how") == "grid",
		"%s via %s, %.1f m" % [w.get("result", ""), w.get("how", ""), float(w.get("distance_m", 0.0))])
	var back: Dictionary = await d.walk_to("spawn:0")
	d.check("walked back to the spawn (auto planner)", bool(back["ok"]), "%s via %s" % [back.get("result", ""), back.get("how", "")])
	var heena: Dictionary = await d.talk_to(HEENA)
	if d.soft_check("Heena can be reached on foot", bool(heena["open"])):
		d.check("Heena speaks", String(heena.get("text", "")) != "", String(heena.get("text", "")).left(80))
		var v := d.read_dialogue()
		while bool(v["open"]) and ("next" in v["buttons"] or "ok" in v["buttons"]):
			v = await d.next()
		d.check("Heena's conversation ends", await d.close_dialogue())

	# Lucy's shop.
	await d.console("warp " + STORE)
	await d.console("mesos 1000")
	var lucy: Dictionary = await d.talk_to(LUCY)
	# Known world issue (2026-10-04): Lucy stands in a pocket behind a 3 m counter, out of talk range of every floor.
	var lucy_on_foot := d.soft_check("Lucy can be reached on foot", bool(lucy["open"]))
	if not lucy_on_foot:
		await d.console("goto npc " + LUCY)
		lucy = await d.talk_to(LUCY)
	if not d.check("Lucy's greeting", bool(lucy["open"]), str(lucy).left(200)):
		return
	await d.next()
	await d.wait(0.2)
	if not d.check("Enter on Lucy's greeting opens her shop", d.shop_open(), str(d.read_dialogue()).left(200)):
		return
	var rows: Array = d.shop().get("buy_rows")
	var item := String((rows[0] as Dictionary)["item_id"])
	# The canonical price, read from the shop's data (not from the window, which would only check itself).
	var price := int(ShopService.row_for(String(d.shop().get("shop_id")), item, d.db()).get("price", -1))
	d.check("the shop window lists the canonical price", price > 0 and int((rows[0] as Dictionary)["price"]) == price,
		"window %d, canonical %d" % [int((rows[0] as Dictionary)["price"]), price])
	var buy: Dictionary = await d.shop_buy(item, 2)
	d.check("bought 2 at the canonical price", bool(buy["ok"]) and int(buy["mesos_delta"]) == -2 * price
		and int(buy["count_delta"]) == 2, "%s (%d mesos, %+d items; price %d)" % [buy["message"], buy["mesos_delta"], buy["count_delta"], price])
	var sell: Dictionary = await d.shop_sell(item, 1)
	d.check("sold 1 back at the canonical sell price", bool(sell["ok"]) and int(sell["mesos_delta"]) == ShopService.sell_price(item, d.db())
		and int(sell["count_delta"]) == -1, "%s (%d mesos, %+d items)" % [sell["message"], sell["mesos_delta"], sell["count_delta"]])
	d.check("Esc leaves the shop", await d.close_shop())
	await d.screenshot("store")
	if not lucy_on_foot:
		await d.console("warp " + STORE)  # out of the pocket behind the counter the goto put the player in

	# A door with Up.
	var door: Dictionary = await d.enter_portal(AMHERST)
	d.check("Up at the store's door leads to Amherst", bool(door["ok"]) and d.current_map() == AMHERST,
		"%s via %s (%s)" % [door["to"], door["via"], "; ".join(door["issues"])])

	# Rain's conversation ended with the End Chat button (a mouse click on the dialogue).
	if d.current_map() == AMHERST:
		var rain: Dictionary = await d.talk_to(RAIN)
		if d.soft_check("Rain can be reached on foot", bool(rain["open"])):
			var after: Dictionary = await d.choose("end")
			d.check("End Chat closes Rain's conversation", not bool(after["open"]) and not bool(d.state().get("modal", true)))

	# Sam's conversation answered page by page: next() on lines, "no" on his offer (Y/N), a menu's first choice.
	await d.console("warp " + HUNTING)
	await d.console("god on")  # setup: the Snails here would interrupt the conversation walk
	var active0 := d.character().quests.active_ids()
	var sam: Dictionary = await d.talk_to(SAM)
	if d.soft_check("Sam can be reached on foot", bool(sam["open"])):
		var seen := {}
		var answers := 0
		var v := d.read_dialogue()
		while bool(v["open"]) and answers < 12:
			answers += 1
			seen[String(v["type"])] = true
			if String(v["type"]) == "menu":
				v = await d.choose(0)
			elif String(v["type"]) == "yes_no":
				v = await d.choose("no")
			else:
				v = await d.next()
		d.check("Sam's conversation answered with next() and choose()", answers >= 2 and not bool(v["open"]),
			"%d answers, views %s" % [answers, seen.keys()])
		if seen.has("yes_no"):
			d.check("declining Sam's offer starts no quest", d.character().quests.active_ids() == active0,
				"%s, before %s" % [d.character().quests.active_ids(), active0])
		await d.close_dialogue()
	await d.console("god off")

	# Nothing to pick up, a mouse click on the pause menu, and the state.
	var pick: Dictionary = await d.pickup_all_nearby(3.0, 3.0)
	d.check("pickup with nothing around picks nothing", int(pick["picked"]) == 0)
	await d.tap_key(KEY_ESCAPE)
	await d.frames(3)
	var resume: Dictionary = await d.click("Resume")
	d.check("a mouse click on the pause menu's Resume", bool(resume["ok"]) and d.main.flow.is_in(ShellFlow.State.PLAYING), str(resume))
	var s := d.state()
	d.check("state() reads the map, vitals and inventory", s.get("map") == d.current_map() and int(s.get("hp", 0)) > 0
		and (s.get("inventory", {}) as Dictionary).has("use"), str(s.get("inventory")).left(160))
	await d.screenshot("amherst")
