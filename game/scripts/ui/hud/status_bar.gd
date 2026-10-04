class_name MisoStatusBar
extends PanelContainer
## The HUD's bottom bar: level (gold), name and job; HP and MP gauges with current / max; the EXP gauge with its
## percent; mesos; buttons that open the character windows (with their keys, and an AP badge on Stat while points
## are unspent); and the quickslot bar on the right. It only displays values handed to it; MisoHud decides when.

signal window_requested(window_name: String)

const GAUGE_WIDTH := 300.0
const MENU_BUTTON_WIDTH := 112.0

var level_label: Label
var name_label: Label
var job_label: Label
var hp_gauge: MisoGauge
var mp_gauge: MisoGauge
var exp_gauge: MisoGauge
var mesos_label: Label
## Unspent AP shown on the Stat button (0 = none).
var ap_available: int = 0
var menu_buttons: Dictionary = {}
var quickslots: MisoQuickslotBar


func _init() -> void:
	theme_type_variation = &"MisoHud"
	mouse_filter = MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(row)

	# Level, name, job.
	var who := VBoxContainer.new()
	who.custom_minimum_size = Vector2(150, 0)
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", -2)
	who.mouse_filter = MOUSE_FILTER_IGNORE
	var lv_row := HBoxContainer.new()
	lv_row.add_theme_constant_override("separation", 4)
	lv_row.mouse_filter = MOUSE_FILTER_IGNORE
	var lv_tag := MisoTheme.make_label("Lv.", 16, MisoTheme.ACCENT_LIGHT, 4, MisoTheme.WEIGHT_BLACK)
	lv_tag.size_flags_vertical = Control.SIZE_SHRINK_END
	lv_row.add_child(lv_tag)
	level_label = MisoTheme.make_label("1", 34, MisoTheme.GOLD, 6, MisoTheme.WEIGHT_BLACK)
	lv_row.add_child(level_label)
	who.add_child(lv_row)
	name_label = MisoTheme.make_label("", 15, MisoTheme.TEXT, 3, MisoTheme.WEIGHT_BOLD)
	who.add_child(name_label)
	job_label = MisoTheme.make_label("", 12, MisoTheme.TEXT_DIM, 2)
	who.add_child(job_label)
	row.add_child(who)
	row.add_child(_vsep())

	# Gauges.
	var gauges := VBoxContainer.new()
	gauges.alignment = BoxContainer.ALIGNMENT_CENTER
	gauges.add_theme_constant_override("separation", 6)
	gauges.mouse_filter = MOUSE_FILTER_IGNORE
	var hpmp := HBoxContainer.new()
	hpmp.add_theme_constant_override("separation", 8)
	hpmp.mouse_filter = MOUSE_FILTER_IGNORE
	hp_gauge = MisoGauge.new("HP", MisoTheme.HP, 22.0)
	hp_gauge.custom_minimum_size.x = GAUGE_WIDTH
	mp_gauge = MisoGauge.new("MP", MisoTheme.MP, 22.0)
	mp_gauge.custom_minimum_size.x = GAUGE_WIDTH
	hpmp.add_child(hp_gauge)
	hpmp.add_child(mp_gauge)
	gauges.add_child(hpmp)
	exp_gauge = MisoGauge.new("EXP", MisoTheme.EXP, 18.0)
	exp_gauge.custom_minimum_size.x = GAUGE_WIDTH * 2 + 8
	gauges.add_child(exp_gauge)
	row.add_child(gauges)
	row.add_child(_vsep())

	# Mesos.
	var money := VBoxContainer.new()
	money.alignment = BoxContainer.ALIGNMENT_CENTER
	money.custom_minimum_size = Vector2(120, 0)
	money.mouse_filter = MOUSE_FILTER_IGNORE
	var meso_row := HBoxContainer.new()
	meso_row.add_theme_constant_override("separation", 6)
	meso_row.mouse_filter = MOUSE_FILTER_IGNORE
	meso_row.add_child(MisoCoinIcon.new(20))
	mesos_label = MisoTheme.make_label("0", 17, MisoTheme.GOLD, 4, MisoTheme.WEIGHT_BLACK)
	meso_row.add_child(mesos_label)
	money.add_child(meso_row)
	var meso_tag := MisoTheme.make_label("mesos", 12, MisoTheme.TEXT_DIM, 2)
	money.add_child(meso_tag)
	row.add_child(money)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# Window buttons (2 x 2).
	var menu := GridContainer.new()
	menu.columns = 2
	menu.add_theme_constant_override("h_separation", 5)
	menu.add_theme_constant_override("v_separation", 5)
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for entry: Array in [["inventory", "Item", "toggle_inventory"], ["equipment", "Equip", "toggle_equipment"],
			["stats", "Stat", "toggle_stats"], ["quests", "Quest", "toggle_quests"]]:
		var key := MisoUiEnv.key_label(String(entry[2]))
		var b := MisoWindow.make_button("%s%s" % [entry[1], " [%s]" % key if key != "" else ""])
		b.custom_minimum_size = Vector2(MENU_BUTTON_WIDTH, 30)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func() -> void: window_requested.emit(String(entry[0])))
		menu.add_child(b)
		menu_buttons[String(entry[0])] = b
	row.add_child(menu)

	# Quickslots.
	quickslots = MisoQuickslotBar.new()
	quickslots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(quickslots)


func set_identity(level: int, char_name: String, job: String) -> void:
	level_label.text = str(level)
	name_label.text = char_name
	job_label.text = job


func set_hp(hp: int, max_hp: int) -> void:
	hp_gauge.set_values(hp, max_hp)


func set_mp(mp: int, max_mp: int) -> void:
	mp_gauge.set_values(mp, max_mp)


## need = EXP to the next level (0 at the level cap: the gauge shows full and "MAX").
func set_exp(exp_value: int, need: int) -> void:
	if need <= 0:
		exp_gauge.set_values(1, 1, "MAX")
		return
	var pct := 100.0 * float(exp_value) / float(need)
	exp_gauge.set_values(exp_value, need, "%s / %s   [%.2f%%]" % [MisoTheme.thousands(exp_value),
		MisoTheme.thousands(need), pct])


func set_mesos(mesos: int) -> void:
	mesos_label.text = MisoTheme.thousands(mesos)


## While AP is unspent the Stat button turns orange and shows the points ("Stat [C] +5").
func set_ap(ap: int) -> void:
	ap_available = ap
	var b: Button = menu_buttons["stats"]
	var key := MisoUiEnv.key_label("toggle_stats")
	b.text = "Stat%s%s" % [" [%s]" % key if key != "" else "", "  +%d" % ap if ap > 0 else ""]
	b.theme_type_variation = &"MisoAccentButton" if ap > 0 else &""
	b.tooltip_text = "%d AP to distribute" % ap if ap > 0 else "Character stats"


func _vsep() -> VSeparator:
	var s := VSeparator.new()
	s.mouse_filter = MOUSE_FILTER_IGNORE
	return s
