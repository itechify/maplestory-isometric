extends PlaytestScenario
## ui_minimap: the minimap and the persistent map name in the real game (brief Phases 11 and 12), on all 25 maps.
## New game through the screens -> on the start map: the minimap is installed and unfolded, its title is the
## canonical street and name, the player's arrow is on the picture; M (real key) folds it to the title strip and back;
## F3 (the debug overlay) adds the canonical map id and takes it away; M does nothing while Heena's conversation is
## open -> the player placed mid-trail: the arrow carries "-> <destination>" -> every one of the 25 maps (console warp,
## setup only): title, portal markers (exactly the visible canonical portals: no arrival gate, no hidden portal), NPC
## dots (exactly the canonical NPCs), shop badges on the doors to Pan, Sid and Lucy, the collision ground drawn, the
## picture on screen with its ground meshes, every exit named on the picture (maps with up to five exits), the arrow
## on the picture after arrival, and the NPC name tags' shop / transport icons; a screenshot per map (windowed)
## -> Phase 12 feedback through real kills in 000000040 to level 2: the flourish, the level, AP and SP lines, hits,
## pickup lines. Ends with no engine error raised from the minimap's scripts.

const START_MAP := "000000001"
const HEENA := "1"
## Snail Hunting Ground I: the first hunting map (Phase 12 feedback through real kills).
const HUNT_MAP := "000000040"
## Maps with at most this many visible portals name every exit on the picture (all but 000001000's eight).
const ALL_NAMED_MAX := 5


func description() -> String:
	return "the minimap on all 25 maps: title, M, debug id, portals, NPCs, shop badges, player arrow, trail tag, name tags"


func max_seconds() -> float:
	return 900.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Minimap", "female", "541", {})
	if not d.check("new game through the title and creation screens", bool(ng["ok"]), str(ng)):
		return
	var mm := d.system("Minimap") as MisoMinimap
	if not d.check("the shell installs the minimap", mm != null, d.main.game_session.installer.summary()):
		return
	await d.frames(10)
	var s := mm.snapshot()
	d.check("the minimap is shown on a new game", bool(s["expanded"]) and mm.visible and mm.view.is_visible_in_tree(), str(s))
	d.check("it shows the start map %s" % START_MAP, s["map_id"] == START_MAP, str(s["map_id"]))
	d.check("its title is the canonical street and name", s["title"] == _title(d, START_MAP), str(s["title"]))
	d.check("the player's arrow is on the picture", bool(s["player_in_view"]), str(mm.view.player_marker()))
	await d.screenshot("minimap_start")

	# M through the real key: the map folds to the title strip (the map name stays) and comes back.
	await d.tap("toggle_minimap")
	await d.frames(2)
	s = mm.snapshot()
	d.check("M folds the map away", not bool(s["expanded"]) and not mm.view.is_visible_in_tree(), str(s["expanded"]))
	d.check("the map name stays on screen while folded", mm.name_label.is_visible_in_tree()
		and mm.name_label.text == String(d.db().map(START_MAP)["name"]), mm.name_label.text)
	await d.screenshot("minimap_folded")
	await d.tap("toggle_minimap")
	await d.frames(2)
	d.check("M brings it back", bool(mm.snapshot()["expanded"]) and mm.view.is_visible_in_tree())

	# Debug mode (F3): the canonical map id joins the title, and leaves with the overlay.
	await d.tap("debug_overlay")
	await d.frames(2)
	s = mm.snapshot()
	d.check("the debug overlay adds the canonical map id", bool(s["debug_id"]) and String(s["title"]).ends_with("[%s]" % START_MAP),
		str(s["title"]))
	await d.screenshot("minimap_debug_id")
	await d.tap("debug_overlay")
	await d.frames(2)
	d.check("and it goes with the overlay", not bool(mm.snapshot()["debug_id"]), str(mm.snapshot()["title"]))

	# Under a modal (Heena's conversation) M does nothing.
	var talk: Dictionary = await d.talk_to(HEENA)
	if d.soft_check("Heena's conversation opens", bool(talk.get("open", false)), str(talk.get("why", ""))):
		await d.tap("toggle_minimap")
		await d.frames(2)
		d.check("M is quiet while the conversation is open", bool(mm.snapshot()["expanded"]))
		d.check("Esc ends the conversation", await d.close_dialogue())

	await _trail(d, mm)

	# Every map: the console warps (setup); the minimap must follow on its own.
	var shops := PackedStringArray()
	var transports := PackedStringArray()
	for id in d.world().defs.ids():
		await d.console("warp %s" % id)
		await d.frames(8)
		s = mm.snapshot()
		var want := _visible_portals(d, id)
		var npcs := _canonical_npcs(d, id)
		var got_npcs: PackedStringArray = s["npcs"]
		got_npcs.sort()
		d.check("%s: the minimap follows the warp" % id, s["map_id"] == id and d.current_map() == id, "%s / %s" % [s["map_id"], d.current_map()])
		d.check("%s: title %s" % [id, _title(d, id)], s["title"] == _title(d, id), str(s["title"]))
		d.check("%s: the collision ground is drawn" % id, s["ground_source"] == MinimapModel.SOURCE_COLLISION and int(s["ground"]) > 0,
			"%s, %d triangles" % [s["ground_source"], int(s["ground"])])
		var screen := Rect2(Vector2.ZERO, mm.get_viewport_rect().size)
		d.check("%s: the picture is on screen with its ground meshes" % id, mm.view.is_visible_in_tree()
			and int(s["meshes"]) > 0 and mm.view.size.x > 0.0 and mm.view.size.y > 0.0 and screen.encloses(mm.get_global_rect()),
			"visible %s, %d meshes, picture %s, minimap %s on %s" % [mm.view.is_visible_in_tree(), int(s["meshes"]),
			mm.view.size, mm.get_global_rect(), screen])
		if want.size() <= ALL_NAMED_MAX:
			var named: PackedStringArray = (s["labels"] as PackedStringArray).duplicate()
			named.sort()
			var sorted_want := want.duplicate()
			sorted_want.sort()
			d.check("%s: every exit is named on the picture" % id, named == sorted_want, "%s of %s" % [named, sorted_want])
		d.check("%s: portal markers = the visible canonical portals %s" % [id, want], s["portals"] == want, str(s["portals"]))
		d.check("%s: NPC dots = the canonical NPCs %s" % [id, npcs], got_npcs == npcs, str(got_npcs))
		d.check("%s: the player's arrow is on the picture" % id, bool(s["player_in_view"]), str(mm.view.player_marker()))
		for door: String in s["shop_doors"]:
			shops.append("%s.%s" % [id, door])
		for nid: String in s["roles"]:
			var tag := _tag(d, nid)
			d.check("%s: NPC %s's name tag carries the %s icon" % [id, nid, s["roles"][nid]],
				tag != null and tag.role == s["roles"][nid] and tag.role_icon.visible, str(tag.role if tag != null else "no tag"))
			if s["roles"][nid] == MapIcons.ROLE_TRANSPORT:
				transports.append(nid)
		d.note("%s: %d triangles, labels %s of %s, markers %s" % [id, int(s["ground"]), s["labels"], s["portals"], s["markers"]])
		await d.screenshot("minimap_%s" % id)
	shops.sort()
	d.check("shop badges on exactly the doors to the three shops", shops == _shop_doors(d), "%s / %s" % [shops, _shop_doors(d)])
	d.check("the Transport NPC's tag carries the boat", not transports.is_empty(), str(transports))
	await _feedback(d)
	var errs: Array = []
	for e: Dictionary in d.report.engine_errors:
		if String(e.get("message", "")).contains("minimap") or String(e.get("message", "")).contains("map_icons"):
			errs.append(e)
	d.check("no engine error from the minimap's scripts", errs.is_empty(), str(errs))


## Phase 12 feedback through real play in Snail Hunting Ground I: fight Snails until level 2, then the HUD log has the
## level line, the AP line and the SP line, the flourish played; the hits showed damage numbers; picked-up drops and
## mesos are announced with the HUD's own lines.
func _feedback(d: PlaytestDriver) -> void:
	await d.console("warp %s" % HUNT_MAP)
	var hud := d.hud() as MisoHud
	var hits: Array = [0]
	var flourish: Array = [false]
	var on_hit := func(_m: String, _dmg: int, _crit: bool) -> void: hits[0] += 1
	var on_level := func(_lv: int) -> void: flourish[0] = hud.flourish.is_playing()
	d.events().connect("monster_hit", on_hit)
	d.events().connect("leveled_up", on_level, CONNECT_DEFERRED)
	var start := hud.log_panel.history.size()
	var f: Dictionary = await d.fight_until(func() -> bool: return d.character().level >= 2, 400.0)
	d.events().disconnect("monster_hit", on_hit)
	d.events().disconnect("leveled_up", on_level)
	if not d.check("level 2 by killing in %s" % HUNT_MAP, d.character().level >= 2, "%d kills, level %d" % [int(f["kills"]), d.character().level]):
		return
	var c := d.character()
	var lines := hud.log_panel.texts().slice(start)
	d.check("level-up: the flourish played", flourish[0] and hud.flourish.sub.text == "Level %d" % c.level, hud.flourish.sub.text)
	d.check("level-up: the log congratulates", lines.has("Congratulations! You have reached level %d." % c.level), str(lines))
	var ap_line := "You have %d AP to distribute (press %s)." % [c.ap, MisoUiEnv.key_label("toggle_stats")]
	d.check("level-up: the AP line", c.ap > 0 and lines.has(ap_line), "%s in %s" % [ap_line, lines])
	var sp_line := "You have %d SP to distribute (press %s)." % [c.sp, MisoUiEnv.key_label("toggle_skills")]
	d.check("level-up: the SP line", c.sp > 0 and lines.has(sp_line), "%s in %s" % [sp_line, lines])
	d.check("hits were announced (monster_hit: damage numbers)", int(hits[0]) > 0, "%d hits" % int(hits[0]))
	var before := hud.log_panel.history.size()
	var p: Dictionary = await d.pickup_all_nearby(10.0, 60.0)
	var picked_lines := hud.log_panel.texts().slice(before)
	var gains := Array(picked_lines).filter(func(t: String) -> bool: return t.begins_with("You have gained"))
	if d.soft_check("something dropped nearby to pick up", int(p["picked"]) > 0, str(p["picked"])):
		d.check("every pickup is announced in the HUD log", gains.size() >= int(p["picked"]),
			"%d picked, lines %s" % [int(p["picked"]), picked_lines])
	await d.screenshot("feedback_level_2")


## The player placed in the middle of a walkable trail of the current map (an API placement, as ui_game_check does):
## RegionMonitor reports it, and the minimap's arrow is tagged with the destination's canonical name.
func _trail(d: PlaytestDriver, mm: MisoMinimap) -> void:
	var here := d.current_map()
	var trail: TrailDef = null
	for t: TrailDef in d.world().defs.trails_of(here):
		if t.has_geometry() and not t.hidden and t.centre.size() >= 3 and d.world().defs.graph.is_edge(t.link_id):
			trail = t
			break
	if not d.check("%s has a walkable trail" % here, trail != null):
		return
	var home := d.player().global_transform
	d.note("api: the player is placed mid-trail on %s (no walk needed to test the tag)" % trail.link_id)
	d.world().place_player(Transform3D(Basis(), trail.centre[trail.centre.size() / 2] + Vector3(0, 0.3, 0)))
	var dest := trail.other_map(here)
	var tagged := await d.wait_until(func() -> bool: return mm.snapshot()["trail_tag"] == String(d.db().map(dest)["name"]), 3.0)
	d.check("on the trail: the arrow is tagged \"-> %s\"" % String(d.db().map(dest)["name"]), tagged, str(mm.snapshot()["trail_tag"]))
	await d.frames(4)
	await d.screenshot("minimap_trail")
	d.world().place_player(home)
	var cleared := await d.wait_until(func() -> bool: return mm.snapshot()["trail_tag"] == "", 3.0)
	d.check("back on the map: no tag", cleared, str(mm.snapshot()["trail_tag"]))


func _title(d: PlaytestDriver, id: String) -> String:
	var rec := d.db().map(id)
	return "%s%s%s" % [String(rec["street_name"]), MisoMinimap.TITLE_SEPARATOR, String(rec["name"])]


func _visible_portals(d: PlaytestDriver, id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for p: Dictionary in d.db().map(id).get("portals", []):
		if int(p.get("type", 0)) == 2:
			out.append(String(p["name"]))
	return out


func _canonical_npcs(d: PlaytestDriver, id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for n: Dictionary in d.db().map(id).get("npcs", []):
		out.append(str(n["id"]))
	out.sort()
	return out


## "<map>.<portal>" of every visible portal whose destination hosts a shopkeeper (canonical records).
func _shop_doors(d: PlaytestDriver) -> PackedStringArray:
	var out := PackedStringArray()
	for id in d.world().defs.ids():
		for p: Dictionary in d.db().map(id).get("portals", []):
			if int(p.get("type", 0)) == 2 and not MinimapModel.shopkeepers_on(d.db(), String(p["to_map_id"])).is_empty():
				out.append("%s.%s" % [id, String(p["name"])])
	out.sort()
	return out


func _tag(d: PlaytestDriver, npc_id: String) -> NpcNameTag:
	var n: Node = d.world().npc_nodes.get(npc_id, null)
	var p := n.get_node_or_null(NpcPresenter.NODE_NAME) as NpcPresenter if n != null else null
	return p.tag if p != null and is_instance_valid(p.tag) else null
