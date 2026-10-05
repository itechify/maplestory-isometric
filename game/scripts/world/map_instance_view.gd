class_name MapInstanceView
extends Node3D
## Live monsters of the current map only (MAP_ARCHITECTURE.md sections 4.5 step 8 and 4.7.4).
##
## realize(state, def, arrival_pos) queues every alive slot nearest-first and spawns at most
## spawns.realize_per_frame per frame, each fading in over spawns.fade_in_s. While live it ticks the instance on
## Game.clock and spawns respawned slots. release() hands every node back (survivor HP is written into the state)
## and clears the queue. Monster nodes come from `monster_factory`:
##   monster_factory: Callable(mob_id: String, slot: SpawnSlot) -> Node3D
## The default factory places the static proxy model from _library.glb; the monster system replaces it with real
## monsters (and may set `monster_releaser: Callable(node: Node3D) -> void` to pool them; the default frees them).
## A spawned node carries metadata spawn_slot (int), mob_id, map_id. Report a kill with notify_killed(slot) or
## notify_node_killed(node); a node with a `died` signal is connected automatically. debug_kill(node) is the debug
## console's kill: the monster's own death when it has one, else the slot kill, else (no slot) a plain release.
##
## Only MeowDB spawn points are slots. A node made for SpawnSlot.NO_SLOT (-1: the debug console's `spawn`, which
## calls monster_factory itself and parents the node here) is never in `nodes`, is never connected to `died`, never
## has a kill recorded and is never respawned; notify_killed(-1) and notify_node_killed() of such a node return false.
##
## A respawn (a slot the tick brought back) is never realized within spawns.respawn_player_clearance_m of the player's
## feet (`player_position`, set by the monster system): it waits at the back of the queue until the player has moved
## away. The slot stays alive in MapInstanceState meanwhile, so capacity and counts are unchanged (an adaptation:
## the brief's 'avoid spawning directly inside the player').

signal monster_spawned(node: Node3D, slot: SpawnSlot)
signal monster_released(node: Node3D, slot_index: int)

var monster_factory: Callable = Callable()
var monster_releaser: Callable = Callable()
var library: ProxyLibrary = null
var tuning: WorldTuning = null
## () -> float, the game time; defaults to the Game autoload's clock.
var clock: Callable = Callable()
## () -> Variant, the player's feet (Vector3) or null without a player; set by the monster system. Unset: no respawn
## clearance check.
var player_position: Callable = Callable()
var state: MapInstanceState = null
var def: MapDefinition = null
## slot index -> Node3D
var nodes: Dictionary = {}
## Respawns that had to wait because the player stood on their slot (tests, the debug overlay).
var deferred_respawns: int = 0

var _queue: Array[int] = []
## Queued slots that came back on a respawn tick (only these wait for the player to move away).
var _respawning: Dictionary = {}
var _arrival := Vector3.ZERO
var _pool: Dictionary = {}
var _fading: Array[Dictionary] = []
## node instance id -> the Callable connected to its died signal (disconnected on release).
var _died_links: Dictionary = {}


func _ready() -> void:
	if not monster_factory.is_valid():
		monster_factory = default_factory


## Activates `st` for `d`: alive slots are spawned over the next frames, nearest to `arrival_pos` first.
func realize(st: MapInstanceState, d: MapDefinition, arrival_pos: Vector3) -> void:
	release()
	state = st
	def = d
	_arrival = arrival_pos
	if st == null or d == null:
		return
	for i in st.alive_indices():
		_queue.append(i)
	_sort_queue()


## Returns every live monster node and forgets the instance. Survivor HP (a node's `hp` property, when it has one)
## is kept in the state so the snapshot restores it.
func release() -> void:
	for i in nodes.keys():
		var n: Node3D = nodes[i]
		if is_instance_valid(n):
			if state != null and state.is_alive(int(i)) and "hp" in n:
				state.set_hp(int(i), int(n.get("hp")))
			_release_node(n, int(i))
	nodes.clear()
	_queue.clear()
	_respawning.clear()
	_fading.clear()
	state = null
	def = null


## The slot's monster died: records died_at in the state and hands the node back. False if it was not alive, or
## for SpawnSlot.NO_SLOT / any index that is not one of this map's slots (nothing is recorded).
func notify_killed(slot_index: int) -> bool:
	if state == null or slot_index < 0 or not state.kill(slot_index, _now()):
		return false
	var n: Node3D = nodes.get(slot_index, null)
	nodes.erase(slot_index)
	_queue.erase(slot_index)
	_respawning.erase(slot_index)
	if n != null and is_instance_valid(n):
		_release_node(n, slot_index)
	return true


## A monster node died: its slot's kill is recorded. Only the node this view spawned for that slot counts, so a
## debug spawn (spawn_slot -1) or a stale node from an earlier realize never kills a live slot.
func notify_node_killed(node: Node) -> bool:
	var i := slot_of(node)
	return i >= 0 and notify_killed(i)


## The slot index `node` occupies in this view, or SpawnSlot.NO_SLOT when it is not one of this view's slot
## monsters (a debug spawn, a released or foreign node).
func slot_of(node: Node) -> int:
	if node == null or not is_instance_valid(node) or not node.has_meta("spawn_slot"):
		return SpawnSlot.NO_SLOT
	var i := int(node.get_meta("spawn_slot"))
	return i if i >= 0 and nodes.get(i, null) == node else SpawnSlot.NO_SLOT


## The debug console's kill of one monster node. Returns {"own_death": bool, "slot": int, "recorded": bool}:
##   - the node has a zero-argument die() (the monster system's Monster): it runs, so EXP, drops and
##     Events.monster_killed happen as in play; a slot monster's `died` signal then records the kill here, a
##     NO_SLOT monster's is not connected to this view and records nothing;
##   - else a slot monster of this view: notify_killed(slot) (the kill is recorded, the node handed back);
##   - else (a NO_SLOT node without a death of its own): it is released (monster_releaser, else queue_free) and
##     nothing is recorded. The caller announces monster_killed for the last two cases if it wants quest credit.
func debug_kill(node: Node) -> Dictionary:
	var out := {"own_death": false, "slot": slot_of(node), "recorded": false}
	if node == null or not is_instance_valid(node):
		return out
	var slot := int(out.slot)
	if _has_zero_arg_method(node, "die"):
		node.call("die")
		out["own_death"] = true
		out["recorded"] = slot >= 0 and state != null and not state.is_alive(slot)
		return out
	if slot >= 0:
		out["recorded"] = notify_killed(slot)
		return out
	if node is Node3D:
		_release_node(node as Node3D, SpawnSlot.NO_SLOT)
	return out


static func _has_zero_arg_method(n: Object, method: String) -> bool:
	if not n.has_method(method):
		return false
	for m in n.get_method_list():
		if String(m.name) == method:
			return (m.args as Array).size() - (m.default_args as Array).size() <= 0
	return false


## Number of monster nodes currently in the scene.
func live_count() -> int:
	return nodes.size()


func pending_count() -> int:
	return _queue.size()


## The default factory: the species' static proxy from _library.glb (sidecar species -> proxy, else
## "Mob_<MeowDB name without spaces>"), or a labelled placeholder.
func default_factory(mob_id: String, slot: SpawnSlot) -> Node3D:
	var name_ := String(def.mob_names.get(mob_id, mob_id)) if def != null else mob_id
	var asset := String(def.species_proxies.get(name_, "")) if def != null else ""
	if asset == "":
		asset = "Mob_" + name_.replace(" ", "").replace(".", "")
	var pool: Array = _pool.get(asset, [])
	var n: Node3D = pool.pop_back() if not pool.is_empty() else null
	if n == null:
		n = library.instance_or_placeholder(asset, name_, library.typical("Mob_")) if library != null else Node3D.new()
		n.set_meta("default_proxy", asset)
	n.transform = slot.transform
	return n


func _process(delta: float) -> void:
	if state == null:
		return
	for i in state.tick(_now()):
		if not _queue.has(i) and not nodes.has(i):
			_queue.append(i)
			_respawning[i] = true
	var budget := tuning.count("spawns", "realize_per_frame") if tuning != null else _queue.size()
	var looked := 0
	var waiting := _queue.size()
	while budget > 0 and looked < waiting and not _queue.is_empty():
		var i: int = _queue.pop_front()
		looked += 1
		if _respawning.has(i) and respawn_blocked(i):
			_queue.append(i)
			deferred_respawns += 1
			continue
		_respawning.erase(i)
		_spawn(i)
		budget -= 1
	_advance_fades(delta)


## True when slot `i`'s respawn must wait: the player's feet are within spawns.respawn_player_clearance_m of it.
func respawn_blocked(i: int) -> bool:
	if not player_position.is_valid() or def == null or tuning == null or i < 0 or i >= def.monster_spawn_definitions.size():
		return false
	var at: Variant = player_position.call()
	if not (at is Vector3):
		return false
	return (at as Vector3).distance_to(def.monster_spawn_definitions[i].position()) < tuning.num("spawns", "respawn_player_clearance_m")


func _spawn(i: int) -> void:
	if def == null or i < 0 or i >= def.monster_spawn_definitions.size() or not state.is_alive(i):
		return
	var slot := def.monster_spawn_definitions[i]
	var n: Node3D = monster_factory.call(slot.mob_id, slot)
	if n == null:
		return
	n.set_meta("spawn_slot", i)
	n.set_meta("mob_id", slot.mob_id)
	n.set_meta("map_id", def.map_id)
	if n.get_parent() == null:
		add_child(n)
	nodes[i] = n
	if n.has_signal("died"):
		var argc := 0
		for sig in n.get_signal_list():
			if String(sig.name) == "died":
				argc = (sig.args as Array).size()
		var link := _on_died.bind(i).unbind(argc)
		n.connect("died", link)
		_died_links[n.get_instance_id()] = link
	if n.has_meta("default_proxy") and tuning != null:
		var t := tuning.num("spawns", "fade_in_s")
		if t > 0.0:
			n.scale = Vector3.ONE * 0.01
			_fading.append({"node": n, "t": 0.0, "d": t})
	monster_spawned.emit(n, slot)


func _on_died(slot_index: int) -> void:
	notify_killed(slot_index)


func _release_node(n: Node3D, slot_index: int) -> void:
	var link: Variant = _died_links.get(n.get_instance_id(), null)
	if link is Callable and n.is_connected("died", link):
		n.disconnect("died", link)
	_died_links.erase(n.get_instance_id())
	monster_released.emit(n, slot_index)
	if n.has_meta("default_proxy"):
		n.scale = Vector3.ONE
		if n.get_parent() == self:
			remove_child(n)
		var asset := String(n.get_meta("default_proxy"))
		if not _pool.has(asset):
			_pool[asset] = []
		(_pool[asset] as Array).append(n)
	elif monster_releaser.is_valid():
		monster_releaser.call(n)
	else:
		n.queue_free()


func _advance_fades(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for f in _fading:
		var n: Node3D = f.node
		if not is_instance_valid(n) or n.get_parent() == null:
			continue
		f.t = float(f.t) + delta
		var k := clampf(float(f.t) / float(f.d), 0.0, 1.0)
		n.scale = Vector3.ONE * maxf(k, 0.01)
		if k < 1.0:
			keep.append(f)
	_fading = keep


func _sort_queue() -> void:
	var slots := def.monster_spawn_definitions
	var origin := _arrival
	_queue.sort_custom(func(a: int, b: int) -> bool:
		return slots[a].transform.origin.distance_squared_to(origin) < slots[b].transform.origin.distance_squared_to(origin))


func _now() -> float:
	if clock.is_valid():
		return float(clock.call())
	var game: Node = get_node_or_null("/root/Game")
	return float(game.get("clock")) if game != null else 0.0


func _exit_tree() -> void:
	for asset in _pool:
		for n in _pool[asset]:
			if is_instance_valid(n) and (n as Node).get_parent() == null:
				(n as Node).free()
	_pool.clear()
