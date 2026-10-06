extends TestCase
## Brief Test D as a pure flow: obtain mesos, a consumable and equipment from drops, pick them up, use the
## consumable, equip the equipment, verify the resulting stats, save (JSON), reload, and confirm everything persists.
## Every number is read from canonical data or the rolled drops; nothing is typed in.

const SWORD := "541"       # Sword: on MeowDB's Snail reference list (drops/2.json meowdb_reference), no requirements
const RED_POTION := "270"  # Red Potion: on Snail's canonical drop table


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## Kills Snails (canonical owner "2") with a fixed seed until a meso bag drops, and returns its ground records.
func _snail_meso_records(now: float) -> Array:
	var rng := _rng(42)
	for i in 200:
		var drops := DropRoller.roll("2", db(), rng)
		for d in drops:
			if d.kind == "mesos":
				return DropRoller.ground_records([d], now, "player", db())
	return []


func test_obtain_use_equip_save_reload() -> void:
	var c := CharacterState.new()
	var s := ItemService.new(c, db())
	var now := 100.0
	# Membership is MeowDB's community list (D3-11): the Snail drops both Red Potion and the Sword.
	var snail_items := {}
	for e in db().drop_table("2").entries:
		snail_items[str(e.item_id)] = true
	assert_true(snail_items.has(RED_POTION) and snail_items.has(SWORD), "precondition: Snail records name both")
	# 1. Obtain: a meso bag from a Snail kill, plus a potion and a weapon as ground records (same shape a kill makes).
	var ground := _snail_meso_records(now)
	assert_eq(ground.size(), 1, "a seeded Snail hunt drops mesos")
	ground.append_array(DropRoller.ground_records([{"kind": "item", "item_id": RED_POTION, "qty": 2},
		{"kind": "item", "item_id": SWORD, "qty": 1}], now, "player", db()))
	# 2. Pick everything up.
	var meso_amount := 0
	for rec in ground:
		assert_true(DropRoller.may_pick_up(rec, "player", now), "the killer may take their own drop")
		var res := s.pickup(rec)
		assert_true(res.ok, "%s -> %s" % [rec, res])
		if rec.kind == "mesos":
			meso_amount += int(rec.amount)
	var snail_meso: Dictionary = db().drop_table("2").meso
	assert_between(float(meso_amount), float(snail_meso.min), float(snail_meso.max), "Snail mesos")  # [drops package] C1 meso
	assert_eq(c.mesos, meso_amount)
	assert_eq(c.inventory.count(RED_POTION), 2)
	assert_eq(c.inventory.count(SWORD), 1)
	# 3. Use the consumable.
	c.hp = 1
	var used := s.use_item(RED_POTION)
	assert_true(used.ok, str(used))
	assert_eq(c.hp, mini(1 + int(db().item(RED_POTION).consumable.hp_restore), StatCalculator.max_hp(c, db())))
	assert_eq(c.inventory.count(RED_POTION), 1)
	# 4. Equip the weapon and verify the stats.
	var bare_watk := int(StatCalculator.snapshot(c, db()).watk)
	assert_true(s.equip(SWORD).ok)
	var snap := StatCalculator.snapshot(c, db())
	assert_eq(int(snap.watk), bare_watk + int(db().item(SWORD).stats.watk))
	# 5. Save as JSON, reload, and compare.
	var back := CharacterState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_eq(back.mesos, c.mesos, "mesos persist")
	assert_eq(back.hp, c.hp, "HP persists")
	assert_eq(back.inventory.to_dict(), c.inventory.to_dict(), "inventory persists")
	assert_eq(back.equipment.to_dict(), c.equipment.to_dict(), "equipment persists")
	assert_eq(back.equipment.weapon_id(), SWORD)
	assert_eq(StatCalculator.snapshot(back, db()), snap, "derived stats are identical after reload")
