extends Node3D
## Monster and combat sandbox: the real island (scenes/world/world.tscn) with the player, the gameplay camera,
## MapSession and the MonsterSystem (scenes/systems/monster_system.tscn wired through a GameContext, exactly as the
## shell does), warped to a hunting map with live spawns. A scripted bot can fight; screenshots can be saved at the
## moments that matter (first hit, a critical, a kill, a touch).
##
##   bash scripts/godot.sh --path <ISOLATE copy> --resolution 1600x900 --disable-vsync \
##       res://scenes/sandbox/monster_sandbox.tscn -- [options]
##
## Options (after --):
##   --map <id>          MeowDB map id (default 000000040, Snail Hunting Ground I)
##   --weapon <id|none>  starting weapon: a creation weapon id (default 541 Sword) or none (bare hands)
##   --bot               a scripted bot walks to the nearest monster and attacks it (holding the attack key)
##   --standoff <m>     how close the bot stands to its target (default: just outside the touch zone)
##   --heal              sandbox cheat: refill HP when it drops under 40% (so a long bot run keeps fighting)
##   --shots <dir>       save screenshots (arrival, first hit, first critical, first kill, first touch, end)
##   --seconds <s>       quit after this many seconds of fighting (with --quit; default 30)
##   --quit              quit at the end and print a SANDBOX_SUMMARY line
##   --showcase <dir>    instead of fighting: each species in turn, spawned next to the player at the gameplay camera,
##                       shot idle, walking, attacking (its touch), flashing on a hit with its HP bar, and dying; then
##                       one monster behind a wall with its see-through silhouette. Quits when done. Use a map without
##                       spawns (e.g. --map 001010000) so the shots are not crowded.
## Keyboard play otherwise: WASD move, Space jump, J / Ctrl attack, F3 toggles the label, K kills every monster.

const DEFAULT_MAP := "000000040"
const DEFAULT_WEAPON := "541"

var world: Node = null
var player: PlayerController = null
var rig: CameraRig = null
var monsters: MonsterSystem = null
var ctx: GameContext = null
var bot: BotInput = null
var session: Node = null

var _args: PackedStringArray = PackedStringArray()
var _label: Label = null
var _shots_dir: String = ""
var _shot_flags: Dictionary = {}
var _shots_taken: int = 0
var _fighting: bool = false
var _fight_t: float = 0.0
var _stats: Dictionary = {"attacks": 0, "hits": 0, "misses": 0, "crits": 0, "kills": 0, "exp": 0, "touches": 0,
	"touch_damage": 0, "deaths": 0, "heals": 0}
var _pending_shot: Dictionary = {}


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	_shots_dir = _arg("--shots", "")
	if _shots_dir != "":
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	session = get_node_or_null(^"/root/MapSession")
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	if scene == null or session == null:
		push_error("[monster_sandbox] needs scenes/world/world.tscn and the MapSession autoload")
		get_tree().quit(2)
		return
	world = scene.instantiate()
	if DisplayServer.get_name() == "headless" and "load_visuals" in world:
		world.set("load_visuals", false)
	add_child(world)
	await world.world_ready
	_new_character()
	player = (load("res://scenes/actors/player.tscn") as PackedScene).instantiate() as PlayerController
	add_child(player)
	world.call("set_player", player)
	rig = (load("res://scenes/actors/camera_rig.tscn") as PackedScene).instantiate() as CameraRig
	add_child(rig)
	rig.set_target(player)
	rig.scan_occluders(world)
	session.call("attach_camera", rig)
	# The shell's wiring: a GameContext, the system scene under ctx.systems, setup(ctx).
	ctx = GameContext.new()
	ctx.main = self
	ctx.world = world
	ctx.player = player
	ctx.camera = rig
	ctx.ui_root = CanvasLayer.new()
	add_child(ctx.ui_root)
	ctx.systems = Node.new()
	ctx.systems.name = "Systems"
	add_child(ctx.systems)
	monsters = (load("res://scenes/systems/monster_system.tscn") as PackedScene).instantiate() as MonsterSystem
	ctx.systems.add_child(monsters)
	monsters.setup(ctx)
	_connect_stats()
	_setup_label()
	session.call("start_new_game")
	await _until_idle()
	var map := _arg("--map", DEFAULT_MAP)
	session.call("debug_warp", map)
	await _until_idle()
	await _wait(1.2)
	print("SANDBOX map %s: %d live monsters (%s)" % [map, monsters.live_monsters().size(), _species_summary()])
	_shot("arrival")
	if _arg("--showcase", "") != "":
		await _showcase(_arg("--showcase", ""))
		get_tree().quit(0)
		return
	if _has("--bot"):
		bot = BotInput.new()
		player.set_input_source(bot)
	_fighting = true


func _physics_process(delta: float) -> void:
	if not _fighting or player == null:
		return
	_fight_t += delta
	if _has("--heal"):
		var c: CharacterState = Game.character
		var mx := StatCalculator.max_hp(c, Data.db)
		if c.hp > 0 and c.hp < int(mx * 0.4):
			c.hp = mx
			_stats.heals += 1
			Events.hp_changed.emit(c.hp, mx)
	if player.is_dead():
		_on_dead_tick()
	elif bot != null:
		_drive_bot()
	if _has("--quit") and _fight_t >= float(_arg("--seconds", "30")) and _pending_shot.is_empty():
		_fighting = false
		await _shot_now("end")
		_summary()
		get_tree().quit(0)


func _process(_delta: float) -> void:
	if _label != null and _label.visible and player != null and monsters != null:
		var c: CharacterState = Game.character
		_label.text = "map %s  live %d  kills %d\nLv %d  EXP %d  HP %d/%d\nattacks %d  hits %d  misses %d  crits %d\ntouches %d (%d dmg)  deaths %d%s" % [
			session.get("current_map"), monsters.live_monsters().size(), _stats.kills, c.level, c.exp, c.hp,
			StatCalculator.max_hp(c, Data.db), _stats.attacks, _stats.hits, _stats.misses, _stats.crits, _stats.touches,
			_stats.touch_damage, _stats.deaths, "  (heal cheat x%d)" % _stats.heals if _stats.heals > 0 else ""]


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.physical_keycode:
		KEY_F3:
			if _label != null:
				_label.visible = not _label.visible
		KEY_K:
			monsters.kill_all()


# --- the bot ---------------------------------------------------------------------------------------------------------

## Walks to the nearest live monster, turns to face it, and holds attack while it is in reach.
func _drive_bot() -> void:
	var target: Monster = null
	var best := INF
	for m in monsters.live_monsters():
		var d := _flat(m.global_position - player.global_position).length()
		if d < best and absf(m.global_position.y - player.global_position.y) < 1.5:
			best = d
			target = m
	bot.release(&"attack")
	bot.world_dir = Vector3.ZERO
	if target == null:
		return
	var to := _flat(target.global_position - player.global_position)
	var reach := float(_arg("--standoff", str(1.1 + target.def.touch_size_m.x * 0.5)))
	if best > reach:
		bot.world_dir = to.normalized()
		return
	if player.facing.dot(to.normalized()) < 0.9:
		bot.world_dir = to.normalized() * 0.2  # a nudge turns the player; the attack plants it
	bot.hold(&"attack")


func _on_dead_tick() -> void:
	if bot != null:
		bot.release_all()
		bot.world_dir = Vector3.ZERO
	if bool(session.call("is_idle")) or String(session.call("state_name")) == "DEAD":
		if String(session.call("state_name")) == "DEAD" and not _shot_flags.has("respawning"):
			_shot_flags["respawning"] = true
			await _wait(1.5)
			session.call("respawn")
			await _until_idle()
			session.call("debug_warp", _arg("--map", DEFAULT_MAP))
			await _until_idle()
			_shot_flags.erase("respawning")


# --- stats and screenshots -------------------------------------------------------------------------------------------

func _connect_stats() -> void:
	monsters.player_combat.attack_started.connect(func(_a: String, _p: String, _s: float) -> void: _stats.attacks += 1)
	monsters.player_combat.attack_resolved.connect(_on_attack_resolved)
	monsters.monster_died.connect(func(m: Monster) -> void:
		_stats.kills += 1
		_stats.exp += m.def.exp_reward
		_queue_shot("first_kill", 0.3))
	monsters.player_touched.connect(func(_m: Monster, res: IncomingResult) -> void:
		_stats.touches += 1
		_stats.touch_damage += res.final
		if res.landed():
			_queue_shot("first_touch", 0.15))
	Events.player_died.connect(func(_map: String) -> void: _stats.deaths += 1)


func _on_attack_resolved(target: Node, res: DamageResult) -> void:
	if target == null or res == null:
		return
	if res.missed:
		_stats.misses += 1
		return
	_stats.hits += 1
	_queue_shot("first_hit", 0.12)
	if res.critical:
		_stats.crits += 1
		_queue_shot("first_crit", 0.12)


func _queue_shot(tag: String, delay: float) -> void:
	if _shots_dir == "" or _shot_flags.has(tag) or not _pending_shot.is_empty():
		return
	_shot_flags[tag] = true
	_pending_shot = {"tag": tag}
	await _wait(delay)
	await _shot_now(tag)
	_pending_shot = {}


func _shot(tag: String) -> void:
	if _shots_dir == "" or _shot_flags.has(tag):
		return
	_shot_flags[tag] = true
	await _shot_now(tag)


func _shot_now(tag: String) -> void:
	if _shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	_shots_taken += 1
	var path := _shots_dir.path_join("%02d_%s.png" % [_shots_taken, tag])
	img.save_png(path)
	print("SANDBOX shot %s" % path)


func _summary() -> void:
	var c: CharacterState = Game.character
	print("SANDBOX_SUMMARY map=%s weapon=%s seconds=%.0f attacks=%d hits=%d misses=%d crits=%d kills=%d exp=%d level=%d exp_now=%d hp=%d touches=%d touch_damage=%d deaths=%d heals=%d live=%d" % [
		session.get("current_map"), _arg("--weapon", DEFAULT_WEAPON), _fight_t, _stats.attacks, _stats.hits, _stats.misses,
		_stats.crits, _stats.kills, _stats.exp, c.level, c.exp, c.hp, _stats.touches, _stats.touch_damage, _stats.deaths,
		_stats.heals, monsters.live_monsters().size()])


# --- showcase --------------------------------------------------------------------------------------------------------

## Every species' states at gameplay scale (#64): idle, walk, attack, hit (flash and HP bar), death; then one monster
## hidden behind a wall showing its silhouette. The monsters are free spawns of the real MonsterSystem that do not run
## their AI (autostep off), so each state is shown on cue; the hit is a real one through apply_player_hit.
func _showcase(dir: String) -> void:
	_shots_dir = dir
	DirAccess.make_dir_recursive_absolute(dir)
	player.set_input_source(BotInput.new())
	var side := _flat(rig.camera.global_transform.basis.x).normalized()
	var toward_cam := _flat(rig.camera.global_transform.basis.z).normalized()
	var fade := monsters.tuning.num("spawns", "fade_in_s") if monsters.tuning != null else 0.0
	for id in ["1", "2", "3", "4", "5", "9"]:
		var at := player.global_position + side * 2.2
		var m := _showcase_spawn(id, at, -side)
		var tag := m.def.name.to_lower().replace(" ", "_").replace(".", "")
		await _wait(fade + 0.8)
		await _shot_now(tag + "_idle")
		# Walking: it walks back and forth on the spot's ground (its AI is off; the visual reads is_walking()).
		var t := 0.0
		var dir_ := side
		while t < 0.9:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			m.set("_walking", true)
			m.facing = dir_
			m.global_position += dir_ * m.def.move_speed_mps * get_physics_process_delta_time()
			m.settle()
		await _shot_now(tag + "_walk")
		m.set("_walking", false)
		m.visual.on_attack()
		await _wait(0.35)
		await _shot_now(tag + "_attack")
		await _wait(0.8)
		var res := DamageResult.new()
		res.final = 1
		monsters.apply_player_hit(m, res, player)
		await get_tree().process_frame
		await _shot_now(tag + "_hit")
		await _wait(0.8)
		m.die()
		await _wait(m.def.die_fade_s * MonsterVisual.DEATH_CLIP_SHARE * 0.6)
		await _shot_now(tag + "_death")
		await _wait(m.def.die_fade_s + 0.3)
	# One monster behind a wall between it and the camera: its silhouette shows through.
	var hidden_at := player.global_position + side * 2.4
	var hidden := _showcase_spawn("9", hidden_at, -side)
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.6, 2.4, 0.4)
	wall.mesh = box
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.55, 0.5, 0.45)
	wall.material_override = stone
	add_child(wall)
	wall.global_position = hidden_at + toward_cam * 1.4 + Vector3.UP * 1.0
	wall.look_at(wall.global_position - toward_cam, Vector3.UP)
	await _wait(fade + 1.0)
	await _shot_now("occluded_silhouette")
	hidden.queue_free()
	wall.queue_free()


func _showcase_spawn(id: String, at: Vector3, facing: Vector3) -> Monster:
	var f := facing.normalized()
	var xf := Transform3D(Basis(Vector3.UP.cross(f).normalized(), Vector3.UP, f), at)
	var m := monsters.spawn_monster(id, xf)
	m.autostep = false
	return m


# --- helpers ---------------------------------------------------------------------------------------------------------

func _new_character() -> void:
	# A sandbox never writes the shared user:// save slots.
	Game.autosave_enabled = false
	Game.autosave_on_quit = false
	var weapon := _arg("--weapon", DEFAULT_WEAPON)
	var params := CharacterFactory.default_params(Data.db)
	params["name"] = "Sandbox"
	params["save"] = false
	if weapon != "none":
		params["weapon_id"] = weapon
	Game.new_game(params)
	if weapon == "none":
		Game.character.equipment = Equipment.new()
		Events.equipment_changed.emit("weapon")


func _species_summary() -> String:
	var count := {}
	for m in monsters.live_monsters():
		count[m.def.name] = int(count.get(m.def.name, 0)) + 1
	var parts := PackedStringArray()
	for k in count:
		parts.append("%s x%d" % [k, count[k]])
	return ", ".join(parts)


func _setup_label() -> void:
	_label = Label.new()
	_label.position = Vector2(12, 10)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	ctx.ui_root.add_child(_label)


func _until_idle() -> void:
	var frames := 0
	while not bool(session.call("is_idle")) and frames < 1200:
		await get_tree().physics_frame
		frames += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _has(flag: String) -> bool:
	return flag in _args


func _arg(flag: String, fallback: String) -> String:
	var i := _args.find(flag)
	if i >= 0 and i + 1 < _args.size() and not _args[i + 1].begins_with("--"):
		return _args[i + 1]
	return fallback
