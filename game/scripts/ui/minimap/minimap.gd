class_name MisoMinimap
extends PanelContainer
## Root of res://scenes/ui/minimap.tscn: the minimap (brief Phase 11), top left of the screen.
##   - title strip: the canonical street (gold) above the canonical map name, always shown, so the map name stays on
##     screen after the arrival banner fades; the canonical map id beside them while the debug overlay is on
##     (Debug.overlay_enabled / overlay_toggled, F3);
##   - the map (MisoMinimapView): the map's walkable ground as the gameplay camera sees it (MinimapModel), its visible
##     portals with destination names, its NPCs with their quest-marker state and shop or transport icon, the
##     player's arrow and the trail stubs.
## M (toggle_minimap) folds the map away to the title strip and back (the "-" / "+" button does the same); nothing
## happens while a modal (dialogue, shop, console, menu) owns the keyboard. Folded or not survives map changes and
## loads for the session. Normal play never needs the debug console for any of it.
##
## Integration: the shell instantiates this scene under ctx.ui_root after the HUD (so windows draw above it) and calls
## setup(ctx): the world (ctx.world: defs and ground_faces), the player (ctx.player: global_position, facing) and the
## camera rig (ctx.camera: view_basis) come from the context; the character, quests, map session and bus from
## MisoUiEnv. Tests call configure(env) with `world`, `player` and `debug` stand-ins set first.
## Rebuilt on Events.map_entered / game_loaded / Game.character_replaced (models cached per map id); quest markers
## re-read on quest, item and level events and every MARKER_REFRESH_S; the player's arrow every PLAYER_REFRESH_S.

const GROUP := &"miso_minimap"
const ACTION := "toggle_minimap"
const PLAYER_REFRESH_S := 1.0 / 15.0
const MARKER_REFRESH_S := 0.5
const SCREEN_OFFSET := Vector2(12, 12)
## Separator between the street and the map name in title_text().
const TITLE_SEPARATOR := " · "

## Bus signal -> handler.
const BUS_HANDLERS := {
	"map_entered": "_on_map_entered",
	"game_loaded": "_on_game_loaded",
	"quest_started": "_on_quests_changed",
	"quest_progressed": "_on_quests_changed",
	"quest_completed": "_on_quests_changed",
	"quest_forfeited": "_on_quests_changed",
	"item_gained": "_on_items_changed",
	"item_lost": "_on_items_changed",
	"leveled_up": "_on_level_changed",
}
## MapSession signal -> handler.
const SESSION_HANDLERS := {
	"trail_changed": "_on_trail_changed",
}

var env: MisoUiEnv = null
## IslandWorld, or a stand-in with `defs` (MapDefinitions) and optionally ground_faces(map_id).
var world: Object = null
## The player body (global_position, optional facing); null hides the arrow.
var player: Node3D = null
## The camera rig (optional view_basis); null = the map sidecar's gameplay camera.
var camera_rig: Object = null
## The Debug autoload or a stand-in with overlay_enabled and the overlay_toggled(on) signal; null = the autoload.
var debug: Object = null

var title_box: VBoxContainer
var street_label: Label
var name_label: Label
var id_label: Label
var fold_button: Button
var view: MisoMinimapView
## The map the minimap shows ("" before the first map).
var map_id: String = ""
var expanded: bool = true

var _models: Dictionary = {}
var _player_t: float = 0.0
var _marker_t: float = 0.0
var _states: Dictionary = {}
var _debug_bound: Object = null


func _init() -> void:
	name = "Minimap"
	theme = MisoTheme.get_theme()
	theme_type_variation = &"MisoHud"
	mouse_filter = MOUSE_FILTER_STOP
	position = SCREEN_OFFSET
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(row)
	title_box = VBoxContainer.new()
	title_box.add_theme_constant_override("separation", -3)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(title_box)
	street_label = MisoTheme.make_label("", 12, MisoTheme.GOLD, 3, MisoTheme.WEIGHT_BOLD)
	title_box.add_child(street_label)
	name_label = MisoTheme.make_label("", 16, MisoTheme.TEXT, 4, MisoTheme.WEIGHT_BLACK)
	title_box.add_child(name_label)
	id_label = MisoTheme.make_label("", 11, MisoTheme.TEXT_DIM, 3, MisoTheme.WEIGHT_BOLD)
	id_label.visible = false
	title_box.add_child(id_label)
	fold_button = Button.new()
	fold_button.name = "Fold"
	fold_button.theme_type_variation = &"MisoFlatButton"
	fold_button.focus_mode = Control.FOCUS_NONE
	fold_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	fold_button.custom_minimum_size = Vector2(24, 22)
	fold_button.pressed.connect(toggle)
	row.add_child(fold_button)
	view = MisoMinimapView.new()
	col.add_child(view)
	_sync_fold()


func _ready() -> void:
	add_to_group(GROUP)
	if env == null:
		configure(MisoUiEnv.standalone())


func _enter_tree() -> void:
	if env != null:
		_bind()
		refresh_all()


func _exit_tree() -> void:
	_unbind()


## The shell's integration call (GameContext contract).
func setup(ctx: GameContext) -> void:
	if ctx != null:
		world = ctx.world
		player = ctx.player as Node3D
		camera_rig = ctx.camera
	configure(MisoUiEnv.from_ctx(ctx))


## Points the minimap at an environment (setup, standalone and tests end here) and redraws it for the current map.
func configure(e: MisoUiEnv) -> void:
	_unbind()
	env = e
	_bind()
	refresh_all()


## Rebuilds for the current map (env.current_map_id()) and re-reads everything dynamic.
func refresh_all() -> void:
	show_map(env.current_map_id() if env != null else "")


## Shows `id` (a canonical map id; "" or an unknown map shows the bare title strip).
func show_map(id: String) -> void:
	map_id = id
	_update_title()
	view.set_model(model_for(id))
	refresh_markers()
	refresh_player()
	reset_size()


## The model of a map, built once per map id (null when the world does not know the map).
func model_for(id: String) -> MinimapModel:
	if id == "":
		return null
	if _models.has(id):
		return _models[id]
	var defs := _defs()
	var def := defs.get_def(id) if defs != null else null
	if def == null:
		return null
	var faces := PackedVector3Array()
	if world != null and world.has_method("ground_faces"):
		faces = world.call("ground_faces", id)
	var m := MinimapModel.build(def, defs, env.get_db() if env != null else null, faces,
		MinimapProjection.for_map(def, _live_basis()))
	# A world still loading has no collision yet: its footprint model is not kept, the built world's will be.
	if world == null or world.get("is_built") != false:
		_models[id] = m
	return m


## M: folds the map away to the title strip, or unfolds it.
func toggle() -> void:
	set_expanded(not expanded)


func set_expanded(on: bool) -> void:
	expanded = on
	_sync_fold()
	if expanded:
		refresh_player()
	reset_size()


func is_expanded() -> bool:
	return expanded


## "<street> · <name>", plus " [<map id>]" while the debug overlay is on. "" before the first map.
func title_text() -> String:
	if name_label.text == "":
		return ""
	var t := name_label.text if street_label.text == "" else street_label.text + TITLE_SEPARATOR + name_label.text
	return t + (" [%s]" % map_id if id_label.visible else "")


## True while the debug overlay is on (the "debug mode" that shows the canonical map id).
func debug_mode() -> bool:
	var d := _debug()
	return d != null and bool(d.get("overlay_enabled"))


## Re-reads every NPC's quest marker (QuestEngine.npc_marker, the rule the markers over the NPCs' heads use).
func refresh_markers() -> void:
	_states = {}
	var engine := env.quest_engine() if env != null else null
	if view.model != null and engine != null:
		for n: Dictionary in view.model.npcs:
			_states[n["npc_id"]] = engine.npc_marker(String(n["npc_id"]))
	refresh_player()


## Moves the player's arrow (and the trail tag) to where the player is now.
func refresh_player() -> void:
	var ok := player != null and is_instance_valid(player) and player.is_inside_tree()
	var pos := player.global_position if ok else Vector3.ZERO
	var facing := Vector3.ZERO
	if ok and "facing" in player and player.get("facing") is Vector3:
		facing = player.get("facing")
	var dest := env.trail_destination() if env != null else ""
	view.update_dynamic(ok, pos, facing, MisoMapBanner.map_name(dest, env.get_db()) if dest != "" and env != null else "",
		_states)


## What the minimap shows now, for playtests and tests: {map_id, title, expanded, debug_id, portals (ids), portal_dests
## (map ids), shop_doors (ids), npcs (ids), markers ({npc id: state}), roles ({npc id: role}), labels (portal ids
## with a drawn name), ground (triangles), ground_source, player_in_view, player_clamped, trail_tag}.
func snapshot() -> Dictionary:
	var m := view.model
	var pm := view.player_marker()
	var labels := PackedStringArray()
	for l: Dictionary in view.label_layout():
		labels.append(String(l["id"]))
	var out := {"map_id": map_id, "title": title_text(), "expanded": expanded, "debug_id": id_label.visible,
		"portals": PackedStringArray(), "portal_dests": PackedStringArray(), "shop_doors": PackedStringArray(),
		"npcs": PackedStringArray(), "markers": _states.duplicate(), "roles": {}, "labels": labels,
		"ground": m.ground_count() if m != null else 0, "ground_source": m.ground_source if m != null else "",
		"player_in_view": bool(pm.get("in_view", false)), "player_clamped": bool(pm.get("clamped", false)),
		"trail_tag": view.trail_dest_name}
	if m == null:
		return out
	var shops := PackedStringArray()
	var dests := PackedStringArray()
	for p: Dictionary in m.portals:
		dests.append(String(p["dest_map_id"]))
		if bool(p["dest_shop"]):
			shops.append(String(p["id"]))
	out["portals"] = m.portal_ids()
	out["portal_dests"] = dests
	out["shop_doors"] = shops
	out["npcs"] = m.npc_ids()
	for n: Dictionary in m.npcs:
		if String(n["role"]) != "":
			out["roles"][n["npc_id"]] = n["role"]
	return out


func _process(delta: float) -> void:
	advance(delta)


## Advances the refresh timers (tests call it directly).
func advance(delta: float) -> void:
	if not expanded:
		return
	_marker_t -= delta
	if _marker_t <= 0.0:
		_marker_t = MARKER_REFRESH_S
		refresh_markers()
		_player_t = PLAYER_REFRESH_S
		return
	_player_t -= delta
	if _player_t <= 0.0:
		_player_t = PLAYER_REFRESH_S
		refresh_player()


func _unhandled_input(event: InputEvent) -> void:
	if env == null or env.is_modal_active():
		return
	if not (event is InputEventKey or event is InputEventAction or event is InputEventJoypadButton):
		return
	if InputMap.has_action(ACTION) and event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()


# --- events ---------------------------------------------------------------------------------------------------

func _bind() -> void:
	if env == null:
		return
	for sig: String in BUS_HANDLERS:
		env.connect_bus(sig, Callable(self, BUS_HANDLERS[sig]))
	for sig: String in SESSION_HANDLERS:
		env.connect_session(sig, Callable(self, SESSION_HANDLERS[sig]))
	env.connect_character_replaced(_on_character_replaced)
	var d := _debug()
	if d != null and d.has_signal("overlay_toggled") and not d.is_connected("overlay_toggled", _on_overlay_toggled):
		d.connect("overlay_toggled", _on_overlay_toggled)
		_debug_bound = d


func _unbind() -> void:
	if env == null:
		return
	for sig: String in BUS_HANDLERS:
		env.disconnect_bus(sig, Callable(self, BUS_HANDLERS[sig]))
	for sig: String in SESSION_HANDLERS:
		env.disconnect_session(sig, Callable(self, SESSION_HANDLERS[sig]))
	env.disconnect_character_replaced(_on_character_replaced)
	if _debug_bound != null and is_instance_valid(_debug_bound) and _debug_bound.is_connected("overlay_toggled", _on_overlay_toggled):
		_debug_bound.disconnect("overlay_toggled", _on_overlay_toggled)
	_debug_bound = null


func _on_map_entered(id: String, _previous: String) -> void:
	show_map(id)


func _on_game_loaded(_slot: String) -> void:
	refresh_all()


func _on_character_replaced(_reason: String) -> void:
	refresh_all()


func _on_quests_changed(_quest_id: String) -> void:
	refresh_markers()


func _on_items_changed(_item_id: String, _qty: int) -> void:
	refresh_markers()


func _on_level_changed(_level: int) -> void:
	refresh_markers()


func _on_trail_changed(_dest_map_id: String) -> void:
	refresh_player()


func _on_overlay_toggled(_on: bool) -> void:
	_update_title()
	reset_size()


# --- internals ------------------------------------------------------------------------------------------------

func _update_title() -> void:
	var rec: Dictionary = {}
	var db := env.get_db() if env != null else null
	if db != null and map_id != "" and db.has("maps", map_id):
		rec = db.map(map_id)
	var street: Variant = rec.get("street_name", "")
	street_label.text = String(street) if street != null else ""
	street_label.visible = street_label.text != ""
	name_label.text = String(rec.get("name", map_id))
	id_label.text = map_id
	id_label.visible = map_id != "" and debug_mode()


func _sync_fold() -> void:
	view.visible = expanded
	var key := MisoUiEnv.key_label(ACTION)
	fold_button.text = "-" if expanded else "+"
	fold_button.tooltip_text = "%s the minimap%s" % ["Hide" if expanded else "Show", " (%s)" % key if key != "" else ""]


func _defs() -> MapDefinitions:
	if world == null:
		return null
	var d: Variant = world.get("defs")
	return d if d is MapDefinitions else null


func _live_basis() -> Basis:
	if camera_rig == null or not is_instance_valid(camera_rig):
		return Basis.IDENTITY
	var b: Variant = camera_rig.get("view_basis")
	return b if b is Basis else Basis.IDENTITY


func _debug() -> Object:
	if debug != null:
		return debug
	return env.autoload("Debug") if env != null else null
