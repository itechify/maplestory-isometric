class_name BreakableSystem
extends Node3D
## The Wooden Boxes of the current map in the real scene (scenes/systems/breakable_system.tscn), contract C8.
##
## Data flow:
##   the live MapInstanceState (MapSession.instance_state)             breakables[i]: hits, respawn_at (pure state)
##     -> BreakablePlacementPlanner.plan(def, world ground query)      where each placement stands (cached per map)
##     -> one WoodenBox per placed placement, showing its state        group &"miso_breakables"
##   the player's basic attack (PlayerCombat.attack_started)           the swing's canonical hit box (last_box_px)
##     -> MeleeQuery.pick over attack_candidates() (intact boxes)      nearest box whose body the box overlaps
##     -> land_hit(box): MapInstanceState.hit_breakable(i, now, hits_to_break)   one landed hit (breakables.json)
##     -> at hits_to_break: BreakableRules.roll_drops("0000001", db, rng, {"quests_in_progress": ...}) (contract C2)
##        and Events.loot_dropped(drops, box position, map_id): the loot system puts them on the ground
##   every frame: MapInstanceState.tick_breakables(now) brings boxes back respawn_s after the break (game clock)
## The state is re-read every frame by identity, so a map change, a reload_map() (no event) or a load re-realizes the
## boxes. Nothing here is saved: the state lives in the map instance (cached for parked maps, never in a save).
##
## Other attack sources ask attack_candidates() (MeleeQuery candidate shape plus "kind": "breakable") or the group, and
## call land_hit(box, source) for a box they reached: a Three Snails cast does (PlayerSkills._search / _hit_box, which
## find this system by its group &"breakable_system"; source "skill:0001000"), one landed hit per throw that picks a box.
##
## setup(ctx) wires it into the game; every collaborator is injectable (tests): db, bus, session, character_provider,
## clock_provider, state_provider, def_provider, ground, rng, roller, player.

## A landed hit counted on `box`; `hits_left` 0 means it broke.
signal box_hit(box: WoodenBox, hits_left: int)
## `box` broke and rolled `drops` (DropRoller output; announced with Events.loot_dropped when not empty).
signal box_broken(box: WoodenBox, drops: Array)
signal box_respawned(box: WoodenBox)
## The boxes of `map_id` were (re)built from its live state.
signal boxes_realized(map_id: String, count: int)

const GROUP := WoodenBox.GROUP
## How often the boxes' cues are refreshed (s), and how far above or below the player's feet a box still counts as
## within reach (m: the attack boxes are about a body tall). Presentation.
const CUE_REFRESH_S := 0.1
const CUE_TIER_DY_M := 0.6

var ctx: GameContext = null
## The player (duck-typed: global_position, facing, a "PlayerCombat" child with attack_started and last_box_px).
var player: Node3D = null
## The PlayerCombat whose attack_started this system listens to.
var player_combat: Node = null
# --- injection seams (null / empty = the autoloads and the world) ------------------------------------------------
var db: ContentDB = null
var bus: Object = null
var session: Node = null
var character_provider: Callable = Callable()
var clock_provider: Callable = Callable()
## () -> MapInstanceState of the current map; empty = MapSession.instance_state.
var state_provider: Callable = Callable()
## (map_id: String) -> MapDefinition; empty = MapSession.get_defs().get_def(map_id).
var def_provider: Callable = Callable()
## Where boxes are placed; null = the world's PhysicsGroundQuery (ctx.world.ground_query).
var ground: GroundQuery = null
var rng: RandomNumberGenerator = null
## (owner_id: String, db: ContentDB, rng: RandomNumberGenerator, ctx: Dictionary) -> Array; empty =
## BreakableRules.roll_drops (DropRoller.roll, contract C2).
var roller: Callable = Callable()

## Live boxes of the current map: placement index -> WoodenBox.
var boxes: Dictionary = {}
var state: MapInstanceState = null
var def: MapDefinition = null
## map_id -> Array[BreakablePlacement] (plans are deterministic, so each map is planned once).
var plans: Dictionary = {}
## Warnings of every plan made (placements that found no room).
var plan_warnings: PackedStringArray = []
# --- counters (tests, the console) -------------------------------------------------------------------------------
var hits_landed: int = 0
var boxes_broken: int = 0

var _combat_link: Callable = Callable()
var _connected_bus: Object = null
var _cue_t: float = 0.0
var _reach_key: String = ""
var _reach_cache: float = 0.0


func _ready() -> void:
	add_to_group(&"breakable_system")


func _exit_tree() -> void:
	_disconnect_combat()
	_disconnect_bus()


## Wires the system into the game (GameContext contract). A null field of ctx means "not available".
func setup(p_ctx: GameContext) -> void:
	ctx = p_ctx
	if ctx != null and ctx.player is Node3D:
		attach_player(ctx.player as Node3D)
	_connect_bus()
	if ctx != null:
		_register_debug_commands()


## Listens to `p`'s basic attack (its PlayerCombat child, which MonsterSystem adds; re-checked every frame).
func attach_player(p: Node3D) -> void:
	player = p
	_connect_combat()


func _process(delta: float) -> void:
	tick(delta)


## One frame: follow the live state (realize on a new instance), bring boxes back whose time has come, make sure
## the player's attack is heard, and refresh the boxes' cues a few times a second.
func tick(delta: float) -> void:
	_connect_combat()
	var st := current_state()
	if st != state:
		realize(st)
		_cue_t = 0.0
	if state == null:
		return
	_bring_back(state.tick_breakables(_now()))
	_cue_t -= delta
	if _cue_t <= 0.0:
		_cue_t = CUE_REFRESH_S
		update_cues()


# --- cues -----------------------------------------------------------------------------------------------------------

## Tells the breakable boxes from the decorative crates (presentation; the acceptance review could not): every intact
## box whose body the player's basic attack can reach from where the player stands shows its rim (within reach_m()
## horizontally, on the player's tier), and while a quest that needs one of the box's quest-gated drops is in progress
## and still short of it (wanted()), every intact box shows its marker.
func update_cues() -> void:
	var feet: Variant = player.global_position if player != null and is_instance_valid(player) else null
	var reach := reach_m()
	var want := wanted()
	for box in live_boxes():
		var intact := state != null and state.is_breakable_intact(box.index())
		var near := false
		if feet is Vector3 and reach > 0.0:
			var f: Vector3 = feet
			near = Vector2(box.global_position.x - f.x, box.global_position.z - f.z).length() <= reach \
				and absf(box.global_position.y - f.y) <= CUE_TIER_DY_M
		box.set_cues(near and intact, want and intact)


## How far (m, horizontal, feet to feet) every basic attack of the character's weapon reaches a box: the shortest
## far edge of its canonical attack boxes (CombatReach.attack_box_px) plus half the box's body (touch_px). 0 without
## a character.
func reach_m() -> float:
	var c := _character()
	if c == null:
		return 0.0
	var stats := PlayerCombatStats.from_character(c, _db())
	var weapon := stats.weapon if stats.weapon != null else WeaponProfile.bare_hands(_db())
	var key := "%s:%d" % [weapon.item_id, c.level]
	if key == _reach_key:
		return _reach_cache
	var far := INF
	for action: Variant in weapon.ordinary_actions().keys():
		for pres in weapon.presentations_for(String(action)):
			far = minf(far, CombatReach.attack_box_px(weapon, pres, true, c.level).end.x)
	_reach_key = key
	_reach_cache = 0.0 if far == INF else WorldScale.actor(far + BreakableRules.touch_px(_db()).x * 0.5)
	return _reach_cache


## True while a quest gating one of this box's drops (contract C1 quest_gate: Pio's quest for the Old Wooden Board
## and the Rusty Screw) is in progress and the character holds fewer of that item than the quest asks for.
func wanted(owner_id: String = BreakableRules.WOODEN_BOX) -> bool:
	var c := _character()
	if c == null or c.quests == null:
		return false
	var active := c.quests.active_ids()
	for row: Dictionary in DropRates.effective_entries(owner_id, _db()):
		var qid := String(row.get("quest_gate", ""))
		var item := String(row.get("item_id", ""))
		if qid == "" or item == "" or String(row.get("excluded", "")) != "" or not (qid in active):
			continue
		var need := 0
		var q := QuestDef.from_records(_db().quest(qid), _db().miso_entity("quests", qid))
		for o: Dictionary in q.objectives_of("item_collection"):
			if String(o.get("id", "")) == item:
				need = int(o.get("count", 0))
		if c.inventory.count(item) < maxi(need, 1):
			return true
	return false


## Shows the placements `indices` came back (MapInstanceState.tick_breakables) on their boxes and announces them. Every
## path that ticks the state passes its result here, so a box node never stays broken after its state came back.
func _bring_back(indices: PackedInt32Array) -> void:
	for i in indices:
		var box: WoodenBox = boxes.get(i, null)
		if box != null and is_instance_valid(box):
			box.show_respawn()
			box_respawned.emit(box)


## Builds the boxes of `st` (its map's placements, showing the state's hits and broken boxes). null releases them.
func realize(st: MapInstanceState) -> void:
	release()
	if st == null:
		return
	var d := _def_of(st.map_id)
	if d == null or st.breakable_count() == 0:
		state = st
		def = d
		return
	var places := placements_for(d)
	if places.is_empty():
		return  # no ground to plan on yet (the world is still loading): try again next frame
	state = st
	def = d
	st.tick_breakables(_now())
	var size := BreakableRules.size_m(_db())
	var n := hits_to_break()
	for b: BreakablePlacement in places:
		if not b.is_placed() or not st.has_breakable(b.index):
			continue
		var box := WoodenBox.new()
		add_child(box)
		box.setup(b, size, n, st.breakable_hits(b.index), not st.is_breakable_intact(b.index), self)
		boxes[b.index] = box
	boxes_realized.emit(st.map_id, boxes.size())


## Frees the boxes and forgets the instance (its state stays in the map instance).
func release() -> void:
	for i in boxes:
		var box: Node = boxes[i]
		if is_instance_valid(box):
			box.queue_free()
			if box.get_parent() == self:
				remove_child(box)
	boxes.clear()
	state = null
	def = null


## The placements of `d` (planned on first use, then cached). [] while there is no ground to plan on.
func placements_for(d: MapDefinition) -> Array:
	if plans.has(d.map_id):
		return plans[d.map_id]
	var q := _ground()
	if q == null:
		return []
	var res := BreakablePlacementPlanner.plan(d, q, _tuning(), _db())
	for w in res.warnings:
		push_warning("[BreakableSystem] " + w)
		plan_warnings.append(w)
	plans[d.map_id] = res.placements
	return res.placements


## Live boxes of the current map, in placement order.
func live_boxes() -> Array[WoodenBox]:
	var out: Array[WoodenBox] = []
	var keys := boxes.keys()
	keys.sort()
	for i in keys:
		var box: WoodenBox = boxes[i]
		if is_instance_valid(box):
			out.append(box)
	return out


## Canonical landed hits that break a Wooden Box (canonical breakables/0000001.json).
func hits_to_break(id: String = BreakableRules.WOODEN_BOX) -> int:
	return BreakableRules.hits_to_break(id, _db())


# --- hits ---------------------------------------------------------------------------------------------------------

## Attack candidates for MeleeQuery.pick: every intact box, its body (breakables.json box.touch_px, as deep as it is
## wide) at its feet. Same shape as MonsterSystem.attack_candidates, plus "kind": "breakable".
func attack_candidates() -> Array:
	var out: Array = []
	var px := BreakableRules.touch_px(_db())
	if px == Vector2.ZERO:
		return out
	for box in live_boxes():
		# The state decides (a node is only its picture).
		if state != null and state.is_breakable_intact(box.index()):
			out.append({"node": box, "feet": box.global_position, "touch_px": px, "depth_px": px.x,
				"spawn_order": box.index(), "kind": "breakable"})
	return out


## One attack whose hit box is `box_px` (px, facing +x, CombatReach.attack_box_px) and `depth_px` deep, made from
## `origin` facing `facing`: the nearest intact boxes it overlaps (breakables.json hit_rule.boxes_per_attack) take one
## landed hit each. Returns the nearest box hit, or null when the attack reached none.
func land_attack(origin: Vector3, facing: Vector3, box_px: Rect2, depth_px: float, source: String = "attack") -> WoodenBox:
	var hits := MeleeQuery.pick(origin, facing, box_px, depth_px, attack_candidates(), BreakableRules.boxes_per_attack(_db()))
	var first: WoodenBox = null
	for h: Dictionary in hits:
		var box: WoodenBox = h["node"]
		if bool(land_hit(box, source).get("counted", false)) and first == null:
			first = box
	return first


## One landed hit on `box` (a box of this system): MapInstanceState.hit_breakable; at the canonical count it breaks
## and its drops are rolled and announced. Returns {"counted", "hits", "broke", "hits_left", "drops" (when it broke)}.
func land_hit(box: WoodenBox, _source: String = "attack") -> Dictionary:
	var out := {"counted": false, "hits": 0, "broke": false, "hits_left": 0}
	if box == null or not is_instance_valid(box) or state == null or boxes.get(box.index(), null) != box:
		return out
	var n := hits_to_break(box.placement.breakable_id)
	var now := _now()
	# Placements whose time came are brought back on their nodes first: hit_breakable would tick them silently.
	_bring_back(state.tick_breakables(now))
	var r := state.hit_breakable(box.index(), now, n)
	out.merge(r, true)
	if not bool(r.counted):
		return out
	hits_landed += 1
	var left := 0 if bool(r.broke) else maxi(n - int(r.hits), 0)
	out["hits_left"] = left
	if bool(r.broke):
		box.show_break()
		var drops := _roll(box.placement.breakable_id)
		out["drops"] = drops
		boxes_broken += 1
		if not drops.is_empty():
			WorldUiServices.emit(_bus(), &"loot_dropped", [drops, box.global_position, state.map_id])
		box_hit.emit(box, 0)
		box_broken.emit(box, drops)
	else:
		box.show_hit(left)
		box_hit.emit(box, left)
	return out


func _roll(owner_id: String) -> Array:
	var c := BreakableRules.drop_context(_character())
	if roller.is_valid():
		var v: Variant = roller.call(owner_id, _db(), _rng(), c)
		return v if v is Array else []
	return BreakableRules.roll_drops(owner_id, _db(), _rng(), c)


## The player swung (PlayerCombat.attack_started): its canonical hit box, placed in front of the player.
func _on_player_attack() -> void:
	if player == null or not is_instance_valid(player) or player_combat == null or not is_instance_valid(player_combat):
		return
	var box_px: Variant = player_combat.get("last_box_px")
	if not (box_px is Rect2):
		return
	var facing: Vector3 = player.get("facing") if "facing" in player else Vector3.BACK
	land_attack(player.global_position, facing, box_px, CombatReach.attack_box_depth_px(_db()))


# --- wiring -------------------------------------------------------------------------------------------------------

func _connect_combat() -> void:
	var pc: Node = player.get_node_or_null(^"PlayerCombat") if player != null and is_instance_valid(player) else null
	if pc == player_combat and (pc == null or (_combat_link.is_valid() and pc.is_connected(&"attack_started", _combat_link))):
		return
	_disconnect_combat()
	if pc == null or not pc.has_signal(&"attack_started"):
		return
	var argc := 0
	for sig in pc.get_signal_list():
		if String(sig.name) == "attack_started":
			argc = (sig.args as Array).size()
	_combat_link = _on_player_attack.unbind(argc) if argc > 0 else _on_player_attack
	pc.connect(&"attack_started", _combat_link)
	player_combat = pc


func _disconnect_combat() -> void:
	if player_combat != null and is_instance_valid(player_combat) and _combat_link.is_valid() \
			and player_combat.is_connected(&"attack_started", _combat_link):
		player_combat.disconnect(&"attack_started", _combat_link)
	player_combat = null
	_combat_link = Callable()


func _connect_bus() -> void:
	var b := _bus()
	if b == _connected_bus:
		return
	_disconnect_bus()
	if b != null and b.has_signal(&"map_left") and not b.is_connected(&"map_left", _on_map_left):
		b.connect(&"map_left", _on_map_left)
	_connected_bus = b


func _disconnect_bus() -> void:
	if _connected_bus != null and is_instance_valid(_connected_bus) and _connected_bus.is_connected(&"map_left", _on_map_left):
		_connected_bus.disconnect(&"map_left", _on_map_left)
	_connected_bus = null


## The old map's boxes go at once (its state is parked by MapSession right after this signal).
func _on_map_left(_map_id: String) -> void:
	release()


func _register_debug_commands() -> void:
	var dbg := WorldUiServices.autoload("Debug")
	if dbg != null and dbg.has_method("register_command"):
		dbg.call("register_command", "boxes", "boxes: the Wooden Boxes of the current map (placement, hits, respawn)", _cmd_boxes)


func _cmd_boxes(_args: Variant = null) -> String:
	if state == null:
		return "no live map"
	var lines: PackedStringArray = ["%s: %d boxes, %d hits to break (%d hits landed, %d broken this session)" % [
		state.map_id, state.breakable_count(), hits_to_break(), hits_landed, boxes_broken]]
	var places: Array = plans.get(state.map_id, [])
	for b: BreakablePlacement in places:
		var p := b.position()
		var what := "intact, %d hits" % state.breakable_hits(b.index) if state.is_breakable_intact(b.index) \
			else "broken, back in %.0f s" % maxf(state.breakable_respawn_at(b.index) - _now(), 0.0)
		lines.append("  %s %s (%s) at (%.1f, %.1f, %.1f): %s" % [b.key(), b.placement, b.region, p.x, p.y, p.z, what])
	return "\n".join(lines)


# --- collaborators ------------------------------------------------------------------------------------------------

func current_state() -> MapInstanceState:
	if state_provider.is_valid():
		var v: Variant = state_provider.call()
		return v if v is MapInstanceState else null
	var s := _session()
	var v2: Variant = s.get("instance_state") if s != null else null
	return v2 if v2 is MapInstanceState else null


func _def_of(map_id: String) -> MapDefinition:
	if def_provider.is_valid():
		var v: Variant = def_provider.call(map_id)
		return v if v is MapDefinition else null
	var s := _session()
	if s == null or not s.has_method("get_defs"):
		return null
	var defs: Variant = s.call("get_defs")
	return (defs as MapDefinitions).get_def(map_id) if defs is MapDefinitions else null


func _tuning() -> WorldTuning:
	var w: Variant = ctx.world if ctx != null else null
	if w is Object and w.get("tuning") is WorldTuning:
		return w.get("tuning")
	var s := _session()
	if s != null and s.has_method("get_defs"):
		var defs: Variant = s.call("get_defs")
		if defs is MapDefinitions:
			return (defs as MapDefinitions).tuning
	return WorldTuning.from_db(_db())


func _ground() -> GroundQuery:
	if ground != null:
		return ground
	var w: Variant = ctx.world if ctx != null else null
	if w is Object and w.get("ground_query") is GroundQuery:
		return w.get("ground_query")
	return null


func _db() -> ContentDB:
	if db == null:
		db = WorldUiServices.content()
	return db


func _bus() -> Object:
	return bus if bus != null else WorldUiServices.events()


func _session() -> Node:
	return session if session != null else WorldUiServices.session()


func _character() -> CharacterState:
	if character_provider.is_valid():
		var v: Variant = character_provider.call()
		return v if v is CharacterState else null
	return WorldUiServices.character()


func _now() -> float:
	if clock_provider.is_valid():
		return float(clock_provider.call())
	return WorldUiServices.clock()


func _rng() -> RandomNumberGenerator:
	if rng != null:
		return rng
	var game := WorldUiServices.autoload("Game")
	if game != null and game.get("rng") is RandomNumberGenerator:
		return game.get("rng")
	rng = RandomNumberGenerator.new()
	return rng
