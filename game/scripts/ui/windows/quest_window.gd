class_name MisoQuestWindow
extends MisoWindow
## The Quest log (toggle_quests, Q / L). Three lists: In Progress, Available (quests the character can accept now,
## those whose start NPC stands on the current map first and marked "nearby": canonical npcs/<id>.json
## locations[].map_id, see npc_is_on_map) and Completed. The selected quest
## shows its status (with MeowDB's "Missable" tag when the record has it), the start and turn-in NPCs with their maps
## ("From Sam (Snail Hunting Ground I)  ·  turn in to Mai (A Split Road)"), its chain ("Mai's Training 2/3" and the
## steps, ticked when completed), its journal text, its objectives with check boxes and counts ("Snail 7/10",
## "Talk to Mai"; "Return to Roger" only for an NPC already met), its canonical rewards (EXP, mesos, fame, items,
## random and selectable item groups) and, once completed, the random reward actually received.
##
## Everything is read from QuestEngine (quest_summaries / quest_summary / availability / definition); the window
## never changes quest state. It refreshes on quest_* events and on inventory changes (item-collection counts are
## read live from the inventory).

const LIST_WIDTH := 200.0
const TAB_IN_PROGRESS := "in_progress"
const TAB_AVAILABLE := "available"
const TAB_COMPLETED := "completed"
const TABS: PackedStringArray = [TAB_IN_PROGRESS, TAB_AVAILABLE, TAB_COMPLETED]
const TAB_LABELS := {TAB_IN_PROGRESS: "In Progress", TAB_AVAILABLE: "Available", TAB_COMPLETED: "Completed"}

var current_tab: String = TAB_IN_PROGRESS
var selected_quest: String = ""
var tab_buttons: Dictionary = {}
var list_box: VBoxContainer
var detail_box: VBoxContainer
## The summaries listed in the current tab (QuestEngine.quest_summary rows, plus "nearby" for available ones).
var entries: Array = []
var _tab_group := ButtonGroup.new()
var _list_group := ButtonGroup.new()


func _init() -> void:
	super._init("quests", "Quest Log", "toggle_quests", Vector2(LIST_WIDTH + 360, 0))


func _build() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	tabs.mouse_filter = MOUSE_FILTER_IGNORE
	for t in TABS:
		var b := MisoWindow.make_button(TAB_LABELS[t], &"MisoTabButton")
		b.toggle_mode = true
		b.button_group = _tab_group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = t == current_tab
		b.pressed.connect(select_tab.bind(t))
		tabs.add_child(b)
		tab_buttons[t] = b
	body.add_child(tabs)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 6)
	split.mouse_filter = MOUSE_FILTER_IGNORE
	split.custom_minimum_size = Vector2(0, 340)
	body.add_child(split)

	var list_inset := PanelContainer.new()
	list_inset.theme_type_variation = &"MisoInset"
	list_inset.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	list_inset.mouse_filter = MOUSE_FILTER_IGNORE
	split.add_child(list_inset)
	var list_scroll := ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_inset.add_child(list_scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 2)
	list_scroll.add_child(list_box)

	var detail_inset := PanelContainer.new()
	detail_inset.theme_type_variation = &"MisoInset"
	detail_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_inset.mouse_filter = MOUSE_FILTER_IGNORE
	split.add_child(detail_inset)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_inset.add_child(detail_scroll)
	detail_box = VBoxContainer.new()
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_box.add_theme_constant_override("separation", 4)
	detail_scroll.add_child(detail_box)


func refresh() -> void:
	ensure_built()
	entries = _entries_for(current_tab)
	var counts := {}
	var engine := env.quest_engine() if env != null else null
	if engine != null:
		counts[TAB_IN_PROGRESS] = engine.active_quests().size()
		counts[TAB_COMPLETED] = engine.completed_quests().size()
		counts[TAB_AVAILABLE] = _available_ids(engine).size()
	for t in TABS:
		var b: Button = tab_buttons[t]
		b.text = "%s (%d)" % [TAB_LABELS[t], int(counts.get(t, 0))]
		b.button_pressed = t == current_tab
	var ids: PackedStringArray = []
	for e: Dictionary in entries:
		ids.append(String(e["quest_id"]))
	if not (selected_quest in ids):
		selected_quest = ids[0] if not ids.is_empty() else ""
	_fill_list()
	_fill_detail()


func select_tab(tab: String) -> void:
	if not (tab in TABS):
		return
	if tab != current_tab:
		selected_quest = ""
	current_tab = tab
	refresh()


func select_quest(quest_id: String) -> void:
	selected_quest = quest_id
	for b in list_box.get_children():
		if b is Button:
			(b as Button).button_pressed = String(b.get_meta("quest_id", "")) == quest_id
	_fill_detail()


## The texts of the detail pane, top to bottom (title, status, journal, objective rows, rewards). For tests.
func detail_texts() -> PackedStringArray:
	var out: PackedStringArray = []
	_collect_texts(detail_box, out)
	return out


## The objective rows of the selected quest as shown ([{text, done}]). For tests.
func objective_rows() -> Array:
	var out: Array = []
	for ch in detail_box.get_children():
		if ch.has_meta("objective"):
			out.append({"text": String(ch.get_meta("objective")), "done": bool(ch.get_meta("done"))})
	return out


func _entries_for(tab: String) -> Array:
	var engine := env.quest_engine() if env != null else null
	if engine == null:
		return []
	match tab:
		TAB_IN_PROGRESS:
			return engine.quest_summaries(PackedStringArray([QuestLog.IN_PROGRESS]))
		TAB_COMPLETED:
			return engine.quest_summaries(PackedStringArray([QuestLog.COMPLETED]))
		TAB_AVAILABLE:
			var here := env.current_map_id()
			var db := env.get_db()
			var near: Array = []
			var far: Array = []
			for qid in _available_ids(engine):
				var s := engine.quest_summary(qid)
				var npc: Dictionary = db.npc(String(s.get("start_npc_id", ""))) if db != null else {}
				s["nearby"] = npc_is_on_map(npc, here)
				s["start_npc_name"] = String(npc.get("name", ""))
				(near if s["nearby"] else far).append(s)
			return near + far
	return []


## True when a canonical NPC record stands on `map_id`. MeowDB places NPCs through locations[].map_id (the record has
## no top-level map_id); any of its locations counts.
static func npc_is_on_map(npc: Dictionary, map_id: String) -> bool:
	if map_id == "":
		return false
	var locs: Variant = npc.get("locations", [])
	if not (locs is Array):
		return false
	for loc: Variant in locs:
		if loc is Dictionary and String((loc as Dictionary).get("map_id", "")) == map_id:
			return true
	return false


func _available_ids(engine: QuestEngine) -> PackedStringArray:
	var out: PackedStringArray = []
	for qid in engine.catalog.ids():
		if engine.status(qid) == QuestLog.NOT_STARTED and engine.is_available(qid):
			out.append(qid)
	return out


func _fill_list() -> void:
	for ch in list_box.get_children():
		list_box.remove_child(ch)
		ch.queue_free()
	if entries.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"MisoDim"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(LIST_WIDTH - 20, 0)
		match current_tab:
			TAB_IN_PROGRESS:
				empty.text = "No quests in progress. Talk to the people of Maple Island to find one."
			TAB_AVAILABLE:
				empty.text = "No quests are available right now."
			_:
				empty.text = "No quests completed yet."
		list_box.add_child(empty)
		return
	for e: Dictionary in entries:
		var qid := String(e["quest_id"])
		var b := MisoWindow.make_button("", &"MisoFlatButton")
		b.toggle_mode = true
		b.button_group = _list_group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size = Vector2(LIST_WIDTH - 18, 0)
		# The tag leads the row, so a long name is the part the ellipsis trims (a trailing tag was clipped away:
		# "Borrowing Sera's Mirror ..." hid its [ready]).
		var mark := ""
		if current_tab == TAB_IN_PROGRESS and bool(e.get("can_complete", false)):
			mark = "[ready] "
		elif current_tab == TAB_AVAILABLE and bool(e.get("nearby", false)):
			mark = "[nearby] "
		b.text = mark + String(e.get("name", qid))
		var chain := chain_text(e.get("chain", {}))
		b.tooltip_text = String(e.get("name", qid)) + ("\n" + chain if chain != "" else "")
		b.set_meta("quest_id", qid)
		b.button_pressed = qid == selected_quest
		if mark != "":
			b.add_theme_color_override("font_color", MisoTheme.GOLD)
		b.pressed.connect(select_quest.bind(qid))
		list_box.add_child(b)


func _fill_detail() -> void:
	for ch in detail_box.get_children():
		detail_box.remove_child(ch)
		ch.queue_free()
	var engine := env.quest_engine() if env != null else null
	if engine == null or selected_quest == "":
		var hint := _label("Select a quest to see its details.", &"MisoDim")
		detail_box.add_child(hint)
		return
	var s := engine.quest_summary(selected_quest)
	if s.is_empty():
		return
	var db := env.get_db()
	var start_npc: Dictionary = db.npc(String(s.get("start_npc_id", ""))) if db != null else {}
	# "Available nearby" (read by _status_text for a quest not started yet), as in the list.
	s["nearby"] = npc_is_on_map(start_npc, env.current_map_id())
	if String(s.get("start_npc_name", "")) == "":
		s["start_npc_name"] = String(start_npc.get("name", ""))
	detail_box.add_child(_label(String(s.get("name", selected_quest)), &"MisoTitle"))
	var status_text := _status_text(s)
	if bool(s.get("missable", false)):
		# MeowDB's own tag on the live quest tracker; MisoStory does not interpret it.
		status_text += "  ·  Missable"
	var status_l := _label(status_text, &"MisoDim")
	if String(s.get("status", "")) == QuestLog.IN_PROGRESS and bool(s.get("can_complete", false)):
		status_l.add_theme_color_override("font_color", MisoTheme.GOLD)
	detail_box.add_child(status_l)
	var who := npc_line(s)
	if who != "":
		detail_box.add_child(_label(who, &"MisoSmall"))
	var chain: Dictionary = s.get("chain", {})
	if not chain.is_empty():
		_add_chain_rows(chain)
	var journal := String(s.get("journal", "")).strip_edges()
	if journal != "":
		detail_box.add_child(_label(journal, &"MisoSmall"))

	var objectives: Array = s.get("objectives", [])
	if not objectives.is_empty():
		detail_box.add_child(HSeparator.new())
		detail_box.add_child(_label("Objectives", &"MisoHeading"))
		var completed := String(s.get("status", "")) == QuestLog.COMPLETED
		for row: Dictionary in objectives:
			var done := completed or bool(row.get("done", false))
			var text := MisoUiText.objective_text(row)
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 6)
			line.set_meta("objective", text)
			line.set_meta("done", done)
			var box := TextureRect.new()
			box.texture = MisoTheme.check_texture(done)
			box.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			box.custom_minimum_size = Vector2(18, 20)
			line.add_child(box)
			var tl := _label(text, &"MisoSmall", 270.0)
			if done:
				tl.add_theme_color_override("font_color", MisoTheme.GOOD)
			line.add_child(tl)
			detail_box.add_child(line)

	var rewards := _reward_rows(engine.definition(selected_quest), db)
	if not rewards.is_empty():
		detail_box.add_child(HSeparator.new())
		detail_box.add_child(_label("Rewards", &"MisoHeading"))
		for r: Control in rewards:
			detail_box.add_child(r)
	var received := received_line(s, db)
	if received != "":
		detail_box.add_child(_label(received, &"MisoGood"))


## "From Sam (Snail Hunting Ground I)  ·  turn in to Mai (A Split Road)", or "From Roger (Mushroom Town)" when the
## same NPC starts and ends the quest. NPC and map names are canonical (quest start_maps / end_maps).
static func npc_line(s: Dictionary) -> String:
	var start_name := String(s.get("start_npc_name", ""))
	var end_name := String(s.get("end_npc_name", ""))
	var parts: PackedStringArray = []
	if start_name != "":
		parts.append("From %s%s" % [start_name, _where(String(s.get("start_map_name", "")))])
	if end_name != "" and String(s.get("end_npc_id", "")) != String(s.get("start_npc_id", "")):
		parts.append("turn in to %s%s" % [end_name, _where(String(s.get("end_map_name", "")))])
	return "  ·  ".join(parts)


## The chain line ("Mai's Training 2/3") for a summary's chain (QuestEngine.chain_info), "" for a standalone quest.
static func chain_text(chain: Dictionary) -> String:
	if chain.is_empty():
		return ""
	return "%s %d/%d" % [String(chain.get("name", "")), int(chain.get("position", 0)), int(chain.get("total", 0))]


## "Received: Green Headband" for a completed quest whose random reward was recorded (QuestLog rewards_received);
## "" otherwise (no random reward, or a completion saved before rewards were recorded).
static func received_line(s: Dictionary, db: ContentDB) -> String:
	if String(s.get("status", "")) != QuestLog.COMPLETED or not bool(s.get("rewards_recorded", false)):
		return ""
	var names: PackedStringArray = []
	for p: Variant in (s.get("rewards_received", {}) as Dictionary).get("random_picks", []):
		var pd: Dictionary = p
		var item_id := String(pd.get("item_id", ""))
		var nm := String(db.item(item_id).get("name", item_id)) if db != null else item_id
		var qty := int(pd.get("qty", 1))
		names.append(nm + (" x%d" % qty if qty > 1 else ""))
	return "" if names.is_empty() else "Received: %s" % ", ".join(names)


static func _where(map_name: String) -> String:
	return " (%s)" % map_name if map_name != "" else ""


## The chain heading and one row per step, ticked when completed; the selected quest's step is highlighted.
func _add_chain_rows(chain: Dictionary) -> void:
	var head := _label(chain_text(chain), &"MisoGold")
	head.set_meta("chain", true)
	detail_box.add_child(head)
	for st: Variant in chain.get("steps", []):
		var sd: Dictionary = st
		var done := String(sd.get("status", "")) == QuestLog.COMPLETED
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var box := TextureRect.new()
		box.texture = MisoTheme.check_texture(done)
		box.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		box.custom_minimum_size = Vector2(18, 18)
		line.add_child(box)
		var tl := _label(String(sd.get("name", "")), &"MisoSmall", 270.0)
		if String(sd.get("quest_id", "")) == selected_quest:
			tl.add_theme_color_override("font_color", MisoTheme.GOLD)
		elif done:
			tl.add_theme_color_override("font_color", MisoTheme.GOOD)
		line.add_child(tl)
		line.set_meta("chain_step", String(sd.get("quest_id", "")))
		detail_box.add_child(line)


func _status_text(s: Dictionary) -> String:
	match String(s.get("status", "")):
		QuestLog.IN_PROGRESS:
			return "Ready to turn in" if bool(s.get("can_complete", false)) else "In progress"
		QuestLog.COMPLETED:
			return "Completed"
	return "Available" + (" nearby" if bool(s.get("nearby", false)) else "")


func _reward_rows(d: QuestDef, db: ContentDB) -> Array:
	var out: Array = []
	if d == null:
		return out
	if d.reward_exp > 0:
		out.append(_label("EXP  +%s" % MisoTheme.thousands(d.reward_exp), &"MisoGood"))
	if d.reward_mesos > 0:
		var row := HBoxContainer.new()
		row.add_child(MisoCoinIcon.new(14))
		row.add_child(_label("%s mesos" % MisoTheme.thousands(d.reward_mesos), &"MisoGold", 0.0))
		out.append(row)
	if d.reward_fame != 0:
		out.append(_label("Fame  %+d" % d.reward_fame, &"MisoGood"))
	for it: Dictionary in d.reward_items:
		out.append(_item_row(String(it.get("item_id", "")), int(it.get("count", 1)), db))
	for group: Dictionary in d.reward_random:
		var label := "One of these at random"
		if String(group.get("job_name", "")) not in QuestDef.ANY_CLASS_LABELS:
			label += " (%s)" % String(group["job_name"])
		out.append(_label(label + ":", &"MisoDim"))
		for it: Dictionary in group.get("items", []):
			out.append(_item_row(String(it.get("item_id", "")), int(it.get("count", 1)), db))
	for group: Dictionary in d.reward_selection:
		var label := "Choose one"
		if String(group.get("job_name", "")) not in QuestDef.ANY_CLASS_LABELS:
			label += " (%s)" % String(group["job_name"])
		out.append(_label(label + ":", &"MisoDim"))
		for it: Dictionary in group.get("items", []):
			out.append(_item_row(String(it.get("item_id", "")), int(it.get("count", 1)), db))
	return out


func _item_row(item_id: String, count: int, db: ContentDB) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon := MisoItemIcon.new()
	icon.custom_minimum_size = Vector2(26, 26)
	icon.set_item(item_id, db)
	row.add_child(icon)
	var nm := String(db.item(item_id).get("name", item_id)) if db != null else item_id
	row.add_child(_label("%s%s" % [nm, " x%d" % count if count > 1 else ""], &"MisoSmall", 0.0))
	return row


func _label(text: String, variation: StringName, width: float = 300.0) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(width, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _collect_texts(n: Node, out: PackedStringArray) -> void:
	for ch in n.get_children():
		if ch is Label:
			out.append((ch as Label).text)
		_collect_texts(ch, out)
