class_name MisoIconResolver
extends RefCounted
## Item and skill pictures from icon packs (docs/runtime/UI.md "Icon packs", docs/adr/0001-icon-packs.md). An icon
## pack is a folder in format 1: pack.json, items/<game_item_id>/<variant>.png and skills/<skill_id>/<variant>.png.
## The resolver asks its packs in order; the first one with a PNG for the id and variant wins. When none has one,
## art() returns null and MisoItemIcon / MisoSkillIcon draw their procedural picture, the base layer under every pack.
##
##   var art := MisoIconResolver.shared().art(MisoIconResolver.ITEMS, "2000000")    # Red Potion, or null
##   var rect := art.rect_in(Vector2(64, 64))                                       # drawn at 2x: (6, 4, 54, 60)
##
## shared() serves the packs listed in data/misostory/icon_packs.json, under assets/icon_packs/. A pack under res://
## (the bundled maplestory_io) loads its imported textures through ResourceLoader, since an exported build holds only
## the imported copies; a pack rooted anywhere else (a test's fake pack, a player's own pack) loads raw PNGs with
## Image.load_from_file. A missing pack folder, a pack.json without its PNGs (a fresh clone) and a missing entry all
## mean "no art". Every lookup is cached, hit or miss, so drawing never touches the disk.

## The pack list (names, highest priority first) and the folder the names live in.
const LIST_PATH := "res://data/misostory/icon_packs.json"
const PACKS_DIR := "res://assets/icon_packs"
const MANIFEST := "pack.json"
## The pack format this resolver reads; a pack.json of another format is skipped with a warning.
const FORMAT := 1
## Kinds (a pack's subfolders) and the plain variant. The other variants (iconRaw; iconMouseOver, iconDisabled) are
## in the packs but not drawn yet (#51).
const ITEMS := "items"
const SKILLS := "skills"
const ICON := "icon"
## The icon cell in px. Item art is placed in it by its origin, skill art (32 x 32) fills it; the cell is drawn at
## whole multiples (cell_transform).
const CELL := 32


## A pack picture: its texture and where the texture's top-left sits in the 32 x 32 cell, in cell px. It may lie
## outside the cell: art larger than the cell (The Spear, 33 x 35) pokes out of it and is not clipped.
class Art extends RefCounted:
	var texture: Texture2D
	var offset: Vector2i

	func _init(p_texture: Texture2D, p_offset: Vector2i) -> void:
		texture = p_texture
		offset = p_offset

	## The rect the texture covers in a box of `box` px (see MisoIconResolver.cell_transform).
	func rect_in(box: Vector2, fill: bool = false) -> Rect2:
		var xf := MisoIconResolver.cell_transform(box, fill)
		return Rect2(xf * Vector2(offset), Vector2(texture.get_size()) * xf.get_scale())


static var _shared: MisoIconResolver = null

## The pack folders asked, highest priority first.
var roots: PackedStringArray = []
## The usable packs, in order: {root, manifest (pack.json), imported (a res:// pack)}.
var _packs: Array[Dictionary] = []
## "<kind>/<id>/<variant>" -> Art, or null for a miss.
var _cache: Dictionary = {}


## A resolver over the pack folders `pack_roots`, highest priority first (injected by tests). Each manifest is read
## here once; the PNGs are loaded on their first lookup.
func _init(pack_roots: PackedStringArray = PackedStringArray()) -> void:
	roots = pack_roots
	for root in roots:
		var manifest := _read_manifest(root)
		if not manifest.is_empty():
			_packs.append({"root": root, "manifest": manifest, "imported": root.begins_with("res://")})


## The resolver the UI draws from: the packs listed in icon_packs.json, built on first use.
static func shared() -> MisoIconResolver:
	if _shared == null:
		_shared = MisoIconResolver.new(listed_roots())
	return _shared


## Replaces the shared resolver (tests: a fake pack). null goes back to the listed packs on the next shared().
static func set_shared(resolver: MisoIconResolver) -> void:
	_shared = resolver


## The folders of the packs the list names, in its order ([] when the list is missing or malformed).
static func listed_roots(list_path: String = LIST_PATH, packs_dir: String = PACKS_DIR) -> PackedStringArray:
	var out := PackedStringArray()
	if not FileAccess.file_exists(list_path):
		return out
	var list: Variant = JSON.parse_string(FileAccess.get_file_as_string(list_path))
	var names: Variant = (list as Dictionary).get("packs", []) if list is Dictionary else []
	for n: Variant in (names if names is Array else []):
		if n is String and (n as String).is_valid_filename():
			out.append(packs_dir.path_join(n))
	return out


## The picture for an id and variant from the first pack that has one, or null (the procedural base draws).
func art(kind: String, id: String, variant: String = ICON) -> Art:
	var key := "%s/%s/%s" % [kind, id, variant]
	if _cache.has(key):
		return _cache[key]
	var found: Art = null
	# Ids and variants become path parts: "?" (an effect with no skill) or "../x" never reaches the disk.
	if id.is_valid_filename() and variant.is_valid_filename():
		for pack: Dictionary in _packs:
			var tex := _texture(pack, "%s/%s/%s.png" % [kind, id, variant])
			if tex == null:
				continue
			var origin: Variant = null
			if kind == ITEMS:
				origin = _entry(pack.manifest, kind, id, variant).get("origin", null)
			found = Art.new(tex, cell_offset(Vector2i(tex.get_size()), origin))
			break
	_cache[key] = found
	return found


## Where art of `size` px sits in the cell: by its origin [x, y] (the pack's iconOrigin, measured from the art's
## top-left to the cell's bottom-left), so the top-left is (-x, 32 - y) and every icon's bottom rests on the cell's
## bottom edge; without an origin, centred. Red Potion (27 x 30, origin [-3, 30]) sits at (3, 2).
static func cell_offset(size: Vector2i, origin: Variant) -> Vector2i:
	if origin is Array and (origin as Array).size() == 2 and _is_num(origin[0]) and _is_num(origin[1]):
		return Vector2i(-int(origin[0]), CELL - int(origin[1]))
	return (Vector2i(CELL, CELL) - size) / 2


## The transform from cell px to the px of a box `box` px large. The cell is scaled by a whole number (at least 1x:
## a box under 32 px lets the art overflow it) and centred on whole pixels, so art drawn with nearest filtering stays
## pixel-exact. With `fill` the cell is scaled to the box's shorter side instead (the effects bar's one exception).
static func cell_transform(box: Vector2, fill: bool = false) -> Transform2D:
	var side := minf(box.x, box.y)
	var k := side / CELL if fill else float(maxi(1, floori(side / CELL)))
	var at := (box - Vector2(CELL, CELL) * k) * 0.5
	return Transform2D(0.0, Vector2(k, k), 0.0, at if fill else at.floor())


# --- loading -------------------------------------------------------------------------------------------------------

## A pack's pack.json, or {} when the folder holds none (a pack that is not there) or it is not format 1.
static func _read_manifest(root: String) -> Dictionary:
	var path := root.path_join(MANIFEST)
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary) or not _is_num((data as Dictionary).get("format")) or int(data.format) != FORMAT:
		push_warning("[MisoIconResolver] %s is not an icon pack of format %d; skipped" % [path, FORMAT])
		return {}
	return data


## A PNG of a pack, loaded once by art(): the imported texture of a res:// pack, else the raw file.
static func _texture(pack: Dictionary, rel: String) -> Texture2D:
	var path := String(pack.root).path_join(rel)
	if pack.imported:
		# Never FileAccess here: an exported build holds only the imported copy, not the .png.
		return load(path) as Texture2D if ResourceLoader.exists(path) else null
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null


## manifest[kind][id][variant] ({} when any level is missing or malformed).
static func _entry(manifest: Dictionary, kind: String, id: String, variant: String) -> Dictionary:
	var node: Variant = manifest
	for k in [kind, id, variant]:
		node = (node as Dictionary).get(k, null) if node is Dictionary else null
	return node if node is Dictionary else {}


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
