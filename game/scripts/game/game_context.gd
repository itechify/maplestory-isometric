class_name GameContext
extends RefCounted
## What the main game scene hands every gameplay subsystem (monsters, loot, interaction, HUD, windows, NPC UI,
## debug). Each subsystem's root node implements `func setup(ctx: GameContext) -> void`; the main scene calls it once
## the world is loaded and the player exists. Subsystems must also run standalone in their own sandbox scenes, so they
## treat any null reference as "not available" rather than crashing.
##
## CONTRACT, owned by the game shell. Fields and method signatures are fixed; the shell may add more.

## Emitted when the first modal opens (true) or the last one closes (false).
signal modal_changed(active: bool)
## Emitted when a window opens or closes (UI systems use it to keep one window per name).
signal window_changed(window: Control, open: bool)

## The main scene root.
var main: Node = null
## IslandWorld (res://scenes/world/world.tscn).
var world: Node = null
## PlayerController (res://scenes/actors/player.tscn).
var player: Node = null
## CameraRig (res://scenes/actors/camera_rig.tscn).
var camera: Node = null
## CanvasLayer that HUD, windows, dialogue and screens are added to.
var ui_root: CanvasLayer = null
## Parent node for gameplay system nodes (monster system, loot system, interaction system).
var systems: Node = null

var _modals: Array[Object] = []
var _windows: Array[Control] = []


# --- modal input ----------------------------------------------------------------------------------------------
# A modal (dialogue, shop, console, pause menu, character creation) takes the keyboard away from the player.
# Non-modal windows (inventory, equipment, stats, quest log) do not: you can walk with them open, as in classic.

func push_modal(owner: Object) -> void:
	if owner in _modals:
		return
	_modals.append(owner)
	if _modals.size() == 1:
		_apply_player_input()
		modal_changed.emit(true)


func pop_modal(owner: Object) -> void:
	if not (owner in _modals):
		return
	_modals.erase(owner)
	if _modals.is_empty():
		_apply_player_input()
		modal_changed.emit(false)


func is_modal_active() -> bool:
	return not _modals.is_empty()


func _apply_player_input() -> void:
	if player == null or not player.has_method("set_input_enabled"):
		return
	if _modals.is_empty():
		# Only hand control back when no map transition owns the player (MapSession freezes input during warps).
		var tree := Engine.get_main_loop() as SceneTree
		var session: Node = tree.root.get_node_or_null(^"/root/MapSession") if tree != null else null
		if session == null or not session.has_method("is_idle") or bool(session.call("is_idle")):
			player.call("set_input_enabled", true)
	else:
		player.call("set_input_enabled", false)


# --- windows --------------------------------------------------------------------------------------------------
# Every UI window registers when it opens and closes, so the "menu" action (Esc) closes the most recent window first
# and only opens the pause menu when nothing else is open.

func window_opened(w: Control) -> void:
	_windows.erase(w)
	_windows.append(w)
	window_changed.emit(w, true)


func window_closed(w: Control) -> void:
	if w in _windows:
		_windows.erase(w)
		window_changed.emit(w, false)


func has_open_windows() -> bool:
	return not _windows.is_empty()


## Closes the most recently opened window (its close() if it has one, else hide()). Returns false if none was open.
func close_top_window() -> bool:
	while not _windows.is_empty():
		var w: Control = _windows.pop_back()
		if not is_instance_valid(w) or not w.visible:
			continue
		if w.has_method("close"):
			w.call("close")
		else:
			w.hide()
		window_changed.emit(w, false)
		return true
	return false
