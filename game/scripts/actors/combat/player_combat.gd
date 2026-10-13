class_name PlayerCombat
extends Node
## The player's basic attack in the world (a child "PlayerCombat" of the PlayerController, added by MonsterSystem).
##
## Each attack, on the "attack" action read from player.input_source (so the bot can press it):
##   1. stats   PlayerCombatStats.from_character(character) with the equipped weapon's WeaponProfile (bare hands
##              when none, combat.json bare_hands)
##   2. action  CombatFormula.choose_ordinary_action(weapon, rng): swing or stab by the weapon's canonical odds, then
##              one of that action's presentations (hit boxes) with equal odds
##   3. timing  weapon.attack_duration_ms(action): the canonical attack-speed ladder. The next attack cannot start
##              before it ends (lockout). Holding attack repeats at exactly that rate; a press up to
##              input_buffer_s before the end is kept and fires on the first free tick.
##   4. reach   CombatReach.attack_box_px(weapon, presentation, facing +x, level) placed in front of player.facing,
##              px -> m by WorldScale.actor, depth combat.json isometric_reach (MeleeQuery)
##   5. target  the nearest monster whose canonical touch box overlaps it (CombatReach.pick_targets capped at
##              basic_attack_targets, combat.json player_attack: 1, as a classic basic attack; attack_styles.json orders)
##   6. hit     CombatFormula.resolve_physical_hit(stats, monster stats, action, rng), applied by MonsterSystem
##              (HP, stagger, numbers, events, EXP and loot on a kill)
## On the ground the attack plants the player for the lockout (AttackLockInput); in the air it does not. The swing
## arc / thrust / punch FX and a small model lunge are presentation only (the body never moves).
##
## Input. Keys (J, Ctrl) and pads are read from player.input_source as always. The left mouse button is also an
## attack binding, but a click that belongs to the UI must never swing: the mouse counts only through presses that
## reach _unhandled_input (no GUI control consumed them) outside a GUI drag (MouseAttackGate). The gate sees every
## mouse event through an internal MouseAttackGate.Observer child that keeps processing while the tree is paused (the
## pause menu's Resume click). Only the keyboard player (the innermost source is a KeyboardInput) takes mouse input;
## bots and the console's parked source do not. A press fires at once when the lockout allows it; input_buffer_s
## only decides how long a press made during the lockout is kept.
##
## The feel values MeowDB does not publish come from data/misostory/combat.json section "player_attack"
## (root_on_ground, input_buffer_s, basic_attack_targets, lunge_m, lunge_s; each with its reason). A missing or
## malformed value is an error (`errors`, push_error) and that feature stays off (no root, no buffer, one target, no
## lunge): there is no fallback tuning number in code.
##
## Skills. On entering the tree this node gives the player its PlayerSkills and EffectTicker siblings (the Beginner
## skills and the timed-effect clock; see those classes). A skill cast shares this node's lockout through
## begin_lockout(), so one timer decides "busy": a basic attack cannot start during a cast or a cast during an attack,
## and is_attacking() is true while either is in progress (contract C4: activity "attacking").

signal attack_started(action: String, presentation: String, lockout_s: float)
## After the hit test, once per target hit: `target` is the monster and `result` its DamageResult. A whiff emits it
## once with both null.
signal attack_resolved(target: Node, result: DamageResult)

## The combat.json section this node reads.
const FEEL_SECTION := "player_attack"
## Share of the lunge time spent going forward (the rest eases back): the shape of the tween, not a duration.
const LUNGE_OUT_SHARE := 0.35

## The PlayerController (duck-typed: input_source, facing, global_position, is_grounded(), is_dead(),
## is_input_enabled(), is_climbing(), in_hitstun).
var player: Node3D = null
## MonsterSystem (live monsters, hit application, FX); null = no targets, FX only when `fx` is set.
var system: Node = null
## Injection seams (tests): null = Data.db / the Game autoload / Game.rng.
var db: ContentDB = null
var game: Node = null
var rng: RandomNumberGenerator = null
var character: CharacterState = null
## Optional FX node (AttackFx) when there is no system.
var fx: AttackFx = null
## Run step() from _physics_process (tests turn it off and call step() themselves). The PlayerSkills and EffectTicker
## siblings follow this flag too.
var autostep: bool = true
## The player's skills, its timed-effect clock and the pack's effect meshes on it (siblings under the player, made by
## ensure_skill_nodes()).
var skills: PlayerSkills = null
var effects: EffectTicker = null
var skill_fx: PlayerFx = null

# --- feel (combat.json player_attack; loaded in _ready, or by load_feel()) ----------------------------------------
## A ground attack plants the player for its lockout.
var root_on_ground: bool = false
## A press up to this long before the lockout ends is kept and fires on the first free tick.
var input_buffer_s: float = 0.0
## Monsters one basic attack hits (nearest first, each with its own roll).
var basic_attack_targets: int = 1
## The model's lunge (presentation): distance (m) and duration (s); 0 = none.
var lunge_m: float = 0.0
var lunge_s: float = 0.0
## Problems found loading the feel values (empty when combat.json player_attack is complete).
var errors: PackedStringArray = []

## Seconds until the next attack may start.
var lockout_left: float = 0.0
## Attacks started (tests, the sandbox report).
var attacks: int = 0
var last_action: String = ""
var last_presentation: String = ""
var last_box_px: Rect2 = Rect2()
var last_lockout_s: float = 0.0
var last_target: Node = null
var last_result: DamageResult = null

var _lock: AttackLockInput = null
var _buffered: float = 0.0
var _lunge: Tween = null
## The mouse's share of the attack action (see the class doc).
var _mouse := MouseAttackGate.new()
## Feeds _mouse every input event, paused or not (MouseAttackGate.Observer, an internal child).
var _mouse_observer: Node = null


func _ready() -> void:
	# After the player body (0): its input source has begun this tick and its position/facing are final.
	process_physics_priority = 10
	if player == null:
		player = get_parent() as Node3D
	load_feel()
	# Every mouse press and release reaches the gate before the GUI does, even while the tree is paused (an internal
	# child that always processes: a click on the pause menu's Resume lands while this node is paused).
	if _mouse_observer == null:
		_mouse_observer = MouseAttackGate.Observer.new(_mouse)
		add_child(_mouse_observer, false, Node.INTERNAL_MODE_FRONT)
	# A player still setting up its children (a scene being instanced) cannot take siblings yet.
	if player != null and player.is_node_ready():
		ensure_skill_nodes()
	elif player != null:
		ensure_skill_nodes.call_deferred()


## Gives the player its "PlayerSkills", "EffectTicker" and "PlayerFx" children (reused when present) wired to this node.
func ensure_skill_nodes() -> void:
	if player == null or not is_instance_valid(player):
		return
	skills = player.get_node_or_null(^"PlayerSkills") as PlayerSkills
	if skills == null:
		skills = PlayerSkills.new()
		skills.name = "PlayerSkills"
		skills.combat = self
		skills.player = player
		player.add_child(skills)
	skills.combat = self
	skills.player = player
	effects = player.get_node_or_null(^"EffectTicker") as EffectTicker
	if effects == null:
		effects = EffectTicker.new()
		effects.name = "EffectTicker"
		effects.combat = self
		player.add_child(effects)
	effects.combat = self
	skill_fx = player.get_node_or_null(^"PlayerFx") as PlayerFx
	if skill_fx == null:
		skill_fx = PlayerFx.new()
		skill_fx.name = "PlayerFx"
		skill_fx.combat = self
		skill_fx.player = player
		player.add_child(skill_fx)
	skill_fx.combat = self


func _physics_process(delta: float) -> void:
	if autostep:
		step(delta)


## Only presses no GUI control consumed arrive here: those are the world clicks that may attack.
func _unhandled_input(event: InputEvent) -> void:
	_mouse.world_press(event, _gui_dragging())


## One tick: lockout timer, buffered/held attack input, and the attack itself when allowed.
func step(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_ensure_lock()
	# The lockout may run up to one tick below zero: the next attack's lockout absorbs that overshoot, so a held attack
	# repeats at the canonical cadence on average (720 ms = 43.2 ticks alternates 43 and 44) instead of rounding every
	# cycle up to whole ticks (733 ms). Bounded to one tick so an idle pause never banks a burst.
	lockout_left = maxf(-delta, lockout_left - delta)
	if lockout_left <= 0.0:
		_lock.locked = false
	var src: InputSource = player.get("input_source")
	var pressed := src != null and src.just_pressed(&"attack")
	var held := src != null and src.is_held(&"attack")
	if _keyboard_player():
		var reading := _mouse.filter(pressed, held, _gui_dragging())
		pressed = reading[0]
		held = reading[1]
	else:
		_mouse.clear()
	# A press is only buffered while the player can act at all (alive, input on): a press under the death notice or a
	# modal must not fire later, after the respawn or when the window closes.
	if pressed and _input_live():
		_buffered = input_buffer_s
	else:
		_buffered = 0.0 if not _input_live() else maxf(0.0, _buffered - delta)
	if lockout_left > 0.0:
		return
	# `pressed` fires on its own: with input_buffer_s 0 (also what a missing value leaves) nothing is kept during the
	# lockout, but a tap whose key is already up again at the tick (a sub-tick J tap or world click) still attacks.
	if (pressed or _buffered > 0.0 or held) and can_attack():
		_buffered = 0.0
		attack()


## True while the player is alive with input enabled (no death notice, modal window or warp holds the keyboard).
func _input_live() -> bool:
	if player == null:
		return false
	if player.has_method("is_dead") and bool(player.call("is_dead")):
		return false
	if player.has_method("is_input_enabled") and not bool(player.call("is_input_enabled")):
		return false
	return true


## True when the player may start an attack now: alive, input enabled (no modal window or warp), not on a ladder,
## not in knockback hit-stun, and not locked out by the previous attack.
func can_attack() -> bool:
	if player == null or lockout_left > 0.0:
		return false
	if player.has_method("is_dead") and bool(player.call("is_dead")):
		return false
	if player.has_method("is_input_enabled") and not bool(player.call("is_input_enabled")):
		return false
	if player.has_method("is_climbing") and bool(player.call("is_climbing")):
		return false
	if "in_hitstun" in player and bool(player.get("in_hitstun")):
		return false
	return _character() != null and _db() != null


## Performs one basic attack now (no input checks; step() calls it when allowed). Returns the monster hit or null.
func attack() -> Node:
	# A seated player stands up before the swing (C5: PlayerController.stand_up with the reason "attack", as a cast does
	# with "skill"), so on the swing's first tick the player is attacking, not seated.
	if player.has_method("is_seated") and bool(player.call("is_seated")):
		player.call("stand_up", &"attack")
	var d := _db()
	var c := _character()
	var stats := PlayerCombatStats.from_character(c, d)
	var weapon := stats.weapon if stats.weapon != null else WeaponProfile.bare_hands(d)
	var r := _rng()
	var pick := CombatFormula.choose_ordinary_action(weapon, r)
	last_action = String(pick["action"])
	last_presentation = String(pick["presentation"])
	last_lockout_s = weapon.attack_duration_ms(last_action, d) / 1000.0
	# Absorb the previous lockout's sub-tick overshoot (at most one tick, see step()).
	lockout_left = last_lockout_s + minf(0.0, lockout_left)
	attacks += 1
	if root_on_ground and player.has_method("is_grounded") and bool(player.call("is_grounded")):
		_ensure_lock()
		_lock.locked = true
	last_box_px = CombatReach.attack_box_px(weapon, last_presentation, true, stats.level)
	var feet := player.global_position
	var facing: Vector3 = player.get("facing") if "facing" in player else Vector3.BACK
	attack_started.emit(last_action, last_presentation, last_lockout_s)
	_play_fx(weapon, feet, facing)
	_play_lunge()
	last_target = null
	last_result = null
	var candidates: Array = system.call("attack_candidates") if system != null and system.has_method("attack_candidates") else []
	var hits := MeleeQuery.pick(feet, facing, last_box_px, CombatReach.attack_box_depth_px(d), candidates, basic_attack_targets)
	# Every target resolves its own hit, nearest first (one target with the default count); the nearest is returned.
	for h: Dictionary in hits:
		var target: Node = h["node"]
		var target_stats: MonsterCombatStats = target.get("def").stats if target.get("def") != null else null
		if target_stats == null:
			continue
		var res := CombatFormula.resolve_physical_hit(stats, target_stats, last_action, r, d, {"presentation": last_presentation})
		if last_target == null:
			last_target = target
			last_result = res
		if system != null and system.has_method("apply_player_hit"):
			system.call("apply_player_hit", target, res, player)
		elif target.has_method("receive_hit"):
			target.call("receive_hit", res, player)
		attack_resolved.emit(target, res)
	if last_target == null:
		attack_resolved.emit(null, null)
	return last_target


## True while a basic attack or a skill cast is in progress (its lockout has not run out).
func is_attacking() -> bool:
	return lockout_left > 0.0


## Starts a lockout of `seconds` for a skill cast (PlayerSkills): no attack or other cast until it ends. With `plant`,
## a cast started on the ground plants the player like a ground attack (combat.json player_attack root_on_ground).
## Absorbs the previous lockout's sub-tick overshoot, as attack() does.
func begin_lockout(seconds: float, plant: bool) -> void:
	if seconds <= 0.0:
		return
	lockout_left = seconds + minf(0.0, lockout_left)
	_buffered = 0.0
	if plant and root_on_ground and player != null and player.has_method("is_grounded") and bool(player.call("is_grounded")):
		_ensure_lock()
		_lock.locked = true


## The collaborators this node resolved (db, Game, character, RNG, event bus), for its PlayerSkills / EffectTicker.
func content_db() -> ContentDB:
	return _db()


func game_node() -> Node:
	return _game()


func live_character() -> CharacterState:
	return _character()


func roll_rng() -> RandomNumberGenerator:
	return _rng()


## The event bus: the system's (MonsterSystem.events) when it has one, else the Events autoload.
func event_bus() -> Object:
	if system != null and system.get("events") is Object:
		return system.get("events")
	return get_node_or_null(^"/root/Events") if is_inside_tree() else null


## Leaving the player (system torn down, scene swap): never leave it planted. The lock is released and the wrapped
## source handed back.
func _exit_tree() -> void:
	_mouse.clear()
	if player == null or not is_instance_valid(player):
		return
	var src: Variant = player.get("input_source")
	if src is AttackLockInput and src == _lock:
		_lock.locked = false
		if player.has_method("set_input_source"):
			player.call("set_input_source", _lock.inner)
		else:
			player.set("input_source", _lock.inner)


## True when the player is driven by the keyboard: the innermost input source (under any AttackLockInput) is a
## KeyboardInput. Only then do mouse clicks attack; a bot, or the console's parked idle source, ignores the mouse.
func _keyboard_player() -> bool:
	var src: Variant = player.get("input_source")
	var guard := 0
	while src is AttackLockInput and guard < 8:
		src = (src as AttackLockInput).inner
		guard += 1
	return src is KeyboardInput


## A GUI drag-and-drop is running (an item dragged from the inventory to a quickslot): no mouse attack.
func _gui_dragging() -> bool:
	var vp := get_viewport() if is_inside_tree() else null
	return vp != null and vp.gui_is_dragging()


func _play_fx(weapon: WeaponProfile, feet: Vector3, facing: Vector3) -> void:
	var node: AttackFx = fx
	if node == null and system != null and system.get("attack_fx") is AttackFx:
		node = system.get("attack_fx")
	if node == null or not node.is_inside_tree():
		return
	var kind := String((weapon.presentations.get(last_presentation, {}) as Dictionary).get("kind", last_action))
	if weapon.is_bare_hands:
		node.punch(feet, facing, last_box_px)
	elif kind == "swing":
		node.swing(feet, facing, last_box_px)
	else:
		node.stab(feet, facing, last_box_px)


## Presentation: the player's model (PlayerVisual's "Model" child, which PlayerVisual never repositions) lunges
## forward along its own +Z and back.
func _play_lunge() -> void:
	var vis := player.get_node_or_null(^"Visual")
	var model: Node3D = vis.get("model") if vis != null and vis.get("model") is Node3D else null
	if model == null or not model.is_inside_tree() or lunge_m <= 0.0 or lunge_s <= 0.0:
		return
	if _lunge != null and _lunge.is_valid():
		_lunge.kill()
	model.position = Vector3.ZERO
	_lunge = create_tween()
	_lunge.tween_property(model, "position", Vector3(0, 0, lunge_m), lunge_s * LUNGE_OUT_SHARE).set_ease(Tween.EASE_OUT)
	_lunge.tween_property(model, "position", Vector3.ZERO, lunge_s * (1.0 - LUNGE_OUT_SHARE)).set_ease(Tween.EASE_IN_OUT)


## Installs (or re-installs, if another system swapped the player's source) the ground-attack input lock.
## A re-wrap always builds a NEW decorator: the old one may still be held by whoever swapped the source (the common
## "before := player.input_source; set_input_source(bot); ...; set_input_source(before)" pattern), and mutating its
## `inner` would hand that caller back the bot instead of the keyboard. The lock state carries over.
func _ensure_lock() -> void:
	var src: InputSource = player.get("input_source")
	if src is AttackLockInput:
		_lock = src
		return
	var was_locked := _lock != null and _lock.locked
	_lock = AttackLockInput.new(src)
	_lock.locked = was_locked and lockout_left > 0.0
	if player.has_method("set_input_source"):
		player.call("set_input_source", _lock)
	else:
		player.set("input_source", _lock)


## Reads the feel values from `db` (default: this node's ContentDB) combat.json player_attack. Every missing or
## malformed value is reported in `errors` (and push_error) and leaves its feature off. Returns `errors`.
func load_feel(content: ContentDB = null) -> PackedStringArray:
	errors = PackedStringArray()
	root_on_ground = false
	input_buffer_s = 0.0
	basic_attack_targets = 1
	lunge_m = 0.0
	lunge_s = 0.0
	var d := content if content != null else _db()
	if d == null:
		return errors  # no content yet (a bare node in a test); the next load_feel() call reads it
	var table: Variant = d.miso_table("combat")
	var section: Dictionary = {}
	if table is Dictionary and (table as Dictionary).get(FEEL_SECTION) is Dictionary:
		section = table[FEEL_SECTION]
	else:
		_feel_error("the section is missing")
		return errors
	var root: Variant = section.get("root_on_ground", null)
	if root is bool:
		root_on_ground = root
	else:
		_feel_error("root_on_ground must be true or false")
	input_buffer_s = _feel_num(section, "input_buffer_s", 0.0)
	var targets := _feel_num(section, "basic_attack_targets", 1.0)
	if targets < 1.0 or targets != floorf(targets):
		_feel_error("basic_attack_targets must be a whole number >= 1")
	else:
		basic_attack_targets = int(targets)
	lunge_m = _feel_num(section, "lunge_m", 0.0)
	lunge_s = _feel_num(section, "lunge_s", 0.0)
	return errors


func _feel_num(section: Dictionary, key: String, off: float) -> float:
	var v: Variant = section.get(key, null)
	if (v is int or v is float) and float(v) >= 0.0:
		return float(v)
	_feel_error("%s must be a number >= 0" % key)
	return off


func _feel_error(msg: String) -> void:
	var line := "misostory/combat.json %s: %s" % [FEEL_SECTION, msg]
	errors.append(line)
	push_error("[PlayerCombat] " + line)


func _db() -> ContentDB:
	if db != null:
		return db
	if system != null and system.get("db") is ContentDB:
		return system.get("db")
	var data := get_node_or_null(^"/root/Data") if is_inside_tree() else null
	return data.get("db") as ContentDB if data != null else null


func _game() -> Node:
	if game != null:
		return game
	if system != null and system.has_method("game_node"):
		return system.call("game_node")
	return get_node_or_null(^"/root/Game") if is_inside_tree() else null


func _character() -> CharacterState:
	if character != null:
		return character
	var g := _game()
	return g.get("character") as CharacterState if g != null else null


func _rng() -> RandomNumberGenerator:
	if rng != null:
		return rng
	var g := _game()
	if g != null and g.get("rng") is RandomNumberGenerator:
		return g.get("rng")
	rng = RandomNumberGenerator.new()
	return rng
