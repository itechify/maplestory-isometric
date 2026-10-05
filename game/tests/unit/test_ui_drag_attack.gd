extends TestCase
## UI drags and the player's attack. The left mouse button is an attack binding (Controls), and the UI's drags start
## with it held: an item dragged out of the inventory, a window dragged by its title. PlayerCombat counts the mouse
## only through presses no GUI control consumed, outside a GUI drag (MouseAttackGate), so the UI leaves the "attack"
## action alone: a drag across the world never swings, and an attack key held meanwhile (J) keeps repeating.
##
## The real windows scene (MisoWindowsRoot) sits over a MonsterTestRig world; events go through
## Input.parse_input_event, the game's path, with viewport points mapped through the root's final transform
## (headless scales the window). As in test_player_combat_mouse, the suite runs inside one process frame, where
## Input.is_action_just_pressed stays true once "attack" was pressed, so every case counts attacks from its own start.

var rig: MonsterTestRig
var layer: CanvasLayer
var root: MisoWindowsRoot
## The last pointer position sent (viewport coordinates), for the motion events' `relative`.
var _pointer := Vector2.ZERO


func before_each() -> void:
	_release_all()
	rig = MonsterTestRig.create(db(), 11)
	rig.floor(40.0)
	rig.set_weapon("541")
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	p.set_input_source(KeyboardInput.new())
	rig.tick()  # PlayerCombat wraps the keyboard in its AttackLockInput
	ItemService.new(rig.character(), db(), null).gain("270", 3)
	layer = CanvasLayer.new()
	layer.name = "DragAttackUI"
	rig.w.host.add_child(layer)
	root = load("res://scenes/ui/windows.tscn").instantiate()
	root.configure(MisoUiEnv.isolated(rig.character(), db(), rig.bus, null, rig.game))
	layer.add_child(root)
	_ready_to_attack()


func after_each() -> void:
	if _vp().gui_is_dragging():
		_vp().gui_cancel_drag()
	_release_all()
	rig.free_all()


func _pc() -> PlayerCombat:
	return rig.system.player_combat


func _vp() -> Viewport:
	return (Engine.get_main_loop() as SceneTree).root


## Ticks from one attack until just after the next one a held input fires.
func _repeat_ticks() -> int:
	return int(ceil(_pc().last_lockout_s / MonsterTestRig.TICK)) + 2


func _ready_to_attack() -> void:
	_pc().lockout_left = 0.0
	_pc().set("_buffered", 0.0)


## Lays a window out now (containers sort deferred) so its controls have their real rects.
func _layout(w: MisoWindow) -> void:
	w.reset_size()
	w.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)


## A point of the viewport no open window covers: the world.
func _world_point() -> Vector2:
	var size := _vp().get_visible_rect().size
	for f: Vector2 in [Vector2(0.45, 0.8), Vector2(0.3, 0.6), Vector2(0.55, 0.5), Vector2(0.2, 0.9)]:
		var at := size * f
		var covered := false
		for w: MisoWindow in root.windows.values():
			if w.visible and w.get_global_rect().has_point(at):
				covered = true
		if not covered:
			return at
	return Vector2(-1, -1)


func _mouse(at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	ev.position = _vp().get_final_transform() * at
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	_pointer = at


func _move(at: Vector2, held: bool) -> void:
	var xf := _vp().get_final_transform()
	var ev := InputEventMouseMotion.new()
	ev.position = xf * at
	ev.global_position = ev.position
	ev.relative = ev.position - xf * _pointer
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	_pointer = at


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _release_all() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_mouse(_pointer, false)
	for k: Key in [KEY_J, KEY_CTRL]:
		if Input.is_physical_key_pressed(k):
			_key(k, false)
	if InputMap.has_action(&"attack"):
		Input.action_release(&"attack")


## Presses on the first Use slot of the open inventory and drags the potion out over the world (a real GUI drag:
## MisoItemSlot._get_drag_data runs). Returns the world point.
func _drag_potion_to_world() -> Vector2:
	root.open_window("inventory")
	root.inventory.select_tab("use")
	_layout(root.inventory)
	var slot: MisoItemSlot = root.inventory.slots[0]
	assert_eq(slot.item_id, "270", "the potion is in the first Use slot")
	var world := _world_point()
	assert_true(world.x >= 0.0, "a world point no window covers")
	_move(world, false)
	assert_true(_vp().gui_get_hovered_control() == null, "the world point hovers no control")
	var at := slot.get_global_rect().get_center()
	_move(at, false)
	_mouse(at, true)
	assert_eq(root.inventory.selected_index, 0, "the slot got the press (it selected it)")
	_move(at + Vector2(24, 0), true)
	_move(world, true)
	assert_true(_vp().gui_is_dragging(), "a real GUI drag runs")
	return world


func test_an_item_dragged_across_the_world_never_swings() -> void:
	var pc := _pc()
	var before := pc.attacks
	var world := _drag_potion_to_world()
	assert_true(Input.is_action_pressed(&"attack"), "the drag leaves the attack action alone (the button is still down)")
	rig.tick()
	assert_eq(pc.attacks, before, "the press that started the drag never swings")
	rig.run(_repeat_ticks())
	assert_eq(pc.attacks, before, "nor does holding it over the world")
	_mouse(world, false)
	assert_false(_vp().gui_is_dragging(), "dropped on the world: the drag ends")
	rig.tick()
	assert_eq(pc.attacks, before, "nor its release over the world")
	assert_eq(rig.character().inventory.count("270"), 3, "dropping on the world changes nothing")
	# Nothing lingers: the next click on the world swings.
	_ready_to_attack()
	_mouse(world, true)
	rig.tick()
	assert_eq(pc.attacks, before + 1, "a later world click attacks")
	_mouse(world, false)


func test_held_j_keeps_repeating_through_an_item_drag() -> void:
	var pc := _pc()
	var before := pc.attacks
	_key(KEY_J, true)
	rig.tick()
	assert_eq(pc.attacks, before + 1, "J attacks")
	var world := _drag_potion_to_world()
	assert_true(Input.is_action_pressed(&"attack"), "J still holds the attack action while the item is dragged")
	rig.run(_repeat_ticks())
	assert_eq(pc.attacks, before + 2, "held J repeats at the lockout rate during the drag")
	_mouse(world, false)
	rig.run(_repeat_ticks())
	assert_eq(pc.attacks, before + 3, "and after the drop")
	_key(KEY_J, false)
	rig.run(_repeat_ticks())
	assert_eq(pc.attacks, before + 3, "released: no more swings")


func test_a_window_dragged_by_its_title_across_the_world_never_swings() -> void:
	var pc := _pc()
	root.open_window("stats")
	var w := root.stats
	_layout(w)
	var start := w.position
	var grab := w.title_label.get_global_rect().get_center()
	var world := _world_point()
	assert_true(world.x >= 0.0, "a world point no window covers")
	var before := pc.attacks
	_move(grab, false)
	_mouse(grab, true)
	_move(world, true)
	assert_ne(w.position, start, "the window follows the pointer")
	assert_true(Input.is_action_pressed(&"attack"), "the title press leaves the attack action alone")
	rig.tick()
	assert_eq(pc.attacks, before, "a title press never swings")
	# Clamped at the screen edge, the pointer leaves the window over the world with the button held.
	_move(world + Vector2(5000, 5000), true)
	var area := _vp().get_visible_rect().size
	assert_eq(w.position.x, area.x - w.size.x, "clamped to the right edge")
	rig.run(_repeat_ticks())
	assert_eq(pc.attacks, before, "nor does holding it while the window is dragged")
	# Held J next to the title drag repeats.
	_key(KEY_J, true)
	rig.tick()
	assert_eq(pc.attacks, before + 1, "J attacks during the title drag")
	rig.run(_repeat_ticks())
	assert_eq(pc.attacks, before + 2, "and repeats while held")
	_key(KEY_J, false)
	_mouse(_pointer, false)
	rig.run(_repeat_ticks())
	assert_eq(pc.attacks, before + 2, "the release over the world never swings")
