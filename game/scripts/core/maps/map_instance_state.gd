class_name MapInstanceState
extends RefCounted
## The live gameplay state of one map instance (MAP_ARCHITECTURE.md section 4.7.2). Pure: no nodes, no clock of its
## own; every call takes the game time `now` (Game.clock, which pauses with the game).
##
##   slots[i] = {alive: bool, hp: int (-1 = full, set by the monster system), died_at: float (-1 while alive)}
##   drops[]  = {uid, item_id | mesos, amount, pos_local, expires_at, owner} (records of the loot system; expired
##              drops are discarded on tick/fast_forward)
##   capacity = SpawnModel.capacity(spawn points, players)
##
## fresh() fills to capacity immediately (an adaptation, open question 6). tick() runs the global respawn ticks
## that passed since the last call: at each tick boundary every dead slot whose death + cooldown is at or before
## the boundary is eligible, and eligible slots respawn in seeded random order while alive < capacity.
## snapshot()/from_snapshot() park a map in MapStateCache; restoring replays the missed boundaries in closed form.
##
## Slot indices are MeowDB spawns[] indices (0..n-1). Anything else, in particular SpawnSlot.NO_SLOT (-1, the debug
## console's synthetic slot), is "no slot": kill() refuses it, it is never alive, never respawned and has no HP.
##
## Drops: add_drop() stores a copy; find_drop(uid) / remove_drop(uid) / expire_drops(now) are the only other ways
## the loot system touches the list (records are matched by their "uid", DROP_UID_KEY).

## The key a drop record is identified by (LootSystem writes it: LootPickupRules.UID_KEY).
const DROP_UID_KEY := "uid"

var map_id: String = ""
var capacity: int = 0
var slots: Array[Dictionary] = []
## Per-slot MeowDB mobTime (seconds; 0 = wave point).
var mob_times: PackedFloat64Array = []
var drops: Array[Dictionary] = []
## Index of the last tick boundary already processed.
var last_tick_index: int = 0
var model: SpawnModel = null
var rng: RandomNumberGenerator = null
## Respawns that happened inside kill() (boundaries that passed before the kill); returned by the next tick().
var _pending_respawns: PackedInt32Array = []


## A new instance for `def`, filled to capacity right away with slots chosen by `rng` (seeded by the caller).
static func fresh(def: MapDefinition, spawn_model: SpawnModel, random: RandomNumberGenerator, now: float,
		players: int = 1) -> MapInstanceState:
	var times: Array[float] = []
	for s in def.monster_spawn_definitions:
		times.append(s.mob_time_s)
	return MapInstanceState.fresh_for(def.map_id, times, spawn_model, random, now, players)


## fresh() without a MapDefinition: one slot per entry of `slot_mob_times`.
static func fresh_for(p_map_id: String, slot_mob_times: Array[float], spawn_model: SpawnModel,
		random: RandomNumberGenerator, now: float, players: int = 1) -> MapInstanceState:
	var st := MapInstanceState.new()
	st.map_id = p_map_id
	st.model = spawn_model
	st.rng = random
	for t in slot_mob_times:
		st.mob_times.append(t)
		st.slots.append({"alive": false, "hp": -1, "died_at": -1.0})
	st.capacity = spawn_model.capacity(st.slots.size(), players)
	st.last_tick_index = spawn_model.boundary_index_at_or_before(now)
	var pool: Array[int] = []
	for i in st.slots.size():
		pool.append(i)
	while st.alive_count() < st.capacity and not pool.is_empty():
		var j := random.randi_range(0, pool.size() - 1)
		var idx: int = pool[j]
		pool.remove_at(j)
		st.slots[idx] = {"alive": true, "hp": -1, "died_at": -1.0}
	return st


func alive_count() -> int:
	var n := 0
	for s in slots:
		if bool(s.alive):
			n += 1
	return n


func alive_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in slots.size():
		if bool(slots[i].alive):
			out.append(i)
	return out


func is_alive(index: int) -> bool:
	return has_slot(index) and bool(slots[index].alive)


## True when `index` names one of this map's spawn slots (false for SpawnSlot.NO_SLOT and anything out of range).
func has_slot(index: int) -> bool:
	return index >= 0 and index < slots.size()


## Marks slot `index` dead at `now` (its monster was killed). False if it was not alive, or is not a slot (a debug
## spawn's NO_SLOT): a kill is never recorded for it.
func kill(index: int, now: float) -> bool:
	if not is_alive(index):
		return false
	# Boundaries that passed before `now` happen first, so time order holds even if tick() was not called yet.
	_pending_respawns.append_array(_advance(now))
	slots[index] = {"alive": false, "hp": 0, "died_at": now}
	return true


## Remembers a survivor's HP so it is restored at its slot (MapInstanceView.release()).
func set_hp(index: int, hp: int) -> void:
	if is_alive(index):
		slots[index]["hp"] = hp


## When slot `index` becomes eligible again (INF while alive, and for an index that is not a slot: GDScript would
## otherwise read slots[-1], the last slot).
func ready_time(index: int) -> float:
	if not has_slot(index) or is_alive(index):
		return INF
	return float(slots[index].died_at) + model.cooldown_for(mob_times[index])


## Runs every tick boundary in (last processed, now]. Returns the slots that respawned since the last call, in
## respawn order.
func tick(now: float) -> PackedInt32Array:
	var out := _pending_respawns
	_pending_respawns = PackedInt32Array()
	expire_drops(now)
	out.append_array(_advance(now))
	return out


func _advance(now: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var k_now := model.boundary_index_at_or_before(now)
	if k_now <= last_tick_index:
		return out
	var k := last_tick_index + 1
	while k <= k_now:
		var dead := _dead_indices()
		if dead.is_empty() or alive_count() >= capacity:
			break
		# Jump straight to the first boundary at which any dead slot is ready (closed form for long absences).
		var k_ready := k_now + 1
		for i in dead:
			k_ready = mini(k_ready, model.boundary_index_at_or_after(ready_time(i)))
		k = maxi(k, k_ready)
		if k > k_now:
			break
		var eligible: Array[int] = []
		for i in dead:
			if model.boundary_index_at_or_after(ready_time(i)) <= k:
				eligible.append(i)
		while alive_count() < capacity and not eligible.is_empty():
			var j := rng.randi_range(0, eligible.size() - 1)
			var idx: int = eligible[j]
			eligible.remove_at(j)
			slots[idx] = {"alive": true, "hp": -1, "died_at": -1.0}
			out.append(idx)
		k += 1
	last_tick_index = k_now
	return out


## Replays the boundaries missed while the map was parked (same rules as tick()).
func fast_forward(now: float) -> PackedInt32Array:
	return tick(now)


## Adds a drop record (owned by the drop system). It must carry "expires_at" (game time) and should carry a unique
## "uid" (DROP_UID_KEY) so find_drop / remove_drop can name it. A copy is stored.
func add_drop(drop: Dictionary) -> void:
	drops.append(drop.duplicate(true))


## The stored record with this uid, or {} ("" never matches). It is the live record in `drops` (the one the map
## cache snapshots): read it; change the list only through add_drop / remove_drop / expire_drops.
func find_drop(uid: String) -> Dictionary:
	var i := _drop_index(uid)
	return drops[i] if i >= 0 else {}


func has_drop(uid: String) -> bool:
	return _drop_index(uid) >= 0


## Removes the record with this uid (picked up). Returns the removed record, or {} when there was none.
func remove_drop(uid: String) -> Dictionary:
	var i := _drop_index(uid)
	if i < 0:
		return {}
	var rec: Dictionary = drops[i]
	drops.remove_at(i)
	return rec


## Removes every record whose expires_at is at or before `now` and returns them in list order (the loot system
## announces each expiry). tick() and snapshot() call it too.
func expire_drops(now: float) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	var gone: Array[Dictionary] = []
	for d in drops:
		if float(d.get("expires_at", INF)) > now:
			kept.append(d)
		else:
			gone.append(d)
	drops = kept
	return gone


func _drop_index(uid: String) -> int:
	if uid == "":
		return -1
	for i in drops.size():
		if str(drops[i].get(DROP_UID_KEY, "")) == uid:
			return i
	return -1


## Parks the instance: everything needed to restore it later, as plain data.
func snapshot(now: float) -> Dictionary:
	expire_drops(now)
	return {
		"map_id": map_id,
		"capacity": capacity,
		"slots": slots.duplicate(true),
		"mob_times": mob_times.duplicate(),
		"drops": drops.duplicate(true),
		"last_tick_index": last_tick_index,
		"rng_seed": rng.seed if rng != null else 0,
		"rng_state": rng.state if rng != null else 0,
		"t": now,
	}


## Restores a snapshot and fast-forwards it to `now`. Returns null for an empty snapshot.
static func from_snapshot(snap: Dictionary, spawn_model: SpawnModel, now: float) -> MapInstanceState:
	if snap.is_empty():
		return null
	var st := MapInstanceState.new()
	st.map_id = String(snap.get("map_id", ""))
	st.capacity = int(snap.get("capacity", 0))
	st.model = spawn_model
	for s in snap.get("slots", []):
		var d: Dictionary = s
		st.slots.append({"alive": bool(d.get("alive", false)), "hp": int(d.get("hp", -1)),
			"died_at": float(d.get("died_at", -1.0))})
	st.mob_times = PackedFloat64Array(snap.get("mob_times", PackedFloat64Array()))
	for d in snap.get("drops", []):
		st.drops.append((d as Dictionary).duplicate(true))
	st.last_tick_index = int(snap.get("last_tick_index", 0))
	st.rng = RandomNumberGenerator.new()
	st.rng.seed = int(snap.get("rng_seed", 0))
	st.rng.state = int(snap.get("rng_state", 0))
	st.fast_forward(now)
	return st


func _dead_indices() -> Array[int]:
	var out: Array[int] = []
	for i in slots.size():
		if not bool(slots[i].alive):
			out.append(i)
	return out
