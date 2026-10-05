class_name SpawnSlotPlanner
extends RefCounted
## Places MeowDB's spawn points in 3D (M1 rule, MAP_ARCHITECTURE.md section 4.7.1 simplified for the current export).
##
## Species and counts are canonical (MeowDB spawns[], index preserved); positions are the adaptation:
##   1. each species' slots are distributed over the map's exported spawn areas tagged with that species, else
##      over every area of the map, else (no areas at all, 000000030 today) over the whole mob region. Every area
##      is first clipped to the map's mob region (the layout footprint inset by spawns.mob_region_inset_m, section
##      4.7.4); areas share a species' slots by largest remainder of their weight (the authored proxy count
##      `points`, else the area in m^2);
##   2. a slot samples points inside its area with a RandomNumberGenerator seeded by hash("<map_id>:<index>"), so
##      placement is deterministic per slot;
##   3. a sample is accepted when the topmost surface there is walkable (first on the area's own tier, within
##      spawns.tier_tolerance_m of its surface height, then on any top surface), the clearance capsule is free
##      (spawns.clearance_radius_m wide, as tall as the species' body: clearance_height()), it lies outside every
##      keep-out disc of maps/<id>.json spawn_keepouts, and it stands at least spawns.slot_min_spacing_m from
##      earlier slots and spawns.slot_portal_clearance_m from every arrival point (portal spawn_transforms and
##      player_spawns[0]);
##   4. maps/<id>.json spawn_slot_overrides may pin a slot's position (with a reason); species/count never change.
## All tuning comes from presentation.json and maps/<id>.json (WorldTuning); species body heights from the monster
## data (species_body_heights). Ground truth comes from a GroundQuery.


## Plans every slot of `def` in place. `body_heights` (mob_id -> m, see species_body_heights) makes the clearance
## capsule as tall as each species. Returns warnings (empty when every constraint held).
static func plan(def: MapDefinition, q: GroundQuery, tuning: WorldTuning, body_heights: Dictionary = {}) -> PackedStringArray:
	var warnings: PackedStringArray = []
	if def.monster_spawn_definitions.is_empty():
		return warnings
	var spacing := tuning.num("spawns", "slot_min_spacing_m")
	var clearance := tuning.num("spawns", "slot_portal_clearance_m")
	var attempts := maxi(tuning.count("spawns", "slot_attempts"), 1)
	var tier_tol := tuning.num("spawns", "tier_tolerance_m")
	var radius := tuning.num("spawns", "clearance_radius_m")
	var problems: Array = []
	var keepouts := keepouts_of(def, tuning, problems)
	for p in problems:
		warnings.append(String(p))
	var avoid: Array[Vector3] = []
	for p in def.portals:
		if p.is_canonical() or p.portal_type == PortalDef.TYPE_ARRIVAL:
			avoid.append(p.spawn_transform.origin)
	if not def.player_spawns.is_empty():
		avoid.append(def.player_spawns[0].origin)
	var areas := _areas_for(def, tuning)
	if areas.is_empty():
		warnings.append("%s: no spawn area and no footprint; %d slots left unplaced" % [def.map_id, def.monster_spawn_definitions.size()])
		return warnings
	var assignment := _assign_areas(def, areas)
	var overrides: Dictionary = (tuning.map_override(def.map_id).get("spawn_slot_overrides", {}) as Dictionary) \
		if tuning.map_override(def.map_id).get("spawn_slot_overrides", null) is Dictionary else {}
	var y_top := def.y_max + tuning.num("grounding", "probe_up_m")
	var y_bottom := def.y_min - tuning.num("grounding", "probe_down_m")
	var placed: Array[Vector3] = []
	for slot in def.monster_spawn_definitions:
		var area: Dictionary = areas[int(assignment[slot.index])]
		slot.region = String(area.name)
		var pin: Variant = overrides.get(str(slot.index), null)
		if pin is Dictionary and (pin as Dictionary).get("position", null) is Array:
			var pp := WorldSidecars.vec3((pin as Dictionary).position)
			var g := q.ground_at(pp, tuning.num("grounding", "probe_up_m"), tuning.num("grounding", "probe_down_m"))
			slot.transform = Transform3D(Basis.IDENTITY, Vector3(pp.x, float(g.y) if bool(g.ok) else pp.y, pp.z))
			slot.grounded = bool(g.ok)
			slot.placement = "pinned"
			placed.append(slot.transform.origin)
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s:%d" % [def.map_id, slot.index])
		var height := clearance_height(slot.mob_id, tuning, body_heights)
		var pieces: Array = area.pieces
		var piece_weights: Array[float] = []
		for piece in pieces:
			piece_weights.append(absf(_polygon_area(piece)))
		var bbox := _bbox(pieces[0])
		var best := {}
		var best_score := -INF
		var accepted := false
		for attempt in attempts:
			var strict := attempt < attempts / 2
			var pt := _sample_pieces(pieces, piece_weights, rng)
			if not pt.is_finite() or in_keepout(pt, keepouts):
				continue
			var hit := q.top_surface(pt.x, pt.y, y_top, y_bottom, float(area.surface_y))
			if not bool(hit.ok):
				continue
			var y := float(hit.y)
			if strict and not _on_tier(y, area, tier_tol):
				continue
			var p3 := Vector3(pt.x, y, pt.y)
			if not q.is_clear(p3, radius, height):
				continue
			var d_slots := _min_dist(p3, placed)
			var d_avoid := _min_dist(p3, avoid)
			var score := minf(d_slots / maxf(spacing, 0.001), d_avoid / maxf(clearance, 0.001))
			if score > best_score:
				best_score = score
				best = {"p": p3, "strict": strict}
			if d_slots >= spacing and d_avoid >= clearance:
				accepted = true
				best = {"p": p3, "strict": strict}
				break
		var yaw := rng.randf_range(-PI, PI)
		if best.is_empty():
			slot.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(bbox.get_center().x, float(area.surface_y), bbox.get_center().y))
			slot.grounded = false
			slot.placement = "unplaced"
			warnings.append("%s slot %d (%s): no walkable, clear point found in %s" % [def.map_id, slot.index, slot.mob_id, slot.region])
			continue
		slot.transform = Transform3D(Basis(Vector3.UP, yaw), best.p)
		slot.grounded = true
		if accepted:
			slot.placement = "strict" if bool(best.strict) else "relaxed"
		else:
			slot.placement = "forced"
			warnings.append("%s slot %d (%s): spacing/clearance not met in %s (best effort)" % [def.map_id, slot.index, slot.mob_id, slot.region])
		placed.append(slot.transform.origin)
	return warnings


## Height (m) of the clearance capsule for one species: its body height from `body_heights`, never below
## presentation.json spawns.clearance_height_m (the original proxy approximation, so small species keep it).
static func clearance_height(mob_id: String, tuning: WorldTuning, body_heights: Dictionary = {}) -> float:
	return maxf(tuning.num("spawns", "clearance_height_m"), float(body_heights.get(mob_id, 0.0)))


## Body height (m) of every monster species with an adaptation file (data/misostory/monsters/<id>.json, owned by
## the monster system), as the monster system sizes the body: when the species' model_fit (its own, else
## monsters/_shared.json's) is "sprite_height", the canonical sprite_size_px[1] x WorldScale.actor (the Tutorial Jr.
## Sentinel: 68 px = 1.7 m); otherwise the species' capsule_height_m. A species without an adaptation file, or with
## neither value, is left out and gets the presentation.json clearance.
static func species_body_heights(db: ContentDB) -> Dictionary:
	var out := {}
	if db == null:
		return out
	var files: Dictionary = db.miso.get("monsters", {}) if db.miso.get("monsters", null) is Dictionary else {}
	var shared: Dictionary = files.get("_shared", {}) if files.get("_shared", null) is Dictionary else {}
	for key in files:
		var id := str(key)
		if id.begins_with("_") or not (files[key] is Dictionary):
			continue
		var a: Dictionary = files[key]
		var fit := str(a.get("model_fit", shared.get("model_fit", "")))
		var spr: Variant = db.monster(id).get("sprite_size_px", null)
		var h := 0.0
		if fit == "sprite_height" and spr is Array and (spr as Array).size() == 2:
			h = WorldScale.actor(float(spr[1]))
		elif typeof(a.get("capsule_height_m", null)) in [TYPE_INT, TYPE_FLOAT]:
			h = float(a["capsule_height_m"])
		if h > 0.0:
			out[id] = h
	return out


## The keep-out discs of maps/<id>.json spawn_keepouts as [{"center": Vector2 (world XZ), "radius": m, "what"}].
## An entry names "around_prop" (every instance of that prop shape in the sidecar's collision.prop_instances) or a
## world "center" [x, z] / [x, y, z], and "radius_m". Problems (unknown prop, bad entry) are appended to `problems`.
static func keepouts_of(def: MapDefinition, tuning: WorldTuning, problems: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = tuning.map_override(def.map_id).get("spawn_keepouts", [])
	if not (raw is Array):
		return out
	for e in raw:
		if not (e is Dictionary) or not (typeof((e as Dictionary).get("radius_m", null)) in [TYPE_INT, TYPE_FLOAT]):
			problems.append("%s: spawn_keepouts entry without radius_m: %s" % [def.map_id, str(e)])
			continue
		var entry: Dictionary = e
		var r := float(entry.radius_m)
		if entry.get("around_prop", null) is String:
			var shape := String(entry.around_prop)
			var found := 0
			var col: Dictionary = def.sidecar.get("collision", {}) if def.sidecar.get("collision", null) is Dictionary else {}
			for inst in col.get("prop_instances", []):
				if inst is Dictionary and String(inst.get("shape", "")) == shape and inst.get("xform", null) is Array \
						and (inst.xform as Array).size() >= 12:
					var x: Array = inst.xform
					out.append({"center": Vector2(float(x[9]), float(x[11])), "radius": r, "what": shape})
					found += 1
			if found == 0 and def.has_markers:
				problems.append("%s: spawn_keepouts names prop %s, which the sidecar does not place" % [def.map_id, shape])
		elif entry.get("center", null) is Array and (entry.center as Array).size() >= 2:
			var c: Array = entry.center
			var z := float(c[2]) if c.size() >= 3 else float(c[1])
			out.append({"center": Vector2(float(c[0]), z), "radius": r, "what": "center"})
		else:
			problems.append("%s: spawn_keepouts entry needs around_prop or center: %s" % [def.map_id, str(entry)])
	return out


## True when the world XZ point lies inside one of `keepouts` (keepouts_of).
static func in_keepout(xz: Vector2, keepouts: Array[Dictionary]) -> bool:
	for k in keepouts:
		if xz.distance_to(k.center) < float(k.radius):
			return true
	return false


## The map's mob region: the layout footprint inset by spawns.mob_region_inset_m ([] without a footprint).
static func mob_region(def: MapDefinition, tuning: WorldTuning) -> PackedVector2Array:
	if def.footprint_layout.size() < 3:
		return PackedVector2Array()
	var shrunk := Geometry2D.offset_polygon(def.footprint_layout, -tuning.num("spawns", "mob_region_inset_m"))
	return shrunk[0] if not shrunk.is_empty() else def.footprint_layout


## Candidate areas of a map, each clipped to the mob region ("pieces"): the exported spawn areas, or the whole mob
## region when the map exported none. Areas with less room than one slot inside the region are dropped.
static func _areas_for(def: MapDefinition, tuning: WorldTuning) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var region := mob_region(def, tuning)
	var spacing := tuning.num("spawns", "slot_min_spacing_m")
	for a in def.spawn_areas:
		var poly: PackedVector2Array = a.polygon
		if poly.size() < 3:
			continue
		var pieces: Array = [poly]
		if region.size() >= 3:
			pieces = []
			for piece in Geometry2D.intersect_polygons(poly, region):
				if absf(_polygon_area(piece)) > 0.0:
					pieces.append(piece)
		var room := 0.0
		for piece in pieces:
			room += absf(_polygon_area(piece))
		if room < spacing * spacing:
			continue
		var clipped := a.duplicate()
		clipped["pieces"] = pieces
		out.append(clipped)
	if out.is_empty() and region.size() >= 3:
		out.append({"name": "fallback:footprint", "species": PackedStringArray(), "polygon": region,
			"pieces": [region], "surface_y": def.base_y, "weight": 1.0})
	return out


## Index into `areas` for every slot (by slot.index), species-matched areas first, largest-remainder quotas.
static func _assign_areas(def: MapDefinition, areas: Array[Dictionary]) -> Dictionary:
	var by_species := {}
	for s in def.monster_spawn_definitions:
		if not by_species.has(s.mob_id):
			by_species[s.mob_id] = [] as Array[int]
		(by_species[s.mob_id] as Array).append(s.index)
	var out := {}
	var species_ids: Array = by_species.keys()
	species_ids.sort()
	for mob_id in species_ids:
		var slots: Array = by_species[mob_id]
		var species_name := String(def.mob_names.get(mob_id, ""))
		var candidates: Array[int] = []
		for i in areas.size():
			if species_name != "" and species_name in (areas[i].species as PackedStringArray):
				candidates.append(i)
		if candidates.is_empty():
			for i in areas.size():
				if (areas[i].species as PackedStringArray).is_empty():
					candidates.append(i)
		if candidates.is_empty():
			for i in areas.size():
				candidates.append(i)
		var quotas := _largest_remainder(slots.size(), candidates, areas)
		var k := 0
		for ci in candidates.size():
			for _n in int(quotas[ci]):
				out[int(slots[k])] = candidates[ci]
				k += 1
	return out


static func _largest_remainder(total: int, candidates: Array[int], areas: Array[Dictionary]) -> Array[int]:
	var weights: Array[float] = []
	var sum := 0.0
	for i in candidates:
		var w := maxf(float(areas[i].get("weight", 1.0)), 0.0001)
		weights.append(w)
		sum += w
	var quotas: Array[int] = []
	var rema: Array[float] = []
	var given := 0
	for w in weights:
		var exact := total * w / sum
		quotas.append(int(floor(exact)))
		rema.append(exact - floor(exact))
		given += int(floor(exact))
	while given < total:
		var best := 0
		for j in rema.size():
			if rema[j] > rema[best]:
				best = j
		quotas[best] += 1
		rema[best] = -1.0
		given += 1
	return quotas


static func _bbox(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


## True when height y belongs to the area's own tier: inside its authored y_band (spawn_regions), else within
## `tol` of its surface height (derived spawn_areas), either way widened by `tol`.
static func _on_tier(y: float, area: Dictionary, tol: float) -> bool:
	var lo := float(area.get("y_lo", NAN))
	var hi := float(area.get("y_hi", NAN))
	if not is_nan(lo) and not is_nan(hi):
		return y >= minf(lo, hi) - tol and y <= maxf(lo, hi) + tol
	return absf(y - float(area.get("surface_y", y))) <= tol


## A uniform sample over several polygons: pick one by area, then sample inside it.
static func _sample_pieces(pieces: Array, weights: Array[float], rng: RandomNumberGenerator) -> Vector2:
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	var k := 0
	while k < weights.size() - 1 and r > weights[k]:
		r -= weights[k]
		k += 1
	var poly: PackedVector2Array = pieces[k]
	return _sample(poly, _bbox(poly), rng)


static func _polygon_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## A uniform sample inside the polygon (rejection from its bounding box); Vector2.INF on failure.
static func _sample(poly: PackedVector2Array, bbox: Rect2, rng: RandomNumberGenerator) -> Vector2:
	for _i in 32:
		var p := Vector2(rng.randf_range(bbox.position.x, bbox.end.x), rng.randf_range(bbox.position.y, bbox.end.y))
		if Geometry2D.is_point_in_polygon(p, poly):
			return p
	return Vector2.INF


static func _min_dist(p: Vector3, points: Array[Vector3]) -> float:
	var d := INF
	for o in points:
		d = minf(d, p.distance_to(o))
	return d
