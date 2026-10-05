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
## These classes read the data the way the game does, which assumes data that is structurally valid. So they run
## only when the data checks before them (ids, schema, provenance, references, adaptation) found no error; otherwise
## the run already fails and the stat gameplay_checks_skipped says why these did not run. A finding's domain and id
## come from the message's own prefix ("quest 1002: ...", "npc 7 (Todd): ...", "misostory/quests/1002.json: ...",
## "dialogue 9 node ...").

const QUEST_CHECK := "quest_data"
const NPC_CHECK := "npc_data"
const DIALOGUE_CHECK := "dialogue_data"

var db: ContentDB
var report: ValidationReport
var _prefix := RegEx.new()
var _miso_file := RegEx.new()


func _init(content: ContentDB, into: ValidationReport) -> void:
	db = content
	report = into
	_prefix.compile("^(quest|npc|dialogue) ([^\\s:(]+)")
	_miso_file.compile("^misostory/([a-z_]+)/([^\\s:]+)\\.json")


## Runs the three validations, unless the report already has errors.
func run() -> void:
	if report.has_errors():
		report.count("gameplay_checks_skipped")
		return
	var quests := QuestCatalog.new(db)
	var npcs := NpcCatalog.new(db)
	_add(QUEST_CHECK, "quests", quests.validate())
	_add(NPC_CHECK, "npcs", npcs.validate())
	_add(DIALOGUE_CHECK, "dialogue", NpcDialogueBuilder.new(db, quests, npcs).validate_all())
	report.count("gameplay_checks_run")


func _add(check: String, default_domain: String, messages: PackedStringArray) -> void:
	for msg in messages:
		var where := locate(msg, default_domain)
		report.error(check, where[0], where[1], msg)


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
