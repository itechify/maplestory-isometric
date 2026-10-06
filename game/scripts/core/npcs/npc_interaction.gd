class_name NpcInteraction
extends RefCounted
## Node-free controller for talking to NPCs: builds the NPC's conversation (NpcDialogueBuilder), runs it
## (DialogueRunner) and routes quest actions through QuestService, so every accept / completion / hand-over reaches
## the Events bus. The dialogue UI only renders views and forwards button presses.
##
##   var talk := NpcInteraction.new(Game.quests)          # Game.quests: the QuestService
##   talk.view_changed.connect(dialogue_ui.show_view)     # or use the returned views
##   talk.shop_requested.connect(func(shop_id, npc_id): shop_ui.open(shop_id))
##   talk.departure_requested.connect(func(npc_id, departure): ...)   # Shanks: the end-of-island screen
##   var view := talk.talk("9")                           # player pressed interact on Sam
##   view = talk.press("next") / talk.press("yes") / talk.choose(view.choices[0].index)
##
## talk() emits Events.npc_talked(npc_id) (quest talk objectives) and Events.dialogue_opened(npc_id); the end of the
## conversation emits Events.dialogue_closed(npc_id). View format: see DialogueRunner.

## Every new view (after talk / press / choose); {"open": false} when the conversation ended.
signal view_changed(view: Dictionary)
## A dialogue action asked to open a shop (the UI opens data/canonical/shops/<shop_id>.json).
signal shop_requested(shop_id: String, npc_id: String)
## The conversation with `npc_id` ended.
signal conversation_closed(npc_id: String)
## A transport NPC's boarding reached the departure boundary (NpcTransport.depart; Shanks): `departure` is the
## "departure_requested" effect {npc_id, route_index, route, flag, at, fare_charged, region, unfinished_quests}. The
## shell shows the end-of-island screen (DepartureScreen).
signal departure_requested(npc_id: String, departure: Dictionary)

var service: QuestService
var npcs: NpcCatalog
var builder: NpcDialogueBuilder
var runner: DialogueRunner = DialogueRunner.new()
## The NPC currently talked to ("" when closed).
var npc_id: String = ""
var _graphs: Dictionary = {}


func _init(p_service: QuestService, p_npcs: NpcCatalog = null) -> void:
	service = p_service
	var db := p_service.engine.db
	npcs = p_npcs if p_npcs != null else NpcCatalog.new(db)
	builder = NpcDialogueBuilder.new(db, p_service.engine.catalog, npcs)
	runner.closed.connect(_on_runner_closed)


## Starts a conversation with an NPC and returns the first view ({"open": false} for an unknown NPC).
func talk(p_npc_id: String) -> Dictionary:
	if runner.is_open():
		runner.close()
	var n := npcs.get_def(p_npc_id)
	if n == null:
		return {"open": false}
	npc_id = p_npc_id
	if service.is_attached():
		_emit("npc_talked", [p_npc_id])
	else:
		service.handle_npc_talked(p_npc_id)
	_emit("dialogue_opened", [p_npc_id])
	var ctx := DialogueContext.new(service.engine, p_npc_id, _sink)
	var v := runner.start(graph_for(p_npc_id), ctx, {"npc_id": n.id, "name": n.name, "portrait": n.portrait})
	view_changed.emit(v)
	return v


func press(button: String) -> Dictionary:
	return _after(runner.press(button))


func choose(index: int) -> Dictionary:
	return _after(runner.choose(index))


func view() -> Dictionary:
	return runner.view()


func is_open() -> bool:
	return runner.is_open()


func close() -> void:
	runner.close()


## The NPC's conversation graph (built once per NPC; the graph is static, conditions are evaluated live).
func graph_for(p_npc_id: String) -> DialogueGraph:
	if not _graphs.has(p_npc_id):
		_graphs[p_npc_id] = builder.build(p_npc_id)
	return _graphs[p_npc_id]


## The quest indicator for an NPC: "completable", "available", "in_progress" or "".
func marker(p_npc_id: String) -> String:
	return service.engine.npc_marker(p_npc_id)


# --- internals ------------------------------------------------------------------------------------------------

func _after(v: Dictionary) -> Dictionary:
	if bool(v.get("open", false)):
		view_changed.emit(v)
	return v


func _sink(effects: Array) -> void:
	service.dispatch(effects)
	for fx: Variant in effects:
		var e := QuestJson.dict(fx)
		match QuestJson.s(e.get("type")):
			"open_shop":
				shop_requested.emit(QuestJson.s(e.get("shop_id")), QuestJson.s(e.get("npc_id")))
			"departure_requested":
				departure_requested.emit(QuestJson.s(e.get("npc_id")), e.duplicate(true))


func _on_runner_closed() -> void:
	var was := npc_id
	npc_id = ""
	_emit("dialogue_closed", [was])
	view_changed.emit({"open": false})
	conversation_closed.emit(was)


func _emit(sig: String, args: Array) -> void:
	var bus := service.bus
	if bus == null or not bus.has_signal(sig):
		return
	bus.callv("emit_signal", [sig] + args)
