extends PlaytestScenario
## reload: a real process reload, the pattern Tests D, E and F need ("save, quit, reload"). Phase 0: a new game, a
## walk along route ToHouseDoor of 000000001, then reload_process() (the pause menu's Quit Game: the shell saves and
## the application quits). Phase 1, a new process on the same save directory: Continue on the title, and the same map,
## place and character. Values cross the process boundary in d.carry, with their Godot types.

const MAP := "000000001"


func description() -> String:
	return "new game, a walk, Quit Game, a new process, Continue: the same map, place and character"


func max_seconds() -> float:
	return 180.0


func run(d: PlaytestDriver) -> void:
	if d.phase == 0:
		var ng: Dictionary = await d.new_game("Reloader", "male", "576", {"dex": 4, "str": 5})
		if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
			return
		var r: Dictionary = await d.walk_route(MAP, "ToHouseDoor")
		d.check("walked route ToHouseDoor", bool(r["ok"]), "; ".join(r["issues"]))
		await d.wait(0.5)
		var s := d.state()
		d.carry["map"] = s["map"]
		d.carry["position"] = s["position"]
		d.carry["character"] = d.character().to_dict()
		d.carry["slot"] = s["slot"]
		await d.reload_process()
		return
	d.check("this is the second process", d.phase == 1, "phase %d" % d.phase)
	d.check("the title offers Continue for the saved slot", d.main.title.continue_button.visible
		and d.main.title.continue_slot == String(d.carry.get("slot", "")),
		"%s, saved %s" % [d.main.title.continue_slot, d.carry.get("slot", "")])
	var c: Dictionary = await d.continue_game()
	if not d.check("continued", bool(c["ok"]) and c["via"] == "screen", str(c)):
		return
	var s := d.state()
	d.check("the same map after the reload", s["map"] == d.carry.get("map"), "%s, saved %s" % [s["map"], d.carry.get("map")])
	var off := (s["position"] as Vector3).distance_to(d.carry.get("position", Vector3.INF))
	d.check("the same place after the reload", off < 1.0, "%.2f m from where the game quit" % off)
	var before: Dictionary = d.carry.get("character", {})
	var now := d.character().to_dict()
	for key in ["name", "gender", "level", "exp", "mesos", "base_stats", "equipment", "inventory", "quests"]:
		var diff := PlaytestDriver.diff(before.get(key), now.get(key))
		d.check("%s survives the reload" % key, diff == "", diff)
