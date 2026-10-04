class_name NpcUi
extends Control
## Root of res://scenes/ui/npc_ui.tscn: the NPC dialogue window and the NPC shop window.
##
##   NpcInteraction.view_changed      -> DialogueWindow.show_view (every VIEW the runner produces)
##   NpcInteraction.shop_requested    -> ShopWindow.open_shop (a shopkeeper's dialogue action)
##   Events.shop_open_requested       -> ShopWindow.open_shop (anyone else: debug console, future systems)
## The NpcInteraction is the shared one (WorldUiServices.npc_talk: ctx.npc_talk, Game.npc_talk, NpcInteraction over
## Game.quests, else a fallback); the interaction system starts conversations on the same instance. Portraits render the
## world NPC's own proxy model (ctx.world.npc_nodes[id].visual) when the world is there.
##
## setup(ctx): the windows push/pop the modal and register on the window stack; Esc is left to the shell's
## close_top_window(). Standalone (no ctx) the windows handle Esc themselves.
##
## One NPC window at a time: the shop opening ends the conversation (deferred, because a shopkeeper's greeting opens the
## shop from inside its own step and then ends by itself), and a conversation starting closes the shop. A map change
## (MapSession.transition_started, or Events.map_left without a session) closes both: a chat or a shop must not follow
## the player into another map (a debug warp, a forced move).

var ctx: GameContext = null
var dialogue: DialogueWindow = null
var shop: ShopWindow = null
var talk: NpcInteraction = null
## () -> NpcInteraction; empty = WorldUiServices.npc_talk(ctx). Tests inject one.
var talk_provider: Callable = Callable()
## Event bus; null = the Events autoload.
var bus: Object = null
## MapSession (duck-typed: signal transition_started); null + use_session = the autoload.
var session: Object = null
var use_session: bool = true

var _bus_connected: Object = null
var _session_connected: Object = null
var _chat_close_queued := false


func _init() -> void:
	name = "NpcUi"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	dialogue = DialogueWindow.new()
	add_child(dialogue)
	shop = ShopWindow.new()
	add_child(shop)
	dialogue.model_provider = model_for
	shop.model_provider = model_for
	dialogue.bottom_inset_provider = bottom_inset
	shop.bottom_inset_provider = bottom_inset
	dialogue.opened.connect(_on_dialogue_opened)
	shop.opened.connect(_on_shop_opened)


func _ready() -> void:
	NpcUiStyle.apply_base(self)
	resized.connect(_relayout)
	if talk == null:
		_resolve_talk()
	_connect_bus()


func _exit_tree() -> void:
	_disconnect_bus()


## Closes the conversation and the shop (a map change, tests). Safe when nothing is open.
func close_all() -> void:
	if shop.is_open():
		shop.close()
	if dialogue.is_open() or (dialogue.talk != null and dialogue.talk.is_open()):
		dialogue.close()


func _on_dialogue_opened() -> void:
	if shop.is_open():
		shop.close()


## True while a chat waits to be ended (at the end of the frame) for a shop that opened over it.
func is_chat_close_queued() -> bool:
	return _chat_close_queued


func _on_shop_opened(_shop_id: String) -> void:
	if dialogue.is_open() and not _chat_close_queued:
		_chat_close_queued = true
		_end_chat_for_shop.call_deferred()


func _end_chat_for_shop() -> void:
	_chat_close_queued = false
	# Still both open after the step that opened the shop (a greeting normally ends by itself first).
	if shop.is_open() and dialogue.is_open():
		dialogue.close()


func _on_map_changing(_a: Variant = null, _b: Variant = null) -> void:
	close_all()


## GameContext seam (see the class comment).
func setup(p_ctx: GameContext) -> void:
	ctx = p_ctx
	for w: Variant in [dialogue, shop]:
		w.set("ctx", ctx)
		w.set("handle_escape", ctx == null)
	if bus != null:
		dialogue.bus = bus
		shop.bus = bus
	_resolve_talk()
	_connect_bus()


## Uses `t` for conversations (tests; normally resolved automatically).
func bind_talk(t: NpcInteraction) -> void:
	if talk == t:
		return
	if talk != null and talk.shop_requested.is_connected(open_shop):
		talk.shop_requested.disconnect(open_shop)
	talk = t
	dialogue.bind_talk(t)
	if t != null and not t.shop_requested.is_connected(open_shop):
		t.shop_requested.connect(open_shop)


## Opens a shop window (idempotent when that shop is already open).
func open_shop(shop_id: String, npc_id: String = "") -> bool:
	return shop.open_shop(shop_id, npc_id)


## The world NPC's model for portraits, or null.
func model_for(npc_id: String) -> Node3D:
	var w: Variant = ctx.world if ctx != null else null
	if not (w is Object) or not is_instance_valid(w):
		return null
	var nodes: Variant = (w as Object).get("npc_nodes")
	if not (nodes is Dictionary):
		return null
	var n: Variant = (nodes as Dictionary).get(npc_id)
	if n is Node3D and is_instance_valid(n):
		var v: Variant = (n as Node3D).get("visual")
		if v is Node3D and is_instance_valid(v):
			return v
	return null


## Pixels at the bottom of this layer taken by another UI system's bottom-wide bar (the HUD's status bar), so the
## dialogue and the shop sit above it instead of covering the gauges. Found by layout, not by name: any visible
## direct child of a sibling UI root (the other subsystems under ctx.ui_root) that is anchored across the bottom edge.
## 0 standalone.
func bottom_inset() -> float:
	var root: Node = get_parent()
	if root == null or not is_inside_tree():
		return 0.0
	var area_bottom := get_global_rect().end.y
	var top := area_bottom
	for sibling in root.get_children():
		if sibling == self or not (sibling is Control) or not (sibling as Control).is_visible_in_tree():
			continue
		for c in sibling.get_children():
			if c is Control and (c as Control).visible and NpcUi._is_bottom_bar(c as Control):
				top = minf(top, (c as Control).get_global_rect().position.y)
	return maxf(0.0, area_bottom - top)


static func _is_bottom_bar(c: Control) -> bool:
	return c.anchor_top >= 0.99 and c.anchor_bottom >= 0.99 and c.anchor_left <= 0.01 and c.anchor_right >= 0.99 \
		and not c.top_level


func _process(_delta: float) -> void:
	# The shared NpcInteraction can appear after setup (the Game autoload wiring); follow it.
	if not talk_provider.is_valid() and (talk == null or WorldUiServices.npc_talk(ctx) != talk):
		_resolve_talk()


func _resolve_talk() -> void:
	var t: NpcInteraction = null
	if talk_provider.is_valid():
		var v: Variant = talk_provider.call()
		t = v if v is NpcInteraction else null
	else:
		t = WorldUiServices.npc_talk(ctx)
	if t != null:
		bind_talk(t)


func _connect_bus() -> void:
	var b: Object = bus if bus != null else WorldUiServices.events()
	if b != _bus_connected:
		_disconnect_bus()
		if b != null and b.has_signal("shop_open_requested"):
			b.connect("shop_open_requested", open_shop)
		if b != null and b.has_signal("map_left"):
			b.connect("map_left", _on_map_changing)
		_bus_connected = b
	var s: Object = session if session != null else (WorldUiServices.session() if use_session else null)
	if s != _session_connected:
		_disconnect_session()
		if s != null and s.has_signal("transition_started"):
			s.connect("transition_started", _on_map_changing)
		_session_connected = s


func _disconnect_bus() -> void:
	if _bus_connected != null and is_instance_valid(_bus_connected):
		for pair in [["shop_open_requested", open_shop], ["map_left", _on_map_changing]]:
			if _bus_connected.has_signal(pair[0]) and _bus_connected.is_connected(pair[0], pair[1]):
				_bus_connected.disconnect(pair[0], pair[1])
	_bus_connected = null
	_disconnect_session()


func _disconnect_session() -> void:
	if _session_connected != null and is_instance_valid(_session_connected) \
			and _session_connected.has_signal("transition_started") \
			and _session_connected.is_connected("transition_started", _on_map_changing):
		_session_connected.disconnect("transition_started", _on_map_changing)
	_session_connected = null


func _relayout() -> void:
	if dialogue.visible:
		dialogue._layout()
	if shop.visible:
		shop._layout()
