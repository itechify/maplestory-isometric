class_name MonsterTestRig
extends RefCounted
## A synchronous combat lab for tests (and tools): a PlayerTestWorld (primitive collision + a PlayerController driven
## by a BotInput) plus a MonsterSystem wired to private collaborators: a private Events bus, a private GameState (not
## in the tree) holding a fresh canonical Beginner, and a seeded RNG. Nothing touches the autoloads.
##
##   var rig := MonsterTestRig.create(db())
##   rig.floor(40.0)                                   # walkable floor, top at y = 0
##   var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
##   var m := rig.spawn("2", Vector3(1.2, 0, 0))
##   rig.run(60)                                       # player, combat, monsters: one tick each, 60 times
##   rig.free_all()

const TICK := 1.0 / 60.0

var w: PlayerTestWorld = null
var system: MonsterSystem = null
var bus: Node = null
var game: GameState = null
## Stands in for MapSession (no autoload): a plain Node, or one with a state_name() script (see set_session_state).
var session: Node = null
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var db: ContentDB = null
## Every signal emitted on the private bus, in order: [name, args...].
var events: Array = []


static func create(content: ContentDB, seed_value: int = 1234) -> MonsterTestRig:
	var r := MonsterTestRig.new()
	r.db = content
	r.rng.seed = seed_value
	r.w = PlayerTestWorld.create(content)
	r.bus = load("res://scripts/autoload/events.gd").new()
	for s: Dictionary in r.bus.get_script().get_script_signal_list():
		var sname := String(s["name"])
		var argc := (s["args"] as Array).size()
		r.bus.connect(sname, r._record.bind(sname) if argc == 0 else _recorder(r, sname, argc))
	r.game = GameState.new()
	r.game.db = content
	r.game.event_bus = r.bus
	r.game.log_warnings = false
	var made := CharacterFactory.create(CharacterFactory.default_params(content), content)
	r.game.character = made.character
	r.game.rng = r.rng
	r.system = MonsterSystem.new()
	r.system.name = "MonsterSystem"
	r.system.db = content
	r.system.game = r.game
	r.system.events = r.bus
	r.system.rng = r.rng
	r.system.tuning = WorldTuning.from_db(content)
	r.session = Node.new()
	r.system.session = r.session
	r.w.host.add_child(r.system)
	return r


static func _recorder(r: MonsterTestRig, sname: String, argc: int) -> Callable:
	match argc:
		1:
			return func(a: Variant) -> void: r.events.append([sname, a])
		2:
			return func(a: Variant, b: Variant) -> void: r.events.append([sname, a, b])
		_:
			return func(a: Variant, b: Variant, c: Variant) -> void: r.events.append([sname, a, b, c])


func _record(sname: String) -> void:
	events.append([sname])


## A walkable floor `size` m square with its top at `y`.
func floor(size: float, y: float = 0.0, center: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var b := w.add_box(Vector3(center.x, y - 0.5, center.z), Vector3(size, 1.0, size))
	b.collision_layer = WorldLayers.WALKABLE
	return b


## A blocking wall box (center, size).
func wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var b := w.add_box(center, size)
	b.collision_layer = WorldLayers.BLOCKING
	return b


## The player (PlayerController + BotInput) with this rig's character and a PlayerCombat attached.
func spawn_player(feet: Vector3, facing: Vector3 = Vector3.RIGHT) -> PlayerController:
	var p := w.spawn_player(feet, facing)
	# The test player has no Hurtbox node; MonsterSystem falls back to the movement model's body.
	system.attach_player(p)
	system.player_combat.autostep = false
	system.player_combat.db = db
	system.player_combat.game = game
	return p


## A monster outside any slot, standing on the ground under `feet`, facing `facing`.
func spawn(mob_id: String, feet: Vector3, facing: Vector3 = Vector3.LEFT, region: MobRegion = null) -> Monster:
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	var xf := Transform3D(Basis(Vector3.UP.cross(f).normalized(), Vector3.UP, f), feet)
	var m := system.spawn_monster(mob_id, xf)
	m.autostep = false
	if region != null:
		m.region = region
	return m


## One tick of everything, in the game's physics order: player (0), combat (10), monsters (20).
func tick() -> void:
	if w.player != null and is_instance_valid(w.player):
		w.player.step(TICK)
		if system.player_combat != null:
			system.player_combat.step(TICK)
	for c in system.get_children():
		if c is Monster:
			(c as Monster).step(TICK)
	if system.view != null:
		for c in system.view.get_children():
			if c is Monster:
				(c as Monster).step(TICK)


func run(ticks: int, before_tick: Callable = Callable()) -> void:
	for i in ticks:
		if before_tick.is_valid():
			before_tick.call(i)
		tick()


## Events named `sname` recorded so far.
func events_named(sname: String) -> Array:
	var out: Array = []
	for e in events:
		if String(e[0]) == sname:
			out.append(e)
	return out


func character() -> CharacterState:
	return game.character


## Equips `item_id` as the weapon ("" = bare hands).
func set_weapon(item_id: String) -> void:
	game.character.equipment = Equipment.new()
	if item_id != "":
		game.character.equipment.force_equip("weapon", item_id, db)


## Makes the stand-in session report `state` from state_name() ("IDLE", "WARP_OUT", ...).
func set_session_state(state: String) -> void:
	var lines := PackedStringArray(["extends Node", "func state_name() -> String:", "\treturn \"%s\"" % state, ""])
	var gd := GDScript.new()
	gd.source_code = "\n".join(lines)
	gd.reload()
	session.set_script(gd)


func free_all() -> void:
	if session != null:
		session.free()
		session = null
	if game != null:
		game.free()
		game = null
	if bus != null:
		bus.free()
		bus = null
	w.free_all()
	system = null
