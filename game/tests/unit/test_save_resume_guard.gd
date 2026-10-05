extends TestCase
## The resume-point guard of the load chain (ArrivalResolver.resolve_load, docs/runtime/SAVES.md): a saved resume
## point is used only while its map's content_hash still equals the map_content_hash saved with it. The hash covers the
## map chunk's collision and that of every shared world chunk overlapping the map's region (MapDefinitions.resume_hash).
## When that collision changed (an Iteration Three trap fix, say), the player arrives at the saved entry instead of a position
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
		"test_resume_hash_covers_the_shared_chunks_the_region_overlaps": ["persistence:current-map"],
		"test_with_the_world_the_island_maps_cover_their_shared_chunks": ["persistence:current-map"],
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


## The guard covers the shared world chunks too (MapDefinitions.resume_hash): a trap fix may land in World_Plinths,
## World_Trails or World_IslandBody instead of the map's own chunk. The resume hash folds in the collision hash of every
## world chunk whose bounds overlap the map's region, so a change to one of them makes a saved point stale, while a
## chunk far away, a chunk without collision and the visual or sidecar hashes do not.
func test_resume_hash_covers_the_shared_chunks_the_region_overlaps() -> void:
	var map_hash := "0123456789abcdef"
	var fp := PackedVector2Array([Vector2(10, 10), Vector2(20, 10), Vector2(20, 20), Vector2(10, 20)])
	var sc := _sidecars({"World_A": "1111111111111111", "World_B": "2222222222222222", "World_Far": "3333333333333333"})
	var r := MapDefinitions.resume_hash(map_hash, fp, sc)
	assert_eq(r.chunks, PackedStringArray(["map", "World_A", "World_B"]), "the map's chunk and the overlapping world chunks")
	assert_eq(String(r.hash).length(), map_hash.length(), "the export's hash format")
	assert_ne(String(r.hash), map_hash, "not the map chunk's hash alone")
	assert_eq(String(MapDefinitions.resume_hash(map_hash, fp, sc).hash), String(r.hash), "deterministic")
	var plinths_fixed := _sidecars({"World_A": "1111111111110000", "World_B": "2222222222222222", "World_Far": "3333333333333333"})
	assert_ne(String(MapDefinitions.resume_hash(map_hash, fp, plinths_fixed).hash), String(r.hash),
		"a fix in an overlapping shared chunk changes the hash")
	var far_changed := _sidecars({"World_A": "1111111111111111", "World_B": "2222222222222222", "World_Far": "0000000000000000"})
	assert_eq(String(MapDefinitions.resume_hash(map_hash, fp, far_changed).hash), String(r.hash),
		"a chunk that does not reach the region does not matter")
	var visuals_changed := _sidecars({"World_A": "1111111111111111", "World_B": "2222222222222222", "World_Far": "3333333333333333"},
		"ffffffffffffffff")
	assert_eq(String(MapDefinitions.resume_hash(map_hash, fp, visuals_changed).hash), String(r.hash), "only collision counts")
	assert_ne(String(MapDefinitions.resume_hash("0123456789abcde0", fp, sc).hash), String(r.hash), "the map's own chunk counts")
	# A region no shared chunk reaches (an interior stage) keeps its own hash.
	var away := PackedVector2Array([Vector2(5000, 5000), Vector2(5010, 5000), Vector2(5010, 5010)])
	var lone := MapDefinitions.resume_hash(map_hash, away, sc)
	assert_eq(String(lone.hash), map_hash)
	assert_eq(lone.chunks, PackedStringArray(["map"]))
	assert_eq(String(MapDefinitions.resume_hash("", fp, sc).hash), "", "no map hash, no guard")
	# Through the load chain: a point saved before the shared chunk changed is not used.
	var def := defs.get_def(MAP)
	def.content_hash = String(MapDefinitions.resume_hash(map_hash, fp, plinths_fixed).hash)
	var res := _resolve(_location(String(r.hash)))
	assert_eq(String(res.step), ArrivalResolver.STEP_ENTRY, "a shared-chunk fix since the save: the entry")
	assert_eq(validated.size(), 0, "the stale point is never offered")
	def.content_hash = String(r.hash)
	assert_eq(String(_resolve(_location(String(r.hash))).step), ArrivalResolver.STEP_RESUME, "unchanged: resume")


## A hand-made export: a map chunk and the world chunks of `world_hashes` (name -> collision hash). World_A and
## World_B overlap x/z 0..100; World_Far lies at 1000; World_Sky has no collision. `visual` is every visual hash.
func _sidecars(world_hashes: Dictionary, visual: String = "aaaaaaaaaaaaaaaa") -> WorldSidecars:
	var sc := WorldSidecars.new()
	var listed := {"Map_1": {"content_hash": {"collision": "0123456789abcdef", "visual": visual}},
		"World_Sky": {"content_hash": {"collision": null, "visual": visual}}}
	sc.chunks = {"Map_1": {"kind": "map"}, "World_Sky": {"kind": "world", "bounds": {"position": [0, 0, 0], "size": [100, 10, 100]}}}
	var where := {"World_A": [[0, -5, 0], [100, 10, 100]], "World_B": [[15, 0, 15], [60, 5, 60]],
		"World_Far": [[1000, 0, 1000], [10, 10, 10]]}
	for n: String in world_hashes:
		listed[n] = {"content_hash": {"collision": world_hashes[n], "visual": visual}}
		sc.chunks[n] = {"kind": "world", "bounds": {"position": where[n][0], "size": where[n][1]}}
	sc.index = {"chunks": listed}
	return sc


## With the exported world: every map's resume hash folds in the shared chunks under it. The island maps all sit on
## World_IslandBody, so their hash is not the map chunk's alone; changing the export's World_Plinths collision hash
## (where most Iteration Three fills are) changes the hash of exactly the maps the plinths reach, and leaves the
## interiors, which no shared chunk reaches, alone.
func test_with_the_world_the_island_maps_cover_their_shared_chunks() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_with_the_world_the_island_maps_cover_their_shared_chunks: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var sc := WorldSidecars.load_dir()
	var world_defs := MapDefinitions.build(db(), sc)
	var before := {}
	var on_plinths := 0
	for id in world_defs.ids():
		var def := world_defs.get_def(id)
		var own := String(sc.content_hash(def.slug).get("collision", ""))
		assert_ne(own, "", "%s has a collision hash" % id)
		before[id] = def.content_hash
		if "World_Plinths" in def.content_hash_chunks:
			on_plinths += 1
		if not def.is_interior():
			assert_true("World_IslandBody" in def.content_hash_chunks, "%s covers the island body: %s" % [id, def.content_hash_chunks])
			assert_ne(def.content_hash, own, "%s: not the map chunk's hash alone" % id)
		else:
			assert_eq(def.content_hash == own, def.content_hash_chunks.size() == 1,
				"%s: an interior keeps its own hash exactly when no shared chunk reaches it" % id)
	assert_true(on_plinths >= 15, "most island maps stand on World_Plinths (%d)" % on_plinths)
	var fixed := WorldSidecars.load_dir()
	((fixed.index["chunks"] as Dictionary)["World_Plinths"]["content_hash"] as Dictionary)["collision"] = "0000000000000000"
	var after := MapDefinitions.build(db(), fixed)
	for id in world_defs.ids():
		var def := world_defs.get_def(id)
		var changed := String(after.get_def(id).content_hash) != String(before[id])
		assert_eq(changed, "World_Plinths" in def.content_hash_chunks,
			"%s: a World_Plinths fix changes the hash exactly where the plinths reach" % id)


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
