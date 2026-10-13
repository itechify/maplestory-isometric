class_name ArtPackChecks
extends RefCounted
## The art pack coverage check (#62): when the pinned art pack is installed, every ID the game requires art for
## (ArtPack.required_ids: the canonical NPCs, monsters, items and breakables, and the kit @asset names the island
## places) must resolve to an imported model, or the run fails with one error per ID. Without the pack (a fresh clone,
## an isolated run without it) nothing fails: stats.art_pack says "no pack".
##
## Options (DataValidator): art_pack (an ArtPack; default ArtPack.load_installed()), art_pack_exists (a Callable
## deciding whether a model path exists; default ResourceLoader.exists).

const CHECK := "art_pack"

var db: ContentDB
var report: ValidationReport
var options: Dictionary


func _init(content: ContentDB, validation_report: ValidationReport, opts: Dictionary = {}) -> void:
	db = content
	report = validation_report
	options = opts


func run() -> void:
	var art: ArtPack = options.get("art_pack", null)
	if art == null:
		art = ArtPack.load_installed()
	var exists: Callable = options.get("art_pack_exists", Callable(ResourceLoader, "exists"))
	var result := art.coverage(ArtPack.required_ids(db), exists)
	report.stats[CHECK] = result.status
	report.count("art_pack_ids_checked", int(result.checked))
	for m in result.missing:
		report.error(CHECK, CHECK, "%s:%s" % [m.kind, m.id], "no art for %s %s in %s: %s" % [m.kind, m.id, art.root, m.why])
