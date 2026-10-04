class_name DebugCompleter
extends RefCounted
## Tab completion for the debug console: command names first, then each argument by the kind its command declared
## with Debug.set_completion(name, kinds).
##
## Kinds: "map", "portal" (of the map named by the previous argument, else the current map), "item", "monster",
## "quest", "quest_sub" (accept/complete/forfeit/reset/status/list, then a quest id), "on_off", "layer", "link_mode",
## "link", "kill", "tab", "stat", "command", or an Array of literal choices.
##
## A word that is a prefix of some candidate ids completes to their longest common prefix (a unique one gets a
## trailing space); otherwise the word is matched against names (a unique name match is replaced by its id).
## complete(line) -> {"line": String, "candidates": PackedStringArray (display lines, "id name")}.

const KINDS: PackedStringArray = ["map", "portal", "item", "monster", "quest", "quest_sub", "on_off", "layer",
	"link_mode", "link", "kill", "tab", "stat", "command"]
const QUEST_SUBCOMMANDS: PackedStringArray = ["accept", "complete", "forfeit", "reset", "status", "list"]
## Kinds whose names may contain spaces.
const NAME_KINDS: PackedStringArray = ["map", "item", "monster", "quest"]
const MAX_SHOWN := 40

var dbg: DebugTools


func _init(debug: DebugTools) -> void:
	dbg = debug


func complete(line: String) -> Dictionary:
	var words := DebugTools.tokenize(line)
	var trailing := line.ends_with(" ") or line == ""
	if trailing:
		words.append("")
	if words.size() <= 1:
		var cmd_cands := _command_candidates()
		return _finish(line, words, 0, cmd_cands)
	var cmd := dbg.resolve_name(words[0])
	var arg_index := words.size() - 2
	var kinds := dbg.completion_kinds(cmd)
	var kind: Variant = kinds[arg_index] if arg_index < kinds.size() else null
	# Names have spaces ("give red pot", "warp snail hunting"): past the declared kinds, or where a portal is expected
	# but the words before it are not a map, the trailing words are one name fragment of the last name kind.
	var merge_from := -1
	if kind == null:
		for k in range(kinds.size() - 1, -1, -1):
			if kinds[k] is String and String(kinds[k]) in NAME_KINDS:
				merge_from = k
				kind = kinds[k]
				break
	elif kind is String and String(kind) == "portal" and arg_index >= 1 and kinds[arg_index - 1] is String \
			and String(kinds[arg_index - 1]) == "map":
		if not bool(DebugResolve.map_id(" ".join(words.slice(1, words.size() - 1)), dbg.get_defs()).ok):
			merge_from = arg_index - 1
			kind = "map"
	if kind == null:
		return {"line": line, "candidates": PackedStringArray()}
	if merge_from >= 0:
		var merged := words.slice(0, merge_from + 1)
		merged.append(" ".join(words.slice(merge_from + 1)))
		return _finish(line, merged, merged.size() - 1, candidates(kind, PackedStringArray()))
	var cands := candidates(kind, words.slice(1, words.size() - 1))
	return _finish(line, words, words.size() - 1, cands)


## Candidate rows [{value, label}] for a kind; `previous` are the arguments before the one being completed.
func candidates(kind: Variant, previous: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if kind is Array:
		for v in kind:
			out.append({"value": String(v), "label": String(v)})
		return out
	var db := dbg.get_db()
	match String(kind):
		"map":
			var defs := dbg.get_defs()
			for id in defs.ids():
				out.append({"value": id, "label": "%s %s" % [id, defs.get_def(id).map_name],
					"names": PackedStringArray([defs.get_def(id).map_name, defs.get_def(id).slug])})
		"portal":
			var defs := dbg.get_defs()
			var map := dbg.current_map()
			if not previous.is_empty():
				var r := DebugResolve.map_id(previous[previous.size() - 1], defs)
				if bool(r.ok):
					map = String(r.id)
			var def := defs.get_def(map)
			if def != null:
				for p in def.portals:
					out.append({"value": p.portal_id, "label": "%s -> %s" % [p.portal_id, p.destination_map_id]})
		"item", "monster", "quest":
			var domain := {"item": "items", "monster": "monsters", "quest": "quests"}[String(kind)] as String
			for row in DebugResolve.search(domain, "", db, 100000):
				var id := row.get_slice(" ", 0)
				out.append({"value": id, "label": row, "names": PackedStringArray([row.substr(id.length() + 1)])})
		"quest_sub":
			for s in QUEST_SUBCOMMANDS:
				out.append({"value": s, "label": s})
		"on_off":
			for s in ["on", "off"]:
				out.append({"value": s, "label": s})
		"layer":
			for s in DebugTools.LAYERS:
				out.append({"value": s, "label": s})
			out.append({"value": "all", "label": "all"})
		"link_mode":
			for s in [PortalDef.LINK_WARP, PortalDef.LINK_EDGE]:
				out.append({"value": s, "label": s})
		"link":
			out.append({"value": "all", "label": "all"})
			var ids: Array = dbg.get_defs().graph.links.keys()
			ids.sort()
			for id in ids:
				out.append({"value": String(id), "label": String(id)})
		"kill":
			for s in ["nearest", "all"]:
				out.append({"value": s, "label": s})
		"tab":
			for s in Inventory.TABS:
				out.append({"value": String(s), "label": String(s)})
		"stat":
			for s in CharacterState.STAT_KEYS:
				out.append({"value": s, "label": s})
		"command":
			out = _command_candidates()
	return out


func _command_candidates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var names := dbg.command_names()
	names.append_array(dbg.alias_names())
	names.sort()
	for n in names:
		out.append({"value": n, "label": n})
	return out


func _finish(line: String, words: PackedStringArray, index: int, cands: Array[Dictionary]) -> Dictionary:
	var word := words[index] if index < words.size() else ""
	var low := word.to_lower()
	var hits: Array[Dictionary] = []
	for c in cands:
		if String(c.value).to_lower().begins_with(low):
			hits.append(c)
	var by_name := false
	if hits.is_empty() and low != "":
		var f := DebugResolve._norm(word)
		for c in cands:
			for n in (c.get("names", PackedStringArray()) as PackedStringArray):
				if f != "" and DebugResolve._norm(n).contains(f):
					hits.append(c)
					break
		by_name = true
	var shown: PackedStringArray = []
	for h in hits.slice(0, MAX_SHOWN):
		shown.append(String(h.label))
	if hits.size() > MAX_SHOWN:
		shown.append("... %d more" % (hits.size() - MAX_SHOWN))
	if hits.is_empty():
		return {"line": line, "candidates": shown}
	var replacement := word
	if hits.size() == 1:
		replacement = String(hits[0].value) + " "
	elif not by_name:
		var values: PackedStringArray = []
		for h in hits:
			values.append(String(h.value))
		replacement = _common_prefix(values)
		if replacement.length() < word.length():
			replacement = word
	var head := words.slice(0, index)
	var rebuilt := ""
	for w in head:
		rebuilt += (_quote(w) + " ")
	rebuilt += replacement
	return {"line": rebuilt, "candidates": shown if hits.size() > 1 else PackedStringArray()}


static func _quote(w: String) -> String:
	return "\"%s\"" % w if w.contains(" ") else w


static func _common_prefix(values: PackedStringArray) -> String:
	if values.is_empty():
		return ""
	var p := values[0]
	for v in values:
		var n := 0
		while n < p.length() and n < v.length() and p[n].to_lower() == v[n].to_lower():
			n += 1
		p = p.left(n)
	return p
