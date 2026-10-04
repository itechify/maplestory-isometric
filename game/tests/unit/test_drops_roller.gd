extends TestCase
## DropRoller: deterministic with a seeded RNG, frequencies match the resolved placeholder rates, meso drops, the
## breakable, and handing rolled drops to ItemService.pickup.


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func test_same_seed_same_drops() -> void:
	for owner_id in db().ids("drops"):
		var a: Array = []
		var b: Array = []
		var ra := _rng(1234)
		var rb := _rng(1234)
		for i in 200:
			a.append(DropRoller.roll(owner_id, db(), ra))
			b.append(DropRoller.roll(owner_id, db(), rb))
		assert_eq(a, b, "owner %s" % owner_id)


func test_different_seeds_differ() -> void:
	var a := DropRoller.simulate("3", 500, db(), _rng(1))
	var b := DropRoller.simulate("3", 500, db(), _rng(2))
	assert_ne(a, b)


func test_roll_shape_and_membership() -> void:
	var rng := _rng(99)
	for owner_id in db().ids("drops"):
		var listed := {}
		for e in DropRates.effective_entries(owner_id, db()):
			if float(e.chance) > 0.0:
				listed[e.item_id] = e
		for i in 300:
			for d in DropRoller.roll(owner_id, db(), rng):
				if d.kind == "mesos":
					var rule := DropRates.meso_rule(owner_id, db())
					assert_between(float(d.amount), float(rule.min), float(rule.max), "%s mesos" % owner_id)
				else:
					assert_eq(d.kind, "item")
					assert_true(listed.has(d.item_id), "%s dropped %s, which is not an eligible entry" % [owner_id, d.item_id])
					var e: Dictionary = listed.get(d.item_id, {"min_quantity": 1, "max_quantity": 1})
					assert_between(float(d.qty), float(e.min_quantity), float(e.max_quantity), "%s qty" % d.item_id)


func test_frequencies_match_resolved_rates() -> void:
	var kills := 20000
	var sim := DropRoller.simulate("3", kills, db(), _rng(7))
	for e in DropRates.effective_entries("3", db()):
		var observed := float(sim.item_drops.get(e.item_id, 0)) / kills
		var p := float(e.chance)
		var tolerance := 4.0 * sqrt(maxf(p * (1.0 - p), 1e-9) / kills) + 1e-9
		assert_near(observed, p, tolerance, "Blue Snail %s" % e.item_id)
	var meso_rule := DropRates.meso_rule("3", db())
	assert_near(float(sim.meso_drops) / kills, float(meso_rule.chance), 0.02, "meso drop rate")


func test_tutorial_sentinel_always_drops_its_shellpiece() -> void:
	var rng := _rng(5)
	for i in 100:
		var drops := DropRoller.roll("1", db(), rng)
		var ids := drops.filter(func(d: Dictionary) -> bool: return d.kind == "item").map(func(d: Dictionary) -> String: return d.item_id)
		assert_has(ids, "347", "kill %d" % i)


func test_snail_mesos_follow_the_player_report() -> void:
	var meso: Dictionary = db().drop_table("2").meso
	var rng := _rng(11)
	var seen := 0
	for i in 500:
		for d in DropRoller.roll("2", db(), rng):
			if d.kind == "mesos":
				seen += 1
				assert_between(float(d.amount), float(meso.median_min), float(meso.median_max))
	assert_true(seen > 0, "Snails drop mesos")


func test_wooden_box_never_drops_mesos() -> void:
	var sim := DropRoller.simulate("0000001", 500, db(), _rng(3))
	assert_eq(sim.meso_drops, 0)
	assert_true((sim.items as Dictionary).has("441") and (sim.items as Dictionary).has("442"), "box quest items drop")


func test_unknown_owner_drops_nothing() -> void:
	assert_eq(DropRoller.roll("no-such-monster", db(), _rng(1)), [])


func test_global_multiplier_zero_stops_item_drops() -> void:
	var d := ContentDB.new()
	d.canonical = db().canonical
	d.miso = db().miso.duplicate()
	var singles: Dictionary = (db().miso[""] as Dictionary).duplicate()
	var rates: Dictionary = (singles["drop_rates"] as Dictionary).duplicate(true)
	rates["global_rate_multiplier"] = 0.0
	rates["owner_item_overrides"] = {}
	singles["drop_rates"] = rates
	d.miso[""] = singles
	d.loaded = true
	var sim := DropRoller.simulate("2", 300, d, _rng(4))
	assert_eq((sim.items as Dictionary).size(), 0)
	assert_true(int(sim.meso_drops) > 0, "the item multiplier does not touch mesos")
	assert_eq(float(db().miso_table("drop_rates").global_rate_multiplier), 1.0, "shared db untouched")


func test_rolled_drops_can_be_picked_up() -> void:
	var c := CharacterState.new()
	var s := ItemService.new(c, db())
	var rng := _rng(21)
	var mesos := 0
	var items := {}
	for i in 50:
		for drop in DropRoller.roll("2", db(), rng):
			assert_true(s.pickup(drop).ok, str(drop))
			if drop.kind == "mesos":
				mesos += int(drop.amount)
			else:
				items[drop.item_id] = int(items.get(drop.item_id, 0)) + int(drop.qty)
	assert_eq(c.mesos, mesos)
	for id in items:
		assert_eq(c.inventory.count(id), items[id], id)
	assert_true(mesos > 0 and not items.is_empty(), "50 Snails dropped something")


func test_ground_records_carry_lifetime_owner_and_scatter() -> void:
	var drops := [{"kind": "mesos", "amount": 4}, {"kind": "item", "item_id": "348", "qty": 1},
		{"kind": "item", "item_id": "270", "qty": 2}, {"kind": "item", "item_id": "541", "qty": 1}]
	var now := 50.0
	var recs := DropRoller.ground_records(drops, now, "player", db())
	assert_eq(recs.size(), drops.size())
	var spacing := DropRates.scatter_spacing_px(db())
	var expected_px := [0.0, spacing, -spacing, 2.0 * spacing]
	for i in recs.size():
		var r: Dictionary = recs[i]
		assert_near(float(r.expires_at), now + DropRates.ground_lifetime_s(db()), 1e-9, "expires_at %d" % i)
		assert_near(float(r.free_at), now + DropRates.owner_exclusive_s(db()), 1e-9, "free_at %d" % i)
		assert_eq(r.owner, "player")
		assert_near(float(r.offset_px), float(expected_px[i]), 1e-9, "alternating scatter %d" % i)
		assert_near(float(r.offset_m), WorldScale.h(float(expected_px[i])), 1e-9, "scatter in meters %d" % i)
	assert_eq([recs[0].kind, recs[0].mesos, recs[0].amount], ["mesos", 4, 4])
	assert_eq([recs[2].kind, recs[2].item_id, recs[2].amount], ["item", "270", 2])
	# The records go straight into MapInstanceState and back out to ItemService.pickup.
	var c := CharacterState.new()
	var s := ItemService.new(c, db())
	for r in recs:
		assert_true(s.pickup(r).ok, str(r))
	assert_eq(c.mesos, 4)
	assert_eq(c.inventory.count("270"), 2)


func test_ownership_window() -> void:
	var rec: Dictionary = DropRoller.ground_records([{"kind": "item", "item_id": "348", "qty": 1}], 10.0, "player",
		db())[0]
	var free_at := float(rec.free_at)
	assert_true(DropRoller.may_pick_up(rec, "player", 10.0), "owner at once")
	if DropRates.owner_exclusive_s(db()) > 0.0:
		assert_false(DropRoller.may_pick_up(rec, "someone-else", 10.0), "others wait")
	assert_true(DropRoller.may_pick_up(rec, "someone-else", free_at), "free for all afterwards")
	assert_true(DropRoller.may_pick_up({"item_id": "348"}, "anyone", 0.0), "a record without an owner is free")


func test_pickup_box_is_canonical_and_converted_through_world_scale() -> void:
	var canon: Dictionary = db().formula("loot_rules").player_pickup_box_px
	var px := DropRates.pickup_box_px(db())
	var m := DropRates.pickup_box_m(db())
	for k in ["left", "right", "above", "below"]:
		assert_eq(float(px[k]), float(canon[k]), "px %s" % k)
		assert_near(float(m[k]), WorldScale.actor(float(canon[k])), 1e-9, "m %s" % k)
		assert_true(float(m[k]) > 0.0, k)
