class_name TraversalTrails
extends RefCounted
## L2 per-link runs (MAP_ARCHITECTURE.md section 4.13 "Per link, walk", "Equivalence"), on a TraversalWalker:
##   walk      every trail link in each allowed direction, in edge mode: from the source portal's arrival, out
##             through the portal, along the trail centreline, across the far gate and on to the destination portal's
##             arrival. Asserts the exact event sequence map_left -> map_entered -> portal_used, a gate commit
##             (via "gate", the source portal, its arrival as last_arrival), no fall recovery, no region invariant
##             violation, no gate error, no stall.
##   press     the same direction by pressing Up at the source portal (doors: both ways), the warp-mode run.
##   equal     walk and press-Up from identical starting state (instance cache cleared, session RNG reseeded, the
##             frozen clock) must give the same current_map, last_arrival, respawn_reference, live instance and
##             event sequence (section 4.4: equivalence is logical, not positional).
##   ledge     40 -> 30 must fail: from 000000040's landing the bot pushes into the 2.4 m ledge and spams jump for
##             LEDGE_SPAM_S; current_map stays 000000040, the player never enters 000000030's region or the trail.
## Results: {"links": {link_id: {"kind", "one_way", "directions": {"<from>><to>": {"edge": run, "warp": run,
## "equivalent": bool, "diff": [..]}}}}, "ledge": {...}, "failed": int, "runs": int}; run = {"ok", "time_s",
## "distance_m", "issues", ...}.

## Seconds the bot spams jump against the one-way ledge (section 4.13: 10 s).
const LEDGE_SPAM_S := 10.0
## Jump presses during the ledge spam: one every this many frames (a fresh press each time).
const LEDGE_JUMP_EVERY := 12
## RNG seed of the equivalence runs (any fixed value: both runs of a pair use it).
const EQUIVALENCE_SEED := 4242


## Every link (or those in `only`: link ids). Await it.
static func run(w: TraversalWalker, only: PackedStringArray = PackedStringArray()) -> Dictionary:
	var d := w.defs()
	d.apply_configured_link_modes()
	var overrides := d.tuning.portal_section("link_modes").get("overrides", {}) as Dictionary
	var out := {"links": {}, "failed": 0, "runs": 0}
	var ids := d.graph.links.keys()
	ids.sort()
	for id in ids:
		if not only.is_empty() and not (String(id) in only):
			continue
		var link: Dictionary = d.graph.links[id]
		var entry := {"kind": String(link.kind), "one_way": bool(link.one_way), "mode": String(link.mode), "directions": {}}
		if overrides.has(id):
			entry["override_reason"] = String((overrides[id] as Dictionary).get("reason", ""))
		var ends: Array[PortalDef] = []
		for k in link.ends:
			var p: PortalDef = d.graph.portals.get(k, null)
			if p != null and p.is_canonical():
				ends.append(p)
		for src in ends:
			var dst_key := "%s>%s" % [src.source_map_id, src.destination_map_id]
			var dir := {}
			if String(link.kind) == PortalGraph.KIND_TRAIL and d.graph.is_edge(String(id)):
				var a: Dictionary = await walk_link(w, src)
				var b: Dictionary = await press_link(w, src)
				dir["edge"] = a
				dir["warp"] = b
				var diff := compare(a.get("state", {}), b.get("state", {}))
				dir["equivalent"] = diff.is_empty()
				dir["diff"] = diff
				for run in [a, b]:
					out["runs"] = int(out.runs) + 1
					if not bool(run.ok):
						out["failed"] = int(out.failed) + 1
				if not diff.is_empty():
					out["failed"] = int(out.failed) + 1
			else:
				var b2: Dictionary = await press_link(w, src)
				dir["warp"] = b2
				out["runs"] = int(out.runs) + 1
				if not bool(b2.ok):
					out["failed"] = int(out.failed) + 1
			(entry.directions as Dictionary)[dst_key] = dir
			print("TRAVERSAL LINK %s %s %s" % [id, dst_key, _line(dir)])
		(out.links as Dictionary)[String(id)] = entry
	if only.is_empty() or "T_000000030_out00__000000040" in only:
		var ledge: Dictionary = await ledge_blocks(w)
		out["ledge"] = ledge
		out["runs"] = int(out.runs) + 1
		if not bool(ledge.ok):
			out["failed"] = int(out.failed) + 1
		print("TRAVERSAL LEDGE 000000040>000000030 %s" % ("blocked (ok)" if bool(ledge.ok) else "FAILED: " + "; ".join(ledge.issues)))
	return out


## The path a walk through `src`'s trail takes: the player's position, src's anchor, the trail centreline from
## src's end and the destination portal's anchor (in the 4.5 m corridor, past the gate).
static func trail_path(d: MapDefinitions, src: PortalDef) -> PackedVector3Array:
	var t := d.trail(src.link_id)
	var dst := d.graph.portals.get(t.portal_key_of(src.destination_map_id), null) as PortalDef
	var path := PackedVector3Array([src.spawn_transform.origin, src.anchor_ground])
	path.append_array(t.centreline_from(src.source_map_id))
	if dst != null:
		path.append(dst.anchor_ground)
	return path


## Edge mode: walk src's trail into its destination. The run carries "state" (the logical state after it).
static func walk_link(w: TraversalWalker, src: PortalDef) -> Dictionary:
	var d := w.defs()
	var issues := PackedStringArray()
	if not await _reset_at(w, src):
		return {"ok": false, "issues": PackedStringArray(["cannot warp to %s" % src.key()])}
	var r: Dictionary = await w.walk(trail_path(d, src), "walk %s" % src.key())
	issues.append_array(r.issues)
	var expect := _expected_events(src)
	if w.events != expect:
		issues.append("events %s, expected %s" % [str(w.events), str(expect)])
	var rec: TransitionRecord = w.session.get("last_transition")
	if String(w.session.get("current_map")) != src.destination_map_id:
		issues.append("current_map %s, expected %s" % [String(w.session.get("current_map")), src.destination_map_id])
	elif rec == null or rec.via != "gate" or rec.portal_id != src.portal_id:
		issues.append("committed via %s portal %s, expected a gate commit of %s" % [rec.via if rec != null else "-",
			rec.portal_id if rec != null else "-", src.key()])
	var out := {"ok": issues.is_empty(), "time_s": r.time_s, "distance_m": r.distance_m, "issues": issues,
		"recoveries": r.recoveries, "violations": r.violations, "state": logical_state(w)}
	return out


## Warp mode: press Up at src (after the same reset as walk_link). The run carries "state".
static func press_link(w: TraversalWalker, src: PortalDef) -> Dictionary:
	var d := w.defs()
	if not await _reset_at(w, src):
		return {"ok": false, "issues": PackedStringArray(["cannot warp to %s" % src.key()])}
	var walk_in: Dictionary = await w.walk(PackedVector3Array([w.player.global_position, src.anchor_ground]), "to %s" % src.key())
	w.events.clear()
	var r: Dictionary = await w.press_up(src)
	var issues: PackedStringArray = r.issues
	if not bool(walk_in.ok):
		issues.append_array(walk_in.issues)
	var expect := _expected_events(src)
	if w.events != expect:
		issues.append("events %s, expected %s" % [str(w.events), str(expect)])
	var arrival := d.arrival_for(src)
	var xf: Transform3D = d.arrival_transform(arrival).xform
	var off := w.player.global_position.distance_to(xf.origin)
	if String(w.session.get("current_map")) != src.destination_map_id:
		issues.append("current_map %s, expected %s" % [String(w.session.get("current_map")), src.destination_map_id])
	elif off > 0.1:
		issues.append("arrived %.3f m from the arrival" % off)
	var rec: TransitionRecord = w.session.get("last_transition")
	var via := "door" if src.portal_type == PortalDef.TYPE_DOOR else "press_up"
	if rec == null or rec.via != via:
		issues.append("via %s, expected %s" % [rec.via if rec != null else "-", via])
	return {"ok": issues.is_empty(), "time_s": float(r.time_s) + float(walk_in.time_s), "distance_m": walk_in.distance_m,
		"issues": issues, "state": logical_state(w)}


## 40 -> 30 must fail (section 4.13): from 000000040's landing, push into the ledge (the arrival gate's outward
## direction) and spam jump for LEDGE_SPAM_S. {"ok", "issues", "max_climb_m", "current_map", "time_s"}.
static func ledge_blocks(w: TraversalWalker) -> Dictionary:
	var d := w.defs()
	var t := d.trail("T_000000030_out00__000000040")
	var issues := PackedStringArray()
	if t == null or not await w.warp("000000040"):
		return {"ok": false, "issues": PackedStringArray(["no 30 -> 40 trail or no warp to 000000040"])}
	var gate := t.gate_into("000000040")
	var top := t.y_lo
	w.events.clear()
	var start_y := w.player.global_position.y
	var max_y := start_y
	var entered_30 := false
	var on_trail := false
	var frames := int(LEDGE_SPAM_S * 60.0)
	# Face the ledge: walk to the gate plane first (straight out of the landing), then push and jump.
	w.bot.world_dir = -gate.normal
	for f in frames:
		if f % LEDGE_JUMP_EVERY == 0:
			w.bot.press(&"jump")
		await w.get_tree().physics_frame
		var pos := w.player.global_position
		max_y = maxf(max_y, pos.y)
		if "000000030" in w.world.region_index.maps_at(pos):
			entered_30 = true
		if gate.signed_distance(pos) < -0.3 and pos.y > top - 0.3:
			on_trail = true
		if String(w.session.get("current_map")) != "000000040":
			break
	w.bot.release_all()
	await w.frames(5)
	if String(w.session.get("current_map")) != "000000040":
		issues.append("current_map became %s" % String(w.session.get("current_map")))
	if entered_30:
		issues.append("the player entered 000000030's region")
	if on_trail:
		issues.append("the player got onto the trail above the ledge (max height %.2f, ledge top %.2f)" % [max_y, top])
	if not w.events.is_empty():
		issues.append("events %s" % str(w.events))
	if gate.signed_distance(w.player.global_position) > 1.5:
		issues.append("the bot never reached the ledge (%.2f m inside the gate plane)" % gate.signed_distance(w.player.global_position))
	return {"ok": issues.is_empty(), "issues": issues, "max_climb_m": snappedf(max_y - start_y, 0.01),
		"ledge_top_y": snappedf(top, 0.01), "current_map": String(w.session.get("current_map")), "time_s": LEDGE_SPAM_S}


## The logical state a map change leaves (section 4.4 equivalence): current_map, last_arrival, respawn_reference,
## the live instance (its snapshot) and the event sequence.
static func logical_state(w: TraversalWalker) -> Dictionary:
	var la: ArrivalRef = w.session.get("last_arrival")
	var inst: MapInstanceState = w.session.get("instance_state")
	return {"current_map": String(w.session.get("current_map")), "last_arrival": la.to_dict() if la != null else {},
		"respawn_reference": String(w.session.get("respawn_reference")),
		"instance": JSON.stringify(inst.snapshot(w.fake_t)) if inst != null else "", "events": w.events.duplicate()}


## Keys of two logical states that differ.
static func compare(a: Dictionary, b: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if a.is_empty() or b.is_empty():
		out.append("missing state")
		return out
	for k in a:
		if str(a[k]) != str(b.get(k, null)):
			out.append(String(k))
	return out


## Warp to src's arrival, then make the next map change start from identical state: an empty instance cache, the
## session RNG reseeded, the event log cleared.
static func _reset_at(w: TraversalWalker, src: PortalDef) -> bool:
	if not await w.warp(src.source_map_id, src.portal_id):
		return false
	var cache: MapStateCache = w.session.get("cache")
	cache.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = EQUIVALENCE_SEED
	w.session.set("rng", rng)
	w.events.clear()
	return true


static func _expected_events(src: PortalDef) -> Array[String]:
	var out: Array[String] = ["left:" + src.source_map_id, "entered:%s<%s" % [src.destination_map_id, src.source_map_id],
		"portal:%s.%s>%s" % [src.source_map_id, src.portal_id, src.destination_map_id]]
	return out


static func _line(dir: Dictionary) -> String:
	var parts := PackedStringArray()
	for mode in ["edge", "warp"]:
		if dir.has(mode):
			var r: Dictionary = dir[mode]
			parts.append("%s=%s %.1fs %.1fm%s" % [mode, "ok" if bool(r.ok) else "FAIL", float(r.get("time_s", 0.0)),
				float(r.get("distance_m", 0.0)), "" if bool(r.ok) else " (" + "; ".join(r.get("issues", PackedStringArray())) + ")"])
	if dir.has("equivalent"):
		parts.append("equivalent=%s%s" % ["yes" if bool(dir.equivalent) else "NO", "" if bool(dir.equivalent) else " " + str(dir.diff)])
	return " ".join(parts)
