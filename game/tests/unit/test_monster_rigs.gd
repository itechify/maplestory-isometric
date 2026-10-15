extends TestCase
## The six monsters' rigged pack models (#64): MonsterVisual.build loads the species' model from the art pack by
## canonical id (ArtPack.MONSTER), fits it to the canonical sprite height (model_fit), and plays the clip the monster's
## state selects (Idle, Walk, Attack, Hit, Death) while the hit flash, HP bar, fades, facing and the see-through
## silhouette keep working on the skinned meshes. Without the pack the proxies stay.
##
## Most tests run on a stand-in pack written to user:// (a two-bone skinned rig with the pack's five clips), so they
## hold with or without the real pack; the test_real_pack_* tests use the installed pack and print SKIP without it.

const STANDIN := "user://_tests/monster_rigs_pack"
const CLIPS := ["Idle", "Walk", "Attack", "Hit", "Death"]
## The stand-in rig's rest height (m) before model_fit.
const STANDIN_H := 0.5

var host: Node3D


func before_each() -> void:
	host = Node3D.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(host)


func after_each() -> void:
	host.free()


# =================================================================================================================
# Stand-in pack
# =================================================================================================================

## A pack with one monster model (canonical ids `ids`, all the same stand-in scene): the pack's layout
## (<Name>/<Name>_Rig/Skeleton3D/{skinned meshes} + AnimationPlayer at the top, clips as imported: Idle and Walk loop).
static func standin_pack(ids: Array = ["2"], clips: Array = CLIPS) -> ArtPack:
	DirAccess.make_dir_recursive_absolute(STANDIN.path_join("monsters"))
	var scene := PackedScene.new()
	var root := _standin_rig(clips)
	scene.pack(root)
	root.free()
	ResourceSaver.save(scene, STANDIN.path_join("monsters/StandIn.tscn"))
	var monsters: Array = []
	for id in ids:
		monsters.append({"id": id, "name": "StandIn", "file": "monsters/StandIn.tscn"})
	var f := FileAccess.open(STANDIN.path_join("asset_index.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"canonical_monsters": monsters}))
	f.close()
	return ArtPack.load_from(STANDIN)


static func _standin_rig(clips: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "StandIn"
	var rig := Node3D.new()
	rig.name = "StandIn_Rig"
	root.add_child(rig)
	rig.owner = root
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	sk.add_bone("root")
	sk.add_bone("body")
	sk.set_bone_parent(1, 0)
	sk.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)))
	sk.reset_bone_poses()
	rig.add_child(sk)
	sk.owner = root
	var skin := Skin.new()
	skin.add_named_bind("root", Transform3D.IDENTITY)
	skin.add_named_bind("body", Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0)))
	# Two materials, each its own mesh (as the import merges them), the second with two surfaces.
	for part in [["Body", [Color(0.9, 0.5, 0.2)]], ["Shell", [Color(0.3, 0.4, 0.9), Color(0.1, 0.1, 0.1)]]]:
		var mi := MeshInstance3D.new()
		mi.name = part[0]
		mi.mesh = _skinned_box(part[1])
		mi.skin = skin
		mi.skeleton = NodePath("..")
		sk.add_child(mi)
		mi.owner = root
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	ap.owner = root
	var lib := AnimationLibrary.new()
	for c in clips:
		var a := Animation.new()
		a.length = 1.0
		a.loop_mode = Animation.LOOP_LINEAR if c in ["Idle", "Walk"] else Animation.LOOP_NONE
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath("StandIn_Rig/Skeleton3D:body"))
		a.rotation_track_insert_key(t, 0.0, Quaternion.IDENTITY)
		a.rotation_track_insert_key(t, 1.0, Quaternion(Vector3.RIGHT, 0.5 + CLIPS.find(c) * 0.1))
		lib.add_animation(c, a)
	ap.add_animation_library("", lib)
	return root


## A box STANDIN_H tall on y = 0, its top half weighted to "body", one surface per colour.
static func _skinned_box(colors: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for i in colors.size():
		var src := BoxMesh.new()
		src.size = Vector3(0.4, STANDIN_H, 0.6)
		var arrays := src.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		for v_i in verts.size():
			verts[v_i] += Vector3(0, STANDIN_H * 0.5, 0)
			bones.append_array([1 if verts[v_i].y > STANDIN_H * 0.5 else 0, 0, 0, 0])
			weights.append_array([1.0, 0.0, 0.0, 0.0])
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var m := StandardMaterial3D.new()
		m.albedo_color = colors[i]
		mesh.surface_set_material(i, m)
	return mesh


## A walking stand-in for the Monster the visual reads (facing, is_walking).
class FakeMonster:
	extends Node3D
	var facing := Vector3.BACK
	var walking := false

	func is_walking() -> bool:
		return walking


func _visual(id: String, art: ArtPack, lib: ProxyLibrary = null) -> MonsterVisual:
	var mon := FakeMonster.new()
	host.add_child(mon)
	var v := MonsterVisual.new()
	v.name = "Visual"
	v.monster = mon
	mon.add_child(v)
	v.set_process(false)
	v.build(MonsterDef.from_id(id, db()), lib, art)
	return v


## The model's meshes (not the fills) and their bounds in the visual's space, at rest.
func _model_box(v: MonsterVisual) -> AABB:
	var box := AABB()
	var first := true
	for n in v.model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if String(mi.name) == MonsterVisual.SEE_THROUGH_NAME or mi.mesh == null:
			continue
		var b := (v.global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


# =================================================================================================================
# The model
# =================================================================================================================

func test_a_species_in_the_pack_uses_its_model_fitted_to_the_sprite_height() -> void:
	var art := standin_pack(["2"])
	var v := _visual("2", art)
	var snail := MonsterDef.from_id("2", db())
	assert_false(v.is_placeholder, "the pack model, not the fallback body")
	assert_eq(v.model_source, art.model(ArtPack.MONSTER, "2"), "built from the pack's Snail model")
	assert_true(v.model.find_child("Skeleton3D", true, false) is Skeleton3D, "the rig came with it")
	assert_near(v.height_m, snail.sprite_size_m.y, 1e-4, "height_m is the canonical sprite height")
	var box := _model_box(v)
	assert_near(box.end.y, snail.sprite_size_m.y, 1e-3, "its top is at the canonical sprite height (model_fit)")
	assert_near(box.position.y, 0.0, 1e-3, "on its feet")


## Owner decision (#59/#64): a model fitted to the sprite height that ends up wider than the species' model width cap
## (1.35x its touch zone width) is scaled down uniformly until it fits. The stand-in (0.4 x 0.5 x 0.6 m at rest) fitted
## to the Tutorial Jr. Sentinel's 1.7 m sprite would be 2.04 m deep against its 0.525 m touch zone.
func test_a_model_wider_than_the_cap_is_scaled_down_uniformly_until_it_fits() -> void:
	var art := standin_pack(["1"])
	var v := _visual("1", art)
	var d := v.def
	var limit := d.model_max_width_m()
	assert_near(limit, 0.525 * 1.35, 1e-4, "the Sentinel's cap")
	var box := _model_box(v)
	var width := maxf(box.size.x, box.size.z)
	assert_near(width, limit, 1e-3, "its widest extent is the cap (%.3f m)" % width)
	# Uniform: the stand-in keeps its 0.4 : 0.5 : 0.6 proportions.
	assert_near(box.size.y, limit * STANDIN_H / 0.6, 1e-3, "scaled uniformly, so shorter than the sprite")
	assert_near(box.size.x, limit * 0.4 / 0.6, 1e-3, "and narrower across")
	assert_near(box.position.y, 0.0, 1e-3, "still on its feet")
	assert_near(v.height_m, box.end.y, 1e-3, "the HP bar sits over the capped model")
	assert_true(v.height_m < d.sprite_size_m.y, "below the sprite height")
	# The touch zone is gameplay: the cap never changes it.
	assert_near(d.touch_size_m.x, 0.525, 1e-6, "touch zone unchanged")


# =================================================================================================================
# Clips follow the state
# =================================================================================================================

## The clip the visual plays, checked against the AnimationPlayer itself.
func _playing(v: MonsterVisual) -> String:
	var ap := v.animation_player()
	assert_true(ap != null, "the rig has its AnimationPlayer")
	if ap == null:
		return ""
	assert_eq(String(ap.assigned_animation), v.clip(), "the AnimationPlayer plays the selected clip")
	return v.clip()


func test_each_state_selects_its_clip() -> void:
	var v := _visual("2", standin_pack(["2"]))
	var mon := v.monster as FakeMonster
	var d := v.def
	v.advance(0.05)
	assert_eq(_playing(v), "Idle", "standing: Idle")
	mon.walking = true
	v.advance(0.05)
	assert_eq(_playing(v), "Walk", "moving: Walk")
	v.on_attack()
	v.advance(0.05)
	assert_eq(_playing(v), "Attack", "its touch: Attack")
	v.on_hit(0.6)
	v.advance(0.05)
	assert_eq(_playing(v), "Hit", "damaged: Hit, over the attack")
	v.on_attack()
	v.advance(0.05)
	assert_eq(_playing(v), "Hit", "a touch never cuts a hit reaction short")
	v.advance(d.hit_s)
	assert_eq(_playing(v), "Walk", "the hit is over after the canonical hit time: back to walking")
	mon.walking = false
	v.advance(0.05)
	assert_eq(_playing(v), "Idle", "stopped: Idle")
	v.on_attack()
	v.advance(1.5)
	assert_eq(_playing(v), "Idle", "the attack plays once, then Idle")
	v.start_death_fade(d.die_fade_s)
	v.advance(0.01)
	assert_eq(_playing(v), "Death", "dead: Death")
	v.on_hit(0.0)
	v.on_attack()
	mon.walking = true
	v.advance(0.05)
	assert_eq(_playing(v), "Death", "nothing interrupts Death")


# =================================================================================================================
# The live monster
# =================================================================================================================

func test_the_system_builds_monsters_from_the_pack_and_a_touch_plays_attack() -> void:
	var rig := MonsterTestRig.create(db())
	rig.floor(40.0)
	rig.system.art = standin_pack(["2"])
	var p := rig.spawn_player(Vector3.ZERO)
	var m := rig.spawn("2", Vector3(0.3, 0, 0))
	assert_eq(m.visual.model_source, rig.system.art.model(ArtPack.MONSTER, "2"), "spawned with the pack model")
	var touched := [0]
	rig.system.player_touched.connect(func(_m: Monster, _r: IncomingResult) -> void: touched[0] += 1)
	rig.run(1)
	assert_eq(touched[0], 1, "it touched the player")
	m.visual.advance(0.01)
	assert_eq(m.visual.clip(), "Attack", "its touch plays Attack")
	assert_true(p != null)
	rig.free_all()


func test_the_shell_setup_loads_the_installed_pack_unless_one_is_injected() -> void:
	var sys := MonsterSystem.new()
	host.add_child(sys)
	assert_true(sys.art == null, "nothing loaded before setup: bare tests keep the proxies")
	sys.setup(GameContext.new())
	assert_true(sys.art != null and sys.art.root == ArtPack.install_dir().trim_suffix("/"), "setup loads the installed pack")
	var injected := standin_pack(["2"])
	var other := MonsterSystem.new()
	host.add_child(other)
	other.art = injected
	other.setup(GameContext.new())
	assert_eq(other.art, injected, "an injected pack is kept")


# =================================================================================================================
# Flash, fades, HP bar and the silhouette on skinned meshes
# =================================================================================================================

## Every model mesh (not a fill).
func _rig_meshes(v: MonsterVisual) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in v.model.find_children("*", "MeshInstance3D", true, false):
		if String(n.name) != MonsterVisual.SEE_THROUGH_NAME:
			out.append(n as MeshInstance3D)
	return out


func test_the_silhouette_fill_follows_the_skeleton() -> void:
	var v := _visual("2", standin_pack(["2"]))
	var meshes := _rig_meshes(v)
	assert_eq(meshes.size(), 2, "the rig's two meshes")
	assert_eq(v.see_through_fills().size(), 2, "one fill per mesh")
	for f in v.see_through_fills():
		var src := f.get_parent() as MeshInstance3D
		assert_true(src.skin != null, "%s is skinned" % src.name)
		assert_eq(f.skin, src.skin, "%s: the fill is bound with the mesh's skin" % src.name)
		var sk := f.get_node_or_null(f.skeleton)
		assert_true(sk is Skeleton3D and sk == src.get_node(src.skeleton), "%s: the fill is driven by the rig's skeleton" % src.name)
		assert_eq(f.mesh.get_surface_count(), 1, "%s: one draw call" % src.name)
		var arrays := f.mesh.surface_get_arrays(0)
		var verts := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		assert_true(arrays[Mesh.ARRAY_BONES] != null and (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() == verts * 4,
			"%s: the fill keeps every vertex's bones" % src.name)
		assert_true(arrays[Mesh.ARRAY_WEIGHTS] != null and (arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array).size() == verts * 4,
			"%s: and weights" % src.name)
		assert_true(f.mesh.get_aabb().is_equal_approx(src.mesh.get_aabb()), "%s: the fill covers the whole mesh" % src.name)


func test_flash_hp_bar_and_fades_work_on_the_skinned_meshes() -> void:
	var v := _visual("2", standin_pack(["2"]))
	var d := v.def
	var fit := d.sprite_size_m.y / STANDIN_H
	v.start_spawn(0.5)
	v.advance(0.25)
	assert_between(v.model.scale.y, fit * 0.3, fit * 0.7, "spawning: scaling in")
	v.advance(0.5)
	assert_true(v.model.scale.is_equal_approx(Vector3.ONE * fit), "spawned: full size, uniformly")
	v.on_hit(0.5)
	v.advance(0.01)
	for mi in _rig_meshes(v):
		assert_true(mi.material_overlay != null, "%s flashes" % mi.name)
	for f in v.see_through_fills():
		assert_true(f.material_overlay == null, "the fill never flashes")
	assert_true(v.hp_bar.visible, "the HP bar once damaged")
	v.advance(MonsterVisual.FLASH_S)
	for mi in _rig_meshes(v):
		assert_true(mi.material_overlay == null, "%s flash over" % mi.name)
	var faded := [false]
	v.faded_out.connect(func() -> void: faded[0] = true)
	v.start_death_fade(d.die_fade_s)
	assert_false(v.hp_bar.visible, "no bar while dying")
	v.advance(d.die_fade_s * 0.25)
	for mi in _rig_meshes(v):
		assert_near(mi.transparency, 0.0, 1e-6, "%s: opaque while the Death clip plays" % mi.name)
	v.advance(d.die_fade_s * 0.5)
	for mi in _rig_meshes(v):
		assert_between(mi.transparency, 0.05, 0.95, "%s: fading after it" % mi.name)
	assert_false(faded[0], "still fading")
	v.advance(d.die_fade_s * 0.25 + 0.01)
	assert_true(faded[0], "faded out at the canonical die time %.2f s" % d.die_fade_s)
	for mi in _rig_meshes(v):
		assert_near(mi.transparency, 1.0, 1e-6, "%s: gone" % mi.name)


# =================================================================================================================
# Clips replace the procedural motion
# =================================================================================================================

## Walks `v` for `seconds` in small steps and returns the most the model pivot moved off its rest (position, tilt,
## squash).
func _walk_motion(v: MonsterVisual, seconds: float) -> Vector3:
	(v.monster as FakeMonster).walking = true
	var most := Vector3.ZERO
	var t := 0.0
	while t < seconds:
		v.advance(0.02)
		t += 0.02
		most.x = maxf(most.x, absf(v.model.position.y))
		most.y = maxf(most.y, absf(v.model.rotation.x))
		most.z = maxf(most.z, absf(v.model.scale.y / v.model.scale.x - 1.0))
	return most


func test_a_rig_never_gets_the_procedural_bob_squash_flinch_or_sink() -> void:
	for id in ["2", "4"]:  # a crawler (squash) and a bouncer (bob)
		var v := _visual(id, standin_pack([id]))
		var walk := _walk_motion(v, 1.0)
		assert_near(walk.x, 0.0, 1e-6, "%s: no bob under the Walk clip" % id)
		assert_near(walk.z, 0.0, 1e-6, "%s: no squash under the Walk clip" % id)
		v.on_hit(0.5)
		var hit := _walk_motion(v, v.def.hit_s)
		assert_near(hit.y, 0.0, 1e-6, "%s: no flinch tilt under the Hit clip" % id)
		v.start_death_fade(v.def.die_fade_s)
		var death := _walk_motion(v, v.def.die_fade_s * 0.9)
		assert_near(death.x, 0.0, 1e-6, "%s: no sink under the Death clip" % id)


func test_without_a_rig_the_fallback_still_moves_procedurally() -> void:
	var crawler := _visual("2", null)
	assert_true(crawler.is_placeholder, "no pack, no library: the fallback body")
	assert_true(crawler.animation_player() == null and crawler.clip() == "", "no clips")
	assert_true(_walk_motion(crawler, 1.0).z > 0.02, "a crawler squashes as it walks")
	var bouncer := _visual("4", null)
	assert_true(_walk_motion(bouncer, 1.0).x > 0.01, "a bouncer bobs as it walks")
	bouncer.on_hit(0.5)
	bouncer.advance(0.02)
	assert_true(absf(bouncer.model.rotation.x) > 0.05, "and flinches when hit")


func test_a_pack_without_the_species_keeps_the_proxy_path() -> void:
	var v := _visual("4", standin_pack(["2"]))
	assert_true(v.is_placeholder, "the pack has no Shroom here: the fallback (no library in this test)")
	assert_eq(v.model_source, "", "not from the pack")
	var none := _visual("2", ArtPack.load_from("res://no_such_pack"))
	assert_true(none.is_placeholder and none.animation_player() == null, "no pack installed: as before")


# =================================================================================================================
# The real pack (bash scripts/art_pack.sh fetch; SKIP without it)
# =================================================================================================================

## Canonical monster id -> the pack's model (asset_index.json canonical_monsters).
const PACK_MODELS := {"1": "TutorialJrSentinel.glb", "2": "Snail.glb", "3": "BlueSnail.glb", "4": "Shroom.glb",
	"5": "RedSnail.glb", "9": "OrangeMushroom.glb"}


func _installed(test: String) -> ArtPack:
	var art := ArtPack.load_installed()
	if art.present():
		return art
	print("SKIP %s: no art pack installed (bash scripts/art_pack.sh fetch)" % test)
	return null


func test_real_pack_every_species_uses_its_model_at_its_sprite_height_unless_capped() -> void:
	var art := _installed("test_real_pack_every_species_uses_its_model_at_its_sprite_height_unless_capped")
	if art == null:
		return
	var ids := PackedStringArray(PACK_MODELS.keys())
	ids.sort()
	var canon := db().ids("monsters")
	canon.sort()
	assert_eq(ids, canon, "the six Maple Island species")
	for id in PACK_MODELS:
		var v := _visual(id, art)
		var d := v.def
		assert_eq(v.model_source.get_file(), PACK_MODELS[id], "%s %s: its pack model" % [id, d.name])
		assert_false(v.is_placeholder, "%s: not the fallback" % id)
		var box := _model_box(v)
		var width := maxf(box.size.x, box.size.z)
		if width < d.model_max_width_m() - 1e-3:
			assert_near(box.end.y, d.sprite_size_m.y, 0.01, "%s: top at the canonical sprite height %.2f m" % [id, d.sprite_size_m.y])
		else:
			assert_true(box.end.y < d.sprite_size_m.y, "%s: at its width cap, so below the sprite height" % id)
		assert_near(v.height_m, box.end.y, 0.01, "%s: the HP bar and numbers sit over it" % id)
		assert_true(box.position.y >= -0.01, "%s: never below its feet (base %.3f m)" % [id, box.position.y])
		print("  %s %-22s fitted %.3f m tall, footprint %.3f x %.3f m (touch width %.3f m, cap %.3f m)" % [id, d.name,
			box.end.y, box.size.x, box.size.z, d.touch_size_m.x, d.model_max_width_m()])


## Owner decision (#59/#64): with the real pack, no species' model is wider than 1.35x its touch zone (the playtest
## test_b_combat "monster visuals" limit). Before the cap the Tutorial Jr. Sentinel was 1.73 m across a 0.525 m zone.
func test_real_pack_every_species_model_fits_its_width_cap() -> void:
	var art := _installed("test_real_pack_every_species_model_fits_its_width_cap")
	if art == null:
		return
	for id in PACK_MODELS:
		var v := _visual(id, art)
		var box := _model_box(v)
		var limit := v.def.touch_size_m.x * 1.35
		assert_true(box.size.x <= limit + 1e-3 and box.size.z <= limit + 1e-3,
			"%s %s: %.3f x %.3f m within %.3f m (1.35x its %.3f m touch zone)" % [id, v.def.name, box.size.x, box.size.z,
				limit, v.def.touch_size_m.x])


func test_real_pack_each_state_selects_its_clip() -> void:
	var art := _installed("test_real_pack_each_state_selects_its_clip")
	if art == null:
		return
	for id in PACK_MODELS:
		var v := _visual(id, art)
		var ap := v.animation_player()
		assert_true(ap != null, "%s: the rig's AnimationPlayer" % id)
		if ap == null:
			continue
		assert_eq(ap.get_animation("Idle").loop_mode, Animation.LOOP_LINEAR, "%s: Idle loops" % id)
		assert_eq(ap.get_animation("Walk").loop_mode, Animation.LOOP_LINEAR, "%s: Walk loops" % id)
		for c in ["Attack", "Hit", "Death"]:
			assert_eq(ap.get_animation(c).loop_mode, Animation.LOOP_NONE, "%s: %s plays once" % [id, c])
		var mon := v.monster as FakeMonster
		v.advance(0.02)
		assert_eq(_playing(v), "Idle", "%s: standing" % id)
		mon.walking = true
		v.advance(0.02)
		assert_eq(_playing(v), "Walk", "%s: moving" % id)
		v.on_attack()
		v.advance(0.02)
		assert_eq(_playing(v), "Attack", "%s: touching" % id)
		v.on_hit(0.5)
		v.advance(0.02)
		assert_eq(_playing(v), "Hit", "%s: hit" % id)
		v.start_death_fade(v.def.die_fade_s)
		v.advance(0.02)
		assert_eq(_playing(v), "Death", "%s: dead" % id)


func test_real_pack_fills_follow_the_skeleton_and_every_surface_writes_the_stencil() -> void:
	var art := _installed("test_real_pack_fills_follow_the_skeleton_and_every_surface_writes_the_stencil")
	if art == null:
		return
	for id in PACK_MODELS:
		var v := _visual(id, art)
		var meshes := _rig_meshes(v)
		assert_eq(v.see_through_fills().size(), meshes.size(), "%s: a fill per mesh" % id)
		for mi in meshes:
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s) as BaseMaterial3D
				assert_true(m != null and m.stencil_mode == BaseMaterial3D.STENCIL_MODE_CUSTOM
					and m.stencil_reference == MonsterVisual.STENCIL_REF, "%s %s[%d] writes the monster stencil" % [id, mi.name, s])
		for f in v.see_through_fills():
			var src := f.get_parent() as MeshInstance3D
			assert_true(f.skin == src.skin and f.get_node_or_null(f.skeleton) is Skeleton3D,
				"%s %s: the fill is skinned to the rig" % [id, src.name])
