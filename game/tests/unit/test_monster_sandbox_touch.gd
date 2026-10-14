extends TestCase
## The monster sandbox's touch-zone overlay (--showcase --touch): a box the size of MonsterDef.touch_size_m standing on
## the monster's feet, with the touch width along its facing (local +Z of a showcase spawn), as MeleeQuery tests it.

const SANDBOX := preload("res://scenes/sandbox/monster_sandbox.gd")


func test_the_box_is_the_touch_zone_standing_on_the_feet() -> void:
	var def := MonsterDef.from_id("1", db())  # the Tutorial Jr. Sentinel
	var mi: MeshInstance3D = SANDBOX.touch_zone_box(def)
	var size := (mi.mesh as BoxMesh).size
	assert_near(size.z, def.touch_size_m.x, 1e-6, "width along the facing")
	assert_near(size.y, def.touch_size_m.y, 1e-6, "height")
	assert_near(size.x, def.touch_size_m.z, 1e-6, "depth across")
	assert_near(mi.position.y, def.touch_size_m.y * 0.5, 1e-6, "bottom on the feet")
	assert_true(def.touch_size_m.y > 0.0 and def.touch_size_m.x > 0.0, "the Sentinel has a touch zone")
	mi.free()
