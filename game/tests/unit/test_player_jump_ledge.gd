extends TestCase
## A jump pressed while walking into a face (#16), with the real PlayerController: every ledge up to the documented
## reach (jump apex + step_up = 1.35 m at Jump 100) is landed on, from a standing start to full walk speed and at 0,
## 30 and 60 degrees off the face normal, against a sharp box edge, and up to 1.3 m against the rounded and
## overhanging lips of the exported route ledges (1.15-1.21 m); the jump keeps its canonical apex, the reach does not
## grow, and a steep slope is not climbed.

## The ledge face is the plane x = FACE_X; the ledge runs from it along +X.
const FACE_X := 2.0
## Approach angles off the face normal (degrees).
const ANGLES := [0.0, 30.0, 60.0]
## Ticks the direction is held at the face before the jump press: 0 (direction and jump pressed on the same tick), 1
## and 2 (1 and 2 m/s: ground_accel reaches full walk in 3 ticks). WALK_IN walks in from 1.2 m back at full walk speed
## and presses jump on the tick the face stops the body.
const WALK_IN := -1
const STARTS := [0, 1, 2, WALK_IN]

var w: PlayerTestWorld
var model: MovementModel


func before_each() -> void:
	w = PlayerTestWorld.create(db())
	model = MovementModel.from_db(db())


func after_each() -> void:
	w.free_all()


func _fresh() -> void:
	w.free_all()
	w = PlayerTestWorld.create(db())


## A floor at y = 0 and a ledge of height `h` whose outermost face is the plane x = FACE_X. `lip`:
##   &"box"       a sharp edge;
##   &"chamfer"   a 45 degree chamfer 0.15 m deep along the top edge, so walkable ground starts 0.15 m behind the
##                face (the rounded lips of 000000042's tiers: 56 degree normals there, walkable from 0.10-0.15 m in);
##   &"overhang"  the top 0.35 m, chamfered the same way, overhangs a lower face 0.25 m behind it (000001020's ledge).
func _ledge(h: float, lip: StringName = &"box") -> void:
	w.add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	if lip == &"box":
		w.add_box(Vector3(FACE_X + 3.0, h * 0.5, 0), Vector3(6, h, 20))
		return
	var c := 0.15
	var slab := 0.35 if lip == &"overhang" else h
	w.add_box(Vector3(FACE_X + c + 3.0, h - slab * 0.5, 0), Vector3(6, slab, 20))  # behind the chamfer
	w.add_box(Vector3(FACE_X + c * 0.5, h - slab + (slab - c) * 0.5, 0), Vector3(c, slab - c, 20))  # under it
	if lip == &"overhang":
		w.add_box(Vector3(FACE_X + 0.25 + 3.0, (h - slab) * 0.5, 0), Vector3(6, h - slab, 20))  # the lower face
	# The chamfer: a square prism turned 45 degrees about Z, centred on the inner corner (FACE_X + c, h - c); its
	# upper-left side runs from (FACE_X, h - c) to (FACE_X + c, h), the rest lies inside the two boxes above.
	w.add_box(Vector3(FACE_X + c, h - c, 0), Vector3(c * sqrt(2.0), c * sqrt(2.0), 20), Vector3(0, 0, 45))


## A jump pressed into the face of an `h` m ledge along `angle_deg` off its normal (see STARTS for `start`), the
## direction held at full strength (as on the keyboard) until the first landing. Returns {landed_y (NAN if none),
## peak (the highest feet height while airborne)}.
func _pressed_jump(h: float, start: int, angle_deg: float, lip: StringName = &"box") -> Dictionary:
	_ledge(h, lip)
	var a := deg_to_rad(angle_deg)
	var dir := Vector3(cos(a), 0.0, sin(a))
	var at_face := FACE_X - model.body_radius - 0.01
	var p: PlayerController
	if start == WALK_IN:
		p = w.spawn_player(Vector3(at_face - 1.2 * cos(a), 0, -1.2 * sin(a)))
		w.bot.world_dir = dir
		var n := w.run_until(func() -> bool: return p.global_position.x > at_face - 0.02, 60)
		assert_true(n > 0, "%.2f m, %d deg: walked into the face" % [h, angle_deg])
	else:
		p = w.spawn_player(Vector3(at_face, 0, 0))
		w.run(5)
		w.bot.world_dir = dir
		w.run(start)
	w.bot.press(&"jump")
	var lands: Array = []
	p.landed.connect(func(_s: float) -> void: lands.append(p.global_position.y))
	var peak := -INF
	for i in 90:
		w.player.step(PlayerTestWorld.TICK)
		if not lands.is_empty():
			break
		if not p.is_grounded():
			peak = maxf(peak, p.global_position.y)
	return {"landed_y": float(lands[0]) if not lands.is_empty() else NAN, "peak": peak}


## Every (height, start, angle) case of a pressed jump that does not land on the ledge, as failure lines.
func _misses(heights: Array, lip: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for h: float in heights:
		for start: int in STARTS:
			for angle: float in ANGLES:
				_fresh()
				var r := _pressed_jump(h, start, angle, lip)
				if not absf(float(r["landed_y"]) - h) < 0.02:
					out.append("%s %.2f m, %s, %d deg: first landing at %.2f m" % [lip, h,
						"walked in" if start == WALK_IN else "held %d tick(s)" % start, angle, r["landed_y"]])
	return out


func test_a_pressed_jump_lands_on_every_box_ledge_within_the_reach() -> void:
	assert_near(model.jump_apex + model.step_up, 1.35, 0.005, "the documented reach")
	var misses := _misses([0.5, 0.9, 1.2, 1.3, 1.35], &"box")
	assert_true(misses.is_empty(), "%d missed:\n    %s" % [misses.size(), "\n    ".join(misses)])


func test_a_pressed_jump_clears_a_rounded_lip() -> void:
	var misses := _misses([0.9, 1.15, 1.2, 1.3], &"chamfer")
	assert_true(misses.is_empty(), "%d missed:\n    %s" % [misses.size(), "\n    ".join(misses)])


func test_a_pressed_jump_clears_an_overhanging_lip() -> void:
	var misses := _misses([1.15, 1.2, 1.3], &"overhang")
	assert_true(misses.is_empty(), "%d missed:\n    %s" % [misses.size(), "\n    ".join(misses)])


func test_a_pressed_jump_keeps_the_canonical_apex() -> void:
	# Against a face too tall to land on, the feet still peak at the canonical apex (0.90 m at Jump 100): the face
	# neither cuts the jump short nor lifts it.
	for lip: StringName in [&"box", &"chamfer"]:
		for start: int in STARTS:
			for angle: float in ANGLES:
				_fresh()
				var r := _pressed_jump(3.0, start, angle, lip)
				assert_near(float(r["peak"]), model.jump_apex, 0.01, "%s, start %d, %d deg: apex" % [lip, start, angle])


func test_the_reach_does_not_grow() -> void:
	# Above apex + step_up (and the feet rays' headroom) a pressed jump never lands on the ledge.
	for lip: StringName in [&"box", &"chamfer"]:
		for start: int in STARTS:
			for angle: float in ANGLES:
				_fresh()
				var r := _pressed_jump(1.5, start, angle, lip)
				assert_near(float(r["landed_y"]), 0.0, 0.02, "%s 1.5 m, start %d, %d deg: back on the floor" % [lip, start, angle])


func test_a_jump_into_a_steep_slope_does_not_climb_it() -> void:
	# A 45 degree slope is not walkable (38 degrees is the limit): a jump held into it peaks at the apex, never stands
	# on it and comes back down to the floor.
	for angle: float in ANGLES:
		_fresh()
		w.add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
		w.add_ramp(FACE_X, 0.0, 0.0, 45.0, 4.0, 20.0)
		var a := deg_to_rad(angle)
		var p := w.spawn_player(Vector3(FACE_X - 1.0, 0, 0))
		w.bot.world_dir = Vector3(cos(a), 0.0, sin(a))
		w.run(40)
		var y0 := p.global_position.y
		w.bot.press(&"jump")
		var peak := -INF
		var steep_ground := 0
		for i in 90:
			w.player.step(PlayerTestWorld.TICK)
			peak = maxf(peak, p.global_position.y)
			if p.is_grounded() and p.global_position.y > y0 + 0.05:
				steep_ground += 1
		assert_true(peak <= y0 + model.jump_apex + 0.01, "%d deg: peak %.3f m above the take-off" % [angle, peak - y0])
		assert_eq(steep_ground, 0, "%d deg: never grounded on the slope" % angle)
		assert_true(p.global_position.y < y0 + 0.05, "%d deg: back on the floor (%.2f m)" % [angle, p.global_position.y - y0])
