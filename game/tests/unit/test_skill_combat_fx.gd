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
