class_name SaveLoadResult
extends RefCounted
## The outcome of reading one save: an error code, or the decoded character, world block and meta.
##
## Produced by SaveDocument.decode() and SaveService.read_save(); consumed by GameState.apply_loaded_save().

var slot: String = ""
## OK, or the reason the save cannot be used (see docs/runtime/SAVES.md, "Error codes").
var error: Error = OK
var message: String = ""
## "main" or "backup": which file was read.
var source: String = "main"
## The schema version found in the file before migration (0 = pre-versioning, -1 = unreadable).
var version_found: int = -1
## Names of the migration steps applied, in order.
var migrations_applied: PackedStringArray = []
## The migrated, number-normalized document.
var document: Dictionary = {}
var character: CharacterState = null
## {"location": {...}, "respawn_reference": String, ...}: the map/session block, already validated against content.
var world: Dictionary = {}
## {"name", "level", "job", "map_id", "map_name", "play_time_s"}, recomputed from the loaded character.
var meta: Dictionary = {}
var saved_at: String = ""
## Non-fatal corrections made while loading (unknown map replaced, respawn reference recomputed, ...).
var warnings: PackedStringArray = []


func ok() -> bool:
	return error == OK


static func failed(err: Error, msg: String, slot_name: String = "") -> SaveLoadResult:
	var r := SaveLoadResult.new()
	r.error = err
	r.message = msg
	r.slot = slot_name
	return r
