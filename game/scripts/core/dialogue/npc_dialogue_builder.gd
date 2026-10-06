class_name NpcDialogueBuilder
extends RefCounted
## Generates every NPC's conversation from canonical data (NPC lines, quest dialogue, quizzes, shops), then applies
## the NPC's override file data/misostory/dialogue/<npc_id>.json (add / replace / remove nodes). Nothing here names a
## specific NPC or quest: a new quest NPC needs only data.
##
## Generated graph (node ids):
##   start                 menu (auto_single) of the quest entries visible now, in this order:
##                           turn-ins of quests completed here and in progress   -> q<id>.turnin
##                           lost accept items of quests started here            -> q<id>.lost.0   (MeowDB "lost")
##                           reminders of quests started here, ended elsewhere   -> q<id>.reminder.0 (MeowDB "wrong_npc")
##                           offers of quests started here and available         -> q<id>.offer.0
##                         no entry -> talk. The menu text (several entries) is the NPC's first own line.
##   talk                  default talk: quest NPCs say their first "What X Says" line until all their quests are
##                         done, then the last one; other NPCs say all their lines in order; NPCs without quoted
##                         lines say their first idle-chatter line; shopkeepers -> shop.greeting -> open_shop.
##   q<id>.offer.<i>       on_accept lines; the last one is a Yes/No (accept). A quest with no "On accept" text
##                         (MeowDB gap, e.g. 1002) is offered as one quest card instead (speaker "journal"): its
##                         journal summary (line 0; the quest name without a journal) and the system prompt
##                         sys offer_prompt ("Accept this quest?") as a Yes/No.
##   q<id>.accepted.<i> / q<id>.declined.<i>    the accept / decline branches
##   q<id>.brief.<i>       quest card after accepting a quest offered that way (when it has no "accepted" lines): the
##                         canonical in-progress journal lines, i.e. the instructions (1002: "Press the hotkey I ...")
##   q<id>.turnin          branch: ready -> completion lines (if any) -> quiz (if any) -> reward pick (if any) ->
##                         complete; else missing_kills / missing_items
##   q<id>.done.<i>        on_completion main lines, then the quiz, q<id>.select or q<id>.complete (action) ->
##                         q<id>.ready.<i> or start
##   q<id>.quiz            menu of the quiz choices; each runs complete_quest with its quiz_choice (answer_quiz when
##                         the quest also has a selection reward, then q<id>.quiz_right -> q<id>.select); a wrong
##                         choice shows its wrong-answer line (paired with the wrong choices in order) and ends the chat
##   q<id>.select          menu of a selection reward (MeowDB rewardChoices); each choice completes with that pick
##   q<id>.reissue         re-issues lost accept items: after the canonical "lost" lines, or (adaptation
##                         reissue_lost_accept_items, MeowDB has no "lost" branch: 1002) first, followed by the
##                         canonical missing_items lines. A quest started and ended by the same NPC routes its turn-in
##                         there when the item is lost (no second menu entry).
##   transport.*           an NPC with transport routes (Shanks): greeting -> the route's canonical guide quote ->
##                         level / fare checks -> the unfinished quests of the boundary's region -> Yes/No -> depart
##                         (NpcTransport); several routes get a destination menu (transport.menu)
##   sys.*                 MisoStory system lines (inventory full, cannot accept / complete)
##
## Rules MeowDB does not give (which On accept line asks the question, which "What X Says" line default talk shows)
## are adaptation data in data/misostory/dialogue/_rules.json (RULES_FILE_ID); validate_all() rejects a rule value
## this builder does not implement.

const SYSTEM_FILE_ID := DialogueText.SYSTEM_FILE_ID
const RULES_FILE_ID := "_rules"
## A misostory/dialogue file named "_<name>" is a shared table, not an NPC override (AdaptationChecks.SHARED_TABLE_PREFIX).
const SHARED_TABLE_PREFIX := "_"
## Offer rule values (rules offer_prompt.line) this builder implements.
const OFFER_PROMPT_RULES: PackedStringArray = ["last_on_accept_line"]
## Default-talk rule values for quest NPCs (rules default_talk.quest_npc).
const QUEST_NPC_TALK_RULES: PackedStringArray = ["first_line_until_all_own_quests_completed_then_last_line",
	"all_lines_in_order"]
## Rules recorded with the one behaviour the code has: {rule path: implemented value}.
const FIXED_RULES := {
	"default_talk.townsfolk": "all_lines_in_order",
	"default_talk.no_quoted_lines": "first_idle_chatter_line",
	"quiz.wrong_answer": "ends_chat_quest_stays_in_progress",
	"quiz.after_right_answer": "ends_chat_next_quiz_needs_a_new_talk",
}

var db: ContentDB
var quests: QuestCatalog
var npcs: NpcCatalog
## data/misostory/dialogue/_rules.json ({} when absent: the defaults above apply).
var rules: Dictionary = {}


func _init(p_db: ContentDB = null, p_quests: QuestCatalog = null, p_npcs: NpcCatalog = null) -> void:
	db = p_db
	quests = p_quests if p_quests != null else QuestCatalog.new(db)
	npcs = p_npcs if p_npcs != null else NpcCatalog.new(db)
	rules = db.miso_entity("dialogue", RULES_FILE_ID) if db != null else {}


## A rule value from _rules.json ("offer_prompt.line"), or `fallback` when the file or the key is absent.
func rule(path: String, fallback: String) -> String:
	var parts := path.split(".")
	var node: Variant = rules
	for p in parts:
		node = QuestJson.dict(node).get(p)
	return QuestJson.s(node, fallback) if node is String else fallback


## The NPC's conversation: generated, then overridden. Empty graph (no nodes) for an unknown NPC.
func build(npc_id: String) -> DialogueGraph:
	var g := generate(npc_id)
	var o := db.miso_entity("dialogue", npc_id)
	if not o.is_empty():
		g.apply_override(o)
	return g


## The generated conversation without the override file.
func generate(npc_id: String) -> DialogueGraph:
	var g := DialogueGraph.new()
	g.id = "npc_" + npc_id
	g.npc_id = npc_id
	var n := npcs.get_def(npc_id)
	if n == null:
		return g
	var own_line := _own_line(n)
	var entries: Array = []
	# The quest records decide which quests an NPC starts and ends (the same lookups QuestEngine.npc_marker uses),
	# so a quest added as data is offered even if the NPC record does not list it yet; an adaptation can still
	# switch the behaviour off ("disabled_behaviors": ["quest"]).
	var quest_disabled := "quest" in QuestJson.strings(n.adaptation.get("disabled_behaviors"))
	var quest_npc := not quest_disabled and (n.has_behavior("quest") or not quests.started_by(npc_id).is_empty()
		or not quests.completed_by(npc_id).is_empty())
	if quest_npc:
		for qid in quests.completed_by(npc_id):
			_add_turn_in(g, quests.get_def(qid), entries)
		for qid in quests.started_by(npc_id):
			_add_start_side(g, quests.get_def(qid), entries)
	g.set_node("start", {"type": "menu", "line": own_line, "auto_single": true, "empty_next": "talk",
		"choices": entries})
	_add_talk(g, n)
	_add_system_nodes(g)
	return g


## Builds and validates every NPC's conversation. Empty = valid.
func validate_all() -> PackedStringArray:
	var errs := PackedStringArray()
	for nid in npcs.ids():
		errs.append_array(build(nid).validate(db))
	for oid: String in db.miso.get("dialogue", {}):
		var o: Dictionary = db.miso["dialogue"][oid]
		# "_" files are shared tables (system lines, rules), not NPC overrides.
		if not oid.begins_with(SHARED_TABLE_PREFIX) and not npcs.has(oid):
			errs.append("misostory/dialogue/%s.json: no canonical npc %s" % [oid, oid])
		if QuestJson.s(o.get("reason")).is_empty():
			errs.append("misostory/dialogue/%s.json: missing top-level reason" % oid)
		if not o.has("verified"):
			errs.append("misostory/dialogue/%s.json: missing top-level verified flag" % oid)
	errs.append_array(validate_rules())
	return errs


## Problems with _rules.json: a rule value this builder does not implement, or a shop title without "{npc}".
func validate_rules() -> PackedStringArray:
	var errs := PackedStringArray()
	if rules.is_empty():
		return errs
	var at := "misostory/dialogue/%s.json" % RULES_FILE_ID
	var offer := rule("offer_prompt.line", OFFER_PROMPT_RULES[0])
	if not (offer in OFFER_PROMPT_RULES):
		errs.append("%s: offer_prompt.line '%s' is not implemented (%s)" % [at, offer, ", ".join(OFFER_PROMPT_RULES)])
	var talk := rule("default_talk.quest_npc", QUEST_NPC_TALK_RULES[0])
	if not (talk in QUEST_NPC_TALK_RULES):
		errs.append("%s: default_talk.quest_npc '%s' is not implemented (%s)" % [at, talk, ", ".join(QUEST_NPC_TALK_RULES)])
	for path: String in FIXED_RULES:
		var v := rule(path, String(FIXED_RULES[path]))
		if v != String(FIXED_RULES[path]):
			errs.append("%s: %s '%s' is not implemented (the code does '%s')" % [at, path, v, FIXED_RULES[path]])
	if not rule("shop_window_title.format", "{npc}'s Shop").contains("{npc}"):
		errs.append("%s: shop_window_title.format must contain {npc}" % at)
	return errs


## The shop window's title for an NPC (rules shop_window_title.format, "{npc}'s Shop" by default): MeowDB has no shop
## title, so this is MisoStory text.
static func shop_title(npc_name: String, content: ContentDB) -> String:
	var fmt := "{npc}'s Shop"
	if content != null:
		var t: Variant = QuestJson.dict(content.miso_entity("dialogue", RULES_FILE_ID).get("shop_window_title")).get("format")
		if t is String and String(t).contains("{npc}"):
			fmt = t
	return fmt.replace("{npc}", npc_name)


# --- quest offer side -----------------------------------------------------------------------------------------

func _add_start_side(g: DialogueGraph, d: QuestDef, entries: Array) -> void:
	var q := d.id
	var p := "q%s." % q
	var elsewhere := d.end_npc_id != d.start_npc_id
	var has_lost := d.reissues_lost_items()
	# MeowDB files "lost" and "wrong_npc" under On completion, but they read as the start NPC speaking
	# (docs/canonical/npcs.md, speaker caveat): MisoStory routes them to the start NPC.
	if has_lost:
		var lost_entry := _add_reissue(g, d)
		# A quest this NPC also ends routes its turn-in to the re-issue instead (see _add_turn_in): one entry.
		if elsewhere:
			entries.append(_entry(d, "lost", {"type": "all", "of": [_status(q, QuestLog.IN_PROGRESS),
				{"type": "quest_items_lost", "quest": q}]}, lost_entry))
	if elsewhere and d.has_branch("on_completion", "wrong_npc"):
		_chain(g, p + "reminder", _branch_specs(d, "on_completion", "wrong_npc"), "", d.name)
		var cond := _status(q, QuestLog.IN_PROGRESS)
		if has_lost:
			cond = {"type": "all", "of": [cond, {"type": "not", "of": {"type": "quest_items_lost", "quest": q}}]}
		entries.append(_entry(d, "reminder", cond, p + "reminder.0"))
	_add_offer(g, d)
	entries.append(_entry(d, "offer", {"type": "quest_available", "quest": q}, p + "offer.0"))


## The re-issue of lost accept items; returns the node the conversation enters it by. With MeowDB's "lost" branch:
## its lines, then q<id>.reissue. With only the adaptation (reissue_lost_accept_items; MeowDB has no "lost" lines, so
## none are invented): q<id>.reissue first, then the quest's canonical missing_items lines (Roger: "Eat the Roger's
## Apple I gave you ..."), which read as the NPC handing the item over again.
func _add_reissue(g: DialogueGraph, d: QuestDef) -> String:
	var p := "q%s." % d.id
	var lost := _branch_specs(d, "on_completion", "lost_items")
	var after := ""
	var entry := p + "reissue"
	if not lost.is_empty():
		_chain(g, p + "lost", lost, p + "reissue", d.name)
		entry = p + "lost.0"
	else:
		var asking := _branch_specs(d, "on_completion", "missing_items")
		_chain(g, p + "lost", asking, "", d.name)
		after = p + "lost.0" if not asking.is_empty() else ""
	g.set_node(p + "reissue", {"type": "action", "actions": [{"type": "reissue_quest_items", "quest": d.id}],
		"next": after, "on_fail": {"inventory_full": "sys.inventory_full", "*": ""}})
	return entry


func _add_offer(g: DialogueGraph, d: QuestDef) -> void:
	var q := d.id
	var p := "q%s." % q
	var specs: Array = []
	var speaker := "npc"
	for i in d.section_lines("on_accept").size():
		specs.append({"quest": q, "section": "on_accept", "line": i})
	var accepted := _branch_specs(d, "on_accept", "accepted")
	var declined := _branch_specs(d, "on_accept", "declined")
	var after_accept := p + "accepted.0" if not accepted.is_empty() else ""
	if specs.is_empty():
		# No canonical "On accept" text (MeowDB gap, e.g. 1002): NPC speech would be invented, so the quest is offered
		# as a quest card. The question is the journal summary (else the quest name) under which the generic system
		# prompt asks to accept; the canonical in-progress journal lines (the instructions) follow the accept.
		speaker = "journal"
		var summary := {"quest": q, "journal": 0} if not d.journal_lines.is_empty() else {"quest": q, "name": true}
		specs.append({"parts": [summary, {"system": "offer_prompt"}]})
		if accepted.is_empty():
			var brief := _journal_brief_specs(d)
			_chain(g, p + "brief", brief, "", d.name, "journal")
			if not brief.is_empty():
				after_accept = p + "brief.0"
	for i in specs.size():
		var nid := p + "offer.%d" % i
		if i < specs.size() - 1:
			g.set_node(nid, {"type": "say", "line": specs[i], "next": p + "offer.%d" % (i + 1), "title": d.name, "speaker": speaker})
		else:
			g.set_node(nid, {"type": "yes_no", "line": specs[i], "title": d.name, "speaker": speaker,
				"yes": {"actions": [{"type": "accept_quest", "quest": q}],
					"next": after_accept,
					"on_fail": {"inventory_full": "sys.inventory_full", "*": "sys.cannot_accept"}},
				"no": {"next": p + "declined.0" if not declined.is_empty() else ""}})
	_chain(g, p + "accepted", accepted, "", d.name)
	_chain(g, p + "declined", declined, "", d.name)


## The in-progress journal lines (the quest's instructions), as QuestEngine.journal_text reads them: the middle
## lines of a journal of 3 or more lines. A 1- or 2-line journal has none apart from line 0 (already the question).
func _journal_brief_specs(d: QuestDef) -> Array:
	var out: Array = []
	for i in range(1, d.journal_lines.size() - 1):
		out.append({"quest": d.id, "journal": i})
	return out


# --- quest turn-in side ---------------------------------------------------------------------------------------

func _add_turn_in(g: DialogueGraph, d: QuestDef, entries: Array) -> void:
	var q := d.id
	var p := "q%s." % q
	var main := _main_specs(d, "on_completion")
	var ready := _branch_specs(d, "on_completion", "ready")
	var kills := _branch_specs(d, "on_completion", "missing_kills")
	var items := _branch_specs(d, "on_completion", "missing_items")
	var has_quiz := not d.quiz.is_empty()
	var has_selection := not d.reward_selection.is_empty()

	# What happens once the quest is ready to turn in.
	var finish := p + "complete"
	if has_selection:
		finish = p + "select"
		_add_selection(g, d, ready)
	g.set_node(p + "complete", {"type": "action", "actions": [{"type": "complete_quest", "quest": q}],
		"next": p + "ready.0" if not ready.is_empty() else "start",
		"on_fail": {"inventory_full": "sys.inventory_full", "*": "sys.cannot_complete"}})
	# Main completion lines come first, then the quiz (if any), then the reward pick / completion.
	var after_main := finish
	if has_quiz:
		after_main = p + "quiz"
		_add_quiz(g, d, has_selection, ready)
	var on_ready := after_main
	if not main.is_empty():
		on_ready = p + "done.0"
		_chain(g, p + "done", main, after_main, d.name)
	_chain(g, p + "ready", ready, "", d.name)
	_chain(g, p + "missing_kills", kills, "", d.name)
	_chain(g, p + "missing_items", items, "", d.name)

	var cases: Array = [{"condition": {"type": "quest_ready", "quest": q}, "next": on_ready}]
	if d.start_npc_id == d.end_npc_id and d.reissues_lost_items():
		# Started here too: a lost accept item is re-issued from the turn-in (the start side adds no second entry).
		cases.append({"condition": {"type": "quest_items_lost", "quest": q},
			"next": p + ("lost.0" if d.has_branch("on_completion", "lost_items") else "reissue")})
	if not kills.is_empty():
		cases.append({"condition": {"type": "objective", "quest": q, "kind": "monster_kills", "done": false},
			"next": p + "missing_kills.0"})
	if not items.is_empty():
		cases.append({"condition": {"type": "any", "of": [
			{"type": "objective", "quest": q, "kind": "item_collection", "done": false},
			{"type": "objective", "quest": q, "kind": "item_usage", "done": false}]}, "next": p + "missing_items.0"})
	var fallback := "talk"
	if not kills.is_empty():
		fallback = p + "missing_kills.0"
	elif not items.is_empty():
		fallback = p + "missing_items.0"
	g.set_node(p + "turnin", {"type": "branch", "cases": cases, "default": fallback})
	entries.append(_entry(d, "turnin", _status(q, QuestLog.IN_PROGRESS), p + "turnin"))


## The quiz menu. Without a selection reward each choice completes the quest with its quiz_choice (graded against
## canonical correct_choice_index), then shows the correct-answer line and the "ready" lines. With a selection reward
## each choice only grades the answer (answer_quiz); the correct-answer line then leads to the reward pick, which
## completes the quest.
func _add_quiz(g: DialogueGraph, d: QuestDef, has_selection: bool = false, ready: Array = []) -> void:
	var q := d.id
	var p := "q%s." % q
	var choices := QuestJson.arr(d.quiz.get("choices"))
	var correct := QuestJson.i(d.quiz.get("correct_choice_index"), -1)
	var wrong_lines := QuestJson.arr(d.quiz.get("wrong_answer_responses"))
	for k in wrong_lines.size():
		g.set_node(p + "quiz_wrong.%d" % k, {"type": "say", "line": {"quest": q, "quiz": "wrong", "line": k},
			"next": "", "title": d.name, "back": false})
	var after_right := ""
	if has_selection:
		after_right = p + "select"
	elif not ready.is_empty():
		after_right = p + "ready.0"
	var right_line := {"quest": q, "quiz": "right"}
	if QuestJson.dict(d.quiz.get("correct_answer_response")).is_empty():
		# No canonical correct-answer line: go straight on.
		right_line = {}
	if right_line.is_empty():
		g.set_node(p + "quiz_right", {"type": "branch", "cases": [], "default": after_right})
	else:
		g.set_node(p + "quiz_right", {"type": "say", "line": right_line, "next": after_right, "title": d.name})
	var opts: Array = []
	var wrong_rank := 0
	for i in choices.size():
		# MeowDB lists one wrong-answer line per wrong choice, in choice order, without linking them; MisoStory
		# pairs them in that order (true for every Maple Island quiz).
		var wrong_target := "sys.cannot_complete"
		if i != correct:
			if not wrong_lines.is_empty():
				wrong_target = p + "quiz_wrong.%d" % mini(wrong_rank, wrong_lines.size() - 1)
			wrong_rank += 1
		var act := {"type": "answer_quiz", "quest": q, "choice": i} if has_selection \
			else {"type": "complete_quest", "quest": q, "quiz_choice": i}
		opts.append({"line": {"quest": q, "quiz": "choice", "line": i},
			"actions": [act],
			"next": p + "quiz_right",
			"on_fail": {"wrong_answer": wrong_target, "inventory_full": "sys.inventory_full", "*": "sys.cannot_complete"}})
	g.set_node(p + "quiz", {"type": "menu", "line": {"quest": q, "quiz": "question"}, "title": d.name,
		"auto_single": false, "empty_next": "", "choices": opts})


## A selection reward (MeowDB rewardChoices) becomes a menu of the items; picking one completes the quest.
func _add_selection(g: DialogueGraph, d: QuestDef, ready: Array) -> void:
	var q := d.id
	var p := "q%s." % q
	var opts: Array = []
	var group: Dictionary = d.reward_selection[0]
	for i in (group["items"] as Array).size():
		var it: Dictionary = group["items"][i]
		var item_name := QuestJson.s(db.item(it["item_id"]).get("name"), String(it["item_id"]))
		opts.append({"line": {"text": "%s x%d" % [item_name, int(it["count"])], "source": "canonical/items/%s.json#name" % it["item_id"]},
			"actions": [{"type": "complete_quest", "quest": q, "selection_index": i}],
			"next": p + "ready.0" if not ready.is_empty() else "start",
			"on_fail": {"inventory_full": "sys.inventory_full", "*": "sys.cannot_complete"}})
	g.set_node(p + "select", {"type": "menu", "line": {"quest": q, "name": true}, "title": d.name,
		"auto_single": false, "empty_next": "", "choices": opts})


# --- talk, shop, system ---------------------------------------------------------------------------------------

func _add_talk(g: DialogueGraph, n: NpcDef) -> void:
	var own := n.dialogue_lines.size()
	if n.has_behavior("shop"):
		g.set_node("talk", {"type": "branch", "cases": [], "default": "shop.greeting"})
		# MeowDB has no shop greeting (docs/canonical/npcs.md gaps): the NPC's own first line is used unless the
		# NPC's dialogue override picks another.
		g.set_node("shop.greeting", {"type": "say", "line": _own_line(n), "next": "shop.open"})
		g.set_node("shop.open", {"type": "action", "actions": [{"type": "open_shop", "shop": n.shop_id}], "next": ""})
		return
	if n.has_behavior("transport"):
		_add_transport(g, n)
		return
	if own == 0:
		g.set_node("talk", {"type": "say", "line": _own_line(n), "next": ""})
		return
	var mine := n.all_quests()
	var quest_rule := rule("default_talk.quest_npc", QUEST_NPC_TALK_RULES[0])
	if n.has_behavior("quest") and own >= 2 and not mine.is_empty() and quest_rule == QUEST_NPC_TALK_RULES[0]:
		# MeowDB does not label when each "What X Says" line is shown; the last one reads as the after-quest line
		# (Heena, Roger, Maria, Rain, Mai), so MisoStory shows it once all of the NPC's quests are completed
		# (rules default_talk.quest_npc, data/misostory/dialogue/_rules.json).
		var done_all: Array = []
		for q in mine:
			done_all.append(_status(q, QuestLog.COMPLETED))
		var before: Array = []
		for i in own - 1:
			before.append({"npc": n.id, "field": "dialogue", "line": i})
		_chain(g, "talk.before", before, "", "")
		_chain(g, "talk.after", [{"npc": n.id, "field": "dialogue", "line": own - 1}], "", "")
		g.set_node("talk", {"type": "branch", "cases": [{"condition": {"type": "all", "of": done_all},
			"next": "talk.after.0"}], "default": "talk.before.0"})
		return
	var all_lines: Array = []
	for i in own:
		all_lines.append({"npc": n.id, "field": "dialogue", "line": i})
	_chain(g, "talk.lines", all_lines, "", "")
	g.set_node("talk", {"type": "branch", "cases": [], "default": "talk.lines.0"})


## Transport (canonical transport.routes, e.g. Shanks). Per route i, nodes "transport.<i>.*":
##   guide     the route's canonical source quote (a "Notice": the MeowDB beginner guide's sentence, not NPC speech)
##   check     level below min_level -> level_low; mesos below fare_mesos -> no_mesos; quests of the boundary's region
##             unfinished -> warning (the list, chains grouped); else offer
##   offer     Yes/No (system text with the canonical destination and fare) -> depart (NpcTransport.depart)
## The greeting is the NPC's own first line (an override may pick another canonical line). MeowDB has no boarding
## dialogue (gap in npcs/15.json), so every line past the greeting is canonical guide text or a system line.
func _add_transport(g: DialogueGraph, n: NpcDef) -> void:
	var routes := QuestJson.arr(n.transport.get("routes"))
	var region := NpcTransport.unfinished_region(n.id, db)
	var first := "transport.0.guide" if routes.size() == 1 else "transport.menu"
	g.set_node("talk", {"type": "branch", "cases": [], "default": "transport.greeting"})
	g.set_node("transport.greeting", {"type": "say", "line": _own_line(n), "next": first})
	g.set_node("sys.cannot_travel", {"type": "say", "line": {"system": "cannot_travel"}, "next": "", "speaker": "system",
		"back": false})
	if routes.size() > 1:
		var opts: Array = []
		for i in routes.size():
			opts.append({"line": {"text": QuestJson.s(QuestJson.dict(routes[i]).get("to_map_name")),
				"source": "canonical/npcs/%s.json#transport.routes[%d].to_map_name" % [n.id, i]},
				"next": "transport.%d.guide" % i})
		g.set_node("transport.menu", {"type": "menu", "line": _own_line(n), "auto_single": false, "empty_next": "",
			"choices": opts})
	for i in routes.size():
		var r := QuestJson.dict(routes[i])
		var p := "transport.%d." % i
		var args := {"destination": QuestJson.s(r.get("to_map_name")), "fare": QuestJson.i(r.get("fare_mesos")),
			"min_level": QuestJson.i(r.get("min_level")), "region": region}
		var src := "canonical/npcs/%s.json#transport.routes[%d]" % [n.id, i]
		if QuestJson.s(r.get("source_quote")).is_empty():
			g.set_node(p + "guide", {"type": "branch", "cases": [], "default": p + "check"})
		else:
			g.set_node(p + "guide", {"type": "say", "line": {"npc": n.id, "route": i, "quote": true},
				"next": p + "check", "speaker": "system"})
		var cases: Array = [
			{"condition": {"type": "not", "of": {"type": "level", "min": args["min_level"]}}, "next": p + "level_low"},
			{"condition": {"type": "not", "of": {"type": "mesos", "min": args["fare"]}}, "next": p + "no_mesos"},
		]
		if not region.is_empty():
			cases.append({"condition": {"type": "unfinished_quests", "region": region}, "next": p + "warning"})
		g.set_node(p + "check", {"type": "branch", "cases": cases, "default": p + "offer"})
		for key: String in ["level_low", "no_mesos"]:
			var sys_key := "transport_level_too_low" if key == "level_low" else "transport_not_enough_mesos"
			g.set_node(p + key, {"type": "say", "line": {"system": sys_key, "args": args, "args_source": src},
				"next": "", "speaker": "system", "back": false})
		if not region.is_empty():
			g.set_node(p + "warning", {"type": "say", "speaker": "system", "next": p + "offer",
				"line": {"system": "departure_unfinished_quests", "args": args, "args_source": src,
					"live": {"quests": {"type": "unfinished_quests", "region": region}}}})
		g.set_node(p + "offer", {"type": "yes_no", "speaker": "system",
			"line": {"system": "transport_offer", "args": args, "args_source": src},
			"yes": {"actions": [{"type": "depart", "route": i}], "next": "",
				"on_fail": {"level_too_low": p + "level_low", "not_enough_mesos": p + "no_mesos", "*": "sys.cannot_travel"}},
			"no": {"next": ""}})


func _add_system_nodes(g: DialogueGraph) -> void:
	for key in ["inventory_full", "cannot_accept", "cannot_complete"]:
		g.set_node("sys." + key, {"type": "say", "line": {"system": key}, "next": "", "speaker": "system", "back": false})


# --- helpers --------------------------------------------------------------------------------------------------

## A chain of say nodes "<prefix>.0", "<prefix>.1", ... ; the last leads to `last_next`. `speaker` "" = the NPC.
func _chain(g: DialogueGraph, prefix: String, specs: Array, last_next: String, title: String,
		speaker: String = "") -> void:
	for i in specs.size():
		var nxt := prefix + ".%d" % (i + 1) if i < specs.size() - 1 else last_next
		var node := {"type": "say", "line": specs[i], "next": nxt}
		if not title.is_empty():
			node["title"] = title
		if not speaker.is_empty():
			node["speaker"] = speaker
		g.set_node(prefix + ".%d" % i, node)


func _main_specs(d: QuestDef, section_name: String) -> Array:
	var out: Array = []
	for i in d.section_lines(section_name).size():
		out.append({"quest": d.id, "section": section_name, "line": i})
	return out


func _branch_specs(d: QuestDef, section_name: String, state: String) -> Array:
	var out: Array = []
	for i in d.branch_lines(section_name, state).size():
		out.append({"quest": d.id, "section": section_name, "branch": state, "line": i})
	return out


func _entry(d: QuestDef, tag: String, condition: Dictionary, next_id: String) -> Dictionary:
	return {"line": {"quest": d.id, "name": true}, "quest_id": d.id, "tag": tag, "condition": condition, "next": next_id}


static func _status(q: String, st: String) -> Dictionary:
	return {"type": "quest_status", "quest": q, "is": st}


## The NPC's first own line: "What X Says" line 0, else idle chatter line 0, else its name as literal text.
static func _own_line(n: NpcDef) -> Dictionary:
	if not n.dialogue_lines.is_empty():
		return {"npc": n.id, "field": "dialogue", "line": 0}
	if not n.idle_chatter.is_empty():
		return {"npc": n.id, "field": "idle_chatter", "line": 0}
	return {"text": n.name, "source": "canonical/npcs/%s.json#name" % n.id}
