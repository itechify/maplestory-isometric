class_name ArrivalResolver
extends RefCounted
## Turns a transition request into a concrete arrival BEFORE any fade, so a failure never leaves the screen black
## (MAP_ARCHITECTURE.md section 4.5 step 2), and implements the load fallback chain (section 4.9). Pure: the
## physics part of validating a saved `resume` point is a Callable supplied by the world.

const STEP_RESUME := "resume"
const STEP_ENTRY := "entry"
const STEP_PLAYER_SPAWN := "player_spawn"
const STEP_FALLBACK_MAP := "fallback_map"


## {"ok": bool, "xform": Transform3D, "arrival": ArrivalRef, "error": String}.
static func resolve(req: TransitionRequest, defs: MapDefinitions) -> Dictionary:
	var fail := {"ok": false, "xform": Transform3D.IDENTITY, "arrival": null, "error": ""}
	if req == null or defs == null:
		fail.error = "no request or no map definitions"
		return fail
	if not defs.has_map(req.to_map):
		fail.error = "unknown map %s" % req.to_map
		return fail
	if req.has_xform:
		var rec := req.arrival if req.arrival != null else ArrivalRef.at_spawn(req.to_map, 0)
		return {"ok": true, "xform": req.arrival_xform, "arrival": rec, "error": ""}
	if req.arrival == null:
		fail.error = "request to %s has no arrival" % req.to_map
		return fail
	if req.arrival.map_id != req.to_map:
		fail.error = "arrival %s is not in %s" % [req.arrival, req.to_map]
		return fail
	var r := defs.arrival_transform(req.arrival)
	if not bool(r.ok):
		fail.error = String(r.error)
		return fail
	return {"ok": true, "xform": r.xform, "arrival": req.arrival, "error": ""}


## The load chain (section 4.9): 1. `resume` (validated by `validate_resume`: Callable(map_id, world_pos) -> bool),
## 2. `entry` (a portal's spawn_transform or a player spawn), 3. player_spawns[0] of map_id, 4. an unknown map id
## loads at `fallback_map` player_spawns[0] (logged as an error).
## Returns {"ok", "map_id", "xform", "arrival": ArrivalRef, "step", "errors": PackedStringArray}.
static func resolve_load(location: Dictionary, defs: MapDefinitions, validate_resume: Callable,
		fallback_map: String) -> Dictionary:
	var errors: PackedStringArray = []
	var map_id := String(location.get("map_id", ""))
	if not defs.has_map(map_id):
		errors.append("saved map '%s' is unknown; loading at %s player_spawns[0]" % [map_id, fallback_map])
		var fb := ArrivalRef.at_spawn(fallback_map, 0)
		var r0 := defs.arrival_transform(fb)
		return {"ok": bool(r0.ok), "map_id": fallback_map, "xform": r0.xform, "arrival": fb, "step": STEP_FALLBACK_MAP,
			"errors": errors}
	var def := defs.get_def(map_id)
	var entry := ArrivalRef.from_dict(location.get("entry", null))
	if entry != null and entry.map_id != map_id:
		errors.append("saved entry %s is not in %s; ignored" % [entry, map_id])
		entry = null
	var resume: Variant = location.get("resume", null)
	if resume is Dictionary and (resume as Dictionary).get("local_pos", null) is Array:
		var world := def.to_world(WorldSidecars.vec3((resume as Dictionary).local_pos))
		if validate_resume.is_valid() and bool(validate_resume.call(map_id, world)):
			# facing_deg is a yaw in the map frame (like local_pos), so it follows the map if the layout turns it.
			var yaw := deg_to_rad(float((resume as Dictionary).get("facing_deg", 0.0)))
			var basis := (def.frame.basis * Basis(Vector3.UP, yaw)).orthonormalized()
			var rec := entry if entry != null else ArrivalRef.at_spawn(map_id, 0)
			return {"ok": true, "map_id": map_id, "xform": Transform3D(basis, world), "arrival": rec,
				"step": STEP_RESUME, "errors": errors}
		errors.append("saved resume point %s in %s failed validation; using the entry" % [world, map_id])
	if entry != null:
		var r := defs.arrival_transform(entry)
		if bool(r.ok):
			return {"ok": true, "map_id": map_id, "xform": r.xform, "arrival": entry, "step": STEP_ENTRY, "errors": errors}
		errors.append("saved entry %s cannot be resolved (%s)" % [entry, String(r.error)])
	var sp := ArrivalRef.at_spawn(map_id, 0)
	var r2 := defs.arrival_transform(sp)
	return {"ok": bool(r2.ok), "map_id": map_id, "xform": r2.xform, "arrival": sp, "step": STEP_PLAYER_SPAWN, "errors": errors}
