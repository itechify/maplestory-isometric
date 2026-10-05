class_name SkillTargeting
extends RefCounted
## The stepped forward search of a projectile skill (Three Snails), MeowDB /formulas/targeting and the skill page:
## bands 20 px long starting `start_px` ahead (50 px for Three Snails) out to the skill's reach (300 px); the band
## that starts d px ahead is centred `aim_px` (28 px) above the feet with a half-height of floor(d / 4), so the last
## band reaches 100 px up and 44 px down. A monster qualifies when its body (canonical touch box) overlaps a band; the
## nearest qualifying monster is the target ("Projectile skills: Nearest monsters first", attack_styles.json).
##
## Bands are Rect2 in px relative to the caster's feet, facing +x (forward), y down, exactly like CombatReach attack
## boxes, and they are placed in the 3D world by MeleeQuery (WorldScale.actor, the isometric attack depth across the
## facing from combat.json isometric_reach). Pure geometry, no scene tree.


## The search bands of a SkillDef band ({"start_px", "reach_px", "band_px", "aim_px", "divisor"}), nearest first.
static func bands_px(band: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var start := float(band.get("start_px", 0.0))
	var reach := float(band.get("reach_px", 0.0))
	var step := float(band.get("band_px", 0.0))
	var aim := float(band.get("aim_px", 0.0))
	var divisor := float(band.get("divisor", 0.0))
	if step <= 0.0 or divisor <= 0.0 or reach <= start:
		return out
	var d := start
	while d < reach:
		var half := floorf(d / divisor)
		out.append(Rect2(d, -aim - half, minf(step, reach - d), 2.0 * half))
		d += step
	return out


## The union of the bands' vertical extent: {"up_px", "down_px"} above / below the feet (Three Snails: 100 / 44).
static func vertical_extent_px(bands: Array[Rect2]) -> Dictionary:
	var up := 0.0
	var down := 0.0
	for b in bands:
		up = maxf(up, -b.position.y)
		down = maxf(down, b.end.y)
	return {"up_px": up, "down_px": down}


## The candidates (MeleeQuery candidate dictionaries: node, feet, touch_px, depth_px, spawn_order) whose bodies overlap
## any band, nearest first (horizontal distance, ties to the lower spawn_order), at most `cap` of them. Each returned
## entry gains "distance" (px) and "rel_px".
static func pick(origin: Vector3, facing: Vector3, bands: Array[Rect2], depth_px: float, candidates: Array,
		cap: int = 1) -> Array:
	var hits: Array = []
	for c: Dictionary in candidates:
		var rel := MeleeQuery.local_px(origin, facing, c["feet"])
		var touched := false
		for b in bands:
			if MeleeQuery.attack_hits(b, depth_px, rel, c["touch_px"], float(c["depth_px"])):
				touched = true
				break
		if not touched:
			continue
		var entry := c.duplicate()
		entry["distance"] = Vector2(rel.x, rel.z).length()
		entry["rel_px"] = rel
		hits.append(entry)
	return CombatReach.pick_targets(hits, cap)
