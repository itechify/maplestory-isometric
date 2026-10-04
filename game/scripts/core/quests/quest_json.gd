class_name QuestJson
extends RefCounted
## Null-safe readers for parsed JSON values, shared by the quest, NPC and dialogue modules.
##
## JSON numbers parse as float, keys that exist with a null value make Dictionary.get() return null, and arrays are
## untyped. These helpers turn any of that into the typed value the caller expects, so a canonical `null` never
## crashes a typed assignment.


## A String, or `fallback` when the value is null.
static func s(v: Variant, fallback: String = "") -> String:
	if v == null:
		return fallback
	return str(v)


## An int (floats are truncated, numeric strings parsed), or `fallback` when null or not numeric.
static func i(v: Variant, fallback: int = 0) -> int:
	match typeof(v):
		TYPE_INT:
			return v
		TYPE_FLOAT:
			return int(v)
		TYPE_BOOL:
			return 1 if v else 0
		TYPE_STRING, TYPE_STRING_NAME:
			var t := String(v)
			if t.is_valid_int():
				return t.to_int()
			if t.is_valid_float():
				return int(t.to_float())
	return fallback


## A float, or `fallback` when null or not numeric.
static func f(v: Variant, fallback: float = 0.0) -> float:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			return float(v)
		TYPE_STRING, TYPE_STRING_NAME:
			var t := String(v)
			if t.is_valid_float():
				return t.to_float()
	return fallback


## A bool (null -> `fallback`).
static func b(v: Variant, fallback: bool = false) -> bool:
	if v == null:
		return fallback
	if typeof(v) == TYPE_BOOL:
		return v
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return v != 0
	return fallback


## An Array (null or non-array -> empty).
static func arr(v: Variant) -> Array:
	if v is Array:
		return v
	return []


## A Dictionary (null or non-dictionary -> empty).
static func dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v
	return {}


## A PackedStringArray from an array of scalars (null entries skipped).
static func strings(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if v is Array or v is PackedStringArray:
		for e: Variant in v:
			if e != null:
				out.append(str(e))
	elif v is String and not String(v).is_empty():
		out.append(String(v))
	return out
