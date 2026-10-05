extends TestCase
## The minimap's data on all 25 maps (brief Phase 11): IslandWorld.ground_faces from the real collision, and
## MinimapModel built from the real MapDefinitions and canonical records. Every expected value is read from the
## canonical maps/<id>.json and npcs/<id>.json, never typed here: the title is the canonical street and name; the
## portal markers are exactly the visible (type 2) canonical portals with their canonical destination names (no
## arrival gate, no hidden type-1 portal); the NPC dots are exactly the canonical NPCs; a door gets a shop badge
## exactly when a shopkeeper stands behind it. Needs the export (INCLUDE_WORLD=1); prints one SKIP line without it.
## The checks that need collision share one island build (test_ground_and_models_on_every_map).

## The doors the brief's shop indication is about (Pan, Sid, Lucy): cross-checked against the canonical derivation.
const SHOP_DOORS := ["000000060.in00", "000001010.in00", "000001010.in02"]

var world: IslandWorld = null


func parity_keys() -> Dictionary:
	var maps: Array = []
	for id in db().ids("maps"):
		maps.append("minimap:%s" % id)
	return {
		"test_ground_and_models_on_every_map": maps + ["ui:shop-indication", "ui:portal-cue"],
		"test_the_sidecar_camera_is_the_game_camera": ["ui:minimap-projection"],
	}


func after_each() -> void:
	if world != null:
		world.free()
		world = null


func _skip(test_name: String) -> bool:
	if WorldSidecars.exists():
		return false
	print("SKIP %s: game/assets/world not present (run with INCLUDE_WORLD=1)" % test_name)
	return true


## The island's collision in the runner's tree (no visuals), as test_world_static builds it.
func _world() -> IslandWorld:
	var tree := Engine.get_main_loop() as SceneTree
	world = IslandWorld.new()
	world.name = "MinimapWorld"
	world.build_on_ready = false
	world.load_visuals = false
	world.attach_to_session = false
	tree.current_scene.add_child(world)
	world.build_now(db())
	return world


## The canonical type-2 portals of a map: {name: to_map_name}.
func _visible_portals(map_id: String) -> Dictionary:
	var out := {}
	for p: Dictionary in db().map(map_id).get("portals", []):
		if int(p.get("type", 0)) == 2:
			out[String(p["name"])] = String(p.get("to_map_name", ""))
	return out


func _canonical_npcs(map_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for n: Dictionary in db().map(map_id).get("npcs", []):
		out.append(str(n.get("id", "")))
	out.sort()
	return out


## One island build for every check that needs the collision: a test process survives about ten island builds (the
## eleventh aborts it with exit code 3, also with nothing else running), and the suite already makes most of them.
func test_ground_and_models_on_every_map() -> void:
	if _skip("test_ground_and_models_on_every_map"):
		return
	var w := _world()
	_check_ground_faces(w)
	_check_models(w)
	_check_hidden_portal_and_lane(w)


func _check_ground_faces(w: IslandWorld) -> void:
	assert_eq(w.defs.ids().size(), db().ids("maps").size(), "every canonical map has a definition")
	for id in w.defs.ids():
		var def := w.defs.get_def(id)
		var faces := w.ground_faces(id)
		assert_true(faces.size() > 0 and faces.size() % 3 == 0, "%s: %d ground face points" % [id, faces.size()])
		var box := _aabb_xz(def.footprint).grow(2.0)
		var inside := 0
		var in_height := 0
		for i in range(0, faces.size(), 3):
			var c := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
			if box.has_point(Vector2(c.x, c.z)):
				inside += 1
			if c.y >= def.y_min - 0.5 and c.y <= def.y_max + 0.5:
				in_height += 1
		var n := faces.size() / 3
		assert_true(inside >= n * 0.9, "%s: %d of %d face centroids inside the footprint (+2 m)" % [id, inside, n])
		assert_eq(in_height, n, "%s: every face within the chunk's height range [%.1f, %.1f]" % [id, def.y_min, def.y_max])
		assert_true(w.ground_faces(id) == faces, "%s: cached" % id)
	assert_eq(w.ground_faces("999999999").size(), 0, "an unknown map has no ground")


func _check_models(w: IslandWorld) -> void:
	var shown_portals := 0
	var canonical_visible := 0
	var npc_dots := 0
	var canonical_npcs := 0
	var shop_doors: PackedStringArray = []
	var roles := {}
	for id in w.defs.ids():
		var def := w.defs.get_def(id)
		var rec := db().map(id)
		var t0 := Time.get_ticks_usec()
		var m := MinimapModel.build(def, w.defs, db(), w.ground_faces(id))
		print("minimap %s: %d of %d ground triangles, tiers %d..%d, %.1f x %.1f m, %d portals, %d npcs, %d trails (%d ms)" % [
			id, m.ground_count(), w.ground_faces(id).size() / 3, m.ground_tiers[0] if m.ground_count() > 0 else 0,
			m.ground_tiers[m.ground_count() - 1] if m.ground_count() > 0 else 0, m.bounds.size.x, m.bounds.size.y,
			m.portals.size(), m.npcs.size(), m.trails.size(), (Time.get_ticks_usec() - t0) / 1000])
		assert_eq(m.map_name, String(rec["name"]), "%s: canonical name" % id)
		assert_eq(m.street_name, String(rec["street_name"]), "%s: canonical street" % id)
		assert_eq(m.ground_source, MinimapModel.SOURCE_COLLISION, "%s: drawn from the collision ground" % id)
		assert_eq(m.interior, def.is_interior(), "%s: interior floors iff an interior stage" % id)
		assert_true(m.ground_count() > 0 and m.ground_tiers.size() == m.ground_count(), "%s: %d ground triangles" % [id, m.ground_count()])
		var sorted := true
		for i in range(1, m.ground_tiers.size()):
			sorted = sorted and m.ground_tiers[i] >= m.ground_tiers[i - 1]
		assert_true(sorted, "%s: lower tiers drawn first" % id)
		# Upward faces only: the closed Ground volumes' undersides (down to 13 m below the base) are left out.
		assert_true(m.ground_tiers[0] >= -2, "%s: nothing drawn more than two tiers below the base (lowest %d)" % [id, m.ground_tiers[0]])
		assert_true(m.bounds.size.x > 0.0 and m.bounds.size.y > 0.0, "%s: bounds %s" % [id, m.bounds])
		# Portals: exactly the visible canonical ones, with their canonical destination names.
		var want := _visible_portals(id)
		var got := m.portal_ids()
		got.sort()
		var want_ids := PackedStringArray(want.keys())
		want_ids.sort()
		assert_eq(got, want_ids, "%s: portal markers = the canonical type-2 portals" % id)
		for p: Dictionary in m.portals:
			assert_eq(p["dest_name"], want.get(p["id"], "?"), "%s.%s: canonical destination name" % [id, p["id"]])
			assert_true(m.bounds.has_point(p["pos"]), "%s.%s inside the bounds" % [id, p["id"]])
			assert_true(String(p["kind"]) in [PortalDef.TYPE_EDGE, PortalDef.TYPE_DOOR], "%s.%s: edge or door" % [id, p["id"]])
			assert_ne(p["out_dir"], Vector2.ZERO, "%s.%s: an outward direction" % [id, p["id"]])
			var behind := MinimapModel.shopkeepers_on(db(), String(p["dest_map_id"]))
			assert_eq(bool(p["dest_shop"]), not behind.is_empty(), "%s.%s: shop badge iff a shopkeeper is behind it" % [id, p["id"]])
			if bool(p["dest_shop"]):
				shop_doors.append(String(p["key"]))
		shown_portals += m.portals.size()
		canonical_visible += want.size()
		# NPCs: exactly the canonical ones, each inside the bounds, with their role icon.
		var npc_ids := m.npc_ids()
		npc_ids.sort()
		assert_eq(npc_ids, _canonical_npcs(id), "%s: NPC dots = the canonical NPCs" % id)
		for n: Dictionary in m.npcs:
			assert_true(m.bounds.has_point(n["pos"]), "%s: NPC %s inside the bounds" % [id, n["npc_id"]])
			assert_eq(n["name"], String(db().npc(n["npc_id"])["name"]), "%s: canonical NPC name" % id)
			if String(n["role"]) != "":
				roles[String(n["npc_id"])] = String(n["role"])
		npc_dots += m.npcs.size()
		canonical_npcs += _canonical_npcs(id).size()
		# The player's first spawn is on the drawn map.
		assert_true(m.bounds.has_point(m.project(def.player_spawn(0).origin)), "%s: player_spawns[0] inside the bounds" % id)
	assert_eq(shown_portals, canonical_visible, "every visible canonical portal is shown, island-wide")
	assert_eq(npc_dots, canonical_npcs, "every canonical NPC has a dot")
	shop_doors.sort()
	assert_eq(shop_doors, PackedStringArray(SHOP_DOORS), "the shop badges: the doors to Pan, Sid and Lucy")
	for nid: String in roles:
		var rec := db().npc(nid)
		var want_role := MapIcons.ROLE_SHOP if rec.get("shop") is Dictionary else MapIcons.ROLE_TRANSPORT
		assert_eq(roles[nid], want_role, "NPC %s role icon" % nid)
		assert_true((rec.get("roles", []) as Array).has(MapIcons.SHOPKEEPER_ROLE if want_role == MapIcons.ROLE_SHOP else MapIcons.TRANSPORT_ROLE),
			"NPC %s: the icon follows the canonical role %s" % [nid, rec.get("roles")])
	var shops := 0
	for nid in db().ids("npcs"):
		if db().npc(nid).get("shop") is Dictionary:
			shops += 1
			assert_eq(roles.get(nid, ""), MapIcons.ROLE_SHOP, "shopkeeper %s has the coin" % nid)
	assert_true(shops > 0 and roles.values().has(MapIcons.ROLE_TRANSPORT), "shops %d, and a transport NPC: %s" % [shops, roles])


func _check_hidden_portal_and_lane(w: IslandWorld) -> void:
	var hidden := 0
	for id in w.defs.ids():
		var def := w.defs.get_def(id)
		var m := MinimapModel.build(def, w.defs, db(), w.ground_faces(id))
		for p in def.portals:
			if p.is_canonical() and p.hidden:
				hidden += 1
				assert_true(m.portal(p.portal_id).is_empty(), "%s: the hidden portal is not shown" % p.key())
			if not p.is_canonical():
				assert_true(m.portal(p.portal_id).is_empty(), "%s: arrival gates are not shown" % p.key())
		for t in w.defs.trails_of(id):
			var shown := m.trails.any(func(e: Dictionary) -> bool: return e["link_id"] == t.link_id)
			# A one-way trail is a way out only at its from end (maps[0]).
			var leaves := not t.one_way or (t.maps.size() >= 2 and t.maps[0] == id)
			var want := not t.hidden and t.has_geometry() and w.defs.graph.is_edge(t.link_id) and leaves
			assert_eq(shown, want, "%s: trail %s shown iff walkable out of the map and not hidden" % [id, t.link_id])
		# Every stub leads where one of the map's own canonical portals goes: a stub is never an exit MeowDB lacks.
		var dests := PackedStringArray()
		for p: Dictionary in db().map(id).get("portals", []):
			dests.append(String(p.get("to_map_id", "")))
		for e: Dictionary in m.trails:
			assert_true(String(e["other_map"]) in dests, "%s: the stub to %s follows a canonical portal %s" % [id, e["other_map"], dests])
	assert_true(hidden >= 1, "the canonical data has a hidden portal (000001020 in00)")
	# The one-way 30 -> 40 (a 2.4 m ledge down into 40): a stub on 30, none back up from 40.
	var snail := MinimapModel.build(w.defs.get_def("000000040"), w.defs, db(), w.ground_faces("000000040"))
	var snail_to := PackedStringArray()
	for e: Dictionary in snail.trails:
		snail_to.append(String(e["other_map"]))
		assert_true((e["points"] as PackedVector2Array).size() >= 2, "000000040: the stub has a line")
	assert_eq(snail_to, PackedStringArray(["000000041"]), "000000040: one stub, east to Snail Hunting Ground II, none back to 000000030")
	var east := MinimapModel.build(w.defs.get_def("000000030"), w.defs, db(), w.ground_faces("000000030"))
	assert_true(east.trails.any(func(e: Dictionary) -> bool: return e["other_map"] == "000000040"),
		"000000030 shows the one-way trail down to 000000040")


func test_the_sidecar_camera_is_the_game_camera() -> void:
	if _skip("test_the_sidecar_camera_is_the_game_camera"):
		return
	var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/misostory/camera.json"))
	assert_true(cfg is Dictionary, "camera.json")
	var game := CameraMath.basis_from_angles(float(cfg["default_pitch_down_deg"]), float(cfg["default_yaw_deg"]))
	var side := WorldSidecars.load_dir()
	var defs := MapDefinitions.build(db(), side)
	for id in defs.ids():
		var p := MinimapProjection.for_map(defs.get_def(id))
		assert_true(p != null, "%s: a gameplay camera in the sidecar" % id)
		if p == null:
			continue
		assert_true(p.right.distance_to(game.x) < 1e-3 and p.up.distance_to(game.y) < 1e-3,
			"%s: the sidecar camera (%s, %s) is the rig's default view (%s, %s)" % [id, p.right, p.up, game.x, game.y])


func test_the_footprint_fallback_without_collision() -> void:
	if _skip("test_the_footprint_fallback_without_collision"):
		return
	var side := WorldSidecars.load_dir()
	var defs := MapDefinitions.build(db(), side)
	for id in defs.ids():
		var def := defs.get_def(id)
		var m := MinimapModel.build(def, defs, db())
		assert_eq(m.ground_source, MinimapModel.SOURCE_FOOTPRINT, "%s: no collision faces, the footprint" % id)
		assert_true(m.ground_count() >= 2, "%s: the footprint filled" % id)
		assert_eq(m.portals.size(), _visible_portals(id).size(), "%s: the portals still shown" % id)
		var routes: Variant = def.sidecar.get("routes", [])
		assert_eq(m.routes.size() > 0, routes is Array and not (routes as Array).is_empty(), "%s: the routes drawn" % id)
		assert_true(m.bounds.has_point(m.project(def.player_spawn(0).origin)), "%s: player_spawns[0] inside" % id)


static func _aabb_xz(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r
