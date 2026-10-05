class_name ProxyLibrary
extends RefCounted
## The placeholder models of _library.glb (portal visuals, NPC proxies, monster proxies, the player proxy): one root
## node per asset at the origin, feet at y = 0, front = +Z (docs/runtime/blender_export.md). Assets are looked up by
## name with Blender's numeric suffix stripped ("NPC_Robin_001" -> "NPC_Robin"). A missing asset gets a labelled
## capsule placeholder sized from _library.json heights, so content without a model still shows up.

const DEFAULT_GLB := "res://assets/world/_library.glb"
const DEFAULT_JSON := "res://assets/world/_library.json"

var _templates: Dictionary = {}
var _heights: Dictionary = {}
var _root: Node = null


static func load_from(glb_path: String = DEFAULT_GLB, json_path: String = DEFAULT_JSON) -> ProxyLibrary:
	var lib := ProxyLibrary.new()
	var scene: PackedScene = load(glb_path) if ResourceLoader.exists(glb_path) else null
	if scene != null:
		lib._root = scene.instantiate()
		for child in lib._root.get_children():
			lib._templates[ProxyLibrary.asset_name(String(child.name))] = child
	var text := FileAccess.get_file_as_string(json_path)
	var data: Variant = JSON.parse_string(text) if text != "" else null
	if data is Dictionary:
		for a in (data as Dictionary).get("assets", []):
			if a is Dictionary:
				lib._heights[String(a.get("asset", ""))] = float(a.get("height", 0.0))
	return lib


## "NPC_Robin_001" -> "NPC_Robin".
static func asset_name(node_name: String) -> String:
	var parts := node_name.rsplit("_", true, 1)
	if parts.size() == 2 and parts[1].is_valid_int():
		return parts[0]
	return node_name


func has(asset: String) -> bool:
	return _templates.has(asset)


func assets() -> PackedStringArray:
	var out := PackedStringArray(_templates.keys())
	out.sort()
	return out


func height(asset: String) -> float:
	return float(_heights.get(asset, 0.0))


## A fresh copy of the asset, or null when the library has no such asset.
func instance(asset: String) -> Node3D:
	var t: Node = _templates.get(asset, null)
	if t == null:
		return null
	var copy := t.duplicate()
	copy.name = asset
	return copy as Node3D


## The asset, or a labelled capsule placeholder as tall as `like_asset` (from _library.json).
func instance_or_placeholder(asset: String, label: String, like_asset: String) -> Node3D:
	var n := instance(asset)
	if n != null:
		return n
	var h := maxf(height(like_asset), 0.1)
	var root := Node3D.new()
	root.name = asset + "_placeholder"
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = h
	capsule.radius = h * 0.2
	mesh.mesh = capsule
	mesh.position = Vector3.UP * (h * 0.5)
	root.add_child(mesh)
	var tag := Label3D.new()
	tag.text = label
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3.UP * (h + 0.3)
	root.add_child(tag)
	root.set_meta("placeholder", true)
	return root


## Median height of the assets whose name starts with `prefix` ("Mob_"), for placeholders of that family.
func typical(prefix: String) -> String:
	var names: Array = []
	for a in _heights:
		if String(a).begins_with(prefix):
			names.append(a)
	if names.is_empty():
		return ""
	names.sort_custom(func(x: Variant, y: Variant) -> bool: return height(String(x)) < height(String(y)))
	return String(names[names.size() / 2])


func free_templates() -> void:
	if _root != null:
		_root.free()
		_root = null
	_templates.clear()
