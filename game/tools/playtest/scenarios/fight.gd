extends PlaytestScenario
## fight: real combat in Snail Hunting Ground I. A new game, a console warp to 000000040 (setup: getting there on
## foot is the traversal scenarios' job), then the attack key against Snails until a kill drops loot (a kill may roll
## nothing, so it fights on, bounded), and the drop picked up with the pickup key. Checks the canonical EXP of every
## kill (MonsterDef.exp_reward against Events.exp_gained "monster:<id>") and that the pickup reached the inventory or
## the mesos.

const MAP := "000000040"
const SNAIL := "2"


func description() -> String:
	return "in %s: the attack key against Snails until a kill drops loot, then the pickup key" % MAP


func max_seconds() -> float:
	return 360.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Fighter", "male", "585", {"str": 9})
	d.check("new game", bool(ng["ok"]), String(ng["why"]))
	if not bool(ng["ok"]):
		return
	await d.console("warp " + MAP)
	if not d.check("in Snail Hunting Ground I", d.current_map() == MAP, d.current_map()):
		return
	await d.wait(1.0)
	var drops: Array = []
	var on_loot := func(list: Array, at: Vector3, map_id: String) -> void:
		if map_id == MAP and not list.is_empty():
			drops.append({"count": list.size(), "at": at})
	var gained := [0]
	var on_exp := func(amount: int, source: String) -> void:
		if source.begins_with("monster:"):
			gained[0] += amount
	var died: Array = []
	var on_died := func(m: Node) -> void: died.append(m.get("def"))
	d.events().connect(&"loot_dropped", on_loot)
	d.events().connect(&"exp_gained", on_exp)
	d.monsters().connect(&"monster_died", on_died)

	var fight: Dictionary = await d.fight_until(func() -> bool: return not drops.is_empty(), 240.0, {"mob_id": SNAIL})
	d.events().disconnect(&"loot_dropped", on_loot)
	d.events().disconnect(&"exp_gained", on_exp)
	d.monsters().disconnect(&"monster_died", on_died)
	d.check("Snails died to the attack key", int(fight["kills"]) >= 1 and int(fight["hits"]) >= 1,
		"%d kills, %d attacks, %d hits in %.1f s" % [int(fight["kills"]), int(fight["attacks"]), int(fight["hits"]),
			float(fight["time_s"])])
	var expected := 0
	for def: Variant in died:
		expected += int(def.get("exp_reward"))
	d.check("every kill gave its canonical EXP", expected > 0 and gained[0] == expected,
		"%d EXP gained, %d expected from %d deaths" % [gained[0], expected, died.size()])
	d.check("a kill dropped loot", not drops.is_empty(), "%d kills, %d with a drop" % [int(fight["kills"]), drops.size()])
	if drops.is_empty():
		return
	d.check("the player is alive", not bool(d.state().get("dead_state", true)))
	await d.screenshot("drops")

	var mesos0 := d.character().mesos
	var items0 := _item_total(d)
	var picked: Dictionary = await d.pickup_all_nearby(8.0, 60.0)
	d.check("the drop was picked up with the pickup key", int(picked["picked"]) >= 1,
		"%d picked, %d refused, %d left" % [int(picked["picked"]), int(picked["refused"]), int(picked["left"])])
	d.check("the pickup reached the inventory or the mesos", d.character().mesos > mesos0 or _item_total(d) > items0,
		"mesos %d -> %d, items %d -> %d" % [mesos0, d.character().mesos, items0, _item_total(d)])
	d.check("nothing left on the ground in reach", int(picked["left"]) == 0 or int(picked["refused"]) > 0,
		"%d left, %d refused" % [int(picked["left"]), int(picked["refused"])])
	await d.screenshot("after_pickup")


static func _item_total(d: PlaytestDriver) -> int:
	var n := 0
	for tab: Variant in d.inventory_summary():
		for row: Dictionary in d.inventory_summary()[tab]:
			n += int(row["qty"])
	return n
