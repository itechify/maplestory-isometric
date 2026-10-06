extends DataValidationTestCase
## Schema 3 drop records (Iteration Three contract C1; decisions D3-9, D3-11, D3-12): the shipped records are valid
## data, and corrupted copies fail with the finding that names the corruption. Each test edits a copy of a shipped
## record in a cloned ContentDB and rebuilds the clone's canonical_sources.json, so only the corruption shows.

const OWNER := "2"


func parity_keys() -> Dictionary:
	return {
		"test_shipped_records_pass_the_validator": ["canon:provenance-per-property", "canon:membership-rarity-separate"],
		"test_a_probability_in_a_canonical_record_is_refused": ["canon:no-probability-in-canonical"],
		"test_henesys_may_supply_only_rarity": ["canon:membership-rarity-separate", "canon:provenance-per-property"],
		"test_membership_from_another_authority_is_refused": ["canon:membership-rarity-separate"],
		"test_an_msea_reference_item_is_never_a_member": ["canon:msea-reference-excluded"],
		"test_unresolved_member_is_valid_and_listed": ["canon:unresolved-visible"],
		"test_rarity_label_and_row": ["canon:membership-rarity-separate"],
	}


## A clone whose drops/<owner> is the shipped record after `edit`, with its sources index kept current.
func _clone_edit(edit: Callable, owner: String = OWNER) -> ContentDB:
	var c := clone_db()
	var rec: Dictionary = c.canonical.drops[owner]
	edit.call(rec)
	reindex(c)
	return c


func _entry(record: Dictionary, key: String) -> Dictionary:
	for e in record.entries:
		if e.key == key:
			return e
	fail("record has no entry %s" % key)
	return {}


func _expect_drop(r: ValidationReport, check: String, contains: String, owner: String = OWNER) -> void:
	expect_new(r, "error", check, "drops", owner, contains)


# --- the shipped records are valid ---------------------------------------------------------------------------

func test_shipped_records_pass_the_validator() -> void:
	var r := baseline()
	for check in ["drop_record", "drop_policy", "provenance"]:
		assert_eq(r.matching(check, "", "", "error").size(), 0, "%s: %s" % [check, str(r.matching(check, "", "", "error"))])
	var entries := 0
	for id in db().ids("drops"):
		entries += ValidationUtil.as_array(db().drop_table(id).get("entries", [])).size()
	assert_eq(int(r.stats.get("drop_records_checked", 0)), db().ids("drops").size(), "every schema 3 record checked")
	assert_eq(int(r.stats.get("drop_entries_checked", 0)), entries, "every entry checked")
	assert_eq(int(r.stats.get("drop_rarities_checked", 0)), entries, "every rarity compared with Henesys.gg's capture")
	# Per entry: a membership source and a rarity source; per record: membership and rarity provenance (+ the Snail's
	# meso amount), all through the authority registry.
	assert_true(int(r.stats.get("provenance_sources_checked", 0)) >= 2 * entries + 2 * db().ids("drops").size(),
		"sources checked: %d" % int(r.stats.get("provenance_sources_checked", 0)))


# --- corrupted copies ----------------------------------------------------------------------------------------

func test_a_probability_in_a_canonical_record_is_refused() -> void:
	var r := run_validator(_clone_edit(func(rec: Dictionary) -> void:
		_entry(rec, "snail-shell")["probability"] = 1.0
		rec.meso["chance"] = 0.4))
	_expect_drop(r, "drop_record", "entries[1].probability: a canonical drop record holds no probability")
	_expect_drop(r, "drop_record", "meso.chance: a canonical drop record holds no probability")
	var r2 := run_validator(_clone_edit(func(rec: Dictionary) -> void: _entry(rec, "red-potion")["quantity"] = {"min": 1, "max": 3}))
	_expect_drop(r2, "drop_record", "entries[5].quantity: a canonical drop record holds no probability or quantity")


func test_henesys_may_supply_only_rarity() -> void:
	var r := run_validator(_clone_edit(func(rec: Dictionary) -> void:
		var ms: Dictionary = _entry(rec, "snail-shell").membership_source
		ms.authority = "Henesys.gg"
		ms.url = "https://henesys.gg/loot"
		ms.capture = "tools/henesys/captures/item_rarity.json"))
	_expect_drop(r, "provenance", "entries[1] 'snail-shell'.membership_source: Henesys.gg may not supply 'membership' (it may supply: rarity)")
	_expect_drop(r, "drop_record", "membership_source.authority Henesys.gg differs from the record's membership_authority")
	var r2 := run_validator(_clone_edit(func(rec: Dictionary) -> void: rec.meso.amount_source.authority = "Henesys.gg"))
	_expect_drop(r2, "provenance", "meso.amount_source: Henesys.gg may not supply 'mesos.amount'")
	var r3 := run_validator(_clone_edit(func(rec: Dictionary) -> void:
		var src: Dictionary = _entry(rec, "snail-shell").rarity.source
		src.erase("capture")
		src.read_at = "yesterday"))
	_expect_drop(r3, "provenance", "rarity.source: needs read_at, an ISO 8601 timestamp")
	_expect_drop(r3, "provenance", "rarity.source: Henesys.gg values need capture")
	var r4 := run_validator(_clone_edit(func(rec: Dictionary) -> void: _entry(rec, "snail-shell").rarity.source.url = "https://henesys.gg.evil/loot"))
	_expect_drop(r4, "provenance", "is not a Henesys.gg page")


func test_membership_from_another_authority_is_refused() -> void:
	var r := run_validator(_clone_edit(func(rec: Dictionary) -> void: rec.membership_authority = "Henesys.gg"))
	_expect_drop(r, "provenance", "membership_authority Henesys.gg may not supply 'membership'")
	_expect_drop(r, "drop_policy", "membership_authority must be MeowDB MS Classic")
	var r2 := run_validator(_clone_edit(func(rec: Dictionary) -> void: rec.membership_authority = "Some Wiki"))
	_expect_drop(r2, "provenance", "membership_authority \"Some Wiki\" is not a registered authority")
	var r3 := run_validator(_clone_edit(func(rec: Dictionary) -> void: rec.membership_list = "MSEA reference drops"))
	_expect_drop(r3, "drop_record", "membership_list must be \"Drops (MS Classic)\"")


func test_an_msea_reference_item_is_never_a_member() -> void:
	var r := run_validator(_clone_edit(func(rec: Dictionary) -> void:
		var e: Dictionary = _entry(rec, "sword").duplicate(true)
		e.key = "red-miniskirt"
		e.name = "Red Miniskirt"
		e.item_id = null
		e.item_resolution = {"state": "not_in_snapshot", "method": "none", "candidates": [], "evidence": "test"}
		e.membership_source.raw_value = "Red Miniskirt\nAny\n▲\n1\n▼\n0"
		e.membership_source.votes = {"up": 1, "down": 0, "score": 1}
		e.rarity = null
		e.chance_category = null
		e.category_inputs = {"item_type": null, "item_subtype": null, "quest_gated": false, "item": null}
		(rec.entries as Array).append(e)))
	_expect_drop(r, "drop_policy", "'Red Miniskirt' is only on MeowDB's MSEA reference list, which is never membership")
	_expect_drop(r, "drop_policy", "membership is not MeowDB's community list")


func test_unresolved_member_is_valid_and_listed() -> void:
	# An item no local record has, and an item Henesys.gg has no row for, stay in the record (null), are listed as
	# warnings and never roll; neither is a shape error.
	var c := _clone_edit(func(rec: Dictionary) -> void:
		var e := _entry(rec, "white-undershirt")
		e.item_id = null
		e.item_resolution = {"state": "not_in_snapshot", "method": "none", "candidates": ["933"], "evidence": "test: no local item"}
		e.chance_category = null
		e.category_inputs = {"item_type": null, "item_subtype": null, "quest_gated": false, "item": null})
	var r := run_validator(c)
	expect_no_new(r, "drop_record")
	expect_new(r, "warning", "drop_unresolved", "drops", OWNER, "'White Undershirt' never rolls: item unresolved (not_in_snapshot)")
	assert_eq(DropRates.effective_entries(OWNER, c).filter(func(x: Dictionary) -> bool: return x.key == "white-undershirt")[0].excluded,
		DropRates.UNRESOLVED_ITEM)
	var r2 := run_validator(_clone_edit(func(rec: Dictionary) -> void:
		var e := _entry(rec, "white-undershirt")
		e.item_id = "933"
		e.item_resolution.state = "ambiguous"))
	_expect_drop(r2, "drop_record", "item_id must be null while item_resolution.state is ambiguous")
	var r3 := run_validator(_clone_edit(func(rec: Dictionary) -> void:
		var e := _entry(rec, "white-undershirt")
		e.item_resolution.method = "meowdb_drop_entry"))
	_expect_drop(r3, "drop_record", "meowdb_drop_entry decides between two or more local items")


func test_rarity_label_and_row() -> void:
	var r := run_validator(_clone_edit(func(rec: Dictionary) -> void:
		_entry(rec, "sword").rarity.source.row = "Sword | One-Handed Sword | Rare"))
	_expect_drop(r, "drop_record", "rarity.source.row \"Sword | One-Handed Sword | Rare\" does not end with the label 'Common'")
	_expect_drop(r, "drop_policy", "'Sword': rarity.source must quote tools/henesys/captures/item_rarity.json")


func test_votes_and_raw_block() -> void:
	var r := run_validator(_clone_edit(func(rec: Dictionary) -> void: _entry(rec, "sword").membership_source.votes.up = 9))
	_expect_drop(r, "drop_record", "membership_source.votes must be {up, down, score = up - down} as the raw value shows (3 up, 0 down)")
	var r2 := run_validator(_clone_edit(func(rec: Dictionary) -> void: _entry(rec, "sword").membership_source.raw_value = "Sword"))
	_expect_drop(r2, "drop_record", "membership_source.raw_value must be the list's block")


func test_meso_block_shape() -> void:
	var r := run_validator(_clone_edit(func(rec: Dictionary) -> void: rec.meso.min = 3))
	_expect_drop(r, "drop_record", "meso: a reported amount needs whole numbers 1 <= min <= max")
	var r2 := run_validator(_clone_edit(func(rec: Dictionary) -> void:
		rec.meso.min = 1
		rec.meso.max = 1))
	_expect_drop(r2, "drop_record", "meso: min 1, max 1 differ from amount_source.raw_value")
	var set_min := func(rec: Dictionary) -> void: rec.meso.min = 4
	var r3 := run_validator(_clone_edit(set_min, "3"))
	_expect_drop(r3, "drop_record", "min, max and amount_source must be null while amount_state is not_reported", "3")
	var box_meso := func(rec: Dictionary) -> void: rec.meso = {"amount_state": "not_reported", "min": null, "max": null, "amount_source": null, "gaps": []}
	var r4 := run_validator(_clone_edit(box_meso, "0000001"))
	_expect_drop(r4, "drop_record", "meso must be null for a breakable", "0000001")


func test_unknown_schema_version() -> void:
	_expect_drop(run_validator(_clone_edit(func(rec: Dictionary) -> void: rec.schema_version = 2)), "drop_record", "schema_version must be 3")


func test_duplicate_keys_and_items() -> void:
	var r := run_validator(_clone_edit(func(rec: Dictionary) -> void: (rec.entries as Array).append(_entry(rec, "red-potion").duplicate(true))))
	_expect_drop(r, "drop_record", "key 'red-potion' is used twice")
	_expect_drop(r, "drop_record", "item 270 is also entry entries[5] 'red-potion'")
	var r2 := run_validator(_clone_edit(func(rec: Dictionary) -> void: _entry(rec, "red-potion").key = "redpotion"))
	_expect_drop(r2, "drop_record", "key must be the slug of the name, 'red-potion'")


func test_quest_gate_must_say_its_rule() -> void:
	var edit := func(rec: Dictionary) -> void:
		var gate: Dictionary = rec.entries[0].quest_gate
		gate.verified = true
		gate.decision = "D3-1"
	var r := run_validator(_clone_edit(edit, "0000001"))
	_expect_drop(r, "drop_record", "quest_gate.decision must be \"D3-9\"", "0000001")
	_expect_drop(r, "drop_record", "must say verified: false", "0000001")
