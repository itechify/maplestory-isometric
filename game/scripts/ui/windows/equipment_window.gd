class_name MisoEquipmentWindow
extends MisoWindow
## The Equipment window (toggle_equipment, E): a paper-doll layout of every equipment slot (the slot list comes from
## data/misostory/inventory.json through ItemsConfig.equipment_slots), equipped pieces with inspect tooltips,
## unequip on double-click (through ItemService.unequip; a full Equip tab fails gracefully with a message and
## nothing changes), and the summed stat contribution of the equipped gear (Equipment.total_bonuses).
## Dragging an equippable item from the inventory onto the doll equips it.

const SLOT_SIZE := 46.0
const PITCH := 52.0
## Doll position (column, row) of each known slot. Presentation only; a slot missing here (a future slot added to
## inventory.json) is placed in the free cells of the bottom rows, so new slots never disappear.
const LAYOUT := {
	"ring_1": Vector2i(0, 0), "face_accessory": Vector2i(1, 0), "hat": Vector2i(2, 0), "eye_accessory": Vector2i(3, 0),
	"ring_2": Vector2i(4, 0),
	"ring_3": Vector2i(0, 1), "earrings": Vector2i(1, 1), "top": Vector2i(2, 1), "cape": Vector2i(3, 1),
	"ring_4": Vector2i(4, 1),
	"pendant": Vector2i(0, 2), "gloves": Vector2i(1, 2), "bottom": Vector2i(2, 2), "weapon": Vector2i(3, 2),
	"shield": Vector2i(4, 2),
	"overall": Vector2i(1, 3), "shoes": Vector2i(2, 3),
}
const COLUMNS := 5
## Short captions for empty slots.
const CAPTIONS := {
	"weapon": "Weapon", "hat": "Hat", "top": "Top", "bottom": "Bottom", "overall": "Overall", "shoes": "Shoes",
	"gloves": "Gloves", "cape": "Cape", "shield": "Shield", "earrings": "Earring", "face_accessory": "Face",
	"eye_accessory": "Eye", "pendant": "Pendant", "ring_1": "Ring", "ring_2": "Ring", "ring_3": "Ring", "ring_4": "Ring",
}

var tooltip_host: Object = null
## slot name -> MisoItemSlot
var slot_controls: Dictionary = {}
var doll: Control
var bonus_grid: GridContainer
var status_label: Label
var _laid_out_for: PackedStringArray = []


func _init() -> void:
	super._init("equipment", "Equipment", "toggle_equipment", Vector2(COLUMNS * PITCH + 30, 0))


func _build() -> void:
	var inset := PanelContainer.new()
	inset.theme_type_variation = &"MisoInset"
	inset.mouse_filter = MOUSE_FILTER_IGNORE
	body.add_child(inset)
	doll = MisoDollBackdrop.new()
	inset.add_child(doll)

	var head := Label.new()
	head.text = "Equipment bonuses"
	head.theme_type_variation = &"MisoHeading"
	body.add_child(head)
	var bonus_inset := PanelContainer.new()
	bonus_inset.theme_type_variation = &"MisoInset"
	bonus_inset.mouse_filter = MOUSE_FILTER_IGNORE
	body.add_child(bonus_inset)
	bonus_grid = GridContainer.new()
	bonus_grid.columns = 4
	bonus_grid.add_theme_constant_override("h_separation", 10)
	bonus_inset.add_child(bonus_grid)

	status_label = add_status_line("Double-click a piece to take it off.")


func refresh() -> void:
	ensure_built()
	var db := env.get_db() if env != null else null
	_layout(ItemsConfig.equipment_slots(db))
	var c := env.character() if env != null else null
	for slot_name: String in slot_controls:
		var sc: MisoItemSlot = slot_controls[slot_name]
		var inst: Dictionary = c.equipment.instance_in(slot_name) if c != null else {}
		if inst.is_empty():
			sc.clear()
		else:
			sc.set_stack(String(inst.item_id), 1, db, inst.get("data", {}))
	_refresh_bonuses(c, db)


## Takes off the piece in an equipment slot. Returns the ItemService result (inventory_full leaves it equipped).
func unequip_slot(slot_name: String) -> Dictionary:
	var items := env.items() if env != null else null
	if items == null:
		return {"ok": false, "code": "unavailable"}
	var item_id := env.character().equipment.item_in(slot_name)
	var res := items.unequip(slot_name)
	if res.get("ok", false):
		set_status("Took off %s." % env.item_name(item_id))
	else:
		var msg := MisoUiText.result_message(res, env.get_db())
		set_status(msg, true)
		env.notice(msg)
	refresh()
	return res


## Equips an item from the inventory (drag onto the doll). Returns the ItemService result.
func equip_from_inventory(item_id: String, inv_index: int = -1) -> Dictionary:
	var items := env.items() if env != null else null
	if items == null:
		return {"ok": false, "code": "unavailable"}
	var res := items.equip(item_id, inv_index)
	if res.get("ok", false):
		set_status("Equipped %s." % env.item_name(item_id))
	else:
		var msg := MisoUiText.result_message(res, env.get_db())
		set_status(msg, true)
		env.notice(msg)
	refresh()
	return res


## The bonus lines currently listed ({key: value}), for tests.
func bonus_lines() -> Dictionary:
	var out := {}
	for ch in bonus_grid.get_children():
		if ch.has_meta("bonus_key"):
			out[String(ch.get_meta("bonus_key"))] = int(ch.get_meta("bonus_value"))
	return out


func _layout(all_slots: PackedStringArray) -> void:
	if all_slots == _laid_out_for and not slot_controls.is_empty():
		return
	_laid_out_for = all_slots
	for sc in slot_controls.values():
		(sc as Node).queue_free()
	slot_controls.clear()
	var used := {}
	for slot_name in all_slots:
		if LAYOUT.has(slot_name):
			used[LAYOUT[slot_name]] = true
	var rows := 4
	var free_cell := Vector2i(0, rows)
	for slot_name in all_slots:
		var cell: Vector2i
		if LAYOUT.has(slot_name):
			cell = LAYOUT[slot_name]
		else:
			while used.has(free_cell):
				free_cell.x += 1
				if free_cell.x >= COLUMNS:
					free_cell = Vector2i(0, free_cell.y + 1)
			cell = free_cell
			used[cell] = true
		rows = maxi(rows, cell.y + 1)
		var sc := MisoItemSlot.new(SLOT_SIZE)
		sc.slot_name = slot_name
		sc.set_caption(CAPTIONS.get(slot_name, slot_name.capitalize()))
		sc.position = Vector2(cell.x * PITCH + 2, cell.y * PITCH + 2)
		sc.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		sc.activated.connect(func(s: MisoItemSlot) -> void:
			if not s.is_empty():
				unequip_slot(s.slot_name))
		sc.hover_changed.connect(_on_hover)
		sc.drop_filter = _can_drop
		sc.drop_handler = _drop
		doll.add_child(sc)
		slot_controls[slot_name] = sc
	doll.custom_minimum_size = Vector2(COLUMNS * PITCH, rows * PITCH)


func _refresh_bonuses(c: CharacterState, db: ContentDB) -> void:
	for ch in bonus_grid.get_children():
		bonus_grid.remove_child(ch)
		ch.queue_free()
	if c == null or db == null:
		return
	var totals := c.equipment.total_bonuses(db)
	var any := false
	for k in MisoItemTooltip.STAT_ORDER:
		var v := int(totals.get(k, 0))
		if v == 0:
			continue
		any = true
		var name_l := Label.new()
		name_l.text = String(MisoItemTooltip.STAT_LABELS.get(k, k)).replace("Weapon Attack", "W.ATK") \
			.replace("Magic Attack", "M.ATK").replace("Weapon Def.", "W.DEF").replace("Magic Def.", "M.DEF")
		name_l.theme_type_variation = &"MisoSmall"
		bonus_grid.add_child(name_l)
		var val := Label.new()
		val.text = "%s%d%s" % ["+" if v > 0 else "", v, "%" if k.ends_with("_pct") else ""]
		val.theme_type_variation = &"MisoGood"
		val.set_meta("bonus_key", k)
		val.set_meta("bonus_value", v)
		bonus_grid.add_child(val)
	if not any:
		var none := Label.new()
		none.text = "Nothing equipped adds stats."
		none.theme_type_variation = &"MisoDim"
		bonus_grid.add_child(none)


func _on_hover(slot: MisoItemSlot, inside: bool) -> void:
	if tooltip_host == null:
		return
	if inside and not slot.is_empty():
		tooltip_host.call("show_item_tooltip", slot.item_id, {"data": slot.data, "equipped": true,
			"hint": "Double-click to take off"}, slot)
	else:
		tooltip_host.call("hide_item_tooltip")


func _can_drop(slot: MisoItemSlot, d: Variant) -> bool:
	if not (d is Dictionary and d.get("kind") == MisoQuickslots.DRAG_KIND and d.get("source") == "inventory"):
		return false
	var def := ItemDef.of(String(d.get("item_id", "")), env.get_db() if env != null else null)
	return def != null and def.is_equipment() and slot.slot_name in ItemsConfig.slots_for(def.equip_slot, env.get_db())


func _drop(_slot: MisoItemSlot, d: Variant) -> void:
	equip_from_inventory(String(d["item_id"]), int(d.get("index", -1)) if d.get("tab") == "equip" else -1)


func _on_closed() -> void:
	if tooltip_host != null:
		tooltip_host.call("hide_item_tooltip")
