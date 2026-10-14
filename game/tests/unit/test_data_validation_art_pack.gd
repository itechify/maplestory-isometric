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
	# The stand-in pack maps two NPCs, one monster, three items, the box, four placed kit names, both presets, hair
	# styles 0 and 1, the bright and sleepy faces and two wearables: everything else the shipped data requires is
	# unmapped.
	var report := DataValidator.validate(db(), {"art_pack": ArtPack.load_from(FIXTURE),
		"art_pack_exists": func(_p: String) -> bool: return true})
	var errors := _art_errors(report)
	assert_eq(errors.size(), (21 - 2) + (6 - 1) + (94 - 3) + 0 + (123 - 4) + 0 + (6 - 2) + (3 - 2) + (40 - 2),
		"one error per required id without a model")
	for id in ["npc:21", "hair:5", "face:determined", "wearable:1158"]:
		assert_eq(report.matching(ArtPackChecks.CHECK, ArtPackChecks.CHECK, id).size(), 1, "%s is named" % id)
	assert_eq(report.stats.get("art_pack", ""), ArtPack.MISSING, "the summary says missing")


## #59 decision 7: the character's look and equipment need art as much as the NPCs do. Besides the canonical NPCs,
## monsters, items, breakables and placed kit names, the game requires both Beginner presets, the six hair styles and
## three faces creation offers (data/misostory/appearance.json), and a wearable for each of the 40 canonical items
## worn on the body (hats, tops, bottoms, shoes, gloves, earrings; weapons are held, so they need an ITEM model).
func test_the_look_and_the_wearables_are_required() -> void:
	var req := ArtPack.required_ids(db())
	var presets: Array = req.get(ArtPack.PRESET, [])
	presets.sort()
	assert_eq(presets, ["Beginner_Female", "Beginner_Male"], "both presets")
	assert_eq(req.get(ArtPack.HAIR, []), ["0", "1", "2", "3", "4", "5"], "six hair styles")
	assert_eq(req.get(ArtPack.FACE, []), ["bright", "determined", "sleepy"], "three faces")
	var worn: Array = req.get(ArtPack.WEARABLE, [])
	assert_eq(worn.size(), 40, "40 worn items")
	assert_true("708" in worn and "1158" in worn, "the Brown Skullcap and a bottom")
	assert_false("541" in worn, "not a sword (held)")


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
	assert_eq(_art_errors(report), [] as Array[Dictionary], "art-pack-v1.0 covers 21 NPCs, 6 monsters, 94 items, the box, 123 kit names, 2 presets, 6 hair styles, 3 faces and 40 wearables")
	assert_eq(report.stats.get("art_pack", ""), ArtPack.COVERED, "the summary says covered")
