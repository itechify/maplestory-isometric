class_name SaveStore
extends RefCounted
## Save-slot files in one directory, as JSON. No game knowledge: it stores and returns Dictionaries.
##
##   <root>/<slot>.json          the save
##   <root>/<slot>.json.bak      the previous good save (one generation)
##   <root>/<slot>.json.tmp      transient, only while a write is in progress
##   <root>/<slot>.json.pre-vN   a one-time copy of the last schema-N save, kept when a newer build first saves over
##                               it (SaveService decides when; keep_copy() makes it and never replaces it)
##
## Writes are atomic in effect: the new text goes to .tmp, is read back and checked, the current save is copied to
## .bak (only if it still parses), and then .tmp is renamed over the save. A failure at any step leaves the previous
## save untouched (and, if the final rename fails after the old file is gone, it is restored from .bak).
## Reads never crash on bad input; they return an error code (see read_document()).

const EXT := ".json"
const BAK_SUFFIX := ".bak"
const TMP_SUFFIX := ".tmp"
## Followed by the schema version of the copied file: "<slot>.json.pre-v1".
const PRE_SUFFIX := ".pre-v"
## Slot names are file names: letters, digits, "_" and "-", 1 to 32 characters (no paths, no dots).
const SLOT_PATTERN := "^[A-Za-z0-9_-]{1,32}$"
## Windows device names, refused in any letter case: "CON.json" still opens the console device, "NUL.json" the
## null device, so a save there would be lost (or a read would block).
const RESERVED_SLOT_PATTERN := "(?i)^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$"

var root: String
## Why the last write_document() failed ("" after a success).
var last_write_message: String = ""


func _init(root_dir: String = "user://saves") -> void:
	root = root_dir


static func is_valid_slot(slot: String) -> bool:
	var m := RegEx.create_from_string(SLOT_PATTERN).search(slot)
	# PCRE's "$" also matches before a trailing newline, so require the match to be the whole string.
	if m == null or m.get_string() != slot:
		return false
	return RegEx.create_from_string(RESERVED_SLOT_PATTERN).search(slot) == null


func path_of(slot: String) -> String:
	return root.path_join(slot + EXT)


func backup_path_of(slot: String) -> String:
	return path_of(slot) + BAK_SUFFIX


func tmp_path_of(slot: String) -> String:
	return path_of(slot) + TMP_SUFFIX


## The one-time copy of the slot's last schema-`version` save.
func pre_copy_path_of(slot: String, version: int) -> String:
	return path_of(slot) + PRE_SUFFIX + str(version)


func has_pre_copy(slot: String, version: int) -> bool:
	return is_valid_slot(slot) and FileAccess.file_exists(pre_copy_path_of(slot, version))


## Copies the slot's save (or its backup) byte for byte to pre_copy_path_of(slot, version), once: an existing copy
## is never replaced (ERR_ALREADY_EXISTS). ERR_FILE_NOT_FOUND when there is nothing to copy.
func keep_copy(slot: String, from_backup: bool, version: int) -> Error:
	if not is_valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var src := backup_path_of(slot) if from_backup else path_of(slot)
	if not FileAccess.file_exists(src):
		return ERR_FILE_NOT_FOUND
	var dst := pre_copy_path_of(slot, version)
	if FileAccess.file_exists(dst):
		return ERR_ALREADY_EXISTS
	var err := DirAccess.copy_absolute(src, dst)
	if err == OK and FileAccess.get_file_as_bytes(dst) != FileAccess.get_file_as_bytes(src):
		DirAccess.remove_absolute(dst)
		err = ERR_FILE_CANT_WRITE
	return err


## True if the slot's save file exists (it may still be corrupt; read it to know).
func has(slot: String) -> bool:
	return is_valid_slot(slot) and FileAccess.file_exists(path_of(slot))


func has_backup(slot: String) -> bool:
	return is_valid_slot(slot) and FileAccess.file_exists(backup_path_of(slot))


## Writes `doc` to the slot atomically. Errors: ERR_INVALID_PARAMETER (slot name), ERR_INVALID_DATA (the document
## holds a value JSON cannot round-trip; nothing is written), ERR_CANT_CREATE (directory), or the file error of the
## failing step. On any error the previous save is unchanged.
func write_document(slot: String, doc: Dictionary) -> Error:
	last_write_message = ""
	if not is_valid_slot(slot):
		last_write_message = "invalid slot name"
		return ERR_INVALID_PARAMETER
	var problem := find_unsupported_value(doc)
	if problem != "":
		last_write_message = problem
		return ERR_INVALID_DATA
	var text := JSON.stringify(doc, "\t", true, true)
	if DirAccess.make_dir_recursive_absolute(root) != OK and not DirAccess.dir_exists_absolute(root):
		last_write_message = "cannot create %s" % root
		return ERR_CANT_CREATE
	var main := path_of(slot)
	var bak := backup_path_of(slot)
	var tmp := tmp_path_of(slot)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	# 1. Write the new text to .tmp and read it back.
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		var open_err := FileAccess.get_open_error()
		last_write_message = "cannot open %s for writing" % tmp
		return open_err if open_err != OK else ERR_FILE_CANT_WRITE
	f.store_string(text)
	var write_err := f.get_error()
	f.close()
	if write_err != OK or FileAccess.get_file_as_string(tmp) != text:
		DirAccess.remove_absolute(tmp)
		last_write_message = "%s did not read back as written" % tmp
		return write_err if write_err != OK else ERR_FILE_CANT_WRITE
	# 2. Keep the current save as the backup, but never replace a good backup with a corrupt save.
	if FileAccess.file_exists(main) and _parses_as_object(main):
		var copy_err := DirAccess.copy_absolute(main, bak)
		if copy_err != OK:
			DirAccess.remove_absolute(tmp)
			last_write_message = "cannot back up %s" % main
			return copy_err
	# 3. Promote .tmp to the save.
	var rename_err := DirAccess.rename_absolute(tmp, main)
	if rename_err != OK:
		if not FileAccess.file_exists(main) and FileAccess.file_exists(bak):
			DirAccess.copy_absolute(bak, main)
		DirAccess.remove_absolute(tmp)
		last_write_message = "cannot rename %s to %s" % [tmp, main]
		return rename_err
	return OK


## Reads and parses a slot (or its backup). Returns {"error": Error, "data": Dictionary, "message": String}:
##   OK                     data is the parsed top-level object
##   ERR_INVALID_PARAMETER  bad slot name
##   ERR_FILE_NOT_FOUND     no such file
##   ERR_PARSE_ERROR        empty, truncated or otherwise invalid JSON
##   ERR_FILE_CORRUPT       valid JSON whose top level is not an object
##   other file errors      the file exists but cannot be opened
func read_document(slot: String, from_backup: bool = false) -> Dictionary:
	if not is_valid_slot(slot):
		return _read_fail(ERR_INVALID_PARAMETER, "invalid slot name '%s'" % slot)
	var path := backup_path_of(slot) if from_backup else path_of(slot)
	if not FileAccess.file_exists(path):
		return _read_fail(ERR_FILE_NOT_FOUND, "%s does not exist" % path)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		var open_err := FileAccess.get_open_error()
		if open_err != OK:
			return _read_fail(open_err, "%s cannot be read (%s)" % [path, error_string(open_err)])
		return _read_fail(ERR_PARSE_ERROR, "%s is empty" % path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return _read_fail(ERR_PARSE_ERROR, "%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
	if not (json.data is Dictionary):
		return _read_fail(ERR_FILE_CORRUPT, "%s: top level is not an object" % path)
	return {"error": OK, "data": json.data, "message": ""}


## Deletes the save, its backup, its pre-migration copies and any leftover temp file. ERR_FILE_NOT_FOUND if none
## existed.
func delete(slot: String) -> Error:
	if not is_valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var found := false
	var paths: Array = [path_of(slot), backup_path_of(slot), tmp_path_of(slot)]
	var dir := DirAccess.open(root)
	if dir != null:
		for f in dir.get_files():
			if f.begins_with(slot + EXT + PRE_SUFFIX) and f.trim_prefix(slot + EXT + PRE_SUFFIX).is_valid_int():
				paths.append(root.path_join(f))
	for path: String in paths:
		if FileAccess.file_exists(path):
			found = true
			var err := DirAccess.remove_absolute(path)
			if err != OK:
				return err
	return OK if found else ERR_FILE_NOT_FOUND


## Replaces the save with its backup (the backup stays). ERR_FILE_NOT_FOUND without a backup, ERR_PARSE_ERROR /
## ERR_FILE_CORRUPT if the backup itself is unreadable.
func restore_backup(slot: String) -> Error:
	var read := read_document(slot, true)
	if int(read["error"]) != OK:
		return int(read["error"]) as Error
	var text := FileAccess.get_file_as_string(backup_path_of(slot))
	var tmp := tmp_path_of(slot)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return ERR_FILE_CANT_WRITE
	f.store_string(text)
	var write_err := f.get_error()
	f.close()
	if write_err != OK or FileAccess.get_file_as_string(tmp) != text:
		DirAccess.remove_absolute(tmp)
		return write_err if write_err != OK else ERR_FILE_CANT_WRITE
	var rename_err := DirAccess.rename_absolute(tmp, path_of(slot))
	if rename_err != OK:
		DirAccess.remove_absolute(tmp)
	return rename_err


## Slot names that have a save or a backup in the directory, sorted.
func list_slots() -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for f in dir.get_files():
		var slot := ""
		if f.ends_with(EXT):
			slot = f.trim_suffix(EXT)
		elif f.ends_with(EXT + BAK_SUFFIX):
			slot = f.trim_suffix(EXT + BAK_SUFFIX)
		if slot != "" and is_valid_slot(slot) and not (slot in out):
			out.append(slot)
	out.sort()
	return out


## Unix time of the save file's last modification (0 when missing).
func modified_time(slot: String) -> int:
	return FileAccess.get_modified_time(path_of(slot)) if has(slot) else 0


## "" if `value` survives JSON unchanged in kind; otherwise the path and type of the first offending value.
## Allowed: null, bool, int, finite float, String/StringName, Arrays of those, Dictionaries with String keys.
static func find_unsupported_value(value: Variant, path: String = "$") -> String:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return ""
		TYPE_FLOAT:
			return "" if is_finite(float(value)) else "%s is not a finite number" % path
		TYPE_ARRAY:
			var arr: Array = value
			for i in arr.size():
				var p := find_unsupported_value(arr[i], "%s[%d]" % [path, i])
				if p != "":
					return p
			return ""
		TYPE_DICTIONARY:
			var d: Dictionary = value
			for k in d:
				if typeof(k) != TYPE_STRING and typeof(k) != TYPE_STRING_NAME:
					return "%s has a %s key (%s); JSON keys must be strings" % [path, type_string(typeof(k)), str(k)]
				var p := find_unsupported_value(d[k], "%s.%s" % [path, String(k)])
				if p != "":
					return p
			return ""
	return "%s is a %s, which JSON cannot store" % [path, type_string(typeof(value))]


func _parses_as_object(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return false
	var json := JSON.new()
	return json.parse(text) == OK and json.data is Dictionary


func _read_fail(err: Error, message: String) -> Dictionary:
	return {"error": err, "data": {}, "message": message}
