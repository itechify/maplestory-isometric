class_name PortalGraph
extends RefCounted
## The island's portal graph (MAP_ARCHITECTURE.md section 4.4). Pure.
##
## Nodes are MeowDB maps; every canonical portal is a directed edge source -> toMapId. PortalGraph resolves each
## portal's destination portal, in order:
##   1. an explicit override in portal_adaptations.json destination_overrides (must carry a reason);
##   2. the unique reciprocal: the one portal in the destination whose toMapId is the source (46 of 47 portals);
##   3. otherwise the destination's playerSpawns[0] (000000030.out00, the one-way link into 000000040).
## Zero-or-several reciprocals without an override would be a validation error (none today).
## It also groups portals into links (one per undirected pair, or one per one-way portal) with a link_mode
## (edge | warp) and answers the graph questions the L0 checks ask (BFS, strongly connected components).
##
## Link modes (section 4.4): a trail link is "edge" (its trail is walked; both portals are press_up_or_walk and its
## gates commit) or "warp" (press Up only; the containment plugs close both trail mouths). A door link is always
## "warp". set_link_mode() (the debug console's linkmode / map_link_mode) switches them at runtime and emits
## link_mode_changed, which the world listens to (plugs, gates, camera bounds).

const RES_OVERRIDE := "override"
const RES_RECIPROCAL := "reciprocal"
const RES_PLAYER_SPAWN := "player_spawn"
const KIND_TRAIL := "trail"
const KIND_DOOR := "door"

## A link changed mode (set_link_mode, or build_links on a rebuild): IslandWorld toggles the plugs and the camera
## bounds, GateMonitor reads the mode each tick.
signal link_mode_changed(link_id: String, mode: String)

## "<map>.<portal>" -> PortalDef (canonical portals and arrival gates).
var portals: Dictionary = {}
## map id -> Array[PortalDef] in insertion order.
var by_map: Dictionary = {}
## link id -> {id, kind, mode, one_way: bool, ends: PackedStringArray (portal keys), maps: PackedStringArray}
var links: Dictionary = {}
var map_ids: PackedStringArray = []
var errors: PackedStringArray = []
var warnings: PackedStringArray = []


func add_map(map_id: String) -> void:
	if not by_map.has(map_id):
		by_map[map_id] = [] as Array[PortalDef]
		map_ids.append(map_id)
		map_ids.sort()


func add_portal(p: PortalDef) -> void:
	add_map(p.source_map_id)
	if portals.has(p.key()):
		errors.append("duplicate portal %s" % p.key())
		return
	portals[p.key()] = p
	(by_map[p.source_map_id] as Array).append(p)


func portal(map_id: String, portal_id: String) -> PortalDef:
	return portals.get("%s.%s" % [map_id, portal_id], null)


func portals_of(map_id: String) -> Array[PortalDef]:
	var out: Array[PortalDef] = []
	for p in by_map.get(map_id, []):
		out.append(p)
	return out


## Every MeowDB portal, sorted by key.
func canonical_portals() -> Array[PortalDef]:
	var out: Array[PortalDef] = []
	var keys: Array = portals.keys()
	keys.sort()
	for k in keys:
		var p: PortalDef = portals[k]
		if p.is_canonical():
			out.append(p)
	return out


## Destination resolution (rules 1-3 above) for every canonical portal. `overrides` is
## portal_adaptations.json destination_overrides.overrides: "<map>.<portal>" -> {destination_portal_id |
## destination_spawn_index, reason}.
func resolve_destinations(overrides: Dictionary) -> void:
	for p in canonical_portals():
		if not by_map.has(p.destination_map_id):
			errors.append("%s leads to unknown map %s" % [p.key(), p.destination_map_id])
			continue
		var o: Variant = overrides.get(p.key(), null)
		if o is Dictionary:
			var od: Dictionary = o
			if String(od.get("reason", "")) == "":
				errors.append("destination override for %s has no reason" % p.key())
			p.provenance["resolution"] = RES_OVERRIDE
			p.provenance["override_reason"] = String(od.get("reason", ""))
			if String(od.get("destination_portal_id", "")) != "":
				p.destination_portal_id = String(od.destination_portal_id)
				p.destination_spawn_index = -1
				if portal(p.destination_map_id, p.destination_portal_id) == null:
					errors.append("override for %s names missing portal %s.%s" % [p.key(), p.destination_map_id, p.destination_portal_id])
			else:
				p.destination_portal_id = ""
				p.destination_spawn_index = int(od.get("destination_spawn_index", 0))
			continue
		var reciprocals: Array[PortalDef] = []
		for q in portals_of(p.destination_map_id):
			if q.is_canonical() and q.destination_map_id == p.source_map_id:
				reciprocals.append(q)
		if reciprocals.size() == 1:
			p.destination_portal_id = reciprocals[0].portal_id
			p.destination_spawn_index = -1
			p.provenance["resolution"] = RES_RECIPROCAL
		elif reciprocals.is_empty():
			p.destination_portal_id = ""
			p.destination_spawn_index = 0
			p.provenance["resolution"] = RES_PLAYER_SPAWN
		else:
			var names: PackedStringArray = []
			for q in reciprocals:
				names.append(q.portal_id)
			errors.append("%s: %d reciprocal portals in %s (%s) and no override" % [p.key(), reciprocals.size(),
				p.destination_map_id, ", ".join(names)])


## Link id of a portal pair: T_<mapA>_<portalA>__<mapB>_<portalB> with the ends in key order; a one-way portal
## with no destination portal gives T_<map>_<portal>__<destination map>.
static func link_id_for(a: PortalDef, b: PortalDef) -> String:
	if b == null:
		return "T_%s_%s__%s" % [a.source_map_id, a.portal_id, a.destination_map_id]
	var first := a
	var second := b
	if b.key() < a.key():
		first = b
		second = a
	return "T_%s_%s__%s_%s" % [first.source_map_id, first.portal_id, second.source_map_id, second.portal_id]


## Groups canonical portals into links and applies link modes. A link is a door link when either end's
## portal_type is "door". Mode: `forced` when non-empty, else link_overrides[id].mode, else default_modes[kind].
## Arrival gates (portal_type "arrival") join the link of their source portal (provenance.source_portal).
func build_links(default_modes: Dictionary, link_overrides: Dictionary, forced: String) -> void:
	# A rebuild (MapDefinitions.apply_configured_link_modes) signals only the links whose mode really changes.
	var before := {}
	for id in links:
		before[id] = String(links[id].mode)
	links.clear()
	for p in canonical_portals():
		var q: PortalDef = null
		if p.destination_portal_id != "":
			q = portal(p.destination_map_id, p.destination_portal_id)
		var id := PortalGraph.link_id_for(p, q)
		if not links.has(id):
			links[id] = {"id": id, "kind": KIND_TRAIL, "mode": String(before.get(id, PortalDef.LINK_WARP)), "one_way": q == null,
				"ends": PackedStringArray(), "maps": PackedStringArray()}
		var link: Dictionary = links[id]
		# A typed local shares the dictionary's array; appending through an `as` cast would change a copy (the M1
		# code did, so every link had empty ends and maps, and set_link_mode never reached the portals).
		var ends: PackedStringArray = link.ends
		ends.append(p.key())
		var link_maps: PackedStringArray = link.maps
		if not (p.source_map_id in link_maps):
			link_maps.append(p.source_map_id)
		if not (p.destination_map_id in link_maps):
			link_maps.append(p.destination_map_id)
		if p.portal_type == PortalDef.TYPE_DOOR or (q != null and q.portal_type == PortalDef.TYPE_DOOR):
			link["kind"] = KIND_DOOR
		p.link_id = id
	for p in portals.values():
		var gate: PortalDef = p
		if gate.portal_type != PortalDef.TYPE_ARRIVAL:
			continue
		var src_key := String(gate.provenance.get("source_portal", ""))
		var src: PortalDef = portals.get(src_key, null)
		if src == null or src.link_id == "":
			errors.append("arrival gate %s names unknown source portal %s" % [gate.key(), src_key])
			continue
		gate.link_id = src.link_id
		var gate_ends: PackedStringArray = links[src.link_id].ends
		gate_ends.append(gate.key())
	for id in links:
		var link: Dictionary = links[id]
		var mode := forced
		if mode == "":
			var o: Variant = link_overrides.get(id, null)
			mode = String((o as Dictionary).get("mode", "")) if o is Dictionary else ""
		if mode == "":
			mode = String(default_modes.get(link.kind, PortalDef.LINK_WARP))
		if link.kind == KIND_DOOR:
			mode = PortalDef.LINK_WARP  # doors are always warps (section 4.4)
		_apply_mode(id, mode)


## Debug/console hook (section 4.14): switches a link (or "all") to "edge" or "warp". Errors:
## ERR_INVALID_PARAMETER (not a mode), ERR_DOES_NOT_EXIST (unknown link), ERR_UNAVAILABLE ("edge" on a door link:
## doors are always warps). "all" with "edge" switches every trail link and leaves the doors warp (OK).
func set_link_mode(link_id: String, mode: String) -> Error:
	if mode != PortalDef.LINK_EDGE and mode != PortalDef.LINK_WARP:
		return ERR_INVALID_PARAMETER
	if link_id == "all":
		for id in links:
			if mode == PortalDef.LINK_WARP or String(links[id].kind) == KIND_TRAIL:
				_apply_mode(id, mode)
		return OK
	if not links.has(link_id):
		return ERR_DOES_NOT_EXIST
	if mode == PortalDef.LINK_EDGE and String(links[link_id].kind) != KIND_TRAIL:
		return ERR_UNAVAILABLE
	_apply_mode(link_id, mode)
	return OK


func link_mode(link_id: String) -> String:
	return String((links.get(link_id, {}) as Dictionary).get("mode", ""))


## True when the link is a trail link in edge mode (its trail is walkable and its gates commit).
func is_edge(link_id: String) -> bool:
	var link: Dictionary = links.get(link_id, {})
	return String(link.get("kind", "")) == KIND_TRAIL and String(link.get("mode", "")) == PortalDef.LINK_EDGE


## {mode: link count}, e.g. {"edge": 20, "warp": 4}.
func mode_counts() -> Dictionary:
	var out := {}
	for id in links:
		var m := String(links[id].mode)
		out[m] = int(out.get(m, 0)) + 1
	return out


## True when some canonical portal of from_map leads to to_map and can be used by pressing Up.
func has_direction(from_map: String, to_map: String) -> bool:
	for p in portals_of(from_map):
		if p.is_canonical() and p.destination_map_id == to_map and p.accepts_press():
			return true
	return false


## The directed map graph: "from>to" -> true, one entry per distinct (from, to) of the canonical portals.
func edge_set() -> Dictionary:
	var out := {}
	for p in canonical_portals():
		out["%s>%s" % [p.source_map_id, p.destination_map_id]] = true
	return out


## Distinct destination maps reachable from map_id in one step.
func neighbors(map_id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for p in portals_of(map_id):
		if p.is_canonical() and not (p.destination_map_id in out):
			out.append(p.destination_map_id)
	return out


## Breadth-first search over the directed graph; the start map is included.
func reachable_from(start: String) -> PackedStringArray:
	var seen: PackedStringArray = [start]
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var m: String = queue.pop_front()
		for n in neighbors(m):
			if not (n in seen):
				seen.append(n)
				queue.append(n)
	seen.sort()
	return seen


## Strongly connected components (Tarjan), each sorted, listed in discovery order.
func strongly_connected_components() -> Array[PackedStringArray]:
	var state := {"index": 0, "stack": [] as Array[String], "on": {}, "idx": {}, "low": {}, "out": [] as Array[PackedStringArray]}
	for m in map_ids:
		if not (state.idx as Dictionary).has(m):
			_strongconnect(m, state)
	return state.out


## Edges between different components: each [from_map, to_map]. With the canonical graph this is exactly the
## one-way 000000030 -> 000000040 (the SCC allowlist).
func cross_component_edges() -> Array[PackedStringArray]:
	var comp := {}
	var sccs := strongly_connected_components()
	for i in sccs.size():
		for m in sccs[i]:
			comp[m] = i
	var out: Array[PackedStringArray] = []
	var keys: Array = edge_set().keys()
	keys.sort()
	for e in keys:
		var parts := String(e).split(">")
		if comp.get(parts[0], -1) != comp.get(parts[1], -2):
			out.append(PackedStringArray([parts[0], parts[1]]))
	return out


func _strongconnect(v: String, s: Dictionary) -> void:
	s.idx[v] = s.index
	s.low[v] = s.index
	s.index = int(s.index) + 1
	(s.stack as Array).append(v)
	s.on[v] = true
	for w in neighbors(v):
		if not (s.idx as Dictionary).has(w):
			_strongconnect(w, s)
			s.low[v] = mini(int(s.low[v]), int(s.low[w]))
		elif bool((s.on as Dictionary).get(w, false)):
			s.low[v] = mini(int(s.low[v]), int(s.idx[w]))
	if int(s.low[v]) == int(s.idx[v]):
		var comp: PackedStringArray = []
		while true:
			var w: String = (s.stack as Array).pop_back()
			s.on[w] = false
			comp.append(w)
			if w == v:
				break
		comp.sort()
		(s.out as Array).append(comp)


func _apply_mode(link_id: String, mode: String) -> void:
	var link: Dictionary = links[link_id]
	var changed := String(link.get("mode", "")) != mode
	link["mode"] = mode
	for k in link.ends:
		var p: PortalDef = portals.get(k, null)
		if p == null:
			continue
		p.link_mode = mode
		if p.portal_type == PortalDef.TYPE_ARRIVAL:
			p.interaction_type = PortalDef.INTERACT_WALK_ONLY
		elif mode == PortalDef.LINK_EDGE and link.kind == KIND_TRAIL:
			p.interaction_type = PortalDef.INTERACT_PRESS_UP_OR_WALK
		else:
			p.interaction_type = PortalDef.INTERACT_PRESS_UP
	if changed:
		link_mode_changed.emit(link_id, mode)
