class_name PlayerSkills
extends Node
## The player's skills in the world: a child "PlayerSkills" of the PlayerController, made by its PlayerCombat
## (PlayerCombat.ensure_skill_nodes). cast(skill_id) is the one way a skill is used; the HUD quickslots call it for a
## bound skill key (MisoQuickslots.use), and tests and the bot call it directly.
##
## A cast, in order:
##   1. the player can act: alive, input enabled (no modal window, warp or death notice holds it), not in knockback
##      hit-stun, and no basic attack or other cast in progress (PlayerCombat's lockout). Refusals change nothing.
##   2. SkillBook.check_cast: learned, cast position (canonical cast_position: Three Snails "ground only", Recovery and
##      Nimble Feet "ground, air, or rope"; a ladder or rope counts as "rope", airborne as "air"), cooldown, MP and
##      the level's shell item.
##   3. a seated player stands up first (contract C5: a skill stands the player up).
##   4. the costs: MP through Game.change_mp, the shell through ItemService.lose (so Events.item_lost reaches quests).
##   5. the effect, from canonical data (SkillDef):
##        Three Snails  the stepped search band (SkillTargeting) in front of the facing picks the nearest live monster
##                      with a clear line from the player at the moment of the throw (SkillSight, the owner's rule in
##                      #6: terrain and buildings block, monsters, boxes and props do not), as many as the skill's
##                      canonical target count (one). Wooden Boxes are never a target (breakables.json hit_rule, the
##                      owner's ruling in #5: only basic attacks break boxes), so a cast with only a box in its band
##                      is a whiff; a whiff's shell flies until a wall or its range ends (shell_end). A monster takes
##                      CombatFormula.resolve_fixed_damage(level's fixed damage, "0001000") through
##                      MonsterSystem.apply_player_hit, the same path as a basic attack (numbers, EXP, drops). The cast
##                      locks out for the canonical action time (800 ms base, weapon-speed scaled: 810 ms at Normal 6)
##                      and plants the player like a ground attack. The thrown shell is presentation.
##        Recovery      a timed effect: the level's HP total over its 30 s in equal ticks (EffectTicker heals).
##        Nimble Feet   a timed effect: Speed + the level's bonus for its duration (StatCalculator counts it; the
##                      PlayerController re-reads its speed on Events.stats_changed).
##   6. the canonical cooldown starts (CharacterState.cooldowns, remaining seconds), and Events.skill_used fires.
## The MisoStory values (Recovery's tick, the buff cast lockout, whether a whiff spends the shell, the wall test and
## what blocks it, the projectile) come from data/misostory/skills.json (SkillRules).
##
## Collaborators resolve through the owning PlayerCombat at call time (tests set its db/game after it entered the
## tree); every one may be overridden here.

signal cast_started(skill_id: String, level: int, lockout_s: float)
## After a Three Snails cast, once per target hit: a monster with its DamageResult, or target and result both null on a
## whiff.
signal cast_resolved(skill_id: String, target: Node, result: DamageResult)
signal cast_refused(skill_id: String, code: String)

## Group the HUD quickslots find this node by when they have no GameContext player.
const GROUP := &"miso_player_skills"
## Name of the thrown-shell presentation node (it leaves the player on the canonical 28 px aim line).
const SHELL_FX_NAME := "SnailShell"

## The PlayerController (duck-typed: global_position, facing, is_grounded(), is_climbing(), is_dead(),
## is_input_enabled(), in_hitstun; optionally is_seated() and stand_up() / stand()).
var player: Node3D = null
## The PlayerCombat whose lockout casts share (and whose collaborators these resolve through).
var combat: PlayerCombat = null
## Injection seams (tests): null = the PlayerCombat's.
var db: ContentDB = null
var game: Node = null
var character: CharacterState = null
var rng: RandomNumberGenerator = null
var bus: Object = null

## Successful casts (tests, the sandbox report) and the last one.
var casts: int = 0
var last_skill: String = ""
var last_level: int = 0
var last_lockout_s: float = 0.0
var last_target: Node = null
var last_result: DamageResult = null
var last_refusal: Dictionary = {}
## Where the last thrown shell ended (shell_end) and whether a wall stopped it short of its reach.
var last_shell_to: Vector3 = Vector3.ZERO
var last_shell_stopped: bool = false
## The last thrown shell's node (SHELL_FX_NAME) and its flight (tests step it with Tween.custom_step); presentation.
var last_shell: Node3D = null
var last_shell_flight: Tween = null
## Where the shell's mesh comes from (tests pin a pack or none); null = EffectMeshes.shared().
var effect_meshes: EffectMeshes = null

## The last cast set a lockout, and PlayerCombat's attack count when it did (is_casting()).
var _cast_locked := false
var _attacks_at_cast := 0


func _ready() -> void:
	add_to_group(GROUP)
	if player == null:
		player = get_parent() as Node3D
	_register_debug_commands.call_deferred()


## Casts a skill now if the rules allow it. Returns {ok, code, skill_id, level, ...}: on success also "lockout_s",
## "target" (Three Snails: the monster hit or null) and "result"; on a refusal "code" is a SkillBook code (and
## "cooldown_left", "item_id", "mp" when they explain it). A refusal changes nothing.
## `ignore_input_hold` is for the debug console's `cast` command only: the open console holds the player's input
## (GameContext.push_modal), which would refuse every console cast as "busy". It skips only that one check; death,
## hit-stun, a running attack or cast and every SkillBook rule still refuse.
func cast(skill_id: String, ignore_input_hold: bool = false) -> Dictionary:
	var d := _db()
	var c := _character()
	if player == null or not is_instance_valid(player) or d == null or c == null:
		return _refuse(skill_id, {"code": SkillBook.UNAVAILABLE})
	if _is_dead():
		return _refuse(skill_id, {"code": SkillBook.DEAD})
	if not _can_act(ignore_input_hold):
		return _refuse(skill_id, {"code": SkillBook.BUSY})
	var check := SkillBook.check_cast(c, skill_id, d, position_now())
	if not check.ok:
		return _refuse(skill_id, check)
	var def: SkillDef = check.def
	var level := int(check.level)
	var rules := SkillRules.of(d)
	var hits: Array = []
	if def.kind == SkillDef.KIND_ATTACK:
		hits = _search(def)
		if hits.is_empty() and not rules.whiff_consumes_costs:
			return _refuse(skill_id, {"code": SkillBook.NO_TARGET})
	_stand_up()
	_pay(c, d, int(check.mp), String(check.item_id), int(check.item_qty))
	var out := {"ok": true, "code": SkillBook.OK, "skill_id": skill_id, "level": level, "lockout_s": 0.0,
		"target": null, "result": null}
	match def.kind:
		SkillDef.KIND_ATTACK:
			_throw(def, level, hits, out)
		SkillDef.KIND_HEAL:
			_start_heal(c, def, level, rules)
			_lock_buff(rules, out)
		SkillDef.KIND_BUFF:
			_start_buff(c, def, level)
			_lock_buff(rules, out)
	EffectBook.start_cooldown(c, skill_id, def.cooldown_s(level))
	casts += 1
	last_skill = skill_id
	last_level = level
	last_lockout_s = float(out.lockout_s)
	last_refusal = {}
	_cast_locked = last_lockout_s > 0.0
	_attacks_at_cast = combat.attacks if combat != null and is_instance_valid(combat) else 0
	cast_started.emit(skill_id, level, last_lockout_s)
	_emit(&"skill_used", [skill_id, level])
	return out


## Where the player is for cast_position: "rope" on a ladder or rope, "ground" on walkable ground, else "air".
func position_now() -> String:
	if player != null and player.has_method("is_climbing") and bool(player.call("is_climbing")):
		return "rope"
	if player != null and player.has_method("is_grounded") and bool(player.call("is_grounded")):
		return "ground"
	return "air"


## True when a cast of `skill_id` would not wait: the player can act now (alive, input enabled, no hit-stun, no attack
## or cast lockout running) and the skill is not cooling down. A held skill key (MisoHud, #20) casts again only then,
## so the lockout and the cooldown are waited out silently; every other rule (MP, shell, position) is cast()'s.
func ready_to_cast(skill_id: String) -> bool:
	var c := _character()
	if player == null or not is_instance_valid(player) or c == null or _is_dead() or not _can_act():
		return false
	return EffectBook.cooldown_left(c, skill_id) <= 0.0


## True while the last cast's lockout runs (PlayerCombat.is_attacking() covers casts and attacks alike).
func is_casting() -> bool:
	return _cast_locked and combat != null and is_instance_valid(combat) and combat.lockout_left > 0.0 \
		and combat.attacks == _attacks_at_cast


## The player-facing line for a refusal ("" for the silent ones: dead, busy, unavailable, no target).
static func refusal_text(res: Dictionary, content: ContentDB) -> String:
	var sid := String(res.get("skill_id", ""))
	var def := SkillDef.of(sid, content) if content != null else null
	var skill_name := def.name if def != null else sid
	match String(res.get("code", "")):
		SkillBook.NOT_LEARNED:
			return "You have not learned %s." % skill_name
		SkillBook.POSITION:
			return "%s can be used %s." % [skill_name, _position_phrase(def)]
		SkillBook.COOLDOWN:
			return "%s is not ready yet (%d s)." % [skill_name, ceili(float(res.get("cooldown_left", 0.0)))]
		SkillBook.NO_MP:
			return "Not enough MP for %s." % skill_name
		SkillBook.NO_ITEM:
			var item_id := String(res.get("item_id", ""))
			var item_name := String(content.item(item_id).get("name", item_id)) if content != null and content.has("items", item_id) else item_id
			return "%s needs a %s." % [skill_name, item_name]
		SkillBook.UNKNOWN_SKILL:
			return "Unknown skill."
	return ""


static func _position_phrase(def: SkillDef) -> String:
	if def == null:
		return "only in some places"
	if def.cast_positions == PackedStringArray(["ground"]):
		return "only on the ground"
	return "only " + " or ".join(def.cast_positions)


# --- the effects -------------------------------------------------------------------------------------------------

## The targets a Three Snails cast would hit from where the player stands now, nearest first (at most the skill's
## canonical target count): live monsters only. Wooden Boxes are never searched (breakables.json hit_rule, #5). With
## skills.json three_snails.terrain_check (#6) a monster counts only with a clear line from the aim point to its body
## (SkillSight: terrain and buildings block, props do not), so a nearer monster behind a wall is skipped.
func _search(def: SkillDef) -> Array:
	var d := _db()
	var sys := _system()
	var candidates: Array = []
	if sys != null and sys.has_method("attack_candidates"):
		candidates.append_array(sys.call("attack_candidates"))
	if candidates.is_empty() or def.band.is_empty():
		return []
	var facing: Vector3 = player.get("facing") if "facing" in player else Vector3.BACK
	var bands := SkillTargeting.bands_px(def.band)
	var depth := CombatReach.attack_box_depth_px(d)
	var cap := maxi(1, def.targets)
	var rules := SkillRules.of(d)
	var space := _space()
	if not rules.terrain_check or space == null:
		return SkillTargeting.pick(player.global_position, facing, bands, depth, candidates, cap)
	var out: Array = []
	var from := _aim_from(def)
	for h: Dictionary in SkillTargeting.pick(player.global_position, facing, bands, depth, candidates, candidates.size()):
		if out.size() >= cap:
			break
		if SkillSight.clear(space, from, _aim_at(def, h["node"]), rules.sight_blocking_hulls):
			out.append(h)
	return out


func _throw(def: SkillDef, level: int, hits: Array, out: Dictionary) -> void:
	var d := _db()
	var c := _character()
	var stats := PlayerCombatStats.from_character(c, d)
	var weapon := stats.weapon if stats.weapon != null else WeaponProfile.bare_hands(d)
	var lock_s := def.action_ms(weapon.speed_tier, d) / 1000.0
	out["lockout_s"] = lock_s
	if combat != null and is_instance_valid(combat):
		combat.begin_lockout(lock_s, true)
	var facing: Vector3 = player.get("facing") if "facing" in player else Vector3.BACK
	last_target = null
	last_result = null
	var r := _rng()
	for h: Dictionary in hits:
		var target: Node = h["node"]
		var target_stats: MonsterCombatStats = target.get("def").stats if target != null and target.get("def") != null else null
		if target_stats == null:
			continue
		var res := CombatFormula.resolve_fixed_damage(stats, target_stats, def.fixed_damage(level), def.id, r, d)
		if last_target == null:
			last_target = target
			last_result = res
		var sys := _system()
		_play_shell(def, level, target)
		if sys != null and sys.has_method("apply_player_hit"):
			sys.call("apply_player_hit", target, res, player)
		elif target.has_method("receive_hit"):
			target.call("receive_hit", res, player)
		cast_resolved.emit(def.id, target, res)
	if last_target == null:
		_play_shell(def, level, null, facing)
		cast_resolved.emit(def.id, null, null)
	out["target"] = last_target
	out["result"] = last_result


func _start_heal(c: CharacterState, def: SkillDef, level: int, rules: SkillRules) -> void:
	var duration := def.duration_s(level)
	EffectBook.add(c, effect_id(def.id), "skill:" + def.id, duration, {"skill_id": def.id, "level": level,
		"hp_total": def.hp_total(level), "duration_s": duration, "tick_s": rules.recovery_tick_s, "ticks_done": 0})
	_emit(&"effects_changed")


func _start_buff(c: CharacterState, def: SkillDef, level: int) -> void:
	var duration := def.duration_s(level)
	EffectBook.add(c, effect_id(def.id), "skill:" + def.id, duration, {"skill_id": def.id, "level": level,
		"duration_s": duration, "bonuses": {"speed": def.speed_bonus(level)}})
	_emit(&"stats_changed")
	_emit(&"effects_changed")


func _lock_buff(rules: SkillRules, out: Dictionary) -> void:
	out["lockout_s"] = rules.buff_lockout_s
	if rules.buff_lockout_s > 0.0 and combat != null and is_instance_valid(combat):
		combat.begin_lockout(rules.buff_lockout_s, false)


## The CharacterState.effects id of a skill's effect ("skill:0001002"); a re-cast replaces it.
static func effect_id(skill_id: String) -> String:
	return "skill:" + skill_id


func _pay(c: CharacterState, d: ContentDB, mp: int, item_id: String, qty: int) -> void:
	if mp > 0:
		var g := _game()
		if g != null and g.has_method("change_mp"):
			g.call("change_mp", -mp)
		else:
			StatCalculator.change_mp(c, -mp, d)
			_emit(&"mp_changed", [c.mp, StatCalculator.max_mp(c, d)])
	if item_id != "" and qty > 0:
		ItemService.new(c, d, _bus()).lose(item_id, qty)


# --- presentation ------------------------------------------------------------------------------------------------

## Where the shell leaves the player: the canonical aim line (aim_px above the feet).
func _aim_from(def: SkillDef) -> Vector3:
	return player.global_position + Vector3.UP * WorldScale.actor(float(def.band.get("aim_px", 0.0)))


## Where the shell meets `target`: its body centre (Monster.body_center), else the aim height above its feet.
func _aim_at(def: SkillDef, target: Node) -> Vector3:
	if target is Node3D and target.has_method("body_center"):
		return target.call("body_center")
	return (target as Node3D).global_position + Vector3.UP * WorldScale.actor(float(def.band.get("aim_px", 0.0)))


## Where a thrown shell ends: on the target's body, or on a whiff straight ahead at the full reach, cut short by the
## first wall in the way when terrain_check is on (SkillSight.first_block). Sets last_shell_to / last_shell_stopped.
func shell_end(def: SkillDef, target: Node, facing: Vector3) -> Vector3:
	var from := _aim_from(def)
	last_shell_stopped = false
	if target is Node3D and (target as Node3D).is_inside_tree():
		last_shell_to = _aim_at(def, target)
		return last_shell_to
	var f := Vector3(facing.x, 0.0, facing.z)
	f = f.normalized() if f.length_squared() > 1e-6 else Vector3.FORWARD
	last_shell_to = from + f * WorldScale.actor(def.range_px)
	var rules := SkillRules.of(_db())
	var space := _space()
	if rules.terrain_check and space != null:
		var hit := SkillSight.first_block(space, from, last_shell_to, rules.sight_blocking_hulls)
		if not hit.is_empty():
			last_shell_to = hit["position"]
			last_shell_stopped = true
	return last_shell_to


## A shell flies from the player's aim line to the target's body (or, on a whiff, to shell_end: the full reach or the
## first wall). With the art pack it is the pack's ThreeSnails mesh (EffectMeshes), as tall as projectile_size_m and
## turned along its flight; without it a procedural sphere in the shell item's colour. Same path and speed either way.
func _play_shell(def: SkillDef, level: int, target: Node, facing: Vector3 = Vector3.ZERO) -> void:
	if player == null or not player.is_inside_tree():
		return
	var from := _aim_from(def)
	var to := shell_end(def, target, facing)
	var rules := SkillRules.of(_db())
	if rules.projectile_speed_mps <= 0.0 or rules.projectile_size_m <= 0.0:
		return
	var parent := _fx_parent()
	if parent == null:
		return
	var meshes := effect_meshes if effect_meshes != null else EffectMeshes.shared()
	var shell := meshes.centered(EffectMeshes.THREE_SNAILS, rules.projectile_size_m)
	if shell == null:
		shell = _procedural_shell(def, level, rules)
	shell.name = SHELL_FX_NAME
	shell.top_level = true
	parent.add_child(shell)
	shell.global_position = from
	var along := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if along.length_squared() > 1e-6:
		shell.global_basis = Basis.looking_at(along.normalized(), Vector3.UP)
	var t := shell.create_tween()
	t.tween_property(shell, "global_position", to, maxf(0.05, from.distance_to(to) / rules.projectile_speed_mps))
	t.tween_callback(shell.queue_free)
	last_shell = shell
	last_shell_flight = t


## The no-art shell: an unshaded sphere of projectile_size_m in the level's shell item colour.
func _procedural_shell(def: SkillDef, level: int, rules: SkillRules) -> MeshInstance3D:
	var shell := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = rules.projectile_size_m * 0.5
	mesh.height = rules.projectile_size_m * 0.8
	mesh.radial_segments = 12
	mesh.rings = 6
	shell.mesh = mesh
	var mat := StandardMaterial3D.new()
	var item := def.item_cost(level)
	var item_def := ItemDef.of(String(item.get("item_id", "")), _db())
	mat.albedo_color = MisoItemIcon.color_for(item_def) if item_def != null else Color(0.8, 0.7, 0.5)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell.material_override = mat
	return shell


func _fx_parent() -> Node:
	var sys := _system()
	if sys != null and sys.get("attack_fx") is Node and (sys.get("attack_fx") as Node).is_inside_tree():
		return sys.get("attack_fx")
	return player.get_parent() if player != null else null


# --- helpers -----------------------------------------------------------------------------------------------------

func _refuse(skill_id: String, check: Dictionary) -> Dictionary:
	var out := {"ok": false, "skill_id": skill_id}
	for k in check:
		if k != "def":
			out[k] = check[k]
	last_refusal = out
	cast_refused.emit(skill_id, String(out.get("code", "")))
	return out


func _can_act(ignore_input_hold: bool = false) -> bool:
	if not ignore_input_hold and player.has_method("is_input_enabled") and not bool(player.call("is_input_enabled")):
		return false
	if "in_hitstun" in player and bool(player.get("in_hitstun")):
		return false
	if combat != null and is_instance_valid(combat) and combat.lockout_left > 0.0:
		return false
	return true


func _is_dead() -> bool:
	var g := _game()
	if g != null and g.has_method("is_character_dead") and bool(g.call("is_character_dead")):
		return true
	return player.has_method("is_dead") and bool(player.call("is_dead"))


## A seated player stands up before the cast (C5: PlayerController.stand_up with the reason "skill").
func _stand_up() -> void:
	if player == null or not player.has_method("is_seated") or not bool(player.call("is_seated")):
		return
	player.call("stand_up", &"skill")


func _system() -> Node:
	return combat.system if combat != null and is_instance_valid(combat) else null


## The physics space the line-of-sight test reads (the player's world), or null outside a world.
func _space() -> PhysicsDirectSpaceState3D:
	if player == null or not player.is_inside_tree() or player.get_world_3d() == null:
		return null
	return player.get_world_3d().direct_space_state


func _db() -> ContentDB:
	if db != null:
		return db
	if combat != null and is_instance_valid(combat):
		return combat.content_db()
	var data := get_node_or_null(^"/root/Data") if is_inside_tree() else null
	return data.get("db") as ContentDB if data != null else null


func _game() -> Node:
	if game != null:
		return game
	if combat != null and is_instance_valid(combat):
		return combat.game_node()
	return get_node_or_null(^"/root/Game") if is_inside_tree() else null


func _character() -> CharacterState:
	if character != null:
		return character
	if combat != null and is_instance_valid(combat):
		return combat.live_character()
	var g := _game()
	return g.get("character") as CharacterState if g != null else null


func _rng() -> RandomNumberGenerator:
	if rng != null:
		return rng
	if combat != null and is_instance_valid(combat):
		return combat.roll_rng()
	rng = RandomNumberGenerator.new()
	return rng


func _bus() -> Object:
	if bus != null:
		return bus
	if combat != null and is_instance_valid(combat):
		return combat.event_bus()
	return get_node_or_null(^"/root/Events") if is_inside_tree() else null


func _emit(sig: StringName, args: Array = []) -> void:
	var b := _bus()
	if b != null and b.has_signal(sig):
		b.callv(&"emit_signal", [sig] + args)


# --- debug console -------------------------------------------------------------------------------------------------

func _register_debug_commands() -> void:
	var dbg := get_node_or_null(^"/root/Debug") if is_inside_tree() else null
	if dbg == null or not dbg.has_method("register_command"):
		return
	dbg.call("register_command", "skills", "skills: skill levels, SP, cooldowns and active effects", _cmd_skills)
	dbg.call("register_command", "cast", "cast <skill id|name>: cast a skill now (PlayerSkills.cast)", _cmd_cast)


func _cmd_skills(_args: PackedStringArray) -> String:
	var c := _character()
	var d := _db()
	if c == null or d == null:
		return "no character"
	var lines: PackedStringArray = ["SP %d" % c.sp]
	for def in SkillDef.catalog(c.job, d):
		lines.append("%s %s: Lv %d/%d, cooldown %.1f s" % [def.id, def.name, SkillBook.level_of(c, def.id), def.max_level,
			EffectBook.cooldown_left(c, def.id)])
	for e in c.effects:
		if e is Dictionary:
			lines.append("effect %s: %.1f s left" % [String(e.get("id", "")), EffectBook.remaining_of(e)])
	return "\n".join(lines)


func _cmd_cast(args: PackedStringArray) -> String:
	if args.is_empty():
		return "usage: cast <skill id|name>"
	var want := " ".join(args).to_lower()
	var c := _character()
	var sid := ""
	for def in SkillDef.catalog(c.job if c != null else "beginner", _db()):
		if def.id == want or def.name.to_lower() == want:
			sid = def.id
	if sid == "":
		return "no skill '%s'" % want
	# The console is open while this runs and holds the player's input: cast past that hold (only).
	var res := cast(sid, true)
	return "cast %s" % sid if res.ok else "refused: %s %s" % [String(res.code), refusal_text(res, _db())]
