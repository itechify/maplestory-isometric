extends TestCase
## Id resolution (DebugResolve) and Tab completion (DebugCompleter): MeowDB ids, v8 ids, padded ids, slugs and name
## fragments for maps; ids and names for items, monsters and quests; ambiguity reported, never guessed.

var defs: MapDefinitions = null


func before_each() -> void:
	defs = MapDefinitions.build(db())


func _map(token: String) -> String:
	var r := DebugResolve.map_id(token, defs)
	return String(r.id) if bool(r.ok) else "ERR " + String(r.error)


func test_every_map_resolves_by_meowdb_id_v8_id_and_slug() -> void:
	assert_eq(defs.ids().size(), 25, "25 maps")
	for id in defs.ids():
		var def := defs.get_def(id)
		assert_eq(_map(id), id, "MeowDB id")
		assert_eq(_map(str(def.gms_v8_id)), id, "v8 id %d" % def.gms_v8_id)
		assert_eq(_map(def.slug), id, "slug")
		assert_eq(_map(def.slug.to_lower()), id, "slug, any case")


func test_map_short_ids_and_names() -> void:
	assert_eq(_map("40000"), "000000040", "v8 id")
	assert_eq(_map("40"), "000000040", "MeowDB id without zeros")
	assert_eq(_map("0"), "000000001", "v8 id 0 is the west entrance")
	assert_eq(_map("snail hunting ground 1"), "000000040", "slug words")
	assert_eq(_map("Southperry"), defs.id_of_v8["60000"], "exact name")
	assert_eq(_map("tomato"), defs.id_of_v8["1020001"], "unique fragment")
	assert_eq(_map("amherst weapon"), defs.id_of_v8["1010001"], "fragment with spaces")


func test_map_ambiguity_and_misses_are_reported() -> void:
	var r := DebugResolve.map_id("Mushroom Town", defs)
	assert_false(bool(r.ok), "two maps are named Mushroom Town")
	assert_true(String(r.error).contains("000000010") and String(r.error).contains("000000020"), String(r.error))
	assert_true((r.candidates as PackedStringArray).size() >= 2, "candidates")
	assert_false(bool(DebugResolve.map_id("atlantis", defs).ok), "no match")
	assert_false(bool(DebugResolve.map_id("", defs).ok), "empty")
	assert_false(bool(DebugResolve.map_id("999999999", defs).ok), "unknown id")


func test_items_monsters_quests_by_id_and_name() -> void:
	assert_eq(String(DebugResolve.item_id("270", db()).id), "270", "item id")
	assert_eq(String(DebugResolve.item_id("red potion", db()).id), "270", "item name")
	assert_eq(String(DebugResolve.monster_id("2", db()).id), "2", "monster id")
	assert_eq(String(DebugResolve.monster_id("orange mushroom", db()).id), _id_named("monsters", "Orange Mushroom"), "monster name")
	assert_eq(String(DebugResolve.quest_id("1006", db()).id), "1006", "quest id")
	assert_eq(String(DebugResolve.quest_id("sam's suggestion", db()).id), "1006", "quest name, punctuation ignored")
	var snail := DebugResolve.monster_id("snail", db())
	assert_eq(String(snail.id), "2", "the exact name beats Blue Snail / Red Snail")
	var potion := DebugResolve.item_id("potion", db())
	assert_false(bool(potion.ok), "several potions are ambiguous")
	assert_true((potion.candidates as PackedStringArray).size() > 1, "candidates listed")
	assert_false(bool(DebugResolve.item_id("27", db()).ok), "an id prefix is not an id")


func test_portal_ids_are_case_insensitive_and_listed_on_error() -> void:
	var def := defs.get_def("000000040")
	var any_id := def.portals[0].portal_id
	assert_eq(String(DebugResolve.portal_id(any_id.to_upper(), def).id), any_id, "case")
	var bad := DebugResolve.portal_id("nope", def)
	assert_false(bool(bad.ok), "unknown portal")
	assert_true(String(bad.error).contains(any_id), "lists the portals")


func test_search_lists_matching_rows() -> void:
	var rows := DebugResolve.search("items", "potion", db())
	assert_true(rows.size() > 1, "potions found")
	for r in rows:
		assert_true(r.to_lower().contains("potion"), r)
	assert_eq(DebugResolve.search("monsters", "", db()).size(), db().ids("monsters").size(), "all")


func test_completion_of_commands_and_arguments() -> void:
	var dbg := DebugTools.new()
	dbg.content = db()
	dbg.session = load("res://scripts/autoload/map_session.gd").new()
	dbg.session.set("defs", defs)
	dbg.register_command("warp", "", func(_a: PackedStringArray) -> String: return "")
	dbg.register_command("warpzone", "", func(_a: PackedStringArray) -> String: return "")
	dbg.register_command("give", "", func(_a: PackedStringArray) -> String: return "")
	dbg.register_command("quest", "", func(_a: PackedStringArray) -> String: return "")
	dbg.set_completion("warp", ["map", "portal"])
	dbg.set_completion("give", ["item"])
	dbg.set_completion("quest", ["quest_sub", "quest"])
	var r := dbg.complete("wa")
	assert_eq(String(r.line), "warp", "common prefix of warp / warpzone")
	assert_eq((r.candidates as PackedStringArray).size(), 2, "both listed")
	assert_eq(String(dbg.complete("gi").line), "give ", "unique command completes with a space")
	r = dbg.complete("warp 00000004")
	assert_true(String(r.line).begins_with("warp 00000004"), "map id prefix kept: " + String(r.line))
	assert_true((r.candidates as PackedStringArray).size() >= 3, "40, 41, 42 listed")
	assert_eq(String(dbg.complete("warp tomato").line), "warp %s " % defs.id_of_v8["1020001"], "a unique name becomes its id")
	var p := dbg.complete("warp 000000040 ")
	assert_true((p.candidates as PackedStringArray).size() >= 2, "portals of 000000040: %s" % str(p.candidates))
	assert_eq(String(dbg.complete("give red pot").line), "give 270 ", "item name -> id")
	assert_eq(String(dbg.complete("quest acc").line), "quest accept ", "quest subcommand")
	assert_eq(String(dbg.complete("quest accept 100").line), "quest accept 100", "quest ids share 100")
	assert_true((dbg.complete("quest accept 100").candidates as PackedStringArray).size() >= 10, "quest candidates")
	dbg.session.free()
	dbg.free()


func _id_named(domain: String, name: String) -> String:
	for id in db().ids(domain):
		if String(db().get_entity(domain, id).get("name", "")) == name:
			return id
	return "?"
