extends TestCase
## DropRoller over the canonical records (contracts C1 and C2): deterministic with a seeded RNG, only rolling entries
## drop, unresolved members never do, quest-gated entries roll only while their quest is in progress (and never
## without a context), meso bags carry a uniform integer amount from the record, and rolled drops become ground
## records the character can pick up.


func parity_keys() -> Dictionary:
	return {
		"test_same_seed_same_drops": ["mechanic:drop-roll-seeded"],
		"test_unresolved_members_never_drop": ["mechanic:unresolved-drops-never-roll", "drop:0000001/egg", "drop:9/omok-piece-mushroom"],
		"test_quest_gate_board_and_screw_need_pios_quest": ["quest:1012", "drop:0000001/old-wooden-board", "drop:0000001/rusty-screw",
			"mechanic:quest-gated-drops"],
		"test_tutorial_sentinel_always_drops_its_shellpiece": ["quest:1005", "drop:1/jr-sentinel-shellpiece"],
		"test_meso_amounts_come_from_the_record": ["mechanic:meso-amount-source", "drop:2/mesos"],
		"test_wooden_box_never_drops_mesos": ["breakable:0000001"],
	}


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## Pio's quest (1012) in progress: the Wooden Box's Board and Screw may roll.
func _pio() -> Dictionary:
	return {"quests_in_progress": PackedStringArray(["1012"])}


func test_same_seed_same_drops() -> void:
	for owner_id in db().ids("drops"):
		for ctx in [{}, _pio()]:
			var a: Array = []
			var b: Array = []
			var ra := _rng(1234)
			var rb := _rng(1234)
			for i in 200:
				a.append(DropRoller.roll(owner_id, db(), ra, ctx))
				b.append(DropRoller.roll(owner_id, db(), rb, ctx))
			assert_eq(a, b, "owner %s ctx %s" % [owner_id, str(ctx)])


func test_different_seeds_differ() -> void:
	var a := DropRoller.simulate("3", 500, db(), _rng(1))
	var b := DropRoller.simulate("3", 500, db(), _rng(2))
	assert_ne(a, b)


func test_roll_shape_and_membership() -> void:
	var rng := _rng(99)
	for owner_id in db().ids("drops"):
		var rolling := {}
		for e in DropRates.effective_entries(owner_id, db()):
			if DropRates.may_roll(e, PackedStringArray(["1012"])):
				rolling[e.item_id] = e
		var rule := DropRates.meso_rule(owner_id, db())
		for i in 300:
			for d in DropRoller.roll(owner_id, db(), rng, _pio()):
				if d.kind == "mesos":
					assert_true(float(rule.chance) > 0.0, "%s drops mesos only with a resolved meso rule" % owner_id)
					assert_between(float(d.amount), float(rule.min), float(rule.max), "%s mesos" % owner_id)
				else:
					assert_eq(d.kind, "item")
					assert_true(rolling.has(d.item_id), "%s dropped %s, which is not a rolling entry" % [owner_id, d.item_id])
					var e: Dictionary = rolling.get(d.item_id, {"min_quantity": 1, "max_quantity": 1})
					assert_between(float(d.qty), float(e.min_quantity), float(e.max_quantity), "%s qty" % d.item_id)


func test_unresolved_members_never_drop() -> void:
	var never := {}
	for owner_id in db().ids("drops"):
		for e in DropRates.effective_entries(owner_id, db()):
			if e.excluded != "" and e.item_id != "":
				never["%s/%s" % [owner_id, e.item_id]] = true
	assert_true(never.has("0000001/237"), "Egg: no KuroDB value for reactor 2001")
	assert_true(never.has("9/177"), "Shoes Jump scroll: KuroDB row not confirmed (D3-8)")
	assert_true(never.has("2/273"), "Blue Potion: no KuroDB row on the Snail page")
	var rng := _rng(8)
	for owner_id in db().ids("drops"):
		var sim := DropRoller.simulate(owner_id, 3000, db(), rng, _pio())
		for item_id in sim.items:
			assert_false(never.has("%s/%s" % [owner_id, item_id]), "%s dropped the unresolved %s" % [owner_id, item_id])
	# Omok Piece : Mushroom has a KuroDB chance (1%) but no item: excluded, never a roll.
	for e in DropRates.effective_entries("9", db()):
		if e.key == "omok-piece-mushroom":
			assert_eq([e.item_id, e.excluded, e.chance], ["", DropRates.UNRESOLVED_ITEM, 0.0])
	assert_eq(DropRates.unresolved("9", db()).filter(func(u: Dictionary) -> bool: return u.key == "omok-piece-mushroom").size(), 1)


func test_quest_gate_board_and_screw_need_pios_quest() -> void:
	var without := DropRoller.simulate("0000001", 400, db(), _rng(3))
	assert_false((without.items as Dictionary).has("441") or (without.items as Dictionary).has("442"), "no context: gated entries never roll")
	var other := DropRoller.simulate("0000001", 400, db(), _rng(3), {"quests_in_progress": PackedStringArray(["1011"])})
	assert_false((other.items as Dictionary).has("441"), "another quest in progress does not open the gate")
	var with_pio := DropRoller.simulate("0000001", 400, db(), _rng(3), _pio())
	assert_eq(int(with_pio.item_drops.get("441", 0)), 400, "Chance value 1 = every box while 1012 is in progress")
	assert_eq(int(with_pio.item_drops.get("442", 0)), 400)
	# A gated entry costs its roll either way, so the ungated Apple rolls identically with and without the quest.
	assert_eq(int(without.item_drops.get("236", 0)), int(with_pio.item_drops.get("236", 0)), "Apple unaffected by the gate")
	# The character's quest log is the context (contract C2).
	var c := CharacterState.new()
	assert_eq(DropRoller.context_for(c), {"quests_in_progress": PackedStringArray()})
	c.quests.start("1012", 0.0)
	assert_eq(DropRoller.context_for(c).quests_in_progress, PackedStringArray(["1012"]))
	assert_eq(DropRoller.context_for(null), {})
	var drops := DropRoller.roll("0000001", db(), _rng(1), DropRoller.context_for(c))
	var ids := drops.map(func(d: Dictionary) -> String: return String(d.get("item_id", "")))
	assert_has(ids, "441")
	assert_has(ids, "442")


func test_debug_drops_command_takes_a_breakable_owner_and_the_characters_quests() -> void:
	# The console's "drops <owner id> [kills] [seed]" on the Wooden Box: the owner id is used as is, the character's
	# quests in progress are the context, and unresolved members are listed with their reason.
	var h := DebugHarness.create(db())
	var before := h.run("drops 0000001 300")
	assert_true(before.begins_with("Wooden Box (0000001), 300 kills, seed 1, quests in progress []"), before)
	assert_true(before.contains("mesos: none (no_mesos)"), before)
	assert_true(before.contains("442 Old Wooden Board x0 (0 kills") and before.contains("gated to quest 1012 (not in progress)"), before)
	assert_true(before.contains("237 Egg: never rolls (%s)" % DropRates.UNRESOLVED_CHANCE), before)
	h.game.character.quests.start("1012", 0.0)
	var during := h.run("drops 0000001 300")
	assert_true(during.contains("quests in progress [1012]"), during)
	assert_true(during.contains("442 Old Wooden Board x300 (300 kills, 100.0000%; configured 100.0000%"), during)
	assert_false(during.contains("(not in progress)"), during)
	h.free_all()


func test_tutorial_sentinel_always_drops_its_shellpiece() -> void:
	# KuroDB "100.00% base | Qty 1 | Quest 1035" with no gate (C1 rule: 347 is MeowDB subtype Monster Drop): every kill,
	# with or without Todd's quest.
	for ctx in [{}, {"quests_in_progress": PackedStringArray(["1005"])}]:
		var rng := _rng(5)
		for i in 100:
			var drops := DropRoller.roll("1", db(), rng, ctx)
			var ids := drops.filter(func(d: Dictionary) -> bool: return d.kind == "item").map(func(d: Dictionary) -> String: return d.item_id)
			assert_eq(ids, ["347"], "kill %d" % i)
			assert_false(drops.any(func(d: Dictionary) -> bool: return d.kind == "mesos"), "no meso row on KuroDB's Sentinel page")


func test_meso_amounts_come_from_the_record() -> void:
	for owner_id in ["2", "3", "4", "5", "9"]:
		var meso: Dictionary = db().drop_table(owner_id).meso
		var rng := _rng(11)
		var seen := {}
		for i in 600:
			for d in DropRoller.roll(owner_id, db(), rng):
				if d.kind == "mesos":
					seen[int(d.amount)] = true
					assert_between(float(d.amount), float(meso.min), float(meso.max), "drops/%s amount" % owner_id)
		for amount in range(int(meso.min), int(meso.max) + 1):
			assert_true(seen.has(amount), "drops/%s: every integer in [%d, %d] occurs (saw %s)" % [owner_id, int(meso.min), int(meso.max), str(seen.keys())])


func test_wooden_box_never_drops_mesos() -> void:
	var sim := DropRoller.simulate("0000001", 500, db(), _rng(3), _pio())
	assert_eq(sim.meso_drops, 0)


func test_unknown_owner_drops_nothing() -> void:
	assert_eq(DropRoller.roll("no-such-monster", db(), _rng(1)), [])


func test_a_v1_table_supplies_no_chance() -> void:
	# Nothing outside a v2 record supplies a chance (C1): an old-style table rolls nothing.
	var c := ContentDB.new()
	c.canonical = db().canonical.duplicate()
	c.canonical["drops"] = (db().canonical["drops"] as Dictionary).duplicate()
	var old: Dictionary = (db().drop_table("2")).duplicate(true)
	old.erase("schema_version")
	c.canonical["drops"]["2"] = old
	c.miso = db().miso
	c.loaded = true
	assert_eq(DropRoller.simulate("2", 300, c, _rng(4)).items, {})
	assert_eq(DropRates.meso_rule("2", c).chance, 0.0)
	assert_true(DropRates.effective_entries("2", c).all(func(r: Dictionary) -> bool: return r.excluded == DropRates.NOT_V2))
	assert_true(DropRecordChecks.is_v2(db().drop_table("2")), "shared db untouched")


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
	assert_true(mesos > 0 and int(items.get("348", 0)) == 50, "50 Snails: a shell each, and some meso bags")


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


## DropRates.rolls_item: what a check of real drops may accept. A rolling member counts; a member the sources leave
## unresolved (it is on the record but never rolls) does not; a gated member counts only under a context with its quest.
## The in-game monster check (monster_game_checks.gd _in_table) uses it, so it no longer passes a member that never
## rolls.
func test_rolls_item_counts_rolling_members_only() -> void:
	var checks: GDScript = load("res://scripts/actors/monsters/monster_game_checks.gd")
	assert_true(DropRates.rolls_item("2", "348", db()), "the Snail Shell rolls on every Snail")
	var never := ""
	for row: Dictionary in DropRates.effective_entries("2", db()):
		if String(row.excluded) != "" and String(row.item_id) != "" and not DropRates.rolls_item("2", String(row.item_id), db()):
			never = String(row.item_id)
			break
	assert_ne(never, "", "the Snail's record has a member with a local item that never rolls")
	assert_false(DropRates.rolls_item("2", never, db()), "an unresolved member is not a drop")
	assert_false(DropRates.rolls_item("0000001", "441", db()), "the Board is gated: no context, no drop")
	assert_false(DropRates.rolls_item("0000001", "441", db(), {"quests_in_progress": PackedStringArray(["1000"])}),
		"another quest does not open the gate")
	assert_true(DropRates.rolls_item("0000001", "441", db(), _pio()), "rolls while Pio's quest is in progress")
	assert_false(DropRates.rolls_item("no-such-owner", "348", db()))
	assert_false(DropRates.rolls_item("2", "", db()))
	# Every drop the roller produces passes.
	var rng := _rng(5)
	for k in 200:
		for d: Dictionary in DropRoller.roll("2", db(), rng):
			if String(d.kind) == "item":
				assert_true(DropRates.rolls_item("2", String(d.item_id), db()), "rolled %s" % d.item_id)
	# The game check agrees.
	var killed := [["2", "000000040"], ["3", "000000040"]]
	assert_true(bool(checks.call("_in_table", db(), killed, "348")))
	assert_false(bool(checks.call("_in_table", db(), killed, never)), "the game check refuses a member that never rolls")
	assert_false(bool(checks.call("_in_table", db(), [["0000001", "000001010"]], "441")), "nor a gated one outside its quest")
	assert_true(bool(checks.call("_in_table", db(), [["0000001", "000001010"]], "441", _pio())))
