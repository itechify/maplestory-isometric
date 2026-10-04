class_name LootPickupRules
extends RefCounted
## Pure rules for drops on the ground: the canonical pickup box in 3D, which drop the pickup key takes, where the
## drops of one kill land, the notice text and the ground-record helpers. No scene tree; LootSystem and the
## InteractionSystem prompt use the same functions, so the prompt always names the drop the key would take.
##
## Pickup box (formulas/loot_rules.json player_pickup_box_px, through DropRates.pickup_box_m = WorldScale.actor):
## MeowDB's box is 25 px left/right of the character and 60 px above to 30 px below. The isometric ground has a depth
## axis the 2D box lacks, so left/right become a horizontal radius around the feet (max of the two, they are equal)
## and above/below stay vertical, measured from the feet.

## Key a ground record carries so the loot system can name it in its MapInstanceState (find_drop / remove_drop).
const UID_KEY := MapInstanceState.DROP_UID_KEY
const POS_KEY := "pos_local"


## True when a drop at `drop_pos` lies inside the pickup box of a player whose feet are at `feet`.
static func in_pickup_box(feet: Vector3, drop_pos: Vector3, box_m: Dictionary) -> bool:
	var dy := drop_pos.y - feet.y
	if dy > float(box_m.get("above", 0.0)) or dy < -float(box_m.get("below", 0.0)):
		return false
	var radius := maxf(float(box_m.get("left", 0.0)), float(box_m.get("right", 0.0)))
	return Vector2(drop_pos.x - feet.x, drop_pos.z - feet.z).length() <= radius


## The candidate the pickup key takes: the nearest (horizontally) of `candidates` inside the box.
## candidates: [{"uid", "position": Vector3, ...}]. Returns the candidate or {}.
static func pick_target(feet: Vector3, candidates: Array, box_m: Dictionary) -> Dictionary:
	var best := {}
	var best_d := INF
	for c: Variant in candidates:
		if not (c is Dictionary):
			continue
		var d: Dictionary = c
		var pos: Variant = d.get("position")
		if not (pos is Vector3) or not in_pickup_box(feet, pos, box_m):
			continue
		var dist := Vector2((pos as Vector3).x - feet.x, (pos as Vector3).z - feet.z).length()
		if dist < best_d:
			best_d = dist
			best = d
	return best


## Landing points of a kill's ground records: the kill point plus each record's offset_m (DropRoller scatter:
## 0, +s, -s, +2s, ...) along `ground_axis` (the camera's ground-projected right axis, so drops spread across the
## screen as in classic). The y stays the kill point's; the caller grounds them.
static func scatter_points(origin: Vector3, records: Array, ground_axis: Vector3) -> Array[Vector3]:
	var axis := Vector3(ground_axis.x, 0.0, ground_axis.z)
	axis = axis.normalized() if axis.length_squared() > 0.000001 else Vector3.RIGHT
	var out: Array[Vector3] = []
	for r: Variant in records:
		var off := float((r as Dictionary).get("offset_m", 0.0)) if r is Dictionary else 0.0
		out.append(origin + axis * off)
	return out


## The notice for a successful pickup (ItemService.pickup result): "You have gained an item (Snail Shell)",
## "You have gained an item (Red Potion x3)" or "You have gained mesos (+1,500)". Word for word the HUD's own
## item_gained / mesos_changed lines (MisoUiText), so the HUD log, which drops a line repeating the previous one,
## shows a pickup once.
static func pickup_notice(result: Dictionary, db: ContentDB) -> String:
	if String(result.get("kind", "")) == "mesos":
		return "You have gained mesos (+%s)" % thousands(int(result.get("amount", 0)))
	var item_id := ItemDef.id_of(result.get("item_id", ""))
	var item_name := String(db.item(item_id).get("name", item_id)) if db != null else item_id
	var qty := int(result.get("qty", 1))
	return "You have gained an item (%s)" % (item_name if qty <= 1 else "%s x%d" % [item_name, qty])


## The notice for a refused pickup: the ItemCodes message ("Your inventory is full.", "You cannot hold any more
## mesos."). A full inventory is also announced by ItemService (Events.inventory_full), which the HUD logs with this
## same sentence, so the two collapse into one line.
static func refusal_notice(result: Dictionary, _db: ContentDB = null) -> String:
	return ItemCodes.message(result)


## "1,500" (the HUD's number format).
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Display label of a ground record: "Snail Shell", "Red Potion x3", "1,500 mesos".
static func drop_label(record: Dictionary, db: ContentDB) -> String:
	if ItemService.is_meso_drop(record):
		return "%s mesos" % thousands(ItemService.quantity_of(record.get("amount", record.get("mesos", 0))))
	var item_id := ItemDef.id_of(record.get("item_id", ""))
	var item_name := String(db.item(item_id).get("name", item_id)) if db != null else item_id
	var qty := ItemService.quantity_of(record.get("amount", record.get("qty", 1)))
	return item_name if qty <= 1 else "%s x%d" % [item_name, qty]


## pos_local of a record as a Vector3 (stored as [x, y, z] so map snapshots stay plain data; Vector3 also read).
static func local_pos(record: Dictionary) -> Vector3:
	var p: Variant = record.get(POS_KEY)
	if p is Vector3:
		return p
	if p is Array and (p as Array).size() >= 3:
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
	return Vector3.ZERO


static func encode_pos(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## Seconds left on the ground at `now` (0 when expired; INF for a record without expires_at).
static func time_left(record: Dictionary, now: float) -> float:
	if not record.has("expires_at"):
		return INF
	return maxf(0.0, float(record["expires_at"]) - now)
