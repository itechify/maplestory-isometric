class_name MisoInventoryWindow
extends MisoWindow
## The Item Inventory window (toggle_inventory, I): the five classic tabs (Equip / Use / Set-up / Etc / Cash), a
## slot grid sized from the live Inventory, procedural icons with stack counts, an inspect tooltip, mesos, and the
## actions:
##   - double-click (or select + Enter, or the action button): use a consumable / equip a piece of equipment;
##   - drag a slot onto another slot of the same tab: move / merge / swap (ItemService.move);
##   - drag a consumable onto a HUD quickslot, or select it and press "Set key" then a key 1-8: bind a quickslot.
## Every change goes through ItemService, so Events (inventory_changed, item_used, equipment_changed ...) fire and
## the HUD, quests and saves hear about it. Failures are shown in the window and as an Events.notice line.

## Slots per grid row (presentation; the slot count itself comes from Inventory.capacity()).
const COLUMNS := 4
const SLOT_SIZE := 46.0
## Display names of Inventory.TABS.
const TAB_LABELS := {"equip": "Equip", "use": "Use", "setup": "Set-up", "etc": "Etc", "cash": "Cash"}

## Something that shows/hides the item tooltip: show_item_tooltip(item_id, opts, anchor) / hide_item_tooltip().
var tooltip_host: Object = null
var current_tab: String = Inventory.TABS[0]
var selected_index: int = -1
var tab_buttons: Dictionary = {}
var slots: Array[MisoItemSlot] = []
var grid: GridContainer
var mesos_label: Label
var action_button: Button
var key_button: Button
var key_picker: HBoxContainer
var status_label: Label
var _tab_group := ButtonGroup.new()


func _init() -> void:
	super._init("inventory", "Item Inventory", "toggle_inventory", Vector2(COLUMNS * (SLOT_SIZE + 6) + 34, 0))


func _build() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	tabs.mouse_filter = MOUSE_FILTER_IGNORE
	for t in Inventory.TABS:
		var b := MisoWindow.make_button(TAB_LABELS.get(t, String(t).capitalize()), &"MisoTabButton")
		b.toggle_mode = true
		b.button_group = _tab_group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = t == current_tab
		b.pressed.connect(select_tab.bind(String(t)))
		tabs.add_child(b)
		tab_buttons[String(t)] = b
	body.add_child(tabs)

	var inset := PanelContainer.new()
	inset.theme_type_variation = &"MisoInset"
	inset.mouse_filter = MOUSE_FILTER_IGNORE
	body.add_child(inset)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 6 * (SLOT_SIZE + 6))
	scroll.mouse_filter = MOUSE_FILTER_PASS
	inset.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.mouse_filter = MOUSE_FILTER_IGNORE
	scroll.add_child(grid)

	var meso_row := HBoxContainer.new()
	meso_row.mouse_filter = MOUSE_FILTER_IGNORE
	var coin := MisoCoinIcon.new()
	meso_row.add_child(coin)
	mesos_label = MisoTheme.make_label("0", 15, MisoTheme.GOLD, 3, MisoTheme.WEIGHT_BOLD)
	mesos_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meso_row.add_child(mesos_label)
	var mesos_tag := Label.new()
	mesos_tag.text = "mesos"
	mesos_tag.theme_type_variation = &"MisoSmall"
	meso_row.add_child(mesos_tag)
	body.add_child(meso_row)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	actions.mouse_filter = MOUSE_FILTER_IGNORE
	action_button = MisoWindow.make_button("Use", &"MisoAccentButton")
	action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_button.pressed.connect(func() -> void: activate_slot(selected_index))
	actions.add_child(action_button)
	key_button = MisoWindow.make_button("Set key")
	key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_button.tooltip_text = "Bind the selected consumable to a quickslot key"
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
	body.add_child(key_picker)

	status_label = add_status_line("Double-click an item to use or equip it.")


func refresh() -> void:
	ensure_built()
	var c := env.character() if env != null else null
	var db := env.get_db() if env != null else null
	if c == null:
		_ensure_slot_count(0)
		mesos_label.text = "-"
		_update_actions()
		return
	var inv := c.inventory
	var cap := inv.capacity(current_tab)
	_ensure_slot_count(cap)
	for i in cap:
		var s := inv.get_slot(current_tab, i)
		if s.is_empty():
			slots[i].clear()
		else:
			slots[i].set_stack(String(s.item_id), int(s.qty), db, s.get("data", {}))
		slots[i].set_selected(i == selected_index)
	if selected_index >= cap or (selected_index >= 0 and slots[selected_index].is_empty()):
		selected_index = -1
	mesos_label.text = MisoTheme.thousands(c.mesos)
	for t in tab_buttons:
		(tab_buttons[t] as Button).button_pressed = t == current_tab
	_update_actions()


## Switches the visible tab.
func select_tab(tab: String) -> void:
	if not (tab in Inventory.TABS):
		return
	if tab != current_tab:
		selected_index = -1
		key_picker.visible = false
	current_tab = tab
	_hide_tooltip()
	refresh()


## Selects a slot of the current tab (-1 = none).
func select_slot(index: int) -> void:
	selected_index = index if index >= 0 and index < slots.size() and not slots[index].is_empty() else -1
	for i in slots.size():
		slots[i].set_selected(i == selected_index)
	if selected_index < 0:
		key_picker.visible = false
	_update_actions()


## Uses (consumable) or equips (equipment) the item in a slot of the current tab. Returns the service result.
func activate_slot(index: int) -> Dictionary:
	if index < 0 or index >= slots.size() or slots[index].is_empty() or env == null:
		return {"ok": false, "code": "slot_empty"}
	var items := env.items()
	if items == null:
		return {"ok": false, "code": "unavailable"}
	var item_id := slots[index].item_id
	var def := ItemDef.of(item_id, env.get_db())
	var res: Dictionary
	if def != null and def.is_equipment():
		res = items.equip(item_id, index if current_tab == "equip" else -1)
		if res.get("ok", false):
			set_status("Equipped %s." % def.name)
	elif def != null and def.is_consumable():
		res = items.use_item(item_id)
		if res.get("ok", false):
			set_status(_use_status(def, res))
	else:
		res = ItemCodes.result(ItemCodes.NOT_USABLE, {"item_id": item_id})
	if not res.get("ok", false):
		_report(res)
	refresh()
	return res


## Binds the selected (or given) slot's consumable to a quickslot key ("1".."8"). Returns false when not allowed.
func assign_quickslot(key: String, index: int = -2) -> bool:
	var i := selected_index if index == -2 else index
	key_picker.visible = false
	if env == null or i < 0 or i >= slots.size() or slots[i].is_empty():
		return false
	var item_id := slots[i].item_id
	var ok := MisoQuickslots.bind(env, key, item_id)
	if ok:
		set_status("%s set to key %s." % [env.item_name(item_id), MisoQuickslots.key_text(key)])
	else:
		_report({"ok": false, "code": ItemCodes.NOT_USABLE, "item_id": item_id})
	return ok


## The item ids shown in the current tab, slot by slot ("" for empty slots). For tests and tools.
func visible_item_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for s in slots:
		out.append(s.item_id)
	return out


func _ensure_slot_count(n: int) -> void:
	while slots.size() > n:
		var s: MisoItemSlot = slots.pop_back()
		grid.remove_child(s)
		s.queue_free()
	while slots.size() < n:
		var s := MisoItemSlot.new(SLOT_SIZE)
		s.index = slots.size()
		s.selected.connect(func(sl: MisoItemSlot) -> void: select_slot(sl.index))
		s.activated.connect(func(sl: MisoItemSlot) -> void:
			select_slot(sl.index)
			activate_slot(sl.index))
		s.context_requested.connect(_on_context)
		s.hover_changed.connect(_on_hover)
		s.drag_source = _drag_data
		s.drop_filter = _can_drop
		s.drop_handler = _drop
		grid.add_child(s)
		slots.append(s)
	for s in slots:
		s.tab = current_tab


func _update_actions() -> void:
	if action_button == null:
		return
	var def: ItemDef = null
	if selected_index >= 0 and env != null:
		def = ItemDef.of(slots[selected_index].item_id, env.get_db())
	if def != null and def.is_equipment():
		action_button.text = "Equip"
		action_button.disabled = false
	elif def != null and def.is_consumable():
		action_button.text = "Use"
		action_button.disabled = false
	else:
		action_button.text = "Use"
		action_button.disabled = true
	key_button.disabled = def == null or not def.is_consumable()
	if key_button.disabled:
		key_picker.visible = false


func _on_context(slot: MisoItemSlot) -> void:
	select_slot(slot.index)
	if not key_button.disabled:
		key_picker.visible = true


func _on_hover(slot: MisoItemSlot, inside: bool) -> void:
	if tooltip_host == null:
		return
	if inside and not slot.is_empty():
		var def := ItemDef.of(slot.item_id, env.get_db() if env != null else null)
		var hint := ""
		if def != null and def.is_equipment():
			hint = "Double-click to equip"
		elif def != null and def.is_consumable():
			hint = "Double-click to use  ·  drag to a quickslot"
		tooltip_host.call("show_item_tooltip", slot.item_id, {"qty": slot.qty, "data": slot.data, "hint": hint}, slot)
	else:
		_hide_tooltip()


func _hide_tooltip() -> void:
	if tooltip_host != null:
		tooltip_host.call("hide_item_tooltip")


func _drag_data(slot: MisoItemSlot) -> Variant:
	_hide_tooltip()
	return {"kind": MisoQuickslots.DRAG_KIND, "source": "inventory", "tab": current_tab, "index": slot.index,
		"item_id": slot.item_id}


func _can_drop(slot: MisoItemSlot, d: Variant) -> bool:
	return d is Dictionary and d.get("kind") == MisoQuickslots.DRAG_KIND and d.get("source") == "inventory" \
		and String(d.get("tab", "")) == current_tab and int(d.get("index", -1)) != slot.index


func _drop(slot: MisoItemSlot, d: Variant) -> void:
	var items := env.items() if env != null else null
	if items == null:
		return
	if items.move(current_tab, int(d["index"]), slot.index):
		selected_index = slot.index
	refresh()


func _use_status(def: ItemDef, res: Dictionary) -> String:
	var parts: PackedStringArray = []
	if int(res.get("hp_gained", 0)) > 0:
		parts.append("+%d HP" % int(res["hp_gained"]))
	if int(res.get("mp_gained", 0)) > 0:
		parts.append("+%d MP" % int(res["mp_gained"]))
	return "Used %s%s." % [def.name, (" (" + ", ".join(parts) + ")") if not parts.is_empty() else ""]


func _report(res: Dictionary) -> void:
	var msg := MisoUiText.result_message(res, env.get_db() if env != null else null)
	set_status(msg, true)
	if env != null:
		env.notice(msg)


func _on_closed() -> void:
	key_picker.visible = false
	_hide_tooltip()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or selected_index < 0 or (env != null and env.is_modal_active()):
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		activate_slot(selected_index)
		get_viewport().set_input_as_handled()
