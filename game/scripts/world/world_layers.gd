class_name WorldLayers
extends RefCounted
## The world's 3D physics layers (bit values for collision_layer / collision_mask). One table for every system;
## see docs/runtime/WORLD_RUNTIME.md "Collision layers". Layer numbers in the editor are bit index + 1.
##
##   1 walkable      map and trail ground (Ground-colonly of map, interior and World_Trails chunks)
##   2 blocking      walls, cliffs, rails, architecture, prop/tree hulls (Walls-colonly, *-convcolonly)
##   3 containment   invisible map rings (and the M2 gate plugs); the player collides, monsters do not
##   4 player        the player body
##   5 monsters      monster bodies
##   6 interactables portal triggers and NPC talk areas (Area3D; they monitor the player layer)
##   7 scenery       collision of island scenery chunks (island body, plinth outcrops, scenery, forest); never
##                   counted as walkable by the world's ground probes
##   8 kill          the sea-level kill plane (Area3D)

const WALKABLE := 1 << 0
const BLOCKING := 1 << 1
const CONTAINMENT := 1 << 2
const PLAYER := 1 << 3
const MONSTERS := 1 << 4
const INTERACTABLES := 1 << 5
const SCENERY := 1 << 6
const KILL := 1 << 7

## What a player body should collide with.
const PLAYER_MASK := WALKABLE | BLOCKING | CONTAINMENT | SCENERY
## What a monster body should collide with (no containment: monsters are clamped to their mob region by AI).
const MONSTER_MASK := WALKABLE | BLOCKING
## Surfaces a vertical ground probe can hit first (the first hit must be walkable).
const SURFACE_MASK := WALKABLE | BLOCKING
## What a standing capsule must not overlap.
const CLEARANCE_MASK := BLOCKING | CONTAINMENT

const NAMES := {
	WALKABLE: "walkable", BLOCKING: "blocking", CONTAINMENT: "containment", PLAYER: "player", MONSTERS: "monsters",
	INTERACTABLES: "interactables", SCENERY: "scenery", KILL: "kill",
}
