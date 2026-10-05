extends TestCase
## The resume-point guard of the load chain (ArrivalResolver.resolve_load, docs/runtime/SAVES.md): a saved resume
## point is used only while its map's content_hash still equals the map_content_hash saved with it. When the map's
## collision changed (an Iteration Three trap fix, say), the player arrives at the saved entry instead of a position
## vetted against geometry that no longer exists. Saves without a hash, and builds without the world export, keep the
## physical validation alone.

const MAP := "000000042"
const IT2_DIR := "res://tests/data/saves/it2"

var defs: MapDefinitions
var validated: Array = []


func parity_keys() -> Dictionary:
	return {
		"test_matching_hash_resumes_where_the_save_was": ["persistence:current-map"],
		"test_changed_map_arrives_at_the_entry": ["persistence:current-map"],
		"test_it2_fixtures_resume_only_on_unchanged_maps": ["persistence:current-map", "mechanic:save-migration"],
	}


func before_each() -> void:
	if defs == null:
		defs = MapDefinitions.build(db())
	defs.get_def(MAP).content_hash = "c0ffee00c0ffee00"
	validated = []


func after_each() -> void:
	defs.get_def(MAP).content_hash = ""


func _location(hash: Variant) -> Dictionary:
	var resume := {"local_pos": [4.0, 0.5, -2.0], "facing_deg": 90.0}
	if hash != null:
		resume["map_content_hash"] = hash
	return {"map_id": MAP, "entry": {"map_id": MAP, "portal_id": "west00"}, "resume": resume}


func _resolve(location: Dictionary) -> Dictionary:
	return ArrivalResolver.resolve_load(location, defs, func(m: String, p: Vector3) -> bool:
		validated.append([m, p])
		return true, "000000001")


func test_matching_hash_resumes_where_the_save_was() -> void:
	var r := _resolve(_location("c0ffee00c0ffee00"))
	assert_eq(String(r.step), ArrivalResolver.STEP_RESUME, "the map is unchanged: resume")
	assert_true((r.xform as Transform3D).origin.is_equal_approx(defs.get_def(MAP).to_world(Vector3(4.0, 0.5, -2.0))),
		"at the saved position")
	assert_eq(validated.size(), 1, "and still physically validated")
	assert_eq(r.errors, PackedStringArray(), "no complaint")


func test_changed_map_arrives_at_the_entry() -> void:
	var r := _resolve(_location("9df259dc7e14e093"))
	assert_eq(String(r.step), ArrivalResolver.STEP_ENTRY, "the map changed: the entry, not the stored position")
	assert_eq((r.arrival as ArrivalRef).portal_id, "west00", "the saved entry portal")
	assert_eq(validated.size(), 0, "the stale point is not even offered to the validator")
	assert_eq(r.errors.size(), 1, "one logged reason")
	assert_true(r.errors[0].contains("changed since the save") and r.errors[0].contains("9df259dc7e14e093"),
		r.errors[0])
	# No usable entry: the map's first player spawn, still never the stale point.
	var no_entry := _location("9df259dc7e14e093")
	no_entry.erase("entry")
	var r2 := _resolve(no_entry)
	assert_eq(String(r2.step), ArrivalResolver.STEP_PLAYER_SPAWN, "falls through to player_spawns[0]")


func test_without_both_hashes_only_the_physical_check_applies() -> void:
	assert_eq(String(_resolve(_location(null)).step), ArrivalResolver.STEP_RESUME, "an old save without a hash")
	assert_eq(String(_resolve(_location("")).step), ArrivalResolver.STEP_RESUME, "an empty saved hash")
	assert_eq(String(_resolve(_location(17)).step), ArrivalResolver.STEP_RESUME, "a non-string hash is ignored")
	defs.get_def(MAP).content_hash = ""
	assert_eq(String(_resolve(_location("9df259dc7e14e093")).step), ArrivalResolver.STEP_RESUME,
		"no world export: the current hash is unknown")
	assert_eq(validated.size(), 4, "each one physically validated")
	var refused := ArrivalResolver.resolve_load(_location(null), defs, func(_m: String, _p: Vector3) -> bool: return false,
		"000000001")
	assert_eq(String(refused.step), ArrivalResolver.STEP_ENTRY, "the physical check still refuses bad points")


## With the exported world: each real Iteration Two save resumes at its point exactly when its map's collision hash
## is unchanged since the save, and arrives at its entry otherwise. (The fixtures matched the world when they were
## promoted; a rebuild that changes one of their maps moves that fixture to the entry branch.) Then, independently of
## what the current export holds, each fixture's map is made to look rebuilt (its hash changed): the stale point is
## never used and the player arrives exactly at the saved entry, resolved against the real exported map.
func test_it2_fixtures_resume_only_on_unchanged_maps() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_it2_fixtures_resume_only_on_unchanged_maps: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var world_defs := MapDefinitions.build(db(), WorldSidecars.load_dir())
	var fixtures := 0
	for f in DirAccess.get_files_at(IT2_DIR):
		if f.get_extension() != "json":
			continue
		fixtures += 1
		var r := SaveDocument.decode(JSON.parse_string(FileAccess.get_file_as_string(IT2_DIR.path_join(f))),
			SaveMigrations.new(), db())
		var loc := r.character.location
		var saved := String((loc["resume"] as Dictionary)["map_content_hash"])
		var def := world_defs.get_def(String(loc["map_id"]))
		var current := def.content_hash
		assert_ne(current, "", "%s: the world export has a hash for %s" % [f, loc["map_id"]])
		assert_eq(saved.length(), current.length(), "%s: the saved hash has the export's format" % f)
		var offered: Array = []
		var res := ArrivalResolver.resolve_load(loc, world_defs, func(_m: String, p: Vector3) -> bool:
			offered.append(p)
			return true, "000000001")
		var want := ArrivalResolver.STEP_RESUME if saved == current else ArrivalResolver.STEP_ENTRY
		assert_eq(String(res.step), want, "%s (saved %s, now %s)" % [f, saved, current])
		# The same save after a rebuild of its map.
		def.content_hash = "rebuilt-" + current
		offered.clear()
		var moved := ArrivalResolver.resolve_load(loc, world_defs, func(_m: String, p: Vector3) -> bool:
			offered.append(p)
			return true, "000000001")
		def.content_hash = current
		assert_eq(String(moved.step), ArrivalResolver.STEP_ENTRY, "%s: a changed map arrives at the entry" % f)
		assert_true(bool(moved.ok), "%s: the saved entry resolves in the exported map" % f)
		assert_eq(offered.size(), 0, "%s: the stale point is never offered to the validator" % f)
		var entry := ArrivalRef.from_dict(loc["entry"])
		assert_eq(str(moved.arrival), str(entry), "%s: the arrival is the saved entry" % f)
		assert_true((moved.xform as Transform3D).is_equal_approx(world_defs.arrival_transform(entry).xform),
			"%s: at the entry's spawn transform" % f)
	assert_eq(fixtures, 6, "every Iteration Two fixture checked")
