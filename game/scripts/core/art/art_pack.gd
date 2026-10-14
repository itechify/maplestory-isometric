class_name ArtPack
extends RefCounted
## The pinned art pack (Project art: Jarvis's 3D asset pack, ADR 0002), looked up by canonical ID. Every lookup goes
## through the pack's asset_index.json and manifests, never through file names (wearable files are named by MeowDB id,
## equipment files by game item id; only the index is consistent). Aliases resolve explicitly from
## environment/source_catalog_mapping.json (Sign_Board and Signpost_Notice share noticeboard.glb).
##
##   var art := ArtPack.load_installed()          # res://assets/art_pack, from data/misostory/art_pack.json
##   if art.present():
##       var shanks := art.instance(ArtPack.NPC, "15")      # null when the model is missing: keep the placeholder
##   art.model(ArtPack.ITEM, "1302000")           # by game_item_id or canonical item id -> "res://.../item_..glb"
##   art.bounds(ArtPack.ITEM, "541")              # AABB as imported, from godot_validation.json (y -0.26..0.94)
##   art.ground_offset_y(ArtPack.ITEM, "541")     # 0.26: raise the grip-centred sword by this to rest on the ground
##
## Kinds and their IDs:
##   NPC        canonical NPC id ("15" Shanks)                       asset_index canonical_npcs
##   MONSTER    canonical monster id ("2" Snail)                     asset_index canonical_monsters
##   ITEM       canonical item id or game_item_id                    asset_index canonical_items (icon() too)
##   WEARABLE   canonical item id or game_item_id of a wearable      characters/wearables_manifest.json
##   BREAKABLE  canonical breakable id ("0000001" Wooden Box)        monsters/manifest.json (category breakable)
##   KIT        a kit @asset name ("Sign_Board")                     environment/source_catalog_mapping.json
##   PRESET     a Beginner preset name ("Beginner_Female")           characters/manifest.json (type player)
##   HAIR       hair style index ("0".."5")                          characters/customization.json hair.files
##   FACE       face style ("bright", "determined", "sleepy")        characters/customization.json faces
##   MESO       "" (the one meso model)                              monsters/manifest.json (drop without an item)
##   EFFECT     effect name ("HitSpark")                             monsters/manifest.json (category effect)
## skin_color(i) is skin palette entry i, converted to sRGB (materials hold sRGB albedo).
##
## Models are imported resources: existence is checked with ResourceLoader.exists, which also holds in exported
## builds. Without the pack (a fresh clone, unit tests) present() is false and every lookup is empty, so callers keep
## the procedural placeholders. coverage() is the check that every ID the game requires has a model.

const PIN := "res://data/misostory/art_pack.json"

const NPC := "npc"
const MONSTER := "monster"
const ITEM := "item"
const WEARABLE := "wearable"
const BREAKABLE := "breakable"
const KIT := "kit"
const PRESET := "preset"
const HAIR := "hair"
const FACE := "face"
const MESO := "meso"
const EFFECT := "effect"

## coverage() statuses.
const COVERED := "covered"
const MISSING := "missing"
const NO_PACK := "no pack"

var root := ""
## kind -> {id: pack-relative path}
var _models: Dictionary = {}
## kind -> {id: pack-relative icon path}
var _icons: Dictionary = {}
var _skin: Array = []
## customization.json faces[].style, in order (a CharacterAppearance face index picks one).
var _face_styles: PackedStringArray = []
## Player preset name -> characters/manifest.json base_recipe {skin, hair_color, hair_style, outfit, palette, hat, face}.
var _recipes: Dictionary = {}
var _present := false
## godot_validation.json files[] by pack-relative path (loaded on first bounds() / ground_offset_y()).
var _validation_by_file: Dictionary = {}


static func _pin() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PIN))
	return data if data is Dictionary else {}


## Where the fetch script installs the pack (art_pack.json install_dir).
static func install_dir() -> String:
	return String(_pin().get("install_dir", "res://assets/art_pack"))


## The one uniform factor applied on import to characters and their parts (art_pack.json character_scale.factor).
static func character_scale() -> float:
	return float(_pin().get("character_scale", {}).get("factor", 1.0))


static func load_installed() -> ArtPack:
	return load_from(install_dir())


static func load_from(dir: String) -> ArtPack:
	var p := ArtPack.new()
	p.root = dir.trim_suffix("/")
	var index := _json(p.root.path_join("asset_index.json"))
	if index.is_empty():
		return p
	p._present = true
	for kind in [NPC, MONSTER, ITEM, WEARABLE, BREAKABLE, KIT, PRESET, HAIR, FACE, MESO, EFFECT]:
		p._models[kind] = {}
		p._icons[kind] = {}
	for n in index.get("canonical_npcs", []):
		p._add(NPC, n.get("id"), n.get("file"))
	for m in index.get("canonical_monsters", []):
		p._add(MONSTER, m.get("id"), m.get("file"))
	for it in index.get("canonical_items", []):
		for key in [it.get("id"), it.get("game_item_id")]:
			p._add(ITEM, key, it.get("file"))
			if it.get("icon") is String:
				p._icons[ITEM][str(key)] = it.icon
	for w in _json(p.root.path_join("characters/wearables_manifest.json")).get("assets", []):
		for key in [w.get("id"), w.get("game_item_id")]:
			p._add(WEARABLE, key, _under("characters", w.get("file")))
	for a in _json(p.root.path_join("monsters/manifest.json")).get("assets", []):
		var file: Variant = _under("monsters", a.get("glb"))
		match String(a.get("category", "")):
			"breakable":
				p._add(BREAKABLE, a.get("canonical_id"), file)
			"effect":
				p._add(EFFECT, a.get("name"), file)
			"drop":
				if a.get("canonical_id") == null and a.get("item_id") == null:
					p._add(MESO, "", file)
	for e in _json(p.root.path_join("environment/source_catalog_mapping.json")).get("entries", []):
		p._add(KIT, e.get("source_asset_id"), e.get("output_file"))
	for c in _json(p.root.path_join("characters/manifest.json")).get("assets", []):
		if String(c.get("type", "")) == "player":
			p._add(PRESET, c.get("name"), _under("characters", c.get("file")))
			if c.get("base_recipe") is Dictionary:
				p._recipes[str(c.get("name"))] = (c.get("base_recipe") as Dictionary).duplicate()
	var custom := _json(p.root.path_join("characters/customization.json"))
	var hair_files: Array = custom.get("hair", {}).get("files", [])
	for i in hair_files.size():
		p._add(HAIR, str(i), _under("characters", hair_files[i]))
	for f in custom.get("faces", []):
		p._add(FACE, f.get("style"), _under("characters", f.get("file")))
		p._face_styles.append(str(f.get("style")))
	p._skin = custom.get("skin", {}).get("colors_linear", [])
	return p


func present() -> bool:
	return _present


## The model's res:// path, or "" when the pack does not map that ID.
func model(kind: String, id: String) -> String:
	var rel: Variant = _models.get(kind, {}).get(id, null)
	return root.path_join(rel) if rel is String and rel != "" else ""


## The rendered icon's res:// path, or "" (items only).
func icon(kind: String, id: String) -> String:
	var rel: Variant = _icons.get(kind, {}).get(id, null)
	return root.path_join(rel) if rel is String and rel != "" else ""


## The IDs the pack maps for one kind, sorted.
func ids(kind: String) -> PackedStringArray:
	var out := PackedStringArray(_models.get(kind, {}).keys())
	out.sort()
	return out


## A fresh instance of the model, or null when it is unmapped or not imported.
func instance(kind: String, id: String) -> Node3D:
	var path := model(kind, id)
	if path == "" or not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	return scene.instantiate() as Node3D if scene != null else null


## The model's bounds as the game imports it, from the pack's godot_validation.json (an empty AABB when the pack has
## none). The pack measured raw imports; ArtImport scales characters and their parts (characters/*) by the character
## factor, so their bounds are scaled the same way here.
func bounds(kind: String, id: String) -> AABB:
	var v := _validation(kind, id)
	if v.is_empty() or not (v.get("bounds_min") is Array) or not (v.get("bounds_max") is Array):
		return AABB()
	var k := _import_scale(kind, id)
	var lo := _vec3(v.bounds_min) * k
	return AABB(lo, _vec3(v.bounds_max) * k - lo)


## How far the model must be raised to sit on the ground (godot_validation.json loot_ground_offset_y, = -bounds
## min y: 0.26 for a grip-centred sword), in the imported model's space; 0 when the pack has none.
func ground_offset_y(kind: String, id: String) -> float:
	var v := _validation(kind, id)
	return float(v.get("loot_ground_offset_y", 0.0)) * _import_scale(kind, id)


## godot_validation.json's entry for the model's file ({} when absent). Read once, on first use.
func _validation(kind: String, id: String) -> Dictionary:
	var rel: Variant = _models.get(kind, {}).get(id, null)
	if not (rel is String):
		return {}
	if _validation_by_file.is_empty():
		for f in _json(root.path_join("godot_validation.json")).get("files", []):
			if f is Dictionary:
				_validation_by_file[String(f.get("file", ""))] = f
	return _validation_by_file.get(rel, {})


func _import_scale(kind: String, id: String) -> float:
	var rel: Variant = _models.get(kind, {}).get(id, null)
	return character_scale() if rel is String and String(rel).begins_with("characters/") else 1.0


static func _vec3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() >= 3 else Vector3.ZERO


## How many skin colours the palette has.
func skin_count() -> int:
	return _skin.size()


## The face styles in customization.json order (FACE ids; a CharacterAppearance face index picks one).
func face_styles() -> PackedStringArray:
	return _face_styles.duplicate()


## A player preset's look as the pack built it (characters/manifest.json base_recipe: "skin", "hair_color",
## "hair_style", "face", ... as indices); {} when unknown.
func base_recipe(preset_name: String) -> Dictionary:
	return (_recipes.get(preset_name, {}) as Dictionary).duplicate()


## Skin palette entry `index` as an sRGB colour (white when out of range).
func skin_color(index: int) -> Color:
	if index < 0 or index >= _skin.size():
		return Color.WHITE
	var c: Array = _skin[index]
	return Color(float(c[0]), float(c[1]), float(c[2])).linear_to_srgb()


## Checks that every required ID has a model: {status: COVERED | MISSING | NO_PACK, checked, missing: [{kind, id,
## why}]}. `required` is kind -> [ids] (see required_ids); `exists` decides whether a model path is there
## (default ResourceLoader.exists: imported, as in an exported build).
func coverage(required: Dictionary, exists: Callable = Callable(ResourceLoader, "exists")) -> Dictionary:
	if not _present:
		return {"status": NO_PACK, "checked": 0, "missing": []}
	var missing: Array = []
	var checked := 0
	for kind in required:
		for id in required[kind]:
			checked += 1
			var path := model(kind, str(id))
			if path == "":
				missing.append({"kind": kind, "id": str(id), "why": "the pack maps no model"})
			elif not exists.call(path):
				missing.append({"kind": kind, "id": str(id), "why": "%s is missing" % path})
	return {"status": MISSING if not missing.is_empty() else COVERED, "checked": checked, "missing": missing}


## The IDs the game requires art for (#59 decision 7): every canonical NPC, monster, item and breakable; the kit @asset
## names the island places (data/misostory/kit_assets_placed.json; the never-placed catalog names are exempt); the
## Beginner presets, hair styles and faces creation offers (data/misostory/appearance.json); and a wearable for every
## canonical item worn on the body (an equip slot other than the hand sockets, CharacterWardrobe.SOCKETS: held items
## need their ITEM model).
static func required_ids(db: ContentDB) -> Dictionary:
	var placed: Variant = db.miso_table("kit_assets_placed")
	var kit: Array = []
	if placed is Dictionary:
		kit = (placed as Dictionary).get("names", []).duplicate()
	var look: Dictionary = db.miso_table("appearance") if db.miso_table("appearance") is Dictionary else {}
	var presets: Array = []
	for g in look.get("defaults", {}):
		var p: Variant = (look.defaults[g] as Dictionary).get("preset")
		if p is String and not (p in presets):
			presets.append(p)
	var hair: Array = []
	for i in int(look.get("choices", {}).get("hair_style", 0)):
		hair.append(str(i))
	var worn: Array = []
	for id in db.ids("items"):
		var slot: Variant = db.item(str(id)).get("equip_slot")
		if slot is String and slot != "" and not CharacterWardrobe.SOCKETS.has(slot):
			worn.append(str(id))
	return {
		NPC: Array(db.ids("npcs")),
		MONSTER: Array(db.ids("monsters")),
		ITEM: Array(db.ids("items")),
		BREAKABLE: Array(db.ids("breakables")),
		KIT: kit,
		PRESET: presets,
		HAIR: hair,
		FACE: Array(look.get("face_styles", [])).map(func(f: Variant) -> String: return str(f)),
		WEARABLE: worn,
	}


func _add(kind: String, id: Variant, rel: Variant) -> void:
	if id == null or not (rel is String) or String(rel) == "":
		return
	_models[kind][str(id)] = rel


static func _under(dir: String, rel: Variant) -> Variant:
	return dir.path_join(rel) if rel is String and rel != "" else null


static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}
