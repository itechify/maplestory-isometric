extends TestCase
## Input gating of the portal keys and of the world's input hand-back (WORLD_RUNTIME.md "Interaction" and "Input
## gating"), without physics: an unbuilt IslandWorld (its own player_input_block / is_modal_active /
## set_player_input logic) with the portal under the player stubbed, a stub session that records requests, and the
## world's test capsule pressing keys through a BotInput. The physics version (a real warp under a GameContext modal)
## is world_checks.gd's "gating" section.


## The session the interactor talks to: idle, records request_portal calls.
class StubSession extends Node:
	var requests: Array[PortalDef] = []
	var idle: bool = true
	var current_map: String = "000000001"

	func is_idle() -> bool:
		return idle

	func request_portal(p: PortalDef) -> Error:
		requests.append(p)
		return OK


## IslandWorld with the trigger test replaced: the player always stands in `under`.
class GateWorld extends IslandWorld:
	var under: WorldPortal = null

	func portal_under_player() -> WorldPortal:
		return under

	func nearest_interactable(_pos: Vector3) -> Dictionary:
		return {"kind": "portal", "node": under, "id": under.def.key(), "distance": 0.0} if under != null else {}


## The capsule plus the controller's is_dead().
class MortalPlayer extends WorldTestPlayer:
	var dead: bool = false

	func is_dead() -> bool:
		return dead


## A parent that owns the game's context, as GameSession does.
class ContextOwner extends Node:
	var ctx: GameContext = null


var world: GateWorld = null
var session: StubSession = null
var player: MortalPlayer = null
var bot: BotInput = null
var interactor: PortalInteractor = null
var portal: WorldPortal = null
var modal: bool = false


func before_each() -> void:
	var defs := MapDefinitions.build(db())
	world = GateWorld.new()  # never enters the tree: no build
	world.tuning = defs.tuning
	session = StubSession.new()
	world.session = session
	player = MortalPlayer.new()
	# In the tree, so global_position is readable (the runner never steps physics during a test).
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(player)
	bot = BotInput.new()
	player.input_source = bot
	world.player = player
	portal = WorldPortal.new()
	portal.def = defs.portal("000000001", "out00")
	world.under = portal
	interactor = PortalInteractor.new()
	interactor.world = world
	modal = false


func after_each() -> void:
	if is_instance_valid(player) and player.get_parent() != null:
		player.get_parent().remove_child(player)
	for n: Node in [interactor, portal, player, session, world]:
		if is_instance_valid(n):
			n.free()


## One physics tick with `action` pressed.
func press(action: StringName) -> void:
	bot.press(action)
	bot.begin_tick()
	interactor._physics_process(1.0 / 60.0)
	bot.begin_tick()


func test_up_and_interact_enter_when_the_player_may_act() -> void:
	press(&"portal_enter")
	assert_eq(session.requests.size(), 1, "Up enters")
	assert_true(session.requests[0] == portal.def, "the portal under the player")
	press(&"interact")
	assert_eq(session.requests.size(), 2, "F enters the nearest portal (interact_also_enters)")
	assert_eq(interactor.last_block, "", "nothing blocked")


func test_input_off_blocks_the_portal_keys() -> void:
	player.set_input_enabled(false)
	press(&"portal_enter")
	press(&"interact")
	assert_eq(session.requests.size(), 0, "no warp with the player's input off")
	assert_eq(interactor.last_block, "input off", "reason")
	assert_eq(world.player_input_block(), "input off", "the world says why")


func test_a_dead_player_never_warps() -> void:
	player.dead = true
	press(&"portal_enter")
	assert_eq(session.requests.size(), 0, "no warp while dead")
	assert_eq(interactor.last_block, "dead", "reason")


func test_a_modal_blocks_the_portal_keys_even_with_input_on() -> void:
	world.modal_provider = func() -> bool: return modal
	modal = true
	assert_true(player.is_input_enabled(), "input is on (something gave it back under the modal)")
	press(&"portal_enter")
	press(&"interact")
	assert_eq(session.requests.size(), 0, "a dialogue's Up arrow never warps")
	assert_eq(interactor.last_block, "modal", "reason")
	modal = false
	press(&"portal_enter")
	assert_eq(session.requests.size(), 1, "the modal closed: Up works again")


func test_not_idle_session_ignores_presses() -> void:
	session.idle = false
	press(&"portal_enter")
	assert_eq(session.requests.size(), 0, "no request mid-warp")


## MapSession's end-of-transition hand-back goes through set_player_input(true): refused under a modal.
func test_set_player_input_never_hands_input_back_under_a_modal() -> void:
	world.modal_provider = func() -> bool: return modal
	modal = true
	world.set_player_input(false)
	world.set_player_input(true)
	assert_false(player.is_input_enabled(), "input stays off while the modal is open")
	modal = false
	world.set_player_input(true)
	assert_true(player.is_input_enabled(), "on once no modal is open")
	modal = true
	world.set_player_input(false)
	assert_false(player.is_input_enabled(), "turning input off always goes through")


## The context the shell hands over (set_context), and the fallback through the parent that owns one.
func test_the_game_context_decides_what_a_modal_is() -> void:
	var ctx := GameContext.new()
	var owner := Node.new()
	world.set_context(ctx)
	assert_false(world.is_modal_active(), "no modal open")
	ctx.push_modal(owner)
	assert_true(world.is_modal_active(), "GameContext.push_modal")
	press(&"portal_enter")
	assert_eq(session.requests.size(), 0, "blocked by the context's modal")
	ctx.pop_modal(owner)
	assert_false(world.is_modal_active(), "popped")
	world.set_context(null)
	var parent := ContextOwner.new()
	parent.ctx = GameContext.new()
	parent.add_child(world)
	parent.ctx.push_modal(owner)
	assert_true(world.is_modal_active(), "found through the parent's ctx when none was set")
	world.modal_provider = func() -> bool: return false
	assert_false(world.is_modal_active(), "modal_provider wins")
	parent.remove_child(world)
	parent.free()
	owner.free()
