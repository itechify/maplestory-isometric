extends DataValidationTestCase
## The drop records against the dated captures themselves (Iteration Three brief "Drop Testing"; contract C1;
## decisions D3-9, D3-11, D3-12): membership is exactly MeowDB's community list "Drops (MS Classic)" for all seven owners
## (every entry, votes recorded, none excluded), no MSEA-only item is a member, every rarity is Henesys.gg's label from
## the capture, every chance category follows the rule from the item's MeowDB type and subtype, and Red Cloth Pants is
## the item MeowDB's own drop entry carries. The captures (tools/meowdb, tools/henesys captures) are read from the folder
## next to the project, as the validator reads them (scripts/test.sh mirrors them next to an ISOLATE copy). Then
## corrupted copies of the shipped records must fail DropChecks with the finding that names the corruption.

const OWNERS := ["1", "2", "3", "4", "5", "9", "0000001"]
const RARITY := "tools/henesys/captures/item_rarity.json"


func parity_keys() -> Dictionary:
	# Membership, rarity and category are checked entry by entry against the dated captures, so those tests prove
	# each drop:<owner>/<key>.
	var monster_drops: Array = []
	var box_drops: Array = []
	for owner_id in OWNERS:
		for e in db().drop_table(owner_id).entries:
			(box_drops if owner_id == "0000001" else monster_drops).append("drop:%s/%s" % [owner_id, String(e.key)])
	return {
		"test_membership_is_exactly_meowdbs_community_list": ["mechanic:drop-membership-authoritative",
			"monster:1", "monster:2", "monster:3", "monster:4", "monster:5", "monster:9", "breakable:0000001"]
			+ monster_drops + box_drops,
		"test_no_msea_only_item_is_a_member": ["mechanic:msea-reference-excluded"],
		"test_rarity_is_henesys_label_from_the_capture": ["mechanic:drop-rarity-from-henesys"] + monster_drops + box_drops,
		"test_every_member_category_follows_the_rule": ["mechanic:drop-category-derivation"] + monster_drops + box_drops,
		"test_red_cloth_pants_is_meowdbs_own_item": ["mechanic:drop-item-ids-resolve"],
		"test_member_removed_or_added_fails": ["mechanic:drop-membership-authoritative"],
		"test_a_record_quoting_another_owners_page_fails": ["mechanic:drop-membership-authoritative"],
		"test_membership_must_be_the_newest_capture_of_the_page": ["mechanic:drop-membership-authoritative"],
		"test_a_dropped_meowdb_meso_report_fails": ["mechanic:meso-amount-source", "meso:2"],
		"test_msea_item_added_as_member_fails": ["mechanic:msea-reference-excluded"],
		"test_wrong_rarity_fails": ["mechanic:drop-rarity-from-henesys"],
		"test_wrong_category_fails": ["mechanic:drop-category-derivation"],
		"test_unknown_item_id_is_an_error_not_a_crash": ["mechanic:drop-item-ids-resolve"],
		"test_progression_item_that_never_rolls_is_a_blocker": ["quest:1011", "mechanic:unresolved-drops-visible"],
		"test_an_incomplete_chance_table_fails_the_data_validator": ["mechanic:no-placeholder-drop-rates", "mechanic:drop-chance-bounds"],
	}


func _root() -> String:
	return ProvenanceChecks.new(db(), ValidationReport.new()).repo_root()


## A capture file's text, from tools/<site>/captures next to the project.
func _capture(rel: String) -> String:
	var text := FileAccess.get_file_as_string(_root().path_join(rel))
	if text == "":
		fail("capture %s not found under %s" % [rel, _root()])
	return text


## The page text of a MeowDB capture with its lines trimmed (what the builder compares member blocks against).
func _page(rel: String) -> String:
	var lines := PackedStringArray()
	for l in DropSourceCaptures.page_text(_root().path_join(rel)).split("\n"):
		lines.append(String(l).strip_edges())
	return "\n".join(lines)


func _rarity() -> Dictionary:
	var j: Variant = JSON.parse_string(_capture(RARITY))
	return j if j is Dictionary else {}


func _capture_of(owner_id: String) -> String:
	return DropChecks.membership_capture(db().drop_table(owner_id))


func test_membership_is_exactly_meowdbs_community_list() -> void:
	for owner_id in OWNERS:
		var table := db().drop_table(owner_id)
		var cap := _capture_of(owner_id)
		var want := "tools/meowdb/captures/%s" % ("breakable_%s.txt" % owner_id if owner_id == "0000001" else "monster_%s" % owner_id)
		assert_true(cap.begins_with(want), "drops/%s: membership is read from the live page capture %s, got %s" % [owner_id, want, cap])
		assert_eq(table.membership_authority, "MeowDB MS Classic", "drops/%s (D3-11)" % owner_id)
		assert_eq(table.membership_list, "Drops (MS Classic)")
		var list := DropSourceCaptures.community_list(_root().path_join(cap))
		assert_true(bool(list.ok), "drops/%s: %s" % [owner_id, str(list.get("error", ""))])
		var names := PackedStringArray(table.entries.map(func(e: Dictionary) -> String: return e.name))
		var listed := PackedStringArray((list.entries as Array).map(func(x: Dictionary) -> String: return x.name))
		assert_eq(names, listed, "drops/%s: every entry of MeowDB's list, nothing else, in page order" % owner_id)
		# Independently of the parser: each member's block is verbatim in the page, with the votes it shows.
		var page := _page(cap)
		for e in table.entries:
			var ms: Dictionary = e.membership_source
			assert_true(page.contains(ms.raw_value), "drops/%s %s: block quoted from the live page" % [owner_id, e.key])
			var lines := String(ms.raw_value).split("\n")
			assert_eq([str(int(ms.votes.up)), str(int(ms.votes.down))], [lines[3], lines[5]], "%s votes recorded" % e.key)
			assert_eq(int(ms.votes.score), int(ms.votes.up) - int(ms.votes.down))
	# Nothing is excluded for votes: Monster Card (+1 -1) and Opal Ore (+0 -1) stay members of the Blue Snail's list.
	var blue := PackedStringArray(db().drop_table("3").entries.map(func(e: Dictionary) -> String: return e.name))
	for name in ["Monster Card", "Opal Ore", "Silver Ore"]:
		assert_true(blue.has(name), "Blue Snail keeps %s whatever its votes" % name)
	assert_eq(PackedStringArray(db().drop_table("0000001").entries.map(func(e: Dictionary) -> String: return e.name)),
		PackedStringArray(["Old Wooden Board", "Rusty Screw", "Apple", "Egg"]))


func test_no_msea_only_item_is_a_member() -> void:
	var seen := 0
	for owner_id in OWNERS:
		var table := db().drop_table(owner_id)
		var list := DropSourceCaptures.community_list(_root().path_join(_capture_of(owner_id)))
		var community := PackedStringArray((list.entries as Array).map(func(x: Dictionary) -> String: return x.name))
		var names := PackedStringArray(table.entries.map(func(e: Dictionary) -> String: return e.name))
		for m in list.msea:
			if community.has(m):
				continue
			seen += 1
			assert_false(names.has(m), "drops/%s: %s is only on MeowDB's MSEA reference list: never a member" % [owner_id, m])
		var ref: Variant = table.get("meowdb_reference", null)
		if ref is Dictionary:
			assert_eq(PackedStringArray((ref.msea_reference as Array).map(func(x: Dictionary) -> String: return x.name)), list.msea,
				"drops/%s keeps the MSEA list as reference" % owner_id)
	assert_true(seen >= 10, "the MSEA lists name items the community lists do not (Cape scrolls, Iron Mace, ...): %d" % seen)
	var snail := PackedStringArray(db().drop_table("2").entries.map(func(e: Dictionary) -> String: return e.name))
	for name in ["Cape Magic Def. Scroll: Intermediate", "Red Miniskirt", "Ice Jeans"]:
		assert_false(snail.has(name), "the Snail never drops the MSEA-only %s" % name)


func test_rarity_is_henesys_label_from_the_capture() -> void:
	var cap := _rarity()
	assert_eq(cap.get("url", ""), "https://henesys.gg/loot")
	var rare := []
	for owner_id in OWNERS:
		for e in db().drop_table(owner_id).entries:
			var row: Variant = (cap.items as Dictionary).get(e.name, null)
			assert_true(row is Dictionary, "%s has a Henesys.gg row" % e.name)
			assert_true(e.rarity is Dictionary, "drops/%s %s has a rarity" % [owner_id, e.key])
			assert_eq(e.rarity.label, row.rarity, "drops/%s %s rarity" % [owner_id, e.key])
			assert_eq([e.rarity.source.authority, e.rarity.source.url, e.rarity.source.read_at, e.rarity.source.capture, e.rarity.source.row],
				["Henesys.gg", cap.url, cap.read_at, RARITY, row.row], "drops/%s %s cites the capture" % [owner_id, e.key])
			if e.rarity.label != "Common":
				rare.append("%s/%s=%s" % [owner_id, e.item_id, e.rarity.label])
	assert_eq(rare, ["5/143=Rare"], "every member is Common except the Red Snail's Overall Armor DEF Scroll: Intermediate")


## The table category rule, written out again here (independent of DropChecks.expected_category).
static func _rule(item: Dictionary, gated: bool) -> String:
	var t := str(item.get("type", ""))
	var s := str(item.get("subtype", ""))
	if t == "Etc" and gated:
		return "etc_quest_gated"
	if t == "Etc":
		return "etc_own_leftover" if s == "Monster Drop" else "etc_other"
	if t == "Use":
		return "use_scroll" if s == "Scroll" else "use_consumable"
	return {"Equip": "equip", "Setup": "setup"}.get(t, "")


func test_every_member_category_follows_the_rule() -> void:
	var by_cat := {}
	for owner_id in OWNERS:
		for e in db().drop_table(owner_id).entries:
			var item := db().item(String(e.item_id))
			assert_false(item.is_empty(), "drops/%s %s resolves to a local item" % [owner_id, e.key])
			var gated: bool = e.quest_gate is Dictionary
			assert_eq([e.category_inputs.item_type, e.category_inputs.item_subtype, e.category_inputs.quest_gated],
				[item.get("type"), item.get("subtype"), gated], "drops/%s %s category inputs are the item's" % [owner_id, e.key])
			assert_eq(e.chance_category, _rule(item, gated), "drops/%s %s (%s / %s)" % [owner_id, e.key, item.get("type"), item.get("subtype")])
			by_cat[e.chance_category] = int(by_cat.get(e.chance_category, 0)) + 1
	assert_eq(by_cat, {"etc_own_leftover": 6, "etc_quest_gated": 2, "etc_other": 14, "use_consumable": 17, "use_scroll": 1, "equip": 46},
		"86 members by category")
	# The gate rule (D3-9): Board and Screw (MeowDB "Quest Item", asked for by Pio's 1012) are gated; Monster Card
	# ("Quest Item" no Maple Island quest asks for) and Jr. Sentinel Shellpiece ("Monster Drop") are not.
	var box := db().drop_table("0000001")
	for e in box.entries:
		assert_eq(e.quest_gate.quest_id if e.quest_gate is Dictionary else "", "1012" if e.key in ["old-wooden-board", "rusty-screw"] else "", e.key)
	var card: Dictionary = db().drop_table("3").entries.filter(func(e: Dictionary) -> bool: return e.name == "Monster Card")[0]
	assert_eq([card.quest_gate, card.chance_category], [null, "etc_other"], "Monster Card is a plain other Etc")
	var shell: Dictionary = db().drop_table("1").entries[0]
	assert_eq([shell.item_id, shell.quest_gate, shell.chance_category], ["347", null, "etc_own_leftover"], "Jr. Sentinel Shellpiece")


func test_red_cloth_pants_is_meowdbs_own_item() -> void:
	var pants: Array = db().drop_table("5").entries.filter(func(e: Dictionary) -> bool: return e.name == "Red Cloth Pants")
	assert_eq(pants.size(), 1)
	var e: Dictionary = pants[0]
	assert_eq(e.item_id, "1168", "the id MeowDB's own Red Snail drop entry carries")
	assert_eq(e.item_resolution.method, "meowdb_drop_entry")
	assert_eq(e.item_resolution.candidates, ["1168", "1177"], "two local items share the name")
	assert_true(String(e.item_resolution.evidence).contains("api/drops?monsterId=5"), e.item_resolution.evidence)
	for owner_id in OWNERS:
		for x in db().drop_table(owner_id).entries:
			if x.name != "Red Cloth Pants":
				assert_eq([x.item_resolution.state, x.item_resolution.method, x.item_resolution.candidates],
					["resolved", "exact_name", [x.item_id]], "drops/%s %s: the only local item with its name" % [owner_id, x.key])


# --- negative: corrupted copies fail -----------------------------------------------------------------------

func _with_entries(owner_id: String, edit: Callable) -> ContentDB:
	var c := clone_db()
	var rec: Dictionary = c.canonical.drops[owner_id]
	edit.call(rec)
	reindex(c)
	return c


func test_member_removed_or_added_fails() -> void:
	var r := run_validator(_with_entries("2", func(rec: Dictionary) -> void: (rec.entries as Array).remove_at(1)))
	expect_new(r, "error", "drop_policy", "drops", "2", "membership is not MeowDB's community list")
	var r2 := run_validator(_with_entries("4", func(rec: Dictionary) -> void:
		var e: Dictionary = (rec.entries[0] as Dictionary).duplicate(true)
		e.key = "blue-potion"
		e.name = "Blue Potion"
		e.item_id = null
		e.item_resolution = {"state": "not_in_snapshot", "method": "none", "candidates": [], "evidence": "test"}
		e.membership_source.raw_value = "Blue Potion\nPotion\n▲\n1\n▼\n0"
		e.membership_source.votes = {"up": 1, "down": 0, "score": 1}
		e.rarity = null
		e.chance_category = null
		e.category_inputs = {"item_type": null, "item_subtype": null, "quest_gated": false, "item": null}
		(rec.entries as Array).append(e)))
	expect_new(r2, "error", "drop_policy", "drops", "4", "not on the list [\"Blue Potion\"]")


func test_msea_item_added_as_member_fails() -> void:
	var r := run_validator(_with_entries("2", func(rec: Dictionary) -> void:
		var e: Dictionary = (rec.entries[6] as Dictionary).duplicate(true)  # an equip
		e.key = "ice-jeans"
		e.name = "Ice Jeans"
		e.item_id = "1195"
		e.item_resolution = {"state": "resolved", "method": "exact_name", "candidates": ["1195"], "evidence": "test"}
		e.membership_source.raw_value = "Ice Jeans\nLv 17 · Any\n▲\n1\n▼\n0"
		e.membership_source.votes = {"up": 1, "down": 0, "score": 1}
		e.category_inputs.item_subtype = "Bottom"
		(rec.entries as Array).append(e)))
	expect_new(r, "error", "drop_policy", "drops", "2", "'Ice Jeans' is only on MeowDB's MSEA reference list")


func test_wrong_rarity_fails() -> void:
	var r := run_validator(_with_entries("2", func(rec: Dictionary) -> void: rec.entries[1].rarity.label = "Rare"))
	expect_new(r, "error", "drop_policy", "drops", "2", "'Snail Shell': rarity \"Rare\", Henesys.gg's capture says Common")
	var r2 := run_validator(_with_entries("2", func(rec: Dictionary) -> void: rec.entries[1].rarity = null))
	expect_new(r2, "error", "drop_policy", "drops", "2", "'Snail Shell': rarity \"\", Henesys.gg's capture says Common")
	expect_new(r2, "warning", "drop_unresolved", "drops", "2", "'Snail Shell' never rolls: rarity unresolved")
	var r3 := run_validator(_with_entries("2", func(rec: Dictionary) -> void: rec.entries[1].rarity.label = "Legendary"))
	expect_new(r3, "error", "drop_record", "drops", "2", "rarity must be null or {label: one of")


func test_wrong_category_fails() -> void:
	var r := run_validator(_with_entries("2", func(rec: Dictionary) -> void: rec.entries[0].chance_category = "etc_own_leftover"))
	expect_new(r, "error", "drop_policy", "drops", "2", "entry 'bronze-ore': chance_category \"etc_own_leftover\", the rule gives \"etc_other\"")
	var r2 := run_validator(_with_entries("0000001", func(rec: Dictionary) -> void: rec.entries[0].quest_gate = null))
	expect_new(r2, "error", "drop_policy", "drops", "0000001", "the quest-gate rule (D3-9) gives quest 1012, the record says no gate")


func test_unknown_item_id_is_an_error_not_a_crash() -> void:
	var r := run_validator(_with_entries("2", func(rec: Dictionary) -> void:
		rec.entries[1].item_id = BOGUS
		rec.entries[1].item_resolution.candidates = [BOGUS]))
	expect_new(r, "error", "drop_policy", "drops", "2", "item %s is not a local MeowDB item" % BOGUS)
	assert_eq(DropRates.effective_entries("2", _with_entries("2", func(rec: Dictionary) -> void: rec.entries[1].item_id = BOGUS))[1].excluded,
		DropRates.UNKNOWN_ITEM, "the runtime never rolls it")


func test_progression_item_that_never_rolls_is_a_blocker() -> void:
	# Blue Snail Shell (349) is what Biggs's quest 1011 collects; without a rarity it never rolls.
	var r := run_validator(_with_entries("3", func(rec: Dictionary) -> void: rec.entries[0].rarity = null))
	expect_new(r, "error", "drop_policy", "drops", "3", "item 349 is needed by quest [\"1011\"] but never rolls here")


func test_a_record_quoting_another_owners_page_fails() -> void:
	# The Blue Snail's record carrying the Snail's members, cited from the Snail's own capture: the list "equals" the
	# capture it cites, but it is not the Blue Snail's page.
	var c := clone_db()
	var snail: Dictionary = (c.canonical.drops["2"] as Dictionary).duplicate(true)
	var rec: Dictionary = c.canonical.drops["3"]
	rec.entries = snail.entries
	rec.provenance.membership = snail.provenance.membership
	reindex(c)
	var r := run_validator(c)
	expect_new(r, "error", "drop_policy", "drops", "3",
		"membership capture \"tools/meowdb/captures/monster_2.txt\" is not the monster's own MeowDB page capture")
	# One entry citing another page than the rest of its record.
	var r2 := run_validator(_with_entries("3", func(rec3: Dictionary) -> void:
		rec3.entries[2].membership_source.url = "https://meowdb.com/msclassic/monsters/2"))
	expect_new(r2, "error", "drop_policy", "drops", "3",
		"entry 'amethyst-ore'.membership_source must cite the owner's page https://meowdb.com/msclassic/monsters/3")
	var r3 := run_validator(_with_entries("0000001", func(box: Dictionary) -> void:
		box.provenance.membership.capture = "tools/meowdb/captures/monster_2.txt"))
	expect_new(r3, "error", "drop_policy", "drops", "0000001", "provenance.membership must cite the owner's page https://meowdb.com/msclassic/breakables/0000001")


func test_a_dropped_meowdb_meso_report_fails() -> void:
	# The Snail's page shows "Mesos: 2 per kill | 1 report": a record without it would roll the level formula instead.
	var r := run_validator(_with_entries("2", func(rec: Dictionary) -> void:
		rec.meso.amount_state = "not_reported"
		rec.meso.min = null
		rec.meso.max = null
		rec.meso.amount_source = null
		rec.provenance.erase("mesos.amount")))
	expect_new(r, "error", "drop_policy", "drops", "2",
		"meso: tools/meowdb/captures/monster_2.txt shows MeowDB's player report 'Mesos: 2 per kill | 1 report', but amount_state is \"not_reported\"")
	# A newer source in sources_compared (a later cache read with no report) decides instead: no error.
	var r2 := run_validator(_with_entries("2", func(rec: Dictionary) -> void:
		rec.meso.amount_state = "not_reported"
		rec.meso.min = null
		rec.meso.max = null
		rec.meso.amount_source = null
		rec.provenance.erase("mesos.amount")
		rec.meso.sources_compared[1].retrieved_at = "2026-11-01T00:00:00Z"))
	assert_eq(r2.matching("drop_policy", "drops", "2", "error").size(), 0, str(r2.matching("drop_policy", "drops", "2", "error")))
	var r3 := run_validator(_with_entries("2", func(rec: Dictionary) -> void:
		rec.meso.amount_source.raw_value = "Mesos: 3 per kill | 1 report"
		rec.meso.min = 3
		rec.meso.max = 3))
	expect_new(r3, "error", "drop_policy", "drops", "2", "meso.amount_source.raw_value \"Mesos: 3 per kill | 1 report\" is not in tools/meowdb/captures/monster_2.txt")


## A copy of every tools/<site>/captures folder under a private root (the validator's repo_root option).
func _captures_copy() -> String:
	var root := ProjectSettings.globalize_path("user://_tests/drop_captures_%d_%d" % [Time.get_ticks_usec(), randi()])
	for site in DirAccess.get_directories_at(_root().path_join("tools")):
		var src := _root().path_join("tools").path_join(site).path_join("captures")
		if not DirAccess.dir_exists_absolute(src):
			continue
		var dst := root.path_join("tools").path_join(site).path_join("captures")
		DirAccess.make_dir_recursive_absolute(dst)
		for f in DirAccess.get_files_at(src):
			DirAccess.copy_absolute(src.path_join(f), dst.path_join(f))
	return root


func _remove_tree(dir: String) -> void:
	for d in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func test_membership_must_be_the_newest_capture_of_the_page() -> void:
	# A second capture of the Blue Snail's page (monster_3.txt beside the cited monster_3.json): newer, the record must
	# be rebuilt from it (tools/sources/captures.mjs keeps the newest); older, nothing changes.
	var json: Dictionary = JSON.parse_string(_capture("tools/meowdb/captures/monster_3.json"))
	for case in [["2026-11-01T00:00:00Z", true], ["2026-10-01T00:00:00.000+02:00", false]]:
		var root := _captures_copy()
		var f := FileAccess.open(root.path_join("tools/meowdb/captures/monster_3.txt"), FileAccess.WRITE)
		f.store_string("URL: %s\nREAD_AT: %s\nMETHOD: test copy\n---\n%s\n%s" % [json.url, case[0], json.head, json.drops])
		f.close()
		var r := run_validator(clone_db(), {"repo_root": root})
		if case[1]:
			expect_new(r, "error", "drop_policy", "drops", "3",
				"membership capture tools/meowdb/captures/monster_3.json is not the newest dated capture of https://meowdb.com/msclassic/monsters/3")
		else:
			assert_eq(r.matching("drop_policy", "drops", "3", "error").size(), 0, "an older second capture changes nothing: %s" % str(r.matching("drop_policy", "drops", "3", "error")))
		_remove_tree(root)
	assert_true(is_nan(DropSourceCaptures.iso_seconds("2026-10-05")), "a date without a time is not ordered")
	assert_eq(DropSourceCaptures.iso_seconds("2026-10-05T09:30:00+02:00"), DropSourceCaptures.iso_seconds("2026-10-05T07:30:00Z"), "zones")


func test_an_incomplete_chance_table_fails_the_data_validator() -> void:
	var c := clone_db()
	var rates: Dictionary = c.miso[""]["drop_rates"]
	(rates.chance_table as Dictionary).erase("setup")
	rates.chance_table.equip.Common = 1.5
	var r := run_validator(c)
	expect_new(r, "error", "drop_policy", "misostory", "drop_rates", "chance_table.setup is missing")
	expect_new(r, "error", "drop_policy", "misostory", "drop_rates", "chance_table.equip.Common must be a chance in [0, 1]")
