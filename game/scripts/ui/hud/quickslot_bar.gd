class_name MisoQuickslotBar
extends GridContainer
## The HUD quickslots: one slot per quickslot_N action (keys 1-8), showing the bound consumable icon and how many the
## inventory holds (0 = greyed). Press the key (or double-click the slot) to use it; drop a consumable from the
## inventory on a slot to bind it; drag between slots to move a binding; right-click to clear. Bindings live in
## CharacterState.quickslots (MisoQuickslots), so they persist with the save.

signal use_requested(key: String)
signal hover_changed(slot: MisoItemSlot, inside: bool)

const SLOT_SIZE := 40.0

var env: MisoUiEnv = null
## key -> MisoItemSlot
var slots: Dictionary = {}


func _init() -> void:
	columns = 4
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 4)
	mouse_filter = MOUSE_FILTER_IGNORE
	for key in MisoQuickslots.keys():
		var s := MisoItemSlot.new(SLOT_SIZE)
		s.slot_name = key
		s.set_key_text(MisoQuickslots.key_text(key))
		s.activated.connect(func(sl: MisoItemSlot) -> void: use_requested.emit(sl.slot_name))
		s.context_requested.connect(func(sl: MisoItemSlot) -> void:
			if env != null:
				MisoQuickslots.unbind(env, sl.slot_name))
		s.hover_changed.connect(func(sl: MisoItemSlot, inside: bool) -> void: hover_changed.emit(sl, inside))
		s.drag_source = _drag_data
		s.drop_filter = _can_drop
		s.drop_handler = _drop
		add_child(s)
		slots[key] = s


## Redraws every slot from the character's bindings and inventory counts.
func refresh() -> void:
	var c := env.character() if env != null else null
	var db := env.get_db() if env != null else null
	for key: String in slots:
		var s: MisoItemSlot = slots[key]
		var item_id := MisoQuickslots.item_for(c, key)
		if item_id == "" or c == null:
			s.clear()
		else:
			s.set_stack(item_id, c.inventory.count(item_id), db, {}, true)


## The count shown on a key ("" when empty), for tests.
func count_text(key: String) -> String:
	return (slots[key] as MisoItemSlot).count_label.text if slots.has(key) else ""


func _drag_data(slot: MisoItemSlot) -> Variant:
	return {"kind": MisoQuickslots.DRAG_KIND, "source": "quickslot", "key": slot.slot_name, "item_id": slot.item_id}


func _can_drop(_slot: MisoItemSlot, d: Variant) -> bool:
	if not (d is Dictionary and d.get("kind") == MisoQuickslots.DRAG_KIND):
		return false
	if d.get("source") == "quickslot":
		return true
	return env != null and MisoQuickslots.can_bind(String(d.get("item_id", "")), env.get_db())


func _drop(slot: MisoItemSlot, d: Variant) -> void:
	if env == null:
		return
	if d.get("source") == "quickslot":
		MisoQuickslots.move(env, String(d.get("key", "")), slot.slot_name)
	else:
		MisoQuickslots.bind(env, slot.slot_name, String(d.get("item_id", "")))
	refresh()
