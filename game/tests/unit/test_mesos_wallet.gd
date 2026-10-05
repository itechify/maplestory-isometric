extends TestCase
## Mesos: add/spend with validation, never negative, capped per data/misostory/inventory.json, Events.mesos_changed
## through ItemService, and persistence.


func test_add_and_spend() -> void:
	var c := CharacterState.new()
	assert_eq(Mesos.add(c, 120, db()), 120)
	assert_eq(c.mesos, 120)
	var res := Mesos.spend(c, 50)
	assert_true(res.ok)
	assert_eq(res.spent, 50)
	assert_eq(c.mesos, 70)


func test_never_negative() -> void:
	var c := CharacterState.new()
	c.mesos = 30
	var res := Mesos.spend(c, 31)
	assert_eq(res.code, ItemCodes.INSUFFICIENT_MESOS)
	assert_eq(c.mesos, 30, "nothing spent")
	assert_eq(Mesos.spend(c, -5).code, ItemCodes.INVALID_QUANTITY)
	assert_eq(Mesos.add(c, -5, db()), 0)
	assert_eq(c.mesos, 30)
	assert_true(Mesos.spend(c, 30).ok)
	assert_eq(c.mesos, 0)
	assert_true(Mesos.can_afford(c, 0))
	assert_false(Mesos.can_afford(c, 1))


func test_cap_from_adaptation_table() -> void:
	var cap := int(db().miso_table("inventory").meso_cap)
	assert_eq(Mesos.cap(db()), cap)
	var c := CharacterState.new()
	c.mesos = cap - 5
	assert_true(Mesos.can_add(c, 5, db()))
	assert_false(Mesos.can_add(c, 6, db()))
	assert_eq(Mesos.add(c, 100, db()), 5, "adds only up to the cap")
	assert_eq(c.mesos, cap)
	assert_eq(Mesos.add(c, 1, db()), 0)


func test_service_emits_mesos_changed() -> void:
	var bus: Node = load("res://scripts/autoload/events.gd").new()
	var seen: Array = []
	bus.mesos_changed.connect(func(m: int, delta: int) -> void: seen.append([m, delta]))
	var s := ItemService.new(CharacterState.new(), db(), bus)
	assert_eq(s.gain_mesos(40), 40)
	assert_true(s.spend_mesos(15).ok)
	assert_false(s.spend_mesos(1000).ok)
	assert_eq(s.gain_mesos(0), 0)
	assert_eq(seen, [[40, 40], [25, -15]], "failures and zero changes emit nothing")
	bus.free()


func test_mesos_persist() -> void:
	var c := CharacterState.new()
	Mesos.add(c, 1234, db())
	var back := CharacterState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_eq(back.mesos, 1234)


func test_meso_cap_is_marked_unverified() -> void:
	var t: Dictionary = db().miso_table("inventory")
	assert_eq(t.verified, false)
	assert_true(String(t.meso_cap_reason).contains("MeowDB documents no meso cap"))
