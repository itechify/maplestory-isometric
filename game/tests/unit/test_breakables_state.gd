extends TestCase
## The Wooden Box's pure rules and state (contract C8): the canonical record against the live MeowDB capture, one
## intact entry per canonical placement in MapInstanceState, 4 landed hits break a box, a broken box comes back
## exactly its placement's respawn_s later on the game clock, the state rides the map snapshot, and the box's body
## (breakables.json box.touch_px) is reachable by the real basic attacks (bare hands, the Wooden Club).

const BOX := "0000001"
## The six maps with Wooden Box placements (canonical maps/<id>.json reactors[]).
const BOX_MAPS := ["000001000", "000001010", "000001011", "000001012", "000001013", "000001014"]
const CAPTURE := "tools/meowdb/captures/breakable_0000001.txt"


func parity_keys() -> Dictionary:
	return {
		"test_canonical_box_matches_the_live_capture": ["breakable:0000001", "breakable-placement:000001000",
			"breakable-placement:000001010", "breakable-placement:000001011", "breakable-placement:000001012",
			"breakable-placement:000001013", "breakable-placement:000001014"],
		"test_fresh_has_one_intact_box_per_canonical_placement": ["breakable:0000001", "breakable-placement:000001000",
			"breakable-placement:000001010", "breakable-placement:000001011", "breakable-placement:000001012",
			"breakable-placement:000001013", "breakable-placement:000001014"],
		"test_three_hits_do_not_break_and_the_fourth_does": ["breakable:0000001", "mechanic:breakable-hit-break-respawn"],
		"test_a_broken_box_comes_back_exactly_after_its_respawn_s": ["mechanic:breakable-hit-break-respawn"],
		"test_the_snapshot_keeps_hits_and_broken_boxes": ["mechanic:breakable-hit-break-respawn"],
	}


func model() -> SpawnModel:
	return SpawnModel.from_db(db())


func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func fresh(map_id: String, defs: MapDefinitions = null) -> MapInstanceState:
	var d := defs if defs != null else MapDefinitions.build(db())
	return MapInstanceState.fresh(d.get_def(map_id), model(), rng(1), 0.0)


func hits() -> int:
	return BreakableRules.hits_to_break(BOX, db())


## The MeowDB breakable page as read by hand on 2026-10-05 (tools/meowdb/captures), mirrored next to the project.
func _capture_text() -> String:
	var path := ProjectSettings.globalize_path("res://").path_join("..").simplify_path().path_join(CAPTURE)
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func test_canonical_box_matches_the_live_capture() -> void:
	var rec := BreakableRules.record(BOX, db())
	assert_eq(String(rec.get("name", "")), "Wooden Box", "canonical breakable 0000001")
	var text := _capture_text()
	if text == "":
		print("SKIP capture check: %s is not next to the project" % CAPTURE)
	else:
		var m := RegEx.create_from_string("breaks in (\\d+) hits").search(text)
		assert_true(m != null and int(m.get_string(1)) == hits(), "capture 'breaks in N hits' == canonical hits_to_break %d" % hits())
		# Per map: "<map name>\nRainbow Street\n×<count> · <respawn>s".
		for map_id in BOX_MAPS:
			var name := String(db().map(map_id).get("name", ""))
			var row := RegEx.create_from_string("%s\\nRainbow Street\\n×(\\d+) · (\\d+)s" % name).search(text)
			assert_true(row != null, "%s (%s) listed on the live page" % [map_id, name])
			if row != null:
				assert_eq(int(row.get_string(1)), BreakableRules.placements_of(db().map(map_id)).size(), "%s count" % map_id)
		for item in ["Old Wooden Board", "Rusty Screw", "Apple", "Egg"]:
			assert_true(("\n%s\n" % item) in text, "the live page lists %s" % item)
	assert_eq(hits(), 4, "canonical hits_to_break")
	# The 19 placements: the map pages' reactors[] (placement order) and the breakable record's placements[] agree.
	var total := 0
	for map_id in BOX_MAPS:
		var mine := BreakableRules.placements_of(db().map(map_id))
		total += mine.size()
		var from_map: Array = []
		for p in mine:
			assert_eq(String(p.id), BOX, "%s reactor %d is the Wooden Box" % [map_id, int(p.index)])
			from_map.append("%s,%s,%d" % [p.x_px, p.y_px, int(p.respawn_s)])
		var from_rec: Array = []
		for p: Dictionary in rec.get("placements", []):
			if String(p.get("map_id", "")) == map_id:
				from_rec.append("%s,%s,%d" % [p.get("x_px"), p.get("y_px"), int(p.get("respawn_s", 0))])
		from_map.sort()
		from_rec.sort()
		assert_eq(from_map, from_rec, "%s: the map page and the breakable record list the same placements" % map_id)
	assert_eq(total, 19, "19 Wooden Box placements on Maple Island")
	var respawns: Array = []
	for p in BreakableRules.placements_of(db().map("000001000")):
		respawns.append(int(p.respawn_s))
	assert_eq(respawns, [120, 120, 120, 180, 90], "000001000 per-placement respawn_s in reactors[] order")


func test_fresh_has_one_intact_box_per_canonical_placement() -> void:
	var defs := MapDefinitions.build(db())
	for map_id in BOX_MAPS:
		var st := fresh(map_id, defs)
		var placements := BreakableRules.placements_of(db().map(map_id))
		assert_eq(st.breakable_count(), placements.size(), "%s boxes" % map_id)
		for p in placements:
			var i := int(p.index)
			assert_true(st.is_breakable_intact(i), "%s box %d intact" % [map_id, i])
			assert_eq(st.breakable_hits(i), 0, "%s box %d no hits" % [map_id, i])
			assert_eq(float(st.breakables[i].respawn_s), float(p.respawn_s), "%s box %d respawn_s" % [map_id, i])
			assert_eq(String(st.breakables[i].id), BOX, "%s box %d id" % [map_id, i])
	assert_eq(fresh("000000040", defs).breakable_count(), 0, "a map without reactors has no boxes")
	assert_eq(MapInstanceState.fresh_for("m", [0.0] as Array[float], model(), rng(1), 0.0).breakable_count(), 0,
		"fresh_for without a definition has no boxes")


func test_three_hits_do_not_break_and_the_fourth_does() -> void:
	var st := fresh("000001010")
	var n := hits()
	for k in n - 1:
		var r := st.hit_breakable(2, 5.0 + k, n)
		assert_true(bool(r.counted) and not bool(r.broke), "hit %d counts and does not break" % (k + 1))
		assert_eq(int(r.hits), k + 1, "hit count")
	assert_true(st.is_breakable_intact(2), "still standing after %d hits" % (n - 1))
	var last := st.hit_breakable(2, 9.0, n)
	assert_true(bool(last.counted) and bool(last.broke), "hit %d breaks it" % n)
	assert_false(st.is_breakable_intact(2), "broken")
	var after := st.hit_breakable(2, 9.5, n)
	assert_false(bool(after.counted), "a broken box takes no hits")
	for other in st.breakable_count():
		if other != 2:
			assert_true(st.is_breakable_intact(other) and st.breakable_hits(other) == 0, "box %d untouched" % other)
	assert_false(bool(st.hit_breakable(-1, 10.0, n).counted), "index -1 is no placement")
	assert_false(bool(st.hit_breakable(st.breakable_count(), 10.0, n).counted), "out of range")
	assert_false(bool(st.hit_breakable(0, 10.0, 0).counted), "no canonical hit count, no hit")
	assert_false(st.is_breakable_intact(-1), "index -1 is never intact")


func test_a_broken_box_comes_back_exactly_after_its_respawn_s() -> void:
	var st := fresh("000001000")
	var n := hits()
	var t0 := 50.0
	# 000001000 reactors[3] respawns after 180 s and reactors[4] after 90 s (per placement, not on the spawn tick).
	for idx in [3, 4]:
		for k in n:
			st.hit_breakable(idx, t0, n)
		assert_false(st.is_breakable_intact(idx), "box %d broken at %.0f" % [idx, t0])
	var r3 := float(st.breakables[3].respawn_s)
	var r4 := float(st.breakables[4].respawn_s)
	assert_eq([r3, r4], [180.0, 90.0], "canonical per-placement respawn_s")
	assert_near(st.breakable_respawn_at(4), t0 + r4, 1e-9, "respawn_at = break + respawn_s")
	assert_eq(st.tick_breakables(t0 + r4 - 0.01).size(), 0, "not before its respawn_s")
	assert_eq(st.tick_breakables(t0 + r4), PackedInt32Array([4]), "box 4 back at exactly break + 90 s")
	assert_true(st.is_breakable_intact(4) and st.breakable_hits(4) == 0, "back intact with no hits")
	assert_false(st.is_breakable_intact(3), "box 3 still broken")
	assert_eq(st.tick_breakables(t0 + r3), PackedInt32Array([3]), "box 3 back at exactly break + 180 s")
	# A hit after the respawn time counts on the returned box even without a tick in between.
	for k in n:
		st.hit_breakable(0, 300.0, n)
	assert_true(bool(st.hit_breakable(0, 300.0 + float(st.breakables[0].respawn_s), n).counted), "a hit at the respawn time counts")


func test_the_snapshot_keeps_hits_and_broken_boxes() -> void:
	var st := fresh("000001014")
	var n := hits()
	st.hit_breakable(0, 1.0, n)
	st.hit_breakable(0, 1.5, n)
	for k in n:
		st.hit_breakable(1, 2.0, n)
	var cache := MapStateCache.new()
	cache.put("000001014", st.snapshot(3.0))
	var back := MapInstanceState.from_snapshot(cache.take("000001014"), model(), 60.0)
	assert_eq(back.breakable_count(), 3, "every placement rides the snapshot")
	assert_eq(back.breakable_hits(0), 2, "partial hits kept")
	assert_false(back.is_breakable_intact(1), "a broken box stays broken while parked")
	assert_near(back.breakable_respawn_at(1), st.breakable_respawn_at(1), 1e-9, "same respawn time")
	assert_true(back.is_breakable_intact(2), "untouched box intact")
	var later := MapInstanceState.from_snapshot(st.snapshot(3.0), model(), 2.0 + float(st.breakables[1].respawn_s))
	assert_true(later.is_breakable_intact(1), "restored after its respawn time: back at once")


func test_rules_and_adaptation_values() -> void:
	var px := BreakableRules.touch_px(db())
	assert_true(px.x > 0.0 and px.y > 0.0, "breakables.json box.touch_px is set")
	assert_near(BreakableRules.size_m(db()).y, WorldScale.actor(px.y), 1e-9, "size through WorldScale.actor")
	assert_eq(BreakableRules.placement_key("000001010", 3), "000001010:3", "placement key")
	assert_eq(BreakableRules.hits_to_break("nope", db()), 0, "unknown breakable: no rule")
	var c := CharacterState.new()
	assert_eq(BreakableRules.drop_context(c), {"quests_in_progress": PackedStringArray()}, "no quests")
	c.quests.start("1012", 0.0)
	var ctx := BreakableRules.drop_context(c)
	assert_eq(typeof(ctx["quests_in_progress"]), TYPE_PACKED_STRING_ARRAY, "C2: a PackedStringArray")
	assert_eq(ctx["quests_in_progress"], PackedStringArray(["1012"]), "C2: the in-progress quest ids")
	assert_eq(BreakableRules.drop_context(null), {"quests_in_progress": PackedStringArray()}, "no character")
	# The declared rules are the ones the runtime implements: boxes_per_attack is read (the MeleeQuery cap), one hit is
	# counted per landed attack (MapInstanceState.hit_breakable) and respawn is exactly respawn_s, never tick-aligned.
	assert_eq(BreakableRules.boxes_per_attack(db()), 1, "hit_rule.boxes_per_attack")
	assert_eq(BreakableRules.section(db(), "hit_rule").get("hits_per_landed_attack", null), 1,
		"hit_rule.hits_per_landed_attack: the runtime counts exactly one hit per landed attack")
	assert_eq(BreakableRules.section(db(), "respawn").get("align_to_spawn_tick", null), false,
		"respawn.align_to_spawn_tick: the runtime brings a box back exactly respawn_s after the break")
	for section in ["box", "hit_rule", "respawn", "placement"]:
		assert_false(BreakableRules.section(db(), section).is_empty(), "breakables.json %s" % section)
		assert_true(String(BreakableRules.section(db(), section).get("reason", "")) != "", "%s has a reason" % section)
		assert_eq(BreakableRules.section(db(), section).get("verified", null), false, "%s is an unverified adaptation" % section)


## The real basic attacks reach the box from a step away: for bare hands and the Wooden Club (the beginner weapon the
## box playtest uses), every ordinary presentation hits a box standing on the same ground somewhere between 0.2 and
## 1.5 m in front, and at least one hits it at 0.8 m.
func test_the_box_is_within_reach_of_the_basic_attacks() -> void:
	var px := BreakableRules.touch_px(db())
	var depth := CombatReach.attack_box_depth_px(db())
	for weapon in [WeaponProfile.bare_hands(db()), WeaponProfile.for_weapon_id("585", db())]:
		var w: WeaponProfile = weapon
		var at_08 := false
		for action: Variant in w.ordinary_actions().keys():
			for pres in w.presentations_for(String(action)):
				var box := CombatReach.attack_box_px(w, pres, true, 1)
				var some := false
				for k in 14:
					var d := 0.2 + 0.1 * k
					var rel := MeleeQuery.local_px(Vector3.ZERO, Vector3.RIGHT, Vector3(d, 0.0, 0.0))
					if MeleeQuery.attack_hits(box, depth, rel, px, px.x):
						some = true
						if is_equal_approx(d, 0.8):
							at_08 = true
				assert_true(some, "%s %s reaches the box from 0.2-1.5 m" % [w.name, pres])
		assert_true(at_08, "%s: a basic attack reaches the box at 0.8 m" % w.name)
