extends TestCase
## Hit areas a player can see and trust (brief: 'Monster Hitboxes'): the attack FX lay the real canonical attack box
## on the ground, isometric depth included (AttackFx.last_reach); a monster's contact zone is exactly its canonical
## touch zone, never an invisible bubble larger than the body you see; and each proxy model stands on its feet with a
## footprint close to that touch zone. Canonical reach numbers are never changed here.

var host: Node3D


func before_each() -> void:
	host = Node3D.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(host)


func after_each() -> void:
	host.free()


## The footprint's extent along the facing (forward) and across it (lateral), in meters, from its mesh corners.
static func _extent(fx: AttackFx, feet: Vector3, facing: Vector3) -> Dictionary:
	var mi := fx.last_reach
	var f := Vector3(facing.x, 0, facing.z).normalized()
	var lat := Vector3.UP.cross(f)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, INF * -1)
	var aabb := mi.mesh.get_aabb()
	for i in 8:
		var p := mi.global_transform * aabb.get_endpoint(i) - feet
		lo = Vector2(minf(lo.x, p.dot(f)), minf(lo.y, p.dot(lat)))
		hi = Vector2(maxf(hi.x, p.dot(f)), maxf(hi.y, p.dot(lat)))
	return {"near": lo.x, "far": hi.x, "lat_lo": lo.y, "lat_hi": hi.y, "y": (mi.global_transform * aabb.get_center()).y - feet.y}


func test_the_swing_shows_the_canonical_box_with_its_isometric_depth() -> void:
	var fx := AttackFx.new()
	host.add_child(fx)
	var depth := CombatReach.attack_box_depth_px(db())
	fx.depth_px = depth
	var sword := WeaponProfile.for_weapon_id("541", db())
	var feet := Vector3(3, 1, -2)
	for facing in [Vector3.RIGHT, Vector3(1, 0, 1).normalized(), Vector3.BACK]:
		for pres in ["swingO1", "swingO2", "swingO3", "stabO1", "stabO2"]:
			var box := CombatReach.attack_box_px(sword, pres, true, 1)
			if pres.begins_with("swing"):
				fx.swing(feet, facing, box)
			else:
				fx.stab(feet, facing, box)
			var e := _extent(fx, feet, facing)
			assert_near(float(e.near), WorldScale.actor(box.position.x), 1e-3, "%s near edge" % pres)
			assert_near(float(e.far), WorldScale.actor(box.end.x), 1e-3, "%s far edge" % pres)
			assert_near(float(e.lat_lo), -WorldScale.actor(depth * 0.5), 1e-3, "%s depth, one side" % pres)
			assert_near(float(e.lat_hi), WorldScale.actor(depth * 0.5), 1e-3, "%s depth, other side" % pres)
			assert_true(float(e.y) > 0.0 and float(e.y) < 0.1, "%s lies on the ground at the feet" % pres)
	# swingO2 [-73, -50, 5, 17] reaches 5 px behind the feet, and its footprint shows it.
	fx.swing(feet, Vector3.RIGHT, CombatReach.attack_box_px(sword, "swingO2", true, 1))
	assert_near(float(_extent(fx, feet, Vector3.RIGHT).near), -WorldScale.actor(5.0), 1e-3, "starts 5 px behind")
	var punch := CombatReach.attack_box_px(WeaponProfile.bare_hands(db()), "stabO1", true, 1)
	fx.punch(feet, Vector3.RIGHT, punch)
	assert_near(float(_extent(fx, feet, Vector3.RIGHT).far), WorldScale.actor(punch.end.x), 1e-3, "a punch shows its reach too")
	fx.advance(1.0)
	assert_eq(fx.live_count(), 0, "short-lived")


func test_the_footprint_is_what_the_hit_test_hits() -> void:
	var fx := AttackFx.new()
	host.add_child(fx)
	fx.depth_px = CombatReach.attack_box_depth_px(db())
	var sword := WeaponProfile.for_weapon_id("541", db())
	var box := CombatReach.attack_box_px(sword, "swingO1", true, 1)
	fx.swing(Vector3.ZERO, Vector3.RIGHT, box)
	var e := _extent(fx, Vector3.ZERO, Vector3.RIGHT)
	var tz := MonsterCombatStats.from_id("2", db()).touch_zone_px
	var k := WorldScale.actor(1.0)
	# A Snail whose touch zone just overlaps the footprint's side edge is hit; one just past it is not.
	var inside := (float(e.lat_hi) + WorldScale.actor(tz.x * 0.5) - 0.01) / k
	var outside := (float(e.lat_hi) + WorldScale.actor(tz.x * 0.5) + 0.01) / k
	var mid := (float(e.near) + float(e.far)) * 0.5 / k
	assert_true(MeleeQuery.attack_hits(box, fx.depth_px, Vector3(mid, 0, inside), tz, tz.x), "touching the drawn depth band: hit")
	assert_false(MeleeQuery.attack_hits(box, fx.depth_px, Vector3(mid, 0, outside), tz, tz.x), "past it: no hit")


func test_the_monster_system_gives_the_fx_the_isometric_depth() -> void:
	var rig := MonsterTestRig.create(db())
	assert_near(rig.system.attack_fx.depth_px, CombatReach.attack_box_depth_px(db()), 1e-9, "combat.json isometric_reach")
	assert_true(rig.system.attack_fx.depth_px > 0.0, "a depth to draw")
	rig.free_all()


## No invisible contact bubble: a monster touches the player exactly when its canonical touch zone (width x height,
## depth = width: combat.json isometric_reach) overlaps the player's body, nowhere else.
func test_contact_is_the_canonical_touch_zone_and_nothing_more() -> void:
	var r := 0.3
	var h := 1.5
	for id in ["1", "2", "3", "4", "5", "9"]:
		var d := MonsterDef.from_id(id, db())
		var tz := d.stats.touch_zone_px
		assert_near(d.touch_size_m.x, WorldScale.actor(tz.x), 1e-9, "%s width = canonical" % id)
		assert_near(d.touch_size_m.y, WorldScale.actor(tz.y), 1e-9, "%s height = canonical" % id)
		assert_near(d.touch_size_m.z, WorldScale.actor(tz.x), 1e-9, "%s depth = its width" % id)
		var reach := d.touch_size_m.x * 0.5 + r
		for dir in [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]:
			assert_true(MeleeQuery.touch_overlaps(Vector3.ZERO, Vector3.RIGHT, d.touch_size_m, dir * (reach - 0.01), r, h),
				"%s touches at w/2 + body radius" % id)
			assert_false(MeleeQuery.touch_overlaps(Vector3.ZERO, Vector3.RIGHT, d.touch_size_m, dir * (reach + 0.01), r, h),
				"%s never beyond it" % id)
		assert_false(MeleeQuery.touch_overlaps(Vector3.ZERO, Vector3.RIGHT, d.touch_size_m, Vector3(0, d.touch_size_m.y + 0.01, 0), r, h),
			"%s never above its height" % id)


## Each proxy (fitted to its canonical sprite height, as in the game) stands on its feet and covers its touch zone
## along its facing without being much larger: the body you see is the body that hits you.
func test_every_proxy_stands_on_its_feet_and_matches_its_touch_zone() -> void:
	var lib := ProxyLibrary.load_from()
	if not lib.has("Mob_Snail"):
		print("SKIP test_every_proxy_stands_on_its_feet_and_matches_its_touch_zone: assets/world/_library.glb not present (INCLUDE_WORLD=1)")
		return
	for id in ["1", "2", "3", "4", "5", "9"]:
		var d := MonsterDef.from_id(id, db())
		assert_true(lib.has(d.model), "%s: %s is in the library" % [id, d.model])
		var v := MonsterVisual.new()
		host.add_child(v)
		v.build(d, lib)
		assert_false(v.is_placeholder, "%s uses its proxy" % id)
		var box := AABB()
		var first := true
		for n in v.model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if String(mi.name) == MonsterVisual.SEE_THROUGH_NAME or mi.mesh == null:
				continue
			var local := v.global_transform.affine_inverse() * mi.global_transform
			var b := local * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var w := d.touch_size_m.x
		assert_near(box.size.y, d.sprite_size_m.y, 0.02, "%s fitted to the canonical sprite height" % id)
		assert_true(absf(box.position.y) <= 0.03, "%s stands on its feet (base %.3f m)" % [id, box.position.y])
		# Facing +Z: the model's length along it covers the touch width, and neither horizontal extent is far past it.
		assert_true(box.size.z >= w * 0.95, "%s covers its touch zone along its facing (%.2f vs %.2f m)" % [id, box.size.z, w])
		assert_true(box.size.z <= w * 1.25 and box.size.x <= w * 1.25,
			"%s footprint %.2f x %.2f m within 1.25x its %.2f m touch zone" % [id, box.size.x, box.size.z, w])
	lib.free_templates()


func parity_keys() -> Dictionary:
	return {
		"test_the_swing_shows_the_canonical_box_with_its_isometric_depth": ["mechanic:basic-attack-hitboxes", "mechanic:isometric-reach-depth"],
		"test_the_footprint_is_what_the_hit_test_hits": ["mechanic:isometric-reach-depth"],
		"test_the_monster_system_gives_the_fx_the_isometric_depth": ["mechanic:isometric-reach-depth"],
		"test_contact_is_the_canonical_touch_zone_and_nothing_more": ["mechanic:monster-touch-damage"],
		"test_every_proxy_stands_on_its_feet_and_matches_its_touch_zone": ["mechanic:monster-hitbox-visual-fit", "monster:1", "monster:2",
			"monster:3", "monster:4", "monster:5", "monster:9"],
	}
