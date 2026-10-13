@tool
extends EditorScenePostImport
## The scene importer's default import script (project.godot [importer_defaults]): normalises every GLB of the pinned
## art pack as Godot imports it (ArtImport, scripts/core/art/art_import.gd) and returns every other scene unchanged,
## such as the exported world chunks. Editor-only: the game never loads it.

const PIN := "res://data/misostory/art_pack.json"


func _post_import(scene: Node) -> Object:
	var pin: Variant = JSON.parse_string(FileAccess.get_file_as_string(PIN))
	if not (pin is Dictionary) or not (scene is Node3D):
		return scene
	var install := String((pin as Dictionary).get("install_dir", "")).trim_suffix("/")
	var source := get_source_file()
	if install == "" or not source.begins_with(install + "/"):
		return scene
	var monsters: Variant = JSON.parse_string(FileAccess.get_file_as_string(install.path_join("monsters/manifest.json")))
	var family := ArtImport.family_of(source.substr(install.length() + 1), monsters if monsters is Dictionary else {})
	if family == "" or family == ArtImport.ENVIRONMENT:
		return scene
	var factor := float((pin as Dictionary).get("character_scale", {}).get("factor", 1.0))
	ArtImport.normalize(scene as Node3D, family, factor)
	return scene
