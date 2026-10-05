extends DataValidationTestCase
## Schema v2 drop records (Iteration Three contract C1): the fixture game/tests/data/drops_v2/fixture_2.json (a Snail
## record built from the dated captures; tools/sources/test/fixture.test.mjs checks its raw values against them) is
## valid data, and corrupted copies of it fail with the finding that names the corruption. Each test swaps the fixture
## in as drops/2 of a cloned ContentDB and rebuilds the clone's canonical_sources.json, so only the corruption shows.

const FIXTURE := "res://tests/data/drops_v2/fixture_2.json"
const OWNER := "2"


func _fixture() -> Dictionary:
	return load_fixture(FIXTURE)


## A clone whose drops/<owner> is `record`, with its sources index kept current.
func _clone_with(record: Dictionary, owner: String = OWNER) -> ContentDB:
	var c := clone_db()
	c.canonical.drops[owner] = record
	reindex(c)
	return c


func _entry(record: Dictionary, key: String) -> Dictionary:
	for e in record.entries:
		if e.key == key:
			return e
	fail("fixture has no entry %s" % key)
	return {}


func _expect_drop(r: ValidationReport, check: String, contains: String, owner: String = OWNER) -> void:
	expect_new(r, "error", check, "drops", owner, contains)


# --- the fixture is valid ----------------------------------------------------------------------------------

func test_fixture_passes_the_validator() -> void:
	var r := run_validator(_clone_with(_fixture()))
	expect_no_new(r)
	assert_eq(int(r.stats.get("drop_records_v2_checked", 0)), 1, "one v2 record checked")
	assert_eq(int(r.stats.get("drop_entries_v2_checked", 0)), 4, "its four entries checked")
	assert_true(int(r.stats.get("provenance_sources_checked", 0)) >= 13, "4 record-level + 4 membership + 3 chance + 2 meso sources")


func test_fixture_holds_the_task_cases() -> void:
	var f := _fixture()
	assert_eq(f.schema_version, 2.0)
	assert_eq(_entry(f, "snail-shell").probability, 1.0)
	assert_eq(_entry(f, "red-potion").probability, 0.02)
	assert_eq(_entry(f, "green-apple").item_id, "242")
	assert_true(db().has("items", "242"), "Green Apple (242) is a canonical item")
	assert_eq(_entry(f, "wooden-buckler").item_id, null)
	assert_eq(_entry(f, "wooden-buckler").chance_state, "unresolved")
	assert_eq(f.excluded_kuro_only[0].name, "Snail Card")
	assert_eq([f.meso.min, f.meso.max, f.meso.probability], [2.0, 2.0, 0.4])


func test_shipped_drop_records_are_still_v1() -> void:
	# Another package converts them; until then the v1 rules and the placeholder rates apply unchanged.
	for id in db().ids("drops"):
		assert_false(DropRecordChecks.is_v2(db().drop_table(id)), "drops/%s is v1" % id)
	assert_eq(baseline().matching("drop_record").size(), 0, "no drop_record findings on the shipped data")


func test_hidden_street_meso_amount_is_accepted() -> void:
	var f := _fixture()
	f.meso.amount_source = {"authority": "Hidden Street", "url": "https://bc.hidden-street.net/monster/snail",
		"read_at": "2026-10-05T08:03:43.486Z", "capture": "tools/hiddenstreet/captures/monsters.json", "raw_value": "Mesos: 1"}
	f.meso.min = 1
	f.meso.max = 1
	expect_no_new(run_validator(_clone_with(f)))


func test_unresolved_meso_and_ambiguous_item_are_valid() -> void:
	var f := _fixture()
	f.meso = {"amount_state": "unresolved", "min": null, "max": null, "chance_state": "unresolved", "probability": null,
		"amount_source": {"authority": "Hidden Street", "url": "https://bc.hidden-street.net/monster/snail",
			"read_at": "2026-10-05T08:03:43.486Z", "capture": "tools/hiddenstreet/captures/monsters.json", "raw_value": "Mesos: ?"},
		"chance_source": null}
	var e := _entry(f, "green-apple")
	e.item_id = null
	e.item_resolution = {"state": "ambiguous", "method": "none", "candidates": ["486", "495"], "note": "test"}
	expect_no_new(run_validator(_clone_with(f)))


# --- corrupted copies fail -----------------------------------------------------------------------------------

func test_probability_above_one() -> void:
	var f := _fixture()
	_entry(f, "red-potion").probability = 1.5
	_expect_drop(run_validator(_clone_with(f)), "drop_record", "entries[1] 'red-potion'.probability must be a number in [0, 1]")


func test_negative_probability() -> void:
	var f := _fixture()
	_entry(f, "red-potion").probability = -0.02
	_entry(f, "red-potion").chance_source.normalized_probability = -0.02
	var r := run_validator(_clone_with(f))
	_expect_drop(r, "drop_record", "probability must be a number in [0, 1]")
	_expect_drop(r, "drop_record", "does not follow from raw_value")


func test_kuro_only_item_added_as_a_kurodb_member() -> void:
	var f := _fixture()
	var card := (_entry(f, "red-potion")).duplicate(true)
	card.key = "snail-card"
	card.name = "Snail Card"
	card.item_id = null
	card.item_resolution = {"state": "not_in_snapshot", "method": "none", "candidates": [], "note": ""}
	card.membership_source = {"authority": "KuroDB", "url": "https://playkuro.com/database/#monsters/100100",
		"read_at": "2026-10-05T07:46:19.383Z", "capture": "tools/kurodb/captures/100100.json", "raw_value": "Snail Card"}
	card.chance_source.kuro_item_id = "2380000"
	card.chance_source.kuro_name = "Snail Card"
	card.chance_source.raw_value = "26% base | Qty 1"
	card.chance_source.normalized_probability = 0.26
	card.probability = 0.26
	f.entries.append(card)
	var r := run_validator(_clone_with(f))
	_expect_drop(r, "provenance", "entries[4] 'snail-card'.membership_source: KuroDB may not supply 'membership'")
	_expect_drop(r, "drop_record", "differs from the record's membership_authority Hidden Street")
	_expect_drop(r, "drop_record", "'Snail Card' is also an excluded_kuro_only row")


func test_kuro_only_item_smuggled_in_with_a_hidden_street_source() -> void:
	var f := _fixture()
	var card := (_entry(f, "snail-shell")).duplicate(true)
	card.key = "snail-card"
	card.name = "Snail Card"
	card.item_id = null
	card.item_resolution = {"state": "not_in_snapshot", "method": "none", "candidates": [], "note": ""}
	card.chance_source = null
	card.chance_state = "unresolved"
	card.probability = null
	card.quantity = null
	f.entries.append(card)
	var r := run_validator(_clone_with(f))
	_expect_drop(r, "drop_record", "membership_source.raw_value \"Etc. drop: Snail Shell\" does not name 'Snail Card'")
	_expect_drop(r, "drop_record", "'Snail Card' is also an excluded_kuro_only row")


func test_missing_chance_source_on_a_resolved_entry() -> void:
	var f := _fixture()
	_entry(f, "green-apple").chance_source = null
	_expect_drop(run_validator(_clone_with(f)), "drop_record", "entries[2] 'green-apple': chance_state is resolved but there is no chance_source")


func test_unknown_item_id() -> void:
	var f := _fixture()
	_entry(f, "snail-shell").item_id = BOGUS
	_expect_drop(run_validator(_clone_with(f)), "reference", "entries[].item_id references items '%s', which does not exist" % BOGUS)


func test_unknown_quest_gate() -> void:
	var f := _fixture()
	_entry(f, "snail-shell").quest_gate = {"quest_id": BOGUS, "basis": "test"}
	_expect_drop(run_validator(_clone_with(f)), "reference", "entries[].quest_gate.quest_id references quests '%s'" % BOGUS)


func test_quest_gate_on_a_real_quest_is_valid() -> void:
	var f := _fixture()
	var quest_id := db().ids("quests")[0]
	_entry(f, "snail-shell").quest_gate = {"quest_id": quest_id, "basis": "test: Quest Item required by the quest"}
	expect_no_new(run_validator(_clone_with(f)))


func test_hidden_street_may_not_supply_a_probability() -> void:
	var f := _fixture()
	var cs: Dictionary = _entry(f, "snail-shell").chance_source
	cs.authority = "Hidden Street"
	cs.url = "https://bc.hidden-street.net/monster/snail"
	cs.capture = "tools/hiddenstreet/captures/monsters.json"
	_expect_drop(run_validator(_clone_with(f)), "provenance", "chance_source: Hidden Street may not supply 'probability'")


func test_one_over_n_read_as_a_percentage() -> void:
	var f := _fixture()
	var cs: Dictionary = _entry(f, "snail-shell").chance_source
	cs.raw_value = "Chance value 4"
	cs.normalized_probability = 0.04
	_entry(f, "snail-shell").probability = 0.04
	_expect_drop(run_validator(_clone_with(f)), "drop_record", "is not a \"<p>% base\" value")
	cs.format = "reactor_chance_value"
	_expect_drop(run_validator(_clone_with(f)), "drop_record", "does not follow from raw_value \"Chance value 4\"")


func test_percentage_read_as_one_over_n() -> void:
	var f := _fixture()
	var cs: Dictionary = _entry(f, "red-potion").chance_source
	cs.normalized_probability = 0.5  # "2.00%" misread as 1/2
	_entry(f, "red-potion").probability = 0.5
	_expect_drop(run_validator(_clone_with(f)), "drop_record", "normalized_probability 0.5 does not follow from raw_value \"2.00% base | Qty 1\"")


func test_truncated_probability() -> void:
	var f := _fixture()
	var cs: Dictionary = _entry(f, "green-apple").chance_source
	cs.normalized_probability = 0.0  # "2.00%" truncated to an integer percent of 0
	_entry(f, "green-apple").probability = 0.0
	_expect_drop(run_validator(_clone_with(f)), "drop_record", "does not follow from raw_value")


func test_reactor_value_needs_an_interpretation() -> void:
	var f := _fixture()
	var cs: Dictionary = _entry(f, "snail-shell").chance_source
	cs.raw_value = "Chance value 4"
	cs.format = "reactor_chance_value"
	cs.normalized_probability = 0.25
	_entry(f, "snail-shell").probability = 0.25
	_expect_drop(run_validator(_clone_with(f)), "drop_record", "is an interpretation; say so in interpretation")
	cs.interpretation = "1/N (decision D3-7)"
	expect_no_new(run_validator(_clone_with(f)))


func test_probability_and_normalized_value_must_agree() -> void:
	var f := _fixture()
	_entry(f, "red-potion").probability = 0.2
	_expect_drop(run_validator(_clone_with(f)), "drop_record", "normalized_probability 0.02 differs from the probability 0.2")


func test_unresolved_entry_has_no_probability() -> void:
	var f := _fixture()
	_entry(f, "wooden-buckler").probability = 0.01
	_expect_drop(run_validator(_clone_with(f)), "drop_record", "probability must be null while chance_state is unresolved")


func test_item_resolution_must_match_item_id() -> void:
	var f := _fixture()
	_entry(f, "wooden-buckler").item_resolution.state = "resolved"
	_entry(f, "red-potion").item_resolution.state = "ambiguous"
	var r := run_validator(_clone_with(f))
	_expect_drop(r, "drop_record", "item_resolution.state is resolved but item_id is null")
	_expect_drop(r, "drop_record", "item_id must be null while item_resolution.state is ambiguous")


func test_quantity_and_meso_ranges() -> void:
	var f := _fixture()
	_entry(f, "red-potion").quantity = {"min": 3, "max": 1}
	f.meso.min = 3
	var r := run_validator(_clone_with(f))
	_expect_drop(r, "drop_record", "quantity must be {min, max} with whole numbers 1 <= min <= max")
	_expect_drop(r, "drop_record", "meso: a resolved amount needs whole numbers 1 <= min <= max")
	f.meso.min = 1
	_expect_drop(run_validator(_clone_with(f)), "drop_record", "meso: min 1, max 2 differ from amount_source.raw_value")


func test_meso_chance_must_be_a_meso_row() -> void:
	var f := _fixture()
	f.meso.chance_source.raw_value = "26% base | Qty 1"
	f.meso.chance_source.normalized_probability = 0.26
	f.meso.probability = 0.26
	_expect_drop(run_validator(_clone_with(f)), "drop_record", "is an item row, not a \"Meso drop\" row")


func test_hidden_street_does_not_describe_breakables() -> void:
	var f := _fixture()
	var box_id := first_id_where(clone_db(), "drops", func(t: Dictionary) -> bool: return t.owner.kind == "breakable", "owned by a breakable")
	f.id = box_id
	f.owner = {"kind": "breakable", "id": box_id, "name": "box"}
	var r := run_validator(_clone_with(f, box_id))
	expect_new(r, "error", "provenance", "drops", box_id, "Hidden Street does not describe breakable drop owners")


func test_unknown_schema_version() -> void:
	var f := _fixture()
	f.schema_version = 3
	_expect_drop(run_validator(_clone_with(f)), "drop_record", "schema_version must be 2")


func test_duplicate_keys_and_items() -> void:
	var f := _fixture()
	var copy: Dictionary = (_entry(f, "red-potion")).duplicate(true)
	f.entries.append(copy)
	var r := run_validator(_clone_with(f))
	_expect_drop(r, "drop_record", "key 'red-potion' is used twice")
	_expect_drop(r, "drop_record", "item 270 is also entry entries[1] 'red-potion'")


# --- the runtime still copes ---------------------------------------------------------------------------------

func test_placeholder_runtime_survives_a_v2_table() -> void:
	# The roller is rewritten by another package; until then DropRates must not crash on a v2 table (item_id null).
	var c := _clone_with(_fixture())
	assert_eq(DropRates.validate(c).size(), 0, "drop_rates.json still validates against a v2 table")
	var rows := DropRates.effective_entries(OWNER, c)
	assert_eq(rows.size(), 4)
	for row in rows:
		if row.item_id == "":
			assert_eq(row.excluded, "unknown_item", "the unresolved member never rolls")


## The brief's "Probability Handling" and "Drop Testing" rules these validator tests prove (parity keys, contract C6;
## added by the validation package: the drops package owns these tests and may extend the map).
func parity_keys() -> Dictionary:
	var conversion := ["canon:probability-conversion"]
	return {
		"test_probability_above_one": conversion,
		"test_negative_probability": conversion,
		"test_one_over_n_read_as_a_percentage": conversion,
		"test_percentage_read_as_one_over_n": conversion,
		"test_truncated_probability": conversion,
		"test_reactor_value_needs_an_interpretation": conversion,
		"test_probability_and_normalized_value_must_agree": conversion,
		"test_kuro_only_item_added_as_a_kurodb_member": ["canon:kuro-only-excluded"],
		"test_kuro_only_item_smuggled_in_with_a_hidden_street_source": ["canon:kuro-only-excluded"],
		"test_unresolved_entry_has_no_probability": ["canon:unresolved-visible"],
		"test_unresolved_meso_and_ambiguous_item_are_valid": ["canon:unresolved-visible"],
		"test_hidden_street_may_not_supply_a_probability": ["canon:membership-chance-separate"],
		"test_missing_chance_source_on_a_resolved_entry": ["canon:membership-chance-separate"],
	}
