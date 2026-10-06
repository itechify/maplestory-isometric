class_name SkillSight
extends RefCounted
## The line of sight of a thrown skill (Three Snails), the owner's rule in #6 (misostory/skills.json three_snails
## terrain_check, sight_blocking_hulls): only terrain and buildings stop a shell. A ray along the world's physics
## layers MASK (walkable ground, blocking walls, island scenery; never the containment rings, the player, monsters or
## the interactables) is tested, and a body it meets blocks unless it is a prop:
##   - terrain and architecture: every body that is not a prop hull (the export's "Ground" and "Walls" trimeshes, the
##     island's scenery chunks, anything else on those layers);
##   - a prop hull ("<object>_hull<k>", one convex prism per prop instance: crates, fences, lamps, signs, trees) does
##     not block, unless its object is one of `blocking_hulls` (the buildings and terrain pieces the export also
##     prisms: houses, towers, plinth outcrops), matched by the object name with its "_hull<k>" and "_NN" suffixes
##     removed ("Amherst_1010000_X1010000_YellowHouse_hull0" -> ends with "X1010000_YellowHouse").
## Monsters (layer monsters) and Wooden Boxes (no physics body) are never on the mask, so they never block either.

const MASK := WorldLayers.WALKABLE | WorldLayers.BLOCKING | WorldLayers.SCENERY
## How many non-blocking props one ray may pass through before giving up (it then counts as clear).
const MAX_PASS_THROUGH := 32


## True when `collider` stops a thrown skill: terrain or a building, never a prop hull outside `blocking_hulls`.
static func blocks(collider: Object, blocking_hulls: PackedStringArray) -> bool:
	if not (collider is Node):
		return collider != null
	var object := hull_object((collider as Node).name)
	if object == "":
		return true
	for b in blocking_hulls:
		if b != "" and object.ends_with(b):
			return true
	return false


## The object a prop hull body was cut from ("<object>_hull<k>" with a trailing "_NN" instance suffix removed), or ""
## when `body_name` is not a prop hull.
static func hull_object(body_name: String) -> String:
	var i := body_name.rfind("_hull")
	if i <= 0 or not body_name.substr(i + 5).is_valid_int():
		return ""
	var object := body_name.left(i)
	var j := object.rfind("_")
	if j > 0 and object.substr(j + 1).is_valid_int():
		object = object.left(j)
	return object


## The first point between `from` and `to` where terrain or a building stops the line ({"position", "collider"}), or
## {} when the line is clear. Props on the way are passed through.
static func first_block(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		blocking_hulls: PackedStringArray) -> Dictionary:
	if space == null or from.is_equal_approx(to):
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, MASK)
	q.hit_back_faces = true
	var skip: Array[RID] = []
	for i in MAX_PASS_THROUGH:
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		if blocks(hit.get("collider"), blocking_hulls):
			return {"position": hit["position"], "collider": hit["collider"]}
		skip.append(hit["rid"])
	return {}


## True when nothing but props stands between `from` and `to`.
static func clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, blocking_hulls: PackedStringArray) -> bool:
	return first_block(space, from, to, blocking_hulls).is_empty()
