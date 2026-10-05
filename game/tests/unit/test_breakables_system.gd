extends TestCase
## BreakableSystem and WoodenBox without the island (contract C8): a synthetic map on the flat GroundQuery, a private
## event bus, an injected clock, character and roller. Boxes are realized from the live MapInstanceState (one per
## placement, in the group the playtest kit reads), the real PlayerCombat's swing counts one hit on the box its
## canonical hit box reaches (and none behind the player), the fourth landed hit breaks the box and rolls its drops
## with the quest context of contract C2 at the box's position, the box comes back after its placement's respawn_s,
## and a new instance (map change, reload_map) re-realizes the boxes. The gated table itself is checked through the
## real DropRoller with a C1-shaped fixture once the roller takes the C2 context (SKIP before the drops package lands).

const BOX := "0000001"
const FIXTURE := "res://tests/data/breakables/drops_0000001_v2.json"


func parity_keys() -> Dictionary:
	return {
		"test_four_landed_hits_break_the_box_and_roll_its_drops_with_the_quest_context": ["breakable:0000001",
			"mechanic:breakable-hit-break-respawn", "mechanic:breakable-drop-roll"],
		"test_the_players_swing_hits_the_box_in_front_and_not_behind": ["mechanic:breakable-hit-break-respawn"],
		"test_a_broken_box_comes_back_after_its_respawn_s": ["mechanic:breakable-hit-break-respawn"],
		"test_gated_drops_through_the_real_roller": ["mechanic:breakable-drop-roll", "drop:0000001/441",
			"drop:0000001/442", "quest:1012"],
	}


class FakePlayer:
	extends Node3D
	var facing := Vector3.RIGHT


var bus: Node = null
var sys: BreakableSystem = null
var st: MapInstanceState = null
var def: MapDefinition = null
var now: float = 0.0
var character: CharacterState = null
var rolls: Array = []
var loot: Array = []


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	bus.loot_dropped.connect(func(drops: Array, pos: Vector3, map_id: String) -> void: loot.append([drops, pos, map_id]))
	def = synthetic(3)
	now = 10.0
	st = MapInstanceState.fresh(def, SpawnModel.from_db(db()), _rng(1), now)
	character = CharacterState.new()
	rolls.clear()
	loot.clear()
	sys = BreakableSystem.new()
	sys.db = db()
	sys.bus = bus
	sys.ground = GroundQuery.new()
	sys.rng = _rng(5)
	sys.state_provider = func() -> MapInstanceState: return st
	sys.def_provider = func(map_id: String) -> MapDefinition: return def if map_id == def.map_id else null
	sys.clock_provider = func() -> float: return now
	sys.character_provider = func() -> CharacterState: return character
	sys.roller = func(owner_id: String, d: ContentDB, r: RandomNumberGenerator, c: Dictionary) -> Array:
		rolls.append([owner_id, d, r, c])
		return [{"kind": "item", "item_id": "441", "qty": 1}]
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(sys)
	sys.tick(0.0)


func after_each() -> void:
	if is_instance_valid(sys):
		sys.free()
	bus.free()


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## A 30 x 30 m map with `n` Wooden Box placements (respawn 60 + 30 i s) and its arrival at (2, 0, 2).
func synthetic(n: int) -> MapDefinition:
	var d := MapDefinition.new()
	d.map_id = "999999001"
	var reactors: Array = []
	for i in n:
		reactors.append({"id": BOX, "name": "Wooden Box", "x_px": i * 100, "y_px": 0, "respawn_s": 60 + 30 * i})
	d.canonical = {"reactors": reactors}
	d.footprint_layout = PackedVector2Array([Vector2(0, 0), Vector2(30, 0), Vector2(30, 30), Vector2(0, 30)])
	d.footprint = PackedVector2Array([Vector2(-1, -1), Vector2(31, -1), Vector2(31, 31), Vector2(-1, 31)])
	d.y_min = -1.0
	d.y_max = 5.0
	d.player_spawns = [Transform3D(Basis.IDENTITY, Vector3(2, 0, 2))] as Array[Transform3D]
	return d


func hits() -> int:
	return BreakableRules.hits_to_break(BOX, db())


func test_boxes_follow_the_live_state() -> void:
	var boxes := sys.live_boxes()
	assert_eq(boxes.size(), 3, "one box per placement")
	var tree := Engine.get_main_loop() as SceneTree
	for i in boxes.size():
		var b := boxes[i]
		assert_true(b.is_in_group(&"miso_breakables"), "box %d in the playtest kit's group" % i)
		assert_eq(b.placement_key(), "%s:%d" % [def.map_id, i], "placement key")
		assert_eq(b.index(), i, "index")
		assert_false(b.is_broken(), "intact")
		assert_eq(b.hits_left(), hits(), "hits left")
		assert_true(b.global_position.distance_to(sys.plans[def.map_id][i].position()) < 1e-4, "stands at its placement")
	assert_eq(tree.get_nodes_in_group(&"miso_breakables").size(), 3, "the group holds exactly the live boxes")
	# A partly hit and a broken box come back as they were when the map is realized again.
	st.hit_breakable(0, now, hits())
	for k in hits():
		st.hit_breakable(1, now, hits())
	sys.realize(st)
	boxes = sys.live_boxes()
	assert_eq(boxes[0].hits_left(), hits() - 1, "partial hits shown")
	assert_true(boxes[1].is_broken(), "broken shown")
	# A new instance (a map change, or MapSession.reload_map, which emits nothing): all intact again.
	st = MapInstanceState.fresh(def, SpawnModel.from_db(db()), _rng(2), now)
	sys.tick(0.0)
	for b in sys.live_boxes():
		assert_false(b.is_broken() or b.hits_left() != hits(), "fresh instance: box %d intact" % b.index())
	st = null
	sys.tick(0.0)
	assert_eq(sys.live_boxes().size(), 0, "no instance, no boxes")
	await_free()
	assert_eq(tree.get_nodes_in_group(&"miso_breakables").size(), 0, "released boxes leave the group")


## Frees queued nodes (released boxes are queue_free'd).
func await_free() -> void:
	for n in (Engine.get_main_loop() as SceneTree).get_nodes_in_group(&"miso_breakables"):
		if n.is_queued_for_deletion():
			n.free()


func test_four_landed_hits_break_the_box_and_roll_its_drops_with_the_quest_context() -> void:
	character.quests.start("1012", 0.0)
	var box := sys.live_boxes()[2]
	var seen: Array = []
	sys.box_hit.connect(func(b: WoodenBox, left: int) -> void: seen.append([b.index(), left]))
	for k in hits() - 1:
		var r := sys.land_hit(box)
		assert_true(bool(r.counted) and not bool(r.broke), "hit %d counts" % (k + 1))
	assert_false(box.is_broken(), "standing after %d hits" % (hits() - 1))
	assert_eq(box.hits_left(), 1, "one hit left")
	assert_eq(rolls.size(), 0, "nothing rolled before the break")
	var last := sys.land_hit(box)
	assert_true(bool(last.broke), "the fourth hit breaks it")
	assert_true(box.is_broken() and box.hits_left() == 0, "the box shows broken")
	assert_false(st.is_breakable_intact(2), "the state says broken")
	assert_eq(rolls.size(), 1, "one roll per break")
	assert_eq(String(rolls[0][0]), BOX, "the Wooden Box's table")
	assert_eq(rolls[0][3], {"quests_in_progress": PackedStringArray(["1012"])}, "contract C2 roll context")
	assert_eq(loot.size(), 1, "Events.loot_dropped once")
	assert_eq(loot[0][0], [{"kind": "item", "item_id": "441", "qty": 1}], "the rolled drops")
	assert_true((loot[0][1] as Vector3).distance_to(box.global_position) < 1e-4, "at the box")
	assert_eq(String(loot[0][2]), def.map_id, "in the live map")
	assert_eq(seen, [[2, 3], [2, 2], [2, 1], [2, 0]], "box_hit with hits left")
	assert_false(bool(sys.land_hit(box).counted), "a broken box takes no hit")
	assert_eq(rolls.size(), 1, "and rolls nothing more")
	assert_eq(sys.boxes_broken, 1, "counter")
	assert_true(box.piece_count() > 0, "break FX")
	box.advance(5.0)
	assert_eq(box.piece_count(), 0, "the FX end")
	# No quest in progress: the context says so (the roller then skips gated entries).
	var other := sys.live_boxes()[0]
	character.quests.forfeit("1012")
	for k in hits():
		sys.land_hit(other)
	assert_eq(rolls[1][3], {"quests_in_progress": PackedStringArray()}, "no quest, empty context")


func test_the_players_swing_hits_the_box_in_front_and_not_behind() -> void:
	var player := FakePlayer.new()
	var pc := PlayerCombat.new()
	pc.name = "PlayerCombat"
	pc.autostep = false
	pc.db = db()
	pc.rng = _rng(9)
	pc.character = CharacterFactory.create(CharacterFactory.default_params(db()), db()).character
	player.add_child(pc)
	sys.add_child(player)
	sys.attach_player(player)
	sys.tick(0.0)
	assert_true(sys.player_combat == pc, "listens to the player's PlayerCombat")
	var box := sys.live_boxes()[0]
	var px := BreakableRules.touch_px(db())
	var depth := CombatReach.attack_box_depth_px(db())
	# Behind the player: never hit.
	player.global_position = box.global_position + Vector3(0.7, 0, 0)
	player.facing = Vector3.RIGHT
	for k in 12:
		pc.attack()
	assert_eq(st.breakable_hits(0), 0, "a swing facing away never reaches the box")
	# In front, 0.7 m away: every swing whose canonical box overlaps the box's body counts, until it breaks.
	player.global_position = box.global_position - Vector3(0.7, 0, 0)
	var expected := 0
	var swings := 0
	while not box.is_broken() and swings < 60:
		pc.attack()
		swings += 1
		var rel := MeleeQuery.local_px(player.global_position, player.facing, box.global_position)
		if MeleeQuery.attack_hits(pc.last_box_px, depth, rel, px, px.x):
			expected += 1
		assert_eq(mini(expected, hits()), hits() - box.hits_left() if not box.is_broken() else hits(), "swing %d" % swings)
	assert_true(box.is_broken(), "broken by %d swings (%d reached)" % [swings, expected])
	assert_eq(expected, hits(), "exactly %d landed swings broke it" % hits())
	assert_eq(sys.hits_landed, hits(), "hits counted")
	player.free()


func test_a_broken_box_comes_back_after_its_respawn_s() -> void:
	var box := sys.live_boxes()[1]
	var back: Array = []
	sys.box_respawned.connect(func(b: WoodenBox) -> void: back.append(b.index()))
	for k in hits():
		sys.land_hit(box)
	assert_true(box.is_broken(), "broken at %.0f" % now)
	var respawn := float(st.breakables[1].respawn_s)
	assert_eq(respawn, 90.0, "placement 1 of the synthetic map: 90 s")
	now += respawn - 0.5
	sys.tick(0.0)
	assert_true(box.is_broken(), "still broken 0.5 s before")
	now += 0.5
	sys.tick(0.0)
	assert_false(box.is_broken(), "back after exactly respawn_s")
	assert_eq(box.hits_left(), hits(), "with no hits")
	assert_eq(back, [1], "box_respawned once")
	assert_true(bool(sys.land_hit(box).counted), "and takes hits again")


func test_attack_candidates_are_the_intact_boxes() -> void:
	var c := sys.attack_candidates()
	assert_eq(c.size(), 3, "three intact boxes")
	for e: Dictionary in c:
		assert_eq(String(e.kind), "breakable", "kind")
		assert_eq(e.touch_px, BreakableRules.touch_px(db()), "body from breakables.json")
	for k in hits():
		sys.land_hit(sys.live_boxes()[0])
	assert_eq(sys.attack_candidates().size(), 2, "a broken box is no target")
	# A box reached by another attack source (receive_hit, the Monster signature) counts one hit.
	assert_true(sys.live_boxes()[2].receive_hit(null, null), "receive_hit counts")
	assert_eq(st.breakable_hits(2), 1, "one hit")


func test_gated_drops_through_the_real_roller() -> void:
	if not BreakableRules.roller_takes_context():
		print("SKIP test_gated_drops_through_the_real_roller: DropRoller.roll takes no roll context yet (contract C2 lands with the drops package)")
		return
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(fixture is Dictionary, "fixture %s" % FIXTURE)
	var c := ContentDB.new()
	c.canonical = db().canonical.duplicate(true)
	c.miso = db().miso.duplicate(true)
	c.loaded = true
	c.canonical["drops"][BOX] = fixture
	var r := _rng(77)
	var with_quest := {"quests_in_progress": PackedStringArray(["1012"])}
	var without := {"quests_in_progress": PackedStringArray()}
	var on := {}
	var off := {}
	var n := 400
	for k in n:
		for pair in [[on, with_quest], [off, without]]:
			var tally: Dictionary = pair[0]
			for d: Dictionary in BreakableRules.roll_drops(BOX, c, r, pair[1]):
				assert_ne(String(d.get("kind", "")), "mesos", "a Wooden Box never drops mesos")
				var id := String(d.get("item_id", ""))
				tally[id] = int(tally.get(id, 0)) + 1
	assert_eq(int(on.get("441", 0)), n, "Rusty Screw every break while 1012 is in progress")
	assert_eq(int(on.get("442", 0)), n, "Old Wooden Board every break while 1012 is in progress")
	assert_eq(int(off.get("441", 0)) + int(off.get("442", 0)), 0, "gated to 1012: none without it")
	assert_eq(int(on.get("237", 0)) + int(off.get("237", 0)), 0, "Egg (unresolved) never drops")
	var apples := float(int(on.get("236", 0)) + int(off.get("236", 0))) / float(2 * n)
	assert_between(apples, 0.18, 0.32, "Apple near its 0.25 (seeded sanity check, not the source)")
