extends DataValidationTestCase
## The Wooden Box drop table the box tests roll (game/tests/data/breakables/drops_0000001_v2.json) is valid schema v2
## data (contract C1): swapped in as drops/0000001 of a cloned ContentDB, the validator finds nothing. Its values follow
## decision D3-7 (Board and Screw 1/1 gated to 1012, Apple 1/4, Egg unresolved, no mesos) and cite the dated captures.

const FIXTURE := "res://tests/data/breakables/drops_0000001_v2.json"


func parity_keys() -> Dictionary:
	return {"test_the_box_fixture_is_valid_v2_data": ["mechanic:breakable-drop-roll", "drop:0000001/441", "drop:0000001/442"]}


func test_the_box_fixture_is_valid_v2_data() -> void:
	var f := load_fixture(FIXTURE)
	var c := clone_db()
	c.canonical.drops["0000001"] = f
	reindex(c)
	var r := run_validator(c)
	expect_no_new(r)
	assert_eq(int(r.stats.get("drop_records_v2_checked", 0)), 1, "one v2 record checked")
	assert_eq(int(r.stats.get("drop_entries_v2_checked", 0)), 4, "its four entries checked")
	var gates := {}
	for e: Dictionary in f.entries:
		gates[String(e.key)] = e.quest_gate.quest_id if e.quest_gate is Dictionary else null
	assert_eq(gates, {"apple": null, "egg": null, "rusty-screw": "1012", "old-wooden-board": "1012"}, "gates (D3-9)")
	assert_eq(f.meso, null, "a Wooden Box never drops mesos")
