extends DataValidationTestCase
## Contract C1 pending_kuro_candidates: a KuroDB row that may be a member under another name, waiting for a hand read
## of its item page (decision D3-8). It never rolls, its member stays unresolved, and it is neither a KuroDB-only row
## nor anybody's chance source. The shipped Orange Mushroom record holds one while KuroDB item 2040705 is unread; each
## test corrupts a copy of a record with one and expects the finding that names the corruption.


func parity_keys() -> Dictionary:
	var keys := ["canon:kuro-only-excluded", "canon:unresolved-visible"]
	return {
		"test_a_pending_member_must_stay_unresolved": keys,
		"test_a_pending_row_is_not_also_kuro_only_or_a_chance_source": keys,
	}


## A drop record (the shipped one holding a pending row, else the first v2 monster record given one) and its row.
func _with_pending(c: ContentDB) -> Dictionary:
	for id in c.ids("drops"):
		var rec: Dictionary = c.canonical.drops[id]
		if not ValidationUtil.as_array(rec.get("pending_kuro_candidates", [])).is_empty():
			return {"id": id, "rec": rec, "row": rec.pending_kuro_candidates[0]}
	var mid := first_id_where(c, "drops", _monster_with_unresolved, "v2 monster record with an unresolved member")
	var rec2: Dictionary = c.canonical.drops[mid]
	var member: Dictionary = ValidationUtil.as_array(rec2.entries).filter(func(e: Dictionary) -> bool: return e.chance_state == "unresolved")[0]
	var row := {"kuro_item_id": "9999999", "name": "Synthetic Candidate", "raw_value": "0.0100% base | Qty 1", "member": member.key,
		"read": "KuroDB item page 9999999", "reason": "test row", "decision": "D3-8"}
	rec2["pending_kuro_candidates"] = [row]
	return {"id": mid, "rec": rec2, "row": row}


static func _monster_with_unresolved(r: Dictionary) -> bool:
	if not DropRecordChecks.is_v2(r) or str((r.get("owner", {}) as Dictionary).get("kind", "")) != "monster":
		return false
	return ValidationUtil.as_array(r.get("entries", [])).any(func(e: Variant) -> bool: return e is Dictionary and e.get("chance_state", "") == "unresolved")


func _member(rec: Dictionary, key: String) -> Dictionary:
	for e in rec.entries:
		if e.key == key:
			return e
	fail("no entry %s" % key)
	return {}


func test_the_shipped_pending_rows_are_valid() -> void:
	for f in baseline().findings:
		if f.severity == "error":
			assert_false(String(f.message).contains("pending_kuro_candidates"), "no error about the shipped pending rows: %s" % f.message)
	var c := clone_db()
	var p := _with_pending(c)
	reindex(c)
	var r := run_validator(c)
	expect_no_new(r, "drop_record")
	expect_no_new(r, "drop_policy")
	assert_true(String(p.row.member) != "", "a pending row names its member")
	var said := 0
	var want := "chance pending: KuroDB item page %s is not read yet" % p.row.kuro_item_id
	for f in r.findings:
		if f.check == "drop_unresolved" and f.id == p.id and String(f.message).contains(want):
			said += 1
	assert_eq(said, 1, "the member's warning says its chance is a pending read, not a missing value")


func test_a_pending_member_must_stay_unresolved() -> void:
	var c := clone_db()
	var p := _with_pending(c)
	var e := _member(p.rec, p.row.member)
	e["chance_state"] = "resolved"
	e["probability"] = 0.0003
	reindex(c)
	expect_new(run_validator(c), "error", "drop_record", "drops", p.id, "must stay unresolved with no chance_source while the row is pending")
	var c2 := clone_db()
	var p2 := _with_pending(c2)
	p2.row["member"] = BOGUS
	reindex(c2)
	expect_new(run_validator(c2), "error", "drop_record", "drops", p2.id, "names member '%s', which is no entry key" % BOGUS)
	var c3 := clone_db()
	var p3 := _with_pending(c3)
	p3.row.erase("read")
	reindex(c3)
	expect_new(run_validator(c3), "error", "drop_record", "drops", p3.id, "must be {kuro_item_id, name, raw_value, member, read, reason}")
	var c4 := clone_db()
	var p4 := _with_pending(c4)
	p4.rec["pending_kuro_candidates"] = "not a list"
	reindex(c4)
	expect_new(run_validator(c4), "error", "drop_record", "drops", p4.id, "pending_kuro_candidates must be a list")


func test_a_pending_row_is_not_also_kuro_only_or_a_chance_source() -> void:
	var c := clone_db()
	var p := _with_pending(c)
	(p.rec.excluded_kuro_only as Array).append({"kuro_item_id": p.row.kuro_item_id, "name": p.row.name, "raw_value": p.row.raw_value, "reason": "x"})
	reindex(c)
	expect_new(run_validator(c), "error", "drop_record", "drops", p.id, "is also an excluded_kuro_only row: a row is pending or KuroDB-only, not both")
	# Another member claiming the pending row as its chance source.
	var c2 := clone_db()
	var p2 := _with_pending(c2)
	var claimer: Dictionary = ValidationUtil.as_array(p2.rec.entries).filter(func(e: Dictionary) -> bool: return e.chance_source is Dictionary)[0]
	claimer.chance_source["kuro_item_id"] = p2.row.kuro_item_id
	claimer.chance_source["kuro_name"] = p2.row.name
	reindex(c2)
	expect_new(run_validator(c2), "error", "drop_policy", "drops", p2.id, "pending_kuro_candidates row %s (%s) is also the chance source of entry '%s'" % [
		p2.row.name, p2.row.kuro_item_id, claimer.key])
