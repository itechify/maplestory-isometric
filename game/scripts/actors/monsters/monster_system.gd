class_name MonsterSystem
extends Node3D
## The live monsters and the player's combat in the real scene (scenes/systems/monster_system.tscn).
##
## setup(ctx) (GameContext; every field may be null, the system then runs with what it has):
##   - installs make_monster / release_monster as the world's MapInstanceView.monster_factory / monster_releaser, so
##     the current map spawns real Monster actors; a map that is already live is realized again at once
##   - adds a PlayerCombat child to ctx.player (the basic attack)
##   - owns the FX layer: DamageNumbers and AttackFx children of this node
## Then, every physics tick, each Monster walks (its own step) and asks monster_touch(self) for contact damage; the
## PlayerCombat asks attack_candidates() and apply_player_hit(). A kill is announced in on_monster_died:
##   Game.gain_exp(canonical EXP)  ->  Events.monster_killed(monster_id, map_id)  ->  DropRoller.roll(...) and
##   Events.loot_dropped(drops, position, map_id) (the loot system puts them on the ground)
## and the monster's `died` signal lets MapInstanceView record the kill in MapInstanceState (respawn on the
## canonical 7.56 s tick, spawn_rate.json).
## Every frame, update_see_through() gives the live monsters near the player their see-through silhouette
## (MonsterVisual), so terrain that never fades cannot hide them.
##
## Collaborators are injectable (tests); null means the autoload: db (Data.db), game (Game), events (Events),
## session (MapSession). See docs/runtime/MONSTERS_AND_COMBAT_RUNTIME.md.

signal monster_spawned(monster: Monster)
## A monster died (after EXP, monster_killed and loot_dropped were announced).
signal monster_died(monster: Monster)
## A monster touched the player and the touch was resolved (hit, miss, guard).
signal player_touched(monster: Monster, result: IncomingResult)

const MONSTER_SCENE := "res://scenes/actors/monster.tscn"

var ctx: GameContext = null
var world: Node = null
var view: MapInstanceView = null
var player: Node3D = null
var player_combat: PlayerCombat = null
var library: ProxyLibrary = null
## The art pack the monsters' rigged models come from. Null = no pack, the proxies. setup(ctx) with a GameContext takes
## ArtPack.shared() when nothing was injected (the ArtPack header has the convention).
var art: ArtPack = null
var ground: PhysicsGroundQuery = null
var tuning: WorldTuning = null
## Injection seams; null = the autoloads.
var db: ContentDB = null
var game: Node = null
var events: Node = null
var session: Node = null
## Character and RNG overrides (tests); null = Game.character / Game.rng.
var character: CharacterState = null
var rng: RandomNumberGenerator = null

var damage_numbers: DamageNumbers = null
var attack_fx: AttackFx = null

# --- counters (tests, the sandbox report, debug) --------------------------------------------------------------------
var kills: int = 0
var exp_awarded: int = 0
var touches: int = 0
var touch_damage: int = 0

var _spawn_counter: int = 0
var _regions: Dictionary = {}
## Monsters made by spawn_monster (not in a slot).
var _free: Array[Monster] = []
var _monster_scene: PackedScene = null
## True when this system loaded its own ProxyLibrary (no world): its template tree is freed with the system.
var _owns_library: bool = false


func _ready() -> void:
	_ensure_fx()


func _process(_delta: float) -> void:
	update_see_through()


## The shell's integration call (GameContext contract). Safe to call once the world is built or before.
func setup(p_ctx: GameContext) -> void:
	ctx = p_ctx
	if ctx != null and art == null:
		art = ArtPack.shared()
	_ensure_fx()
	if ctx != null and ctx.player != null:
		attach_player(ctx.player as Node3D)
	if ctx != null and ctx.world != null:
		attach_world(ctx.world)
	if ctx != null and ctx.camera != null:
		var cam: Node = ctx.camera if ctx.camera is Camera3D else ctx.camera.get_node_or_null(^"Camera3D")
		if cam is Camera3D:
			damage_numbers.camera = cam


## Hooks the IslandWorld (duck-typed: instance_view, library, tuning, ground_query, is_built, world_ready,
## body_fell). Installs the factory now, or when the world finishes building.
func attach_world(w: Node) -> void:
	world = w
	if w == null:
		return
	if w.has_signal("body_fell") and not w.is_connected("body_fell", _on_body_fell):
		w.connect("body_fell", _on_body_fell)
	if bool(w.get("is_built")):
		_install_factory()
	elif w.has_signal("world_ready"):
		w.connect("world_ready", _install_factory, CONNECT_ONE_SHOT)


## Gives the player its basic attack (a PlayerCombat child, reused if the scene already has one).
func attach_player(p: Node3D) -> void:
	player = p
	if p == null:
		return
	var pc := p.get_node_or_null(^"PlayerCombat") as PlayerCombat
	var fresh := pc == null
	if fresh:
		pc = PlayerCombat.new()
		pc.name = "PlayerCombat"
	# Wired before it enters the tree, so its _ready reads the feel values (combat.json player_attack) from this
	# system's ContentDB.
	pc.system = self
	pc.player = p
	if fresh:
		p.add_child(pc)
	else:
		pc.load_feel()
	player_combat = pc
	# Natural HP recovery (data/misostory/recovery.json, the owner's rule). It reads the player's activity after
	# PlayerCombat each tick through its own process_physics_priority (NaturalRecovery.PHYSICS_PRIORITY 20 > 10).
	if p.get_node_or_null(^"NaturalRecovery") == null:
		var nr := NaturalRecovery.new()
		nr.name = "NaturalRecovery"
		p.add_child(nr)


## The monster factory (MapInstanceView.monster_factory): a Monster for `mob_id` at `slot`, restored with the slot's
## survivor HP (MapInstanceState hp, -1 = full), with Monster.slot_index = slot.index. A slot index of -1 (the debug
## console's spawns: placement "debug", metadata debug_spawn = true) is no slot: full HP, slot_index NO_SLOT, and its
## death is never reported to the view (only MapInstanceView._spawn links a node's `died` to its slot), so it never
## frees or respawns a slot. It still dies like any monster: EXP, drops, monster_killed.
func make_monster(mob_id: String, slot: SpawnSlot) -> Node3D:
	var def := view.def if view != null else null
	var start_hp := -1
	if view != null and view.state != null and slot != null and slot.index >= 0 and slot.index < view.state.slots.size():
		start_hp = int(view.state.slots[slot.index].get("hp", -1))
	var map_id := def.map_id if def != null else _current_map()
	var m := _new_monster(mob_id, slot.transform if slot != null else Transform3D.IDENTITY, def, map_id, start_hp,
		slot.index if slot != null else -1)
	return m


## The monster releaser (MapInstanceView.monster_releaser): a survivor leaving with its map is freed now; a dying
## monster (released by its own kill) finishes its canonical death fade and frees itself.
func release_monster(node: Node3D) -> void:
	if node is Monster and (node as Monster).is_dying():
		return
	if is_instance_valid(node):
		node.queue_free()


## A monster outside any slot (sandbox, tests): full HP, child of this system, on `def`'s mob region if given.
func spawn_monster(mob_id: String, xform: Transform3D, def: MapDefinition = null) -> Monster:
	var m := _new_monster(mob_id, xform, def, def.map_id if def != null else _current_map(), -1, -1)
	add_child(m)
	m.global_transform = xform
	m.settle()
	_free.append(m)
	return m


## The player's feet, or null without a player (MapInstanceView.player_position: the respawn clearance).
func player_feet() -> Variant:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return null
	return player.global_position


## Every live (not dying) monster: the view's slot monsters, debug spawns under the view, and free spawns.
func live_monsters() -> Array[Monster]:
	var out: Array[Monster] = []
	if view != null:
		for c in view.get_children():
			if c is Monster and (c as Monster).is_alive():
				out.append(c)
	for m in _free:
		if is_instance_valid(m) and m.is_alive() and not out.has(m):
			out.append(m)
	return out


## Basic-attack candidates for MeleeQuery.pick: canonical touch boxes (px) at each monster's feet.
func attack_candidates() -> Array:
	var out: Array = []
	var d := _db()
	for m in live_monsters():
		out.append({"node": m, "feet": m.global_position, "touch_px": m.def.stats.touch_zone_px,
			"depth_px": CombatReach.touch_zone_depth_px(m.def.stats, d), "spawn_order": m.spawn_order})
	return out


## Applies a resolved player attack to `m`: the number (MISS, damage, critical), a hit spark, Events.monster_hit or
## monster_missed, then the monster's own reaction (HP, stagger, provocation, death).
func apply_player_hit(m: Monster, res: DamageResult, attacker: Node3D) -> void:
	if m == null or not m.is_alive() or res == null:
		return
	var id := m.def.id
	if res.missed:
		damage_numbers.miss(m.head_position(), m)
		_emit(&"monster_missed", [id])
	else:
		damage_numbers.dealt(m.head_position(), res.final, res.critical, m)
		attack_fx.spark(m.body_center(), maxf(0.25, m.def.touch_size_m.y * 0.35))
		_emit(&"monster_hit", [id, res.final, res.critical])
	m.receive_hit(res, attacker)


## Called by a Monster when it dies: the canonical EXP through Game.gain_exp, Events.monster_killed, and the
## monster's canonical drop record rolled at once (DropRoller, with the character's quests in progress for quest-gated
## drops, contract C2) and announced with
## Events.loot_dropped(drops, feet position, map_id) when anything dropped.
func on_monster_died(m: Monster) -> void:
	kills += 1
	var id := m.def.id
	var map_id := m.map_id if m.map_id != "" else _current_map()
	var amount := m.def.exp_reward
	var g := game_node()
	if amount > 0:
		if g != null and g.has_method("gain_exp"):
			g.call("gain_exp", amount, "monster:%s" % id)
		elif _character() != null:
			Progression.gain_exp(_character(), amount, _db())
		exp_awarded += amount
	_emit(&"monster_killed", [id, map_id])
	var drops := DropRoller.roll(id, _db(), _rng(), DropRoller.context_for(_character()))
	if not drops.is_empty():
		_emit(&"loot_dropped", [drops, m.global_position, map_id])
	_free.erase(m)
	monster_died.emit(m)


## Contact damage, asked by every Monster after it moves: when its touch zone overlaps the player's body and the
## player can be touched (alive, not invulnerable, not warping), the canonical touch attack is rolled and applied.
## Returns true when a touch was resolved.
func monster_touch(m: Monster) -> bool:
	if player == null or not is_instance_valid(player) or not m.touch_active():
		return false
	if not ContactDamage.can_be_touched(player, _session()):
		return false
	var body := _player_body()
	if not MeleeQuery.touch_overlaps(m.global_position, m.facing, m.def.touch_size_m, player.global_position, body.x, body.y):
		return false
	var c := _character()
	var d := _db()
	if c == null or d == null:
		return false
	var res := ContactDamage.resolve(m.def.stats, c, d, _rng())
	if res.no_attack:
		return false
	touches += 1
	var lost := ContactDamage.apply(res, m.def.id, m.global_position, player, c, d, _events())
	touch_damage += lost
	var above := player.global_position + Vector3.UP * (body.y + 0.25)
	if res.landed():
		damage_numbers.taken(above, res.final, player)
	elif res.guarded:
		damage_numbers.guard(above, player)
	else:
		damage_numbers.miss(above, player)
	player_touched.emit(m, res)
	if res.landed() and c.hp <= 0:
		ContactDamage.announce_death(player, _session(), _events(), m.map_id if m.map_id != "" else _current_map())
	return true


## The authored height band (Vector2(y_lo, y_hi)) of the spawn region slot `slot_index` of `def` was placed in
## (SpawnSlotPlanner sets SpawnSlot.region to the area's name), or (NAN, NAN) when it has none: a monster's floor
## covers its region's tier (MonsterDef.floor_range).
static func region_band(def: MapDefinition, slot_index: int) -> Vector2:
	if def == null or slot_index < 0 or slot_index >= def.monster_spawn_definitions.size():
		return Vector2(NAN, NAN)
	var name_ := def.monster_spawn_definitions[slot_index].region
	for a in def.spawn_areas:
		if String(a.get("name", "")) == name_:
			return Vector2(float(a.get("y_lo", NAN)), float(a.get("y_hi", NAN)))
	return Vector2(NAN, NAN)


## The mob region of `def` (cached per map).
func region_for(def: MapDefinition) -> MobRegion:
	if def == null:
		return null
	if not _regions.has(def.map_id):
		_regions[def.map_id] = MobRegion.from_def(def, _tuning())
	return _regions[def.map_id]


## Turns each live monster's see-through silhouette on or off by its distance to the player (feet to feet;
## MonsterVisual.see_through_wanted with the species' see_through_radius_m and see_through_hysteresis_m). Without a
## player none shows. Called every frame from _process; returns how many monsters want it (tests, the sandbox).
func update_see_through() -> int:
	var has_player := player != null and is_instance_valid(player) and player.is_inside_tree()
	var at := player.global_position if has_player else Vector3.ZERO
	var on := 0
	for m in live_monsters():
		if m.visual == null or m.def == null or not m.is_inside_tree():
			continue
		var want := has_player and MonsterVisual.see_through_wanted(true, m.global_position.distance_to(at),
			m.def.see_through_radius_m, m.def.see_through_hysteresis_m, m.visual.is_see_through())
		m.visual.set_see_through(want)
		if want:
			on += 1
	return on


## Kills every live monster through its own death path (EXP, events, drops). Returns how many.
func kill_all() -> int:
	var n := 0
	for m in live_monsters():
		m.die()
		n += 1
	return n


func game_node() -> Node:
	if game != null:
		return game
	return get_node_or_null(^"/root/Game") if is_inside_tree() else null


# =================================================================================================================
# Internals
# =================================================================================================================

func _install_factory() -> void:
	if world == null:
		return
	var v: Variant = world.get("instance_view")
	if not (v is MapInstanceView):
		push_warning("[MonsterSystem] the world has no MapInstanceView; monsters stay static")
		return
	if world.get("library") is ProxyLibrary:
		library = world.get("library")
	if world.get("tuning") is WorldTuning:
		tuning = world.get("tuning")
	if world.get("ground_query") is PhysicsGroundQuery:
		ground = world.get("ground_query")
	use_view(v)


## Makes `v` spawn real monsters: installs make_monster / release_monster. A map already live (the shell called
## setup after the first warp) is realized again at once, so its static proxies become monsters.
func use_view(v: MapInstanceView) -> void:
	view = v
	view.monster_factory = make_monster
	view.monster_releaser = release_monster
	# No monster is realized while the player stands on its slot (presentation.json spawns.respawn_player_clearance_m).
	view.player_position = player_feet
	if view.state != null and view.def != null:
		var st := view.state
		var d := view.def
		var at := player.global_position if player != null and is_instance_valid(player) else d.player_spawn(0).origin
		view.realize(st, d, at)


func _new_monster(mob_id: String, xform: Transform3D, def: MapDefinition, map_id: String, start_hp: int,
		slot_index: int) -> Monster:
	var d := MonsterDef.from_id(mob_id, _db())
	var m: Monster = null
	if _monster_scene == null and ResourceLoader.exists(MONSTER_SCENE):
		_monster_scene = load(MONSTER_SCENE)
	if _monster_scene != null:
		m = _monster_scene.instantiate() as Monster
	if m == null:
		m = Monster.new()
	_spawn_counter += 1
	m.spawn_order = _spawn_counter
	m.slot_index = slot_index if slot_index >= 0 else Monster.NO_SLOT
	m.map_id = map_id
	m.kill_y = def.kill_y if def != null and def.has_markers else -INF
	var t := _tuning()
	if t != null:
		m.settle_up_m = t.num("grounding", "probe_up_m")
		m.settle_down_m = t.num("grounding", "probe_down_m")
	var seed_value := hash("%s:%d:%d" % [map_id, slot_index, _spawn_counter])
	m.setup(d, self, xform, seed_value, region_for(def), _ground(), _library(), start_hp, art)
	var band := region_band(def, slot_index)
	if not is_nan(band.x):
		m.set_region_band(band.x, band.y)
	var fade := _tuning().num("spawns", "fade_in_s") if _tuning() != null else 0.0
	m.visual.start_spawn(fade)
	monster_spawned.emit(m)
	return m


func _on_body_fell(body: Node3D) -> void:
	if body is Monster:
		(body as Monster).recover()


func _ensure_fx() -> void:
	if damage_numbers == null:
		damage_numbers = get_node_or_null(^"DamageNumbers") as DamageNumbers
		if damage_numbers == null:
			damage_numbers = DamageNumbers.new()
			damage_numbers.name = "DamageNumbers"
			add_child(damage_numbers)
	if attack_fx == null:
		attack_fx = get_node_or_null(^"AttackFx") as AttackFx
		if attack_fx == null:
			attack_fx = AttackFx.new()
			attack_fx.name = "AttackFx"
			add_child(attack_fx)
	# The swing FX lay the real hit area on the ground: the attack box as deep as the hit test makes it.
	if _db() != null:
		attack_fx.depth_px = CombatReach.attack_box_depth_px(_db())


## The player's body for contact: (radius, height) of its Hurtbox capsule (player.tscn), else the movement model.
func _player_body() -> Vector2:
	var cs := player.get_node_or_null(^"Hurtbox/CollisionShape3D") as CollisionShape3D
	if cs != null and cs.shape is CapsuleShape3D:
		var cap := cs.shape as CapsuleShape3D
		return Vector2(cap.radius, cap.height)
	var model: Variant = player.get("model") if "model" in player else null
	if model is MovementModel:
		return Vector2((model as MovementModel).body_radius, (model as MovementModel).body_height)
	var mv: Variant = _db().miso_table("movement") if _db() != null else null
	if mv is Dictionary:
		return Vector2(float((mv as Dictionary).get("body_radius_m", 0.0)), float((mv as Dictionary).get("body_height_m", 0.0)))
	return Vector2.ZERO


func _ground() -> PhysicsGroundQuery:
	if ground == null and is_inside_tree():
		ground = PhysicsGroundQuery.new(get_world_3d().direct_space_state)
		var t := _tuning()
		if t != null:
			ground.coplanar_tolerance = t.num("grounding", "coplanar_tolerance_m")
	return ground


func _library() -> ProxyLibrary:
	if library == null:
		library = ProxyLibrary.load_from()
		_owns_library = true
	return library


func _tuning() -> WorldTuning:
	if tuning == null and _db() != null:
		tuning = WorldTuning.from_db(_db())
	return tuning


func _db() -> ContentDB:
	if db != null:
		return db
	var data := get_node_or_null(^"/root/Data") if is_inside_tree() else null
	if data != null and data.get("db") is ContentDB:
		db = data.get("db")
	return db


func _events() -> Node:
	if events != null:
		return events
	return get_node_or_null(^"/root/Events") if is_inside_tree() else null


func _session() -> Node:
	if session != null:
		return session
	return get_node_or_null(^"/root/MapSession") if is_inside_tree() else null


func _character() -> CharacterState:
	if character != null:
		return character
	var g := game_node()
	return g.get("character") as CharacterState if g != null else null


func _rng() -> RandomNumberGenerator:
	if rng != null:
		return rng
	var g := game_node()
	if g != null and g.get("rng") is RandomNumberGenerator:
		return g.get("rng")
	rng = RandomNumberGenerator.new()
	return rng


func _current_map() -> String:
	var s := _session()
	var v: Variant = s.get("current_map") if s != null else null
	return String(v) if v is String else ""


func _emit(sig: StringName, args: Array) -> void:
	var bus := _events()
	if bus != null and bus.has_signal(sig):
		bus.callv(&"emit_signal", [sig] + args)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _owns_library and library != null:
		library.free_templates()


func _exit_tree() -> void:
	# Hand the world back its default proxies if this system leaves before the world.
	if view != null and is_instance_valid(view):
		if view.monster_factory == Callable(self, &"make_monster"):
			view.monster_factory = Callable(view, &"default_factory")
		if view.monster_releaser == Callable(self, &"release_monster"):
			view.monster_releaser = Callable()
		if view.player_position == Callable(self, &"player_feet"):
			view.player_position = Callable()
