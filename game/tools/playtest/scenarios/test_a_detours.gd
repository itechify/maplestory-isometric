extends PlaytestScenario
## test_a_detours (play-A): the in-map stretches of test_a_traversal whose walked distance was 2x or more the straight
## distance between the arrival and the exit portal. For each: a console warp to the arrival portal (setup), then the
## walk to the exit portal with the route planner (the exported Iteration One routes) and again with the grid planner
## (A* on the real collision). The result says whether the detour is the world's (both long) or only the routes' (the
## grid finds a much shorter way a player could take).

## [map, arrival portal (where the traversal entered), exit portal]
const STRETCHES: Array = [
	["000000030", "in00", "out00"],
	["000000042", "west00", "east00"],
	["000001000", "west00", "in00"],
	["000001000", "in02", "in03"],
	["000001000", "in03", "in04"],
	["000001000", "in01", "in02"],
	["000001000", "in05", "east00"],
	["000001010", "west00", "in00"],
	["000000020", "in00", "in01"],
	["000001010", "in02", "in01"],
]


func description() -> String:
	return "long in-map stretches of the traversal: the routes planner against the grid planner, straight distance for scale"


func max_seconds() -> float:
	return 1800.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Measurer", "female")
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	await d.console("god on")
	var defs := d.world().defs
	for st: Array in STRETCHES:
		var map_id := String(st[0])
		var a := defs.portal(map_id, String(st[1]))
		var b := defs.portal(map_id, String(st[2]))
		if a == null or b == null:
			d.check("portals %s %s/%s exist" % [map_id, st[1], st[2]], false)
			continue
		var straight := Vector2(b.anchor_ground.x - a.spawn_transform.origin.x, b.anchor_ground.z - a.spawn_transform.origin.z).length()
		var line := PackedStringArray()
		for planner: String in ["routes", "grid"]:
			await d.console("warp %s %s" % [map_id, a.portal_id])
			var r: Dictionary = await d.walk_to("portal:" + b.portal_id, {"planner": planner, "max_s": 120.0, "within_m": 1.0})
			line.append("%s: %s %.1f s / %.1f m (%s, %d prop cells)" % [planner, "ok" if bool(r["ok"]) else String(r.get("result", "")),
				float(r.get("time_s", 0.0)), float(r.get("distance_m", 0.0)), String(r.get("how", "")), int(r.get("props", 0))])
		d.note("DETOUR %s %s -> %s: straight %.1f m, dy %.1f m; %s" % [map_id, a.portal_id, b.portal_id, straight,
			b.anchor_ground.y - a.spawn_transform.origin.y, "; ".join(line)])
	d.check("measured", true)
