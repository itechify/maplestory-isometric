class_name MisoQuickslotBar
extends GridContainer
## The HUD quickslots: one slot per quickslot_N action (keys 1-8). An item binding shows the item's icon and how many
## the inventory holds (0 = greyed); a skill binding shows the skill's icon, greyed while the character lacks the MP
## or the shell item for it, with the cooldown drawn as a dark sweep and the seconds left. Press the key (or
## double-click the slot) to use it; drop a consumable or a chair from the inventory, or a skill from the skill
## window, on a slot to bind it; drag between slots to move a binding; right-click to clear. Bindings live in
## CharacterState.quickslots as typed values (MisoQuickslots), so they persist with the save.

signal use_requested(key: String)
## Item slots only (the HUD shows the item card); a skill slot shows its own tooltip text.
signal hover_changed(slot: MisoItemSlot, inside: bool)

const SLOT_SIZE := 40.0


## A quickslot square: an item slot that can also hold a skill (an icon overlay with the cooldown sweep, showing its
## mouse-over picture while the pointer is over the slot).
class QuickslotCell extends MisoItemSlot:
	## The bound skill ("" for an item binding or an empty slot).
	var skill_id: String = ""
	var skill_icon: MisoSkillIcon

	func _init(slot_size: float) -> void:
		super._init(slot_size)
		skill_icon = MisoSkillIcon.new()
		skill_icon.visible = false
		add_child(skill_icon)
		# Under the slot's own layer, so the key label stays on top.
		move_child(skill_icon, 0)
		hover_changed.connect(func(_slot: MisoItemSlot, inside: bool) -> void: skill_icon.hover = inside)

	## Shows a skill binding (clears any item).
	func set_skill(p_skill_id: String, usable: bool, cooldown_share: float, cooldown_left_s: float) -> void:
		if item_id != "":
			clear()
		skill_id = p_skill_id
		skill_icon.visible = true
		skill_icon.skill_id = p_skill_id
		skill_icon.dim = not usable
		skill_icon.cooldown = cooldown_share
		skill_icon.cooldown_text = str(ceili(cooldown_left_s)) if cooldown_left_s > 0.0 else ""
		caption_label.visible = false

	func clear_skill() -> void:
		skill_id = ""
		skill_icon.visible = false
		skill_icon.skill_id = ""
		tooltip_text = ""
		caption_label.visible = item_id == ""

	func is_empty() -> bool:
		return item_id == "" and skill_id == ""

	func _get_drag_data(at_position: Vector2) -> Variant:
		if skill_id == "":
			return super._get_drag_data(at_position)
		if not drag_source.is_valid():
			return null
		var d: Variant = drag_source.call(self)
		var preview := MisoSkillIcon.new()
		preview.size = Vector2(36, 36)
		preview.position = Vector2(-18, -18)
		preview.skill_id = skill_id
		var holder := Control.new()
		holder.add_child(preview)
		set_drag_preview(holder)
		return d


## Seconds between redraws of the skill slots while any is bound (MP greying follows MP, the sweep follows the
## cooldown; presentation).
const SKILL_REDRAW_S := 0.1

var env: MisoUiEnv = null
## key -> QuickslotCell
var slots: Dictionary = {}
## True while any bound skill is cooling down (the bar then redraws its sweeps every frame).
var _cooling: bool = false
var _has_skills: bool = false
var _since_redraw: float = 0.0


func _init() -> void:
	columns = 4
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 4)
	mouse_filter = MOUSE_FILTER_IGNORE
	for key in MisoQuickslots.keys():
		var s := QuickslotCell.new(SLOT_SIZE)
		s.slot_name = key
		s.set_key_text(MisoQuickslots.key_text(key))
		s.activated.connect(func(sl: MisoItemSlot) -> void: use_requested.emit(sl.slot_name))
		s.context_requested.connect(func(sl: MisoItemSlot) -> void:
			if env != null:
				MisoQuickslots.unbind(env, sl.slot_name))
		s.hover_changed.connect(func(sl: MisoItemSlot, inside: bool) -> void:
			hover_changed.emit(sl, inside and (sl as QuickslotCell).skill_id == ""))
		s.drag_source = _drag_data
		s.drop_filter = _can_drop
		s.drop_handler = _drop
		add_child(s)
		slots[key] = s


func _process(delta: float) -> void:
	if not _has_skills:
		return
	_since_redraw += delta
	if _cooling or _since_redraw >= SKILL_REDRAW_S:
		_since_redraw = 0.0
		refresh_skills()


## Redraws every slot from the character's bindings, inventory counts, MP and cooldowns.
func refresh() -> void:
	var c := env.character() if env != null else null
	var db := env.get_db() if env != null else null
	_has_skills = false
	for key: String in slots:
		var s: QuickslotCell = slots[key]
		var b := MisoQuickslots.binding(c, key)
		if b.is_empty() or c == null:
			s.clear_skill()
			s.clear()
		elif b["kind"] == MisoQuickslots.KIND_SKILL:
			s.clear_skill()
			_show_skill(s, c, db, String(b["id"]))
			_has_skills = true
		else:
			s.clear_skill()
			s.set_stack(String(b["id"]), c.inventory.count(String(b["id"])), db, {}, true)
			s.tooltip_text = ""


## Redraws only the skill slots (MP greying and the cooldown sweeps).
func refresh_skills() -> void:
	var c := env.character() if env != null else null
	var db := env.get_db() if env != null else null
	_cooling = false
	for key: String in slots:
		var s: QuickslotCell = slots[key]
		if s.skill_id != "" and c != null:
			_show_skill(s, c, db, s.skill_id)


func _show_skill(s: QuickslotCell, c: CharacterState, db: ContentDB, skill_id: String) -> void:
	var def := SkillDef.of(skill_id, db) if db != null else null
	var level := SkillBook.level_of(c, skill_id)
	var left := EffectBook.cooldown_left(c, skill_id)
	var total := def.cooldown_s(maxi(1, mini(level, def.max_level))) if def != null else 0.0
	s.set_skill(skill_id, def != null and level > 0 and SkillBook.affordable(c, skill_id, db),
		left / total if total > 0.0 else 0.0, left)
	if left > 0.0:
		_cooling = true
	s.tooltip_text = "%s  Lv. %d\nKey %s  ·  right-click to clear" % [def.name if def != null else skill_id, level,
		s.key_label.text]


## The count shown on a key ("" when empty or a skill), for tests.
func count_text(key: String) -> String:
	return (slots[key] as MisoItemSlot).count_label.text if slots.has(key) else ""


## The skill shown on a key ("" when none), for tests.
func skill_on(key: String) -> String:
	return (slots[key] as QuickslotCell).skill_id if slots.has(key) else ""


func _drag_data(slot: MisoItemSlot) -> Variant:
	var cell := slot as QuickslotCell
	if cell != null and cell.skill_id != "":
		return {"kind": MisoQuickslots.SKILL_DRAG_KIND, "source": "quickslot", "key": slot.slot_name, "skill_id": cell.skill_id}
	return {"kind": MisoQuickslots.DRAG_KIND, "source": "quickslot", "key": slot.slot_name, "item_id": slot.item_id}


func _can_drop(_slot: MisoItemSlot, d: Variant) -> bool:
	if not (d is Dictionary):
		return false
	var kind: Variant = d.get("kind")
	if kind != MisoQuickslots.DRAG_KIND and kind != MisoQuickslots.SKILL_DRAG_KIND:
		return false
	if d.get("source") == "quickslot":
		return true
	if env == null:
		return false
	if kind == MisoQuickslots.SKILL_DRAG_KIND:
		return MisoQuickslots.can_bind_skill(env.character(), String(d.get("skill_id", "")), env.get_db())
	return MisoQuickslots.can_bind(String(d.get("item_id", "")), env.get_db())


func _drop(slot: MisoItemSlot, d: Variant) -> void:
	if env == null:
		return
	if d.get("source") == "quickslot":
		MisoQuickslots.move(env, String(d.get("key", "")), slot.slot_name)
	elif d.get("kind") == MisoQuickslots.SKILL_DRAG_KIND:
		MisoQuickslots.bind_skill(env, slot.slot_name, String(d.get("skill_id", "")))
	else:
		MisoQuickslots.bind(env, slot.slot_name, String(d.get("item_id", "")))
	refresh()
