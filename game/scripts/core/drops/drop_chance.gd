class_name DropChance
extends RefCounted
## Exact readers for the raw source values a canonical drop record keeps (contract C1): the GDScript twin of
## tools/sources/parse.mjs. DropChecks re-reads every record's raw_value with these and requires the stored numbers to
## follow from it, so a conversion slip (a /100 missed, N% read as 1/N, "0.0700" truncated to 0) cannot ship.
##
##   DropChance.parse_kuro_percent("0.0700% base | Qty 1")
##   # -> {ok: true, probability: 0.0007, numerator: 700, denominator: 1000000, qty_min: 1, qty_max: 1, quest: "",
##   #     meso: false, conversion: "0.0700 / 100"}
##   DropChance.parse_reactor_chance_value("Chance value 4 | Quest 1008")   # -> {ok, probability: 0.25, n: 4, quest: "1008"}
##   DropChance.parse_meso_amount("Mesos: 4-6")                              # -> {ok, state: "resolved", min: 4, max: 6}
##
## Every result has "ok"; when it is false, "error" says why and no number is given. Nothing is guessed, rounded or
## defaulted: a negative value, more than 100%, a non-decimal, an unknown "| ..." segment, a zero or reversed quantity
## all fail. A KuroDB percentage and a reactor value are different formats; each reader rejects the other.

## More digits than this in a percentage would not fit the exact integer numerator.
const MAX_DIGITS := 15

static var _re_percent := _compile("^(\\S+?)\\s*%\\s*base\\s*(?:\\|(.*))?$")
static var _re_decimal := _compile("^(\\d+)(?:\\.(\\d+))?$")
static var _re_qty := _compile("^Qty\\s+(\\d+)(?:\\s*[-~]\\s*(\\d+))?$")
static var _re_quest := _compile("^Quest\\s+(\\d+)$")
static var _re_id := _compile("^ID\\s+(\\d+)$")
static var _re_reactor := _compile("^Chance value\\s+(\\S+)\\s*(?:\\|(.*))?$")
static var _re_whole := _compile("^\\d+$")
static var _re_meso := _compile("^(?:Mesos\\s*:\\s*)?(\\d+)(?:\\s*-\\s*(\\d+))?(?:\\s+per kill\\s*\\|\\s*(\\d+)\\s+reports?)?$")


static func _compile(pattern: String) -> RegEx:
	var r := RegEx.new()
	r.compile(pattern)
	return r


static func _fail(message: String, raw: Variant) -> Dictionary:
	return {"ok": false, "error": "%s: %s" % [message, var_to_str(raw)]}


## KuroDB's monster / item drop value "<p>% base | Qty <n>[ | Quest <q>][ | ID <id>]" or "<p>% base | Meso drop".
## probability = p / 100 from the digits as written (integer numerator / power-of-ten denominator).
static func parse_kuro_percent(raw: Variant) -> Dictionary:
	if not (raw is String):
		return _fail("a KuroDB value must be a string", raw)
	var text := String(raw).strip_edges()
	if text.to_lower().begins_with("chance value"):
		return _fail("this is a reactor value (\"Chance value N\"), not a percentage", raw)
	var m := _re_percent.search(text)
	if m == null:
		return _fail("not a KuroDB \"<p>% base\" value", raw)
	var pct := m.get_string(1)
	var d := _re_decimal.search(pct)
	if d == null:
		return _fail("the percentage is not an unsigned decimal number", raw)
	var digits := d.get_string(1) + d.get_string(2)
	if digits.length() > MAX_DIGITS:
		return _fail("the percentage has more than %d digits" % MAX_DIGITS, raw)
	var numerator := digits.to_int()
	var denominator := 1
	for i in d.get_string(2).length() + 2:
		denominator *= 10
	if numerator > denominator:
		return _fail("percentage above 100%", raw)
	var out := {"ok": true, "format": "percent_base", "percent_text": pct, "numerator": numerator,
		"denominator": denominator, "probability": float(numerator) / float(denominator), "conversion": "%s / 100" % pct,
		"qty_min": 0, "qty_max": 0, "has_qty": false, "quest": "", "meso": false, "source_id": ""}
	if m.get_string(2) != "" or text.contains("|"):
		for seg in m.get_string(2).split("|"):
			var s := String(seg).strip_edges()
			if s == "":
				return _fail("empty \"|\" segment", raw)
			var q := _re_qty.search(s)
			var quest := _re_quest.search(s)
			var id := _re_id.search(s)
			if q != null:
				if out.has_qty:
					return _fail("two quantities", raw)
				var lo := q.get_string(1).to_int()
				var hi := q.get_string(2).to_int() if q.get_string(2) != "" else lo
				if lo < 1:
					return _fail("a quantity must be at least 1", raw)
				if hi < lo:
					return _fail("a quantity range has min > max", raw)
				out.qty_min = lo
				out.qty_max = hi
				out.has_qty = true
			elif quest != null:
				if out.quest != "":
					return _fail("two quest conditions", raw)
				out.quest = quest.get_string(1)
			elif s.to_lower() == "meso drop":
				out.meso = true
			elif id != null:
				out.source_id = id.get_string(1)
			else:
				return _fail("unknown segment \"%s\"" % s, raw)
	if out.meso and out.has_qty:
		return _fail("a meso row has no item quantity", raw)
	return out


## KuroDB's reactor (breakable) value "Chance value <N>[ | Quest <q>]", read as 1 / N: an interpretation by the
## project owner's decision D3-7, never a percentage.
static func parse_reactor_chance_value(raw: Variant) -> Dictionary:
	if not (raw is String):
		return _fail("a reactor value must be a string", raw)
	var text := String(raw).strip_edges()
	if text.contains("%"):
		return _fail("this is a percentage, not a reactor \"Chance value N\"", raw)
	var m := _re_reactor.search(text)
	if m == null:
		return _fail("not a KuroDB \"Chance value N\" value", raw)
	if _re_whole.search(m.get_string(1)) == null:
		return _fail("N must be a positive whole number", raw)
	if m.get_string(1).length() > MAX_DIGITS:
		return _fail("N is too large", raw)
	var n := m.get_string(1).to_int()
	if n < 1:
		return _fail("N must be at least 1 (1/0 is not a probability)", raw)
	var out := {"ok": true, "format": "reactor_chance_value", "n": n, "probability": 1.0 / float(n),
		"conversion": "1 / %d (interpretation, decision D3-7)" % n, "quest": ""}
	if text.contains("|"):
		for seg in m.get_string(2).split("|"):
			var q := _re_quest.search(String(seg).strip_edges())
			if q == null or out.quest != "":
				return _fail("unknown segment \"%s\"" % String(seg).strip_edges(), raw)
			out.quest = q.get_string(1)
	return out


## A meso amount: Hidden Street "Mesos: <a>" / "Mesos: <a>-<b>" / "Mesos: ?" or MeowDB's report line
## "Mesos: <a>[-<b>] per kill | <n> report(s)". {ok, state: "resolved", min, max} or {ok, state: "unresolved"} for "?".
static func parse_meso_amount(raw: Variant) -> Dictionary:
	if not (raw is String):
		return _fail("a meso amount must be a string", raw)
	var text := String(raw).strip_edges()
	var value := text
	if value.to_lower().begins_with("mesos"):
		value = value.substr(5).strip_edges().trim_prefix(":").strip_edges()
	if value == "?":
		return {"ok": true, "state": "unresolved", "min": null, "max": null}
	var m := _re_meso.search(value)
	if m == null:
		return _fail("not a meso amount (\"Mesos: a\", \"Mesos: a-b\" or \"Mesos: a per kill | n report\")", raw)
	if m.get_string(1).length() > MAX_DIGITS or m.get_string(2).length() > MAX_DIGITS:
		return _fail("the amount is too large", raw)
	var lo := m.get_string(1).to_int()
	var hi := m.get_string(2).to_int() if m.get_string(2) != "" else lo
	if hi < lo:
		return _fail("a meso range has min > max", raw)
	return {"ok": true, "state": "resolved", "min": lo, "max": hi}


## Parses `raw` by its declared C1 `format` ("percent_base" | "reactor_chance_value").
static func parse_by_format(format: Variant, raw: Variant) -> Dictionary:
	match str(format):
		"percent_base":
			return parse_kuro_percent(raw)
		"reactor_chance_value":
			return parse_reactor_chance_value(raw)
	return _fail("unknown chance format", format)
