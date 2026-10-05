extends PlaytestScenario
## test_a_traversal (play-A): brief Test A, the entire island on foot. From a NEW GAME at 000000001 the player walks
## every trail across its far gate and uses every door with Up, visiting all 25 maps in the brief's order (Mushroom
## Town, the Snail Hunting Grounds, A Split Road, the Field West of Amherst and its six branches, Amherst and its
## interiors, the Snail Field of Flowers, the Field East of Amherst and the Tomato Field, then back west to Southperry
## and its Armor Store) and using every canonical portal at least once ("check" legs walk the reverse trails the
## journey does not). Each leg records its walking time (approach to the portal, the trail to the far gate, the gate
## to the arrival point), the transition (map, via, source portal), the arrival banner against the canonical map
## record, the trail line, the grounding at the arrival (floor, region, distance from the arrival point, kill_y,
## re-placement), hits taken, and per map the World Review numbers (footprint area, spawn slots and live monsters,
## NPCs, portal distances, and whether each exit is in the camera's view at the arrival). Windowed runs take a
## screenshot at each map's first arrival (right after the gate commits or the door's fade, with the banner up).
##
## Env options (setup only): PLAYA_GOD=1 runs with `god on` (logged), PLAYA_LEGS=a-b runs a slice of the tour (the
## slice starts with a console warp to its first map's arrival).
## The walker is monster-aware (PlaytestKit's survival policy): a monster it can beat that keeps hitting it is fought,
## and below 40% HP it drinks what it holds or walks away and rests, then walks the leg on. These interruptions are
## not leg attempts; each leg counts them ("survival").

const START := "000000001"
## The tour after the start map: [to_map, tag]. "journey" = the island's natural order; "check" = a leg that exists
## only to use a portal the journey does not (a reverse trail).
const TOUR: Array = [
	["000000010", "journey"], ["000000001", "check"], ["000000010", "check"],
	["000000020", "journey"], ["000000010", "check"], ["000000020", "check"],
	["000000021", "journey"], ["000000020", "journey"],
	["000000030", "journey"], ["000000020", "check"], ["000000030", "check"],
	["000000040", "journey"],
	["000000041", "journey"], ["000000040", "check"], ["000000041", "check"],
	["000000042", "journey"], ["000000041", "check"], ["000000042", "check"],
	["000000050", "journey"], ["000000042", "check"], ["000000050", "check"],
	["000001000", "journey"],
	["000001001", "journey"], ["000001000", "journey"],
	["000001002", "journey"], ["000001000", "journey"],
	["000001003", "journey"], ["000001000", "journey"],
	["000001004", "journey"], ["000001000", "journey"],
	["000001005", "journey"], ["000001000", "journey"],
	["000001006", "journey"], ["000001000", "journey"],
	["000001010", "journey"],
	["000001011", "journey"], ["000001010", "journey"],
	["000001013", "journey"], ["000001010", "journey"],
	["000001012", "journey"], ["000001014", "journey"], ["000001012", "journey"], ["000001010", "journey"],
	["000001020", "journey"], ["000001021", "journey"], ["000001020", "journey"],
	["000001010", "journey"], ["000001000", "journey"], ["000000050", "journey"],
	["000000060", "journey"], ["000000061", "journey"], ["000000060", "journey"],
	["000000050", "check"], ["000000060", "check"],
]
## Grounding tolerances at the arrival.
const ARRIVE_WITHIN_M := 1.0
const DOOR_ARRIVE_M := 0.15
const KILL_Y_MARGIN_M := 2.0

var d: PlaytestDriver = null
var kit: PlaytestKit = null
var hits := {"n": 0, "dmg": 0, "deaths": 0}
var banner_at_entry := {}
var trail_seen := {}
var legs_out: Array = []
var review := {}
var used_portals := {}
var visited := {}
var shot_maps := {}
var via_door := "door"
var via_press := "press_up"
var via_gate := "gate"


func description() -> String:
	return "Test A: the whole island on foot from a new game, every trail through its gates, every door with Up, all 25 maps and every portal"


func max_seconds() -> float:
	return 4200.0


func run(driver: PlaytestDriver) -> void:
	d = driver
	var consts: Dictionary = (d.session().get_script() as Script).get_script_constant_map()
	via_door = String(consts.get("VIA_DOOR", "door"))
	via_press = String(consts.get("VIA_PRESS_UP", "press_up"))
	via_gate = String(consts.get("VIA_GATE", "gate"))
	var ng: Dictionary = await d.new_game("Walker", "female", "", {})
	if not d.check("new game through the title and creation screens", bool(ng["ok"]), "via %s: %s" % [ng["via"], ng["why"]]):
		return
	d.check("the new game starts in %s" % START, d.current_map() == START, d.current_map())
	if OS.get_environment("PLAYA_GOD") == "1":
		await d.console("god on")
		d.note("SETUP: god mode on (PLAYA_GOD=1): contact damage cannot kill or knock the walker off the tour")
	kit = PlaytestKit.new(d)
	kit.connect_bus()
	var ev := d.events()
	ev.connect("player_damaged", _on_damaged)
	ev.connect("player_died", _on_died)
	ev.connect("map_entered", _on_map_entered)

	var first := 0
	var last := TOUR.size() - 1
	var slice := OS.get_environment("PLAYA_LEGS")
	if slice.contains("-"):
		first = clampi(int(slice.get_slice("-", 0)), 0, TOUR.size() - 1)
		last = clampi(int(slice.get_slice("-", 1)), first, TOUR.size() - 1)
	var from := START if first == 0 else String((TOUR[first - 1] as Array)[0])
	if first > 0:
		var prev_from := START if first == 1 else String((TOUR[first - 2] as Array)[0])
		var pp := TraversalTour.portal_between(d.world().defs, prev_from, from)
		await d.console("warp %s %s" % [from, pp.destination_portal_id if pp != null else ""])
	visited[from] = true
	shot_maps[from] = true
	await d.wait_idle(5.0)
	await d.screenshot("arr_%s_%s" % [from, _name(from).replace(" ", "")])
	await _first_arrival(from, null)

	for i in range(first, last + 1):
		var to := String((TOUR[i] as Array)[0])
		var tag := String((TOUR[i] as Array)[1])
		var leg := await _leg(i, from, to, tag)
		legs_out.append(leg)
		if d.current_map() != to:
			d.check("the tour can go on after leg %d" % i, false, "stuck in %s after %s -> %s" % [d.current_map(), from, to])
			break
		from = to

	ev.disconnect("player_damaged", _on_damaged)
	ev.disconnect("player_died", _on_died)
	ev.disconnect("map_entered", _on_map_entered)
	_summarise(first == 0 and last == TOUR.size() - 1)


# ----------------------------------------------------------------------------------------------------------------
# One leg
# ----------------------------------------------------------------------------------------------------------------

func _leg(i: int, from: String, to: String, tag: String) -> Dictionary:
	var w := d.world()
	var defs := w.defs
	var src := TraversalTour.portal_between(defs, from, to)
	var leg := {"i": i, "from": from, "to": to, "tag": tag, "portal": "", "how": "", "ok": false, "via": "",
		"approach_s": 0.0, "approach_m": 0.0, "trail_s": 0.0, "trail_m": 0.0, "arrive_s": 0.0, "arrive_m": 0.0,
		"total_s": 0.0, "hits": 0, "damage": 0, "deaths": 0, "attempts": 0, "issues": [],
		"trail_line": "", "banner": "", "arrival_err_m": -1.0, "frames_to_ground": -1}
	if not d.check("leg %d: a portal leads %s -> %s" % [i, from, to], src != null):
		return leg
	leg["portal"] = src.key()
	var edge := defs.graph.is_edge(src.link_id)
	leg["how"] = "walk" if edge else "door"
	var h0 := hits.duplicate()
	var t0 := d.game_s()
	var res := {}
	var iss := PackedStringArray()
	var force_auto := false
	var start_pos := d.player().global_position
	for attempt in 3:
		leg["attempts"] = attempt + 1
		if d.current_map() != from:
			break
		var pl := _choose_planner(src.anchor_ground)
		if force_auto:
			pl["planner"] = "auto"
		leg["planner"] = pl["planner"]
		leg["plan_routes_m"] = pl["routes_m"]
		leg["plan_grid_m"] = pl["grid_m"]
		if edge:
			trail_seen.clear()
			var guard := kit.interrupt_when()
			var stop := func() -> bool:
				_sample_trail_line()
				return d.current_map() == to or bool(guard.call())
			for _s in PlaytestKit.MAX_INTERRUPTS:
				res = await d.walk_trail(from, to, {"stop_when": stop, "planner": pl["planner"]})
				var legs: Array = res.get("legs", [])
				if legs.size() >= 1:
					leg["approach_s"] = float(leg["approach_s"]) + float((legs[0] as Dictionary).get("time_s", 0.0))
					leg["approach_m"] = float(leg["approach_m"]) + float((legs[0] as Dictionary).get("distance_m", 0.0))
				if legs.size() >= 2:
					leg["trail_s"] = float(leg["trail_s"]) + float((legs[1] as Dictionary).get("time_s", 0.0))
					leg["trail_m"] = float(leg["trail_m"]) + float((legs[1] as Dictionary).get("distance_m", 0.0))
				if d.current_map() != from or kit.is_dead() or not bool(guard.call()):
					break
				# A monster that keeps hitting, or low HP: the survival policy, then the leg goes on (not an attempt).
				leg["survival"] = int(leg.get("survival", 0)) + 1
				await kit.survive()
		else:
			var td := d.game_s()
			# enter_portal walks with the default planner; walk to the door first with the chosen one.
			var wd: Dictionary = await kit.walk_safely("portal:" + src.portal_id, {"planner": pl["planner"], "within_m": 1.0})
			leg["survival"] = int(leg.get("survival", 0)) + int(wd.get("interrupts", 0))
			leg["approach_m"] = float(leg["approach_m"]) + float(wd.get("distance_m", 0.0))
			res = await d.enter_portal(src.portal_id)
			leg["approach_s"] = float(leg["approach_s"]) + d.game_s() - td
		for x: Variant in res.get("issues", PackedStringArray()):
			iss.append("try %d: %s" % [attempt + 1, str(x)])
		if d.current_map() == to:
			break
		if bool(d.state().get("dead_state", false)) or String(d.session().call("state_name")) == "DEAD":
			d.soft_check("leg %d %s -> %s: the walker survives" % [i, from, to], false,
				"died at %s in %s" % [str(d.player().global_position), d.current_map()])
			await _recover_from_death(from, i)
		elif pl["planner"] == "grid":
			# The grid's direct way did not walk (RouteBot stalled on it): walk back the way that worked to where the leg
			# started, then take the routes (the harness's route plan can stall from an off-route spot).
			force_auto = true
			iss.append("try %d: the direct (grid) way stalled at %s; back to the start, then the routes" % [attempt + 1, _v(d.player().global_position)])
			var back: Dictionary = await d.walk_to(start_pos, {"planner": "grid", "max_s": 60.0, "within_m": 1.0})
			if not bool(back.get("ok", false)):
				iss.append("try %d: could not walk back: %s" % [attempt + 1, "; ".join(back.get("issues", PackedStringArray()))])
		else:
			break
	leg["total_s"] = snappedf(d.game_s() - t0, 0.01)
	leg["issues"] = Array(iss)
	leg["hits"] = int(hits["n"]) - int(h0["n"])
	leg["damage"] = int(hits["dmg"]) - int(h0["dmg"])
	leg["deaths"] = int(hits["deaths"]) - int(h0["deaths"])
	var rec: Variant = d.session().get("last_transition")
	var tr: TransitionRecord = rec as TransitionRecord
	leg["via"] = tr.via if tr != null else ""
	var want_via := via_gate if edge else (via_door if src.portal_type == PortalDef.TYPE_DOOR else via_press)
	var arrived := d.current_map() == to
	d.check("leg %d %s -> %s: in %s (%s)" % [i, from, to, to, _name(to)], arrived, "ended in %s; %s" % [d.current_map(),
		"; ".join(iss)])
	if not arrived:
		return leg
	d.check("leg %d %s: the transition is %s -> %s via %s through %s" % [i, src.key(), from, to, want_via, src.portal_id],
		tr != null and tr.from_map == from and tr.to_map == to and tr.via == want_via and tr.portal_id == src.portal_id,
		str(tr))
	if tr != null:
		used_portals["%s.%s" % [tr.from_map, tr.portal_id]] = true
		leg["frames_to_ground"] = tr.frames_to_ground
		d.check("leg %d: no re-placement at the arrival (a broken destination spawn)" % i, not tr.replaced, str(tr.to_dict()))
	# The banner: what the HUD showed when the map was entered, against the canonical record.
	var want_banner := "%s / %s" % [String(d.db().map(to).get("street_name", "")), String(d.db().map(to).get("name", ""))]
	var got: Dictionary = banner_at_entry.get(to, {})
	leg["banner"] = String(got.get("text", ""))
	d.check("leg %d: the banner names %s" % [i, want_banner], String(got.get("text", "")) == want_banner and bool(got.get("visible", false)),
		"banner %s" % str(got))
	banner_at_entry.erase(to)
	if edge:
		leg["trail_line"] = String(trail_seen.get("text", ""))
		d.soft_check("leg %d: the trail line showed '-> %s' on the trail" % [i, _name(to)],
			String(trail_seen.get("text", "")) == "-> " + _name(to), str(trail_seen))
	var first_visit := not shot_maps.has(to)
	if first_visit:
		shot_maps[to] = true
		await d.screenshot("arr_%s_%s" % [to, _name(to).replace(" ", "")])
	# The arrival point: a gate commit leaves the walker on the trail's cap; walk on to the arrival as a player would.
	var arr_xf: Dictionary = defs.arrival_transform(defs.arrival_for(src))
	var arr: Vector3 = (arr_xf["xform"] as Transform3D).origin
	if edge:
		var at_commit := d.player().global_position
		var r: Dictionary = await d.walk_to(arr, {"within_m": 0.6, "max_s": 30.0})
		leg["arrive_s"] = float(r.get("time_s", 0.0))
		leg["arrive_m"] = float(r.get("distance_m", 0.0))
		if not bool(r.get("ok", false)):
			d.soft_check("leg %d: walked from the gate to %s's arrival" % [i, to], false, "; ".join(r.get("issues", PackedStringArray())))
			await d.screenshot("stall_%s_arrival" % to)
			_probe_between(at_commit, arr, "leg %d: what stands between the walker and %s's arrival" % [i, to])
	await d.wait_idle(5.0)
	_check_grounded(i, to, arr, edge)
	var s := d.state()
	leg["arrival_err_m"] = snappedf(_flat(s.get("position", Vector3.ZERO) - arr), 0.01)
	leg["ok"] = true
	visited[to] = true
	if first_visit:
		await _first_arrival(to, src)
	var line := "LEG %02d %s %s->%s (%s) %s: approach %.1f s/%.1f m, trail %.1f s/%.1f m, arrive %.1f s/%.1f m, total %.1f s; planner %s (plans: routes %.0f m, grid %.0f m); hits %d dmg %d deaths %d; attempts %d, survival stops %d%s" % [
		i, tag, from, to, src.key(), leg["how"], leg["approach_s"], leg["approach_m"], leg["trail_s"], leg["trail_m"],
		leg["arrive_s"], leg["arrive_m"], leg["total_s"], leg.get("planner", ""), float(leg.get("plan_routes_m", -1.0)), float(leg.get("plan_grid_m", -1.0)), leg["hits"], leg["damage"], leg["deaths"], leg["attempts"],
		int(leg.get("survival", 0)), "" if iss.is_empty() else "; issues: " + " | ".join(iss)]
	d.note(line)
	d.soft_check("leg %d %s -> %s walked cleanly (one attempt, no stall, no issue)" % [i, from, to],
		int(leg["attempts"]) == 1 and iss.is_empty(), " | ".join(iss))
	return leg


func _check_grounded(i: int, to: String, arr: Vector3, edge: bool) -> void:
	var s := d.state()
	var def := d.world().defs.get_def(to)
	var pos: Vector3 = s.get("position", Vector3.ZERO)
	var region: Dictionary = s.get("region", {})
	var err := _flat(pos - arr)
	var tol := ARRIVE_WITHIN_M if edge else DOOR_ARRIVE_M
	var where := "on_floor %s, region %s %s, pos %s (local %s), %.2f m from the arrival %s (dy %.2f), kill_y %.1f" % [s.get("on_floor"),
		region.get("kind"), region.get("id"), _v(pos), _v(s.get("local", Vector3.ZERO)), err, _v(arr), pos.y - arr.y, def.kill_y]
	var grounded := bool(s.get("on_floor", false)) and not bool(s.get("climbing", false)) and String(region.get("kind", "")) == "map" \
		and String(region.get("id", "")) == to and pos.y > def.kill_y + KILL_Y_MARGIN_M
	var at_arrival := err <= tol and absf(pos.y - arr.y) < 1.5
	if edge:
		# A walked trail never places the player: the hard check is standing on the map's floor inside its region; the
		# portal's arrival point (where a press-Up arrival would land) only has to be reachable from the gate (WARN).
		d.check("leg %d: grounded on %s's floor, inside its region, after the gate" % [i, to], grounded, where)
		d.soft_check("leg %d: the arrival point of %s is reachable from the trail's gate" % [i, to], at_arrival, where)
	else:
		d.check("leg %d: grounded in %s on the door's arrival point" % [i, to], grounded and at_arrival, where)


## The World Review numbers of a map, at its first arrival (the walker stands on the arrival point).
func _first_arrival(map_id: String, src: PortalDef) -> void:
	await d.wait(0.6)  # the camera settles on the new bounds
	var w := d.world()
	var def := w.defs.get_def(map_id)
	var p := d.player()
	var rig: Node = d.ctx().camera
	var cam: Camera3D = rig.get("camera") as Camera3D if rig != null else null
	var area := _area(def.footprint)
	var ext := _extent(def.footprint)
	var live := 0
	var ms := d.monsters()
	if ms != null:
		live = (ms.call("live_monsters") as Array).size()
	var portals: Array = []
	for q: PortalDef in def.canonical_portals():
		var pos := q.anchor_ground
		var in_view := cam != null and cam.is_position_in_frustum(pos + Vector3.UP * 1.5)
		portals.append({"id": q.portal_id, "to": q.destination_map_id, "type": q.portal_type, "visual": q.visual,
			"hidden": q.hidden, "link": q.link_id, "dist_m": snappedf(_flat(pos - p.global_position), 0.1),
			"dy_m": snappedf(pos.y - p.global_position.y, 0.1), "in_view": in_view})
	var r := {"name": _name(map_id), "kind": def.kind, "area_m2": snappedf(area, 1.0), "extent_m": [snappedf(ext.x, 0.1), snappedf(ext.y, 0.1)],
		"spawn_slots": def.monster_spawn_definitions.size(), "spawn_areas": def.spawn_areas.size(), "live_monsters": live,
		"npcs": def.npc_definitions.size(), "canonical_mobs": int(d.db().map(map_id).get("total_mob_count", 0)),
		"monsters_per_100m2": snappedf(100.0 * live / maxf(area, 1.0), 0.01), "portals": portals,
		"arrived_by": src.key() if src != null else "new game",
		"ortho_size": snappedf(float(rig.get("ortho_size")), 0.1) if rig != null else 0.0}
	review[map_id] = r
	var pl := PackedStringArray()
	for q: Dictionary in portals:
		pl.append("%s->%s %s%s %.0f m (dy %.1f)%s" % [q["id"], q["to"], q["type"], " hidden" if bool(q["hidden"]) else "",
			float(q["dist_m"]), float(q["dy_m"]), " IN VIEW" if bool(q["in_view"]) else " off-screen"])
	d.note("MAP %s %s (%s): footprint %.0f m2 (%.0f x %.0f m), spawn slots %d, live monsters %d (%.2f / 100 m2), NPCs %d, view ortho %.1f; portals from the arrival: %s" % [
		map_id, r["name"], r["kind"], area, ext.x, ext.y, r["spawn_slots"], live, r["monsters_per_100m2"], r["npcs"],
		r["ortho_size"], "; ".join(pl)])


## The planner a player's choice of way matches best: the exported routes (ladders, ropes, the Iteration One
## walkways) unless the grid planner finds a path on the real collision at least 15% shorter (a player walks the
## direct way). PLAYA_PLANNER=auto keeps the harness default (routes first). Returns {planner, routes_m, grid_m}.
func _choose_planner(target: Vector3) -> Dictionary:
	var out := {"planner": "auto", "routes_m": -1.0, "grid_m": -1.0}
	if OS.get_environment("PLAYA_PLANNER") == "auto":
		return out
	var r: Dictionary = d.walker.plan(target, "routes")
	var g: Dictionary = d.walker.plan(target, "grid")
	var rl := _length(r["path"]) if String(r["how"]) == "routes" else -1.0
	var gl := _length(g["path"]) if String(g["how"]) == "grid" else -1.0
	out["routes_m"] = snappedf(rl, 0.1)
	out["grid_m"] = snappedf(gl, 0.1)
	if gl > 0.0 and (rl < 0.0 or gl < rl * 0.85):
		out["planner"] = "grid"
	return out


static func _length(path: PackedVector3Array) -> float:
	var s := 0.0
	for k in range(1, path.size()):
		s += path[k].distance_to(path[k - 1])
	return s


## Notes what collision a straight walk from `a` to `b` meets (rays at knee and chest height) and whether the body
## fits standing at `b` (a diagnostic for a stalled walk; changes nothing).
func _probe_between(a: Vector3, b: Vector3, label: String) -> void:
	var w := d.world()
	var space := w.ground_query.space
	var parts := PackedStringArray()
	parts.append("standable at the target %s: %s" % [_v(b), str(d.walker.standable(b))])
	for h: float in [0.3, 0.6, 1.0]:
		var q := PhysicsRayQueryParameters3D.create(a + Vector3.UP * h, b + Vector3.UP * h, 0xFFFFFFFF, [d.player().get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			parts.append("ray at %.1f m: clear" % h)
		else:
			var col: Object = hit.get("collider")
			var nm: String = str((col as Node).get_path()) if col is Node else str(col)
			parts.append("ray at %.1f m hits %s at %s (normal %s, layer %d)" % [h, nm, _v(hit["position"]), _v(hit["normal"]),
				(col as CollisionObject3D).collision_layer if col is CollisionObject3D else -1])
	d.note("%s: from %s: %s" % [label, _v(a), "; ".join(parts)])


func _recover_from_death(from: String, i: int) -> void:
	await d.wait(2.0)
	var c: Dictionary = await d.click("OK")
	if not bool(c.get("ok", false)):
		await d.tap_key(KEY_ENTER)
	await d.wait_idle(20.0)
	d.note("leg %d: died, respawned in %s; warping back to %s (setup) to retry the leg" % [i, d.current_map(), from])
	await d.console("warp " + from)
	await d.wait_idle(5.0)


func _summarise(full: bool) -> void:
	# Every canonical portal of the 25 maps (MeowDB), by "map.portal".
	var want := PackedStringArray()
	var all_maps := PackedStringArray()
	for f in DirAccess.get_files_at("res://data/canonical/maps"):
		if f.ends_with(".json"):
			all_maps.append(f.get_basename())
	all_maps.sort()
	for m in all_maps:
		for q: Variant in d.db().map(m).get("portals", []):
			want.append("%s.%s" % [m, String((q as Dictionary).get("name", ""))])
	var missing := PackedStringArray()
	for k in want:
		if not used_portals.has(k):
			missing.append(k)
	var not_visited := PackedStringArray()
	for m in all_maps:
		if not visited.has(m):
			not_visited.append(m)
	if full:
		d.check("all %d maps visited on foot" % all_maps.size(), not_visited.is_empty(), "not visited: %s" % ", ".join(not_visited))
		d.check("every canonical portal used (%d of %d)" % [want.size() - missing.size(), want.size()], missing.is_empty(),
			"unused: %s" % ", ".join(missing))
		d.check("the tour ends in Southperry (000000060)", d.current_map() == "000000060", d.current_map())
	var tj := 0.0
	var tc := 0.0
	var walk_s := 0.0
	var door_s := 0.0
	for l: Dictionary in legs_out:
		if String(l["tag"]) == "journey":
			tj += float(l["total_s"])
		else:
			tc += float(l["total_s"])
		if String(l["how"]) == "walk":
			walk_s += float(l["total_s"])
		else:
			door_s += float(l["total_s"])
	d.note("TOTAL legs %d: journey %.1f s, check legs %.1f s; walked legs %.1f s, door legs %.1f s; hits %d, damage %d, deaths %d" % [
		legs_out.size(), tj, tc, walk_s, door_s, hits["n"], hits["dmg"], hits["deaths"]])
	d.carry["legs"] = legs_out
	d.carry["review"] = review
	d.carry["used_portals"] = used_portals.keys()


# ----------------------------------------------------------------------------------------------------------------
# Signals and helpers
# ----------------------------------------------------------------------------------------------------------------

func _on_damaged(amount: int, _src: String) -> void:
	hits["n"] = int(hits["n"]) + 1
	hits["dmg"] = int(hits["dmg"]) + amount


func _on_died(_map_id: String) -> void:
	hits["deaths"] = int(hits["deaths"]) + 1


func _on_map_entered(map_id: String, _prev: String) -> void:
	_capture_banner.call_deferred(map_id)


func _capture_banner(map_id: String) -> void:
	var hud := d.hud()
	var b: Variant = hud.get("banner") if hud != null else null
	if not (b is Control):
		banner_at_entry[map_id] = {"text": "", "visible": false, "why": "no banner"}
		return
	var bc := b as Control
	var st := String((bc.get("street_label") as Label).text)
	var nm := String((bc.get("name_label") as Label).text)
	banner_at_entry[map_id] = {"text": "%s / %s" % [st, nm], "visible": bc.visible}


func _sample_trail_line() -> void:
	var hud := d.hud()
	var b: Variant = hud.get("banner") if hud != null else null
	if b is Control and bool((b as Control).call("is_trail_showing")):
		var t := String(((b as Control).get("trail_label") as Label).text)
		if not trail_seen.has("text"):
			trail_seen["text"] = t
			trail_seen["at_map"] = d.current_map()


func _name(map_id: String) -> String:
	return String(d.db().map(map_id).get("name", map_id))


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


static func _v(v: Variant) -> String:
	if v is Vector3:
		var u := v as Vector3
		return "(%.1f, %.1f, %.1f)" % [u.x, u.y, u.z]
	return str(v)


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for k in poly.size():
		var p := poly[k]
		var q := poly[(k + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


static func _extent(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var lo := poly[0]
	var hi := poly[0]
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return hi - lo
