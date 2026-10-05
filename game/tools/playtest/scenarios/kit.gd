extends PlaytestScenario
## kit: PlaytestKit's own check in the real game, for the helpers no other scenario exercises yet (the reference run,
## like `api` is for the driver). After a logged console setup (mesos, a level, a pair of sandals, a warp to Lucy's
## Amherst Department Store): AP spent through the stats window, Lucy's shop opened by talking, Red Potions bought
## and one sold back at canonical prices, a potion bound to a quickslot by a mouse drag and used with its key, one
## drunk through the Item window, the sandals equipped by a double-click, a checkpoint, and the contract helpers:
## The Green Relaxer from the Set-up tab and with the X key (C4/C5), Recovery learned with the Skills window's "+"
## (learn_skill), put on key 2 (bind_skill) and cast with it (C3), and the store's Wooden Box (C8). The chair and box
## checks were WARNs until the mechanics and breakables packages were merged (wave 1); they are hard checks now.

const STORE := "000001013"
const LUCY := "21"
const POTION := "270"
const SANDALS := "1305"
## The Green Relaxer (canonical items/522.json: a Setup item with setup data, contract C5's chair).
const CHAIR := "522"
const KEY := "1"

var d: PlaytestDriver = null
var k: PlaytestKit = null


func description() -> String:
	return "PlaytestKit in the real game: AP, a shop by talking, buy and sell, quickslot, drink, equip, checkpoint, contract helpers"


func max_seconds() -> float:
	return 300.0


func run(p_d: PlaytestDriver) -> void:
	d = p_d
	k = PlaytestKit.new(d)
	var db := d.db()
	var ng: Dictionary = await d.new_game("KitCheck", "male", "585", {"str": 5, "dex": 4})
	if not d.check("new game through the screens", bool(ng["ok"]), str(ng)):
		return
	k.connect_bus()
	await _setup_console("mesos 1000")
	await _setup_console("level 3")
	await _setup_console("give %s 1" % SANDALS)
	await _setup_console("give %s 1" % CHAIR)
	await _setup_console("warp %s" % STORE)
	var c := d.character()

	# --- AP through the stats window --------------------------------------------------------------------------------
	var ap0 := c.ap
	var s0 := c.base_stats.duplicate()
	var al: Dictionary = await k.allocate_ap(["str", "dex"])
	d.check("allocate_ap: every unspent AP through the stats window's '+' (%d)" % ap0, bool(al["ok"]) and int(al["spent"]) == ap0
		and c.ap == 0 and c.get_base_stat("str") + c.get_base_stat("dex") == int(s0["str"]) + int(s0["dex"]) + ap0,
		"%s; stats %s -> %s" % [al, s0, c.base_stats])

	# --- the shop -----------------------------------------------------------------------------------------------------
	var opened := await k.open_shop(LUCY)
	if not d.check("open_shop: talking to Lucy opens her shop", opened, ""):
		return
	var shop_id := String(d.shop().get("shop_id"))
	var price := int(ShopService.row_for(shop_id, POTION, db).get("price", -1))
	var buy: Dictionary = await k.buy(POTION, 3)
	d.check("buy: 3 Red Potions at the canonical price %d" % price, bool(buy["ok"]) and int(buy["count_delta"]) == 3
		and int(buy["mesos_delta"]) == -3 * price, str(buy), ["shop:" + shop_id, "item:" + POTION])
	var sell: Dictionary = await k.sell(POTION, 1)
	d.check("sell: 1 back at the canonical sell price %d" % ShopService.sell_price(POTION, db), bool(sell["ok"])
		and int(sell["count_delta"]) == -1 and int(sell["mesos_delta"]) == ShopService.sell_price(POTION, db), str(sell),
		["shop:" + shop_id])
	d.check("close_shop", await k.close_shop(), "")

	# --- items --------------------------------------------------------------------------------------------------------
	var b: Dictionary = await k.bind_quickslot(POTION, KEY)
	d.check("bind_quickslot: a mouse drag binds the potion to key %s" % KEY, bool(b["ok"]), str(b))
	var n0 := c.inventory.count(POTION)
	var q: Dictionary = await k.use_item(POTION, "quickslot")
	d.check("use_item via the quickslot key uses one", bool(q["ok"]) and c.inventory.count(POTION) == n0 - 1, str(q))
	var dr: Dictionary = await k.drink(POTION)
	d.check("drink: one through the Item window's Use button, HP + the canonical restore (capped)", bool(dr["ok"])
		and int(dr["hp1"]) == int(dr["want_hp"]), String(dr["row"]))
	var eq: Dictionary = await k.equip(SANDALS)
	d.check("equip: a double-click in the Equip tab equips the sandals", bool(eq["ok"]), str(eq), ["item:" + SANDALS])
	var cp := k.checkpoint("kit")
	d.check("checkpoint: recorded in carry", (d.carry.get("checkpoints", []) as Array).size() == 1 and int(cp["level"]) == c.level,
		str(cp).left(200))

	# --- contract helpers ---------------------------------------------------------------------------------------------
	# The chair (C5: The Green Relaxer, a Setup item with setup data) is in the bag from the setup.
	var ch: Dictionary = await k.use_chair(CHAIR)
	d.check("use_chair: a double-click on the chair in the Set-up tab seats the player (contracts C4/C5)",
		bool(ch["ok"]), str(ch), ["chair:" + CHAIR])
	if bool(ch["ok"]):
		var up0: Dictionary = await k.stand()
		d.check("stand: a step stands the player up from the chair", bool(up0["ok"]), str(up0), ["chair:" + CHAIR])
	var st: Dictionary = await k.sit()
	d.check("sit (X): seated on the first chair the character owns (contracts C4/C5)", bool(st["ok"]), str(st),
		["chair:" + CHAIR])
	if bool(st["ok"]):
		var up: Dictionary = await k.stand()
		d.check("stand: a step stands the player up", bool(up["ok"]), str(up))
	# The level 3 setup gave 2 SP: Recovery learned with the Skills window's "+", put on key 2 with Set key, cast.
	var ls: Dictionary = await k.learn_skill("0001001")
	d.check("learn_skill: K and Recovery's '+' spend one SP", bool(ls["ok"]), str(ls), ["skill:0001001", "mechanic:skill-window"])
	var bs: Dictionary = await k.bind_skill("0001001", "2")
	d.check("bind_skill: Recovery on key 2 with the Skills window's Set key", bool(bs["ok"]), str(bs), ["mechanic:skill-window"])
	var sk: Dictionary = await k.cast_skill("0001001")
	d.check("cast_skill: Recovery from its quickslot key (contract C3)", bool(sk["ok"]), str(sk), ["skill:0001001"])
	d.check("breakables: Wooden Boxes in %s (contract C8)" % STORE, not k.breakables(true).is_empty(),
		"%d nodes in group miso_breakables" % k.breakables(true).size())


func _setup_console(cmd: String) -> void:
	await d.console(cmd)
