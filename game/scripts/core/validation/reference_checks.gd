class_name ReferenceChecks
extends RefCounted
## Cross-record reference checks: every id a record points at must exist in the dataset.
##
## Two mechanisms, so new data is covered without new code:
##   1. A typed-key sweep walks every record and resolves any key named in TYPED_KEYS (item_id -> items,
##      to_map_id -> maps, npc_id -> npcs, ...). Values are a string id, an array of string ids, null (no ref), or
##      an object whose "value" is one of those (adaptation files wrap a value with its reason that way).
##   2. EXPLICIT_RULES cover keys that are ambiguous ("id" inside maps.npcs[] is an NPC id) or that may leave the
##      dataset on purpose (a Victoria Island quest listed on a Maple Island map). An explicit rule for a path wins
##      over the sweep at that path.
## Dialogue link objects ({"kind"|"type": "npc", "id": "2"}) are checked too, as warnings: a dangling link only
## loses its hyperlink, it does not break play.
## Then come the structural checks the sweep cannot express: portals (destination map and destination portal),
## drop tables (owner and file reference) and a few two-sided consistency checks (warnings).

## key -> canonical domain it references. Applies at any depth in canonical and misostory records.
const TYPED_KEYS := {
	"item_id": "items", "item_ids": "items", "item_cost_id": "items", "required_ammunition_item_id": "items",
	"weapon_id": "items",
	"mob_id": "monsters", "mob_ids": "monsters", "monster_id": "monsters", "monster_ids": "monsters",
	"npc_id": "npcs", "npc_ids": "npcs", "start_npc_id": "npcs", "complete_npc_id": "npcs", "end_npc_id": "npcs",
	"map_id": "maps", "map_ids": "maps", "to_map_id": "maps", "from_map_id": "maps", "return_map_id": "maps",
	"sold_at_map_id": "maps", "start_map_id": "maps", "respawn_map_id": "maps",
	"quest_id": "quests", "quest_ids": "quests",
	"shop_id": "shops", "shop_ids": "shops",
	"breakable_id": "breakables", "breakable_ids": "breakables",
}

## A typed key whose value is an object {"value": <id>, "reason": ..., "verified": ...} (the adaptation files' way of
## attaching a reason to one value) resolves <id>.
const VALUE_KEY := "value"

## Subtrees never swept, at any depth: provenance and commentary, which cite pages and ids outside the dataset.
const EXCLUDED_KEYS := ["source", "field_sources", "cross_checks", "discrepancies", "notes", "gaps",
	"change_history", "external"]

## Per-domain subtrees never swept (path from the record root). Items list every place in the whole game an item
## comes from or goes to (Victoria Island shops, monsters and quests), which is reference material, not a link
## the game follows.
const EXCLUDED_PATHS := {
	"items": ["sources", "used_in"],
	"maps": ["portals[].to_map_id"],  # resolved by _check_portals, which names the broken exit
}

## scope values: "" = must resolve; "quest_region" = out of scope when the owning entry's area_label/region is
## not a region of the shipped quests; "maple_island_flag" = out of scope when the owning entry says
## maple_island: false; "may_leave_dataset" = a destination outside the dataset is expected (NPC transport).
const EXPLICIT_RULES := [
	{"domain": "maps", "path": "npcs[].id", "target": "npcs", "scope": ""},
	{"domain": "maps", "path": "monsters[].id", "target": "monsters", "scope": ""},
	{"domain": "maps", "path": "meowdb_spawn_estimates.per_mob[].id", "target": "monsters", "scope": ""},
	{"domain": "maps", "path": "reactors[].id", "target": "breakables", "scope": ""},
	{"domain": "maps", "path": "quests.starts_here[].id", "target": "quests", "scope": ""},  # its NPC stands here
	{"domain": "maps", "path": "quests.progress_here[].id", "target": "quests", "scope": "quest_region"},
	{"domain": "npcs", "path": "quests.given[].id", "target": "quests", "scope": ""},
	{"domain": "npcs", "path": "quests.turned_in[].id", "target": "quests", "scope": ""},
	{"domain": "npcs", "path": "quests.started_here[]", "target": "quests", "scope": ""},
	{"domain": "npcs", "path": "quests.completed_here[]", "target": "quests", "scope": ""},
	{"domain": "npcs", "path": "transport.routes[].to_map_id", "target": "maps", "scope": "may_leave_dataset"},
	{"domain": "monsters", "path": "spawns[].map_id", "target": "maps", "scope": "maple_island_flag"},
	{"domain": "monsters", "path": "quests[].quest_id", "target": "quests", "scope": "quest_region"},
	{"domain": "formulas", "path": "map_page_display.example_map.monsters[].id", "target": "monsters", "scope": ""},
]

## Dialogue link kinds -> canonical domain.
const LINK_KINDS := {"npc": "npcs", "map": "maps", "item": "items", "monster": "monsters", "quest": "quests",
	"shop": "shops"}

## Owner kinds a drop table may belong to -> canonical domain.
const DROP_OWNER_KINDS := {"monster": "monsters", "breakable": "breakables"}

## The to_portal_derivation values tools/meowdb/extract_maps.mjs writes (docs/canonical/maps.md).
const PORTAL_DERIVATIONS := ["reverse_lookup", "none"]
const REDERIVE_HINT := "rerun node tools/meowdb/extract_maps.mjs"

var db: ContentDB
var report: ValidationReport
var _rules: Dictionary = {}  # "domain|path" -> rule
var _quest_regions: Dictionary = {}  # region label -> true
var _pending: Dictionary = {}  # dedup key -> {severity, domain, id, message, check, count}
var _pending_order: Array[String] = []
var _skipped: Dictionary = {}  # dedup of out-of-scope lines


func _init(content: ContentDB, into: ValidationReport) -> void:
	db = content
	report = into
	for rule in EXPLICIT_RULES:
		_rules["%s|%s" % [rule.domain, rule.path]] = rule
	_quest_regions = _collect_quest_regions()


## Runs every reference check over the canonical data.
func run() -> void:
	for domain_name in ValidationUtil.canonical_domains(db):
		var excluded: Array = EXCLUDED_PATHS.get(domain_name, [])
		for id in db.ids(domain_name):
			sweep(domain_name, id, db.get_entity(domain_name, id), excluded, true)
	_check_portals()
	_check_portal_graph()
	_check_drop_tables()
	_check_consistency()
	flush()


## Walks one record (canonical or adaptation) and resolves every typed key, explicit rule and dialogue link.
## `domain_label` and `id` name the record in findings; `excluded` lists extra root-relative paths to skip;
## `use_rules` applies EXPLICIT_RULES for `domain_label` (canonical domains only).
func sweep(domain_label: String, id: String, record: Variant, excluded: Array = [], use_rules: bool = false) -> void:
	var ctx := {"domain": domain_label, "id": id, "excluded": excluded, "use_rules": use_rules}
	_visit(ctx, record, "", {})


## Emits the collected (deduplicated) reference findings into the report. Call after the last sweep().
func flush() -> void:
	for key in _pending_order:
		var p: Dictionary = _pending[key]
		var msg: String = p.message
		if int(p.count) > 1:
			msg += " (%d occurrences)" % int(p.count)
		report.add(p.severity, p.check, p.domain, p.id, msg)
	_pending.clear()
	_pending_order.clear()


# --- the sweep ----------------------------------------------------------------------------------------------

func _visit(ctx: Dictionary, node: Variant, path: String, owner: Dictionary) -> void:
	if node is Dictionary:
		var dict: Dictionary = node
		for k in dict:
			var key := str(k)
			if key in EXCLUDED_KEYS:
				continue
			var child_path := key if path == "" else "%s.%s" % [path, key]
			if child_path in ctx.excluded:
				continue
			var value: Variant = dict[k]
			var rule: Dictionary = _rule_for(ctx, child_path)
			if not rule.is_empty():
				_apply_rule(ctx, rule, value, child_path, dict)
			elif TYPED_KEYS.has(key) and not (value is Dictionary):
				_resolve_value(ctx, TYPED_KEYS[key], value, child_path, dict, "")
			elif TYPED_KEYS.has(key) and value.has(VALUE_KEY):
				# Adaptation house style wraps a value with its reason: "start_map_id": {"value": "...", "reason": ...}.
				_resolve_value(ctx, TYPED_KEYS[key], value[VALUE_KEY], "%s.%s" % [child_path, VALUE_KEY], dict, "")
				_visit(ctx, value, child_path, dict)
			elif key == "ref" and value is Dictionary:
				_check_link(ctx, value, child_path)
			else:
				_visit(ctx, value, child_path, dict)
	elif node is Array:
		var elem_path := path + "[]"
		var rule: Dictionary = _rule_for(ctx, elem_path)
		for e in node:
			if not rule.is_empty() and not (e is Dictionary or e is Array):
				_resolve_one(ctx, rule.target, e, elem_path, owner, rule.scope)
			else:
				_visit(ctx, e, elem_path, owner)


func _rule_for(ctx: Dictionary, path: String) -> Dictionary:
	if not ctx.use_rules:
		return {}
	return _rules.get("%s|%s" % [ctx.domain, path], {})


func _apply_rule(ctx: Dictionary, rule: Dictionary, value: Variant, path: String, owner: Dictionary) -> void:
	if value is Dictionary:
		_visit(ctx, value, path, owner)
	else:
		_resolve_value(ctx, rule.target, value, path, owner, rule.scope)


func _resolve_value(ctx: Dictionary, target: String, value: Variant, path: String, owner: Dictionary, scope: String) -> void:
	if value is Array:
		for e in value:
			_resolve_one(ctx, target, e, path + "[]", owner, scope)
	else:
		_resolve_one(ctx, target, value, path, owner, scope)


func _resolve_one(ctx: Dictionary, target: String, value: Variant, path: String, owner: Dictionary, scope: String) -> void:
	if value == null:
		return  # an optional reference that is not set
	report.count("references_checked")
	if not (value is String):
		_note(ValidationReport.ERROR, "reference", ctx.domain, ctx.id,
			"%s must be a string id (ids are strings exactly as MeowDB writes them), got %s" % [path, var_to_str(value)])
		return
	var ref: String = value
	if db.has(target, ref):
		return
	if _out_of_scope(scope, owner):
		_skip("%s/%s: %s -> %s/%s (%s)" % [ctx.domain, ctx.id, path, target, ref, _scope_reason(scope, owner)])
		return
	_note(ValidationReport.ERROR, "reference", ctx.domain, ctx.id,
		"%s references %s '%s', which does not exist" % [path, target, ref])


func _check_link(ctx: Dictionary, link: Dictionary, path: String) -> void:
	var kind: Variant = link.get("kind", link.get("type", null))
	var ref: Variant = link.get("id", null)
	report.count("references_checked")
	if not (kind is String) or not LINK_KINDS.has(kind):
		_note(ValidationReport.WARNING, "dialogue_link", ctx.domain, ctx.id,
			"%s has an unknown link kind %s" % [path, var_to_str(kind)])
		return
	var target: String = LINK_KINDS[kind]
	if not (ref is String):
		_note(ValidationReport.WARNING, "dialogue_link", ctx.domain, ctx.id, "%s link has no string id" % path)
		return
	if not db.has(target, ref):
		_note(ValidationReport.WARNING, "dialogue_link", ctx.domain, ctx.id,
			"dialogue links to %s '%s', which is not in the dataset (the text renders without the link); first at %s" % [
				target, ref, path], "link|%s|%s" % [target, ref])


func _out_of_scope(scope: String, owner: Dictionary) -> bool:
	match scope:
		"may_leave_dataset":
			return true
		"maple_island_flag":
			return ValidationUtil.same(owner.get("maple_island", true), false)
		"quest_region":
			var label: Variant = owner.get("area_label", owner.get("region", null))
			return label is String and label != "" and not _quest_regions.has(label)
	return false


func _scope_reason(scope: String, owner: Dictionary) -> String:
	match scope:
		"may_leave_dataset":
			return "destination outside the dataset"
		"maple_island_flag":
			return "maple_island: false"
		"quest_region":
			return "region %s" % str(owner.get("area_label", owner.get("region", "")))
	return scope


## Regions of the shipped quests plus the area label of every quest that starts on a shipped map. Quest references
## from another region are out of scope (e.g. a Henesys quest whose kill target also lives on Maple Island).
func _collect_quest_regions() -> Dictionary:
	var out := {}
	for id in db.ids("quests"):
		var region: Variant = db.quest(id).get("region", null)
		if region is String and region != "":
			out[region] = true
	for id in db.ids("maps"):
		var quests: Variant = db.map(id).get("quests", null)
		if not (quests is Dictionary):
			continue
		var starts: Variant = quests.get("starts_here", [])
		if not (starts is Array):
			continue
		for entry in starts:
			if entry is Dictionary and entry.get("area_label", null) is String:
				out[entry.area_label] = true
	return out


# --- portals ------------------------------------------------------------------------------------------------

func _check_portals() -> void:
	for map_id in db.ids("maps"):
		var portals: Variant = db.map(map_id).get("portals", [])
		if not (portals is Array):
			report.error("schema", "maps", map_id, "portals must be an array")
			continue
		var seen := {}
		for p in portals:
			if not (p is Dictionary):
				report.error("portal", "maps", map_id, "portal entry is not an object")
				continue
			report.count("portals_checked")
			var portal_name: Variant = p.get("name", null)
			if not (portal_name is String) or portal_name == "":
				report.error("portal", "maps", map_id, "a portal has no name")
				continue
			if seen.has(portal_name):
				report.error("portal", "maps", map_id, "portal name '%s' is used twice (to_portal lookups become ambiguous)" % portal_name)
			seen[portal_name] = true
			_check_portal(map_id, p)


func _check_portal(map_id: String, p: Dictionary) -> void:
	var label := "portal '%s'" % p.name
	var dest: Variant = p.get("to_map_id", null)
	if not (dest is String) or dest == "":
		report.error("portal", "maps", map_id, "%s has no to_map_id" % label)
		return
	report.count("references_checked")
	if not db.has("maps", dest):
		report.error("portal", "maps", map_id, "%s leads to map '%s', which does not exist" % [label, dest])
		return
	var dest_map: Dictionary = db.map(dest)
	var to_portal: Variant = p.get("to_portal", null)
	var derivation: Variant = p.get("to_portal_derivation", null)
	_check_derivation(map_id, label, dest, dest_map, to_portal, derivation)
	if to_portal == null:
		if ValidationUtil.same(derivation, "reverse_lookup"):
			report.error("portal", "maps", map_id, "%s says to_portal_derivation reverse_lookup but has no to_portal" % label)
		var spawns: Variant = dest_map.get("player_spawns", [])
		if not (spawns is Array) or spawns.is_empty():
			report.error("portal", "maps", map_id,
				"%s has no to_portal and destination %s has no player_spawns, so the arrival point is undefined" % [label, dest])
		return
	if not (to_portal is String) or to_portal == "":
		report.error("portal", "maps", map_id, "%s to_portal must be a portal name or null" % label)
		return
	var target_portal := find_portal(dest_map, to_portal)
	if target_portal.is_empty():
		report.error("portal", "maps", map_id,
			"%s arrives at portal '%s' in %s, which has no portal of that name" % [label, to_portal, dest])
		return
	if ValidationUtil.same(derivation, "reverse_lookup") and not ValidationUtil.same(target_portal.get("to_map_id", null), map_id):
		report.error("portal", "maps", map_id,
			"%s: to_portal '%s' in %s is derived by reverse lookup but leads to %s, not back to %s" % [
				label, to_portal, dest, str(target_portal.get("to_map_id", null)), map_id])


## docs/canonical/maps.md "Destination portals": to_portal is the UNIQUE portal of the destination that leads back to
## the source map ("reverse_lookup"); when the destination has no portal back, to_portal is null ("none"). A derivation
## the extractor would not have written means the canonical file was edited by hand or is stale.
func _check_derivation(map_id: String, label: String, dest: String, dest_map: Dictionary, to_portal: Variant,
		derivation: Variant) -> void:
	if derivation == null:
		return  # not derived: an explicit to_portal, checked by the caller
	if not (derivation is String) or not (derivation in PORTAL_DERIVATIONS):
		report.error("portal", "maps", map_id, "%s has to_portal_derivation %s; the extractor writes only %s" % [
			label, var_to_str(derivation), ", ".join(PackedStringArray(PORTAL_DERIVATIONS))])
		return
	var backs := portals_leading_to(dest_map, map_id)
	if derivation == "none":
		if to_portal != null:
			report.error("portal", "maps", map_id, "%s says to_portal_derivation none but names to_portal %s" % [
				label, var_to_str(to_portal)])
		if not backs.is_empty():
			report.error("portal", "maps", map_id,
				"%s says to_portal_derivation none, but %s has a portal back (%s), so the derivation is stale; %s" % [
					label, dest, ", ".join(backs), REDERIVE_HINT])
	elif backs.size() > 1:
		report.error("portal", "maps", map_id,
			"%s: the reverse lookup is ambiguous, %s has %d portals back to %s (%s) and maps.md requires exactly one" % [
				label, dest, backs.size(), map_id, ", ".join(backs)])


## The portal graph (MAP_ARCHITECTURE.md section 4.13, L0). Every reference can resolve while a retargeted portal still
## strands a map, so: every canonical map is reachable by portals from the new character's start map
## (new_character.json start_location.map_id), and every one-way link (no portal back) is listed in
## portal_adaptations.json one_way_allowlist.links. Each half is skipped when its adaptation file is absent.
func _check_portal_graph() -> void:
	var edges := {}  # map id -> {destination map id: true}
	for map_id in db.ids("maps"):
		var out := {}
		for p in ValidationUtil.as_array(db.map(map_id).get("portals", [])):
			if p is Dictionary and p.get("to_map_id", null) is String and db.has("maps", p.to_map_id):
				out[p.to_map_id] = true
		edges[map_id] = out
	var start := _start_map_id()
	if start != "":
		var reached := {start: true}
		var queue: Array[String] = [start]
		while not queue.is_empty():
			var at: String = queue.pop_front()
			for next in edges.get(at, {}):
				if not reached.has(next):
					reached[next] = true
					queue.append(str(next))
		for map_id in db.ids("maps"):
			if not reached.has(map_id):
				report.error("portal", "maps", map_id,
					"cannot be reached through portals from the start map %s (new_character.json start_location)" % start)
	var allow: Variant = _one_way_allowlist()
	if not (allow is Dictionary):
		return
	for a in edges:
		for b in edges[a]:
			if not edges.get(b, {}).has(a) and not allow.has("%s>%s" % [a, b]):
				report.error("portal", "maps", str(a),
					"the link %s -> %s is one-way (%s has no portal back), but portal_adaptations.json one_way_allowlist does not list it" % [a, b, b])


## The new character's start map from new_character.json, or "" when that file or map is missing (reported elsewhere).
func _start_map_id() -> String:
	var nc: Variant = db.miso_table("new_character")
	var loc: Variant = nc.get("start_location", null) if nc is Dictionary else null
	var map_id: Variant = loc.get("map_id", null) if loc is Dictionary else null
	return map_id if map_id is String and db.has("maps", map_id) else ""


## {"<from>><to>": true} from portal_adaptations.json one_way_allowlist.links, or null when the file is absent.
func _one_way_allowlist() -> Variant:
	var pa: Variant = db.miso_table("portal_adaptations")
	if not (pa is Dictionary):
		return null
	var out := {}
	var allow: Variant = pa.get("one_way_allowlist", null)
	for link in ValidationUtil.as_array(allow.get("links", []) if allow is Dictionary else []):
		if link is Dictionary:
			out["%s>%s" % [str(link.get("from", "")), str(link.get("to", ""))]] = true
	return out


## Names of the portals in `map_record` whose to_map_id is `to_map_id`.
static func portals_leading_to(map_record: Dictionary, to_map_id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for q in ValidationUtil.as_array(map_record.get("portals", [])):
		if q is Dictionary and ValidationUtil.same(q.get("to_map_id", null), to_map_id):
			out.append(str(q.get("name", "?")))
	return out


## The portal named `portal_name` in a canonical map record, or {} when there is none.
static func find_portal(map_record: Dictionary, portal_name: String) -> Dictionary:
	var portals: Variant = map_record.get("portals", [])
	if portals is Array:
		for q in portals:
			if q is Dictionary and ValidationUtil.same(q.get("name", null), portal_name):
				return q
	return {}


# --- drop tables --------------------------------------------------------------------------------------------

func _check_drop_tables() -> void:
	for id in db.ids("drops"):
		var table: Dictionary = db.drop_table(id)
		var owner: Variant = table.get("owner", null)
		if not (owner is Dictionary):
			report.error("drop_owner", "drops", id, "drop table has no owner {kind, id}")
			continue
		var kind: Variant = owner.get("kind", null)
		var owner_id: Variant = owner.get("id", null)
		if not (kind is String) or not DROP_OWNER_KINDS.has(kind):
			report.error("drop_owner", "drops", id, "owner.kind must be one of %s, got %s" % [
				str(DROP_OWNER_KINDS.keys()), var_to_str(kind)])
			continue
		if not (owner_id is String):
			report.error("drop_owner", "drops", id, "owner.id must be a string id")
			continue
		var owner_domain: String = DROP_OWNER_KINDS[kind]
		report.count("references_checked")
		if not db.has(owner_domain, owner_id):
			report.error("drop_owner", "drops", id, "drop table owner %s '%s' does not exist" % [kind, owner_id])
		if owner_id != id:
			report.error("drop_owner", "drops", id, "owner.id '%s' differs from the table id (drop tables are keyed by owner id)" % owner_id)
	for domain_name in ["monsters", "breakables"]:
		for id in db.ids(domain_name):
			_check_drop_table_ref(domain_name, id)


func _check_drop_table_ref(domain_name: String, id: String) -> void:
	var ref: Variant = db.get_entity(domain_name, id).get("drop_table", null)
	if ref == null:
		return
	report.count("references_checked")
	if not (ref is String) or not String(ref).begins_with("drops/") or String(ref).get_extension() != "json":
		report.error("drop_table", domain_name, id, "drop_table must look like \"drops/<owner id>.json\", got %s" % var_to_str(ref))
		return
	var table_id := String(ref).trim_prefix("drops/").get_basename()
	if not db.has("drops", table_id):
		report.error("drop_table", domain_name, id, "drop_table %s does not exist" % ref)
		return
	var owner: Variant = db.drop_table(table_id).get("owner", {})
	if owner is Dictionary and not ValidationUtil.same(owner.get("id", null), id):
		report.warning("consistency", domain_name, id, "drop_table %s belongs to owner '%s', not to this record" % [ref, str(owner.get("id", null))])


# --- two-sided consistency (warnings) -----------------------------------------------------------------------

func _check_consistency() -> void:
	# Map <-> NPC placement.
	for map_id in db.ids("maps"):
		for n in ValidationUtil.as_array(db.map(map_id).get("npcs", [])):
			if n is Dictionary and n.get("id", null) is String and db.has("npcs", n.id):
				if not (map_id in _npc_map_ids(n.id)):
					report.warning("consistency", "maps", map_id, "places NPC %s, whose locations do not list this map" % n.id)
	for npc_id in db.ids("npcs"):
		for map_id in _npc_map_ids(npc_id):
			if db.has("maps", map_id) and not _map_has_npc(map_id, npc_id):
				report.warning("consistency", "npcs", npc_id, "lists map %s, which does not place this NPC" % map_id)
	# Shop <-> NPC.
	for shop_id in db.ids("shops"):
		var npc_id: Variant = db.shop(shop_id).get("npc_id", null)
		if npc_id is String and db.has("npcs", npc_id):
			var npc_shop: Variant = db.npc(npc_id).get("shop", null)
			if not (npc_shop is Dictionary) or not ValidationUtil.same(npc_shop.get("shop_id", null), shop_id):
				report.warning("consistency", "shops", shop_id, "owner NPC %s does not name this shop in its shop block" % npc_id)
	# Quest NPC stands on the quest's start/end map.
	for quest_id in db.ids("quests"):
		var q: Dictionary = db.quest(quest_id)
		_check_quest_npc_map(quest_id, q.get("start_npc", null), q.get("start_maps", null), "start")
		_check_quest_npc_map(quest_id, q.get("end_npc", null), q.get("end_maps", null), "end")
	# Map species list <-> spawn points.
	for map_id in db.ids("maps"):
		var listed := {}
		for m in ValidationUtil.as_array(db.map(map_id).get("monsters", [])):
			if m is Dictionary and m.get("id", null) is String:
				listed[m.id] = true
		var spawned := {}
		for s in ValidationUtil.as_array(db.map(map_id).get("spawns", [])):
			if s is Dictionary and s.get("mob_id", null) is String:
				spawned[s.mob_id] = true
		for mob in spawned:
			if not listed.has(mob):
				report.warning("consistency", "maps", map_id, "has spawn points for monster %s but does not list it in monsters[]" % mob)
		for mob in listed:
			if not spawned.has(mob):
				report.warning("consistency", "maps", map_id, "lists monster %s but has no spawn point for it" % mob)


func _check_quest_npc_map(quest_id: String, npc_ref: Variant, maps: Variant, role: String) -> void:
	if not (npc_ref is Dictionary) or not (maps is Array) or maps.is_empty():
		return
	var npc_id: Variant = npc_ref.get("npc_id", null)
	if not (npc_id is String) or not db.has("npcs", npc_id):
		return
	var npc_maps := _npc_map_ids(npc_id)
	for m in maps:
		if m is Dictionary and m.get("map_id", null) is String and npc_maps.has(m.map_id):
			return
	report.warning("consistency", "quests", quest_id, "%s NPC %s does not stand on any of the quest's %s_maps" % [role, npc_id, role])


func _npc_map_ids(npc_id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for loc in ValidationUtil.as_array(db.npc(npc_id).get("locations", [])):
		if loc is Dictionary and loc.get("map_id", null) is String:
			out.append(loc.map_id)
	return out


func _map_has_npc(map_id: String, npc_id: String) -> bool:
	for n in ValidationUtil.as_array(db.map(map_id).get("npcs", [])):
		if n is Dictionary and ValidationUtil.same(n.get("id", null), npc_id):
			return true
	return false


# --- helpers ------------------------------------------------------------------------------------------------


func _note(severity: String, check: String, domain_label: String, id: String, message: String, dedupe: String = "") -> void:
	var key := "%s|%s|%s|%s|%s" % [severity, check, domain_label, id, message if dedupe == "" else dedupe]
	if _pending.has(key):
		_pending[key].count = int(_pending[key].count) + 1
		return
	_pending[key] = {"severity": severity, "check": check, "domain": domain_label, "id": id, "message": message, "count": 1}
	_pending_order.append(key)


func _skip(line: String) -> void:
	if _skipped.has(line):
		return
	_skipped[line] = true
	report.out_of_scope.append(line)

