class_name DataValidator
extends RefCounted
## Validates MisoStory's local content (canonical MeowDB data + MisoStory adaptation data) as loaded by ContentDB,
## the same loader the game uses. Broken references are treated like compile errors: tools/validate_data.gd exits
## non-zero on any error, and tests/unit/test_data_validation.gd fails on any error in the shipped data.
##
##   var report := DataValidator.validate(ContentDB.new().load_all())
##   if report.has_errors(): print(report.format_text())
##
## Pure: it reads only the ContentDB it is given, plus the Blender export sidecars for the crosswalk slug check
## (options.world_dir, or options.world_sidecars injected by tests). It never touches the scene tree.
##
## The checks, in order (see docs/runtime/DATA_VALIDATION.md):
##   load            ContentDB load errors (unparsable JSON, a domain file whose top level is not an object)
##   ids, schema, provenance, external, sources_index      ProvenanceChecks (+ the ProvenanceAuthorities registry)
##   drop_record (+ provenance)                            DropRecordChecks (schema 3 drop records, contract C1)
##   drop_policy, drop_unresolved                          DropChecks (the drop policy over the shipped records, the
##                                                         dated captures and the owner's drop rule files)
##   reference, dialogue_link, portal, drop_owner, drop_table, consistency   ReferenceChecks (+ skill references and
##                                                                            the Phase 16 per-category counters)
##   chair, name, duplicate                                                   IntegrityChecks
##   adaptation, crosswalk                                                    AdaptationChecks
##   art_pack        every required ID has a model when the art pack is installed ("no pack" otherwise; ArtPackChecks)
##   quest_data, npc_data, dialogue_data   GameplayDataChecks (QuestCatalog / NpcCatalog / NpcDialogueBuilder
##                   validation, run over the records everything above found no error in)
##   validator       a script error inside any of the above (see validate())

## Check slug (and domain) of the findings that report a script error inside the validator itself.
const VALIDATOR_CHECK := "validator"

## Options:
##   world_dir: String          where the Blender export sidecars live (default "res://assets/world")
##   world_sidecars: Dictionary slug -> sidecar Dictionary; replaces the disk lookup (tests)
##   repo_root: String          the folder holding tools/*/captures (default: the folder above res://)
##   capture_files: Dictionary  capture path -> true; replaces the disk lookup of cited captures (tests)
##   art_pack: ArtPack          the art pack to check (default ArtPack.shared(), the installed pack) (tests)
##   art_pack_exists: Callable  whether a model path exists (default ResourceLoader.exists) (tests)
var options: Dictionary
var db: ContentDB
var report := ValidationReport.new()


func _init(content: ContentDB, opts: Dictionary = {}) -> void:
	db = content
	options = opts


## Validates `content` and returns the report. See the class doc for `opts`.
##
## The run is guarded: a GDScript runtime error inside a check aborts only that function (Godot carries on with the
## caller), which would silently skip the rest of the check and make broken data look clean. Every such error is
## turned into an error finding with check "validator" (domain "validator"), so a crashed validator never passes.
## tools/validate_data.gd exits 2 when it sees one.
static func validate(content: ContentDB, opts: Dictionary = {}) -> ValidationReport:
	var guard := ScriptErrorGuard.new()
	guard.attach()
	var validator := DataValidator.new(content, opts)
	validator.run()
	guard.detach()
	for e in guard.errors():
		validator.report.error(VALIDATOR_CHECK, VALIDATOR_CHECK, "",
			"script error inside the validator, so this report is incomplete: %s" % e)
	return validator.report


## Runs every check once and returns the report (call once per instance). Unguarded: prefer validate(), which also
## reports script errors raised by the checks.
func run() -> ValidationReport:
	if db == null:
		report.error("load", "load", "", "no ContentDB given")
		return report
	_check_load()
	if ValidationUtil.canonical_domains(db).is_empty():
		report.error("load", "load", "", "no canonical data loaded (is game/data/canonical present?)")
		return report
	var provenance := ProvenanceChecks.new(db, report, options)
	provenance.run()
	DropRecordChecks.new(db, report, provenance).run()
	DropChecks.new(db, report, provenance).run()
	var refs := ReferenceChecks.new(db, report)
	refs.run()
	IntegrityChecks.new(db, report).run()
	AdaptationChecks.new(db, report, refs, provenance, options).run()
	ArtPackChecks.new(db, report, options).run()
	refs.flush()
	# Last: the game's own quest / NPC / dialogue validation assumes structurally valid data, so it reads only the
	# records the checks above found no error in.
	GameplayDataChecks.new(db, report).run()
	return report


func _check_load() -> void:
	for e in db.load_errors:
		report.error("load", "load", _path_of(e), e)


## "res://data/x/y.json:3: msg" -> "res://data/x/y.json"; anything else unchanged.
static func _path_of(message: String) -> String:
	var at := message.find(".json")
	return message.substr(0, at + 5) if at >= 0 else message
