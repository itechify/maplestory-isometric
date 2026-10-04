class_name DialogueText
extends RefCounted
## Turns dialogue text references into the one segment format the dialogue UI renders.
##
## A dialogue node never stores canonical text; it stores a LINE SPEC that points at it, so the text stays exactly
## MeowDB's and keeps its provenance. Line specs:
##   {"quest": "1006", "section": "on_accept", "line": 0}                        main line of a quest dialogue section
##   {"quest": "1006", "section": "on_completion", "branch": "ready", "line": 1}  line of a branch (by its "state")
##   {"quest": "1013", "quiz": "question"} / {"quest", "quiz": "choice", "line": 2}
##   {"quest": "1013", "quiz": "wrong", "line": 0} / {"quest", "quiz": "right"}
##   {"quest": "1002", "journal": 1}                                             a quest journal line
##   {"quest": "1006", "name": true}                                             the quest's name
##   {"npc": "3", "field": "dialogue" | "idle_chatter", "line": 1}              an NPC's own lines
##   {"system": "inventory_full"}                                                MisoStory system line
##                                                                                (data/misostory/dialogue/_system.json)
##   {"parts": [LineSpec, ...]}                                                  several lines shown as one page,
##                                                                                one paragraph each (a quest card:
##                                                                                journal summary + system prompt)
##   {"text": "...", "segments": [...]?, "source": "..."}                         literal text (adaptations; must name
##                                                                                its source)
## Any spec may add "counters": [{"segment", "item_id"}]: those segments show the live inventory count (see
## apply_counters; the runner applies them, because resolve() has no character).
## resolve() returns {"text", "segments", "source"}; text is "" when the spec does not resolve. A "parts" line joins
## its parts' sources with " + " and skips parts that do not resolve (part_problems() reports them).
##
## UI segment: {"text": String, "bold": bool, "color": "" | "red", "ref": {"kind", "id", "known"}?,
##              "icon": {"kind": "item", "id", "icon_key"}?}
## Canonical quest lines use {red, ref.type} and NPC lines {color, ref.kind}; both normalize to the above.

const SYSTEM_FILE_ID := "_system"

## db instance id -> {icon_key -> item id}
static var _icon_cache: Dictionary = {}
## "<db instance id>:<quest id>" -> {meowdb_link_id -> corrected id}
static var _remap_cache: Dictionary = {}


## Paragraph break between the parts of a "parts" line.
const PART_BREAK := "\n\n"


## Resolves a line spec against the content. See the class comment for the spec forms.
static func resolve(spec: Dictionary, db: ContentDB) -> Dictionary:
	if spec.has("text"):
		return _literal(spec)
	if spec.has("parts"):
		return _parts(spec, db)
	if db == null:
		# Every other spec points into the content; without it nothing resolves (and nothing crashes).
		return _empty()
	if spec.has("system"):
		var key := QuestJson.s(spec.get("system"))
		var lines := QuestJson.dict(db.miso_entity("dialogue", SYSTEM_FILE_ID).get("lines"))
		var line := QuestJson.dict(lines.get(key))
		var out := _literal(line)
		out["source"] = "misostory/dialogue/_system.json#%s" % key
		return out
	if spec.has("npc"):
		var nid := QuestJson.s(spec.get("npc"))
		var field := QuestJson.s(spec.get("field"), "dialogue")
		var lines := QuestJson.arr(db.npc(nid).get(field))
		var idx := QuestJson.i(spec.get("line"))
		if idx < 0 or idx >= lines.size():
			return _empty()
		var out := normalize_line(lines[idx], {}, db)
		out["source"] = "canonical/npcs/%s.json#%s[%d]" % [nid, field, idx]
		return out
	if spec.has("quest"):
		return _resolve_quest(spec, db)
	return _empty()


## {"text", "segments"} from a canonical line ({text, segments?}); `remap` corrects ref ids (meowdb link id ->
## chosen id).
static func normalize_line(line: Variant, remap: Dictionary = {}, db: ContentDB = null) -> Dictionary:
	var ld := QuestJson.dict(line)
	var text := QuestJson.s(ld.get("text"))
	var raw := QuestJson.arr(ld.get("segments"))
	var segs: Array = []
	if raw.is_empty():
		if not text.is_empty():
			segs.append(segment(text))
	else:
		segs = normalize_segments(raw, remap, db)
	return {"text": text, "segments": segs, "source": ""}


## Normalizes canonical segments (either domain's style) to UI segments.
static func normalize_segments(raw: Array, remap: Dictionary = {}, db: ContentDB = null) -> Array:
	var out: Array = []
	for r: Variant in raw:
		var s := QuestJson.dict(r)
		var seg := segment(QuestJson.s(s.get("text")), QuestJson.b(s.get("bold")),
			"red" if (QuestJson.b(s.get("red")) or QuestJson.s(s.get("color")) == "red") else QuestJson.s(s.get("color")))
		var ref := QuestJson.dict(s.get("ref"))
		if not ref.is_empty():
			var kind := QuestJson.s(ref.get("kind"), QuestJson.s(ref.get("type")))
			var rid := QuestJson.s(ref.get("id"))
			if remap.has(rid):
				rid = String(remap[rid])
			seg["ref"] = {"kind": kind, "id": rid, "known": _known(db, kind, rid)}
		var icon_key := QuestJson.s(s.get("icon_key"))
		if not icon_key.is_empty():
			seg["icon"] = {"kind": "item", "id": _item_for_icon(db, icon_key), "icon_key": icon_key}
		out.append(seg)
	return out


## One UI segment.
static func segment(text: String, bold: bool = false, color: String = "") -> Dictionary:
	return {"text": text, "bold": bold, "color": color}


## Replaces counter segments of a resolved line with live values. MeowDB renders an in-game counter as a literal
## (1012's "Rusty Screw 0/3", docs/canonical/quests.md §10); a line spec marks such segments with
## "counters": [{"segment": <index into the line's segments>, "item_id": "441"}]. `count_of` is
## (item_id: String) -> int (the live inventory count). Returns a new resolved line; `resolved` is not modified.
static func apply_counters(resolved: Dictionary, counters: Variant, count_of: Callable) -> Dictionary:
	var list := QuestJson.arr(counters)
	if list.is_empty() or not count_of.is_valid():
		return resolved
	var segs: Array = QuestJson.arr(resolved.get("segments")).duplicate(true)
	var changed := false
	for c: Variant in list:
		var cd := QuestJson.dict(c)
		var idx := QuestJson.i(cd.get("segment"), -1)
		if idx < 0 or idx >= segs.size() or not (segs[idx] is Dictionary):
			continue
		(segs[idx] as Dictionary)["text"] = str(QuestJson.i(count_of.call(QuestJson.s(cd.get("item_id")))))
		changed = true
	if not changed:
		return resolved
	var out := resolved.duplicate()
	out["segments"] = segs
	out["text"] = plain(segs).strip_edges()
	return out


## Problems with a line spec's "counters" against its resolved line (index out of range, a segment that is not a
## number, an unknown item). Empty = valid.
static func counter_problems(spec: Dictionary, resolved: Dictionary, db: ContentDB) -> PackedStringArray:
	var errs := PackedStringArray()
	if not spec.has("counters"):
		return errs
	if not (spec.get("counters") is Array):
		errs.append("counters must be a list of {segment, item_id}")
		return errs
	var segs := QuestJson.arr(resolved.get("segments"))
	for c: Variant in spec.get("counters"):
		var cd := QuestJson.dict(c)
		var idx := QuestJson.i(cd.get("segment"), -1)
		var item_id := QuestJson.s(cd.get("item_id"))
		if idx < 0 or idx >= segs.size():
			errs.append("counter segment %d is not a segment of the line (it has %d)" % [idx, segs.size()])
		elif not String(QuestJson.dict(segs[idx]).get("text", "")).strip_edges().is_valid_int():
			errs.append("counter segment %d ('%s') is not a number" % [idx, QuestJson.dict(segs[idx]).get("text", "")])
		if item_id.is_empty() or (db != null and not db.has("items", item_id)):
			errs.append("counter item '%s' is not a canonical item" % item_id)
	return errs


## Problems with the parts of a "parts" line spec: not a list, empty, a part that does not resolve (a composite line
## would otherwise still show the parts that do, hiding the broken one), or a part with its own "counters" (never
## applied: they belong on the parts line). Empty = valid, or not a "parts" spec.
static func part_problems(spec: Dictionary, db: ContentDB) -> PackedStringArray:
	var errs := PackedStringArray()
	if not spec.has("parts"):
		return errs
	if not (spec.get("parts") is Array) or (spec.get("parts") as Array).is_empty():
		errs.append("parts must be a non-empty list of line specs")
		return errs
	var parts: Array = spec.get("parts")
	for i in parts.size():
		var part: Variant = parts[i]
		if not (part is Dictionary) or (part as Dictionary).is_empty():
			errs.append("part %d is not a line spec" % i)
			continue
		if (part as Dictionary).has("counters"):
			# The runner applies only the line's own counters (DialogueRunner._resolve), so a part's would be dropped.
			errs.append("part %d: counters on a part are not applied; put them on the parts line" % i)
		var r := resolve(part, db)
		if String(r["text"]).is_empty() and (r["segments"] as Array).is_empty():
			errs.append("part %d %s does not resolve" % [i, JSON.stringify(part)])
		else:
			for p in part_problems(part, db):
				errs.append("part %d: %s" % [i, p])
	return errs


## Plain text of a segment list.
static func plain(segments: Array) -> String:
	var parts := PackedStringArray()
	for s: Dictionary in segments:
		parts.append(String(s.get("text", "")))
	return "".join(parts)


# --- internals ------------------------------------------------------------------------------------------------

static func _resolve_quest(spec: Dictionary, db: ContentDB) -> Dictionary:
	var qid := QuestJson.s(spec.get("quest"))
	var rec := db.quest(qid)
	if rec.is_empty():
		return _empty()
	var path := "canonical/quests/%s.json#" % qid
	if spec.has("name"):
		var out := normalize_line({"text": QuestJson.s(rec.get("name"))})
		out["source"] = path + "name"
		return out
	if spec.has("journal"):
		var lines := QuestJson.strings(QuestJson.dict(rec.get("journal")).get("lines"))
		var idx := QuestJson.i(spec.get("journal"))
		if idx < 0 or idx >= lines.size():
			return _empty()
		var out := normalize_line({"text": lines[idx]})
		out["source"] = path + "journal.lines[%d]" % idx
		return out
	var dlg := QuestJson.dict(rec.get("dialogue"))
	var remap := _remap_for(db, qid)
	var idx := QuestJson.i(spec.get("line"))
	if spec.has("quiz"):
		var quiz := QuestJson.dict(QuestJson.dict(dlg.get("on_completion")).get("quiz"))
		var which := QuestJson.s(spec.get("quiz"))
		var line: Variant = null
		match which:
			"question":
				line = quiz.get("question")
			"choice":
				line = _at(QuestJson.arr(quiz.get("choices")), idx)
			"wrong":
				line = _at(QuestJson.arr(quiz.get("wrong_answer_responses")), idx)
			"right":
				line = quiz.get("correct_answer_response")
		if line == null:
			return _empty()
		var out := normalize_line(line, remap, db)
		out["source"] = path + "dialogue.on_completion.quiz.%s%s" % [which, "[%d]" % idx if which in ["choice", "wrong"] else ""]
		return out
	var section_name := QuestJson.s(spec.get("section"))
	var sec := QuestJson.dict(dlg.get(section_name))
	var lines: Array = []
	var where := "dialogue.%s" % section_name
	if spec.has("branch"):
		var state := QuestJson.s(spec.get("branch"))
		for b: Variant in QuestJson.arr(sec.get("branches")):
			if QuestJson.s(QuestJson.dict(b).get("state")) == state:
				lines = QuestJson.arr(QuestJson.dict(b).get("lines"))
				break
		where += ".branches[%s]" % state
	else:
		lines = QuestJson.arr(sec.get("lines"))
	if idx < 0 or idx >= lines.size():
		return _empty()
	var out := normalize_line(lines[idx], remap, db)
	out["source"] = path + "%s.lines[%d]" % [where, idx]
	return out


## A "parts" line: each part resolved, one paragraph each (PART_BREAK between them); parts that do not resolve are
## skipped. Counters of the whole spec index the joined segments (the runner applies them after this).
static func _parts(spec: Dictionary, db: ContentDB) -> Dictionary:
	var texts := PackedStringArray()
	var segs: Array = []
	var sources := PackedStringArray()
	for part: Variant in QuestJson.arr(spec.get("parts")):
		if not (part is Dictionary):
			continue
		var r := resolve(part, db)
		if String(r["text"]).is_empty() and (r["segments"] as Array).is_empty():
			continue
		if not segs.is_empty():
			segs.append(segment(PART_BREAK))
		segs.append_array(r["segments"])
		texts.append(String(r["text"]) if not String(r["text"]).is_empty() else plain(r["segments"]))
		if not String(r["source"]).is_empty():
			sources.append(String(r["source"]))
	return {"text": PART_BREAK.join(texts), "segments": segs, "source": " + ".join(sources)}


static func _literal(d: Dictionary) -> Dictionary:
	var text := QuestJson.s(d.get("text"))
	var raw := QuestJson.arr(d.get("segments"))
	var segs: Array = normalize_segments(raw) if not raw.is_empty() else ([segment(text)] if not text.is_empty() else [])
	if text.is_empty() and not segs.is_empty():
		text = plain(segs)
	return {"text": text, "segments": segs, "source": QuestJson.s(d.get("source"))}


static func _empty() -> Dictionary:
	return {"text": "", "segments": [], "source": ""}


static func _at(a: Array, idx: int) -> Variant:
	return a[idx] if idx >= 0 and idx < a.size() else null


static func _known(db: ContentDB, kind: String, rid: String) -> bool:
	if db == null:
		return false
	var domains := {"npc": "npcs", "item": "items", "monster": "monsters", "map": "maps", "quest": "quests"}
	var domain_name := QuestJson.s(domains.get(kind))
	return not domain_name.is_empty() and db.has(domain_name, rid)


## Item-db id for an icon key (items' game_item_id), "" when unknown.
static func _item_for_icon(db: ContentDB, icon_key: String) -> String:
	if db == null:
		return ""
	var dbid := db.get_instance_id()
	if not _icon_cache.has(dbid):
		var m := {}
		var items: Dictionary = db.domain("items")
		for iid: String in items:
			var gk := QuestJson.s(QuestJson.dict(items[iid]).get("game_item_id"))
			if not gk.is_empty():
				m[gk] = iid
		_icon_cache[dbid] = m
	return String((_icon_cache[dbid] as Dictionary).get(icon_key, ""))


## The NPC domain carries corrected dialogue links (ref.meowdb_link_id = MeowDB's raw link, ref.id = the item the
## quest actually uses, docs/canonical/npcs.md "Discrepancies"). Quest-domain dialogue keeps the raw link, so refs
## are remapped per quest with what the NPC files say.
static func _remap_for(db: ContentDB, qid: String) -> Dictionary:
	if db == null:
		return {}
	var key := "%d:%s" % [db.get_instance_id(), qid]
	if _remap_cache.has(key):
		return _remap_cache[key]
	var m := {}
	var npcs: Dictionary = db.domain("npcs")
	for nid: String in npcs:
		for qd: Variant in QuestJson.arr(QuestJson.dict(npcs[nid]).get("quest_dialogue")):
			var qdd := QuestJson.dict(qd)
			if QuestJson.s(qdd.get("quest_id")) == qid:
				_collect_remaps(qdd, m)
	_remap_cache[key] = m
	return m


static func _collect_remaps(v: Variant, m: Dictionary) -> void:
	if v is Dictionary:
		var d: Dictionary = v
		var ref := QuestJson.dict(d.get("ref"))
		if ref.has("meowdb_link_id"):
			m[QuestJson.s(ref.get("meowdb_link_id"))] = QuestJson.s(ref.get("id"))
		for k: Variant in d:
			if d[k] is Dictionary or d[k] is Array:
				_collect_remaps(d[k], m)
	elif v is Array:
		for e: Variant in v:
			_collect_remaps(e, m)
