class_name DropSourceCaptures
extends RefCounted
## Reads the two dated captures a schema 3 drop record is built from (contract C1, decision D3-11), so the validator
## and the tests can hold every record to them: the GDScript twin of the parts of tools/sources/captures.mjs that
## tools/sources/drops_merge.mjs uses.
##
##   MeowDB's community list "Drops (MS Classic)" on a live monster or breakable page capture
##   (tools/meowdb/captures/monster_<id>.json | .txt, breakable_<id>.txt):
##     var list := DropSourceCaptures.community_list(root.path_join("tools/meowdb/captures/monster_2.txt"))
##     # -> {"ok": true, "entries": [{"group": "ETC", "name": "Bronze Ore", "subtype": "Ore & Mineral", "up": 16,
##     #     "down": 1, "raw": "Bronze Ore\nOre & Mineral\n▲\n16\n▼\n1"}, ...], "msea": ["Snail Shell", ...]}
##   Henesys.gg's rarity labels (tools/henesys/captures/item_rarity.json):
##     var rarity := DropSourceCaptures.rarity_capture(root.path_join("tools/henesys/captures/item_rarity.json"))
##     # -> {"ok": true, "url", "read_at", "items": {"Snail Shell": {"rarity": "Common", "row": "..."}, ...}}
##
## Every result has "ok"; when it is false, "error" says why. Nothing is guessed: a list group without its count, a
## member block that is not "name, subtype, ▲, n, ▼, n", or a rarity outside the four labels is an error.

const LIST_HEADING := "drops (ms classic)"
const MSEA_HEADING := "MSEA reference drops"
const GROUPS := ["ETC", "USE", "EQUIPMENT", "SETUP", "CASH"]
const INTRO := ["Community sourced", "Items players have personally seen", "Track a grind here"]
const MSEA_INTRO := ["Read-only", "Classic World appears"]
const RARITY_CAPTURE := "tools/henesys/captures/item_rarity.json"


## The rendered page text of a MeowDB capture: a monster_<id>.json ({head, drops} joined by a line break) or a .txt
## capture (the text after its "---" header line). "" when the file cannot be read.
static func page_text(path: String) -> String:
	var text := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
	if text == "":
		return ""
	if path.ends_with(".json"):
		var j: Variant = JSON.parse_string(text)
		if not (j is Dictionary):
			return ""
		return "%s\n%s" % [str(j.get("head", "")), str(j.get("drops", ""))]
	var lines := text.split("\n")
	var sep := lines.find("---")
	if sep < 0:
		return ""
	return "\n".join(lines.slice(sep + 1))


## The read time a MeowDB page capture records: "read_at" of a .json capture, the "READ_AT:" header line of a .txt
## capture. "" when the file cannot be read or records none.
static func read_at(path: String) -> String:
	var text := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
	if text == "":
		return ""
	if path.ends_with(".json"):
		var j: Variant = JSON.parse_string(text)
		return str(j.get("read_at", "")) if j is Dictionary and j.get("read_at", null) is String else ""
	for line in text.split("\n"):
		if line == "---":
			break
		if line.begins_with("READ_AT:"):
			return line.trim_prefix("READ_AT:").strip_edges()
	return ""


## Seconds since the Unix epoch of an ISO 8601 date-time with a zone ("2026-10-05T07:47:01.065Z",
## "2026-10-05T07:30+02:00"), for ordering captures by read time; NAN when the text is not one.
static func iso_seconds(text: String) -> float:
	var re := RegEx.new()
	re.compile("^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2})(?::(\\d{2})(\\.\\d+)?)?(Z|([+-])(\\d{2}):(\\d{2}))$")
	var m := re.search(text)
	if m == null:
		return NAN
	var t := float(Time.get_unix_time_from_datetime_dict({"year": m.get_string(1).to_int(), "month": m.get_string(2).to_int(),
		"day": m.get_string(3).to_int(), "hour": m.get_string(4).to_int(), "minute": m.get_string(5).to_int(),
		"second": m.get_string(6).to_int()}))
	if m.get_string(7) != "":
		t += m.get_string(7).to_float()
	if m.get_string(8) != "Z":
		var offset := m.get_string(10).to_int() * 3600 + m.get_string(11).to_int() * 60
		t -= offset if m.get_string(9) == "+" else -offset
	return t


## The trimmed, non-empty lines of a text.
static func _lines(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for l in text.split("\n"):
		var s := String(l).strip_edges()
		if s != "":
			out.append(s)
	return out


static func _starts_with_any(line: String, prefixes: Array) -> bool:
	for p in prefixes:
		if line.begins_with(str(p)):
			return true
	return false


## MeowDB's community list on a captured page (and the names on its MSEA reference list, which is never membership).
static func community_list(path: String) -> Dictionary:
	var text := page_text(path)
	if text == "":
		return {"ok": false, "error": "cannot read the capture %s" % path}
	return parse_community_list(text)


## The community list in a page text: {"ok", "entries": [{group, name, subtype, up, down, raw}], "msea": [names]}.
static func parse_community_list(text: String) -> Dictionary:
	var lines := _lines(text)
	var at := -1
	for i in lines.size():
		if lines[i].to_lower() == LIST_HEADING:
			at = i
			break
	if at < 0:
		return {"ok": false, "error": "no \"Drops (MS Classic)\" list in the page text"}
	var i := at + 1
	while i < lines.size() and _starts_with_any(lines[i], INTRO):
		i += 1
	var entries: Array = []
	while i + 1 < lines.size() and lines[i] in GROUPS and lines[i + 1].is_valid_int():
		var group := lines[i]
		var n := lines[i + 1].to_int()
		i += 2
		for k in n:
			if i + 5 >= lines.size():
				return {"ok": false, "error": "the %s group ends before its %d members" % [group, n]}
			var name := lines[i]
			var sub := lines[i + 1]
			if lines[i + 2] != "▲" or lines[i + 4] != "▼" or not lines[i + 3].is_valid_int() or not lines[i + 5].is_valid_int():
				return {"ok": false, "error": "member %s is not \"name, subtype, ▲, n, ▼, n\"" % var_to_str(name)}
			entries.append({"group": group, "name": name, "subtype": sub, "up": lines[i + 3].to_int(),
				"down": lines[i + 5].to_int(), "raw": "\n".join([name, sub, "▲", lines[i + 3], "▼", lines[i + 5]])})
			i += 6
	var msea := PackedStringArray()
	var m := lines.find(MSEA_HEADING)
	if m >= 0:
		var j := m + 1
		while j < lines.size() and _starts_with_any(lines[j], MSEA_INTRO):
			j += 1
		while j + 1 < lines.size() and lines[j] in GROUPS and lines[j + 1].is_valid_int():
			var n2 := lines[j + 1].to_int()
			j += 2
			for k in n2:
				if j < lines.size():
					msea.append(lines[j])
				j += 2
	return {"ok": true, "entries": entries, "msea": msea}


## Henesys.gg's rarity capture: {"ok", "url", "read_at", "items": {name: {"rarity", "row"}}}.
static func rarity_capture(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return {"ok": false, "error": "cannot read the capture %s" % path}
	var j: Variant = JSON.parse_string(text)
	if not (j is Dictionary) or not (j.get("items", null) is Dictionary):
		return {"ok": false, "error": "%s is not {url, read_at, items: {name: {row, rarity}}}" % path}
	var items := {}
	for name in j.items:
		var it: Variant = j.items[name]
		if not (it is Dictionary) or not (str(it.get("rarity", "")) in DropRates.RARITIES):
			return {"ok": false, "error": "%s: %s has no rarity among %s" % [path, str(name), str(DropRates.RARITIES)]}
		items[str(name)] = {"rarity": str(it.rarity), "row": str(it.get("row", ""))}
	return {"ok": true, "url": str(j.get("url", "")), "read_at": str(j.get("read_at", "")), "items": items}
