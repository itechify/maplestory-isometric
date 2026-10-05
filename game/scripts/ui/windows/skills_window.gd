class_name MisoSkillsWindow
extends MisoWindow
## The Skills window (toggle_skills, K): the character's skills (SkillDef.catalog: the canonical Beginner skills
## Three Snails, Recovery and Nimble Feet) with their icon, name, level / max level and the current level's MeowDB
## effect line; the unspent SP; a "+" per skill while SP is left and the skill is below its max level (SkillBook.learn:
## one SP per level, no refunds); the selected skill's description with its current and next level; and two ways to
## put a learned skill on a quickslot: drag its icon onto a HUD quickslot, or select it, press "Set key" and pick a
## key 1-8 (MisoQuickslots.bind_skill).
##
## Spending SP announces Events.skill_leveled(skill_id, level) and Events.stats_changed (the HUD's SP badge and the
## stat window follow) and asks for an autosave.

## The size of a "+" button and of a skill icon.
const PLUS_SIZE := Vector2(34, 26)
const ICON_SIZE := 40.0
const ROW_WIDTH := 330.0


## A skill's icon in its row: a drag source for learned skills ({"kind": SKILL_DRAG_KIND, "source": "skills",
## "skill_id"}), which a HUD quickslot accepts.
class SkillIconCell extends PanelContainer:
	var skill_id: String = ""
	var icon: MisoSkillIcon
	## () -> bool: whether the skill is learned (only learned skills drag).
	var learned: Callable = Callable()

	func _init(p_skill_id: String) -> void:
		skill_id = p_skill_id
		theme_type_variation = &"MisoSlot"
		custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		mouse_filter = MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		icon = MisoSkillIcon.new()
		icon.skill_id = p_skill_id
		add_child(icon)

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if learned.is_valid() and not bool(learned.call()):
			return null
		var preview := MisoSkillIcon.new()
		preview.size = Vector2(36, 36)
		preview.position = Vector2(-18, -18)
		preview.skill_id = skill_id
		var holder := Control.new()
		holder.add_child(preview)
		set_drag_preview(holder)
		return {"kind": MisoQuickslots.SKILL_DRAG_KIND, "source": "skills", "skill_id": skill_id}


## skill id -> the row's parts: {"panel", "icon", "name", "level", "effect", "plus"}.
var rows: Dictionary = {}
## skill id -> "+" Button.
var plus_buttons: Dictionary = {}
## quickslot key -> its Button in the key picker.
var key_buttons: Dictionary = {}
var sp_label: Label
var job_label: Label
var detail_label: Label
var key_button: Button
var key_picker: HBoxContainer
var rows_box: VBoxContainer
## The skill the description and "Set key" act on ("" = none).
var selected: String = ""


func _init() -> void:
	super._init("skills", "Skills", "toggle_skills", Vector2(360, 0))


func _build() -> void:
	var head := HBoxContainer.new()
	head.mouse_filter = MOUSE_FILTER_IGNORE
	job_label = Label.new()
	job_label.theme_type_variation = &"MisoHeading"
	job_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(job_label)
	var sp_title := Label.new()
	sp_title.text = "Skill Points"
	sp_title.theme_type_variation = &"MisoDim"
	head.add_child(sp_title)
	var sp_box := PanelContainer.new()
	sp_box.theme_type_variation = &"MisoSlot"
	sp_box.custom_minimum_size = Vector2(54, 0)
	sp_label = MisoTheme.make_label("0", 16, MisoTheme.GOLD, 3, MisoTheme.WEIGHT_BLACK)
	sp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sp_box.add_child(sp_label)
	head.add_child(sp_box)
	body.add_child(head)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 6)
	rows_box.mouse_filter = MOUSE_FILTER_IGNORE
	body.add_child(rows_box)
	_build_rows()
	var detail := PanelContainer.new()
	detail.theme_type_variation = &"MisoInset"
	detail.mouse_filter = MOUSE_FILTER_IGNORE
	detail_label = Label.new()
	detail_label.theme_type_variation = &"MisoSmall"
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size = Vector2(ROW_WIDTH, 0)
	detail.add_child(detail_label)
	body.add_child(detail)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	actions.mouse_filter = MOUSE_FILTER_IGNORE
	key_button = MisoWindow.make_button("Set key")
	key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_button.tooltip_text = "Bind the selected skill to a quickslot key"
	key_button.pressed.connect(func() -> void: key_picker.visible = not key_picker.visible)
	actions.add_child(key_button)
	body.add_child(actions)
	key_picker = HBoxContainer.new()
	key_picker.add_theme_constant_override("separation", 3)
	key_picker.visible = false
	for key in MisoQuickslots.keys():
		var kb := MisoWindow.make_button(MisoQuickslots.key_text(key))
		kb.custom_minimum_size = Vector2(28, 26)
		kb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kb.pressed.connect(func() -> void: assign_quickslot(key))
		key_picker.add_child(kb)
		key_buttons[key] = kb
	body.add_child(key_picker)
	add_status_line("Spend SP with \"+\"; drag a learned skill to a quickslot.")


## One row per skill the character's job can learn (built once content is available).
func _build_rows() -> void:
	var db := env.get_db() if env != null else null
	if db == null or not rows.is_empty():
		return
	var c := env.character()
	for def in SkillDef.catalog(c.job if c != null else SkillDef.BASE_CLASS, db):
		_add_row(def)


func _add_row(def: SkillDef) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"MisoInset"
	panel.mouse_filter = MOUSE_FILTER_STOP
	panel.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			select_skill(def.id))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var icon := SkillIconCell.new(def.id)
	icon.learned = func() -> bool: return SkillBook.level_of(env.character() if env != null else null, def.id) > 0
	icon.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			select_skill(def.id))
	row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.mouse_filter = MOUSE_FILTER_IGNORE
	var name_l := Label.new()
	name_l.text = def.name
	name_l.theme_type_variation = &"MisoHeading"
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	var lv := Label.new()
	lv.theme_type_variation = &"MisoDim"
	top.add_child(lv)
	texts.add_child(top)
	var effect := Label.new()
	effect.theme_type_variation = &"MisoSmall"
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.custom_minimum_size = Vector2(ROW_WIDTH - ICON_SIZE - PLUS_SIZE.x - 24.0, 0)
	texts.add_child(effect)
	row.add_child(texts)
	var plus := MisoWindow.make_button("+", &"MisoAccentButton")
	plus.custom_minimum_size = PLUS_SIZE
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plus.add_theme_font_size_override("font_size", 19)
	plus.add_theme_font_override("font", MisoTheme.black_font())
	plus.tooltip_text = "Spend 1 SP on %s" % def.name
	plus.pressed.connect(add_point.bind(def.id))
	row.add_child(MisoStatsWindow.PlusCell.new(plus))
	rows_box.add_child(panel)
	rows[def.id] = {"panel": panel, "icon": icon, "name": name_l, "level": lv, "effect": effect, "plus": plus}
	plus_buttons[def.id] = plus


func refresh() -> void:
	ensure_built()
	var c := env.character() if env != null else null
	var db := env.get_db() if env != null else null
	_build_rows()
	if c == null or db == null:
		sp_label.text = "-"
		job_label.text = ""
		for sid in rows:
			(plus_buttons[sid] as Button).visible = false
		detail_label.text = ""
		_update_actions()
		return
	job_label.text = env.job_name(c)
	sp_label.text = str(c.sp)
	sp_label.add_theme_color_override("font_color", MisoTheme.GOLD if c.sp > 0 else MisoTheme.TEXT_DIM)
	for sid: String in rows:
		var def := SkillDef.of(sid, db)
		var level := SkillBook.level_of(c, sid)
		var r: Dictionary = rows[sid]
		(r["level"] as Label).text = "Lv. %d / %d" % [level, def.max_level]
		(r["effect"] as Label).text = def.effect_text(level) if level > 0 else "Not learned yet."
		((r["icon"] as SkillIconCell).icon as MisoSkillIcon).dim = level <= 0
		(plus_buttons[sid] as Button).visible = bool(SkillBook.can_learn(c, sid, db).ok)
		var panel: PanelContainer = r["panel"]
		if sid == selected:
			panel.add_theme_stylebox_override("panel", MisoTheme.panel_style("slot_selected"))
		else:
			panel.remove_theme_stylebox_override("panel")
	_show_detail(c, db)
	_update_actions()


## Spends one SP on a skill (SkillBook.learn) and announces it. Returns false when refused (no SP, max level).
func add_point(skill_id: String) -> bool:
	var c := env.character() if env != null else null
	var db := env.get_db() if env != null else null
	if c == null or db == null:
		return false
	var res := SkillBook.learn(c, skill_id, db)
	var def := SkillDef.of(skill_id, db)
	if res.ok:
		env.emit("skill_leveled", [skill_id, int(res.level)])
		env.emit("stats_changed")
		env.request_autosave("skill")
		MisoQuickslots.notify()
		set_status("%s is now level %d." % [def.name, int(res.level)])
		selected = skill_id
	else:
		match String(res.code):
			SkillBook.NO_SP:
				set_status("You have no SP to spend.", true)
			SkillBook.MAX_LEVEL:
				set_status("%s is at its max level." % (def.name if def != null else skill_id), true)
			_:
				set_status("You cannot learn that skill.", true)
	refresh()
	return bool(res.ok)


## Selects the skill the description and "Set key" act on.
func select_skill(skill_id: String) -> void:
	selected = skill_id if rows.has(skill_id) else ""
	if selected == "":
		key_picker.visible = false
	refresh()


## Binds the selected (or given) skill to a quickslot key ("1".."8"). Returns false when it is not learned.
func assign_quickslot(key: String, skill_id: String = "") -> bool:
	var sid := skill_id if skill_id != "" else selected
	key_picker.visible = false
	if env == null or sid == "":
		return false
	var def := SkillDef.of(sid, env.get_db())
	var ok := MisoQuickslots.bind_skill(env, key, sid)
	if ok:
		set_status("%s set to key %s." % [def.name, MisoQuickslots.key_text(key)])
	else:
		set_status("Learn %s before setting it to a key." % (def.name if def != null else sid), true)
	return ok


## The "Lv. x / max" text of a skill's row, for tests and tools.
func level_text(skill_id: String) -> String:
	return (rows[skill_id]["level"] as Label).text if rows.has(skill_id) else ""


func _show_detail(c: CharacterState, db: ContentDB) -> void:
	if selected == "":
		detail_label.text = "Select a skill to read it."
		return
	var def := SkillDef.of(selected, db)
	var level := SkillBook.level_of(c, selected)
	var lines: PackedStringArray = ["%s  (%s)" % [def.name, def.cast_position], def.description]
	lines.append("Now: %s" % (def.effect_text(level) if level > 0 else "not learned"))
	if level < def.max_level:
		lines.append("Next (Lv. %d): %s" % [level + 1, def.effect_text(level + 1)])
	else:
		lines.append("Max level.")
	detail_label.text = "\n".join(lines)


func _update_actions() -> void:
	var c := env.character() if env != null else null
	key_button.disabled = selected == "" or SkillBook.level_of(c, selected) <= 0
	if key_button.disabled:
		key_picker.visible = false
