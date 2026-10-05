class_name MapDefinition
extends RefCounted
## The per-map runtime API the brief asks for (MAP_ARCHITECTURE.md section 4.3): one MeowDB map joined with its
## crosswalk row, its Blender sidecar markers and its adaptation data. Pure: built by MapDefinitions, grounded on
## collision by MapDefinitions.ground_all() once the world's physics exists.
##
## Canonical (MeowDB): map_id, map_name, street_name, which portals exist and where they lead, spawns (species,
## count, index), NPC ids, player spawn count, returnMap, bgm, isTown, fieldLimit.
## Adaptation (Blender + data/misostory): every transform, footprint, frame, camera bounds, ortho size, kill_y.

const SPACE_ISLAND := &"maple_island"
const SPACE_INTERIOR := &"interior_stage"

var map_id: String = ""
var map_name: String = ""
var street_name: String = ""
## &"maple_island" or &"interior_stage" (sidecar kind "interior").
var world_space: StringName = SPACE_ISLAND
## Every portal of the map: the canonical ones (MeowDB order) followed by adaptation arrival gates.
var portals: Array[PortalDef] = []
## Unique toMapIds of the canonical portals, in portal order.
var destination_maps: PackedStringArray = []
## index == MeowDB spawns[] index.
var monster_spawn_definitions: Array[SpawnSlot] = []
## MeowDB npc list, each with a 3D transform.
var npc_definitions: Array[NpcPlacement] = []
## index == MeowDB playerSpawns[] index. M1: [0] is the sidecar player_start (or the sidecar's own player_spawns
## when the exporter provides them); the rest repeat [0] until authored (open question 1: only [0] is used).
var player_spawns: Array[Transform3D] = []
## How many player_spawns entries come from authored markers (the rest are copies of [0]).
var player_spawns_authored: int = 0
## {map_id: returnMap, spawn_index: 0}.
var respawn_location: ArrivalRef = null
## {bgm, bgm_name, is_town, safe_zone, field_limit (raw), mob_rate (raw, ignored by spawns), preset, ortho_size,
##  ortho_size_keep_height, camera_pitch_deg, camera_forward}.
var environment_configuration: Dictionary = {}
## Map-local -> world (from the sidecar footprint local_frame).
var frame: Transform3D = Transform3D.IDENTITY
## World XZ polygon: the map's region and containment ring line. The layout footprint grown by the containment ring
## offset (footprint + 1 m), united with the map's authored region extensions (`region_extensions`).
var footprint: PackedVector2Array = []
## World XZ polygon the camera may show (M1: the footprint; M2 adds the touching trail zones).
var camera_bounds: PackedVector2Array = []

# --- extras used by the world runtime -----------------------------------------------------------------------
## Iteration One slug ("SnailHuntingGround1_40000"); keys the sidecar and the glbs.
var slug: String = ""
var gms_v8_id: int = -1
## Sidecar map_kind ("town", "hunting", "field", "townstreet", "interior"); "" without a sidecar.
var kind: String = ""
var has_markers: bool = false
## The raw layout rectangle (footprint without the ring offset) and its base height.
var footprint_layout: PackedVector2Array = []
## The layout rectangle grown by the ring offset, before the region extensions: `footprint` when the map has none.
var footprint_base: PackedVector2Array = []
## Region extensions merged into `footprint` (data/misostory/maps/<id>.json region_extensions, see
## MapDefinitions.apply_region_extensions): {name, ring_line: PackedVector2Array (world XZ), keep_ring_below_y
## (world y; NAN when the layout's own ring opens at every height), reason}.
var region_extensions: Array[Dictionary] = []
var base_y: float = 0.0
## Vertical extent of the map chunk (sidecar bounds) and the fall-recovery height.
var y_min: float = 0.0
var y_max: float = 0.0
var kill_y: float = 0.0
## Ortho size (frame width, Camera3D.KEEP_WIDTH) from cameras.gameplay x maps/<id>.json camera.ortho_size_scale.
var ortho_size: float = 0.0
## The collision this map's saved resume points were vetted against (MapDefinitions.resume_hash): the map chunk's
## collision hash (index.json) folded with those of the shared world chunks that overlap its region. A save stores
## it as resume.map_content_hash, and ArrivalResolver distrusts a resume point whose hash differs. "" without export.
var content_hash: String = ""
## The chunks folded into content_hash ("map" for the map's own chunk, then shared world chunk names).
var content_hash_chunks: PackedStringArray = []
## Parsed spawn areas: {name, species: PackedStringArray, polygon: PackedVector2Array, surface_y, weight}.
var spawn_areas: Array[Dictionary] = []
## MeowDB monster id -> name for the species on this map (canonical monsters[]), used to match spawn areas.
var mob_names: Dictionary = {}
## Species name -> library proxy asset, from the sidecar's spawn_points ("Snail" -> "Mob_Snail").
var species_proxies: Dictionary = {}
## The MeowDB record (read-only) and the parsed sidecar (read-only), for tools and debug overlays.
var canonical: Dictionary = {}
var sidecar: Dictionary = {}


## The portal named `id` ("east00", "arrival:..."), or null.
func portal(id: String) -> PortalDef:
	for p in portals:
		if p.portal_id == id:
			return p
	return null


## The MeowDB portals only (no arrival gates).
func canonical_portals() -> Array[PortalDef]:
	var out: Array[PortalDef] = []
	for p in portals:
		if p.is_canonical():
			out.append(p)
	return out


func spawn_point_count() -> int:
	return monster_spawn_definitions.size()


func player_spawn(index: int) -> Transform3D:
	if player_spawns.is_empty():
		return Transform3D.IDENTITY
	return player_spawns[clampi(index, 0, player_spawns.size() - 1)]


func npc(npc_id: String) -> NpcPlacement:
	for n in npc_definitions:
		if n.npc_id == npc_id:
			return n
	return null


func is_interior() -> bool:
	return world_space == SPACE_INTERIOR


## True when the world point lies inside the footprint (+ ring offset, + region extensions) in XZ.
func footprint_contains(p: Vector3) -> bool:
	if footprint.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), footprint)


## World -> map-local (save `resume.local_pos`, MAP_ARCHITECTURE section 4.9).
func to_local(world: Vector3) -> Vector3:
	return frame.affine_inverse() * world


func to_world(local: Vector3) -> Vector3:
	return frame * local


func is_town() -> bool:
	return bool(environment_configuration.get("is_town", false))


func _to_string() -> String:
	return "MapDefinition(%s %s)" % [map_id, map_name]
