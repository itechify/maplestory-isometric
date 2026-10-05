extends PlaytestScenario
## walk_probe: can the walker get from a spot to a target? Places the player at a map-local point (an API teleport:
## setup for the diagnosis, like trap_probe) and walks to the target with the walker's planners, reporting the plan
## and the walk. For walks a scenario saw fail from an odd spot (a knockback off a terrace):
##   WALK_MAP=000001000 WALK_FROM="29.0,0,-40.6" WALK_TO="portal:in01" bash scripts/playtest.sh walk_probe
## WALK_TO is any walk_to target ("portal:<id>", "npc:<id>", "local:x,y,z", "spawn:<n>"), or "talk:<npc id>": then
## PlaytestKit.talk() plays it as the scenarios do (its approach points, the walk back to the arrival, unstick()) and
## the check is that the conversation opens. The check fails when the walk does not arrive.


func description() -> String:
	return "probe a walk from a map-local spot to a target (WALK_MAP, WALK_FROM, WALK_TO)"


func max_seconds() -> float:
	return 240.0


func run(d: PlaytestDriver) -> void:
	var map := OS.get_environment("WALK_MAP")
	var parts := OS.get_environment("WALK_FROM").split(",")
	var target := OS.get_environment("WALK_TO")
	if not d.check("WALK_MAP, WALK_FROM (x,y,z) and WALK_TO are set", map != "" and parts.size() == 3 and target != "",
			"%s / %s / %s" % [map, parts, target]):
		return
	var ng: Dictionary = await d.new_game("Walker", "male", "585", {"str": 9})
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	await d.console("warp " + map)
	await d.console("god on")
	var p := d.player()
	var w := d.world()
	var def := w.defs.get_def(map)
	var spot := def.to_world(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	var space := p.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 20.0, spot + Vector3.DOWN * 5.0))
	if not hit.is_empty():
		spot = hit.position
	w.place_player(Transform3D(p.global_transform.basis, spot + Vector3.UP * 0.05))
	await d.wait(0.5)
	if target.begins_with("talk:"):
		var k := PlaytestKit.new(d)
		var npc := target.trim_prefix("talk:")
		var v: Dictionary = await k.talk(npc)
		d.check("PlaytestKit.talk(%s) from local %s opens the conversation" % [npc, OS.get_environment("WALK_FROM")],
			bool(v.get("open", false)), "%s; ended at local %s; unsticks %d" % [String(v.get("why", "")).left(200),
				def.to_local(p.global_position), int(k.survival.get("unsticks", 0))])
		return
	var t := d.resolve_target(target)
	if not d.check("the target resolves", bool(t["ok"]), String(t.get("why", ""))):
		return
	var pl := d.walker.plan(t["position"])
	d.note("plan from %s: %s, %d points" % [def.to_local(p.global_position), pl["how"], (pl["path"] as PackedVector3Array).size()])
	var r: Dictionary = await d.walk_to(target, {"max_s": 90.0, "within_m": 1.0})
	d.check("walked from local %s to %s" % [OS.get_environment("WALK_FROM"), target], bool(r["ok"]),
		"%s via %s in %.1f s, %.1f m; ended at local %s; %s" % [r.get("result", ""), r.get("how", ""), float(r.get("time_s", 0.0)),
			float(r.get("distance_m", 0.0)), def.to_local(p.global_position), "; ".join(r.get("issues", PackedStringArray()))])
