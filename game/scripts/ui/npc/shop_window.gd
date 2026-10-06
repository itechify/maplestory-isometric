class_name ShopWindow
extends PanelContainer
## The NPC shop window, rendered from data only: the Buy tab lists the canonical stock of data/canonical/shops/<id>.json
## in its order (ShopService.stock: price, bundle size), with the owned count, a quantity picker and a live meso
## check; the Sell tab lists the inventory tabs with each slot's canonical sell-back price (ShopService.sell_slot keeps
## the exact equipment instance). Every purchase and sale goes through ShopService, so prices, meso validation,
## inventory space and the Events (mesos_changed, item_gained, item_lost, inventory_changed, inventory_full) are the
## items system's; the window shows the result code as a message (ItemCodes.message plus the numbers).
##
## Input: mouse, or Up/Down (W/S) to pick a row, Left/Right (A/D) to change the quantity (Shift = 10), Enter to buy or
## sell, Tab to switch Buy/Sell, 1-5 for the inventory tab while selling, Esc to leave (standalone; in the game the
## shell's window stack calls close()). Modal: push_modal/pop_modal + window_opened/window_closed on the GameContext.
## Space never buys (it is the jump key and the dialogue's Next key; it is swallowed), and Enter is ignored for
## confirm_arm_s after the shop opens, so mashing Enter or Space through a shopkeeper's greeting cannot spend mesos.

signal opened(shop_id: String)
signal closed(shop_id: String)
## A buy or sell finished (ok or not) with this message.
signal result_shown(result: Dictionary, message: String)

const SIZE := Vector2(940, 600)
const TAB_LABELS := {"equip": "Equip", "use": "Use", "setup": "Set-up", "etc": "Etc", "cash": "Cash"}
const STAT_LABELS := {"watk": "Weapon ATT", "matk": "Magic ATT", "wdef": "Weapon DEF", "mdef": "Magic DEF",
	"str": "STR", "dex": "DEX", "int": "INT", "luk": "LUK", "max_hp": "Max HP", "max_mp": "Max MP",
	"acc": "Accuracy", "avoid": "Avoidability", "speed": "Speed", "jump": "Jump", "crit_rate_pct": "Critical Rate %",
	"knockback_pct": "Knockback %"}

var ctx: GameContext = null
var db: ContentDB = null
## Event bus (Events or a private events.gd); null = the Events autoload.
var bus: Object = null
## () -> CharacterState; empty = Game.character.
var character_provider: Callable = Callable()
## (npc_id) -> Node3D model for the portrait, or null.
var model_provider: Callable = Callable()
## () -> float: pixels at the bottom of the screen taken by another UI layer's bar (NpcUi.bottom_inset); empty = 0.
var bottom_inset_provider: Callable = Callable()
var handle_escape: bool = true
## Seconds after opening during which the Enter key does not buy or sell (mouse clicks are never delayed). A UI feel
## value: long enough to swallow the presses that advanced the greeting, short enough to go unnoticed.
var confirm_arm_s: float = 0.3

var shop_id: String = ""
var npc_id: String = ""
## "buy" or "sell".
var mode: String = "buy"
var sell_tab: String = "use"
## ShopService.stock rows.
var buy_rows: Array = []
## [{"tab", "index", "item_id", "qty", "price"}] of the sell tab.
var sell_rows: Array = []
var selected: int = -1
var quantity: int = 1
var last_result: Dictionary = {}
var status_text: String = ""

var visuals: LootVisuals = null
var portrait: NpcPortrait = null
var title_label: Label = null
var subtitle_label: Label = null
var tab_buttons: Dictionary = {}
var sell_tab_buttons: Dictionary = {}
var sell_tab_bar: HBoxContainer = null
var list_box: VBoxContainer = null
var list_scroll: ScrollContainer = null
var header_price: Label = null
var detail_icon: Control = null
var detail_name: Label = null
var detail_type: Label = null
var detail_desc: Label = null
var detail_stats: Label = null
var detail_price: Label = null
var detail_owned: Label = null
var qty_label: Label = null
var total_label: Label = null
var check_label: Label = null
var action_button: Button = null
var status_label: Label = null
var meso_label: Label = null

var _open := false
var _rows: Array[PanelContainer] = []
var _bus_connected: Object = null
## Frame time (process delta) since the shop opened (see confirm_arm_s).
var _open_age: float = 0.0


func _init() -> void:
	name = "ShopWindow"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


# --- open / close ----------------------------------------------------------------------------------------------

## Opens the shop (idempotent for the shop already open). False when the shop id is not canonical.
func open_shop(p_shop_id: String, p_npc_id: String = "") -> bool:
	_ensure_db()
	if db == null or not ShopService.exists(p_shop_id, db):
		push_warning("[ShopWindow] unknown shop '%s'" % p_shop_id)
		return false
	if _open and p_shop_id == shop_id:
		return true
	if _open:
		close()
	shop_id = p_shop_id
	var rec := db.shop(shop_id)
	npc_id = p_npc_id if not p_npc_id.is_empty() else String(rec.get("npc_id", ""))
	buy_rows = ShopService.stock(shop_id, db)
	mode = "buy"
	selected = 0 if not buy_rows.is_empty() else -1
	quantity = 1
	status_text = ""
	last_result = {}
	var npc_name := String(rec.get("npc_name", rec.get("name", shop_id)))
	# MeowDB has no shop title: the format is adaptation data (misostory/dialogue/_rules.json shop_window_title).
	title_label.text = NpcDialogueBuilder.shop_title(npc_name, db)
	var func_title := String(rec.get("npc_function", "")) if rec.get("npc_function") is String else ""
	var where := String(rec.get("map_display_name", rec.get("map_name", ""))) if rec.get("map_display_name") is String else ""
	var sub := PackedStringArray()
	for part in [func_title, where]:
		if not String(part).is_empty():
			sub.append(part)
	subtitle_label.text = "  ·  ".join(sub)
	var model: Node3D = null
	if model_provider.is_valid():
		var m: Variant = model_provider.call(npc_id)
		model = m if m is Node3D else null
	portrait.show_speaker(npc_id, npc_name, model)
	_connect_bus()
	_open = true
	_open_age = 0.0
	visible = true
	refresh()
	if ctx != null:
		ctx.push_modal(self)
		ctx.window_opened(self)
	_layout()
	WorldUiServices.emit(_bus(), &"shop_opened", [shop_id])
	opened.emit(shop_id)
	return true


## Leaves the shop (Exit, Esc, the window stack). Safe to call twice.
func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	var was := shop_id
	if ctx != null:
		ctx.pop_modal(self)
		ctx.window_closed(self)
	_disconnect_bus()
	WorldUiServices.emit(_bus(), &"shop_closed", [was])
	closed.emit(was)


func is_open() -> bool:
	return _open


## True once the Enter key may buy or sell (confirm_arm_s of frame time after opening).
func confirm_key_armed() -> bool:
	return _open and _open_age >= confirm_arm_s


func _process(delta: float) -> void:
	if _open:
		_open_age += delta


func _exit_tree() -> void:
	close()


# --- public handlers (buttons, keys and tests) -----------------------------------------------------------------

func set_mode(m: String) -> void:
	if m != "buy" and m != "sell":
		return
	mode = m
	selected = 0
	quantity = 1
	refresh()


func set_sell_tab(tab: String) -> void:
	if not (tab in Inventory.TABS):
		return
	sell_tab = tab
	mode = "sell"
	selected = 0
	quantity = 1
	refresh()


## Selects a row of the current list (buy: stock order; sell: the non-empty slots of the tab in slot order).
func select(index: int) -> void:
	var n := _row_count()
	selected = clampi(index, 0, n - 1) if n > 0 else -1
	quantity = 1
	refresh()


## Selects the buy row of `item_id` (switches to Buy). False if the shop does not sell it.
func select_buy_item(item_id: String) -> bool:
	for i in buy_rows.size():
		if String(buy_rows[i].item_id) == item_id:
			mode = "buy"
			select(i)
			return true
	return false


## Selects the inventory slot `tab`/`index` for selling. False if that slot is empty.
func select_sell_slot(tab: String, index: int) -> bool:
	sell_tab = tab
	mode = "sell"
	_rebuild_sell_rows()
	for i in sell_rows.size():
		if int(sell_rows[i].index) == index:
			select(i)
			return true
	return false


func set_quantity(n: int) -> void:
	quantity = clampi(n, 1, max_quantity())
	_refresh_detail()


func change_quantity(delta: int) -> void:
	set_quantity(quantity + delta)


## The largest quantity the picker allows: buy = what fits and what the mesos pay for (at least 1, so a click still
## reports why it fails); sell = the slot's quantity.
func max_quantity() -> int:
	var c := _character()
	if c == null or selected < 0:
		return 1
	if mode == "buy":
		if selected >= buy_rows.size():
			return 1
		var row: Dictionary = buy_rows[selected]
		var per := maxi(1, int(row.quantity_per_purchase))
		var room := c.inventory.room_for(String(row.item_id), db) / per
		var price := ShopService.price_for(row, c, shop_id, db)
		var afford := c.mesos / price if price > 0 else room
		return clampi(mini(room, afford), 1, 9999)
	if selected >= sell_rows.size():
		return 1
	return maxi(1, int(sell_rows[selected].qty))


## Buys or sells the selected row at the current quantity. Returns ShopService's result.
func confirm() -> Dictionary:
	if mode == "buy":
		return buy_selected()
	return sell_selected()


func buy_selected() -> Dictionary:
	var c := _character()
	if c == null or selected < 0 or selected >= buy_rows.size():
		return {"ok": false, "code": "nothing_selected"}
	var row: Dictionary = buy_rows[selected]
	var res := ShopService.buy(c, shop_id, String(row.item_id), quantity, db, _bus())
	var msg := ""
	if bool(res.get("ok", false)):
		msg = "Bought %s for %s mesos." % [_qty_name(String(row.item_id), int(res.get("units", quantity))),
			_thousands(int(res.get("cost", 0)))]
	else:
		msg = ItemCodes.message(res)
		if String(res.get("code", "")) == ItemCodes.INSUFFICIENT_MESOS:
			msg += " (costs %s, you have %s)" % [_thousands(int(res.get("cost", 0))), _thousands(c.mesos)]
	_show_result(res, msg)
	return res


func sell_selected() -> Dictionary:
	var c := _character()
	if c == null or selected < 0 or selected >= sell_rows.size():
		return {"ok": false, "code": "nothing_selected"}
	var row: Dictionary = sell_rows[selected]
	var qty := quantity
	var res := ShopService.sell_slot(c, shop_id, String(row.tab), int(row.index), qty, db, _bus())
	var msg := ""
	if bool(res.get("ok", false)):
		msg = "Sold %s for %s mesos." % [_qty_name(String(row.item_id), qty), _thousands(int(res.get("total", 0)))]
	else:
		msg = _sell_message(res)
	_show_result(res, msg)
	return res


## The message for a sale result: ItemCodes' words, or MisoUiText's for a quest item a quest still needs ("Roger's
## Apple is needed for Roger's Apple (keep 1). The shop will not buy it while the quest is in progress.") and for a
## protected item ("The Green Relaxer cannot be obtained again. The shop will not buy it.").
func _sell_message(res: Dictionary) -> String:
	if String(res.get("code", "")) in [ShopService.QUEST_ITEM_NEEDED, ShopService.PROTECTED_ITEM]:
		return MisoUiText.result_message(res, db)
	return ItemCodes.message(res)


func meso_text() -> String:
	var c := _character()
	return _thousands(c.mesos if c != null else 0)


## Owned count of an item (all tabs).
func owned(item_id: String) -> int:
	var c := _character()
	return c.inventory.count(item_id) if c != null else 0


## Handles a key. Returns true when used.
func handle_key(event: InputEventKey) -> bool:
	if not _open or not event.pressed:
		return false
	var k := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	match k:
		KEY_ESCAPE:
			if handle_escape:
				close()
				return true
			return false
		KEY_ENTER, KEY_KP_ENTER:
			if not event.echo and confirm_key_armed():
				confirm()
			return true
		KEY_SPACE:
			# Swallowed: Space advances the dialogue and jumps; it must never spend mesos here.
			return true
		KEY_UP, KEY_W:
			select(selected - 1)
			_scroll_to_selected()
			return true
		KEY_DOWN, KEY_S:
			select(selected + 1)
			_scroll_to_selected()
			return true
		KEY_LEFT, KEY_A:
			change_quantity(-10 if event.shift_pressed else -1)
			return true
		KEY_RIGHT, KEY_D:
			change_quantity(10 if event.shift_pressed else 1)
			return true
		KEY_TAB:
			if not event.echo:
				set_mode("sell" if mode == "buy" else "buy")
			return true
	if k >= KEY_1 and k <= KEY_5:
		if mode == "sell" and not event.echo:
			set_sell_tab(Inventory.TABS[k - KEY_1])
		return true
	return (k >= KEY_0 and k <= KEY_9)


func _input(event: InputEvent) -> void:
	if _open and visible and event is InputEventKey and handle_key(event as InputEventKey):
		get_viewport().set_input_as_handled()


# --- rendering -------------------------------------------------------------------------------------------------

## Rebuilds the list, the detail panel and the meso display from the live character.
func refresh() -> void:
	if not _open:
		return
	if mode == "sell":
		_rebuild_sell_rows()
	var n := _row_count()
	if n == 0:
		selected = -1
	elif selected < 0 or selected >= n:
		selected = clampi(selected, 0, n - 1)
	for m: String in tab_buttons:
		NpcUiStyle.style_button(tab_buttons[m], "primary" if m == mode else "secondary")
	sell_tab_bar.visible = mode == "sell"
	for t: String in sell_tab_buttons:
		NpcUiStyle.style_button(sell_tab_buttons[t], "primary" if t == sell_tab else "secondary")
	header_price.text = "Price" if mode == "buy" else "Sells for"
	_render_rows()
	_refresh_detail()
	meso_label.text = meso_text()


func _rebuild_sell_rows() -> void:
	sell_rows = []
	var c := _character()
	if c == null:
		return
	for i in c.inventory.capacity(sell_tab):
		var slot := c.inventory.get_slot(sell_tab, i)
		if slot.is_empty():
			continue
		var item_id := String(slot.item_id)
		sell_rows.append({"tab": sell_tab, "index": i, "item_id": item_id, "qty": int(slot.qty),
			"price": ShopService.sell_price(item_id, db)})


func _row_count() -> int:
	return buy_rows.size() if mode == "buy" else sell_rows.size()


func _render_rows() -> void:
	for r in _rows:
		list_box.remove_child(r)
		r.queue_free()
	_rows.clear()
	var data: Array = buy_rows if mode == "buy" else sell_rows
	if data.is_empty():
		var empty := NpcUiStyle.label("Nothing to sell in this tab." if mode == "sell" else "This shop sells nothing.",
			NpcUiStyle.INK_SOFT, 15)
		var holder := PanelContainer.new()
		holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		holder.add_child(empty)
		list_box.add_child(holder)
		_rows.append(holder)
		return
	for i in data.size():
		var d: Dictionary = data[i]
		var item_id := String(d.item_id)
		var row := PanelContainer.new()
		row.name = "Row_%d" % i
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var on := i == selected
		row.add_theme_stylebox_override("panel", NpcUiStyle.box(NpcUiStyle.SELECT if on else (NpcUiStyle.BODY if i % 2 == 0 else NpcUiStyle.BODY_ALT),
			Color("#d9a440") if on else Color(0, 0, 0, 0), 1, 4, 8, 4))
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 10)
		row.add_child(h)
		var icon := NpcUiStyle.item_icon(item_id, db, visuals, 30.0)
		h.add_child(icon)
		var nm := NpcUiStyle.label(_item_name(item_id), NpcUiStyle.INK, 15, true)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nm.clip_text = true
		h.add_child(nm)
		var price := int(d.price) if mode == "sell" else int(d.price)
		var price_text := "%s mesos" % _thousands(price) if price >= 0 else "—"
		if mode == "buy" and int(d.quantity_per_purchase) > 1:
			price_text += " / %d" % int(d.quantity_per_purchase)
		var pl := NpcUiStyle.label(price_text, Color("#7a5a12"), 14, true)
		pl.custom_minimum_size = Vector2(110, 0)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(pl)
		var count := owned(item_id) if mode == "buy" else int(d.qty)
		var ol := NpcUiStyle.label(("Owned %d" % count) if mode == "buy" else ("x%d" % count), NpcUiStyle.INK_SOFT, 13)
		ol.custom_minimum_size = Vector2(76, 0)
		ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(ol)
		var idx := i
		row.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
					and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				# Deferred: the click must not rebuild (free) the row while it is still handling the event.
				if (ev as InputEventMouseButton).double_click and idx == selected:
					confirm.call_deferred()
				else:
					select.call_deferred(idx))
		list_box.add_child(row)
		_rows.append(row)


func _refresh_detail() -> void:
	var c := _character()
	var has := selected >= 0 and selected < _row_count()
	for n in [detail_icon, detail_name, detail_type, detail_desc, detail_stats, detail_price, detail_owned, qty_label,
			total_label, check_label]:
		(n as Control).visible = has
	action_button.disabled = not has
	action_button.text = "Buy" if mode == "buy" else "Sell"
	if not has or c == null:
		return
	var item_id := String((buy_rows if mode == "buy" else sell_rows)[selected].item_id)
	var def := ItemDef.of(item_id, db)
	NpcUiStyle.set_icon_item(detail_icon, item_id, db, visuals)
	detail_name.text = _item_name(item_id)
	detail_type.text = ("%s / %s" % [def.type, def.subtype]) if def != null and def.subtype != "" else (def.type if def != null else "")
	detail_desc.text = def.description if def != null else ""
	detail_desc.visible = not detail_desc.text.is_empty()
	detail_stats.text = _stat_text(def)
	detail_stats.visible = not detail_stats.text.is_empty()
	quantity = clampi(quantity, 1, max_quantity())
	qty_label.text = str(quantity)
	if mode == "buy":
		var row: Dictionary = buy_rows[selected]
		var price := ShopService.price_for(row, c, shop_id, db)
		var per := maxi(1, int(row.quantity_per_purchase))
		detail_price.text = "Price: %s mesos%s" % [_thousands(price), (" for %d" % per) if per > 1 else ""]
		detail_owned.text = "You have: %d" % owned(item_id)
		var cost := price * quantity
		total_label.text = "Total: %s mesos" % _thousands(cost)
		var quote := ShopService.quote_buy(c, shop_id, item_id, quantity, db)
		var ok := bool(quote.get("ok", false))
		total_label.add_theme_color_override("font_color", NpcUiStyle.INK if ok else NpcUiStyle.RED)
		check_label.text = "" if ok else ItemCodes.message(quote)
	else:
		var srow: Dictionary = sell_rows[selected]
		var sp := int(srow.price)
		detail_price.text = ("Sells for: %s mesos each" % _thousands(sp)) if sp >= 0 else "The shop will not buy this."
		detail_owned.text = "In this slot: %d" % int(srow.qty)
		total_label.text = "Total: %s mesos" % _thousands(maxi(sp, 0) * quantity)
		var q := ShopService.quote_sell(c, shop_id, item_id, quantity, db)
		total_label.add_theme_color_override("font_color", NpcUiStyle.INK if bool(q.get("ok", false)) else NpcUiStyle.RED)
		check_label.text = "" if bool(q.get("ok", false)) else _sell_message(q)
	check_label.visible = not check_label.text.is_empty()


func _stat_text(def: ItemDef) -> String:
	if def == null:
		return ""
	var lines := PackedStringArray()
	if def.req_level > 0:
		lines.append("Req. Level %d" % def.req_level)
	for k in def.req_stats:
		if int(def.req_stats[k]) > 0:
			lines.append("Req. %s %d" % [String(k).to_upper(), int(def.req_stats[k])])
	# The canonical gender requirement, worded as MisoItemTooltip words it. Shown to every character: buying stays
	# allowed (classic sells it to anyone), Equipment refuses the equip on a mismatch.
	if def.gender != "":
		lines.append("For %s characters" % ("male" if def.gender == "male" else "female"))
	var st := def.stat_lines()
	for k: String in st:
		lines.append("%s %+d" % [STAT_LABELS.get(k, k), int(st[k])])
	if def.hp_flat > 0:
		lines.append("Recovers %d HP" % def.hp_flat)
	if def.mp_flat > 0:
		lines.append("Recovers %d MP" % def.mp_flat)
	if def.upgrade_slots > 0:
		lines.append("Upgrades available: %d" % def.upgrade_slots)
	return "\n".join(lines)


func _show_result(res: Dictionary, msg: String) -> void:
	last_result = res
	status_text = msg
	status_label.text = msg
	status_label.add_theme_color_override("font_color", NpcUiStyle.GREEN if bool(res.get("ok", false)) else NpcUiStyle.RED)
	refresh()
	result_shown.emit(res, msg)


func _scroll_to_selected() -> void:
	if selected >= 0 and selected < _rows.size() and list_scroll != null and list_scroll.is_inside_tree():
		list_scroll.ensure_control_visible(_rows[selected])


# --- collaborators ---------------------------------------------------------------------------------------------

func _ensure_db() -> void:
	if db == null:
		db = WorldUiServices.content()
	if visuals == null and db != null:
		visuals = LootVisuals.new(db)


func _character() -> CharacterState:
	if character_provider.is_valid():
		var v: Variant = character_provider.call()
		return v if v is CharacterState else null
	return WorldUiServices.character()


func _bus() -> Object:
	return bus if bus != null else WorldUiServices.events()


func _connect_bus() -> void:
	var b := _bus()
	if b == _bus_connected or b == null:
		return
	_disconnect_bus()
	for sig in ["mesos_changed", "inventory_changed"]:
		if b.has_signal(sig):
			b.connect(sig, _on_wallet_changed.unbind(2) if sig == "mesos_changed" else _on_wallet_changed)
	_bus_connected = b


func _disconnect_bus() -> void:
	if _bus_connected == null or not is_instance_valid(_bus_connected):
		_bus_connected = null
		return
	for sig in ["mesos_changed", "inventory_changed"]:
		if not _bus_connected.has_signal(sig):
			continue
		for cn: Dictionary in _bus_connected.get_signal_connection_list(sig):
			var cb: Callable = cn["callable"]
			if cb.get_object() == self:
				_bus_connected.disconnect(sig, cb)
	_bus_connected = null


func _on_wallet_changed() -> void:
	if _open:
		refresh()


func _item_name(item_id: String) -> String:
	return String(db.item(item_id).get("name", item_id)) if db != null else item_id


func _qty_name(item_id: String, qty: int) -> String:
	var n := _item_name(item_id)
	return n if qty <= 1 else "%s x%d" % [n, qty]


static func _thousands(n: int) -> String:
	return DialogueWindow._thousands(n)


# --- construction ----------------------------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_layout.call_deferred()


## Centred in the screen area above the bottom bar of other UI layers (the HUD's status bar; NpcUi.bottom_inset).
func _layout() -> void:
	if not is_inside_tree():
		return
	var area := get_parent_area_size()
	var inset := float(bottom_inset_provider.call()) if bottom_inset_provider.is_valid() else 0.0
	size = SIZE
	position = Vector2(roundf((area.x - SIZE.x) * 0.5), maxf(8.0, roundf((area.y - inset - SIZE.y) * 0.5)))


func _build() -> void:
	add_theme_stylebox_override("panel", NpcUiStyle.window_frame())
	custom_minimum_size = SIZE
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	# Header: portrait, title, close.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	portrait = NpcPortrait.new()
	portrait.custom_minimum_size = Vector2(76, 86)
	head.add_child(portrait)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(titles)
	title_label = NpcUiStyle.label("", NpcUiStyle.chrome("title"), 22, true)
	titles.add_child(title_label)
	subtitle_label = NpcUiStyle.label("", NpcUiStyle.chrome("dim"), 14)
	titles.add_child(subtitle_label)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	titles.add_child(tabs)
	for m in ["buy", "sell"]:
		var b := Button.new()
		b.text = "Buy" if m == "buy" else "Sell"
		b.custom_minimum_size = Vector2(90, 30)
		NpcUiStyle.style_button(b, "secondary")
		var mm: String = m
		b.pressed.connect(func() -> void: set_mode(mm))
		tabs.add_child(b)
		tab_buttons[m] = b
	var exit := Button.new()
	exit.text = "Exit"
	exit.custom_minimum_size = Vector2(80, 32)
	NpcUiStyle.style_button(exit, "secondary")
	exit.pressed.connect(close)
	exit.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(exit)
	sell_tab_bar = HBoxContainer.new()
	sell_tab_bar.add_theme_constant_override("separation", 4)
	root.add_child(sell_tab_bar)
	for i in Inventory.TABS.size():
		var t: String = Inventory.TABS[i]
		var tb := Button.new()
		tb.text = "%d %s" % [i + 1, TAB_LABELS.get(t, t)]
		tb.custom_minimum_size = Vector2(84, 26)
		NpcUiStyle.style_button(tb, "secondary")
		tb.add_theme_font_size_override("font_size", 13)
		tb.pressed.connect(func() -> void: set_sell_tab(t))
		sell_tab_bar.add_child(tb)
		sell_tab_buttons[t] = tb
	# Main: list + detail.
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)
	var list_panel := PanelContainer.new()
	list_panel.add_theme_stylebox_override("panel", NpcUiStyle.body_panel())
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(list_panel)
	var list_col := VBoxContainer.new()
	list_panel.add_child(list_col)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	list_col.add_child(header)
	var hn := NpcUiStyle.label("Item", NpcUiStyle.INK_SOFT, 13, true)
	hn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hn.custom_minimum_size = Vector2(40, 0)
	header.add_child(hn)
	header_price = NpcUiStyle.label("Price", NpcUiStyle.INK_SOFT, 13, true)
	header_price.custom_minimum_size = Vector2(110, 0)
	header_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(header_price)
	var ho := NpcUiStyle.label("", NpcUiStyle.INK_SOFT, 13, true)
	ho.custom_minimum_size = Vector2(76, 0)
	header.add_child(ho)
	list_scroll = ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_col.add_child(list_scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 2)
	list_scroll.add_child(list_box)
	var detail_panel := PanelContainer.new()
	detail_panel.add_theme_stylebox_override("panel", NpcUiStyle.body_panel())
	detail_panel.custom_minimum_size = Vector2(310, 0)
	main.add_child(detail_panel)
	var dcol := VBoxContainer.new()
	dcol.add_theme_constant_override("separation", 6)
	detail_panel.add_child(dcol)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	dcol.add_child(top)
	detail_icon = NpcUiStyle.item_icon("", db, visuals, 56.0)
	top.add_child(detail_icon)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	detail_name = NpcUiStyle.label("", NpcUiStyle.INK, 18, true)
	detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_name.custom_minimum_size = Vector2(200, 0)
	names.add_child(detail_name)
	detail_type = NpcUiStyle.label("", NpcUiStyle.INK_SOFT, 13)
	names.add_child(detail_type)
	detail_desc = NpcUiStyle.label("", NpcUiStyle.INK, 13)
	detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_desc.custom_minimum_size = Vector2(280, 0)
	dcol.add_child(detail_desc)
	detail_stats = NpcUiStyle.label("", Color("#2a4f8a"), 14)
	dcol.add_child(detail_stats)
	dcol.add_child(HSeparator.new())
	detail_price = NpcUiStyle.label("", Color("#7a5a12"), 15, true)
	dcol.add_child(detail_price)
	detail_owned = NpcUiStyle.label("", NpcUiStyle.INK_SOFT, 14)
	dcol.add_child(detail_owned)
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 6)
	dcol.add_child(qrow)
	qrow.add_child(NpcUiStyle.label("Quantity", NpcUiStyle.INK, 14, true))
	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(32, 30)
	NpcUiStyle.style_button(minus, "secondary")
	minus.pressed.connect(func() -> void: change_quantity(-1))
	qrow.add_child(minus)
	var qbox := PanelContainer.new()
	qbox.add_theme_stylebox_override("panel", NpcUiStyle.box(Color.WHITE, Color("#b9ab86"), 1, 4, 10, 2))
	qbox.custom_minimum_size = Vector2(64, 0)
	qrow.add_child(qbox)
	qty_label = NpcUiStyle.label("1", NpcUiStyle.INK, 16, true)
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qbox.add_child(qty_label)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(32, 30)
	NpcUiStyle.style_button(plus, "secondary")
	plus.pressed.connect(func() -> void: change_quantity(1))
	qrow.add_child(plus)
	var mx := Button.new()
	mx.text = "Max"
	mx.custom_minimum_size = Vector2(52, 30)
	NpcUiStyle.style_button(mx, "secondary")
	mx.pressed.connect(func() -> void: set_quantity(max_quantity()))
	qrow.add_child(mx)
	total_label = NpcUiStyle.label("", NpcUiStyle.INK, 16, true)
	dcol.add_child(total_label)
	check_label = NpcUiStyle.label("", NpcUiStyle.RED, 13)
	check_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	check_label.custom_minimum_size = Vector2(280, 0)
	dcol.add_child(check_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dcol.add_child(spacer)
	action_button = Button.new()
	action_button.text = "Buy"
	action_button.custom_minimum_size = Vector2(0, 40)
	NpcUiStyle.style_button(action_button, "primary")
	action_button.add_theme_font_size_override("font_size", 17)
	action_button.pressed.connect(func() -> void: confirm())
	dcol.add_child(action_button)
	# Footer: status + mesos.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	root.add_child(foot)
	status_label = NpcUiStyle.label("", NpcUiStyle.GREEN, 15, true)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(560, 0)
	var status_panel := PanelContainer.new()
	status_panel.add_theme_stylebox_override("panel", NpcUiStyle.box(Color("#f4efe0"), Color("#c9b98f"), 1, 5, 10, 4))
	status_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_panel.add_child(status_label)
	foot.add_child(status_panel)
	var wallet := PanelContainer.new()
	wallet.add_theme_stylebox_override("panel", NpcUiStyle.inset())
	foot.add_child(wallet)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 6)
	wallet.add_child(wrow)
	wrow.add_child(NpcUiStyle.coin_icon(22.0))
	meso_label = NpcUiStyle.label("0", NpcUiStyle.chrome("title"), 17, true)
	meso_label.custom_minimum_size = Vector2(110, 0)
	meso_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wrow.add_child(meso_label)
	wrow.add_child(NpcUiStyle.label("mesos", NpcUiStyle.chrome("dim"), 14))
