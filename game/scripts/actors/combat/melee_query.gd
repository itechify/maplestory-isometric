class_name MeleeQuery
extends RefCounted
## Hit boxes and touch zones in the 3D world: CombatReach's canonical 2D boxes (MeowDB /formulas/targeting,
## attack_styles.json, monsters/*.json touch_zone_px) placed in the attacker's frame. Pure geometry, no scene tree.
##
## The attacker's frame: origin at its feet, +forward = its facing (horizontal), +up, +lateral = up x forward.
## A MeowDB box is [left, top, right, bottom] px, y down, facing LEFT; CombatReach.attack_box_px(..., true, level)
## mirrors it to face +x, which here is forward. Px convert to meters with WorldScale.actor (both axes: hit boxes
## and touch zones are sizes measured against a body sprite). The third axis is the isometric adaptation
## (combat.json isometric_reach): an attack box is attack_box_depth_px deep, centred on the facing line, and a touch
## zone is as deep as it is wide. Overlap is strict on every axis, as MeowDB's rule is ("touching at an edge does not
## count").

## One candidate for a basic attack: {"node": Object, "feet": Vector3, "touch_px": Vector2 (w, h),
## "depth_px": float, "spawn_order": int}.


## A point in the attacker's frame, in px: Vector3(forward, up, lateral).
static func local_px(origin: Vector3, facing: Vector3, p: Vector3) -> Vector3:
	var f := Vector3(facing.x, 0.0, facing.z)
	f = f.normalized() if f.length_squared() > 1e-8 else Vector3.FORWARD
	var lat := Vector3.UP.cross(f)
	var rel := p - origin
	var k := WorldScale.actor(1.0)
	return Vector3(rel.dot(f) / k, rel.y / k, rel.dot(lat) / k)


## True when an attack box (px, already facing +x, y down) of total depth `depth_px` overlaps a touch zone of size
## `touch_px` (w, h) and depth `touch_depth_px` whose feet are at `rel_px` = local_px(...) of the target.
static func attack_hits(box_px: Rect2, depth_px: float, rel_px: Vector3, touch_px: Vector2, touch_depth_px: float) -> bool:
	if box_px.size == Vector2.ZERO:
		return false
	var target := Rect2(rel_px.x - touch_px.x * 0.5, -rel_px.y - touch_px.y, touch_px.x, touch_px.y)
	if not CombatReach.boxes_overlap(box_px, target):
		return false
	return maxf(-depth_px * 0.5, rel_px.z - touch_depth_px * 0.5) < minf(depth_px * 0.5, rel_px.z + touch_depth_px * 0.5)


## The candidates a basic attack hits, nearest first (horizontal distance; a tie goes to the lower spawn_order),
## at most `mob_cap` of them (CombatReach.pick_targets: classic basic attacks hit 1).
static func pick(origin: Vector3, facing: Vector3, box_px: Rect2, depth_px: float, candidates: Array,
		mob_cap: int = 1) -> Array:
	var hits: Array = []
	for c: Dictionary in candidates:
		var rel := local_px(origin, facing, c["feet"])
		if not attack_hits(box_px, depth_px, rel, c["touch_px"], float(c["depth_px"])):
			continue
		var entry := c.duplicate()
		entry["distance"] = Vector2(rel.x, rel.z).length()
		entry["rel_px"] = rel
		hits.append(entry)
	return CombatReach.pick_targets(hits, mob_cap)


## True when a monster's touch zone (size_m: width, height, depth; feet at `mob_feet`, facing `mob_facing`) overlaps
## the player's body, an upright capsule of `radius` and `height` standing at `player_feet`. Strict, like MeowDB's
## overlap rule.
static func touch_overlaps(mob_feet: Vector3, mob_facing: Vector3, size_m: Vector3, player_feet: Vector3,
		radius: float, height: float) -> bool:
	var up := player_feet.y - mob_feet.y
	if not (up < size_m.y and up + height > 0.0):
		return false
	var f := Vector3(mob_facing.x, 0.0, mob_facing.z)
	f = f.normalized() if f.length_squared() > 1e-8 else Vector3.FORWARD
	var lat := Vector3.UP.cross(f)
	var rel := player_feet - mob_feet
	var p := Vector2(rel.dot(f), rel.dot(lat))
	var half := Vector2(size_m.x, size_m.z) * 0.5
	var closest := Vector2(clampf(p.x, -half.x, half.x), clampf(p.y, -half.y, half.y))
	return p.distance_to(closest) < radius
