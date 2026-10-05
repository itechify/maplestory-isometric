class_name LootSystem
extends Node3D
## Ground loot (res://scenes/systems/loot_system.tscn): puts monster drops on the ground, lets the player pick them
## up with the pickup key, expires them, and keeps them in the live map instance so leaving and returning finds them
## again (MAP_ARCHITECTURE.md section 4.7.7).
##
## Data flow:
##   Events.loot_dropped(drops, world_position, map_id)            the monster system (DropRoller.roll output)
##     -> DropRoller.ground_records(drops, now, "player", db)       expires_at, owner, free_at, scatter offset
##     -> landing points: kill point + offset along the camera's ground right axis, grounded on the kill's tier
##     -> MapInstanceState.add_drop(record + uid + pos_local)       the record lives in the map instance
##     -> GroundDrop node (toss arc, hover, bob, spin, expiry blink)
##   pickup key (Z): the nearest landed drop inside the canonical pickup box (LootPickupRules, DropRates.pickup_box_m)
##     -> ItemService.pickup(record)                                  inventory or mesos; item_gained / mesos_changed
##     -> ok: MapInstanceState.remove_drop(uid), node freed, Events.notice("You have gained an item (Snail Shell)")
##     -> refused (inventory full, meso cap): the drop stays, Events.notice(the ItemCodes message)
##   every frame: MapInstanceState.expire_drops(now) removes expired records (the map instance also expires them on
##   its own tick) and the nodes are reconciled against the live MapInstanceState.drops. A map change rebuilds the
##   nodes from the restored records, with their remaining lifetime (the snapshot carries expires_at on the pausable
##   game clock).
##
## setup(ctx) wires it into the game; every collaborator is also injectable (tests, sandboxes): db, bus,
## character_provider, clock_provider, state_provider, def_provider, player, ground_axis_provider, space.

signal drop_spawned(node: GroundDrop)
signal drop_picked_up(record: Dictionary, result: Dictionary)
signal pickup_refused(record: Dictionary, result: Dictionary)
signal drop_expired(uid: String)

const GROUP := &"loot_system"
## Runs after the player controller (0), PortalInteractor (100) and the interaction system, so it reads the same
## presses the controller saw this tick.
const PHYSICS_PRIORITY := 120

var ctx: GameContext = null
var db: ContentDB = null
## Events bus (any Object with the Events signals). null = the Events autoload.
var bus: Object = null
## () -> CharacterState; empty = Game.character.
var character_provider: Callable = Callable()
## () -> float; empty = Game.clock.
var clock_provider: Callable = Callable()
## () -> MapInstanceState of the current map; empty = MapSession.instance_state.
var state_provider: Callable = Callable()
## () -> MapDefinition of the current map (for pos_local); empty = MapSession's current definition. May return null.
var def_provider: Callable = Callable()
## () -> Vector3 ground axis drops scatter along; empty = the camera rig's ground_right, else +X+Z.
var ground_axis_provider: Callable = Callable()
## The player (duck-typed: global_position, input_source, is_input_enabled, is_dead).
var player: Node3D = null
## Physics space for grounding drops; null = this node's world.
var space: PhysicsDirectSpaceState3D = null
## Who picks up (DropRoller ownership).
var owner_name: String = "player"
## Read the pickup key in _physics_process (off in tests that call try_pickup directly).
var read_input: bool = true
## MapSession (duck-typed is_idle()); null = the autoload. Tests set use_session = false.
var use_session: bool = true

var visuals: LootVisuals = null
var _nodes: Dictionary = {}
var _seq: int = 0
var _state_id: int = 0
var _hold_t: float = 0.0
## uids refused (inventory full, meso cap) since the pickup key went down; the hold-repeat skips them.
var _refused: Dictionary = {}
var _connected_bus: Object = null


func _ready() -> void:
	add_to_group(GROUP)
	process_physics_priority = PHYSICS_PRIORITY
	_ensure_ready()


func _exit_tree() -> void:
	_disconnect_bus()


## Wires the system into the game (GameContext contract). Null fields of ctx mean "not available"; a null ctx only
## connects the bus (tests and sandboxes that inject their collaborators).
func setup(p_ctx: GameContext) -> void:
	ctx = p_ctx
	if ctx != null and ctx.player is Node3D:
		player = ctx.player
	add_to_group(GROUP)
	_ensure_ready()
	if ctx != null:
		_register_debug_commands()


## Loads the visuals table and connects the bus (idempotent).
func _ensure_ready() -> void:
	if db == null:
		db = WorldUiServices.content()
	if visuals == null and db != null:
		visuals = LootVisuals.new(db)
	var b := _bus()
	if b != _connected_bus:
		_disconnect_bus()
		if b != null:
			for pair in [["loot_dropped", _on_loot_dropped], ["map_left", _on_map_left], ["map_entered", _on_map_entered]]:
				if b.has_signal(pair[0]) and not b.is_connected(pair[0], pair[1]):
					b.connect(pair[0], pair[1])
		_connected_bus = b


func _disconnect_bus() -> void:
	if _connected_bus == null or not is_instance_valid(_connected_bus):
		_connected_bus = null
		return
	for pair in [["loot_dropped", _on_loot_dropped], ["map_left", _on_map_left], ["map_entered", _on_map_entered]]:
		if _connected_bus.has_signal(pair[0]) and _connected_bus.is_connected(pair[0], pair[1]):
			_connected_bus.disconnect(pair[0], pair[1])
	_connected_bus = null


# --- frame -------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


func _physics_process(delta: float) -> void:
	if not read_input or player == null or not is_instance_valid(player):
		return
	# Not while climbing either: the prompt shows nothing on a ladder, and the key must not act where the prompt is
	# silent (InteractionResolver).
	if not WorldUiServices.player_can_act(player, ctx, _session()) \
			or (player.has_method("is_climbing") and bool(player.call("is_climbing"))):
		_hold_t = 0.0
		_refused.clear()
		return
	if WorldUiServices.pressed(player, &"pickup"):
		# A fresh press always tries (and explains) the drop the prompt names, refused before or not.
		_hold_t = 0.0
		_refused.clear()
		_note_refusal(try_pickup())
	elif WorldUiServices.held(player, &"pickup"):
		_hold_t += delta
		var repeat := visuals.num("pickup", "hold_repeat_s") if visuals != null else 0.0
		if repeat > 0.0 and _hold_t >= repeat:
			_hold_t = 0.0
			# Holding repeats over the drops not refused during this hold: a full inventory is said once per press,
			# not every hold_repeat_s, and a meso bag next to a refused item is still taken.
			_note_refusal(try_pickup(Vector3.INF, _refused))
	else:
		_hold_t = 0.0
		_refused.clear()


func _note_refusal(result: Dictionary) -> void:
	if not bool(result.get("ok", false)) and result.has("uid"):
		_refused[String(result["uid"])] = true


## Reconciles the nodes with the live records, expires old drops and advances the animations.
func tick(delta: float) -> void:
	_ensure_ready()
	var st := current_state()
	var sid := st.get_instance_id() if st != null else 0
	if sid != _state_id:
		clear_nodes()
		_state_id = sid
	if st == null:
		return
	var now := _now()
	# Expire records (the map instance also drops them on its own tick).
	for rec: Dictionary in st.expire_drops(now):
		drop_expired.emit(String(rec.get(LootPickupRules.UID_KEY, "")))
	# Nodes follow the records: a record without a node gets one at rest; a node without a record goes.
	var alive := {}
	for rec: Dictionary in st.drops:
		var uid := String(rec.get(LootPickupRules.UID_KEY, ""))
		if uid.is_empty():
			continue
		alive[uid] = true
		if not _nodes.has(uid):
			var at := _to_world(LootPickupRules.local_pos(rec))
			_spawn_node(rec, at, at, false)
	for uid: String in _nodes.keys():
		if not alive.has(uid):
			_free_node(uid)
	for uid: String in _nodes:
		(_nodes[uid] as GroundDrop).update(now, delta)


# --- spawning ----------------------------------------------------------------------------------------------------

## Puts rolled drops (DropRoller.roll output) on the ground around `world_position` in the current map. Returns the
## records added. Drops for another map than the live instance are ignored (warning).
func spawn_drops(drops: Array, world_position: Vector3, map_id: String = "") -> Array:
	_ensure_ready()
	var st := current_state()
	if st == null or db == null or drops.is_empty():
		return []
	if map_id != "" and st.map_id != "" and map_id != st.map_id:
		push_warning("[LootSystem] loot for %s ignored: the live map is %s" % [map_id, st.map_id])
		return []
	var now := _now()
	var records := DropRoller.ground_records(drops, now, owner_name, db)
	var points := LootPickupRules.scatter_points(world_position, records, _ground_axis())
	var origin_hit := _ground_y(world_position, INF)
	var origin_ground := origin_hit if origin_hit != INF else world_position.y
	var from := world_position + Vector3.UP * (visuals.num("placement", "toss_from_height_m") if visuals != null else 0.0)
	var added: Array = []
	for k in records.size():
		var rec: Dictionary = records[k]
		var landing := Vector3(points[k].x, origin_ground, points[k].z)
		if origin_hit != INF:
			landing = _landing(world_position, points[k], origin_ground)
		_seq += 1
		rec[LootPickupRules.UID_KEY] = "%s:%d:%d" % [st.map_id, Time.get_ticks_usec() % 1000000007, _seq]
		rec[LootPickupRules.POS_KEY] = LootPickupRules.encode_pos(_to_local(landing))
		st.add_drop(rec)
		_spawn_node(rec, landing, from, true)
		added.append(rec)
	return added


func _on_loot_dropped(drops: Array, world_position: Vector3, map_id: String) -> void:
	spawn_drops(drops, world_position, map_id)


func _on_map_left(_map_id: String) -> void:
	# The records stay in the instance (MapSession snapshots it right after this signal); only the nodes go.
	clear_nodes()
	_state_id = 0


func _on_map_entered(_map_id: String, _previous: String) -> void:
	clear_nodes()
	_state_id = 0
	tick(0.0)


func _spawn_node(rec: Dictionary, landing: Vector3, from: Vector3, toss: bool) -> GroundDrop:
	var n := GroundDrop.new()
	add_child(n)
	n.setup(rec, visuals if visuals != null else LootVisuals.new(db), landing, from, toss)
	_nodes[n.uid] = n
	drop_spawned.emit(n)
	return n


func _free_node(uid: String) -> void:
	var n: Variant = _nodes.get(uid)
	_nodes.erase(uid)
	if n is Node and is_instance_valid(n):
		var parent := (n as Node).get_parent()
		if parent != null:
			parent.remove_child(n)
		(n as Node).free()


## Frees every drop node (the records are untouched).
func clear_nodes() -> void:
	for uid: String in _nodes.keys():
		_free_node(uid)
	_nodes.clear()


# --- pickup ------------------------------------------------------------------------------------------------------

## The drop the pickup key would take now: {"uid", "position", "label", "record"} or {} (also used by the prompt).
## `exclude` (uid -> true) leaves drops out (the hold-repeat skips the ones it was refused).
func pickup_target(feet: Vector3 = Vector3.INF, exclude: Dictionary = {}) -> Dictionary:
	if feet == Vector3.INF:
		if player == null or not is_instance_valid(player):
			return {}
		feet = player.global_position
	if db == null:
		return {}
	var now := _now()
	var candidates: Array = []
	var st := current_state()
	if st == null:
		return {}
	for rec: Dictionary in st.drops:
		var uid := String(rec.get(LootPickupRules.UID_KEY, ""))
		var n: GroundDrop = _nodes.get(uid)
		if n == null or not n.is_landed() or exclude.has(uid) or not DropRoller.may_pick_up(rec, owner_name, now):
			continue
		candidates.append({"uid": uid, "position": n.landing, "record": rec})
	var t := LootPickupRules.pick_target(feet, candidates, DropRates.pickup_box_m(db))
	if not t.is_empty():
		t["label"] = LootPickupRules.drop_label(t["record"], db)
	return t


## Picks up the drop pickup_target() names. Returns ItemService.pickup's result ({"ok", "code", ...}), or
## {"ok": false, "code": "nothing"} when no drop is in the box. On success the record leaves the map instance, the
## node goes and Events.notice announces the gain; a refusal leaves the drop and announces the reason. The result also
## carries the drop's "uid". `exclude`: see pickup_target.
func try_pickup(feet: Vector3 = Vector3.INF, exclude: Dictionary = {}) -> Dictionary:
	var t := pickup_target(feet, exclude)
	if t.is_empty():
		return {"ok": false, "code": "nothing"}
	var c := _character()
	if c == null:
		return {"ok": false, "code": "no_character"}
	var rec: Dictionary = t["record"]
	var result := ItemService.new(c, db, _bus()).pickup(rec)
	result["uid"] = String(t["uid"])
	if bool(result.get("ok", false)):
		remove_record(String(t["uid"]))
		WorldUiServices.emit(_bus(), &"notice", [LootPickupRules.pickup_notice(result, db)])
		drop_picked_up.emit(rec, result)
	else:
		WorldUiServices.emit(_bus(), &"notice", [LootPickupRules.refusal_notice(result, db)])
		pickup_refused.emit(rec, result)
	return result


## Removes a record (by uid) from the live map instance and frees its node. True if it was there.
func remove_record(uid: String) -> bool:
	var st := current_state()
	var found := st != null and not st.remove_drop(uid).is_empty()
	if _nodes.has(uid):
		_free_node(uid)
	return found


## Live drop nodes by uid (read-only use: tests, debug).
func nodes() -> Dictionary:
	return _nodes


func node_for(uid: String) -> GroundDrop:
	return _nodes.get(uid)


# --- collaborators -----------------------------------------------------------------------------------------------

func current_state() -> MapInstanceState:
	if state_provider.is_valid():
		var v: Variant = state_provider.call()
		return v if v is MapInstanceState else null
	var s := _session()
	var v2: Variant = s.get("instance_state") if s != null else null
	return v2 if v2 is MapInstanceState else null


func _current_def() -> MapDefinition:
	if def_provider.is_valid():
		var v: Variant = def_provider.call()
		return v if v is MapDefinition else null
	var s := _session()
	if s == null or not s.has_method("get_defs"):
		return null
	var defs: Variant = s.call("get_defs")
	var map_id := String(s.get("current_map"))
	if defs is MapDefinitions and map_id != "":
		return (defs as MapDefinitions).get_def(map_id)
	return null


func _to_local(world: Vector3) -> Vector3:
	var d := _current_def()
	return d.to_local(world) if d != null else world


func _to_world(local: Vector3) -> Vector3:
	var d := _current_def()
	return d.to_world(local) if d != null else local


func _session() -> Node:
	return WorldUiServices.session() if use_session else null


func _bus() -> Object:
	return bus if bus != null else WorldUiServices.events()


func _character() -> CharacterState:
	if character_provider.is_valid():
		var v: Variant = character_provider.call()
		return v if v is CharacterState else null
	return WorldUiServices.character()


func _now() -> float:
	if clock_provider.is_valid():
		return float(clock_provider.call())
	return WorldUiServices.clock()


func _ground_axis() -> Vector3:
	if ground_axis_provider.is_valid():
		return ground_axis_provider.call()
	var cam: Variant = ctx.camera if ctx != null else null
	if cam is Object and "ground_right" in cam:
		return cam.get("ground_right")
	return Vector3(1, 0, 1).normalized()


## Where a scatter point lands: on the kill's tier (within placement.ground_step_tolerance_m of the kill's ground),
## trying the full offset, then half, then the kill point itself. (Without any ground under the kill point, e.g. an
## empty test world, the scatter point keeps the kill's height.)
func _landing(origin: Vector3, point: Vector3, origin_ground: float) -> Vector3:
	var tol := visuals.num("placement", "ground_step_tolerance_m") if visuals != null else 0.0
	for f in [1.0, 0.5, 0.0]:
		var p := origin.lerp(point, f)
		var y := _ground_y(p, INF)
		if y != INF and (tol <= 0.0 or absf(y - origin_ground) <= tol):
			return Vector3(p.x, y, p.z)
	return Vector3(origin.x, origin_ground, origin.z)


## The first walkable/blocking surface under `p` (motion.ground_probe_up_m above to ground_probe_down_m below), or
## `fallback` when there is none (no physics world in tests).
func _ground_y(p: Vector3, fallback: float) -> float:
	var sp := space
	if sp == null and is_inside_tree():
		sp = get_world_3d().direct_space_state
	if sp == null:
		return p.y if fallback == INF else fallback
	var up := visuals.motion("ground_probe_up_m") if visuals != null else 1.0
	var down := visuals.motion("ground_probe_down_m") if visuals != null else 3.0
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * up, p - Vector3.UP * down, WorldLayers.SURFACE_MASK)
	var hit := sp.intersect_ray(q)
	if hit.is_empty():
		return fallback
	return (hit.position as Vector3).y


# --- debug -------------------------------------------------------------------------------------------------------

func _register_debug_commands() -> void:
	var dbg := WorldUiServices.autoload("Debug")
	if dbg == null or not dbg.has_method("register_command"):
		return
	dbg.call("register_command", "loot", "loot <owner_id> [kills]: roll an owner's drop record at the player's feet (quest-gated drops follow the character's quests)", _cmd_loot)
	dbg.call("register_command", "drop_item", "drop_item <item_id> [qty]: put an item on the ground at the player's feet", _cmd_drop_item)
	dbg.call("register_command", "drop_mesos", "drop_mesos <amount>: put mesos on the ground at the player's feet", _cmd_drop_mesos)


func _feet_or_origin() -> Vector3:
	return player.global_position if player != null and is_instance_valid(player) else global_position


func _cmd_loot(args: PackedStringArray) -> String:
	if args.is_empty():
		return "usage: loot <owner_id> [kills]"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var total := 0
	var ctx := DropRoller.context_for(_character())
	for k in maxi(1, int(args[1]) if args.size() > 1 else 1):
		total += spawn_drops(DropRoller.roll(args[0], db, rng, ctx), _feet_or_origin()).size()
	return "%d drops on the ground" % total


func _cmd_drop_item(args: PackedStringArray) -> String:
	if args.is_empty() or db == null or not db.has("items", args[0]):
		return "usage: drop_item <item_id> [qty] (a canonical item id)"
	var qty := maxi(1, int(args[1]) if args.size() > 1 else 1)
	return "%d drop(s) on the ground" % spawn_drops([{"kind": "item", "item_id": args[0], "qty": qty}], _feet_or_origin()).size()


func _cmd_drop_mesos(args: PackedStringArray) -> String:
	if args.is_empty() or int(args[0]) <= 0:
		return "usage: drop_mesos <amount>"
	return "%d drop(s) on the ground" % spawn_drops([{"kind": "mesos", "amount": int(args[0])}], _feet_or_origin()).size()
