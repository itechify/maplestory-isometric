extends TestCase
## The end-of-Maple-Island screen (DepartureScreen, scenes/ui/screens/departure_screen.tscn): Shanks' Yes opens it
## through NpcInteraction.departure_requested; it states the boundary (no travel, no fare), the character's level,
## mesos and Maple Island quests, takes the keyboard as a modal on the GameContext window stack and closes with its
## button or Esc (close_top_window).

class FakePlayer:
	extends Node3D
	var input_on := true

	func set_input_enabled(on: bool) -> void:
		input_on = on


class FakeShell:
	extends Node
	signal session_ended
	var game_ctx: GameContext = null

	func ctx() -> GameContext:
		return game_ctx


var bus: Node
var character: CharacterState
var service: QuestService
var talk: NpcInteraction
var screen: DepartureScreen
var shell: FakeShell
var player: FakePlayer


func parity_keys() -> Dictionary:
	return {"test_yes_at_shanks_opens_the_boundary_screen": ["npc:15", "mechanic:southperry-departure"]}


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	character = CharacterState.new()
	character.level = 7
	character.mesos = 300
	service = QuestService.create(bus, db(), character, RandomNumberGenerator.new(), func() -> float: return 12.0)
	talk = NpcInteraction.new(service)
	shell = FakeShell.new()
	shell.game_ctx = GameContext.new()
	player = FakePlayer.new()
	shell.game_ctx.player = player
	screen = DepartureScreen.for_shell(shell)
	screen.talk_provider = func() -> NpcInteraction: return talk
	screen.character_provider = func() -> CharacterState: return character
	screen.db = db()
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(screen)
	screen.bind()


func after_each() -> void:
	screen.free()
	player.free()
	shell.free()
	bus.free()


## Talks to Shanks and says Yes to the voyage (pressing Next through every page before the offer).
func _board() -> void:
	var v := talk.talk("15")
	for k in 6:
		if v["type"] == "yes_no":
			break
		v = talk.press("next")
	assert_eq(v["type"], "yes_no", "reached the offer")
	talk.press("yes")


func test_scene_builds_the_screen_hidden() -> void:
	assert_true(screen is DepartureScreen)
	assert_false(screen.visible)
	assert_false(screen.is_open())
	assert_eq(screen.title_label.text, "End of Maple Island")


func test_yes_at_shanks_opens_the_boundary_screen() -> void:
	for qid in service.engine.catalog.ids():
		character.quests.start(qid, 0.0)
		character.quests.complete(qid, 0.0)
	_board()
	assert_true(screen.is_open(), "the screen opened from departure_requested")
	assert_true(screen.visible)
	var t := screen.texts()
	assert_eq(t[0], "End of Maple Island")
	assert_true(t[1].contains("The boat to Lith Harbor"), t[1])
	assert_true(t[1].contains("Victoria Island is not part of MisoStory yet"), t[1])
	assert_true(t[1].contains("the 300-meso fare was not taken"), t[1])
	assert_eq(t[2], "Level 7  ·  300 mesos  ·  Maple Island quests completed: 20 of 20")
	assert_eq(t[3], "Every Maple Island quest is done.")
	assert_true(shell.game_ctx.is_modal_active(), "modal: the player stands still")
	assert_false(player.input_on)
	assert_true(shell.game_ctx.has_open_windows(), "on the window stack (Esc)")
	screen.continue_button.pressed.emit()
	assert_false(screen.is_open())
	assert_false(screen.visible)
	assert_false(shell.game_ctx.is_modal_active(), "the modal is released (GameContext hands the keyboard back once MapSession is idle)")
	assert_eq(character.mesos, 300)


func test_unfinished_quests_are_named_and_esc_closes() -> void:
	character.quests.start("1002", 0.0)
	character.quests.complete("1002", 0.0)
	_board()
	assert_true(screen.is_open())
	var t := screen.texts()
	assert_eq(t[2], "Level 7  ·  300 mesos  ·  Maple Island quests completed: 1 of 20")
	assert_true(t[3].begins_with("Still unfinished: Borrowing Sera's Mirror, Bringing a Mirror to Heena, "), t[3])
	assert_false(t[3].contains("Roger's Apple"))
	assert_true(shell.game_ctx.close_top_window(), "Esc closes the newest window: this screen")
	assert_false(screen.is_open())
	assert_false(shell.game_ctx.is_modal_active())


func test_quit_to_title_closes_it() -> void:
	_board()
	assert_true(screen.is_open())
	shell.session_ended.emit()
	assert_false(screen.is_open())
	assert_false(shell.game_ctx.is_modal_active())


func test_body_text_when_a_boundary_charges() -> void:
	var body := DepartureScreen.body_for({"route": {"to_map_name": "Lith Harbor", "fare_mesos": 300}, "fare_charged": 300})
	assert_true(body.contains("You paid the 300-meso fare."), body)
