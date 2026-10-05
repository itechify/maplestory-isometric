class_name MisoWindowsRoot
extends Control
## Root of res://scenes/ui/windows.tscn: the character windows (Inventory, Equipment, Character Stats, Quest Log,
## Skills), their hotkeys (toggle_inventory / toggle_equipment / toggle_stats / toggle_quests / toggle_skills from
## Controls) and the shared item tooltip. Windows are non-modal: the player keeps control while they are open. Each window registers with
## the GameContext window stack when it opens and closes, so the shell's Esc ("menu") closes the newest first.
##
## Integration: the shell instantiates this scene under ctx.ui_root and calls setup(ctx). Without setup() (a
## sandbox) the root runs standalone against the Game / Data / Events autoloads with a private window stack, and
## then handles Esc itself. Tests call configure(MisoUiEnv.isolated(...)).
##
## Other UI can open windows without knowing this node: get_tree().call_group(&"miso_windows", &"toggle_window",
## "inventory"), or by sending the toggle_* input action.

const GROUP := &"miso_windows"
## Input action -> window name.
const ACTIONS := {
	"toggle_inventory": "inventory",
	"toggle_equipment": "equipment",
	"toggle_stats": "stats",
	"toggle_quests": "quests",
	"toggle_skills": "skills",
}
## Where each window first appears (presentation only): Character Stats and the Quest Log side by side from the left
## edge, the Item Inventory (classic: bags on the right) and Equipment side by side from the right edge, each placed
## from the windows' measured widths so the four never overlap on the 1600 x 900 base viewport (or anything wider).
## The five windows are wider together than the screen, so the Skills window opens under the Quest Log (BELOW: window
## -> the window it sits under, left-aligned, WINDOW_GAP lower, pulled up to stay on screen). A window not listed
## anywhere opens at FALLBACK_X.
const LEFT_ROW: PackedStringArray = ["stats", "quests"]
## Listed from the right edge inward.
const RIGHT_ROW: PackedStringArray = ["inventory", "equipment"]
const BELOW := {"skills": "quests"}
const EDGE_MARGIN := 16.0
const WINDOW_GAP := 10.0
## Top edge of a newly placed window, as a fraction of the viewport height.
const TOP_FRACTION := 0.08
const FALLBACK_X := 0.3

## Bus signal -> handler.
const BUS_HANDLERS := {
	"inventory_changed": "_on_inventory_changed",
	"equipment_changed": "_on_equipment_changed",
	"stats_changed": "_on_stats_changed",
	"hp_changed": "_on_vitals_changed",
	"mp_changed": "_on_vitals_changed",
	"exp_gained": "_on_exp_gained",
	"leveled_up": "_on_leveled_up",
	"mesos_changed": "_on_mesos_changed",
	"item_gained": "_on_item_count_changed",
	"item_lost": "_on_item_count_changed",
	"quest_started": "_on_quest_event",
	"quest_progressed": "_on_quest_event",
	"quest_completed": "_on_quest_event",
	"quest_forfeited": "_on_quest_event",
	"map_entered": "_on_map_entered",
	"game_loaded": "_on_game_loaded",
	"skill_leveled": "_on_skill_leveled",
}

var env: MisoUiEnv = null
## name -> MisoWindow
var windows: Dictionary = {}
var inventory: MisoInventoryWindow
var equipment: MisoEquipmentWindow
var stats: MisoStatsWindow
var quests: MisoQuestWindow
var skills: MisoSkillsWindow
var tooltip: MisoItemTooltip
var _placed: Dictionary = {}
var _configured_by_setup := false


func _init() -> void:
	name = "Windows"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	theme = MisoTheme.get_theme()
	inventory = MisoInventoryWindow.new()
	equipment = MisoEquipmentWindow.new()
	stats = MisoStatsWindow.new()
	quests = MisoQuestWindow.new()
	skills = MisoSkillsWindow.new()
	for w: MisoWindow in [stats, quests, skills, equipment, inventory]:
		windows[w.window_name] = w
		add_child(w)
		w.opened.connect(_on_window_opened)
	inventory.tooltip_host = self
	equipment.tooltip_host = self
	tooltip = MisoItemTooltip.new()
	tooltip.top_level = true
	add_child(tooltip)


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(MisoQuickslots.GROUP)
	if env == null:
		configure(MisoUiEnv.standalone())


## Re-entering the tree (a reparent) reconnects what _exit_tree disconnected (connections are idempotent) and
## redraws whatever changed meanwhile.
func _enter_tree() -> void:
	if env != null:
		_bind()
		refresh_open()


func _exit_tree() -> void:
	_unbind()


## The shell's integration call (GameContext contract).
func setup(ctx: GameContext) -> void:
	_configured_by_setup = true
	configure(MisoUiEnv.from_ctx(ctx))


## Points every window at an environment (setup, standalone and tests all end here).
func configure(e: MisoUiEnv) -> void:
	_unbind()
	env = e
	for w: MisoWindow in windows.values():
		w.env = e
	_bind()
	refresh_open()


func window_by_name(window_name: String) -> MisoWindow:
	return windows.get(window_name, null)


func open_window(window_name: String) -> void:
	var w := window_by_name(window_name)
	if w != null:
		w.open()


func close_window(window_name: String) -> void:
	var w := window_by_name(window_name)
	if w != null:
		w.close()


func toggle_window(window_name: String) -> void:
	var w := window_by_name(window_name)
	if w != null:
		w.toggle()


func is_open(window_name: String) -> bool:
	var w := window_by_name(window_name)
	return w != null and w.visible


## Closes every window (e.g. before a cutscene or the title screen).
func close_all() -> void:
	for w: MisoWindow in windows.values():
		w.close()


## Redraws the open windows from the live state.
func refresh_open() -> void:
	for w: MisoWindow in windows.values():
		if w.visible:
			w.refresh()


## MisoQuickslots group hook: the inventory's quickslot hints follow binding changes.
func refresh_quickslots() -> void:
	if inventory.visible:
		inventory.refresh()
	if skills.visible:
		skills.refresh()


# --- tooltip host -----------------------------------------------------------------------------------------------

## Shows the item card beside `anchor` (a slot) without covering it (MisoItemTooltip.place_beside): right of the slot,
## or left of it when the right side does not fit (the right-docked inventory, the Equipment doll next to it).
func show_item_tooltip(item_id: String, opts: Dictionary, anchor: Control) -> void:
	if env == null:
		return
	tooltip.show_item(item_id, env.character(), env.get_db(), opts)
	var bounds := get_viewport_rect() if is_inside_tree() else Rect2(Vector2.ZERO, Vector2(1600, 900))
	if anchor != null:
		tooltip.place_beside(anchor.get_global_rect(), bounds)
	else:
		tooltip.place_near(Vector2.ZERO, bounds)


func hide_item_tooltip() -> void:
	tooltip.visible = false


# --- input ------------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if env == null or env.is_modal_active():
		return
	if not (event is InputEventKey or event is InputEventAction or event is InputEventJoypadButton):
		return
	for action: String in ACTIONS:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			toggle_window(ACTIONS[action])
			get_viewport().set_input_as_handled()
			return
	# Standalone only: the shell owns Esc in the game (ctx.close_top_window()).
	if env.owns_ctx and InputMap.has_action("menu") and event.is_action_pressed("menu"):
		if env.ctx.close_top_window():
			get_viewport().set_input_as_handled()


# --- events -----------------------------------------------------------------------------------------------------

func _bind() -> void:
	if env == null:
		return
	for sig: String in BUS_HANDLERS:
		env.connect_bus(sig, Callable(self, BUS_HANDLERS[sig]))
	env.connect_character_replaced(_on_character_replaced)


func _unbind() -> void:
	if env == null:
		return
	for sig: String in BUS_HANDLERS:
		env.disconnect_bus(sig, Callable(self, BUS_HANDLERS[sig]))
	env.disconnect_character_replaced(_on_character_replaced)


func _refresh_if_open(names: Array) -> void:
	for n in names:
		var w := window_by_name(String(n))
		if w != null and w.visible:
			w.refresh()


func _on_inventory_changed() -> void:
	_refresh_if_open(["inventory", "quests"])


func _on_equipment_changed(_slot: String) -> void:
	_refresh_if_open(["equipment", "stats", "inventory"])


func _on_stats_changed() -> void:
	_refresh_if_open(["stats", "equipment", "skills"])


func _on_vitals_changed(_v: int, _max_v: int) -> void:
	_refresh_if_open(["stats"])


func _on_skill_leveled(_skill_id: String, _level: int) -> void:
	_refresh_if_open(["skills", "stats"])


func _on_exp_gained(_amount: int, _source: String) -> void:
	_refresh_if_open(["stats"])


func _on_leveled_up(_level: int) -> void:
	_refresh_if_open(["stats", "quests", "skills"])


func _on_mesos_changed(_mesos: int, _delta: int) -> void:
	_refresh_if_open(["inventory"])


func _on_item_count_changed(_item_id: String, _qty: int) -> void:
	_refresh_if_open(["quests"])


func _on_quest_event(_quest_id: String) -> void:
	_refresh_if_open(["quests"])


func _on_map_entered(_map_id: String, _previous: String) -> void:
	_refresh_if_open(["quests"])


func _on_game_loaded(_slot: String) -> void:
	refresh_open()


func _on_character_replaced(_reason: String) -> void:
	hide_item_tooltip()
	skills.selected = ""
	refresh_open()


func _on_window_opened(w: MisoWindow) -> void:
	if _placed.has(w.window_name):
		return
	_placed[w.window_name] = true
	w.position = default_position(w.window_name)


## The top-left corner a window gets the first time it opens (see LEFT_ROW / RIGHT_ROW / BELOW).
func default_position(window_name: String) -> Vector2:
	var area := get_viewport_rect().size if is_inside_tree() else Vector2(1600, 900)
	var y := roundf(area.y * TOP_FRACTION)
	if BELOW.has(window_name):
		var anchor := String(BELOW[window_name])
		var above := default_position(anchor)
		var below_y := above.y + window_size(anchor).y + WINDOW_GAP
		var h := window_size(window_name).y
		return Vector2(above.x, roundf(maxf(y, minf(below_y, area.y - h - EDGE_MARGIN))))
	if window_name in LEFT_ROW:
		var x := EDGE_MARGIN
		for n in LEFT_ROW:
			if n == window_name:
				break
			x += window_width(n) + WINDOW_GAP
		return Vector2(roundf(x), y)
	if window_name in RIGHT_ROW:
		var x := area.x - EDGE_MARGIN
		for n in RIGHT_ROW:
			x -= window_width(n)
			if n == window_name:
				break
			x -= WINDOW_GAP
		return Vector2(roundf(maxf(0.0, x)), y)
	return Vector2(roundf(area.x * FALLBACK_X), y)


## A window's laid-out width: built and filled (so the slot grid and the doll count), never below its minimum.
func window_width(window_name: String) -> float:
	return window_size(window_name).x


## A window's laid-out size: built and filled, never below its minimum.
func window_size(window_name: String) -> Vector2:
	var w := window_by_name(window_name)
	if w == null:
		return Vector2.ZERO
	if not w.visible:
		w.refresh()
	return w.size.max(w.get_combined_minimum_size())
