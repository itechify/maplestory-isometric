extends Node
## Headless canonical-data validation (brief Phase 22). Loads the content through the game's own ContentDB, runs
## DataValidator and prints one line per finding plus a summary. Exit code 0 = no errors, 1 = errors (broken data
## is treated like a compile error), 2 = the validator itself is broken (does not compile, raised a script error,
## timed out) or the command line is wrong.
##
##   bash scripts/validate_data.sh                      # the usual entry point (import pass + this scene)
##   bash scripts/validate_data.sh --verbose            # also list every reference skipped as out of scope
##   bash scripts/validate_data.sh --strict             # warnings fail too
##   bash scripts/validate_data.sh --json <path>        # also write the report as JSON (absolute or res:// path)
##   bash scripts/validate_data.sh --world-dir <dir>    # Blender export to check the crosswalk slugs against
##   bash scripts/validate_data.sh --report             # also write the provenance validation report
##                                                      # (docs/provenance_report.json + docs/PROVENANCE_REPORT.md;
##                                                      # the script passes --report-json <path> --report-md <path>)
##
## Prints VALIDATION_PASSED or VALIDATION_FAILED as the last line.
##
## Why the validator is loaded with load() instead of by class name: if this script named ContentDB or DataValidator
## directly, a parse error in any of them would stop this script from compiling, and Godot would then idle forever
## with a script-less node (no _ready, no watchdog). Loading them at run time keeps this file compilable, so a broken
## dependency becomes a clear exit 2. scripts/validate_data.sh adds an outer timeout as a last resort.

const WATCHDOG_S := 120.0
const EXIT_PASSED := 0
const EXIT_DATA_ERRORS := 1
const EXIT_VALIDATOR_BROKEN := 2
const CONTENT_DB_SCRIPT := "res://scripts/core/content_db.gd"
const VALIDATOR_SCRIPT := "res://scripts/core/validation/data_validator.gd"
const GUARD_SCRIPT := "res://scripts/core/validation/script_error_guard.gd"
const REPORT_SCRIPT := "res://scripts/core/validation/provenance_report.gd"
const FLAGS := ["--verbose", "--strict"]
const VALUE_FLAGS := ["--json", "--world-dir", "--report-json", "--report-md"]

## The process exit code. It starts as EXIT_VALIDATOR_BROKEN and is lowered only when run() reaches its end: a script
## error aborts a GDScript function, which then returns its default value (0 for an int), so returning the code from
## run() would turn a crashed validator into a pass.
var exit_code := EXIT_VALIDATOR_BROKEN


func _ready() -> void:
	# Backstop for a validator that never returns (an endless loop); script errors are caught by the guard below.
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	run(OS.get_cmdline_user_args())
	get_tree().quit(exit_code)


## Runs the validation with command-line style arguments, sets exit_code and returns it.
func run(args: PackedStringArray) -> int:
	exit_code = EXIT_VALIDATOR_BROKEN
	var bad_args := _bad_args(args)
	if bad_args != "":
		_broken("bad command line: %s (flags: %s; with a value: %s)" % [bad_args, ", ".join(PackedStringArray(FLAGS)),
			", ".join(PackedStringArray(VALUE_FLAGS))])
		return exit_code
	var content_db_script := _compiled(CONTENT_DB_SCRIPT)
	var validator_script := _compiled(VALIDATOR_SCRIPT)
	var guard_script := _compiled(GUARD_SCRIPT)
	if content_db_script == null or validator_script == null or guard_script == null:
		_broken("the validator does not compile (see the SCRIPT ERROR / Parse Error lines above)")
		return exit_code
	var options := {}
	var world_dir := _arg_value(args, "--world-dir")
	if world_dir != "":
		options["world_dir"] = world_dir
	var t0 := Time.get_ticks_msec()
	# Everything that runs validator code (load, validate, format) runs under the guard.
	var guard: Object = guard_script.new()
	guard.call("attach")
	var db: Object = content_db_script.new()
	db.call("load_all")
	var report: Object = validator_script.call("validate", db, options)
	var text := ""
	var as_dict: Dictionary = {}
	var failed := true
	var provenance_doc: Dictionary = {}
	var provenance_md := ""
	var report_json := _arg_value(args, "--report-json")
	var report_md := _arg_value(args, "--report-md")
	if report != null:
		text = report.call("format_text", args.has("--verbose"))
		as_dict = report.call("to_dict")
		failed = bool(report.call("has_errors")) or (args.has("--strict") and int(report.call("warning_count")) > 0)
		if report_json != "" or report_md != "":
			var report_script := _compiled(REPORT_SCRIPT)
			if report_script != null:
				provenance_doc = report_script.call("build", db, report)
				provenance_md = report_script.call("to_markdown", provenance_doc)
	guard.call("detach")
	# This guard sees every script error DataValidator.validate() turns into a "validator" finding, plus any raised
	# while loading or formatting; either way the report is incomplete.
	var script_errors: PackedStringArray = guard.call("errors")
	var self_reported: Array = report.call("matching", "validator") if report != null else []
	if report == null or not script_errors.is_empty() or not self_reported.is_empty():
		for e in script_errors:
			print("VALIDATION ERROR script error inside the validator: %s" % e)
		_broken("the validator raised script errors, so its report is incomplete")
		return exit_code
	print("MisoStory canonical data validation (%d ms)" % (Time.get_ticks_msec() - t0))
	print(text)
	# The art pack coverage check (ArtPackChecks): covered, missing, or no pack (not a failure).
	print("ART PACK coverage: %s" % report.stats.get("art_pack", "not run"))
	var json_path := _arg_value(args, "--json")
	if json_path != "" and not _write_json(json_path, as_dict):
		_broken("cannot write %s (%s)" % [json_path, error_string(FileAccess.get_open_error())])
		return exit_code
	if (report_json != "" or report_md != "") and provenance_doc.is_empty():
		_broken("the provenance report could not be built (see the lines above)")
		return exit_code
	if report_json != "" and not _write_json(report_json, provenance_doc):
		_broken("cannot write %s (%s)" % [report_json, error_string(FileAccess.get_open_error())])
		return exit_code
	if report_md != "" and not _write_text(report_md, provenance_md):
		_broken("cannot write %s (%s)" % [report_md, error_string(FileAccess.get_open_error())])
		return exit_code
	print("VALIDATION_FAILED" if failed else "VALIDATION_PASSED")
	exit_code = EXIT_DATA_ERRORS if failed else EXIT_PASSED
	return exit_code


## The script at `path` if it loads and compiles, else null (Godot has already printed why).
static func _compiled(path: String) -> GDScript:
	var res: Resource = load(path)
	var script := res as GDScript
	if script == null or not script.can_instantiate():
		print("VALIDATION ERROR %s does not compile" % path)
		return null
	return script


static func _write_json(path: String, data: Variant) -> bool:
	return _write_text(path, JSON.stringify(data, "  ") + "\n")


static func _write_text(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text if text.ends_with("\n") else text + "\n")
	f.close()
	print("report written to %s" % path)
	return true


## "" when every argument is a known flag (and value flags have a value), else a description of the first bad one.
static func _bad_args(args: PackedStringArray) -> String:
	var i := 0
	while i < args.size():
		var a := args[i]
		if a in VALUE_FLAGS:
			if i + 1 >= args.size() or args[i + 1].begins_with("--"):
				return "%s needs a value" % a
			i += 2
			continue
		if not (a in FLAGS):
			return "unknown argument '%s'" % a
		i += 1
	return ""


static func _arg_value(args: PackedStringArray, flag: String) -> String:
	var i := args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else ""


func _broken(why: String) -> void:
	exit_code = EXIT_VALIDATOR_BROKEN
	print("VALIDATION ERROR %s" % why)
	print("VALIDATION_FAILED")


func _on_watchdog() -> void:
	print("VALIDATION ERROR the validator did not finish within %d s" % int(WATCHDOG_S))
	print("VALIDATION_FAILED")
	get_tree().quit(EXIT_VALIDATOR_BROKEN)
