extends TestCase
## InteractionSystem with a duck-typed world and player: F talks to the NPC the world names nearest (through the
## shared NpcInteraction), never when the controller grabbed a ladder or a portal is nearer, never while a modal is
## open; the prompt names the same thing (NPC, portal, ladder, drop); NPC presenters get name tags, quest markers that
## follow the quest state, an idle bob and face the player while talking; a modal leaves the world's PortalInteractor to
## its own modal rule.

class FakeWorld:
	extends Node
	var near: Dictionary = {}
	var under: Node = null
	var npc_nodes: Dictionary = {}
	var interactor: Node = null

	func nearest_interactable(_pos: Vector3) -> Dictionary:
		return near

	func portal_under_player() -> Node:
		return under


class FakePlayer:
	extends Node3D
	var input_source := BotInput.new()
	var input_on := true
	var climbing := false
	var grabbable: ClimbableDef = null

	func is_input_enabled() -> bool:
		return input_on

	func set_input_enabled(on: bool) -> void:
		input_on = on

	func is_dead() -> bool:
		return false

	func is_climbing() -> bool:
		return climbing

	func grabbable_climbable() -> ClimbableDef:
		return grabbable


var bus: Node
var character: CharacterState
var service: QuestService
var talk: NpcInteraction
var world: FakeWorld
var player: FakePlayer
var system: InteractionSystem
var roger: Node3D


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	character = CharacterState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	service = QuestService.create(bus, db(), character, rng, func() -> float: return 0.0)
	service.attach()
	talk = NpcInteraction.new(service)
	world = FakeWorld.new()
	_parent().add_child(world)
	player = FakePlayer.new()
	world.add_child(player)
	roger = _npc("3", "Roger", Vector3(1, 0, 0))
	system = InteractionSystem.new()
	system.world = world
	system.player = player
	system.db = db()
	system.use_session = false
	system.talk_provider = func() -> NpcInteraction: return talk
	_parent().add_child(system)


func after_each() -> void:
	service.detach()
	if talk.is_open():
		talk.close()
	system.free()
	world.free()
	bus.free()


func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root


## A world NPC stand-in: metadata like WorldNpc, a 1.5 m "Visual" model.
func _npc(id: String, npc_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "NPC_" + id
	n.set_meta("npc_id", id)
	n.set_meta("npc_name", npc_name)
	world.add_child(n)
	n.position = pos
	var visual := Node3D.new()
	visual.name = "Visual"
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 1.5, 0.4)
	mi.mesh = box
	mi.position = Vector3(0, 0.75, 0)
	visual.add_child(mi)
	n.add_child(visual)
	world.npc_nodes[id] = n
	return n


## Contract C6: the interact indicator (the prompt names what F / Up / Z will do) and the NPC quest markers.
func parity_keys() -> Dictionary:
	return {
		"test_interact_talks_to_the_nearest_npc": ["ui:interact-indicator"],
		"test_climb_down_prompt_at_the_top": ["ui:interact-indicator"],
		"test_a_nearer_portal_takes_interact": ["ui:interact-indicator"],
		"test_drop_prompt_comes_from_the_loot_system": ["ui:interact-indicator"],
		"test_presenters_tag_mark_bob_and_face_the_player": ["ui:quest-indicators"],
	}


func _near_npc(n: Node3D) -> void:
	world.near = {"kind": "npc", "node": n, "id": String(n.get_meta("npc_id")), "distance": 1.0}


func _press_interact() -> void:
	player.input_source.begin_tick()  # a tick without the key, so the press below is a fresh edge
	player.input_source.press(&"interact")
	player.input_source.begin_tick()
	system._physics_process(1.0 / 60.0)


func test_interact_talks_to_the_nearest_npc() -> void:
	_near_npc(roger)
	var started: Array = []
	system.talk_started.connect(func(id: String) -> void: started.append(id))
	assert_eq(system.update_prompt()["text"], "[F] Talk to Roger")
	assert_true(system.prompt.visible)
	assert_eq(system.prompt.text(), "[F] Talk to Roger")
	_press_interact()
	assert_true(talk.is_open(), "F talked")
	assert_eq(talk.npc_id, "3")
	assert_eq(started, ["3"])


func test_no_talk_when_the_controller_grabbed_a_ladder() -> void:
	_near_npc(roger)
	var ladder := ClimbableDef.new()
	ladder.top = Vector3(0, 3, 0)
	player.grabbable = ladder
	assert_eq(system.update_prompt()["text"], "[Up] Climb", "the prompt names what F/Up will do")
	_press_interact()
	assert_false(talk.is_open(), "F grabs the ladder; talking too would be double handling")
	player.grabbable = null
	player.climbing = true
	assert_eq(system.update_prompt(), {}, "no prompt while climbing")
	_press_interact()
	assert_false(talk.is_open())


func test_climb_down_prompt_at_the_top() -> void:
	var rope := ClimbableDef.new()
	rope.bottom = Vector3(0, -3, 0)
	rope.top = Vector3(0, 0.1, 0)
	player.grabbable = rope
	assert_eq(system.update_prompt()["text"], "[Down] Climb down")


func test_a_nearer_portal_takes_interact() -> void:
	var portal := Node3D.new()
	world.add_child(portal)
	world.near = {"kind": "portal", "node": portal, "id": "000000010.out00", "distance": 0.5}
	world.under = portal
	assert_eq(system.update_prompt()["text"], "[Up] Enter portal")
	_press_interact()
	assert_false(talk.is_open(), "PortalInteractor owns F on a portal")


func test_no_talk_and_no_prompt_while_a_modal_is_open() -> void:
	var ctx := GameContext.new()
	ctx.player = player
	ctx.world = world
	system.setup(ctx)
	_near_npc(roger)
	ctx.push_modal(self)
	assert_eq(system.update_prompt(), {})
	assert_false(system.prompt.visible)
	_press_interact()
	assert_false(talk.is_open())
	ctx.pop_modal(self)
	player.input_on = true  # MapSession is not idle in tests, so the context leaves input to us
	_press_interact()
	assert_true(talk.is_open())


func test_drop_prompt_comes_from_the_loot_system() -> void:
	var r := RandomNumberGenerator.new()
	var none: Array[float] = []
	var st := MapInstanceState.fresh_for("000000040", none, SpawnModel.from_db(db()), r, 0.0)
	var loot := LootSystem.new()
	loot.db = db()
	loot.bus = bus
	loot.use_session = false
	loot.read_input = false
	loot.state_provider = func() -> MapInstanceState: return st
	loot.clock_provider = func() -> float: return 0.0
	loot.setup(null)
	system.loot = loot
	loot.spawn_drops([{"kind": "item", "item_id": "348", "qty": 1}], player.position)
	loot.tick(1.0)
	assert_eq(system.update_prompt()["text"], "[Z] Pick up Snail Shell")
	_near_npc(roger)
	assert_eq(system.update_prompt()["kind"], "npc", "an NPC in range comes first")
	loot.free()


func test_presenters_tag_mark_bob_and_face_the_player() -> void:
	var sam := _npc("9", "Sam", Vector3(0, 0, 2))
	var mai := _npc("11", "Mai", Vector3(5, 0, 0))
	system.attach_presenters()
	var ps: NpcPresenter = sam.get_node("Presenter")
	assert_true(ps != null, "presenter attached as a child of the NPC node")
	assert_eq(system.presenters.size(), 3)
	assert_eq(ps.tag.name_label.text, "Sam")
	assert_near(ps.height, 1.5, 0.01, "height from the model")
	assert_eq(system.attach_presenter(sam), ps, "idempotent")
	system.refresh_markers()
	assert_eq(ps.marker.state, "available", "Sam offers 1006")
	assert_eq((system.presenters["11"] as NpcPresenter).marker.state, "", "Mai has nothing yet")
	talk.talk("9")
	talk.press("yes")
	system.refresh_markers()
	assert_eq(ps.marker.state, "in_progress", "Sam: started here, under way")
	assert_eq((system.presenters["11"] as NpcPresenter).marker.state, "in_progress", "Mai: not ready")
	for k in 10:
		bus.emit_signal("monster_killed", "2", "000000040")
	system.refresh_markers()
	assert_eq((system.presenters["11"] as NpcPresenter).marker.state, "completable", "Mai: ready to turn in")
	# Facing: talking to Mai turns her model toward the player (the player stands at the origin, Mai at +X).
	var pm: NpcPresenter = system.presenters["11"]
	talk.close()
	talk.talk("11")
	for i in 30:
		pm.update(0.1)
	assert_near(absf(angle_difference(pm.model_yaw(), atan2(-1.0, 0.0))), 0.0, 0.05, "faces -X toward the player")
	talk.close()
	for i in 30:
		pm.update(0.1)
	assert_near(pm.model_yaw(), 0.0, 0.05, "turns back after the chat")
	# Idle bob.
	var ys: Array = []
	for i in 30:
		ps.update(0.1)
		ys.append((sam.get_node("Visual") as Node3D).position.y)
	assert_true(ys.max() - ys.min() > 0.02, "bobs")
	assert_true(ys.max() < 0.05, "subtly")
	assert_eq(mai.get_node("Presenter"), pm)


func test_markers_hide_for_npcs_of_other_maps() -> void:
	# A WorldNpc reports interaction_enabled = false outside the current map; the presenter goes quiet.
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar interaction_enabled := false\n"
	script.reload()
	var other := Node3D.new()
	other.set_script(script)
	other.set_meta("npc_id", "9")
	other.set_meta("npc_name", "Sam")
	world.add_child(other)
	var p2 := NpcPresenter.attach(other, system.overlay, db())
	p2.talk_provider = func() -> NpcInteraction: return talk
	p2.refresh_marker()
	assert_false(p2.is_active())
	assert_eq(p2.marker.state, "", "no marker off-map")
	p2.update(0.1)
	assert_false(p2.tag.visible)


## The world's PortalInteractor ignores presses under a modal itself (PortalInteractor.blocked). The interaction system
## used to pause it while a modal was open; it no longer touches it, so the two can never disagree about whether the
## interactor runs (Up in a menu inside a portal is checked in the real game by test_interaction_main_flow).
func test_a_modal_leaves_the_world_portal_interactor_alone() -> void:
	var interactor := Node.new()
	world.add_child(interactor)
	world.interactor = interactor
	interactor.set_physics_process(true)
	var ctx := GameContext.new()
	ctx.world = world
	ctx.player = player
	system.setup(ctx)
	_near_npc(roger)
	ctx.push_modal(self)
	assert_true(interactor.is_physics_processing(), "not paused by the interaction system")
	assert_eq(system.update_prompt(), {}, "no prompt under the modal")
	assert_false(system.handle_interact(), "F does not talk under the modal")
	assert_eq(PortalInteractor.blocked(null, player), "input off", "the world's own rule refuses portals under the modal")
	ctx.pop_modal(self)
	assert_true(interactor.is_physics_processing())
	player.input_on = true  # (GameContext hands input back only when MapSession is idle; no session runs here)
	assert_eq(PortalInteractor.blocked(null, player), "", "and allows them again afterwards")


func test_presenters_survive_a_freed_overlay() -> void:
	var sam := _npc("9", "Sam", Vector3(0, 0, 2))
	var first := Control.new()
	_parent().add_child(first)
	var p := NpcPresenter.attach(sam, first, db())
	assert_eq(p.tag.get_parent(), first)
	first.free()  # an earlier interaction system's overlay went away; the world node stayed
	p.update(0.1)  # no access to freed controls
	p.refresh_marker()
	var again := NpcPresenter.attach(sam, system.overlay, db())
	assert_eq(again, p, "same presenter")
	assert_true(is_instance_valid(p.tag) and p.tag.get_parent() == system.overlay, "fresh tag in the new overlay")
	assert_true(is_instance_valid(p.marker) and p.marker.get_parent() == system.overlay)
