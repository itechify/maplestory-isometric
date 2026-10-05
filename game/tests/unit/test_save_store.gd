extends TestCase
## SaveStore: the slot files. Atomic writes with one backup, error codes for missing/corrupt files, slot-name
## safety, list and delete. Every test works in its own user://_tests/ directory (never user://saves).

var root := ""
var store: SaveStore


func before_each() -> void:
	root = "user://_tests/save_store_%d_%d" % [Time.get_ticks_usec(), randi()]
	store = SaveStore.new(root)


func after_each() -> void:
	_remove_tree(root)


func _write_raw(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


func test_write_then_read() -> void:
	assert_eq(store.write_document("slot1", {"a": 1, "b": "x", "c": [1.5, true, null]}), OK, "write")
	assert_true(store.has("slot1"), "has after write")
	var r := store.read_document("slot1")
	assert_eq(r["error"], OK, "read")
	assert_eq(r["data"]["b"], "x")
	assert_eq(r["data"]["c"], [1.5, true, null])
	assert_false(FileAccess.file_exists(store.tmp_path_of("slot1")), "no temp file left behind")


func test_second_write_keeps_one_backup() -> void:
	store.write_document("slot1", {"gen": 1})
	assert_false(store.has_backup("slot1"), "first write has nothing to back up")
	store.write_document("slot1", {"gen": 2})
	store.write_document("slot1", {"gen": 3})
	assert_eq(store.read_document("slot1")["data"]["gen"], 3.0, "main is the newest")
	assert_eq(store.read_document("slot1", true)["data"]["gen"], 2.0, "backup is the previous save")
	var files := DirAccess.get_files_at(root)
	assert_eq(files.size(), 2, "only the save and one backup: %s" % ", ".join(files))


func test_failed_write_leaves_the_old_save_intact() -> void:
	store.write_document("slot1", {"gen": 1})
	store.write_document("slot1", {"gen": 2})
	var before_main := FileAccess.get_file_as_string(store.path_of("slot1"))
	var before_bak := FileAccess.get_file_as_string(store.backup_path_of("slot1"))
	# A real file-system failure: the temp path is occupied by a non-empty directory, so it cannot be opened.
	DirAccess.make_dir_recursive_absolute(store.tmp_path_of("slot1"))
	_write_raw(store.tmp_path_of("slot1").path_join("blocker"), "x")
	var err := store.write_document("slot1", {"gen": 3})
	assert_ne(err, OK, "the write reports failure")
	assert_eq(FileAccess.get_file_as_string(store.path_of("slot1")), before_main, "old save byte-identical")
	assert_eq(FileAccess.get_file_as_string(store.backup_path_of("slot1")), before_bak, "backup untouched")
	assert_eq(store.read_document("slot1")["data"]["gen"], 2.0, "old save still loads")


func test_unserializable_values_are_refused_before_touching_disk() -> void:
	store.write_document("slot1", {"gen": 1})
	var before := FileAccess.get_file_as_string(store.path_of("slot1"))
	var bad_values := {
		"vector": {"pos": Vector3(1, 2, 3)},
		"int key": {"quickslots": {1: "270"}},
		"object": {"o": RefCounted.new()},
		"infinity": {"x": INF},
	}
	for label in bad_values:
		assert_eq(store.write_document("slot1", bad_values[label]), ERR_INVALID_DATA, "%s refused" % label)
	assert_eq(FileAccess.get_file_as_string(store.path_of("slot1")), before, "save unchanged")
	assert_ne(SaveStore.find_unsupported_value({"a": {"b": [Vector2.ZERO]}}).find("$.a.b[0]"), -1,
		"problem path is reported")


func test_missing_and_corrupt_files_return_error_codes() -> void:
	assert_eq(store.read_document("nope")["error"], ERR_FILE_NOT_FOUND, "missing")
	var cases := {
		"garbage": ["this is not json", ERR_PARSE_ERROR],
		"empty": ["", ERR_PARSE_ERROR],
		"truncated": ["{\"save_version\": 1, \"character\": {\"name\": \"Tr", ERR_PARSE_ERROR],
		"array": ["[1, 2, 3]", ERR_FILE_CORRUPT],
		"number": ["42", ERR_FILE_CORRUPT],
	}
	for slot in cases:
		_write_raw(store.path_of(slot), cases[slot][0])
		var r := store.read_document(slot)
		assert_eq(r["error"], cases[slot][1], "%s error code" % slot)
		assert_true(String(r["message"]).length() > 0, "%s has a message" % slot)
		assert_eq(r["data"], {}, "%s gives no data" % slot)


func test_binary_garbage_is_a_parse_error() -> void:
	DirAccess.make_dir_recursive_absolute(root)
	var f := FileAccess.open(store.path_of("binary"), FileAccess.WRITE)
	f.store_buffer(PackedByteArray([0x7b, 0x00, 0x01, 0x02, 0x22, 0x41, 0x00]))
	f.close()
	assert_ne(store.read_document("binary")["error"], OK, "binary file rejected")


func test_slot_names_cannot_escape_the_directory() -> void:
	for bad in ["", "../escape", "a/b", "a b", "dot.name", "x".repeat(33), "C:", "slot\n"]:
		assert_false(SaveStore.is_valid_slot(bad), "'%s' invalid" % bad)
		assert_eq(store.write_document(bad, {"a": 1}), ERR_INVALID_PARAMETER, "'%s' write refused" % bad)
		assert_eq(store.read_document(bad)["error"], ERR_INVALID_PARAMETER, "'%s' read refused" % bad)
	for good in ["slot1", "Slot_2", "auto-save", "x".repeat(32), "CONSOLE", "nully", "COM10", "lpt"]:
		assert_true(SaveStore.is_valid_slot(good), "'%s' valid" % good)
	# Windows device names: "CON.json" opens the console, "NUL.json" the null device.
	for device in ["CON", "con", "PRN", "Aux", "NUL", "COM1", "com9", "LPT1", "lpt9"]:
		assert_false(SaveStore.is_valid_slot(device), "'%s' is a Windows device name" % device)
		assert_eq(store.write_document(device, {"a": 1}), ERR_INVALID_PARAMETER, "'%s' write refused" % device)
	assert_false(FileAccess.file_exists(root.get_base_dir().path_join("escape.json")), "nothing written outside")


func test_list_and_delete() -> void:
	assert_eq(store.list_slots(), PackedStringArray(), "empty dir lists nothing")
	store.write_document("b", {"x": 1})
	store.write_document("a", {"x": 1})
	store.write_document("a", {"x": 2})
	_write_raw(root.path_join("notes.txt"), "ignored")
	assert_eq(store.list_slots(), PackedStringArray(["a", "b"]), "sorted slots, backups and strays not listed twice")
	assert_eq(store.delete("a"), OK, "delete")
	assert_false(store.has("a"), "save gone")
	assert_false(store.has_backup("a"), "backup gone too")
	assert_eq(store.list_slots(), PackedStringArray(["b"]))
	assert_eq(store.delete("a"), ERR_FILE_NOT_FOUND, "deleting twice")
	assert_eq(store.delete("../b"), ERR_INVALID_PARAMETER)


func test_restore_backup_and_corrupt_save_never_overwrites_a_good_backup() -> void:
	store.write_document("slot1", {"gen": 1})
	store.write_document("slot1", {"gen": 2})
	_write_raw(store.path_of("slot1"), "{corrupt")
	assert_eq(store.read_document("slot1")["error"], ERR_PARSE_ERROR)
	# Writing over a corrupt save keeps the good backup (gen 1) instead of backing up the corrupt file.
	store.write_document("slot1", {"gen": 3})
	assert_eq(store.read_document("slot1", true)["data"]["gen"], 1.0, "backup still the last good save")
	_write_raw(store.path_of("slot1"), "{corrupt again")
	assert_eq(store.restore_backup("slot1"), OK, "restore")
	assert_eq(store.read_document("slot1")["data"]["gen"], 1.0, "restored from backup")
	assert_eq(store.restore_backup("nobackup"), ERR_FILE_NOT_FOUND, "no backup to restore")


func test_backup_only_slot_is_listed() -> void:
	store.write_document("slot1", {"gen": 1})
	store.write_document("slot1", {"gen": 2})
	DirAccess.remove_absolute(store.path_of("slot1"))
	assert_eq(store.list_slots(), PackedStringArray(["slot1"]), "a slot with only a backup is still offered")
	assert_eq(store.read_document("slot1")["error"], ERR_FILE_NOT_FOUND)
	assert_eq(store.restore_backup("slot1"), OK)
	assert_eq(store.read_document("slot1")["data"]["gen"], 1.0)
