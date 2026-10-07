extends TestCase
## PlaytestBubbleWatch (#40), the playthrough's proof that an open shop hides NPC speech bubbles: driven with real
## NpcPresenters whose modal check is injected, as test_npc_speech_bubbles.gd drives them. With the window rule a
## bubble falls due within the schedule's bound and none shows; with the rule disabled (the presenter ignores the open
## window) the same watch fails; a bubble skipped because the NPC is talking to the player proves nothing.

var bus: Node
var service: QuestService
var talk: NpcInteraction
var nodes: Array = []


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


func test_the_watch_passes_when_an_open_window_hides_a_bubble_that_falls_due() -> void:
	var p := _lucy([true])
	var r := _watch(p)
	assert_true(r["proven"], "a bubble fell due within the bound: %s" % r)
	assert_true(r["quiet"], "and none showed: %s" % r)
	assert_true(float(r["at_s"]) <= float(r["bound_s"]), "within next_due + MARGIN_S: %s" % r)


func test_the_watch_fails_when_hiding_bubbles_under_a_window_is_disabled() -> void:
	# The shop is open, but the presenter's modal check says no: what the game would do without the window rule.
	var p := _lucy([false])
	var r := _watch(p)
	assert_true(r["proven"], "a bubble fell due: %s" % r)
	assert_false(r["quiet"], "and it showed, so the check fails: %s" % r)
	assert_true((r["shown"] as Array).size() > 0 and String(r["shown"][0]["npc"]) == "21", "Lucy's bubble: %s" % r)


func test_a_bubble_skipped_during_a_conversation_proves_nothing() -> void:
	var p := _lucy([true])
	talk.talk("21")
	assert_true(p.is_talking(), "talking to Lucy")
	var r := _watch(p, 30.0)
	assert_false(r["proven"], "the conversation rule hid it, not the window rule: %s" % r)
	assert_eq(PlaytestBubbleWatch.next_due(PlaytestBubbleWatch.sample({"21": p})), -1.0, "no NPC could show one")


func test_wait_shown_finds_the_next_bubble_within_the_schedule() -> void:
	var p := _lucy([false])
	var s := PlaytestBubbleWatch.sample({"21": p})
	assert_true(bool(s["21"]["on_screen"]) and not bool(s["21"]["talking"]), "on screen, not talking: %s" % s)
	var bound := PlaytestBubbleWatch.next_due(s) + PlaytestBubbleWatch.MARGIN_S
	assert_eq(PlaytestBubbleWatch.next_due(s), p.bubbles.until_next, "the schedule's own due")
	var t := 0.0
	while PlaytestBubbleWatch.visible_in(s).is_empty() and t <= bound:
		p.update(0.1)
		t += 0.1
		s = PlaytestBubbleWatch.sample({"21": p})
	assert_eq(PlaytestBubbleWatch.visible_in(s), PackedStringArray(["21"]), "Lucy chattered within %.1f s (%.1f s)" % [bound, t])


## Feeds a watch one sample per 0.1 s update, as watch_quiet() does per frame, until a bubble fell due or the bound
## (the schedule's next due plus MARGIN_S, or `max_s` when no NPC could show one) passed.
func _watch(p: NpcPresenter, max_s: float = -1.0) -> Dictionary:
	var w := PlaytestBubbleWatch.new()
	var s := PlaytestBubbleWatch.sample({"21": p})
	var due := PlaytestBubbleWatch.next_due(s)
	var bound := due + PlaytestBubbleWatch.MARGIN_S if due >= 0.0 else max_s
	w.feed(s, 0.0)
	var t := 0.0
	while not w.proven() and t <= bound:
		p.update(0.1)
		t += 0.1
		w.feed(PlaytestBubbleWatch.sample({"21": p}), t)
	return {"proven": w.proven(), "quiet": w.quiet(), "shown": w.shown, "due": w.due, "at_s": t, "bound_s": bound}


## Lucy on screen in front of a camera; `modal[0]` is what her presenter's modal check answers (a shop is open).
func _lucy(modal: Array) -> NpcPresenter:
	var tree := Engine.get_main_loop() as SceneTree
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	var overlay := Control.new()
	parent.add_child(overlay)
	nodes.append(overlay)
	var root := Node3D.new()
	parent.add_child(root)
	nodes.append(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 2, 7)
	cam.look_at(Vector3(0, 1, 0))
	var npc := Node3D.new()
	npc.set_meta("npc_id", "21")
	npc.set_meta("npc_name", "Lucy")
	root.add_child(npc)
	var p := NpcPresenter.attach(npc, overlay, db())
	p.camera_provider = func() -> Camera3D: return cam
	p.talk_provider = func() -> NpcInteraction: return talk
	p.modal_provider = func() -> bool: return modal[0]
	p.update(0.0)
	return p
