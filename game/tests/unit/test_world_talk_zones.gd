extends TestCase
## NPC talk zones (docs/runtime/WORLD_RUNTIME.md "NPC talk zones"): presentation.json npc.interaction_radius_m and
## npc.talk_centre_height_m for every NPC, and the npc.talk_zones profiles (the shopkeepers' "across_counter") read
## through WorldTuning.talk_zone; WorldNpc builds its TalkArea sphere from them. L0: no world export needed. The walk
## itself (every NPC talked to on foot, at least 0.4 m inside its zone) is test_npc_reach_scenario.gd.


func tuning() -> WorldTuning:
	return WorldTuning.from_db(db())


func test_an_npc_no_profile_lists_gets_the_default_zone() -> void:
	var t := tuning()
	var z := t.talk_zone("8")  # Robin: in the open, no counter
	assert_eq(String(z.profile), "default", "Robin's profile")
	assert_near(float(z.radius_m), t.num("npc", "interaction_radius_m"), 1e-6, "the default radius is npc.interaction_radius_m")
	assert_near(float(z.centre_height_m), t.num("npc", "talk_centre_height_m"), 1e-6, "the default centre height")
	# The centre height is its own key now, no longer derived from the radius; it keeps the old value (half of 1.6 m).
	assert_near(t.num("npc", "talk_centre_height_m"), t.num("npc", "interaction_radius_m") * 0.5, 1e-6,
		"the default zone sits where the old rule (half the radius) put it")


func test_across_counter_lists_exactly_the_meowdb_shopkeepers() -> void:
	var t := tuning()
	var profiles := t.talk_zone_profiles()
	assert_has(profiles, "across_counter", "the shopkeepers' profile")
	var p: Dictionary = profiles.get("across_counter", {})
	var listed := PackedStringArray()
	for v: Variant in p.get("npcs", []):
		listed.append(str(v))
	listed.sort()
	var keepers := PackedStringArray()
	for sid in db().ids("shops"):
		keepers.append(str(db().shop(sid).get("npc_id", "")))
	keepers.sort()
	assert_eq(listed, keepers, "across_counter lists the NPC of every canonical shop, and only those")
	assert_true(float(p.get("radius_m", 0.0)) > t.num("npc", "interaction_radius_m"), "the counter zone reaches further")
	assert_near(float(p.get("centre_height_m", -1.0)), t.num("npc", "talk_centre_height_m"), 1e-6,
		"the counter zone is not raised: only its reach grows")
	assert_true(String(p.get("reason", "")).length() > 40, "the adaptation has a reason")
	assert_eq(p.get("verified", null), false, "an adaptation stays verified: false")
	for id in keepers:
		var z := t.talk_zone(id)
		assert_eq(String(z.profile), "across_counter", "shopkeeper %s uses the counter zone" % id)
		assert_near(float(z.radius_m), float(p.get("radius_m", 0.0)), 1e-6, "shopkeeper %s radius" % id)


func test_the_shipped_talk_zone_data_is_sound() -> void:
	assert_eq(tuning().talk_zone_errors(), PackedStringArray(), "presentation.json npc.talk_zones")


func test_talk_zone_errors_catch_bad_profiles() -> void:
	var t := tuning()
	t.presentation = t.presentation.duplicate(true)  # never the shared ContentDB table
	var npc: Dictionary = t.presentation["npc"]
	npc["talk_zones"] = {
		"a_first": {"npcs": ["16"], "radius_m": 2.0, "centre_height_m": 0.8, "reason": "test"},
		"b_second": {"npcs": ["16", "20"], "radius_m": 3.0, "centre_height_m": 0.8, "reason": "test"},
		"c_no_reason": {"npcs": ["21"], "radius_m": 2.0, "centre_height_m": 0.8},
		"d_no_radius": {"npcs": ["9"], "centre_height_m": 0.8, "reason": "test"},
		"e_empty": {"npcs": [], "radius_m": 2.0, "centre_height_m": 0.8, "reason": "test"},
	}
	t.presentation["npc"] = npc
	var errs := "\n".join(t.talk_zone_errors())
	assert_true(errs.contains("npc 16 is listed by npc.talk_zones.a_first and npc.talk_zones.b_second"), "a duplicate listing: " + errs)
	assert_true(errs.contains("c_no_reason needs a reason"), "a missing reason: " + errs)
	assert_true(errs.contains("d_no_radius needs a positive radius_m"), "a missing radius: " + errs)
	assert_true(errs.contains("e_empty lists no npcs"), "an empty profile: " + errs)
	assert_eq(String(t.talk_zone("16").profile), "a_first", "the first profile by name wins")
	assert_near(float(t.talk_zone("20").radius_m), 3.0, 1e-6, "a profile's own radius")


func test_world_npc_builds_its_sphere_from_the_zone() -> void:
	# Outside the tree: setup() only assigns transforms and builds children (the runner is still in _ready).
	var pl := NpcPlacement.new()
	pl.npc_id = "20"
	pl.npc_name = "Sid"
	pl.map_id = "000001011"
	pl.transform = Transform3D(Basis.IDENTITY, Vector3(2808.6, 0.45, 1.75))
	var t := tuning()
	var z := t.talk_zone("20")
	var n := WorldNpc.new()
	n.setup(pl, null, float(z.radius_m), float(z.centre_height_m), String(z.profile))
	var cs := _sphere_of(n)
	assert_true(cs != null, "the TalkArea has a sphere")
	if cs != null:
		assert_near((cs.shape as SphereShape3D).radius, float(z.radius_m), 1e-6, "the sphere's radius is the zone's")
		assert_near(cs.position.y, float(z.centre_height_m), 1e-6, "centred centre_height_m above the feet, not half the radius")
	assert_eq(n.talk_profile, "across_counter", "the node keeps its profile")
	assert_near(n.talk_radius_m, float(z.radius_m), 1e-6, "talk_radius_m")
	n.free()
	# Without a centre height the old rule stands: half the radius.
	var old := WorldNpc.new()
	old.setup(pl, null, 1.6)
	var cs2 := _sphere_of(old)
	if cs2 != null:
		assert_near(cs2.position.y, 0.8, 1e-6, "NAN centre height: half the radius")
	assert_eq(old.talk_profile, "default", "no profile given")
	old.free()


static func _sphere_of(n: WorldNpc) -> CollisionShape3D:
	if n.talk_area == null:
		return null
	for c in n.talk_area.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is SphereShape3D:
			return c
	return null
