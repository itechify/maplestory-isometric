extends TestCase
## Ground drops with the art pack (#70): every canonical item and every meso tier shows its pack model, resting on the
## ground by the pack's godot_validation.json ground offsets (weapons are grip-centred), sized alike across item kinds.
## Needs the pack installed (bash scripts/art_pack.sh fetch); the pack tests print SKIP without it. The procedural
## drops stay pinned by test_loot_visuals.gd, and the fallback tests here run with and without the pack.

## One amount per meso tier of data/misostory/loot_visuals.json (bronze coin, gold coin, pile, bag).
const MESO_AMOUNTS := [7, 60, 500, 5000]

var _art: ArtPack = null


func before_each() -> void:
	_art = ArtPack.load_installed()


func _skip(test: String) -> bool:
	if _art.present():
		return false
	print("SKIP %s: no art pack installed (bash scripts/art_pack.sh fetch)" % test)
	return true


func _vis() -> LootVisuals:
	return LootVisuals.new(db(), _art)


## Every canonical item as a ground record, then one meso drop per tier.
func _drops() -> Array:
	var out: Array = []
	for id in db().ids("items"):
		out.append({"kind": "item", "item_id": String(id), "amount": 1})
	for amount in MESO_AMOUNTS:
		out.append({"kind": "mesos", "amount": amount, "mesos": amount})
	return out


func test_every_item_and_meso_tier_resolves_a_pack_model() -> void:
	if _skip("test_every_item_and_meso_tier_resolves_a_pack_model"):
		return
	assert_eq(db().ids("items").size(), 94, "the 94 canonical items")
	var v := _vis()
	for d: Dictionary in _drops():
		var m := v.build_drop_model(d)
		assert_true(LootVisuals.is_pack_model(m), "pack model for %s" % str(d))
		m.free()


## One meso model for every tier (the pack has no pile or bag): the bronze coin is the gold coin recoloured, and the
## pile and the bag are bigger coins. The recoloured material is shared, not one per drop.
func test_meso_tiers_differ_by_tint_then_size() -> void:
	if _skip("test_meso_tiers_differ_by_tint_then_size"):
		return
	var v := _vis()
	var bronze := v.build_drop_model({"kind": "mesos", "amount": 7})
	var bronze2 := v.build_drop_model({"kind": "mesos", "amount": 30})
	var gold := v.build_drop_model({"kind": "mesos", "amount": 60})
	assert_eq(_coin_colour(bronze), Color("#c98a3a"), "below 50 the coin is bronze")
	assert_ne(_coin_colour(gold), Color("#c98a3a"), "from 50 the coin keeps the pack's gold")
	assert_true(_coin_material(bronze) == _coin_material(bronze2), "bronze coins share one material")
	var sizes := []
	for amount in MESO_AMOUNTS:
		var m := v.build_drop_model({"kind": "mesos", "amount": amount})
		var box := ArtImport.visual_aabb(m)
		sizes.append(maxf(box.size.x, box.size.y))
		m.free()
	assert_near(sizes[0], sizes[1], 0.01, "bronze and gold coins are the same size")
	assert_true(sizes[2] > sizes[1] + 0.05 and sizes[3] > sizes[2] + 0.05, "the pile and the bag grow: %s" % str(sizes))
	for m in [bronze, bronze2, gold]:
		m.free()


## The coin's gold surface material as drawn (the tier's override, else the pack's).
func _coin_material(model: Node) -> Material:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_material(i).resource_name == "Gold":
				return mi.get_active_material(i)
	return null


func _coin_colour(model: Node) -> Color:
	var m := _coin_material(model)
	return (m as BaseMaterial3D).albedo_color if m is BaseMaterial3D else Color.TRANSPARENT


## Without the pack, or for an ID whose model the pack does not have imported, drops keep their procedural shapes.
## (Runs with and without the installed pack.)
func test_drops_without_a_pack_model_stay_procedural() -> void:
	var packs := {
		"no pack": ArtPack.load_from("res://tests/data/no_such_pack"),
		"a pack that maps the IDs but has no models": ArtPack.load_from("res://tests/data/art_pack"),
	}
	for label: String in packs:
		var v := LootVisuals.new(db(), packs[label])
		for d: Dictionary in [{"kind": "item", "item_id": "541", "amount": 1}, {"kind": "item", "item_id": "348", "amount": 1},
				{"kind": "mesos", "amount": 7}, {"kind": "mesos", "amount": 5000}]:
			var m := v.build_drop_model(d)
			assert_false(LootVisuals.is_pack_model(m), "%s: %s is procedural" % [label, str(d)])
			var meshes := m.find_children("*", "MeshInstance3D", true, false)
			assert_true(meshes.size() >= 1 and (meshes[0] as MeshInstance3D).material_override != null, "%s: %s has its shape" % [label, str(d)])
			m.free()


## A monster's loot as the game drops it (Events.loot_dropped through LootSystem) lies on the ground as pack models;
## a LootSystem given no pack keeps the procedural drops.
func test_the_loot_system_drops_pack_models() -> void:
	if _skip("test_the_loot_system_drops_pack_models"):
		return
	var shown := {}
	for label in ["installed", "none"]:
		var bus: Node = load("res://scripts/autoload/events.gd").new()
		var r := RandomNumberGenerator.new()
		r.seed = 3
		var none: Array[float] = []
		var state := MapInstanceState.fresh_for("000000040", none, SpawnModel.from_db(db()), r, 100.0)
		var l := LootSystem.new()
		l.db = db()
		l.bus = bus
		l.use_session = false
		l.read_input = false
		l.character_provider = func() -> CharacterState: return CharacterState.new()
		l.clock_provider = func() -> float: return 100.0
		l.state_provider = func() -> MapInstanceState: return state
		l.ground_axis_provider = func() -> Vector3: return Vector3(1, 0, 0)
		if label == "none":
			l.art = ArtPack.load_from("res://tests/data/no_such_pack")
		l.setup(null)
		var nodes: Array = []
		l.drop_spawned.connect(func(n: GroundDrop) -> void: nodes.append(n))
		bus.emit_signal("loot_dropped", [{"kind": "mesos", "amount": 12}, {"kind": "item", "item_id": "348", "qty": 1},
			{"kind": "item", "item_id": "541", "qty": 1}], Vector3(5, 1, 2), "000000040")
		assert_eq(nodes.size(), 3, "%s: three drops on the ground" % label)
		shown[label] = nodes.map(func(n: GroundDrop) -> bool: return LootVisuals.is_pack_model(n.model))
		l.free()
		bus.free()
	assert_eq(shown["installed"], [true, true, true], "the installed pack's models")
	assert_eq(shown["none"], [false, false, false], "procedural without a pack")


## Measured on the built model (its meshes, not the pack's validation data): the lowest point sits on the drop's base
## (the ground plane under the hover), never below it and not floating above it, weapons included; the model is
## centred over the drop so it turns in place; and its longest side is the table's size, alike across item kinds.
func test_every_drop_rests_on_the_ground_centred_and_sized_alike() -> void:
	if _skip("test_every_drop_rests_on_the_ground_centred_and_sized_alike"):
		return
	var v := _vis()
	var item_extent := v.pack_num("item_extent_m")
	assert_between(item_extent, 0.3, 1.0, "an item-sized drop")
	for d: Dictionary in _drops():
		var m := v.build_drop_model(d)
		var box := ArtImport.visual_aabb(m)
		var label := "%s (%s)" % [str(d.get("item_id", "mesos %s" % d.get("amount"))), db().item(String(d.get("item_id", ""))).get("name", "")]
		assert_between(box.position.y, -0.005, 0.02, "%s: lowest point on the ground (%.3f)" % [label, box.position.y])
		assert_near(box.get_center().x, 0.0, 0.02, "%s: centred in x" % label)
		assert_near(box.get_center().z, 0.0, 0.02, "%s: centred in z" % label)
		var want := item_extent if d.kind == "item" else float(v.style_for_mesos(int(d.amount)).pack_extent_m)
		var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		# The pack's validation bounds are a conservative box (the Apple's is 2 cm taller than its meshes), so a model
		# may come out a little under the size, never over it.
		assert_between(longest, want * 0.9, want * 1.01, "%s: longest side %.3f (want %.2f)" % [label, longest, want])
		m.free()


## The pack's Hover clip loops on the ground and only ever lifts the model (its root keys never go below rest), so the
## animation cannot sink a drop either.
func test_hover_loops_and_never_sinks_the_drop() -> void:
	if _skip("test_hover_loops_and_never_sinks_the_drop"):
		return
	var v := _vis()
	var hovering := 0
	for d: Dictionary in _drops():
		var m := v.build_drop_model(d)
		for ap in m.find_children("*", "AnimationPlayer", true, false):
			var player := ap as AnimationPlayer
			if not player.has_animation("Hover"):
				continue
			hovering += 1
			var clip := player.get_animation("Hover")
			assert_eq(clip.loop_mode, Animation.LOOP_LINEAR, "%s: Hover loops" % str(d))
			assert_eq(String(player.autoplay), "Hover", "%s: Hover plays" % str(d))
			for t in clip.get_track_count():
				if clip.track_get_type(t) == Animation.TYPE_POSITION_3D:
					for k in clip.track_get_key_count(t):
						assert_true((clip.track_get_key_value(t, k) as Vector3).y >= -0.0001, "%s: Hover lifts only" % str(d))
		m.free()
	# The six monster drops (347-351, 356) and the four meso tiers.
	assert_eq(hovering, 10, "every skinned drop hovers")


## #59 decision 5: a clip retires the procedural motion it covers, never both. Hover bobs the model's root (a lift of
## a couple of centimetres, no turn), so a hovering drop rests at the hover height without the procedural bob and
## keeps only the procedural spin; a static pack model (no clip) keeps both.
func test_a_hovering_drop_bobs_by_its_clip_alone_and_still_spins() -> void:
	if _skip("test_a_hovering_drop_bobs_by_its_clip_alone_and_still_spins"):
		return
	var v := _vis()
	for d: Dictionary in [{"kind": "item", "item_id": "348", "amount": 1}, {"kind": "mesos", "amount": 7}]:
		var n := GroundDrop.new()
		n.setup(d.merged({"uid": "h:1", "expires_at": 1000.0}), v, Vector3.ZERO, Vector3.ZERO, false)
		var ap := n.model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var sk := n.model.find_child("Skeleton3D", true, false) as Skeleton3D
		var bone := sk.find_bone("root")
		# Outside the tree autoplay has not started it.
		ap.play(String(ap.autoplay))
		var ys := []
		var yaws := []
		var lifts := []
		for i in 20:
			n.update(0.0, v.motion("bob_period_s") / 20.0)
			ap.advance(v.motion("bob_period_s") / 20.0)
			ys.append(n.model.position.y)
			yaws.append(n.model.rotation.y)
			lifts.append(sk.get_bone_pose_position(bone).y)
		assert_near(ys.max() - ys.min(), 0.0, 0.0001, "%s: no procedural bob" % str(d))
		assert_near(ys[0], v.motion("hover_m"), 0.0001, "%s: at the hover height" % str(d))
		assert_true(absf(yaws[19] - yaws[0]) > 0.1, "%s: still spins" % str(d))
		assert_true(lifts.max() - lifts.min() > 0.005, "%s: the clip bobs the root (%s)" % [str(d), str(lifts)])
		n.free()
	var still := GroundDrop.new()
	still.setup({"uid": "s:1", "kind": "item", "item_id": "541", "amount": 1, "expires_at": 1000.0}, v, Vector3.ZERO,
		Vector3.ZERO, false)
	assert_true(LootVisuals.is_pack_model(still.model), "the sword is a static pack model")
	var sy := []
	for i in 20:
		still.update(0.0, v.motion("bob_period_s") / 20.0)
		sy.append(still.model.position.y)
	assert_true(sy.max() - sy.min() > v.motion("bob_amplitude_m"), "a static pack model bobs procedurally")
	still.free()
