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
	for pair: Array in [["1002", ok_rep], ["1005", bad_rep]]:
		DirAccess.make_dir_recursive_absolute(out.path_join(String(pair[0])))
		var f := FileAccess.open(out.path_join(String(pair[0])).path_join("report.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(pair[1]))
		f.close()
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
	for d in ["1002", "1005"]:
		DirAccess.remove_absolute(out.path_join(d).path_join("report.json"))
		DirAccess.remove_absolute(out.path_join(d))
	DirAccess.remove_absolute(out)
