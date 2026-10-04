class_name DialogueGraph
extends RefCounted
## A branching conversation as data: {"id", "npc_id", "start", "nodes": {node_id: Node}}.
##
## Node types (every node is a Dictionary with "type"):
##   say     shows a line.            {"line": LineSpec, "next": id, "title"?, "speaker"?, "back"?: bool}
##   yes_no  shows a line + Yes / No. {"line", "yes": Option, "no": Option, "title"?, "speaker"?, "back"?}
##   menu    shows a line + choices.  {"line", "choices": [Option + {"line", "condition"?, "quest_id"?, "tag"?}],
##                                    "auto_single"?: bool (one visible choice = take it without showing the menu),
##                                    "empty_next"?: id (no visible choice), "title"?, "speaker"?, "back"?}
##   branch  invisible switch.        {"cases": [{"condition", "next"}], "default": id}
##   action  invisible side effects.  {"actions": [Action], "next": id, "on_fail"?: id | {reason: id, "*": id}}
##   end     closes the conversation.
## Option = {"actions"?: [Action], "next": id, "on_fail"?: id | {reason: id, "*": id}}.
## A target id of "" ends the conversation. LineSpec: see DialogueText. Condition / Action: see DialogueContext.
## "speaker" is "npc" (default: the NPC being talked to), another NPC id, "system" or "journal" (a quest card).
##
## Display nodes (say / yes_no / menu) never run actions, so Back can never undo one.

const NODE_TYPES: PackedStringArray = ["say", "yes_no", "menu", "branch", "action", "end"]
const DISPLAY_TYPES: PackedStringArray = ["say", "yes_no", "menu"]

var id: String = ""
var npc_id: String = ""
var start: String = "start"
var nodes: Dictionary = {}
## Problems found while applying overrides (a patch for a node that does not exist); reported by validate().
var override_errors: PackedStringArray = []


static func from_dict(d: Dictionary) -> DialogueGraph:
	var g := DialogueGraph.new()
	g.id = QuestJson.s(d.get("id"))
	g.npc_id = QuestJson.s(d.get("npc_id"))
	g.start = QuestJson.s(d.get("start"), "start")
	var ns := QuestJson.dict(d.get("nodes"))
	for k: Variant in ns:
		g.nodes[str(k)] = QuestJson.dict(ns[k]).duplicate(true)
	return g


func to_dict() -> Dictionary:
	return {"id": id, "npc_id": npc_id, "start": start, "nodes": nodes.duplicate(true)}


func node(node_id: String) -> Dictionary:
	return nodes.get(node_id, {})


func has_node(node_id: String) -> bool:
	return nodes.has(node_id)


## Adds or replaces a node.
func set_node(node_id: String, n: Dictionary) -> void:
	nodes[node_id] = n


## Applies an override file (data/misostory/dialogue/<npc_id>.json): "remove_nodes" deletes nodes, "nodes" adds or
## replaces whole nodes, "patch_nodes" ({node_id: {key: value}}) replaces single keys of existing (generated) nodes,
## "start" moves the entry point. Applied in that order.
func apply_override(o: Dictionary) -> void:
	for nid: String in QuestJson.strings(o.get("remove_nodes")):
		nodes.erase(nid)
	var ns := QuestJson.dict(o.get("nodes"))
	for k: Variant in ns:
		nodes[str(k)] = QuestJson.dict(ns[k]).duplicate(true)
	var patches := QuestJson.dict(o.get("patch_nodes"))
	for k: Variant in patches:
		var nid := str(k)
		if not nodes.has(nid):
			override_errors.append("patch for node '%s', which does not exist" % nid)
			continue
		var patch := QuestJson.dict(patches[k])
		for key: Variant in patch:
			var v: Variant = patch[key]
			if v is Dictionary:
				v = (v as Dictionary).duplicate(true)
			elif v is Array:
				v = (v as Array).duplicate(true)
			(nodes[nid] as Dictionary)[str(key)] = v
	if o.get("start") != null:
		start = QuestJson.s(o.get("start"), start)


## Every target id a node can lead to ("" = end).
static func targets_of(n: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if n.has("next"):
		out.append(QuestJson.s(n.get("next")))
	if n.has("default"):
		out.append(QuestJson.s(n.get("default")))
	if n.has("empty_next"):
		out.append(QuestJson.s(n.get("empty_next")))
	_fail_targets(n.get("on_fail"), out)
	for key in ["yes", "no"]:
		var opt := QuestJson.dict(n.get(key))
		if not opt.is_empty():
			out.append(QuestJson.s(opt.get("next")))
			_fail_targets(opt.get("on_fail"), out)
	for c: Variant in QuestJson.arr(n.get("choices")) + QuestJson.arr(n.get("cases")):
		var cd := QuestJson.dict(c)
		out.append(QuestJson.s(cd.get("next")))
		_fail_targets(cd.get("on_fail"), out)
	return out


## Structural problems (unknown types, dangling targets, bad conditions/actions) and, when `db` is given, line specs
## that do not resolve to text. Empty = valid.
func validate(db: ContentDB = null) -> PackedStringArray:
	var errs := PackedStringArray()
	var at := "dialogue %s" % (id if not id.is_empty() else npc_id)
	for e in override_errors:
		errs.append("%s: override %s" % [at, e])
	if not nodes.has(start):
		errs.append("%s: start node '%s' missing" % [at, start])
	for nid: String in nodes:
		var n: Dictionary = nodes[nid]
		var where := "%s node '%s'" % [at, nid]
		var t := QuestJson.s(n.get("type"))
		if not (t in NODE_TYPES):
			errs.append("%s: unknown type '%s'" % [where, t])
			continue
		for target in targets_of(n):
			if not target.is_empty() and not nodes.has(target):
				errs.append("%s: target '%s' does not exist" % [where, target])
		if t in DISPLAY_TYPES:
			_check_line(errs, where, n.get("line"), db)
		match t:
			"yes_no":
				if QuestJson.dict(n.get("yes")).is_empty() or QuestJson.dict(n.get("no")).is_empty():
					errs.append("%s: yes_no needs both 'yes' and 'no'" % where)
			"menu":
				if not n.has("choices"):
					errs.append("%s: menu without choices" % where)
				for c: Variant in QuestJson.arr(n.get("choices")):
					var cd := QuestJson.dict(c)
					_check_line(errs, where + " choice", cd.get("line"), db)
					errs.append_array(DialogueContext.validate_condition(cd.get("condition"), where))
			"branch":
				if not n.has("default"):
					errs.append("%s: branch without default" % where)
				for c: Variant in QuestJson.arr(n.get("cases")):
					errs.append_array(DialogueContext.validate_condition(QuestJson.dict(c).get("condition"), where))
		for a: Variant in _all_actions(n):
			errs.append_array(DialogueContext.validate_action(a, where))
	return errs


# --- internals ------------------------------------------------------------------------------------------------

static func _fail_targets(v: Variant, out: PackedStringArray) -> void:
	if v is String:
		out.append(String(v))
	elif v is Dictionary:
		for k: Variant in v:
			out.append(QuestJson.s(v[k]))


static func _all_actions(n: Dictionary) -> Array:
	var out: Array = []
	out.append_array(QuestJson.arr(n.get("actions")))
	for key in ["yes", "no"]:
		out.append_array(QuestJson.arr(QuestJson.dict(n.get(key)).get("actions")))
	for c: Variant in QuestJson.arr(n.get("choices")):
		out.append_array(QuestJson.arr(QuestJson.dict(c).get("actions")))
	return out


static func _check_line(errs: PackedStringArray, where: String, spec: Variant, db: ContentDB) -> void:
	if not (spec is Dictionary) or (spec as Dictionary).is_empty():
		errs.append("%s: missing line" % where)
		return
	if db == null:
		return
	var r := DialogueText.resolve(spec, db)
	if String(r["text"]).is_empty() and (r["segments"] as Array).is_empty():
		errs.append("%s: line %s does not resolve" % [where, JSON.stringify(spec)])
		return
	for p in DialogueText.counter_problems(spec, r, db):
		errs.append("%s: %s" % [where, p])
