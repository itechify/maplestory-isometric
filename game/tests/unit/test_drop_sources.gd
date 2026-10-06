extends DataValidationTestCase
## The drop policy against the dated captures themselves (Iteration Three brief "Drop Testing"; contract C1; decisions
## D3-3 to D3-9): membership is exactly the membership source's list, a KuroDB-only row never enters a table, the meso
## amount and the meso chance come from their own authorities, unknown probabilities stay visible, every item id
## resolves. The captures (tools/hiddenstreet, tools/kurodb, tools/meowdb captures) are read from the folder next to the
## project, as the validator reads them (scripts/test.sh mirrors them next to an ISOLATE copy). Then corrupted copies of
## the shipped records must fail DropChecks with the finding that names the corruption.


func parity_keys() -> Dictionary:
	# Membership and chance are checked entry by entry against the dated captures (every monster entry; the box's
	# entries), so those tests prove each drop:<owner>/<key>; the meso test checks each monster's meso record.
	var monster_drops: Array = []
	var mesos: Array = []
	for owner_id in _monsters():
		mesos.append("meso:" + owner_id)
		for e in db().drop_table(owner_id).entries:
			monster_drops.append("drop:%s/%s" % [owner_id, String(e.key)])
	var box_drops: Array = []
	for e in db().drop_table("0000001").entries:
		box_drops.append("drop:0000001/" + String(e.key))
	return {
		"test_membership_is_exactly_the_hidden_street_lists": ["mechanic:drop-membership-authoritative",
			"monster:1", "monster:2", "monster:3", "monster:4", "monster:5", "monster:9"] + monster_drops,
		"test_box_membership_is_meowdbs_live_list": ["breakable:0000001", "mechanic:drop-membership-authoritative"] + box_drops,
		"test_kurodb_only_rows_never_enter": ["mechanic:kurodb-only-excluded"],
		"test_chances_quote_the_kurodb_capture": ["mechanic:drop-chance-from-kurodb"] + monster_drops + box_drops,
		"test_meso_amount_and_chance_sources": ["mechanic:meso-amount-source", "mechanic:meso-chance-source"] + mesos,
		"test_unknown_probabilities_stay_visible": ["mechanic:unresolved-drops-visible"],
		"test_kurodb_only_row_added_back_fails": ["mechanic:kurodb-only-excluded"],
		"test_meso_chance_from_meowdb_fails": ["mechanic:meso-chance-source"],
		"test_unknown_item_id_is_an_error_not_a_crash": ["mechanic:drop-item-ids-resolve"],
		"test_progression_item_that_never_rolls_is_a_blocker": ["quest:1011", "mechanic:unresolved-drops-visible"],
		"test_a_rate_put_back_into_drop_rates_json_fails_the_data_validator": ["mechanic:no-placeholder-drop-rates"],
	}


## A capture file's text, from tools/<site>/captures next to the project.
func _capture(rel: String) -> String:
	var root := ProvenanceChecks.new(db(), ValidationReport.new()).repo_root()
	var text := FileAccess.get_file_as_string(root.path_join(rel))
	if text == "":
		fail("capture %s not found under %s" % [rel, root])
	return text


func _json(rel: String) -> Variant:
	return JSON.parse_string(_capture(rel))


const HS_CATEGORIES := ["Etc. drop", "Common equipment", "Warrior equipment", "Magician equipment", "Bowman equipment",
	"Thief equipment", "Pirate equipment", "Ore drop", "Maker item", "Useable drop"]


## Hidden Street's members for one monster page text: names in first-seen order across the drop categories.
static func _hs_members(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in text.split("\n"):
		for cat in HS_CATEGORIES:
			if line.begins_with(cat + ":"):
				var body := line.substr(cat.length() + 1).strip_edges()
				if body == "-" or body == "":
					continue
				for name in body.split(","):
					var n := String(name).strip_edges()
					if n != "" and not out.has(n):
						out.append(n)
	return out


func _hs_page(url: String) -> Dictionary:
	var hs: Variant = _json("tools/hiddenstreet/captures/monsters.json")
	for m in (hs as Dictionary).get("monsters", []):
		if m.url == url:
			return m
	fail("no Hidden Street capture for %s" % url)
	return {}


func _kuro_page(table: Dictionary) -> Dictionary:
	var cap := str(table.provenance.probability.capture)
	var j: Variant = _json(cap)
	return j if j is Dictionary else {}


func _monsters() -> Array:
	return Array(db().ids("drops")).filter(func(id: String) -> bool: return db().drop_table(id).owner.kind == "monster")


func test_membership_is_exactly_the_hidden_street_lists() -> void:
	assert_eq(_monsters().size(), 6, "the six Maple Island monsters")
	for owner_id in _monsters():
		var table := db().drop_table(owner_id)
		assert_eq(table.membership_authority, "Hidden Street", "drops/%s (D3-6)" % owner_id)
		var page := _hs_page(table.provenance.membership.url)
		var names := PackedStringArray(table.entries.map(func(e: Dictionary) -> String: return e.name))
		assert_eq(names, _hs_members(page.text), "drops/%s: every Hidden Street member, nothing else, in page order" % owner_id)
		for e in table.entries:
			assert_eq(e.membership_source.authority, "Hidden Street")
			for line in String(e.membership_source.raw_value).split("\n"):
				assert_true(page.text.contains(line), "drops/%s %s: '%s' is a captured line" % [owner_id, e.key, line])


func test_box_membership_is_meowdbs_live_list() -> void:
	var table := db().drop_table("0000001")
	assert_eq(table.membership_authority, "MeowDB MS Classic", "Hidden Street has no breakables (D3-7)")
	var text := _capture("tools/meowdb/captures/breakable_0000001.txt").replace("\r\n", "\n")
	assert_eq(PackedStringArray(table.entries.map(func(e: Dictionary) -> String: return e.name)),
		PackedStringArray(["Old Wooden Board", "Rusty Screw", "Apple", "Egg"]))
	for e in table.entries:
		assert_true(text.contains(e.membership_source.raw_value), "%s quoted from the live page" % e.name)


func test_kurodb_only_rows_never_enter() -> void:
	for owner_id in _monsters():
		var table := db().drop_table(owner_id)
		var kuro := _kuro_page(table)
		var matched := {}
		for e in table.entries:
			if e.chance_source is Dictionary:
				matched["%s|%s" % [e.chance_source.kuro_item_id, e.chance_source.kuro_name]] = true
		var excluded := {}
		for x in table.excluded_kuro_only:
			excluded["%s|%s" % [x.kuro_item_id, x.name]] = true
			for e in table.entries:
				assert_ne(DropRecordChecks._name_key(e.name), DropRecordChecks._name_key(x.name), "drops/%s: KuroDB-only %s is not a member" % [owner_id, x.name])
		# A row that may be a member under another name, waiting for its item page (decision D3-8): never rolls.
		var pending := {}
		for x in table.get("pending_kuro_candidates", []):
			pending["%s|%s" % [x.kuro_item_id, x.name]] = true
		for row in kuro.rows:
			if row.link_id == null:
				continue  # the meso row
			var key := "%s|%s" % [row.link_id, row.name]
			var buckets := int(matched.has(key)) + int(excluded.has(key)) + int(pending.has(key))
			assert_eq(buckets, 1, "drops/%s: KuroDB row %s is matched, excluded or pending, once" % [owner_id, key])
	var snail := PackedStringArray(db().drop_table("2").entries.map(func(e: Dictionary) -> String: return e.name))
	for name in ["Snail Card", "Bronze Ore", "Garnet Ore", "Sword", "Green Headband"]:
		assert_false(snail.has(name), "the Snail never drops the KuroDB-only %s" % name)
	# None of them can roll either.
	var sim := DropRoller.simulate("2", 5000, db(), _rng(17))
	for id in ["413", "320", "541", "713"]:
		assert_false((sim.items as Dictionary).has(id), "KuroDB-only / MeowDB-reference item %s never drops from the Snail" % id)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func test_chances_quote_the_kurodb_capture() -> void:
	for owner_id in _monsters():
		var table := db().drop_table(owner_id)
		var kuro := _kuro_page(table)
		for e in table.entries:
			if not (e.chance_source is Dictionary):
				continue
			var row: Variant = null
			for r in kuro.rows:
				if str(r.link_id) == e.chance_source.kuro_item_id and r.name == e.chance_source.kuro_name:
					row = r
			assert_true(row != null, "drops/%s %s: its KuroDB row is on the captured page" % [owner_id, e.key])
			if row != null:
				assert_eq(e.chance_source.raw_value, row.detail)
				assert_near(float(e.probability), float(DropChance.parse_kuro_percent(row.detail).probability), 1e-15)
	var reactor: Variant = _json("tools/kurodb/captures/reactor_2001_items.json")
	for e in db().drop_table("0000001").entries:
		if e.chance_source is Dictionary:
			var found := false
			for it in reactor.items:
				if it.kuro_item_id == e.chance_source.kuro_item_id:
					found = String(it.text).contains("Reactor 2001\n%s" % e.chance_source.raw_value)
			assert_true(found, "%s: 'Reactor 2001' row on KuroDB's item page" % e.name)


func test_meso_amount_and_chance_sources() -> void:
	for owner_id in _monsters():
		var table := db().drop_table(owner_id)
		var kuro := _kuro_page(table)
		var meso_row: Variant = null
		for r in kuro.rows:
			if r.link_id == null and String(r.detail).contains("Meso drop"):
				meso_row = r
		if meso_row == null:
			assert_eq(table.meso, null, "drops/%s: no KuroDB meso row, no mesos" % owner_id)
			continue
		assert_eq(table.meso.chance_source.raw_value, meso_row.detail, "drops/%s meso chance quotes KuroDB" % owner_id)
		var amount_src: Dictionary = table.meso.amount_source
		if amount_src.authority == "MeowDB MS Classic":
			assert_true(_capture(amount_src.capture).contains(amount_src.raw_value), "drops/%s: MeowDB report line captured" % owner_id)
		else:
			assert_eq(amount_src.authority, "Hidden Street")
			assert_true(_hs_page(amount_src.url).text.contains(amount_src.raw_value), "drops/%s: Hidden Street meso captured" % owner_id)
			assert_true(_capture("tools/meowdb/captures/" + ("monster_%s.json" % owner_id)).contains("No meso reports yet"),
				"drops/%s: Hidden Street only because MeowDB has no report" % owner_id)
	assert_eq(db().drop_table("2").meso.amount_source.authority, "MeowDB MS Classic", "the Snail keeps MeowDB's report (D3-5)")


func test_unknown_probabilities_stay_visible() -> void:
	var r := baseline()
	var listed := {}
	for f in r.matching("drop_unresolved", "drops", "", "warning"):
		listed["%s|%s" % [f.id, String(f.message).get_slice("'", 1)]] = true
	var count := 0
	for owner_id in db().ids("drops"):
		for u in DropRates.unresolved(owner_id, db()):
			count += 1
			assert_true(listed.has("%s|%s" % [owner_id, u.name]), "validation lists the unresolved %s/%s" % [owner_id, u.name])
	assert_eq(count, 54, "54 members never roll (21 do)")
	assert_true(str(db().drop_table("0000001").gaps).contains("Egg"), "the Egg's unresolved chance is in the record's gaps")


func test_all_drop_item_ids_exist() -> void:
	for owner_id in db().ids("drops"):
		for e in db().drop_table(owner_id).entries:
			if e.item_id != null:
				assert_true(db().has("items", e.item_id), "drops/%s %s -> item %s" % [owner_id, e.key, e.item_id])
	assert_eq(baseline().matching("reference", "drops").size(), 0, "no dangling id in a drop record")


# --- corrupted copies fail (DropChecks) ----------------------------------------------------------------------

## A clone of the shipped content; edit c.canonical.drops[id], then _validate(c).
func _rec(c: ContentDB, owner_id: String) -> Dictionary:
	return c.canonical.drops[owner_id]


func _validate(c: ContentDB) -> ValidationReport:
	reindex(c)
	return run_validator(c)


func _entry(rec: Dictionary, key: String) -> Dictionary:
	for e in rec.entries:
		if e.key == key:
			return e
	fail("no entry %s" % key)
	return {}


func test_kurodb_only_row_added_back_fails() -> void:
	var c := clone_db()
	var rec := _rec(c, "2")
	var card: Dictionary = (_entry(rec, "red-potion")).duplicate(true)
	card.key = "snail-card"
	card.name = "Snail Card"
	card.chance_source.kuro_item_id = "2380000"
	card.chance_source.kuro_name = "Snail Card"
	card.chance_source.raw_value = "26% base | Qty 1"
	card.chance_source.normalized_probability = 0.26
	card.chance_source.conversion = "26 / 100"
	card.probability = 0.26
	card.item_id = null
	card.item_resolution = {"state": "not_in_snapshot", "method": "none", "candidates": [], "note": "test"}
	rec.entries.append(card)
	var r := _validate(c)
	expect_new(r, "error", "drop_policy", "drops", "2", "excluded_kuro_only row Snail Card (2380000) is also the chance source")
	expect_new(r, "error", "drop_record", "drops", "2", "'Snail Card' is also an excluded_kuro_only row")


func test_raw_value_and_probability_must_agree_exactly() -> void:
	var c := clone_db()
	var e := _entry(_rec(c, "5"), "brown-woodsman-boots")
	e.probability = 0.0008000001
	e.chance_source.normalized_probability = 0.0008000001
	expect_new(_validate(c), "error", "drop_policy", "drops", "5", "probability 0.0008000001 is not the exact reading of \"0.0800% base | Qty 1\"")
	var q := clone_db()
	_entry(_rec(q, "2"), "snail-shell").quantity = {"min": 1, "max": 2, "source": "x"}
	expect_new(_validate(q), "error", "drop_policy", "drops", "2", "quantity")
	var flag := clone_db()
	_rec(flag, "1").entries[0].chance_source.kuro_quest_condition = null
	expect_new(_validate(flag), "error", "drop_policy", "drops", "1", "kuro_quest_condition null differs from the raw value's quest flag \"1035\"")


func test_meso_chance_from_meowdb_fails() -> void:
	var c := clone_db()
	var meso: Dictionary = _rec(c, "2").meso
	meso.chance_source.authority = "MeowDB MS Classic"
	meso.chance_source.url = "https://meowdb.com/msclassic/api/mesos-reports?monsterId=2"
	meso.chance_source.raw_value = "dropChancePct 100"
	meso.chance_source.normalized_probability = 1.0
	meso.probability = 1.0
	expect_new(_validate(c), "error", "drop_policy", "drops", "2", "the meso chance comes from KuroDB only")


func test_meso_amount_must_match_its_source() -> void:
	var c := clone_db()
	_rec(c, "4").meso.max = 8
	expect_new(_validate(c), "error", "drop_policy", "drops", "4", "meso: min 4, max 8 are not the amount_source's 4-6")


func test_quest_gate_rule_is_enforced() -> void:
	var ungated := clone_db()
	_entry(_rec(ungated, "0000001"), "rusty-screw").quest_gate = null
	expect_new(_validate(ungated), "error", "drop_policy", "drops", "0000001", "the C1 quest-gate rule gives quest 1012, the record says no gate")
	var shell := clone_db()
	_rec(shell, "1").entries[0].quest_gate = {"quest_id": "1005", "basis": "KuroDB says Quest 1035", "verified": false}
	expect_new(_validate(shell), "error", "drop_policy", "drops", "1", "the C1 quest-gate rule gives no gate, the record says quest 1005")
	var verified := clone_db()
	_entry(_rec(verified, "0000001"), "old-wooden-board").quest_gate.verified = true
	expect_new(_validate(verified), "error", "drop_policy", "drops", "0000001", "must say verified: false")


func test_wrong_membership_authority_and_v1_record_fail() -> void:
	var c := clone_db()
	_rec(c, "3").membership_authority = "MeowDB MS Classic"
	expect_new(_validate(c), "error", "drop_policy", "drops", "3", "membership_authority must be Hidden Street for a monster")
	var v1 := clone_db()
	_rec(v1, "4").erase("schema_version")
	expect_new(_validate(v1), "error", "drop_policy", "drops", "4", "not a schema v2 record")


func test_reactor_quantity_must_be_a_labelled_adaptation() -> void:
	var c := clone_db()
	_entry(_rec(c, "0000001"), "apple").quantity = {"min": 1, "max": 1, "source": "assumed"}
	expect_new(_validate(c), "error", "drop_policy", "drops", "0000001", "KuroDB reactor rows give no quantity")


func test_progression_item_that_never_rolls_is_a_blocker() -> void:
	var c := clone_db()
	var e := _entry(_rec(c, "3"), "blue-snail-shell")
	e.chance_state = "unresolved"
	e.chance_source = null
	e.probability = null
	e.quantity = null
	expect_new(_validate(c), "error", "drop_policy", "drops", "3", "item 349 is needed by quest")
	# The same hole when the item itself is unresolved: a candidate that a quest asks for blocks too.
	var amb := clone_db()
	var a := _entry(_rec(amb, "3"), "blue-snail-shell")
	a.item_id = null
	a.item_resolution = {"state": "ambiguous", "method": "normalized", "candidates": ["349", "2584"], "note": "test"}
	expect_new(_validate(amb), "error", "drop_policy", "drops", "3", "item 349 (a candidate of the unresolved item) is needed by quest")


func test_unknown_item_id_is_an_error_not_a_crash() -> void:
	# An item id with no local definition: a drop_policy error (run_validator fails the test on a validator crash).
	var c := clone_db()
	_entry(_rec(c, "2"), "red-potion").item_id = "99999"
	var r := _validate(c)
	expect_new(r, "error", "drop_policy", "drops", "2", "item 99999 is not a local MeowDB item")
	assert_true(DropRates.effective_entries("2", c).any(func(row: Dictionary) -> bool:
		return row.key == "red-potion" and row.excluded == DropRates.UNKNOWN_ITEM), "and it never rolls")


func test_a_rate_put_back_into_drop_rates_json_fails_the_data_validator() -> void:
	# C1: nothing outside the records supplies a chance, quantity or meso amount. The data validator (not only the unit
	# test of DropRates.validate) refuses a placeholder rate or any number in data/misostory/drop_rates.json.
	expect_no_new(baseline(), "drop_policy")
	assert_eq(baseline().matching("drop_policy", "misostory", "drop_rates").size(), 0, "the shipped file holds no rate")
	var c := clone_db()
	(c.miso[""]["drop_rates"] as Dictionary)["subtype_rates"] = {"Etc/Monster Drop": {"chance": 0.4}}
	var r := _validate(c)
	expect_new(r, "error", "drop_policy", "misostory", "drop_rates", "subtype_rates: a chance, quantity or meso value outside the canonical drop records")
	expect_new(r, "error", "drop_policy", "misostory", "drop_rates", "holds the number 0.4")
	var dist := clone_db()
	(dist.miso[""]["drop_rates"] as Dictionary)["meso_amount_distribution"]["value"] = "normal"
	expect_new(_validate(dist), "error", "drop_policy", "misostory", "drop_rates", "meso_amount_distribution.value must be")
