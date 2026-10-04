class_name SaveMigrations
extends RefCounted
## The save-schema migration registry: one function per step, v -> v + 1, applied in order up to CURRENT_VERSION.
##
## A step is a Callable(doc: Dictionary) -> Dictionary that receives a deep copy of the version-v document (numbers
## already normalized, see SaveDocument.normalize_numbers) and returns the version v + 1 document, or {} when the
## input is not a valid version-v save. The registry stamps "save_version" after each step.
##
## Adding a schema change: bump CURRENT_VERSION, write _vN_to_vN1(), register it in _init(), add a fixture test
## (tests/unit/test_save_migrations.gd). Never edit an existing step: old saves in the wild depend on it.

## The schema version this build writes. SaveService.SAVE_VERSION is this constant.
const CURRENT_VERSION := 1
## Version reported for a document whose "save_version" is present but not a whole number >= 0.
const INVALID_VERSION := -1

## from_version -> Callable
var _steps: Dictionary = {}
## from_version -> human-readable step name (reported in SaveLoadResult.migrations_applied)
var _names: Dictionary = {}


func _init(include_builtin: bool = true) -> void:
	if include_builtin:
		register(0, "v0_flat_character_to_v1_envelope", _v0_to_v1)


## Registers (or replaces) the step from_version -> from_version + 1.
func register(from_version: int, step_name: String, step: Callable) -> void:
	_steps[from_version] = step
	_names[from_version] = step_name


## True if a step from `from_version` exists.
func has_step(from_version: int) -> bool:
	return _steps.has(from_version)


## The schema version of a parsed document: "save_version", or 0 when absent (pre-versioning saves).
static func version_of(doc: Dictionary) -> int:
	if not doc.has("save_version"):
		return 0
	var v: Variant = doc["save_version"]
	if typeof(v) == TYPE_INT and int(v) >= 0:
		return int(v)
	if typeof(v) == TYPE_FLOAT and is_finite(float(v)) and float(v) == floorf(float(v)) and float(v) >= 0.0:
		return int(v)
	return INVALID_VERSION


## Migrates `doc` up to `target_version`. Returns {"error": Error, "doc": Dictionary, "applied": PackedStringArray,
## "message": String}. ERR_INVALID_DATA when the version is invalid, newer than the target, a step is missing, or a
## step rejects the document. The input is never modified.
func migrate(doc: Dictionary, target_version: int = CURRENT_VERSION) -> Dictionary:
	var applied: PackedStringArray = []
	var from := version_of(doc)
	if from == INVALID_VERSION:
		return _fail("save_version is not a whole number >= 0", doc, applied)
	if from > target_version:
		return _fail("save_version %d is newer than this build supports (%d)" % [from, target_version], doc, applied)
	var current := doc.duplicate(true)
	var v := from
	while v < target_version:
		if not _steps.has(v):
			return _fail("no migration registered from save_version %d" % v, doc, applied)
		var step: Callable = _steps[v]
		var out: Variant = step.call(current.duplicate(true))
		if not (out is Dictionary) or (out as Dictionary).is_empty():
			return _fail("migration %s rejected the document" % String(_names.get(v, str(v))), doc, applied)
		current = out
		current["save_version"] = v + 1
		applied.append(String(_names.get(v, "v%d_to_v%d" % [v, v + 1])))
		v += 1
	return {"error": OK, "doc": current, "applied": applied, "message": ""}


func _fail(message: String, doc: Dictionary, applied: PackedStringArray) -> Dictionary:
	return {"error": ERR_INVALID_DATA, "doc": doc, "applied": applied, "message": message}


# --- built-in steps -------------------------------------------------------------------------------------------

## v0 -> v1. Version 0 is the pre-envelope prototype save: one flat object with no "save_version", using the field
## names of the Iteration Two brief's Phase 6 list:
##   {name, level, exp, hp, max_hp, mp, max_mp, str, dex, int, luk, available_ap, mesos, inventory, equipment,
##    quest_state, current_map, respawn_reference, play_time?, saved_at?}
## Version 1 wraps CharacterState.to_dict() in the envelope {save_version, game, saved_at, character, world, meta}:
##   max_hp/max_mp -> base_max_hp/base_max_mp, str..luk -> base_stats, available_ap -> ap, quest_state -> quests,
##   current_map -> location {map_id, entry: {map_id, spawn_index: 0}} (v0 had no arrival reference), play_time ->
##   play_time_s. Fields v0 lacks are left out so CharacterState.from_dict's defaults apply; the inventory,
##   equipment and quest blobs are passed through unchanged (their modules own their format).
func _v0_to_v1(old: Dictionary) -> Dictionary:
	if not (old.has("name") and old.has("level")):
		return {}
	var character := {}
	var renames := {
		"name": "name", "job": "job", "level": "level", "exp": "exp", "hp": "hp", "mp": "mp",
		"max_hp": "base_max_hp", "max_mp": "base_max_mp", "available_ap": "ap", "sp": "sp", "fame": "fame",
		"mesos": "mesos", "inventory": "inventory", "equipment": "equipment", "quest_state": "quests",
		"respawn_reference": "respawn_reference", "play_time": "play_time_s",
	}
	for old_key in renames:
		if old.has(old_key):
			character[renames[old_key]] = old[old_key]
	var stats := {}
	for key in CharacterState.STAT_KEYS:
		if old.has(key):
			stats[key] = old[key]
	if not stats.is_empty():
		character["base_stats"] = stats
	var location := {}
	var map_id := SaveDocument.as_text(old.get("current_map", ""))
	if map_id != "":
		location = {"map_id": map_id, "entry": {"map_id": map_id, "spawn_index": 0}}
	character["location"] = location
	var world := {
		"location": location.duplicate(true),
		"respawn_reference": SaveDocument.as_text(old.get("respawn_reference", "")),
	}
	return {
		"save_version": 1,
		"game": SaveDocument.GAME_ID,
		"saved_at": SaveDocument.as_text(old.get("saved_at", "")),
		"character": character,
		"world": world,
		"meta": {},
	}
