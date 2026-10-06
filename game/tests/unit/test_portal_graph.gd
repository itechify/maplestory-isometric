extends TestCase
## L0 graph checks (MAP_ARCHITECTURE.md section 4.13): portal resolution, the directed graph against MeowDB,
## reachability, the SCC allowlist and returnMap reachability. Pure; runs without the Blender export.

const START_MAP := "000000001"

var _defs: MapDefinitions = null


func defs() -> MapDefinitions:
	if _defs == null:
		_defs = MapDefinitions.build(db())
	return _defs


## Contract C6. The three whole-graph tests compare every canonical portal with its MeowDB record, so they prove each
## portal:<map>/<name> key. The returnMap test checks the respawn map against the canonical record, not that anything
## is saved, so it proves no persistence key.
func parity_keys() -> Dictionary:
	var portals: Array = []
	for id in db().ids("maps"):
		for p in db().map(id).get("portals", []):
			portals.append("portal:%s/%s" % [id, String(p.name)])
	return {
		"test_every_meowdb_portal_has_exactly_one_portal_def": portals,
		"test_destination_resolution_is_unique_and_matches_meowdb_derivation": portals + ["xref:portal-destination"],
		"test_directed_graph_equals_meowdb": portals + ["xref:portal-destination"],
		"test_bfs_from_start_reaches_all_25_maps": ["xref:portal-destination"],
		"test_every_map_reaches_its_return_map": ["mechanic:death-respawn"],
	}


func test_builds_without_errors() -> void:
	assert_eq(defs().errors.size(), 0, "build errors: %s" % "; ".join(defs().errors))
	assert_eq(defs().ids().size(), 25, "map count")


func test_every_meowdb_portal_has_exactly_one_portal_def() -> void:
	var total := 0
	for id in db().ids("maps"):
		var rec := db().map(id)
		for p in rec.get("portals", []):
			total += 1
			var found := 0
			for pd in defs().get_def(id).portals:
				if pd.portal_id == String(p.name) and pd.is_canonical():
					found += 1
			assert_eq(found, 1, "%s.%s PortalDefs" % [id, p.name])
	assert_eq(total, 47, "MeowDB portal count (MAP_ARCHITECTURE 3.1)")
	assert_eq(defs().canonical_portals().size(), 47, "canonical PortalDefs")


func test_non_canonical_portals_have_an_adaptation_reason() -> void:
	var arrivals := 0
	for key in defs().graph.portals:
		var p: PortalDef = defs().graph.portals[key]
		if p.is_canonical():
			continue
		arrivals += 1
		assert_eq(p.portal_type, PortalDef.TYPE_ARRIVAL, "%s type" % key)
		assert_eq(p.interaction_type, PortalDef.INTERACT_WALK_ONLY, "%s interaction" % key)
		assert_true(String(p.provenance.get("adaptation_reason", "")) != "", "%s has no reason" % key)
	assert_eq(arrivals, 1, "exactly one arrival gate (30 -> 40)")
	var gate := defs().portal("000000040", "arrival:T_000000030_out00__000000040")
	assert_true(gate != null, "the 30 -> 40 arrival gate exists")


func test_destination_resolution_is_unique_and_matches_meowdb_derivation() -> void:
	var reciprocal := 0
	var spawn := 0
	for p in defs().canonical_portals():
		var res := String(p.provenance.get("resolution", ""))
		var meow := String(p.provenance.get("meowdb_to_portal", ""))
		if res == PortalGraph.RES_RECIPROCAL:
			reciprocal += 1
			assert_eq(p.destination_portal_id, meow, "%s agrees with MeowDB's reverse lookup" % p.key())
			var back := defs().portal(p.destination_map_id, p.destination_portal_id)
			assert_true(back != null and back.destination_map_id == p.source_map_id, "%s reciprocal leads back" % p.key())
		elif res == PortalGraph.RES_PLAYER_SPAWN:
			spawn += 1
			assert_eq(meow, "", "%s has no MeowDB destination portal" % p.key())
			assert_eq(p.destination_spawn_index, 0, "%s uses playerSpawns[0]" % p.key())
		else:
			fail("%s resolved by '%s'" % [p.key(), res])
	assert_eq(reciprocal, 46, "portals resolved by the unique reciprocal")
	assert_eq(spawn, 1, "portals resolved to playerSpawns[0]")
	var one_way := defs().portal("000000030", "out00")
	assert_eq(one_way.destination_map_id, "000000040", "30.out00 destination")
	assert_eq(one_way.destination_portal_id, "", "30.out00 has no destination portal")


func test_directed_graph_equals_meowdb() -> void:
	var expected := {}
	for id in db().ids("maps"):
		for p in db().map(id).get("portals", []):
			expected["%s>%s" % [id, String(p.to_map_id)]] = true
	var actual := defs().graph.edge_set()
	var exp_keys: Array = expected.keys()
	exp_keys.sort()
	var act_keys: Array = actual.keys()
	act_keys.sort()
	assert_eq(act_keys, exp_keys, "directed map graph")
	assert_eq(act_keys.size(), 47, "directed edges (one per portal; no two portals share a direction)")


func test_bfs_from_start_reaches_all_25_maps() -> void:
	var reach := defs().graph.reachable_from(START_MAP)
	assert_eq(reach.size(), 25, "reachable from %s: %s" % [START_MAP, ", ".join(reach)])


func test_scc_allowlist_covers_the_one_way_link() -> void:
	var allow := {}
	for l in defs().tuning.portal_section("one_way_allowlist").get("links", []):
		allow["%s>%s" % [String(l.from), String(l.to)]] = true
	var crossing := defs().graph.cross_component_edges()
	var crossing_keys: PackedStringArray = []
	for e in crossing:
		crossing_keys.append("%s>%s" % [e[0], e[1]])
		assert_true(allow.has("%s>%s" % [e[0], e[1]]), "edge %s>%s leaves its component but is not allowlisted" % [e[0], e[1]])
	assert_eq(crossing_keys, PackedStringArray(["000000030>000000040"]), "the only one-way crossing")
	var sccs := defs().graph.strongly_connected_components()
	assert_eq(sccs.size(), 2, "components: %s" % str(sccs))
	var source := PackedStringArray(["000000001", "000000010", "000000020", "000000021", "000000030"])
	var found := false
	for c in sccs:
		if c == source:
			found = true
	assert_true(found, "1, 10, 20, 21, 30 form the source component")


func test_every_map_reaches_its_return_map() -> void:
	for id in defs().ids():
		var ret := defs().get_def(id).respawn_location.map_id
		assert_eq(ret, String(db().map(id).return_map_id), "%s respawn_location" % id)
		assert_true(ret in defs().graph.reachable_from(id), "%s cannot reach its returnMap %s" % [id, ret])


func test_has_direction_follows_meowdb_and_is_one_way_for_30_40() -> void:
	var g := defs().graph
	assert_true(g.has_direction("000000030", "000000040"), "30 -> 40")
	assert_false(g.has_direction("000000040", "000000030"), "40 -> 30 must not exist")
	assert_true(g.has_direction("000001010", "000001011"), "Amherst -> Weapon Store")
	assert_false(g.has_direction("000000001", "000000060"), "no direct 1 -> 60")


## Link modes come from portal_adaptations.json (section 4.4): force_link_mode is empty since M2, so each link takes
## default_link_mode by kind; every portal's interaction follows its link (press_up_or_walk on edge-mode trails,
## press_up otherwise, walk_only for the arrival gate). Without the export every link is a trail (door links are
## known from the sidecar's door markers; see test_link_kinds_with_the_export).
func test_links_and_link_modes() -> void:
	var g := defs().graph
	assert_eq(g.links.size(), 24, "24 links (MAP_ARCHITECTURE Appendix A)")
	assert_eq(defs().tuning.forced_link_mode(), "", "force_link_mode is empty (M2): links take their default mode")
	var defaults := defs().tuning.portal_section("default_link_mode")
	var overrides: Dictionary = defs().tuning.portal_section("link_modes").get("overrides", {})
	var one_way := 0
	for id in g.links:
		var link: Dictionary = g.links[id]
		if bool(link.one_way):
			one_way += 1
		var expected := PortalDef.LINK_WARP if String(link.kind) == PortalGraph.KIND_DOOR else String(defaults.trail)
		if overrides.has(id) and String(link.kind) != PortalGraph.KIND_DOOR:
			expected = String(overrides[id].mode)
		assert_eq(String(link.mode), expected, "%s (%s) mode" % [id, String(link.kind)])
		assert_eq((link.ends as PackedStringArray).size(), 2, "%s has two portal ends: %s" % [id, str(link.ends)])
		assert_eq((link.maps as PackedStringArray).size(), 2, "%s joins two maps: %s" % [id, str(link.maps)])
	assert_eq(one_way, 1, "one one-way link")
	assert_true(g.links.has("T_000000030_out00__000000040"), "one-way link id")
	assert_eq(g.links["T_000000030_out00__000000040"].ends, PackedStringArray(["000000030.out00",
		"000000040.arrival:T_000000030_out00__000000040"]), "the one-way link ends at the arrival gate")
	for p in defs().canonical_portals():
		var expect := PortalDef.INTERACT_PRESS_UP_OR_WALK if g.is_edge(p.link_id) else PortalDef.INTERACT_PRESS_UP
		assert_eq(p.interaction_type, expect, "%s interaction (link %s)" % [p.key(), g.link_mode(p.link_id)])
		assert_eq(p.link_mode, g.link_mode(p.link_id), "%s carries its link's mode" % p.key())
		assert_true(p.accepts_press(), "%s accepts press" % p.key())
	var gate := defs().portal("000000040", "arrival:T_000000030_out00__000000040")
	assert_eq(gate.interaction_type, PortalDef.INTERACT_WALK_ONLY, "the arrival gate is walk-only")
	assert_false(gate.accepts_press(), "the arrival gate cannot be pressed")


## With the export: 20 trail links and 4 door links; every trail walks (edge) and the doors warp. A trail whose source
## geometry cannot be walked would be kept warp by a link_modes override with its reason; since the Blender round-3
## export (000001014 moved, its trail re-routed) there is none, and 000001012 <-> 000001014 walks too.
func test_link_kinds_with_the_export() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_link_kinds_with_the_export: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var w := MapDefinitions.build(db(), WorldSidecars.load_dir())
	var overrides: Dictionary = w.tuning.portal_section("link_modes").get("overrides", {})
	for id in overrides:
		assert_true(w.graph.links.has(id), "override %s names a link" % id)
		assert_true(String((overrides[id] as Dictionary).get("reason", "")).length() > 40, "override %s explains itself" % id)
	var kinds := {}
	for id in w.graph.links:
		var link: Dictionary = w.graph.links[id]
		kinds[String(link.kind)] = int(kinds.get(String(link.kind), 0)) + 1
		var expected := PortalDef.LINK_EDGE
		if String(link.kind) == PortalGraph.KIND_DOOR:
			expected = PortalDef.LINK_WARP
		elif overrides.has(id):
			expected = String(overrides[id].mode)
		assert_eq(String(link.mode), expected, "%s (%s) mode" % [id, String(link.kind)])
	assert_eq(kinds, {"trail": 20, "door": 4}, "link kinds")
	assert_eq(w.graph.mode_counts(), {"edge": 20 - overrides.size(), "warp": 4 + overrides.size()}, "mode counts")
	assert_eq(overrides.size(), 0, "no trail is kept warp: all 20 walk (docs/runtime/traversal_report.json)")
	assert_eq(w.graph.link_mode("T_000001012_west00__000001014_east00"), PortalDef.LINK_EDGE,
		"the 000001012 <-> 000001014 trail walks since the Blender round-3 re-route (WORLD_RUNTIME.md Source world status)")


## force_link_mode "warp" is the M1 fallback: every link press-Up only, the arrival gate still walk-only.
func test_force_link_mode_warp_is_the_m1_fallback() -> void:
	var local := MapDefinitions.build(db())
	var defaults := local.tuning.portal_section("default_link_mode")
	local.graph.build_links({PortalGraph.KIND_TRAIL: String(defaults.trail), PortalGraph.KIND_DOOR: String(defaults.door)}, {},
		PortalDef.LINK_WARP)
	for id in local.graph.links:
		assert_eq(local.graph.link_mode(id), PortalDef.LINK_WARP, "%s forced warp" % id)
		assert_false(local.graph.is_edge(id), "%s is not walkable" % id)
	for p in local.canonical_portals():
		assert_eq(p.interaction_type, PortalDef.INTERACT_PRESS_UP, "%s is press_up in warp mode" % p.key())
	assert_eq(local.portal("000000040", "arrival:T_000000030_out00__000000040").interaction_type, PortalDef.INTERACT_WALK_ONLY,
		"the arrival gate stays walk-only")
	assert_true(local.graph.has_direction("000000030", "000000040"), "30 -> 40 still by press-Up")


## The debug console's path (section 4.14): set_link_mode switches trail links both ways (portals follow, one
## link_mode_changed per actual change) and refuses edge on a door link.
func test_set_link_mode_switches_trail_links_and_never_doors() -> void:
	var local := MapDefinitions.build(db())
	var g := local.graph
	var id := "T_000000040_east00__000000041_west00"
	var changes: Array[String] = []
	g.link_mode_changed.connect(func(l: String, m: String) -> void: changes.append("%s=%s" % [l, m]))
	assert_eq(g.set_link_mode(id, PortalDef.LINK_WARP), OK, "trail -> warp")
	assert_eq(local.portal("000000040", "east00").interaction_type, PortalDef.INTERACT_PRESS_UP, "warp: press Up only")
	assert_eq(local.portal("000000041", "west00").link_mode, PortalDef.LINK_WARP, "both ends follow")
	assert_eq(g.set_link_mode(id, PortalDef.LINK_WARP), OK, "again")
	assert_eq(changes, [id + "=warp"] as Array[String], "one change signal per actual change")
	assert_eq(g.set_link_mode(id, PortalDef.LINK_EDGE), OK, "trail -> edge (M2)")
	assert_eq(local.portal("000000040", "east00").interaction_type, PortalDef.INTERACT_PRESS_UP_OR_WALK, "edge: walk or press Up")
	assert_eq(g.set_link_mode("nope", PortalDef.LINK_WARP), ERR_DOES_NOT_EXIST, "unknown link")
	assert_eq(g.set_link_mode("all", "sideways"), ERR_INVALID_PARAMETER, "bad mode")
	# A door link (kind from the export's door markers; set by hand here) is always warp.
	var door := "T_000001010_in00__000001011_out00"
	g.links[door]["kind"] = PortalGraph.KIND_DOOR
	g.set_link_mode(door, PortalDef.LINK_WARP)
	assert_eq(g.set_link_mode(door, PortalDef.LINK_EDGE), ERR_UNAVAILABLE, "doors are always warp")
	assert_eq(g.set_link_mode("all", PortalDef.LINK_WARP), OK, "all warp")
	assert_eq(g.mode_counts(), {"warp": 24}, "every link warp")
	assert_eq(g.set_link_mode("all", PortalDef.LINK_EDGE), OK, "all edge")
	assert_eq(g.link_mode(door), PortalDef.LINK_WARP, "all edge leaves the door warp")
	assert_eq(g.mode_counts(), {"edge": 23, "warp": 1}, "every trail link edge")


func test_hidden_type_one_portal() -> void:
	var p := defs().portal("000001020", "in00")
	assert_eq(p.canonical_type, 1, "MeowDB type")
	assert_true(p.hidden, "type 1 is hidden")
	assert_true(p.accepts_press(), "but press-Up still works")
	assert_eq(p.visual, "", "no swirl")
	var visible := 0
	for q in defs().canonical_portals():
		if not q.hidden:
			visible += 1
	assert_eq(visible, 46, "46 visible portals")
