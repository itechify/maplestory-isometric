extends TestCase
## DropChance: the exact readers the validator uses to re-check every raw drop value (brief "Probability Handling":
## keep the raw value, normalize it, document and test the conversion; reject impossible probabilities, a wrong
## percentage normalization and integer truncation; never confuse 1/N with N% or 0.01 with 1%).


func parity_keys() -> Dictionary:
	return {
		"test_kurodb_percentages_from_the_captures": ["mechanic:drop-chance-parsing"],
		"test_traps_truncation_and_double_division": ["mechanic:drop-chance-parsing"],
		"test_one_over_n_is_never_n_percent": ["mechanic:drop-chance-parsing"],
		"test_impossible_values_are_rejected": ["mechanic:drop-chance-bounds"],
		"test_meso_rows_and_amounts": ["mechanic:meso-chance-source", "mechanic:meso-amount-source"],
		"test_every_shipped_raw_value_reads_back_exactly": ["mechanic:drop-chance-parsing"],
	}


func _ok(r: Dictionary, what: String) -> bool:
	assert_true(bool(r.ok), "%s: %s" % [what, str(r.get("error", ""))])
	return bool(r.ok)


func test_kurodb_percentages_from_the_captures() -> void:
	var cases := {
		"26% base | Qty 1": 0.26, "2.00% base | Qty 1": 0.02, "0.90% base | Qty 1": 0.009, "0.13% base | Qty 1": 0.0013,
		"0.0800% base | Qty 1": 0.0008, "0.0700% base | Qty 1": 0.0007, "0.0300% base | Qty 1": 0.0003,
		"12.50% base | Qty 1": 0.125, "100% base | Qty 1": 1.0, "1.00% base | Qty 1": 0.01, "0.0500% base | Qty 1": 0.0005,
	}
	for raw in cases:
		var r := DropChance.parse_kuro_percent(raw)
		if _ok(r, raw):
			assert_near(float(r.probability), float(cases[raw]), 1e-15, raw)
			assert_eq([r.qty_min, r.qty_max, r.quest, r.meso], [1, 1, "", false], raw)
			assert_eq(r.conversion, "%s / 100" % raw.get_slice("%", 0), raw)
	var q := DropChance.parse_kuro_percent("100.00% base | Qty 1 | Quest 1035")
	if _ok(q, "quest row"):
		assert_eq([q.probability, q.quest, q.qty_min], [1.0, "1035", 1])
	var id_row := DropChance.parse_kuro_percent("100% base | Qty 1 | Quest 1008 | ID 2000")
	if _ok(id_row, "item-page row"):
		assert_eq([id_row.quest, id_row.source_id], ["1008", "2000"])
	var exact := DropChance.parse_kuro_percent("0.0700% base | Qty 1")
	assert_eq([exact.numerator, exact.denominator], [700, 1000000], "exact digits, no float on a partial string")
	var ranged := DropChance.parse_kuro_percent("5% base | Qty 1-3")
	assert_eq([ranged.qty_min, ranged.qty_max], [1, 3])


func test_traps_truncation_and_double_division() -> void:
	# "0.90%" is 0.009: not 0 (integer truncation), not 0.9 (percent not divided), not 0.00009 (divided twice).
	var p := float(DropChance.parse_kuro_percent("0.90% base | Qty 1").probability)
	assert_true(p > 0.0, "never truncated to 0")
	assert_near(p, 0.009, 1e-15)
	assert_ne(p, 0.9)
	assert_ne(p, 0.00009)
	# "1.00%" is 0.01, and "0.01%" is 0.0001.
	assert_near(float(DropChance.parse_kuro_percent("1.00% base | Qty 1").probability), 0.01, 1e-15)
	assert_near(float(DropChance.parse_kuro_percent("0.01% base | Qty 1").probability), 0.0001, 1e-15)


func test_one_over_n_is_never_n_percent() -> void:
	var r := DropChance.parse_reactor_chance_value("Chance value 4")
	if _ok(r, "Chance value 4"):
		assert_eq([r.n, r.probability, r.quest], [4, 0.25, ""])
		assert_true(String(r.conversion).contains("interpretation"), "1/N is labelled an interpretation (D3-7)")
	var q := DropChance.parse_reactor_chance_value("Chance value 1 | Quest 1008")
	if _ok(q, "Chance value 1 | Quest 1008"):
		assert_eq([q.probability, q.quest], [1.0, "1008"])
	assert_false(bool(DropChance.parse_kuro_percent("Chance value 4").ok), "a reactor value is not a percentage")
	assert_false(bool(DropChance.parse_reactor_chance_value("4% base | Qty 1").ok), "a percentage is not a reactor value")
	assert_eq(DropChance.parse_by_format("reactor_chance_value", "Chance value 30").probability, 1.0 / 30.0)
	assert_false(bool(DropChance.parse_by_format("percent", "4% base").ok), "unknown format")


func test_impossible_values_are_rejected() -> void:
	for raw in ["-5% base | Qty 1", "150% base | Qty 1", "100.01% base | Qty 1", "% base", "abc", "", "NaN% base",
			"1e2% base", "2.00% base |", "2.00% base | Qty 0", "2.00% base | Qty 3-1", "2.00% base | Qty 1 | Qty 1",
			"2.00% base | Weekend", "40% base | Meso drop | Qty 1", "2,00% base | Qty 1"]:
		assert_false(bool(DropChance.parse_kuro_percent(raw).ok), "rejected: %s" % raw)
	for raw in ["Chance value 0", "Chance value -1", "Chance value 1.5", "Chance value", "Chance value 4 | Event", "chance 4"]:
		assert_false(bool(DropChance.parse_reactor_chance_value(raw).ok), "rejected: %s" % raw)
	assert_false(bool(DropChance.parse_kuro_percent(null).ok))
	assert_false(bool(DropChance.parse_reactor_chance_value(4).ok))


func test_meso_rows_and_amounts() -> void:
	var m := DropChance.parse_kuro_percent("40% base | Meso drop")
	if _ok(m, "meso row"):
		assert_eq([m.meso, m.probability, m.has_qty], [true, 0.4, false])
	var hs := DropChance.parse_meso_amount("Mesos: 4-6")
	assert_eq([hs.state, hs.min, hs.max], ["resolved", 4, 6])
	assert_eq(DropChance.parse_meso_amount("Mesos: 4").min, 4)
	assert_eq(DropChance.parse_meso_amount("Mesos: ?").state, "unresolved", "Hidden Street's '?' stays unresolved")
	var report := DropChance.parse_meso_amount("Mesos: 2 per kill | 1 report")
	assert_eq([report.state, report.min, report.max], ["resolved", 2, 2], "MeowDB's report line gives an amount, never a chance")
	assert_false(report.has("probability"))
	for raw in ["Mesos: 6-4", "Mesos: -1", "Mesos: 4.5", "Mesos:", "40% base | Meso drop"]:
		assert_false(bool(DropChance.parse_meso_amount(raw).ok), "rejected: %s" % raw)


func test_every_shipped_raw_value_reads_back_exactly() -> void:
	var seen := 0
	for owner_id in db().ids("drops"):
		var table := db().drop_table(owner_id)
		for e in table.entries:
			if e.chance_source is Dictionary:
				var r := DropChance.parse_by_format(e.chance_source.format, e.chance_source.raw_value)
				if _ok(r, "drops/%s %s" % [owner_id, e.key]):
					assert_near(float(e.probability), float(r.probability), 1e-15, "drops/%s %s" % [owner_id, e.key])
					seen += 1
		if table.meso is Dictionary:
			var c := DropChance.parse_kuro_percent(table.meso.chance_source.raw_value)
			assert_true(bool(c.ok) and bool(c.meso), "drops/%s meso chance is a Meso drop row" % owner_id)
			var a := DropChance.parse_meso_amount(table.meso.amount_source.raw_value)
			assert_eq([a.min, a.max], [int(table.meso.min), int(table.meso.max)], "drops/%s meso amount" % owner_id)
	assert_true(seen >= 22, "every resolved chance read back (%d)" % seen)
