extends TestCase
## Default talk with the per-NPC in-progress lines (owner ruling #9, data/misostory/dialogue/_rules.json
## default_talk.in_progress_lines): Sera's "Did you give my mirror to Heena?" shows only while 1001 is in progress and
## Sen's "What did my sister say?" only while 1004 is; otherwise each says its other line. Every other quest NPC keeps
## the general rule (first line until all its quests are done, then the last), and the rule validation accepts the
## shipped overrides and rejects one naming a line, an NPC or a quest that does not exist.

const HEENA := "1"
const SERA := "2"
const NINA := "4"
const SEN := "5"
const SERA_LINE_0 := "It's a fine day for laundry, don't you think?"
const SERA_MIRROR := "Did you give my mirror to Heena? When will she help me with the laundry..."
const SERA_REMINDER := "It looks like you haven't delivered the mirror to Heena yet. Please hurry!"
const SEN_LINE_0 := "There's nothing to eat in here. Oh..."
const SEN_SISTER := "What did my sister say? Oh, I'm so hungry..."

var bus: Node
var character: CharacterState
var service: QuestService
var talk: NpcInteraction


func parity_keys() -> Dictionary:
	return {
		"test_sera_before_during_and_after_1001": ["npc:2", "quest:1001"],
		"test_sen_before_during_and_after_1004": ["npc:5", "quest:1004"],
	}


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	character = CharacterState.new()
	service = QuestService.create(bus, db(), character, RandomNumberGenerator.new(), func() -> float: return 2.0)
	service.attach()
	talk = NpcInteraction.new(service)


func after_each() -> void:
	service.detach()
	bus.free()


## The first page talking to the NPC shows now, then the chat is closed.
func _first_text(npc_id: String) -> String:
	var v := talk.talk(npc_id)
	var t := String(v.get("text", "")) if bool(v.get("open", false)) else "(closed)"
	talk.close()
	return t


## The page the NPC's default talk ("talk" node) opens on now, whatever quest entry the conversation would show first.
func _default_talk(npc_id: String) -> String:
	var g := talk.graph_for(npc_id)
	var start := g.start
	g.start = "talk"
	var r := DialogueRunner.new()
	var v := r.start(g, DialogueContext.new(service.engine, npc_id), {"npc_id": npc_id})
	g.start = start
	return String(v.get("text", ""))


## The builder over a copy of the content whose _rules.json is `rules` (null: no in-progress lines at all).
func _builder_with(in_progress: Variant) -> NpcDialogueBuilder:
	var d := ContentDB.new()
	d.canonical = db().canonical
	d.miso = db().miso.duplicate(false)
	var dlg: Dictionary = (db().miso["dialogue"] as Dictionary).duplicate(false)
	var rules: Dictionary = (dlg["_rules"] as Dictionary).duplicate(true)
	if in_progress == null:
		(rules["default_talk"] as Dictionary).erase("in_progress_lines")
	else:
		rules["default_talk"]["in_progress_lines"] = in_progress
	dlg["_rules"] = rules
	d.miso["dialogue"] = dlg
	d.loaded = true
	return NpcDialogueBuilder.new(d)


func _complete(qid: String) -> void:
	character.quests.start(qid, 0.0)
	character.quests.complete(qid, 1.0)


func test_sera_before_during_and_after_1001() -> void:
	assert_eq(_first_text(SERA), SERA_LINE_0, "before: a new character")
	_complete("1000")
	assert_eq(_default_talk(SERA), SERA_LINE_0, "before 1001 (1000 done, 1001 offered)")
	assert_true(bool(service.accept("1001", SERA)["ok"]))
	# While 1001 is in progress Sera's conversation opens on the canonical reminder (1001's wrong_npc branch), as before
	# the ruling; her default talk, reached only without a quest entry, is the mid-quest line.
	assert_eq(_first_text(SERA), SERA_REMINDER, "during: the quest entry comes first")
	assert_eq(_default_talk(SERA), SERA_MIRROR, "during: the mirror line")
	assert_true(bool(service.complete("1001", {"at_npc_id": HEENA})["ok"]))
	assert_eq(_first_text(SERA), SERA_LINE_0, "after: back to her other line, not the mirror line")
	assert_eq(_default_talk(SERA), SERA_LINE_0)


func test_sen_before_during_and_after_1004() -> void:
	assert_eq(_first_text(SEN), SEN_LINE_0, "before: a new character")
	_complete("1003")
	assert_eq(_default_talk(SEN), SEN_LINE_0, "before 1004 (1003 done, 1004 offered)")
	assert_true(bool(service.accept("1004", SEN)["ok"]))
	assert_eq(_first_text(SEN), SEN_SISTER, "during: 1004 has no reminder, so the talk shows the line")
	assert_true(bool(service.complete("1004", {"at_npc_id": NINA})["ok"]))
	assert_eq(_first_text(SEN), SEN_LINE_0, "after: back to his other line")


func test_other_quest_npcs_keep_the_general_rule() -> void:
	var shipped := NpcDialogueBuilder.new(db())
	var without := _builder_with(null)
	var npcs := NpcCatalog.new(db())
	var named := {}
	for r: Dictionary in shipped.in_progress_lines():
		named[String(r["npc_id"])] = true
	assert_eq(named.keys().size(), 2)
	assert_true(named.has(SERA) and named.has(SEN))
	for nid in npcs.ids():
		var a := shipped.build(nid)
		var b := without.build(nid)
		if named.has(nid):
			assert_ne(a.nodes.get("talk"), b.nodes.get("talk"), "%s's talk changes" % nid)
			continue
		assert_eq(a.nodes, b.nodes, "NPC %s (%s) talks as before" % [nid, npcs.get_def(nid).name])
	# Heena still says her first line before her quests and her last after them (the rule's model case).
	assert_eq(_first_text(HEENA).is_empty(), false)
	var heena := npcs.get_def(HEENA)
	for q in heena.all_quests():
		_complete(q)
	assert_eq(_first_text(HEENA), String((heena.dialogue_lines[heena.dialogue_lines.size() - 1] as Dictionary).get("text", "")))


func test_rule_validation_accepts_the_overrides() -> void:
	assert_eq(NpcDialogueBuilder.new(db()).validate_rules(), PackedStringArray())
	var rules: Dictionary = db().miso["dialogue"]["_rules"]
	var why := String(rules["default_talk"]["reason"])
	assert_false(why.contains("an owner decision could"), "the reason no longer leaves the decision open")
	assert_true(why.contains("#9"), why)
	for r: Dictionary in NpcDialogueBuilder.new(db()).in_progress_lines():
		assert_eq(r.get("verified"), false, "an adaptation")
		assert_true(String(r.get("decision", "")).begins_with("#9"), str(r))
		assert_false(String(r.get("reason", "")).is_empty())


func test_rule_validation_rejects_a_missing_line_npc_or_quest() -> void:
	var row := {"npc_id": SEN, "line": 1, "quest_id": "1004", "reason": "test", "verified": false}
	var bad_line := row.duplicate()
	bad_line["line"] = 2
	assert_true(_has(_builder_with([bad_line]).validate_rules(), "has 2 \"What X Says\" lines, so line 2 does not exist"))
	var bad_quest := row.duplicate()
	bad_quest["quest_id"] = "9999"
	assert_true(_has(_builder_with([bad_quest]).validate_rules(), "quest_id '9999' is not a canonical quest"))
	var bad_npc := row.duplicate()
	bad_npc["npc_id"] = "9999"
	assert_true(_has(_builder_with([bad_npc]).validate_rules(), "npc_id '9999' is not a canonical NPC"))
	var both := row.duplicate()
	both["line"] = 0
	assert_true(_has(_builder_with([row, both]).validate_rules(), "has no line left for the general rule"))
	assert_true(_has(_builder_with([row, row]).validate_rules(), "line 1 is already overridden"))
	assert_eq(_builder_with([row]).validate_rules(), PackedStringArray(), "a good row passes")
	# validate_all (the data validator's dialogue_data check) reports it too.
	assert_true(_has(_builder_with([bad_line]).validate_all(), "line 2 does not exist"))


func _has(errs: PackedStringArray, needle: String) -> bool:
	for e in errs:
		if e.contains(needle):
			return true
	fail("no error containing '%s' in %s" % [needle, errs])
	return false
