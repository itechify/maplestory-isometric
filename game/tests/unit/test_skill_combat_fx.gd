extends TestCase
## The pack's effect meshes on the existing skill and combat events (#71): the hit spark plays where AttackFx.spark
## played its procedural burst, for the same life; Three Snails' shell flies the same path and ends where it ended
## (the target, or the wall a whiff meets); Recovery and Nimble Feet show for exactly as long as their timed effects
## run (expiry, death, a recast, a load); dust plays at the feet on a ground jump and a landing. Each pack test pins
## the pack path with EffectMeshes.from_pack and prints SKIP without an installed pack (bash scripts/art_pack.sh
## fetch); the procedural tests pin EffectMeshes.none(), so both paths are proven whatever the copy holds.

var host: Node3D = null
var _art: ArtPack = null


func before_each() -> void:
	host = Node3D.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(host)
	_art = ArtPack.load_installed()


func after_each() -> void:
	if host != null and is_instance_valid(host):
		host.free()


func _skip(test: String) -> bool:
	if _art.present():
		return false
	print("SKIP %s: no art pack installed (bash scripts/art_pack.sh fetch)" % test)
	return true


func _pack() -> EffectMeshes:
	return EffectMeshes.from_pack(_art)


## The world-space bounds of every mesh under `n` (rest pose).
func _world_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in n.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _transparencies(n: Node) -> Array:
	var out := []
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		out.append((g as GeometryInstance3D).transparency)
	return out


# --- the hit spark (AttackFx.spark) -------------------------------------------------------------------------------

func test_without_the_pack_the_spark_is_the_procedural_burst() -> void:
	var fx := AttackFx.new()
	fx.effect_meshes = EffectMeshes.none()
	host.add_child(fx)
	var s := fx.spark(Vector3(1, 1, 0), 0.35)
	assert_true(s is MeshInstance3D and (s as MeshInstance3D).mesh is ArrayMesh, "the procedural starburst")
	assert_eq(fx.live_count(), 1, "one live effect")
	fx.advance(AttackFx.SPARK_LIFE_S + 0.01)
	assert_eq(fx.live_count(), 0, "gone after its life")


func test_the_pack_hit_spark_plays_where_the_spark_played_for_its_life() -> void:
	if _skip("test_the_pack_hit_spark_plays_where_the_spark_played_for_its_life"):
		return
	var fx := AttackFx.new()
	fx.effect_meshes = _pack()
	host.add_child(fx)
	var at := Vector3(2.0, 0.6, -1.0)
	var s := fx.spark(at, 0.35)
	assert_true(s != null and s.find_child(EffectMeshes.HIT_SPARK, true, false) != null, "the pack's HitSpark model")
	assert_false(s is MeshInstance3D, "not the procedural burst")
	var box := _world_aabb(s)
	assert_near(box.get_center().y, at.y, 0.05, "centred on the spark's point (y %.2f)" % box.get_center().y)
	assert_near(box.get_center().x, at.x, 0.05, "and across it")
	assert_between(box.size.y, 0.35, 0.35 * 2.0 * 1.2, "as tall as the burst's diameter (%.2f m)" % box.size.y)
	var ap := s.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_true(ap != null and ap.is_playing() and ap.current_animation == EffectMeshes.CLIP, "its Loop clip plays")
	for g in s.find_children("*", "GeometryInstance3D", true, false):
		assert_eq((g as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow")
	assert_eq(fx.live_count(), 1, "one live effect")
	fx.advance(AttackFx.SPARK_LIFE_S * 0.5)
	assert_eq(fx.live_count(), 1, "still playing halfway through its life")
	for t in _transparencies(s):
		assert_between(t, 0.2, 0.8, "fading out")
	fx.advance(AttackFx.SPARK_LIFE_S * 0.5 + 0.01)
	assert_eq(fx.live_count(), 0, "gone after the spark's life, %.2f s" % AttackFx.SPARK_LIFE_S)
	assert_true(s.is_queued_for_deletion(), "and freed")


# --- Three Snails: the thrown shell (PlayerSkills._play_shell) ----------------------------------------------------

const SNAILS := "0001000"


func _rig() -> MonsterTestRig:
	var rig := MonsterTestRig.create(db(), 7)
	rig.floor(60.0)
	return rig


func _caster(rig: MonsterTestRig, meshes: EffectMeshes) -> PlayerSkills:
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var c := rig.character()
	c.skills = {SNAILS: 1}
	c.base_max_mp = 500
	c.mp = 500
	ItemService.new(c, db(), null).gain("348", 3)
	var ps: PlayerSkills = p.get_node(^"PlayerSkills")
	ps.effect_meshes = meshes
	rig.run(5)
	return ps


func _aim_from(ps: PlayerSkills) -> Vector3:
	var def := SkillDef.of(SNAILS, db())
	return ps.player.global_position + Vector3.UP * WorldScale.actor(float(def.band.get("aim_px", 0.0)))


## The shell leaves the aim line on the cast and lands on `to`, then goes.
func _assert_flight(ps: PlayerSkills, to: Vector3, what: String) -> void:
	var shell := ps.last_shell
	assert_true(shell != null and shell.name == PlayerSkills.SHELL_FX_NAME, "%s: a %s flies" % [what, PlayerSkills.SHELL_FX_NAME])
	if shell == null:
		return
	assert_true(shell.global_position.distance_to(_aim_from(ps)) < 0.01, "%s: it starts on the aim line" % what)
	ps.last_shell_flight.custom_step(0.05)
	assert_true(shell.global_position.distance_to(_aim_from(ps)) > 0.1, "%s: it is on its way" % what)
	assert_false(shell.is_queued_for_deletion(), "%s: still flying" % what)
	ps.last_shell_flight.custom_step(10.0)
	assert_true(shell.global_position.distance_to(to) < 0.01, "%s: it ends at %s, got %s" % [what, to, shell.global_position])
	assert_true(shell.is_queued_for_deletion(), "%s: and goes when it lands" % what)


func test_without_the_pack_three_snails_throws_the_procedural_shell() -> void:
	var rig := _rig()
	var ps := _caster(rig, EffectMeshes.none())
	var m := rig.spawn("2", Vector3(WorldScale.actor(200.0), 0.0, 0.0))
	var res := ps.cast(SNAILS)
	assert_true(res.ok and res.target == m, "the Snail is the target")
	assert_true(ps.last_shell is MeshInstance3D and (ps.last_shell as MeshInstance3D).mesh is SphereMesh, "the procedural shell")
	_assert_flight(ps, m.body_center(), "a hit")
	rig.free_all()


func test_the_pack_three_snails_flies_the_same_path_to_the_target() -> void:
	if _skip("test_the_pack_three_snails_flies_the_same_path_to_the_target"):
		return
	var rig := _rig()
	var ps := _caster(rig, _pack())
	var m := rig.spawn("2", Vector3(WorldScale.actor(200.0), 0.0, 0.0))
	var res := ps.cast(SNAILS)
	assert_true(res.ok and res.target == m, "the Snail is the target")
	var shell := ps.last_shell
	assert_true(shell != null and shell.find_child(EffectMeshes.THREE_SNAILS, true, false) != null, "the pack's ThreeSnails model")
	assert_false(shell is MeshInstance3D, "not the procedural sphere")
	if shell != null:
		var box := _world_aabb(shell)
		assert_near(box.size.y, SkillRules.of(db()).projectile_size_m, 0.03, "as tall as skills.json projectile_size_m")
		assert_near(box.get_center().y, shell.global_position.y, 0.03, "centred on the flight line")
	_assert_flight(ps, m.body_center(), "a hit")
	assert_eq(ps.last_shell_to, m.body_center(), "the shell's end is unchanged (the target's body)")
	rig.free_all()


func test_the_pack_three_snails_whiff_stops_at_the_wall() -> void:
	if _skip("test_the_pack_three_snails_whiff_stops_at_the_wall"):
		return
	var rig := _rig()
	rig.wall(Vector3(2.0, 1.5, 0.0), Vector3(0.2, 3.0, 3.0))
	var ps := _caster(rig, _pack())
	var res := ps.cast(SNAILS)
	assert_true(res.ok and res.target == null, "a whiff")
	assert_true(ps.last_shell_stopped, "the wall stops the shell")
	assert_near(ps.last_shell_to.x, 1.9, 0.01, "at the wall's face")
	_assert_flight(ps, ps.last_shell_to, "a whiff into a wall")
	rig.free_all()


# --- Recovery and Nimble Feet: shown while the timed effect runs (PlayerFx) ---------------------------------------

const RECOVERY := "0001001"
const NIMBLE := "0001002"


## A player with `skills` learned, its PlayerFx drawing from `meshes`; returns [PlayerSkills, PlayerFx].
func _fx_player(rig: MonsterTestRig, meshes: EffectMeshes, skills: Dictionary) -> Array:
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var c := rig.character()
	c.skills = skills.duplicate()
	c.base_max_mp = 500
	c.mp = 500
	var fx: PlayerFx = p.get_node_or_null(^"PlayerFx")
	assert_true(fx != null, "PlayerCombat gave the player its PlayerFx")
	fx.effect_meshes = meshes
	rig.run(5)
	fx.advance(PlayerFx.DUST_LIFE_S + 0.01)
	return [p.get_node(^"PlayerSkills"), fx]


func _tick(rig: MonsterTestRig, seconds: float) -> void:
	var ticker: EffectTicker = rig.w.player.get_node(^"EffectTicker")
	for i in int(round(seconds / MonsterTestRig.TICK)):
		rig.tick()
		ticker.step(MonsterTestRig.TICK)


func _assert_aura(fx: PlayerFx, skill: String, effect: String, what: String) -> void:
	var a := fx.aura(PlayerSkills.effect_id(skill))
	assert_true(a != null and a.name == effect, "%s: the pack's %s shows" % [what, effect])
	if a == null:
		return
	assert_true(fx.player.is_ancestor_of(a), "%s: it moves with the player" % what)
	var ap := a.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_true(ap != null and ap.is_playing(), "%s: its Loop clip plays" % what)


func test_recovery_shows_its_mesh_for_as_long_as_it_heals() -> void:
	if _skip("test_recovery_shows_its_mesh_for_as_long_as_it_heals"):
		return
	var rig := _rig()
	var pair := _fx_player(rig, _pack(), {RECOVERY: 1})
	var ps: PlayerSkills = pair[0]
	var fx: PlayerFx = pair[1]
	assert_eq(fx.aura_ids(), [], "nothing before the cast")
	assert_true(ps.cast(RECOVERY).ok, "cast")
	_assert_aura(fx, RECOVERY, EffectMeshes.RECOVERY, "on the cast")
	var shown := fx.aura(PlayerSkills.effect_id(RECOVERY))
	var duration := SkillDef.of(RECOVERY, db()).duration_s(1)
	_tick(rig, duration - 0.5)
	assert_true(EffectBook.has(rig.character(), PlayerSkills.effect_id(RECOVERY)), "still healing")
	assert_true(fx.aura(PlayerSkills.effect_id(RECOVERY)) == shown, "the same mesh shows all along")
	_tick(rig, 1.0)
	assert_false(EffectBook.has(rig.character(), PlayerSkills.effect_id(RECOVERY)), "the heal ended")
	assert_eq(fx.aura_ids(), [], "and its mesh with it")
	assert_true(not is_instance_valid(shown) or shown.is_queued_for_deletion(), "freed")
	rig.free_all()


func test_nimble_feet_shows_its_mesh_until_it_ends_and_a_recast_keeps_one() -> void:
	if _skip("test_nimble_feet_shows_its_mesh_until_it_ends_and_a_recast_keeps_one"):
		return
	var rig := _rig()
	var pair := _fx_player(rig, _pack(), {NIMBLE: 1})
	var ps: PlayerSkills = pair[0]
	var fx: PlayerFx = pair[1]
	assert_true(ps.cast(NIMBLE).ok, "cast")
	_assert_aura(fx, NIMBLE, EffectMeshes.NIMBLE_FEET, "on the cast")
	_tick(rig, 2.0)
	rig.character().cooldowns.clear()
	assert_true(ps.cast(NIMBLE).ok, "a recast (cooldown cleared) replaces the effect")
	assert_eq(fx.aura_ids(), [PlayerSkills.effect_id(NIMBLE)], "still exactly one Nimble Feet mesh")
	var live := fx.find_children(EffectMeshes.NIMBLE_FEET, "", false, false).filter(
		func(n: Node) -> bool: return not n.is_queued_for_deletion())
	assert_eq(live.size(), 1, "one node")
	_tick(rig, SkillDef.of(NIMBLE, db()).duration_s(1) + 0.1)
	assert_false(EffectBook.has(rig.character(), PlayerSkills.effect_id(NIMBLE)), "the buff ended")
	assert_eq(fx.aura_ids(), [], "and its mesh with it")
	rig.free_all()


func test_both_meshes_end_when_death_ends_the_effects() -> void:
	if _skip("test_both_meshes_end_when_death_ends_the_effects"):
		return
	var rig := _rig()
	var pair := _fx_player(rig, _pack(), {NIMBLE: 1, RECOVERY: 1})
	var ps: PlayerSkills = pair[0]
	var fx: PlayerFx = pair[1]
	assert_true(ps.cast(NIMBLE).ok, "Nimble Feet cast")
	rig.system.player_combat.lockout_left = 0.0
	assert_true(ps.cast(RECOVERY).ok, "Recovery cast")
	assert_eq(fx.aura_ids().size(), 2, "both show")
	rig.bus.emit_signal(&"player_died", "000000040")
	assert_true(rig.character().effects.is_empty(), "death ended the effects")
	assert_eq(fx.aura_ids(), [], "and both meshes")
	rig.free_all()


func test_a_loaded_or_replaced_character_shows_its_own_effects() -> void:
	if _skip("test_a_loaded_or_replaced_character_shows_its_own_effects"):
		return
	var rig := _rig()
	var pair := _fx_player(rig, _pack(), {})
	var fx: PlayerFx = pair[1]
	var c := rig.character()
	EffectBook.add(c, PlayerSkills.effect_id(RECOVERY), "skill:" + RECOVERY, 12.0, {"skill_id": RECOVERY, "level": 1})
	rig.bus.emit_signal(&"game_loaded", "slot1")
	assert_eq(fx.aura_ids(), [PlayerSkills.effect_id(RECOVERY)], "a loaded save's Recovery shows")
	var other := CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	EffectBook.add(other, PlayerSkills.effect_id(NIMBLE), "skill:" + NIMBLE, 5.0, {"bonuses": {"speed": 10}})
	rig.game.character = other
	rig.game.character_replaced.emit("load")
	assert_eq(fx.aura_ids(), [PlayerSkills.effect_id(NIMBLE)], "the replacing character's Nimble Feet, not the old Recovery")
	rig.free_all()


func test_without_the_pack_timed_effects_show_nothing() -> void:
	var rig := _rig()
	var pair := _fx_player(rig, EffectMeshes.none(), {NIMBLE: 1, RECOVERY: 1})
	var ps: PlayerSkills = pair[0]
	var fx: PlayerFx = pair[1]
	assert_true(ps.cast(NIMBLE).ok, "Nimble Feet cast")
	rig.system.player_combat.lockout_left = 0.0
	assert_true(ps.cast(RECOVERY).ok, "Recovery cast")
	assert_eq(fx.aura_ids(), [], "no mesh, as before the pack")
	assert_eq(fx.get_child_count(), 0, "nothing under PlayerFx")
	rig.free_all()


# --- dust: a ground jump and a landing (PlayerController.jumped / landed) -----------------------------------------

func _assert_puff(fx: PlayerFx, at: Vector3, what: String) -> void:
	assert_eq(fx.dust_count(), 1, "%s: one puff of dust" % what)
	var d := fx.last_dust()
	assert_true(d != null and d.scene_file_path == _art.model(ArtPack.EFFECT, EffectMeshes.JUMP_DUST),
		"%s: the pack's JumpDust" % what)
	if d == null:
		return
	assert_true(d.global_position.distance_to(at) < 0.02, "%s: at the feet %s, got %s" % [what, at, d.global_position])
	fx.advance(PlayerFx.DUST_LIFE_S * 0.5)
	assert_eq(fx.dust_count(), 1, "%s: still there halfway" % what)
	fx.advance(PlayerFx.DUST_LIFE_S * 0.5 + 0.01)
	assert_eq(fx.dust_count(), 0, "%s: gone after %.2f s" % [what, PlayerFx.DUST_LIFE_S])
	assert_true(d.is_queued_for_deletion(), "%s: freed" % what)


func test_dust_plays_on_a_ground_jump_and_on_the_landing() -> void:
	if _skip("test_dust_plays_on_a_ground_jump_and_on_the_landing"):
		return
	var rig := _rig()
	var fx: PlayerFx = _fx_player(rig, _pack(), {})[1]
	var p := rig.w.player
	assert_true(p.is_grounded(), "standing")
	assert_eq(fx.dust_count(), 0, "no dust standing still")
	var feet := p.global_position
	var jumps := [0]
	p.jumped.connect(func() -> void: jumps[0] += 1)
	rig.w.bot.press(&"jump")
	rig.tick()
	assert_eq(jumps[0], 1, "the player jumped")
	_assert_puff(fx, feet, "the take-off")
	var landed: Array = []
	p.landed.connect(func(_s: float) -> void: landed.append(p.global_position))
	for i in 120:
		rig.tick()
		if not landed.is_empty():
			break
	assert_eq(landed.size(), 1, "the player landed")
	if not landed.is_empty():
		_assert_puff(fx, landed[0], "the landing")
	rig.free_all()


func test_no_dust_on_a_jump_off_a_rope_in_mid_air() -> void:
	if _skip("test_no_dust_on_a_jump_off_a_rope_in_mid_air"):
		return
	var rig := _rig()
	var fx: PlayerFx = _fx_player(rig, _pack(), {})[1]
	var p := rig.w.player
	var rope := ClimbableDef.from_sidecar({"name": "R", "kind": "rope", "bottom": [1.0, 0.0, 0.0], "top": [1.0, 4.0, 0.0],
		"foot_ground": [1.0, 0.0, 0.0], "top_exit": [1.5, 4.0, 0.0], "facing_xz": [1.0, 0.0], "descend_only": false})
	p.set_climbables([rope])
	assert_true(p.grab_climbable(rope), "on the rope")
	rig.w.bot.hold(&"move_up")
	for i in 40:
		rig.tick()
	rig.w.bot.release_all()
	assert_true(p.is_climbing() and p.global_position.y > 0.5, "up the rope (y %.2f)" % p.global_position.y)
	fx.advance(PlayerFx.DUST_LIFE_S + 0.01)
	var ended: Array = []
	p.climb_ended.connect(func(_c: ClimbableDef, how: StringName) -> void: ended.append(how))
	rig.w.bot.world_dir = Vector3.BACK
	rig.w.bot.press(&"jump")
	rig.tick()
	assert_eq(ended, [&"jump"], "jumped off the rope")
	assert_eq(fx.dust_count(), 0, "no dust in mid-air")
	rig.free_all()


func test_without_the_pack_there_is_no_dust() -> void:
	var rig := _rig()
	var fx: PlayerFx = _fx_player(rig, EffectMeshes.none(), {})[1]
	rig.w.bot.press(&"jump")
	rig.run(120)
	assert_eq(fx.dust_count(), 0, "no dust, as before the pack")
	assert_eq(fx.get_child_count(), 0, "nothing under PlayerFx")
	rig.free_all()
