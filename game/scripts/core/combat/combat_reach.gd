class_name CombatReach
extends RefCounted
## Attack and touch geometry in MapleStory pixels (MeowDB /formulas/targeting, attack_styles.json).
##
## Boxes are Rect2 in px relative to the actor's feet, y down (negative y = above the feet). Attack boxes are
## published facing LEFT; mirror_box() flips them for a right-facing attacker. Overlap is strict: boxes touching at an
## edge do not hit. Consumers convert px to meters with WorldScale.actor() and add the isometric depth from
## attack_box_depth_px() / touch_zone_depth_px() (a MisoStory adaptation: MeowDB is 2D).


## A facing-left box mirrored for the attacker's facing (x -> -x, left and right swap).
static func mirror_box(box: Rect2, facing_right: bool) -> Rect2:
	if not facing_right:
		return box
	return Rect2(-box.end.x, box.position.y, box.size.x, box.size.y)


## "Hit when max(AttackLeft, MonsterLeft) < min(AttackRight, MonsterRight) and max(AttackTop, MonsterTop) <
## min(AttackBottom, MonsterBottom)": both boxes in the same space; touching edges do not count.
static func boxes_overlap(a: Rect2, b: Rect2) -> bool:
	return maxf(a.position.x, b.position.x) < minf(a.end.x, b.end.x) \
		and maxf(a.position.y, b.position.y) < minf(a.end.y, b.end.y)


## The attack box of a weapon presentation for an attacker, relative to the attacker's feet.
static func attack_box_px(weapon: WeaponProfile, presentation: String, facing_right: bool, level: int = 1) -> Rect2:
	return mirror_box(weapon.hit_box_px(presentation, level), facing_right)


## A monster's touch zone relative to its feet: canonical touch_zone_px [w, h], anchored at the bottom centre.
## MeowDB ignores artwork, so this box is also the monster's body for attack overlap.
static func monster_touch_box_px(monster: MonsterCombatStats) -> Rect2:
	var w := monster.touch_zone_px.x
	var h := monster.touch_zone_px.y
	return Rect2(-w / 2.0, -h, w, h)


## A box moved from actor-local px to a shared px space (actor feet at `origin_px`).
static func translated(box: Rect2, origin_px: Vector2) -> Rect2:
	return Rect2(box.position + origin_px, box.size)


## MisoStory isometric adaptation: total depth (px) of an attack box across the facing direction.
static func attack_box_depth_px(db: ContentDB) -> float:
	return float(CombatRules.of(db).adaptation("isometric_reach").get("attack_box_depth_px", 0.0))


## MisoStory isometric adaptation: depth (px) of a monster's touch zone (its canonical width).
static func touch_zone_depth_px(monster: MonsterCombatStats, db: ContentDB) -> float:
	var mode := String(CombatRules.of(db).adaptation("isometric_reach").get("touch_zone_depth", ""))
	if mode == "width":
		return monster.touch_zone_px.x
	push_error("[CombatReach] unknown touch_zone_depth mode '%s'" % mode)
	return monster.touch_zone_px.x


## Basic-attack target order: nearest first, a tie goes to the monster that appeared first. `candidates` are
## Dictionaries with "distance" (any unit) and "spawn_order" (int); returns at most `mob_cap` of them, sorted.
static func pick_targets(candidates: Array, mob_cap: int) -> Array:
	var sorted := candidates.duplicate()
	sorted.sort_custom(_closer_first)
	return sorted.slice(0, maxi(0, mob_cap))


static func _closer_first(a: Dictionary, b: Dictionary) -> bool:
	var da := float(a.get("distance", 0.0))
	var dbv := float(b.get("distance", 0.0))
	if da != dbv:
		return da < dbv
	return int(a.get("spawn_order", 0)) < int(b.get("spawn_order", 0))
