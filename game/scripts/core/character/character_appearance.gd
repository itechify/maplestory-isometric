class_name CharacterAppearance
extends RefCounted
## A character's look (#67): hair style, face and skin, each an index into the art pack's customization.json (hair
## files, faces, skin palette), chosen at creation only (Maple Island has no salon). An Adaptation recorded in
## data/misostory/appearance.json (decision #59, unverified); docs/runtime/SAVES.md has the save shape.
##
##   {"hair_style": 0..5, "face": 0..2, "skin": 0..3}
##
## Each gender's default is its Beginner preset's own look (the pack's base_recipe of Beginner_Male and
## Beginner_Female); a character with no gender ("": quick start, tools) gets the male default, as the player model
## shows the male preset for it (PlayerVisual.DEFAULT_PRESET). These constants are the runtime source because
## CharacterState.from_dict and the save migrations have no ContentDB; test_appearance_data pins them against the
## data file and, with the pack installed, against the pack.

const HAIR_STYLE := "hair_style"
const FACE := "face"
const SKIN := "skin"
const KEYS: PackedStringArray = [HAIR_STYLE, FACE, SKIN]
## How many choices each key has (customization.json: 6 hair files, 3 faces, 4 skin colours).
const CHOICES := {HAIR_STYLE: 6, FACE: 3, SKIN: 4}
const DEFAULTS := {
	"male": {HAIR_STYLE: 3, FACE: 0, SKIN: 0},
	"female": {HAIR_STYLE: 2, FACE: 0, SKIN: 3},
}
const DEFAULT_GENDER := "male"


## The default look of a CharacterState.gender (a copy).
static func default_for(gender: String) -> Dictionary:
	return (DEFAULTS.get(gender, DEFAULTS[DEFAULT_GENDER]) as Dictionary).duplicate()


## How many choices `key` has (0 for an unknown key).
static func choices(key: String) -> int:
	return int(CHOICES.get(key, 0))


## A complete look: every valid choice of `value` kept, every missing, unknown or out-of-range one replaced by the
## gender's default; unknown keys are dropped.
static func resolve(value: Variant, gender: String) -> Dictionary:
	var out := default_for(gender)
	if not (value is Dictionary):
		return out
	for key in KEYS:
		var v: Variant = (value as Dictionary).get(key, null)
		if _valid(key, v):
			out[key] = int(v)
	return out


## Why `value` is not a look new_game() accepts (empty when it is, or when none is given: the gender's default).
static func problems(value: Variant) -> PackedStringArray:
	var out: PackedStringArray = []
	if value == null:
		return out
	if not (value is Dictionary):
		out.append("appearance must be an object {%s}" % ", ".join(KEYS))
		return out
	for key in KEYS:
		var d: Dictionary = value
		if d.has(key) and not _valid(key, d[key]):
			out.append("appearance %s must be a whole number from 0 to %d" % [key, choices(key) - 1])
	return out


static func _valid(key: String, v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return int(v) >= 0 and int(v) < choices(key)
	if typeof(v) == TYPE_FLOAT and is_finite(float(v)) and float(v) == floorf(float(v)):
		return int(v) >= 0 and int(v) < choices(key)
	return false
