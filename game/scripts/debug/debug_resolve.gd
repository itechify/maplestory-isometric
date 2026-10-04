class_name DebugResolve
extends RefCounted
## Turns what a developer types into canonical ids (pure: no scene tree).
##
## Maps accept, in order: the MeowDB id ("000000040"), the GMS v8 id ("40000", Iteration One's), the MeowDB id
## without leading zeros ("40"), the Blender slug ("SnailHuntingGround1_40000"), then a name fragment matched
## case- and punctuation-insensitively against the MeowDB name, the street, the Iteration One name and the slug
## ("snail hunting ground 1", "southperry"). An exact name match wins over a partial one; several equally good
## matches are an ambiguity ("Mushroom Town" is both 000000010 and 000000020) and list the candidates.
## Items, monsters and quests accept the MeowDB id or a name fragment the same way.
##
## Every resolver returns {"ok": bool, "id": String, "error": String, "candidates": PackedStringArray}.

const MAX_CANDIDATES := 12


## Resolves a map reference against the definitions (MeowDB ids, crosswalk v8 ids and slugs, names).
static func map_id(token: String, defs: MapDefinitions) -> Dictionary:
	var t := token.strip_edges()
	if t == "":
		return _fail("no map given")
	if defs.has_map(t):
		return _ok(t)
	if t.is_valid_int():
		var v8 := str(int(t))
		if defs.id_of_v8.has(v8):
			return _ok(String(defs.id_of_v8[v8]))
		var padded := t.lpad(9, "0")
		if defs.has_map(padded):
			return _ok(padded)
	for slug in defs.id_of_slug:
		if String(slug).to_lower() == t.to_lower():
			return _ok(String(defs.id_of_slug[slug]))
	var rows: Array[Dictionary] = []
	for id in defs.ids():
		var def := defs.get_def(id)
		var names: PackedStringArray = [def.map_name, "%s %s" % [def.street_name, def.map_name], def.slug,
			def.slug.get_slice("_", 0)]
		for r in defs.crosswalk_rows:
			if String(r.get("meowdb_id", "")) == id:
				names.append(String(r.get("iteration_one_name", "")))
		rows.append({"id": id, "label": "%s %s" % [id, def.map_name], "names": names})
	return _match(t, rows, "map")


## Resolves an item by MeowDB id or name.
static func item_id(token: String, db: ContentDB) -> Dictionary:
	return _domain_id(token, db, "items", "item")


static func monster_id(token: String, db: ContentDB) -> Dictionary:
	return _domain_id(token, db, "monsters", "monster")


static func quest_id(token: String, db: ContentDB) -> Dictionary:
	return _domain_id(token, db, "quests", "quest")


## A portal of `map` by id ("east00"); case-insensitive.
static func portal_id(token: String, def: MapDefinition) -> Dictionary:
	var t := token.strip_edges()
	if def == null:
		return _fail("no map")
	if def.portal(t) != null:
		return _ok(t)
	var ids: PackedStringArray = []
	for p in def.portals:
		if p.portal_id.to_lower() == t.to_lower():
			return _ok(p.portal_id)
		ids.append(p.portal_id)
	return {"ok": false, "id": "", "error": "%s has no portal '%s' (portals: %s)" % [def.map_id, t, ", ".join(ids)],
		"candidates": ids}


## Entities of a domain whose id or name contains `fragment` ("" = all), as "id name" lines, sorted by id.
static func search(domain: String, fragment: String, db: ContentDB, limit: int = 40) -> PackedStringArray:
	var out: PackedStringArray = []
	var f := _norm(fragment)
	for id in _sorted_ids(db, domain):
		var n := String(db.get_entity(domain, id).get("name", ""))
		if f == "" or _norm(id).contains(f) or _norm(n).contains(f):
			out.append("%s %s" % [id, n])
			if out.size() >= limit:
				break
	return out


## Lowercase letters and digits only ("Sera's Mirror" -> "serasmirror").
static func _norm(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


static func _domain_id(token: String, db: ContentDB, domain: String, what: String) -> Dictionary:
	var t := token.strip_edges()
	if t == "":
		return _fail("no %s given" % what)
	if db.has(domain, t):
		return _ok(t)
	var rows: Array[Dictionary] = []
	for id in _sorted_ids(db, domain):
		var n := String(db.get_entity(domain, id).get("name", ""))
		rows.append({"id": id, "label": "%s %s" % [id, n], "names": PackedStringArray([n])})
	return _match(t, rows, what)


## Exact normalized name first, then "starts with", then "contains"; a unique hit wins at the first level that has
## any hit, several hits there are ambiguous.
static func _match(token: String, rows: Array[Dictionary], what: String) -> Dictionary:
	var f := _norm(token)
	if f == "":
		return _fail("'%s' is not a %s id or name" % [token, what])
	for level in 3:
		var hits: PackedStringArray = []
		var labels: PackedStringArray = []
		for r in rows:
			for n in (r.names as PackedStringArray):
				var nn := _norm(n)
				if nn == "":
					continue
				var hit := nn == f if level == 0 else (nn.begins_with(f) if level == 1 else nn.contains(f))
				if hit:
					if not (String(r.id) in hits):
						hits.append(String(r.id))
						labels.append(String(r.label))
					break
		if hits.size() == 1:
			return _ok(hits[0])
		if hits.size() > 1:
			return {"ok": false, "id": "", "error": "'%s' matches %d %ss: %s" % [token, hits.size(), what,
				"; ".join(labels.slice(0, MAX_CANDIDATES))], "candidates": hits}
	return {"ok": false, "id": "", "error": "no %s matches '%s'" % [what, token], "candidates": PackedStringArray()}


static func _sorted_ids(db: ContentDB, domain: String) -> PackedStringArray:
	var ids := db.ids(domain)
	var arr: Array = Array(ids)
	arr.sort_custom(func(a: String, b: String) -> bool:
		if a.is_valid_int() and b.is_valid_int() and a.length() != b.length():
			return int(a) < int(b)
		return a < b)
	return PackedStringArray(arr)


static func _ok(id: String) -> Dictionary:
	return {"ok": true, "id": id, "error": "", "candidates": PackedStringArray([id])}


static func _fail(why: String) -> Dictionary:
	return {"ok": false, "id": "", "error": why, "candidates": PackedStringArray()}
