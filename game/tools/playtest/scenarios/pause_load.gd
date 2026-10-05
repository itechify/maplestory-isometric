extends PlaytestScenario
## pause_load: the pause menu's Load inside one running session (contract C3: monsters, ground drops and Wooden Box
## state are never saved, so a load must not inherit them from the live map). A new game through the title and
## creation screens; setup by console (logged): a warp to Amherst Weapon Store (000001011, two canonical Wooden
## Boxes). Save through the pause menu; break a box with the attack key (PlaytestKit.break_box, which also picks up
## what it dropped); two Snail Shells put on the ground (console setup). Then Esc, the pause menu's Load and the slot's
## Load button (PlaytestDriver.load_from_pause_menu): the same map, a new map instance (the live one is not taken back
## from the cache), both boxes whole with every hit left, no ground-drop record or node, nothing parked in the map
## cache, and the character as saved (EXP, mesos, inventory). Adopted from the wave-2 integration review's scratch
## scenario (zz_rev_pause_load.gd: 12 checks; it failed 3 on the code before the integration fixes).

const MAP := "000001011"
const WEAPON := "585"
const SHELL := "348"


func description() -> String:
	return "the pause menu's Load in a running session starts the map fresh: boxes whole, no ground drops, the saved character"


func max_seconds() -> float:
	return 600.0


func run(d: PlaytestDriver) -> void:
	var k := PlaytestKit.new(d)
	var ng: Dictionary = await d.new_game("PauseLoad", "female", WEAPON)
	if not d.check("new game through the screens", bool(ng["ok"]) and ng["via"] == "screen", str(ng)):
		return
	await _setup_warp(d)
	await d.wait_idle(20.0)
	await d.wait(0.5)
	var sv: Dictionary = await d.save_game()
	var slot := String(sv.get("slot", ""))
	d.check("saved through the pause menu in %s" % MAP, bool(sv["ok"]) and sv["via"] == "screen" and d.current_map() == MAP,
		str(sv), ["mechanic:save-load"])
	var saved := _char_subset(d.character())
	var canon := BreakableRules.placements_of(d.db().map(MAP)).size()
	var boxes := k.breakables(true)
	d.check("%s shows its %d canonical Wooden Boxes, intact" % [MAP, canon], boxes.size() == canon and canon > 0
		and boxes.all(func(b: Node) -> bool: return not bool(b.call("is_broken"))), _boxes_text(boxes),
		["breakable-placement:" + MAP])
	if boxes.is_empty():
		return
	var r: Dictionary = await k.break_box(boxes[0])
	d.check("a box broken with the attack key after the save", bool(r["ok"]), str(r))
	await _setup_drop(d)
	await d.wait(0.6)
	var st_before: MapInstanceState = d.session().get("instance_state")
	var nodes_before := (d.loot().call("nodes") as Dictionary).size()
	var broken_before := k.breakables(true).filter(func(b: Node) -> bool: return bool(b.call("is_broken"))).size()
	d.check("before the load: a broken box and drops on the ground", broken_before >= 1 and st_before != null
		and st_before.drops.size() > 0 and nodes_before > 0,
		"%d broken boxes, %d drop records, %d drop nodes" % [broken_before, st_before.drops.size() if st_before != null else -1,
			nodes_before])

	var ld: Dictionary = await d.load_from_pause_menu(slot)
	d.check("Esc, Load, the slot's Load: the save is loaded through the pause menu", bool(ld["ok"]) and ld["via"] == "screen",
		str(ld), ["mechanic:save-load"])
	await d.wait(1.0)
	var st_after: MapInstanceState = d.session().get("instance_state")
	d.check("still in %s after the load" % MAP, d.current_map() == MAP, d.current_map(), ["persistence:current-map"])
	d.check("a new map instance (the live one is not taken back)", st_after != null and st_after != st_before, "",
		["mechanic:save-load"])
	var after := k.breakables(true)
	d.check("both boxes whole after the load (box state is not saved)", after.size() == canon and after.all(func(b: Node) -> bool:
		return not bool(b.call("is_broken")) and int(b.call("hits_left")) == BreakableRules.hits_to_break(BreakableRules.WOODEN_BOX, d.db())),
		_boxes_text(after), ["persistence:breakable-state"])
	var nodes_after := (d.loot().call("nodes") as Dictionary).size()
	d.check("no ground drop record or node survives the load", st_after != null and st_after.drops.size() == 0 and nodes_after == 0,
		"%d records, %d nodes" % [st_after.drops.size() if st_after != null else -1, nodes_after], ["mechanic:save-load"])
	d.check("nothing parked in the map cache survives the load", (d.session().get("cache") as Object).call("size") == 0, "",
		["mechanic:save-load"])
	var now := _char_subset(d.character())
	var bad: PackedStringArray = []
	for key: String in saved:
		var df := PlaytestDriver.diff(saved[key], now[key], "$." + key)
		if df != "":
			bad.append(df)
	d.check("the character is the saved one (EXP, mesos, inventory, quests)", bad.is_empty(), "; ".join(bad),
		["persistence:level-exp", "persistence:mesos", "persistence:inventory"])


func _setup_warp(d: PlaytestDriver) -> void:
	await d.console("warp " + MAP)


func _setup_drop(d: PlaytestDriver) -> void:
	await d.console("drop_item %s 2" % SHELL)


static func _char_subset(c: CharacterState) -> Dictionary:
	var all := c.to_dict()
	var out := {}
	for key: String in ["level", "exp", "mesos", "inventory", "equipment", "quests"]:
		out[key] = all.get(key)
	return out


static func _boxes_text(boxes: Array) -> String:
	return ", ".join(PackedStringArray(boxes.map(func(b: Node) -> String:
		return "%s broken %s hits_left %d" % [b.call("placement_key"), b.call("is_broken"), int(b.call("hits_left"))])))
