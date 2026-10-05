class_name SaveDocument
extends RefCounted
## The save-file envelope: builds it from live state and decodes (migrates, validates) it back. Pure, no file IO.
##
##   {"save_version": N, "game": "MisoStory", "saved_at": "2026-10-04T12:00:00Z",
##    "character": CharacterState.to_dict(),
##    "world": {"location": {...}, "respawn_reference": "...", ...whatever MapSession adds},
##    "meta": {"name", "level", "job", "map_id", "map_name", "play_time_s"}}
##
## The character block is CharacterState.to_dict() verbatim, so new CharacterState fields flow through without
## touching this file. "world" is authoritative for location and respawn_reference: on load it is copied back into
## the character. "meta" is a convenience for the slot picker and is recomputed on load.

const GAME_ID := "MisoStory"


## The envelope for `character` at the current schema version. `world` may be {} (then it is derived from the
## character). `db` (optional) resolves the map name for meta.
static func build(character: CharacterState, world: Dictionary, saved_at: String, db: ContentDB = null) -> Dictionary:
	var cd := character.to_dict()
	var w := world.duplicate(true)
	var loc: Variant = w.get("location", null)
	if loc is Dictionary and not (loc as Dictionary).is_empty():
		cd["location"] = (loc as Dictionary).duplicate(true)
	else:
		w["location"] = (cd.get("location", {}) as Dictionary).duplicate(true)
	var respawn: Variant = w.get("respawn_reference", null)
	if typeof(respawn) == TYPE_STRING and String(respawn) != "":
		cd["respawn_reference"] = String(respawn)
	else:
		w["respawn_reference"] = String(cd.get("respawn_reference", ""))
	return {
		"save_version": SaveMigrations.CURRENT_VERSION,
		"game": GAME_ID,
		"saved_at": saved_at,
		"character": cd,
		"world": w,
		"meta": make_meta(cd, w, db),
	}


## The world block a character implies when no MapSession data is available.
static func world_from_character(character: CharacterState) -> Dictionary:
	return {"location": character.location.duplicate(true), "respawn_reference": character.respawn_reference}


## Slot-picker summary of a character dict + world block.
static func make_meta(character_dict: Dictionary, world: Dictionary, db: ContentDB = null) -> Dictionary:
	var loc: Dictionary = world.get("location", {}) if world.get("location", {}) is Dictionary else {}
	var map_id := as_text(loc.get("map_id", ""))
	var map_name := ""
	if db != null and map_id != "":
		map_name = String(db.map(map_id).get("name", ""))
	return {
		"name": String(character_dict.get("name", "")),
		"level": int(character_dict.get("level", 0)),
		"job": String(character_dict.get("job", "")),
		"map_id": map_id,
		"map_name": map_name,
		"play_time_s": float(character_dict.get("play_time_s", 0.0)),
	}


## Migrates, validates and decodes a parsed save. Never crashes on bad input; returns a result with an error code:
##   ERR_INVALID_DATA  unknown, newer or unmigratable schema version
##   ERR_FILE_CORRUPT  not a MisoStory save, or a field of the wrong type
## With `db`, the location's map must exist (else the start location is used, with a warning) and the respawn
## reference is recomputed from the canonical return map (a mismatch is a warning; canonical wins). Saved item ids
## the item data does not define are kept and reported (r.unknown_item_ids and one warning; _check_items).
static func decode(raw: Dictionary, migrations: SaveMigrations, db: ContentDB = null) -> SaveLoadResult:
	var r := SaveLoadResult.new()
	var doc_in: Dictionary = normalize_numbers(raw)
	r.version_found = SaveMigrations.version_of(doc_in)
	var mig := migrations.migrate(doc_in, SaveMigrations.CURRENT_VERSION)
	if int(mig["error"]) != OK:
		# No save_version and the v0 step does not recognise it either: this is not a save at all.
		r.error = ERR_FILE_CORRUPT if r.version_found == 0 else ERR_INVALID_DATA
		r.message = String(mig["message"])
		return r
	r.migrations_applied = mig["applied"]
	var doc: Dictionary = mig["doc"]
	r.document = doc
	if as_text(doc.get("game", "")) != GAME_ID:
		return _corrupt(r, "not a %s save (game = %s)" % [GAME_ID, str(doc.get("game", null))])
	if not (doc.get("character", null) is Dictionary):
		return _corrupt(r, "the character block is missing or not an object")
	var cd: Dictionary = doc["character"]
	var problem := character_dict_problem(cd)
	if problem != "":
		return _corrupt(r, problem)
	var world: Dictionary = {}
	if doc.has("world"):
		if not (doc["world"] is Dictionary):
			return _corrupt(r, "the world block is not an object")
		world = (doc["world"] as Dictionary).duplicate(true)
	if world.has("location") and not (world["location"] is Dictionary):
		return _corrupt(r, "world.location is not an object")
	if world.has("respawn_reference") and typeof(world["respawn_reference"]) != TYPE_STRING:
		return _corrupt(r, "world.respawn_reference is not a string")
	var c := CharacterState.from_dict(cd)
	# A script error inside a module's from_dict() (a value of a type it cannot convert) aborts it and leaves null
	# behind; report the file as corrupt rather than hand on a half-built character (and never return null).
	if c == null or c.inventory == null or c.equipment == null or c.quests == null:
		return _corrupt(r, "the character block could not be decoded")
	_resolve_location(c, world, db, r)
	if db != null:
		_check_items(c, db, r)
	r.character = c
	r.world = world
	r.saved_at = String(doc.get("saved_at", "")) if typeof(doc.get("saved_at", "")) == TYPE_STRING else ""
	r.meta = make_meta(c.to_dict(), world, db)
	return r


## "" if every field of a character dict has the type CharacterState.from_dict() expects, else the first problem.
## The expected types come from a default CharacterState, so new fields are checked automatically.
static func character_dict_problem(cd: Dictionary) -> String:
	var defaults := CharacterState.new().to_dict()
	for key in cd:
		if not defaults.has(key):
			continue  # unknown keys are ignored by from_dict (forward compatible)
		var want := typeof(defaults[key])
		var got := typeof(cd[key])
		var numeric_ok := (want == TYPE_INT or want == TYPE_FLOAT) and (got == TYPE_INT or got == TYPE_FLOAT)
		if not (got == want or numeric_ok):
			return "character.%s is a %s, expected %s" % [String(key), type_string(got), type_string(want)]
	if cd.has("base_stats"):
		var bs: Dictionary = cd["base_stats"]
		for k in bs:
			if typeof(bs[k]) != TYPE_INT and typeof(bs[k]) != TYPE_FLOAT:
				return "character.base_stats.%s is not a number" % String(k)
	return ""


## JSON parses every number as float. Turns every integral float (|x| <= 2^53) back into int, recursively, so ids,
## counts and indices in free-form blocks (location, flags, quickslots, module blobs) come back as ints. Fields typed
## float in CharacterState are re-floated by from_dict(). A float that happened to be integral (e.g. 135.0) comes
## back as the int 135, which compares equal with == but not with Dictionary ==; see docs/runtime/SAVES.md.
static func normalize_numbers(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			if is_finite(f) and f == floorf(f) and absf(f) <= 9007199254740992.0:
				return int(f)
			return f
		TYPE_DICTIONARY:
			var d: Dictionary = value
			var out := {}
			for k in d:
				out[k] = normalize_numbers(d[k])
			return out
		TYPE_ARRAY:
			var arr: Array = value
			var out_arr := []
			for e in arr:
				out_arr.append(normalize_numbers(e))
			return out_arr
	return value


## A save value as text: strings as-is, numbers via str(), anything else (null, containers) as "".
static func as_text(v: Variant) -> String:
	match typeof(v):
		TYPE_STRING, TYPE_STRING_NAME:
			return String(v)
		TYPE_INT, TYPE_FLOAT:
			return str(v)
	return ""


# --- internals ------------------------------------------------------------------------------------------------

## The location with its MAP_ARCHITECTURE.md §4.9 fields checked, so MapSession never receives a malformed one:
##   - "map_id" becomes text;
##   - "entry" must be {"map_id": <this map>, "portal_id": non-empty String} or {"map_id", "spawn_index": int >= 0}
##     (with `db`, also < the map's player_spawns count); otherwise it becomes {"map_id", "spawn_index": 0};
##   - "resume", when present, must have "local_pos" = 3 finite numbers and, if present, a finite "facing_deg";
##     both are re-floated (JSON turned 135.0 into 135). A malformed resume is dropped, so the entry is used.
## Other keys (MapSession may add some) are kept. Every correction is appended to `warnings`.
## A location without a map_id is returned unchanged (the caller falls back to the start location).
static func sanitize_location(loc: Dictionary, warnings: PackedStringArray, db: ContentDB = null) -> Dictionary:
	var out := loc.duplicate(true)
	var map_id := as_text(out.get("map_id", ""))
	if map_id == "":
		return out
	out["map_id"] = map_id
	var entry: Variant = out.get("entry", null)
	if not _entry_ok(entry, map_id, db):
		if entry != null:
			warnings.append("location.entry %s is not an arrival in map %s; using player spawn 0"
				% [str(entry), map_id])
		out["entry"] = {"map_id": map_id, "spawn_index": 0}
	if out.has("resume"):
		var resume := _clean_resume(out["resume"])
		if resume.is_empty():
			warnings.append("location.resume %s is malformed; dropped (the entry is used instead)"
				% str(out["resume"]))
			out.erase("resume")
		else:
			out["resume"] = resume
	return out


static func _entry_ok(entry: Variant, map_id: String, db: ContentDB) -> bool:
	if not (entry is Dictionary):
		return false
	var e: Dictionary = entry
	if as_text(e.get("map_id", "")) != map_id:
		return false
	var portal: Variant = e.get("portal_id", null)
	if typeof(portal) == TYPE_STRING and String(portal) != "":
		return true
	var idx: Variant = e.get("spawn_index", null)
	if typeof(idx) != TYPE_INT or int(idx) < 0:
		return false
	if db != null and db.has("maps", map_id):
		return int(idx) < (db.map(map_id).get("player_spawns", []) as Array).size()
	return true


## A resume block with re-floated position/facing, or {} when it is malformed.
static func _clean_resume(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var src: Dictionary = v
	var lp: Variant = src.get("local_pos", null)
	if not (lp is Array) or (lp as Array).size() != 3:
		return {}
	var pos: Array = []
	for n: Variant in lp:
		if not _is_finite_number(n):
			return {}
		pos.append(float(n))
	var out := src.duplicate(true)
	out["local_pos"] = pos
	if src.has("facing_deg"):
		if not _is_finite_number(src["facing_deg"]):
			return {}
		out["facing_deg"] = float(src["facing_deg"])
	return out


static func _is_finite_number(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	return typeof(v) == TYPE_FLOAT and is_finite(float(v))


## world.location wins over the character's copy; both end up identical. The shape is always sanitized
## (sanitize_location); with db the map must exist and the respawn reference is recomputed from canonical data.
static func _resolve_location(c: CharacterState, world: Dictionary, db: ContentDB, r: SaveLoadResult) -> void:
	var loc: Dictionary = world.get("location", {})
	if loc.is_empty():
		loc = c.location
	var respawn := String(world.get("respawn_reference", c.respawn_reference))
	loc = sanitize_location(loc, r.warnings, db)
	if db != null:
		var map_id := as_text(loc.get("map_id", ""))
		if map_id == "" or not db.has("maps", map_id):
			var start := CharacterFactory.start_location(db)
			if map_id == "":
				r.warnings.append("the save has no location; using the start map %s" % String(start["map_id"]))
			else:
				r.warnings.append("unknown map %s in the save; using the start map %s" % [map_id, String(start["map_id"])])
			loc = start
			map_id = String(start["map_id"])
		var canonical_respawn := String(db.map(map_id).get("return_map_id", ""))
		if canonical_respawn != "" and canonical_respawn != respawn:
			if respawn != "":
				r.warnings.append("respawn_reference %s differs from %s's canonical return map %s; using canonical"
					% [respawn, map_id, canonical_respawn])
			respawn = canonical_respawn
	c.location = loc.duplicate(true)
	c.respawn_reference = respawn
	world["location"] = loc.duplicate(true)
	world["respawn_reference"] = respawn


## Lossless item checks. A saved item id the current item data does not define (an item a later build dropped, or a
## hand edit) stays exactly where it is: in its inventory slot, its equipment slot or its quickslot, so a build that
## defines it again gets it back and a re-save writes it unchanged. The game shows it as an unknown item that cannot
## be used, equipped or sold (every item path looks the id up and refuses an unknown one). The ids go to
## r.unknown_item_ids, and one warning counts the places that hold them (inventory stacks, equipped pieces,
## quickslot bindings). A known item held in another tab than its canonical inventory_tab is also kept where it is,
## with a warning.
static func _check_items(c: CharacterState, db: ContentDB, r: SaveLoadResult) -> void:
	var unknown := {}
	var places := 0
	for tab in Inventory.TABS:
		for s: Dictionary in c.inventory.slots(tab):
			if s.is_empty():
				continue
			var id := String(s["item_id"])
			if not db.has("items", id):
				unknown[id] = true
				places += 1
				continue
			var canonical_tab := String(db.item(id).get("inventory_tab", tab))
			if canonical_tab != tab:
				r.warnings.append("item %s is in the %s tab, but its canonical tab is %s; kept where it is"
					% [id, tab, canonical_tab])
	var equipped: Dictionary = c.equipment.equipped()
	for slot: String in equipped:
		if not db.has("items", String(equipped[slot])):
			unknown[String(equipped[slot])] = true
			places += 1
	for key: Variant in c.quickslots:
		var id := CharacterState.quickslot_item_id(c.quickslots[key])
		if id != "" and not db.has("items", id):
			unknown[id] = true
			places += 1
	if unknown.is_empty():
		return
	var ids := PackedStringArray(unknown.keys())
	ids.sort()
	r.unknown_item_ids = ids
	r.warnings.append(("%d saved item place(s) hold %d item id(s) this build's item data does not define (%s); "
		+ "kept as unknown items, which cannot be used or equipped") % [places, ids.size(), ", ".join(ids)])


static func _corrupt(r: SaveLoadResult, message: String) -> SaveLoadResult:
	r.error = ERR_FILE_CORRUPT
	r.message = message
	return r
