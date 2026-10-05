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
	assert_false(m.uses_map_mob_rate, "MSC ignores mobRate")


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
