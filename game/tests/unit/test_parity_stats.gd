extends ParityTestCase
## Character stats (ACC, EVA, Magic, WDEF, MDEF, HP/MP, crit, speed/jump) and the stat-window damage range vs
## MeowDB's character builder (game/tests/data/parity_vectors.json).


## Contract C6 (Definition of Done: MeowDB parity tests still pass).
func parity_keys() -> Dictionary:
	return {
		"test_character_stats_and_damage_window": ["canon:meowdb-formula-parity"],
		"test_guide_lv30_warrior_stats": ["canon:meowdb-formula-parity"],
		"test_fixture_builds_total_ap": ["canon:meowdb-formula-parity"],
	}


func _check_builder_vector(v: Dictionary) -> void:
	var inp: Dictionary = v["inputs"]
	var out: Dictionary = v["outputs"]
	var id := String(v["case_id"])
	var job := String(inp["klass"])
	var level := int(inp["level"])
	var weapon: Variant = inp["equipment"]["weapon"]
	var weapon_id := String(inp["weapon_item_id"]) if inp["weapon_item_id"] != null else ""
	var bonus := {}
	if weapon is Dictionary:
		bonus["watk"] = int(weapon["stats"]["watk"])
		assert_eq(int(db().item(weapon_id)["stats"]["watk"]), bonus["watk"], id + " canonical weapon W.ATK")
	var hm := Progression.base_max_hp_mp(job, level, db())
	var snap := StatCalculator.compute(job, level, inp["ap"], int(hm["max_hp"]), int(hm["max_mp"]), bonus, weapon_id, db())
	var st: Dictionary = out["stats"]
	for k in ["str", "dex", "int", "luk", "watk", "matk", "wdef", "mdef", "acc", "avoid", "speed", "jump"]:
		assert_eq(snap[k], int(st[k]), "%s %s" % [id, k])
	assert_eq(snap["max_hp"], int(st["hp"]), id + " hp")
	assert_eq(snap["max_mp"], int(st["mp"]), id + " mp")
	assert_eq(snap["attack_power"], int(st["attackPower"]), id + " attackPower")
	assert_rel(float(snap["crit_rate_pct"]), float(st["critRate"]), id + " critRate")
	assert_rel(float(snap["crit_damage_pct"]), float(st["critDamage"]), id + " critDamage")
	assert_eq(snap["primary"], int(out["primary"]), id + " primary")
	assert_eq(snap["secondary"], int(out["secondary"]), id + " secondary")
	assert_rel(float(snap["shield_guard_chance"]), float(out["shieldGuardChance"]), id + " shieldGuardChance")
	var bd: Variant = out["beginnerDamage"]
	if bd is Dictionary:
		assert_eq(snap["damage_min"], int(bd["min"]), id + " window min")
		assert_eq(snap["damage_max"], int(bd["max"]), id + " window max")
		assert_eq(snap["damage_avg"], float(bd["avg"]), id + " window avg")
	elif job == "beginner" and weapon_id == "":
		# MeowDB models no unarmed damage (null). MisoStory adaptation (misostory/combat.json bare_hands): the
		# documented formula with W.ATK 0, so the final clamp gives 1-1.
		assert_eq(snap["damage_min"], 1, id + " bare hands min (adaptation)")
		assert_eq(snap["damage_max"], 1, id + " bare hands max (adaptation)")


## character_stats_and_damage_window: Beginner builds at levels 1/5/8/10 with each starter weapon and no weapon.
func test_character_stats_and_damage_window() -> void:
	for v in vectors("character_stats_and_damage_window"):
		_check_builder_vector(v)


## guide_example_lv30_warrior_stats: ACC 49, EVA 11, Magic 2, WDEF 33, MDEF 1 (and HP 1104 / MP 503).
func test_guide_lv30_warrior_stats() -> void:
	for v in vectors("guide_example_lv30_warrior_stats"):
		_check_builder_vector(v)
		var g: Dictionary = v["guide_expected"]
		var snap := StatCalculator.compute("warrior", 30, g["ap_plan"], 0, 0, {"watk": int(g["weapon_watk"])}, "551", db())
		assert_eq(snap["acc"], int(g["acc"]), "guide ACC 49")
		assert_eq(snap["avoid"], int(g["eva"]), "guide EVA 11")
		assert_eq(snap["magic"], int(g["magic"]), "guide Magic 2")
		assert_eq(snap["wdef"], int(g["wdef"]), "guide WDEF 33")
		assert_eq(snap["mdef"], int(g["mdef"]), "guide MDEF 1")
		assert_eq(Progression.total_ap(30, db()), int(g["available_ap"]), "guide 170 total AP")


## The fixture builds' AP plans spend exactly the AP MeowDB says a character has (25 + 5 x (L - 1)).
func test_fixture_builds_total_ap() -> void:
	for b in parity_doc()["fixtures"]["beginner_builds"]:
		var ap: Dictionary = b["ap"]
		var spent := int(ap["str"]) + int(ap["dex"]) + int(ap["int"]) + int(ap["luk"])
		assert_eq(spent, Progression.total_ap(int(b["level"]), db()), "build %s level %s" % [b.get("plan", ""), b["level"]])
