class_name DialogueRunner
extends RefCounted
## Runs a DialogueGraph: walks invisible nodes (branch, action, single-choice menus), stops on display nodes and
## exposes them as a VIEW the dialogue UI renders. Keeps a history of display nodes for Back; executing any action
## clears it, so Back never crosses (or repeats) an accept, a completion or a hand-over.
##
##   var r := DialogueRunner.new()
##   var view := r.start(graph, ctx, {"npc_id": "9", "name": "Sam", "portrait": "npc_9"})
##   view = r.press("next")          # "next", "ok", "back", "yes", "no", "end"
##   view = r.choose(view.choices[0].index)
##
## VIEW: {"open": bool, "node_id", "type": "say" | "yes_no" | "menu", "npc_id", "speaker_id", "speaker_name",
##        "portrait", "speaker_kind": "npc" | "system" | "journal", "title", "text", "segments": [UI segment],
##        "source", "choices": [{"index", "text", "segments", "quest_id", "tag"}], "buttons": [String]}
## Buttons: "back" (when history allows), "next" (say with a next node), "ok" (say that ends the chat),
## "yes" / "no" (yes_no), "end" (menu: End Chat). A closed runner returns {"open": false}.

signal closed()

## Guard against authoring loops in invisible nodes.
const MAX_AUTO_STEPS := 64

var graph: DialogueGraph
var ctx: DialogueContext
var db: ContentDB
## {"npc_id", "name", "portrait"} of the NPC being talked to.
var speaker: Dictionary = {}
var current_id: String = ""
## Display node ids visited before the current one (Back pops this).
var history: PackedStringArray = []
var _open := false


## Starts the conversation at graph.start; returns the first view ({"open": false} if it ends immediately).
func start(p_graph: DialogueGraph, p_ctx: DialogueContext, p_speaker: Dictionary = {}) -> Dictionary:
	graph = p_graph
	ctx = p_ctx
	db = p_ctx.engine.db if p_ctx != null and p_ctx.engine != null else null
	speaker = p_speaker
	history = PackedStringArray()
	current_id = ""
	_open = true
	_goto(graph.start, false)
	return view()


func is_open() -> bool:
	return _open


## The current view (see the class comment).
func view() -> Dictionary:
	if not _open:
		return {"open": false}
	var n := graph.node(current_id)
	var t := QuestJson.s(n.get("type"))
	var line := _resolve(QuestJson.dict(n.get("line")))
	var sp := _speaker_for(QuestJson.s(n.get("speaker"), "npc"))
	var v := {
		"open": true,
		"node_id": current_id,
		"type": t,
		"npc_id": QuestJson.s(speaker.get("npc_id")),
		"speaker_id": sp["id"],
		"speaker_name": sp["name"],
		"portrait": sp["portrait"],
		"speaker_kind": sp["kind"],
		"title": QuestJson.s(n.get("title")),
		"text": line["text"],
		"segments": line["segments"],
		"source": line["source"],
		"choices": [],
		"buttons": [],
	}
	var buttons: Array = []
	if can_back():
		buttons.append("back")
	match t:
		"say":
			buttons.append("next" if not QuestJson.s(n.get("next")).is_empty() else "ok")
		"yes_no":
			buttons.append_array(["yes", "no"])
		"menu":
			var choices: Array = []
			for c: Dictionary in visible_choices():
				var cl := _resolve(QuestJson.dict(c["choice"].get("line")))
				choices.append({"index": c["index"], "text": cl["text"], "segments": cl["segments"],
					"quest_id": QuestJson.s(c["choice"].get("quest_id")), "tag": QuestJson.s(c["choice"].get("tag"))})
			v["choices"] = choices
			buttons.append("end")
	v["buttons"] = buttons
	return v


## True if Back is possible from the current node.
func can_back() -> bool:
	return _open and not history.is_empty() and QuestJson.b(graph.node(current_id).get("back"), true)


## Menu choices whose condition passes now: [{"index": original index, "choice": Dictionary}].
func visible_choices() -> Array:
	var out: Array = []
	var cs := QuestJson.arr(graph.node(current_id).get("choices"))
	for idx in cs.size():
		var c := QuestJson.dict(cs[idx])
		if ctx.check(c.get("condition")):
			out.append({"index": idx, "choice": c})
	return out


## Generic button press (see the class comment). Unknown or unavailable buttons leave the view unchanged.
func press(button: String) -> Dictionary:
	match button:
		"next", "ok":
			return next()
		"back":
			return back()
		"yes":
			return yes()
		"no":
			return no()
		"end":
			close()
	return view()


func next() -> Dictionary:
	if not _open:
		return view()
	var n := graph.node(current_id)
	if QuestJson.s(n.get("type")) != "say":
		return view()
	_goto(QuestJson.s(n.get("next")), false)
	return view()


func back() -> Dictionary:
	if not can_back():
		return view()
	current_id = history[history.size() - 1]
	history.remove_at(history.size() - 1)
	return view()


func yes() -> Dictionary:
	return _answer("yes")


func no() -> Dictionary:
	return _answer("no")


## Picks a menu choice by its "index" from view().choices.
func choose(index: int) -> Dictionary:
	if not _open or QuestJson.s(graph.node(current_id).get("type")) != "menu":
		return view()
	for c: Dictionary in visible_choices():
		if int(c["index"]) == index:
			_take(c["choice"])
			return view()
	return view()


func close() -> void:
	if not _open:
		return
	_open = false
	current_id = ""
	history = PackedStringArray()
	closed.emit()


# --- internals ------------------------------------------------------------------------------------------------

## Resolves a line spec for display, with its live counters (DialogueText.apply_counters) filled in.
func _resolve(spec: Dictionary) -> Dictionary:
	var line := DialogueText.resolve(spec, db)
	if spec.has("counters") and ctx != null and ctx.engine != null:
		line = DialogueText.apply_counters(line, spec.get("counters"), _count_item)
	return line


func _count_item(item_id: String) -> int:
	return ctx.character().inventory.count(item_id)


func _answer(key: String) -> Dictionary:
	if not _open or QuestJson.s(graph.node(current_id).get("type")) != "yes_no":
		return view()
	_take(QuestJson.dict(graph.node(current_id).get(key)))
	return view()


## Follows an option ({actions?, next, on_fail?}) from the current display node.
func _take(option: Dictionary) -> void:
	var actions := QuestJson.arr(option.get("actions"))
	if actions.is_empty():
		_goto(QuestJson.s(option.get("next")), false)
		return
	var r := ctx.run(actions)
	_goto(QuestJson.s(option.get("next")) if bool(r.get("ok", false)) else _fail_target(option.get("on_fail"), r), true)


## Moves to `target`, resolving invisible nodes until a display node (or the end) is reached.
func _goto(target: String, acted: bool) -> void:
	var from_display := current_id
	var t := target
	var did_act := acted
	for step in MAX_AUTO_STEPS:
		if t.is_empty():
			close()
			return
		var n := graph.node(t)
		if n.is_empty():
			push_warning("[Dialogue] %s: missing node '%s'" % [graph.id, t])
			close()
			return
		match QuestJson.s(n.get("type")):
			"end":
				close()
				return
			"branch":
				var to := QuestJson.s(n.get("default"))
				for c: Variant in QuestJson.arr(n.get("cases")):
					var cd := QuestJson.dict(c)
					if ctx.check(cd.get("condition")):
						to = QuestJson.s(cd.get("next"))
						break
				t = to
				continue
			"action":
				var r := ctx.run(QuestJson.arr(n.get("actions")))
				did_act = true
				t = QuestJson.s(n.get("next")) if bool(r.get("ok", false)) else _fail_target(n.get("on_fail"), r)
				continue
			"menu":
				var vis := _visible_choices_of(n)
				if vis.is_empty():
					t = QuestJson.s(n.get("empty_next"))
					continue
				if vis.size() == 1 and QuestJson.b(n.get("auto_single")):
					var only: Dictionary = vis[0]
					var acts := QuestJson.arr(only.get("actions"))
					if acts.is_empty():
						t = QuestJson.s(only.get("next"))
					else:
						var r := ctx.run(acts)
						did_act = true
						t = QuestJson.s(only.get("next")) if bool(r.get("ok", false)) else _fail_target(only.get("on_fail"), r)
					continue
			"say", "yes_no":
				pass
			_:
				push_warning("[Dialogue] %s: unknown node type at '%s'" % [graph.id, t])
				close()
				return
		# A display node.
		if did_act:
			history = PackedStringArray()
		elif not from_display.is_empty() and from_display != t:
			history.append(from_display)
		current_id = t
		return
	push_error("[Dialogue] %s: more than %d invisible steps from '%s' (loop?)" % [graph.id, MAX_AUTO_STEPS, target])
	close()


func _visible_choices_of(n: Dictionary) -> Array:
	var out: Array = []
	for c: Variant in QuestJson.arr(n.get("choices")):
		if ctx.check(QuestJson.dict(c).get("condition")):
			out.append(QuestJson.dict(c))
	return out


## on_fail: a node id, or {reason: id, "*": id}. No match = end the conversation.
static func _fail_target(on_fail: Variant, result: Dictionary) -> String:
	if on_fail is String:
		return on_fail
	if on_fail is Dictionary:
		var reason := QuestJson.s(result.get("reason"))
		var d: Dictionary = on_fail
		if d.has(reason):
			return QuestJson.s(d[reason])
		return QuestJson.s(d.get("*"))
	return ""


func _speaker_for(kind: String) -> Dictionary:
	var own_id := QuestJson.s(speaker.get("npc_id"))
	var own := {"id": own_id, "name": QuestJson.s(speaker.get("name")), "portrait": QuestJson.s(speaker.get("portrait")), "kind": "npc"}
	match kind:
		"npc", "":
			return own
		"journal":
			own["kind"] = "journal"
			return own
		"system":
			return {"id": "", "name": "", "portrait": "", "kind": "system"}
	# Another NPC speaks this line.
	var other_name := QuestJson.s(db.npc(kind).get("name")) if db != null else ""
	var other_portrait := QuestJson.s(db.miso_entity("npcs", kind).get("portrait"), "npc_" + kind) if db != null else ""
	return {"id": kind, "name": other_name, "portrait": other_portrait, "kind": "npc"}
