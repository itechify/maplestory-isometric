extends PlaytestScenario
## player_rig (#63): gameplay-scale screenshots of the rigged Beginner in the real game (run --windowed; headless
## only checks the clips): idle, walking, mid-jump, climbing a rope, attacking with each of the three starter weapons,
## seated on The Green Relaxer, hurt (blinking), behind a wall with the X-ray silhouette and outline, and dead. Each
## stop checks the clip the rig plays. Setup steps (equipping the next weapon, sitting, the knockback, a teleport
## under the canopy) go through code, not input: the scenario is a camera, not a gameplay test.
##
##   ISOLATE=rig bash scripts/playtest.sh player_rig --windowed        # the male Beginner
##   QUEST=female ISOLATE=rig bash scripts/playtest.sh player_rig --windowed   # the female Beginner

const START_MAP := "000000001"
## Dangerous Forest: canopies that hide the player (test_feel_camera's canopy stop).
const CANOPY_MAP := "000001002"
const CHAIR := "522"


func description() -> String:
	return "the rigged Beginner in the real game: walk, jump, rope, three weapons, sit, hurt, behind a wall, dead"


func max_seconds() -> float:
	return 1200.0


func run(d: PlaytestDriver) -> void:
	var gender := "female" if OS.get_environment("QUEST") == "female" else "male"
	var ng: Dictionary = await d.new_game("Rigger", gender, "541")
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	var p := d.player()
	var vis := p.get_node(^"Visual") as PlayerVisual
	if not d.check("the player is the rigged Beginner", vis.rigged(), "preset %s" % vis.preset):
		return
	d.note("PRESET %s" % vis.preset)
	await d.wait(1.0)
	_clip(d, vis, &"idle", "standing")
	await _shot(d, "idle")

	# Held in the background so the shot lands mid-stride.
	d.press(&"move_right", 1.2)
	await d.wait(0.8)
	_clip(d, vis, &"walk", "walking")
	await _shot(d, "walk")
	await d.wait(1.0)

	await d.tap(&"jump")
	await d.wait(0.2)
	_clip(d, vis, &"jump", "mid-jump")
	await _shot(d, "jump")
	await d.wait_idle(5.0)
	await d.wait(0.5)

	for weapon_id: String in CharacterFactory.creation_weapon_ids(d.db()):
		d.character().equipment.force_equip("weapon", weapon_id, d.db())
		await d.wait(0.6)
		await d.tap(&"attack")
		await d.wait(0.2)
		_clip(d, vis, &"attack", "attacking with %s" % weapon_id)
		await _shot(d, "attack_%s" % weapon_id)
		await d.wait(1.0)
	d.character().equipment.force_equip("weapon", "541", d.db())

	d.check("sits on The Green Relaxer", p.sit(CHAIR))
	await d.wait(1.6)
	_clip(d, vis, &"sit", "seated")
	await _shot(d, "sit_green_relaxer")
	p.stand_up(&"move")
	await d.wait(0.6)

	p.apply_knockback_from_point(p.global_position + p.facing * 0.5)
	await d.wait(0.12)
	_clip(d, vis, &"hit", "hurt")
	await _shot(d, "hurt_a")
	await d.wait(0.07)
	await _shot(d, "hurt_b")
	await d.wait_until(func() -> bool: return not p.is_invulnerable(), 5.0)

	await _rope(d, p, vis)
	await _behind_wall(d, p, vis, false)
	await _behind_wall(d, p, vis, true)

	await d.wait_idle(10.0)
	d.game().damage_player(d.character().hp + 1000)
	await d.wait(2.0)
	d.soft_check("dead", p.is_dead())
	_clip(d, vis, &"death", "dead")
	await _shot(d, "dead")


func _clip(d: PlaytestDriver, vis: PlayerVisual, want: StringName, what: String) -> void:
	d.check("%s plays %s" % [what, want], vis.current_clip() == want, "playing %s" % vis.current_clip())


## The gameplay-scale screenshot, plus a 3x crop around the player (<name>_zoom.png) to read the pose.
func _shot(d: PlaytestDriver, shot_name: String) -> void:
	var path: String = await d.screenshot(shot_name)
	var cam := d.get_viewport().get_camera_3d()
	if path == "" or cam == null:
		return
	var img := Image.load_from_file(path)
	var at := Vector2i(cam.unproject_position(d.player().global_position + Vector3.UP * 0.75))
	var r := Rect2i(at - Vector2i(150, 110), Vector2i(300, 220)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	var crop := img.get_region(r)
	crop.resize(r.size.x * 3, r.size.y * 3, Image.INTERPOLATE_LANCZOS)
	crop.save_png(path.get_basename() + "_zoom.png")


## The first map with a rope: warp there, stand at its foot (a setup teleport: some ropes stand by a gate), hold Up.
func _rope(d: PlaytestDriver, p: PlayerController, vis: PlayerVisual) -> void:
	for map_id: String in ["000000030", "000000001", "000001000", "000001002", "000001003"]:
		await d.console("warp " + map_id)
		await d.wait_idle(10.0)
		p = d.player()
		vis = p.get_node(^"Visual") as PlayerVisual
		var slug := d.world().defs.get_def(d.current_map()).slug
		for c: ClimbableDef in p.climbables:
			# The player knows every climbable of the island; a rope of this map keeps the camera on it.
			if c.kind != &"rope" or not c.has_foot_ground or not String(c.name).begins_with(slug):
				continue
			d.note("ROPE %s in %s" % [c.name, map_id])
			var face := Vector3(c.facing.x, 0.0, c.facing.z).normalized()
			p.teleport(Transform3D(Basis(Vector3.UP.cross(face).normalized(), Vector3.UP, face), c.foot_ground - face * 0.3))
			(d.ctx().camera as CameraRig).snap()
			await d.wait(0.5)
			d.press(&"portal_enter", 1.6)
			await d.wait(1.2)
			if not p.is_climbing():
				continue
			d.check("climbing the rope", true, "%s in %s" % [c.name, map_id])
			_clip(d, vis, &"climb", "on the rope")
			await _shot(d, "climb_rope")
			await d.wait(0.6)
			await d.tap(&"jump")
			await d.wait_idle(10.0)
			return
	d.check("climbing a rope", false, "no rope could be climbed in the maps tried")


## Puts the player (a setup teleport) on the ground just behind a building as the camera sees it, then shows the
## silhouette standing and walking (it follows the walk clip's pose). `terrain` false: a faded building covers the
## player (the outline ring, the body through the dither); true: the ground in front hides the body (the X-ray fill).
func _behind_wall(d: PlaytestDriver, p: PlayerController, vis: PlayerVisual, terrain: bool) -> void:
	var label := "behind_terrain" if terrain else "behind_wall"
	for map_id: String in ["000000010", "000001010", "000000020"]:
		await d.console("warp " + map_id)
		await d.wait_idle(10.0)
		p = d.player()
		vis = p.get_node(^"Visual") as PlayerVisual
		var rig := d.ctx().camera as CameraRig
		var houses: Array = []
		for n in d.world().find_children("*", "MeshInstance3D", true, false):
			var extras: Variant = n.get_meta(&"extras", null)
			if extras is Dictionary and String((extras as Dictionary).get("category", "")) == "Architecture":
				var box: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
				if box.size.y > (2.5 if terrain else 4.0) and box.get_center().distance_to(p.global_position) < 80.0:
					houses.append(box)
		houses.sort_custom(func(a: AABB, b: AABB) -> bool:
			return a.get_center().distance_to(p.global_position) < b.get_center().distance_to(p.global_position))
		var space := p.get_world_3d().direct_space_state
		for box: AABB in houses.slice(0, 16):
			var behind := box.get_center() + rig.ground_forward * (maxf(box.size.x, box.size.z) * 0.5 + 0.6)
			var q := PhysicsRayQueryParameters3D.create(Vector3(behind.x, box.position.y + 1.2, behind.z),
				Vector3(behind.x, box.position.y - 3.0, behind.z), WorldLayers.WALKABLE)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			p.teleport(Transform3D(Basis.IDENTITY, hit["position"]))
			rig.snap()
			await d.wait(0.8)
			var hidden_by := rig.terrain_hides(p.global_position) if terrain else rig.fader.player_covered \
				and not rig.terrain_hides(p.global_position)
			if not (p.is_grounded() and hidden_by and vis.see_through_amount > 0.99):
				continue
			d.note("%s in %s at %s" % [label.to_upper(), map_id, p.global_position])
			await _shot(d, label)
			d.press(&"move_left", 0.9)
			await d.wait(0.45)
			_clip(d, vis, &"walk", "walking " + label.replace("_", " "))
			await _shot(d, label + "_walking")
			await d.wait(0.6)
			return
	d.soft_check("found a spot " + label.replace("_", " "), false)
