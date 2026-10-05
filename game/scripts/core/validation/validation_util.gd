class_name ValidationUtil
extends RefCounted
## Small helpers shared by the validation checks. The validator reads data that may be broken in any way, so every
## comparison has to survive mismatched types: in Godot 4.7 `1 == "1"` is a script error, not false.


## Type-safe equality: false (never a script error) when the types differ; ints and floats compare by value.
static func same(a: Variant, b: Variant) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
		return float(a) == float(b)
	return ta == tb and a == b


## True for a String with visible content.
static func non_empty(v: Variant) -> bool:
	return v is String and String(v).strip_edges() != ""


## v if it is an Array, else an empty Array (so loops over optional fields stay short).
static func as_array(v: Variant) -> Array:
	return v if v is Array else []


## True for a JSON number (parsed as float, or int when built in code).
static func is_number(v: Variant) -> bool:
	return v is float or v is int


## The canonical domain names of a ContentDB, sorted, without the "" bucket of root-level single files.
static func canonical_domains(db: ContentDB) -> PackedStringArray:
	var out: PackedStringArray = []
	for d in db.canonical:
		if str(d) != "":
			out.append(str(d))
	out.sort()
	return out
