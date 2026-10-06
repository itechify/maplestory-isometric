class_name SaveService
extends Node
## Autoload "Saves": versioned save/load of logical game state (never the scene tree).
##
## Fixed contract (other systems call these):
##   save_game(slot: String) -> Error, load_game(slot: String) -> Error, has_save(slot) -> bool,
##   delete_save(slot) -> Error, list_saves() -> Array[Dictionary], SAVE_VERSION: int.
##
## Files are JSON in user://saves/<slot>.json with one .bak generation and a one-time copy of the last save of each
## older schema, <slot>.json.pre-v<N> (SaveStore, keep_pre_migration_copy()). The document is built and
## decoded by SaveDocument and migrated by SaveMigrations. The live character comes from the Game autoload and the
## map/session block from MapSession; both are injectable (game_node, map_session_node, can_save_override,
## world_provider) so tests never touch autoload state. See docs/runtime/SAVES.md.
##
## Error codes: OK; ERR_INVALID_PARAMETER bad slot name; ERR_UNAVAILABLE saving not allowed now (MapSession.can_save()
## is false); ERR_UNCONFIGURED no active game; ERR_FILE_NOT_FOUND no save; ERR_PARSE_ERROR not JSON / empty /
## truncated; ERR_FILE_CORRUPT JSON but not a valid MisoStory save; ERR_INVALID_DATA unsupported or unmigratable
## schema version, or (on save) a value JSON cannot store; other Error values are file-system failures.

const SAVE_VERSION: int = SaveMigrations.CURRENT_VERSION
const DEFAULT_SAVE_DIR := "user://saves"

## Directory holding the slot files. Tests point this at a private directory.
var save_dir: String = DEFAULT_SAVE_DIR:
	set(value):
		save_dir = value
		_store = null
var migrations: SaveMigrations = SaveMigrations.new()
## Content used for map validation and slot meta; null = the Data autoload's db.
var db: ContentDB = null
## The node owning the live character (GameState); null = the Game autoload.
var game_node: Node = null
## The map session; null = the MapSession autoload (if present).
var map_session_node: Node = null
## Optional () -> bool replacing the MapSession.can_save() check.
var can_save_override: Callable = Callable()
## Optional (character: CharacterState) -> Dictionary replacing MapSession as the source of the "world" block.
var world_provider: Callable = Callable()
## The signal bus for game_saved; null = the Events autoload.
var event_bus: Node = null
## push_warning() on failures and load corrections (tests switch it off).
var log_failures: bool = true

## The last failure (OK after a success) and a readable reason, for UI and the debug console.
var last_error: Error = OK
var last_error_message: String = ""

var _store: SaveStore = null


## The file layer for save_dir.
func store() -> SaveStore:
	if _store == null:
		_store = SaveStore.new(save_dir)
	return _store


## Saving is allowed only when MapSession.can_save() holds (state IDLE, player alive with valid SafeGround).
## A MapSession without can_save() (e.g. a contract stub) is treated as allowing saves.
func can_save() -> bool:
	if can_save_override.is_valid():
		return bool(can_save_override.call())
	var ms := _map_session()
	if ms != null and ms.has_method("can_save"):
		return bool(ms.call("can_save"))
	return true


## Saves the live game (Game.character + the MapSession world block) into `slot`.
func save_game(slot: String) -> Error:
	if not SaveStore.is_valid_slot(slot):
		return _fail(ERR_INVALID_PARAMETER, "invalid slot name '%s'" % slot)
	var game := _game()
	if game == null or not game.has_active_game():
		return _fail(ERR_UNCONFIGURED, "no game in progress")
	if not can_save():
		return _fail(ERR_UNAVAILABLE, "saving is not possible right now")
	var character: CharacterState = game.character
	var world := capture_world(character)
	# MapSession owns the location; keep the live character's copy identical to what is written.
	if world.get("location", {}) is Dictionary and not (world["location"] as Dictionary).is_empty():
		character.location = (world["location"] as Dictionary).duplicate(true)
	if typeof(world.get("respawn_reference", null)) == TYPE_STRING and String(world["respawn_reference"]) != "":
		character.respawn_reference = String(world["respawn_reference"])
	var err := save_character(slot, character, world)
	if err == OK:
		_emit(&"game_saved", [slot])
	return err


## Asks for a debounced autosave of the live game (forwards to GameState.request_autosave, which waits for
## can_save()). MapSession calls this after every committed transition (MAP_ARCHITECTURE.md §4.5 step 15).
## Returns false when it is ignored (no Game node, no active game, autosave disabled).
func request_autosave(reason: String = "") -> bool:
	var game := _game()
	return game != null and game.request_autosave(reason if reason != "" else "map_session")


## Writes `character` + `world` to `slot` with no can_save() check (new-game initial save, tools, tests). The first
## write over a save of an older schema keeps that file first (keep_pre_migration_copy()).
func save_character(slot: String, character: CharacterState, world: Dictionary = {}) -> Error:
	if not SaveStore.is_valid_slot(slot):
		return _fail(ERR_INVALID_PARAMETER, "invalid slot name '%s'" % slot)
	var doc := SaveDocument.build(character, world, now_iso(), _db())
	keep_pre_migration_copy(slot)
	var err := store().write_document(slot, doc)
	if err != OK:
		var why := store().last_write_message
		return _fail(err, "writing %s failed: %s%s" % [slot, error_string(err), " (%s)" % why if why != "" else ""])
	last_error = OK
	last_error_message = ""
	return OK


## Keeps a one-time copy of the slot's save written at an older schema version, as <slot>.json.pre-v<N>, before
## this build writes over it, so a faulty migration can never destroy the only copy of a player's progress (the
## single .bak generation would lose it on the second save). The save file is checked first, then the backup: a slot
## loaded from its backup writes the save without rotating, and the next write would replace that backup. Existing
## copies are never replaced; delete_save() removes them. Returns the versions copied. A copy that fails is logged
## and does not block the save.
func keep_pre_migration_copy(slot: String) -> PackedInt32Array:
	var copied: PackedInt32Array = []
	for from_backup: bool in [false, true]:
		var read := store().read_document(slot, from_backup)
		if int(read["error"]) != OK:
			continue
		var v := SaveMigrations.version_of(read["data"])
		if v < 0 or v >= SaveMigrations.CURRENT_VERSION or store().has_pre_copy(slot, v):
			continue
		var err := store().keep_copy(slot, from_backup, v)
		if err == OK:
			copied.append(v)
		elif log_failures:
			push_warning("[Saves] %s: could not keep a copy of the save_version %d file (%s)" % [slot, v,
				error_string(err)])
	return copied


## Reads, migrates and validates a slot without touching the live game. Check result.error.
func read_save(slot: String, from_backup: bool = false) -> SaveLoadResult:
	var raw := store().read_document(slot, from_backup)
	if int(raw["error"]) != OK:
		return SaveLoadResult.failed(int(raw["error"]) as Error, String(raw["message"]), slot)
	var r := SaveDocument.decode(raw["data"], migrations, _db())
	r.slot = slot
	r.source = "backup" if from_backup else "main"
	if log_failures:
		for w in r.warnings:
			push_warning("[Saves] %s: %s" % [slot, w])
	return r


## Reads a slot for loading: the save, or its backup when the save file is MISSING but a backup exists (a crash
## between "remove old" and "move new" on Windows leaves exactly that). A save that is present but corrupt is never
## replaced by its backup here; the UI offers restore_backup() for that.
func read_for_load(slot: String) -> SaveLoadResult:
	var r := read_save(slot)
	if r.error == ERR_FILE_NOT_FOUND and store().has_backup(slot):
		var from_bak := read_save(slot, true)
		from_bak.warnings.append("the save file is missing; loaded its backup")
		if log_failures:
			push_warning("[Saves] %s: the save file is missing; using its backup" % slot)
		return from_bak
	return r


## Loads `slot` into the live game: the character is replaced wholesale and the refresh signals fire
## (GameState.apply_loaded_save). On error the live game is unchanged. A slot whose save file is missing but whose
## backup exists loads the backup (Events.notice says so; see read_for_load()).
func load_game(slot: String) -> Error:
	var r := read_for_load(slot)
	if not r.ok():
		return _fail(r.error, "loading %s failed: %s" % [slot, r.message])
	var game := _game()
	if game == null:
		return _fail(ERR_UNCONFIGURED, "no Game node to load into")
	var err := game.apply_loaded_save(r)
	if err != OK:
		return _fail(err, "applying %s failed" % slot)
	last_error = OK
	last_error_message = ""
	return OK


## True if the slot's save file exists (it may still be corrupt; list_saves() reports validity).
func has_save(slot: String) -> bool:
	return store().has(slot)


## Deletes the save, its backup, its pre-migration copies and any temp file. ERR_FILE_NOT_FOUND if there was nothing
## to delete.
func delete_save(slot: String) -> Error:
	return store().delete(slot)


## Replaces a slot's save with its .bak (offer this when a save reads as corrupt).
func restore_backup(slot: String) -> Error:
	return store().restore_backup(slot)


## One entry per slot with a save or backup, sorted by slot name:
##   {"slot", "ok": bool, "error": int, "error_text": String, "has_backup": bool, "modified_unix": int,
##    "save_version": int (as found in the file, before migration), "saved_at": String, "meta": Dictionary,
##    "source": "main" | "backup" (what load_game(slot) would load; "backup" when only the backup is left)}
## "meta" is {"name", "level", "job", "map_id", "map_name", "play_time_s"} for readable saves, {} otherwise.
func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in store().list_slots():
		var r := read_for_load(slot)
		out.append({
			"slot": slot,
			"ok": r.ok(),
			"error": int(r.error),
			"error_text": r.message,
			"has_backup": store().has_backup(slot),
			"modified_unix": _modified_unix(slot, r.source),
			"save_version": r.version_found,
			"saved_at": r.saved_at,
			"meta": r.meta if r.ok() else {},
			"source": r.source,
		})
	return out


## The "world" block for a save. Sources, in order: world_provider; MapSession.save_world() -> Dictionary when
## MapSession implements it; otherwise the character's own location, checked against MapSession:
##   - MapSession.current_map ("" = no world yet: the character's location is kept as it is);
##   - MapSession.last_arrival (an ArrivalRef with to_dict(), or a Dictionary) is the entry (MAP_ARCHITECTURE.md
##     §4.9). When the character's location is for another map, or its entry is not last_arrival, the location is
##     stale and becomes {"map_id": current_map, "entry": last_arrival} (spawn 0 when last_arrival is unavailable),
##     without "resume": only MapSession knows SafeGround, so it must implement save_world() to save a resume point.
##   - MapSession.respawn_reference, when set.
func capture_world(character: CharacterState) -> Dictionary:
	if world_provider.is_valid():
		var provided: Variant = world_provider.call(character)
		if provided is Dictionary:
			return (provided as Dictionary).duplicate(true)
	var ms := _map_session()
	if ms != null and ms.has_method("save_world"):
		var w: Variant = ms.call("save_world")
		if w is Dictionary and not (w as Dictionary).is_empty():
			return (w as Dictionary).duplicate(true)
	var world := SaveDocument.world_from_character(character)
	if ms != null:
		var current := SaveDocument.as_text(ms.get("current_map"))
		if current != "":
			var loc: Dictionary = world["location"]
			var arrival := _last_arrival_in(ms, current)
			var stale := SaveDocument.as_text(loc.get("map_id", "")) != current
			if not arrival.is_empty() and not _same_dict(loc.get("entry", null), arrival):
				stale = true
			if stale:
				world["location"] = {
					"map_id": current,
					"entry": arrival if not arrival.is_empty() else {"map_id": current, "spawn_index": 0},
				}
		var respawn := SaveDocument.as_text(ms.get("respawn_reference"))
		if respawn != "":
			world["respawn_reference"] = respawn
	return world


## UTC timestamp, ISO 8601 ("2026-10-04T12:00:00Z").
static func now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


# --- internals ------------------------------------------------------------------------------------------------

func _db() -> ContentDB:
	if db != null:
		return db
	var data := _autoload("Data")
	return data.get("db") as ContentDB if data != null else null


## Modification time of the file a slot loads from (the backup when only the backup is left).
func _modified_unix(slot: String, source: String) -> int:
	if source == "backup":
		return int(FileAccess.get_modified_time(store().backup_path_of(slot)))
	return store().modified_time(slot)


## MapSession.last_arrival as a save entry ({"map_id", "portal_id"} or {"map_id", "spawn_index"}), or {} when it is
## unavailable or names another map.
static func _last_arrival_in(ms: Node, current: String) -> Dictionary:
	var a: Variant = ms.get("last_arrival")
	var d: Dictionary = {}
	if a is Dictionary:
		d = a
	elif a is Object and (a as Object).has_method("to_dict"):
		var v: Variant = (a as Object).call("to_dict")
		if v is Dictionary:
			d = v
	if d.is_empty() or SaveDocument.as_text(d.get("map_id", "")) != current:
		return {}
	return d.duplicate(true)


## Dictionary equality where numbers compare by value (a loaded spawn_index may be int where MapSession has float).
static func _same_dict(a: Variant, b: Variant) -> bool:
	if not (a is Dictionary and b is Dictionary):
		return false
	var da: Dictionary = a
	var dbb: Dictionary = b
	if da.size() != dbb.size():
		return false
	for k: Variant in da:
		if not dbb.has(k):
			return false
		var x: Variant = da[k]
		var y: Variant = dbb[k]
		var x_num := typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT
		var y_num := typeof(y) == TYPE_INT or typeof(y) == TYPE_FLOAT
		if x_num and y_num:
			if float(x) != float(y):
				return false
		elif typeof(x) != typeof(y) or x != y:
			return false
	return true


func _game() -> GameState:
	if game_node != null:
		return game_node as GameState
	return _autoload("Game") as GameState


func _map_session() -> Node:
	if map_session_node != null:
		return map_session_node
	return _autoload("MapSession")


func _emit(sig: StringName, args: Array = []) -> void:
	var bus := event_bus if event_bus != null else _autoload("Events")
	if bus != null:
		bus.callv(&"emit_signal", [sig] + args)


## An autoload by name, found through the SceneTree so this also works on instances outside the tree (tests).
static func _autoload(autoload_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(autoload_name) if tree != null else null


func _fail(err: Error, message: String) -> Error:
	last_error = err
	last_error_message = message
	if log_failures:
		push_warning("[Saves] " + message)
	return err
