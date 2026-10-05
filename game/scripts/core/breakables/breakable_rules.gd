class_name BreakableRules
extends RefCounted
## The Wooden Box's rules (contract C8), pure: what the canonical record says, the MisoStory adaptation values
## (data/misostory/breakables.json) and the drop roll. No scene tree; the live state is MapInstanceState.breakables.
##
## Canonical (MeowDB): hits_to_break (canonical/breakables/<id>.json), the placements of a map and their respawn_s
## (canonical/maps/<id>.json reactors[], index = placement index), the drop table (drops/<id>.json, through
## DropRoller). Adaptation (breakables.json): the box's size (box.touch_px), the hit rule, the respawn clock and the
## 3D placement rules (BreakablePlacementPlanner).
##
##   BreakableRules.hits_to_break("0000001", db)                    # 4
##   BreakableRules.drop_context(character)                         # {"quests_in_progress": active quest ids}
##   BreakableRules.roll_drops("0000001", db, rng, ctx)             # DropRoller.roll(owner, db, rng, ctx) (contract C2)

## The adaptation table (data/misostory/breakables.json).
const TABLE := "breakables"
## The only breakable on Maple Island (MeowDB breakable 0000001, the Wooden Box).
const WOODEN_BOX := "0000001"


## The canonical record of breakable `id` ({} when there is none).
static func record(id: String, db: ContentDB) -> Dictionary:
	return db.get_entity("breakables", id) if db != null else {}


## Landed basic attacks that break `id` (canonical hits_to_break); 0 when the record or the value is missing.
static func hits_to_break(id: String, db: ContentDB) -> int:
	var v: Variant = record(id, db).get("hits_to_break", null)
	return int(v) if (v is int or v is float) and int(v) > 0 else 0


## A section of breakables.json ({} when the table or the section is missing).
static func section(db: ContentDB, name: String) -> Dictionary:
	var t: Variant = db.miso_table(TABLE) if db != null else null
	if t is Dictionary and (t as Dictionary).get(name, null) is Dictionary:
		return t[name]
	return {}


## A number of breakables.json `name`.`key`, or NAN when it is missing or not a number (callers report it).
static func num(db: ContentDB, name: String, key: String) -> float:
	var v: Variant = section(db, name).get(key, null)
	return float(v) if v is int or v is float else NAN


## The box's body in px (breakables.json box.touch_px: width, height; as deep as it is wide). Vector2.ZERO when the
## value is missing (nothing can then hit a box: the hit test needs a size).
static func touch_px(db: ContentDB) -> Vector2:
	var v: Variant = section(db, "box").get("touch_px", null)
	if v is Array and (v as Array).size() == 2 and (v[0] is int or v[0] is float) and (v[1] is int or v[1] is float):
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


## The box's body in meters: (width, height, depth) through WorldScale.actor.
static func size_m(db: ContentDB) -> Vector3:
	var px := touch_px(db)
	return Vector3(WorldScale.actor(px.x), WorldScale.actor(px.y), WorldScale.actor(px.x))


## The placements of a map, in canonical maps/<id>.json reactors[] order (the placement index):
## [{"index", "id", "name", "respawn_s", "x_px", "y_px"}]. `map_record` is the canonical map record
## (MapDefinition.canonical or ContentDB.map()).
static func placements_of(map_record: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = map_record.get("reactors", [])
	if not (raw is Array):
		return out
	for i in (raw as Array).size():
		var r: Variant = raw[i]
		if not (r is Dictionary):
			continue
		var e: Dictionary = r
		out.append({"index": i, "id": str(e.get("id", "")), "name": String(e.get("name", "")),
			"respawn_s": float(e.get("respawn_s", 0.0)) if (e.get("respawn_s", null) is int or e.get("respawn_s", null) is float) else 0.0,
			"x_px": e.get("x_px", null), "y_px": e.get("y_px", null)})
	return out


## The stable name of a placement: "<map_id>:<index>" (index into the map's canonical reactors[]).
static func placement_key(map_id: String, index: int) -> String:
	return "%s:%d" % [map_id, index]


## The drop roll context of contract C2: {"quests_in_progress": the character's in-progress quest ids}. A null
## character gives an empty list (gated entries then never roll).
static func drop_context(character: CharacterState) -> Dictionary:
	var ids := PackedStringArray()
	if character != null and character.quests != null:
		ids = character.quests.active_ids()
	return {"quests_in_progress": ids}


## Rolls a broken box's loot: DropRoller.roll(owner_id, db, rng, ctx), contract C2 (gated entries roll only while
## their quest is in progress). Until the drops package's v2 roller lands, DropRoller.roll takes no context: it is
## then called without one, and its placeholder table has no gate. The arity is read from the Callable, so this
## switches to the C2 call by itself once the roller takes the context.
static func roll_drops(owner_id: String, db: ContentDB, rng: RandomNumberGenerator, ctx: Dictionary) -> Array:
	var roll: Callable = DropRoller.roll
	var out: Variant = roll.call(owner_id, db, rng, ctx) if roller_takes_context() else roll.call(owner_id, db, rng)
	return out if out is Array else []


## True when DropRoller.roll takes the C2 roll context (a fourth argument).
static func roller_takes_context() -> bool:
	var roll: Callable = DropRoller.roll
	return roll.get_argument_count() >= 4
