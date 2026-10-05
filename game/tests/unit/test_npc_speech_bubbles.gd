extends TestCase
## NPC speech bubbles (Iteration Three): every bubble is one of the NPC's canonical idle-chatter lines (MeowDB's
## speech-bubble pool), shown now and then on a seeded schedule whose timing is adaptation data
## (data/misostory/npcs/_speech_bubbles.json), only for an NPC on the current map and on screen, never during a
## conversation with it.

var bus: Node
var service: QuestService
var talk: NpcInteraction
var nodes: Array = []


func parity_keys() -> Dictionary:
	return {"test_every_bubble_is_a_canonical_line_for_all_21_npcs": ["mechanic:npc-idle-chatter-bubbles"]}


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	service = QuestService.create(bus, db(), CharacterState.new(), RandomNumberGenerator.new())
	talk = NpcInteraction.new(service)


func after_each() -> void:
	if talk.is_open():
		talk.close()
	nodes.reverse()
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	bus.free()


func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root


func test_timing_comes_from_the_adaptation_file() -> void:
	var cfg := db().miso_entity("npcs", NpcBubbleSchedule.CONFIG_ID)
	assert_false(cfg.is_empty(), "misostory/npcs/_speech_bubbles.json")
	assert_eq(cfg.get("verified"), false)
	var s := NpcBubbleSchedule.for_npc("1", db())
	assert_eq(s.line_count, (db().npc("1").get("idle_chatter") as Array).size())
	assert_between(s.until_next, float(cfg["first_delay_min_s"]), float(cfg["first_delay_max_s"]), "first delay")
	assert_eq(float(s.config["display_s"]), float(cfg["display_s"]))


func test_schedule_is_seeded_per_npc() -> void:
	var a := NpcBubbleSchedule.for_npc("12", db())
	var b := NpcBubbleSchedule.for_npc("12", db())
	var seq_a: Array = []
	var seq_b: Array = []
	for k in 2000:
		var la := a.tick(0.1, true)
		var lb := b.tick(0.1, true)
		if la >= 0:
			seq_a.append([k, la])
		if lb >= 0:
			seq_b.append([k, lb])
	assert_eq(seq_a, seq_b, "same NPC, same bubbles at the same times")
	assert_true(seq_a.size() >= 5, "a bubble every 14-26 s over 200 s: %d" % seq_a.size())
	var gaps_ok := true
	for i in range(1, seq_a.size()):
		var gap := float(int(seq_a[i][0]) - int(seq_a[i - 1][0])) * 0.1
		gaps_ok = gaps_ok and gap >= 13.9 and gap <= 26.2
	assert_true(gaps_ok, "intervals within the adaptation's range")


func test_sequential_order_shows_every_line() -> void:
	var n := (db().npc("7").get("idle_chatter") as Array).size()
	var s := NpcBubbleSchedule.for_npc("7", db())
	var seen := {}
	var last := -1
	for k in 20000:
		var l := s.tick(0.1, true)
		if l < 0:
			continue
		if last >= 0:
			assert_eq(l, (last + 1) % n, "lines follow the canonical order")
		last = l
		seen[l] = true
		if seen.size() == n:
			break
	assert_eq(seen.size(), n, "every one of Todd's %d lines comes up" % n)


func test_an_ineligible_turn_is_skipped_and_hiding_ends_the_bubble() -> void:
	var s := NpcBubbleSchedule.new("x", 3, {"first_delay_min_s": 1.0, "first_delay_max_s": 1.0, "interval_min_s": 5.0,
		"interval_max_s": 5.0, "display_s": 2.0})
	assert_eq(s.tick(1.5, false), -1, "due while off screen: skipped")
	assert_false(s.is_showing())
	assert_eq(s.tick(4.0, true), -1, "the next one is 5 s after the skipped one")
	var l := s.tick(1.0, true)
	assert_true(l >= 0 and l < 3)
	assert_true(s.is_showing())
	s.hide_now()
	assert_false(s.is_showing(), "a conversation hides it")
	assert_eq(NpcBubbleSchedule.new("y", 0).tick(100.0, true), -1, "no lines, no bubbles")


func test_every_bubble_is_a_canonical_line_for_all_21_npcs() -> void:
	var cat := NpcCatalog.new(db())
	assert_eq(cat.ids().size(), 21)
	for nid in cat.ids():
		var def := cat.get_def(nid)
		var canon: Array = db().npc(nid).get("idle_chatter")
		assert_true(canon.size() >= 1, "npc %s has a bubble pool" % nid)
		var s := NpcBubbleSchedule.for_npc(nid, db())
		var shown := 0
		for k in 3000:
			var l := s.tick(0.5, true)
			if l < 0:
				continue
			var line := def.idle_line(l)
			assert_eq(line["text"], String((canon[l] as Dictionary)["text"]), "npc %s bubble %d" % [nid, l])
			assert_eq(line["source"], "canonical/npcs/%s.json#idle_chatter[%d]" % [nid, l])
			shown += 1
		assert_true(shown >= canon.size(), "npc %s: %d bubbles in 25 min" % [nid, shown])


func test_presenter_shows_bubbles_on_screen_and_never_while_talking() -> void:
	var overlay := Control.new()
	_parent().add_child(overlay)
	nodes.append(overlay)
	var root := Node3D.new()
	_parent().add_child(root)
	nodes.append(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 2, 7)
	cam.look_at(Vector3(0, 1, 0))
	var npc := Node3D.new()
	npc.set_meta("npc_id", "16")
	npc.set_meta("npc_name", "Pan")
	root.add_child(npc)
	var p := NpcPresenter.attach(npc, overlay, db())
	p.camera_provider = func() -> Camera3D: return cam
	p.talk_provider = func() -> NpcInteraction: return talk
	assert_true(p.bubble != null and p.bubble.get_parent() == overlay, "the bubble lives in the overlay")
	var canon: PackedStringArray = []
	for l: Dictionary in db().npc("16").get("idle_chatter"):
		canon.append(String(l["text"]))
	var seen := 0
	for k in 600:
		p.update(0.1)
		if p.bubble.visible:
			seen += 1
			assert_true(p.bubble.text in canon, "canonical text: %s" % p.bubble.text)
			assert_true(p.bubble.source.begins_with("canonical/npcs/16.json#idle_chatter["))
			assert_true(p.bubble.size.x > 0.0 and p.bubble.size.x <= NpcSpeechBubble.MAX_TEXT_WIDTH + 30.0)
	assert_true(seen > 0, "Pan said something within a minute")
	# Talking to Pan: the bubble goes away and stays away for the whole conversation.
	talk.talk("16")
	for k in 600:
		p.update(0.1)
		assert_false(p.bubble.visible, "no bubble during the conversation")
		if not talk.is_open():
			talk.talk("16")
	talk.close()
	# Off the current map: never.
	npc.set("interaction_enabled", false)
	npc.set_meta("interaction_enabled", false)
	p.npc = _off_map_npc(root)
	for k in 600:
		p.update(0.1)
		assert_false(p.bubble.visible, "an NPC of another map stays quiet")


## A stand-in WorldNpc whose interaction_enabled is false (another map's NPC).
func _off_map_npc(root: Node3D) -> Node3D:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar interaction_enabled := false\n"
	script.reload()
	var n: Node3D = script.new()
	n.set_meta("npc_id", "16")
	root.add_child(n)
	return n
