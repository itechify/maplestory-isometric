class_name DebugUI
extends CanvasLayer
## The debug tools' root (res://scenes/debug/debug_ui.tscn): the console (` toggles, modal while open) and the overlay
## (F3). The game shell instantiates it under ctx.ui_root and calls setup(ctx); it also runs standalone, reading the
## autoloads (MapSession.world, its player and camera) when no context is given.
##
## Modal input: opening the console calls ctx.push_modal(self) and ctx.window_opened(console) (so the shell's Esc
## closes it as the newest window); closing pops both. Without a context the player's input is switched off directly
## (KeyboardInput polls Input, so typing would otherwise walk the player).

## Above every other CanvasLayer of the game: the HUD/windows (10), the death notice (90), the world's ScreenFader
## (100, which would otherwise darken the console during every warp) and the shell's screens (110: loading, pause
## menu), so the console stays readable while it owns the keyboard.
const CANVAS_LAYER := 120

var ctx: Object = null
var console: DebugConsole = null
var overlay: DebugOverlay = null
var dbg: DebugTools = null

var _player_input_off: Node = null
var _idle_source: BotInput = BotInput.new()
var _muted_player: Node = null
var _saved_source: Object = null
var _console_was_open: bool = false
## Nodes whose scripted _input the open console switched off (restored when it closes).
var _fenced: Array[Node] = []


func _init() -> void:
	layer = CANVAS_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = DebugOverlay.new()
	add_child(overlay)
	console = DebugConsole.new()
	add_child(console)


func _ready() -> void:
	if dbg == null:
		dbg = get_node_or_null("/root/Debug") as DebugTools
	console.bind(dbg)
	overlay.dbg = dbg
	overlay.refresh()
	console.opened.connect(_on_console_opened)
	console.closed.connect(_on_console_closed)
	if dbg != null:
		dbg.overlay_toggled.connect(_on_overlay_toggled)
		dbg.capture_state.connect(_on_capture_state)
		overlay.visible = dbg.overlay_enabled
	get_viewport().size_changed.connect(_place_overlay)


## The integration seam: wires the context into the Debug autoload (world, player, camera, modal input).
func setup(context: Object) -> void:
	ctx = context
	if dbg == null:
		dbg = get_node_or_null("/root/Debug") as DebugTools
	if dbg != null:
		dbg.attach_context(context)


func open_console() -> void:
	console.open()


func close_console() -> void:
	console.close()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event.is_action_pressed("debug_console"):
		console.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_overlay"):
		if dbg != null:
			dbg.set_overlay(not dbg.overlay_enabled)
		get_viewport().set_input_as_handled()
	elif console.is_open() and event.is_action_pressed("menu"):
		console.close()
		get_viewport().set_input_as_handled()


func _on_console_opened() -> void:
	if ctx != null and ctx.has_method("push_modal"):
		ctx.call("push_modal", self)
		if ctx.has_method("window_opened"):
			ctx.call("window_opened", console)
	else:
		var p: Node = dbg.get_player() if dbg != null else null
		if p != null and p.has_method("set_input_enabled"):
			p.call("set_input_enabled", false)
			_player_input_off = p
	_mute_player_source(true)
	_fence_input(true)
	_place_overlay()


func _on_console_closed() -> void:
	if ctx != null and ctx.has_method("pop_modal"):
		ctx.call("pop_modal", self)
		if ctx.has_method("window_closed"):
			ctx.call("window_closed", console)
	elif _player_input_off != null and is_instance_valid(_player_input_off):
		_player_input_off.call("set_input_enabled", true)
		_player_input_off = null
	_mute_player_source(false)
	_fence_input(false)
	_place_overlay()


## While the console is open it owns the keyboard (it is the newest modal). Other UI's `_input` handlers run before
## GUI focus, so an open NPC dialogue or shop (DialogueWindow / ShopWindow.handle_key) would otherwise take Enter,
## Space, Backspace, digits and WASD typed into the console: the command line loses letters and Enter advances the
## dialogue instead of running the command. The scripted `_input` of every node under the context's ui_root and
## systems (this UI excepted) is switched off while the console is open and switched back on when it closes.
func _fence_input(on: bool) -> void:
	if not on:
		for n in _fenced:
			if is_instance_valid(n):
				n.set_process_input(true)
		_fenced.clear()
		return
	for root in _fence_roots():
		for n in root.find_children("*", "", true, false):
			if n == self or is_ancestor_of(n) or not n.is_processing_input() or not DebugUI._scripted_input(n):
				continue
			n.set_process_input(false)
			_fenced.append(n)


## The subtrees whose key handlers the console fences: the context's ui_root and systems (none standalone).
func _fence_roots() -> Array[Node]:
	var out: Array[Node] = []
	if ctx == null or not is_instance_valid(ctx):
		return out
	for field in ["ui_root", "systems"]:
		var v: Variant = ctx.get(field)
		if v is Node and is_instance_valid(v) and not (v in out):
			out.append(v)
	return out


## True when the node's own script defines `_input` (built-in controls manage their own input processing).
static func _scripted_input(n: Node) -> bool:
	var s := n.get_script() as Script
	if s == null:
		return false
	for m in s.get_script_method_list():
		if String(m.get("name", "")) == "_input":
			return true
	return false


func _exit_tree() -> void:
	# Leaving with an open console (the session ends): close it through the normal path (modal and window popped,
	# player input, input source and fenced handlers handed back); the two calls after it are no-ops then.
	if console != null and console.is_open():
		console.close()
	_fence_input(false)
	_mute_player_source(false)


## While the console is open the player's innermost InputSource is swapped for an idle BotInput.
## set_input_enabled(false) gates only the controller; systems that read player.input_source themselves
## (PortalInteractor, PlayerCombat, LootSystem; docs/runtime/PLAYER_AND_CAMERA.md "Known issues") would otherwise see
## the Up/Down history keys as portal and ladder presses, and MapSession re-enables the controller at the end of every
## warp even while the console is open, so typed letters would walk the player.
##
## Decorators are walked: PlayerCombat wraps the real source in an AttackLockInput (`inner`) and re-wraps whatever
## the player's source is on its next physics tick. The idle source therefore replaces the innermost source, and
## closing puts the parked source back wherever the idle one sits by then (the player's own source or a decorator's
## `inner`), so the keyboard comes back whichever order the console and the decorator act in.
func _mute_player_source(on: bool) -> void:
	if on:
		if _muted_player != null:
			return
		var p: Node = dbg.get_player() if dbg != null else null
		if p == null or not p.has_method("set_input_source"):
			return
		var holder: Object = p
		var src: Variant = p.get("input_source")
		var guard := 0
		while src is Object and DebugUI._decorates(src as Object) and guard < 8:
			holder = src
			src = (src as Object).get("inner")
			guard += 1
		if src == _idle_source:
			return
		_muted_player = p
		_saved_source = src
		if holder == p:
			p.call("set_input_source", _idle_source)
		else:
			holder.set("inner", _idle_source)
	elif _muted_player != null:
		if is_instance_valid(_muted_player):
			DebugUI._put_back(_muted_player, _idle_source, _saved_source)
		_muted_player = null
		_saved_source = null


## True when `o` is an InputSource decorator (it has an `inner` InputSource), e.g. AttackLockInput.
static func _decorates(o: Object) -> bool:
	return o is InputSource and "inner" in o and o.get("inner") is InputSource


## Replaces `idle` with `saved` wherever it sits in the player's source chain. Returns true when it was found.
static func _put_back(p: Node, idle: Object, saved: Object) -> bool:
	var src: Variant = p.get("input_source")
	if src == idle:
		p.call("set_input_source", saved)
		return true
	var guard := 0
	while src is Object and "inner" in (src as Object) and guard < 8:
		var o := src as Object
		if o.get("inner") == idle:
			# A decorator never wraps itself: when the parked source is this very decorator (it had no inner of its
			# own), give it back its empty inner and make it the player's source again.
			if o == saved:
				o.set("inner", null)
				p.call("set_input_source", saved)
			else:
				o.set("inner", saved)
			return true
		src = o.get("inner")
		guard += 1
	return false


func _on_overlay_toggled(on: bool) -> void:
	overlay.visible = on
	if on:
		overlay.refresh()


## Hides the console for a screenshot (Debug.screenshot) and brings it back.
func _on_capture_state(capturing: bool) -> void:
	if capturing:
		_console_was_open = console.visible
		console.visible = false
	else:
		console.visible = _console_was_open


func _place_overlay() -> void:
	var h := get_viewport().get_visible_rect().size.y if is_inside_tree() else 0.0
	overlay.set_top(h * DebugConsole.HEIGHT_FRACTION if console.visible else 0.0)
