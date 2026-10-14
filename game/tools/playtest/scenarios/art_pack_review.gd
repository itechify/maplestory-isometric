extends PlaytestScenario
## art_pack_review: before/after screenshots of an art-pack bump in the real game (#61, Jarvis's v1.1 correction).
## Screenshots need --windowed; each shot's region of interest (screen rect, px) is a note, for cropping. A new Beginner
## is given Basic Archer Gloves (1439), Brown Duo (1440) and Amethyst Earrings (900) (console give, setup only) -> the
## inventory's Equip tab at its real slot size -> a warp to Amherst (setup), a walk up to the nearest Wooden Box and
## its hit presentation (WoodenBox.show_hit: the pack's Hit clip, or the procedural wobble without the pack) shot at
## HIT_FRAMES_S after the hit (the player beside it on the camera's right), the box keeping all its hits -> a warp to the Tomato Field (setup) and a walk to the
## open strip in front of its west beds, shot at the gameplay camera.

const ITEMS := ["1439", "1440", "900"]
const WEAPON := "541"
const AMHERST := "000001010"
const TOMATO_FIELD := "000001021"
## Map-local (Godot axes: x east, y up, z = -Blender y): the strip in front of the west beds' ridges (m1020001).
const TOMATO_SPOT := Vector3(19.0, 0.0, -1.2)
## Seconds after the hit at which the box is shot (one hit per shot, so each frame is exact).
const HIT_FRAMES_S := [0.0, 0.05, 0.1, 0.15, 0.2, 0.3, 0.45]
## How far in front of the box (m) the player stands.
const BOX_STAND_M := 1.4


func description() -> String:
	return "art pack review shots: inventory icons 1439/1440/900, a Wooden Box's Hit, the Tomato Field's beds"


func max_seconds() -> float:
	return 400.0


func run(d: PlaytestDriver) -> void:
	d.note("art pack installed: %s" % ArtPack.shared().present())
	var ng: Dictionary = await d.new_game("Review", "male", WEAPON, {"str": 9})
	if not d.check("new game through the title and creation screens", bool(ng["ok"]), str(ng)):
		return
	for id: String in ITEMS:
		await d.console("give %s 1" % id)
	await _inventory(d)
	await _box(d)
	await _tomatoes(d)


func _inventory(d: PlaytestDriver) -> void:
	if not d.check("the inventory window opens (I)", await d.open_window("inventory")):
		return
	var inv := (d.windows() as MisoWindowsRoot).inventory
	inv.select_tab("equip")
	await d.frames(4)
	var ids := inv.visible_item_ids()
	var rects: PackedStringArray = []
	for id: String in ITEMS:
		var k := ids.find(id)
		if d.check("item %s is in the Equip tab" % id, k >= 0, ", ".join(ids)) and k < inv.slots.size():
			rects.append("%s %s" % [id, _rect(inv.slots[k].get_global_rect())])
	d.note("inventory slots: " + "; ".join(rects))
	await d.screenshot("inventory_equip")
	await d.close_window("inventory")


func _box(d: PlaytestDriver) -> void:
	await d.console("warp " + AMHERST)
	await d.wait_idle(20.0)
	var box := _nearest_box(d)
	if not d.check("a Wooden Box stands in Amherst", box != null):
		return
	# Beside the box on the camera's right, so the player never stands between the camera and the box.
	var cam := d.get_viewport().get_camera_3d()
	var right := cam.global_transform.basis.x if cam != null else Vector3.RIGHT
	right.y = 0.0
	var spot := box.global_position + (right.normalized() if right.length() > 0.01 else Vector3.RIGHT) * BOX_STAND_M
	await d.walk_to(spot, {"max_s": 30.0, "within_m": 0.4})
	d.input.release_movement()
	await d.wait(1.0)
	var left := int(box.call("hits_left"))
	cam = d.get_viewport().get_camera_3d()
	var c: Vector3 = box.call("center")
	d.note("box %s at screen %s" % [box.call("placement_key"), str(cam.unproject_position(c)) if cam != null else "?"])
	for t: float in HIT_FRAMES_S:
		box.call("show_hit", left)
		if t > 0.0:
			await d.wait(t)
		await d.screenshot("box_hit_%03dms" % int(round(t * 1000.0)))
		await d.wait(1.2)
	d.check("the box keeps its hits (presentation only)", int(box.call("hits_left")) == left)


func _tomatoes(d: PlaytestDriver) -> void:
	await d.console("warp " + TOMATO_FIELD)
	await d.wait_idle(20.0)
	var r: Dictionary = await d.walk_to({"local": TOMATO_SPOT}, {"max_s": 40.0, "within_m": 0.5})
	d.soft_check("walked to the front of the west beds", bool(r["ok"]), str(r.get("issues", "")))
	d.input.release_movement()
	await d.wait(1.5)
	d.note("player at %s" % str(d.player().global_position))
	await d.screenshot("tomato_field")


func _nearest_box(d: PlaytestDriver) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for b: Node in d.get_tree().get_nodes_in_group(&"miso_breakables"):
		if String(b.call("map_id")) != d.current_map() or bool(b.call("is_broken")):
			continue
		var dd := (b as Node3D).global_position.distance_to(d.player().global_position)
		if dd < best_d:
			best_d = dd
			best = b as Node3D
	return best


static func _rect(r: Rect2) -> String:
	return "(%d,%d %dx%d)" % [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]
