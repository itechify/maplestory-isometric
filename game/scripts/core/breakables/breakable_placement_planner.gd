class_name BreakablePlacementPlanner
extends RefCounted
## Places a map's breakables in 3D (contract C8), the way SpawnSlotPlanner places monster spawn slots (and with its
## public machinery: the mob region, the spawn keep-outs, the GroundQuery). Pure: it only talks to a GroundQuery, so
## the world answers with PhysicsGroundQuery and L0 tests with the flat base class.
##
## Canonical (MeowDB): which placements exist and their order (maps/<id>.json reactors[], the placement index), the
## breakable id and respawn_s. MeowDB's x_px/y_px are 2D side-view coordinates and are not used (as for spawns).
## Adaptation (data/misostory/breakables.json placement, verified: false):
##   1. candidates are sampled inside the map's exported spawn areas clipped to its mob region (any species; first on
##      the area's own tier, then on any walkable top surface), and, for maps without areas (towns, interiors) or a
##      placement the areas cannot hold, inside the "floor": the mob region plus the region extensions (each inset
##      by spawns.mob_region_inset_m), first on the map's base floor tier (base_y within tier_tolerance_m), then on any
##      walkable top surface;
##   2. each placement samples with a RandomNumberGenerator seeded by hash("<map_id>:box:<index>"), placements in
##      index order, so a map always gets the same boxes;
##   3. a candidate passes when the topmost surface is walkable, the clearance capsule (clearance_radius_m x
##      clearance_height_m, lifted grounding.capsule_lift_m like the grounding probe) is clear of walls, it lies
##      outside every spawn keep-out and portal trigger, at least portal_clearance_m from every portal anchor and
##      arrival and player_spawns[0], min_spacing_m from the other boxes, spawn_slot_clearance_m from every monster
##      spawn slot and npc_clearance_m outside every NPC's talk zone (WorldTuning.talk_zone), and at least
##      approach_min_free of approach_directions points approach_m around it are grounded on its tier with the
##      player's grounding capsule clear (a walking player can stand beside it and swing);
##   4. of the first candidates_per_box candidates that pass, the one farthest from the boxes already placed is kept.
## A placement where nothing passes within `attempts` samples per pass is "unplaced" (not grounded) and logged.

## The keys breakables.json placement must hold (numbers >= 0).
const CONFIG_KEYS := ["attempts", "candidates_per_box", "tier_tolerance_m", "clearance_radius_m", "clearance_height_m",
	"min_spacing_m", "portal_clearance_m", "spawn_slot_clearance_m", "npc_clearance_m", "approach_m",
	"approach_directions", "approach_min_free"]
const REGION_FLOOR := "floor"


## Plans every breakable placement of `def` (its canonical reactors[]). `def` should be grounded already
## (MapDefinitions.ground_all: portals, NPCs and spawn slots stand where the player sees them). Returns
## {"placements": Array[BreakablePlacement] (index order), "warnings": PackedStringArray}.
static func plan(def: MapDefinition, q: GroundQuery, tuning: WorldTuning, db: ContentDB) -> Dictionary:
	var placements: Array[BreakablePlacement] = []
	var warnings: PackedStringArray = []
	var specs := BreakableRules.placements_of(def.canonical)
	if specs.is_empty():
		return {"placements": placements, "warnings": warnings}
	var cfg := config(db, warnings)
	var ctx := _context(def, tuning, cfg, warnings) if not cfg.is_empty() else {}
	var placed: Array[Vector3] = []
	for spec in specs:
		var b := BreakablePlacement.new()
		b.map_id = def.map_id
		b.index = int(spec.index)
		b.breakable_id = String(spec.id)
		b.respawn_s = float(spec.respawn_s)
		placements.append(b)
		if ctx.is_empty():
			warnings.append("%s box %d: not placed (no placement rules)" % [def.map_id, b.index])
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s:box:%d" % [def.map_id, b.index])
		var found := {}
		if not (ctx.areas as Dictionary).is_empty():
			found = _search(ctx.areas, true, q, ctx, placed, rng)
			if found.is_empty():
				found = _search(ctx.areas, false, q, ctx, placed, rng)
		if found.is_empty() and not (ctx.floor as Dictionary).is_empty():
			found = _search(ctx.floor, true, q, ctx, placed, rng)
			if found.is_empty():
				found = _search(ctx.floor, false, q, ctx, placed, rng)
		var yaw := rng.randf_range(-PI, PI)
		if found.is_empty():
			var c := def.player_spawn(0).origin
			b.transform = Transform3D(Basis(Vector3.UP, yaw), c)
			b.placement = BreakablePlacement.UNPLACED
			warnings.append("%s box %d: no walkable, clear point found" % [def.map_id, b.index])
			continue
		b.transform = Transform3D(Basis(Vector3.UP, yaw), found.p)
		b.region = String(found.region)
		b.placement = String(found.placement)
		b.grounded = true
		placed.append(b.position())
	return {"placements": placements, "warnings": warnings}


## breakables.json placement as numbers, or {} (and one warning per problem) when a key is missing or malformed.
static func config(db: ContentDB, problems: PackedStringArray = PackedStringArray()) -> Dictionary:
	var sec := BreakableRules.section(db, "placement")
	var out := {}
	var bad: PackedStringArray = []
	for k: String in CONFIG_KEYS:
		var v: Variant = sec.get(k, null)
		if (v is int or v is float) and float(v) >= 0.0:
			out[k] = float(v)
		else:
			bad.append(k)
	if not bad.is_empty():
		problems.append("misostory/breakables.json placement: missing or negative %s" % ", ".join(bad))
		return {}
	return out


## Everything a candidate is checked against, gathered once per map.
static func _context(def: MapDefinition, tuning: WorldTuning, cfg: Dictionary, warnings: PackedStringArray) -> Dictionary:
	var problems: Array = []
	var keepouts := SpawnSlotPlanner.keepouts_of(def, tuning, problems)
	for p in problems:
		warnings.append(String(p))
	var portal_points: Array[Vector3] = []
	var triggers: Array[PortalDef] = []
	for p in def.portals:
		if p.is_canonical() or p.portal_type == PortalDef.TYPE_ARRIVAL:
			portal_points.append(p.spawn_transform.origin)
		if p.has_anchor:
			portal_points.append(p.anchor_ground if p.anchor_ground != Vector3.ZERO else p.anchor_transform.origin)
			if p.is_canonical():
				triggers.append(p)
	if not def.player_spawns.is_empty():
		portal_points.append(def.player_spawns[0].origin)
	var npcs: Array[Dictionary] = []
	for n in def.npc_definitions:
		var zone := tuning.talk_zone(n.npc_id)
		npcs.append({"p": n.transform.origin, "r": float(zone.radius_m) + float(cfg.npc_clearance_m), "name": n.npc_name})
	var slots: Array[Vector3] = []
	for s in def.monster_spawn_definitions:
		if s.grounded:
			slots.append(s.position())
	var ctx := {
		"def": def, "cfg": cfg, "keepouts": keepouts, "portal_points": portal_points, "triggers": triggers,
		"npcs": npcs, "slots": slots,
		"y_top": def.y_max + tuning.num("grounding", "probe_up_m"),
		"y_bottom": def.y_min - tuning.num("grounding", "probe_down_m"),
		"probe_up": tuning.num("grounding", "probe_up_m"), "probe_down": tuning.num("grounding", "probe_down_m"),
		"lift": tuning.num("grounding", "capsule_lift_m"),
		"body_radius": tuning.num("grounding", "capsule_radius_m"), "body_height": tuning.num("grounding", "capsule_height_m"),
		"areas": _areas(def, tuning, cfg), "floor": _floor(def, tuning, cfg),
	}
	return ctx


## One sampling pool over the map's exported spawn areas clipped to its mob region (any species): {"pieces",
## "weights" (m^2), "tiers" (per piece: {"name", "surface_y", "y_lo", "y_hi"})}; {} without areas. Areas too small
## for one box are left out.
static func _areas(def: MapDefinition, tuning: WorldTuning, cfg: Dictionary) -> Dictionary:
	var pool := {"pieces": [], "weights": [] as Array[float], "tiers": [], "floor": false}
	var region := SpawnSlotPlanner.mob_region(def, tuning)
	var min_room := pow(2.0 * float(cfg.clearance_radius_m), 2.0)
	for a in def.spawn_areas:
		var poly: PackedVector2Array = a.get("polygon", PackedVector2Array())
		if poly.size() < 3:
			continue
		var pieces: Array = [poly]
		if region.size() >= 3:
			pieces = Geometry2D.intersect_polygons(poly, region)
		var tier := {"name": String(a.get("name", "")), "surface_y": float(a.get("surface_y", def.base_y)),
			"y_lo": float(a.get("y_lo", NAN)), "y_hi": float(a.get("y_hi", NAN))}
		for piece: PackedVector2Array in pieces:
			var w := absf(_polygon_area(piece))
			if w >= min_room:
				(pool.pieces as Array).append(piece)
				(pool.weights as Array[float]).append(w)
				(pool.tiers as Array).append(tier)
	return pool if not (pool.pieces as Array).is_empty() else {}


## The fallback floor pool: the mob region plus every region extension inset the same way, all on the map's base
## floor tier (base_y); {} without a footprint.
static func _floor(def: MapDefinition, tuning: WorldTuning, _cfg: Dictionary) -> Dictionary:
	var pool := {"pieces": [], "weights": [] as Array[float], "tiers": [], "floor": true}
	var tier := {"name": REGION_FLOOR, "surface_y": def.base_y, "y_lo": NAN, "y_hi": NAN}
	var polys: Array = []
	var region := SpawnSlotPlanner.mob_region(def, tuning)
	if region.size() >= 3:
		polys.append(region)
	var inset := tuning.num("spawns", "mob_region_inset_m")
	for e in def.region_extensions:
		var line: Variant = e.get("ring_line", null)
		if line is PackedVector2Array and (line as PackedVector2Array).size() >= 3:
			polys.append_array(Geometry2D.offset_polygon(line, -inset))
	for piece: PackedVector2Array in polys:
		var w := absf(_polygon_area(piece))
		if w > 0.0:
			(pool.pieces as Array).append(piece)
			(pool.weights as Array[float]).append(w)
			(pool.tiers as Array).append(tier)
	return pool if not (pool.pieces as Array).is_empty() else {}


## One pass over a pool (_areas / _floor): samples up to cfg.attempts points and keeps the best of the first
## cfg.candidates_per_box that pass every rule ({} when none does). `strict` keeps each sample to its piece's tier.
static func _search(pool: Dictionary, strict: bool, q: GroundQuery, ctx: Dictionary, placed: Array[Vector3],
		rng: RandomNumberGenerator) -> Dictionary:
	var cfg: Dictionary = ctx.cfg
	var best := {}
	var best_score := -INF
	var found := 0
	for _attempt in int(cfg.attempts):
		var k := _pick_piece(pool.weights, rng)
		var xz := _sample(pool.pieces[k], rng)
		if not xz.is_finite() or SpawnSlotPlanner.in_keepout(xz, ctx.keepouts):
			continue
		var tier: Dictionary = pool.tiers[k]
		var hit := q.top_surface(xz.x, xz.y, float(ctx.y_top), float(ctx.y_bottom), float(tier.surface_y))
		if not bool(hit.ok):
			continue
		var y := float(hit.y)
		if strict and not _on_tier(y, tier, float(cfg.tier_tolerance_m)):
			continue
		var p := Vector3(xz.x, y, xz.y)
		if not candidate_ok(p, q, ctx, placed):
			continue
		var score := _min_dist(p, placed)
		if score > best_score:
			best_score = score
			best = {"p": p, "region": String(tier.name),
				"placement": ("floor" if bool(pool.floor) else "area") + ("" if strict else "_relaxed")}
		found += 1
		if found >= int(cfg.candidates_per_box):
			break
	return best


## True when a box standing at `p` (feet on the ground) keeps every rule of the class doc against `ctx` (_context)
## and the boxes in `placed`. Public so the physics test checks the planner's own rules.
static func candidate_ok(p: Vector3, q: GroundQuery, ctx: Dictionary, placed: Array[Vector3]) -> bool:
	return violation(p, q, ctx, placed) == ""


## The first rule a box at `p` breaks, or "" when it keeps them all.
static func violation(p: Vector3, q: GroundQuery, ctx: Dictionary, placed: Array[Vector3]) -> String:
	var cfg: Dictionary = ctx.cfg
	var def: MapDefinition = ctx.def
	var lift := float(ctx.lift)
	if def.footprint.size() >= 3 and not def.footprint_contains(p):
		return "outside the map"
	if SpawnSlotPlanner.in_keepout(Vector2(p.x, p.z), ctx.keepouts):
		return "inside a spawn keep-out"
	if not q.is_clear(p + Vector3.UP * lift, float(cfg.clearance_radius_m), float(cfg.clearance_height_m)):
		return "clearance capsule blocked"
	for t: PortalDef in ctx.triggers:
		if t.trigger_contains(p + Vector3.UP * 0.1):
			return "inside portal trigger %s" % t.key()
	if _min_dist(p, ctx.portal_points) < float(cfg.portal_clearance_m):
		return "%.2f m from a portal or arrival" % _min_dist(p, ctx.portal_points)
	for n: Dictionary in ctx.npcs:
		var npc_p: Vector3 = n.p
		if Vector2(p.x - npc_p.x, p.z - npc_p.z).length() < float(n.r):
			return "inside NPC %s's talk space" % String(n.name)
	if _min_dist(p, ctx.slots) < float(cfg.spawn_slot_clearance_m):
		return "%.2f m from a monster spawn slot" % _min_dist(p, ctx.slots)
	if _min_dist(p, placed) < float(cfg.min_spacing_m):
		return "%.2f m from another box" % _min_dist(p, placed)
	var free := approach_points(p, q, ctx)
	if free < int(cfg.approach_min_free):
		return "only %d standing points beside it" % free
	return ""


## How many of the approach_directions points approach_m around `p` a player can stand on: grounded within
## tier_tolerance_m of the box's ground, the player's grounding capsule clear, inside the map and outside the triggers.
static func approach_points(p: Vector3, q: GroundQuery, ctx: Dictionary) -> int:
	var cfg: Dictionary = ctx.cfg
	var def: MapDefinition = ctx.def
	var n := maxi(int(cfg.approach_directions), 1)
	var free := 0
	for k in n:
		var a := p + Vector3.FORWARD.rotated(Vector3.UP, TAU * k / n) * float(cfg.approach_m)
		if def.footprint.size() >= 3 and not def.footprint_contains(a):
			continue
		var g := q.ground_at(a, float(ctx.probe_up), float(ctx.probe_down))
		if not bool(g.ok) or absf(float(g.y) - p.y) > float(cfg.tier_tolerance_m):
			continue
		var feet := Vector3(a.x, float(g.y), a.z)
		if not q.is_clear(feet + Vector3.UP * float(ctx.lift), float(ctx.body_radius), float(ctx.body_height)):
			continue
		var in_trigger := false
		for t: PortalDef in ctx.triggers:
			if t.trigger_contains(feet + Vector3.UP * 0.1):
				in_trigger = true
				break
		if not in_trigger:
			free += 1
	return free


## The rule context of `def` (_context) for checks outside plan(): {} when breakables.json placement is broken.
static func rules_for(def: MapDefinition, tuning: WorldTuning, db: ContentDB) -> Dictionary:
	var warnings: PackedStringArray = []
	var cfg := config(db, warnings)
	return _context(def, tuning, cfg, warnings) if not cfg.is_empty() else {}


## True when height y belongs to the area's own tier: inside its authored y band (spawn_regions), else within `tol`
## of its surface height (the floor: base_y), either way widened by `tol`.
static func _on_tier(y: float, area: Dictionary, tol: float) -> bool:
	var lo := float(area.get("y_lo", NAN))
	var hi := float(area.get("y_hi", NAN))
	if not is_nan(lo) and not is_nan(hi):
		return y >= minf(lo, hi) - tol and y <= maxf(lo, hi) + tol
	return absf(y - float(area.get("surface_y", y))) <= tol


## A piece index drawn by weight (area), so samples are uniform over the whole pool.
static func _pick_piece(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	var k := 0
	while k < weights.size() - 1 and r > weights[k]:
		r -= weights[k]
		k += 1
	return k


## A uniform sample inside the polygon (rejection from its bounding box); Vector2.INF on failure.
static func _sample(poly: PackedVector2Array, rng: RandomNumberGenerator) -> Vector2:
	var box := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		box = box.expand(v)
	for _i in 32:
		var p := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
		if Geometry2D.is_point_in_polygon(p, poly):
			return p
	return Vector2.INF


static func _polygon_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func _min_dist(p: Vector3, points: Array[Vector3]) -> float:
	var d := INF
	for o in points:
		d = minf(d, p.distance_to(o))
	return d
