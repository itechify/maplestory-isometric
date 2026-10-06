class_name MisoEffectsBar
extends HBoxContainer
## The HUD's row of active timed effects (CharacterState.effects, contract C3: Nimble Feet, Recovery): one icon per
## effect, newest last, with the time left under it and the name, level and seconds left in its tooltip. The dark sweep
## over the icon grows as the effect runs out (the elapsed share of data.duration_s). Without it a player cannot see a
## buff at all: only a cast's cooldown showed, on its quickslot. A MisoStory UI adaptation; MeowDB publishes no HUD.
##
## Reads the live character through the HUD's MisoUiEnv on every refresh (never cached); MisoHud calls refresh() on
## Events.effects_changed, game_loaded and a replaced character, and the bar redraws itself every REDRAW_S while an
## effect runs, since remaining_s counts down every physics tick without an event.

## Presentation constants (UI.md convention: drawn in code, not gameplay values). The icon is a quickslot's size
## (MisoQuickslotBar.SLOT_SIZE), and the time left is drawn bold with a dark outline so it reads over any ground.
const ICON_SIZE := 40.0
const REDRAW_S := 0.2
const TIME_FONT_SIZE := 14

var env: MisoUiEnv = null
## Effect id -> its cell (VBoxContainer: the icon, then the time label), in c.effects order.
var cells: Dictionary = {}
var _since_redraw: float = 0.0


func _init() -> void:
	name = "Effects"
	mouse_filter = MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 6)


func _process(delta: float) -> void:
	if cells.is_empty():
		return
	_since_redraw += delta
	if _since_redraw >= REDRAW_S:
		_since_redraw = 0.0
		refresh()


## Rebuilds the row from the live character's effects: a cell per effect with a positive remaining_s, its time left
## and its sweep. Cells of effects that ended go.
func refresh() -> void:
	var c := env.character() if env != null else null
	var db := env.get_db() if env != null else null
	var live := {}
	var order: Array[String] = []
	if c != null:
		for e: Variant in c.effects:
			if not (e is Dictionary):
				continue
			var left := EffectBook.remaining_of(e)
			var id := String((e as Dictionary).get("id", ""))
			if id == "" or left <= 0.0:
				continue
			live[id] = e
			order.append(id)
	for id: String in cells.keys():
		if not live.has(id):
			var gone: Control = cells[id]
			cells.erase(id)
			remove_child(gone)
			gone.queue_free()
	for i in order.size():
		var id := order[i]
		if not cells.has(id):
			cells[id] = _make_cell(id)
			add_child(cells[id])
		var cell: Control = cells[id]
		move_child(cell, i)
		_show(cell, live[id], db)


## What the row shows, for tests and tools: [{id, skill_id, name, time, tooltip, sweep}] in order.
func snapshot() -> Array:
	var out: Array = []
	for child in get_children():
		if not (child is Control) or not child.has_meta("effect_id"):
			continue
		var icon: MisoSkillIcon = child.get_node("Icon")
		var label: Label = child.get_node("Time")
		out.append({"id": String(child.get_meta("effect_id")), "skill_id": icon.skill_id, "name": String(child.get_meta("label")),
			"time": label.text, "tooltip": (child as Control).tooltip_text, "sweep": icon.cooldown})
	return out


## "1:05" for a minute or more, else "45s"; rounded up (a buff with 0.2 s left still shows 1s).
static func time_text(seconds: float) -> String:
	var s := ceili(maxf(seconds, 0.0))
	if s >= 60:
		return "%d:%02d" % [s / 60, s % 60]
	return "%ds" % s


func _make_cell(id: String) -> Control:
	var cell := VBoxContainer.new()
	cell.set_meta("effect_id", id)
	# STOP, like an item slot: the tooltip shows, and a click on the icon never reaches the world (mouse attacks come
	# from unhandled input only).
	cell.mouse_filter = MOUSE_FILTER_STOP
	cell.add_theme_constant_override("separation", 0)
	var icon := MisoSkillIcon.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	cell.add_child(icon)
	var label := MisoTheme.make_label("", TIME_FONT_SIZE, MisoTheme.TEXT, 4, MisoTheme.WEIGHT_BOLD)
	label.name = "Time"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = MOUSE_FILTER_IGNORE
	cell.add_child(label)
	return cell


func _show(cell: Control, e: Dictionary, db: ContentDB) -> void:
	var data: Dictionary = e.get("data", {}) if e.get("data", null) is Dictionary else {}
	var skill_id := String(data.get("skill_id", ""))
	var source := String(e.get("source", ""))
	if skill_id == "" and source.begins_with("skill:"):
		skill_id = source.trim_prefix("skill:")
	var def := SkillDef.of(skill_id, db) if skill_id != "" and db != null else null
	var label := def.name if def != null and def.name != "" else String(e.get("id", ""))
	var level := int(data.get("level", 0))
	var left := EffectBook.remaining_of(e)
	var total := float(data.get("duration_s", 0.0))
	var icon: MisoSkillIcon = cell.get_node("Icon")
	icon.skill_id = skill_id if skill_id != "" else "?"
	icon.cooldown = clampf(1.0 - left / total, 0.0, 1.0) if total > 0.0 else 0.0
	(cell.get_node("Time") as Label).text = time_text(left)
	cell.set_meta("label", label)
	cell.tooltip_text = "%s%s\n%s left" % [label, "  Lv. %d" % level if level > 0 else "", time_text(left)]
