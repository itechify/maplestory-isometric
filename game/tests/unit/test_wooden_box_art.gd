extends TestCase
## The Wooden Box with the art pack (#65): BreakableSystem hands its ArtPack to every box it realizes, and the box
## shows the pack's rigged WoodenBox (looked up by canonical breakable id) instead of the procedural crate. Idle loops
## while it stands, Hit plays on each hit that does not break it, and the breaking hit detaches the model as a
## presentation-only node that plays Break once and frees itself, while the gameplay state (broken, no target, drops,
## respawn clock) flips at the same moment as without the pack. Without the pack the procedural crate stays.
## Tests that need the pack print SKIP and return when it is not installed (NO_ART_PACK=1).

const BOX := "0000001"

var bus: Node = null
var sys: BreakableSystem = null
var st: MapInstanceState = null
var def: MapDefinition = null
var now: float = 0.0
var art: ArtPack = null
var loot: Array = []


func before_each() -> void:
	art = ArtPack.load_installed()
	bus = load("res://scripts/autoload/events.gd").new()
	loot.clear()
	bus.loot_dropped.connect(func(drops: Array, _pos: Vector3, _map_id: String) -> void: loot.append(drops))
	def = _synthetic(2)
	now = 10.0
	var r := RandomNumberGenerator.new()
	r.seed = 1
	st = MapInstanceState.fresh(def, SpawnModel.from_db(db()), r, now)
	sys = BreakableSystem.new()
	sys.db = db()
	sys.bus = bus
	sys.ground = GroundQuery.new()
	var r2 := RandomNumberGenerator.new()
	r2.seed = 5
	sys.rng = r2
	sys.state_provider = func() -> MapInstanceState: return st
	sys.def_provider = func(map_id: String) -> MapDefinition: return def if map_id == def.map_id else null
	sys.clock_provider = func() -> float: return now
	sys.character_provider = func() -> CharacterState: return CharacterState.new()
	sys.roller = func(_o: String, _d: ContentDB, _r: RandomNumberGenerator, _c: Dictionary) -> Array:
		return [{"kind": "item", "item_id": "441", "qty": 1}]


func after_each() -> void:
	if is_instance_valid(sys):
		sys.free()
	bus.free()


## Realizes the boxes with `pack` as the system's art (null = no art).
func _realize(pack: ArtPack) -> void:
	sys.art = pack
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(sys)
	sys.tick(0.0)


func _synthetic(n: int) -> MapDefinition:
	var d := MapDefinition.new()
	d.map_id = "999999065"
	var reactors: Array = []
	for i in n:
		reactors.append({"id": BOX, "name": "Wooden Box", "x_px": i * 100, "y_px": 0, "respawn_s": 60})
	d.canonical = {"reactors": reactors}
	d.footprint_layout = PackedVector2Array([Vector2(0, 0), Vector2(30, 0), Vector2(30, 30), Vector2(0, 30)])
	d.footprint = PackedVector2Array([Vector2(-1, -1), Vector2(31, -1), Vector2(31, 31), Vector2(-1, 31)])
	d.y_min = -1.0
	d.y_max = 5.0
	d.player_spawns = [Transform3D(Basis.IDENTITY, Vector3(2, 0, 2))] as Array[Transform3D]
	return d


func _no_pack(test: String) -> bool:
	if art.present():
		return false
	print("SKIP %s: the art pack is not installed (bash scripts/art_pack.sh fetch)" % test)
	return true


func test_a_standing_box_shows_the_pack_model_playing_idle() -> void:
	if _no_pack("test_a_standing_box_shows_the_pack_model_playing_idle"):
		return
	_realize(art)
	var box := sys.live_boxes()[0]
	assert_true(box.rig != null, "the box shows the pack's model")
	assert_true(box.rig.get_parent() == box.model, "under the box's Model (hidden, scaled and cued with it)")
	assert_eq(box.clip(), "Idle", "Idle plays while it stands")
	box.advance(2.5)
	assert_eq(box.clip(), "Idle", "and loops")


func test_each_hit_that_does_not_break_the_box_plays_hit_then_idle_again() -> void:
	if _no_pack("test_each_hit_that_does_not_break_the_box_plays_hit_then_idle_again"):
		return
	_realize(art)
	var box := sys.live_boxes()[0]
	var ap := box.rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	sys.land_hit(box)
	assert_eq(box.clip(), "Hit", "hit 1 plays Hit")
	box.advance(0.5)
	sys.land_hit(box)
	assert_eq(box.clip(), "Hit", "hit 2 plays Hit")
	assert_near(ap.current_animation_position, 0.0, 1e-4, "from its start, also when the last Hit is still playing")
	box.advance(1.2)
	assert_eq(box.clip(), "Idle", "Idle again once Hit ends")
	sys.land_hit(box)
	assert_eq(box.clip(), "Hit", "hit 3 plays Hit")
	assert_eq(box.hits_left(), 1, "one hit left")


## The orchestrator's ruling on #65: gameplay removal (no target, drops, the respawn clock, the hidden model) happens
## at the breaking hit exactly as without the pack; the model that plays Break is a detached, presentation-only node.
func test_the_breaking_hit_flips_the_state_at_once_and_a_detached_model_plays_break_then_frees_itself() -> void:
	if _no_pack("test_the_breaking_hit_flips_the_state_at_once_and_a_detached_model_plays_break_then_frees_itself"):
		return
	_realize(art)
	var box := sys.live_boxes()[0]
	var standing := box.rig
	var at := standing.global_transform
	var n := BreakableRules.hits_to_break(BOX, db())
	for k in n - 1:
		sys.land_hit(box)
	var r := sys.land_hit(box)
	# Before any frame: everything gameplay sees has already changed.
	assert_true(bool(r.broke), "the fourth hit breaks it")
	assert_true(box.is_broken() and box.hits_left() == 0, "broken at once")
	assert_false(box.model.visible, "the box's model hides at once, as without the pack")
	assert_false(box.cues_drawn().rim or box.cues_drawn().marker, "no cue")
	assert_eq(sys.attack_candidates().size(), 1, "no attack target at once")
	assert_eq(loot.size(), 1, "the drops are announced at once")
	assert_false(st.is_breakable_intact(0), "the respawn clock runs from the breaking hit")
	# The model that breaks: detached from the hidden Model, where it stood, playing Break once.
	var breaking := box.breaking_rigs()
	assert_eq(breaking.size(), 1, "one breaking model")
	var b: Node3D = breaking[0]
	assert_true(b == standing, "the standing model is the one that breaks")
	assert_false(box.model.is_ancestor_of(b), "outside the hidden Model")
	assert_true(b.is_visible_in_tree(), "and drawn")
	assert_true(b.global_transform.is_equal_approx(at), "where it stood")
	var ap := b.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_eq(String(ap.current_animation), "Break", "plays Break")
	assert_true(box.rig != null and box.rig != b and box.model.is_ancestor_of(box.rig), "a fresh model waits in the hidden Model")
	box.advance(0.5)
	assert_eq(String(ap.current_animation), "Break", "still breaking half way")
	box.advance(0.6)
	assert_eq(box.breaking_rigs().size(), 0, "gone once Break has played")
	assert_true(b.is_queued_for_deletion() or not is_instance_valid(b), "it frees itself")


func test_the_box_comes_back_after_respawn_s_in_its_spot_playing_idle() -> void:
	if _no_pack("test_the_box_comes_back_after_respawn_s_in_its_spot_playing_idle"):
		return
	_realize(art)
	var box := sys.live_boxes()[1]
	var spot := box.global_transform
	var fit := box.rig.transform
	var back: Array = []
	sys.box_respawned.connect(func(b: WoodenBox) -> void: back.append(b.index()))
	for k in BreakableRules.hits_to_break(BOX, db()):
		sys.land_hit(box)
	box.advance(1.5)
	now += 60.0 - 0.5
	sys.tick(0.0)
	assert_true(box.is_broken() and not box.model.visible, "still broken 0.5 s before respawn_s")
	now += 0.5
	sys.tick(0.0)
	assert_eq(back, [1], "back after exactly respawn_s")
	assert_false(box.is_broken(), "intact")
	assert_true(box.model.visible, "shown")
	assert_eq(box.clip(), "Idle", "playing Idle")
	assert_true(box.global_transform.is_equal_approx(spot), "in its original spot")
	assert_true(box.rig.transform.is_equal_approx(fit), "at the same fit")
	assert_eq(box.breaking_rigs().size(), 0, "nothing left of the break")
	box.advance(WoodenBox.RESPAWN_S)
	assert_true(box.model.scale.is_equal_approx(Vector3.ONE), "grown back")
	sys.land_hit(box)
	assert_eq(box.clip(), "Hit", "and takes hits again")


## The ticket's acceptance test: the clip sequence across four hits and a respawn.
func test_the_clip_sequence_across_four_hits_and_a_respawn() -> void:
	if _no_pack("test_the_clip_sequence_across_four_hits_and_a_respawn"):
		return
	_realize(art)
	var box := sys.live_boxes()[0]
	var seen: Array = [box.clip()]
	for k in BreakableRules.hits_to_break(BOX, db()):
		sys.land_hit(box)
		var breaking := box.breaking_rigs()
		if box.is_broken() and breaking.size() == 1:
			seen.append(String((breaking[0].find_child("AnimationPlayer", true, false) as AnimationPlayer).current_animation))
		else:
			seen.append(box.clip())
		box.advance(0.9)  # a swing's lockout is 0.81 s at Normal 6: the next hit lands while Hit still plays
	box.advance(1.0)
	now += float(st.breakables[0].respawn_s)
	sys.tick(0.0)
	seen.append(box.clip())
	assert_eq(seen, ["Idle", "Hit", "Hit", "Hit", "Break", "Idle"], "Idle, Hit x3, Break, Idle after the respawn")
	assert_eq(box.breaking_rigs().size(), 0, "the Break model is gone")


## A box shown at once (a re-realized map) stands in Idle whatever its standing model was playing.
func test_sync_shows_an_intact_box_in_idle() -> void:
	if _no_pack("test_sync_shows_an_intact_box_in_idle"):
		return
	_realize(art)
	var box := sys.live_boxes()[0]
	sys.land_hit(box)
	assert_eq(box.clip(), "Hit", "mid-Hit")
	box.sync(1, false)
	assert_eq(box.clip(), "Idle", "sync shows it in Idle")


## Without the pack (or a pack without the model) the box keeps the procedural crate and its plank burst.
func test_without_the_pack_the_procedural_crate_stays() -> void:
	_realize(ArtPack.load_from("res://_no_art_pack_here"))
	var box := sys.live_boxes()[0]
	assert_true(box.rig == null, "no pack model")
	assert_eq(box.clip(), "", "no clip")
	var body := box.model.get_child(0) as MeshInstance3D
	assert_true(body != null and body.mesh is BoxMesh, "the crate's plank body")
	for k in BreakableRules.hits_to_break(BOX, db()):
		sys.land_hit(box)
	assert_true(box.is_broken() and not box.model.visible, "breaks and hides as before")
	assert_eq(box.breaking_rigs().size(), 0, "nothing plays Break")
	assert_true(box.piece_count() > 1, "the planks fly")
