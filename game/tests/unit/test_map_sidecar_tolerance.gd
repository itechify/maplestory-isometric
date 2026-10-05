extends TestCase
## The runtime tolerates both shapes of the Blender sidecar (docs/runtime/blender_export.md): the Phase 1 export
## (portals with one-way arrival markers, player_start only, derived spawn_areas, NPCs matched by name) and the
## current one (arrival_points, authored player_spawns, spawn_regions, meowdb_npc_id), plus unknown added fields and
## missing NPC markers (Todd, Sam, Mai: MAP_ARCHITECTURE section 3.3), which get a logged fallback placement.
## Built from the real export, then edited in memory. Needs INCLUDE_WORLD=1; prints SKIP without it.

const MISSING := {"000000030": "Todd", "000000040": "Sam", "000000050": "Mai"}


func sidecars(test_name: String) -> WorldSidecars:
	if not WorldSidecars.exists():
		print("SKIP %s: game/assets/world not present (run with INCLUDE_WORLD=1)" % test_name)
		return null
	var s := WorldSidecars.load_dir()
	s.chunks = s.chunks.duplicate(true)
	return s


func slug(map_id: String) -> String:
	for row in db().miso_table("map_id_crosswalk"):
		if String(row.meowdb_id) == map_id:
			return String(row.iteration_one_slug)
	return ""


func test_missing_npc_markers_get_a_logged_fallback() -> void:
	var s := sidecars("test_missing_npc_markers_get_a_logged_fallback")
	if s == null:
		return
	for map_id in MISSING:
		var sc: Dictionary = s.chunks[slug(map_id)]
		var kept: Array = []
		for n in sc.get("npcs", []):
			if String(n.name) != MISSING[map_id]:
				kept.append(n)
		sc["npcs"] = kept
	var d := MapDefinitions.build(db(), s)
	assert_eq(d.errors.size(), 0, "errors: %s" % "; ".join(d.errors))
	var missing: PackedStringArray = []
	for m in d.npc_report.missing_markers:
		missing.append("%s:%s" % [m.map_id, m.name])
	missing.sort()
	assert_eq(missing, PackedStringArray(["000000030:Todd", "000000040:Sam", "000000050:Mai"]), "missing markers reported")
	d.ground_all(GroundQuery.new())
	for map_id in MISSING:
		var def := d.get_def(map_id)
		var placed := false
		for n in def.npc_definitions:
			if n.npc_name == MISSING[map_id]:
				placed = true
				assert_false(n.from_marker, "%s fallback flagged" % n.npc_name)
				assert_true(n.grounded, "%s fallback grounded" % n.npc_name)
				assert_true(def.footprint_contains(n.transform.origin), "%s fallback inside the map" % n.npc_name)
				assert_true(n.transform.origin.distance_to(def.player_spawns[0].origin) > 0.5, "%s does not stand on the spawn point" % n.npc_name)
		assert_true(placed, "%s placed on %s" % [MISSING[map_id], map_id])
	var warned := 0
	for w in d.warnings:
		if w.contains("no Blender NPC marker"):
			warned += 1
	assert_eq(warned, 3, "one warning per fallback")


func test_phase_one_export_shape() -> void:
	var s := sidecars("test_phase_one_export_shape")
	if s == null:
		return
	for chunk in s.chunks:
		var sc: Dictionary = s.chunks[chunk]
		for key in ["arrival_points", "player_spawns", "spawn_regions", "ledges", "meowdb_map_id"]:
			sc.erase(key)
		for n in sc.get("npcs", []):
			(n as Dictionary).erase("meowdb_npc_id")
		for p in sc.get("portals", []):
			for key in ["to_arrival", "to_spawn_index", "one_way", "to_meowdb_map_id"]:
				(p as Dictionary).erase(key)
	# Phase 1: 30.out00 named the v8 arrival marker as its to_portal, and 40000 carried that marker as a portal.
	var sc40: Dictionary = s.chunks[slug("000000040")]
	(sc40.portals as Array).append({"name": "in00", "map": 40000, "to_map": 30000, "to_portal": "out00", "kind": "edge",
		"one_way_arrival": true, "visual": "Portal_Arrival", "position": [55.3871, 12.2001, 208.7391],
		"xform": [1, 0, 0, 0, 1, 0, 0, 0, 1, 55.3871, 12.2001, 208.7391], "anchor_normal_xz": [0, -1]})
	for p in s.chunks[slug("000000030")].portals:
		if String(p.name) == "out00":
			p["to_portal"] = "in00"
	var d := MapDefinitions.build(db(), s)
	assert_eq(d.errors.size(), 0, "errors: %s" % "; ".join(d.errors))
	var gate := d.portal("000000040", "arrival:T_000000030_out00__000000040")
	assert_true(gate != null and gate.has_anchor, "the arrival gate finds its anchor among the portals")
	assert_eq(d.get_def("000000040").canonical_portals().size(), 1, "the v8 arrival marker is not a MeowDB portal")
	for id in d.ids():
		var def := d.get_def(id)
		assert_eq(def.player_spawns_authored, 1, "%s player_start is player_spawns[0]" % id)
		if def.spawn_point_count() > 0 and not (def.sidecar.get("spawn_areas", []) as Array).is_empty():
			assert_true(not def.spawn_areas.is_empty(), "%s falls back to the derived spawn_areas" % id)
	d.ground_all(GroundQuery.new())
	var unplaced := 0
	for id in d.ids():
		for slot in d.get_def(id).monster_spawn_definitions:
			if not slot.grounded:
				unplaced += 1
	assert_eq(unplaced, 0, "every slot placed on the old export too")


func test_added_fields_are_ignored() -> void:
	var s := sidecars("test_added_fields_are_ignored")
	if s == null:
		return
	for chunk in s.chunks:
		var sc: Dictionary = s.chunks[chunk]
		sc["future_field"] = {"anything": [1, 2, 3]}
		for p in sc.get("portals", []):
			p["future_portal_field"] = "x"
		for n in sc.get("npcs", []):
			n["future_npc_field"] = 7
	s.index["future_index_field"] = true
	var d := MapDefinitions.build(db(), s)
	assert_eq(d.errors.size(), 0, "errors: %s" % "; ".join(d.errors))
	assert_eq(d.canonical_portals().size(), 47, "portals")


func test_current_export_uses_authored_fields() -> void:
	var s := sidecars("test_current_export_uses_authored_fields")
	if s == null:
		return
	var d := MapDefinitions.build(db(), s)
	var sc40: Dictionary = d.get_def("000000040").sidecar
	if not sc40.has("player_spawns") or not sc40.has("spawn_regions"):
		print("NOTE the export predates authored player_spawns/spawn_regions; nothing to check")
		return
	var authored := WorldSidecars.marker_xform((sc40.player_spawns as Array)[0])
	assert_true(d.get_def("000000040").player_spawns[0].origin.is_equal_approx(authored.origin), "authored player_spawns[0] wins over player_start")
	var regions := (sc40.spawn_regions as Array).size()
	assert_eq(d.get_def("000000040").spawn_areas.size(), regions, "spawn_regions win over the derived spawn_areas")
	var gate := d.portal("000000040", "arrival:T_000000030_out00__000000040")
	assert_true(gate != null and gate.has_anchor, "arrival gate anchored on arrival_points")
	assert_eq(d.npc_report.missing_markers.size(), 0, "every MeowDB NPC has a marker in the current export")
