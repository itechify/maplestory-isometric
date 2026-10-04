extends TestCase
## The authored scenes other systems instance (scenes/actors/player.tscn, scenes/actors/camera_rig.tscn): collision
## layers, the body capsule and Hurtbox built from movement.json, the duck-typed contracts the world runtime, MapSession
## and combat call, and camera rig edge cases (bounds before the first snap, a freed target).

const PLAYER_SCENE := "res://scenes/actors/player.tscn"
const RIG_SCENE := "res://scenes/actors/camera_rig.tscn"

var w: PlayerTestWorld


func before_each() -> void:
	w = PlayerTestWorld.create(db())
	w.add_box(Vector3(0, -0.5, 0), Vector3(100, 1, 100))


func after_each() -> void:
	w.free_all()


## player.tscn instanced like the game does, without autoloads and without the (presentation-only) visual.
func _scene_player() -> PlayerController:
	var p := (load(PLAYER_SCENE) as PackedScene).instantiate() as PlayerController
	p.use_autoloads = false
	p.model = MovementModel.from_db(db())
	var vis := p.get_node_or_null(^"Visual")
	if vis != null:
		p.remove_child(vis)
		vis.free()
	p.set_input_source(w.bot)
	w.add_node(p)
	w.player = p
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0)))
	return p


func test_player_scene_layers_and_body() -> void:
	var p := _scene_player()
	var m := p.model
	assert_eq(p.collision_layer, WorldLayers.PLAYER, "body on the player layer")
	assert_eq(p.collision_mask & WorldLayers.PLAYER_MASK, WorldLayers.PLAYER_MASK, "collides with walkable, blocking, containment, scenery")
	assert_eq(p.collision_mask & WorldLayers.MONSTERS, 0, "walks through monsters (classic)")
	var body := p.get_node(^"CollisionShape3D") as CollisionShape3D
	var cap := body.shape as CapsuleShape3D
	assert_true(cap != null, "capsule body")
	assert_near(cap.radius, m.body_radius, 1e-6, "radius from movement.json")
	assert_near(body.position.y - cap.height * 0.5, m.step_up, 1e-4, "capsule starts at step_up (the floating step band)")
	assert_near(body.position.y + cap.height * 0.5, m.body_height, 1e-4, "capsule ends at body_height")
	var hurt := p.get_node(^"Hurtbox") as Area3D
	assert_true(hurt != null, "Hurtbox Area3D")
	assert_eq(hurt.collision_layer, WorldLayers.PLAYER, "Hurtbox on the player layer (monster touch zones see it)")
	assert_true(hurt.monitorable, "Hurtbox is detectable")
	var hs := (hurt.get_node(^"CollisionShape3D") as CollisionShape3D)
	var hcap := hs.shape as CapsuleShape3D
	assert_near(hs.position.y + hcap.height * 0.5, m.body_height, 1e-3, "Hurtbox covers the full body height")
	assert_near(hs.position.y - hcap.height * 0.5, 0.0, 1e-3, "from the feet")
	assert_true(p.is_grounded(), "the scene's body settles on the floor")
	w.bot.world_dir = Vector3(1, 0, 0)
	w.run(30)
	assert_near(p.actual_velocity.length(), m.walk_speed, 0.01, "the scene's body walks at the canonical speed")
	assert_true(p.is_grounded(), "and stays grounded")


func test_player_scene_exposes_the_contracts_other_systems_call() -> void:
	var p := _scene_player()
	# World runtime (WORLD_RUNTIME.md "Player"), MapSession, FallRecovery, GateMonitor, PortalInteractor.
	for method in ["teleport", "is_on_floor", "set_input_enabled", "set_input_source"]:
		assert_true(p.has_method(method), "world contract: %s()" % method)
	for prop in ["input_source", "safe_ground", "safe_ground_filter", "in_hitstun", "velocity"]:
		assert_true(prop in p, "world contract: %s" % prop)
	# Combat (COMBAT.md) and the death flow.
	for method in ["apply_knockback", "apply_knockback_from_point", "set_invulnerable", "is_invulnerable", "die", "revive", "is_dead"]:
		assert_true(p.has_method(method), "combat/death contract: %s()" % method)
	# Camera rig.
	for method in ["follow_anchor", "set_view_axes"]:
		assert_true(p.has_method(method), "camera contract: %s()" % method)
	assert_true(p.safe_ground is SafeGround, "safe_ground is a SafeGround")
	assert_true(p.input_source is InputSource, "input_source is an InputSource")


func test_camera_rig_scene_and_mapsession_contract() -> void:
	var rig := (load(RIG_SCENE) as PackedScene).instantiate() as CameraRig
	rig.auto_aspect = false
	w.add_node(rig)
	rig.set_process(false)
	rig.set_physics_process(false)
	assert_eq(rig.camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "orthographic")
	assert_eq(rig.camera.keep_aspect, Camera3D.KEEP_HEIGHT, "KEEP_HEIGHT")
	assert_true(rig.fader != null, "occlusion fader child")
	assert_true(rig.has_method("set_bounds") and rig.has_method("snap"), "MapSession.attach_camera duck type")
	var cfg: Dictionary = db().miso_table("camera")
	assert_near(rig.camera.near, float(cfg["near_m"]), 1e-6, "near plane from camera.json")
	# MapSession calls set_bounds(PackedVector2Array, frame width, blend) right after attach, before any snap: the
	# size must apply even with a blend requested (nothing to blend from yet).
	var width := 30.0
	rig.set_bounds(PackedVector2Array([Vector2(-50, -50), Vector2(50, -50), Vector2(50, 50), Vector2(-50, 50)]), width, 0.35)
	rig.update_camera(1.0 / 60.0)
	assert_near(rig.ortho_size, rig.view_size_for_frame_width(width), 1e-4, "size applied before the first snap")
	assert_near(rig.camera.size, rig.ortho_size, 1e-4, "on the Camera3D")


func test_camera_survives_a_freed_target() -> void:
	var p := w.spawn_player(Vector3(0, 0, 0))
	var rig := CameraRig.new()
	rig.auto_aspect = false
	w.add_node(rig)
	rig.set_process(false)
	rig.set_physics_process(false)
	rig.set_target(p)
	rig.update_camera(1.0 / 60.0)
	var focus := rig.focus_point()
	w.player = null
	p.get_parent().remove_child(p)
	p.free()
	rig.update_camera(1.0 / 60.0)
	rig.snap()
	assert_near(rig.focus_point().distance_to(focus), 0.0, 1e-4, "holds the framing when the followed node is freed")
