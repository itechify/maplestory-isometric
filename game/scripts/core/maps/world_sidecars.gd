class_name WorldSidecars
extends RefCounted
## Reads the Blender export's gameplay sidecars: game/assets/world/index.json and one <chunk>.json per chunk
## (docs/runtime/blender_export.md, "Gameplay sidecar"). The sidecar is the gameplay-marker authority for M1/M2
## (MAP_ARCHITECTURE.md section 4.10 decision box). Pure file reading; every field is read with a default, so
## additive exporter changes (new fields) never break the runtime.

const DEFAULT_DIR := "res://assets/world"

var dir: String = DEFAULT_DIR
var index: Dictionary = {}
## chunk name -> parsed sidecar Dictionary.
var chunks: Dictionary = {}
var load_errors: PackedStringArray = []


## True when an export is present (index.json exists). The test mirror omits assets/world unless INCLUDE_WORLD=1.
static func exists(path: String = DEFAULT_DIR) -> bool:
	return FileAccess.file_exists(path.path_join("index.json"))


## Reads index.json and every chunk sidecar it lists (plus any <chunk>.json next to it that the index misses).
static func load_dir(path: String = DEFAULT_DIR) -> WorldSidecars:
	var s := WorldSidecars.new()
	s.dir = path
	var idx: Variant = _read_json(path.path_join("index.json"), s.load_errors)
	if idx is Dictionary:
		s.index = idx
	var names: Array = []
	var listed: Variant = s.index.get("chunks", {})
	if listed is Dictionary:
		names = (listed as Dictionary).keys()
	elif listed is Array:
		for c in listed:
			if c is Dictionary and c.has("chunk"):
				names.append(String(c.chunk))
	for f in DirAccess.get_files_at(path):
		if f.get_extension() == "json" and f != "index.json" and not (f.get_basename() in names):
			names.append(f.get_basename())
	names.sort()
	for n in names:
		var file := path.path_join(String(n) + ".json")
		if not FileAccess.file_exists(file):
			s.load_errors.append("index.json lists chunk %s but %s is missing" % [n, file])
			continue
		var data: Variant = _read_json(file, s.load_errors)
		if data is Dictionary:
			s.chunks[String(n)] = data
	return s


func chunk(chunk_name: String) -> Dictionary:
	return chunks.get(chunk_name, {})


func has_chunk(chunk_name: String) -> bool:
	return chunks.has(chunk_name)


## Chunk names of a sidecar kind ("map", "interior", "world", "library").
func chunks_of_kind(kind: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for n in chunks:
		if String((chunks[n] as Dictionary).get("kind", "")) == kind:
			out.append(String(n))
	out.sort()
	return out


## Every chunk with geometry to place in the world (maps, interiors, world chunks; not the library).
func geometry_chunks() -> PackedStringArray:
	var out: PackedStringArray = []
	for n in chunks:
		if String((chunks[n] as Dictionary).get("kind", "")) != "library":
			out.append(String(n))
	out.sort()
	return out


## res:// path of a chunk's visual or collision glb ("" when the sidecar lists none).
func file_path(chunk_name: String, which: String) -> String:
	var files: Dictionary = chunk(chunk_name).get("files", {})
	var f := String(files.get(which, ""))
	return dir.path_join(f) if f != "" else ""


## index.json content hashes of a chunk ({} when absent).
func content_hash(chunk_name: String) -> Dictionary:
	var listed: Variant = index.get("chunks", {})
	if listed is Dictionary:
		var entry: Dictionary = (listed as Dictionary).get(chunk_name, {})
		var h: Variant = entry.get("content_hash", {})
		return h if h is Dictionary else {}
	return {}


func environment() -> Dictionary:
	var e: Variant = index.get("environment", {})
	return e if e is Dictionary else {}


## Sea level: index.json sea_level_y, else the World_SkyAndSea sidecar's, else NAN.
func sea_level_y() -> float:
	if index.has("sea_level_y"):
		return float(index.sea_level_y)
	for n in chunks:
		var c: Dictionary = chunks[n]
		if c.has("sea_level_y"):
			return float(c.sea_level_y)
	return NAN


# --- tolerant field parsers (shared by MapDefinitions and the world) ---------------------------------------

## A sidecar xform (12 floats: basis x, y, z columns, then origin) -> Transform3D; identity when malformed.
static func xform(a: Variant) -> Transform3D:
	if not (a is Array) or (a as Array).size() < 12:
		return Transform3D.IDENTITY
	var v: Array = a
	return Transform3D(Basis(Vector3(float(v[0]), float(v[1]), float(v[2])), Vector3(float(v[3]), float(v[4]), float(v[5])),
		Vector3(float(v[6]), float(v[7]), float(v[8]))), Vector3(float(v[9]), float(v[10]), float(v[11])))


## [x, y, z] -> Vector3 (fallback when malformed).
static func vec3(a: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if not (a is Array) or (a as Array).size() < 3:
		return fallback
	var v: Array = a
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


## [[x, z], ...] -> PackedVector2Array.
static func poly_xz(a: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not (a is Array):
		return out
	for p in a:
		if p is Array and (p as Array).size() >= 2:
			out.append(Vector2(float(p[0]), float(p[1])))
	return out


## A marker's transform: its "xform" when present, else "position" + "yaw_deg".
static func marker_xform(m: Dictionary) -> Transform3D:
	if m.get("xform", null) is Array:
		return xform(m.xform)
	var pos := vec3(m.get("position", null))
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(m.get("yaw_deg", 0.0)))), pos)


static func _read_json(path: String, errors: PackedStringArray) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		errors.append("%s: cannot read" % path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
