extends TestCase
## L0 data checks for MapDefinitions (MAP_ARCHITECTURE.md sections 4.3 and 4.13): the crosswalk, the per-map API,
## the v8 cross-check and the NPC parity report. Checks that need the Blender sidecars print one SKIP line when
## game/assets/world is absent (the ISOLATE mirror omits it unless INCLUDE_WORLD=1).

static var _with_world: MapDefinitions = null


func defs_canonical() -> MapDefinitions:
	return MapDefinitions.build(db())


## Definitions joined with the export, or null (after printing SKIP) when the export is not present.
func defs_world(test_name: String) -> MapDefinitions:
	if not WorldSidecars.exists():
		print("SKIP %s: game/assets/world not present (run with INCLUDE_WORLD=1)" % test_name)
		return null
	if _with_world == null:
		_with_world = MapDefinitions.build(db(), WorldSidecars.load_dir())
	return _with_world


func test_crosswalk_is_bijective_with_25_rows() -> void:
	var d := defs_canonical()
	assert_eq(d.crosswalk_rows.size(), 25, "crosswalk rows")
	var ids := {}
	var slugs := {}
	var v8 := {}
	for row in d.crosswalk_rows:
		var id := String(row.get("meowdb_id", ""))
		var slug := String(row.get("iteration_one_slug", ""))
		assert_false(ids.has(id), "duplicate id %s" % id)
		assert_false(slugs.has(slug), "duplicate slug %s" % slug)
		assert_false(v8.has(int(row.gms_v8_id)), "duplicate v8 id %s" % str(row.gms_v8_id))
		ids[id] = true
		slugs[slug] = true
		v8[int(row.gms_v8_id)] = true
		assert_true(db().has("maps", id), "crosswalk id %s has canonical data" % id)
		assert_true(slug.ends_with("_%d" % int(row.gms_v8_id)), "slug %s ends with its v8 id" % slug)
	for id in db().ids("maps"):
		assert_true(ids.has(id), "canonical map %s has a crosswalk row" % id)


func test_per_map_api_from_canonical_data() -> void:
	var d := defs_canonical()
	for id in d.ids():
		var def := d.get_def(id)
		var rec := db().map(id)
		assert_eq(def.map_name, String(rec.name), "%s name" % id)
		assert_eq(def.street_name, String(rec.street_name), "%s street" % id)
		assert_eq(def.respawn_location.map_id, String(rec.return_map_id), "%s respawn map" % id)
		assert_eq(def.respawn_location.spawn_index, d.tuning.respawn_spawn_index(),
			"%s respawn spawn index comes from death.json respawn_player_spawn_index (open question 1)" % id)
		assert_eq(def.player_spawns.size(), maxi((rec.player_spawns as Array).size(), 1), "%s player spawn count" % id)
		assert_eq(def.monster_spawn_definitions.size(), (rec.spawns as Array).size(), "%s spawn slot count" % id)
		assert_eq(def.npc_definitions.size(), (rec.npcs as Array).size(), "%s npc count" % id)
		assert_eq(String(def.environment_configuration.bgm), String(rec.bgm.path), "%s bgm" % id)
		assert_eq(bool(def.environment_configuration.is_town), bool(rec.is_town), "%s is_town" % id)
		assert_eq(int(def.environment_configuration.field_limit), int(rec.field_limit), "%s raw field_limit" % id)
		var dests: PackedStringArray = []
		for p in rec.portals:
			if not (String(p.to_map_id) in dests):
				dests.append(String(p.to_map_id))
		assert_eq(def.destination_maps, dests, "%s destination_maps" % id)
		for i in def.monster_spawn_definitions.size():
			var s := def.monster_spawn_definitions[i]
			assert_eq(s.index, i, "%s slot index" % id)
			assert_eq(s.mob_id, str(rec.spawns[i].mob_id), "%s slot %d species" % [id, i])


## The respawn spawn index is an adaptation value (MeowDB is silent): it must live in data with a reason, never in
## code, and the definitions must follow it.
func test_respawn_spawn_index_is_adaptation_data() -> void:
	var raw: Variant = db().miso_table("death")
	var section: Dictionary = (raw as Dictionary).get(WorldTuning.DEATH_RESPAWN_INDEX_KEY, {}) if raw is Dictionary else {}
	assert_true(section.has("value"), "death.json respawn_player_spawn_index.value")
	assert_true(String(section.get("reason", "")) != "", "respawn_player_spawn_index has a reason")
	assert_eq(section.get("verified", null), false, "respawn spawn index is unverified (MeowDB does not publish it)")
	var pres: Variant = db().miso_table("presentation")
	assert_false(pres is Dictionary and (pres as Dictionary).has("respawn"), "the key moved: presentation.json has no respawn section")
	var d := defs_canonical()
	assert_eq(d.tuning.respawn_spawn_index(), int(section.get("value", -1)), "WorldTuning reads death.json")
	# The old lookup still answers (the shell's checks call it) without a missing-key error.
	assert_eq(d.tuning.count("respawn", "player_spawn_index"), d.tuning.respawn_spawn_index(), "moved key alias")
	assert_eq(d.tuning.errors.size(), 0, "no missing-key error: %s" % ", ".join(d.tuning.errors))
	d.tuning.death = d.tuning.death.duplicate(true)
	d.tuning.death[WorldTuning.DEATH_RESPAWN_INDEX_KEY]["value"] = 2
	var cw := d.crosswalk_rows
	var rebuilt := MapDefinitions.new()
	rebuilt.tuning = d.tuning
	rebuilt.spawn_model = d.spawn_model
	rebuilt.crosswalk_rows = cw
	rebuilt.slug_of = d.slug_of
	rebuilt._build_map(db(), "000000040")
	assert_eq(rebuilt.get_def("000000040").respawn_location.spawn_index, 2, "follows the data")
	assert_eq(rebuilt.get_def("000000040").respawn_location.map_id, "000000060", "returnMap unchanged")


func test_returnmap_examples_from_the_spec() -> void:
	var d := defs_canonical()
	var expect := {"000000040": "000000060", "000000050": "000000060", "000001014": "000001010", "000000060": "000000060",
		"000000021": "000000021", "000000061": "000000060", "000001011": "000001010", "000001012": "000001010",
		"000001013": "000001010", "000000001": "000000001"}
	for id in expect:
		assert_eq(d.get_def(id).respawn_location.map_id, expect[id], "%s respawns in" % id)


func test_every_map_has_a_sidecar_and_geometry() -> void:
	var d := defs_world("test_every_map_has_a_sidecar_and_geometry")
	if d == null:
		return
	assert_eq(d.errors.size(), 0, "build errors: %s" % "; ".join(d.errors))
	var interiors: PackedStringArray = []
	for id in d.ids():
		var def := d.get_def(id)
		assert_true(def.has_markers, "%s has a sidecar" % id)
		assert_true(d.sidecars.file_path(def.slug, "visual") != "", "%s visual glb listed" % id)
		assert_true(d.sidecars.file_path(def.slug, "collision") != "", "%s collision glb listed" % id)
		assert_true(def.footprint.size() >= 4, "%s footprint" % id)
		assert_true(def.camera_bounds.size() >= 4, "%s camera bounds" % id)
		assert_true(def.ortho_size > 0.0, "%s ortho size from cameras.gameplay" % id)
		assert_true(def.frame != Transform3D.IDENTITY, "%s frame" % id)
		assert_true(def.kill_y < def.base_y, "%s kill_y below base" % id)
		assert_true(def.player_spawns_authored >= 1, "%s player_spawns[0] authored" % id)
		assert_true(def.footprint_contains(def.player_spawns[0].origin), "%s player_spawns[0] inside its footprint" % id)
		if def.is_interior():
			interiors.append(id)
		for p in def.canonical_portals():
			assert_true(p.has_anchor, "%s has a marker" % p.key())
			assert_true(def.footprint_contains(p.spawn_transform.origin), "%s arrival inside its footprint" % p.key())
	assert_eq(interiors, PackedStringArray(["000000021", "000000061", "000001011", "000001013"]), "interior stage maps")


func test_resolution_agrees_with_v8_names() -> void:
	var d := defs_world("test_resolution_agrees_with_v8_names")
	if d == null:
		return
	for p in d.canonical_portals():
		assert_true(bool(p.provenance.get("v8_name_match", false)), "%s vs v8 '%s'" % [p.key(), String(p.provenance.get("v8_to_portal", ""))])


func test_door_links_and_world_spaces() -> void:
	var d := defs_world("test_door_links_and_world_spaces")
	if d == null:
		return
	var doors := 0
	var trails := 0
	for id in d.graph.links:
		var link: Dictionary = d.graph.links[id]
		if link.kind == PortalGraph.KIND_DOOR:
			doors += 1
		else:
			trails += 1
	assert_eq(doors, 4, "door links")
	assert_eq(trails, 20, "trail links")
	var door_portals := 0
	for p in d.canonical_portals():
		if p.portal_type == PortalDef.TYPE_DOOR:
			door_portals += 1
			assert_eq(p.visual, "Portal_Door", "%s door visual" % p.key())
		elif not p.hidden:
			assert_eq(p.visual, "Portal_Swirl", "%s swirl (MeowDB type 2, even where Iteration One drew an arrival marker)" % p.key())
	assert_eq(door_portals, 8, "door portals (Appendix A)")


func test_npc_parity_report() -> void:
	var d := defs_world("test_npc_parity_report")
	if d == null:
		return
	var meow := 0
	for id in d.ids():
		var def := d.get_def(id)
		var rec := db().map(id)
		var expected: PackedStringArray = []
		for n in rec.npcs:
			expected.append(str(n.id))
		var actual: PackedStringArray = []
		for n in def.npc_definitions:
			actual.append(n.npc_id)
			assert_true(db().has("npcs", n.npc_id), "%s NPC %s is a MeowDB NPC" % [id, n.npc_id])
		assert_eq(actual, expected, "%s runtime NPCs are exactly MeowDB's" % id)
		meow += expected.size()
	assert_eq(meow, 21, "MeowDB Maple Island NPCs")
	var missing: PackedStringArray = []
	for m in d.npc_report.missing_markers:
		missing.append("%s %s(%s)" % [m.map_id, m.name, m.npc_id])
	var extra: PackedStringArray = []
	for m in d.npc_report.extra_markers:
		extra.append("%s %s" % [m.map_id, m.name])
	print("NPC parity: %d matched; missing markers (fallback placed): %s; extra Blender markers (ignored): %s" % [
		int(d.npc_report.matched), ", ".join(missing) if not missing.is_empty() else "none",
		", ".join(extra) if not extra.is_empty() else "none"])
	assert_eq(int(d.npc_report.matched) + missing.size(), 21, "every MeowDB NPC is placed")
	# Blender NPCs MeowDB does not place on Maple Island (ignored by the runtime). Mai is a MeowDB NPC (A Split Road),
	# so a Mai marker left over would be a mismatch, not an extra: she is not in this list.
	for m in d.npc_report.extra_markers:
		var known := ["Tia", "Maple Administrator", "Paul"]
		assert_true(String(m.name) in known, "unexpected extra Blender NPC %s on %s" % [m.name, m.map_id])
