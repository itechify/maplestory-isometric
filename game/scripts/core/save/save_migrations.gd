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
const CURRENT_VERSION := 3
## Version reported for a document whose "save_version" is present but not a whole number >= 0.
const INVALID_VERSION := -1

## from_version -> Callable
var _steps: Dictionary = {}
## from_version -> human-readable step name (reported in SaveLoadResult.migrations_applied)
var _names: Dictionary = {}


func _init(include_builtin: bool = true) -> void:
	if include_builtin:
		register(0, "v0_flat_character_to_v1_envelope", _v0_to_v1)
		register(1, "v1_typed_quickslots_quest_rewards", _v1_to_v2)
		register(2, "v2_appearance_default_preset", _v2_to_v3)


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


## v1 -> v2 (Iteration Three, ITERATION_THREE_CONTRACTS.md C3). Only the character block is reshaped; the envelope,
## world, location, inventory and equipment pass through unchanged. A part that has the wrong type is left as it is,
## so SaveDocument's type check still reports the file as corrupt.
##   - quickslots: a bare item id (String, or a number from a hand edit) becomes {"kind": "item", "id"}; a binding
##     that already has that shape is kept; anything else (null, an empty id, a container) is dropped, because v1
##     could only bind item ids.
##   - quests: "format" 2, and every completed entry without "rewards_received" gets {"recorded": false}. v1 never
##     recorded what a completion gave (random picks included), and nothing may be inferred from the inventory, so
##     the record says exactly that. In-progress entries are untouched.
##   - effects: cleared. v1 had no effect producer (every Iteration Two save holds []), and the shape it allowed used
##     per-process clock times that mean nothing after a restart.
##   - cooldowns {} and natural_recovery {"hp_rest_s": 0.0} are written when absent; values already present (a late
##     v1 build wrote both) are kept.
func _v1_to_v2(doc: Dictionary) -> Dictionary:
	var cd: Variant = doc.get("character", null)
	if not (cd is Dictionary):
		return doc
	var c: Dictionary = cd
	var slots: Variant = c.get("quickslots", null)
	if slots is Dictionary:
		var typed := {}
		for key: Variant in slots:
			var v: Variant = (slots as Dictionary)[key]
			if v is Dictionary:
				var kind := str((v as Dictionary).get("kind", ""))
				var bound := SaveDocument.as_text((v as Dictionary).get("id", ""))
				if kind in ["item", "skill"] and bound != "":
					typed[str(key)] = {"kind": kind, "id": bound}
				continue
			var id := SaveDocument.as_text(v)
			if id != "":
				typed[str(key)] = {"kind": "item", "id": id}
		c["quickslots"] = typed
	var quests: Variant = c.get("quests", null)
	if quests is Dictionary:
		var q: Dictionary = quests
		q["format"] = 2
		var entries: Variant = q.get("quests", null)
		if entries is Dictionary:
			for quest_id: Variant in entries:
				var e: Variant = (entries as Dictionary)[quest_id]
				if e is Dictionary and str((e as Dictionary).get("status", "")) == "completed" \
						and not (e as Dictionary).has("rewards_received"):
					(e as Dictionary)["rewards_received"] = {"recorded": false}
	if c.get("effects", null) is Array:
		c["effects"] = []
	if not c.has("cooldowns"):
		c["cooldowns"] = {}
	if not c.has("natural_recovery"):
		c["natural_recovery"] = {"hp_rest_s": 0.0}
	return doc


## The looks the v2 -> v3 step gives (frozen here: the step must keep meaning what it meant when v3 shipped, whatever
## CharacterAppearance.DEFAULTS becomes later). The pack's base_recipe of Beginner_Male and Beginner_Female.
const V3_DEFAULT_LOOKS := {
	"male": {"hair_style": 3, "face": 0, "skin": 0},
	"female": {"hair_style": 2, "face": 0, "skin": 3},
}
## The look of a v2 character whose gender is neither (""): the male preset, which the game showed for it.
const V3_DEFAULT_GENDER := "male"


## v2 -> v3 (#67: hair, face and skin chosen at creation). v2 characters had no look, so each gets its gender's
## default Beginner preset look (V3_DEFAULT_LOOKS; no or an unknown gender: the male one) as "appearance". Nothing
## else changes. A character block that is not an object is left as it is (SaveDocument reports it as corrupt).
func _v2_to_v3(doc: Dictionary) -> Dictionary:
	var cd: Variant = doc.get("character", null)
	if not (cd is Dictionary):
		return doc
	var gender := SaveDocument.as_text((cd as Dictionary).get("gender", ""))
	(cd as Dictionary)["appearance"] = (V3_DEFAULT_LOOKS.get(gender, V3_DEFAULT_LOOKS[V3_DEFAULT_GENDER]) as Dictionary).duplicate()
	return doc
