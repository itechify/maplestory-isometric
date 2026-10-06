extends DataValidationTestCase
## The Wooden Box drop table the box tests roll (game/tests/data/breakables/drops_0000001.json) is valid schema 3 data
## (contract C1): swapped in as drops/0000001 of a cloned ContentDB, the validator finds nothing new. It follows
## decision D3-11 (MeowDB's community list: Old Wooden Board and Rusty Screw gated to Pio's 1012 by D3-9, Apple and
## Egg; every rarity Common from Henesys.gg) and holds no meso block (a breakable never drops mesos, D3-12).

const FIXTURE := "res://tests/data/breakables/drops_0000001.json"


func test_the_box_fixture_is_valid_schema_3_data() -> void:
	var f := load_fixture(FIXTURE)
	var c := clone_db()
	c.canonical.drops["0000001"] = f
	reindex(c)
	var r := run_validator(c)
	expect_no_new(r)
	assert_eq(int(f.get("schema_version", 0)), DropRates.SCHEMA_VERSION, "schema 3")
	var gates := {}
	var cats := {}
	for e: Dictionary in f.entries:
		gates[String(e.key)] = e.quest_gate.quest_id if e.quest_gate is Dictionary else null
		cats[String(e.key)] = "%s/%s" % [e.chance_category, e.rarity.label]
	assert_eq(gates, {"apple": null, "egg": null, "rusty-screw": "1012", "old-wooden-board": "1012"}, "gates (D3-9)")
	assert_eq(cats, {"apple": "use_consumable/Common", "egg": "use_consumable/Common",
		"rusty-screw": "etc_quest_gated/Common", "old-wooden-board": "etc_quest_gated/Common"}, "categories and rarity")
	assert_eq(f.meso, null, "a Wooden Box never drops mesos")
