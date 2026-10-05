class_name Inventory
extends RefCounted
## Classic five-tab inventory: Equip, Use, Setup, Etc, Cash. CONTRACT: the class name, TABS and the signatures of
## count / can_add / add / remove / can_add_all / to_dict / from_dict are fixed (other systems call them).
##
## Items are referenced by canonical MeowDB item id; an item's tab comes from its canonical inventory_tab and its
## stack size from its canonical max_stack (equipment: 1, an adaptation in data/misostory/inventory.json). Each tab
## is a fixed row of slots; a slot is empty or holds {"item_id", "qty", "data"}, where "data" is per-instance state
## (empty for clean items; future scroll results on equipment). Stacks only merge when both have empty data.
##
## Pure: no signals, no scene tree. ItemService wraps it and emits the Events item signals.

const TABS: PackedStringArray = ["equip", "use", "setup", "etc", "cash"]
const SAVE_VERSION := 1

## tab -> Array of slots (null = empty, else {"item_id": String, "qty": int, "data": Dictionary}).
var _tabs: Dictionary = {}


func _init() -> void:
	var caps := ItemsConfig.tab_slots()
	for tab in TABS:
		var row: Array = []
		row.resize(int(caps.get(tab, 0)))
		_tabs[tab] = row


# --- the fixed contract ---------------------------------------------------------------------------------------

## Total quantity of an item across all slots.
func count(item_id: String) -> int:
	var total := 0
	for tab in TABS:
		for s in _tabs[tab]:
			if s != null and s.item_id == item_id:
				total += int(s.qty)
	return total


## True if `qty` of the item fits (respecting stacking and free slots). Unknown items and negative quantities never fit.
func can_add(item_id: String, qty: int, db: ContentDB) -> bool:
	if qty < 0:
		return false
	var def := ItemDef.of(item_id, db)
	if def == null or not _tabs.has(def.tab):
		return false
	return qty <= _room_for(def)


## Adds up to `qty`; returns how many were actually added (0 when the tab is full). Tops up existing stacks first,
## then fills empty slots in order.
func add(item_id: String, qty: int, db: ContentDB) -> int:
	if qty <= 0:
		return 0
	var def := ItemDef.of(item_id, db)
	if def == null or not _tabs.has(def.tab):
		return 0
	var row: Array = _tabs[def.tab]
	var left := qty
	for s in row:
		if left == 0:
			break
		if s != null and s.item_id == item_id and (s.data as Dictionary).is_empty() and int(s.qty) < def.max_stack:
			var put := mini(left, def.max_stack - int(s.qty))
			s.qty = int(s.qty) + put
			left -= put
	for i in row.size():
		if left == 0:
			break
		if row[i] == null:
			var put := mini(left, def.max_stack)
			row[i] = {"item_id": item_id, "qty": put, "data": {}}
			left -= put
	return qty - left


## Removes up to `qty`; returns how many were actually removed. Takes from the last slots first, and from clean
## stacks (empty data) before stacks that carry per-instance data.
func remove(item_id: String, qty: int) -> int:
	if qty <= 0:
		return 0
	var left := qty
	for pass_clean in [true, false]:
		for tab in TABS:
			var row: Array = _tabs[tab]
			for i in range(row.size() - 1, -1, -1):
				if left == 0:
					return qty
				var s: Variant = row[i]
				if s == null or s.item_id != item_id or (s.data as Dictionary).is_empty() != pass_clean:
					continue
				var take := mini(left, int(s.qty))
				s.qty = int(s.qty) - take
				left -= take
				if int(s.qty) <= 0:
					row[i] = null
	return qty - left


## True if every {item_id, qty} in `items` fits at once (used before quest rewards and shop purchases). Each entry may
## name its quantity "qty", "count" or "quantity" (quest reward JSON uses "count").
func can_add_all(items: Array, db: ContentDB) -> bool:
	var sim := Inventory.from_dict(to_dict())
	for e in items:
		if not (e is Dictionary):
			return false
		var item_id := ItemDef.id_of(e.get("item_id", ""))
		var qty := entry_qty(e)
		if qty < 0 or sim.add(item_id, qty, db) != qty:
			return false
	return true


## Lossless snapshot: capacities plus every occupied slot with its index, quantity and per-instance data.
func to_dict() -> Dictionary:
	var caps := {}
	var slots := {}
	for tab in TABS:
		var row: Array = _tabs[tab]
		caps[tab] = row.size()
		var list: Array = []
		for i in row.size():
			var s: Variant = row[i]
			if s == null:
				continue
			var e := {"index": i, "item_id": s.item_id, "qty": int(s.qty)}
			if not (s.data as Dictionary).is_empty():
				e["data"] = (s.data as Dictionary).duplicate(true)
			list.append(e)
		slots[tab] = list
	return {"version": SAVE_VERSION, "capacity": caps, "slots": slots}


## Restores a snapshot (missing keys fall back to defaults; JSON floats and numeric ids are converted). Never drops a
## valid item: a slot index past the saved capacity grows the tab. Entries that cannot be an item (no id, qty <= 0, a
## tab outside TABS) are skipped with a warning, since only a corrupt or hand-edited save contains them.
static func from_dict(d: Dictionary) -> Inventory:
	var inv := Inventory.new()
	var caps: Dictionary = d.get("capacity", {}) if d.get("capacity") is Dictionary else {}
	var slots: Dictionary = d.get("slots", {}) if d.get("slots") is Dictionary else {}
	for tab in slots:
		if not (str(tab) in TABS):
			push_warning("[Inventory] save has unknown tab '%s'; its slots are ignored" % str(tab))
	for tab in TABS:
		if caps.has(tab):
			(inv._tabs[tab] as Array).resize(maxi(0, _whole(caps[tab], (inv._tabs[tab] as Array).size())))
		var list: Variant = slots.get(tab, [])
		if not (list is Array):
			continue
		for e in list:
			if not (e is Dictionary):
				continue
			var qty := _whole(e.get("qty", 0), 0)
			var item_id := ItemDef.id_of(e.get("item_id", ""))
			if qty <= 0 or item_id == "":
				push_warning("[Inventory] skipping invalid saved slot in '%s': %s" % [tab, str(e)])
				continue
			var data: Dictionary = normalize_data(e.get("data", {}))
			var row: Array = inv._tabs[tab]
			var idx := _whole(e.get("index", -1), -1)
			if idx < 0 or (idx < row.size() and row[idx] != null):
				idx = inv.first_empty(tab)
				if idx < 0:
					idx = row.size()
			if idx >= row.size():
				row.resize(idx + 1)
			row[idx] = {"item_id": item_id, "qty": qty, "data": data}
	return inv


## A saved count or index as an int: a number (JSON's floats included) or numeric text, else `fallback`, so a
## hand-edited container or null there never aborts the load (int() of a container is a script error).
static func _whole(v: Variant, fallback: int) -> int:
	match typeof(v):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return int(v) if is_finite(float(v)) else fallback
		TYPE_STRING, TYPE_STRING_NAME:
			return int(String(v)) if String(v).is_valid_int() else fallback
	return fallback

# --- queries --------------------------------------------------------------------------------------------------

## Number of slots in a tab.
func capacity(tab: String) -> int:
	return (_tabs[tab] as Array).size() if _tabs.has(tab) else 0


## Changes a tab's slot count. Growing always works; shrinking fails if a removed slot holds an item.
func set_capacity(tab: String, slots_count: int) -> bool:
	if not _tabs.has(tab) or slots_count < 0:
		return false
	var row: Array = _tabs[tab]
	for i in range(slots_count, row.size()):
		if row[i] != null:
			return false
	row.resize(slots_count)
	return true


func free_slots(tab: String) -> int:
	var n := 0
	for s in _tabs.get(tab, []):
		if s == null:
			n += 1
	return n


func is_full(tab: String) -> bool:
	return free_slots(tab) == 0


## Index of the first empty slot in a tab, or -1.
func first_empty(tab: String) -> int:
	var row: Array = _tabs.get(tab, [])
	for i in row.size():
		if row[i] == null:
			return i
	return -1


## A copy of one slot: {"item_id", "qty", "data"}, or {} when empty or out of range.
func get_slot(tab: String, index: int) -> Dictionary:
	var row: Array = _tabs.get(tab, [])
	if index < 0 or index >= row.size() or row[index] == null:
		return {}
	return (row[index] as Dictionary).duplicate(true)


## Copies of every slot of a tab, in order ({} for empty slots). For the inventory window.
func slots(tab: String) -> Array:
	var out: Array = []
	for i in capacity(tab):
		out.append(get_slot(tab, i))
	return out


## First slot holding the item: {"tab", "index"}, or {} if none.
func find(item_id: String) -> Dictionary:
	for tab in TABS:
		var row: Array = _tabs[tab]
		for i in row.size():
			if row[i] != null and row[i].item_id == item_id:
				return {"tab": tab, "index": i}
	return {}


## Every distinct item id held, sorted.
func item_ids() -> PackedStringArray:
	var seen := {}
	for tab in TABS:
		for s in _tabs[tab]:
			if s != null:
				seen[s.item_id] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


func is_empty() -> bool:
	for tab in TABS:
		for s in _tabs[tab]:
			if s != null:
				return false
	return true


## Empties every slot of one tab, or of every tab when `tab` is "" (capacities are kept). Returns what was removed as
## {item_id: qty} (the debug console's "clear inventory"; ItemService.clear_inventory emits the signals).
func clear(tab: String = "") -> Dictionary:
	var removed := {}
	for t in TABS:
		if tab != "" and t != tab:
			continue
		var row: Array = _tabs[t]
		for i in row.size():
			if row[i] != null:
				removed[row[i].item_id] = int(removed.get(row[i].item_id, 0)) + int(row[i].qty)
				row[i] = null
	return removed


## How many more of this item fit right now.
func room_for(item_id: String, db: ContentDB) -> int:
	var def := ItemDef.of(item_id, db)
	if def == null or not _tabs.has(def.tab):
		return 0
	return _room_for(def)


# --- slot-level operations (equipment, selling a chosen slot, the inventory window) ----------------------------

## Removes up to `qty` from one slot (all of it when qty < 0). Returns the removed part as
## {"item_id", "qty", "data"}, or {} when the slot is empty.
func remove_at(tab: String, index: int, qty: int = -1) -> Dictionary:
	var row: Array = _tabs.get(tab, [])
	if index < 0 or index >= row.size() or row[index] == null:
		return {}
	var s: Dictionary = row[index]
	var take := int(s.qty) if qty < 0 else mini(qty, int(s.qty))
	if take <= 0:
		return {}
	var out := {"item_id": s.item_id, "qty": take, "data": (s.data as Dictionary).duplicate(true)}
	s.qty = int(s.qty) - take
	if int(s.qty) <= 0:
		row[index] = null
	return out


## Puts a whole stack ({"item_id", "qty", "data"?}) into an empty slot. False if the slot is taken or out of range.
func put_at(tab: String, index: int, stack: Dictionary) -> bool:
	var row: Array = _tabs.get(tab, [])
	if index < 0 or index >= row.size() or row[index] != null:
		return false
	var qty := int(stack.get("qty", 0))
	var item_id := ItemDef.id_of(stack.get("item_id", ""))
	if qty <= 0 or item_id == "":
		return false
	var data: Dictionary = (stack.get("data", {}) as Dictionary).duplicate(true) if stack.get("data") is Dictionary else {}
	row[index] = {"item_id": item_id, "qty": qty, "data": data}
	return true


## Adds one item instance with its per-instance data into the first empty slot of its tab. Returns the slot index, or
## -1 when the tab is full or the item unknown.
func add_instance(item_id: String, data: Dictionary, db: ContentDB) -> int:
	var def := ItemDef.of(item_id, db)
	if def == null or not _tabs.has(def.tab):
		return -1
	var idx := first_empty(def.tab)
	if idx < 0:
		return -1
	put_at(def.tab, idx, {"item_id": item_id, "qty": 1, "data": data})
	return idx


## Moves a stack between two slots of one tab. Into an empty slot it moves; onto the same clean stackable item it
## merges up to the stack size (needs `db`; the rest stays behind); otherwise the two slots swap.
func move(tab: String, from_index: int, to_index: int, db: ContentDB = null) -> bool:
	var row: Array = _tabs.get(tab, [])
	if from_index < 0 or to_index < 0 or from_index >= row.size() or to_index >= row.size():
		return false
	if row[from_index] == null:
		return false
	if from_index == to_index:
		return true
	var a: Dictionary = row[from_index]
	var b: Variant = row[to_index]
	if b == null:
		row[to_index] = a
		row[from_index] = null
		return true
	if db != null and b.item_id == a.item_id and (a.data as Dictionary).is_empty() and (b.data as Dictionary).is_empty():
		var def := ItemDef.of(String(a.item_id), db)
		if def != null and def.max_stack > 1:
			var put := mini(int(a.qty), def.max_stack - int(b.qty))
			if put > 0:
				b.qty = int(b.qty) + put
				a.qty = int(a.qty) - put
				if int(a.qty) <= 0:
					row[from_index] = null
				return true
	return swap(tab, from_index, to_index)


## Swaps two slots of one tab (either may be empty).
func swap(tab: String, a: int, b: int) -> bool:
	var row: Array = _tabs.get(tab, [])
	if a < 0 or b < 0 or a >= row.size() or b >= row.size():
		return false
	var tmp: Variant = row[a]
	row[a] = row[b]
	row[b] = tmp
	return true


## A deep copy of per-instance data with whole-number floats turned back into ints, so data that went through a JSON
## save comes back equal (JSON has one number type). Non-dictionaries give {}.
static func normalize_data(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	return _normalize(v)


static func _normalize(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _normalize(v[k])
		return out
	if v is Array:
		var arr: Array = []
		for x in v:
			arr.append(_normalize(x))
		return arr
	if typeof(v) == TYPE_FLOAT and is_finite(v) and float(v) == floorf(v) and absf(v) < 9.0e15:
		return int(v)
	return v


## The quantity of a {item_id, qty|count|quantity} entry.
static func entry_qty(e: Dictionary) -> int:
	for k in ["qty", "count", "quantity"]:
		if e.has(k):
			return int(e[k])
	return 1


func _room_for(def: ItemDef) -> int:
	var room := 0
	for s in _tabs[def.tab]:
		if s == null:
			room += def.max_stack
		elif s.item_id == def.id and (s.data as Dictionary).is_empty():
			room += maxi(0, def.max_stack - int(s.qty))
	return room
