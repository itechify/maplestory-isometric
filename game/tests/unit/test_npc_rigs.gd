extends TestCase
## The 21 NPCs are the art pack's rigged models (#66): a WorldNpc given an ArtPack shows the pack's model for its
## canonical NPC id (not its name, and not the GMS ids of characters/manifest.json), at the character scale the import
## put on its rig node, playing the looping idle clip; NpcPresenter measures the taller model for the name tag, the
## quest marker and the bubble, and drops its procedural bob where idle covers it; NpcPortrait renders the rigged
## model, head and shoulders. Needs the art pack installed (bash scripts/art_pack.sh fetch); every test prints SKIP
## without it. Without the pack the proxies and their bob stay (test_interaction_system, test_npc_ui_dialogue).

var art: ArtPack
var _nodes: Array[Node] = []


func before_each() -> void:
	art = ArtPack.load_installed()


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


func _skip(test: String) -> bool:
	if art.present():
		return false
	print("SKIP %s: no art pack installed (bash scripts/art_pack.sh fetch)" % test)
	return true


func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root


## A WorldNpc for canonical NPC `id` (its canonical name), in the tree, with the pack injected.
func _npc(id: String, pos: Vector3 = Vector3.ZERO) -> WorldNpc:
	var pl := NpcPlacement.new()
	pl.npc_id = id
	pl.npc_name = String(db().npc(id).get("name", id))
	pl.map_id = "000000040"
	pl.proxy = "NPC_" + pl.npc_name
	pl.transform = Transform3D(Basis.IDENTITY, pos)
	var n := WorldNpc.new()
	n.art = art
	_parent().add_child(n)
	_nodes.append(n)
	n.setup(pl, null, 1.6)
	return n


func test_every_canonical_npc_is_its_pack_model_playing_idle() -> void:
	if _skip("test_every_canonical_npc_is_its_pack_model_playing_idle"):
		return
	var ids := db().ids("npcs")
	assert_eq(ids.size(), 21, "21 canonical NPCs")
	for id in ids:
		var n := _npc(id)
		var v := n.visual
		assert_true(v != null and v.name == &"Visual", "%s: a Visual" % id)
		if v == null:
			continue
		assert_false(v.has_meta("placeholder"), "%s: not the placeholder" % id)
		assert_eq(n.model_source, art.model(ArtPack.NPC, id), "%s: the pack's model for its canonical id" % id)
		assert_true(v.find_child("Skeleton3D", true, false) is Skeleton3D, "%s: rigged" % id)
		var ap := n.animation_player()
		assert_true(ap != null and ap.is_playing(), "%s: its AnimationPlayer plays" % id)
		if ap != null:
			assert_eq(String(ap.current_animation), "idle", "%s: idle" % id)
			assert_eq(ap.get_animation("idle").loop_mode, Animation.LOOP_LINEAR, "%s: idle loops" % id)
		n.free()


func test_the_presenter_measures_the_rig_and_lets_idle_replace_the_bob() -> void:
	if _skip("test_the_presenter_measures_the_rig_and_lets_idle_replace_the_bob"):
		return
	# Shanks (15) is the tallest NPC, Jarvis made him taller than the 1.5 m player; Sera (2) is one of the shortest.
	var expect := {"15": 1.79, "2": 1.41}
	for id: String in expect:
		var n := _npc(id)
		n.interaction_enabled = true
		var p := NpcPresenter.attach(n, null, db())
		assert_near(p.height, float(expect[id]), 0.01, "%s: the name tag and marker sit on the model's height" % id)
		assert_true(p.idle_covers_bob(), "%s: the idle clip replaces the bob" % id)
		var ys: Array = []
		for i in 30:
			p.update(0.1)
			ys.append(n.visual.position.y)
		assert_near(ys.max() - ys.min(), 0.0, 1e-6, "%s: no procedural bob on the rig" % id)


func test_every_portrait_renders_the_rig_head_and_shoulders() -> void:
	if _skip("test_every_portrait_renders_the_rig_head_and_shoulders"):
		return
	var portrait := NpcPortrait.new()
	_parent().add_child(portrait)
	_nodes.append(portrait)
	for id in db().ids("npcs"):
		var n := _npc(id)
		# The presenter's turn and the source's pose must not leak into the portrait.
		n.visual.rotation.y = 1.0
		portrait.show_speaker(id, String(db().npc(id).get("name", id)), n.visual)
		assert_eq(portrait.mode, "model", "%s: the rigged model, not the badge" % id)
		var copy := portrait.shown_model()
		assert_true(copy != null and copy.find_child("Skeleton3D", true, false) is Skeleton3D, "%s: the rig" % id)
		if copy == null:
			continue
		var ap := copy.find_child("AnimationPlayer", true, false) as AnimationPlayer
		assert_true(ap != null and ap.is_playing() and String(ap.current_animation) == "idle", "%s: idles" % id)
		# Head and shoulders: the frame holds the top of the head (a hat too) and the shoulders, not the hips.
		var span := portrait.framed_span()
		var box := ArtImport.visual_aabb(copy)
		var sk := copy.find_child("Skeleton3D", true, false) as Skeleton3D
		var k := ArtPack.character_scale()
		var shoulders := sk.get_bone_global_rest(sk.find_bone("upper_arm.L")).origin.y * k
		var hips := sk.get_bone_global_rest(sk.find_bone("hips")).origin.y * k
		assert_true(span.y >= box.end.y, "%s: the head's top (%.2f) is in the frame (top %.2f)" % [id, box.end.y, span.y])
		assert_true(span.x < shoulders, "%s: the shoulders (%.2f) are in the frame (bottom %.2f)" % [id, shoulders, span.x])
		assert_true(span.x > hips, "%s: the hips (%.2f) are below the frame (bottom %.2f)" % [id, hips, span.x])
		n.free()


func test_a_portrait_of_the_same_speaker_is_not_rebuilt_every_line() -> void:
	if _skip("test_a_portrait_of_the_same_speaker_is_not_rebuilt_every_line"):
		return
	var portrait := NpcPortrait.new()
	_parent().add_child(portrait)
	_nodes.append(portrait)
	var roger := _npc("3")
	portrait.show_speaker("3", "Roger", roger.visual)
	var first := portrait.shown_model()
	portrait.show_speaker("3", "Roger", roger.visual)
	assert_true(portrait.shown_model() == first, "the next line of the same speaker keeps the rendered copy")
	var sera := _npc("2", Vector3(3, 0, 0))
	portrait.show_speaker("2", "Sera", sera.visual)
	assert_true(portrait.shown_model() != first, "another speaker is rendered afresh")
	portrait.show_speaker("", "", null, "system")
	assert_eq(portrait.mode, "badge", "a system line still shows the badge")
	portrait.show_speaker("2", "Sera", sera.visual)
	assert_eq(portrait.mode, "model", "and the speaker's model comes back")
