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
	# Counted against the unbroken copy, so this holds before and after the drops package rewrites the shipped
	# records as v2: the fixture replaces drops/0000001 (one more v2 record unless the shipped one already is v2).
	var shipped: Dictionary = db().canonical.get("drops", {}).get("0000001", {})
	var shipped_v2 := int(shipped.get("schema_version", 1)) == 2
	var base := baseline()
	assert_eq(int(r.stats.get("drop_records_v2_checked", 0)), int(base.stats.get("drop_records_v2_checked", 0)) + (0 if shipped_v2 else 1),
		"the fixture is checked as a v2 record")
	assert_eq(int(r.stats.get("drop_entries_v2_checked", 0)), int(base.stats.get("drop_entries_v2_checked", 0))
		- ((shipped.get("entries", []) as Array).size() if shipped_v2 else 0) + 4, "its four entries checked")
	var gates := {}
	for e: Dictionary in f.entries:
		gates[String(e.key)] = e.quest_gate.quest_id if e.quest_gate is Dictionary else null
	assert_eq(gates, {"apple": null, "egg": null, "rusty-screw": "1012", "old-wooden-board": "1012"}, "gates (D3-9)")
	assert_eq(f.meso, null, "a Wooden Box never drops mesos")
