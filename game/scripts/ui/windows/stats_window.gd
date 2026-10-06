class_name MisoStatsWindow
extends MisoWindow
## The Character Stats window (toggle_stats, C): name, job, level, EXP (current / needed and percent), HP, MP and
## fame; STR / DEX / INT / LUK as total (base + bonus) with a "+" button per stat while AP is available (spent
## through Game.allocate_ap, which announces the change); and the derived numbers of StatCalculator.snapshot: the
## damage range, ACC, AVOID, W.DEF, M.DEF, Magic, Speed and Jump. Which stats take AP comes from canonical
## formulas/beginner.json ap.allocatable_stats. The unspent Skill Points (CharacterState.sp, granted by Progression)
## are shown under the AP; they are spent in the Skills window (toggle_skills, K). Each "+" sits in a PlusCell that keeps its size while the button is
## hidden, so STR / DEX / INT / LUK keep one row each at any AP (a GridContainer skips hidden children).

## The size of a "+" button (and of the cell that holds it).
const PLUS_SIZE := Vector2(34, 26)


## A grid cell holding one "+" button. Its minimum size is the button's whether or not the button is shown, so hiding
## the button at 0 AP leaves the 3-column grid (name, value, "+") in place instead of reflowing the next row's cells
## into this one.
class PlusCell extends Container:
	var button: Button

	func _init(b: Button) -> void:
		button = b
		mouse_filter = MOUSE_FILTER_IGNORE
		add_child(b)

	func _get_minimum_size() -> Vector2:
		return button.get_combined_minimum_size()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			fit_child_in_rect(button, Rect2(Vector2.ZERO, size))


## value key -> Label
var values: Dictionary = {}
## stat -> "+" Button
var plus_buttons: Dictionary = {}
var ap_label: Label
var ap_box: PanelContainer
var sp_label: Label
var sp_box: PanelContainer


func _init() -> void:
	super._init("stats", "Character Stats", "toggle_stats", Vector2(300, 0))


func _build() -> void:
	var info := _section()
	var info_grid := _grid(info, 2)
	for row: Array in [["name", "Name"], ["job", "Job"], ["level", "Level"], ["exp", "EXP"], ["hp", "HP"],
			["mp", "MP"], ["fame", "Fame"]]:
		_pair(info_grid, row[0], row[1])

	var ap_row := HBoxContainer.new()
	ap_row.mouse_filter = MOUSE_FILTER_IGNORE
	var ap_title := Label.new()
	ap_title.text = "Ability Points"
	ap_title.theme_type_variation = &"MisoHeading"
	ap_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ap_row.add_child(ap_title)
	ap_box = PanelContainer.new()
	ap_box.theme_type_variation = &"MisoSlot"
	ap_box.custom_minimum_size = Vector2(54, 0)
	ap_label = MisoTheme.make_label("0", 16, MisoTheme.GOLD, 3, MisoTheme.WEIGHT_BLACK)
	ap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ap_box.add_child(ap_label)
	ap_row.add_child(ap_box)
	body.add_child(ap_row)

	var sp_row := HBoxContainer.new()
	sp_row.mouse_filter = MOUSE_FILTER_IGNORE
	var sp_title := Label.new()
	var skills_key := MisoUiEnv.key_label("toggle_skills")
	sp_title.text = "Skill Points%s" % (" [%s]" % skills_key if skills_key != "" else "")
	sp_title.theme_type_variation = &"MisoHeading"
	sp_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp_title.tooltip_text = "Spend SP in the Skills window"
	sp_row.add_child(sp_title)
	sp_box = PanelContainer.new()
	sp_box.theme_type_variation = &"MisoSlot"
	sp_box.custom_minimum_size = Vector2(54, 0)
	sp_label = MisoTheme.make_label("0", 16, MisoTheme.GOLD, 3, MisoTheme.WEIGHT_BLACK)
	sp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sp_box.add_child(sp_label)
	sp_row.add_child(sp_box)
	body.add_child(sp_row)

	var abil := _section()
	var abil_grid := _grid(abil, 3)
	for stat in CharacterState.STAT_KEYS:
		var name_l := Label.new()
		name_l.text = MisoUiText.STAT_NAMES.get(stat, stat.to_upper())
		name_l.theme_type_variation = &"MisoHeading"
		name_l.custom_minimum_size = Vector2(70, 0)
		abil_grid.add_child(name_l)
		var v := Label.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		abil_grid.add_child(v)
		values[stat] = v
		var plus := MisoWindow.make_button("+", &"MisoAccentButton")
		plus.custom_minimum_size = PLUS_SIZE
		plus.add_theme_font_size_override("font_size", 19)
		plus.add_theme_font_override("font", MisoTheme.black_font())
		plus.tooltip_text = "Spend 1 AP on %s" % name_l.text
		plus.pressed.connect(add_point.bind(String(stat)))
		abil_grid.add_child(PlusCell.new(plus))
		plus_buttons[stat] = plus

	var derived := _section()
	var d_grid := _grid(derived, 4)
	for row: Array in [["damage", "Damage"], ["acc", "ACC"], ["avoid", "AVOID"], ["wdef", "W.DEF"], ["mdef", "M.DEF"],
			["magic", "Magic"], ["speed", "Speed"], ["jump", "Jump"]]:
		_pair(d_grid, row[0], row[1])
	# The damage range is the widest number: give it a row of its own.
	var dmg_label: Label = values["damage"]
	dmg_label.add_theme_color_override("font_color", MisoTheme.ACCENT_LIGHT)


func refresh() -> void:
	ensure_built()
	var c := env.character() if env != null else null
	var db := env.get_db() if env != null else null
	if c == null or db == null:
		for k in values:
			(values[k] as Label).text = "-"
		for s in plus_buttons:
			(plus_buttons[s] as Button).visible = false
		ap_label.text = "-"
		sp_label.text = "-"
		return
	var snap := StatCalculator.snapshot(c, db)
	_show("name", c.name)
	_show("job", env.job_name(c))
	_show("level", str(c.level))
	var need := Progression.exp_to_next(c.level, db)
	if need > 0:
		_show("exp", "%s / %s  (%.2f%%)" % [MisoTheme.thousands(c.exp), MisoTheme.thousands(need), 100.0 * float(c.exp) / float(need)])
	else:
		_show("exp", "MAX")
	_show("hp", "%s / %s" % [MisoTheme.thousands(c.hp), MisoTheme.thousands(int(snap["max_hp"]))])
	_show("mp", "%s / %s" % [MisoTheme.thousands(c.mp), MisoTheme.thousands(int(snap["max_mp"]))])
	_show("fame", str(c.fame))
	var allowed := allocatable_stats(db)
	for stat in CharacterState.STAT_KEYS:
		var base := c.get_base_stat(stat)
		var total := int(snap.get(stat, base))
		var bonus := total - base
		var text := str(total)
		if bonus != 0:
			text += "  (%d %s %d)" % [base, "+" if bonus > 0 else "-", absi(bonus)]
		_show(stat, text)
		var plus: Button = plus_buttons[stat]
		plus.visible = c.ap > 0 and stat in allowed
	ap_label.text = str(c.ap)
	ap_label.add_theme_color_override("font_color", MisoTheme.GOLD if c.ap > 0 else MisoTheme.TEXT_DIM)
	sp_label.text = str(c.sp)
	sp_label.add_theme_color_override("font_color", MisoTheme.GOLD if c.sp > 0 else MisoTheme.TEXT_DIM)
	_show("damage", "%s ~ %s" % [MisoTheme.thousands(int(snap["damage_min"])), MisoTheme.thousands(int(snap["damage_max"]))])
	_show("acc", str(int(snap["acc"])))
	_show("avoid", str(int(snap["avoid"])))
	_show("wdef", str(int(snap["wdef"])))
	_show("mdef", str(int(snap["mdef"])))
	_show("magic", str(int(snap["matk"])))
	_show("speed", "%d%%" % int(snap["speed"]))
	_show("jump", "%d%%" % int(snap["jump"]))


## Spends one AP on a stat (Game.allocate_ap). Returns false when refused (no AP, a stat that takes no AP).
func add_point(stat: String) -> bool:
	if env == null:
		return false
	var ok := env.allocate_ap(stat, 1)
	refresh()
	return ok


## The text currently shown for a value key ("str", "acc", "damage", ...).
func value_text(key: String) -> String:
	return (values[key] as Label).text if values.has(key) else ""


## Stats that take AP (canonical formulas/beginner.json ap.allocatable_stats; CharacterState.STAT_KEYS without data).
static func allocatable_stats(db: ContentDB) -> PackedStringArray:
	if db != null:
		var ap: Variant = db.formula("beginner").get("ap", {})
		if ap is Dictionary and (ap as Dictionary).get("allocatable_stats") is Array:
			return PackedStringArray((ap as Dictionary)["allocatable_stats"])
	return CharacterState.STAT_KEYS


func _show(key: String, text: String) -> void:
	if values.has(key):
		(values[key] as Label).text = text


func _section() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"MisoInset"
	p.mouse_filter = MOUSE_FILTER_IGNORE
	body.add_child(p)
	return p


func _grid(parent: Control, columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 3)
	g.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(g)
	return g


func _pair(grid: GridContainer, key: String, label: String) -> void:
	var name_l := Label.new()
	name_l.text = label
	name_l.theme_type_variation = &"MisoDim"
	name_l.add_theme_font_size_override("font_size", MisoTheme.FONT_SIZE)
	grid.add_child(name_l)
	var v := Label.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(v)
	values[key] = v
