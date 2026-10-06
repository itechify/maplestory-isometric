extends TestCase
## The large offline simulation (Iteration Three brief, "Drop Testing"): 120,000 seeded kills of every drop owner,
## and each observed rate must sit within a statistical bound of the chance the owner's table configures for the
## member's category and rarity (data/misostory/drop_rates.json, decision D3-11). It only checks that the roller behaves
## as configured; it is never a source of a probability (nothing is read back into the data).
##
## Bound: |observed - p| <= Z * sqrt(p (1 - p) / n) with Z = 5 (a false alarm about once in 1.7 million checks), plus
## exact checks where p is 0 or 1. Meso bags: the bag rate against meso_rules.json's chance (D3-12), and each integer
## amount in [min, max] against the uniform share 1 / (max - min + 1) of the bags.

const KILLS := 120000
const Z := 5.0


func parity_keys() -> Dictionary:
	return {
		"test_every_owner_rolls_as_configured": ["mechanic:drop-simulation", "mechanic:drop-chance-table", "drop:2/snail-shell",
			"drop:3/blue-snail-shell", "drop:4/mushroom-spore", "drop:5/red-snail-shell", "drop:9/orange-mushroom-cap",
			"drop:1/jr-sentinel-shellpiece"],
		"test_wooden_box_with_and_without_pios_quest": ["breakable:0000001", "quest:1012", "mechanic:quest-gated-drops"],
		"test_meso_bags_rate_and_uniform_amounts": ["mechanic:meso-chance-source", "mechanic:meso-amount-source"],
	}


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _bound(p: float, n: int) -> float:
	return Z * sqrt(maxf(p * (1.0 - p), 0.0) / float(n))


## Checks one simulation of `owner_id` under `quests` against DropRates' configured rows.
func _check_items(owner_id: String, sim: Dictionary, quests: PackedStringArray) -> void:
	var n := int(sim.kills)
	var expected := {}
	var table: Dictionary = db().miso_table("drop_rates").chance_table
	for row in DropRates.effective_entries(owner_id, db()):
		if DropRates.may_roll(row, quests):
			expected[row.item_id] = float(row.chance)
			assert_eq(float(row.chance), float(table[row.category][row.rarity]), "drops/%s %s: the table cell" % [owner_id, row.key])
	for item_id in sim.item_drops:
		assert_true(expected.has(item_id), "drops/%s: %s dropped but may not roll here" % [owner_id, item_id])
	for item_id in expected:
		var p: float = expected[item_id]
		var observed := float((sim.item_drops as Dictionary).get(item_id, 0)) / float(n)
		if p >= 1.0:
			assert_eq(int((sim.item_drops as Dictionary).get(item_id, 0)), n, "drops/%s %s: p = 1, every kill" % [owner_id, item_id])
		else:
			assert_near(observed, p, _bound(p, n), "drops/%s %s: observed %.6f vs configured %.6f over %d kills" % [owner_id, item_id, observed, p, n])
		assert_eq(int((sim.items as Dictionary).get(item_id, 0)), int((sim.item_drops as Dictionary).get(item_id, 0)),
			"drops/%s %s: quantity 1 per drop" % [owner_id, item_id])


func test_every_owner_rolls_as_configured() -> void:
	var seed_value := 1000
	for owner_id in db().ids("drops"):
		if DropRates.owner_kind(owner_id, db()) != "monster":
			continue
		seed_value += 1
		var sim := DropRoller.simulate(owner_id, KILLS, db(), _rng(seed_value))
		_check_items(owner_id, sim, PackedStringArray())


func test_wooden_box_with_and_without_pios_quest() -> void:
	var without := DropRoller.simulate("0000001", KILLS, db(), _rng(77))
	_check_items("0000001", without, PackedStringArray())
	assert_false((without.item_drops as Dictionary).has("441") or (without.item_drops as Dictionary).has("442"),
		"Board and Screw never drop outside Pio's quest")
	var quests := PackedStringArray(["1012"])
	var with_pio := DropRoller.simulate("0000001", KILLS, db(), _rng(78), {"quests_in_progress": quests})
	_check_items("0000001", with_pio, quests)
	assert_eq(int(with_pio.meso_drops) + int(without.meso_drops), 0, "a box never drops mesos")
	assert_true((with_pio.items as Dictionary).has("236") and (with_pio.items as Dictionary).has("237"), "Apple and Egg drop at 2%")


func test_meso_bags_rate_and_uniform_amounts() -> void:
	var seed_value := 2000
	for owner_id in ["2", "3", "4", "5", "9"]:
		seed_value += 1
		var rule := DropRates.meso_rule(owner_id, db())
		var sim := DropRoller.simulate(owner_id, KILLS, db(), _rng(seed_value))
		var p := float(rule.chance)
		var bags := int(sim.meso_drops)
		assert_near(p, 0.6, 1e-15, "drops/%s: the meso rule's chance (D3-12)" % owner_id)
		assert_near(float(bags) / float(KILLS), p, _bound(p, KILLS), "drops/%s meso bag rate vs the rule's %s" % [owner_id, str(p)])
		var span := int(rule.max) - int(rule.min) + 1
		var share := 1.0 / float(span)
		var total := 0
		for amount in sim.meso_amounts:
			assert_between(float(amount), float(rule.min), float(rule.max), "drops/%s amount %s inside the rule's range" % [owner_id, str(amount)])
			total += int(sim.meso_amounts[amount]) * int(amount)
		for amount in range(int(rule.min), int(rule.max) + 1):
			var got := float((sim.meso_amounts as Dictionary).get(amount, 0)) / float(bags)
			assert_near(got, share, _bound(share, bags) + 1e-12, "drops/%s amount %d share %.4f vs uniform %.4f" % [owner_id, amount, got, share])
		assert_eq(total, int(sim.mesos), "drops/%s meso total" % owner_id)
	var none := DropRoller.simulate("1", 20000, db(), _rng(9))
	assert_eq(int(none.meso_drops), 0, "the Tutorial Jr. Sentinel drops no mesos")
