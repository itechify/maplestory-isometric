class_name CreationScreen
extends Control
## Character creation: name (CharacterFactory's rules), gender, one of the creation weapons with its canonical W.ATK
## and attack speed, and the creation AP spread over the allocatable stats on top of the starting stats, with a live
## preview (StatCalculator.compute through CreationModel: HP/MP, ACC, EVA, W.ATK, damage range). Start is enabled
## only when CreationModel.errors() is empty. All rules live in CreationModel; this is only its view.

signal start_pressed(params: Dictionary)
signal back_pressed

const STAT_LABELS := {"str": "STR", "dex": "DEX", "int": "INT", "luk": "LUK"}
const GENDER_LABELS := {"male": "Male", "female": "Female"}

var model: CreationModel = null
var name_edit: LineEdit = null
var name_hint: Label = null
var start_button: Button = null
var back_button: Button = null
var errors_label: Label = null
var ap_label: Label = null
var slot_label: Label = null

var _gender_buttons: Dictionary = {}
var _weapon_buttons: Dictionary = {}
var _stat_values: Dictionary = {}
var _stat_plus: Dictionary = {}
var _stat_minus: Dictionary = {}
var _preview_labels: Dictionary = {}


func _init(p_model: CreationModel = null) -> void:
	name = "CreationScreen"
	model = p_model
	ScreenKit.full_rect(self)
	ScreenKit.apply(self)
	var bg := TitleBackdrop.new()
	ScreenKit.full_rect(bg)
	add_child(bg)
	add_child(ScreenKit.dim(Color(0.02, 0.05, 0.12, 0.35)))


func _ready() -> void:
	if model == null:
		model = CreationModel.new(_db())
	_build()
	refresh()


## Sets the slot the new game will be saved into (shown under the title).
func set_target_slot(slot: String) -> void:
	if slot_label != null:
		slot_label.text = "Saves to %s" % slot if slot != "" else ""


## Re-reads the model into every control.
func refresh() -> void:
	if model == null or name_edit == null:
		return
	if name_edit.text != model.name:
		name_edit.text = model.name
	for g in _gender_buttons:
		(_gender_buttons[g] as Button).button_pressed = model.gender == g
	for w in _weapon_buttons:
		(_weapon_buttons[w] as Button).button_pressed = model.weapon_id == w
	for k in _stat_values:
		(_stat_values[k] as Label).text = str(model.stat_total(k))
		(_stat_plus[k] as Button).disabled = not model.can_add(k)
		(_stat_minus[k] as Button).disabled = not model.can_remove(k)
	ap_label.text = "AP to place: %d" % model.ap_remaining()
	ap_label.add_theme_color_override("font_color", ScreenKit.GOLD if model.ap_remaining() > 0 else ScreenKit.GOOD)
	var p := model.preview()
	_set_preview("hp", "%d / %d" % [int(p.get("max_hp", 0)), int(p.get("max_mp", 0))])
	_set_preview("watk", str(int(p.get("watk", 0))))
	_set_preview("acc", str(int(p.get("acc", 0))))
	_set_preview("avoid", str(int(p.get("avoid", 0))))
	_set_preview("damage", "%d ~ %d" % [int(p.get("damage_min", 0)), int(p.get("damage_max", 0))])
	var name_problems := model.name_errors() if model.name != "" else PackedStringArray()
	name_hint.text = name_problems[0] if not name_problems.is_empty() else _name_rule_text()
	name_hint.add_theme_color_override("font_color", ScreenKit.BAD if not name_problems.is_empty() else ScreenKit.TEXT_DIM)
	var errs := model.errors()
	start_button.disabled = not errs.is_empty()
	errors_label.text = "" if errs.is_empty() else _friendly(errs)


## Presses Start (returns false when the model is not valid). Used by the button and by the checks.
func submit() -> bool:
	if model == null or not model.is_valid():
		refresh()
		return false
	start_pressed.emit(model.params())
	return true


func focus_default() -> void:
	if name_edit != null:
		name_edit.grab_focus()


# --- building -------------------------------------------------------------------------------------------------

func _build() -> void:
	var panel := ScreenKit.window_panel()
	panel.custom_minimum_size = Vector2(1040, 0)
	add_child(ScreenKit.centered(panel))
	var root := ScreenKit.vbox(14)
	panel.add_child(ScreenKit.margin(root, 8))
	var head := ScreenKit.hbox(16)
	root.add_child(head)
	var t := ScreenKit.title("Create your character", 24)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	slot_label = ScreenKit.label("", 13, ScreenKit.TEXT_DIM, "MisoDim")
	head.add_child(slot_label)

	var cols := ScreenKit.hbox(18)
	root.add_child(cols)
	var left := ScreenKit.vbox(12)
	left.custom_minimum_size = Vector2(500, 0)
	cols.add_child(left)
	var right := ScreenKit.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	# Name.
	left.add_child(ScreenKit.label("Name", 16, Color(0, 0, 0, 0), "MisoHeading"))
	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.placeholder_text = "Your name"
	name_edit.custom_minimum_size = Vector2(0, 36)
	name_edit.max_length = 32
	name_edit.text_changed.connect(func(text: String) -> void:
		model.name = text
		refresh())
	name_edit.text_submitted.connect(func(_text: String) -> void: submit())
	left.add_child(name_edit)
	name_hint = ScreenKit.label("", 13, ScreenKit.TEXT_DIM, "MisoDim")
	left.add_child(name_hint)

	# Gender.
	left.add_child(ScreenKit.label("Gender", 16, Color(0, 0, 0, 0), "MisoHeading"))
	var genders := ScreenKit.hbox(8)
	var group := ButtonGroup.new()
	for g in GameState.GENDERS:
		var b := ScreenKit.button(String(GENDER_LABELS.get(g, g.capitalize())), false, 120)
		b.toggle_mode = true
		b.button_group = group
		if ScreenKit.has_miso_theme():
			b.theme_type_variation = "MisoTabButton"
		b.pressed.connect(func() -> void:
			model.gender = g
			refresh())
		genders.add_child(b)
		_gender_buttons[g] = b
	left.add_child(genders)

	# Starter weapon.
	left.add_child(ScreenKit.label("Starter weapon", 16, Color(0, 0, 0, 0), "MisoHeading"))
	var weapons := ScreenKit.hbox(8)
	var wgroup := ButtonGroup.new()
	for w in model.weapons():
		var id := String(w["id"])
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = wgroup
		b.custom_minimum_size = Vector2(160, 76)
		b.text = "%s\n%s\nW.ATK %d · %s (%d)" % [w["name"], w["subtype"], int(w["watk"]), w["speed_name"], int(w["speed"])]
		b.name = "Weapon_%s" % id
		if ScreenKit.has_miso_theme():
			b.theme_type_variation = "MisoTabButton"
		b.pressed.connect(func() -> void:
			model.weapon_id = id
			refresh())
		weapons.add_child(b)
		_weapon_buttons[id] = b
	left.add_child(weapons)
	left.add_child(ScreenKit.label("Canonical item stats (MeowDB). Speed: the weapon's attack speed tier.", 12,
		ScreenKit.TEXT_DIM, "MisoSmall"))

	# Stats.
	var stats_head := ScreenKit.hbox(8)
	var st := ScreenKit.label("Ability points", 16, Color(0, 0, 0, 0), "MisoHeading")
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_head.add_child(st)
	ap_label = ScreenKit.label("", 15, ScreenKit.GOLD, "MisoGold")
	stats_head.add_child(ap_label)
	right.add_child(stats_head)
	var stats_panel := ScreenKit.inset_panel()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	stats_panel.add_child(grid)
	for k in model.stat_keys():
		var key := k
		var l := ScreenKit.label(String(STAT_LABELS.get(k, k.to_upper())), 16)
		l.custom_minimum_size = Vector2(70, 0)
		grid.add_child(l)
		var minus := ScreenKit.button("-", false, 40)
		minus.name = "Minus_%s" % k
		minus.pressed.connect(func() -> void:
			model.remove_ap(key)
			refresh())
		grid.add_child(minus)
		var val := ScreenKit.label("0", 18, ScreenKit.TEXT, "MisoHeading")
		val.custom_minimum_size = Vector2(60, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(val)
		var plus := ScreenKit.button("+", false, 40)
		plus.name = "Plus_%s" % k
		plus.pressed.connect(func() -> void:
			model.add_ap(key)
			refresh())
		grid.add_child(plus)
		_stat_values[k] = val
		_stat_plus[k] = plus
		_stat_minus[k] = minus
	right.add_child(stats_panel)
	var stat_buttons := ScreenKit.hbox(8)
	var reset := ScreenKit.button("Clear", false, 110)
	reset.pressed.connect(func() -> void:
		model.clear_ap()
		refresh())
	stat_buttons.add_child(reset)
	var rec := ScreenKit.button("Recommended", false, 150)
	rec.tooltip_text = "The Beginner's guide spread (new_character.json quick_start)"
	rec.pressed.connect(func() -> void:
		model.use_defaults()
		refresh())
	stat_buttons.add_child(rec)
	right.add_child(stat_buttons)
	right.add_child(ScreenKit.label("Every stat starts at %d. Place all %d creation AP." % [
		model.starting_stat(model.stat_keys()[0]) if not model.stat_keys().is_empty() else 0, model.creation_ap()],
		12, ScreenKit.TEXT_DIM, "MisoSmall"))

	# Preview.
	right.add_child(ScreenKit.label("Preview (level 1)", 16, Color(0, 0, 0, 0), "MisoHeading"))
	var prev_panel := ScreenKit.inset_panel()
	var pgrid := GridContainer.new()
	pgrid.columns = 2
	pgrid.add_theme_constant_override("h_separation", 24)
	prev_panel.add_child(pgrid)
	for row in [["hp", "HP / MP"], ["watk", "W.ATK"], ["acc", "Accuracy"], ["avoid", "Avoidability"], ["damage", "Damage"]]:
		pgrid.add_child(ScreenKit.label(String(row[1]), 15, ScreenKit.TEXT_DIM, "MisoDim"))
		var v := ScreenKit.label("", 16, ScreenKit.TEXT, "MisoHeading")
		pgrid.add_child(v)
		_preview_labels[row[0]] = v
	right.add_child(prev_panel)

	# Footer.
	errors_label = ScreenKit.label("", 13, ScreenKit.BAD, "MisoBad")
	errors_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(errors_label)
	var foot := ScreenKit.hbox(10)
	foot.alignment = BoxContainer.ALIGNMENT_END
	back_button = ScreenKit.button("Back", false, 130)
	back_button.name = "Back"
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	start_button = ScreenKit.button("Start", true, 160)
	start_button.name = "Start"
	start_button.pressed.connect(submit)
	foot.add_child(back_button)
	foot.add_child(start_button)
	root.add_child(foot)


func _set_preview(key: String, text: String) -> void:
	var l: Label = _preview_labels.get(key, null)
	if l != null:
		l.text = text


func _name_rule_text() -> String:
	var rules: Dictionary = CharacterFactory.rules_table(model.db).get("name_rules", {}) if model.db != null else {}
	return "%d to %d letters or digits" % [int(rules.get("min_length", 0)), int(rules.get("max_length", 0))]


## The first validation problem, phrased for the player.
func _friendly(errs: PackedStringArray) -> String:
	if model.name == "":
		return "Enter a name."
	if model.ap_remaining() > 0:
		return "Place the remaining %d AP." % model.ap_remaining()
	return errs[0]


static func _db() -> ContentDB:
	var data := (Engine.get_main_loop() as SceneTree).root.get_node_or_null(^"Data") if Engine.get_main_loop() else null
	return data.get("db") as ContentDB if data != null else null
