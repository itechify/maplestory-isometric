class_name AdaptationChecks
extends RefCounted
## Checks the MisoStory adaptation data in game/data/misostory (everything that is not a MeowDB fact).
##
## Every file gets, unless its FILE_SCHEMAS entry opts out:
##   convention   every adapted value carries a reason and a verified flag (see check_convention)
##   sweep        typed id keys (item_id, map_id, npc_id, ...) resolve against canonical data (ReferenceChecks)
##   domain folder  a file in misostory/<domain>/ where <domain> is a canonical domain adapts that canonical record,
##                so its basename must be a canonical id (misostory/quests/1002.json -> quest 1002). Exception: a
##                basename starting with "_" (SHARED_TABLE_PREFIX) is a shared adaptation table for that folder's
##                entity files, not an entity file (misostory/monsters/_shared.json: values every species shares), so
##                it is not matched against canonical ids; the convention, sweep and external checks still apply
##   external     `external` lists follow the canonical rule (field, source_url, reason, verified: false)
##   provenance   a top-level `provenance` block {<property>: source object} follows the authority registry
##                (ProvenanceChecks.check_source_object, contract C7), e.g. the project owner's natural-regen rule
##                ({"authority": "Project owner", "decision": "..."}); every `capture` key names an existing capture
## plus its file-specific check from FILE_SCHEMAS. Required files are checked even when absent.
##
## Adding a new adaptation file needs no change here as long as it follows the convention. To add file-specific
## rules, add a FILE_SCHEMAS entry naming a method of this class and write that method.

## Pattern -> schema. Patterns: "<basename>" for a file directly in data/misostory, "<folder>/<basename>" for a file
## in a subfolder, "<folder>/*" for every file in that folder; the exact pattern wins over the folder wildcard.
## Schema keys: convention (bool, default true), sweep (bool, default true), check (method name, optional),
## required (bool, default false: an error when the file is missing).
const FILE_SCHEMAS := {
	"map_id_crosswalk": {"convention": false, "sweep": false, "check": "_check_crosswalk", "required": true},
	"world_scale": {"check": "_check_world_scale"},
	"drop_rates": {"required": true},
	"meso_rules": {"required": true},
	"recovery": {"check": "_check_recovery", "required": true},
	"new_character": {"check": "_check_new_character"},
	"inventory": {"check": "_check_inventory"},
	"combat": {"check": "_check_combat"},
	"portal_adaptations": {"check": "_check_portal_adaptations"},
	"dialogue/*": {"check": "_check_dialogue"},
	"npcs/*": {"check": "_check_npc_adaptation"},
}

## A file in a canonical-domain folder whose basename starts with this is a shared adaptation table (values the
## folder's entity files share, e.g. misostory/monsters/_shared.json read by MonsterDef), not an entity file.
const SHARED_TABLE_PREFIX := "_"

## The interaction behaviours NpcDef derives (scripts/core/npcs/npc_def.gd) and that npcs/<id>.json may disable.
const NPC_BEHAVIORS := ["quest", "shop", "transport", "talk"]

## Keys that describe a value rather than being one; they never need their own reason/verified.
const META_KEYS := ["id", "kind", "description", "title", "name", "label", "note", "notes", "comment", "comments",
	"reason", "verified", "verification", "verified_by", "verified_against", "source", "sources", "source_url",
	"source_urls", "retrieved_at", "schema", "schema_version", "version", "see", "doc", "docs", "external", "gaps",
	"discrepancies", "match_basis", "reasons", "provenance"]
const META_SUFFIXES := ["_reason", "_note", "_notes", "_verified", "_verified_against", "_source", "_source_url",
	"_description", "_comment", "_doc", "_label"]
## A verified: true value must say what it was verified against: a `verified_against` on the same object (for a
## `<key>_verified: true` sibling flag, `<key>_verified_against` or `verified_against`), a non-empty string or a
## non-empty list of them: a canonical record, a URL, or a decision or brief section (the project owner's natural-regen
## rule is verified against "docs/ITERATION_THREE_BRIEF.md: Natural HP Regeneration"). Anything else is not accepted:
## a value nobody can say was checked is verified: false with its reason.
const VERIFIED_AGAINST := "verified_against"
## WorldScale (scripts/core/world_scale.gd) reads these factors; each must be a positive number.
const WORLD_SCALE_FACTORS := ["horizontal_px_to_m", "vertical_px_to_m", "actor_px_to_m"]
const DEFAULT_WORLD_DIR := "res://assets/world"
## The export's chunk list (<world_dir>/index.json: chunks.<slug>.{kind, map_id}).
const WORLD_INDEX := "index"
const MAX_LISTED_PATHS := 8

var db: ContentDB
var report: ValidationReport
var refs: ReferenceChecks
var provenance: ProvenanceChecks
var options: Dictionary


func _init(content: ContentDB, into: ValidationReport, reference_checks: ReferenceChecks,
		provenance_checks: ProvenanceChecks, opts: Dictionary = {}) -> void:
	db = content
	report = into
	refs = reference_checks
	provenance = provenance_checks
	options = opts


## Runs every adaptation check. Reference findings go through `refs`; the caller flushes it.
func run() -> void:
	var seen := {}
	for folder in _folders():
		var files: Dictionary = db.miso.get(folder, {})
		var keys: Array = files.keys()
		keys.sort()
		for k in keys:
			var key := str(k)
			var pattern := key if folder == "" else "%s/%s" % [folder, key]
			seen[pattern] = true
			_check_file(folder, key, files[k])
	for pattern in FILE_SCHEMAS:
		if FILE_SCHEMAS[pattern].get("required", false) and not seen.has(pattern):
			report.error("adaptation", "misostory", pattern, "required adaptation file game/data/misostory/%s.json is missing" % pattern)


## The schema that applies to a file: exact pattern first, then the folder wildcard, else the defaults.
static func schema_for(folder: String, key: String) -> Dictionary:
	var exact := key if folder == "" else "%s/%s" % [folder, key]
	if FILE_SCHEMAS.has(exact):
		return FILE_SCHEMAS[exact]
	if folder != "" and FILE_SCHEMAS.has(folder + "/*"):
		return FILE_SCHEMAS[folder + "/*"]
	return {}


func _check_file(folder: String, key: String, data: Variant) -> void:
	var label := "misostory" if folder == "" else "misostory/" + folder
	var schema := schema_for(folder, key)
	report.count("adaptation_files_checked")
	if data == null:
		return  # unparsable; ContentDB already recorded it in load_errors
	if schema.get("convention", true):
		check_convention(label, key, data)
	if schema.get("sweep", true):
		refs.sweep(label, key, data)
	if data is Dictionary:
		provenance.check_external(label, key, data.get("external", null))
		provenance.check_provenance_block(label, key, data.get("provenance", null))
	provenance.check_capture_paths(label, key, data)
	if folder != "" and folder in ValidationUtil.canonical_domains(db) and not is_shared_table(key):
		_check_domain_file(folder, label, key, data)
	var method: String = schema.get("check", "")
	if method != "":
		call(method, label, key, data)


## True when `key` (a file key inside a misostory folder) names a shared adaptation table (SHARED_TABLE_PREFIX).
static func is_shared_table(key: String) -> bool:
	return key.get_file().begins_with(SHARED_TABLE_PREFIX)


func _check_domain_file(folder: String, label: String, key: String, data: Variant) -> void:
	var basename := key.get_file()
	if not db.has(folder, basename):
		report.error("adaptation", label, key, "adapts %s '%s', which is not in canonical data (file basename must be a canonical id)" % [folder, basename])
	if not (data is Dictionary):
		return
	# The record id may be spelled "id" or "<singular>_id" (quests/1002.json carries quest_id).
	for id_key in ["id", folder.trim_suffix("s") + "_id"]:
		if data.has(id_key) and not ValidationUtil.same(data[id_key], basename):
			report.error("adaptation", label, key, "%s %s differs from the file basename '%s'" % [id_key, var_to_str(data[id_key]), basename])


# --- the reason/verified convention -------------------------------------------------------------------------

## Checks that every adapted value in `data` is explained (reason) and flagged (verified).
##
## A value is any leaf (number, bool, string, null) under a non-metadata key. It is covered for "reason" when
##   - its object has a sibling "<key>_reason", or "<prefix>_reason" where key starts with "<prefix>_"
##     (world_scale.json: horizontal_reason explains horizontal_px_to_m), or
##   - its object has a "reasons" map with a non-empty string under its key (camera.json, movement.json), or
##   - its object or any enclosing object has a non-empty string "reason".
## A covered key covers everything nested under it. A value is covered for "verified" when its object has a
## sibling "<key>_verified" (or "<prefix>_verified"), or its object or any enclosing object has "verified"; both
## must be bools. So one top-level reason + verified covers a whole file, and per-entry reasons refine it. Arrays
## are transparent.
## A verified: true flag must say what it was checked against (VERIFIED_AGAINST on the same object), else it is an
## error.
func check_convention(label: String, id: String, data: Variant) -> void:
	var missing_reason := {}
	var missing_verified := {}
	_cover(label, id, data, "", false, false, missing_reason, missing_verified)
	if not missing_reason.is_empty():
		report.error("adaptation", label, id, "adapted values without a reason: %s" % _list(missing_reason))
	if not missing_verified.is_empty():
		report.error("adaptation", label, id, "adapted values without a verified flag: %s" % _list(missing_verified))


func _cover(label: String, id: String, node: Variant, path: String, has_reason: bool, has_verified: bool,
		missing_reason: Dictionary, missing_verified: Dictionary) -> void:
	if node is Dictionary:
		var dict: Dictionary = node
		var reason_here := has_reason
		var verified_here := has_verified
		if dict.has("reason"):
			if ValidationUtil.non_empty(dict.reason):
				reason_here = true
			else:
				report.error("adaptation", label, id, "%s must be a non-empty string" % _join(path, "reason"))
		if dict.has("verified"):
			if dict.verified is bool:
				verified_here = true
				if dict.verified:
					_check_verified_against(label, id, _join(path, "verified"), dict.get(VERIFIED_AGAINST, null),
						_join(path, VERIFIED_AGAINST))
			else:
				report.error("adaptation", label, id, "%s must be true or false" % _join(path, "verified"))
		var reasons: Dictionary = {}
		if dict.has("reasons"):
			if dict.reasons is Dictionary:
				reasons = dict.reasons
				for rk in reasons:
					if not ValidationUtil.non_empty(reasons[rk]):
						report.error("adaptation", label, id, "%s must be a non-empty string" % _join(_join(path, "reasons"), str(rk)))
			else:
				report.error("adaptation", label, id, "%s must be a map of value name -> reason" % _join(path, "reasons"))
		for k in dict:
			var key := str(k)
			if key.ends_with("_verified") and not (dict[k] is bool):
				report.error("adaptation", label, id, "%s must be true or false" % _join(path, key))
			elif key.ends_with("_verified") and dict[k]:
				var own := key + "_against"
				_check_verified_against(label, id, _join(path, key), dict.get(own, dict.get(VERIFIED_AGAINST, null)),
					_join(path, own))
			if key.ends_with("_reason") and not ValidationUtil.non_empty(dict[k]):
				report.error("adaptation", label, id, "%s must be a non-empty string" % _join(path, key))
			if is_meta_key(key):
				continue
			var r := reason_here or _has_sibling(dict, key, "_reason") or ValidationUtil.non_empty(reasons.get(key, null))
			var v := verified_here or _has_sibling(dict, key, "_verified")
			_cover(label, id, dict[k], _join(path, key), r, v, missing_reason, missing_verified)
	elif node is Array:
		for e in node:
			_cover(label, id, e, path + "[]", has_reason, has_verified, missing_reason, missing_verified)
	else:
		var shown := path if path != "" else "(file value)"
		if not has_reason:
			missing_reason[shown] = true
		if not has_verified:
			missing_verified[shown] = true


## True for keys that describe a value instead of being one (META_KEYS, META_SUFFIXES, or a leading "_").
static func is_meta_key(key: String) -> bool:
	if key in META_KEYS or key.begins_with("_"):
		return true
	for suffix in META_SUFFIXES:
		if key.ends_with(suffix):
			return true
	return false


## "<key><suffix>" exists on dict, or "<prefix><suffix>" where key starts with "<prefix>_".
static func _has_sibling(dict: Dictionary, key: String, suffix: String) -> bool:
	if dict.has(key + suffix):
		return true
	for k in dict:
		var other := str(k)
		if other.ends_with(suffix):
			var prefix := other.trim_suffix(suffix)
			if prefix != "" and key.begins_with(prefix + "_"):
				return true
	return false


## A true verified flag at `flag_path` needs `against` (read from `against_path`): a non-empty string or a non-empty
## list of non-empty strings (VERIFIED_AGAINST).
func _check_verified_against(label: String, id: String, flag_path: String, against: Variant, against_path: String) -> void:
	if against == null:
		report.error("adaptation", label, id,
			"%s is true but has no %s saying what it was verified against (a canonical record, a URL, or a decision or brief section); a value nobody can say was checked is verified: false with its reason" % [
				flag_path, against_path])
		return
	var ok := ValidationUtil.non_empty(against)
	if against is Array:
		ok = not against.is_empty()
		for v in against:
			ok = ok and ValidationUtil.non_empty(v)
	if not ok:
		report.error("adaptation", label, id, "%s must be a non-empty string or a non-empty list of them, got %s" % [
			against_path, var_to_str(against)])


static func _join(path: String, key: String) -> String:
	return key if path == "" else "%s.%s" % [path, key]


static func _list(paths: Dictionary) -> String:
	var keys: Array = paths.keys()
	keys.sort()
	var shown: PackedStringArray = []
	for i in mini(keys.size(), MAX_LISTED_PATHS):
		shown.append(str(keys[i]))
	var text := ", ".join(shown)
	if keys.size() > MAX_LISTED_PATHS:
		text += " and %d more" % (keys.size() - MAX_LISTED_PATHS)
	return text


# --- file-specific checks (FILE_SCHEMAS[...].check) ---------------------------------------------------------

## world_scale.json: the factors WorldScale reads exist and are positive numbers.
func _check_world_scale(label: String, id: String, data: Variant) -> void:
	if not (data is Dictionary):
		report.error("adaptation", label, id, "must be an object")
		return
	for factor in WORLD_SCALE_FACTORS:
		var v: Variant = data.get(factor, null)
		if not ValidationUtil.is_number(v) or float(v) <= 0.0:
			report.error("adaptation", label, id, "%s must be a positive number (WorldScale reads it), got %s" % [factor, var_to_str(v)])


## map_id_crosswalk.json: bijective onto the canonical maps, one Blender slug per map, and (when the Blender export
## is present) a gameplay sidecar game/assets/world/<slug>.json whose map_id is the row's gms_v8_id.
## Accepts both spellings in use: meowdb_id/iteration_one_slug (the file) and map_id/blender_slug (MAP_ARCHITECTURE).
func _check_crosswalk(_label: String, _id: String, data: Variant) -> void:
	var rows: Variant = data
	if data is Dictionary and data.get("rows", null) is Array:
		rows = data.rows
	if not (rows is Array):
		report.error("crosswalk", "crosswalk", "map_id_crosswalk", "must be an array of rows {meowdb_id, gms_v8_id, iteration_one_slug, match_basis}")
		return
	var by_map := {}
	var by_slug := {}
	var by_gms := {}
	var slugs := {}  # slug -> gms id (Variant)
	var i := 0
	for row in rows:
		var where := "row %d" % i
		i += 1
		if not (row is Dictionary):
			report.error("crosswalk", "crosswalk", where, "is not an object")
			continue
		var map_id: Variant = row.get("meowdb_id", row.get("map_id", null))
		var slug: Variant = row.get("iteration_one_slug", row.get("blender_slug", null))
		var gms: Variant = row.get("gms_v8_id", null)
		var id := str(map_id) if map_id != null else where
		if not ValidationUtil.non_empty(map_id):
			report.error("crosswalk", "crosswalk", where, "has no meowdb_id string")
		else:
			report.count("references_checked")
			if not db.has("maps", map_id):
				report.error("crosswalk", "crosswalk", id, "maps MeowDB id %s, which is not a canonical map" % map_id)
			if by_map.has(map_id):
				report.error("crosswalk", "crosswalk", id, "MeowDB id %s appears in more than one row (not bijective)" % map_id)
			by_map[map_id] = true
		if not ValidationUtil.non_empty(slug):
			report.error("crosswalk", "crosswalk", id, "has no Blender slug (iteration_one_slug)")
		else:
			if by_slug.has(slug):
				report.error("crosswalk", "crosswalk", id, "Blender slug %s appears in more than one row (not bijective)" % slug)
			by_slug[slug] = true
			slugs[slug] = gms
		if gms == null:
			report.warning("crosswalk", "crosswalk", id, "has no gms_v8_id (needed to match the Blender sidecar's map_id)")
		elif not ValidationUtil.is_number(gms):
			report.error("crosswalk", "crosswalk", id, "gms_v8_id must be a number, got %s" % var_to_str(gms))
		else:
			if by_gms.has(int(gms)):
				report.error("crosswalk", "crosswalk", id, "gms_v8_id %d appears in more than one row (not bijective)" % int(gms))
			by_gms[int(gms)] = true
		if not ValidationUtil.non_empty(row.get("match_basis", row.get("reason", null))):
			report.error("crosswalk", "crosswalk", id, "has no match_basis (the evidence that joined the two ids)")
	for map_id in db.ids("maps"):
		if not by_map.has(map_id):
			report.error("crosswalk", "crosswalk", map_id, "canonical map %s has no crosswalk row" % map_id)
	var map_count := db.ids("maps").size()
	if rows.size() != map_count:
		report.error("crosswalk", "crosswalk", "map_id_crosswalk", "has %d rows but there are %d canonical maps" % [rows.size(), map_count])
	_check_sidecars(slugs)


func _check_sidecars(slugs: Dictionary) -> void:
	var injected: Variant = options.get("world_sidecars", null)
	var world_dir: String = options.get("world_dir", DEFAULT_WORLD_DIR)
	if injected == null and DirAccess.open(world_dir) == null:
		report.warning("crosswalk", "crosswalk", "world_assets",
			"no Blender export at %s, so the crosswalk's Blender slugs were not checked (run scripts/export_runtime.py, or INCLUDE_WORLD=1 for isolated runs)" % world_dir)
		return
	var keys: Array = slugs.keys()
	keys.sort()
	for slug in keys:
		report.count("sidecars_checked")
		var sidecar: Variant = _sidecar(injected, world_dir, slug)
		if sidecar == null:
			report.error("crosswalk", "crosswalk", str(slug), "Blender slug %s has no gameplay sidecar %s/%s.json" % [slug, world_dir, slug])
			continue
		if not (sidecar is Dictionary):
			report.error("crosswalk", "crosswalk", str(slug), "sidecar %s.json is not a JSON object" % slug)
			continue
		var sidecar_map: Variant = sidecar.get("map_id", null)
		var gms: Variant = slugs[slug]
		if not ValidationUtil.is_number(sidecar_map):
			report.error("crosswalk", "crosswalk", str(slug), "sidecar %s.json has no numeric map_id (got %s), so it cannot be matched to its crosswalk row" % [
				slug, var_to_str(sidecar_map)])
		elif ValidationUtil.is_number(gms) and int(sidecar_map) != int(gms):
			report.error("crosswalk", "crosswalk", str(slug), "sidecar %s.json has map_id %d but the crosswalk row says gms_v8_id %d" % [
				slug, int(sidecar_map), int(gms)])
	_check_unlisted_chunks(injected, world_dir, slugs)


## The export's chunk list against the crosswalk, read from <world_dir>/index.json (or the injected sidecars):
## - a crosswalk slug with a sidecar but no chunk in index.json is a half-written export (error; disk only);
## - a map chunk (an entry with a map_id: kind map or interior) that no crosswalk row names has no canonical map, so
##   the runtime cannot place it (warning: the export is environment data, not canonical data).
## Skipped when the export has no index.json.
func _check_unlisted_chunks(injected: Variant, world_dir: String, slugs: Dictionary) -> void:
	var chunks := {}  # slug -> map_id
	var source: Variant = injected
	if not (injected is Dictionary):
		var index: Variant = _sidecar(null, world_dir, WORLD_INDEX)
		source = index.get("chunks", null) if index is Dictionary else null
		if source is Dictionary:
			var listed: Array = slugs.keys()
			listed.sort()
			for slug in listed:
				if not source.has(slug):
					report.error("crosswalk", "crosswalk", str(slug), "Blender slug %s has no chunk in %s/%s.json (re-run scripts/export_runtime.py)" % [
						slug, world_dir, WORLD_INDEX])
	if not (source is Dictionary):
		return
	for slug in source:
		var entry: Variant = source[slug]
		if entry is Dictionary and ValidationUtil.is_number(entry.get("map_id", null)):
			chunks[str(slug)] = int(entry.map_id)
	var keys: Array = chunks.keys()
	keys.sort()
	for slug in keys:
		if not slugs.has(slug):
			report.warning("crosswalk", "crosswalk", str(slug), "the Blender export has map chunk %s (map_id %d) but no crosswalk row names it" % [
				slug, int(chunks[slug])])


## The sidecar for a slug: from the injected test table, else parsed from disk; null when absent.
static func _sidecar(injected: Variant, world_dir: String, slug: String) -> Variant:
	if injected is Dictionary:
		return injected.get(slug, null)
	var path := world_dir.path_join(slug + ".json")
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed != null else "unparsable"


## recovery.json (contracts C4, C5): what NaturalRecoveryRule and Chairs read is there and of the kind they need
## (natural_hp: hp_per_tick a whole number >= 0, tick_s > 0, eligible_activities a non-empty list of
## PlayerController.activity() values; chair_bonus: two true/false switches; sitting.sit_key_chair a rule Chairs
## implements), and natural_mp supplies no number while it is the unresolved source gap it says it is: MeowDB documents
## no natural MP recovery, so an MP rate there would be an invented value.
func _check_recovery(label: String, id: String, data: Variant) -> void:
	if not (data is Dictionary):
		report.error("adaptation", label, id, "must be an object")
		return
	var hp: Variant = (data as Dictionary).get("natural_hp", null)
	if not (hp is Dictionary):
		report.error("adaptation", label, id, "natural_hp must be an object (NaturalRecoveryRule reads it)")
	else:
		var per: Variant = hp.get("hp_per_tick", null)
		if not ValidationUtil.is_number(per) or float(per) < 0.0 or float(per) != floorf(float(per)):
			report.error("adaptation", label, id, "natural_hp.hp_per_tick must be a whole number >= 0, got %s" % var_to_str(per))
		var tick: Variant = hp.get("tick_s", null)
		if not ValidationUtil.is_number(tick) or float(tick) <= 0.0:
			report.error("adaptation", label, id, "natural_hp.tick_s must be a positive number, got %s" % var_to_str(tick))
		var acts: Variant = hp.get("eligible_activities", null)
		if not (acts is Array) or (acts as Array).is_empty():
			report.error("adaptation", label, id, "natural_hp.eligible_activities must be a non-empty list")
		else:
			for a in acts:
				if not (str(a) in NaturalRecoveryRule.ACTIVITIES):
					report.error("adaptation", label, id, "natural_hp.eligible_activities: '%s' is not a player activity (%s)" % [
						str(a), ", ".join(NaturalRecoveryRule.ACTIVITIES)])
	var mp: Variant = (data as Dictionary).get("natural_mp", null)
	if mp is Dictionary and str(mp.get("status", "")) == "unresolved_source_gap":
		for k in mp:
			if ValidationUtil.is_number(mp[k]) and not (mp[k] is bool):
				report.error("adaptation", label, id, "natural_mp.%s: an unresolved source gap supplies no number, got %s" % [
					str(k), var_to_str(mp[k])])
	var chair: Variant = (data as Dictionary).get("chair_bonus", null)
	if not (chair is Dictionary):
		report.error("adaptation", label, id, "chair_bonus must be an object (NaturalRecoveryRule reads it)")
	else:
		for k in ["stand_resets_clock", "full_hp_holds_clock"]:
			if not (chair.get(k, null) is bool):
				report.error("adaptation", label, id, "chair_bonus.%s must be true or false" % k)
	var sitting: Variant = (data as Dictionary).get("sitting", null)
	var rule := str(sitting.get("sit_key_chair", "")) if sitting is Dictionary else ""
	if sitting is Dictionary and sitting.has("sit_key_chair") and not (rule in NaturalRecoveryRule.SIT_KEY_RULES):
		report.error("adaptation", label, id, "sitting.sit_key_chair '%s' is not a rule Chairs implements (%s)" % [
			str(sitting.get("sit_key_chair", "")), ", ".join(NaturalRecoveryRule.SIT_KEY_RULES)])


## portal_adaptations.json: every portal it names ("<map_id>.<portal>", link ids "T_<map>_<portal>__<map>[_<portal>]",
## arrival gates, the one-way allowlist) exists in canonical data, spawn indexes are in range, and each allowlisted
## one-way link really is one-way (else the entry is stale).
func _check_portal_adaptations(label: String, id: String, data: Variant) -> void:
	if not (data is Dictionary):
		report.error("adaptation", label, id, "must be an object")
		return
	var link_modes: Variant = data.get("link_modes", {})
	if link_modes is Dictionary and link_modes.get("overrides", null) is Dictionary:
		for link_id in link_modes.overrides:
			_check_link_id(label, id, "link_modes.overrides", str(link_id))
	var dest_overrides: Variant = data.get("destination_overrides", {})
	if dest_overrides is Dictionary and dest_overrides.get("overrides", null) is Dictionary:
		for portal_ref in dest_overrides.overrides:
			var where := "destination_overrides.overrides.%s" % str(portal_ref)
			var portal := _portal_by_ref(label, id, where, str(portal_ref))
			var o: Variant = dest_overrides.overrides[portal_ref]
			if portal.is_empty() or not (o is Dictionary):
				continue
			var dest: Variant = portal.get("to_map_id", null)
			if not (dest is String) or not db.has("maps", dest):
				continue
			if o.get("destination_portal_id", null) is String:
				if ReferenceChecks.find_portal(db.map(dest), o.destination_portal_id).is_empty():
					report.error("adaptation", label, id, "%s.destination_portal_id '%s' is not a portal of %s" % [where, o.destination_portal_id, dest])
			if o.has("destination_spawn_index"):
				_check_spawn_index(label, id, where + ".destination_spawn_index", dest, o.destination_spawn_index)
	var gates: Variant = data.get("arrival_gates", {})
	if gates is Dictionary:
		var i := 0
		for g in ValidationUtil.as_array(gates.get("gates", [])):
			var where := "arrival_gates.gates[%d]" % i
			i += 1
			if not (g is Dictionary):
				continue
			var map_id: Variant = g.get("map_id", null)
			if g.get("source_portal", null) is String:
				var source := _portal_by_ref(label, id, where + ".source_portal", g.source_portal)
				if not source.is_empty() and map_id is String and not ValidationUtil.same(source.get("to_map_id", null), map_id):
					report.error("adaptation", label, id, "%s: source_portal %s leads to %s, not to the gate's map %s" % [
						where, g.source_portal, str(source.get("to_map_id", null)), map_id])
			if map_id is String and db.has("maps", map_id) and g.has("spawn_index"):
				_check_spawn_index(label, id, where + ".spawn_index", map_id, g.spawn_index)
	var allow: Variant = data.get("one_way_allowlist", {})
	if allow is Dictionary:
		for link in ValidationUtil.as_array(allow.get("links", [])):
			if not (link is Dictionary):
				continue
			var from: Variant = link.get("from", null)
			var to: Variant = link.get("to", null)
			var ok := true
			for m in [from, to]:
				if not (m is String) or not _require_key_ref(label, id, "one_way_allowlist.links", "maps", str(m)):
					ok = false
			if not ok:
				continue
			if not _has_portal_to(from, to):
				report.error("adaptation", label, id, "one_way_allowlist allows %s -> %s, but %s has no portal to %s" % [from, to, from, to])
			elif _has_portal_to(to, from):
				report.warning("adaptation", label, id, "one_way_allowlist lists %s -> %s, but %s has a portal back; the entry is stale" % [from, to, to])


## "T_<mapA>_<portalA>__<mapB>[_<portalB>]": both maps exist and each named portal exists on its map.
func _check_link_id(label: String, id: String, where: String, link_id: String) -> void:
	var sides := link_id.trim_prefix("T_").split("__")
	if not link_id.begins_with("T_") or sides.size() != 2:
		report.error("adaptation", label, id, "%s key '%s' is not a link id T_<map>_<portal>__<map>[_<portal>]" % [where, link_id])
		return
	for side in sides:
		var map_id := side.get_slice("_", 0)
		var portal_name := side.substr(map_id.length() + 1) if side.length() > map_id.length() else ""
		if not _require_key_ref(label, id, where, "maps", map_id):
			continue
		if portal_name != "" and ReferenceChecks.find_portal(db.map(map_id), portal_name).is_empty():
			report.error("adaptation", label, id, "%s key '%s': %s has no portal '%s'" % [where, link_id, map_id, portal_name])


## "<map_id>.<portal>" -> the canonical portal Dictionary, or {} after reporting what is missing.
func _portal_by_ref(label: String, id: String, where: String, portal_ref: String) -> Dictionary:
	var map_id := portal_ref.get_slice(".", 0)
	var portal_name := portal_ref.get_slice(".", 1) if portal_ref.contains(".") else ""
	if portal_name == "":
		report.error("adaptation", label, id, "%s '%s' must be \"<map_id>.<portal>\"" % [where, portal_ref])
		return {}
	if not _require_key_ref(label, id, where, "maps", map_id):
		return {}
	var portal := ReferenceChecks.find_portal(db.map(map_id), portal_name)
	if portal.is_empty():
		report.error("adaptation", label, id, "%s: map %s has no portal '%s'" % [where, map_id, portal_name])
	return portal


func _has_portal_to(from_map: String, to_map: String) -> bool:
	for p in ValidationUtil.as_array(db.map(from_map).get("portals", [])):
		if p is Dictionary and ValidationUtil.same(p.get("to_map_id", null), to_map):
			return true
	return false


func _check_spawn_index(label: String, id: String, where: String, map_id: String, index: Variant) -> void:
	var spawn_count := ValidationUtil.as_array(db.map(map_id).get("player_spawns", [])).size()
	if not ValidationUtil.is_number(index) or int(index) < 0 or int(index) >= spawn_count:
		report.error("adaptation", label, id, "%s %s is not one of map %s's %d player spawns" % [where, var_to_str(index), map_id, spawn_count])


## dialogue/<npc id>.json (or dialogue/_<name>.json, SHARED_TABLE_PREFIX, for shared system lines): the file belongs to
## a canonical NPC, and every canonical line it reuses exists: {"npc", "field", "line"} indexes that NPC's line list
## (0-based, as DialogueText reads it) and {"quest", ...} names a canonical quest.
func _check_dialogue(label: String, id: String, data: Variant) -> void:
	if not is_shared_table(id):
		if not db.has("npcs", id):
			report.error("adaptation", label, id, "dialogue file for NPC '%s', which is not in canonical data (name it <npc id>.json, or _<name>.json for shared lines)" % id)
		elif data is Dictionary and data.has("npc_id") and not ValidationUtil.same(data.npc_id, id):
			report.error("adaptation", label, id, "npc_id %s differs from the file basename '%s'" % [var_to_str(data.npc_id), id])
	_check_line_specs(label, id, data, "")


func _check_line_specs(label: String, id: String, node: Variant, path: String) -> void:
	if node is Dictionary:
		if node.get("npc", null) is String and node.has("line"):
			_check_npc_line(label, id, path, node)
		if node.get("quest", null) is String:
			report.count("references_checked")
			if not db.has("quests", node.quest):
				report.error("reference", label, id, "%s reuses a line of quest '%s', which does not exist" % [path, node.quest])
		for k in node:
			_check_line_specs(label, id, node[k], _join(path, str(k)))
	elif node is Array:
		for e in node:
			_check_line_specs(label, id, e, path + "[]")


func _check_npc_line(label: String, id: String, path: String, spec: Dictionary) -> void:
	report.count("references_checked")
	var npc_id: String = spec.npc
	if not db.has("npcs", npc_id):
		report.error("reference", label, id, "%s reuses a line of NPC '%s', which does not exist" % [path, npc_id])
		return
	var field: Variant = spec.get("field", "dialogue")
	var lines: Variant = db.npc(npc_id).get(str(field), null)
	var index: Variant = spec.line
	if not (lines is Array):
		report.error("adaptation", label, id, "%s: NPC %s has no line list '%s'" % [path, npc_id, str(field)])
	elif not ValidationUtil.is_number(index) or int(index) < 0 or int(index) >= lines.size():
		report.error("adaptation", label, id, "%s: NPC %s %s has %d lines, so line %s does not exist (0-based)" % [
			path, npc_id, str(field), lines.size(), var_to_str(index)])


## npcs/<npc id>.json: every disabled_behaviors entry is a behaviour NpcDef knows (a typo would be ignored and leave
## the behaviour on, e.g. Shanks' out-of-scope boat), and one the NPC actually has (else the entry is stale: warning).
func _check_npc_adaptation(label: String, id: String, data: Variant) -> void:
	if not (data is Dictionary) or not data.has("disabled_behaviors"):
		return
	var list: Variant = data.disabled_behaviors
	if not (list is Array):
		report.error("adaptation", label, id, "disabled_behaviors must be an array of behaviour names (%s)" % ", ".join(PackedStringArray(NPC_BEHAVIORS)))
		return
	var npc: Dictionary = db.npc(id.get_file())
	for b in list:
		if not (b is String) or not (b in NPC_BEHAVIORS):
			report.error("adaptation", label, id, "disabled_behaviors entry %s is not an NPC behaviour (%s)" % [
				var_to_str(b), ", ".join(PackedStringArray(NPC_BEHAVIORS))])
		elif not npc.is_empty() and not _npc_has_behavior(npc, b):
			report.warning("adaptation", label, id, "disables '%s', which NPC %s does not have; the entry is stale" % [b, id])


## Whether the canonical NPC record gives it this behaviour, by the rules NpcDef uses.
static func _npc_has_behavior(npc: Dictionary, behavior: String) -> bool:
	match behavior:
		"quest":
			var q: Variant = npc.get("quests", null)
			return q is Dictionary and (not ValidationUtil.as_array(q.get("started_here", [])).is_empty() \
				or not ValidationUtil.as_array(q.get("completed_here", [])).is_empty())
		"shop":
			var s: Variant = npc.get("shop", null)
			return s is Dictionary and ValidationUtil.non_empty(s.get("shop_id", null))
		"transport":
			var t: Variant = npc.get("transport", null)
			return t is Dictionary and not ValidationUtil.as_array(t.get("routes", [])).is_empty()
	return true  # "talk": every NPC talks


## new_character.json: the start map is a canonical map (typed sweep) and spawn_index picks one of its player spawns.
func _check_new_character(label: String, id: String, data: Variant) -> void:
	var start: Variant = data.get("start_location", null) if data is Dictionary else null
	if not (start is Dictionary):
		report.error("adaptation", label, id, "start_location {map_id, spawn_index} is missing")
		return
	var map_id: Variant = start.get("map_id", null)
	if not (map_id is String) or not db.has("maps", map_id):
		return  # the typed sweep reports a missing or unknown map
	_check_spawn_index(label, id, "start_location.spawn_index", map_id, start.get("spawn_index", 0))


## inventory.json: every canonical weapon's subtype has a weapon_subtypes entry, or the damage formula cannot be
## chosen for it.
func _check_inventory(label: String, id: String, data: Variant) -> void:
	var subtypes: Variant = data.get("weapon_subtypes", null) if data is Dictionary else null
	if not (subtypes is Dictionary):
		report.error("adaptation", label, id, "weapon_subtypes is missing")
		return
	for item_id in db.ids("items"):
		var it: Dictionary = db.item(item_id)
		if it.get("weapon", null) is Dictionary and not subtypes.has(str(it.get("subtype", ""))):
			report.error("adaptation", label, id, "weapon_subtypes has no entry for '%s' (canonical weapon item %s)" % [str(it.get("subtype", "")), item_id])
	# shop.protected_items (ItemsConfig.protected_item): every entry names a canonical item. A dangling id would
	# protect nothing and hide the mistake.
	var shop: Variant = data.get("shop", null)
	var protected: Variant = (shop as Dictionary).get("protected_items", null) if shop is Dictionary else null
	if protected == null:
		return
	if not (protected is Array):
		report.error("adaptation", label, id, "shop.protected_items must be a list of {item_id, reason, verified}")
		return
	for e: Variant in protected:
		var pid: Variant = (e as Dictionary).get("item_id", null) if e is Dictionary else null
		if not (pid is String) or not db.has("items", pid):
			report.error("adaptation", label, id, "shop.protected_items names item %s, which is not a canonical item" % var_to_str(pid))


## combat.json: fixed_damage_skills is keyed by canonical skill ids (formulas skills[].skill_id).
func _check_combat(label: String, id: String, data: Variant) -> void:
	var skills: Variant = data.get("fixed_damage_skills", null) if data is Dictionary else null
	if not (skills is Dictionary):
		return
	var known := ReferenceChecks.skill_definitions(db)
	for skill_id in skills:
		if not known.has(str(skill_id)):
			report.error("adaptation", label, id, "fixed_damage_skills.%s is not a canonical skill id (formulas skills[].skill_id)" % str(skill_id))


# --- helpers ------------------------------------------------------------------------------------------------

## Reports an error when `ref` (used as a map key under `where`) is not a record of `target`; returns true if it is.
func _require_key_ref(label: String, id: String, where: String, target: String, ref: String) -> bool:
	report.count("references_checked")
	if db.has(target, ref):
		return true
	report.error("reference", label, id, "%s key '%s' is not a canonical %s id" % [where, ref, target])
	return false


func _folders() -> PackedStringArray:
	var out: PackedStringArray = []
	for f in db.miso:
		out.append(str(f))
	out.sort()
	return out
