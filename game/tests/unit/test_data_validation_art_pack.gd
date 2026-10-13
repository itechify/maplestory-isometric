extends TestCase
## The art pack coverage check in DataValidator (ArtPackChecks, #62): with the pack present every required ID needs a
## model, without it the run reports "no pack" and passes.

const FIXTURE := "res://tests/data/art_pack"


func _art_errors(report: ValidationReport) -> Array[Dictionary]:
	return report.matching(ArtPackChecks.CHECK, "", "", ValidationReport.ERROR)


func test_without_the_pack_the_check_reports_no_pack_and_passes() -> void:
	var report := DataValidator.validate(db(), {"art_pack": ArtPack.load_from("res://tests/data/no_such_pack")})
	assert_eq(_art_errors(report), [] as Array[Dictionary], "no art_pack errors")
	assert_eq(report.stats.get("art_pack", ""), ArtPack.NO_PACK, "the summary says no pack")
	assert_false(report.has_errors(), "the shipped data still validates")


func test_a_pack_missing_required_models_fails_naming_each_id() -> void:
	# The stand-in pack maps two NPCs, one monster, three items, the box and four placed kit names: everything else the
	# shipped data requires is unmapped.
	var report := DataValidator.validate(db(), {"art_pack": ArtPack.load_from(FIXTURE),
		"art_pack_exists": func(_p: String) -> bool: return true})
	var errors := _art_errors(report)
	assert_eq(errors.size(), (21 - 2) + (6 - 1) + (94 - 3) + 0 + (123 - 4), "one error per required id without a model")
	assert_eq(report.matching(ArtPackChecks.CHECK, ArtPackChecks.CHECK, "npc:21").size(), 1, "NPC 21 (Lucy) is named")
	assert_eq(report.stats.get("art_pack", ""), ArtPack.MISSING, "the summary says missing")


func test_a_removed_model_file_fails_the_check() -> void:
	var gone := FIXTURE.path_join("monsters/WoodenBox.glb")
	var report := DataValidator.validate(db(), {"art_pack": ArtPack.load_from(FIXTURE),
		"art_pack_exists": func(p: String) -> bool: return p != gone})
	var box := report.matching(ArtPackChecks.CHECK, ArtPackChecks.CHECK, "breakable:0000001")
	assert_eq(box.size(), 1, "the Wooden Box is named")
	if box.size() == 1:
		assert_true(String(box[0].message).contains("WoodenBox.glb"), "with its missing file: %s" % box[0].message)


func test_the_installed_pack_covers_every_required_id() -> void:
	var art := ArtPack.load_installed()
	if not art.present():
		print("SKIP test_the_installed_pack_covers_every_required_id: no art pack installed (bash scripts/art_pack.sh fetch)")
		return
	var report := DataValidator.validate(db(), {"art_pack": art})
	assert_eq(_art_errors(report), [] as Array[Dictionary], "art-pack-v1.0 covers 21 NPCs, 6 monsters, 94 items, the box and 123 kit names")
	assert_eq(report.stats.get("art_pack", ""), ArtPack.COVERED, "the summary says covered")
