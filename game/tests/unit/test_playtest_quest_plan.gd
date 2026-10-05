extends TestCase
## PlaytestQuestPlan (docs/runtime/PLAYTEST_HARNESS.md "Quest plans"): the every-quest scenario's knowledge of each
## quest comes from canonical data only. The NPCs, maps, kill counts and hunt maps, item sources (drop tables and the
## Wooden Box), accept items, quiz answers, setup needs and the chain list are derived and checked here against the
## canonical records, and PlaytestQuestSummary turns the per-chain reports into the per-quest table.


func parity_keys() -> Dictionary:
	return {
		"test_1005_kills_and_collects_tutorial_jr_sentinel_parts_in_000000030": ["quest:1005", "monster:1", "item:347"],
		"test_1009_hunts_three_species_at_mai": ["quest:1009", "monster:3", "monster:4", "monster:5"],
		"test_1012_items_come_from_the_wooden_box": ["quest:1012", "breakable:0000001", "item:441", "item:442"],
		"test_1002_uses_the_apple_roger_hands_over": ["quest:1002", "item:235"],
		"test_1011_collects_from_blue_snails_and_orange_mushrooms": ["quest:1011", "item:349", "item:356"],
		"test_quiz_quests_plan_their_canonical_answer": ["quest:1013", "mechanic:quiz-quests"],
		"test_chains_are_the_canonical_quest_lines": ["quest:1000", "quest:1001", "quest:1003", "quest:1004", "quest:1006",
			"quest:1007", "quest:1008", "quest:1009", "quest:1010", "quest:1013", "quest:1019"],
	}


func test_1005_kills_and_collects_tutorial_jr_sentinel_parts_in_000000030() -> void:
	var p := PlaytestQuestPlan.plan("1005", db())
	assert_true(bool(p["ok"]), "playable: %s" % p["blocked"])
	assert_eq(String(p["start"]["npc"]), "7", "Todd")
	assert_eq(String(p["end"]["npc"]), "6", "Peter")
	assert_eq(String(p["start"]["map"]), "000000030")
	assert_eq((p["kills"] as Array).size(), 1)
	var k: Dictionary = p["kills"][0]
	assert_eq(String(k["mob_id"]), "1")
	assert_eq(int(k["count"]), 3)
	assert_eq(String(k["hunt_map"]), "000000030", "the Tutorial Jr. Sentinels spawn only there")
	var it: Dictionary = p["items"][0]
	assert_eq(String(it["item_id"]), "347")
	assert_eq(int(it["count"]), 3)
	assert_true(bool(it["obtainable"]), "Jr. Sentinel Shellpiece drops: %s" % it["sources"])
	assert_eq(String((it["hunt"] as Dictionary)["owner"]), "1", "from the Tutorial Jr. Sentinel")
	assert_eq(String((it["hunt"] as Dictionary)["map"]), "000000030")
	assert_eq(int(p["rewards"]["exp"]), int(db().quest("1005")["rewards"]["exp"]), "the canonical EXP")


func test_1009_hunts_three_species_at_mai() -> void:
	var p := PlaytestQuestPlan.plan("1009", db())
	assert_true(bool(p["ok"]), str(p["blocked"]))
	var want := {}
	for o: Dictionary in db().quest("1009")["objectives"]["monster_kills"]:
		want[String(o["mob_id"])] = int(o["count"])
	assert_eq(want.size(), 3, "Blue Snail, Shroom, Red Snail")
	for k: Dictionary in p["kills"]:
		assert_eq(int(k["count"]), int(want[String(k["mob_id"])]), "count of %s" % k["mob_id"])
		assert_eq(String(k["hunt_map"]), "000000050", "%s spawns at Mai's A Split Road" % k["name"])
	assert_eq(int(p["min_level"]), int(db().quest("1009")["min_level"]))
	assert_eq(p["prerequisites"], PackedStringArray(["1006"]))
	var s := PlaytestQuestPlan.setup_for(PackedStringArray(["1009"]), db())
	assert_eq(s["complete"], PackedStringArray(["1006"]), "the setup completes 1006 first")
	assert_eq(int(s["level"]), int(p["min_level"]))
	assert_eq(String(s["map"]), "000000050")


func test_1012_items_come_from_the_wooden_box() -> void:
	var p := PlaytestQuestPlan.plan("1012", db())
	for it: Dictionary in p["items"]:
		var box := (it["sources"] as Array).filter(func(s: Dictionary) -> bool: return String(s["kind"]) == "breakable")
		assert_eq(box.size(), 1, "%s comes from a breakable: %s" % [it["item_id"], it["sources"]])
		var src: Dictionary = box[0]
		assert_eq(String(src["owner"]), "0000001", "the Wooden Box")
		assert_true((src["maps"] as PackedStringArray).has("000001010"), "boxes stand in Amherst: %s" % src["maps"])
		# Gated to 1012 (C1) or not: for 1012 itself the source is obtainable once a chance is resolved.
		if src.get("chance") != null and float(src["chance"]) > 0.0:
			assert_true(bool(src["obtainable"]), "obtainable for 1012: %s" % src)
			assert_eq(String((it["hunt"] as Dictionary)["kind"]), "breakable")
	assert_eq(String(p["start"]["npc"]), "18", "Pio")


func test_schema_v2_drop_entries_give_chance_gate_and_obtainability() -> void:
	# Contract C1 records (the drops package's schema v2; the base data is still v1, so the plan's v2 path is proved
	# here on a synthetic Wooden Box table shaped like C1).
	var table := {"schema_version": 2, "owner": {"kind": "breakable", "id": "0000001", "name": "Wooden Box"}, "entries": [
		{"key": "rusty-screw", "item_id": "441", "chance_state": "resolved", "probability": 1.0,
			"quest_gate": {"quest_id": "1012", "basis": "C1 quest-gate rule"}},
		{"key": "apple", "item_id": "236", "chance_state": "resolved", "probability": 0.25, "quest_gate": null},
		{"key": "egg", "item_id": "237", "chance_state": "unresolved", "probability": null, "quest_gate": null},
		{"key": "unknown", "item_id": null, "chance_state": "unresolved", "probability": null, "quest_gate": null}]}
	var screw := PlaytestQuestPlan._source_row("0000001", table, "441", db())
	assert_eq(int(screw["schema"]), 2)
	assert_near(float(screw["chance"]), 1.0, 1e-9, "the resolved probability")
	assert_eq(String(screw["quest_gate"]), "1012", "the C1 gate")
	var apple := PlaytestQuestPlan._source_row("0000001", table, "236", db())
	assert_near(float(apple["chance"]), 0.25, 1e-9)
	assert_eq(String(apple["quest_gate"]), "", "no gate")
	var egg := PlaytestQuestPlan._source_row("0000001", table, "237", db())
	assert_true(egg["chance"] == null and String(egg["chance_state"]) == "unresolved", "an unresolved chance never rolls: %s" % egg)
	assert_eq(PlaytestQuestPlan._source_row("0000001", table, "999", db()), {}, "an item the table does not list")
	var maps := PackedStringArray(["000001010"])
	screw["maps"] = maps
	apple["maps"] = PackedStringArray()
	egg["maps"] = maps
	assert_eq(PlaytestQuestPlan.source_why(screw, "1012"), "", "obtainable for the quest it is gated to")
	assert_eq(PlaytestQuestPlan.source_why(screw, "1011"), "gated to quest 1012", "not for another quest")
	assert_eq(PlaytestQuestPlan.source_why(screw, ""), "gated to quest 1012", "nor for no quest")
	assert_eq(PlaytestQuestPlan.source_why(egg, "1012"), "unresolved chance")
	assert_eq(PlaytestQuestPlan.source_why(apple, ""), "no map has the owner")
	var zero := {"chance": 0.0, "quest_gate": "", "maps": maps}
	assert_eq(PlaytestQuestPlan.source_why(zero, ""), "chance 0")
	# best_source never picks a source that cannot supply the item.
	screw["kind"] = "breakable"
	egg["kind"] = "breakable"
	var best := PlaytestQuestPlan.best_source([egg.merged({"obtainable": false}), screw.merged({"obtainable": true})],
		"000001010", db())
	assert_near(float(best.get("chance", -1.0)), 1.0, 1e-9, "the gated, resolved entry: %s" % best)
	assert_eq(String(best.get("map", "")), "000001010")


func test_1002_uses_the_apple_roger_hands_over() -> void:
	var p := PlaytestQuestPlan.plan("1002", db())
	assert_true(bool(p["ok"]), str(p["blocked"]))
	var acc: Array = p["accept_items"]
	assert_eq(acc.size(), 1)
	assert_eq(String(acc[0]["item_id"]), "235")
	assert_true(bool(acc[0]["adaptation"]), "the hand-out is the MisoStory adaptation data/misostory/quests/1002.json")
	assert_eq(String(p["uses"][0]["item_id"]), "235")
	assert_true(bool(p["uses"][0]["from_accept"]), "the apple to use is the one handed over")


func test_1011_collects_from_blue_snails_and_orange_mushrooms() -> void:
	var p := PlaytestQuestPlan.plan("1011", db())
	var owners := {}
	for it: Dictionary in p["items"]:
		var src: Dictionary = it.get("hunt", {})
		owners[String(it["item_id"])] = String(src.get("owner", ""))
		if not src.is_empty():
			assert_true(db().has("maps", String(src["map"])), "a real map for %s" % it["item_id"])
			assert_true(PlaytestQuestPlan.hops(String(src["map"]), "000000060", db()) >= 0, "Biggs can be reached from there")
	assert_eq(String(owners.get("349", "")), "3", "Blue Snail Shell from the Blue Snail")
	assert_eq(String(owners.get("356", "")), "9", "Orange Mushroom Cap from the Orange Mushroom")
	assert_eq((p["rewards"]["random"] as Array).size(), 1, "one random group (Fruit Knife / Razor)")
	# The turn-in takes what canonical items_removed_on_completion lists (the reward check's hand-ins).
	var want: Array = []
	for it: Dictionary in db().quest("1011")["items_removed_on_completion"]["items"]:
		want.append({"item_id": String(it["item_id"]), "count": int(it["count"])})
	assert_eq(p["hand_ins"], want, "hand-ins of 1011")
	assert_eq(want.size(), 2, "Blue Snail Shell x10 and Orange Mushroom Cap x1")
	assert_eq(PlaytestQuestPlan.plan("1013", db())["hand_ins"], [], "a quiz takes nothing")


func test_quiz_quests_plan_their_canonical_answer() -> void:
	var p := PlaytestQuestPlan.plan("1013", db())
	assert_true(bool(p["ok"]), str(p["blocked"]))
	var z: Dictionary = db().quest("1013")["dialogue"]["on_completion"]["quiz"]
	assert_eq(int(p["quiz"]["index"]), int(z["correct_choice_index"]))
	assert_eq(String(p["start"]["map"]), "000001010", "Rain in Amherst")
	var s := PlaytestQuestPlan.setup_for(PlaytestQuestPlan.parse_ids("1016", db()), db())
	assert_eq(s["complete"], PackedStringArray(["1013", "1014", "1015"]), "1016 alone needs the first three quizzes")
	assert_eq(int(s["level"]), 5)


func test_chains_are_the_canonical_quest_lines() -> void:
	var specs := PackedStringArray()
	for ch: PackedStringArray in PlaytestQuestPlan.chains(db()):
		specs.append(PlaytestQuestPlan.chain_spec(ch))
	assert_eq(" ".join(specs), "1000-1001 1002 1003-1004 1005 1006,1009,1010 1007-1008 1011 1012 1013-1019")
	var n := 0
	for ch: PackedStringArray in PlaytestQuestPlan.chains(db()):
		n += ch.size()
	assert_eq(n, db().ids("quests").size(), "every canonical quest is in exactly one chain")
	assert_eq(PlaytestQuestPlan.parse_ids("1013-1015", db()), PackedStringArray(["1013", "1014", "1015"]))
	assert_eq(PlaytestQuestPlan.parse_ids("1006,1009", db()), PackedStringArray(["1006", "1009"]))
	assert_eq(PlaytestQuestPlan.parse_ids("999", db()), PackedStringArray(), "unknown quests")
	# scripts/playtest_quests.sh runs the same list (its CHAINS_DEFAULT line), when the repo is around the project:
	# game/ itself, or an ISOLATE mirror in _scratch/godot_runs/<name>/game.
	var sh := ""
	for rel in ["../scripts/playtest_quests.sh", "../../../../scripts/playtest_quests.sh"]:
		var path := ProjectSettings.globalize_path("res://").path_join(rel).simplify_path()
		if FileAccess.file_exists(path):
			sh = FileAccess.get_file_as_string(path)
			break
	if sh == "":
		print("SKIP the CHAINS_DEFAULT comparison: scripts/playtest_quests.sh is not next to this project copy")
		return
	var line := ""
	for l in sh.split("\n"):
		if l.begins_with("CHAINS_DEFAULT="):
			line = l.trim_prefix("CHAINS_DEFAULT=").trim_prefix("\"").trim_suffix("\"")
	assert_eq(line, " ".join(specs), "scripts/playtest_quests.sh's default chains")


func test_summary_reads_the_chain_reports() -> void:
	var out := ProjectSettings.globalize_path("user://_tests/quest_summary_%d_%d" % [Time.get_ticks_usec(), randi()])
	var ok_rep := {"result": "PASS", "strict": {"enabled": true, "ok": true, "since": {"step": 3}},
		"steps": [{"i": 0, "kind": "console"}, {"i": 5, "kind": "play"}], "totals": {"game_s": 60.0, "wall_s": 9.0},
		"phases": [{}, {}], "carry": {"quest_results": {"1002": {"result": "PASS", "completed": true, "checks": 25,
			"failed": [], "warnings": 0, "name": "Roger's Apple"}}}}
	var bad_rep := {"result": "FAIL", "strict": {"enabled": true, "ok": false}, "carry": {},
		"parity": {"quest:1005": {"checks": 4, "passed": 3, "failed": 1, "warned": 0}},
		"checks": [{"name": "1005: completed", "ok": false, "parity": ["quest:1005"]}]}
	# A verdict the scenario wrote, then a script error in the same run: no quest of the chain passes over it.
	var err_rep := {"result": "FAIL", "strict": {"enabled": true, "ok": true}, "errors": [{"phase": 1, "kind": "script",
		"message": "Invalid call. Nonexistent function"}], "carry": {"quest_results": {
			"1007": {"result": "PASS", "completed": true, "checks": 20, "failed": [], "warnings": 0, "name": "Letter for Lucas"},
			"1008": {"result": "PASS", "completed": true, "checks": 20, "failed": [], "warnings": 0, "name": "Lucas's Reply"}}}}
	# A failure tagged to 1014 fails 1014 only (a WARN with no quest key fails nothing)...
	var part_rep := {"result": "FAIL", "strict": {"enabled": true, "ok": true}, "errors": [],
		"checks": [{"name": "1014: completed", "ok": false, "parity": ["quest:1014"]},
			{"name": "a marker is drawn", "ok": false, "soft": true}], "carry": {"quest_results": {
			"1013": {"result": "PASS", "completed": true, "checks": 25, "failed": [], "warnings": 0, "name": "Quiz 1"},
			"1014": {"result": "FAIL", "completed": false, "checks": 9, "failed": ["1014: completed"], "warnings": 0, "name": "Quiz 2"}}}}
	# ...and a failed check that names no quest fails every quest of its chain.
	var loose_rep := {"result": "FAIL", "strict": {"enabled": true, "ok": true}, "errors": [],
		"checks": [{"name": "walked the trail 000001010 -> 000001000", "ok": false}], "carry": {"quest_results": {
			"1015": {"result": "PASS", "completed": true, "checks": 25, "failed": [], "warnings": 0, "name": "Quiz 3"},
			"1016": {"result": "PASS", "completed": true, "checks": 25, "failed": [], "warnings": 0, "name": "Quiz 4"}}}}
	for pair: Array in [["1002", ok_rep], ["1005", bad_rep], ["1007-1008", err_rep], ["1013-1014", part_rep],
			["1015-1016", loose_rep]]:
		DirAccess.make_dir_recursive_absolute(out.path_join(String(pair[0])))
		var f := FileAccess.open(out.path_join(String(pair[0])).path_join("report.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(pair[1]))
		f.close()
	var s2 := PlaytestQuestSummary.collect(out, PackedStringArray(["1007-1008", "1013-1014", "1015-1016"]))
	var by2 := {}
	for q: Dictionary in s2["quests"]:
		by2[String(q["id"])] = q
	assert_eq(String(by2["1007"]["result"]), "FAIL", "a script error in the chain: %s" % by2["1007"])
	assert_true(str(by2["1008"]["failed"]).contains("Nonexistent function"), "the error is named: %s" % by2["1008"])
	assert_eq(String(by2["1013"]["result"]), "PASS", "a failure tagged to 1014 leaves 1013 alone: %s" % by2["1013"])
	assert_eq(String(by2["1014"]["result"]), "FAIL")
	for id in ["1015", "1016"]:
		assert_eq(String(by2[id]["result"]), "FAIL", "an unattributed failure in the chain: %s" % by2[id])
		assert_true(str(by2[id]["failed"]).contains("walked the trail"), "named: %s" % by2[id])
	assert_eq(int(s2["passed"]), 1, "only 1013 passes")
	var s := PlaytestQuestSummary.collect(out, PackedStringArray(["1002", "1005", "1006,1009"]))
	var by := {}
	for q: Dictionary in s["quests"]:
		by[String(q["id"])] = q
	assert_eq(String(by["1002"]["result"]), "PASS")
	assert_eq(String(by["1005"]["result"]), "FAIL", "rebuilt from the parity keys")
	assert_eq(Array(by["1005"]["failed"]), ["1005: completed"])
	assert_eq(String(by["1006"]["result"]), "NOT_PLAYED", "no report for the chain")
	assert_eq(String(by["1009"]["result"]), "NOT_PLAYED")
	assert_eq(int(s["passed"]), 1)
	assert_false(bool(s["ok"]))
	assert_eq(int((s["chains"] as Array)[0]["console_setup"]), 1, "setup console steps before the strict step")
	assert_eq(PlaytestQuestSummary.chain_dir("1006,1009,1010"), "1006_1009_1010")
	var md := PlaytestQuestSummary.to_markdown(s)
	assert_true(md.contains("| 1002 | Roger's Apple | 1002 | PASS | 25 |"), md)
	for d in ["1002", "1005", "1007-1008", "1013-1014", "1015-1016"]:
		DirAccess.remove_absolute(out.path_join(d).path_join("report.json"))
		DirAccess.remove_absolute(out.path_join(d))
	DirAccess.remove_absolute(out)
