extends TestCase
## ArtPack: Project art looked up by canonical ID through the pack's asset_index.json and manifests, never by file
## name (#62), and the coverage check over the IDs the game requires. Runs on the stand-in pack in
## tests/data/art_pack (no models needed); test_art_pack_imported.gd checks the real, imported pack.

const FIXTURE := "res://tests/data/art_pack"


func _pack() -> ArtPack:
	return ArtPack.load_from(FIXTURE)


func _at(rel: String) -> String:
	return FIXTURE.path_join(rel)


# --- lookup by ID ------------------------------------------------------------------------------------------------

func test_an_npc_resolves_by_its_canonical_id() -> void:
	assert_eq(_pack().model(ArtPack.NPC, "15"), _at("characters/glb/Shanks.glb"), "NPC 15 is Shanks")
	assert_eq(_pack().model(ArtPack.NPC, "2101"), "", "the GMS NPC id is not a canonical id")


func test_a_monster_resolves_by_its_canonical_id() -> void:
	assert_eq(_pack().model(ArtPack.MONSTER, "2"), _at("monsters/Snail.glb"), "monster 2 is the Snail")


func test_an_item_resolves_by_its_game_item_id_and_by_its_id() -> void:
	assert_eq(_pack().model(ArtPack.ITEM, "1302000"), _at("equipment/glb/item_1302000_Sword.glb"), "by game_item_id")
	assert_eq(_pack().model(ArtPack.ITEM, "541"), _at("equipment/glb/item_1302000_Sword.glb"), "by canonical id")
	assert_eq(_pack().icon(ArtPack.ITEM, "1302000"), _at("icons/equipment/item_1302000_Sword.png"), "its icon")
	assert_eq(_pack().model(ArtPack.ITEM, "4000001"), _at("monsters/SnailShell.glb"), "a drop's model sits with the monsters")


func test_a_wearable_resolves_by_item_id_though_its_file_is_named_by_meowdb_id() -> void:
	assert_eq(_pack().model(ArtPack.WEARABLE, "1060001"), _at("characters/wearables/1157_Blue_Jean_Shorts.glb"), "by game_item_id")
	assert_eq(_pack().model(ArtPack.WEARABLE, "1157"), _at("characters/wearables/1157_Blue_Jean_Shorts.glb"), "by canonical id")
	assert_eq(_pack().model(ArtPack.WEARABLE, "1302000"), "", "a weapon is not a wearable")


func test_aliased_kit_assets_resolve_explicitly_to_one_shared_model() -> void:
	var p := _pack()
	assert_eq(p.model(ArtPack.KIT, "Sign_Board"), _at("environment/glb/noticeboard.glb"), "Sign_Board")
	assert_eq(p.model(ArtPack.KIT, "Signpost_Notice"), _at("environment/glb/noticeboard.glb"), "Signpost_Notice shares it")
	assert_eq(p.model(ArtPack.KIT, "Bed"), _at("environment/glb/Bed.glb"), "Bed keeps the catalog's Bed.glb")
	assert_eq(p.model(ArtPack.KIT, "Noticeboard"), "", "no guessing from file names")


func test_the_wooden_box_resolves_by_its_breakable_id() -> void:
	assert_eq(_pack().model(ArtPack.BREAKABLE, "0000001"), _at("monsters/WoodenBox.glb"), "breakable 0000001")


func test_presets_hair_face_skin_and_meso() -> void:
	var p := _pack()
	assert_eq(p.model(ArtPack.PRESET, "Beginner_Female"), _at("characters/glb/Beginner_Female.glb"), "preset")
	assert_eq(p.model(ArtPack.PRESET, "Heena"), "", "an NPC is not a preset")
	assert_eq(p.model(ArtPack.HAIR, "1"), _at("characters/modules/Hair_1.glb"), "hair style 1")
	assert_eq(p.model(ArtPack.FACE, "sleepy"), _at("characters/modules/Face_sleepy.glb"), "face style")
	assert_eq(p.model(ArtPack.MESO, ""), _at("monsters/Meso.glb"), "the one meso model")
	assert_eq(p.model(ArtPack.EFFECT, "HitSpark"), _at("monsters/HitSpark.glb"), "an effect by name")
	var skin := p.skin_color(1)
	# 0.42 linear is 0.6724 sRGB: materials hold sRGB albedo, so the palette is converted once here.
	assert_near(skin.r, Color(0.42, 0.2, 0.105).linear_to_srgb().r, 1e-5, "skin 1 in sRGB")
	assert_eq(p.ids(ArtPack.HAIR), PackedStringArray(["0", "1"]), "hair ids")
	assert_eq(p.ids(ArtPack.NPC), PackedStringArray(["1", "15"]), "npc ids")


func test_an_unknown_kind_or_id_resolves_to_nothing() -> void:
	assert_eq(_pack().model(ArtPack.NPC, "999"), "", "unknown NPC")
	assert_eq(_pack().model("vehicle", "1"), "", "unknown kind")
	assert_eq(_pack().instance(ArtPack.NPC, "1"), null, "no model file, no instance")


func test_without_a_pack_nothing_resolves_and_nothing_breaks() -> void:
	var p := ArtPack.load_from("res://tests/data/no_such_pack")
	assert_false(p.present(), "absent")
	assert_eq(p.model(ArtPack.NPC, "1"), "", "no path")
	assert_eq(p.instance(ArtPack.MONSTER, "2"), null, "no instance: callers keep their procedural placeholder")
	assert_true(_pack().present(), "the stand-in is present")


func test_the_installed_pack_comes_from_the_pin() -> void:
	assert_eq(ArtPack.install_dir(), "res://assets/art_pack", "art_pack.json install_dir")
	assert_near(ArtPack.character_scale(), 1.5 / 1.9825, 1e-4, "the one character factor")


## Every consumer the game wires shares one read of the installed pack (with or without the pack installed).
func test_the_shared_pack_is_the_installed_one_read_once() -> void:
	var a := ArtPack.shared()
	assert_true(a == ArtPack.shared(), "the same instance every time")
	assert_eq(a.root, ArtPack.install_dir(), "from the pin's install_dir")
	assert_eq(a.present(), ArtPack.load_installed().present(), "the installed pack")


# --- coverage ----------------------------------------------------------------------------------------------------

func _required() -> Dictionary:
	return {ArtPack.NPC: ["1", "15"], ArtPack.MONSTER: ["2"], ArtPack.ITEM: ["541", "348"],
		ArtPack.BREAKABLE: ["0000001"], ArtPack.KIT: ["Sign_Board", "Signpost_Notice", "Bed", "Player_Proxy"]}


func test_coverage_passes_when_every_required_id_has_a_model() -> void:
	var c := _pack().coverage(_required(), func(_p: String) -> bool: return true)
	assert_eq(c.status, ArtPack.COVERED, "covered: %s" % [c.missing])
	assert_eq(c.missing, [], "nothing missing")
	assert_eq(c.checked, 10, "every required id checked")


func test_coverage_fails_when_a_mapped_model_is_missing() -> void:
	var gone := _at("environment/glb/noticeboard.glb")
	var c := _pack().coverage(_required(), func(p: String) -> bool: return p != gone)
	assert_eq(c.status, ArtPack.MISSING, "a removed GLB fails the check")
	var ids := []
	for m in c.missing:
		ids.append("%s:%s" % [m.kind, m.id])
	assert_eq(ids, ["kit:Sign_Board", "kit:Signpost_Notice"], "both aliases of the removed model are named")


func test_coverage_fails_when_a_required_id_is_unmapped() -> void:
	var req := _required()
	req[ArtPack.NPC] = ["1", "15", "21"]
	var c := _pack().coverage(req, func(_p: String) -> bool: return true)
	assert_eq(c.status, ArtPack.MISSING, "unmapped NPC")
	assert_eq(c.missing.size(), 1, "one missing")
	assert_eq(c.missing[0].id, "21", "NPC 21 named")


func test_coverage_without_a_pack_reports_no_pack() -> void:
	var c := ArtPack.load_from("res://tests/data/no_such_pack").coverage(_required())
	assert_eq(c.status, ArtPack.NO_PACK, "no pack is not a failure")
	assert_eq(c.missing, [], "nothing listed")


func test_the_required_ids_are_every_npc_monster_item_box_and_placed_kit_asset() -> void:
	var req := ArtPack.required_ids(db())
	assert_eq(req[ArtPack.NPC].size(), 21, "21 NPCs")
	assert_eq(req[ArtPack.MONSTER].size(), 6, "6 monsters")
	assert_eq(req[ArtPack.ITEM].size(), 94, "94 items")
	assert_eq(req[ArtPack.BREAKABLE], ["0000001"], "the Wooden Box")
	assert_eq(req[ArtPack.KIT].size(), 123, "the 123 kit names the island places (of 149)")
	assert_true("Player_Proxy" in req[ArtPack.KIT] and not ("Ship_Southperry" in req[ArtPack.KIT]), "never-placed names are exempt")
