extends TestCase
## MapInstanceState and MapStateCache (MAP_ARCHITECTURE.md sections 4.7.2 and 4.7.3). Pure and deterministic.


func model() -> SpawnModel:
	return SpawnModel.from_db(db())


func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func wave_slots(n: int) -> Array[float]:
	var out: Array[float] = []
	for i in n:
		out.append(0.0)
	return out


func test_fresh_fills_to_capacity_immediately() -> void:
	var defs := MapDefinitions.build(db())
	var def := defs.get_def("000000040")
	var st := MapInstanceState.fresh(def, model(), rng(1), 0.0)
	assert_eq(st.slots.size(), 40, "slots")
	assert_eq(st.capacity, 30, "capacity")
	assert_eq(st.alive_count(), 30, "filled to capacity")
	var town := MapInstanceState.fresh(defs.get_def("000000060"), model(), rng(1), 0.0)
	assert_eq(town.alive_count(), 0, "Southperry has no spawns")


func test_fresh_is_deterministic_per_seed() -> void:
	var a := MapInstanceState.fresh_for("m", wave_slots(42), model(), rng(7), 0.0)
	var b := MapInstanceState.fresh_for("m", wave_slots(42), model(), rng(7), 0.0)
	var c := MapInstanceState.fresh_for("m", wave_slots(42), model(), rng(8), 0.0)
	assert_eq(a.alive_indices(), b.alive_indices(), "same seed, same slots")
	assert_ne(a.alive_indices(), c.alive_indices(), "different seed, different slots")


func test_kill_records_death_and_respawns_on_the_tick() -> void:
	var m := model()
	var st := MapInstanceState.fresh_for("m", wave_slots(4), m, rng(3), 0.0)
	assert_eq(st.capacity, 3, "4 points -> 3")
	var victim: int = st.alive_indices()[0]
	assert_true(st.kill(victim, 10.0), "kill")
	assert_false(st.kill(victim, 10.0), "already dead")
	assert_near(float(st.slots[victim].died_at), 10.0, 1e-9, "died_at")
	assert_eq(st.alive_count(), 2, "one fewer")
	assert_eq(st.tick(15.0).size(), 0, "ready at 15 s but no tick yet (ticks at 7.56, 15.12)")
	var back := st.tick(15.12)
	assert_eq(back.size(), 1, "respawn on the 15.12 s tick")
	assert_eq(st.alive_count(), 3, "back to capacity")


func test_capacity_caps_respawns_and_any_dead_slot_may_refill() -> void:
	var m := model()
	var st := MapInstanceState.fresh_for("m", wave_slots(8), m, rng(5), 0.0)
	assert_eq(st.capacity, 6, "8 points -> 6")
	for i in st.alive_indices():
		st.kill(i, 1.0)
	assert_eq(st.alive_count(), 0, "all dead")
	var back := st.tick(7.56)
	assert_eq(back.size(), 6, "refills to capacity on the first tick after death + 5 s")
	assert_eq(st.alive_count(), 6, "never above capacity")
	assert_eq(st.tick(100.0).size(), 0, "nothing more while at capacity")


func test_snapshot_and_fast_forward() -> void:
	var m := model()
	var st := MapInstanceState.fresh_for("m", wave_slots(10), m, rng(11), 0.0)
	var killed: PackedInt32Array = []
	for i in st.alive_indices():
		if killed.size() < 4:
			st.kill(i, 3.0)
			killed.append(i)
	st.drops.append({"item_id": "2000000", "amount": 1, "expires_at": 20.0})
	st.drops.append({"mesos": 5, "amount": 5, "expires_at": 90.0})
	var snap := st.snapshot(4.0)
	assert_eq(int(snap.slots.size()), 10, "snapshot slots")
	var cache := MapStateCache.new()
	cache.put("m", snap)
	var restored := MapInstanceState.from_snapshot(cache.take("m"), m, 30.0)
	assert_eq(restored.alive_count(), restored.capacity, "refilled after ~13 s away (section 4.7.2)")
	assert_eq(restored.drops.size(), 1, "expired drop discarded")
	var survivors := 0
	for i in st.alive_indices():
		if restored.is_alive(i):
			survivors += 1
	assert_eq(survivors, st.alive_count(), "survivors stay at their slots")
	var short := MapInstanceState.from_snapshot(snap, m, 6.0)
	assert_eq(short.alive_count(), st.alive_count(), "no tick between 4 s and 6 s")


func test_hp_of_survivors_is_kept() -> void:
	var st := MapInstanceState.fresh_for("m", wave_slots(4), model(), rng(2), 0.0)
	var i: int = st.alive_indices()[0]
	st.set_hp(i, 7)
	var back := MapInstanceState.from_snapshot(st.snapshot(1.0), model(), 2.0)
	assert_eq(int(back.slots[i].hp), 7, "HP restored at the slot")


func test_long_absence_is_closed_form() -> void:
	var st := MapInstanceState.fresh_for("m", wave_slots(66), model(), rng(9), 0.0)
	for i in st.alive_indices():
		st.kill(i, 1.0)
	var t0 := Time.get_ticks_usec()
	st.tick(3600.0 * 24.0)
	assert_true(Time.get_ticks_usec() - t0 < 50000, "a day away replays in < 50 ms")
	assert_eq(st.alive_count(), 49, "refilled")


func test_state_cache_is_lru_of_four() -> void:
	var c := MapStateCache.new()
	assert_eq(c.capacity, 4, "spec capacity")
	for id in ["a", "b", "c", "d", "e"]:
		c.put(id, {"map_id": id})
	assert_false(c.has("a"), "oldest evicted")
	assert_eq(c.keys(), PackedStringArray(["b", "c", "d", "e"]), "order")
	c.put("b", {"map_id": "b"})
	c.put("f", {"map_id": "f"})
	assert_false(c.has("c"), "least recently parked evicted")
	assert_eq(c.take("b").get("map_id", ""), "b", "take")
	assert_false(c.has("b"), "take removes")
	assert_true(c.take("zzz").is_empty(), "missing -> {}")


## The drop records' API (LootSystem's records carry a "uid"): add_drop copies, find_drop / remove_drop name a record
## by uid, expire_drops hands back what it removed, and the records ride the snapshot.
func test_drop_records_by_uid() -> void:
	var st := MapInstanceState.fresh_for("m", wave_slots(2), model(), rng(4), 0.0)
	var rec := {"uid": "m:1:1", "item_id": "4000019", "qty": 1, "pos_local": [1.0, 0.0, 2.0], "expires_at": 50.0}
	st.add_drop(rec)
	st.add_drop({"uid": "m:1:2", "kind": "mesos", "amount": 7, "expires_at": 10.0})
	st.add_drop({"kind": "mesos", "amount": 1, "expires_at": 90.0})  # no uid: never found by uid
	rec["qty"] = 99
	assert_eq(int(st.find_drop("m:1:1").get("qty", 0)), 1, "add_drop stored a copy")
	assert_true(st.has_drop("m:1:2"), "has_drop")
	assert_true(st.find_drop("").is_empty(), "an empty uid never matches")
	assert_true(st.find_drop("nope").is_empty(), "unknown uid -> {}")
	assert_true(st.find_drop("m:1:1") == st.drops[0], "find_drop returns the stored record itself")
	var gone := st.expire_drops(10.0)
	assert_eq(gone.size(), 1, "one record expired at its expires_at")
	assert_eq(String(gone[0].uid), "m:1:2", "the expired record is handed back")
	assert_false(st.has_drop("m:1:2"), "and removed")
	var snap := MapInstanceState.from_snapshot(st.snapshot(11.0), model(), 12.0)
	assert_eq(String(snap.find_drop("m:1:1").get("item_id", "")), "4000019", "records ride the cache snapshot with their uid")
	var removed := st.remove_drop("m:1:1")
	assert_eq(String(removed.get("item_id", "")), "4000019", "remove_drop returns the record")
	assert_true(st.remove_drop("m:1:1").is_empty(), "a second remove finds nothing")
	assert_eq(st.drops.size(), 1, "the uid-less record is untouched")


## SpawnSlot.NO_SLOT (-1, the debug console's synthetic slot) and out-of-range indices are "no slot": never alive,
## never killed, never respawned, no HP, and ready_time does not wrap to the last slot.
func test_no_slot_index_is_never_a_slot() -> void:
	var st := MapInstanceState.fresh_for("m", wave_slots(4), model(), rng(3), 0.0)
	var last := st.slots.size() - 1
	for i in st.alive_indices():
		st.kill(i, 1.0)
	assert_false(st.has_slot(SpawnSlot.NO_SLOT), "NO_SLOT is not a slot")
	assert_false(st.is_alive(SpawnSlot.NO_SLOT), "never alive")
	assert_false(st.kill(SpawnSlot.NO_SLOT, 2.0), "a NO_SLOT kill is refused")
	assert_false(st.kill(st.slots.size(), 2.0), "an out-of-range kill is refused")
	assert_eq(st.ready_time(SpawnSlot.NO_SLOT), INF, "no ready time (GDScript would read slots[-1])")
	assert_ne(st.ready_time(last), INF, "the real last slot has one")
	st.set_hp(SpawnSlot.NO_SLOT, 5)
	for s in st.slots:
		assert_ne(int(s.hp), 5, "set_hp(-1) changed no slot")
	var back := st.tick(1000.0)
	assert_false(back.has(SpawnSlot.NO_SLOT), "never respawned")
	assert_eq(st.alive_count(), st.capacity, "the real slots refilled")
	var synthetic := SpawnSlot.synthetic("2", Transform3D.IDENTITY)
	assert_false(synthetic.is_spawn_point(), "SpawnSlot.synthetic is not a spawn point")
	assert_eq([synthetic.index, synthetic.placement], [SpawnSlot.NO_SLOT, "debug"], "synthetic slot shape")
