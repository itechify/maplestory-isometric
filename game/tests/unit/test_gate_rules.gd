extends TestCase
## The walk-through gate rule (MAP_ARCHITECTURE.md section 4.4 "Gates"), pure: GateDef.step() arms on an inward
## crossing inside the gate's box (also mid-jump), commits on the first grounded tick after hit-stun with the feet
## inside, disarms when the player walks back out past disarm_back, and never arms outside its box. Sizes come from
## portal_adaptations.json gates.

var sizes: Dictionary = {}


func before_each() -> void:
	sizes = MapDefinitions.build(db()).tuning.portal_section("gates")


## A gate on the plane z = 0 leading into +z (lateral along x), ground at y = 0.
func gate() -> GateDef:
	return GateDef.make("T_test", "B", "A", Vector3.ZERO, Vector3(0, 0, 1), sizes)


func test_sizes_come_from_the_data() -> void:
	for key in ["half_width_m", "height_m", "below_m", "disarm_back_m", "teleport_step_m", "reason"]:
		assert_true(sizes.has(key), "portal_adaptations.json gates.%s" % key)
	var g := gate()
	assert_near(g.half_width, float(sizes.half_width_m), 1e-6, "half width")
	assert_near(g.height, float(sizes.height_m), 1e-6, "height")
	assert_eq(g.lateral, Vector3(1, 0, 0), "lateral = UP x normal")
	assert_eq(g.key(), "T_test>B", "key")


func test_walking_in_commits_on_the_first_grounded_tick() -> void:
	var g := gate()
	assert_false(g.step(Vector3(0, 0, -0.5), Vector3(0, 0, -0.1), true, false), "outside: nothing")
	assert_false(g.armed, "not armed before the crossing")
	assert_true(g.step(Vector3(0, 0, -0.1), Vector3(0, 0, 0.1), true, false), "a grounded crossing commits at once")
	assert_false(g.armed, "disarmed by the commit")


func test_a_crossing_mid_jump_arms_and_commits_on_landing() -> void:
	var g := gate()
	assert_false(g.step(Vector3(0, 1.0, -0.1), Vector3(0, 1.1, 0.1), false, false), "airborne: no commit")
	assert_true(g.armed, "armed mid-jump")
	assert_false(g.step(Vector3(0, 1.1, 0.1), Vector3(0, 0.5, 0.3), false, false), "still airborne")
	assert_true(g.step(Vector3(0, 0.5, 0.3), Vector3(0, 0.0, 0.4), true, false), "lands inside: commit")


func test_hit_stun_delays_the_commit_until_it_ends() -> void:
	var g := gate()
	assert_false(g.step(Vector3(0, 0, -0.1), Vector3(0, 0, 0.2), true, true), "knocked across: no commit in hit-stun")
	assert_true(g.armed, "armed under knockback")
	assert_false(g.step(Vector3(0, 0, 0.2), Vector3(0, 0, 0.3), true, true), "still in hit-stun")
	assert_true(g.step(Vector3(0, 0, 0.3), Vector3(0, 0, 0.3), true, false), "the first grounded tick after hit-stun commits")


func test_walking_back_out_disarms() -> void:
	var g := gate()
	g.step(Vector3(0, 1.0, -0.1), Vector3(0, 1.0, 0.1), false, false)
	assert_true(g.armed, "armed")
	g.step(Vector3(0, 1.0, 0.1), Vector3(0, 0.5, -0.1), false, false)
	assert_true(g.armed, "just behind the plane: still armed (within disarm_back)")
	g.step(Vector3(0, 0.5, -0.1), Vector3(0, 0.2, -g.disarm_back - 0.05), false, false)
	assert_false(g.armed, "past disarm_back: disarmed")
	assert_false(g.step(Vector3(0, 0.2, -0.3), Vector3(0, 0, -0.4), true, false), "landing outside commits nothing")


func test_no_arming_outside_the_box_or_from_inside() -> void:
	var g := gate()
	g.step(Vector3(g.half_width + 0.2, 0, -0.1), Vector3(g.half_width + 0.2, 0, 0.1), false, false)
	assert_false(g.armed, "beside the corridor")
	g.step(Vector3(0, g.height + 0.2, -0.1), Vector3(0, g.height + 0.2, 0.1), false, false)
	assert_false(g.armed, "above the box")
	g.step(Vector3(0, -g.below - 0.2, -0.1), Vector3(0, -g.below - 0.2, 0.1), false, false)
	assert_false(g.armed, "below the box")
	assert_false(g.step(Vector3(0, 0, 0.5), Vector3(0, 0, 0.6), true, false), "moving about inside never commits by itself")
	assert_false(g.armed, "no crossing, no arming")


func test_signed_distance_and_box() -> void:
	var g := GateDef.make("T", "B", "A", Vector3(10, 2, 5), Vector3(1, 0, 0), sizes)
	assert_near(g.signed_distance(Vector3(12, 2, 5)), 2.0, 1e-6, "+normal side is inside")
	assert_near(g.signed_distance(Vector3(9, 7, 0)), -1.0, 1e-6, "height and lateral do not count")
	assert_true(g.in_box(Vector3(10.5, 3.0, 5 + g.half_width - 0.01)), "inside the box")
	assert_false(g.in_box(Vector3(10.5, 2.0 + g.height + 0.01, 5)), "too high")
