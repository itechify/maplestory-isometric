class_name GameplayDataChecks
extends RefCounted
## The gameplay systems' own data validation, run headless: the problems that would make a quest, an NPC or a
## conversation unplayable or silently wrong, as the game itself reads the data.
##
##   quest_data      QuestCatalog.validate(): unknown objective kinds, unsupported "other" objectives (the quest could
##                   never complete), unsupported prerequisites, quiz choices, empty reward groups, adaptation files
##   npc_data        NpcCatalog.validate(): the NPC's map, quests and shop, both sides of every quest's start / end NPC
##   dialogue_data   NpcDialogueBuilder.validate_all(): every NPC's generated conversation plus its override file
##                   (dangling node targets, line specs that resolve to no text, conditions, actions, counters)
##
## These classes read the data the way the game does, which assumes data that is structurally valid. So they read only
## the records the data checks before them (ids, schema, provenance, references, adaptation) found no error in: every
## record with an error finding, and every file that failed to load, is left out of a copy of the content, the three
## validations run on that copy, and each finding is reported unless it names a left-out record. A finding on a
## left-out record would be read over broken data, and one that names a left-out record may only be the consequence of
## leaving it out ("prerequisite quest 1005 does not exist"); the run fails on that record's own error anyway. The stat
## gameplay_checks_run counts the run, and gameplay_records_left_out (only when there are any) the records left out.
## A finding's domain and id come from the message's own prefix ("quest 1002: ...", "npc 7 (Todd): ...",
## "misostory/quests/1002.json: ...", "dialogue 9 node ...").

const QUEST_CHECK := "quest_data"
const NPC_CHECK := "npc_data"
const DIALOGUE_CHECK := "dialogue_data"

var db: ContentDB
var report: ValidationReport
var _prefix := RegEx.new()
var _miso_file := RegEx.new()
var _data_path := RegEx.new()
## The records left out of this run (left_out_records()).
var _left_out: Dictionary = {}


func _init(content: ContentDB, into: ValidationReport) -> void:
	db = content
	report = into
	_prefix.compile("^(quest|npc|dialogue) ([^\\s:(]+)")
	_miso_file.compile("^misostory/([a-z_]+)/([^\\s:]+)\\.json")
	_data_path.compile("data/(canonical|misostory)/(?:([^/]+)/)?([^/]+)\\.json")


## Runs the three validations over the records the checks before found no error in.
func run() -> void:
	var content := db
	_left_out = left_out_records()
	if not _left_out.is_empty():
		content = sound_copy(_left_out)
		report.count("gameplay_records_left_out", _left_out.size())
	var quests := QuestCatalog.new(content)
	var npcs := NpcCatalog.new(content)
	_add(QUEST_CHECK, "quests", quests.validate())
	_add(NPC_CHECK, "npcs", npcs.validate())
	_add(DIALOGUE_CHECK, "dialogue", NpcDialogueBuilder.new(content, quests, npcs).validate_all())
	report.count("gameplay_checks_run")


## The records the report's error findings so far fall on, as "<domain>/<id>" (canonical), "misostory/<folder>/<id>"
## or "misostory/<table>" -> the record id. A load error names its file's record. An error with no record behind it
## (the sources index, the crosswalk) leaves nothing out.
func left_out_records() -> Dictionary:
	var out := {}
	for f in report.errors():
		var domain := str(f.domain)
		var id := str(f.id)
		if domain == "load":
			var m := _data_path.search(id)
			if m == null:
				continue
			var root := "" if m.get_string(1) == "canonical" else "misostory"
			var parts := PackedStringArray()
			for part in [root, m.get_string(2), m.get_string(3)]:
				if part != "":
					parts.append(part)
			out["/".join(parts)] = m.get_string(3)
		elif id == "":
			continue
		elif domain != "" and db.canonical.has(domain) and db.has(domain, id):
			out["%s/%s" % [domain, id]] = id
		elif domain == "misostory" and (db.miso.get("", {}) as Dictionary).has(id):
			out["misostory/" + id] = id
		elif domain.begins_with("misostory/") and (db.miso.get(domain.trim_prefix("misostory/"), {}) as Dictionary).has(id):
			out["%s/%s" % [domain, id]] = id
	return out


## A copy of the content without the `left_out` records (keys as left_out_records() makes them). Shallow: only the
## dictionaries that lose a record are copied, and the records themselves are shared (the catalogs only read them).
func sound_copy(left_out: Dictionary) -> ContentDB:
	var c := ContentDB.new()
	c.canonical = db.canonical.duplicate(false)
	c.miso = db.miso.duplicate(false)
	c.load_errors = db.load_errors.duplicate()
	c.loaded = true
	for key: String in left_out:
		var tree := c.canonical
		var rest := key
		if key.begins_with("misostory/"):
			tree = c.miso
			rest = key.trim_prefix("misostory/")
		# "<folder>/<id>" (a nested canonical id keeps its own slash: formulas "group/name"), or a top-level table.
		var cut := rest.find("/")
		var folder := rest.substr(0, cut) if cut >= 0 else ""
		var id := rest.substr(cut + 1) if cut >= 0 else rest
		if not (tree.get(folder, null) is Dictionary):
			continue
		var records: Dictionary = (tree[folder] as Dictionary).duplicate(false)
		records.erase(id)
		tree[folder] = records
	return c


func _add(check: String, default_domain: String, messages: PackedStringArray) -> void:
	for msg in messages:
		var where := locate(msg, default_domain)
		if _names_left_out(msg, where):
			continue
		report.error(check, where[0], where[1], msg)


## True when a finding falls on a left-out record or names one by its id.
func _names_left_out(msg: String, where: Array) -> bool:
	if _left_out.is_empty():
		return false
	if _left_out.has("%s/%s" % [where[0], where[1]]):
		return true
	for key: String in _left_out:
		if names_id(msg, str(_left_out[key])):
			return true
	return false


## True when `id` appears in `msg` as a whole id, not inside a longer number or slug ("7" is not in "1007"). A number
## may follow a letter, as in the dialogue node ids the builder makes ("q1005.offer.1" names quest 1005).
static func names_id(msg: String, id: String) -> bool:
	if id == "":
		return false
	var at := msg.find(id)
	while at >= 0:
		var before := msg.substr(at - 1, 1) if at > 0 else ""
		var after := msg.substr(at + id.length(), 1)
		if not _continues(before, id.left(1)) and not _continues(after, id.right(1)):
			return true
		at = msg.find(id, at + 1)
	return false


## True when `ch` next to an id's end character `end` would make them one longer id: a digit next to a digit; any
## letter, digit, "_" or "-" next to a letter.
static func _continues(ch: String, end: String) -> bool:
	if ch == "":
		return false
	if end.is_valid_int():
		return ch.is_valid_int()
	return ch.is_valid_int() or ch.is_valid_identifier() or ch == "-"


## [domain, id] named by a message's prefix; [default_domain, ""] when it names none.
func locate(msg: String, default_domain: String) -> Array:
	var m := _miso_file.search(msg)
	if m != null:
		return ["misostory/" + m.get_string(1), m.get_string(2)]
	m = _prefix.search(msg)
	if m != null:
		var domain: String = {"quest": "quests", "npc": "npcs", "dialogue": "npcs"}[m.get_string(1)]
		return [domain, m.get_string(2)]
	return [default_domain, ""]
