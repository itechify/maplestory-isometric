class_name ContentDB
extends RefCounted
## Loads MisoStory's local content: canonical MeowDB-derived data and MisoStory adaptation data.
##
## Layout (one entity per JSON file, keyed by file basename):
##   res://data/canonical/<domain>/<id>.json   MapleStory facts (MeowDB MS Classic), each with a "source" block
##   res://data/misostory/<domain>/<id>.json   isometric 3D adaptation (positions, visuals, spawn regions, ...)
##   res://data/misostory/<name>.json          single-file adaptation tables (e.g. map_id_crosswalk.json)
##
## The game never talks to MeowDB; this cache ships with the game. The same loader is used by the runtime, the unit
## tests and tools/validate_data.gd, so a broken reference fails validation exactly where the game would fail.

const CANONICAL_ROOT := "res://data/canonical"
const MISO_ROOT := "res://data/misostory"

## domain -> { id -> Dictionary }
var canonical: Dictionary = {}
## domain -> { id -> Dictionary }; single-file tables live under key "" -> { basename -> data }
var miso: Dictionary = {}
var load_errors: PackedStringArray = []
var loaded := false


func load_all(canonical_root: String = CANONICAL_ROOT, miso_root: String = MISO_ROOT) -> ContentDB:
	canonical = _load_tree(canonical_root)
	miso = _load_tree(miso_root)
	loaded = true
	return self


# --- generic access -------------------------------------------------------------------------------------------

func has(domain: String, id: Variant) -> bool:
	return canonical.get(domain, {}).has(str(id))


func get_entity(domain: String, id: Variant) -> Dictionary:
	return canonical.get(domain, {}).get(str(id), {})


func ids(domain: String) -> PackedStringArray:
	var out := PackedStringArray(canonical.get(domain, {}).keys())
	out.sort()
	return out


func domain(domain_name: String) -> Dictionary:
	return canonical.get(domain_name, {})


func miso_entity(domain_name: String, id: Variant) -> Dictionary:
	return miso.get(domain_name, {}).get(str(id), {})


func miso_table(basename: String) -> Variant:
	return miso.get("", {}).get(basename, null)


# --- typed conveniences ---------------------------------------------------------------------------------------

func map(id: Variant) -> Dictionary: return get_entity("maps", id)
func monster(id: Variant) -> Dictionary: return get_entity("monsters", id)
func item(id: Variant) -> Dictionary: return get_entity("items", id)
func npc(id: Variant) -> Dictionary: return get_entity("npcs", id)
func quest(id: Variant) -> Dictionary: return get_entity("quests", id)
func shop(id: Variant) -> Dictionary: return get_entity("shops", id)
func drop_table(monster_id: Variant) -> Dictionary: return get_entity("drops", monster_id)
func formula(name: String) -> Dictionary: return get_entity("formulas", name)


# --- loading --------------------------------------------------------------------------------------------------

func _load_tree(root: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(root)
	if dir == null:
		load_errors.append("missing data root %s" % root)
		return out
	var singles := {}
	for f in dir.get_files():
		if f.get_extension() == "json":
			singles[f.get_basename()] = _read_json(root.path_join(f))
	if not singles.is_empty():
		out[""] = singles
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		out[sub] = _load_domain(root.path_join(sub))
	return out


func _load_domain(path: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	for f in dir.get_files():
		# Exported builds list "<file>.json" normally; tolerate remapped names just in case.
		var name := f.trim_suffix(".remap")
		if name.get_extension() != "json":
			continue
		var data: Variant = _read_json(path.path_join(name))
		if data is Dictionary:
			out[name.get_basename()] = data
		else:
			load_errors.append("%s: top level is not an object" % path.path_join(name))
	for sub in dir.get_directories():
		# Nested folders (e.g. formulas/<group>/) are flattened as "<sub>/<basename>".
		var nested := _load_domain(path.path_join(sub))
		for k in nested:
			out["%s/%s" % [sub, k]] = nested[k]
	return out


func _read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		load_errors.append("%s: cannot read (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		load_errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
