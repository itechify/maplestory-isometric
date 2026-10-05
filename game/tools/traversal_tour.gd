class_name TraversalTour
extends RefCounted
## L3: the Test A tour (MAP_ARCHITECTURE.md section 4.13), one continuous bot session from a new game at 000000001
## player_spawns[0], on a TraversalWalker:
##
##   1 -> 10 -> 20 -> 21 -> 20 -> 30 -> 40 -> 41 -> 42 -> 50 -> 60 -> 61 -> 60 -> 50 -> 1000
##     -> (1001, 1002, 1003, 1004, 1005, 1006: each out and back)
##     -> 1010 -> 1011 -> 1010 -> 1013 -> 1010 -> 1012 -> 1014 -> 1012 -> 1010 -> 1020 -> 1021 -> 1020
##
## Each leg walks inside the current map to the portal toward the next map (TraversalNav over the map's routes),
## then:
##   edge mode  a trail link is walked along its trail and committed at the far gate; a door is pressed (doors are
##              always warps);
##   warp mode  every link is pressed (PortalGraph.set_link_mode("all", "warp"): the force_link_mode fallback, plugs
##              closed, trails scenery).
## A leg asserts the exact map_left -> map_entered -> portal_used sequence and its via (gate / press_up / door). The
## tour passes with every leg ok and zero fall recoveries, stalls and region invariant violations. It is never served
## from a cache. Result: {"mode", "ok", "legs": [leg], "time_s", "distance_m", "recoveries", "stalls", "violations",
## "teleports", "maps_visited"}; leg = {"from", "to", "portal", "link", "how", "ok", "time_s", "distance_m", "issues"}.

const ROUTE: Array[String] = ["000000001", "000000010", "000000020", "000000021", "000000020", "000000030",
	"000000040", "000000041", "000000042", "000000050", "000000060", "000000061", "000000060", "000000050", "000001000",
	"000001001", "000001000", "000001002", "000001000", "000001003", "000001000", "000001004", "000001000", "000001005",
	"000001000", "000001006", "000001000", "000001010", "000001011", "000001010", "000001013", "000001010", "000001012",
	"000001014", "000001012", "000001010", "000001020", "000001021", "000001020"]


## Runs the tour in `mode` ("edge" or "warp"). Await it. `from_leg` / `to_leg` run a segment (leg indices into the
## route's steps; the segment starts with a debug warp to its first map's arrival of the previous leg's portal).
static func run(w: TraversalWalker, mode: String, from_leg: int = 0, to_leg: int = -1) -> Dictionary:
	var d := w.defs()
	var out := {"mode": mode, "ok": false, "legs": [], "time_s": 0.0, "distance_m": 0.0, "recoveries": 0, "stalls": 0,
		"violations": 0, "teleports": 0, "maps_visited": PackedStringArray()}
	# Edge mode is the configured game (portal_adaptations.json: trails walk, doors and overridden links warp); warp
	# mode is the force_link_mode fallback.
	d.apply_configured_link_modes()
	if mode != "edge":
		d.graph.set_link_mode("all", PortalDef.LINK_WARP)
	var last := ROUTE.size() - 2 if to_leg < 0 else mini(to_leg, ROUTE.size() - 2)
	var started := false
	if from_leg == 0:
		started = await w.new_game()
	else:
		var prev := portal_between(d, ROUTE[from_leg - 1], ROUTE[from_leg])
		started = prev != null and await w.warp(ROUTE[from_leg], d.arrival_for(prev).portal_id if d.arrival_for(prev).is_portal() else "")
	if not started or String(w.session.get("current_map")) != ROUTE[from_leg]:
		(out.legs as Array).append({"from": "", "to": ROUTE[from_leg], "ok": false, "issues": PackedStringArray(["cannot start at %s" % ROUTE[from_leg]])})
		return out
	var rec0 := w.world.fall_recovery.recoveries
	var vio0 := w.world.region_monitor.violations
	var navs := {}
	var all_ok := true
	var visited := PackedStringArray([ROUTE[from_leg]])
	for i in range(from_leg, last + 1):
		var leg: Dictionary = await _leg(w, ROUTE[i], ROUTE[i + 1], mode, navs)
		(out.legs as Array).append(leg)
		out["time_s"] = float(out.time_s) + float(leg.time_s)
		out["distance_m"] = float(out.distance_m) + float(leg.distance_m)
		out["stalls"] = int(out.stalls) + int(leg.get("stalls", 0))
		out["teleports"] = int(out.teleports) + int(leg.get("teleports", 0))
		print("TRAVERSAL TOUR %s %s>%s %s %s %.1fs %.1fm%s" % [mode, ROUTE[i], ROUTE[i + 1], String(leg.how), "ok" if bool(leg.ok) else "FAIL",
			float(leg.time_s), float(leg.distance_m), "" if bool(leg.ok) else " (" + "; ".join(leg.issues) + ")"])
		if not bool(leg.ok):
			all_ok = false
		if String(w.session.get("current_map")) != ROUTE[i + 1]:
			break  # lost: the rest of the tour cannot follow
		if not (ROUTE[i + 1] in visited):
			visited.append(ROUTE[i + 1])
	out["recoveries"] = w.world.fall_recovery.recoveries - rec0
	out["violations"] = w.world.region_monitor.violations - vio0
	visited.sort()
	out["maps_visited"] = visited
	out["time_s"] = snappedf(float(out.time_s), 0.01)
	out["distance_m"] = snappedf(float(out.distance_m), 0.1)
	out["ok"] = all_ok and (out.legs as Array).size() == last - from_leg + 1 and int(out.recoveries) == 0 \
		and int(out.stalls) == 0 and int(out.violations) == 0 and int(out.teleports) == 0
	d.apply_configured_link_modes()
	return out


## The canonical portal of `from_map` leading to `to_map` (null when none).
static func portal_between(d: MapDefinitions, from_map: String, to_map: String) -> PortalDef:
	for p in d.get_def(from_map).canonical_portals():
		if p.destination_map_id == to_map:
			return p
	return null


static func _leg(w: TraversalWalker, from_map: String, to_map: String, mode: String, navs: Dictionary) -> Dictionary:
	var d := w.defs()
	var src := portal_between(d, from_map, to_map)
	var leg := {"from": from_map, "to": to_map, "portal": src.key() if src != null else "", "link": src.link_id if src != null else "",
		"how": "", "ok": false, "time_s": 0.0, "distance_m": 0.0, "issues": PackedStringArray(), "stalls": 0, "teleports": 0}
	var issues: PackedStringArray = leg.issues
	if src == null:
		issues.append("no portal %s -> %s" % [from_map, to_map])
		return leg
	if String(w.session.get("current_map")) != from_map:
		issues.append("not in %s (in %s)" % [from_map, String(w.session.get("current_map"))])
		return leg
	var walk_trail := mode == "edge" and d.graph.is_edge(src.link_id)
	leg["how"] = "walk" if walk_trail else ("door" if src.portal_type == PortalDef.TYPE_DOOR else "press_up")
	# 1. Inside the map, to the portal.
	if not navs.has(from_map):
		navs[from_map] = TraversalNav.build(d.get_def(from_map))
	var nav: TraversalNav = navs[from_map]
	var here := w.player.global_position
	var path := nav.path(here, src.anchor_ground)
	if path.is_empty():
		issues.append("no route in %s from %s to %s" % [from_map, here, src.key()])
		path = PackedVector3Array([here, src.anchor_ground])
	w.events.clear()
	var inner: Dictionary = await w.walk(path, "%s to %s" % [from_map, src.key()])
	leg["time_s"] = float(inner.time_s)
	leg["distance_m"] = float(inner.distance_m)
	if not bool(inner.ok):
		issues.append("in-map leg: " + "; ".join(inner.issues))
		if String(inner.result) != "DONE":
			leg["stalls"] = 1
	if not w.events.is_empty():
		issues.append("map changed during the in-map leg: %s" % str(w.events))
		return leg
	if String(inner.result) != "DONE" and w.player.global_position.distance_to(src.anchor_ground) > 2.5:
		# The in-map route failed short of the portal: teleport next to it so the tour can go on (counted).
		w.world.place_player(src.spawn_transform)
		await w.frames(5)
		leg["teleports"] = 1
		issues.append("teleported to %s's arrival after the in-map leg failed" % src.key())
	# 2. Through the link.
	w.events.clear()
	var expect: Array[String] = ["left:" + from_map, "entered:%s<%s" % [to_map, from_map], "portal:%s.%s>%s" % [from_map, src.portal_id, to_map]]
	if walk_trail:
		var t := d.trail(src.link_id)
		var dst := d.graph.portals.get(t.portal_key_of(to_map), null) as PortalDef
		var tp := PackedVector3Array([w.player.global_position, src.anchor_ground])
		tp.append_array(t.centreline_from(from_map))
		if dst != null:
			tp.append(dst.anchor_ground)
		var r: Dictionary = await w.walk(tp, "trail %s -> %s" % [src.key(), to_map])
		leg["time_s"] = float(leg.time_s) + float(r.time_s)
		leg["distance_m"] = float(leg.distance_m) + float(r.distance_m)
		if not bool(r.ok):
			issues.append("trail: " + "; ".join(r.issues))
			if String(r.result) != "DONE":
				leg["stalls"] = int(leg.stalls) + 1
		var rec: TransitionRecord = w.session.get("last_transition")
		if rec == null or rec.via != "gate" or rec.from_map != from_map:
			issues.append("not committed by the gate (via %s)" % (rec.via if rec != null else "-"))
	else:
		var p: Dictionary = await w.press_up(src)
		leg["time_s"] = float(leg.time_s) + float(p.time_s)
		if not bool(p.ok):
			issues.append_array(p.issues)
		var arrival: Transform3D = d.arrival_transform(d.arrival_for(src)).xform
		if w.player.global_position.distance_to(arrival.origin) > 0.1:
			issues.append("arrived %.3f m from the arrival" % w.player.global_position.distance_to(arrival.origin))
	if w.events != expect:
		issues.append("events %s, expected %s" % [str(w.events), str(expect)])
	if String(w.session.get("current_map")) != to_map:
		issues.append("ended in %s, expected %s" % [String(w.session.get("current_map")), to_map])
	leg["time_s"] = snappedf(float(leg.time_s), 0.01)
	leg["distance_m"] = snappedf(float(leg.distance_m), 0.1)
	leg["ok"] = issues.is_empty()
	return leg
