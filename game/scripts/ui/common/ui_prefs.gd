class_name MisoUiPrefs
extends RefCounted
## The player's UI preferences on this machine, kept across restarts: today whether the minimap is folded. They are
## user settings, not character progress, so they live in no save slot: a ConfigFile beside the slots
## (`<SaveService.save_dir>/ui_prefs.cfg`, user://saves/ui_prefs.cfg in the game; MisoUiEnv.ui_prefs_path). A
## playtest's or a test's private save directory therefore gets its own file, and a fresh playtest run starts from
## the defaults. SaveStore lists only `.json` slots, so the file is never taken for one.
##
## Every call reads the file again (and a write rewrites it), so two UI roots never hold different copies. A path of
## "" means no file: reads return the default and writes do nothing (tests, sandboxes without a save directory).

const FILE_NAME := "ui_prefs.cfg"
const MINIMAP := "minimap"
## [section, key] of the minimap's fold: true = the picture shows (the default), false = folded to the title strip.
const MINIMAP_EXPANDED := "expanded"


## The value stored under section / key in the file at `path`, else `default`.
static func read(path: String, section: String, key: String, default: Variant) -> Variant:
	if path == "" or not FileAccess.file_exists(path):
		return default
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return default
	return cfg.get_value(section, key, default)


## Stores `value` under section / key, keeping the file's other values. OK, or the error (nothing written for "").
static func write(path: String, section: String, key: String, value: Variant) -> Error:
	if path == "":
		return OK
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(path):
		cfg.load(path)
	cfg.set_value(section, key, value)
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return cfg.save(path)
