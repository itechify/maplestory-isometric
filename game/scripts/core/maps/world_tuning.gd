class_name WorldTuning
extends RefCounted
## Typed access to the world runtime's adaptation constants, so no feel number lives in code:
##   data/misostory/presentation.json         transition timings, spawn-slot rules, grounding, containment, ...
##   data/misostory/portal_adaptations.json   link modes, overrides, arrival gates, trigger size, arrival inset
##   data/misostory/maps/<id>.json            per-map overrides (camera.ortho_size_scale, spawn_slot_overrides,
##                                            spawn_keepouts, ...)
##   data/misostory/death.json                respawn_player_spawn_index only (the rest is the game shell's)
## Each section carries its "reason" in the file. A missing key is a data error (push_error), never a silent default.

## death.json key: which player spawn of the return map a respawn uses (MAP_ARCHITECTURE open question 1).
const DEATH_RESPAWN_INDEX_KEY := "respawn_player_spawn_index"
## Old lookups that moved to another file: "section.key" of presentation.json -> the accessor that answers now.
## presentation.json respawn.player_spawn_index moved to death.json respawn_player_spawn_index.
const MOVED_KEYS := {"respawn.player_spawn_index": "respawn_spawn_index"}

var presentation: Dictionary = {}
var portals: Dictionary = {}
var per_map: Dictionary = {}
## data/misostory/death.json ({} when absent).
var death: Dictionary = {}
var errors: PackedStringArray = []


static func from_db(db: ContentDB) -> WorldTuning:
	var t := WorldTuning.new()
	var p: Variant = db.miso_table("presentation")
	t.presentation = p if p is Dictionary else {}
	var pa: Variant = db.miso_table("portal_adaptations")
	t.portals = pa if pa is Dictionary else {}
	var dt: Variant = db.miso_table("death")
	t.death = dt if dt is Dictionary else {}
	t.per_map = db.miso.get("maps", {})
	if t.presentation.is_empty():
		t.errors.append("data/misostory/presentation.json is missing")
	if t.portals.is_empty():
		t.errors.append("data/misostory/portal_adaptations.json is missing")
	return t


## presentation.json [section][key]. A key that moved to another file (MOVED_KEYS) is answered from its new home,
## so older callers keep working.
func value(section: String, key: String) -> Variant:
	var moved := "%s.%s" % [section, key]
	var sec: Variant = presentation.get(section, null)
	if MOVED_KEYS.has(moved) and not (sec is Dictionary and (sec as Dictionary).has(key)):
		return call(String(MOVED_KEYS[moved]))
	return _lookup(presentation, "presentation", section, key)


## Which player spawn of the canonical returnMap a respawn (and a save made while dead) uses:
## death.json respawn_player_spawn_index.value (MeowDB names the map, not the spawn: open question 1).
func respawn_spawn_index() -> int:
	return int(_lookup(death, "death", DEATH_RESPAWN_INDEX_KEY, "value"))


func num(section: String, key: String) -> float:
	return float(value(section, key))


func count(section: String, key: String) -> int:
	return int(value(section, key))


func flag(section: String, key: String) -> bool:
	return bool(value(section, key))


func text(section: String, key: String) -> String:
	return str(value(section, key))


## portal_adaptations.json [section][key].
func portal_value(section: String, key: String) -> Variant:
	return _lookup(portals, "portal_adaptations", section, key)


func portal_num(section: String, key: String) -> float:
	return float(portal_value(section, key))


## portal_adaptations.json [section] as a Dictionary ({} when absent).
func portal_section(section: String) -> Dictionary:
	var s: Variant = portals.get(section, {})
	return s if s is Dictionary else {}


## data/misostory/maps/<id>.json ({} when the map has no adaptation file).
func map_override(map_id: String) -> Dictionary:
	var m: Variant = per_map.get(map_id, {})
	return m if m is Dictionary else {}


## The talk zone of NPC `npc_id` (MeowDB id): {"radius_m", "centre_height_m", "profile"}. The zone is a sphere
## centred centre_height_m above the NPC's feet. Every NPC uses presentation.json npc.interaction_radius_m and
## npc.talk_centre_height_m (profile "default") unless a profile of npc.talk_zones lists it (for example
## "across_counter": the shopkeepers a player talks to across their counter); a profile's own radius_m and
## centre_height_m then apply. The first profile (by name) that lists the NPC wins; talk_zone_errors() reports one
## listed twice.
func talk_zone(npc_id: String) -> Dictionary:
	var zone := {"radius_m": num("npc", "interaction_radius_m"), "centre_height_m": num("npc", "talk_centre_height_m"),
		"profile": "default"}
	var profiles := talk_zone_profiles()
	var names := profiles.keys()
	names.sort()
	for pname: String in names:
		var p: Dictionary = profiles[pname]
		if npc_id in _ids(p.get("npcs", [])):
			zone["radius_m"] = float(p.get("radius_m", zone["radius_m"]))
			zone["centre_height_m"] = float(p.get("centre_height_m", zone["centre_height_m"]))
			zone["profile"] = pname
			break
	return zone


## presentation.json npc.talk_zones ({} when absent): profile name -> {"npcs", "radius_m", "centre_height_m",
## "reason"}.
func talk_zone_profiles() -> Dictionary:
	var npc: Variant = presentation.get("npc", {})
	var z: Variant = (npc as Dictionary).get("talk_zones", {}) if npc is Dictionary else {}
	var out := {}
	if z is Dictionary:
		for k: Variant in z:
			if z[k] is Dictionary:
				out[str(k)] = z[k]
	return out


## Problems in npc.talk_zones: a profile without npcs, a positive radius_m, a centre_height_m or a reason, and an NPC
## listed by two profiles. Empty when the data is sound.
func talk_zone_errors() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	var profiles := talk_zone_profiles()
	var names := profiles.keys()
	names.sort()
	for pname: String in names:
		var p: Dictionary = profiles[pname]
		var ids := _ids(p.get("npcs", []))
		if ids.is_empty():
			out.append("npc.talk_zones.%s lists no npcs" % pname)
		if not (p.get("radius_m", null) is float or p.get("radius_m", null) is int) or float(p.get("radius_m", 0.0)) <= 0.0:
			out.append("npc.talk_zones.%s needs a positive radius_m" % pname)
		if not (p.get("centre_height_m", null) is float or p.get("centre_height_m", null) is int):
			out.append("npc.talk_zones.%s needs centre_height_m" % pname)
		if str(p.get("reason", "")).strip_edges() == "":
			out.append("npc.talk_zones.%s needs a reason" % pname)
		for id in ids:
			if seen.has(id):
				out.append("npc %s is listed by npc.talk_zones.%s and npc.talk_zones.%s" % [id, seen[id], pname])
			else:
				seen[id] = pname
	return out


static func _ids(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if v is Array:
		for x: Variant in v:
			out.append(str(x))
	return out


## The trigger box size (x = width, y = height, z = depth).
func trigger_size() -> Vector3:
	return Vector3(portal_num("trigger", "width_m"), portal_num("trigger", "height_m"), portal_num("trigger", "depth_m"))


## "warp", "edge" or "" (no force) from portal_adaptations.json force_link_mode.
func forced_link_mode() -> String:
	var s := portal_section("force_link_mode")
	return str(s.get("value", "")) if s.get("value", null) != null else ""


func hidden_portal_types() -> Array:
	var v: Variant = portal_section("hidden_portal_types").get("value", [])
	var out: Array = []
	if v is Array:
		for t in v:
			out.append(int(t))
	return out


func _lookup(table: Dictionary, file_label: String, section: String, key: String) -> Variant:
	var s: Variant = table.get(section, null)
	if not (s is Dictionary) or not (s as Dictionary).has(key):
		var msg := "data/misostory/%s.json: missing %s.%s" % [file_label, section, key]
		if not (msg in errors):
			errors.append(msg)
			push_error("[WorldTuning] " + msg)
		return 0
	return (s as Dictionary)[key]
