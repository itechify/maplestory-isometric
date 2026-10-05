class_name MapStateCache
extends RefCounted
## LRU of the most recently left maps' instance snapshots (MAP_ARCHITECTURE.md section 4.7.3). Eviction discards the
## state, so the next entry into that map gets MapInstanceState.fresh(). Monster and drop state never reaches a save.

## Spec value (section 4.7.3: "the 4 most recent non-live maps"); a structural size, not gameplay tuning.
const DEFAULT_CAPACITY := 4

var capacity: int = DEFAULT_CAPACITY
## Most recent last.
var _order: PackedStringArray = []
var _data: Dictionary = {}


func _init(p_capacity: int = DEFAULT_CAPACITY) -> void:
	capacity = maxi(p_capacity, 0)


## Parks `snapshot` for `map_id` (replacing an older one), evicting the least recently parked map past capacity.
func put(map_id: String, snapshot: Dictionary) -> void:
	if map_id == "" or snapshot.is_empty():
		return
	var at := _order.find(map_id)
	if at >= 0:
		_order.remove_at(at)
	_order.append(map_id)
	_data[map_id] = snapshot
	while _order.size() > capacity:
		_data.erase(_order[0])
		_order.remove_at(0)


## Removes and returns the snapshot for `map_id` ({} when not cached).
func take(map_id: String) -> Dictionary:
	if not _data.has(map_id):
		return {}
	var snap: Dictionary = _data[map_id]
	_data.erase(map_id)
	_order.remove_at(_order.find(map_id))
	return snap


func has(map_id: String) -> bool:
	return _data.has(map_id)


func size() -> int:
	return _order.size()


## Cached map ids, least recent first.
func keys() -> PackedStringArray:
	return _order.duplicate()


func clear() -> void:
	_order.clear()
	_data.clear()
