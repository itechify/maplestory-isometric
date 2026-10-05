extends PlaytestScenario
## test_b_population: the monster population of every Maple Island hunting map in the real game (brief Phase 6 and
## 'Isometric Spawn Adaptation'). A new character warps (console, setup only) through every map with MeowDB spawn
## points. On each it checks, against canonical data (maps/<id>.json, formulas/spawn_rate.json) and the adaptation
## rules (presentation.json spawns):
##   - one slot per MeowDB spawn point with the canonical species counts, and the solo capacity live after the first
##     fill, every live monster of a canonical species;
##   - every slot placed (strict, relaxed or pinned) on real collision, clear of every portal arrival and NPC;
##   - after 8 s of wandering every grounded monster stands on its floor (Monster.floor_range) inside its mob region;
##   - after `kill all`, the map is back at capacity on the respawn ticks, and no respawn is realized within the
##     respawn clearance of the player.
## On Snail Hunting Ground I it also stands the player on a dead slot through a respawn tick: the slot comes back in the
## instance state, its monster waits until the player walks away, then appears.
## Run: `ISOLATE=<name> bash scripts/playtest.sh test_b_population` (headless).

var d: PlaytestDriver = null
var db: ContentDB = null
var _view: Node = null
## Realized spawns after each map's first fill: {map, slot, dist_player}.
var _respawns: Array = []
var _first_fill_done: bool = false


func description() -> String:
	return "every hunting map: canonical slots and capacity, placement clearances, floors, refills, no respawn on the player"


func max_seconds() -> float:
	return 1500.0


func run(driver: PlaytestDriver) -> void:
	d = driver
	db = d.db()
	var ng: Dictionary = await d.new_game("Census", "female", "541", {"str": 9})
	if not d.check("new game through the creation screen", bool(ng["ok"]), String(ng["why"])):
		return
	await d.console("god on")
	var maps: Array = []
	for id in db.ids("maps"):
		if not (db.map(id).get("spawns", []) as Array).is_empty():
			maps.append(String(id))
	maps.sort()
	d.check("15 Maple Island maps have MeowDB spawn points", maps.size() == 15, str(maps))
	var spawn_f := db.formula("spawn_rate")
	var solo := 0
	for row: Dictionary in (spawn_f.get("capacity", {}) as Dictionary).get("player_scalar_table", []):
		if String(row.get("players", "")) == "1":
			solo = int(row.get("scalar_pct", 0))
	var tuning := WorldTuning.from_db(db)
	var npc_clear := tuning.num("spawns", "slot_npc_clearance_m")
	var arrival_clear := tuning.num("spawns", "slot_portal_clearance_m")
	var respawn_clear := tuning.num("spawns", "respawn_player_clearance_m")
	var total_slots := 0
	var total_cap := 0
	for map: String in maps:
		await _visit(map)
		if d.current_map() != map:
			d.check("arrived in %s" % map, false, d.current_map())
			continue
		var defs: MapDefinitions = d.world().defs
		var def := defs.get_def(map)
		var view: MapInstanceView = d.monsters().get("view")
		var st := view.state
		var rec := db.map(map)
		var points := (rec.get("spawns", []) as Array).size()
		total_slots += def.monster_spawn_definitions.size()
		# --- canonical slots and capacity ---------------------------------------------------------------------
		var want := {}
		for m: Dictionary in rec.get("monsters", []):
			want[str(m.get("id", ""))] = int(m.get("count", 0))
		var have := {}
		for s in def.monster_spawn_definitions:
			have[s.mob_id] = int(have.get(s.mob_id, 0)) + 1
		var cap := points * solo / 100
		total_cap += st.capacity
		d.check("%s: %d slots = MeowDB spawn points, species %s" % [map, points, want],
			def.monster_spawn_definitions.size() == points and have == want, "slots %s" % [have])
		var live := _live(map)
		var alien := 0
		for m: Monster in live:
			if not want.has(m.def.id):
				alien += 1
		d.check("%s: solo capacity %d live after the first fill, all canonical species" % [map, cap],
			st.capacity == cap and defs.capacity_of(map) == cap and live.size() == cap and alien == 0,
			"state capacity %d, live %d, %d of another species" % [st.capacity, live.size(), alien])
		# --- placement clearances on real collision -----------------------------------------------------------
		var bad_place: Array = []
		var npcs := SpawnSlotPlanner.npc_points(def)
		var arrivals := SpawnSlotPlanner.arrival_points(def)
		var nearest_npc := INF
		for s in def.monster_spawn_definitions:
			if not (s.placement in ["strict", "relaxed", "pinned"]):
				bad_place.append("slot %d %s" % [s.index, s.placement])
			for n in npcs:
				nearest_npc = minf(nearest_npc, s.position().distance_to(n))
				if s.position().distance_to(n) < npc_clear - 1e-3:
					bad_place.append("slot %d %.2f m from an NPC" % [s.index, s.position().distance_to(n)])
			for a in arrivals:
				if s.position().distance_to(a) < arrival_clear - 1e-3:
					bad_place.append("slot %d %.2f m from an arrival" % [s.index, s.position().distance_to(a)])
		d.check("%s: every slot placed clear of %d arrivals and %d NPCs" % [map, arrivals.size(), npcs.size()],
			bad_place.is_empty(), "%s; nearest NPC %.1f m" % [bad_place.slice(0, 5), nearest_npc])
		# --- floors after wandering ----------------------------------------------------------------------------
		await d.wait(8.0)
		var off_floor: Array = []
		var outside: Array = []
		var region: MobRegion = d.monsters().call("region_for", def)
		var floor_blocks := 0
		for m: Monster in _live(map):
			floor_blocks += int(m.blocked_by.get("floor", 0))
			if not m.airborne and m.recoveries == 0:
				var y := m.global_position.y
				if y < m.floor_range.x - 0.05 or y > m.floor_range.y + 0.05:
					off_floor.append("%s %.2f not in %s" % [m.name, y, m.floor_range])
			if region != null and region.outside_distance(m.global_position) > 0.25:
				outside.append("%s %.2f m out" % [m.name, region.outside_distance(m.global_position)])
		d.check("%s: after 8 s every grounded monster is on its floor, inside the mob region" % map,
			off_floor.is_empty() and outside.is_empty(), "%s %s; %d turns at a floor edge" % [off_floor.slice(0, 4), outside.slice(0, 4), floor_blocks])
		# --- refills after kill all ----------------------------------------------------------------------------
		_respawns.clear()
		_first_fill_done = true
		await d.console("kill all")
		var tick := float(spawn_f.get("global_respawn_tick_s", 0.0))
		var cool := float(spawn_f.get("wave_point_cooldown_s", 0.0))
		await d.wait(cool + 2.0 * tick + 1.0)
		var refilled := _live(map).size()
		var near := _respawns.filter(func(r: Dictionary) -> bool: return float(r["dist_player"]) < respawn_clear)
		d.check("%s: back at capacity %d on the respawn ticks after kill all; no respawn within %.1f m of the player" % [map, cap, respawn_clear],
			refilled == st.capacity and near.is_empty(), "live %d, %d respawns realized, closest %s" % [refilled, _respawns.size(),
				_respawns.map(func(r: Dictionary) -> float: return snappedf(float(r["dist_player"]), 0.01)).min() if not _respawns.is_empty() else "-"])
		_first_fill_done = false
		if map == "000000040":
			await _respawn_on_player_probe(map, tick, cool, respawn_clear)
	d.check("island: 577 slots, solo capacity 426", total_slots == 577 and total_cap == 426, "%d slots, capacity %d" % [total_slots, total_cap])


func _visit(map: String) -> void:
	await d.console("warp " + map)
	await d.wait_idle(20.0)
	await d.wait(1.5)
	var v: Node = d.monsters().get("view")
	if v != _view:
		if _view != null and is_instance_valid(_view) and _view.is_connected(&"monster_spawned", _on_spawned):
			_view.disconnect(&"monster_spawned", _on_spawned)
		_view = v
		if _view != null:
			_view.connect(&"monster_spawned", _on_spawned)
	await d.wait_until(func() -> bool: return int(_view.call("pending_count")) == 0, 5.0)


func _live(map: String) -> Array[Monster]:
	var out: Array[Monster] = []
	for m: Monster in d.monsters().call("live_monsters"):
		if m.has_slot() and m.map_id == map:
			out.append(m)
	return out


func _on_spawned(node: Node3D, slot: SpawnSlot) -> void:
	if not _first_fill_done or slot == null:
		return
	var p := d.player()
	_respawns.append({"map": d.current_map(), "slot": slot.index,
		"dist_player": p.global_position.distance_to(slot.position()) if p != null else INF})


## The player stands on a dead slot through respawn ticks: when the tick brings that slot back, its monster is not
## realized while the player stays, and appears once the player walks away.
func _respawn_on_player_probe(map: String, tick: float, cool: float, clear: float) -> void:
	var i := d._begin(PlaytestReport.KIND_PLAY, "respawn_on_player", "stand on a dead slot of %s through respawn ticks" % map)
	var view: MapInstanceView = d.monsters().get("view")
	var def: MapDefinition = d.world().defs.get_def(map)
	var held := -1
	var waited := 0
	for attempt in 6:
		await d.console("kill all")
		var slot := attempt * 7 % def.monster_spawn_definitions.size()
		await d.console("goto slot %d" % slot)
		await d.wait(cool + tick + 0.5)
		var p := d.player()
		if view.state.is_alive(slot) and p.global_position.distance_to(def.monster_spawn_definitions[slot].position()) < clear:
			if not view.nodes.has(slot):
				held = slot
				waited = int(view.deferred_respawns)
				break
	var appeared := false
	if held >= 0:
		await d.console("goto portal %s" % def.portals[0].portal_id)
		await d.wait(1.0)
		appeared = view.nodes.has(held)
	var ok := held >= 0 and appeared
	d.check("a respawn on the player's slot waits until the player leaves, then appears", ok,
		"slot %d held (%d deferrals), realized after leaving: %s" % [held, waited, appeared])
	d._end(i, ok, "slot %d" % held)
