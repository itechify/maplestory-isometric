extends TestCase
## The pack's effect meshes on the existing skill and combat events (#71): the hit spark plays where AttackFx.spark
## played its procedural burst, for the same life. Each pack test pins the pack path with EffectMeshes.from_pack and
## prints SKIP without an installed pack (bash scripts/art_pack.sh fetch); the procedural tests pin
## EffectMeshes.none(), so both paths are proven whatever the copy holds.

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
