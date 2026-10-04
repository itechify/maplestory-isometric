class_name SpawnSlot
extends RefCounted
## One monster spawn point in 3D (MAP_ARCHITECTURE.md section 4.7.1): MeowDB's spawns[index] placed on the map.
##
## index and mob_id are canonical and never change; transform and region are the adaptation (which exported spawn
## area it was distributed into, grounded on walkable collision).
##
## index NO_SLOT (-1) is a synthetic slot that is not one of MeowDB's spawn points: the debug console's `spawn`
## hands the monster factory one with placement "debug". MapInstanceState and MapInstanceView treat it as "no slot":
## no kill is ever recorded for it and it is never respawned.

## The index of a synthetic slot (debug spawns): not a MeowDB spawn point.
const NO_SLOT := -1
const PLACEMENT_DEBUG := "debug"

var index: int = NO_SLOT
## MeowDB monster id ("2" = Snail).
var mob_id: String = ""
## MeowDB mobTime in seconds (0 = wave point, 5 s cooldown; > 0 = timed point).
var mob_time_s: float = 0.0
var transform: Transform3D = Transform3D.IDENTITY
## Name of the spawn area the slot was placed in ("fallback:footprint" when the map exported none).
var region: String = ""
## "strict" (on its area's own tier), "relaxed" (any top surface in the area), "pinned" (maps/<id>.json override),
## "unplaced" (no geometry yet), "forced" (constraints could not all be met; logged) or "debug" (a NO_SLOT spawn).
var placement: String = "unplaced"
var grounded: bool = false


func position() -> Vector3:
	return transform.origin


## True for one of MeowDB's spawn points (index >= 0); false for a synthetic NO_SLOT slot.
func is_spawn_point() -> bool:
	return index >= 0


## A synthetic slot for a monster outside the spawn system (the debug console's `spawn`), standing at `xform`.
static func synthetic(mob: String, xform: Transform3D, grounded_ok: bool = true) -> SpawnSlot:
	var s := SpawnSlot.new()
	s.index = NO_SLOT
	s.mob_id = mob
	s.region = PLACEMENT_DEBUG
	s.placement = PLACEMENT_DEBUG
	s.grounded = grounded_ok
	s.transform = xform
	return s


func to_dict() -> Dictionary:
	var o := transform.origin
	return {"index": index, "mob_id": mob_id, "region": region, "placement": placement, "grounded": grounded,
		"position": [o.x, o.y, o.z]}
