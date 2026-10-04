extends TestCase
## The one-way link invariant (MAP_ARCHITECTURE.md sections 4.4 and 4.13 L0/L1): MeowDB's only one-way link,
## 000000030.out00 -> 000000040, is enforced by the source world as a ledge the player can drop down but never climb:
##   jump_apex_m_at_cap + step_up_m + clearance_margin_m <= ledge height <= max_drop_m
## with the jump apex and step-up from the player's MovementModel (canonical jump table x WorldScale, movement.json),
## the margins from portal_adaptations.json one_way_ledge, and the ledge from the Blender sidecar (`ledges[]`). The
## ledge face must lie on the arrival gate plane, footprint + containment.ring_offset_m. Needs INCLUDE_WORLD=1 for
## the sidecar part; prints one SKIP line without it.


func test_the_ledge_cannot_be_climbed_and_is_a_legal_drop() -> void:
	var d := MapDefinitions.build(db())
	var rule := d.tuning.portal_section("one_way_ledge")
	for key in ["clearance_margin_m", "max_drop_m", "gate_plane_tolerance_m", "reason"]:
		assert_true(rule.has(key), "portal_adaptations.json one_way_ledge.%s" % key)
	var mm := MovementModel.from_db(db())
	var apex := mm.jump_apex_at_cap()
	assert_true(apex > 0.5 and apex < 2.0, "jump apex at the Jump cap %.3f m (canonical px x WorldScale)" % apex)
	var min_height := apex + mm.step_up + float(rule.get("clearance_margin_m", 0.0))
	var max_height := float(rule.get("max_drop_m", 0.0))
	assert_true(min_height <= max_height, "the invariant is satisfiable: %.3f <= %.3f" % [min_height, max_height])
	if not WorldSidecars.exists():
		print("SKIP test_the_ledge_cannot_be_climbed_and_is_a_legal_drop (sidecar part): game/assets/world not present")
		return
	var w := MapDefinitions.build(db(), WorldSidecars.load_dir())
	var links: Array = w.tuning.portal_section("one_way_allowlist").get("links", [])
	assert_eq(links.size(), 1, "one allowlisted one-way link")
	for l in links:
		var src := w.portal(String(l.from), "out00")
		var to_def := w.get_def(String(l.to))
		assert_true(src != null and to_def != null, "%s -> %s portals" % [l.from, l.to])
		if src == null or to_def == null:
			continue
		# The arrival gate of that link names the sidecar arrival point the ledge belongs to.
		var gate: PortalDef = null
		for p in to_def.portals:
			if p.portal_type == PortalDef.TYPE_ARRIVAL and String(p.provenance.get("source_portal", "")) == src.key():
				gate = p
		assert_true(gate != null, "%s has an arrival gate for %s" % [to_def.map_id, src.key()])
		if gate == null:
			continue
		var anchor := String(gate.provenance.get("anchor_marker", ""))
		var ledge: Dictionary = {}
		for lg in to_def.sidecar.get("ledges", []):
			if lg is Dictionary and String(lg.get("arrival_point", "")) == anchor:
				ledge = lg
		assert_false(ledge.is_empty(), "%s exports a ledge for arrival point %s" % [to_def.slug, anchor])
		if ledge.is_empty():
			continue
		var h := float(ledge.get("height_m", 0.0))
		assert_true(h >= min_height - 1e-6, "ledge %.2f m is climbable: needs >= %.3f (apex %.3f + step %.2f + margin %.2f)" % [
			h, min_height, apex, mm.step_up, float(rule.clearance_margin_m)])
		assert_true(h <= max_height + 1e-6, "ledge %.2f m exceeds the %.2f m one-way drop cap" % [h, max_height])
		var tol := float(rule.get("gate_plane_tolerance_m", 0.0))
		assert_true(absf(float(ledge.get("face_offset_from_gate_m", INF))) <= tol, "ledge face %.3f m off the gate plane" % float(ledge.get("face_offset_from_gate_m", INF)))
		var plane: Dictionary = ledge.get("gate_plane", {}) if ledge.get("gate_plane", null) is Dictionary else {}
		assert_near(float(plane.get("offset_from_footprint_m", INF)), w.tuning.num("containment", "ring_offset_m"), tol,
			"gate plane at footprint + ring offset (the containment ring line)")
		# The landing is the arrival: player_spawns[0] of the destination stands on the ledge's lower level.
		assert_near(to_def.player_spawn(0).origin.y, float(ledge.get("landing_y", INF)), 0.3, "player_spawns[0] on the landing")
