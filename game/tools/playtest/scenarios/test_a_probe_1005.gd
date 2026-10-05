extends PlaytestScenario
## test_a_probe_1005 (play-A): a focused probe behind two test_a findings in 000001005 (Hunting Ground Middle of the
## Forest I). (1) out00's arrival point: test_a_traversal could not walk from the trail's gate to it (a wall of the
## door mound stands between). Here the 000001000 <-> 000001005 link is switched to warp (console, setup: the
## force_link_mode fallback) and Up is pressed at 000001000.in04, so the game places the player on that arrival; then
## the player walks to three far points of the map. (2) The JumpTower ladder: test_a_routes saw a walk to the
## JumpTower route's start (up the ladder beside out00) leave the map. Here the player walks to the ladder's foot in
## edge mode (the configured game) and holds Up, as a player climbing it would.

const FIELD := "000001000"
const FOREST := "000001005"


func description() -> String:
	return "probe: 000001005 out00's arrival (warp fallback) and the JumpTower ladder beside out00"


func max_seconds() -> float:
	return 600.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Prober", "female")
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	if OS.get_environment("PLAYA_GOD") == "1":
		await d.console("god on")
	var defs := d.world().defs
	var src := TraversalTour.portal_between(defs, FIELD, FOREST)
	var out00 := TraversalTour.portal_between(defs, FOREST, FIELD)
	d.note("link %s; %s anchor %s, arrival %s; %s anchor %s, arrival %s, trigger %s" % [src.link_id, src.key(), src.anchor_ground,
		src.spawn_transform.origin, out00.key(), out00.anchor_ground, out00.spawn_transform.origin, out00.trigger_size])

	# (2) The ladder beside out00, in the configured (edge) game.
	await d.console("warp " + FOREST)
	var jt := d.route_points(FOREST, "JumpTower")
	d.note("JumpTower route: %d points, first %s, second %s" % [jt.size(), jt[0], jt[1] if jt.size() > 1 else Vector3.ZERO])
	var climbs: Array = d.player().climbables
	var near := PackedStringArray()
	for c: Variant in climbs:
		var cd: Dictionary = {}
		if c is Dictionary:
			cd = c
		elif c is Object and (c as Object).has_method("to_dict"):
			cd = (c as Object).call("to_dict")
		near.append(str(cd).left(200) if not cd.is_empty() else str(c).left(200))
	d.note("climbables (%d): %s" % [climbs.size(), " || ".join(near.slice(0, 40))])
	var foot: Dictionary = await d.walk_to(jt[0], {"within_m": 0.4})
	var s := d.state()
	var w := d.world()
	var under := w.portal_under_player()
	d.note("at the JumpTower start: %s, map %s, inside portal trigger: %s (prompt %s)" % [str(s.get("position")), d.current_map(),
		under.def.key() if under != null else "none", str(under.shows_prompt()) if under != null else "-"])
	await d.screenshot("jumptower_foot")
	var before := d.current_map()
	await d.press(&"portal_enter", 1.5)
	await d.wait_idle(10.0)
	var after := d.state()
	d.soft_check("holding Up at the JumpTower ladder beside %s climbs instead of using the portal" % out00.key(),
		d.current_map() == before, "map %s -> %s, last transition %s, position %s" % [before, d.current_map(),
		str(after.get("last_transition", {})), str(after.get("position"))])
	await d.screenshot("after_up_at_ladder")

	# (1) out00's arrival, reached the way the warp fallback places a player.
	if d.current_map() != FIELD:
		await d.console("warp %s %s" % [FIELD, "in04"])
	var lm := await d.console("linkmode warp %s" % src.link_id)
	var e: Dictionary = await d.enter_portal(src.portal_id)
	d.check("Up at %s in warp mode enters %s" % [src.key(), FOREST], bool(e["ok"]), str(e))
	await d.screenshot("warp_arrival_out00")
	var here := d.player().global_position
	d.note("placed at %s (the arrival %s): on_floor %s, region %s" % [here, out00.spawn_transform.origin, str(d.state().get("on_floor")),
		str(d.state().get("region"))])
	for target: String in ["route:Floor", "route:SummitStair:end", "spawn:0"]:
		var r: Dictionary = await d.walk_to(target, {"max_s": 60.0})
		d.soft_check("from out00's arrival the player walks to %s" % target, bool(r["ok"]), "%s via %s; %s" % [r.get("result", ""),
			r.get("how", ""), "; ".join(r.get("issues", PackedStringArray()))])
		if bool(r["ok"]):
			break
		await d.console("warp %s %s" % [FOREST, "out00"])
	await d.console("linkmode edge %s" % src.link_id)
	d.check("probe finished", true, lm)
