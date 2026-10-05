extends TestCase
## LootVisuals (data/misostory/loot_visuals.json) and the GroundDrop animation: one procedural shape per item family,
## meso art by amount, every drop-table item buildable, toss arc / hover / blink driven by the table.


func vis() -> LootVisuals:
	return LootVisuals.new(db())


func test_table_is_a_labelled_adaptation() -> void:
	var t: Variant = db().miso_table("loot_visuals")
	assert_true(t is Dictionary, "data/misostory/loot_visuals.json loads")
	assert_eq(t.get("verified"), false, "unverified adaptation")
	assert_false(String(t.get("reason", "")).is_empty(), "top-level reason")
	for section in ["motion", "placement", "pickup", "sizes", "shapes", "colors"]:
		assert_true(t.get(section) is Dictionary, section)
		assert_false(String(t[section].get("reason", "")).is_empty(), section + " reason")
	for key in ["toss_duration_s", "toss_height_m", "blink_before_expiry_s", "blink_hz", "bob_period_s"]:
		assert_true(vis().motion(key) > 0.0, key)


func test_shapes_follow_canonical_type_and_subtype() -> void:
	var v := vis()
	var expect := {"270": "potion", "237": "food", "235": "food", "348": "pouch", "541": "box", "933": "box",
		"320": "gem", "413": "gem", "209": "bundle", "139": "scroll", "522": "chair_box", "441": "pouch"}
	for id: String in expect:
		var rec := db().item(id)
		assert_false(rec.is_empty(), "item %s exists" % id)
		assert_eq(v.style_for_item(id)["shape"], expect[id], "%s (%s/%s)" % [rec.get("name"), rec.get("type"), rec.get("subtype")])
	assert_eq(v.style_for_item("no-such-item")["shape"], "pouch", "unknown ids fall back")


func test_name_keywords_tint_the_body() -> void:
	var v := vis()
	assert_eq(v.style_for_item("270")["body"], Color("#e03a3a"), "Red Potion")
	assert_eq(v.style_for_item("273")["body"], Color("#3f6fe0"), "Blue Potion")
	assert_eq(v.style_for_item("237")["body"], Color("#f3ead2"), "Egg")
	assert_eq(v.style_for_item("349")["body"], Color("#3f6fe0"), "Blue Snail Shell: Blue comes first")


func test_meso_art_changes_with_the_amount() -> void:
	var v := vis()
	assert_eq(v.style_for_mesos(7)["coins"], 1)
	assert_eq(v.style_for_mesos(7)["body"], Color("#c98a3a"), "bronze under 50")
	assert_eq(v.style_for_mesos(60)["body"], Color("#f4c430"), "gold under 100")
	assert_eq(v.style_for_mesos(500)["coins"], 3, "a pile under 1000")
	assert_true(bool(v.style_for_mesos(5000)["bag"]), "a bag from 1000")
	assert_eq(v.style_for_drop({"kind": "mesos", "amount": 12})["shape"], "meso")
	assert_eq(v.style_for_drop({"item_id": "270", "amount": 1})["shape"], "potion")


func test_every_drop_table_item_and_meso_tier_builds_a_model() -> void:
	var v := vis()
	# Every resolved member of a drop record (an unresolved one has item_id null and never drops) and every MeowDB
	# reference item the records name.
	var seen := {}
	for owner in db().ids("drops"):
		var table := db().drop_table(owner)
		var ref: Dictionary = table.get("meowdb_reference", {}) if table.get("meowdb_reference") is Dictionary else {}
		for e: Dictionary in table.get("entries", []) + ref.get("community_drops", []) + ref.get("msea_reference", []):
			if e.get("item_id", null) is String:
				seen[String(e.item_id)] = true
	assert_true(seen.size() > 50, "drop records name items (%d)" % seen.size())
	var drops: Array = []
	for id: String in seen:
		drops.append({"kind": "item", "item_id": id, "qty": 1})
	for amount in [1, 49, 50, 99, 100, 999, 1000, 50000]:
		drops.append({"kind": "mesos", "amount": amount})
	for d: Dictionary in drops:
		var m := v.build_drop_model(d)
		var meshes := m.find_children("*", "MeshInstance3D", true, false)
		assert_true(meshes.size() >= 1, "model for %s" % str(d))
		for mi in meshes:
			assert_true((mi as MeshInstance3D).mesh != null and (mi as MeshInstance3D).material_override != null)
		m.free()


func test_ground_drop_toss_lands_then_hovers_and_bobs() -> void:
	var v := vis()
	var n := GroundDrop.new()
	var rec := {"uid": "a:1", "kind": "item", "item_id": "270", "amount": 1, "expires_at": 1000.0}
	n.setup(rec, v, Vector3(2, 0, 0), Vector3(0, 0.5, 0), true)
	assert_false(n.is_landed(), "tossing")
	var toss := v.motion("toss_duration_s")
	var peak := -INF
	var steps := 30
	for i in steps:
		n.update(0.0, toss / steps)
		peak = maxf(peak, n.model.position.y)
	assert_true(n.is_landed(), "landed after toss_duration_s")
	assert_true(peak > v.motion("hover_m") + v.motion("toss_height_m") * 0.5, "an arc, not a slide (peak %.2f)" % peak)
	assert_near(n.model.position.x, 0.0, 0.01, "ends over the landing point")
	var ys := []
	for i in 20:
		n.update(0.0, v.motion("bob_period_s") / 20.0)
		ys.append(n.model.position.y)
	assert_true(ys.max() - ys.min() > v.motion("bob_amplitude_m"), "bobs")
	assert_near((ys.max() + ys.min()) * 0.5, v.motion("hover_m"), 0.02, "around the hover height")
	n.free()


func test_ground_drop_blinks_only_before_expiry() -> void:
	var v := vis()
	var n := GroundDrop.new()
	n.setup({"uid": "b:1", "kind": "mesos", "amount": 5, "mesos": 5, "expires_at": 100.0}, v, Vector3.ZERO, Vector3.ZERO, false)
	var window := v.motion("blink_before_expiry_s")
	n.update(100.0 - window - 1.0, 0.016)
	assert_true(n.model.visible, "steady before the window")
	var off := 0
	var samples := 40
	for i in samples:
		n.update(100.0 - window * 0.5 + float(i) / (v.motion("blink_hz") * 8.0), 0.016)
		if n.is_blinking_off():
			off += 1
	assert_between(float(off) / samples, 0.3, 0.7, "blinks about half the time")
	n.free()
