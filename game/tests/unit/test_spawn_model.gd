extends TestCase
## SpawnModel against MeowDB's worked numbers (formulas/spawn_rate.json; MAP_ARCHITECTURE.md sections 3.2, 4.13)
## and the capacity table of Appendix B.

## MAP_ARCHITECTURE.md Appendix B: map -> [spawn points, solo cap].
const APPENDIX_B := {
	"000000001": [0, 0], "000000010": [0, 0], "000000020": [0, 0], "000000021": [0, 0], "000000030": [6, 4],
	"000000040": [40, 30], "000000041": [45, 33], "000000042": [42, 31], "000000050": [42, 31], "000000060": [0, 0],
	"000000061": [0, 0], "000001000": [66, 49], "000001001": [40, 30], "000001002": [34, 25], "000001003": [35, 26],
	"000001004": [41, 30], "000001005": [44, 33], "000001006": [45, 33], "000001010": [0, 0], "000001011": [0, 0],
	"000001012": [0, 0], "000001013": [0, 0], "000001014": [34, 25], "000001020": [38, 28], "000001021": [25, 18],
}


func model() -> SpawnModel:
	return SpawnModel.from_db(db())


func test_reads_the_canonical_record() -> void:
	var m := model()
	assert_eq(m.errors.size(), 0, "errors: %s" % ", ".join(m.errors))
	var rec := db().formula("spawn_rate")
	assert_eq(m.tick_s, float(rec.global_respawn_tick_s), "tick")
	assert_eq(m.wave_cooldown_s, float(rec.wave_point_cooldown_s), "wave cooldown")
	assert_near(m.tick_s, 7.56, 1e-9, "MeowDB tick")
	assert_near(m.wave_cooldown_s, 5.0, 1e-9, "MeowDB wave cooldown")
	assert_false(m.uses_map_mob_rate, "presentation.json map_mob_rate.apply is false: mobRate ignored (MisoStory decision)")
	assert_eq(m.canonical_applied_by_msc, bool(rec.map_spawn_rate_multiplier.applied_by_msc), "MeowDB's guide statement kept as data")


func test_player_scalar_table() -> void:
	var m := model()
	assert_eq(m.scalar_pct(1), 75, "solo")
	assert_eq(m.scalar_pct(2), 80, "2 players")
	assert_eq(m.scalar_pct(5), 95, "5 players")
	assert_eq(m.scalar_pct(6), 100, "6 players")
	assert_eq(m.scalar_pct(9), 100, "6+ players")


func test_worked_capacity_numbers() -> void:
	var m := model()
	assert_eq(m.capacity(50), 37, "50 points -> 37 solo (MAP_ARCHITECTURE 4.13)")
	assert_eq(m.capacity(40), 30, "MeowDB's 000000040 example: 40 points, 30 solo")
	assert_eq(m.capacity(40, 6), 40, "full party")
	assert_eq(m.capacity(42), 31, "31.5 floors to 31 (maps.md discrepancy 2)")
	assert_eq(m.capacity(45, 2), 36, "45 x 80% is exactly 36 (integer math)")
	assert_eq(m.capacity(66), 49, "largest map")
	assert_eq(m.capacity(0), 0, "no points")


func test_mob_rate_is_ignored() -> void:
	var m := model()
	var rec := db().map("000000050")
	assert_near(float(rec.mob_rate), 1.5, 1e-9, "A Split Road's MeowDB mob rate")
	assert_eq(m.capacity((rec.spawns as Array).size(), 1, float(rec.mob_rate)), 31, "42 points stay 31, not 47")
	assert_eq(m.capacity(6, 1, 0.6), 4, "000000030 mob rate 0.6 ignored")
	assert_eq(m.capacity_for_map("000000050", 42), 31, "the game's entry point: switch off")
	assert_near(float(m.map_mob_rates["000000050"]), 1.5, 1e-9, "the map's canonical rate is at hand")
	var defs := MapDefinitions.build(db())
	for id in defs.ids():
		var points := defs.get_def(id).spawn_point_count()
		assert_eq(defs.capacity_of(id), m.capacity(points), "%s capacity_of ignores the mob rate" % id)


## presentation.json map_mob_rate.apply is a real switch: turned on, capacity_for_map multiplies by the map's canonical
## mob rate, capped at the spawn-point count (one monster per MeowDB spawn point), and MapInstanceState uses it.
func test_the_mob_rate_switch_is_live() -> void:
	var c := ContentDB.new()
	c.canonical = db().canonical
	c.miso = db().miso.duplicate(true)
	c.loaded = true
	c.miso[""]["presentation"]["map_mob_rate"]["apply"] = true
	var on := SpawnModel.from_db(c)
	assert_eq(on.errors.size(), 0, ", ".join(on.errors))
	assert_true(on.uses_map_mob_rate, "switch on")
	assert_eq(on.capacity_for_map("000000050", 42), 42, "31 x 1.5 = 46, capped at 42 spawn points")
	assert_true(on.warnings.size() == 1 and on.warnings[0].contains("000000050"), "the cap is reported: %s" % on.warnings)
	assert_eq(on.capacity_for_map("000000030", 6), 2, "4 x 0.6 = 2.4 -> 2")
	assert_eq(on.capacity_for_map("000001000", 66), 63, "49 x 1.3 = 63.7 -> 63")
	assert_eq(on.capacity_for_map("000000040", 40), 30, "1.0x unchanged")
	var none: Array[float] = []
	for i in 42:
		none.append(0.0)
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var st := MapInstanceState.fresh_for("000000050", none, on, r, 0.0)
	assert_eq(st.capacity, 42, "MapInstanceState asks capacity_for_map")
	assert_eq(st.alive_count(), 42, "and fills to it")
	var off := MapInstanceState.fresh_for("000000050", none, SpawnModel.from_db(db()), r, 0.0)
	assert_eq(off.capacity, 31, "switch off: 31")


func test_respawn_is_the_first_tick_at_or_after_death_plus_cooldown() -> void:
	var m := model()
	assert_near(m.respawn_time(10.0), 15.12, 1e-6, "death 10 s -> ready 15 s -> tick 2 (15.12 s)")
	assert_near(m.respawn_time(7.56), 15.12, 1e-6, "killed on a tick: exactly one tick later")
	assert_near(m.respawn_time(2.56), 7.56, 1e-6, "ready exactly on a tick (7.56) respawns on it")
	assert_near(m.respawn_time(0.0), 7.56, 1e-6, "death at 0 -> first tick")
	assert_near(m.respawn_time(10.0, 60.0), 75.6, 1e-6, "timed point: own timer (70 s -> tick 10 at 75.6 s)")
	for k in 50:
		var t := k * 0.731
		var r := m.respawn_time(t)
		assert_true(r >= t + 5.0 - 1e-6, "never before death + cooldown")
		assert_true(r < t + 5.0 + m.tick_s + 1e-6, "within one tick after ready")


func test_capacity_table_equals_appendix_b_and_meowdb_estimates() -> void:
	var m := model()
	var d := MapDefinitions.build(db())
	var total_points := 0
	var total_cap := 0
	for id in APPENDIX_B:
		var rec := db().map(id)
		var points := (rec.spawns as Array).size()
		assert_eq(points, int(APPENDIX_B[id][0]), "%s spawn points" % id)
		assert_eq(d.capacity_of(id), int(APPENDIX_B[id][1]), "%s solo cap" % id)
		var est: Variant = rec.get("meowdb_spawn_estimates", null)
		if est is Dictionary and (est as Dictionary).has("capacity_solo"):
			assert_eq(m.capacity(points), int(floor(float(est.capacity_solo))), "%s vs MeowDB's own estimate" % id)
		total_points += points
		total_cap += d.capacity_of(id)
	assert_eq(total_points, 577, "island spawn points")
	assert_eq(total_cap, 426, "island solo capacity")


func parity_keys() -> Dictionary:
	return {
		"test_reads_the_canonical_record": ["mechanic:spawn-respawn-tick"],
		"test_player_scalar_table": ["mechanic:spawn-capacity"],
		"test_worked_capacity_numbers": ["mechanic:spawn-capacity"],
		"test_mob_rate_is_ignored": ["mechanic:spawn-mob-rate"],
		"test_the_mob_rate_switch_is_live": ["mechanic:spawn-mob-rate"],
		"test_respawn_is_the_first_tick_at_or_after_death_plus_cooldown": ["mechanic:spawn-respawn-tick"],
		"test_capacity_table_equals_appendix_b_and_meowdb_estimates": ["mechanic:spawn-capacity"],
	}
