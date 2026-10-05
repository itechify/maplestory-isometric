extends PlaytestScenario
## test_a_ladders (play-A): Up is both "climb" and "enter portal" (Controls: portal_enter). A ladder, rope or vine whose
## foot stands inside a portal's trigger cannot be climbed from the foot: the fresh Up press uses the portal
## (PortalInteractor) first. test_a_routes met it in 000001005 (the JumpTower ladder beside out00). This survey checks
## every climbable of the island against every press-Up portal trigger (geometry, an observation), then verifies each
## overlap with real input: a console warp to the map (setup), a walk to the climbable's foot, Up held as a player
## climbing it would. A soft check per overlap; the run passes when the survey ran.

const FOOT_SAMPLES_M: Array[float] = [0.0, 0.4, 0.8]


func description() -> String:
	return "every ladder/rope/vine foot against every press-Up portal trigger; overlaps verified with real Up presses"


func max_seconds() -> float:
	return 1800.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Climber", "female")
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	await d.console("god on")
	var w := d.world()
	var p := d.player()
	var overlaps: Array = []
	var nodes: Array = w.get_tree().get_nodes_in_group(&"portals")
	for c: ClimbableDef in p.climbables:
		var foot := c.foot_ground if c.has_foot_ground else c.bottom
		for n: Node in nodes:
			var wp := n as WorldPortal
			if wp == null or wp.def == null or wp.def.hidden or not wp.def.accepts_press():
				continue
			var shape := wp.trigger.shape as BoxShape3D
			if shape == null:
				continue
			# The body capsule (0.3 m radius, from 0.45 m above the feet) overlaps the box when the feet are within
			# the half extents plus the radius; the grab radius lets a player stand up to 0.8 m from the line.
			var inv := wp.trigger.global_transform.affine_inverse()
			var half := shape.size * 0.5 + Vector3(0.3, 0.0, 0.3)
			var best := INF
			var grab := Vector3.INF
			for r: float in FOOT_SAMPLES_M:
				for k in 8:
					if r == 0.0 and k > 0:
						continue
					var a := TAU * k / 8.0
					var q := foot + Vector3(cos(a), 0.0, sin(a)) * r + Vector3.UP * 0.9
					var l := inv * q
					if absf(l.x) <= half.x and absf(l.y) <= half.y + 0.45 and absf(l.z) <= half.z:
						if r < best:
							grab = q - Vector3.UP * 0.9
						best = minf(best, r)
			if best < INF:
				overlaps.append({"climbable": c.name, "kind": String(c.kind), "foot": foot, "top": c.top,
					"portal": wp.def.key(), "map": wp.def.source_map_id, "to": wp.def.destination_map_id,
					"anchor": wp.def.anchor_ground, "within_m": best, "grab": grab,
					"foot_to_anchor_m": snappedf(Vector2(foot.x - wp.def.anchor_ground.x, foot.z - wp.def.anchor_ground.z).length(), 0.01)})
	d.note("SURVEY %d climbables x %d portal triggers: %d overlaps (a climbable's foot within 0.8 m of a press-Up trigger)" % [
		p.climbables.size(), nodes.size(), overlaps.size()])
	for o: Dictionary in overlaps:
		d.note("OVERLAP %s %s foot %s (top y %.1f) vs %s -> %s trigger: grab point %.1f m from the foot is inside; foot %.2f m from the portal anchor" % [
			o["kind"], o["climbable"], _v(o["foot"]), (o["top"] as Vector3).y, o["portal"], o["to"], o["within_m"], o["foot_to_anchor_m"]])
	# Real input: stand at the foot (or the grab point found inside) and hold Up.
	for o: Dictionary in overlaps:
		var map_id := String(o["map"])
		for spot: String in ["foot", "grab"]:
			await d.wait_idle(10.0)
			await d.console("warp " + map_id)
			if d.current_map() != map_id:
				continue
			var target: Vector3 = o[spot]
			if target == Vector3.INF:
				continue
			# The grab point is reached from the portal's side (a player coming in off the trail): walk to the portal's
			# anchor first, then to the point.
			if spot == "grab":
				await d.walk_to(o["anchor"] as Vector3, {"within_m": 1.0, "max_s": 60.0})
			var r: Dictionary = await d.walk_to(target, {"within_m": 0.25, "max_s": 60.0, "planner": "grid"})
			var s0 := d.state()
			var under := w.portal_under_player()
			var before := d.current_map()
			await d.press(&"portal_enter", 1.2)
			await d.wait_idle(10.0)
			var s1 := d.state()
			var t: Dictionary = s1.get("last_transition", {})
			var warped := d.current_map() != before
			var climbed := (s1.get("position", Vector3.ZERO) as Vector3).y - (s0.get("position", Vector3.ZERO) as Vector3).y
			d.soft_check("%s: Up at the %s of %s %s (%s) climbs instead of using %s" % [map_id, spot, o["kind"], o["climbable"], _v(target), o["portal"]],
				not warped, "walk %s (%s); stood at %s, %.2f m from the climbable's foot, inside trigger %s; after Up: map %s via %s, rose %.2f m" % [
				r.get("result", ""), r.get("how", ""), _v(s0.get("position")),
				Vector2((s0.get("position") as Vector3).x - (o["foot"] as Vector3).x, (s0.get("position") as Vector3).z - (o["foot"] as Vector3).z).length(),
				under.def.key() if under != null else "none", d.current_map(), String(t.get("via", "")), climbed])
			if warped:
				await d.screenshot("ladder_portal_%s_%s_%s" % [map_id, String(o["climbable"]), spot])
	d.carry["overlaps"] = overlaps
	d.check("the survey ran", true, "%d overlaps" % overlaps.size())


static func _v(v: Variant) -> String:
	if v is Vector3:
		var u := v as Vector3
		return "(%.1f, %.1f, %.1f)" % [u.x, u.y, u.z]
	return str(v)
