class_name DepartureScreen
extends Control
## The end-of-Maple-Island boundary (Iteration Three adaptation, data/misostory/npcs/15.json "departure"). When the
## player boards Shanks' boat (NpcInteraction.departure_requested, NpcTransport.depart), this screen says the island is
## done for now: Victoria Island is not in this build, so nobody travels and no fare is taken. It shows the canonical
## destination and fare, the character's level and mesos, how many Maple Island quests are completed and which are
## not, and one button that returns to Southperry. Modal (the player stands still), registered on the window stack so
## Esc closes it too. Opening it requests an autosave (the departure flag is new progress).
##
## The shell installs it once with one line (MainShell._ready):  screens.add_child(DepartureScreen.for_shell(self))
## It follows Game.npc_talk (re-binding if the instance changes) and is null-safe without the autoloads (tests and
## sandboxes inject talk_provider / character_provider / db).

signal opened(departure: Dictionary)
signal closed()

const SCENE := "res://scenes/ui/screens/departure_screen.tscn"
const TITLE := "End of Maple Island"
const CONTINUE_TEXT := "Stay on Maple Island"

## The MainShell that installed it (ctx() for the modal and the window stack), or null.
var shell: Node = null
## () -> NpcInteraction; default: Game.npc_talk.
var talk_provider: Callable = Callable()
## () -> CharacterState; default: Game.character.
var character_provider: Callable = Callable()
## Content (default: Data.db).
var db: ContentDB = null
## The departure_requested effect being shown ({} when closed).
var departure: Dictionary = {}

var title_label: Label = null
var body_label: Label = null
var stats_label: Label = null
var quests_label: Label = null
var continue_button: Button = null
var _bound: NpcInteraction = null
var _ctx: GameContext = null
var _open := false


## The screen from its scene, for the shell (hidden until a departure).
static func for_shell(p_shell: Node) -> DepartureScreen:
	var s: DepartureScreen = (load(SCENE) as PackedScene).instantiate() if ResourceLoader.exists(SCENE) else DepartureScreen.new()
	s.shell = p_shell
	if p_shell != null and p_shell.has_signal(&"session_ended"):
		p_shell.connect(&"session_ended", s.close)
	return s


func _init() -> void:
	name = "DepartureScreen"
	visible = false
	ScreenKit.full_rect(self)
	ScreenKit.apply(self)
	add_child(ScreenKit.dim(Color(0.02, 0.05, 0.12, 0.62)))
	var panel := ScreenKit.window_panel()
	panel.custom_minimum_size = Vector2(620, 0)
	var v := ScreenKit.vbox(12)
	panel.add_child(ScreenKit.margin(v, 14))
	title_label = ScreenKit.title(TITLE, 26)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title_label)
	body_label = _wrapping(ScreenKit.label("", 16))
	v.add_child(body_label)
	v.add_child(ScreenKit.separator())
	stats_label = _wrapping(ScreenKit.label("", 15, ScreenKit.GOLD, "MisoGold"))
	v.add_child(stats_label)
	quests_label = _wrapping(ScreenKit.label("", 14, ScreenKit.TEXT_DIM, "MisoDim"))
	v.add_child(quests_label)
	var row := ScreenKit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	continue_button = ScreenKit.button(CONTINUE_TEXT, true, 220)
	continue_button.name = "Continue"
	continue_button.pressed.connect(close)
	continue_button.gui_input.connect(_filter_button_input)
	row.add_child(continue_button)
	v.add_child(row)
	add_child(ScreenKit.centered(panel))


func _process(_delta: float) -> void:
	bind()


## Shows the screen for a departure_requested effect (NpcTransport.depart).
func open(p_departure: Dictionary) -> void:
	departure = p_departure.duplicate(true)
	_fill()
	show()
	if not _open:
		_open = true
		_ctx = _game_ctx()
		if _ctx != null:
			_ctx.push_modal(self)
			_ctx.window_opened(self)
		var game := _autoload("Game")
		if game != null and game.has_method("request_autosave"):
			game.call("request_autosave", "departure")
	continue_button.grab_focus()
	opened.emit(departure)


## Closes the screen; the player is back in Southperry with the keyboard.
func close() -> void:
	if not _open:
		hide()
		return
	_open = false
	hide()
	if _ctx != null:
		_ctx.pop_modal(self)
		_ctx.window_closed(self)
	_ctx = null
	closed.emit()


func is_open() -> bool:
	return _open


## Every text on the screen, top to bottom (for tests and playtests).
func texts() -> PackedStringArray:
	return PackedStringArray([title_label.text, body_label.text, stats_label.text, quests_label.text])


## The body text for a departure (static, so it is testable without a scene).
static func body_for(dep: Dictionary) -> String:
	var route: Dictionary = dep.get("route", {})
	var dest := String(route.get("to_map_name", "the next island"))
	var fare := int(route.get("fare_mesos", 0))
	var charged := int(dep.get("fare_charged", 0))
	var lines := PackedStringArray()
	lines.append("You are ready to leave Maple Island. The boat to %s is the edge of this world for now: Victoria Island is not part of MisoStory yet." % dest)
	if charged > 0:
		lines.append("You paid the %s-meso fare." % ScreenKit.thousands(charged))
	else:
		lines.append("You stay in Southperry, and the %s-meso fare was not taken." % ScreenKit.thousands(fare))
	return "\n\n".join(lines)


func _fill() -> void:
	body_label.text = body_for(departure)
	var c := _character()
	var content := _db()
	var region := String(departure.get("region", ""))
	var unfinished: Array = []
	for q: Variant in departure.get("unfinished_quests", []):
		unfinished.append(String(q))
	var total := 0
	if content != null:
		for qid: String in content.ids("quests"):
			if region == "" or String(content.quest(qid).get("region", "")) == region:
				total += 1
	var stats := PackedStringArray()
	if c != null:
		stats.append("Level %d" % c.level)
		stats.append("%s mesos" % ScreenKit.thousands(c.mesos))
	if total > 0:
		stats.append("%s quests completed: %d of %d" % [region if region != "" else "All", total - unfinished.size(), total])
	stats_label.text = "  ·  ".join(stats)
	if unfinished.is_empty():
		quests_label.text = "Every %s quest is done." % region if region != "" else ""
	else:
		var names := PackedStringArray()
		for q: String in unfinished:
			names.append(String(content.quest(q).get("name", q)) if content != null else q)
		quests_label.text = "Still unfinished: %s." % ", ".join(names)
	quests_label.visible = quests_label.text != ""


## Follows the NpcInteraction (Game.npc_talk or talk_provider): connects its departure_requested. Called every frame.
func bind() -> void:
	var t := _talk()
	if t == _bound:
		return
	if _bound != null and is_instance_valid(_bound) and _bound.departure_requested.is_connected(_on_departure):
		_bound.departure_requested.disconnect(_on_departure)
	_bound = t
	if _bound != null and not _bound.departure_requested.is_connected(_on_departure):
		_bound.departure_requested.connect(_on_departure)


func _on_departure(_npc_id: String, dep: Dictionary) -> void:
	open(dep)


## Space (a jump key) and key repeat never press the button, as on the death notice: the Y / Enter that answered
## Shanks must not dismiss the screen at once.
func _filter_button_input(event: InputEvent) -> void:
	if event is InputEventKey and DeathNotice.ignores_key(event as InputEventKey):
		continue_button.accept_event()


func _talk() -> NpcInteraction:
	if talk_provider.is_valid():
		var v: Variant = talk_provider.call()
		return v if v is NpcInteraction else null
	var game := _autoload("Game")
	var t: Variant = game.get("npc_talk") if game != null else null
	return t if t is NpcInteraction else null


func _character() -> CharacterState:
	if character_provider.is_valid():
		var v: Variant = character_provider.call()
		return v if v is CharacterState else null
	var game := _autoload("Game")
	var c: Variant = game.get("character") if game != null else null
	return c if c is CharacterState else null


func _db() -> ContentDB:
	if db != null:
		return db
	var data := _autoload("Data")
	var d: Variant = data.get("db") if data != null else null
	return d if d is ContentDB else null


func _game_ctx() -> GameContext:
	if shell != null and is_instance_valid(shell) and shell.has_method("ctx"):
		var c: Variant = shell.call("ctx")
		return c if c is GameContext else null
	return null


static func _wrapping(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(580, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func _autoload(autoload_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(autoload_name) if tree != null else null
